# AuxiNux OS Center

Magasin d'applications et centre système maison d'AuxiNux OS EN.

- **Backend** : Rust (modules `apps`, `sources`, `system`), délègue à `flatpak`,
  à la CLI `auxi` (politique APT maison) et à `apt-cache`.
- **UI** : Kirigami (QML), interface Qt6/Kirigami sous COSMIC.
- **Pont** : CXX-Qt — objet singleton QML `Backend` (URI `ca.auxinux.Center`).

## Sections

- **Applications** : recherche, install, désinstall, mise à jour. Source par
  défaut **Flathub** ; bascule possible sur **AuxiNux (DEB)**. Si une app n'est
  pas sur Flathub mais existe en DEB, elle est affichée avec la source DEB.
- **Sources** : activer/désactiver les dépôts APT, ajouter un dépôt (presets
  **Docker**, **VS Code**, ou personnalisé deb822), gérer les remotes Flatpak.
- **Configuration** : politique APT (`auxi set apt=…`), raccourcis réglages COSMIC.
- **Système** : infos de base et vue avancée (GPU, session, uptime, disques…).

## Compilation (sur l'hôte de build Debian 13)

Prérequis : toolchain Rust, Qt6 + KF6 dev (`qt6-base-dev qt6-declarative-dev
cmake build-essential`), Kirigami runtime, `pkg-config libssl-dev`.

```bash
./build.sh
# Test du backend SANS Qt (utile pour valider la logique):
./target/release/auxinux-center --cli search vlc
./target/release/auxinux-center --cli sources
./target/release/auxinux-center --cli sysinfo advanced
```

## Intégration ISO

`image-builder/scripts/install-auxinux-center.sh` compile (ou prend
`AUXINUX_CENTER_BIN`) puis installe le binaire, le `.desktop` et le metainfo
dans le rootfs. Appelé par `build-image.sh`. L'app **reste** sur le système
installé (ce n'est pas un artefact live).

## À vérifier en premier sur debiandev

1. `cargo build` — le pont CXX-Qt est la partie à confirmer contre la version
   exacte de `cxx-qt` installée (API 0.7 visée).
2. Lancement UI : `auxinux-center`.
3. Droits : les opérations DEB et l'écriture sous `/etc/apt` passent par
   `pkexec` (agent polkit de la session).

## Limites connues (v1)

- Opérations install/maj **synchrones** (l'UI se fige pendant l'action) →
  passer en tâche asynchrone (signal `taskFinished`) en v2.
- Fusion Flatpak/DEB **heuristique** (par nom/app-id) → AppStream unifié en v2
  pour des fiches riches et une correspondance fiable.
- Correspondance Flatpak/DEB et confirmations APT : voir `../../docs/limitations.md`.
