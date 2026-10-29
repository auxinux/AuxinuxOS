//! Assistant de premier demarrage: le choix des applications.
//!
//! Decision d'aporler (2026-10-02): l'image n'impose plus aucune application
//! d'usage. « Notre valeur de vie privee, de libre choix et de liberte, on ne
//! la respecte pas a 100 %: nous imposons plein de logiciels des le depart. »
//! L'installation est un socle -- systeme, KDE Plasma, couche Windows -- et cet
//! assistant demande, au premier demarrage, ce que la personne veut:
//! navigateur, lecteur multimedia, profil d'usage avec ses applications
//! suggerees, outils de vie privee. Il se relance a tout moment depuis le
//! centre de controle.
//!
//! La bureautique n'est plus une question (2026-10-04): AuxiOffice (AuxiNux
//! Office avant la 0.3.0) est inclus dans l'image. LibreOffice reste installable depuis la page
//! Applications.
//!
//! Flatpak d'abord (arbitrage du meme jour): versions recentes, isolees,
//! desinstallables sans toucher au systeme. Brave a longtemps ete l'exception,
//! en DEB depuis son depot; depuis le 2026-10-29 (decision d'aporler) il vient
//! lui aussi de Flathub, ou il est publie et verifie par Brave Software
//! (com.brave.Browser, x86_64 et aarch64). La politique de confidentialite
//! geree de /etc/brave/policies/managed s'applique toujours: le Flatpak lit
//! les politiques de l'hote (permission host-etc).
//!
//! Ce module ne depend pas de l'interface: le catalogue, le plan
//! d'installation et la regle du premier demarrage sont testes par
//! `cargo test --no-default-features`.

use crate::model::ActionResult;

/// Programme privilegie qui applique la selection (voir
/// helper/auxinux-assistant-apply).
pub const APPLY_HELPER: &str = "/usr/libexec/auxinux/auxinux-assistant-apply";

/// D'ou vient une application.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
    Flatpak,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct App {
    pub id: &'static str,
    pub name: &'static str,
    pub summary: &'static str,
    pub source: Source,
}

const fn flatpak(id: &'static str, name: &'static str, summary: &'static str) -> App {
    App { id, name, summary, source: Source::Flatpak }
}

/// Installee pour TOUT LE MONDE, quels que soient les choix: Bottles fait
/// tourner les applications Windows, chacune dans son espace, avec Proton-GE
/// et DXVK (decision d'aporler: « Wine et la couche Proton sont installes peu
/// importe »). Wine lui-meme est dans l'image (couche-windows.txt).
pub const TOUJOURS: [App; 1] = [flatpak(
    "com.usebottles.bottles",
    "Bottles",
    "Applications Windows, chacune dans son espace isolé (Proton, DXVK)",
)];

/// La couche Windows (Wine, Bottles, Proton, et donc les jeux Steam) n'existe
/// que sur x86_64. Sur l'Edition ARM (aarch64), Bottles n'est pas impose et le
/// profil Jeu n'est pas propose: ils meneraient a des programmes Windows qui
/// ne peuvent pas tourner.
pub fn couche_windows() -> bool {
    couche_windows_pour(std::env::consts::ARCH)
}

/// `couche_windows` pour une architecture donnee (`std::env::consts::ARCH`).
pub fn couche_windows_pour(arch: &str) -> bool {
    arch == "x86_64"
}

/// Applications installees quels que soient les choix, sur cette architecture.
pub fn toujours_pour(arch: &str) -> &'static [App] {
    if couche_windows_pour(arch) {
        &TOUJOURS
    } else {
        &[]
    }
}

pub const NAVIGATEURS: [App; 5] = [
    flatpak("org.mozilla.firefox", "Firefox", "Navigateur libre de la fondation Mozilla"),
    flatpak(
        "com.brave.Browser",
        "Brave",
        "Bloqueur de publicités intégré; télémétrie coupée par AuxiNux",
    ),
    flatpak(
        "io.gitlab.librewolf-community",
        "LibreWolf",
        "Firefox durci pour la vie privée",
    ),
    flatpak("org.chromium.Chromium", "Chromium", "Version libre du moteur de Chrome"),
    flatpak("com.vivaldi.Vivaldi", "Vivaldi", "Navigateur très personnalisable"),
];

