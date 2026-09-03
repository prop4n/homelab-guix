;;; SPDX-License-Identifier: MIT
;;;
;;; web01 — an nginx web server. Point a VM at this file via its userData:
;;;   #cloud-config
;;;   ((system-file . "systems/web01.scm"))

(use-modules (systems base)
             (gnu)
             (gnu packages web)
             (gnu services web))

(homelab-operating-system
 #:host-name "web01"
 #:packages (list nginx)
 #:extra-services
 ;; nginx on :8083 — :8080 is taken by BitLatch's observability server.
 (list (service nginx-service-type
                (nginx-configuration
                 (server-blocks
                  (list (nginx-server-configuration
                         (listen '("8083"))
                         (root "/srv/http"))))))))
