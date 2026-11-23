# Journal des versions

## 0.15.1 — 2026-11-23

### Ordinateurs, Utilisateurs et Groupes
- **Nouveautés** : une fenêtre résume ce qui a changé au premier lancement d'une nouvelle version. **Paramètres › Nouveautés** la rouvre.
- **La fenêtre s'ouvre au centre de l'écran de la souris**, devant les autres programmes, à sa taille habituelle.
- **L'info-bulle du temps de recherche** donne un domaine par ligne, les temps alignés.

### Ordinateurs
- **Propriétés…** (clic droit › Active Directory, ou Alt+Entrée) : les propriétés AD d'un ordinateur, même éteint. On y change la description, l'état, l'OU, l'emplacement, **Géré par**, les groupes et la protection contre la suppression.
- **Prochain nom…** et **Paramètres › SCCM** disent en une ligne quand mettre à jour la console Configuration Manager.

### Utilisateurs
- **Le nouveau mot de passe est masqué** après **Nouveau mot de passe…** : l'œil l'affiche, **Copier** le copie.

### Utilisateurs et Groupes
- **Propriétés** : au-delà de 10 groupes, une case filtre **Groupes** et **Membre de** par nom ou description.

## 0.15.0 — 2026-11-19

### Ordinateurs, Utilisateurs et Groupes
- **L'info-bulle de la case de recherche suit le type de recherche**, comme le texte dans la case. Elle dit aussi quand le texte est facultatif (**Verrouillés**, **Désactivés**, **Sans membres**), et la description des ordinateurs a la sienne.
- **Le texte tapé ne saute plus d'un pixel** en Bureau à distance avec Inter, Bahnschrift, Verdana ou Tahoma, surtout en densité **Compacte**.
- **Repère garde son propre bouton dans la barre des tâches** : il pouvait de nouveau être regroupé avec PowerShell.

### Ordinateurs
- **Prochain nom…** a son bouton dans la barre d'actions, son raccourci **Ctrl+N** et un clic droit, **Prochain nom de cette série…**. Ce n'est plus un type de recherche.
  - Le clic droit part du nom de l'ordinateur (`ORD-0143` donne la série `ORD-####`). Le bouton et Ctrl+N font de même avec un ordinateur sélectionné ; sans sélection, ils reprennent le dernier modèle utilisé.
  - La fenêtre ne descend plus sous 1122 pixels de large (1142 avec plusieurs domaines), pour que le bouton ne fasse pas perdre leur nom aux autres.
- **Prochain nom…** avec SCCM ne se contredit plus : sous les noms proposés, SCCM dit seulement « Pas dans SCCM. », et la ligne du compte compte les noms de la série qui ne sont que dans SCCM, sans ceux que l'AD a déjà.
- **Caractéristiques** copie et exporte « Libellé : valeur », sans espaces d'alignement, pour que le texte reste droit une fois collé dans Teams, Outlook ou un billet. Une valeur sur plusieurs lignes (adresses IP, disques, écrans) passe sous son libellé.
- **Caractéristiques** dit les choses une seule fois :
  - **Mémoire** donne le fabricant et la référence des barrettes (un code JEDEC comme 80CE devient Samsung).
  - **Processeur** n'écrit plus deux fois le fabricant, (R), (TM), CPU ni la vitesse.
  - **Station d'accueil** ne liste plus deux fois le même périphérique ni son propre nom.
  - Un champ sans valeur disparaît, dans la fenêtre comme dans le rapport. Le micrologiciel d'une station reste « Non communiqué par Windows » : aucune source fiable ne le donne à distance.
- **Activer WinRM** (**PowerShell à distance**, **Caractéristiques**) et **Forcer les stratégies** ne finissent plus sur « The CancellationTokenSource has been disposed » avec PowerShell 7.6 ou plus récent. Le terminal ou la fenêtre s'ouvre du premier coup, et Repère continue si WinRM répond malgré une erreur. Pendant l'activation (jusqu'à une minute), la barre du bas affiche « ORD-05 : activation de WinRM… ».
- **Forcer les stratégies** dit tout de suite qu'il est lancé : « ORD-05 : en cours… » reste en bas de la fenêtre pendant gpupdate (jusqu'à 2 minutes), puis devient le résultat en quelques mots, le détail étant dans l'info-bulle. Un échec reste affiché jusqu'à ce qu'on le ferme. Un second clic pendant la mise à jour ne la relance pas.
- **La page dit « Ordinateurs »** et compte des ordinateurs (« 12 ordinateurs »), comme Utilisateurs et Groupes comptent les leurs. Exporter et le clic droit aussi.
- **Sans description** et **Liste de noms** n'affichent plus la case de recherche inutile : l'autre prend toute la barre, et **Ctrl+F** va à la case affichée.
- **Les autres cases inutilisées** (**Autre** dans **Nouveau mot de passe…**, **Commencer à** dans **Prochain nom…**, la durée de **Dernière connexion**) sont grisées, avec leur texte en pâle. La raison est dans l'info-bulle.

### Utilisateurs
- **Retirer d'un groupe…** a son bouton dans la barre d'actions, à côté d'**Ajouter à un groupe…**, allumé dans les mêmes cas que dans le clic droit.
- **Le clic droit** range **Comparer les groupes…**, **Ajouter à un groupe…** et **Retirer d'un groupe…** dans un sous-menu **Groupes**, et les copies dans **Copier**, comme sur Ordinateurs.
- **Liste d'identifiants** lit les noms séparés par des virgules (« Jean Bertrand, Léa Perrin ») et toutes les adresses d'un courriel copiées sur une ligne, pas seulement la première.
- **Nouveau mot de passe…** ouvre une fenêtre du même nom, et non plus « Réinitialiser le mot de passe ». Son info-bulle dit ce qu'il propose : un mot de passe généré, celui par défaut ou un autre.

### Groupes
- **Ajouter des membres…** est dans la barre d'actions et le clic droit, pour un groupe à la fois : le même choix de membres que dans Propriétés, sans l'ouvrir d'abord. Un groupe privilégié (Admins du domaine…) demande une seconde confirmation.
- **Liste de noms** sépare les noms par des virgules (« GG-Accueil, GG-VPN »), comme dans un courriel. Les espaces restent dans les noms.
- **Le clic droit** range les copies dans un sous-menu **Copier**, comme sur Ordinateurs.

### Paramètres
- **Raccourcis** est plus clair : « ↓ (champ de recherche) » et « Clic droit ou Maj+F10 ». F2 et Suppr sont sous **Ordinateurs**, la seule page qui les a, avec le double-clic. Ctrl+N est listé, une section **Propriétés** donne F5 et Échap, et Ctrl+C dit qu'il copie les identifiants sur **Utilisateurs**.
- **SCCM** n'affiche plus « Enregistré » : seuls un problème et « SCCM désactivé » s'affichent encore.

## 0.14.1 — 2026-11-16

### Ordinateurs
- **Recherche avancée** : la case **OU nommées** est vide au départ ; tapez le début du nom des OU où chercher. Une recherche enregistrée avant la version 0.11.0 revient sans la case qui la limitait à certaines OU.

### Documentation
- **La documentation est refaite**, en français et en anglais : un README court pour commencer, puis un guide de chaque page, le dépannage par message et l'administration (options de lancement, droits, paramètres). Les captures montrent Repère tel qu'il est aujourd'hui.