/// VLC en tete: c'est le lecteur que le projet recommande.
pub const LECTEURS: [App; 3] = [
    flatpak("org.videolan.VLC", "VLC", "Lit à peu près tout (recommandé)"),
    flatpak("org.kde.haruna", "Haruna", "Lecteur vidéo de KDE"),
    flatpak("io.mpv.Mpv", "mpv", "Lecteur minimaliste"),
];

pub const VIE_PRIVEE: [App; 5] = [
    flatpak("org.keepassxc.KeePassXC", "KeePassXC", "Coffre-fort de mots de passe, hors ligne"),
    flatpak("org.kde.kleopatra", "Kleopatra", "Chiffrement et signature (OpenPGP)"),
    flatpak("org.onionshare.OnionShare", "OnionShare", "Partage de fichiers anonyme par Tor"),
    flatpak(
        "fr.romainvigier.MetadataCleaner",
        "Metadata Cleaner",
        "Retire les métadonnées des photos et documents",
    ),
    flatpak("org.bleachbit.BleachBit", "BleachBit", "Efface les traces et fichiers temporaires"),
];

/// Profil d'usage (les trois profils d'auxinux-profile).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Profil {
    Bureautique,
    Multimedia,
    Jeu,
}

impl Profil {
    pub const TOUS: [Profil; 3] = [Profil::Bureautique, Profil::Multimedia, Profil::Jeu];
    /// Sans couche Windows (Edition ARM): pas de profil Jeu dans l'assistant.
    const SANS_JEU: [Profil; 2] = [Profil::Bureautique, Profil::Multimedia];

    /// Profils proposes par l'assistant sur cette machine.
    pub fn proposes() -> &'static [Profil] {
        Self::proposes_pour(std::env::consts::ARCH)
    }

    /// `proposes` pour une architecture donnee.
    pub fn proposes_pour(arch: &str) -> &'static [Profil] {
        if couche_windows_pour(arch) {
            &Self::TOUS
        } else {
            &Self::SANS_JEU
        }
    }

    /// Nom compris par `auxinux-profile set`.
    pub fn id(self) -> &'static str {
        match self {
            Profil::Bureautique => "bureautique",
            Profil::Multimedia => "multimedia",
            Profil::Jeu => "gaming",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Profil::Bureautique => "Bureautique",
            Profil::Multimedia => "Multimédia",
            Profil::Jeu => "Jeu",
        }
    }

    /// Applications suggerees, et si elles sont cochees d'avance. Cochees:
    /// celles que l'image installait d'office pour cet usage avant le
    /// 2026-10-02. Les autres sont proposees, decochees.
    ///
    /// Steam est DECOCHE: il collecte pour son compte, et docs/privacy-stance.md
    /// engage le projet a ce que son installation soit un acte explicite --
    /// « jamais une case pre-cochee ».
    pub fn suggestions(self) -> &'static [(App, bool)] {
        // Thunderbird n'est plus propose: AuxiMail est dans l'image (regle
        // d'aporler, 2026-10-23: une application AuxiNux installee remplace
        // son equivalent).
        const BUREAUTIQUE: [(App, bool); 2] = [
            (flatpak("org.gnome.SimpleScan", "Numériseur", "Numériser des documents"), true),
            (flatpak("com.github.xournalpp.xournalpp", "Xournal++", "Annoter des PDF, prendre des notes"), false),
        ];
        const MULTIMEDIA: [(App, bool); 6] = [
            (flatpak("org.kde.elisa", "Elisa", "Lecteur de musique de KDE"), true),
            (flatpak("org.kde.kdenlive", "Kdenlive", "Montage vidéo"), true),
            (flatpak("org.audacityteam.Audacity", "Audacity", "Édition audio"), true),
            (flatpak("org.gimp.GIMP", "GIMP", "Retouche d'images"), true),
            (flatpak("org.kde.krita", "Krita", "Peinture et illustration"), false),
            (flatpak("com.obsproject.Studio", "OBS Studio", "Enregistrement et diffusion d'écran"), false),
        ];
        const JEU: [(App, bool); 4] = [
            (flatpak("com.valvesoftware.Steam", "Steam", "Jeux Steam, avec Proton pour les jeux Windows"), false),
            (flatpak("com.heroicgameslauncher.hgl", "Heroic", "Jeux Epic, GOG et Amazon"), true),
            (flatpak("net.lutris.Lutris", "Lutris", "Lanceur pour tous les autres jeux"), false),
            (flatpak("net.davidotek.pupgui2", "ProtonUp-Qt", "Versions supplémentaires de Proton"), false),
        ];
        match self {
            Profil::Bureautique => &BUREAUTIQUE,
            Profil::Multimedia => &MULTIMEDIA,
            Profil::Jeu => &JEU,
        }
    }
}

