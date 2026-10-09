#!/usr/bin/env bash
#
# Tests de coherence de la version affichee.
#
# POURQUOI: le passage de « AuxiNux OS EN 0.1-BETA » a « AuxiNux OS 0.2.0 » a
# demande de toucher NEUF fichiers, dont trois qui ne sont lus que par GRUB ou
# par l'installateur. Une version oubliee ne casse rien: elle s'affiche, c'est
# tout -- et c'est precisement pour ca qu'elle survit a une release.
#
# Ce test prend `os-release` comme SOURCE DE VERITE et exige que tous les
# autres emplacements s'alignent dessus. Il verifie aussi qu'aucune mention
# d'« edition » ne revient: la notion a ete abandonnee en 0.2.0.
#
# Les emplacements absents sont SAUTES, pas echoues: les fichiers de Calamares
# disparaitront avec l'installateur maison, et ce test ne doit pas devenir la
# raison de les garder.
#
# Usage: bash tests/test-version-consistency.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_RELEASE="${ROOT}/packages/release/root/usr/lib/os-release"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
contains() {
  local label="$1" file="$2" needle="$3"
  if [[ ! -f "${file}" ]]; then echo "  SAUTE $label (absent: ${file#${ROOT}/})"; return; fi
  if grep -qF -- "${needle}" "${file}"; then echo "  OK   $label"
  else echo "  ECHEC $label: [${needle}] absent de ${file#${ROOT}/}"; fail=1; fi
}

echo "== source de verite =="
if [[ ! -f "${OS_RELEASE}" ]]; then
  echo "  ECHEC os-release introuvable: ${OS_RELEASE}"; exit 1
fi
VERSION="$(sed -n 's/^VERSION="\([^ ]*\) .*/\1/p' "${OS_RELEASE}")"
check "VERSION lisible dans os-release" "$([[ -n ${VERSION} ]] && echo oui || echo non)" "oui"
echo "  version de reference: ${VERSION}"
PRETTY="AuxiNux OS ${VERSION}"
check "PRETTY_NAME aligne" \
  "$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' "${OS_RELEASE}")" "${PRETTY}"

echo "== affichage systeme =="
contains "/etc/issue"     "${ROOT}/image-builder/overlays/etc/issue"     "${PRETTY}"
contains "/etc/issue.net" "${ROOT}/image-builder/overlays/etc/issue.net" "${PRETTY}"

echo "== construction de l'ISO =="
BUILD="${ROOT}/image-builder/build-image.sh"
contains "nom de l'ISO"      "${BUILD}" "auxinuxos-${VERSION}-amd64.iso"
contains "profil de build"   "${BUILD}" "PROFILE=\"${VERSION}-live\""
# Deux entrees principales depuis le 2026-10-02: installer (par defaut) et
# essayer le bureau live.
contains "menu GRUB: installer" "${BUILD}" "menuentry \"Installer ${PRETTY} maintenant"
contains "menu GRUB: live"      "${BUILD}" "menuentry \"Essayer ${PRETTY} (bureau live)"

echo "== installateur (si present) =="
contains "branding versionedName" \
  "${ROOT}/image-builder/overlays/etc/calamares/branding/auxinuxos/branding.desc" "${PRETTY}"
contains "branding version" \
  "${ROOT}/image-builder/overlays/etc/calamares/branding/auxinuxos/branding.desc" "version:             ${VERSION}"

# Controle EXHAUSTIF du branding, et non champ par champ.
#
# `shortVersionedName: AuxiNux OS 0.1` a survecu au passage en 0.2.0: il ne
# contenait pas « 0.1-BETA », donc le renommage ne l'a pas vu, et ce test ne
# regardait que deux champs sur trois. Resultat: Calamares demandait a
# l'utilisateur de confirmer l'installation d'« AuxiNux OS 0.1 » -- signale par
# aporler pendant une vraie installation.
#
# On refuse desormais TOUTE version qui n'est pas la version courante,
# n'importe ou dans le fichier.
BRANDING="${ROOT}/image-builder/overlays/etc/calamares/branding/auxinuxos/branding.desc"
if [[ -f "${BRANDING}" ]]; then
  strays="$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z]+)?' "${BRANDING}" \
            | grep -vFx "${VERSION}" | sort -u | paste -sd' ')"
  check "branding: aucune autre version que ${VERSION}" "${strays:-aucune}" "aucune"
fi

echo "== plus aucune « edition » =="
hits="$(cd "${ROOT}" && git ls-files \
  | grep -vE '^(LICENSE|tests/test-version-consistency\.sh|README\.md|image-builder/(assets|keys)/)' \
  | xargs grep -lIE 'AuxiNux ?OS EN|Edition-Normal|[EÉ]dition normale' 2>/dev/null)"
check "aucune mention d'edition" "$([[ -z ${hits} ]] && echo aucune || echo "${hits}")" "aucune"

echo "== adresse du projet =="
# Le site du projet est https://os.auxinux.ca/auxinuxos (aporler, 2026-10-06).
# https://auxinux.ca/ etait affiche partout: os-release, Calamares, centre.
# dep., git. et repo@ sont d'autres services, legitimes.
hits="$(cd "${ROOT}" && git ls-files \
  | grep -vFx 'tests/test-version-consistency.sh' \
  | xargs grep -lIE 'https?://(www\.)?auxinux\.ca' 2>/dev/null)"
check "aucun lien vers auxinux.ca au lieu de os.auxinux.ca/auxinuxos" \
  "$([[ -z ${hits} ]] && echo aucun || echo "${hits}")" "aucun"
check "os-release: HOME_URL" \
  "$(grep -c '^HOME_URL="https://os.auxinux.ca/auxinuxos"$' "${ROOT}/packages/release/root/usr/lib/os-release")" "1"

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; fi
exit "${fail}"
