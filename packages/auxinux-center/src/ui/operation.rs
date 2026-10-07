//! Suivi d'une operation longue: etape, barre de progression, journal.
//!
//! Une seule operation privilegiee a la fois: apt verrouille dpkg, et une
//! seconde transaction lancee pendant la premiere echouait sur ce verrou avec
//! un message incomprehensible. Les boutons qui en lanceraient une autre sont
//! donc inactifs tant que celle-ci tourne (voir `App::op_running`).

use std::collections::VecDeque;

use cosmic::{iced, widget, Element};

use crate::model::ActionResult;
use crate::progress::{self, Parsed, Step};
use crate::ui::Message;

/// Lignes gardees en memoire. Une mise a jour complete en ecrit quelques
/// centaines; la borne protege seulement d'un programme anormalement bavard.
const LOG_LIMIT: usize = 5000;
/// Lignes affichees dans le detail. Le texte est remis en page a chaque ligne
/// recue: au-dela, l'affichage ralentirait. « Copier le journal » emporte tout.
const LOG_SHOWN: usize = 400;
/// Longueur maximale de la ligne « ce qui se passe »: une URL de depot entiere
/// ferait sauter la mise en page a chaque ligne.
const DETAIL_CHARS: usize = 140;

pub struct Operation {
    pub title: String,
    pub step: Step,
    pub log: VecDeque<String>,
    /// `None` tant que l'operation tourne.
    pub result: Option<ActionResult>,
    pub show_log: bool,
    /// Etape courante d'une operation en plusieurs etapes (assistant de
    /// premier demarrage): numero, total, libelle.
    stage: Option<(u32, u32, String)>,
}

impl Operation {
    pub fn new(title: impl Into<String>) -> Self {
        Operation {
            title: title.into(),
            step: Step::starting(),
            log: VecDeque::new(),
            result: None,
            show_log: false,
            stage: None,
        }
    }

    pub fn running(&self) -> bool {
        self.result.is_none()
    }

    /// Integre une ligne de sortie: les lignes d'avancement d'apt deplacent la
    /// barre, les autres vont au journal et deviennent le « ce qui se passe ».
    pub fn feed(&mut self, line: &str) {
        match progress::parse(line) {
            Parsed::Status {
                label,
                fraction,
                detail,
            } => {
                // Dans une operation en plusieurs etapes, la barre reste
                // GLOBALE: l'avancement d'apt n'est qu'une fraction de l'etape
                // en cours, sinon elle repartirait de zero a chaque etape.
                self.step = match &self.stage {
                    Some((index, total, name)) => Step {
                        label: format!("Étape {index} sur {total} — {name} — {label}"),
                        fraction: Some(((*index - 1) as f32 + fraction) / *total as f32),
                        detail: shorten(&detail),
                    },
                    None => Step {
                        label: label.to_string(),
                        fraction: Some(fraction),
                        detail: shorten(&detail),
                    },
                };
            }
            Parsed::Stage { index, total, label } => {
                self.step = Step {
                    label: format!("Étape {index} sur {total} — {label}"),
                    fraction: Some((index - 1) as f32 / total as f32),
                    detail: String::new(),
                };
                self.stage = Some((index, total, label.clone()));
                self.push_log(format!("== Étape {index} sur {total}: {label}"));
            }
            Parsed::Log(text) => {
                self.step.detail = shorten(&text);
                self.push_log(text);
            }
        }
    }

    fn push_log(&mut self, text: String) {
        if self.log.len() == LOG_LIMIT {
            self.log.pop_front();
        }
        self.log.push_back(text);
    }

    pub fn log_text(&self) -> String {
        self.log.iter().map(String::as_str).collect::<Vec<_>>().join("\n")
    }
}

fn shorten(text: &str) -> String {
    let text = text.trim();
    match text.char_indices().nth(DETAIL_CHARS) {
        Some((cut, _)) => format!("{}…", &text[..cut]),
        None => text.to_string(),
    }
}

