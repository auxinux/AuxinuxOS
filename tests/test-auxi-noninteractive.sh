#!/usr/bin/env bash
#
# `auxi --yes --progress`: le chemin qu'emprunte le centre de controle.
#
# PANNE A L'ORIGINE DE CE TEST (2026-10-02): « Mettre a jour le systeme »
# echouait apres plusieurs minutes avec « Echec de l'operation » et rien
# d'autre. Le centre lance `pkexec auxi upgrade` sans terminal, entree standard
# fermee; `apt-get upgrade` sans -y posait « Continuer ? [O/n] », lisait une fin
# de fichier, repondait « Abandon. » et sortait en 1 -- sur la sortie standard,
# que l'interface ne lisait pas.
#
# apt-get et flatpak sont remplaces par des stubs qui consignent leurs
# arguments. Le faux apt-get reproduit le comportement reel: sans -y, il
# abandonne sur une entree fermee.
#
# Usage: bash tests/test-auxi-noninteractive.sh
set -uo pipefail

AUXI_BIN="${AUXI_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxi-cli/auxi}"
if [[ ! -r "${AUXI_BIN}" ]]; then
  echo "auxi introuvable: ${AUXI_BIN}" >&2
  exit 66
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CALLS="${WORK}/calls"

cat >"${WORK}/apt-get" <<STUB
#!/usr/bin/env bash
echo "apt-get \$* DEBIAN_FRONTEND=\${DEBIAN_FRONTEND:-}" >>"${CALLS}"
case " \$* " in
  *" -y "*) echo "Lecture des listes de paquets..."; exit 0 ;;
esac
# Comportement reel d'apt-get sans terminal: la question recoit une fin de
# fichier, la transaction est abandonnee, et tout part sur la sortie STANDARD.
printf 'Souhaitez-vous continuer ? [O/n] '
if read -r answer && [[ "\${answer}" =~ ^[OoYy] ]]; then exit 0; fi
echo "Abandon."
exit 1
STUB
chmod +x "${WORK}/apt-get"

FLATPAK_RC=0
# Sorties simulees de `flatpak search` et `flatpak remote-ls` (colonnes
# separees par des tabulations, comme hors terminal).
FLATPAK_SEARCH_OUT=""
FLATPAK_REMOTE_OUT=""
flatpak() {
  echo "flatpak $*" >>"${CALLS}"
  case "$1" in
    search) [[ -n "${FLATPAK_SEARCH_OUT}" ]] && printf '%s\n' "${FLATPAK_SEARCH_OUT}" ;;
    remote-ls) [[ -n "${FLATPAK_REMOTE_OUT}" ]] && printf '%s\n' "${FLATPAK_REMOTE_OUT}" ;;
  esac
  return "${FLATPAK_RC}"
}

# Charge les fonctions sans executer de commande (aucun argument: usage).
source "${AUXI_BIN}" >/dev/null
# Le harnais observe des codes de sortie: pas d'arret sur erreur ICI. Chaque
# cas remet en revanche `set -e` dans son sous-shell, comme dans le vrai
# script: c'est lui qui fait sortir `auxi` quand apt-get echoue.
set +e
apt_real() { echo "${WORK}/apt-get"; }
apt_cache() { echo "apt-cache $*" >>"${CALLS}"; }
require_root_for_deb() { return 0; }
# L'etape noyaux de osupdate a son propre test (test-auxi-kernel.sh): ici, on
# verifie seulement qu'elle est appelee.
kernel_update_channels() { echo "etape-noyaux" >>"${CALLS}"; }
# Installation DEB activee pour les cas 1 a 7; le cas 8 la coupe.
APPS_CONF="${WORK}/apps.conf"
printf 'DEB_APPS=1\n' >"${APPS_CONF}"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
has() {
  if grep -qF -- "$2" "${CALLS}"; then echo "  OK   $1"; else echo "  ECHEC $1: [$2] absent de:"; sed 's/^/         /' "${CALLS}"; fail=1; fi
}
lacks() {
  if ! grep -qF -- "$2" "${CALLS}"; then echo "  OK   $1"; else echo "  ECHEC $1: [$2] present"; fail=1; fi
}

echo "== 1. Sans --yes, une entree fermee fait echouer (la panne d'origine) =="
: >"${CALLS}"
ASSUME_YES=0 PROGRESS=0
out="$( (set -e; run_upgrade) </dev/null 2>&1)"
check "code de sortie" "$?" "1"
check "la raison est sur la sortie standard" "$(grep -c 'Abandon.' <<<"${out}")" "1"

