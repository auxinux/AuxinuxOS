# Installateur AuxiNuxOS

Installateur graphique et backend pour l'installation classique d'AuxiNuxOS.

## 0.2.0 : Calamares, en attendant l'installateur maison

L'arbitrage du 2026-09-12 retient un **installateur maison** (contrôle matériel
bloquant, choix de la langue, du clavier et du fuseau, disque, type
d'installation). Il n'est **pas** dans la 0.2.0 : écrire un partitionneur et un
poseur d'amorçage depuis zéro est un chantier de plusieurs semaines, et livrer
une ISO avec un installateur à moitié écrit serait pire que livrer Calamares,
qui fonctionne.

La 0.2.0 conserve donc Calamares, reconfiguré pour Plasma. Le live expose
l'icone `Install AuxiNuxOS`.

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
retire : icone d'installation **et son autodémarrage**, lanceur Calamares,
`sudoers.d/90-auxinux-live` (NOPASSWD), autologin COSMIC/greetd live, compte
live `auxinux`, paquets live-boot **et Calamares lui-même**.

Le retrait de l'autodémarrage et de Calamares n'est pas cosmétique : sans lui,
l'installateur se relançait à chaque ouverture de session du système installé,
après avoir déplacé `/etc/fstab`.

Couvert par `tests/test-post-install.sh`. Les limites du nettoyage sont
documentées dans `docs/limitations.md`.

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

Le modèle de configuration snapper est cherché sous `/usr/share` **puis**
`/etc` : Debian 13 ne le livre qu'au premier emplacement. Ne chercher que dans
`/etc` faisait sortir le script en code 0 avec un simple avertissement, et le
rollback était absent de **chaque** système installé — sans aucun signal.
À défaut de modèle, une configuration minimale est écrite plutôt que
d'abandonner la fonction.

Le script est non bloquant par conception : une racine ext4 choisie en
partitionnement manuel le fait sortir en code 0 sans configurer le rollback.
Contrairement à `post-install-cleanup.sh`, il ne masque aucune erreur : chaque
échec est tracé sur stderr et résumé en fin d'exécution.

Voir [docs/rollback.md](../docs/rollback.md).
