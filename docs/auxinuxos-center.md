# AuxiNux OS Center — conception

Centre de contrôle d'AuxiNuxOS, en Rust + libcosmic, intégré à l'ISO d'AuxiNuxOS.

## Objectifs

1. Recherche/install/désinstall/mise à jour d'applications, **Flathub par
   défaut**, **AuxiNux DEB** en alternative ou en repli.
2. **Mise à jour du système d'exploitation**, avec instantané préalable.
3. **Santé du système** : un diagnostic lisible, assorti de conseils.
4. **Restauration** : revenir à un état antérieur depuis un instantané BTRFS.
5. Gestion des **sources** : activer/désactiver les dépôts AuxiNux et autres,
   ajouter des dépôts (Docker, etc.), gérer les remotes Flatpak.
6. **Configuration** : politique APT maison (`auxi`), accès aux réglages du bureau.

## Stack (0.2)

| Couche | Choix |
|--------|-------|
| UI | **libcosmic** (Iced) — voir la note ci-dessous depuis le retour à Plasma |
| Asynchrone | `tokio` + `spawn_blocking`, isolé dans `task.rs` |
| Logique | Rust : `apps`, `sources`, `system`, `health`, `recovery`, `updates` |
| Types partagés | `model.rs` — un identifiant **par source** |
| Back-ends | `flatpak`, CLI `auxi`, `apt-cache`, `snapper`, `auxinux-profile` ; privilèges via `pkexec`/polkit |
| Infos système | crate `sysinfo` + `lspci` |

### Note 0.2.0 : libcosmic sur un bureau Plasma

Le bureau est KDE Plasma depuis le 2026-09-12. Le Center reste en libcosmic pour
cette version : l'interface existe, elle fonctionne sous n'importe quel
compositeur Wayland (libcosmic est iced + winit + wgpu, pas COSMIC), et la
réécrire coûterait 1 575 lignes d'interface contre **trois lignes** à changer
pour la garder. Le prix payé est visuel : l'application ne suit pas le thème
Breeze.

Le backend étant séparé par la feature `gui`, une interface Kirigami/QML pourra
s'y brancher sans toucher à la logique — en passant par l'interface
`auxinux-center --cli` (JSON) plutôt que par CXX-Qt, qui était le point
douloureux de la 0.1.

Kirigami/CXX-Qt a été abandonné en 0.2 : une fenêtre Qt/KDE au milieu d'un
bureau en Iced ne s'intègre pas, et la pile KF6 pesait dans l'ISO pour une
seule application. Go a été évalué et écarté — les défauts de la 0.1 étaient
architecturaux, pas liés au langage.

## Séparation backend / interface

L'interface est derrière la feature Cargo `gui`, active par défaut :

```bash
cargo check --no-default-features   # logique seule, aucune dépendance graphique
cargo build --release               # application complète
```

Sans cette séparation, la moindre vérification de la logique exigerait
Wayland, libxkbcommon et une pile graphique complète — impossible en
intégration continue et sur la plupart des machines de développement.

## Logique de priorité de source

- Recherche Flathub (prioritaire) puis `apt-cache search`.
- Si une app Flathub correspond à un paquet DEB (heuristique nom/app-id) → DEB
  ajouté comme **source alternative**, défaut = Flathub.
- App absente de Flathub mais présente en DEB → affichée, source = AuxiNux DEB.

La fusion conserve désormais un **identifiant par source** (`AppEntry.deb_name`).
En 0.1, une fiche Flathub basculée sur DEB transmettait l'app-id Flatpak
(`org.videolan.VLC`) à apt-get au lieu du nom de paquet (`vlc`) : l'installation
échouait, ou visait un paquet homonyme. L'interface affiche maintenant
l'identifiant réellement visé sous chaque fiche.

## Sections

| Section | Rôle |
|---|---|
| Applications | recherche, installation, désinstallation, bascule Flathub/DEB |
| Mises à jour | applications et système, via `auxi upgrade` (donc avec instantané) |
| Santé | disque, mémoire, services en échec, mises à jour, restauration, démarrage |
| Restauration | instantanés BTRFS : lister, créer, revenir en arrière |
| Sources | dépôts APT, dépôts connus, remotes Flatpak |
| Réglages | politique APT, **profil d'usage** (bureautique / multimédia / jeu) et accès aux réglages du bureau |

La section Santé donne un **conseil en français courant** pour chaque anomalie.
Afficher « swap : 94 % » sans dire quoi faire ne sert qu'à ceux qui savaient
déjà.

## Asynchrone

Toutes les opérations passent par `task::background()`, qui exécute le travail
bloquant sur un fil séparé et renvoie le résultat sous forme de message. En 0.1,
chaque installation figeait la fenêtre — parfois plusieurs minutes, sans qu'on
puisse distinguer une attente d'un plantage.

Tout le contact avec l'API de tâche de libcosmic est concentré dans cette seule
fonction : si l'API bouge d'une version à l'autre, une fonction est à corriger,
pas six pages.

## Sécurité

- Aucune écriture directe sous `/etc` par l'app : tout passe par `pkexec`
  (agent polkit). Les presets génèrent un script root unique (1 invite).
- Clés GPG installées sous `/etc/apt/keyrings/*.asc` avec `Signed-By` (deb822),
  jamais `apt-key`.
- Validation des noms de fichiers (pas de `/` ni `..`).

## Intégration ISO

- `packages/auxinux-center/` : code + données.
- `image-builder/scripts/install-auxinux-center.sh` : build + install rootfs.
- Câblé dans `image-builder/build-image.sh` après la config Flatpak.
- L'app **persiste** sur le système installé (pas un artefact live).

## Feuille de route

Livré en 0.2 : libcosmic, opérations asynchrones, identifiant par source,
sections Mises à jour / Santé / Restauration.

Reste à faire :

- **AppStream unifié** : icônes, captures d'écran et descriptions riches dans
  les listes, et une correspondance Flatpak/DEB fondée sur les métadonnées
  plutôt que sur l'heuristique de nom actuelle.
- **Sortie en direct** des opérations longues : aujourd'hui seul le résultat
  final s'affiche, l'utilisateur ne voit pas la progression d'un gros
  téléchargement.
- **Barre de progression** réelle, adossée à cette sortie.
- Sections additionnelles possibles : pilotes, assistant Wine, sauvegardes.
