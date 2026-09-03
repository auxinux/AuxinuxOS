//! Pont CXX-Qt: expose le backend Rust a QML sous l'objet singleton `Backend`
//! (URI QML "ca.auxinux.Center"). Toutes les methodes prennent/retournent des
//! QString (les payloads structures sont du JSON), ce qui garde le pont simple
//! et robuste. Cote QML: `import ca.auxinux.Center` puis `Backend.method(...)`.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        type Backend = super::BackendRust;

        // --- Apps ---
        #[qinvokable]
        fn featured(self: &Backend) -> QString;
        #[qinvokable]
        fn search_apps(self: &Backend, query: &QString) -> QString;
        #[qinvokable]
        fn list_installed(self: &Backend) -> QString;
        #[qinvokable]
        fn list_updates(self: &Backend) -> QString;
        #[qinvokable]
        fn install(self: &Backend, id: &QString, source: &QString) -> QString;
        #[qinvokable]
        fn remove(self: &Backend, id: &QString, source: &QString) -> QString;
        #[qinvokable]
        fn update_app(self: &Backend, id: &QString, source: &QString) -> QString;
        #[qinvokable]
        fn app_details(self: &Backend, id: &QString, source: &QString) -> QString;
        #[qinvokable]
        fn app_status(self: &Backend, id: &QString, source: &QString) -> QString;

        // --- Sources APT ---
        #[qinvokable]
        fn list_apt_sources(self: &Backend) -> QString;
        #[qinvokable]
        fn set_apt_source_enabled(self: &Backend, file: &QString, enabled: bool) -> QString;
        #[qinvokable]
        fn remove_apt_source(self: &Backend, file: &QString) -> QString;
        #[qinvokable]
        fn list_source_presets(self: &Backend) -> QString;
        #[qinvokable]
        fn add_source_preset(self: &Backend, preset: &QString) -> QString;
        #[qinvokable]
        fn add_custom_apt_source(
            self: &Backend,
            name: &QString,
            body: &QString,
            key_url: &QString,
        ) -> QString;

        // --- Remotes Flatpak ---
        #[qinvokable]
        fn list_flatpak_remotes(self: &Backend) -> QString;
        #[qinvokable]
        fn set_flatpak_remote_enabled(self: &Backend, name: &QString, enabled: bool) -> QString;

        // --- Politique APT maison ---
        #[qinvokable]
        fn apt_wrapper_enabled(self: &Backend) -> QString;
        #[qinvokable]
        fn set_apt_wrapper(self: &Backend, enabled: bool) -> QString;

        // --- Systeme ---
        #[qinvokable]
        fn system_info(self: &Backend, advanced: bool) -> QString;
        #[qinvokable]
        fn open_system_settings(self: &Backend);
    }
}

use cxx_qt_lib::QString;

#[derive(Default)]
pub struct BackendRust;

impl qobject::Backend {
    fn featured(&self) -> QString {
        QString::from(crate::apps::featured().as_str())
    }

    fn search_apps(&self, query: &QString) -> QString {
        QString::from(crate::apps::search(&query.to_string()).as_str())
    }

    fn list_installed(&self) -> QString {
        QString::from(crate::apps::list_installed().as_str())
    }

    fn list_updates(&self) -> QString {
        QString::from(crate::apps::list_updates().as_str())
    }

    fn install(&self, id: &QString, source: &QString) -> QString {
        QString::from(crate::apps::install(&id.to_string(), &source.to_string()).as_str())
    }

    fn remove(&self, id: &QString, source: &QString) -> QString {
        QString::from(crate::apps::remove(&id.to_string(), &source.to_string()).as_str())
    }

    fn update_app(&self, id: &QString, source: &QString) -> QString {
        QString::from(crate::apps::update_app(&id.to_string(), &source.to_string()).as_str())
    }

    fn app_details(&self, id: &QString, source: &QString) -> QString {
        QString::from(crate::apps::app_details(&id.to_string(), &source.to_string()).as_str())
    }

    fn app_status(&self, id: &QString, source: &QString) -> QString {
        QString::from(crate::apps::app_status(&id.to_string(), &source.to_string()).as_str())
    }

    fn list_apt_sources(&self) -> QString {
        QString::from(crate::sources::list_apt_sources().as_str())
    }

    fn set_apt_source_enabled(&self, file: &QString, enabled: bool) -> QString {
        QString::from(crate::sources::set_apt_source_enabled(&file.to_string(), enabled).as_str())
    }

    fn remove_apt_source(&self, file: &QString) -> QString {
        QString::from(crate::sources::remove_apt_source(&file.to_string()).as_str())
    }

    fn list_source_presets(&self) -> QString {
        QString::from(crate::sources::list_source_presets().as_str())
    }

    fn add_source_preset(&self, preset: &QString) -> QString {
        QString::from(crate::sources::add_source_preset(&preset.to_string()).as_str())
    }

    fn add_custom_apt_source(&self, name: &QString, body: &QString, key_url: &QString) -> QString {
        QString::from(
            crate::sources::add_custom_apt_source(
                &name.to_string(),
                &body.to_string(),
                &key_url.to_string(),
            )
            .as_str(),
        )
    }

    fn list_flatpak_remotes(&self) -> QString {
        QString::from(crate::sources::list_flatpak_remotes().as_str())
    }

    fn set_flatpak_remote_enabled(&self, name: &QString, enabled: bool) -> QString {
        QString::from(
            crate::sources::set_flatpak_remote_enabled(&name.to_string(), enabled).as_str(),
        )
    }

    fn apt_wrapper_enabled(&self) -> QString {
        QString::from(crate::sources::apt_wrapper_enabled().as_str())
    }

    fn set_apt_wrapper(&self, enabled: bool) -> QString {
        QString::from(crate::sources::set_apt_wrapper(enabled).as_str())
    }

    fn system_info(&self, advanced: bool) -> QString {
        QString::from(crate::system::info(advanced).as_str())
    }

    fn open_system_settings(&self) {
        crate::system::open_system_settings();
    }
}