echo "== 2. Le chemin du centre: auxi --yes --progress upgrade =="
: >"${CALLS}"
ASSUME_YES=1 PROGRESS=1
export DEBIAN_FRONTEND=noninteractive
( set -e; run_upgrade ) </dev/null >/dev/null 2>&1
check "reussit sans terminal" "$?" "0"
has "apt-get recoit -y" "apt-get -y "
has "fichiers de configuration modifies conserves" "Dpkg::Options::=--force-confold"
has "dpkg tranche seul quand il le peut" "Dpkg::Options::=--force-confdef"
has "lignes d'avancement sur la sortie standard" "APT::Status-Fd=1"
has "debconf sans question" "DEBIAN_FRONTEND=noninteractive"
has "flatpak sans tableau anime" "flatpak update -y --noninteractive"
unset DEBIAN_FRONTEND

echo "== 3. Un echec Flatpak n'empeche plus les correctifs DEB =="
: >"${CALLS}"
FLATPAK_RC=1
( set -e; run_upgrade ) </dev/null >/dev/null 2>&1
check "l'echec est rendu" "$?" "1"
has "apt-get upgrade a quand meme tourne" "upgrade --with-new-pkgs DEBIAN_FRONTEND"
FLATPAK_RC=0

echo "== 3b. Le systeme se met a jour avec ses NOUVEAUX paquets (noyau) =="
# PANNE (2026-10-07): `apt-get upgrade` simple met de cote (« kept back ») un
# kernel-auxinuxos qui tire un nouveau linux-image, et sort en 0.
: >"${CALLS}"
ASSUME_YES=1 PROGRESS=1
( set -e; run_upgrade ) </dev/null >/dev/null 2>&1
check "reussit" "$?" "0"
has "les index sont rafraichis d'abord" "update DEBIAN_FRONTEND"
has "upgrade accepte les nouveaux paquets tires" "upgrade --with-new-pkgs"
lacks "jamais de full-upgrade (qui retirerait des paquets)" "full-upgrade"
has "les noyaux d'essai suivent" "etape-noyaux"
check "update AVANT upgrade" \
  "$(grep '^apt-get' "${CALLS}" | grep -e ' update ' -e 'upgrade --with' | head -n1 | grep -c ' update ')" "1"

echo "== 3c. auxi osupdate: le systeme seul, quel que soit le reglage DEB =="
printf 'DEB_APPS=0\n' >"${APPS_CONF}"
: >"${CALLS}"
( set -e; run_osupdate ) </dev/null >/dev/null 2>&1
check "reussit avec DEB_APPS=0" "$?" "0"
has "upgrade --with-new-pkgs" "upgrade --with-new-pkgs"
lacks "aucune application Flatpak touchee" "flatpak"
printf 'DEB_APPS=1\n' >"${APPS_CONF}"

echo "== 4. Le terminal garde son comportement sans --yes =="
: >"${CALLS}"
ASSUME_YES=0 PROGRESS=0
( set -e; run_install --deb vlc ) </dev/null >/dev/null 2>&1
lacks "aucun -y impose" " -y "
lacks "aucune ligne d'avancement imposee" "Status-Fd"

echo "== 5. Desinstallation depuis le centre (apt-get remove questionne toujours) =="
: >"${CALLS}"
ASSUME_YES=1 PROGRESS=1
( set -e; run_uninstall --deb vlc ) </dev/null >/dev/null 2>&1
check "reussit sans terminal" "$?" "0"
has "remove recoit -y" "apt-get -y "

echo "== 6. Plusieurs elements en une transaction (assistant de premier demarrage) =="
: >"${CALLS}"
ASSUME_YES=1 PROGRESS=1
( set -e; run_install --flatpak org.mozilla.firefox org.videolan.VLC ) </dev/null >/dev/null 2>&1
check "reussit" "$?" "0"
has "les deux applications en un seul appel, deja installee = mise a jour" \
  "flatpak install -y --noninteractive --or-update flathub -- org.mozilla.firefox org.videolan.VLC"
: >"${CALLS}"
( set -e; run_install --deb brave-browser vlc ) </dev/null >/dev/null 2>&1
has "les deux paquets en un seul apt-get" "install -- brave-browser vlc"

echo "== 7. Options globales: avant la commande seulement =="
parse() {
  # Sous-shell: chaque cas repart d'un etat vierge.
  ( set -- "$@"; source "${AUXI_BIN}" >/dev/null 2>&1; echo "${ASSUME_YES}${PROGRESS} ${DEBIAN_FRONTEND:-}" )
}
check "--yes --progress" "$(parse --yes --progress)" "11 noninteractive"
check "--progress seul" "$(parse --progress)" "01 "
check "sans option" "$(parse)" "00 "
# `auxi rollback N --yes` confirme une restauration: ce --yes-la ne doit PAS
# etre lu comme l'option globale.
check "--yes apres la commande ignore" "$(parse help --yes)" "00 "

