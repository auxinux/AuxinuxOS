#!/usr/bin/env bash
# Publie les paquets auxi et auxinux-center dans la suite APPS du depot
# AuxiNuxOS (https://dep.auxinux.ca/AUXINUXOS, suite APPS, composant main).
#
# POURQUOI LA SUITE APPS: elle est deja active sur toutes les installations
# (/etc/apt/sources.list.d/auxinux-apps.sources) et signee par la meme cle que
# le noyau. Une nouvelle version y est donc recue par la mise a jour du systeme
# (`auxi osupdate`, bouton « Mettre a jour le systeme »), sans rien configurer.
#
# La suite est geree par le script de publication d'AuxiNux Office, sur l'hote
# de depot: ~/auxinuxos-apps-pub/publish-repo.sh. Il est utilise TEL QUEL, comme
# il le documente (des .deb en arguments, --deploy): son pool local est
# cumulatif, donc auxinux-office reste indexe. On verifie quand meme, apres
# coup, que les trois paquets sont dans l'index.
#
# Comme publish-iso.sh: l'hote de build n'a pas de cle vers l'hote de depot, le
# transfert passe en flux par la machine qui lance ce script, et rien n'est
# publie sans --deploy.
#
# Usage:
#   publish-debs.sh --dir DOSSIER_DISTANT [--version V] [--deploy]
#
#   --dir      dossier SUR l'hote de build qui contient auxi_<V>_all.deb et
#              auxinux-center_<V>_amd64.deb (sortie de packages/build-debs.sh)
#   --version  version a publier (defaut: celle de packages/auxinux-center/Cargo.toml)
#   --deploy   publie reellement; sans cette option, le script verifie et
#              affiche ce qu'il ferait
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_HOST="${AUXINUX_BUILD_HOST:-virtua-dev}"
REPO_HOST="${AUXINUX_REPO_HOST:-virtua-repo}"
PUB_DIR="${AUXINUX_APPS_PUB_DIR:-auxinuxos-apps-pub}"
BASE_URL="${AUXINUX_REPO_URL:-https://dep.auxinux.ca/AUXINUXOS}"
PACKAGES_URL="${BASE_URL}/dists/APPS/main/binary-amd64/Packages"

REMOTE_DIR=""
VERSION=""
DEPLOY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     REMOTE_DIR="${2:?--dir demande un dossier}"; shift 2 ;;
    --version) VERSION="${2:?--version demande une version}"; shift 2 ;;
    --deploy)  DEPLOY=1; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "argument inconnu: $1" >&2; exit 64 ;;
  esac
done

[[ -n "${REMOTE_DIR}" ]] || { echo "--dir est obligatoire" >&2; exit 64; }
if [[ -z "${VERSION}" ]]; then
  VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "${SCRIPT_DIR}/auxinux-center/Cargo.toml" | head -n1)"
fi
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version invalide: ${VERSION}" >&2; exit 64; }

DEBS=("auxi_${VERSION}_all.deb" "auxinux-center_${VERSION}_amd64.deb")

# Version publiee d'un paquet dans l'index (vide si absent).
published_version() {
  awk -v p="$1" '
    $1 == "Package:" { cur = $2 }
    $1 == "Version:" && cur == p { print $2 }
  ' <<<"$2" | sort -V | tail -n1
}

echo "==> Index publie: ${PACKAGES_URL}"
INDEX="$(curl -fsS "${PACKAGES_URL}")" || { echo "index APPS illisible" >&2; exit 69; }
for pkg in auxi auxinux-center; do
  current="$(published_version "${pkg}" "${INDEX}")"
  echo "    ${pkg}: publie ${current:-(aucun)}, a publier ${VERSION}"
  if [[ -n "${current}" ]] && ! dpkg --compare-versions "${VERSION}" gt "${current}"; then
    echo "ERREUR: ${pkg} ${VERSION} n'est pas plus recent que ${current} (deja publie)." >&2
    echo "  Augmentez la version dans packages/auxinux-center/Cargo.toml (et la metainfo)." >&2
    exit 73
  fi
done
[[ -n "$(published_version auxinux-office "${INDEX}")" ]] \
  || echo "AVERTISSEMENT: auxinux-office absent de l'index AVANT publication." >&2

