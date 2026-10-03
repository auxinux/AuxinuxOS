#!/usr/bin/env bash
set -euo pipefail

# Nettoyage post-installation: retire du systeme INSTALLE tous les artefacts
# propres a l'environnement live. Sans ce nettoyage, le systeme installe
# heriterait d'un sudo sans mot de passe, d'un compte par defaut connu et d'un
# autologin -> contraire a la posture vie privee/securite visee.
#
# Doit etre branche dans Calamares (voir installer/calamares/) et s'executer
# une fois la copie du systeme terminee, avant le premier demarrage.
#
# Usage: post-install-cleanup.sh TARGET_ROOT
#   TARGET_ROOT = point de montage du systeme installe ("/" si deja chroote).

TARGET_ROOT="${1:?usage: post-install-cleanup.sh TARGET_ROOT}"
LIVE_USER="auxinux"

# Normalise: "/" => prefixe vide pour des chemins absolus propres.
prefix="${TARGET_ROOT%/}"

# 0. Tout fichier de /boot doit etre stocke EN CLAIR et SANS TROU.
#
#    PANNE RENCONTREE SUR MATERIEL REEL (2026-09-13), puis REPRODUITE EN VM
#    le 2026-09-29 sur l'ISO qui devait la corriger:
#
#      Loading Linux 7.2.5-auxinuxos-amd64 ...
#      erreur : fin prematuree du fichier /@/boot/vmlinuz-7.2.5-auxinuxos-amd64.
#      erreur : le noyau doit d'abord etre charge.
#
#    LA VRAIE CAUSE est un TROU en fin de fichier, pas la compression. Les
#    512 derniers octets du noyau sont des zeros de remplissage. Calamares
#    copie le systeme avec `rsync -S`, qui transforme ces zeros en trou; la
#    fonction BTRFS no-holes n'ecrit alors AUCUN extent pour ce trou final, et
#    le pilote BTRFS de GRUB 2.12 s'arrete au dernier extent: il lit
#    16 752 640 octets sur 16 753 152 (mesure avec grub-fstest, qui execute
#    le pilote de GRUB lui-meme). Le noyau Linux, lui, lit le trou comme des
#    zeros: aucune relecture faite depuis Linux ne pouvait le voir.
#
#    Le premier correctif (propriete « compression none » + `cp --reflink=
#    never`) ne touchait pas au trou: `cp` le RECREE (--sparse=auto par
#    defaut). D'ou `--sparse=never` ci-dessous, qui ecrit les zeros.
#
#    La compression reste desactivee sur /boot par prudence: GRUB relit ces
#    fichiers avec son propre decompresseur, et rien ne justifie de lui en
#    demander davantage pour quelques dizaines de Mo. La propriete est posee
#    sur les REPERTOIRES: elle est heritee par l'initramfs regenere plus bas ET
#    par les futurs noyaux installes par apt. Elle prime sur l'option de
#    montage.
#
#    Sur TOUS les repertoires de /boot, et pas seulement /boot: /boot/grub a
#    ete cree par grub-install AVANT ce script, il n'herite donc de rien. Or
#    GRUB y lit son menu, ses polices et -- sur une installation BIOS -- ses
#    modules: un normal.mod qu'il ne sait pas relire, c'est une invite
#    « grub rescue> » au lieu du menu.
#
#    Puis on reecrit chaque fichier de /boot. `--reflink=never` est
#    INDISPENSABLE: sans lui, cp partage les extents existants et rien ne
#    change. /boot/efi est exclu: c'est une partition FAT.
boot_fstype="$(findmnt -no FSTYPE -T "${prefix}/boot" 2>/dev/null || true)"
if [ -d "${prefix}/boot" ] && [ "${boot_fstype}" = "btrfs" ]; then
  if command -v btrfs >/dev/null 2>&1 &&
     btrfs property set "${prefix}/boot" compression none 2>/dev/null; then
    while IFS= read -r -d '' bdir; do
      btrfs property set "${bdir}" compression none 2>/dev/null \
        || echo "post-install-cleanup: AVERTISSEMENT: ${bdir#"${prefix}"} garde la compression." >&2
    done < <(find "${prefix}/boot" -mindepth 1 -xdev \
               \( -path "${prefix}/boot/efi" -prune \) -o -type d -print0 2>/dev/null)
  else
    echo "post-install-cleanup: AVERTISSEMENT: compression de /boot non desactivee." >&2
  fi
  # La reecriture sans trou est faite QUOI QU'IL ARRIVE a la propriete: c'est
  # elle, et non la compression, qui rend le noyau lisible par GRUB.
  #
  # La liste est ARRETEE avant de reecrire quoi que ce soit: chaque reecriture
  # ajoute une entree au repertoire, et un parcours encore en cours pourrait
  # la revoir -- et la reecrire encore.
  mapfile -d '' -t boot_files < <(find "${prefix}/boot" -xdev \
    \( -path "${prefix}/boot/efi" -prune \) -o -type f ! -name '*.aux-tmp' -print0 2>/dev/null)
  for kf in "${boot_files[@]}"; do
    if cp -a --reflink=never --sparse=never "${kf}" "${kf}.aux-tmp" 2>/dev/null; then
      mv -f "${kf}.aux-tmp" "${kf}"
    else
      rm -f "${kf}.aux-tmp"
      echo "post-install-cleanup: AVERTISSEMENT: ${kf#"${prefix}"} non reecrit;" >&2
      echo "  GRUB peut echouer sur « fin prematuree du fichier »." >&2
    fi
  done
  sync
