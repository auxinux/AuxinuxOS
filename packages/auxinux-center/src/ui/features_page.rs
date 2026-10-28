//! Page FONCTIONNALITES AUXINUX: lecteurs virtuels a la Windows et fonctions
//! de l'activation (dont le mode PRO). Logique: crate::features.

use cosmic::{iced, widget, Element};

use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Fonctionnalités AuxiNux",
        "Ce qui n'existe que dans AuxiNux OS",
        vec![widget::button::standard("Actualiser").on_press(Message::RefreshFeatures).into()],
    );

    let Some(state) = app.features.ready() else {
        return widget::Column::new()
            .spacing(16)
            .push(header)
            .push(widget::text::body(if matches!(app.features, Loading::Busy) {
                "Lecture des fonctionnalités…"
            } else {
                ""
            }))
            .into();
    };

    // --- Lecteurs virtuels ----------------------------------------------------
    let drives = &state.drives;
    let mut drives_col = widget::Column::new()
        .spacing(8)
        .push(widget::text::heading("Lecteurs virtuels à la Windows"))
        .push(widget::text::caption(
            "C:\\ est la racine du système, C:\\Users\\<compte> votre dossier personnel ; \
             les disques, clés USB et partages réseau reçoivent une lettre à partir de D:. \
             AuxiFiles accepte les chemins Windows, et dans le terminal toutes les \
             commandes les comprennent (ls c:\\, cd C:\\Users\\…, cp D:\\a.txt …). Rien \
             n'est monté, déplacé ni renommé : c'est une traduction, réversible.",
        ));
    if drives.available {
        drives_col = drives_col
            .push(
                widget::Row::new()
                    .spacing(12)
                    .align_y(iced::Alignment::Center)
                    .push(
                        widget::text::body(if drives.enabled {
                            "Lecteurs virtuels : activés (AuxiFiles et terminal)"
                        } else {
                            "Lecteurs virtuels : désactivés"
                        })
                        .width(iced::Length::Fill),
                    )
                    .push(widget::toggler(drives.enabled).on_toggle(Message::SetDrives)),
            )
            .push(widget::text::caption(
                "Le terminal en tient compte à son prochain lancement (Bash et Zsh).",
            ));
        if drives.enabled {
            let mut display = widget::Row::new()
                .spacing(8)
                .align_y(iced::Alignment::Center)
                .push(widget::text::body("Chemins dans AuxiFiles :"));
            for (mode, label) in [("linux", "Linux (/home/…)"), ("windows", "Windows (C:\\Users\\…)")] {
                display = display.push(if drives.display == mode {
                    widget::button::suggested(label)
                } else {
                    widget::button::standard(label).on_press(Message::SetDrivesDisplay(mode.to_string()))
                });
            }
            drives_col = drives_col.push(display).push(
                widget::button::standard("Lettres et réservations…").on_press(Message::OpenDriveOptions),
            );
        }
    } else {
        drives_col = drives_col.push(widget::text::caption(
            "Non disponible : les lecteurs virtuels viennent d'AuxiNux Shell 0.3.19 ou plus \
             récent (commande auxidrive). Mettez le système à jour.",
        ));
    }
    let drives_card = widget::container(drives_col)
        .class(super::apparence::carte())
        .padding(14)
        .width(iced::Length::Fill);

    // --- Activation et fonctions PRO -----------------------------------------
    let activation = &state.activation;
    let mut act_col = widget::Column::new().spacing(8).push(widget::text::heading("Activation et mode PRO"));
    if activation.available {
        act_col = act_col.push(widget::text::body(match activation.edition.as_deref() {
            Some("pro") => "Édition PRO activée.",
            Some(_) => "AuxiNux OS est activé (activation gratuite).",
            None => "AuxiNux OS n'est pas activé : édition de base. Tout ce que vous utilisez reste gratuit.",
        }));
        for feature in &activation.features {
            let (label, description, page) = crate::features::describe(&feature.id);
            let status = if feature.pro && feature.offered {
                "PRO — offerte pendant la bêta"
            } else if feature.entitled {
                if feature.pro { "PRO — incluse" } else { "Débloquée" }
            } else if feature.pro {
                "PRO — édition PRO requise"
            } else {
                "Débloquée par l'activation gratuite"
            };
            let mut row = widget::Row::new()
                .spacing(12)
                .align_y(iced::Alignment::Center)
                .push(
                    widget::Column::new()
                        .spacing(2)
                        .push(widget::text::body(label))
                        .push(widget::text::caption(format!("{status}. {description}")))
                        .width(iced::Length::Fill),
                );
            if let (Some(page), true) = (page, feature.entitled) {
                row = row.push(
                    widget::button::standard("Configurer")
                        .on_press(Message::OpenShellSettings(page.to_string())),
                );
            }
            act_col = act_col.push(row);
        }
        act_col = act_col.push(
            widget::button::suggested(if activation.edition.is_some() {
                "Gérer l'activation"
            } else {
                "Activer AuxiNux OS"
            })
            .on_press(Message::OpenShellSettings("activation".into())),
        );
    } else {
        act_col = act_col.push(widget::text::caption(
            "Non disponible : l'activation vient d'AuxiNux Shell (Paramètres > Activation), \
             introuvable sur ce système.",
        ));
    }
    let act_card = widget::container(act_col)
        .class(super::apparence::carte())
        .padding(14)
        .width(iced::Length::Fill);

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(
            widget::scrollable(widget::Column::new().spacing(12).push(drives_card).push(act_card))
                .height(iced::Length::Fill),
        )
        .into()
}
