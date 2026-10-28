#!/usr/bin/env bash
#
# Coherence entre cycle.md (lu par les humains) et cycle.json (lu par le site
# os.auxinux.ca).
#
# POURQUOI: les deux fichiers disent la meme chose sous deux formes. Le site
# affiche cycle.json ; GitHub montre cycle.md. Une date changee dans un seul des
# deux ne casse rien, elle affiche simplement deux calendriers differents.
#
# cycle.json doit etre du JSON valide, au schema 1, et chaque version, chaque
# libelle et chaque date qu'il annonce doit figurer dans cycle.md.
#
# Usage: bash tests/test-cycle.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -I - "${ROOT}/cycle.json" "${ROOT}/cycle.md" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    try:
        c = json.load(f)
    except ValueError as e:
        print(f"  ECHEC cycle.json invalide: {e}")
        sys.exit(1)
with open(sys.argv[2], encoding="utf-8") as f:
    md = f.read()

echecs = 0
def check(label, ok):
    global echecs
    print(f"  {'OK  ' if ok else 'ECHEC'} {label}")
    echecs += not ok

check("schema 1", c.get("schema") == 1)
check(f"mise a jour {c['mise_a_jour']} dans cycle.md",
      f"Dernière mise à jour : {c['mise_a_jour']}" in md)
check("transition majeure dans cycle.md",
      f"**{c['maintenance']['transition_majeure_mois']} mois**" in md)
for d in c["debian"]:
    for champ in ("sortie", "securite_fin", "lts_fin", "libelle"):
        v = d[champ]
        if v is not None:
            check(f"Debian {d['version']} {champ} [{v}]", v in md)
for v in c["versions"]:
    ligne = f"| {v['version']} | Debian {v['debian']} | {v['sortie_libelle']} |"
    check(f"version {v['version']}: ligne du calendrier", ligne in md)
    check(f"version {v['version']}: libelle", v["libelle"].split(" (")[0] in md)
sys.exit(1 if echecs else 0)
PY
