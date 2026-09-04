#!/usr/bin/env bash
set -euo pipefail

# Identite visuelle: logos, icone du systeme, fond d'ecran et ressources du
# branding Calamares.
#
# TOUTE la configuration Plasma a ete retiree de ce script (fond d'ecran
# Plasma, themes look-and-feel Breeze, /etc/sddm.conf.d, kscreenlockerrc).
# Aucun de ces composants n'est installe depuis le passage a COSMIC: ces
# fichiers n'etaient lus par rien, tout en donnant l'impression que le fond
# d'ecran et l'ecran de connexion etaient configures.

ROOTFS="${1:?usage: configure-branding.sh ROOTFS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSET_DIR="${PROJECT_DIR}/assets"

sudo install -d -m 0755 \
  "${ROOTFS}/usr/share/auxinux/branding" \
  "${ROOTFS}/usr/share/backgrounds/auxinuxos" \
  "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"

sudo install -m 0644 \
  "${ASSET_DIR}/logo-AuxiNux-source.png" \
  "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux.png"
sudo install -m 0644 \
  "${ASSET_DIR}/logo-AuxiNux-square.png" \
  "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux-square.png"
sudo install -m 0644 \
  "${ASSET_DIR}/BanniereAuxiNux-Youtube.png" \
  "${ROOTFS}/usr/share/auxinux/branding/banner-AuxiNuxOS.png"

# Fond d'ecran a un emplacement standard, ou il est selectionnable depuis les
# reglages de COSMIC. Le definir PAR DEFAUT demande un fichier de
# configuration cosmic-bg, non ecrit ici tant qu'il n'a pas ete verifie sur une
# session reelle (voir docs/limitations.md).
sudo install -m 0644 \
  "${ASSET_DIR}/BanniereAuxiNux-Youtube.png" \
  "${ROOTFS}/usr/share/backgrounds/auxinuxos/default.png"

sudo cp "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux-square.png" \
  "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/auxinuxos.png"

# Logo pour le branding Calamares (chemins relatifs au dossier de branding).
if [[ -d "${ROOTFS}/etc/calamares/branding/auxinuxos" ]]; then
  sudo cp "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux.png" \
    "${ROOTFS}/etc/calamares/branding/auxinuxos/logo-AuxiNux.png"
  sudo cp "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux-square.png" \
    "${ROOTFS}/etc/calamares/branding/auxinuxos/logo-AuxiNux-square.png"
  sudo cp "${ROOTFS}/usr/share/auxinux/branding/banner-AuxiNuxOS.png" \
    "${ROOTFS}/etc/calamares/branding/auxinuxos/banner-AuxiNuxOS.png"
fi
