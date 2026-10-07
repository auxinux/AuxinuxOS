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
    progress::auxi(&["update"], on_line, "Listes de paquets à jour")
}

/// Met a jour tout le systeme: applications Flatpak, puis `auxi osupdate`
/// (index rafraichis, tous les paquets DEB AVEC les paquets nouveaux qu'ils
/// tirent -- un nouveau noyau --, noyaux d'essai). L'instantane est pose par le
/// hook dpkg avant la partie DEB.
pub fn upgrade_all(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(&["upgrade"], on_line, "Mise à jour du système terminée")
}

/// Version du paquet auxinux-center installee, si elle differe du binaire en
/// cours d'execution: le paquet a ete mis a jour pendant que le Center tournait.
pub fn center_updated() -> Option<String> {
    let out = run("dpkg-query", &["-W", "-f=${Version}", "auxinux-center"]);
    if !out.ok {
        return None;
    }
    newer_than_running(out.stdout.trim(), env!("CARGO_PKG_VERSION"))
}

fn newer_than_running(installed: &str, running: &str) -> Option<String> {
    if installed.is_empty() || installed == running {
        None
    } else {
        Some(installed.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn center_update_is_detected_only_when_versions_differ() {
        assert_eq!(newer_than_running("0.2.2", "0.2.1"), Some("0.2.2".into()));
        assert_eq!(newer_than_running("0.2.1", "0.2.1"), None);
        // Paquet absent (installation d'avant la 0.2.1): rien a signaler.
        assert_eq!(newer_than_running("", "0.2.1"), None);
    }
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
