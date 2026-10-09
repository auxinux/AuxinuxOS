//! Page MISES A JOUR: applications Flatpak, paquets DEB et systeme, et la
//! nouvelle version d'AuxiNux OS quand une ISO plus recente est publiee.
//!
//! Le message central de cette page est le filet de securite: chaque mise a
//! jour DEB est precedee d'un instantane cree par `auxi`. Le dire ici evite
//! que l'utilisateur repousse indefiniment ses mises a jour par crainte de
//! casser sa machine.

use cosmic::{iced, widget, Element};

use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    // Une seule transaction a la fois: pendant une mise a jour, les boutons qui
    // en lanceraient une autre sont inactifs (verrou de dpkg).
    let idle = !app.op_running();

    let header = widgets::header(
        "Mises à jour",
        app.os_version.clone(),
        vec![
            widget::button::standard("Actualiser les listes")
                .on_press_maybe(idle.then_some(Message::RefreshIndexes))
                .into(),
            widget::button::standard("Rechercher")
                .on_press(Message::RefreshUpdates)
                .into(),
        ],
    );

    let body: Element<Message> = match &app.updates {
        Loading::Idle | Loading::Busy => {
            widgets::loading(
                "Recherche des mises à jour…",
                widgets::stage_or_start(&app.updates_stage),
            )
        }
        Loading::Ready(list) if list.is_empty() => widgets::empty(
            "Votre système est à jour",
            "Rien à installer pour le moment.",
        ),
        Loading::Ready(list) => {
            let mut col = widget::Column::new().spacing(8);
            for (index, entry) in list.iter().enumerate() {
                let mut info = widget::Column::new()
                    .spacing(2)
                    .width(iced::Length::Fill)
                    .push(widget::text::heading(entry.name.clone()))
                    .push(widget::text::caption(format!(
                        "{} — {}",
                        widgets::source_label(&entry.default_source),
                        entry.summary
                    )));
                if !entry.version.is_empty() {
                    info = info.push(widget::text::caption(format!(
                        "Nouvelle version: {}",
                        entry.version
                    )));
                }
                col = col.push(
                    widget::container(
                        widget::Row::new()
                            .spacing(12)
                            .align_y(iced::Alignment::Center)
                            .push(info)
                            .push(
                                widget::button::standard("Mettre à jour")
                                    .on_press_maybe(idle.then_some(Message::UpdateOne(index))),
                            ),
                    )
                    .class(cosmic::theme::Container::Card)
                    .padding(12)
                    .width(iced::Length::Fill),
                );
            }
            widget::scrollable(col).height(iced::Length::Fill).into()
        }
    };

    let count = app.updates.ready().map(|l| l.len()).unwrap_or(0);

    let banner = widget::container(
        widget::Column::new()
            .spacing(6)
            .push(widget::text::heading(if count == 0 {
                "Tout mettre à jour".to_string()
            } else {
                format!("Tout mettre à jour ({count})")
            }))
            .push(widget::text::caption(
                "Un point de restauration est créé automatiquement avant la mise à \
                 jour des paquets système. En cas de problème, l'onglet Restauration \
                 permet de revenir à l'état précédent.",
            ))
            .push(
                widget::button::suggested("Mettre à jour le système")
                    .on_press_maybe(idle.then_some(Message::UpgradeAll)),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill);

    let mut page = widget::Column::new().spacing(16).push(header);
    if let Some(update) = &app.os_update {
        page = page.push(os_update_card(app, update, idle));
    }
    page.push(banner).push(body).into()
}

/// Nouvelle version d'AuxiNux OS (une edition par ISO publiee): ce qu'elle
/// apporte, et la mise a jour en un clic. Le bouton lance la meme operation
/// que « Mettre a jour le systeme »: `auxi upgrade` installe ou met a jour le
/// paquet auxinuxos-release, qui tire le reste.
fn os_update_card<'a>(
    app: &'a App,
    update: &'a crate::updates::OsUpdate,
    idle: bool,
) -> Element<'a, Message> {
    let mut col = widget::Column::new()
        .spacing(6)
        .push(widget::text::heading("Nouvelle version d'AuxiNux OS disponible"))
        .push(widget::text::body(update.available.clone()))
        .push(widget::text::caption(format!("Version installée : {}", app.os_version)));
    if !update.notes.is_empty() {
        let mut notes = widget::Column::new().spacing(2);
        for note in &update.notes {
            notes = notes.push(widget::text::caption(format!("• {note}")));
        }
        col = col.push(notes);
    }
    col = col.push(
        widget::button::suggested("Mettre à jour vers cette version")
            .on_press_maybe(idle.then_some(Message::UpgradeAll)),
    );
    widget::container(col)
        .class(cosmic::theme::Container::Card)
        .padding(14)
        .width(iced::Length::Fill)
        .into()
}
