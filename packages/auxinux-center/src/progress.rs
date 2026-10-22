//! Avancement des operations longues: installation, desinstallation, mise a
//! jour.
//!
//! Jusqu'ici l'interface affichait « Operation en cours… » pendant plusieurs
//! minutes, puis « Echec de l'operation » sans la moindre raison: seule la
//! sortie d'erreur etait gardee, et apt ecrit sur la sortie STANDARD le message
//! qui explique son abandon. Desormais chaque ligne remonte a l'interface pendant
//! l'operation, apt y ajoute ses lignes d'avancement (`auxi --progress`), et un
//! echec rend les dernieres lignes ecrites, quel que soit le flux.
//!
//! Ce module reste hors de la feature `gui`: l'analyse des lignes est couverte
//! par `cargo test --no-default-features`.

use std::collections::VecDeque;

use crate::model::ActionResult;
use crate::util::{run_streaming, Output};

/// Lignes gardees pour expliquer un echec.
const RECENT_LINES: usize = 8;

/// Etape en cours, telle que l'interface l'affiche.
#[derive(Clone, Debug, PartialEq)]
pub struct Step {
    pub label: String,
    /// Avancement entre 0 et 1. `None` quand il n'est pas mesurable: Flatpak,
    /// resolution des dependances, creation du point de restauration.
    pub fraction: Option<f32>,
    /// Ce qui se passe precisement: « Configuration de libssl3t64 (amd64) »,
    /// ou la derniere ligne ecrite.
    pub detail: String,
}

impl Step {
    pub fn starting() -> Self {
        Step {
            label: "Démarrage…".into(),
            fraction: None,
            detail: String::new(),
        }
    }
}

/// Ce qu'une ligne de sortie apprend sur l'operation.
#[derive(Clone, Debug, PartialEq)]
pub enum Parsed {
    /// Ligne d'avancement d'apt (`APT::Status-Fd`). Elle ne va pas au journal:
    /// elle n'a de sens que pour la barre de progression.
    Status {
        label: &'static str,
        fraction: f32,
        detail: String,
    },
    /// Debut d'une etape de l'assistant de premier demarrage
    /// (`auxinux-etape:N:TOTAL:LIBELLE`, ecrit par auxinux-assistant-apply).
    Stage {
        index: u32,
        total: u32,
        label: String,
    },
    /// Ligne ordinaire, a garder dans le journal.
    Log(String),
}

/// Interprete une ligne de sortie de `auxi --progress`.
///
/// Formats d'apt (voir apt-get(8), APT::Status-Fd):
///   dlstatus:NUMERO:POURCENT:DESCRIPTION
///   pmstatus:PAQUET:POURCENT:DESCRIPTION
///   pmerror:PAQUET:POURCENT:MESSAGE
///   pmconffile:FICHIER:POURCENT:...
/// PAQUET peut lui-meme contenir « : » (libc6:i386), et la description aussi:
/// le pourcentage est donc le premier champ numerique, pas le troisieme.
pub fn parse(line: &str) -> Parsed {
    let fields: Vec<&str> = line.split(':').collect();
    match fields[0] {
        "dlstatus" if fields.len() >= 4 => {
            if let Ok(percent) = fields[2].trim().parse::<f32>() {
                return Parsed::Status {
                    label: "Téléchargement",
                    fraction: (percent / 100.0).clamp(0.0, 1.0),
                    detail: fields[3..].join(":").trim().to_string(),
                };
            }
        }
        "pmstatus" | "pmerror" if fields.len() >= 4 => {
            if let Some(i) = (2..fields.len() - 1).find(|&i| fields[i].trim().parse::<f32>().is_ok()) {
                let package = fields[1..i].join(":");
                let message = fields[i + 1..].join(":").trim().to_string();
                if fields[0] == "pmerror" {
                    return Parsed::Log(format!("Erreur — {package}: {message}"));
                }
                let percent: f32 = fields[i].trim().parse().unwrap_or(0.0);
                return Parsed::Status {
                    label: "Application des modifications",
                    fraction: (percent / 100.0).clamp(0.0, 1.0),
                    detail: message,
                };
            }
        }
        // Copie des fichiers par l'installateur (rsync --info=progress2).
        "auxinux-progression" if fields.len() >= 2 => {
            if let Ok(percent) = fields[1].trim().parse::<f32>() {
                return Parsed::Status {
                    label: "Copie des fichiers",
                    fraction: (percent / 100.0).clamp(0.0, 1.0),
                    detail: String::new(),
                };
            }
        }
        "auxinux-etape" if fields.len() >= 4 => {
            if let (Ok(index), Ok(total)) = (fields[1].parse::<u32>(), fields[2].parse::<u32>()) {
                if index >= 1 && index <= total {
                    return Parsed::Stage {
                        index,
                        total,
                        label: fields[3..].join(":").trim().to_string(),
                    };
                }
            }
        }
        _ => {}
    }
    Parsed::Log(line.to_string())
}

