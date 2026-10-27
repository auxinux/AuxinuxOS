//! Section FONCTIONNALITES AUXINUX: ce qui n'existe que dans AuxiNux OS.
//!
//! - Lecteurs virtuels a la Windows (DriveCompat d'AuxiNux Shell 0.3.19+):
//!   C:\, D:\... dans AuxiFiles ET dans le terminal, un seul interrupteur.
//! - Activation et fonctions PRO (AuxiNux Shell 0.3.0+, mode PRO en 0.3.17).
//!
//! Comme pour les profils d'usage, le Center ne reimplemente rien: il lit
//! l'etat et appelle les outils du Shell, seuls proprietaires de ces reglages.
//! - DriveCompat: `auxidrive enable|disable|display` (compte de l'utilisateur,
//!   pas de root), etat lu dans ~/.config/auxinux-shell/drivecompat.json
//!   (versionne par « schema »; seule la cle « enabled » et « display » sont
//!   lues). `auxidrive status` est traduit: inutilisable par un programme.
//! - Activation: le module Python du Shell (auxinux_shell.services.activation)
//!   est interroge tel quel. Recopier ici la liste des cles et des fonctions
//!   ferait deux endroits qui divergent des la premiere cle PRO.
//!
//! Hors session AuxiNux Shell (Plasma, ou Shell absent), la section le DIT au
//! lieu d'afficher un etat invente.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::model::ActionResult;
use crate::util::run;

/// Modules Python du Shell (meme variable que ses assistants root).
fn shell_python() -> String {
    std::env::var("AUXINUX_SHELL_PYTHON").unwrap_or_else(|_| "/usr/share/auxinux-shell/python".into())
}