## 0.14.0 — 2026-11-16

### Ordinateurs, Utilisateurs et Groupes
- **Une nouvelle icône** : une boussole dessinée à la main sur la couleur d'accent de Repère, plus grande dans la barre de titre.
- **Repère a son propre bouton dans la barre des tâches**, à son icône, au lieu d'être regroupé avec PowerShell. Épinglé, il lance Repère avec les mêmes options, et non une fenêtre PowerShell.
- **Repère s'ouvre plus vite** : Repère.cmd ne relance plus PowerShell à chaque démarrage pour vérifier la version (il retient celle qu'il a déjà vérifiée), et le thème se met en place plus vite. La fenêtre s'affiche environ une demi-seconde plus tôt.
- **Un écran de démarrage** montre le logo de Repère et une barre qui défile pendant que la fenêtre se prépare : deux secondes d'habitude, jusqu'à une quinzaine au premier lancement après le démarrage de Windows. Avant, on pouvait croire que le double-clic n'avait pas marché et en refaire un, qui ouvrait un deuxième Repère.
  - Il suit le mode clair ou sombre choisi et s'affiche là où la fenêtre s'ouvrira.
  - Il ne prend jamais le clavier : ce qu'on tape va où on était. On peut le faire glisser, s'il cache quelque chose.
- **Installer PowerShell depuis Repère.cmd** démarre Repère une fois l'installation finie. Avant, Repère.cmd redemandait PowerShell 7.5 juste après l'avoir installé, parce que winget l'installe maintenant depuis le Microsoft Store, où il ne le cherchait pas.
  - Repère.cmd trouve aussi une PowerShell assez récente installée à côté d'une plus ancienne, ou que la console ouverte avant l'installation ne voit pas encore.
  - Quand winget n'a rien installé, il le dit, avec son code.

## 0.13.0 — 2026-11-14

### Ordinateurs

#### Prochain nom…
- **Prochain nom…**, à la fin de la liste des types de recherche, trouve le prochain nom libre d'une série, sans syntaxe à apprendre : tapez le début d'un nom et cliquez une série déjà dans l'AD, ou tapez un vrai nom (`ORD-0143` devient `ORD-####`).
  - Le nom s'affiche en blocs ; un clic fixe un bloc ou le fait varier, et le champ le reprend aussitôt. `ORD-AAA-####` fonctionne aussi, et `LABO` ou `LAPTOP` restent tels quels.
  - Une série compte ses noms, comme « déjà pris » : un nom présent dans deux domaines compte une fois. Avec SCCM, « déjà pris » dit aussi combien de noms ne sont que dans SCCM.
  - **Options** : ordre aléatoire, trous comblés, nom de départ et caractères à éviter. **Rechercher** relit l'AD, pour un ordinateur ajouté depuis.
  - **Configurer…** ouvre Paramètres › SCCM, et Prochain nom revient, sur le même modèle, quand Paramètres se ferme.
  - La fenêtre garde la même hauteur pendant qu'on tape.
- **Prochain nom…** retient les domaines cochés d'une fois à l'autre ; la première fois, seul le domaine choisi sur la page Ordinateurs est coché.
  - Avec plus de trois domaines, **Filtrer les domaines** cache ceux qui ne contiennent pas le texte tapé, sans les décocher. **Tous** et **Aucun** ne touchent alors que ceux affichés, et Échap efface le filtre.
  - Un modèle commence par un texte fixe, pour ne pas interroger tout l'AD.
  - Quand **Exclure** ne laisse que `0` au compteur, `ORD-#` donne `ORD-0`, et une série pleine le dit aussitôt.

#### Caractéristiques
- **Les valeurs sont rangées par sujet**, dans le même ordre à l'écran, dans Copier et dans Exporter.
  - **Général** montre l'ordinateur et son utilisateur, puis la machine, Windows et le BIOS. Réduit, il montre aussi le numéro de série.
  - **Réseau** et **Processeur** ont trois colonnes, pour que leurs longues valeurs tiennent sur une ligne.
  - **Batterie** et **Écrans** commencent par ce qu'on cherche le plus.
- **Une section Station d'accueil**, après **Écrans** et **Batterie**, dit si une station est connectée, son modèle et son pilote quand Windows les donne, et dit franchement quand il ne les donne pas (le micrologiciel, toujours).
  - Une station reconnue seulement à des indices, comme une carte réseau USB, n'est pas annoncée comme connectée.
  - Ces deux sections ne s'affichent que pour un portable, ou quand l'ordinateur a une batterie ou une station, à l'écran comme dans Copier et Exporter.
- **Les alertes tiennent sur une ligne** : la première, et **Tout voir (3)** pour la liste, pour que la bande ne prenne pas la place des sections. Chaque section garde son ⚠. **Mémoire** et **Disques** n'écrivent plus « module(s) » ni « disque(s) ».
- **Les sections ne descendent plus à la fin de la lecture** : les alertes (« Volume C: plein à 93 % ») et les sections non lues s'affichent en bas de la fenêtre, toujours en vue.
  - Une section ouverte d'un clic défile pour se montrer, **Logiciels** surtout, qui s'ouvrait hors de vue. **Tout développer** ne fait pas défiler.
- **Logiciels** montre la date d'installation comme le reste de Repère (8/15/2024 en anglais), et la colonne se trie par date. Une date à la façon d'un installateur (15/08/2024) est lue quand le jour et le mois ne peuvent pas s'inverser ; une date douteuse (2025610, 20241399) n'est pas affichée, plutôt qu'une fausse date.
- **Le texte sous le nom de l'ordinateur** (aussi dans **Mot de passe LAPS** et **Clés BitLocker**) finit par « … » quand il ne tient pas, au lieu d'être coupé sous les boutons. Caractéristiques le montre en entier dans son info-bulle. Dans **Clés BitLocker**, l'ID d'une clé finit aussi par « … », entier dans son info-bulle, et « La plus récente » passe sous la date quand la place manque.
- **L'ordinateur est joint avant l'ouverture de la fenêtre**, et une notification le dit pendant ce temps.
  - Éteint, injoignable, absent du DNS ou accès refusé : Repère le dit en quelques secondes, sans fenêtre.
  - Sans WinRM, Repère le dit et propose de l'activer le temps de la lecture, comme PowerShell à distance : il est remis comme avant quand la fenêtre se ferme. **Lire par DCOM** lit sans l'activer, plus lentement.
- **Un ordinateur du même nom que le vôtre dans un autre domaine** (`PC-001.lyon.corp`, ouvert depuis `PC-001.paris.corp`) est bien lu. Avant, la fenêtre portait son nom mais montrait votre matériel, votre utilisateur, vos logiciels et vos alertes.

#### Recherche
- **Recherche avancée** : « à 2 semaines près » s'affiche à côté de **Dernière connexion il y a**, au lieu d'une note de deux lignes. Les unités (jours, semaines, mois, ans) ont la même largeur.
  - La fenêtre défile quand elle ne tient pas sous **Avancée** (texte **Très grande** sur un petit écran), au lieu de passer sous la barre des tâches.
  - **Dernière connexion** : « Au moins » devient « Plus de » (« il y a plus de 90 jours »), ici et dans le filtre de la colonne. Sur « Peu importe », la durée et son unité sont grisées, et la case affiche « Non utilisé » en entier.
