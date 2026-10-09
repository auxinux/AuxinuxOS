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

/// Couche basse de la racine quand on a demarre sur un instantane depuis GRUB
/// (hook initramfs auxinux-snapshot-overlay): c'est la qu'est le vrai BTRFS.
const SNAPSHOT_OVERLAY_LOWER: &str = "/run/auxinux-snapshot/lower";

/// Numero de l'instantane demarre depuis le sous-menu GRUB, lu sur la ligne de
/// commande du noyau (`auxinux.snapshot=1` et `...@snapshots/N/snapshot...`).
///
/// Sans cette detection, la page affichait « la racine est en overlay et non
/// en BTRFS » puis parlait d'une installation ext4 -- faux, et inquietant au
/// moment precis ou l'on depanne sa machine (constate le 2026-10-04).
pub fn snapshot_boot(cmdline: &str) -> Option<u32> {
    if !cmdline.split_whitespace().any(|w| w == "auxinux.snapshot=1") {
        return None;
    }
    for marker in ["@snapshots/", ".snapshots/"] {
        let mut rest = cmdline;
        while let Some(i) = rest.find(marker) {
            rest = &rest[i + marker.len()..];
            let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if !digits.is_empty() && rest[digits.len()..].starts_with("/snapshot") {
                return digits.parse().ok();
            }
        }
    }
    None
}

fn snapshot_boot_now() -> Option<u32> {
    snapshot_boot(&std::fs::read_to_string("/proc/cmdline").unwrap_or_default())
}

/// Vrai si la racine est un BTRFS avec une configuration snapper "root".
fn configured() -> Result<(), String> {
    if !std::path::Path::new("/etc/snapper/configs/root").exists() {
        return Err("snapper n'est pas configuré sur ce système".into());
    }
    let racine = if snapshot_boot_now().is_some() { SNAPSHOT_OVERLAY_LOWER } else { "/" };
    let fs = run("findmnt", &["-no", "FSTYPE", racine]);
    if fs.stdout.trim() != "btrfs" {
        return Err(format!(
            "la racine est en {} et non en BTRFS",
            if fs.stdout.trim().is_empty() { "système inconnu" } else { fs.stdout.trim() }
        ));
    }
    Ok(())
}

pub fn state() -> RecoveryState {
    if let Err(reason) = configured() {
        return RecoveryState { available: false, reason, snapshots: Vec::new(), demarre_sur: None };
    }

    let out = run(
        "snapper",
        &["-c", SNAPPER_CONFIG, "--machine-readable", "csv", "list"],
    );
    if !out.ok {
        return RecoveryState {
            available: false,
            reason: "lecture des instantanés impossible (droits insuffisants ?)".into(),
            snapshots: Vec::new(),
            demarre_sur: snapshot_boot_now(),
        };
    }

    RecoveryState {
        available: true,
        reason: String::new(),
        snapshots: parse_csv(&out.stdout),
        demarre_sur: snapshot_boot_now(),
    }
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

    let (i_num, i_type, i_date, i_desc, i_data, i_cleanup) = (
        idx("number"),
        idx("type"),
        idx("date"),
        idx("description"),
        idx("userdata"),
        idx("cleanup"),
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
            cleanup: get(i_cleanup),
        });
    }
    out.sort_by(|a, b| b.number.cmp(&a.number));
    out
}

// ---------------------------------------------------------------------------
// Presentation: des points de restauration lisibles
// ---------------------------------------------------------------------------

/// D'ou vient un point de restauration.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origine {
    /// L'etat de sortie d'usine, pose par l'installation.
    Installation,
    /// Pose avant une transaction de paquets (hook dpkg).
    AvantModification,
    /// La sauvegarde automatique quotidienne de snapper.
    Quotidien,
    /// Cree par la personne, depuis le centre ou `auxi snapshot`.
    Manuel,
}

