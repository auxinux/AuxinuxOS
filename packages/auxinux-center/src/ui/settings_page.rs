//! Page REGLAGES: bureau (AuxiNux Shell / KDE Plasma), assistant de
//! configuration, applications DEB, politique APT
//! maison, profil d'usage et acces aux reglages du bureau.
//!
//! Le Center ne reimplemente pas les reglages du bureau: il y renvoie.
//! Dupliquer les panneaux du bureau produirait deux endroits pour changer la
//! meme chose, avec des valeurs qui finissent par diverger.

use cosmic::{iced, widget, Element};

use crate::ui::{widgets, App, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Réglages",
        "Politique de paquets et accès aux réglages du bureau",
        vec![],
    );

    let apt = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Commandes APT directes"))
            .push(widget::text::caption(
                "Par défaut, « apt » et « apt-get » renvoient vers « auxi », qui met \
                 Flatpak en avant et crée un point de restauration avant chaque \
                 opération. Réactiver APT direct rend ces commandes utilisables \
                 telles quelles — mais sans ce filet de sécurité.",
            ))
            .push(
                widget::Row::new()
                    .spacing(12)
                    .align_y(iced::Alignment::Center)
                    .push(
                        widget::text::body(if app.apt_direct {
                            "APT direct: actif"
                        } else {
                            "APT direct: masqué (recommandé)"
                        })
                        .width(iced::Length::Fill),
                    )
                    .push(
                        widget::toggler(app.apt_direct).on_toggle(Message::ToggleAptPolicy),
                    ),
            ),
    )
    .class(super::apparence::carte())
    .padding(14)
    .width(iced::Length::Fill);

    // Distinct d'APT direct: on peut vouloir des applications DEB dans le
    // centre tout en gardant apt/apt-get renvoyes vers auxi.
    let deb = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Applications DEB"))
            .push(widget::text::caption(
                "Par défaut, les applications s'installent depuis Flatpak \
                 (Flathub), isolées du système. Activer l'installation DEB ajoute \
                 une liste déroulante Flatpak / DEB à la page Applications. Flatpak \
                 reste prioritaire: « auxi install » ne prend le paquet DEB que si \
                 aucun Flatpak n'existe.",
            ))
            .push(
                widget::Row::new()
                    .spacing(12)
                    .align_y(iced::Alignment::Center)
                    .push(
                        widget::text::body(if app.deb_apps {
                            "Installation DEB: activée"
                        } else {
                            "Installation DEB: désactivée (recommandé)"
                        })
                        .width(iced::Length::Fill),
                    )
                    .push(widget::toggler(app.deb_apps).on_toggle(Message::ToggleDebApps)),
            ),
    )
    .class(super::apparence::carte())
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
                "Alimentation {}, quantum audio {} échantillons, rtprio {}.",
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
            "« auxinux-profile » est introuvable sur ce système: les profils \
             d'usage ne sont pas disponibles.",
        ));
    }

    let profile = widget::container(profile_col)
        .class(super::apparence::carte())
        .padding(14)
        .width(iced::Length::Fill);

    // --- Bureau ---------------------------------------------------------------
    // AuxiNux Shell par defaut (decision d'aporler, 2026-10-10), KDE Plasma au
    // choix. Comme les profils: le choix courant est affiche, non cliquable.
    let mut desktop_col = widget::Column::new()
        .spacing(8)
        .push(widget::text::heading("Bureau"))
        .push(widget::text::caption(format!(
            "Ouvert à la connexion: {}. Le changement s'applique à la prochaine \
             ouverture de session; l'écran de connexion permet aussi de choisir \
             l'autre bureau pour une seule session.",
            crate::session::label(&app.desktop.default)
        )));
    if let Some(running) = &app.desktop.running {
        desktop_col = desktop_col.push(widget::text::caption(format!(
            "Session en cours: {}.",
            crate::session::label(running)
        )));
    }
    for (id, label, description) in crate::session::DESKTOPS {
        let installed = app.desktop.installed.iter().any(|i| i == id);
        let button = if id == app.desktop.default.as_str() {
            widget::button::suggested(label)
        } else if installed {
            widget::button::standard(label).on_press(Message::SetDesktopSession(id.to_string()))
        } else {
            widget::button::standard(label)
        };
        desktop_col = desktop_col.push(
            widget::Row::new()
                .spacing(12)
                .align_y(iced::Alignment::Center)
                .push(button)
                .push(widget::text::caption(if installed {
                    description.to_string()
                } else {
                    format!("{description} (non installé)")
                })),
        );
    }
    let desktop_choice = widget::container(desktop_col)
        .class(super::apparence::carte())
        .padding(14)
        .width(iced::Length::Fill);

    let assistant = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Assistant de configuration"))
            .push(widget::text::caption(
                "L'assistant du premier démarrage: navigateur, lecteur \
                 multimédia, applications selon votre profil, outils de vie privée. \
                 Le relancer n'enlève rien: il installe ce que vous ajoutez.",
            ))
            .push(
                widget::button::suggested("Relancer l'assistant")
                    .on_press(Message::AssistantRestart),
            ),
    )
    .class(super::apparence::carte())
    .padding(14)
    .width(iced::Length::Fill);

    let desktop = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("Réglages du bureau"))
            .push(widget::text::caption(
                "Affichage, apparence, clavier, langue, réseau et comptes se \
                 configurent dans les réglages du bureau.",
            ))
            .push(
                widget::button::suggested("Ouvrir les réglages du bureau")
                    .on_press(Message::OpenSystemSettings),
            ),
    )
    .class(super::apparence::carte())
    .padding(14)
    .width(iced::Length::Fill);

    let about = widget::container(
        widget::Column::new()
            .spacing(8)
            .push(widget::text::heading("À propos"))
            .push(widget::text::body(app.os_version.clone()))
            .push(widget::text::caption(
                "AuxiNux OS Center — centre de contrôle: applications, mises à jour, \
                 santé, sources, réglages et restauration.",
            ))
            .push(
                widget::button::text("Site du projet")
                    .on_press(Message::OpenUrl("https://os.auxinux.ca/auxinuxos".into())),
            ),
    )
    .class(super::apparence::carte())
    .padding(14)
    .width(iced::Length::Fill);

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(
            widget::scrollable(
                widget::Column::new()
                    .spacing(12)
                    .push(desktop_choice)
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
