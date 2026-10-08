#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?usage: configure-apt-sources.sh ROOTFS}"

# ----------------------------------------------------------------------------
# Empreintes SHA-256 attendues des artefacts telecharges.
#
# A renseigner depuis une source de CONFIANCE hors-bande (release signee,
# annonce officielle), jamais en copiant simplement la valeur servie en ligne.
# Tant qu'une valeur reste "TODO", le telechargement correspondant ECHOUE
# (fail-closed), sauf bypass explicite via AUXINUX_ALLOW_UNVERIFIED=1.
#
# Justification: configure-apt-sources.sh execute en root, dans le chroot, des
# scripts distants qui posent les depots et les cles de tout l'OS (y compris le
# kernel). Sans verification, une compromission de l'hote/CDN injecte du code
# root dans chaque image.
# ----------------------------------------------------------------------------
# Mis a jour le 2026-09-13: le script distant passe de « Architectures: amd64 »
# a « Architectures: amd64 i386 ». La valeur n'est PAS recopiee aveuglement de
# ce qui est servi: le changement a ete fait sur le serveur, et `diff` confirme
# qu'une SEULE ligne differe de la version precedente (77c77).
DEB_SOURCES_SHA256="fc27108b817e85df84f061f29e9a792af897cc828835d093d257212c96c927ac"
AUXINUXOS_KEYRING_SHA256="963f569b4a74f9c76e0c56dd9fa288222b344ff6b102d26fc5eabf6e3ca3f410"
BRAVE_KEYRING_SHA256="c85e85aa3d1783ffaa649ee8dbbc22af7f87192d304602d37e3018226b394788"
BRAVE_SOURCES_SHA256="afb89575e544c6da0e2ba4f850931be800b442507a0ad9be3e12d0439566fb1f"

ALLOW_UNVERIFIED="${AUXINUX_ALLOW_UNVERIFIED:-0}"

# fetch_verified URL DEST EXPECTED_SHA256
fetch_verified() {
  local url="$1" dest="$2" expected="$3"
  sudo curl -fsSL "${url}" -o "${dest}"
  local actual
  actual="$(sha256sum "${dest}" | awk '{print $1}')"

  if [[ "${expected}" == "TODO" ]]; then
    if [[ "${ALLOW_UNVERIFIED}" == "1" ]]; then
      echo "AVERTISSEMENT: ${url}" >&2
      echo "  telecharge SANS verification (AUXINUX_ALLOW_UNVERIFIED=1)." >&2
      echo "  sha256 observe: ${actual}" >&2
      return 0
    fi
    echo "ERREUR: empreinte attendue non renseignee pour ${url}." >&2
    echo "  sha256 observe: ${actual}" >&2
    echo "  -> Renseignez la constante correspondante dans ce script depuis une" >&2
    echo "     source de confiance, ou relancez avec AUXINUX_ALLOW_UNVERIFIED=1" >&2
    echo "     pour ignorer la verification (NON recommande)." >&2
    exit 65
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERREUR: empreinte invalide pour ${url}" >&2
    echo "  attendu: ${expected}" >&2
    echo "  obtenu : ${actual}" >&2
    exit 65
  fi
}

sudo install -d -m 0755 "${ROOTFS}/usr/local/lib/auxinux" "${ROOTFS}/usr/share/keyrings"

