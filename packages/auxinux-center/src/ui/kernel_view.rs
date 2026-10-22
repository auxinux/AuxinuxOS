//! Vue NOYAU de la page Applications: noyau actif, noyaux installes, mises a
//! jour, noyaux en essai.
//!
//! Chaque bouton correspond a une commande `auxi kernel` (voir kernel.rs). Les
//! boutons qu'auxi refuserait (desinstaller le noyau en cours ou le dernier
//! noyau stable) ne sont pas proposes: echouer APRES l'authentification
//! n'apprend rien a l'utilisateur.

use cosmic::{iced, widget, Element};

use crate::kernel::{Kernel, KernelState};
use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    match &app.kernel {
        Loading::Idle | Loading::Busy => widgets::loading("Lecture des noyaux…", ""),
        Loading::Ready(Err(reason)) => widgets::empty("Lecture des noyaux impossible", reason),
        Loading::Ready(Ok(state)) => {
            let mut col = widget::Column::new().spacing(12).push(active_card(app, state));
            for dev in [false, true] {
                if let Some(newer) = state.update_for(dev) {
                    col = col.push(update_card(app, newer));
                }
            }

            col = col.push(widget::text::heading("Noyaux installés"));
            for kernel in state.installed() {
                col = col.push(installed_card(app, state, kernel));
            }

            let stables = state.available(false);
            if !stables.is_empty() {
                col = col.push(widget::text::heading("Autres noyaux stables disponibles"));
                for kernel in stables {
                    col = col.push(available_card(app, kernel));
                }
            }

            col = col.push(dev_card(app, state));
            widget::scrollable(col).height(iced::Length::Fill).into()
        }
    }
}

fn channel(kernel: &Kernel) -> &'static str {
    if kernel.dev {
        "En essai"
    } else {
        "Stable"
    }
}

/// Bouton inactif pendant une operation: deux transactions se disputeraient le
/// verrou de dpkg.
fn action(app: &App, message: Message) -> Option<Message> {
    if app.op_running() {
        None
    } else {
        Some(message)
    }
}

fn card<'a>(content: impl Into<Element<'a, Message>>) -> Element<'a, Message> {
    widget::container(content)
        .class(super::apparence::carte())
        .padding(12)
        .width(iced::Length::Fill)
        .into()
}

fn active_card<'a>(app: &'a App, state: &'a KernelState) -> Element<'a, Message> {
    let mut col = widget::Column::new()
        .spacing(4)
        .push(widget::text::heading(format!("Noyau actif: {}", state.running)));

    if !state.default.is_empty() && state.default != state.running {
        col = col.push(widget::text::body(format!(
            "Au prochain démarrage: {}. Redémarrez l'ordinateur pour l'utiliser.",
            state.default
        )));
    }
    col = col.push(widget::text::caption(if state.pinned {
        "Le noyau de démarrage a été choisi à la main: les nouveaux noyaux \
         s'installent, mais ne sont pas utilisés tant que vous ne revenez pas \
         au plus récent."
    } else {
        "L'ordinateur démarre toujours sur le noyau le plus récent. Les autres \
         restent proposés dans le menu de démarrage, « Options avancées »."
    }));
    if state.pinned {
        col = col.push(
            widget::button::standard("Revenir au plus récent")
                .on_press_maybe(action(app, Message::KernelActivate("latest".into()))),
        );
    }
    card(col)
}

fn update_card<'a>(app: &'a App, newer: &'a Kernel) -> Element<'a, Message> {
    card(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(
                widget::Column::new()
                    .spacing(2)
                    .width(iced::Length::Fill)
                    .push(widget::text::heading(format!(
                        "Nouveau noyau disponible: {}",
                        newer.version
                    )))
                    .push(widget::text::caption(if newer.dev {
                        "Canal en essai. L'ancien noyau reste installé."
                    } else {
                        "Canal stable. L'ancien noyau reste installé: c'est votre \
                         recours si le nouveau pose problème."
                    })),
            )
            .push(
                widget::button::suggested("Mettre à jour")
                    .on_press_maybe(action(app, Message::KernelUpdate)),
            ),
    )
}

