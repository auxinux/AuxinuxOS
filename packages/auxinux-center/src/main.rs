//! AuxiNux OS Center — point d'entree.
//!
//! - Sans argument: lance l'interface Kirigami (QML).
//! - `--cli ...`: mode de test du backend sans Qt (voir src/cli.rs).

pub mod bridge;

mod apps;
mod cli;
mod sources;
mod system;
mod util;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(|s| s == "--cli").unwrap_or(false) {
        cli::run(&args[2..]);
        return;
    }

    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();

    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/ca/auxinux/Center/qml/main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
