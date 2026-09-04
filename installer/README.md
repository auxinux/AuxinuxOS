# Installateur Edition-Normal

Installateur graphique et backend pour l'installation classique d'AuxiNuxOS.

## Beta 0.1

La beta conventionnelle utilise Calamares comme base d'installation classique.
Le live expose l'icone `Install AuxiNuxOS`.

L'installation finale ne doit pas conserver cette icone. Le script
`post-install-cleanup.sh` supprime les artefacts live dans la cible installee.

## Configuration Calamares

La configuration est versionnee dans les overlays et embarquee dans l'image:

- `image-builder/overlays/etc/calamares/settings.conf` — sequence de modules;
- `image-builder/overlays/etc/calamares/modules/shellprocess-cleanup.conf` —
  branche `post-install-cleanup.sh` en fin de sequence `exec`;
- `image-builder/overlays/etc/calamares/branding/auxinuxos/` — branding + slides.

`post-install-cleanup.sh` est installe dans l'image a
`/usr/lib/auxinux/post-install-cleanup.sh` (voir `install-auxi-cli.sh`) et
retire: icone d'installation, `sudoers.d/90-auxinux-live` (NOPASSWD),
autologin COSMIC/greetd live et compte live `auxinux`.
Les limites du nettoyage sont documentées dans `docs/limitations.md`.

Le nom de compte `auxinux` est réservé au live et interdit par la
configuration des utilisateurs de Calamares. A valider en VM avant
toute ISO publique.

## Rollback système

L'installation cible **BTRFS** avec des sous-volumes plats, ce qui rend le
rollback possible. La configuration est versionnée dans les overlays :

- `modules/partition.conf` — BTRFS par défaut et les sept sous-volumes ;
- `modules/mount.conf` — options de montage **pendant** l'installation ;
- `modules/fstab.conf` — options écrites dans le `/etc/fstab` **installé** ;
- `modules/shellprocess-snapshots.conf` — branche `setup-btrfs-rollback.sh`.

`setup-btrfs-rollback.sh` est installé à
`/usr/lib/auxinux/setup-btrfs-rollback.sh` (voir `install-auxi-cli.sh`) et
configure snapper, `grub-btrfs` et l'instantané d'installation initiale.

Il doit rester le **dernier** job de la séquence `exec`, après
`shellprocess@cleanup` : le nettoyage purge live-boot puis régénère
l'initramfs, et ce script termine par `update-grub`. Dans l'ordre inverse, les
entrées de restauration du menu GRUB pointeraient sur un initrd encore
contaminé par les hooks live-boot.

Le script est non bloquant par conception : une racine ext4 choisie en
partitionnement manuel le fait sortir en code 0 sans configurer le rollback.
Contrairement à `post-install-cleanup.sh`, il ne masque aucune erreur : chaque
échec est tracé sur stderr et résumé en fin d'exécution.

Voir [docs/rollback.md](../docs/rollback.md).
