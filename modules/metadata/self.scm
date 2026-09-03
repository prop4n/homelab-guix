;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 prop4n <contact@legrandenzo.fr>

(define-module (metadata self)
  #:use-module (ice-9 match)
  #:export (metadata-module-name?))

(define (metadata-module-name? name)
  "Return true if NAME (a list of symbols) denotes a guix-metadata module.
Guix modules are excluded: they reach the reader through the 'guix' package
added as a G-Expression extension, not as imported source."
  (match name
    (('metadata _ ...) #t)
    (_ #f)))
