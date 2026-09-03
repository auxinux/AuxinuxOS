//! Mode CLI de test du backend, sans Qt.
//!
//! Permet de valider toute la logique (recherche, sources, infos systeme) avec
//! un simple `cargo run -- --cli <commande> [args]`, meme sur une machine sans
//! KDE. Affiche le JSON brut renvoye par les modules.
//!
//! Exemples:
//!   auxinux-center --cli search vlc
//!   auxinux-center --cli sources
//!   auxinux-center --cli presets
//!   auxinux-center --cli sysinfo advanced

pub fn run(args: &[String]) {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("help");
    let a = |i: usize| args.get(i).map(|s| s.as_str()).unwrap_or("");

    let out = match cmd {
        "search" => crate::apps::search(a(1)),
        "installed" => crate::apps::list_installed(),
        "install" => crate::apps::install(a(1), if a(2).is_empty() { "flathub" } else { a(2) }),
        "remove" => crate::apps::remove(a(1), if a(2).is_empty() { "flathub" } else { a(2) }),
        "update" => crate::apps::update_app(a(1), if a(2).is_empty() { "flathub" } else { a(2) }),
        "featured" => crate::apps::featured(),
        "details" => crate::apps::app_details(a(1), if a(2).is_empty() { "flathub" } else { a(2) }),
        "status" => crate::apps::app_status(a(1), if a(2).is_empty() { "flathub" } else { a(2) }),
        "sources" => crate::sources::list_apt_sources(),
        "toggle" => crate::sources::set_apt_source_enabled(a(1), a(2) == "on"),
        "presets" => crate::sources::list_source_presets(),
        "add-preset" => crate::sources::add_source_preset(a(1)),
        "remotes" => crate::sources::list_flatpak_remotes(),
        "apt-status" => crate::sources::apt_wrapper_enabled(),
        "sysinfo" => crate::system::info(a(1) == "advanced"),
        _ => {
            eprintln!(
                "commandes: search|installed|install|remove|update|sources|toggle|\
                 presets|add-preset|remotes|apt-status|sysinfo"
            );
            return;
        }
    };
    println!("{out}");
}
