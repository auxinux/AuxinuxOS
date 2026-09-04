//! Section SOURCES: depots APT (activer/desactiver/ajouter/retirer), depots
//! connus (orientes vie privee/liberte), remotes Flatpak (activer/desactiver),
//! et politique APT maison (`auxi set apt=`).
//!
//! Securite: toute ecriture sous /etc passe par `pkexec` (agent polkit). Les
//! cles sont installees sous /etc/apt/keyrings avec `Signed-By` (jamais
//! apt-key). Les depots systeme (auxinux*, brave*) sont proteges contre la
//! suppression.

use std::fs;
use std::path::Path;

use crate::model::{ActionResult, AptSource, FlatpakRemote, SourcePreset};
use crate::util::{run, run_pkexec, run_pkexec_script};

const SOURCES_DIR: &str = "/etc/apt/sources.list.d";

fn pretty_name(file: &str) -> String {
    file.trim_end_matches(".disabled")
        .trim_end_matches(".sources")
        .trim_end_matches(".list")
        .replace(['-', '_'], " ")
}

fn is_protected(base: &str) -> bool {
    base.starts_with("auxinux") || base.starts_with("brave")
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
        return ActionResult::ok("deja dans l'etat demande");
    }
    let out = run_pkexec(&["mv", "-f", &from, &to]);
    if out.ok {
        let _ = run_pkexec(&["auxi", "update"]);
        ActionResult::ok(if enabled { "Depot active" } else { "Depot desactive" })
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
        return ActionResult::err("Depot systeme protege (non supprimable)");
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
        ActionResult::ok("Depot retire")
    } else {
        ActionResult::ok("rien a retirer")
    }
}

// ---------------------------------------------------------------------------
// Depots connus (presets)
// ---------------------------------------------------------------------------

struct PresetDef {
    name: &'static str,
    desc: &'static str,
    key_url: &'static str,
    body: &'static str,
}

fn preset_defs() -> Vec<(&'static str, PresetDef)> {
    vec![
        ("vscode", PresetDef {
            name: "Visual Studio Code",
            desc: "Editeur de code Microsoft, tres populaire.",
            key_url: "https://packages.microsoft.com/keys/microsoft.asc",
            body: "Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/vscode.asc\n",
        }),
        ("docker", PresetDef {
            name: "Docker CE",
            desc: "Moteur de conteneurs Docker (depot officiel).",
            key_url: "https://download.docker.com/linux/debian/gpg",
            body: "Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: trixie\nComponents: stable\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/docker.asc\n",
        }),
        ("mozilla", PresetDef {
            name: "Mozilla Firefox",
            desc: "Firefox officiel par Mozilla, mises a jour rapides.",
            key_url: "https://packages.mozilla.org/apt/repo-signing-key.gpg",
            body: "Types: deb\nURIs: https://packages.mozilla.org/apt\nSuites: mozilla\nComponents: main\nSigned-By: /etc/apt/keyrings/mozilla.asc\n",
        }),
        ("mullvad", PresetDef {
            name: "Mullvad VPN",
            desc: "VPN axe vie privee, sans journaux, paiement anonyme possible.",
            key_url: "https://repository.mullvad.net/deb/mullvad-keyring.asc",
            body: "Types: deb\nURIs: https://repository.mullvad.net/deb/stable\nSuites: trixie\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/mullvad.asc\n",
        }),
        ("signal", PresetDef {
            name: "Signal Desktop",
            desc: "Messagerie chiffree de bout en bout, orientee vie privee.",
            key_url: "https://updates.signal.org/desktop/apt/keys.asc",
            body: "Types: deb\nURIs: https://updates.signal.org/desktop/apt\nSuites: xenial\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/signal.asc\n",
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
    // Presets are compile-time constants, but the writer path is shared with
    // user input; assert their safety so a bad edit can't reopen the
    // hole.
    if !is_safe_key_url(d.key_url) || !is_safe_sources_body(d.body) {
        return ActionResult::err("preset interne invalide");
    }
    let out = run_pkexec_script(&preset_script(id, d.key_url, d.body));
    if out.ok {
        ActionResult::ok(format!("Depot '{}' ajoute", d.name))
    } else {
        ActionResult::err(out.stderr)
    }
}

fn preset_script(id: &str, key_url: &str, sources_body: &str) -> String {
    format!(
        r#"set -euo pipefail
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "{key_url}" -o /etc/apt/keyrings/{id}.asc
chmod 0644 /etc/apt/keyrings/{id}.asc
cat > /etc/apt/sources.list.d/{id}.sources <<'AUXIEOF'
{sources_body}AUXIEOF
auxi update || apt-get update || true
"#
    )
}

pub fn add_custom_apt_source(name: &str, sources_body: &str, key_url: &str) -> ActionResult {
    let safe: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
        .collect();
    if safe.is_empty() {
        return ActionResult::err("nom invalide");
    }
    // both fields are written/executed in root context. Validate
    // before building the script so neither can inject shell.
    if !is_safe_sources_body(sources_body) {
        return ActionResult::err(
            "corps de depot invalide (champs deb822 attendus, sans caractere special)",
        );
    }
    let key_trimmed = key_url.trim();
    let key_part = if key_trimmed.is_empty() {
        String::new()
    } else {
        if !is_safe_key_url(key_trimmed) {
            return ActionResult::err("URL de cle invalide (https:// requis)");
        }
        format!(
            "install -d -m 0755 /etc/apt/keyrings\ncurl -fsSL \"{key_trimmed}\" -o /etc/apt/keyrings/{safe}.asc\nchmod 0644 /etc/apt/keyrings/{safe}.asc\n"
        )
    };
    let script = format!(
        r#"set -euo pipefail
{key_part}cat > /etc/apt/sources.list.d/{safe}.sources <<'AUXIEOF'
{sources_body}
AUXIEOF
auxi update || apt-get update || true
"#
    );
    let out = run_pkexec_script(&script);
    if out.ok {
        ActionResult::ok(format!("Depot '{safe}' ajoute"))
    } else {
        ActionResult::err(out.stderr)
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
        ActionResult::ok("Remote mis a jour")
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
        ActionResult::ok("Politique APT mise a jour")
    } else {
        ActionResult::err(out.stderr)
    }
}
