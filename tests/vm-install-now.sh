#!/bin/bash
# Installation complete par l'installateur console « Install NOW », sans
# intervention: entree GRUB par defaut -> ecrans -> installation -> Entree
# (redemarrage) -> SDDM -> bureau. Usage: vm-install-now.sh NOM ISO
#
# Choix: francais, en ligne, Toronto, clavier Francais (Canada), disque entier
# SANS chiffrement, Firefox seul (+ Bottles, toujours installe; AuxiNux Office
# est dans l'image, il n'y a plus de question bureautique), profil
# Bureautique sans suggestion, aucun outil de vie privee -- le plus court
# chemin qui exerce TOUTES les etapes du moteur.
set -u
name="$1"; iso="$2"
B=/dev/shm/e2e/$name
V="./vm-driver.py"
cd "$(dirname "$0")"
log() { echo "$(date -u +%H:%M:%S) $*"; }
shot() { $V shot "$name" "$B/$1.png" >/dev/null 2>&1; }

rm -f /mnt/build/e2e/$name-disk.raw; rm -rf "$B"
AUXINUX_ENTREE=0 ./vm-boot-live-serial.sh "$name" "$iso" /mnt/build/e2e/$name-disk.raw || { log "ECHEC live"; exit 1; }
$V sh "$name" "dmesg -n 1; systemctl is-active auxinux-installer" --timeout 60
sleep 10; shot e0
k() { $V key "$name" "$@"; sleep 3; }
k ret; sleep 20; shot e1                      # langue -> reseau (en ligne)
k ret; sleep 8; k ret; sleep 6; k ret; sleep 6; shot e2   # reseau, fuseau, clavier
k ret; sleep 4                                # disque (sans chiffrement)
$V type "$name" "Marie Tremblay"; k tab; k tab; k tab
$V type "$name" "Quebec2026"; k tab; $V type "$name" "Quebec2026"; k ret; sleep 4
k ret; k down down down; k ret               # Firefox, pas de lecteur (AuxiNux Office est inclus)
k spc; k down; k spc; k ret                   # profil: aucune suggestion
for i in 1 2 3 4 5; do k spc; k down; done; k ret   # aucun outil de vie privee
shot e3
$V type "$name" "OUI"; k ret
log "installation lancee"
for i in $(seq 1 45); do
  sleep 120
  r=$($V sh "$name" "grep -cE '^Installation terminee|auxinux-erreur' /var/log/auxinux-installation.log; grep ^auxinux-etape /var/log/auxinux-installation.log | tail -1" --timeout 90 | head -2 | tr '\n' ' ')
  log "$r"
  case "$r" in [1-9]*) break;; esac
done
shot fin
$V sh "$name" "grep -E 'auxinux-erreur|^Installation terminee' /var/log/auxinux-installation.log" --timeout 60
$V sh "$name" "grep -q '^Installation terminee' /var/log/auxinux-installation.log" --timeout 60 | grep -q "rc=0" \
  || { log "ECHEC installation"; exit 2; }
$V eject "$name" >/dev/null 2>&1
L=$B/serial.log; n0=$(wc -c < "$L")
k ret                                         # « Entree pour redemarrer »
for i in $(seq 1 60); do tail -c +"$n0" "$L" | grep -aq "BdsDxe: starting" && break; sleep 5; done
tail -c +"$n0" "$L" | grep -a "BdsDxe: starting" | tail -1 | cut -c1-90
for i in $(seq 1 60); do sleep 20; shot sddm; [ "$(stat -c %s "$B/sddm.png")" -gt 150000 ] && break; done
sleep 20; shot sddm
$V click "$name" 622 476; sleep 2; $V type "$name" "Quebec2026"; $V key "$name" ret
for i in $(seq 1 40); do sleep 20; shot bureau; [ "$(stat -c %s "$B/bureau.png")" -gt 400000 ] && break; done
sleep 60; shot bureau
log "BUREAU ATTEINT"
