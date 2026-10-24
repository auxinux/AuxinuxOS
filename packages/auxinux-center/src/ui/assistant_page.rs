//! Page ASSISTANT: le choix des applications au premier demarrage.
//!
//! Six etapes, une question par ecran: bienvenue, navigateur, lecteur
//! multimedia, profil d'usage (avec ses applications suggerees), vie
//! privee, recapitulatif. Rien n'est installe avant le dernier ecran, et le
//! recapitulatif montre exactement ce qui le sera. Une fois l'installation
//! finie, une page de bilan le remplace: ce qui est installe, ce qui a echoue. Le catalogue et le calcul de
//! la selection vivent dans assistant.rs, hors de l'interface.

use cosmic::{iced, widget, Element};

use crate::assistant::{self, App as Entry, Profil, LECTEURS, NAVIGATEURS, VIE_PRIVEE};
use crate::ui::{widgets, App, Message};

pub const STEPS: usize = 6;
/// Valeur de bouton radio pour « aucun ».
const AUCUN: usize = usize::MAX;

pub fn view(app: &App) -> Element<'_, Message> {
    if let Some(bilan) = &app.assistant_bilan {
        return fin(app, bilan);
    }
    let sel = &app.selection;
    let step = app.assistant_step.min(STEPS - 1);

    let header = widgets::header(
        "Assistant de configuration",
        format!("Étape {} sur {}", step + 1, STEPS),
        vec![],
    );

    let body: Element<Message> = match step {
        0 => intro(),
        1 => question(
            "Quel navigateur voulez-vous ?",
            "Un seul sera installé. Vous pourrez en ajouter d'autres plus tard \
             depuis la page Applications.",
            radios(&NAVIGATEURS, sel.navigateur, Message::AssistantBrowser, "Aucun pour l'instant"),
        ),
        2 => question(
            "Quel lecteur multimédia voulez-vous ?",
            "Pour vos vidéos et votre musique. Les codecs sont déjà installés: \
             tout lecteur saura lire les formats courants.",
            radios(&LECTEURS, sel.lecteur, Message::AssistantPlayer, "Aucun"),
        ),
        3 => profil(sel),
        4 => question(
            "Outils de vie privée",
            "Proposés par AuxiNux, cochés d'avance. Décochez ceux dont vous ne \
             voulez pas.",
            checkboxes(
                VIE_PRIVEE.iter().copied().zip(sel.vie_privee.iter().copied()),
                Message::AssistantPrivacy,
            ),
        ),
        _ => recap(app),
    };

    // Navigation. « Suivant » n'existe pas au dernier ecran: c'est
    // « Installer », qui seul agit sur le systeme.
    let idle = !app.op_running();
    let mut nav = widget::Row::new().spacing(8).align_y(iced::Alignment::Center);
    nav = nav.push(
        widget::button::text("Passer l'assistant")
            .on_press_maybe(idle.then_some(Message::AssistantSkip)),
    );
    nav = nav.push(widget::Space::new().width(iced::Length::Fill));
    if step > 0 {
        nav = nav.push(
            widget::button::standard("Précédent")
                .on_press_maybe(idle.then_some(Message::AssistantBack)),
        );
    }
    if step + 1 < STEPS {
        nav = nav.push(
            widget::button::suggested(if step == 0 { "Commencer" } else { "Suivant" })
                .on_press(Message::AssistantNext),
        );
    } else {
        nav = nav.push(
            widget::button::suggested(if app.assistant_installing {
                "Installation en cours…"
            } else {
                "Installer"
            })
            .on_press_maybe(idle.then_some(Message::AssistantInstall)),
        );
    }

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(widget::scrollable(body).height(iced::Length::Fill))
        .push(nav)
        .into()
}

fn card<'a>(content: impl Into<Element<'a, Message>>) -> Element<'a, Message> {
    widget::container(content)
        .class(super::apparence::carte())
        .padding(16)
        .width(iced::Length::Fill)
        .into()
}

fn question<'a>(
    title: &'a str,
    hint: &'a str,
    choices: Element<'a, Message>,
) -> Element<'a, Message> {
    card(
        widget::Column::new()
            .spacing(12)
            .push(widget::text::title4(title))
            .push(widget::text::body(hint))
            .push(choices),
    )
}

