//! AuxiNux OS Center — centre de controle d'AuxiNux OS.
//!
//! - Sans argument: interface libcosmic (necessite la feature "gui").
//! - `--cli ...`: backend seul, sortie JSON (voir src/cli.rs).
//!
//! L'interface est derriere une feature pour que `cargo check
//! --no-default-features` valide toute la logique sur une machine depourvue de
//! Wayland, libxkbcommon et pile graphique.

mod apps;
mod cli;
mod health;
mod model;
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

    #[cfg(feature = "gui")]
    {
        if let Err(e) = ui::run() {
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
