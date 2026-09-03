;;; SPDX-License-Identifier: MIT
;;;
;;; What every machine in this homelab has in common.  A machine file loads
;;; this, then adds what makes it itself.
;;;
;;; The agent is BitLatch, running in DIRECT mode: it reconfigures with the Guix
;;; baked into the image (no time-machine, no guix.git clone) using the vendored
;;; modules under ./modules on the load path.  A machine reconfigures in seconds
;;; once its bytecode cache is warm; the trade-off is that Guix itself is updated
;;; by rebuilding the image, not by a commit.
;;;
;;; Vendored (see ./modules), copy in fresh trees to update:
;;;   modules/bitlatch  from github.com/prop4n/bitlatch  (guix/bitlatch)
;;;   modules/metadata  from github.com/prop4n/guix-metadata (modules/metadata)

(define-module (systems base)
  #:use-module (gnu)
  #:use-module (guix channels)
  #:use-module (guix store)
  #:use-module (bitlatch services)
  #:use-module (metadata services nocloud)
  #:export (%homelab-channels
            %homelab-repo
            %homelab-services
            homelab-operating-system))

(use-service-modules base networking ssh)

;; The Git repository every machine watches. Point this at THIS repo's remote.
(define %homelab-repo "https://github.com/prop4n/homelab-guix.git")

;; Public keys allowed to log in as root. Replace with your own.
(define %root-authorized-key
  (plain-file "root.pub"
              "ssh-ed25519 AAAAREPLACE_ME_WITH_YOUR_PUBLIC_KEY comment"))

;; The nonguix substitute server's signing key, so machines download its
;; prebuilt binaries instead of rebuilding from source.
(define %nonguix-key
  (plain-file "nonguix.pub"
              "(public-key
 (ecc
  (curve Ed25519)
  (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))"))

;; Channels installed as /etc/guix/channels.scm (for the machine's own
;; `guix pull`) and used to build the image. Pin them so the image's Guix and
;; the machine's Guix match. Bump here, then rebuild the image.
(define %homelab-channels
  (list (channel
         (name 'guix)
         (url "https://git.guix.gnu.org/guix.git")
         (branch "master")
         (commit "e5186f7bd43e5a12228ffd9b058fd346a4a94ba1")
         (introduction
          (make-channel-introduction
           "9edb3f66fd807b096b48283debdcddccfea34bad"
           (openpgp-fingerprint
            "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
        (channel
         (name 'nonguix)
         (url "https://gitlab.com/nonguix/nonguix")
         (branch "master")
         (commit "bdc27101e06737197834cb65e31256cd4d44d40a")
         (introduction
          (make-channel-introduction
           "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
           (openpgp-fingerprint
            "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))))

(define* (%homelab-services #:key (extra '())
                            (networking (list (service dhcpcd-service-type))))
  "The services every machine runs: BitLatch (the agent), nocloud (reads which
machine it is from userData), SSH, networking, and a guix daemon configured for
nonguix substitutes. EXTRA and NETWORKING are appended per machine."
  (cons* (service agetty-service-type
                  (agetty-configuration
                   (extra-options '("-L"))
                   (baud-rate "115200")
                   (term "vt100")
                   (tty "ttyS0")))

         (service openssh-service-type
                  (openssh-configuration
                   (permit-root-login 'prohibit-password)
                   (password-authentication? #f)
                   (authorized-keys `(("root" ,%root-authorized-key)))))

         ;; Reads this host's userData (NoCloud cidata disk) at boot into
         ;; /etc/guix-gitops/runtime.scm, telling BitLatch which system to apply.
         (service nocloud-service-type)

         ;; The agent. git-url/branch are fleet-wide (baked here); the per-machine
         ;; system-file arrives via userData. Direct mode + vendored modules.
         (service bitlatch-service-type
                  (bitlatch-configuration
                   (git-url %homelab-repo)
                   (git-branch "main")
                   (poll-interval "60s")
                   (reconfigure-mode "direct")
                   (load-path "modules")
                   (allow-downgrades? #t)
                   (reconfigure-timeout "20m")))

         (append
          extra
          networking
          (modify-services %base-services
            (guix-service-type
             config => (guix-configuration
                        (inherit config)
                        (channels %homelab-channels)
                        (substitute-urls
                         (cons "https://substitutes.nonguix.org"
                               %default-substitute-urls))
                        (authorized-keys
                         (cons %nonguix-key
                               %default-authorized-guix-keys))))))))

(define* (homelab-operating-system #:key host-name
                                   (extra-services '())
                                   (packages '())
                                   (networking (list (service dhcpcd-service-type))))
  "An operating-system for a Proxmox VM in this homelab. The root disk comes from
the generic image (label \"Guix_image\"), the bootloader targets /dev/vda, and
the serial console is on ttyS0 so `qm terminal` works."
  (operating-system
    (host-name host-name)
    (timezone "Europe/Paris")
    (locale "fr_FR.utf8")

    (bootloader (bootloader-configuration
                 (bootloader grub-bootloader)
                 (targets '("/dev/vda"))
                 (terminal-outputs '(console))))
    ;; net.ifnames=0 forces the NIC to be "eth0" (instead of ens18/enp0s18),
    ;; so static-networking in a machine file can rely on a stable device name.
    (kernel-arguments '("console=ttyS0,115200" "net.ifnames=0"))

    (file-systems (cons (file-system
                          (mount-point "/")
                          (device (file-system-label "Guix_image"))
                          (type "ext4"))
                        %base-file-systems))

    (users %base-user-accounts)
    (packages (append packages %base-packages))
    (services (%homelab-services #:extra extra-services
                                 #:networking networking))))
