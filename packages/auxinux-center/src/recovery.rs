//! Section RESTAURATION: instantanes BTRFS et retour arriere.
//!
//! Le Center ne parle jamais directement a BTRFS. La lecture passe par
//! `snapper` (autorise au groupe sudo via ALLOW_GROUPS, donc sans invite), et
//! toute action passe par `pkexec auxi ...`, qui porte deja la logique sure de
//! l'echange de sous-volumes et sa reprise sur echec. Dupliquer cette logique
//! ici creerait deux chemins de restauration a maintenir en parallele -- le
//! genre de divergence qui ne se decouvre qu'au moment ou l'on en a besoin.

use crate::model::{ActionResult, RecoveryState, Snapshot};
use crate::util::{run, run_pkexec};

const SNAPPER_CONFIG: &str = "root";

/// Vrai si la racine est un BTRFS avec une configuration snapper "root".
fn configured() -> Result<(), String> {
    if !std::path::Path::new("/etc/snapper/configs/root").exists() {
        return Err("snapper n'est pas configure sur ce systeme".into());
    }
    let fs = run("findmnt", &["-no", "FSTYPE", "/"]);
    if fs.stdout.trim() != "btrfs" {
        return Err(format!(
            "la racine est en {} et non en BTRFS",
            if fs.stdout.trim().is_empty() { "systeme inconnu" } else { fs.stdout.trim() }
        ));
    }
    Ok(())
}

pub fn state() -> RecoveryState {
    if let Err(reason) = configured() {
        return RecoveryState { available: false, reason, snapshots: Vec::new() };
    }

    let out = run(
        "snapper",
        &["-c", SNAPPER_CONFIG, "--machine-readable", "csv", "list"],
    );
    if !out.ok {
        return RecoveryState {
            available: false,
            reason: "lecture des instantanes impossible (droits insuffisants ?)".into(),
            snapshots: Vec::new(),
        };
    }

    RecoveryState { available: true, reason: String::new(), snapshots: parse_csv(&out.stdout) }
}

/// Analyse la sortie CSV de snapper EN S'APPUYANT SUR L'EN-TETE, jamais sur
/// des positions de colonnes: leur ordre et leur nombre ont change entre les
/// versions de snapper, et un parseur positionnel afficherait des dates dans
/// la colonne des descriptions sans jamais echouer franchement.
fn parse_csv(text: &str) -> Vec<Snapshot> {
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let Some(header) = lines.next() else {
        return Vec::new();
    };
    let cols: Vec<&str> = header.split(',').map(|c| c.trim()).collect();
    let idx = |name: &str| cols.iter().position(|c| *c == name);

    let (i_num, i_type, i_date, i_desc, i_data) = (
        idx("number"),
        idx("type"),
        idx("date"),
        idx("description"),
        idx("userdata"),
    );
    let Some(i_num) = i_num else {
        return Vec::new();
    };

    let mut out = Vec::new();
    for line in lines {
        let f: Vec<&str> = line.split(',').collect();
        let get = |i: Option<usize>| {
            i.and_then(|i| f.get(i)).map(|s| s.trim().to_string()).unwrap_or_default()
        };
        let Some(number) = f.get(i_num).and_then(|n| n.trim().parse::<u32>().ok()) else {
            continue;
        };
        // L'instantane 0 est la racine courante de snapper, pas un point de
        // restauration: le proposer n'aurait aucun sens.
        if number == 0 {
            continue;
        }
        let userdata = get(i_data);
        out.push(Snapshot {
            number,
            kind: get(i_type),
            date: get(i_date),
            description: get(i_desc),
            from_auxi: userdata.contains("auxi=1"),
        });
    }
    out.sort_by(|a, b| b.number.cmp(&a.number));
    out
}

pub fn create_snapshot(description: &str) -> ActionResult {
    let desc = description.trim();
    // La description arrive en argv (aucune injection shell possible), mais
    // elle est reaffichee par snapper: on borne la longueur et on refuse les
    // caracteres de controle qui casseraient la sortie CSV relue ci-dessus.
    if desc.is_empty() || desc.len() > 200 || desc.chars().any(|c| c.is_control() || c == ',') {
        return ActionResult::err("description invalide (200 caracteres max, sans virgule)");
    }
    let out = run_pkexec(&["auxi", "snapshot", desc]);
    if out.ok {
        ActionResult::ok(format!("Instantane cree: {desc}"))
    } else {
        ActionResult::err(last_lines(&out.stderr))
    }
}

pub fn rollback(number: u32) -> ActionResult {
    let n = number.to_string();
    let out = run_pkexec(&["auxi", "rollback", &n, "--yes"]);
    if out.ok {
        ActionResult::ok(format!(
            "Restauration de l'instantane {number} prete. Redemarrez pour l'appliquer."
        ))
    } else {
        ActionResult::err(last_lines(&out.stderr))
    }
}

fn last_lines(s: &str) -> String {
    let lines: Vec<&str> = s.lines().filter(|l| !l.trim().is_empty()).collect();
    let start = lines.len().saturating_sub(6);
    let msg = lines[start..].join("\n");
    if msg.is_empty() {
        "Echec de l'operation".into()
    } else {
        msg
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn csv_parse_uses_header_names_not_positions() {
        // Ordre de colonnes deliberement different de celui de snapper 0.10.
        let csv = "config,subvolume,number,default,active,date,type,description,userdata\n\
                   root,/,0,yes,yes,,single,current,\n\
                   root,/,7,no,no,2026-09-03 10:15:00,pre,auxi install vlc,auxi=1\n\
                   root,/,8,no,no,2026-09-03 10:16:00,post,,auxi=1\n";
        let snaps = parse_csv(csv);
        assert_eq!(snaps.len(), 2, "l'instantane 0 doit etre ignore");
        // Tri decroissant: le plus recent en tete.
        assert_eq!(snaps[0].number, 8);
        assert_eq!(snaps[1].number, 7);
        assert_eq!(snaps[1].kind, "pre");
        assert_eq!(snaps[1].date, "2026-09-03 10:15:00");
        assert_eq!(snaps[1].description, "auxi install vlc");
        assert!(snaps[1].from_auxi);
    }

    #[test]
    fn csv_parse_survives_unknown_columns() {
        let csv = "number,type,date,description,userdata,used-space\n\
                   3,single,2026-09-01 08:00:00,Installation initiale,important=yes,1.2 GiB\n";
        let snaps = parse_csv(csv);
        assert_eq!(snaps.len(), 1);
        assert_eq!(snaps[0].description, "Installation initiale");
        assert!(!snaps[0].from_auxi);
    }

    #[test]
    fn csv_parse_empty_or_headerless_is_not_a_panic() {
        assert!(parse_csv("").is_empty());
        assert!(parse_csv("config,subvolume\nroot,/\n").is_empty());
    }

    #[test]
    fn snapshot_description_is_validated() {
        assert!(!create_snapshot("").ok);
        assert!(!create_snapshot("avec,virgule").ok);
        assert!(!create_snapshot(&"x".repeat(201)).ok);
    }
}
