#!/usr/bin/env bash
#
# Test du hook d'instantane branche sur dpkg.
#
# C'est desormais LUI qui porte la promesse centrale de la distribution: « un
# instantane est cree avant chaque transaction DEB ». Elle n'etait tenue,
# jusqu'ici, que par la commande `auxi`; tout autre chemin vers dpkg (apt
# reactive, PackageKit, dpkg direct) modifiait le systeme sans filet.
#
# Deux proprietes sont verifiees en priorite:
#   - le hook NE FAIT JAMAIS ECHOUER apt (un DPkg::Pre-Invoke qui sort en
#     erreur avorte la transaction: une panne de snapper rendrait la machine
#     incapable d'installer quoi que ce soit);
#   - il reste silencieux partout ou les instantanes n'ont pas de sens (ext4,
#     snapper absent, chroot d'installation, demarrage sur un instantane).
#
# snapper et findmnt sont remplaces par des stubs: ce test valide la logique
# et l'enchainement pre/post, pas le comportement reel de BTRFS.
#
# Usage: bash tests/test-apt-snapshot-hook.sh
set -uo pipefail

HOOK="${HOOK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxi-cli/apt-snapshot-hook}"
[[ -x "${HOOK}" ]] || { echo "hook introuvable: ${HOOK}" >&2; exit 66; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
STUBS="${WORK}/bin"
mkdir -p "${STUBS}"

# snapper pilote par SNAPPER_SHOULD_FAIL; journalise ses arguments.
cat > "${STUBS}/snapper" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SNAPPER_LOG}"
if [[ "${SNAPPER_SHOULD_FAIL:-0}" == "1" ]]; then
  echo "snapper: echec simule" >&2
  exit 1
fi
# --print-number: seule la creation "pre" en attend un.
if [[ "$*" == *--print-number* ]]; then
  echo "42"
fi
exit 0
STUB
chmod +x "${STUBS}/snapper"

cat > "${STUBS}/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${FINDMNT_FSTYPE:-btrfs}"
STUB
chmod +x "${STUBS}/findmnt"

export SNAPPER_LOG="${WORK}/snapper.log"
export AUXI_SNAPPER_CONFIG_FILE="${WORK}/snapper-config-root"
export AUXI_SNAPSHOT_STATE="${WORK}/state"
export AUXI_SNAPSHOT_OVERLAY_LOWER="${WORK}/overlay-lower"
export AUXI_CMDLINE_FILE="${WORK}/cmdline"

reset_env() {
  : > "${SNAPPER_LOG}"
  rm -f "${AUXI_SNAPSHOT_STATE}"
  rm -rf "${AUXI_SNAPSHOT_OVERLAY_LOWER}"
  printf 'BOOT_IMAGE=/vmlinuz root=UUID=x ro quiet\n' > "${AUXI_CMDLINE_FILE}"
  : > "${AUXI_SNAPPER_CONFIG_FILE}"
  unset SNAPPER_SHOULD_FAIL FINDMNT_FSTYPE AUXI_NO_SNAPSHOT
}

run_hook() { PATH="${STUBS}:${PATH}" "${HOOK}" "$@"; }

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

echo "== 1. Transaction nominale: paire pre/post =="
reset_env
run_hook pre >/dev/null 2>&1
check "pre sort en 0" "$?" "0"
check "instantane pre demande" "$(grep -c -- '--type pre' "${SNAPPER_LOG}")" "1"
check "numero memorise" "$(cat "${AUXI_SNAPSHOT_STATE}" 2>/dev/null)" "42"
run_hook post >/dev/null 2>&1
check "post sort en 0" "$?" "0"
check "post rattache au pre" "$(grep -c -- '--pre-number 42' "${SNAPPER_LOG}")" "1"
check "etat efface apres post" "$([[ -e "${AUXI_SNAPSHOT_STATE}" ]] && echo present || echo absent)" "absent"

echo "== 2. Racine non BTRFS: aucun instantane, aucune erreur =="
reset_env
FINDMNT_FSTYPE=ext4 run_hook pre >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "snapper non appele" "$(wc -l < "${SNAPPER_LOG}")" "0"

echo "== 3. snapper non configure (chroot d'installation) =="
reset_env
rm -f "${AUXI_SNAPPER_CONFIG_FILE}"
run_hook pre >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "snapper non appele" "$(wc -l < "${SNAPPER_LOG}")" "0"

echo "== 4. AUXI_NO_SNAPSHOT=1 respecte =="
reset_env
AUXI_NO_SNAPSHOT=1 run_hook pre >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "snapper non appele" "$(wc -l < "${SNAPPER_LOG}")" "0"

echo "== 5. Echec de snapper: apt ne doit PAS etre avorte (cas critique) =="
reset_env
SNAPPER_SHOULD_FAIL=1 run_hook pre >/dev/null 2>&1
check "pre sort quand meme en 0" "$?" "0"
check "aucun etat laisse derriere" "$([[ -e "${AUXI_SNAPSHOT_STATE}" ]] && echo present || echo absent)" "absent"
SNAPPER_SHOULD_FAIL=1 run_hook post >/dev/null 2>&1
check "post sort quand meme en 0" "$?" "0"

echo "== 6. post orphelin (sans pre): sans effet =="
reset_env
run_hook post >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "snapper non appele" "$(wc -l < "${SNAPPER_LOG}")" "0"

echo "== 7. Demarrage sur un instantane: pas d'instantane de l'overlay =="
reset_env
mkdir -p "${AUXI_SNAPSHOT_OVERLAY_LOWER}"
printf 'BOOT_IMAGE=/vmlinuz auxinux.snapshot=1 ro\n' > "${AUXI_CMDLINE_FILE}"
run_hook pre >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "snapper non appele" "$(wc -l < "${SNAPPER_LOG}")" "0"

echo "== 8. Argument inconnu: sans effet, sans erreur =="
reset_env
run_hook bidon >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "snapper non appele" "$(wc -l < "${SNAPPER_LOG}")" "0"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
