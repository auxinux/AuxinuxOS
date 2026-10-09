# Packages AuxiNuxOS

Paquets et composants propres a la variante conventionnelle.

## Paquets DEB publiés : `auxi` et `auxinux-center`

Depuis la 0.2.1, la commande `auxi` et AuxiNux OS Center sont livrés en
paquets DEB, publiés dans la suite **APPS** du dépôt AuxiNuxOS
(`https://dep.auxinux.ca/AUXINUXOS`, déjà active sur toutes les installations).
Une nouvelle version arrive donc avec la mise à jour du système, sans nouvelle
ISO.

| Paquet | Contenu |
|---|---|
| `auxi_<V>_all.deb` | `/usr/bin/auxi`, le bouclier apt, le hook d'instantané |
| `auxinux-center_<V>_amd64.deb` | le Center, ses deux helpers, son action polkit, l'autostart de l'assistant |

Une seule version pour les deux : celle de `auxinux-center/Cargo.toml`. Le
Center exige le `auxi` de la même livraison.

### Versions d'AuxiNux OS : le paquet `auxinuxos-release`

Chaque ISO publiée est une **édition** d'AuxiNux OS : `0.2.0+AAAAMMJJ`, ou
`0.2.0+AAAAMMJJ.N` pour une deuxième ISO le même jour. Le paquet
`auxinuxos-release` de cette édition :

- annonce la nouvelle version dans le centre de contrôle (page Mises à jour),
  avec les nouveautés de `release/NOUVEAUTES`, et un bouton pour y passer ;
- exige les versions minimales d'auxi, du centre et du noyau : sa mise à jour
  tire le reste ;
- porte les réglages du système installé (`release/root/`) : associations de
  fichiers, Plasma, verrouillage, systemd, SDDM, Brave, hook d'instantané,
  hook initramfs, rafraîchissement quotidien des listes apt ;
- détourne `/usr/lib/os-release` de `base-files` : sans cela, une mise à jour de
  Debian remettait « Debian GNU/Linux » partout.

`auxi osupdate` l'installe s'il manque (machines d'avant le 2026-10-09).

Avant chaque ISO : écrire les nouveautés dans `release/NOUVEAUTES` (affichées
telles quelles, une ligne par point). L'édition est fixée par `build-image.sh`
(`AUXINUX_RELEASE`, par défaut la date du jour) et inscrite dans l'ISO.

### Publier une nouvelle version

1. Augmenter `version` dans `auxinux-center/Cargo.toml` (et `Cargo.lock`), et
   ajouter le `<release>` correspondant dans
   `auxinux-center/data/ca.auxinux.Center.metainfo.xml`.
2. Sur l'hôte de build : `auxinux-center/build.sh`, puis
   `packages/build-debs.sh --out ~/build/debs`.
3. Depuis le poste local :
   `packages/publish-debs.sh --dir ~/build/debs` (vérifications seulement),
   puis la même commande avec `--deploy`.
4. Pour une ISO : publier ses paquets (dont `auxinuxos-release` de la même
   édition) AVANT l'ISO. `image-builder/publish-iso.sh` lit l'édition dans
   l'ISO, en tire le nom publié, et refuse si le paquet n'est pas en ligne.

`publish-debs.sh` refuse une version qui n'est pas plus récente que celle déjà
publiée, et vérifie après coup l'index servi (y compris la présence
d'`auxinux-office`) et l'empreinte de chaque paquet téléchargé.

### Installations faites avant l'ISO 20261008

Leur `auxi` et leur Center ont été copiés par l'image, sans paquet : la mise à
jour du système n'installe pas un paquet que rien ne demande. Une seule fois :

```bash
sudo auxi set apt=true
sudo apt update
sudo apt install -o Dpkg::Options::=--force-confnew auxi auxinux-center auxinuxos-release
sudo auxi set apt=false
```

`--force-confnew` : `/etc/xdg/autostart/auxinux-assistant.desktop` existe déjà,
copié par l'image sans paquet ; sans l'option, dpkg demande s'il faut le
remplacer.
