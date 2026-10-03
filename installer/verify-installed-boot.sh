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
# vide -- puis, surtout, AVEC LE PILOTE DE GRUB LUI-MEME (grub-fstest, point
# 3a). La relecture par Linux ne suffit pas: les deux pilotes ne voient pas le
# meme fichier (voir 3a). C'est le seul moment ou l'on peut encore prevenir
# l'utilisateur pendant qu'il est devant l'installateur, plutot que de le
# laisser decouvrir une machine morte.
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

# Chemin GRUB -> chemin sur le disque monte.
#
# grub.cfg designe les fichiers par rapport au systeme de fichiers qui porte
# /boot: « /@/boot/vmlinuz-... » quand /boot est dans le sous-volume @ (notre
# disposition), « /vmlinuz-... » quand /boot est une partition separee
# (partitionnement manuel). Ne connaitre que le premier cas faisait ECHOUER une
# installation saine a /boot separe.
grub_local_path() {
  local p="$1"
  if [ -f "${prefix}${p#/@}" ]; then
    printf '%s' "${prefix}${p#/@}"
  elif [ -f "${prefix}/boot${p}" ]; then
    printf '%s' "${prefix}/boot${p}"
  else
    printf '%s' "${prefix}${p#/@}"
  fi
}

# 3. Le menu de demarrage doit exister et designer un noyau qui existe
#    VRAIMENT. Un grub.cfg qui pointe sur un fichier absent produit exactement
#    l'ecran d'erreur rapporte.
GRUB_CFG="${prefix}/boot/grub/grub.cfg"
if [ ! -s "${GRUB_CFG}" ]; then
  fail "/boot/grub/grub.cfg absent ou vide — aucun menu de demarrage."
else
  ok "/boot/grub/grub.cfg present"
  missing=0
  while read -r kpath; do
    [ -n "${kpath}" ] || continue
    real="$(grub_local_path "${kpath}")"
    if [ ! -f "${real}" ]; then
      fail "grub.cfg designe ${kpath}, introuvable sur le disque."
      missing=$((missing + 1))
    fi
  done < <(awk '$1 == "linux" { print $2 }' "${GRUB_CFG}" | sort -u)
  [ "${missing}" -eq 0 ] && ok "chaque entree de grub.cfg designe un noyau existant"
fi

# 3a. Relecture PAR LE PILOTE DE GRUB LUI-MEME.
#
#     C'est le controle qui aurait intercepte la panne du 2026-09-13. Tous
#     ceux qui precedent relisent les fichiers avec le noyau Linux; or c'est
#     GRUB qui les lira au demarrage, avec son propre pilote BTRFS, et les
#     deux ne voient pas le meme fichier. Le noyau livre se termine par 512
#     octets de zeros; `rsync -S` (Calamares) en faisait un trou, que Linux lit
#     comme des zeros et devant lequel GRUB 2.12 s'arrete: « fin prematuree du
#     fichier ». Aucune relecture depuis Linux ne pouvait le voir.
#
#     grub-fstest (paquet grub-common) execute le code de GRUB en espace
#     utilisateur, sur le peripherique reel: chaque noyau et initrd designe par
#     grub.cfg doit en ressortir identique, octet pour octet.
BOOT_DEV="$(findmnt -no SOURCE -T "${prefix}/boot" 2>/dev/null | head -n1)"
BOOT_DEV="${BOOT_DEV%%\[*}"
GRUB_FSTEST="${AUXINUX_GRUB_FSTEST:-grub-fstest}"
if [ -s "${GRUB_CFG}" ] && command -v "${GRUB_FSTEST}" >/dev/null 2>&1 &&
   [ -n "${BOOT_DEV}" ] && [ -e "${BOOT_DEV}" ]; then
  grub_read="$(mktemp)"
  while read -r gpath; do
    [ -n "${gpath}" ] || continue
    real="$(grub_local_path "${gpath}")"
    [ -f "${real}" ] || continue   # absence deja signalee au point 3
    # grub-fstest lit le PERIPHERIQUE BRUT, dont Linux garde un cache distinct
    # de celui du systeme de fichiers: il peut encore servir des blocs lus
    # plus tot (grub-probe, grub-mkconfig), d'avant la reecriture de /boot
    # par post-install-cleanup.sh. Constate le 2026-10-02 (installateur
    # maison): « 0 octets relus », puis le fichier entier quelques minutes
    # plus tard, sans que rien n'ait change sur le disque. drop_caches, plus
    # haut, ne suffit pas. On invalide ce cache avant chaque lecture, et une
    # lecture courte est retentee une fois avant de conclure.
    for essai in 1 2; do
      sync
      blockdev --flushbufs "${BOOT_DEV}" 2>/dev/null || true
      rm -f "${grub_read}"
      "${GRUB_FSTEST}" "${BOOT_DEV}" cp "(loop0)${gpath}" "${grub_read}" >/dev/null 2>&1
      cmp -s "${grub_read}" "${real}" && break
      [ "${essai}" -eq 1 ] && sleep 3
    done
    if cmp -s "${grub_read}" "${real}"; then
      ok "${gpath} relu en entier par le pilote de GRUB"
    else
      got="$(stat -c %s "${grub_read}" 2>/dev/null || echo 0)"
      fail "GRUB ne relit que ${got} octets de ${gpath} sur $(stat -c %s "${real}") — il s'arretera sur « fin prematuree du fichier ». Reecrire le fichier sans trou: cp --sparse=never --reflink=never."
    fi
  done < <(awk '$1 == "linux" { print $2 } $1 == "initrd" { for (i = 2; i <= NF; i++) print $i }' \
             "${GRUB_CFG}" | sort -u)
  rm -f "${grub_read}"