# ----------------------------------------------------------------------------
# Neutralise le /etc/apt/sources.list laisse par mmdebstrap.
#
# PANNE OBSERVEE LE 2026-09-12, a la premiere construction depuis le miroir
# AuxiNux: mmdebstrap ecrit un sources.list a l'ancienne
# (« deb https://dep.auxinux.ca/DEBIAN trixie main contrib ... ») qui ne porte
# AUCUNE restriction d'architecture. install-auxinux-sources-DEB.sh ne le
# desactive pas: il ne desactive que les sources contenant « debian.org », et
# dep.auxinux.ca n'y ressemble pas.
#
# Deux consequences:
#   1. chaque cible est declaree deux fois (« configured multiple times »);
#   2. surtout, des que i386 est ajoute comme architecture etrangere, apt
#      reclame dists/trixie/main/binary-i386/Packages au miroir -- qui repond
#      404, faute de miroiter i386 -- et `apt-get update` sort en erreur. La
#      construction s'arretait la, apres 45 minutes de bootstrap.
#
# Le fichier deb822 pose par le script officiel decrit exactement le meme
# miroir avec « Architectures: amd64 »: celui-ci est donc redondant. On le vide
# au lieu de le supprimer, pour qu'un lecteur comprenne ce qui s'est passe.
#
# CE BLOC DOIT RESTER AVANT install-auxinux-sources-DEB.sh: ce script fait son
# PROPRE `apt-get update` a la fin. Place apres lui, la neutralisation arrivait
# trop tard et la construction mourait dans le script distant -- constate sur
# la reprise du 2026-09-12.
if [[ -f "${ROOTFS}/etc/apt/sources.list" ]] &&
   grep -q 'dep\.auxinux\.ca' "${ROOTFS}/etc/apt/sources.list"; then
  sudo tee "${ROOTFS}/etc/apt/sources.list" >/dev/null <<'EOF'
# Volontairement vide.
#
# Les sources d'AuxiNuxOS sont dans /etc/apt/sources.list.d/ au format deb822.
# Le sources.list produit par mmdebstrap au bootstrap a ete neutralise ici
# (image-builder/scripts/configure-apt-sources.sh): il decrivait le meme miroir
# que auxinux-debian.sources, mais SANS restriction d'architecture, ce qui
# faisait echouer `apt-get update` des l'ajout de l'architecture i386 (le
# miroir ne porte pas binary-i386).
EOF
fi


fetch_verified \
  https://dep.auxinux.ca/scripts/install-auxinux-sources-DEB.sh \
  "${ROOTFS}/usr/local/lib/auxinux/install-auxinux-sources-DEB.sh" \
  "${DEB_SOURCES_SHA256}"
sudo chmod 0755 \
  "${ROOTFS}/usr/local/lib/auxinux/install-auxinux-sources-DEB.sh"

sudo chroot "${ROOTFS}" /usr/local/lib/auxinux/install-auxinux-sources-DEB.sh

# AuxiNuxOS kernel repository. Keep this local and pinned so the build cannot
# silently fall back to the retired /VIRTUA repository configuration.
fetch_verified \
  https://dep.auxinux.ca/AUXINUXOS/auxinuxos-archive-keyring.gpg \
  "${ROOTFS}/usr/share/keyrings/auxinuxos-archive-keyring.gpg" \
  "${AUXINUXOS_KEYRING_SHA256}"
sudo tee "${ROOTFS}/etc/apt/sources.list.d/auxinuxos-kernel.list" >/dev/null <<'EOF'
deb [signed-by=/usr/share/keyrings/auxinuxos-archive-keyring.gpg arch=amd64,arm64] https://dep.auxinux.ca/AUXINUXOS kernel main
EOF

# Applications AuxiNux (AuxiNux Office, dont AuxiText, l'editeur de texte de
# l'image). Meme depot racine que le noyau, meme cle de signature (AuxiNux
# Repository <repo@auxinux.ca>, 0E27 7CCF 3E14 E496 3499 3BC9 A042 4AF5 37AB
# 9980): aucune cle de plus a verifier. Actif: auxinux-office est installe dans
# l'image. La suite s'ecrit APPS, en MAJUSCULES: APT respecte la casse.
# Forme fixee par ceux qui publient le depot (2026-10-04).
sudo rm -f "${ROOTFS}/etc/apt/sources.list.d/auxinux-apps.sources.disabled"
sudo tee "${ROOTFS}/etc/apt/sources.list.d/auxinux-apps.sources" >/dev/null <<'EOF'
# Applications AuxiNux: AuxiNux Office (AuxiWriter, AuxiSheet, AuxiPresent,
# AuxiPDF, AuxiText).
Types: deb
URIs: https://dep.auxinux.ca/AUXINUXOS
Suites: APPS
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/auxinuxos-archive-keyring.gpg
EOF

