#!/usr/bin/env bash
#
# `auxi kernel`: lister, installer, activer, desinstaller les noyaux AuxiNux.
#
# PANNE A L'ORIGINE (2026-10-07, rapportee par aporler): avec le reglage DEB
# coupe, impossible d'installer le noyau d'essai. Le noyau d'essai est un
# paquet DISTINCT (linux-image-7.2.9-dev-auxinuxos-amd64): activer la source
# n'installait rien, et `auxi install --deb` refuse tout paquet nouveau.
#
# dpkg-query, apt-cache, apt-get, uname et les outils GRUB sont simules; le
# grub.cfg de test reprend la forme exacte de celui de Debian.
#
# Usage: bash tests/test-auxi-kernel.sh
set -uo pipefail

AUXI_BIN="${AUXI_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxi-cli/auxi}"
if [[ ! -r "${AUXI_BIN}" ]]; then
  echo "auxi introuvable: ${AUXI_BIN}" >&2
  exit 66
fi

# Messages en francais quelle que soit la langue de la machine de test.
export LANG=C.UTF-8 LANGUAGE= LC_ALL= LC_MESSAGES=

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CALLS="${WORK}/calls"
export AUXI_GRUB_CFG="${WORK}/grub.cfg"
export AUXI_GRUBENV="${WORK}/grubenv"
export AUXI_GRUB_DEFAULT_D="${WORK}/grub.d"
export AUXI_SOURCES_D="${WORK}/sources.list.d"
mkdir -p "${AUXI_SOURCES_D}"

UUID="0b6e5c1e-1111-2222-3333-444455556666"
cat >"${AUXI_GRUB_CFG}" <<EOF
menuentry 'AuxiNux OS' --class auxinux --class gnu-linux --class gnu --class os \$menuentry_id_option 'gnulinux-simple-${UUID}' {
	linux	/@/boot/vmlinuz-7.2.9-dev-auxinuxos-amd64 root=UUID=${UUID} ro rootflags=subvol=@
}
submenu 'Options avancées pour AuxiNux OS' \$menuentry_id_option 'gnulinux-advanced-${UUID}' {
	menuentry 'AuxiNux OS, avec Linux 7.2.9-dev-auxinuxos-amd64' --class auxinux \$menuentry_id_option 'gnulinux-7.2.9-dev-auxinuxos-amd64-advanced-${UUID}' {
		linux	/@/boot/vmlinuz-7.2.9-dev-auxinuxos-amd64 root=UUID=${UUID} ro
	}
	menuentry 'AuxiNux OS, avec Linux 7.2.9-dev-auxinuxos-amd64 (recovery mode)' --class auxinux \$menuentry_id_option 'gnulinux-7.2.9-dev-auxinuxos-amd64-recovery-${UUID}' {
		linux	/@/boot/vmlinuz-7.2.9-dev-auxinuxos-amd64 root=UUID=${UUID} ro single
	}
	menuentry 'AuxiNux OS, avec Linux 7.2.5-auxinuxos-amd64' --class auxinux \$menuentry_id_option 'gnulinux-7.2.5-auxinuxos-amd64-advanced-${UUID}' {
		linux	/@/boot/vmlinuz-7.2.5-auxinuxos-amd64 root=UUID=${UUID} ro
	}
}
EOF

# Faux apt-get (le vrai binaire est appele par chemin, via apt_real): consigne
# ses arguments; `-s purge` imprime la simulation choisie par le cas.
cat >"${WORK}/apt-get" <<STUB
#!/usr/bin/env bash
echo "apt-get \$*" >>"${CALLS}"
case " \$* " in
  *" -s purge "*) cat "${WORK}/simulation" 2>/dev/null ;;
esac
exit 0
STUB
chmod +x "${WORK}/apt-get"

# Etat simule de la machine, modifie par chaque cas.
INSTALLED="7.2.5-auxinuxos-amd64"
AVAILABLE="7.2.5-auxinuxos-amd64 7.2.6-auxinuxos-amd64 7.2.9-dev-auxinuxos-amd64"
RUNNING="7.2.5-auxinuxos-amd64"

