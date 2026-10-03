//! Ce que l'installateur demande au systeme: disques, reseau, Wi-Fi, fuseaux,
//! claviers -- et ce qu'il lui transmet: le fichier de configuration du moteur.
//!
//! Aucune dependance a l'interface: tout ce qui peut etre analyse (sortie de
//! lsblk et nmcli, validations, diapositives) est teste par
//! `cargo test --no-default-features --features tui`.

use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

use crate::util::run;

pub const MOTEUR: &str = "/usr/lib/auxinux/auxinux-install-engine";
pub const JOURNAL: &str = "/var/log/auxinux-installation.log";
/// Repertoire des fichiers transmis au moteur: en memoire (/run), lisible par
/// root seul -- il contient le mot de passe et la phrase de chiffrement.
const DOSSIER: &str = "/run/auxinux-installer";
/// En dessous, l'installation n'a pas la place de vivre: systeme, echange,
/// instantanes et applications Flatpak.
pub const TAILLE_MINIMALE: u64 = 25 * 1024 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Langue {
    Fr,
    En,
}

impl Langue {
    pub fn locale(self) -> &'static str {
        match self {
            Langue::Fr => "fr_CA.UTF-8",
            Langue::En => "en_CA.UTF-8",
        }
    }
}

/// Le texte dans la langue choisie. Tout texte affiche passe par ici: un
/// libelle oublie dans une seule langue se voit a la relecture du code.
pub fn tr(l: Langue, fr: &'static str, en: &'static str) -> &'static str {
    match l {
        Langue::Fr => fr,
        Langue::En => en,
    }
}

// ---------------------------------------------------------------------------
// Diapositives
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub struct Diapositive {
    pub titre: String,
    pub texte: String,
}

/// Source unique, partagee avec le diaporama de Calamares (installer/
/// diapositives/, voir image-builder/scripts/generate-slideshow.sh).
const DIAPOS_FR: &str = include_str!("../../../../installer/diapositives/fr.txt");
const DIAPOS_EN: &str = include_str!("../../../../installer/diapositives/en.txt");

pub fn diapositives(l: Langue) -> Vec<Diapositive> {
    analyser_diapositives(match l {
        Langue::Fr => DIAPOS_FR,
        Langue::En => DIAPOS_EN,
    })
}

/// Blocs separes par « --- »; premiere ligne = titre; lignes « # » ignorees
/// (commentaires d'en-tete).
pub fn analyser_diapositives(source: &str) -> Vec<Diapositive> {
    let mut diapos = Vec::new();
    for bloc in source.split("\n---") {
        let lignes: Vec<&str> = bloc
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#') && *l != "---")
            .collect();
        if let Some((titre, texte)) = lignes.split_first() {
            diapos.push(Diapositive {
                titre: titre.to_string(),
                texte: texte.join(" "),
            });
        }
    }
    diapos
}

// ---------------------------------------------------------------------------
// Disques
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub struct Disque {
    pub chemin: String,
    pub taille: u64,
    pub modele: String,
    pub transport: String,
}

impl Disque {
    pub fn taille_lisible(&self) -> String {
        format!("{:.0} Go", self.taille as f64 / 1e9)
    }
    pub fn trop_petit(&self) -> bool {
        self.taille < TAILLE_MINIMALE
    }
}

pub fn lister_disques() -> Vec<Disque> {
    let sortie = run("lsblk", &["-J", "-b", "-d", "-o", "PATH,SIZE,MODEL,TYPE,TRAN"]);
    let support = run("findmnt", &["-no", "SOURCE", "/run/live/medium"]);
    let parent = if support.stdout.trim().is_empty() {
        String::new()
    } else {
        let p = run("lsblk", &["-no", "PKNAME", support.stdout.trim()]);
        match p.stdout.lines().next().map(str::trim) {
            Some(n) if !n.is_empty() => format!("/dev/{n}"),
            _ => support.stdout.trim().to_string(),
        }
    };
    analyser_lsblk(&sortie.stdout, &parent)
}

