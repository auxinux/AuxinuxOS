//! Ecrans de l'installateur console, un par question.
//!
//! Langue, reseau (avec connexion Wi-Fi), fuseau horaire, clavier, disque (et
//! chiffrement), compte administrateur, applications -- seulement en ligne --,
//! resume, installation avec barre de progression et diapositives, fin.
//!
//! Entree = suivant, Echap = precedent. Rien n'est ecrit sur le disque avant le
//! resume, ou il faut taper OUI (YES) pour confirmer l'effacement.

use std::collections::VecDeque;
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use ratatui::crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Gauge, List, ListItem, ListState, Paragraph, Wrap};
use ratatui::{DefaultTerminal, Frame};

use crate::assistant::{Profil, Selection, LECTEURS, NAVIGATEURS, VIE_PRIVEE};
use crate::progress::{self, Parsed};
use crate::systeme::{self, tr, Clavier, Configuration, Disque, EtatInternet, Langue, Lien, Wifi, CLAVIERS};

/// Duree d'affichage d'une diapositive pendant l'installation.
const DUREE_DIAPO: Duration = Duration::from_secs(14);
const LIGNES_JOURNAL: usize = 400;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Ecran {
    Langue,
    Reseau,
    Fuseau,
    Clavier,
    Disque,
    Chiffrement,
    Compte,
    Navigateur,
    Lecteur,
    Profil,
    ViePrivee,
    Resume,
    Installation,
    Fin,
    Quitter,
}

/// Ce que l'installateur rend a son appelant (main.rs).
pub enum Sortie {
    Redemarrer,
    Eteindre,
    BureauLive,
    Console,
}

/// Travail reseau fait APRES le prochain affichage: curl, nmcli et le reglage
/// de l'heure bloquent plusieurs secondes, et l'ecran doit dire pourquoi il ne
/// repond plus.
enum Attente {
    Verifier,
    Connecter { ssid: String, mot_de_passe: String },
    Horloge,
}

enum Evenement {
    Ligne(String),
    Fin(Result<(), String>),
}

struct Progression {
    etape: Option<(u32, u32, String)>,
    fraction: f32,
    libelle: String,
    detail: String,
    journal: VecDeque<String>,
}

pub struct App {
    l: Langue,
    ecran: Ecran,
    curseur: usize,
    message: String,

    // Reseau
    en_ligne: bool,
    internet: EtatInternet,
    liens: Vec<Lien>,
    /// L'heure de l'ordinateur au dernier echec TLS, affichee avec la raison.
    heure: String,
    attente: Option<Attente>,
    /// Le reglage de l'heure a deja ete tente pour cette verification.
    horloge_tentee: bool,
    wifi: bool,
    reseaux: Vec<Wifi>,
    /// Reseau choisi dont on saisit le mot de passe.
    saisie_wifi: Option<(String, String)>,

    // Fuseau
    fuseaux: Vec<String>,
    filtre: String,
    fuseau: String,

    clavier: usize,

    // Disque
    disques: Vec<Disque>,
    disque: Option<usize>,
    chiffrer: bool,
    phrase: [String; 2],

    // Compte: nom complet, utilisateur, machine, mot de passe x2
    champs: [String; 5],
    champ: usize,
    utilisateur_modifie: bool,

    selection: Selection,
    confirmation: String,

    // Installation
    rx: Option<Receiver<Evenement>>,
    progression: Progression,
    debut_diapo: Instant,
    diapo: usize,
    montrer_journal: bool,
    resultat: Option<Result<(), String>>,
}

impl App {
    pub fn new() -> Self {
        App {
            l: Langue::Fr,
            ecran: Ecran::Langue,
            curseur: 0,
            message: String::new(),
            en_ligne: false,
            internet: EtatInternet::Dns,
            liens: Vec::new(),
            heure: String::new(),
            attente: None,
            horloge_tentee: false,
            wifi: false,
            reseaux: Vec::new(),
            saisie_wifi: None,
            fuseaux: Vec::new(),
            filtre: String::new(),
            fuseau: "America/Toronto".into(),
            clavier: 0,
            disques: Vec::new(),
            disque: None,
            chiffrer: false,
            phrase: Default::default(),
            champs: Default::default(),
            champ: 0,
            utilisateur_modifie: false,
            selection: Selection::default(),
            confirmation: String::new(),
            rx: None,
            progression: Progression {
                etape: None,
                fraction: 0.0,
                libelle: String::new(),
                detail: String::new(),
                journal: VecDeque::new(),
            },
            debut_diapo: Instant::now(),
            diapo: 0,
            montrer_journal: false,
            resultat: None,
        }
    }

