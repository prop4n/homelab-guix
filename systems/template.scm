;;; SPDX-License-Identifier: MIT
;;;
;;; The generic image. Build ONE qcow2 from this file (see ../image/build.sh),
;;; upload it to Proxmox, and boot every machine from it. On first boot the
;;; nocloud service reads the VM's userData and BitLatch reconfigures the machine
;;; to the system file it names. Until then, the machine is this template.

(use-modules (systems base) (gnu))

(homelab-operating-system
 #:host-name "homelab-template")
