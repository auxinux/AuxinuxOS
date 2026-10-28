# Cycle de vie d'AuxiNux OS

> **Calendrier prévisionnel.** Les dates ci-dessous sont des intentions, pas des
> engagements : elles peuvent bouger selon l'avancement du projet et le
> calendrier de Debian. Cette page est la référence consultée par
> [os.auxinux.ca](https://os.auxinux.ca/auxinuxos).
>
> Dernière mise à jour : 2026-10-28
>
> Les mêmes informations existent en format lisible par machine dans
> [`cycle.json`](cycle.json) (utilisé par le site). Les deux fichiers doivent
> être modifiés ensemble ; `tests/test-cycle.sh` vérifie qu'ils concordent.

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
(sécurité : environ 3 ans après la sortie ; LTS : environ 5 ans).
Il n'y a pas d'édition « LTS » séparée : chez Debian, les mises à jour LTS sont
publiées dans le même dépôt de sécurité (`trixie-security`), qu'AuxiNux OS
utilise déjà. Elles arrivent donc automatiquement avec les mises à jour
habituelles. Note : pendant la période LTS, Debian ne couvre plus tout à fait
tous les paquets (quelques-uns sont exclus et listés par le paquet
`debian-security-support`). Voir
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
| 1.0 | Debian 13 | Janvier-février 2027 | Prévue — première version stable |
| 1.x | Debian 13 | 2027, aux 3 à 6 mois | Prévue |
| 2.0 | Debian 14 | À déterminer | Prévue — passage à Debian 14 |

La 2.0 sera construite sur Debian 14 ; sa date dépendra de la sortie de
Debian 14.

## Durée de maintenance

- **Version mineure** : maintenue (versions correctives) jusqu'à la sortie de
  la version mineure suivante.
- **Changement de version majeure** : à la sortie de la 2.0, la 1.x reste
  maintenue environ **3 mois** de plus, le temps de mettre à niveau
  (même principe pour les majeures suivantes).
- **Limite Debian** : une version d'AuxiNux OS n'est jamais maintenue au-delà
  de la fin du support de sa base Debian (sécurité puis LTS). Quand Debian
  cesse de publier des mises à jour pour sa version, AuxiNux OS ne peut plus
  en fournir non plus.
- **Base Debian** : les mises à jour de sécurité de Debian continuent d'arriver
  tant que la version de Debian est maintenue (voir le premier tableau).

La mise à niveau se fait avec `auxi os upgrade` ou depuis AuxiNux Center ; un
instantané est pris automatiquement avant chaque montée de version.

## Éditions

Les éditions PC (amd64) et ARM (arm64) suivent le même cycle et les mêmes
numéros de version.