- **Les résultats sont triés par nom**, comme dans Utilisateurs et Groupes, et par description seulement quand on a cherché une description. Une recherche par nom ne commence donc plus par les ordinateurs sans description. La colonne triée montre sa flèche, et un tri choisi en cliquant une colonne reste d'une recherche à l'autre.
- **Une recherche qui trouve un seul ordinateur** vérifie s'il est en ligne, sans attendre un clic.
- **Une recherche qui ne trouve rien** dit où elle a cherché (« Aucun ordinateur trouvé dans demo.local. ») et ce qu'elle cherchait (« Nom contient « ORD » · Description contient « accueil » · désactivés », comme les recherches récentes).
  - Elle propose la suite : **Chercher dans tous les domaines** quand elle n'a cherché que dans un, et **Retirer les critères avancés** quand ceux de la Recherche avancée l'ont restreinte. Ces liens relancent la recherche qui n'a rien trouvé, même si les cases ont changé depuis.
  - Quand le filtre cache tous les résultats, **Effacer le filtre** les montre de nouveau. La grille vide ne parle plus de sélectionner des résultats.
- **Description contient**, **commence par** et **termine par** ignorent les espaces collées autour de la description, comme les recherches récentes : « accueil » collé avec une espace trouve les mêmes ordinateurs que depuis **Recherches récentes**, au lieu de rien.
- **Adresse IP** et **ID de clé BitLocker** demandent l'adresse ou la clé quand elle manque, et non une partie du nom : le nom y est facultatif, et sa case le dit.
- **Adresse IP** sans nom DNS demande une partie du nom sous sa case, qui reçoit le curseur, au lieu d'une erreur en bas de la fenêtre.
  - Un nom qui trouve plus de 300 ordinateurs est dit trop large.
  - La grille dit « Aucun nom DNS pour 10.0.1.14. » plutôt que « La recherche a échoué ».
  - Dans tous les domaines, un domaine qui trouve l'ordinateur suffit : rien n'est demandé.
- **Liste de noms** montre les noms introuvables au-dessus des résultats, dans un bandeau orange marqué ⚠, avec **Copier** pour les copier tous, un par ligne, au lieu de les ajouter au compte en bas de la fenêtre.
  - Sur les trois pages, le bandeau montre autant de noms qu'il en tient sur sa ligne, puis combien d'autres, et s'ajuste quand la fenêtre change de largeur.
  - Quand un domaine n'a pas répondu, le bandeau le dit : ces noms y sont peut-être.
- **La colonne État s'appelle maintenant Compte**, dans les résultats, Exporter et la Recherche avancée : elle dit si le compte est activé dans l'AD, et non si l'ordinateur est allumé, comme **En ligne** juste à côté.
- **Emplacement** montre une virgule dans le nom d'une OU sans la barre oblique inverse de l'AD.

#### Actions
- **Le clic droit a un sous-menu Copier** : le nom, **les noms sur une ligne** (séparés par des virgules, pour un champ d'une seule ligne, où les sauts de ligne disparaissent) et **les lignes**.
- **Le clic droit place ses icônes au pixel près**, pour qu'elles ne changent plus de taille au passage de la souris, et la flèche d'un sous-menu ne touche plus son nom (« Clés et mots de passe › » dans une police large).
- **Déplacer vers…** : une OU choisie dans un domaine enfant ne vide plus la liste de son domaine parent, et effacer le filtre garde la destination choisie. Une OU que le filtre cache cesse d'être la destination.
- **Un ordinateur éteint ou injoignable** le dit dans une notification, comme **Vérifier en ligne**, et non plus dans une fenêtre à fermer : dans **Caractéristiques** (hors ligne, absent du DNS, ou sans réponse après 30 secondes), **PowerShell à distance**, **Forcer les stratégies** (les messages de Windows dans son info-bulle), **Prendre la main** et **Redémarrer**. Un accès refusé ou une autre erreur garde sa fenêtre, avec le message de Windows.
- **Clés BitLocker** et **Mot de passe LAPS** n'ouvrent plus de fenêtre pour dire qu'il n'y a rien : une notification le dit, ou, si la lecture a échoué, le rapport dit pour quels ordinateurs et pourquoi. Le bas de la fenêtre LAPS ne parle plus du mot de passe quand aucun n'est lisible.
- **Clés BitLocker… › Sélectionner les anciennes** ne coche plus la clé qu'un disque utilise.
  - Une clé dont l'AD n'indique pas le volume compte pour un disque à part, marqué « Volume inconnu » : la sélection la laisse de côté, et la supprimer demande la même mise en garde que la plus récente d'un disque. Avant, toutes ces clés d'un ordinateur comptaient pour un seul disque, et celle de l'autre disque passait pour une ancienne.
  - Les clés se trient à la seconde près, et non plus à la minute en heure locale : deux clés enregistrées dans la même minute, ou autour du changement d'heure d'automne, ne s'inversent plus.
- **Désactiver…**, **Supprimer de l'AD…** et **Déplacer vers…** :
  - reconnaissent l'ordinateur où Repère est ouvert même quand son nom dans l'AD n'est pas celui de Windows (objet renommé, compte créé d'avance sous un autre nom, ordinateur renommé mais pas encore redémarré). Il est laissé de côté, comme quand les deux noms sont les mêmes ;
  - ne figent plus la fenêtre pendant qu'ils demandent à l'AD quels ordinateurs sont des contrôleurs de domaine : la vérification se fait en arrière-plan, et la confirmation s'ouvre quand l'AD a répondu. Un deuxième clic pendant ce temps ne la demande pas deux fois.

#### WinRM et tâches à distance
- **Caractéristiques** et **PowerShell à distance**, sur un ordinateur qui répond au ping mais ni à WinRM ni à DCOM, proposent d'essayer d'activer WinRM, ou, pour Caractéristiques, de lire par DCOM : un pare-feu ne fait peut-être que les ralentir.
- **Quand Repère active WinRM**, chaque technicien a sa propre règle de pare-feu, et WinRM n'est remis comme avant qu'à la fin de la dernière session : la fermeture d'un terminal ne coupe plus celui d'un collègue sur le même ordinateur.
  - Une règle que Repère n'a pas pu supprimer est signalée au lieu de « ✔ WinRM remis comme avant », et une erreur de Repère n'est plus présentée comme « ordinateur injoignable ».
  - Après l'activation, Repère attend que WinRM réponde à votre compte, jusqu'à 20 secondes, avant d'ouvrir le terminal ou la fenêtre, et non plus seulement que son port s'ouvre.
  - La fenêtre qui propose **Activer WinRM** s'élargit quand ses boutons ne tiennent plus côte à côte, en texte **Grande** ou avec une police plus large.
- **Forcer les stratégies** et **PowerShell à distance** fonctionnent sans WinRM quel que soit le format régional de Windows. En finnois ou en danois, la tâche planifiée qui les exécute recevait une heure de fin que Windows ne savait pas lire, et ils échouaient ; en thaï, une tâche que Repère n'avait pas pu supprimer restait sur l'ordinateur au lieu d'expirer après 30 minutes.
  - Le nom proposé par **Exporter** et celui des fichiers de **Caractéristiques › Exporter** gardent une date du calendrier grégorien (2026, et non 2569 en thaï), pour que les exports se trient par date.

