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
