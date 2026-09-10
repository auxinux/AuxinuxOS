#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?usage: install-auxi-cli.sh ROOTFS}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sudo install -D -m 0755 "${PROJECT_DIR}/packages/auxi-cli/auxi" "${ROOTFS}/usr/bin/auxi"
sudo install -D -m 0755 "${PROJECT_DIR}/packages/auxi-cli/apt-wrapper" "${ROOTFS}/usr/lib/auxinux/wrappers/apt-wrapper"
sudo install -D -m 0755 "${PROJECT_DIR}/packages/windows-support/auxinux-windows-wizard" "${ROOTFS}/usr/bin/auxinux-windows-wizard"
sudo install -D -m 0755 "${PROJECT_DIR}/packages/windows-support/auxinux-windows-setup" "${ROOTFS}/usr/bin/auxinux-windows-setup"
sudo install -D -m 0755 "${PROJECT_DIR}/packages/welcome/auxinux-welcome" "${ROOTFS}/usr/bin/auxinux-welcome"
sudo install -D -m 0755 "${PROJECT_DIR}/packages/welcome/auxinux-install-launcher" "${ROOTFS}/usr/lib/auxinux/auxinux-install-launcher"

# Hook d'instantane branche sur dpkg (voir etc/apt/apt.conf.d/80auxinux-snapshot).
sudo install -D -m 0755 "${PROJECT_DIR}/packages/auxi-cli/apt-snapshot-hook" "${ROOTFS}/usr/lib/auxinux/apt-snapshot-hook"

# Assistant privilegie du centre de controle + son action polkit.
sudo install -D -m 0755 "${PROJECT_DIR}/packages/auxinux-center/helper/auxinux-source-helper" "${ROOTFS}/usr/libexec/auxinux/auxinux-source-helper"
sudo install -D -m 0644 "${PROJECT_DIR}/packages/auxinux-center/helper/ca.auxinux.center.policy" "${ROOTFS}/usr/share/polkit-1/actions/ca.auxinux.center.policy"

# Script de nettoyage post-installation, appele par le module Calamares
# shellprocess@cleanup (voir image-builder/overlays/etc/calamares/).
sudo install -D -m 0755 "${PROJECT_DIR}/installer/post-install-cleanup.sh" "${ROOTFS}/usr/lib/auxinux/post-install-cleanup.sh"

# Configuration du rollback systeme, appelee par shellprocess@snapshots en
# toute fin de sequence Calamares.
sudo install -D -m 0755 "${PROJECT_DIR}/installer/setup-btrfs-rollback.sh" "${ROOTFS}/usr/lib/auxinux/setup-btrfs-rollback.sh"

# Verification finale d'amorcabilite (shellprocess@verifyboot), dernier job
# avant le demontage de la cible.
sudo install -D -m 0755 "${PROJECT_DIR}/installer/verify-installed-boot.sh" "${ROOTFS}/usr/lib/auxinux/verify-installed-boot.sh"

sudo install -d -m 0755 "${ROOTFS}/usr/lib/auxinux/apt-real"

# On detourne les vrais binaires APT avec dpkg-divert (et non mv + symlink):
# la diversion est enregistree dans la base dpkg et survit aux mises a jour du
# paquet apt, qui sinon restaurerait /usr/bin/apt-get et casserait la politique.
#
# apt-cache N'EST PLUS detourne. C'est une commande de LECTURE SEULE: la
# masquer ne protegeait rien, cassait la complétion et les scripts tiers, et
# obligeait le centre de controle a contourner sa propre politique pour faire
# une simple recherche.
for tool in apt apt-get; do
  if ! sudo chroot "${ROOTFS}" dpkg-divert --list "/usr/bin/${tool}" \
      | grep -q "/usr/lib/auxinux/apt-real/${tool}"; then
    sudo chroot "${ROOTFS}" dpkg-divert --add --rename \
      --divert "/usr/lib/auxinux/apt-real/${tool}" "/usr/bin/${tool}"
  fi
  sudo ln -sf /usr/lib/auxinux/wrappers/apt-wrapper "${ROOTFS}/usr/bin/${tool}"
done

# Rootfs reutilise: annuler une diversion d'apt-cache posee par une version
# precedente, sans quoi elle survivrait a la mise a jour du script.
if sudo chroot "${ROOTFS}" dpkg-divert --list /usr/bin/apt-cache \
    | grep -q "/usr/lib/auxinux/apt-real/apt-cache"; then
  sudo rm -f "${ROOTFS}/usr/bin/apt-cache"
  sudo chroot "${ROOTFS}" dpkg-divert --remove --rename /usr/bin/apt-cache
fi
