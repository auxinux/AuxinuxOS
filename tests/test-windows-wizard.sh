#!/usr/bin/env bash
#
# Test de l'assistant d'ouverture des fichiers .exe.
#
# Le point critique verifie ici: l'assistant ne doit JAMAIS utiliser le prefixe
# Wine partage ~/.wine. C'est ce que faisait la version precedente, et une
# seule application cassee y rendait toutes les autres inutilisables.
#
# zenity et wine sont remplaces par des stubs sur le PATH: le test valide la
# LOGIQUE et les chemins, pas le rendu graphique.
#
# Usage: bash tests/test-windows-wizard.sh
set -uo pipefail

WIZARD="${WIZARD:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/windows-support/auxinux-windows-wizard}"
[[ -x "${WIZARD}" ]] || { echo "assistant introuvable: ${WIZARD}" >&2; exit 66; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
STUBS="${WORK}/bin"
mkdir -p "${STUBS}"

# Journal des appels wine, pour inspecter WINEPREFIX.
cat > "${STUBS}/wine" <<'STUB'
#!/usr/bin/env bash
printf 'WINEPREFIX=%s\n' "${WINEPREFIX:-<absent>}" >> "${WINE_LOG}"
printf 'OVERRIDES=%s\n' "${WINEDLLOVERRIDES:-<absent>}" >> "${WINE_LOG}"
printf 'TARGET=%s\n' "$1" >> "${WINE_LOG}"
STUB
chmod +x "${STUBS}/wine"

# zenity pilote par ZENITY_LIST (reponse a --list) et ZENITY_ANSWER (--question).
cat > "${STUBS}/zenity" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "${arg}" in
    --list)     printf '%s\n' "${ZENITY_LIST:-}"; exit 0 ;;
    --question) exit "${ZENITY_ANSWER:-1}" ;;
  esac
done
exit 0
STUB
chmod +x "${STUBS}/zenity"

export HOME="${WORK}/home"
mkdir -p "${HOME}"
export WINE_LOG="${WORK}/wine.log"
: > "${WINE_LOG}"

run_wizard() { PATH="${STUBS}:${PATH}" "${WIZARD}" "$@"; }

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

echo "== 1. Aucun argument =="
ZENITY_LIST="" run_wizard >/dev/null 2>&1
check "sort en 64" "$?" "64"

echo "== 2. Fichier inexistant =="
ZENITY_LIST="" run_wizard "${WORK}/absent.exe" >/dev/null 2>&1
check "sort en 66" "$?" "66"

echo "== 3. zenity absent: erreur explicite, pas de repli silencieux =="
PATH="/usr/bin:/bin" "${WIZARD}" "${WORK}/x.exe" >/dev/null 2>&1
check "sort en 69" "$?" "69"

echo "== 4. Annulation de la liste =="
printf 'MZ' > "${WORK}/Setup Jeu (v2).exe"
ZENITY_LIST="" run_wizard "${WORK}/Setup Jeu (v2).exe" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "wine non appele" "$(wc -l < "${WINE_LOG}")" "0"

echo "== 5. Wine: prefixe dedie, jamais ~/.wine (cas critique) =="
: > "${WINE_LOG}"
ZENITY_LIST="Lancer directement avec Wine (dernier recours)" ZENITY_ANSWER=0 \
  run_wizard "${WORK}/Setup Jeu (v2).exe" >/dev/null 2>&1
prefix="$(grep '^WINEPREFIX=' "${WINE_LOG}" | head -1 | cut -d= -f2-)"
check "wine a ete appele" "$([[ -s "${WINE_LOG}" ]] && echo oui)" "oui"
check "~/.wine NON cree" "$([[ -e "${HOME}/.wine" ]] && echo cree || echo absent)" "absent"
check "prefixe sous auxinux/wine-prefixes" \
  "$(case "${prefix}" in */auxinux/wine-prefixes/*) echo oui;; *) echo "non:${prefix}";; esac)" "oui"
check "nom de prefixe assaini" "$(basename "${prefix}")" "Setup-Jeu--v2"
check "le prefixe existe" "$([[ -d "${prefix}" ]] && echo oui)" "oui"
check "mono/gecko desactives" "$(grep '^OVERRIDES=' "${WINE_LOG}" | cut -d= -f2-)" "mscoree,mshtml="

echo "== 6. Wine: refus de la confirmation =="
: > "${WINE_LOG}"
ZENITY_LIST="Lancer directement avec Wine (dernier recours)" ZENITY_ANSWER=1 \
  run_wizard "${WORK}/Setup Jeu (v2).exe" >/dev/null 2>&1
check "wine non appele" "$(wc -l < "${WINE_LOG}")" "0"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
