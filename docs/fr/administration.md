# Administration

*[English](../en/administration.md) · [Retour au README](../../README.md)*

Pour installer Repère pour une équipe, le régler et savoir ce qu'il demande au domaine.

## Installer pour une équipe

Le zip d'une release contient tout ce qu'il faut : extrayez-le dans un dossier partagé ou sur chaque poste, et donnez un raccourci vers **Repère.cmd**. Repère.cmd :

- trouve une PowerShell 7.5 ou plus récente, et propose de l'installer avec winget s'il n'y en a pas ;
- débloque les fichiers téléchargés, pour que Windows ne refuse pas de les exécuter ;
- lance Repère sans fenêtre de console.

Chaque personne garde ses propres paramètres (voir plus bas). Repère agit avec les droits de la personne qui l'ouvre : il n'a besoin d'aucun compte de service ni d'aucune installation sur les contrôleurs de domaine.

## Options de lancement

Elles s'ajoutent à la cible du raccourci, après `Repère.cmd` :

```
"C:\Outils\Repere\Repère.cmd" -Domains a.local,b.local
```

| Option | Effet |
|---|---|
| `-Domains a.local,b.local` | Les domaines proposés. Par défaut, toute la forêt. |
| `-MoveRoots "OU=Postes,DC=…;OU=Kiosques,DC=…"` | Limite **Déplacer vers…** à ces OU, à la place de celles de **Paramètres**. Pratique pour un raccourci partagé. |
| `-Language fr` ou `-Language en` | Repère en français ou en anglais. Sans elle, Repère prend la langue choisie dans **Paramètres**, ou celle de Windows au premier lancement. |
| `-NoUpdateCheck` | Ne cherche pas de nouvelle version. |

Une liste s'écrit sans espace après les virgules.

## Ce que le domaine doit permettre

Repère ne demande aucun droit de plus que la console : chaque action réussit si votre compte peut la faire dans *Utilisateurs et ordinateurs Active Directory*.

| Pour | Il faut |
|---|---|
| Chercher | lire l'AD (tout utilisateur du domaine). |
| Modifier la description, déplacer, activer, désactiver, supprimer | les droits correspondants sur l'OU de l'ordinateur. |
| Clés BitLocker | lire les informations de récupération BitLocker ; les supprimer demande le droit de supprimer ces objets. |
| Mot de passe LAPS | lire le mot de passe LAPS de ces ordinateurs, et, pour Windows LAPS chiffré, le déchiffrer. |
| Utilisateurs : déverrouiller, nouveau mot de passe, groupes | les droits délégués au soutien sur ces comptes et ces groupes. |
| Outils à distance, Caractéristiques, Redémarrer | être administrateur de l'ordinateur. Caractéristiques et PowerShell à distance utilisent WinRM, ou DCOM. |
| Prochain nom avec SCCM | la console Configuration Manager sur l'ordinateur où Repère est ouvert, et des droits de lecture sur SCCM. |

### WinRM

**Caractéristiques**, **PowerShell à distance** et **Forcer les stratégies** passent par WinRM. Quand il n'est pas actif sur l'ordinateur visé, Repère propose de l'activer le temps de l'opération, puis le remet comme il était. **Lire par DCOM** lit les caractéristiques sans WinRM.

### Prendre la main

Il faut être administrateur de l'ordinateur, et :

- la stratégie *Définir les règles de contrôle à distance des sessions utilisateur des services Bureau à distance* (Configuration ordinateur › Modèles d'administration › Composants Windows › Services Bureau à distance › Hôte de la session Bureau à distance › Connexions) ;
- `AllowRemoteRPC = 1` (DWORD) dans `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server`, pour lister les sessions ;
- la règle de pare-feu *Remote Desktop - Shadow (TCP-In)*.

## Où Repère garde ses paramètres

Dans `%APPDATA%\Repere`, un fichier par partie, pour qu'un fichier abîmé ne fasse perdre que la sienne :

| Fichier | Contient |
|---|---|
| `apparence.json` | le mode, le thème et vos thèmes, la police, la taille du texte, la densité |
| `parametres.json` | **Déplacer vers**, le site SCCM, la langue, et la dernière version lancée, pour montrer **Nouveautés** une fois par mise à jour |
| `recherche.json` | le domaine, le type de recherche et les recherches récentes |
| `redemarrage.json` | le délai et le message de **Redémarrer…** |
| `motdepasse.json` | le choix de mot de passe, et le mot de passe par défaut, chiffré pour votre compte Windows |
| `prochainnom.json` | les modèles récents, les domaines cochés et les options de **Prochain nom…** |
| `fenetre.json` | la taille et la place de la fenêtre, et la page affichée |

Supprimer un fichier, Repère fermé, remet sa partie par défaut. Un fichier illisible est gardé tel quel et mis de côté sous `.illisible` au prochain enregistrement.

## Mises à jour

Au lancement, Repère demande à GitHub la dernière release ; s'il y en a une plus récente, un point apparaît sur **Paramètres**, avec un lien pour la télécharger. Rien n'est installé tout seul : remplacez le dossier par celui du nouveau zip, les paramètres restent. `-NoUpdateCheck` désactive cette vérification.

## Pour les développeurs

Le dépôt contient aussi ce que le zip n'a pas :

- `src\FakeAD` : un AD fictif pour essayer Repère sans domaine (`-FakeAD`, depuis le dépôt seulement) ;
- `tests` : les tests unitaires (Pester) et les tests de l'interface (`Test-RepereUI.ps1`) ;
- `tests\Capture-Docs.ps1` : refait les captures de cette documentation, en français et en anglais (`-Language en`) ;
- `tools\New-RepereRelease.ps1` : construit le zip d'une release et ses notes, tirées du [journal des versions](../../CHANGELOG.md). La version doit aussi être dans [CHANGELOG.en.md](../../CHANGELOG.en.md), que **Nouveautés** montre en anglais.
