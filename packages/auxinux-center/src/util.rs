//! Helpers d'execution de commandes externes.
//!
//! Le Center delegue tout le travail aux outils systeme deja presents:
//! `flatpak`, la CLI `auxi` (politique APT maison) et `apt-cache`. Les
//! operations privilegiees passent par `pkexec`, TOUJOURS sur un programme
//! installe a un emplacement fixe appartenant a root -- jamais sur un script
//! genere a la volee dans un repertoire temporaire.

use std::process::Command;

pub struct Output {
    pub ok: bool,
    pub stdout: String,
    pub stderr: String,
}

/// Execute une commande et capture sa sortie.
pub fn run(cmd: &str, args: &[&str]) -> Output {
    match Command::new(cmd).args(args).output() {
        Ok(o) => Output {
            ok: o.status.success(),
            stdout: String::from_utf8_lossy(&o.stdout).to_string(),
            stderr: String::from_utf8_lossy(&o.stderr).to_string(),
        },
        Err(e) => Output {
            ok: false,
            stdout: String::new(),
            stderr: format!("{cmd}: {e}"),
        },
    }
}

/// Execute une commande privilegiee via pkexec (declenche l'agent polkit).
/// `args[0]` est le programme a lancer en root, le reste ses arguments.
pub fn run_pkexec(args: &[&str]) -> Output {
    run("pkexec", args)
}