/// Ce que la personne a choisi dans l'assistant.
#[derive(Clone, Debug, PartialEq)]
pub struct Selection {
    /// Index dans NAVIGATEURS; `None` = aucun pour l'instant.
    pub navigateur: Option<usize>,
    /// Index dans LECTEURS; `None` = aucun.
    pub lecteur: Option<usize>,
    pub profil: Profil,
    /// Une case par suggestion du profil, dans l'ordre de `suggestions()`.
    pub suggestions: Vec<bool>,
    /// Une case par entree de VIE_PRIVEE.
    pub vie_privee: Vec<bool>,
}

impl Default for Selection {
    /// Les valeurs proposees d'avance. Firefox parce qu'il faut un navigateur
    /// et que c'est le choix le plus neutre; VLC parce que c'est le lecteur
    /// recommande; les outils de vie privee coches, comme convenu. Tout se
    /// decoche.
    fn default() -> Self {
        let profil = Profil::Bureautique;
        Selection {
            navigateur: Some(0),
            lecteur: Some(0),
            profil,
            suggestions: defaults_for(profil),
            vie_privee: vec![true; VIE_PRIVEE.len()],
        }
    }
}

impl Selection {
    /// Change de profil et repart de ses cases par defaut: les cases d'un
    /// autre profil n'ont pas de sens pour celui-ci.
    pub fn set_profil(&mut self, profil: Profil) {
        if self.profil != profil {
            self.profil = profil;
            self.suggestions = defaults_for(profil);
        }
    }

    /// Toutes les applications qui seront installees, dans l'ordre affiche
    /// par le recapitulatif.
    pub fn applications(&self) -> Vec<App> {
        self.applications_pour(std::env::consts::ARCH)
    }

    /// `applications` pour une architecture donnee: sans couche Windows,
    /// Bottles n'est pas ajoute d'office.
    pub fn applications_pour(&self, arch: &str) -> Vec<App> {
        let mut apps = Vec::new();
        if let Some(app) = self.navigateur.and_then(|i| NAVIGATEURS.get(i)) {
            apps.push(*app);
        }
        if let Some(app) = self.lecteur.and_then(|i| LECTEURS.get(i)) {
            apps.push(*app);
        }
        for ((app, _), chosen) in self.profil.suggestions().iter().zip(&self.suggestions) {
            if *chosen {
                apps.push(*app);
            }
        }
        for (app, chosen) in VIE_PRIVEE.iter().zip(&self.vie_privee) {
            if *chosen {
                apps.push(*app);
            }
        }
        apps.extend_from_slice(toujours_pour(arch));
        // Une meme application ne doit pas etre installee deux fois si deux
        // etapes la proposent un jour.
        let mut seen = std::collections::HashSet::new();
        apps.retain(|app| seen.insert(app.id));
        apps
    }

    /// Arguments de auxinux-assistant-apply.
    pub fn helper_args(&self) -> Vec<String> {
        let mut args = vec!["--profil".to_string(), self.profil.id().to_string()];
        args.extend(self.app_args());
        args
    }

    /// Les applications seules, sans le profil: l'installateur ecrit le
    /// profil lui-meme (`auxinux-profile set` reglerait le systeme EN COURS,
    /// c'est-a-dire le live).
    pub fn app_args(&self) -> Vec<String> {
        let mut args = Vec::new();
        for app in self.applications() {
            match app.source {
                Source::Flatpak => {
                    args.push("--flatpak".into());
                    args.push(app.id.into());
                }
            }
        }
        args
    }
}

