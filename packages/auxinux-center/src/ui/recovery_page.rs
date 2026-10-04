//! Page RESTAURATION: points de restauration BTRFS.
//!
//! Deux garde-fous d'interface, parce que l'action remplace la racine du
//! systeme: la restauration demande une confirmation explicite, et l'ecran
//! rappelle systematiquement que /home n'est jamais touche -- c'est la
//! premiere crainte exprimee devant ce genre de bouton.

use cosmic::{iced, widget, Element};

use crate::recovery::{Origine, Point};
use crate::ui::{widgets, App, Loading, Message};

/// Points montres d'emblee. Au-dela, « Afficher les autres »: une longue
/// liste de retours en arriere possibles inquiete plus qu'elle ne rassure.
const VISIBLES: usize = 5;

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
            let points = crate::recovery::points(&state.snapshots);
            let mut col = widget::Column::new().spacing(8).push(widget::text::caption(
                "En cas de probleme, choisissez le point le plus recent d'AVANT le \
                 probleme. Vos fichiers personnels ne sont jamais touches.",
            ));
            let caches = points.len().saturating_sub(VISIBLES);
            for (i, point) in points.into_iter().enumerate() {
                // L'etat d'origine reste toujours visible: c'est le retour
                // ultime, celui qu'on cherche quand tout le reste a echoue.
                if app.recovery_show_all || i < VISIBLES || point.origine == Origine::Installation {
                    col = col.push(point_card(app, point));
                }
            }
            if caches > 0 {
                col = col.push(
                    widget::button::text(if app.recovery_show_all {
                        "Afficher seulement les plus recents".to_string()
                    } else {
                        format!("Afficher les {caches} autres points")
                    })
                    .on_press(Message::ToggleAllSnapshots),
                );
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

    let demarre_sur = app.recovery.ready().and_then(|s| s.demarre_sur);
    if let Some(n) = demarre_sur {
        column = column.push(temporary_card(app, n));
    } else if available {
        column = column.push(create_card(app));
    }

    column.push(body).into()
}

/// Demarrage sur un instantane depuis GRUB: dire ou l'on est, que c'est
/// temporaire, et comment le rendre definitif.
fn temporary_card(app: &App, number: u32) -> Element<'_, Message> {
    let titre = app
        .recovery
        .ready()
        .and_then(|s| {
            crate::recovery::points(&s.snapshots)
                .into_iter()
                .find(|p| p.number == number)
                .map(|p| format!("« {} » du {}", p.titre, p.date))
        })
        .unwrap_or_else(|| format!("n° {number}"));

    let action: Element<Message> = if app.pending_rollback == Some(number) {
        widget::Row::new()
            .spacing(8)
            .push(
                widget::button::destructive("Confirmer: garder cet etat")
                    .on_press(Message::Rollback(number)),
            )
            .push(widget::button::standard("Annuler").on_press(Message::ConfirmRollback(None)))
            .into()
    } else {
        widget::button::suggested("Garder cet etat definitivement")
            .on_press(Message::ConfirmRollback(Some(number)))
            .into()
    };

    widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Vous utilisez un point de restauration, temporairement"))
            .push(widget::text::body(format!(
                "Le systeme a demarre sur le point {titre}, choisi dans le menu de \
                 demarrage. Rien n'est encore restaure: ce que vous faites maintenant \
                 sera perdu au prochain redemarrage."
            )))
            .push(widget::text::caption(
                "Si tout fonctionne, gardez cet etat: il remplacera le systeme au \
                 prochain redemarrage (l'ancien est conserve, et vos fichiers \
                 personnels ne sont pas touches). Sinon, redemarrez normalement.",
            ))
            .push(action),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill)
    .into()
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

fn point_card(app: &App, point: Point) -> Element<'_, Message> {
    let origine = match point.origine {
        Origine::Installation => "Le systeme tel qu'il etait juste apres l'installation",
        Origine::AvantModification => "Pose automatiquement avant une modification des logiciels",
        Origine::Quotidien => "Sauvegarde automatique, une par jour",
        Origine::Manuel => "Cree par vous",
    };

    let info = widget::Column::new()
        .spacing(2)
        .width(iced::Length::Fill)
        .push(widget::text::heading(point.titre))
        .push(widget::text::caption(point.date))
        .push(widget::text::caption(origine));

    // Confirmation en deux temps sur la fiche concernee: pas de boite de
    // dialogue modale qui masquerait la date a laquelle on revient.
    let action: Element<Message> = if app.pending_rollback == Some(point.number) {
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
                            .on_press(Message::Rollback(point.number)),
                    )
                    .push(
                        widget::button::standard("Annuler")
                            .on_press(Message::ConfirmRollback(None)),
                    ),
            )
            .into()
    } else {
        widget::button::standard("Restaurer")
            .on_press(Message::ConfirmRollback(Some(point.number)))
            .into()
    };

    // En attente de confirmation, la question passe SOUS la fiche: a cote, elle
    // ecrasait le titre et la date en une colonne de quelques lettres.
    let content: Element<Message> = if app.pending_rollback == Some(point.number) {
        widget::Column::new().spacing(10).push(info).push(action).into()
    } else {
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(info)
            .push(action)
            .into()
    };

    widget::container(content)
    .class(cosmic::theme::Container::Card)
    .padding(12)
    .width(iced::Length::Fill)
    .into()
}
