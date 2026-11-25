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

# What an error means, for the code that decides what to say (a toast or a report, « accès refusé »…): read from its
# codes and its type, never from its text, which is in Windows' language. ConvertTo-FrenchError only changes how a
# message reads, and leaves a message in another language as Windows wrote it; these decide. Each kind is a Win32 code,
# in any of the forms Windows gives it (an HRESULT 0x8007xxxx, a CIM error's error_Code or MessageId, PowerShell's
# FullyQualifiedErrorId), or a code of its own:
# - AccessDenied: 5, an UnauthorizedAccessException, a CIM or WMI AccessDenied (0x80041003).
# - RpcUnavailable: 1722 (0x800706BA), « the RPC server is unavailable »: the computer didn't answer DCOM or RPC.
# - WinRMUnreachable: 0x80338012, WinRM's client couldn't connect to the computer.
# - InvalidNamespace: WMI's 0x8004100E, or a CIM InvalidNamespace (an SCCM site that isn't on its server).
function Get-ErrorKind($Failure) {
    # The kinds above that $Failure holds, each once; none when it has no code Repère knows. $Failure: an
    # ErrorRecord, an exception, and everything inside them (InnerException, the ErrorRecord PowerShell wraps an error
    # in, an AggregateException's, and the causes Repère joined into one message, in Data['Repere.Causes']: WinRM's and
    # DCOM's), a list of them, or a text Add-ErrorKind gave its kinds. Self-contained, for the runspaces' -Functions.
    if ($null -eq $Failure) { return }
    $given = $Failure.PSObject.Properties['ErrorKind']
    if ($given) { return @($given.Value) }
    # Int64 keys, as the codes are read: a hashtable's 1722 and 1722L are different keys.
    $codes = @{ 5L = 'AccessDenied'; 1722L = 'RpcUnavailable'; 0x80041003L = 'AccessDenied'; 0x80338012L = 'WinRMUnreachable'; 0x8004100EL = 'InvalidNamespace' }
    $kinds = [System.Collections.Generic.List[string]]::new()
    $found = [System.Collections.Generic.List[int64]]::new()
    $pending = [System.Collections.Generic.Queue[object]]::new()
    $seen = [System.Collections.Generic.HashSet[object]]::new()
    $pending.Enqueue($Failure)
    $addHex = { param($text) if ("$text" -match '^(?:HRESULT )?0x([0-9a-f]{8})\b') { $found.Add([Convert]::ToInt64($Matches[1], 16)) } }
    while ($pending.Count -and $seen.Count -lt 50) {
        $item = $pending.Dequeue()
        if ($null -eq $item -or $item -is [string] -or -not $seen.Add($item)) { continue }
        if ($item -is [System.Management.Automation.ErrorRecord]) {
            # « HRESULT 0x800706ba,Microsoft.Management.Infrastructure.CimCmdlets.NewCimSessionCommand »
            & $addHex $item.FullyQualifiedErrorId
            $pending.Enqueue($item.Exception)
            continue
        }
        if ($item -isnot [System.Exception]) {
            if ($item -is [System.Collections.IEnumerable]) { foreach ($each in $item) { $pending.Enqueue($each) } }
            continue
        }
        if ($item -is [System.UnauthorizedAccessException]) { $kinds.Add('AccessDenied') }
        $found.Add($item.HResult)
        # ADException's and PSRemotingTransportException's ErrorCode, Win32Exception's NativeErrorCode: a Win32 code, or
        # an HRESULT. CimException's NativeErrorCode and ManagementException's ErrorCode are enums, read by their name:
        # their values aren't Win32 codes (a CIM AccessDenied is 2).
        foreach ($name in 'ErrorCode', 'NativeErrorCode') {
            $property = $item.PSObject.Properties[$name]
            if (-not $property -or $null -eq $property.Value) { continue }
            if ($property.Value -is [enum]) { if ("$($property.Value)" -in 'AccessDenied', 'InvalidNamespace') { $kinds.Add("$($property.Value)") } }
            elseif ($property.Value -is [int] -or $property.Value -is [uint32] -or $property.Value -is [int64]) { $found.Add([int64]$property.Value) }
        }
        # A CIM error's own: error_Code (an HRESULT or a Win32 code) and MessageId (« HRESULT 0x80338012 »).
        $data = $item.PSObject.Properties['ErrorData']
        if ($data -and $data.Value -and $data.Value.PSObject.Properties['CimInstanceProperties']) {
            $code = $data.Value.CimInstanceProperties['error_Code']
            if ($code -and $null -ne $code.Value) { $found.Add([int64]$code.Value) }
        }
        $id = $item.PSObject.Properties['MessageId']
        if ($id) { & $addHex $id.Value }
        $pending.Enqueue($item.InnerException)
        foreach ($name in 'InnerExceptions', 'ErrorRecord') {
            $property = $item.PSObject.Properties[$name]
            if ($property) { $pending.Enqueue($property.Value) }
        }
        if ($item.Data.Contains('Repere.Causes')) { $pending.Enqueue($item.Data['Repere.Causes']) }
    }
    foreach ($code in $found) {
        $value = $code -band 0xFFFFFFFFL
        # An HRESULT of FACILITY_WIN32 holds a Win32 code: 0x800706BA is 1722.
        if (($value -band 0xFFFF0000L) -eq 0x80070000L) { $value = $value -band 0xFFFF }
        if ($codes.ContainsKey($value)) { $kinds.Add($codes[$value]) }
    }
    @($kinds | Select-Object -Unique)
}

function Add-ErrorKind([string]$Text, $Cause) {
    # $Text, the message of $Cause as Repère shows it, with what Get-ErrorKind finds in $Cause as its ErrorKind: a
    # failure passed on as a text (to an OnDone, into a line) still says what it was once its exception is gone. As it
    # is when $Cause holds no known code.
    $kinds = @(Get-ErrorKind $Cause)
    if (-not $Text -or -not $kinds.Count) { return $Text }
    $failure = [psobject]::new($Text)
    $failure.PSObject.Properties.Add([psnoteproperty]::new('ErrorKind', [string[]]$kinds))
    $failure
}
