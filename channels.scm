;; Pinned channels for this homelab. Installed on each machine as
;; /etc/guix/channels.scm (via systems/base.scm) so `guix pull` sees the same
;; Guix the image was built with. Keep the commits here and in
;; systems/base.scm's %homelab-channels in sync.
;;
;; NB: loaded by `guix pull`/`guix time-machine -C` in an environment where
;; `channel', `make-channel-introduction' and `openpgp-fingerprint' are already
;; bound -- do NOT add (use-modules ...) here.

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
          "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5")))))
