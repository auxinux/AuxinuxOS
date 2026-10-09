# Validation avant diffusion

Aucune suite automatisée complète n’est actuellement fournie.

## Tests automatisés

```bash
bash tests/test-rollback.sh
bash tests/test-auxi-noninteractive.sh
bash tests/test-assistant-apply.sh
bash tests/test-install-engine.sh
bash tests/test-windows-wizard.sh
bash tests/test-apt-snapshot-hook.sh
bash tests/test-post-install.sh
bash tests/test-welcome.sh
bash tests/test-verify-boot.sh
bash tests/test-boot-sentinel.sh
bash tests/test-profile.sh
bash tests/test-hwcheck.sh
bash tests/test-no-telemetry.sh
bash tests/test-version-consistency.sh
bash tests/test-auxi-kernel.sh
bash tests/test-user-dirs.sh
bash tests/test-release-package.sh
(cd packages/auxinux-center && cargo test --no-default-features)
```

`test-rollback.sh` couvre la logique de `auxi rollback` : numéro invalide,
instantané inexistant, refus de confirmation, restauration nominale et — le cas
critique — reprise après échec de `btrfs subvolume snapshot`, quand la machine
se retrouverait sinon sans racine amorçable.

`test-auxi-noninteractive.sh` couvre `auxi --yes --progress`, le chemin du
centre de contrôle. Le cas critique est la panne qui l’a fait naître : lancé
sans terminal, `apt-get upgrade` répondait « Abandon. » à sa propre question et
la mise à jour du système échouait sans message visible. Le faux `apt-get` du
test reproduit ce comportement ; le test vérifie aussi qu’un échec Flatpak
n’empêche plus les correctifs DEB, et que l’option `--yes` d’`auxi rollback`
n’est pas confondue avec l’option globale.

`test-assistant-apply.sh` couvre ce que l’assistant de premier démarrage
exécute en root. Cas critiques : une application indisponible sur Flathub ne
prive pas la personne des autres, le dépôt Brave n’est activé que si Brave est
choisi, et un identifiant commençant par un tiret est refusé avant d’atteindre
apt ou flatpak.

`test-install-engine.sh` exécute le moteur de l’installateur maison en
`--simuler` : les commandes sont affichées, pas exécutées. Cas critiques : une
configuration invalide est refusée **avant toute commande sur le disque**, le
support d’installation n’est jamais une cible, et un disque chiffré reste
déverrouillable par GRUB (PBKDF2, GRUB non signé avec cryptodisk).
`vm-install-now.sh` rejoue, lui, une vraie installation en VM par l’entrée GRUB
par défaut, jusqu’au bureau.

`test-windows-wizard.sh` couvre l’assistant `.exe` : arguments invalides, sortie
en erreur explicite quand `zenity` manque, annulation, et — le cas critique —
l’usage d’un préfixe Wine dédié avec vérification que `~/.wine` n’est jamais
créé.

`test-verify-boot.sh` couvre la verification finale d'amorcabilite. Le cas
critique : `grub.cfg` qui designe un noyau absent, et noyau tronque sur le
disque — les deux formes de la panne « error: premature end of file » qui,
jusqu'ici, ne se voyait qu'au redemarrage, apres une installation annoncee
reussie.

`test-boot-sentinel.sh` couvre la protection au démarrage. Les cas critiques
sont **symétriques** : trop prudente, elle laisse l’utilisateur devant un écran
noir ; trop zélée, elle fait basculer en mode secours une machine qui démarre
volontairement en console, ou une session live. Une session `tty` active ne doit
jamais compter comme un succès — c’est l’état d’une machine déjà tombée sur la
console de secours.

`test-profile.sh` couvre les profils d’usage. Le cas critique : un réglage qui
ne **part pas** quand on quitte un profil (la priorité temps réel audio qui
resterait accordée en bureautique), car le système cumulerait alors les réglages
de tous les profils déjà essayés.

`test-no-telemetry.sh` est un audit statique de la promesse « aucune
télémétrie ». Il ne regarde **aucun trafic réseau** : l’audit réel demande une
VM avec capture du trafic, et reste à faire.

