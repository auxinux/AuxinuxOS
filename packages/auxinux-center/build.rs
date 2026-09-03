// Build CXX-Qt: compile le pont Rust et le module QML dans le binaire (qrc).
// Le module QML est expose sous l'URI "ca.auxinux.Center" et charge depuis
// "qrc:/qt/qml/ca/auxinux/Center/qml/main.qml".
use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new()
        .qml_module(QmlModule {
            uri: "ca.auxinux.Center",
            rust_files: &["src/bridge.rs"],
            qml_files: &[
                "qml/main.qml",
                "qml/AppsPage.qml",
                "qml/UpdatesPage.qml",
                "qml/DetailPage.qml",
                "qml/SourcesPage.qml",
                "qml/ConfigPage.qml",
                "qml/SystemPage.qml",
            ],
            ..Default::default()
        })
        .build();
}