/// Un point de restauration tel que la page le montre.
#[derive(Clone, Debug, PartialEq)]
pub struct Point {
    pub number: u32,
    pub titre: String,
    /// Date lisible, en francais.
    pub date: String,
    pub origine: Origine,
}

/// Les points a proposer, du plus recent au plus ancien.
///
/// La liste brute de snapper en comptait une trentaine sur une machine
/// ordinaire: deux instantanes par transaction de paquets (avant et apres),
/// un par heure, un par demarrage. Illisible, et inquietant pour qui ne sait
/// pas lequel choisir (constat d'aporler, 2026-10-04). On ne garde que ce qui
/// a un sens pour revenir en arriere:
///   - l'instantane « post » est ecarte: on revient a l'etat d'AVANT une
///     modification, celui d'apres est l'etat qui pose probleme;
///   - les instantanes de demarrage (« boot ») sont ecartes: ils ne sont plus
///     crees, et ceux des anciennes installations doublonnent les sauvegardes
///     quotidiennes;
///   - une seule sauvegarde automatique par jour, la plus recente.
///
/// Tous restent accessibles depuis le sous-menu de restauration de GRUB.
pub fn points(snapshots: &[Snapshot]) -> Vec<Point> {
    let mut sorted: Vec<&Snapshot> = snapshots.iter().collect();
    sorted.sort_by(|a, b| b.number.cmp(&a.number));
    let mut days_seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for s in sorted {
        if s.kind == "post" || s.description == "boot" {
            continue;
        }
        let origine = origine(s);
        if origine == Origine::Quotidien {
            let day = s.date.split_whitespace().next().unwrap_or("").to_string();
            if !days_seen.insert(day) {
                continue;
            }
        }
        out.push(Point {
            number: s.number,
            titre: titre(s, origine),
            date: date_lisible(&s.date),
            origine,
        });
    }
    out
}

fn origine(s: &Snapshot) -> Origine {
    if s.description.starts_with("Installation initiale") {
        Origine::Installation
    } else if s.kind == "pre" || s.description.starts_with("Avant AuxiNux OS") {
        // « Avant AuxiNux OS 0.2.1, édition du … »: pose par `auxi os upgrade`
        // avant une montee de version (type single, mais automatique).
        // Le type, et non la marque auxi=1: `auxi snapshot` -- donc le bouton
        // « Creer » du centre -- pose aussi cette marque sur les points faits
        // a la main, qui s'affichaient alors « Avant une modification ».
        Origine::AvantModification
    } else if s.cleanup == "timeline" || s.description == "timeline" {
        Origine::Quotidien
    } else {
        Origine::Manuel
    }
}

fn titre(s: &Snapshot, origine: Origine) -> String {
    match origine {
        Origine::Installation => "État d'origine (installation du système)".into(),
        Origine::Quotidien => "Sauvegarde automatique du jour".into(),
        Origine::Manuel if s.description.is_empty() => format!("Point de restauration {}", s.number),
        Origine::Manuel => s.description.clone(),
        Origine::AvantModification if s.description.starts_with("Avant AuxiNux OS") => {
            s.description.clone()
        }
        Origine::AvantModification => avant(&s.description),
    }
}

/// « Avant ... » a partir de la commande qui a declenche la transaction
/// (`/usr/bin/apt-get -y install vlc`, `apt upgrade`, `auxi install ...`).
fn avant(commande: &str) -> String {
    let mots: Vec<&str> = commande.split_whitespace().collect();
    let verbe = mots.iter().position(|m| {
        matches!(
            *m,
            "install" | "reinstall" | "remove" | "purge" | "autoremove" | "upgrade"
                | "dist-upgrade" | "full-upgrade"
        )
    });
    let Some(i) = verbe else {
        return "Avant une modification des logiciels".into();
    };
    let paquets: Vec<&str> = mots[i + 1..]
        .iter()
        .copied()
        .filter(|m| !m.starts_with('-') && !m.contains('='))
        .take(3)
        .collect();
    let liste = if paquets.is_empty() {
        String::new()
    } else {
        let plus = mots[i + 1..].iter().filter(|m| !m.starts_with('-')).count() > paquets.len();
        format!(" de {}{}", paquets.join(", "), if plus { "…" } else { "" })
    };
    match mots[i] {
        "upgrade" | "dist-upgrade" | "full-upgrade" => "Avant la mise à jour du système".into(),
        "remove" | "purge" | "autoremove" if liste.is_empty() => "Avant une désinstallation".into(),
        "remove" | "purge" | "autoremove" => format!("Avant la désinstallation{liste}"),
        _ if liste.is_empty() => "Avant une installation".into(),
        _ => format!("Avant l'installation{liste}"),
    }
}

