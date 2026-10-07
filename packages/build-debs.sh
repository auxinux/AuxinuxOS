#!/usr/bin/env bash
# Construit les paquets DEB d'AuxiNux OS Center et de la commande auxi.
#
# POURQUOI DES PAQUETS (2026-10-07): le Center et auxi etaient COPIES dans
# l'image (install -D). Inconnus de dpkg, ils ne pouvaient etre corriges que par
# une nouvelle ISO: aucune installation existante ne recevait un correctif. En
# paquets, publies dans la suite APPS du depot AuxiNuxOS (deja active partout,
# meme cle de signature), ils suivent la mise a jour du systeme.
#
#   auxi_<V>_all.deb            /usr/bin/auxi, le bouclier apt, le hook
#                               d'instantane
#   auxinux-center_<V>_amd64.deb  le Center, ses deux helpers, son action polkit
#
# Une seule version pour les deux, celle de packages/auxinux-center/Cargo.toml:
# le Center appelle des commandes d'auxi (auxi kernel...) et exige le auxi de la
# meme livraison. A AUGMENTER A CHAQUE PUBLICATION (publish-debs.sh refuse une
# version deja publiee).
#
# Ce qui reste pose par l'image (install-auxi-cli.sh), et pourquoi: les
# diversions dpkg d'apt/apt-get vers le bouclier, et le raccourci de
# /etc/skel/Desktop (copie pour chaque nouveau compte, ne se met pas a jour).
#
# Usage:
#   packages/build-debs.sh [--out DIR]
# Variables:
#   AUXINUX_CENTER_BIN  binaire du Center deja compile (sinon target/release)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTER_DIR="${SCRIPT_DIR}/auxinux-center"
AUXI_DIR="${SCRIPT_DIR}/auxi-cli"
OUT_DIR="${SCRIPT_DIR}/../build/debs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argument inconnu: $1" >&2; exit 64 ;;
  esac
done

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "${CENTER_DIR}/Cargo.toml" | head -n1)"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version illisible dans ${CENTER_DIR}/Cargo.toml: '${VERSION}'" >&2
  exit 65
fi

# La metainfo AppStream annonce la version: une metainfo en retard affiche une
# version perimee dans les logitheques.
if ! grep -q "<release version=\"${VERSION}\"" "${CENTER_DIR}/data/ca.auxinux.Center.metainfo.xml"; then
  echo "ca.auxinux.Center.metainfo.xml n'a pas de <release version=\"${VERSION}\">" >&2
  exit 65
fi

BIN="${AUXINUX_CENTER_BIN:-${CENTER_DIR}/target/release/auxinux-center}"
if [[ ! -x "${BIN}" ]]; then
  echo "binaire du Center introuvable: ${BIN}" >&2
  echo "compilez-le (packages/auxinux-center/build.sh) ou definissez AUXINUX_CENTER_BIN" >&2
  exit 70
fi
# Le binaire doit etre celui de CETTE version: un ancien binaire dans un paquet
# neuf serait publie, installe partout, et ne se distinguerait de rien.
BIN_VERSION="$("${BIN}" --version 2>/dev/null || true)"
if [[ "${BIN_VERSION}" != "auxinux-center ${VERSION}" ]]; then
  echo "le binaire ${BIN} annonce « ${BIN_VERSION} », pas « auxinux-center ${VERSION} »: recompilez-le" >&2
  exit 65
fi