# Noyaux en essai (suite kernel-dev). Livre DESACTIVE: c'est un choix de ceux
# qui veulent tester un noyau avant sa sortie, pas le cas general.
#
# ACTIVER LA SOURCE N'INSTALLE RIEN (corrige le 2026-10-07; ce commentaire
# affirmait le contraire). Le noyau d'essai est un paquet DISTINCT
# (kernel-auxinuxos-dev -> linux-image-<v>-dev-auxinuxos-amd64), qu'aucun paquet
# installe ne demande. On l'installe explicitement: `auxi kernel install
# VERSION`, ou la vue Noyau de la page Applications du centre de controle.
# Ensuite, la mise a jour du systeme suit les nouveaux noyaux d'essai.
# `auxi kernel dev on|off` renomme ce fichier.
sudo rm -f "${ROOTFS}/etc/apt/sources.list.d/auxinuxos-kernel-dev.sources"
sudo tee "${ROOTFS}/etc/apt/sources.list.d/auxinuxos-kernel-dev.sources.disabled" >/dev/null <<'EOF'
# Noyaux d'AuxiNuxOS en cours d'essai. Pour l'activer: sudo auxi kernel dev on,
# ou centre de controle, Applications > Noyau. Puis: auxi kernel list, et
# sudo auxi kernel install VERSION. En cas de probleme, choisir l'ancien noyau
# dans le menu GRUB « Options avancees », ou sudo auxi kernel activate VERSION.
Types: deb
URIs: https://dep.auxinux.ca/AUXINUXOS
Suites: kernel-dev
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/auxinuxos-archive-keyring.gpg
EOF

# ----------------------------------------------------------------------------
# Architecture i386 (couche jeu): elle vient desormais du miroir AuxiNux.
#
# Le 2026-09-13, i386 a ete ajoute au miroir (drop-in systemd
# /etc/systemd/system/auxinux-depot-sync.service.d/10-arches.conf sur le
# serveur de depot: ARCHES=amd64,i386) et le script officiel de sources autorise
# maintenant « Architectures: amd64 i386 ». Verifie: l'index i386 servi par
# dep.auxinux.ca correspond au sha256 annonce par le fichier Release SIGNE PAR
# DEBIAN, et contient 67 026 paquets.
#
# Le depot deb.debian.org epingle a i386 qui se trouvait ici a donc ete retire.
# Il avait deux defauts que le miroir supprime: une divergence de version
# possible entre l'amd64 du miroir et l'i386 de Debian (apt refuse alors
# l'installation multiarch), et sa desactivation silencieuse par
# install-auxinux-sources-DEB.sh, qui desactive toute source contenant
# « debian.org ».
#
# Un reliquat peut trainer sur un rootfs reutilise: on le retire.
sudo rm -f "${ROOTFS}/etc/apt/sources.list.d/debian-i386.sources" \
  "${ROOTFS}/etc/apt/sources.list.d/debian-i386.sources.disabled"

# Brave: methode officielle (brave.com/linux), avec verification d'empreinte.
#
# Le depot est livre DESACTIVE (.disabled) depuis le 2026-10-02: Brave n'est
# plus impose, c'est un choix de l'assistant de premier demarrage. Actif, ce
# depot ferait contacter les serveurs de Brave a chaque `apt update`, chez des
# utilisateurs qui ne s'en servent pas. L'assistant l'active (simple
# renommage, cle deja verifiee ici) quand Brave est choisi -- en DEB et non en
# Flatpak, pour que la politique de confidentialite geree
# (/etc/brave/policies/managed/auxinux-privacy.json) s'applique.
fetch_verified \
  https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
  "${ROOTFS}/usr/share/keyrings/brave-browser-archive-keyring.gpg" \
  "${BRAVE_KEYRING_SHA256}"
fetch_verified \
  https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
  "${ROOTFS}/etc/apt/sources.list.d/brave-browser-release.sources.disabled" \
  "${BRAVE_SOURCES_SHA256}"
sudo rm -f "${ROOTFS}/etc/apt/sources.list.d/brave-browser-release.sources"

sudo chroot "${ROOTFS}" apt-get update
