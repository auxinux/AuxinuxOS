//! AuxiNux OS Center — centre de controle d'AuxiNux OS.
//!
//! - Sans argument: interface libcosmic (necessite la feature "gui").
//! - `--cli ...`: backend seul, sortie JSON (voir src/cli.rs).
//!
//! L'interface est derriere une feature pour que `cargo check
//! --no-default-features` valide toute la logique sur une machine depourvue de
//! Wayland, libxkbcommon et pile graphique.

mod apps;
mod assistant;
mod cli;
mod health;
mod kernel;
mod model;
mod progress;
mod profile;
mod recovery;
mod session;
mod sources;
mod system;
mod updates;
mod util;

#[cfg(feature = "gui")]
mod task;
#[cfg(feature = "gui")]
mod ui;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // Lu par packages/build-debs.sh (le binaire empaquete est-il celui de la
    // version annoncee?) et utile a quiconque rapporte un probleme.
    if args.get(1).map(|s| s == "--version").unwrap_or(false) {
        println!("auxinux-center {}", env!("CARGO_PKG_VERSION"));
        return;
    }

    if args.get(1).map(|s| s == "--cli").unwrap_or(false) {
        std::process::exit(cli::run(&args[2..]));
    }

    // --premier-demarrage: lance par /etc/xdg/autostart a chaque ouverture de
    // session. Ne fait rien si l'assistant a deja ete termine ou passe, ni dans
    // la session live (voir assistant::should_open_at_login).
    // --assistant: ouvre l'assistant, toujours (relance manuelle).
    let first_run = args.get(1).map(|s| s == "--premier-demarrage").unwrap_or(false);
    if first_run && !assistant::open_at_login_now() {
        std::process::exit(0);
    }
    #[cfg(feature = "gui")]
    let ouverture = if first_run || args.get(1).map(|s| s == "--assistant").unwrap_or(false) {
        ui::Ouverture::Assistant
    } else {
        match (args.get(1).map(String::as_str), args.get(2)) {
            // Ouvert par l'assistant des .exe, sur une alternative Linux.
            (Some("--rechercher"), Some(terme)) if !terme.trim().is_empty() => {
                ui::Ouverture::Recherche(terme.trim().to_string())
            }
            _ => ui::Ouverture::Accueil,
        }
    };

    #[cfg(feature = "gui")]
    {
        if let Err(e) = ui::run(ouverture) {
            eprintln!("auxinux-center: {e}");
            std::process::exit(70);
        }
    }

    #[cfg(not(feature = "gui"))]
    {
        eprintln!(
            "auxinux-center a été compilé sans interface (--no-default-features).\n\
             Utilisez « auxinux-center --cli <commande> »."
        );
        std::process::exit(64);
    }
}
