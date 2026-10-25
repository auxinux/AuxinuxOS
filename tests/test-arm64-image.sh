#!/usr/bin/env bash
#
# Edition ARM (arm64): la chaine de construction de l'image, a sec.
#
# La construction reelle demande un hote arm64 natif (mmdebstrap et chroot
# executent les binaires de l'image). Ce banc verifie, sur n'importe quel
# hote, ce qui ne depend que des scripts:
#
#   1. le filtre des listes de paquets (marqueurs [amd64] / [arm64]), et
#      qu'il ne change RIEN a l'edition amd64;
#   2. build-image.sh: architecture, repertoire de travail, refus d'une
#      architecture inconnue;
#   3. make-iso.sh en arm64: chaine signee aa64, UEFI SEULEMENT (aucune
#      partie BIOS); et en amd64: amorce BIOS toujours la. xorriso, mtools et
#      grub-mkimage sont simules;
#   4. build-debs.sh: paquet auxinux-center a l'architecture demandee, sans
#      l'assistant des .exe en arm64.
#
# Usage: bash tests/test-arm64-image.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMES="${ROOT}/image-builder/scripts/package-names.sh"
LISTS="${ROOT}/image-builder/package-lists"
MAKE_ISO="${ROOT}/image-builder/scripts/make-iso.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
in_list() { grep -qx -- "$2" <<<"$1" && echo oui || echo non; }

