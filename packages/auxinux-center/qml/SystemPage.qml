// Section SYSTEME: infos de base + avancees.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ScrollablePage {
    id: page
    title: "Système"

    property var info: ({})
    property bool advanced: false

    function reload() {
        try { page.info = JSON.parse(Backend.system_info(page.advanced)) } catch (e) { page.info = ({}) }
    }
    Component.onCompleted: reload()

    actions: [
        Kirigami.Action {
            text: page.advanced ? "Vue simple" : "Vue avancée"
            icon.name: "documentinfo"
            onTriggered: { page.advanced = !page.advanced; page.reload() }
        },
        Kirigami.Action {
            text: "Actualiser"
            icon.name: "view-refresh"
            onTriggered: page.reload()
        }
    ]

    ColumnLayout {
        width: page.width

        Kirigami.FormLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing

            Kirigami.Separator { Kirigami.FormData.label: "Système"; Kirigami.FormData.isSection: true }
            QQC2.Label { Kirigami.FormData.label: "Produit :"; text: page.info.product || "—" }
            QQC2.Label { Kirigami.FormData.label: "Base :"; text: page.info.os || "—" }
            QQC2.Label { Kirigami.FormData.label: "Noyau :"; text: page.info.kernel || "—" }
            QQC2.Label { Kirigami.FormData.label: "Hôte :"; text: page.info.hostname || "—" }
            QQC2.Label { Kirigami.FormData.label: "Architecture :"; text: page.info.arch || "—" }

            Kirigami.Separator { Kirigami.FormData.label: "Matériel"; Kirigami.FormData.isSection: true }
            QQC2.Label { Kirigami.FormData.label: "Processeur :"; text: (page.info.cpu || "—") + " (" + (page.info.cpu_cores || 0) + " cœurs)" }
            QQC2.Label { Kirigami.FormData.label: "Mémoire :"; text: (page.info.memory_used_mb || 0) + " / " + (page.info.memory_total_mb || 0) + " Mo" }

            Kirigami.Separator { Kirigami.FormData.label: "Avancé"; Kirigami.FormData.isSection: true; visible: page.advanced }
            QQC2.Label { visible: page.advanced; Kirigami.FormData.label: "Bureau :"; text: page.info.desktop || "—" }
            QQC2.Label { visible: page.advanced; Kirigami.FormData.label: "Session :"; text: page.info.session_type || "—" }
            QQC2.Label { visible: page.advanced; Kirigami.FormData.label: "GPU :"; text: page.info.gpu || "—" }
            QQC2.Label { visible: page.advanced; Kirigami.FormData.label: "Uptime :"; text: (page.info.uptime_min || 0) + " min" }
            QQC2.Label { visible: page.advanced; Kirigami.FormData.label: "Runtimes Flatpak :"; text: (page.info.flatpak_runtimes !== undefined ? page.info.flatpak_runtimes : "—") }
        }

        Repeater {
            model: page.info.disks || []
            delegate: Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                contentItem: RowLayout {
                    Kirigami.Icon {
                        source: "drive-harddisk"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    }
                    QQC2.Label { Layout.fillWidth: true; text: modelData.mount }
                    QQC2.Label {
                        text: modelData.available_gb + " Go libres / " + modelData.total_gb + " Go"
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
