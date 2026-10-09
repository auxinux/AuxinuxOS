# Politique APT

AuxiNux OS reste une distribution conventionnelle: APT doit
continuer d'exister et de fonctionner.

## Comportement par defaut

Les commandes directes `apt` et `apt-get` sont masquées par un wrapper
utilisateur, qui explique d'utiliser `auxi` (`apt-cache`, en lecture seule,
reste disponible : voir plus bas).

Exemples:

```bash
auxi update
auxi upgrade                      # applications Flatpak + système
auxi os update                    # une nouvelle version d'AuxiNux OS est-elle disponible?
sudo auxi os upgrade              # l'installer: instantané nommé, puis tous les paquets DEB
auxi kernel                       # noyaux installés et disponibles
auxi search firefox
auxi install gimp                 # Flatpak org.gimp.GIMP
auxi install org.mozilla.firefox
sudo auxi install --deb nom-du-paquet   # seulement si deb=true (voir plus bas)
```

Les **mises à jour** passent toujours, même `apt` masqué et même si DEB est
désactivé :

- `apt update` devient `auxi update --deb` ; `apt upgrade`, `apt full-upgrade`
  et `apt dist-upgrade` deviennent `auxi os upgrade` (point de restauration si
  la version d'AuxiNux OS change, nouveaux noyaux acceptés, rien n'est
  retiré). Avec des noms de paquets (`apt upgrade firefox`), le refus habituel
  s'applique.
- Dans un terminal, une commande `auxi` qui exige root (`auxi update`,
  `auxi upgrade`, `auxi os upgrade`…) se relance d'elle-même par `sudo` au
  lieu d'échouer. Sans terminal, elle s'arrête avec un message.
- Dans le centre, « Actualiser les listes » ne demande **pas** de mot de passe
  (action polkit `ca.auxinux.center.refresh`, session locale active) ; les
  mises à jour du système passent par `ca.auxinux.center.system-update`
  (« Mettre à jour AuxiNux OS », mot de passe gardé quelques minutes). Voir
  `packages/auxinux-center/helper/`.

## Applications: Flatpak d'abord

Les applications s'installent depuis **Flatpak (Flathub)**. `auxi install NOM`
reconnaît l'identifiant complet (`org.gimp.GIMP`), son dernier composant
(`gimp`) ou le nom affiché (`obs-studio` pour « OBS Studio »), sans tenir
compte de la casse ni des tirets. Rien n'est deviné au-delà : sans
correspondance exacte, `auxi` affiche les applications proches au lieu d'en
choisir une.

L'installation **DEB** d'applications est désactivée par défaut :

```bash
sudo auxi set deb=true    # aussi: Réglages du centre, « Applications DEB »
sudo auxi set deb=false
```

Une fois activée, Flatpak reste **toujours** prioritaire : `auxi install NOM`
ne prend le paquet DEB que si aucun Flatpak ne correspond. Le centre ajoute
alors une liste déroulante Flatpak / DEB à la page Applications, et
`auxi search` liste aussi les paquets DEB.

Désactivée, `auxi install --deb` refuse un paquet **nouveau**, mais met
toujours à jour un paquet déjà installé (le centre s'en sert pour AuxiNux
Office). Les mises à jour du système (`auxi update`, `auxi upgrade`,
`auxi osupdate`) et les noyaux (`auxi kernel`) ne dépendent pas de ce réglage :
il ne concerne que les **applications**. Le réglage vit dans
`/etc/auxinux/apps.conf` (`DEB_APPS=0|1`), distinct d'`apt.conf` : on peut
vouloir des applications DEB tout en gardant `apt` et `apt-get` renvoyés vers
`auxi`.

## Mise à jour du système

`sudo auxi os upgrade` rafraîchit les index puis met à jour **tous** les paquets
DEB installés (`apt-get upgrade --with-new-pkgs`). Les paquets nouveaux tirés
par un paquet installé sont acceptés — c'est le cas de chaque nouveau noyau :
`kernel-auxinuxos` 7.2.6 dépend du nouveau paquet `linux-image-7.2.6-…`. Rien
n'est retiré (contrairement à `full-upgrade`), et aucune application que rien
ne demande n'est ajoutée. `auxi upgrade` fait la même chose après les
applications Flatpak ; c'est aussi ce que lance « Mettre à jour le système »
dans le centre de contrôle.

