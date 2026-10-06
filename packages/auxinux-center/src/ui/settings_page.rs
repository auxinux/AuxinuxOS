//! Page REGLAGES: assistant de configuration, applications DEB, politique APT
//! maison, profil d'usage et acces aux reglages du bureau.
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

    // Distinct d'APT direct: on peut vouloir des applications DEB dans le
    // centre tout en gardant apt/apt-get renvoyes vers auxi.
    let deb = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Applications DEB"))
            .push(widget::text::caption(
                "Par defaut, les applications s'installent depuis Flatpak \
                 (Flathub), isolees du systeme. Activer l'installation DEB ajoute \
                 une liste deroulante Flatpak / DEB a la page Applications. Flatpak \
                 reste prioritaire: « auxi install » ne prend le paquet DEB que si \
                 aucun Flatpak n'existe.",
            ))
            .push(
                widget::Row::new()
                    .spacing(12)
                    .align_y(iced::Alignment::Center)
                    .push(
                        widget::text::body(if app.deb_apps {
                            "Installation DEB: active"
                        } else {
                            "Installation DEB: desactivee (recommande)"
                        })
                        .width(iced::Length::Fill),
                    )
                    .push(widget::toggler(app.deb_apps).on_toggle(Message::ToggleDebApps)),
            ),
    )
    .class(cosmic::theme::Container::Card)
    .padding(14)
    .width(iced::Length::Fill);

    // --- Profil d'usage -----------------------------------------------------
    // Les trois usages annonces par AuxiNuxOS. Le Center n'ecrit rien lui-meme:
    // il appelle `auxinux-profile`, seul proprietaire de ces reglages.
    let mut profile_col = widget::Column::new()
        .spacing(8)
        .push(widget::text::heading("Profil d'usage"));

    if app.profile.available {
        let (label, effect) = crate::profile::describe(&app.profile.current);
        profile_col = profile_col
            .push(widget::text::caption(format!(
                "Actuel: {label} — {effect}"
            )))
            .push(widget::text::caption(format!(
                "Alimentation {}, quantum audio {} echantillons, rtprio {}.",
                app.profile.power, app.profile.quantum, app.profile.rtprio
            )));

        let mut row = widget::Row::new().spacing(8);
        for name in crate::profile::PROFILES {
            let (label, _) = crate::profile::describe(name);
            // Le profil courant reste affiche mais non cliquable: reappliquer
            // le meme profil n'apporte rien et couterait une invite polkit.
            let button = if name == app.profile.current.as_str() {
                widget::button::suggested(label)
            } else {
                widget::button::standard(label).on_press(Message::SetProfile(name.to_string()))
            };
            row = row.push(button);
        }
        profile_col = profile_col.push(row);
    } else {
        profile_col = profile_col.push(widget::text::caption(
            "« auxinux-profile » est introuvable sur ce systeme: les profils \
             d'usage ne sont pas disponibles.",
        ));
    }

    let profile = widget::container(profile_col)
        .class(cosmic::theme::Container::Card)
        .padding(14)
        .width(iced::Length::Fill);

    let assistant = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Assistant de configuration"))
            .push(widget::text::caption(
                "L'assistant du premier demarrage: navigateur, lecteur \
                 multimedia, applications selon votre profil, outils de vie privee. \
                 Le relancer n'enleve rien: il installe ce que vous ajoutez.",
            ))
            .push(
                widget::button::suggested("Relancer l'assistant")
                    .on_press(Message::AssistantRestart),
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
                    .on_press(Message::OpenUrl("https://os.auxinux.ca/auxinuxos".into())),
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
                    .push(assistant)
                    .push(deb)
                    .push(apt)
                    .push(profile)
                    .push(desktop)
                    .push(about),
            )
            .height(iced::Length::Fill),
        )
        .into()
}
