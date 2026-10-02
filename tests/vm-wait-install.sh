#!/bin/bash
# Attend la fin (ou l'echec) de l'installation Calamares dans la VM $1.
# Sort avec une ligne de verdict. Interroge la VM par la console serie.
name="$1"
LOG=/home/auxinux/.cache/calamares/session.log
while true; do
  out=$(timeout 90 "$(dirname "$0")"/vm-driver.py sh "$name" "echo MNT=\$(findmnt -rn | grep -c calamares-root); echo FAIL=\$(grep -c -E 'Installation failed|ERROR: ' $LOG); echo DONE=\$(grep -c 'completion: succeeded' $LOG); tail -n 1 $LOG | cut -c1-200" --timeout 80 2>&1)
  mnt=$(sed -n 's/^MNT=\([0-9]*\).*/\1/p' <<<"$out" | tail -1)
  fail=$(sed -n 's/^FAIL=\([0-9]*\).*/\1/p' <<<"$out" | tail -1)
  echo "$(date -u +%H:%M:%S) mnt=${mnt:-?} fail=${fail:-?} $(tail -n 3 <<<"$out" | head -1)" >> /tmp/vm-wait-$name.log
  if [[ -n "$fail" && "$fail" != "0" ]]; then echo "ECHEC detecte"; echo "$out"; exit 1; fi
  done_=$(sed -n 's/^DONE=\([0-9]*\).*/\1/p' <<<"$out" | tail -1)
  # « 0 montage » seul ne prouve rien: c'est aussi l'etat AVANT que Calamares
  # ne monte la cible. Seule la ligne de fin de Calamares fait foi.
  if [[ "${done_:-0}" != "0" && "$mnt" == "0" ]]; then echo "installation terminee"; echo "$out"; exit 0; fi
  sleep 240
done