### Utilisateurs
- **Propriétés** : **Modifier…** dans les cartes **Identité**, **Organisation** et **Profil** change leurs valeurs dans l'AD, avec **Enregistrer** (Entrée) et **Annuler** (Échap) dans la carte ; le **Responsable** se choisit par une recherche.
  - Seules les valeurs changées sont envoyées. Une valeur trop longue, un lecteur ou un chemin invalide sont signalés avant l'envoi.
  - Un champ que l'AD refuse (droits) est nommé dans la carte, qui garde ce qui a été tapé, et les autres sont enregistrés.
  - Repère ne crée pas le dossier de base. La ligne de la page suit.
- **Propriétés** : l'en-tête ne montre que ce qui demande attention (verrouillé, désactivé, expiration proche) ; « Compte activé » n'y est plus, **Compte › État** le dit. En texte **Très grande**, les étiquettes ne passent plus chacune sur sa ligne.
- **Propriétés**, **Caractéristiques** et **Comparer les groupes** : les étiquettes des lignes (« Utilisateur », « Directe », « Sécurité », « Système »…) ne ressemblent plus à des boutons. Elles sont plus petites, sans gras ni couleur d'accent, et ont le même style dans les trois fenêtres.
- Les colonnes **Identifiant** et **Dernière connexion** sont assez larges pour leur bouton de filtre, qui était coupé.
- **Propriétés › Groupes** n'a plus de case à cocher sur la ligne qui dit qu'un domaine n'a pas pu être lu, ni sur un groupe non lu : **Retirer…** échouait sur elles.
- **Comparer avec…** nomme sous la liste le domaine qui n'a pas pu être cherché : l'autre utilisateur y est peut-être.

### Ordinateurs, Utilisateurs et Groupes

#### Recherche
- **Recherches récentes** décrit une recherche de la même façon sur les trois pages : le type de recherche en mots, puis le texte cherché, puis le domaine, par exemple « Nom contient « ORD » · Description commence par « acc » — demo.local ».
  - Une description cherchée ne ressemble plus à un nom, et « commence par » ou « termine par » ne tient plus à des points de suspension.
  - Seules une liste (« liste : a, b, c (+12) ») et une adresse (« IP 10.0.1.14 ») ne nomment pas leur type.
  - Une recherche trop longue pour le menu se termine par des points de suspension, et son info-bulle la donne en entier.
- **Ce qui manque pour chercher** s'affiche juste sous la case à remplir, encadrée en rouge, et le curseur s'y place, au lieu d'un petit texte rouge en bas de la fenêtre. Le message disparaît dès qu'on tape, et les résultats précédents restent affichés.
- **Après une recherche**, rien n'est sélectionné : aucune action ne vise un résultat qu'on n'a pas choisi. Les flèches du clavier parcourent aussitôt les résultats, ↓ à partir du premier et ↑ à partir du dernier. Ctrl+F revient au champ de recherche.
- **Utilisateurs** et **Groupes** : une recherche récente, ou Entrée dans la case, pendant une recherche la remplace, comme dans Ordinateurs. Elle était ignorée sans rien dire, et les résultats de l'ancienne s'affichaient ensuite sous les cases de la nouvelle. Lancer une recherche récente ou la Recherche avancée pendant une recherche la remplace aussi.
- **Tout afficher**, après une recherche annulée avant qu'un domaine ait répondu, relance la recherche dont les résultats sont affichés, et non celle qui a été annulée : elle pouvait interroger toute la forêt sans limite et remplacer ces résultats.
- **Liste d'identifiants** et **Liste de noms**, dans Utilisateurs et Groupes, disent quel domaine n'a pas répondu, ou a été annulé, à la suite des introuvables (« 2 introuvables : pbertrand, inconnu · sans réponse de nord.demo.local »), comme Ordinateurs : ces comptes et ces groupes y sont peut-être, et ne sont plus présentés comme absents de l'AD.
- **Une case qui ne sert pas** ne ressemble plus à une case vide : elle est grisée, sans cadre, et dit « Non utilisé », avec la raison en info-bulle. Ce qui y était tapé n'est que caché, et revient quand la case sert de nouveau. C'est le cas de la description pour **Sans description**, du nom pour **Liste de noms**, de **Autre** dans **Réinitialiser le mot de passe** tant qu'il n'est pas choisi, et de **Commencer à** dans **Prochain nom…** en ordre aléatoire.

#### Résultats et copie
- **Le texte des résultats se sélectionne** : glissez sur un texte pour en sélectionner une partie, puis Ctrl+C. Sans texte sélectionné, Ctrl+C copie toujours les noms.
- **Copier les lignes** (Ctrl+Maj+C) copie les lignes sélectionnées, avec les mêmes colonnes qu'Exporter : elles se collent en colonnes dans Excel.
- **Les boutons Copier** disent sur eux-mêmes que la copie est faite : une coche verte et « Copié » pendant un instant, sur le dernier bouton cliqué, dans **Clés BitLocker…**, **Mot de passe LAPS…**, **Propriétés** et **Nouveau mot de passe…**. Le Narrateur l'annonce, et le curseur reste sur le bouton. Quand un autre programme occupe le presse-papiers, le bouton montre une croix rouge, « Copie impossible », et le bas de la fenêtre le dit.
- **Clés BitLocker**, pour plusieurs ordinateurs, nomme ceux qui n'ont pas de clé sur une seule ligne (« Clé BitLocker manquante : ORD-01, ORD-02 »), au lieu d'une phrase par ordinateur. Des clés qui n'ont pas pu être lues gardent chacune leur ligne.

#### Notifications
- **Les notifications ne cachent plus les résultats** : ce qu'une action a fait s'affiche dans une barre en bas de la fenêtre, sous le nombre de résultats, et non plus par-dessus les dernières lignes.
  - La grille raccourcit d'autant le temps de la notification, sans qu'une ligne bouge, et la dernière ligne sélectionnée reste visible.
  - La barre tient le titre et le texte sur une ligne, sur deux si besoin, et son info-bulle a le reste. Elle reste ouverte sous la souris, et × la ferme.
- **La notification d'une action réussie** dit ce qui a été fait : « Désactivé », « Déverrouillés », « Clé supprimée », « Copié dans le presse-papiers ». **Vérifier en ligne** dit « En ligne » ou « Hors ligne », et pour plusieurs ordinateurs, lesquels sont hors ligne. Un long message passe à la ligne au lieu d'être coupé, et reste affiché plus longtemps.

