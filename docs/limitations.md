# Limites connues de la bêta

## Construction

- Le cache COSMIC conserve `packages-before.txt` entre les builds. Une
  empreinte SHA-256 des listes de paquets est désormais stockée à côté du
  cache : `build-cosmic-source.sh` invalide ce fichier automatiquement dès que
  les listes changent. Auparavant, l’oubli produisait une ISO amputée de
  fonctions entières sans le moindre message d’erreur.
- Le centre d’applications est recompilé seulement si son binaire est absent.
  Après une modification des sources, lancer explicitement son `build.sh`.
- L’hôte de build a besoin de nouvelles dépendances depuis la 0.2 du centre :
  `libxkbcommon-dev libwayland-dev libudev-dev libinput-dev`. En contrepartie,
  Qt6 et KF6 ne sont plus nécessaires.

## Applications et centre de contrôle

- Le centre a été reconstruit en libcosmic (0.2). **Sa compilation complète n’a
  pas encore été effectuée sur l’hôte de build** : la logique est vérifiée par
  `cargo test --no-default-features`, mais la couche d’interface exige un
  premier passage de compilation sur une machine disposant de
  `libxkbcommon-dev` et `libwayland-dev`. Voir `packages/auxinux-center/README.md`.
- `Cargo.lock` épingle `tinyvec` en 1.8.1 : la version 1.13.0, tirée
  transitivement par la pile de rendu de texte, ne compile pas. À lever quand
  la dépendance sera corrigée en amont.
- La sortie des opérations longues n’est pas diffusée en direct : seul le
  résultat final s’affiche. Un gros téléchargement paraît donc immobile, même
  si l’interface reste réactive.
- La fiche détaillée AppStream (icônes haute définition, captures d’écran,
  description) existe dans le backend mais n’est pas encore branchée sur
  l’interface.
- La correspondance Flatpak/DEB reste **heuristique** (nom et app-id). Le
  mauvais paquet n’est plus transmis à apt — chaque fiche porte désormais un
  identifiant par source — mais l’appariement lui-même peut encore rapprocher
  à tort deux logiciels homonymes.
- Les opérations DEB lancées depuis le centre nécessitent une validation de
  l’authentification graphique et des confirmations APT.
- `auxi update --flatpak` ignore le code d’échec de Flatpak.
- L’assistant de langue live configure encore des fichiers Plasma ; son
  intégration à COSMIC reste à valider.

## Rollback système

- Le parcours BTRFS complet n’est pas encore validé en machine virtuelle :
  formatage par Calamares, création des sept sous-volumes, écriture du
  `/etc/fstab`, sous-menu GRUB de restauration, puis restauration effective.
- **BTRFS + LUKS + grub-btrfs** n’est pas testé. GRUB doit déverrouiller le
  volume avant de lire `/.snapshots` ; à confirmer avant toute ISO chiffrée.
- Le fichier d’échange sur `@swap` repose sur `btrfsSwapSubvol` de Calamares.
  Ni la création ni la mise en veille prolongée ne sont vérifiées.
- `tests/test-rollback.sh` valide la logique de restauration avec des
  commandes BTRFS simulées, pas le comportement réel de BTRFS.
- Un rollback ne restaure ni `/home`, ni les applications Flatpak, ni les
  journaux — c’est délibéré (voir `rollback.md`), mais cela signifie qu’une
  panne causée par une application Flatpak ne sera pas corrigée par un
  rollback système.
- La restauration passe par un instant où `@` a été déplacé et où le nouveau
  `@` n’existe pas encore. La reprise sur échec est implémentée et testée,
  mais une coupure de courant à cet instant précis laisse la machine sans
  racine amorçable, réparable seulement depuis un média live.
- `grub-btrfs` **n'existe pas dans Debian 13** : il est installé depuis les
  sources à un commit épinglé (voir `rollback.md`). C'est une dépendance
  externe supplémentaire, à resuivre à chaque montée de version.
- La vérification de disponibilité des paquets doit se faire avec
  `apt-cache policy` sur l'hôte de build : `packages.debian.org` a renvoyé un
  faux positif pour `grub-btrfs`.

## Dépendances tierces fragiles

- Le dépôt OBS `home:nomispaz:debian:cosmic-desktop` est la seule source APT de
  COSMIC pour Trixie, et il **a cassé entre juillet et septembre 2026** : il
  publie `cosmic-session`, qui dépend de `cosmic-applets`, absent du dépôt.
  Les paquets nécessaires sont désormais énumérés explicitement au lieu de
  passer par ce métapaquet. Un dépôt communautaire peut casser à tout moment ;
  ces paquets ne servent qu'à tirer les dépendances d'exécution, les binaires
  venant de la compilation depuis les sources officielles.
- `grub-btrfs` est installé depuis GitHub à un commit épinglé.

## Applications Windows et jeux

- **Aucune** de cette couche n’a été testée : ni Wine 32 bits après l’activation
  de i386, ni Bottles, ni Steam/Proton, ni Heroic, ni Lutris.
- L’activation de i386 alourdit le rootfs et l’ISO. L’impact n’a pas été mesuré.
- L’assistant `.exe` suppose `zenity` présent. Il sort désormais en erreur
  explicite s’il manque, au lieu de retomber silencieusement sur une lecture au
  clavier — mais il faut confirmer que `zenity` est bien installé dans l’image.
- Les Flatpak de jeu ne sont pas embarqués : la première installation exige une
  connexion et plusieurs Go de téléchargement.

## Fluidité

- `zram-tools`, `systemd-oomd` et `fstrim.timer` sont configurés et activés,
  mais **aucune mesure n’a été faite sur matériel réel**. L’effet annoncé est
  attendu, pas vérifié.
- `systemd-oomd` exige cgroup v2, actif par défaut sur Debian 13. À reconfirmer
  sur l’image.
- Le seuil `ManagedOOMMemoryPressureLimit=50%` n’a pas été éprouvé : trop bas,
  il tuerait des applications pendant une charge légitime.

## Défaut ouvert : assistant d’accueil live

- `packages/welcome/auxinux-welcome` appelle encore `kdialog`, qui venait de
  Plasma et n’est plus installé depuis le passage à COSMIC. Il retombe alors
  sur une lecture au clavier — donc, en session graphique, **le sélecteur de
  langue du live n’affiche rien**. C’est le premier écran que voit
  l’utilisateur. `zenity` est désormais dans l’image ; la conversion du script
  reste à faire.

## Installation et validation

- Le nettoyage masque les erreurs de suppression du compte live, de purge
  des paquets live et de régénération de l’initramfs.
- Le fichier d’autodémarrage de l’installateur reste dans la cible installée.
- Le parcours Calamares graphique → installation → redémarrage sans ISO →
  ouverture de session n’est pas encore validé pour l’image finale.
- La suite de tests du backend Rust est partielle : elle couvre le choix
  d’identifiant par source, l’agrégation des gravités de santé et l’analyse du
  CSV de snapper, mais aucun des modules qui appellent `flatpak`, `apt-cache`
  ou `pkexec`.

## Points de sécurité à vérifier

- Le script temporaire exécuté via `pkexec` utilise un nom prévisible dans
  le répertoire temporaire ; sa création doit être durcie.
- La politique APT est une aide d’utilisation, pas une barrière de sécurité.
- Vérifier les permissions, l’absence du compte live et de son accès sudo
  sans mot de passe sur le système installé.
