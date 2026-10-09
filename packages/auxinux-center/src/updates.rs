//! Section MISES A JOUR: applications ET systeme d'exploitation.
//!
//! Tout passe par la CLI `auxi`, jamais par apt-get directement: c'est `auxi`
//! qui pose l'instantane de securite avant la transaction. Court-circuiter
//! `auxi` ici reviendrait a offrir dans l'interface un chemin de mise a jour
//! SANS filet, alors que le terminal en a un.

use crate::model::ActionResult;
use crate::progress;
use crate::util::run;

/// Rafraichit les index de paquets (equivalent de `auxi update`).
pub fn refresh_indexes(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(&["update"], on_line, "Listes de paquets à jour")
}

/// Met a jour tout le systeme: applications Flatpak, puis `auxi osupdate`
/// (index rafraichis, tous les paquets DEB AVEC les paquets nouveaux qu'ils
/// tirent -- un nouveau noyau --, noyaux d'essai). L'instantane est pose par le
/// hook dpkg avant la partie DEB.
pub fn upgrade_all(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(&["upgrade"], on_line, "Mise à jour du système terminée")
}

/// Version du paquet auxinux-center installee, si elle differe du binaire en
/// cours d'execution: le paquet a ete mis a jour pendant que le Center tournait.
pub fn center_updated() -> Option<String> {
    let out = run("dpkg-query", &["-W", "-f=${Version}", "auxinux-center"]);
    if !out.ok {
        return None;
    }
    newer_than_running(out.stdout.trim(), env!("CARGO_PKG_VERSION"))
}

fn newer_than_running(installed: &str, running: &str) -> Option<String> {
    if installed.is_empty() || installed == running {
        None
    } else {
        Some(installed.to_string())
    }
}


/// Version du systeme telle qu'affichee a l'utilisateur.
///
/// « AuxiNux OS 0.2.0, édition du 2026-10-09 »: l'edition vient du champ
/// BUILD_ID d'os-release, ecrit par le paquet auxinuxos-release.
pub fn os_version() -> String {
    let out = run(
        "sh",
        &["-c", ". /etc/os-release 2>/dev/null && printf '%s\\n%s' \"$PRETTY_NAME\" \"$BUILD_ID\""],
    );
    let mut lines = out.stdout.lines();
    let name = lines.next().unwrap_or("").trim();
    let name = if name.is_empty() { "AuxiNux OS" } else { name };
    match lines.next().and_then(|b| edition_label(b.trim())) {
        Some(edition) => format!("{name}, {edition}"),
        None => name.to_string(),
    }
}

/// Nouvelle version d'AuxiNux OS disponible (paquet auxinuxos-release).
#[derive(Clone, Debug, PartialEq)]
pub struct OsUpdate {
    /// « AuxiNux OS 0.2.0, édition du 2026-10-09 »
    pub available: String,
    /// Nouveautes, une par ligne (description longue du paquet).
    pub notes: Vec<String>,
}

/// La version d'AuxiNux OS proposee par les depots, si elle est plus recente
/// que celle installee.
///
/// Une machine installee avant le 2026-10-09 n'a pas le paquet: la version
/// disponible lui est quand meme annoncee, et `auxi osupdate` l'installe.
/// Les listes de paquets doivent etre a jour: le paquet auxinuxos-release
/// active leur rafraichissement quotidien (apt-daily).
pub fn os_update_available() -> Option<OsUpdate> {
    // LC_ALL=C: la sortie d'apt-cache est traduite (« Installé : (aucun) »).
    let policy = run("env", &["LC_ALL=C", "apt-cache", "policy", "auxinuxos-release"]);
    let (installed, candidate) = parse_policy(&policy.stdout)?;
    if let Some(installed) = &installed {
        let newer = run("dpkg", &["--compare-versions", &candidate, "gt", installed]);
        if !newer.ok {
            return None;
        }
    }
    let show = run(
        "env",
        &["LC_ALL=C", "apt-cache", "show", "--no-all-versions", "auxinuxos-release"],
    );
    let (summary, notes) = parse_description(&show.stdout);
    let available = if summary.is_empty() {
        format!("AuxiNux OS {}", candidate)
    } else {
        summary
    };
    Some(OsUpdate { available, notes })
}

