#!/usr/bin/env python3
"""Genere le diaporama de Calamares (show.qml) depuis installer/diapositives/.

Source UNIQUE des diapositives: l'installateur console les embarque
(include_str!), et Calamares les recoit ici. Ecrire les textes deux fois, c'etait
garantir qu'ils divergent.

La langue suit celle choisie dans Calamares (Qt.locale()): francais si elle
commence par « fr », anglais sinon.

Usage: generate-slideshow.py DOSSIER_DIAPOSITIVES SORTIE_QML
"""
import json
import pathlib
import sys


def lire(chemin):
    diapos = []
    for bloc in chemin.read_text(encoding="utf-8").split("\n---"):
        lignes = [l.strip() for l in bloc.splitlines()]
        lignes = [l for l in lignes if l and not l.startswith("#") and l != "---"]
        if lignes:
            diapos.append((lignes[0], " ".join(lignes[1:])))
    return diapos


def main():
    dossier, sortie = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    fr, en = lire(dossier / "fr.txt"), lire(dossier / "en.txt")
    if len(fr) != len(en) or not fr:
        sys.exit("generate-slideshow: fr.txt et en.txt doivent avoir le meme nombre de diapositives")

    slides = []
    for (tf, xf), (te, xe) in zip(fr, en):
        # json.dumps produit une chaine JavaScript correctement echappee.
        slides.append(f"""
    Slide {{
        Rectangle {{
            anchors.fill: parent
            color: "#0f1724"
            Image {{
                id: bandeau
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 120
                fillMode: Image.PreserveAspectCrop
                source: "banner-AuxiNuxOS.png"
            }}
            Column {{
                anchors.top: bandeau.bottom
                anchors.topMargin: 32
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 64, 760)
                spacing: 18
                Text {{
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#f4bf97"
                    font.pixelSize: 26
                    font.bold: true
                    text: presentation.fr ? {json.dumps(tf, ensure_ascii=False)} : {json.dumps(te, ensure_ascii=False)}
                }}
                Text {{
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#e2e8f0"
                    font.pixelSize: 18
                    text: presentation.fr ? {json.dumps(xf, ensure_ascii=False)} : {json.dumps(xe, ensure_ascii=False)}
                }}
            }}
        }}
    }}""")

    sortie.write_text(f"""/* Diaporama Calamares d'AuxiNux OS.
 * GENERE par image-builder/scripts/generate-slideshow.py depuis
 * installer/diapositives/ -- ne pas modifier ici. */
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {{
    id: presentation
    property bool fr: Qt.locale().name.indexOf("fr") === 0

    Timer {{
        interval: 14000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }}
{"".join(slides)}
}}
""", encoding="utf-8")


if __name__ == "__main__":
    main()