source "${AUXI_BIN}" >/dev/null
set +e
apt_real() { echo "${WORK}/apt-get"; }
require_root_for_deb() { return 0; }
kernel_running() { echo "${RUNNING}"; }
dpkg-query() {
  local v
  for v in ${INSTALLED}; do
    printf 'linux-image-%s\tinstall ok installed\n' "${v}"
  done
  # Paquets d'un autre fournisseur: jamais listes.
  printf 'linux-image-6.12.48+deb13-amd64\tinstall ok installed\n'
  printf 'linux-image-7.1.0-auxinuxos-amd64\tdeinstall ok config-files\n'
}
deb_installed() { [[ "$1" == linux-headers-* && " ${INSTALLED} " == *" ${1#linux-headers-} "* ]]; }
apt_cache() {
  local v
  case "$1" in
    pkgnames)
      for v in ${AVAILABLE}; do printf 'linux-image-%s\n' "${v}"; done
      printf 'linux-image-6.12.48+deb13-amd64\nlinux-image-amd64\nlinux-image-7.1.0-auxinuxos-amd64\n'
      ;;
    show)
      v="${3#linux-image-}"; v="${v#linux-headers-}"
      [[ " ${AVAILABLE} " == *" ${v} "* ]]
      ;;
  esac
}
update-grub() { echo "update-grub" >>"${CALLS}"; }
grub-set-default() { echo "grub-set-default $*" >>"${CALLS}"; printf 'saved_entry=%s\n' "$1" >"${AUXI_GRUBENV}"; }
grub-editenv() { echo "grub-editenv $*" >>"${CALLS}"; : >"${AUXI_GRUBENV}"; }

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
has() {
  if grep -qF -- "$2" "${CALLS}"; then echo "  OK   $1"; else echo "  ECHEC $1: [$2] absent de:"; sed 's/^/         /' "${CALLS}"; fail=1; fi
}
lacks() {
  if ! grep -qF -- "$2" "${CALLS}"; then echo "  OK   $1"; else echo "  ECHEC $1: [$2] present"; fail=1; fi
}
run() { : >"${CALLS}"; out="$( (set -e; "$@") </dev/null 2>&1)"; rc=$?; }

echo "== 1. Liste lisible par le centre (--porcelain) =="
run run_kernel_list --porcelain
check "reussit sans root" "${rc}" "0"
check "noyau actif" "$(grep -P '^actif\t' <<<"${out}")" $'actif\t7.2.5-auxinuxos-amd64'
check "defaut: premiere entree de grub.cfg, non epingle" "$(grep -P '^defaut\t' <<<"${out}")" $'defaut\t7.2.9-dev-auxinuxos-amd64\tauto'
check "source d'essai coupee" "$(grep -P '^source-dev\t' <<<"${out}")" $'source-dev\toff'
check "installe et actif" "$(grep -P '^noyau\t7.2.5-' <<<"${out}")" $'noyau\t7.2.5-auxinuxos-amd64\tstable\tinstalle,actif'
check "stable disponible" "$(grep -P '^noyau\t7.2.6-' <<<"${out}")" $'noyau\t7.2.6-auxinuxos-amd64\tstable\tdisponible'
check "essai disponible, canal dev" "$(grep -P '^noyau\t7.2.9-' <<<"${out}")" $'noyau\t7.2.9-dev-auxinuxos-amd64\tdev\tdisponible'
check "ni noyau Debian ni reliquat de configuration" "$(grep -cE 'deb13|7\.1\.0|linux-image-amd64' <<<"${out}")" "0"

echo "== 2. Seuls les noyaux AuxiNux sont acceptes (pas une porte derobee DEB) =="
for nom in vlc linux-image-amd64 6.12.48+deb13-amd64 '7.2.5-auxinuxos-amd64;rm' ''; do
  run run_kernel_install "${nom}"
  check "install [${nom}]: refuse" "${rc}" "64"
done
lacks "aucun apt-get" "apt-get"

