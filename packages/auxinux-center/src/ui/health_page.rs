//! Page SANTE: diagnostic lisible, avec un conseil par probleme.
//!
//! Un centre de controle ne doit pas se contenter d'afficher des pourcentages.
//! Chaque constat en anomalie porte donc la phrase « voici quoi faire », en
//! francais courant.

use cosmic::{iced, widget, Element};

use crate::model::{HealthCheck, Severity};
use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Santé du système",
        "Diagnostic de l'espace disque, de la mémoire, des services et des sauvegardes",
        vec![widget::button::standard("Réanalyser")
            .on_press(Message::RefreshHealth)
            .into()],
    );

    let body: Element<Message> = match &app.health {
        Loading::Idle | Loading::Busy => widgets::busy("Analyse du système…"),
        Loading::Ready(report) => {
            let mut col = widget::Column::new().spacing(8).push(summary(report));
            for c in &report.checks {
                col = col.push(check_card(c));
            }
            if let Some(system) = app.system.ready() {
                col = col.push(hardware_card(system));
            }
            widget::scrollable(col).height(iced::Length::Fill).into()
        }
    };

    widget::Column::new().spacing(16).push(header).push(body).into()
}

fn summary(report: &crate::model::HealthReport) -> Element<'_, Message> {
    let critical = report.count(Severity::Critical);
    let warning = report.count(Severity::Warning);

    let (title, detail) = match report.overall() {
        Severity::Ok => (
            "Tout va bien".to_string(),
            "Aucun point d'attention détecté.".to_string(),
        ),
        Severity::Warning => (
            format!("{warning} point(s) d'attention"),
            "Rien d'urgent, mais ces points méritent un coup d'œil.".to_string(),
        ),
        Severity::Critical => (
            format!("{critical} problème(s) à traiter"),
            "Ces points peuvent empêcher le système de fonctionner correctement."
                .to_string(),
        ),
    };

    widget::container(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Center)
            .push(widget::icon::from_name(severity_icon(report.overall())).size(32))
            .push(
                widget::Column::new()
                    .spacing(2)
                    .push(widget::text::title4(title))
                    .push(widget::text::caption(detail)),
            ),
    )
    .class(super::apparence::carte())
    .padding(16)
    .width(iced::Length::Fill)
    .into()
}

fn check_card(c: &HealthCheck) -> Element<'_, Message> {
    let mut col = widget::Column::new()
        .spacing(4)
        .width(iced::Length::Fill)
        .push(widget::text::heading(c.title.clone()))
        .push(widget::text::body(c.detail.clone()));

    if !c.advice.is_empty() {
        col = col.push(widget::text::caption(c.advice.clone()));
    }

    widget::container(
        widget::Row::new()
            .spacing(12)
            .align_y(iced::Alignment::Start)
            .push(widget::icon::from_name(severity_icon(c.severity)).size(20))
            .push(col),
    )
    .class(super::apparence::carte())
    .padding(12)
    .width(iced::Length::Fill)
    .into()
}

fn hardware_card(system: &crate::model::SystemReport) -> Element<'_, Message> {
    let mut col = widget::Column::new()
        .spacing(4)
        .push(widget::text::heading("Matériel et session"))
        .push(widget::text::body(format!(
            "{} — noyau {}",
            system.os, system.kernel
        )))
        .push(widget::text::body(format!(
            "{} ({} cœurs)",
            system.cpu, system.cpu_cores
        )));

    if let Some(gpu) = &system.gpu {
        col = col.push(widget::text::body(format!("Graphique: {gpu}")));
    }
    if let (Some(desktop), Some(session)) = (&system.desktop, &system.session_type) {
        col = col.push(widget::text::caption(format!(
            "Bureau: {desktop} · session {session}"
        )));
    }
    if let Some(uptime) = system.uptime_min {
        col = col.push(widget::text::caption(format!(
            "Allumé depuis {} h {:02} min",
            uptime / 60,
            uptime % 60
        )));
    }

    widget::container(col)
        .class(super::apparence::carte())
        .padding(12)
        .width(iced::Length::Fill)
        .into()
}

/// Icones du theme plutot que des couleurs seules: un code uniquement
/// chromatique est illisible pour une partie des utilisateurs daltoniens.
fn severity_icon(severity: Severity) -> &'static str {
    match severity {
        Severity::Ok => "emblem-ok-symbolic",
        Severity::Warning => "dialog-warning-symbolic",
        Severity::Critical => "dialog-error-symbolic",
    }
}
