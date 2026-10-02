#!/bin/bash
# Demarre l'ISO en VM UEFI, ajoute la console serie a l'entree live, et ouvre
# un shell root sur cette console.   Usage: boot-live.sh NOM ISO DISQUE
set -u
name="$1"; iso="$2"; disk="$3"
cd "$(dirname "$0")"
./vm-driver.py start "$name" --iso "$iso" --disk "$disk" --size 60G --mem 4608 --cpus 4 || exit 1
# Retient le menu GRUB: toute touche arrete le compte a rebours.
for i in $(seq 1 50); do ./vm-driver.py key "$name" up >/dev/null 2>&1; sleep 2; done
# Entree GRUB: 0 = « Installer maintenant » (par defaut depuis le
# 2026-10-02), 1 = bureau live (Calamares). Le banc vise le bureau live sauf
# AUXINUX_ENTREE=0.
for i in $(seq 1 "${AUXINUX_ENTREE:-1}"); do ./vm-driver.py key "$name" down; sleep 1; done
./vm-driver.py key "$name" e; sleep 2
./vm-driver.py key "$name" down down ctrl-e
./vm-driver.py type "$name" " console=tty0 console=ttyS0,115200 nvme_core.io_timeout=600 loglevel=3 nowatchdog nmi_watchdog=0 rcupdate.rcu_cpu_stall_suppress=1"
./vm-driver.py shot "$name" ${E2E_BASE:-/dev/shm/e2e}/$name/grub-edit.png >/dev/null
./vm-driver.py key "$name" ctrl-x
# Attente de l'invite de connexion sur la console serie.
for i in $(seq 1 120); do
  grep -aq "auxinuxos-live login:" ${E2E_BASE:-/dev/shm/e2e}/$name/serial.log 2>/dev/null && break
  sleep 10
done
sleep 5
./vm-driver.py send "$name" "auxinux\r"; sleep 5
./vm-driver.py send "$name" "auxinux\r"; sleep 15
./vm-driver.py send "$name" "sudo -i\r"; sleep 8
./vm-driver.py send "$name" "stty -echo; PS1=''; export PS1 TERM=dumb PAGER=cat SYSTEMD_PAGER=cat SYSTEMD_COLORS=0\r"; sleep 3
./vm-driver.py sh "$name" "echo 900 > /sys/block/sr0/device/timeout; id -un; uname -r" --timeout 120
