//! Section APPS: recherche, fiche detaillee, installation, desinstallation,
//! mise a jour.
//!
//! Priorite de source: Flathub d'abord. Si une application existe sur Flathub
//! ET en DEB, la source par defaut est Flathub mais l'utilisateur peut basculer
//! sur AuxiNux (DEB). Si elle n'existe PAS sur Flathub mais est disponible en
//! DEB, elle est affichee avec la source AuxiNux (DEB).
//!
//! Les metadonnees riches de la fiche (icone HD, captures, description) viennent
//! de l'API publique Flathub v2; les icones des tuiles viennent du cache
//! AppStream local de Flatpak (rapide, hors-ligne).

use serde_json::Value;

use crate::model::{
    ActionResult, AppDetails, AppEntry, AppStatus, SOURCE_DEB, SOURCE_FLATHUB,
};
use crate::util::{run, run_pkexec};

const MAX_DEB_RESULTS: usize = 60;

/// identifiers reach `pkexec auxi/apt-get/flatpak <id>` as argv. argv
/// means no shell injection, but an id starting with `-` would be read as an
/// apt/flatpak option. Accept only a plain package name or Flatpak app-id
/// and never a leading dash.
fn is_safe_app_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 255
        && !id.starts_with('-')
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '+'))
}

/// Le vrai binaire apt-cache (les commandes apt/apt-cache sont detournees vers
/// le wrapper `auxi`; pour une recherche en lecture seule on contourne la
/// politique en appelant directement le binaire reel detourne par dpkg-divert).
fn apt_cache_bin() -> &'static str {
    if std::path::Path::new("/usr/lib/auxinux/apt-real/apt-cache").exists() {
        "/usr/lib/auxinux/apt-real/apt-cache"
    } else {
        "apt-cache"
    }
}

/// Icone d'une app Flatpak depuis le cache AppStream local (hors-ligne).
fn flatpak_icon_path(id: &str) -> String {
    let arch = std::env::consts::ARCH; // "x86_64"
    for size in ["128x128", "64x64"] {
        let p = format!(
            "/var/lib/flatpak/appstream/flathub/{arch}/active/icons/{size}/{id}.png"
        );
        if std::path::Path::new(&p).exists() {
            return format!("file://{p}");
        }
    }
    String::new()
}

fn flatpak_matches_deb(app: &AppEntry, deb_name: &str) -> bool {
    let deb = deb_name.to_lowercase();
    let id = app.id.to_lowercase();
    let name = app.name.to_lowercase();
    name == deb || id.rsplit('.').next().map(|s| s == deb).unwrap_or(false) || id.ends_with(&deb)
}

pub fn search(query: &str) -> Vec<AppEntry> {
    let query = query.trim();
    if query.len() < 2 {
        return Vec::new();
    }

    let mut entries: Vec<AppEntry> = Vec::new();

    // --- Flathub (prioritaire) ---
    let fp = run(
        "flatpak",
        &["search", "--columns=application,name,description,version", query],
    );
    if fp.ok {
        for line in fp.stdout.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let cols: Vec<&str> = line.split('\t').collect();
            let id = cols.first().copied().unwrap_or("").trim();
            if id.is_empty() {
                continue;
            }
            entries.push(AppEntry {
                id: id.to_string(),
                name: cols.get(1).copied().unwrap_or(id).trim().to_string(),
                summary: cols.get(2).copied().unwrap_or("").trim().to_string(),
                version: cols.get(3).copied().unwrap_or("").trim().to_string(),
                sources: vec![SOURCE_FLATHUB.into()],
                default_source: SOURCE_FLATHUB.into(),
                icon: flatpak_icon_path(id),
                deb_name: None,
            });
        }
    }

    // --- DEB (apt-cache search) ---
    let deb = run(apt_cache_bin(), &["search", query]);
    if deb.ok {
        let mut added = 0usize;
        for line in deb.stdout.lines() {
            if added >= MAX_DEB_RESULTS {
                break;
            }
            let Some((name, desc)) = line.split_once(" - ") else { continue };
            let name = name.trim();
            if name.is_empty() {
                continue;
            }
            if let Some(e) = entries.iter_mut().find(|e| flatpak_matches_deb(e, name)) {
                if !e.has_source(SOURCE_DEB) {
                    e.sources.push(SOURCE_DEB.into());
                }
                // Sans cette ligne, basculer la fiche sur DEB enverrait
                // l'app-id Flatpak a apt-get.
                e.deb_name.get_or_insert_with(|| name.to_string());
                continue;
            }
            entries.push(AppEntry {
                id: name.to_string(),
                name: name.to_string(),
                summary: desc.trim().to_string(),
                version: String::new(),
                sources: vec![SOURCE_DEB.into()],
                default_source: SOURCE_DEB.into(),
                icon: String::new(),
                deb_name: Some(name.to_string()),
            });
            added += 1;
        }
    }

    entries
}

