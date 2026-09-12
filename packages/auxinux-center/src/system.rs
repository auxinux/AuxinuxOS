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

/// Opens the COSMIC settings application (replaces the old KDE
/// systemsettings:// URL handler). Detached: the Center does not wait for it.
pub fn open_system_settings() {
    use std::process::{Command, Stdio};
    let _ = Command::new("cosmic-settings")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}
