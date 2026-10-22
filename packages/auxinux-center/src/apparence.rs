//! Apparence du Center dans la session AuxiNux Shell (XDG_CURRENT_DESKTOP=AuxiNux).
//!
//! PROBLEME (2026-10-22, aporler: « le Center est bof » a cote de Dolphin): le
//! Center gardait le theme COSMIC par defaut -- gris bleutes, accent turquoise,
//! boutons en pilule, police Open Sans et sa propre barre de titre -- alors que
//! le shell et les applications KDE de la session ont des gris neutres, l'accent
//! choisi par l'utilisateur, Inter et la barre de titre de labwc.
//!
//! Le shell ecrit deja, pour la session seulement, un kdeglobals verrouille
//! ([$i]) dans $XDG_RUNTIME_DIR/auxinux-shell/kde, place en tete de
//! XDG_CONFIG_DIRS: c'est lui que lisent Dolphin et les autres. Le Center lit
//! les memes fichiers avec les memes regles que KConfig, sans contrat nouveau
//! avec le shell: un changement de theme (clair/sombre au coucher du soleil,
//! accent) l'atteint de la meme facon.
//!
//! Ce module ne depend pas de libcosmic (feature "gui"): il est teste partout.
#![cfg_attr(not(feature = "gui"), allow(dead_code))]

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::SystemTime;

/// Couleur sRGB 8 bits.
pub type Rgb = [u8; 3];

/// Ce que le Center reprend de la session.
#[derive(Clone, Debug, PartialEq)]
pub struct Apparence {
    pub sombre: bool,
    pub fond: Rgb,
    pub carte: Rgb,
    pub texte: Rgb,
    pub accent: Rgb,
    pub negatif: Option<Rgb>,
    pub positif: Option<Rgb>,
    pub neutre: Option<Rgb>,
    /// Famille de la police d'interface (taille ignoree: celle de libcosmic).
    pub police: Option<String>,
}

/// Session AuxiNux Shell? (XDG_CURRENT_DESKTOP peut etre une liste « A:B »).
pub fn session_auxinux() -> bool {
    std::env::var("XDG_CURRENT_DESKTOP")
        .map(|v| v.split(':').any(|d| d == "AuxiNux"))
        .unwrap_or(false)
}

/// Fichiers kdeglobals, du moins prioritaire au plus prioritaire, comme
/// KConfig: les dossiers systeme de XDG_CONFIG_DIRS en partant du dernier,
/// puis celui de l'utilisateur.
pub fn fichiers() -> Vec<PathBuf> {
    let mut dirs = crate::system::xdg_dirs("XDG_CONFIG_HOME", ".config", "XDG_CONFIG_DIRS", "/etc/xdg");
    // xdg_dirs: utilisateur d'abord, puis systeme par priorite decroissante.
    let user = if dirs.is_empty() { None } else { Some(dirs.remove(0)) };
    dirs.reverse();
    dirs.extend(user);
    dirs.into_iter().map(|d| d.join("kdeglobals")).collect()
}

/// Empreinte des fichiers (dates de modification): change quand le shell
/// recrit son kdeglobals.
pub fn empreinte(fichiers: &[PathBuf]) -> Vec<Option<SystemTime>> {
    fichiers
        .iter()
        .map(|f| std::fs::metadata(f).and_then(|m| m.modified()).ok())
        .collect()
}

/// Fusion des fichiers selon KConfig: un fichier plus prioritaire remplace
/// une valeur, sauf si elle est immuable -- cle « nom[$i]=… » ou groupe
/// « [Groupe][$i] ». C'est ce qui fait gagner le kdeglobals de la session
/// sur ~/.config/kdeglobals (celui de Plasma).
pub fn fusionner(textes: &[String]) -> HashMap<(String, String), String> {
    let mut valeurs: HashMap<(String, String), (String, bool)> = HashMap::new();
    for texte in textes {
        let mut groupe = String::new();
        let mut groupe_fige = false;
        for ligne in texte.lines() {
            let ligne = ligne.trim();
            if ligne.is_empty() || ligne.starts_with('#') {
                continue;
            }
            if ligne.starts_with('[') {
                groupe_fige = ligne.ends_with("[$i]");
                let nom = ligne.strip_suffix("[$i]").unwrap_or(ligne);
                groupe = nom.trim_start_matches('[').trim_end_matches(']').to_string();
                continue;
            }
            let Some((cle, valeur)) = ligne.split_once('=') else { continue };
            let cle = cle.trim();
            let fige = groupe_fige || cle.ends_with("[$i]");
            let cle = cle.strip_suffix("[$i]").unwrap_or(cle).to_string();
            let entree = (groupe.clone(), cle);
            if valeurs.get(&entree).map(|(_, f)| *f).unwrap_or(false) {
                continue;
            }
            valeurs.insert(entree, (valeur.trim().to_string(), fige));
        }
    }
    valeurs.into_iter().map(|(k, (v, _))| (k, v)).collect()
}

