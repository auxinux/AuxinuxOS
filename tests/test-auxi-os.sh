#!/usr/bin/env bash
#
# `auxi os update` / `auxi os upgrade`: nouvelle version d'AuxiNux OS.
#
# DEMANDE A L'ORIGINE (2026-10-09, aporler): « auxi os update » dit s'il y a
# une nouvelle version, « auxi os upgrade » l'installe; et une montee de
# version de l'OS, depuis le centre ou en ligne de commande, fait TOUJOURS un
# instantane.
#
# apt-get, apt-cache et snapper sont simules.
#
# Usage: bash tests/test-auxi-os.sh
set -uo pipefail

export LANG=C.UTF-8 LANGUAGE= LC_ALL= LC_MESSAGES=
AUXI_BIN="${AUXI_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxi-cli/auxi}"
[[ -r "${AUXI_BIN}" ]] || { echo "auxi introuvable: ${AUXI_BIN}" >&2; exit 66; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CALLS="${WORK}/calls"

cat >"${WORK}/apt-get" <<STUB
#!/usr/bin/env bash
echo "apt-get \$* NOSNAP=\${AUXI_NO_SNAPSHOT:-}" >>"${CALLS}"
exit 0
STUB
chmod +x "${WORK}/apt-get"

printf 'PRETTY_NAME="AuxiNux OS 0.2.0"\nBUILD_ID=20261008.2\n' >"${WORK}/os-release"
export AUXI_OS_RELEASE="${WORK}/os-release"

source "${AUXI_BIN}" >/dev/null
set +e
apt_real() { echo "${WORK}/apt-get"; }
require_root_for_deb() { return 0; }
kernel_update_channels() { echo "etape-noyaux NOSNAP=${AUXI_NO_SNAPSHOT:-}" >>"${CALLS}"; }
deb_installed() { [[ "$1" == "auxinuxos-release" ]]; }

# Etat simule des depots.
INSTALLED="0.2.0+20261008.2"
CANDIDATE="0.2.1+20261009"
apt_cache() {
  case "$1" in
    policy) printf 'auxinuxos-release:\n  Installed: %s\n  Candidate: %s\n' "${INSTALLED}" "${CANDIDATE}" ;;
    show) printf 'Package: auxinuxos-release\nVersion: %s\nDescription: AuxiNux OS 0.2.1, édition du 2026-10-09\n Dossiers personnels.\n .\n Wine 32 bits.\nHomepage: x\n' "${CANDIDATE}" ;;
  esac
}
SNAPSHOTS=1
SNAPPER_RC=0
snapshots_available() { [[ "${SNAPSHOTS}" -eq 1 ]]; }
snapper() { echo "snapper $*" >>"${CALLS}"; [[ "${SNAPPER_RC}" -eq 0 ]] && echo 42; return "${SNAPPER_RC}"; }
flatpak() { echo "flatpak $*" >>"${CALLS}"; }

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
run() { : >"${CALLS}"; out="$( (set -e; "$@") </dev/null 2>&1)"; rc=$?; }

echo "== 1. os update: nouvelle version annoncee, rien d'installe =="
EUID_SAVE=${EUID}
run run_os_update
check "sort en 0" "${rc}" "0"
check "version installee" "$(grep -c 'Version installée: AuxiNux OS 0.2.0, édition du 2026-10-08 (2)' <<<"${out}")" "1"
check "nouvelle version nommee" "$(grep -c 'Nouvelle version disponible: AuxiNux OS 0.2.1, édition du 2026-10-09' <<<"${out}")" "1"
check "nouveautes listees" "$(grep -cE '^  - (Dossiers personnels\.|Wine 32 bits\.)$' <<<"${out}")" "2"
check "comment l'installer" "$(grep -c 'sudo auxi os upgrade' <<<"${out}")" "1"
lacks "aucun upgrade" " upgrade "
lacks "aucun instantane" "snapper"

echo "== 2. os update: a jour =="
CANDIDATE="${INSTALLED}"
run run_os_update
check "a jour" "$(grep -c 'AuxiNux OS est à jour.' <<<"${out}")" "1"
CANDIDATE="0.2.1+20261009"

echo "== 3. os upgrade: instantane NOMME d'abord, puis la mise a jour =="
run run_osupdate
check "sort en 0" "${rc}" "0"
has "instantane nomme d'apres la version" "snapper -c root create --type single --print-number --cleanup-algorithm number --description Avant AuxiNux OS 0.2.1, édition du 2026-10-09 --userdata auxi=1,important=yes"
check "instantane AVANT le upgrade" "$(grep -nE '^(snapper|apt-get .*upgrade)' "${CALLS}" | head -n1 | cut -d: -f2 | cut -d' ' -f1)" "snapper"
has "pas de doublon du hook dpkg pendant la transaction" "upgrade --with-new-pkgs NOSNAP=1"
has "noyaux couverts par le meme instantane" "etape-noyaux NOSNAP=1"

echo "== 4. Machine d'avant le 2026-10-09 (paquet absent): meme instantane, puis installation =="
INSTALLED="(none)"
deb_installed() { return 1; }
run run_osupdate
has "instantane" "snapper -c root create"
has "auxinuxos-release installe sous le meme instantane" "install -- auxinuxos-release NOSNAP=1"
deb_installed() { [[ "$1" == "auxinuxos-release" ]]; }
INSTALLED="0.2.0+20261008.2"

echo "== 5. Pas de nouvelle version: mise a jour ordinaire (instantane du hook dpkg) =="
CANDIDATE="${INSTALLED}"
run run_osupdate
lacks "aucun instantane nomme" "snapper"
has "le hook dpkg reste actif" "upgrade --with-new-pkgs NOSNAP="
lacks "pas de NOSNAP=1" "NOSNAP=1"
CANDIDATE="0.2.1+20261009"

echo "== 6. Instantane impossible sur un systeme BTRFS: la montee de version est ANNULEE =="
SNAPPER_RC=1
run run_osupdate
check "sort en 69" "${rc}" "69"
lacks "aucun upgrade" "upgrade --with-new-pkgs"
check "la raison est dite" "$(grep -c 'annulée: rien n.a été modifié' <<<"${out}")" "1"
SNAPPER_RC=0

echo "== 7. Racine non BTRFS: avertissement, la mise a jour continue =="
SNAPSHOTS=0
run run_osupdate
check "sort en 0" "${rc}" "0"
check "avertissement" "$(grep -c 'pas d.instantané possible' <<<"${out}")" "1"
has "upgrade quand meme" "upgrade --with-new-pkgs"
SNAPSHOTS=1

echo "== 8. auxi upgrade (le bouton « Mettre a jour le systeme ») prend le meme chemin =="
run run_upgrade
has "applications Flatpak" "flatpak update"
has "instantane nomme" "snapper -c root create"

echo "== 9. Commande os sans sous-commande =="
run run_os
check "sort en 64" "${rc}" "64"

if [[ "${fail}" -eq 0 ]]; then echo "test-auxi-os: OK"; else echo "test-auxi-os: ECHEC"; fi
exit "${fail}"
