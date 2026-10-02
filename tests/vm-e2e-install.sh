#!/bin/bash
# Installation complete de validation, sans intervention: live -> Calamares ->
# « Terminé » -> redemarrage -> GRUB -> SDDM -> session Plasma.
# Usage: run-e2e.sh NOM ISO
set -u
name="$1"; iso="$2"
B=/dev/shm/e2e/$name
V="./vm-driver.py"
cd "$(dirname "$0")"
log() { echo "$(date -u +%H:%M:%S) $*"; }
shot() { $V shot "$name" "$B/$1.png" >/dev/null 2>&1; }
size() { stat -c %s "$B/$1.png" 2>/dev/null || echo 0; }
wait_big() { # capture NOM seuil_octets delai_max_s
  local t=0
  while [ $t -lt "$3" ]; do shot "$1"; [ "$(size "$1")" -gt "$2" ] && return 0; sleep 20; t=$((t+20)); done
  return 1
}

rm -f /mnt/build/e2e/$name-disk.raw; rm -rf "$B"
./vm-boot-live-serial.sh "$name" "$iso" /mnt/build/e2e/$name-disk.raw || { log "ECHEC live"; exit 1; }
$V sh "$name" "dmesg -n 1" --timeout 60 >/dev/null
log "live pret, attente du bureau"
wait_big w 200000 1200 || { log "ECHEC bureau live"; exit 1; }
sleep 30
$V click "$name" 770 505; sleep 40
$V click "$name" 639 492; sleep 25
for try in 1 2 3 4; do
  # 2e icone du bureau: depuis le 2026-10-02, « AuxiNux OS Center » precede
  # « Install AuxiNuxOS » (ordre alphabetique), et le banc ouvrait le centre.
  $V click "$name" 173 45 --double; sleep 50
  n=$($V sh "$name" "pgrep -c -x calamares" --timeout 60 | head -1)
  [ "${n:-0}" -ge 1 ] 2>/dev/null && break
done
sleep 20; shot c1
$V click "$name" 1000 643; sleep 30; shot c3      # emplacement
$V click "$name" 1000 643; sleep 35; shot c4      # clavier
$V click "$name" 1000 643; sleep 60; shot c5      # partitions
$V click "$name" 1000 643; sleep 30               # utilisateurs
$V click "$name" 424 198; sleep 2; $V type "$name" "Marie Tremblay"; sleep 3
$V click "$name" 424 266; sleep 2; $V key "$name" end shift-home; sleep 1; $V type "$name" "marie"; sleep 2
$V click "$name" 424 402; sleep 2; $V type "$name" "Quebec2026/"; sleep 2
$V click "$name" 630 402; sleep 2; $V type "$name" "Quebec2026/"; sleep 10; shot c6
$V click "$name" 1000 643; sleep 30; shot c7      # resume
$V click "$name" 997 732; sleep 20; shot c8
$V click "$name" 679 424; $V key "$name" ctrl-alt-f3
log "installation lancee"
./vm-wait-install.sh "$name" > "$B/wait.out" 2>&1; rc=$?
log "fin installation rc=$rc"; tail -4 "$B/wait.out"
$V sh "$name" "grep -E 'completion|ECHEC|verify-installed-boot' /home/auxinux/.cache/calamares/session.log | tail -5" --timeout 120
[ $rc -eq 0 ] || exit 1
$V key "$name" ctrl-alt-f2; sleep 30; shot f1
L=$B/serial.log; n0=$(wc -c < "$L")
$V click "$name" 1102 732                          # Terminé (redemarrer)
for i in $(seq 1 60); do tail -c +"$n0" "$L" | grep -aq "BdsDxe: starting" && break; sleep 5; done
tail -c +"$n0" "$L" | grep -a "BdsDxe: starting" | tail -1 | cut -c1-100
log "redemarrage, attente GRUB puis SDDM"
sleep 40; shot g1
wait_big sddm 150000 1500 || { log "ECHEC: pas d'ecran de connexion"; shot sddm-echec; exit 2; }
sleep 20; shot sddm
$V click "$name" 622 476; sleep 2; $V type "$name" "Quebec2026/"; sleep 1; $V key "$name" ret
sleep 60
wait_big bureau 400000 900 || { log "ECHEC: pas de bureau"; exit 3; }
sleep 40; shot bureau
log "BUREAU ATTEINT"
