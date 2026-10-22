//! Page SOURCES: depots APT, depots connus et remotes Flatpak.
//!
//! Les depots systeme (auxinux*, brave*) sont affiches mais non supprimables:
//! les retirer casserait les mises a jour du noyau et du navigateur, sans
//! signal clair pour l'utilisateur avant la panne suivante.

use cosmic::{iced, widget, Element};

use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Sources de logiciels",
        "D'où proviennent les applications et les mises à jour",
        vec![widget::button::standard("Actualiser")
            .on_press(Message::RefreshSources)
            .into()],
    );

    let body: Element<Message> = match &app.apt_sources {
        Loading::Idle | Loading::Busy => widgets::busy("Lecture des dépôts…"),
        Loading::Ready(sources) => {
            let mut col = widget::Column::new().spacing(16);

            // --- Depots APT ---
            let mut apt = widget::Column::new()
                .spacing(8)
                .push(widget::text::heading("Dépôts APT (paquets DEB)"));
            if sources.is_empty() {
                apt = apt.push(widget::text::caption("Aucun dépôt configuré."));
            }
            for source in sources {
                let mut actions = widget::Row::new()
                    .spacing(8)
                    .align_y(iced::Alignment::Center)
                    .push(widget::toggler(source.enabled).on_toggle({
                        let file = source.file.clone();
                        move |enabled| Message::ToggleAptSource(file.clone(), enabled)
                    }));

                if source.removable {
                    actions = actions.push(
                        widget::button::destructive("Retirer")
                            .on_press(Message::RemoveAptSource(source.file.clone())),
                    );
                }

                let mut info = widget::Column::new()
                    .spacing(2)
                    .width(iced::Length::Fill)
                    .push(widget::text::body(source.name.clone()))
                    .push(widget::text::caption(format!(
                        "{} · {}",
                        source.file, source.kind
                    )));
                if !source.removable {
                    info = info.push(widget::text::caption(
                        "Dépôt système AuxiNux — protégé contre la suppression.",
                    ));
                }

                apt = apt.push(
                    widget::container(
                        widget::Row::new()
                            .spacing(12)
                            .align_y(iced::Alignment::Center)
                            .push(info)
                            .push(actions),
                    )
                    .class(super::apparence::carte())
                    .padding(12)
                    .width(iced::Length::Fill),
                );
            }
            col = col.push(apt);

            // --- Depots connus ---
            let mut presets = widget::Column::new().spacing(8).push(
                widget::Column::new()
                    .spacing(2)
                    .push(widget::text::heading("Dépôts connus"))
                    .push(widget::text::caption(
                        "Ajout en un clic. La clé de signature est téléchargée depuis le \
                         domaine officiel de l'éditeur, vérifiée comme clé OpenPGP valide, \
                         puis épinglée: un changement ultérieur est refusé.",
                    )),
            );
            for preset in &app.presets {
                let action: Element<Message> = if preset.installed {
                    widget::text::caption("Déjà ajouté").into()
                } else {
                    widget::button::standard("Ajouter")
                        .on_press(Message::AddPreset(preset.id.clone()))
                        .into()
                };
                presets = presets.push(
                    widget::container(
                        widget::Row::new()
                            .spacing(12)
                            .align_y(iced::Alignment::Center)
                            .push(
                                widget::Column::new()
                                    .spacing(2)
                                    .width(iced::Length::Fill)
                                    .push(widget::text::body(preset.name.clone()))
                                    .push(widget::text::caption(preset.description.clone())),
                            )
                            .push(action),
                    )
                    .class(super::apparence::carte())
                    .padding(12)
                    .width(iced::Length::Fill),
                );
            }
            col = col.push(presets);

            // --- Remotes Flatpak ---
            let mut remotes = widget::Column::new()
                .spacing(8)
                .push(widget::text::heading("Dépôts Flatpak"));
            for remote in &app.remotes {
                remotes = remotes.push(
                    widget::container(
                        widget::Row::new()
                            .spacing(12)
                            .align_y(iced::Alignment::Center)
                            .push(
                                widget::Column::new()
                                    .spacing(2)
                                    .width(iced::Length::Fill)
                                    .push(widget::text::body(remote.name.clone()))
                                    .push(widget::text::caption(remote.url.clone())),
                            )
                            .push(widget::toggler(remote.enabled).on_toggle({
                                let name = remote.name.clone();
                                move |enabled| Message::ToggleRemote(name.clone(), enabled)
                            })),
                    )
                    .class(super::apparence::carte())
                    .padding(12)
                    .width(iced::Length::Fill),
                );
            }
            col = col.push(remotes);
            col = col.push(custom_form(app));

            widget::scrollable(col).height(iced::Length::Fill).into()
        }
    };

    widget::Column::new().spacing(16).push(header).push(body).into()
}

/// Formulaire de depot personnalise.
///
/// Le corps et l'URL de cle sont ecrits/executes en contexte root: la
/// validation reelle est faite cote backend (`is_safe_sources_body`,
/// `is_safe_key_url`), jamais ici. L'interface se contente d'expliquer le
/// format attendu -- un champ libre sans exemple produit surtout des erreurs.
fn custom_form(app: &App) -> Element<'_, Message> {
    widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Ajouter un dépôt personnalisé"))
            .push(widget::text::caption(
                "Format deb822. Seuls les champs Types, URIs, Suites, Components, \
                 Architectures, Signed-By et Enabled sont acceptés.",
            ))
            .push(
                widget::text_input("Nom (ex. mon-depot)", &app.custom_name)
                    .on_input(Message::CustomName),
            )
            .push(
                widget::text_input(
                    "Types: deb / URIs: https://… / Suites: trixie / Components: main",
                    &app.custom_body,
                )
                .on_input(Message::CustomBody),
            )
            .push(
                widget::text_input(
                    "URL de la clé GPG (https://…, facultatif)",
                    &app.custom_key_url,
                )
                .on_input(Message::CustomKeyUrl),
            )
            .push(
                widget::button::suggested("Ajouter le dépôt")
                    .on_press(Message::AddCustomSource),
            ),
    )
    .class(super::apparence::carte())
    .padding(14)
    .width(iced::Length::Fill)
    .into()
}