echo "== 3. Installation =="
run run_kernel_install 7.2.9-dev-auxinuxos-amd64
check "essai avec la source coupee: refuse" "${rc}" "1"
check "la facon de l'activer est dite" "$(grep -c 'auxi kernel dev on' <<<"${out}")" "1"
lacks "aucun apt-get" "apt-get"
run run_kernel_install 7.3.0-auxinuxos-amd64
check "version absente des depots: refusee" "${rc}" "1"
run run_kernel_install 7.2.6-auxinuxos-amd64
check "stable disponible: installe" "${rc}" "0"
has "image et en-tetes en une transaction" "install -- linux-image-7.2.6-auxinuxos-amd64 linux-headers-7.2.6-auxinuxos-amd64"
run run_kernel_install 7.2.5-auxinuxos-amd64
check "deja installe: rien a faire" "${rc}" "0"
lacks "deja installe: aucun apt-get" "apt-get"

echo "== 4. Source d'essai =="
printf 'Types: deb\n' >"${AUXI_SOURCES_D}/auxinuxos-kernel-dev.sources.disabled"
run run_kernel_dev on
check "dev on" "${rc}" "0"
check "le fichier est renomme" "$(ls "${AUXI_SOURCES_D}")" "auxinuxos-kernel-dev.sources"
has "les index sont rafraichis" "update"
run run_kernel_install 7.2.9-dev-auxinuxos-amd64
check "essai avec la source active: installe" "${rc}" "0"
has "apt-get install du noyau d'essai" "install -- linux-image-7.2.9-dev-auxinuxos-amd64"

echo "== 5. Mise a jour par canal =="
INSTALLED="7.2.5-auxinuxos-amd64"
run kernel_update_channels
has "stable: la 7.2.6 arrive" "install -- linux-image-7.2.6-auxinuxos-amd64"
lacks "essai: rien tant qu'aucun noyau d'essai n'est installe" "7.2.9-dev"
INSTALLED="7.2.5-auxinuxos-amd64 7.2.6-auxinuxos-amd64 7.2.8-dev-auxinuxos-amd64"
run kernel_update_channels
has "essai: la 7.2.9-dev suit la 7.2.8-dev" "install -- linux-image-7.2.9-dev-auxinuxos-amd64"
lacks "stable deja a jour: rien" "linux-image-7.2.6"
INSTALLED="7.2.5-auxinuxos-amd64"

echo "== 6. Activer un noyau (GRUB) =="
INSTALLED="7.2.5-auxinuxos-amd64 7.2.9-dev-auxinuxos-amd64"
run run_kernel_activate 7.2.6-auxinuxos-amd64
check "non installe: refuse" "${rc}" "1"
run run_kernel_activate 7.2.5-auxinuxos-amd64
check "activer 7.2.5" "${rc}" "0"
check "GRUB_DEFAULT=saved par un fichier grub.d" \
  "$(grep -c '^GRUB_DEFAULT=saved$' "${AUXI_GRUB_DEFAULT_D}/50-auxinux-noyau.cfg")" "1"
has "update-grub" "update-grub"
has "entree avancee exacte (pas le mode de secours)" \
  "grub-set-default gnulinux-advanced-${UUID}>gnulinux-7.2.5-auxinuxos-amd64-advanced-${UUID}"
run run_kernel_list --porcelain
check "defaut epingle sur 7.2.5" "$(grep -P '^defaut\t' <<<"${out}")" $'defaut\t7.2.5-auxinuxos-amd64\tepingle'
check "badge defaut" "$(grep -P '^noyau\t7.2.5-' <<<"${out}")" $'noyau\t7.2.5-auxinuxos-amd64\tstable\tinstalle,actif,defaut'

sed 's/7\.2\.5-auxinuxos/7.2.4-auxinuxos/g' "${AUXI_GRUB_CFG}" >"${WORK}/grub-sans.cfg"
AUXI_GRUB_CFG_SAVE="${GRUB_CFG}"
GRUB_CFG="${WORK}/grub-sans.cfg"
rm -rf "${AUXI_GRUB_DEFAULT_D}"
run run_kernel_activate 7.2.5-auxinuxos-amd64
check "entree introuvable dans grub.cfg: refus" "${rc}" "69"
check "rien n'a ete modifie" "$([[ -e ${AUXI_GRUB_DEFAULT_D}/50-auxinux-noyau.cfg ]] && echo modifie || echo intact)" "intact"
GRUB_CFG="${AUXI_GRUB_CFG_SAVE}"

