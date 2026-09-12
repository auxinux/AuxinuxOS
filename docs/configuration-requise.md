# Configuration requise

`auxinux-hwcheck` mesure la machine et rend un verdict. C'est la première page
de l'installateur maison demandée le 2026-09-12 ; comme elle ne dépend ni du
partitionnement ni d'un toolkit graphique, elle est livrée séparément — et déjà
branchée sur le lanceur d'installation de la 0.2.0.

## Seuils

| | minimum (jaune) | recommandé (vert) |
|---|---|---|
| Mémoire | 4 Go | 8 Go et plus |
| Processeur | 2 cœurs | 4 cœurs et plus |
| Disque | 40 Go | 80 Go et plus |

**Sous le minimum : X rouge et installation bloquée.** Au minimum :
installation autorisée, éléments concernés en jaune. Au niveau recommandé :
vert.

### Pourquoi 3,6 Gio et pas 4,0

Une machine vendue avec 4 Go n'annonce jamais 4 GiB de `MemTotal` : le
firmware, le GPU intégré et le noyau en prélèvent. Exiger 4,0 GiB refuserait des
machines qui respectent le minimum annoncé. La borne est donc 3 774 873 kio.

## La carte vidéo ne bloque jamais

Elle est évaluée **pour chaque usage**, parce que la vraie question n'est pas
« ai-je un GPU » mais « est-ce que le jeu est possible sur cette machine ».

| | bureautique | multimédia | jeu |
|---|---|---|---|
| dédiée + Vulkan | vert | vert | **vert** |
| intégrée (Intel/AMD) | vert | vert si VA-API | jaune |
| virtualisée | vert | vert si VA-API | jaune |
| rendu logiciel (llvmpipe) | jaune | jaune | jaune |
| aucun pilote chargé | jaune | jaune | jaune |

La détection lit `/sys/class/drm`, donc **le pilote réellement chargé** : une
carte que le noyau ne pilote pas n'accélère rien, quoi qu'en dise `lspci`.
L'accélération réelle se distingue du rendu logiciel par le *renderer* OpenGL
(`llvmpipe` = logiciel).

### Heuristique « carte dédiée »

Dans l'ordre : vendeur NVIDIA (`0x10de`, jamais intégré à un processeur x86) ;
VRAM dédiée ≥ 4 Gio (les APU exposent 512 Mo à 2 Go prélevés sur la RAM) ; ou
deux GPU pilotés, ce qui signifie une machine hybride. **Faillible** sur une
carte dédiée récente de moins de 4 Gio — cas devenu rare, et le verdict est
alors jaune, donc jamais bloquant.

## Utilisation

```bash
auxinux-hwcheck          # tableau lisible, code de sortie 1 si bloqué
auxinux-hwcheck --json   # pour l'installateur et le centre de contrôle
```

Le lanceur d'installation l'appelle avant d'ouvrir Calamares et refuse
l'installation sur un verdict de blocage. **Sécurité positive** : il ne bloque
que sur un verdict explicite (code 1 *et* message correspondant). Si l'outil est
absent, plante, ou répond autre chose, l'installation continue — un défaut de
l'outil de contrôle ne doit jamais rendre une ISO inutilisable.

## Limites

- Couvert par `tests/test-hwcheck.sh` (34 assertions, `/proc` et `/sys`
  simulés). Aucune mesure sur du matériel réel varié.
- Le disque retenu est le plus grand périphérique bloc hors `loop`, `zram`,
  `sr`, `dm-` et `md`. Une machine dont le seul disque est un RAID logiciel
  (`md`) est donc mal évaluée.
- `vainfo` et `vulkaninfo` ne sont présents que si les couches multimédia et
  jeu sont installées : dans le live de la 0.2.0 elles le sont, sur un système
  minimal futur elles pourraient manquer, et les verdicts correspondants
  passeraient à jaune sans que la machine ait changé.
