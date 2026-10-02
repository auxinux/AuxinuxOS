//! Page APPLICATIONS: recherche, mise en avant, installation, desinstallation.
//!
//! La bascule Flathub/DEB est explicite sur chaque fiche, avec le nom du
//! paquet reellement vise. C'est ce que l'ancienne interface ne montrait pas:
//! l'utilisateur choisissait « DEB » sans savoir quel paquet allait etre
//! installe -- et ce n'etait pas toujours le bon.

use cosmic::{iced, widget, Element};

use crate::model::{AppEntry, SOURCE_DEB, SOURCE_FLATHUB};
use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let search = widget::search_input("Rechercher une application…", &app.query)
        .on_input(Message::SearchInput)
        .on_submit(|_| Message::SearchSubmit)
        .width(iced::Length::Fill);

    let header = widgets::header(
        "Applications",
        "Flathub en priorite, paquets DEB disponibles en alternative",
        vec![
            widget::button::standard("Suggestions")
                .on_press(Message::ShowFeatured)
                .into(),
            widget::button::standard("Installees")
                .on_press(Message::ShowInstalled)
                .into(),
        ],
    );

    let body: Element<Message> = match &app.apps {
        Loading::Busy => widgets::busy("Recherche en cours…"),
        Loading::Idle => widgets::busy("Chargement…"),
        Loading::Ready(list) if list.is_empty() => widgets::empty(
            "Aucune application trouvee",
            "Essayez un autre terme, ou parcourez les suggestions.",
        ),
        Loading::Ready(list) => {
            let mut col = widget::Column::new().spacing(8);
            for (index, entry) in list.iter().enumerate() {
                col = col.push(card(app, index, entry));
            }
            widget::scrollable(col).height(iced::Length::Fill).into()
        }
    };

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(search)
        .push(body)
        .into()
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

    // La bascule n'apparait que si l'application existe reellement dans les
    // deux sources.
    if entry.has_source(SOURCE_FLATHUB) && entry.has_source(SOURCE_DEB) {
        for candidate in [SOURCE_FLATHUB, SOURCE_DEB] {
            let selected = source == candidate;
            let label = widgets::source_label(candidate);
            let button = if selected {
                widget::button::suggested(label)
            } else {
                widget::button::standard(label)
            };
            actions = actions.push(
                button.on_press(Message::SelectSource(index, candidate.to_string())),
            );
        }
    }

    // Un seul bouton, celui qui a un sens. Afficher « Installer » ET
    // « Desinstaller » sur toutes les fiches laissait l'utilisateur deviner ce
    // qui etait deja present -- et « Installer » sur une application deja
    // installee ne rendait qu'un message d'erreur d'apt.
    if entry.is_installed(&source) {
        actions = actions
            .push(widget::text::caption("Installee"))
            .push(
                widget::button::destructive("Desinstaller")
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
