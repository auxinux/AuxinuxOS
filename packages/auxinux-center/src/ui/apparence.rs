//! Theme libcosmic construit depuis l'apparence de la session AuxiNux Shell
//! (voir crate::apparence): gris et accent du shell, coins a la Windows 11
//! (4 px pour les boutons et champs, 8 px pour les cartes) au lieu des pilules
//! de COSMIC, police du shell.

use std::sync::Arc;

use cosmic::cosmic_theme::palette::{Srgb, Srgba};
use cosmic::cosmic_theme::{CornerRadii, ThemeBuilder};

use crate::apparence::{Apparence, Rgb};

fn srgb([r, g, b]: Rgb) -> Srgb {
    Srgb::new(r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0)
}

fn srgba(c: Rgb) -> Srgba {
    let s = srgb(c);
    Srgba::new(s.red, s.green, s.blue, 1.0)
}

pub fn theme(a: &Apparence) -> cosmic::Theme {
    let mut builder = if a.sombre { ThemeBuilder::dark() } else { ThemeBuilder::light() };
    builder = builder
        .bg_color(srgba(a.fond))
        // Panneau lateral du fond de la fenetre, comme les Parametres du shell.
        .primary_container_bg(srgba(a.fond))
        .accent(srgb(a.accent))
        .corner_radii(CornerRadii {
            radius_0: [0.0; 4],
            radius_xs: [4.0; 4],
            radius_s: [4.0; 4],
            radius_m: [8.0; 4],
            radius_l: [8.0; 4],
            radius_xl: [4.0; 4],
        });
    if let Some(c) = a.negatif {
        builder = builder.destructive(srgb(c));
    }
    if let Some(c) = a.positif {
        builder = builder.success(srgb(c));
    }
    if let Some(c) = a.neutre {
        builder = builder.warning(srgb(c));
    }
    cosmic::Theme::custom(Arc::new(builder.build()))
}

/// Police d'interface de libcosmic (titres en semi-gras compris: ils relisent
/// ce reglage a chaque affichage).
pub fn appliquer_police(a: &Apparence) {
    if let Some(famille) = &a.police {
        garder_police(famille);
    }
}

/// Repose la police si libcosmic l'a remplacee (rechargement de sa config).
pub fn garder_police(famille: &str) {
    let a_changer = cosmic::config::COSMIC_TK
        .read()
        .map(|tk| tk.interface_font.family != famille)
        .unwrap_or(false);
    if a_changer {
        if let Ok(mut tk) = cosmic::config::COSMIC_TK.write() {
            tk.interface_font.family = famille.to_string();
        }
    }
}

/// Couleur des cartes de la session AuxiNux (None: cartes de libcosmic).
///
/// libcosmic derive la couleur des cartes du fond, sans reglage: en mode clair
/// elles sortaient plus FONCEES que le fond (gris sur gris), quand celles du
/// shell et de Windows 11 sont blanches sur un fond gris clair.
static CARTE: std::sync::RwLock<Option<Rgb>> = std::sync::RwLock::new(None);

pub fn retenir_carte(a: &Apparence) {
    if let Ok(mut carte) = CARTE.write() {
        *carte = Some(a.carte);
    }
}

/// Style des cartes: celui de libcosmic, avec la couleur et les coins du
/// shell dans la session AuxiNux.
pub fn carte<'a>() -> cosmic::theme::Container<'a> {
    cosmic::theme::Container::custom(|theme: &cosmic::Theme| {
        use cosmic::iced::widget::container::Catalog;
        let mut style = theme.style(&cosmic::theme::Container::Card);
        if let Some([r, g, b]) = CARTE.read().ok().and_then(|c| *c) {
            style.background = Some(cosmic::iced::Background::Color(cosmic::iced::Color::from_rgb8(r, g, b)));
            style.border.radius = 8.0.into();
        }
        style
    })
}