run run_kernel_activate 7.2.5-auxinuxos-amd64
run run_kernel_activate latest
check "revenir au plus recent" "${rc}" "0"
check "fichier grub.d retire" "$([[ -e ${AUXI_GRUB_DEFAULT_D}/50-auxinux-noyau.cfg ]] && echo present || echo retire)" "retire"
has "entree enregistree effacee" "grub-editenv"

echo "== 7. Desinstaller =="
INSTALLED="7.2.5-auxinuxos-amd64 7.2.9-dev-auxinuxos-amd64"
RUNNING="7.2.9-dev-auxinuxos-amd64"
run run_kernel_remove 7.2.9-dev-auxinuxos-amd64
check "le noyau en cours: refuse" "${rc}" "1"
lacks "aucun apt-get" "apt-get"
run run_kernel_remove 7.2.5-auxinuxos-amd64
check "le dernier noyau stable: refuse" "${rc}" "1"
lacks "aucun apt-get" "apt-get"

INSTALLED="7.2.5-auxinuxos-amd64 7.2.6-auxinuxos-amd64 7.2.9-dev-auxinuxos-amd64"
printf 'Purg linux-image-7.2.6-auxinuxos-amd64 [7.2.6-auxinuxos-amd64.1]\nPurg kernel-auxinuxos [7.2.6-auxinuxos-amd64.1]\n' >"${WORK}/simulation"
run run_kernel_remove 7.2.6-auxinuxos-amd64
check "emporterait kernel-auxinuxos: refuse" "${rc}" "1"
check "la raison est dite" "$(grep -c 'kernel-auxinuxos' <<<"${out}")" "1"
check "rien de desinstalle (seulement la simulation)" "$(grep -c '^apt-get purge' "${CALLS}")" "0"

run run_kernel_activate 7.2.5-auxinuxos-amd64
RUNNING="7.2.6-auxinuxos-amd64"
printf 'Purg linux-headers-7.2.5-auxinuxos-amd64 [x]\nPurg linux-image-7.2.5-auxinuxos-amd64 [x]\n' >"${WORK}/simulation"
run run_kernel_remove 7.2.5-auxinuxos-amd64
check "ancien stable avec un autre stable present: desinstalle" "${rc}" "0"
has "image et en-tetes purges (apres la simulation)" "apt-get purge -- linux-image-7.2.5-auxinuxos-amd64 linux-headers-7.2.5-auxinuxos-amd64"
check "il etait epingle: retour au plus recent" \
  "$([[ -e ${AUXI_GRUB_DEFAULT_D}/50-auxinux-noyau.cfg ]] && echo epingle || echo plus-recent)" "plus-recent"

printf 'Purg linux-image-7.2.9-dev-auxinuxos-amd64 [x]\nPurg kernel-auxinuxos-dev [x]\n' >"${WORK}/simulation"
run run_kernel_remove 7.2.9-dev-auxinuxos-amd64
check "noyau d'essai avec son metapaquet: desinstalle" "${rc}" "0"
has "purge du noyau d'essai" "apt-get purge -- linux-image-7.2.9-dev-auxinuxos-amd64"

echo "== 8. Couper la source d'essai garde les noyaux installes =="
INSTALLED="7.2.5-auxinuxos-amd64 7.2.9-dev-auxinuxos-amd64"
run run_kernel_dev off
check "dev off" "${rc}" "0"
check "le fichier est desactive" "$(ls "${AUXI_SOURCES_D}")" "auxinuxos-kernel-dev.sources.disabled"
check "l'utilisateur est prevenu" "$(grep -c 'gardés' <<<"${out}")" "1"
lacks "aucun noyau retire" "purge"

if [[ "${fail}" -eq 0 ]]; then
  echo "test-auxi-kernel: OK"
else
  echo "test-auxi-kernel: ECHEC"
fi
exit "${fail}"
