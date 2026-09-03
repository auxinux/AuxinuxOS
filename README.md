# AuxiNuxOS — Édition normale

Distribution Linux conventionnelle basée sur Debian 13 (Trixie), avec le
bureau COSMIC, une installation sur disque via Calamares et le noyau
`kernel-auxinuxos` fourni par les dépôts AuxiNux.

Dépôt : https://git.auxinux.ca/Auxinux/AuxinuxOS.git

## État

Version **0.1-BETA**. Une ISO a été construite et un démarrage live a été
rapporté. La validation complète de l’installation graphique, du redémarrage
sans le média live et de l’ouverture de session reste à effectuer.
Voir [les limites connues](docs/limitations.md).

## Composants

- `image-builder/` : construction de l’ISO, listes de paquets, ressources et configuration.
- `installer/` : nettoyage du système après installation.
- `packages/auxi-cli/` : gestion des applications et politique APT.
- `packages/auxinux-center/` : centre d’applications Rust, Qt6 et Kirigami.
- `packages/welcome/` : accueil live et lanceur Calamares.
- `packages/windows-support/` : assistant Wine.
- `docs/` : documentation technique.
- `tests/` : procédure de validation.

Les applications Flatpak sont privilégiées ; les paquets DEB restent
accessibles. Les langues visées sont le français et l’anglais canadiens.

## Construction

La construction nécessite un hôte **Debian 13 amd64**, les outils Linux de
création d’images et les dépendances du centre d’applications. Elle ne
s’exécute pas directement sous macOS.

Consulter [les instructions de construction](image-builder/README.md).
Les ISO et les caches de compilation sont exclus de Git ; les sources,
`Cargo.lock`, les clés publiques et les ressources graphiques sont conservés.

## Licence

Voir le fichier `LICENSE` à la racine du dépôt. La licence globale reste à
finaliser ; le manifeste du centre d’applications déclare GPL-3.0-or-later.
