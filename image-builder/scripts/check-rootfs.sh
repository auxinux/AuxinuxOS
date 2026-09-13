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

# TOUS les tests de fichiers passent par sudo.
#
# Le dossier personnel du compte live est en 0700 et appartient a l'UID 60000:
# un test lance par l'utilisateur de construction ne peut meme pas le
# TRAVERSER, et declarait donc « manquants » des fichiers parfaitement
# presents. Constate a la deuxieme construction de la 0.2.0, sur les reglages
# de verrouillage du live.
need_file() {
  local path="$1" why="$2"
  # `-e` suit les liens symboliques: pour display-manager.service, qui pointe
  # vers /usr/lib/systemd/system/sddm.service DANS LE ROOTFS, il resoudrait la
  # cible sur l'HOTE de build -- ou sddm n'est pas installe. Le lien correct
  # serait donc declare manquant. `-L` rattrape ce cas.
  if sudo test -e "${ROOTFS}${path}" || sudo test -L "${ROOTFS}${path}"; then ok "${path}"
  else fail "${path} — ${why}"; fi
}

need_exec() {
  local path="$1" why="$2"
  if sudo test -x "${ROOTFS}${path}"; then ok "${path}"; else fail "${path} (executable) — ${why}"; fi
}

need_any() {
  local why="$1"; shift
  local path
  for path in "$@"; do
    if sudo test -e "${ROOTFS}${path}"; then ok "${path}"; return; fi
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

refuse_file() {
  local path="$1" why="$2"
  if sudo test -e "${ROOTFS}${path}"; then
    fail "${path} present alors qu'il doit etre absent — ${why}"
  else
    ok "${path} absent"
  fi
}

need_setting() {
  local path="$1" pattern="$2" why="$3"
  if ! sudo test -f "${ROOTFS}${path}"; then
    fail "${path} — ${why}"
  elif sudo grep -qE "${pattern}" "${ROOTFS}${path}"; then
    ok "${path}: ${pattern}"
  else
    fail "${path}: '${pattern}' absent — ${why}"
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

echo "-- Installateur (Calamares)"
# La configuration de montage de Calamares est du YAML lu par un module
# Python. Deux erreurs y sont MUETTES a la construction et ne se voient qu'a
# l'ecran d'installation de l'utilisateur:
#
#   1. `options: bind` ecrit en SCALAIRE. main.py fait ",".join(options); sur
#      une chaine Python joint les caracteres et lance `mount -o b,i,n,d`,
#      qui echoue. Le module se contente d'un avertissement et l'installation
#      CONTINUE sans /dev dans la cible: grub-probe ne trouve plus aucun
#      peripherique ("failed to get canonical path of /dev/vda1") et
#      l'installation s'arrete au bootloader. Il faut `options: [ bind ]`.
#   2. Un point de montage manquant. La liste remplace les defauts compiles:
#      incomplete, elle prive le chroot de /proc, /sys, /dev ou /dev/pts.
CAL_MOUNT="${ROOTFS}/etc/calamares/modules/mount.conf"
if [[ ! -f "${CAL_MOUNT}" ]]; then
  fail "/etc/calamares/modules/mount.conf — Calamares n'aurait aucun extraMounts"
else
  bad_opts="$(grep -nE '^[[:space:]]*options:[[:space:]]*[^[:space:]]' "${CAL_MOUNT}" \
              | grep -vE 'options:[[:space:]]*\[' || true)"
  if [[ -n "${bad_opts}" ]]; then
    fail "mount.conf: options en scalaire au lieu d'une liste — ${bad_opts//$'\n'/ ; }"
  else
    ok "mount.conf: chaque options est une liste YAML"
  fi

  for mp in /proc /sys /dev /dev/pts /run; do
    if grep -qE "^[[:space:]]*mountPoint:[[:space:]]*${mp}[[:space:]]*\$" "${CAL_MOUNT}"; then
      ok "mount.conf: ${mp} monte dans la cible"
    else
      fail "mount.conf: ${mp} absent — les modules chrootes (bootloader, initramfs) echoueraient"
    fi
  done

  # `extraMountsEfi` n'existe pas dans ce module: elle est ignoree en silence,
  # donc efivarfs ne serait jamais monte et grub-install ne pourrait pas
  # enregistrer l'entree NVRAM d'une installation UEFI.
  if grep -qE '^[[:space:]]*extraMountsEfi:' "${CAL_MOUNT}"; then
    fail "mount.conf: cle extraMountsEfi ignoree par Calamares — utiliser 'efi: true' sur l'entree"
  else
    ok "mount.conf: pas de cle extraMountsEfi"
  fi
fi

echo "-- Instantane avant transaction DEB"
need_exec /usr/lib/auxinux/apt-snapshot-hook "la promesse d'un instantane avant chaque transaction ne serait pas tenue"
need_file /etc/apt/apt.conf.d/80auxinux-snapshot "le hook ne serait jamais appele par dpkg"

echo "-- Outils AuxiNux"
need_exec /usr/bin/auxi "commande d'administration principale"
need_exec /usr/bin/auxinux-center "centre de controle"
need_exec /usr/libexec/auxinux/auxinux-source-helper "l'ajout de depot depuis le centre echouerait"
need_file /usr/share/polkit-1/actions/ca.auxinux.center.policy "l'assistant privilegie n'aurait pas d'action polkit"
need_exec /usr/lib/auxinux/post-install-cleanup.sh "les artefacts du live resteraient sur le systeme installe"
need_exec /usr/lib/auxinux/verify-installed-boot.sh "une installation produisant un noyau illisible s'annoncerait reussie"
need_exec /usr/lib/auxinux/wrappers/apt-wrapper "la politique APT ne serait pas appliquee"

echo "-- Assistants graphiques"
need_package zenity "les assistants (accueil live, .exe) n'afficheraient aucune fenetre"
need_package kdialog "boites de dialogue natives pour les scripts KDE"
need_exec /usr/bin/auxinux-welcome "premier ecran de la session live"
need_exec /usr/bin/auxinux-windows-wizard "ouverture des fichiers .exe"
need_exec /usr/bin/auxinux-windows-setup "installation de la couche Windows et jeux"

echo "-- Bureau et session (KDE Plasma / Wayland)"
need_exec /usr/bin/startplasma-wayland "le bureau ne demarrerait pas"
need_exec /usr/bin/plasmashell "aucun panneau ni bureau"
need_exec /usr/bin/kwin_wayland "aucun compositeur Wayland"
need_exec /usr/bin/systemsettings "le centre de controle renvoie vers les reglages de Plasma"
need_package libgl1-mesa-dri "serveur graphique SANS pilote DRI: KWin ne demarre pas (ce paquet n'est qu'un Recommends)"
need_package login "PAM sans /etc/pam.d/login: la pile d'authentification du greeter echoue"

echo "-- Ecran de connexion (SDDM)"
need_exec /usr/bin/sddm "aucun gestionnaire de session: le systeme s'arrete sur une console"
need_file /etc/pam.d/sddm "SDDM refuse d'ouvrir une session sans son service PAM"
need_file /etc/pam.d/sddm-autologin "l'autologin du live echouerait faute de service PAM"
need_file /etc/sddm.conf.d/10-auxinux.conf "theme et bornes d'UID de l'ecran de connexion"
need_file /etc/systemd/system/display-manager.service "graphical.target n'aurait aucun gestionnaire d'affichage a demarrer"
need_file /etc/systemd/system/sddm.service.d/50-auxinux-fallback.conf \
  "aucune console de secours si l'ecran de connexion echoue, et le mode secours ne pourrait pas prendre la main"

# LE controle qui compte: la session nommee dans l'autologin doit EXISTER.
# Une valeur erronee (« plasma-wayland », « plasmawayland », un nom change en
# amont) ne produit aucune erreur de construction: le live demarre, SDDM tente
# d'ouvrir une session inexistante, echoue en boucle, et l'utilisateur voit un
# ecran noir. C'est la meme famille de panne que le greeter de la 0.1.
AUTOLOGIN="${ROOTFS}/etc/sddm.conf.d/90-auxinux-live-autologin.conf"
if [[ ! -f "${AUTOLOGIN}" ]]; then
  fail "/etc/sddm.conf.d/90-auxinux-live-autologin.conf — le live demanderait un mot de passe inconnu de l'utilisateur"
else
  ok "/etc/sddm.conf.d/90-auxinux-live-autologin.conf"
  session="$(awk -F= '/^Session=/{gsub(/[[:space:]]/,"",$2); print $2}' "${AUTOLOGIN}" | tail -n1)"
  session="${session%.desktop}"
  if [[ -z "${session}" ]]; then
    fail "autologin live: aucune cle Session= — SDDM ouvrirait sa session par defaut, pas forcement Wayland"
  elif [[ -f "${ROOTFS}/usr/share/wayland-sessions/${session}.desktop" ]]; then
    ok "autologin live: session Wayland '${session}' presente"
  elif [[ -f "${ROOTFS}/usr/share/xsessions/${session}.desktop" ]]; then
    fail "autologin live: '${session}' n'existe qu'en X11 — tout le live basculerait en X11 sans que rien ne le signale"
  else
    fail "autologin live: session '${session}' INTROUVABLE — ecran noir au demarrage du live"
  fi
  autologin_user="$(awk -F= '/^User=/{gsub(/[[:space:]]/,"",$2); print $2}' "${AUTOLOGIN}" | tail -n1)"
  if [[ "${autologin_user}" == "auxinux" ]]; then
    ok "autologin live: compte 'auxinux'"
  else
    fail "autologin live: compte '${autologin_user:-absent}' au lieu de 'auxinux'"
  fi
fi

echo "-- Protection au demarrage"
need_exec /usr/lib/auxinux/auxinux-boot-sentinel "rien ne detecterait un demarrage qui n'aboutit pas au bureau"
need_exec /usr/lib/auxinux/auxinux-rescue "aucune console de secours ni restauration automatique"
for unit in auxinux-boot-arm.service auxinux-boot-sentinel.service auxinux-rescue.service; do
  need_file "/etc/systemd/system/${unit}" "unite de la protection au demarrage absente"
  # La PRESENCE du fichier d'unite ne suffit pas: auxinux-rescue.service a ete
  # livre une fois installe mais non active, donc la console de secours
  # n'aurait jamais demarre -- la protection se serait arretee a « le bureau ne
  # demarre pas », sans rien proposer.
  need_file "/etc/systemd/system/graphical.target.wants/${unit}" \
    "unite presente mais NON ACTIVEE: elle ne demarrera jamais"
done
need_file /etc/systemd/system/multi-user.target.wants/auxinux-profile.service \
  "le profil d'usage ne serait pas reapplique au demarrage"

echo "-- Profil d'usage"
need_exec /usr/bin/auxinux-hwcheck "le lanceur d'installation ne pourrait pas verifier la configuration requise"
need_exec /usr/bin/auxinux-profile "aucun reglage par usage (bureautique / multimedia / jeu)"
need_file /etc/auxinux/profile "auxinux-profile.service ne demarrerait pas (ConditionPathExists)"
need_file /etc/systemd/system/auxinux-profile.service "le profil serait perdu a chaque redemarrage"

echo "-- Vie privee (loi 25)"
need_setting /etc/xdg/PlasmaUserFeedback '^FeedbackLevel=0' \
  "la telemetrie de Plasma ne serait pas explicitement neutralisee"
need_setting /etc/xdg/kdeglobals 'StatisticsCollectionMode=NoTelemetry' \
  "les applications KDE qui lisent leur propre section pourraient collecter"
need_setting /etc/xdg/baloofilerc '^Indexing-Enabled=false' \
  "l'indexeur copierait le texte de tous les documents dans une base non chiffree"
need_setting /etc/xdg/kscreenlockerrc '^Autolock=true' \
  "un poste non verrouille est le premier trou de confidentialite"

echo "-- Materiel portable"
# Ces micrologiciels ne produisent AUCUN message quand ils manquent: la machine
# n'a simplement pas de son, ou pas de WiFi. Sur un portable, c'est la
# difference entre un systeme utilisable et un systeme qu'on desinstalle.
need_package firmware-sof-signed "AUCUN son sur la plupart des portables Intel/AMD depuis 2019"
need_package firmware-cirrus "haut-parleurs muets sur beaucoup de Dell/HP/Lenovo recents"
need_package firmware-mediatek "pas de WiFi du tout sur les portables AMD a MT7921/MT7922"
need_package firmware-iwlwifi "pas de WiFi sur les portables Intel"
need_file /lib/firmware/intel/sof "le paquet est la mais les blobs SOF manquent"

echo "-- Fluidite"
# Controle ajoute apres coup: `systemctl enable systemd-oomd.service` echouait
# avec un simple avertissement parce que le PAQUET n'etait pas installe (dans
# Debian 13, systemd-oomd est separe de systemd). L'image promettait donc une
# protection contre le gel memoire qu'elle n'avait pas, et seul le journal de
# construction le disait -- noye dans 20 000 lignes.
need_package systemd-oomd "gel total garanti quand la memoire sature: l'unite n'existe meme pas"
need_file /usr/lib/systemd/system/systemd-oomd.service "le paquet est la mais l'unite manque"
need_file /etc/systemd/system/multi-user.target.wants/systemd-oomd.service \
  "systemd-oomd installe mais NON ACTIVE: il ne protegera rien"
need_package zram-tools "pas d'echange compresse en RAM"
need_file /etc/systemd/system/multi-user.target.wants/zramswap.service "zram installe mais non active"

echo "-- Demarrage observable"
# `quiet` masque noyau ET systemd; sans plymouth (absent de l'image) `splash`
# est inerte. Les deux reunis transforment n'importe quelle panne de session en
# ecran noir muet, impossible a diagnostiquer pour l'utilisateur.
for grub_file in /etc/default/grub /etc/calamares/modules/grubcfg.conf; do
  if [[ -f "${ROOTFS}${grub_file}" ]] &&
     grep -qE '^[^#]*GRUB_CMDLINE_LINUX_DEFAULT.*(quiet|splash)' "${ROOTFS}${grub_file}"; then
    fail "${grub_file}: 'quiet'/'splash' actif alors que plymouth est absent — un demarrage en echec n'afficherait rien"
  else
    ok "${grub_file}: demarrage bavard"
  fi
done

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
refuse_file /etc/apt/sources.list.d/obs-cosmic.sources "depot tiers OBS, abandonne avec COSMIC"
# Un rootfs REUTILISE (--reuse-rootfs) vient peut-etre d'une image COSMIC. Ces
# fichiers n'appartiennent a aucun paquet (ils etaient copies par
# build-cosmic-source.sh): dpkg ne les enlevera jamais, et un bureau fantome
# resterait selectionnable a l'ecran de connexion.
refuse_file /usr/bin/cosmic-session "reste d'une image COSMIC: relancer la construction sans --reuse-rootfs"
refuse_file /usr/bin/cosmic-comp "reste d'une image COSMIC: relancer la construction sans --reuse-rootfs"
refuse_file /etc/greetd/cosmic-greeter.toml "reste de l'ancien gestionnaire de session"
# Ecartes par arbitrage: Discover ramene PackageKit (un second chemin vers
# dpkg, deja retire) et duplique le centre de controle; plasma-welcome va
# chercher du contenu en ligne.
refuse_package plasma-discover "double du centre de controle et ramene PackageKit"
refuse_package plasma-welcome "recupere du contenu en ligne au premier demarrage"

echo "-- Session live: rien qui ressemble a un ecran noir"
# Le live ne doit NI se verrouiller NI eteindre l'ecran: un visiteur qui laisse
# la machine deux minutes revenait devant un ecran noir, puis un mot de passe
# qu'il n'a jamais choisi. Constate sur le premier essai VM de la 0.2.0.
need_setting /home/auxinux/.config/kscreenlockerrc '^Autolock=false' \
  "le live se verrouillerait apres dix minutes"
need_setting /home/auxinux/.config/powermanagementprofilesrc 'idleTime=86400' \
  "l'ecran du live s'eteindrait apres dix minutes"
# Et le systeme INSTALLE, lui, doit garder le verrouillage: la surcharge doit
# rester locale au compte live, jamais dans /etc/xdg.
need_setting /etc/xdg/kscreenlockerrc '^Autolock=true' \
  "le systeme installe ne se verrouillerait plus"
refuse_file /etc/xdg/autostart/auxinux-install.desktop \
  "l'installateur s'ouvrirait par-dessus l'ecran d'accueil, deux fenetres empilees"

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
