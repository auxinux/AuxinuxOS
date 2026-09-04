#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 ROOTFS_DIR CACHE_DIR" >&2
  exit 64
fi

ROOTFS_DIR="$(realpath "$1")"
CACHE_DIR="$(realpath -m "$2")"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_LISTS_DIR="${PROJECT_DIR}/image-builder/package-lists"
COSMIC_TAG="epoch-1.2.0"
COSMIC_COMMIT="0098ab4d8f930bf7f7738121e04a4532154852ef"
SOURCE_DIR="${CACHE_DIR}/cosmic-epoch-${COSMIC_TAG}"
CHROOT_SOURCE="${ROOTFS_DIR}/tmp/cosmic-epoch-source"
CHROOT_STAGE="${ROOTFS_DIR}/tmp/cosmic-epoch-stage"
MOUNTED=0

cleanup() {
  if [[ "${MOUNTED}" -eq 1 ]]; then
    sudo umount -l "${CHROOT_SOURCE}" >/dev/null 2>&1 || true
  fi
  if ! sudo mountpoint -q "${CHROOT_SOURCE}"; then
    sudo rm -rf "${CHROOT_SOURCE}"
  fi
  sudo rm -rf "${CHROOT_STAGE}"
}
trap cleanup EXIT

mkdir -p "${CACHE_DIR}"
if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  sudo git clone --branch "${COSMIC_TAG}" --depth 1 --recurse-submodules \
    --shallow-submodules https://github.com/pop-os/cosmic-epoch.git "${SOURCE_DIR}"
fi

if [[ "$(sudo git -C "${SOURCE_DIR}" rev-parse HEAD)" != "${COSMIC_COMMIT}" ]]; then
  echo "COSMIC source cache is not at pinned commit ${COSMIC_COMMIT}" >&2
  exit 70
fi
sudo git -C "${SOURCE_DIR}" submodule update --init --recursive --depth 1

sudo install -d -m 0755 "${CHROOT_SOURCE}" "${CHROOT_STAGE}"
sudo mount --bind "${SOURCE_DIR}" "${CHROOT_SOURCE}"
MOUNTED=1

for metadata_file in packages-before.txt packages-after.txt build-only-packages.txt; do
  sudo touch "${CACHE_DIR}/${metadata_file}"
  sudo chown "$(id -u):$(id -g)" "${CACHE_DIR}/${metadata_file}"
done

# Invalidation automatique de packages-before.txt quand les listes de paquets
# changent.
#
# Ce fichier n'est regenere que s'il est VIDE, et build-only = after - before
# est ensuite PURGE du rootfs. Un packages-before.txt herite d'une
# construction anterieure aux listes actuelles fait donc classer chaque paquet
# nouvellement ajoute (snapper, grub-btrfs, zenity, zram-tools...) parmi les
# dependances de compilation a supprimer: l'ISO se construit sans erreur et
# arrive amputee de fonctions entieres, sans le moindre message. Panne deja
# rencontree, jusqu'ici documentee comme une precaution manuelle a prendre --
# ce qui revient a compter sur la memoire de l'operateur.
LISTS_FINGERPRINT="$(cat "${PACKAGE_LISTS_DIR}"/*.txt 2>/dev/null | sha256sum | cut -d' ' -f1)"
FINGERPRINT_FILE="${CACHE_DIR}/package-lists.sha256"
sudo touch "${FINGERPRINT_FILE}"
sudo chown "$(id -u):$(id -g)" "${FINGERPRINT_FILE}"
if [[ "$(cat "${FINGERPRINT_FILE}")" != "${LISTS_FINGERPRINT}" ]]; then
  if [[ -s "${CACHE_DIR}/packages-before.txt" ]]; then
    echo "==> Listes de paquets modifiees: invalidation de packages-before.txt"
  fi
  : >"${CACHE_DIR}/packages-before.txt"
  printf '%s\n' "${LISTS_FINGERPRINT}" >"${FINGERPRINT_FILE}"
fi

if [[ ! -s "${CACHE_DIR}/packages-before.txt" ]]; then
  sudo chroot "${ROOTFS_DIR}" dpkg-query -W -f='${binary:Package}\n' \
    | LC_ALL=C sort >"${CACHE_DIR}/packages-before.txt"
fi

sudo chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential dbus git curl ca-certificates pkg-config cmake just \
  libclang-dev libdbus-1-dev libdisplay-info-dev libexpat1-dev \
  libflatpak-dev libfontconfig-dev libfreetype-dev libgbm-dev libglvnd-dev \
  libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev libinput-dev \
  libpam0g-dev libpipewire-0.3-dev libpixman-1-dev libpulse-dev libseat-dev \
  libssl-dev libsystemd-dev libwayland-dev libxkbcommon-dev lld mold udev

# Epoch 1.2 components require Rust 1.93; Debian's compiler is intentionally
# not used so every component follows the toolchain files pinned upstream.
sudo chroot "${ROOTFS_DIR}" bash -lc \
  'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.93.0'
