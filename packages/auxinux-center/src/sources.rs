//! Section SOURCES: depots APT (activer/desactiver/ajouter/retirer), depots
//! connus (orientes vie privee/liberte), remotes Flatpak (activer/desactiver),
//! et politique APT maison (`auxi set apt=`).
//!
//! Securite: toute ecriture sous /etc passe par `pkexec` (agent polkit). Les
//! cles sont installees sous /etc/apt/keyrings avec `Signed-By` (jamais
//! apt-key). Les depots systeme (auxinux*) sont proteges contre la
//! suppression. Le depot de Brave ne l'est plus depuis le 2026-10-29: Brave
//! vient de Flathub, et son ancien depot DEB se retire comme n'importe quel
//! autre.

use std::fs;
use std::path::Path;

use crate::model::{ActionResult, AptSource, FlatpakRemote, SourcePreset};
use crate::util::{run, run_pkexec};

const SOURCES_DIR: &str = "/etc/apt/sources.list.d";

/// Assistant privilegie. Tout ce qui s'execute en root vit dans ce fichier,
/// appartenant a root, avec sa propre action polkit: l'invite
/// d'authentification annonce « ajouter une source de logiciels » au lieu de
/// « executer bash », et plus aucun script n'est depose dans un repertoire
/// temporaire partage avant d'etre execute avec les privileges.
const SOURCE_HELPER: &str = "/usr/libexec/auxinux/auxinux-source-helper";

fn pretty_name(file: &str) -> String {
    file.trim_end_matches(".disabled")
        .trim_end_matches(".sources")
        .trim_end_matches(".list")
        .replace(['-', '_'], " ")
}

fn is_protected(base: &str) -> bool {
    base.starts_with("auxinux")
}

/// A GPG key URL is only ever fetched, in root context, by the preset/custom
/// source scripts. Restrict it to a plain https URL over a conservative
/// character set so it can never break out of the `curl "<url>"` argument.
fn is_safe_key_url(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("https://") else {
        return false;
    };
    !rest.is_empty()
        && rest.len() <= 512
        && rest.chars().all(|c| {
            c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '/' | '~' | '%' | '?' | '=' | '&' | '+' | ':' | '@')
        })
}

/// A deb822 sources body is written verbatim into a file in root context.
/// Reject control characters and any line that could terminate the heredoc
/// the writer script uses. Only the small set of deb822
/// fields AuxiNuxOS understands is allowed.
fn is_safe_sources_body(body: &str) -> bool {
    if body.is_empty() || body.len() > 4096 {
        return false;
    }
    let allowed_keys = [
        "Types:",
        "URIs:",
        "Suites:",
        "Components:",
        "Architectures:",
        "Signed-By:",
        "Enabled:",
    ];
    for raw in body.lines() {
        let line = raw.trim_end();
        if line.is_empty() {
            continue;
        }
        if line.chars().any(|c| c.is_control() && c != '\t') {
            return false;
        }
        // Would terminate the writer's heredoc.
        if line.trim() == "AUXIEOF" {
            return false;
        }
        if !allowed_keys.iter().any(|k| line.starts_with(k)) {
            return false;
        }
    }
    true
}

// ---------------------------------------------------------------------------
// Depots APT
// ---------------------------------------------------------------------------

pub fn list_apt_sources() -> Vec<AptSource> {
    let mut out: Vec<AptSource> = Vec::new();
    if let Ok(entries) = fs::read_dir(SOURCES_DIR) {
        for e in entries.flatten() {
            let fname = e.file_name().to_string_lossy().to_string();
            let (kind, enabled) = if fname.ends_with(".sources") {
                ("deb822", deb822_enabled(&e.path()))
            } else if fname.ends_with(".sources.disabled") {
                ("deb822", false)
            } else if fname.ends_with(".list") {
                ("list", true)
            } else if fname.ends_with(".list.disabled") {
                ("list", false)
            } else {
                continue;
            };
            let base = fname.trim_end_matches(".disabled");
            out.push(AptSource {
                name: pretty_name(&fname),
                removable: !is_protected(base),
                file: fname,
                kind: kind.into(),
                enabled,
            });
        }
    }
    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    out
}

