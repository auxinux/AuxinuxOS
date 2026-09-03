#!/usr/bin/env bash
# Build local d'AuxiNux OS Center (Rust + CXX-Qt + Kirigami).
#
# Prerequis sur l'hote de build (debiandev / Debian 13 Trixie):
#   - toolchain Rust (rustup ou paquet rustc/cargo >= 1.75)
#   - Qt6 + KF6 dev: qt6-base-dev qt6-declarative-dev cmake build-essential
#     qml6-module-org-kde-kirigami (runtime), kirigami2 / kf6
#   - libssl-dev pkg-config
#
# Resultat: target/release/auxinux-center
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo introuvable: installez le toolchain Rust." >&2
  exit 69
fi

echo "==> cargo build --release"
cargo build --release

echo "==> Binaire: ${SCRIPT_DIR}/target/release/auxinux-center"
echo "Test backend sans Qt: ./target/release/auxinux-center --cli sysinfo"