echo "== 8. Flatpak d'abord, DEB seulement si active et sans Flatpak =="
# PANNE (2026-10-06): `auxi install gimp` installait le DEB, parce que seul
# l'identifiant exact org.gimp.GIMP etait reconnu comme Flatpak.
GIMP_SEARCH=$'org.gimp.GIMP.Manual\tGIMP User Manual\tflathub\norg.gimp.GIMP\tGNU Image Manipulation Program\tflathub\norg.gimp.GIMP.Plugin.Resynthesizer\tResynthesizer\tflathub'
ASSUME_YES=1 PROGRESS=0
FLATPAK_SEARCH_OUT="${GIMP_SEARCH}"
for etat in 0 1; do
  printf 'DEB_APPS=%s\n' "${etat}" >"${APPS_CONF}"
  : >"${CALLS}"
  ( set -e; run_install gimp ) </dev/null >/dev/null 2>&1
  check "gimp (DEB_APPS=${etat}): reussit" "$?" "0"
  has "gimp (DEB_APPS=${etat}): le Flatpak org.gimp.GIMP, pas un greffon" "flatpak install -y --noninteractive flathub -- org.gimp.GIMP"
  lacks "gimp (DEB_APPS=${etat}): aucun apt-get" "apt-get"
done
check "nom affiche: OBS Studio" "$(pick_flatpak_id obs-studio <<<$'com.obsproject.Studio\tOBS Studio\tflathub')" "com.obsproject.Studio"
check "identifiant complet, casse ignoree" "$(pick_flatpak_id org.videolan.vlc <<<$'org.videolan.VLC\tVLC\tflathub')" "org.videolan.VLC"
check "une autre remote que flathub ne compte pas" "$(pick_flatpak_id vlc <<<$'org.videolan.VLC\tVLC\tautre' || echo aucun)" "aucun"
check "aucune correspondance approximative" "$(pick_flatpak_id gim <<<"${GIMP_SEARCH}" || echo aucun)" "aucun"

# Aucun Flatpak: DEB desactive -> refus avec suggestions; active -> DEB.
FLATPAK_SEARCH_OUT=$'org.example.Htop2\tHtop Deux\tflathub'
printf 'DEB_APPS=0\n' >"${APPS_CONF}"
: >"${CALLS}"
out="$( (set -e; run_install htop) </dev/null 2>&1)"
check "sans Flatpak, DEB desactive: refus" "$?" "1"
lacks "sans Flatpak, DEB desactive: aucun apt-get" "apt-get"
check "la suggestion est affichee" "$(grep -c 'org.example.Htop2' <<<"${out}")" "1"
check "la facon d'activer le DEB est dite" "$(grep -c 'auxi set deb=true' <<<"${out}")" "1"
printf 'DEB_APPS=1\n' >"${APPS_CONF}"
: >"${CALLS}"
( set -e; run_install htop ) </dev/null >/dev/null 2>&1
check "sans Flatpak, DEB active: reussit" "$?" "0"
has "sans Flatpak, DEB active: apt-get install htop" "install -- htop"

# --deb explicite, DEB desactive: nouveau paquet refuse, paquet installe mis a
# jour (chemin du centre), paquets de l'assistant acceptes.
printf 'DEB_APPS=0\n' >"${APPS_CONF}"
deb_installed() { [[ "$1" == "auxinux-office" ]]; }
: >"${CALLS}"
( set -e; run_install --deb vlc ) </dev/null >/dev/null 2>&1
check "--deb d'un paquet nouveau, DEB desactive: refus" "$?" "1"
lacks "--deb refuse: aucun apt-get" "apt-get"
( set -e; run_install --deb auxinux-office ) </dev/null >/dev/null 2>&1
check "--deb d'un paquet installe (mise a jour): accepte" "$?" "0"
: >"${CALLS}"
( set -e; AUXI_DEB_SYSTEME=1 run_install --deb brave-browser ) </dev/null >/dev/null 2>&1
check "--deb de l'assistant: accepte" "$?" "0"
has "--deb de l'assistant: apt-get install" "install -- brave-browser"

# La recherche ne liste les DEB que si leur installation est activee.
: >"${CALLS}"
( set -e; run_search gimp ) </dev/null >/dev/null 2>&1
lacks "recherche, DEB desactive: pas d'apt-cache" "apt-cache search"
printf 'DEB_APPS=1\n' >"${APPS_CONF}"
: >"${CALLS}"
( set -e; run_search gimp ) </dev/null >/dev/null 2>&1
has "recherche, DEB active: apt-cache aussi" "apt-cache search -- gimp"

if [[ "${fail}" -eq 0 ]]; then
  echo "test-auxi-noninteractive: OK"
else
  echo "test-auxi-noninteractive: ECHEC"
fi
exit "${fail}"
