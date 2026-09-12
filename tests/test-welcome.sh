#!/usr/bin/env bash
#
# Tests de l'ecran d'accueil live et du lanceur d'installation.
#
# POURQUOI: ces deux scripts portaient la panne rapportee le 2026-09-09 --
# « si je choisis la langue, ca quitte l'interface et reste sur un ecran
# noir ». L'accueil terminait la session utilisateur (`loginctl
# terminate-user`) pour appliquer la langue. Or la session live est ouverte
# par le bloc [initial_session] de greetd, qui ne s'applique QU'UNE FOIS, au
# demarrage: la terminer jetait l'utilisateur hors du live sans retour.
#
# Ces tests verifient qu'aucun chemin ne peut plus fermer la session, et que
# la langue choisie est bien transmise a l'installateur -- le seul effet que
# l'utilisateur attend reellement de ce choix.
#
# Usage: bash tests/test-welcome.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WELCOME="${ROOT}/packages/welcome/auxinux-welcome"
LAUNCHER="${ROOT}/packages/welcome/auxinux-install-launcher"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
STUBS="${WORK}/bin"
mkdir -p "${STUBS}"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

# Stubs: zenity repond ce qu'on lui dit, tout le reste est journalise.
cat > "${STUBS}/zenity" <<'STUB'
#!/usr/bin/env bash
printf 'zenity %s\n' "$*" >> "${STUB_LOG}"
case "$*" in
  *--list*) printf '%s\n' "${ZENITY_CHOICE:-Francais (Canada)}" ;;
esac
exit 0
STUB

for tool in loginctl systemctl dbus-update-activation-environment notify-send; do
  cat > "${STUBS}/${tool}" <<STUB
