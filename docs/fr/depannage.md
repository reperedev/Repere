# Dépannage

*[English](../en/troubleshooting.md) · [Retour au README](../../README.md)*

Ce que veulent dire les messages de Repère, et quoi faire.

## Au lancement

**« Repère demande PowerShell 7.5 ou plus récent »**
Repère.cmd propose de l'installer avec winget : répondez **O**. Sans winget, installez PowerShell 7.5 vous-même (`winget install --id Microsoft.PowerShell --source winget`, ou depuis le Microsoft Store), puis relancez Repère.cmd.

**« Module ActiveDirectory introuvable »**
Installez les outils RSAT pour Active Directory. Sur Windows 10 et 11 : Paramètres › Système › Fonctionnalités facultatives › Ajouter une fonctionnalité › *RSAT : outils Active Directory Domain Services*.

**« Cet ordinateur n'est pas joint à un domaine »**
Repère a besoin d'Active Directory : ouvrez-le sur un ordinateur du domaine.

**« WMI ne répond pas »**
Repère ne peut pas savoir si l'ordinateur est joint à un domaine. Redémarrer le service *Infrastructure de gestion Windows* (Winmgmt), ou l'ordinateur, règle souvent le problème.

**« Option de lancement inconnue »**
La cible du raccourci contient une option que Repère ne connaît pas, ou une liste avec des espaces. Écrivez `-Domains a.local,b.local`, sans espace après les virgules. Les options sont dans [Administration](administration.md#options-de-lancement).

**Rien ne s'ouvre après le double-clic**
Le premier lancement après le démarrage de Windows peut prendre une quinzaine de secondes ; l'écran de démarrage de Repère le montre. S'il n'apparaît pas, lancez Repère.cmd depuis une invite de commandes pour voir le message.

**La barre de l'écran de démarrage ne bouge pas**
Les animations de Windows sont désactivées (Paramètres › Accessibilité › Effets visuels). En Bureau à distance, Windows les désactive aussi, sauf si la connexion est rapide : dans la Connexion Bureau à distance, **Afficher les options › Expérience**, choisissez la vitesse la plus rapide (10 Mbits/s ou plus) ou cochez **Animation des menus et des fenêtres**.

## En cherchant

**« Aucun ordinateur trouvé »**
Le message dit où Repère a cherché. Essayez **Chercher dans tous les domaines**, vérifiez le type de recherche (**Nom contient** ou **Description contient**), ou **Retirer les critères avancés** si **Avancée** est actif.

**« Précisez la recherche, ou Tout afficher »**
La recherche a trouvé plus de résultats que la limite. Ajoutez des lettres, ou cliquez **Tout afficher** : la même recherche, sans limite, peut prendre un moment.

**« Sans réponse de… » ou « Recherche annulée »**
Un domaine ou un contrôleur de domaine n'a pas répondu à temps. Les résultats des autres domaines s'affichent quand même ; relancez avec F5.

**Un nom de la liste est introuvable**
Les noms introuvables s'affichent au-dessus des résultats, avec **Copier**. Cherchez-les sans domaine (`ORD-01`, pas `DEMO\ORD-01$`), ou dans **Tous les domaines**.

## En agissant sur un ordinateur

**« Éteint ou injoignable »**
L'ordinateur ne répond pas au ping : il est éteint, hors du réseau, ou un pare-feu bloque. **Vérifier en ligne** le reteste.

**Caractéristiques ou PowerShell à distance : « WinRM »**
WinRM n'est pas actif sur l'ordinateur. Repère propose de l'activer le temps de l'opération, puis le remet comme avant. Pour les Caractéristiques, **Lire par DCOM** lit sans WinRM, plus lentement.

**« Accès refusé »**
Votre compte n'a pas le droit de faire cette action sur cet ordinateur ou dans cette OU. Repère agit avec vos droits : demandez-les à l'administrateur du domaine.

**Prendre la main ne fonctionne pas**
La prise en main demande des réglages dans le domaine : voir [Administration](administration.md#prendre-la-main).

**Pas de clé BitLocker, ou pas de mot de passe LAPS**
Une notification le dit. Soit l'AD n'en a pas pour cet ordinateur, soit votre compte n'a pas le droit de les lire. Un mot de passe Windows LAPS chiffré demande aussi le droit de le déchiffrer.

**« Laissés de côté »**
Repère ne désactive, ne supprime ni ne déplace jamais un contrôleur de domaine, ni l'ordinateur où il est ouvert. Un ordinateur protégé contre la suppression accidentelle n'est pas déplacé.

**Prochain nom : « Vérification SCCM impossible »**
Le site SCCM n'est pas configuré, la console Configuration Manager manque sur cet ordinateur, ou votre compte n'a pas le droit de lire SCCM. La raison est affichée ; **Paramètres › SCCM › Tester** aide à trouver laquelle. Les noms proposés viennent alors de l'AD seul.

## Paramètres

**« parametres.json illisible »**
Le fichier a été modifié à la main et contient une erreur. Repère le garde tel quel et utilise les valeurs par défaut. Corrigez-le dans `%APPDATA%\Repere`, ou enregistrez un paramètre : le fichier est alors mis de côté sous `parametres.json.illisible`.

**Repère est en anglais (ou en français) et vous voulez l'autre langue**
**Paramètres › Apparence › Langue**, ou l'option de lancement `-Language fr` ou `-Language en`.

**Retrouver la fenêtre, les thèmes et les recherches par défaut**
Fermez Repère et supprimez le fichier correspondant dans `%APPDATA%\Repere` (voir [Administration](administration.md#où-repère-garde-ses-paramètres)).

## Autre chose ?

Ouvrez un ticket dans les [Issues](https://github.com/reperedev/Repere/issues), avec le message exact et ce que vous faisiez.