/// « 2026-10-04 10:12:33 » -> « 4 octobre 2026 a 10 h 12 ». Une date que
/// snapper ecrirait autrement est rendue telle quelle.
pub fn date_lisible(date: &str) -> String {
    const MOIS: [&str; 12] = [
        "janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
        "septembre", "octobre", "novembre", "décembre",
    ];
    let mut parts = date.split_whitespace();
    let (Some(jour), Some(heure)) = (parts.next(), parts.next()) else {
        return date.to_string();
    };
    let d: Vec<&str> = jour.split('-').collect();
    let h: Vec<&str> = heure.split(':').collect();
    let (Some(y), Some(m), Some(j), Some(hh), Some(mm)) =
        (d.first(), d.get(1).and_then(|m| m.parse::<usize>().ok()), d.get(2).and_then(|j| j.parse::<u32>().ok()), h.first(), h.get(1))
    else {
        return date.to_string();
    };
    match MOIS.get(m.wrapping_sub(1)) {
        Some(mois) => format!("{j} {mois} {y} à {} h {mm}", hh.trim_start_matches('0').parse::<u32>().unwrap_or(0)),
        None => date.to_string(),
    }
}

pub fn create_snapshot(description: &str) -> ActionResult {
    let desc = description.trim();
    // La description arrive en argv (aucune injection shell possible), mais
    // elle est reaffichee par snapper: on borne la longueur et on refuse les
    // caracteres de controle qui casseraient la sortie CSV relue ci-dessus.
    if desc.is_empty() || desc.len() > 200 || desc.chars().any(|c| c.is_control() || c == ',') {
        return ActionResult::err("description invalide (200 caractères max, sans virgule)");
    }
    let out = run_pkexec(&["auxi", "snapshot", desc]);
    if out.ok {
        ActionResult::ok(format!("Instantané créé: {desc}"))
    } else {
        ActionResult::err(last_lines(&out.stderr))
    }
}

