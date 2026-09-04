//! Section MISES A JOUR: applications ET systeme d'exploitation.
//!
//! Tout passe par la CLI `auxi`, jamais par apt-get directement: c'est `auxi`
//! qui pose l'instantane de securite avant la transaction. Court-circuiter
//! `auxi` ici reviendrait a offrir dans l'interface un chemin de mise a jour
//! SANS filet, alors que le terminal en a un.

use crate::model::ActionResult;
use crate::util::{run, run_pkexec};

/// Rafraichit les index de paquets (equivalent de `auxi update`).
pub fn refresh_indexes() -> ActionResult {
    let out = run_pkexec(&["auxi", "update"]);
    if out.ok {
        ActionResult::ok("Listes de paquets a jour")
    } else {
        ActionResult::err(tail(&out.stderr))
    }
}

/// Met a jour tout le systeme: paquets DEB et applications Flatpak.
/// `auxi upgrade` cree un instantane avant la partie DEB.
pub fn upgrade_all() -> ActionResult {
    let out = run_pkexec(&["auxi", "upgrade"]);
    if out.ok {
        ActionResult::ok("Mise a jour du systeme terminee")
    } else {
        ActionResult::err(tail(&out.stderr))
    }
}

/// Version du systeme telle qu'affichee a l'utilisateur.
pub fn os_version() -> String {
    let out = run("sh", &["-c", ". /etc/os-release 2>/dev/null && printf '%s' \"$PRETTY_NAME\""]);
    let v = out.stdout.trim();
    if v.is_empty() {
        "AuxiNux OS EN".into()
    } else {
        v.to_string()
    }
}

fn tail(s: &str) -> String {
    let lines: Vec<&str> = s.lines().filter(|l| !l.trim().is_empty()).collect();
    let start = lines.len().saturating_sub(8);
    let msg = lines[start..].join("\n");
    if msg.is_empty() {
        "Echec de l'operation".into()
    } else {
        msg
    }
}
