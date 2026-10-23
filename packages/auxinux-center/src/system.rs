//! Section SYSTEME: informations de base et avancees.

use sysinfo::{CpuRefreshKind, Disks, MemoryRefreshKind, RefreshKind, System};

use crate::model::{DiskInfo, SystemReport};
use crate::util::run;

pub const MB: u64 = 1024 * 1024;
pub const GB: u64 = 1024 * 1024 * 1024;

pub fn info(advanced: bool) -> SystemReport {
    // Rafraichissement CIBLE. `System::new_all()` enumere TOUS les processus,
    // avec leurs lignes de commande et leurs cartes memoire, puis
    // `refresh_all()` recommencait le meme travail: deux parcours complets de
    // /proc pour n'afficher au final qu'un modele de CPU, une quantite de
    // memoire et des disques. Le rapport de sante appelle cette fonction a
    // chaque analyse.
    let sys = System::new_with_specifics(
        RefreshKind::new()
            .with_cpu(CpuRefreshKind::new())
            .with_memory(MemoryRefreshKind::everything()),
    );

    let cpu = sys
        .cpus()
        .first()
        .map(|c| c.brand().trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "inconnu".into());

    let disks = Disks::new_with_refreshed_list();
    let disk_info: Vec<DiskInfo> = disks
        .iter()
        .filter(|d| d.total_space() > 0)
        .map(|d| DiskInfo {
            mount: d.mount_point().to_string_lossy().to_string(),
            total_gb: d.total_space() / GB,
            available_gb: d.available_space() / GB,
        })
        .collect();

    let mut report = SystemReport {
        product: product_name(),
        os: System::long_os_version().unwrap_or_else(|| "Debian 13 (trixie)".into()),
        kernel: System::kernel_version().unwrap_or_else(|| "inconnu".into()),
        hostname: System::host_name().unwrap_or_else(|| "inconnu".into()),
        arch: System::cpu_arch().unwrap_or_else(|| "inconnu".into()),
        cpu,
        cpu_cores: sys.cpus().len(),
        memory_total_mb: sys.total_memory() / MB,
        memory_used_mb: sys.used_memory() / MB,
        disks: disk_info,
        desktop: None,
        session_type: None,
        gpu: None,
        uptime_min: None,
        flatpak_runtimes: None,
    };

    if advanced {
        report.desktop = std::env::var("XDG_CURRENT_DESKTOP").ok();
        report.session_type = std::env::var("XDG_SESSION_TYPE").ok();
        report.uptime_min = Some(System::uptime() / 60);

        // GPU via lspci (si present).
        let gpu = run("sh", &["-c", "lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 | sed 's/.*: //'"]);
        if gpu.ok && !gpu.stdout.trim().is_empty() {
            report.gpu = Some(gpu.stdout.trim().to_string());
        }

        // Nombre de runtimes Flatpak installes.
        let rt = run("flatpak", &["list", "--runtime", "--columns=application"]);
        if rt.ok {
            report.flatpak_runtimes =
                Some(rt.stdout.lines().filter(|l| !l.trim().is_empty()).count() as u64);
        }
    }

    report
}

/// Nom produit lu depuis /etc/os-release, avec repli sur la valeur compilee.
/// Coder la version en dur obligeait a modifier le Rust a chaque version.
fn product_name() -> String {
    if let Ok(content) = std::fs::read_to_string("/etc/os-release") {
        for line in content.lines() {
            if let Some(v) = line.strip_prefix("PRETTY_NAME=") {
                let v = v.trim().trim_matches('"');
                if !v.is_empty() {
                    return v.to_string();
                }
            }
        }
    }
    "AuxiNux OS".into()
}

/// Ouvre les reglages du bureau, detache: le Center ne l'attend pas.
///
/// Le bureau par defaut est KDE Plasma depuis la 0.2.0, mais le Center doit
/// survivre a un CHANGEMENT de bureau (Plasma <-> GNOME): un binaire code en
/// dur laisserait un bouton mort sur toute machine qui a change de bureau.
/// On essaie donc les candidats dans l'ordre et on s'arrete au premier qui
/// demarre.
pub fn open_system_settings() {
    use std::process::{Command, Stdio};
    // Les Parametres d'AuxiNux Shell d'abord: depuis 2026-10-23 Plasma (et
    // systemsettings) n'est plus dans l'image, et ce bouton ne faisait rien.
    for candidate in [
        "auxinux-settings",
        "systemsettings",
        "gnome-control-center",
        "cosmic-settings",
    ] {
        let spawned = Command::new(candidate)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        if spawned.is_ok() {
            return;
        }
    }
}