fn installed_card<'a>(app: &'a App, state: &'a KernelState, kernel: &'a Kernel) -> Element<'a, Message> {
    let mut details = vec![channel(kernel)];
    if kernel.running {
        details.push("en cours d'utilisation");
    }
    if kernel.default {
        details.push("démarrage par défaut");
    }

    let info = widget::Column::new()
        .spacing(2)
        .width(iced::Length::Fill)
        .push(widget::text::heading(kernel.version.clone()))
        .push(widget::text::caption(details.join(" · ")));

    // Confirmation en deux temps, comme pour une restauration.
    if app.pending_kernel_remove.as_deref() == Some(kernel.version.as_str()) {
        return card(
            widget::Column::new()
                .spacing(8)
                .push(info)
                .push(widget::text::caption(
                    "Désinstaller ce noyau? Il disparaîtra aussi du menu de démarrage. \
                     Vos fichiers ne sont pas touchés.",
                ))
                .push(
                    widget::Row::new()
                        .spacing(8)
                        .push(
                            widget::button::destructive("Désinstaller")
                                .on_press_maybe(action(app, Message::KernelRemove(kernel.version.clone()))),
                        )
                        .push(
                            widget::button::standard("Annuler")
                                .on_press(Message::KernelConfirmRemove(None)),
                        ),
                ),
        );
    }

    let mut actions = widget::Row::new().spacing(8).align_y(iced::Alignment::Center);
    if !kernel.default {
        actions = actions.push(
            widget::button::standard("Activer")
                .on_press_maybe(action(app, Message::KernelActivate(kernel.version.clone()))),
        );
    }
    if state.removable(kernel) {
        actions = actions.push(
            widget::button::standard("Désinstaller")
                .on_press_maybe(action(app, Message::KernelConfirmRemove(Some(kernel.version.clone())))),
        );
    }

    card(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(info)
            .push(actions),
    )
}

fn available_card<'a>(app: &'a App, kernel: &'a Kernel) -> Element<'a, Message> {
    card(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(
                widget::Column::new()
                    .spacing(2)
                    .width(iced::Length::Fill)
                    .push(widget::text::heading(kernel.version.clone()))
                    .push(widget::text::caption(channel(kernel))),
            )
            .push(
                widget::button::standard("Installer")
                    .on_press_maybe(action(app, Message::KernelInstall(kernel.version.clone()))),
            ),
    )
}

fn dev_card<'a>(app: &'a App, state: &'a KernelState) -> Element<'a, Message> {
    let toggler = widget::toggler(state.dev_source);
    let toggler = if app.op_running() {
        toggler
    } else {
        toggler.on_toggle(Message::KernelDevSource)
    };

    let mut col = widget::Column::new()
        .spacing(8)
        .push(widget::text::heading("Noyaux en essai (kernel-dev)"))
        .push(widget::text::caption(
            "Des noyaux plus récents, avant leur sortie en version stable. À réserver \
             à ceux qui veulent les essayer: en cas de problème, choisissez l'ancien \
             noyau dans le menu de démarrage, « Options avancées ».",
        ))
        .push(
            widget::Row::new()
                .spacing(12)
                .align_y(iced::Alignment::Center)
                .push(
                    widget::text::body(if state.dev_source {
                        "Noyaux en essai: activés"
                    } else {
                        "Noyaux en essai: désactivés"
                    })
                    .width(iced::Length::Fill),
                )
                .push(toggler),
        );

    if state.dev_source {
        let available = state.available(true);
        if available.is_empty() {
            col = col.push(widget::text::caption(
                "Aucun noyau en essai à installer pour l'instant.",
            ));
        }
        for kernel in available {
            col = col.push(available_card(app, kernel));
        }
    }
    card(col)
}
