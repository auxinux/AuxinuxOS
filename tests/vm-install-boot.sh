#!/usr/bin/env bash
# Banc d'essai « installation puis demarrage », a lancer sur l'hote de build.
#
# POURQUOI CE SCRIPT EXISTE: jusqu'ici, la seule facon de savoir si le systeme
# INSTALLE demarrait etait de graver une ISO et d'essayer sur une vraie
# machine. Les deux pannes du 2026-09-09 (« ecran noir apres le choix de la
# langue », « le systeme installe ne finit jamais de demarrer ») n'ont pu etre
# comprises qu'en reconstituant une installation complete et en la demarrant.
# Ce script fige cette reconstitution pour qu'elle soit rejouable.
#
# Il reproduit, hors Calamares, ce que fait la sequence exec sur la cible:
#   unpackfs -> fstab -> users -> enableapt -> initramfs -> shellprocess@cleanup
# puis fabrique un disque GPT (ESP + BTRFS avec les sous-volumes @, @home,
# @snapshots, @var_*) SANS avoir besoin de peripherique loop -- l'hote de build
# est un conteneur LXC qui n'en a pas. mkfs.btrfs --rootdir/--subvol et mtools
# font tout le travail.
#
# Etapes (argument 1): copy | conf | cleanup | image | all
#
# Ensuite, pour demarrer le disque obtenu:
#   qemu-system-x86_64 -machine q35 -m 4096 -smp 4 \
#     -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
#     -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd \
#     -drive file=disk.raw,format=raw,if=virtio -device virtio-vga \
#     -serial file:serial.log -display none
#
# CE QUE CE BANC NE COUVRE PAS: les modules Calamares eux-memes (partition,
# unpackfs, bootloader, packages...). Il part du rootfs de construction, pas
# du squashfs, et pose GRUB a la main. Il valide donc le CONTENU du systeme
# installe et son demarrage, pas l'installateur.
set -euo pipefail

ROOTFS="${ROOTFS:-/mnt/build/Auxinuxos-normal/0.3.0-live/rootfs}"
WORK="${WORK:-/mnt/build/vmtest}"
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET="${WORK}/target"
DISK="${WORK}/disk.raw"
ESP_IMG="${WORK}/esp.img"
ROOT_IMG="${WORK}/root.img"
FS_UUID="${FS_UUID:-8f3c1d2e-4a5b-4c6d-8e9f-0a1b2c3d4e5f}"
DISK_MB=24000
ESP_MB=512
STAGE="${1:-all}"

msg() { echo "== $*"; }