command -v dpkg-deb >/dev/null 2>&1 || { echo "dpkg-deb introuvable" >&2; exit 69; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

MAINTAINER="AuxiNux <repo@auxinux.ca>"
HOMEPAGE="https://os.auxinux.ca/auxinuxos"

# --- auxi --------------------------------------------------------------------
AUXI_ROOT="${WORK}/auxi"
install -D -m 0755 "${AUXI_DIR}/auxi" "${AUXI_ROOT}/usr/bin/auxi"
install -D -m 0755 "${AUXI_DIR}/apt-wrapper" "${AUXI_ROOT}/usr/lib/auxinux/wrappers/apt-wrapper"
install -D -m 0755 "${AUXI_DIR}/apt-snapshot-hook" "${AUXI_ROOT}/usr/lib/auxinux/apt-snapshot-hook"
install -d -m 0755 "${AUXI_ROOT}/DEBIAN"
cat >"${AUXI_ROOT}/DEBIAN/control" <<EOF
Package: auxi
Version: ${VERSION}
Architecture: all
Maintainer: ${MAINTAINER}
Section: admin
Priority: optional
Depends: bash, apt, dpkg
Recommends: flatpak, snapper, grub-common
Homepage: ${HOMEPAGE}
Description: commande d'administration d'AuxiNux OS
 auxi installe les applications (Flatpak d'abord), met le systeme a jour,
 gere les noyaux AuxiNux et les points de restauration BTRFS.
EOF

# --- auxinux-center ----------------------------------------------------------
CENTER_ROOT="${WORK}/center"
install -D -m 0755 "${BIN}" "${CENTER_ROOT}/usr/bin/auxinux-center"
install -D -m 0644 "${CENTER_DIR}/data/ca.auxinux.Center.desktop" \
  "${CENTER_ROOT}/usr/share/applications/ca.auxinux.Center.desktop"
install -D -m 0644 "${CENTER_DIR}/data/ca.auxinux.Center.metainfo.xml" \
  "${CENTER_ROOT}/usr/share/metainfo/ca.auxinux.Center.metainfo.xml"
install -D -m 0644 "${CENTER_DIR}/data/auxinux-assistant.desktop" \
  "${CENTER_ROOT}/etc/xdg/autostart/auxinux-assistant.desktop"
install -D -m 0755 "${CENTER_DIR}/helper/auxinux-source-helper" \
  "${CENTER_ROOT}/usr/libexec/auxinux/auxinux-source-helper"
install -D -m 0755 "${CENTER_DIR}/helper/auxinux-assistant-apply" \
  "${CENTER_ROOT}/usr/libexec/auxinux/auxinux-assistant-apply"
install -D -m 0644 "${CENTER_DIR}/helper/ca.auxinux.center.policy" \
  "${CENTER_ROOT}/usr/share/polkit-1/actions/ca.auxinux.center.policy"
install -d -m 0755 "${CENTER_ROOT}/DEBIAN"
printf '/etc/xdg/autostart/auxinux-assistant.desktop\n' >"${CENTER_ROOT}/DEBIAN/conffiles"

# Bibliotheques liees au binaire (libc, libgcc, libssl...), calculees par
# dpkg-shlibdeps quand il est la. libwayland-client et libxkbcommon sont
# ouvertes par dlopen (winit, sctk): aucun outil ne les voit, d'ou la liste
# explicite.
SHLIBS=""
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
  mkdir -p "${WORK}/shlibs/debian"
  printf 'Source: auxinux-center\n\nPackage: auxinux-center\nArchitecture: amd64\n' \
    >"${WORK}/shlibs/debian/control"
  SHLIBS="$(cd "${WORK}/shlibs" && dpkg-shlibdeps -O "${CENTER_ROOT}/usr/bin/auxinux-center" 2>/dev/null \
    | sed -n 's/^shlibs:Depends=//p')"
fi
DEPENDS="auxi (= ${VERSION}), pkexec, flatpak, libwayland-client0, libxkbcommon0"
[[ -n "${SHLIBS}" ]] && DEPENDS="${DEPENDS}, ${SHLIBS}"

cat >"${CENTER_ROOT}/DEBIAN/control" <<EOF
Package: auxinux-center
Version: ${VERSION}
Architecture: amd64
Maintainer: ${MAINTAINER}
Section: admin
Priority: optional
Depends: ${DEPENDS}
Homepage: ${HOMEPAGE}
Description: AuxiNux OS Center, centre de controle d'AuxiNux OS
 Applications, mises a jour, noyaux, sante du systeme, sources,
 reglages et restauration.
EOF

for root in "${AUXI_ROOT}" "${CENTER_ROOT}"; do
  (cd "${root}" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
    | xargs -0 md5sum >DEBIAN/md5sums)
done

AUXI_DEB="${OUT_DIR}/auxi_${VERSION}_all.deb"
CENTER_DEB="${OUT_DIR}/auxinux-center_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "${AUXI_ROOT}" "${AUXI_DEB}" >/dev/null
dpkg-deb --root-owner-group -Zxz --build "${CENTER_ROOT}" "${CENTER_DEB}" >/dev/null

echo "${AUXI_DEB}"
echo "${CENTER_DEB}"
