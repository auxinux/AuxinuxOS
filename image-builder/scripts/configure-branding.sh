#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?usage: configure-branding.sh ROOTFS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSET_DIR="${PROJECT_DIR}/assets"
WALLPAPER_PATH="/usr/share/wallpapers/AuxiNuxOS/contents/images/default.png"

sudo install -d -m 0755 \
  "${ROOTFS}/usr/share/auxinux/branding" \
  "${ROOTFS}/usr/share/wallpapers/AuxiNuxOS/contents/images" \
  "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"

sudo install -m 0644 \
  "${ASSET_DIR}/logo-AuxiNux-source.png" \
  "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux.png"
sudo install -m 0644 \
  "${ASSET_DIR}/logo-AuxiNux-square.png" \
  "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux-square.png"
sudo install -m 0644 \
  "${ASSET_DIR}/BanniereAuxiNux-Youtube.png" \
  "${ROOTFS}${WALLPAPER_PATH}"
sudo install -m 0644 \
  "${ASSET_DIR}/BanniereAuxiNux-Youtube.png" \
  "${ROOTFS}/usr/share/auxinux/branding/banner-AuxiNuxOS.png"

sudo cp "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux-square.png" \
  "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/auxinuxos.png"

sudo tee "${ROOTFS}/usr/share/wallpapers/AuxiNuxOS/metadata.json" >/dev/null <<'EOF'
{
  "KPlugin": {
    "Id": "AuxiNuxOS",
    "Name": "AuxiNuxOS",
    "Name[fr]": "AuxiNuxOS"
  }
}
EOF

# Logo pour le branding Calamares (chemins relatifs au dossier de branding).
if [[ -d "${ROOTFS}/etc/calamares/branding/auxinuxos" ]]; then
  sudo cp "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux.png" \
    "${ROOTFS}/etc/calamares/branding/auxinuxos/logo-AuxiNux.png"
  sudo cp "${ROOTFS}/usr/share/auxinux/branding/logo-AuxiNux-square.png" \
    "${ROOTFS}/etc/calamares/branding/auxinuxos/logo-AuxiNux-square.png"
  sudo cp "${ROOTFS}/usr/share/auxinux/branding/banner-AuxiNuxOS.png" \
    "${ROOTFS}/etc/calamares/branding/auxinuxos/banner-AuxiNuxOS.png"
fi

for defaults in \
  "${ROOTFS}/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/defaults" \
  "${ROOTFS}/usr/share/plasma/look-and-feel/org.kde.breezedark.desktop/contents/defaults" \
  "${ROOTFS}/usr/share/plasma/look-and-feel/org.kde.breezetwilight.desktop/contents/defaults"
do
  if [[ -f "${defaults}" ]]; then
    if sudo grep -q "^Image=" "${defaults}"; then
      sudo sed -i "s|^Image=.*|Image=file://${WALLPAPER_PATH}|" "${defaults}"
    elif sudo grep -q "^\[Wallpaper\]" "${defaults}"; then
      sudo sed -i "/^\[Wallpaper\]/a Image=file://${WALLPAPER_PATH}" "${defaults}"
    else
      printf '\n[Wallpaper]\nImage=file://%s\n' "${WALLPAPER_PATH}" | sudo tee -a "${defaults}" >/dev/null
    fi
  fi
done

sudo install -d -m 0755 "${ROOTFS}/etc/sddm.conf.d" "${ROOTFS}/etc/xdg"
sudo tee "${ROOTFS}/etc/sddm.conf.d/20-auxinuxos-normal.conf" >/dev/null <<'EOF'
[Theme]
Current=breeze

[General]
InputMethod=
EOF

sudo tee "${ROOTFS}/etc/xdg/kscreenlockerrc" >/dev/null <<'EOF'
[Daemon]
Autolock=false
LockOnResume=false
EOF
