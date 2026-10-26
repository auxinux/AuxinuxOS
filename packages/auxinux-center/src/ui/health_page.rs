//! Page SANTE: diagnostic lisible, avec un conseil par probleme.
//!
//! Un centre de controle ne doit pas se contenter d'afficher des pourcentages.
//! Chaque constat en anomalie porte donc la phrase « voici quoi faire », en
//! francais courant.

use cosmic::{iced, widget, Element};

use crate::model::{HealthCheck, IntegrityReport, Severity};
use crate::ui::{widgets, App, Loading, Message};

pub fn view(app: &App) -> Element<'_, Message> {
    let header = widgets::header(
        "Santé du système",
        "Diagnostic de l'espace disque, de la mémoire, des services et des sauvegardes",
        vec![
            widget::button::standard("Vérifier l'intégrité")
                .on_press_maybe(
                    (!matches!(app.integrity, Loading::Busy)).then_some(Message::CheckIntegrity),
                )
                .into(),
            widget::button::standard("Réanalyser")
                .on_press(Message::RefreshHealth)
                .into(),
        ],
    );

    let body: Element<Message> = match &app.health {
        Loading::Idle | Loading::Busy => widgets::busy("Analyse du système…"),
        Loading::Ready(report) => {
            let mut col = widget::Column::new()
                .spacing(8)
                .push(summary(report))
                .push(integrity_section(app));
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

/// Integrite d'AuxiNux OS (`auxi check`): le Shell, les commandes et
/// applications AuxiNux, leurs dependances et leurs fichiers. A la demande:
/// le diagnostic courant ne voit pas un Shell RETENU par la mise a jour.
fn integrity_section(app: &App) -> Element<'_, Message> {
    let report = match &app.integrity {
        Loading::Idle => {
            return widget::container(
                widget::Row::new()
                    .spacing(12)
                    .align_y(iced::Alignment::Center)
                    .push(widget::icon::from_name("system-search-symbolic").size(20))
                    .push(
                        widget::Column::new()
                            .spacing(2)
                            .width(iced::Length::Fill)
                            .push(widget::text::heading("Intégrité d'AuxiNux OS"))
                            .push(widget::text::caption(
                                "Vérifie AuxiNux Shell, les commandes et applications AuxiNux, \
                                 leurs dépendances et leurs fichiers. Utile si quelque chose \
                                 fonctionne mal après une mise à jour, même quand tout semble aller.",
                            )),
                    )
                    .push(
                        widget::button::standard("Vérifier").on_press(Message::CheckIntegrity),
                    ),
            )
            .class(super::apparence::carte())
            .padding(12)
            .width(iced::Length::Fill)
            .into();
        }
        Loading::Busy => return widgets::busy("Actualisation des listes et vérification de l'intégrité d'AuxiNux OS…"),
        Loading::Ready(report) => report,
    };

    let mut col = widget::Column::new()
        .spacing(8)
        .push(integrity_summary(app, report));
    for c in &report.report.checks {
        col = col.push(check_card(c));
    }
    col.into()
}

fn integrity_summary<'a>(app: &App, integrity: &'a IntegrityReport) -> Element<'a, Message> {
    let report = &integrity.report;
    let overall = report.overall();
    let (title, detail) = if integrity.repairable {
        (
            "Intégrité d'AuxiNux OS: réparation possible",
            "Un instantané est créé avant: la restauration peut annuler la réparation. \
             Si la fenêtre de mot de passe ne s'affiche pas, ouvrez un terminal et \
             tapez « sudo auxi repair ».",
        )
    } else if overall == Severity::Ok {
        ("Intégrité d'AuxiNux OS: tout est en place", "")
    } else {
        (
            "Intégrité d'AuxiNux OS: rien à réparer automatiquement",
            "Suivez le conseil de chaque point ci-dessous.",
        )
    };

    let mut text = widget::Column::new()
        .spacing(2)
        .width(iced::Length::Fill)
        .push(widget::text::heading(title));
    if !detail.is_empty() {
        text = text.push(widget::text::caption(detail));
    }
    let mut row = widget::Row::new()
        .spacing(12)
        .align_y(iced::Alignment::Center)
        .push(widget::icon::from_name(severity_icon(overall)).size(24))
        .push(text);
    if integrity.repairable {
        row = row.push(
            widget::button::suggested("Réparer")
                .on_press_maybe((!app.op_running()).then_some(Message::RepairSystem)),
        );
    }

    widget::container(row)
        .class(super::apparence::carte())
        .padding(12)
        .width(iced::Length::Fill)
        .into()
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