else
  echo "verify-installed-boot: grub-fstest indisponible: relecture par GRUB non verifiee." >&2
fi

# 3b. Partition EFI (installation UEFI seulement).
#
#     Le micrologiciel ne lit QUE la partition EFI. Le GRUB signe de Debian qui
#     s'y trouve est une image monolithique: il ne connait pas notre disque et
#     suit le grub.cfg pose a cote de lui, qui designe le systeme de fichiers
#     racine par son UUID. Un UUID perime ou un fichier absent, et la machine
#     s'arrete sur une invite « grub> » avant meme de lire /boot.
ESP="${prefix}/boot/efi"
# Surchargeable UNIQUEMENT pour les tests (tests/test-verify-boot.sh): ils
# doivent pouvoir simuler une machine UEFI comme une machine BIOS, quel que
# soit le micrologiciel de l'hote qui les execute.
EFI_SYSFS="${AUXINUX_EFI_SYSFS:-/sys/firmware/efi}"
if [ -d "${EFI_SYSFS}" ]; then
  root_uuid="$(findmnt -no UUID "${TARGET_ROOT}" 2>/dev/null | head -n1)"
  vendor=""
  fallback=""
  for d in "${ESP}"/EFI/*; do
    [ -d "${d}" ] || continue
    case "$(basename "${d}" | tr '[:lower:]' '[:upper:]')" in
      AUXINUXOS) vendor="${d}" ;;
      BOOT) fallback="${d}" ;;
    esac
  done
  # Deux dispositions legitimes. Le GRUB SIGNE de Debian (avec shim) suit le
  # grub.cfg pose a cote de lui. Le GRUB AUTONOME, construit par
  # l'installateur maison pour un disque chiffre (grub-install
  # --no-uefi-secure-boot: le GRUB signe ne sait pas ouvrir LUKS avant de
  # lire son menu), embarque sa configuration -- deverrouillage et chemin
  # du menu: il n'a pas de grub.cfg, et c'est normal.
  autonome=0
  if [ -n "${vendor}" ] && [ ! -e "${vendor}/shimx64.efi" ] && [ ! -e "${vendor}/grub.cfg" ] &&
     [ -s "${vendor}/grubx64.efi" ] &&
     { grep -aq cryptomount "${vendor}/grubx64.efi" ||
       { [ -n "${root_uuid}" ] && grep -aq "${root_uuid}" "${vendor}/grubx64.efi"; }; }; then
    autonome=1
  fi
  if [ -z "${vendor}" ] || [ ! -s "${vendor}/grubx64.efi" ]; then
    fail "EFI/AuxiNuxOS/grubx64.efi absent de la partition EFI — le micrologiciel n'a rien a demarrer."
  elif [ "${autonome}" -eq 1 ]; then
    ok "partition EFI: GRUB autonome (configuration embarquee: disque chiffre)"
  elif [ ! -s "${vendor}/grub.cfg" ]; then
    fail "EFI/AuxiNuxOS/grub.cfg absent — GRUB s'arreterait sur une invite « grub> »."
  elif [ -n "${root_uuid}" ] && ! grep -q "${root_uuid}" "${vendor}/grub.cfg"; then
    fail "EFI/AuxiNuxOS/grub.cfg ne designe pas la racine installee (UUID ${root_uuid})."
  else
    ok "partition EFI: EFI/AuxiNuxOS complet, grub.cfg designe la racine installee"
  fi
  # Le chemin de secours n'est pas bloquant: l'entree NVRAM suffit a la
  # plupart des machines. Mais son absence se dit.
  if [ -n "${fallback}" ] && ls "${fallback}" 2>/dev/null | grep -qi '^bootx64\.efi$' &&
     { [ -s "${fallback}/grub.cfg" ] || [ "${autonome}" -eq 1 ]; }; then
    ok "partition EFI: chemin de secours EFI/BOOT/BOOTX64.EFI complet"
  else
    echo "verify-installed-boot: AVERTISSEMENT: chemin de secours EFI/BOOT incomplet; une machine qui oublie l'entree NVRAM ne demarrera pas." >&2
  fi
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
