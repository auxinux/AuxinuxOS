# Construction de l’ISO

## Prérequis

Hôte Debian 13 amd64 avec accès sudo et réseau, espace disque suffisant pour
le rootfs, les sources COSMIC, les caches Rust et l’ISO.

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

La sortie est `image-builder/output/auxinuxos-en-0.1-beta-amd64.iso`.
`--force` supprime le répertoire de construction du profil avant de repartir.
`--reuse-rootfs` réutilise un rootfs existant ; ces options sont incompatibles.

## Sources et caches

COSMIC est compilé depuis `pop-os/cosmic-epoch`, étiquette `epoch-1.2.0`,
commit `0098ab4d8f930bf7f7738121e04a4532154852ef`.
Les paquets OBS fournissent les dépendances d’exécution ; le dépôt OBS est
ensuite retiré des sources APT de l’image.

Les clés publiques et les ressources graphiques sont versionnées. Les caches
et ISO ne le sont pas. Les empreintes des téléchargements sont définies dans
`scripts/configure-apt-sources.sh` ; `rustup-init` est épinglé à la première
construction dans `rustup-init.sha256`, à côté du cache COSMIC.

Avant la compression du squashfs, `scripts/check-rootfs.sh` vérifie que chaque
fonction annoncée est réellement présente dans l’image et **interrompt la
construction** sinon.

Avant une reconstruction, lire les [limites du cache et du binaire du centre](../docs/limitations.md).
