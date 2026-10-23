//! Interface libcosmic du centre de controle.
//!
//! Pourquoi libcosmic alors que le bureau est KDE Plasma depuis la 0.2.0:
//! l'interface existe, elle fonctionne sous n'importe quel compositeur Wayland
//! (libcosmic est iced + winit + wgpu, pas COSMIC), et la reecrire en Kirigami
//! est un chantier a part -- 1 500 lignes d'interface contre trois lignes a
//! changer ici. Le prix a payer est visuel: l'application ne suit pas le theme
//! Breeze. Le backend etant separe par la feature `gui`, une interface
//! Kirigami/QML pourra s'y brancher sans toucher a la logique.
//! Kirigami affichait une fenetre Qt/KDE au milieu d'un bureau en Iced --
//! theme, coins, boutons et police differents -- et imposait toute la pile KF6
//! dans l'ISO. libcosmic est le toolkit natif du bureau: l'application herite
//! du theme (clair/sombre, accent), se reduit a un binaire, et demarre sans
//! charger de moteur QML.
//!
//! Dans la session AuxiNux Shell, le Center prend l'apparence du shell
//! (couleurs, accent, police, barre de titre de labwc): voir crate::apparence.
//!
//! Organisation: un `nav_bar` a gauche, une page par section. Chaque page vit
//! dans son propre module et n'expose qu'une fonction `view`.

mod apparence;
mod apps_page;
mod assistant_page;
mod health_page;
mod kernel_view;
mod operation;
mod recovery_page;
mod settings_page;
mod sources_page;
mod updates_page;

use cosmic::app::{Core, Settings, Task};
use cosmic::widget::nav_bar;
use cosmic::{executor, iced, Application, ApplicationExt, Element};

use crate::model::{
    ActionResult, AppEntry, AptSource, FlatpakRemote, HealthReport, RecoveryState, SourcePreset,
    SystemReport, SOURCE_DEB, SOURCE_FLATHUB,
};
use crate::task::{background, staged};

pub const APP_ID: &str = "ca.auxinux.Center";

/// Sources de la liste deroulante de la page Applications, dans l'ordre
/// affiche (libelles: apps_page::SOURCE_LABELS).
pub const APPS_SOURCES: [&str; 2] = [SOURCE_FLATHUB, SOURCE_DEB];

