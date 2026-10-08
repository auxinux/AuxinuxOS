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

# Messages en francais quelle que soit la langue de la machine de test.
export LANG=C.UTF-8 LANGUAGE= LC_ALL= LC_MESSAGES=

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
printf 'ARGS=%s\n' "$*" >> "${WINE_LOG}"
STUB
chmod +x "${STUBS}/wine"

# wineserver -w: l'installateur simule cree un raccourci de menu, comme le
# fait winemenubuilder, si WINE_CREE_MENU est defini.
cat > "${STUBS}/wineserver" <<'STUB'
#!/usr/bin/env bash
echo "wineserver $*" >> "${WINE_LOG}"
if [[ -n "${WINE_CREE_MENU:-}" ]]; then
  d="${HOME}/.local/share/applications/wine/Programs"
  mkdir -p "${d}"
  printf '[Desktop Entry]\nName=%s\n' "${WINE_CREE_MENU}" > "${d}/app.desktop"
fi
STUB
chmod +x "${STUBS}/wineserver"

# Centre de controle et flatpak (Bottles): consignent leurs arguments.
cat > "${STUBS}/auxinux-center" <<'STUB'
#!/usr/bin/env bash
echo "center $*" >> "${WINE_LOG}"
STUB
chmod +x "${STUBS}/auxinux-center"
cat > "${STUBS}/flatpak" <<'STUB'
#!/usr/bin/env bash
echo "flatpak $*" >> "${WINE_LOG}"
case " $* " in
  *" info "*) exit 0 ;;
  *" new --bottle-name "*)
    [[ -n "${BOTTLES_ECHEC:-}" ]] && exit 1
    args="$*"; name="${args##*--bottle-name }"; name="${name%% *}"
    mkdir -p "${HOME}/.var/app/com.usebottles.bottles/data/bottles/bottles/${name}" ;;
esac
exit 0
STUB
chmod +x "${STUBS}/flatpak"

# zenity pilote par ZENITY_LIST (reponse a --list) et ZENITY_ANSWER (--question).
cat > "${STUBS}/zenity" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "${arg}" in
    --list)     printf '%s\n' "${ZENITY_LIST:-}"; exit 0 ;;
    --question) exit "${ZENITY_ANSWER:-1}" ;;
    --info) printf '%s\n' "$@" >> "${ZENITY_LOG}"; exit 0 ;;
  esac
done
exit 0
STUB
chmod +x "${STUBS}/zenity"

export HOME="${WORK}/home"
mkdir -p "${HOME}"
export WINE_LOG="${WORK}/wine.log"
: > "${WINE_LOG}"
export ZENITY_LOG="${WORK}/zenity.log"
: > "${ZENITY_LOG}"
INSTALLER="Installer ce programme (recommandé)"

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
ZENITY_LIST="${INSTALLER}" \
  run_wizard "${WORK}/Setup Jeu (v2).exe" >/dev/null 2>&1
prefix="$(grep '^WINEPREFIX=' "${WINE_LOG}" | head -1 | cut -d= -f2-)"
check "wine a ete appele" "$([[ -s "${WINE_LOG}" ]] && echo oui)" "oui"
check "~/.wine NON cree" "$([[ -e "${HOME}/.wine" ]] && echo cree || echo absent)" "absent"
check "prefixe sous auxinux/wine-prefixes" \
  "$(case "${prefix}" in */auxinux/wine-prefixes/*) echo oui;; *) echo "non:${prefix}";; esac)" "oui"
check "nom de prefixe assaini" "$(basename "${prefix}")" "Setup-Jeu--v2"
check "le prefixe existe" "$([[ -d "${prefix}" ]] && echo oui)" "oui"
check "mono/gecko desactives" "$(grep '^OVERRIDES=' "${WINE_LOG}" | cut -d= -f2-)" "mscoree,mshtml="

echo "== 6. Wine: un paquet .msi passe par msiexec =="
: > "${WINE_LOG}"
printf 'MZ' > "${WORK}/Installeur.msi"
ZENITY_LIST="${INSTALLER}" \
  run_wizard "${WORK}/Installeur.msi" >/dev/null 2>&1