/// Disques proposes: de vrais disques, jamais le support d'installation, ni
/// les peripheriques virtuels (zram, lecteurs optiques, boucles).
pub fn analyser_lsblk(json: &str, support: &str) -> Vec<Disque> {
    let v: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };
    let mut disques = Vec::new();
    for d in v["blockdevices"].as_array().into_iter().flatten() {
        let chemin = d["path"].as_str().unwrap_or("").to_string();
        if d["type"].as_str() != Some("disk")
            || chemin.is_empty()
            || chemin == support
            || chemin.starts_with("/dev/zram")
        {
            continue;
        }
        let taille = match &d["size"] {
            serde_json::Value::Number(n) => n.as_u64().unwrap_or(0),
            serde_json::Value::String(s) => s.parse().unwrap_or(0),
            _ => 0,
        };
        disques.push(Disque {
            chemin,
            taille,
            modele: d["model"].as_str().unwrap_or("").trim().to_string(),
            transport: d["tran"].as_str().unwrap_or("").to_string(),
        });
    }
    disques
}

// ---------------------------------------------------------------------------
// Reseau
// ---------------------------------------------------------------------------

/// Internet REELLEMENT joignable: le depot AuxiNux, d'ou viennent les mises a
/// jour. Un reseau local sans sortie ne compte pas.
pub fn internet() -> bool {
    run(
        "curl",
        &["-sfI", "--max-time", "8", "-o", "/dev/null", "https://dep.auxinux.ca/"],
    )
    .ok
}

pub fn wifi_present() -> bool {
    run("nmcli", &["-t", "-f", "TYPE", "device"])
        .stdout
        .lines()
        .any(|l| l.trim() == "wifi")
}

#[derive(Clone, Debug, PartialEq)]
pub struct Wifi {
    pub ssid: String,
    pub signal: u8,
    pub securise: bool,
}

pub fn reseaux_wifi() -> Vec<Wifi> {
    let sortie = run(
        "nmcli",
        &["-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes"],
    );
    analyser_wifi(&sortie.stdout)
}

/// Sortie « terse » de nmcli: champs separes par « : », et « \: » pour un
/// deux-points DANS le nom du reseau. Un reseau vu par plusieurs bornes
/// n'apparait qu'une fois, avec le meilleur signal; les reseaux caches (sans
/// nom) sont ignores.
pub fn analyser_wifi(terse: &str) -> Vec<Wifi> {
    let mut reseaux: Vec<Wifi> = Vec::new();
    for ligne in terse.lines() {
        let mut champs = Vec::new();
        let mut courant = String::new();
        let mut echappe = false;
        for c in ligne.chars() {
            if echappe {
                courant.push(c);
                echappe = false;
            } else if c == '\\' {
                echappe = true;
            } else if c == ':' {
                champs.push(std::mem::take(&mut courant));
            } else {
                courant.push(c);
            }
        }
        champs.push(courant);
        if champs.len() < 3 || champs[0].is_empty() {
            continue;
        }
        let signal = champs[1].parse().unwrap_or(0);
        let securise = !champs[2].trim().is_empty() && champs[2].trim() != "--";
        match reseaux.iter_mut().find(|r| r.ssid == champs[0]) {
            Some(r) if r.signal >= signal => {}
            Some(r) => r.signal = signal,
            None => reseaux.push(Wifi { ssid: champs[0].clone(), signal, securise }),
        }
    }
    reseaux.sort_by(|a, b| b.signal.cmp(&a.signal));
    reseaux
}

pub fn connecter_wifi(ssid: &str, mot_de_passe: &str) -> Result<(), String> {
    let mut args = vec!["device", "wifi", "connect", ssid];
    if !mot_de_passe.is_empty() {
        args.extend(["password", mot_de_passe]);
    }
    let sortie = run("nmcli", &args);
    if sortie.ok {
        Ok(())
    } else {
        Err(sortie.stderr.trim().to_string())
    }
}

