// Ecran de connexion d'AuxiNux OS (SDDM, API de theme 2.0, Qt 6).
//
// Depuis 2026-10-23 le bureau Plasma n'est plus dans l'image: le theme
// debian-breeze, qui DEPEND de plasma-workspace (Kirigami, composants Plasma),
// part avec lui. Ce theme n'utilise QUE le module QtQuick de base, deja exige
// par le paquet sddm: aucune dependance de plus, rien qui puisse manquer.
//
// Contexte fourni par SDDM: sddm (login, powerOff, reboot, suspend, can*),
// userModel (name, realName, icon; lastIndex), sessionModel (name; lastIndex),
// keyboard (capsLock), config (theme.conf).

import QtQuick 2.15

Rectangle {
    id: root
    width: 1280
    height: 800
    color: "#151b23"

    readonly property color accent: config.accent ? config.accent : "#ef8a12"
    readonly property color texte: "#f2f4f7"
    readonly property color texteDoux: "#b8c0cc"
    readonly property var fr: Qt.locale("fr_CA")

    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool occupe: false

    // Donnees du compte choisi. userModel n'est pas un tableau JS: on passe par
    // un Repeater invisible pour lire ses roles.
    property string userName: ""
    property string userRealName: ""
    property string userIcon: ""
    property string sessionName: ""

    Repeater {
        model: userModel
        delegate: Item {
            visible: false
            Component.onCompleted: if (index === root.userIndex) root.majCompte(model.name, model.realName, model.icon)
            Connections {
                target: root
                function onUserIndexChanged() {
                    if (index === root.userIndex) root.majCompte(model.name, model.realName, model.icon)
                }
            }
        }
    }
    Repeater {
        model: sessionModel
        delegate: Item {
            visible: false
            Component.onCompleted: if (index === root.sessionIndex) root.sessionName = model.name
            Connections {
                target: root
                function onSessionIndexChanged() {
                    if (index === root.sessionIndex) root.sessionName = model.name
                }
            }
        }
    }

    function majCompte(name, realName, icon) {
        userName = name
        userRealName = realName && realName.length > 0 ? realName : name
        userIcon = icon ? icon : ""
    }

    function connecter() {
        var compte = userModel.count > 0 ? userName : saisieCompte.text
        if (compte.length === 0 || occupe)
            return
        occupe = true
        erreur.text = ""
        sddm.login(compte, motDePasse.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            occupe = false
            motDePasse.text = ""
            erreur.text = "Mot de passe incorrect. Réessayez."
            motDePasse.forceActiveFocus()
        }
        function onLoginSucceeded() {
            erreur.text = ""
        }
    }

    // --- Fond: le decor de l'ecran de demarrage -----------------------------
    // Plymouth (theme auxinux) puis ce greeter puis l'ecran d'ouverture du
    // Shell: meme fond et meme logo, le demarrage se lit comme un seul ecran.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#151b23" }
            GradientStop { position: 1.0; color: "#05080c" }
        }
    }

    // --- Logo et heure ---------------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.07
        spacing: 6
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: config.logo ? config.logo : "logo.png"
            width: Math.min(360, root.width * 0.4)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Item { width: 1; height: 10 }
        Text {
            id: heure
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.texte
            font.pixelSize: Math.max(40, root.height * 0.07)
            font.weight: Font.Light
            text: Qt.formatTime(new Date(), "HH' h 'mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.texteDoux
            font.pixelSize: Math.max(16, root.height * 0.024)
            text: new Date().toLocaleDateString(root.fr, "dddd d MMMM yyyy")
        }
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
                heure.text = Qt.formatTime(new Date(), "HH' h 'mm")
                date.text = new Date().toLocaleDateString(root.fr, "dddd d MMMM yyyy")
            }
        }
    }

    // --- Compte et mot de passe ---------------------------------------------
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: parent.height * 0.12
        spacing: 16
        width: 360

        // Avatar: photo du compte, sinon son initiale sur l'accent.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 112; height: 112
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: avatar.status === Image.Ready ? "#2a3340" : root.accent
                Text {
                    anchors.centerIn: parent
                    color: "white"
                    font.pixelSize: 48
                    font.weight: Font.DemiBold
                    visible: avatar.status !== Image.Ready
                    text: (root.userRealName.length > 0 ? root.userRealName : "?").charAt(0).toUpperCase()
                }
            }
            Image {
                id: avatar
                anchors.fill: parent
                anchors.margins: 6
                source: root.userIcon.length === 0 ? "" : (root.userIcon.charAt(0) === "/" ? "file://" + root.userIcon : root.userIcon)
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }
        }

        // Nom du compte; un clic passe au compte suivant s'il y en a plusieurs.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: userModel.count > 0
            color: root.texte
            font.pixelSize: 22
            text: root.userRealName + (userModel.count > 1 ? "  ▾" : "")
            MouseArea {
                anchors.fill: parent
                enabled: userModel.count > 1
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.userIndex = (root.userIndex + 1) % userModel.count
                    motDePasse.text = ""
                    erreur.text = ""
                    motDePasse.forceActiveFocus()
                }
            }
        }

        // Aucun compte liste (UID hors des bornes de 10-auxinux.conf): saisie
        // du nom, plutot qu'un ecran ou l'on ne peut rien faire.
        Champ {
            id: champCompte
            visible: userModel.count === 0
            anchors.horizontalCenter: parent.horizontalCenter
            TextInput {
                id: saisieCompte
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: root.texte
                font.pixelSize: 17
                clip: true
                KeyNavigation.tab: motDePasse
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.text.length === 0
                    color: root.texteDoux
                    font.pixelSize: 17
                    text: "Nom d'utilisateur"
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Champ {
                id: champMdp
                width: 300
                TextInput {
                    id: motDePasse
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: root.texte
                    font.pixelSize: 17
                    clip: true
                    focus: true
                    enabled: !root.occupe
                    onAccepted: root.connecter()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text.length === 0
                        color: root.texteDoux
                        font.pixelSize: 17
                        text: "Mot de passe"
                    }
                }
            }
            Rectangle {
                width: 44; height: 44
                radius: 10
                color: zoneOk.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
                opacity: root.occupe ? 0.5 : 1
                Text {
                    anchors.centerIn: parent
                    color: "white"
                    font.pixelSize: 22
                    text: "→"
                }
                MouseArea {
                    id: zoneOk
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.connecter()
                }
            }
        }

        Text {
            id: erreur
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ffb4a8"
            font.pixelSize: 15
            text: ""
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: keyboard.capsLock
            color: root.accent
            font.pixelSize: 14
            text: "Majuscules activées"
        }
    }

    // --- Bas de l'ecran: bureau et alimentation -------------------------------
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        color: root.texteDoux
        font.pixelSize: 15
        text: "Bureau : " + root.sessionName + (sessionModel.rowCount() > 1 ? "  ▾" : "")
        MouseArea {
            anchors.fill: parent
            enabled: sessionModel.rowCount() > 1
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount()
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        spacing: 36
        Bouton { libelle: "Veille"; visible: sddm.canSuspend; onActive: sddm.suspend() }
        Bouton { libelle: "Redémarrer"; visible: sddm.canReboot; onActive: sddm.reboot() }
        Bouton { libelle: "Éteindre"; visible: sddm.canPowerOff; onActive: sddm.powerOff() }
    }

    component Champ: Rectangle {
        width: 360
        height: 44
        radius: 10
        color: "#cc0b1016"
        border.width: 2
        border.color: activeFocus || children[0].activeFocus ? root.accent : "#4dffffff"
    }

    component Bouton: Text {
        id: bouton
        property string libelle
        signal active()
        color: zone.containsMouse ? root.accent : root.texte
        font.pixelSize: 16
        text: libelle
        MouseArea {
            id: zone
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bouton.active()
        }
    }

    Component.onCompleted: motDePasse.forceActiveFocus()
}