# `wine fichier.msi` echoue: un paquet MSI n'est pas un executable. Le type est
# pourtant associe a cet assistant dans /etc/xdg/mimeapps.list.
check "msiexec /i utilise" \
  "$(grep '^ARGS=' "${WINE_LOG}" | head -1 | cut -d= -f2- | cut -d' ' -f1-2)" "msiexec /i"

echo "== 7. Wine: un raccourci .lnk passe par start /unix =="
: > "${WINE_LOG}"
printf 'L' > "${WORK}/Raccourci.lnk"
ZENITY_LIST="${INSTALLER}" \
  run_wizard "${WORK}/Raccourci.lnk" >/dev/null 2>&1
check "start /unix utilise" \
  "$(grep '^ARGS=' "${WINE_LOG}" | head -1 | cut -d= -f2- | cut -d' ' -f1-2)" "start /unix"

echo "== 8. Installation: un seul clic, puis ce qui a ete ajoute au menu =="
# PANNE (2026-10-08): le choix par defaut ouvrait le centre de controle sur sa
# page d'accueil -- « rien ne se passe ». Le choix par defaut INSTALLE.
: > "${WINE_LOG}"; : > "${ZENITY_LOG}"
ZENITY_LIST="${INSTALLER}" ZENITY_ANSWER=1 WINE_CREE_MENU="Jeu Deluxe" \
  run_wizard "${WORK}/Setup Jeu (v2).exe" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "aucune question de plus: wine appele" "$(grep -c '^TARGET=' "${WINE_LOG}")" "1"
check "attend la fin de tout l'espace Wine" "$(grep -c '^wineserver -w' "${WINE_LOG}")" "1"
check "le programme installe est nomme" "$(grep -c 'Jeu Deluxe' "${ZENITY_LOG}")" "1"

echo "== 9. Alternative Linux: le centre s'ouvre SUR une recherche =="
for cas in "vlc-3.0.20-win64.exe:vlc" "ChromeSetup.exe:chrome" "Setup Jeu (v2).exe:jeu" "obs-studio-30.1-Full-Installer-x64.exe:obs studio"; do
  : > "${WINE_LOG}"
  fichier="${cas%%:*}"; attendu="${cas#*:}"
  printf 'MZ' > "${WORK}/${fichier}"
  ZENITY_LIST="Chercher une alternative Linux" run_wizard "${WORK}/${fichier}" >/dev/null 2>&1
  check "${fichier} -> « ${attendu} »" "$(grep '^center' "${WINE_LOG}")" "center --rechercher ${attendu}"
done

echo "== 10. Bottles: bouteille creee puis installateur lance, sans consigne manuelle =="
: > "${WINE_LOG}"; : > "${ZENITY_LOG}"
ZENITY_LIST="Installer avec Bottles (jeux, logiciels exigeants)" \
  run_wizard "${WORK}/Setup Jeu (v2).exe" >/dev/null 2>&1
check "bouteille creee par bottles-cli" "$(grep -c -- '--command=bottles-cli com.usebottles.bottles new --bottle-name Setup-Jeu--v2 --environment application' "${WINE_LOG}")" "1"
check "installateur lance dans la bouteille" "$(grep -c -- 'bottles-cli com.usebottles.bottles run -b Setup-Jeu--v2 -e '"${WORK}"'/Setup Jeu (v2).exe' "${WINE_LOG}")" "1"
check "dossier du fichier en lecture seule, pour cette execution" "$(grep -c -- "--filesystem=${WORK}:ro" "${WINE_LOG}")" "2"
check "wine du systeme non utilise" "$(grep -c '^TARGET=' "${WINE_LOG}")" "0"

echo "== 11. Bottles ne sait pas creer la bouteille: Bottles s'ouvre avec la marche a suivre =="
: > "${WINE_LOG}"; : > "${ZENITY_LOG}"
printf 'MZ' > "${WORK}/Autre.exe"
BOTTLES_ECHEC=1 ZENITY_LIST="Installer avec Bottles (jeux, logiciels exigeants)" \
  run_wizard "${WORK}/Autre.exe" >/dev/null 2>&1
check "Bottles ouvert" "$(grep -c '^flatpak run com.usebottles.bottles$' "${WINE_LOG}")" "1"
check "la marche a suivre est donnee" "$(grep -c 'Exécuter un fichier' "${ZENITY_LOG}")" "1"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
