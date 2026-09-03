;;; SPDX-License-Identifier: MIT
;;; Copyright © 2026 prop4n

(define-module (bitlatch packages)
  #:use-module (guix packages)
  #:use-module (guix git-download)
  #:use-module (guix build-system go)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages golang)
  #:use-module (gnu packages version-control))

(define-public bitlatch
  (package
    (name "bitlatch")
    (version "0.4.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/prop4n/bitlatch.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "107rqmnd9yczgw1dnx603kj017c9n6cbz01qjxjch8x24mh0hrx4"))))
    (build-system go-build-system)
    (arguments
     (list
      #:go go-1.26
      #:import-path "github.com/prop4n/bitlatch/cmd/bitlatch"
      #:unpack-path "github.com/prop4n/bitlatch"
      #:install-source? #f
      ;; go-build-system already passes "-ldflags=-s -w"; a second -ldflags
      ;; overrides it, so keep "-s -w" here to preserve stripping while
      ;; injecting the version stamp read by `bitlatch -version`.
      #:build-flags
      #~(list (string-append "-ldflags=-s -w -X main.version=" #$version))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap-binary
            (lambda* (#:key inputs #:allow-other-keys)
              (wrap-program (string-append #$output "/bin/bitlatch")
                ;; bitlatch shells out to `git' by bare name; make sure the
                ;; binary finds it even when installed standalone.
                `("PATH" ":" prefix
                  (,(dirname (search-input-file inputs "/bin/git"))))
                ;; go-build-system compiles in GOPATH mode, so the module's
                ;; `go 1.26' directive is not honored and net/http's ServeMux
                ;; falls back to the pre-1.22 default where method patterns
                ;; like "GET /state" are treated as literal paths -- making
                ;; every observability route return 404.  Force the modern
                ;; behavior at runtime.
                `("GODEBUG" "," prefix ("httpmuxgo121=0"))))))))
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
