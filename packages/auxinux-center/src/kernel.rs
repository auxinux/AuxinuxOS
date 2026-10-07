//! Noyaux AuxiNux: lire l'etat, installer, activer, desinstaller.
//!
//! Tout passe par `auxi kernel` (voir packages/auxi-cli/auxi), jamais par
//! apt-get directement: c'est auxi qui n'accepte que les noyaux AuxiNux, qui
//! refuse de retirer le noyau en cours ou le dernier noyau stable, et dont la
//! transaction est couverte par l'instantane du hook dpkg.
//!
//! Pourquoi une vue a part: le noyau d'essai est un paquet DISTINCT du noyau
//! stable (linux-image-7.2.9-dev-auxinuxos-amd64). Activer sa source
//! n'installait rien, et la mise a jour du systeme ne pouvait pas le choisir a
//! la place de l'utilisateur.
//!
//! Hors de la feature `gui`: l'analyse est couverte par
//! `cargo test --no-default-features`.

use std::cmp::Ordering;

use crate::model::ActionResult;
use crate::progress;
use crate::util::run;

#[derive(Clone, Debug, PartialEq)]
pub struct Kernel {
    /// Version telle que `uname -r` l'affiche: 7.2.5-auxinuxos-amd64.
    pub version: String,
    /// Canal d'essai (suite kernel-dev).
    pub dev: bool,
    pub installed: bool,
    /// Le noyau qui tourne en ce moment.
    pub running: bool,
    /// Celui que GRUB demarrera la prochaine fois.
    pub default: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct KernelState {
    pub running: String,
    pub default: String,
    /// Noyau de demarrage choisi par l'utilisateur (`auxi kernel activate`),
    /// au lieu du plus recent.
    pub pinned: bool,
    /// Source kernel-dev active.
    pub dev_source: bool,
    /// Installes puis disponibles, chacun du plus ancien au plus recent.
    pub kernels: Vec<Kernel>,
}

impl KernelState {
    pub fn installed(&self) -> Vec<&Kernel> {
        self.kernels.iter().filter(|k| k.installed).collect()
    }

    /// Noyaux installables d'un canal, du plus recent au plus ancien.
    pub fn available(&self, dev: bool) -> Vec<&Kernel> {
        let mut list: Vec<&Kernel> =
            self.kernels.iter().filter(|k| !k.installed && k.dev == dev).collect();
        list.sort_by(|a, b| version_cmp(&b.version, &a.version));
        list
    }

    /// Version plus recente que tous les noyaux installes d'un canal deja
    /// present sur la machine: c'est ce que `auxi kernel update` installerait.
    pub fn update_for(&self, dev: bool) -> Option<&Kernel> {
        let newest_installed = self
            .kernels
            .iter()
            .filter(|k| k.installed && k.dev == dev)
            .max_by(|a, b| version_cmp(&a.version, &b.version))?;
        self.kernels
            .iter()
            .filter(|k| !k.installed && k.dev == dev)
            .max_by(|a, b| version_cmp(&a.version, &b.version))
            .filter(|k| version_cmp(&k.version, &newest_installed.version) == Ordering::Greater)
    }

    /// Nombre de noyaux stables installes: le dernier ne se desinstalle pas.
    pub fn stable_installed(&self) -> usize {
        self.kernels.iter().filter(|k| k.installed && !k.dev).count()
    }

