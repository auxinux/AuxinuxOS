#!/usr/bin/env bash
set -uo pipefail

# Configuration du rollback systeme sur le systeme INSTALLE.
#
# Branche dans Calamares via shellprocess@snapshots, APRES shellprocess@cleanup:
# le nettoyage purge live-boot et regenere l'initramfs, donc les entrees de
# menu produites ici pointent sur un initrd propre, et le grub.cfg genere en
# dernier n'est pas ecrase ensuite.
#
# Usage: setup-btrfs-rollback.sh TARGET_ROOT
#   TARGET_ROOT = racine du systeme installe ("/" car dontChroot: false).
#
# Politique d'erreur: ce script NE DOIT PAS faire echouer une installation par
# ailleurs valide -- un systeme sans instantanes reste un systeme utilisable.
# Mais contrairement a post-install-cleanup.sh, il ne masque RIEN: chaque
# echec est trace sur stderr et resume a la fin (voir docs/limitations.md).

TARGET_ROOT="${1:?usage: setup-btrfs-rollback.sh TARGET_ROOT}"
prefix="${TARGET_ROOT%/}"

SNAPPER_CONFIG_DIR="${prefix}/etc/snapper/configs"
SNAPPER_CONFIG="${SNAPPER_CONFIG_DIR}/root"

# Emplacements possibles du modele de configuration snapper.
#
# Debian 13 livre le modele sous /usr/share/snapper/config-templates/default
# et NON sous /etc/snapper/config-templates/default (verifie dans la liste des
# fichiers du paquet). Ne chercher que dans /etc faisait sortir ce script en
# code 0 avec un simple avertissement: aucune config snapper, aucun instantane
# initial, aucun sous-menu GRUB -- le rollback etait absent de CHAQUE systeme
# installe, et la panne n'apparaissait que le jour ou l'utilisateur en avait
# besoin. On cherche donc les deux, et a defaut on ecrit un modele minimal
# plutot que d'abandonner la fonction principale de la distribution.
SNAPPER_TEMPLATE_CANDIDATES="
${prefix}/usr/share/snapper/config-templates/default
${prefix}/etc/snapper/config-templates/default
"

WARNINGS=0

warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "setup-btrfs-rollback: AVERTISSEMENT: $*" >&2
}

info() {
  echo "setup-btrfs-rollback: $*"
}

finish() {
  if [ "${WARNINGS}" -gt 0 ]; then
    echo "setup-btrfs-rollback: termine avec ${WARNINGS} avertissement(s)." >&2
  else
    info "rollback systeme configure."
  fi
  exit 0
}

# 1. Le rollback n'a de sens que sur BTRFS. L'utilisateur a pu choisir ext4 en
#    partitionnement manuel: on sort proprement, sans rien casser.
root_fstype="$(findmnt -no FSTYPE "${TARGET_ROOT}" 2>/dev/null || true)"
if [ "${root_fstype}" != "btrfs" ]; then
  info "racine en '${root_fstype:-inconnu}' et non BTRFS: rollback non configure."
  exit 0
fi

if [ ! -x "${prefix}/usr/bin/snapper" ] && [ ! -x "${prefix}/usr/sbin/snapper" ]; then
  warn "snapper absent du systeme installe; rollback non configure."
  finish
fi

# 2. Config snapper ecrite DIRECTEMENT plutot que via `snapper create-config`.
#    create-config veut creer lui-meme le sous-volume /.snapshots et echoue
#    quand Calamares l'a deja cree et monte (notre cas). Ecrire le fichier de
#    config evite entierement la desactivation/remontage acrobatique.
SNAPPER_TEMPLATE=""
for candidate in ${SNAPPER_TEMPLATE_CANDIDATES}; do
  if [ -f "${candidate}" ]; then
    SNAPPER_TEMPLATE="${candidate}"
    break
  fi
done

