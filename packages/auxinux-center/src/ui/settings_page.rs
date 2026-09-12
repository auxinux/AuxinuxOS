//! Page REGLAGES: politique APT maison et acces aux reglages du bureau.
//!
//! Le Center ne reimplemente pas les reglages du bureau: il y renvoie.
//! Dupliquer les panneaux du bureau produirait deux endroits pour changer la
//! meme chose, avec des valeurs qui finissent par diverger.

use cosmic::{iced, widget, Element};

use crate::ui::{widgets, App, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Reglages",
        "Politique de paquets et acces aux reglages du bureau",
        vec![],
    );

    let apt = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Commandes APT directes"))
            .push(widget::text::caption(
                "Par defaut, « apt » et « apt-get » renvoient vers « auxi », qui met \
                 Flatpak en avant et cree un point de restauration avant chaque \
                 operation. Reactiver APT direct rend ces commandes utilisables \
                 telles quelles — mais sans ce filet de securite.",
            ))
            .push(
                widget::Row::new()
                    .spacing(12)
                    .align_y(iced::Alignment::Center)
                    .push(
                        widget::text::body(if app.apt_direct {
                            "APT direct: actif"
                        } else {
                            "APT direct: masque (recommande)"
                        })
                        .width(iced::Length::Fill),
                    )
                    .push(
                        widget::toggler(app.apt_direct).on_toggle(Message::ToggleAptPolicy),
                    ),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill);

    let desktop = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Reglages du bureau"))
            .push(widget::text::caption(
                "Affichage, apparence, clavier, langue, reseau et comptes se \
                 configurent dans les reglages du bureau.",
            ))
            .push(
                widget::button::suggested("Ouvrir les reglages du bureau")
                    .on_press(Message::OpenSystemSettings),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill);

    let about = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("A propos"))
            .push(widget::text::body(app.os_version.clone()))
            .push(widget::text::caption(
                "AuxiNux OS Center — centre de controle: applications, mises a jour, \
                 sante, sources, reglages et restauration.",
            ))
            .push(
                widget::button::text("Site du projet")
                    .on_press(Message::OpenUrl("https://auxinux.ca/".into())),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill);

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(
            widget::scrollable(
                widget::Column::new()
                    .spacing(12)
                    .push(apt)
                    .push(desktop)
                    .push(about),
            )
            .height(iced::Length::Fill),
        )
        .into()
}