pub fn view(op: &Operation) -> Element<'_, Message> {
    let (icon, headline) = match &op.result {
        None => (
            crate::ui::icon("content-loading-symbolic", &["process-working-symbolic"]),
            op.title.clone(),
        ),
        Some(r) if r.ok => (
            crate::ui::icon("emblem-ok-symbolic", &["object-select-symbolic"]),
            format!("{} — terminé", op.title),
        ),
        Some(_) => (
            crate::ui::icon("dialog-error-symbolic", &["dialog-error", "data-error"]),
            format!("{} — échec", op.title),
        ),
    };

    let mut actions = widget::Row::new().spacing(8).align_y(iced::Alignment::Center);
    if op.show_log {
        actions = actions
            .push(widget::button::text("Copier le journal").on_press(Message::CopyLog))
            .push(widget::button::text("Masquer le détail").on_press(Message::ToggleLog));
    } else {
        actions = actions.push(widget::button::text("Voir le détail").on_press(Message::ToggleLog));
    }
    if !op.running() {
        actions = actions.push(widget::button::text("Fermer").on_press(Message::DismissOperation));
    }

    let mut column = widget::Column::new().spacing(8).push(
        widget::Row::new()
            .spacing(10)
            .align_y(iced::Alignment::Center)
            .push(icon.size(16))
            .push(widget::text::heading(headline).width(iced::Length::Fill))
            .push(actions),
    );

    match &op.result {
        None => {
            let label = match op.step.fraction {
                Some(f) => format!("{} — {} %", op.step.label, (f * 100.0).round() as u32),
                None => op.step.label.clone(),
            };
            column = column.push(widget::text::caption(label));
            column = column.push(match op.step.fraction {
                Some(f) => Element::from(
                    widget::progress_bar::determinate_linear(f).width(iced::Length::Fill),
                ),
                None => Element::from(
                    widget::progress_bar::indeterminate_linear().width(iced::Length::Fill),
                ),
            });
            if !op.step.detail.is_empty() {
                column = column.push(widget::text::caption(op.step.detail.clone()));
            }
        }
        // Le message d'un echec, ce sont les dernieres lignes ecrites: c'est la
        // raison que l'utilisateur ne voyait jamais.
        Some(result) => column = column.push(widget::text::body(result.message.clone())),
    }

    if op.show_log {
        let skip = op.log.len().saturating_sub(LOG_SHOWN);
        let shown = op
            .log
            .iter()
            .skip(skip)
            .map(String::as_str)
            .collect::<Vec<_>>()
            .join("\n");
        let shown = if shown.is_empty() {
            "Aucune sortie pour le moment.".to_string()
        } else {
            shown
        };
        column = column.push(
            widget::container(
                widget::scrollable(widget::text::monotext(shown).width(iced::Length::Fill))
                    // Colle au bas tant que l'utilisateur ne remonte pas: on
                    // suit ce qui s'ecrit, comme dans un terminal.
                    .anchor_bottom()
                    .width(iced::Length::Fill),
            )
            .height(iced::Length::Fixed(220.0))
            .width(iced::Length::Fill),
        );
    }

    widget::container(column)
        .class(cosmic::theme::Container::Card)
        .padding(12)
        .width(iced::Length::Fill)
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_lines_move_the_bar_and_stay_out_of_the_log() {
        let mut op = Operation::new("Mise à jour du système");
        op.feed("Lecture des listes de paquets…");
        op.feed("dlstatus:2:50:Réception du fichier 2 sur 4");
        assert_eq!(op.step.fraction, Some(0.5));
        assert_eq!(op.step.label, "Téléchargement");
        assert_eq!(op.log.len(), 1);
        op.feed("Depaquetage de libssl3t64 (3.5.7-1~deb13u3) …");
        // Une ligne ordinaire change le detail, pas l'avancement.
        assert_eq!(op.step.fraction, Some(0.5));
        assert!(op.step.detail.starts_with("Depaquetage"));
        assert_eq!(op.log.len(), 2);
    }

    #[test]
    fn stages_keep_the_bar_global() {
        let mut op = Operation::new("Installation de vos applications");
        op.feed("auxinux-etape:2:4:Paquets système");
        assert_eq!(op.step.fraction, Some(0.25));
        op.feed("pmstatus:brave-browser:50:Configuration de brave-browser");
        // Moitie de l'etape 2 sur 4: 1,5 / 4.
        assert_eq!(op.step.fraction, Some(0.375));
        assert!(op.step.label.starts_with("Étape 2 sur 4"));
    }

    #[test]
    fn long_details_are_shortened_on_a_char_boundary() {
        let long = "é".repeat(DETAIL_CHARS + 10);
        let short = shorten(&long);
        assert_eq!(short.chars().count(), DETAIL_CHARS + 1);
        assert!(short.ends_with('…'));
    }
}
