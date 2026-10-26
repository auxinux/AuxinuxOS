#!/usr/bin/env bash
#
# Les MISES A JOUR passent toujours: en ligne de commande comme dans le
# centre, que le reglage DEB soit actif ou non.
#
# DEMANDE A L'ORIGINE (2026-10-09, aporler): « que ce soit en cmd ou en
# interface, meme si DEB est desactive, les UPDATE doivent fonctionner ».
# Sa capture: « Actualisation des listes de paquets -- echec: Error executing
# command as another user: Not authorized ». Reproduit en VM: c'est l'invite
# GENERIQUE de pkexec (en anglais, « run /usr/bin/auxi --yes --progress update
# as the super user »), fermee. Et en ligne de commande, `auxi update` sans
# sudo -- la forme que propose le message d'apt -- s'arretait sur « Les
# operations DEB doivent etre executees avec sudo ».
#
# Couvre:
#   1. auxinux-refresh-helper (actualiser, sans mot de passe: aucun argument)
#   2. auxinux-update-helper (system | os | package <installes seulement>)
#   3. la politique polkit des deux helpers
#   4. apt-wrapper: `apt update` / `apt upgrade` confies a auxi, apt masque
#   5. auxi: relais par sudo dans un terminal, erreur sans terminal
#
# Usage: bash tests/test-update-paths.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS="${ROOT}/packages/auxinux-center/helper"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CALLS="${WORK}/calls"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Test a lancer hors root (les stubs ne sont honores que hors root)."
  exit 0
fi

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

mkdir -p "${WORK}/stubs"
cat >"${WORK}/stubs/auxi" <<STUB
#!/usr/bin/env bash
echo "auxi \$*" >>"${CALLS}"
STUB
cat >"${WORK}/stubs/dpkg-query" <<'STUB'
#!/usr/bin/env bash
# Installes: liblzma5, liblzma5:i386. Le reste: absent.
pkg="${@: -1}"
case "${pkg}" in
  liblzma5|liblzma5:i386) printf 'installed' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${WORK}/stubs/"*
export AUXINUX_UPDATE_TEST_ROOT="${WORK}/stubs"
last() { tail -n1 "${CALLS}" 2>/dev/null; }
run() { : >"${CALLS}"; "$@" >/dev/null 2>&1; echo $?; }

echo "== 1. Actualiser les listes =="
check "sans argument: auxi update" "$(run "${HELPERS}/auxinux-refresh-helper")" "0"
check "commande transmise" "$(last)" "auxi --yes --progress update"
check "un argument est refuse" "$(run "${HELPERS}/auxinux-refresh-helper" install x)" "64"
check "rien n'est lance" "$(last)" ""

echo "== 2. Mettre a jour le systeme =="
H="${HELPERS}/auxinux-update-helper"
run "${H}" system >/dev/null; check "system: auxi upgrade" "$(last)" "auxi --yes --progress upgrade"
run "${H}" os >/dev/null; check "os: auxi os upgrade" "$(last)" "auxi --yes --progress os upgrade"
check "package installe" "$(run "${H}" package liblzma5:i386)" "0"
check "package: install --deb du paquet installe" "$(last)" "auxi --yes --progress install --deb liblzma5:i386"
check "package NON installe refuse" "$(run "${H}" package vlc)" "64"
check "rien n'est lance" "$(last)" ""
check "nom invalide refuse" "$(run "${H}" package -- '--allow-unauthenticated')" "64"
check "option deguisee refusee" "$(run "${H}" package '-oAPT::X=1')" "64"
check "system avec argument refuse" "$(run "${H}" system extra)" "64"
check "commande inconnue refusee" "$(run "${H}" rm -rf /)" "64"

echo "== 3. Politique polkit =="
POLICY="${HELPERS}/ca.auxinux.center.policy"
action() {
  python3 - "${POLICY}" "$1" "$2" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for a in root.findall("action"):
    if a.get("id") == sys.argv[2]:
        if sys.argv[3] == "path":
            for an in a.findall("annotate"):
                if an.get("key") == "org.freedesktop.policykit.exec.path":
                    print(an.text)
        else:
            print(a.find("defaults/" + sys.argv[3]).text)
PY
}
check "refresh: helper d'actualisation" "$(action ca.auxinux.center.refresh path)" "/usr/libexec/auxinux/auxinux-refresh-helper"
check "refresh: sans mot de passe en session active" "$(action ca.auxinux.center.refresh allow_active)" "yes"
check "refresh: rien hors session" "$(action ca.auxinux.center.refresh allow_any)" "no"
check "system-update: helper de mise a jour" "$(action ca.auxinux.center.system-update path)" "/usr/libexec/auxinux/auxinux-update-helper"
check "system-update: mot de passe garde" "$(action ca.auxinux.center.system-update allow_active)" "auth_admin_keep"
check "system-update: message en francais" \
  "$(grep -c 'xml:lang="fr">Mettre à jour AuxiNux OS<' "${POLICY}")" "1"
CENTER="${ROOT}/packages/auxinux-center/src"
update_app="$(sed -n '/^pub fn update_app/,/^}/p' "${CENTER}/apps.rs")"
check "le centre n'appelle plus pkexec auxi pour les mises a jour" \
  "$(grep -c 'progress::auxi' "${CENTER}/updates.rs")/$(grep -c 'progress::auxi' <<<"${update_app}")" "0/0"
