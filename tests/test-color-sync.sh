#!/usr/bin/env bash
#
# auxinux-color-sync: le choix clair/sombre du portail XDG recopie dans
# gsettings (org.gnome.desktop.interface color-scheme).
#
# DEMANDE A L'ORIGINE (2026-10-09, aporler): AuxiText et AuxiNux Office
# doivent suivre le theme clair ou sombre, sous Plasma comme dans AuxiNux
# Shell. En VM: Plasma sombre, portail = 1 (AuxiNux Office suit), gsettings
# reste 'default' (AuxiText, qui ne lit que lui, restait clair).
#
# gdbus et gsettings sont remplaces par des stubs. Le suivi en direct (signal
# SettingChanged) est valide en VM.
#
# Usage: bash tests/test-color-sync.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="${ROOT}/packages/release/root/usr/lib/auxinux/auxinux-color-sync"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

# Faux gsettings: la valeur vit dans un fichier; chaque « set » est consigne.
cat >"${WORK}/gsettings" <<STUB
#!/usr/bin/env bash
case "\$1" in
  get) printf "'%s'\n" "\$(cat "${WORK}/value")" ;;
  set) printf '%s' "\$4" >"${WORK}/value"; echo "set \$4" >>"${WORK}/sets" ;;
esac
STUB
# Faux gdbus: « call » rend PORTAL; « monitor » rejoue MONITOR.
cat >"${WORK}/gdbus" <<STUB
#!/usr/bin/env bash
case "\$1" in
  call) [[ -n "\$(cat "${WORK}/portal")" ]] || exit 1; cat "${WORK}/portal" ;;
  monitor) cat "${WORK}/monitor" ;;
esac
STUB
chmod +x "${WORK}/gsettings" "${WORK}/gdbus"
export AUXI_GDBUS="${WORK}/gdbus" AUXI_GSETTINGS="${WORK}/gsettings"
once() {
  printf '%s' "$1" >"${WORK}/value"; printf '%s' "$2" >"${WORK}/portal"; : >"${WORK}/sets"
  bash "${SYNC}" --once
  cat "${WORK}/value"
}

echo "== 1. Lecture au demarrage de la session =="
check "portail sombre -> prefer-dark" "$(once default '(<uint32 1>,)')" "prefer-dark"
check "portail clair -> prefer-light" "$(once prefer-dark '(<uint32 2>,)')" "prefer-light"
check "sans preference -> default" "$(once prefer-dark '(<uint32 0>,)')" "default"
once prefer-dark '(<uint32 1>,)' >/dev/null
check "deja a jour: aucune ecriture" "$(wc -l <"${WORK}/sets" | tr -d ' ')" "0"
check "reponse inattendue: rien n'est touche" "$(once prefer-dark '(<string bizarre>,)')" "prefer-dark"

echo "== 2. Changements pendant la session =="
printf 'default' >"${WORK}/value"; printf '(<uint32 2>,)' >"${WORK}/portal"; : >"${WORK}/sets"
cat >"${WORK}/monitor" <<'EOF2'
/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.kde.kdeglobals.General', 'ColorScheme', <'BreezeDark'>)
/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'color-scheme', <uint32 1>)
/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'accent-color', <(0.2, 0.5, 0.9)>)
/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'color-scheme', <uint32 2>)
/org/freedesktop/portal/desktop: org.freedesktop.portal.Settings.SettingChanged ('org.freedesktop.appearance', 'color-scheme', <uint32 1>)
EOF2
bash "${SYNC}"
check "suit sombre -> clair -> sombre, ignore le reste" "$(tr '\n' ' ' <"${WORK}/sets")" "set prefer-light set prefer-dark set prefer-light set prefer-dark "

echo "== 3. Portail muet: pas de boucle infinie =="
printf '' >"${WORK}/portal"; : >"${WORK}/monitor"
cat >"${WORK}/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "${WORK}/sleep"
PATH="${WORK}:${PATH}" timeout 10 bash "${SYNC}" --once
check "abandonne apres quelques essais" "$?" "0"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
