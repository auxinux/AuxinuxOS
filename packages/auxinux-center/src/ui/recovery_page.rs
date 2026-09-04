//! Page RESTAURATION: points de restauration BTRFS.
//!
//! Deux garde-fous d'interface, parce que l'action remplace la racine du
//! systeme: la restauration demande une confirmation explicite, et l'ecran
//! rappelle systematiquement que /home n'est jamais touche -- c'est la
//! premiere crainte exprimee devant ce genre de bouton.

use cosmic::{iced, widget, Element};

use crate::model::Snapshot;
use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Restauration",
        "Revenir a un etat anterieur du systeme",
        vec![widget::button::standard("Actualiser")
            .on_press(Message::RefreshRecovery)
            .into()],
    );

    let body: Element<Message> = match &app.recovery {
        Loading::Idle | Loading::Busy => widgets::busy("Lecture des points de restauration…"),
        Loading::Ready(state) if !state.available => widget::container(
            widget::Column::new()
                .spacing(8)
                .align_x(iced::Alignment::Center)
                .push(widget::text::title4("Restauration indisponible"))
                .push(widget::text::body(state.reason.clone()))
                .push(widget::text::caption(
                    "La restauration exige une installation sur BTRFS. Elle ne peut pas \
                     etre activee apres coup sur un systeme installe en ext4.",
                )),
        )
        .center_x(iced::Length::Fill)
        .padding(40)
        .into(),
        Loading::Ready(state) if state.snapshots.is_empty() => widgets::empty(
            "Aucun point de restauration",
            "Creez-en un maintenant: c'est la sauvegarde a laquelle vous reviendrez \
             si une mise a jour tourne mal.",
        ),
        Loading::Ready(state) => {
            let mut col = widget::Column::new().spacing(8);
            for snapshot in &state.snapshots {
                col = col.push(snapshot_card(app, snapshot));
            }
            widget::scrollable(col).height(iced::Length::Fill).into()
        }
    };

    let available = app
        .recovery
        .ready()
        .map(|s| s.available)
        .unwrap_or(false);

    let mut column = widget::Column::new().spacing(16).push(header);

    if available {
        column = column.push(create_card(app));
    }

    column.push(body).into()
}

fn create_card(app: &App) -> Element<'_, Message> {
    widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Creer un point de restauration"))
            .push(widget::text::caption(
                "Utile avant une manipulation risquee. Un point est deja cree \
                 automatiquement avant chaque installation ou mise a jour de paquets.",
            ))
            .push(
                widget::Row::new()
                    .spacing(8)
                    .align_y(iced::Alignment::Center)
                    .push(
                        widget::text_input(
                            "Description (ex. « avant essai pilote graphique »)",
                            &app.snapshot_description,
                        )
                        .on_input(Message::SnapshotDescription)
                        .on_submit(|_| Message::CreateSnapshot)
                        .width(iced::Length::Fill),
                    )
                    .push(
                        widget::button::suggested("Creer")
                            .on_press(Message::CreateSnapshot),
                    ),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill)
    .into()
}

fn snapshot_card<'a>(app: &'a App, snapshot: &'a Snapshot) -> Element<'a, Message> {
    let description = if snapshot.description.is_empty() {
        format!("Instantane {}", snapshot.number)
    } else {
        snapshot.description.clone()
    };

    let origin = if snapshot.from_auxi {
        "Cree automatiquement avant une operation de paquets"
    } else {
        "Cree manuellement ou par la planification horaire"
    };

    let info = widget::Column::new()
        .spacing(2)
        .width(iced::Length::Fill)
        .push(widget::text::heading(description))
        .push(widget::text::caption(format!(
            "N° {} · {} · {}",
            snapshot.number, snapshot.date, snapshot.kind
        )))
        .push(widget::text::caption(origin));

    // Confirmation en deux temps sur la fiche concernee: pas de boite de
    // dialogue modale qui masquerait la date a laquelle on revient.
    let action: Element<Message> = if app.pending_rollback == Some(snapshot.number) {
        widget::Column::new()
            .spacing(6)
            .push(widget::text::caption(
                "Confirmer? Vos fichiers personnels et vos applications Flatpak \
                 ne seront pas modifies. Le systeme actuel est conserve.",
            ))
            .push(
                widget::Row::new()
                    .spacing(8)
                    .push(
                        widget::button::destructive("Restaurer et redemarrer plus tard")
                            .on_press(Message::Rollback(snapshot.number)),
                    )
                    .push(
                        widget::button::standard("Annuler")
                            .on_press(Message::ConfirmRollback(None)),
                    ),
            )
            .into()
    } else {
        widget::button::standard("Restaurer")
            .on_press(Message::ConfirmRollback(Some(snapshot.number)))
            .into()
    };

    widget::container(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(info)
            .push(action),
    )
    .class(cosmic::theme::Container::Card)
    .padding(12)
    .width(iced::Length::Fill)
    .into()
}