`test-version-consistency.sh` prend `os-release` comme source de vérité et exige
que les huit autres emplacements de la version s’alignent. Une version oubliée
ne casse rien — elle s’affiche — donc rien ne la signale avant une release.

`test-welcome.sh` couvre l’écran d’accueil live et le lanceur d’installation.
Le cas critique : **aucun chemin ne doit fermer la session**. L’accueil
proposait auparavant de la redémarrer et exécutait `loginctl terminate-user` ;
comme la session live vient du bloc `[initial_session]` de greetd, qui ne
s’applique qu’une fois au démarrage, cela jetait l’utilisateur hors du live —
la panne « je choisis la langue, ça quitte l’interface et reste noir ». Le test
vérifie aussi que la langue choisie est bien transmise à Calamares.

`test-apt-snapshot-hook.sh` couvre le hook dpkg qui porte désormais la promesse
« un instantané avant chaque transaction DEB » : paire pre/post, silence sur une
racine ext4 ou dans le chroot d’installation, respect de `AUXI_NO_SNAPSHOT`, et
— le cas critique — le fait qu’un échec de snapper **n’avorte jamais** la
transaction apt.

`test-post-install.sh` couvre les deux scripts de fin d’installation : le
retrait effectif de l’installateur, de son autodémarrage et de Calamares du
système installé, et la configuration du rollback quel que soit l’emplacement
du modèle snapper — la régression qui laissait chaque système installé sans
aucune restauration.

Dans tous les cas, les commandes système (`btrfs`, `mount`, `wine`, `zenity`,
`snapper`, `chroot`, `findmnt`) sont remplacées par des stubs : ces tests
valident l’enchaînement et les chemins, pas le comportement réel des outils.

## Vérification du rootfs pendant la construction

`image-builder/scripts/check-rootfs.sh` s’exécute automatiquement avant la
compression du squashfs et **arrête la construction** si une fonction annoncée
manque à l’image. Il peut aussi être lancé seul sur un rootfs existant :

```bash
./image-builder/scripts/check-rootfs.sh /mnt/build/Auxinuxos-normal/0.2.0-live/rootfs
```

## Vérifications locales

- Vérifier la syntaxe des scripts avec `bash -n`.
- Valider le JSON de la politique Brave.
- Tester `auxi --help`, `auxi status` et le refus d’une opération DEB sans sudo.
- Compiler le centre sur Debian 13 amd64 et vérifier son lancement graphique.
  `./packages/auxinux-center/build.sh --backend-only` valide la logique sans
  aucune dépendance graphique ; la compilation complète exige
  `libxkbcommon-dev` et `libwayland-dev`.

## Validation en machine virtuelle

1. Construire une ISO depuis un environnement maîtrisé.
2. Tester le démarrage live en BIOS puis UEFI.
3. Vérifier COSMIC, le réseau et l’ouverture de Calamares.
4. Installer sur un disque virtuel jetable avec un compte autre que `auxinux`.
5. Retirer l’ISO, redémarrer et ouvrir une session avec ce compte.
6. Vérifier que le compte live, son sudo sans mot de passe et l’autologin ont
   disparu, que **Calamares n’est plus installé**, qu’aucune fenêtre
   d’installation ne s’ouvre à l’ouverture de session, que `/etc/fstab` est
   intact, et que le compte créé porte bien l’**UID 1000** (`id -u`).
7. Tester recherche, installation, mise à jour et désinstallation Flatpak et DEB.
8. Vérifier les langues, le son et les paramètres du bureau.

## Validation du rollback (obligatoire avant diffusion)

9. Vérifier que `/` est en BTRFS et que les sept sous-volumes sont montés :
   `findmnt -t btrfs`.
10. Vérifier les options dans `/etc/fstab` : `noatime`, `compress=zstd:1`.
11. `auxi status` doit annoncer « Rollback système : actif » et lister
    l’instantané « Installation initiale ».
12. `sudo auxi install <un paquet DEB>` doit créer un instantané avant
    l’opération ; `sudo snapper -c root list` doit montrer une paire pre/post.
