;;; SPDX-License-Identifier: MIT
;;; Copyright © 2026 prop4n

(define-module (bitlatch services)
  #:use-module (bitlatch packages)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu packages version-control)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (ice-9 match)
  #:export (bitlatch-configuration
            bitlatch-configuration?
            bitlatch-configuration-package
            bitlatch-configuration-git-url
            bitlatch-configuration-system-file
            bitlatch-configuration-runtime-file
            bitlatch-configuration-reconfigure-mode
            bitlatch-configuration-load-path
            bitlatch-configuration-log-file
            bitlatch-service-type))

;;; Commentary:
;;;
;;; A Guix system service for the BitLatch GitOps agent.
;;;
;;; The daemon reads an env-style file (/etc/bitlatch/config.env).  That file
;;; is rendered at boot by the one-shot `bitlatch-config` service, which merges
;;; the static defaults carried by <bitlatch-configuration> with per-instance
;;; overrides.  When `runtime-file' is set (the default,
;;; /etc/guix-gitops/runtime.scm written by guix-metadata's nocloud service),
;;; those overrides come from a Scheme association list injected through the
;;; host's userData -- letting one generic image be specialised per instance.
;;;
;;; Code:

(define-record-type* <bitlatch-configuration>
  bitlatch-configuration make-bitlatch-configuration
  bitlatch-configuration?
  (package               bitlatch-configuration-package
                         (default bitlatch))
  ;; Required at runtime; may stay #f here and arrive via userData.
  (git-url               bitlatch-configuration-git-url
                         (default #f))
  (git-branch            bitlatch-configuration-git-branch
                         (default "main"))
  (channels-file         bitlatch-configuration-channels-file
                         (default "channels.scm"))
  (system-file           bitlatch-configuration-system-file
                         (default #f))
  (poll-interval         bitlatch-configuration-poll-interval
                         (default "60s"))
  (work-dir              bitlatch-configuration-work-dir
                         (default "/var/lib/bitlatch/repo"))
  (state-file            bitlatch-configuration-state-file
                         (default "/var/lib/bitlatch/state.json"))
  (listen-addr           bitlatch-configuration-listen-addr
                         (default ":8080"))
  (retry-max-attempts    bitlatch-configuration-retry-max-attempts
                         (default 5))
  (retry-initial-backoff bitlatch-configuration-retry-initial-backoff
                         (default "1s"))
  (retry-max-backoff     bitlatch-configuration-retry-max-backoff
                         (default "30s"))
  (log-level             bitlatch-configuration-log-level
                         (default "info"))
  (reconfigure-mode      bitlatch-configuration-reconfigure-mode
                         (default "time-machine"))
  (load-path             bitlatch-configuration-load-path
                         (default #f))
  (allow-downgrades?     bitlatch-configuration-allow-downgrades?
                         (default #f))
  (reconfigure-timeout   bitlatch-configuration-reconfigure-timeout
                         (default #f))
  ;; Shepherd log file for the daemon (its stdout/stderr, including streamed
  ;; guix output). #f uses shepherd's default; "/dev/console" shows it on the
  ;; system console.
  (log-file              bitlatch-configuration-log-file
                         (default #f))
  ;; Where per-instance overrides are read from; #f disables runtime merging
  ;; (purely declarative mode, no dependency on the nocloud service).
  (runtime-file          bitlatch-configuration-runtime-file
                         (default "/etc/guix-gitops/runtime.scm")))

(define %config-file "/etc/bitlatch/config.env")

(define (bitlatch-static-pairs config)
  "Return the list of (ENV-NAME RUNTIME-SYMBOL VALUE) triples describing every
config.env key, its matching userData alist key, and the static default from
CONFIG.  VALUE may be a string, an integer, or #f (key omitted)."
  (match-record config <bitlatch-configuration>
    (git-url git-branch channels-file system-file poll-interval
     work-dir state-file listen-addr retry-max-attempts retry-initial-backoff
     retry-max-backoff reconfigure-mode load-path allow-downgrades?
     reconfigure-timeout)
    ;; Each entry: (ENV-NAME (RUNTIME-KEYS...) DEFAULT REQUIRED?).  The first
    ;; runtime key that appears in the userData alist wins; extra keys are
    ;; aliases.  REQUIRED? fields must resolve to a non-#f value before the
    ;; daemon can start, so the bridge waits for them (see the program below).
    `(("BITLATCH_GIT_URL"              (git-url url)             ,git-url               #t)
      ("BITLATCH_GIT_BRANCH"           (git-branch branch)       ,git-branch            #f)
      ("BITLATCH_CHANNELS_FILE"        (channels-file)           ,channels-file         #f)
      ("BITLATCH_SYSTEM_FILE"          (system-file)             ,system-file           #t)
      ("BITLATCH_POLL_INTERVAL"        (poll-interval)           ,poll-interval         #f)
      ("BITLATCH_WORK_DIR"             (work-dir)                ,work-dir              #f)
      ("BITLATCH_STATE_FILE"           (state-file)              ,state-file            #f)
      ("BITLATCH_LISTEN_ADDR"          (listen-addr)             ,listen-addr           #f)
      ("BITLATCH_RETRY_MAX_ATTEMPTS"   (retry-max-attempts)      ,retry-max-attempts    #f)
      ("BITLATCH_RETRY_INITIAL_BACKOFF" (retry-initial-backoff)  ,retry-initial-backoff #f)
      ("BITLATCH_RETRY_MAX_BACKOFF"    (retry-max-backoff)       ,retry-max-backoff     #f)
      ("BITLATCH_RECONFIGURE_MODE"     (reconfigure-mode)        ,reconfigure-mode      #f)
      ("BITLATCH_LOAD_PATH"            (load-path)               ,load-path             #f)
      ("BITLATCH_ALLOW_DOWNGRADES"     (allow-downgrades)        ,(if allow-downgrades? "true" "false") #f)
      ("BITLATCH_RECONFIGURE_TIMEOUT"  (reconfigure-timeout)     ,reconfigure-timeout   #f))))

(define (bitlatch-run-program config)
  "Return the daemon's start program: it renders /etc/bitlatch/config.env from
the static defaults in CONFIG (overridden by the userData alist in
`runtime-file' when set), then execs the bitlatch binary.  Rendering and exec
happen in the SAME process so there is no cross-service race: shepherd marks a
forkexec service \"started\" as soon as it forks, not when it finishes, so a
separate one-shot config service could not reliably run before the daemon."
  (let ((static-pairs (bitlatch-static-pairs config))
        (runtime-file (bitlatch-configuration-runtime-file config))
        (package (bitlatch-configuration-package config))
        (log-level (bitlatch-configuration-log-level config)))
    (program-file
     "bitlatch-run"
     #~(begin
         (use-modules (ice-9 match)
                      (srfi srfi-1))

         (define out #$%config-file)
         ;; Each entry: (ENV-NAME (RUNTIME-KEYS...) DEFAULT REQUIRED?).
         (define static (list #$@(map (match-lambda
                                        ((env keys value required?)
                                         #~(list #$env '#$keys #$value #$required?)))
                                      static-pairs)))
         (define runtime-file #$runtime-file)

         ;; How long to wait for the userData reader (nocloud) to publish the
         ;; runtime file with the required fields.  nocloud is marked "started"
         ;; by shepherd as soon as it forks -- before it has written the file --
         ;; so a plain requirement is not enough; we poll here.
         (define wait-deadline 60)          ; seconds
         (define wait-step 500000)          ; microseconds (0.5s)

         (define (read-overrides file)
           (if (and file (file-exists? file))
               (catch #t
                 (lambda ()
                   (call-with-input-file file
                     (lambda (port)
                       (let ((data (read port)))
                         (if (and (list? data) (pair? data) (every pair? data))
                             data
                             '())))))
                 (lambda _ '()))
               '()))

         (define (lookup keys default overrides)
           ;; First runtime key present wins; otherwise the static default.
           (let loop ((ks keys))
             (match ks
               (() default)
               ((k . rest)
                (let ((cell (assq k overrides)))
                  (if cell (cdr cell) (loop rest)))))))

         (define (missing-required overrides)
           (filter-map (match-lambda
                         ((env keys default required?)
                          (and required?
                               (not (lookup keys default overrides))
                               env)))
                       static))

         ;; Wait until every required field resolves (from userData or the
         ;; record default), or the deadline passes -- then proceed with what
         ;; we have (BitLatch will report ERROR if a required field is absent).
         (define overrides
           (let loop ((waited 0) (ov (read-overrides runtime-file)))
             (cond
              ((not runtime-file) ov)
              ((null? (missing-required ov)) ov)
              ((>= waited (* wait-deadline 1000000))
               (format (current-error-port)
                       "bitlatch-configure: timed out waiting for ~a; missing ~a~%"
                       runtime-file (missing-required ov))
               ov)
              (else
               (usleep wait-step)
               (loop (+ waited wait-step) (read-overrides runtime-file))))))

         (define (value->string v)
           (cond ((string? v) v)
                 ((number? v) (number->string v))
                 ((symbol? v) (symbol->string v))
                 (else #f)))

         (define known (append-map cadr static))
         (for-each (match-lambda
                     ((k . _)
                      (unless (memq k known)
                        (format (current-error-port)
                                "bitlatch-configure: ignoring unknown key ~a~%" k))))
                   overrides)

         ;; The activation step created /etc/bitlatch, but guard anyway.
         (let ((dir (dirname out)))
           (unless (file-exists? dir) (mkdir dir)))

         (call-with-output-file out
           (lambda (port)
             (for-each
              (match-lambda
                ((env keys default required?)
                 (let ((v (value->string (lookup keys default overrides))))
                   (when v (format port "~a=~a~%" env v)))))
              static)))
         (chmod out #o600)

         ;; Replace this process with the agent.  The PATH/HOME set by the
         ;; shepherd forkexec constructor are inherited across execl.
         (let ((bin #$(file-append package "/bin/bitlatch")))
           (execl bin bin "-config" out "-log-level" #$log-level))))))

(define (bitlatch-shepherd-services config)
  (let ((runtime-file (bitlatch-configuration-runtime-file config))
        (log-file (bitlatch-configuration-log-file config)))
    (list
     ;; The long-running agent.  Its start program renders config.env (waiting
     ;; for the userData reader when needed) and then execs the binary, so no
     ;; separate config service can race ahead of it.  Runs as root: `guix
     ;; system reconfigure' activates a new system generation and requires it.
     (shepherd-service
      (documentation "BitLatch GitOps agent.")
      (provision '(bitlatch))
      ;; nocloud (when used) publishes the runtime file; the start program
      ;; still polls for it, since shepherd marks nocloud started at fork.
      (requirement (if runtime-file '(nocloud networking) '(networking)))
      (start #~(make-forkexec-constructor
                (list #$(bitlatch-run-program config))
                #:log-file #$log-file
                #:environment-variables
                ;; git from the store, and the LIVE system guix (never a
                ;; store-pinned one) so `guix time-machine' works.
                (list (string-append
                       "PATH=" #$(file-append git-minimal "/bin")
                       ":/run/current-system/profile/bin")
                      "HOME=/var/lib/bitlatch"
                      ;; CA bundle so git can verify HTTPS remotes (GitHub).
                      "SSL_CERT_DIR=/etc/ssl/certs"
                      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                      "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt")))
      (stop #~(make-kill-destructor))))))

(define (bitlatch-activation config)
  (let ((work-dir (bitlatch-configuration-work-dir config)))
    #~(begin
        (use-modules (guix build utils))
        (mkdir-p #$work-dir)
        (mkdir-p "/var/lib/bitlatch")
        (mkdir-p "/etc/bitlatch")
        (chmod "/etc/bitlatch" #o700))))

(define bitlatch-service-type
  (service-type
   (name 'bitlatch)
   (extensions
    (list (service-extension shepherd-root-service-type
                             bitlatch-shepherd-services)
          (service-extension activation-service-type
                             bitlatch-activation)
          (service-extension profile-service-type
                             (lambda (config)
                               (list (bitlatch-configuration-package config))))))
   (description "Run the BitLatch GitOps agent: watch a Git repository and
atomically reconfigure this Guix system from the configuration it declares.")))
