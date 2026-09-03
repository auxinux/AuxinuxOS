// Fenetre principale AuxiNux OS Center (Kirigami / COSMIC desktop).
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ApplicationWindow {
    id: root
    title: "AuxiNux OS Center"
    width: 1040
    height: 700
    minimumWidth: 720
    minimumHeight: 480

    // Navigation en colonne unique (une page a la fois) pour eviter l'affichage
    // de plusieurs pages cote a cote.
    Component.onCompleted: {
        pageStack.columnView.columnResizeMode = Kirigami.ColumnView.SingleColumn
    }

    function goPage(comp) {
        pageStack.clear()
        pageStack.push(comp)
    }

    // Named navigation helpers so pages in other files can jump without
    // holding a reference to the Component ids declared here.
    function goUpdates() { goPage(updatesComponent) }
    function goSystemSettings() { Backend.open_system_settings() }

    // Notification helper accessible depuis toutes les pages via applicationWindow().
    function notifyResult(json) {
        var r = { ok: false, message: "" }
        try { r = JSON.parse(json) } catch (e) { r.message = json }
        showPassiveNotification(r.message && r.message.length ? r.message
                                : (r.ok ? "Termine" : "Echec"), "short")
    }

    globalDrawer: Kirigami.GlobalDrawer {
        title: "AuxiNux OS Center"
        titleIcon: "applications-other"
        modal: false
        collapsible: true
        width: Kirigami.Units.gridUnit * 11
        actions: [
            Kirigami.Action {
                text: "Applications"
                icon.name: "applications-all"
                onTriggered: root.goPage(appsComponent)
            },
            Kirigami.Action {
                text: "Mises à jour"
                icon.name: "system-software-update"
                onTriggered: root.goPage(updatesComponent)
            },
            Kirigami.Action {
                text: "Sources"
                icon.name: "repository"
                onTriggered: root.goPage(sourcesComponent)
            },
            Kirigami.Action {
                text: "Configuration"
                icon.name: "configure"
                onTriggered: root.goPage(configComponent)
            },
            Kirigami.Action {
                text: "Système"
                icon.name: "computer-laptop"
                onTriggered: root.goPage(systemComponent)
            }
        ]
    }

    pageStack.initialPage: appsComponent

    Component { id: appsComponent; AppsPage {} }
    Component { id: updatesComponent; UpdatesPage {} }
    Component { id: sourcesComponent; SourcesPage {} }
    Component { id: configComponent; ConfigPage {} }
    Component { id: systemComponent; SystemPage {} }
}
