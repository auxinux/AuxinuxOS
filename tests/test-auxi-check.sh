#!/usr/bin/env bash
#
# `auxi check` / `auxi repair`: integrite d'AuxiNux OS, du Shell et de leurs
# dependances.
#
# DEMANDE A L'ORIGINE (2026-10-26, aporler): machine installee depuis une ISO
# ancienne puis mise a jour; fenetre de mot de passe absente, filigrane absent,
# AuxiFiles avec des rates, et la page Sante dit que tout va bien. Cause: le
# Shell RETENU en 0.3.5 par `apt-get upgrade --with-new-pkgs` (recommandation
# nouvelle impossible a satisfaire), et les paquets que seule l'ISO installe.
#
# dpkg, dpkg-query, apt-get, apt-cache, apt-mark et snapper sont simules.
#
# Usage: bash tests/test-auxi-check.sh
set -uo pipefail

export LANG=C.UTF-8 LANGUAGE= LC_ALL= LC_MESSAGES=
AUXI_BIN="${AUXI_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxi-cli/auxi}"
[[ -r "${AUXI_BIN}" ]] || { echo "auxi introuvable: ${AUXI_BIN}" >&2; exit 66; }
command -v dpkg >/dev/null || { echo "dpkg absent: test saute"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CALLS="${WORK}/calls"
export CALLS

# apt-get simule: la simulation d'upgrade liste UPGRADABLE, check rend
# APT_CHECK_RC, le reste est journalise.
cat >"${WORK}/apt-get" <<'STUB'
#!/usr/bin/env bash
if [[ " $* " == *" -s "* && " $* " == *" upgrade "* ]]; then
  for p in ${UPGRADABLE:-}; do echo "Inst ${p} [1] (2 AuxiNux:APPS [all])"; done
  exit 0
fi
if [[ " $* " == *" check"* ]]; then exit "${APT_CHECK_RC:-0}"; fi
echo "apt-get $* NOSNAP=${AUXI_NO_SNAPSHOT:-}" >>"${CALLS}"
exit 0
STUB
chmod +x "${WORK}/apt-get"

printf '# socle\npolkit-kde-agent-1\nxdg-desktop-portal-wlr  # portail\n\n' >"${WORK}/socle.list"
export AUXI_SOCLE_LIST="${WORK}/socle.list"

source "${AUXI_BIN}" >/dev/null
set +e
apt_real() { echo "${WORK}/apt-get"; }
require_root_for_deb() { return 0; }
kernel_update_channels() { :; }
snapshots_available() { return 0; }
snapper() { echo "snapper $*" >>"${CALLS}"; echo 7; }
pgrep() { return 1; }

# Etat simule: paquet -> « installee candidate » ((none) si absent).
declare -A STATE
declare -A VERIFY
AUDIT=""
AUTO=""
reset_state() {
  STATE=(
    [auxinuxos-release]="0.4.0+20261026.1 0.4.0+20261026.1"
    [auxi]="0.2.11 0.2.11"
    [auxinux-center]="0.2.11 0.2.11"
    [kernel-auxinuxos]="7.2.11 7.2.11"
    [auxinux-shell]="0.3.13 0.3.13"
    [auxi-shell-games]="0.3.13 0.3.13"
    [auxioffice]="1.0 1.0"
    [wlsunset]="1 1"
    [fonts-inter]="1 1"
    [polkit-kde-agent-1]="6 6"
    [xdg-desktop-portal-wlr]="0.7 0.7"
    [auxi-shell-auxipak]="0.3.13 0.3.13"
  )
  VERIFY=()
  AUDIT=""
  AUTO=""
  export UPGRADABLE="" APT_CHECK_RC=0
}
apt_cache() {
  [[ "$1" == policy ]] || return 0
  shift
  local p
  for p in "$@"; do
    [[ -n "${STATE[${p}]:-}" ]] || continue
    printf '%s:\n  Installed: %s\n  Candidate: %s\n' "${p}" ${STATE[${p}]}
  done
}
dpkg-query() {
  case "$*" in
    *'${Depends}'*auxinuxos-release) echo "auxi (>= 0.2.11), auxinux-center (>= 0.2.11), kernel-auxinuxos, auxinux-shell (>= 0.2.1), auxioffice, plymouth, base-files" ;;
    *'${Recommends}'*auxinux-shell) echo "auxinux-center, auxi-shell-auxipak, wlsunset, fonts-inter-variable | fonts-inter, gvfs-backends" ;;
    *'${Status}'*)
      local p="${*: -1}"
      [[ -n "${STATE[${p}]:-}" && "${STATE[${p}]%% *}" != "(none)" ]] && echo "install ok installed" ;;
  esac
}
dpkg() {
  case "$1" in
    --audit) printf '%s' "${AUDIT}" ;;
    --verify) printf '%s' "${VERIFY[$2]:-}" ;;
    --compare-versions) command dpkg "$@" ;;
    *) echo "dpkg $*" >>"${CALLS}" ;;
  esac
}
apt-mark() {
  case "$1" in
    showauto) shift; [[ "$1" == "--" ]] && shift; local p; for p in "$@"; do [[ " ${AUTO} " == *" ${p} "* ]] && echo "${p}"; done; return 0 ;;
    *) echo "apt-mark $*" >>"${CALLS}" ;;
  esac
}

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
line() { grep -P "^[a-z]+\t$1\t" <<<"${out}"; }

