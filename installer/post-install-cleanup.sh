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
#    Aucun de ces cinq points de montage n'est necessaire pour demarrer: sans
#    eux le systeme perd des instantanes ou des journaux, il ne perd pas la
#    capacite de s'amorcer. `nofail` transforme donc une panne totale en une
#    degradation visible dans `systemctl --failed`.
#
#    / , /home et /boot/efi ne sont volontairement PAS touches: si la racine
#    ou le repertoire personnel manquent, il n'y a rien a sauver et le silence
#    serait pire.
if [ -f "${prefix}/etc/fstab" ]; then
  awk '
    {
      if ($0 ~ /^[^#]/ && NF >= 4 &&
          ($2 == "/.snapshots" || $2 == "/var/lib/flatpak" || $2 == "/var/tmp" ||
           $2 == "/var/cache"  || $2 == "/var/log"         || $2 == "/swap"  ||
           $3 == "swap")) {
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