mkdir -p "${SNAPPER_CONFIG_DIR}"
if [ ! -f "${SNAPPER_CONFIG}" ]; then
  if [ -n "${SNAPPER_TEMPLATE}" ]; then
    if ! cp "${SNAPPER_TEMPLATE}" "${SNAPPER_CONFIG}"; then
      warn "copie du modele snapper impossible."
      finish
    fi
  else
    # Repli: aucun modele livre par le paquet. Toutes les cles que ce script
    # pilote sont ecrites plus bas par set_cfg; celles-ci sont les valeurs
    # structurelles que snapper attend et qui ne doivent pas rester vides.
    warn "modele snapper introuvable; ecriture d'une configuration minimale."
    cat >"${SNAPPER_CONFIG}" <<'SNAPPER_EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="no"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="no"
TIMELINE_CLEANUP="no"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_QUARTERLY="0"
TIMELINE_LIMIT_YEARLY="10"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
SNAPPER_EOF
    if [ ! -s "${SNAPPER_CONFIG}" ]; then
      warn "ecriture de la configuration snapper impossible."
      finish
    fi
  fi
fi
chmod 0640 "${SNAPPER_CONFIG}" || warn "chmod sur ${SNAPPER_CONFIG} echoue."

set_cfg() {
  local key="$1" value="$2"
  if grep -Eq "^[#[:space:]]*${key}=" "${SNAPPER_CONFIG}"; then
    sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=\"${value}\"|" "${SNAPPER_CONFIG}" \
      || warn "ecriture de ${key} echouee."
  else
    printf '%s="%s"\n' "${key}" "${value}" >>"${SNAPPER_CONFIG}" \
      || warn "ajout de ${key} echoue."
  fi
}

set_cfg SUBVOLUME "/"
set_cfg FSTYPE "btrfs"
# Le groupe sudo peut consulter et comparer les instantanes sans passer root.
set_cfg ALLOW_GROUPS "sudo"
set_cfg SYNC_ACL "yes"

# Instantanes horaires: filet de securite pour les degats qui ne viennent pas
# d'une transaction de paquets (mauvaise manipulation, script tiers).
set_cfg TIMELINE_CREATE "yes"
set_cfg TIMELINE_CLEANUP "yes"
set_cfg TIMELINE_LIMIT_HOURLY "5"
set_cfg TIMELINE_LIMIT_DAILY "7"
set_cfg TIMELINE_LIMIT_WEEKLY "0"
set_cfg TIMELINE_LIMIT_MONTHLY "0"
set_cfg TIMELINE_LIMIT_YEARLY "0"

# Instantanes numerotes: ceux que cree `auxi` avant chaque transaction DEB.
set_cfg NUMBER_CLEANUP "yes"
set_cfg NUMBER_LIMIT "10"
set_cfg NUMBER_LIMIT_IMPORTANT "5"
set_cfg NUMBER_MIN_AGE "1800"
set_cfg EMPTY_PRE_POST_CLEANUP "yes"

# Garde-fous d'espace disque: sans eux, les instantanes remplissent le disque
# en quelques mois et le systeme devient inutilisable -- exactement la panne
# que le rollback est cense eviter.
set_cfg SPACE_LIMIT "0.4"
set_cfg FREE_LIMIT "0.2"

# SPACE_LIMIT et FREE_LIMIT sont INOPERANTS sans les quotas BTRFS: snapper ne
# sait pas mesurer la place occupee par les instantanes tant qu'un qgroup
# n'existe pas. Les deux reglages ci-dessus etaient donc purement decoratifs,
# et seules les limites numeriques retenaient quoi que ce soit. `setup-quota`
# active les quotas et renseigne la cle QGROUP de la configuration.
if ! chroot "${TARGET_ROOT}" snapper --no-dbus -c root setup-quota >/dev/null 2>&1; then
  warn "quotas BTRFS non actives: les limites d'espace des instantanes seront ignorees."
fi

# 3. Declarer la config aupres des services snapper.
if [ -f "${prefix}/etc/default/snapper" ]; then
  if grep -Eq '^SNAPPER_CONFIGS=' "${prefix}/etc/default/snapper"; then
    sed -i -E 's|^SNAPPER_CONFIGS=.*|SNAPPER_CONFIGS="root"|' \
      "${prefix}/etc/default/snapper" || warn "SNAPPER_CONFIGS non ecrit."
  else
    printf 'SNAPPER_CONFIGS="root"\n' >>"${prefix}/etc/default/snapper" \
      || warn "SNAPPER_CONFIGS non ajoute."
  fi
