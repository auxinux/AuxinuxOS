# Bilingue Canada

AuxiNux OS EN 0.1-BETA vise le Canada et doit fournir un environnement
francais/anglais pret a l'emploi.

## Defaut beta

- langue par defaut: francais Canada (`fr_CA.UTF-8`);
- langue de secours: anglais Canada, puis anglais generique;
- formats regionaux: Canada francophone;
- dictionnaires: francais et anglais Canada quand disponibles.

## LiveCD

Le LiveCD lance automatiquement `auxinux-welcome` apres l'autologin COSMIC.
L'assistant demande d'abord:

- Francais;
- English.

Le choix est applique au profil live via `~/.config/plasma-localerc`, puis une
page de bienvenue explique la philosophie AuxiNuxOS dans la langue choisie.
Cet assistant est un artefact live et doit etre retire du systeme installe.

## Installation

L'installateur devra laisser choisir clairement:

- Francais Canada;
- English Canada.

Le choix de langue doit etre applique a l'utilisateur installe, pas seulement
au live.

Le choix de langue utilise encore des fichiers Plasma ; son application à
la session COSMIC reste à valider (voir `limitations.md`).
