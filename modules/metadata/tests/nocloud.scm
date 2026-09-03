;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 prop4n <contact@legrandenzo.fr>

(define-module (metadata tests nocloud)
  #:use-module (gnu packages cdrom)
  #:use-module (gnu services)
  #:use-module (gnu system vm)
  #:use-module (gnu tests)
  #:use-module (guix gexp)
  #:use-module (metadata services nocloud)
  #:export (%test-nocloud))

(define %payload
  '((system-file . "systems/web01.scm")
    (branch . "production")))

(define %seed-image
  ;; The very disk Proxmox attaches to a virtual machine: an ISO9660
  ;; filesystem labelled CIDATA, holding user-data and meta-data.  Built the
  ;; same way here as by hand, so that what passes here passes there.
  (computed-file
   "cidata.iso"
   (with-imported-modules '((guix build utils))
     #~(begin
         (use-modules (guix build utils))
         (mkdir "seed")
         (call-with-output-file "seed/meta-data"
           (lambda (port)
             (display "instance-id: web01\nlocal-hostname: web01\n" port)))
         (call-with-output-file "seed/user-data"
           (lambda (port)
             ;; Providers expect this first line, and it is not Scheme.
             (display "#cloud-config\n# guix-metadata\n" port)
             (write '#$%payload port)
             (newline port)))
         (invoke #$(file-append xorriso "/bin/xorriso")
                 "-as" "mkisofs"
                 "-output" #$output
                 "-volid" "CIDATA"
                 "-joliet" "-rock"
                 "seed")))))

(define %nocloud-os
  (simple-operating-system (service nocloud-service-type)))

(define (run-nocloud-test)
  (define os
    (marionette-operating-system
     %nocloud-os
     #:imported-modules '((gnu services herd))))

  (define test
    (with-imported-modules '((gnu build marionette))
      #~(begin
          (use-modules (gnu build marionette)
                       (srfi srfi-64))

          ;; The generated script ends in 'exec qemu … "$@"', so the seed disk
          ;; can be attached by appending to the command.
          (define marionette
            (make-marionette
             (list #$(virtual-machine os)
                   "-drive"
                   (string-append "file=" #$%seed-image
                                  ",media=cdrom,readonly=on"))))

          (test-runner-current (system-test-runner #$output))
          (test-begin "nocloud")

          (test-assert "the datasource shows up under its label"
            (marionette-eval
             '(begin
                (use-modules (ice-9 ftw) (srfi srfi-1))
                (let loop ((attempts 30))
                  (define entries
                    (or (scandir "/dev/disk/by-label") '()))
                  (cond ((any (lambda (name)
                                (string-ci=? name "cidata"))
                              entries)
                         #t)
                        ((zero? attempts) #f)
                        (else (sleep 1) (loop (- attempts 1))))))
             marionette))

          (test-assert "the payload is written out"
            (wait-for-file "/etc/guix-gitops/runtime.scm" marionette))

          (test-equal "the payload is what the datasource carried"
            '#$%payload
            (marionette-eval
             '(call-with-input-file "/etc/guix-gitops/runtime.scm" read)
             marionette))

          ;; Mounting is the one thing unit tests cannot reach: it needs a
          ;; block device and root.  Having read the payload proves it worked,
          ;; and this proves it was cleaned up.
          (test-assert "the datasource is left unmounted"
            (marionette-eval
             '(begin
                (use-modules (guix build syscalls) (srfi srfi-1))
                (not (any (lambda (mount)
                            (string-prefix? "/tmp/guix-metadata"
                                            (mount-point mount)))
                          (mounts))))
             marionette))

          (test-end))))

  (gexp->derivation "nocloud-test" test))

(define %test-nocloud
  (system-test
   (name "nocloud")
   (description "Boot a machine with a NoCloud datasource attached and check
that the payload it carries is read and written out.")
   (value (run-nocloud-test))))
