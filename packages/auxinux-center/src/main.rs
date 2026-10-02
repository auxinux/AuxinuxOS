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
mod model;
mod progress;
mod profile;
mod recovery;
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
    let open_assistant = first_run || args.get(1).map(|s| s == "--assistant").unwrap_or(false);

    #[cfg(feature = "gui")]
    {
        if let Err(e) = ui::run(open_assistant) {
            eprintln!("auxinux-center: {e}");
            std::process::exit(70);
        }
    }

    #[cfg(not(feature = "gui"))]
    {
        eprintln!(
            "auxinux-center a ete compile sans interface (--no-default-features).\n\
             Utilisez « auxinux-center --cli <commande> »."
        );
        std::process::exit(64);
    }
}
