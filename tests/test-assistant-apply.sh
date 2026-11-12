#!/usr/bin/env bash
#
# auxinux-assistant-apply: ce que l'assistant de premier demarrage execute en
# root pour installer la selection.
#
# auxi et auxinux-profile sont remplaces par des stubs qui consignent leurs
# appels (AUXINUX_ASSISTANT_TEST_ROOT, honore hors root seulement). Cas
# critiques: une application indisponible ne doit pas priver la personne des
# autres, et un identifiant commencant par un tiret ne doit jamais atteindre
# apt ou flatpak, ou il serait lu comme une option.
#
# Usage: bash tests/test-assistant-apply.sh
set -uo pipefail

HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/auxinux-center/helper/auxinux-assistant-apply"
if [[ "${EUID}" -eq 0 ]]; then
  echo "a lancer SANS root: en root, le helper ignore les stubs (c'est voulu)" >&2
  exit 77
fi

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
export AUXINUX_ASSISTANT_TEST_ROOT="${T}"
CALLS="${T}/calls"
mkdir -p "${T}/sources.list.d"

cat >"${T}/auxi" <<STUB
#!/usr/bin/env bash
echo "auxi \$*" >>"${CALLS}"
# Simule une application Flatpak indisponible sur Flathub.
[[ " \$* " == *" org.absent.App "* ]] && { echo "error: org.absent.App not found" >&2; exit 1; }
exit 0
STUB
cat >"${T}/auxinux-profile" <<STUB
#!/usr/bin/env bash
echo "auxinux-profile \$*" >>"${CALLS}"
STUB
chmod +x "${T}/auxi" "${T}/auxinux-profile"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
reset() { : >"${CALLS}"; }

echo "== 1. Selection complete, avec Brave (Flatpak depuis le 2026-10-29) =="
reset
out="$(bash "${HELPER}" --profil gaming --flatpak com.brave.Browser --flatpak org.mozilla.Thunderbird --flatpak com.usebottles.bottles 2>&1)"
check "code de sortie" "$?" "0"
check "quatre etapes annoncees" "$(grep -c '^auxinux-etape:' <<<"${out}")" "4"
check "premiere etape" "$(grep -m1 '^auxinux-etape:' <<<"${out}")" "auxinux-etape:1:4:Profil d'usage: gaming"
check "profil applique" "$(grep -c '^auxinux-profile set gaming$' "${CALLS}")" "1"
check "Brave installe en Flatpak" "$(grep -c 'install --flatpak com.brave.Browser' "${CALLS}")" "1"
check "un appel par Flatpak" "$(grep -c 'install --flatpak' "${CALLS}")" "3"
check "aucun appel apt" "$(grep -c -- '--deb' "${CALLS}")" "0"

echo "== 2. L'ancienne option --brave (depot DEB) est refusee =="
reset
bash "${HELPER}" --brave >/dev/null 2>&1
check "--brave refuse" "$?" "64"
check "rien n'a ete execute" "$(wc -l <"${CALLS}" | tr -d ' ')" "0"
reset
bash "${HELPER}" --deb vlc >/dev/null 2>&1
check "--deb: code de sortie" "$?" "0"
check "--deb: index rafraichis AVANT l'installation" "$(sed -n 1p "${CALLS}")" "auxi --yes --progress update --deb"
check "--deb: paquet installe" "$(sed -n 2p "${CALLS}")" "auxi --yes --progress install --deb vlc"

echo "== 3. Une application indisponible n'emporte pas les autres =="
reset
out="$(bash "${HELPER}" --flatpak org.absent.App --flatpak org.videolan.VLC 2>&1)"
check "echec rendu" "$?" "1"
check "la suivante est quand meme installee" "$(grep -c 'install --flatpak org.videolan.VLC' "${CALLS}")" "1"
check "l'echec est nomme" "$(grep -c 'Échec pour: org.absent.App' <<<"${out}")" "1"

echo "== 4. Arguments refuses AVANT toute action =="
reset
bash "${HELPER}" --flatpak --force-everything >/dev/null 2>&1
check "tiret initial refuse" "$?" "64"
bash "${HELPER}" --profil root >/dev/null 2>&1
check "profil inconnu refuse" "$?" "64"
bash "${HELPER}" --deb 'vlc;rm' >/dev/null 2>&1
check "caractere hors liste refuse" "$?" "64"
check "rien n'a ete execute" "$(wc -l <"${CALLS}" | tr -d ' ')" "0"

echo "== 5. Rien a faire =="
reset
check "sans argument" "$(bash "${HELPER}" 2>&1)" "Rien à installer."

if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "ECHEC"; fi
exit "${fail}"
