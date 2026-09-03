// Section APPS: page d'accueil "A la une" + recherche en tuiles.
// Un clic sur une tuile ouvre la fiche produit (DetailPage).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ca.auxinux.Center

Kirigami.ScrollablePage {
    id: page
    title: "Applications"

    property var apps: []
    property bool busy: false
    property string sectionTitle: ""

    Component { id: detailComp; DetailPage {} }

    Component.onCompleted: loadFeatured()

    function loadFeatured() {
        page.busy = true
        try { page.apps = JSON.parse(Backend.featured()) }
        catch (e) { page.apps = [] }
        finally { page.busy = false }
        page.sectionTitle = "À la une"
    }

    function runSearch() {
        var q = searchField.text.trim()
        if (q.length < 2) { loadFeatured(); return }
        page.busy = true
        try { page.apps = JSON.parse(Backend.search_apps(q)) }
        catch (e) { page.apps = [] }
        finally { page.busy = false }
        page.sectionTitle = "Résultats pour « " + q + " »"
    }

    function showInstalled() {
        page.busy = true
        try { page.apps = JSON.parse(Backend.list_installed()) }
        catch (e) { page.apps = [] }
        finally { page.busy = false }
        page.sectionTitle = "Applications installées"
    }

    header: QQC2.ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            Kirigami.SearchField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Rechercher une application…"
                onAccepted: page.runSearch()
            }
            QQC2.Button {
                text: "Rechercher"
                icon.name: "search"
                onClicked: page.runSearch()
            }
            QQC2.Button {
                text: "Installées"
                icon.name: "view-list-details"
                onClicked: page.showInstalled()
            }
            QQC2.ToolButton {
                icon.name: "go-home"
                QQC2.ToolTip.text: "Accueil"
                QQC2.ToolTip.visible: hovered
                onClicked: { searchField.text = ""; page.loadFeatured() }
            }
        }
    }

    ColumnLayout {
        width: page.width
        spacing: 0

        QQC2.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            running: page.busy
            visible: page.busy
        }

        Kirigami.Heading {
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
            level: 3
            text: page.sectionTitle
            visible: !page.busy && page.apps.length > 0
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 3
            visible: !page.busy && page.apps.length === 0
            icon.name: "applications-all"
            text: "Aucun résultat"
            explanation: "Flathub est la source par défaut. Le dépôt AuxiNux (DEB) est proposé quand il est disponible."
        }

        Kirigami.CardsLayout {
            id: cards
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            maximumColumns: 2

            Repeater {
                model: page.apps
                delegate: Kirigami.AbstractCard {
                    id: tile
                    showClickFeedback: true
                    onClicked: applicationWindow().pageStack.push(detailComp, { appData: modelData })
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Icon {
                            source: modelData.icon && modelData.icon.length > 0
                                    ? modelData.icon
                                    : (modelData.default_source === "flathub" ? "flatpak" : "package-x-generic")
                            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                            Layout.alignment: Qt.AlignTop
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Kirigami.Heading { level: 4; text: modelData.name; elide: Text.ElideRight; Layout.fillWidth: true }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: modelData.summary
                                opacity: 0.8
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    source: modelData.sources.indexOf("flathub") >= 0 ? "flatpak" : "package-x-generic"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }
                                QQC2.Label {
                                    text: modelData.sources.indexOf("flathub") >= 0 ? "Flathub" : "AuxiNux (DEB)"
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
