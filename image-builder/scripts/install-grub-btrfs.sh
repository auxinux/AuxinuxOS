#!/usr/bin/env bash
set -euo pipefail

# Installation de grub-btrfs depuis les sources officielles.
#
# POURQUOI DEPUIS LES SOURCES: `grub-btrfs` n'existe PAS dans Debian 13. Les
# douze autres paquets de la pile rollback y sont, celui-la non -- verifie avec
# `apt-cache policy` sur l'hote de build, apres qu'une verification via
# packages.debian.org ait donne un faux positif.
#
# POURQUOI NE PAS S'EN PASSER: grub-btrfs est ce qui genere le sous-menu GRUB
# permettant de demarrer sur un instantane. Sans lui, `auxi rollback` ne
# fonctionne que depuis un systeme qui demarre encore -- c'est-a-dire pas dans
# le seul cas ou l'on en a vraiment besoin, et c'etait l'argument decisif
# retenu contre LVM. Voir docs/rollback.md.
#
# Aucune compilation: le projet est du shell, une unite systemd et un script
# /etc/grub.d. Meme motif de vendorisation que COSMIC (clone a un tag, puis
# verification du commit epingle).

ROOTFS="${1:?usage: install-grub-btrfs.sh ROOTFS [CACHE_DIR]}"
CACHE_DIR="${2:-}"

GRUB_BTRFS_TAG="v4.14"
GRUB_BTRFS_COMMIT="2fcfbe967637166b88dadd49c834807243a941bf"
GRUB_BTRFS_REPO="https://github.com/Antynea/grub-btrfs.git"

if [[ -n "${CACHE_DIR}" ]]; then
  SOURCE_DIR="${CACHE_DIR}/grub-btrfs-${GRUB_BTRFS_TAG}"
  mkdir -p "${CACHE_DIR}"
  CLEANUP=0
else
  SOURCE_DIR="$(mktemp -d)/grub-btrfs"
  CLEANUP=1
fi

cleanup() {
  if [[ "${CLEANUP}" -eq 1 ]]; then
    rm -rf "$(dirname "${SOURCE_DIR}")"
  fi
}
trap cleanup EXIT

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  echo "==> Clonage de grub-btrfs ${GRUB_BTRFS_TAG}"
  git clone --branch "${GRUB_BTRFS_TAG}" --depth 1 "${GRUB_BTRFS_REPO}" "${SOURCE_DIR}"
fi

# On refuse d'installer autre chose que le commit epingle: un tag amont peut
# etre deplace, et ce code s'execute en root dans le rootfs de l'image.
actual="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
if [[ "${actual}" != "${GRUB_BTRFS_COMMIT}" ]]; then
  echo "grub-btrfs n'est pas au commit epingle:" >&2
  echo "  attendu ${GRUB_BTRFS_COMMIT}" >&2
  echo "  obtenu  ${actual}" >&2
  exit 70
fi

echo "==> Installation de grub-btrfs dans le rootfs"
# On n'utilise PAS `make install`: sa cible refuse de tourner hors root, tente
# de generer les pages de man avec pandoc (absent) et voudrait lancer
# update-grub sur l'HOTE. On pose donc les quatre fichiers utiles nous-memes,
# avec les modes du Makefile amont.
sudo install -Dm755 "${SOURCE_DIR}/41_snapshots-btrfs" \
  "${ROOTFS}/etc/grub.d/41_snapshots-btrfs"
sudo install -Dm644 "${SOURCE_DIR}/config" \
  "${ROOTFS}/etc/default/grub-btrfs/config"
sudo install -Dm755 "${SOURCE_DIR}/grub-btrfsd" \
  "${ROOTFS}/usr/bin/grub-btrfsd"
sudo install -Dm644 "${SOURCE_DIR}/grub-btrfsd.service" \
  "${ROOTFS}/usr/lib/systemd/system/grub-btrfsd.service"
sudo install -Dm644 "${SOURCE_DIR}/LICENSE" \
  "${ROOTFS}/usr/share/licenses/grub-btrfs/LICENSE"

printf '%s %s\n' "${GRUB_BTRFS_TAG}" "${GRUB_BTRFS_COMMIT}" \
  | sudo tee "${ROOTFS}/usr/share/auxinuxos/grub-btrfs-version" >/dev/null

echo "==> grub-btrfs ${GRUB_BTRFS_TAG} (${GRUB_BTRFS_COMMIT}) installe"
