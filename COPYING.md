# Portée de la licence

## Le code d'AuxiNuxOS

Tout ce que ce dépôt contient en propre est sous **GPL-3.0-or-later**, dont le
texte intégral est dans [`LICENSE`](LICENSE) :

- `packages/auxi-cli/` — la commande `auxi` et le wrapper APT ;
- `packages/auxinux-center/` — le centre de contrôle (déjà déclaré
  `GPL-3.0-or-later` dans son `Cargo.toml` et son metainfo) ;
- `packages/welcome/`, `packages/windows-support/` — les assistants ;
- `image-builder/`, `installer/` — les scripts de construction et
  d'installation, les overlays et les listes de paquets ;
- `docs/`, `tests/`.

## L'image ISO n'est PAS sous GPL

C'est la distinction qui compte, et l'oublier reviendrait à prétendre
relicencier le travail des autres — ce qui n'est pas possible.

L'ISO produite est une **agrégation** de milliers de logiciels tiers. Chacun
conserve sa propre licence :

- la base **Debian 13** et ses paquets, sous leurs licences respectives ;
- **COSMIC** (`pop-os/cosmic-epoch`), sous ses propres termes ;
- les composants **`non-free` et `non-free-firmware`**, délibérément activés :
  `firmware-linux-nonfree`, `firmware-iwlwifi`, `firmware-realtek`,
  `firmware-atheros`, `firmware-brcm80211`, `firmware-misc-nonfree`. Sans eux,
  de nombreuses cartes WiFi, Bluetooth et GPU ne sont pas détectées — c'est un
  choix d'utilisabilité assumé, pas un oubli ;
- les applications tierces embarquées ou proposées (Brave, LibreOffice,
  Thunderbird, les Flatpak installés à la demande).

Redistribuer l'ISO suppose donc de respecter **aussi** ces licences-là, pas
seulement la GPL-3.0-or-later.

## Ce que la GPL-3.0-or-later implique concrètement

| Vous pouvez | À condition de |
|---|---|
| Utiliser AuxiNuxOS pour n'importe quel usage, y compris commercial | — |
| Étudier et modifier le code | — |
| Redistribuer, tel quel ou modifié | Fournir le code source correspondant |
| | Conserver la licence GPL-3.0-or-later sur les dérivés (*copyleft*) |
| | Conserver les mentions de droit d'auteur |
| | Documenter vos modifications |

« or-later » signifie qu'un utilisateur peut choisir d'appliquer une version
ultérieure de la GPL s'il en publie une.

La GPL fournit le logiciel **sans aucune garantie**. C'est aussi ce que
rappelle [`docs/limitations.md`](docs/limitations.md), de manière beaucoup plus
concrète.

## Marques

Le nom « AuxiNux », « AuxiNuxOS » et les logos de `image-builder/assets/` ne
sont pas couverts par la GPL : le code est libre, l'identité de marque reste à
AuxiNux.