echo "== 1. Systeme intact =="
reset_state
run run_check --porcelain
check "sort en 0" "${rc}" "0"
check "7 paquets AuxiNux presents" "$(line paquets | cut -f1,4)" $'ok\t7 paquets présents et à jour'
check "dependances presentes (alternative satisfaite, gvfs-backends absent des depots)" "$(line dependances | cut -f1)" "ok"
check "gvfs-backends signale sans effet" "$(line dependances | cut -f5 | grep -c 'gvfs-backends')" "1"
check "fichiers intacts" "$(line fichiers | cut -f1)" "ok"
check "rien a reparer" "$(tail -n1 <<<"${out}")" $'reparable\tnon'
lacks "aucune modification" "apt-get"

echo "== 2. Le cas d'aporler: Shell RETENU en 0.3.5, agent polkit de repli absent =="
reset_state
STATE[auxinux-shell]="0.3.5 0.3.13"
STATE[auxi-shell-games]="0.3.5 0.3.13"
STATE[polkit-kde-agent-1]="(none) 6"
UPGRADABLE="auxi-shell-games"
run run_check --porcelain
check "sort en 1" "${rc}" "1"
check "retenu = critique" "$(line paquets | cut -f1)" "critique"
check "le Shell est nomme avec ses versions" "$(line paquets | cut -f4 | grep -c 'auxinux-shell 0.3.5 → 0.3.13')" "1"
check "dependance absente nommee" "$(line dependances | cut -f1,4)" $'attention\t1 absente(s): polkit-kde-agent-1'
check "reparable" "$(tail -n1 <<<"${out}")" $'reparable\toui'
run run_check
check "texte: commande de reparation" "$(grep -c 'sudo auxi repair' <<<"${out}")" "1"

echo "== 3. Une mise a jour simplement en attente n'est pas « retenue » =="
reset_state
STATE[auxi]="0.2.9 0.2.10"
UPGRADABLE="auxi"
run run_check --porcelain
check "attention, pas critique" "$(line paquets | cut -f1,4)" $'attention\tmise à jour en attente: auxi 0.2.9 → 0.2.10'

echo "== 3 bis. Absent ET en attente: les deux sont dits (vu sur le rootfs 0.4.0) =="
reset_state
STATE[auxi]="0.2.9 0.2.10"
STATE[auxi-shell-games]="(none) 0.3.13"
UPGRADABLE="auxi"
run run_check --porcelain
check "critique, les deux listes" "$(line paquets | cut -f1,4)" $'critique\tabsents: auxi-shell-games; mise à jour en attente: auxi 0.2.9 → 0.2.10'

