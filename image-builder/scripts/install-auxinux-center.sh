#!/usr/bin/env bash
# Compile (ou recupere) AuxiNux OS Center et l'installe dans le rootfs de l'ISO.
#
# Variables:
#   AUXINUX_CENTER_BIN  chemin d'un binaire deja compile (saute la compilation)
#
# Le binaire est natif de l'hote de build (Debian 13 amd64 == cible), donc on
# peut le compiler sur l'hote et le copier tel quel dans le rootfs.
set -euo pipefail

ROOTFS="${1:?usage: install-auxinux-center.sh ROOTFS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PKG_DIR="${PROJECT_DIR}/packages/auxinux-center"

BIN="${AUXINUX_CENTER_BIN:-${PKG_DIR}/target/release/auxinux-center}"

if [[ ! -x "${BIN}" ]]; then
  echo "==> Compilation d'AuxiNux OS Center"
  "${PKG_DIR}/build.sh"
fi

if [[ ! -x "${BIN}" ]]; then
  echo "binaire auxinux-center introuvable: ${BIN}" >&2
  echo "compilez-le sur l'hote (packages/auxinux-center/build.sh) ou definissez AUXINUX_CENTER_BIN" >&2
  exit 70
fi

echo "==> Installation d'AuxiNux OS Center dans le rootfs"
sudo install -D -m 0755 "${BIN}" "${ROOTFS}/usr/bin/auxinux-center"
sudo install -D -m 0644 "${PKG_DIR}/data/ca.auxinux.Center.desktop" \
  "${ROOTFS}/usr/share/applications/ca.auxinux.Center.desktop"
sudo install -D -m 0644 "${PKG_DIR}/data/ca.auxinux.Center.metainfo.xml" \
  "${ROOTFS}/usr/share/metainfo/ca.auxinux.Center.metainfo.xml"

# Installateur console « Install NOW » (entree GRUB par defaut du live):
# programme, moteur et unite qui le lance sur la premiere console. Tous trois
# sont retires du systeme installe par post-install-cleanup.sh.
INSTALLER_BIN="${AUXINUX_INSTALLER_BIN:-${PKG_DIR}/target/release/auxinux-installer}"
if [[ ! -x "${INSTALLER_BIN}" ]]; then
  echo "==> Compilation de l'installateur console"
  if [[ -x "${HOME}/.cargo/bin/cargo" ]]; then export PATH="${HOME}/.cargo/bin:${PATH}"; fi
  (cd "${PKG_DIR}" && cargo build --release --no-default-features --features tui --bin auxinux-installer)
fi
sudo install -D -m 0755 "${INSTALLER_BIN}" "${ROOTFS}/usr/bin/auxinux-installer"
sudo install -D -m 0755 "${PROJECT_DIR}/installer/auxinux-install-engine" \
  "${ROOTFS}/usr/lib/auxinux/auxinux-install-engine"
sudo install -D -m 0644 "${PROJECT_DIR}/installer/auxinux-installer.service" \
  "${ROOTFS}/etc/systemd/system/auxinux-installer.service"
sudo install -d -m 0755 "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/auxinux-installer.service \
  "${ROOTFS}/etc/systemd/system/multi-user.target.wants/auxinux-installer.service"

# Assistant de premier demarrage: ouvert a chaque ouverture de session tant
# qu'il n'a pas ete termine ou passe (le centre en decide lui-meme).
sudo install -D -m 0644 "${PKG_DIR}/data/auxinux-assistant.desktop" \
  "${ROOTFS}/etc/xdg/autostart/auxinux-assistant.desktop"

# Raccourci sur le bureau de chaque nouveau compte (useradd -m copie /etc/skel).
#
# Une COPIE executable, comme le raccourci d'installation du live: Plasma ne
# lance sans avertissement « programme non fiable » qu'un .desktop executable
# hors de /usr/share/applications. Un lien symbolique aurait suivi le .desktop
# installe, mais Plasma l'affiche en italique avec un embleme de lien --
# essaye en VM le 2026-10-02, et ecarte pour cette raison.
#
# ~/Desktop et non un nom traduit: xdg-user-dirs n'est pas installe, donc le
# bureau de Plasma est ~/Desktop quelle que soit la langue.
sudo install -d -m 0755 "${ROOTFS}/etc/skel/Desktop"
sudo rm -f "${ROOTFS}/etc/skel/Desktop/AuxiNux OS Center.desktop"
sudo install -m 0755 "${PKG_DIR}/data/ca.auxinux.Center.desktop" \
  "${ROOTFS}/etc/skel/Desktop/AuxiNux OS Center.desktop"

# Le Center est un binaire libcosmic: aucune dependance QML/Kirigami/KF6 a
# installer. Ses dependances d'execution (libwayland-client, libxkbcommon,
# pilotes mesa GL/Vulkan) sont toutes tirees par le bureau Plasma et par
# desktop-plasma.txt, qui declare explicitement libgl1-mesa-dri et
# mesa-vulkan-drivers -- de simples Recommends que --no-install-recommends
# aurait laisses de cote.
#
# LE NETTOYAGE QUI SE TROUVAIT ICI A ETE SUPPRIME, ET IL FAUT COMPRENDRE
# POURQUOI AVANT DE LE REMETTRE:
#
#   apt-get autoremove -y --purge qml6-module-org-kde-kirigami
#
# Il datait de l'interface Kirigami de la 0.1: ce module QML ne servait plus a
# rien apres le passage a libcosmic, et sur un rootfs reutilise il restait dans
# l'image. Depuis le retour a KDE Plasma (2026-09-12), ce paquet est une
# DEPENDANCE de plasma-desktop. Avec `-y`, la commande aurait donc purge
# qml6-module-org-kde-kirigami ET tout ce qui en depend -- c'est-a-dire le
# bureau. Sans question, et avec `2>/dev/null || true` pour ne rien dire.
#
# Le controle d'image (check-rootfs.sh) l'aurait attrape en constatant
# l'absence de plasmashell, mais apres une heure de construction.
#
# Le Center n'a aucun reliquat a nettoyer: c'est un binaire unique.