fn rgb(valeur: &str) -> Option<Rgb> {
    let parts: Vec<u8> = valeur
        .split(',')
        .take(3)
        .map(|p| p.trim().parse::<u8>())
        .collect::<Result<_, _>>()
        .ok()?;
    (parts.len() == 3).then(|| [parts[0], parts[1], parts[2]])
}

fn luminance([r, g, b]: Rgb) -> f32 {
    (0.2126 * r as f32 + 0.7152 * g as f32 + 0.0722 * b as f32) / 255.0
}

/// Apparence tiree des valeurs fusionnees; None sans couleurs de fenetre.
pub fn depuis_valeurs(v: &HashMap<(String, String), String>) -> Option<Apparence> {
    let get = |g: &str, k: &str| v.get(&(g.to_string(), k.to_string())).map(String::as_str);
    let couleur = |g: &str, k: &str| get(g, k).and_then(rgb);
    let fond = couleur("Colors:Window", "BackgroundNormal")?;
    let accent = couleur("General", "AccentColor")
        .or_else(|| couleur("Colors:Selection", "BackgroundNormal"))?;
    let police = get("General", "font")
        .and_then(|f| f.split(',').next())
        .map(str::trim)
        .filter(|f| !f.is_empty())
        .map(str::to_string);
    Some(Apparence {
        sombre: luminance(fond) < 0.5,
        fond,
        carte: couleur("Colors:Button", "BackgroundNormal").unwrap_or(fond),
        texte: couleur("Colors:Window", "ForegroundNormal").unwrap_or(if luminance(fond) < 0.5 {
            [243, 243, 243]
        } else {
            [27, 27, 27]
        }),
        accent,
        negatif: couleur("Colors:View", "ForegroundNegative"),
        positif: couleur("Colors:View", "ForegroundPositive"),
        neutre: couleur("Colors:View", "ForegroundNeutral"),
        police,
    })
}

/// Apparence de la session AuxiNux, ou None hors de cette session (le Center
/// garde alors son theme habituel).
pub fn lire() -> Option<Apparence> {
    if !session_auxinux() {
        return None;
    }
    let textes: Vec<String> = fichiers()
        .iter()
        .filter_map(|f| std::fs::read_to_string(f).ok())
        .collect();
    depuis_valeurs(&fusionner(&textes))
}

#[cfg(test)]
mod tests {
    use super::*;

    const PLASMA: &str = "[General]\nfont=Noto Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nAccentColor=61,174,233\n\
        [Colors:Window]\nBackgroundNormal=239,240,241\nForegroundNormal=35,38,41\n";
    const SESSION: &str = "[General]\nAccentColor[$i]=239,138,18\nfont[$i]=Inter Variable,10,-1,5,400\n\n\
        [Colors:Window][$i]\nBackgroundNormal=32,32,32\nForegroundNormal=243,243,243\n\
        [Colors:Button][$i]\nBackgroundNormal=45,45,45\n[Colors:View][$i]\nForegroundNegative=218,68,83\n";

    #[test]
    fn la_session_verrouillee_gagne_sur_plasma() {
        // Ordre de fichiers(): systeme (session) puis utilisateur (Plasma).
        let v = fusionner(&[SESSION.to_string(), PLASMA.to_string()]);
        let a = depuis_valeurs(&v).unwrap();
        assert!(a.sombre);
        assert_eq!(a.fond, [32, 32, 32]);
        assert_eq!(a.carte, [45, 45, 45]);
        assert_eq!(a.accent, [239, 138, 18]);
        assert_eq!(a.negatif, Some([218, 68, 83]));
        assert_eq!(a.police.as_deref(), Some("Inter Variable"));
    }

    #[test]
    fn sans_verrou_l_utilisateur_gagne() {
        let systeme = "[Colors:Window]\nBackgroundNormal=32,32,32\n[General]\nAccentColor=1,2,3\n";
        let v = fusionner(&[systeme.to_string(), PLASMA.to_string()]);
        let a = depuis_valeurs(&v).unwrap();
        assert!(!a.sombre);
        assert_eq!(a.accent, [61, 174, 233]);
        assert_eq!(a.police.as_deref(), Some("Noto Sans"));
    }

    #[test]
    fn sans_couleurs_rien() {
        assert!(depuis_valeurs(&fusionner(&["[General]\nfont=X\n".to_string()])).is_none());
    }
}