#### Fenêtres et boutons
- **Moins de texte** : les notes et les messages trop longs sont raccourcis, dans Paramètres, Prochain nom, Propriétés, Redémarrer, Prendre la main, Clés BitLocker et Mot de passe LAPS, et dans les confirmations pour retirer d'un groupe ou désactiver.
- **Les fenêtres restent au-dessus de la barre des tâches**, sur l'écran où elles s'ouvrent : **Propriétés**, **Caractéristiques**, **Prochain nom…**, **Paramètres** et les autres. Des **Propriétés** ouvertes depuis d'autres se décalent encore un peu, mais seulement de la place que l'écran laisse. Une fenêtre trop haute pour un petit écran, ou pour un second écran plus petit, est raccourcie à sa taille.
- **Filtres**, et **Options** dans **Prochain nom…**, ne ressemblent plus au bouton principal quand ils sont activés : ils prennent la couleur de sélection avec un contour, comme l'onglet de la page affichée. La couleur pleine reste à **Rechercher** ou **Copier**.
- **Les boutons** des fenêtres qui demandent confirmation (**Supprimer**, **Activer WinRM**, **Lire par DCOM**…) ont les coins arrondis des autres boutons, comme **Copier** de **Nouveau mot de passe**, **Dans 1 an** dans **Expiration du compte** et les petits boutons de **Mot de passe LAPS…**, **Clés BitLocker…** et **Propriétés**.
- **Ajouter à un groupe…**, **Retirer d'un groupe…** et **Ajouter des membres…** gardent leur bouton désactivé tant que rien n'est coché : il fermait la fenêtre sans rien faire ni rien dire. Une nouvelle recherche qui décoche tout le désactive à nouveau. Dans les **Propriétés** d'un utilisateur, une recherche qui ne trouve que ses propres groupes le dit, au lieu de « Aucun groupe ».
- **Réinitialiser le mot de passe** masque le mot de passe tapé dans **Autre**, comme les autres cases de mot de passe, avec un œil pour vérifier ce qui est tapé. La case du mot de passe par défaut de **Paramètres › Mots de passe** a maintenant l'allure des autres cases.
- **Le filtre d'une colonne** : quand la liste de valeurs défile, sa barre de défilement ne cache plus les nombres au bout des lignes.
- **Tout développer** et **Tout réduire**, dans les **Propriétés** d'un utilisateur ou d'un groupe, restent en haut de la fenêtre, comme dans **Caractéristiques** : ils ne défilent plus avec les cartes, et restent à portée de clic même en bas de la fenêtre.
- **Une colonne élargie ou rétrécie** garde la largeur choisie, sur chaque page : elle ne change plus avec la taille de la fenêtre ni quand une colonne apparaît ou disparaît (**Domaine**, **En ligne**). Une colonne ajustée à son contenu d'un double-clic sur le bord de son en-tête garde aussi sa largeur au prochain démarrage.
- **Copier**, dans **Groupes…** et **Comparer les groupes**, dit sur le bouton si la copie est faite : quand un autre programme occupe le presse-papiers, il montre « Copie impossible » au lieu d'annoncer des groupes copiés.

### Fiabilité et sécurité

#### Sécurité
- **PowerShell à distance** refuse un nom d'ordinateur qui n'en est pas un : venu de l'AD, il pouvait être exécuté comme du code.
- **Ajouter à un groupe…**, dans les **Propriétés** d'un utilisateur et pour les utilisateurs ou ordinateurs sélectionnés, marque en rouge « Privilégié » les groupes d'administration que l'AD protège (adminCount) et ceux qui en sont membres : Admins du domaine, Administrateurs, les groupes Opérateurs, Contrôleurs de domaine, Administrateurs de l'entreprise ou du schéma, ainsi que DnsAdmins.
  - Quand un de ces groupes est coché, **Ajouter** demande une seconde confirmation, en rouge, qui les nomme, avec **Annuler** par défaut : un clic de trop ne donne plus les droits d'administrateur du domaine.
  - Un groupe qui a cessé d'être protégé garde souvent son adminCount, et reste donc marqué ; il s'ajoute comme les autres une fois confirmé.
- **Supprimer de l'AD** essaie d'abord de supprimer l'ordinateur : ses objets enfants ne sont supprimés que si l'AD l'exige, les clés BitLocker en dernier. Un refus, de droits par exemple, laisse tout en place.
- **Exporter** et **Copier les lignes** (Ctrl+Maj+C), comme **Copier** dans **Groupes…** et **Clés BitLocker…**, gardent en texte une valeur qu'Excel lirait comme une formule : une description qui commence par `=` reste du texte. Copier une seule valeur ou des noms les copie tels quels.
- **Adresse IP** vérifie que le nom donné par le DNS mène encore à cette adresse.

#### Mots de passe et presse-papiers
- **Mots de passe** : les mots de passe et clés copiés restent hors de l'historique du Presse-papiers et s'effacent après une minute. Le mot de passe LAPS masqué n'est plus lu par les lecteurs d'écran.
  - Un mot de passe ou une clé que le presse-papiers occupé empêchait de copier n'est plus copié d'une autre façon, qui le laissait dans l'historique et pouvait l'envoyer aux autres appareils de l'utilisateur. La fenêtre ne reste plus figée jusqu'à cinq secondes pendant que Repère réessaie.
  - Le mot de passe ou la clé s'efface aussi quand un autre programme, comme le Bureau à distance ou un gestionnaire de presse-papiers, occupe le presse-papiers à ce moment : Repère réessaie toutes les deux secondes, puis de nouveau quand il se ferme.
- **Nouveau mot de passe…** : le mot de passe généré a maintenant trois mots, et la personne doit toujours le changer à sa prochaine connexion. Le mot de passe par défaut de **Paramètres › Mots de passe** aussi : le même pour chaque réinitialisation et connu de tous les techniciens, il ne peut plus rester valide indéfiniment.
  - Ni l'un ni l'autre n'est proposé pour un compte dont le mot de passe n'expire jamais.
  - Dans Paramètres, la case « doit le changer » ne vaut plus que pour un mot de passe tapé dans **Autre**.
- **Les clés BitLocker à copier avant une suppression**, dans **Supprimer de l'AD…** et **Clés BitLocker…**, se copient comme les autres clés : hors de l'historique du Presse-papiers, sans aller aux autres appareils de l'utilisateur, et effacées après une minute.
  - Un bouton **Copier** à côté de la liste les copie toutes, et Ctrl+C ou le clic droit, la sélection ou tout ; le bouton dit « Copie impossible » quand un autre programme occupe le presse-papiers.
  - Les clés ne se glissent plus hors de la liste vers un autre programme.

#### Active Directory et groupes
- **Supprimer de l'AD**, **Activer**, **Désactiver**, **Déplacer vers…**, **Modifier la description**, **Groupes…**, **Ajouter à un groupe…** et **Retirer d'un groupe…** se font en arrière-plan : un contrôleur de domaine lent ne fige plus la fenêtre.
- **Utilisateurs** et **Groupes** : une recherche se lance même pendant le chargement du module AD, juste après l'ouverture, et s'arrête avec **Annuler** ou Échap. Les résultats s'affichent plus vite.
- **Utilisateurs** et les **Propriétés** d'un utilisateur font leurs changements sur le PDC du domaine, là où les Propriétés lisent le compte : la fenêtre et la ligne de la page montrent le changement tout de suite, et non plus l'état d'avant. Quand le PDC ne répond pas, les deux passent par un même autre contrôleur de domaine, et la carte **Verrouillage** le dit.
- **Ajouter à un groupe…**, **Retirer d'un groupe…** et les **Propriétés** d'un groupe changent les membres sur ce même contrôleur de domaine, et les y relisent : un groupe ajouté ou retiré se voit tout de suite dans les Propriétés de l'utilisateur et du groupe, et **Retirer d'un groupe…** ne propose plus un groupe qu'on vient de quitter. Un groupe universel d'une forêt à plusieurs domaines lit ses membres dans le catalogue global, qui peut les montrer un peu plus tard.
- **Groupes › Sans membres** ne liste plus Utilisateurs du domaine, Ordinateurs du domaine, Contrôleurs de domaine, ni aucun groupe qui est le groupe principal d'un compte : l'AD ne met pas un compte dans la liste des membres de son groupe principal, et ces groupes semblaient vides. La limite s'applique aux groupes affichés.
- **Groupes › Propriétés** d'un groupe universel ou domaine local : **Retirer…** retire maintenant un membre d'un autre domaine de la forêt, ce qui échouait toujours (« Cannot find an object with identity »).
- **Groupes › Propriétés** : la recherche d'un membre ne trouve plus que les noms et identifiants qui commencent par le texte (« mont » ne trouve plus tous ceux dont le bureau est à Montréal).
  - Un catalogue global qui n'a pas répondu est cherché de nouveau à la lecture suivante, au lieu de laisser tout groupe universel lu domaine par domaine jusqu'à la fermeture de Repère ; quand celui retenu ne répond plus, Repère en cherche un autre une fois.
