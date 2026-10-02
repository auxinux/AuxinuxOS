//! Section MISES A JOUR: applications ET systeme d'exploitation.
//!
//! Tout passe par la CLI `auxi`, jamais par apt-get directement: c'est `auxi`
//! qui pose l'instantane de securite avant la transaction. Court-circuiter
//! `auxi` ici reviendrait a offrir dans l'interface un chemin de mise a jour
//! SANS filet, alors que le terminal en a un.

use crate::model::ActionResult;
use crate::progress;
use crate::util::run;

/// Rafraichit les index de paquets (equivalent de `auxi update`).
pub fn refresh_indexes(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(&["update"], on_line, "Listes de paquets a jour")
}

/// Met a jour tout le systeme: paquets DEB et applications Flatpak.
/// `auxi upgrade` cree un instantane avant la partie DEB.
pub fn upgrade_all(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(&["upgrade"], on_line, "Mise a jour du systeme terminee")
}

/// Version du systeme telle qu'affichee a l'utilisateur.
pub fn os_version() -> String {
    let out = run("sh", &["-c", ". /etc/os-release 2>/dev/null && printf '%s' \"$PRETTY_NAME\""]);
    let v = out.stdout.trim();
    if v.is_empty() {
        "AuxiNux OS".into()
    } else {
        v.to_string()
    }
}
