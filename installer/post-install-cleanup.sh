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

# 1. Icone d'installation (live uniquement).
rm -f "${prefix}/home"/*/Desktop/"Install AuxiNuxOS.desktop"
rm -f "${prefix}/usr/share/applications/auxinux-install.desktop"
rm -f "${prefix}/etc/xdg/autostart/auxinux-welcome.desktop"
rm -f "${prefix}/usr/bin/auxinux-welcome"

# 2. Sudo NOPASSWD du live.
rm -f "${prefix}/etc/sudoers.d/90-auxinux-live"

# 3. Autologin du live. AuxiNuxOS EN utilise COSMIC + greetd: l'autologin
#    live est le bloc [initial_session] de /etc/greetd/cosmic-greeter.toml,
#    qui connecte automatiquement le compte live "auxinux". Ce compte est
#    supprime a l'etape 5. Si l'autologin reste, le systeme INSTALLE tente de
#    connecter un utilisateur inexistant -> greetd echoue en boucle et le
#    demarrage reste bloque en console (panne rapportee). On reecrit donc la
#    config greetd SANS [initial_session]: le systeme installe affiche l'ecran
#    de connexion COSMIC normal pour le compte cree par Calamares.
if [ -f "${prefix}/etc/greetd/cosmic-greeter.toml" ]; then
  cat > "${prefix}/etc/greetd/cosmic-greeter.toml" <<'GREETD_EOF'
[terminal]
vt = "1"

[general]
service = "cosmic-greeter"

[default_session]
command = "cosmic-comp systemd-cat -t cosmic-greeter cosmic-greeter"
user = "cosmic-greeter"
GREETD_EOF
fi
# Ancien autologin SDDM (images pre-COSMIC), au cas ou.
rm -f "${prefix}/etc/sddm.conf.d/10-auxinuxos-live.conf"

# 3b. Reaffirme le gestionnaire d'affichage. Le module Calamares
#     "displaymanager" ne connait pas greetd/cosmic-greeter et peut avoir
#     retire le lien display-manager.service -> le systeme installe
#     demarrerait alors sans interface graphique (console). On retablit le
#     lien vers cosmic-greeter.
if [ -e "${prefix}/usr/lib/systemd/system/cosmic-greeter.service" ]; then
  ln -sf /usr/lib/systemd/system/cosmic-greeter.service \
    "${prefix}/etc/systemd/system/display-manager.service"
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
chroot "${TARGET_ROOT}" apt-get purge -y \
  live-boot live-boot-initramfs-tools live-config live-config-systemd \
  2>/dev/null || true

# 6b. Regenere l'initramfs maintenant que live-boot est purge. Le module
#     Calamares `initramfs` a deja tourne plus tot dans la sequence (avec
#     live-boot encore present) -- sans cette regeneration, l'initrd sur
#     disque resterait celui, contamine, construit avant la purge.
chroot "${TARGET_ROOT}" update-initramfs -u -k all 2>/dev/null || true

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
