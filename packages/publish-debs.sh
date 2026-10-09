#!/usr/bin/env bash
# Publie les paquets auxi et auxinux-center dans la suite APPS du depot
# AuxiNuxOS (https://dep.auxinux.ca/AUXINUXOS, suite APPS, composant main).
#
# POURQUOI LA SUITE APPS: elle est deja active sur toutes les installations
# (/etc/apt/sources.list.d/auxinux-apps.sources) et signee par la meme cle que
# le noyau. Une nouvelle version y est donc recue par la mise a jour du systeme
# (`auxi os upgrade`, boutons du centre de controle), sans rien configurer.
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

# Version publiee d'un paquet dans l'index (vide si absent).
published_version() {
  awk -v p="$1" '
    $1 == "Package:" { cur = $2 }
    $1 == "Version:" && cur == p { print $2 }
  ' <<<"$2" | sort -V | tail -n1
}

# Edition d'AuxiNux OS du dossier (auxinuxos-release_<R>_all.deb, depuis le
# 2026-10-09): une par ISO, elle doit TOUJOURS etre plus recente que celle en
# ligne -- c'est elle qui annonce la nouvelle version aux machines installees.
RELEASE_DEB="$(ssh "${BUILD_HOST}" "cd '${REMOTE_DIR}' && ls auxinuxos-release_*_all.deb 2>/dev/null" | sort -V | tail -n1)"
[[ -n "${RELEASE_DEB}" ]] || { echo "ERREUR: aucun auxinuxos-release_*_all.deb dans ${BUILD_HOST}:${REMOTE_DIR}" >&2; exit 66; }
RELEASE="${RELEASE_DEB#auxinuxos-release_}"; RELEASE="${RELEASE%_all.deb}"

declare -A WANT=([auxi]="${VERSION}" [auxinux-center]="${VERSION}" [auxinuxos-release]="${RELEASE}")
declare -A FILE=([auxi]="auxi_${VERSION}_all.deb" [auxinux-center]="auxinux-center_${VERSION}_amd64.deb" [auxinuxos-release]="${RELEASE_DEB}")

echo "==> Index publie: ${PACKAGES_URL}"
INDEX="$(curl -fsS "${PACKAGES_URL}")" || { echo "index APPS illisible" >&2; exit 69; }
PKGS=()
for pkg in auxi auxinux-center auxinuxos-release; do
  current="$(published_version "${pkg}" "${INDEX}")"
  echo "    ${pkg}: publie ${current:-(aucun)}, a publier ${WANT[${pkg}]}"
  if [[ -z "${current}" ]] || dpkg --compare-versions "${WANT[${pkg}]}" gt "${current}"; then
    PKGS+=("${pkg}")
  elif [[ "${pkg}" != auxinuxos-release && "${current}" == "${WANT[${pkg}]}" ]]; then
    # Une nouvelle edition ne change pas forcement le centre ni auxi.
    echo "      (deja en ligne: inchange)"
  else
    echo "ERREUR: ${pkg} ${WANT[${pkg}]} n'est pas plus recent que ${current} (deja publie)." >&2
    [[ "${pkg}" == auxinuxos-release ]] \
      && echo "  Construisez avec une nouvelle edition (AUXINUX_RELEASE=...+AAAAMMJJ.N)." >&2 \
      || echo "  Augmentez la version dans packages/auxinux-center/Cargo.toml (et la metainfo)." >&2
    exit 73
  fi
done
[[ -n "$(published_version auxinux-office "${INDEX}")" ]] \
  || echo "AVERTISSEMENT: auxinux-office absent de l'index AVANT publication." >&2