impl App {
    /// Lanceur .desktop installe par cette application, et l'endroit ou il
    /// apparait une fois installee.
    pub fn desktop_file(&self) -> (String, std::path::PathBuf) {
        match self.source {
            Source::Flatpak => {
                let name = format!("{}.desktop", self.id);
                let path = std::path::Path::new("/var/lib/flatpak/exports/share/applications").join(&name);
                (name, path)
            }
        }
    }
}

fn defaults_for(profil: Profil) -> Vec<bool> {
    profil.suggestions().iter().map(|(_, on)| *on).collect()
}

/// Installe la selection: une seule invite d'autorisation, avancement transmis
/// ligne a ligne (voir progress.rs pour les lignes « auxinux-etape »).
pub fn apply(selection: &Selection, on_line: &mut dyn FnMut(&str)) -> ActionResult {
    let args = selection.helper_args();
    let mut full: Vec<&str> = vec![APPLY_HELPER];
    full.extend(args.iter().map(String::as_str));
    let result = crate::progress::privileged(&full, on_line, "Vos applications sont installées");
    // Le navigateur choisi devient celui du bureau (liens ouverts depuis les
    // applications, lanceur « navigateur » de la barre des taches). L'image
    // n'en declare plus aucun. Seulement s'il est REELLEMENT installe: une
    // autre application a pu echouer sans lui, et lui sans elles.
    if let Some(browser) = selection.navigateur.and_then(|i| NAVIGATEURS.get(i)) {
        let (desktop, path) = browser.desktop_file();
        if path.exists() {
            let out = crate::util::run("xdg-settings", &["set", "default-web-browser", &desktop]);
            on_line(&if out.ok {
                format!("Navigateur par défaut: {}", browser.name)
            } else {
                format!("Impossible de déclarer {} comme navigateur par défaut: {}", browser.name, out.stderr.trim())
            });
        }
    }
    if result.ok {
        let _ = mark_done();
    }
    result
}

/// Ce que l'installation de l'assistant a reellement donne, pour sa page
/// finale.
#[derive(Clone, Debug, PartialEq)]
pub struct Bilan {
    pub ok: bool,
    pub installees: Vec<&'static str>,
    pub echecs: Vec<&'static str>,
    /// Le changement de profil d'usage a echoue (« Echec pour: profil ... »).
    pub profil_echoue: bool,
    /// Message du resultat: l'explication de l'echec, s'il y en a un.
    pub message: String,
}

/// Bilan d'une installation terminee. En cas d'echec, chaque application est
/// jugee sur pieces (`installed`: son lanceur est-il la ?) plutot que sur le
/// texte d'erreur: le programme d'installation continue apres un echec, donc
/// une partie de la selection peut tres bien etre installee.
pub fn bilan(selection: &Selection, result: &ActionResult, installed: impl Fn(&App) -> bool) -> Bilan {
    let apps = selection.applications();
    let (installees, echecs): (Vec<&App>, Vec<&App>) = if result.ok {
        (apps.iter().collect(), Vec::new())
    } else {
        apps.iter().partition(|app| installed(app))
    };
    let profil_echoue = !result.ok
        && result
            .message
            .lines()
            .any(|l| l.trim_start().starts_with("Échec pour:") && l.contains("profil "));
    Bilan {
        ok: result.ok,
        installees: installees.iter().map(|a| a.name).collect(),
        echecs: echecs.iter().map(|a| a.name).collect(),
        profil_echoue,
        message: result.message.clone(),
    }
}

// ---------------------------------------------------------------------------
// Premier demarrage
// ---------------------------------------------------------------------------

/// Fichier qui dit que l'assistant a ete termine ou passe pour ce compte.
pub fn done_marker() -> Option<std::path::PathBuf> {
    let config = match std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty()) {
        Some(dir) => std::path::PathBuf::from(dir),
        None => std::path::PathBuf::from(std::env::var_os("HOME")?).join(".config"),
    };
    Some(config.join("auxinux").join("assistant-termine"))
}

