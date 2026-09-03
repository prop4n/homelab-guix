;;; SPDX-License-Identifier: MIT
;;;
;;; web02 — a second machine, here just a plain box with a couple of tools.
;;; Point a VM at it via userData: ((system-file . "systems/web02.scm"))

(use-modules (systems base)
             (gnu)
             (gnu packages admin)
             (gnu packages version-control))

(homelab-operating-system
 #:host-name "web02"
 #:packages (list htop git))
