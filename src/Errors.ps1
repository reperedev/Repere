# The errors of the AD cmdlets, ADWS, LDAP and RPC, in French: on an English Windows they reach the French UI in
# English (« ✖ nlevy : mot de passe non réinitialisé (Access is denied) »). Only messages known whole are replaced,
# wherever they are in a text, and the rest of the text is kept; any other message is left as it is, so a French
# Windows' own messages pass through unchanged. The display functions call ConvertTo-FrenchError on what they show
# (Show-Dialog, Show-ActionReport, Show-ActionNotice, Show-DetailNotice…), not each place that catches an error. When
# Repère is in English (Language.ps1), the messages stay as AD says them. Dot-sourced by the main script, after
# Language.ps1.

# Each English message as a regex (spaces match any blank, case is ignored), and its French. A message with a variable
# part names it (?<name>…), and its French puts it back with ${name}. The longer messages come before those they
# contain. A message's last period isn't part of it: the text keeps its own.
$script:FrenchErrorList = @(
    , @('Access is denied', 'Accès refusé')
    , @('Insufficient access rights to perform the operation', 'Droits insuffisants pour cette opération')
    , @('The user has insufficient access rights', 'Droits insuffisants')
    , @('Unable to contact the server\. This may be because this server does not exist, it is currently down, or it does not have the Active Directory Web Services running',
        "Le serveur ne répond pas : il n'existe pas, il est arrêté ou les services Web Active Directory n'y fonctionnent pas")
    , @('Unable to find a default server with Active Directory Web Services running', 'Aucun contrôleur de domaine avec les services Web Active Directory trouvé')
    , @('The server is not operational', 'Le serveur ne répond pas')
    , @('The specified domain either does not exist or could not be contacted', 'Domaine inexistant ou injoignable')
    , @('The operation being requested was not performed because the user has not been authenticated', 'Opération non effectuée : utilisateur non authentifié')
    # Set-ADAccountPassword's, and the same refusal as LDAP and Windows word it.
    , @('(?:Unable to update the password\. )?The value provided for the new password does not meet the length, complexity, or history requirements? of the domain',
        'Mot de passe refusé par la stratégie du domaine (longueur, complexité ou historique)')
    , @('The password does not meet the length, complexity, or history requirements? of the domain',
        'Mot de passe refusé par la stratégie du domaine (longueur, complexité ou historique)')
    , @('The password does not meet the password policy requirements\. Check the minimum password length, password complexity and password history requirements',
        'Mot de passe refusé par la stratégie du domaine (longueur, complexité ou historique)')
    , @("Cannot find an object with identity: '(?<identity>.+?)' under: '(?<base>.+?)'", 'Objet « ${identity} » introuvable dans « ${base} »')
    # The fake AD names the object it didn't find; the ActiveDirectory module doesn't.
    , @("Directory object not found: '(?<object>.+?)'", "Objet introuvable dans l'annuaire : « `${object} »")
    , @('Directory object not found', "Objet introuvable dans l'annuaire")
    , @('There is no such object on the server', 'Objet inexistant sur le serveur')
    , @('The object name has bad syntax', "Nom d'objet mal formé")
    , @('An attempt was made to add an object to the directory with a name that is already in use', 'Un objet de ce nom existe déjà à cet endroit')
    , @('The specified account name is already a member of the group', 'Déjà membre du groupe')
    , @('The specified account name is not a member of the group', "N'est pas membre du groupe")
    , @('The server is unwilling to process the request', 'Le serveur refuse de traiter la demande')
    , @('A referral was returned from the server', 'Le serveur renvoie vers un autre domaine')
    , @('The directory service can perform the requested operation only on a leaf object', 'Opération possible seulement sur un objet sans objets enfants')
    , @('A constraint violation occurred', "Contrainte de l'annuaire non respectée")
    , @('The size limit for this request was exceeded', 'Trop de résultats : limite de la requête dépassée')
    , @('The search filter cannot be recognized', 'Filtre de recherche non reconnu')
    # tokenGroups asked for in a search rather than of one object by its DN.
    , @('The requested search operation is only supported for base searches', "Opération possible seulement sur un objet lu par son chemin (recherche de base)")
    , @('The operation returned because the timeout limit was exceeded', "Délai d'attente dépassé")
    , @('This operation returned because the timeout period expired', "Délai d'attente dépassé")
    , @('The RPC server is unavailable', "Le serveur RPC n'est pas disponible")
    , @('The network path was not found', 'Chemin réseau introuvable')
)

# Built once: whole messages only, so « Access is denied » inside a longer word or message of its own isn't touched.
$script:FrenchErrors = @($script:FrenchErrorList | ForEach-Object {
    [pscustomobject]@{
        Pattern = [regex]::new("(?<!\w)$($_[0] -replace ' ', '\s+')(?!\w)", 'IgnoreCase, CultureInvariant')
        French  = $_[1]
    }
})

function ConvertTo-FrenchError([string]$Text) {
    # $Text with each English message it holds in French; the rest as it is. Empty stays empty. In English, $Text as it
    # is: AD's own message rather than its French put back in English.
    if (-not $Text -or [System.AppDomain]::CurrentDomain.GetData('Repere.TextTable')) { return $Text }
    foreach ($entry in $script:FrenchErrors) { $Text = $entry.Pattern.Replace($Text, $entry.French) }
    $Text
}
