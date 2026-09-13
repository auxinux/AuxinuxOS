#!/usr/bin/env bash
# Fabrique l'ISO amorcable: BIOS, UEFI, et UEFI AVEC SECURE BOOT.
#
# POURQUOI CE SCRIPT EXISTE, ET POURQUOI PLUS grub-mkrescue:
#
# grub-mkrescue fabrique lui-meme l'image EFI, avec un GRUB qu'il compile sur
# place -- donc NON SIGNE. Resultat, verifie en VM le 2026-09-13 avec un
# micrologiciel OVMF portant les cles Microsoft (c'est-a-dire la configuration
# d'usine de la quasi-totalite des portables du commerce):
#
#   BdsDxe: failed to load Boot0001 "UEFI QEMU DVD-ROM": Access Denied
#   BdsDxe: No bootable option or device was found.
#
# L'utilisateur ne voit pas un message sur la signature: il voit une machine
# qui ignore la cle USB. Il faut desactiver Secure Boot dans le micrologiciel
# pour seulement essayer le systeme -- ce qu'une bonne partie des gens ne fera
# pas, et ce que certaines machines d'entreprise interdisent.
#
# On assemble donc l'ISO nous-memes avec la chaine signee de Debian:
#   EFI/BOOT/BOOTX64.EFI  <- shimx64.efi.signed   (signe par Microsoft)
#   EFI/BOOT/grubx64.efi  <- gcdx64.efi.signed    (signe par Debian, prefixe
#                                                  /boot/grub, variante CD)
#   EFI/BOOT/mmx64.efi    <- mmx64.efi.signed     (MokManager)
#
# Le micrologiciel verifie shim avec les cles Microsoft, shim verifie GRUB avec
# la cle Debian, GRUB lit /boot/grub/grub.cfg sur l'ISO9660. Aucune cle a
# enroler, aucune manipulation.
#
# Usage: make-iso.sh ISO_ROOT ROOTFS OUTPUT_ISO
set -euo pipefail

ISO_ROOT="${1:?usage: make-iso.sh ISO_ROOT ROOTFS OUTPUT_ISO}"
ROOTFS="${2:?}"
OUTPUT_ISO="${3:?}"

VOLID="${AUXINUX_VOLID:-AUXINUXOS}"
ESP_IMG="$(dirname "${OUTPUT_ISO}")/.esp-$$.img"
cleanup() { rm -f "${ESP_IMG}"; }
trap cleanup EXIT

SHIM="${ROOTFS}/usr/lib/shim/shimx64.efi.signed"
MOK="${ROOTFS}/usr/lib/shim/mmx64.efi.signed"
GRUB_EFI="${ROOTFS}/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed"

# Fail-closed: une ISO qui perdrait la chaine signee redeviendrait
# silencieusement inamorcable en Secure Boot, et personne ne le verrait avant
# qu'un utilisateur ne rapporte « ma machine ignore la cle USB ».
for f in "${SHIM}" "${MOK}" "${GRUB_EFI}"; do
  if [[ ! -s "${f}" ]]; then
    echo "binaire EFI signe manquant: ${f}" >&2
    echo "verifiez que shim-signed et grub-efi-amd64-signed sont installes dans le rootfs" >&2
    exit 70
  fi
done

echo "==> Construction de la partition EFI (chaine signee)"
# 16 Mo: large pour trois binaires d'environ 4 Mo au total. Une image trop
# juste fait echouer mcopy a la derniere copie, sans message clair.
#
# PAS DE `-F` (qui force FAT32). Piege verifie le 2026-09-13: sur 16 Mo avec
# des clusters d'un secteur, FAT32 ne compte que ~32 000 clusters, alors que le
# format en exige au MINIMUM 65 525. Le systeme de fichiers produit est donc
# invalide, et le micrologiciel UEFI ne le lit pas:
#
#   BdsDxe: failed to load Boot0001 "UEFI QEMU DVD-ROM": Not Found
#
# Sans `-F`, mformat choisit FAT16 d'apres la taille -- valide, et exige par la
# specification UEFI pour les medias amovibles.
rm -f "${ESP_IMG}"
truncate -s 16M "${ESP_IMG}"
mformat -i "${ESP_IMG}" -v AUXINUXEFI ::

# Controle: un FAT invalide ne se voit qu'au demarrage, et le message ne parle
# pas du systeme de fichiers.
if ! mdir -i "${ESP_IMG}" :: >/dev/null 2>&1; then
  echo "la partition EFI fabriquee n'est pas lisible" >&2
  exit 70
fi
mmd -i "${ESP_IMG}" ::/EFI ::/EFI/BOOT
mcopy -i "${ESP_IMG}" "${SHIM}"     ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "${ESP_IMG}" "${GRUB_EFI}" ::/EFI/BOOT/grubx64.efi
mcopy -i "${ESP_IMG}" "${MOK}"      ::/EFI/BOOT/mmx64.efi

# Le micrologiciel cherche EXACTEMENT ce chemin sur un media amovible.
if ! mdir -i "${ESP_IMG}" ::/EFI/BOOT 2>/dev/null | grep -qi "BOOTX64"; then
  echo "EFI/BOOT/BOOTX64.EFI absent de la partition EFI" >&2
  exit 70
fi

# Meme arborescence dans l'ISO9660: certains micrologiciels amorcent depuis la
# partition EFI, d'autres (et les cles USB copiees fichier par fichier)
# cherchent EFI/BOOT sur le systeme de fichiers principal.
install -d -m 0755 "${ISO_ROOT}/EFI/BOOT"
install -m 0644 "${SHIM}"     "${ISO_ROOT}/EFI/BOOT/BOOTX64.EFI"
install -m 0644 "${GRUB_EFI}" "${ISO_ROOT}/EFI/BOOT/grubx64.efi"
install -m 0644 "${MOK}"      "${ISO_ROOT}/EFI/BOOT/mmx64.efi"

echo "==> Construction de l'amorce BIOS"
install -d -m 0755 "${ISO_ROOT}/boot/grub/i386-pc" "${ISO_ROOT}/boot/grub/x86_64-efi"
# Les modules doivent etre SUR l'ISO: le noyau GRUB embarque le strict
# necessaire pour lire l'ISO9660 et charger le reste.
cp -a /usr/lib/grub/i386-pc/*.mod /usr/lib/grub/i386-pc/*.lst \
  "${ISO_ROOT}/boot/grub/i386-pc/" 2>/dev/null || true
cp -a /usr/lib/grub/x86_64-efi/*.mod /usr/lib/grub/x86_64-efi/*.lst \
  "${ISO_ROOT}/boot/grub/x86_64-efi/" 2>/dev/null || true

grub-mkimage -O i386-pc-eltorito -p /boot/grub \
  -o "${ISO_ROOT}/boot/grub/i386-pc/eltorito.img" \
  biosdisk iso9660 part_msdos search search_fs_uuid search_label configfile \
  normal linux linux16 echo test all_video gfxterm videoinfo loadenv minicmd \
  reboot halt sleep

echo "==> Assemblage de l'ISO"
xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "${VOLID}" \
  -rational-rock \
  -eltorito-boot boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
  -append_partition 2 0xef "${ESP_IMG}" \
  -partition_offset 16 \
  -o "${OUTPUT_ISO}" \
  "${ISO_ROOT}"

echo "==> Verification de l'amorcabilite"
xorriso -indev "${OUTPUT_ISO}" -report_el_torito plain 2>/dev/null \
  | grep -E "El Torito boot img" || true