/// Theme d'icones a donner a l'interface.
///
/// libcosmic cherche ses icones dans le theme « Cosmic », qui n'existe pas
/// sous Plasma: AUCUNE icone ne s'affichait. Ni celles de la barre laterale,
/// ni les boutons reduire, agrandir et fermer de la fenetre -- l'en-tete est
/// dessine par l'application et ces boutons sont, eux aussi, des icones du
/// theme. On prend le theme choisi dans Plasma, puis Breeze, puis Adwaita: le
/// premier qui est reellement installe.
pub fn icon_theme() -> Option<String> {
    let installed = icon_dirs();
    kde_icon_theme()
        .into_iter()
        .chain(["breeze".to_string(), "Adwaita".to_string()])
        .find(|name| {
            installed
                .iter()
                .any(|dir| dir.join(name).join("index.theme").is_file())
        })
}

/// Theme d'icones de Plasma: `[Icons] Theme=` de kdeglobals, le fichier de
/// l'utilisateur d'abord, puis les defauts du systeme (/etc/xdg).
fn kde_icon_theme() -> Option<String> {
    xdg_dirs("XDG_CONFIG_HOME", ".config", "XDG_CONFIG_DIRS", "/etc/xdg")
        .into_iter()
        .find_map(|dir| {
            let text = std::fs::read_to_string(dir.join("kdeglobals")).ok()?;
            ini_value(&text, "Icons", "Theme")
        })
}

fn icon_dirs() -> Vec<std::path::PathBuf> {
    let mut dirs: Vec<std::path::PathBuf> =
        xdg_dirs("XDG_DATA_HOME", ".local/share", "XDG_DATA_DIRS", "/usr/local/share:/usr/share")
            .into_iter()
            .map(|d| d.join("icons"))
            .collect();
    if let Some(home) = std::env::var_os("HOME") {
        dirs.push(std::path::PathBuf::from(home).join(".icons"));
    }
    dirs
}

/// Repertoire personnel XDG puis repertoires systeme, dans l'ordre de priorite.
pub(crate) fn xdg_dirs(home_var: &str, home_default: &str, sys_var: &str, sys_default: &str) -> Vec<std::path::PathBuf> {
    let mut dirs = Vec::new();
    match std::env::var_os(home_var).filter(|v| !v.is_empty()) {
        Some(dir) => dirs.push(std::path::PathBuf::from(dir)),
        None => {
            if let Some(home) = std::env::var_os("HOME") {
                dirs.push(std::path::PathBuf::from(home).join(home_default));
            }
        }
    }
    let system = std::env::var(sys_var)
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| sys_default.to_string());
    dirs.extend(system.split(':').filter(|d| !d.is_empty()).map(std::path::PathBuf::from));
    dirs
}

/// Valeur d'une cle dans un fichier au format INI de KDE.
fn ini_value(text: &str, section: &str, key: &str) -> Option<String> {
    let header = format!("[{section}]");
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == header;
            continue;
        }
        if !inside {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            if k.trim() == key && !v.trim().is_empty() {
                return Some(v.trim().to_string());
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::ini_value;

    #[test]
    fn reads_the_icon_theme_of_its_own_section_only() {
        let kdeglobals = "[General]\nTheme=pas-ceci\n\n[Icons]\nTheme=breeze-dark\n\n[KDE]\nSingleClick=false\n";
        assert_eq!(ini_value(kdeglobals, "Icons", "Theme").as_deref(), Some("breeze-dark"));
    }

    #[test]
    fn missing_or_empty_key_gives_nothing() {
        assert_eq!(ini_value("[Icons]\nTheme=\n", "Icons", "Theme"), None);
        assert_eq!(ini_value("[KDE]\nSingleClick=false\n", "Icons", "Theme"), None);
    }
}