sudo chroot "${ROOTFS_DIR}" bash -lc \
  'set -e
   cd /tmp/cosmic-epoch-source
   export PATH=/root/.cargo/bin:$PATH
   export CARGO_TARGET_DIR=/tmp/cosmic-epoch-source/target
   required_bins="cosmic-applets cosmic-app-library cosmic-bg cosmic-comp cosmic-greeter cosmic-greeter-daemon cosmic-idle cosmic-launcher cosmic-notifications cosmic-osd cosmic-panel cosmic-randr cosmic-screenshot cosmic-settings cosmic-settings-daemon cosmic-session cosmic-workspaces"
   rebuild=0
   for binary in ${required_bins}; do
     test -x "${CARGO_TARGET_DIR}/release/${binary}" || rebuild=1
   done
   if test "${rebuild}" -eq 1; then
     just cosmic-applets/build-release
     just cosmic-applibrary/build-release
     just cosmic-bg/build-release
     make -C cosmic-comp all
     just cosmic-greeter/build-release
     just cosmic-idle/build-release
     just cosmic-launcher/build-release
     just cosmic-notifications/build-release
     just cosmic-osd/build-release
     just cosmic-panel/build-release
     just cosmic-randr/build-release
     just cosmic-screenshot/build-release
     just cosmic-settings/build-release
     make -C cosmic-settings-daemon all
     just cosmic-session/build-release
     make -C cosmic-workspaces-epoch all
   else
     echo "Reusing complete COSMIC binary cache"
   fi
   make -C cosmic-wallpapers all
   if test ! -x "${CARGO_TARGET_DIR}/release/pop-launcher-bin"; then
     just pop-launcher/build-release
   fi
   install -Dm0755 "${CARGO_TARGET_DIR}/release/pop-launcher-bin" \
     pop-launcher/target/release/pop-launcher-bin
   portal_target=/tmp/cosmic-epoch-source/xdg-desktop-portal-cosmic/target-auxinuxos
   if test ! -x "${portal_target}/release/xdg-desktop-portal-cosmic"; then
     CARGO_TARGET_DIR="${portal_target}" \
       just --justfile xdg-desktop-portal-cosmic/justfile build
   fi

   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-applets/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-applibrary/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-bg/install
   make -C cosmic-comp install DESTDIR=/tmp/cosmic-epoch-stage prefix=/usr
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-greeter/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-icons/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-idle/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-launcher/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-notifications/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-osd/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-panel/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-randr/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-screenshot/install
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-settings/install
   make -C cosmic-settings-daemon install DESTDIR=/tmp/cosmic-epoch-stage prefix=/usr
   just rootdir=/tmp/cosmic-epoch-stage prefix=/usr cosmic-session/install
   make -C cosmic-wallpapers install DESTDIR=/tmp/cosmic-epoch-stage prefix=/usr
   make -C cosmic-workspaces-epoch install DESTDIR=/tmp/cosmic-epoch-stage prefix=/usr
   just rootdir=/tmp/cosmic-epoch-stage pop-launcher/install
   CARGO_TARGET_DIR="${portal_target}" \
     just --justfile xdg-desktop-portal-cosmic/justfile rootdir=/tmp/cosmic-epoch-stage prefix=/usr install'

sudo rsync -aHAX "${CHROOT_STAGE}/" "${ROOTFS_DIR}/"
sudo install -d -m 0755 "${ROOTFS_DIR}/usr/share/auxinuxos"
printf '%s\n' "${COSMIC_TAG} ${COSMIC_COMMIT}" \
  | sudo tee "${ROOTFS_DIR}/usr/share/auxinuxos/cosmic-version" >/dev/null

# LC_ALL=C throughout (both sort calls, here and packages-before.txt above,
# AND comm itself): comm validates that its two inputs are sorted under the
# CURRENT locale's collation, independent of what locale `sort` used to
# produce them. packages-before.txt is cached and reused across
# sessions/build hosts (guarded above by `-s` check), so any locale
# mismatch -- sort vs sort, or sort vs comm's own default locale -- silently
# breaks comparison: GNU comm detects it ("input is not in sorted order")
# and exits 1, aborting the whole build under `set -e`.
sudo chroot "${ROOTFS_DIR}" dpkg-query -W -f='${binary:Package}\n' \
  | LC_ALL=C sort >"${CACHE_DIR}/packages-after.txt"
LC_ALL=C comm -13 "${CACHE_DIR}/packages-before.txt" "${CACHE_DIR}/packages-after.txt" \
  >"${CACHE_DIR}/build-only-packages.txt"
if [[ -s "${CACHE_DIR}/build-only-packages.txt" ]]; then
  mapfile -t BUILD_ONLY_PACKAGES <"${CACHE_DIR}/build-only-packages.txt"
  sudo chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive \
    apt-get purge -y "${BUILD_ONLY_PACKAGES[@]}"
fi
sudo rm -rf "${ROOTFS_DIR}/root/.cargo" "${ROOTFS_DIR}/root/.rustup"

echo "Installed COSMIC ${COSMIC_TAG} (${COSMIC_COMMIT}) from official sources"
