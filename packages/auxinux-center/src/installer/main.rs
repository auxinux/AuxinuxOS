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
        eprintln!("auxinux-installer: doit être lancé en root / must run as root");
        std::process::exit(77);
    }
    // Un arret imprevu doit se VOIR et laisser une trace. Le service envoie
    // stderr au journal et relance aussitot une invite de connexion: une
    // panique ou une erreur d'entree/sortie ressemblait a « ca plante direct »
    // sans aucun message (signale par aporler sur une vraie machine, le
    // 2026-10-10, juste apres la confirmation).
    let precedent = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        ratatui::restore();
        signaler(&format!("panique: {info}"));
        precedent(info);
    }));
    let mut terminal = ratatui::init();
    let resultat = App::new().executer(&mut terminal);
    ratatui::restore();
    match resultat {
        Ok(Sortie::Redemarrer) => arreter("reboot", "b"),
        Ok(Sortie::Eteindre) => arreter("poweroff", "o"),
        // Le bureau live, tel qu'il demarre depuis l'entree « Live »: on
        // bascule simplement vers la cible graphique.
        Ok(Sortie::BureauLive) => {
            let _ = util::run("systemctl", &["isolate", "graphical.target"]);
        }
        Ok(Sortie::Console) => {}
        Err(e) => {
            signaler(&format!("erreur d'entrée/sortie du terminal: {e}"));
            std::process::exit(1);
        }
    }
}

const JOURNAL_ARRET: &str = "/var/log/auxinux-installer-arret.log";

/// Consigne l'arret imprevu, l'affiche sur la console et attend Entree: sans
/// cette pause, l'invite de connexion relancee par le service l'effacait.
/// L'installation en cours (moteur) a son propre journal.
fn signaler(cause: &str) {
    use std::io::{BufRead, Write};
    let texte = format!(
        "auxinux-installer s'est arrêté / stopped: {cause}\n\
         Journal de l'installation / installation log: {}\n",
        systeme::JOURNAL
    );
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(JOURNAL_ARRET) {
        let _ = f.write_all(texte.as_bytes());
    }
    eprintln!("{texte}");
    let mut out = std::io::stdout();
    let _ = write!(
        out,
        "\r\n\r\nL'installateur s'est arrêté de façon imprévue.\r\n{cause}\r\n\r\n\
         Détails: {JOURNAL_ARRET} et {}\r\n\
         Appuyez sur Entrée pour ouvrir une console (compte auxinux / auxinux).\r\n",
        systeme::JOURNAL
    );
    let _ = out.flush();
    let mut ligne = String::new();
    let _ = std::io::stdin().lock().read_line(&mut ligne);
}

/// Redemarre ou eteint la machine, MEME si le support d'installation a deja
/// ete retire.
///
/// Le systeme live s'execute DEPUIS ce support, et l'ecran de fin demande de
/// le retirer avant d'appuyer sur Entree. `systemctl reboot` arretait alors
/// tout proprement... puis systemd ne pouvait plus charger son programme
/// d'arret final, reste sur le support: « Failed to execute shutdown
/// binary », machine figee (constate en VM le 2026-10-02).
///
/// On passe donc directement par le noyau (sysrq), qui n'a besoin d'aucun
/// fichier: ecriture des tampons (s), remontage en lecture seule (u), puis
/// redemarrage ou arret. Sans perte possible: la session live n'a rien a
/// sauvegarder, et le moteur a deja demonte le systeme installe.
/// /proc/sysrq-trigger est accessible a root quel que soit kernel.sysrq.
fn arreter(_action: &str, sysrq: &str) {
    for touche in ["s", "u", sysrq] {
        let _ = std::fs::write("/proc/sysrq-trigger", touche);
        std::thread::sleep(std::time::Duration::from_secs(2));
    }
}