// ---------------------------------------------------------------------------
// Fuseaux horaires et claviers
// ---------------------------------------------------------------------------

pub fn fuseaux() -> Vec<String> {
    let sortie = run("timedatectl", &["list-timezones"]);
    let liste: Vec<String> = sortie
        .stdout
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect();
    if liste.is_empty() {
        // timedatectl peut manquer: les fuseaux du Canada suffisent alors.
        [
            "America/Toronto", "America/Montreal", "America/Halifax", "America/Moncton",
            "America/St_Johns", "America/Winnipeg", "America/Regina", "America/Edmonton",
            "America/Vancouver", "Europe/Paris", "UTC",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect()
    } else {
        liste
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Clavier {
    pub disposition: &'static str,
    pub variante: &'static str,
    pub fr: &'static str,
    pub en: &'static str,
}

pub const CLAVIERS: [Clavier; 8] = [
    Clavier { disposition: "ca", variante: "", fr: "Français (Canada)", en: "French (Canada)" },
    Clavier { disposition: "us", variante: "", fr: "Anglais (États-Unis, QWERTY)", en: "English (US, QWERTY)" },
    Clavier { disposition: "ca", variante: "multix", fr: "Canadien multilingue", en: "Canadian multilingual" },
    Clavier { disposition: "ca", variante: "eng", fr: "Anglais (Canada)", en: "English (Canada)" },
    Clavier { disposition: "fr", variante: "", fr: "Français (France, AZERTY)", en: "French (France, AZERTY)" },
    Clavier { disposition: "be", variante: "", fr: "Belge (AZERTY)", en: "Belgian (AZERTY)" },
    Clavier { disposition: "ch", variante: "fr", fr: "Suisse romand", en: "Swiss French" },
    Clavier { disposition: "gb", variante: "", fr: "Anglais (Royaume-Uni)", en: "English (UK)" },
];

/// Applique la disposition a la console DU LIVE, tout de suite. Sans cela, le
/// mot de passe serait tape avec une disposition et verifie avec une autre:
/// c'est exactement la panne vue le 2026-09-29 (mot de passe accepte a
/// l'ecran de connexion, refuse au deverrouillage).
pub fn appliquer_clavier_console(c: &Clavier) -> bool {
    let mut args = vec!["-layout", c.disposition];
    if !c.variante.is_empty() {
        args.extend(["-variant", c.variante]);
    }
    let carte = run("ckbcomp", &args);
    if !carte.ok {
        return false;
    }
    let lancer = std::process::Command::new("loadkeys")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
    match lancer {
        Ok(mut enfant) => {
            if let Some(mut entree) = enfant.stdin.take() {
                let _ = entree.write_all(carte.stdout.as_bytes());
            }
            enfant.wait().map(|s| s.success()).unwrap_or(false)
        }
        Err(_) => false,
    }
}

// ---------------------------------------------------------------------------
// Compte
// ---------------------------------------------------------------------------

/// Memes regles que le moteur (qui revalide): un refus ici evite d'aller
/// jusqu'au resume pour se faire refuser l'installation.
pub fn utilisateur_valide(nom: &str) -> bool {
    let mut c = nom.chars();
    nom.len() <= 32
        && c.next().is_some_and(|f| f.is_ascii_lowercase() || f == '_')
        && c.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
        && !matches!(nom, "root" | "nobody" | "auxinux")
}

pub fn nom_machine_valide(nom: &str) -> bool {
    let b = nom.as_bytes();
    !b.is_empty()
        && b.len() <= 63
        && b[0].is_ascii_alphanumeric()
        && b[b.len() - 1].is_ascii_alphanumeric()
        && b.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'-')
}

pub fn nom_complet_valide(nom: &str) -> bool {
    !nom.contains([':', ',', '\n'])
}

/// « Marie-Ève Tremblay » -> « marie-eve ». Une proposition, modifiable.
pub fn proposer_utilisateur(nom_complet: &str) -> String {
    let premier = nom_complet.split_whitespace().next().unwrap_or("");
    let mut s: String = premier
        .chars()
        .filter_map(|c| {
            let c = match c {
                'à' | 'â' | 'ä' | 'á' | 'À' | 'Â' => 'a',
                'é' | 'è' | 'ê' | 'ë' | 'É' | 'È' | 'Ê' => 'e',
                'î' | 'ï' | 'Î' => 'i',
                'ô' | 'ö' | 'Ô' => 'o',
                'ù' | 'û' | 'ü' | 'Û' => 'u',
                'ç' | 'Ç' => 'c',
                c => c,
            };
            let c = c.to_ascii_lowercase();
            (c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-').then_some(c)
        })
        .collect();
    s.truncate(32);
    if s.is_empty() || !utilisateur_valide(&s) {
        String::new()
    } else {
        s
    }
}

// ---------------------------------------------------------------------------
// Configuration du moteur
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct Configuration {
    pub disque: String,
    pub chiffrement: Option<String>,
    pub locale: String,
    pub fuseau: String,
    pub disposition: String,
    pub variante: String,
    pub nom_machine: String,
    pub utilisateur: String,
    pub nom_complet: String,
    pub mot_de_passe: String,
    pub en_ligne: bool,
    pub profil: String,
    pub applications: Vec<String>,
}

fn ecrire_prive(chemin: &Path, contenu: &str) -> std::io::Result<()> {
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(chemin)?;
    f.write_all(contenu.as_bytes())
}

impl Configuration {
    /// Le texte du fichier CLE=VALEUR lu par le moteur (sans les secrets, qui
    /// vont dans des fichiers a part).
    pub fn texte(&self, dossier: &Path) -> String {
        let mut t = String::new();
        let mut l = |k: &str, v: &str| {
            // Une valeur sur une ligne: un retour a la ligne injecterait une
            // cle. Le moteur revalide de toute facon chaque valeur.
            t.push_str(&format!("{k}={}\n", v.replace(['\n', '\r'], " ")));
        };
        l("DISQUE", &self.disque);
        l("CHIFFREMENT", if self.chiffrement.is_some() { "1" } else { "0" });
        if self.chiffrement.is_some() {
            l("CLE_LUKS", &dossier.join("cle-luks").to_string_lossy());
        }
        l("LOCALE", &self.locale);
        l("FUSEAU", &self.fuseau);
        l("CLAVIER", &self.disposition);
        l("VARIANTE_CLAVIER", &self.variante);
        l("NOM_MACHINE", &self.nom_machine);
        l("UTILISATEUR", &self.utilisateur);
        l("NOM_COMPLET", &self.nom_complet);
        l("MOT_DE_PASSE", &dossier.join("mot-de-passe").to_string_lossy());
        l("EN_LIGNE", if self.en_ligne { "1" } else { "0" });
        l("PROFIL", &self.profil);
        l("APPLICATIONS", &self.applications.join(" "));
        t
    }

    /// Ecrit la configuration et les secrets, lisibles par root seul.
    pub fn ecrire(&self) -> std::io::Result<PathBuf> {
        let dossier = Path::new(DOSSIER);
        if !dossier.exists() {
            std::fs::DirBuilder::new().mode(0o700).create(dossier)?;
        }
        ecrire_prive(&dossier.join("mot-de-passe"), &self.mot_de_passe)?;
        if let Some(phrase) = &self.chiffrement {
            // Sans retour a la ligne final: cryptsetup lit le fichier tel quel,
            // et un « \n » ferait partie de la phrase de passe.
            ecrire_prive(&dossier.join("cle-luks"), phrase)?;
        }
        let chemin = dossier.join("configuration");
        ecrire_prive(&chemin, &self.texte(dossier))?;
        Ok(chemin)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slides_are_parsed_in_both_languages_with_the_same_count() {
        let fr = diapositives(Langue::Fr);
        let en = diapositives(Langue::En);
        assert!(fr.len() >= 5);
        assert_eq!(fr.len(), en.len(), "chaque diapositive doit exister dans les deux langues");
        assert_eq!(fr[0].titre, "Bienvenue dans AuxiNux OS");
        assert!(fr.iter().all(|d| !d.texte.is_empty() && !d.titre.starts_with('#')));
    }

    #[test]
    fn disks_exclude_the_install_medium_and_virtual_devices() {
        let json = r#"{"blockdevices":[
          {"path":"/dev/sda","size":16000000000,"model":"USB Stick","type":"disk","tran":"usb"},
          {"path":"/dev/nvme0n1","size":512110190592,"model":"Samsung SSD 980 ","type":"disk","tran":"nvme"},
          {"path":"/dev/sr0","size":2026973184,"model":"QEMU DVD","type":"rom","tran":"sata"},
          {"path":"/dev/zram0","size":4000000000,"model":null,"type":"disk","tran":null}
        ]}"#;
        let d = analyser_lsblk(json, "/dev/sda");
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].chemin, "/dev/nvme0n1");
        assert_eq!(d[0].modele, "Samsung SSD 980");
        assert!(!d[0].trop_petit());
    }

    #[test]
    fn wifi_names_with_colons_and_duplicates() {
        let t = "Maison\\:5G:72:WPA2\nCafe:40:\nMaison\\:5G:85:WPA2\n:30:WPA2\n";
        let r = analyser_wifi(t);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0], Wifi { ssid: "Maison:5G".into(), signal: 85, securise: true });
        assert!(!r[1].securise);
    }

    #[test]
    fn account_rules_match_the_engine() {
        assert!(utilisateur_valide("marie"));
        assert!(utilisateur_valide("jean-luc_2"));
        for refuse in ["", "Marie", "1marie", "root", "auxinux", "marie tremblay", "-x"] {
            assert!(!utilisateur_valide(refuse), "{refuse} accepte");
        }
        assert!(nom_machine_valide("portable-marie"));
        assert!(!nom_machine_valide("-x") && !nom_machine_valide("a_b") && !nom_machine_valide(""));
        assert!(!nom_complet_valide("Tremblay, Marie"));
    }

    #[test]
    fn username_is_proposed_from_the_full_name() {
        assert_eq!(proposer_utilisateur("Marie-Ève Tremblay"), "marie-eve");
        assert_eq!(proposer_utilisateur("François"), "francois");
        assert_eq!(proposer_utilisateur("  "), "");
    }

    #[test]
    fn configuration_text_never_contains_secrets_or_injected_keys() {
        let c = Configuration {
            disque: "/dev/nvme0n1".into(),
            chiffrement: Some("phrase secrete".into()),
            locale: "fr_CA.UTF-8".into(),
            fuseau: "America/Toronto".into(),
            disposition: "ca".into(),
            nom_machine: "pc".into(),
            utilisateur: "marie".into(),
            nom_complet: "Marie\nDISQUE=/dev/sda".into(),
            mot_de_passe: "secret".into(),
            en_ligne: true,
            profil: "gaming".into(),
            applications: vec!["--flatpak".into(), "org.videolan.VLC".into()],
            ..Default::default()
        };
        let t = c.texte(Path::new("/run/x"));
        assert!(!t.contains("secret"));
        assert!(t.contains("CHIFFREMENT=1\nCLE_LUKS=/run/x/cle-luks\n"));
        assert!(t.contains("APPLICATIONS=--flatpak org.videolan.VLC\n"));
        assert_eq!(
            t.lines().filter(|l| l.starts_with("DISQUE=")).count(),
            1,
            "cle injectee par un retour a la ligne"
        );
    }
}