/// Marque l'assistant comme termine. Appele quand l'installation reussit, ou
/// quand la personne choisit « Passer »: dans les deux cas elle ne doit plus le
/// voir s'ouvrir a chaque session. Il reste dans le centre de controle.
pub fn mark_done() -> std::io::Result<()> {
    let path = done_marker().ok_or_else(|| std::io::Error::other("HOME inconnu"))?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, b"")
}

/// Faut-il ouvrir l'assistant a l'ouverture de session ?
///
/// Non dans la session live: on y essaie le systeme, et tout ce qui serait
/// installe disparaitrait au redemarrage. Non plus une fois termine ou passe.
pub fn should_open_at_login(cmdline: &str, marker_exists: bool) -> bool {
    let live = cmdline.split_whitespace().any(|w| w == "boot=live");
    !live && !marker_exists
}

/// `should_open_at_login` sur l'etat reel de la machine.
pub fn open_at_login_now() -> bool {
    let cmdline = std::fs::read_to_string("/proc/cmdline").unwrap_or_default();
    let marker = done_marker().map(|p| p.exists()).unwrap_or(false);
    should_open_at_login(&cmdline, marker)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Catalogue de l'edition x86_64 (avec couche Windows), quelle que soit
    /// l'architecture qui execute les tests.
    fn ids(sel: &Selection) -> Vec<&'static str> {
        sel.applications_pour("x86_64").iter().map(|a| a.id).collect()
    }

    #[test]
    fn defaults_install_a_browser_vlc_privacy_tools_and_bottles() {
        let sel = Selection::default();
        let ids = ids(&sel);
        for expected in [
            "org.mozilla.firefox",
            "org.videolan.VLC",
            "org.keepassxc.KeePassXC",
            "com.usebottles.bottles",
        ] {
            assert!(ids.contains(&expected), "{expected} manque: {ids:?}");
        }
        // Proposee mais decochee.
        assert!(!ids.contains(&"com.github.xournalpp.xournalpp"));
        // AuxiOffice et AuxiMail sont dans l'image: ni suite bureautique ni
        // courrielleur a installer.
        assert!(!ids.contains(&"org.libreoffice.LibreOffice"));
        assert!(!ids.contains(&"org.mozilla.Thunderbird"));
    }

    #[test]
    fn arm_has_no_windows_layer_and_no_gaming_profile() {
        // Edition ARM (aarch64): ni Bottles impose, ni profil Jeu propose.
        let mut sel = Selection::default();
        sel.navigateur = None;
        sel.lecteur = None;
        sel.suggestions = vec![false; sel.suggestions.len()];
        sel.vie_privee = vec![false; VIE_PRIVEE.len()];
        assert!(sel.applications_pour("aarch64").is_empty());
        assert_eq!(ids(&sel), vec!["com.usebottles.bottles"]);
        assert!(!couche_windows_pour("aarch64"));
        assert!(couche_windows_pour("x86_64"));
        assert_eq!(Profil::proposes_pour("aarch64"), &[Profil::Bureautique, Profil::Multimedia]);
        assert!(!Profil::proposes_pour("aarch64").contains(&Profil::Jeu));
        assert_eq!(Profil::proposes_pour("x86_64"), &Profil::TOUS);
    }

    #[test]
    fn bottles_is_installed_even_when_everything_is_declined() {
        let sel = Selection {
            navigateur: None,
            lecteur: None,
            profil: Profil::Bureautique,
            suggestions: vec![false; 3],
            vie_privee: vec![false; VIE_PRIVEE.len()],
        };
        assert_eq!(ids(&sel), vec!["com.usebottles.bottles"]);
    }

    #[test]
    fn brave_comes_from_flathub_not_its_deb_repository() {
        let mut sel = Selection::default();
        sel.navigateur = NAVIGATEURS.iter().position(|a| a.name == "Brave");
        let args = sel.helper_args();
        let i = args.iter().position(|a| a == "com.brave.Browser").expect("Brave absent");
        assert_eq!(args[i - 1], "--flatpak");
        assert!(!args.iter().any(|a| a == "--brave" || a == "brave-browser"));
        assert!(!args.iter().any(|a| a == "org.mozilla.firefox"));
    }

    #[test]
    fn changing_profile_resets_its_suggestions_and_sets_it() {
        let mut sel = Selection::default();
        sel.set_profil(Profil::Jeu);
        // Steam decoche d'avance (docs/privacy-stance.md), Heroic coche.
        assert_eq!(sel.suggestions, vec![false, true, false, false]);
        let args = sel.helper_args();
        assert_eq!(&args[..2], &["--profil".to_string(), "gaming".to_string()]);
        assert!(!args.contains(&"com.valvesoftware.Steam".to_string()));
        sel.suggestions[0] = true;
        assert!(sel.helper_args().contains(&"com.valvesoftware.Steam".to_string()));
        assert!(!args.contains(&"org.mozilla.Thunderbird".to_string()));
    }

    #[test]
    fn every_flatpak_argument_follows_its_flag() {
        let args = Selection::default().helper_args();
        for (i, a) in args.iter().enumerate() {
            if a.contains('.') {
                assert_eq!(args[i - 1], "--flatpak", "{a} sans --flatpak");
            }
        }
    }

    #[test]
    fn catalog_ids_pass_the_helper_validation() {
        // Meme regle que valid_id() dans auxinux-assistant-apply: un
        // identifiant refuse ici ferait echouer toute l'installation.
        let valid = |id: &str| {
            let mut c = id.chars();
            c.next().is_some_and(|f| f.is_ascii_alphanumeric())
                && id.len() <= 255
                && id.chars().all(|ch| ch.is_ascii_alphanumeric() || ".+_:-".contains(ch))
        };
        let mut all: Vec<App> = NAVIGATEURS.to_vec();
        all.extend(LECTEURS);
        all.extend(VIE_PRIVEE);
        all.extend(TOUJOURS);
        for p in Profil::TOUS {
            all.extend(p.suggestions().iter().map(|(a, _)| *a));
        }
        for app in all {
            assert!(valid(app.id), "identifiant refuse par l'assistant: {}", app.id);
        }
    }

    #[test]
    fn browser_launchers_are_where_flatpak_puts_them() {
        let (name, path) = NAVIGATEURS[0].desktop_file();
        assert_eq!(name, "org.mozilla.firefox.desktop");
        assert!(path.starts_with("/var/lib/flatpak/exports/share/applications"));
        let brave = NAVIGATEURS.iter().find(|a| a.name == "Brave").unwrap();
        assert_eq!(brave.desktop_file().0, "com.brave.Browser.desktop");
    }

    #[test]
    fn never_opens_in_the_live_session_nor_once_done() {
        let installed = "BOOT_IMAGE=/@/boot/vmlinuz root=UUID=x rootflags=subvol=@ rw";
        let live = "BOOT_IMAGE=/live/vmlinuz boot=live components quiet";
        assert!(should_open_at_login(installed, false));
        assert!(!should_open_at_login(installed, true));
        assert!(!should_open_at_login(live, false));
    }

    #[test]
    fn bilan_reussi_liste_toute_la_selection() {
        let sel = Selection::default();
        let b = bilan(&sel, &ActionResult::ok("ok"), |_| false);
        assert!(b.ok);
        assert!(b.echecs.is_empty());
        assert_eq!(b.installees.len(), sel.applications().len());
        assert_eq!(b.installees.contains(&"Bottles"), couche_windows());
    }

    #[test]
    fn bilan_echec_partiel_juge_chaque_application() {
        let sel = Selection::default();
        // Firefox et non Bottles: le cas doit valoir aussi sur l'Edition ARM,
        // ou Bottles n'est pas dans la selection.
        let result = ActionResult::err("flatpak: erreur réseau\nÉchec pour: org.mozilla.firefox");
        let b = bilan(&sel, &result, |app| app.name != "Firefox");
        assert!(!b.ok);
        assert_eq!(b.echecs, vec!["Firefox"]);
        assert!(!b.installees.contains(&"Firefox"));
        assert!(!b.profil_echoue);
    }

    #[test]
    fn bilan_repere_l_echec_du_profil() {
        let result = ActionResult::err("Échec pour: profil gaming");
        let b = bilan(&Selection::default(), &result, |_| true);
        assert!(b.profil_echoue);
        assert!(b.echecs.is_empty());
    }
}
