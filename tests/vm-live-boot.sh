#!/usr/bin/env bash
# Banc d'essai « le live demarre-t-il jusqu'au bureau ? », a lancer sur l'hote
# de build.
#
# POURQUOI: ce projet a publie une ISO dont le bureau ne s'ouvrait pas, et l'a
# appris par un utilisateur. La seule preuve qui vaille est une CAPTURE D'ECRAN
# de la session live: le journal peut etre parfaitement propre alors que l'ecran
# est noir (panne du 2026-09-09), et un gestionnaire d'affichage « actif » peut
# tourner en boucle sur du vide.
#
# L'hote de build n'a pas /dev/kvm: QEMU emule (TCG). Un demarrage complet se
# compte donc en MINUTES, pas en secondes. C'est lent, c'est suffisant.
#
# Usage:
#   tests/vm-live-boot.sh --iso CHEMIN [--minutes 12] [--uefi] [--vga std]
#
# Produit dans le repertoire de travail:
#   serial.log      journal de la console serie (noyau + systemd)
#   shot-NNNs.png   captures d'ecran horodatees
#   verdict.txt     resume des signatures trouvees dans le journal
set -uo pipefail

ISO=""
MINUTES=12
FIRMWARE="bios"
VGA="virtio"
WORK="${AUXINUX_VMWORK:-/mnt/build/vm-live}"
MEM="${AUXINUX_VMMEM:-4096}"
CPUS="${AUXINUX_VMCPUS:-4}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso)     ISO="${2:?}"; shift 2 ;;
    --minutes) MINUTES="${2:?}"; shift 2 ;;
    --uefi)    FIRMWARE="uefi"; shift ;;
    --vga)     VGA="${2:?}"; shift 2 ;;
    --work)    WORK="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "argument inconnu: $1" >&2; exit 64 ;;
  esac
done

[[ -r "${ISO}" ]] || { echo "ISO introuvable: ${ISO:-<vide>}" >&2; exit 66; }
command -v qemu-system-x86_64 >/dev/null || { echo "qemu-system-x86_64 manquant" >&2; exit 69; }
command -v socat >/dev/null || { echo "socat manquant (dialogue avec le moniteur QEMU)" >&2; exit 69; }

rm -rf "${WORK}"; mkdir -p "${WORK}"
SERIAL="${WORK}/serial.log"
MON="${WORK}/monitor.sock"

QEMU_ARGS=(
  -machine q35
  -m "${MEM}" -smp "${CPUS}"
  -cdrom "${ISO}" -boot d
  -display none
  -monitor "unix:${MON},server,nowait"
  -serial "file:${SERIAL}"
  -rtc base=utc
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0
)

case "${VGA}" in
  virtio) QEMU_ARGS+=(-device virtio-vga) ;;
  std)    QEMU_ARGS+=(-vga std) ;;
  *) echo "carte video inconnue: ${VGA} (virtio|std)" >&2; exit 64 ;;
esac

if [[ "${FIRMWARE}" == "uefi" ]]; then
  # Les variables OVMF doivent etre INSCRIPTIBLES et propres a cette VM: le
  # fichier livre par le paquet est en lecture seule, et une VM qui ne peut pas
  # ecrire ses variables ne garde aucune entree de demarrage.
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "${WORK}/OVMF_VARS.fd"
  QEMU_ARGS+=(
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd"
    -drive "if=pflash,format=raw,unit=1,file=${WORK}/OVMF_VARS.fd"
  )
fi

echo "== Demarrage de la VM (${FIRMWARE}, vga ${VGA}, ${MEM} Mo, ${CPUS} coeurs, TCG)"
qemu-system-x86_64 "${QEMU_ARGS[@]}" >"${WORK}/qemu.log" 2>&1 &
QEMU_PID=$!
trap 'kill "${QEMU_PID}" 2>/dev/null || true' EXIT

shot() {
  local secs="$1" ppm="${WORK}/shot-${1}s.ppm" png="${WORK}/shot-${1}s.png"
  printf 'screendump %s\n' "${ppm}" | socat - "UNIX-CONNECT:${MON}" >/dev/null 2>&1 || {
    echo "   (moniteur QEMU injoignable a ${secs}s)"; return 1; }
  # Le moniteur repond avant que le fichier soit complet.
  sleep 2
  python3 - "${ppm}" "${png}" <<'PY' 2>/dev/null || return 1
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PY
  rm -f "${ppm}"
  echo "   capture: ${png} ($(stat -c %s "${png}") octets)"
}

# Captures a intervalles croissants: le plus interessant est la fin (bureau ou
# pas), mais une capture precoce distingue « n'a jamais demarre » de
# « a demarre puis a echoue ».
END=$((MINUTES * 60))
NEXT=60
while [[ "${NEXT}" -le "${END}" ]]; do
  sleep 60
  if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
    echo "== QEMU s'est arrete avant la fin (${NEXT}s)"
    break
  fi
  echo "== ${NEXT}s"
  shot "${NEXT}"
  NEXT=$((NEXT + 60))
done

echo "== Analyse du journal serie"
{
  echo "### Signatures d'echec"
  grep -aiE 'kernel panic|BUG: |Oops|start-limit-hit|Failed to start|emergency mode|Cannot open access to console|No such file or directory.*sddm|segfault' \
    "${SERIAL}" | sort -u | head -30
  echo
  echo "### Signatures attendues"
  grep -aiE 'live-boot|Reached target|sddm|plasma|Started Simple Desktop|auxinux' \
    "${SERIAL}" | tail -40
} | tee "${WORK}/verdict.txt"

echo
echo "== Fichiers: ${WORK}"
ls -la "${WORK}"