MOUNTED=()
umount_all() {
  local i
  for ((i=${#MOUNTED[@]}-1; i>=0; i--)); do
    sudo umount -R "${MOUNTED[i]}" 2>/dev/null || sudo umount -Rl "${MOUNTED[i]}" 2>/dev/null || true
  done
  MOUNTED=()
}
trap umount_all EXIT

mount_api() {
  local r="$1"
  sudo mount -t proc proc "$r/proc";            MOUNTED+=("$r/proc")
  sudo mount -t sysfs sys "$r/sys";             MOUNTED+=("$r/sys")
  sudo mount --rbind /dev "$r/dev"
  sudo mount --make-rslave "$r/dev" || true;    MOUNTED+=("$r/dev")
  sudo mount -t tmpfs tmpfs "$r/run";           MOUNTED+=("$r/run")
}

# ---------------------------------------------------------------- unpackfs
if [[ "${STAGE}" == "all" || "${STAGE}" == "copy" ]]; then
  msg "unpackfs: copie du rootfs vers ${TARGET}/@"
  sudo rm -rf "${TARGET}"
  sudo mkdir -p "${TARGET}/@"
  sudo rsync -aHAX --numeric-ids \
    --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' \
    --exclude='/run/*' --exclude='/tmp/*' --exclude='/var/cache/apt/archives/*.deb' \
    "${ROOTFS}/" "${TARGET}/@/"

  msg "partition: sous-volumes plats"
  for sv in @home @snapshots @var_log @var_cache @var_tmp @var_lib_flatpak; do
    sudo mkdir -p "${TARGET}/${sv}"
  done
  # Le contenu des points de montage part dans son sous-volume, comme le fait
  # Calamares en montant les subvolumes avant unpackfs.
  move_into() { # src-rel  subvol
    local src="${TARGET}/@/$1" dst="${TARGET}/$2"
    if [[ -d "${src}" ]]; then
      sudo rsync -aHAX --numeric-ids "${src}/" "${dst}/"
      sudo rm -rf "${src:?}"/* "${src:?}"/.[!.]* 2>/dev/null || true
    fi
    sudo mkdir -p "${src}"
  }
  move_into home            @home
  move_into var/log         @var_log
  move_into var/cache       @var_cache
  move_into var/tmp         @var_tmp
  move_into var/lib/flatpak @var_lib_flatpak
  sudo mkdir -p "${TARGET}/@/.snapshots"
fi

T="${TARGET}/@"

# ---------------------------------------------------------------- fstab
if [[ "${STAGE}" == "all" || "${STAGE}" == "conf" ]]; then
  msg "fstab / machineid / hostname / users"
  sudo tee "${T}/etc/fstab" >/dev/null <<EOF
# /etc/fstab genere par le banc de test (equivalent module Calamares fstab)
UUID=${FS_UUID} /                btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@              0 0
UUID=${FS_UUID} /home            btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@home          0 0
UUID=${FS_UUID} /.snapshots      btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@snapshots     0 0
UUID=${FS_UUID} /var/log         btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@var_log       0 0
UUID=${FS_UUID} /var/cache       btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@var_cache     0 0
UUID=${FS_UUID} /var/tmp         btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@var_tmp       0 0
UUID=${FS_UUID} /var/lib/flatpak btrfs   defaults,noatime,compress=zstd:1,space_cache=v2,subvol=@var_lib_flatpak 0 0
UUID=1234-ABCD  /boot/efi        vfat    umask=0077                                                           0 2
EOF
  sudo rm -f "${T}/etc/machine-id"; sudo touch "${T}/etc/machine-id"
  echo "auxi-test" | sudo tee "${T}/etc/hostname" >/dev/null
  printf '127.0.0.1 localhost\n127.0.1.1 auxi-test\n' | sudo tee "${T}/etc/hosts" >/dev/null
  sudo mkdir -p "${T}/boot/efi"

  mount_api "${T}"
  # users: compte cree par Calamares, PAS d'autologin (cas par defaut).
  sudo chroot "${T}" bash -c '
    id -u testeur >/dev/null 2>&1 || useradd -m -s /bin/bash -G users,sudo,audio,video,plugdev,netdev testeur
    echo "testeur:testeur" | chpasswd'
  # enableapt
  sudo mkdir -p "${T}/etc/auxinux"
  echo 'APT_ENABLED=1' | sudo tee "${T}/etc/auxinux/apt.conf" >/dev/null
  umount_all
fi

# ---------------------------------------------------------------- cleanup
if [[ "${STAGE}" == "all" || "${STAGE}" == "cleanup" ]]; then
  msg "shellprocess@cleanup: post-install-cleanup.sh"
  # Toujours prendre la version du depot, pas celle figee dans le rootfs.
  sudo install -D -m0755 "${REPO}/installer/post-install-cleanup.sh" \
    "${T}/usr/lib/auxinux/post-install-cleanup.sh"
  sudo install -D -m0755 "${REPO}/installer/setup-btrfs-rollback.sh" \
    "${T}/usr/lib/auxinux/setup-btrfs-rollback.sh"
  mount_api "${T}"
  sudo chroot "${T}" /usr/lib/auxinux/post-install-cleanup.sh / 2>&1 | tail -40 || \
    echo "!! post-install-cleanup a echoue (code $?)"
  msg "verification post-cleanup"
  sudo chroot "${T}" bash -c '
    echo "-- live-boot restant:"; dpkg -l 2>/dev/null | grep -E "^ii +live-(boot|config)" || echo "   aucun (ok)"
    echo "-- calamares restant:"; dpkg -l 2>/dev/null | grep -E "^ii +calamares" || echo "   aucun (ok)"
    echo "-- compte auxinux:"; id auxinux 2>&1 || echo "   supprime (ok)"
    echo "-- autologin live restant:"; ls -l /etc/sddm.conf.d/ 2>/dev/null || echo "   aucun (ok)"
    echo "-- reliquat greetd:"; ls -d /etc/greetd 2>/dev/null || echo "   supprime (ok)"
    echo "-- display-manager:"; ls -l /etc/systemd/system/display-manager.service
    echo "-- session Plasma:"; ls -l /usr/share/wayland-sessions/plasma.desktop
    echo "-- protection au demarrage:"; ls -l /etc/systemd/system/graphical.target.wants/ 2>/dev/null | grep auxinux || echo "   ABSENTE"
    echo "-- compteur de demarrages:"; ls -l /var/lib/auxinux/boot-failures 2>/dev/null || echo "   absent (ok)"
    echo "-- initrd:"; ls -l /boot/initrd.img-*
    echo "-- live-boot dans initrd:"; lsinitramfs /boot/initrd.img-* 2>/dev/null | grep -c live || echo 0'
  umount_all
fi

# ---------------------------------------------------------------- images
if [[ "${STAGE}" == "all" || "${STAGE}" == "image" ]]; then
  msg "construction de l'image btrfs (${DISK_MB}Mo)"
  sudo rm -f "${ROOT_IMG}" "${ESP_IMG}" "${DISK}"
  ROOT_MB=$((DISK_MB - ESP_MB - 2))
  truncate -s "${ROOT_MB}M" "${ROOT_IMG}"
  # mkfs.btrfs 6.14 (--subvol) vient du rootfs de build, execute en chroot pour
  # ses bibliotheques; le plan de travail y est bind-monte sous /mnt/vmtest.
  sudo install -d -m0755 "${ROOTFS}/mnt/vmtest"
  sudo mount --bind "${WORK}" "${ROOTFS}/mnt/vmtest"; MOUNTED+=("${ROOTFS}/mnt/vmtest")
  # mkfs.btrfs lit /proc/self/mountinfo pour refuser d'ecraser un FS monte:
  # sans /proc dans le chroot il abandonne sur "cannot check mount status".
  sudo mountpoint -q "${ROOTFS}/proc" || { sudo mount -t proc proc "${ROOTFS}/proc"; MOUNTED+=("${ROOTFS}/proc"); }
  sudo chroot "${ROOTFS}" mkfs.btrfs -q -U "${FS_UUID}" -L auxinuxos \
    -r /mnt/vmtest/target \
    -u rw:@ -u rw:@home -u rw:@snapshots -u rw:@var_log \
    -u rw:@var_cache -u rw:@var_tmp -u rw:@var_lib_flatpak \
    /mnt/vmtest/root.img
  umount_all

  msg "construction de l'ESP"
  truncate -s "${ESP_MB}M" "${ESP_IMG}"
  mformat -i "${ESP_IMG}" -F -N 1234ABCD ::
  mmd -i "${ESP_IMG}" ::/EFI ::/EFI/BOOT ::/EFI/debian
  KVER="$(basename "$(ls "${T}"/boot/vmlinuz-* | head -1)" | sed 's/^vmlinuz-//')"
  cat > "${WORK}/grub-embed.cfg" <<EOF
set timeout=2
set default=0
search --no-floppy --fs-uuid --set=root ${FS_UUID}
menuentry "AuxiNux OS (test)" {
  linux /@/boot/vmlinuz-${KVER} root=UUID=${FS_UUID} rootflags=subvol=@ rw pci=noaer pcie_aspm=off console=ttyS0,115200 console=tty0 systemd.log_level=info
  initrd /@/boot/initrd.img-${KVER}
}
EOF
  sudo cp "${WORK}/grub-embed.cfg" "${T}/tmp/grub-embed.cfg"
  sudo chroot "${T}" grub-mkstandalone -O x86_64-efi \
    -o /tmp/bootx64.efi "boot/grub/grub.cfg=/tmp/grub-embed.cfg"
  sudo cp "${T}/tmp/bootx64.efi" "${WORK}/bootx64.efi"
  sudo chown "$(id -u):$(id -g)" "${WORK}/bootx64.efi"
  mcopy -i "${ESP_IMG}" "${WORK}/bootx64.efi" ::/EFI/BOOT/BOOTX64.EFI

  msg "assemblage du disque GPT"
  truncate -s "${DISK_MB}M" "${DISK}"
  sudo mount --bind "${WORK}" "${ROOTFS}/mnt/vmtest"; MOUNTED+=("${ROOTFS}/mnt/vmtest")
  sudo mountpoint -q "${ROOTFS}/proc" || { sudo mount -t proc proc "${ROOTFS}/proc"; MOUNTED+=("${ROOTFS}/proc"); }
  sudo chroot "${ROOTFS}" sgdisk \
    -n 1:2048:+${ESP_MB}M -t 1:ef00 -c 1:EFI \
    -n 2:0:0 -t 2:8300 -c 2:root /mnt/vmtest/disk.raw >/dev/null
  dd if="${ESP_IMG}"  of="${DISK}" bs=512 seek=2048 conv=notrunc status=none
  ROOT_START=$(sudo chroot "${ROOTFS}" sgdisk -i 2 /mnt/vmtest/disk.raw | awk '/First sector/{print $3}')
  echo "   partition root au secteur ${ROOT_START}"
  dd if="${ROOT_IMG}" of="${DISK}" bs=512 seek="${ROOT_START}" conv=notrunc status=none
  msg "disque pret: ${DISK}"
fi