fn intro<'a>() -> Element<'a, Message> {
    card(
        widget::Column::new()
            .spacing(12)
            .push(widget::text::title3("Bienvenue dans AuxiNux OS"))
            .push(widget::text::body(
                "Votre système est installé avec le strict nécessaire: le bureau \
                 AuxiNux Shell, les applications AuxiNux (AuxiOffice avec \
                 AuxiPDF, AuxiText, AuxiMail, le correcteur AuxiCorrect), le \
                 catalogue AuxiPak, quelques outils de KDE (fichiers, terminal, \
                 images) et de quoi faire tourner les applications Windows \
                 (Wine et Bottles). KDE Plasma s'installe depuis Réglages.",
            ))
            .push(widget::text::body(
                "Aucune autre application n'a été choisie à votre place. Cet \
                 assistant vous demande ce que vous voulez: navigateur, \
                 lecteur multimédia, et des applications selon l'usage que \
                 vous faites de votre ordinateur.",
            ))
            .push(widget::text::caption(
                "Rien n'est installé avant le dernier écran, qui récapitule vos \
                 choix. Une connexion Internet est nécessaire. Vous pourrez \
                 relancer cet assistant à tout moment depuis le centre de \
                 contrôle, dans Réglages.",
            )),
    )
}

fn entry_label<'a>(entry: &Entry) -> Element<'a, Message> {
    widget::Column::new()
        .spacing(2)
        .push(widget::text::body(entry.name))
        .push(widget::text::caption(entry.summary))
        .into()
}

fn radios<'a>(
    entries: &'static [Entry],
    selected: Option<usize>,
    on_pick: fn(Option<usize>) -> Message,
    none_label: &'a str,
) -> Element<'a, Message> {
    let selected = Some(selected.unwrap_or(AUCUN));
    let mut col = widget::Column::new().spacing(10);
    for (index, entry) in entries.iter().enumerate() {
        col = col.push(widget::radio(entry_label(entry), index, selected, move |v| {
            on_pick(Some(v))
        }));
    }
    col.push(widget::radio(
        widget::text::body(none_label),
        AUCUN,
        selected,
        move |_| on_pick(None),
    ))
    .into()
}

fn checkboxes<'a>(
    items: impl Iterator<Item = (Entry, bool)>,
    on_toggle: fn(usize, bool) -> Message,
) -> Element<'a, Message> {
    let mut col = widget::Column::new().spacing(10);
    for (index, (entry, checked)) in items.enumerate() {
        col = col.push(
            widget::Row::new()
                .spacing(10)
                .align_y(iced::Alignment::Center)
                .push(widget::checkbox(checked).on_toggle(move |v| on_toggle(index, v)))
                .push(entry_label(&entry)),
        );
    }
    col.into()
}

fn profil(sel: &assistant::Selection) -> Element<'_, Message> {
    let mut profiles = widget::Row::new().spacing(8);
    for p in Profil::TOUS {
        let button = if p == sel.profil {
            widget::button::suggested(p.label())
        } else {
            widget::button::standard(p.label()).on_press(Message::AssistantProfil(p))
        };
        profiles = profiles.push(button);
    }
    let (_, effect) = crate::profile::describe(sel.profil.id());

    card(
        widget::Column::new()
            .spacing(12)
            .push(widget::text::title4("À quoi servira surtout cet ordinateur ?"))
            .push(widget::text::body(
                "Le profil règle le système pour cet usage, et propose des \
                 applications. Il se change ensuite dans Réglages.",
            ))
            .push(profiles)
            .push(widget::text::caption(effect))
            .push(widget::text::heading("Applications suggérées"))
            .push(checkboxes(
                sel.profil
                    .suggestions()
                    .iter()
                    .map(|(entry, _)| *entry)
                    .zip(sel.suggestions.iter().copied()),
                Message::AssistantSuggestion,
            )),
    )
}

fn recap(app: &App) -> Element<'_, Message> {
    let sel = &app.selection;
    let mut list = widget::Column::new().spacing(6);
    for entry in sel.applications() {
        let origin = match entry.source {
            assistant::Source::Flatpak => "Flatpak (Flathub)",
            assistant::Source::Brave => "Dépôt officiel de Brave",
        };
        list = list.push(
            widget::Row::new()
                .spacing(12)
                .push(widget::text::body(entry.name).width(iced::Length::Fixed(160.0)))
                .push(widget::text::caption(format!("{} — {}", entry.summary, origin))),
        );
    }

    card(
        widget::Column::new()
            .spacing(12)
            .push(widget::text::title4("Récapitulatif"))
            .push(widget::text::body(format!(
                "Profil d'usage: {}. Ces applications vont être installées:",
                sel.profil.label()
            )))
            .push(list)
            .push(widget::text::caption(
                "Bottles est toujours installé: c'est lui qui fait tourner les \
                 applications Windows exigeantes. Une seule autorisation vous sera \
                 demandée pour l'ensemble. L'installation peut prendre plusieurs \
                 minutes; vous pouvez suivre le détail ci-dessous.",
            )),
    )
}

