;;; SPDX-License-Identifier: MIT
;;; Copyright © 2026 prop4n

(define-module (bitlatch packages)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system copy)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages version-control))

;; BitLatch is a statically linked (CGO_ENABLED=0) Go binary. We install the
;; prebuilt release tarball from GitHub instead of compiling from source with
;; go-build-system: the latter drags in gcc + go-std and rebuilds them on any
;; machine that lacks a substitute for them, turning the first reconfigure into
;; a 20-minute compile. Downloading a 2.7 MB tarball is a few seconds instead.
(define-public bitlatch
  (package
    (name "bitlatch")
    (version "0.4.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/prop4n/bitlatch/releases/download/v"
             version "/bitlatch_" version "_linux_amd64.tar.gz"))
       (sha256
        (base32 "1b8w36b7fv1m2clac7ac7jf2p1am3kfpakxw5crzcrblwhhq4prh"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan #~'(("bitlatch" "bin/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap-binary
            (lambda* (#:key inputs #:allow-other-keys)
              ;; bitlatch shells out to `git' by bare name; make sure the
              ;; binary finds it even when installed standalone.
              (wrap-program (string-append #$output "/bin/bitlatch")
                `("PATH" ":" prefix
                  (,(dirname (search-input-file inputs "/bin/git"))))))))))
    (inputs (list bash-minimal git-minimal))
    (home-page "https://github.com/prop4n/bitlatch")
    (synopsis "Lightweight GitOps execution agent for Guix System")
    (description
     "BitLatch watches a remote Git repository, atomically applies the system
configuration it declares through Guix (@code{guix time-machine} +
@code{system reconfigure}), and exposes the machine's live state over an
embedded HTTP observability server.")
    (license license:expat)))

bitlatch
