// Section MISES A JOUR: liste consolidee Flatpak + DEB, avec mise a jour
// unitaire ou globale. Branchee sur Backend.list_updates()/update_app().
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ScrollablePage {
    id: page
    title: "Mises à jour"

    property var updates: []
    property bool busy: false
    property bool working: false

    Component.onCompleted: refresh()

    function refresh() {
        page.busy = true
        try { page.updates = JSON.parse(Backend.list_updates()) }
        catch (e) { page.updates = [] }
        finally { page.busy = false }
    }

    function updateOne(item) {
        page.working = true
        var res = Backend.update_app(item.id, item.default_source)
        applicationWindow().notifyResult(res)
        page.working = false
        page.refresh()
    }

    function updateAll() {
        page.working = true
        for (var i = 0; i < page.updates.length; i++) {
            var it = page.updates[i]
            Backend.update_app(it.id, it.default_source)
        }
        applicationWindow().showPassiveNotification("Mises à jour terminées", "short")
        page.working = false
        page.refresh()
    }

    header: QQC2.ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                level: 4
                text: page.updates.length > 0
                      ? page.updates.length + " mise(s) à jour"
                      : "Mises à jour"
                Layout.fillWidth: true
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                QQC2.ToolTip.text: "Vérifier"
                QQC2.ToolTip.visible: hovered
                enabled: !page.busy && !page.working
                onClicked: page.refresh()
            }
            QQC2.Button {
                text: "Tout mettre à jour"
                icon.name: "system-software-update"
                enabled: page.updates.length > 0 && !page.working
                onClicked: page.updateAll()
            }
        }
    }

    ColumnLayout {
        width: page.width
        spacing: 0

        QQC2.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            running: page.busy || page.working
            visible: page.busy || page.working
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 3
            visible: !page.busy && !page.working && page.updates.length === 0
            icon.name: "checkmark"
            text: "Tout est à jour"
            explanation: "Aucune mise à jour d'application ou de paquet n'est disponible."
        }

        Repeater {
            model: page.updates
            delegate: Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        source: modelData.icon && modelData.icon.length > 0
                                ? modelData.icon
                                : (modelData.default_source === "flathub" ? "flatpak" : "package-x-generic")
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Kirigami.Heading { level: 4; text: modelData.name; elide: Text.ElideRight; Layout.fillWidth: true }
                        QQC2.Label {
                            text: (modelData.default_source === "flathub" ? "Flathub" : "AuxiNux (DEB)")
                                  + (modelData.version ? "  ·  " + modelData.version : "")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    QQC2.Button {
                        text: "Mettre à jour"
                        icon.name: "system-software-update"
                        enabled: !page.working
                        onClicked: page.updateOne(modelData)
                    }
                }
            }
        }
    }
}
