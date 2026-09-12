# Limites connues

## État de la 0.2.0

Ce qui a changé le 2026-09-12 et n'est **pas encore validé en machine
virtuelle** :

- le bureau est **KDE Plasma** (Debian 13, 6.3.6) et non plus COSMIC ;
- l'écran de connexion est **SDDM** (greeter X11, session Wayland) ;
- la **protection au démarrage** (compteur, console de secours, restauration
  automatique) est neuve et couverte par des tests de logique seulement ;
- les **profils d'usage** sont neufs, et aucune mesure de performance n'a été
  faite ;
- l'**installateur maison** n'existe pas : la 0.2.0 garde Calamares.

Aucune installation graphique complète n'a jamais été menée sur ce projet, quelle
que soit la version. C'est le jalon bloquant.

## Construction

- `check-rootfs.sh` s’exécute avant la compression du squashfs et **arrête la
  construction** si une fonction annoncée est absente de l’image (modèle
  snapper, hook d’instantané, grub-btrfs, hook initramfs, zenity, wine/i386,
  détournement APT, compte live, session Plasma, SDDM et **la session nommée
  dans l’autologin du live**, protection au démarrage, profil d’usage, réglages
  de vie privée). C’est le contrôle qui aurait intercepté
  l’absence de rollback sur tous les systèmes installés.
- Le rootfs est bootstrappé depuis le miroir Debian d'AuxiNux, qui **ne
  miroite pas i386** (vérifié : `binary-i386/Packages.xz` répond 404). Les
  paquets 32 bits viennent donc de `deb.debian.org`, par un dépôt épinglé à
  `Architectures: i386`. Deux conséquences : une version amd64 et une version
  i386 d'une même bibliothèque peuvent diverger si le miroir prend du retard
  (apt refuse alors l'installation multiarch), et un utilisateur qui relance
  `install-auxinux-sources-DEB.sh` désactive ce dépôt — le script désactive
  toute source contenant `debian.org`. À supprimer le jour où le miroir portera
  i386.
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
- Le Center est en **libcosmic sur un bureau Plasma** : il fonctionne (iced +
  winit + wgpu, aucune dépendance à COSMIC) mais **ne suit pas le thème
  Breeze**. Il aura l'air étranger jusqu'à une interface Kirigami/QML.
- Le fond d'écran par défaut est écrit dans
  `/etc/xdg/plasma-org.kde.plasma.desktop-appletsrc`, qui suppose que la vue
  bureau porte le numéro de containment 1 dans la disposition par défaut de
  Plasma. Si ce numéro change en amont, l'utilisateur voit le fond d'écran de
  Breeze — pas un bureau cassé, mais le branding est perdu sans avertissement.
- Le thème SDDM est surchargé par `theme.conf.user` dans le thème
  `debian-breeze`. Si Debian renomme ce thème, l'écran de connexion revient à
  son apparence d'origine, silencieusement (`configure-branding.sh` émet un
  avertissement dans le journal de construction).

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

- `auxinux-welcome` **ne ferme plus jamais la session**. Il proposait
  auparavant de la redémarrer pour appliquer la langue et exécutait
  `loginctl terminate-user`. Or la session live est ouverte par le bloc
  `[initial_session]` de greetd, qui ne s’applique **qu’une seule fois, au
  démarrage** : la terminer jetait l’utilisateur hors du live sans retour —
  au mieux un écran de connexion pour un compte dont il ignore le mot de
  passe, au pire un écran noir. C’est la panne « je choisis la langue, ça
  quitte l’interface et reste noir ».
- La langue est désormais appliquée sans rien fermer : `environment.d` pour
  les sessions suivantes, `systemctl --user import-environment` et
  `dbus-update-activation-environment` pour tout ce qui est lancé ensuite,
  **l’installateur compris** (`auxinux-install-launcher` relit le choix et le
  passe à Calamares).
- Limite assumée : le panneau COSMIC **déjà affiché** garde sa langue jusqu’à
  la session suivante. C’est dit explicitement dans la fenêtre d’accueil,
  plutôt que payé par une déconnexion.

## Démarrage du système installé

- **Le mode d’échec « écran noir infini » est corrigé à la racine.** Reproduit
  en VM le 2026-09-09 : `cosmic-greeter.service` déclare
  `Conflicts=getty@tty1.service` (il arrête la console texte) et
  `Restart=always` avec `StartLimitBurst=5`. Si le greeter échoue cinq fois,
  systemd renonce (`start-limit-hit`) et **plus rien ne reprend tty1** :
  l’écran est noir à 100 %, définitivement, sans un seul message — alors que
  le système tourne (vérifié : 14 services actifs, connexion possible par la
  console série). L’utilisateur en conclut que le démarrage ne se termine
  jamais.
- Correctif : le drop-in
  `etc/systemd/system/cosmic-greeter.service.d/50-auxinux-fallback.conf` ajoute
  `OnFailure=getty@tty1.service`. Vérifié en VM : greeter en échec →
  invite de connexion à l’écran au lieu du noir.
- `quiet splash` a été retiré du live **et** du système installé (`grubcfg.conf`
  et `/etc/default/grub`). `splash` était inerte — plymouth n’est pas dans
  l’image — et `quiet` masquait tout, y compris la raison d’un démarrage qui
  n’aboutit pas. `check-rootfs.sh` refuse désormais une image qui les
  réintroduirait sans plymouth.
