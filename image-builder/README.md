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

La sortie est `image-builder/output/auxinuxos-0.2.0-amd64.iso`.
`--force` supprime le répertoire de construction du profil avant de repartir.
`--reuse-rootfs` réutilise un rootfs existant ; ces options sont incompatibles.

## Listes de paquets

Le contenu de l’image est décrit par `package-lists/`, et par rien d’autre :

| Liste | Contenu |
|---|---|
| `base.txt`, `firmware.txt` | socle système et micrologiciels |
| `desktop-plasma.txt` | KDE Plasma, SDDM, pilotes graphiques, audio |
| `i18n-canada.txt` | dictionnaires fr/en-CA |
| `live-installer.txt` | installateur du médium live |
| `rollback.txt`, `performance.txt` | snapper/grub-btrfs, zram |
| `apps-socle.txt` | navigateur et outils de vie privée |
| `layer-bureautique.txt`, `layer-multimedia.txt`, `layer-gaming.txt` | les trois usages |
| `auxinux-system.txt` | noyau `kernel-auxinuxos` |

L’ISO embarque les trois couches : voir
[les profils d’usage](../docs/profils-usage.md).

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
