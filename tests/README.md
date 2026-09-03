# Validation avant diffusion

Aucune suite automatisée complète n’est actuellement fournie.

## Vérifications locales

- Vérifier la syntaxe des scripts avec `bash -n`.
- Valider le JSON de la politique Brave.
- Tester `auxi --help`, `auxi status` et le refus d’une opération DEB sans sudo.
- Compiler le centre sur Debian 13 amd64 et vérifier son lancement graphique.

## Validation en machine virtuelle

1. Construire une ISO depuis un environnement maîtrisé.
2. Tester le démarrage live en BIOS puis UEFI.
3. Vérifier COSMIC, le réseau et l’ouverture de Calamares.
4. Installer sur un disque virtuel jetable avec un compte autre que `auxinux`.
5. Retirer l’ISO, redémarrer et ouvrir une session avec ce compte.
6. Vérifier que le compte live, son sudo sans mot de passe et l’autologin ont disparu.
7. Tester recherche, installation, mise à jour et désinstallation Flatpak et DEB.
8. Vérifier les langues, le son et les paramètres du bureau.

Consigner la version de l’ISO, les résultats et les échecs avant diffusion.
