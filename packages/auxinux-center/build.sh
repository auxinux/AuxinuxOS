#!/usr/bin/env bash
# Build local d'AuxiNux OS Center (Rust + libcosmic).
#
# Prerequis sur l'hote de build (Debian 13 Trixie):
#   - toolchain Rust >= 1.93 (rustup: le rustc de Debian 13 est en 1.85)
#   - build-essential pkg-config
#   - libxkbcommon-dev libwayland-dev libudev-dev libinput-dev
#   - libssl-dev
#
# Qt6 et KF6 ne sont pas necessaires pour compiler: l'interface Kirigami/CXX-Qt
# a ete remplacee par libcosmic (iced), qui ne depend d'aucun toolkit du bureau.
#
# Resultat: target/release/auxinux-center
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

BACKEND_ONLY=0
if [[ "${1:-}" == "--backend-only" ]]; then
  BACKEND_ONLY=1
fi

# Une toolchain rustup, si elle existe, passe AVANT celle de Debian. Sans cela,
# un shell non interactif (CI, ssh non-login) resout `cargo` vers /usr/bin/cargo
# -- 1.85 sur Trixie -- et la compilation echoue sur une cascade de "requires
# rustc 1.9x" incomprehensible alors qu'une toolchain recente est installee.
if [[ -x "${HOME}/.cargo/bin/cargo" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo introuvable: installez le toolchain Rust (rustup recommande)." >&2
  exit 69
fi

# libcosmic 1.0 et ses dependances (wgpu, icu, zbus) exigent une toolchain
# recente. On verifie AVANT de compiler: l'echec natif de cargo arrive apres
# plusieurs minutes de resolution et noie la cause dans trente lignes.
MIN_RUST="1.93.0"
rust_version="$(rustc --version | cut -d' ' -f2)"
if [[ "$(printf '%s\n%s\n' "${MIN_RUST}" "${rust_version}" | sort -V | head -n1)" != "${MIN_RUST}" ]]; then
  echo "rustc ${rust_version} est trop ancien: ${MIN_RUST} minimum (libcosmic)." >&2
  echo "Installez rustup: curl -sSf https://sh.rustup.rs | sh -s -- -y" >&2
  echo "rustc utilise: $(command -v rustc)" >&2
  exit 69
fi
echo "==> rustc ${rust_version} ($(command -v rustc))"

if [[ "${BACKEND_ONLY}" -eq 1 ]]; then
  # Valide toute la logique sans aucune dependance graphique. Utile sur une
  # machine de developpement sans Wayland ni libxkbcommon.
  echo "==> cargo test --no-default-features"
  cargo test --no-default-features
  echo "==> cargo build --release --no-default-features"
  cargo build --release --no-default-features
  echo "==> Backend seul: ${SCRIPT_DIR}/target/release/auxinux-center --cli sysinfo"
  exit 0
fi

echo "==> cargo test --no-default-features (logique)"
cargo test --no-default-features

echo "==> cargo build --release (interface libcosmic)"
cargo build --release

echo "==> Binaire: ${SCRIPT_DIR}/target/release/auxinux-center"
echo "Test du backend sans interface: ./target/release/auxinux-center --cli health"
