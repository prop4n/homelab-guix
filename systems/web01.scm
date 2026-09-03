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
 ;; nginx serves the fixed /srv/http; an activation step copies ./web01-site
 ;; there on every reconfigure. Because the nginx config itself never changes,
 ;; a front edit shows up without restarting nginx: edit, commit, done.
 (list (service nginx-service-type
                (nginx-configuration
                 (server-blocks
                  (list (nginx-server-configuration
                         (listen '("8083"))
                         (root "/srv/http"))))))
       (simple-service 'web01-page activation-service-type
                       #~(begin
                           (use-modules (guix build utils))
                           (mkdir-p "/srv/http")
                           (copy-recursively #$(local-file "web01-site"
                                                           #:recursive? #t)
                                             "/srv/http")
                           (for-each (lambda (f) (chmod f #o644))
                                     (find-files "/srv/http"))))))
