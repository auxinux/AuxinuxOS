//! Page APPLICATIONS: recherche, mise en avant, installation, desinstallation.
//!
//! Flatpak (Flathub) seulement, sauf si l'installation DEB est activee dans
//! les Reglages (`auxi set deb=true`): une liste deroulante, sous les boutons
//! de vue, bascule alors TOUTE la page entre Flatpak et DEB. Une fiche dit
//! toujours le nom reellement vise: sur une fiche Flathub affichee en DEB,
//! l'identifiant Flatpak et le nom du paquet different.

use cosmic::{iced, widget, Element};

use crate::model::AppEntry;
use crate::ui::{widgets, App, AppsView, Loading, Message, APPS_SOURCES};

/// Libelles de la liste deroulante, dans l'ordre de APPS_SOURCES.
const SOURCE_LABELS: &[&str] = &["Flatpak (Flathub)", "DEB (AuxiNux)"];

pub fn view(app: &App) -> Element<'_, Message> {
    let search = widget::search_input("Rechercher une application…", &app.query)
        .on_input(Message::SearchInput)
        .on_submit(|_| Message::SearchSubmit)
        .width(iced::Length::Fill);

    let kernel_view = app.apps_view == AppsView::Kernel;
    let header = widgets::header(
        "Applications",
        if kernel_view {
            "Noyaux AuxiNux: le noyau actif, les autres versions, les noyaux en essai"
        } else if app.deb_apps {
            "Flatpak par défaut; paquets DEB au choix dans la liste"
        } else {
            "Applications Flatpak (Flathub)"
        },
        vec![
            widget::button::standard("Suggestions")
                .on_press(Message::ShowFeatured)
                .into(),
            widget::button::standard("Installées")
                .on_press(Message::ShowInstalled)
                .into(),
            widget::button::standard("Noyau")
                .on_press(Message::ShowKernel)
                .into(),
        ],
    );

    // Vue Noyau: ni recherche ni source Flatpak/DEB, qui n'ont pas de sens ici.
    if kernel_view {
        return widget::Column::new()
            .spacing(16)
            .push(header)
            .push(super::kernel_view::view(app))
            .into();
    }

    let body: Element<Message> = match &app.apps {
        Loading::Busy => widgets::loading(
            match app.apps_view {
                AppsView::Search(_) => "Recherche en cours…",
                AppsView::Installed => "Lecture des applications installées…",
                AppsView::Featured | AppsView::Kernel => "Chargement des suggestions…",
            },
            widgets::stage_or_start(&app.apps_stage),
        ),
        Loading::Idle => widgets::loading("Chargement…", ""),
        Loading::Ready(list) if list.is_empty() => widgets::empty(
            "Aucune application trouvée",
            "Essayez un autre terme, ou parcourez les suggestions.",
        ),
        Loading::Ready(list) => {
            // Seules les fiches de la source affichee; l'index reste celui de
            // la liste complete, que Install/Remove relisent.
            let source = app.apps_source();
            let mut col = widget::Column::new().spacing(8);
            let mut shown = 0usize;
            for (index, entry) in list.iter().enumerate() {
                if entry.has_source(source) {
                    col = col.push(card(app, index, entry));
                    shown += 1;
                }
            }
            if shown == 0 {
                widgets::empty(
                    "Aucune application trouvée dans cette source",
                    "Essayez un autre terme, ou l'autre source de la liste.",
                )
            } else {
                widget::scrollable(col).height(iced::Length::Fill).into()
            }
        }
    };

    let mut page = widget::Column::new().spacing(16).push(header);
    // La liste deroulante n'existe que si l'installation DEB est activee:
    // sinon il n'y a rien a choisir.
    if app.deb_apps {
        let selected = APPS_SOURCES.iter().position(|s| *s == app.apps_source());
        page = page.push(
            widget::Row::new()
                .spacing(8)
                .align_y(iced::Alignment::Center)
                .push(widget::Space::new().width(iced::Length::Fill))
                .push(widget::text::body("Source"))
                .push(widget::dropdown(SOURCE_LABELS, selected, Message::AppsSource)),
        );
    }
    page.push(search).push(body).into()
}

fn card<'a>(app: &'a App, index: usize, entry: &'a AppEntry) -> Element<'a, Message> {
    let source = app.source_for(entry);

    let mut info = widget::Column::new()
        .spacing(2)
        .width(iced::Length::Fill)
        .push(widget::text::heading(entry.name.clone()));

    if !entry.summary.is_empty() {
        info = info.push(widget::text::caption(entry.summary.clone()));
    }

    // Toujours dire ce qui sera installe, et sous quel nom. Sur une fiche
    // Flathub basculee en DEB, ces deux identifiants different.
    let target = entry.id_for(&source);
    info = info.push(widget::text::caption(format!(
        "{} — {}{}",
        widgets::source_label(&source),
        target,
        if entry.version.is_empty() {
            String::new()
        } else {
            format!(" · {}", entry.version)
        }
    )));

    let mut actions = widget::Row::new().spacing(8).align_y(iced::Alignment::Center);
    // Inactifs pendant une autre installation: voir App::op_running.
    let idle = !app.op_running();

    // Un seul bouton, celui qui a un sens. Afficher « Installer » ET
    // « Desinstaller » sur toutes les fiches laissait l'utilisateur deviner ce
    // qui etait deja present -- et « Installer » sur une application deja
    // installee ne rendait qu'un message d'erreur d'apt.
    if entry.is_installed(&source) {
        actions = actions
            .push(widget::text::caption("Installée"))
            .push(
                widget::button::destructive("Désinstaller")
                    .on_press_maybe(idle.then_some(Message::Remove(index))),
            );
    } else {
        actions = actions.push(
            widget::button::suggested("Installer")
                .on_press_maybe(idle.then_some(Message::Install(index))),
        );
    }

    widget::container(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(info)
            .push(actions),
    )
    .class(cosmic::theme::Container::Card)
    .padding(12)
    .width(iced::Length::Fill)
    .into()
}