/// (version installee, version candidate) d'`apt-cache policy`, en LC_ALL=C.
fn parse_policy(out: &str) -> Option<(Option<String>, String)> {
    let field = |key: &str| {
        out.lines()
            .find_map(|l| l.trim().strip_prefix(key).map(|v| v.trim().to_string()))
    };
    let candidate = field("Candidate:")?;
    if candidate.is_empty() || candidate == "(none)" {
        return None;
    }
    let installed = field("Installed:").filter(|v| !v.is_empty() && v != "(none)");
    Some((installed, candidate))
}

/// Resume et lignes de la description longue d'`apt-cache show`.
fn parse_description(out: &str) -> (String, Vec<String>) {
    let mut lines = out.lines().skip_while(|l| !l.starts_with("Description"));
    let summary = lines
        .next()
        .and_then(|l| l.split_once(':'))
        .map(|(_, v)| v.trim().to_string())
        .unwrap_or_default();
    let notes = lines
        .take_while(|l| l.starts_with(' '))
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && *l != ".")
        .map(str::to_string)
        .collect();
    (summary, notes)
}

/// « 20261009.2 » -> « édition du 2026-10-09 (2) ».
fn edition_label(build_id: &str) -> Option<String> {
    let (day, n) = match build_id.split_once('.') {
        Some((d, n)) => (d, Some(n)),
        None => (build_id, None),
    };
    if day.len() != 8 || !day.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut label = format!("édition du {}-{}-{}", &day[..4], &day[4..6], &day[6..]);
    if let Some(n) = n.filter(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit())) {
        label.push_str(&format!(" ({n})"));
    }
    Some(label)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edition_labels() {
        assert_eq!(edition_label("20261009").as_deref(), Some("édition du 2026-10-09"));
        assert_eq!(edition_label("20261009.2").as_deref(), Some("édition du 2026-10-09 (2)"));
        assert_eq!(edition_label(""), None);
        assert_eq!(edition_label("trixie"), None);
    }

    #[test]
    fn policy_of_an_installed_and_a_missing_release() {
        let installed = "auxinuxos-release:\n  Installed: 0.2.0+20261008.2\n  Candidate: 0.2.0+20261009\n  Version table:\n";
        assert_eq!(
            parse_policy(installed),
            Some((Some("0.2.0+20261008.2".into()), "0.2.0+20261009".into()))
        );
        // Machine d'avant le 2026-10-09: paquet absent, version quand meme annoncee.
        let missing = "auxinuxos-release:\n  Installed: (none)\n  Candidate: 0.2.0+20261009\n";
        assert_eq!(parse_policy(missing), Some((None, "0.2.0+20261009".into())));
        // Depot sans le paquet (listes perimees): rien a annoncer.
        assert_eq!(parse_policy("auxinuxos-release:\n  Installed: (none)\n  Candidate: (none)\n"), None);
        assert_eq!(parse_policy(""), None);
    }

    #[test]
    fn release_notes_from_the_package_description() {
        let show = "Package: auxinuxos-release\nVersion: 0.2.0+20261009\n\
                    Description: AuxiNux OS 0.2.0, édition du 2026-10-09\n \
                    Dossiers personnels standard.\n .\n Wine 32 bits inclus.\nHomepage: x\n";
        let (summary, notes) = parse_description(show);
        assert_eq!(summary, "AuxiNux OS 0.2.0, édition du 2026-10-09");
        assert_eq!(notes, vec!["Dossiers personnels standard.", "Wine 32 bits inclus."]);
    }

    #[test]
    fn center_update_is_detected_only_when_versions_differ() {
        assert_eq!(newer_than_running("0.2.2", "0.2.1"), Some("0.2.2".into()));
        assert_eq!(newer_than_running("0.2.1", "0.2.1"), None);
        // Paquet absent (installation d'avant la 0.2.1): rien a signaler.
        assert_eq!(newer_than_running("", "0.2.1"), None);
    }
}
