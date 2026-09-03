;;; SPDX-License-Identifier: MIT
;;;
;;; web02 — a second machine, here just a plain box with a couple of tools.
;;; Point a VM at it via userData: ((system-file . "systems/web02.scm"))

(use-modules (systems base)
             (gnu)
             (gnu packages admin)
             (gnu packages version-control)
             (gnu services networking))

(homelab-operating-system
 #:host-name "web02"
 #:packages (list htop git)
 ;; Static IP so you can ping web02 directly. Adjust to your LAN.
 #:networking
 (list (service static-networking-service-type
                (list (static-networking
                       (addresses
                        (list (network-address
                               (device "eth0")
                               (value "192.168.1.212/24"))))
                       (routes
                        (list (network-route
                               (destination "default")
                               (gateway "192.168.1.1"))))
                       (name-servers '("1.1.1.1")))))))
