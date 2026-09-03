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

## Justification

L'objectif n'est pas de bloquer Debian. L'objectif est de guider les
utilisateurs moins experimentes vers une commande coherente qui met Flatpak
en avant et garde les paquets DEB disponibles quand ils sont necessaires.
