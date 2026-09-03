# AuxiNux OS Center — conception

Magasin d'applications et centre système maison, en Rust + Kirigami, intégré à
l'ISO Edition-Normal.

## Objectifs

1. Recherche/install/désinstall/mise à jour d'applications, **Flathub par
   défaut**, **AuxiNux DEB** en alternative ou en repli.
2. Gestion des **sources** : activer/désactiver les dépôts AuxiNux et autres,
   ajouter des dépôts (Docker, etc.), gérer les remotes Flatpak.
3. **Configuration** : politique APT maison (`auxi`), raccourcis COSMIC.
4. **Infos système** simples et avancées.

## Stack

| Couche | Choix |
|--------|-------|
| UI | Kirigami (QML), exécuté sous COSMIC |
| Pont Rust↔QML | CXX-Qt 0.7, singleton `Backend` (URI `ca.auxinux.Center`) |
| Logique | Rust : `apps`, `sources`, `system` |
| Back-ends | `flatpak`, CLI `auxi`, `apt-cache` ; privilèges via `pkexec`/polkit |
| Infos système | crate `sysinfo` + `lspci` |

## Logique de priorité de source

- Recherche Flathub (prioritaire) puis `apt-cache search`.
- Si une app Flathub correspond à un paquet DEB (heuristique nom/app-id) → DEB
  ajouté comme **source alternative**, défaut = Flathub.
- App absente de Flathub mais présente en DEB → affichée, source = AuxiNux DEB.

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

- v2 : opérations **asynchrones** (signaux CXX-Qt + threads), **AppStream**
  unifié (fiches + correspondance fiable), barre de progression, capture de
  sortie en direct.
- Sections additionnelles possibles : pilotes, Wine wizard, sauvegardes.