echo "== 4. Absent des depots: le dire, et pointer vers les sources =="
reset_state
unset 'STATE[auxinux-shell]'
run run_check --porcelain
check "critique" "$(line paquets | cut -f1,4)" $'critique\tabsents: auxinux-shell'
check "conseil: actualiser, puis le depot" "$(line paquets | cut -f5 | grep -c 'sudo auxi update.*Sources')" "1"

echo "== 5. Fichiers alteres (configuration exclue), installation interrompue =="
reset_state
VERIFY[auxinux-shell]=$'??5??????   /usr/share/auxinux-shell/python/auxinux_shell/app.py\nmissing     /usr/bin/auxi-files\n'
VERIFY[auxi]=$'??5?????? c /etc/auxinux/apt.conf\n'
AUDIT="Le paquet suivant n'est configure qu'a moitie"
APT_CHECK_RC=100
run run_check --porcelain
check "fichiers: Shell seul, 2 fichiers" "$(line fichiers | cut -f1,4)" $'critique\tfichiers modifiés ou manquants: auxinux-shell (2)'
check "dpkg critique" "$(line dpkg | cut -f1)" "critique"
check "apt critique" "$(line apt | cut -f1)" "critique"

echo "== 6. repair: instantane nomme, puis chaque correction, sans doublon du hook =="
reset_state
STATE[auxinux-shell]="0.3.5 0.3.13"
STATE[auxi-shell-games]="0.3.5 0.3.13"
STATE[polkit-kde-agent-1]="(none) 6"
VERIFY[auxinux-shell]=$'missing     /usr/bin/auxi-files\n'
VERIFY[auxioffice]=$'??5??????   /usr/bin/auxioffice\n'
AUDIT="x"
AUTO="auxi-shell-games"
run run_repair
has "instantane nomme" "snapper -c root create --type single --print-number --cleanup-algorithm number --description Avant la réparation d’AuxiNux OS"
check "instantane AVANT toute modification" "$(grep -vE '^apt-get update' "${CALLS}" | head -n1 | cut -d' ' -f1)" "snapper"
has "dpkg --configure -a" "dpkg --force-confdef --force-confold --configure -a"
has "apt-get install -f" "install -f NOSNAP=1"
has "Shell et jeux installes explicitement" "install -- auxinux-shell auxi-shell-games NOSNAP=1"
has "jeux remis en automatique" "apt-mark auto -- auxi-shell-games"
has "dependance sans recommandations" "install -o APT::Install-Recommends=0 -- polkit-kde-agent-1 NOSNAP=1"
has "AuxiOffice reinstalle" "install --reinstall -- auxioffice NOSNAP=1"
lacks "le Shell n'est pas reinstalle en plus" "--reinstall -- auxinux-shell"

echo "== 7. repair sur un systeme intact: rien, pas d'instantane =="
reset_state
run run_repair
check "sort en 0" "${rc}" "0"
check "le dit" "$(grep -c 'Rien à réparer' <<<"${out}")" "1"
lacks "pas d'instantane" "snapper"

echo "== 8. auxi os upgrade: un paquet AuxiNux retenu est installe explicitement =="
reset_state
STATE[auxinux-shell]="0.3.5 0.3.13"
release_candidate() { :; }
run run_osupdate
has "upgrade ordinaire" "upgrade --with-new-pkgs"
has "puis le Shell retenu" "install -- auxinux-shell NOSNAP="
check "dans cet ordre" "$(grep -nE 'with-new-pkgs|install -- auxinux-shell' "${CALLS}" | cut -d: -f1 | tr '\n' ' ')" "2 3 "
reset_state
run run_osupdate
lacks "rien de retenu: aucune installation" "install --"

if [[ "${fail}" -eq 0 ]]; then
  echo "test-auxi-check: OK"
else
  echo "test-auxi-check: ECHEC"
  exit 1
fi