fi

# 1. Artefacts de l'installateur (live uniquement).
#
#    Le fichier d'AUTODEMARRAGE etait oublie: l'installateur se relancait donc
#    a CHAQUE ouverture de session du systeme installe. Pire, son lanceur
#    commence par « sudo mv /etc/fstab /etc/fstab.orig.calamares »: sur un
#    systeme en service, cela deplace le fstab et rouvre un partitionneur.
rm -f "${prefix}/home"/*/Desktop/"Install AuxiNuxOS.desktop"
rm -f "${prefix}/usr/share/applications/auxinux-install.desktop"
rm -f "${prefix}/etc/xdg/autostart/auxinux-install.desktop"
rm -f "${prefix}/usr/lib/auxinux/auxinux-install-launcher"
rm -f "${prefix}/etc/xdg/autostart/auxinux-welcome.desktop"
rm -f "${prefix}/usr/bin/auxinux-welcome"

#    Un fstab mis de cote par un lancement precedent du lanceur ne doit pas
#    rester dans la cible: il ferait croire a une sauvegarde valide.
rm -f "${prefix}/etc/fstab.orig.calamares"

# 2. Sudo NOPASSWD du live.
rm -f "${prefix}/etc/sudoers.d/90-auxinux-live"

# 3. Autologin du live. AuxiNuxOS utilise SDDM: l'autologin live est le
#    fichier /etc/sddm.conf.d/90-auxinux-live-autologin.conf, qui connecte
#    automatiquement le compte live "auxinux". Ce compte est supprime a
#    l'etape 5. Laisse en place, il ferait ouvrir au systeme INSTALLE une
#    session pour un utilisateur inexistant: SDDM echoue, recommence, atteint
#    sa limite de redemarrages, et le demarrage n'aboutit jamais. C'est la
#    panne rapportee sur la 0.1 (avec greetd a l'epoque).
rm -f "${prefix}/etc/sddm.conf.d/90-auxinux-live-autologin.conf"
# Autologins des images precedentes (greetd + cosmic-greeter, et l'ancien SDDM
# pre-COSMIC), au cas ou le squashfs viendrait d'une image plus ancienne.
rm -f "${prefix}/etc/sddm.conf.d/10-auxinuxos-live.conf"
rm -rf "${prefix}/etc/greetd"

# 3b. Reaffirme le gestionnaire d'affichage. Le module Calamares
#     "displaymanager" reecrit ce lien selon SA liste de gestionnaires connus:
#     s'il ne trouve pas celui de l'image, il peut le retirer, et le systeme
#     installe demarre alors sans interface graphique. On retablit SDDM.
if [ -e "${prefix}/usr/lib/systemd/system/sddm.service" ]; then
  ln -sf /usr/lib/systemd/system/sddm.service \
    "${prefix}/etc/systemd/system/display-manager.service"
  printf '/usr/bin/sddm\n' > "${prefix}/etc/X11/default-display-manager"
fi

# 3b-bis. UNE SEULE disposition de clavier, partout.
#
#     Calamares ecrit la disposition choisie dans /etc/default/keyboard et
#     /etc/X11/xorg.conf.d/00-keyboard.conf: l'ecran de connexion (SDDM, en
#     X11) et la console la suivent. La session Plasma, elle, tourne sous
#     KWin/Wayland, qui ne lit NI l'un NI l'autre: KWin prend la disposition
#     dans kxkbrc et, sans ce fichier, charge « us ».
#
#     Le mot de passe a ete tape dans l'installateur avec la disposition
#     choisie. Quand elle differe de « us » (AZERTY, ou simplement un
#     caractere place autrement), il ouvre la session a l'ecran de connexion,
#     puis ne DEVERROUILLE plus l'ecran apres dix minutes, et sudo le refuse:
#     la machine devient inutilisable sans qu'aucun message ne dise pourquoi.
#
#     /etc/xdg/kxkbrc est le defaut systeme de KDE (lu apres ~/.config): la
#     session prend la meme disposition que l'ecran de connexion, et chacun
#     garde la main dans Configuration du systeme > Clavier.
if [ -r "${prefix}/etc/default/keyboard" ]; then
  (
    XKBMODEL="" XKBLAYOUT="" XKBVARIANT="" XKBOPTIONS=""
    # shellcheck disable=SC1091
    . "${prefix}/etc/default/keyboard"
    mkdir -p "${prefix}/etc/xdg"
    {
      echo "# Ecrit par post-install-cleanup.sh depuis /etc/default/keyboard:"
      echo "# la session Plasma utilise la disposition choisie a l'installation."
      echo "[Layout]"
      echo "Use=true"
      echo "LayoutList=${XKBLAYOUT:-us}"
      echo "VariantList=${XKBVARIANT}"
      echo "Model=${XKBMODEL:-pc105}"
      if [ -n "${XKBOPTIONS}" ]; then
        echo "ResetOldOptions=true"
        echo "Options=${XKBOPTIONS}"
      fi
    } > "${prefix}/etc/xdg/kxkbrc"
  ) || echo "post-install-cleanup: AVERTISSEMENT: /etc/xdg/kxkbrc non ecrit; la session Plasma sera en « us »." >&2
fi

# 3c. Compteur de la protection au demarrage. Le squashfs a ete produit apres
#     des demarrages du LIVE; si le compteur en gardait la trace, le systeme
#     installe pourrait basculer en console de secours a son PREMIER demarrage,
#     et proposer de restaurer un instantane qui n'existe pas encore.
rm -f "${prefix}/var/lib/auxinux/boot-failures"

# 4. Montages non essentiels en `nofail`.
#
#    Le /etc/fstab ecrit par Calamares monte @snapshots, @var_lib_flatpak,
#    @var_tmp, @var_cache et @var_log SANS `nofail`. Si l'un d'eux manque ou
#    refuse de se monter, systemd echoue local-fs.target et bascule en mode
#    urgence. Or ce systeme n'a PAS de mot de passe root (users.conf:
#    setRootPassword: false): sulogin refuse alors la console avec « cannot
#    open access to console, the root account is locked » et le demarrage
#    s'arrete la, DEFINITIVEMENT, sur un ecran que l'utilisateur ne peut ni
#    lire ni quitter.
#
#    Aucun de ces points de montage n'est necessaire pour demarrer: sans eux
#    le systeme perd des instantanes ou des journaux, il ne perd pas la
#    capacite de s'amorcer. `nofail` transforme donc une panne totale en une
#    degradation visible dans `systemctl --failed`.
#
#    /boot/efi aussi: seul le micrologiciel lit la partition EFI, le systeme
#    en marche n'en a pas besoin. Or c'est un FAT, que la moindre extinction
#    brutale laisse « sale »; un fsck.vfat qui n'arrive pas a le reparer
#    suffisait a envoyer la machine en mode urgence.
#
#    / et /home ne sont volontairement PAS touches: si la racine ou le
#    repertoire personnel manquent, il n'y a rien a sauver et le silence
#    serait pire.
if [ -f "${prefix}/etc/fstab" ]; then
  awk '
    {
      if ($0 ~ /^[^#]/ && NF >= 4 &&
          ($2 == "/.snapshots" || $2 == "/var/lib/flatpak" || $2 == "/var/tmp" ||
           $2 == "/var/cache"  || $2 == "/var/log"         || $2 == "/swap"  ||
           $2 == "/boot/efi"   || $3 == "swap")) {
        if ($4 !~ /(^|,)nofail(,|$)/) { $4 = $4 ",nofail" }
        printf "%-46s %-16s %-8s %-42s %s %s\n", $1, $2, $3, $4, $5, $6
        next
      }
      print
    }
  ' "${prefix}/etc/fstab" > "${prefix}/etc/fstab.auxinux" &&
    mv "${prefix}/etc/fstab.auxinux" "${prefix}/etc/fstab"
fi

# 5. Compte live par defaut (mot de passe connu "auxinux"). Calamares cree le
#    vrai compte utilisateur; on supprime le compte live et son /home.
if chroot "${TARGET_ROOT}" id -u "${LIVE_USER}" >/dev/null 2>&1; then
  # Ne jamais supprimer le compte que l'installateur vient de creer.
  if [[ "${LIVE_USER}" != "${AUXINUX_KEEP_USER:-}" ]]; then
    chroot "${TARGET_ROOT}" userdel -r "${LIVE_USER}" 2>/dev/null || \
      chroot "${TARGET_ROOT}" userdel "${LIVE_USER}" || true
  fi
fi

# 6. Paquets live-boot/live-config: le squashfs installe est une copie du
#    systeme LIVE, qui a live-boot/live-boot-initramfs-tools/live-config/
#    live-config-systemd installes pour amorcer le medium live. Sur le
#    systeme INSTALLE, ces paquets n'ont aucune utilite -- pire,
#    live-boot-initramfs-tools embarque un hook initramfs-tools qui injecte
#    les scripts live-boot (recherche de medium live, montages HTTP/CIFS,
#    verification de checksums...) dans CHAQUE initramfs regenere, y compris
#    celui du systeme installe. Au demarrage reel, ce script tente de
#    detecter un medium live inexistant -> le noyau/Plymouth demarrent
#    (l'ecran "change") mais rien ne prend jamais la main pour de bon
#    (panne rapportee: "l'ecran change... mais ne termine jamais de
#    charger"). On purge ces paquets ici, pendant que enableapt (module
#    Calamares execute plus tot dans la sequence) a encore APT_ENABLED=1.
if ! chroot "${TARGET_ROOT}" apt-get purge -y \
     live-boot live-boot-initramfs-tools live-config live-config-systemd; then
  echo "post-install-cleanup: AVERTISSEMENT: purge de live-boot/live-config echouee." >&2
  echo "  L'initramfs du systeme installe peut encore contenir les scripts live." >&2
fi

# 6a. Installateur lui-meme. Calamares partitionne et formate des disques; le
#     laisser sur le systeme installe, avec son entree de menu, revient a
#     livrer un outil capable d'effacer la machine a un utilisateur qui vient
#     d'en terminer l'installation. Il n'a plus aucune raison d'etre presente.
if ! chroot "${TARGET_ROOT}" apt-get purge -y calamares calamares-settings-debian; then
  echo "post-install-cleanup: AVERTISSEMENT: purge de Calamares echouee; l'installateur reste sur le systeme installe." >&2
fi
rm -f "${prefix}/usr/share/applications/calamares.desktop" \
      "${prefix}/usr/share/applications/calamares-install-debian.desktop"
#     Nos propres fichiers de configuration Calamares survivent a la purge du
#     paquet (dpkg les signale: « directory /etc/calamares/modules not empty
#     so not removed »). Ils decrivent comment partitionner et formater un
#     disque: rien a faire sur un systeme en service.
rm -rf "${prefix}/etc/calamares"
#     Meme raison pour l'installateur maison « Install NOW »: son programme,
#     son moteur (qui efface un disque entier), son unite de demarrage et les
#     paquets de GRUB/LUKS embarques pour installer sans Internet.
rm -f "${prefix}/usr/bin/auxinux-installer" \
      "${prefix}/usr/lib/auxinux/auxinux-install-engine" \
      "${prefix}/etc/systemd/system/auxinux-installer.service" \
      "${prefix}/etc/systemd/system/multi-user.target.wants/auxinux-installer.service"
rm -rf "${prefix}/usr/share/auxinux/installateur"

# 6b. Regenere l'initramfs maintenant que live-boot est purge. Le module
#     Calamares `initramfs` a deja tourne plus tot dans la sequence (avec
#     live-boot encore present) -- sans cette regeneration, l'initrd sur
#     disque resterait celui, contamine, construit avant la purge.
#     Cet echec-la n'est PAS anodin: un initramfs non regenere laisse les
#     scripts live-boot en place, et le systeme installe cherche un medium
#     live inexistant au demarrage. On le dit fort; shellprocess@verifyboot
#     relira ensuite l'initrd depuis le disque et fera echouer l'installation
#     s'il est inexploitable.
if ! chroot "${TARGET_ROOT}" update-initramfs -u -k all; then
  echo "post-install-cleanup: AVERTISSEMENT: regeneration de l'initramfs echouee." >&2
fi

# 6c. Chemin de demarrage UEFI de secours: EFI/BOOT/BOOTX64.EFI.
#
#     C'est le SEUL fichier qu'un micrologiciel est oblige de savoir amorcer.
#     Beaucoup de portables ignorent ou perdent l'entree NVRAM « AuxiNuxOS »
#     (mise a jour du BIOS, pile CMOS, micrologiciel qui ne garde que
#     « Windows Boot Manager ») et retombent sur ce chemin.
#
#     Calamares y copiait grubx64.efi SEUL. Or c'est le GRUB signe de Debian,
#     une image monolithique qui ne connait pas notre disque: elle lit le
#     grub.cfg pose A COTE D'ELLE par grub-install. Sans ce fichier dans
#     EFI/BOOT, la machine s'arretait sur une invite « grub> » -- un systeme
#     installe, intact, et inutilisable pour qui ne connait pas GRUB.
#
#     On reproduit donc dans EFI/BOOT le repertoire EFI/AuxiNuxOS tel que
#     grub-install l'a rempli: shim en BOOTX64.EFI (s'il est la), GRUB,
#     MokManager et grub.cfg. fbx64.efi n'est volontairement PAS copie: il
#     recreerait les entrees NVRAM puis redemarrerait, en boucle si le
#     micrologiciel refuse l'ecriture.
esp="${prefix}/boot/efi"
if [ -d "${esp}/EFI" ]; then
  vendor=""
  bootdir=""
  for d in "${esp}"/EFI/*; do
    [ -d "${d}" ] || continue
    case "$(basename "${d}" | tr '[:lower:]' '[:upper:]')" in
      AUXINUXOS) vendor="${d}" ;;
      BOOT) bootdir="${d}" ;;
    esac
  done
  if [ -n "${vendor}" ] && [ -f "${vendor}/grub.cfg" ] && [ -f "${vendor}/grubx64.efi" ]; then
    # Chemin de SECOURS: un echec ici ne doit pas faire echouer toute
    # l'installation (set -e). Il est signale, et verify-installed-boot.sh
    # redit l'absence de chemin de secours.
    bootdir="${bootdir:-${esp}/EFI/BOOT}"
    # Chaque etape rend la main a la premiere erreur: bash ignore `set -e`
    # dans une fonction appelee en condition de `if`.
    copy_fallback() {
      mkdir -p "${bootdir}" || return 1
      # FAT ignore la casse: on retire toute variante de nom avant d'ecrire.
      for f in "${bootdir}"/*; do
        [ -f "${f}" ] || continue
        case "$(basename "${f}" | tr '[:lower:]' '[:upper:]')" in
          BOOTX64.EFI|GRUBX64.EFI|MMX64.EFI|GRUB.CFG) rm -f "${f}" || return 1 ;;
        esac
      done
      if [ -f "${vendor}/shimx64.efi" ]; then
        cp "${vendor}/shimx64.efi" "${bootdir}/BOOTX64.EFI" || return 1
        cp "${vendor}/grubx64.efi" "${bootdir}/grubx64.efi" || return 1
        if [ -f "${vendor}/mmx64.efi" ]; then
          cp "${vendor}/mmx64.efi" "${bootdir}/mmx64.efi" || return 1
        fi
      else
        cp "${vendor}/grubx64.efi" "${bootdir}/BOOTX64.EFI" || return 1
      fi
      cp "${vendor}/grub.cfg" "${bootdir}/grub.cfg" || return 1
    }
    if ! copy_fallback; then
      echo "post-install-cleanup: AVERTISSEMENT: chemin de secours EFI/BOOT incomplet (partition EFI pleine ?)." >&2
    fi
    # Et que les mises a jour de GRUB le tiennent a jour: grub-efi-amd64
    # relance grub-install a chaque nouvelle version, avec
    # --force-extra-removable si cette question debconf vaut « true ».
    echo "grub-efi-amd64 grub2/force_efi_extra_removable boolean true" \
      | chroot "${TARGET_ROOT}" debconf-set-selections 2>/dev/null \
      || echo "post-install-cleanup: AVERTISSEMENT: grub2/force_efi_extra_removable non pose." >&2
  elif [ -n "${vendor}" ] && [ ! -e "${vendor}/shimx64.efi" ] && [ -s "${vendor}/grubx64.efi" ]; then
    # GRUB autonome (disque chiffre, installateur maison): il a ecrit lui-meme
    # EFI/BOOT/BOOTX64.EFI avec grub-install --removable.
    :
  else
    echo "post-install-cleanup: AVERTISSEMENT: EFI/AuxiNuxOS incomplet; chemin de secours EFI/BOOT non ecrit." >&2
  fi
fi

# 7. Restaure la politique APT du systeme installe. Pendant l'installation, le
#    module enableapt a mis APT_ENABLED=1 (pour permettre l'install de GRUB);
#    on remet la valeur par defaut (apt redirige vers auxi).
mkdir -p "${prefix}/etc/auxinux"
printf 'APT_ENABLED=0\n' > "${prefix}/etc/auxinux/apt.conf"

# 8. Securite (ceinture+bretelles): retire toute source APT LOCALE residuelle
#    (media d'installation file:/cdrom:). Normalement sources-media-unmount l'a
#    deja fait, mais on garantit qu'aucune source locale ne survit.
for f in "${prefix}/etc/apt/sources.list.d/"*; do
  [ -e "${f}" ] || continue
  if grep -qiE 'file:|cdrom:' "${f}" 2>/dev/null; then
    rm -f "${f}"
  fi
done
if [ -f "${prefix}/etc/apt/sources.list" ]; then
  sed -i -E '/file:|cdrom:/d' "${prefix}/etc/apt/sources.list"
fi

exit 0
