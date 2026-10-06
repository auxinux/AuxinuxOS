# AuxiNux OS Center

Centre de contrôle d'AuxiNux OS : applications, mises à jour, santé du système,
sources, réglages et restauration.

- **Interface** : Rust + [libcosmic](https://github.com/pop-os/libcosmic), le
  toolkit natif du bureau COSMIC.
- **Backend** : Rust (`apps`, `sources`, `system`, `health`, `recovery`,
  `updates`), délègue à `flatpak`, à la CLI `auxi` et à `apt-cache`.
- **Privilèges** : `pkexec` (agent polkit). Le Center n'écrit jamais
  directement sous `/etc`.

## Pourquoi libcosmic et pas Kirigami

La 0.1 était en Kirigami (Qt6) via CXX-Qt. Trois problèmes, tous résolus par le
changement de toolkit :

| Problème 0.1 | 0.2 |
|---|---|
| Fenêtre Qt/KDE au milieu d'un bureau COSMIC (thème, police, boutons différents) | Thème du bureau hérité, clair et sombre |
| Toute la pile KF6 + modules QML dans l'ISO | Aucune dépendance de paquet propre |
| Moteur QML chargé au lancement | Un binaire, démarrage direct |

Go a été évalué et écarté : les défauts réels de la 0.1 étaient architecturaux
(opérations synchrones, fusion Flatpak/DEB heuristique), pas liés au langage, et
Go n'offre pas de binding GUI qui s'intègre au bureau.

## Sections

- **Applications** — recherche, installation, désinstallation. **Flatpak
  (Flathub) seulement**, sauf si l'installation DEB est activée dans les
  Réglages (`auxi set deb=true`) : une liste déroulante Flatpak / DEB, sous les
  boutons de vue, bascule alors toute la page. La fiche affiche toujours
  l'identifiant réellement visé pour la source affichée.
- **Mises à jour** — applications Flatpak, paquets DEB et système, avec le
  rappel qu'un point de restauration est créé automatiquement avant.
- **Santé du système** — espace disque, mémoire, services en échec, mises à
  jour en attente, état de la restauration, temps de démarrage. Chaque anomalie
  porte un **conseil en français courant**, pas seulement un chiffre.
- **Restauration** — points de restauration BTRFS : lister, créer, revenir en
  arrière. Confirmation en deux temps, `/home` jamais touché.
- **Sources** — dépôts APT (activer/désactiver/retirer), dépôts connus
  (VS Code, Docker, Mozilla, Mullvad, Signal), remotes Flatpak.
- **Réglages** — politique APT (`auxi set apt=…`) et accès aux réglages COSMIC.

## Compilation

Prérequis sur l’hôte de build Debian 13 : toolchain Rust ≥ 1.93 (via rustup —
le `rustc` de Trixie est en 1.85 et ne suffit pas),
`build-essential pkg-config libxkbcommon-dev libwayland-dev libudev-dev
libinput-dev libssl-dev`. **Qt6 et KF6 ne sont plus nécessaires.**

```bash
./build.sh                 # tests + binaire complet
./build.sh --backend-only  # logique seule, sans dépendance graphique
```

`--backend-only` compile avec `--no-default-features` : toute la logique est
validée sur une machine dépourvue de Wayland et de libxkbcommon. C'est le mode
à utiliser en intégration continue.

```bash
./target/release/auxinux-center --cli health
./target/release/auxinux-center --cli snapshots
./target/release/auxinux-center --cli search vlc
./target/release/auxinux-center --cli sysinfo advanced
```

## Tests

```bash
cargo test --no-default-features
```

Couvre le choix d'identifiant par source (le bug DEB/Flatpak de la 0.1),
l'agrégation des gravités de santé et l'analyse du CSV de snapper.

## Intégration ISO

`image-builder/scripts/install-auxinux-center.sh` compile (ou prend
`AUXINUX_CENTER_BIN`) puis installe le binaire, le `.desktop` et le metainfo
dans le rootfs. L'application reste sur le système installé.

## Limites connues

Voir [docs/limitations.md](../../docs/limitations.md). En résumé pour la 0.2 :
la progression n'est mesurée que pour les paquets DEB (Flatpak affiche une
barre indéterminée et sa dernière ligne), et la fiche détaillée AppStream
(icônes, captures) n'est pas encore branchée sur l'interface.

## Opérations longues

Installation, désinstallation et mises à jour affichent une étape, une barre de
progression et, sur demande (« Voir le détail »), tout ce que la commande a
écrit, avec un bouton pour le copier. En cas d'échec, ce sont les dernières
lignes écrites qui s'affichent — sortie standard comprise : c'est là qu'apt
explique ses abandons.

Le Center lance `pkexec auxi --yes --progress …` : `--yes` parce qu'aucune
question ne peut recevoir de réponse sans terminal, `--progress` pour les
lignes d'avancement d'apt (voir `auxi --help`). Une seule opération à la fois :
les boutons qui en lanceraient une seconde sont inactifs pendant ce temps.
