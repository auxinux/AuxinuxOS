#!/usr/bin/env bash
#
# auxinux-session-helper: le bureau ouvert a la connexion (AuxiNux Shell ou
# KDE Plasma), choisi dans les Reglages du centre.
#
# DEMANDE A L'ORIGINE (2026-10-10, aporler): AuxiNux Shell devient le bureau
# par defaut; le centre permet de choisir KDE Plasma ou AuxiNux Shell. SDDM
# memorise la derniere session ouverte: ecrire seulement DefaultSession ne
# changerait rien pour un compte qui a deja ouvert l'autre bureau.
#
# Usage: bash tests/test-session-helper.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="${ROOT}/packages/auxinux-center/helper/auxinux-session-helper"
[[ "${EUID}" -ne 0 ]] || { echo "hors root seulement"; exit 0; }
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export AUXINUX_SESSION_TEST_ROOT="${WORK}"
mkdir -p "${WORK}/wayland-sessions" "${WORK}/sddm"
touch "${WORK}/wayland-sessions/auxinux.desktop" "${WORK}/wayland-sessions/plasma.desktop"
CONF="${WORK}/sddm.conf.d/20-auxinux-session.conf"
STATE="${WORK}/sddm/state.conf"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
run() { "$@" >/dev/null 2>&1; echo $?; }

echo "== 1. Session par defaut =="
check "plasma accepte" "$(run "${H}" plasma)" "0"
check "DefaultSession ecrit dans [General]" "$(grep -A1 '^\[General\]$' "${CONF}" | tail -n1)" "DefaultSession=plasma.desktop"
check "pas de state.conf: aucun cree" "$([[ -e ${STATE} ]] && echo oui || echo non)" "non"
check "auxinux accepte" "$(run "${H}" auxinux)" "0"
check "remplace, pas d'ajout" "$(grep -c DefaultSession "${CONF}")/$(grep -c auxinux.desktop "${CONF}")" "1/1"

echo "== 2. Derniere session memorisee par SDDM =="
printf '[Last]\nSession=/usr/share/wayland-sessions/plasma.desktop\nUser=marie\n' >"${STATE}"
run "${H}" auxinux >/dev/null
check "chemin complet conserve comme format" "$(grep '^Session=' "${STATE}")" "Session=${WORK}/wayland-sessions/auxinux.desktop"
check "User conserve" "$(grep -c '^User=marie$' "${STATE}")" "1"
printf '[Last]\nUser=marie\nSession=plasma.desktop\n' >"${STATE}"
run "${H}" auxinux >/dev/null
check "nom de fichier conserve comme format" "$(grep '^Session=' "${STATE}")" "Session=auxinux.desktop"
printf '[Last]\nUser=marie\n\n[Autre]\nX=1\n' >"${STATE}"
run "${H}" plasma >/dev/null
check "Session ajoutee dans [Last] si absente" "$(awk '/^\[Last\]/{f=1;next} /^\[/{f=0} f && /^Session=/' "${STATE}")" "Session=${WORK}/wayland-sessions/plasma.desktop"
check "autres sections intactes" "$(grep -c '^X=1$' "${STATE}")" "1"
printf '[General]\nFoo=1\n' >"${STATE}"
run "${H}" plasma >/dev/null
check "section [Last] creee si absente" "$(grep -A1 '^\[Last\]$' "${STATE}" | tail -n1)" "Session=${WORK}/wayland-sessions/plasma.desktop"

echo "== 3. Refus =="
check "bureau inconnu" "$(run "${H}" gnome)" "64"
check "argument deguise" "$(run "${H}" '../../etc/passwd')" "64"
check "sans argument" "$(run "${H}")" "64"
rm "${WORK}/wayland-sessions/plasma.desktop"
check "bureau non installe" "$(run "${H}" plasma)" "64"
check "rien n'a change" "$(grep DefaultSession "${CONF}")" "DefaultSession=plasma.desktop"

echo "== 4. Politique et paquet =="
POLICY="${ROOT}/packages/auxinux-center/helper/ca.auxinux.center.policy"
check "action polkit dediee" "$(grep -c 'auxinux-session-helper</annotate>' "${POLICY}")" "1"
check "empaquete" "$(grep -c 'usr/libexec/auxinux/auxinux-session-helper"$' "${ROOT}/packages/build-debs.sh")" "1"
check "AuxiNux Shell par defaut (auxinuxos-release)" \
  "$(grep -c '^DefaultSession=auxinux.desktop$' "${ROOT}/packages/release/root/etc/sddm.conf.d/10-auxinux.conf")" "1"
check "live: autologin sur AuxiNux Shell" \
  "$(grep -c '^Session=auxinux$' "${ROOT}/image-builder/build-image.sh")" "1"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
