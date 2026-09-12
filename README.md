# AuxiNuxOS

Distribution Linux de bureau basée sur Debian 13 (Trixie), avec le bureau
**KDE Plasma** sous Wayland, un installateur maison et le noyau
`kernel-auxinuxos` fourni par les dépôts AuxiNux. Trois usages assumés :
bureautique, multimédia, jeu.

Dépôt : https://git.auxinux.ca/Auxinux/AuxinuxOS.git

## État

**0.2.0 en développement.** La 0.1-BETA publiée utilisait le bureau COSMIC et
Calamares ; les deux sont abandonnés en 0.2.0 (décision du 2026-09-12). La
migration vers Plasma et l'installateur maison est en cours, aucune ISO 0.2.0
n'a encore été construite. Voir [les limites connues](docs/limitations.md).

## Composants

- `image-builder/` : construction de l’ISO, listes de paquets, ressources et configuration.
- `installer/` : nettoyage du système après installation et configuration du rollback.
- `packages/auxi-cli/` : gestion des applications et politique APT.
- `packages/auxinux-center/` : centre de contrôle Rust et libcosmic.
- `packages/boot-sentinel/` : protection au démarrage, console de secours et
  restauration automatique.
- `packages/auxinux-profile/` : profils d'usage bureautique / multimédia / jeu.
- `packages/welcome/` : accueil live et lanceur de l'installateur.
- `packages/windows-support/` : assistant `.exe` et installation de la couche Windows/jeux.
- `docs/` : documentation technique.
- `tests/` : procédure de validation.

Les applications Flatpak sont privilégiées ; les paquets DEB restent
accessibles. Les langues visées sont le français et l’anglais canadiens.

Si le bureau ne démarre pas deux fois de suite, la machine bascule sur une
console de secours et propose la restauration ; au troisième échec, elle
restaure sans rien demander. Voir
[la protection au démarrage](docs/protection-demarrage.md).

L’installation se fait sur **BTRFS** avec instantanés : un instantané est créé
automatiquement avant chaque transaction DEB, et le système peut être restauré
depuis le menu GRUB même quand il ne démarre plus. Voir
[le rollback système](docs/rollback.md).

## Construction

La construction nécessite un hôte **Debian 13 amd64**, les outils Linux de
création d’images et les dépendances du centre de contrôle. Elle ne
s’exécute pas directement sous macOS.

Consulter [les instructions de construction](image-builder/README.md).
Les ISO et les caches de compilation sont exclus de Git ; les sources,
`Cargo.lock`, les clés publiques et les ressources graphiques sont conservés.

## Licence

Le code d’AuxiNuxOS est sous **GPL-3.0-or-later** (texte intégral dans
[`LICENSE`](LICENSE)).

L’**image ISO** n’est pas sous GPL : c’est une agrégation de logiciels tiers
qui conservent chacun leur licence, y compris les composants `non-free` et
`non-free-firmware` délibérément activés pour la prise en charge du matériel.
Voir [`COPYING.md`](COPYING.md) avant toute redistribution.
