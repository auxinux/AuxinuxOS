#!/usr/bin/env bash
# Construit l'ISO dans un conteneur debian:trixie PRIVILEGIE (workflow
# .github/workflows/iso.yml). Debian 13 = la cible: le centre y est compile
# contre la bonne glibc, et mmdebstrap/grub/xorriso sont ceux de virtua-dev.
#
#   docker run --privileged -v "$PWD:/src" -v /mnt/work:/work debian:trixie \
#     /src/image-builder/ci/build-iso-in-container.sh
#
# Le conteneur tourne en root: un faux `sudo` suffit (build-image.sh
# l'appelle partout, comme sur l'hote de build).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git sudo rsync xz-utils \
  mmdebstrap squashfs-tools xorriso mtools dosfstools \
  grub-common grub-efi-amd64-bin grub-pc-bin \
  build-essential pkg-config dpkg-dev \
  libxkbcommon-dev libwayland-dev libudev-dev libinput-dev libssl-dev \
  initramfs-tools-core util-linux

# rustc de Debian 13 = 1.85: libcosmic exige 1.93 (packages/auxinux-center/build.sh).
if ! command -v cargo >/dev/null 2>&1 || [[ ! -x "${HOME}/.cargo/bin/cargo" ]]; then
  curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
export PATH="${HOME}/.cargo/bin:${PATH}"

git config --global --add safe.directory /src
cd /src
/src/image-builder/build-image.sh --work-dir /work --force
ls -l /src/image-builder/output/
