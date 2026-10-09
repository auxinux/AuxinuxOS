#!/usr/bin/env bash
#
# Audit « aucune telemetrie » — controle STATIQUE de l'image.
#
# POURQUOI: la promesse d'AuxiNuxOS (loi 25 quebecoise: aucune collecte, aucun
# echange avec un tiers sans consentement) est aujourd'hui une phrase dans un
# fichier de documentation. Ce test la transforme en controle executable: si
# quelqu'un ajoute un paquet qui rapporte des donnees, ou si une mise a jour de
# Plasma change un defaut, le test echoue au lieu que personne ne s'en
# apercoive.
#
# CE QUE CE TEST NE FAIT PAS: il ne regarde AUCUN trafic reseau. Un audit
# complet demande de demarrer l'image en VM avec capture du trafic et de
# refuser toute destination hors liste blanche. C'est le prolongement naturel
# de ce fichier, pas son contenu actuel -- et il ne faut pas croire cette
# verification plus forte qu'elle n'est.
#
# Usage: bash tests/test-no-telemetry.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAYS="${ROOT}/image-builder/overlays"
# Reglages du systeme installe: dans le paquet auxinuxos-release depuis le
# 2026-10-09 (ils arrivent aussi par la mise a jour).
RELEASE_ROOT="${ROOT}/packages/release/root"
LISTS="${ROOT}/image-builder/package-lists"

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}
setting() {
  local label="$1" file="$2" pattern="$3"
  if [[ ! -f "${file}" ]]; then echo "  ECHEC ${label}: ${file#${ROOT}/} absent"; fail=1; return; fi
  if grep -qE "${pattern}" "${file}"; then echo "  OK   ${label}"
  else echo "  ECHEC ${label}: '${pattern}' absent de ${file#${ROOT}/}"; fail=1; fi
}

echo "== 1. Telemetrie du bureau (KDE) =="
setting "Plasma: FeedbackLevel=0" "${RELEASE_ROOT}/etc/xdg/PlasmaUserFeedback" '^FeedbackLevel=0'
setting "Applications KDE: NoTelemetry" "${RELEASE_ROOT}/etc/xdg/kdeglobals" 'StatisticsCollectionMode=NoTelemetry'

echo "== 2. Indexation locale du contenu des documents =="
setting "Baloo desactive" "${RELEASE_ROOT}/etc/xdg/baloofilerc" '^Indexing-Enabled=false'

echo "== 3. Navigateur =="
BRAVE="${RELEASE_ROOT}/etc/brave/policies/managed/auxinux-privacy.json"
for key in MetricsReportingEnabled BraveRewardsDisabled BraveWalletDisabled BraveVPNDisabled SyncDisabled; do
  setting "Brave: ${key} sous politique" "${BRAVE}" "\"${key}\""
done

echo "== 4. Paquets qui rapportent des donnees ou ouvrent un service reseau =="
# popularity-contest envoie la liste des paquets installes a Debian chaque
# semaine. Il n'est pas installe par defaut, mais il suffit qu'un jour
# quelqu'un ajoute `task-*` ou `standard` pour qu'il arrive sans bruit.
# kdeconnect ouvre un service a l'ecoute sur le reseau local.
for pkg in popularity-contest whoopsie apport ubuntu-report kdeconnect \
           plasma-browser-integration plasma-welcome plasma-discover packagekit \
           zeitgeist-core; do
  hits="$(grep -rlE "^[[:space:]]*${pkg}[[:space:]]*$" "${LISTS}" 2>/dev/null || true)"
  check "${pkg} absent des listes" "$([[ -z "${hits}" ]] && echo absent || echo "${hits}")" "absent"
done

echo "== 5. Rien ne part en arriere-plan sans action de l'utilisateur =="
BUILD="${ROOT}/image-builder/build-image.sh"
check "minuteries apt masquees" \
  "$(grep -c 'apt-daily.timer apt-daily-upgrade.timer' "${BUILD}")" "1"
check "tor non demarre au boot" \
  "$(grep -c 'multi-user.target.wants/tor.service' "${BUILD}")" "1"
# Flathub est un tiers: la recherche d'applications l'interroge, donc son IP
# est exposee des que l'utilisateur cherche une application. C'est un acte
# volontaire de l'utilisateur, pas une collecte -- mais la remote ne doit pas
# etre interrogee AU DEMARRAGE. On verifie qu'aucun minuteur de mise a jour
# Flatpak n'est active.
check "aucune mise a jour Flatpak automatique" \
  "$(grep -rc 'flatpak-update.timer' "${ROOT}/image-builder" 2>/dev/null | grep -v ':0$' | wc -l)" "0"

echo "== 6. Verrouillage de l'ecran (confidentialite physique) =="
setting "verrouillage automatique actif" "${RELEASE_ROOT}/etc/xdg/kscreenlockerrc" '^Autolock=true'

echo "== 7. Destinations reseau decidees (docs/privacy-stance.md) =="
# NTP contacte un tiers a chaque demarrage. La destination a ete choisie le
# 2026-10-05 (CNRC, pool Debian en secours): la changer doit etre un acte
# visible, pas une ligne modifiee en passant.
TIMESYNCD="${RELEASE_ROOT}/etc/systemd/timesyncd.conf.d/50-auxinux.conf"
setting "NTP: serveurs du CNRC" "${TIMESYNCD}" '^NTP=time\.nrc\.ca time\.chu\.nrc\.ca$'
setting "NTP: secours limite au pool Debian" "${TIMESYNCD}" '^FallbackNTP=([0-3]\.debian\.pool\.ntp\.org ?)+$'

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; fi
exit "${fail}"
