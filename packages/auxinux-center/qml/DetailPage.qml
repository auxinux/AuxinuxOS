// Fiche produit: icone, captures, description, choix de source, actions.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ScrollablePage {
    id: dpage
    title: appData.name || "Application"

    property var appData: ({})
    property var details: ({})
    property var status: ({ installed: false, update_available: false })
    property bool busy: false
    property string currentSource: (appData.default_source && appData.default_source.length > 0)
                                   ? appData.default_source
                                   : ((appData.sources && appData.sources.length > 0) ? appData.sources[0] : "flathub")

    function sourceLabel(s) { return s === "flathub" ? "Flathub (Flatpak)" : "AuxiNux (DEB)" }

    function load() {
        dpage.busy = true
        try { dpage.details = JSON.parse(Backend.app_details(appData.id, currentSource)) }
        catch (e) { dpage.details = ({}) }
        try { dpage.status = JSON.parse(Backend.app_status(appData.id, currentSource)) }
        catch (e) { dpage.status = ({ installed: false, update_available: false }) }
        dpage.busy = false
    }
    Component.onCompleted: load()

    function runAction(action) {
        dpage.busy = true
        try {
            var res
            if (action === "install") res = Backend.install(appData.id, currentSource)
            else if (action === "remove") res = Backend.remove(appData.id, currentSource)
            else res = Backend.update_app(appData.id, currentSource)
            applicationWindow().notifyResult(res)
        } catch (e) {
            applicationWindow().notifyResult('{"ok":false,"message":"erreur QML"}')
        } finally {
            dpage.busy = false
        }
        load() // rafraichit l'etat (installe / mise a jour) et les boutons
    }

    ColumnLayout {
        width: dpage.width
        spacing: Kirigami.Units.largeSpacing

        // --- En-tete ---
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: (details.icon && details.icon.length > 0) ? details.icon
                        : (appData.icon && appData.icon.length > 0 ? appData.icon
                           : (currentSource === "flathub" ? "flatpak" : "package-x-generic"))
                Layout.preferredWidth: Kirigami.Units.iconSizes.enormous
                Layout.preferredHeight: Kirigami.Units.iconSizes.enormous
                Layout.alignment: Qt.AlignTop
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading { level: 1; text: appData.name || ""; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: details.summary || appData.summary || ""
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    QQC2.Label {
                        visible: details.version && details.version.length > 0
                        text: "Version : " + (details.version || "")
                        font: Kirigami.Theme.smallFont; opacity: 0.6
                    }
                    QQC2.Label {
                        visible: details.license && details.license.length > 0
                        text: "Licence : " + (details.license || "")
                        font: Kirigami.Theme.smallFont; opacity: 0.6
                    }
                }
            }
        }

        // --- Source + actions ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: "Source :" }
            QQC2.ComboBox {
                id: sourceBox
                model: appData.sources || ["flathub"]
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                Component.onCompleted: {
                    var i = (appData.sources || []).indexOf(dpage.currentSource)
                    if (i >= 0) currentIndex = i
                }
                displayText: dpage.sourceLabel(model && model[currentIndex] ? model[currentIndex] : dpage.currentSource)
                delegate: QQC2.ItemDelegate {
                    width: sourceBox.width
                    text: dpage.sourceLabel(modelData)
                }
                onActivated: { dpage.currentSource = model[currentIndex]; dpage.load() }
            }

            Item { Layout.fillWidth: true }

            QQC2.Button {
                text: "Installer"
                icon.name: "install"
                visible: !dpage.status.installed
                enabled: !dpage.busy
                onClicked: dpage.runAction("install")
            }
            QQC2.Button {
                text: "Mettre à jour"
                icon.name: "system-software-update"
                visible: dpage.status.installed && dpage.status.update_available
                enabled: !dpage.busy
                highlighted: true
                onClicked: dpage.runAction("update")
            }
            QQC2.Button {
                text: "Désinstaller"
                icon.name: "edit-delete"
                visible: dpage.status.installed
                enabled: !dpage.busy
                onClicked: dpage.runAction("remove")
            }
        }

        QQC2.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: dpage.busy
            visible: dpage.busy
        }

        // --- Capture d'ecran ---
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.preferredHeight: shot.visible ? Math.min(shot.paintedHeight, Kirigami.Units.gridUnit * 22) : 0
            visible: shot.visible

            Image {
                id: shot
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignHCenter
                asynchronous: true
                cache: true
                source: (details.screenshots && details.screenshots.length > 0) ? details.screenshots[0] : ""
                visible: source != "" && status === Image.Ready
            }
        }

        // --- Description ---
        QQC2.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            text: (details.description && details.description.length > 0)
                  ? details.description
                  : (appData.summary || "Aucune description disponible.")
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }

        QQC2.Label {
            visible: details.homepage && details.homepage.length > 0
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            text: '<a href="' + (details.homepage || "") + '">' + (details.homepage || "") + '</a>'
            textFormat: Text.RichText
            onLinkActivated: (link) => Qt.openUrlExternally(link)
        }
    }
}
