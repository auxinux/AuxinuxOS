# Fluidité

Trois mesures, choisies pour leur effet **ressenti** plutôt que pour leur score
en test synthétique.

## zram — espace d'échange compressé en RAM

`zram-tools`, configuré dans `/etc/default/zramswap` : algorithme `zstd`, 50 %
de la RAM en taille maximale, priorité 100.

C'est le levier le plus rentable sur les machines à 4–8 Go. Les pages inactives
sont compressées en mémoire (ratio d'environ 3:1) au lieu de partir sur le
disque. `PERCENT=50` est un plafond, pas une réservation : zram n'occupe que ce
qu'il contient réellement. Au-delà de 50 %, la mémoire récupérée par la
compression ne compense plus celle que prend zram lui-même.

La priorité 100 garantit que le noyau préfère toujours la RAM compressée au
fichier d'échange sur disque.

## systemd-oomd — contre le gel total

Sans lui, une machine à court de mémoire **ne plante pas** : elle devient
inutilisable pendant plusieurs minutes, souris comprise, pendant que le noyau
échange frénétiquement. L'utilisateur croit à un plantage et coupe
l'alimentation, avec le risque de corruption que cela implique. C'est le défaut
de fluidité le plus violent qu'on puisse rencontrer, et le plus invisible dans
les mesures.

Deux fichiers sont nécessaires — et le second est celui qu'on oublie :

- `/etc/systemd/oomd.conf.d/50-auxinux.conf` — `DefaultMemoryPressureDurationSec=20s`.
  Trop court, on tue une application pendant un pic normal (compilation, import
  de photos) ; 20 s distingue un pic d'une saturation.
- `/etc/systemd/system/user@.service.d/50-auxinux-oomd.conf` —
  `ManagedOOMMemoryPressure=kill`. **systemd-oomd n'agit que sur les tranches
  qui l'autorisent explicitement** : sans ce fichier, le service tourne et ne
  fait rien.

La cible est `user@.service` et non `-.slice` : systemd-oomd tue alors le
descendant le plus gourmand, c'est-à-dire une application. Viser `-.slice`
tuerait des services système et rendrait le remède pire que le mal.

## Entretien du stockage

- `fstrim.timer` activé, pour les installations en ext4.
- Sur BTRFS, `discard=async` (voir [rollback](rollback.md)) regroupe le TRIM et
  l'émet en arrière-plan, sans la pause perceptible du TRIM synchrone.
- `compress=zstd:1` sur BTRFS **réduit le volume d'E/S disque** : c'est un gain
  de réactivité, pas seulement d'espace.

## Allègement

`q4wine` a été retiré de l'image (interface abandonnée en amont), et le centre
de contrôle n'a plus aucune dépendance QML/Kirigami/KF6 depuis son passage à
libcosmic — voir [le centre de contrôle](auxinuxos-center.md).

## Vérification

Aucune de ces mesures n'a encore été mesurée sur matériel réel. Les commandes
de contrôle sont dans [la procédure de validation](../tests/README.md).
