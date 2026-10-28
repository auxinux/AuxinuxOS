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

# Architecture de l'image (exportee par build-image.sh). amd64: UEFI + BIOS et
# couche Windows. arm64 (Edition ARM): UEFI seulement, sans couche Windows ni
# paquet i386.
ARCH="${AUXINUX_ARCH:-$(dpkg --print-architecture 2>/dev/null || echo amd64)}"
PACKAGE_NAMES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package-names.sh"

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

# Le fichier appartient-il au paquet attendu? Un fichier copie a la main par
# un script de construction ne recevrait aucune mise a jour.
need_owned() {
  local path="$1" pkg="$2" why="$3"
  if sudo chroot "${ROOTFS}" dpkg-query -S "${path}" 2>/dev/null | grep -q "^${pkg}: ${path}$"; then
    ok "${path} (paquet ${pkg})"
  else
    fail "${path} n'appartient pas au paquet ${pkg} — ${why}"
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
  # -L aussi: un lien vers un chemin absolu du rootfs se resoudrait sur l'HOTE,
  # et un lien bien present serait declare absent.
  if sudo test -e "${ROOTFS}${path}" || sudo test -L "${ROOTFS}${path}"; then
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

  # Les sous-volumes BTRFS sont crees par le module `mount`, a partir de SA
  # configuration. Ecrite ailleurs, la liste est ignoree et Calamares retombe
  # sur @ et @home: pas de @snapshots, donc aucun instantane possible sur le
  # systeme installe. C'est ce qu'ont livre toutes les ISO jusqu'au 2026-09-29.
  subvols="$(awk '
    /^btrfsSubvolumes:/ { inblk = 1; next }
    inblk && /^[^[:space:]#]/ { inblk = 0 }
    inblk && /mountPoint:/ { mp = $NF }
    inblk && /subvolume:/ { print mp " " $NF }
  ' "${CAL_MOUNT}")"
  for pair in "/ /@" "/home /@home" "/.snapshots /@snapshots" "/var/log /@var_log" \
              "/var/cache /@var_cache" "/var/tmp /@var_tmp" \
              "/var/lib/flatpak /@var_lib_flatpak"; do
    if grep -qxF "${pair}" <<<"${subvols}"; then
      ok "mount.conf: sous-volume ${pair#* } sur ${pair% *}"
    else
      fail "mount.conf: sous-volume '${pair#* }' sur '${pair% *}' absent de btrfsSubvolumes — ce qui n'est pas cree ici n'existe pas sur le systeme installe"
    fi
  done
  # /swap est AJOUTE par le module quand l'utilisateur choisit un fichier
  # d'echange. Liste ici aussi, @swap serait cree deux fois et le second
  # `btrfs subvolume create` ferait echouer l'installation.
  if grep -qE '^/swap ' <<<"${subvols}"; then
    fail "mount.conf: /swap dans btrfsSubvolumes — Calamares l'ajoute deja lui-meme, l'installation echouerait"
  else
    ok "mount.conf: /swap laisse a Calamares"
  fi
fi

# Zone par defaut: sans elle, Calamares part de New York, en deduit fr_FR et
# propose l'AZERTY de France -- applique aussitot a la saisie du mot de passe.
need_setting /etc/calamares/modules/locale.conf '^zone:[[:space:]]*"?Toronto"?' \
  "Calamares proposerait fr_FR, des nombres americains et un clavier AZERTY"
# Sans ckbcomp, l'apercu du clavier est vide: l'utilisateur ne voit pas quelle
# disposition il valide. console-setup le fournit, et regle la console texte.
need_exec /usr/bin/ckbcomp "apercu du clavier vide dans l'installateur (paquet console-setup)"

# Des cles de sous-volumes dans partition.conf n'ont AUCUN effet: ce module ne
# les lit pas. Les y laisser, c'est faire croire a une disposition que le
# systeme installe n'aura pas.
CAL_PART="${ROOTFS}/etc/calamares/modules/partition.conf"
if [[ -f "${CAL_PART}" ]] && grep -qE '^[[:space:]]*btrfs(Subvolumes|SwapSubvol):' "${CAL_PART}"; then
  fail "partition.conf: btrfsSubvolumes/btrfsSwapSubvol ignores par ce module — les declarer dans mount.conf"
else
  ok "partition.conf: aucune cle de sous-volume trompeuse"
fi

echo "-- Instantane avant transaction DEB"
need_exec /usr/lib/auxinux/apt-snapshot-hook "la promesse d'un instantane avant chaque transaction ne serait pas tenue"
need_file /etc/apt/apt.conf.d/80auxinux-snapshot "le hook ne serait jamais appele par dpkg"

echo "-- Outils AuxiNux"
need_exec /usr/bin/auxi "commande d'administration principale"
need_exec /usr/bin/auxinux-center "centre de controle"
need_owned /usr/bin/auxi auxi "auxi ne se mettrait jamais a jour (suite APPS)"
need_owned /usr/bin/auxinux-center auxinux-center "le centre de controle ne se mettrait jamais a jour (suite APPS)"
# os-release est DETOURNE de base-files (dpkg -S repond alors
# « auxinuxos-release, base-files: ... »): c'est le detournement qu'on verifie.
if sudo chroot "${ROOTFS}" dpkg-divert --list /usr/lib/os-release 2>/dev/null | grep -q 'by auxinuxos-release'; then
  ok "/usr/lib/os-release detourne par auxinuxos-release"
else
  fail "/usr/lib/os-release non detourne par auxinuxos-release — une mise a jour de base-files remplacerait « AuxiNux OS » par « Debian »"
fi
if [[ -n "${AUXINUX_RELEASE:-}" ]]; then
  got="$(sudo chroot "${ROOTFS}" dpkg-query -W -f='${Version}' auxinuxos-release 2>/dev/null)"
  if [[ "${got}" == "${AUXINUX_RELEASE}" ]]; then ok "edition ${got}"
  else fail "auxinuxos-release ${got:-absent} au lieu de l'edition ${AUXINUX_RELEASE} construite"; fi
fi
# Applications AuxiNux: publiees pour amd64 ET arm64 depuis le 2026-10-26,
# sauf AuxiMail (amd64 seulement: marqueur [amd64] d'applications-auxinux.txt).
need_package auxioffice "pas d'AuxiOffice: aucune suite bureautique"
need_package auxitext "pas d'AuxiText, donc pas d'editeur de texte (AuxiText remplace Kate)"
need_package auxipak "pas d'AuxiPak (demande d'aporler pour la 0.3.0)"
need_exec /usr/bin/auxipak "commande auxipak absente"
need_setting /etc/auxipak/config.toml '^program = "(/usr/bin/)?auxi"$' \
  "AuxiPak passerait par apt-get, bloque sur AuxiNux OS"
need_setting /usr/lib/os-release '^VARIANT_ID=auxinuxos$' \
  "AuxiPak prendrait AuxiNux OS pour une Debian ordinaire (apt-get bloque)"
# Noyau: celui de la suite prod « kernel » au moment du build, jamais un
# noyau en retard (exigence d'aporler pour la 0.3.0: « le dernier kernel de
# notre depot en prod »). Les listes apt du chroot sont celles du build.
kernel_got="$(sudo chroot "${ROOTFS}" dpkg-query -W -f='${Version}' kernel-auxinuxos 2>/dev/null || true)"
kernel_cand="$(sudo chroot "${ROOTFS}" apt-cache policy kernel-auxinuxos 2>/dev/null \
  | sed -n 's/^ *Candidate: //p')"
if [[ -z "${kernel_got}" ]]; then
  fail "kernel-auxinuxos absent"
elif [[ -n "${kernel_cand}" && "${kernel_cand}" != "(none)" && "${kernel_got}" != "${kernel_cand}" ]]; then
  fail "noyau kernel-auxinuxos ${kernel_got} alors que la suite prod offre ${kernel_cand}"
else
  ok "noyau kernel-auxinuxos ${kernel_got} (le plus recent de la suite prod)"
fi
need_file /var/lib/live/config/sddm \
  "live-config ecrirait /etc/sddm.conf (Session=plasma.desktop) et le live ouvrirait Plasma au lieu d'AuxiNux Shell"
need_package auxinux-shell "pas d'AuxiNux Shell: le bureau par defaut (live et installe) serait introuvable"
need_file /usr/share/wayland-sessions/auxinux.desktop "session AuxiNux Shell absente: ecran noir a l'ouverture de session"
if grep -q '^DefaultSession=auxinux.desktop$' "${ROOTFS}/etc/sddm.conf.d/10-auxinux.conf" 2>/dev/null; then
  ok "SDDM: AuxiNux Shell est la session par defaut"
else
  fail "SDDM: DefaultSession=auxinux.desktop absent de 10-auxinux.conf"
fi
need_file /usr/share/applications/ca.auxinux.AuxiText.desktop \
  "les fichiers texte seraient associes (mimeapps.list) a un lanceur absent"
need_setting /etc/xdg/mimeapps.list '^text/plain=ca\.auxinux\.AuxiText\.desktop$' \
  "les fichiers texte ne s'ouvriraient pas avec AuxiText"
# Applications AuxiNux (2026-10-23): chacune remplace son equivalent.
need_package auxicorrect "pas d'AuxiCorrect: ni correcteur ni dictionnaire pour AuxiOffice et AuxiMail"
need_exec /usr/lib/auxicorrect/auxicorrect-cli "AuxiOffice et AuxiMail appellent auxicorrect-cli: correction impossible"
need_file /usr/share/applications/ca.auxinux.pdf.desktop "les PDF seraient associes (mimeapps.list) a un lanceur absent"
need_setting /etc/xdg/mimeapps.list '^application/pdf=ca\.auxinux\.pdf\.desktop$' \
  "les PDF ne s'ouvriraient pas avec AuxiPDF"
# AuxiMail: amd64 seulement pour l'instant.
if [[ "${ARCH}" == "amd64" ]]; then
  need_package auxi-mail "pas d'AuxiMail: aucun logiciel de courrier"
  need_file /usr/share/applications/AuxiMail.desktop "les liens mailto: seraient associes a un lanceur absent"
  need_setting /etc/xdg/mimeapps.list '^x-scheme-handler/mailto=AuxiMail\.desktop$' \
    "un lien « courriel » ouvrirait autre chose qu'AuxiMail"
fi
need_file /etc/apt/sources.list.d/auxinux-apps.sources "AuxiOffice, AuxiText et AuxiPak ne recevraient aucune mise a jour"
need_file /etc/apt/sources.list.d/auxinuxos-kernel-dev.sources.disabled \
  "le depot des noyaux en essai ne serait pas propose dans le centre de controle"
need_file /usr/share/applications/ca.auxinux.Center.desktop "le centre de controle n'apparaitrait dans aucun menu"
# Executable: sinon Plasma demande s'il faut faire confiance au raccourci.
need_exec "/etc/skel/Desktop/AuxiNux OS Center.desktop" "aucun raccourci du centre de controle sur le bureau des nouveaux comptes"
need_exec /usr/libexec/auxinux/auxinux-source-helper "l'ajout de depot depuis le centre echouerait"
need_file /usr/share/polkit-1/actions/ca.auxinux.center.policy "l'assistant privilegie n'aurait pas d'action polkit"
need_exec /usr/lib/auxinux/post-install-cleanup.sh "les artefacts du live resteraient sur le systeme installe"
need_exec /usr/lib/auxinux/verify-installed-boot.sh "une installation produisant un noyau illisible s'annoncerait reussie"
need_exec /usr/lib/auxinux/wrappers/apt-wrapper "la politique APT ne serait pas appliquee"
need_setting /etc/auxinux/apps.conf '^DEB_APPS=0$' \
  "les applications doivent s'installer depuis Flatpak par defaut (auxi set deb=true pour le DEB)"

echo "-- Installateur console « Install NOW »"
need_exec /usr/bin/auxinux-installer "l'entree GRUB par defaut menerait a une console vide"
# Le bandeau de l'installateur nomme la version: un binaire d'une construction
# precedente (premiere ISO 0.3.0: celui du 10 octobre, « 0.2.1 ») se voit ici.
os_version="$(sed -n 's/^VERSION="\([^ "]*\).*/\1/p' "${ROOTFS}/usr/lib/os-release" 2>/dev/null)"
if [[ -n "${os_version}" ]] && sudo grep -aqF "AuxiNux OS ${os_version} " "${ROOTFS}/usr/bin/auxinux-installer"; then
  ok "installateur console de la version ${os_version}"
else
  fail "installateur console d'une autre version que ${os_version:-?} — binaire perime d'une construction precedente"
fi
need_exec /usr/lib/auxinux/auxinux-install-engine "l'installateur ne pourrait rien installer"
need_file /etc/systemd/system/multi-user.target.wants/auxinux-installer.service \
  "l'installateur ne se lancerait pas depuis l'entree « Installer maintenant »"
need_file /etc/calamares/branding/auxinuxos/show.qml "l'installateur graphique n'aurait pas de diaporama"
# Installation SANS Internet: GRUB (UEFI et BIOS) et LUKS doivent etre dans
# l'image. Un lot vide, c'est une installation hors ligne qui echoue au
# moment d'installer le chargeur de demarrage. En arm64: UEFI et LUKS
# seulement, et le lot efi doit porter le GRUB arm64.
if [[ "${ARCH}" == "amd64" ]]; then
  LOTS=(efi bios luks)
else
  LOTS=(efi luks)
  if sudo sh -c "ls '${ROOTFS}/usr/share/auxinux/installateur/paquets/efi/'grub-efi-arm64_*.deb" >/dev/null 2>&1; then
    ok "paquets embarques: efi contient grub-efi-arm64"
  else
    fail "paquets embarques: efi sans grub-efi-arm64 — Install NOW ne pourrait pas installer GRUB hors ligne"
  fi
  refuse_file /usr/share/auxinux/installateur/paquets/bios "lot BIOS dans une image arm64 (UEFI seulement)"
fi
for lot in "${LOTS[@]}"; do
  if sudo sh -c "ls '${ROOTFS}/usr/share/auxinux/installateur/paquets/${lot}/'*.deb" >/dev/null 2>&1; then
    ok "paquets embarques: ${lot}"
  else
    fail "paquets embarques: ${lot} — installation hors ligne impossible (chargeur ou chiffrement)"
  fi
done

echo "-- Assistants graphiques"
need_package zenity "les assistants (accueil live, .exe) n'afficheraient aucune fenetre"
need_package kdialog "boites de dialogue natives pour les scripts KDE"
need_exec /usr/bin/auxinux-welcome "premier ecran de la session live"
if [[ "${ARCH}" == "amd64" ]]; then
  need_exec /usr/bin/auxinux-windows-wizard "ouverture des fichiers .exe"
  need_package wine32:i386 "Wine ne lancerait aucun programme 32 bits, donc presque aucun installateur Windows"
  need_package wine64 "Wine ne lancerait aucun programme Windows 64 bits"
  need_owned /usr/bin/auxinux-windows-wizard auxinux-center "l'assistant des .exe ne recevrait aucun correctif"
fi
need_setting /etc/xdg/kiorc '^behaviourOnLaunch=execute$' \
  "Dolphin demanderait « Executer / Annuler » (Annuler par defaut) avant d'ouvrir un .exe"
need_file /etc/skel/Downloads "les telechargements des nouveaux comptes partiraient dans le bac a sable de Firefox"
need_file /etc/skel/.config/user-dirs.dirs "aucun dossier de telechargement declare pour les nouveaux comptes"
need_setting /etc/xdg/user-dirs.conf '^enabled=False$' \
  "xdg-user-dirs (tire par wine32) creerait des dossiers traduits et deplacerait le bureau"
need_file /etc/xdg/autostart/auxinux-user-dirs.desktop "les comptes existants n'auraient jamais leurs dossiers personnels"
if [[ "${ARCH}" == "amd64" ]]; then
  need_exec /usr/bin/auxinux-windows-setup "installation de la couche Windows et jeux"
else
  # Edition ARM: pas de couche Windows. Une entree de menu qui l'annonce
  # menerait a une installation qui echoue.
  refuse_file /usr/share/applications/auxinux-windows-setup.desktop \
    "entree « couche Windows » dans une image arm64 (Wine x86 indisponible)"
  refuse_file /usr/share/applications/auxinux-windows-wizard.desktop \
    "ouverture des .exe annoncee dans une image arm64 (Wine x86 indisponible)"
fi

echo "-- Bureau et session (AuxiNux Shell, sans le bureau Plasma)"
# Depuis 2026-10-23, le bureau Plasma n'est plus dans l'image (option du centre
# de controle): ses executables sont REFUSES plus bas (retire-du-socle.txt).
# Les scripts de mise en page Plasma restent livres par auxinuxos-release:
# ils servent a qui l'installe.
need_exec /usr/bin/labwc "aucun compositeur Wayland pour AuxiNux Shell"
need_exec /usr/bin/auxinux-session "la session AuxiNux Shell ne demarrerait pas"
need_package x11-xserver-utils "xset/xhost absents: le lanceur de l'installateur graphique echoue (tires jusqu'ici par plasma-workspace)"
need_package xdg-desktop-portal-wlr "aucune capture ni partage d'ecran sous labwc"
need_package plasma-integration "les applications KDE et le centre ne suivraient plus le mode sombre ni l'accent du Shell"
need_package xdg-desktop-portal-kde "le mode sombre ne serait plus publie aux applications GTK (auxinux-color-sync)"
need_file /usr/share/sddm/themes/auxinux/Main.qml "ecran de connexion sans theme: celui de Debian dependait de Plasma"
need_setting /etc/sddm.conf.d/10-auxinux.conf '^Current=auxinux$' "SDDM chercherait un theme absent"
need_file /usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/auxinux-sans-discover.js \
  "Plasma installe a la demande garderait Discover epingle: une icone blanche qui ne lance rien"
need_file /usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/auxinux-fond-ecran.js \
  "Plasma installe a la demande garderait son fond d'ecran au lieu de celui d'AuxiNux"
need_file /usr/share/backgrounds/auxinuxos/default.png "le script du fond d'ecran pointerait vers un fichier absent"
need_package libgl1-mesa-dri "serveur graphique SANS pilote DRI: labwc et le greeter ne demarrent pas (ce paquet n'est qu'un Recommends)"
need_package login "PAM sans /etc/pam.d/login: la pile d'authentification du greeter echoue"

echo "-- Heure (sans elle, aucun HTTPS)"
# Ajoute le 2026-10-05: l'image n'avait AUCUNE synchronisation de l'heure. Sur
# une vraie machine a l'horloge fausse, le certificat de dep.auxinux.ca etait
# « pas encore valide »: l'installateur console ne voyait pas Internet, et apt
# echouait sur le systeme installe. Invisible en VM, ou QEMU donne l'heure.
need_package systemd-timesyncd "l'horloge n'est jamais synchronisee: HTTPS (apt, Flatpak, installateur) echoue des qu'elle est fausse"
need_file /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service \
  "systemd-timesyncd installe mais NON ACTIVE"
need_setting /etc/systemd/timesyncd.conf.d/50-auxinux.conf '^NTP=time\.nrc\.ca' \
  "serveurs d'heure du CNRC (destination decidee dans docs/privacy-stance.md)"
need_any "sans hwclock, l'heure corrigee n'est jamais inscrite dans la machine (module hwclock de Calamares, moteur Install NOW)" \
  /usr/sbin/hwclock /sbin/hwclock

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

echo "-- Mode urgence"
# Le compte root est verrouille: sans SYSTEMD_SULOGIN_FORCE, le mode urgence
# repond « the root account is locked » et la machine s'arrete la.
need_setting /etc/systemd/system/emergency.service.d/50-auxinux-sulogin.conf \
  '^Environment=SYSTEMD_SULOGIN_FORCE=1' "mode urgence sans issue: compte root verrouille"
need_setting /etc/systemd/system/rescue.service.d/50-auxinux-sulogin.conf \
  '^Environment=SYSTEMD_SULOGIN_FORCE=1' "mode de secours sans issue: compte root verrouille"

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
# graphical.target et non multi-user.target: power-profiles-daemon s'ordonne
# APRES multi-user.target, et le cycle faisait sauter l'unite a chaque
# demarrage (« Ordering cycle found, skipping auxinux-profile.service »).
refuse_file /etc/systemd/system/multi-user.target.wants/auxinux-profile.service \
  "cycle avec power-profiles-daemon: le profil ne serait jamais applique"
need_file /etc/systemd/system/graphical.target.wants/auxinux-profile.service \
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

echo "-- Fonctions du Shell et d'AuxiFiles"
# Paquets que la 0.4.0 n'avait que par accident (voir bureau-auxinux.txt).
need_package accountsservice "Parametres > Comptes: ni nom, ni photo, ni autres utilisateurs"
need_package gvfs-backends "AuxiFiles: aucun partage reseau (smb, sftp, ftp)"
need_package openssh-client "AuxiFiles: sftp:// impossible (gvfs lance ssh)"
need_package fonts-liberation "documents Windows sans les metriques d'Arial et Times New Roman"

echo "-- Pare-feu"
# firewalld depuis la 0.5.0: le Shell (Parametres > Securite) ne pilote plus ufw.
need_package firewalld "aucun pare-feu: Parametres > Securite dirait « non protege »"
need_file /etc/systemd/system/multi-user.target.wants/firewalld.service \
  "firewalld installe mais NON ACTIVE: la machine n'est pas protegee"

echo "-- Ecran de demarrage"
# Depuis la 0.3.0, logo + roue orange (Plymouth, theme auxinux) au lieu du
# texte de la console (demande d'aporler: le texte fait peur a qui arrive de
# Windows). `quiet splash` ne vient QUE de /etc/default/grub.d/50-auxinux-splash.cfg
# (paquet auxinuxos-release): /etc/default/grub et grubcfg.conf restent vides,
# et les entrees de secours de GRUB gardent le texte. Sans Plymouth et son
# theme dans l'initramfs, `quiet` seul ferait d'une panne un ecran noir muet:
# l'un sans l'autre est refuse.
for grub_file in /etc/default/grub /etc/calamares/modules/grubcfg.conf; do
  if [[ -f "${ROOTFS}${grub_file}" ]] &&
     grep -qE '^[^#]*GRUB_CMDLINE_LINUX_DEFAULT.*(quiet|splash)' "${ROOTFS}${grub_file}"; then
    fail "${grub_file}: 'quiet'/'splash' ici aussi — seul grub.d/50-auxinux-splash.cfg doit le porter"
  else
    ok "${grub_file}: pas de 'quiet' (porte par grub.d)"
  fi
done
need_package plymouth "pas d'ecran de demarrage: 'quiet splash' donnerait un ecran noir"
need_setting /etc/default/grub.d/50-auxinux-splash.cfg '^GRUB_CMDLINE_LINUX_DEFAULT=".*quiet splash' \
  "le texte de la console s'afficherait au demarrage"
need_file /usr/share/plymouth/themes/auxinux/auxinux.plymouth "theme Plymouth AuxiNux absent"
need_setting /etc/plymouth/plymouthd.conf '^Theme=auxinux$' "Plymouth afficherait le theme Debian et non le logo AuxiNux"
initrd="$(sudo find "${ROOTFS}/boot" -maxdepth 1 -name 'initrd.img-*auxinuxos*' 2>/dev/null | sort -V | tail -n1)"
if [[ -z "${initrd}" ]]; then
  fail "aucun initramfs AuxiNux dans /boot"
# grep -c et non grep -q: -q s'arrete au premier resultat et coupe le tube;
# lsinitramfs meurt alors de SIGPIPE et pipefail le compte comme un echec.
# Invisible en PC (lsinitramfs finit avant), systematique sous emulation ARM
# (1re ISO arm64, 2026-10-25): le theme etait present et le controle disait
# l'inverse.
elif [[ "$(sudo chroot "${ROOTFS}" lsinitramfs "/boot/$(basename "${initrd}")" 2>/dev/null \
            | grep -c 'usr/share/plymouth/themes/auxinux/auxinux.script')" -gt 0 ]]; then
  ok "$(basename "${initrd}"): theme Plymouth auxinux present"
else
  fail "$(basename "${initrd}"): theme Plymouth auxinux absent de l'initramfs — splash muet ou theme Debian"
fi

# Le module Calamares `grubcfg` ajoute « quiet » de lui-meme (kernel_params,
# defaut ["quiet"]) par-dessus une GRUB_CMDLINE_LINUX_DEFAULT vide: le controle
# ci-dessus passait, et le systeme installe demarrait quand meme en silence.
if [[ -f "${ROOTFS}/etc/calamares/modules/grubcfg.conf" ]] &&
   grep -qE '^[[:space:]]*kernel_params:[[:space:]]*\[[[:space:]]*\]' \
     "${ROOTFS}/etc/calamares/modules/grubcfg.conf"; then
  ok "grubcfg.conf: kernel_params vide, Calamares n'ajoute pas « quiet »"
else
  fail "grubcfg.conf: kernel_params absent — Calamares ajouterait « quiet » au systeme installe"
fi

if [[ "${ARCH}" == "amd64" ]]; then
  echo "-- Couche Windows"
  if sudo chroot "${ROOTFS}" dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
    ok "architecture i386"
  else
    fail "architecture i386 — wine32 absent, donc aucune application Windows 32 bits"
  fi
  need_package wine "couche de compatibilite Windows"
else
  echo "-- Edition ARM (${ARCH}): UEFI seulement, sans couche Windows"
  if sudo chroot "${ROOTFS}" dpkg --print-foreign-architectures 2>/dev/null | grep -q .; then
    fail "architecture etrangere declaree ($(sudo chroot "${ROOTFS}" dpkg --print-foreign-architectures 2>/dev/null | paste -sd' ')) — l'Edition ARM n'en a aucune"
  else
    ok "aucune architecture etrangere"
  fi
  i386_pkgs="$(sudo chroot "${ROOTFS}" dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | grep ':i386$' | paste -sd' ' || true)"
  if [[ -n "${i386_pkgs}" ]]; then
    fail "paquets i386 installes: ${i386_pkgs}"
  else
    ok "aucun paquet i386"
  fi
  # Chaine de demarrage signee arm64, lue par make-iso.sh.
  need_file /usr/lib/shim/shimaa64.efi.signed "pas de shim arm64: l'ISO ne demarrerait pas (paquet shim-signed)"
  need_file /usr/lib/shim/mmaa64.efi.signed "pas de MokManager arm64 (paquet shim-signed)"
  need_file /usr/lib/grub/arm64-efi-signed/gcdaa64.efi.signed "pas de GRUB arm64 signe (paquet grub-efi-arm64-signed)"
  need_package grub-efi-arm64-bin "grub-install --target=arm64-efi impossible pendant l'installation"
  refuse_package grub-pc-bin "GRUB BIOS dans une image arm64"
  refuse_package wine "couche Windows dans une image arm64 (Wine x86 indisponible)"
  # Outils invites: presse-papiers et redimensionnement dans les VM sur Mac.
  need_package spice-vdagent "presse-papiers et taille d'ecran dans UTM/QEMU"
  need_package qemu-guest-agent "arret propre et synchronisation depuis l'hote UTM/QEMU"
  need_package open-vm-tools-desktop "presse-papiers et taille d'ecran dans VMware Fusion"
fi

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

echo "-- Socle: aucune application imposee"
# Decision d'aporler (2026-10-02): l'image ne contient plus aucune application
# d'usage; l'assistant de premier demarrage les propose. hors-socle.txt est la
# seule liste de ce qui doit etre absent: la purge de build-image.sh et ce
# controle la lisent tous deux.
HORS_SOCLE_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/package-lists/hors-socle.txt"
while read -r pkg; do
  refuse_package "${pkg}" "application imposee: elle doit etre proposee par l'assistant, pas installee d'office"
done < <("${PACKAGE_NAMES}" "${ARCH}" "${HORS_SOCLE_LIST}")
# Bureau Plasma et equivalents des applications AuxiNux (2026-10-23).
while read -r pkg; do
  refuse_package "${pkg}" "retire du socle (retire-du-socle.txt): Plasma s'installe depuis le centre, l'application AuxiNux remplace son equivalent"
done < <("${PACKAGE_NAMES}" "${ARCH}" "$(dirname "${HORS_SOCLE_LIST}")/retire-du-socle.txt")
# Le depot Brave est livre, mais DESACTIVE: actif, il ferait contacter Brave a
# chaque `apt update`, meme par qui ne l'a pas choisi.
refuse_file /etc/apt/sources.list.d/brave-browser-release.sources \
  "depot Brave actif sans que l'utilisateur ait choisi Brave"
need_file /etc/apt/sources.list.d/brave-browser-release.sources.disabled \
  "l'assistant ne pourrait pas activer le depot Brave quand Brave est choisi"
need_file /usr/share/keyrings/brave-browser-archive-keyring.gpg \
  "depot Brave sans sa cle: choisir Brave dans l'assistant echouerait (« Failed to parse keyring »)"
need_exec /usr/libexec/auxinux/auxinux-assistant-apply \
  "l'assistant de premier demarrage ne pourrait rien installer"
need_file /etc/xdg/autostart/auxinux-assistant.desktop \
  "l'assistant ne s'ouvrirait pas au premier demarrage"
need_exec /usr/libexec/auxinux/auxinux-refresh-helper \
  "« Actualiser les listes » du centre echouerait (pkexec: programme absent)"
need_exec /usr/libexec/auxinux/auxinux-update-helper \
  "les mises a jour du systeme depuis le centre echoueraient (pkexec: programme absent)"
need_exec /usr/libexec/auxinux/auxinux-session-helper \
  "le choix du bureau (Reglages du centre) echouerait (pkexec: programme absent)"

echo "-- Session live: rien qui ressemble a un ecran noir"
# Le live ne doit NI se verrouiller NI eteindre l'ecran: un visiteur qui laisse
# la machine deux minutes revenait devant un ecran noir, puis un mot de passe
# qu'il n'a jamais choisi. Constate sur le premier essai VM de la 0.2.0.
need_setting /home/auxinux/.config/auxinux-shell/config.json '"lock_after": 0,' \
  "le live (AuxiNux Shell) se verrouillerait apres cinq minutes"
need_setting /home/auxinux/.config/auxinux-shell/config.json '"screen_off_after": 0,' \
  "l'ecran du live (AuxiNux Shell) s'eteindrait apres dix minutes"
need_setting /home/auxinux/.config/kscreenlockerrc '^Autolock=false' \
  "le live se verrouillerait apres dix minutes"
need_setting /home/auxinux/.config/powerdevilrc '^TurnOffDisplayWhenIdle=false' \
  "l'ecran du live s'eteindrait apres dix minutes"
need_setting /home/auxinux/.config/powerdevilrc '^DimDisplayWhenIdle=false' \
  "l'ecran du live s'assombrirait pendant l'installation"
# L'ancien format (Plasma 5) est MIGRE par Plasma 6 avec des unites fausses:
# 86400 ms d'assombrissement devenaient 86 secondes.
refuse_file /home/auxinux/.config/powermanagementprofilesrc \
  "fichier Plasma 5 que Plasma 6 migrerait en assombrissant l'ecran au bout de 86 s"
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