    /// Le noyau peut-il etre desinstalle? Memes refus que `auxi kernel
    /// remove`: le bouton est grise au lieu d'echouer apres l'authentification.
    pub fn removable(&self, kernel: &Kernel) -> bool {
        kernel.installed && !kernel.running && (kernel.dev || self.stable_installed() > 1)
    }
}

/// Analyse la sortie de `auxi kernel list --porcelain`:
///
/// ```text
/// actif       7.2.5-auxinuxos-amd64
/// defaut      7.2.5-auxinuxos-amd64   auto|epingle
/// source-dev  on|off
/// noyau       VERSION   stable|dev   installe,actif,defaut | disponible
/// ```
///
/// (colonnes separees par des tabulations). Une ligne inconnue est ignoree:
/// une version plus recente d'auxi peut en ajouter.
pub fn parse(out: &str) -> KernelState {
    let mut state = KernelState::default();
    for line in out.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        match fields.as_slice() {
            ["actif", v, ..] => state.running = v.to_string(),
            ["defaut", v, mode, ..] => {
                state.default = v.to_string();
                state.pinned = *mode == "epingle";
            }
            ["defaut", v] => state.default = v.to_string(),
            ["source-dev", on, ..] => state.dev_source = *on == "on",
            ["noyau", v, channel, states, ..] if !v.is_empty() => {
                let states: Vec<&str> = states.split(',').collect();
                state.kernels.push(Kernel {
                    version: v.to_string(),
                    dev: *channel == "dev",
                    installed: states.contains(&"installe"),
                    running: states.contains(&"actif"),
                    default: states.contains(&"defaut"),
                });
            }
            _ => {}
        }
    }
    state
}

/// Etat des noyaux. Sans droits: auxi lit dpkg, apt-cache et grub.cfg.
pub fn load() -> Result<KernelState, String> {
    let out = run("auxi", &["kernel", "list", "--porcelain"]);
    if !out.ok {
        let reason = out.stderr.trim();
        return Err(if reason.is_empty() {
            "Lecture des noyaux impossible (auxi kernel list).".to_string()
        } else {
            format!("Lecture des noyaux impossible: {reason}")
        });
    }
    Ok(parse(&out.stdout))
}

pub fn install(version: &str, on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(
        &["kernel", "install", version],
        on_line,
        &format!("Noyau {version} installé."),
    )
}

pub fn update(on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(&["kernel", "update"], on_line, "Noyaux à jour.")
}

/// `version` = "latest": revenir au noyau le plus recent.
pub fn activate(version: &str, on_line: &mut dyn FnMut(&str)) -> ActionResult {
    let success = if version == "latest" {
        "Le noyau le plus récent sera utilisé au prochain démarrage.".to_string()
    } else {
        format!("Le noyau {version} sera utilisé au prochain démarrage.")
    };
    progress::auxi(&["kernel", "activate", version], on_line, &success)
}

pub fn remove(version: &str, on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(
        &["kernel", "remove", version],
        on_line,
        &format!("Noyau {version} désinstallé."),
    )
}

pub fn set_dev_source(enabled: bool, on_line: &mut dyn FnMut(&str)) -> ActionResult {
    progress::auxi(
        &["kernel", "dev", if enabled { "on" } else { "off" }],
        on_line,
        if enabled {
            "Noyaux en essai activés."
        } else {
            "Noyaux en essai désactivés."
        },
    )
}

/// Comparaison de versions « naturelle », comme `sort -V` dans auxi: les
/// nombres sont compares comme des nombres (7.2.10 > 7.2.9).
pub fn version_cmp(a: &str, b: &str) -> Ordering {
    let (mut a, mut b) = (a.as_bytes(), b.as_bytes());
    loop {
        match (a.first(), b.first()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let na = a.iter().take_while(|c| c.is_ascii_digit()).count();
                let nb = b.iter().take_while(|c| c.is_ascii_digit()).count();
                let (da, db) = (trim_zeros(&a[..na]), trim_zeros(&b[..nb]));
                let order = da.len().cmp(&db.len()).then_with(|| da.cmp(db));
                if order != Ordering::Equal {
                    return order;
                }
                a = &a[na..];
                b = &b[nb..];
            }
            (Some(x), Some(y)) => {
                if x != y {
                    return x.cmp(y);
                }
                a = &a[1..];
                b = &b[1..];
            }
        }
    }
}

