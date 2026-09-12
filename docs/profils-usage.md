# Profils d'usage : bureautique, multimédia, jeu

AuxiNuxOS assume trois usages. Le noyau `kernel-auxinuxos` 7.2.5 est déjà
construit pour les trois ; ce que le profil change, c'est l'espace utilisateur.

## Ce que le noyau apporte déjà

Vérifié dans la configuration du noyau publié :

- `HZ=1000`, `PREEMPT` complet + `PREEMPT_DYNAMIC`, `NO_HZ_FULL`, `SCHED_HRTICK`
  — latence basse, utile aux trois usages ;
- `NTSYNC` et `FUTEX_PRIVATE_HASH` — gain réel sur Wine/Proton ;
- MGLRU actif, `ZSWAP`, `PSI` (prérequis de `systemd-oomd`), THP en `madvise` ;
- `BTRFS_FS` **compilé en dur**, ce qui rend le rollback indépendant de
  l'initramfs.

**Ce qu'il n'apporte pas** : `CONFIG_SCHED_CLASS_EXT` (sched_ext) n'est pas
activé. Aucun profil ne peut donc changer d'ordonnanceur. Tout se joue dans
quatre fichiers, écrits par `auxinux-profile`.

## Ce que chaque profil change

| | bureautique | multimédia | jeu |
|---|---|---|---|
| `vm.swappiness` | 100 | 60 | 60 |
| `vm.vfs_cache_pressure` | 100 | 50 | 50 |
| `vm.max_map_count` | défaut | défaut | 2147483642 |
| `vm.compaction_proactiveness` | défaut | défaut | 0 |
| `kernel.split_lock_mitigate` | 1 | 1 | **0** |
| quantum PipeWire | 1024 | 256 | 512 |
| `rtprio` du groupe `audio` | — | 95 | 90 |
| profil d'alimentation | balanced | performance | performance |

Les trois valeurs qui méritent une justification :

- **`swappiness=100`, pas 10.** Le conseil « swappiness bas » vise un fichier
  d'échange sur disque. Ici l'échange va dans la RAM compressée (zram), où il
  coûte quelques microsecondes : le pénaliser n'a aucun sens.
- **`max_map_count`** : Proton et une partie des jeux Windows dépassent la
  limite par défaut et se ferment **sans message**. La valeur est celle de
  SteamOS.
- **`split_lock_mitigate=0`** uniquement en jeu : la mitigation coûte cher à
  certains jeux sous Proton, mais elle protège d'un déni de service local. Elle
  n'est levée que là, et jamais par défaut.

### Pourquoi `@audio` et pas l'utilisateur

La priorité temps réel est accordée au **groupe `audio`**, pas à un compte : le
compte créé à l'installation y est ajouté par Calamares
(`modules/users.conf`, `defaultGroups`). Accorder `rtprio` à un nom
d'utilisateur aurait produit un réglage qui ne s'applique à personne sur la
machine suivante.

## Un seul propriétaire pour le CPU

`auxinux-profile` ne touche **pas** à `scaling_governor` ni à
`energy_performance_preference`. Il passe par `power-profiles-daemon`, que
`powerdevil` (l'applet batterie de Plasma) utilise aussi. Deux écrivains sur le
même réglage, c'est le dernier arrivé qui gagne — au hasard, et sans que rien ne
le signale.

## Utilisation

```bash
auxinux-profile show            # profil courant et réglages
auxinux-profile list            # les trois profils
sudo auxinux-profile set gaming # change et applique
auxinux-profile status          # sortie machine, pour le centre de contrôle
```

`auxinux-profile.service` réapplique le profil à chaque démarrage : les fichiers
`sysctl` et `limits` survivent seuls, mais le profil de
`power-profiles-daemon` revient à `balanced` à chaque redémarrage.

## Type d'installation et profil d'usage sont deux choses

Le **type d'installation** décide de ce qui est *installé*
(`package-lists/layer-*.txt`) ; le **profil d'usage** décide de ce qui est
*réglé*. Le second est commutable à tout moment, le premier pas.

L'ISO 0.2.0 embarque les trois couches : l'installation étant une copie du
squashfs, le médium doit contenir tout ce qu'une installation peut recevoir.
Choisir un type (donc retirer les couches non voulues) appartient à
l'installateur maison, qui n'existe pas encore.

## Limites

- Couvert par `tests/test-profile.sh` (logique et nettoyage entre profils).
  **Aucune mesure de performance n'a été faite** : les valeurs sont choisies sur
  des mécanismes connus, pas sur un banc d'essai maison.
- Le centre de contrôle propose la bascule dans **Réglages → Profil d'usage**
  (il appelle `auxinux-profile` via `pkexec`, sans réimplémenter les réglages).
  Cette carte **n'a jamais été vue à l'écran** : elle compile, sa logique est
  testée, mais l'interface du Center n'a encore jamais été lancée
  graphiquement.
