// Section SOURCES: depots APT (toggle + retrait), depots connus (ajout),
// remotes Flatpak (toggle). Depots systeme proteges.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ScrollablePage {
    id: page
    title: "Sources"

    property var aptSources: []
    property var presets: []
    property var remotes: []

    // Largeur fixe de la colonne de controle (pour aligner tous les toggles).
    readonly property int ctrlWidth: Kirigami.Units.gridUnit * 6

    function reload() {
        try { page.aptSources = JSON.parse(Backend.list_apt_sources()) } catch (e) { page.aptSources = [] }
        try { page.presets = JSON.parse(Backend.list_source_presets()) } catch (e) { page.presets = [] }
        try { page.remotes = JSON.parse(Backend.list_flatpak_remotes()) } catch (e) { page.remotes = [] }
    }
    Component.onCompleted: reload()

    actions: [
        Kirigami.Action { text: "Actualiser"; icon.name: "view-refresh"; onTriggered: page.reload() }
    ]

    ColumnLayout {
        width: page.width
        spacing: Kirigami.Units.largeSpacing

        // ===================== Depots APT =====================
        Kirigami.Heading {
            level: 3; text: "Dépôts APT"
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.largeSpacing
        }

        Repeater {
            model: page.aptSources
            delegate: Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        source: "repository"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading { level: 5; text: modelData.name }
                        QQC2.Label {
                            text: modelData.file + "  ·  " + modelData.kind
                            font: Kirigami.Theme.smallFont; opacity: 0.6
                        }
                    }
                    // Colonne de controle alignee (largeur fixe).
                    RowLayout {
                        Layout.preferredWidth: page.ctrlWidth
                        Layout.alignment: Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing
                        Item { Layout.fillWidth: true }
                        QQC2.Switch {
                            checked: modelData.enabled
                            onToggled: {
                                applicationWindow().notifyResult(Backend.set_apt_source_enabled(modelData.file, checked))
                                page.reload()
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            visible: modelData.removable
                            opacity: enabled ? 1 : 0
                            QQC2.ToolTip.text: "Retirer le dépôt"
                            QQC2.ToolTip.visible: hovered
                            onClicked: {
                                applicationWindow().notifyResult(Backend.remove_apt_source(modelData.file))
                                page.reload()
                            }
                        }
                    }
                }
            }
        }

        // ===================== Depots connus =====================
        Kirigami.Heading {
            level: 3; text: "Ajouter un dépôt connu"
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            text: "Dépôts officiels sélectionnés (vie privée, liberté, outils utiles). Une fois ajoutés, ils apparaissent dans « Dépôts APT » et peuvent être activés, désactivés ou retirés."
            wrapMode: Text.WordWrap; opacity: 0.75
        }

        Repeater {
            model: page.presets
            delegate: Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    ColumnLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading { level: 5; text: modelData.name }
                        QQC2.Label { Layout.fillWidth: true; text: modelData.description; wrapMode: Text.WordWrap; opacity: 0.8 }
                    }
                    QQC2.Button {
                        Layout.preferredWidth: page.ctrlWidth
                        text: modelData.installed ? "Ajouté" : "Ajouter"
                        icon.name: modelData.installed ? "checkmark" : "list-add"
                        enabled: !modelData.installed
                        onClicked: {
                            applicationWindow().notifyResult(Backend.add_source_preset(modelData.id))
                            page.reload()
                        }
                    }
                }
            }
        }

        QQC2.Button {
            Layout.leftMargin: Kirigami.Units.largeSpacing
            text: "Ajouter un dépôt personnalisé…"
            icon.name: "document-edit"
            onClicked: customDialog.open()
        }

        // ===================== Remotes Flatpak =====================
        Kirigami.Heading {
            level: 3; text: "Remotes Flatpak"
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.largeSpacing
        }

        Repeater {
            model: page.remotes
            delegate: Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        source: "flatpak"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading { level: 5; text: modelData.name }
                        QQC2.Label { text: modelData.url; font: Kirigami.Theme.smallFont; opacity: 0.6; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    RowLayout {
                        Layout.preferredWidth: page.ctrlWidth
                        Layout.alignment: Qt.AlignRight
                        Item { Layout.fillWidth: true }
                        QQC2.Switch {
                            checked: modelData.enabled
                            QQC2.ToolTip.text: "Activer / désactiver (non supprimable)"
                            QQC2.ToolTip.visible: hovered
                            onToggled: {
                                applicationWindow().notifyResult(Backend.set_flatpak_remote_enabled(modelData.name, checked))
                                page.reload()
                            }
                        }
                    }
                }
            }
        }
    }

    // Fenetre d'ajout d'un depot APT personnalise.
    QQC2.Dialog {
        id: customDialog
        title: "Ajouter un dépôt personnalisé"
        modal: true
        parent: QQC2.Overlay.overlay
        width: Math.min(page.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 32)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        standardButtons: QQC2.Dialog.Cancel

        onAccepted: {
            applicationWindow().notifyResult(
                Backend.add_custom_apt_source(customName.text, customBody.text, customKey.text))
            page.reload()
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: "Nom du dépôt :" }
            QQC2.TextField {
                id: customName
                Layout.fillWidth: true
                placeholderText: "mon-depot"
            }
            QQC2.Label { text: "URL de la clé GPG (optionnel) :" }
            QQC2.TextField {
                id: customKey
                Layout.fillWidth: true
                placeholderText: "https://exemple.org/key.asc"
            }
            QQC2.Label { text: "Bloc deb822 :" }
            QQC2.TextArea {
                id: customBody
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                wrapMode: TextEdit.NoWrap
                placeholderText: "Types: deb\nURIs: https://exemple.org/debian\nSuites: trixie\nComponents: main\nSigned-By: /etc/apt/keyrings/mon-depot.asc"
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: "Ajouter le dépôt"
                icon.name: "list-add"
                onClicked: customDialog.accept()
            }
        }
    }
}
