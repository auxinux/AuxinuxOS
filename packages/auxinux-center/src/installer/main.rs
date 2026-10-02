//! auxinux-installer — installateur console d'AuxiNux OS (« Install NOW »).
//!
//! Lance sur la premiere console par auxinux-installer.service quand le live
//! demarre avec l'entree GRUB « Installer maintenant » (auxinux.install=1).
//! Il pose les questions (ecrans.rs), puis confie l'installation au moteur
//! /usr/lib/auxinux/auxinux-install-engine, dont il affiche l'avancement.
//!
//! Partage avec le centre de controle le catalogue d'applications
//! (assistant.rs) et la lecture de l'avancement (progress.rs).

// Modules partages avec le centre de controle: l'installateur n'en utilise
// qu'une partie.
#[allow(dead_code)]
#[path = "../assistant.rs"]
mod assistant;
mod ecrans;
#[allow(dead_code)]
#[path = "../model.rs"]
mod model;
#[allow(dead_code)]
#[path = "../progress.rs"]
mod progress;
mod systeme;
#[allow(dead_code)]
#[path = "../util.rs"]
mod util;

use ecrans::{App, Sortie};

fn main() {
    if util::run("id", &["-u"]).stdout.trim() != "0" {
        eprintln!("auxinux-installer: doit etre lance en root / must run as root");
        std::process::exit(77);
    }
    let mut terminal = ratatui::init();
    let resultat = App::new().executer(&mut terminal);
    ratatui::restore();
    match resultat {
        Ok(Sortie::Redemarrer) => {
            let _ = util::run("systemctl", &["reboot"]);
        }
        Ok(Sortie::Eteindre) => {
            let _ = util::run("systemctl", &["poweroff"]);
        }
        // Le bureau live, tel qu'il demarre depuis l'entree « Live »: on
        // bascule simplement vers la cible graphique.
        Ok(Sortie::BureauLive) => {
            let _ = util::run("systemctl", &["isolate", "graphical.target"]);
        }
        Ok(Sortie::Console) => {}
        Err(e) => {
            eprintln!("auxinux-installer: {e}");
            std::process::exit(1);
        }
    }
}
