# Protection au démarrage

AuxiNuxOS ne doit **jamais** laisser l'utilisateur devant un écran noir sans
recours. Cette page décrit le mécanisme qui l'en empêche.

## Le problème, tel qu'il s'est produit

Le 2026-09-09, la panne a été reproduite en VM : le gestionnaire de session
échouait, atteignait sa limite de redémarrages, et comme il avait arrêté la
console texte de `tty1`, l'écran restait **noir à 100 %, définitivement**. La
machine tournait pourtant : 14 services actifs, connexion possible par la
console série. L'utilisateur, lui, n'avait aucun moyen de le savoir ni d'agir —
il en concluait que le démarrage ne se terminait jamais.

Un rollback existait, prêt à l'emploi. Il était inatteignable.

## Le mécanisme

Trois unités, aucun script GRUB :

| Unité | Moment | Rôle |
|---|---|---|
| `auxinux-boot-arm.service` | avant le gestionnaire d'affichage | incrémente un compteur persistant ; au seuil, pose `/run/auxinux/rescue` |
| `auxinux-boot-sentinel.service` | après `graphical.target` | attend une session graphique **réellement active**, puis remet le compteur à zéro |
| `auxinux-rescue.service` | si `/run/auxinux/rescue` existe | prend `tty1` et propose la restauration |

Le drop-in `sddm.service.d/50-auxinux-fallback.conf` refuse de démarrer SDDM
quand le fichier de secours existe (`ConditionPathExists=!`), et rend la main à
une console (`OnFailure=getty@tty1.service`) si SDDM abandonne.

```
démarrage 1 échoué  ->  compteur = 1  ->  on réessaie le bureau
démarrage 2 échoué  ->  compteur = 2  ->  console de secours, restauration proposée
démarrage 3 échoué  ->  compteur = 3  ->  restauration AUTOMATIQUE, sans question
```

## Pourquoi « session active » et pas « gestionnaire démarré »

Parce qu'un gestionnaire d'affichage qui tourne ne prouve rien : il peut boucler
sur un écran noir. La sentinelle interroge `logind` et exige une session de type
`wayland` ou `x11` dans l'état `active`. Un `tty` actif ne compte pas — c'est
précisément l'état dans lequel se trouve une machine tombée sur la console de
secours, et le compter comme un succès désarmerait la protection au pire moment.

La source est `logind`, pas un processus nommé : le mécanisme survit donc à un
changement de bureau (Plasma vers GNOME) sans modification.

### Mais l'absence de session n'est pas forcément une panne

Quelqu'un qui allume sa machine et s'en va laisse l'écran de connexion ouvert
sans jamais ouvrir de session. Deux démarrages comme celui-là auraient suffi à
envoyer la machine en mode secours, puis à lui proposer une restauration dont
elle n'avait aucun besoin.

Le signe qui distingue les deux cas est l'état du gestionnaire d'affichage : dans
la panne du 2026-09-09 il finissait en `failed (start-limit-hit)`, alors qu'un
écran de connexion simplement inutilisé est `active`. À l'expiration du délai, la
sentinelle remet donc le compteur à zéro **si `display-manager.service` est
actif**, et ne l'incrémente qu'autrement.

Conséquence assumée : un greeter qui tourne en affichant une fenêtre noire — donc
`active` — n'est pas détecté. On préfère cette lacune à une restauration
automatique déclenchée sur une machine qui marche. Dans ce cas, `tty1` reste
accessible (SDDM occupe `tty7`) et `auxi rollback` est utilisable à la main.

## Quel instantané est restauré

Le dernier instantané **`pre`**, c'est-à-dire celui posé juste avant une
transaction de paquets. Une transaction de paquets est de loin la première cause
d'un bureau qui ne démarre plus, et le hook dpkg garantit qu'un instantané
existe avant chacune (voir [rollback](rollback.md)). À défaut, le plus récent,
quel qu'il soit. L'instantané 0 (l'état courant) est toujours ignoré.

`auxinux-rescue --pick-snapshot` affiche le choix sans rien modifier.

## Ce que ça ne couvre pas

Un noyau ou un initramfs qui ne démarre **pas du tout**. Ce cas reste du ressort
du sous-menu d'instantanés de GRUB (`grub-btrfs`), qui ne dépend d'aucun service
de la machine. Les deux mécanismes sont complémentaires : l'un agit quand le
système démarre mais n'aboutit pas, l'autre quand il ne démarre plus.

## Désactivation

Paramètre de noyau `auxinux.nosentinel` : les trois unités se taisent pour ce
démarrage. La protection ne doit jamais devenir un piège.

## Limites

- Le seuil, la fenêtre d'attente (180 s) et le seuil automatique sont réglables
  par variables d'environnement, mais aucune interface ne les expose encore.
- Le mécanisme est couvert par `tests/test-boot-sentinel.sh` (logique, avec des
  stubs `systemctl`/`loginctl`). **La bascule réelle en mode secours n'a pas
  encore été validée en VM.**
