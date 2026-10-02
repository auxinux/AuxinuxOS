//! Page ASSISTANT: le choix des applications au premier demarrage.
//!
//! Sept etapes, une question par ecran: bienvenue, navigateur, LibreOffice,
//! lecteur multimedia, profil d'usage (avec ses applications suggerees), vie
//! privee, recapitulatif. Rien n'est installe avant le dernier ecran, et le
//! recapitulatif montre exactement ce qui le sera. Le catalogue et le calcul de
//! la selection vivent dans assistant.rs, hors de l'interface.

use cosmic::{iced, widget, Element};

use crate::assistant::{self, App as Entry, Profil, LECTEURS, NAVIGATEURS, VIE_PRIVEE};
use crate::ui::{widgets, App, Message};

pub const STEPS: usize = 7;
/// Valeur de bouton radio pour « aucun ».
const AUCUN: usize = usize::MAX;

pub fn view(app: &App) -> Element<'_, Message> {
    let sel = &app.selection;
    let step = app.assistant_step.min(STEPS - 1);

    let header = widgets::header(
        "Assistant de configuration",
        format!("Etape {} sur {}", step + 1, STEPS),
        vec![],
    );

    let body: Element<Message> = match step {
        0 => intro(),
        1 => question(
            "Quel navigateur voulez-vous ?",
            "Un seul sera installe. Vous pourrez en ajouter d'autres plus tard \
             depuis la page Applications.",
            radios(&NAVIGATEURS, sel.navigateur, Message::AssistantBrowser, "Aucun pour l'instant"),
        ),
        2 => question(
            "Voulez-vous LibreOffice ?",
            "Traitement de texte, tableur et presentations, compatibles avec les \
             documents Microsoft Office.",
            widget::Column::new()
                .spacing(8)
                .push(radio_yes_no(sel.libreoffice))
                .into(),
        ),
        3 => question(
            "Quel lecteur multimedia voulez-vous ?",
            "Pour vos videos et votre musique. Les codecs sont deja installes: \
             tout lecteur saura lire les formats courants.",
            radios(&LECTEURS, sel.lecteur, Message::AssistantPlayer, "Aucun"),
        ),
        4 => profil(sel),
        5 => question(
            "Outils de vie privee",
            "Proposes par AuxiNux, coches d'avance. Decochez ceux dont vous ne \
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
            widget::button::standard("Precedent")
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
            widget::button::suggested("Installer")
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
        .class(cosmic::theme::Container::Card)
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
                "Votre systeme est installe avec le strict necessaire: le bureau KDE \
                 Plasma, ses outils de base, et de quoi faire tourner les \
                 applications Windows (Wine et Bottles).",
            ))
            .push(widget::text::body(
                "Aucune autre application n'a ete choisie a votre place. Cet \
                 assistant vous demande ce que vous voulez: navigateur, \
                 bureautique, lecteur multimedia, et des applications selon \
                 l'usage que vous faites de votre ordinateur.",
            ))
            .push(widget::text::caption(
                "Rien n'est installe avant le dernier ecran, qui recapitule vos \
                 choix. Une connexion Internet est necessaire. Vous pourrez \
                 relancer cet assistant a tout moment depuis le centre de \
                 controle, dans Reglages.",
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

fn radio_yes_no<'a>(yes: bool) -> Element<'a, Message> {
    let selected = Some(yes);
    widget::Column::new()
        .spacing(10)
        .push(widget::radio(widget::text::body("Oui, installer LibreOffice"), true, selected, Message::AssistantLibreOffice))
        .push(widget::radio(widget::text::body("Non merci"), false, selected, Message::AssistantLibreOffice))
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
            .push(widget::text::title4("A quoi servira surtout cet ordinateur ?"))
            .push(widget::text::body(
                "Le profil regle le systeme pour cet usage, et propose des \
                 applications. Il se change ensuite dans Reglages.",
            ))
            .push(profiles)
            .push(widget::text::caption(effect))
            .push(widget::text::heading("Applications suggerees"))
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
            assistant::Source::Brave => "Depot officiel de Brave",
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
            .push(widget::text::title4("Recapitulatif"))
            .push(widget::text::body(format!(
                "Profil d'usage: {}. Ces applications vont etre installees:",
                sel.profil.label()
            )))
            .push(list)
            .push(widget::text::caption(
                "Bottles est toujours installe: c'est lui qui fait tourner les \
                 applications Windows exigeantes. Une seule autorisation vous sera \
                 demandee pour l'ensemble. L'installation peut prendre plusieurs \
                 minutes; vous pouvez suivre le detail ci-dessous.",
            )),
    )
}
