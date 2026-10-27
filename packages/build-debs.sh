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
#   auxinux-center_<V>_<ARCH>.deb le Center, ses deux helpers, son action polkit,
#                               l'assistant des .exe (amd64 seulement), les
#                               dossiers personnels. ARCH = architecture native
#                               de l'hote (amd64, ou arm64 pour l'Edition ARM).
#   auxinuxos-release_<R>_<arch>.deb la VERSION d'AuxiNux OS (une par ISO publiee,
#                               R = 0.5.0+AAAAMMJJ[.N]) et les reglages du
#                               systeme installe (packages/release/root/)
#
# auxinuxos-release (depuis le 2026-10-09): chaque ISO publiee est une
# « version » annoncee dans le centre de controle. Le paquet exige les versions
# minimales des autres paquets AuxiNux: sa mise a jour tire le reste. Il porte
# aussi les reglages de /etc qui etaient copies par l'image (associations,
# Plasma, systemd, SDDM, Brave...): les machines installees les recoivent.
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
#   AUXINUX_RELEASE     version d'AuxiNux OS: 0.5.0+AAAAMMJJ[.N]
#                       (defaut: version de os-release + date du jour)
#   AUXINUX_STRIP=0     ne pas stripper le binaire (tests avec un faux binaire)
#   AUXINUX_ARCH        architecture du paquet auxinux-center (defaut: celle
#                       de l'hote, qui est aussi celle du binaire compile)
set -euo pipefail

