# Rollback système

AuxiNuxOS peut annuler une mise à jour ou une installation qui a cassé le
système, **y compris quand le système ne démarre plus**.

## Pourquoi BTRFS et pas LVM

| | LVM | BTRFS |
|---|---|---|
| Taille des instantanés | pré-allouée, fixe | dynamique, quasi gratuite |
| Instantané plein | se casse silencieusement | sans objet |
| Écritures | dégradées tant qu'un instantané existe | inchangées |
| Démarrer sur un instantané | **impossible** sans média externe | **oui**, via le menu GRUB |

Le dernier point est décisif. Un rollback n'a de valeur que si l'on peut
l'utiliser au pire moment, c'est-à-dire quand la machine ne démarre plus. Avec
LVM, l'utilisateur doit trouver une clé USB de secours ; avec `grub-btrfs`, il
lui suffit de choisir une entrée dans le menu de démarrage.

## Disposition des sous-volumes

Ce qui est **hors** de `@` n'est pas capturé, donc n'est pas effacé par un
rollback.

| Sous-volume | Monté sur | Restauré ? | Raison |
|---|---|---|---|
| `@` | `/` | ✅ | l'état système |
| `@home` | `/home` | ❌ | un rollback ne doit **jamais** toucher aux données |
| `@snapshots` | `/.snapshots` | ❌ | sinon l'historique disparaît au moment du rollback |
| `@var_log` | `/var/log` | ❌ | garder la trace de la panne qu'on vient d'annuler |
| `@var_cache` | `/var/cache` | ❌ | cache APT, sans intérêt |
| `@var_tmp` | `/var/tmp` | ❌ | transitoire |
| `@var_lib_flatpak` | `/var/lib/flatpak` | ❌ | applications Flatpak = contenu utilisateur |
| `@swap` | fichier d'échange | ❌ | exigence BTRFS (ni CoW ni compression) |

`@snapshots` est un sous-volume **de premier niveau**, jamais imbriqué dans
`@`. Imbriqué, il serait déplacé avec `@` pendant la restauration et
l'utilisateur perdrait tout son historique au moment précis où il en a besoin.

Cette liste est déclarée dans `image-builder/overlays/etc/calamares/modules/mount.conf`
(`btrfsSubvolumes`) : c'est le module `mount` de Calamares qui crée les
sous-volumes. **Les installations faites avant le 2026-09-29 n'ont que `@`,
`@home` et `@swap`** : la liste était alors écrite dans `partition.conf`, que
Calamares ignore pour cela. Sur ces machines, `/.snapshots` n'est pas un
sous-volume, snapper ne peut créer aucun instantané et `auxi rollback` ne
trouve rien à restaurer. Elles doivent être réinstallées pour bénéficier du
rollback.

Options de montage : `noatime,compress=zstd:1,space_cache=v2`, plus
`discard=async` sur SSD. La compression zstd niveau 1 **réduit le volume d'E/S
disque** : c'est un gain de réactivité, pas seulement d'espace.

## Quand un instantané est créé

- **Automatiquement, avant chaque transaction DEB**, quel que soit le chemin
  emprunté : `auxi`, le centre de contrôle, `apt` réactivé, ou `dpkg` appelé
  par un script tiers. L'instantané est posé par un hook branché sur dpkg
  lui-même (`/etc/apt/apt.conf.d/80auxinux-snapshot` →
  `/usr/lib/auxinux/apt-snapshot-hook`), et non plus par la commande `auxi`.
  Tant qu'il vivait dans `auxi`, la promesse était fausse pour tout autre point
  d'entrée. C'est le filet principal : l'utilisateur n'a rien à demander.
- **Toutes les heures** (`snapper-timeline.timer`), pour les dégâts qui ne
  viennent pas d'une transaction de paquets.
- **Manuellement**, avec `auxi snapshot`.
- **À l'installation**, un instantané « Installation initiale » marqué
  important sert de point de retour d'usine.

Rétention : 10 instantanés numérotés, 5 horaires, 7 quotidiens. Le nettoyage
se déclenche aussi si BTRFS dépasse 40 % d'occupation par les instantanés ou
si l'espace libre passe sous 20 %.

Les instantanés sont posés par **paires pre/post**, ce qui permet de voir
exactement ce qu'une transaction a changé :

