//! Bureau utilise a l'ouverture de session: AuxiNux Shell ou KDE Plasma.
//!
//! Decision d'aporler (2026-10-10): AuxiNux Shell est le bureau par defaut
//! (DefaultSession de /etc/sddm.conf.d/10-auxinux.conf, paquet
//! auxinuxos-release), et le centre permet de choisir l'un ou l'autre.
//!
//! Le choix vaut pour la machine: SDDM n'a qu'une session par defaut et ne
//! memorise que la DERNIERE session ouverte (/var/lib/sddm/state.conf). Le
//! helper ecrit les deux, sinon un compte qui a deja ouvert Plasma y
//! retournerait malgre le choix. L'ecran de connexion permet toujours de
//! choisir l'autre bureau pour une seule session.

use std::fs;
use std::path::Path;

use crate::model::ActionResult;
use crate::util::run_pkexec;

pub const SESSION_HELPER: &str = "/usr/libexec/auxinux/auxinux-session-helper";
const SESSIONS_DIR: &str = "/usr/share/wayland-sessions";
const SDDM_CONFS: [&str; 2] = [
    "/etc/sddm.conf.d/10-auxinux.conf",
    "/etc/sddm.conf.d/20-auxinux-session.conf",
];

/// (identifiant de session, nom affiche, description)
pub const DESKTOPS: [(&str, &str, &str); 2] = [
    (
        "auxinux",
        "AuxiNux Shell",
        "Bureau léger à l'ergonomie familière (barre des tâches, menu Démarrer). Par défaut.",
    ),
    (
        "plasma",
        "KDE Plasma",
        "Bureau complet et très personnalisable.",
    ),
];

#[derive(Debug, Clone, Default)]
pub struct DesktopState {
    /// Session ouverte par defaut a la prochaine connexion.
    pub default: String,
    /// Session en cours (d'apres XDG_CURRENT_DESKTOP), si elle est reconnue.
    pub running: Option<String>,
    /// Sessions installees, dans l'ordre de DESKTOPS.
    pub installed: Vec<String>,
}

pub fn state() -> DesktopState {
    let texts: Vec<String> = SDDM_CONFS
        .iter()
        .map(|p| fs::read_to_string(p).unwrap_or_default())
        .collect();
    let installed = DESKTOPS
        .iter()
        .map(|(id, _, _)| id.to_string())
        .filter(|id| Path::new(SESSIONS_DIR).join(format!("{id}.desktop")).exists())
        .collect();
    DesktopState {
        default: default_session_in(&texts).unwrap_or_else(|| "plasma".to_string()),
        running: running_in(&std::env::var("XDG_CURRENT_DESKTOP").unwrap_or_default()),
        installed,
    }
}

pub fn label(id: &str) -> &'static str {
    DESKTOPS
        .iter()
        .find(|(i, _, _)| *i == id)
        .map(|(_, l, _)| *l)
        .unwrap_or("bureau inconnu")
}

/// Derniere valeur de DefaultSession= dans les fichiers, lus dans l'ordre de
/// SDDM (le dernier l'emporte), section [General] seulement.
pub fn default_session_in(texts: &[String]) -> Option<String> {
    let mut found = None;
    for text in texts {
        let mut general = false;
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with('[') {
                general = line == "[General]";
                continue;
            }
            if !general {
                continue;
            }
            if let Some(v) = line.strip_prefix("DefaultSession=") {
                let v = v.trim().trim_end_matches(".desktop");
                if !v.is_empty() {
                    found = Some(v.to_string());
                }
            }
        }
    }
    found
}

fn running_in(current_desktop: &str) -> Option<String> {
    let names: Vec<&str> = current_desktop.split(':').collect();
    if names.iter().any(|n| n.eq_ignore_ascii_case("AuxiNux")) {
        Some("auxinux".into())
    } else if names.iter().any(|n| n.eq_ignore_ascii_case("KDE")) {
        Some("plasma".into())
    } else {
        None
    }
}

pub fn set(id: &str) -> ActionResult {
    if !DESKTOPS.iter().any(|(i, _, _)| *i == id) {
        return ActionResult::err("bureau inconnu");
    }
    let out = run_pkexec(&[SESSION_HELPER, id]);
    if out.ok {
        ActionResult::ok(format!(
            "{} sera ouvert à la prochaine connexion",
            label(id)
        ))
    } else if out.code == Some(126) || out.stderr.contains("Not authorized") {
        ActionResult::err(crate::progress::AUTH_REFUSED)
    } else {
        let msg = out.stderr.trim();
        ActionResult::err(if msg.is_empty() {
            "Le bureau par défaut n'a pas pu être changé.".to_string()
        } else {
            msg.to_string()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn last_default_session_wins() {
        let base = "[Theme]\nCurrent=x\n[General]\nDefaultSession=auxinux.desktop\nNumlock=on\n".to_string();
        assert_eq!(default_session_in(&[base.clone()]).as_deref(), Some("auxinux"));
        let choice = "[General]\nDefaultSession=plasma.desktop\n".to_string();
        assert_eq!(default_session_in(&[base, choice]).as_deref(), Some("plasma"));
    }

    #[test]
    fn default_session_outside_general_is_ignored() {
        let t = "[Autologin]\nDefaultSession=plasma.desktop\n".to_string();
        assert_eq!(default_session_in(&[t]), None);
        assert_eq!(default_session_in(&[String::new()]), None);
    }

    #[test]
    fn running_session_from_current_desktop() {
        assert_eq!(running_in("AuxiNux").as_deref(), Some("auxinux"));
        assert_eq!(running_in("KDE").as_deref(), Some("plasma"));
        assert_eq!(running_in("ubuntu:GNOME"), None);
    }

    #[test]
    fn unknown_desktop_is_refused_without_helper() {
        assert!(!set("gnome").ok);
    }
}
