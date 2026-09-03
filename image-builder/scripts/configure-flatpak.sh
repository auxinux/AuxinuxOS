#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?usage: configure-flatpak.sh ROOTFS}"

sudo chroot "${ROOTFS}" flatpak remote-add \
  --system \
  --if-not-exists \
  --from \
  flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