fn deb822_enabled(path: &Path) -> bool {
    match fs::read_to_string(path) {
        Ok(c) => !c
            .lines()
            .any(|l| l.trim().to_lowercase().replace(' ', "") == "enabled:no"),
        Err(_) => true,
    }
}

/// Source des noyaux en essai. Son interrupteur passe par `auxi kernel dev`
/// (voir kernel.rs) et non par un simple renommage: l'operation est suivie en
/// direct, et un echec du rafraichissement des index est montre au lieu d'etre
/// ignore.
pub fn is_kernel_dev_source(file: &str) -> bool {
    file.trim_end_matches(".disabled") == "auxinuxos-kernel-dev.sources"
}

pub fn set_apt_source_enabled(file: &str, enabled: bool) -> ActionResult {
    if file.contains('/') || file.contains("..") {
        return ActionResult::err("nom de fichier invalide");
    }
    let base = file.trim_end_matches(".disabled");
    let (from, to) = if enabled {
        (format!("{SOURCES_DIR}/{base}.disabled"), format!("{SOURCES_DIR}/{base}"))
    } else {
        (format!("{SOURCES_DIR}/{base}"), format!("{SOURCES_DIR}/{base}.disabled"))
    };
    if !Path::new(&from).exists() {
        return ActionResult::ok("déjà dans l'état demandé");
    }
    let out = run_pkexec(&["mv", "-f", &from, &to]);
    if out.ok {
        let _ = run_pkexec(&["auxi", "update"]);
        ActionResult::ok(if enabled { "Dépôt activé" } else { "Dépôt désactivé" })
    } else {
        ActionResult::err(out.stderr)
    }
}

pub fn remove_apt_source(file: &str) -> ActionResult {
    if file.contains('/') || file.contains("..") {
        return ActionResult::err("nom de fichier invalide");
    }
    let base = file.trim_end_matches(".disabled");
    if is_protected(base) {
        return ActionResult::err("Dépôt système protégé (non supprimable)");
    }
    let mut removed = false;
    for f in [format!("{SOURCES_DIR}/{base}"), format!("{SOURCES_DIR}/{base}.disabled")] {
        if Path::new(&f).exists() {
            let out = run_pkexec(&["rm", "-f", &f]);
            if !out.ok {
                return ActionResult::err(out.stderr);
            }
            removed = true;
        }
    }
    if removed {
        let _ = run_pkexec(&["auxi", "update"]);
        ActionResult::ok("Dépôt retiré")
    } else {
        ActionResult::ok("rien à retirer")
    }
}

// ---------------------------------------------------------------------------
// Depots connus (presets)
// ---------------------------------------------------------------------------

struct PresetDef {
    name: &'static str,
    desc: &'static str,
}

/// Libelles seuls. L'URL de la cle et le corps deb822 de chaque depot connu
/// sont definis DANS l'assistant privilegie: le centre ne transmet qu'un
/// identifiant, et ne peut donc pas faire telecharger une cle arbitraire en
/// root, meme si son propre code etait detourne.
fn preset_defs() -> Vec<(&'static str, PresetDef)> {
    vec![
        ("vscode", PresetDef {
            name: "Visual Studio Code",
            desc: "Éditeur de code Microsoft, très populaire.",
        }),
        ("docker", PresetDef {
            name: "Docker CE",
            desc: "Moteur de conteneurs Docker (dépôt officiel).",
        }),
        ("mozilla", PresetDef {
            name: "Mozilla Firefox",
            desc: "Firefox officiel par Mozilla, mises à jour rapides.",
        }),
        ("mullvad", PresetDef {
            name: "Mullvad VPN",
            desc: "VPN axé vie privée, sans journaux, paiement anonyme possible.",
        }),
        ("signal", PresetDef {
            name: "Signal Desktop",
            desc: "Messagerie chiffrée de bout en bout, orientée vie privée.",
        }),
    ]
}

