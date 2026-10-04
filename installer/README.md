# Installateur AuxiNuxOS

Installateur graphique et backend pour l'installation classique d'AuxiNuxOS.

## Deux installateurs

Le menu GRUB du live propose, **par défaut**, « Installer AuxiNux OS
maintenant » : le live démarre en console et lance l’**installateur maison**
(« Install NOW »). L’entrée « Essayer » donne le bureau live, inchangé, avec
**Calamares** (icône `Install AuxiNuxOS`). Les deux finissent par les mêmes
scripts : `post-install-cleanup.sh`, `setup-btrfs-rollback.sh`,
`verify-installed-boot.sh`.

## Installateur maison « Install NOW »

- **Interface** : `packages/auxinux-center/src/installer/` (Rust + ratatui,
  binaire `auxinux-installer`, feature `tui`), lancée sur la première console
  par `auxinux-installer.service` quand le noyau reçoit `auxinux.install=1`.
  Bilingue : langue, connexion Internet (choix d’un réseau Wi-Fi si une carte
  est détectée), fuseau, clavier (appliqué tout de suite à la console), disque
  entier et chiffrement LUKS optionnel, compte administrateur, puis — en ligne
  seulement — les questions de l’assistant (navigateur, lecteur multimédia,
  profil et applications, vie privée). Résumé avec confirmation tapée
  (`OUI`/`YES`), barre de progression globale, diapositives, journal (`J`).
- **Moteur** : `auxinux-install-engine` (bash, root). Lit un fichier
  `CLE=VALEUR`, **valide tout avant de toucher au disque**, refuse le support
  d’installation comme cible, puis : GPT (bios_grub + EFI + BTRFS), sous-volumes
  de `mount.conf`, copie de la couche intacte du live (sans `rsync -S`),
  configuration, GRUB, en ligne mises à jour et applications, scripts de fin.
  `--simuler` affiche le plan sans rien exécuter (`tests/test-install-engine.sh`).
- **Hors ligne** : `grub-efi-amd64`, `grub-pc` et les outils LUKS sont embarqués
  dans l’image (`/usr/share/auxinux/installateur/paquets/`) ; Calamares les
  téléchargeait. Sans Internet, l’installation est **minimale** et le dit :
  l’assistant de premier démarrage proposera les applications une fois connecté.
- **Chiffrement** : LUKS2 en **PBKDF2** (GRUB ne déverrouille pas Argon2), avec
  `/boot` dans la racine chiffrée pour que les instantanés contiennent le bon
  noyau. GRUB est alors construit **non signé** avec cryptodisk (le GRUB signé de
  Debian ne sait pas ouvrir LUKS avant de lire son menu — Secure Boot n’est de
  toute façon pas pris en charge) ; une clé interne à la racine évite de taper
  la phrase de passe deux fois.
- **Diapositives** : `installer/diapositives/{fr,en}.txt`, source unique ;
  l’installateur console les embarque, `image-builder/scripts/
  generate-slideshow.py` en fait le `show.qml` de Calamares.

## Configuration Calamares

La configuration est versionnee dans les overlays et embarquee dans l'image:

- `image-builder/overlays/etc/calamares/settings.conf` — sequence de modules;
- `image-builder/overlays/etc/calamares/modules/shellprocess-cleanup.conf` —
  branche `post-install-cleanup.sh` en fin de sequence `exec`;
- `image-builder/overlays/etc/calamares/branding/auxinuxos/` — branding + slides.

`post-install-cleanup.sh` est installe dans l'image a
`/usr/lib/auxinux/post-install-cleanup.sh` (voir `install-auxi-cli.sh`) et
retire : icone d'installation **et son autodémarrage**, lanceur Calamares,
`sudoers.d/90-auxinux-live` (NOPASSWD), autologin COSMIC/greetd live, compte
live `auxinux`, paquets live-boot **et Calamares lui-même**.

Le retrait de l'autodémarrage et de Calamares n'est pas cosmétique : sans lui,
l'installateur se relançait à chaque ouverture de session du système installé,
après avoir déplacé `/etc/fstab`.

Couvert par `tests/test-post-install.sh`. Les limites du nettoyage sont
documentées dans `docs/limitations.md`.

Le nom de compte `auxinux` est réservé au live et interdit par la
configuration des utilisateurs de Calamares. A valider en VM avant
toute ISO publique.

## Rollback système

