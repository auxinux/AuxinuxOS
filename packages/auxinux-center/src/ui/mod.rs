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
//! Organisation: un `nav_bar` a gauche, une page par section. Chaque page vit
//! dans son propre module et n'expose qu'une fonction `view`.

mod apps_page;
mod health_page;
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
use crate::task::background;

pub const APP_ID: &str = "ca.auxinux.Center";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Page {
    Apps,
    Updates,
    Health,
    Recovery,
    Sources,
    Settings,
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

    // Applications
    SearchInput(String),
    SearchSubmit,
    AppsLoaded(Vec<AppEntry>),
    ShowInstalled,
    ShowFeatured,
    SelectSource(usize, String),
    Install(usize),
    Remove(usize),

    // Mises a jour
    RefreshUpdates,
    RefreshIndexes,
    UpdatesLoaded(Vec<AppEntry>),
    UpgradeAll,
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
    OpenSystemSettings,
    OpenUrl(String),

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
    /// Source retenue pour chaque fiche, quand l'utilisateur en change.
    chosen_source: std::collections::HashMap<String, String>,

    // Mises a jour
    updates: Loading<Vec<AppEntry>>,
    os_version: String,

    // Sante
    health: Loading<HealthReport>,
    system: Loading<SystemReport>,

    // Restauration
    recovery: Loading<RecoveryState>,
    snapshot_description: String,
    /// Instantane dont la restauration attend confirmation.
    pending_rollback: Option<u32>,

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

    /// Derniere operation terminee, affichee en bandeau.
    toast: Option<ActionResult>,
    /// Nombre d'operations longues en cours, pour l'indicateur global.
    busy: usize,
}

impl App {
    /// Source active pour une fiche: le choix de l'utilisateur s'il en a fait
    /// un, sinon la source par defaut calculee par le backend (Flathub).
    pub fn source_for(&self, app: &AppEntry) -> String {
        self.chosen_source
            .get(&app.id)
            .cloned()
            .unwrap_or_else(|| app.default_source.clone())
    }

    fn start(&mut self) {
        self.busy += 1;
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
        self.apps = Loading::Busy;
        self.start();
        match self.apps_view.clone() {
            AppsView::Featured => background(crate::apps::featured, Message::AppsLoaded),
            AppsView::Installed => background(crate::apps::list_installed, Message::AppsLoaded),
            AppsView::Search(q) => background(move || crate::apps::search(&q), Message::AppsLoaded),
        }
    }

    fn load_updates(&mut self) -> Task<Message> {
        self.updates = Loading::Busy;
        self.start();
        background(crate::apps::list_updates, Message::UpdatesLoaded)
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
            Page::Settings => Task::none(),
        }
    }
}

impl Application for App {
    type Executor = executor::Default;
    type Flags = ();
    type Message = Message;

    const APP_ID: &'static str = APP_ID;

    fn core(&self) -> &Core {
        &self.core
    }

    fn core_mut(&mut self) -> &mut Core {
        &mut self.core
    }

