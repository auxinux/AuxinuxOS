#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_WORK_DIR="/mnt/build/Auxinuxos-normal"
OUTPUT_DIR="${PROJECT_DIR}/image-builder/output"
WORK_DIR="${AUXINUX_NORMAL_BUILD_DIR:-${DEFAULT_WORK_DIR}}"
PROFILE="0.2.0-live"
FORCE=0
REUSE_ROOTFS=0

usage() {
  cat <<EOF
usage: $0 [--work-dir PATH] [--force] [--reuse-rootfs]

Builds AuxiNux OS 0.2.0 live ISO.

Defaults:
  work dir : ${DEFAULT_WORK_DIR}
  output   : ${OUTPUT_DIR}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)
      WORK_DIR="${2:?missing work dir}"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --reuse-rootfs)
      REUSE_ROOTFS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

for tool in mmdebstrap mksquashfs grub-mkrescue xorriso rsync curl mformat; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "missing required tool: ${tool}" >&2
    exit 69
  fi
done

CHROOT_MOUNTS=()

mount_chroot_api_filesystems() {
  sudo install -d -m 0755 "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/dev"

  if ! sudo mountpoint -q "${ROOTFS_DIR}/proc"; then
    sudo mount -t proc proc "${ROOTFS_DIR}/proc"
    CHROOT_MOUNTS+=("${ROOTFS_DIR}/proc")
  fi

  if ! sudo mountpoint -q "${ROOTFS_DIR}/dev"; then
    sudo mount --rbind /dev "${ROOTFS_DIR}/dev"
    sudo mount --make-rslave "${ROOTFS_DIR}/dev" >/dev/null 2>&1 || true
    CHROOT_MOUNTS+=("${ROOTFS_DIR}/dev")
  fi
}

