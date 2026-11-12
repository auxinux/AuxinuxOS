#!/usr/bin/env bash
#
# auxinuxos-agent-update: recherche des mises a jour toutes les 60 minutes,
# signalement dans la zone de notification, clic = Parametres > Mises a jour.
#
# DEMANDE A L'ORIGINE (2026-11-12, aporler): « regarder au 60 minutes si des
# updates sont disponibles ; si oui dans la zone de notification on notifie,
# et si la personne clique dessus on lance les Parametres du Shell dans la
# section Mise a jour ; dans les parametres on peut desactiver la verification
# automatique, mais par defaut elle est active ».
#
# Couvre:
#   1. fonctions pures (lecture apt/flatpak, reglage, empreinte, rappel)
#   2. de bout en bout dans une session D-Bus jetable (dbus-run-session):
#      faux serveur de notifications et fausse zone de notification, faux
#      pkcheck/pkexec/apt-get/flatpak/auxinux-settings (tests/agent-update-harness.py)
#   3. le service utilisateur (syntaxe systemd, si systemd-analyze est la)
#
# Exige python3-gi et dbus-run-session (hote de build: homedev).
# Usage: bash tests/test-agent-update.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="${ROOT}/packages/agent-update/auxinuxos-agent-update"
UNIT="${ROOT}/packages/agent-update/auxinuxos-agent-update.service"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

python3 -c 'import gi; from gi.repository import Gio' 2>/dev/null \
  || { echo "python3-gi absent: test impossible ici (lancez-le sur l'hote de build)" >&2; exit 77; }
command -v dbus-run-session >/dev/null || { echo "dbus-run-session absent" >&2; exit 77; }

fail=0

echo "== 1. Fonctions pures =="
python3 -I - "${AGENT}" <<'PY' || fail=1
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("agent", sys.argv[1])
spec = importlib.util.spec_from_loader("agent", loader)
a = importlib.util.module_from_spec(spec)
loader.exec_module(a)
bad = 0
def check(label, got, want):
    global bad
    print(("  OK   " if got == want else "  ECHEC ") + label + ("" if got == want else f": attendu [{want}] obtenu [{got}]"))
    bad += got != want

apt = ("Reading package lists...\n"
       "Inst libc6 [2.41-12] (2.41-12+deb13u1 Debian:13.2/stable [amd64])\n"
       "Inst kernel-auxinuxos (7.2.14 AuxiNux:APPS [amd64])\n"
       "Conf libc6 (2.41-12+deb13u1 Debian:13.2/stable [amd64])\n")
check("apt: mise a jour et nouveau paquet", a.parse_apt_simulation(apt),
      [["libc6", "2.41-12", "2.41-12+deb13u1"], ["kernel-auxinuxos", "", "7.2.14"]])
check("flatpak: en-tete ignore", a.parse_flatpak_updates("Application ID\tName\tVersion\norg.gimp.GIMP\tGIMP\t3.0.6\n"),
      [["org.gimp.GIMP", "GIMP", "3.0.6"]])
check("version: resume", a.release_summary("Package: x\nDescription: AuxiNux OS 0.5.1, édition\n"),
      "AuxiNux OS 0.5.1, édition")

import json, tempfile, pathlib
d = pathlib.Path(tempfile.mkdtemp())
user, default = d / "user.json", d / "default.json"
check("reglage: ACTIF par defaut (aucun fichier)", a.auto_check_enabled(user, default), True)
default.write_text(json.dumps({"updates": {"auto_check": True}}))
check("reglage: defaut du paquet", a.auto_check_enabled(user, default), True)
user.write_text(json.dumps({"updates": {"auto_check": False}}))
check("reglage: coupe par l'utilisateur", a.auto_check_enabled(user, default), False)
user.write_text("{casse")
check("reglage: fichier illisible = actif", a.auto_check_enabled(user, default), True)

