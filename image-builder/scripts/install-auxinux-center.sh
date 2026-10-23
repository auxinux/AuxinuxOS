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

# EN PAQUETS DEB depuis le 2026-10-07 (packages/build-debs.sh): auxinux-center
# (binaire, .desktop, metainfo, autostart de l'assistant, helpers, action
# polkit) et auxi (la commande, le bouclier apt, le hook d'instantane). Copies
# a la main, ces fichiers etaient inconnus de dpkg: aucune installation ne
# pouvait recevoir un correctif sans nouvelle ISO. Installes ici par paquet,
# ils suivent la mise a jour du systeme (suite APPS du depot AuxiNuxOS).
#
# apt-get install d'un fichier local, et non dpkg -i: les dependances
# manquantes eventuelles sont resolues au lieu de laisser dpkg a moitie
# configure. A ce stade, les diversions d'apt (install-auxi-cli.sh) ne sont
# pas encore posees: c'est le vrai apt-get.
echo "==> Construction des paquets auxi et auxinux-center"
# Gardes a cote de l'ISO: ce sont CES paquets qu'il faut publier avec elle
# (packages/publish-debs.sh --dir .../image-builder/output/debs), en
# particulier auxinuxos-release de la meme edition.
DEBS_DIR="${AUXINUX_DEBS_DIR:-${PROJECT_DIR}/image-builder/output/debs}"
mkdir -p "${DEBS_DIR}"
rm -f "${DEBS_DIR}"/*.deb
AUXINUX_CENTER_BIN="${BIN}" "${PROJECT_DIR}/packages/build-debs.sh" --out "${DEBS_DIR}" >/dev/null
AUXI_DEB="$(ls "${DEBS_DIR}"/auxi_*_all.deb)"
CENTER_DEB="$(ls "${DEBS_DIR}"/auxinux-center_*_amd64.deb)"
# Version d'AuxiNux OS et reglages du systeme installe (packages/release).
RELEASE_DEB="$(ls "${DEBS_DIR}"/auxinuxos-release_*_all.deb)"

echo "==> Installation d'AuxiNux OS Center et d'auxi dans le rootfs"
sudo install -d -m 0755 "${ROOTFS}/tmp/auxinux-debs"
sudo cp "${AUXI_DEB}" "${CENTER_DEB}" "${RELEASE_DEB}" "${ROOTFS}/tmp/auxinux-debs/"
# --force-confnew: sur un rootfs reutilise, /etc/xdg/autostart/auxinux-assistant.desktop
# existe deja, copie a la main par une construction precedente et inconnu de
# dpkg. Le conffile du paquet en differe: dpkg POSE UNE QUESTION, lit une fin
# de fichier et echoue (constate en VM le 2026-10-07 sur un systeme installe).
# PAS --force-confdef avec: il l'emporte, et dpkg garde alors l'ancien fichier
# (« Keeping old config file as default », construction du 2026-10-08).
#
# dpkg -i et non apt-get install: sur un rootfs reutilise, la mise a jour des
# paquets a pu installer la MEME version depuis la suite APPS (publiee avant la
# construction), avec un contenu different (binaire recompile). apt refuse
# alors le fichier local (« DOWNGRADED ... without --allow-downgrades »,
# construction du 2026-10-08); dpkg reinstalle sans discuter. apt-get -f
# complete ensuite une dependance manquante, s'il y en a une.
if ! sudo chroot "${ROOTFS}" env DEBIAN_FRONTEND=noninteractive dpkg -i --force-confnew \
  "/tmp/auxinux-debs/$(basename "${AUXI_DEB}")" \
  "/tmp/auxinux-debs/$(basename "${CENTER_DEB}")" \
  "/tmp/auxinux-debs/$(basename "${RELEASE_DEB}")"; then
  sudo chroot "${ROOTFS}" env DEBIAN_FRONTEND=noninteractive apt-get install -f -y \
    --no-install-recommends -o Dpkg::Options::=--force-confnew
fi
sudo rm -rf "${ROOTFS}/tmp/auxinux-debs"
# Sur un rootfs reutilise, le preinst d'auxinuxos-release range ici les copies
# laissees par une construction precedente: rien a garder dans l'ISO.
sudo rm -rf "${ROOTFS}/var/backups/auxinuxos-release"

# Installateur console « Install NOW » (entree GRUB par defaut du live):
# programme, moteur et unite qui le lance sur la premiere console. Tous trois
# sont retires du systeme installe par post-install-cleanup.sh.
# TOUJOURS recompiler (cargo ne refait que ce qui a change): un binaire
# simplement PRESENT pouvait dater d'une construction precedente -- la
# premiere ISO 0.3.0 (2026-10-22) embarquait l'installateur du 10 octobre,
# bandeau « AuxiNux OS 0.2.1 » compris. AUXINUX_INSTALLER_BIN reste respecte.
INSTALLER_BIN="${AUXINUX_INSTALLER_BIN:-${PKG_DIR}/target/release/auxinux-installer}"
if [[ -z "${AUXINUX_INSTALLER_BIN:-}" ]]; then
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

# L'assistant de premier demarrage (/etc/xdg/autostart/auxinux-assistant.desktop)
# vient du paquet auxinux-center: ouvert a chaque ouverture de session tant
# qu'il n'a pas ete termine ou passe (le centre en decide lui-meme).

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
# Downloads, Documents... et ~/.config/user-dirs.dirs pour tout nouveau compte
# (useradd -m copie /etc/skel). Sans eux, Firefox (Flatpak) telechargeait dans
# son bac a sable, introuvable (rapporte le 2026-10-08). Les comptes existants
# sont repares a l'ouverture de session (/etc/xdg/autostart/auxinux-user-dirs.desktop).
sudo chroot "${ROOTFS}" /usr/lib/auxinux/auxinux-user-dirs /etc/skel
sudo rm -f "${ROOTFS}/etc/skel/Desktop/AuxiNux OS Center.desktop"
sudo install -m 0755 "${PKG_DIR}/data/ca.auxinux.Center.desktop" \
  "${ROOTFS}/etc/skel/Desktop/AuxiNux OS Center.desktop"

# Le Center est un binaire libcosmic: aucune dependance QML/Kirigami/KF6 a
# installer. Ses dependances d'execution (libwayland-client, libxkbcommon,
# pilotes mesa GL/Vulkan) sont toutes tirees par le bureau Plasma et par
# bureau-auxinux.txt, qui declare explicitement libgl1-mesa-dri et
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
