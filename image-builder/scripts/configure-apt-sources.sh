#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?usage: configure-apt-sources.sh ROOTFS}"

# ----------------------------------------------------------------------------
# Empreintes SHA-256 attendues des artefacts telecharges.
#
# A renseigner depuis une source de CONFIANCE hors-bande (release signee,
# annonce officielle), jamais en copiant simplement la valeur servie en ligne.
# Tant qu'une valeur reste "TODO", le telechargement correspondant ECHOUE
# (fail-closed), sauf bypass explicite via AUXINUX_ALLOW_UNVERIFIED=1.
#
# Justification: configure-apt-sources.sh execute en root, dans le chroot, des
# scripts distants qui posent les depots et les cles de tout l'OS (y compris le
# kernel). Sans verification, une compromission de l'hote/CDN injecte du code
# root dans chaque image.
# ----------------------------------------------------------------------------
DEB_SOURCES_SHA256="9e11094efadc01cd98079cdf53e11b2e767a82f44efc3cb96a86f841fdb64ca8"
AUXINUXOS_KEYRING_SHA256="963f569b4a74f9c76e0c56dd9fa288222b344ff6b102d26fc5eabf6e3ca3f410"
BRAVE_KEYRING_SHA256="c85e85aa3d1783ffaa649ee8dbbc22af7f87192d304602d37e3018226b394788"
BRAVE_SOURCES_SHA256="afb89575e544c6da0e2ba4f850931be800b442507a0ad9be3e12d0439566fb1f"

ALLOW_UNVERIFIED="${AUXINUX_ALLOW_UNVERIFIED:-0}"

# fetch_verified URL DEST EXPECTED_SHA256
fetch_verified() {
  local url="$1" dest="$2" expected="$3"
  sudo curl -fsSL "${url}" -o "${dest}"
  local actual
  actual="$(sha256sum "${dest}" | awk '{print $1}')"

  if [[ "${expected}" == "TODO" ]]; then
    if [[ "${ALLOW_UNVERIFIED}" == "1" ]]; then
      echo "AVERTISSEMENT: ${url}" >&2
      echo "  telecharge SANS verification (AUXINUX_ALLOW_UNVERIFIED=1)." >&2
      echo "  sha256 observe: ${actual}" >&2
      return 0
    fi
    echo "ERREUR: empreinte attendue non renseignee pour ${url}." >&2
    echo "  sha256 observe: ${actual}" >&2
    echo "  -> Renseignez la constante correspondante dans ce script depuis une" >&2
    echo "     source de confiance, ou relancez avec AUXINUX_ALLOW_UNVERIFIED=1" >&2
    echo "     pour ignorer la verification (NON recommande)." >&2
    exit 65
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERREUR: empreinte invalide pour ${url}" >&2
    echo "  attendu: ${expected}" >&2
    echo "  obtenu : ${actual}" >&2
    exit 65
  fi
}

sudo install -d -m 0755 "${ROOTFS}/usr/local/lib/auxinux" "${ROOTFS}/usr/share/keyrings"

fetch_verified \
  https://dep.auxinux.ca/scripts/install-auxinux-sources-DEB.sh \
  "${ROOTFS}/usr/local/lib/auxinux/install-auxinux-sources-DEB.sh" \
  "${DEB_SOURCES_SHA256}"
sudo chmod 0755 \
  "${ROOTFS}/usr/local/lib/auxinux/install-auxinux-sources-DEB.sh"

sudo chroot "${ROOTFS}" /usr/local/lib/auxinux/install-auxinux-sources-DEB.sh

# AuxiNuxOS kernel repository. Keep this local and pinned so the build cannot
# silently fall back to the retired /VIRTUA repository configuration.
fetch_verified \
  https://dep.auxinux.ca/AUXINUXOS/auxinuxos-archive-keyring.gpg \
  "${ROOTFS}/usr/share/keyrings/auxinuxos-archive-keyring.gpg" \
  "${AUXINUXOS_KEYRING_SHA256}"
sudo tee "${ROOTFS}/etc/apt/sources.list.d/auxinuxos-kernel.list" >/dev/null <<'EOF'
deb [signed-by=/usr/share/keyrings/auxinuxos-archive-keyring.gpg arch=amd64,arm64] https://dep.auxinux.ca/AUXINUXOS kernel main
EOF

# Brave: methode officielle (brave.com/linux), avec verification d'empreinte.
fetch_verified \
  https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
  "${ROOTFS}/usr/share/keyrings/brave-browser-archive-keyring.gpg" \
  "${BRAVE_KEYRING_SHA256}"
fetch_verified \
  https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
  "${ROOTFS}/etc/apt/sources.list.d/brave-browser-release.sources" \
  "${BRAVE_SOURCES_SHA256}"

sudo chroot "${ROOTFS}" apt-get update
