# Construction de l’ISO

## Prérequis

Hôte Debian 13 amd64 avec accès sudo et réseau, espace disque suffisant pour
le rootfs, les caches Rust et l’ISO.

Depuis la 0.2.0, **aucune compilation de bureau** : Plasma vient de Debian. Le
cache de sources COSMIC (21 Go) et le dépôt OBS tiers ont disparu de la
chaîne.

Outils : `mmdebstrap`, `mksquashfs` (squashfs-tools), `grub-mkrescue`,
`xorriso`, `rsync`, `curl`, `mformat` (mtools), `git` et les outils GRUB BIOS/EFI.
Le centre nécessite Rust ≥ 1.93 et les dépendances de développement de
libcosmic (`libxkbcommon-dev`, `libwayland-dev`, `libudev-dev`,
`libinput-dev`) : voir [son README](../packages/auxinux-center/README.md).
Qt6 et KF6 ne sont plus nécessaires depuis la 0.2.

## Commandes

Depuis la racine du dépôt, sur l’hôte Linux :

```bash
./packages/auxinux-center/build.sh
./image-builder/build-image.sh --work-dir /mnt/build/Auxinuxos-normal
```

La sortie est `image-builder/output/auxinuxos-0.4.0-amd64.iso`, et les paquets
qu'elle contient (`auxi`, `auxinux-center`, `auxinuxos-release` de son édition)
sont dans `image-builder/output/debs/`. Publication : d'abord ces paquets
(`packages/publish-debs.sh --dir …/image-builder/output/debs --deploy`), puis
l'ISO (`image-builder/publish-iso.sh --iso … --deploy`), qui le vérifie.
`--force` supprime le répertoire de construction du profil avant de repartir.
`--reuse-rootfs` réutilise un rootfs existant ; ces options sont incompatibles.

## Listes de paquets

Le contenu de l’image est décrit par `package-lists/`, et par rien d’autre :

| Liste | Contenu |
|---|---|
| `base.txt`, `firmware.txt` | socle système et micrologiciels |
| `bureau-auxinux.txt` | AuxiNux Shell, SDDM, applications AuxiNux et KDE, pilotes graphiques, audio |
| `retire-du-socle.txt` | bureau Plasma et equivalents des applications AuxiNux : purges et refuses |
| `i18n-canada.txt` | dictionnaires fr/en-CA |
| `live-installer.txt` | installateur du médium live |
| `rollback.txt`, `performance.txt` | snapper/grub-btrfs, zram |
| `codecs-multimedia.txt` | codecs, décodage matériel, audio temps réel |
| `securite.txt` | pare-feu UFW |
| `couche-windows.txt` | Wine, Vulkan 64/32 bits, gamemode — pour tout le monde |
| `auxinux-system.txt` | noyau `kernel-auxinuxos` |
| `hors-socle.txt` | ce qui ne doit **pas** être dans l’image (purgé, puis refusé par `check-rootfs.sh`) |

L’image est un **socle** : système, KDE Plasma et ses outils de base, codecs,
pare-feu et couche Windows. Aucune application d’usage (navigateur,
bureautique, lecteur, jeux, outils de vie privée) n’est imposée : l’assistant
de premier démarrage du centre de contrôle les propose, en Flatpak de
préférence, et se relance depuis Réglages. Le dépôt Brave est livré
**désactivé** ; l’assistant ne l’active que si Brave est choisi.

## Sources et caches

Le rootfs est bootstrappé depuis **le miroir Debian d’AuxiNux**
(`https://dep.auxinux.ca/DEBIAN`), un vrai miroir signé par les clés de
l’archive Debian — donc vérifié par `debian-archive-keyring` comme
`deb.debian.org`. C’est aussi la source vers laquelle pointe le système
installé : bootstrapper ailleurs, c’était construire l’image avec des paquets
qui ne sont pas ceux dont la machine recevra ses mises à jour.

Les ressources graphiques sont versionnées. Les caches
et ISO ne le sont pas. Les empreintes des téléchargements sont définies dans
`scripts/configure-apt-sources.sh` ; `rustup-init` est épinglé à la première
construction dans `rustup-init.sha256`, à côté du cache COSMIC.

Avant la compression du squashfs, `scripts/check-rootfs.sh` vérifie que chaque
fonction annoncée est réellement présente dans l’image et **interrompt la
construction** sinon.

Avant une reconstruction, lire les [limites du cache et du binaire du centre](../docs/limitations.md).