ARCH="${AUXINUX_ARCH:-$(dpkg --print-architecture 2>/dev/null || echo amd64)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTER_DIR="${SCRIPT_DIR}/auxinux-center"
AUXI_DIR="${SCRIPT_DIR}/auxi-cli"
OUT_DIR="${SCRIPT_DIR}/../build/debs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Version d'AuxiNux OS: celle de os-release (0.5.0), plus l'edition (la date
# de l'ISO, et .N pour une seconde ISO le meme jour).
RELEASE_DIR="${SCRIPT_DIR}/release"
OS_VERSION="$(sed -n 's/^VERSION="\([^ "]*\).*/\1/p' "${RELEASE_DIR}/root/usr/lib/os-release")"
RELEASE="${AUXINUX_RELEASE:-${OS_VERSION}+$(date +%Y%m%d)}"
if [[ ! "${RELEASE}" =~ ^${OS_VERSION//./\\.}\+([0-9]{8})(\.([0-9]+))?$ ]]; then
  echo "AUXINUX_RELEASE invalide: '${RELEASE}' (attendu ${OS_VERSION}+AAAAMMJJ ou ${OS_VERSION}+AAAAMMJJ.N)" >&2
  exit 65
fi
BUILD_ID="${RELEASE#*+}"
EDITION="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2}"
[[ -n "${BASH_REMATCH[3]}" ]] && EDITION="${EDITION} (${BASH_REMATCH[3]})"
if ! grep -q '[^[:space:]]' "${RELEASE_DIR}/NOUVEAUTES" 2>/dev/null; then
  echo "packages/release/NOUVEAUTES est vide: c'est ce que le centre affiche pour cette version" >&2
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
Depends: apt
Recommends: flatpak, snapper, grub-common
Homepage: ${HOMEPAGE}
Description: commande d'administration d'AuxiNux OS
 auxi installe les applications (Flatpak d'abord), met le systeme a jour,
 gere les noyaux AuxiNux et les points de restauration BTRFS.
EOF

# --- auxinux-center ----------------------------------------------------------
CENTER_ROOT="${WORK}/center"
install -D -m 0755 "${BIN}" "${CENTER_ROOT}/usr/bin/auxinux-center"
# Les symboles de debogage gonflent le paquet et ne servent a personne sur une
# machine d'utilisateur.
if [[ "${AUXINUX_STRIP:-1}" != 0 ]] && command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "${CENTER_ROOT}/usr/bin/auxinux-center"
fi
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
install -D -m 0755 "${CENTER_DIR}/helper/auxinux-refresh-helper" \
  "${CENTER_ROOT}/usr/libexec/auxinux/auxinux-refresh-helper"
install -D -m 0755 "${CENTER_DIR}/helper/auxinux-update-helper" \
  "${CENTER_ROOT}/usr/libexec/auxinux/auxinux-update-helper"
install -D -m 0755 "${CENTER_DIR}/helper/auxinux-session-helper" \
  "${CENTER_ROOT}/usr/libexec/auxinux/auxinux-session-helper"
install -D -m 0644 "${CENTER_DIR}/helper/ca.auxinux.center.policy" \
  "${CENTER_ROOT}/usr/share/polkit-1/actions/ca.auxinux.center.policy"
# Assistant d'ouverture des .exe et dossiers personnels (depuis la 0.2.2): en
# paquet, leurs correctifs atteignent aussi les machines deja installees.
# amd64 seulement: en arm64 (Edition ARM), Wine n'execute pas de programmes
# x86; un assistant qui propose d'ouvrir un .exe menerait a un echec.
if [[ "${ARCH}" == "amd64" ]]; then
  install -D -m 0755 "${SCRIPT_DIR}/windows-support/auxinux-windows-wizard" \
    "${CENTER_ROOT}/usr/bin/auxinux-windows-wizard"
  install -D -m 0644 "${SCRIPT_DIR}/windows-support/auxinux-windows-wizard.desktop" \
    "${CENTER_ROOT}/usr/share/applications/auxinux-windows-wizard.desktop"
fi
install -D -m 0755 "${SCRIPT_DIR}/user-dirs/auxinux-user-dirs" \
  "${CENTER_ROOT}/usr/lib/auxinux/auxinux-user-dirs"
install -D -m 0644 "${SCRIPT_DIR}/user-dirs/auxinux-user-dirs.desktop" \
  "${CENTER_ROOT}/etc/xdg/autostart/auxinux-user-dirs.desktop"
install -d -m 0755 "${CENTER_ROOT}/DEBIAN"
# /etc/xdg/kiorc est passe a auxinuxos-release (Replaces/Breaks plus bas).
printf '%s\n' /etc/xdg/autostart/auxinux-assistant.desktop \
  /etc/xdg/autostart/auxinux-user-dirs.desktop >"${CENTER_ROOT}/DEBIAN/conffiles"

# Bibliotheques liees au binaire (libc, libgcc, libssl...), calculees par
# dpkg-shlibdeps quand il est la. libwayland-client et libxkbcommon sont
# ouvertes par dlopen (winit, sctk): aucun outil ne les voit, d'ou la liste
# explicite.
SHLIBS=""
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
  mkdir -p "${WORK}/shlibs/debian"
  printf 'Source: auxinux-center\n\nPackage: auxinux-center\nArchitecture: %s\n' "${ARCH}" \
    >"${WORK}/shlibs/debian/control"
  SHLIBS="$(cd "${WORK}/shlibs" && dpkg-shlibdeps -O "${CENTER_ROOT}/usr/bin/auxinux-center" 2>/dev/null \
    | sed -n 's/^shlibs:Depends=//p')"
fi
DEPENDS="auxi (= ${VERSION}), pkexec, flatpak, zenity, libwayland-client0, libxkbcommon0"
[[ -n "${SHLIBS}" ]] && DEPENDS="${DEPENDS}, ${SHLIBS}"

cat >"${CENTER_ROOT}/DEBIAN/control" <<EOF
Package: auxinux-center
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Section: admin
Priority: optional
Depends: ${DEPENDS}
Homepage: ${HOMEPAGE}
Description: AuxiNux OS Center, centre de controle d'AuxiNux OS
 Applications, mises a jour, noyaux, sante du systeme, sources,
 reglages et restauration.
EOF

# --- auxinuxos-release --------------------------------------------------------
REL_ROOT="${WORK}/release"
cp -a "${RELEASE_DIR}/root" "${REL_ROOT}"
# Permissions d'un paquet, pas celles de la copie de travail (un depot clone
# dans un dossier setgid donne des repertoires en 2755, que dpkg-deb refuse).
find "${REL_ROOT}" -type d -exec chmod 0755 {} + -exec chmod g-s {} +
find "${REL_ROOT}" -type f -exec chmod go-w,a+r {} +
# L'edition est ecrite dans os-release (champ standard BUILD_ID): c'est ce que
# le centre affiche, et ce qu'il compare a la version disponible.
printf 'BUILD_ID=%s\n' "${BUILD_ID}" >>"${REL_ROOT}/usr/lib/os-release"
# Socle du bureau de l'image (bureau-auxinux.txt), lu par `auxi check` et
# `auxi repair` (2026-10-26): l'ISO installe ces paquets sans qu'aucun paquet
# n'en depende, une machine installee AVANT leur ajout ne les recoit donc
# jamais par les mises a jour (agent polkit de repli, portails...). Les
# applications KDE en sont exclues: les retirer est un choix de l'utilisateur.
BUREAU_LIST="${SCRIPT_DIR}/../image-builder/package-lists/bureau-auxinux.txt"
install -d -m 0755 "${REL_ROOT}/usr/share/auxinuxos"
awk '/^# --- / { skip = /Applications KDE/ } !skip' "${BUREAU_LIST}" >"${WORK}/socle-bureau.txt"
{
  printf '# Socle du bureau d%sAuxiNux OS %s (%s), genere depuis bureau-auxinux.txt.\n' "'" "${RELEASE}" "${ARCH}"
  "${SCRIPT_DIR}/../image-builder/scripts/package-names.sh" "${ARCH}" "${WORK}/socle-bureau.txt"
} >"${REL_ROOT}/usr/share/auxinuxos/socle-bureau.list"
chmod 0644 "${REL_ROOT}/usr/share/auxinuxos/socle-bureau.list"
install -d -m 0755 "${REL_ROOT}/DEBIAN"
install -m 0755 "${RELEASE_DIR}/debian/preinst" "${RELEASE_DIR}/debian/postinst" \
  "${RELEASE_DIR}/debian/postrm" "${REL_ROOT}/DEBIAN/"
install -m 0644 "${RELEASE_DIR}/debian/triggers" "${REL_ROOT}/DEBIAN/"
(cd "${REL_ROOT}" && find etc -type f | sort | sed 's|^|/|') >"${REL_ROOT}/DEBIAN/conffiles"
# Le preinst met de cote, a la premiere installation, les copies laissees par
# l'image: il lui faut la liste exacte des conffiles.
sed -i "s|@CONFFILES@|$(tr '\n' ' ' <"${REL_ROOT}/DEBIAN/conffiles" | sed 's/ $//')|" "${REL_ROOT}/DEBIAN/preinst"
# Description longue = nouveautes, une ligne par paragraphe (format deb822).
NOTES="$(sed -e '/^[[:space:]]*$/d' -e 's/^/ /' "${RELEASE_DIR}/NOUVEAUTES")"
# Paquet PAR ARCHITECTURE depuis l'Edition ARM (2026-10-25), et non plus
# « all »: un paquet all est le meme pour toutes les machines, or Debian ne
# permet pas de conditionner ses Depends a l'architecture. La version amd64
# tire les applications AuxiNux; la version arm64 seulement ce qui existe en
# arm64 (les applications y entreront avec leurs paquets arm64).
REL_DEPENDS="auxi (>= ${VERSION}), auxinux-center (>= ${VERSION}), kernel-auxinuxos, auxinux-shell (>= 0.3.23)"
# Applications AuxiNux publiees pour les deux architectures (arm64 depuis le
# 2026-10-26); AuxiMail n'existe encore qu'en amd64.
REL_DEPENDS="${REL_DEPENDS}, auxioffice, auxitext, auxicorrect, auxipak (>= 1.0.11)"
if [[ "${ARCH}" == "amd64" ]]; then
  REL_DEPENDS="${REL_DEPENDS}, auxi-mail"
fi
REL_DEPENDS="${REL_DEPENDS}, plymouth, base-files"
cat >"${REL_ROOT}/DEBIAN/control" <<EOF
Package: auxinuxos-release
Version: ${RELEASE}
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Section: admin
Priority: important
Depends: ${REL_DEPENDS}
Replaces: auxinux-center (<< 0.2.3)
Breaks: auxinux-center (<< 0.2.3)
Homepage: ${HOMEPAGE}
Description: AuxiNux OS ${OS_VERSION}, édition du ${EDITION}
${NOTES}
EOF

# Licence et journal des changements: exiges par la politique Debian
# (/usr/share/doc/<paquet>/), et ce que lit quiconque se demande d'ou vient un
# paquet installe.
for pkg in auxi auxinux-center auxinuxos-release; do
  case "${pkg}" in
    auxi) root="${AUXI_ROOT}"; ver="${VERSION}" ;;
    auxinux-center) root="${CENTER_ROOT}"; ver="${VERSION}" ;;
    auxinuxos-release) root="${REL_ROOT}"; ver="${RELEASE}" ;;
  esac
  doc="${root}/usr/share/doc/${pkg}"
  install -d -m 0755 "${doc}"
  cat >"${doc}/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${pkg}
Source: ${HOMEPAGE}

Files: *
Copyright: AuxiNux
License: GPL-3.0-or-later
 On Debian systems, the full text of the GNU General Public License version 3
 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT
  {
    printf '%s (%s) stable; urgency=medium\n\n' "${pkg}" "${ver}"
    printf '  * Version %s, voir %s.\n\n' "${ver}" "${HOMEPAGE}"
    printf ' -- %s  %s\n' "${MAINTAINER}" "$(date -R)"
  } | gzip -9n >"${doc}/changelog.gz"
  chmod 0644 "${doc}/copyright" "${doc}/changelog.gz"
done

for root in "${AUXI_ROOT}" "${CENTER_ROOT}" "${REL_ROOT}"; do
  (cd "${root}" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
    | xargs -0 md5sum >DEBIAN/md5sums)
done

AUXI_DEB="${OUT_DIR}/auxi_${VERSION}_all.deb"
CENTER_DEB="${OUT_DIR}/auxinux-center_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "${AUXI_ROOT}" "${AUXI_DEB}" >/dev/null
dpkg-deb --root-owner-group -Zxz --build "${CENTER_ROOT}" "${CENTER_DEB}" >/dev/null
RELEASE_DEB="${OUT_DIR}/auxinuxos-release_${RELEASE}_${ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "${REL_ROOT}" "${RELEASE_DEB}" >/dev/null

echo "${AUXI_DEB}"
echo "${CENTER_DEB}"
echo "${RELEASE_DEB}"
