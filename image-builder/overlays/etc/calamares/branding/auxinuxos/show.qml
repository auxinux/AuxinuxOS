/* Slideshow Calamares — AuxiNux OS EN 0.1-BETA */
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0f1724"

            Image {
                id: topBanner
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 120
                fillMode: Image.PreserveAspectCrop
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignTop
                source: "banner-AuxiNuxOS.png"
            }

            Rectangle {
                anchors.top: topBanner.bottom
                anchors.topMargin: 28
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 64, 760)
                height: 210
                radius: 12
                color: "#162033"
                border.width: 1
                border.color: "#334155"

                Column {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 16

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "#f8fafc"
                        font.pixelSize: 28
                        font.bold: true
                        text: "Bienvenue dans l'installateur de AuxiNux OS EN 0.1-BETA"
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "#cbd5e1"
                        font.pixelSize: 18
                        text: "Configuration classique, vie privee elevee, KDE Plasma bilingue et ecosysteme logiciel oriente Flatpak d'abord."
                    }
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0f1724"

            Image {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 120
                fillMode: Image.PreserveAspectCrop
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignTop
                source: "banner-AuxiNuxOS.png"
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 64, 760)
                height: 190
                radius: 12
                color: "#162033"
                border.width: 1
                border.color: "#334155"

                Column {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 16

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "#f8fafc"
                        font.pixelSize: 26
                        font.bold: true
                        text: "Bilingue Canada, sans telemetrie activee"
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "#cbd5e1"
                        font.pixelSize: 18
                        text: "AuxiNuxOS fournit un environnement francais ou anglais, sans telemetrie maison, avec DEB et Flatpak accessibles selon le besoin."
                    }
                }
            }
        }
    }
}
