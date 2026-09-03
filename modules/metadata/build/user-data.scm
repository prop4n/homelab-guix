;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 prop4n <contact@legrandenzo.fr>

(define-module (metadata build user-data)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 match)
  #:export (extract-payload
            read-payload
            write-payload))

;; Cloud providers hand user data over as an opaque blob, and most of them
;; expect it to start with a '#cloud-config' line.  Rather than parse YAML to
;; get at a value, the payload is written as a Scheme datum and everything
;; before it is skipped.  That keeps the file valid enough for whatever else
;; may glance at it, and reduces reading it here to a single 'read'.

(define (payload-line? line)
  (string-prefix? "(" (string-trim line)))

(define (extract-payload port)
  "Read the first Scheme datum appearing at the start of a line in PORT,
skipping any preamble.  Return #f when there is none, or when what is there is
not an association list: everything here comes from outside the store."
  (let loop ()
    (match (read-line port)
      ((? eof-object?) #f)
      ((? payload-line? line)
       (let ((datum (catch #t
                      (lambda ()
                        (call-with-input-string
                         (string-append line "\n" (read-string port))
                         read))
                      (const #f))))
         (and (list? datum)
              (not (null? datum))
              (every-pair? datum)
              datum)))
      (_ (loop)))))

(define (every-pair? datum)
  (let loop ((entries datum))
    (match entries
      (() #t)
      ((((? symbol?) . _) . rest) (loop rest))
      (_ #f))))

(define (read-payload file)
  "Read the payload held in FILE, or #f."
  (catch #t
    (lambda () (call-with-input-file file extract-payload))
    (const #f)))

(define (write-payload payload file)
  "Atomically write PAYLOAD to FILE."
  (let ((temporary (string-append file ".tmp")))
    (call-with-output-file temporary
      (lambda (port)
        (display ";; Written by guix-metadata from this host's user data.\n"
                 port)
        (write payload port)
        (newline port)))
    (rename-file temporary file)
    payload))
