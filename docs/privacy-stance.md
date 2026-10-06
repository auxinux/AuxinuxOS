# Vie privee

AuxiNux OS 0.2.0 vise une posture vie privee elevee pour le Canada.

## Regles

- aucune telemetrie activee par AuxiNuxOS;
- aucun compte cloud obligatoire;
- logiciels choisis en priorite pour limiter la collecte de donnees;
- preference pour Flatpak afin d'isoler les applications de bureau;
- outils de chiffrement et de nettoyage de metadonnees visibles;
- pare-feu disponible via UFW/GUFW.

## Bureau KDE Plasma (0.2.0)

Plasma livre sa telemetrie desactivee. AuxiNuxOS ne s'en contente pas: la
promesse doit tenir meme apres une mise a jour qui changerait un defaut amont.
Trois fichiers sous `/etc/xdg` (donc des DEFAUTS, que l'utilisateur reste libre
de changer pour lui-meme -- c'est ce que « consentement » veut dire):

| Fichier | Effet |
|---|---|
| `PlasmaUserFeedback` | `FeedbackLevel=0` — aucune statistique d'usage |
| `kdeglobals` | `StatisticsCollectionMode=NoTelemetry` pour les applications KDE |
| `baloofilerc` | indexation du contenu des fichiers desactivee |
| `kscreenlockerrc` | verrouillage automatique apres 10 min, et au reveil — **systeme installe uniquement** |

La session LIVE fait exception: elle ne se verrouille pas et n'eteint pas
l'ecran (surcharge dans le dossier personnel du compte live, supprime a
l'installation). Un visiteur qui laisse la machine deux minutes revenait sinon
devant un ecran noir, puis un mot de passe qu'il n'a jamais choisi.

Baloo n'envoie rien a personne: il est desactive pour la performance ET parce
que son index contient le TEXTE de tous les documents, dans une base non
chiffree, creee sans que l'utilisateur l'ait demandee.

Ecartes par arbitrage, pour la meme raison:

- `plasma-discover` (ramene PackageKit, un second chemin vers dpkg);
- `plasma-welcome` (recupere du contenu en ligne au premier demarrage);
- `plasma-browser-integration` et `kdeconnect` (service a l'ecoute sur le
  reseau local).

`tests/test-no-telemetry.sh` verifie tout ce tableau, plus l'absence de
`popularity-contest`, `whoopsie` et `apport` des listes de paquets. C'est un
controle STATIQUE: il ne regarde aucun trafic reseau.

## Mesures appliquees

- Aucune application imposee (2026-10-02): l'image est un socle, et
  l'assistant de premier demarrage PROPOSE navigateur, bureautique, lecteur,
  applications du profil et outils de vie privee. Rien n'est installe avant le
  recapitulatif, et Steam n'est jamais coche d'avance.
- Depot Brave livre DESACTIVE: actif, il ferait contacter Brave a chaque
  `apt update`, meme par qui ne l'utilise pas. L'assistant ne l'active que si
  Brave est choisi (check-rootfs.sh refuse une image ou il est actif).
- Brave: policy managee `/etc/brave/policies/managed/auxinux-privacy.json`
  desactivant les rapports de metriques, la collecte anonymisee, Sync, Rewards,
  Wallet, VPN et le service de conversation intégré. A confirmer: clef exacte de desactivation P3A selon
  la liste de politiques Brave en vigueur.

- Heure (NTP), decision du 2026-10-05: `systemd-timesyncd` interroge les
  serveurs du Conseil national de recherches du Canada (`time.nrc.ca`,
  `time.chu.nrc.ca`), organisme public qui tient l'heure officielle du Canada;
  le pool Debian ne sert qu'en secours. Une synchronisation est indispensable:
  sans heure juste, aucun certificat HTTPS ne se verifie (installateur, apt,
  Flatpak), ce qu'a montre la premiere installation sur une vraie machine.
  L'installateur console peut aussi lire l'en-tete `Date` de dep.auxinux.ca
  quand NTP est filtre. Fichier: `/etc/systemd/timesyncd.conf.d/50-auxinux.conf`,
  verifie par `tests/test-no-telemetry.sh`.

## Points a auditer

- **Audit reseau reel**: demarrer l'image en VM avec capture du trafic et
  refuser toute destination hors liste blanche. C'est la seule verification qui
  transformerait la promesse en preuve; `tests/test-no-telemetry.sh` n'en est
  que la moitie statique.
- A decider explicitement, destination par destination: verification de
  connectivite de NetworkManager, requetes Flathub du centre de controle (NTP:
  decide, voir plus haut).
- Steam (profil Jeu) collecte pour son compte: son installation en Flatpak, a la
  demande, doit etre un acte explicite de l'utilisateur -- jamais une case
  pre-cochee. Respecte par l'assistant de premier demarrage (Steam propose,
  decoche).
- Brave: confirmer la couverture P3A et les services optionnels restants;
- Wine: execution de binaires Windows et messages utilisateur;
- Calamares: partitionnement, creation utilisateur, permissions post-install;
- wrappers APT: contournement volontaire via `auxi set apt=true`.
