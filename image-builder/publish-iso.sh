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
# LIENS FIXES (2026-10-27): le site os.auxinux.ca pointe toujours vers
# auxinuxos-<ARCH>.iso (et .iso.sha256). Ce ne sont PAS des fichiers: nginx
# redirige (302) vers l'ISO datee, par un extrait par architecture,
# /etc/nginx/snippets/auxinuxos-iso-<ARCH>.conf, que ce script reecrit apres la
# publication. Une redirection et non un lien symbolique: le fichier telecharge
# garde son nom date, et une reprise de telechargement ne peut pas recoller
# deux ISO differentes sous le meme nom (raison 3). A cote, la fiche
# auxinuxos-<ARCH>.json (version, noyau, Debian, Shell, applications,
# nouveautes, taille, sha256), tiree de l'ISO par scripts/iso-manifest.py: le
# site l'affiche, plus rien n'est recopie a la main.
#
# Usage:
#   publish-iso.sh --iso CHEMIN_DISTANT [--name NOM] [--arch ARCH] [--deploy]
#   publish-iso.sh --iso CHEMIN_DISTANT --name NOM_PUBLIE --relink [--arch ARCH] [--deploy]
#
#   --iso     chemin de l'ISO SUR l'hote de build (obligatoire)
#   --name    nom publie (defaut: <base>-<AAAAMMJJ>-<ARCH>.iso deduit de l'ISO)
#   --arch    architecture de l'ISO: amd64 (defaut) ou arm64 (Edition ARM);
#             fixe le suffixe du nom et l'index APPS verifie (binary-<ARCH>)
#   --relink  l'ISO est DEJA publiee sous NOM_PUBLIE (verifie par sha256):
#             ne refait que la fiche et les liens fixes
#   --deploy  effectue reellement la publication; sans cette option, le script
#             se contente de verifier et d'afficher ce qu'il ferait
set -euo pipefail

BUILD_HOST="${AUXINUX_BUILD_HOST:-virtua-dev}"
REPO_HOST="${AUXINUX_REPO_HOST:-virtua-repo}"
REPO_DIR="${AUXINUX_REPO_DIR:-/var/www/dep.auxinux.ca/DOWNLOAD/ISO}"
PUBLIC_URL="${AUXINUX_PUBLIC_URL:-https://dep.auxinux.ca/DOWNLOAD/ISO}"
# Chemin URL du repertoire, pour les `location` nginx.
URL_PATH="/${PUBLIC_URL#https://*/}"
NGINX_SNIPPETS="${AUXINUX_NGINX_SNIPPETS:-/etc/nginx/snippets}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISO_REMOTE=""
PUBLISH_NAME=""
ARCH="amd64"
DEPLOY=0
RELINK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso)    ISO_REMOTE="${2:?--iso demande un chemin}"; shift 2 ;;
    --name)   PUBLISH_NAME="${2:?--name demande un nom}"; shift 2 ;;
    --arch)   ARCH="${2:?--arch demande une architecture}"; shift 2 ;;
    --relink) RELINK=1; shift ;;
    --deploy) DEPLOY=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "argument inconnu: $1" >&2; exit 64 ;;
  esac
done

[[ -n "${ISO_REMOTE}" ]] || { echo "--iso est obligatoire" >&2; exit 64; }
case "${ARCH}" in
  amd64|arm64) ;;
  *) echo "architecture non prise en charge: ${ARCH} (amd64 ou arm64)" >&2; exit 64 ;;
esac

base="$(basename "${ISO_REMOTE}")"
if [[ "${RELINK}" -eq 1 && -z "${PUBLISH_NAME}" ]]; then
  echo "--relink demande --name (le nom sous lequel l'ISO est deja publiee)" >&2
  exit 64
fi

# Edition inscrite dans l'ISO par build-image.sh (/.disk/auxinux-release):
# 0.2.0+20261009.2. Depuis le 2026-10-09, chaque ISO publiee est une version
# annoncee aux machines installees par le paquet auxinuxos-release du meme
# numero: le nom publie en decoule, et ce paquet doit deja etre publie.
RELEASE="$(ssh "${BUILD_HOST}" "t=\$(mktemp); xorriso -osirrox on -indev '${ISO_REMOTE}' -extract /.disk/auxinux-release \"\$t\" >/dev/null 2>&1; cat \"\$t\" 2>/dev/null; rm -f \"\$t\"" | tr -d '[:space:]')"
if [[ -n "${RELEASE}" ]]; then
  echo "==> Edition: ${RELEASE}"
  if [[ -z "${PUBLISH_NAME}" ]]; then
    # 0.2.0+20261009.2 -> auxinuxos-0.2.0-20261009-2-amd64.iso
    ver="${RELEASE%%+*}"; id="${RELEASE#*+}"
    PUBLISH_NAME="auxinuxos-${ver}-${id//./-}-${ARCH}.iso"
  fi
  APPS_INDEX="${AUXINUX_APPS_INDEX:-https://dep.auxinux.ca/AUXINUXOS/dists/APPS/main/binary-${ARCH}/Packages}"
  # --relink: l'ISO est deja en ligne, et son edition a pu etre remplacee
  # depuis dans APPS (l'ARM 20261025 l'etait le 2026-10-27).
  if [[ "${RELINK}" -eq 0 ]] && ! curl -fsS "${APPS_INDEX}" | awk -v r="${RELEASE}" '
        $1 == "Package:" { p = $2 } $1 == "Version:" && p == "auxinuxos-release" && $2 == r { f = 1 }
        END { exit !f }'; then
    echo "ERREUR: auxinuxos-release ${RELEASE} n'est pas publie dans la suite APPS." >&2
    echo "  Publiez d'abord les paquets de cette construction:" >&2
    echo "  packages/publish-debs.sh --dir <dossier des .deb> --deploy" >&2
    echo "  Sans lui, les machines installees ne verraient jamais cette version." >&2
    exit 73
  fi
