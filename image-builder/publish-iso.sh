#!/usr/bin/env bash
# Publie une ISO construite sur l'hote de build vers le depot public.
#
# POURQUOI UN SCRIPT: la publication du 2026-09-10 a ete faite a la main, et
# trois details ne se devinent pas.
#
#   1. L'hote de build N'A PAS de cle SSH vers l'hote de depot. Le transfert
#      passe donc EN FLUX par la machine qui lance ce script, sans fichier
#      intermediaire.
#   2. Le fichier arrive sous un nom cache (`.nom.part`) et n'est renomme
#      qu'APRES comparaison des empreintes des deux cotes. nginx sert le
#      repertoire avec autoindex: un fichier visible est un fichier
#      telechargeable, donc un fichier tronque serait telecharge.
#   3. Le nom porte la DATE. Ecraser une ISO deja publiee laisse les caches et
#      les liens existants servir un contenu different sous le meme nom.
#
# Usage:
#   publish-iso.sh --iso CHEMIN_DISTANT [--name NOM] [--deploy]
#
#   --iso     chemin de l'ISO SUR l'hote de build (obligatoire)
#   --name    nom publie (defaut: <base>-<AAAAMMJJ>-amd64.iso deduit de l'ISO)
#   --deploy  effectue reellement la publication; sans cette option, le script
#             se contente de verifier et d'afficher ce qu'il ferait
set -euo pipefail

BUILD_HOST="${AUXINUX_BUILD_HOST:-virtua-dev}"
REPO_HOST="${AUXINUX_REPO_HOST:-virtua-repo}"
REPO_DIR="${AUXINUX_REPO_DIR:-/var/www/dep.auxinux.ca/DOWNLOAD/ISO}"
PUBLIC_URL="${AUXINUX_PUBLIC_URL:-https://dep.auxinux.ca/DOWNLOAD/ISO}"

ISO_REMOTE=""
PUBLISH_NAME=""
DEPLOY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso)    ISO_REMOTE="${2:?--iso demande un chemin}"; shift 2 ;;
    --name)   PUBLISH_NAME="${2:?--name demande un nom}"; shift 2 ;;
    --deploy) DEPLOY=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "argument inconnu: $1" >&2; exit 64 ;;
  esac
done

[[ -n "${ISO_REMOTE}" ]] || { echo "--iso est obligatoire" >&2; exit 64; }

base="$(basename "${ISO_REMOTE}")"
if [[ -z "${PUBLISH_NAME}" ]]; then
  # auxinuxos-0.2.0-amd64.iso -> auxinuxos-0.2.0-20260912-amd64.iso
  PUBLISH_NAME="${base%-amd64.iso}-$(date +%Y%m%d)-amd64.iso"
fi

echo "==> Source : ${BUILD_HOST}:${ISO_REMOTE}"
echo "==> Cible  : ${REPO_HOST}:${REPO_DIR}/${PUBLISH_NAME}"

read -r SIZE SHA_SRC <<<"$(ssh "${BUILD_HOST}" "stat -c %s '${ISO_REMOTE}' && sha256sum '${ISO_REMOTE}' | cut -d' ' -f1" | paste -sd' ')"
[[ -n "${SIZE}" && -n "${SHA_SRC}" ]] || { echo "ISO introuvable sur ${BUILD_HOST}" >&2; exit 66; }
echo "    taille : ${SIZE} octets"
echo "    sha256 : ${SHA_SRC}"

# Refus d'ecraser: le nom date est justement la pour que ca n'arrive pas.
if ssh "${REPO_HOST}" "test -e '${REPO_DIR}/${PUBLISH_NAME}'"; then
  echo "ERREUR: ${PUBLISH_NAME} existe deja sur le depot." >&2
  echo "  Choisissez un autre nom (--name) plutot que d'ecraser une ISO publiee." >&2
  exit 73
fi

if [[ "${DEPLOY}" -ne 1 ]]; then
  echo
  echo "Verifications passees. Relancez avec --deploy pour publier."
  exit 0
fi

echo "==> Transfert en flux (${BUILD_HOST} -> ici -> ${REPO_HOST})"
ssh "${BUILD_HOST}" "cat '${ISO_REMOTE}'" \
  | ssh "${REPO_HOST}" "cat > '${REPO_DIR}/.${PUBLISH_NAME}.part'"

read -r SIZE_DST SHA_DST <<<"$(ssh "${REPO_HOST}" "stat -c %s '${REPO_DIR}/.${PUBLISH_NAME}.part' && sha256sum '${REPO_DIR}/.${PUBLISH_NAME}.part' | cut -d' ' -f1" | paste -sd' ')"
echo "    taille recue : ${SIZE_DST}"
echo "    sha256 recu  : ${SHA_DST}"

if [[ "${SHA_SRC}" != "${SHA_DST}" || "${SIZE}" != "${SIZE_DST}" ]]; then
  echo "ERREUR: empreinte differente apres transfert. Fichier partiel supprime." >&2
  ssh "${REPO_HOST}" "rm -f '${REPO_DIR}/.${PUBLISH_NAME}.part'"
  exit 65
fi

echo "==> Publication (renommage atomique) + fichier .sha256"
ssh "${REPO_HOST}" "
  set -e
  mv '${REPO_DIR}/.${PUBLISH_NAME}.part' '${REPO_DIR}/${PUBLISH_NAME}'
  chmod 0664 '${REPO_DIR}/${PUBLISH_NAME}'
  printf '%s  %s\n' '${SHA_SRC}' '${PUBLISH_NAME}' > '${REPO_DIR}/${PUBLISH_NAME}.sha256'
  chmod 0664 '${REPO_DIR}/${PUBLISH_NAME}.sha256'
"

echo "==> Verification HTTP"
code="$(curl -sS -o /dev/null -w '%{http_code}' -r 0-0 "${PUBLIC_URL}/${PUBLISH_NAME}")"
len="$(curl -sSI "${PUBLIC_URL}/${PUBLISH_NAME}" | awk 'tolower($1) == "content-length:" { print $2 }' | tr -d '\r')"
echo "    HTTP ${code}, Content-Length ${len}"
[[ "${code}" == "200" || "${code}" == "206" ]] || { echo "ERREUR: l'ISO n'est pas servie" >&2; exit 70; }
[[ "${len}" == "${SIZE}" ]] || { echo "ERREUR: taille servie differente de la source" >&2; exit 70; }
curl -sS "${PUBLIC_URL}/${PUBLISH_NAME}.sha256"

echo
echo "Publie: ${PUBLIC_URL}/${PUBLISH_NAME}"
