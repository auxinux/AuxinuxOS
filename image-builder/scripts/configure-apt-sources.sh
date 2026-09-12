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

# ----------------------------------------------------------------------------
# Neutralise le /etc/apt/sources.list laisse par mmdebstrap.
#
# PANNE OBSERVEE LE 2026-09-12, a la premiere construction depuis le miroir
# AuxiNux: mmdebstrap ecrit un sources.list a l'ancienne
# (« deb https://dep.auxinux.ca/DEBIAN trixie main contrib ... ») qui ne porte
# AUCUNE restriction d'architecture. install-auxinux-sources-DEB.sh ne le
# desactive pas: il ne desactive que les sources contenant « debian.org », et
# dep.auxinux.ca n'y ressemble pas.
#
# Deux consequences:
#   1. chaque cible est declaree deux fois (« configured multiple times »);
#   2. surtout, des que i386 est ajoute comme architecture etrangere, apt
#      reclame dists/trixie/main/binary-i386/Packages au miroir -- qui repond
#      404, faute de miroiter i386 -- et `apt-get update` sort en erreur. La
#      construction s'arretait la, apres 45 minutes de bootstrap.
#
# Le fichier deb822 pose par le script officiel decrit exactement le meme
# miroir avec « Architectures: amd64 »: celui-ci est donc redondant. On le vide
# au lieu de le supprimer, pour qu'un lecteur comprenne ce qui s'est passe.
#
# CE BLOC DOIT RESTER AVANT install-auxinux-sources-DEB.sh: ce script fait son
# PROPRE `apt-get update` a la fin. Place apres lui, la neutralisation arrivait
# trop tard et la construction mourait dans le script distant -- constate sur
# la reprise du 2026-09-12.
if [[ -f "${ROOTFS}/etc/apt/sources.list" ]] &&
   grep -q 'dep\.auxinux\.ca' "${ROOTFS}/etc/apt/sources.list"; then
  sudo tee "${ROOTFS}/etc/apt/sources.list" >/dev/null <<'EOF'
# Volontairement vide.
#
# Les sources d'AuxiNuxOS sont dans /etc/apt/sources.list.d/ au format deb822.
# Le sources.list produit par mmdebstrap au bootstrap a ete neutralise ici
# (image-builder/scripts/configure-apt-sources.sh): il decrivait le meme miroir
# que auxinux-debian.sources, mais SANS restriction d'architecture, ce qui
# faisait echouer `apt-get update` des l'ajout de l'architecture i386 (le
# miroir ne porte pas binary-i386).
EOF
fi


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

# ----------------------------------------------------------------------------
# Architecture i386, indispensable a la couche jeu.
#
# LE MIROIR AUXINUX NE MIROITE PAS i386 (verifie le 2026-09-12:
# dists/trixie/main/ ne contient que binary-all et binary-amd64, et
# binary-i386/Packages.xz repond 404). Le script officiel
# install-auxinux-sources-DEB.sh en tient compte en epinglant
# « Architectures: amd64 » -- ce qui evite un 404 a chaque apt update, mais
# rend AUCUN paquet 32 bits installable sur un systeme AuxiNuxOS.
#
# Consequence concrete, passee inapercue jusqu'ici: wine32 n'arrivait dans la
# 0.1 que parce que mmdebstrap bootstrappait depuis deb.debian.org. Sur la
# machine INSTALLEE, ni Steam, ni un jeu 32 bits, ni une bibliotheque
# Vulkan 32 bits ne pouvaient etre installes -- et le message d'apt ne dit pas
# pourquoi.
#
# Tant que le miroir ne porte pas i386, cette architecture vient de Debian
# directement. Le depot est epingle a « Architectures: i386 »: il ne peut donc
# pas servir un seul paquet amd64, et le miroir AuxiNux reste la source unique
# de tout le systeme 64 bits.
#
# A SUPPRIMER le jour ou dep.auxinux.ca/DEBIAN miroitera i386.
# install-auxinux-sources-DEB.sh desactive toute source contenant
# « debian.org »: sur une construction reprise, il a donc renomme ce fichier
# en .sources.disabled avant qu'on le reecrive. On retire le cadavre, sinon
# l'image livree garde une source desactivee sans que personne sache pourquoi.
sudo rm -f "${ROOTFS}/etc/apt/sources.list.d/debian-i386.sources.disabled"
sudo tee "${ROOTFS}/etc/apt/sources.list.d/debian-i386.sources" >/dev/null <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Architectures: i386
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Architectures: i386
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
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