```bash
sudo snapper -c root status 42..43
```

## Utilisation

```bash
auxi snapshots                    # lister les instantanés
sudo auxi snapshot "avant essai"  # instantané manuel
sudo auxi rollback                # lister puis choisir
sudo auxi rollback 42             # restaurer l'instantané 42
sudo auxi rollback 42 --yes       # sans confirmation
```

Pour désactiver l'instantané automatique d'une seule commande :

```bash
sudo AUXI_NO_SNAPSHOT=1 auxi install paquet
```

### Le système démarre encore

`sudo auxi rollback 42`, puis redémarrer. La commande fonctionne depuis une
session normale : renommer un sous-volume monté n'affecte pas le montage en
cours, et c'est au démarrage suivant que `subvol=@` désigne le système
restauré.

### Le système ne démarre plus

1. Au démarrage, choisir **« AuxiNux OS - instantanés (restauration) »**.
2. Sélectionner un instantané antérieur à la panne.
3. `sudo auxi rollback NUMERO`, puis redémarrer.

Les instantanés snapper sont en **lecture seule**, et un système dont la racine
n'accepte aucune écriture ne démarre pas : systemd s'arrête dès qu'il touche
`/etc` ou `/var/lib`. Ces entrées de menu portent donc le paramètre
`auxinux.snapshot=1`, qui déclenche un hook initramfs
(`auxinux-snapshot-overlay`) superposant un espace inscriptible **en mémoire**
sur l'instantané. Le système démarre normalement ; les modifications faites
dans cette session sont volatiles, ce qui est précisément ce que l'on veut : la
seule action qui doit persister est `auxi rollback`, qui agit sur les
sous-volumes et non sur la session en cours.

Un démarrage normal ne porte jamais ce paramètre et n'est donc jamais
concerné.

## Ce que fait réellement la restauration

`snapper rollback` **ne suffit pas** sur une disposition plate `@` : il agit
sur le sous-volume par défaut de BTRFS, alors que `/etc/fstab` monte la racine
par chemin (`subvol=@`). `auxi rollback` échange donc les sous-volumes :

1. `@` est renommé `@.rollback-<horodatage>` — le système actuel est
   **conservé**, jamais supprimé ;
2. un sous-volume `@` inscriptible est créé à partir de l'instantané choisi ;
3. si cette seconde étape échoue, `@` est immédiatement remis en place.

C'est entre les étapes 1 et 2 que la machine n'a temporairement plus de racine
amorçable. La reprise sur échec est vérifiée par `tests/test-rollback.sh`.

L'ancien système reste sur le disque jusqu'à suppression explicite. Chaque
restauration en laisse un : sans nettoyage, ils occupent le disque jusqu'à
saturation.

```bash
sudo auxi rollback-cleanup        # liste, demande confirmation, supprime
sudo auxi rollback-cleanup --yes  # sans confirmation
```

Ne les supprimer qu'**après** avoir vérifié que le système restauré démarre :
c'est le seul recours si la restauration s'avère pire que la panne.

## Provenance de grub-btrfs

`grub-btrfs` **n'est pas un paquet Debian 13**. Les douze autres composants de
la pile (`btrfs-progs`, `snapper`, `inotify-tools`…) le sont ; celui-là non.

Il est installé depuis les sources officielles
([Antynea/grub-btrfs](https://github.com/Antynea/grub-btrfs)), tag `v4.14`,
commit `2fcfbe967637166b88dadd49c834807243a941bf`, par
`image-builder/scripts/install-grub-btrfs.sh`. Le script **refuse d'installer**
si le dépôt n'est pas exactement à ce commit : un tag amont peut être déplacé,
et ce code s'exécute en root dans le rootfs de l'image.

Aucune compilation : le projet est un script `/etc/grub.d`, un démon shell et
une unité systemd.

S'en passer aurait vidé la fonction de sa substance — `auxi rollback` ne
marcherait plus que depuis un système qui démarre encore, c'est-à-dire pas dans
le seul cas où l'on en a réellement besoin.

## Limites

Voir [les limites connues](limitations.md) — notamment BTRFS + LUKS,
le fichier d'échange sur `@swap` et la validation en machine virtuelle,
qui restent à faire.