echo "==> Paquets sur ${BUILD_HOST}:${REMOTE_DIR}"
declare -A SHA
for pkg in "${PKGS[@]}"; do
  deb="${FILE[${pkg}]}"
  read -r name ver sha <<<"$(ssh "${BUILD_HOST}" \
    "cd '${REMOTE_DIR}' && printf '%s %s %s' \"\$(dpkg-deb -f '${deb}' Package)\" \"\$(dpkg-deb -f '${deb}' Version)\" \"\$(sha256sum '${deb}' | cut -d' ' -f1)\"")"
  [[ -n "${sha:-}" ]] || { echo "ERREUR: ${deb} introuvable sur ${BUILD_HOST}" >&2; exit 66; }
  [[ "${name}" == "${pkg}" && "${ver}" == "${WANT[${pkg}]}" ]] \
    || { echo "ERREUR: ${deb} annonce ${name} ${ver}" >&2; exit 65; }
  SHA["${pkg}"]="${sha}"
  echo "    ${deb}: sha256 ${sha}"
done

if [[ "${DEPLOY}" -ne 1 ]]; then
  echo
  echo "Verifications passees. Relancez avec --deploy pour publier."
  exit 0
fi

echo "==> Transfert en flux (${BUILD_HOST} -> ici -> ${REPO_HOST}:~/${PUB_DIR}/incoming)"
ssh "${REPO_HOST}" "mkdir -p '${PUB_DIR}/incoming'"
ARGS=()
for pkg in "${PKGS[@]}"; do
  deb="${FILE[${pkg}]}"
  ssh "${BUILD_HOST}" "cat '${REMOTE_DIR}/${deb}'" \
    | ssh "${REPO_HOST}" "cat > '${PUB_DIR}/incoming/${deb}'"
  got="$(ssh "${REPO_HOST}" "sha256sum '${PUB_DIR}/incoming/${deb}' | cut -d' ' -f1")"
  if [[ "${got}" != "${SHA[${pkg}]}" ]]; then
    echo "ERREUR: empreinte differente apres transfert de ${deb}." >&2
    ssh "${REPO_HOST}" "rm -f '${PUB_DIR}/incoming/${deb}'"
    exit 65
  fi
  ARGS+=("incoming/${deb}")
done

echo "==> Index, signature et deploiement (publish-repo.sh, suite APPS)"
ssh "${REPO_HOST}" "cd '${PUB_DIR}' && ./publish-repo.sh ${ARGS[*]} --deploy"

echo "==> Verification de l'index servi"
INDEX="$(curl -fsS "${PACKAGES_URL}")"
fail=0
for pkg in auxi auxinux-center auxinuxos-release; do
  got="$(published_version "${pkg}" "${INDEX}")"
  echo "    ${pkg}: ${got:-(absent)}"
  [[ "${got}" == "${WANT[${pkg}]}" ]] || fail=1
done
office="$(published_version auxinux-office "${INDEX}")"
echo "    auxinux-office: ${office:-(absent)}"
[[ -n "${office}" ]] || { echo "ERREUR: auxinux-office a disparu de l'index APPS" >&2; fail=1; }

for pkg in "${PKGS[@]}"; do
  file="$(awk -v p="${pkg}" -v v="${WANT[${pkg}]}" '
    $1 == "Package:" { cur = $2; ver = "" }
    $1 == "Version:" { ver = $2 }
    $1 == "Filename:" && cur == p && ver == v { print $2 }
  ' <<<"${INDEX}" | head -n1)"
  [[ -n "${file}" ]] || { echo "ERREUR: ${pkg} ${WANT[${pkg}]} sans Filename dans l'index" >&2; fail=1; continue; }
  served="$(curl -fsS "${BASE_URL}/${file}" | sha256sum | cut -d' ' -f1)"
  echo "    ${BASE_URL}/${file}: sha256 ${served}"
  [[ "${served}" == "${SHA[${pkg}]}" ]] || { echo "ERREUR: ${file} servi differe de la source" >&2; fail=1; }
done

[[ "${fail}" -eq 0 ]] || exit 70
echo
echo "Publie dans la suite APPS: ${PKGS[*]} (edition ${RELEASE})."
echo "Les machines le recoivent par « auxi os upgrade » / le centre de controle."
