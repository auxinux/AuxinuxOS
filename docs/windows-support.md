# Applications Windows et jeux

## Trois couches, pas une

Wine seul ne couvre qu'une partie du besoin. Les cas d'usage sont différents et
appellent des outils différents.

| Usage | Outil | Pourquoi |
|---|---|---|
| Applications bureautiques | **Bottles** (Flatpak) | Un préfixe isolé par application, runners multiples, installateurs guidés |
| Jeux Steam | **Steam + Proton** (Flatpak) | Proton = Wine + DXVK/VKD3D + correctifs par jeu |
| Jeux Epic / GOG | **Heroic** (Flatpak) | Lanceur natif pour ces boutiques |
| Autres jeux, émulateurs | **Lutris** (Flatpak) | Scripts d'installation communautaires |
| Exécutable isolé | **Wine** (paquet DEB) | Dernier recours, préfixe dédié |

Aucun de ces Flatpak n'est embarqué dans l'ISO : Steam seul pèse plusieurs Go
et gonflerait l'image pour la majorité des utilisateurs. Ils s'installent à la
demande via **Applications Windows et jeux** (`auxinux-windows-setup`), qui les
présente avec une explication de ce que chacun sert — un utilisateur non
technique ne devinera jamais qu'il doit chercher « Bottles ».

## Ouverture d'un fichier `.exe`

`auxinux-windows-wizard` est associé aux types MIME `application/x-ms-dos-executable`,
`application/x-msi` et `application/x-ms-shortcut`. Il propose **trois** choix :

1. **Chercher une alternative Linux** (proposé par défaut) — ouvre le centre de
   contrôle.
2. **Installer dans un espace isolé avec Bottles** — installe Bottles si besoin,
   puis l'ouvre.
3. **Lancer directement avec Wine** — dernier recours.

### Le préfixe partagé, et pourquoi il a disparu

La version précédente posait une question oui/non puis exécutait
`wine "$fichier"`. Wine utilise alors le préfixe **par défaut**, `~/.wine`,
partagé par toutes les applications. Une application qui installe un runtime
cassé rendait toutes les autres inutilisables, sans que l'utilisateur ait le
moindre moyen de comprendre ni de nettoyer.

Chaque application a désormais son propre préfixe :

```
~/.local/share/auxinux/wine-prefixes/<nom-de-l-application>/
```

Tout annuler revient à supprimer ce dossier. `WINEDLLOVERRIDES=mscoree,mshtml=`
supprime au passage les deux fenêtres d'installation de mono/gecko, qui
s'ouvrent sinon au premier lancement sans explication.

## Paquets embarqués dans l'ISO

| Paquet | Rôle |
|---|---|
| `wine`, `winetricks` | Base Wine. Le métapaquet tire wine64 **et** wine32 |
| `mesa-vulkan-drivers`, `libvulkan1`, `vulkan-tools` | Vulkan — requis par DXVK/VKD3D, donc par Proton |
| `gamemode` | Bascule le gouverneur CPU et les priorités pendant une partie |
| `mangohud` | Superposition FPS et températures |

`q4wine` a été **retiré** : son interface est abandonnée en amont et elle
exposait la gestion brute des préfixes Wine, précisément ce qu'un utilisateur
non technique ne doit pas manipuler.

L'architecture **i386 est activée** dès le debootstrap. Sans elle, seules les
applications Windows 64 bits fonctionnent — ce qui exclut une grande partie des
logiciels anciens, précisément ceux pour lesquels on garde Wine.

## Limites

Voir [les limites connues](limitations.md). En particulier : rien de cette
couche n'a encore été testé en machine virtuelle.