- **Verrouillés** applique sa limite aux seuls comptes encore verrouillés.
- **PowerShell à distance** active WinRM de nouveau après un essai qui a échoué.

#### Adresse IP et affichage
- **Adresse IP** ne cherche qu'une adresse entière : `255.255.255` était cherché comme 255.255.0.255, et `10.1` comme 10.0.0.1, sans le dire.
  - Le début d'une adresse, un sous-réseau ou une plage (`10.0.1.`, `10.0.1.*`, `10.0.1.0/24`) sont refusés sous la case : chacun demanderait de chercher chaque ordinateur dans le DNS.
  - Des zéros au début se lisent en décimal (`010` est 10).
- **Vérifier en ligne** ne redessine des milliers de lignes qu'une fois par seconde.
- Les chemins montrent aussi `+`, `=`, `#` et les autres caractères que l'AD fait précéder d'une barre oblique inverse.

#### Erreurs et démarrage
- **Une erreur inattendue** s'affiche dans une notification, et non plus seulement dans la console. Une erreur dans un rapport n'en affiche plus un second, faux.
  - Une valeur de l'AD qui contient un caractère de contrôle n'empêche plus d'ouvrir une fenêtre.
  - Une très longue durée de connexion ou de redémarrage ne bloque plus sa fenêtre.
  - Une interruption pendant l'enregistrement ne perd plus les paramètres.