/// Ce que la fenetre affiche a l'ouverture.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Ouverture {
    /// Page Applications, suggestions.
    Accueil,
    /// Assistant de premier demarrage (`--premier-demarrage`, `--assistant`).
    Assistant,
    /// Page Applications sur une recherche (`--rechercher TERME`): l'assistant
    /// d'ouverture des .exe y envoie quand on cherche une alternative Linux.
    Recherche(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Page {
    Apps,
    Updates,
    Health,
    Recovery,
    Sources,
    Settings,
    Assistant,
}

/// Contenu actuellement affiche dans la page Applications.
///
/// Sans cette memoire, la page ne pouvait pas etre rechargee apres une
/// installation: la liste restait telle quelle, l'application installee
/// s'affichait toujours comme absente, et l'utilisateur relancait l'operation.
#[derive(Clone, Debug, PartialEq)]
pub enum AppsView {
    Featured,
    Installed,
    Search(String),
    /// Noyaux AuxiNux (voir kernel_view.rs).
    Kernel,
}

/// Etat de chargement d'une section. Distinguer « en cours » de « vide »
/// evite d'afficher « aucun resultat » pendant qu'une recherche tourne encore,
/// message qui faisait croire a un echec.
#[derive(Clone, Debug, PartialEq)]
pub enum Loading<T> {
    Idle,
    Busy,
    Ready(T),
}

impl<T> Loading<T> {
    pub fn ready(&self) -> Option<&T> {
        match self {
            Loading::Ready(v) => Some(v),
            _ => None,
        }
    }
}

#[derive(Clone, Debug)]
pub enum Message {
    // Navigation
    Page(Page),
    /// Verifier si le shell a change de theme (session AuxiNux).
    Apparence,

    // Applications
    SearchInput(String),
    SearchSubmit,
    /// Etape en cours d'un chargement de la page (numero de chargement,
    /// libelle). Le numero ecarte les nouvelles d'une recherche depassee.
    AppsStage(u64, String),
    AppsLoaded(u64, Vec<AppEntry>),
    ShowInstalled,
    ShowFeatured,
    /// Source affichee par la page Applications (index dans APPS_SOURCES).
    AppsSource(usize),
    Install(usize),
    Remove(usize),

    // Noyaux (vue Noyau de la page Applications)
    ShowKernel,
    KernelLoaded(Result<crate::kernel::KernelState, String>),
    KernelInstall(String),
    KernelUpdate,
    /// Version, ou "latest" pour revenir au plus recent.
    KernelActivate(String),
    /// Noyau dont la desinstallation attend confirmation.
    KernelConfirmRemove(Option<String>),
    KernelRemove(String),
    KernelDevSource(bool),

    // Mises a jour
    RefreshUpdates,
    RefreshIndexes,
    UpdatesStage(u64, String),
    UpdatesLoaded(u64, Vec<AppEntry>),
    /// Nouvelle version d'AuxiNux OS disponible (paquet auxinuxos-release).
    OsUpdateLoaded(Option<crate::updates::OsUpdate>),
    UpgradeAll,
    /// Nouvelle version d'AuxiNux OS (`auxi os upgrade`, avec instantane).
    UpgradeOs,
    UpdateOne(usize),

    // Sante
    RefreshHealth,
    HealthLoaded(HealthReport),
    SystemLoaded(SystemReport),

    // Restauration
    RefreshRecovery,
    RecoveryLoaded(RecoveryState),
    SnapshotDescription(String),
    CreateSnapshot,
    ConfirmRollback(Option<u32>),
    ToggleAllSnapshots,
    Rollback(u32),

    // Sources
    RefreshSources,
    SourcesLoaded(Vec<AptSource>, Vec<SourcePreset>, Vec<FlatpakRemote>),
    ToggleAptSource(String, bool),
    RemoveAptSource(String),
    AddPreset(String),
    ToggleRemote(String, bool),
    CustomName(String),
    CustomBody(String),
    CustomKeyUrl(String),
    AddCustomSource,

    // Reglages
    ToggleAptPolicy(bool),
    ToggleDebApps(bool),
    SetProfile(String),
    SetDesktopSession(String),
    InstallPlasma,
    RemovePlasma,
    OpenSystemSettings,
    OpenUrl(String),

    // Assistant de premier demarrage
    AssistantRestart,
    AssistantNext,
    AssistantBack,
    AssistantSkip,
    AssistantBrowser(Option<usize>),
    AssistantPlayer(Option<usize>),
    AssistantProfil(crate::assistant::Profil),
    AssistantSuggestion(usize, bool),
    AssistantPrivacy(usize, bool),
    AssistantInstall,
    AssistantFinish,

    // Operation longue suivie en direct (voir operation.rs)
    OpLine(String),
    OpFinished(ActionResult),
    ToggleLog,
    CopyLog,
    DismissOperation,

    // Transverse
    Done(ActionResult),
    DismissToast,
    TaskPanicked,
}

pub struct App {
    core: Core,
    nav: nav_bar::Model,
    page: Page,

    // Applications
    query: String,
    apps: Loading<Vec<AppEntry>>,
    apps_view: AppsView,
    /// Etape du chargement en cours, affichee sous la barre d'attente.
    apps_stage: String,
    /// Numero du dernier chargement lance: une recherche relancee avant la fin
    /// de la precedente ne doit pas etre ecrasee par son resultat.
    apps_generation: u64,
    /// Source choisie dans la liste deroulante (Flathub ou DEB). Sans
    /// effet tant que l'installation DEB n'est pas activee.
    apps_source: String,

    // Noyaux
    kernel: Loading<Result<crate::kernel::KernelState, String>>,
    pending_kernel_remove: Option<String>,

    // Mises a jour
    updates: Loading<Vec<AppEntry>>,
    updates_stage: String,
    updates_generation: u64,
    os_version: String,
    /// Nouvelle version d'AuxiNux OS, annoncee en tete de la page Mises a jour.
    os_update: Option<crate::updates::OsUpdate>,

    // Sante
    health: Loading<HealthReport>,
    system: Loading<SystemReport>,

    // Restauration
    recovery: Loading<RecoveryState>,
    snapshot_description: String,
    /// Instantane dont la restauration attend confirmation.
    pending_rollback: Option<u32>,
    /// Montrer tous les points, et non les plus recents seulement.
    recovery_show_all: bool,

    // Sources
    apt_sources: Loading<Vec<AptSource>>,
    presets: Vec<SourcePreset>,
    remotes: Vec<FlatpakRemote>,
    /// Formulaire de depot personnalise (nom, corps deb822, URL de cle).
    custom_name: String,
    custom_body: String,
    custom_key_url: String,

    // Reglages
    apt_direct: bool,
    /// Installation d'applications DEB activee (`auxi set deb=true`).
    deb_apps: bool,
    profile: crate::profile::ProfileState,
    /// Bureau ouvert a la connexion (AuxiNux Shell ou KDE Plasma).
    desktop: crate::session::DesktopState,

    // Assistant de premier demarrage
    assistant_step: usize,
    selection: crate::assistant::Selection,
    /// Vrai entre le clic sur « Installer » et la fin de l'installation.
    assistant_installing: bool,
    /// Bilan de la derniere installation de l'assistant: s'il existe, la page
    /// finale remplace le recapitulatif.
    assistant_bilan: Option<crate::assistant::Bilan>,

    /// Operation longue (installation, mise a jour) en cours ou terminee, avec
    /// sa progression et son journal.
    operation: Option<operation::Operation>,

    /// Derniere operation terminee, affichee en bandeau.
    toast: Option<ActionResult>,
    /// Nombre d'operations longues en cours, pour l'indicateur global.
    busy: usize,
    /// Session AuxiNux: empreinte des kdeglobals lus, pour suivre un
    /// changement de theme du shell (None hors de cette session).
    apparence: Option<Vec<Option<std::time::SystemTime>>>,
    /// Police du shell, reposee a chaque affichage (voir view()).
    police: Option<String>,
}

impl App {
    /// Source affichee par la page Applications: Flathub, sauf si
    /// l'installation DEB est activee ET choisie dans la liste deroulante.
    pub fn apps_source(&self) -> &str {
        if self.deb_apps && self.apps_source == SOURCE_DEB {
            SOURCE_DEB
        } else {
            SOURCE_FLATHUB
        }
    }

    /// Source visee par une fiche: celle de la page. La page n'affiche que les
    /// fiches qui l'ont; le repli ne sert qu'a ne jamais viser une source
    /// absente de la fiche.
    pub fn source_for(&self, app: &AppEntry) -> String {
        let source = self.apps_source();
        if app.has_source(source) {
            source.to_string()
        } else {
            app.default_source.clone()
        }
    }

    fn start(&mut self) {
        self.busy += 1;
    }

    /// Vrai pendant une installation ou une mise a jour: les boutons qui en
    /// lanceraient une seconde sont alors inactifs.
    pub fn op_running(&self) -> bool {
        self.operation.as_ref().is_some_and(|op| op.running())
    }

    /// Lance une operation longue suivie en direct. Refusee si une autre tourne
    /// deja: les deux se disputeraient le verrou de dpkg.
    fn launch<F>(&mut self, title: String, work: F) -> Task<Message>
    where
        F: FnOnce(&mut dyn FnMut(&str)) -> ActionResult + Send + 'static,
    {
        if self.op_running() {
            return Task::none();
        }
        self.toast = None;
        self.operation = Some(operation::Operation::new(title));
        crate::task::streamed(work)
    }

    fn finish(&mut self) {
        self.busy = self.busy.saturating_sub(1);
    }

    fn load_apps_featured(&mut self) -> Task<Message> {
        self.apps_view = AppsView::Featured;
        self.reload_apps()
    }

    /// Recharge la page Applications dans la vue courante.
    fn reload_apps(&mut self) -> Task<Message> {
        if self.apps_view == AppsView::Kernel {
            return self.load_kernel();
        }
        self.apps = Loading::Busy;
        self.apps_stage.clear();
        self.apps_generation += 1;
        let generation = self.apps_generation;
        self.start();
        let stage = move |label| Message::AppsStage(generation, label);
        let done = move |list| Message::AppsLoaded(generation, list);
        match self.apps_view.clone() {
            AppsView::Featured => staged(crate::apps::featured_with, stage, done),
            AppsView::Installed => staged(crate::apps::list_installed_with, stage, done),
            AppsView::Search(q) => {
                staged(move |on_stage| crate::apps::search_with(&q, on_stage), stage, done)
            }
            AppsView::Kernel => unreachable!("traite plus haut"),
        }
    }

    fn load_kernel(&mut self) -> Task<Message> {
        self.kernel = Loading::Busy;
        self.pending_kernel_remove = None;
        self.start();
        background(crate::kernel::load, Message::KernelLoaded)
    }

    fn load_updates(&mut self) -> Task<Message> {
        self.updates = Loading::Busy;
        self.updates_stage.clear();
        self.updates_generation += 1;
        let generation = self.updates_generation;
        self.start();
        // Second chargement en parallele: la version d'AuxiNux OS disponible.
        self.start();
        let os_update = background(crate::updates::os_update_available, Message::OsUpdateLoaded);
        let list = staged(
            crate::apps::list_updates_with,
            move |label| Message::UpdatesStage(generation, label),
            move |list| Message::UpdatesLoaded(generation, list),
        );
        Task::batch(vec![list, os_update])
    }

    fn load_health(&mut self) -> Task<Message> {
        self.health = Loading::Busy;
        self.start();
        background(crate::health::report, Message::HealthLoaded)
    }

    fn load_recovery(&mut self) -> Task<Message> {
        self.recovery = Loading::Busy;
        self.start();
        background(crate::recovery::state, Message::RecoveryLoaded)
    }

    fn load_sources(&mut self) -> Task<Message> {
        self.apt_sources = Loading::Busy;
        self.start();
        background(
            || {
                (
                    crate::sources::list_apt_sources(),
                    crate::sources::list_source_presets(),
                    crate::sources::list_flatpak_remotes(),
                )
            },
            |(s, p, r)| Message::SourcesLoaded(s, p, r),
        )
    }

    /// Apres une action qui modifie l'etat systeme, on recharge la page
    /// concernee: laisser une liste perimee a l'ecran apres une installation
    /// est la premiere source de confusion signalee sur ce genre d'outil.
    fn reload_current_page(&mut self) -> Task<Message> {
        match self.page {
            Page::Apps => self.reload_apps(),
            Page::Updates => self.load_updates(),
            Page::Health => self.load_health(),
            Page::Recovery => self.load_recovery(),
            Page::Sources => self.load_sources(),
            Page::Settings | Page::Assistant => Task::none(),
        }
    }
}

impl Application for App {
    type Executor = executor::Default;
    /// Ce que la fenetre affiche a l'ouverture (voir `Ouverture`).
    type Flags = Ouverture;
    type Message = Message;

    const APP_ID: &'static str = APP_ID;

    fn core(&self) -> &Core {
        &self.core
    }

    fn core_mut(&mut self) -> &mut Core {
        &mut self.core
    }

    fn init(mut core: Core, ouverture: Self::Flags) -> (Self, Task<Self::Message>) {
        let apparence_lue = crate::apparence::lire();
        let apparence_suivie = apparence_lue.is_some();
        if apparence_suivie {
            // labwc dessine la barre de titre et ses boutons: l'en-tete de
            // libcosmic ne serait plus qu'une bande vide sous celle-ci.
            core.window.show_headerbar = false;
            core.window.sharp_corners = true;
        }
        let mut nav = nav_bar::Model::default();
        for (title, icon, page) in [
            // Le second nom de chaque ligne est celui que porte Breeze, qui
            // n'a pas toutes les variantes « -symbolic » d'Adwaita. Il doit
            // s'agir d'une icone MONOCHROME: une icone en couleur est teintee
            // d'un bloc et s'affiche en carre plein (« applications-all »,
            // constate en VM).
            ("Applications", ["system-software-install-symbolic", "view-app-grid-symbolic"], Page::Apps),
            ("Mises à jour", ["software-update-available-symbolic", "update-none"], Page::Updates),
            ("Santé du système", ["utilities-system-monitor-symbolic", "speedometer"], Page::Health),
            ("Restauration", ["document-revert-symbolic", "edit-undo"], Page::Recovery),
            ("Sources", ["application-x-addon-symbolic", "repository"], Page::Sources),
            ("Réglages", ["preferences-system-symbolic", "configure"], Page::Settings),
            ("Assistant", ["tools-wizard-symbolic", "tools-wizard"], Page::Assistant),
        ] {
            nav.insert()
                .text(title)
                .icon(self::icon(icon[0], &icon[1..]))
                .data::<Page>(page);
        }
        nav.activate_position(0);

        let mut app = App {
            core,
            nav,
            page: Page::Apps,
            query: String::new(),
            apps: Loading::Idle,
            apps_view: AppsView::Featured,
            apps_stage: String::new(),
            apps_generation: 0,
            apps_source: SOURCE_FLATHUB.to_string(),
            kernel: Loading::Idle,
            pending_kernel_remove: None,
            updates: Loading::Idle,
            updates_stage: String::new(),
            updates_generation: 0,
            os_version: crate::updates::os_version(),
            os_update: None,
            health: Loading::Idle,
            system: Loading::Idle,
            recovery: Loading::Idle,
            snapshot_description: String::new(),
            pending_rollback: None,
            recovery_show_all: false,
            apt_sources: Loading::Idle,
            presets: Vec::new(),
            remotes: Vec::new(),
            custom_name: String::new(),
            custom_body: String::new(),
            custom_key_url: String::new(),
            apt_direct: crate::sources::apt_wrapper_enabled(),
            deb_apps: crate::sources::deb_apps_enabled(),
            profile: crate::profile::state(),
            desktop: crate::session::state(),
            assistant_step: 0,
            selection: crate::assistant::Selection::default(),
            assistant_installing: false,
            assistant_bilan: None,
            operation: None,
            toast: None,
            busy: 0,
            apparence: apparence_suivie
                .then(|| crate::apparence::empreinte(&crate::apparence::fichiers())),
            police: apparence_lue.and_then(|a| a.police),
        };

        let task = match ouverture {
            Ouverture::Assistant => {
                app.page = Page::Assistant;
                app.nav.activate_position(6);
                Task::none()
            }
            Ouverture::Recherche(terme) => {
                app.query = terme;
                app.update(Message::SearchSubmit)
            }
            Ouverture::Accueil => app.load_apps_featured(),
        };
        let title = app.set_window_title(format!("Centre de contrôle — {}", app.os_version));
        (app, Task::batch(vec![task, title]))
    }

    fn nav_model(&self) -> Option<&nav_bar::Model> {
        Some(&self.nav)
    }

    fn on_nav_select(&mut self, id: nav_bar::Id) -> Task<Self::Message> {
        self.nav.activate(id);
        let page = self.nav.data::<Page>(id).copied().unwrap_or(Page::Apps);
        self.update(Message::Page(page))
    }

    fn update(&mut self, message: Message) -> Task<Self::Message> {
        match message {
            Message::Apparence => {
                let fichiers = crate::apparence::fichiers();
                let empreinte = crate::apparence::empreinte(&fichiers);
                if self.apparence.as_ref() == Some(&empreinte) {
                    return Task::none();
                }
                self.apparence = Some(empreinte);
                if let Some(a) = crate::apparence::lire() {
                    self.police = a.police.clone();
                    apparence::retenir_carte(&a);
                    return cosmic::command::set_theme(apparence::theme(&a));
                }
                Task::none()
            }
            Message::Page(page) => {
                self.page = page;
                self.toast = None;
                // Chargement paresseux: une section n'est interrogee qu'a sa
                // premiere ouverture. Tout charger au demarrage rendrait le
                // lancement aussi lent que l'operation la plus lente.
                match page {
                    Page::Apps if self.apps_view == AppsView::Kernel
                        && matches!(self.kernel, Loading::Idle) =>
                    {
                        self.load_kernel()
                    }
                    Page::Apps if matches!(self.apps, Loading::Idle) => self.load_apps_featured(),
                    Page::Updates if matches!(self.updates, Loading::Idle) => self.load_updates(),
                    Page::Health if matches!(self.health, Loading::Idle) => {
                        self.system = Loading::Busy;
                        self.start();
                        Task::batch(vec![
                            self.load_health(),
                            background(|| crate::system::info(true), Message::SystemLoaded),
                        ])
                    }
                    Page::Recovery if matches!(self.recovery, Loading::Idle) => {
                        self.load_recovery()
                    }
                    Page::Sources if matches!(self.apt_sources, Loading::Idle) => {
                        self.load_sources()
                    }
                    _ => Task::none(),
                }
            }

            // --- Applications ---
            Message::SearchInput(q) => {
                self.query = q;
                Task::none()
            }
            Message::SearchSubmit => {
                let q = self.query.trim().to_string();
                if q.len() < 2 {
                    return self.load_apps_featured();
                }
                self.apps_view = AppsView::Search(q);
                self.reload_apps()
            }
            Message::ShowFeatured => {
                self.query.clear();
                self.load_apps_featured()
            }
            Message::ShowInstalled => {
                self.query.clear();
                self.apps_view = AppsView::Installed;
                self.reload_apps()
            }
            Message::AppsStage(generation, label) => {
                if generation == self.apps_generation {
                    self.apps_stage = label;
                }
                Task::none()
            }
            Message::AppsLoaded(generation, list) => {
                self.finish();
                if generation == self.apps_generation {
                    self.apps = Loading::Ready(list);
                }
                Task::none()
            }
            Message::AppsSource(index) => {
                if let Some(source) = APPS_SOURCES.get(index) {
                    self.apps_source = source.to_string();
                }
                Task::none()
            }
            Message::Install(index) => match self.apps.ready().and_then(|l| l.get(index)) {
                Some(app) => {
                    let source = self.source_for(app);
                    // id_for: c'est ici que le nom de paquet DEB remplace
                    // l'app-id Flatpak. Passer `app.id` installerait le mauvais
                    // paquet.
                    let id = app.id_for(&source).to_string();
                    let title = format!("Installation de {}", app.name);
                    self.launch(title, move |on_line| {
                        crate::apps::install(&id, &source, on_line)
                    })
                }
                None => Task::none(),
            },
            Message::Remove(index) => match self.apps.ready().and_then(|l| l.get(index)) {
                Some(app) => {
                    let source = self.source_for(app);
                    let id = app.id_for(&source).to_string();
                    let title = format!("Désinstallation de {}", app.name);
                    self.launch(title, move |on_line| {
                        crate::apps::remove(&id, &source, on_line)
                    })
                }
                None => Task::none(),
            },

            // --- Noyaux ---
            Message::ShowKernel => {
                self.query.clear();
                self.apps_view = AppsView::Kernel;
                self.reload_apps()
            }
            Message::KernelLoaded(state) => {
                self.finish();
                self.kernel = Loading::Ready(state);
                Task::none()
            }
            Message::KernelInstall(version) => {
                self.launch(format!("Installation du noyau {version}"), move |on_line| {
                    crate::kernel::install(&version, on_line)
                })
            }
            Message::KernelUpdate => {
                self.launch("Mise à jour des noyaux".into(), crate::kernel::update)
            }
            Message::KernelActivate(version) => {
                let title = if version == "latest" {
                    "Retour au noyau le plus récent".to_string()
                } else {
                    format!("Activation du noyau {version}")
                };
                self.launch(title, move |on_line| crate::kernel::activate(&version, on_line))
            }
            Message::KernelConfirmRemove(version) => {
                // Comme une restauration: jamais d'un seul clic.
                self.pending_kernel_remove = version;
                Task::none()
            }
            Message::KernelRemove(version) => {
                self.pending_kernel_remove = None;
                self.launch(format!("Désinstallation du noyau {version}"), move |on_line| {
                    crate::kernel::remove(&version, on_line)
                })
            }
            Message::KernelDevSource(enabled) => self.launch(
                if enabled {
                    "Activation des noyaux en essai".into()
                } else {
                    "Désactivation des noyaux en essai".into()
                },
                move |on_line| crate::kernel::set_dev_source(enabled, on_line),
            ),

            // --- Mises a jour ---
            Message::RefreshUpdates => self.load_updates(),
            Message::RefreshIndexes => {
                // Rafraichir les index AVANT de lister les mises a jour: sans
                // cela, l'utilisateur qui vient d'activer un depot ne voit rien
                // de nouveau et croit le depot cassé.
                self.launch(
                    "Actualisation des listes de paquets".into(),
                    crate::updates::refresh_indexes,
                )
            }
            Message::UpdatesStage(generation, label) => {
                if generation == self.updates_generation {
                    self.updates_stage = label;
                }
                Task::none()
            }
            Message::OsUpdateLoaded(update) => {
                self.finish();
                self.os_update = update;
                Task::none()
            }
            Message::UpdatesLoaded(generation, list) => {
                self.finish();
                if generation == self.updates_generation {
                    self.updates = Loading::Ready(list);
                }
                Task::none()
            }
            Message::UpgradeAll => {
                self.launch("Mise à jour du système".into(), crate::updates::upgrade_all)
            }
            Message::UpgradeOs => self.launch(
                "Mise à jour d'AuxiNux OS".into(),
                crate::updates::upgrade_os,
            ),
            Message::UpdateOne(index) => match self.updates.ready().and_then(|l| l.get(index)) {
                Some(app) => {
                    let source = app.default_source.clone();
                    let id = app.id_for(&source).to_string();
                    let title = format!("Mise à jour de {}", app.name);
                    self.launch(title, move |on_line| {
                        crate::apps::update_app(&id, &source, on_line)
                    })
                }
                None => Task::none(),
            },

            // --- Sante ---
            Message::RefreshHealth => self.load_health(),
            Message::HealthLoaded(report) => {
                self.finish();
                self.health = Loading::Ready(report);
                Task::none()
            }
            Message::SystemLoaded(report) => {
                self.finish();
                self.system = Loading::Ready(report);
                Task::none()
            }

            // --- Restauration ---
            Message::RefreshRecovery => self.load_recovery(),
            Message::RecoveryLoaded(state) => {
                self.finish();
                self.recovery = Loading::Ready(state);
                Task::none()
            }
            Message::SnapshotDescription(d) => {
                self.snapshot_description = d;
                Task::none()
            }
            Message::CreateSnapshot => {
                let desc = if self.snapshot_description.trim().is_empty() {
                    "Instantané manuel".to_string()
                } else {
                    self.snapshot_description.trim().to_string()
                };
                self.snapshot_description.clear();
                self.start();
                background(move || crate::recovery::create_snapshot(&desc), Message::Done)
            }
            Message::ConfirmRollback(number) => {
                // Une restauration ne doit jamais partir d'un seul clic: elle
                // remplace la racine du systeme.
                self.pending_rollback = number;
                Task::none()
            }
            Message::ToggleAllSnapshots => {
                self.recovery_show_all = !self.recovery_show_all;
                Task::none()
            }
            Message::Rollback(number) => {
                self.pending_rollback = None;
                self.start();
                background(move || crate::recovery::rollback(number), Message::Done)
            }

            // --- Sources ---
            Message::RefreshSources => self.load_sources(),
            Message::SourcesLoaded(sources, presets, remotes) => {
                self.finish();
                self.apt_sources = Loading::Ready(sources);
                self.presets = presets;
                self.remotes = remotes;
                Task::none()
            }
            Message::ToggleAptSource(file, enabled) if crate::sources::is_kernel_dev_source(&file) => {
                self.update(Message::KernelDevSource(enabled))
            }
            Message::ToggleAptSource(file, enabled) => {
                self.start();
                background(
                    move || crate::sources::set_apt_source_enabled(&file, enabled),
                    Message::Done,
                )
            }
            Message::RemoveAptSource(file) => {
                self.start();
                background(move || crate::sources::remove_apt_source(&file), Message::Done)
            }
            Message::AddPreset(id) => {
                self.start();
                background(move || crate::sources::add_source_preset(&id), Message::Done)
            }
            Message::ToggleRemote(name, enabled) => {
                self.start();
                background(
                    move || crate::sources::set_flatpak_remote_enabled(&name, enabled),
                    Message::Done,
                )
            }
            Message::CustomName(v) => {
                self.custom_name = v;
                Task::none()
            }
            Message::CustomBody(v) => {
                self.custom_body = v;
                Task::none()
            }
            Message::CustomKeyUrl(v) => {
                self.custom_key_url = v;
                Task::none()
            }
            Message::AddCustomSource => {
                let name = self.custom_name.trim().to_string();
                let body = self.custom_body.clone();
                let key = self.custom_key_url.trim().to_string();
                if name.is_empty() || body.trim().is_empty() {
                    self.toast = Some(ActionResult::err(
                        "Renseignez au moins un nom et un corps deb822 (Types:, URIs:, Suites:…).",
                    ));
                    return Task::none();
                }
                self.custom_name.clear();
                self.custom_body.clear();
                self.custom_key_url.clear();
                self.start();
                background(
                    move || crate::sources::add_custom_apt_source(&name, &body, &key),
                    Message::Done,
                )
            }

            // --- Reglages ---
            Message::ToggleAptPolicy(enabled) => {
                self.apt_direct = enabled;
                self.start();
                background(move || crate::sources::set_apt_wrapper(enabled), Message::Done)
            }
            Message::ToggleDebApps(enabled) => {
                self.deb_apps = enabled;
                self.start();
                background(move || crate::sources::set_deb_apps(enabled), Message::Done)
            }
            Message::SetProfile(name) => {
                self.start();
                background(move || crate::profile::set(&name), Message::Done)
            }
            Message::SetDesktopSession(id) => {
                self.start();
                background(move || crate::session::set(&id), Message::Done)
            }
            Message::InstallPlasma => {
                self.launch("Installation de KDE Plasma".into(), crate::session::install_plasma)
            }
            Message::RemovePlasma => {
                self.launch("Retrait de KDE Plasma".into(), crate::session::remove_plasma)
            }
            Message::OpenSystemSettings => {
                crate::system::open_system_settings();
                Task::none()
            }
            Message::OpenUrl(url) => {
                let _ = open::that_detached(url);
                Task::none()
            }

            // --- Assistant de premier demarrage ---
            Message::AssistantRestart => {
                self.assistant_step = 0;
                self.selection = crate::assistant::Selection::default();
                self.assistant_bilan = None;
                self.page = Page::Assistant;
                self.nav.activate_position(6);
                Task::none()
            }
            Message::AssistantNext => {
                self.assistant_step = (self.assistant_step + 1).min(assistant_page::STEPS - 1);
                Task::none()
            }
            Message::AssistantBack => {
                self.assistant_step = self.assistant_step.saturating_sub(1);
                Task::none()
            }
            Message::AssistantSkip => {
                // « Passer » vaut reponse: l'assistant ne s'ouvrira plus a
                // chaque session, et il reste ici.
                let _ = crate::assistant::mark_done();
                self.nav.activate_position(0);
                // Le changement de page efface le bandeau: on le pose apres.
                let task = self.update(Message::Page(Page::Apps));
                self.toast = Some(ActionResult::ok(
                    "Assistant passé. Vous pouvez le relancer à tout moment: \
                     Réglages, « Relancer l'assistant ».",
                ));
                task
            }
            Message::AssistantBrowser(choice) => {
                self.selection.navigateur = choice;
                Task::none()
            }
            Message::AssistantPlayer(choice) => {
                self.selection.lecteur = choice;
                Task::none()
            }
            Message::AssistantProfil(profil) => {
                self.selection.set_profil(profil);
                Task::none()
            }
            Message::AssistantSuggestion(index, on) => {
                if let Some(slot) = self.selection.suggestions.get_mut(index) {
                    *slot = on;
                }
                Task::none()
            }
            Message::AssistantPrivacy(index, on) => {
                if let Some(slot) = self.selection.vie_privee.get_mut(index) {
                    *slot = on;
                }
                Task::none()
            }
            Message::AssistantInstall => {
                if self.op_running() {
                    return Task::none();
                }
                let selection = self.selection.clone();
                self.assistant_installing = true;
                self.assistant_bilan = None;
                self.launch("Installation de vos applications".into(), move |on_line| {
                    crate::assistant::apply(&selection, on_line)
                })
            }
            Message::AssistantFinish => {
                // Le bilan est sur la page finale: le panneau d'operation, qui
                // dit la meme chose, n'a plus de raison de rester affiche.
                self.operation = None;
                self.nav.activate_position(0);
                self.update(Message::Page(Page::Apps))
            }

            // --- Operation longue ---
            Message::OpLine(line) => {
                if let Some(op) = self.operation.as_mut() {
                    op.feed(&line);
                }
                Task::none()
            }
            Message::OpFinished(result) => {
                // Fin de l'installation de l'assistant: on passe a la page
                // finale, qui dit ce qui est installe et ce qui a echoue, au
                // lieu de laisser le recapitulatif et son bouton « Installer ».
                if std::mem::take(&mut self.assistant_installing) {
                    // Relue a la prochaine visite: sinon les applications que
                    // l'assistant vient d'installer y restent « a installer ».
                    if self.page != Page::Apps {
                        self.apps = Loading::Idle;
                    }
                    self.assistant_bilan = Some(crate::assistant::bilan(
                        &self.selection,
                        &result,
                        |app| app.desktop_file().1.exists(),
                    ));
                }
                if let Some(op) = self.operation.as_mut() {
                    op.result = Some(result);
                }
                // La liste des mises a jour est perimee des qu'un paquet a
                // bouge. Si l'utilisateur est sur une autre page, elle sera
                // relue a sa prochaine visite: sinon il verrait encore les
                // paquets qu'il vient de mettre a jour, et recommencerait.
                if self.page != Page::Updates {
                    self.updates = Loading::Idle;
                }
                // Meme raison pour les noyaux: une mise a jour du systeme ou la
                // page Sources peuvent les avoir changes.
                if self.page != Page::Apps || self.apps_view != AppsView::Kernel {
                    self.kernel = Loading::Idle;
                }
                // Le Center est un paquet DEB depuis la 0.2.1: une mise a jour
                // du systeme peut l'avoir remplace pendant qu'il tourne. Le
                // binaire en memoire reste l'ancien jusqu'a sa reouverture.
                // Une nouvelle version d'AuxiNux OS a pu etre installee:
                // os-release a change.
                self.os_version = crate::updates::os_version();
                // KDE Plasma installe ou retire depuis Reglages: la carte
                // « Bureau » doit montrer l'etat reel.
                self.desktop = crate::session::state();
                if let Some(version) = crate::updates::center_updated() {
                    self.toast = Some(ActionResult::ok(format!(
                        "AuxiNux OS Center a été mis à jour (version {version}). \
                         Fermez-le et rouvrez-le pour utiliser la nouvelle version."
                    )));
                }
                self.reload_current_page()
            }
            Message::ToggleLog => {
                if let Some(op) = self.operation.as_mut() {
                    op.show_log = !op.show_log;
                }
                Task::none()
            }
            Message::CopyLog => match &self.operation {
                Some(op) => cosmic::iced::clipboard::write::<cosmic::Action<Message>>(op.log_text()),
                None => Task::none(),
            },
            Message::DismissOperation => {
                if !self.op_running() {
                    self.operation = None;
                }
                Task::none()
            }

            // --- Transverse ---
            Message::Done(result) => {
                self.finish();
                // La politique APT affichee doit refleter l'etat REEL: si
                // l'utilisateur annule l'invite polkit, le bouton doit revenir
                // en arriere au lieu de mentir.
                self.apt_direct = crate::sources::apt_wrapper_enabled();
                self.deb_apps = crate::sources::deb_apps_enabled();
                // Meme raison pour le profil d'usage: si l'invite polkit est
                // annulee, la carte doit afficher le profil REEL, pas celui
                // qu'on vient de cliquer.
                self.profile = crate::profile::state();
                self.desktop = crate::session::state();
                self.toast = Some(result);
                self.reload_current_page()
            }
            Message::DismissToast => {
                self.toast = None;
                Task::none()
            }
            Message::TaskPanicked => {
                self.finish();
                self.toast = Some(ActionResult::err(
                    "L'opération s'est interrompue de façon inattendue. \
                     Réessayez; si le problème persiste, lancez la même action \
                     dans un terminal avec « auxi » pour voir le message complet.",
                ));
                Task::none()
            }
        }
    }

    fn subscription(&self) -> cosmic::iced::Subscription<Self::Message> {
        // Une lecture de dates toutes les deux secondes, fenetre ouverte et
        // dans la session AuxiNux seulement: le clair/sombre automatique du
        // shell bascule au coucher du soleil, sans autre signal.
        if self.apparence.is_some() {
            cosmic::iced::time::every(std::time::Duration::from_secs(2)).map(|_| Message::Apparence)
        } else {
            cosmic::iced::Subscription::none()
        }
    }

    fn view(&self) -> Element<'_, Self::Message> {
        // libcosmic recharge sa configuration (police Open Sans comprise)
        // juste apres le lancement, apres notre reglage: on la repose avant
        // de dessiner. Une simple lecture quand rien n'a change.
        if let Some(famille) = &self.police {
            apparence::garder_police(famille);
        }
        let content = match self.page {
            Page::Apps => apps_page::view(self),
            Page::Updates => updates_page::view(self),
            Page::Health => health_page::view(self),
            Page::Recovery => recovery_page::view(self),
            Page::Sources => sources_page::view(self),
            Page::Settings => settings_page::view(self),
            Page::Assistant => assistant_page::view(self),
        };

        let mut column = cosmic::widget::Column::new().spacing(12).push(content);

        if self.busy > 0 {
            column = column.push(widgets::activity(self.busy));
        }

        // Reste affichee d'une page a l'autre: on peut naviguer pendant une
        // mise a jour, et en retrouver le resultat ensuite.
        if let Some(op) = &self.operation {
            column = column.push(operation::view(op));
        }

        if let Some(toast) = &self.toast {
            column = column.push(widgets::toast(toast));
        }

        cosmic::widget::container(column)
            .padding(20)
            .width(iced::Length::Fill)
            .height(iced::Length::Fill)
            .into()
    }
}