    fn t(&self, fr: &'static str, en: &'static str) -> &'static str {
        tr(self.l, fr, en)
    }

    pub fn executer(mut self, terminal: &mut DefaultTerminal) -> std::io::Result<Sortie> {
        loop {
            self.recevoir();
            terminal.draw(|f| self.dessiner(f))?;
            if let Some(a) = self.attente.take() {
                self.traiter(a);
                continue;
            }
            if event::poll(Duration::from_millis(150))? {
                if let Event::Key(k) = event::read()? {
                    if k.kind == KeyEventKind::Press {
                        if let Some(sortie) = self.touche(k) {
                            return Ok(sortie);
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Enchainement
    // -----------------------------------------------------------------------

    fn aller(&mut self, ecran: Ecran) {
        self.message.clear();
        self.curseur = 0;
        match ecran {
            Ecran::Reseau => self.demander(Attente::Verifier),
            Ecran::Fuseau => {
                if self.fuseaux.is_empty() {
                    self.fuseaux = systeme::fuseaux();
                }
                self.curseur = self.fuseaux.iter().position(|f| *f == self.fuseau).unwrap_or(0);
            }
            Ecran::Clavier => self.curseur = self.clavier,
            Ecran::Disque => {
                self.disques = systeme::lister_disques();
                self.curseur = self.disque.unwrap_or(0);
            }
            Ecran::Navigateur => {
                self.curseur = self.selection.navigateur.unwrap_or(NAVIGATEURS.len())
            }
            Ecran::Lecteur => self.curseur = self.selection.lecteur.unwrap_or(LECTEURS.len()),
            Ecran::Installation => self.lancer(),
            _ => {}
        }
        self.ecran = ecran;
    }

    fn suivant(&self) -> Ecran {
        use Ecran::*;
        match self.ecran {
            Langue => Reseau,
            Reseau => Fuseau,
            Fuseau => Clavier,
            Clavier => Disque,
            Disque if self.chiffrer => Chiffrement,
            Disque | Chiffrement => Compte,
            Compte if self.en_ligne => Navigateur,
            Compte => Profil,
            Navigateur => Lecteur,
            Lecteur => Profil,
            Profil if self.en_ligne => ViePrivee,
            Profil | ViePrivee => Resume,
            Resume => Installation,
            e => e,
        }
    }

    fn precedent(&self) -> Ecran {
        use Ecran::*;
        match self.ecran {
            Reseau => Langue,
            Fuseau => Reseau,
            Clavier => Fuseau,
            Disque => Clavier,
            Chiffrement => Disque,
            Compte if self.chiffrer => Chiffrement,
            Compte => Disque,
            Navigateur => Compte,
            Lecteur => Navigateur,
            Profil if self.en_ligne => Lecteur,
            Profil => Compte,
            ViePrivee => Profil,
            Resume if self.en_ligne => ViePrivee,
            Resume => Profil,
            e => e,
        }
    }

    fn demander(&mut self, a: Attente) {
        self.message.clear();
        if matches!(a, Attente::Verifier | Attente::Connecter { .. }) {
            self.horloge_tentee = false;
        }
        self.attente = Some(a);
    }

    fn traiter(&mut self, a: Attente) {
        match a {
            Attente::Verifier => self.verifier_reseau(),
            Attente::Connecter { ssid, mot_de_passe } => match systeme::connecter_wifi(&ssid, &mot_de_passe) {
                Ok(()) => self.verifier_reseau(),
                Err(e) => self.message = format!("{} {e}", self.t("Connexion impossible:", "Could not connect:")),
            },
            Attente::Horloge => {
                systeme::regler_horloge();
                self.verifier_reseau();
            }
        }
    }

    fn verifier_reseau(&mut self) {
        self.internet = systeme::internet();
        self.en_ligne = self.internet == EtatInternet::EnLigne;
        self.liens = systeme::liens_actifs();
        self.wifi = systeme::wifi_present();
        // Le serveur repond mais refuse la connexion securisee: l'horloge,
        // presque toujours. Un seul reglage par verification demandee.
        if self.internet == EtatInternet::Tls && !self.horloge_tentee {
            self.horloge_tentee = true;
            self.attente = Some(Attente::Horloge);
            return;
        }
        self.heure = systeme::heure_locale();
        if !self.en_ligne && self.wifi {
            self.reseaux = systeme::reseaux_wifi();
        }
    }

    // -----------------------------------------------------------------------
    // Clavier
    // -----------------------------------------------------------------------

    fn touche(&mut self, k: KeyEvent) -> Option<Sortie> {
        let ctrl = k.modifiers.contains(KeyModifiers::CONTROL);
        // Ctrl+Q: menu de sortie, partout sauf pendant l'installation.
        if ctrl && matches!(k.code, KeyCode::Char('q')) && self.ecran != Ecran::Installation {
            self.ecran = Ecran::Quitter;
            self.curseur = 0;
            return None;
        }
        match self.ecran {
            Ecran::Langue => self.liste(k, 2, |a, i| {
                a.l = if i == 0 { Langue::Fr } else { Langue::En };
                // Le clavier propose suit la langue; il reste modifiable.
                a.clavier = if a.l == Langue::Fr { 0 } else { 1 };
                true
            }),
            Ecran::Reseau => self.touche_reseau(k),
            Ecran::Fuseau => self.touche_fuseau(k),
            Ecran::Clavier => self.liste(k, CLAVIERS.len(), |a, i| {
                a.clavier = i;
                if !systeme::appliquer_clavier_console(&CLAVIERS[i]) {
                    a.message = a
                        .t(
                            "Disposition non appliquée à la console: vérifiez votre mot de passe en le tapant.",
                            "Layout not applied to the console: check your password as you type it.",
                        )
                        .into();
                }
                true
            }),
            Ecran::Disque => self.touche_disque(k),
            Ecran::Chiffrement => self.touche_chiffrement(k),
            Ecran::Compte => self.touche_compte(k),
            Ecran::Navigateur => self.liste(k, NAVIGATEURS.len() + 1, |a, i| {
                a.selection.navigateur = (i < NAVIGATEURS.len()).then_some(i);
                true
            }),
            Ecran::Lecteur => self.liste(k, LECTEURS.len() + 1, |a, i| {
                a.selection.lecteur = (i < LECTEURS.len()).then_some(i);
                true
            }),
            Ecran::Profil => self.touche_profil(k),
            Ecran::ViePrivee => self.touche_cases(k, VIE_PRIVEE.len(), false),
            Ecran::Resume => self.touche_resume(k),
            Ecran::Installation => {
                if matches!(k.code, KeyCode::Char('j') | KeyCode::Char('J')) {
                    self.montrer_journal = !self.montrer_journal;
                }
                None
            }
            Ecran::Fin => self.touche_fin(k),
            Ecran::Quitter => self.touche_quitter(k),
        }
    }

    /// Liste a choix unique: fleches, Entree pour choisir et avancer.
    fn liste(&mut self, k: KeyEvent, n: usize, choisir: fn(&mut App, usize) -> bool) -> Option<Sortie> {
        match k.code {
            KeyCode::Up => self.curseur = self.curseur.saturating_sub(1),
            KeyCode::Down => self.curseur = (self.curseur + 1).min(n.saturating_sub(1)),
            KeyCode::Enter => {
                if choisir(self, self.curseur) {
                    let s = self.suivant();
                    self.aller(s);
                }
            }
            KeyCode::Esc => {
                let p = self.precedent();
                self.aller(p);
            }
            _ => {}
        }
        None
    }

    fn touche_reseau(&mut self, k: KeyEvent) -> Option<Sortie> {
        if let Some((ssid, mdp)) = &mut self.saisie_wifi {
            match k.code {
                KeyCode::Char(c) => mdp.push(c),
                KeyCode::Backspace => {
                    mdp.pop();
                }
                KeyCode::Esc => self.saisie_wifi = None,
                KeyCode::Enter => {
                    let (ssid, mot_de_passe) = (ssid.clone(), mdp.clone());
                    self.saisie_wifi = None;
                    self.demander(Attente::Connecter { ssid, mot_de_passe });
                }
                _ => {}
            }
            return None;
        }
        // Lignes: les reseaux Wi-Fi, puis « Reessayer », puis « Continuer ».
        let n = self.reseaux.len() + 2;
        match k.code {
            KeyCode::Up => self.curseur = self.curseur.saturating_sub(1),
            KeyCode::Down => self.curseur = (self.curseur + 1).min(n - 1),
            KeyCode::Esc => self.aller(Ecran::Langue),
            KeyCode::Enter if self.en_ligne => {
                let s = self.suivant();
                self.aller(s);
            }
            KeyCode::Enter => {
                if self.curseur < self.reseaux.len() {
                    let r = &self.reseaux[self.curseur];
                    if r.securise {
                        self.saisie_wifi = Some((r.ssid.clone(), String::new()));
                    } else {
                        let ssid = r.ssid.clone();
                        self.demander(Attente::Connecter { ssid, mot_de_passe: String::new() });
                    }
                } else if self.curseur == self.reseaux.len() {
                    self.demander(Attente::Verifier);
                    self.curseur = 0;
                } else {
                    // Sans Internet: socle seul, et on le dit.
                    let s = self.suivant();
                    self.aller(s);
                }
            }
            _ => {}
        }
        None
    }

    fn fuseaux_filtres(&self) -> Vec<&String> {
        let f = self.filtre.to_lowercase();
        self.fuseaux.iter().filter(|z| z.to_lowercase().contains(&f)).collect()
    }

    fn touche_fuseau(&mut self, k: KeyEvent) -> Option<Sortie> {
        let n = self.fuseaux_filtres().len();
        match k.code {
            KeyCode::Up => self.curseur = self.curseur.saturating_sub(1),
            KeyCode::Down => self.curseur = (self.curseur + 1).min(n.saturating_sub(1)),
            KeyCode::PageUp => self.curseur = self.curseur.saturating_sub(10),
            KeyCode::PageDown => self.curseur = (self.curseur + 10).min(n.saturating_sub(1)),
            KeyCode::Char(c) => {
                self.filtre.push(c);
                self.curseur = 0;
            }
            KeyCode::Backspace => {
                self.filtre.pop();
                self.curseur = 0;
            }
            KeyCode::Esc => {
                let p = self.precedent();
                self.aller(p);
            }
            KeyCode::Enter => {
                if let Some(z) = self.fuseaux_filtres().get(self.curseur) {
                    self.fuseau = z.to_string();
                    let s = self.suivant();
                    self.aller(s);
                }
            }
            _ => {}
        }
        None
    }

    fn touche_disque(&mut self, k: KeyEvent) -> Option<Sortie> {
        let n = self.disques.len();
        match k.code {
            KeyCode::Up => self.curseur = self.curseur.saturating_sub(1),
            KeyCode::Down => self.curseur = (self.curseur + 1).min(n.saturating_sub(1)),
            KeyCode::Char(' ') | KeyCode::Char('c') | KeyCode::Char('C') => self.chiffrer = !self.chiffrer,
            KeyCode::Esc => {
                let p = self.precedent();
                self.aller(p);
            }
            KeyCode::Enter => match self.disques.get(self.curseur) {
                Some(d) if d.trop_petit() => {
                    self.message = self
                        .t("Ce disque est trop petit (25 Go au minimum).", "This disk is too small (25 GB minimum).")
                        .into()
                }
                Some(_) => {
                    self.disque = Some(self.curseur);
                    let s = self.suivant();
                    self.aller(s);
                }
                None => {}
            },
            _ => {}
        }
        None
    }

    fn saisir(champ: &mut String, k: &KeyEvent) {
        match k.code {
            KeyCode::Char(c) => champ.push(c),
            KeyCode::Backspace => {
                champ.pop();
            }
            _ => {}
        }
    }

    fn touche_chiffrement(&mut self, k: KeyEvent) -> Option<Sortie> {
        match k.code {
            KeyCode::Tab | KeyCode::Down | KeyCode::Up => self.champ = 1 - self.champ.min(1),
            KeyCode::Esc => {
                self.champ = 0;
                let p = self.precedent();
                self.aller(p);
            }
            KeyCode::Enter => {
                if self.phrase[0].chars().count() < 8 {
                    self.message = self
                        .t("Au moins 8 caractères.", "At least 8 characters.")
                        .into();
                } else if self.phrase[0] != self.phrase[1] {
                    self.message = self.t("Les deux saisies diffèrent.", "The two entries differ.").into();
                } else {
                    self.champ = 0;
                    let s = self.suivant();
                    self.aller(s);
                }
            }
            _ => Self::saisir(&mut self.phrase[self.champ.min(1)], &k),
        }
        None
    }

    fn touche_compte(&mut self, k: KeyEvent) -> Option<Sortie> {
        match k.code {
            KeyCode::Tab | KeyCode::Down => self.champ = (self.champ + 1) % 5,
            KeyCode::BackTab | KeyCode::Up => self.champ = (self.champ + 4) % 5,
            KeyCode::Esc => {
                let p = self.precedent();
                self.aller(p);
            }
            KeyCode::Enter => {
                if self.champ < 4 {
                    self.champ += 1;
                } else if let Some(m) = self.compte_invalide() {
                    self.message = m.into();
                } else {
                    let s = self.suivant();
                    self.aller(s);
                }
            }
            _ => {
                let i = self.champ;
                Self::saisir(&mut self.champs[i], &k);
                if i == 1 {
                    self.utilisateur_modifie = true;
                }
                // Proposer le nom d'utilisateur et le nom de la machine a
                // partir du nom complet, tant qu'on n'y a pas touche.
                if i == 0 && !self.utilisateur_modifie {
                    self.champs[1] = systeme::proposer_utilisateur(&self.champs[0]);
                    if !self.champs[1].is_empty() {
                        self.champs[2] = format!("{}-pc", self.champs[1]);
                    }
                }
            }
        }
        None
    }

    fn compte_invalide(&self) -> Option<&'static str> {
        let c = &self.champs;
        if c[0].trim().is_empty() || !systeme::nom_complet_valide(&c[0]) {
            return Some(self.t("Nom complet invalide (sans « : » ni « , »).", "Invalid full name (no “:” or “,”)."));
        }
        if !systeme::utilisateur_valide(&c[1]) {
            return Some(self.t(
                "Nom d'utilisateur: minuscules, chiffres, « - » ou « _ », commençant par une lettre.",
                "Username: lowercase letters, digits, “-” or “_”, starting with a letter.",
            ));
        }
        if !systeme::nom_machine_valide(&c[2]) {
            return Some(self.t("Nom de l'ordinateur: lettres, chiffres et « - ».", "Computer name: letters, digits and “-”."));
        }
        if c[3].chars().count() < 4 {
            return Some(self.t("Mot de passe: au moins 4 caractères.", "Password: at least 4 characters."));
        }
        if c[3] != c[4] {
            return Some(self.t("Les deux mots de passe diffèrent.", "The two passwords differ."));
        }
        None
    }

    fn touche_profil(&mut self, k: KeyEvent) -> Option<Sortie> {
        match k.code {
            KeyCode::Left | KeyCode::Right | KeyCode::Char('p') | KeyCode::Char('P') => {
                let i = Profil::TOUS.iter().position(|p| *p == self.selection.profil).unwrap_or(0);
                let n = if k.code == KeyCode::Left { i + 2 } else { i + 1 };
                self.selection.set_profil(Profil::TOUS[n % 3]);
                self.curseur = 0;
                None
            }
            _ => {
                if self.en_ligne {
                    let n = self.selection.profil.suggestions().len();
                    self.touche_cases(k, n, true)
                } else {
                    // Hors ligne: le profil seul, pas d'application.
                    match k.code {
                        KeyCode::Enter => {
                            let s = self.suivant();
                            self.aller(s);
                        }
                        KeyCode::Esc => {
                            let p = self.precedent();
                            self.aller(p);
                        }
                        _ => {}
                    }
                    None
                }
            }
        }
    }

    /// Cases a cocher: Espace coche, Entree avance.
    fn touche_cases(&mut self, k: KeyEvent, n: usize, suggestions: bool) -> Option<Sortie> {
        match k.code {
            KeyCode::Up => self.curseur = self.curseur.saturating_sub(1),
            KeyCode::Down => self.curseur = (self.curseur + 1).min(n.saturating_sub(1)),
            KeyCode::Char(' ') => {
                let cases = if suggestions { &mut self.selection.suggestions } else { &mut self.selection.vie_privee };
                if let Some(c) = cases.get_mut(self.curseur) {
                    *c = !*c;
                }
            }
            KeyCode::Enter => {
                let s = self.suivant();
                self.aller(s);
            }
            KeyCode::Esc => {
                let p = self.precedent();
                self.aller(p);
            }
            _ => {}
        }
        None
    }

    fn touche_resume(&mut self, k: KeyEvent) -> Option<Sortie> {
        match k.code {
            KeyCode::Esc => {
                self.confirmation.clear();
                let p = self.precedent();
                self.aller(p);
            }
            KeyCode::Enter => {
                let attendu = self.t("OUI", "YES");
                if self.confirmation.trim().eq_ignore_ascii_case(attendu) {
                    self.confirmation.clear();
                    self.aller(Ecran::Installation);
                } else {
                    self.message = self
                        .t("Tapez OUI pour confirmer l'effacement du disque.", "Type YES to confirm erasing the disk.")
                        .into();
                }
            }
            _ => Self::saisir(&mut self.confirmation, &k),
        }
        None
    }

    fn touche_fin(&mut self, k: KeyEvent) -> Option<Sortie> {
        let reussi = matches!(self.resultat, Some(Ok(())));
        match k.code {
            KeyCode::Enter if reussi => Some(Sortie::Redemarrer),
            KeyCode::Enter => {
                self.ecran = Ecran::Quitter;
                self.curseur = 0;
                None
            }
            KeyCode::Char('r') | KeyCode::Char('R') if !reussi => {
                self.aller(Ecran::Resume);
                None
            }
            KeyCode::Char('j') | KeyCode::Char('J') => {
                self.montrer_journal = !self.montrer_journal;
                None
            }
            _ => None,
        }
    }

    fn touche_quitter(&mut self, k: KeyEvent) -> Option<Sortie> {
        match k.code {
            KeyCode::Up => self.curseur = self.curseur.saturating_sub(1),
            KeyCode::Down => self.curseur = (self.curseur + 1).min(4),
            KeyCode::Esc => self.aller(Ecran::Langue),
            KeyCode::Enter => {
                return match self.curseur {
                    0 => {
                        self.aller(Ecran::Langue);
                        None
                    }
                    1 => Some(Sortie::BureauLive),
                    2 => Some(Sortie::Console),
                    3 => Some(Sortie::Redemarrer),
                    _ => Some(Sortie::Eteindre),
                }
            }
            _ => {}
        }
        None
    }

    // -----------------------------------------------------------------------
    // Installation
    // -----------------------------------------------------------------------

    fn configuration(&self) -> Configuration {
        let clavier: &Clavier = &CLAVIERS[self.clavier];
        Configuration {
            disque: self.disque.and_then(|i| self.disques.get(i)).map(|d| d.chemin.clone()).unwrap_or_default(),
            chiffrement: self.chiffrer.then(|| self.phrase[0].clone()),
            locale: self.l.locale().into(),
            fuseau: self.fuseau.clone(),
            disposition: clavier.disposition.into(),
            variante: clavier.variante.into(),
            nom_machine: self.champs[2].clone(),
            utilisateur: self.champs[1].clone(),
            nom_complet: self.champs[0].clone(),
            mot_de_passe: self.champs[3].clone(),
            en_ligne: self.en_ligne,
            profil: self.selection.profil.id().into(),
            applications: if self.en_ligne { self.selection.app_args() } else { Vec::new() },
        }
    }

    fn lancer(&mut self) {
        self.resultat = None;
        self.progression = Progression {
            etape: None,
            fraction: 0.0,
            libelle: self.t("Démarrage…", "Starting…").into(),
            detail: String::new(),
            journal: VecDeque::new(),
        };
        self.debut_diapo = Instant::now();
        self.diapo = 0;
        let chemin = match self.configuration().ecrire() {
            Ok(c) => c,
            Err(e) => {
                self.resultat = Some(Err(format!("configuration: {e}")));
                self.ecran = Ecran::Fin;
                return;
            }
        };
        let (tx, rx) = mpsc::channel();
        self.rx = Some(rx);
        std::thread::spawn(move || {
            let lignes = tx.clone();
            let mut erreur = String::new();
            let sortie = crate::util::run_streaming(
                systeme::MOTEUR,
                &[chemin.to_string_lossy().as_ref()],
                &mut |l| {
                    if let Some(m) = l.strip_prefix("auxinux-erreur:") {
                        erreur = m.to_string();
                    }
                    let _ = lignes.send(Evenement::Ligne(l.to_string()));
                },
            );
            // Les secrets ne survivent pas a l'installation.
            let _ = std::fs::remove_dir_all("/run/auxinux-installer");
            let fin = if sortie.ok {
                Ok(())
            } else if erreur.is_empty() {
                Err(format!(
                    "code {}",
                    sortie.code.map(|c| c.to_string()).unwrap_or_else(|| "?".into())
                ))
            } else {
                Err(erreur)
            };
            let _ = tx.send(Evenement::Fin(fin));
        });
    }

    fn recevoir(&mut self) {
        let Some(rx) = &self.rx else { return };
        let evenements: Vec<Evenement> = rx.try_iter().collect();
        let mut fin = None;
        for e in evenements {
            match e {
                Evenement::Ligne(l) => self.integrer(&l),
                Evenement::Fin(r) => fin = Some(r),
            }
        }
        if let Some(r) = fin {
            self.rx = None;
            if r.is_ok() {
                self.progression.fraction = 1.0;
            }
            self.resultat = Some(r);
            self.ecran = Ecran::Fin;
        }
        if self.debut_diapo.elapsed() >= DUREE_DIAPO {
            self.diapo += 1;
            self.debut_diapo = Instant::now();
        }
    }

    fn integrer(&mut self, ligne: &str) {
        let p = &mut self.progression;
        match progress::parse(ligne) {
            Parsed::Stage { index, total, label } => {
                p.fraction = (index - 1) as f32 / total as f32;
                p.etape = Some((index, total, label));
                p.libelle.clear();
                p.detail.clear();
            }
            Parsed::Status { label, fraction, detail } => {
                if let Some((i, n, _)) = &p.etape {
                    p.fraction = ((*i - 1) as f32 + fraction) / *n as f32;
                }
                p.libelle = format!("{} — {} %", traduire(self.l, label), (fraction * 100.0).round() as u32);
                p.detail = detail;
            }
            Parsed::Log(t) => {
                if !t.starts_with("auxinux-") {
                    p.detail = t.clone();
                }
                if p.journal.len() == LIGNES_JOURNAL {
                    p.journal.pop_front();
                }
                p.journal.push_back(t);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Dessin
    // -----------------------------------------------------------------------

    fn dessiner(&self, f: &mut Frame) {
        let [haut, corps, bas] = Layout::vertical([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .areas(f.area());

        let titre = Paragraph::new(Line::from(vec![
            Span::styled(" AuxiNux OS 0.2.1 ", Style::new().fg(Color::Black).bg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::raw("  "),
            Span::styled(self.t("Installation", "Installation"), Style::new().add_modifier(Modifier::BOLD)),
            Span::raw(format!("  —  {}", self.titre_ecran())),
        ]))
        .block(Block::new().borders(Borders::BOTTOM));
        f.render_widget(titre, haut);

        match self.ecran {
            Ecran::Langue => self.dessiner_liste(
                f,
                corps,
                "Choisissez votre langue  /  Choose your language",
                vec!["Français".into(), "English".into()],
            ),
            Ecran::Reseau => self.dessiner_reseau(f, corps),
            Ecran::Fuseau => self.dessiner_fuseau(f, corps),
            Ecran::Clavier => self.dessiner_liste(
                f,
                corps,
                self.t(
                    "Disposition du clavier. Elle s'applique tout de suite: le mot de passe sera tapé avec elle.",
                    "Keyboard layout. It applies right away: your password will be typed with it.",
                ),
                CLAVIERS.iter().map(|c| tr(self.l, c.fr, c.en).to_string()).collect(),
            ),
            Ecran::Disque => self.dessiner_disque(f, corps),
            Ecran::Chiffrement => self.dessiner_champs(
                f,
                corps,
                self.t(
                    "Phrase de passe du chiffrement. Elle sera demandée à chaque démarrage. PERDUE, vos données sont irrécupérables.",
                    "Encryption passphrase. It will be asked at every startup. If LOST, your data cannot be recovered.",
                ),
                &[self.t("Phrase de passe", "Passphrase"), self.t("Confirmation", "Confirm")],
                &self.phrase,
                &[true, true],
                self.champ.min(1),
            ),
            Ecran::Compte => self.dessiner_champs(
                f,
                corps,
                self.t(
                    "Compte administrateur. Il pourra installer des logiciels et modifier le système.",
                    "Administrator account. It can install software and change the system.",
                ),
                &[
                    self.t("Nom complet", "Full name"),
                    self.t("Nom d'utilisateur", "Username"),
                    self.t("Nom de l'ordinateur", "Computer name"),
                    self.t("Mot de passe", "Password"),
                    self.t("Confirmation", "Confirm"),
                ],
                &self.champs,
                &[false, false, false, true, true],
                self.champ,
            ),
            Ecran::Navigateur => {
                let mut items: Vec<String> = NAVIGATEURS.iter().map(|a| format!("{}  —  {}", a.name, a.summary)).collect();
                items.push(self.t("Aucun pour l'instant", "None for now").into());
                self.dessiner_liste(f, corps, self.t("Quel navigateur voulez-vous ?", "Which web browser do you want?"), items)
            }
            Ecran::Lecteur => {
                let mut items: Vec<String> = LECTEURS.iter().map(|a| format!("{}  —  {}", a.name, a.summary)).collect();
                items.push(self.t("Aucun", "None").into());
                self.dessiner_liste(f, corps, self.t("Quel lecteur multimédia ?", "Which media player?"), items)
            }
            Ecran::Profil => self.dessiner_profil(f, corps),
            Ecran::ViePrivee => self.dessiner_cases(
                f,
                corps,
                self.t("Outils de vie privée, cochés d'avance (Espace pour décocher).", "Privacy tools, pre-checked (Space to uncheck)."),
                VIE_PRIVEE.iter().map(|a| format!("{}  —  {}", a.name, a.summary)).collect(),
                &self.selection.vie_privee,
            ),
            Ecran::Resume => self.dessiner_resume(f, corps),
            Ecran::Installation => self.dessiner_installation(f, corps),
            Ecran::Fin => self.dessiner_fin(f, corps),
            Ecran::Quitter => self.dessiner_liste(
                f,
                corps,
                self.t("Que voulez-vous faire ?", "What do you want to do?"),
                vec![
                    self.t("Revenir à l'installation", "Back to the installation").into(),
                    self.t("Démarrer le bureau live (essayer sans installer)", "Start the live desktop (try without installing)").into(),
                    self.t("Ouvrir une console", "Open a console").into(),
                    self.t("Redémarrer", "Restart").into(),
                    self.t("Éteindre", "Shut down").into(),
                ],
            ),
        }

        let aide = match self.ecran {
            Ecran::Installation => self.t("J: journal détaillé", "J: detailed log"),
            Ecran::Fin => self.t("Entrée: continuer   J: journal   R: recommencer", "Enter: continue   J: log   R: retry"),
            Ecran::Compte | Ecran::Chiffrement => {
                self.t("Tab: champ suivant   Entrée: valider   Échap: retour   Ctrl+Q: quitter", "Tab: next field   Enter: confirm   Esc: back   Ctrl+Q: quit")
            }
            Ecran::Profil | Ecran::ViePrivee => {
                self.t("←/→: profil   Espace: cocher   Entrée: suivant   Échap: retour", "←/→: profile   Space: check   Enter: next   Esc: back")
            }
            _ => self.t("↑/↓: choisir   Entrée: suivant   Échap: retour   Ctrl+Q: quitter", "↑/↓: select   Enter: next   Esc: back   Ctrl+Q: quit"),
        };
        let mut pied = vec![Line::styled(aide, Style::new().fg(Color::DarkGray))];
        if !self.message.is_empty() {
            pied.insert(0, Line::styled(self.message.clone(), Style::new().fg(Color::Yellow)));
        }
        f.render_widget(Paragraph::new(pied).block(Block::new().borders(Borders::TOP)), bas);
    }

    fn titre_ecran(&self) -> &'static str {
        match self.ecran {
            Ecran::Langue => "Langue / Language",
            Ecran::Reseau => self.t("Connexion Internet", "Internet connection"),
            Ecran::Fuseau => self.t("Fuseau horaire", "Time zone"),
            Ecran::Clavier => self.t("Clavier", "Keyboard"),
            Ecran::Disque => self.t("Disque", "Disk"),
            Ecran::Chiffrement => self.t("Chiffrement", "Encryption"),
            Ecran::Compte => self.t("Compte", "Account"),
            Ecran::Navigateur => self.t("Navigateur", "Web browser"),
            Ecran::Lecteur => self.t("Multimédia", "Media"),
            Ecran::Profil => self.t("Profil d'usage", "Usage profile"),
            Ecran::ViePrivee => self.t("Vie privée", "Privacy"),
            Ecran::Resume => self.t("Résumé", "Summary"),
            Ecran::Installation => self.t("Installation en cours", "Installing"),
            Ecran::Fin => self.t("Terminé", "Finished"),
            Ecran::Quitter => self.t("Quitter", "Quit"),
        }
    }

    fn dessiner_liste(&self, f: &mut Frame, zone: Rect, question: &str, items: Vec<String>) {
        let [q, l] = Layout::vertical([Constraint::Length(3), Constraint::Min(3)]).areas(zone);
        f.render_widget(Paragraph::new(question.to_string()).wrap(Wrap { trim: true }), q);
        let liste = List::new(items.into_iter().map(ListItem::new))
            .highlight_style(Style::new().fg(Color::Black).bg(Color::Cyan))
            .highlight_symbol("> ");
        let mut etat = ListState::default().with_selected(Some(self.curseur));
        f.render_stateful_widget(liste, l, &mut etat);
    }

    /// Ce que l'installateur fait pendant que l'ecran attend.
    fn libelle_attente(&self, a: &Attente) -> String {
        match a {
            Attente::Verifier => self.t("Vérification de la connexion Internet…", "Checking the Internet connection…").into(),
            Attente::Connecter { ssid, .. } => format!("{} « {ssid} »…", self.t("Connexion au réseau", "Connecting to network")),
            Attente::Horloge => self
                .t(
                    "La connexion sécurisée est refusée: réglage de l'heure de l'ordinateur (jusqu'à 20 secondes)…",
                    "The secure connection is refused: setting the computer's clock (up to 20 seconds)…",
                )
                .into(),
        }
    }

    /// Les liens reseau actifs, qu'Internet reponde ou non: la personne voit
    /// que son Wi-Fi ou son cable est bien pris en compte.
    fn lignes_liens(&self) -> Vec<Line<'static>> {
        if self.liens.is_empty() {
            return vec![Line::raw(self.t("Réseau: aucun câble branché ni Wi-Fi connecté.", "Network: no cable plugged in and no Wi-Fi connected."))];
        }
        let vert = Style::new().fg(Color::Green);
        self.liens
            .iter()
            .map(|l| match l {
                Lien::Cable => Line::styled(self.t("Câble réseau: connecté.", "Network cable: connected."), vert),
                Lien::Wifi(nom) => Line::styled(format!("{} « {nom} ».", self.t("Wi-Fi: connecté à", "Wi-Fi: connected to")), vert),
            })
            .collect()
    }

    /// Pourquoi Internet ne repond pas, quand un lien est actif (sans lien,
    /// l'explication suffit) ou que la connexion securisee echoue.
    fn raison_hors_ligne(&self) -> Option<String> {
        match self.internet {
            EtatInternet::EnLigne => None,
            EtatInternet::Tls => Some(format!(
                "{} {}. {}",
                self.t(
                    "Le serveur AuxiNux répond, mais la connexion sécurisée échoue. L'horloge de l'ordinateur indique",
                    "The AuxiNux server answers, but the secure connection fails. The computer's clock reads",
                ),
                self.heure,
                self.t(
                    "Si cette date ou cette heure est fausse, corrigez-la dans le BIOS/UEFI puis réessayez.",
                    "If this date or time is wrong, correct it in the BIOS/UEFI and try again.",
                ),
            )),
            _ if self.liens.is_empty() => None,
            EtatInternet::Dns => Some(
                self.t(
                    "Le réseau est relié, mais aucun nom de domaine ne se résout (pas de serveur DNS, ou réseau sans sortie vers Internet).",
                    "The network is up, but no domain name resolves (no DNS server, or a network with no way out to the Internet).",
                )
                .into(),
            ),
            EtatInternet::Injoignable => Some(
                self.t(
                    "Le réseau est relié, mais le serveur dep.auxinux.ca ne répond pas (réseau sans sortie, pare-feu, ou portail de connexion).",
                    "The network is up, but the dep.auxinux.ca server does not answer (no way out, firewall, or sign-in portal).",
                )
                .into(),
            ),
        }
    }

    fn dessiner_reseau(&self, f: &mut Frame, zone: Rect) {
        if let Some(a) = &self.attente {
            f.render_widget(
                Paragraph::new(self.libelle_attente(a)).style(Style::new().fg(Color::Cyan)).wrap(Wrap { trim: true }),
                zone,
            );
            return;
        }
        if self.en_ligne {
            let mut lignes = self.lignes_liens();
            lignes.extend([
                Line::raw(""),
                Line::styled(self.t("Connecté à Internet.", "Connected to the Internet."), Style::new().fg(Color::Green).add_modifier(Modifier::BOLD)),
                Line::raw(""),
                Line::raw(self.t(
                    "L'installation inclura les mises à jour de sécurité et les applications que vous allez choisir.",
                    "The installation will include security updates and the applications you are about to choose.",
                )),
                Line::raw(""),
                Line::raw(self.t("Appuyez sur Entrée pour continuer.", "Press Enter to continue.")),
            ]);
            f.render_widget(Paragraph::new(Text::from(lignes)).wrap(Wrap { trim: true }), zone);
            return;
        }
        if let Some((ssid, mdp)) = &self.saisie_wifi {
            let t = Text::from(vec![
                Line::raw(format!("{} « {ssid} »", self.t("Mot de passe du réseau", "Password for network"))),
                Line::raw(""),
                Line::styled(format!("> {}", "•".repeat(mdp.chars().count())), Style::new().fg(Color::Cyan)),
            ]);
            f.render_widget(Paragraph::new(t), zone);
            return;
        }
        let [q, l] = Layout::vertical([Constraint::Length(12), Constraint::Min(3)]).areas(zone);
        let explication = if self.wifi {
            self.t(
                "Aucune connexion Internet. Choisissez un réseau Wi-Fi, ou continuez sans Internet: l'installation sera MINIMALE, et il faudra relier l'ordinateur à Internet pour terminer la personnalisation (applications, mises à jour).",
                "No Internet connection. Pick a Wi-Fi network, or continue offline: the installation will be MINIMAL, and the computer must be connected to the Internet to finish the personalisation (applications, updates).",
            )
        } else {
            self.t(
                "Aucune connexion Internet. Branchez un câble réseau puis réessayez, ou continuez sans Internet: l'installation sera MINIMALE, et il faudra relier l'ordinateur à Internet pour terminer la personnalisation.",
                "No Internet connection. Plug in a network cable and try again, or continue offline: the installation will be MINIMAL, and the computer must be connected to the Internet to finish the personalisation.",
            )
        };
        let mut lignes = self.lignes_liens();
        if let Some(raison) = self.raison_hors_ligne() {
            lignes.push(Line::styled(raison, Style::new().fg(Color::Red).add_modifier(Modifier::BOLD)));
        }
        lignes.push(Line::raw(""));
        lignes.push(Line::styled(explication, Style::new().fg(Color::Yellow)));
        f.render_widget(Paragraph::new(Text::from(lignes)).wrap(Wrap { trim: true }), q);
        let mut items: Vec<String> = self
            .reseaux
            .iter()
            .map(|r| format!("{}  {:>3} %{}", r.ssid, r.signal, if r.securise { "  [WPA]" } else { "" }))
            .collect();
        items.push(self.t("Réessayer", "Try again").into());
        items.push(self.t("Continuer sans Internet (installation minimale)", "Continue offline (minimal installation)").into());
        let liste = List::new(items.into_iter().map(ListItem::new))
            .highlight_style(Style::new().fg(Color::Black).bg(Color::Cyan))
            .highlight_symbol("> ");
        let mut etat = ListState::default().with_selected(Some(self.curseur));
        f.render_stateful_widget(liste, l, &mut etat);
    }

    fn dessiner_fuseau(&self, f: &mut Frame, zone: Rect) {
        let [q, l] = Layout::vertical([Constraint::Length(3), Constraint::Min(3)]).areas(zone);
        f.render_widget(
            Paragraph::new(vec![
                Line::raw(self.t("Fuseau horaire. Tapez pour filtrer (ex.: Toronto, Montreal, Paris).", "Time zone. Type to filter (e.g. Toronto, Vancouver, Paris).")),
                Line::styled(format!("> {}", self.filtre), Style::new().fg(Color::Cyan)),
            ]),
            q,
        );
        let items: Vec<ListItem> = self.fuseaux_filtres().into_iter().map(|z| ListItem::new(z.clone())).collect();
        let liste = List::new(items).highlight_style(Style::new().fg(Color::Black).bg(Color::Cyan)).highlight_symbol("> ");
        let mut etat = ListState::default().with_selected(Some(self.curseur));
        f.render_stateful_widget(liste, l, &mut etat);
    }

    fn dessiner_disque(&self, f: &mut Frame, zone: Rect) {
        let [q, l, c] = Layout::vertical([Constraint::Length(3), Constraint::Min(3), Constraint::Length(4)]).areas(zone);
        f.render_widget(
            Paragraph::new(self.t(
                "Disque où installer AuxiNux OS. TOUT son contenu sera effacé. Le système utilise BTRFS, pour les points de restauration.",
                "Disk to install AuxiNux OS on. ALL its content will be erased. The system uses BTRFS, for restore points.",
            ))
            .wrap(Wrap { trim: true }),
            q,
        );
        let items: Vec<ListItem> = if self.disques.is_empty() {
            vec![ListItem::new(self.t("Aucun disque utilisable trouvé.", "No usable disk found."))]
        } else {
            self.disques
                .iter()
                .map(|d| {
                    let mut t = format!("{}   {}   {} {}", d.chemin, d.taille_lisible(), d.modele, d.transport);
                    if d.trop_petit() {
                        t.push_str(self.t("   (trop petit)", "   (too small)"));
                    }
                    ListItem::new(t)
                })
                .collect()
        };
        let liste = List::new(items).highlight_style(Style::new().fg(Color::Black).bg(Color::Cyan)).highlight_symbol("> ");
        let mut etat = ListState::default().with_selected(Some(self.curseur));
        f.render_stateful_widget(liste, l, &mut etat);
        let case = if self.chiffrer { "[x]" } else { "[ ]" };
        f.render_widget(
            Paragraph::new(vec![
                Line::styled(
                    format!("{case} {}", self.t("Chiffrer le disque (touche C)", "Encrypt the disk (C key)")),
                    Style::new().add_modifier(Modifier::BOLD),
                ),
                Line::raw(self.t(
                    "Protège vos données si l'ordinateur est volé. Une phrase de passe sera demandée à chaque démarrage.",
                    "Protects your data if the computer is stolen. A passphrase will be asked at every startup.",
                )),
            ])
            .wrap(Wrap { trim: true }),
            c,
        );
    }

    #[allow(clippy::too_many_arguments)]
    fn dessiner_champs(&self, f: &mut Frame, zone: Rect, consigne: &str, noms: &[&str], valeurs: &[String], masques: &[bool], actif: usize) {
        let mut lignes = vec![Line::raw(consigne.to_string()), Line::raw("")];
        for (i, nom) in noms.iter().enumerate() {
            let v = if masques[i] { "•".repeat(valeurs[i].chars().count()) } else { valeurs[i].clone() };
            let style = if i == actif { Style::new().fg(Color::Black).bg(Color::Cyan) } else { Style::new() };
            lignes.push(Line::from(vec![
                Span::raw(format!("{:<22}", nom)),
                Span::styled(format!(" {v}{} ", if i == actif { "_" } else { "" }), style),
            ]));
            lignes.push(Line::raw(""));
        }
        f.render_widget(Paragraph::new(lignes).wrap(Wrap { trim: false }), zone);
    }

    fn dessiner_cases(&self, f: &mut Frame, zone: Rect, question: &str, items: Vec<String>, cases: &[bool]) {
        let items = items
            .into_iter()
            .zip(cases.iter())
            .map(|(t, c)| format!("{} {t}", if *c { "[x]" } else { "[ ]" }))
            .collect();
        self.dessiner_liste(f, zone, question, items);
    }

    fn dessiner_profil(&self, f: &mut Frame, zone: Rect) {
        let [q, p, l] = Layout::vertical([Constraint::Length(3), Constraint::Length(3), Constraint::Min(3)]).areas(zone);
        f.render_widget(
            Paragraph::new(self.t(
                "À quoi servira surtout cet ordinateur ? Le profil règle le système pour cet usage (modifiable ensuite).",
                "What will this computer mostly be used for? The profile tunes the system for it (can be changed later).",
            ))
            .wrap(Wrap { trim: true }),
            q,
        );
        let mut spans = Vec::new();
        for pr in Profil::TOUS {
            let nom = match pr {
                Profil::Bureautique => self.t("Bureautique", "Office"),
                Profil::Multimedia => self.t("Multimédia", "Multimedia"),
                Profil::Jeu => self.t("Jeu", "Gaming"),
            };
            let style = if pr == self.selection.profil {
                Style::new().fg(Color::Black).bg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::new()
            };
            spans.push(Span::styled(format!(" {nom} "), style));
            spans.push(Span::raw("   "));
        }
        f.render_widget(Paragraph::new(Line::from(spans)), p);
        if self.en_ligne {
            let items: Vec<String> = self
                .selection
                .profil
                .suggestions()
                .iter()
                .map(|(a, _)| format!("{}  —  {}", a.name, a.summary))
                .collect();
            self.dessiner_cases(f, l, self.t("Applications suggérées:", "Suggested applications:"), items, &self.selection.suggestions);
        } else {
            f.render_widget(
                Paragraph::new(self.t(
                    "Sans Internet, aucune application n'est installée maintenant: l'assistant de configuration vous les proposera au premier démarrage connecté.",
                    "Without Internet, no application is installed now: the setup assistant will offer them at the first connected startup.",
                ))
                .wrap(Wrap { trim: true }),
                l,
            );
        }
    }

    fn dessiner_resume(&self, f: &mut Frame, zone: Rect) {
        let d = self.disque.and_then(|i| self.disques.get(i));
        let mut lignes = vec![
            Line::styled(
                format!(
                    "{} {} ({}) {}",
                    self.t("TOUT LE CONTENU DE", "ALL THE CONTENT OF"),
                    d.map(|d| d.chemin.as_str()).unwrap_or("?"),
                    d.map(|d| d.taille_lisible()).unwrap_or_default(),
                    self.t("SERA EFFACÉ.", "WILL BE ERASED."),
                ),
                Style::new().fg(Color::Red).add_modifier(Modifier::BOLD),
            ),
            Line::raw(""),
            Line::raw(format!("{:<24}{}", self.t("Langue", "Language"), tr(self.l, "Français", "English"))),
            Line::raw(format!("{:<24}{}", self.t("Fuseau horaire", "Time zone"), self.fuseau)),
            Line::raw(format!("{:<24}{}", self.t("Clavier", "Keyboard"), tr(self.l, CLAVIERS[self.clavier].fr, CLAVIERS[self.clavier].en))),
            Line::raw(format!(
                "{:<24}BTRFS{}",
                self.t("Système de fichiers", "File system"),
                if self.chiffrer { self.t(", chiffré (LUKS2)", ", encrypted (LUKS2)") } else { "" }
            )),
            Line::raw(format!("{:<24}{} ({})", self.t("Compte", "Account"), self.champs[0], self.champs[1])),
            Line::raw(format!("{:<24}{}", self.t("Ordinateur", "Computer"), self.champs[2])),
            Line::raw(format!("{:<24}{}", self.t("Profil", "Profile"), self.selection.profil.label())),
        ];
        if self.en_ligne {
            let apps: Vec<&str> = self.selection.applications().iter().map(|a| a.name).collect();
            lignes.push(Line::raw(format!("{:<24}{}", self.t("Applications", "Applications"), apps.join(", "))));
            lignes.push(Line::raw(format!("{:<24}{}", self.t("Mises à jour", "Updates"), self.t("oui", "yes"))));
        } else {
            lignes.push(Line::styled(
                self.t(
                    "Sans Internet: installation minimale. Reliez l'ordinateur à Internet après le redémarrage pour terminer la personnalisation.",
                    "Offline: minimal installation. Connect the computer to the Internet after restarting to finish the personalisation.",
                ),
                Style::new().fg(Color::Yellow),
            ));
        }
        lignes.push(Line::raw(""));
        lignes.push(Line::raw(self.t("Tapez OUI puis Entrée pour installer:", "Type YES then Enter to install:")));
        lignes.push(Line::styled(format!("> {}", self.confirmation), Style::new().fg(Color::Cyan)));
        f.render_widget(Paragraph::new(lignes).wrap(Wrap { trim: true }), zone);
    }

    fn dessiner_installation(&self, f: &mut Frame, zone: Rect) {
        let [g, d, s] = Layout::vertical([Constraint::Length(3), Constraint::Length(2), Constraint::Min(5)]).areas(zone);
        let p = &self.progression;
        let etape = match &p.etape {
            Some((i, n, cle)) => format!("{} {i} {} {n} — {}", self.t("Étape", "Step"), self.t("sur", "of"), etape_lisible(self.l, cle)),
            None => p.libelle.clone(),
        };
        let libelle = if p.libelle.is_empty() || p.etape.is_none() { etape } else { format!("{etape} — {}", p.libelle) };
        f.render_widget(
            Gauge::default()
                .block(Block::new().borders(Borders::ALL).title(libelle))
                .gauge_style(Style::new().fg(Color::Cyan).bg(Color::DarkGray))
                .ratio(p.fraction.clamp(0.0, 1.0) as f64),
            g,
        );
        f.render_widget(Paragraph::new(p.detail.clone()).style(Style::new().fg(Color::DarkGray)), d);
        if self.montrer_journal {
            self.dessiner_journal(f, s);
        } else {
            let diapos = systeme::diapositives(self.l);
            if let Some(diapo) = diapos.get(self.diapo % diapos.len().max(1)) {
                f.render_widget(
                    Paragraph::new(vec![
                        Line::styled(diapo.titre.clone(), Style::new().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
                        Line::raw(""),
                        Line::raw(diapo.texte.clone()),
                    ])
                    .wrap(Wrap { trim: true })
                    .block(Block::new().borders(Borders::ALL).title(" AuxiNux OS ")),
                    s,
                );
            }
        }
    }

    fn dessiner_journal(&self, f: &mut Frame, zone: Rect) {
        let hauteur = zone.height.saturating_sub(2) as usize;
        let j = &self.progression.journal;
        let lignes: Vec<Line> = j.iter().skip(j.len().saturating_sub(hauteur)).map(|l| Line::raw(l.clone())).collect();
        f.render_widget(
            Paragraph::new(lignes).block(Block::new().borders(Borders::ALL).title(format!(" {} ", systeme::JOURNAL))),
            zone,
        );
    }

    fn dessiner_fin(&self, f: &mut Frame, zone: Rect) {
        if self.montrer_journal {
            self.dessiner_journal(f, zone);
            return;
        }
        let lignes = match &self.resultat {
            Some(Ok(())) => vec![
                Line::styled(self.t("AuxiNux OS est installé.", "AuxiNux OS is installed."), Style::new().fg(Color::Green).add_modifier(Modifier::BOLD)),
                Line::raw(""),
                Line::raw(self.t(
                    "Retirez le support d'installation (clé USB ou DVD), puis appuyez sur Entrée pour redémarrer.",
                    "Remove the installation medium (USB stick or DVD), then press Enter to restart.",
                )),
                Line::raw(""),
                Line::raw(if self.en_ligne {
                    self.t("Vos applications sont prêtes.", "Your applications are ready.")
                } else {
                    self.t(
                        "Au premier démarrage, reliez l'ordinateur à Internet: l'assistant de configuration vous proposera vos applications.",
                        "At first startup, connect the computer to the Internet: the setup assistant will offer your applications.",
                    )
                }),
            ],
            Some(Err(e)) => {
                let mut l = vec![
                    Line::styled(self.t("L'installation a échoué.", "The installation failed."), Style::new().fg(Color::Red).add_modifier(Modifier::BOLD)),
                    Line::raw(""),
                    Line::raw(e.clone()),
                    Line::raw(""),
                    Line::raw(format!("{} {}", self.t("Journal complet:", "Full log:"), systeme::JOURNAL)),
                    Line::raw(""),
                ];
                let j = &self.progression.journal;
                l.extend(j.iter().skip(j.len().saturating_sub(8)).map(|x| Line::styled(x.clone(), Style::new().fg(Color::DarkGray))));
                l
            }
            None => vec![],
        };
        f.render_widget(Paragraph::new(lignes).wrap(Wrap { trim: true }), zone);
    }
}

/// Codes d'etape du moteur, dans la langue choisie.
fn etape_lisible(l: Langue, cle: &str) -> String {
    match cle {
        "disque" => tr(l, "Préparation du disque", "Preparing the disk"),
        "sous-volumes" => tr(l, "Sous-volumes et points de restauration", "Subvolumes and restore points"),
        "copie" => tr(l, "Copie du système", "Copying the system"),
        "configuration" => tr(l, "Configuration", "Configuration"),
        "demarrage" => tr(l, "Chargeur de démarrage", "Boot loader"),
        "mises-a-jour" => tr(l, "Mises à jour de sécurité", "Security updates"),
        "applications" => tr(l, "Vos applications", "Your applications"),
        "finalisation" => tr(l, "Finalisation et vérification", "Finishing and checking"),
        "demontage" => tr(l, "Démontage", "Unmounting"),
        autre => return autre.to_string(),
    }
    .to_string()
}

/// Libelles d'avancement de progress.rs, dans la langue choisie.
fn traduire(l: Langue, libelle: &str) -> &str {
    match libelle {
        "Téléchargement" => tr(l, "Téléchargement", "Downloading"),
        "Application des modifications" => tr(l, "Installation des paquets", "Installing packages"),
        "Copie des fichiers" => tr(l, "Copie des fichiers", "Copying files"),
        autre => autre,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_stage_codes_are_translated_in_both_languages() {
        for code in ["disque", "sous-volumes", "copie", "configuration", "demarrage", "mises-a-jour", "applications", "finalisation", "demontage"] {
            assert_ne!(etape_lisible(Langue::Fr, code), code);
            assert_ne!(etape_lisible(Langue::En, code), code);
        }
    }

    #[test]
    fn offline_flow_skips_application_screens() {
        let mut a = App::new();
        a.en_ligne = false;
        a.ecran = Ecran::Compte;
        assert_eq!(a.suivant(), Ecran::Profil);
        a.ecran = Ecran::Profil;
        assert_eq!(a.suivant(), Ecran::Resume);
        a.ecran = Ecran::Resume;
        assert_eq!(a.precedent(), Ecran::Profil);
        a.en_ligne = true;
        a.ecran = Ecran::Compte;
        assert_eq!(a.suivant(), Ecran::Navigateur);
    }

    #[test]
    fn encryption_screen_only_when_chosen() {
        let mut a = App::new();
        a.ecran = Ecran::Disque;
        assert_eq!(a.suivant(), Ecran::Compte);
        a.chiffrer = true;
        assert_eq!(a.suivant(), Ecran::Chiffrement);
    }

    #[test]
    fn progress_bar_stays_global_across_stages() {
        let mut a = App::new();
        a.integrer("auxinux-etape:3:7:copie");
        assert!((a.progression.fraction - 2.0 / 7.0).abs() < 1e-6);
        a.integrer("auxinux-progression:50");
        assert!((a.progression.fraction - 2.5 / 7.0).abs() < 1e-6);
        a.integrer("Réglage de grub-efi-amd64");
        assert_eq!(a.progression.detail, "Réglage de grub-efi-amd64");
    }

    #[test]
    fn offline_reason_names_the_clock_and_stays_quiet_without_a_link() {
        let mut a = App::new();
        a.internet = EtatInternet::Tls;
        a.heure = "2026-04-13 09:00".into();
        let r = a.raison_hors_ligne().expect("raison TLS");
        assert!(r.contains("2026-04-13 09:00") && r.contains("BIOS/UEFI"), "{r}");
        a.internet = EtatInternet::Dns;
        assert_eq!(a.raison_hors_ligne(), None, "sans lien, l'explication suffit");
        a.liens = vec![Lien::Wifi("Maison".into())];
        assert!(a.raison_hors_ligne().unwrap().contains("DNS"));
        a.internet = EtatInternet::EnLigne;
        assert_eq!(a.raison_hors_ligne(), None);
    }

    #[test]
    fn every_new_check_may_set_the_clock_again() {
        let mut a = App::new();
        a.horloge_tentee = true;
        a.demander(Attente::Horloge);
        assert!(a.horloge_tentee);
        a.demander(Attente::Verifier);
        assert!(!a.horloge_tentee);
        assert!(matches!(a.attente, Some(Attente::Verifier)));
    }

    #[test]
    fn offline_installation_sends_no_application() {
        let mut a = App::new();
        a.en_ligne = false;
        assert!(a.configuration().applications.is_empty());
        a.en_ligne = true;
        assert!(!a.configuration().applications.is_empty());
    }
}