echo "== 1. Listes de paquets filtrees par architecture =="
AMD="$("${NAMES}" amd64 "${LISTS}"/*.txt)"
# couche-windows.txt (Wine, paquets :i386) n'est pas lue en arm64: build-image.sh
# ne l'ajoute qu'en amd64.
mapfile -t ARM_LISTS < <(ls "${LISTS}"/*.txt | grep -v '/couche-windows\.txt$')
ARM="$("${NAMES}" arm64 "${ARM_LISTS[@]}")"
check "amd64: grub-pc-bin" "$(in_list "${AMD}" grub-pc-bin)" "oui"
check "amd64: grub-efi-amd64-signed" "$(in_list "${AMD}" grub-efi-amd64-signed)" "oui"
check "amd64: decodage Intel" "$(in_list "${AMD}" intel-media-va-driver-non-free)" "oui"
check "amd64: pas de GRUB arm64" "$(in_list "${AMD}" grub-efi-arm64-signed)" "non"
check "amd64: pas d'outils invites VM" "$(in_list "${AMD}" spice-vdagent)" "non"
check "arm64: grub-efi-arm64-bin" "$(in_list "${ARM}" grub-efi-arm64-bin)" "oui"
check "arm64: grub-efi-arm64-signed" "$(in_list "${ARM}" grub-efi-arm64-signed)" "oui"
check "arm64: shim-signed (commun)" "$(in_list "${ARM}" shim-signed)" "oui"
check "arm64: pas de GRUB BIOS" "$(in_list "${ARM}" grub-pc-bin)" "non"
check "arm64: pas de GRUB amd64" "$(in_list "${ARM}" grub-efi-amd64-bin)" "non"
check "arm64: pas de decodage Intel" "$(in_list "${ARM}" intel-media-va-driver-non-free)" "non"
check "arm64: aucun paquet :i386" "$(grep -c ':i386$' <<<"${ARM}")" "0"
check "couche Windows lue en amd64 seulement" \
  "$(grep -c 'EXTRA_LISTS=(couche-windows.txt' "${ROOT}/image-builder/build-image.sh")" "1"
for p in spice-vdagent qemu-guest-agent open-vm-tools open-vm-tools-desktop; do
  check "arm64: outil invite ${p}" "$(in_list "${ARM}" "${p}")" "oui"
done
check "commentaires ignores" "$(grep -c '^#' <<<"${ARM}")" "0"
check "aucun marqueur dans les noms" "$(grep -c '\[' <<<"${AMD}${ARM}")" "0"
# Marqueurs connus seulement: une faute de frappe ([arm], [x86]) retirerait
# le paquet des DEUX editions sans rien dire.
check "marqueurs: [amd64] ou [arm64] seulement" \
  "$(grep -hoE '\[[^]]*\][[:space:]]*$' "${LISTS}"/*.txt | sed 's/[[:space:]]*$//' | sort -u | grep -cvE '^\[(amd64|arm64)\]$')" "0"
# L'edition amd64 doit recevoir EXACTEMENT ce qu'elle recevait avant les
# marqueurs: toutes les lignes, sauf celles reservees a arm64.
ANCIEN="$(awk 'NF && $1 !~ /^#/ && $NF != "[arm64]" {print $1}' "${LISTS}"/*.txt)"
check "amd64: contenu inchange" "$([[ "${AMD}" == "${ANCIEN}" ]] && echo identique)" "identique"
printf 'a\n# c\nb [arm64]\nc [amd64]\n\nd\n' > "${WORK}/l.txt"
check "filtre: arm64" "$("${NAMES}" arm64 "${WORK}/l.txt" | paste -sd,)" "a,b,d"
check "filtre: amd64" "$("${NAMES}" amd64 "${WORK}/l.txt" | paste -sd,)" "a,c,d"

echo "== 2. build-image.sh: architecture =="
out="$(AUXINUX_ARCH=arm64 bash "${ROOT}/image-builder/build-image.sh" --help 2>&1)"
check "arm64: repertoire de travail propre" "$(grep -c '/mnt/build/Auxinuxos-arm64' <<<"${out}")" "1"
out="$(AUXINUX_ARCH=amd64 bash "${ROOT}/image-builder/build-image.sh" --help 2>&1)"
check "amd64: repertoire historique garde" "$(grep -c '/mnt/build/Auxinuxos-normal' <<<"${out}")" "1"
AUXINUX_ARCH=i386 bash "${ROOT}/image-builder/build-image.sh" --help >/dev/null 2>&1
check "architecture inconnue refusee" "$?" "64"

echo "== 3. make-iso.sh a sec =="
STUBS="${WORK}/bin"; mkdir -p "${STUBS}"
LOG="${WORK}/calls"
for t in xorriso grub-mkimage mformat mmd; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "${t}" "${LOG}" > "${STUBS}/${t}"
done
# mcopy consigne la destination; mdir la relit (comme une vraie FAT).
printf '#!/bin/sh\necho "mcopy $*" >> "%s"\n' "${LOG}" > "${STUBS}/mcopy"
printf '#!/bin/sh\ngrep -o "::/EFI/BOOT/[^ ]*" "%s" 2>/dev/null | sed "s|::/EFI/BOOT/||"\nexit 0\n' "${LOG}" > "${STUBS}/mdir"
chmod 755 "${STUBS}"/*

fake_rootfs() { # rootfs sfx plateforme
  mkdir -p "$1/usr/lib/shim" "$1/usr/lib/grub/$3-signed"
  printf 'SHIM' > "$1/usr/lib/shim/shim$2.efi.signed"
  printf 'MOK'  > "$1/usr/lib/shim/mm$2.efi.signed"
  printf 'GRUB' > "$1/usr/lib/grub/$3-signed/gcd$2.efi.signed"
}
make_iso() { # arch rootfs iso_root
  : > "${LOG}"
  mkdir -p "$3" "${WORK}/out"
  PATH="${STUBS}:${PATH}" AUXINUX_ARCH="$1" bash "${MAKE_ISO}" "$3" "$2" "${WORK}/out/test.iso" >"${WORK}/mkiso.out" 2>&1
}

fake_rootfs "${WORK}/rootfs-arm" aa64 arm64-efi
make_iso arm64 "${WORK}/rootfs-arm" "${WORK}/iso-arm"; rc=$?
check "arm64: reussit" "${rc}" "0"
check "arm64: BOOTAA64.EFI = shim (ISO9660)" "$(cat "${WORK}/iso-arm/EFI/BOOT/BOOTAA64.EFI" 2>/dev/null)" "SHIM"
check "arm64: grubaa64.efi = GRUB signe" "$(cat "${WORK}/iso-arm/EFI/BOOT/grubaa64.efi" 2>/dev/null)" "GRUB"
check "arm64: mmaa64.efi = MokManager" "$(cat "${WORK}/iso-arm/EFI/BOOT/mmaa64.efi" 2>/dev/null)" "MOK"
check "arm64: BOOTAA64.EFI dans la partition EFI" "$(grep -c 'mcopy .*::/EFI/BOOT/BOOTAA64.EFI' "${LOG}")" "1"
check "arm64: aucun nom x64" "$(grep -ci 'x64' "${LOG}")" "0"
check "arm64: aucun repertoire i386-pc" "$([[ -e "${WORK}/iso-arm/boot/grub/i386-pc" ]] && echo present || echo absent)" "absent"
check "arm64: pas de grub-mkimage BIOS" "$(grep -c '^grub-mkimage' "${LOG}")" "0"
XO="$(grep '^xorriso -as mkisofs' "${LOG}")"
check "arm64: une seule image assemblee" "$(grep -c . <<<"${XO}")" "1"
check "arm64: pas d'El Torito BIOS" "$(grep -c -- '-eltorito-boot' <<<"${XO}")" "0"
check "arm64: pas de boot_hybrid.img" "$(grep -c 'boot_hybrid' <<<"${XO}")" "0"
check "arm64: pas de --grub2-mbr" "$(grep -c -- '--grub2-mbr' <<<"${XO}")" "0"
check "arm64: El Torito EFI sur la partition ajoutee" "$(grep -c -- '-e --interval:appended_partition_2:all::' <<<"${XO}")" "1"
check "arm64: partition EFI ajoutee" "$(grep -c -- '-append_partition 2 0xef' <<<"${XO}")" "1"

rm -f "${WORK}/rootfs-arm/usr/lib/grub/arm64-efi-signed/gcdaa64.efi.signed"
make_iso arm64 "${WORK}/rootfs-arm" "${WORK}/iso-arm2"; rc=$?
check "arm64 sans GRUB signe: refuse" "${rc}" "70"
check "arm64: le bon paquet est nomme" "$(grep -c 'grub-efi-arm64-signed' "${WORK}/mkiso.out")" "1"

fake_rootfs "${WORK}/rootfs-amd" x64 x86_64-efi
make_iso amd64 "${WORK}/rootfs-amd" "${WORK}/iso-amd"; rc=$?
check "amd64: reussit" "${rc}" "0"
check "amd64: BOOTX64.EFI = shim" "$(cat "${WORK}/iso-amd/EFI/BOOT/BOOTX64.EFI" 2>/dev/null)" "SHIM"
check "amd64: grubx64.efi" "$(cat "${WORK}/iso-amd/EFI/BOOT/grubx64.efi" 2>/dev/null)" "GRUB"
check "amd64: amorce BIOS construite" "$(grep -c '^grub-mkimage -O i386-pc-eltorito' "${LOG}")" "1"
XO="$(grep '^xorriso -as mkisofs' "${LOG}")"
check "amd64: El Torito BIOS" "$(grep -c -- '-eltorito-boot boot/grub/i386-pc/eltorito.img' <<<"${XO}")" "1"
check "amd64: MBR hybride" "$(grep -c -- '--grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img' <<<"${XO}")" "1"
check "amd64: El Torito EFI en second" "$(grep -c -- '-eltorito-alt-boot' <<<"${XO}")" "1"
rm -f "${WORK}/rootfs-amd/usr/lib/shim/shimx64.efi.signed"
make_iso amd64 "${WORK}/rootfs-amd" "${WORK}/iso-amd2"; rc=$?
check "amd64 sans shim: refuse" "${rc}" "70"
check "amd64: le bon paquet est nomme" "$(grep -c 'grub-efi-amd64-signed' "${WORK}/mkiso.out")" "1"

echo "== 4. build-debs.sh: paquet du centre par architecture =="
if command -v dpkg-deb >/dev/null; then
  VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "${ROOT}/packages/auxinux-center/Cargo.toml" | head -n1)"
  printf '#!/bin/sh\necho "auxinux-center %s"\n' "${VERSION}" > "${WORK}/center"; chmod +x "${WORK}/center"
  for arch in arm64 amd64; do
    AUXINUX_ARCH="${arch}" AUXINUX_STRIP=0 AUXINUX_CENTER_BIN="${WORK}/center" \
      AUXINUX_RELEASE="0.4.0+20261025" "${ROOT}/packages/build-debs.sh" --out "${WORK}/debs-${arch}" \
      >/dev/null 2>"${WORK}/debs.err"
    check "${arch}: construit" "$?" "0"
    CDEB="${WORK}/debs-${arch}/auxinux-center_${VERSION}_${arch}.deb"
    check "${arch}: nom du paquet" "$([[ -f "${CDEB}" ]] && echo oui)" "oui"
    [[ -f "${CDEB}" ]] || continue
    check "${arch}: champ Architecture" "$(dpkg-deb -f "${CDEB}" Architecture)" "${arch}"
    wiz="$(dpkg-deb -c "${CDEB}" | grep -c 'auxinux-windows-wizard')"
    if [[ "${arch}" == arm64 ]]; then
      check "arm64: pas d'assistant des .exe" "${wiz}" "0"
    else
      check "amd64: assistant des .exe et son lanceur" "${wiz}" "2"
    fi
  done
else
  echo "  (saute: dpkg-deb absent)"
fi

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; fi
exit "${fail}"
