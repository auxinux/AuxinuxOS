# Limites connues de la bêta

## Construction

- Le cache COSMIC conserve `packages-before.txt` entre les builds. Après une
  modification des paquets de base, sa comparaison avec le nouvel état peut
  classer des paquets essentiels parmi ceux à purger. Ce cache doit être
  invalidé avant une reconstruction concernée.
- Le centre d’applications est recompilé seulement si son binaire est absent.
  Après une modification des sources, lancer explicitement son `build.sh`.
- Les dépendances QML sont installées avec une erreur non bloquante : vérifier
  leur présence et le lancement du centre dans l’image finale.

## Applications

- La fusion des résultats Flatpak et DEB ne conserve pas un identifiant par
  source. Choisir DEB pour une fiche Flatpak peut transmettre le mauvais nom
  de paquet.
- Les opérations du centre sont synchrones et peuvent figer l’interface.
- Les opérations DEB lancées depuis le centre nécessitent une validation de
  l’authentification graphique et des confirmations APT.
- `auxi update --flatpak` ignore le code d’échec de Flatpak.
- L’assistant de langue live configure encore des fichiers Plasma ; son
  intégration à COSMIC reste à valider.

## Installation et validation

- Le nettoyage masque les erreurs de suppression du compte live, de purge
  des paquets live et de régénération de l’initramfs.
- Le fichier d’autodémarrage de l’installateur reste dans la cible installée.
- Le parcours Calamares graphique → installation → redémarrage sans ISO →
  ouverture de session n’est pas encore validé pour l’image finale.
- Il n’existe pas de suite automatisée de tests du backend Rust.

## Points de sécurité à vérifier

- Le script temporaire exécuté via `pkexec` utilise un nom prévisible dans
  le répertoire temporaire ; sa création doit être durcie.
- La politique APT est une aide d’utilisation, pas une barrière de sécurité.
- Vérifier les permissions, l’absence du compte live et de son accès sudo
  sans mot de passe sur le système installé.