cleanup_chroot_api_filesystems() {
  local index
  for ((index = ${#CHROOT_MOUNTS[@]} - 1; index >= 0; index--)); do
    sudo umount -R "${CHROOT_MOUNTS[index]}" >/dev/null 2>&1 || true
  done
}

trap cleanup_chroot_api_filesystems EXIT

# Refuse de supprimer un repertoire de construction qui porte encore des
# montages.
#
# `--force` faisait `rm -rf` sans rien demonter. Si une construction
# precedente avait ete interrompue en laissant /dev rbind-monte dans le
# rootfs, la suppression TRAVERSAIT ce montage et effacait les noeuds de
# peripheriques de l'HOTE de build. On demonte donc d'abord, et on abandonne
# plutot que d'effacer si un montage resiste.
purge_build_dir() {
  local target="$1" mnt

  [[ -e "${target}" ]] || return 0

  while IFS= read -r mnt; do
    [[ -n "${mnt}" ]] || continue
    sudo umount -R "${mnt}" >/dev/null 2>&1 || sudo umount -Rl "${mnt}" >/dev/null 2>&1 || true
  done < <(findmnt -rno TARGET | awk -v d="${target}" \
             'index($0, d "/") == 1 || $0 == d' | LC_ALL=C sort -r)

  local remaining
  remaining="$(findmnt -rno TARGET | awk -v d="${target}" \
                 'index($0, d "/") == 1 || $0 == d' | head -n1)"
  if [[ -n "${remaining}" ]]; then
    echo "montage encore actif sous ${target}: ${remaining}" >&2
    echo "demontez-le manuellement avant de relancer avec --force" >&2
    exit 73
  fi

  sudo rm -rf "${target}"
}

BUILD_DIR="${WORK_DIR}/${PROFILE}"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ISO_ROOT="${BUILD_DIR}/iso-root"
OUTPUT_ISO="${OUTPUT_DIR}/auxinuxos-0.2.0-amd64.iso"

if [[ "${FORCE}" -eq 1 && "${REUSE_ROOTFS}" -eq 1 ]]; then
  echo "--force and --reuse-rootfs cannot be used together" >&2
  exit 64
fi

if [[ "${FORCE}" -eq 1 ]]; then
  purge_build_dir "${BUILD_DIR}"
fi

if [[ -e "${BUILD_DIR}" && "${REUSE_ROOTFS}" -ne 1 ]]; then
  echo "build directory already exists: ${BUILD_DIR}" >&2
  echo "use --force to rebuild or --reuse-rootfs to resume" >&2
  exit 73
fi

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

package_csv() {
  awk 'NF && $1 !~ /^#/' "$@" | paste -sd,
}

# Listes de paquets. UNE seule declaration sert au bootstrap et a
# l'installation: deux enumerations separees, c'etait deux sources de verite
# pour le meme contenu.
#
# L'image est un SOCLE (decision d'aporler, 2026-10-02): le systeme, KDE
# Plasma et ses outils de base, les codecs, le pare-feu et la couche Windows.
# AUCUNE application d'usage -- navigateur, bureautique, multimedia, jeu, vie
# privee: l'assistant de premier demarrage les propose et les installe, en
# Flatpak de preference. Ce qui ne doit plus etre dans l'image est liste dans
# hors-socle.txt, purge plus bas et refuse par check-rootfs.sh.
BOOTSTRAP_LISTS=(
  base.txt
  firmware.txt
  desktop-plasma.txt
  i18n-canada.txt
  live-installer.txt
  rollback.txt
  performance.txt
  codecs-multimedia.txt
  securite.txt
)
# Ces deux listes ne peuvent PAS etre traitees par mmdebstrap:
#   - couche-windows.txt contient des paquets :i386, et l'architecture
#     etrangere n'est garantie qu'apres le `dpkg --add-architecture` ci-dessous;
#   - auxinux-system.txt contient le noyau, qui vient du depot AuxiNux, qui
#     n'existe qu'apres configure-apt-sources.sh.
EXTRA_LISTS=(
  couche-windows.txt
  auxinux-system.txt
)

list_paths() {
  local name
  for name in "$@"; do
    printf '%s\n' "${PROJECT_DIR}/image-builder/package-lists/${name}"
  done
}

mapfile -t BOOTSTRAP_PATHS < <(list_paths "${BOOTSTRAP_LISTS[@]}")
mapfile -t ALL_PATHS < <(list_paths "${BOOTSTRAP_LISTS[@]}" "${EXTRA_LISTS[@]}")
BASE_PACKAGES="$(package_csv "${BOOTSTRAP_PATHS[@]}")"

if [[ "${REUSE_ROOTFS}" -eq 1 ]]; then
  if [[ ! -e "${ROOTFS_DIR}/etc/os-release" ]]; then
    echo "cannot reuse missing rootfs: ${ROOTFS_DIR}" >&2
    exit 73
  fi
  echo "==> Reusing rootfs: ${ROOTFS_DIR}"
else
  echo "==> Creating Debian 13 rootfs (miroir AuxiNux)"
  # Le miroir AuxiNux et non deb.debian.org: c'est la source declaree des
  # paquets Debian du projet, et c'est celle vers laquelle le systeme installe
  # pointe de toute facon (install-auxinux-sources-DEB.sh). Bootstrapper
  # ailleurs, c'etait construire l'image avec des paquets qui ne sont pas ceux
  # dont la machine recevra ses mises a jour.
  #
  # C'est un VRAI miroir Debian, signe par les cles de l'archive Debian
  # (verifie: 4CB50190207B4758A3F73A796ED0E7B82643E131 et les deux autres
  # signatures de la trixie): mmdebstrap le valide avec
  # debian-archive-keyring exactement comme deb.debian.org. Aucun contournement
  # de verification n'est necessaire, et aucun ne doit etre ajoute.
  # amd64 SEUL au bootstrap: le miroir AuxiNux ne porte pas i386 (verifie le
  # 2026-09-12), donc mmdebstrap echouerait a recuperer binary-i386/Packages.
  # L'architecture i386 est ajoutee juste apres, avec son propre depot
  # (configure-apt-sources.sh), et la couche jeu est installee a ce
  # moment-la.
  sudo mmdebstrap \
    --architectures=amd64 \
    --variant=apt \
    --components=main,contrib,non-free,non-free-firmware \
    --include="${BASE_PACKAGES}" \
    trixie \
    "${ROOTFS_DIR}" \
    https://dep.auxinux.ca/DEBIAN
fi

if [[ -x "${ROOTFS_DIR}/usr/bin/auxi" ]]; then
  echo "==> Temporarily enabling direct APT for build reuse"
  sudo chroot "${ROOTFS_DIR}" /usr/bin/auxi set apt=true
fi

mount_chroot_api_filesystems
# Applications sorties de l'image (hors-socle.txt). Sur un rootfs reutilise,
# les retirer des listes ne les desinstalle pas.
#
# AVANT configure-apt-sources.sh, et pas apres: le paquet brave-browser
# POSSEDE /usr/share/keyrings/brave-browser-archive-keyring.gpg. Purge apres
# coup, il emportait la cle que configure-apt-sources.sh venait de poser, et
# l'assistant ne pouvait plus installer Brave (« Failed to parse keyring »,
# constate en VM le 2026-10-02). On ne purge que ce qui est
# reellement installe: apt-get refuse un nom qu'il ne trouve dans aucun index
# -- c'est le cas de brave-browser, dont le depot est desormais desactive.
mapfile -t HORS_SOCLE < <(awk 'NF && $1 !~ /^#/ {print $1}' \
  "${PROJECT_DIR}/image-builder/package-lists/hors-socle.txt")
mapfile -t HORS_SOCLE_PRESENTS < <(sudo chroot "${ROOTFS_DIR}" \
  dpkg-query -W -f='${binary:Package} ${db:Status-Status}\n' "${HORS_SOCLE[@]}" 2>/dev/null \
  | awk '$2 == "installed" {print $1}')
if [[ "${#HORS_SOCLE_PRESENTS[@]}" -gt 0 ]]; then
  echo "==> Retrait des applications sorties du socle: ${HORS_SOCLE_PRESENTS[*]}"
  sudo chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive \
    apt-get purge -y "${HORS_SOCLE_PRESENTS[@]}"
fi

echo "==> Configuring APT sources"
"${PROJECT_DIR}/image-builder/scripts/configure-apt-sources.sh" "${ROOTFS_DIR}"

echo "==> Installing AuxiNux kernel and applications"
# package_csv strips comment and blank lines; a plain `tr '\n' ' '` would feed
# `#` comment words to apt-get (desktop-base.txt now carries a comment block).
INSTALL_PACKAGES="$(package_csv "${ALL_PATHS[@]}" | tr ',' ' ')"
# i386 doit exister AVANT l'installation: le metapaquet `wine` tire wine32, et
# la couche jeu demande explicitement les bibliotheques Vulkan/GL 32 bits.
# mmdebstrap ne l'ajoute plus (le miroir ne porte pas i386), donc c'est ICI que
# l'architecture entre, avec le depot i386 pose par configure-apt-sources.sh
# juste avant.
if ! sudo chroot "${ROOTFS_DIR}" dpkg --print-foreign-architectures | grep -qx i386; then
  sudo chroot "${ROOTFS_DIR}" dpkg --add-architecture i386
fi
# Mise a jour des index TOUJOURS, et non seulement quand l'architecture vient
# d'etre ajoutee. Sur un rootfs reutilise ou i386 etait deja declare -- par
# exemple apres une construction interrompue -- l'ancienne condition sautait
# cette etape, apt restait sans index i386, et `apt-get install` echouait sur
# « Unable to locate package libvulkan1:i386 » sans expliquer pourquoi.
sudo chroot "${ROOTFS_DIR}" apt-get update

# Mise a jour de TOUT le rootfs, pas seulement des paquets des listes.
#
# Sur un rootfs reutilise, `apt-get install` ci-dessous ne touche qu'aux
# paquets nommes et a leurs dependances: tout le reste garde la version de la
# premiere construction. L'ISO du 2026-09-29 a ainsi ete livree avec 18 mises a
# jour de securite en attente (ghostscript, xserver-xorg-core...), constate en
# VM le 2026-10-02. Sur un rootfs neuf, l'etape ne fait rien.
#
# Memes options que `auxi --yes`: sans terminal, dpkg echoue sur un fichier de
# configuration modifie (« end of file on stdin at conffile prompt ») -- c'est
# le cas de /etc/issue, que l'overlay remplace. Les overlays sont de toute
# facon reappliques plus bas.
sudo chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold

# Une SEULE installation, pilotee par les listes de paquets.
#
# Les blocs `apt-get install` qui suivaient reprenaient a la main dosfstools,
# btrfs-progs, snapper, inotify-tools, wine, la pile Vulkan, zram-tools et
# zenity -- tous deja presents dans les listes. Deux sources de verite pour le
# meme contenu: un paquet retire d'une liste restait installe, un paquet ajoute
# a une liste manquait aux rootfs reutilises, et rien ne le signalait.
sudo chroot "${ROOTFS_DIR}" apt-get install -y --no-install-recommends ${INSTALL_PACKAGES}

# q4wine a ete retire de la couche Windows (interface abandonnee en amont, et
# gestion brute des prefixes). Sur un rootfs reutilise il resterait installe.
sudo chroot "${ROOTFS_DIR}" apt-get purge -y q4wine 2>/dev/null || true

sudo chroot "${ROOTFS_DIR}" apt-get autoremove -y --purge

# Le bureau vient desormais de Debian: voir package-lists/desktop-plasma.txt,
# installe par le bloc apt ci-dessus comme n'importe quel autre paquet.
#
# Ce qui se trouvait ICI a ete supprime avec l'abandon de COSMIC (2026-09-12):
# un depot OBS tiers pour les dependances, puis la compilation de cosmic-epoch
# depuis les sources (cache de 21 Go, plusieurs heures). Le resultat n'etait
# meme pas empaquete -- des fichiers copies dans le rootfs, donc invisibles de
# dpkg: aucune mise a jour du bureau, aucun `apt purge`, et aucun retour
# possible a COSMIC apres un passage a GNOME ou KDE.

echo "==> Installing grub-btrfs from source"
# Absent de Debian 13: sans lui, aucun sous-menu GRUB pour demarrer sur un
# instantane, donc pas de restauration quand le systeme ne demarre plus.
"${PROJECT_DIR}/image-builder/scripts/install-grub-btrfs.sh" \
  "${ROOTFS_DIR}" "${WORK_DIR}/grub-btrfs-cache"

echo "==> Configuring Flatpak"
"${PROJECT_DIR}/image-builder/scripts/configure-flatpak.sh" "${ROOTFS_DIR}"

echo "==> Installing AuxiNux OS Center"
"${PROJECT_DIR}/image-builder/scripts/install-auxinux-center.sh" "${ROOTFS_DIR}"
cleanup_chroot_api_filesystems

echo "==> Applying overlays and AuxiNux tooling"
sudo rsync -a "${PROJECT_DIR}/image-builder/overlays/" "${ROOTFS_DIR}/"
"${PROJECT_DIR}/image-builder/scripts/install-auxi-cli.sh" "${ROOTFS_DIR}"
"${PROJECT_DIR}/image-builder/scripts/configure-branding.sh" "${ROOTFS_DIR}"
sudo chroot "${ROOTFS_DIR}" locale-gen
sudo chroot "${ROOTFS_DIR}" update-locale LANG=fr_CA.UTF-8 LANGUAGE=fr_CA:fr:en_CA:en

echo "auxinuxos-live" | sudo tee "${ROOTFS_DIR}/etc/hostname" >/dev/null
sudo tee "${ROOTFS_DIR}/etc/hosts" >/dev/null <<'EOF'
127.0.0.1 localhost
127.0.1.1 auxinuxos-live
EOF

# UID 60000 et non le 1000 par defaut: le compte live occupe sinon le premier
# UID libre, et le compte cree par Calamares herite du 1001. Apres la
# suppression du compte live, l'utilisateur reel garde un UID decale, ce qui
# casse silencieusement toute restauration de donnees ou tout disque partage
# entre deux installations.
if ! sudo chroot "${ROOTFS_DIR}" id -u auxinux >/dev/null 2>&1; then
  sudo chroot "${ROOTFS_DIR}" useradd -m -s /bin/bash -u 60000 auxinux
fi
printf 'auxinux:auxinux\n' | sudo chroot "${ROOTFS_DIR}" chpasswd
sudo install -d -m 0755 "${ROOTFS_DIR}/etc/sudoers.d" "${ROOTFS_DIR}/home/auxinux/Desktop"
echo 'auxinux ALL=(ALL) NOPASSWD:ALL' | sudo tee "${ROOTFS_DIR}/etc/sudoers.d/90-auxinux-live" >/dev/null
sudo chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/90-auxinux-live"
sudo install -m 0755 "${ROOTFS_DIR}/usr/share/applications/auxinux-install.desktop" "${ROOTFS_DIR}/home/auxinux/Desktop/Install AuxiNuxOS.desktop"
# useradd -m l'a deja copie depuis /etc/skel, sauf sur un rootfs reutilise ou le
# compte live existait deja (voir install-auxinux-center.sh).
sudo rm -f "${ROOTFS_DIR}/home/auxinux/Desktop/AuxiNux OS Center.desktop"
sudo install -m 0755 "${ROOTFS_DIR}/etc/skel/Desktop/AuxiNux OS Center.desktop" "${ROOTFS_DIR}/home/auxinux/Desktop/AuxiNux OS Center.desktop"
sudo chroot "${ROOTFS_DIR}" chown -R auxinux:auxinux /home/auxinux/Desktop

# --- Pas de verrouillage ni d'extinction d'ecran DANS LE LIVE ----------------
#
# PANNE CONSTATEE SUR LE PREMIER ESSAI VM DE LA 0.2.0: le bureau apparaissait,
# puis l'ecran devenait NOIR au bout de dix minutes d'inactivite -- verrouillage
# automatique (notre propre /etc/xdg/kscreenlockerrc) et extinction de l'ecran
# par powerdevil. Sur un medium live, c'est le pire des comportements: le
# visiteur laisse la machine deux minutes, revient devant un ecran noir puis un
# mot de passe qu'il n'a jamais choisi (celui du compte live, ecrit dans un
# README qu'il n'a pas lu). C'est le symptome « ecran noir » que tout ce projet
# cherche a supprimer, reintroduit par un reglage de securite.
#
# On ne touche PAS a /etc/xdg: le systeme INSTALLE doit se verrouiller. On
# ecrit la surcharge dans le dossier personnel du compte live, qui est supprime
# a l'installation -- l'utilisateur cree herite donc du defaut securise, sans
# aucune etape de nettoyage a prevoir.
sudo install -d -m 0755 "${ROOTFS_DIR}/home/auxinux/.config"
sudo tee "${ROOTFS_DIR}/home/auxinux/.config/kscreenlockerrc" >/dev/null <<'EOF'
# Session LIVE uniquement (voir build-image.sh). Le systeme installe utilise
# /etc/xdg/kscreenlockerrc, qui verrouille apres dix minutes.
[Daemon]
Autolock=false
LockOnResume=false
EOF
# Format de Plasma 6 (powerdevilrc), et non plus powermanagementprofilesrc.
#
# L'ancien fichier etait au format de Plasma 5. Plasma 6 le MIGRE a la
# premiere ouverture de session -- en gardant les nombres, alors que l'unite a
# change: `[DimDisplay] idleTime` etait en MILLISECONDES. 86400 est donc devenu
# 86 secondes, et l'ecran du live s'assombrissait au bout d'une minute et demie
# d'inactivite, pendant toute l'installation (constate en VM le 2026-09-29).
# Ici, les actions sont simplement desactivees, dans les trois profils.
sudo tee "${ROOTFS_DIR}/home/auxinux/.config/powerdevilrc" >/dev/null <<'EOF'
# Session LIVE uniquement (voir build-image.sh).
[AC][Display]
DimDisplayWhenIdle=false
TurnOffDisplayWhenIdle=false
LockBeforeTurnOffDisplay=false

[AC][SuspendAndShutdown]
AutoSuspendAction=0

[Battery][Display]
DimDisplayWhenIdle=false
TurnOffDisplayWhenIdle=false
LockBeforeTurnOffDisplay=false

[Battery][SuspendAndShutdown]
AutoSuspendAction=0

[LowBattery][Display]
DimDisplayWhenIdle=false
TurnOffDisplayWhenIdle=false
LockBeforeTurnOffDisplay=false

[LowBattery][SuspendAndShutdown]
AutoSuspendAction=0
EOF
# Un rootfs reutilise garde l'ancien fichier: Plasma le migrerait par-dessus.
sudo rm -f "${ROOTFS_DIR}/home/auxinux/.config/powermanagementprofilesrc"
sudo chroot "${ROOTFS_DIR}" chown -R auxinux:auxinux /home/auxinux/.config
# L'installateur ne s'autodemarre PAS. Il l'a fait tant que le bureau etait
# COSMIC, qui n'affiche aucune icone de bureau; Plasma en affiche (vue
# dossier), donc l'icone « Install AuxiNuxOS » suffit.
#
# Constate sur le premier essai VM de la 0.2.0: les deux fenetres s'ouvraient
# EN MEME TEMPS et se recouvraient -- l'ecran d'accueil (choix de la langue)
# par-dessus le controle de configuration requise. L'utilisateur voyait deux
# boites empilees des la premiere seconde. L'accueil s'ouvre desormais seul, et
# l'installateur quand on le demande.
sudo install -d -m 0755 "${ROOTFS_DIR}/etc/xdg/autostart"
sudo rm -f "${ROOTFS_DIR}/etc/xdg/autostart/auxinux-install.desktop"

# Assistants de premier demarrage a museler dans la session live (assistant de
# creation de cle de KGpg, notificateur de disques). Ils restent lancables
# depuis le menu; ils ne doivent pas s'ouvrir PAR-DESSUS l'installateur au
# demarrage du live.
# calamares-desktop-icon ajoute une deuxieme icone « Install Debian », non
# traduite et sans notre branding, a cote de la notre. AuxiNuxOS fournit son
# propre lanceur (auxinux-install-launcher): on supprime le doublon.
for noisy in org.kde.kgpg org.gnome.SettingsDaemon.DiskUtilityNotify calamares-desktop-icon; do
  if [[ -e "${ROOTFS_DIR}/etc/xdg/autostart/${noisy}.desktop" ]]; then
    echo "Hidden=true" | sudo tee -a "${ROOTFS_DIR}/etc/xdg/autostart/${noisy}.desktop" >/dev/null
  fi
done

# Ecran de connexion: SDDM, greeter en X11 (son defaut dans Debian) et session
# utilisateur en WAYLAND. C'est la combinaison que Debian et KDE testent.
#
# Un greeter Wayland a deja coute deux semaines a ce projet: greetd +
# cosmic-greeter arretait getty@tty1 (Conflicts=), echouait cinq fois, et
# laissait un ecran 100 % noir SANS console de secours -- panne reproduite en
# VM le 2026-09-09. On ne recommence pas avec un greeter experimental.
#
# Xorg est present de toute facon: dans Debian, `sddm` en depend FERMEMENT
# (xserver-xorg | xserver), ce n'est pas un Recommends qu'on pourrait eviter.
sudo install -d -m 0755 "${ROOTFS_DIR}/etc/sddm.conf.d"

# Autologin du LIVE uniquement. post-install-cleanup.sh supprime ce fichier sur
# le systeme installe -- sinon la machine installee ouvrirait une session sans
# mot de passe, sur un compte `auxinux` qui n'existe plus.
#
# Session=plasma est le fichier /usr/share/wayland-sessions/plasma.desktop.
# Ecrire `plasmax11` ici basculerait tout le live en X11 sans que rien ne le
# signale.
sudo tee "${ROOTFS_DIR}/etc/sddm.conf.d/90-auxinux-live-autologin.conf" >/dev/null <<'EOF'
[Autologin]
User=auxinux
Session=plasma
# false: apres une deconnexion, on veut l'ecran de connexion, pas une nouvelle
# session automatique en boucle.
Relogin=false
EOF

# display-manager.service est un lien symbolique, pas un Alias: `systemctl
# enable sddm` ne le cree pas dans un chroot. Sans lui, graphical.target n'a
# aucun gestionnaire d'affichage a demarrer et le systeme s'arrete sur une
# console.
sudo chroot "${ROOTFS_DIR}" ln -sf \
  /usr/lib/systemd/system/sddm.service \
  /etc/systemd/system/display-manager.service
# install -D: /etc/X11 vient de x11-common (dependance de sddm), mais on ne
# fait pas dependre l'ecriture d'un fichier de la presence d'un repertoire
# qu'un tiers doit avoir cree.
printf '/usr/bin/sddm\n' | sudo install -D -m 0644 /dev/stdin \
  "${ROOTFS_DIR}/etc/X11/default-display-manager"

# Tor and OnionShare are available for privacy workflows, but Tor must be
# user-started instead of running by default on every boot.
sudo rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/tor.service"

# Package operations should be user-visible through auxi, not automatic apt
# timers that may run in the background and hit the apt wrapper policy.
#
# `mask` et non la suppression du lien: un `systemctl preset` ou une mise a
# jour du paquet apt recreait le lien, et les timers repartaient sans que rien
# ne le signale. Le masque est un lien vers /dev/null, que rien ne restaure.
for timer in apt-daily.timer apt-daily-upgrade.timer; do
  sudo chroot "${ROOTFS_DIR}" systemctl mask "${timer}" >/dev/null 2>&1 || \
    sudo ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/${timer}"
done

# Fluidite: zram (echange compresse en RAM), systemd-oomd (evite le gel total
# en saturation memoire) et fstrim (entretien des SSD). Les fichiers de
# configuration viennent des overlays, appliques juste avant.
#
# On remonte /proc et /dev le temps de l'activation: `systemctl enable` teste
# /proc/1/root pour detecter le chroot et echoue sans lui. On passe bien par
# systemctl et non par des liens symboliques faits main, parce que
# systemd-oomd.service declare `Also=systemd-oomd.socket` -- un lien pose a la
# main activerait le service sans sa socket.
mount_chroot_api_filesystems
# sddm.service: le lien display-manager.service ci-dessus suffit a
# graphical.target, mais l'activation explicite protege d'un preset qui aurait
# desactive l'unite dans le chroot.
#
# auxinux-boot-arm.service et auxinux-boot-sentinel.service forment la
# protection au demarrage (voir packages/boot-sentinel/README.md): la premiere
# compte les demarrages, la seconde confirme qu'une session graphique s'est
# reellement ouverte.
for unit in zramswap.service systemd-oomd.service fstrim.timer sddm.service \
            auxinux-boot-arm.service auxinux-boot-sentinel.service \
            auxinux-profile.service; do
  if ! sudo chroot "${ROOTFS_DIR}" systemctl enable "${unit}" >/dev/null 2>&1; then
    echo "AVERTISSEMENT: activation de ${unit} echouee." >&2
  fi
done
cleanup_chroot_api_filesystems

sudo install -d -m 0755 "${ROOTFS_DIR}/etc/auxinux"
printf 'APT_ENABLED=0\n' | sudo tee "${ROOTFS_DIR}/etc/auxinux/apt.conf" >/dev/null

# Verification AVANT la compression: chaque fonction annoncee a l'utilisateur
# doit etre reellement presente dans l'image. C'est le controle le moins cher
# qui aurait intercepte l'absence de rollback sur tous les systemes installes.
"${PROJECT_DIR}/image-builder/scripts/check-rootfs.sh" "${ROOTFS_DIR}"

echo "==> Cleaning rootfs"
sudo rm -rf "${ROOTFS_DIR}/var/cache/apt/archives"/*.deb
# install-auxinux-sources-DEB.sh sauvegarde les sources APT existantes a chaque
# execution, dans un repertoire horodate. Sur une construction reprise, l'image
# en accumule plusieurs -- livres a l'utilisateur, qui n'a rien a en faire.
sudo rm -rf "${ROOTFS_DIR}"/etc/apt/auxinux-sources-backup-*
sudo rm -rf "${ROOTFS_DIR}/tmp/"* "${ROOTFS_DIR}/var/tmp/"*

# Defensive cleanup before squashing the rootfs. Some interrupted or nested
# chroot operations can leave proc/dev/sys mounted, which would otherwise make
# mksquashfs try to archive host pseudo-filesystems.
cleanup_chroot_api_filesystems
sudo umount -Rl "${ROOTFS_DIR}/sys" >/dev/null 2>&1 || true
sudo umount -Rl "${ROOTFS_DIR}/run" >/dev/null 2>&1 || true
sudo install -d -m 0755 \
  "${ROOTFS_DIR}/proc" \
  "${ROOTFS_DIR}/sys" \
  "${ROOTFS_DIR}/dev" \
  "${ROOTFS_DIR}/run"

echo "==> Preparing ISO tree"
rm -rf "${ISO_ROOT}"
mkdir -p "${ISO_ROOT}/live" "${ISO_ROOT}/boot/grub"
# `sort -V` et non `sort`: en tri alphabetique, vmlinuz-6.9 passe APRES
# vmlinuz-6.12, et l'ISO embarquerait l'ancien noyau des qu'une version a deux
# chiffres cohabite avec une version a un chiffre.
KERNEL_PATH="$(find "${ROOTFS_DIR}/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)"
INITRD_PATH="$(find "${ROOTFS_DIR}/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -n1)"

if [[ -z "${KERNEL_PATH}" || -z "${INITRD_PATH}" ]]; then
  echo "kernel or initrd not found" >&2
  exit 70
fi

# The current `kernel-auxinuxos` meta-package installs this kernel flavor.
if [[ "${KERNEL_PATH}" != *-auxinuxos-* ]]; then
  echo "selected kernel is not an AuxiNuxOS kernel: ${KERNEL_PATH}" >&2
  exit 70
fi
echo "==> Selected AuxiNuxOS kernel: $(basename "${KERNEL_PATH}")"

cp "${KERNEL_PATH}" "${ISO_ROOT}/live/vmlinuz"
cp "${INITRD_PATH}" "${ISO_ROOT}/live/initrd.img"

# Le systeme INSTALLE est une copie du squashfs. Il DOIT donc contenir /boot
# (noyau + initrd) et /boot/grub, sinon Calamares ne peut pas installer GRUB et
# le systeme ne demarre pas. /tmp doit exister (vide) pour qu'apt fonctionne
# pendant l'installation (bootloader-config). On exclut uniquement les
# pseudo-systemes de fichiers (recrees au demarrage) et le CONTENU de /tmp.
sudo mkdir -p "${ROOTFS_DIR}/boot/grub"
sudo install -d -m 1777 "${ROOTFS_DIR}/tmp"
sudo mksquashfs "${ROOTFS_DIR}" "${ISO_ROOT}/live/filesystem.squashfs" \
  -noappend -comp xz \
  -wildcards \
  -e 'tmp/*' 'proc/*' 'sys/*' 'dev/*' 'run/*'

# pci=noaer pcie_aspm=off: evite la tempete d'erreurs PCIe AER de certaines
# cartes WiFi Atheros (ath10k) qui inonde la console et bloque le boot; le
# WiFi reste fonctionnel. Meme reglage que /etc/default/grub du systeme
# installe.
#
# `quiet splash` a ete retire des entrees de menu, comme sur le systeme
# installe: `splash` est inerte (pas de plymouth dans l'image) et `quiet`
# masque tout, y compris les raisons d'un demarrage qui n'aboutit pas. Un
# medium live sert AUSSI a diagnostiquer une machine: il doit parler.
cat >"${ISO_ROOT}/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0

menuentry "AuxiNux OS 0.2.0 Live" {
    linux /live/vmlinuz boot=live components username=auxinux hostname=auxinuxos-live pci=noaer pcie_aspm=off
    initrd /live/initrd.img
}

menuentry "AuxiNux OS 0.2.0 (graphiques de secours / nomodeset)" {
    linux /live/vmlinuz boot=live components username=auxinux hostname=auxinuxos-live pci=noaer pcie_aspm=off nomodeset
    initrd /live/initrd.img
}

menuentry "AuxiNux OS 0.2.0 (copie en RAM / toram)" {
    linux /live/vmlinuz boot=live components username=auxinux hostname=auxinuxos-live pci=noaer pcie_aspm=off toram
    initrd /live/initrd.img
}
EOF

cat >"${ISO_ROOT}/README.txt" <<'EOF'
AuxiNux OS 0.2.0

Live user: auxinux
Live password: auxinux
EOF

echo "==> Creating ISO"
# grub-mkrescue a ete ABANDONNE ici le 2026-09-13. Il fabrique lui-meme l'image
# EFI avec un GRUB qu'il compile sur place, donc NON SIGNE: sur une machine a
# Secure Boot actif -- la configuration d'usine de la quasi-totalite des
# portables --, le micrologiciel refuse de l'amorcer et l'utilisateur voit une
# machine qui ignore purement et simplement la cle USB.
#
# make-iso.sh assemble l'ISO avec la chaine signee de Debian (shim + GRUB
# signe) et garde l'amorce BIOS. Voir le script pour le detail et les pieges.
"${PROJECT_DIR}/image-builder/scripts/make-iso.sh" \
  "${ISO_ROOT}" "${ROOTFS_DIR}" "${OUTPUT_ISO}"
ls -lh "${OUTPUT_ISO}"
