#!/usr/bin/env bash
#
# Test du chemin de restauration de `auxi rollback`.
#
# C'est l'operation la plus dangereuse du systeme: entre le deplacement de "@"
# et la creation du nouveau "@", la machine n'a PLUS de racine amorcable. Ce
# test verifie en particulier qu'un echec a cet instant precis remet bien le
# systeme d'origine en place (cas 5).
#
# Les commandes btrfs/mount/findmnt sont remplacees par des stubs: le test
# valide la LOGIQUE et l'ordre des operations, pas le comportement reel de
# BTRFS. Un vrai rollback doit etre valide en VM (voir tests/README.md).
#
# Usage: bash tests/test-rollback.sh
set -uo pipefail

AUXI_BIN="${AUXI_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxi-cli/auxi}"
if [[ ! -r "${AUXI_BIN}" ]]; then
  echo "auxi introuvable: ${AUXI_BIN}" >&2
  exit 66
fi

source "${AUXI_BIN}" >/dev/null
# auxi active `set -euo pipefail`: on le desactive pour pouvoir observer les
# codes de sortie des cas d'echec au lieu d'arreter le harnais.
set +e

TOP="$(mktemp -d)"
BTRFS_TOPLEVEL_MNT="${TOP}/toplevel"

require_snapshots() { return 0; }
require_root_for_config() { return 0; }
findmnt() { echo "/dev/loop9[/@]"; }
mount() { echo "STUB mount $*"; return 0; }
umount() { echo "STUB umount $*"; return 0; }

BTRFS_SHOULD_FAIL=0
btrfs() {
  echo "STUB btrfs $*"
  if [[ "${BTRFS_SHOULD_FAIL}" == "1" ]]; then
    echo "STUB btrfs: echec simule" >&2
    return 1
  fi
  mkdir -p "${4:-}"   # btrfs subvolume snapshot SRC DEST
  return 0
}

reset_fs() {
  rm -rf "${BTRFS_TOPLEVEL_MNT}"
  mkdir -p "${BTRFS_TOPLEVEL_MNT}/@/etc"
  echo "systeme-actuel" > "${BTRFS_TOPLEVEL_MNT}/@/marqueur"
  mkdir -p "${BTRFS_TOPLEVEL_MNT}/@snapshots/7/snapshot"
  mkdir -p "${BTRFS_TOPLEVEL_MNT}/@home"
}

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

echo "== 1. Numero invalide =="
reset_fs
( run_rollback "abc" ) >/dev/null 2>&1
check "sort en 64" "$?" "64"

echo "== 2. Instantane inexistant =="
reset_fs
( run_rollback 99 --yes ) >/dev/null 2>&1
check "sort en 69" "$?" "69"
check "@ intact" "$(cat "${BTRFS_TOPLEVEL_MNT}/@/marqueur")" "systeme-actuel"

echo "== 3. Refus a la confirmation =="
reset_fs
echo "n" | run_rollback 7 >/dev/null 2>&1
check "@ non deplace" "$([[ -d "${BTRFS_TOPLEVEL_MNT}/@" ]] && echo oui)" "oui"
check "aucun @.rollback-*" "$(ls -d "${BTRFS_TOPLEVEL_MNT}"/@.rollback-* 2>/dev/null | wc -l)" "0"

echo "== 4. Rollback nominal =="
reset_fs
BTRFS_SHOULD_FAIL=0
run_rollback 7 --yes >/dev/null 2>&1
check "un @.rollback-* cree" "$(ls -d "${BTRFS_TOPLEVEL_MNT}"/@.rollback-* 2>/dev/null | wc -l)" "1"
check "ancien systeme conserve" "$(cat "${BTRFS_TOPLEVEL_MNT}"/@.rollback-*/marqueur)" "systeme-actuel"
check "nouveau @ present" "$([[ -d "${BTRFS_TOPLEVEL_MNT}/@" ]] && echo oui)" "oui"
check "@home intact" "$([[ -d "${BTRFS_TOPLEVEL_MNT}/@home" ]] && echo oui)" "oui"
check "@snapshots preserve" "$([[ -d "${BTRFS_TOPLEVEL_MNT}/@snapshots/7/snapshot" ]] && echo oui)" "oui"
# Panne du 2026-10-04: le compteur de demarrages rates est restaure avec la
# racine. Il doit repartir de zero DANS le systeme restaure.
check "compteur de demarrages remis a zero dans le systeme restaure" \
  "$(cat "${BTRFS_TOPLEVEL_MNT}/@/var/lib/auxinux/boot-failures" 2>/dev/null)" "0"
check "instantane restaure note pour le verrou anti-boucle" \
  "$(cat "${BTRFS_TOPLEVEL_MNT}/@/var/lib/auxinux/last-restore" 2>/dev/null)" "7"

echo "== 5. Echec btrfs -> restauration de l'original (cas critique) =="
reset_fs
BTRFS_SHOULD_FAIL=1
( run_rollback 7 --yes ) >/dev/null 2>&1
check "sort en 69" "$?" "69"
check "@ remis en place" "$(cat "${BTRFS_TOPLEVEL_MNT}/@/marqueur" 2>/dev/null)" "systeme-actuel"
check "aucun @.rollback-* orphelin" "$(ls -d "${BTRFS_TOPLEVEL_MNT}"/@.rollback-* 2>/dev/null | wc -l)" "0"

rm -rf "${TOP}"
echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