// ---------------------------------------------------------------------------
// Fragments partages entre les pages
// ---------------------------------------------------------------------------

pub mod widgets {
    use super::*;
    use cosmic::widget;

    /// Bandeau de resultat. Les erreurs d'apt/flatpak sont verbeuses: on les
    /// affiche telles quelles plutot que de les resumer, car c'est ce texte que
    /// l'utilisateur copiera pour demander de l'aide.
    pub fn toast(result: &ActionResult) -> Element<'_, Message> {
        let icon = if result.ok {
            super::icon("emblem-ok-symbolic", &["object-select-symbolic"])
        } else {
            super::icon("dialog-error-symbolic", &["dialog-error", "data-error"])
        };
        widget::container(
            widget::Row::new()
                .spacing(10)
                .align_y(iced::Alignment::Center)
                .push(icon.size(16))
                .push(widget::text::body(result.message.clone()).width(iced::Length::Fill))
                .push(
                    widget::button::text("Fermer")
                        .on_press(Message::DismissToast),
                ),
        )
        .class(apparence::carte())
        .padding(12)
        .width(iced::Length::Fill)
        .into()
    }

    /// En-tete de page: titre, sous-titre et actions a droite.
    pub fn header<'a>(
        title: &'a str,
        subtitle: impl Into<String>,
        actions: Vec<Element<'a, Message>>,
    ) -> Element<'a, Message> {
        let mut right = widget::Row::new().spacing(8).align_y(iced::Alignment::Center);
        for action in actions {
            right = right.push(action);
        }
        widget::Row::new()
            .spacing(16)
            .align_y(iced::Alignment::Center)
            .push(
                widget::Column::new()
                    .spacing(2)
                    .width(iced::Length::Fill)
                    .push(widget::text::title3(title))
                    .push(widget::text::caption(subtitle.into())),
            )
            .push(right)
            .into()
    }

    /// Bandeau d'activite global. Il compte les operations en cours pour que
    /// l'utilisateur sache qu'il se passe quelque chose meme quand il a change
    /// de page entre-temps -- ce qui est justement ce que l'asynchrone permet.
    pub fn activity(count: usize) -> Element<'static, Message> {
        widget::container(
            widget::Row::new()
                .spacing(10)
                .align_y(iced::Alignment::Center)
                .push(super::icon("content-loading-symbolic", &["process-working-symbolic"]).size(16))
                .push(widget::text::caption(if count > 1 {
                    format!("{count} opérations en cours…")
                } else {
                    "Opération en cours…".to_string()
                })),
        )
        .class(apparence::carte())
        .padding(10)
        .width(iced::Length::Fill)
        .into()
    }

    /// Etat « en cours de chargement », avec un texte qui dit CE QUI est en
    /// cours: un indicateur muet ne distingue pas une attente d'un blocage.
    pub fn busy(what: &str) -> Element<'_, Message> {
        loading(what, "")
    }

    /// Etape d'un chargement, ou un texte d'attente tant que le fil de travail
    /// ne l'a pas encore annoncee: la page ne saute pas a la premiere etape.
    pub fn stage_or_start(stage: &str) -> &str {
        if stage.is_empty() {
            "Démarrage…"
        } else {
            stage
        }
    }

    /// `busy`, avec une barre animee et l'etape en cours (`detail`, vide si
    /// le chargement ne l'a pas encore annoncee). La barre bouge tant que
    /// l'interface vit: c'est ce qui distingue une attente d'un gel.
    pub fn loading<'a>(what: &'a str, detail: &'a str) -> Element<'a, Message> {
        let mut col = widget::Column::new()
            .spacing(10)
            .align_x(iced::Alignment::Center)
            .push(widget::text::body(what))
            .push(
                widget::container(
                    widget::progress_bar::indeterminate_linear().width(iced::Length::Fill),
                )
                .max_width(420),
            );
        if !detail.is_empty() {
            col = col.push(widget::text::caption(detail));
        }
        widget::container(col.push(widget::text::caption(
            "Vous pouvez continuer à naviguer pendant l'opération.",
        )))
        .center_x(iced::Length::Fill)
        .padding(40)
        .into()
    }

    /// Etat vide, avec une piste d'action plutot qu'un simple constat.
    pub fn empty<'a>(title: &'a str, hint: &'a str) -> Element<'a, Message> {
        widget::container(
            widget::Column::new()
                .spacing(6)
                .align_x(iced::Alignment::Center)
                .push(widget::text::title4(title))
                .push(widget::text::caption(hint)),
        )
        .center_x(iced::Length::Fill)
        .padding(40)
        .into()
    }

    pub fn source_label(source: &str) -> &'static str {
        match source {
            SOURCE_DEB => "AuxiNux (DEB)",
            SOURCE_FLATHUB => "Flathub",
            _ => "Autre",
        }
    }
}

