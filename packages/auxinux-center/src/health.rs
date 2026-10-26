//! Section SANTE: un diagnostic lisible par un utilisateur non technique.
//!
//! Chaque controle produit un constat, une gravite et surtout un CONSEIL en
//! clair. Un centre de controle qui affiche "swap: 94%" sans dire quoi faire
//! ne sert qu'a ceux qui savaient deja.

use crate::model::{ActionResult, HealthCheck, HealthReport, IntegrityReport, Severity, SystemReport};
use crate::util::run;

/// Seuils d'occupation disque. Au-dela de 95%, APT et les instantanes
/// commencent reellement a echouer, d'ou le passage en critique.
const DISK_WARN: f32 = 0.85;
const DISK_CRIT: f32 = 0.95;
const MEM_WARN: f32 = 0.90;

fn check(id: &str, title: &str, detail: impl Into<String>, severity: Severity, advice: &str) -> HealthCheck {
    HealthCheck {
        id: id.into(),
        title: title.into(),
        detail: detail.into(),
        severity,
        advice: advice.into(),
    }
}

/// Rapport complet. `list_updates` interroge le reseau (Flathub + APT), donc
/// cet appel peut durer plusieurs secondes: il doit toujours etre lance depuis
/// une tache de fond, jamais depuis le fil de l'interface.
pub fn report() -> HealthReport {
    // Un SEUL releve systeme pour tout le rapport. `disk_checks` et
    // `memory_check` en declenchaient chacun un, soit deux inventaires
    // complets du materiel par analyse, pour des donnees identiques.
    let info = crate::system::info(false);
    let mut checks = Vec::new();
    checks.extend(disk_checks(&info));
    checks.push(memory_check(&info));
    checks.push(failed_services_check());
    checks.push(updates_check());
    checks.push(rollback_check());
    checks.push(boot_time_check());
    checks.push(apt_policy_check());
    HealthReport { checks }
}

fn disk_checks(info: &SystemReport) -> Vec<HealthCheck> {
    let mut out = Vec::new();
    for disk in &info.disks {
        // Les montages minuscules (ESP, tmpfs divers) polluent le diagnostic
        // sans rien apprendre a l'utilisateur.
        if disk.total_gb < 2 {
            continue;
        }
        let ratio = disk.used_ratio();
        let percent = (ratio * 100.0).round() as u32;
        let severity = if ratio >= DISK_CRIT {
            Severity::Critical
        } else if ratio >= DISK_WARN {
            Severity::Warning
        } else {
            Severity::Ok
        };
        let advice = match severity {
            Severity::Critical => {
                "Libérez de l'espace maintenant: videz le cache avec « auxi clean », \
                 supprimez des applications inutilisées, ou supprimez d'anciens instantanés."
            }
            Severity::Warning => {
                "Pensez à libérer de l'espace: « auxi clean » vide le cache des paquets."
            }
            Severity::Ok => "",
        };
        out.push(check(
            &format!("disk:{}", disk.mount),
            &format!("Espace disque — {}", disk.mount),
            format!(
                "{percent}% utilisé — {} Go libres sur {} Go",
                disk.available_gb, disk.total_gb
            ),
            severity,
            advice,
        ));
    }
    if out.is_empty() {
        out.push(check(
            "disk",
            "Espace disque",
            "aucun disque lisible",
            Severity::Warning,
            "Vérifiez les montages avec « findmnt ».",
        ));
    }
    out
}

fn memory_check(info: &SystemReport) -> HealthCheck {
    if info.memory_total_mb == 0 {
        return check("memory", "Mémoire", "indisponible", Severity::Ok, "");
    }
    let ratio = info.memory_used_mb as f32 / info.memory_total_mb as f32;
    let percent = (ratio * 100.0).round() as u32;
    let severity = if ratio >= MEM_WARN { Severity::Warning } else { Severity::Ok };
    check(
        "memory",
        "Mémoire vive",
        format!(
            "{percent}% utilisée — {} Mo sur {} Mo",
            info.memory_used_mb, info.memory_total_mb
        ),
        severity,
        if severity == Severity::Warning {
            "Fermez des applications, ou redémarrez si la mémoire ne se libère pas."
        } else {
            ""
        },
    )
}

