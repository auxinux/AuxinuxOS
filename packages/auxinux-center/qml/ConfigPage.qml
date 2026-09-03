// Section CONFIGURATION: politique APT maison + raccourcis reglages systeme.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ScrollablePage {
    id: page
    title: "Configuration"

    property bool aptDirect: false

    function reload() {
        try { page.aptDirect = JSON.parse(Backend.apt_wrapper_enabled()).enabled } catch (e) { page.aptDirect = false }
    }
    Component.onCompleted: reload()

    ColumnLayout {
        width: page.width
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: true
            type: Kirigami.MessageType.Information
            text: "AuxiNux OS privilégie Flatpak. Les commandes apt/apt-get/apt-cache sont redirigées vers « auxi » par défaut."
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Kirigami.Separator { Kirigami.FormData.label: "Politique des paquets"; Kirigami.FormData.isSection: true }

            RowLayout {
                Kirigami.FormData.label: "Accès direct à APT :"
                QQC2.Switch {
                    checked: page.aptDirect
                    onToggled: {
                        applicationWindow().notifyResult(Backend.set_apt_wrapper(checked))
                        page.reload()
                    }
                }
                QQC2.Label {
                    text: page.aptDirect ? "Activé (apt non redirigé)" : "Désactivé (apt → auxi)"
                    opacity: 0.7
                }
            }

            Kirigami.Separator { Kirigami.FormData.label: "Réglages du bureau"; Kirigami.FormData.isSection: true }

            QQC2.Button {
                text: "Ouvrir les Réglages COSMIC"
                icon.name: "preferences-system"
                onClicked: Backend.open_system_settings()
            }
            QQC2.Button {
                text: "Voir les mises à jour"
                icon.name: "system-software-update"
                onClicked: applicationWindow().goUpdates()
            }
        }
    }
}
