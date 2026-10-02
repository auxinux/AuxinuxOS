#!/usr/bin/env bash
#
# Tests des deux scripts qui s'executent en fin d'installation Calamares.
#
# Ils n'etaient couverts par aucun test, alors qu'ils portent deux defauts qui
# ne se voient qu'apres coup, sur la machine de l'utilisateur:
#
#   - setup-btrfs-rollback.sh cherchait le modele snapper au seul emplacement
#     ou Debian 13 ne le livre PAS. Il sortait en code 0 avec un avertissement:
#     l'installation reussissait, et le rollback -- la fonction principale de
#     la distribution -- etait absent de chaque systeme installe.
#   - post-install-cleanup.sh laissait l'installateur et son autodemarrage
#     dans le systeme installe. Calamares se relancait a chaque session, apres
#     avoir deplace /etc/fstab.
#
# chroot, findmnt et snapper sont remplaces par des stubs.
#
# Usage: bash tests/test-post-install.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP="${ROOT}/installer/post-install-cleanup.sh"
ROLLBACK="${ROOT}/installer/setup-btrfs-rollback.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# `sync` neutralise: post-install-cleanup.sh l'appelle apres avoir reecrit le
# noyau sans compression -- ce qui est juste sur une vraie cible. Dans un
# conteneur LXC, sync() porte sur tous les systemes de fichiers visibles et
# reste bloque en etat D (observe le 2026-09-14, « Dirty: 0 kB » a l'appui).
# Un banc d'essai ne doit pas dependre de l'etat du systeme qui l'execute.
STUB_BIN="${WORK}/stub-bin"
mkdir -p "${STUB_BIN}"
printf '#!/bin/sh\nexit 0\n' > "${STUB_BIN}/sync"
chmod 755 "${STUB_BIN}/sync"
export PATH="${STUB_BIN}:${PATH}"
STUBS="${WORK}/bin"
mkdir -p "${STUBS}"

cat > "${STUBS}/chroot" <<'STUB'
#!/usr/bin/env bash
# Journalise puis ignore: on valide ce qui est DEMANDE a la cible, pas
# l'execution reelle dans un chroot.
shift || true
printf '%s\n' "$*" >> "${CHROOT_LOG}"
exit "${CHROOT_EXIT:-0}"
STUB

cat > "${STUBS}/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${FINDMNT_FSTYPE:-btrfs}"
STUB

cat > "${STUBS}/snapper" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