/// Selection d'applications mises en avant a l'ouverture (Flathub + DEB si disponible).
pub fn featured() -> Vec<AppEntry> {
    // (flatpak_id, nom, resume, paquet_deb_candidat)
    let curated: &[(&str, &str, &str, &str)] = &[
        ("org.videolan.VLC",          "VLC",        "Lecteur multimedia universel",              "vlc"),
        ("org.mozilla.firefox",        "Firefox",    "Navigateur web respectueux de la vie privee","firefox"),
        ("org.gimp.GIMP",              "GIMP",       "Retouche et edition d'images",              "gimp"),
        ("org.kde.krita",              "Krita",      "Peinture numerique et illustration",         "krita"),
        ("org.libreoffice.LibreOffice","LibreOffice","Suite bureautique complete",                  "libreoffice"),
        ("com.obsproject.Studio",      "OBS Studio", "Enregistrement et streaming video",          "obs-studio"),
        ("org.blender.Blender",        "Blender",    "Creation 3D, animation, rendu",              "blender"),
        ("org.kde.kdenlive",           "Kdenlive",   "Montage video non lineaire",                 "kdenlive"),
        ("org.audacityteam.Audacity",  "Audacity",   "Edition audio multipiste",                   "audacity"),
        ("org.inkscape.Inkscape",      "Inkscape",   "Dessin vectoriel",                           "inkscape"),
        ("org.signal.Signal",          "Signal",     "Messagerie chiffree, vie privee",            "signal-desktop"),
        ("org.telegram.desktop",       "Telegram",   "Messagerie rapide",                          "telegram-desktop"),
    ];

    // Verification des paquets DEB en un seul appel apt-cache.
    let deb_candidates: Vec<&str> = curated.iter().map(|(_, _, _, d)| *d).collect();
    let mut args = vec!["show", "--no-all-versions"];
    args.extend(deb_candidates.iter().copied());
    let deb_out = run(apt_cache_bin(), &args);
    let mut available_debs: std::collections::HashSet<String> = std::collections::HashSet::new();
    for line in deb_out.stdout.lines() {
        if let Some(rest) = line.strip_prefix("Package:") {
            available_debs.insert(rest.trim().to_string());
        }
    }

    let entries: Vec<AppEntry> = curated
        .iter()
        .map(|(id, name, summary, deb)| {
            let mut sources = vec![SOURCE_FLATHUB.into()];
            let mut deb_name = None;
            if available_debs.contains(*deb) {
                sources.push(SOURCE_DEB.into());
                deb_name = Some((*deb).to_string());
            }
            AppEntry {
                id: id.to_string(),
                name: name.to_string(),
                summary: summary.to_string(),
                version: String::new(),
                sources,
                default_source: SOURCE_FLATHUB.into(),
                icon: flatpak_icon_path(id),
                deb_name,
            }
        })
        .collect();
    entries
}

pub fn list_installed() -> Vec<AppEntry> {
    let mut entries: Vec<AppEntry> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    // --- Applications Flatpak ---
    let fp = run(
        "flatpak",
        &["list", "--app", "--columns=application,name,version,origin"],
    );
    if fp.ok {
        for line in fp.stdout.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let cols: Vec<&str> = line.split('\t').collect();
            let id = cols.first().copied().unwrap_or("").trim();
            if id.is_empty() {
                continue;
            }
            let name = cols.get(1).copied().unwrap_or(id).trim().to_string();
            seen.insert(name.to_lowercase());
            entries.push(AppEntry {
                id: id.to_string(),
                name,
                summary: format!("Flatpak — origine: {}", cols.get(3).copied().unwrap_or("").trim()),
                version: cols.get(2).copied().unwrap_or("").trim().to_string(),
                sources: vec![SOURCE_FLATHUB.into()],
                default_source: SOURCE_FLATHUB.into(),
                icon: flatpak_icon_path(id),
                deb_name: None,
            });
        }
    }

    // --- Applications DEB installees (entrees de menu .desktop) ---
    // On resout le NOM DE PAQUET de chaque .desktop (l'id du fichier, ex.
    // org.kde.kate, n'est pas le paquet "kate") pour que install/remove/status
    // fonctionnent ensuite.
    let pkg_map = desktop_package_map();
    if let Ok(rd) = std::fs::read_dir("/usr/share/applications") {
        for f in rd.flatten() {
            let path = f.path();
            if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            if let Some(app) = parse_desktop(&path, &pkg_map) {
                if seen.insert(app.name.to_lowercase()) {
                    entries.push(app);
                }
            }
        }
    }

    entries.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    entries
}

