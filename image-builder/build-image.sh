#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_WORK_DIR="/mnt/build/Auxinuxos-normal"
OUTPUT_DIR="${PROJECT_DIR}/image-builder/output"
WORK_DIR="${AUXINUX_NORMAL_BUILD_DIR:-${DEFAULT_WORK_DIR}}"
PROFILE="en-0.1-beta-live"
FORCE=0
REUSE_ROOTFS=0

usage() {
  cat <<EOF
usage: $0 [--work-dir PATH] [--force] [--reuse-rootfs]

Builds AuxiNux OS Edition-Normal 0.1-BETA live ISO.

Defaults:
  work dir : ${DEFAULT_WORK_DIR}
  output   : ${OUTPUT_DIR}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)
      WORK_DIR="${2:?missing work dir}"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --reuse-rootfs)
      REUSE_ROOTFS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

for tool in mmdebstrap mksquashfs grub-mkrescue xorriso rsync curl mformat; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "missing required tool: ${tool}" >&2
    exit 69
  fi
done

CHROOT_MOUNTS=()

mount_chroot_api_filesystems() {
  sudo install -d -m 0755 "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/dev"

  if ! sudo mountpoint -q "${ROOTFS_DIR}/proc"; then
    sudo mount -t proc proc "${ROOTFS_DIR}/proc"
    CHROOT_MOUNTS+=("${ROOTFS_DIR}/proc")
  fi

  if ! sudo mountpoint -q "${ROOTFS_DIR}/dev"; then
    sudo mount --rbind /dev "${ROOTFS_DIR}/dev"
    sudo mount --make-rslave "${ROOTFS_DIR}/dev" >/dev/null 2>&1 || true
    CHROOT_MOUNTS+=("${ROOTFS_DIR}/dev")
  fi
}

