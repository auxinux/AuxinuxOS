#!/usr/bin/env bash
set -euo pipefail

# Identite visuelle: logos, icone du systeme, fond d'ecran et ressources du
# branding Calamares.
#
# Le retour a Plasma (2026-09-12) rend a nouveau utile ce que ce script avait
# perdu sous COSMIC: l'ecran de connexion et le fond d'ecran par defaut.
# /etc/sddm.conf.d et kscreenlockerrc, eux, sont des overlays statiques.

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

# Fond d'ecran a un emplacement standard, selectionnable depuis les reglages de
# Plasma.
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

# Diaporama de l'installateur graphique, GENERE depuis installer/diapositives/
# -- la meme source que l'installateur console, dans la langue choisie.
if [[ -d "${ROOTFS}/etc/calamares/branding/auxinuxos" ]]; then
  python3 "${SCRIPT_DIR}/generate-slideshow.py" "${PROJECT_DIR}/../installer/diapositives" /tmp/auxinux-show.qml
  sudo install -m 0644 /tmp/auxinux-show.qml "${ROOTFS}/etc/calamares/branding/auxinuxos/show.qml"
  rm -f /tmp/auxinux-show.qml
fi

# --- Ecran de connexion SDDM -----------------------------------------------
#
# Depuis 2026-10-23, le theme « auxinux » (fond, couleurs, textes en
# francais) est LIVRE par auxinuxos-release (/usr/share/sddm/themes/auxinux):
# il suit les mises a jour. L'ancien habillage de debian-breeze se faisait ici
# (theme.conf.user), mais ce theme depend de plasma-workspace, retire de
# l'image.

# --- Fond d'ecran par defaut du bureau -------------------------------------
#
# Il etait ecrit ici dans /etc/xdg/plasma-org.kde.plasma.desktop-appletsrc,
# sous le numero de containment suppose de la vue bureau. Constate en VM le
# 2026-10-02: Plasma ne l'appliquait PAS. Il est desormais pose par le script
# de mise a jour de Plasma auxinux-fond-ecran.js (overlays/usr/share/plasma/
# shells/org.kde.plasma.desktop/contents/updates/), qui s'execute pour chaque
# nouvel utilisateur. L'ancien fichier est retire d'un rootfs reutilise: il ne
# servait a rien et faisait croire le contraire.
sudo rm -f "${ROOTFS}/etc/xdg/plasma-org.kde.plasma.desktop-appletsrc"