pub fn list_source_presets() -> Vec<SourcePreset> {
    let mut out = Vec::new();
    for (id, d) in preset_defs() {
        let installed = Path::new(&format!("{SOURCES_DIR}/{id}.sources")).exists()
            || Path::new(&format!("{SOURCES_DIR}/{id}.sources.disabled")).exists();
        out.push(SourcePreset {
            id: id.to_string(),
            name: d.name.into(),
            description: d.desc.into(),
            installed,
        });
    }
    out
}

pub fn add_source_preset(preset: &str) -> ActionResult {
    let Some((id, d)) = preset_defs().into_iter().find(|(id, _)| *id == preset) else {
        return ActionResult::err(format!("preset inconnu: {preset}"));
    };
    let out = run_pkexec(&[SOURCE_HELPER, "preset", id]);
    if out.ok {
        ActionResult::ok(format!("Dépôt '{}' ajouté", d.name))
    } else {
        ActionResult::err(helper_error(&out.stderr))
    }
}

/// Message d'echec de l'assistant, ramene a sa derniere ligne utile: la sortie
/// de pkexec ajoute des lignes de refus d'autorisation qui noient la cause.
fn helper_error(stderr: &str) -> String {
    let msg = stderr
        .lines()
        .filter(|l| !l.trim().is_empty())
        .last()
        .unwrap_or("")
        .trim()
        .to_string();
    if msg.is_empty() {
        "Ajout du dépôt impossible (authentification refusée ?)".into()
    } else {
        msg
    }
}

pub fn add_custom_apt_source(name: &str, sources_body: &str, key_url: &str) -> ActionResult {
    let safe: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
        .collect();
    if safe.is_empty() || safe.len() > 64 {
        return ActionResult::err("nom invalide");
    }
    // Pre-validation cote interface pour rendre l'erreur immediate et lisible.
    // Le controle qui FAIT FOI est celui de l'assistant privilegie: c'est lui
    // qui s'execute en root.
    if !is_safe_sources_body(sources_body) {
        return ActionResult::err(
            "corps de dépôt invalide (champs deb822 attendus, sans caractère spécial)",
        );
    }
    let key_trimmed = key_url.trim();
    if !key_trimmed.is_empty() && !is_safe_key_url(key_trimmed) {
        return ActionResult::err("URL de clé invalide (https:// requis)");
    }

    // argv, jamais un script: ni le corps ni l'URL ne sont interpretes par un
    // shell a un quelconque moment.
    let out = run_pkexec(&[SOURCE_HELPER, "custom", &safe, key_trimmed, sources_body]);
    if out.ok {
        ActionResult::ok(format!("Dépôt '{safe}' ajouté"))
    } else {
        ActionResult::err(helper_error(&out.stderr))
    }
}

// ---------------------------------------------------------------------------
// Remotes Flatpak
// ---------------------------------------------------------------------------

pub fn list_flatpak_remotes() -> Vec<FlatpakRemote> {
    let out = run(
        "flatpak",
        &["remotes", "--show-disabled", "--columns=name,url,options"],
    );
    let mut remotes: Vec<FlatpakRemote> = Vec::new();
    if out.ok {
        for line in out.stdout.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let cols: Vec<&str> = line.split('\t').collect();
            let name = cols.first().copied().unwrap_or("").trim().to_string();
            if name.is_empty() {
                continue;
            }
            let options = cols.get(2).copied().unwrap_or("");
            let enabled = !options.split(',').any(|o| o.trim() == "disabled");
            remotes.push(FlatpakRemote {
                name,
                url: cols.get(1).copied().unwrap_or("").trim().to_string(),
                enabled,
            });
        }
    }
    remotes
}

pub fn set_flatpak_remote_enabled(name: &str, enabled: bool) -> ActionResult {
    let flag = if enabled { "--enable" } else { "--disable" };
    let out = run_pkexec(&["flatpak", "remote-modify", flag, name]);
    if out.ok {
        ActionResult::ok("Remote mis à jour")
    } else {
        ActionResult::err(out.stderr)
    }
}

// ---------------------------------------------------------------------------
// Politique APT maison (auxi)
// ---------------------------------------------------------------------------

/// Vrai quand APT direct est reactive (`auxi set apt=true`).
pub fn apt_wrapper_enabled() -> bool {
    fs::read_to_string("/etc/auxinux/apt.conf")
        .map(|c| c.lines().any(|l| l.trim() == "APT_ENABLED=1"))
        .unwrap_or(false)
}

