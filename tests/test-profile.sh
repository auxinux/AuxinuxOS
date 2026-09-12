#!/usr/bin/env bash
#
# Tests du profil d'usage (packages/auxinux-profile/).
#
# POURQUOI: c'est la seule chose qui differencie concretement les trois usages
# annonces (bureautique, multimedia, jeu). Le noyau 7.2.5 n'expose pas
# sched_ext, donc TOUT se joue dans ces quatre fichiers -- et deux erreurs y
# sont muettes:
#
#   1. un reglage qui ne part pas quand on QUITTE un profil (la priorite temps
#      reel audio qui reste accordee en bureautique, par exemple): le systeme
#      cumule alors les reglages de tous les profils deja essayes;
#   2. un profil invalide accepte, qui ecrirait un fichier sysctl vide et
#      ferait croire a un reglage applique.
#
# Usage: bash tests/test-profile.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${ROOT}/packages/auxinux-profile/auxinux-profile"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

STUBS="${WORK}/bin"
mkdir -p "${STUBS}"
cat > "${STUBS}/sysctl" <<'STUB'
#!/bin/sh
echo "sysctl $*" >> "${STUB_SYSCTL_LOG}"
STUB
cat > "${STUBS}/powerprofilesctl" <<'STUB'
#!/bin/sh
echo "$*" >> "${STUB_PPD_LOG}"
STUB
chmod 755 "${STUBS}/sysctl" "${STUBS}/powerprofilesctl"
export PATH="${STUBS}:${PATH}"
export STUB_SYSCTL_LOG="${WORK}/sysctl.log"
export STUB_PPD_LOG="${WORK}/ppd.log"
export AUXINUX_PROFILE_ROOT="${WORK}/root"

SYSCTL_F="${AUXINUX_PROFILE_ROOT}/etc/sysctl.d/60-auxinux-profile.conf"
LIMITS_F="${AUXINUX_PROFILE_ROOT}/etc/security/limits.d/60-auxinux-profile.conf"
PIPEWIRE_F="${AUXINUX_PROFILE_ROOT}/etc/pipewire/pipewire.conf.d/60-auxinux-profile.conf"
PROFILE_F="${AUXINUX_PROFILE_ROOT}/etc/auxinux/profile"

reset_env() { rm -rf "${AUXINUX_PROFILE_ROOT}"; : > "${STUB_SYSCTL_LOG}"; : > "${STUB_PPD_LOG}"; }
has() { grep -qF -- "$2" "$1" 2>/dev/null && echo oui || echo non; }

echo "== 1. Profil jeu =="
reset_env
"${PROFILE}" set gaming >/dev/null
check "profil enregistre" "$(cat "${PROFILE_F}")" "gaming"
# Proton depasse la limite par defaut de max_map_count et se ferme SANS
# message: c'est le reglage le plus utile des trois profils.
check "max_map_count releve" "$(has "${SYSCTL_F}" 'vm.max_map_count=2147483642')" "oui"
check "mitigation split-lock levee" "$(has "${SYSCTL_F}" 'kernel.split_lock_mitigate=0')" "oui"
check "sysctl recharge" "$(has "${STUB_SYSCTL_LOG}" '--system')" "oui"
check "quantum PipeWire" "$(has "${PIPEWIRE_F}" 'default.clock.quantum     = 512')" "oui"
check "priorite audio accordee" "$(has "${LIMITS_F}" 'rtprio     90')" "oui"
check "plein regime demande" "$(has "${STUB_PPD_LOG}" 'set performance')" "oui"

echo "== 2. Profil multimedia =="
reset_env
"${PROFILE}" set multimedia >/dev/null
check "quantum bas" "$(has "${PIPEWIRE_F}" 'default.clock.quantum     = 256')" "oui"
check "rtprio maximal" "$(has "${LIMITS_F}" 'rtprio     95')" "oui"
check "memlock leve" "$(has "${LIMITS_F}" 'memlock    unlimited')" "oui"
# La mitigation split-lock ne se leve QUE pour le jeu: c'est une protection
# contre un deni de service local, pas un reglage de confort.
check "mitigation split-lock conservee" "$(has "${SYSCTL_F}" 'kernel.split_lock_mitigate=1')" "oui"
check "pas de limite Proton hors jeu" "$(has "${SYSCTL_F}" 'max_map_count')" "non"

echo "== 3. Retour en bureautique: les reglages du profil quitte DISPARAISSENT =="
"${PROFILE}" set bureautique >/dev/null
check "priorite temps reel retiree" \
  "$([[ -e "${LIMITS_F}" ]] && echo present || echo absent)" "absent"
check "quantum par defaut" "$(has "${PIPEWIRE_F}" 'default.clock.quantum     = 1024')" "oui"
check "regime equilibre" "$(has "${STUB_PPD_LOG}" 'set balanced')" "oui"
# swappiness eleve et non l'inverse: l'echange va dans la RAM compressee
# (zram), ou il coute quelques microsecondes.
check "swappiness adapte a zram" "$(has "${SYSCTL_F}" 'vm.swappiness=100')" "oui"

echo "== 4. Profil invalide: refus, et rien d'ecrit =="
reset_env
out="$("${PROFILE}" set turbo 2>&1)"; rc=$?
check "code de sortie non nul" "$([[ "${rc}" -ne 0 ]] && echo oui || echo non)" "oui"
check "message explicite" "$(echo "${out}" | grep -c 'profil inconnu')" "1"
check "aucun fichier sysctl ecrit" \
  "$([[ -e "${SYSCTL_F}" ]] && echo present || echo absent)" "absent"

echo "== 5. apply relit le profil enregistre =="
reset_env
mkdir -p "$(dirname "${PROFILE_F}")"
printf 'gaming\n' > "${PROFILE_F}"
"${PROFILE}" apply >/dev/null
check "reglages du profil enregistre appliques" "$(has "${SYSCTL_F}" 'vm.max_map_count')" "oui"

echo "== 6. Fichier de profil corrompu: on retombe sur bureautique =="
reset_env
mkdir -p "$(dirname "${PROFILE_F}")"
printf 'n-importe-quoi\n' > "${PROFILE_F}"
check "profil courant sain" "$("${PROFILE}" status | sed -n 's/^profile=//p')" "bureautique"

echo "== 7. Sans power-profiles-daemon, le profil s'applique quand meme =="
reset_env
rm -f "${STUBS}/powerprofilesctl"
out="$("${PROFILE}" set gaming 2>&1)"; rc=$?
check "code de sortie 0" "${rc}" "0"
check "sysctl ecrit malgre tout" "$(has "${SYSCTL_F}" 'vm.max_map_count')" "oui"

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; fi
exit "${fail}"