13. Casser volontairement le système (par exemple purger un paquet essentiel),
    redémarrer, puis restaurer via le sous-menu GRUB
    « AuxiNux OS - instantanés ». **Point à valider en priorité** : l’entrée
    doit aboutir à une session utilisable, et non se figer — c’est le hook
    initramfs `auxinux-snapshot-overlay` qui rend l’instantané inscriptible, et
    il n’a jamais été éprouvé sur un démarrage réel. Vérifier ensuite
    `findmnt /` (attendu : `overlay`) puis lancer `sudo auxi rollback NUMERO`.
13b. Vérifier qu’un démarrage NORMAL n’est pas affecté : `findmnt -no FSTYPE /`
    doit renvoyer `btrfs`, jamais `overlay`.
14. Après restauration : vérifier que `/home` est intact, que les journaux
    d’avant la restauration sont toujours dans `/var/log`, et que les
    applications Flatpak sont toujours installées.
15. Vérifier que `@.rollback-*` existe encore, puis que
    `sudo auxi rollback-cleanup` le liste et le supprime.
15b. Vérifier que l’instantané est bien posé HORS de `auxi` :
    `sudo AUXI_NO_SNAPSHOT=0 apt install <paquet>` après
    `sudo auxi set apt=true` doit créer une paire pre/post dans
    `sudo snapper -c root list`.
16. Reprendre les étapes 9 à 15 sur une installation **chiffrée (LUKS)**, cas
    non testé à ce jour.

## Validation du centre de contrôle (0.2, jamais lancé graphiquement)

17. Vérifier que le centre s'ouvre et adopte le thème COSMIC, en clair
    **et** en sombre.
18. Lancer une installation depuis Applications : la fenêtre doit rester
    utilisable et navigable pendant toute l'opération.
19. Rechercher une application présente sur Flathub **et** en DEB (VLC, GIMP),
    basculer sur « AuxiNux (DEB) » et vérifier que la fiche affiche le nom de
    paquet (`vlc`) et non l'app-id Flatpak. Installer et confirmer avec
    `dpkg -l`.
20. Ouvrir Santé : vérifier que chaque anomalie porte un conseil lisible.
21. Ouvrir Restauration : créer un point, vérifier qu'il apparaît dans
    `snapper -c root list`, puis tester la confirmation en deux temps.
22. Annuler une invite polkit et vérifier que l'interface affiche l'échec au
    lieu de rester bloquée ou d'afficher un faux succès.

## Validation de la couche Windows et de la fluidité (jamais testée)

23. `dpkg --print-foreign-architectures` doit renvoyer `i386`, et
    `dpkg -l wine32` doit montrer le paquet installé.
24. Double-cliquer un `.exe` depuis le gestionnaire de fichiers : l'assistant
    doit s'ouvrir avec **trois** choix. Vérifier qu'aucune fenêtre ne manque —
    c'est le cas qui échouait silencieusement avec `kdialog`.
25. Choisir « Lancer directement avec Wine » et vérifier qu'un préfixe dédié
    apparaît sous `~/.local/share/auxinux/wine-prefixes/`, et que `~/.wine`
    n'est **pas** créé.
26. Ouvrir « Applications Windows et jeux », installer Bottles, vérifier que la
    fenêtre de progression s'affiche et que l'état passe à « Déjà installé ».
27. `zramswap status` (ou `zramctl`) doit montrer un périphérique zram actif en
    zstd, de priorité supérieure à tout autre swap (`swapon --show`).
28. `systemctl status systemd-oomd` doit être actif, et
    `systemd-analyze cat-config systemd/oomd.conf` doit reprendre les 20 s.
29. `systemctl show user@$(id -u).service -p ManagedOOMMemoryPressure` doit
    renvoyer `kill` — sans quoi systemd-oomd tourne sans rien surveiller.
30. Saturer volontairement la mémoire et vérifier que le bureau reste utilisable
    et qu'une application est tuée, au lieu d'un gel de plusieurs minutes.
31. `systemctl is-enabled fstrim.timer` doit renvoyer `enabled`.

Consigner la version de l’ISO, les résultats et les échecs avant diffusion.

## Banc d’essai « installation puis démarrage » (hôte de build)