/// Lance `auxi` en root par pkexec, sans aucune question (`--yes`) et avec
/// l'avancement d'apt (`--progress`). Chaque ligne est transmise a `on_line`.
///
/// `--yes` est indispensable: sans terminal, apt-get repondait « Abandon. » a
/// sa propre question et toute mise a jour du systeme echouait.
pub fn auxi(args: &[&str], on_line: &mut dyn FnMut(&str), success: &str) -> ActionResult {
    let mut full = vec!["auxi", "--yes", "--progress"];
    full.extend_from_slice(args);
    let (out, recent) = run_tracked("pkexec", &full, on_line);
    conclude(&out, &recent, true, success)
}

/// Lance un programme privilegie quelconque par pkexec (`args[0]` = chemin du
/// programme). Utilise par l'assistant de premier demarrage.
pub fn privileged(args: &[&str], on_line: &mut dyn FnMut(&str), success: &str) -> ActionResult {
    let (out, recent) = run_tracked("pkexec", args, on_line);
    conclude(&out, &recent, true, success)
}

/// Lance une commande avec les droits de l'utilisateur (flatpak).
pub fn user(cmd: &str, args: &[&str], on_line: &mut dyn FnMut(&str), success: &str) -> ActionResult {
    let (out, recent) = run_tracked(cmd, args, on_line);
    conclude(&out, &recent, false, success)
}

/// `run_streaming`, en gardant les dernieres lignes ordinaires pour expliquer
/// un eventuel echec.
fn run_tracked(cmd: &str, args: &[&str], on_line: &mut dyn FnMut(&str)) -> (Output, Vec<String>) {
    let mut recent: VecDeque<String> = VecDeque::with_capacity(RECENT_LINES);
    let out = run_streaming(cmd, args, &mut |line| {
        if let Parsed::Log(text) = parse(line) {
            if !text.trim().is_empty() {
                if recent.len() == RECENT_LINES {
                    recent.pop_front();
                }
                recent.push_back(text);
            }
        }
        on_line(line);
    });
    (out, recent.into())
}

/// Message d'un refus d'autorisation par pkexec.
///
/// Le meme refus arrive quand l'agent d'autorisation du bureau plante au lieu
/// de repondre: AuxiNux Shell 0.1.2 se terminait en SEGV des que le mot de
/// passe etait valide (reproduit en VM le 2026-10-22). Le Center ne pouvait
/// alors plus rien mettre a jour, pas meme le Shell fautif; le terminal, qui
/// passe par sudo et non par polkit, reste la seule issue: on la nomme.
pub const AUTH_REFUSED: &str = "Opération annulée: l'autorisation administrateur n'a pas été donnée. \
     Rien n'a été modifié.\n\
     Si la fenêtre d'autorisation n'est pas apparue, ou a disparu après le mot de passe, \
     faites la mise à jour dans un terminal: sudo auxi os upgrade";

