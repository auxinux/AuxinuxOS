#!/usr/bin/env python3
"""Fiche d'une ISO AuxiNux OS, en JSON, tiree du systeme qu'elle contient.

POURQUOI: le site os.auxinux.ca affichait a la main la version, le noyau et le
nom de l'ISO, et on oubliait de le mettre a jour (le 2026-10-27, il annoncait
encore 0.2.0, Plasma, et un lien en 404). publish-iso.sh publie cette fiche a
cote de l'ISO; le site la lit. Rien n'y est saisi a la main: tout vient du
squashfs de l'ISO elle-meme.

Usage: iso-manifest.py RACINE ARCH NOYAU...
  RACINE  dossier ou ont ete extraits du squashfs var/lib/dpkg/status et
          etc/debian_version
  ARCH    amd64 ou arm64
  NOYAU   noms des fichiers vmlinuz-* de /boot (le plus recent est retenu,
          comme le fait build-image.sh)

publish-iso.sh complete la fiche (fichier, taille, sha256, adresses, date de
publication). Les cles sont stables: le site en depend.
"""
import json
import re
import sys
from pathlib import Path

# Paquets dont la version interesse le public. Absents = non affiches (AuxiMail
# n'existe pas encore en arm64).
PAQUETS = {
    "auxinux-shell": "AuxiNux Shell",
    "auxinux-center": "AuxiNux OS Center",
    "auxi": "auxi",
    "auxioffice": "AuxiOffice",
    "auxitext": "AuxiText",
    "auxi-mail": "AuxiMail",
    "auxicorrect": "AuxiCorrect",
    "auxipak": "AuxiPak",
}

NOMS_DEBIAN = {"13": "trixie", "14": "forky", "15": "duke"}


def lire_status(chemin):
    """Paquets INSTALLES du fichier status de dpkg: {nom: champs}."""
    paquets = {}
    for bloc in chemin.read_text(encoding="utf-8").split("\n\n"):
        champs, cle = {}, None
        for ligne in bloc.splitlines():
            if ligne.startswith((" ", "\t")) and cle:
                champs[cle] += "\n" + ligne[1:]
            elif ":" in ligne:
                cle, _, valeur = ligne.partition(":")
                champs[cle] = valeur.strip()
        if champs.get("Status", "").endswith(" installed") and "Package" in champs:
            paquets[champs["Package"]] = champs
    return paquets


def cle_version(texte):
    # Meme ordre que `sort -V` pour des noms comme vmlinuz-7.2.11-auxinuxos-amd64.
    return [int(p) if p.isdigit() else p for p in re.split(r"(\d+)", texte)]


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    racine, arch, noyaux = Path(sys.argv[1]), sys.argv[2], sys.argv[3:]
    status = lire_status(racine / "var/lib/dpkg/status")

    release = status.get("auxinuxos-release")
    if not release:
        sys.exit("auxinuxos-release absent de l'ISO: fiche impossible")
    edition = release["Version"]                    # 0.4.0+20261024[.2]
    version, _, ident = edition.partition("+")
    m = re.match(r"(\d{4})(\d{2})(\d{2})", ident)
    construite = f"{m[1]}-{m[2]}-{m[3]}" if m else None

    # Description longue = NOUVEAUTES (une ligne par paragraphe, la plus
    # recente en premier); la 1re ligne est le titre.
    description = release.get("Description", "").split("\n")
    nouveautes = [l.strip() for l in description[1:] if l.strip() and l.strip() != "."]

    noyau = sorted((n for n in noyaux if "-auxinuxos-" in n), key=cle_version)
    noyau = noyau[-1].removeprefix("vmlinuz-") if noyau else None
    # 7.2.11-auxinuxos-amd64 -> 7.2.11
    noyau_court = noyau.split("-", 1)[0] if noyau else None

    debian = (racine / "etc/debian_version").read_text().strip()
    majeure = debian.split(".")[0]

    fiche = {
        "schema": 1,
        "produit": "AuxiNux OS",
        "version": version,
        "edition": edition,
        "architecture": arch,
        "construite": construite,
        "debian": {"version": debian, "majeure": majeure, "nom": NOMS_DEBIAN.get(majeure)},
        "noyau": {"version": noyau_court, "complet": noyau},
        "bureau": "AuxiNux Shell",
        "logiciels": [
            {"paquet": p, "nom": nom, "version": status[p]["Version"]}
            for p, nom in PAQUETS.items() if p in status
        ],
        "nouveautes": nouveautes,
    }
    json.dump(fiche, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