L'installation cible **BTRFS** avec des sous-volumes plats, ce qui rend le
rollback possible. La configuration est versionnée dans les overlays :

- `modules/partition.conf` — BTRFS par défaut ;
- `modules/mount.conf` — **les sept sous-volumes** (`btrfsSubvolumes`) et les
  options de montage **pendant** l'installation ;
- `modules/fstab.conf` — options écrites dans le `/etc/fstab` **installé** ;
- `modules/shellprocess-snapshots.conf` — branche `setup-btrfs-rollback.sh`.

`setup-btrfs-rollback.sh` est installé à
`/usr/lib/auxinux/setup-btrfs-rollback.sh` (voir `install-auxi-cli.sh`) et
configure snapper, `grub-btrfs` et l'instantané d'installation initiale.

Il doit rester le **dernier** job de la séquence `exec`, après
`shellprocess@cleanup` : le nettoyage purge live-boot puis régénère
l'initramfs, et ce script termine par `update-grub`. Dans l'ordre inverse, les
entrées de restauration du menu GRUB pointeraient sur un initrd encore
contaminé par les hooks live-boot.

Le modèle de configuration snapper est cherché sous `/usr/share` **puis**
`/etc` : Debian 13 ne le livre qu'au premier emplacement. Ne chercher que dans
`/etc` faisait sortir le script en code 0 avec un simple avertissement, et le
rollback était absent de **chaque** système installé — sans aucun signal.
À défaut de modèle, une configuration minimale est écrite plutôt que
d'abandonner la fonction.

Le script est non bloquant par conception : une racine ext4 choisie en
partitionnement manuel le fait sortir en code 0 sans configurer le rollback.
Contrairement à `post-install-cleanup.sh`, il ne masque aucune erreur : chaque
échec est tracé sur stderr et résumé en fin d'exécution.

Les sous-volumes se déclarent dans `mount.conf` et **nulle part ailleurs** :
c'est le module `mount` qui les crée. Jusqu'au 2026-09-29, la liste vivait dans
`partition.conf`, que Calamares ne lit pas pour cela ; elle était ignorée en
silence (seul le journal de Calamares le disait : « No configuration for
btrfsSubvolumes »), et **aucun système installé n'avait `@snapshots`** — donc
aucun instantané possible. `check-rootfs.sh` refuse désormais une image où la
liste manque à `mount.conf`, ou traîne dans `partition.conf`. Ne pas y ajouter
`/swap` : Calamares crée lui-même `@swap` quand l'utilisateur choisit un
fichier d'échange, et le déclarer deux fois ferait échouer l'installation.

## Clavier, langue et fuseau

`modules/locale.conf` place le fuseau par défaut sur `America/Toronto`. Sans
lui, Calamares partait de New York, proposait `fr_FR` et en déduisait le
clavier **AZERTY de France**, appliqué aussitôt à la saisie du nom et du mot de
passe. Avec une zone canadienne, il propose `fr_CA` (ou `en_CA`) et le clavier
« French (Canada) », QWERTY.

La disposition choisie doit être la même **partout** où l'on tape le mot de
passe : Calamares l'écrit dans `/etc/default/keyboard` (console, écran de
connexion X11), et `post-install-cleanup.sh` la recopie dans `/etc/xdg/kxkbrc`
pour la session Plasma, que KWin ne configure pas autrement. Sans cette copie,
un mot de passe tapé dans une disposition autre que « us » ouvrait la session
mais ne déverrouillait plus l'écran, et sudo le refusait.

## Partition EFI

`post-install-cleanup.sh` reproduit `EFI/AuxiNuxOS` (shim, GRUB, MokManager et
`grub.cfg`) dans le chemin de secours `EFI/BOOT`, le seul que tout
micrologiciel sait amorcer quand il a perdu son entrée NVRAM. Calamares n'y
copiait que le GRUB signé, sans le `grub.cfg` dont cette image monolithique a
besoin : la machine s'arrêtait sur une invite `grub>`. La question debconf
`grub2/force_efi_extra_removable` est posée pour que les mises à jour de GRUB
maintiennent ce chemin.

`verify-installed-boot.sh` contrôle la partition EFI avant la fin de
l'installation : répertoire `EFI/AuxiNuxOS` complet et `grub.cfg` désignant
bien l'UUID de la racine installée.

Voir [docs/rollback.md](../docs/rollback.md).
