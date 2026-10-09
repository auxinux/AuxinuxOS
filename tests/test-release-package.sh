#!/usr/bin/env bash
#
# Paquet auxinuxos-release: la VERSION d'AuxiNux OS (une edition par ISO
# publiee) et les reglages du systeme installe.
#
# DEMANDE A L'ORIGINE (2026-10-09, aporler): quand une nouvelle version est
# publiee, la page Mises a jour doit l'annoncer et permettre d'y passer. Et
# un defaut latent trouve en chemin: /usr/lib/os-release appartient a
# base-files; une mise a jour de Debian aurait remis « Debian GNU/Linux 13 ».
#
# Construit les trois paquets avec un faux binaire du centre (AUXINUX_STRIP=0)
# et verifie leur contenu. L'installation reelle (detournement d'os-release,
# passage depuis la 0.2.2) est validee en VM.
#
# Usage: bash tests/test-release-package.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v dpkg-deb >/dev/null || { echo "dpkg-deb absent: test saute"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "${ROOT}/packages/auxinux-center/Cargo.toml" | head -n1)"
printf '#!/bin/sh\necho "auxinux-center %s"\n' "${VERSION}" > "${WORK}/center"
chmod +x "${WORK}/center"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
build() {
  AUXINUX_STRIP=0 AUXINUX_CENTER_BIN="${WORK}/center" AUXINUX_RELEASE="$1" \
    "${ROOT}/packages/build-debs.sh" --out "$2" >/dev/null 2>"${WORK}/err"
}

echo "== 1. Edition du jour, seconde ISO du meme jour =="
build "0.2.0+20261009.2" "${WORK}/out"
check "construit" "$?" "0"
DEB="${WORK}/out/auxinuxos-release_0.2.0+20261009.2_all.deb"
check "paquet d'edition present" "$([[ -f ${DEB} ]] && echo oui)" "oui"
field() { dpkg-deb -f "${DEB}" "$1"; }
check "version" "$(field Version)" "0.2.0+20261009.2"
check "resume lisible" "$(field Description | head -n1)" "AuxiNux OS 0.2.0, édition du 2026-10-09 (2)"
check "nouveautes = description longue" \
  "$(dpkg-deb -f "${DEB}" Description | tail -n +2 | grep -c 'Programmes Windows')" "1"
check "tire auxi et le centre de la livraison" \
  "$(field Depends | grep -c "auxi (>= ${VERSION}), auxinux-center (>= ${VERSION}), kernel-auxinuxos")" "1"
check "reprend kiorc au centre 0.2.2" "$(field Replaces)" "auxinux-center (<< 0.2.3)"
check "os-release porte l'edition" \
  "$(dpkg-deb --fsys-tarfile "${DEB}" | tar -xO ./usr/lib/os-release | grep -c '^BUILD_ID=20261009.2$')" "1"
check "os-release dit toujours AuxiNux OS" \
  "$(dpkg-deb --fsys-tarfile "${DEB}" | tar -xO ./usr/lib/os-release | grep -c '^PRETTY_NAME="AuxiNux OS ')" "1"

echo "== 2. Reglages du systeme installe: dans le paquet, en conffiles =="
contents="$(dpkg-deb -c "${DEB}" | awk '{print $6}')"
for f in etc/xdg/mimeapps.list etc/xdg/kiorc etc/xdg/kscreenlockerrc etc/sddm.conf.d/10-auxinux.conf \
         etc/apt/apt.conf.d/80auxinux-snapshot etc/apt/apt.conf.d/20auxinux-periodic \
         etc/brave/policies/managed/auxinux-privacy.json; do
  check "contient /${f}" "$(grep -cx "./${f}" <<<"${contents}")" "1"
done
conffiles="$(dpkg-deb --ctrl-tarfile "${DEB}" | tar -xO ./conffiles)"
check "chaque fichier de /etc est un conffile" \
  "$(grep -c '^\./etc/.*[^/]$' <<<"${contents}")" "$(wc -l <<<"${conffiles}" | tr -d ' ')"
check "os-release N'EST PAS un conffile (detourne)" "$(grep -c os-release <<<"${conffiles}")" "0"
check "hook initramfs executable" \
  "$(dpkg-deb -c "${DEB}" | awk '$6 == "./etc/initramfs-tools/hooks/auxinux-snapshot-overlay" {print $1}')" "-rwxr-xr-x"
ctrl="$(dpkg-deb --ctrl-tarfile "${DEB}" | tar -t | sort | tr '\n' ' ')"
check "scripts de maintenance" "${ctrl}" "./ ./conffiles ./control ./md5sums ./postinst ./postrm ./preinst ./triggers "
check "preinst detourne os-release de base-files" \
  "$(dpkg-deb --ctrl-tarfile "${DEB}" | tar -xO ./preinst | grep -c 'dpkg-divert --package auxinuxos-release --add --no-rename')" "1"

preinst="$(dpkg-deb --ctrl-tarfile "${DEB}" | tar -xO ./preinst)"
check "preinst: plus de marqueur @CONFFILES@" "$(grep -c '@CONFFILES@' <<<"${preinst}")" "0"
check "preinst: met de cote les copies de l'image (ex. mimeapps.list)" \
  "$(grep -c '/etc/xdg/mimeapps.list' <<<"${preinst}")" "1"
check "preinst: syntaxe" "$(sh -n <<<"${preinst}" && echo ok)" "ok"

echo "== 3. Kiorc quitte le paquet du centre =="
CDEB="${WORK}/out/auxinux-center_${VERSION}_amd64.deb"
check "plus de /etc/xdg/kiorc dans auxinux-center" "$(dpkg-deb -c "${CDEB}" | grep -c 'etc/xdg/kiorc')" "0"

echo "== 4. Editions refusees =="
for bad in "0.3.0+20261009" "0.2.0" "0.2.0+2026109" "0.2.0+20261009-2"; do
  build "${bad}" "${WORK}/bad"
  check "« ${bad} » refusee" "$?" "65"
done

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