else
  printf 'SNAPPER_CONFIGS="root"\n' >"${prefix}/etc/default/snapper" \
    || warn "/etc/default/snapper non cree."
fi

# 4. /.snapshots ne doit pas etre lisible par tout le monde: il contient une
#    copie complete de /etc, donc des fichiers sensibles (shadow, cles).
if [ -d "${prefix}/.snapshots" ]; then
  chmod 0750 "${prefix}/.snapshots" || warn "chmod sur /.snapshots echoue."
  chown root:root "${prefix}/.snapshots" || warn "chown sur /.snapshots echoue."
else
  warn "/.snapshots absent: le sous-volume @snapshots n'a pas ete monte."
fi

# 5. grub-btrfs: le sous-menu GRUB qui rend le rollback possible MEME quand le
#    systeme ne demarre plus. C'est la difference de fond avec LVM.
GRUB_BTRFS_CONF="${prefix}/etc/default/grub-btrfs/config"
if [ -f "${GRUB_BTRFS_CONF}" ]; then
  if ! grep -q 'AuxiNux OS' "${GRUB_BTRFS_CONF}"; then
    cat >>"${GRUB_BTRFS_CONF}" <<'GRUB_BTRFS_EOF'

# --- AuxiNux OS EN -----------------------------------------------------
# Ces affectations sont ajoutees en fin de fichier: le fichier est source par
# grub-btrfs, donc la derniere valeur l'emporte sur les defauts ci-dessus.
GRUB_BTRFS_SUBMENUNAME="AuxiNux OS - instantanes (restauration)"
GRUB_BTRFS_LIMIT="20"
GRUB_BTRFS_TITLE_FORMAT=("date" "description" "type")
GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND="true"

# Marqueur consomme par le hook initramfs auxinux-snapshot-overlay. Les
# instantanes snapper sont en LECTURE SEULE: sans superposition inscriptible,
# systemd s'arrete des les premieres ecritures et le menu de restauration ne
# menait nulle part. Ce parametre est le seul declencheur du hook, ce qui
# garantit qu'un demarrage normal n'est jamais touche.
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="auxinux.snapshot=1"
GRUB_BTRFS_EOF
  fi
else
  warn "config grub-btrfs introuvable: ${GRUB_BTRFS_CONF}"
fi

# 6. Activation des services. `systemctl enable` dans un chroot se limite a
#    creer des liens symboliques, ce qui fonctionne sans systemd en cours
#    d'execution.
for unit in snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service; do
  if ! chroot "${TARGET_ROOT}" systemctl enable "${unit}" >/dev/null 2>&1; then
    warn "activation de ${unit} echouee."
  fi
done

# 7. Instantane de reference: l'etat exact de la sortie d'usine. C'est le point
#    de retour ultime si tout le reste a ete nettoye par la retention.
#
#    --no-dbus est OBLIGATOIRE ici: snapper parle normalement a snapperd via le
#    bus systeme, or aucun dbus ne tourne dans le chroot d'installation. Sans
#    cette option, la commande echoue systematiquement sur "failed to connect
#    to dbus" et l'installation se termine sans aucun point de restauration --
#    panne silencieuse, visible seulement le jour ou l'utilisateur en a besoin.
if ! chroot "${TARGET_ROOT}" snapper --no-dbus -c root create \
    --description "Installation initiale AuxiNuxOS" \
    --cleanup-algorithm "" \
    --userdata "important=yes" >/dev/null 2>&1; then
  warn "instantane initial non cree."
fi

# 8. Regeneration du menu GRUB, instantanes compris.
if ! chroot "${TARGET_ROOT}" update-grub >/dev/null 2>&1; then
  warn "update-grub echoue: le sous-menu de restauration sera absent."
fi

finish
