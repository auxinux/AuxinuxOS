//! Section SYSTEME: informations de base et avancees.

use serde::Serialize;
use sysinfo::{Disks, System};

use crate::util::run;

#[derive(Serialize)]
struct DiskInfo {
    mount: String,
    total_gb: u64,
    available_gb: u64,
}

#[derive(Serialize)]
struct SystemReport {
    product: String,
    os: String,
    kernel: String,
    hostname: String,
    arch: String,
    cpu: String,
    cpu_cores: usize,
    memory_total_mb: u64,
    memory_used_mb: u64,
    disks: Vec<DiskInfo>,
    // Champs avances (optionnels).
    desktop: Option<String>,
    session_type: Option<String>,
    gpu: Option<String>,
    uptime_min: Option<u64>,
    flatpak_runtimes: Option<u64>,
}

const MB: u64 = 1024 * 1024;
const GB: u64 = 1024 * 1024 * 1024;

pub fn info(advanced: bool) -> String {
    let mut sys = System::new_all();
    sys.refresh_all();

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
        product: "AuxiNux OS EN 0.1-BETA".into(),
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

    serde_json::to_string(&report).unwrap_or_else(|_| "{}".into())
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