Avant le 2026-10-07, `auxi upgrade` lançait un `apt-get upgrade` simple : le
nouveau noyau était mis de côté (« kept back ») et la commande réussissait
quand même.

## Versions d'AuxiNux OS

Chaque ISO publiée est une édition (`0.2.1+AAAAMMJJ`), portée par le paquet
`auxinuxos-release`. `auxi os update` dit si une édition plus récente est
disponible (sans rien installer ; en root, rafraîchit d'abord les listes).
`sudo auxi os upgrade` l'installe : **un instantané nommé** (« Avant AuxiNux OS
0.2.1, édition du … », marqué important) est posé d'abord ; s'il échoue sur un
système qui sait en faire, la mise à jour est annulée. Le bouton « Mettre à jour
vers cette version » du centre de contrôle fait la même chose, et « Mettre à
jour le système » (`auxi upgrade`) aussi dès qu'une nouvelle version arrive.
`auxi osupdate` reste accepté (ancien nom de `auxi os upgrade`).

## Noyaux

```bash
auxi kernel                                   # actif, installés, disponibles
sudo auxi kernel dev on|off                   # noyaux en essai (suite kernel-dev)
sudo auxi kernel install 7.2.9-dev-auxinuxos-amd64
sudo auxi kernel activate 7.2.5-auxinuxos-amd64   # démarrer dessus
sudo auxi kernel activate latest              # revenir au plus récent
sudo auxi kernel update                       # dernière version de chaque canal installé
sudo auxi kernel remove 7.2.9-dev-auxinuxos-amd64
```

Seuls les noyaux AuxiNux (`linux-image-<v>-auxinuxos-amd64`) sont acceptés.
`remove` refuse le noyau en cours, le dernier noyau stable, et tout ce qui
emporterait `kernel-auxinuxos` (le noyau que suit la mise à jour du système).
`activate` passe `GRUB_DEFAULT=saved` par `/etc/default/grub.d/50-auxinux-noyau.cfg`
et enregistre l'entrée choisie ; sans lui, GRUB démarre toujours le plus récent.
Le centre de contrôle offre les mêmes actions (Applications > Noyau).

Le noyau d'essai est un paquet **distinct** du noyau stable : activer la source
kernel-dev n'installe rien tant qu'on ne choisit pas une version. Une fois un
noyau d'essai installé, `osupdate` suit les nouveaux noyaux d'essai.

## Reactivation explicite

Un utilisateur administrateur peut reactiver les commandes APT directes:

```bash
sudo auxi set apt=true
```

Pour revenir au comportement guide:

```bash
sudo auxi set apt=false
```

## L'instantané ne dépend pas de cette politique

Le point de restauration créé avant chaque transaction DEB **n'est pas** posé
par `auxi`. Il l'est par un hook branché sur dpkg :

```
/etc/apt/apt.conf.d/80auxinux-snapshot
  -> /usr/lib/auxinux/apt-snapshot-hook pre | post
```

Conséquence : réactiver APT direct avec `auxi set apt=true` ne fait **pas**
perdre le filet de sécurité. Tant que la logique vivait dans `auxi`, tout autre
chemin vers dpkg — `apt` réactivé, PackageKit, un script tiers — modifiait le
système sans instantané, alors que l'interface affirmait le contraire.

Pour désactiver l'instantané d'une seule commande :

```bash
sudo AUXI_NO_SNAPSHOT=1 apt install paquet
```

Le hook sort toujours en code 0 : un `DPkg::Pre-Invoke` en échec avorterait la
transaction, et une indisponibilité de snapper rendrait la machine incapable
d'installer quoi que ce soit.

`apt-cache` **n'est pas** détourné : c'est une commande de lecture seule, la
masquer ne protégeait rien et cassait la complétion.

## Justification

L'objectif n'est pas de bloquer Debian. L'objectif est de guider les
utilisateurs moins experimentes vers une commande coherente qui met Flatpak
en avant et garde les paquets DEB disponibles quand ils sont necessaires.