pub fn rollback(number: u32) -> ActionResult {
    let n = number.to_string();
    let out = run_pkexec(&["auxi", "rollback", &n, "--yes"]);
    if out.ok {
        ActionResult::ok(format!(
            "Restauration de l'instantané {number} prête. Redémarrez pour l'appliquer."
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
        "Échec de l'opération".into()
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

    fn snap(number: u32, kind: &str, date: &str, desc: &str, auxi: bool, cleanup: &str) -> Snapshot {
        Snapshot {
            number,
            kind: kind.into(),
            date: date.into(),
            description: desc.into(),
            from_auxi: auxi,
            cleanup: cleanup.into(),
        }
    }

    #[test]
    fn points_keep_one_entry_per_event_most_recent_first() {
        let snaps = vec![
            snap(1, "single", "2026-10-01 09:00:00", "Installation initiale AuxiNuxOS", false, ""),
            snap(2, "single", "2026-10-02 08:00:00", "timeline", false, "timeline"),
            snap(3, "single", "2026-10-02 09:00:00", "timeline", false, "timeline"),
            snap(4, "single", "2026-10-02 09:30:00", "boot", false, "number"),
            snap(5, "pre", "2026-10-02 10:00:00", "/usr/bin/apt-get -y install vlc", true, "number"),
            snap(6, "post", "2026-10-02 10:01:00", "", true, "number"),
            snap(7, "single", "2026-10-03 11:00:00", "avant essai pilote", false, ""),
        ];
        let p = points(&snaps);
        let numeros: Vec<u32> = p.iter().map(|p| p.number).collect();
        // post, boot et la 2e sauvegarde du 2 octobre sont ecartes.
        assert_eq!(numeros, vec![7, 5, 3, 1]);
        assert_eq!(p[0].titre, "avant essai pilote");
        assert_eq!(p[0].origine, Origine::Manuel);
        assert_eq!(p[1].titre, "Avant l'installation de vlc");
        assert_eq!(p[2].origine, Origine::Quotidien);
        assert_eq!(p[3].origine, Origine::Installation);
        assert_eq!(p[3].date, "1 octobre 2026 à 9 h 00");
    }

    #[test]
    fn a_manual_point_made_through_auxi_keeps_its_name() {
        let snaps = vec![snap(2, "single", "2026-10-04 16:47:00", "avant essai pilote", true, "number")];
        let p = points(&snaps);
        assert_eq!(p[0].origine, Origine::Manuel);
        assert_eq!(p[0].titre, "avant essai pilote");
    }

    #[test]
    fn an_os_version_upgrade_point_shows_the_version() {
        // Pose par `auxi os upgrade` (type single, marque auxi=1): automatique,
        // et titre = la version d'AuxiNux OS quittee pour la suivante.
        let snaps = vec![snap(
            9,
            "single",
            "2026-10-09 08:00:00",
            "Avant AuxiNux OS 0.2.1, édition du 2026-10-09",
            true,
            "number",
        )];
        let p = points(&snaps);
        assert_eq!(p[0].origine, Origine::AvantModification);
        assert_eq!(p[0].titre, "Avant AuxiNux OS 0.2.1, édition du 2026-10-09");
    }

    #[test]
    fn transaction_titles_say_what_was_about_to_happen() {
        assert_eq!(avant("apt-get -y upgrade"), "Avant la mise à jour du système");
        assert_eq!(avant("/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold full-upgrade"), "Avant la mise à jour du système");
        assert_eq!(avant("apt purge kate"), "Avant la désinstallation de kate");
        assert_eq!(avant("apt install a b c d"), "Avant l'installation de a, b, c…");
        assert_eq!(avant("/usr/bin/dpkg --status-fd 3"), "Avant une modification des logiciels");
        assert_eq!(avant(""), "Avant une modification des logiciels");
    }

    #[test]
    fn unreadable_dates_are_shown_as_is() {
        assert_eq!(date_lisible("2026-12-25 07:05:00"), "25 décembre 2026 à 7 h 05");
        assert_eq!(date_lisible("hier"), "hier");
        assert_eq!(date_lisible("2026-13-01 10:00:00"), "2026-13-01 10:00:00");
    }

    #[test]
    fn snapshot_boot_is_read_from_the_grub_btrfs_command_line() {
        let grub = "BOOT_IMAGE=/@snapshots/5/snapshot/boot/vmlinuz-7.2.5 root=UUID=ab \
                    rootflags=subvol=@snapshots/5/snapshot quiet auxinux.snapshot=1";
        assert_eq!(snapshot_boot(grub), Some(5));
        // Disposition imbriquee des anciennes installations.
        assert_eq!(
            snapshot_boot("rootflags=subvol=@/.snapshots/12/snapshot auxinux.snapshot=1"),
            Some(12)
        );
        // Demarrage normal: pas de marqueur, pas de mode temporaire.
        assert_eq!(snapshot_boot("BOOT_IMAGE=/@/boot/vmlinuz rootflags=subvol=@ quiet"), None);
        assert_eq!(snapshot_boot("auxinux.snapshot=1"), None);
    }
}