echo "==> Paquets sur ${BUILD_HOST}:${REMOTE_DIR}"
declare -A SHA
for deb in "${DEBS[@]}"; do
  read -r pkg ver sha <<<"$(ssh "${BUILD_HOST}" \
    "cd '${REMOTE_DIR}' && printf '%s %s %s' \"\$(dpkg-deb -f '${deb}' Package)\" \"\$(dpkg-deb -f '${deb}' Version)\" \"\$(sha256sum '${deb}' | cut -d' ' -f1)\"")"
  [[ -n "${sha:-}" ]] || { echo "ERREUR: ${deb} introuvable sur ${BUILD_HOST}" >&2; exit 66; }
  [[ "${ver}" == "${VERSION}" ]] || { echo "ERREUR: ${deb} annonce la version ${ver}" >&2; exit 65; }
  SHA["${deb}"]="${sha}"
  echo "    ${deb}: ${pkg} ${ver}, sha256 ${sha}"
done

if [[ "${DEPLOY}" -ne 1 ]]; then
  echo
  echo "Verifications passees. Relancez avec --deploy pour publier."
  exit 0
fi

echo "==> Transfert en flux (${BUILD_HOST} -> ici -> ${REPO_HOST}:~/${PUB_DIR}/incoming)"
ssh "${REPO_HOST}" "mkdir -p '${PUB_DIR}/incoming'"
for deb in "${DEBS[@]}"; do
  ssh "${BUILD_HOST}" "cat '${REMOTE_DIR}/${deb}'" \
    | ssh "${REPO_HOST}" "cat > '${PUB_DIR}/incoming/${deb}'"
  got="$(ssh "${REPO_HOST}" "sha256sum '${PUB_DIR}/incoming/${deb}' | cut -d' ' -f1")"
  if [[ "${got}" != "${SHA[${deb}]}" ]]; then
    echo "ERREUR: empreinte differente apres transfert de ${deb}." >&2
    ssh "${REPO_HOST}" "rm -f '${PUB_DIR}/incoming/${deb}'"
    exit 65
  fi
done

echo "==> Index, signature et deploiement (publish-repo.sh, suite APPS)"
ssh "${REPO_HOST}" "cd '${PUB_DIR}' && ./publish-repo.sh incoming/${DEBS[0]} incoming/${DEBS[1]} --deploy"

echo "==> Verification de l'index servi"
INDEX="$(curl -fsS "${PACKAGES_URL}")"
fail=0
for pkg in auxi auxinux-center; do
  got="$(published_version "${pkg}" "${INDEX}")"
  echo "    ${pkg}: ${got:-(absent)}"
  [[ "${got}" == "${VERSION}" ]] || fail=1
done
office="$(published_version auxinux-office "${INDEX}")"
echo "    auxinux-office: ${office:-(absent)}"
[[ -n "${office}" ]] || { echo "ERREUR: auxinux-office a disparu de l'index APPS" >&2; fail=1; }

for deb in "${DEBS[@]}"; do
  pkg="${deb%%_*}"
  file="$(awk -v p="${pkg}" -v v="${VERSION}" '
    $1 == "Package:" { cur = $2; ver = "" }
    $1 == "Version:" { ver = $2 }
    $1 == "Filename:" && cur == p && ver == v { print $2 }
  ' <<<"${INDEX}" | head -n1)"
  [[ -n "${file}" ]] || { echo "ERREUR: ${pkg} ${VERSION} sans Filename dans l'index" >&2; fail=1; continue; }
  served="$(curl -fsS "${BASE_URL}/${file}" | sha256sum | cut -d' ' -f1)"
  echo "    ${BASE_URL}/${file}: sha256 ${served}"
  [[ "${served}" == "${SHA[${deb}]}" ]] || { echo "ERREUR: ${file} servi differe de la source" >&2; fail=1; }
done

[[ "${fail}" -eq 0 ]] || exit 70
echo
echo "Publie: auxi ${VERSION} et auxinux-center ${VERSION} (suite APPS)."
echo "Les machines le recoivent par « auxi osupdate » / « Mettre a jour le systeme »."
