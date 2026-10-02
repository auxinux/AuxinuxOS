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
flatpak() {
  echo "flatpak $*" >>"${CALLS}"
  return "${FLATPAK_RC}"
}

# Charge les fonctions sans executer de commande (aucun argument: usage).
source "${AUXI_BIN}" >/dev/null
# Le harnais observe des codes de sortie: pas d'arret sur erreur ICI. Chaque
# cas remet en revanche `set -e` dans son sous-shell, comme dans le vrai
# script: c'est lui qui fait sortir `auxi` quand apt-get echoue.
set +e
apt_real() { echo "${WORK}/apt-get"; }
require_root_for_deb() { return 0; }

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
has "apt-get upgrade a quand meme tourne" "upgrade DEBIAN_FRONTEND"
FLATPAK_RC=0

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

echo "== 6. Options globales: avant la commande seulement =="
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

if [[ "${fail}" -eq 0 ]]; then
  echo "test-auxi-noninteractive: OK"
else
  echo "test-auxi-noninteractive: ECHEC"
fi
exit "${fail}"