/// Construit une table {nom-de-fichier-.desktop-sans-extension -> paquet} via
/// une seule invocation `dpkg -S` sur le dossier des applications.
fn desktop_package_map() -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    let out = run("dpkg", &["-S", "/usr/share/applications/"]);
    if out.ok {
        for line in out.stdout.lines() {
            // Format: "pkg1, pkg2: /usr/share/applications/foo.desktop"
            if let Some((pkgs, path)) = line.split_once(": ") {
                if path.ends_with(".desktop") {
                    if let Some(stem) = std::path::Path::new(path.trim()).file_stem() {
                        let pkg = pkgs.split(',').next().unwrap_or(pkgs).trim().to_string();
                        map.insert(stem.to_string_lossy().to_string(), pkg);
                    }
                }
            }
        }
    }
    map
}

/// Lit une entree .desktop et renvoie une AppEntry si c'est une application
/// visible (non NoDisplay). L'icone est le nom de theme ou un chemin.
fn parse_desktop(
    path: &std::path::Path,
    pkg_map: &std::collections::HashMap<String, String>,
) -> Option<AppEntry> {
    let content = std::fs::read_to_string(path).ok()?;
    let (mut name, mut name_fr) = (String::new(), String::new());
    let (mut comment, mut comment_fr) = (String::new(), String::new());
    let mut icon = String::new();
    let mut is_app = false;
    let mut hidden = false;
    let mut in_entry = false;

    for line in content.lines() {
        let l = line.trim();
        if l.starts_with('[') {
            in_entry = l == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        if let Some(v) = l.strip_prefix("Type=") {
            is_app = v.trim() == "Application";
        } else if let Some(v) = l.strip_prefix("NoDisplay=") {
            if v.trim() == "true" { hidden = true; }
        } else if let Some(v) = l.strip_prefix("Hidden=") {
            if v.trim() == "true" { hidden = true; }
        } else if let Some(v) = l.strip_prefix("Name[fr]=") {
            name_fr = v.trim().to_string();
        } else if let Some(v) = l.strip_prefix("Name=") {
            name = v.trim().to_string();
        } else if let Some(v) = l.strip_prefix("Comment[fr]=") {
            comment_fr = v.trim().to_string();
        } else if let Some(v) = l.strip_prefix("Comment=") {
            comment = v.trim().to_string();
        } else if let Some(v) = l.strip_prefix("Icon=") {
            icon = v.trim().to_string();
        }
    }

    if !is_app || hidden {
        return None;
    }
    let final_name = if !name_fr.is_empty() { name_fr } else { name };
    if final_name.is_empty() {
        return None;
    }
    let stem = path.file_stem()?.to_string_lossy().to_string();
    let id = pkg_map.get(&stem).cloned().unwrap_or(stem);
    Some(AppEntry {
        id: id.clone(),
        name: final_name,
        summary: if !comment_fr.is_empty() { comment_fr } else { comment },
        version: String::new(),
        sources: vec![SOURCE_DEB.into()],
        default_source: SOURCE_DEB.into(),
        icon,
        deb_name: Some(id),
    })
}

// ---------------------------------------------------------------------------
// Fiche detaillee
// ---------------------------------------------------------------------------

pub fn app_details(id: &str, source: &str) -> AppDetails {
    if source != SOURCE_DEB {
        if let Some(d) = flathub_details(id) {
            return d;
        }
    }
    deb_details(id)
}

fn flathub_details(id: &str) -> Option<AppDetails> {
    let url = format!("https://flathub.org/api/v2/appstream/{id}");
    let out = run("curl", &["-fsSL", "--max-time", "12", &url]);
    if !out.ok || out.stdout.trim().is_empty() {
        return None;
    }
    let v: Value = serde_json::from_str(&out.stdout).ok()?;
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();

    let version = v
        .get("releases")
        .and_then(|r| r.as_array())
        .and_then(|a| a.first())
        .and_then(|r| r.get("version"))
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();

    let homepage = v
        .get("urls")
        .and_then(|u| u.get("homepage"))
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();

    let mut screenshots = Vec::new();
    if let Some(arr) = v.get("screenshots").and_then(|s| s.as_array()) {
        for sc in arr.iter().take(4) {
            if let Some(sizes) = sc.get("sizes").and_then(|z| z.as_array()) {
                let pick = sizes
                    .iter()
                    .find(|s| s.get("width").and_then(|w| w.as_str()) == Some("752"))
                    .or_else(|| sizes.iter().find(|s| s.get("width").and_then(|w| w.as_str()) == Some("624")))
                    .or_else(|| sizes.first());
                if let Some(p) = pick.and_then(|p| p.get("src")).and_then(|x| x.as_str()) {
                    screenshots.push(p.to_string());
                }
            }
        }
    }

    Some(AppDetails {
        name: if s("name").is_empty() { id.to_string() } else { s("name") },
        summary: s("summary"),
        description: strip_html(&s("description")),
        version,
        license: s("project_license"),
        homepage,
        icon: s("icon"),
        screenshots,
    })
}

fn deb_details(id: &str) -> AppDetails {
    let out = run(apt_cache_bin(), &["show", id]);
    let mut summary = String::new();
    let mut description = String::new();
    let mut version = String::new();
    let mut homepage = String::new();
    if out.ok {
        let mut in_desc = false;
        for line in out.stdout.lines() {
            if let Some(rest) = line.strip_prefix("Description:") {
                if summary.is_empty() {
                    summary = rest.trim().to_string();
                }
                in_desc = true;
                continue;
            }
            if let Some(rest) = line.strip_prefix("Version:") {
                if version.is_empty() {
                    version = rest.trim().to_string();
                }
                continue;
            }
            if let Some(rest) = line.strip_prefix("Homepage:") {
                homepage = rest.trim().to_string();
                continue;
            }
            if in_desc {
                if line.starts_with(' ') {
                    let t = line.trim();
                    description.push_str(if t == "." { "" } else { t });
                    description.push('\n');
                } else {
                    in_desc = false;
                }
            }
        }
    }
    AppDetails {
        name: id.to_string(),
        summary,
        description: description.trim().to_string(),
        version,
        license: String::new(),
        homepage,
        icon: String::new(),
        screenshots: vec![],
    }
}

/// Convertit la description HTML de Flathub en texte lisible.
fn strip_html(s: &str) -> String {
    let pre = s
        .replace("</p>", "\n\n")
        .replace("<br>", "\n")
        .replace("<br/>", "\n")
        .replace("<br />", "\n")
        .replace("<li>", "• ")
        .replace("</li>", "\n");
    let mut out = String::new();
    let mut in_tag = false;
    for c in pre.chars() {
        match c {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    out.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .trim()
        .to_string()
}

// ---------------------------------------------------------------------------
// Etat d'installation (pour des boutons contextuels)
// ---------------------------------------------------------------------------

pub fn app_status(id: &str, source: &str) -> AppStatus {
    if source == SOURCE_DEB {
        deb_status(id)
    } else {
        flatpak_status(id)
    }
}

fn flatpak_status(id: &str) -> AppStatus {
    let info = run("flatpak", &["info", id]);
    if !info.ok {
        return AppStatus { installed: false, update_available: false };
    }
    let installed_commit = line_value(&info.stdout, "Commit:");
    let remote = run("flatpak", &["remote-info", "flathub", id]);
    let update_available = if remote.ok {
        let rc = line_value(&remote.stdout, "Commit:");
        !rc.is_empty() && !installed_commit.is_empty() && rc != installed_commit
    } else {
        false
    };
    AppStatus { installed: true, update_available }
}

fn deb_status(id: &str) -> AppStatus {
    let q = run("dpkg-query", &["-W", "-f=${Status}", id]);
    let installed = q.ok && q.stdout.contains("install ok installed");
    if !installed {
        return AppStatus { installed: false, update_available: false };
    }
    let pol = run(apt_cache_bin(), &["policy", id]);
    let inst = line_value(&pol.stdout, "Installed:");
    let cand = line_value(&pol.stdout, "Candidate:");
    let update_available = !inst.is_empty() && inst != "(none)" && !cand.is_empty() && cand != inst;
    AppStatus { installed: true, update_available }
}

/// Premiere valeur apres une cle "Cle:" dans une sortie texte (lignes trimmees).
fn line_value(text: &str, key: &str) -> String {
    for line in text.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix(key) {
            return rest.trim().to_string();
        }
    }
    String::new()
}

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

pub fn install(id: &str, source: &str) -> ActionResult {
    if !is_safe_app_id(id) {
        return ActionResult::err("identifiant d'application invalide");
    }
    let out = match source {
        SOURCE_FLATHUB | "flatpak" => run("flatpak", &["install", "-y", "flathub", id]),
        _ => run_pkexec(&["auxi", "install", "--deb", id]),
    };
    if out.ok {
        ActionResult::ok(format!("Installe: {id}"))
    } else {
        ActionResult::err(tail(&out.stderr))
    }
}

pub fn remove(id: &str, source: &str) -> ActionResult {
    if !is_safe_app_id(id) {
        return ActionResult::err("identifiant d'application invalide");
    }
    let out = match source {
        SOURCE_FLATHUB | "flatpak" => run("flatpak", &["uninstall", "-y", id]),
        _ => run_pkexec(&["auxi", "uninstall", "--deb", id]),
    };
    if out.ok {
        ActionResult::ok(format!("Desinstalle: {id}"))
    } else {
        ActionResult::err(tail(&out.stderr))
    }
}

pub fn update_app(id: &str, source: &str) -> ActionResult {
    if !is_safe_app_id(id) {
        return ActionResult::err("identifiant d'application invalide");
    }
    let out = match source {
        SOURCE_FLATHUB | "flatpak" => run("flatpak", &["update", "-y", id]),
        // update only the requested package, not the whole system.
        _ => run_pkexec(&["auxi", "install", "--deb", id]),
    };
    if out.ok {
        ActionResult::ok("Mise a jour terminee")
    } else {
        ActionResult::err(tail(&out.stderr))
    }
}

/// consolidated "what has an update" list across Flatpak and DEB, so
/// the UI can offer a single updates view instead of one fiche per app.
pub fn list_updates() -> Vec<AppEntry> {
    let mut entries: Vec<AppEntry> = Vec::new();

    // Flatpak apps with a newer commit on their remote.
    let fp = run(
        "flatpak",
        &["remote-ls", "--updates", "--app", "--columns=application,name,version"],
    );
    if fp.ok {
        for line in fp.stdout.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let cols: Vec<&str> = line.split('\t').collect();
            let id = cols.first().copied().unwrap_or("").trim();
            if id.is_empty() {
                continue;
            }
            entries.push(AppEntry {
                id: id.to_string(),
                name: cols.get(1).copied().unwrap_or(id).trim().to_string(),
                summary: "Mise a jour Flatpak disponible".into(),
                version: cols.get(2).copied().unwrap_or("").trim().to_string(),
                sources: vec![SOURCE_FLATHUB.into()],
                default_source: SOURCE_FLATHUB.into(),
                icon: flatpak_icon_path(id),
                deb_name: None,
            });
        }
    }

    // Upgradable DEB packages (simulated upgrade, read-only).
    let deb = run(apt_cache_bin(), &["-s", "upgrade"]);
    let apt_get_sim = if deb.ok && deb.stdout.contains("Inst ") {
        deb
    } else {
        // apt-cache has no `upgrade`; use the real apt-get in dry-run mode.
        run(apt_get_bin(), &["-s", "upgrade"])
    };
    if apt_get_sim.ok {
        for line in apt_get_sim.stdout.lines() {
            // Format: "Inst <pkg> [old] (new arch ...)"
            let Some(rest) = line.strip_prefix("Inst ") else { continue };
            let pkg = rest.split_whitespace().next().unwrap_or("").to_string();
            if pkg.is_empty() {
                continue;
            }
            let version = rest
                .split_once('(')
                .and_then(|(_, r)| r.split_whitespace().next())
                .unwrap_or("")
                .to_string();
            entries.push(AppEntry {
                id: pkg.clone(),
                name: pkg.clone(),
                summary: "Mise a jour DEB disponible".into(),
                version,
                sources: vec![SOURCE_DEB.into()],
                default_source: SOURCE_DEB.into(),
                icon: String::new(),
                deb_name: Some(pkg),
            });
        }
    }

    entries
}

/// The real apt-get binary (diverted by dpkg-divert), for read-only dry-run
/// queries. Falls back to the wrapper name if the divert is absent (dev).
fn apt_get_bin() -> &'static str {
    if std::path::Path::new("/usr/lib/auxinux/apt-real/apt-get").exists() {
        "/usr/lib/auxinux/apt-real/apt-get"
    } else {
        "apt-get"
    }
}

fn tail(s: &str) -> String {
    let lines: Vec<&str> = s.lines().filter(|l| !l.trim().is_empty()).collect();
    let start = lines.len().saturating_sub(6);
    let msg = lines[start..].join("\n");
    if msg.is_empty() { "Echec de l'operation".into() } else { msg }
}