pub fn set_apt_wrapper(enabled: bool) -> ActionResult {
    let val = if enabled { "apt=true" } else { "apt=false" };
    let out = run_pkexec(&["auxi", "set", val]);
    if out.ok {
        ActionResult::ok("Politique APT mise à jour")
    } else {
        ActionResult::err(out.stderr)
    }
}

/// Vrai quand l'installation d'APPLICATIONS en DEB est activee
/// (`auxi set deb=true`). Sans elle, le centre n'affiche que Flatpak.
pub fn deb_apps_enabled() -> bool {
    deb_apps_in(&fs::read_to_string("/etc/auxinux/apps.conf").unwrap_or_default())
}

fn deb_apps_in(conf: &str) -> bool {
    conf.lines().any(|l| l.trim() == "DEB_APPS=1")
}

pub fn set_deb_apps(enabled: bool) -> ActionResult {
    let val = if enabled { "deb=true" } else { "deb=false" };
    let out = run_pkexec(&["auxi", "set", val]);
    if out.ok {
        ActionResult::ok(if enabled {
            "Installation DEB activée (Flatpak reste prioritaire)"
        } else {
            "Installation DEB désactivée: Flatpak seulement"
        })
    } else {
        ActionResult::err(out.stderr)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kernel_dev_source_is_recognized_in_both_states() {
        assert!(is_kernel_dev_source("auxinuxos-kernel-dev.sources"));
        assert!(is_kernel_dev_source("auxinuxos-kernel-dev.sources.disabled"));
        assert!(!is_kernel_dev_source("auxinuxos-kernel.list"));
        assert!(!is_kernel_dev_source("auxinux-apps.sources"));
    }

    #[test]
    fn deb_apps_needs_the_explicit_line() {
        assert!(deb_apps_in("DEB_APPS=1\n"));
        assert!(!deb_apps_in("DEB_APPS=0\n"));
        assert!(!deb_apps_in(""), "fichier absent: Flatpak seulement");
        assert!(!deb_apps_in("#DEB_APPS=1\n"));
    }

    #[test]
    fn key_urls_must_be_https_and_shell_safe() {
        assert!(is_safe_key_url("https://packages.microsoft.com/keys/microsoft.asc"));
        assert!(!is_safe_key_url("http://example.tld/key.asc"));
        assert!(!is_safe_key_url("https://example.tld/$(id).asc"));
        assert!(!is_safe_key_url("https://example.tld/`id`"));
        assert!(!is_safe_key_url("https://example.tld/a\";id;\""));
        assert!(!is_safe_key_url("file:///etc/shadow"));
        assert!(!is_safe_key_url(""));
    }

    #[test]
    fn sources_body_accepts_only_known_deb822_fields() {
        let good = "Types: deb\nURIs: https://example.tld\nSuites: trixie\nComponents: main\n";
        assert!(is_safe_sources_body(good));
        assert!(!is_safe_sources_body("Types: deb\nrm -rf /\n"));
        assert!(!is_safe_sources_body("Types: deb\nAUXIEOF\n"));
        assert!(!is_safe_sources_body(""));
        assert!(!is_safe_sources_body(&"Types: deb\n".repeat(1000)));
    }

    #[test]
    fn unknown_preset_is_refused_without_calling_the_helper() {
        let result = add_source_preset("../../etc/passwd");
        assert!(!result.ok);
        assert!(result.message.contains("preset inconnu"));
    }

    #[test]
    fn protected_system_sources_cannot_be_removed() {
        assert!(is_protected("auxinuxos-kernel.list"));
        assert!(!is_protected("brave-browser-release.sources"));
        assert!(!is_protected("docker.sources"));

        let result = remove_apt_source("auxinuxos-kernel.list");
        assert!(!result.ok);

        // Traversee de chemin refusee avant tout appel privilegie.
        assert!(!remove_apt_source("../../etc/passwd").ok);
        assert!(!set_apt_source_enabled("../../etc/passwd", false).ok);
    }
}
