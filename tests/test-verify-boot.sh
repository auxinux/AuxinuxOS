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

# Machine BIOS par defaut: les cas 1 a 7 ne regardent pas la partition EFI,
# quel que soit le micrologiciel de l'hote qui execute ce banc.
export AUXINUX_EFI_SYSFS="${WORK}/pas-d-efi"
# Et sans grub-fstest: les cas 1 a 12 ne dependent pas de l'outil de l'hote,
# qui lirait sinon le VRAI disque de la machine qui execute ce banc.
export AUXINUX_GRUB_FSTEST="${WORK}/grub-fstest-absent"
# Noms EFI de l'edition amd64 (x64) quelle que soit la machine de test; le cas
# 12d passe en arm64 (aa64).
export AUXINUX_ARCH=amd64

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

echo "== 5b. /boot sur une partition separee -> laisse passer =="
# Partitionnement manuel: grub.cfg designe alors « /vmlinuz-... », relatif a la
# partition /boot. La verification le prenait pour un noyau absent et faisait
# echouer une installation saine.
T="${WORK}/bootsepare"; make_target "${T}" 12288 34816 "/vmlinuz-${KVER}"
sed -i "s|initrd\t/@/boot/|initrd\t/|" "${T}/boot/grub/grub.cfg"
bash "${VERIFY}" "${T}" >/dev/null 2>&1
check "sort en 0" "$?" "0"

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

# --- Partition EFI -----------------------------------------------------------
#
# Le micrologiciel ne lit que la partition EFI. Le GRUB signe de Debian y suit
# le grub.cfg pose a cote de lui, qui designe la racine par son UUID: s'il
# manque ou vise un autre disque, la machine s'arrete sur « grub> ».
mkdir -p "${WORK}/efi-sysfs"
cat > "${STUBS}/findmnt" <<'STUB'
#!/bin/sh
echo "${FINDMNT_UUID:-}"
STUB
chmod 755 "${STUBS}/findmnt"
export FINDMNT_UUID="0d2c1e9a-7b36-4c55-9a5f-1e2d3c4b5a69"

make_esp() {
  local t="$1"
  mkdir -p "${t}/boot/efi/EFI/AuxiNuxOS" "${t}/boot/efi/EFI/BOOT"
  printf 'x' > "${t}/boot/efi/EFI/AuxiNuxOS/grubx64.efi"
  printf 'x' > "${t}/boot/efi/EFI/AuxiNuxOS/shimx64.efi"
  printf "search.fs_uuid %s root\nconfigfile (\$root)/@/boot/grub/grub.cfg\n" "${FINDMNT_UUID}" \
    > "${t}/boot/efi/EFI/AuxiNuxOS/grub.cfg"
  printf 'x' > "${t}/boot/efi/EFI/BOOT/BOOTX64.EFI"
  cp "${t}/boot/efi/EFI/AuxiNuxOS/grub.cfg" "${t}/boot/efi/EFI/BOOT/grub.cfg"
}

echo "== 8. UEFI: partition EFI complete -> laisse passer =="
T="${WORK}/uefi-sain"; make_target "${T}" 12288 34816; make_esp "${T}"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 0" "${rc}" "0"
check "partition EFI jugee complete" "$(grep -c 'EFI/AuxiNuxOS complet' <<<"${out}")" "1"
check "chemin de secours juge complet" "$(grep -c 'chemin de secours EFI/BOOT/BOOTX64.EFI complet' <<<"${out}")" "1"

echo "== 9. UEFI: grub.cfg absent de EFI/AuxiNuxOS -> echoue =="
T="${WORK}/uefi-sanscfg"; make_target "${T}" 12288 34816; make_esp "${T}"
rm -f "${T}/boot/efi/EFI/AuxiNuxOS/grub.cfg"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "annonce l'invite grub>" "$(grep -c 'invite « grub> »' <<<"${out}")" "1"

echo "== 10. UEFI: grub.cfg vise un autre disque -> echoue =="
T="${WORK}/uefi-uuid"; make_target "${T}" 12288 34816; make_esp "${T}"
sed -i 's/0d2c1e9a/ffffffff/' "${T}/boot/efi/EFI/AuxiNuxOS/grub.cfg"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "nomme l'UUID attendu" "$(grep -c "UUID ${FINDMNT_UUID}" <<<"${out}")" "1"

echo "== 11. UEFI: chemin de secours incomplet -> avertit sans bloquer =="
T="${WORK}/uefi-secours"; make_target "${T}" 12288 34816; make_esp "${T}"
rm -f "${T}/boot/efi/EFI/BOOT/grub.cfg"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 0" "${rc}" "0"
check "avertit" "$(grep -c 'chemin de secours EFI/BOOT incomplet' <<<"${out}")" "1"

echo "== 12. UEFI: aucun GRUB sur la partition EFI -> echoue =="
T="${WORK}/uefi-vide"; make_target "${T}" 12288 34816; mkdir -p "${T}/boot/efi/EFI"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
echo "== 12b. UEFI, disque chiffre: GRUB autonome sans grub.cfg -> laisse passer =="
# L'installateur maison construit un GRUB NON signe qui embarque sa
# configuration (cryptomount, chemin du menu): ni shim, ni grub.cfg a cote.
T="${WORK}/uefi-autonome"; make_target "${T}" 12288 34816; make_esp "${T}"
rm -f "${T}/boot/efi/EFI/AuxiNuxOS/shimx64.efi" "${T}/boot/efi/EFI/AuxiNuxOS/grub.cfg" \
      "${T}/boot/efi/EFI/BOOT/grub.cfg"
