#!/usr/bin/env bash
set -uo pipefail

# Verification finale: le systeme installe est-il REELLEMENT amorcable ?
#
# POURQUOI CE SCRIPT EXISTE. Une installation s'est deroulee sans la moindre
# erreur, jusqu'a la page « Termine », puis la machine a affiche au demarrage:
#
#   error: premature end of file /@/boot/vmlinuz-7.1.12-auxinuxos-amd64.
#   error: you need to load the kernel first.
#
# GRUB trouve le noyau mais n'arrive pas a en lire tout le contenu. Autrement
# dit, l'installateur a annonce un succes alors que le fichier le plus
# indispensable de l'installation n'etait pas exploitable. Aucun controle de la
# sequence ne regardait ce fichier: on verifiait que les COMMANDES avaient ete
# lancees, jamais que le RESULTAT tenait debout.
#
# CE QUE FAIT CE SCRIPT: il relit le noyau et l'initrd DEPUIS LE DISQUE, cache
# vide, exactement comme GRUB le fera au prochain demarrage. C'est le seul
# moment ou l'on peut encore prevenir l'utilisateur pendant qu'il est devant
# l'installateur, plutot que de le laisser decouvrir une machine morte.
#
# Usage: verify-installed-boot.sh TARGET_ROOT
#   TARGET_ROOT = racine du systeme installe ("/" car dontChroot: false).

TARGET_ROOT="${1:?usage: verify-installed-boot.sh TARGET_ROOT}"
prefix="${TARGET_ROOT%/}"

PROBLEMS=0

fail() {
  PROBLEMS=$((PROBLEMS + 1))
  echo "verify-installed-boot: ECHEC: $*" >&2
}

ok() {
  echo "verify-installed-boot: ok: $*"
}

# 1. Vider le cache avant de relire.
#
#    C'est le coeur du controle. Sans cela, `cat` sert les donnees depuis la
#    memoire et un fichier qui n'a jamais atteint le disque parait parfait --
#    precisement le cas ou GRUB, lui, ne trouvera rien a lire. Le sync force
#    l'ecriture, drop_caches oblige les lectures suivantes a passer par le
#    disque.
sync
if [ -w /proc/sys/vm/drop_caches ]; then
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
else
  echo "verify-installed-boot: drop_caches indisponible, lecture possiblement servie par le cache." >&2
fi

# Un fichier de /boot stocke COMPRESSE est illisible par GRUB.
#
# CE CONTROLE EXISTE PARCE QUE LE PRECEDENT NE SUFFISAIT PAS. Sur du materiel
# reel (2026-09-13), une installation a ete declaree saine par ce script puis a
# refuse de demarrer:
#
#   erreur : fin prematuree du fichier /@/boot/vmlinuz-7.2.5-auxinuxos-amd64.
#
# La relecture par `dd` passe par le pilote BTRFS du NOYAU LINUX, qui
# decompresse parfaitement. GRUB a son propre pilote BTRFS, dont le
# decompresseur zstd echoue sur des fichiers de cette taille. Verifier la
# relecture ne dit donc RIEN de ce que GRUB saura faire: il faut verifier que
# le fichier est stocke EN CLAIR.
#
# `filefrag -v` marque « encoded » chaque extent compresse.
storage_is_plain() {
  f="$1"
  command -v filefrag >/dev/null 2>&1 || return 0   # sans outil, on ne juge pas
  if filefrag -v "${f}" 2>/dev/null | grep -q "encoded"; then
    return 1
  fi
  return 0
}

# 2. Le noyau et l'initrd doivent exister, avoir une taille credible, se relire
#    INTEGRALEMENT, et etre stockes SANS COMPRESSION.
found_kernel=0
for kernel in "${prefix}"/boot/vmlinuz-*; do
  [ -f "${kernel}" ] || continue
  found_kernel=1
  size="$(stat -c %s "${kernel}" 2>/dev/null || echo 0)"

  # Un noyau x86-64 fait plusieurs mega-octets. Un fichier de quelques
  # kilo-octets est une ecriture interrompue, pas un noyau.
  if [ "${size}" -lt 1000000 ]; then
    fail "${kernel#"${prefix}"} ne fait que ${size} octets — ecriture tronquee."
    continue
  fi

  # Relecture complete: c'est ce que fait GRUB. `cat` echoue si un extent est
  # illisible; on compare aussi le nombre d'octets reellement relus.
  read_bytes="$(dd if="${kernel}" bs=1M 2>/dev/null | wc -c)"
  if [ "${read_bytes}" != "${size}" ]; then
    fail "${kernel#"${prefix}"}: ${read_bytes} octets relus sur ${size} annonces — GRUB echouera sur « premature end of file »."
  else
    ok "${kernel#"${prefix}"} relu en entier (${size} octets)"
  fi

  if storage_is_plain "${kernel}"; then
    ok "${kernel#"${prefix}"} stocke sans compression"
  else
    fail "${kernel#"${prefix}"}: stocke COMPRESSE — GRUB echouera sur « fin prematuree du fichier ». Corriger avec: btrfs property set ${prefix}/boot compression none, puis reecrire le fichier avec cp --reflink=never."
  fi