else
  echo "AVERTISSEMENT: ISO sans /.disk/auxinux-release (construite avant le 2026-10-09)." >&2
fi
if [[ -z "${PUBLISH_NAME}" ]]; then
  # auxinuxos-0.2.0-amd64.iso -> auxinuxos-0.2.0-20260912-amd64.iso
  PUBLISH_NAME="${base%-"${ARCH}".iso}-$(date +%Y%m%d)-${ARCH}.iso"
fi

echo "==> Source : ${BUILD_HOST}:${ISO_REMOTE}"
echo "==> Cible  : ${REPO_HOST}:${REPO_DIR}/${PUBLISH_NAME}"

read -r SIZE SHA_SRC <<<"$(ssh "${BUILD_HOST}" "stat -c %s '${ISO_REMOTE}' && sha256sum '${ISO_REMOTE}' | cut -d' ' -f1" | paste -sd' ')"
[[ -n "${SIZE}" && -n "${SHA_SRC}" ]] || { echo "ISO introuvable sur ${BUILD_HOST}" >&2; exit 66; }
echo "    taille : ${SIZE} octets"
echo "    sha256 : ${SHA_SRC}"

# Refus d'ecraser: le nom date est justement la pour que ca n'arrive pas.
if [[ "${RELINK}" -eq 1 ]]; then
  SHA_PUB="$(ssh "${REPO_HOST}" "sha256sum '${REPO_DIR}/${PUBLISH_NAME}' 2>/dev/null | cut -d' ' -f1")"
  if [[ "${SHA_PUB}" != "${SHA_SRC}" ]]; then
    echo "ERREUR: ${PUBLISH_NAME} absente du depot ou differente de ${ISO_REMOTE}." >&2
    exit 73
  fi
  echo "==> Deja publiee, identique: seuls la fiche et les liens fixes seront refaits"
elif ssh "${REPO_HOST}" "test -e '${REPO_DIR}/${PUBLISH_NAME}'"; then
  echo "ERREUR: ${PUBLISH_NAME} existe deja sur le depot." >&2
  echo "  Choisissez un autre nom (--name) plutot que d'ecraser une ISO publiee." >&2
  exit 73
fi