#!/usr/bin/env bash
printf '${tool} %s\n' "\$*" >> "\${STUB_LOG}"
exit 0
STUB
done
chmod +x "${STUBS}"/*

export STUB_LOG="${WORK}/stub.log"

echo "== 1. Accueil: le choix de la langue ne ferme JAMAIS la session =="
HOME_DIR="${WORK}/home-fr"; mkdir -p "${HOME_DIR}"
: > "${STUB_LOG}"
HOME="${HOME_DIR}" USER=auxinux LANG=en_US.UTF-8 \
  PATH="${STUBS}:${PATH}" bash "${WELCOME}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "aucun terminate-user" "$(grep -c 'terminate-user' "${STUB_LOG}")" "0"
check "aucune demande de redemarrage de session" \
  "$(grep -ci 'redemarrer\|restart' "${STUB_LOG}")" "0"
check "langue enregistree" "$(cat "${HOME_DIR}/.config/auxinux/language")" "fr"
check "environment.d ecrit" \
  "$(grep -c '^LANG=fr_CA.UTF-8$' "${HOME_DIR}/.config/environment.d/60-auxinux-locale.conf")" "1"
check "langue appliquee a la session en cours" \
  "$(grep -c 'import-environment' "${STUB_LOG}")" "1"
check "langue appliquee au bus de session" \
  "$(grep -c 'dbus-update-activation-environment' "${STUB_LOG}")" "1"
check "accueil marque comme vu" \
  "$([[ -s "${HOME_DIR}/.config/auxinux/welcome-seen" ]] && echo oui)" "oui"

echo "== 2. Accueil: deuxieme lancement -> ne reaffiche rien =="
: > "${STUB_LOG}"
HOME="${HOME_DIR}" USER=auxinux PATH="${STUBS}:${PATH}" bash "${WELCOME}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "aucune fenetre reouverte" "$(grep -c 'zenity' "${STUB_LOG}")" "0"

echo "== 3. Accueil: choix anglais =="
HOME_DIR="${WORK}/home-en"; mkdir -p "${HOME_DIR}"
: > "${STUB_LOG}"
HOME="${HOME_DIR}" USER=auxinux ZENITY_CHOICE="English (Canada)" \
  PATH="${STUBS}:${PATH}" bash "${WELCOME}" >/dev/null 2>&1
check "langue enregistree" "$(cat "${HOME_DIR}/.config/auxinux/language")" "en"
check "environment.d en anglais" \
  "$(grep -c '^LANG=en_CA.UTF-8$' "${HOME_DIR}/.config/environment.d/60-auxinux-locale.conf")" "1"
check "aucun terminate-user" "$(grep -c 'terminate-user' "${STUB_LOG}")" "0"

echo "== 4. Accueil: fenetre fermee sans choix -> francais, sans blocage =="
HOME_DIR="${WORK}/home-vide"; mkdir -p "${HOME_DIR}"
HOME="${HOME_DIR}" USER=auxinux ZENITY_CHOICE="" \
  PATH="${STUBS}:${PATH}" bash "${WELCOME}" >/dev/null 2>&1
check "sort en 0" "$?" "0"
check "francais par defaut" "$(cat "${HOME_DIR}/.config/auxinux/language")" "fr"

echo "== 5. Lanceur: la langue choisie est transmise a Calamares =="
# On n'execute pas le lanceur (il eleve les privileges et parle a un serveur
# X); on verifie qu'il lit bien le choix et le passe a l'installateur.
check "lit le fichier de langue" \
  "$(grep -c 'auxinux/language' "${LAUNCHER}")" "1"
check "transmet LANG a calamares" \
  "$(grep -c 'LANG="\${LANG:-fr_CA.UTF-8}"' "${LAUNCHER}")" "1"
# Le lanceur met /etc/fstab de cote avant Calamares. L'utilisateur termine
# normalement par « Redemarrer maintenant », ce qui tue le lanceur sur place:
# sans trap, la derniere ligne de restauration n'etait jamais atteinte.
check "restauration du fstab par trap" \
  "$(grep -c "trap 'restore_fstab' EXIT HUP INT TERM" "${LAUNCHER}")" "1"

echo "== 6. Lanceur: la configuration requise bloque, mais seulement sur un verdict =="
# Stubs du chemin d'elevation: sans eux, ce test deplacerait le /etc/fstab de la
# machine qui l'execute.
for tool in sudo xset xhost; do
  cat > "${STUBS}/${tool}" <<STUB
#!/usr/bin/env bash
printf '${tool} %s\n' "\$*" >> "\${STUB_LOG}"
exit 0
STUB
done
chmod +x "${STUBS}/sudo" "${STUBS}/xset" "${STUBS}/xhost"

run_launcher() {
  : > "${STUB_LOG}"
  HOME="${WORK}/home-fr" USER=auxinux PATH="${STUBS}:${PATH}" \
    bash "${LAUNCHER}" >/dev/null 2>&1
  echo "$?"
}

# a) verdict explicite de blocage: sous le minimum, on refuse AVANT d'installer.
cat > "${STUBS}/auxinux-hwcheck" <<'STUB'
#!/bin/sh
echo "INSTALLATION IMPOSSIBLE: un minimum n'est pas atteint."
exit 1
STUB
chmod +x "${STUBS}/auxinux-hwcheck"
rc="$(run_launcher)"
check "installation refusee" "${rc}" "1"
check "l'utilisateur est averti" "$(grep -c 'zenity --error' "${STUB_LOG}")" "1"
check "installateur non lance" "$(grep -c 'calamares' "${STUB_LOG}")" "0"
check "fstab non touche" "$(grep -c 'mv /etc/fstab' "${STUB_LOG}")" "0"

# b) l'outil de controle plante: SECURITE POSITIVE, l'installation continue. Un
# defaut de l'outil accessoire ne doit jamais rendre une ISO inutilisable.
cat > "${STUBS}/auxinux-hwcheck" <<'STUB'
#!/bin/sh
echo "erreur interne" >&2
exit 2
STUB
chmod +x "${STUBS}/auxinux-hwcheck"
rc="$(run_launcher)"
check "installation poursuivie malgre le plantage" "${rc}" "0"
check "installateur lance" \
  "$([[ $(grep -c 'calamares' "${STUB_LOG}") -ge 1 ]] && echo oui || echo non)" "oui"

# c) outil absent: l'installation continue aussi.
rm -f "${STUBS}/auxinux-hwcheck"
rc="$(run_launcher)"
check "installation poursuivie sans l'outil" "${rc}" "0"
check "installateur lance" \
  "$([[ $(grep -c 'calamares' "${STUB_LOG}") -ge 1 ]] && echo oui || echo non)" "oui"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
