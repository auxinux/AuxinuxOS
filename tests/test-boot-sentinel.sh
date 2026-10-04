#!/usr/bin/env bash
#
# Tests de la protection au demarrage (packages/boot-sentinel/).
#
# POURQUOI: ce mecanisme n'agit QUE le jour ou le bureau ne demarre plus. Une
# erreur dedans ne se voit jamais en usage normal -- elle se voit le jour ou
# l'utilisateur a besoin d'etre sauve, et ce jour-la il n'a plus d'ecran pour
# lire un message d'erreur. Deux risques symetriques:
#
#   - trop prudent: le compteur ne monte jamais, le mode secours ne se
#     declenche pas, et l'utilisateur reste devant un ecran noir;
#   - trop zele: un demarrage en console voulu, ou une session live, fait
#     basculer la machine en mode secours et proposer une restauration a
#     quelqu'un qui n'a rien demande.
#
# Les commandes systemctl et loginctl sont remplacees par des stubs: on valide
# la LOGIQUE de decision. Le comportement reel doit etre valide en VM.
#
# Usage: bash tests/test-boot-sentinel.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SENTINEL="${ROOT}/packages/boot-sentinel/auxinux-boot-sentinel"
RESCUE="${ROOT}/packages/boot-sentinel/auxinux-rescue"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

STUBS="${WORK}/bin"
mkdir -p "${STUBS}"

# --- Stubs pilotes par des fichiers, pour changer d'etat sans reecrire ------
cat > "${STUBS}/systemctl" <<'STUB'
#!/bin/sh
[ "$1" = "get-default" ] && { cat "${STUB_DEFAULT_TARGET_FILE}"; exit 0; }
[ "$1" = "is-active" ] && { cat "${STUB_DM_STATE_FILE}"; exit 0; }
exit 0
STUB
cat > "${STUBS}/loginctl" <<'STUB'
#!/bin/sh
# list-sessions --no-legend : une ligne par session
if [ "$1" = "list-sessions" ]; then cat "${STUB_SESSIONS_FILE}"; exit 0; fi
# show-session ID -p Type --value | -p State --value
if [ "$1" = "show-session" ]; then
  case "$3" in
    -p) key="$4" ;;
  esac
  grep "^$2 " "${STUB_SESSIONS_DETAIL}" | awk -v k="${key}" \
    '{ if (k == "Type") print $2; else print $3 }'
  exit 0
fi
exit 0
STUB
chmod 755 "${STUBS}/systemctl" "${STUBS}/loginctl"

export PATH="${STUBS}:${PATH}"
export STUB_DEFAULT_TARGET_FILE="${WORK}/default-target"
export STUB_SESSIONS_FILE="${WORK}/sessions"
export STUB_SESSIONS_DETAIL="${WORK}/sessions-detail"
export STUB_DM_STATE_FILE="${WORK}/dm-state"
export AUXINUX_STATE_DIR="${WORK}/state"
export AUXINUX_RUN_DIR="${WORK}/run"
export AUXINUX_CMDLINE="${WORK}/cmdline"
export AUXINUX_LIVE_MARKER="${WORK}/live-medium"

reset_env() {
  rm -rf "${AUXINUX_STATE_DIR}" "${AUXINUX_RUN_DIR}" "${AUXINUX_LIVE_MARKER}"
  mkdir -p "${AUXINUX_STATE_DIR}" "${AUXINUX_RUN_DIR}"
  echo "graphical.target" > "${STUB_DEFAULT_TARGET_FILE}"
  # Par defaut le gestionnaire d'affichage est en echec: c'est le cas qui doit
  # declencher la protection.
  echo "failed" > "${STUB_DM_STATE_FILE}"
  : > "${STUB_SESSIONS_FILE}"
  : > "${STUB_SESSIONS_DETAIL}"
  echo "root=UUID=x ro" > "${AUXINUX_CMDLINE}"
}

count() { cat "${AUXINUX_STATE_DIR}/boot-failures" 2>/dev/null || echo "absent"; }
rescue_flag() { [[ -e "${AUXINUX_RUN_DIR}/rescue" ]] && echo pose || echo absent; }

echo "== 1. Systeme graphique normal: le compteur monte, le seuil declenche =="
reset_env
"${SENTINEL}" arm >/dev/null
check "premiere tentative comptee" "$(count)" "1"
check "pas encore de mode secours" "$(rescue_flag)" "absent"
"${SENTINEL}" arm >/dev/null
check "deuxieme tentative comptee" "$(count)" "2"
check "mode secours arme au seuil" "$(rescue_flag)" "pose"

echo "== 2. Une session graphique ACTIVE remet tout a zero =="
printf '3 1000 utilisateur seat0 -\n' > "${STUB_SESSIONS_FILE}"
printf '3 wayland active\n' > "${STUB_SESSIONS_DETAIL}"
AUXINUX_WATCH_TIMEOUT=6 "${SENTINEL}" watch >/dev/null
check "compteur remis a zero" "$(count)" "0"
check "mode secours desarme" "$(rescue_flag)" "absent"