cleanup_chroot_api_filesystems() {
  local index
  for ((index = ${#CHROOT_MOUNTS[@]} - 1; index >= 0; index--)); do
    sudo umount -R "${CHROOT_MOUNTS[index]}" >/dev/null 2>&1 || true
  done
}

trap cleanup_chroot_api_filesystems EXIT

BUILD_DIR="${WORK_DIR}/${PROFILE}"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ISO_ROOT="${BUILD_DIR}/iso-root"
OUTPUT_ISO="${OUTPUT_DIR}/auxinuxos-en-0.1-beta-amd64.iso"

if [[ "${FORCE}" -eq 1 && "${REUSE_ROOTFS}" -eq 1 ]]; then
  echo "--force and --reuse-rootfs cannot be used together" >&2
  exit 64
fi

if [[ "${FORCE}" -eq 1 ]]; then
  sudo rm -rf "${BUILD_DIR}"
fi

if [[ -e "${BUILD_DIR}" && "${REUSE_ROOTFS}" -ne 1 ]]; then
  echo "build directory already exists: ${BUILD_DIR}" >&2
  echo "use --force to rebuild or --reuse-rootfs to resume" >&2
  exit 73
fi

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

package_csv() {
  awk 'NF && $1 !~ /^#/' "$@" | paste -sd,
}

BASE_PACKAGES="$(package_csv "${PROJECT_DIR}/image-builder/package-lists/base.txt" "${PROJECT_DIR}/image-builder/package-lists/firmware.txt" "${PROJECT_DIR}/image-builder/package-lists/desktop-base.txt" "${PROJECT_DIR}/image-builder/package-lists/i18n-canada.txt" "${PROJECT_DIR}/image-builder/package-lists/live-installer.txt" "${PROJECT_DIR}/image-builder/package-lists/windows-support.txt")"

if [[ "${REUSE_ROOTFS}" -eq 1 ]]; then
  if [[ ! -e "${ROOTFS_DIR}/etc/os-release" ]]; then
    echo "cannot reuse missing rootfs: ${ROOTFS_DIR}" >&2
    exit 73
  fi
  echo "==> Reusing rootfs: ${ROOTFS_DIR}"
else
  echo "==> Creating Debian 13.5 rootfs"
  sudo mmdebstrap \
    --architectures=amd64 \
    --variant=apt \
    --components=main,contrib,non-free,non-free-firmware \
    --include="${BASE_PACKAGES}" \
    trixie \
    "${ROOTFS_DIR}" \
    http://deb.debian.org/debian
fi

if [[ -x "${ROOTFS_DIR}/usr/bin/auxi" ]]; then
  echo "==> Temporarily enabling direct APT for build reuse"
  sudo chroot "${ROOTFS_DIR}" /usr/bin/auxi set apt=true
fi

echo "==> Configuring APT sources"
mount_chroot_api_filesystems
"${PROJECT_DIR}/image-builder/scripts/configure-apt-sources.sh" "${ROOTFS_DIR}"

echo "==> Installing AuxiNux kernel and applications"
# package_csv strips comment and blank lines; a plain `tr '\n' ' '` would feed
# `#` comment words to apt-get (desktop-base.txt now carries a comment block).
INSTALL_PACKAGES="$(package_csv \
  "${PROJECT_DIR}/image-builder/package-lists/base.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/firmware.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/desktop-base.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/i18n-canada.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/live-installer.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/windows-support.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/auxinux-system.txt" \
  "${PROJECT_DIR}/image-builder/package-lists/apps-privacy.txt" \
  | tr ',' ' ')"
sudo chroot "${ROOTFS_DIR}" apt-get install -y --no-install-recommends ${INSTALL_PACKAGES}

# Reuse builds must also keep the installer formatting stack available for EFI
# partition creation, even when the rootfs predates new package-list entries.
sudo chroot "${ROOTFS_DIR}" apt-get install -y --no-install-recommends dosfstools

echo "==> Installing COSMIC runtime dependencies (OBS home:nomispaz Debian_13)"
# COSMIC has no Debian package; the only APT source for trixie is the
# community OBS repo. Its key is VENDORED here (never fetched blindly), the
# repo is enabled only inside this build chroot, and the runtime auxi/apt
# policy still applies to the installed system.
COSMIC_KEY="${PROJECT_DIR}/image-builder/keys/obs-cosmic-debian13.asc"
if [[ ! -s "${COSMIC_KEY}" ]]; then
  echo "missing vendored OBS COSMIC key: ${COSMIC_KEY}" >&2
  exit 70
fi
sudo install -D -m 0644 "${COSMIC_KEY}" \
  "${ROOTFS_DIR}/usr/share/keyrings/obs-cosmic-debian13.asc"
sudo tee "${ROOTFS_DIR}/etc/apt/sources.list.d/obs-cosmic.sources" >/dev/null <<'EOF'
Types: deb
URIs: https://download.opensuse.org/repositories/home:/nomispaz:/debian:/cosmic-desktop/Debian_13/
Suites: /
Signed-By: /usr/share/keyrings/obs-cosmic-debian13.asc
EOF
sudo chroot "${ROOTFS_DIR}" apt-get update
sudo chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
  cosmic-session cosmic-greeter cosmic-term cosmic-files cosmic-edit \
  cosmic-wallpapers xdg-desktop-portal-cosmic adw-gtk3

# The OBS repo must not remain enabled on the shipped system.
sudo rm -f "${ROOTFS_DIR}/etc/apt/sources.list.d/obs-cosmic.sources"

echo "==> Building coherent COSMIC Epoch stack from official sources"
"${PROJECT_DIR}/image-builder/scripts/build-cosmic-source.sh" \
  "${ROOTFS_DIR}" "${WORK_DIR}/cosmic-source-cache"

echo "==> Configuring Flatpak"
"${PROJECT_DIR}/image-builder/scripts/configure-flatpak.sh" "${ROOTFS_DIR}"

echo "==> Installing AuxiNux OS Center"
"${PROJECT_DIR}/image-builder/scripts/install-auxinux-center.sh" "${ROOTFS_DIR}"
cleanup_chroot_api_filesystems

echo "==> Applying overlays and AuxiNux tooling"
sudo rsync -a "${PROJECT_DIR}/image-builder/overlays/" "${ROOTFS_DIR}/"
"${PROJECT_DIR}/image-builder/scripts/install-auxi-cli.sh" "${ROOTFS_DIR}"
"${PROJECT_DIR}/image-builder/scripts/configure-branding.sh" "${ROOTFS_DIR}"
sudo chroot "${ROOTFS_DIR}" locale-gen
sudo chroot "${ROOTFS_DIR}" update-locale LANG=fr_CA.UTF-8 LANGUAGE=fr_CA:fr:en_CA:en

echo "auxinuxos-live" | sudo tee "${ROOTFS_DIR}/etc/hostname" >/dev/null
sudo tee "${ROOTFS_DIR}/etc/hosts" >/dev/null <<'EOF'
127.0.0.1 localhost
127.0.1.1 auxinuxos-live
EOF

if ! sudo chroot "${ROOTFS_DIR}" id -u auxinux >/dev/null 2>&1; then
  sudo chroot "${ROOTFS_DIR}" useradd -m -s /bin/bash auxinux
fi
printf 'auxinux:auxinux\n' | sudo chroot "${ROOTFS_DIR}" chpasswd
sudo install -d -m 0755 "${ROOTFS_DIR}/etc/sudoers.d" "${ROOTFS_DIR}/home/auxinux/Desktop"
echo 'auxinux ALL=(ALL) NOPASSWD:ALL' | sudo tee "${ROOTFS_DIR}/etc/sudoers.d/90-auxinux-live" >/dev/null
sudo chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/90-auxinux-live"
sudo install -m 0755 "${ROOTFS_DIR}/usr/share/applications/auxinux-install.desktop" "${ROOTFS_DIR}/home/auxinux/Desktop/Install AuxiNuxOS.desktop"
sudo chroot "${ROOTFS_DIR}" chown -R auxinux:auxinux /home/auxinux/Desktop
# COSMIC shows no desktop icons; also autostart the installer in the live
# session so it opens on login (it stays in the app library to relaunch).
sudo install -d -m 0755 "${ROOTFS_DIR}/etc/xdg/autostart"
sudo install -m 0644 "${ROOTFS_DIR}/usr/share/applications/auxinux-install.desktop" \
  "${ROOTFS_DIR}/etc/xdg/autostart/auxinux-install.desktop"

# Suppress noisy first-run wizards that autostart on the live COSMIC session
# (KGpg's key-setup assistant, the disk-utility notifier). They are launchable
# from the app library if the user wants them; they must not pop over the
# installer on boot.
# calamares-desktop-icon adds a second, X11-only "Install Debian" icon that
# is broken under COSMIC/Wayland; AuxiNuxOS ships its own working launcher
# (auxinux-install-launcher) and desktop icon, so suppress the duplicate.
for noisy in org.kde.kgpg org.gnome.SettingsDaemon.DiskUtilityNotify calamares-desktop-icon; do
  if [[ -e "${ROOTFS_DIR}/etc/xdg/autostart/${noisy}.desktop" ]]; then
    echo "Hidden=true" | sudo tee -a "${ROOTFS_DIR}/etc/xdg/autostart/${noisy}.desktop" >/dev/null
  fi
done

# Live autologin via greetd + cosmic-greeter. cosmic-greeter runs
# `greetd --config /etc/greetd/cosmic-greeter.toml`; we add greetd's
# [initial_session] so the live user is logged straight into cosmic-session
# on boot, with the regular greeter shown on subsequent logouts. cosmic-comp
# renders through llvmpipe when the VM has no GPU, so no X11 fallback is
# needed (unlike Plasma-Wayland). SDDM is not installed anymore.
sudo install -d -m 0755 "${ROOTFS_DIR}/etc/greetd"
sudo tee "${ROOTFS_DIR}/etc/greetd/cosmic-greeter.toml" >/dev/null <<'EOF'
[terminal]
vt = "1"

[general]
service = "cosmic-greeter"

[initial_session]
command = "/usr/bin/start-cosmic"
user = "auxinux"

[default_session]
command = "cosmic-comp systemd-cat -t cosmic-greeter cosmic-greeter"
user = "cosmic-greeter"
EOF
sudo chroot "${ROOTFS_DIR}" ln -sf \
  /usr/lib/systemd/system/cosmic-greeter.service \
  /etc/systemd/system/display-manager.service

# Tor and OnionShare are available for privacy workflows, but Tor must be
# user-started instead of running by default on every boot.
sudo rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/tor.service"

# Package operations should be user-visible through auxi, not automatic apt
# timers that may run in the background and hit the apt wrapper policy.
sudo rm -f "${ROOTFS_DIR}/etc/systemd/system/timers.target.wants/apt-daily.timer"
sudo rm -f "${ROOTFS_DIR}/etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer"

sudo install -d -m 0755 "${ROOTFS_DIR}/etc/auxinux"
printf 'APT_ENABLED=0\n' | sudo tee "${ROOTFS_DIR}/etc/auxinux/apt.conf" >/dev/null

echo "==> Cleaning rootfs"
sudo rm -rf "${ROOTFS_DIR}/var/cache/apt/archives"/*.deb
sudo rm -rf "${ROOTFS_DIR}/tmp/"* "${ROOTFS_DIR}/var/tmp/"*

# Defensive cleanup before squashing the rootfs. Some interrupted or nested
# chroot operations can leave proc/dev/sys mounted, which would otherwise make
# mksquashfs try to archive host pseudo-filesystems.
cleanup_chroot_api_filesystems
sudo umount -Rl "${ROOTFS_DIR}/sys" >/dev/null 2>&1 || true
sudo umount -Rl "${ROOTFS_DIR}/run" >/dev/null 2>&1 || true
sudo install -d -m 0755 \
  "${ROOTFS_DIR}/proc" \
  "${ROOTFS_DIR}/sys" \
  "${ROOTFS_DIR}/dev" \
  "${ROOTFS_DIR}/run"

echo "==> Preparing ISO tree"
rm -rf "${ISO_ROOT}"
mkdir -p "${ISO_ROOT}/live" "${ISO_ROOT}/boot/grub"
KERNEL_PATH="$(find "${ROOTFS_DIR}/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort | tail -n1)"
INITRD_PATH="$(find "${ROOTFS_DIR}/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort | tail -n1)"

if [[ -z "${KERNEL_PATH}" || -z "${INITRD_PATH}" ]]; then
  echo "kernel or initrd not found" >&2
  exit 70
fi

# The current `kernel-auxinuxos` meta-package installs this kernel flavor.
if [[ "${KERNEL_PATH}" != *-auxinuxos-* ]]; then
  echo "selected kernel is not an AuxiNuxOS kernel: ${KERNEL_PATH}" >&2
  exit 70
fi
echo "==> Selected AuxiNuxOS kernel: $(basename "${KERNEL_PATH}")"

cp "${KERNEL_PATH}" "${ISO_ROOT}/live/vmlinuz"
cp "${INITRD_PATH}" "${ISO_ROOT}/live/initrd.img"

# Le systeme INSTALLE est une copie du squashfs. Il DOIT donc contenir /boot
# (noyau + initrd) et /boot/grub, sinon Calamares ne peut pas installer GRUB et
# le systeme ne demarre pas. /tmp doit exister (vide) pour qu'apt fonctionne
# pendant l'installation (bootloader-config). On exclut uniquement les
# pseudo-systemes de fichiers (recrees au demarrage) et le CONTENU de /tmp.
sudo mkdir -p "${ROOTFS_DIR}/boot/grub"
sudo install -d -m 1777 "${ROOTFS_DIR}/tmp"
sudo mksquashfs "${ROOTFS_DIR}" "${ISO_ROOT}/live/filesystem.squashfs" \
  -noappend -comp xz \
  -wildcards \
  -e 'tmp/*' 'proc/*' 'sys/*' 'dev/*' 'run/*'

# pci=noaer pcie_aspm=off: evite la tempete d'erreurs PCIe AER de certaines
# cartes WiFi Atheros (ath10k) qui inonde la console et bloque le boot; le
# WiFi reste fonctionnel. Meme reglage que /etc/default/grub du systeme
# installe.
cat >"${ISO_ROOT}/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0

menuentry "AuxiNux OS EN 0.1-BETA Live" {
    linux /live/vmlinuz boot=live components username=auxinux hostname=auxinuxos-live pci=noaer pcie_aspm=off quiet splash
    initrd /live/initrd.img
}

menuentry "AuxiNux OS EN 0.1-BETA (graphiques de secours / nomodeset)" {
    linux /live/vmlinuz boot=live components username=auxinux hostname=auxinuxos-live pci=noaer pcie_aspm=off nomodeset
    initrd /live/initrd.img
}

menuentry "AuxiNux OS EN 0.1-BETA (copie en RAM / toram)" {
    linux /live/vmlinuz boot=live components username=auxinux hostname=auxinuxos-live pci=noaer pcie_aspm=off toram quiet splash
    initrd /live/initrd.img
}
EOF

cat >"${ISO_ROOT}/README.txt" <<'EOF'
AuxiNux OS EN 0.1-BETA

Live user: auxinux
Live password: auxinux
EOF

echo "==> Creating ISO"
# mbr_force_bootable marks the protective-MBR partition active (0x80).
# grub-mkrescue leaves it at 0x00, and several legacy BIOSes refuse to boot a
# USB stick without an active MBR partition -- the classic "boots in QEMU but
# not on the real machine" failure. Harmless for UEFI.
grub-mkrescue -o "${OUTPUT_ISO}" "${ISO_ROOT}" -- \
  -boot_image any mbr_force_bootable=on
ls -lh "${OUTPUT_ISO}"
