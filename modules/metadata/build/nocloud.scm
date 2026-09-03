;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 prop4n <contact@legrandenzo.fr>

(define-module (metadata build nocloud)
  #:use-module (metadata build user-data)
  #:use-module (guix build syscalls)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (%default-labels
            %default-file-system-types
            find-datasource
            call-with-mounted-datasource
            fetch-payload))

;; The NoCloud datasource is a filesystem carrying 'user-data' and
;; 'meta-data', labelled 'cidata'.  Proxmox attaches one to every virtual
;; machine it manages, as do libvirt, plain QEMU and others.  This reads it
;; directly rather than through cloud-init, which Guix does not package.

(define %default-labels
  ;; Labels are matched case insensitively, as the specification says, because
  ;; tools disagree on the case they write.
  '("cidata" "CIDATA"))

(define %default-file-system-types
  '("iso9660" "vfat"))

(define (label-directory) "/dev/disk/by-label")

(define* (find-datasource #:key (labels %default-labels)
                          (directory (label-directory)))
  "Return the device carrying one of LABELS, or #f.  Matching is done on the
names udev created, so nothing needs to be mounted to look."
  (define (normalize name) (string-downcase name))

  (let ((wanted (map normalize labels))
        (entries (or (scandir directory) '())))
    (and=> (find (lambda (name)
                   (and (not (member name '("." "..")))
                        (member (normalize name) wanted)))
                 entries)
           (lambda (name) (string-append directory "/" name)))))

(define* (call-with-mounted-datasource device proc
                                       #:key (types %default-file-system-types))
  "Mount DEVICE read-only somewhere temporary, call PROC on the mount point,
and unmount it whatever happens.  Try each of TYPES in turn: the label says
nothing about the filesystem, and providers use more than one."
  (let ((target (mkdtemp "/tmp/guix-metadata-XXXXXX")))
    (dynamic-wind
      (const #t)
      (lambda ()
        (and (any (lambda (type)
                    (catch 'system-error
                      (lambda () (mount device target type MS_RDONLY) #t)
                      (const #f)))
                  types)
             (proc target)))
      (lambda ()
        (catch 'system-error (lambda () (umount target)) (const #t))
        (catch 'system-error (lambda () (rmdir target)) (const #t))))))

(define* (fetch-payload #:key (labels %default-labels)
                        (types %default-file-system-types)
                        (file-name "user-data")
                        (log (const #t)))
  "Return the payload this host was given, or #f when there is no datasource
or nothing usable on it."
  (match (find-datasource #:labels labels)
    (#f
     (log "no datasource found")
     #f)
    (device
     (log (string-append "reading " device))
     (call-with-mounted-datasource
      device
      (lambda (mount-point)
        (let ((payload (read-payload (string-append mount-point "/"
                                                    file-name))))
          (unless payload
            (log (string-append "no payload in " file-name)))
          payload))
      #:types types))))