- **Une valeur qui commence par `{`** (une description `{Temporaire} accueil`, un téléphone, le nom d'un écran…) s'affiche telle quelle : elle empêchait d'ouvrir **Propriétés**, **Mot de passe LAPS…** ou **Clés BitLocker…**, et arrêtait la lecture de **Caractéristiques**.
- **Ce qui empêche Repère de démarrer** s'affiche dans une fenêtre, au lieu de ne rien montrer du tout.
  - Une option de lancement mal écrite dans un raccourci le dit et nomme ce qui ne va pas : une langue que Repère n'a pas (`-Language de`), une option inconnue ou un mot en trop, comme l'espace après la virgule de `-Domains a.local, b.local`.
  - Un fichier de Repère qui ne se charge pas, abîmé par exemple, est nommé dans le message, avec la ligne en cause.
  - Quand WMI ne répond pas, Repère le dit, au lieu de prétendre que l'ordinateur n'est pas joint à un domaine.

### Paramètres

#### Apparence
- **Apparence est refaite en lignes**, regroupées par Couleurs, Texte, Affichage et langue : le nom et l'effet de chaque réglage à gauche, son contrôle à droite, sans cartes ni double aperçu. Toute la page tient dans la fenêtre, et **Par défaut** est à côté du texte qu'il remet.
  - D'abord le **mode** : selon le système, clair ou sombre.
  - Puis le **thème**, dans une liste qui montre son fond et son accent dans ce mode, vos thèmes sous **Mes thèmes**, à la suite des préréglages. Parcourir la liste ouverte, à la souris ou aux flèches, essaie chaque thème sur toutes les fenêtres ; Échap ou un clic ailleurs ramène le thème choisi. Choisir un thème ne change plus le mode : un Repère qui suit Windows continue de le suivre.
  - **Créer un thème** reste sous la liste, avec **Copier celui-ci** pour un préréglage, **Modifier** et **Supprimer** pour un de vos thèmes.
  - **Supprimer un thème** demande d'abord confirmation, Annuler par défaut, et dit si Repère reprendra son thème. Il était supprimé au premier clic, sans retour possible. Ensuite, la ligne **Mes thèmes** dit quel thème a été supprimé.
  - **Police** montre chaque police écrite dans cette police. **Langue** est une liste, et dit que le choix s'applique au prochain lancement.
- **L'éditeur de thème** a un seul aperçu, du mode utilisé, avec **Clair** et **Sombre** pour passer de l'un à l'autre ; changer une couleur d'un mode l'y amène.
  - **La couleur d'accent vaut pour les deux modes** : la choisir remplace l'accent propre à un mode, qu'une copie de préréglage avait gardé. Sous elle, une ligne dit comment elle s'affiche dans chaque mode : éclaircie ou assombrie pour ressortir, ou remplacée par l'accent propre au mode.
  - Les avertissements de contraste sont plus courts, dans un encadré, et disent que le thème peut quand même être enregistré. Un thème aux couleurs automatiques n'en a plus : le texte secondaire et le texte sur l'accent restent lisibles sur tous les fonds.
- **Mode**, **Thème**, **Police** et **Épaisseur** n'ont plus de sous-titre, leurs choix parlent d'eux-mêmes, et chaque réglage tient sur une ligne en texte **Grande** ou **Très grande**. Dans **Raccourcis**, une description trop longue passe à la ligne au lieu d'être coupée.
- **Texte › Par défaut** a l'air d'un bouton, avec un contour, et il est grisé quand la police, la taille et l'épaisseur sont déjà celles par défaut.

#### Déplacer vers
- **Déplacer vers** est refaite pour tenir dans la fenêtre, même agrandie : le titre et le filtre restent en place et seule la liste d'OU défile.
  - L'arbre est plus compact, se filtre, et sa carte a la hauteur de ses OU au lieu de remplir la fenêtre.
  - Les OU cochées sont listées à côté, avec leur chemin, un bouton pour retirer chacune et **Tout décocher**, même si elles sont cachées dans une branche fermée ou dans un autre domaine.
  - Le `_` des noms d'OU, qui disparaissait, s'affiche.

#### SCCM et Redémarrage
- **SCCM** : le code du site et le serveur où **Prochain nom…** vérifie aussi, avec **Tester**. SCCM dit « Dans SCCM », « Pas dans SCCM » ou pourquoi il n'a pas pu être vérifié, sans jamais confondre les deux. Il faut la console Configuration Manager sur cet ordinateur.
  - Le site s'enregistre en quittant ses cases, et **Tester** l'enregistre avant de le tester, grisé pendant le test.
  - Une case incorrecte le dit juste dessous, encadrée en rouge ; vider les deux cases le dit aussi : **Prochain nom…** ne vérifiera plus que dans l'AD.
- **SCCM** et **Redémarrage** s'enregistrent sans bouton, comme le reste des Paramètres : en quittant une case, en changeant de page ou en fermant la fenêtre. Ce qui ne peut pas être enregistré garde la fenêtre ouverte, en le disant ; la fermer de nouveau abandonne ces changements. Ils étaient perdus sans avertissement si on oubliait **Enregistrer**.
- **Redémarrage** : l'heure de l'aperçu du message se calcule en arrivant sur la page, et non à l'ouverture des Paramètres.

#### Fichiers de paramètres
- **Un `parametres.json` illisible n'est plus écrasé** : une erreur de JSON dans un fichier modifié à la main, comme une seule barre oblique inverse dans le DN d'une OU, faisait perdre au lancement suivant **Déplacer vers**, **SCCM** et la langue.
  - Repère garde maintenant le fichier tel quel, utilise les valeurs par défaut et le dit dans une notification à l'ouverture, avec l'erreur en info-bulle.
  - Si on enregistre quand même un paramètre, le fichier est d'abord mis de côté sous `parametres.json.illisible`, pour être corrigé.
  - Les autres fichiers de paramètres illisibles (`fenetre.json`, `apparence.json`…) sont eux aussi mis de côté sous `.illisible` à leur prochain enregistrement, au lieu d'être remplacés sans rien dire.


## 0.12.0 — 2026-11-02

### Ordinateurs
- **Les recherches sont de nouveau rapides** sur un AD réel : depuis la 0.11.0, un millier d'ordinateurs prenait 20 à 25 secondes à s'afficher. Désactiver, Supprimer et Déplacer reconnaissent maintenant les contrôleurs de domaine en le demandant à l'AD à leur ouverture ; s'il ne répond pas, aucun ordinateur de ce domaine n'est touché, et la confirmation le dit.
- **Caractéristiques** :
  - une section **Écrans** : les écrans branchés, celui du portable compris, avec leur connexion (HDMI, DisplayPort, DVI, VGA…), leur fabricant, leur numéro de série, leur taille et leur résolution native ;
  - plus rapide sur un ordinateur sans WinRM : quand le port 5985 ne répond pas en 2 secondes, Repère passe directement par DCOM au lieu d'attendre ;
  - par WinRM, les logiciels se lisent en une seule fois ;
  - l'info-bulle de la ligne d'état dit combien de temps a pris chaque section, et par où Repère s'est connecté.
- **Mot de passe LAPS…** et **Clés BitLocker…** lisent l'AD en arrière-plan : la fenêtre ne fige plus quand un contrôleur de domaine tarde à répondre, et un double-clic n'ouvre qu'une fenêtre.
- **Barre d'actions** :
  - dans une fenêtre étroite, Vérifier en ligne, Caractéristiques et Désactiver deviennent carrés eux aussi, leur nom dans leur info-bulle ; avec une police large, la fenêtre peut être plus étroite ;
  - **Désactiver…** est un seul bouton, sans flèche : il devient **Activer** quand tous les ordinateurs sélectionnés sont désactivés. Avec un mélange des deux, Activer est au clic droit ;
  - chaque bouton dit son nom au survol, même sans sélection ;
  - BitLocker a pour icône un disque cadenassé, et LAPS une clé.
- **Recherche avancée** : « au moins … » avec « Jamais » est vérifié par l'AD lui-même. C'est plus rapide, et la limite de 2 000 résultats ne fait plus manquer d'ordinateurs.
- La barre d'état garde entiers le nombre de résultats et le temps de recherche ; c'est l'aide à droite qui est raccourcie.

### Ordinateurs, Utilisateurs et Groupes
- **Les dates s'écrivent à la canadienne-française**, en chiffres : « 2026-10-23 à 15 h 08 », ou « 2026-10-23 » quand l'heure ne compte pas. C'est le cas dans les Propriétés, LAPS, BitLocker, Caractéristiques, Redémarrer et l'info-bulle de Dernière connexion. En anglais : « 10/23/2026 at 3:08 PM ». Les exports CSV gardent « 2026-10-23 15:08 ».
- Le temps de recherche (« en … ms ») dit en info-bulle où il est passé : pour chaque domaine, la requête à l'AD et la préparation des lignes, puis la grille.

### Paramètres
- **Apparence**, thèmes personnalisés : cliquer le carré d'une couleur ouvre un **sélecteur de couleur** (saturation et luminosité, teinte, code) ; **Automatique** rend à une couleur celle tirée de l'accent. Le # est fixe devant chaque code : on tape ou colle les six chiffres, avec ou sans #.
- **Déplacer vers** : les OU de l'arbre commencent fermées, sauf pour montrer celles qui sont choisies, et l'arbre prend la hauteur de la fenêtre.
- Un fichier de paramètres illisible est signalé dans la console, avec les valeurs par défaut utilisées à sa place, au lieu d'être ignoré en silence.

### Corrections
- La **Recherche avancée** n'affiche plus l'erreur « Parameter count mismatch » à son ouverture.

## 0.11.1 — 2026-10-29

### Corrections
- Au lancement, une erreur « Get-OUPath n'est pas reconnu » s'affichait quand une OU avait été choisie dans la **Recherche avancée** : le bouton **Avancée** ne disait plus combien de critères étaient choisis, et l'OU n'était plus nommée.

## 0.11.0 — 2026-10-29

### Ordinateurs
- **Recherche avancée** : le bouton **Avancée**, à la place de la case qui limitait la recherche à certaines OU, ouvre des critères que l'AD applique lui-même, ajoutés au nom et à la description :
  - **Emplacement** : partout, une OU choisie dans l'arbre, ou les OU dont le nom commence par un texte, chaque fois avec celles qu'elles contiennent ;
  - **État** (activés ou désactivés) et **Système contient** (`Windows 10`, `Server`…) ;
  - **Dernière connexion** : au moins ou moins de tant de jours, semaines, mois ou ans, avec ou sans « Jamais ». Elle remplace **Inactifs depuis**.

  Le bouton dit combien de critères sont choisis. Avec eux, ni le début du nom ni une description ne sont nécessaires. Les recherches enregistrées avec cette case ou Inactifs depuis reviennent avec ces critères.
- **Vérifier en ligne** vérifie 48 ordinateurs à la fois au lieu de 16 : bien plus rapide quand beaucoup sont éteints.
- **Caractéristiques › Logiciels** ne s'arrête plus sur un programme dont une valeur du registre n'a pas le type attendu (« registre illisible (GetDWORDValue, code 2147749893) »).

### Ordinateurs, Utilisateurs et Groupes
- **Filtres de colonne** : un entonnoir dans chaque en-tête liste les valeurs de la colonne, chacune avec son nombre de résultats, à cocher comme dans Excel.
  - Un texte tapé dans la liste garde tout ce qui le contient, par exemple une OU et celles qu'elle contient dans **Emplacement**.
  - **Nom** se filtre par le texte qu'il contient, **Dernière connexion** par ancienneté, **Mot de passe** par état.
  - Le bouton **Filtres** affiche ou masque les entonnoirs. Une nouvelle recherche efface les filtres ; **Tout afficher** les garde.
- **Tous les domaines** est en tête de la liste des domaines sur Utilisateurs et Groupes, comme sur Ordinateurs.
- Le filtre des résultats d'Utilisateurs et de Groupes ne ralentit plus la frappe avec des milliers de résultats.

### Sécurité
- Repère ne désactive, ne supprime ni ne déplace jamais un **contrôleur de domaine**, ni l'ordinateur où il est ouvert, et ne désactive pas votre propre compte. Sélectionnés avec d'autres, ils sont laissés de côté, et la confirmation le dit.
- **Supprimer de l'AD** montre tout ce qui est supprimé avec l'ordinateur, pas seulement ses clés BitLocker. Au-delà de 25 ordinateurs, il faut en taper le nombre pour confirmer.

### Corrections
- Après une action réussie sur plusieurs utilisateurs ou plusieurs clés BitLocker, la notification disait « ordinateurs ».
- La fenêtre réduite à sa largeur minimale coupait le texte de la sélection (« 3 ordinateurs sélectionnés ») avec une police plus large que Segoe UI, comme JetBrains Mono.

## 0.10.0 — 2026-10-28

### Ordinateurs
- **Utilisateurs connectés…** (clic droit, Outils à distance) : qui a une session ouverte sur chaque ordinateur sélectionné, active ou déconnectée, et depuis quand, sans la rejoindre. Chaque ordinateur a 25 secondes pour répondre : un ordinateur éteint n'empêche pas de voir les autres. Un utilisateur du domaine y ouvre ses Propriétés, et un ordinateur où une session est active propose Prendre la main….
- **Liste de noms** : une recherche des ordinateurs dont on colle les noms (d'un ticket, d'une colonne Excel), 200 au plus ; le compte dit ceux qui sont introuvables.
- Un double-clic ouvre les Caractéristiques de l'ordinateur, et F2 modifie sa description.
- **Forcer les stratégies** et **PowerShell à distance** fonctionnent sans WinRM : par une tâche planifiée créée sur l'ordinateur (puis supprimée), et pour PowerShell à distance, WinRM activé le temps de la session, pour votre ordinateur seulement, puis remis comme avant.
- Prendre la main… dit quand un ordinateur n'a pas répondu à temps.

### Utilisateurs
- **Désactiver…** (avec confirmation) et **Activer**, dans la barre et au clic droit.
- **Ajouter à un groupe…** cherche aussi dans les autres domaines de la forêt (leurs groupes universels et domaine local), quand le domaine de l'utilisateur n'en a pas ou sur demande.

### Utilisateurs et Groupes
- Le domaine et le type de recherche reviennent au lancement suivant, et chaque page a ses **Recherches récentes**, comme Ordinateurs.
- Ouvrir un utilisateur depuis les membres d'un groupe ou depuis Utilisateurs connectés… ne fige plus la fenêtre quand un contrôleur de domaine tarde à répondre.

### Fenêtre et Paramètres
- La fenêtre revient à sa taille et à sa place, et sur la page affichée à la fermeture.
- **Mots de passe** : un œil affiche le mot de passe par défaut, pour en vérifier l'orthographe.
- Une nouvelle version de Repère est signalée par un point sur Paramètres, avec un lien pour la télécharger. GitHub est consulté une fois par jour au plus ; `-NoUpdateCheck` l'évite.

## 0.9.2 — 2026-10-27

- **Repère.cmd** : Repère se lance d'un double-clic (ou d'un raccourci vers ce fichier), sans fenêtre de console. Au premier lancement, il débloque les fichiers téléchargés : plus besoin d'`Unblock-File`.
- **Anglais** : Paramètres › Apparence › Langue (langue de Windows, français ou anglais), au prochain lancement ; ou `-Language en`. Qui utilisait déjà Repère reste en français.
- **ID de clé BitLocker** : une recherche des Ordinateurs qui trouve l'ordinateur d'après l'ID que montre l'écran de récupération de BitLocker (les 8 premiers caractères suffisent). Clés BitLocker… signale ensuite la clé cherchée.
- Ce qui empêche Repère de démarrer (ordinateur hors domaine, RSAT absent, PowerShell trop ancien) s'affiche dans une fenêtre, et plus seulement dans la console.
- Les propriétés d'un utilisateur ou d'un groupe disent de nouveau pourquoi ses groupes hérités n'ont pas pu être lus.
- Avec `-MoveRoots`, enregistrer un paramètre n'enregistre plus ces OU comme celles de Paramètres.
- Le zip ne contient plus le README ni ses captures : le mode d'emploi est sur la page du dépôt.