    fn init(core: Core, _flags: Self::Flags) -> (Self, Task<Self::Message>) {
        let mut nav = nav_bar::Model::default();
        for (title, icon, page) in [
            ("Applications", "system-software-install-symbolic", Page::Apps),
            ("Mises a jour", "software-update-available-symbolic", Page::Updates),
            ("Sante du systeme", "utilities-system-monitor-symbolic", Page::Health),
            ("Restauration", "document-revert-symbolic", Page::Recovery),
            ("Sources", "application-x-addon-symbolic", Page::Sources),
            ("Reglages", "preferences-system-symbolic", Page::Settings),
        ] {
            nav.insert()
                .text(title)
                .icon(cosmic::widget::icon::from_name(icon))
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
            chosen_source: std::collections::HashMap::new(),
            updates: Loading::Idle,
            os_version: crate::updates::os_version(),
            health: Loading::Idle,
            system: Loading::Idle,
            recovery: Loading::Idle,
            snapshot_description: String::new(),
            pending_rollback: None,
            apt_sources: Loading::Idle,
            presets: Vec::new(),
            remotes: Vec::new(),
            custom_name: String::new(),
            custom_body: String::new(),
            custom_key_url: String::new(),
            apt_direct: crate::sources::apt_wrapper_enabled(),
            toast: None,
            busy: 0,
        };

        let task = app.load_apps_featured();
        let title = app.set_window_title(format!("Centre de controle — {}", app.os_version));
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
            Message::Page(page) => {
                self.page = page;
                self.toast = None;
                // Chargement paresseux: une section n'est interrogee qu'a sa
                // premiere ouverture. Tout charger au demarrage rendrait le
                // lancement aussi lent que l'operation la plus lente.
                match page {
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
            Message::AppsLoaded(list) => {
                self.finish();
                self.apps = Loading::Ready(list);
                Task::none()
            }
            Message::SelectSource(index, source) => {
                if let Some(app) = self.apps.ready().and_then(|l| l.get(index)) {
                    self.chosen_source.insert(app.id.clone(), source);
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
                    self.start();
                    background(move || crate::apps::install(&id, &source), Message::Done)
                }
                None => Task::none(),
            },
            Message::Remove(index) => match self.apps.ready().and_then(|l| l.get(index)) {
                Some(app) => {
                    let source = self.source_for(app);
                    let id = app.id_for(&source).to_string();
                    self.start();
                    background(move || crate::apps::remove(&id, &source), Message::Done)
                }
                None => Task::none(),
            },

            // --- Mises a jour ---
            Message::RefreshUpdates => self.load_updates(),
            Message::RefreshIndexes => {
                // Rafraichir les index AVANT de lister les mises a jour: sans
                // cela, l'utilisateur qui vient d'activer un depot ne voit rien
                // de nouveau et croit le depot cassé.
                self.start();
                background(crate::updates::refresh_indexes, Message::Done)
            }
            Message::UpdatesLoaded(list) => {
                self.finish();
                self.updates = Loading::Ready(list);
                Task::none()
            }
            Message::UpgradeAll => {
                self.start();
                background(crate::updates::upgrade_all, Message::Done)
            }
            Message::UpdateOne(index) => match self.updates.ready().and_then(|l| l.get(index)) {
                Some(app) => {
                    let source = app.default_source.clone();
                    let id = app.id_for(&source).to_string();
                    self.start();
                    background(move || crate::apps::update_app(&id, &source), Message::Done)
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
                    "Instantane manuel".to_string()
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
            Message::OpenSystemSettings => {
                crate::system::open_system_settings();
                Task::none()
            }
            Message::OpenUrl(url) => {
                let _ = open::that_detached(url);
                Task::none()
            }

            // --- Transverse ---
            Message::Done(result) => {
                self.finish();
                // La politique APT affichee doit refleter l'etat REEL: si
                // l'utilisateur annule l'invite polkit, le bouton doit revenir
                // en arriere au lieu de mentir.
                self.apt_direct = crate::sources::apt_wrapper_enabled();
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
                    "L'operation s'est interrompue de facon inattendue. \
                     Reessayez; si le probleme persiste, lancez la meme action \
                     dans un terminal avec « auxi » pour voir le message complet.",
                ));
                Task::none()
            }
        }
    }

    fn view(&self) -> Element<'_, Self::Message> {
        let content = match self.page {
            Page::Apps => apps_page::view(self),
            Page::Updates => updates_page::view(self),
            Page::Health => health_page::view(self),
            Page::Recovery => recovery_page::view(self),
            Page::Sources => sources_page::view(self),
            Page::Settings => settings_page::view(self),
        };

        let mut column = cosmic::widget::Column::new().spacing(12).push(content);

        if self.busy > 0 {
            column = column.push(widgets::activity(self.busy));
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
            "emblem-ok-symbolic"
        } else {
            "dialog-error-symbolic"
        };
        widget::container(
            widget::Row::new()
                .spacing(10)
                .align_y(iced::Alignment::Center)
                .push(widget::icon::from_name(icon).size(16))
                .push(widget::text::body(result.message.clone()).width(iced::Length::Fill))
                .push(
                    widget::button::text("Fermer")
                        .on_press(Message::DismissToast),
                ),
        )
        .class(cosmic::theme::Container::Card)
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
                .push(widget::icon::from_name("content-loading-symbolic").size(16))
                .push(widget::text::caption(if count > 1 {
                    format!("{count} operations en cours…")
                } else {
                    "Operation en cours…".to_string()
                })),
        )
        .class(cosmic::theme::Container::Card)
        .padding(10)
        .width(iced::Length::Fill)
        .into()
    }

    /// Etat « en cours de chargement », avec un texte qui dit CE QUI est en
    /// cours: un indicateur muet ne distingue pas une attente d'un blocage.
    pub fn busy(what: &str) -> Element<'_, Message> {
        widget::container(
            widget::Column::new()
                .spacing(10)
                .align_x(iced::Alignment::Center)
                .push(widget::text::body(what))
                .push(widget::text::caption(
                    "Vous pouvez continuer a naviguer pendant l'operation.",
                )),
        )
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

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    // `Settings` n'expose pas de constructeur de taille dans cette version de
    // libcosmic (ses champs sont pub(crate)): on garde les valeurs par defaut.
    cosmic::app::run::<App>(Settings::default(), ())?;
    Ok(())
}
