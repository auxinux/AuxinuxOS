#!/usr/bin/env bash
#
# Moteur de l'installateur « Install NOW », en mode --simuler: les commandes
# sont affichees au lieu d'etre executees, les fichiers ecrits dans un
# repertoire jetable. On verifie le PLAN, sans disque.
#
# Cas critiques: rien ne doit toucher au disque avant que toute la
# configuration soit validee, le support d'installation ne doit jamais etre
# choisi comme cible, et un disque chiffre doit rester deverrouillable par
# GRUB (PBKDF2, GRUB non signe avec cryptodisk).
#
# Usage: bash tests/test-install-engine.sh
set -uo pipefail

ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/installer/auxinux-install-engine"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin"
cat >"${T}/bin/lsblk" <<'STUB'
#!/usr/bin/env bash
case " $* " in
  *" TYPE "*) echo disk ;;
  *" PKNAME "*) echo "${STUB_PKNAME:-}" ;;
esac
STUB
cat >"${T}/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
[[ " $* " == *" /run/live/medium "* && -n "${STUB_SUPPORT:-}" ]] && echo "${STUB_SUPPORT}"
exit 0
STUB
chmod +x "${T}/bin/"*
export PATH="${T}/bin:${PATH}"
printf 'motdepasse' >"${T}/mdp"
printf 'phrase' >"${T}/luks"

config() { # surcharges CLE=VALEUR...
  local f="${T}/config"
  {
    echo "DISQUE=/dev/nvme0n1"
    echo "CHIFFREMENT=0"
    echo "LOCALE=fr_CA.UTF-8"
    echo "FUSEAU=America/Toronto"
    echo "CLAVIER=ca"
    echo "VARIANTE_CLAVIER="
    echo "NOM_MACHINE=portable-marie"
    echo "UTILISATEUR=marie"
    echo "NOM_COMPLET=Marie Tremblay"
    echo "MOT_DE_PASSE=${T}/mdp"
    echo "EN_LIGNE=0"
    echo "PROFIL=bureautique"
    echo "APPLICATIONS="
  } >"${f}"
  local kv
  for kv in "$@"; do
    sed -i "/^${kv%%=*}=/d" "${f}"
    echo "${kv}" >>"${f}"
  done
}
simuler() {
  rm -rf "${T}/cible"; mkdir -p "${T}/cible"
  AUXINUX_SIMULATION_CIBLE="${T}/cible" AUXINUX_SIMULATION_EFI="${EFI:-1}" \
    bash "${ENGINE}" "${T}/config" --simuler >"${T}/out" 2>&1
}

fail=0
check() { if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi; }
has() { if grep -qF -- "$2" "${T}/out"; then echo "  OK   $1"; else echo "  ECHEC $1: [$2] absent"; tail -5 "${T}/out" | sed 's/^/         /'; fail=1; fi; }
lacks() { if ! grep -qF -- "$2" "${T}/out"; then echo "  OK   $1"; else echo "  ECHEC $1: [$2] present"; fail=1; fi; }
ligne() { grep -nF -- "$1" "${T}/out" | head -n1 | cut -d: -f1; }

echo "== 1. Configurations refusees AVANT toute action sur le disque =="
for cas in "DISQUE=/dev/nvme0n1;rm" "UTILISATEUR=root" "UTILISATEUR=Marie" "FUSEAU=Mars/Olympus" \
           "LOCALE=de_DE.UTF-8" "NOM_COMPLET=a:b" "PROFIL=serveur" "INCONNUE=1" "CHIFFREMENT=1"; do
  config "${cas}"; simuler; rc=$?
  check "${cas} refuse" "${rc}" "1"
  check "${cas}: aucune commande lancee" "$(grep -c '^SIMULATION:' "${T}/out")" "0"
done

echo "== 2. Le support d'installation n'est jamais une cible =="
config "DISQUE=/dev/sdb"
STUB_SUPPORT=/dev/sdb1 STUB_PKNAME=sdb simuler; rc=$?
check "refus" "${rc}" "1"
has "raison donnee" "est le support d'installation"

