//! Section PROFIL D'USAGE: bureautique, multimedia, jeu.
//!
//! Le Center ne reimplemente PAS les reglages: il appelle `auxinux-profile`,
//! qui reste la seule chose a ecrire sysctl, limites temps reel audio, quantum
//! PipeWire et profil d'alimentation. Deux endroits qui ecrivent les memes
//! fichiers finiraient par diverger, et c'est la ligne de commande qui
//! resterait la reference.
//!
//! Voir docs/profils-usage.md.

use serde::{Deserialize, Serialize};

use crate::model::ActionResult;
use crate::util::{run, run_pkexec};

/// Les seuls profils acceptes. La liste est ici ET dans `auxinux-profile`:
/// le Center valide avant d'appeler pour ne jamais passer a `pkexec` une
/// valeur venue de l'interface sans controle.
pub const PROFILES: [&str; 3] = ["bureautique", "multimedia", "gaming"];

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ProfileState {
    /// Faux si `auxinux-profile` est absent: la section doit alors le DIRE,
    /// pas afficher un profil par defaut invente.
    pub available: bool,
    pub current: String,
    pub power: String,
    pub quantum: String,
    pub rtprio: String,
}

pub fn state() -> ProfileState {
    let out = run("auxinux-profile", &["status"]);
    if !out.ok {
        return ProfileState::default();
    }
    let mut st = parse_status(&out.stdout);
    st.available = !st.current.is_empty();
    st
}

/// Analyse la sortie `cle=valeur` de `auxinux-profile status`.
///
/// Tolerante par construction: une cle ajoutee en amont ne casse rien, et une
/// cle manquante laisse une chaine vide plutot que de faire echouer la lecture
/// de tout l'etat.
fn parse_status(text: &str) -> ProfileState {
    let mut st = ProfileState::default();
    for line in text.lines() {
        let (key, value) = match line.split_once('=') {
            Some(kv) => kv,
            None => continue,
        };
        let value = value.trim().to_string();
        match key.trim() {
            "profile" => st.current = value,
            "power" => st.power = value,
            "quantum" => st.quantum = value,
            "rtprio" => st.rtprio = value,
            _ => {}
        }
    }
    st
}

/// Libelle et effet de chaque profil, pour l'interface.
pub fn describe(name: &str) -> (&'static str, &'static str) {
    match name {
        "bureautique" => (
            "Bureautique",
            "Réactivité du bureau, autonomie préservée.",
        ),
        "multimedia" => (
            "Multimédia",
            "Latence audio basse, priorité temps réel, plein régime.",
        ),
        "gaming" => (
            "Jeu",
            "Limites relevées pour Proton, mitigation split-lock levée, plein régime.",
        ),
        _ => ("Inconnu", ""),
    }
}

pub fn set(name: &str) -> ActionResult {
    if !PROFILES.contains(&name) {
        return ActionResult::err(format!("profil inconnu: {name}"));
    }
    let out = run_pkexec(&["auxinux-profile", "set", name]);
    if out.ok {
        let (label, _) = describe(name);
        ActionResult::ok(format!("Profil d'usage: {label}"))
    } else {
        let msg = out.stderr.trim();
        ActionResult::err(if msg.is_empty() {
            "Changement de profil refusé ou annulé".to_string()
        } else {
            msg.to_string()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_status_reads_known_keys_and_ignores_others() {
        let st = parse_status(
            "profile=gaming\npower=performance\nquantum=512\nrtprio=90\napplied=yes\n",
        );
        assert_eq!(st.current, "gaming");
        assert_eq!(st.power, "performance");
        assert_eq!(st.quantum, "512");
        assert_eq!(st.rtprio, "90");
    }

    #[test]
    fn parse_status_survives_garbage_and_missing_keys() {
        let st = parse_status("bruit\n\nprofile=bureautique\n=vide\n");
        assert_eq!(st.current, "bureautique");
        assert!(st.power.is_empty());
    }

    #[test]
    fn set_refuses_a_profile_that_is_not_in_the_list() {
        // Le refus doit arriver AVANT pkexec: rien ne doit etre lance en root
        // sur une valeur venue de l'interface.
        let r = set("turbo");
        assert!(!r.ok);
        assert!(r.message.contains("turbo"));
    }

    #[test]
    fn unavailable_state_is_not_a_fake_default() {
        let st = ProfileState::default();
        assert!(!st.available);
        assert!(st.current.is_empty());
    }
}
