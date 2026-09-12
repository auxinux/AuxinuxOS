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

# --- Ecran de connexion SDDM -----------------------------------------------
#
# Le theme debian-breeze pointe son fond d'ecran et son logo vers
# /usr/share/desktop-base/, or le paquet desktop-base N'EST PAS installe: sans
# cette surcharge, l'ecran de connexion s'affiche sur un aplat de couleur, sans
# logo. SDDM lit theme.conf.user APRES theme.conf, ce qui evite de modifier un
# fichier appartenant a un paquet Debian (une mise a jour de plasma-desktop
# l'ecraserait).
SDDM_THEME_DIR="${ROOTFS}/usr/share/sddm/themes/debian-breeze"
if [[ -d "${SDDM_THEME_DIR}" ]]; then
  sudo install -m 0644 \
    "${ASSET_DIR}/BanniereAuxiNux-Youtube.png" \
    "${ROOTFS}/usr/share/sddm/themes/debian-breeze/auxinux-background.png"
  sudo install -m 0644 \
    "${ASSET_DIR}/logo-AuxiNux-source.png" \
    "${ROOTFS}/usr/share/sddm/themes/debian-breeze/auxinux-logo.png"
  sudo tee "${SDDM_THEME_DIR}/theme.conf.user" >/dev/null <<'SDDM_EOF'
[General]
type=image
background=/usr/share/sddm/themes/debian-breeze/auxinux-background.png
logo=/usr/share/sddm/themes/debian-breeze/auxinux-logo.png
showlogo=shown
showClock=true
SDDM_EOF
else
  echo "AVERTISSEMENT: theme SDDM debian-breeze absent, branding de l'ecran de connexion ignore." >&2
fi

# --- Fond d'ecran par defaut du bureau -------------------------------------
#
# Purement cosmetique et volontairement minimal: on n'ecrit QUE la cle du fond
# d'ecran de la vue bureau. kconfig fusionne cle par cle, donc la disposition
# des panneaux reste celle de Plasma. Au pire, si la numerotation des
# containments change en amont, l'utilisateur voit le fond d'ecran de Breeze --
# pas un bureau casse.
sudo install -D -m 0644 /dev/stdin \
  "${ROOTFS}/etc/xdg/plasma-org.kde.plasma.desktop-appletsrc" <<'PLASMA_EOF'
[Containments][1][Wallpaper][org.kde.image][General]
Image=/usr/share/backgrounds/auxinuxos/default.png
PreviewImage=/usr/share/backgrounds/auxinuxos/default.png
PLASMA_EOF