# btrfs: journalise les proprietes posees, sans rien toucher.
cat > "${STUBS}/btrfs" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BTRFS_LOG}"
exit 0
STUB
chmod +x "${STUBS}"/*

export CHROOT_LOG="${WORK}/chroot.log"
export BTRFS_LOG="${WORK}/btrfs.log"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

# Arborescence cible minimale, telle que Calamares la laisse.
make_target() {
  local t="$1" template_dir="$2"
  rm -rf "${t}"
  mkdir -p "${t}/etc/xdg/autostart" "${t}/usr/share/applications" \
           "${t}/usr/lib/auxinux" "${t}/usr/bin" "${t}/etc/auxinux" \
           "${t}/etc/apt/sources.list.d" "${t}/etc/greetd" \
           "${t}/etc/sddm.conf.d" "${t}/etc/systemd/system" \
           "${t}/usr/lib/systemd/system" "${t}/etc/X11" \
           "${t}/var/lib/auxinux" \
           "${t}/etc/snapper/configs" "${t}/etc/default" \
           "${t}/etc/default/grub-btrfs" "${t}/.snapshots" \
           "${t}/home/utilisateur/Desktop"

  touch "${t}/etc/xdg/autostart/auxinux-install.desktop" \
        "${t}/etc/xdg/autostart/auxinux-welcome.desktop" \
        "${t}/usr/share/applications/auxinux-install.desktop" \
        "${t}/usr/lib/auxinux/auxinux-install-launcher" \
        "${t}/usr/bin/auxinux-welcome" \
        "${t}/etc/fstab.orig.calamares" \
        "${t}/home/utilisateur/Desktop/Install AuxiNuxOS.desktop"
  mkdir -p "${t}/etc/sudoers.d"
  touch "${t}/etc/sudoers.d/90-auxinux-live"

  # fstab tel que le module Calamares `fstab` l'ecrit: aucun `nofail`, y
  # compris sur des montages dont l'absence ne devrait pas empecher de
  # demarrer.
  cat > "${t}/etc/fstab" <<'FSTAB'
# /etc/fstab
UUID=aaaa / btrfs defaults,noatime,subvol=@ 0 0
UUID=aaaa /home btrfs defaults,noatime,subvol=@home 0 0
UUID=aaaa /.snapshots btrfs defaults,noatime,subvol=@snapshots 0 0
UUID=aaaa /var/log btrfs defaults,noatime,subvol=@var_log 0 0
UUID=aaaa /var/lib/flatpak btrfs defaults,subvol=@var_lib_flatpak 0 0
UUID=BBBB-CCCC /boot/efi vfat umask=0077 0 2
/swap/swapfile none swap defaults 0 0
FSTAB

  # Autologin SDDM du live: il ouvre une session pour le compte `auxinux`, que
  # ce script supprime.
  cat > "${t}/etc/sddm.conf.d/90-auxinux-live-autologin.conf" <<'SDDM'
[Autologin]
User=auxinux
Session=plasma
Relogin=false
SDDM
  # Reliquat d'une image COSMIC: le squashfs peut venir d'une construction
  # precedente.
  cat > "${t}/etc/greetd/cosmic-greeter.toml" <<'GREETD'
[initial_session]
command = "/usr/bin/start-cosmic"
user = "auxinux"
GREETD
  touch "${t}/usr/lib/systemd/system/sddm.service"
  # Compteur de la protection au demarrage, incremente par les demarrages du
  # LIVE avant la construction du squashfs.
  printf '2\n' > "${t}/var/lib/auxinux/boot-failures"

  mkdir -p "${t}/etc/calamares/modules"
  touch "${t}/etc/calamares/modules/partition.conf"
  printf 'APT_ENABLED=1\n' > "${t}/etc/auxinux/apt.conf"
  printf 'deb file:/cdrom trixie main\n' > "${t}/etc/apt/sources.list.d/media.list"

  # /boot tel que grub-install et l'installation du noyau le laissent.
  mkdir -p "${t}/boot/grub/i386-pc" "${t}/boot/grub/fonts"
  # Noyau avec un TROU FINAL, comme apres `rsync -S` dans Calamares: les
  # 512 derniers octets du vrai noyau sont des zeros de remplissage, et le
  # pilote BTRFS de GRUB 2.12 s'arrete au dernier extent (« fin prematuree du
  # fichier »). 8 Kio de donnees, puis 512 octets de trou.
  printf 'NOYAU' > "${t}/boot/vmlinuz-7.2.5-auxinuxos-amd64"
  head -c 8187 /dev/zero | tr '\0' 'k' >> "${t}/boot/vmlinuz-7.2.5-auxinuxos-amd64"
  truncate -s 8704 "${t}/boot/vmlinuz-7.2.5-auxinuxos-amd64"
  printf 'INITRD' > "${t}/boot/initrd.img-7.2.5-auxinuxos-amd64"
  printf 'MENU' > "${t}/boot/grub/grub.cfg"
  printf 'MODULE' > "${t}/boot/grub/i386-pc/normal.mod"
  printf 'POLICE' > "${t}/boot/grub/fonts/unicode.pf2"

  # Disposition choisie dans l'installateur (ici l'AZERTY de France), telle que
  # le module Calamares `keyboard` l'ecrit.
  cat > "${t}/etc/default/keyboard" <<'KBD'
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBD

  # Partition EFI apres grub-install (images signees de Debian) et apres la
  # copie de secours de Calamares: grubx64.efi SEUL dans EFI/boot, sans son
  # grub.cfg -- ce qui mene a une invite « grub> ».
  mkdir -p "${t}/boot/efi/EFI/AuxiNuxOS" "${t}/boot/efi/EFI/boot"
  printf 'SHIM' > "${t}/boot/efi/EFI/AuxiNuxOS/shimx64.efi"
  printf 'GRUB' > "${t}/boot/efi/EFI/AuxiNuxOS/grubx64.efi"
  printf 'MOK'  > "${t}/boot/efi/EFI/AuxiNuxOS/mmx64.efi"
  printf "search.fs_uuid aaaa root\nset prefix=(\$root)'/@/boot/grub'\nconfigfile \$prefix/grub.cfg\n" \
    > "${t}/boot/efi/EFI/AuxiNuxOS/grub.cfg"
  printf 'GRUB' > "${t}/boot/efi/EFI/boot/bootx64.efi"

  touch "${t}/etc/default/grub-btrfs/config"
  printf 'y\n' > "${t}/usr/bin/snapper"; chmod +x "${t}/usr/bin/snapper"

  if [[ -n "${template_dir}" ]]; then
    mkdir -p "${t}/${template_dir}"
    printf 'SUBVOLUME=""\nFSTYPE=""\nTIMELINE_CREATE="no"\n' \
      > "${t}/${template_dir}/default"
  fi
}

echo "== 1. Nettoyage: l'installateur ne survit pas a l'installation =="
TARGET="${WORK}/cible1"
make_target "${TARGET}" ""
: > "${CHROOT_LOG}"
: > "${BTRFS_LOG}"
PATH="${STUBS}:${PATH}" bash "${CLEANUP}" "${TARGET}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "autodemarrage de l'installateur retire" \
  "$([[ -e "${TARGET}/etc/xdg/autostart/auxinux-install.desktop" ]] && echo present || echo absent)" "absent"
check "lanceur de l'installateur retire" \
  "$([[ -e "${TARGET}/usr/lib/auxinux/auxinux-install-launcher" ]] && echo present || echo absent)" "absent"
check "entree de menu retiree" \
  "$([[ -e "${TARGET}/usr/share/applications/auxinux-install.desktop" ]] && echo present || echo absent)" "absent"
check "icone du bureau retiree" \
  "$([[ -e "${TARGET}/home/utilisateur/Desktop/Install AuxiNuxOS.desktop" ]] && echo present || echo absent)" "absent"
check "fstab mis de cote retire" \
  "$([[ -e "${TARGET}/etc/fstab.orig.calamares" ]] && echo present || echo absent)" "absent"
check "sudo NOPASSWD retire" \
  "$([[ -e "${TARGET}/etc/sudoers.d/90-auxinux-live" ]] && echo present || echo absent)" "absent"
check "calamares purge de la cible" \
  "$(grep -c 'purge -y calamares' "${CHROOT_LOG}")" "1"
check "live-boot purge de la cible" \
  "$(grep -c 'live-boot' "${CHROOT_LOG}")" "1"
check "initramfs regenere apres la purge" \
  "$(grep -c 'update-initramfs' "${CHROOT_LOG}")" "1"
check "politique APT retablie" \
  "$(cat "${TARGET}/etc/auxinux/apt.conf")" "APT_ENABLED=0"
check "source APT locale retiree" \
  "$([[ -e "${TARGET}/etc/apt/sources.list.d/media.list" ]] && echo present || echo absent)" "absent"

# L'autologin du live pointe sur un compte que ce script supprime. S'il
# survit, SDDM tente d'ouvrir une session pour un utilisateur inexistant,
# echoue, recommence, atteint sa limite de redemarrages -- et le demarrage
# n'aboutit jamais. C'est la panne rapportee sur la 0.1 (avec greetd a
# l'epoque), et c'est le controle le plus important de ce fichier.
check "autologin SDDM du live retire" \
  "$([[ -e "${TARGET}/etc/sddm.conf.d/90-auxinux-live-autologin.conf" ]] && echo present || echo absent)" \
  "absent"
# Le reliquat COSMIC doit partir AUSSI: une config greetd laissee sur place
# avec un [initial_session] sur un compte supprime reintroduirait exactement la
# meme panne si greetd revenait a etre installe.
check "reliquat greetd/cosmic retire" \
  "$([[ -e "${TARGET}/etc/greetd" ]] && echo present || echo absent)" "absent"
check "gestionnaire d'affichage = sddm" \
  "$(readlink "${TARGET}/etc/systemd/system/display-manager.service")" \
  "/usr/lib/systemd/system/sddm.service"
check "default-display-manager ecrit" \
  "$(cat "${TARGET}/etc/X11/default-display-manager" 2>/dev/null)" "/usr/bin/sddm"
# Un compteur herite des demarrages du live enverrait le systeme installe en
# console de secours des son PREMIER demarrage, pour proposer de restaurer un
# instantane qui n'existe pas encore.
check "compteur de demarrages remis a zero" \
  "$([[ -e "${TARGET}/var/lib/auxinux/boot-failures" ]] && echo present || echo absent)" \
  "absent"

# Sans `nofail`, un seul de ces montages absent fait basculer systemd en mode
# urgence -- et comme le compte root n'a pas de mot de passe (users.conf:
# setRootPassword: false), sulogin refuse la console et le demarrage s'arrete
# la, definitivement.
for mp in /.snapshots /var/lib/flatpak /var/log /boot/efi; do
  check "nofail sur ${mp}" \
    "$(awk -v m="${mp}" '$2 == m { print ($4 ~ /(^|,)nofail(,|$)/) ? "oui" : "non" }' "${TARGET}/etc/fstab")" "oui"
done
check "nofail sur l'espace d'echange" \
  "$(awk '$3 == "swap" { print ($4 ~ /(^|,)nofail(,|$)/) ? "oui" : "non" }' "${TARGET}/etc/fstab")" "oui"
# La racine et le repertoire personnel ne doivent PAS etre en nofail: si l'un
# manque il n'y a rien a sauver, et demarrer en silence serait pire.
check "racine intacte (pas de nofail)" \
  "$(awk '$2 == "/" { print ($4 ~ /(^|,)nofail(,|$)/) ? "oui" : "non" }' "${TARGET}/etc/fstab")" "non"
check "/home intact (pas de nofail)" \
  "$(awk '$2 == "/home" { print ($4 ~ /(^|,)nofail(,|$)/) ? "oui" : "non" }' "${TARGET}/etc/fstab")" "non"

# GRUB lit /boot avec son propre pilote BTRFS, dont le decompresseur zstd a
# deja refuse un noyau compresse (« fin prematuree du fichier »). Tout /boot
# doit donc etre en clair -- y compris /boot/grub, cree par grub-install
# AVANT le nettoyage et qui n'herite de rien: sur une installation BIOS, GRUB y
# charge normal.mod.
for d in /boot /boot/grub /boot/grub/i386-pc /boot/grub/fonts; do
  check "compression desactivee sur ${d}" \
    "$(grep -cxF "property set ${TARGET}${d} compression none" "${BTRFS_LOG}")" "1"
done
check "partition EFI (FAT) laissee hors de BTRFS" \
  "$(grep -c "${TARGET}/boot/efi" "${BTRFS_LOG}")" "0"
check "noyau reecrit a l'identique" \
  "$(head -c 5 "${TARGET}/boot/vmlinuz-7.2.5-auxinuxos-amd64")$(stat -c %s "${TARGET}/boot/vmlinuz-7.2.5-auxinuxos-amd64")" "NOYAU8704"
# LE controle de la panne du 2026-09-13: plus aucun trou dans le noyau. Un
# fichier sans trou occupe au moins sa taille sur le disque.
check "trou final du noyau comble (GRUB lit jusqu'au dernier octet)" \
  "$(stat -c '%b %B %s' "${TARGET}/boot/vmlinuz-7.2.5-auxinuxos-amd64" | awk '{ print ($1 * $2 >= $3) ? "plein" : "troue" }')" "plein"
check "module GRUB reecrit a l'identique" \
  "$(cat "${TARGET}/boot/grub/i386-pc/normal.mod")" "MODULE"
check "aucun fichier temporaire oublie" \
  "$(find "${TARGET}/boot" -name '*.aux-tmp' | wc -l)" "0"

# La session Plasma (KWin) ne lit pas /etc/default/keyboard: sans kxkbrc elle
# est en « us ». Le mot de passe, tape en AZERTY dans l'installateur, ouvrait
# alors la session a l'ecran de connexion mais ne deverrouillait plus l'ecran.
check "disposition de la session = celle de l'installateur" \
  "$(sed -n 's/^LayoutList=//p' "${TARGET}/etc/xdg/kxkbrc" 2>/dev/null)" "fr"
check "modele de clavier repris" \
  "$(sed -n 's/^Model=//p' "${TARGET}/etc/xdg/kxkbrc" 2>/dev/null)" "pc105"
check "aucune option xkb inventee" \
  "$(grep -c '^Options=' "${TARGET}/etc/xdg/kxkbrc" 2>/dev/null)" "0"

# Chemin UEFI de secours: EFI/BOOT doit reproduire EFI/AuxiNuxOS, grub.cfg
# compris, sinon une machine qui a perdu l'entree NVRAM s'arrete sur « grub> ».
check "EFI/BOOT: shim en BOOTX64.EFI" \
  "$(cat "${TARGET}"/boot/efi/EFI/boot/BOOTX64.EFI 2>/dev/null)" "SHIM"
check "EFI/BOOT: GRUB a cote de shim" \
  "$(cat "${TARGET}"/boot/efi/EFI/boot/grubx64.efi 2>/dev/null)" "GRUB"
check "EFI/BOOT: grub.cfg present" \
  "$(cmp -s "${TARGET}/boot/efi/EFI/boot/grub.cfg" "${TARGET}/boot/efi/EFI/AuxiNuxOS/grub.cfg" && echo identique)" "identique"
# FAT ignore la casse: l'ancien bootx64.efi et le nouveau BOOTX64.EFI seraient
# le MEME fichier sur la vraie partition. Il ne doit en rester qu'un.
check "EFI/BOOT: une seule image de demarrage" \
  "$(ls "${TARGET}/boot/efi/EFI/boot" | grep -ci '^bootx64\.efi$')" "1"
check "mises a jour de GRUB: chemin de secours maintenu" \
  "$(grep -c 'debconf-set-selections' "${CHROOT_LOG}")" "1"

# Nos fichiers de configuration Calamares decrivent comment partitionner et
# formater un disque: ils n'ont rien a faire sur un systeme en service.
check "configuration Calamares retiree" \
  "$([[ -e "${TARGET}/etc/calamares" ]] && echo present || echo absent)" "absent"

echo "== 1b. Clavier a plusieurs dispositions, et installation sans shim =="
TARGET="${WORK}/cible1b"
make_target "${TARGET}" ""
cat > "${TARGET}/etc/default/keyboard" <<'KBD'
XKBMODEL="pc105"
XKBLAYOUT="ca,us"
XKBVARIANT="multix,"
XKBOPTIONS="grp:alt_shift_toggle"
KBD
rm -f "${TARGET}/boot/efi/EFI/AuxiNuxOS/shimx64.efi" "${TARGET}/boot/efi/EFI/AuxiNuxOS/mmx64.efi"
PATH="${STUBS}:${PATH}" bash "${CLEANUP}" "${TARGET}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "les deux dispositions reprises" \
  "$(sed -n 's/^LayoutList=//p' "${TARGET}/etc/xdg/kxkbrc")" "ca,us"
check "variantes reprises" \
  "$(sed -n 's/^VariantList=//p' "${TARGET}/etc/xdg/kxkbrc")" "multix,"
check "raccourci de bascule repris" \
  "$(sed -n 's/^Options=//p' "${TARGET}/etc/xdg/kxkbrc")" "grp:alt_shift_toggle"
check "options appliquees (ResetOldOptions)" \
  "$(grep -c '^ResetOldOptions=true$' "${TARGET}/etc/xdg/kxkbrc")" "1"
check "sans shim, GRUB lui-meme en BOOTX64.EFI" \
  "$(cat "${TARGET}"/boot/efi/EFI/boot/BOOTX64.EFI 2>/dev/null)" "GRUB"
check "sans shim, grub.cfg quand meme present" \
  "$([[ -s "${TARGET}/boot/efi/EFI/boot/grub.cfg" ]] && echo oui)" "oui"

echo "== 1c. Installation BIOS: aucune partition EFI, rien n'est invente =="
TARGET="${WORK}/cible1c"
make_target "${TARGET}" ""
rm -rf "${TARGET}/boot/efi"
PATH="${STUBS}:${PATH}" bash "${CLEANUP}" "${TARGET}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "aucune partition EFI creee" \
  "$([[ -e "${TARGET}/boot/efi" ]] && echo present || echo absent)" "absent"

echo "== 2. Rollback: modele snapper sous /usr/share (Debian 13) =="
TARGET="${WORK}/cible2"
make_target "${TARGET}" "usr/share/snapper/config-templates"
: > "${CHROOT_LOG}"
PATH="${STUBS}:${PATH}" bash "${ROLLBACK}" "${TARGET}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "configuration snapper ecrite" \
  "$([[ -f "${TARGET}/etc/snapper/configs/root" ]] && echo oui)" "oui"
check "sous-volume racine declare" \
  "$(grep -c '^SUBVOLUME="/"$' "${TARGET}/etc/snapper/configs/root")" "1"
check "instantanes horaires actives" \
  "$(grep -c '^TIMELINE_CREATE="yes"$' "${TARGET}/etc/snapper/configs/root")" "1"
check "config declaree aux services" \
  "$(grep -c 'SNAPPER_CONFIGS="root"' "${TARGET}/etc/default/snapper")" "1"
check "quotas BTRFS demandes" "$(grep -c 'setup-quota' "${CHROOT_LOG}")" "1"
check "instantane initial cree" "$(grep -c 'Installation initiale' "${CHROOT_LOG}")" "1"
check "menu GRUB regenere" "$(grep -c 'update-grub' "${CHROOT_LOG}")" "1"
check "marqueur de demarrage sur instantane pose" \
  "$(grep -c 'auxinux.snapshot=1' "${TARGET}/etc/default/grub-btrfs/config")" "1"
check "/.snapshots non lisible par tous" \
  "$(stat -c '%a' "${TARGET}/.snapshots")" "750"

echo "== 3. Rollback: modele sous /etc (autres distributions) =="
TARGET="${WORK}/cible3"
make_target "${TARGET}" "etc/snapper/config-templates"
PATH="${STUBS}:${PATH}" bash "${ROLLBACK}" "${TARGET}" >/dev/null 2>&1
check "configuration snapper ecrite" \
  "$([[ -f "${TARGET}/etc/snapper/configs/root" ]] && echo oui)" "oui"

echo "== 4. Rollback: aucun modele -> configuration minimale, jamais d'abandon =="
TARGET="${WORK}/cible4"
make_target "${TARGET}" ""
PATH="${STUBS}:${PATH}" bash "${ROLLBACK}" "${TARGET}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "configuration snapper ecrite quand meme" \
  "$([[ -s "${TARGET}/etc/snapper/configs/root" ]] && echo oui)" "oui"
check "sous-volume racine declare" \
  "$(grep -c '^SUBVOLUME="/"$' "${TARGET}/etc/snapper/configs/root")" "1"

echo "== 5. Rollback: racine ext4 -> sortie propre, rien de configure =="
TARGET="${WORK}/cible5"
make_target "${TARGET}" "usr/share/snapper/config-templates"
FINDMNT_FSTYPE=ext4 PATH="${STUBS}:${PATH}" bash "${ROLLBACK}" "${TARGET}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "aucune configuration snapper" \
  "$([[ -e "${TARGET}/etc/snapper/configs/root" ]] && echo present || echo absent)" "absent"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
