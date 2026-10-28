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

## Applications Windows (auxiwine), depuis AuxiNux Shell 0.3.28

Installer un programme Windows créait un espace Wine ou une bouteille Bottles,
mais rien ne les regroupait : pas de liste, pas de désinstallation, des
dossiers cachés à deux endroits. **Applications Windows** (`auxiwine`, dans
le paquet `auxinux-shell`) est désormais l'unique point d'entrée :

- **Mes applications** : une fiche par application, quel que soit le moteur
  (Wine ou Bottles) : ouvrir, épingler, raccourci, lecteur C:\,
  désinstaller un programme, version de Windows, mise à l'échelle,
  composants winetricks, supprimer l'espace.
- **Installer** : le parcours de l'assistant ci-dessous, dans l'application ;
  plus les lanceurs Flatpak (Bottles, Steam, Heroic, Lutris).
- **Entretien** : place occupée, raccourcis orphelins, espaces vides, état de
  Wine 32 bits et de Bottles.

Toutes les installations sont au même endroit :

```
~/.local/share/auxinux/windows/
├── wine/<application>/          préfixes Wine
└── bouteilles/<application>/    bouteilles Bottles (custom_bottles_path)
```

Les anciens emplacements (`~/.local/share/auxinux/wine-prefixes`, dossier
par défaut de Bottles) sont regroupés d'un clic. AuxiNux OS Center l'ouvre
depuis Applications ; `auxiwine --installer FICHIER` est l'association des
`.exe` et `.msi` dans la session AuxiNux.

`auxinux-windows-wizard` passe la main à `auxiwine` dès qu'il est installé et
ne reste qu'en secours (`AUXINUX_WIZARD_LEGACY=1` force l'ancien parcours).

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