/// Interrogation de l'activation, sans GTK. Le chemin des modules est passe
/// en argument (sys.argv[1]), jamais colle dans le code Python.
const ACTIVATION_QUERY: &str = r#"
import json, sys
sys.path.insert(0, sys.argv[1])
from auxinux_shell.services import activation as a
s = a.state()
feats = list(a.FEATURES) + [f for f in a.PRO_FEATURES if f not in a.FEATURES]
print(json.dumps({
    "edition": s["edition"] if s else None,
    "features": [{"id": f, "pro": a.is_pro_feature(f), "offered": a.offered(f),
                  "entitled": a.entitled(f)} for f in feats],
}))
"#;

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct DriveCompat {
    /// `auxidrive` est installe (AuxiNux Shell 0.3.19 ou plus).
    pub available: bool,
    pub enabled: bool,
    /// « linux » ou « windows »: chemins affiches dans AuxiFiles.
    pub display: String,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Feature {
    pub id: String,
    /// Reservee au mode PRO.
    #[serde(default)]
    pub pro: bool,
    /// Fonction PRO offerte gratuitement pour l'instant.
    #[serde(default)]
    pub offered: bool,
    /// Le PC y a droit (edition qui la comprend, ou offerte).
    #[serde(default)]
    pub entitled: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Activation {
    /// Le module d'activation du Shell a repondu.
    #[serde(default)]
    pub available: bool,
    /// « free », « pro », ou None (edition de base).
    pub edition: Option<String>,
    #[serde(default)]
    pub features: Vec<Feature>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct FeaturesState {
    pub drives: DriveCompat,
    pub activation: Activation,
}

pub fn state() -> FeaturesState {
    FeaturesState { drives: drive_state(), activation: activation_state() }
}

fn config_dir() -> PathBuf {
    match std::env::var_os("XDG_CONFIG_HOME") {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"),
    }
}

fn drive_state() -> DriveCompat {
    let available = crate::util::run("sh", &["-c", "command -v auxidrive"]).ok;
    let path = config_dir().join("auxinux-shell/drivecompat.json");
    let mut st = parse_drivecompat(&std::fs::read_to_string(path).unwrap_or_default());
    st.available = available;
    st
}

/// Fichier absent ou illisible = valeurs par defaut de DriveCompat
/// (desactive, affichage Linux), comme le Shell lui-meme.
fn parse_drivecompat(text: &str) -> DriveCompat {
    let value: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
    let display = match value.get("display").and_then(|v| v.as_str()) {
        Some("windows") => "windows",
        _ => "linux",
    };
    DriveCompat {
        available: false,
        enabled: value.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false),
        display: display.to_string(),
    }
}

fn activation_state() -> Activation {
    let python = shell_python();
    let out = run("python3", &["-I", "-c", ACTIVATION_QUERY, &python]);
    if !out.ok {
        return Activation::default();
    }
    parse_activation(&out.stdout)
}

fn parse_activation(text: &str) -> Activation {
    match serde_json::from_str::<Activation>(text.trim()) {
        Ok(mut a) => {
            a.available = true;
            a
        }
        Err(_) => Activation::default(),
    }
}

/// Active ou desactive les lecteurs virtuels (AuxiFiles et terminal).
pub fn set_drives(enabled: bool) -> ActionResult {
    let action = if enabled { "enable" } else { "disable" };
    let out = run("auxidrive", &[action]);
    if out.ok {
        ActionResult::ok(if enabled {
            "Lecteurs virtuels activés : C:\\ et les autres lettres sont dans AuxiFiles, et dans tout nouveau terminal."
        } else {
            "Lecteurs virtuels désactivés. Rien n'a été déplacé ni supprimé."
        })
    } else {
        failure(&out, "auxidrive a refusé le changement")
    }
}

/// Chemins affiches dans AuxiFiles: « linux » ou « windows ».
pub fn set_display(mode: &str) -> ActionResult {
    // Valide AVANT d'appeler: aucune valeur de l'interface n'est passee telle quelle.
    if mode != "linux" && mode != "windows" {
        return ActionResult::err(format!("affichage inconnu : {mode}"));
    }
    let out = run("auxidrive", &["display", mode]);
    if out.ok {
        ActionResult::ok(if mode == "windows" {
            "AuxiFiles affiche les chemins à la Windows (C:\\Users\\…)."
        } else {
            "AuxiFiles affiche les chemins Linux (/home/…)."
        })
    } else {
        failure(&out, "auxidrive a refusé le changement")
    }
}

fn failure(out: &crate::util::Output, fallback: &str) -> ActionResult {
    let msg = out.stderr.trim();
    ActionResult::err(if msg.is_empty() { fallback.to_string() } else { msg.to_string() })
}

/// Libelle, description et page des Parametres du Shell de chaque fonction.
/// Une fonction inconnue (ajoutee par un Shell plus recent) garde son
/// identifiant: elle s'affiche quand meme.
pub fn describe(id: &str) -> (String, &'static str, Option<&'static str>) {
    match id {
        "ldap" => (
            "Annuaire d'entreprise".into(),
            "Rejoindre un domaine Active Directory ou un serveur OpenLDAP.",
            Some("comptes/annuaire"),
        ),
        "themes" => (
            "Styles et dispositions".into(),
            "Dispositions XP et Liquid, jeux de couleurs supplémentaires.",
            Some("personnalisation/style"),
        ),
        "games" => (
            "Jeux maison".into(),
            "Démineur, Solitaire et Échecs contre l'ordinateur.",
            None,
        ),
        "shield" => (
            "AuxiNuxOS Shield".into(),
            "Protection antivirus en temps réel : fichiers infectés bloqués, dossiers surveillés.",
            Some("securite/antivirus"),
        ),
        other => (other.to_string(), "", None),
    }
}

/// Pages des Parametres du Shell que le Center a le droit d'ouvrir.
pub const SETTINGS_PAGES: [&str; 4] =
    ["activation", "comptes/annuaire", "personnalisation/style", "securite/antivirus"];

/// Ouvre une page des Parametres d'AuxiNux Shell (`auxinux-settings PAGE`).
pub fn open_settings(page: &str) -> ActionResult {
    if !SETTINGS_PAGES.contains(&page) {
        return ActionResult::err(format!("page inconnue : {page}"));
    }
    spawn("auxinux-settings", &[page])
}

/// Options des lecteurs virtuels d'AuxiFiles (lettres, reservations...).
pub fn open_drive_options() -> ActionResult {
    spawn("auxi-files", &["--drives"])
}

fn spawn(cmd: &str, args: &[&str]) -> ActionResult {
    use std::process::{Command, Stdio};
    match Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(_) => ActionResult::ok(""),
        Err(e) => ActionResult::err(format!("{cmd} : {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drivecompat_reads_enabled_and_display() {
        let st = parse_drivecompat(r#"{"schema": 1, "enabled": true, "display": "windows", "drives": []}"#);
        assert!(st.enabled);
        assert_eq!(st.display, "windows");
    }

    #[test]
    fn missing_or_broken_drivecompat_is_the_shell_default() {
        for text in ["", "pas du json", "[]", r#"{"display": 42}"#] {
            let st = parse_drivecompat(text);
            assert!(!st.enabled, "{text}");
            assert_eq!(st.display, "linux", "{text}");
        }
    }

    #[test]
    fn activation_answer_is_parsed() {
        let a = parse_activation(
            r#"{"edition": null, "features": [{"id": "ldap", "pro": false, "offered": false, "entitled": false},
               {"id": "shield", "pro": true, "offered": true, "entitled": true}]}"#,
        );
        assert!(a.available);
        assert_eq!(a.edition, None);
        assert_eq!(a.features.len(), 2);
        assert!(a.features[1].pro && a.features[1].offered && a.features[1].entitled);
    }

    #[test]
    fn unreadable_activation_is_unavailable_not_base_edition() {
        let a = parse_activation("Traceback (most recent call last): ...");
        assert!(!a.available);
        assert!(a.features.is_empty());
    }

    #[test]
    fn unknown_feature_keeps_its_id() {
        assert_eq!(describe("nouvelle").0, "nouvelle");
        assert_eq!(describe("shield").0, "AuxiNuxOS Shield");
    }

    #[test]
    fn only_known_values_reach_external_programs() {
        assert!(!set_display("C:\\").ok);
        assert!(!open_settings("../../etc").ok);
    }

    #[test]
    fn every_settings_link_is_allowed() {
        for id in ["ldap", "themes", "games", "shield"] {
            if let Some(page) = describe(id).2 {
                assert!(SETTINGS_PAGES.contains(&page), "{id} -> {page}");
            }
        }
    }

    #[test]
    fn query_runs_against_the_shell_module() {
        // Le vrai module du Shell, s'il est la (image, ou AUXINUX_SHELL_PYTHON
        // vers le src/ d'un checkout du Shell): la reponse doit se lire.
        let python = PathBuf::from(shell_python());
        if !python.join("auxinux_shell/services/activation.py").exists() {
            return;
        }
        let out = run("python3", &["-I", "-c", ACTIVATION_QUERY, python.to_str().unwrap()]);
        assert!(out.ok, "{}", out.stderr);
        let a = parse_activation(&out.stdout);
        assert!(a.available);
        assert!(a.features.iter().any(|f| f.id == "shield" && f.pro));
    }
}