echo "== 3. Une session NON graphique ne compte pas comme un succes =="
reset_env
"${SENTINEL}" arm >/dev/null
# tty active: c'est exactement le cas ou sddm est mort et ou l'utilisateur est
# tombe sur la console de secours. Le compter comme un succes desarmerait la
# protection au pire moment.
printf '5 1000 utilisateur seat0 tty2\n' > "${STUB_SESSIONS_FILE}"
printf '5 tty active\n' > "${STUB_SESSIONS_DETAIL}"
AUXINUX_WATCH_TIMEOUT=3 "${SENTINEL}" watch >/dev/null
check "compteur conserve" "$(count)" "1"

echo "== 4. Une session graphique INACTIVE ne compte pas non plus =="
reset_env
"${SENTINEL}" arm >/dev/null
printf '7 1000 utilisateur seat0 -\n' > "${STUB_SESSIONS_FILE}"
printf '7 wayland closing\n' > "${STUB_SESSIONS_DETAIL}"
AUXINUX_WATCH_TIMEOUT=3 "${SENTINEL}" watch >/dev/null
check "compteur conserve" "$(count)" "1"

echo "== 5. Medium live: aucune protection (autologin, pas d'instantane) =="
reset_env
echo "boot=live components username=auxinux" > "${AUXINUX_CMDLINE}"
"${SENTINEL}" arm >/dev/null
check "rien n'est compte sur le live" "$(count)" "absent"
check "aucun mode secours sur le live" "$(rescue_flag)" "absent"
reset_env
mkdir -p "${AUXINUX_LIVE_MARKER}"
"${SENTINEL}" arm >/dev/null
check "medium live detecte aussi par /run/live/medium" "$(count)" "absent"
reset_env
echo "BOOT_IMAGE=/@snapshots/5/snapshot/boot/vmlinuz ro auxinux.snapshot=1" > "${AUXINUX_CMDLINE}"
echo 2 > "${AUXINUX_STATE_DIR}/boot-failures"
"${SENTINEL}" arm >/dev/null
check "instantane demarre depuis GRUB: compteur non juge" "$(count)" "2"
check "instantane demarre depuis GRUB: pas de mode secours" "$(rescue_flag)" "absent"

echo "== 6. Cible par defaut non graphique: aucune protection =="
reset_env
echo "multi-user.target" > "${STUB_DEFAULT_TARGET_FILE}"
"${SENTINEL}" arm >/dev/null
check "un demarrage console voulu n'est pas un echec" "$(count)" "absent"

echo "== 7. Compteur corrompu: repart de zero au lieu de planter =="
reset_env
printf 'du-texte\n' > "${AUXINUX_STATE_DIR}/boot-failures"
"${SENTINEL}" arm >/dev/null
check "valeur illisible traitee comme zero" "$(count)" "1"

echo "== 8. status et reset =="
reset_env
"${SENTINEL}" arm >/dev/null
out="$("${SENTINEL}" status)"
check "status: compteur" "$(echo "${out}" | sed -n 's/^failures=//p')" "1"
check "status: seuil secours" "$(echo "${out}" | sed -n 's/^rescue_threshold=//p')" "2"
check "status: etat" "$(echo "${out}" | sed -n 's/^state=//p')" "normal"
"${SENTINEL}" reset >/dev/null
check "reset remet a zero" "$(count)" "0"

echo "== 8b. Ecran de connexion inutilise: ce N'EST PAS une panne =="
# Quelqu'un allume sa machine et s'en va. Deux demarrages comme celui-la
# auraient suffi a envoyer la machine en mode secours et a lui proposer une
# restauration dont elle n'avait aucun besoin. Le signe qui distingue les deux
# cas est l'etat du gestionnaire d'affichage.
reset_env
"${SENTINEL}" arm >/dev/null
echo "active" > "${STUB_DM_STATE_FILE}"
AUXINUX_WATCH_TIMEOUT=3 "${SENTINEL}" watch >/dev/null
check "compteur remis a zero" "$(count)" "0"
check "aucun mode secours" "$(rescue_flag)" "absent"

echo "== 8c. Gestionnaire d'affichage en echec: la protection s'arme =="
reset_env
"${SENTINEL}" arm >/dev/null
echo "failed" > "${STUB_DM_STATE_FILE}"
AUXINUX_WATCH_TIMEOUT=3 "${SENTINEL}" watch >/dev/null
check "compteur conserve" "$(count)" "1"

