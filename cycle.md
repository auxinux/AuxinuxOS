# Cycle de vie d'AuxiNux OS

> **Calendrier prévisionnel.** Les dates ci-dessous sont des intentions, pas des
> engagements : elles peuvent bouger selon l'avancement du projet et le
> calendrier de Debian. Cette page est la référence consultée par
> [os.auxinux.ca](https://os.auxinux.ca/auxinuxos).
>
> Dernière mise à jour : 2026-10-28

## Base Debian et mises à jour de sécurité

AuxiNux OS est construit sur les dépôts de **Debian stable**. Les mises à jour
de sécurité et de maintenance des paquets de la base viennent directement de
Debian : une version d'AuxiNux OS est couverte tant que sa version de Debian
l'est.

| Base Debian | Nom de code | Sortie Debian | Sécurité Debian (jusqu'à) | Debian LTS (jusqu'à) | Statut pour AuxiNux OS |
|---|---|---|---|---|---|
| Debian 13 | trixie | 2025-08-09 | ~2028-08 | 2030-06-30 | **Base actuelle** |
| Debian 14 | forky | ~2027 (prévue) | ~3 ans après la sortie | ~5 ans après la sortie | Base prévue de la 2.x |

Les dates de fin de Debian sont celles annoncées par le projet Debian
(sécurité : environ 3 ans après la sortie ; LTS : environ 5 ans). Voir
<https://www.debian.org/releases/> et <https://wiki.debian.org/LTS>.

Ce qu'AuxiNux fournit lui-même (noyau AuxiNux, AuxiNux Center, AuxiNux Shell,
applications AuxiNux, outil `auxi`) est mis à jour par les dépôts AuxiNux, au
rythme des versions décrites ci-dessous.

## Numérotation des versions

Les versions suivent la forme **MAJEURE.MINEURE.CORRECTIVE** (ex. `1.2.3`).

| Niveau | Exemple | Rythme visé | Contenu |
|---|---|---|---|
| Majeure | `1.0`, `2.0`, `3.0` | Annuel | Grands changements : nouvelle base Debian, changements d'interface ou de fonctionnement importants. |
| Mineure | `1.1`, `1.2` | Aux 3 à 6 mois | Nouvelles fonctionnalités, nouvelle ISO, noyau plus récent. |
| Corrective | `1.1.1`, `1.1.2` | Au besoin | Corrections de bogues et de sécurité, sans nouvelle fonctionnalité. |

Les versions **0.x** (actuelles) sont des versions de développement et de
test : seule la dernière 0.x publiée est maintenue.

## Calendrier prévisionnel

| Version | Base Debian | Sortie visée | Statut |
|---|---|---|---|
| 0.5 | Debian 13 | 2026-10-27 | **Actuelle** (développement) |
| 1.0 | Debian 13 | Début 2027 | Prévue — première version stable |
| 1.x | Debian 13 | 2027, aux 3 à 6 mois | Prévue |
| 2.0 | Debian 14 | Début 2028 | Prévue — passage à Debian 14 |
| 2.x | Debian 14 | 2028, aux 3 à 6 mois | Prévue |
| 3.0 | Debian 14 | Début 2029 | Prévue |

Le passage à Debian 14 est prévu pour la 2.0, quelques mois après la sortie de
Debian 14, le temps que ses premières mises à jour correctives soient publiées.

## Durée de maintenance

- **Version mineure** : maintenue (versions correctives) jusqu'à la sortie de
  la version mineure suivante.
- **Version majeure** : la dernière mineure d'une version majeure reste
  maintenue environ **3 mois** après la sortie de la majeure suivante, pour
  laisser le temps de mettre à niveau.
- **Base Debian** : les mises à jour de sécurité de Debian continuent d'arriver
  tant que la version de Debian est maintenue (voir le premier tableau).

La mise à niveau se fait avec `auxi os upgrade` ou depuis AuxiNux Center ; un
instantané est pris automatiquement avant chaque montée de version.

## Éditions

Les éditions PC (amd64) et ARM (arm64) suivent le même cycle et les mêmes
numéros de version.
