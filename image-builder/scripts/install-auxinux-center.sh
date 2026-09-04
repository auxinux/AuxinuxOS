#!/usr/bin/env bash
# Compile (ou recupere) AuxiNux OS Center et l'installe dans le rootfs de l'ISO.
#
# Variables:
#   AUXINUX_CENTER_BIN  chemin d'un binaire deja compile (saute la compilation)
#
# Le binaire est natif de l'hote de build (Debian 13 amd64 == cible), donc on
# peut le compiler sur l'hote et le copier tel quel dans le rootfs.
set -euo pipefail

ROOTFS="${1:?usage: install-auxinux-center.sh ROOTFS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PKG_DIR="${PROJECT_DIR}/packages/auxinux-center"

BIN="${AUXINUX_CENTER_BIN:-${PKG_DIR}/target/release/auxinux-center}"

if [[ ! -x "${BIN}" ]]; then
  echo "==> Compilation d'AuxiNux OS Center"
  "${PKG_DIR}/build.sh"
fi

if [[ ! -x "${BIN}" ]]; then
  echo "binaire auxinux-center introuvable: ${BIN}" >&2
  echo "compilez-le sur l'hote (packages/auxinux-center/build.sh) ou definissez AUXINUX_CENTER_BIN" >&2
  exit 70
fi

echo "==> Installation d'AuxiNux OS Center dans le rootfs"
sudo install -D -m 0755 "${BIN}" "${ROOTFS}/usr/bin/auxinux-center"
sudo install -D -m 0644 "${PKG_DIR}/data/ca.auxinux.Center.desktop" \
  "${ROOTFS}/usr/share/applications/ca.auxinux.Center.desktop"
sudo install -D -m 0644 "${PKG_DIR}/data/ca.auxinux.Center.metainfo.xml" \
  "${ROOTFS}/usr/share/metainfo/ca.auxinux.Center.metainfo.xml"

# Depuis la 0.2, le Center est un binaire libcosmic: il n'a plus AUCUNE
# dependance QML/Kirigami/KF6 a installer dans l'image. Ses dependances
# d'execution (wayland, libxkbcommon, mesa) sont deja tirees par COSMIC.
#
# Nettoyage des reliquats: sur un rootfs reutilise (--reuse-rootfs), les
# modules QML installes par les versions precedentes resteraient dans l'image
# sans que rien ne les utilise.
sudo chroot "${ROOTFS}" apt-get autoremove -y --purge \
  qml6-module-org-kde-kirigami 2>/dev/null || true