check "mise a jour d'un paquet DEB: helper « package »" "$(grep -c 'UPDATE_HELPER, "package"' <<<"${update_app}")" "1"
check "les helpers sont empaquetes" \
  "$(grep -c 'usr/libexec/auxinux/auxinux-\(refresh\|update\)-helper"$' "${ROOT}/packages/build-debs.sh")" "2"

echo "== 4. apt masque: les mises a jour passent par auxi =="
mkdir -p "${WORK}/bin"
ln -s "${ROOT}/packages/auxi-cli/apt-wrapper" "${WORK}/bin/apt"
ln -s "${ROOT}/packages/auxi-cli/apt-wrapper" "${WORK}/bin/apt-get"
export AUXI_BIN="${WORK}/stubs/auxi"
if [[ -r /etc/auxinux/apt.conf ]] && grep -Eq '^APT_ENABLED=1$' /etc/auxinux/apt.conf; then
  echo "  (apt actif sur cette machine: partie 4 sautee)"
else
  check "apt update" "$(run "${WORK}/bin/apt" update)" "0"
  check "  -> auxi update --deb" "$(last)" "auxi update --deb"
  run "${WORK}/bin/apt" upgrade >/dev/null; check "apt upgrade -> auxi os upgrade" "$(last)" "auxi os upgrade"
  run "${WORK}/bin/apt-get" -y upgrade >/dev/null; check "apt-get -y upgrade -> --yes" "$(last)" "auxi --yes os upgrade"
  run "${WORK}/bin/apt" full-upgrade >/dev/null; check "apt full-upgrade -> auxi os upgrade (ne retire rien)" "$(last)" "auxi os upgrade"
  check "apt upgrade firefox: refuse" "$(run "${WORK}/bin/apt" upgrade firefox)" "1"
  check "  rien n'est lance" "$(last)" ""
  # Nettoyage (2026-10-26): confie a auxi, plus refuse.
  run "${WORK}/bin/apt" autoremove >/dev/null; check "apt autoremove -> auxi autoremove --deb" "$(last)" "auxi autoremove --deb"
  run "${WORK}/bin/apt-get" -y autoremove >/dev/null; check "apt-get -y autoremove -> --yes" "$(last)" "auxi --yes autoremove --deb"
  run "${WORK}/bin/apt" autoclean >/dev/null; check "apt autoclean -> auxi autoclean" "$(last)" "auxi autoclean"
  run "${WORK}/bin/apt-get" clean >/dev/null; check "apt-get clean -> auxi clean" "$(last)" "auxi clean"
  check "apt install vlc: toujours refuse" "$(run "${WORK}/bin/apt" install vlc)" "1"
  check "  rien n'est lance" "$(last)" ""
fi
unset AUXI_BIN

echo "== 5. auxi: relais par sudo dans un terminal =="
export LANGUAGE=fr_CA:fr LANG=fr_CA.UTF-8
unset AUXI_NO_SUDO
AUXI="${ROOT}/packages/auxi-cli/auxi"
cat >"${WORK}/bin/sudo" <<STUB
#!/usr/bin/env bash
echo "sudo \$*" >>"${CALLS}"
STUB
cat >"${WORK}/bin/flatpak" <<STUB
#!/usr/bin/env bash
echo "flatpak \$*" >>"${CALLS}"
STUB
chmod +x "${WORK}/bin/sudo" "${WORK}/bin/flatpak"
: >"${CALLS}"
PATH="${WORK}/bin:${PATH}" script -qec "${AUXI} update" /dev/null >"${WORK}/tty.out" 2>&1
check "auxi update (terminal): relance par sudo" "$(grep -c "^sudo -- ${AUXI} update$" "${CALLS}")" "1"
check "  sans faire d'abord la partie Flatpak" "$(grep -c '^flatpak' "${CALLS}")" "0"
check "  et le dit" "$(grep -c 'Droits administrateur nécessaires: sudo auxi update' "${WORK}/tty.out")" "1"
: >"${CALLS}"
PATH="${WORK}/bin:${PATH}" script -qec "${AUXI} --yes os upgrade" /dev/null >/dev/null 2>&1
check "options globales conservees" "$(last)" "sudo -- ${AUXI} --yes os upgrade"
: >"${CALLS}"
PATH="${WORK}/bin:${PATH}" script -qec "${AUXI} upgrade" /dev/null >/dev/null 2>&1
check "auxi upgrade: sudo avant Flatpak" "$(head -n1 "${CALLS}")" "sudo -- ${AUXI} upgrade"
: >"${CALLS}"
PATH="${WORK}/bin:${PATH}" "${AUXI}" update </dev/null >/dev/null 2>"${WORK}/err"
check "sans terminal: erreur claire, pas de sudo" "$(grep -c '^sudo' "${CALLS}")/$(grep -c 'avec sudo' "${WORK}/err")" "0/1"
: >"${CALLS}"
PATH="${WORK}/bin:${PATH}" script -qec "${AUXI} update --flatpak" /dev/null >/dev/null 2>&1
check "auxi update --flatpak: reste utilisateur" "$(grep -c '^sudo' "${CALLS}")" "0"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