fn failed_services_check() -> HealthCheck {
    let out = run("systemctl", &["--failed", "--no-legend", "--plain"]);
    if !out.ok {
        return check(
            "services",
            "Services système",
            "état indisponible",
            Severity::Ok,
            "",
        );
    }
    let failed: Vec<&str> = out
        .stdout
        .lines()
        .filter_map(|l| l.split_whitespace().next())
        .filter(|n| !n.is_empty())
        .collect();

    if failed.is_empty() {
        return check("services", "Services système", "tous les services fonctionnent", Severity::Ok, "");
    }
    check(
        "services",
        "Services système",
        format!("{} service(s) en échec: {}", failed.len(), failed.join(", ")),
        Severity::Warning,
        "Consultez le détail avec « systemctl status <service> ». Si la panne est \
         apparue après une mise à jour, la restauration peut l'annuler.",
    )
}

fn updates_check() -> HealthCheck {
    let updates = crate::apps::list_updates();
    if updates.is_empty() {
        return check("updates", "Mises à jour", "le système est à jour", Severity::Ok, "");
    }
    check(
        "updates",
        "Mises à jour",
        format!("{} mise(s) à jour disponible(s)", updates.len()),
        Severity::Warning,
        "Installez-les depuis l'onglet « Mises à jour ». Un instantané est créé \
         automatiquement avant, vous pourrez revenir en arrière.",
    )
}

fn rollback_check() -> HealthCheck {
    let state = crate::recovery::state();
    if !state.available {
        return check(
            "rollback",
            "Restauration système",
            format!("indisponible — {}", state.reason),
            Severity::Warning,
            "Sans instantanés, une mise à jour ratée ne peut pas être annulée. \
             La restauration exige une installation sur BTRFS.",
        );
    }
    if state.snapshots.is_empty() {
        return check(
            "rollback",
            "Restauration système",
            "active, mais aucun instantané enregistré",
            Severity::Warning,
            "Créez un premier point de restauration depuis l'onglet « Restauration ».",
        );
    }
    check(
        "rollback",
        "Restauration système",
        format!(
            "{} point(s) de restauration — le plus récent: {}",
            state.snapshots.len(),
            state.snapshots[0].date
        ),
        Severity::Ok,
        "",
    )
}

fn boot_time_check() -> HealthCheck {
    let out = run("systemd-analyze", &["time"]);
    if !out.ok || out.stdout.trim().is_empty() {
        return check("boot", "Temps de démarrage", "indisponible", Severity::Ok, "");
    }
    let line = out.stdout.lines().next().unwrap_or("").trim().to_string();
    check("boot", "Temps de démarrage", line, Severity::Ok, "")
}

fn apt_policy_check() -> HealthCheck {
    if crate::sources::apt_wrapper_enabled() {
        check(
            "apt-policy",
            "Politique APT",
            "APT direct est réactivé",
            Severity::Ok,
            "Les commandes apt fonctionnent normalement. « auxi » reste recommandé: \
             il crée un instantané avant chaque opération, ce que apt ne fait pas.",
        )
    } else {
        check(
            "apt-policy",
            "Politique APT",
            "APT direct est masqué, « auxi » prend le relais",
            Severity::Ok,
            "",
        )
    }
}

/// Verification d'integrite d'AuxiNux OS, a la demande (bouton « Vérifier
/// l'intégrité »).
///
/// DEMANDE A L'ORIGINE (2026-10-26, aporler): une machine installee depuis une
/// ISO ancienne puis mise a jour avait la fenetre de mot de passe absente, le
/// filigrane du bureau absent et AuxiFiles avec des rates, alors que cette
/// page disait « Tout va bien »: le Shell etait RETENU en 0.3.5 par la mise a
/// jour, et des paquets que seule l'ISO installe manquaient. Les controles
/// eux-memes sont dans `auxi check`, utilisable aussi en terminal.
///
/// Plusieurs secondes (dpkg --verify des paquets AuxiNux): tache de fond.
pub fn integrity() -> IntegrityReport {
    // Listes de paquets fraiches d'abord: sinon un paquet RETENU passe pour
    // a jour, et un paquet AuxiNux recent pour introuvable. L'action
    // d'actualisation ne demande pas de mot de passe a la session active: elle
    // marche meme quand l'agent d'autorisation est en panne. Un echec (hors
    // ligne) n'empeche pas la verification, faite alors sur les listes du jour.
    run("pkexec", &[crate::updates::REFRESH_HELPER]);
    let out = run("auxi", &["check", "--porcelain"]);
    let parsed = parse_integrity(&out.stdout);
    if parsed.report.checks.is_empty() {
        // auxi d'avant la 0.2.11, ou introuvable: pas de verification possible.
        return IntegrityReport {
            report: HealthReport {
                checks: vec![check(
                    "integrity",
                    "Vérification d'intégrité",
                    "indisponible avec cette version d'auxi",
                    Severity::Warning,
                    "Mettez le système à jour (onglet « Mises à jour »), puis relancez la vérification.",
                )],
            },
            repairable: false,
        };
    }
    parsed
}

