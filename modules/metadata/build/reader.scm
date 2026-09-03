;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 prop4n <contact@legrandenzo.fr>

(define-module (metadata build reader)
  #:use-module (metadata build nocloud)
  #:use-module (metadata build user-data)
  #:use-module (ice-9 format)
  #:export (run-reader))

(define (log-message format-string . arguments)
  (format (current-output-port) "~a guix-metadata: ~a~%"
          (strftime "%Y-%m-%dT%H:%M:%S%z" (localtime (current-time)))
          (apply format #f format-string arguments))
  (force-output (current-output-port)))

(define* (run-reader #:key output (file-name "user-data") (labels #f))
  "Write what this host was told to be into OUTPUT, and exit.  Leaving OUTPUT
untouched when there is nothing to read is deliberate: a machine that was
provisioned once and rebooted without a datasource must keep the answer it was
given, not lose it."
  (let ((payload (fetch-payload #:file-name file-name
                                #:log (lambda (message)
                                        (log-message "~a" message))
                                #:labels (or labels %default-labels))))
    (cond (payload
           (write-payload payload output)
           (log-message "wrote ~a" output)
           0)
          (else
           (log-message "leaving ~a as it is" output)
           0))))
