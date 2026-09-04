#!/usr/bin/env bash
set -uo pipefail

# Verification du rootfs juste avant la compression en squashfs.
#
# POURQUOI CE SCRIPT EXISTE: le defaut le plus couteux rencontre sur ce projet
# ne produisait AUCUN message. Le rollback n'etait configure sur aucun systeme
# installe parce qu'un fichier attendu a un endroit se trouvait a un autre; la
# construction reussissait, l'ISO demarrait, et la panne n'apparaissait que le
# jour ou l'utilisateur avait besoin de restaurer. Le cache de paquets a
# produit le meme genre d'ISO amputee, silencieusement.
#
# Chaque controle ci-dessous correspond a une fonction annoncee a
# l'utilisateur. Un echec ARRETE la construction: mieux vaut pas d'ISO qu'une
# ISO dont on croit a tort qu'elle sait restaurer le systeme.
#
# Usage: check-rootfs.sh ROOTFS_DIR

ROOTFS="${1:?usage: check-rootfs.sh ROOTFS}"

FAILURES=0

fail() {
  echo "  MANQUE  $*" >&2
  FAILURES=$((FAILURES + 1))
}

ok() {
  echo "  ok      $*"
}

need_file() {
  local path="$1" why="$2"
  if [[ -e "${ROOTFS}${path}" ]]; then ok "${path}"; else fail "${path} — ${why}"; fi
}

need_exec() {
  local path="$1" why="$2"
  if [[ -x "${ROOTFS}${path}" ]]; then ok "${path}"; else fail "${path} (executable) — ${why}"; fi
}

need_any() {
  local why="$1"; shift
  local path
  for path in "$@"; do
    if [[ -e "${ROOTFS}${path}" ]]; then ok "${path}"; return; fi
  done
  fail "aucun de: $* — ${why}"
}

need_package() {
  local pkg="$1" why="$2"
  if sudo chroot "${ROOTFS}" dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null \
      | grep -q "install ok installed"; then
    ok "paquet ${pkg}"
  else
    fail "paquet ${pkg} — ${why}"
  fi
}

refuse_package() {
  local pkg="$1" why="$2"
  if sudo chroot "${ROOTFS}" dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null \
      | grep -q "install ok installed"; then
    fail "paquet ${pkg} present alors qu'il doit etre absent — ${why}"
  else
    ok "paquet ${pkg} absent"
  fi
}

echo "==> Verification du rootfs"

echo "-- Restauration systeme"
need_any "sans modele, setup-btrfs-rollback.sh ne peut pas configurer snapper a l'installation" \
  /usr/share/snapper/config-templates/default \
  /etc/snapper/config-templates/default
need_package snapper "pas d'instantanes, donc pas de restauration"
need_package btrfs-progs "Calamares ne peut pas formater la cible en BTRFS"
need_file /etc/grub.d/41_snapshots-btrfs "pas de sous-menu GRUB: restauration impossible quand le systeme ne demarre plus"
need_exec /usr/bin/grub-btrfsd "le menu de restauration ne serait jamais mis a jour"
need_exec /usr/lib/auxinux/setup-btrfs-rollback.sh "le rollback ne serait pas configure a l'installation"
need_exec /etc/initramfs-tools/scripts/local-bottom/auxinux-snapshot-overlay \
  "un instantane demarre depuis GRUB resterait en lecture seule et n'aboutirait pas"
need_exec /etc/initramfs-tools/hooks/auxinux-snapshot-overlay \
  "le module overlay serait absent de l'initramfs"

echo "-- Instantane avant transaction DEB"
need_exec /usr/lib/auxinux/apt-snapshot-hook "la promesse d'un instantane avant chaque transaction ne serait pas tenue"
need_file /etc/apt/apt.conf.d/80auxinux-snapshot "le hook ne serait jamais appele par dpkg"

echo "-- Outils AuxiNux"
need_exec /usr/bin/auxi "commande d'administration principale"
need_exec /usr/bin/auxinux-center "centre de controle"
need_exec /usr/libexec/auxinux/auxinux-source-helper "l'ajout de depot depuis le centre echouerait"
need_file /usr/share/polkit-1/actions/ca.auxinux.center.policy "l'assistant privilegie n'aurait pas d'action polkit"
need_exec /usr/lib/auxinux/post-install-cleanup.sh "les artefacts du live resteraient sur le systeme installe"
need_exec /usr/lib/auxinux/wrappers/apt-wrapper "la politique APT ne serait pas appliquee"

echo "-- Assistants graphiques"
need_package zenity "les assistants (accueil live, .exe) n'afficheraient aucune fenetre"
need_exec /usr/bin/auxinux-welcome "premier ecran de la session live"
need_exec /usr/bin/auxinux-windows-wizard "ouverture des fichiers .exe"
need_exec /usr/bin/auxinux-windows-setup "installation de la couche Windows et jeux"

echo "-- Bureau et session"
need_exec /usr/bin/cosmic-session "le bureau ne demarrerait pas"
need_exec /usr/bin/cosmic-comp "aucun compositeur"
need_file /etc/greetd/cosmic-greeter.toml "aucun gestionnaire de session"
need_package login "PAM sans /etc/pam.d/login: greetd boucle et l'ecran reste noir"

echo "-- Couche Windows"
if sudo chroot "${ROOTFS}" dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
  ok "architecture i386"
else
  fail "architecture i386 — wine32 absent, donc aucune application Windows 32 bits"
fi
need_package wine "couche de compatibilite Windows"

echo "-- Politique APT"
if [[ -L "${ROOTFS}/usr/bin/apt-get" ]]; then
  ok "/usr/bin/apt-get detourne vers le wrapper"
else
  fail "/usr/bin/apt-get non detourne — la politique APT serait inactive"
fi
if [[ -L "${ROOTFS}/usr/bin/apt-cache" ]]; then
  fail "/usr/bin/apt-cache detourne — commande de lecture seule, elle ne doit pas l'etre"
else
  ok "/usr/bin/apt-cache non detourne"
fi
need_exec /usr/lib/auxinux/apt-real/apt-get "le vrai binaire APT est introuvable: auxi ne fonctionnerait pas"

echo "-- Ce qui doit avoir disparu"
refuse_package q4wine "interface abandonnee en amont, remplacee par Bottles"
refuse_package packagekit "chemin vers dpkg parallele, retire de l'image"
if [[ -e "${ROOTFS}/etc/apt/sources.list.d/obs-cosmic.sources" ]]; then
  fail "le depot OBS COSMIC est reste active sur le systeme livre"
else
  ok "depot OBS COSMIC retire"
fi

echo "-- Compte live"
live_uid="$(sudo chroot "${ROOTFS}" id -u auxinux 2>/dev/null || true)"
if [[ "${live_uid}" == "60000" ]]; then
  ok "compte live a l'UID 60000"
else
  fail "compte live a l'UID '${live_uid:-absent}' au lieu de 60000 — le compte cree par Calamares heriterait d'un UID decale"
fi

echo
if [[ "${FAILURES}" -gt 0 ]]; then
  echo "Verification du rootfs: ${FAILURES} manque(s). Construction interrompue." >&2
  exit 70
fi
echo "Verification du rootfs: tout est en place."
