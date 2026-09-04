# Limites connues de la bêta

## Construction

- `check-rootfs.sh` s’exécute avant la compression du squashfs et **arrête la
  construction** si une fonction annoncée est absente de l’image (modèle
  snapper, hook d’instantané, grub-btrfs, hook initramfs, zenity, wine/i386,
  détournement APT, compte live). C’est le contrôle qui aurait intercepté
  l’absence de rollback sur tous les systèmes installés.
- Le cache COSMIC conserve `packages-before.txt` entre les builds. Une
  empreinte SHA-256 des listes de paquets est stockée à côté du cache :
  `build-cosmic-source.sh` invalide ce fichier automatiquement dès que les
  listes changent.
- `rustup-init` est téléchargé puis **épinglé à la première construction**
  (`rustup-init.sha256` dans le cache) et exigé identique ensuite. Une montée
  de version amont légitime demande de supprimer ce fichier après vérification.
  Aucune empreinte de confiance n’est codée en dur : la recopier depuis ce que
  sert le site ne vérifierait rien.
- `--force` refuse d’effacer un répertoire de construction qui porte encore des
  montages, au lieu de traverser un `/dev` monté et d’effacer celui de l’hôte.
- Le centre d’applications est recompilé seulement si son binaire est absent.
  Après une modification des sources, lancer explicitement son `build.sh`.
- L’hôte de build a besoin de `libxkbcommon-dev libwayland-dev libudev-dev
  libinput-dev`. Qt6 et KF6 ne sont plus nécessaires.

## Applications et centre de contrôle

- Le centre a été reconstruit en libcosmic (0.2). Sa logique et **la couche
  d’interface passent `cargo check`**, mais l’application **n’a encore jamais
  été lancée graphiquement**.
- `Cargo.lock` épingle `tinyvec` en 1.8.1 : la version 1.13.0, tirée
  transitivement par la pile de rendu de texte, ne compile pas.
- La sortie des opérations longues n’est pas diffusée en direct : seul le
  résultat final s’affiche. Un gros téléchargement paraît donc immobile, même
  si l’interface reste réactive.
- La fiche détaillée AppStream (icônes haute définition, captures d’écran,
  description) existe dans le backend mais n’est pas branchée sur l’interface.
- La correspondance Flatpak/DEB reste **heuristique** (nom et app-id). Chaque
  fiche porte un identifiant par source, mais l’appariement lui-même peut
  encore rapprocher à tort deux logiciels homonymes.
- `auxi update --flatpak` ignore le code d’échec de Flatpak.
- Le fond d’écran AuxiNux est installé dans `/usr/share/backgrounds/auxinuxos`
  et **sélectionnable**, mais il n’est pas appliqué par défaut : cela demande
  un fichier de configuration `cosmic-bg` non encore vérifié sur une session
  réelle.

## Rollback système

- Le parcours BTRFS complet n’est pas encore validé en machine virtuelle :
  formatage par Calamares, création des sept sous-volumes, écriture du
  `/etc/fstab`, sous-menu GRUB de restauration, puis restauration effective.
- Le **hook initramfs qui rend inscriptible un instantané démarré depuis GRUB**
  (`auxinux-snapshot-overlay`) est écrit et sa condition de déclenchement est
  étroite — le seul paramètre `auxinux.snapshot=1`, absent d’un démarrage
  normal — mais il **n’a jamais été éprouvé sur un démarrage réel**. C’est le
  point à valider en priorité : sans lui, le menu de restauration ne mène nulle
  part ; avec un déclenchement erroné, il modifierait un démarrage normal.
- **BTRFS + LUKS + grub-btrfs** n’est pas testé. GRUB doit déverrouiller le
  volume avant de lire `/.snapshots`.
- Le fichier d’échange sur `@swap` repose sur `btrfsSwapSubvol` de Calamares.
  Ni la création ni la mise en veille prolongée ne sont vérifiées.
- Les limites d’espace (`SPACE_LIMIT`, `FREE_LIMIT`) exigent les quotas BTRFS.
  `snapper setup-quota` est appelé à l’installation ; **son effet réel n’a pas
  été mesuré**, et un échec n’est qu’un avertissement.
- Un rollback ne restaure ni `/home`, ni les applications Flatpak, ni les
  journaux — c’est délibéré (voir `rollback.md`).
- La restauration passe par un instant où `@` a été déplacé et où le nouveau
  `@` n’existe pas encore. La reprise sur échec est implémentée et testée, mais
  une coupure de courant à cet instant précis laisse la machine sans racine
  amorçable, réparable seulement depuis un média live.
