#!/usr/bin/env bash
#
# Tests de la verification finale d'amorcabilite (shellprocess@verifyboot).
#
# POURQUOI: une installation s'est deroulee sans la moindre erreur, jusqu'a la
# page « Termine », et la machine a affiche au demarrage:
#     error: premature end of file /@/boot/vmlinuz-7.1.12-auxinuxos-amd64.
# Aucun controle ne regardait le resultat: on verifiait que les COMMANDES
# avaient ete lancees, jamais que le fichier produit tenait debout.
#
# Ces tests fixent le contrat: ce script doit LAISSER PASSER une installation
# saine et FAIRE ECHOUER tout ce qui empecherait GRUB de demarrer.
#
# Usage: bash tests/test-verify-boot.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="${ROOT}/installer/verify-installed-boot.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# `sync` est remplace par un stub.
#
# verify-installed-boot.sh commence par `sync`, ce qui est JUSTE sur une vraie
# cible d'installation: il faut forcer l'ecriture avant de relire. Mais dans un
# conteneur LXC, sync() porte sur tous les systemes de fichiers visibles et
# reste bloque en etat D -- observe le 2026-09-14 sur l'hote de build ET sur la
# machine de developpement, alors que /proc/meminfo annoncait « Dirty: 0 kB ».
# Un banc d'essai ne doit pas dependre de l'etat du systeme qui l'execute.
STUBS="${WORK}/bin"
mkdir -p "${STUBS}"
printf '#!/bin/sh\nexit 0\n' > "${STUBS}/sync"
chmod 755 "${STUBS}/sync"
export PATH="${STUBS}:${PATH}"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

KVER="7.1.12-auxinuxos-amd64"

make_target() {
  local t="$1" ksize="$2" isize="$3" kpath="${4:-/@/boot/vmlinuz-${KVER}}"
  rm -rf "${t}"; mkdir -p "${t}/boot/grub"
  [[ "${ksize}" != "0" ]] && \
    dd if=/dev/zero of="${t}/boot/vmlinuz-${KVER}" bs=1024 count="${ksize}" status=none
  [[ "${isize}" != "0" ]] && \
    dd if=/dev/zero of="${t}/boot/initrd.img-${KVER}" bs=1024 count="${isize}" status=none
  printf 'menuentry x {\n\tlinux\t%s root=UUID=x ro\n\tinitrd\t/@/boot/initrd.img-%s\n}\n' \
    "${kpath}" "${KVER}" > "${t}/boot/grub/grub.cfg"
}

echo "== 1. Installation saine -> laisse passer =="
T="${WORK}/sain"; make_target "${T}" 12288 34816
bash "${VERIFY}" "${T}" >/dev/null 2>&1
check "sort en 0" "$?" "0"

echo "== 2. Noyau tronque -> echoue =="
T="${WORK}/tronque"; make_target "${T}" 40 34816
out="$(bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "signale l'ecriture tronquee" "$(grep -c 'ecriture tronquee' <<<"${out}")" "1"

echo "== 3. Aucun noyau -> echoue =="
T="${WORK}/sansnoyau"; make_target "${T}" 0 34816
out="$(bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "signale l'absence de noyau" "$(grep -c 'aucun noyau' <<<"${out}")" "1"

echo "== 4. Initramfs tronque -> echoue =="
T="${WORK}/initrd"; make_target "${T}" 12288 12
out="$(bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"

echo "== 5. grub.cfg designe un noyau absent -> echoue =="
# C'est la forme exacte de la panne rapportee: le menu propose une entree, et
# GRUB s'arrete faute de pouvoir charger ce qu'elle designe.
T="${WORK}/grubfaux"; make_target "${T}" 12288 34816 "/@/boot/vmlinuz-UNE-AUTRE-VERSION"
out="$(bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "signale l'entree menteuse" "$(grep -c 'introuvable sur le disque' <<<"${out}")" "1"

echo "== 6. grub.cfg absent -> echoue =="
T="${WORK}/sansgrub"; make_target "${T}" 12288 34816; rm -f "${T}/boot/grub/grub.cfg"
out="$(bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "signale l'absence de menu" "$(grep -c 'aucun menu de demarrage' <<<"${out}")" "1"

echo "== 7. Noyau stocke COMPRESSE -> echoue =="
# LA panne du 2026-09-13 sur materiel reel: installation declaree saine, puis
#   erreur : fin prematuree du fichier /@/boot/vmlinuz-7.2.5-auxinuxos-amd64
# Le fichier se relit parfaitement avec dd (pilote BTRFS du noyau Linux), mais
# GRUB a son propre pilote, dont le decompresseur zstd echoue. Verifier la
# relecture ne suffit donc pas: il faut verifier le STOCKAGE.
T="${WORK}/compresse"
make_target "${T}" 12288 34816
cat > "${STUBS}/filefrag" <<'STUB'
#!/bin/sh
# Imite la sortie de filefrag pour un fichier a extents compresses.
case "$*" in
  *vmlinuz*) echo "   0:        0..    4095:      12345..     16440:   4096:             encoded" ;;
  *)         echo "   0:        0..    4095:      12345..     16440:   4096:" ;;
esac
STUB
chmod 755 "${STUBS}/filefrag"
out="$(bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "nomme la compression" "$(echo "${out}" | grep -c 'stocke COMPRESSE')" "1"
check "donne la commande de correction" "$(echo "${out}" | grep -c 'compression none')" "1"
rm -f "${STUBS}/filefrag"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
