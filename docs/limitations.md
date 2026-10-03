# Limites connues

## État de la 0.2.0

### Installation complète validée en machine virtuelle le 2026-09-29

Pour la première fois, une installation **Calamares graphique complète** a été
menée puis démarrée, en QEMU (UEFI, disque NVMe, TCG sans KVM), pilotée par
`tests/vm-driver.py` et prouvée par captures d'écran :

- parcours de l'installateur en français, fuseau **America/Toronto**, locale
  **fr_CA**, clavier **French (Canada)** proposés par défaut, aperçu du clavier
  affiché ;
- disque effacé, **les huit sous-volumes créés et montés** (`@`, `@home`,
  `@snapshots`, `@var_log`, `@var_cache`, `@var_tmp`, `@var_lib_flatpak`,
  `@swap`), instantané « Installation initiale » posé ;
- installation terminée sans erreur ;
- **la panne rapportée sur matériel réel a été reproduite à l'identique** avec
  l'ISO publiée le 2026-09-14 : `erreur : fin prématurée du fichier
  /@/boot/vmlinuz-7.2.5-auxinuxos-amd64`. Cause : un trou en fin de noyau (voir
  « Rollback système » plus bas). Corrigée, puis :
- menu GRUB du système installé, démarrage, **écran de connexion SDDM**,
  ouverture de la session **Plasma (Wayland)** avec le mot de passe choisi,
  `sudo`, **verrouillage et déverrouillage de l'écran** avec ce même mot de
  passe — tapé avec une touche dont le caractère diffère entre QWERTY US et
  « French (Canada) », pour prouver que les trois dispositions concordent ;
- second démarrage, `systemctl is-system-running` = `running`, protection au
  démarrage à zéro échec, snapper actif (instantanés au démarrage et horaires).

**Confirmé le même jour avec l'ISO reconstruite, publiée sous
`auxinuxos-0.2.0-20260929-amd64.iso`** : installation complète sans aucune
intervention, redémarrage par « Terminé » (média encore inséré), GRUB,
connexion, bureau, verrouillage/déverrouillage, second démarrage après coupure
brutale. L'ISO du 2026-09-14 a été retirée.

**Remplacée le 2026-10-02 par `auxinuxos-0.2.0-20261002-amd64.iso`**
(commit `9e23aa5`), et l'ISO du 2026-09-29 retirée. Validé en VM sur la
session live de cette ISO : fond d'écran AuxiNux, Discover absent de la barre
des tâches, raccourci du centre sur le bureau, boutons et icônes du centre,
« Actualiser les listes », système livré à jour. **L'installation complète
n'a pas été rejouée avec cette ISO** : ses changements ne touchent ni
Calamares ni l'amorçage, mais le parcours ci-dessus reste celui de l'ISO du
2026-09-29.

**Remplacée le même jour par `auxinuxos-0.2.0-20261002-2-amd64.iso`**
(commit `0f68113`) : le **socle minimal** — plus aucune application imposée —
et l'assistant de premier démarrage. Validé en VM par une **installation
complète** (Calamares, redémarrage, connexion) : l'assistant s'ouvre seul à la
première session, et les 12 étapes de la sélection par défaut réussissent avec
une seule autorisation. L'ISO précédente du 2026-10-02 a été retirée.

**Remplacée le 2026-10-03 par `auxinuxos-0.2.0-20261003-amd64.iso`**
(commit `c77235d`, sha256 `119b2286…97551cca`) : dans le centre de contrôle,
la recherche d'applications et la recherche de mises à jour affichent une
barre animée et l'étape en cours, et l'assistant se termine sur une page de
bilan (tout installé, ou ce qui a échoué et pourquoi, avec « Réessayer »).
Validée en VM (session live, Center ouvert, recherche). L'ISO 20261002-2 a été
retirée. Constat non corrigé : dans la VM, une recherche Flathub prend près de
deux minutes, et la toute première n'a rien trouvé (l'index AppStream
téléchargé n'a pas été installé).

**Remplacée le même jour par `auxinuxos-0.2.0-20261003-2-amd64.iso`**
(commit `c378d92`, sha256 `a0c3cbf2…c80d0d3c`) : la même image, plus
l'**installateur maison « Install NOW »**, entrée par défaut de GRUB. Validée
en VM par une installation complète sans intervention (UEFI, en ligne, sans
chiffrement, Firefox + Bottles) jusqu'au bureau du système installé.
L'ISO 20261003 a été retirée.

Reste à valider : le démarrage par le chemin UEFI de secours (`EFI/BOOT`, le
micrologiciel l'a bien choisi après suppression de l'entrée NVRAM, mais l'écran
obtenu n'a pas pu être capturé), le démarrage sur un instantané depuis le
sous-menu GRUB, une installation BIOS, une installation chiffrée (LUKS), et du
matériel réel.

### Validé en machine virtuelle le 2026-09-13

L'ISO `auxinuxos-0.2.0-20260913-amd64.iso` a été démarrée en QEMU (TCG, sans
KVM) et **photographiée toutes les minutes pendant 20 minutes** :

- le bureau **KDE Plasma** s'ouvre en session live (autologin SDDM), en français,
  avec le panneau, l'icône « Install AuxiNuxOS » et l'écran d'accueil ;
- le noyau `7.2.5-auxinuxos-amd64` démarre, `virtio-gpu` s'initialise ;
- le contrôle de configuration requise **bloque l'installation** quand la
  machine n'a pas de disque — vérifié, c'était le cas de la VM ;
- l'écran **ne noircit plus** après dix minutes (corrigé après l'avoir constaté
  sur la première image du jour).

C'est la première fois qu'une ISO de ce projet est prouvée par l'image jusqu'au
bureau.

### Secure Boot

**Non supporté. Il faut le désactiver dans le micrologiciel** (arbitrage du
2026-09-13).

Ce que les essais en VM ont établi, avec un OVMF portant les clés Microsoft
— c'est-à-dire la configuration d'usine de la plupart des portables :

| Étape | État |
|---|---|
| micrologiciel → `shimx64.efi.signed` | ✅ accepté (signé Microsoft) |
| shim → `gcdx64.efi.signed` | ✅ accepté (signé Debian) |
| GRUB → menu AuxiNuxOS | ✅ affiché, compte à rebours compris |
| GRUB → noyau `7.2.5-auxinuxos-amd64` | ❌ `error: bad shim signature` |

Le noyau est compilé par le projet et signé par personne. L'ISO embarque tout de
même la chaîne signée : sans elle, la machine répondait `No bootable option or
device was found` — l'utilisateur voyait sa clé USB purement ignorée, sans
aucune indication. Avec elle, il obtient un menu et un message qui nomme le
problème, et le chemin d'enrôlement d'une clé (MokManager, `mmx64.efi`) est déjà
en place si le projet décide un jour de signer son noyau.

Les trois sorties possibles, si la question est reprise :

1. **clé AuxiNux + enrôlement MOK** — un écran bleu au premier démarrage, une
   fois par machine ; suppose une clé privée gardée en lieu sûr et **chaque
   noyau publié signé** ;
2. **noyau Debian signé en second choix** — tout démarre sans rien faire, mais
   le noyau optimisé du projet n'est alors pas celui qui tourne ;
3. **statu quo** — désactiver Secure Boot.

### Ce qui reste non validé

Ce qui a changé le 2026-09-12 et n'est **pas encore validé en machine
virtuelle** :

- le bureau est **KDE Plasma** (Debian 13, 6.3.6) et non plus COSMIC ;
- l'écran de connexion est **SDDM** (greeter X11, session Wayland) ;
- la **protection au démarrage** (compteur, console de secours, restauration
  automatique) est neuve et couverte par des tests de logique seulement ;
- les **profils d'usage** sont neufs, et aucune mesure de performance n'a été
  faite ;
- l'**installateur maison** n'existe pas : la 0.2.0 garde Calamares.

(Le paragraphe qui disait « aucune installation graphique complète n'a jamais
été menée » est caduc depuis le 2026-09-29 : voir plus haut.)

## Construction

- `check-rootfs.sh` s’exécute avant la compression du squashfs et **arrête la
  construction** si une fonction annoncée est absente de l’image (modèle
  snapper, hook d’instantané, grub-btrfs, hook initramfs, zenity, wine/i386,
  détournement APT, compte live, session Plasma, SDDM et **la session nommée
  dans l’autologin du live**, protection au démarrage, profil d’usage, réglages
  de vie privée). C’est le contrôle qui aurait intercepté
  l’absence de rollback sur tous les systèmes installés.
- Le rootfs est bootstrappé depuis le miroir Debian d'AuxiNux, **i386 compris
  depuis le 2026-09-13** (67 026 paquets, index conforme au `Release` signé par
  Debian). Le contournement `deb.debian.org` a été retiré. Attention : l'ISO
  `auxinuxos-0.2.0-20260913-amd64.iso` **déjà publiée** a été construite AVANT
  ce changement, donc avec le contournement ; la prochaine construction est la
  première à valider le nouveau chemin.
- `--force` refuse d’effacer un répertoire de construction qui porte encore des
  montages, au lieu de traverser un `/dev` monté et d’effacer celui de l’hôte.
- Le centre d’applications est recompilé seulement si son binaire est absent.
  Après une modification des sources, lancer explicitement son `build.sh`.
- L’hôte de build a besoin de `libxkbcommon-dev libwayland-dev libudev-dev
  libinput-dev`. Qt6 et KF6 ne sont plus nécessaires.

## Installateur maison « Install NOW » (2026-10-02)

- **Disque entier seulement** : pas d’installation à côté de Windows ni dans
  une partition existante (arbitrage d’aporler pour cette version) ; le
  double démarrage reste possible par Calamares, depuis le bureau live.
- Validé en VM (UEFI, en ligne, disque **chiffré**) : installation, GRUB qui
  demande la phrase de passe une seule fois, bureau, applications choisies
  pendant l’installation. **Pas encore rejoué** : installation BIOS, hors
  ligne, Wi-Fi réel (la VM est en filaire), matériel réel.
- Le Wi-Fi est choisi dans l’installateur et recopié dans le système installé ;
  les réseaux d’entreprise (WPA-Entreprise) ne sont pas gérés.
- Le clavier choisi est appliqué à la console du live (`ckbcomp | loadkeys`).
  Si cela échoue, l’installateur le dit : le mot de passe pourrait alors être
  tapé avec une autre disposition que celle du système installé.

## Applications et centre de contrôle

- Le centre a été reconstruit en libcosmic (0.2). Validé en VM sous Plasma le
  2026-10-02 : fenêtre et icônes, page Mises à jour, mise à jour complète du
  système (18 paquets) avec progression et journal. Les pages Applications
  (installation), Sources et Restauration n’ont pas été rejouées en VM.
- **Assistant de premier démarrage** (2026-10-02) : il demande une connexion
  Internet (tout s’installe depuis Flathub, Brave depuis son dépôt). Hors
  ligne, l’installation échoue avec son journal ; on relance l’assistant depuis
  Réglages une fois connecté. Il **installe** ce qu’on coche mais ne
  **désinstalle** jamais ce qu’on décoche en le relançant : la page
  Applications sert à cela.
- La **session live** n’a plus de navigateur ni d’applications : l’assistant
  ne s’y ouvre pas (tout ce qu’il installerait disparaîtrait au redémarrage).
  La page Applications du centre reste utilisable dans le live.
- Bottles est installé par l’assistant, pas par l’image (un Flatpak et son
  runtime GNOME pèseraient près d’un gigaoctet dans l’ISO). Si l’assistant est
  passé, `auxinux-windows-wizard` propose de l’installer à l’ouverture du
  premier `.exe` ; Wine, lui, est toujours dans l’image.
- `Cargo.lock` épingle `tinyvec` en 1.8.1 : la version 1.13.0, tirée
  transitivement par la pile de rendu de texte, ne compile pas.
- La progression des opérations longues est **mesurée pour la partie DEB**
  (téléchargement puis installation, lignes `Status-Fd` d’apt). Pour Flatpak,
  la barre reste indéterminée : seule la dernière ligne écrite indique où en
  est l’opération. Le détail complet est disponible à la demande.
- La fiche détaillée AppStream (icônes haute définition, captures d’écran,
  description) existe dans le backend mais n’est pas branchée sur l’interface.
- La correspondance Flatpak/DEB reste **heuristique** (nom et app-id). Chaque
  fiche porte un identifiant par source, mais l’appariement lui-même peut
  encore rapprocher à tort deux logiciels homonymes.
- `auxi update --flatpak` ignore le code d’échec de Flatpak.
- Le Center est en **libcosmic sur un bureau Plasma** : il fonctionne (iced +
  winit + wgpu, aucune dépendance à COSMIC) mais **ne suit pas le thème
  Breeze**. Il aura l'air étranger jusqu'à une interface Kirigami/QML.
- Le fond d'écran et le retrait de Discover de la barre des tâches sont posés
  par deux **scripts de mise à jour de Plasma** (`auxinux-fond-ecran.js`,
  `auxinux-sans-discover.js`), exécutés une fois par compte. Plasma ne rejoue
  pas un script déjà exécuté : s'il change, il faut lui donner un nouveau nom.
  Le fond n'est remplacé que s'il est celui de Plasma par défaut.
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
- Le fichier d’échange sur `@swap` repose sur `btrfsSwapSubvol` (dans
  `mount.conf`) : Calamares ajoute lui-même ce sous-volume quand l’utilisateur
  choisit un fichier d’échange. La mise en veille prolongée n’est pas vérifiée.
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
  peut pas en lire tout le contenu.
- **CAUSE IDENTIFIEE ET CORRIGEE le 2026-09-29** (reproduite en VM avec l'ISO
  publiee le 2026-09-14, qui devait la corriger). Les 512 derniers octets du
  noyau sont des zeros de remplissage. Le module `unpackfs` de Calamares copie
  le systeme avec `rsync -S`, qui transforme ces zeros en **trou** ; avec la
  fonction BTRFS `no-holes`, un trou final n'a aucun extent, et le pilote BTRFS
  de GRUB 2.12 s'arrete au dernier extent : `grub-fstest`, qui execute ce
  pilote, ne relit que 16 752 640 octets sur 16 753 152. Linux lit le trou comme
  des zeros : aucune relecture faite depuis Linux ne pouvait le voir.
  Correctif : `post-install-cleanup.sh` reecrit tout `/boot` avec
  `cp --sparse=never --reflink=never`, et `verify-installed-boot.sh` relit
  noyau et initrd **avec `grub-fstest`** avant d'annoncer la fin de
  l'installation. Le correctif du 2026-09-14 (« /boot non compresse ») visait
  une cause deja eliminee plus bas, et `cp` y recreait le trou.
- **Les systemes installes avec une ISO anterieure au 2026-09-29 ne demarrent
  pas.** Reparation depuis un live : monter `@`, puis
  `cp --sparse=never --reflink=never /boot/vmlinuz-X /boot/vmlinuz-X.tmp &&
  mv /boot/vmlinuz-X.tmp /boot/vmlinuz-X`. Leurs instantanes, s'ils en ont,
  portent le meme noyau troue.
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
- (Pistes envisagees avant le 2026-09-29 — cible saturee, BIOS legacy,
  hyperviseur — sans objet : la cause est le trou final ci-dessus.)
- **Garde-fou ajoute** (`shellprocess@verifyboot`, dernier job avant `umount`) :
  `installer/verify-installed-boot.sh` fait `sync` puis vide le cache
  (`drop_caches`) et relit le noyau et l'initrd depuis le disque, **puis les
  relit avec le pilote de GRUB lui-meme** (`grub-fstest`) : seule cette
  seconde relecture voit ce que GRUB verra. Il verifie aussi que chaque entree de `grub.cfg` designe un
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
- **Les sous-volumes n’étaient pas créés** (constaté en VM le 2026-09-29).
  `btrfsSubvolumes` et `btrfsSwapSubvol` étaient écrits dans `partition.conf`,
  que Calamares ne lit pas pour cela : seuls `@`, `@home` et `@swap` (ce
  dernier ajouté d’office par le module `mount` quand l’utilisateur choisit un
  fichier d’échange) existaient sur les systèmes installés. Pas de
  `@snapshots`, donc aucun instantané : le rollback n’a fonctionné sur aucune
  installation antérieure. La liste est désormais dans `mount.conf`, et
  `check-rootfs.sh` le vérifie. L’ancien paragraphe qui annonçait `@swap`
  « corrigé » par un ajout à cette liste se trompait de fichier.
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
