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

Options de montage : `noatime,compress=zstd:1,space_cache=v2`, plus
`discard=async` sur SSD. La compression zstd niveau 1 **réduit le volume d'E/S
disque** : c'est un gain de réactivité, pas seulement d'espace.

## Quand un instantané est créé

- **Automatiquement, avant chaque transaction DEB** (`install`, `upgrade`,
  `uninstall`, `purge`) faite via `auxi` ou le centre d'applications. C'est le
  filet principal : l'utilisateur n'a rien à demander.
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
2. Sélectionner un instantané antérieur à la panne. Le système démarre dessus
   en lecture seule.
3. `sudo auxi rollback NUMERO`, puis redémarrer.

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

L'ancien système reste sur le disque jusqu'à suppression explicite :

```bash
sudo mount -o subvolid=5 /dev/VOTRE_DISQUE /mnt
sudo btrfs subvolume delete /mnt/@.rollback-20260903-101500
sudo umount /mnt
```

## Limites

Voir [les limites connues](limitations.md) — notamment BTRFS + LUKS,
le fichier d'échange sur `@swap` et la validation en machine virtuelle,
qui restent à faire.