# Fiche de l'ISO, tiree de son squashfs SUR l'hote de build (lecture a
# l'offset du squashfs dans l'ISO: rien n'est copie, ~2 s).
echo "==> Fiche de l'ISO"
MANIFEST="$(ssh "${BUILD_HOST}" "
  set -e
  t=\$(mktemp -d); trap 'rm -rf \"\$t\"' EXIT
  cat > \"\$t/iso-manifest.py\"
  lba=\$(xorriso -indev '${ISO_REMOTE}' -find /live/filesystem.squashfs -exec report_lba -- 2>/dev/null \\
        | awk -F, '/filesystem.squashfs/ { print \$2 + 0 }')
  [ -n \"\$lba\" ]
  off=\$((lba * 2048))
  unsquashfs -q -n -o \"\$off\" -d \"\$t/r\" '${ISO_REMOTE}' var/lib/dpkg/status etc/debian_version >/dev/null
  noyaux=\$(unsquashfs -lc -o \"\$off\" '${ISO_REMOTE}' boot | sed -n 's|.*/boot/\\(vmlinuz-[^/]*\\)\$|\\1|p')
  python3 \"\$t/iso-manifest.py\" \"\$t/r\" '${ARCH}' \$noyaux
" < "${SCRIPT_DIR}/scripts/iso-manifest.py")"
python3 -c 'import json, sys; f = json.loads(sys.argv[1])
print("    %s %s, noyau %s, Debian %s" % (f["edition"], f["architecture"], f["noyau"]["version"], f["debian"]["version"]))' "${MANIFEST}"

if [[ "${DEPLOY}" -ne 1 ]]; then
  echo
  echo "Verifications passees. Relancez avec --deploy pour publier."
  exit 0
fi

if [[ "${RELINK}" -eq 0 ]]; then
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
fi

# --- Liens fixes et fiche ------------------------------------------------------
STABLE="auxinuxos-${ARCH}"
SNIPPET="${NGINX_SNIPPETS}/auxinuxos-iso-${ARCH}.conf"

echo "==> Liens fixes ${STABLE}.iso -> ${PUBLISH_NAME} (${SNIPPET})"
# Ancien extrait garde de cote: rendu si nginx refuse le nouveau. Les liens
# d'abord, la fiche ensuite: si nginx refuse, la fiche decrit encore l'ISO
# vers laquelle pointe le lien fixe.
ssh "${REPO_HOST}" "
  set -e
  sudo -n test -f '${SNIPPET}' && sudo -n cp -p '${SNIPPET}' '${SNIPPET}.precedent' || true
  sudo -n tee '${SNIPPET}' >/dev/null <<'EOF'
# ECRIT PAR publish-iso.sh (depot AuxinuxOS) -- ne pas modifier a la main.
# ${STABLE}.iso -> ${PUBLISH_NAME}
location = ${URL_PATH}/${STABLE}.iso {
    add_header Cache-Control \"no-cache\" always;
    return 302 ${PUBLIC_URL}/${PUBLISH_NAME};
}
location = ${URL_PATH}/${STABLE}.iso.sha256 {
    add_header Cache-Control \"no-cache\" always;
    return 302 ${PUBLIC_URL}/${PUBLISH_NAME}.sha256;
}
location = ${URL_PATH}/${STABLE}.json {
    add_header Cache-Control \"no-cache\" always;
    add_header Access-Control-Allow-Origin \"*\" always;
    default_type application/json;
    charset utf-8;
    charset_types application/json;
    try_files \$uri =404;
}
EOF
  if ! sudo -n /usr/sbin/nginx -t 2>/tmp/publish-iso-nginx.err; then
    cat /tmp/publish-iso-nginx.err >&2
    if sudo -n test -f '${SNIPPET}.precedent'; then sudo -n mv '${SNIPPET}.precedent' '${SNIPPET}'; else sudo -n rm -f '${SNIPPET}'; fi
    exit 1
  fi
  sudo -n systemctl reload nginx
" || { echo "ERREUR: configuration nginx refusee; extrait precedent remis en place" >&2; exit 70; }

echo "==> Fiche ${STABLE}.json"
PUBLIE_LE="$(ssh "${REPO_HOST}" "date -u -d @\$(stat -c %Y '${REPO_DIR}/${PUBLISH_NAME}') +%Y-%m-%dT%H:%M:%SZ")"
python3 - "${MANIFEST}" "${PUBLISH_NAME}" "${SIZE}" "${SHA_SRC}" "${PUBLIE_LE}" "${PUBLIC_URL}" "${STABLE}" <<'PY' \
  | ssh "${REPO_HOST}" "cat > '${REPO_DIR}/.${STABLE}.json.part' && chmod 0664 '${REPO_DIR}/.${STABLE}.json.part' && mv '${REPO_DIR}/.${STABLE}.json.part' '${REPO_DIR}/${STABLE}.json'"
import json, sys
fiche, nom, taille, sha, publie, url, stable = sys.argv[1:]
fiche = json.loads(fiche)
fiche.update({
    "fichier": nom,
    "taille": int(taille),
    "sha256": sha,
    "publiee": publie,
    "url": f"{url}/{nom}",
    "url_sha256": f"{url}/{nom}.sha256",
    "lien_fixe": f"{url}/{stable}.iso",
    "lien_fixe_sha256": f"{url}/{stable}.iso.sha256",
})
json.dump(fiche, sys.stdout, ensure_ascii=False, indent=2)
print()
PY

echo "==> Verification des liens fixes"
for suffixe in "" ".sha256"; do
  cible="$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' "${PUBLIC_URL}/${STABLE}.iso${suffixe}")"
  echo "    ${STABLE}.iso${suffixe} -> ${cible}"
  [[ "${cible}" == "302 ${PUBLIC_URL}/${PUBLISH_NAME}${suffixe}" ]] \
    || { echo "ERREUR: le lien fixe ne redirige pas vers ${PUBLISH_NAME}${suffixe}" >&2
         echo "  L'extrait est-il inclus dans le server{} de dep.auxinux.ca ?" >&2
         echo "  include ${NGINX_SNIPPETS}/auxinuxos-iso-*.conf;" >&2; exit 70; }
done
curl -fsS "${PUBLIC_URL}/${STABLE}.json" | python3 -c '
import json, sys
f = json.load(sys.stdin)
assert f["fichier"] == sys.argv[1] and f["sha256"] == sys.argv[2], "fiche servie incorrecte"
print("    " + sys.argv[3] + ".json: " + f["edition"] + ", " + f["fichier"])' "${PUBLISH_NAME}" "${SHA_SRC}" "${STABLE}"

echo
echo "Publie: ${PUBLIC_URL}/${PUBLISH_NAME}"
echo "Lien fixe: ${PUBLIC_URL}/${STABLE}.iso  (fiche: ${PUBLIC_URL}/${STABLE}.json)"