/// Page finale: le bilan de l'installation. Elle dit ce qui est installe, et
/// en cas d'erreur ce qui ne l'est pas, avec de quoi reessayer.
fn fin<'a>(app: &'a App, bilan: &'a assistant::Bilan) -> Element<'a, Message> {
    let idle = !app.op_running();
    // Rien d'installe du tout (autorisation refusee, pas de reseau...): ce
    // n'est pas une installation « avec des erreurs », elle n'a pas eu lieu.
    let partiel = !bilan.ok && !bilan.installees.is_empty();

    let header = widgets::header(
        "Assistant de configuration",
        if bilan.ok { "Terminé" } else { "Terminé, avec des erreurs" },
        vec![],
    );

    let (icone, titre) = if bilan.ok {
        // Noms Breeze MONOCHROMES en repli: une icone en couleur est teintee
        // d'un bloc et s'affiche en forme pleine.
        (
            crate::ui::icon("emblem-ok-symbolic", &["state-ok-symbolic", "object-select-symbolic"]),
            "Tout est installé !",
        )
    } else if partiel {
        (
            crate::ui::icon(
                "dialog-warning-symbolic",
                &["state-warning-symbolic", "messagebox_warning-symbolic"],
            ),
            "Installation terminée, avec des erreurs",
        )
    } else {
        (
            crate::ui::icon("dialog-error-symbolic", &["state-error-symbolic"]),
            "L'installation n'a pas abouti",
        )
    };

    let mut col = widget::Column::new().spacing(12).push(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(icone.size(32))
            .push(widget::text::title4(titre)),
    );

    if !bilan.installees.is_empty() {
        col = col.push(widget::text::heading(if bilan.ok {
            "Vos applications sont prêtes:"
        } else {
            "Installées:"
        }));
        col = col.push(liste(&bilan.installees));
    }
    if !bilan.echecs.is_empty() {
        col = col.push(widget::text::heading(if partiel {
            "Non installées:"
        } else {
            "Aucune application n'a été installée:"
        }));
        col = col.push(liste(&bilan.echecs));
    }
    if bilan.profil_echoue {
        col = col.push(widget::text::body(format!(
            "Le profil d'usage « {} » n'a pas pu être appliqué.",
            app.selection.profil.label()
        )));
    }

    if bilan.ok {
        col = col.push(widget::text::caption(
            "Elles sont dans le menu des applications. Pour en ajouter d'autres, \
             ouvrez la page Applications. L'assistant reste disponible ici à tout \
             moment.",
        ));
    } else {
        // La cause est ecrite ICI, et pas seulement dans le panneau
        // d'operation: celui-ci se ferme, la page finale reste.
        if !bilan.message.is_empty() {
            col = col
                .push(widget::text::heading("Cause signalée:"))
                .push(widget::text::monotext(bilan.message.clone()));
        }
        col = col.push(widget::text::caption(
            "« Réessayer » relance l'installation de votre sélection; vérifiez \
             d'abord la connexion Internet. Le journal complet est dans le panneau \
             ci-dessous (« Voir le détail »). Tant que l'installation n'a pas \
             réussi, l'assistant se rouvrira à la prochaine session.",
        ));
    }

    let mut nav = widget::Row::new().spacing(8).align_y(iced::Alignment::Center);
    nav = nav.push(widget::Space::new().width(iced::Length::Fill));
    if !bilan.ok {
        nav = nav.push(
            widget::button::standard("Réessayer")
                .on_press_maybe(idle.then_some(Message::AssistantInstall)),
        );
    }
    nav = nav.push(
        widget::button::suggested(if bilan.ok { "Terminer" } else { "Fermer l'assistant" })
            .on_press_maybe(idle.then_some(Message::AssistantFinish)),
    );

    widget::Column::new()
        .spacing(16)
        .push(header)
        .push(widget::scrollable(card(col)).height(iced::Length::Fill))
        .push(nav)
        .into()
}

fn liste<'a>(noms: &[&'static str]) -> Element<'a, Message> {
    let mut col = widget::Column::new().spacing(4).padding([0, 0, 0, 12]);
    for nom in noms {
        col = col.push(widget::text::body(format!("• {nom}")));
    }
    col.into()
}
