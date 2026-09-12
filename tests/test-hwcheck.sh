#!/usr/bin/env bash
#
# Tests du controle de configuration requise (packages/auxinux-hwcheck/).
#
# POURQUOI: ce controle a le droit de BLOQUER une installation. Deux erreurs
# opposees, aussi graves l'une que l'autre:
#
#   - trop laxiste: on laisse installer sur une machine qui ne pourra pas
#     faire tourner le systeme, et l'utilisateur decouvre le probleme apres
#     quarante minutes d'installation;
#   - trop strict: on REFUSE une machine parfaitement conforme. Le piege
#     concret est la memoire: une machine vendue avec 4 Go n'annonce jamais
#     4 GiB de MemTotal (firmware, GPU integre, noyau en prelevent). Exiger
#     4,0 GiB refuserait une machine qui respecte le minimum annonce.
#
# /proc et /sys sont simules, glxinfo/vulkaninfo/vainfo remplaces par des
# stubs: on valide les seuils et la regle de decision.
#
# Usage: bash tests/test-hwcheck.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HW="${ROOT}/packages/auxinux-hwcheck/auxinux-hwcheck"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  OK   $1"; else echo "  ECHEC $1: attendu [$3] obtenu [$2]"; fail=1; fi
}

STUBS="${WORK}/bin"; mkdir -p "${STUBS}"
export PATH="${STUBS}:${PATH}"
export AUXINUX_HW_PROC="${WORK}/proc"
export AUXINUX_HW_SYS="${WORK}/sys"

# --- Fabrique de machines ---------------------------------------------------
fake_machine() {
  local ram_kb="$1" cores="$2"
  rm -rf "${AUXINUX_HW_PROC}" "${AUXINUX_HW_SYS}" "${STUBS}"/glxinfo "${STUBS}"/vulkaninfo "${STUBS}"/vainfo
  mkdir -p "${AUXINUX_HW_PROC}" "${AUXINUX_HW_SYS}/block" "${AUXINUX_HW_SYS}/class/drm"
  printf 'MemTotal:       %s kB\nMemFree:  1000 kB\n' "${ram_kb}" > "${AUXINUX_HW_PROC}/meminfo"
  : > "${AUXINUX_HW_PROC}/cpuinfo"
  local i=0
  while [ "${i}" -lt "${cores}" ]; do
    printf 'processor\t: %s\nmodel name\t: CPU de test\n\n' "${i}" >> "${AUXINUX_HW_PROC}/cpuinfo"
    i=$((i + 1))
  done
}
fake_disk() {  # nom, taille_Go
  local n="$1" gb="$2"
  mkdir -p "${AUXINUX_HW_SYS}/block/${n}"
  echo $(( gb * 1024 * 1024 * 2 )) > "${AUXINUX_HW_SYS}/block/${n}/size"
}
fake_gpu() {   # cardN, pilote, vendor, vram_Mo
  local card="$1" drv="$2" vendor="$3" vram_mb="$4"
  mkdir -p "${AUXINUX_HW_SYS}/class/drm/${card}/device" "${AUXINUX_HW_SYS}/drivers/${drv}"
  ln -sfn "${AUXINUX_HW_SYS}/drivers/${drv}" "${AUXINUX_HW_SYS}/class/drm/${card}/device/driver"
  echo "${vendor}" > "${AUXINUX_HW_SYS}/class/drm/${card}/device/vendor"
  [ "${vram_mb}" != "0" ] && echo $(( vram_mb * 1024 * 1024 )) > "${AUXINUX_HW_SYS}/class/drm/${card}/device/mem_info_vram_total"
  # Un connecteur, pour verifier qu'il n'est PAS compte comme une carte.
  mkdir -p "${AUXINUX_HW_SYS}/class/drm/${card}-DP-1"
}
stub_glxinfo() { printf '#!/bin/sh\necho "OpenGL renderer string: %s"\n' "$1" > "${STUBS}/glxinfo"; chmod 755 "${STUBS}/glxinfo"; }
stub_vulkan()  { printf '#!/bin/sh\nexit %s\n' "$1" > "${STUBS}/vulkaninfo"; chmod 755 "${STUBS}/vulkaninfo"; }
stub_vainfo()  { printf '#!/bin/sh\nexit %s\n' "$1" > "${STUBS}/vainfo"; chmod 755 "${STUBS}/vainfo"; }
j() { "${HW}" --json 2>/dev/null | sed -n "s/.*\"$1\": \"\{0,1\}\([^,\"]*\)\"\{0,1\},\{0,1\}.*/\1/p" | head -1; }

echo "== 1. Sous le minimum: installation BLOQUEE =="
fake_machine 2097152 2        # 2 Gio
fake_disk sda 500
"${HW}" >/dev/null 2>&1; rc=$?
check "code de sortie 1" "${rc}" "1"
check "memoire rouge" "$(j ram_verdict)" "rouge"
check "blocage annonce" "$(j install_blocked)" "yes"
check "message explicite" "$("${HW}" 2>/dev/null | grep -c 'INSTALLATION IMPOSSIBLE')" "1"

