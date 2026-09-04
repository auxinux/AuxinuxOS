//! Page MISES A JOUR: applications Flatpak, paquets DEB et systeme.
//!
//! Le message central de cette page est le filet de securite: chaque mise a
//! jour DEB est precedee d'un instantane cree par `auxi`. Le dire ici evite
//! que l'utilisateur repousse indefiniment ses mises a jour par crainte de
//! casser sa machine.

use cosmic::{iced, widget, Element};

use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Mises a jour",
        app.os_version.clone(),
        vec![
            widget::button::standard("Actualiser les listes")
                .on_press(Message::RefreshIndexes)
                .into(),
            widget::button::standard("Rechercher")
                .on_press(Message::RefreshUpdates)
                .into(),
        ],
    );

    let body: Element<Message> = match &app.updates {
        Loading::Idle | Loading::Busy => widgets::busy("Recherche des mises a jour…"),
        Loading::Ready(list) if list.is_empty() => widgets::empty(
            "Votre systeme est a jour",
            "Rien a installer pour le moment.",
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
                                widget::button::standard("Mettre a jour")
                                    .on_press(Message::UpdateOne(index)),
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
                "Tout mettre a jour".to_string()
            } else {
                format!("Tout mettre a jour ({count})")
            }))
            .push(widget::text::caption(
                "Un point de restauration est cree automatiquement avant la mise a \
                 jour des paquets systeme. En cas de probleme, l'onglet Restauration \
                 permet de revenir a l'etat precedent.",
            ))
            .push(
                widget::button::suggested("Mettre a jour le systeme")
                    .on_press(Message::UpgradeAll),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill);

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(banner)
        .push(body)
        .into()
}