/// Sortie de `auxi check --porcelain`:
/// `ETAT<tab>ID<tab>TITRE<tab>DETAIL<tab>CONSEIL`, puis `reparable<tab>oui|non`.
fn parse_integrity(stdout: &str) -> IntegrityReport {
    let mut checks = Vec::new();
    let mut repairable = false;
    for line in stdout.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.first() == Some(&"reparable") {
            repairable = fields.get(1) == Some(&"oui");
            continue;
        }
        if fields.len() < 4 {
            continue;
        }
        let severity = match fields[0] {
            "ok" => Severity::Ok,
            "attention" => Severity::Warning,
            "critique" => Severity::Critical,
            _ => continue,
        };
        checks.push(check(
            &format!("integrity:{}", fields[1]),
            fields[2],
            fields[3],
            severity,
            fields.get(4).copied().unwrap_or(""),
        ));
    }
    IntegrityReport { report: HealthReport { checks }, repairable }
}

/// Repare AuxiNux OS (`auxi repair`, instantane nomme d'abord), sous l'action
/// polkit des mises a jour.
pub fn repair(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    let result = crate::progress::privileged(
        &[crate::updates::UPDATE_HELPER, "repair"],
        on_line,
        "AuxiNux OS est réparé. Fermez la session puis rouvrez-la pour charger le Shell réparé.",
    );
    // Le message de refus generique nomme `sudo auxi os upgrade`; ici, c'est
    // la reparation qu'il faut lancer en terminal. C'est justement le cas
    // d'une machine dont l'agent d'autorisation est en panne.
    if !result.ok && result.message == crate::progress::AUTH_REFUSED {
        return ActionResult::err(REPAIR_AUTH_REFUSED);
    }
    result
}

pub const REPAIR_AUTH_REFUSED: &str = "Réparation annulée: l'autorisation administrateur n'a pas été donnée. \
     Rien n'a été modifié.\n\
     Si la fenêtre d'autorisation n'est pas apparue, c'est peut-être justement ce qu'il faut réparer: \
     ouvrez un terminal et tapez sudo auxi repair";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::HealthReport;

    #[test]
    fn overall_severity_is_the_worst_check() {
        let report = HealthReport {
            checks: vec![
                check("a", "A", "", Severity::Ok, ""),
                check("b", "B", "", Severity::Critical, ""),
                check("c", "C", "", Severity::Warning, ""),
            ],
        };
        assert_eq!(report.overall(), Severity::Critical);
        assert_eq!(report.count(Severity::Warning), 1);
        assert_eq!(report.count(Severity::Ok), 1);
    }

    #[test]
    fn empty_report_is_ok_not_a_panic() {
        let report = HealthReport { checks: vec![] };
        assert_eq!(report.overall(), Severity::Ok);
    }

    #[test]
    fn integrity_porcelain_is_parsed() {
        let out = "ok\tdpkg\tInstallation des paquets\taucune installation interrompue\t\n\
                   critique\tpaquets\tPaquets AuxiNux OS\tretenus: auxinux-shell 0.3.5 → 0.3.13\tLa réparation les installe.\n\
                   attention\tdependances\tDépendances du bureau\t1 absente(s): polkit-kde-agent-1\t\n\
                   reparable\toui\n";
        let parsed = parse_integrity(out);
        assert!(parsed.repairable);
        assert_eq!(parsed.report.checks.len(), 3);
        assert_eq!(parsed.report.overall(), Severity::Critical);
        assert_eq!(parsed.report.checks[1].id, "integrity:paquets");
        assert_eq!(parsed.report.checks[1].advice, "La réparation les installe.");
        assert_eq!(parsed.report.checks[2].advice, "");
    }

    #[test]
    fn integrity_nothing_to_repair() {
        let parsed = parse_integrity("ok\tapt\tDépendances\taucune\t\nreparable\tnon\n");
        assert!(!parsed.repairable);
        assert_eq!(parsed.report.overall(), Severity::Ok);
    }

    #[test]
    fn disk_ratio_handles_zero_sized_disk() {
        let d = crate::model::DiskInfo { mount: "/x".into(), total_gb: 0, available_gb: 0 };
        assert_eq!(d.used_ratio(), 0.0);
    }
}
