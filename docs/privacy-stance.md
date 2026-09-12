# Vie privee

AuxiNux OS 0.2.0 vise une posture vie privee elevee pour le Canada.

## Regles

- aucune telemetrie activee par AuxiNuxOS;
- aucun compte cloud obligatoire;
- logiciels choisis en priorite pour limiter la collecte de donnees;
- preference pour Flatpak afin d'isoler les applications de bureau;
- outils de chiffrement et de nettoyage de metadonnees visibles;
- pare-feu disponible via UFW/GUFW.

## Mesures appliquees

- Brave: policy managee `/etc/brave/policies/managed/auxinux-privacy.json`
  desactivant les rapports de metriques, la collecte anonymisee, Sync, Rewards,
  Wallet, VPN et le service de conversation intégré. A confirmer: clef exacte de desactivation P3A selon
  la liste de politiques Brave en vigueur.

## Points a auditer

- Brave: confirmer la couverture P3A et les services optionnels restants;
- KDE Discover/PackageKit: privileges et confirmations;
- Wine: execution de binaires Windows et messages utilisateur;
- Calamares: partitionnement, creation utilisateur, permissions post-install;
- wrappers APT: contournement volontaire via `auxi set apt=true`.