echo "== 2. Disque trop petit: bloque aussi =="
fake_machine 8388608 4
fake_disk sda 30
"${HW}" >/dev/null 2>&1; rc=$?
check "code de sortie 1" "${rc}" "1"
check "disque rouge" "$(j disk_verdict)" "rouge"

echo "== 3. Machine vendue avec 4 Go: AUTORISEE, en jaune =="
# Le piege: 4 Go annonces = 3,6 GiB de MemTotal. Refuser cette machine serait
# refuser le minimum qu'on annonce soi-meme.
fake_machine 3774873 2
fake_disk sda 40
"${HW}" >/dev/null 2>&1; rc=$?
check "code de sortie 0" "${rc}" "0"
check "memoire jaune, pas rouge" "$(j ram_verdict)" "jaune"
check "processeur jaune" "$(j cpu_verdict)" "jaune"
check "disque jaune" "$(j disk_verdict)" "jaune"
check "message de minimum" "$("${HW}" 2>/dev/null | grep -c 'Installation possible')" "1"

echo "== 4. Juste sous la borne memoire: refusee =="
fake_machine 3774872 2
fake_disk sda 40
check "un kilo-octet de moins bloque" "$(j ram_verdict)" "rouge"

echo "== 5. Machine recommandee =="
fake_machine 16777216 8
fake_disk sda 500
check "memoire verte" "$(j ram_verdict)" "vert"
check "processeur vert" "$(j cpu_verdict)" "vert"
check "disque vert" "$(j disk_verdict)" "vert"

echo "== 6. Choix du disque: le plus grand, et pas n'importe quoi =="
fake_machine 8388608 4
fake_disk sda 120
fake_disk sdb 250
fake_disk loop0 999
fake_disk zram0 800
fake_disk sr0 700
check "le plus grand disque reel" "$(j disk_gb)" "250"
check "peripherique retenu" "$(j disk_device)" "sdb"

echo "== 7. Carte dediee NVIDIA + Vulkan: jeu VERT =="
fake_machine 16777216 8; fake_disk sda 500
fake_gpu card0 nvidia 0x10de 8192
stub_glxinfo "NVIDIA GeForce RTX 4060/PCIe/SSE2"; stub_vulkan 0; stub_vainfo 0
check "une seule carte comptee (pas le connecteur)" "$(j gpu_count)" "1"
check "carte dediee" "$(j gpu_dedicated)" "yes"
check "jeu vert" "$(j gpu_gaming)" "vert"
check "bureautique vert" "$(j gpu_bureautique)" "vert"

echo "== 8. GPU integre Intel: bureautique et multimedia verts, jeu jaune =="
fake_machine 8388608 4; fake_disk sda 200
fake_gpu card0 i915 0x8086 0
stub_glxinfo "Mesa Intel(R) UHD Graphics 620 (KBL GT2)"; stub_vulkan 0; stub_vainfo 0
check "non dediee" "$(j gpu_dedicated)" "no"
check "bureautique vert" "$(j gpu_bureautique)" "vert"
check "multimedia vert (VA-API)" "$(j gpu_multimedia)" "vert"
check "jeu jaune" "$(j gpu_gaming)" "jaune"

echo "== 9. Sans decodage materiel: multimedia jaune =="
stub_vainfo 1
check "multimedia jaune" "$(j gpu_multimedia)" "jaune"

echo "== 10. Machine virtuelle: jeu jaune meme avec un pilote charge =="
fake_machine 8388608 4; fake_disk vda 100
fake_gpu card0 virtio-pci 0x1af4 0
stub_glxinfo "virgl (virtio-gpu)"; stub_vulkan 0; stub_vainfo 0
check "virtualisation detectee" "$(j gpu_virtual)" "yes"
check "jeu jaune" "$(j gpu_gaming)" "jaune"

echo "== 11. Rendu logiciel: tout jaune, et surtout PAS de blocage =="
fake_machine 8388608 4; fake_disk sda 200
fake_gpu card0 i915 0x8086 0
stub_glxinfo "llvmpipe (LLVM 19.1.7, 256 bits)"; stub_vulkan 1; stub_vainfo 1
check "rendu logiciel" "$(j gpu_accel)" "logiciel"
check "bureautique jaune" "$(j gpu_bureautique)" "jaune"
"${HW}" >/dev/null 2>&1; rc=$?
check "installation autorisee quand meme" "${rc}" "0"

echo "== 12. Deux GPU = machine hybride, donc un dedie present =="
fake_machine 16777216 8; fake_disk sda 500
fake_gpu card0 i915 0x8086 0
fake_gpu card1 amdgpu 0x1002 2048
stub_glxinfo "Mesa Intel(R) Graphics"; stub_vulkan 0; stub_vainfo 0
check "deux cartes comptees" "$(j gpu_count)" "2"
check "dediee deduite de l'hybridation" "$(j gpu_dedicated)" "yes"

echo "== 13. Aucun GPU pilote: jaune partout, jamais bloquant =="
fake_machine 8388608 4; fake_disk sda 200
"${HW}" >/dev/null 2>&1; rc=$?
check "code de sortie 0" "${rc}" "0"
check "aucune carte" "$(j gpu_count)" "0"
check "jeu jaune" "$(j gpu_gaming)" "jaune"

echo
if [[ "${fail}" -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "DES TESTS ECHOUENT"; fi
exit "${fail}"
