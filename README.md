# homelab-guix

A GitOps homelab on **Proxmox**, driven by **Guix** and **BitLatch**.

One generic Guix image boots every VM. At first boot each VM reads its userData
(a tiny NoCloud payload) to learn *which machine it is*, and
[BitLatch](https://github.com/prop4n/bitlatch) reconfigures it to the matching
system file from this repository — then keeps it in sync with every commit.

```
   this repo (desired state)                Proxmox
  ┌───────────────────────────┐        ┌──────────────────────────┐
  │ systems/web01.scm         │        │  VM web01                │
  │ systems/web02.scm         │        │   image = homelab.qcow2  │
  │ image = systems/template  │──────▶ │   userData: web01.scm    │
  └───────────────────────────┘        │      │                   │
             ▲                          │   nocloud → BitLatch     │
             │  git push a commit       │      │                   │
             └──────────────────────────┼── reconfigure to web01 ──┘
                (BitLatch follows it)    └──────────────────────────┘
```

Two GitOps agents cooperate:
- **proxmops** turns `proxmox/*.yaml` into real VMs (disk from the image + the
  userData seed).
- **BitLatch** runs *inside* each VM and applies `systems/<machine>.scm`.

## Layout

```
systems/          the machines BitLatch watches (the desired state)
  base.scm        homelab-operating-system: BitLatch (direct mode), nocloud, ssh,
                  nonguix substitutes, pinned channels
  template.scm    the generic image (what a VM is until userData specialises it)
  web01.scm       a machine: nginx on :8083
  web02.scm       a machine: plain box
modules/          vendored channels, on the load path for direct-mode reconfigure
  bitlatch/       from github.com/prop4n/bitlatch (guix/bitlatch)
  metadata/       from github.com/prop4n/guix-metadata (modules/metadata)
image/build.sh    builds the generic qcow2 from systems/template.scm
channels.scm      pinned guix + nonguix (kept in sync with base.scm)
proxmox/*.yaml    proxmops manifests, one VirtualMachine per machine
```

## One-time setup

1. **Push this repo** to a Git host and set `%homelab-repo` in
   `systems/base.scm` to its URL (BitLatch clones it from inside each VM).
2. **Set your SSH key**: replace `%root-authorized-key` in `systems/base.scm`.
3. **Build the image**:
   ```sh
   ./image/build.sh                 # -> image/homelab.qcow2
   ```
4. **Upload** `image/homelab.qcow2` somewhere Proxmox can fetch by URL, and put
   that URL in `proxmox/*.yaml` (`spec.image.source`).
5. **Adjust** the manifests (`node`, `vmid`, `storage`, `bridge`) to your cluster.

## Deploy

Point proxmops at this repo (its `proxmox/` folder). It imports the image,
generates each VM's CIDATA seed from `userData`, and boots the VMs. Each machine
then specialises itself and follows this repo.

## Add a machine

1. Write `systems/<name>.scm` (`(homelab-operating-system #:host-name "<name>" …)`).
2. Copy a `proxmox/*.yaml`, bump `vmid`/`name`, set
   `userData: ((system-file . "systems/<name>.scm"))`.
3. Commit, push. proxmops creates the VM; BitLatch makes it that machine.

## Reconfigure mode: direct

Machines run **direct mode** (reconfigure with the image's Guix + vendored
`modules/`, no `guix.git` clone), so commits apply in ~1 minute once warm.
Updating Guix itself means bumping `channels.scm` + `%homelab-channels` and
**rebuilding the image** — not a commit.

> First boot of a fresh VM is slower (the Guile bytecode cache is cold); steady
> state is fast. A reboot keeps the cache. `BITLATCH_RECONFIGURE_TIMEOUT` (set to
> 20m in base.scm) aborts a stuck reconfigure and retries.

## Security note

BitLatch runs as root and applies whatever this repo says: whoever controls the
repo controls the machines. Protect the branch.
