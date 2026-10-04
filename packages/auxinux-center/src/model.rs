//! Types partages entre le backend, le mode CLI et l'interface.
//!
//! Avant la 0.2, chaque module renvoyait du JSON dans une `String` et l'UI le
//! reserialisait. Ce detour coutait une double (de)serialisation a chaque
//! affichage et surtout il PERDAIT de l'information: la fusion Flatpak/DEB ne
//! conservait qu'un seul identifiant, si bien que choisir "DEB" sur une fiche
//! Flathub envoyait l'app-id Flatpak a apt-get et installait le mauvais paquet
//! (ou rien). Les types ci-dessous portent desormais un identifiant PAR
//! SOURCE, ce qui supprime la classe de bug entiere.

use serde::{Deserialize, Serialize};

pub const SOURCE_FLATHUB: &str = "flathub";
pub const SOURCE_DEB: &str = "auxinux-deb";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppEntry {
    /// Identifiant de la source par defaut (app-id Flatpak ou nom de paquet).
    pub id: String,
    pub name: String,
    pub summary: String,
    pub version: String,
    pub sources: Vec<String>,
    pub default_source: String,
    /// Chemin file:// de l'icone si trouvee dans le cache Flatpak, sinon "".
    pub icon: String,
    /// Nom du paquet DEB correspondant, quand il differe de `id`.
    ///
    /// C'est le champ qui corrige la fusion Flatpak/DEB: sans lui,
    /// `install(entry, "auxinux-deb")` passait "org.videolan.VLC" a apt-get au
    /// lieu de "vlc".
    #[serde(default)]
    pub deb_name: Option<String>,

    /// Application deja installee, PAR SOURCE.
    ///
    /// L'interface affichait « Installer » ET « Desinstaller » sur chaque
    /// fiche, sans jamais dire laquelle des deux s'appliquait: l'utilisateur
    /// ne pouvait pas savoir si une application etait deja presente, et
    /// « Installer » sur une application deja installee ne produisait qu'un
    /// message d'erreur d'apt. Ces deux champs sont remplis en deux appels
    /// pour toute une liste, jamais un par fiche.
    #[serde(default)]
    pub installed_flathub: bool,
    #[serde(default)]
    pub installed_deb: bool,
}

impl AppEntry {
    /// Identifiant a utiliser pour agir sur `source`.
    pub fn id_for(&self, source: &str) -> &str {
        if source == SOURCE_DEB {
            if let Some(name) = self.deb_name.as_deref() {
                return name;
            }
        }
        &self.id
    }

    pub fn has_source(&self, source: &str) -> bool {
        self.sources.iter().any(|s| s == source)
    }

