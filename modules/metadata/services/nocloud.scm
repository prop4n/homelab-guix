;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 prop4n <contact@legrandenzo.fr>

(define-module (metadata services nocloud)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages package-management)
  #:use-module (gnu services)
  #:use-module (gnu services configuration)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (ice-9 match)
  #:use-module (metadata self)
  #:use-module (srfi srfi-1)
  #:export (nocloud-configuration
            nocloud-configuration?
            nocloud-configuration-output
            nocloud-configuration-file-name
            nocloud-configuration-labels
            nocloud-configuration-requirement
            nocloud-configuration-provision

            nocloud-reader-program
            nocloud-service-type))

(define (list-of-strings? value)
  (and (list? value) (every string? value)))

(define (list-of-symbols? value)
  (and (list? value) (every symbol? value)))

(define-configuration/no-serialization nocloud-configuration
  (output
   (string "/etc/guix-gitops/runtime.scm")
   "The file the payload found in the host's user data is written to.  The
default points at where @code{guix-gitops} looks for its runtime
configuration, which is the reason this exists, but nothing here is tied to
it: whatever reads that file is none of this service's business.")
  (file-name
   (string "user-data")
   "The name of the file to read on the datasource.")
  (labels
   (list-of-strings '("cidata" "CIDATA"))
   "The filesystem labels a datasource may carry.  Matching is case
insensitive.")
  (requirement
   (list-of-symbols '(udev file-systems))
   "Shepherd services that must be running first.  The default waits for
@code{udev}, without which the datasource has no name to be found under.")
  (provision
   (list-of-symbols '(nocloud))
   "The names this service provides.  Services that need the payload should
require one of them."))

(define (input-packages inputs)
  (filter-map (match-lambda
                ((? package? package) package)
                ((_ (? package? package) . _) package)
                (_ #f))
              inputs))

(define (guix-extensions)
  (cons guix (input-packages (package-transitive-propagated-inputs guix))))

(define (guix-guile)
  "Return the Guile GUIX is built with, so that the reader's bytecode matches
the '.go' files it loads from it."
  (or (find (lambda (package) (string=? "guile" (package-name package)))
            (append (input-packages (package-native-inputs guix))
                    (input-packages (package-inputs guix))))
      guile-3.0-latest))

(define (nocloud-reader-program config)
  (match-record config <nocloud-configuration> (output file-name labels)
    (let ((entry-point
           (with-extensions (guix-extensions)
             (with-imported-modules (source-module-closure
                                     '((metadata build reader))
                                     #:select? metadata-module-name?)
               #~(begin
                   (use-modules (metadata build reader))
                   (exit (run-reader #:output #$output
                                     #:file-name #$file-name
                                     #:labels '#$labels)))))))
      (program-file "nocloud-reader" entry-point #:guile (guix-guile)))))

(define (nocloud-shepherd-services config)
  (match-record config <nocloud-configuration> (output requirement provision)
    (list (shepherd-service
           (documentation "Read this host's user data into a local file.")
           (provision provision)
           (requirement requirement)
           (one-shot? #t)
           (start #~(make-forkexec-constructor
                     (list #$(nocloud-reader-program config))))
           (stop #~(make-kill-destructor))))))

(define (nocloud-activation config)
  (match-record config <nocloud-configuration> (output)
    #~(begin
        (mkdir-p (dirname #$output))
        (chmod (dirname #$output) #o700))))

(define nocloud-service-type
  (service-type
   (name 'nocloud)
   (extensions
    (list (service-extension shepherd-root-service-type
                             nocloud-shepherd-services)
          (service-extension activation-service-type
                             nocloud-activation)))
   (default-value (nocloud-configuration))
   (description "Read the NoCloud datasource this host was booted with -- the
disk labelled @code{cidata} that Proxmox, libvirt and QEMU attach to a virtual
machine -- and write the payload it carries to a local file.")))