- Les montages non essentiels (`/.snapshots`, `/var/lib/flatpak`, `/var/tmp`,
  `/var/cache`, `/var/log`, `/swap` et l’espace d’échange) passent en `nofail`
  au nettoyage post-installation. Sans cela, un seul d’entre eux absent faisait
  basculer systemd en mode urgence ; et comme le compte root n’a pas de mot de
  passe (`setRootPassword: false`), `sulogin` refuse la console et le démarrage
  s’arrête là. `/`, `/home` et `/boot/efi` restent volontairement bloquants.
- La commande de session greetd est celle d’**amont** (`cosmic-greeter-start`)
  et non plus la forme héritée de Pop!\_OS. Le script amont purge l’état
  résiduel de `CosmicSettingsDaemon` avant de lancer le compositeur.
- `accounts-daemon` échouait à **chaque** démarrage
  (`226/NAMESPACE`, `/run/systemd/seats: No such file or directory`) : course
  avec `systemd-logind`. Un drop-in ordonne les deux ; le système passe de
  `degraded` à `running`.

## Amorcabilite du systeme installe

- **Panne rapportee le 2026-09-10** : une installation menee jusqu'au bout,
  sans la moindre erreur affichee, produit au redemarrage
  `error: premature end of file /@/boot/vmlinuz-7.1.12-auxinuxos-amd64`.
  GRUB trouve le noyau (le chemin et le sous-volume `@` sont corrects) mais ne
  peut pas en lire tout le contenu. **Cause premiere non encore identifiee.**
- Hypotheses **eliminees par test en VM**, pas par raisonnement :
  1. *Compression zstd* — un noyau recompresse en zstd (4 extents `encoded`)
     demarre sans probleme ; `btrfs.mod` declare `zstd` en dependance, le
     decompresseur est donc embarque.
  2. *Contenu ecrit par l'installation* — une installation reconstituee
     fidelement (btrfs vierge monte en `compress=zstd:1`, copie depuis le vrai
     squashfs, `grub-install` et `update-grub` en chroot) demarre jusqu'a
     l'ecran de connexion.
  3. *Arret brutal* — ecrire sur la cible puis couper par `reboot -ff` sans
     `sync` ni demontage ne casse pas le demarrage : BTRFS revient a un etat
     coherent.
  4. *GRUB signe Debian sans zstd* — `grubx64.efi.signed` embarque bien
     `btrfs`, `zstd`, `lzopio` et `gzio`.
- Pistes restantes, a departager avec les donnees de la machine touchee :
  cible saturee en fin d'installation (ecritures differees perdues),
  demarrage **BIOS legacy** (chemin `i386-pc`, jamais teste ici), ou
  specificite de l'hyperviseur.
- **Garde-fou ajoute** (`shellprocess@verifyboot`, dernier job avant `umount`) :
  `installer/verify-installed-boot.sh` fait `sync` puis vide le cache
  (`drop_caches`) et **relit le noyau et l'initrd depuis le disque**, comme le
  fera GRUB. Il verifie aussi que chaque entree de `grub.cfg` designe un
  fichier existant et qu'il reste de la place. C'est le seul job de la sequence
  autorise a **faire echouer l'installation** : mieux vaut une erreur affichee
  pendant que l'utilisateur est devant l'ecran qu'une machine morte au
  redemarrage.
- Le nettoyage post-installation ne masque plus les echecs de purge de
  `live-boot`/Calamares ni de regeneration de l'initramfs : ils sont ecrits sur
  stderr, donc dans le journal de l'installateur.

## Installation et validation

- **Ce qui est validé en VM** (`tests/vm-install-boot.sh`, 2026-09-09) : une
  installation reconstituée démarre de bout en bout — GRUB EFI, racine BTRFS
  sur `subvol=@`, `graphical.target` atteint, écran de connexion COSMIC
  affiché, `snapper` configuré avec l’instantané « Installation initiale »,
  `systemctl is-system-running` = `running`.
- **Ce qui ne l’est pas** : les modules Calamares eux-mêmes. Le banc part du
  rootfs de construction, pas du squashfs, et pose GRUB à la main. Le parcours
  Calamares graphique → installation → redémarrage reste à valider sur une
  machine réelle.
- Le module Calamares `displaymanager` **ne connaît pas greetd** (sa liste se
  limite à slim, sddm, lightdm, gdm, mdm, lxdm, kdm). Il sort proprement sans
  rien faire — vérifié dans son `main.py` —, mais **l’option « connexion
  automatique » de l’installateur reste donc sans effet**. Le lien
  `display-manager.service` est rétabli par le nettoyage post-installation.
- Le sous-volume `/@swap` manquait dans `btrfsSubvolumes` : `btrfsSwapSubvol`
  dit seulement où créer le sous-volume, c’est `btrfsSubvolumes` qui produit
  les lignes de `/etc/fstab`. Résultat, `@swap` n’était jamais monté et
  `swapon` échouait à chaque démarrage. Corrigé.
- Le nettoyage masque encore les erreurs de suppression du compte live, de
  purge des paquets live et de régénération de l’initramfs.
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