- `grub-btrfs` **n’existe pas dans Debian 13** : il est installé depuis les
  sources à un commit épinglé. Dépendance externe à resuivre à chaque montée
  de version.

## Instantané avant transaction DEB

- L’instantané n’est plus posé par `auxi` mais par un hook `DPkg::Pre-Invoke`
  et `DPkg::Post-Invoke` : il couvre désormais **tous** les chemins vers dpkg.
  Couvert par `tests/test-apt-snapshot-hook.sh` avec des stubs ; **jamais
  éprouvé contre un vrai apt**.
- Le hook sort toujours en code 0 par conception. Un échec de snapper laisse
  donc passer la transaction **sans filet**, en le signalant seulement sur la
  sortie standard d’apt — que peu d’utilisateurs lisent.
- La description de l’instantané est la ligne de commande du processus
  appelant, tronquée à 180 caractères.

## Dépendances tierces fragiles

- Le dépôt OBS `home:nomispaz:debian:cosmic-desktop` est la seule source APT de
  COSMIC pour Trixie, et il **a cassé entre juillet et septembre 2026**. Les
  paquets nécessaires sont énumérés explicitement au lieu de passer par le
  métapaquet `cosmic-session`.
- `grub-btrfs` est installé depuis GitHub à un commit épinglé.

## Applications Windows et jeux

- **Aucune** de cette couche n’a été testée sur matériel : ni Wine 32 bits, ni
  Bottles, ni Steam/Proton, ni Heroic, ni Lutris.
- Les formats `.msi` et `.lnk`, associés à l’assistant, passent maintenant par
  `msiexec` et `start /unix` (couvert par les tests à stubs, pas par un essai
  réel).
- L’activation de i386 alourdit le rootfs et l’ISO. L’impact n’a pas été mesuré.
- Les Flatpak de jeu ne sont pas embarqués : la première installation exige une
  connexion et plusieurs Go de téléchargement.

## Fluidité

- `zram-tools`, `systemd-oomd` et `fstrim.timer` sont configurés et activés,
  mais **aucune mesure n’a été faite sur matériel réel**.
- `systemd-oomd` exige cgroup v2, actif par défaut sur Debian 13. À reconfirmer
  sur l’image.
- Le seuil `ManagedOOMMemoryPressureLimit=50%` n’a pas été éprouvé.

## Accueil live

- `auxinux-welcome` a été réécrit pour zenity et écrit la langue dans
  `~/.config/environment.d`. **Non vérifié sur une session COSMIC réelle** :
  reste à confirmer que le gestionnaire de session lit bien `environment.d`
  dans une session lancée par greetd, sans quoi la langue ne s’appliquera qu’au
  redémarrage de session.

## Installation et validation

- Le nettoyage masque encore les erreurs de suppression du compte live, de
  purge des paquets live et de régénération de l’initramfs.
- Le parcours Calamares graphique → installation → redémarrage sans ISO →
  ouverture de session n’est pas encore validé pour l’image finale.
- Le compte live utilise l’UID 60000 pour que le compte créé par Calamares
  obtienne bien l’UID 1000. **À vérifier sur une installation réelle.**
- La suite de tests couvre : choix d’identifiant par source, agrégation des
  gravités, analyse du CSV de snapper, validateurs de sources, rollback,
  assistant Windows, hook d’instantané, nettoyage post-installation et
  configuration du rollback. Aucun test ne couvre les modules qui appellent
  réellement `flatpak`, `apt-cache` ou `pkexec`.

## Points de sécurité

- Les opérations privilégiées du centre passent par
  `/usr/libexec/auxinux/auxinux-source-helper`, avec son action polkit
  dédiée : plus aucun script n’est écrit dans un répertoire temporaire avant
  d’être exécuté en root.
- Les clés des dépôts connus sont téléchargées en HTTPS depuis le domaine de
  l’éditeur, vérifiées comme clés OpenPGP valides, puis **épinglées** : un
  changement ultérieur est refusé. Il ne s’agit **pas** d’une vérification par
  empreinte de confiance connue d’avance — le premier téléchargement reste un
  point de confiance.
- La politique APT est une aide d’utilisation, pas une barrière de sécurité.
- Vérifier, sur une installation réelle, l’absence du compte live, de son sudo
  sans mot de passe, de l’autodémarrage de l’installateur et de Calamares.
