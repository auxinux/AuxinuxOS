//! Mode CLI du backend, sans interface graphique.
//!
//! Permet de valider toute la logique (recherche, sources, sante, restauration)
//! avec `auxinux-center --cli <commande> [args]`, y compris sur une machine
//! sans aucune pile graphique. Affiche le JSON des modules.
//!
//! Ce mode est aussi le seul disponible quand le binaire est compile avec
//! `--no-default-features` (backend seul).
//!
//! Exemples:
//!   auxinux-center --cli search vlc
//!   auxinux-center --cli sources
//!   auxinux-center --cli health
//!   auxinux-center --cli snapshots
//!   auxinux-center --cli sysinfo advanced
//!   auxinux-center --cli profile

use serde::Serialize;

fn json<T: Serialize>(v: &T) -> String {
    serde_json::to_string_pretty(v).unwrap_or_else(|e| format!("{{\"error\":\"{e}\"}}"))
}

pub fn run(args: &[String]) -> i32 {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("help");
    let a = |i: usize| args.get(i).map(|s| s.as_str()).unwrap_or("");
    let src = |i: usize| {
        if a(i).is_empty() {
            crate::model::SOURCE_FLATHUB
        } else {
            a(i)
        }
    };

    let out = match cmd {
        "search" => json(&crate::apps::search(a(1))),
        "installed" => json(&crate::apps::list_installed()),
        "featured" => json(&crate::apps::featured()),
        "updates" => json(&crate::apps::list_updates()),
        "install" => json(&crate::apps::install(a(1), src(2))),
        "remove" => json(&crate::apps::remove(a(1), src(2))),
        "update" => json(&crate::apps::update_app(a(1), src(2))),
        "details" => json(&crate::apps::app_details(a(1), src(2))),
        "status" => json(&crate::apps::app_status(a(1), src(2))),
        "sources" => json(&crate::sources::list_apt_sources()),
        "toggle" => json(&crate::sources::set_apt_source_enabled(a(1), a(2) == "on")),
        "presets" => json(&crate::sources::list_source_presets()),
        "add-preset" => json(&crate::sources::add_source_preset(a(1))),
        "remotes" => json(&crate::sources::list_flatpak_remotes()),
        "apt-status" => json(&serde_json::json!({
            "enabled": crate::sources::apt_wrapper_enabled()
        })),
        "sysinfo" => json(&crate::system::info(a(1) == "advanced")),
        "health" => json(&crate::health::report()),
        "snapshots" => json(&crate::recovery::state()),
        "profile" => json(&crate::profile::state()),
        "set-profile" => json(&crate::profile::set(a(1))),
        _ => {
            eprintln!(
                "commandes: search|installed|featured|updates|install|remove|update|\n\
                 details|status|sources|toggle|presets|add-preset|remotes|\n\
                 apt-status|sysinfo|health|snapshots|profile|set-profile"
            );
            return 64;
        }
    };
    println!("{out}");
    0
}