echo "== 3. Installation UEFI hors ligne, sans chiffrement =="
config; EFI=1 simuler; rc=$?
check "plan complet" "${rc}" "0"
check "sept etapes" "$(grep -c '^auxinux-etape:' "${T}/out")" "7"
has "trois partitions (bios_grub, EFI, racine)" "-t1:ef02"
has "racine BTRFS" "mkfs.btrfs -f -L AuxiNuxOS /dev/nvme0n1p3"
check "effacement AVANT formatage" "$(( $(ligne 'wipefs -a') < $(ligne 'mkfs.btrfs') ))" "1"
has "sous-volume des instantanes" "btrfs subvolume create /"
has "copie depuis la couche intacte du live" "rsync -aHAX /run/live/rootfs/filesystem.squashfs/"
lacks "jamais de rsync -S (noyau illisible par GRUB)" "rsync -aHAXS"
has "GRUB comme Calamares (signe)" "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=AuxiNuxOS --force"
has "paquets GRUB embarques, pas Internet" "/usr/share/auxinux/installateur/paquets/efi/*.deb"
has "fichiers de configuration ecrits avant le paquet: gardes" "dpkg -i --force-confdef --force-confold"
lacks "hors ligne: pas de mise a jour" "auxi --yes --progress upgrade"
has "scripts de fin communs" "post-install-cleanup.sh /"
has "compte conserve par le nettoyage" "AUXINUX_KEEP_USER=marie"
has "verification d'amorcabilite" "verify-installed-boot.sh /"
check "fstab: racine sur @" "$(grep -c ' / btrfs subvol=/@,' "${T}/cible/etc/fstab")" "1"
check "fstab: instantanes" "$(grep -c ' /.snapshots btrfs subvol=/@snapshots,' "${T}/cible/etc/fstab")" "1"
check "fstab: echange sans compression" "$(grep ' /swap btrfs' "${T}/cible/etc/fstab" | grep -c compress)" "0"
check "langue" "$(grep '^LANG=' "${T}/cible/etc/default/locale")" "LANG=fr_CA.UTF-8"
check "clavier" "$(grep '^XKBLAYOUT=' "${T}/cible/etc/default/keyboard")" 'XKBLAYOUT="ca"'
check "profil" "$(cat "${T}/cible/etc/auxinux/profile")" "bureautique"
check "pas de crypttab" "$([[ -e "${T}/cible/etc/crypttab" ]] && echo oui || echo non)" "non"

echo "== 4. Chiffrement: deverrouillable par GRUB =="
config "CHIFFREMENT=1" "CLE_LUKS=${T}/luks"; EFI=1 simuler; rc=$?
check "plan complet" "${rc}" "0"
has "LUKS2 en PBKDF2 (GRUB ne lit pas Argon2)" "luksFormat --batch-mode --type luks2 --pbkdf pbkdf2"
has "BTRFS sur le volume dechiffre" "mkfs.btrfs -f -L AuxiNuxOS /dev/mapper/auxinux-racine"
has "GRUB avec cryptodisk (non signe)" "--bootloader-id=AuxiNuxOS --no-uefi-secure-boot --force"
has "chemin de secours EFI/BOOT" "--removable --no-uefi-secure-boot"
has "outils LUKS embarques" "paquets/luks/*.deb"
check "crypttab avec cle interne" "$(grep -c 'auxinux-racine UUID=.* /crypto_keyfile.bin luks' "${T}/cible/etc/crypttab")" "1"
check "GRUB_ENABLE_CRYPTODISK" "$(grep -c '^GRUB_ENABLE_CRYPTODISK=y' "${T}/cible/etc/default/grub")" "1"

echo "== 5. BIOS =="
config; EFI=0 simuler
has "GRUB BIOS sur le disque" "grub-install --target=i386-pc /dev/nvme0n1"
has "paquet grub-pc embarque" "paquets/bios/*.deb"

echo "== 6. En ligne: mises a jour puis applications =="
config "EN_LIGNE=1" "APPLICATIONS=--brave --flatpak org.videolan.VLC"; simuler
check "neuf etapes" "$(grep -c '^auxinux-etape:' "${T}/out")" "9"
has "mises a jour" "auxi --yes --progress upgrade --deb"
has "applications par le programme de l'assistant" "auxinux-assistant-apply --brave --flatpak org.videolan.VLC"
check "mises a jour AVANT le nettoyage final" "$(( $(ligne 'upgrade --deb') < $(ligne 'post-install-cleanup.sh') ))" "1"

if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "ECHEC"; fi
exit "${fail}"