`tests/vm-install-boot.sh` reconstitue une installation complète à partir du
rootfs de construction — sous-volumes BTRFS, `/etc/fstab`, compte utilisateur,
`post-install-cleanup.sh` — puis fabrique un disque GPT (ESP + BTRFS) **sans
périphérique loop**, l’hôte de build étant un conteneur LXC qui n’en a pas.
Le disque obtenu se démarre en QEMU avec OVMF.

```bash
# sur l'hôte de build
bash tests/vm-install-boot.sh all
qemu-system-x86_64 -machine q35 -m 4096 -smp 4 \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd \
  -drive file=/mnt/build/vmtest/disk.raw,format=raw,if=virtio \
  -device virtio-vga -serial file:serial.log -display none
```

C’est ce banc qui a permis, le 2026-09-09, de reproduire et de comprendre
l’écran noir du système installé. Il ne couvre **pas** les modules Calamares
eux-mêmes : il part du rootfs, pas du squashfs, et pose GRUB à la main.

## Banc d’essai de bout en bout : la VRAIE installation Calamares

Les deux bancs précédents ne passent pas par Calamares : le premier s’arrête au
bureau live, le second pose GRUB à la main. Or c’est **la séquence Calamares
elle-même** qui a produit les pannes vues sur matériel réel. Ce banc rejoue
l’installation graphique complète dans QEMU (UEFI, disque NVMe), puis démarre
le système installé.

`tests/vm-driver.py` pilote la VM par QMP (clavier, souris absolue, captures
d’écran) et par une console série journalisée :

```bash
# sur l'hôte de build (TCG, sans KVM)
tests/vm-boot-live-serial.sh e2e /dev/shm/auxinuxos.iso /mnt/build/e2e/disk.raw
tests/vm-driver.py shot e2e /tmp/ecran.png        # ce que voit l'utilisateur
tests/vm-driver.py click e2e 1000 643             # « Suivant »
tests/vm-driver.py type e2e "Quebec2026/"         # frappe physique (clavier US)
tests/vm-driver.py sh e2e "findmnt -t btrfs"      # shell root sur la console série
tests/vm-wait-install.sh e2e                      # attend la fin de Calamares
```

Pièges de l’émulation, tous rencontrés le 2026-09-29 :

- Le conteneur de construction est **plafonné à 4 processeurs**
  (`/sys/fs/cgroup/cpu.max`) alors que `nproc` en affiche 8 : au-delà de
  `-smp 4`, les processeurs virtuels sont étranglés et l’invité se bloque.
- Le disque de l’hôte est partagé et souvent saturé. QEMU écrit le journal de
  la console série et les captures depuis sa boucle principale : sur ce disque,
  **un octet écrit pouvait figer toute la VM**. Le répertoire de travail est
  donc en RAM (`/dev/shm/e2e`, défaut du pilote), l’ISO aussi ; seul le disque
  virtuel reste sur le disque de l’hôte.
- **KWin consomme 300 % du processeur** de la VM en rendu logiciel (llvmpipe)
  pendant le diaporama de Calamares : la copie tombe à 30 Mo/min, et le montage
  de la cible dépasse le délai de Calamares, qui l’interrompt — l’installation
  échoue. Basculer sur une console texte (`key e2e ctrl-alt-f3`) **dès le clic
  « Installer maintenant »** ; Calamares continue en arrière-plan.
- Le **chien de garde TCO** émulé redémarrait la VM en pleine installation
  quand le noyau invité, saturé, ne le relançait pas : `vm-driver.py` démarre
  QEMU avec `ICH9-LPC.noreboot=true`.
- Les délais d’E/S de l’invité (NVMe, lecteur optique) sont dépassés sur un
  hôte chargé : `nvme_core.io_timeout=600` sur la ligne de commande du live, et
  `/sys/block/sr0/device/timeout` relevé dès l’ouverture du shell.
- Une seule conversation à la fois sur la console série : deux clients y
  entrelacent leurs caractères et le shell root exécute un mélange des deux
  commandes. `vm-driver.py` prend un verrou.
- `pgrep -f motif` lancé par ssh se trouve lui-même.