/// Resultat affiche a l'utilisateur.
pub fn conclude(out: &Output, recent: &[String], via_pkexec: bool, success: &str) -> ActionResult {
    if out.ok {
        return ActionResult::ok(success);
    }
    // pkexec: 126 = la fenetre d'authentification a ete fermee ou le mot de
    // passe refuse. Rien n'a ete lance; le dire evite de chercher une panne.
    // 127 + « Not authorized »: l'invite a ete fermee ou a echoue. pkexec
    // l'ecrit en anglais, brut; c'est ce qu'affichait la page Mises a jour
    // (constate en VM le 2026-10-09 en cliquant « Annuler »).
    if via_pkexec
        && (out.code == Some(126)
            || (out.code == Some(127) && out.stderr.contains("Not authorized")))
    {
        return ActionResult::err(AUTH_REFUSED);
    }
    if recent.is_empty() {
        return ActionResult::err(match out.code {
            Some(code) => format!("Échec de l'opération (code {code}), sans message."),
            None => "Échec de l'opération: le programme s'est arrêté sans message.".to_string(),
        });
    }
    ActionResult::err(recent.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn status(line: &str) -> (&'static str, f32, String) {
        match parse(line) {
            Parsed::Status { label, fraction, detail } => (label, fraction, detail),
            other => panic!("ligne d'avancement attendue: {other:?}"),
        }
    }

    #[test]
    fn download_status() {
        let (label, fraction, detail) = status("dlstatus:3:42.5000:Retrieving file 3 of 28");
        assert_eq!(label, "Téléchargement");
        assert!((fraction - 0.425).abs() < 1e-6);
        assert_eq!(detail, "Retrieving file 3 of 28");
    }

    #[test]
    fn package_status_with_architecture_and_colon_in_message() {
        let (label, fraction, detail) =
            status("pmstatus:libc6:i386:57.1429:Configuration de libc6:i386 (i386)");
        assert_eq!(label, "Application des modifications");
        assert!((fraction - 0.571429).abs() < 1e-4);
        assert_eq!(detail, "Configuration de libc6:i386 (i386)");
    }

    #[test]
    fn package_error_goes_to_the_log() {
        assert_eq!(
            parse("pmerror:foo:12.5:le sous-processus a renvoye un code d'erreur 1"),
            Parsed::Log("Erreur — foo: le sous-processus a renvoye un code d'erreur 1".into())
        );
    }

    #[test]
    fn ordinary_lines_are_kept_verbatim() {
        for line in [
            "Reception de :1 http://deb.debian.org/debian trixie/main amd64 libssl3t64 [2 345 kB]",
            "AuxiNuxOS: instantané de sécurité 12 créé avant cette opération.",
            "dlstatus:pas un nombre",
            "pmstatus:",
        ] {
            assert_eq!(parse(line), Parsed::Log(line.into()));
        }
    }

    /// Lignes REELLES d'apt 3.0 (Debian 13), relevees le 2026-10-02 en faisant
    /// tourner `auxi --yes --progress upgrade` sur un vrai apt/dpkg. Les tests
    /// ci-dessus sont ecrits d'apres la documentation; celui-ci garde le format
    /// effectivement produit.
    #[test]
    fn real_apt_output() {
        let (label, fraction, detail) = status("dlstatus:2:49.9995:Retrieving file 2 of 2");
        assert_eq!(label, "Téléchargement");
        assert!((fraction - 0.499995).abs() < 1e-5);
        assert_eq!(detail, "Retrieving file 2 of 2");

        let (label, fraction, detail) = status("pmstatus:essai-a:11.1111:Unpacking essai-a (amd64)");
        assert_eq!(label, "Application des modifications");
        assert!((fraction - 0.111111).abs() < 1e-5);
        assert_eq!(detail, "Unpacking essai-a (amd64)");

        assert_eq!(status("pmstatus:dpkg-exec:44.4444:Running dpkg").2, "Running dpkg");

        assert_eq!(
            parse("pmerror:essai-b:60.0000:installed essai-b package post-installation script subprocess returned error exit status 1"),
            Parsed::Log(
                "Erreur — essai-b: installed essai-b package post-installation script subprocess returned error exit status 1"
                    .into()
            )
        );

        // Fichier de configuration modifie par l'utilisateur: dpkg l'annonce,
        // garde l'ancien (--force-confold), et la ligne reste au journal.
        let conffile = "pmconffile:/etc/essai-a.conf:66.6667:'/etc/essai-a.conf' '/etc/essai-a.conf.dpkg-new' 1 1 ";
        assert_eq!(parse(conffile), Parsed::Log(conffile.into()));
    }

    #[test]
    fn assistant_stage_lines() {
        assert_eq!(
            parse("auxinux-etape:2:7:Installation de org.mozilla.firefox"),
            Parsed::Stage { index: 2, total: 7, label: "Installation de org.mozilla.firefox".into() }
        );
        // Incoherente: reste une ligne de journal plutot qu'une barre fausse.
        assert!(matches!(parse("auxinux-etape:9:7:x"), Parsed::Log(_)));
        assert!(matches!(parse("auxinux-etape:a:7:x"), Parsed::Log(_)));
    }

    #[test]
    fn installer_copy_progress() {
        let (label, fraction, _) = status("auxinux-progression:42");
        assert_eq!(label, "Copie des fichiers");
        assert!((fraction - 0.42).abs() < 1e-6);
    }

    #[test]
    fn fraction_is_clamped() {
        assert_eq!(status("dlstatus:1:180:x").1, 1.0);
    }

    fn output(ok: bool, code: Option<i32>) -> Output {
        Output {
            ok,
            code,
            stdout: String::new(),
            stderr: String::new(),
        }
    }

    #[test]
    fn failure_shows_the_last_lines_whatever_the_stream() {
        // Le cas qui a declenche ce module: « Abandon. » arrive sur la sortie
        // STANDARD, la sortie d'erreur est vide.
        let r = conclude(
            &output(false, Some(1)),
            &["Souhaitez-vous continuer ? [O/n] Abandon.".into()],
            true,
            "ok",
        );
        assert!(!r.ok);
        assert!(r.message.contains("Abandon."));
    }

    #[test]
    fn dismissed_authorization_is_named() {
        let r = conclude(&output(false, Some(126)), &[], true, "ok");
        assert!(r.message.contains("autorisation"));
        // Hors pkexec, 126 n'a pas ce sens.
        let r = conclude(&output(false, Some(126)), &[], false, "ok");
        assert!(r.message.contains("code 126"));
    }

    #[test]
    fn refused_authorization_is_named_too() {
        // Ce que pkexec rend quand l'invite est fermee (VM, 2026-10-09).
        let mut out = output(false, Some(127));
        out.stderr = "Error executing command as another user: Not authorized\n\
                      This incident has been reported.\n"
            .to_string();
        let r = conclude(&out, &["Error executing command as another user: Not authorized".into()], true, "ok");
        assert!(r.message.contains("autorisation"), "{}", r.message);
        // Agent d'autorisation plante (Shell 0.1.2): la voie du terminal est nommee.
        assert!(r.message.contains("sudo auxi os upgrade"), "{}", r.message);
        // 127 sans ce message: un vrai echec, montre tel quel.
        let r = conclude(&output(false, Some(127)), &["E: autre".into()], true, "ok");
        assert_eq!(r.message, "E: autre");
    }

    #[test]
    fn tracked_run_keeps_only_ordinary_lines() {
        let mut seen = 0;
        let (out, recent) = run_tracked(
            "sh",
            &["-c", "echo 'dlstatus:1:50:x'; echo une; echo deux >&2; exit 1"],
            &mut |_| seen += 1,
        );
        assert!(!out.ok);
        assert_eq!(seen, 3);
        let mut recent = recent;
        recent.sort();
        assert_eq!(recent, vec!["deux".to_string(), "une".to_string()]);
    }
}