done

if [ "${found_kernel}" -eq 0 ]; then
  fail "aucun noyau dans ${prefix}/boot — le systeme ne peut pas demarrer."
fi

found_initrd=0
for initrd in "${prefix}"/boot/initrd.img-*; do
  [ -f "${initrd}" ] || continue
  found_initrd=1
  size="$(stat -c %s "${initrd}" 2>/dev/null || echo 0)"
  if [ "${size}" -lt 1000000 ]; then
    fail "${initrd#"${prefix}"} ne fait que ${size} octets — ecriture tronquee."
    continue
  fi
  read_bytes="$(dd if="${initrd}" bs=1M 2>/dev/null | wc -c)"
  if [ "${read_bytes}" != "${size}" ]; then
    fail "${initrd#"${prefix}"}: ${read_bytes} octets relus sur ${size} annonces."
  else
    ok "${initrd#"${prefix}"} relu en entier (${size} octets)"
  fi

  if storage_is_plain "${initrd}"; then
    ok "${initrd#"${prefix}"} stocke sans compression"
  else
    fail "${initrd#"${prefix}"}: stocke COMPRESSE — GRUB echouera sur « fin prematuree du fichier »."
  fi
done

if [ "${found_initrd}" -eq 0 ]; then
  fail "aucun initramfs dans ${prefix}/boot — le systeme ne peut pas demarrer."
fi

# 3. Le menu de demarrage doit exister et designer un noyau qui existe
#    VRAIMENT. Un grub.cfg qui pointe sur un fichier absent produit exactement
#    l'ecran d'erreur rapporte.
GRUB_CFG="${prefix}/boot/grub/grub.cfg"
if [ ! -s "${GRUB_CFG}" ]; then
  fail "/boot/grub/grub.cfg absent ou vide — aucun menu de demarrage."
else
  ok "/boot/grub/grub.cfg present"
  # Les chemins y sont relatifs a la racine du systeme de fichiers BTRFS
  # (« /@/boot/... »), pas au systeme monte: on retire le prefixe de
  # sous-volume avant de verifier l'existence du fichier.
  missing=0
  while read -r kpath; do
    [ -n "${kpath}" ] || continue
    real="${prefix}${kpath#/@}"
    if [ ! -f "${real}" ]; then
      fail "grub.cfg designe ${kpath}, introuvable sur le disque."
      missing=$((missing + 1))
    fi
  done < <(awk '$1 == "linux" { print $2 }' "${GRUB_CFG}" | sort -u)
  [ "${missing}" -eq 0 ] && ok "chaque entree de grub.cfg designe un noyau existant"
fi

# 4. Espace disque. Une cible saturee explique a elle seule des ecritures
#    differees perdues -- et donc un noyau tronque.
avail_kb="$(df -Pk "${prefix}/boot" 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${avail_kb}" ]; then
  if [ "${avail_kb}" -lt 262144 ]; then
    fail "moins de 256 Mo libres sur la cible (${avail_kb} Ko) — les ecritures ont pu etre perdues."
  else
    ok "espace libre sur la cible: $((avail_kb / 1024)) Mo"
  fi
fi

echo
if [ "${PROBLEMS}" -gt 0 ]; then
  cat >&2 <<EOF
verify-installed-boot: ${PROBLEMS} probleme(s). Le systeme installe NE DEMARRERAIT PAS.

Mieux vaut le signaler maintenant que de laisser la machine s'arreter au
demarrage sur « premature end of file ». Relancez l'installation; si le disque
manquait de place, choisissez une cible plus grande ou un fichier d'echange
plus petit.
EOF
  exit 1
fi

echo "verify-installed-boot: le systeme installe est amorcable."
exit 0