    /// Vrai si l'application est installee VIA `source`.
    pub fn is_installed(&self, source: &str) -> bool {
        if source == SOURCE_DEB {
            self.installed_deb
        } else {
            self.installed_flathub
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct AppDetails {
    pub name: String,
    pub summary: String,
    pub description: String,
    pub version: String,
    pub license: String,
    pub homepage: String,
    pub icon: String,
    pub screenshots: Vec<String>,
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
pub struct AppStatus {
    pub installed: bool,
    pub update_available: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ActionResult {
    pub ok: bool,
    pub message: String,
}

impl ActionResult {
    pub fn ok(msg: impl Into<String>) -> Self {
        Self { ok: true, message: msg.into() }
    }

    pub fn err(msg: impl Into<String>) -> Self {
        Self { ok: false, message: msg.into() }
    }
}

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AptSource {
    pub file: String,
    pub name: String,
    pub kind: String,
    pub enabled: bool,
    /// Faux pour les depots systeme proteges (auxinux*, brave*).
    pub removable: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SourcePreset {
    pub id: String,
    pub name: String,
    pub description: String,
    /// Vrai si le depot est deja present (active ou desactive).
    pub installed: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FlatpakRemote {
    pub name: String,
    pub url: String,
    pub enabled: bool,
}

// ---------------------------------------------------------------------------
// Systeme
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DiskInfo {
    pub mount: String,
    pub total_gb: u64,
    pub available_gb: u64,
}

impl DiskInfo {
    pub fn used_ratio(&self) -> f32 {
        if self.total_gb == 0 {
            return 0.0;
        }
        let used = self.total_gb.saturating_sub(self.available_gb) as f32;
        used / self.total_gb as f32
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SystemReport {
    pub product: String,
    pub os: String,
    pub kernel: String,
    pub hostname: String,
    pub arch: String,
    pub cpu: String,
    pub cpu_cores: usize,
    pub memory_total_mb: u64,
    pub memory_used_mb: u64,
    pub disks: Vec<DiskInfo>,
    // Champs avances (optionnels).
    pub desktop: Option<String>,
    pub session_type: Option<String>,
    pub gpu: Option<String>,
    pub uptime_min: Option<u64>,
    pub flatpak_runtimes: Option<u64>,
}

// ---------------------------------------------------------------------------
// Sante
// ---------------------------------------------------------------------------

/// Gravite d'un point de controle. L'ordre compte: `Critical > Warning > Ok`,
/// ce qui permet de deduire l'etat global par un simple `max()`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Severity {
    Ok,
    Warning,
    Critical,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HealthCheck {
    pub id: String,
    pub title: String,
    pub detail: String,
    pub severity: Severity,
    /// Ce que l'utilisateur peut faire, en clair. Vide si rien a faire.
    pub advice: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HealthReport {
    pub checks: Vec<HealthCheck>,
}

impl HealthReport {
    pub fn overall(&self) -> Severity {
        self.checks.iter().map(|c| c.severity).max().unwrap_or(Severity::Ok)
    }

    pub fn count(&self, severity: Severity) -> usize {
        self.checks.iter().filter(|c| c.severity == severity).count()
    }
}

// ---------------------------------------------------------------------------
// Restauration
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Snapshot {
    pub number: u32,
    /// "single", "pre" ou "post".
    pub kind: String,
    pub date: String,
    pub description: String,
    /// Vrai si l'instantane a ete pose automatiquement par `auxi`.
    pub from_auxi: bool,
    /// Algorithme de nettoyage de snapper: "number", "timeline" ou vide.
    #[serde(default)]
    pub cleanup: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct RecoveryState {
    /// Faux si la racine n'est pas BTRFS ou si snapper n'est pas configure.
    pub available: bool,
    pub reason: String,
    pub snapshots: Vec<Snapshot>,
    /// Numero de l'instantane sur lequel la machine a demarre depuis le menu
    /// GRUB (mode temporaire, racine en memoire), ou `None` en temps normal.
    #[serde(default)]
    pub demarre_sur: Option<u32>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vlc() -> AppEntry {
        // Fiche telle que la produit la fusion Flathub + apt-cache.
        AppEntry {
            id: "org.videolan.VLC".into(),
            name: "VLC".into(),
            summary: String::new(),
            version: String::new(),
            sources: vec![SOURCE_FLATHUB.into(), SOURCE_DEB.into()],
            default_source: SOURCE_FLATHUB.into(),
            icon: String::new(),
            deb_name: Some("vlc".into()),
            installed_flathub: false,
            installed_deb: false,
        }
    }

    #[test]
    fn deb_source_uses_the_package_name_not_the_flatpak_id() {
        // Le bug corrige en 0.2: sans deb_name, "org.videolan.VLC" partait vers
        // apt-get et l'installation DEB echouait ou visait le mauvais paquet.
        let app = vlc();
        assert_eq!(app.id_for(SOURCE_DEB), "vlc");
        assert_eq!(app.id_for(SOURCE_FLATHUB), "org.videolan.VLC");
    }

    #[test]
    fn deb_source_falls_back_to_id_when_no_package_name_is_known() {
        let mut app = vlc();
        app.deb_name = None;
        assert_eq!(app.id_for(SOURCE_DEB), "org.videolan.VLC");
    }

    #[test]
    fn has_source_reflects_the_merge() {
        let app = vlc();
        assert!(app.has_source(SOURCE_DEB));
        assert!(app.has_source(SOURCE_FLATHUB));
        assert!(!app.has_source("inconnue"));
    }

    #[test]
    fn entry_survives_a_json_round_trip_without_deb_name() {
        // Les fiches serialisees par une version anterieure n'ont pas le champ.
        let json = r#"{"id":"vlc","name":"VLC","summary":"","version":"",
                       "sources":["auxinux-deb"],"default_source":"auxinux-deb","icon":""}"#;
        let app: AppEntry = serde_json::from_str(json).expect("deserialisation");
        assert_eq!(app.deb_name, None);
        assert_eq!(app.id_for(SOURCE_DEB), "vlc");
    }
}