s1 = a.signature([["libc6", "1", "2"]], [["org.gimp.GIMP", "GIMP", "3"]])
s2 = a.signature([["libc6", "1", "2"]], [["org.gimp.GIMP", "GIMP", "3"]])
s3 = a.signature([["libc6", "1", "3"]], [["org.gimp.GIMP", "GIMP", "3"]])
check("empreinte stable", s1, s2)
check("empreinte change avec une nouvelle version", s1 != s3, True)
check("rien a installer: pas d'empreinte", a.signature([], []), "")
check("notifier: ensemble nouveau", a.should_notify(s1, {}, 1000), True)
check("notifier: meme ensemble, moins d'un jour", a.should_notify(s1, {"notified_signature": s1, "notified_at": 1000}, 1000 + 3600), False)
check("notifier: rappel apres un jour", a.should_notify(s1, {"notified_signature": s1, "notified_at": 1000}, 1000 + 86400), True)
check("notifier: rien a installer", a.should_notify("", {}, 1000), False)
check("intervalle par defaut: 60 minutes", a.INTERVAL, 3600)
sys.exit(1 if bad else 0)
PY

echo "== 2. De bout en bout (session D-Bus jetable) =="
mkdir -p "${WORK}/bin" "${WORK}/helpers" "${WORK}/home"
CALLS="${WORK}/calls"
cat >"${WORK}/apt-output" <<'EOF'
Inst auxinuxos-release [0.5.0+20261027] (0.5.1+20261112 AuxiNux:APPS [amd64])
Inst firefox-esr (140.5 Debian-Security:13/stable [amd64])
EOF
printf 'org.gimp.GIMP\tGIMP\t3.0.6\n' >"${WORK}/flatpak-output"
echo 0 >"${WORK}/pkcheck-status"
fake() { printf '#!/bin/sh\n%s\n' "$2" >"${WORK}/bin/$1"; chmod +x "${WORK}/bin/$1"; }
fake pkcheck "echo \"pkcheck \$*\" >>'${CALLS}'; exit \$(cat '${WORK}/pkcheck-status')"
fake pkexec "echo \"pkexec \$*\" >>'${CALLS}'; exec \"\$@\""
fake apt-get "echo \"apt-get \$*\" >>'${CALLS}'; cat '${WORK}/apt-output'"
fake apt-cache "echo 'Package: auxinuxos-release'; echo 'Description: AuxiNux OS 0.5.1'"
fake flatpak "echo \"flatpak \$*\" >>'${CALLS}'; cat '${WORK}/flatpak-output'"
fake auxinux-settings "echo \"auxinux-settings \$*\" >>'${CALLS}'"
fake auxinux-center "echo \"auxinux-center\" >>'${CALLS}'"
printf '#!/bin/sh\necho refresh >>"%s"\n' "${CALLS}" >"${WORK}/helpers/auxinux-refresh-helper"
chmod +x "${WORK}/helpers/auxinux-refresh-helper"
dbus-run-session -- python3 -I "${ROOT}/tests/agent-update-harness.py" "${AGENT}" "${WORK}" || fail=1

echo "== 3. Service utilisateur =="
grep -q '^WantedBy=graphical-session.target$' "${UNIT}" && echo "  OK   WantedBy=graphical-session.target" \
  || { echo "  ECHEC WantedBy"; fail=1; }
grep -q '^ConditionKernelCommandLine=!boot=live$' "${UNIT}" && echo "  OK   pas dans le live" \
  || { echo "  ECHEC live"; fail=1; }
if command -v systemd-analyze >/dev/null; then
  # Le programme n'est pas installe ici: seules les erreurs de syntaxe comptent.
  out="$(systemd-analyze --user verify "${UNIT}" 2>&1 | grep -v 'auxinuxos-agent-update.*\(executable\|No such file\|not found\)\|bus\|XDG_RUNTIME_DIR' || true)"
  [[ -z "${out}" ]] && echo "  OK   systemd-analyze verify" || { echo "  ECHEC systemd-analyze: ${out}"; fail=1; }
fi

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