## 0.9.1 — 2026-10-26

- Le zip de la release ne contient plus les données d'exemple (`FakeAD`) : elles servent à essayer Repère et aux tests, et restent dans le dépôt.
- Hors domaine, Repère installé depuis le zip dit qu'il a besoin d'Active Directory, au lieu d'une erreur de chargement du module.

## 0.9.0 — 2026-10-25

Première version publiée. Repère est utilisé sur un domaine réel ; chaque commande AD qu'il emploie y a été vérifiée (`tests\Test-RepereAD.ps1`).

### Ordinateurs
- Recherche par début du nom, description (contient, commence par, termine par, sans description), partie du nom, adresse IP, ou inactifs depuis 90 jours, 180 jours ou 1 an ; dans un domaine, ou tous à la fois ; dans certaines OU seulement, au besoin.
- Recherches récentes, filtre des résultats, colonnes à choisir, déplacer et redimensionner, export CSV pour Excel.
- Actions : modifier la description, déplacer vers une OU, groupes, clés BitLocker (et suppression des anciennes), mot de passe LAPS (Windows LAPS et LAPS hérité), activer, désactiver, supprimer de l'AD, vérifier en ligne, caractéristiques (matériel, Windows, réseau, logiciels), prendre la main, Bureau à distance et autres outils à distance, forcer les stratégies, redémarrer avec un message.

### Utilisateurs
- Recherche par nom, identifiant ou courriel, verrouillés, désactivés, ou description.
- Déverrouiller, nouveau mot de passe (généré et facile à dicter, ou celui par défaut, jamais enregistré ni journalisé).
- Propriétés : compte, verrouillage lu sur le PDC, mot de passe, expiration du compte, groupes (directs, principal, hérités ; ajouter et retirer), identité et organisation en lecture seule.

### Groupes
- Recherche par nom, description, ou groupes sans membres.
- Propriétés : membres (200 au plus, et une recherche dans le groupe), ajouter et retirer des membres, groupes dont il est membre ; un groupe ou un utilisateur listé s'ouvre par-dessus.
- Forêts de plusieurs domaines : membres d'un groupe universel par le catalogue global, membres d'autres domaines d'un groupe domaine local, groupes des autres domaines qui listent un compte.

### Paramètres
- Neuf thèmes clairs et sombres, et les siens ; police, taille et épaisseur du texte ; densité.
- OU proposées pour *Déplacer vers*, valeurs par défaut du redémarrage et des mots de passe, raccourcis clavier.

### Charge sur les contrôleurs de domaine
- Une recherche montre 2 000 résultats au plus par domaine ; au-delà, elle le dit, et **Tout afficher** la relance sans limite.
- Les recherches au fil de la frappe (*Ajouter des membres…*, *Ajouter à un groupe…*) ne demandent à l'AD que ce qu'elles affichent.
- Les recherches et les lectures se font en arrière-plan : la fenêtre reste utilisable, et un domaine qui ne répond pas n'empêche pas d'afficher les autres.

### Qualité
- Erreurs courantes de l'AD affichées en français.
- Tests de l'interface sur un AD d'exemple, tests unitaires et analyse du code à chaque changement (GitHub Actions), mode strict pour les tests.
