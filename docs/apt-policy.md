# Politique APT

AuxiNux OS Edition-Normal reste une distribution conventionnelle: APT doit
continuer d'exister et de fonctionner.

## Comportement par defaut

Les commandes directes `apt`, `apt-get` et `apt-cache` sont masquees par un
wrapper utilisateur. Le wrapper explique d'utiliser `auxi`.

Exemples:

```bash
auxi update
auxi upgrade
auxi search firefox
auxi install org.mozilla.firefox
auxi install --deb nom-du-paquet
```

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