printf 'MZ...cryptomount -u 4f1d...' > "${T}/boot/efi/EFI/AuxiNuxOS/grubx64.efi"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 0" "${rc}" "0"
check "reconnu comme GRUB autonome" "$(grep -c 'GRUB autonome' <<<"${out}")" "1"
check "chemin de secours accepte sans grub.cfg" "$(grep -c 'chemin de secours EFI/BOOT/BOOTX64.EFI complet' <<<"${out}")" "1"

echo "== 12c. UEFI: GRUB non signe SANS configuration -> echoue =="
T="${WORK}/uefi-nu"; make_target "${T}" 12288 34816; make_esp "${T}"
rm -f "${T}/boot/efi/EFI/AuxiNuxOS/shimx64.efi" "${T}/boot/efi/EFI/AuxiNuxOS/grub.cfg"
out="$(AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "annonce l'invite grub>" "$(grep -c 'invite « grub> »' <<<"${out}")" "1"

echo "== 12d. Edition ARM (arm64): noms aa64 sur la partition EFI =="
T="${WORK}/uefi-arm64"; make_target "${T}" 12288 34816; make_esp "${T}"
for f in "${T}"/boot/efi/EFI/AuxiNuxOS/*x64.efi; do mv "${f}" "${f%x64.efi}aa64.efi"; done
mv "${T}/boot/efi/EFI/BOOT/BOOTX64.EFI" "${T}/boot/efi/EFI/BOOT/BOOTAA64.EFI"
out="$(AUXINUX_ARCH=arm64 AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "arm64: sort en 0" "${rc}" "0"
check "arm64: partition EFI jugee complete" "$(grep -c 'EFI/AuxiNuxOS complet' <<<"${out}")" "1"
check "arm64: chemin de secours BOOTAA64.EFI complet" "$(grep -c 'chemin de secours EFI/BOOT/BOOTAA64.EFI complet' <<<"${out}")" "1"
# Les memes fichiers, lus avec les noms amd64: rien a demarrer.
out="$(AUXINUX_ARCH=amd64 AUXINUX_EFI_SYSFS="${WORK}/efi-sysfs" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "noms aa64 sur une machine amd64: echoue" "${rc}" "1"
check "nomme grubx64.efi" "$(grep -c 'grubx64.efi absent' <<<"${out}")" "1"
rm -f "${STUBS}/findmnt"

# --- Relecture par le pilote de GRUB (grub-fstest) --------------------------
#
# LA panne du 2026-09-13, enfin comprise le 2026-09-29: le noyau finit par un
# trou (rsync -S), Linux le lit comme des zeros, GRUB s'arrete avant. Seule
# une relecture par le code de GRUB le voit. Le stub imite grub-fstest: il
# copie le fichier de la cible, ou n'en rend que le debut (lecture courte).
cat > "${STUBS}/grub-fstest" <<'STUB'
#!/bin/sh
# grub-fstest PERIPHERIQUE cp (loop0)CHEMIN SORTIE
src="${3#(loop0)}"; src="${src#/@}"
if [ "${FSTEST_COURT:-0}" = 1 ] && [ "${src#*vmlinuz}" != "${src}" ]; then
  head -c 4096 "${FSTEST_ROOT}${src}" > "$4"
else
  cp "${FSTEST_ROOT}${src}" "$4"
fi
STUB
chmod 755 "${STUBS}/grub-fstest"
cat > "${STUBS}/findmnt" <<'STUB'
#!/bin/sh
echo "/dev/null[/@]"
STUB
chmod 755 "${STUBS}/findmnt"

echo "== 13. GRUB relit noyau et initrd en entier -> laisse passer =="
T="${WORK}/grub-lit"; make_target "${T}" 12288 34816
out="$(AUXINUX_GRUB_FSTEST="${STUBS}/grub-fstest" FSTEST_ROOT="${T}" bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 0" "${rc}" "0"
check "noyau et initrd relus par GRUB" "$(grep -c 'relu en entier par le pilote de GRUB' <<<"${out}")" "2"

echo "== 14. GRUB s'arrete avant la fin du noyau -> echoue =="
T="${WORK}/grub-court"; make_target "${T}" 12288 34816
out="$(AUXINUX_GRUB_FSTEST="${STUBS}/grub-fstest" FSTEST_ROOT="${T}" FSTEST_COURT=1 bash "${VERIFY}" "${T}" 2>&1)"; rc=$?
check "sort en 1" "${rc}" "1"
check "annonce la fin prematuree" "$(grep -c 'GRUB ne relit que 4096 octets' <<<"${out}")" "1"
check "donne la commande de correction" "$(grep -c 'sparse=never' <<<"${out}")" "1"
rm -f "${STUBS}/grub-fstest" "${STUBS}/findmnt"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
