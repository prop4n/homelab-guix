# HANDOFF — homelab-guix (contexte technique complet)

Document de passation. But : qu'une autre IA (ou un humain) reprenne le projet
sans le contexte de la conversation d'origine. Écrit le 2026-09-04.

Langue : le projet est piloté en français, le code/commentaires en anglais.

---

## 1. Ce qu'on essaie de faire

Un **homelab GitOps déclaratif** sur **Proxmox**, piloté par **Guix** et
**BitLatch**.

Le principe :

1. On construit **UNE image Guix générique** (`image/homelab.qcow2`) à partir de
   `systems/template.scm`.
2. On la déploie sur Proxmox pour **chaque** VM (via `proxmops`, voir §6).
3. Au premier boot, chaque VM lit son **userData** (payload NoCloud) qui dit
   *quelle machine elle est* : `((system-file . "systems/web01.scm"))`.
4. **BitLatch** (l'agent, tourne dans la VM) clone ce repo et applique
   `systems/<machine>.scm` avec `guix system reconfigure`, puis **suit chaque
   commit** (reconcile loop).

```
  ce repo (desired state)                    Proxmox
 ┌──────────────────────────┐          ┌──────────────────────────┐
 │ systems/web01.scm        │          │  VM (image homelab.qcow2) │
 │ systems/web02.scm        │─proxmops→│   userData: web01.scm     │
 │ systems/template.scm     │          │     │                     │
 └──────────────────────────┘          │  nocloud → BitLatch       │
            ▲   git push               │     │                     │
            └───────────────────────────┼── reconfigure to web01 ──┘
              (BitLatch suit)            └──────────────────────────┘
```

**Contrainte de conception voulue par le propriétaire** : on garde le modèle
**tout-déclaratif, rebuild complet, bit-à-bit reproductible**. On NE veut PAS
découpler le contenu applicatif du système (ex. servir un site via un `git pull`
runtime séparé) même si ce serait plus rapide : la reproductibilité totale prime.

---

## 2. Les 4 dépôts en jeu

| Repo (local) | Rôle | GitHub |
|---|---|---|
| `~/projets/homelab-guix` | **CE repo** : l'infra déclarative + l'image | github.com/prop4n/homelab-guix (public) |
| `~/projets/bitlatch` | L'agent Go + le canal Guix (`guix/bitlatch/*.scm`) | github.com/prop4n/bitlatch |
| `~/projets/guix-metadata` | Le canal `nocloud` (lit l'userData) | github.com/prop4n/guix-metadata |
| `~/projets/proxmops` | GitOps Proxmox (déploie les VMs depuis `proxmox/*.yaml`) | github.com/prop4n/proxmops |

`modules/bitlatch` et `modules/metadata` dans CE repo sont des **copies
vendorées** de `guix/bitlatch` et `modules/metadata` des deux canaux — parce
qu'en **mode direct** (voir §4) le `guix system reconfigure` a besoin de ces
modules sur son load-path (`-L modules`). Pour les mettre à jour : recopier les
arbres depuis les dépôts sources.

---

## 3. Structure de CE repo

```
systems/
  base.scm         helper (homelab-operating-system) : configure BitLatch (mode
                   direct), nocloud, ssh (clé debug), substituts nonguix, canaux
                   épinglés, console tty0 (affichage Proxmox), net.ifnames=0 (eth0)
  template.scm     l'OS générique -> SOURCE DE L'IMAGE
  web01.scm        machine : nginx :8083, IP statique 192.168.1.211, sert une page
  web01-site/index.html   le contenu servi par nginx (via local-file + activation)
  web02.scm        machine : box simple (htop, git), IP statique 192.168.1.212
modules/
  bitlatch/{packages,services}.scm   vendoré de ~/projets/bitlatch/guix/bitlatch
  metadata/…                         vendoré de ~/projets/guix-metadata/modules/metadata
channels.scm       guix + nonguix épinglés (mêmes commits que %homelab-channels)
image/build.sh     construit le qcow2 depuis template.scm
image/homelab.qcow2   L'IMAGE (gitignorée, ~560 Mo, régénérable)
proxmox/web01.yaml, web02.yaml   manifests proxmops (kind: VirtualMachine)
.ssh-debug/homelab{,.pub}   clé SSH debug pour entrer dans les VMs (gitignorée)
README.md          doc user-facing
HANDOFF.md         CE fichier
```

---

## 4. Mode « direct » vs « time-machine » (important)

BitLatch peut reconfigurer de deux façons (`reconfigure-mode` dans le service) :

- **time-machine** (défaut de BitLatch) : `guix time-machine -C channels.scm --
  system reconfigure …`. Reproductibilité maximale, mais **clone tout `guix.git`**
  (~500 Mo) au premier boot de chaque VM → très lent (~15 min juste pour ça).
- **direct** (ce qu'on utilise ici, réglé dans `systems/base.scm`) :
  `guix system reconfigure -L . -L modules …` avec le guix **déjà présent dans
  l'image**. Pas de clone. `-L .` résout `(systems base)`, `-L modules` résout
  `(bitlatch services)` + `(metadata services nocloud)`.
  Compromis : Guix lui-même se met à jour en **rebuildant l'image**, pas par un
  commit. C'est le modèle voulu ici.

Conséquence du mode direct : **tout module non-standard doit être vendoré dans
`modules/`**. C'est pourquoi on ne peut pas facilement utiliser le noyau nonguix
`(nongnu packages linux)` sans vendorer tout nonguix (jugé trop crade, écarté).

---

## 5. Construire l'image + tester en LOCAL (QEMU)

### Construire l'image
```sh
cd ~/projets/homelab-guix
./image/build.sh          # -> image/homelab.qcow2
# (fait: guix system image -t qcow2 --image-size=20G -L . -L modules systems/template.scm)
```

### Tester en local avec QEMU (sans Proxmox)
Le workflow utilisé pendant le dev (tout est dans /tmp, adaptable) :

```sh
# 1. seed userData NoCloud pointant sur web01
mkdir -p /tmp/hl-seed
printf '#cloud-config\n((system-file . "systems/web01.scm"))\n' > /tmp/hl-seed/user-data
echo "instance-id: hl-web01" > /tmp/hl-seed/meta-data
guix shell xorriso -- xorriso -as mkisofs -output /tmp/hl-seed.iso \
     -volid CIDATA -joliet -rock /tmp/hl-seed

# 2. disque neuf depuis l'image
cp image/homelab.qcow2 /tmp/hl-vm.qcow2 && chmod +w /tmp/hl-vm.qcow2

# 3. boot QEMU (user-net : 2225->22 ssh, 8085->8080 observabilité BitLatch)
qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 \
  -drive file=/tmp/hl-vm.qcow2,if=virtio,format=qcow2 \
  -drive file=/tmp/hl-seed.iso,media=cdrom,readonly=on \
  -netdev user,id=n0,hostfwd=tcp::2225-:22,hostfwd=tcp::8085-:8080 \
  -device virtio-net-pci,netdev=n0 \
  -display none -serial file:/tmp/hl-serial.log
```

Observer / entrer :
```sh
# état de l'agent
curl -s http://localhost:8085/state
# SSH (clé debug de ce repo)
ssh -i .ssh-debug/homelab -p 2225 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null root@localhost
# dans la VM :
herd status bitlatch
guix processes                 # voir les builds en cours (LockHeld)
tail -f /var/log/messages
```

La VM boote en `homelab-template`, puis bascule sur `web01` (+ IP 192.168.1.211)
quand BitLatch a appliqué `web01.scm`. Le `/state` passe FETCHING →
BUILDING_AND_RECONFIGURING → IDLE, avec `applied_hash`.

Note : la sortie de `guix reconfigure` va sur `/dev/console` = tty0 (VGA), donc
elle N'est PAS dans `/tmp/hl-serial.log` (série) ni facilement dans un fichier ;
sur Proxmox on la voit dans la console noVNC. `/var/log/messages` a les événements
shepherd/BitLatch mais pas le flux guix complet.

---

## 6. Déployer sur le VRAI Proxmox

Proxmox réel : **192.168.1.200** (node name : vérifier via `ssh root@192.168.1.200
hostname`, les manifests supposent `pve`). Storage local : `/var/lib/vz/import`.

```sh
# upload de l'image (une fois le dossier import activé)
ssh root@192.168.1.200 'mkdir -p /var/lib/vz/import'
scp image/homelab.qcow2 root@192.168.1.200:/var/lib/vz/import/homelab.qcow2
ssh root@192.168.1.200 'pvesm set local --content iso,vztmpl,backup,snippets,import'
```

`proxmox/web01.yaml` / `web02.yaml` (format proxmops) référencent l'image en
`local:import/homelab.qcow2` (volume ref = pas de download) et portent l'userData.
Ensuite on pointe **proxmops** sur le dossier `proxmox/` ; il crée les VMs, génère
l'ISO CIDATA depuis `userData`, et les démarre.

VMs déployées observées : web01 → 192.168.1.211, web02 → 192.168.1.212 (IP
statiques qui montent QUAND le système-cible est appliqué → `ping` = signal
« c'est appliqué »).

---

## 7. Historique des bugs corrigés (dans le canal bitlatch)

Tous poussés sur github.com/prop4n/bitlatch (main). Le canal (HEAD de main)
fournit `(bitlatch packages)` + `(bitlatch services)`.

1. Course config.env / nocloud → le rendu de `/etc/bitlatch/config.env` est
   fusionné DANS le programme de start du daemon (shepherd marque un one-shot
   « started » au fork, donc un service de config séparé ne pouvait pas gagner
   la course).
2. `reboot_required` toujours vrai → `filepath.EvalSymlinks` + comparer
   `/run/booted-system` vs `/run/current-system`.
3. État non persistant → `state.json` (applied_hash rechargé au démarrage, plus
   de reconfigure inutile au reboot).
4. `--allow-downgrades` (option) : requis en direct mode, sinon le guix figé de
   l'image ressemble à un downgrade après reboot et reconfigure aborte.
5. `reconfigure-timeout` (option) + streaming de la sortie guix sur stderr.
6. CA/SSL → le service passe `SSL_CERT_DIR`, `SSL_CERT_FILE`, `GIT_SSL_CAINFO`
   et `nss-certs` est dans les packages (sinon `git clone https://…github` échoue
   « certificate signer not trusted »).
7. `log-file` (option) → route la sortie du daemon sur `/dev/console`.
8. **Package = binaire release** (LE gros fix perf, voir §8) : `packages.scm`
   utilise maintenant `url-fetch` du tarball
   `bitlatch_<ver>_linux_amd64.tar.gz` (goreleaser, `CGO_ENABLED=0`, statique) +
   `copy-build-system`, AU LIEU de `go-build-system`. Le hack `GODEBUG=httpmuxgo121=0`
   a disparu (le binaire goreleaser route correctement, contrairement au build
   GOPATH de go-build-system qui renvoyait 404 sur toutes les routes).

Côté homelab : load-path `.:modules`, IP statiques, `net.ifnames=0`, console
tty0, clé SSH debug.

---

## 8. LE problème ouvert : performance des reconfigures (À RÉSOUDRE)

C'est le sujet chaud. Le propriétaire veut que ça aille **vite** tout en gardant
le **rebuild complet déclaratif** (pas de découplage contenu/infra).

### Ce qui a DÉJÀ été éliminé
- Clone `guix.git` → supprimé par le mode direct.
- Compilation de bitlatch (tirait **gcc + go-std**, ~20 min) → supprimée par le
  fix #8 (binaire release). **Vérifié** : plus de `go-std`, closure de bitlatch =
  `bitlatch + git-minimal + bash-minimal` seulement.

### Mesures (VM QEMU 4 vCPU / 4 Go, hôte 16 cœurs/14 Go)
- Premier boot d'une VM vierge → web01 appliqué : **~288 s** (dont : gcc pour les
  *modules kernel* du système, matérialisation initrd, éval Guile).
- Changement TRIVIAL de contenu (VM déjà chaude) : **~1176 s (~20 min)** — anormal.
- Régime « idéal » théorique (tout en cache) : ~110 s d'éval + le poll (60 s).

### Diagnostic (partiel, à confirmer)
- Le **noyau `linux-libre-7.0.14` n'est PAS recompilé** : il y en a UN seul dans
  le store, il vient des substituts. (Un grep `build=linux` trop large avait
  induit en erreur ; il matchait probablement `linux-modules`/scripts.)
- Un **dry-run prouve** que changer `systems/web01-site/index.html` force la
  reconstruction de : `raw-initrd.drv`, plusieurs `activate-service.scm.drv`,
  `system.drv`. Autrement dit, **mettre le contenu web DANS la config système**
  (via `local-file` + un `simple-service activation-service-type` dans
  `web01.scm`) fait dépendre l'initrd/le système du contenu → rebuild à chaque
  changement de page.
- MAIS les logs de build (`/var/log/guix/drvs/`) du dernier reconfigure ne
  montraient que des dérivations LÉGÈRES (scripts d'activation, shepherd.conf,
  grub.cfg, system, boot) construites en ~23 s. **Donc le gros des ~20 min n'est
  PAS du build** — c'est probablement l'**évaluation Guile** de
  `guix system reconfigure` (process `guix` mono-thread ~50-70 % CPU pendant
  plusieurs minutes, `guix processes` sans `LockHeld` significatif) + peut-être
  de la matérialisation/téléchargement intermittente.

### Questions ouvertes pour la prochaine IA
1. **Où passent réellement les minutes** d'un reconfigure sur cette VM ?
   Instrumenter : `guix system reconfigure … --verbosity=2` capturé dans un
   fichier (le lancer À LA MAIN dans la VM, pas via BitLatch qui envoie sur
   /dev/console) ; corréler avec `guix processes` (LockHeld) et le CPU. Trancher
   entre : (a) éval Guile pure, (b) construction locale (initrd/cpio), (c)
   attente daemon/substituts.
2. **Pourquoi `raw-initrd` se reconstruit** quand seul le contenu change, alors
   que l'initrd ne devrait dépendre que du matériel/fs/modules ? Est-ce le
   `activation-service` qui injecte le contenu dans le graphe de boot ? Si oui,
   comment garder le rebuild déclaratif SANS que l'initrd dépende du contenu.
3. **L'évaluation Guile est mono-thread et incompressible** : est-ce que
   pré-compiler le cache bytecode `.go` des modules dans l'image aide (charge)
   ou pas (l'éval du graphe n'est pas du chargement) ? À mesurer, pas supposer.
4. Piste flotte « build once, deploy many » : évaluer/construire le système UNE
   fois (machine costaude / CI), publier sur un **cache de substituts**, et faire
   que les VMs **téléchargent** le système déjà construit au lieu de l'évaluer
   chacune. Change le modèle d'exécution de BitLatch (télécharger vs évaluer).

### Contrainte à respecter
Le propriétaire REFUSE la solution « découpler le contenu du système » (servir la
page via un service qui git-pull dans /srv/http hors config Guix). Il veut le
rebuild complet déclaratif. Donc : accélérer le reconfigure LUI-MÊME, ou changer
le modèle de distribution (substituts/cache), sans sacrifier la repro bit-à-bit.

---

## 9. Environnement / divers

- Hôte de dev : **Guix System**, 16 cœurs, 14 Go RAM. `~/.cache/guix/checkouts`
  contient les canaux (guix, nonguix pin `bdc27101`, …).
- `rtk` (préfixe visible dans l'historique) = un proxy CLI token-saver branché en
  hook ; l'ignorer, ce n'est pas dans le projet.
- La clé SSH debug (`.ssh-debug/homelab`) est **gitignorée** ; elle est câblée en
  `authorized_keys` root dans `systems/base.scm` (%root-authorized-key). Pour la
  prod, remplacer par une vraie clé.
- LAN : hôte 192.168.1.34, Proxmox 192.168.1.200, VMs .211/.212.
- `guix gc --delete-generations=1w` (ou `-F <N>G`) si le store sature pendant les
  builds d'image (l'image raw temporaire fait ~20 Go).