/// Icone du theme, avec des noms de repli si le theme ne porte pas le premier.
///
/// Sans repli explicite, libcosmic retire les suffixes un a un
/// (« software-update-available-symbolic » → « software-update » →
/// « software »), ce qui ne tombe sur rien dans Breeze.
pub fn icon(name: &'static str, fallbacks: &[&'static str]) -> cosmic::widget::icon::Named {
    let named = cosmic::widget::icon::from_name(name);
    if fallbacks.is_empty() {
        return named;
    }
    named.fallback(Some(cosmic::widget::icon::IconFallback::Names(
        fallbacks.iter().map(|&f| f.into()).collect(),
    )))
}

pub fn run(ouverture: Ouverture) -> Result<(), Box<dyn std::error::Error>> {
    // Session AuxiNux Shell: apparence du shell et barre de titre de labwc
    // (voir crate::apparence). La police est posee AVANT Settings::default(),
    // qui la lit.
    let apparence = crate::apparence::lire();
    if let Some(a) = &apparence {
        apparence::appliquer_police(a);
        apparence::retenir_carte(a);
    }
    let mut settings = Settings::default();
    if let Some(a) = &apparence {
        settings = settings
            .theme(apparence::theme(a))
            .client_decorations(false)
            .transparent(false);
    }
    // Voir system::icon_theme(): sans cela, le theme « Cosmic », absent sous
    // Plasma, et une fenetre sans aucune icone -- boutons reduire, agrandir et
    // fermer compris.
    if let Some(theme) = crate::system::icon_theme() {
        settings = settings.default_icon_theme(theme);
    }
    cosmic::app::run::<App>(settings, ouverture)?;
    Ok(())
}