fn trim_zeros(digits: &[u8]) -> &[u8] {
    let zeros = digits.iter().take_while(|&&c| c == b'0').count();
    &digits[zeros..]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Sortie de `auxi kernel list --porcelain` (voir tests/test-auxi-kernel.sh,
    /// qui verifie l'autre cote du format).
    const SAMPLE: &str = "actif\t7.2.5-auxinuxos-amd64\n\
                          defaut\t7.2.9-dev-auxinuxos-amd64\tauto\n\
                          source-dev\ton\n\
                          noyau\t7.2.5-auxinuxos-amd64\tstable\tinstalle,actif\n\
                          noyau\t7.2.9-dev-auxinuxos-amd64\tdev\tinstalle,defaut\n\
                          noyau\t7.2.6-auxinuxos-amd64\tstable\tdisponible\n\
                          noyau\t7.2.10-dev-auxinuxos-amd64\tdev\tdisponible\n\
                          ligne-future\tignoree\n";

    #[test]
    fn parses_the_porcelain_output() {
        let s = parse(SAMPLE);
        assert_eq!(s.running, "7.2.5-auxinuxos-amd64");
        assert_eq!(s.default, "7.2.9-dev-auxinuxos-amd64");
        assert!(!s.pinned);
        assert!(s.dev_source);
        assert_eq!(s.kernels.len(), 4);
        let running = &s.kernels[0];
        assert!(running.installed && running.running && !running.default && !running.dev);
        let dev = &s.kernels[1];
        assert!(dev.installed && dev.default && dev.dev && !dev.running);
        assert!(!s.kernels[2].installed);
    }

    #[test]
    fn pinned_default() {
        let s = parse("defaut\t7.2.5-auxinuxos-amd64\tepingle\nsource-dev\toff\n");
        assert!(s.pinned);
        assert!(!s.dev_source);
    }

    #[test]
    fn updates_per_channel() {
        let s = parse(SAMPLE);
        assert_eq!(s.update_for(false).map(|k| k.version.as_str()), Some("7.2.6-auxinuxos-amd64"));
        // 7.2.10 > 7.2.9: comparaison numerique, pas alphabetique.
        assert_eq!(
            s.update_for(true).map(|k| k.version.as_str()),
            Some("7.2.10-dev-auxinuxos-amd64")
        );
        // Aucun noyau d'essai installe: rien a « mettre a jour » dans ce canal.
        let s = parse("noyau\t7.2.5-auxinuxos-amd64\tstable\tinstalle\nnoyau\t7.2.9-dev-auxinuxos-amd64\tdev\tdisponible\n");
        assert_eq!(s.update_for(true), None);
        // Une version disponible PLUS ANCIENNE n'est pas une mise a jour.
        let s = parse("noyau\t7.2.6-auxinuxos-amd64\tstable\tinstalle\nnoyau\t7.2.5-auxinuxos-amd64\tstable\tdisponible\n");
        assert_eq!(s.update_for(false), None);
    }

    #[test]
    fn removal_rules_match_auxi() {
        let s = parse(SAMPLE);
        // Le noyau en cours, et le dernier stable: non.
        assert!(!s.removable(&s.kernels[0]));
        // Un noyau d'essai qui ne tourne pas: oui.
        assert!(s.removable(&s.kernels[1]));
        // Pas installe: rien a desinstaller.
        assert!(!s.removable(&s.kernels[2]));
        let two_stables = parse(
            "noyau\t7.2.5-auxinuxos-amd64\tstable\tinstalle\nnoyau\t7.2.6-auxinuxos-amd64\tstable\tinstalle,actif\n",
        );
        assert!(two_stables.removable(&two_stables.kernels[0]));
    }

    #[test]
    fn available_newest_first() {
        let s = parse("noyau\t7.2.9-dev-auxinuxos-amd64\tdev\tdisponible\nnoyau\t7.2.10-dev-auxinuxos-amd64\tdev\tdisponible\n");
        let v: Vec<&str> = s.available(true).iter().map(|k| k.version.as_str()).collect();
        assert_eq!(v, vec!["7.2.10-dev-auxinuxos-amd64", "7.2.9-dev-auxinuxos-amd64"]);
        assert!(s.available(false).is_empty());
    }

    #[test]
    fn natural_version_order() {
        assert_eq!(version_cmp("7.2.10-auxinuxos-amd64", "7.2.9-auxinuxos-amd64"), Ordering::Greater);
        assert_eq!(version_cmp("7.2.5-auxinuxos-amd64", "7.2.5-auxinuxos-amd64"), Ordering::Equal);
        assert_eq!(version_cmp("7.10.0", "7.9.9"), Ordering::Greater);
        assert_eq!(version_cmp("7.2.05", "7.2.5"), Ordering::Equal);
    }
}
