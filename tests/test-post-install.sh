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
chmod +x "${STUBS}"/*

export CHROOT_LOG="${WORK}/chroot.log"

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
  printf 'APT_ENABLED=1\n' > "${t}/etc/auxinux/apt.conf"
  printf 'deb file:/cdrom trixie main\n' > "${t}/etc/apt/sources.list.d/media.list"

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
