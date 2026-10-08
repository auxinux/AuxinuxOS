#!/usr/bin/env bash
#
# auxinux-user-dirs: dossiers personnels standard.
#
# PANNE A L'ORIGINE (2026-10-08): le compte n'avait que ~/Desktop; sans
# ~/.config/user-dirs.dirs ni ~/Downloads, Firefox (Flatpak) telechargeait
# dans son bac a sable, ou l'utilisateur ne retrouvait rien.
#
# Usage: bash tests/test-user-dirs.sh
set -uo pipefail

SCRIPT="${SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/user-dirs/auxinux-user-dirs}"
[[ -x "${SCRIPT}" ]] || { echo "script introuvable: ${SCRIPT}" >&2; exit 66; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

echo "== 1. Compte vierge (le cas rapporte: seulement ~/Desktop) =="
H="${WORK}/vierge"; mkdir -p "${H}/Desktop"
HOME="${H}" "${SCRIPT}"
check "sort en 0" "$?" "0"
for d in Desktop Downloads Documents Music Pictures Videos Templates Public; do
  check "~/${d} existe" "$([[ -d ${H}/${d} ]] && echo oui)" "oui"
done
check "XDG_DOWNLOAD_DIR declare" "$(grep -c '^XDG_DOWNLOAD_DIR="\$HOME/Downloads"$' "${H}/.config/user-dirs.dirs")" "1"
check "bureau inchange: ~/Desktop" "$(grep -c '^XDG_DESKTOP_DIR="\$HOME/Desktop"$' "${H}/.config/user-dirs.dirs")" "1"
check "langue des noms figee" "$(cat "${H}/.config/user-dirs.locale")" "en_US"

echo "== 2. Idempotent: rien n'est reecrit =="
printf '# modifie\n' >> "${H}/.config/user-dirs.dirs"
HOME="${H}" "${SCRIPT}"
check "user-dirs.dirs garde la modification" "$(tail -n1 "${H}/.config/user-dirs.dirs")" "# modifie"

echo "== 3. Configuration existante en francais: respectee =="
H="${WORK}/fr"; mkdir -p "${H}/.config"
cat > "${H}/.config/user-dirs.dirs" <<'DIRS'
XDG_DESKTOP_DIR="$HOME/Bureau"
XDG_DOWNLOAD_DIR="$HOME/Téléchargements"
XDG_PUBLICSHARE_DIR="$HOME/"
DIRS
HOME="${H}" "${SCRIPT}"
check "Téléchargements cree" "$([[ -d ${H}/Téléchargements ]] && echo oui)" "oui"
check "Bureau cree" "$([[ -d ${H}/Bureau ]] && echo oui)" "oui"
check "aucun Downloads anglais ajoute" "$([[ -e ${H}/Downloads ]] && echo present || echo absent)" "absent"
check "dossier desactive (\$HOME) laisse tel quel" "$(grep -c 'XDG_PUBLICSHARE_DIR="\$HOME/"' "${H}/.config/user-dirs.dirs")" "1"

echo "== 4. Construction de l'image: dossier explicite (/etc/skel) =="
S="${WORK}/skel"; mkdir -p "${S}"
HOME="${WORK}/autre" "${SCRIPT}" "${S}"
check "sort en 0" "$?" "0"
check "skel/Downloads" "$([[ -d ${S}/Downloads ]] && echo oui)" "oui"
check "le \$HOME litteral est garde (copie par useradd)" "$(grep -c '\$HOME/Documents' "${S}/.config/user-dirs.dirs")" "1"

echo "== 5. Dossier absent: erreur =="
"${SCRIPT}" "${WORK}/nexiste-pas" 2>/dev/null
check "sort en 66" "$?" "66"

echo
if [[ "${fail}" == "0" ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; exit 1; fi