echo "== 9. Choix de l'instantane a restaurer =="
# La regle: le dernier « pre » (pose juste AVANT une transaction de paquets,
# premiere cause d'un bureau qui ne demarre plus), sinon le dernier point pose a
# la main ou a l'installation, sinon la derniere sauvegarde quotidienne; jamais
# un « boot » ni un « post ».
cat > "${STUBS}/snapper" <<'STUB'
#!/bin/sh
cat "${STUB_SNAPPER_CSV}"
STUB
chmod 755 "${STUBS}/snapper"
export STUB_SNAPPER_CSV="${WORK}/snapper.csv"

cat > "${STUB_SNAPPER_CSV}" <<'CSV'
number,type,date,description
0,single,,current
3,single,2026-09-01 08:00:00,Installation initiale
7,pre,2026-09-11 10:15:00,auxi upgrade
8,post,2026-09-11 10:18:00,
9,single,2026-09-12 11:00:00,timeline
CSV
check "le dernier « pre » est prefere" "$("${RESCUE}" --pick-snapshot)" "7"

cat > "${STUB_SNAPPER_CSV}" <<'CSV'
number,type,date,description
0,single,,current
3,single,2026-09-01 08:00:00,Installation initiale
9,single,2026-09-12 11:00:00,timeline
CSV
# Sans « pre », un point pose a la main ou a l'installation passe AVANT la
# sauvegarde automatique: celle-ci peut avoir ete prise pendant un demarrage
# rate (le minuteur quotidien rattrape au demarrage une sauvegarde manquee).
check "sans « pre », l'installation avant la sauvegarde automatique" "$("${RESCUE}" --pick-snapshot)" "3"

cat > "${STUB_SNAPPER_CSV}" <<'CSV'
number,type,date,description
0,single,,current
CSV
check "aucun instantane utilisable: rien, pas le 0" "$("${RESCUE}" --pick-snapshot)" ""

# Panne du 2026-10-04: un instantane « boot » est pris PENDANT le demarrage qui
# echoue. Le restaurer remettait la panne elle-meme, a chaque tour.
cat > "${STUB_SNAPPER_CSV}" <<'CSV'
number,type,date,description
0,single,,current
1,single,2026-10-04 13:10:50,Installation initiale AuxiNuxOS
2,single,2026-10-04 13:32:49,boot
3,single,2026-10-04 14:00:07,timeline
4,single,2026-10-04 14:06:49,boot
5,single,2026-10-04 14:07:26,boot
CSV
check "jamais un instantane de demarrage; l'installation avant la sauvegarde du jour" \
  "$("${RESCUE}" --pick-snapshot)" "1"

cat > "${STUB_SNAPPER_CSV}" <<'CSV'
number,type,date,description
0,single,,current
3,single,2026-10-04 14:00:07,timeline
5,single,2026-10-04 14:07:26,boot
CSV
check "a defaut, la derniere sauvegarde quotidienne" "$("${RESCUE}" --pick-snapshot)" "3"

cat > "${STUB_SNAPPER_CSV}" <<'CSV'
number,type,date,description
0,single,,current
7,pre,2026-09-11 10:15:00,auxi upgrade
8,post,2026-09-11 10:18:00,
CSV
check "jamais un « post »" "$("${RESCUE}" --pick-snapshot)" "7"

echo "== 10. Verrou anti-boucle: pas deux restaurations automatiques du meme instantane =="
RSTATE="${WORK}/rescue-state"
mkdir -p "${RSTATE}"
: > "${WORK}/snapper-root"
cat > "${STUBS}/auxi" <<'STUB'
#!/bin/sh
echo "$*" >> "${STUB_AUXI_LOG}"
exit 0
STUB
for c in clear journalctl; do printf '#!/bin/sh\nexit 0\n' > "${STUBS}/${c}"; done
chmod 755 "${STUBS}/auxi" "${STUBS}/clear" "${STUBS}/journalctl"
export STUB_AUXI_LOG="${WORK}/auxi.log"
run_rescue() {
  : > "${STUB_AUXI_LOG}"
  AUXINUX_STATE_DIR="${RSTATE}" AUXINUX_SNAPPER_CONF="${WORK}/snapper-root" \
    AUXINUX_SENTINEL="${WORK}/absent" timeout 20 "${RESCUE}" --auto </dev/null >/dev/null 2>&1
}
printf '7\n' > "${RSTATE}/last-restore"
run_rescue
check "instantane deja restaure: aucune restauration automatique" "$(wc -l < "${STUB_AUXI_LOG}")" "0"
rm -f "${RSTATE}/last-restore"
# Sans restauration anterieure, le 3e echec restaure bien (sleep neutralise;
# le stub systemctl absorbe le redemarrage).
printf '#!/bin/sh\nexit 0\n' > "${STUBS}/sleep"; chmod 755 "${STUBS}/sleep"
run_rescue
check "premier essai: restauration automatique de l'instantane 7" "$(cat "${STUB_AUXI_LOG}")" "rollback 7 --yes"
rm -f "${STUBS}/sleep"

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; fi
exit "${fail}"
