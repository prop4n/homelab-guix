;;; SPDX-License-Identifier: MIT
;;;
;;; web01 — an nginx web server. Point a VM at this file via its userData:
;;;   #cloud-config
;;;   ((system-file . "systems/web01.scm"))

(use-modules (systems base)
             (gnu)
             (gnu packages web)
             (gnu services networking)
             (gnu services web))

(homelab-operating-system
 #:host-name "web01"
 #:packages (list nginx)
 ;; Static IP so you can ping web01 directly and watch the apply land.
 ;; Adjust the address/gateway/DNS to your LAN.
 #:networking
 (list (service static-networking-service-type
                (list (static-networking
                       (addresses
                        (list (network-address
                               (device "eth0")
                               (value "192.168.1.211/24"))))
                       (routes
                        (list (network-route
                               (destination "default")
                               (gateway "192.168.1.1"))))
                       (name-servers '("1.1.1.1"))))))
 #:extra-services
 ;; nginx on :8083 — :8080 is taken by BitLatch's observability server.
 ;; The document root is the ./web01-site directory, served straight from the
 ;; store: edit the page, commit, and BitLatch redeploys it.
 (list (service nginx-service-type
                (nginx-configuration
                 (server-blocks
                  (list (nginx-server-configuration
                         (listen '("8083"))
                         (root (local-file "web01-site" #:recursive? #t)))))))))
