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

### Publier une nouvelle version

1. Augmenter `version` dans `auxinux-center/Cargo.toml` (et `Cargo.lock`), et
   ajouter le `<release>` correspondant dans
   `auxinux-center/data/ca.auxinux.Center.metainfo.xml`.
2. Sur l'hôte de build : `auxinux-center/build.sh`, puis
   `packages/build-debs.sh --out ~/build/debs`.
3. Depuis le poste local :
   `packages/publish-debs.sh --dir ~/build/debs` (vérifications seulement),
   puis la même commande avec `--deploy`.

`publish-debs.sh` refuse une version qui n'est pas plus récente que celle déjà
publiée, et vérifie après coup l'index servi (y compris la présence
d'`auxinux-office`) et l'empreinte de chaque paquet téléchargé.

### Installations faites avant la 0.2.1

Leur `auxi` et leur Center ont été copiés par l'image, sans paquet : la mise à
jour du système n'installe pas un paquet que rien ne demande. Une seule fois :

```bash
sudo auxi set apt=true
sudo apt update
sudo apt install -o Dpkg::Options::=--force-confnew auxi auxinux-center
sudo auxi set apt=false
```

`--force-confnew` : `/etc/xdg/autostart/auxinux-assistant.desktop` existe déjà,
copié par l'image sans paquet ; sans l'option, dpkg demande s'il faut le
remplacer.
