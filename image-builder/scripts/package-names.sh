#!/usr/bin/env bash
# Noms de paquets d'une ou plusieurs listes (image-builder/package-lists),
# filtres par architecture. Un seul filtre pour toute la chaine: installation
# et purge (build-image.sh), controles (check-rootfs.sh), tests.
#
# Syntaxe des listes:
#   - lignes vides et commentaires (#) ignores;
#   - premier mot = nom du paquet;
#   - un marqueur FINAL `[amd64]` ou `[arm64]` restreint la ligne a cette
#     architecture (ex. `grub-pc-bin [amd64]`, `grub-efi-arm64-bin [arm64]`).
#     Sans marqueur, la ligne vaut pour toutes les architectures.
#
# Usage: package-names.sh ARCH LISTE...
set -euo pipefail

ARCH="${1:?usage: package-names.sh ARCH LISTE...}"
shift
[[ $# -gt 0 ]] || { echo "usage: package-names.sh ARCH LISTE..." >&2; exit 64; }

awk -v arch="${ARCH}" '
  NF && $1 !~ /^#/ {
    if (NF >= 2 && $NF ~ /^\[[a-z0-9]+\]$/) {
      if ($NF != "[" arch "]") next
    }
    print $1
  }' "$@"
