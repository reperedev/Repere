<#
.SYNOPSIS
    UI tests for Repère, run against the fake AD.
.DESCRIPTION
    Starts Repère with -FakeAD and drives its window through Windows UI Automation (no mouse input;
    the few keys needed are posted to Repère's own windows). For each scenario it checks the queries
    sent to the fake AD and what the window shows, then the action bar and the filter box. A Repère
    window opens while the tests run (again without any Communs OU and with nord.demo.local
    unreachable, twice with slow domains to check that the background searches run in parallel,
    keep the window usable and can be cancelled, then for the right-click menu and Déplacer vers…, the Recherche
    avancée's popup and its OU tree, then with -MoveRoots, then with -Domains
    and for the Apparence section: its mode, its list of themes, which tries a theme as it's gone through, and
    its editor, then a few more times with settings
    saved by older versions and with as many themes of one's own as Repère allows) and closes at
    the end. The Apparence settings go to a temporary folder, never to the user's own.
    Requires Windows and PowerShell 7.
.PARAMETER ScreenshotDirectory
    Saves a screenshot of the window after each scenario in this folder.
.EXAMPLE
    pwsh -File .\tests\Test-RepereUI.ps1
.EXAMPLE
    pwsh -File .\tests\Test-RepereUI.ps1 -ScreenshotDirectory $env:TEMP\repere-captures
#>
# Used inside the functions below, which the analyzer doesn't follow.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ScreenshotDirectory')]
param(
    [string]$ScreenshotDirectory,

    # Only these sessions (each starts Repère afresh), e.g. -Only UserDetail, GroupPage for a change to the Propriétés
    # windows; all of them without it.
    [ValidateSet('Search', 'Address', 'Unreachable', 'Parallel', 'Actions', 'Remote', 'WinRMError', 'Shadow', 'Specs', 'SpecsDelay', 'MoveRootsLong', 'SingleDomain', 'Appearance', 'Column', 'Restart', 'Safeguards', 'Advanced', 'SearchMemory', 'UserPage', 'UserDetail', 'GroupPage', 'Settings', 'SettingsSave', 'Density', 'Limit', 'NextName', 'Copy', 'CopyButton', 'UnusedBox', 'BitLocker', 'Changelog')]
    [string[]]$Only,

    # Repère in strict mode (REPERE_STRICT): what strict mode refuses fails the checks that reach it.
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
if (-not ('RepereFocus' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RepereFocus {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
}
if (-not ('RepereWindows' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RepereWindows {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
'@
}
if (-not ('RepereClipboard' -as [type])) {
    # The clipboard held, as another program can (CopyButton): Repère can't copy until it's closed.
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RepereClipboard {
    [DllImport("user32.dll", SetLastError = true)] public static extern bool OpenClipboard(IntPtr hWndNewOwner);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool CloseClipboard();
}
'@
}

$AE          = [System.Windows.Automation.AutomationElement]
$Descendants = [System.Windows.Automation.TreeScope]::Descendants
$appScript   = (Resolve-Path (Join-Path $PSScriptRoot '..\src\Repere - Recherche PC AD par description.ps1')).Path
$windowName  = 'Repère (AD fictif)'
$queryLog    = Join-Path ([IO.Path]::GetTempPath()) "repere-fakead-$PID.log"

# The fake AD's domains, as listed in the Domaine list after 'Tous les domaines'.
$fakeDomains = 'demo.local', 'nord.demo.local'

# With the Recherche avancée's OU nommées Communs, Repère should search only these OUs of each domain.
# Communs-Entree isn't one of them: it's inside OU=Communs, whose search already covers it.
$commonSearchBases = @{
    'demo.local'      = 'OU=Communs,OU=Postes,DC=demo,DC=local', 'OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local'
    'nord.demo.local' = @('OU=Communs,OU=Postes,DC=nord,DC=demo,DC=local')
}

# Each scenario fills in the form and clicks Search, then expects either a Message (and no AD query)
# or the Filter sent plus the computers listed (Rows), or just their Count when the list is long.
# Domain: what to pick in the Domaine list (demo.local by default). Advanced: the Recherche avancée's criteria
# (Set-AdvancedSearch), none by default. The filter must be sent to each domain searched (-Server), once for the
# whole domain, or once per Communs OU with OU nommées (or each of SearchBases).
# Cells: every cell of some computers' rows, in column order (Compte, Nom, Description, Dernière connexion, Système,
# Domaine, Emplacement). The fake AD's last logons are relative to today, so the ages shown don't change.
# ShownDomains: what the Domaine column shows. Label: the expected result label (-like), when it isn't just the count.
function Get-LogonCutoff([int]$Number, [int]$Unit = 0) {
    # The cutoff Repère sends for Dernière connexion: midnight, that many days (Unit 0), weeks (1) or years (3) ago, as
    # a FILETIME.
    $date = switch ($Unit) { 0 { (Get-Date).Date.AddDays(-$Number) } 1 { (Get-Date).Date.AddDays(-7 * $Number) } default { (Get-Date).Date.AddYears(-$Number) } }
    $date.ToFileTimeUtc()
}

$scenarios = @(
    @{ Name = 'Empty prefix and term are refused'
       Prefix = ''; Term = ''; Type = 'Description contient'
       Message = 'Entrez une partie du nom ou une description'; Focus = 'prefix' }
    @{ Name = 'Prefix only lists every computer'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'
       Filter = "Name -like '*ORD*'"; Count = 12 }
    @{ Name = 'Prefix only includes computers without a description'
       Prefix = 'ORD-1'; Term = ''; Type = 'Description contient'
       Filter = "Name -like '*ORD-1*'"; Rows = 'ORD-10', 'ORD-11', 'ORD-12' }
    @{ Name = 'No match shows 0 ordinateur'
       Prefix = 'XYZ'; Term = ''; Type = 'Description contient'
       Filter = "Name -like '*XYZ*'"; Count = 0 }
    @{ Name = 'Apostrophe in the term'
       Prefix = 'ORD'; Term = "d'accueil"; Type = 'Description contient'
       Filter = "Name -like '*ORD*' -and Description -like '*d''accueil*'"; Rows = 'ORD-01' }
    @{ Name = 'Description commence par'
       Prefix = ''; Term = 'salle'; Type = 'Description commence par'
       Filter = "Name -like '*' -and Description -like 'salle*'"; Rows = 'ORD-02', 'ORD-06', 'ORD-10' }
    @{ Name = 'Description termine par'
       Prefix = ''; Term = 'pause'; Type = 'Description termine par'
       Filter = "Name -like '*' -and Description -like '*pause'"; Rows = 'ORD-06' }
    @{ Name = 'Sans description disables and ignores the term'
       Prefix = 'ORD'; Term = 'salle'; Type = 'Sans description'; TermEnabled = $false
       Filter = "Name -like '*ORD*' -and -not (Description -like '*')"; Rows = 'ORD-03', 'ORD-05', 'ORD-07', 'ORD-12' }
    @{ Name = 'Compte, Description, Dernière connexion, Système and Emplacement columns'
       Prefix = 'ORD'; Term = ''; Type = 'Sans description'
       Filter = "Name -like '*ORD*' -and -not (Description -like '*')"; Rows = 'ORD-03', 'ORD-05', 'ORD-07', 'ORD-12'
       Cells = @{
           'ORD-03' = 'Activé', 'ORD-03', 'Aucune description', 'Jamais', 'Inconnu', 'demo.local', 'Postes'
           'ORD-05' = 'Désactivé', 'ORD-05', 'Aucune description', 'il y a 7 mois', 'Win 10 22H2', 'demo.local', 'Postes › Communs'
           'ORD-07' = 'Désactivé', 'ORD-07', 'Aucune description', 'Jamais', 'Inconnu', 'demo.local', 'Postes'
           'ORD-12' = 'Activé', 'ORD-12', 'Aucune description', 'il y a 1 mois', 'Server 2022', 'demo.local', 'Postes' } }
    @{ Name = 'OU nommées Communs searches each Communs OU once, not the domain'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Advanced = @{ Scope = 'name' }
       Filter = "Name -like '*ORD*'"; Rows = 'ORD-04', 'ORD-05', 'ORD-11' }
    @{ Name = 'Sans description with OU nommées Communs'
       Prefix = 'ORD'; Term = ''; Type = 'Sans description'; Advanced = @{ Scope = 'name' }
       Filter = "Name -like '*ORD*' -and -not (Description -like '*')"; Rows = 'ORD-05' }
    @{ Name = 'OU nommées with another name searches the OUs it finds'
       Prefix = ''; Term = ''; Type = 'Description contient'; Advanced = @{ Scope = 'name'; OUName = 'Labo' }
       Filter = "Name -like '*'"; SearchBases = @('OU=Labo-Communs,OU=Postes,DC=demo,DC=local'); Rows = 'ORD-08' }
    @{ Name = 'Sans description requires a prefix'
       Prefix = ' '; Term = 'salle'; Type = 'Sans description'
       Message = 'Entrez une partie du nom'; Focus = 'prefix' }
    @{ Name = 'Back to Description contient re-enables the term, with OU nommées Communs'
       Prefix = ''; Term = 'commun'; Type = 'Description contient'; Advanced = @{ Scope = 'name' }; TermEnabled = $true
       Filter = "Name -like '*' -and Description -like '*commun*'"; Rows = 'ORD-04', 'ORD-11' }
    @{ Name = 'Another domain is searched on its own'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Domain = 'nord.demo.local'
       Filter = "Name -like '*ORD*'"; Rows = 'ORD-01'; ShownDomains = 'nord.demo.local' }
    @{ Name = 'Tous les domaines searches each domain'
       Prefix = 'ORD-01'; Term = ''; Type = 'Description contient'; Domain = 'Tous les domaines'
       Filter = "Name -like '*ORD-01*'"; Rows = 'ORD-01', 'ORD-01'; ShownDomains = 'demo.local', 'nord.demo.local' }
    @{ Name = 'Tous les domaines with OU nommées Communs searches the Communs OUs of each domain'
       Prefix = ''; Term = 'commun'; Type = 'Description contient'; Advanced = @{ Scope = 'name' }; Domain = 'Tous les domaines'
       Filter = "Name -like '*' -and Description -like '*commun*'"; Rows = 'NRD-01', 'ORD-04', 'ORD-11' }
    @{ Name = 'The name box matches anywhere in the name'
       Prefix = '-1'; Term = ''; Type = 'Description contient'
       Filter = "Name -like '*-1*'"; Rows = 'ORD-10', 'ORD-11', 'ORD-12' }
    @{ Name = 'A part of the name and a part of the description: both have to match'
       Prefix = '1'; Term = 'salle'; Type = 'Description contient'; TermEnabled = $true
       Filter = "Name -like '*1*' -and Description -like '*salle*'"; Rows = 'ORD-10' }
    # Liste de noms: the names whole, each once, without their domain; the start of the name (left in its disabled box)
    # isn't part of it, and those not found are in the banner above the grid, to copy, not in the count (#190).
    @{ Name = 'Liste de noms finds those computers, and lists the names it found nowhere, to copy'
       Prefix = 'XYZ'; Term = 'ORD-01, ord-04.demo.local ORD-99 ORD-01'; Type = 'Liste de noms'
       Filter = "Name -like '*' -and (Name -eq 'ORD-01' -or Name -eq 'ord-04' -or Name -eq 'ORD-99')"; Rows = 'ORD-01', 'ORD-04'
       Label = '2 ordinateurs'; NotFound = '1 introuvable : ORD-99'; Copied = 'ORD-99' }
    @{ Name = 'Liste de noms without a name asks for them, without querying AD'
       Prefix = ''; Term = ' , ; '; Type = 'Liste de noms'; Message = 'Entrez les noms des ordinateurs (ex. ORD-01, ORD-04)'
       Focus = 'search_term' }
    # Adresse IP: the Address session ($addressScenarios).
    # ID de clé BitLocker: ORD-09 holds 6F1C2E7A… (its C: key) and A2E47C19… (the one of 2024, left behind). A key that
    # isn't there finds no computer, and no computer is asked for.
    @{ Name = 'ID de clé BitLocker finds the computer holding the key, from the 8 characters the recovery screen shows'
       Prefix = ''; Term = '6f1c2e7a'; Type = 'ID de clé BitLocker'
       Filter = "Name -like '*' -and (DistinguishedName -eq 'CN=ORD-09,OU=Postes,DC=demo,DC=local')"; Rows = 'ORD-09' }
    @{ Name = 'ID de clé BitLocker finds an old key too, written with its hyphen, with the prefix'
       Prefix = 'ORD'; Term = 'A2E47C19-5D3B'; Type = 'ID de clé BitLocker'
       Filter = "Name -like '*ORD*' -and (DistinguishedName -eq 'CN=ORD-09,OU=Postes,DC=demo,DC=local')"; Rows = 'ORD-09' }
    @{ Name = 'ID de clé BitLocker without such a key finds no computer'
       Prefix = ''; Term = 'FFFFFFFF'; Type = 'ID de clé BitLocker'; SearchBases = @(); Count = 0; Empty = 'Aucun ordinateur trouvé dans demo.local.' }
    @{ Name = 'ID de clé BitLocker refuses fewer than 8 characters'
       Prefix = ''; Term = '6F1C2'; Type = 'ID de clé BitLocker'
       Message = "Entrez au moins les 8 premiers caractères de l'ID de la clé (ex. 6F1C2E7A)"; Focus = 'search_term' }
    @{ Name = 'ID de clé BitLocker with both boxes empty asks for the key'
       Prefix = ''; Term = ''; Type = 'ID de clé BitLocker'
       Message = "Entrez au moins les 8 premiers caractères de l'ID de la clé (ex. 6F1C2E7A)"; Focus = 'search_term' }
    # Recherche avancée. Dernière connexion: not logged on since the cutoff (midnight, that long ago), or never. Worked
    # out when checked, so a run that goes past midnight still expects the right day. ORD-03 never logged on but was
    # joined 5 days ago: au moins leaves it out. ORD-07 and NRD-02 never logged on and are old.
    @{ Name = 'Dernière connexion au moins 90 jours needs no prefix, and leaves out a computer joined recently'
       Prefix = ''; Term = ''; Type = 'Description contient'; Advanced = @{ Logon = 'atleast'; Number = '90' }
       Filter = { "Name -like '*' -and (lastLogonTimestamp -lt $(Get-LogonCutoff 90) -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))" }; Rows = 'ORD-05', 'ORD-07', 'ORD-09' }
    @{ Name = 'Dernière connexion adds up with the description'
       Prefix = ''; Term = 'poste'; Type = 'Description contient'; Advanced = @{ Logon = 'atleast'; Number = '90' }
       Filter = { "Name -like '*' -and Description -like '*poste*' -and (lastLogonTimestamp -lt $(Get-LogonCutoff 90) -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))" }; Rows = 'ORD-09' }
    @{ Name = 'Dernière connexion au moins 180 jours, with a prefix'
       Prefix = 'ORD-0'; Term = ''; Type = 'Description contient'; Advanced = @{ Logon = 'atleast'; Number = '180' }
       Filter = { "Name -like '*ORD-0*' -and (lastLogonTimestamp -lt $(Get-LogonCutoff 180) -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))" }; Rows = 'ORD-05', 'ORD-07' }
    @{ Name = 'Dernière connexion au moins 1 an in every domain'
       Prefix = ''; Term = ''; Type = 'Description contient'; Advanced = @{ Logon = 'atleast'; Number = '1'; Unit = 3 }; Domain = 'Tous les domaines'
       Filter = { "Name -like '*' -and (lastLogonTimestamp -lt $(Get-LogonCutoff 1 3) -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))" }; Rows = 'NRD-02', 'ORD-07' }
    @{ Name = 'Dernière connexion moins de 1 semaine, without Jamais'
       Prefix = 'ORD-0'; Term = ''; Type = 'Description contient'; Advanced = @{ Logon = 'less'; Number = '1'; Unit = 1 }
       Filter = { "Name -like '*ORD-0*' -and lastLogonTimestamp -ge $(Get-LogonCutoff 1 1)" }; Rows = 'ORD-01', 'ORD-02', 'ORD-04', 'ORD-06' }
    @{ Name = 'Dernière connexion without a number asks for one, without querying AD'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Advanced = @{ Logon = 'atleast'; Number = '' }
       Message = 'Entrez un nombre de 1 à 999 pour la dernière connexion (Recherche avancée)' }
    @{ Name = 'Compte Désactivés'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Advanced = @{ State = 'disabled' }
       Filter = "Name -like '*ORD*' -and Enabled -eq 'False'"; Rows = 'ORD-05', 'ORD-07', 'ORD-09' }
    @{ Name = 'Sans description needs no prefix with a criterion'
       Prefix = ''; Term = ''; Type = 'Sans description'; Advanced = @{ State = 'disabled' }
       Filter = "Name -like '*' -and -not (Description -like '*') -and Enabled -eq 'False'"; Rows = 'ORD-05', 'ORD-07' }
    @{ Name = 'Système contient, alone'
       Prefix = ''; Term = ''; Type = 'Description contient'; Advanced = @{ System = 'server' }
       Filter = "Name -like '*' -and OperatingSystem -like '*server*'"; Rows = 'DC1', 'ORD-12' }
    @{ Name = 'Every criterion at once'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Advanced = @{ Scope = 'name'; State = 'disabled'; System = 'Windows 10'; Logon = 'atleast'; Number = '90' }
       Filter = { "Name -like '*ORD*' -and Enabled -eq 'False' -and OperatingSystem -like '*Windows 10*' -and (lastLogonTimestamp -lt $(Get-LogonCutoff 90) -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))" }
       Rows = 'ORD-05' }
)

# Run in a second session, with no Communs OU in the fake AD and nord.demo.local unreachable.
$secondSessionScenarios = @(
    @{ Name = 'No Communs OU gives 0 ordinateur, not a domain-wide search'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Advanced = @{ Scope = 'name' }
       Filter = "Name -like '*ORD*'"; Count = 0; SearchBases = @() }
    @{ Name = 'An unreachable domain shows its error'
       Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Domain = 'nord.demo.local'
       Filter = "Name -like '*ORD*'"; Count = 0; Label = 'Erreur: Le serveur ne répond pas*' }
    @{ Name = 'Tous les domaines shows what the others found and names the unreachable one'
       Prefix = 'ORD-01'; Term = ''; Type = 'Description contient'; Domain = 'Tous les domaines'
       Filter = "Name -like '*ORD-01*'"; Rows = 'ORD-01'; ShownDomains = 'demo.local'; Label = '1 ordinateur (erreur : nord.demo.local)' }
    # A name may be missing only because its domain didn't answer: the banner says which one didn't.
    @{ Name = 'Liste de noms in every domain names the unreachable one next to the names not found'
       Prefix = ''; Term = 'ORD-01 NRD-01'; Type = 'Liste de noms'; Domain = 'Tous les domaines'
       Filter = "Name -like '*' -and (Name -eq 'ORD-01' -or Name -eq 'NRD-01')"; Rows = 'ORD-01'; Label = '1 ordinateur (erreur : nord.demo.local)'
       NotFound = '1 introuvable : NRD-01 · sans réponse de nord.demo.local' }
)

# Adresse IP, run with 301 extra computers (PC-001 to PC-301) for the 300 that can be looked up one by one. The fake
# DNS names 10.0.1.11 ord-01.demo.local (PTR). 10.0.1.14 (ORD-04) has no PTR record: with a prefix, each computer found
# is looked up instead; without one, or with one that finds more than 300, the name is asked for under its box (#189),
# not as an error. Only a whole address is searched (#163): .NET would read 255.255.255 as 255.255.0.255.
$addressScenarios = @(
    @{ Name = 'Adresse IP finds the computer the DNS names for the address'
       Prefix = ''; Term = '10.0.1.11'; Type = 'Adresse IP'
       Filter = "Name -like '*' -and (dNSHostName -eq 'ord-01.demo.local')"; Rows = 'ORD-01' }
    @{ Name = 'Adresse IP without a DNS name looks up the computers the prefix finds'
       Prefix = 'ORD-0'; Term = '10.0.1.14'; Type = 'Adresse IP'
       Filter = "Name -like '*ORD-0*'"; Rows = 'ORD-04' }
    @{ Name = 'Adresse IP without a DNS name nor a prefix asks for the name under its box, without querying AD'
       Prefix = ''; Term = '10.0.1.14'; Type = 'Adresse IP'
       Message = "Aucun nom DNS pour 10.0.1.14 : entrez une partie du nom, l'adresse sera cherchée parmi ces ordinateurs"
       Focus = 'prefix'; Label = '0 ordinateur'; Empty = 'Aucun nom DNS pour 10.0.1.14.' }
    @{ Name = 'Adresse IP without a DNS name nor a prefix, in every domain, asks for the name once'
       Prefix = ''; Term = '10.0.1.14'; Type = 'Adresse IP'; Domain = 'Tous les domaines'
       Message = "Aucun nom DNS pour 10.0.1.14 : entrez une partie du nom, l'adresse sera cherchée parmi ces ordinateurs"
       Focus = 'prefix'; Label = '0 ordinateur'; Empty = 'Aucun nom DNS pour 10.0.1.14.' }
    @{ Name = 'Adresse IP with a name that finds more than 300 computers asks for a more precise one'
       Prefix = 'PC-'; Term = '10.0.1.14'; Type = 'Adresse IP'; Queried = $true
       Message = 'Plus de 300 ordinateurs contiennent « PC- » : précisez le nom pour y chercher 10.0.1.14'
       Focus = 'prefix'; Label = '0 ordinateur'; Empty = 'Aucun nom DNS pour 10.0.1.14.' }
    @{ Name = 'Adresse IP refuses the start of an address rather than search another one'
       Prefix = ''; Term = '255.255.255'; Type = 'Adresse IP'
       Message = "Entrez l'adresse entière, ses quatre nombres (ex. 10.0.1.14) : pas un sous-réseau ni une plage"; Focus = 'search_term' }
    @{ Name = 'Adresse IP refuses a subnet'
       Prefix = 'ORD'; Term = '10.0.1.0/24'; Type = 'Adresse IP'
       Message = "Entrez l'adresse entière, ses quatre nombres (ex. 10.0.1.14) : pas un sous-réseau ni une plage"; Focus = 'search_term' }
    @{ Name = 'Adresse IP refuses what is not an address'
       Prefix = ''; Term = 'accueil'; Type = 'Adresse IP'
       Message = 'Entrez une adresse IP (ex. 10.0.1.14)'; Focus = 'search_term' }
    # The address is what Adresse IP asks for, even with nothing else filled in, or with only the name.
    @{ Name = 'Adresse IP with both boxes empty asks for the address'
       Prefix = ''; Term = ''; Type = 'Adresse IP'
       Message = 'Entrez une adresse IP (ex. 10.0.1.14)'; Focus = 'search_term' }
    @{ Name = 'Adresse IP with only the name asks for the address'
       Prefix = 'ORD'; Term = ''; Type = 'Adresse IP'
       Message = 'Entrez une adresse IP (ex. 10.0.1.14)'; Focus = 'search_term' }
    # The hint goes once the search changes, and a search that finds the computer asks for nothing.
    @{ Name = 'Adresse IP with the name asked for finds the computer'
       Prefix = 'ORD'; Term = '10.0.1.14'; Type = 'Adresse IP'
       Filter = "Name -like '*ORD*'"; Rows = 'ORD-04' }
)

# Run with -Domains nord.demo.local: a single domain, so no Domaine list or column.
$singleDomainScenario = @{ Name = '-Domains limits the search to that domain'
    Prefix = 'ORD'; Term = ''; Type = 'Description contient'; Domain = 'nord.demo.local'; SingleDomain = $true
    Filter = "Name -like '*ORD*'"; Rows = 'ORD-01' }

function Wait-AppWindow {
    # Only accept the window of our Repère process.
    $deadline = (Get-Date).AddSeconds(60)
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ProcessIdProperty, $app.Id),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $windowName))
    while ((Get-Date) -lt $deadline) {
        if ($app.HasExited) { throw "Repère exited before its window opened (exit code $($app.ExitCode))." }
        $found = try { $AE::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition) } catch { $null }
        if ($found) { return $found }
        Start-Sleep -Milliseconds 500
    }
    throw "The '$windowName' window didn't open within 60 seconds."
}

function Get-DesktopProblem {
    # Why the desktop can't be driven right now, or $null when it can. UI Automation and the windows of the tests live
    # on the desktop that receives the user's input, "Default". While the screen is locked, a screen saver runs or the
    # session is disconnected, that is another one (Winlogon, Screen-saver) or none this process may open, and every
    # check that needs a window then fails as if Repère were broken. The type is defined here, not at the top of the
    # script, so that Capture-Docs.ps1, which only takes this file's functions, has it too.
    if (-not ('RepereDesktop' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class RepereDesktop {
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", SetLastError = true)] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr obj, int index, StringBuilder info, int length, out int needed);
    // The name of the desktop that has the input, or null when this process can't open it (as with the lock screen).
    public static string InputDesktopName() {
        IntPtr desktop = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
        if (desktop == IntPtr.Zero) return null;
        try {
            StringBuilder name = new StringBuilder(256);
            int needed;
            return GetUserObjectInformation(desktop, 2, name, name.Capacity * 2, out needed) ? name.ToString() : null;  // UOI_NAME
        }
        finally { CloseDesktop(desktop); }
    }
}
'@
    }
    $name = [RepereDesktop]::InputDesktopName()
    if ($null -eq $name) { return "the input desktop can't be opened, which is the case while Windows is locked or the session is disconnected" }
    if ($name -ne 'Default') { return "the desktop that has the input is '$name', not the user's own ('Default'): Windows is locked or a screen saver is running" }
    $null
}

function Assert-DesktopUsable {
    # Stops the run, with one message at its end (the main script's catch), when the desktop can't be driven: what would
    # fail from here on is the desktop, not Repère.
    $problem = Get-DesktopProblem
    if ($problem) {
        $script:desktopProblem = $problem
        throw "The desktop can't be used for the UI tests: $problem."
    }
}

function Start-App([string]$Arguments, [switch]$KeepSettings) {
    # Not on a desktop that can't be driven: it would only fail to find the window.
    Assert-DesktopUsable
    # Each session starts from the default search settings, Paramètres and window (size, place, page), unless asked to
    # keep those the last one saved.
    if (-not $KeepSettings) {
        foreach ($file in 'recherche.json', 'parametres.json', 'motdepasse.json', 'fenetre.json', 'prochainnom.json') { Remove-Item (Join-Path $env:APPDATA "Repere\$file") -ErrorAction SilentlyContinue }
    }
    # In strict mode, Repère's own errors go to a file for each start (Show-StrictError lists them at the end): one
    # inside an event handler only stops its statement, and the window carries on.
    $errors = @{}
    # (Not when another script uses these helpers: Capture-Docs.ps1 has no such list.)
    if ($env:REPERE_STRICT -and $null -ne $script:StrictErrorFiles) {
        $script:StrictErrorFiles.Add((Join-Path ([IO.Path]::GetTempPath()) "repere-errors-$PID-$($script:StrictErrorFiles.Count).txt"))
        $errors.RedirectStandardError = $script:StrictErrorFiles[-1]
    }
    $script:app = Start-Process $pwsh -ArgumentList "-NoProfile -File `"$appScript`" -FakeAD -Language fr $Arguments" -WindowStyle Hidden -PassThru @errors
    $script:window = Wait-AppWindow
}

function Stop-App {
    # UI Automation's Close does nothing while the Apparence menu is open: then WM_CLOSE, posted to the window.
    $handle = [IntPtr]::Zero
    if ($script:window) {
        try {
            $handle = [IntPtr]$script:window.Current.NativeWindowHandle
            $script:window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        }
        catch { Write-Verbose "Fenêtre déjà fermée : $_" }
        $script:window = $null
    }
    if ($script:app) {
        if (-not $script:app.WaitForExit(1000) -and $handle -ne [IntPtr]::Zero) {
            [RepereWindows]::PostMessage($handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null  # WM_CLOSE
        }
        if (-not $script:app.WaitForExit(15000)) { Stop-Process -Id $script:app.Id -Force }
        $script:app = $null
    }
}

function Find-Control([string]$AutomationId) {
    # A control of the main window or of a window it owns. Just after a window opens, or while the grid is redrawn, UI
    # Automation can miss it for a moment: looked for again for up to 2 s before giving up.
    $condition = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId)
    for ($i = 0; $i -lt 8; $i++) {
        $element = $window.FindFirst($Descendants, $condition)
        if ($element) { return $element }
        Start-Sleep -Milliseconds 250
    }
    throw "Control '$AutomationId' not found."
}

function Set-Text([string]$AutomationId, [string]$Text) {
    (Find-Control $AutomationId).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
}

function Get-ComboText([string]$AutomationId) {
    # The selected item of a list (a ComboBox, which has no Value pattern when it isn't editable).
    $selection = (Find-Control $AutomationId).GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()
    if ($selection.Count) { $selection[0].Current.Name }
}

function Select-ComboItem([string]$AutomationId, [string]$Type) {
    if ((Get-ComboText $AutomationId) -eq $Type) { return }

    # The items only exist once the list has been opened. They're listed under the ComboBox, and only list
    # items match: a grid cell can have the same text (a domain name in the Domaine column).
    $combo = Find-Control $AutomationId
    $expand = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $byName = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Type),
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem))
    $item = $null
    for ($i = 0; $i -lt 20 -and -not $item; $i++) {
        if ($expand.Current.ExpandCollapseState -ne 'Expanded') { $expand.Expand() }
        Start-Sleep -Milliseconds 150
        $item = $combo.FindFirst($Descendants, $byName)
    }
    if (-not $item) { throw "'$Type' not found in the '$AutomationId' list." }
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    if ($expand.Current.ExpandCollapseState -eq 'Expanded') { $expand.Collapse() }
    for ($i = 0; $i -lt 20 -and (Get-ComboText $AutomationId) -ne $Type; $i++) { Start-Sleep -Milliseconds 100 }
    if ((Get-ComboText $AutomationId) -ne $Type) { throw "'$Type' couldn't be selected in the '$AutomationId' list." }
}

function Get-ComboItemName([string]$AutomationId) {
    # The items of a list, in order: opened, read, then closed again.
    $combo = Find-Control $AutomationId
    $expand = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    $items = $null
    for ($i = 0; $i -lt 20 -and -not $items.Count; $i++) {
        if ($expand.Current.ExpandCollapseState -ne 'Expanded') { $expand.Expand() }
        Start-Sleep -Milliseconds 150
        $items = $combo.FindAll($Descendants, $isItem)
    }
    if ($expand.Current.ExpandCollapseState -eq 'Expanded') { $expand.Collapse() }
    @($items | ForEach-Object { $_.Current.Name })
}

function Select-SearchType([string]$Type) { Select-ComboItem 'search_type' $Type }
function Select-Domain([string]$Domain) { Select-ComboItem 'domain' $Domain }

function Open-AdvancedSearch {
    # Avancée's popup, once it shows.
    Invoke-Element (Find-Control 'advanced')
    for ($i = 0; $i -lt 20 -and -not (Find-ShownControl 'advanced_reset'); $i++) { Start-Sleep -Milliseconds 150 }
    if (-not (Find-ShownControl 'advanced_reset')) { throw "Avancée's popup didn't open." }
    Start-Sleep -Milliseconds 150
}

function Use-AdvancedSearch {
    # The popup open for the next step: it closes on its own when the window stops being the active one (another
    # window took the focus meanwhile), its criteria kept, so it's opened again.
    if (-not (Find-ShownControl 'advanced_reset')) { Open-AdvancedSearch }
}

function Close-AdvancedSearch {
    # Échap closes the popup, its criteria kept. Already closed (it does when the window loses the focus): nothing to do.
    $reset = Find-ShownControl 'advanced_reset'
    if (-not $reset) { return }
    Send-Key 0x1B (Get-HolderWindow $reset)
    for ($i = 0; $i -lt 20 -and (Find-ShownControl 'advanced_reset'); $i++) { Start-Sleep -Milliseconds 150 }
    if (Find-ShownControl 'advanced_reset') { throw "Échap didn't close Avancée's popup." }
}

function Select-AdvancedButton([string]$Name) {
    # One of the popup's buttons: scope_all, scope_name, state_disabled, logon_atleast, logon_unit3…
    Use-AdvancedSearch
    (Find-Control "advanced_$Name").GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 100
}

function Set-AdvancedSearch([hashtable]$Criteria = @{}) {
    # The Recherche avancée's criteria, in its popup: Réinitialiser, then those given (Scope: all or name, never ou,
    # which opens the tree; OUName, the sample AD's Communs OUs by default with name; State: all, enabled, disabled;
    # System; Logon: any, atleast, less; Number, as typed; Unit, 0 to 3; Never), then Échap.
    Open-AdvancedSearch
    Invoke-Element (Find-Control 'advanced_reset')
    Start-Sleep -Milliseconds 150
    if ($Criteria.Scope) { Select-AdvancedButton "scope_$($Criteria.Scope)" }
    $ouName = if ($Criteria.OUName) { $Criteria.OUName } elseif ($Criteria.Scope -eq 'name') { 'Communs' }
    if ($ouName) { Use-AdvancedSearch; Set-Text 'advanced_ou_name' $ouName }
    if ($Criteria.State) { Select-AdvancedButton "state_$($Criteria.State)" }
    if ($Criteria.System) { Use-AdvancedSearch; Set-Text 'advanced_system' $Criteria.System }
    if ($Criteria.Logon) { Select-AdvancedButton "logon_$($Criteria.Logon)" }
    if ($Criteria.ContainsKey('Number')) { Use-AdvancedSearch; Set-Text 'advanced_logon_number' $Criteria.Number }
    if ($Criteria.ContainsKey('Unit')) { Select-AdvancedButton "logon_unit$($Criteria.Unit)" }
    if ($Criteria.ContainsKey('Never')) {
        Use-AdvancedSearch
        $toggle = (Find-Control 'advanced_logon_never').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if (($toggle.Current.ToggleState -eq 'On') -ne $Criteria.Never) { $toggle.Toggle() }
    }
    Start-Sleep -Milliseconds 150
    Close-AdvancedSearch
}

function Reset-AdvancedSearch {
    # No criterion: only opened when Avancée says some are set.
    if ((Find-Control 'advanced_text').Current.Name -ne 'Avancée') { Set-AdvancedSearch }
}

function Find-ShownControl([string]$AutomationId) {
    # A control of the main window, or $null while it's collapsed: WPF leaves collapsed controls out of UI Automation.
    $window.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId))
}

function Test-SearchRunning {
    # The search runs in the background: meanwhile Rechercher is disabled and Annuler is shown.
    (-not (Find-Control 'button').Current.IsEnabled) -or [bool](Find-ShownControl 'cancel_search')
}

function Wait-SearchEnd([int]$TimeoutSeconds = 30) {
    # Until Rechercher is back and Annuler gone, then a moment for the grid to draw its rows.
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while (Test-SearchRunning) {
        if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "The search didn't end within $TimeoutSeconds seconds." }
        Start-Sleep -Milliseconds 50
    }
    Start-Sleep -Milliseconds 300
}

function Invoke-Search {
    # Repère handles the click a moment after Invoke returns. Wait for the search to start (or for the label or the
    # search time to change, or for what's missing to show, when it was refused or already done at the first look), then
    # for it to end.
    $countBefore = (Find-Control 'results_count').Current.Name
    $timeBefore = (Find-Control 'search_time').Current.Name
    (Find-Control 'button').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt 1500 -and -not (Test-SearchRunning) -and -not (Find-ShownControl 'search_hint_text') -and
           (Find-Control 'results_count').Current.Name -eq $countBefore -and (Find-Control 'search_time').Current.Name -eq $timeBefore) {
        Start-Sleep -Milliseconds 20
    }
    Wait-SearchEnd
}

function Start-SlowSearch([string]$Domain, [string]$Prefix) {
    # Fills in the form and clicks Rechercher without waiting for the results: returns a stopwatch started at the
    # click, once Annuler shows.
    Select-Domain $Domain
    Select-SearchType 'Description contient'
    Reset-AdvancedSearch
    Set-Text 'prefix' $Prefix
    Set-Text 'search_term' ''
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    (Find-Control 'button').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    while (-not (Find-ShownControl 'cancel_search')) {
        if ($watch.ElapsedMilliseconds -ge 5000) { throw "Annuler didn't show up after Rechercher." }
        Start-Sleep -Milliseconds 20
    }
    $watch
}

function Wait-Elapsed($Watch, [int]$Milliseconds) {
    # Until $Milliseconds have passed on $Watch.
    $left = $Milliseconds - $Watch.ElapsedMilliseconds
    if ($left -gt 0) { Start-Sleep -Milliseconds $left }
}

function Stop-RunningSearch {
    # After a failed check: Annuler if a search still runs, so the next check doesn't start during it.
    $cancelButton = Find-ShownControl 'cancel_search'
    if ($cancelButton) {
        try { $cancelButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { Write-Verbose "Annuler déjà parti : $_" }
    }
    Wait-SearchEnd
}

function Get-SearchDuration {
    # search_time reads « en 1 234 ms » (fr-CA groups the digits with a no-break space): the milliseconds, or
    # $null when it reads something else.
    $text = (Find-Control 'search_time').Current.Name
    if ($text -match '^en ([\d\s  ]+) ms$') { [int]($Matches[1] -replace '\D', '') }
}

function Get-ResultName {
    $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    @((Find-Control 'data_grid').FindAll($Descendants, $isText) |
        ForEach-Object { $_.Current.Name } |
        Where-Object { $_ -match '^((ORD|NRD)-\d+|DC\d+)$' } |
        Sort-Object)
}

function Get-ResultRowElement {
    # The grid's rows, sorted by their position on screen. The grid only creates the rows it shows, which is
    # every row in these tests.
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    @((Find-Control 'data_grid').FindAll($Descendants, $isRow)) | Sort-Object { $_.Current.BoundingRectangle.Top }
}

function Get-ResultRow {
    # The cell texts of each row, in column order. Every cell's text is named CellTextBlock; the Compte dot's
    # text is Activé or Désactivé.
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    foreach ($row in Get-ResultRowElement) {
        , @($row.FindAll($Descendants, $isCell) | ForEach-Object { $_.Current.Name })
    }
}

function Get-LoggedQuery {
    if (Test-Path $queryLog) { @(Get-Content $queryLog -Encoding utf8 | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
}

function Wait-LoggedCommand([string]$Command, [int]$Skip, [int]$Count = 1) {
    # Until $Count $Command were sent since the query $Skip, or for 5 s: the check then says what it found. OK closes a
    # dialog first and acts after (Show-Dialog), so Close-OwnedDialog's fixed wait can end before anything was sent.
    for ($i = 0; $i -lt 50; $i++) {
        if (@(Get-LoggedQuery | Select-Object -Skip $Skip | Where-Object Command -eq $Command).Count -ge $Count) { return }
        Start-Sleep -Milliseconds 100
    }
}

function Format-Query($Query) {
    $where = if ($Query.SearchBase) { $Query.SearchBase } else { 'the whole domain' }
    $server = if ($Query.Server) { $Query.Server } else { "the user's domain" }
    "$($Query.Command) -Filter $($Query.Filter) in $where on $server"
}

function Initialize-WindowImage {
    # What Get-WindowImage draws with, once, in physical pixels.
    if (-not ('ReperePrintWindow' -as [type])) {
        Add-Type -AssemblyName System.Drawing
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ReperePrintWindow {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
    }
    [ReperePrintWindow]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null  # physical pixels
}

function Save-Screenshot([string]$Name, $Target = $window) {
    Initialize-WindowImage
    $image = Get-WindowImage $Target
    if ([System.Windows.Automation.Automation]::Compare($Target, $window)) {
        # An open popup (the Apparence panel) is a window of its own: it's drawn over the main window, where it shows.
        $graphics = [System.Drawing.Graphics]::FromImage($image.Bitmap)
        foreach ($popup in Get-AppWindow | Where-Object { $_.Current.ClassName -eq 'Popup' }) {
            $part = Get-WindowImage $popup
            # Its see-through edge (room for the shadow) comes out black.
            $part.Bitmap.MakeTransparent([System.Drawing.Color]::Black)
            $graphics.DrawImage($part.Bitmap, $part.Left - $image.Left, $part.Top - $image.Top)
            $part.Bitmap.Dispose()
        }
        $graphics.Dispose()
    }
    New-Item -ItemType Directory -Force -Path $ScreenshotDirectory | Out-Null
    $image.Bitmap.Save((Join-Path $ScreenshotDirectory "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $image.Bitmap.Dispose()
}

function Get-WindowImage($Element) {
    # The window as drawn, even behind other windows, and where it is on screen.
    $handle = [IntPtr]$Element.Current.NativeWindowHandle
    $rect = [ReperePrintWindow+RECT]::new()
    [ReperePrintWindow]::GetWindowRect($handle, [ref]$rect) | Out-Null
    $bitmap = [System.Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    [ReperePrintWindow]::PrintWindow($handle, $hdc, 2) | Out-Null  # PW_RENDERFULLCONTENT
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()
    @{ Bitmap = $bitmap; Left = $rect.Left; Top = $rect.Top }
}

function Send-Key([int]$VirtualKey, $Target = $window) {
    # For what UI Automation can't do: open the right-click menu, close it, and press a dialog's default button.
    # The keys are posted straight to the window, so they can't reach any other app; WPF hands them to the
    # control that has the keyboard focus.
    # A window that has closed meanwhile has no handle any more: nothing to send it.
    $native = $null
    try { $native = $Target.Current.NativeWindowHandle } catch { $native = $null }
    if (-not $native) { return }
    $handle = [IntPtr]$native
    [RepereWindows]::PostMessage($handle, 0x0100, [IntPtr]$VirtualKey, [IntPtr]1) | Out-Null           # WM_KEYDOWN
    [RepereWindows]::PostMessage($handle, 0x0101, [IntPtr]$VirtualKey, [IntPtr]0xC0000001) | Out-Null  # WM_KEYUP
    Start-Sleep -Milliseconds 300
}

function Test-WindowEnabled {
    # A modal dialog disables the main window's handle; UI Automation's IsEnabled doesn't follow it.
    [RepereWindows]::IsWindowEnabled([IntPtr]$window.Current.NativeWindowHandle)
}

function Invoke-PrefixSearch([string]$Prefix, [string]$Term = '') {
    Select-SearchType 'Description contient'
    Reset-AdvancedSearch
    Set-Text 'prefix' $Prefix
    Set-Text 'search_term' $Term
    Invoke-Search
}

function Select-ResultRow([string]$Name) {
    # Selects that row alone, through UI Automation, then waits for the action bar's selection text to name it.
    $isName = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock'),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Name))
    $row = @(Get-ResultRowElement) | Where-Object { $_.FindFirst($Descendants, $isName) } | Select-Object -First 1
    if (-not $row) { throw "$Name isn't in the results." }
    $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    $selection = Find-Control 'selection_text'
    for ($i = 0; $i -lt 30 -and $selection.Current.Name -ne "$Name sélectionné"; $i++) { Start-Sleep -Milliseconds 100 }
    if ($selection.Current.Name -ne "$Name sélectionné") { throw "Couldn't select $Name (selection: '$($selection.Current.Name)')." }
}

function Add-ResultRow([string]$Name) {
    # Adds that row to the selection (like Ctrl + click).
    $isName = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock'),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Name))
    $row = @(Get-ResultRowElement) | Where-Object { $_.FindFirst($Descendants, $isName) } | Select-Object -First 1
    if (-not $row) { throw "$Name isn't in the results." }
    $before = (Find-Control 'selection_text').Current.Name
    $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).AddToSelection()
    $selection = Find-Control 'selection_text'
    for ($i = 0; $i -lt 30 -and $selection.Current.Name -eq $before; $i++) { Start-Sleep -Milliseconds 100 }
}

function Get-AppWindow {
    # The windows the main window owns: its dialogs, Paramètres, and the popups of its menus.
    # UI Automation lists them under the main window rather than at the top level.
    $isWindow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    @($window.FindAll([System.Windows.Automation.TreeScope]::Children, $isWindow))
}

function Get-OpenMenuItem {
    # The items of the open menu, if any: a menu is a popup of its own.
    $isMenuItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)
    @(foreach ($top in Get-AppWindow) { $top.FindAll($Descendants, $isMenuItem) })
}

function Clear-ResultSelection {
    # A search selects nothing, but an earlier check may have: this is for the checks of no selection at all.
    foreach ($row in @(Get-ResultRowElement)) {
        $item = $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($item.Current.IsSelected) { $item.RemoveFromSelection() }
    }
    Start-Sleep -Milliseconds 300
}

function Open-ResultMenu {
    # The context menu key, while the grid has the focus. Right after a dialog closes, the key can be
    # missed, so it's sent again if the menu doesn't show up.
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        (Find-Control 'data_grid').SetFocus()
        Send-Key 0x5D
        for ($i = 0; $i -lt 10; $i++) {
            $items = Get-OpenMenuItem
            if ($items.Count) { return $items }
            Start-Sleep -Milliseconds 200
        }
    }
    throw "The right-click menu didn't open."
}

function Close-Menu {
    # Escape, until the menu is gone.
    for ($i = 0; $i -lt 3 -and (Get-OpenMenuItem).Count; $i++) { Send-Key 0x1B }
}

# The right-click menu's submenus and their items, in order (separators aren't items).
$menuGroups = [ordered]@{
    'Active Directory'      = "Modifier la description…", "Déplacer vers…", "Groupes…", "Ajouter à un groupe…", "Retirer d'un groupe…", "Prochain nom de cette série…", "Activer", "Désactiver…", "Supprimer de l'AD…"
    'Clés et mots de passe' = "Clés BitLocker…", "Mot de passe LAPS…"
    'Outils à distance'     = "Bureau à distance", "Prendre la main…", "Utilisateurs connectés…", "Vérifier en ligne", "Caractéristiques…", "Gestion de l'ordinateur", "Ouvrir C$", "PowerShell à distance", "Services", "Observateur d'événements", "Forcer les stratégies (gpupdate)"
    'Redémarrage'           = "Redémarrer…", "Annuler le redémarrage"
    'Copier'                = "Copier le nom", "Copier les noms sur une ligne", "Copier les lignes"
}

function Open-MenuGroup([string]$Group) {
    # Opens a submenu of the open right-click menu and returns its items (the open menu's items that aren't submenus).
    $parent = @(Get-OpenMenuItem) | Where-Object { $_.Current.Name -eq $Group } | Select-Object -First 1
    if (-not $parent) { throw "No '$Group' in the right-click menu." }
    if (-not $parent.Current.IsEnabled) { return @() }
    $parent.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    # The popup fills in over a few moments: wait until every item expected is listed (or what's there after 3 s).
    $items = @()
    for ($i = 0; $i -lt 20; $i++) {
        # UI Automation lists a submenu's items twice (under the submenu and under its popup): each name once.
        $seen = @{}
        $items = @(Get-OpenMenuItem | Where-Object { $menuGroups.Keys -notcontains $_.Current.Name -and -not $seen.ContainsKey($_.Current.Name) } | ForEach-Object { $seen[$_.Current.Name] = $true; $_ })
        if ($items.Count -ge @($menuGroups[$Group]).Count) { return $items }
        Start-Sleep -Milliseconds 150
    }
    if ($items.Count) { return $items }
    throw "The '$Group' submenu didn't open."
}

function Close-MenuGroup([string]$Group) {
    $parent = @(Get-OpenMenuItem) | Where-Object { $_.Current.Name -eq $Group } | Select-Object -First 1
    if ($parent) { $parent.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() }
    Start-Sleep -Milliseconds 150
}

function Get-MenuItemState([string]$Name) {
    # Selects the row, opens the right-click menu and returns which items are enabled, by header: the submenus, and
    # the items of the enabled ones (a disabled submenu's items aren't listed, so they read as disabled).
    Select-ResultRow $Name
    $states = @{}
    foreach ($item in @(Open-ResultMenu)) { $states[$item.Current.Name] = $item.Current.IsEnabled }
    foreach ($group in $menuGroups.Keys) {
        foreach ($item in @(Open-MenuGroup $group)) { $states[$item.Current.Name] = $item.Current.IsEnabled }
        Close-MenuGroup $group
    }
    Close-Menu
    $states
}

function Invoke-ResultMenuItem([string]$Header) {
    # Opens the right-click menu, then the submenu that holds the item, and clicks it.
    $group = @($menuGroups.Keys | Where-Object { $menuGroups[$_] -contains $Header })[0]
    if (-not $group) { throw "No '$Header' in the right-click menu." }
    $null = Open-ResultMenu
    $item = @(Open-MenuGroup $group) | Where-Object { $_.Current.Name -eq $Header } | Select-Object -First 1
    if (-not $item) { throw "No '$Header' in the '$group' submenu." }
    $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Wait-AnyDialog {
    # A Repère dialog: a window owned by the main one that has the dialog's Annuler/Fermer button.
    for ($i = 0; $i -lt 20; $i++) {
        foreach ($top in Get-AppWindow) {
            if (Get-DialogPart $top 'dialog_cancel') { return $top }
        }
        Start-Sleep -Milliseconds 250
    }
}

function Open-ActionDialog([string]$Name, [string]$MenuItem, [string]$Title, [string]$Expected) {
    # Selects the row, picks the menu item and checks that the right dialog opened, about that computer.
    Select-ResultRow $Name
    Invoke-ResultMenuItem $MenuItem
    $dialog = Wait-AnyDialog
    if (-not $dialog) { throw "No dialog opened after '$MenuItem' for $Name." }
    $message = Get-DialogText $dialog
    if ($dialog.Current.Name -ne $Title -or $message -notlike $Expected) {
        throw "'$MenuItem' for $Name opened '$($dialog.Current.Name)': '$message', expected '$Title'."
    }
    $dialog
}

function Close-OpenDialog {
    # After a failed check: close the menu and any dialog, so the next checks start clean. The main window
    # isn't in Get-AppWindow, so it can't be closed here.
    Send-Key 0x1B
    foreach ($top in Get-AppWindow) {
        try { $top.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() } catch { Write-Verbose "Pas une fenêtre de dialogue : $_" }
    }
    Wait-DialogsClosed
}

function Invoke-Check([string]$Name, [scriptblock]$Body) {
    # Runs a check that fills in a list of problems; an error counts as one and doesn't stop the run.
    $problems = [System.Collections.Generic.List[string]]::new()
    try {
        & $Body $problems
    }
    catch {
        $problems.Add("error: $($_.Exception.Message)")
        Close-OpenDialog
    }
    Write-Result $Name $problems
}

function Test-Foreground($Window) {
    # Whether $Window is the one Windows has in front, once a window has closed (2 s at most): not another application's.
    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    for ($i = 0; $i -lt 20; $i++) {
        if ([RepereFocus]::GetForegroundWindow() -eq $handle) { return $true }
        Start-Sleep -Milliseconds 100
    }
    $false
}

function Wait-Dialog([string]$Title) {
    # Dialogs are owned by the main window, so UI Automation lists them under it.
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Title))
    for ($i = 0; $i -lt 40; $i++) {
        $dialog = $window.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
        if ($dialog) { return $dialog }
        Start-Sleep -Milliseconds 250
    }
    throw "The '$Title' dialog didn't open."
}

function Wait-ActionNotice([string]$Expected) {
    # What the status bar says after an action that went well, once it says $Expected (or after 3 s): there's no window
    # then. A notice from an earlier action may still show meanwhile.
    $text = ''
    for ($i = 0; $i -lt 20; $i++) {
        $notice = Find-ShownControl 'action_notice'
        $text = if ($notice) { $notice.Current.Name } else { '' }
        if ($text -eq $Expected) { break }
        Start-Sleep -Milliseconds 150
    }
    $text
}

function Test-ReportShown {
    # Whether a dialog with a message is open (a report, which an action that went well no longer shows).
    [bool](@(Get-AppWindow | Where-Object { Get-DialogPart $_ 'dialog_message' }).Count)
}

function Wait-FailureReport([string]$Title) {
    # The report of an action that failed somewhere: a dialog named after the action, like its confirmation was, so
    # it's told apart by its first line.
    for ($i = 0; $i -lt 40; $i++) {
        foreach ($top in Get-AppWindow) {
            $message = Get-DialogPart $top 'dialog_message'
            if ($top.Current.Name -eq $Title -and $message -and $message.Current.Name.StartsWith('✖')) { return $top }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "No '$Title' report of a failure opened."
}

function Get-BitLockerKeyRow($Dialog) {
    # Clés BitLocker's keys, top to bottom: each key's box is named after it (computer | date | status | ID | password).
    $isBox = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::CheckBox)
    @($Dialog.FindAll($Descendants, $isBox) | Where-Object { $_.Current.AutomationId -like 'bitlocker_key_*' } |
        Sort-Object { $_.Current.BoundingRectangle.Top } | ForEach-Object { $_.Current.Name })
}

function Wait-OwnedDialog($Owner, [string]$Title) {
    # A dialog opened over another one (a confirmation over Clés BitLocker): UI Automation lists it under that one.
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Title))
    for ($i = 0; $i -lt 40; $i++) {
        $dialog = $Owner.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
        if ($dialog) { return $dialog }
        Start-Sleep -Milliseconds 250
    }
    throw "The '$Title' dialog didn't open over '$($Owner.Current.Name)'."
}

function Get-DialogPart($Dialog, [string]$AutomationId) {
    $Dialog.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId))
}

function Read-NewPassword($Shown, $Problems) {
    # Mot de passe réinitialisé's password: hidden at first (#332), then shown by its eye, and hidden again by the other.
    $box = Get-DialogPart $Shown 'user_new_password'
    $value = { $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
    if ((& $value) -ne [string]::new([char]0x25CF, 12)) { $Problems.Add("before its eye, the new password reads '$(& $value)'") }
    Invoke-Element (Get-DialogPart $Shown 'user_new_password_show')
    Start-Sleep -Milliseconds 200
    $password = & $value
    Invoke-Element (Get-DialogPart $Shown 'user_new_password_hide')
    Start-Sleep -Milliseconds 200
    if ((& $value) -ceq $password -or -not (Get-DialogPart $Shown 'user_new_password_show')) { $Problems.Add('after hiding it, the new password is still shown') }
    $password
}

function Get-DialogText($Dialog) {
    # The message, plus the read-only details box (BitLocker keys) when there's one, and Mot de passe LAPS' cards.
    $message = Get-DialogPart $Dialog 'dialog_message'
    $text = if ($message) { $message.Current.Name } else { '' }
    $details = Get-DialogPart $Dialog 'dialog_details'
    if ($details) { $text += "`n" + $details.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
    $sections = @(Get-LapsSection $Dialog)
    if ($sections) { $text += "`n" + ($sections -join "`n`n") }
    $text
}

function Get-LapsSection($Dialog) {
    # Mot de passe LAPS' cards, top to bottom: each reads as its computer's text (name and kind, account, password).
    $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    @($Dialog.FindAll($Descendants, $isText) | Where-Object { $_.Current.AutomationId -like 'laps_section_*' } |
        Sort-Object { $_.Current.BoundingRectangle.Top } | ForEach-Object { $_.Current.Name })
}

function Test-DialogRoom($Dialog, [string]$ScrollId, [string]$FirstId, $Problems) {
    # A window sized to its content, with what's in $ScrollId scrolling between its header and its footer. Maximized,
    # restored and made taller by hand, $FirstId stays just under the header and the scrolling area reaches the footer;
    # in a small window, it scrolls.
    $measure = {
        $scroll = (Get-DialogPart $Dialog $ScrollId).Current.BoundingRectangle
        [pscustomobject]@{
            Above = (Get-DialogPart $Dialog $FirstId).Current.BoundingRectangle.Top - $Dialog.Current.BoundingRectangle.Top
            Below = (Get-DialogPart $Dialog 'dialog_cancel').Current.BoundingRectangle.Top - $scroll.Bottom
        }
    }
    $state = $Dialog.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
    $transform = $Dialog.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern)
    $expected = & $measure
    $box = $Dialog.Current.BoundingRectangle
    $compare = {
        param([string]$When, [double]$Margin = 2)
        $now = & $measure
        if ([Math]::Abs($now.Above - $expected.Above) -gt $Margin) { $Problems.Add("$When, the content starts $($now.Above) pixels down, not $($expected.Above)") }
        if ([Math]::Abs($now.Below - $expected.Below) -gt 2) { $Problems.Add("$When, the scrolling area ends $($now.Below) pixels above the button, not $($expected.Below)") }
    }

    $state.SetWindowVisualState('Maximized')
    Start-Sleep -Milliseconds 800
    # Maximized, the window's edges are past the screen: 8 pixels at 100 %, more at a larger scale.
    & $compare 'maximized' 24
    $state.SetWindowVisualState('Normal')
    Start-Sleep -Milliseconds 800
    & $compare 'restored'
    $height = $Dialog.Current.BoundingRectangle.Height
    if ([Math]::Abs($height - $box.Height) -gt 2) { $Problems.Add("restored, the window is $height pixels tall, not $($box.Height)") }

    $transform.Move($box.Left, 10)
    $transform.Resize($box.Width, $AE::RootElement.Current.BoundingRectangle.Height - 40)
    Start-Sleep -Milliseconds 800
    & $compare 'taller by hand'

    $transform.Resize($box.Width, 220)
    Start-Sleep -Milliseconds 800
    $scroll = (Get-DialogPart $Dialog $ScrollId).GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
    if (-not $scroll.Current.VerticallyScrollable) { $Problems.Add('in a small window, the content has no scroll bar') }
    else {
        $scroll.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll, 100)
        Start-Sleep -Milliseconds 300
        if ($scroll.Current.VerticalScrollPercent -lt 99) { $Problems.Add("in a small window, the content scrolls to $($scroll.Current.VerticalScrollPercent) %") }
    }
    $close = (Get-DialogPart $Dialog 'dialog_cancel').Current.BoundingRectangle
    if ($close.Bottom -gt $Dialog.Current.BoundingRectangle.Bottom) { $Problems.Add('in a small window, Fermer is cut off') }
}

function Close-Dialog($Dialog, [string]$Button) {
    (Get-DialogPart $Dialog $Button).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Wait-DialogsClosed
}

function Wait-DialogsClosed {
    # The main window is enabled again once every dialog is closed (they're modal).
    for ($i = 0; $i -lt 40 -and -not (Test-WindowEnabled); $i++) { Start-Sleep -Milliseconds 250 }
    Start-Sleep -Milliseconds 300
}

function Get-ResultCell([string]$Name, [int]$Column) {
    # Column: 0 Compte, 1 Nom, 2 Description, 3 Dernière connexion, 4 Système, 5 Domaine, 6 Emplacement.
    $row = @(Get-ResultRow) | Where-Object { $_[1] -eq $Name } | Select-Object -First 1
    if ($row) { $row[$Column] }
}

function Test-BitLockerNote {
    # Clés BitLocker for computers without a key (ORD-01, ORD-02; ORD-09 has some): a toast for one alone, a line naming
    # them above the others' keys.
    Invoke-PrefixSearch 'ORD-0'
    Invoke-Check 'Clés BitLocker says when there are none, in a toast rather than a window' {
        param($problems)
        Select-ResultRow 'ORD-02'
        Invoke-ResultMenuItem $script:ResultMenuItems[2]
        $notice = Wait-ActionNotice 'Clés BitLocker : ORD-02 : aucune clé BitLocker'
        if ($notice -ne 'Clés BitLocker : ORD-02 : aucune clé BitLocker') { $problems.Add("the toast says '$notice'") }
        if (@(Get-AppWindow | Where-Object { Get-DialogPart $_ 'dialog_cancel' }).Count) { $problems.Add('a window opened') }
    }

    Invoke-Check 'Clés BitLocker names the computers without a key on one line' {
        param($problems)
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-02'
        Add-ResultRow 'ORD-09'
        Invoke-ResultMenuItem $script:ResultMenuItems[2]
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        $notes = Get-DialogPart $dialog 'bitlocker_notes'
        $text = if ($notes) { $notes.Current.Name }
        if ($text -notmatch '^Clé BitLocker manquante : ORD-0[12], ORD-0[12]$' -or $text -notlike '*ORD-01*' -or $text -notlike '*ORD-02*') { $problems.Add("the note says '$text'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'cles-bitlocker-manquantes' $dialog }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

# The right-click menu's items, in order: Test-ResultMenu and Test-RemoteActions pick them by index.
$script:ResultMenuItems = "Modifier la description…", "Déplacer vers…", "Clés BitLocker…", "Mot de passe LAPS…", "Activer", "Désactiver…", "Supprimer de l'AD…", "Vérifier en ligne", "Caractéristiques…", "Bureau à distance", "Gestion de l'ordinateur", "Ouvrir C$", "PowerShell à distance", "Services", "Observateur d'événements", "Redémarrer…", "Annuler le redémarrage", "Forcer les stratégies (gpupdate)", "Groupes…", "Prendre la main…", "Utilisateurs connectés…"

function Test-ResultMenu {
    # Runs against a fresh fake AD, since it edits and removes computers.
    $menuItems = $script:ResultMenuItems
    Invoke-PrefixSearch 'ORD-0'

    Invoke-Check 'The right-click menu has four submenus, disabled without a selection' {
        param($problems)
        Clear-ResultSelection
        $items = @(Open-ResultMenu)
        $names = @($items | ForEach-Object { $_.Current.Name })
        if (($names -join ', ') -ne ($menuGroups.Keys -join ', ')) { $problems.Add("menu items: $($names -join ', ')") }
        foreach ($item in $items) {
            if ($item.Current.IsEnabled) { $problems.Add("'$($item.Current.Name)' is enabled") }
        }
        Close-Menu
    }

    Invoke-Check 'Each submenu holds its actions, in order' {
        param($problems)
        Select-ResultRow 'ORD-01'
        $null = Open-ResultMenu
        foreach ($group in $menuGroups.Keys) {
            $names = (@(Open-MenuGroup $group) | ForEach-Object { $_.Current.Name }) -join ', '
            if ($names -ne ($menuGroups[$group] -join ', ')) { $problems.Add("$group holds: $names") }
            Close-MenuGroup $group
        }
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-groupes' }
        Close-Menu
    }

    Invoke-Check 'Modifier la description changes AD and the row, without a new search' {
        param($problems)
        $dialog = Open-ActionDialog 'ORD-01' $menuItems[0] 'Modifier la description' 'Description de ORD-01 :'
        $queriesBefore = @(Get-LoggedQuery).Count
        if (Test-WindowEnabled) { $problems.Add('the main window stays enabled behind the dialog') }
        $textBox = (Get-DialogPart $dialog 'dialog_text').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($textBox.Current.Value -ne "Bureau d'accueil") { $problems.Add("text box holds '$($textBox.Current.Value)', expected the current description") }
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-1-modifier-la-description' $dialog }
        $textBox.SetValue('Accueil principal')
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $notice = Wait-ActionNotice 'Description modifiée : ✔ ORD-01'
        if ($notice -ne 'Description modifiée : ✔ ORD-01') { $problems.Add("the status bar says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report window opened') }
        if ((Get-ResultCell 'ORD-01' 2) -ne 'Accueil principal') { $problems.Add("row shows '$(Get-ResultCell 'ORD-01' 2)'") }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
        $writes = @($calls | Where-Object Command -eq 'Set-ADComputer')
        if ($writes.Count -ne 1 -or $writes[0].Identity -ne 'CN=ORD-01,OU=Postes,DC=demo,DC=local' -or $writes[0].Description -ne 'Accueil principal' -or $writes[0].Server -ne 'demo.local') {
            $problems.Add("AD writes: $($writes | ConvertTo-Json -Compress)")
        }
        if ($calls | Where-Object Command -eq 'Get-ADComputer') { $problems.Add('the grid was refreshed with a new search') }
    }

    Invoke-Check 'A failed change is reported and the row keeps its description' {
        param($problems)
        Invoke-PrefixSearch 'ORD-1'
        $dialog = Open-ActionDialog 'ORD-12' $menuItems[0] 'Modifier la description' 'Description de ORD-12 :'
        (Get-DialogPart $dialog 'dialog_text').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Nouvelle description')
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $report = Wait-FailureReport 'Modifier la description'
        $reportText = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($reportText -notlike '✖ ORD-12 : *Droits insuffisants pour cette opération*') { $problems.Add("report says '$reportText'") }
        Close-Dialog $report 'dialog_cancel'
        if ((Get-ResultCell 'ORD-12' 2) -ne 'Aucune description') { $problems.Add("row shows '$(Get-ResultCell 'ORD-12' 2)'") }
    }
    Invoke-Check 'An emptied description is cleared in AD, the row and the filter' {
        param($problems)
        # ORD-08 (Laboratoire) isn't used by any other check. An empty description clears it: the row then holds no
        # description, shown as « Aucune description », and the filter box no longer finds the old one.
        Invoke-PrefixSearch 'ORD-0'
        $queriesBefore = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-08' $menuItems[0] 'Modifier la description' 'Description de ORD-08 :'
        (Get-DialogPart $dialog 'dialog_text').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $notice = Wait-ActionNotice 'Description modifiée : ✔ ORD-08'
        if ($notice -ne 'Description modifiée : ✔ ORD-08') { $problems.Add("the status bar says '$notice'") }
        $writes = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADComputer')
        if ($writes.Count -ne 1 -or $writes[0].Identity -ne 'CN=ORD-08,OU=Labo-Communs,OU=Postes,DC=demo,DC=local' -or $writes[0].Description -or $writes[0].Clear -ne 'Description') {
            $problems.Add("AD writes: $($writes | ConvertTo-Json -Compress)")
        }
        if ((Get-ResultCell 'ORD-08' 2) -ne 'Aucune description') { $problems.Add("row shows '$(Get-ResultCell 'ORD-08' 2)'") }
        try {
            Set-Text 'filter' 'laboratoire'
            if (@(Get-ResultName) -contains 'ORD-08') { $problems.Add("the filter still finds ORD-08 by its old description") }
        }
        finally {
            Set-Text 'filter' ''
        }
    }

    Invoke-PrefixSearch 'ORD-0'
    Invoke-Check 'Clés BitLocker after ID de clé BitLocker points out the key searched for, and only it' {
        param($problems)
        Select-SearchType 'ID de clé BitLocker'
        Set-Text 'search_term' 'A2E47C19'
        Invoke-Search
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem $menuItems[2]
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        $isBadge = [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'ID cherché')
        $badges = @($dialog.FindAll($Descendants, $isBadge))
        # On the 2024 key: the badge's key box is named after the key (computer | date | status | ID | password).
        $box = if ($badges.Count -eq 1) { $badges[0] }
        while ($box -and $box.Current.ControlType -ne [System.Windows.Automation.ControlType]::CheckBox) { $box = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($box) }
        if ($badges.Count -ne 1 -or -not $box -or $box.Current.Name -notlike '*| A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54 |*') {
            $problems.Add("$($badges.Count) « ID cherché » in the dialog, on: '$(if ($box) { $box.Current.Name })'")
        }
        Close-Dialog $dialog 'dialog_cancel'
        # Another search: no key pointed out any more.
        Invoke-PrefixSearch 'ORD-0'
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem $menuItems[2]
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        if (@($dialog.FindAll($Descendants, $isBadge)).Count) { $problems.Add('a key is still pointed out after another search') }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Clés BitLocker: no gap maximized or taller by hand, and the keys scroll in a small window' {
        param($problems)
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem $menuItems[2]
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        Test-DialogRoom $dialog 'bitlocker_scroll' 'bitlocker_key_0' $problems
        Close-Dialog $dialog 'dialog_cancel'
    }

    # ORD-09's keys: C:'s, replaced in January (the 2024 one left behind), and D:'s. The newest of each disk first.
    Invoke-Check 'Clés BitLocker lists the keys, and deletes the old one selected after a confirmation' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem $menuItems[2]
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        # Disk 1 (C:) first, its January key then the 2024 one, then disk 2 (D:).
        $rows = @(Get-BitLockerKeyRow $dialog)
        $expected = 'ORD-09 | 2026-01-15 à * | La plus récente | 6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61 | 418649-302104-655721-128930-583011-472560-090288-361757',
                    'ORD-09 | 2024-03-02 à * | Ancienne | A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54 | 207152-660011-394580-512237-081664-725903-466312-150898',
                    'ORD-09 | 2025-06-20 à * | La plus récente | C93B8E05-1F6A-4D27-A0B4-3E8F5C7D9A16 | 533841-102498-719620-284317-650650-097185-381194-626701'
        $listed = $rows.Count -eq 3
        for ($i = 0; $listed -and $i -lt 3; $i++) { $listed = $rows[$i] -like $expected[$i] }
        if (-not $listed) { $problems.Add("rows: $($rows -join ' // ')") }
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-4-cles-bitlocker' $dialog }
        Invoke-Element (Get-DialogPart $dialog 'bitlocker_select_old')
        Start-Sleep -Milliseconds 200
        $label = (Get-DialogPart $dialog 'bitlocker_delete_label').Current.Name
        if ($label -ne 'Supprimer la clé…') { $problems.Add("the delete button says '$label'") }
        Invoke-Element (Get-DialogPart $dialog 'bitlocker_delete')
        $confirm = Wait-OwnedDialog $dialog 'Supprimer des clés BitLocker'
        $text = Get-DialogText $confirm
        if ($text -notlike "Supprimer cette clé BitLocker de l'AD ?*A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54*" -or $text -like '*⚠*') { $problems.Add("the confirmation says: '$text'") }
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*').Count) { $problems.Add('a key was deleted before the confirmation') }
        Invoke-Element (Get-DialogPart $confirm 'dialog_ok')
        Start-Sleep -Milliseconds 400
        $notice = Wait-ActionNotice 'Clé supprimée : ✔ ORD-09 : clé A2E47C19'
        if ($notice -ne 'Clé supprimée : ✔ ORD-09 : clé A2E47C19') { $problems.Add("the status bar says '$notice'") }
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*' | ForEach-Object { "$($_.Command) $($_.Identity)" })
        if ($sent.Count -ne 1 -or $sent[0] -notlike 'Remove-ADObject CN=2024-03-02T11:05:00-05:00{A2E47C19-*},CN=ORD-09,*') { $problems.Add("removals: $($sent -join ' | ')") }
        $rows = @(Get-BitLockerKeyRow $dialog)
        if ($rows.Count -ne 2 -or ($rows -like '*A2E47C19*')) { $problems.Add("left: $($rows -join ' // ')") }
        if ((Get-DialogPart $dialog 'bitlocker_select_old').Current.IsEnabled) { $problems.Add('Sélectionner les anciennes is still enabled') }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check "Clés BitLocker warns before deleting a disk's newest key, and reports one it can't delete" {
        param($problems)
        Select-ResultRow 'ORD-07'
        Invoke-ResultMenuItem $menuItems[2]
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        $rows = @(Get-BitLockerKeyRow $dialog)
        if ($rows.Count -ne 1 -or $rows[0] -notlike 'ORD-07 | 2025-11-03 à * | La plus récente | 0D8B5F21-7A3C-4E9A-8C16-5B2E9F4A3D70 | non lisible (droits insuffisants)') { $problems.Add("rows: $($rows -join ' // ')") }
        $box = Get-DialogPart $dialog 'bitlocker_key_0'
        $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 200
        Invoke-Element (Get-DialogPart $dialog 'bitlocker_delete')
        $confirm = Wait-OwnedDialog $dialog 'Supprimer des clés BitLocker'
        if ((Get-DialogText $confirm) -notlike "*⚠ La sélection comprend la clé la plus récente d'un disque de ORD-07*") { $problems.Add("no warning: '$(Get-DialogText $confirm)'") }
        Invoke-Element (Get-DialogPart $confirm 'dialog_ok')
        Start-Sleep -Milliseconds 400
        $report = Wait-OwnedDialog $dialog 'Supprimer des clés BitLocker'
        $reportText = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($reportText -ne '✖ ORD-07 : clé 0D8B5F21 non supprimée (Accès refusé)') { $problems.Add("report says '$reportText'") }
        Invoke-Element (Get-DialogPart $report 'dialog_cancel')
        Start-Sleep -Milliseconds 400
        if (@(Get-BitLockerKeyRow $dialog).Count -ne 1) { $problems.Add('the key left the list') }
        Close-Dialog $dialog 'dialog_cancel'
    }

    # The fake AD's LAPS passwords, which expire a number of days from today: ORD-01 Windows LAPS, ORD-04 legacy LAPS,
    # ORD-12 legacy LAPS the user can't read, ORD-06 Windows LAPS encrypted for others, and ORD-02 none.
    Invoke-PrefixSearch 'ORD'
    $lapsExpiry = { param([int]$Days, [string]$Time) ((Get-Date).Date.AddDays($Days) + [timespan]$Time).ToString("yyyy-MM-dd 'à' HH 'h' mm", [cultureinfo]'fr-CA') }
    $lapsChecks = @(
        @{ Name = 'ORD-01'; Check = 'Mot de passe LAPS shows a Windows LAPS password, its account and expiration'; Password = 'Vq7#mR2t!xL9pW4z'
           Expected = "*ORD-01 — Windows LAPS, expire le $(& $lapsExpiry 18 '14:00')`n  Compte : Administrateur" }
        @{ Name = 'ORD-04'; Check = 'Mot de passe LAPS shows a legacy LAPS password'; Password = 'K3n$8vTq2Lm+Hd'
           Expected = "*ORD-04 — LAPS hérité, expire le $(& $lapsExpiry 9 '03:30')*" }
        @{ Name = 'ORD-12'; Check = "Mot de passe LAPS says when the password can't be read"
           Expected = "*ORD-12 — LAPS hérité, expire le $(& $lapsExpiry 21 '22:00')`n  Mot de passe : non lisible (droits insuffisants)" }
        @{ Name = 'ORD-06'; Check = "Mot de passe LAPS says when an encrypted password can't be decrypted"
           Expected = "*ORD-06 — Windows LAPS (chiffré), expire le $(& $lapsExpiry 5 '10:15')`n  Mot de passe : chiffré, non déchiffrable avec vos droits" }
    )
    foreach ($laps in $lapsChecks) {
        Invoke-Check $laps.Check {
            param($problems)
            $queriesBefore = @(Get-LoggedQuery).Count
            $dialog = Open-ActionDialog $laps.Name $menuItems[3] 'Mot de passe LAPS' $laps.Expected
            if ($ScreenshotDirectory -and $laps.Name -eq 'ORD-01') { Save-Screenshot 'menu-4-mot-de-passe-laps' $dialog }
            # Hidden, not even UI Automation reads the password; Afficher shows it.
            if ($laps['Password']) {
                if (@(Get-LapsSection $dialog)[0].Contains($laps.Password)) { $problems.Add('the hidden password is in the name of its card') }
                (Get-DialogPart $dialog 'laps_show_0').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                Start-Sleep -Milliseconds 200
                $shown = (Get-DialogPart $dialog 'laps_password_0').Current.Name
                if ($shown -ne $laps.Password) { $problems.Add("Afficher shows '$shown'") }
            }
            # The footer says the password isn't kept only when there's one.
            $status = Get-DialogPartName $dialog 'laps_status'
            $expectedStatus = if ($laps['Password']) { 'Ni enregistré ni journalisé.' } else { '' }
            if ($status -ne $expectedStatus) { $problems.Add("the footer says '$status'") }
            Close-Dialog $dialog 'dialog_cancel'
            $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
            $writes = @($calls | Where-Object Command -match '^(Set|Remove|Enable|Disable)-')
            if ($writes.Count) { $problems.Add("AD writes: $($writes | ConvertTo-Json -Compress)") }
            $windowsLaps = @($calls | Where-Object Command -eq 'Get-LapsADPassword')
            if ($windowsLaps.Count -ne 1 -or $windowsLaps[0].Domain -ne 'demo.local' -or -not $windowsLaps[0].AsPlainText -or $windowsLaps[0].Identity -notlike "CN=$($laps.Name),*") {
                $problems.Add("Get-LapsADPassword calls: $($windowsLaps | ConvertTo-Json -Compress)")
            }
        }
    }

    Invoke-Check 'Mot de passe LAPS says when there is none, in a toast rather than a window' {
        param($problems)
        Select-ResultRow 'ORD-02'
        Invoke-ResultMenuItem $menuItems[3]
        $notice = Wait-ActionNotice 'Mot de passe LAPS : ORD-02 : aucun mot de passe LAPS'
        if ($notice -ne 'Mot de passe LAPS : ORD-02 : aucun mot de passe LAPS') { $problems.Add("the toast says '$notice'") }
        if (@(Get-AppWindow | Where-Object { Get-DialogPart $_ 'dialog_cancel' }).Count) { $problems.Add('a window opened') }
    }

    Invoke-Check 'Mot de passe LAPS: several computers, a card each' {
        param($problems)
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-02'
        Add-ResultRow 'ORD-06'
        Invoke-ResultMenuItem $menuItems[3]
        $dialog = Wait-Dialog 'Mot de passe LAPS'
        Start-Sleep -Milliseconds 300
        $sections = @(Get-LapsSection $dialog | ForEach-Object { ($_ -split "`r?`n")[0] })
        $expected = "ORD-01 — Windows LAPS, expire le $(& $lapsExpiry 18 '14:00')", 'ORD-02 : aucun mot de passe LAPS', "ORD-06 — Windows LAPS (chiffré), expire le $(& $lapsExpiry 5 '10:15')"
        if ((@($sections | Sort-Object) -join ' | ') -ne (@($expected | Sort-Object) -join ' | ')) { $problems.Add("the sections are: $($sections -join ' | ')") }
        Close-Dialog $dialog 'dialog_cancel'
        Select-ResultRow 'ORD-02'
    }

    Invoke-Check 'Mot de passe LAPS: no gap maximized or taller by hand, and the card scrolls in a small window' {
        param($problems)
        Select-ResultRow 'ORD-01'
        Invoke-ResultMenuItem $menuItems[3]
        $dialog = Wait-Dialog 'Mot de passe LAPS'
        Start-Sleep -Milliseconds 300
        Test-DialogRoom $dialog 'laps_scroll' 'laps_section_0' $problems
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Mot de passe LAPS: more cards than the screen holds stay on it, and scroll' {
        param($problems)
        $names = @(Get-ResultRow | ForEach-Object { $_[1] })
        Select-ResultRow $names[0]
        foreach ($name in $names | Select-Object -Skip 1) { Add-ResultRow $name }
        Invoke-ResultMenuItem $menuItems[3]
        $dialog = Wait-Dialog 'Mot de passe LAPS'
        Start-Sleep -Milliseconds 1000
        $screen = $AE::RootElement.Current.BoundingRectangle
        $box = $dialog.Current.BoundingRectangle
        if ($box.Top -lt $screen.Top -or $box.Bottom -gt $screen.Bottom) { $problems.Add("with $($names.Count) cards, the window goes from $($box.Top) to $($box.Bottom) on a screen of $($screen.Height)") }
        $scroll = (Get-DialogPart $dialog 'laps_scroll').GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
        if (-not $scroll.Current.VerticallyScrollable) { $problems.Add("with $($names.Count) cards, there's no scroll bar") }
        Close-Dialog $dialog 'dialog_cancel'
        Select-ResultRow 'ORD-02'
    }

    Invoke-PrefixSearch 'ORD-0'
    Invoke-Check 'Supprimer: Enter picks Annuler, the default button' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-02' $menuItems[6] "Supprimer de l'AD" "Supprimer ORD-02 de l'AD ?*"
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-2-supprimer-confirmation' $dialog }
        Send-Key 0x0D $dialog
        Wait-DialogsClosed
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*').Count) { $problems.Add('Enter removed the computer') }
        if ($null -eq (Get-ResultCell 'ORD-02' 1)) { $problems.Add('ORD-02 left the grid') }
    }

    $removals = @(
        # Calls: the removals expected, in order. The computer first; AD refuses it while it holds objects, so its
        # BitLocker objects go then (ORD-09's two left: its old one was deleted by Clés BitLocker), without -Recursive,
        # and the computer after. Nothing at all is removed from a protected computer, not even its BitLocker object.
        @{ Name = 'ORD-02'; Report = "Supprimé de l'AD : ✔ ORD-02"; Count = '8 ordinateurs'; Removed = $true
           Calls = 'Remove-ADComputer CN=ORD-02,*' }
        @{ Name = 'ORD-09'; Report = "Supprimé de l'AD : ✔ ORD-09 (avec 2 objets enfants)"; Count = '7 ordinateurs'; Removed = $true
           KeysShown = '*ID 6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61*418649-302104-655721-128930-583011-472560-090288-361757*'
           Calls = 'Remove-ADComputer CN=ORD-09,*', 'Remove-ADObject CN=2026-01-15T09:30:00*,CN=ORD-09,*', 'Remove-ADObject CN=2025-06-20T16:40:00*,CN=ORD-09,*', 'Remove-ADComputer CN=ORD-09,*' }
        @{ Name = 'ORD-07'; Report = '✖ ORD-07 : protégé contre la suppression accidentelle, non supprimé'; Count = '7 ordinateurs'; Removed = $false
           Calls = @() }
    )
    foreach ($removal in $removals) {
        Invoke-Check "Supprimer de l'AD: $($removal.Report)" {
            param($problems)
            $queriesBefore = @(Get-LoggedQuery).Count
            $dialog = Open-ActionDialog $removal.Name $menuItems[6] "Supprimer de l'AD" "Supprimer $($removal.Name) de l'AD ?*"
            if ($removal.KeysShown -and (Get-DialogText $dialog) -notlike $removal.KeysShown) { $problems.Add("the confirmation doesn't show the BitLocker key: '$(Get-DialogText $dialog)'") }
            (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            if ($removal.Removed) {
                # Removed: said in the status bar, without a window.
                Wait-DialogsClosed
                $reportText = Wait-ActionNotice $removal.Report
                if (Test-ReportShown) { $problems.Add('a report window opened') }
            }
            else {
                $report = Wait-FailureReport "Supprimer de l'AD"
                $reportText = (Get-DialogPart $report 'dialog_message').Current.Name
                if ($ScreenshotDirectory) { Save-Screenshot 'menu-3-supprimer-echec' $report }
                Close-Dialog $report 'dialog_cancel'
            }
            if ($reportText -ne $removal.Report) { $problems.Add("report says '$reportText', expected '$($removal.Report)'") }
            $removeCalls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*')
            $sent = @($removeCalls | ForEach-Object { "$($_.Command) $($_.Identity)" })
            if ($removeCalls | Where-Object Recursive) { $problems.Add('a removal used -Recursive') }
            $expected = @($removal.Calls)
            $inOrder = $sent.Count -eq $expected.Count
            for ($i = 0; $inOrder -and $i -lt $sent.Count; $i++) { $inOrder = $sent[$i] -like $expected[$i] }
            if (-not $inOrder) { $problems.Add("removals: $($sent -join ' | '); expected: $($expected -join ' | ')") }
            $stillShown = $null -ne (Get-ResultCell $removal.Name 1)
            if ($stillShown -eq $removal.Removed) { $problems.Add("still in the grid: $stillShown") }
            $label = (Find-Control 'results_count').Current.Name
            if ($label -ne $removal.Count) { $problems.Add("label is '$label', expected '$($removal.Count)'") }
        }
    }

    Invoke-Check 'A new search no longer finds the removed computers' {
        param($problems)
        Invoke-PrefixSearch 'ORD'
        $label = (Find-Control 'results_count').Current.Name
        if ($label -ne '10 ordinateurs') { $problems.Add("label is '$label', expected '10 ordinateurs' (12 minus ORD-02 and ORD-09)") }
    }

    Invoke-Check "Supprimer de l'AD: refused for its rights, a computer keeps what it holds" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-12' $menuItems[6] "Supprimer de l'AD" "Supprimer ORD-12 de l'AD ?*"
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $report = Wait-FailureReport "Supprimer de l'AD"
        $reportText = (Get-DialogPart $report 'dialog_message').Current.Name
        Close-Dialog $report 'dialog_cancel'
        if ($reportText -notlike '✖ ORD-12 : *Droits insuffisants pour cette opération*') { $problems.Add("report says '$reportText'") }
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*' | ForEach-Object { "$($_.Command) $($_.Identity)" })
        if ($sent.Count -ne 1 -or $sent[0] -notlike 'Remove-ADComputer CN=ORD-12,*') { $problems.Add("removals: $($sent -join ' | ')") }
    }

    # ORD-06 and ORD-10 ("Salle ..."), both enabled. With ORD-10 disabled, Activer is greyed out for ORD-06, so if
    # the wrong row gets selected, Activer (which has no confirmation) can't run on it.
    $ord10DN = 'CN=ORD-10,OU=Postes,DC=demo,DC=local'
    Invoke-PrefixSearch '' 'salle'

    Invoke-Check 'Désactiver: greyed out Activer, and Enter picks Annuler' {
        param($problems)
        $states = Get-MenuItemState 'ORD-10'
        if ($states[$menuItems[4]] -or -not $states[$menuItems[5]]) { $problems.Add("for an enabled computer, Activer is $($states[$menuItems[4]]) and Désactiver is $($states[$menuItems[5]])") }
        $queriesBefore = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-10' $menuItems[5] 'Désactiver' 'Désactiver ORD-10 ?*'
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-5-desactiver-confirmation' $dialog }
        Send-Key 0x0D $dialog
        Wait-DialogsClosed
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*-ADAccount') { $problems.Add('Enter changed the account') }
        if ((Get-ResultCell 'ORD-10' 0) -ne 'Activé') { $problems.Add("ORD-10 shows '$(Get-ResultCell 'ORD-10' 0)'") }
    }

    Invoke-Check 'Désactiver disables the computer and updates its row' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-10' $menuItems[5] 'Désactiver' 'Désactiver ORD-10 ?*'
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $notice = Wait-ActionNotice 'Désactivé : ✔ ORD-10'
        if ($notice -ne 'Désactivé : ✔ ORD-10') { $problems.Add("the status bar says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report window opened') }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*-ADAccount')
        if ($calls.Count -ne 1 -or $calls[0].Command -ne 'Disable-ADAccount' -or $calls[0].Identity -ne $ord10DN -or $calls[0].Server -ne 'demo.local') {
            $problems.Add("account changes: $($calls | ConvertTo-Json -Compress)")
        }
        if ((Get-ResultCell 'ORD-10' 0) -ne 'Désactivé') { $problems.Add("ORD-10 shows '$(Get-ResultCell 'ORD-10' 0)'") }
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer').Count) { $problems.Add('the grid was refreshed with a new search') }
        $states = Get-MenuItemState 'ORD-10'
        if (-not $states[$menuItems[4]] -or $states[$menuItems[5]]) { $problems.Add("for a disabled computer, Activer is $($states[$menuItems[4]]) and Désactiver is $($states[$menuItems[5]])") }
    }

    Invoke-Check 'Activer enables the computer, without confirmation' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-10'
        Invoke-ResultMenuItem $menuItems[4]
        $notice = Wait-ActionNotice 'Activé : ✔ ORD-10'
        if ($notice -ne 'Activé : ✔ ORD-10') { $problems.Add("the status bar says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report window opened') }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*-ADAccount')
        if ($calls.Count -ne 1 -or $calls[0].Command -ne 'Enable-ADAccount' -or $calls[0].Identity -ne $ord10DN -or $calls[0].Server -ne 'demo.local') {
            $problems.Add("account changes: $($calls | ConvertTo-Json -Compress)")
        }
        if ((Get-ResultCell 'ORD-10' 0) -ne 'Activé') { $problems.Add("ORD-10 shows '$(Get-ResultCell 'ORD-10' 0)'") }
    }

    Invoke-Check 'A failed Désactiver is reported and the row stays enabled' {
        param($problems)
        Invoke-PrefixSearch 'ORD-1'
        $dialog = Open-ActionDialog 'ORD-12' $menuItems[5] 'Désactiver' 'Désactiver ORD-12 ?*'
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $report = Wait-FailureReport 'Désactiver'
        $reportText = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($reportText -notlike '✖ ORD-12 : *Droits insuffisants pour cette opération*') { $problems.Add("report says '$reportText'") }
        Close-Dialog $report 'dialog_cancel'
        if ((Get-ResultCell 'ORD-12' 0) -ne 'Activé') { $problems.Add("ORD-12 shows '$(Get-ResultCell 'ORD-12' 0)'") }
    }

    Test-RemoteActions $menuItems

    Invoke-Check "Actions on another domain's computer go to that domain" {
        param($problems)
        # nord.demo.local's ORD-01 has the same name as demo.local's. Without -Server, the fake AD (like the
        # real one) only looks in demo.local and doesn't find it.
        $nordDN = 'CN=ORD-01,OU=Postes,DC=nord,DC=demo,DC=local'
        Select-Domain 'nord.demo.local'
        Select-SearchType 'Description contient'
        Reset-AdvancedSearch
        Set-Text 'prefix' ''
        Set-Text 'search_term' 'nord'
        Invoke-Search
        $queriesBefore = @(Get-LoggedQuery).Count

        $dialog = Open-ActionDialog 'ORD-01' $menuItems[0] 'Modifier la description' 'Description de ORD-01 :'
        $textBox = (Get-DialogPart $dialog 'dialog_text').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($textBox.Current.Value -ne 'Accueil Nord') { $problems.Add("text box holds '$($textBox.Current.Value)', expected nord's ORD-01 description") }
        $textBox.SetValue('Accueil Nord modifié')
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $notice = Wait-ActionNotice 'Description modifiée : ✔ ORD-01'
        if ($notice -ne 'Description modifiée : ✔ ORD-01') { $problems.Add("the edit notice says '$notice'") }

        $dialog = Open-ActionDialog 'ORD-01' $menuItems[5] 'Désactiver' 'Désactiver ORD-01 ?*'
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $notice = Wait-ActionNotice 'Désactivé : ✔ ORD-01'
        if ($notice -ne 'Désactivé : ✔ ORD-01') { $problems.Add("the disable notice says '$notice'") }

        # nord's ORD-01 has its own LAPS password, encrypted for the user, who can decrypt it.
        $dialog = Open-ActionDialog 'ORD-01' $menuItems[3] 'Mot de passe LAPS' '*ORD-01 — Windows LAPS, expire le *'
        Close-Dialog $dialog 'dialog_cancel'

        $dialog = Open-ActionDialog 'ORD-01' $menuItems[6] "Supprimer de l'AD" "Supprimer ORD-01 de l'AD ?*"
        if ((Get-DialogText $dialog) -notlike '*ORD-01 : aucune clé BitLocker*') { $problems.Add("the confirmation shows: '$(Get-DialogText $dialog)'") }
        (Get-DialogPart $dialog 'dialog_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $notice = Wait-ActionNotice "Supprimé de l'AD : ✔ ORD-01"
        if ($notice -ne "Supprimé de l'AD : ✔ ORD-01") { $problems.Add("the removal notice says '$notice'") }

        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
        # Get-LapsADPassword names the domain with -Domain rather than -Server.
        foreach ($call in $calls | Where-Object { "$($_.Server)$($_.Domain)" -ne 'nord.demo.local' }) {
            $problems.Add("$($call.Command) $($call.Identity)$($call.SearchBase) sent to '$($call.Server)$($call.Domain)', expected nord.demo.local")
        }
        foreach ($command in 'Set-ADComputer', 'Disable-ADAccount', 'Get-LapsADPassword', 'Remove-ADComputer') {
            $sent = @($calls | Where-Object Command -eq $command | ForEach-Object Identity)
            if (($sent -join ' | ') -ne $nordDN) { $problems.Add("$command sent for: $($sent -join ' | '); expected $nordDN") }
        }

        # demo.local's ORD-01 kept the description set earlier.
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-01'
        if ((Get-ResultCell 'ORD-01' 2) -ne 'Accueil principal') { $problems.Add("demo.local's ORD-01 shows '$(Get-ResultCell 'ORD-01' 2)'") }
    }
}

function Test-RemoteActions([string[]]$MenuItems) {
    # The remote actions, which Actions runs after the rest of the right-click menu, and Remote alone ($MenuItems: the
    # menu's items, Test-ResultMenu's). ORD-01, ORD-03, ORD-04 and ORD-06 are enabled, so Activer (no confirmation)
    # can't run on them by accident. The fake AD's Test-Connection: ord-01 and ord-08 answer ping, ord-04 only port
    # 3389, the others nothing. Its DNS: each name gives its address (ord-01 an IPv6 one too, not shown), except ORD-03,
    # which has no DNS name. ORD-06 is offline, but its name still gives an address.
    Invoke-PrefixSearch 'ORD-0'
    $offline = 'hors ligne (pas de réponse au ping ni aux ports 445 et 3389)'
    # Vérifier en ligne fills the En ligne column (hidden until then, the last one: cell 7) and says so in the status bar.
    $onlineChecks = @(
        @{ Name = 'ORD-01'; Cell = '✔ 10.0.1.11'; Notice = 'En ligne : ✔ ORD-01 : en ligne (ping) — 10.0.1.11' }
        @{ Name = 'ORD-04'; Cell = '✔ 10.0.1.14'; Notice = 'En ligne : ✔ ORD-04 : en ligne (port 3389) — 10.0.1.14' }
        @{ Name = 'ORD-06'; Cell = '✖ 10.0.1.16'; Notice = "Hors ligne : ✖ ORD-06 : $offline — 10.0.1.16" }
        @{ Name = 'ORD-03'; Cell = '✖ nom DNS introuvable'; Notice = "Hors ligne : ✖ ORD-03 : $offline — nom DNS introuvable" }
    )
    Invoke-Check 'Vérifier en ligne: the En ligne column is hidden until then' {
        param($problems)
        $headers = Get-ColumnHeader
        if ($headers -like '*En ligne*') { $problems.Add("columns are: $headers") }
    }
    foreach ($online in $onlineChecks) {
        Invoke-Check "Vérifier en ligne: $($online.Name) shows $($online.Cell) in the En ligne column" {
            param($problems)
            Select-ResultRow $online.Name
            Invoke-ResultMenuItem $menuItems[7]
            $cell = $null
            for ($i = 0; $i -lt 30; $i++) {
                # The rows are redrawn as the answers come: the grid can be missing from UI Automation for a moment.
                $cell = try { Get-ResultCell $online.Name 7 } catch { $null }
                if ($cell -and $cell -ne '…') { break }
                Start-Sleep -Milliseconds 150
            }
            if ($cell -ne $online.Cell) { $problems.Add("the cell says '$cell'") }
            $notice = Wait-ActionNotice $online.Notice
            if ($notice -ne $online.Notice) { $problems.Add("the status bar says '$notice'") }
            if (Test-ReportShown) { $problems.Add('a window opened') }
            if ($ScreenshotDirectory -and $online.Name -eq 'ORD-04') { Save-Screenshot 'menu-6-verifier-en-ligne' }
        }
    }

    Invoke-Check 'Vérifier en ligne: several computers, each in its row, and a count in the status bar' {
        param($problems)
        Invoke-PrefixSearch 'ORD-0'
        if ((Get-ResultCell 'ORD-01' 7)) { $problems.Add("after a new search, ORD-01's cell says '$(Get-ResultCell 'ORD-01' 7)'") }
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-03'
        Add-ResultRow 'ORD-06'
        Invoke-ResultMenuItem $menuItems[7]
        $notice = Wait-ActionNotice '1 en ligne sur 3 : Hors ligne : ORD-03, ORD-06'
        if ($notice -ne '1 en ligne sur 3 : Hors ligne : ORD-03, ORD-06') { $problems.Add("the status bar says '$notice'") }
        $cells = "$(Get-ResultCell 'ORD-01' 7) | $(Get-ResultCell 'ORD-03' 7) | $(Get-ResultCell 'ORD-06' 7) | $(Get-ResultCell 'ORD-04' 7)"
        if ($cells -ne '✔ 10.0.1.11 | ✖ nom DNS introuvable | ✖ 10.0.1.16 | ') { $problems.Add("cells: $cells") }
        # Back to a single selection: selecting a row that's already selected doesn't unselect the others.
        Select-ResultRow 'ORD-04'
    }

    # With the fake AD nothing is started: the dialog shows the command, with the DNS name (or the name without one).
    $remoteChecks = @(
        @{ Name = 'ORD-01'; Item = 9; Title = 'Bureau à distance'; Command = 'mstsc.exe /v:ord-01.demo.local' }
        @{ Name = 'ORD-01'; Item = 10; Title = "Gestion de l'ordinateur"; Command = 'compmgmt.msc /computer=ord-01.demo.local' }
        @{ Name = 'ORD-01'; Item = 11; Title = 'Ouvrir C$'; Command = 'explorer.exe \\ord-01.demo.local\c$' }
        @{ Name = 'ORD-03'; Item = 9; Title = 'Bureau à distance'; Command = 'mstsc.exe /v:ORD-03' }
        # ORD-01 answers on WinRM: the terminal opens at once.
        @{ Name = 'ORD-01'; Item = 12; Title = 'PowerShell à distance'; Command = '*pwsh*-NoExit -Command "Enter-PSSession -ComputerName ord-01.demo.local"' }
        @{ Name = 'ORD-01'; Item = 13; Title = 'Services'; Command = 'services.msc /computer=ord-01.demo.local' }
        @{ Name = 'ORD-01'; Item = 14; Title = "Observateur d'événements"; Command = 'eventvwr.exe ord-01.demo.local' }
        @{ Name = 'ORD-01'; Item = 16; Title = 'Annuler le redémarrage'; Command = 'shutdown.exe /a /m \\ord-01.demo.local' }
    )
    foreach ($remote in $remoteChecks) {
        Invoke-Check "$($remote.Title) for $($remote.Name) runs $($remote.Command)" {
            $dialog = Open-ActionDialog $remote.Name $menuItems[$remote.Item] $remote.Title "AD fictif : rien n'est lancé.*$($remote.Command)"
            Close-Dialog $dialog 'dialog_cancel'
        }
    }

    # Forcer les stratégies and PowerShell à distance on a computer without WinRM go through scheduled tasks, which the
    # fake AD runs at once: each is registered to run as SYSTEM, started, then deleted.
    Invoke-Check 'Forcer les stratégies says it runs, runs gpupdate through a scheduled task, then deletes it' {
        param($problems)
        $before = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-01'
        # The task takes half a second at least (Invoke-RemoteTask's wait): « en cours… » shows meanwhile.
        Invoke-ResultMenuItem $menuItems[17]
        $running = Wait-ActionNotice 'Forcer les stratégies : ORD-01 : en cours…'
        if ($running -ne 'Forcer les stratégies : ORD-01 : en cours…') { $problems.Add("after the click, the status bar says '$running'") }
        $expected = "Forcer les stratégies : ✔ ORD-01 : stratégies de l'ordinateur à jour"
        $notice = ''
        for ($i = 0; $i -lt 4 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the status bar says '$notice'") }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $before | Where-Object { $_.Command -like '*ScheduledTask' -or $_.Command -eq 'Remove-CimInstance' })
        $register = @($calls | Where-Object Command -eq 'Register-ScheduledTask')
        if ($register.Count -ne 1 -or $register[0].Arguments -ne '/target:computer /force /wait:120' -or $register[0].UserId -ne 'S-1-5-18' -or $register[0].Server -ne 'ord-01.demo.local') {
            $problems.Add("registered: $($register | ConvertTo-Json -Compress)")
        }
        if (($calls.Command -join ', ') -ne 'Register-ScheduledTask, Start-ScheduledTask, Remove-CimInstance') { $problems.Add("task calls: $($calls.Command -join ', ')") }
    }

    Invoke-Check 'Forcer les stratégies on a computer that answers neither WinRM nor DCOM says so in a toast' {
        param($problems)
        Select-ResultRow 'ORD-06'
        Invoke-ResultMenuItem $menuItems[17]
        $expected = 'Forcer les stratégies : ✖ ORD-06 : injoignable (ni WinRM ni DCOM ne répondent : ordinateur éteint, ou pare-feu)'
        $notice = ''
        for ($i = 0; $i -lt 4 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the toast says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report opened') }
    }

    Invoke-Check 'PowerShell à distance on ORD-04, without WinRM, turns it on after a confirmation and puts it back after' {
        param($problems)
        $before = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-04' $menuItems[12] 'PowerShell à distance' "WinRM n'est pas activé sur ORD-04*à la fermeture du terminal*"
        Close-Dialog $dialog 'dialog_ok'
        # The terminal, once WinRM is on; closing its dialog stands for closing the terminal.
        $terminal = $null
        for ($i = 0; $i -lt 4 -and -not $terminal; $i++) { $terminal = Wait-AnyDialog }
        $text = if ($terminal) { Get-DialogText $terminal } else { '' }
        if ($text -notlike "AD fictif : rien n'est lancé.*-NoExit -Command `"Enter-PSSession -ComputerName ord-04.demo.local`"") { $problems.Add("the terminal's dialog says '$text'") }
        if ($terminal) { Close-Dialog $terminal 'dialog_cancel' }
        $expected = 'PowerShell à distance : ✔ ORD-04 : WinRM remis comme avant'
        $notice = ''
        for ($i = 0; $i -lt 4 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the status bar says '$notice'") }

        # The task that puts WinRM back first, on a timer and at startup; then the one that turns it on, only for this
        # computer's addresses; then, once the terminal closed, the first one runs (and deletes itself). The task and
        # the firewall rule are named after the technician.
        $name = 'Repere-WinRM-' + ($env:USERNAME -replace '[^A-Za-z0-9._-]', '_')
        $calls = @(Get-LoggedQuery | Select-Object -Skip $before | Where-Object { $_.Command -like '*ScheduledTask' -or $_.Command -eq 'Remove-CimInstance' })
        $restore = @($calls | Where-Object { $_.Command -eq 'Register-ScheduledTask' -and $_.TaskName -eq $name })
        if ($restore.Count -ne 1 -or ($restore[0].Triggers -join ',') -ne 'Once,Boot' -or $restore[0].Arguments -notlike "*firewall delete rule name=$name *net.exe stop WinRM*schtasks.exe /Delete /TN \$name /F)") {
            $problems.Add("the restoring task: $($restore | ConvertTo-Json -Compress)")
        }
        $enable = @($calls | Where-Object { $_.Command -eq 'Register-ScheduledTask' -and $_.TaskName -like 'Repere-WinRM-on-*' })
        if ($enable.Count -ne 1 -or $enable[0].Arguments -notlike "/c net.exe start WinRM && *winrm.vbs create winrm/config/Listener?Address=``*+Transport=HTTP && netsh.exe advfirewall firewall add rule name=$name *localport=5985*remoteip=*") {
            $problems.Add("the enabling task: $($enable | ConvertTo-Json -Compress)")
        }
        $order = ($calls | ForEach-Object { "$($_.Command) $($_.TaskName -replace '-on-\w+$', '-on')" }) -join ', '
        if ($order -ne "Register-ScheduledTask $name, Register-ScheduledTask Repere-WinRM-on, Start-ScheduledTask Repere-WinRM-on, Remove-CimInstance Repere-WinRM-on, Start-ScheduledTask $name") {
            $problems.Add("task calls: $order")
        }
    }

    Invoke-Check 'PowerShell à distance on ORD-04 again asks again: WinRM was put back' {
        $dialog = Open-ActionDialog 'ORD-04' $menuItems[12] 'PowerShell à distance' "WinRM n'est pas activé sur ORD-04*"
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'PowerShell à distance on a computer that answers neither ping, WinRM nor DCOM says so in a toast' {
        param($problems)
        Select-ResultRow 'ORD-06'
        Invoke-ResultMenuItem $menuItems[12]
        $expected = 'PowerShell à distance : ✖ ORD-06 : hors ligne (pas de réponse au ping, ni à WinRM ni à DCOM)'
        $notice = ''
        for ($i = 0; $i -lt 4 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the toast says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report opened') }
    }

    Invoke-Check 'PowerShell à distance on ORD-08, which answers ping only, offers to turn WinRM on' {
        $dialog = Open-ActionDialog 'ORD-08' $menuItems[12] 'PowerShell à distance' 'ORD-08 répond au ping, mais pas à Repère*un pare-feu*à la fermeture du terminal*'
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-WinRMEnableError([string]$MenuItem) {
    # Activer WinRM when a step fails once WinRM is on ($env:REPERE_FAKEAD_WINRM_ON_ERROR, #316): Repère asks WinRM, and
    # goes on when it answers, as a second click did. When it doesn't, the failure is said, as before. $MenuItem:
    # PowerShell à distance.
    Invoke-PrefixSearch 'ORD-0'
    Invoke-Check 'Activer WinRM on ORD-04, which fails once WinRM is on, opens the terminal all the same' {
        param($problems)
        $dialog = Open-ActionDialog 'ORD-04' $MenuItem 'PowerShell à distance' "WinRM n'est pas activé sur ORD-04*"
        Close-Dialog $dialog 'dialog_ok'
        # From the click until the terminal opens (slowed by $env:REPERE_FAKEAD_SPECS_DELAY), the bar says it's under way.
        $running = 'PowerShell à distance : ORD-04 : activation de WinRM…'
        $notice = Wait-ActionNotice $running
        if ($notice -ne $running) { $problems.Add("while WinRM is turned on, the status bar says '$notice'") }
        $terminal = $null
        for ($i = 0; $i -lt 8 -and -not $terminal; $i++) { $terminal = Wait-AnyDialog }
        $text = if ($terminal) { Get-DialogText $terminal } else { '' }
        if ($text -notlike "AD fictif : rien n'est lancé.*Enter-PSSession -ComputerName ord-04.demo.local*") { $problems.Add("instead of the terminal: '$text'") }
        $shown = Find-ShownControl 'action_notice'
        if ($shown -and $shown.Current.Name -eq $running) { $problems.Add('the notice still says WinRM is being turned on') }
        if ($terminal) { Close-Dialog $terminal 'dialog_cancel' }
        # Still put back once the terminal closes.
        $expected = 'PowerShell à distance : ✔ ORD-04 : WinRM remis comme avant'
        $notice = ''
        for ($i = 0; $i -lt 4 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the status bar says '$notice'") }
    }

    Invoke-Check 'Activer WinRM on ORD-08, where WinRM still does not answer, says it failed' {
        param($problems)
        $dialog = Open-ActionDialog 'ORD-08' $MenuItem 'PowerShell à distance' 'ORD-08 répond au ping, mais pas à Repère*'
        Close-Dialog $dialog 'dialog_ok'
        $report = Wait-FailureReport 'PowerShell à distance'
        $text = Get-DialogText $report
        if ($text -notlike '✖ ORD-08 : WinRM non activé (*') { $problems.Add("the report says '$text'") }
        Close-Dialog $report 'dialog_cancel'
    }
}

function Test-WinRMPromptFit([string]$MenuItem) {
    # The prompts to turn WinRM on, at a larger text size: each button within the dialog, beside the next one. The one
    # of Caractéristiques has three (Activer WinRM, Lire par DCOM, Annuler), which no longer fitted at Grande. Verdana,
    # in bold, is wider than Segoe UI. Repère starts again for each, apparence.json removed after.
    $sizes = @{ Settings = '{ "TextScale": 1.15 }'; Name = 'Grande' }, @{ Settings = '{ "TextScale": 1.3, "FontFamily": "Verdana", "FontWeight": "Bold" }'; Name = 'Très grande, Verdana gras' }
    foreach ($size in $sizes) {
        Restart-App $size.Settings
        Invoke-PrefixSearch 'ORD-0'
        $prompts = @{ Name = 'ORD-04'; Item = $MenuItem; Title = 'PowerShell à distance'; Expected = "WinRM n'est pas activé sur ORD-04*"; Buttons = 'dialog_ok', 'dialog_cancel' },
                   @{ Name = 'ORD-08'; Item = 'Caractéristiques…'; Title = 'Caractéristiques'; Expected = 'ORD-08 répond au ping, mais pas à Repère*'; Buttons = 'dialog_ok', 'dialog_alt', 'dialog_cancel' }
        foreach ($prompt in $prompts) {
            Invoke-Check "$($prompt.Title) on $($prompt.Name), at $($size.Name): the buttons of the prompt to turn WinRM on fit in it" {
                param($problems)
                $dialog = Open-ActionDialog $prompt.Name $prompt.Item $prompt.Title $prompt.Expected
                try {
                    $box = $dialog.Current.BoundingRectangle
                    $right = $null
                    foreach ($id in $prompt.Buttons) {
                        $rect = (Get-DialogPart $dialog $id).Current.BoundingRectangle
                        if ($rect.Left -lt $box.Left + 8 -or $rect.Right -gt $box.Right - 8) { $problems.Add("$id spans $($rect.Left)-$($rect.Right), the dialog $($box.Left)-$($box.Right)") }
                        if ($null -ne $right -and $rect.Left -lt $right) { $problems.Add("$id overlaps the button before it") }
                        $right = $rect.Right
                    }
                    if ($ScreenshotDirectory) { Save-Screenshot "winrm-prompt-$($prompt.Name)-$($size.Settings.Length)" $dialog }
                }
                finally { Close-Dialog $dialog 'dialog_cancel' }
            }
        }
    }
    Remove-Item $appearanceFile -ErrorAction SilentlyContinue
}

function Wait-SpecsWindow([string]$Name) {
    # The Caractéristiques window of a computer (owned by the main one), once its reading has ended.
    $specsWindow = Wait-Dialog "Caractéristiques — $Name"
    $status = Get-DialogPart $specsWindow 'spec_status'
    for ($i = 0; $i -lt 120 -and $status.Current.Name -notmatch '^(Lu en|Échec|Lecture annulée)'; $i++) { Start-Sleep -Milliseconds 250 }
    $specsWindow
}

function Get-SpecsValue($SpecsWindow, [string]$AutomationId) {
    # A value of the window (a read-only text box), or $null when it isn't shown.
    $part = Get-DialogPart $SpecsWindow $AutomationId
    if ($part) { $part.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
}

function Close-SpecsWindow($SpecsWindow) {
    $title = $SpecsWindow.Current.Name
    $SpecsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    for ($i = 0; $i -lt 20 -and @(Get-AppWindow | Where-Object { $_.Current.Name -eq $title }).Count; $i++) { Start-Sleep -Milliseconds 250 }
}

function Test-SpecsWindow {
    # The fake AD's network: ord-01 answers over WinRM (a docked laptop with three alerts and three monitors, whose
    # software is read in one call), ord-04 over DCOM only, its WinRM port closed (a kiosk without brand, with no battery
    # and old Windows, whose adapters and storage can't be read, so the older classes are used; its software read value
    # by value). ORD-06 doesn't answer, and ORD-03's name isn't in the DNS. Timing: what the status's tooltip says.
    # The window opens only once the computer answers: ORD-04 first offers to turn WinRM on (Prompt; Lire par DCOM
    # here), and ORD-06 and ORD-03 say why in a warning, without a window (Report: its heading, then its line).
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'
    $specsChecks = @(
        @{ Name = 'ORD-01'; Via = 'menu'; Status = 'Lu en * s · 3 alertes'
           Timing = 'Connexion : * ms (WinRM)', 'Général : * ms', 'Logiciels : * ms (en un appel WinRM)'
           Subtitle = 'ord-01.demo.local · * · lu le *'
           Values = [ordered]@{
               spec_General_ComputerName = 'ORD-01'; spec_General_Manufacturer = 'Dell Inc.'; spec_General_Model = 'Latitude 5440'
               spec_General_SerialNumber = '7H2KQ54'; spec_General_LoggedOnUser = 'DEMO\accueil'; spec_General_OSName = 'Windows 11 Professionnel'
               spec_General_BuildNumber = '10.0.26200 (build 26200)'; spec_General_LastBoot = '* (il y a 20 j *'
               spec_Network_IPAddress = '10.0.1.11*172.20.48.1 (vEthernet (Default Switch))'; spec_Network_LinkType = 'Wi-Fi · 1,2 Gbit/s'
               spec_Network_FQDN = 'ORD-01.demo.local'; spec_Processor_Name = '13th Gen Intel Core i5-1345U'; spec_Processor_Cores = '10 / 12'; spec_Memory_Total = '16 Go'; spec_Memory_Type = 'DDR5'
               spec_Memory_Physical = '2 × 8,0 Go'; spec_Memory_Maker = 'Samsung'; spec_Memory_Part = 'M425R1GB4BB0-CWM'; vol_C = '* (86 %)'; spec_Battery_Health = '62 %*'; spec_Battery_Cycles = '412'
               # Its own screen first, then the Dell and the Samsung; not the LG, no longer connected.
               spec_Monitor_Count = '3 écrans'; mon_1_Manufacturer = 'AU Optronics'; mon_1_Serial = 'N/D'; mon_1_Size = '≈ 14 po (31 × 17 cm)'
               mon_1_Resolution = '1920 × 1200'; mon_2_Manufacturer = 'Dell'; mon_2_Serial = 'CN0J5H2X7C'; mon_2_Size = '≈ 24 po (53 × 30 cm)'
               mon_2_Resolution = '1920 × 1080'; mon_3_Manufacturer = 'Samsung'; mon_3_Serial = 'H4ZN301234'
               # Its Dell dock, known by its hubs' USB ids (#271).
               spec_Dock_Status = 'Connectée'; spec_Dock_Model = 'Station Dell (modèle inconnu)'
               spec_Dock_Firmware = 'Non communiqué par Windows (révision USB 01.01)'
           }
           Alerts = "⚠  Pas redémarré depuis 20 jours.`n⚠  Volume C: plein à 86 % (71 Go libres).`n⚠  Batterie usée : 62 % de sa capacité d'origine." }
        @{ Name = 'ORD-04'; Via = 'act_specs'; Status = 'Lu en * s · 2 alertes'
           Prompt = "WinRM n'est pas activé sur ORD-04*à la fermeture de la fenêtre*"
           Timing = 'Connexion : * ms (DCOM)', 'Logiciels : * ms (par le registre à distance, valeur par valeur)'
           Subtitle = 'ord-04.demo.local · Poste commun cafétéria · lu le *'
           Values = [ordered]@{
               spec_General_Manufacturer = 'N/D'; spec_General_Model = 'PRIME B460M-A'; spec_General_SerialNumber = 'N/D'; spec_General_SKU = 'N/D'
               spec_General_LoggedOnUser = 'DEMO\kiosque'; spec_Network_Adapter = 'Ethernet — Realtek PCIe GbE Family Controller'
               spec_Network_LinkType = 'Ethernet · 1 Gbit/s'; vol_C = '* (94 %)'
               # A monitor without a serial number, whose size can't be read: the rest is still shown.
               spec_Monitor_Count = '1 écran'; mon_1_Manufacturer = 'ViewSonic'; mon_1_Serial = 'N/D'; mon_1_Size = 'N/D'; mon_1_Resolution = '1920 × 1080'
           }
           # A desktop: neither Batterie nor Station d'accueil (#271).
           Hidden = 'spec_Battery_Capacity', 'toggle_Battery', 'spec_Dock_Status', 'toggle_Dock', 'spec_Processor_Vendor', 'spec_Processor_Extra', 'spec_Memory_Maker', 'spec_Memory_Part'
           Alerts = "⛔  Windows 10 22H2 n'est plus supporté depuis le 2025-10-14.`n⛔  Volume C: plein à 94 % (14 Go libres)." }
        # Off, or not in the DNS: a toast, as Vérifier en ligne says it, and no dialog to close.
        @{ Name = 'ORD-06'; Via = 'menu'; Notice = 'Caractéristiques : ✖ ORD-06 : hors ligne (pas de réponse au ping, ni à WinRM ni à DCOM)' }
        @{ Name = 'ORD-03'; Via = 'menu'; Notice = "Caractéristiques : ✖ ORD-03 : introuvable (son nom n'est pas dans le DNS)" }
    )
    foreach ($specsCheck in $specsChecks) {
        $what = if ($specsCheck.Error -or $specsCheck.Report -or $specsCheck.Notice) { "says why $($specsCheck.Name) can't be read" } else { "shows $($specsCheck.Name)'s specs and alerts" }
        Invoke-Check "Caractéristiques ($(if ($specsCheck.Via -eq 'menu') { 'right-click menu' } else { 'action bar' })) $what" {
            param($problems)
            Select-ResultRow $specsCheck.Name
            if ($specsCheck.Via -eq 'menu') { Invoke-ResultMenuItem 'Caractéristiques…' } else { Invoke-Element (Find-Control 'act_specs') }
            if ($specsCheck.Notice) {
                $notice = ''
                for ($i = 0; $i -lt 4 -and $notice -ne $specsCheck.Notice; $i++) { $notice = Wait-ActionNotice $specsCheck.Notice }
                if ($notice -ne $specsCheck.Notice) { $problems.Add("the toast says '$notice'") }
                # Shown with the toast, if at all: no need to wait for one.
                $dialog = @(Get-AppWindow | Where-Object { Get-DialogPart $_ 'dialog_cancel' })[0]
                if ($dialog) {
                    $problems.Add("a dialog opened: '$(Get-DialogText $dialog)'")
                    Close-Dialog $dialog 'dialog_cancel'
                }
                if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq "Caractéristiques — $($specsCheck.Name)" }).Count) { $problems.Add('its window opened') }
                return
            }
            if ($specsCheck.Report) {
                $report = Wait-AnyDialog
                if (-not $report -or $report.Current.Name -ne 'Caractéristiques') { throw "No warning for $($specsCheck.Name)." }
                $text = (Get-DialogText $report) -replace "`r", ''
                if ($text -ne $specsCheck.Report) { $problems.Add("the warning says '$text'") }
                Close-Dialog $report 'dialog_cancel'
                if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq "Caractéristiques — $($specsCheck.Name)" }).Count) { $problems.Add('its window opened') }
                return
            }
            if ($specsCheck.Prompt) {
                $dialog = Wait-AnyDialog
                $text = if ($dialog) { Get-DialogText $dialog } else { '' }
                if (-not $dialog -or $dialog.Current.Name -ne 'Caractéristiques' -or $text -notlike $specsCheck.Prompt) { throw "No WinRM prompt for $($specsCheck.Name): '$text'" }
                if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq "Caractéristiques — $($specsCheck.Name)" }).Count) { $problems.Add('its window opened before the prompt was answered') }
                Close-Dialog $dialog 'dialog_alt'
            }
            $specsWindow = Wait-SpecsWindow $specsCheck.Name
            # A window of its own: the main window stays usable.
            if (-not (Test-WindowEnabled)) { $problems.Add('the main window is disabled') }
            $status = (Get-DialogPart $specsWindow 'spec_status').Current.Name
            if ($status -notlike $specsCheck.Status) { $problems.Add("status is '$status', expected '$($specsCheck.Status)'") }
            $tip = @((Get-DialogPart $specsWindow 'spec_status').Current.HelpText -split "`n")
            foreach ($line in @($specsCheck['Timing'])) {
                if ($line -and -not @($tip | Where-Object { $_ -like $line }).Count) { $problems.Add("the status's tooltip has no '$line': $($tip -join ' // ')") }
            }
            if ($specsCheck.Error) {
                $errorText = Get-SpecsValue $specsWindow 'spec_error_text'
                if ($errorText -notlike $specsCheck.Error) { $problems.Add("error is '$errorText'") }
                if (Get-DialogPart $specsWindow 'spec_General_Model') { $problems.Add('the sections are shown') }
                if ((Get-DialogPart $specsWindow 'spec_copy').Current.IsEnabled) { $problems.Add('Copier is enabled') }
            }
            else {
                foreach ($id in $specsCheck.Values.Keys) {
                    $value = Get-SpecsValue $specsWindow $id
                    if ($value -notlike $specsCheck.Values[$id]) { $problems.Add("$id is '$value', expected '$($specsCheck.Values[$id])'") }
                }
                foreach ($id in @($specsCheck['Hidden'] | Where-Object { $_ })) {
                    if (Get-DialogPart $specsWindow $id) { $problems.Add("$id is shown") }
                }
                # Several alerts: the first alone, and Tout voir (n) for the list, which then stays open.
                $alertCount = @($specsCheck.Alerts -split "`n").Count
                $summary = (Get-DialogPart $specsWindow 'spec_alert_summary').Current.Name
                $firstAlert = ($specsCheck.Alerts -split "`n")[0]
                if ($summary -ne $firstAlert) { $problems.Add("the folded banner shows '$summary', expected '$firstAlert'") }
                $toggle = Get-DialogPart $specsWindow 'spec_alert_toggle'
                if ($toggle.Current.Name -ne "Tout voir ($alertCount)") { $problems.Add("the banner's button is '$($toggle.Current.Name)'") }
                Invoke-Element $toggle
                Start-Sleep -Milliseconds 300
                $alerts = (Get-SpecsValue $specsWindow 'spec_alert_text') -replace "`r", ''
                if ($alerts -ne $specsCheck.Alerts) { $problems.Add("alerts are '$alerts'") }
                if ((Get-DialogPart $specsWindow 'spec_alert_toggle').Current.Name -ne 'Replier') { $problems.Add('the open banner has no Replier') }
                $subtitle = (Get-DialogPart $specsWindow 'spec_subtitle').Current.Name
                if ($subtitle -notlike $specsCheck.Subtitle) { $problems.Add("subtitle is '$subtitle'") }
                foreach ($id in 'spec_copy', 'spec_export', 'spec_refresh') {
                    if (-not (Get-DialogPart $specsWindow $id).Current.IsEnabled) { $problems.Add("$id is disabled") }
                }
                if ($ScreenshotDirectory) { Save-Screenshot "specs-$($specsCheck.Name)" $specsWindow }
            }
            Close-SpecsWindow $specsWindow
        }
    }

    Invoke-Check 'Caractéristiques on ORD-08, which answers ping only, offers to turn WinRM on or to read over DCOM' {
        param($problems)
        Select-ResultRow 'ORD-08'
        Invoke-ResultMenuItem 'Caractéristiques…'
        $dialog = Wait-AnyDialog
        $text = if ($dialog) { Get-DialogText $dialog } else { '' }
        if (-not $dialog -or $dialog.Current.Name -ne 'Caractéristiques' -or $text -notlike 'ORD-08 répond au ping, mais pas à Repère*un pare-feu*') { throw "No prompt for ORD-08: '$text'" }
        foreach ($button in @{ Id = 'dialog_ok'; Name = 'Activer WinRM' }, @{ Id = 'dialog_alt'; Name = 'Lire par DCOM' }) {
            $part = Get-DialogPart $dialog $button.Id
            if (-not $part -or $part.Current.Name -ne $button.Name) { $problems.Add("$($button.Id) is '$(if ($part) { $part.Current.Name })'") }
        }
        Close-Dialog $dialog 'dialog_cancel'
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Caractéristiques — ORD-08' }).Count) { $problems.Add('its window opened') }
    }

    Invoke-Check 'Caractéristiques on ORD-04, without WinRM, turns it on after a confirmation, reads over it, and puts it back once the window closes' {
        param($problems)
        Select-ResultRow 'ORD-04'
        Invoke-ResultMenuItem 'Caractéristiques…'
        $dialog = Wait-AnyDialog
        $text = if ($dialog) { Get-DialogText $dialog } else { '' }
        if (-not $dialog -or $text -notlike "WinRM n'est pas activé sur ORD-04*à la fermeture de la fenêtre*") { throw "No WinRM prompt for ORD-04: '$text'" }
        Close-Dialog $dialog 'dialog_ok'
        $specsWindow = Wait-SpecsWindow 'ORD-04'
        $tip = @((Get-DialogPart $specsWindow 'spec_status').Current.HelpText -split "`n")
        foreach ($line in 'Connexion : * ms (WinRM)', 'Logiciels : * ms (en un appel WinRM)') {
            if (-not @($tip | Where-Object { $_ -like $line }).Count) { $problems.Add("the status's tooltip has no '$line': $($tip -join ' // ')") }
        }
        Close-SpecsWindow $specsWindow
        $expected = 'Caractéristiques : ✔ ORD-04 : WinRM remis comme avant'
        $notice = ''
        for ($i = 0; $i -lt 4 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the status bar says '$notice'") }
    }

    Invoke-Check 'Caractéristiques: Logiciels lists the programs for the computer and its user, without system components or updates, and filters them' {
        param($problems)
        # ord-01's registry: 7 programs (Chrome in both the 64-bit and 32-bit keys, Zoom for the logged-on user only, 7-Zip
        # with its date as a number, Adobe's as 30/09/2026, Dell's a digit short), two system components (one marked by text), an update of Office, and HKU keys that
        # aren't users.
        Select-ResultRow 'ORD-01'
        Invoke-ResultMenuItem 'Caractéristiques…'
        $specsWindow = Wait-SpecsWindow 'ORD-01'
        $summary = (Get-DialogPart $specsWindow 'summary_Software').Current.Name
        if ($summary -ne '7 logiciels') { $problems.Add("Logiciels' summary is '$summary'") }
        if (Get-DialogPart $specsWindow 'software_grid') { $problems.Add('Logiciels is open at first') }
        Invoke-Element (Get-DialogPart $specsWindow 'toggle_Software')
        Start-Sleep -Milliseconds 400
        $rows = @(Get-DialogRow $specsWindow)
        if ($rows.Count -ne 7) { $problems.Add("$($rows.Count) programs: $($rows -join ' // ')") }
        if ($rows -notcontains 'Zoom Workplace | 6.4.3 (60103) | Zoom Video Communications, Inc. | 2026-10-01 | Utilisateur') { $problems.Add("no Zoom for the user: $($rows -join ' // ')") }
        if (@($rows | Where-Object { $_ -like 'Google Chrome | *' }).Count -ne 1) { $problems.Add('Google Chrome is not listed once') }
        if (@($rows | Where-Object { $_ -like '*Minimum Runtime*' -or $_ -like 'Pilote audio*' -or $_ -like 'Mise à jour*' -or $_ -like 'Pas un utilisateur*' }).Count) { $problems.Add("hidden keys are listed: $($rows -join ' // ')") }
        if ($rows -notcontains '7-Zip 24.08 (x64) | 24.08 | Igor Pavlov | 2024-08-15 | Ordinateur') { $problems.Add("7-Zip's date, a number, isn't read: $($rows -join ' // ')") }
        if ($rows -notcontains 'Adobe Acrobat Reader | 25.001.20756 | Adobe | 2026-09-30 | Ordinateur') { $problems.Add("Adobe's date, in its installer's locale, isn't read: $($rows -join ' // ')") }
        if (@($rows | Where-Object { $_ -like 'Dell Command | Update | *' -and $_ -match '\d{4}-\d{2}-\d{2}' }).Count) { $problems.Add("Dell's date, a digit short, is shown as one: $($rows -join ' // ')") }
        (Get-DialogPart $specsWindow 'software_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('GOOGLE')
        Start-Sleep -Milliseconds 300
        $filtered = @(Get-DialogRow $specsWindow)
        if ($filtered.Count -ne 1 -or $filtered[0] -notlike 'Google Chrome | 141.0.7390.66 | Google LLC | *') { $problems.Add("filtered on 'GOOGLE': $($filtered -join ' // ')") }
        $count = (Get-DialogPart $specsWindow 'software_count').Current.Name
        if ($count -ne '1 sur 7') { $problems.Add("the count says '$count'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'specs-logiciels' $specsWindow }
        Close-SpecsWindow $specsWindow
    }

    Invoke-Check 'Caractéristiques: a closed section shows its summary, and opening the same computer again brings its window back' {
        param($problems)
        Select-ResultRow 'ORD-01'
        Invoke-ResultMenuItem 'Caractéristiques…'
        $specsWindow = Wait-SpecsWindow 'ORD-01'
        Invoke-Element (Get-DialogPart $specsWindow 'toggle_General')
        Start-Sleep -Milliseconds 300
        if (Get-DialogPart $specsWindow 'spec_General_Model') { $problems.Add("Général's values are still shown") }
        $summary = (Get-DialogPart $specsWindow 'summary_General').Current.Name
        if ($summary -ne '⚠ Dell Inc. Latitude 5440 · série 7H2KQ54 · Windows 11 Professionnel') { $problems.Add("Général's summary is '$summary'") }
        Invoke-Element (Get-DialogPart $specsWindow 'spec_expand_all')
        Start-Sleep -Milliseconds 300
        if (-not (Get-DialogPart $specsWindow 'spec_General_Model')) { $problems.Add("Tout développer didn't open Général") }

        Invoke-Element (Find-Control 'act_specs')
        Start-Sleep -Milliseconds 800
        $open = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Caractéristiques — ORD-01' }).Count
        if ($open -ne 1) { $problems.Add("$open windows for ORD-01") }
        Close-SpecsWindow $specsWindow
    }
}

function Test-SpecsCancel {
    # Run with every CIM query slowed down, so a reading takes several seconds.
    Invoke-PrefixSearch 'ORD-0'
    Invoke-Check 'Caractéristiques: the sections appear as they are read, Annuler stops the reading, and Échap closes the window' {
        param($problems)
        Select-ResultRow 'ORD-01'
        Invoke-Element (Find-Control 'act_specs')
        # Until the computer answers (its check reads one class too), a toast says it's being reached, and no window.
        $notice = Wait-ActionNotice 'Caractéristiques : Connexion à ORD-01…'
        if ($notice -ne 'Caractéristiques : Connexion à ORD-01…') { $problems.Add("while connecting, the status bar says '$notice'") }
        $specsWindow = Wait-Dialog 'Caractéristiques — ORD-01'
        if (Find-ShownControl 'action_notice') { $problems.Add('the toast is still shown once the window opened') }
        $status = Get-DialogPart $specsWindow 'spec_status'
        for ($i = 0; $i -lt 80 -and $status.Current.Name -notlike 'Lecture des caractéristiques… (*'; $i++) { Start-Sleep -Milliseconds 100 }
        if ($status.Current.Name -notlike 'Lecture des caractéristiques… (*') { $problems.Add("status is '$($status.Current.Name)'") }
        $model = Get-SpecsValue $specsWindow 'spec_General_Model'
        $battery = Get-SpecsValue $specsWindow 'spec_Battery_Capacity'
        if ($model -ne 'Latitude 5440' -or $battery -ne '…') { $problems.Add("during the reading, the model is '$model' and the battery '$battery'") }
        if (-not (Test-WindowEnabled)) { $problems.Add('the main window is disabled during the reading') }
        if ((Get-DialogPart $specsWindow 'spec_refresh').Current.IsEnabled) { $problems.Add('Actualiser is enabled during the reading') }

        Invoke-Element (Get-DialogPart $specsWindow 'spec_cancel')
        Start-Sleep -Milliseconds 300
        if ($status.Current.Name -ne 'Lecture annulée.') { $problems.Add("after Annuler, status is '$($status.Current.Name)'") }
        $battery = Get-SpecsValue $specsWindow 'spec_Battery_Capacity'
        if ($battery -ne '—') { $problems.Add("after Annuler, the battery shows '$battery'") }
        if ((Get-DialogPart $specsWindow 'spec_copy').Current.IsEnabled) { $problems.Add('Copier is enabled without a complete reading') }
        if (-not (Get-DialogPart $specsWindow 'spec_refresh').Current.IsEnabled) { $problems.Add('Actualiser is disabled after Annuler') }

        Send-Key 0x1B $specsWindow
        for ($i = 0; $i -lt 20 -and @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Caractéristiques — ORD-01' }).Count; $i++) { Start-Sleep -Milliseconds 250 }
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Caractéristiques — ORD-01' }).Count) {
            $problems.Add("Échap didn't close the window")
            Close-SpecsWindow $specsWindow
        }
    }
}

function Open-MoveDialog([string]$Via = 'menu') {
    # « Déplacer vers… » for the selected rows, from the right-click menu or the action bar: its window, once the
    # domain's OUs are shown (move_status is collapsed then, so UI Automation no longer finds it).
    if ($Via -eq 'menu') { Invoke-ResultMenuItem 'Déplacer vers…' } else { Invoke-Element (Find-Control 'act_move') }
    $dialog = Wait-Dialog 'Déplacer vers…'
    for ($i = 0; $i -lt 40 -and (Get-DialogPart $dialog 'move_status'); $i++) { Start-Sleep -Milliseconds 250 }
    $status = Get-DialogPart $dialog 'move_status'
    if ($status) { throw "The OUs aren't shown: '$($status.Current.Name)'." }
    $dialog
}

function Get-MoveTreeItem($Dialog, [switch]$TopLevel) {
    # The names of the OUs the tree shows, sorted: those at the top, or every one shown. An OU's children are only
    # there while it's opened, and UI Automation leaves out the OUs the filter hides.
    $scope = if ($TopLevel) { [System.Windows.Automation.TreeScope]::Children } else { $Descendants }
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem)
    @((Get-DialogPart $Dialog 'move_tree').FindAll($scope, $isItem) | ForEach-Object { $_.Current.Name } | Sort-Object)
}

function Find-MoveTreeItem($Dialog, [string]$Name) {
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Name))
    $item = (Get-DialogPart $Dialog 'move_tree').FindFirst($Descendants, $condition)
    if (-not $item) { throw "No '$Name' in the tree." }
    $item
}

function Select-MoveTarget($Dialog, [string]$Name) {
    # Picks an OU in the tree, then returns the destination text once it has followed.
    $target = Get-DialogPart $Dialog 'move_target'
    $before = $target.Current.Name
    (Find-MoveTreeItem $Dialog $Name).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    for ($i = 0; $i -lt 20 -and $target.Current.Name -eq $before; $i++) { Start-Sleep -Milliseconds 100 }
    $target.Current.Name
}

function Get-GroupChange([string]$Command, [int]$Skip) {
    # The changes of groups sent since the query $Skip, each « group: member;member » by name, members sorted.
    @(Get-LoggedQuery | Select-Object -Skip $Skip | Where-Object Command -eq $Command | ForEach-Object {
        $name = ($_.Identity -split ',')[0] -replace '^CN=', ''
        "${name}: $(@($_.Members -split ';' | ForEach-Object { ($_ -split ',')[0] -replace '^CN=', '' } | Sort-Object) -join ';')"
    })
}

function Get-DialogListName($Dialog, [string]$List) {
    # The items of a dialog's list, top to bottom, joined by « , ».
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    @((Get-DialogPart $Dialog $List).FindAll($Descendants, $isItem) | ForEach-Object { $_.Current.Name }) -join ', '
}

function Get-MoveCall([int]$Skip) {
    # The Move-ADObject calls logged after the first $Skip lines, as « Identity -> TargetPath on Server », sorted.
    @(Get-LoggedQuery | Select-Object -Skip $Skip | Where-Object Command -eq 'Move-ADObject' |
        ForEach-Object { "$($_.Identity) -> $($_.TargetPath) on $($_.Server)" } | Sort-Object)
}

function Test-SameList([string[]]$Shown, [string[]]$Expected) {
    # Whether two lists hold the same names, in any order.
    (@($Shown | Sort-Object) -join ' | ') -eq (@($Expected | Sort-Object) -join ' | ')
}

function Test-MoveDialog {
    # Runs last in its session, after the right-click menu's checks (which removed ORD-02, ORD-09 and nord.demo.local's
    # ORD-01) and the Caractéristiques ones: the computers moved here stay in their new OU in the fake AD, and no later
    # check depends on where they are. The domain's OUs, as the tree shows them, Domain Controllers left out.
    $menuItem = 'Déplacer vers…'
    $disabledOU = 'OU=Ordinateurs désactivés,DC=demo,DC=local'
    $topOUs = 'Computers', 'Kiosques', 'Ordinateurs désactivés', 'Postes', 'Serveurs'
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD'

    Invoke-Check "Déplacer vers… offers the domain's OUs and Computers, marks the current one, and never Domain Controllers" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $states = Get-MenuItemState 'ORD-06'
        if (-not $states[$menuItem]) { $problems.Add("'$menuItem' is disabled for a selected computer") }
        $dialog = Open-MoveDialog
        if (Test-WindowEnabled) { $problems.Add('the main window stays enabled behind the window') }
        $message = (Get-DialogPart $dialog 'move_message').Current.Name
        if ($message -ne 'Déplacer ORD-06 (demo.local/Postes) vers :') { $problems.Add("the message is '$message'") }
        $top = Get-MoveTreeItem $dialog -TopLevel
        $expected = $topOUs -replace '^Postes$', 'Postes (actuel)'
        if (-not (Test-SameList $top $expected)) { $problems.Add("OUs at the top: $($top -join ', '); expected $($expected -join ', ')") }
        if ((Get-MoveTreeItem $dialog) -like 'Domain Controllers*') { $problems.Add('Domain Controllers is offered') }
        $target = (Get-DialogPart $dialog 'move_target').Current.Name
        if ($target -ne "Choisissez l'OU de destination.") { $problems.Add("before a choice, the destination reads '$target'") }
        if ((Get-DialogPart $dialog 'move_ok').Current.IsEnabled) { $problems.Add('Déplacer is enabled before a choice') }
        $target = Select-MoveTarget $dialog 'Postes (actuel)'
        if ($target -ne 'Destination : demo.local/Postes (ils y sont déjà)') { $problems.Add("with its own OU, the destination reads '$target'") }
        if ((Get-DialogPart $dialog 'move_ok').Current.IsEnabled) { $problems.Add('Déplacer is enabled for the OU the computer is already in') }
        $target = Select-MoveTarget $dialog 'Computers'
        if ($target -ne 'Destination : demo.local/Computers') { $problems.Add("with Computers, the destination reads '$target'") }
        if (-not (Get-DialogPart $dialog 'move_ok').Current.IsEnabled) { $problems.Add('Déplacer is disabled with a destination chosen') }
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-7-deplacer-vers' $dialog }
        Close-Dialog $dialog 'move_cancel'
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
        $lookups = @($calls | Where-Object { $_.Command -in 'Get-ADDomain', 'Get-ADOrganizationalUnit' } | ForEach-Object { "$($_.Command) $($_.Filter) on $($_.Server)".Replace('  ', ' ') })
        if (($lookups -join ' | ') -ne 'Get-ADDomain on demo.local | Get-ADOrganizationalUnit * on demo.local') { $problems.Add("OU lookups: $($lookups -join ' | ')") }
        if ($calls | Where-Object Command -eq 'Move-ADObject') { $problems.Add('something was moved') }
    }

    Invoke-Check "Déplacer vers…: Annuler moves nothing, and the domain's OUs aren't looked up again" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-06'
        $dialog = Open-MoveDialog 'act_move'
        $null = Select-MoveTarget $dialog 'Serveurs'
        Close-Dialog $dialog 'move_cancel'
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Déplacer vers…' }).Count) { $problems.Add('the window is still open') }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
        foreach ($call in $calls | Where-Object { $_.Command -in 'Move-ADObject', 'Get-ADDomain', 'Get-ADOrganizationalUnit' }) { $problems.Add("$($call.Command) was sent") }
        if ((Get-ResultCell 'ORD-06' 6) -ne 'Postes') { $problems.Add("ORD-06 shows '$(Get-ResultCell 'ORD-06' 6)'") }
    }

    Invoke-Check "Déplacer vers…: the current OU's parents are opened, and the filter shows the matching OUs with their parents" {
        param($problems)
        # ORD-11 is in Postes/Communs/Communs-Entree: Postes and Communs are opened, Kiosques isn't.
        Select-ResultRow 'ORD-11'
        $dialog = Open-MoveDialog
        $shown = Get-MoveTreeItem $dialog
        $expected = @($topOUs) + 'Communs', 'Communs-Entree (actuel)', 'Labo-Communs'
        if (-not (Test-SameList $shown $expected)) { $problems.Add("OUs shown: $($shown -join ', '); expected $($expected -join ', ')") }
        $filters = @(
            @{ Text = 'comm'; Expected = 'Postes', 'Communs', 'Communs-Entree (actuel)', 'Labo-Communs', 'Kiosques', 'Communs-Kiosques' }
            @{ Text = 'SERV'; Expected = @('Serveurs') }
            @{ Text = 'xyz'; Expected = @() }
        )
        foreach ($filter in $filters) {
            (Get-DialogPart $dialog 'move_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($filter.Text)
            Start-Sleep -Milliseconds 300
            $shown = Get-MoveTreeItem $dialog
            if (-not (Test-SameList $shown $filter.Expected)) { $problems.Add("with '$($filter.Text)', OUs shown: $($shown -join ', '); expected $($filter.Expected -join ', ')") }
            if ($ScreenshotDirectory -and $filter.Text -eq 'auto') { Save-Screenshot 'menu-8-deplacer-filtre' $dialog }
        }
        (Get-DialogPart $dialog 'move_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
        Start-Sleep -Milliseconds 300
        $top = Get-MoveTreeItem $dialog -TopLevel
        if (-not (Test-SameList $top $topOUs)) { $problems.Add("once the filter is emptied, OUs at the top: $($top -join ', ')") }
        Close-Dialog $dialog 'move_cancel'
    }

    Invoke-Check 'Déplacer vers…: the filter keeps the OU chosen, and one it hides is no longer the destination' {
        param($problems)
        # ORD-11 is under Postes: Kiosques is closed until the filter opens it.
        Select-ResultRow 'ORD-11'
        $dialog = Open-MoveDialog
        $filter = (Get-DialogPart $dialog 'move_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $filter.SetValue('Kiosques')
        Start-Sleep -Milliseconds 300
        $chosen = Select-MoveTarget $dialog 'Communs-Kiosques'
        $filter.SetValue('')
        Start-Sleep -Milliseconds 300
        $target = (Get-DialogPart $dialog 'move_target').Current.Name
        if ($target -ne $chosen) { $problems.Add("the filter erased, the destination goes from '$chosen' to '$target'") }
        $filter.SetValue('Serveurs')
        Start-Sleep -Milliseconds 300
        $target = (Get-DialogPart $dialog 'move_target').Current.Name
        if ($target -ne "Choisissez l'OU de destination.") { $problems.Add("with the OU hidden, the destination is '$target'") }
        if ((Get-DialogPart $dialog 'move_ok').Current.IsEnabled) { $problems.Add('with the OU hidden, the move can go ahead') }
        Close-Dialog $dialog 'move_cancel'
    }

    Invoke-Check 'Déplacer vers… moves a computer, updates its row without a new search, and a new search finds it there' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-03'
        $dialog = Open-MoveDialog 'act_move'
        $target = Select-MoveTarget $dialog 'Ordinateurs désactivés'
        if ($target -ne 'Destination : demo.local/Ordinateurs désactivés') { $problems.Add("the destination reads '$target'") }
        (Get-DialogPart $dialog 'move_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-DialogsClosed
        $expectedNotice = 'Déplacé : ✔ ORD-03 : demo.local/Postes → demo.local/Ordinateurs désactivés'
        $notice = Wait-ActionNotice $expectedNotice
        if ($notice -ne $expectedNotice) { $problems.Add("the status bar says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report window opened') }
        $moves = (Get-MoveCall $queriesBefore) -join ' | '
        if ($moves -ne "CN=ORD-03,OU=Postes,DC=demo,DC=local -> $disabledOU on demo.local") { $problems.Add("moves: $moves") }
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer') { $problems.Add('the grid was refreshed with a new search') }
        if ((Get-ResultCell 'ORD-03' 6) -ne 'Ordinateurs désactivés') { $problems.Add("ORD-03 shows '$(Get-ResultCell 'ORD-03' 6)'") }
        try {
            # The filter box finds a row by its Emplacement too: the new one.
            Set-Text 'filter' 'ordinateurs désactivés'
            $shown = (Get-ResultName) -join ', '
            if ($shown -ne 'ORD-03') { $problems.Add("the filter finds by the new OU: '$shown'") }
        }
        finally {
            Set-Text 'filter' ''
        }
        Invoke-PrefixSearch 'ORD-03'
        if ((Get-ResultCell 'ORD-03' 6) -ne 'Ordinateurs désactivés') { $problems.Add("after a new search, ORD-03 shows '$(Get-ResultCell 'ORD-03' 6)'") }
    }

    Invoke-Check 'Déplacer vers… several computers: a protected one and a refused one are reported first, one already there is left alone' {
        param($problems)
        # ORD-03 is already in Ordinateurs désactivés (moved above), ORD-07 is protected from accidental deletion, the
        # fake AD refuses changes to ORD-12, and ORD-10 moves.
        Invoke-PrefixSearch 'ORD'
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-03'
        foreach ($name in 'ORD-07', 'ORD-10', 'ORD-12') { Add-ResultRow $name }
        $dialog = Open-MoveDialog
        $message = (Get-DialogPart $dialog 'move_message').Current.Name
        if ($message -notlike 'Déplacer ces 4 ordinateurs de demo.local vers :*' -or $message -notlike '*ORD-03*demo.local/Ordinateurs désactivés*' -or $message -notlike '*ORD-12*demo.local/Postes*') {
            $problems.Add("the message is '$message'")
        }
        # Not all in the same OU: none is marked as the current one.
        $top = Get-MoveTreeItem $dialog -TopLevel
        if (-not (Test-SameList $top $topOUs)) { $problems.Add("OUs at the top: $($top -join ', ')") }
        $target = Select-MoveTarget $dialog 'Ordinateurs désactivés'
        if ($target -ne 'Destination : demo.local/Ordinateurs désactivés (1 y sont déjà)') { $problems.Add("the destination reads '$target'") }
        (Get-DialogPart $dialog 'move_ok').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $report = Wait-Dialog 'Déplacer'
        $lines = @((Get-DialogText $report) -split "`r?`n")
        if ($ScreenshotDirectory) { Save-Screenshot 'menu-9-deplacer-rapport' $report }
        Close-Dialog $report 'dialog_cancel'
        # Failures first; within each group, in the order of the selection.
        $failures = @($lines | Select-Object -First 2 | Sort-Object)
        $successes = @($lines | Select-Object -Skip 2 | Sort-Object)
        if ($lines.Count -ne 4 -or $failures[0] -ne '✖ ORD-07 : protégé contre la suppression accidentelle, non déplacé' -or $failures[1] -notlike '✖ ORD-12 : *Droits insuffisants pour cette opération*' -or
            $successes[0] -ne '✔ ORD-03 (déjà dans cette OU)' -or $successes[1] -ne '✔ ORD-10 : demo.local/Postes → demo.local/Ordinateurs désactivés') {
            $problems.Add("report says: $($lines -join ' | ')")
        }
        # ORD-07's protection is checked first: no move is even tried for it, nor for ORD-03.
        $moves = (Get-MoveCall $queriesBefore) -join ' | '
        $expected = "CN=ORD-10,OU=Postes,DC=demo,DC=local -> $disabledOU on demo.local | CN=ORD-12,OU=Postes,DC=demo,DC=local -> $disabledOU on demo.local"
        if ($moves -ne $expected) { $problems.Add("moves: $moves; expected $expected") }
        $cells = @{ 'ORD-03' = 'Ordinateurs désactivés'; 'ORD-07' = 'Postes'; 'ORD-10' = 'Ordinateurs désactivés'; 'ORD-12' = 'Postes' }
        foreach ($name in $cells.Keys) {
            $shown = Get-ResultCell $name 6
            if ($shown -ne $cells[$name]) { $problems.Add("$name shows '$shown', expected '$($cells[$name])'") }
        }
        Select-ResultRow 'ORD-01'
    }

    Invoke-Check 'Déplacer vers… with computers of two domains says so and moves nothing' {
        param($problems)
        # NRD-01 (nord.demo.local) and ORD-11 (demo.local) both have « commun » in their description.
        Select-Domain 'Tous les domaines'
        try {
            Invoke-PrefixSearch '' 'commun'
            $queriesBefore = @(Get-LoggedQuery).Count
            Select-ResultRow 'ORD-11'
            Add-ResultRow 'NRD-01'
            Invoke-ResultMenuItem $menuItem
            $dialog = Wait-Dialog 'Déplacer'
            $message = Get-DialogText $dialog
            if ($message -notlike '*dans 2 domaines (demo.local, nord.demo.local)*' -and $message -notlike '*dans 2 domaines (nord.demo.local, demo.local)*') { $problems.Add("the dialog says '$message'") }
            if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Déplacer vers…' }).Count) { $problems.Add('the Déplacer vers… window opened') }
            Close-Dialog $dialog 'dialog_cancel'
            $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
            foreach ($call in $calls | Where-Object { $_.Command -in 'Move-ADObject', 'Get-ADDomain', 'Get-ADOrganizationalUnit' }) { $problems.Add("$($call.Command) was sent to $($call.Server)") }
        }
        finally {
            Select-Domain 'demo.local'
        }
    }
}

function Test-MoveRootImposed {
    Invoke-Check 'Paramètres › Déplacer vers: with -MoveRoots, the OUs are imposed and cannot be changed' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        if (-not (Get-DialogPart $settingsWindow 'move_roots_imposed_text')) { $problems.Add("it doesn't say -MoveRoots imposes them") }
        $box = Get-MoveRootBox $settingsWindow 'Postes'
        if ((Get-BoxState $box) -ne 'On (grisée)') { $problems.Add("Postes is $(Get-BoxState $box)") }
        if (Get-DialogPart $settingsWindow 'move_roots_clear') { $problems.Add('Tout décocher is offered') }
        if ($settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Retirer Postes'))) { $problems.Add('Postes can be taken off') }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }
}

function Test-MoveRootLong {
    # Run with 40 more OUs under demo.local's Postes, and a -MoveRoots of nord.demo.local's OUs: too long for its banner,
    # one of them named {Bureau-1.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-04'
    Invoke-Check '-MoveRoots in a child domain leaves its parent''s OUs as they are' {
        param($problems)
        Select-ResultRow 'ORD-04'
        $dialog = Open-MoveDialog 'act_move'
        $top = @(Get-MoveTreeItem $dialog -TopLevel)
        if ($top -notcontains 'Postes' -or $top -notcontains 'Serveurs') { $problems.Add("Déplacer vers… offers at the top: $($top -join ', ')") }
        Close-Dialog $dialog 'move_cancel'
    }
    Invoke-Check 'Paramètres › Déplacer vers: at its smallest, a tree longer than the window scrolls alone, beside a -MoveRoots kept to a few lines' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        (Get-MoveRootItem $settingsWindow 'Postes').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        $size = $settingsWindow.Current.BoundingRectangle
        # Below its minimum: the window stops there.
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern).Resize($size.Width, 100)
        Start-Sleep -Milliseconds 500
        $window = $settingsWindow.Current.BoundingRectangle
        $treePart = Get-DialogPart $settingsWindow 'move_roots_tree'
        $tree = $treePart.Current.BoundingRectangle
        if ($tree.Bottom -gt $window.Bottom) { $problems.Add("the tree ends $([int]($tree.Bottom - $window.Bottom)) px below the window") }
        if ($tree.Height -lt $window.Height / 3) { $problems.Add("the tree has $([int]$tree.Height) px of a $([int]$window.Height) px window") }
        if (Get-DialogPart $settingsWindow 'settings_scroll') { $problems.Add('the scrolling of the other sections is shown') }
        $scroll = $treePart.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
        if (-not $scroll.Current.VerticallyScrollable) { $problems.Add("the tree doesn't scroll") }
        $filterTop = (Get-DialogPart $settingsWindow 'move_roots_filter').Current.BoundingRectangle.Top
        $scroll.SetScrollPercent(-1, 100)
        Start-Sleep -Milliseconds 300
        $moved = (Get-DialogPart $settingsWindow 'move_roots_filter').Current.BoundingRectangle.Top - $filterTop
        if ($moved) { $problems.Add("the filter moved $([int]$moved) px with the tree") }
        if (-not $settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, '{Bureau-1'))) { $problems.Add("{Bureau-1 isn't listed") }
        (Get-DialogPart $settingsWindow 'move_roots_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Site_01')
        Start-Sleep -Milliseconds 400
        # The text shown, not the name given to screen readers: an underscore is an access key to a check box.
        if (-not (Get-MoveRootBox $settingsWindow 'Site_01').FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Site_01'))) { $problems.Add("Site_01 doesn't show its underscore") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
    }
    Invoke-Check 'Paramètres › Déplacer vers: another domain chosen during a slow lookup shows its own OUs, and the lookup can be made again' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        # demo.local is known already, nord.demo.local takes 1.5 s.
        Select-ComboItem 'move_roots_domain' 'nord.demo.local'
        Select-ComboItem 'move_roots_domain' 'demo.local'
        Start-Sleep -Seconds 2
        $null = Get-MoveRootBox $settingsWindow 'Serveurs'
        if (Get-DialogPartName $settingsWindow 'move_roots_status') { $problems.Add("demo.local says '$(Get-DialogPartName $settingsWindow 'move_roots_status')'") }
        Select-ComboItem 'move_roots_domain' 'nord.demo.local'
        $null = Get-MoveRootBox $settingsWindow 'Postes'
        if ($settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Serveurs'))) { $problems.Add('demo.local''s OUs stay in nord.demo.local') }
        Select-ComboItem 'move_roots_domain' 'demo.local'
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }
}

function Test-MoveRoot {
    # Run with -MoveRoots "OU=Postes,DC=demo,DC=local": only Postes and the OUs under it are offered, not Computers.
    # ORD-04 is in Kiosques/Communs-Kiosques, outside them: none is marked as its current OU.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-04'
    Invoke-Check '-MoveRoots limits Déplacer vers… to those OUs and the ones under them' {
        param($problems)
        Select-ResultRow 'ORD-04'
        $dialog = Open-MoveDialog 'act_move'
        $top = (Get-MoveTreeItem $dialog -TopLevel) -join ', '
        if ($top -ne 'Postes') { $problems.Add("OUs at the top: $top; expected Postes") }
        (Find-MoveTreeItem $dialog 'Postes').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        Start-Sleep -Milliseconds 300
        $shown = Get-MoveTreeItem $dialog
        if (-not (Test-SameList $shown 'Postes', 'Communs', 'Labo-Communs')) { $problems.Add("OUs shown with Postes opened: $($shown -join ', ')") }
        Close-Dialog $dialog 'move_cancel'
    }
}

function Get-HeaderByPosition([string]$Grid = 'data_grid') {
    # The column headers' names and widths, left to right as shown (dragging a header moves it on screen only).
    $isHeader = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::HeaderItem)
    @((Find-Control $Grid).FindAll($Descendants, $isHeader) | Where-Object { $_.Current.Name } |
        Sort-Object { $_.Current.BoundingRectangle.Left } |
        ForEach-Object { [pscustomobject]@{ Name = $_.Current.Name; Width = $_.Current.BoundingRectangle.Width; Element = $_ } })
}

function Get-HeaderWidthRatio([string]$Grid, [string]$Name, [string]$Base) {
    # A column's width over another's, as shown: screen widths follow the display's scaling, a ratio doesn't.
    $headers = @(Get-HeaderByPosition $Grid)
    $width = @($headers | Where-Object Name -eq $Name)[0].Width
    $baseWidth = @($headers | Where-Object Name -eq $Base)[0].Width
    if ($baseWidth) { $width / $baseWidth } else { 0 }
}

function Open-ColumnMenu {
    # The Colonnes button's menu: its items.
    Invoke-Element (Find-Control 'columns')
    for ($i = 0; $i -lt 20; $i++) {
        $items = @(Get-OpenMenuItem)
        if ($items.Count) { return $items }
        Start-Sleep -Milliseconds 150
    }
    throw "The Colonnes menu didn't open."
}

function Invoke-ColumnMenuItem([string]$AutomationId) {
    $item = @(Open-ColumnMenu) | Where-Object { $_.Current.AutomationId -eq $AutomationId } | Select-Object -First 1
    if (-not $item) { throw "No $AutomationId in the Colonnes menu." }
    $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 300
    Close-Menu
}

function Test-Column {
    # Runs last, in a session of its own: it saves columns to apparence.json, which the Apparence checks expect empty.
    $allColumns = 'Compte, Nom, Description, Dernière connexion, Système, Domaine, Emplacement'
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'

    Invoke-Check 'Colonnes: the menu lists every column but Nom, all ticked but En ligne, and Réinitialiser' {
        param($problems)
        $items = @(Open-ColumnMenu)
        $names = ($items | ForEach-Object { $_.Current.Name }) -join ', '
        if ($names -ne 'Compte, Description, Dernière connexion, Système, Domaine, Emplacement, En ligne, Réinitialiser les colonnes') { $problems.Add("menu items: $names") }
        # En ligne only shows once Vérifier en ligne has filled it.
        foreach ($item in $items | Where-Object { $_.Current.AutomationId -ne 'column_reset' }) {
            $state = $item.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
            $expected = if ($item.Current.AutomationId -eq 'column_Online') { 'Off' } else { 'On' }
            if ($state -ne $expected) { $problems.Add("$($item.Current.Name) is $state") }
        }
        if ($ScreenshotDirectory) { Save-Screenshot 'colonnes-menu' }
        Close-Menu
    }

    Invoke-Check 'Tri: by name, by description when one was searched, and a sort chosen stays (#195)' {
        param($problems)
        # « ORD-0 »: ORD-03, ORD-05 and ORD-07 have no description, and came first when the rows were sorted by it.
        $names = @(Get-ResultRow | ForEach-Object { $_[1] }) -join ', '
        $expected = @(Get-ResultRow | ForEach-Object { $_[1] } | Sort-Object) -join ', '
        if ($names -ne $expected) { $problems.Add("« ORD-0 » shows $names, expected $expected") }
        # « poste »: by name it'd be ORD-04, ORD-09, ORD-11.
        Invoke-PrefixSearch '' 'poste'
        $names = @(Get-ResultRow | ForEach-Object { $_[1] }) -join ', '
        if ($names -ne 'ORD-04, ORD-11, ORD-09') { $problems.Add("description « poste » shows $names, expected ORD-04, ORD-11, ORD-09 (by description)") }
        # A name search has Nom's arrow, ascending, so a click on Nom sorts it descending; that sort stays for the next
        # search, a description's too.
        Invoke-PrefixSearch 'ORD-0'
        $isHeader = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::HeaderItem)
        $nameHeader = @((Find-Control 'data_grid').FindAll($Descendants, $isHeader) | Where-Object { $_.Current.Name -eq 'Nom' })[0]
        Invoke-Element $nameHeader
        Start-Sleep -Milliseconds 300
        $names = @(Get-ResultRow | ForEach-Object { $_[1] })
        $expected = @($names | Sort-Object -Descending) -join ', '
        if (($names -join ', ') -ne $expected) { $problems.Add("after a click on Nom, « ORD-0 » shows $($names -join ', '), expected $expected") }
        Invoke-PrefixSearch '' 'poste'
        $names = @(Get-ResultRow | ForEach-Object { $_[1] }) -join ', '
        if ($names -ne 'ORD-11, ORD-09, ORD-04') { $problems.Add("after a click on Nom, « poste » shows $names, expected ORD-11, ORD-09, ORD-04 (the sort chosen)") }
        Invoke-PrefixSearch 'ORD-0'
    }

    Invoke-Check 'Colonnes: a hidden column leaves the grid, and the filter box no longer searches it' {
        param($problems)
        # ORD-04 is the only one in a Kiosques OU; ORD-04, ORD-05 and ORD-09 are on Windows 10.
        Set-Text 'filter' 'kiosques'
        if (((Get-ResultName) -join ', ') -ne 'ORD-04') { $problems.Add("before hiding Emplacement, 'kiosques' finds: $((Get-ResultName) -join ', ')") }
        Set-Text 'filter' ''
        Invoke-ColumnMenuItem 'column_ShortPath'
        $headers = (Get-HeaderByPosition | ForEach-Object Name) -join ', '
        if ($headers -ne 'Compte, Nom, Description, Dernière connexion, Système, Domaine') { $problems.Add("columns are: $headers") }
        try {
            Set-Text 'filter' 'kiosques'
            if (@(Get-ResultName).Count) { $problems.Add("with Emplacement hidden, 'kiosques' still finds: $((Get-ResultName) -join ', ')") }
            Set-Text 'filter' 'win 10'
            if (((Get-ResultName) -join ', ') -ne 'ORD-04, ORD-05, ORD-09') { $problems.Add("'win 10' finds: $((Get-ResultName) -join ', ')") }
        }
        finally { Set-Text 'filter' '' }
    }

    Invoke-Check 'Colonnes: a hidden column stays hidden after a restart, and Réinitialiser brings it back' {
        param($problems)
        Restart-App
        $saved = Read-SavedAppearance
        $savedShortPath = @($saved.Columns | Where-Object Key -eq 'ShortPath')[0]
        if (-not $savedShortPath -or $savedShortPath.Visible) { $problems.Add("apparence.json holds: $($saved.Columns | ConvertTo-Json -Compress)") }
        $headers = (Get-HeaderByPosition | ForEach-Object Name) -join ', '
        if ($headers -ne 'Compte, Nom, Description, Dernière connexion, Système, Domaine') { $problems.Add("after the restart, columns are: $headers") }
        Invoke-ColumnMenuItem 'column_reset'
        $headers = (Get-HeaderByPosition | ForEach-Object Name) -join ', '
        if ($headers -ne $allColumns) { $problems.Add("after Réinitialiser, columns are: $headers") }
    }

    Invoke-Check 'Colonnes: the order and widths saved in the settings are restored' {
        param($problems)
        # Système first, and Description 300 wide (Nom keeps its 110). Screen widths follow the display's scaling, so
        # they're compared with each other.
        $columns = @(
            @{ Key = 'OSBuild'; Visible = $true; Width = 130; Unit = 'Pixel'; Index = 0 }
            @{ Key = 'Disabled'; Visible = $true; Width = 80; Unit = 'Pixel'; Index = 1 }
            @{ Key = 'ComputerName'; Visible = $true; Width = 110; Unit = 'Pixel'; Index = 2 }
            @{ Key = 'Description'; Visible = $true; Width = 300; Unit = 'Pixel'; Index = 3 }
            @{ Key = 'LastLogon'; Visible = $true; Width = 160; Unit = 'Pixel'; Index = 4 }
            @{ Key = 'Domain'; Visible = $true; Width = 150; Unit = 'Pixel'; Index = 5 }
            @{ Key = 'ShortPath'; Visible = $true; Width = 2; Unit = 'Star'; Index = 6 }
        )
        Restart-App (@{ Columns = $columns } | ConvertTo-Json -Depth 3)
        $headers = @(Get-HeaderByPosition)
        $names = ($headers | ForEach-Object Name) -join ', '
        if ($names -ne 'Système, Compte, Nom, Description, Dernière connexion, Domaine, Emplacement') { $problems.Add("columns are: $names") }
        $description = @($headers | Where-Object Name -eq 'Description')[0].Width
        $name = @($headers | Where-Object Name -eq 'Nom')[0].Width
        $ratio = if ($name) { $description / $name } else { 0 }
        if ([Math]::Abs($ratio - 300 / 110) -gt 0.15) { $problems.Add("Description is $description wide and Nom $name, expected 300 and 110") }
        if ($ScreenshotDirectory) { Save-Screenshot 'colonnes-ordre' }
    }

    Invoke-Check 'Colonnes: a width chosen on Utilisateurs and on Groupes stays after a search and a restart, each page its own (#277)' {
        param($problems)
        # Identifiant 250 wide (État keeps its 105), Type 200 (Étendue keeps its 120), resized as a screen reader does:
        # a drag of the header's edge takes a real mouse, which these tests don't use (the unit tests drag it).
        $resize = {
            param([string]$Grid, [string]$Name, [double]$Width)
            $header = @(Get-HeaderByPosition $Grid | Where-Object Name -eq $Name)[0].Element
            $header.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern).Resize($Width, 0)
            Start-Sleep -Milliseconds 300
        }
        # Checked on its page, the other page's grid being hidden.
        $check = {
            param([string]$Grid, [string]$When)
            $column = @{ user_grid = @{ Name = 'Identifiant'; Base = 'État'; Ratio = 250 / 105 }; group_grid = @{ Name = 'Type'; Base = 'Étendue'; Ratio = 200 / 120 } }[$Grid]
            $ratio = Get-HeaderWidthRatio $Grid $column.Name $column.Base
            if ([Math]::Abs($ratio - $column.Ratio) -gt 0.15) { $problems.Add("$When, $($column.Name) is $([Math]::Round($ratio, 2)) times $($column.Base)'s width, expected $([Math]::Round($column.Ratio, 2))") }
        }
        Show-UserPage
        $null = Invoke-UserSearch 'Tous les domaines' 'Nom, identifiant ou courriel' 'bert'
        & $resize 'user_grid' 'Identifiant' 250
        Show-GroupPage
        $null = Invoke-GroupSearch 'Tous les domaines' 'Nom contient' 'g'
        & $resize 'group_grid' 'Type' 200
        Show-UserPage
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bertrand'
        & $check 'user_grid' 'after another search'
        Show-GroupPage
        $null = Invoke-GroupSearch 'demo.local' 'Nom contient' 'vpn'
        & $check 'group_grid' 'after another search'
        Restart-App
        $saved = Read-SavedAppearance
        $login = @($saved.UserColumns | Where-Object Key -eq 'Login')[0]
        $type = @($saved.GroupColumns | Where-Object Key -eq 'Type')[0]
        if ("$($login.Width) $($login.Unit) / $($type.Width) $($type.Unit)" -ne '250 Pixel / 200 Pixel') { $problems.Add("apparence.json holds Identifiant $($login.Width) $($login.Unit), Type $($type.Width) $($type.Unit)") }
        Show-UserPage
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        & $check 'user_grid' 'after a restart'
        Show-GroupPage
        $null = Invoke-GroupSearch 'demo.local' 'Nom contient' 'g'
        & $check 'group_grid' 'after a restart'
        Invoke-Element (Find-Control 'tab_computers')
        for ($i = 0; $i -lt 10 -and -not (Find-ShownControl 'prefix'); $i++) { Start-Sleep -Milliseconds 200 }
    }
}

function Find-ColumnFilterButton([string]$Key, [string]$Grid = 'data_grid') {
    # A column's funnel, in its header, or $null when it isn't shown.
    (Find-Control $Grid).FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, "colfilter_$Key"))
}

function Open-ColumnFilterList([string]$Key, [string]$Grid = 'data_grid', [string]$Prefix = '') {
    # A column's filter (its list of values, its text or its age), opened by its funnel.
    $button = Find-ColumnFilterButton $Key $Grid
    if (-not $button) { throw "No funnel on the $Key column." }
    Invoke-Element $button
    for ($i = 0; $i -lt 20 -and -not (Find-ShownControl "$($Prefix)colfilter_ok"); $i++) { Start-Sleep -Milliseconds 150 }
    if (-not (Find-ShownControl "$($Prefix)colfilter_ok")) { throw "The $Key column's filter didn't open." }
    Start-Sleep -Milliseconds 200
}

function Get-ColumnFilterAge([string]$Prefix = '') {
    # The open Age filter, « Plus de 90 jours On »: its direction, number, unit and Jamais.
    $chosen = { param($names) foreach ($name in $names) { $button = Find-Control "$($Prefix)colfilter_age_$name"; if ($button.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected) { $button.Current.Name } } }
    $number = (Find-Control "$($Prefix)colfilter_age_number").GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    $never = (Find-Control "$($Prefix)colfilter_age_never").GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
    "$(& $chosen 'atleast', 'less') $number $(& $chosen 'unit0', 'unit1', 'unit2', 'unit3') $never"
}

function Select-ColumnFilterButton([string]$Name, [string]$Prefix = '') {
    # One of the open Age filter's buttons: atleast, less, unit0 (jours) to unit3 (ans).
    (Find-Control "$($Prefix)colfilter_age_$Name").GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 150
}

function Get-ColumnFilterPart([string]$Prefix = '') {
    # Which parts of the open filter show, in order: search, age, hint, all, values.
    @(foreach ($part in 'search', 'age_number', 'hint', 'all', 'values') { if (Find-ShownControl "$($Prefix)colfilter_$part") { $part } }) -join ', '
}

function Get-ColumnFilterBox([string]$Prefix = '') {
    # The check boxes of the open list, in order.
    $isBox = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'ValueBox')
    @((Find-Control "$($Prefix)colfilter_values").FindAll($Descendants, $isBox) | Sort-Object { $_.Current.BoundingRectangle.Top })
}

function Get-ColumnFilterListText([string]$Prefix = '') {
    # The open list's values and counts, « Activé (6) », ticked ones marked ✔.
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $isBox = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'ValueBox')
    @(foreach ($item in (Find-Control "$($Prefix)colfilter_values").FindAll([System.Windows.Automation.TreeScope]::Children, $isItem) | Sort-Object { $_.Current.BoundingRectangle.Top }) {
        $box = $item.FindFirst($Descendants, $isBox)
        $count = @($item.FindAll($Descendants, $isText))[-1].Current.Name
        $mark = if ($box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On') { '✔' } else { '' }
        "$mark$($box.Current.Name) ($count)"
    })
}

function Set-ColumnFilterTicked([string[]]$Ticked, [string]$Prefix = '') {
    # Ticks these values of the open list and unticks the others.
    foreach ($box in Get-ColumnFilterBox $Prefix) {
        $toggle = $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if (($toggle.Current.ToggleState -eq 'On') -ne ($box.Current.Name -in $Ticked)) { $toggle.Toggle() }
    }
    Start-Sleep -Milliseconds 200
}

function Close-ColumnFilterList([string]$Button = 'ok', [string]$Prefix = '') {
    # OK, Annuler or Effacer le filtre, then waits for the list to close and the grid to follow.
    Invoke-Element (Find-Control "$($Prefix)colfilter_$Button")
    for ($i = 0; $i -lt 20 -and (Find-ShownControl "$($Prefix)colfilter_ok"); $i++) { Start-Sleep -Milliseconds 150 }
    Start-Sleep -Milliseconds 300
}

function Test-ColumnFilter {
    # Ordinateurs' column filters, on ORD-01 to ORD-09: six enabled and three disabled (ORD-05, ORD-07, ORD-09); last
    # logged on 1 to 6 days ago (ORD-01, 02, 04, 06), 45 days (ORD-08), 120 (ORD-09), 210 (ORD-05), never (ORD-03, 07).
    # Saves the Filtres button's state in apparence.json.
    $all = 'ORD-01, ORD-02, ORD-03, ORD-04, ORD-05, ORD-06, ORD-07, ORD-08, ORD-09'
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'

    Invoke-Check 'Filtres: every column header has its funnel, and the Filtres button hides them' {
        param($problems)
        $toggle = (Find-Control 'column_filters').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle.Current.ToggleState -ne 'On') { $problems.Add("Filtres is $($toggle.Current.ToggleState) at first") }
        foreach ($key in 'Disabled', 'ComputerName', 'Description', 'LastLogon', 'OSBuild', 'Domain', 'ShortPath') {
            if (-not (Find-ColumnFilterButton $key)) { $problems.Add("no funnel on $key") }
        }
        $toggle.Toggle()
        Start-Sleep -Milliseconds 300
        if (Find-ColumnFilterButton 'Description') { $problems.Add('with Filtres off, Description still has its funnel') }
        $saved = Wait-SavedAppearance { param($saved) @($saved.HiddenColumnFilters) -contains 'Computers' }
        if (@($saved.HiddenColumnFilters) -notcontains 'Computers') { $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress)") }
        $toggle.Toggle()
        Start-Sleep -Milliseconds 300
        if (-not (Find-ColumnFilterButton 'Description')) { $problems.Add('with Filtres on again, Description has no funnel') }
    }

    Invoke-Check 'Filtres: Compte lists its values with their counts, and only Désactivé leaves the disabled computers' {
        param($problems)
        Open-ColumnFilterList 'Disabled'
        $listed = (Get-ColumnFilterListText) -join ', '
        if ($listed -ne '✔Activé (6), ✔Désactivé (3)') { $problems.Add("the list holds: $listed") }
        if ($ScreenshotDirectory) { Save-Screenshot 'filtre-colonne' }
        Set-ColumnFilterTicked 'Désactivé'
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-05, ORD-07, ORD-09') { $problems.Add("rows shown: $((Get-ResultName) -join ', ')") }
        $count = (Find-Control 'results_count').Current.Name
        if ($count -ne '9 ordinateurs · 3 affichés') { $problems.Add("the count says '$count'") }
        $button = (Find-Control 'column_filters_text').Current.Name
        if ($button -ne 'Filtres (1)') { $problems.Add("the button says '$button'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'filtre-actif' }
    }

    Invoke-Check "Filtres: another column lists only the filtered rows' values, the empty one first" {
        param($problems)
        Open-ColumnFilterList 'OSBuild'
        $listed = (Get-ColumnFilterListText) -join ', '
        if ($listed -ne '✔Inconnu (1), ✔Win 10 21H2 (1), ✔Win 10 22H2 (1)') { $problems.Add("the list holds: $listed") }
        Close-ColumnFilterList 'cancel'
        if (((Get-ResultName) -join ', ') -ne 'ORD-05, ORD-07, ORD-09') { $problems.Add("after Annuler, rows shown: $((Get-ResultName) -join ', ')") }
    }

    Invoke-Check 'Filtres: with Filtres off, a filtered column keeps its funnel' {
        param($problems)
        $toggle = (Find-Control 'column_filters').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $toggle.Toggle()
        Start-Sleep -Milliseconds 300
        try {
            if (-not (Find-ColumnFilterButton 'Disabled')) { $problems.Add('Compte, filtered, has no funnel') }
            if (Find-ColumnFilterButton 'Description') { $problems.Add('Description, not filtered, still has its funnel') }
        }
        finally { $toggle.Toggle(); Start-Sleep -Milliseconds 300 }
    }

    Invoke-Check 'Filtres: the filter box and the column filters work together' {
        param($problems)
        Set-Text 'filter' 'ventes'
        try {
            if (((Get-ResultName) -join ', ') -ne 'ORD-09') { $problems.Add("'ventes' and Désactivé show: $((Get-ResultName) -join ', ')") }
        }
        finally { Set-Text 'filter' '' }
    }

    Invoke-Check 'Filtres: Effacer le filtre shows every row again' {
        param($problems)
        Open-ColumnFilterList 'Disabled'
        Close-ColumnFilterList 'clear'
        if (((Get-ResultName) -join ', ') -ne $all) { $problems.Add("rows shown: $((Get-ResultName) -join ', ')") }
        $button = (Find-Control 'column_filters_text').Current.Name
        if ($button -ne 'Filtres') { $problems.Add("the button says '$button'") }
    }

    Invoke-Check "Filtres: a search in the list with all it finds ticked keeps what contains it" {
        param($problems)
        Open-ColumnFilterList 'ShortPath'
        Set-Text 'colfilter_search' 'commun'
        Start-Sleep -Milliseconds 300
        $listed = (Get-ColumnFilterListText) -join ', '
        if ($listed -ne '✔Kiosques › Communs-Kiosques (1), ✔Postes › Communs (1), ✔Postes › Labo-Communs (1)') { $problems.Add("the list holds: $listed") }
        $hint = (Find-Control 'colfilter_hint').Current.Name
        if ($hint -ne 'OK : Emplacement contient « commun »') { $problems.Add("the hint says '$hint'") }
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-04, ORD-05, ORD-08') { $problems.Add("rows shown: $((Get-ResultName) -join ', ')") }
        # Opened again, it shows its text; one value unticked, only the others are kept, and there's no hint.
        Open-ColumnFilterList 'ShortPath'
        $search = (Find-Control 'colfilter_search').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($search -ne 'commun') { $problems.Add("opened again, the search holds '$search'") }
        Set-ColumnFilterTicked 'Postes › Communs', 'Postes › Labo-Communs'
        if (Find-ShownControl 'colfilter_hint') { $problems.Add('with a value unticked, the hint still shows') }
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-05, ORD-08') { $problems.Add("with one unticked, rows shown: $((Get-ResultName) -join ', ')") }
    }

    Invoke-Check 'Filtres: a new search clears them' {
        param($problems)
        Invoke-PrefixSearch 'ORD-0'
        if (((Get-ResultName) -join ', ') -ne $all) { $problems.Add("rows shown: $((Get-ResultName) -join ', ')") }
        $button = (Find-Control 'column_filters_text').Current.Name
        if ($button -ne 'Filtres') { $problems.Add("the button says '$button'") }
    }

    Invoke-Check 'Filtres: Nom filters by the text it contains, with no list' {
        param($problems)
        Open-ColumnFilterList 'ComputerName'
        $parts = Get-ColumnFilterPart
        if ($parts -ne 'search, hint') { $problems.Add("the filter shows: $parts") }
        Set-Text 'colfilter_search' '-03'
        Start-Sleep -Milliseconds 200
        $hint = (Find-Control 'colfilter_hint').Current.Name
        if ($hint -ne 'OK : Nom contient « -03 »') { $problems.Add("the hint says '$hint'") }
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-03') { $problems.Add("rows shown: $((Get-ResultName) -join ', ')") }
        # Emptied, it's no longer filtered.
        Open-ColumnFilterList 'ComputerName'
        Set-Text 'colfilter_search' ''
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne $all) { $problems.Add("with no text, rows shown: $((Get-ResultName) -join ', ')") }
    }

    Invoke-Check 'Filtres: Dernière connexion filters by how long ago, with or without Jamais' {
        param($problems)
        Open-ColumnFilterList 'LastLogon'
        $parts = Get-ColumnFilterPart
        if ($parts -ne 'age_number') { $problems.Add("the filter shows: $parts") }
        $shown = Get-ColumnFilterAge
        if ($shown -ne 'Plus de 90 jours On') { $problems.Add("at first, it says: $shown") }
        if ($ScreenshotDirectory) { Save-Screenshot 'filtre-date' }
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-03, ORD-05, ORD-07, ORD-09') { $problems.Add("90 days or more, rows shown: $((Get-ResultName) -join ', ')") }
        # Moins de leaves Jamais out; a number that isn't one can't be applied.
        Open-ColumnFilterList 'LastLogon'
        Select-ColumnFilterButton 'less'
        Set-Text 'colfilter_age_number' '0'
        Start-Sleep -Milliseconds 200
        if ((Find-Control 'colfilter_ok').Current.IsEnabled) { $problems.Add('with 0, OK can be clicked') }
        Set-Text 'colfilter_age_number' '1'
        Select-ColumnFilterButton 'unit1'
        $shown = Get-ColumnFilterAge
        if ($shown -ne 'Moins de 1 semaines Off') { $problems.Add("with Moins de and 1 semaines, it says: $shown") }
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-01, ORD-02, ORD-04, ORD-06') { $problems.Add("less than 1 week, rows shown: $((Get-ResultName) -join ', ')") }
        # Opened again, it shows what it filters by.
        Open-ColumnFilterList 'LastLogon'
        $shown = Get-ColumnFilterAge
        if ($shown -ne 'Moins de 1 semaines Off') { $problems.Add("opened again, it says: $shown") }
        Close-ColumnFilterList 'clear'
        if (((Get-ResultName) -join ', ') -ne $all) { $problems.Add("cleared, rows shown: $((Get-ResultName) -join ', ')") }
    }

    Invoke-Check 'Filtres: hiding a filtered column clears its filter' {
        param($problems)
        Open-ColumnFilterList 'Disabled'
        Set-ColumnFilterTicked 'Activé'
        Close-ColumnFilterList
        if (((Get-ResultName) -join ', ') -ne 'ORD-01, ORD-02, ORD-03, ORD-04, ORD-06, ORD-08') { $problems.Add("with Activé, rows shown: $((Get-ResultName) -join ', ')") }
        Invoke-ColumnMenuItem 'column_Disabled'
        try {
            if (((Get-ResultName) -join ', ') -ne $all) { $problems.Add("with Compte hidden, rows shown: $((Get-ResultName) -join ', ')") }
        }
        finally { Invoke-ColumnMenuItem 'column_reset' }
    }

    Invoke-Check 'Filtres: the button stays off after a restart' {
        param($problems)
        (Find-Control 'column_filters').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        $null = Wait-SavedAppearance { param($saved) @($saved.HiddenColumnFilters) -contains 'Computers' }
        Restart-App
        try {
            $state = (Find-Control 'column_filters').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
            if ($state -ne 'Off') { $problems.Add("after the restart, Filtres is $state") }
            Select-Domain 'demo.local'
            Invoke-PrefixSearch 'ORD-0'
            if (Find-ColumnFilterButton 'Description') { $problems.Add('after the restart, Description has its funnel') }
        }
        finally {
            # On again: apparence.json stays for the next sessions, whose checks open the funnels.
            $toggle = (Find-Control 'column_filters').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if ($toggle.Current.ToggleState -eq 'Off') { $toggle.Toggle() }
            $null = Wait-SavedAppearance { param($saved) @($saved.HiddenColumnFilters) -notcontains 'Computers' }
        }
    }
}

function Open-RestartDialog([string]$Name) {
    # Redémarrer… from the right-click menu, for that computer alone.
    Select-ResultRow $Name
    Invoke-ResultMenuItem 'Redémarrer…'
    $dialog = Wait-Dialog "Redémarrer $Name"
    Start-Sleep -Milliseconds 300
    $dialog
}

function Get-RestartPart($Dialog, [string]$AutomationId) {
    # A part of the restart dialog: its text (a text box's value, or a text's name).
    $part = Get-DialogPart $Dialog $AutomationId
    if (-not $part) { return $null }
    $value = $null
    if ($part.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$value)) { $value.Current.Value } else { $part.Current.Name }
}

function Test-RestartDialog {
    # Runs in a session of its own, from no saved defaults: it saves some, then restarts Repère to find them again.
    Remove-Item (Join-Path $testAppData 'Repere\redemarrage.json') -ErrorAction SilentlyContinue
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'
    $defaultMessage = 'Votre ordinateur va redémarrer dans {délai} (vers {heure}) pour une intervention du support informatique. Enregistrez votre travail.'

    Invoke-Check 'Redémarrer…: opens on 5 minutes and the default message, and Entrée picks Annuler' {
        param($problems)
        $dialog = Open-RestartDialog 'ORD-01'
        if ((Get-RestartPart $dialog 'restart_amount') -ne '5') { $problems.Add("the delay is '$(Get-RestartPart $dialog 'restart_amount')'") }
        if ((Get-ComboText 'restart_unit') -ne 'minutes') { $problems.Add("the unit is '$(Get-ComboText 'restart_unit')'") }
        if ((Get-RestartPart $dialog 'restart_message') -ne $defaultMessage) { $problems.Add("the message is '$(Get-RestartPart $dialog 'restart_message')'") }
        $preview = Get-RestartPart $dialog 'restart_preview'
        if ($preview -notlike 'Votre ordinateur va redémarrer dans 5 minutes (vers * h *) pour une intervention du support informatique. Enregistrez votre travail.') { $problems.Add("the preview is '$preview'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'redemarrer' $dialog }
        (Get-DialogPart $dialog 'restart_amount').SetFocus()
        Send-Key 0x0D $dialog
        Wait-DialogsClosed
        if (Wait-AnyDialog) { $problems.Add('a report opened: Entrée restarted the computer') }
    }

    Invoke-Check "Redémarrer…: a delay that isn't a number or is over 7 days greys out Redémarrer, 0 warns" {
        param($problems)
        $dialog = Open-RestartDialog 'ORD-01'
        $cases = @(
            @{ Amount = 'abc'; Unit = 'minutes'; Enabled = $false; Problem = 'Entrez un délai en nombre entier.' }
            @{ Amount = '8'; Unit = 'jours'; Enabled = $false; Problem = 'Le délai est de 7 jours au plus.' }
            @{ Amount = '0'; Unit = 'minutes'; Enabled = $true; Problem = "Redémarrage immédiat : l'utilisateur n'aura pas le temps de lire le message." }
            @{ Amount = '7'; Unit = 'jours'; Enabled = $true; Problem = $null }
        )
        foreach ($case in $cases) {
            Select-ComboItem 'restart_unit' $case.Unit
            (Get-DialogPart $dialog 'restart_amount').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($case.Amount)
            Start-Sleep -Milliseconds 200
            $enabled = (Get-DialogPart $dialog 'restart_ok').Current.IsEnabled
            $problem = Get-RestartPart $dialog 'restart_problem'
            if ($enabled -ne $case.Enabled -or $problem -ne $case.Problem) {
                $problems.Add("$($case.Amount) $($case.Unit): Redémarrer enabled is $enabled, problem '$problem'")
            }
        }
        Close-Dialog $dialog 'restart_cancel'
    }

    Invoke-Check 'Redémarrer…: 2 heures gives /t 7200, with the delay and the time written in the message' {
        param($problems)
        $dialog = Open-RestartDialog 'ORD-01'
        Select-ComboItem 'restart_unit' 'heures'
        (Get-DialogPart $dialog 'restart_amount').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('2')
        Start-Sleep -Milliseconds 200
        Invoke-Element (Get-DialogPart $dialog 'restart_ok')
        $report = Wait-Dialog 'Redémarrer'
        $text = Get-DialogText $report
        $expected = "AD fictif : rien n'est lancé.*shutdown.exe /r /f /m \\ord-01.demo.local /t 7200 /c `"Votre ordinateur va redémarrer dans 2 heures (vers *h*) pour une intervention du support informatique. Enregistrez votre travail.`""
        if ($text -notlike $expected) { $problems.Add("the report says '$text'") }
        Close-Dialog $report 'dialog_cancel'
    }

    Invoke-Check 'Redémarrer…: the defaults saved come back after a restart of Repère' {
        param($problems)
        $dialog = Open-RestartDialog 'ORD-01'
        Select-ComboItem 'restart_unit' 'heures'
        (Get-DialogPart $dialog 'restart_amount').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('1')
        (Get-DialogPart $dialog 'restart_message').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Redémarrage dans {délai}, à {heure}.')
        (Get-DialogPart $dialog 'restart_save').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Invoke-Element (Get-DialogPart $dialog 'restart_ok')
        $report = Wait-Dialog 'Redémarrer'
        if ((Get-DialogText $report) -notlike '*/t 3600 /c "Redémarrage dans 1 heure, à * h *."') { $problems.Add("the report says '$(Get-DialogText $report)'") }
        Close-Dialog $report 'dialog_cancel'

        Restart-App
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-0'
        $dialog = Open-RestartDialog 'ORD-01'
        $amount = Get-RestartPart $dialog 'restart_amount'
        $unit = Get-ComboText 'restart_unit'
        $message = Get-RestartPart $dialog 'restart_message'
        if ($amount -ne '1' -or $unit -ne 'heures' -or $message -ne 'Redémarrage dans {délai}, à {heure}.') { $problems.Add("after a restart, the dialog holds $amount $unit and '$message'") }
        Close-Dialog $dialog 'restart_cancel'
    }
}

function Read-Export {
    # The exported file's rows, read as Excel would: the culture's list separator, UTF-8.
    @(Import-Csv -LiteralPath $exportFile -Delimiter (Get-Culture).TextInfo.ListSeparator -Encoding utf8)
}

function Test-UnusedBox {
    # The search field's boxes a search type doesn't use are hidden, the other across the field, and what was typed in
    # them is back with them. The other boxes a choice makes useless (#183) are disabled, with why for Narrator (its
    # help text); back in use, a box has its own tooltip again, which UI Automation gives as its help text. How it's
    # greyed is drawn by the TextBox style, out of UI Automation's reach: see the screenshots.
    $state = {
        param($Element)
        $value = try { $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { '?' }
        '{0} | {1} | {2}' -f $(if ($Element.Current.IsEnabled) { 'used' } else { 'unused' }), $Element.Current.HelpText, $value
    }
    # The field's two boxes side by side: the width one box alone takes, more or less (the divider between them).
    $both = 0
    $searchState = {
        param([string]$Id)
        # A collapsed box isn't in UI Automation's tree at all.
        $element = $window.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $Id))
        if (-not $element -or $element.Current.IsOffscreen) { return 'hidden' }
        $value = try { $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { '?' }
        $wide = if ($element.Current.BoundingRectangle.Width -gt $both * 0.9) { 'wide' } else { 'half' }
        'shown | {0} | {1}' -f $wide, $value
    }

    Invoke-Check 'Ordinateurs: Sans description and Liste de noms hide the box they don''t use, the other across the field, and keep its text' {
        param($problems)
        Select-SearchType 'Description contient'
        Set-Text 'prefix' 'ORD'
        Set-Text 'search_term' 'salle'
        $both = (Find-Control 'prefix').Current.BoundingRectangle.Width + (Find-Control 'search_term').Current.BoundingRectangle.Width
        $expected = [ordered]@{
            'Sans description'     = 'shown | wide | ORD', 'hidden'
            'Liste de noms'        = 'hidden', 'shown | wide | salle'
            'Description contient' = 'shown | half | ORD', 'shown | half | salle'
        }
        foreach ($type in $expected.Keys) {
            Select-SearchType $type
            Start-Sleep -Milliseconds 300
            $shown = (. $searchState 'prefix'), (. $searchState 'search_term')
            for ($i = 0; $i -lt 2; $i++) {
                if ($shown[$i] -ne $expected[$type][$i]) { $problems.Add("$type, $(('prefix', 'search_term')[$i]): '$($shown[$i])', expected '$($expected[$type][$i])'") }
            }
            if ($ScreenshotDirectory -and $type -ne 'Description contient') { Save-Screenshot "recherche-$($type -replace ' ', '-')" }
        }
        Set-Text 'prefix' ''
        Set-Text 'search_term' ''
    }

    Invoke-Check 'Nouveau mot de passe…: the Autre box is unused until Autre is chosen, hidden, and its eye shows what was typed' {
        param($problems)
        Show-UserPage
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'lperrin'
        Select-UserRow 'Léa Perrin'
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        # A password box: UI Automation doesn't give what's typed, only the eye shows it.
        $box = Get-DialogPart $dialog 'reset_custom_value'
        $use = { param($Element) '{0} | {1}' -f $(if ($Element.Current.IsEnabled) { 'used' } else { 'unused' }), $Element.Current.HelpText }
        $why = 'Choisissez « Autre » pour taper le mot de passe.'
        if (-not $box.Current.IsPassword) { $problems.Add("the Autre box isn't a password box") }
        if ((& $use $box) -ne "unused | $why") { $problems.Add("at first: '$(& $use $box)'") }
        $eye = Get-DialogPart $dialog 'reset_custom_show'
        if ($eye -and -not $eye.Current.IsOffscreen) { $problems.Add('at first, the eye is shown') }
        (Get-DialogPart $dialog 'reset_custom').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Sauvegarde-2026')
        if ((& $use $box) -ne 'used | ') { $problems.Add("Autre chosen: '$(& $use $box)'") }
        (Get-DialogPart $dialog 'reset_generated').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        if ((& $use $box) -ne "unused | $why") { $problems.Add("back on generated: '$(& $use $box)'") }
        (Get-DialogPart $dialog 'reset_custom').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        Invoke-Element (Get-DialogPart $dialog 'reset_custom_show')
        Start-Sleep -Milliseconds 300
        $plain = Get-DialogPart $dialog 'reset_custom_text'
        $shown = if ($plain) { $plain.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
        if ($shown -ne 'Sauvegarde-2026') { $problems.Add("the eye shows '$shown', not what was typed before generated was chosen") }
        Invoke-Element (Get-DialogPart $dialog 'reset_custom_hide')
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPart $dialog 'reset_custom_text') -or -not (Get-DialogPart $dialog 'reset_custom_show')) { $problems.Add('after hiding it, the password is still shown') }
        Close-Dialog $dialog 'dialog_cancel'
        Invoke-Element (Find-Control 'tab_computers')
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Prochain nom: Commencer à is unused in random order' {
        param($problems)
        $dialog = Open-NextName
        (Get-DialogPart $dialog 'next_options').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 300
        $from = Get-DialogPart $dialog 'next_from'
        $order = Get-DialogPart $dialog 'next_order'
        $pick = {
            param([string]$Name)
            $expand = $order.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            $expand.Expand()
            Start-Sleep -Milliseconds 200
            $order.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Name)).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
            $expand.Collapse()
            Start-Sleep -Milliseconds 300
        }
        $tip = 'Un nom de la série, ex. ORD-0500'
        if ((& $state $from) -ne "used | $tip | ") { $problems.Add("Séquentiel: '$(& $state $from)'") }
        & $pick 'Aléatoire'
        if ((& $state $from) -ne 'unused | En ordre aléatoire, il n''y a pas de point de départ. | ') { $problems.Add("Aléatoire: '$(& $state $from)'") }
        & $pick 'Séquentiel'
        if ((& $state $from) -ne "used | $tip | ") { $problems.Add("back on Séquentiel: '$(& $state $from)'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-Copy {
    # What a search leaves selected, then what the Copier items copy. A drag on a cell's text takes a real mouse, which
    # these tests don't use.
    Select-Domain 'demo.local'
    Invoke-Check 'A search selects nothing, then ↓ starts from the first row and ↑ from the last; one result is also checked, without a toast' {
        param($problems)
        Invoke-PrefixSearch 'ORD-01'
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne 'Aucune sélection') { $problems.Add("selection text is '$selection'") }
        if ((Find-Control 'act_rdp').Current.IsEnabled) { $problems.Add('Bureau à distance is enabled after the search') }
        for ($i = 0; $i -lt 30 -and ((Get-ResultRow) -join ' | ') -notlike '*✔*'; $i++) { Start-Sleep -Milliseconds 100 }
        $row = (Get-ResultRow) -join ' | '
        if ($row -notlike '*✔ 10.0.1.11*') { $problems.Add("the row says '$row'") }
        if (Find-ShownControl 'action_notice') { $problems.Add('a toast shows') }
        Invoke-PrefixSearch 'ORD-1'
        if ((Get-ColumnHeader) -like '*En ligne*') { $problems.Add('En ligne stays after the lone result') }
        $rows = @(Get-ResultRow)
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne 'Aucune sélection') { $problems.Add("with several results, selection text is '$selection'") }
        # Suppr right after the search: no row was chosen, so nothing is asked.
        $queriesBefore = @(Get-LoggedQuery).Count
        Send-Key 0x2E # Suppr
        $dialog = Wait-AnyDialog
        if ($dialog) {
            $problems.Add("Suppr after the search opened '$($dialog.Current.Name)'")
            Close-Dialog $dialog 'dialog_cancel'
        }
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*') { $problems.Add('a computer was removed') }
        Send-Key 0x28 # ↓
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne "$($rows[0][1]) sélectionné") { $problems.Add("after ↓, selection text is '$selection'") }
        Send-Key 0x28 # ↓
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne "$($rows[1][1]) sélectionné") { $problems.Add("after ↓ ↓, selection text is '$selection'") }
        # The same search again: nothing selected, and ↑ starts from the last row.
        Invoke-PrefixSearch 'ORD-1'
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne 'Aucune sélection') { $problems.Add("after the search again, selection text is '$selection'") }
        Send-Key 0x26 # ↑
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne "$($rows[-1][1]) sélectionné") { $problems.Add("after ↑, selection text is '$selection'") }
        # Début starts from the first row too.
        Invoke-PrefixSearch 'ORD-1'
        Send-Key 0x24 # Début
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne "$($rows[0][1]) sélectionné") { $problems.Add("after Début, selection text is '$selection'") }
    }
    Invoke-Check 'Copier: the names on one line, and the whole rows' {
        param($problems)
        Select-ResultRow 'ORD-10'
        Add-ResultRow 'ORD-11'
        Set-Clipboard -Value 'avant'
        $null = Open-ResultMenu
        $item = @(Open-MenuGroup 'Copier' | Where-Object { $_.Current.Name -eq 'Copier les noms sur une ligne' })[0]
        $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 400
        Close-Menu
        $copied = (Get-Clipboard) -join ' | '
        if ($copied -ne 'ORD-10, ORD-11') { $problems.Add("on one line: '$copied'") }
        Set-Clipboard -Value 'avant'
        $null = Open-ResultMenu
        $item = @(Open-MenuGroup 'Copier' | Where-Object { $_.Current.Name -eq 'Copier les lignes' })[0]
        $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 400
        Close-Menu
        $lines = @(Get-Clipboard | Where-Object { $_ })
        if ($lines.Count -ne 2) { $problems.Add("$($lines.Count) lines copied") }
        foreach ($line in $lines) {
            $columns = $line -split "`t"
            if ($columns.Count -ne 9 -or $columns[0] -notin 'ORD-10', 'ORD-11' -or $columns[6] -ne 'demo.local') { $problems.Add("a line says '$line'") }
        }
    }
    Invoke-Check 'A notice shows under the results, not over them, and the last selected row stays in view' {
        param($problems)
        # A short window, so the results go past the bottom of the grid: the bar would hide the last row that shows.
        $transform = $window.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern)
        $size = $window.Current.BoundingRectangle
        $transform.Resize($size.Width, 520)
        try {
            Invoke-PrefixSearch 'ORD'
            $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
            $before = (Find-Control 'data_grid').Current.BoundingRectangle
            $last = @(Get-ResultRowElement | Where-Object { -not $_.Current.IsOffscreen -and $_.Current.BoundingRectangle.Bottom -le $before.Bottom + 1 }) |
                Sort-Object { $_.Current.BoundingRectangle.Bottom } | Select-Object -Last 1
            $name = @($last.FindAll($Descendants, $isCell))[1].Current.Name
            Select-ResultRow $name
            Invoke-Element (Find-Control 'act_ping')
            for ($i = 0; $i -lt 30 -and -not (Find-ShownControl 'action_notice'); $i++) { Start-Sleep -Milliseconds 100 }
            $notice = Find-ShownControl 'action_notice'
            if (-not $notice) { throw 'no notice after Vérifier en ligne' }
            Start-Sleep -Milliseconds 400
            $after = (Find-Control 'data_grid').Current.BoundingRectangle
            $bar = $notice.Current.BoundingRectangle
            if ($bar.Top -lt $after.Bottom) { $problems.Add("the notice (top $($bar.Top)) is over the grid (bottom $($after.Bottom))") }
            if ($after.Bottom -ge $before.Bottom) { $problems.Add("the grid kept its height ($($before.Bottom) → $($after.Bottom))") }
            $row = @(Get-ResultRowElement | Where-Object { @($_.FindAll($Descendants, $isCell))[1].Current.Name -eq $name })[0]
            $rect = if ($row) { $row.Current.BoundingRectangle }
            if (-not $row -or $row.Current.IsOffscreen -or $rect.Bottom -gt $after.Bottom + 1 -or $rect.Top -lt $after.Top) {
                $problems.Add("$name, the last row shown, is cut or hidden once the notice shows")
            }
        }
        finally { $transform.Resize($size.Width, $size.Height) }
    }
    Invoke-Check 'Utilisateurs: a search selects nothing, ↓ selects the result, and Copier les lignes copies it' {
        param($problems)
        Invoke-Element (Find-Control 'tab_users')
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'lperrin'
        $selection = (Find-Control 'user_selection').Current.Name
        if ($selection -ne 'Aucune sélection') { $problems.Add("after the search, selection text is '$selection'") }
        Send-Key 0x28 # ↓
        $selection = (Find-Control 'user_selection').Current.Name
        if ($selection -ne 'Léa Perrin sélectionné') { $problems.Add("after ↓, selection text is '$selection'") }
        Set-Clipboard -Value 'avant'
        $item = Open-UserMenuItem 'Copier les lignes'
        $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 400
        $copied = (Get-Clipboard) -join ' | '
        if (($copied -split "`t").Count -ne 12 -or ($copied -split "`t")[1] -ne 'lperrin') { $problems.Add("copied: '$copied'") }
    }
}

function Test-CopyButton {
    # A copy button says what its copy did, where it was clicked (#200): « Copié » for 1.5 seconds, on the last one
    # clicked only, and « Copie impossible » when another program holds the clipboard, with nothing copied then.
    # Supprimer de l'AD's keys too, kept out of the clipboard history (#228).
    # Each check searches its own computer: the grid only shows UI Automation the rows on screen.
    Select-Domain 'demo.local'
    $keyCopy = 'Copier le mot de passe de récupération'
    Invoke-Check 'Clés BitLocker: the key copied says « Copié » on its button, only the last one, then its copy icon is back' {
        param($problems)
        Invoke-PrefixSearch 'ORD-09'
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem 'Clés BitLocker…'
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        Set-Clipboard -Value 'avant'
        Invoke-Element (Get-DialogPart $dialog 'bitlocker_copy_0')
        Start-Sleep -Milliseconds 300
        if ((Get-Clipboard) -ne '418649-302104-655721-128930-583011-472560-090288-361757') { $problems.Add("the first key's button copied '$(Get-Clipboard)'") }
        $name = Get-DialogPartName $dialog 'bitlocker_copy_0'
        if ($name -ne 'Copié') { $problems.Add("after the copy, its button says '$name'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'cle-bitlocker-copiee' $dialog }
        $footer = Get-DialogPartName $dialog 'bitlocker_selection'
        if ($footer -ne 'Mot de passe de la clé 6F1C2E7A copié') { $problems.Add("the footer says '$footer'") }
        # Another key within the 1.5 seconds: the first button is back at once, the second says it.
        Invoke-Element (Get-DialogPart $dialog 'bitlocker_copy_1')
        Start-Sleep -Milliseconds 300
        $names = (Get-DialogPartName $dialog 'bitlocker_copy_0'), (Get-DialogPartName $dialog 'bitlocker_copy_1')
        if ($names[0] -ne $keyCopy -or $names[1] -ne 'Copié') { $problems.Add("after the second key's copy, the buttons say '$($names -join ' | ')'") }
        if ((Get-Clipboard) -notlike '207152-*') { $problems.Add("the second key's button copied '$(Get-Clipboard)'") }
        Start-Sleep -Milliseconds 1700
        $name = Get-DialogPartName $dialog 'bitlocker_copy_1'
        if ($name -ne $keyCopy) { $problems.Add("2 seconds later, its button says '$name'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
    Invoke-Check 'Clés BitLocker: with the clipboard held by another program, « Copie impossible » and the key not copied' {
        param($problems)
        Invoke-PrefixSearch 'ORD-09'
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem 'Clés BitLocker…'
        $dialog = Wait-Dialog 'Clés BitLocker'
        Start-Sleep -Milliseconds 300
        Set-Clipboard -Value 'avant'
        if (-not [RepereClipboard]::OpenClipboard([IntPtr]::Zero)) { throw 'The test could not hold the clipboard.' }
        try {
            Invoke-Element (Get-DialogPart $dialog 'bitlocker_copy_0')
            # WPF tries for about a second before it gives up.
            for ($i = 0; $i -lt 30 -and (Get-DialogPartName $dialog 'bitlocker_copy_0') -ne 'Copie impossible'; $i++) { Start-Sleep -Milliseconds 100 }
            $name = Get-DialogPartName $dialog 'bitlocker_copy_0'
            if ($name -ne 'Copie impossible') { $problems.Add("its button says '$name'") }
            if ($ScreenshotDirectory) { Save-Screenshot 'cle-bitlocker-copie-impossible' $dialog }
            $footer = Get-DialogPartName $dialog 'bitlocker_selection'
            if ($footer -ne 'Clé 6F1C2E7A non copiée : presse-papiers occupé par un autre programme') { $problems.Add("the footer says '$footer'") }
        }
        finally { $null = [RepereClipboard]::CloseClipboard() }
        if ((Get-Clipboard) -ne 'avant') { $problems.Add("the clipboard holds '$(Get-Clipboard)'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
    Invoke-Check "Supprimer de l'AD: the keys shown are copied as a secret, by Copier and Ctrl+C, and not at all with the clipboard held" {
        param($problems)
        Add-Type -AssemblyName System.Windows.Forms
        Invoke-PrefixSearch 'ORD-09'
        $dialog = Open-ActionDialog 'ORD-09' "Supprimer de l'AD…" "Supprimer de l'AD" "Supprimer ORD-09 de l'AD ?*"
        # Closed even when a step fails, so the next checks don't open their windows behind it.
        try {
            $details = Get-DialogPart $dialog 'dialog_details'
            $keys = $details.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            # Kept out of the clipboard history: copied with the formats Windows reads for that (Set-SecretClipboard).
            $copiedAsSecret = {
                param([string]$How)
                $copied = "$(Get-Clipboard -Raw)" -replace "`r", ''
                if ($copied -ne ($keys -replace "`r", '')) { $problems.Add("$How copied '$copied'") }
                elseif (-not [System.Windows.Forms.Clipboard]::ContainsData('ExcludeClipboardContentFromMonitorProcessing')) { $problems.Add("$How copied the keys where the clipboard history keeps them") }
            }
            Set-Clipboard -Value 'avant'
            Invoke-Element (Get-DialogPart $dialog 'dialog_details_copy')
            # The feedback can take a moment to reach UI Automation: waited for, as with the clipboard held below.
            for ($i = 0; $i -lt 30 -and (Get-DialogPartName $dialog 'dialog_details_copy') -ne 'Copié'; $i++) { Start-Sleep -Milliseconds 100 }
            & $copiedAsSecret 'Copier'
            $name = Get-DialogPartName $dialog 'dialog_details_copy'
            if ($name -ne 'Copié') { $problems.Add("after the copy, Copier says '$name'") }
            # Nothing selected: Ctrl+C copies all of it, as Copier does.
            Set-Clipboard -Value 'avant'
            $details.SetFocus()
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            Start-Sleep -Milliseconds 300
            & $copiedAsSecret 'Ctrl+C'
            Set-Clipboard -Value 'avant'
            if (-not [RepereClipboard]::OpenClipboard([IntPtr]::Zero)) { throw 'The test could not hold the clipboard.' }
            try {
                Invoke-Element (Get-DialogPart $dialog 'dialog_details_copy')
                for ($i = 0; $i -lt 30 -and (Get-DialogPartName $dialog 'dialog_details_copy') -ne 'Copie impossible'; $i++) { Start-Sleep -Milliseconds 100 }
                $name = Get-DialogPartName $dialog 'dialog_details_copy'
                if ($name -ne 'Copie impossible') { $problems.Add("with the clipboard held, Copier says '$name'") }
            }
            finally { $null = [RepereClipboard]::CloseClipboard() }
            if ((Get-Clipboard -Raw) -ne 'avant') { $problems.Add("with the clipboard held, it then holds '$(Get-Clipboard -Raw)'") }
        }
        finally { Close-Dialog $dialog 'dialog_cancel' }
    }
    Invoke-Check 'Mot de passe LAPS: the password copied says « Copié » on its button' {
        param($problems)
        Invoke-PrefixSearch 'ORD-01'
        $dialog = Open-ActionDialog 'ORD-01' 'Mot de passe LAPS…' 'Mot de passe LAPS' '*ORD-01*'
        Set-Clipboard -Value 'avant'
        Invoke-Element (Get-DialogPart $dialog 'laps_copy_0')
        Start-Sleep -Milliseconds 300
        if ((Get-Clipboard) -ne 'Vq7#mR2t!xL9pW4z') { $problems.Add("its button copied '$(Get-Clipboard)'") }
        $name = Get-DialogPartName $dialog 'laps_copy_0'
        if ($name -ne 'Copié') { $problems.Add("after the copy, its button says '$name'") }
        $footer = Get-DialogPartName $dialog 'laps_status'
        if ($footer -ne 'Mot de passe de ORD-01 copié.') { $problems.Add("the footer says '$footer'") }
        Start-Sleep -Milliseconds 1700
        $name = Get-DialogPartName $dialog 'laps_copy_0'
        if ($name -ne 'Copier le mot de passe') { $problems.Add("2 seconds later, its button says '$name'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
    Invoke-Check 'Propriétés: a value copied says « Copié » on its Copier button, as Copier for the whole window does' {
        param($problems)
        Invoke-Element (Find-Control 'tab_users')
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        Invoke-Element (Get-DialogPart $details 'user_detail_copy_mail')
        Start-Sleep -Milliseconds 300
        $name = Get-DialogPartName $details 'user_detail_copy_mail'
        if ($name -ne 'Copié') { $problems.Add("Courriel's button says '$name'") }
        Invoke-Element (Get-DialogPart $details 'user_detail_copy')
        Start-Sleep -Milliseconds 300
        $names = (Get-DialogPartName $details 'user_detail_copy_mail'), (Get-DialogPartName $details 'user_detail_copy')
        if ($names[0] -ne 'Copier Courriel' -or $names[1] -ne 'Copié') { $problems.Add("after Copier, the buttons say '$($names -join ' | ')'") }
        Close-UserDetail $details
    }
}

function Test-Export {
    # Repère saves to $env:REPERE_EXPORT_PATH instead of asking where.
    Select-Domain 'demo.local'
    Invoke-Check 'Exporter: disabled without rows to save' {
        param($problems)
        Invoke-PrefixSearch 'XYZ'
        if ((Find-Control 'export').Current.IsEnabled) { $problems.Add('Exporter is enabled with 0 ordinateur') }
    }

    Invoke-Check 'Exporter: the rows shown, in their order, as CSV for Excel (UTF-8 with BOM, the list separator)' {
        param($problems)
        Remove-Item $exportFile -ErrorAction SilentlyContinue
        Invoke-PrefixSearch 'ORD-0'
        try {
            Set-Text 'filter' 'salle'
            $shown = @(Get-ResultRow | ForEach-Object { $_[1] })
            Invoke-Element (Find-Control 'export')
            for ($i = 0; $i -lt 20 -and -not (Test-Path $exportFile); $i++) { Start-Sleep -Milliseconds 150 }
            if (-not (Test-Path $exportFile)) { throw 'no file was saved' }
            $bytes = [IO.File]::ReadAllBytes($exportFile)
            if ($bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { $problems.Add('the file has no UTF-8 BOM') }
            $separator = (Get-Culture).TextInfo.ListSeparator
            $header = (Get-Content -LiteralPath $exportFile -Encoding utf8 -TotalCount 1)
            $expectedHeader = @('Nom', 'Description', 'Compte', 'Système', 'Version de Windows', 'Dernière connexion', 'Domaine', 'Emplacement', 'Nom distinctif') -join $separator
            if ($header -ne $expectedHeader) { $problems.Add("the header is '$header', expected '$expectedHeader'") }
            $rows = Read-Export
            $names = @($rows | ForEach-Object Nom)
            if (($names -join ', ') -ne ($shown -join ', ')) { $problems.Add("rows saved: $($names -join ', '); shown: $($shown -join ', ')") }
            $row = @($rows | Where-Object Nom -eq 'ORD-02')[0]
            if (-not $row -or $row.'Compte' -ne 'Activé' -or $row.'Système' -ne 'Win 11 24H2' -or $row.'Version de Windows' -ne 'Windows 11 Professionnel 10.0 (26100)' -or
                $row.'Dernière connexion' -notmatch '^\d{4}-\d\d-\d\d \d\d:\d\d$' -or $row.Emplacement -ne 'demo.local/Postes' -or $row.'Nom distinctif' -ne 'CN=ORD-02,OU=Postes,DC=demo,DC=local') {
                $problems.Add("ORD-02 is saved as: $($row | ConvertTo-Json -Compress)")
            }
            $note = (Find-Control 'search_time').Current.Name
            if ($note -ne "· $($shown.Count) lignes exportées") { $problems.Add("the note says '$note'") }
        }
        finally { Set-Text 'filter' '' }
    }

    Invoke-Check 'Exporter: a computer that never logged on has an empty date and no Windows version' {
        param($problems)
        Remove-Item $exportFile -ErrorAction SilentlyContinue
        Invoke-PrefixSearch 'ORD-03'
        Invoke-Element (Find-Control 'export')
        for ($i = 0; $i -lt 20 -and -not (Test-Path $exportFile); $i++) { Start-Sleep -Milliseconds 150 }
        $row = @(Read-Export)[0]
        if (-not $row -or $row.Nom -ne 'ORD-03' -or $row.'Dernière connexion' -or $row.'Système' -or $row.Description) { $problems.Add("ORD-03 is saved as: $($row | ConvertTo-Json -Compress)") }
        $note = (Find-Control 'search_time').Current.Name
        if ($note -ne '· 1 ligne exportée') { $problems.Add("the note says '$note'") }
    }
}

function Get-DialogRow($Dialog) {
    # The rows of a dialog's grid, top to bottom: each row's cell texts, joined with « | ».
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    @($Dialog.FindAll($Descendants, $isRow) | Sort-Object { $_.Current.BoundingRectangle.Top } | ForEach-Object {
        (@($_.FindAll($Descendants, $isCell) | ForEach-Object { $_.Current.Name })) -join ' | '
    })
}

function Test-GroupsDialog {
    # The fake AD's groups: ORD-01 is in two global groups and a distribution list, and through one of them in a domain
    # local group and in a universal group of nord.demo.local (read in that domain); ORD-04 is in that universal group;
    # ORD-03 is in no group but its primary one.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'
    $primary = 'Ordinateurs du domaine | Sécurité | Globale | Principale | demo.local | Tous les ordinateurs joints au domaine'
    $groupsChecks = @(
        @{ Name = 'ORD-01'; Via = 'menu'; Rows = @(
            'GG-Logiciel-Office | Sécurité | Globale | Directe | demo.local | Déploiement de Microsoft 365 Apps'
            "GG-Postes-Accueil | Sécurité | Globale | Directe | demo.local | Postes de l'accueil"
            'Liste-Inventaire | Distribution | Globale | Directe | demo.local | Inventaire annuel'
            $primary
            "DL-Imprimantes-Accueil | Sécurité | Domaine local | Héritée | demo.local | Accès aux imprimantes de l'accueil"
            "GU-Postes-Nord | Sécurité | Universelle | Héritée | nord.demo.local | Postes gérés par l'équipe Nord") }
        @{ Name = 'ORD-04'; Via = 'act_groups'; Rows = @(
            'GG-GPO-Kiosques | Sécurité | Globale | Directe | demo.local | Filtre de la GPO des kiosques'
            "GU-Postes-Nord | Sécurité | Universelle | Directe | nord.demo.local | Postes gérés par l'équipe Nord"
            $primary) }
        @{ Name = 'ORD-03'; Via = 'act_groups'; Rows = @(, $primary) }
    )
    foreach ($groupsCheck in $groupsChecks) {
        Invoke-Check "Groupes… ($(if ($groupsCheck.Via -eq 'menu') { 'right-click menu' } else { 'action bar' })) lists $($groupsCheck.Name)'s groups: direct, primary and inherited" {
            param($problems)
            $queriesBefore = @(Get-LoggedQuery).Count
            Select-ResultRow $groupsCheck.Name
            if ($groupsCheck.Via -eq 'menu') { Invoke-ResultMenuItem 'Groupes…' } else { Invoke-Element (Find-Control 'act_groups') }
            $dialog = Wait-Dialog "Groupes de $($groupsCheck.Name)"
            Start-Sleep -Milliseconds 300
            $rows = @(Get-DialogRow $dialog)
            if (($rows -join "`n") -ne ($groupsCheck.Rows -join "`n")) { $problems.Add("rows: $($rows -join ' // ')") }
            if ($groupsCheck.Name -eq 'ORD-01') {
                if ($ScreenshotDirectory) { Save-Screenshot 'groupes' $dialog }
                (Get-DialogPart $dialog 'groups_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('imprimantes')
                Start-Sleep -Milliseconds 300
                $filtered = @(Get-DialogRow $dialog)
                if ($filtered.Count -ne 1 -or $filtered[0] -notlike 'DL-Imprimantes-Accueil | *') { $problems.Add("filtered on 'imprimantes': $($filtered -join ' // ')") }
            }
            $writes = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -notlike 'Get-*')
            if ($writes.Count) { $problems.Add("AD was changed: $(($writes | ForEach-Object Command) -join ', ')") }
            Close-Dialog $dialog 'dialog_cancel'
        }
    }
}

function Select-DialogRow($Dialog, [string]$FirstCell) {
    # Selects the row of a dialog's grid whose first cell is that text.
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    $row = @($Dialog.FindAll($Descendants, $isRow) | Where-Object { $_.FindFirst($Descendants, $isCell).Current.Name -eq $FirstCell })[0]
    if (-not $row) { throw "No '$FirstCell' row." }
    $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 200
}

function Wait-ReportDialog {
    # The dialog that reports an action (it has a message), once the one before it has closed.
    for ($i = 0; $i -lt 20; $i++) {
        foreach ($top in Get-AppWindow) {
            if (Get-DialogPart $top 'dialog_message') { return $top }
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'No report dialog opened.'
}

function Test-ShadowSession {
    # quser on the fake computers: ORD-01 has accueil at the desk (active) and Jean Bertrand's disconnected session (jebertrand),
    # ORD-04 its kiosk account over Remote Desktop, nobody is logged on ORD-08, ORD-06 refuses the query, and ORD-10
    # doesn't answer. With the fake AD, mstsc isn't started: the report shows its command. Utilisateurs connectés… reads
    # the same sessions.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD'

    Invoke-Check "Prendre la main… lists ORD-01's sessions, selects the active one, won't join a disconnected one, and can only watch" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-01'
        Invoke-ResultMenuItem 'Prendre la main…'
        $dialog = Wait-Dialog 'Prendre la main'
        Start-Sleep -Milliseconds 300
        $question = (Get-DialogPart $dialog 'shadow_question').Current.Name
        if ($question -ne '2 sessions sont ouvertes sur ORD-01 :') { $problems.Add("the question is '$question'") }
        $rows = @(Get-DialogRow $dialog)
        if ($rows.Count -ne 2 -or $rows[0] -notlike 'accueil | console | 1 | Actif | 12 | *' -or $rows[1] -notlike 'jebertrand | * | 3 | Déco | 1:05 | *') { $problems.Add("rows: $($rows -join ' // ')") }
        $queries = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'quser')
        if ($queries.Count -ne 1 -or $queries[0].Server -ne 'ord-01.demo.local') { $problems.Add("quser queries: $(($queries | ForEach-Object Server) -join ', ')") }
        if (-not (Get-DialogPart $dialog 'shadow_ok').Current.IsEnabled) { $problems.Add('Prendre la main is disabled for the active session') }
        if ($ScreenshotDirectory) { Save-Screenshot 'prendre-la-main' $dialog }

        Select-DialogRow $dialog 'jebertrand'
        if ((Get-DialogPart $dialog 'shadow_ok').Current.IsEnabled) { $problems.Add('Prendre la main is enabled for a disconnected session') }
        $problem = (Get-DialogPart $dialog 'shadow_problem').Current.Name
        if ($problem -notlike 'La session de jebertrand est déconnectée*') { $problems.Add("the problem says '$problem'") }

        Select-DialogRow $dialog 'accueil'
        (Get-DialogPart $dialog 'shadow_control').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Invoke-Element (Get-DialogPart $dialog 'shadow_ok')
        $report = Wait-ReportDialog
        $text = Get-DialogText $report
        if ($text -notlike "AD fictif : rien n'est lancé.*mstsc.exe /v:ord-01.demo.local /shadow:1" ) { $problems.Add("the report says '$text'") }
        Close-Dialog $report 'dialog_cancel'
    }

    Invoke-Check "Prendre la main… joins ORD-04's Remote Desktop session with control" {
        param($problems)
        Select-ResultRow 'ORD-04'
        Invoke-ResultMenuItem 'Prendre la main…'
        $dialog = Wait-Dialog 'Prendre la main'
        Start-Sleep -Milliseconds 300
        $question = (Get-DialogPart $dialog 'shadow_question').Current.Name
        if ($question -ne 'Une session est ouverte sur ORD-04 :') { $problems.Add("the question is '$question'") }
        Invoke-Element (Get-DialogPart $dialog 'shadow_ok')
        $report = Wait-ReportDialog
        $text = Get-DialogText $report
        if ($text -notlike "AD fictif : rien n'est lancé.*mstsc.exe /v:ord-04.demo.local /shadow:2 /control") { $problems.Add("the report says '$text'") }
        Close-Dialog $report 'dialog_cancel'
    }

    $shadowReports = @(
        @{ Name = 'ORD-08'; What = 'says nobody is logged on'; Expected = "ORD-08 : Personne n'a de session ouverte sur cet ordinateur." }
        @{ Name = 'ORD-06'; What = 'says access is denied'; Expected = "✖ ORD-06 : Accès refusé : il faut être administrateur de l'ordinateur.*Erreur 0x00000005*" }
        @{ Name = 'ORD-10'; What = "says the computer doesn't answer"; Expected = "✖ ORD-10 : L'ordinateur ne répond pas*AllowRemoteRPC*Erreur 0x000006BA*" }
    )
    foreach ($shadowReport in $shadowReports) {
        Invoke-Check "Prendre la main… for $($shadowReport.Name) $($shadowReport.What)" {
            param($problems)
            $dialog = Open-ActionDialog $shadowReport.Name 'Prendre la main…' 'Prendre la main' $shadowReport.Expected
            if (Get-DialogPart $dialog 'shadow_grid') { $problems.Add('the sessions dialog opened') }
            Close-Dialog $dialog 'dialog_cancel'
        }
    }

    Invoke-Check 'Prendre la main… for ORD-12, whose quser never answers, says so in a toast' {
        param($problems)
        # REPERE_SESSION_TIMEOUT: 3 s, as Actions and Shadow set it. The fake quser runs inside the background action,
        # so it's the action's own limit that ends it, 5 s later.
        Select-ResultRow 'ORD-12'
        Invoke-ResultMenuItem 'Prendre la main…'
        $expected = 'Prendre la main : ✖ ORD-12 : pas de réponse après 8 secondes (ordinateur éteint ou injoignable ?)'
        $notice = ''
        for ($i = 0; $i -lt 6 -and $notice -ne $expected; $i++) { $notice = Wait-ActionNotice $expected }
        if ($notice -ne $expected) { $problems.Add("the toast says '$notice'") }
        if (Test-ReportShown) { $problems.Add('a report opened') }
    }

    Invoke-Check "Utilisateurs connectés… says who is signed in on ORD-04" {
        param($problems)
        Select-ResultRow 'ORD-04'
        Invoke-ResultMenuItem 'Utilisateurs connectés…'
        $dialog = Wait-Dialog 'Utilisateurs connectés'
        $text = Get-DialogText $dialog
        if ($text -notlike "Qui est connecté à ORD-04 ?`n✔ ORD-04 : kiosque (active, rdp-tcp#0, ouverte le *)") { $problems.Add("the dialog says '$text'") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check "Utilisateurs connectés… reads each selected computer once: those with sessions first, the failures last" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-06'
        Add-ResultRow 'ORD-08'
        Add-ResultRow 'ORD-04'
        Invoke-ResultMenuItem 'Utilisateurs connectés…'
        $dialog = Wait-Dialog 'Utilisateurs connectés'
        $text = Get-DialogText $dialog
        $expected = "Qui est connecté à ces 4 ordinateurs ?`nSessions ouvertes sur 2 des 4 ordinateurs.`n" +
            "✔ ORD-01 : accueil (active, console, inactive depuis 12 min, ouverte le *) · jebertrand (déconnectée, inactive depuis 1 h 5 min, ouverte le *)`n" +
            "✔ ORD-04 : kiosque (active, rdp-tcp#0, ouverte le *)`nORD-08 : Personne n'a de session ouverte sur cet ordinateur.`n✖ ORD-06 : Accès refusé*"
        if ($text -notlike $expected) { $problems.Add("the dialog says '$text'") }
        $servers = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'quser' | ForEach-Object Server | Sort-Object)
        if (($servers -join ', ') -ne 'ord-01.demo.local, ord-04.demo.local, ord-06.demo.local, ord-08.demo.local') { $problems.Add("quser queries: $($servers -join ', ')") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check "Utilisateurs connectés…: a computer that doesn't answer has its own time, and the others are still shown" {
        param($problems)
        # This session gives each computer 3 s, and ORD-12's quser hangs (REPERE_SESSION_TIMEOUT, REPERE_FAKEAD_QUSER_HANG).
        # ORD-12 first: selecting a row that is already selected doesn't leave it alone.
        Select-ResultRow 'ORD-12'
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-12'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-ResultMenuItem 'Utilisateurs connectés…'
        $dialog = Wait-Dialog 'Utilisateurs connectés'
        $watch.Stop()
        $text = Get-DialogText $dialog
        if ($text -notlike "*✔ ORD-01 : accueil (*`n✖ ORD-12 : pas de réponse après 3 secondes*") { $problems.Add("the dialog says '$text'") }
        if ($watch.Elapsed.TotalSeconds -gt 12) { $problems.Add("it took $([int]$watch.Elapsed.TotalSeconds) s") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check "Utilisateurs connectés…: a user of the domain opens their Propriétés, a local account says so, and Prendre la main… is offered" {
        param($problems)
        Select-ResultRow 'ORD-12'
        Select-ResultRow 'ORD-01'
        Invoke-ResultMenuItem 'Utilisateurs connectés…'
        $dialog = Wait-Dialog 'Utilisateurs connectés'
        # jebertrand's session is ORD-01's 3rd: Jean Bertrand, of demo.local.
        $link = Get-DialogPart $dialog 'session_user_0_3'
        if (-not $link) { throw "jebertrand isn't a link." }
        Invoke-Element $link
        # A window of its own, owned by the main one, like every Propriétés.
        $details = $null
        for ($i = 0; $i -lt 40 -and -not $details; $i++) {
            $details = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Jean Bertrand' })[0]
            if (-not $details) { Start-Sleep -Milliseconds 250 }
        }
        if (-not $details) { $problems.Add("jebertrand's link opened no Propriétés de Jean Bertrand") }
        else { $details.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); Start-Sleep -Milliseconds 400 }

        # accueil is a local account: no domain has it.
        Invoke-Element (Get-DialogPart $dialog 'session_user_0_1')
        $isWindow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
        $local = $null
        for ($i = 0; $i -lt 20 -and -not $local; $i++) {
            $local = @($dialog.FindAll($Descendants, $isWindow) | Where-Object { Get-DialogPart $_ 'dialog_message' })[0]
            if (-not $local) { Start-Sleep -Milliseconds 250 }
        }
        $message = if ($local) { (Get-DialogPart $local 'dialog_message').Current.Name } else { '' }
        if ($message -notlike "accueil n'est un compte d'aucun domaine*") { $problems.Add("for accueil: '$message'") }
        if ($local) { Close-Dialog $local 'dialog_cancel' }

        Invoke-Element (Get-DialogPart $dialog 'session_shadow_0')
        $shadow = Wait-Dialog 'Prendre la main'
        Start-Sleep -Milliseconds 300
        $question = (Get-DialogPart $shadow 'shadow_question').Current.Name
        if ($question -ne '2 sessions sont ouvertes sur ORD-01 :') { $problems.Add("Prendre la main… asks '$question'") }
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Utilisateurs connectés' }).Count) { $problems.Add('Utilisateurs connectés stayed open') }
        Close-Dialog $shadow 'dialog_cancel'
    }
}

function Test-Shortcut {
    # The keys are posted to Repère's window, so they reach the control that has the focus, as typed ones would. WPF
    # reads Ctrl from the keyboard itself, which a posted key can't press: Ctrl+F and Ctrl+C aren't checked here (Ctrl+N
    # is, in Test-NextName, by holding Ctrl for real: Send-CtrlKey).
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'

    Invoke-Check 'F5 runs the last search again' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Send-Key 0x74
        $searches = @()
        for ($i = 0; $i -lt 20 -and -not $searches.Count; $i++) {
            Start-Sleep -Milliseconds 150
            $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer')
        }
        Wait-SearchEnd
        if ($searches.Count -ne 1 -or $searches[0].Filter -ne "Name -like '*ORD-0*'") { $problems.Add("searches sent: $(($searches | ForEach-Object { Format-Query $_ }) -join ' | ')") }
    }

    Invoke-Check "Suppr on a result asks to remove it, and Annuler leaves it" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-06'
        (Find-Control 'data_grid').SetFocus()
        Send-Key 0x2E
        $dialog = Wait-AnyDialog
        if (-not $dialog) { throw 'Suppr opened no dialog.' }
        $message = Get-DialogText $dialog
        if ($dialog.Current.Name -ne "Supprimer de l'AD" -or $message -notlike "Supprimer ORD-06 de l'AD ?*") { $problems.Add("Suppr opened '$($dialog.Current.Name)': '$message'") }
        Close-Dialog $dialog 'dialog_cancel'
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like 'Remove-*') { $problems.Add('a computer was removed') }
        if (-not (Get-ResultCell 'ORD-06' 1)) { $problems.Add('ORD-06 is no longer shown') }
    }

    Invoke-Check 'F2 on a result opens Modifier la description, and Annuler changes nothing' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-ResultRow 'ORD-06'
        (Find-Control 'data_grid').SetFocus()
        Send-Key 0x71
        $dialog = Wait-AnyDialog
        if (-not $dialog) { throw 'F2 opened no dialog.' }
        $message = Get-DialogText $dialog
        if ($dialog.Current.Name -ne 'Modifier la description' -or $message -notlike '*Description de ORD-06*') { $problems.Add("F2 opened '$($dialog.Current.Name)': '$message'") }
        Close-Dialog $dialog 'dialog_cancel'
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADComputer') { $problems.Add('a description was changed') }
    }
}

function Get-RecentMenuItem([string]$Button = 'recent_searches') {
    # Opens Recherches récentes (the computers', or a page's: user_recent, group_recent) and returns its items (the
    # searches, then Effacer…), menu left open.
    Invoke-Element (Find-Control $Button)
    for ($i = 0; $i -lt 20; $i++) {
        $items = @(Get-OpenMenuItem)
        if ($items.Count) { return $items }
        Start-Sleep -Milliseconds 150
    }
    throw "Recherches récentes didn't open."
}

function Get-AdvancedSearchSent([int]$Skip) {
    # The computer searches logged after the first $Skip lines, sorted.
    @(Get-LoggedQuery | Select-Object -Skip $Skip | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object { Format-Query $_ } | Sort-Object)
}

function Open-OuPicker([string]$Via = 'scope_ou') {
    # Chercher dans une OU, from Une OU or Choisir…: its window, once the domain's OUs are shown.
    if ($Via -eq 'scope_ou') { Select-AdvancedButton 'scope_ou' } else { Invoke-Element (Find-Control 'advanced_ou_pick') }
    $dialog = Wait-Dialog 'Chercher dans une OU'
    for ($i = 0; $i -lt 40 -and (Get-DialogPart $dialog 'move_status'); $i++) { Start-Sleep -Milliseconds 250 }
    if (Get-DialogPart $dialog 'move_status') { throw "The OUs aren't shown: '$((Get-DialogPart $dialog 'move_status').Current.Name)'." }
    $dialog
}

function Close-OuPicker($Dialog, [string]$Button = 'move_ok') {
    # Choisir or Annuler, then Avancée's popup opens again.
    Invoke-Element (Get-DialogPart $Dialog $Button)
    Wait-DialogsClosed
    for ($i = 0; $i -lt 20 -and -not (Find-ShownControl 'advanced_reset'); $i++) { Start-Sleep -Milliseconds 150 }
    if (-not (Find-ShownControl 'advanced_reset')) { throw "Avancée's popup didn't open again." }
}

function Test-AdvancedSearch {
    # Recherche avancée's popup: what Avancée says, an OU chosen in the tree (in a domain of its own), and the tree
    # closed without an OU.
    Invoke-Check 'Avancée says how many criteria are set and which, and the results say what was searched' {
        param($problems)
        $button = Find-Control 'advanced'
        $before = "$((Find-Control 'advanced_text').Current.Name) | $($button.Current.HelpText)"
        if ($before -ne 'Avancée | Recherche avancée : emplacement, état, système, dernière connexion') { $problems.Add("before: $before") }
        Open-AdvancedSearch
        $shown = @('advanced_ou_pick', 'advanced_ou_name', 'advanced_scope_note' | Where-Object { Find-ShownControl $_ })
        if ($shown.Count) { $problems.Add("with Partout, these show: $($shown -join ', ')") }
        if ((Find-Control 'advanced_logon_number').Current.IsEnabled) { $problems.Add('the duration is enabled with Peu importe') }
        Select-AdvancedButton 'scope_name'
        for ($i = 0; $i -lt 10 -and -not (Find-ShownControl 'advanced_ou_name'); $i++) { Start-Sleep -Milliseconds 150 }
        if (-not (Find-ShownControl 'advanced_ou_name') -or -not (Find-ShownControl 'advanced_scope_note')) { $problems.Add('OU nommées shows no name, or no note') }
        $name = (Find-Control 'advanced_ou_name').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($name -ne '') { $problems.Add("the OU name is '$name', not empty") }
        Set-Text 'advanced_ou_name' 'Communs'
        Select-AdvancedButton 'state_disabled'
        Select-AdvancedButton 'logon_less'
        $never = (Find-Control 'advanced_logon_never').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
        if ($never -ne 'Off') { $problems.Add("Moins de leaves Jamais $never") }
        Set-Text 'advanced_logon_number' '2'
        Select-AdvancedButton 'logon_unit1'
        if ($ScreenshotDirectory) { Save-Screenshot 'avancee' }
        Close-AdvancedSearch
        $after = "$((Find-Control 'advanced_text').Current.Name) | $($button.Current.HelpText)"
        if ($after -ne 'Avancée (3) | Recherche avancée : OU Communs…, désactivés, connectés depuis moins de 2 semaines') { $problems.Add("after: $after") }
        Select-Domain 'demo.local'
        Set-Text 'prefix' ''
        Set-Text 'search_term' ''
        Invoke-Search
        $scope = (Find-Control 'results_scope').Current.Name
        if ($scope -ne 'dans demo.local, OU Communs…, désactivés, connectés depuis moins de 2 semaines') { $problems.Add("results: $scope") }
        Set-AdvancedSearch
        if ((Find-Control 'advanced_text').Current.Name -ne 'Avancée') { $problems.Add("after Réinitialiser: $((Find-Control 'advanced_text').Current.Name)") }
    }

    Invoke-Check 'Une OU: chosen in the tree, searched in its domain only, with the OUs under it' {
        param($problems)
        Open-AdvancedSearch
        $dialog = Open-OuPicker
        if (-not (Get-DialogPart $dialog 'move_domain')) { $problems.Add('no Domaine list in the tree') }
        if (Get-DialogPart $dialog 'move_note') { $problems.Add('the Group Policy note shows') }
        $ok = Get-DialogPart $dialog 'move_ok'
        if ($ok.Current.IsEnabled) { $problems.Add('Choisir is enabled before an OU is chosen') }
        $target = Select-MoveTarget $dialog 'Kiosques'
        if ($target -ne 'Chercher dans : demo.local/Kiosques') { $problems.Add("the tree says '$target'") }
        Close-OuPicker $dialog
        $ou = (Find-Control 'advanced_ou_text').Current.Name
        if ($ou -ne 'Kiosques · demo.local') { $problems.Add("the popup says '$ou'") }
        Close-AdvancedSearch
        Select-Domain 'Tous les domaines'
        Set-Text 'prefix' 'ORD'
        Set-Text 'search_term' ''
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Search
        $sent = (Get-AdvancedSearchSent $queriesBefore) -join ' | '
        $expected = Format-Query @{ Command = 'Get-ADComputer'; Filter = "Name -like '*ORD*'"; SearchBase = 'OU=Kiosques,DC=demo,DC=local'; Server = 'demo.local' }
        if ($sent -ne $expected) { $problems.Add("searches sent: $sent") }
        if (((Get-ResultName) -join ', ') -ne 'ORD-04') { $problems.Add("rows: $((Get-ResultName) -join ', ')") }
        $scope = (Find-Control 'results_scope').Current.Name
        if ($scope -ne 'dans demo.local, OU Kiosques') { $problems.Add("results: $scope") }
    }

    Invoke-Check 'An OU chosen comes back after a restart, said on the button and in the popup' {
        param($problems)
        Stop-App
        Start-App -KeepSettings
        $button = Find-Control 'advanced'
        $said = "$((Find-Control 'advanced_text').Current.Name) | $($button.Current.HelpText)"
        if ($said -ne 'Avancée (1) | Recherche avancée : OU Kiosques (demo.local)') { $problems.Add("after a restart: $said") }
        Open-AdvancedSearch
        $ou = (Find-Control 'advanced_ou_text').Current.Name
        if ($ou -ne 'Kiosques · demo.local') { $problems.Add("the popup says '$ou'") }
        Close-AdvancedSearch
    }

    Invoke-Check 'Choisir…: an OU of another domain, and the tree closed without one leaves the emplacement as it was' {
        param($problems)
        Open-AdvancedSearch
        $dialog = Open-OuPicker 'pick'
        Select-ComboItem 'move_domain' 'nord.demo.local'
        for ($i = 0; $i -lt 40 -and -not (Get-MoveTreeItem $dialog -TopLevel | Where-Object { $_ -eq 'Postes' }) -or (Get-DialogPart $dialog 'move_status'); $i++) { Start-Sleep -Milliseconds 250 }
        $top = (Get-MoveTreeItem $dialog -TopLevel) -join ', '
        if ($top -notlike '*Postes*' -or $top -like '*Kiosques*') { $problems.Add("nord.demo.local's OUs: $top") }
        $null = Select-MoveTarget $dialog 'Postes'
        Close-OuPicker $dialog
        Close-AdvancedSearch
        Set-Text 'prefix' ''
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Search
        $sent = (Get-AdvancedSearchSent $queriesBefore) -join ' | '
        $expected = Format-Query @{ Command = 'Get-ADComputer'; Filter = "Name -like '*'"; SearchBase = 'OU=Postes,DC=nord,DC=demo,DC=local'; Server = 'nord.demo.local' }
        if ($sent -ne $expected) { $problems.Add("searches sent: $sent") }
        if (((Get-ResultName) -join ', ') -ne 'NRD-01, NRD-02, ORD-01') { $problems.Add("rows: $((Get-ResultName) -join ', ')") }

        Set-AdvancedSearch
        Open-AdvancedSearch
        $dialog = Open-OuPicker
        Close-OuPicker $dialog 'move_cancel'
        $chosen = (Find-Control 'advanced_scope_all').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
        if (-not $chosen) { $problems.Add('Partout is no longer chosen') }
        Close-AdvancedSearch
        if ((Find-Control 'advanced_text').Current.Name -ne 'Avancée') { $problems.Add("Avancée says '$((Find-Control 'advanced_text').Current.Name)'") }
    }
}

function Test-Safeguard {
    # What Repère never does, run with ORD-10 as the computer it runs on (named SALLE-REU2: its CN isn't its name),
    # jebertrand as its user, and Supprimer asking for the count above 2 computers: DC1 (a domain controller) and
    # ORD-10 are never disabled, deleted or moved, the deletion shows every object it removes, and jebertrand can't
    # disable their own account. Nothing is changed but two other Bertrands, disabled last.
    $changes = 'Disable-ADAccount', 'Remove-ADComputer', 'Remove-ADObject', 'Move-ADObject'
    Select-Domain 'demo.local'

    Invoke-Check 'A domain controller is never disabled, deleted or moved' {
        param($problems)
        Invoke-PrefixSearch 'DC'
        $queriesBefore = @(Get-LoggedQuery).Count
        foreach ($action in @(@('Désactiver…', 'Désactiver'), @("Supprimer de l'AD…", "Supprimer de l'AD"), @('Déplacer vers…', 'Déplacer'))) {
            $dialog = Open-ActionDialog 'DC1' $action[0] $action[1] "$($action[1]) : rien à faire*DC1 (contrôleur de domaine)*"
            Close-Dialog $dialog 'dialog_cancel'
        }
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -in $changes })
        if ($sent.Count) { $problems.Add("AD was changed: $(($sent | ForEach-Object { Format-Query $_ }) -join ' | ')") }
    }

    Invoke-Check 'The computer Repère runs on is left out, and the confirmation says so' {
        param($problems)
        Invoke-PrefixSearch 'ORD-1'
        $queriesBefore = @(Get-LoggedQuery).Count
        $dialog = Open-ActionDialog 'ORD-10' 'Désactiver…' 'Désactiver' "Désactiver : rien à faire*ORD-10 (l'ordinateur où Repère est ouvert)*"
        Close-Dialog $dialog 'dialog_cancel'
        Select-ResultRow 'ORD-10'
        Add-ResultRow 'ORD-11'
        Invoke-ResultMenuItem "Supprimer de l'AD…"
        $dialog = Wait-AnyDialog
        $text = Get-DialogText $dialog
        if ($text -notlike "Supprimer ORD-11 de l'AD ?*Laissés de côté : ORD-10 (l'ordinateur où Repère est ouvert).*") { $problems.Add("Supprimer asked: '$text'") }
        Close-Dialog $dialog 'dialog_cancel'
        Invoke-ResultMenuItem 'Déplacer vers…'
        $dialog = Wait-Dialog 'Déplacer vers…'
        $heading = (Get-DialogPart $dialog 'move_message').Current.Name
        if ($heading -notlike "Déplacer ORD-11 (*Laissés de côté : ORD-10 (l'ordinateur où Repère est ouvert).") { $problems.Add("Déplacer asked: '$heading'") }
        Close-Dialog $dialog 'move_cancel'
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -in $changes })
        if ($sent.Count) { $problems.Add("AD was changed: $(($sent | ForEach-Object { Format-Query $_ }) -join ' | ')") }
    }

    Invoke-Check 'Supprimer shows every object deleted with the computer, not only its BitLocker keys' {
        param($problems)
        Invoke-PrefixSearch 'ORD-06'
        $dialog = Open-ActionDialog 'ORD-06' "Supprimer de l'AD…" "Supprimer de l'AD" "Supprimer ORD-06 de l'AD ?*"
        $text = Get-DialogText $dialog
        if ($text -notlike '*ORD-06 : aucune clé BitLocker*Aussi supprimé : Windows Virtual Machine (serviceConnectionPoint)*') { $problems.Add("the details say: '$text'") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Past the limit, Supprimer asks for the number of computers to be typed' {
        param($problems)
        Invoke-PrefixSearch 'ORD-0'
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-02'
        Invoke-ResultMenuItem "Supprimer de l'AD…"
        $dialog = Wait-AnyDialog
        if (Get-DialogPart $dialog 'dialog_confirm') { $problems.Add('2 computers (the limit) ask for their number') }
        Close-Dialog $dialog 'dialog_cancel'
        Add-ResultRow 'ORD-04'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-ResultMenuItem "Supprimer de l'AD…"
        $dialog = Wait-AnyDialog
        $box = Get-DialogPart $dialog 'dialog_confirm'
        $ok = Get-DialogPart $dialog 'dialog_ok'
        if (-not $box) { $problems.Add("3 computers don't ask for their number") }
        else {
            if ($box.Current.Name -ne 'Pour confirmer, tapez 3 :') { $problems.Add("the box reads '$($box.Current.Name)'") }
            $states = foreach ($typed in '', '2', ' 3 ') {
                $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($typed)
                Start-Sleep -Milliseconds 150
                "'$typed' $($ok.Current.IsEnabled)"
            }
            if (($states -join ' | ') -ne "'' False | '2' False | ' 3 ' True") { $problems.Add("Supprimer is enabled: $($states -join ' | ')") }
        }
        Close-Dialog $dialog 'dialog_cancel'
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -in $changes })
        if ($sent.Count) { $problems.Add("AD was changed: $(($sent | ForEach-Object { Format-Query $_ }) -join ' | ')") }
    }

    Invoke-Check 'Your own account is never disabled' {
        param($problems)
        Invoke-Element (Find-Control 'tab_users')
        Start-Sleep -Milliseconds 500
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'jebertrand'
        Select-UserRow 'Jean Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_toggle')
        $dialog = Wait-AnyDialog
        if (-not $dialog) { throw 'Désactiver… said nothing.' }
        $text = Get-DialogText $dialog
        if ($dialog.Current.Name -ne 'Désactiver' -or $text -notlike 'Désactiver : rien à faire*votre propre compte (jebertrand)*') { $problems.Add("Désactiver… said '$($dialog.Current.Name)': '$text'") }
        Close-Dialog $dialog 'dialog_cancel'
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Disable-ADAccount')
        if ($sent.Count) { $problems.Add('the account was disabled') }
    }

    Invoke-Check 'With other users, your own account is left out, and the notice counts users' {
        param($problems)
        # The three Bertrands: Julie and Jean (yours) in demo.local, Paul in nord.demo.local.
        $null = Invoke-UserSearch 'Tous les domaines' 'Nom, identifiant ou courriel' 'bertrand'
        Select-UserRow 'Julie Bertrand'
        Select-UserRow 'Jean Bertrand' -Add
        Select-UserRow 'Paul Bertrand' -Add
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_toggle')
        $dialog = Wait-AnyDialog
        if (-not $dialog) { throw 'Désactiver… asked nothing.' }
        $text = Get-DialogText $dialog
        if ($text -notlike 'Désactiver 2 utilisateurs ?*Laissé de côté : jebertrand (votre compte).') { $problems.Add("Désactiver… asked '$text'") }
        Close-Dialog $dialog 'dialog_ok'
        $notice = Wait-ActionNotice 'Désactivés : ✔ 2 utilisateurs'
        if ($notice -ne 'Désactivés : ✔ 2 utilisateurs') { $problems.Add("the notice says '$notice'") }
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Disable-ADAccount' | ForEach-Object Identity | Sort-Object)
        if (($sent -join ' | ') -ne 'CN=Julie Bertrand,OU=Utilisateurs,DC=demo,DC=local | CN=Paul Bertrand,OU=Utilisateurs,DC=nord,DC=demo,DC=local') { $problems.Add("disabled: $($sent -join ' | ')") }
        Invoke-Element (Find-Control 'tab_computers')
    }

    Invoke-Check "Past the limit, Ajouter à un groupe… and Retirer d'un groupe… ask for the number of computers, then change each group once" {
        param($problems)
        # ORD-01 is in GG-Postes-Accueil already; ORD-02 and ORD-04 aren't.
        Invoke-PrefixSearch 'ORD-0'
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-02'
        Add-ResultRow 'ORD-04'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-ResultMenuItem 'Ajouter à un groupe…'
        $add = Wait-Dialog 'Ajouter à un groupe'
        $text = Get-DialogText $add
        if ($text -notlike 'Ajouter 3 ordinateurs à des groupes*ORD-01*ORD-02*ORD-04*prochain redémarrage*') { $problems.Add("Ajouter à un groupe… says '$text'") }
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is enabled before the number is typed') }
        (Get-DialogPart $add 'dialog_confirm').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('3')
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('postes')
        Start-Sleep -Milliseconds 900
        # The number typed isn't enough: a group too.
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is enabled with the number typed but no group ticked') }
        Select-GroupChoice $add 'GG-Postes-Accueil'
        if (-not (Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is disabled with the number typed and a group ticked') }
        Close-Dialog $add 'dialog_ok'
        $notice = Wait-ActionNotice 'Ajouter à un groupe : ✔ 3 ordinateurs dans GG-Postes-Accueil'
        if ($notice -ne 'Ajouter à un groupe : ✔ 3 ordinateurs dans GG-Postes-Accueil') { $problems.Add("after adding, the notice says '$notice'") }
        $added = (Get-GroupChange 'Add-ADGroupMember' $queriesBefore) -join ' | '
        if ($added -ne 'GG-Postes-Accueil: ORD-02;ORD-04') { $problems.Add("additions: $added") }

        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-ResultMenuItem "Retirer d'un groupe…"
        $remove = Wait-Dialog "Retirer d'un groupe"
        $listed = Get-DialogListName $remove 'group_remove_results'
        if ($listed -ne 'GG-GPO-Kiosques, GG-Logiciel-Office, GG-Postes-Accueil, Liste-Inventaire') { $problems.Add("Retirer d'un groupe… offers: $listed") }
        (Get-DialogPart $remove 'dialog_confirm').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('3')
        Start-Sleep -Milliseconds 200
        if ((Get-DialogPart $remove 'dialog_ok').Current.IsEnabled) { $problems.Add('Retirer is enabled with the number typed but no group ticked') }
        Select-ListChoice $remove 'group_remove_results' 'GG-Postes-Accueil'
        if ($ScreenshotDirectory) { Save-Screenshot 'ordinateurs-retirer-groupe' $remove }
        Close-Dialog $remove 'dialog_ok'
        $notice = Wait-ActionNotice "Retirer d'un groupe : ✔ 3 ordinateurs retirés de GG-Postes-Accueil"
        if ($notice -ne "Retirer d'un groupe : ✔ 3 ordinateurs retirés de GG-Postes-Accueil") { $problems.Add("after removing, the notice says '$notice'") }
        $removed = (Get-GroupChange 'Remove-ADGroupMember' $queriesBefore) -join ' | '
        if ($removed -ne 'GG-Postes-Accueil: ORD-01;ORD-02;ORD-04') { $problems.Add("removals: $removed") }
    }
}

function Test-SafeguardInBackground {
    # Run with nord.demo.local taking 2 s per call: the guard of Désactiver and Supprimer de l'AD asks it which computers
    # are its controllers in the background, so the window answers meanwhile, and a second click asks once.
    Select-Domain 'nord.demo.local'
    Invoke-PrefixSearch 'NRD'

    Invoke-Check 'Désactiver asks AD in the background: the window stays usable, and clicking twice asks once' {
        param($problems)
        Select-ResultRow 'NRD-01'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Element (Find-Control 'act_toggle')
        Invoke-Element (Find-Control 'act_toggle')
        $count = (Find-Control 'results_count').Current.Name
        if ($watch.ElapsedMilliseconds -ge 1500 -or $count -ne '2 ordinateurs') { $problems.Add("the window answered after $($watch.ElapsedMilliseconds) ms, its count reading '$count'") }
        if (-not (Test-WindowEnabled)) { $problems.Add('the confirmation opened before AD answered') }
        $dialog = Wait-Dialog 'Désactiver'
        $text = Get-DialogText $dialog
        if ($text -notlike 'Désactiver NRD-01 ?*') { $problems.Add("Désactiver asked: '$text'") }
        Start-Sleep -Milliseconds 2500
        $open = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Désactiver' }).Count
        if ($open -ne 1) { $problems.Add("$open Désactiver windows") }
        Close-Dialog $dialog 'dialog_cancel'
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Désactiver' }).Count) { Close-OpenDialog }
    }

    Invoke-Check "Supprimer de l'AD reads the guard and what goes with the computer in the background, then asks" {
        param($problems)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Element (Find-Control 'act_remove')
        $count = (Find-Control 'results_count').Current.Name
        if ($watch.ElapsedMilliseconds -ge 1500 -or $count -ne '2 ordinateurs') { $problems.Add("the window answered after $($watch.ElapsedMilliseconds) ms, its count reading '$count'") }
        $dialog = Wait-Dialog "Supprimer de l'AD"
        $text = Get-DialogText $dialog
        if ($text -notlike "Supprimer NRD-01 de l'AD ?*") { $problems.Add("Supprimer asked: '$text'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-SearchMemory {
    # Two searches, then Repère closes and starts again with what it saved: the last search's settings come back, and
    # both searches are in Recherches récentes, the last one first. Picking the other one runs it again.
    Invoke-Check 'Recherches récentes names each search type, as Utilisateurs and Groupes do, except a list''s and an address''s' {
        param($problems)
        Select-Domain 'demo.local'
        Select-SearchType 'Description commence par'
        Reset-AdvancedSearch
        Set-Text 'prefix' 'ORD'
        # Pasted with stray spaces: searched as the recent search shows it, « acc » (#238).
        Set-Text 'search_term' ' acc '
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Search
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object { Format-Query $_ })
        if (($sent -join ' | ') -ne "Get-ADComputer -Filter Name -like '*ORD*' -and Description -like 'acc*' in the whole domain on demo.local") { $problems.Add("« acc » with spaces sent: $($sent -join ' | ')") }
        Select-SearchType 'ID de clé BitLocker'
        Set-Text 'prefix' ''
        Set-Text 'search_term' '6f1c2e7a'
        Invoke-Search
        Select-SearchType 'Adresse IP'
        Set-Text 'search_term' '10.0.1.11'
        Invoke-Search
        $items = @(Get-RecentMenuItem)
        $names = @($items | ForEach-Object { $_.Current.Name })
        $expected = 'IP 10.0.1.11  —  demo.local', 'ID de clé BitLocker « 6f1c2e7a »  —  demo.local',
                    'Nom contient « ORD » · Description commence par « acc »  —  demo.local', 'Effacer les recherches récentes'
        if (($names -join ' | ') -ne ($expected -join ' | ')) { $problems.Add("recent searches: $($names -join ' | ')") }
        # Cleared: the next check counts the recent searches it makes.
        $items[-1].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 200
        Close-Menu
    }

    Invoke-Check 'The last search settings come back after a restart, with the recent searches' {
        param($problems)
        Select-Domain 'nord.demo.local'
        Invoke-PrefixSearch '' 'accueil'
        Select-Domain 'demo.local'
        Select-SearchType 'Sans description'
        Set-AdvancedSearch @{ Scope = 'name'; Logon = 'atleast'; Number = '180' }
        Set-Text 'prefix' 'ORD'
        Invoke-Search
        Stop-App
        Start-App -KeepSettings
        $restored = "$(Get-ComboText 'domain') | $(Get-ComboText 'search_type') | $((Find-Control 'advanced_text').Current.Name)"
        if ($restored -ne 'demo.local | Sans description | Avancée (2)') { $problems.Add("restored: $restored") }

        $names = @(Get-RecentMenuItem | ForEach-Object { $_.Current.Name })
        $expected = 'Nom contient « ORD » · Sans description · OU Communs… · inactifs depuis 180 jours  —  demo.local', 'Description contient « accueil »  —  nord.demo.local', 'Effacer les recherches récentes'
        if (($names -join ' | ') -ne ($expected -join ' | ')) { $problems.Add("recent searches: $($names -join ' | ')") }

        $queriesBefore = @(Get-LoggedQuery).Count
        $item = @(Get-OpenMenuItem) | Where-Object { $_.Current.Name -eq 'Description contient « accueil »  —  nord.demo.local' } | Select-Object -First 1
        $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 300
        Wait-SearchEnd
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object { Format-Query $_ })
        if (($sent -join ' | ') -ne "Get-ADComputer -Filter Name -like '*' -and Description -like '*accueil*' in the whole domain on nord.demo.local") { $problems.Add("searches sent: $($sent -join ' | ')") }
        $state = "$(Get-ComboText 'domain') | $(Get-ComboText 'search_type') | $((Find-Control 'advanced_text').Current.Name)"
        if ($state -ne 'nord.demo.local | Description contient | Avancée') { $problems.Add("after picking it: $state") }
        if (((Get-ResultName) -join ', ') -ne 'ORD-01') { $problems.Add("rows: $((Get-ResultName) -join ', ')") }
    }

    Invoke-Check 'A recherche.json saved before the advanced search: its Inactifs depuis comes back as a criterion' {
        param($problems)
        Stop-App
        $old = [ordered]@{
            Domain = 'demo.local'; SearchType = 'Inactifs depuis'; Inactive = '1 an'
            Recent = @(
                [ordered]@{ Domain = 'demo.local'; Type = 'Inactifs depuis'; Prefix = 'ORD'; Term = ''; Inactive = '180 jours' }
                [ordered]@{ Domain = 'demo.local'; Type = 'Nom contient'; Prefix = 'ORD'; Term = '1' }
                [ordered]@{ Domain = 'demo.local'; Type = 'Nom contient'; Prefix = ''; Term = '12' }
                # Prochain nom… was once the last search type: no longer one, so this search is left out.
                [ordered]@{ Domain = 'demo.local'; Type = 'Prochain nom…'; Prefix = 'ORD'; Term = '' })
        }
        $old | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $env:APPDATA 'Repere\recherche.json') -Encoding utf8
        Start-App -KeepSettings
        $restored = "$(Get-ComboText 'search_type') | $((Find-Control 'advanced_text').Current.Name) | $((Find-Control 'advanced').Current.HelpText)"
        if ($restored -ne 'Description contient | Avancée (1) | Recherche avancée : inactifs depuis 1 an') { $problems.Add("restored: $restored") }
        $names = @(Get-RecentMenuItem | ForEach-Object { $_.Current.Name })
        if ($names[0] -ne 'Nom contient « ORD » · inactifs depuis 180 jours  —  demo.local') { $problems.Add("recent searches: $($names -join ' | ')") }
        if ($names[1] -ne 'Nom contient « ORD*1 »  —  demo.local' -or $names[2] -ne 'Nom contient « 12 »  —  demo.local') { $problems.Add("recent Nom contient: $($names -join ' | ')") }
        if ($names.Count -ne 4) { $problems.Add("with a search of the Prochain nom… type saved, recent searches: $($names -join ' | ')") }
        Send-Key 0x1B
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Search
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object { Format-Query $_ } | Sort-Object)
        $filter = "Name -like '*' -and (lastLogonTimestamp -lt $(Get-LogonCutoff 1 3) -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))"
        $expected = @(Format-Query @{ Command = 'Get-ADComputer'; Filter = $filter; Server = 'demo.local' })
        if (($sent -join ' | ') -ne ($expected -join ' | ')) { $problems.Add("searches sent: $($sent -join ' | ')") }
    }

    Invoke-Check 'After a restart: the window at its size and place, on the page it showed, and Utilisateurs and Groupes with their search and recent searches' {
        param($problems)
        Set-WindowState 'Normal'
        $window.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern).Move(60, 40)
        $window.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern).Resize(1240, 780)
        Start-Sleep -Milliseconds 500
        Invoke-Element (Find-Control 'tab_groups')
        Start-Sleep -Milliseconds 500
        $null = Invoke-GroupSearch 'demo.local' 'Nom contient' 'vpn'
        Invoke-Element (Find-Control 'tab_users')
        Start-Sleep -Milliseconds 500
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        $null = Invoke-UserSearch 'Tous les domaines' 'Verrouillés' ''
        $before = $window.Current.BoundingRectangle
        Stop-App
        Start-App -KeepSettings
        Start-Sleep -Milliseconds 500

        $after = $window.Current.BoundingRectangle
        foreach ($side in 'Left', 'Top', 'Width', 'Height') {
            if ([Math]::Abs($after.$side - $before.$side) -gt 2) { $problems.Add("window $side was $($before.$side), is $($after.$side)") }
        }
        if (-not (Find-ShownControl 'user_grid')) { $problems.Add("Utilisateurs isn't the page shown") }
        $restored = "$(Get-ComboText 'user_domain') | $(Get-ComboText 'user_search_type')"
        if ($restored -ne 'Tous les domaines | Verrouillés') { $problems.Add("Utilisateurs restored: $restored") }
        $items = @(Get-RecentMenuItem 'user_recent')
        $names = @($items | ForEach-Object { $_.Current.Name })
        $expected = 'Verrouillés  —  Tous les domaines', 'Nom, identifiant ou courriel « bert »  —  demo.local', 'Effacer les recherches récentes'
        if (($names -join ' | ') -ne ($expected -join ' | ')) { $problems.Add("Utilisateurs' recent searches: $($names -join ' | ')") }
        $item = $items | Where-Object { $_.Current.Name -eq 'Nom, identifiant ou courriel « bert »  —  demo.local' } | Select-Object -First 1
        if ($item) {
            $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            for ($i = 0; $i -lt 40 -and -not (Find-Control 'user_search').Current.IsEnabled; $i++) { Start-Sleep -Milliseconds 100 }
            Start-Sleep -Milliseconds 300
            $state = "$(Get-ComboText 'user_domain') | $(Get-ComboText 'user_search_type') | $((Find-Control 'user_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value)"
            if ($state -ne 'demo.local | Nom, identifiant ou courriel | bert') { $problems.Add("after picking « bert »: $state") }
            if (-not @(Get-DialogRow (Find-Control 'user_grid')).Count) { $problems.Add('picking « bert » found nobody') }
        }

        Invoke-Element (Find-Control 'tab_groups')
        Start-Sleep -Milliseconds 500
        $restored = "$(Get-ComboText 'group_domain') | $(Get-ComboText 'group_search_type')"
        if ($restored -ne 'demo.local | Nom contient') { $problems.Add("Groupes restored: $restored") }
        $names = @(Get-RecentMenuItem 'group_recent' | ForEach-Object { $_.Current.Name })
        if (($names -join ' | ') -ne 'Nom contient « vpn »  —  demo.local | Effacer les recherches récentes') { $problems.Add("Groupes' recent searches: $($names -join ' | ')") }
        Send-Key 0x1B
    }
}

function Set-WindowState([string]$State, [int]$Width, [int]$Height) {
    # Maximized, or Normal at that size (in screen pixels), then a moment for the layout.
    $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).SetWindowVisualState($State)
    if ($Width) { $window.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern).Resize($Width, $Height) }
    Start-Sleep -Milliseconds 700
}

function Test-TitleBar {
    # Repère draws its own title bar: the app bar holds the window's buttons, and Agrandir becomes Restaurer.
    Invoke-Check "The app bar is the title bar: Réduire, Agrandir (then Restaurer) and Fermer at its end" {
        param($problems)
        $names = @('caption_minimize', 'caption_maximize', 'caption_close' | Where-Object { -not (Find-ShownControl $_) })
        if ($names) { $problems.Add("missing: $($names -join ', ')") }
        $maximize = Find-Control 'caption_maximize'
        try {
            Invoke-Element $maximize
            Start-Sleep -Milliseconds 600
            $state = $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Current.WindowVisualState
            if ($state -ne 'Maximized') { $problems.Add("Agrandir left the window $state") }
            if ($maximize.Current.Name -ne 'Restaurer') { $problems.Add("once maximized, the button is named '$($maximize.Current.Name)'") }
            Invoke-Element $maximize
            Start-Sleep -Milliseconds 600
            $state = $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Current.WindowVisualState
            if ($state -ne 'Normal') { $problems.Add("Restaurer left the window $state") }
        }
        finally { Set-WindowState 'Normal' }
    }
}

function Test-ActionLabel {
    Invoke-Check 'The icon buttons show their label when the window is wide enough, and only then' {
        param($problems)
        $rect = $window.Current.BoundingRectangle
        $labels = 'act_edit_label', 'act_move_label', 'act_groups_label', 'act_next_name_label', 'act_bitlocker_label', 'act_laps_label', 'act_copy_label', 'act_remove_label'
        $texts = 'act_ping_label', 'act_specs_label', 'act_toggle_text'
        try {
            # In Segoe UI, Vérifier en ligne, Caractéristiques and Désactiver keep theirs even at its narrowest (in a wider
            # font they don't: Paramètres › Apparence).
            Set-WindowState 'Normal' 1000 $rect.Height
            $shown = @($labels | Where-Object { Find-ShownControl $_ })
            if ($shown.Count) { $problems.Add("in a window 1000 wide, labels shown: $($shown -join ', ')") }
            $hidden = @($texts | Where-Object { -not (Find-ShownControl $_) })
            if ($hidden.Count) { $problems.Add("in a window 1000 wide, labels hidden: $($hidden -join ', ')") }
            $tip = (Find-Control 'act_ping').Current.HelpText
            if ($tip.StartsWith('Vérifier en ligne')) { $problems.Add("labelled, Vérifier en ligne's tooltip still names it: '$tip'") }
            Set-WindowState 'Maximized'
            $wide = $window.Current.BoundingRectangle.Width
            $shown = @($labels | Where-Object { Find-ShownControl $_ })
            # A screen this wide has room for them; on a smaller one they may stay hidden.
            if ($wide -ge 1700 -and $shown.Count -ne $labels.Count) { $problems.Add("in a window $wide wide, labels shown: $($shown -join ', ')") }
            if ($shown.Count) {
                $names = @($labels | ForEach-Object { (Find-Control $_).Current.Name }) -join ', '
                if ($names -ne 'Description, Déplacer, Groupes, Prochain nom, BitLocker, LAPS, Copier, Supprimer') { $problems.Add("labels: $names") }
                $last = (Find-Control 'act_remove').Current.BoundingRectangle
                $selection = (Find-Control 'selection_text').Current.BoundingRectangle
                if ($last.Right -gt $selection.Left) { $problems.Add("the buttons run into the selection text ($($last.Right) > $($selection.Left))") }
            }
            if ($ScreenshotDirectory) { Save-Screenshot 'actions-libelles' }
        }
        finally {
            Set-WindowState 'Normal' $rect.Width $rect.Height
        }
    }
}

function Open-SettingsSection([string]$Key) {
    # Paramètres, on one of its sections (appearance, move, restart, shortcuts): the window.
    Invoke-Element (Find-Control 'settings')
    $settingsWindow = Wait-Dialog 'Paramètres'
    (Get-DialogPart $settingsWindow "nav_$Key").GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 400
    $settingsWindow
}

function Get-MoveRootBox($SettingsWindow, [string]$Name) {
    # A check box of Paramètres › Déplacer vers, by its OU's name, once the domain's OUs are shown.
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::CheckBox),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Name))
    for ($i = 0; $i -lt 40; $i++) {
        $box = $SettingsWindow.FindFirst($Descendants, $condition)
        if ($box) { return $box }
        Start-Sleep -Milliseconds 250
    }
    throw "No '$Name' check box in Déplacer vers."
}

function Get-MoveRootItem($SettingsWindow, [string]$Name) {
    # The tree item holding that OU's check box: it opens and closes (ExpandCollapsePattern).
    [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent((Get-MoveRootBox $SettingsWindow $Name))
}

function Get-BoxState($Box) {
    "$($Box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState)$(if (-not $Box.Current.IsEnabled) { ' (grisée)' })"
}

function Invoke-UserSearch([string]$Domain, [string]$Type, [string]$Text) {
    # A search of the Utilisateurs page, once it has answered: its rows (state | name | login | title | department |
    # last logon | password | domain when several | OU).
    if ($Domain) { Select-ComboItem 'user_domain' $Domain }
    Select-ComboItem 'user_search_type' $Type
    (Find-Control 'user_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    Invoke-Element (Find-Control 'user_search')
    for ($i = 0; $i -lt 40 -and -not (Find-Control 'user_search').Current.IsEnabled; $i++) { Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 200
    @(Get-DialogRow (Find-Control 'user_grid'))
}

function Select-UserRow([string]$Name, [switch]$Add) {
    # Selects the row of the Utilisateurs page whose Nom is $Name (-Add: adds it to the selection, like Ctrl + click).
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    $row = @((Find-Control 'user_grid').FindAll($Descendants, $isRow) | Where-Object { @($_.FindAll($Descendants, $isCell) | ForEach-Object { $_.Current.Name }) -contains $Name })[0]
    if (-not $row) { throw "No '$Name' row." }
    $pattern = $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if ($Add) { $pattern.AddToSelection() } else { $pattern.Select() }
    Start-Sleep -Milliseconds 200
}

function Test-UserPage {
    # The fake AD's users: two Bertrands in demo.local and one in nord, Marc Durand locked out, Luc Lefebvre whose
    # password expired, Nathalie Lévy whose password the user can't reset. The fake domain wants 10 characters or more.
    Invoke-Check 'Utilisateurs: its tab shows the page, the computers stay where they were' {
        param($problems)
        Show-UserPage
        if (-not (Find-ShownControl 'user_query')) { $problems.Add("the users' search box isn't shown") }
        if (Find-ShownControl 'prefix') { $problems.Add("the computers' search box is still shown") }
        # Tous les domaines first, as on the Ordinateurs page.
        $domains = Get-ComboItemName 'user_domain'
        if (($domains -join ' | ') -ne (@('Tous les domaines') + $fakeDomains -join ' | ')) { $problems.Add("the Domaine list holds: $($domains -join ' | ')") }
    }

    Invoke-Check "Utilisateurs: the search box's tooltip follows the search type" {
        param($problems)
        $tips = [ordered]@{
            'Verrouillés' = "Facultatif : le début du nom, de l'identifiant ou du courriel (Ctrl+F)"
            'Description contient' = 'Une partie de la description (Ctrl+F)'
            "Liste d'identifiants" = 'Identifiants, courriels ou noms entiers, séparés par des virgules (Ctrl+F)'
            'Nom, identifiant ou courriel' = "Le début du prénom, du nom, de l'identifiant ou du courriel (Ctrl+F)"
        }
        foreach ($type in $tips.Keys) {
            Select-ComboItem 'user_search_type' $type
            $tip = (Find-Control 'user_query').Current.HelpText
            if ($tip -ne $tips[$type]) { $problems.Add("$type's tooltip: '$tip'") }
        }
    }

    Invoke-Check 'Utilisateurs: « bert » in every domain finds the three Bertrands, with their state, password and domain' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $rows = @(Invoke-UserSearch 'Tous les domaines' 'Nom, identifiant ou courriel' 'bert')
        $expected = "Actif | Jean Bertrand | jebertrand | Technicien | Informatique | aujourd'hui | Expire dans 3 jours | demo.local | Utilisateurs",
                    "Actif | Julie Bertrand | jbertrand | Agente d'accueil | Accueil | hier | Expire le * | demo.local | Utilisateurs",
                    'Actif | Paul Bertrand | pbertrand | Magasinier | Entrepôt | il y a 6 jours | Expire le * | nord.demo.local | Utilisateurs'
        $listed = $rows.Count -eq 3
        for ($i = 0; $listed -and $i -lt 3; $i++) { $listed = $rows[$i] -like $expected[$i] }
        if (-not $listed) { $problems.Add("rows: $($rows -join ' // ')") }
        $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADUser' | ForEach-Object { "$($_.Server) $($_.LDAPFilter)" } | Sort-Object)
        $filter = '(&(objectCategory=person)(objectClass=user)(anr=bert))'
        if (($searches -join ' | ') -ne "demo.local $filter | nord.demo.local $filter") { $problems.Add("searches: $($searches -join ' | ')") }
        $count = (Find-Control 'user_count').Current.Name
        if ($count -ne '3 utilisateurs') { $problems.Add("the count says '$count'") }
        # The search time's tooltip: each domain's AD query and rows, then the grid.
        $tip = (Find-Control 'user_time').Current.HelpText -split "`n"
        if ($tip.Count -ne 3 -or $tip[0] -notmatch '^demo\.local : AD [\d  ]+ ms, lignes [\d  ]+ ms \(2 utilisateurs\)$' -or
            $tip[1] -notmatch '^nord\.demo\.local : AD [\d  ]+ ms, lignes [\d  ]+ ms \(1 utilisateurs\)$' -or $tip[2] -notmatch '^Grille : [\d  ]+ ms$') {
            $problems.Add("the search time's tooltip says: $($tip -join ' // ')")
        }
    }

    Invoke-Check 'Utilisateurs: Exporter saves the users shown as CSV, with their email and distinguished name' {
        param($problems)
        Remove-Item $exportFile -ErrorAction SilentlyContinue
        Invoke-Element (Find-Control 'user_export')
        for ($i = 0; $i -lt 20 -and -not (Test-Path $exportFile); $i++) { Start-Sleep -Milliseconds 150 }
        $rows = @(Import-Csv -LiteralPath $exportFile -Delimiter (Get-Culture).TextInfo.ListSeparator -Encoding utf8)
        $logins = ($rows | ForEach-Object Identifiant) -join ', '
        if ($logins -ne 'jebertrand, jbertrand, pbertrand') { $problems.Add("logins exported: $logins") }
        $julie = @($rows | Where-Object Identifiant -eq 'jbertrand')[0]
        if ($julie.Courriel -ne 'jbertrand@demo.local' -or $julie.'Nom distinctif' -ne 'CN=Julie Bertrand,OU=Utilisateurs,DC=demo,DC=local' -or $julie.'État' -ne 'Actif') {
            $problems.Add("Julie's line: $($julie | ConvertTo-Json -Compress)")
        }
    }

    Invoke-Check 'Utilisateurs: Mot de passe filters by state, the count says how many are shown, and a new search clears it' {
        param($problems)
        Open-ColumnFilterList 'PasswordSort' 'user_grid' 'user_'
        $listed = (Get-ColumnFilterListText 'user_') -join ', '
        if ($listed -ne '✔Expire dans 14 jours ou moins (1), ✔Expire dans plus de 14 jours (2)') { $problems.Add("the list holds: $listed") }
        Set-ColumnFilterTicked 'Expire dans 14 jours ou moins' 'user_'
        Close-ColumnFilterList 'ok' 'user_'
        $rows = @(Get-DialogRow (Find-Control 'user_grid'))
        if ($rows.Count -ne 1 -or $rows[0] -notlike '*| Jean Bertrand |*') { $problems.Add("rows: $($rows -join ' // ')") }
        $count = (Find-Control 'user_count').Current.Name
        if ($count -ne '1 sur 3 utilisateurs') { $problems.Add("the count says '$count'") }
        $rows = @(Invoke-UserSearch 'Tous les domaines' 'Nom, identifiant ou courriel' 'bert')
        if ($rows.Count -ne 3) { $problems.Add("after a new search, $($rows.Count) rows: $($rows -join ' // ')") }
        $button = (Find-Control 'user_column_filters_text').Current.Name
        if ($button -ne 'Filtres') { $problems.Add("after a new search, the button says '$button'") }
    }

    Invoke-Check 'Utilisateurs: Colonnes shows Courriel, hidden at first, and Réinitialiser hides it again' {
        param($problems)
        Invoke-Element (Find-Control 'user_columns')
        $items = @()
        for ($i = 0; $i -lt 20 -and -not $items.Count; $i++) { Start-Sleep -Milliseconds 150; $items = @(Get-OpenMenuItem) }
        $names = ($items | ForEach-Object { $_.Current.Name }) -join ', '
        if ($names -ne 'État, Identifiant, Courriel, Poste, Service, Description, Dernière connexion, Mot de passe, Domaine, Emplacement, Réinitialiser les colonnes') { $problems.Add("menu items: $names") }
        $mail = @($items | Where-Object { $_.Current.AutomationId -eq 'user_column_Mail' })[0]
        if ($mail.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -ne 'Off') { $problems.Add('Courriel is ticked at first') }
        $mail.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 300
        Close-Menu
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[1]
        if ($row -notlike 'Actif | Julie Bertrand | jbertrand | jbertrand@demo.local | *') { $problems.Add("with Courriel, the row says '$row'") }
        Invoke-Element (Find-Control 'user_columns')
        for ($i = 0; $i -lt 20 -and -not @(Get-OpenMenuItem).Count; $i++) { Start-Sleep -Milliseconds 150 }
        @(Get-OpenMenuItem | Where-Object { $_.Current.AutomationId -eq 'user_column_reset' })[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 300
        Close-Menu
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[1]
        if ($row -like '*@demo.local*') { $problems.Add("after Réinitialiser, the row says '$row'") }
    }

    Invoke-Check "Utilisateurs: Copier le courriel copies the selected users' emails, one per line, and waits for a user who has one" {
        param($problems)
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        Select-UserRow 'Julie Bertrand'
        Select-UserRow 'Jean Bertrand' -Add
        Set-Clipboard -Value 'avant'
        $item = Open-UserMenuItem 'Copier le courriel'
        if (-not $item.Current.IsEnabled) { $problems.Add('Copier le courriel is disabled for two users with an email') }
        else { $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
        Start-Sleep -Milliseconds 400
        $copied = @((Get-Clipboard) | Where-Object { $_ } | Sort-Object) -join ' | '
        if ($copied -ne 'jbertrand@demo.local | jebertrand@demo.local') { $problems.Add("copied: '$copied'") }

        $null = Invoke-UserSearch 'demo.local' 'Description contient' 'sauvegarde'
        Select-UserRow 'Sauvegarde'
        $item = Open-UserMenuItem 'Copier le courriel'
        if ($item.Current.IsEnabled) { $problems.Add('Copier le courriel is enabled for a user without an email') }
        Close-Menu
    }

    Invoke-Check 'Utilisateurs: Verrouillés without text lists the locked accounts, and Déverrouiller unlocks them' {
        param($problems)
        $rows = @(Invoke-UserSearch 'demo.local' 'Verrouillés' '')
        if ($rows.Count -ne 1 -or $rows[0] -notlike 'Verrouillé | Marc Durand | mdurand | *') { $problems.Add("rows: $($rows -join ' // ')") }
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-UserRow 'Marc Durand'
        Invoke-Element (Find-Control 'user_unlock')
        $notice = Wait-ActionNotice 'Déverrouillé : ✔ mdurand'
        if ($notice -ne 'Déverrouillé : ✔ mdurand') { $problems.Add("the notice says '$notice'") }
        # On the PDC, where Propriétés reads the account (Invoke-UserChange).
        $unlocks = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Unlock-ADAccount')
        if ($unlocks.Count -ne 1 -or $unlocks[0].Identity -ne 'CN=Marc Durand,OU=Utilisateurs,DC=demo,DC=local' -or $unlocks[0].Server -ne 'dc1.demo.local') {
            $problems.Add("unlocks: $($unlocks | ConvertTo-Json -Compress)")
        }
        $state = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($state -notlike 'Actif | Marc Durand | *') { $problems.Add("after it, the row says '$state'") }
        if ((Find-Control 'user_unlock').Current.IsEnabled) { $problems.Add('Déverrouiller is still enabled') }
    }

    Invoke-Check 'Utilisateurs: a disabled account offers Activer, an enabled one Désactiver… after a confirmation, and a refusal is reported' {
        param($problems)
        $rows = @(Invoke-UserSearch 'demo.local' 'Désactivés' '')
        if ($rows.Count -ne 1 -or $rows[0] -notlike 'Désactivé | Sophie Rey | srey | *') { $problems.Add("rows: $($rows -join ' // ')") }
        Select-UserRow 'Sophie Rey'
        $text = (Find-Control 'user_toggle_text').Current.Name
        if ($text -ne 'Activer') { $problems.Add("for a disabled account, the button says '$text'") }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_toggle')
        $notice = Wait-ActionNotice 'Activé : ✔ srey'
        if ($notice -ne 'Activé : ✔ srey') { $problems.Add("Activer's notice says '$notice'") }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*-ADAccount')
        if ($calls.Count -ne 1 -or $calls[0].Command -ne 'Enable-ADAccount' -or $calls[0].Identity -ne 'CN=Sophie Rey,OU=Utilisateurs,DC=demo,DC=local') { $problems.Add("Activer sent: $($calls | ConvertTo-Json -Compress)") }
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike 'Actif | Sophie Rey | *') { $problems.Add("once enabled, the row says '$row'") }

        $text = (Find-Control 'user_toggle_text').Current.Name
        if ($text -ne 'Désactiver…') { $problems.Add("for an enabled account, the button says '$text'") }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_toggle')
        $dialog = Wait-AnyDialog
        if (-not $dialog) { throw 'Désactiver… asked nothing.' }
        $message = Get-DialogText $dialog
        if ($dialog.Current.Name -ne 'Désactiver' -or $message -notlike 'Désactiver Sophie Rey ?*') { $problems.Add("Désactiver… asked '$($dialog.Current.Name)': '$message'") }
        Close-Dialog $dialog 'dialog_ok'
        $notice = Wait-ActionNotice 'Désactivé : ✔ srey'
        if ($notice -ne 'Désactivé : ✔ srey') { $problems.Add("Désactiver's notice says '$notice'") }
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*-ADAccount')
        if ($calls.Count -ne 1 -or $calls[0].Command -ne 'Disable-ADAccount') { $problems.Add("Désactiver sent: $($calls | ConvertTo-Json -Compress)") }
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike 'Désactivé | Sophie Rey | *') { $problems.Add("once disabled, the row says '$row'") }

        # Nathalie Lévy's account can't be changed by the user: the report says so, and the row stays.
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'nlevy'
        Select-UserRow 'Nathalie Lévy'
        Invoke-Element (Find-Control 'user_toggle')
        Close-Dialog (Wait-AnyDialog) 'dialog_ok'
        $report = Wait-FailureReport 'Désactiver'
        $text = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($text -notlike '✖ nlevy : *') { $problems.Add("the refusal's report says '$text'") }
        Close-Dialog $report 'dialog_cancel'
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike 'Actif | Nathalie Lévy | *') { $problems.Add("after the refusal, the row says '$row'") }
    }

    Invoke-Check 'Utilisateurs: Nouveau mot de passe… sets a generated one, to change at the next logon, and shows it once' {
        param($problems)
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'lefebvre'
        Select-UserRow 'Luc Lefebvre'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        $generated = (Get-DialogPart $dialog 'reset_generated').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
        $mustChange = (Get-DialogPart $dialog 'reset_must_change').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
        if (-not $generated -or $mustChange -ne 'On') { $problems.Add("generated: $generated, must change: $mustChange") }
        if ($ScreenshotDirectory) { Save-Screenshot 'utilisateurs-reinitialiser' $dialog }
        Invoke-Element (Get-DialogPart $dialog 'dialog_ok')
        $shown = Wait-Dialog 'Mot de passe réinitialisé'
        Start-Sleep -Milliseconds 300
        $password = Read-NewPassword $shown $problems
        if ($password -cnotmatch '^[A-Z][a-z]+-[A-Z][a-z]+-[A-Z][a-z]+-\d\d$') { $problems.Add("the password shown is '$password'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'utilisateurs-mot-de-passe' $shown }
        Close-Dialog $shown 'dialog_cancel'
        $calls = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -match '^(Set-|Unlock-)')
        $sent = @($calls | ForEach-Object { "$($_.Command) $(if ($_.Command -eq 'Set-ADUser') { $_.ChangePasswordAtLogon } else { $_.Length })" }) -join ' | '
        if ($sent -ne "Set-ADAccountPassword $($password.Length) | Set-ADUser True") { $problems.Add("calls: $sent") }
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike '* | À changer à la connexion | *') { $problems.Add("after it, the row says '$row'") }
    }

    Invoke-Check 'Utilisateurs: a generated password is always changed at the next logon, one typed in Autre as chosen' {
        param($problems)
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'lperrin'
        Select-UserRow 'Léa Perrin'
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        $box = Get-DialogPart $dialog 'reset_must_change'
        $toggle = $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle.Current.ToggleState -ne 'On' -or $box.Current.IsEnabled) { $problems.Add("generated, « Doit le changer » is $($toggle.Current.ToggleState), enabled: $($box.Current.IsEnabled)") }
        (Get-DialogPart $dialog 'reset_custom').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        if (-not $box.Current.IsEnabled) { $problems.Add('Autre leaves « Doit le changer » held') }
        $toggle.Toggle()
        (Get-DialogPart $dialog 'reset_generated').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        if ($toggle.Current.ToggleState -ne 'On' -or $box.Current.IsEnabled) { $problems.Add("back on generated, « Doit le changer » is $($toggle.Current.ToggleState), enabled: $($box.Current.IsEnabled)") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check "Utilisateurs: Réinitialiser doesn't offer « Doit le changer » when the password never expires" {
        param($problems)
        $null = Invoke-UserSearch 'demo.local' 'Description contient' 'sauvegarde'
        Select-UserRow 'Sauvegarde'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        $box = Get-DialogPart $dialog 'reset_must_change'
        $state = $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
        if ($state -ne 'Off' -or $box.Current.IsEnabled) { $problems.Add("« Doit le changer » is $state, enabled: $($box.Current.IsEnabled)") }
        $note = Get-DialogPart $dialog 'reset_must_change_note'
        if (-not $note -or $note.Current.IsOffscreen) { $problems.Add("the note saying why isn't shown") }
        if ((Get-DialogPart $dialog 'reset_generated').Current.IsEnabled) { $problems.Add('a generated password is offered') }
        (Get-DialogPart $dialog 'reset_custom_value').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Sauvegarde-Longue-2026')
        Invoke-Element (Get-DialogPart $dialog 'dialog_ok')
        $shown = Wait-Dialog 'Mot de passe réinitialisé'
        Start-Sleep -Milliseconds 300
        $message = (Get-DialogPart $shown 'dialog_message').Current.Name
        if ($message -like '*⚠*') { $problems.Add("the result warns: '$message'") }
        Close-Dialog $shown 'dialog_cancel'
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADUser').Count) { $problems.Add('Set-ADUser was called') }
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -like '*À changer à la connexion*') { $problems.Add("after it, the row says '$row'") }
    }

    Invoke-Check "Utilisateurs: the default password of Paramètres is offered, always to change at the next logon, and a reset the user can't make is reported" {
        param($problems)
        # As Paramètres › Mots de passe saves it: encrypted for this Windows account. « Doit le changer » unticked
        # there only goes for Autre: the default password, the same for everyone, is always temporary.
        $secure = [securestring]::new()
        foreach ($char in 'Bienvenue-2026!'.ToCharArray()) { $secure.AppendChar($char) }
        [ordered]@{ Mode = 'Default'; MustChange = $false; Default = (ConvertFrom-SecureString -SecureString $secure) } | ConvertTo-Json |
            Set-Content (Join-Path $env:APPDATA 'Repere\motdepasse.json') -Encoding utf8
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'nlevy'
        Select-UserRow 'Nathalie Lévy'
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        $default = (Get-DialogPart $dialog 'reset_default').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
        $box = Get-DialogPart $dialog 'reset_must_change'
        $toggle = $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if (-not $default -or $toggle.Current.ToggleState -ne 'On' -or $box.Current.IsEnabled) { $problems.Add("default: $default, must change: $($toggle.Current.ToggleState), enabled: $($box.Current.IsEnabled)") }
        (Get-DialogPart $dialog 'reset_custom').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        if ($toggle.Current.ToggleState -ne 'Off' -or -not $box.Current.IsEnabled) { $problems.Add("Autre, « Doit le changer » is $($toggle.Current.ToggleState), enabled: $($box.Current.IsEnabled), not as Paramètres says") }
        # From the default password straight to a generated one, and back: held all along, then as before them.
        (Get-DialogPart $dialog 'reset_default').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        (Get-DialogPart $dialog 'reset_generated').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        (Get-DialogPart $dialog 'reset_default').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        if ($toggle.Current.ToggleState -ne 'On' -or $box.Current.IsEnabled) { $problems.Add("back on default, « Doit le changer » is $($toggle.Current.ToggleState), enabled: $($box.Current.IsEnabled)") }
        (Get-DialogPart $dialog 'reset_custom').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        if ($toggle.Current.ToggleState -ne 'Off') { $problems.Add("back on Autre, « Doit le changer » is $($toggle.Current.ToggleState)") }
        (Get-DialogPart $dialog 'reset_default').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        Invoke-Element (Get-DialogPart $dialog 'dialog_ok')
        $report = Wait-FailureReport 'Nouveau mot de passe'
        $text = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($text -ne '✖ nlevy : mot de passe non réinitialisé (Accès refusé)') { $problems.Add("the report says '$text'") }
        Close-Dialog $report 'dialog_cancel'

        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'jbertrand'
        Select-UserRow 'Julie Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Invoke-Element (Get-DialogPart $dialog 'dialog_ok')
        $shown = Wait-Dialog 'Mot de passe réinitialisé'
        Start-Sleep -Milliseconds 300
        $password = Read-NewPassword $shown $problems
        if ($password -cne 'Bienvenue-2026!') { $problems.Add("the password shown is '$password'") }
        Close-Dialog $shown 'dialog_cancel'
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADUser' | ForEach-Object { $_.ChangePasswordAtLogon }) -join ' | '
        if ($sent -ne 'True') { $problems.Add("« must change » sent: '$sent'") }

        # A password that never expires can't be asked to change: the default password isn't offered, only Autre.
        $null = Invoke-UserSearch 'demo.local' 'Description contient' 'sauvegarde'
        Select-UserRow 'Sauvegarde'
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPart $dialog 'reset_default').Current.IsEnabled) { $problems.Add('the password never expires, yet the default one is offered') }
        if (-not (Get-DialogPart $dialog 'reset_custom').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected) { $problems.Add("the password never expires, yet Autre isn't chosen") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check "Utilisateurs: Ordinateurs de l'utilisateur searches the computers' descriptions for their name, in every domain and from AD only; one without any says so" {
        param($problems)
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'jbertrand'
        Select-UserRow 'Julie Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Open-UserMenuItem "Ordinateurs de l'utilisateur")
        Wait-UserComputer
        Test-UserComputer $problems $queriesBefore 'NRD-02'

        Show-UserPage
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'mdurand'
        Select-UserRow 'Marc Durand'
        Invoke-Element (Open-UserMenuItem "Ordinateurs de l'utilisateur")
        Wait-UserComputer
        $empty = (Find-Control 'grid_empty_text').Current.Name
        if ($empty -ne 'Aucun ordinateur dont la description contient « Marc Durand ».') { $problems.Add("with none, the grid says '$empty'") }
        Show-UserPage
    }

    Invoke-Check "Utilisateurs: Liste d'identifiants finds logins, emails and names in every domain, each once, and lists those found nowhere, to copy" {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $rows = @(Invoke-UserSearch 'Tous les domaines' "Liste d'identifiants" 'jbertrand; LPERRIN@demo.local; Paul Bertrand; DEMO\mdurand; JBertrand; inconnu; Personne Absente')
        $names = ($rows | ForEach-Object { ($_ -split ' \| ')[1] }) -join ', '
        if ($names -ne 'Julie Bertrand, Léa Perrin, Marc Durand, Paul Bertrand') { $problems.Add("rows: $($rows -join ' // ')") }
        # One query per domain, every entry in one OR, exactly: a login as a login, one with an @ as a UPN or an email, a
        # name with spaces as a name.
        $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADUser')
        $filter = '(&(objectCategory=person)(objectClass=user)(|(sAMAccountName=jbertrand)(userPrincipalName=LPERRIN@demo.local)(mail=LPERRIN@demo.local)' +
            '(displayName=Paul Bertrand)(name=Paul Bertrand)(sAMAccountName=mdurand)(sAMAccountName=inconnu)(displayName=Personne Absente)(name=Personne Absente)))'
        if ($searches.Count -ne 2 -or @($searches | Where-Object LDAPFilter -ne $filter).Count) { $problems.Add("searches: $(@($searches | ForEach-Object { "$($_.Server) $($_.LDAPFilter)" }) -join ' | ')") }
        $notFound = Find-ShownControl 'user_not_found_text'
        $said = if ($notFound) { $notFound.Current.Name } else { '(not shown)' }
        if ($said -ne '2 introuvables : inconnu, Personne Absente') { $problems.Add("the entries not found say '$said'") }
        Set-Clipboard -Value 'avant'
        Invoke-Element (Find-Control 'user_not_found_copy')
        $notice = Wait-ActionNotice 'Copié dans le presse-papiers : ✔ 2 introuvables copiés'
        if ($notice -ne 'Copié dans le presse-papiers : ✔ 2 introuvables copiés') { $problems.Add("after Copier, the notice says '$notice'") }
        $copied = @(Get-Clipboard | Where-Object { $_ }) -join ' | '
        if ($copied -ne 'inconnu | Personne Absente') { $problems.Add("copied: '$copied'") }
        $recent = @(Get-RecentMenuItem 'user_recent')[0].Current.Name
        Close-Menu
        if ($recent -ne 'liste : jbertrand, LPERRIN@demo.local, Paul Bertrand (+3)  —  Tous les domaines') { $problems.Add("the recent search says '$recent'") }

        # Lines pasted stay apart, a name with spaces whole.
        Set-Clipboard -Value "Julie Bertrand`r`nlperrin`r`n"
        $box = Find-Control 'user_query'
        $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
        $box.SetFocus()
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 300
        $pasted = $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($pasted -ne 'Julie Bertrand; lperrin') { $problems.Add("pasted, the box holds '$pasted'") }
        # Pasted after them: a semicolon first.
        Set-Clipboard -Value "mdurand`r`nsrey"
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 300
        $pasted = $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($pasted -ne 'Julie Bertrand; lperrin; mdurand; srey') { $problems.Add("pasted after them, the box holds '$pasted'") }

        # Another search: the entries not found go.
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        if (Find-ShownControl 'user_not_found') { $problems.Add('after another search, the entries not found still show') }
        # Nothing to look for: said, without asking AD.
        $queriesBefore = @(Get-LoggedQuery).Count
        $null = Invoke-UserSearch '' "Liste d'identifiants" ' ; , '
        # Said under the field, whose box gets the focus; the count still tells the rows shown.
        for ($i = 0; $i -lt 10 -and -not ($hint = Find-ShownControl 'user_search_hint_text'); $i++) { Start-Sleep -Milliseconds 100 }
        $hintText = if ($hint) { $hint.Current.Name }
        if ($hintText -ne 'Entrez les identifiants ou les courriels (ex. jbertrand, lperrin@demo.local)') { $problems.Add("without entries, the hint says '$hintText'") }
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement.Current.AutomationId
        if ($focused -ne 'user_query') { $problems.Add("without entries, the focus is on '$focused'") }
        if (@(Get-LoggedQuery).Count -ne $queriesBefore) { $problems.Add('without entries, AD was asked') }
        # Typing makes it go.
        (Find-Control 'user_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('jbertrand')
        Start-Sleep -Milliseconds 200
        if (Find-ShownControl 'user_search_hint_text') { $problems.Add('the hint still shows once something is typed') }
    }

    Invoke-Check "Utilisateurs: Ajouter à un groupe… puts the users selected in the groups ticked, one call per group; Retirer d'un groupe… offers their direct groups" {
        param($problems)
        # Julie and Jean Bertrand are both in GG-VPN, neither in GG-Ventes; Julie is in GG-Accueil too.
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        Select-UserRow 'Julie Bertrand'
        if (-not (Find-Control 'user_groups_add').Current.IsEnabled) { $problems.Add('Ajouter à un groupe… is disabled for one user') }
        Select-UserRow 'Jean Bertrand' -Add
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_groups_add')
        $add = Wait-Dialog 'Ajouter à un groupe'
        $text = Get-DialogText $add
        if ($text -notlike 'Ajouter 2 utilisateurs à des groupes*jbertrand*' -or $text -notlike '*jebertrand*ouverture de session*') { $problems.Add("Ajouter à un groupe… says '$text'") }
        if (Get-DialogPart $add 'dialog_confirm') { $problems.Add('2 users ask for their number') }
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('gg-')
        Start-Sleep -Milliseconds 900
        # Ajouter waits for a group: with none ticked, it would close and add nothing.
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is enabled before a group is ticked') }
        Select-GroupChoice $add 'GG-VPN', 'GG-Ventes'
        if (-not (Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is disabled with two groups ticked') }
        Close-Dialog $add 'dialog_ok'
        $notice = Wait-ActionNotice 'Ajouter à un groupe : ✔ 2 utilisateurs dans 2 groupes'
        if ($notice -ne 'Ajouter à un groupe : ✔ 2 utilisateurs dans 2 groupes') { $problems.Add("after adding, the notice says '$notice'") }
        # GG-VPN had them both: only GG-Ventes is changed, once.
        $added = (Get-GroupChange 'Add-ADGroupMember' $queriesBefore) -join ' | '
        if ($added -ne 'GG-Ventes: Jean Bertrand;Julie Bertrand') { $problems.Add("additions: $added") }

        $queriesBefore = @(Get-LoggedQuery).Count
        # Retirer d'un groupe… has its button by Ajouter's, enabled as the menu item is, and does what it does.
        $button = Find-Control 'user_groups_remove'
        if (-not $button.Current.IsEnabled) { $problems.Add("Retirer d'un groupe… is disabled for two users") }
        if ($button.Current.HelpText -notlike "Retirer d'un groupe…*") { $problems.Add("its tooltip says '$($button.Current.HelpText)'") }
        $menuEnabled = (Open-UserMenuItem "Retirer d'un groupe…").Current.IsEnabled
        Close-Menu
        if (-not $menuEnabled) { $problems.Add("the menu's Retirer d'un groupe… is disabled for two users") }
        Invoke-Element $button
        $remove = Wait-Dialog "Retirer d'un groupe"
        $listed = Get-DialogListName $remove 'group_remove_results'
        if ($listed -ne 'GG-Accueil, GG-Ventes, GG-VPN') { $problems.Add("Retirer d'un groupe… offers: $listed") }
        if ((Get-DialogPart $remove 'dialog_ok').Current.IsEnabled) { $problems.Add('Retirer is enabled before a group is ticked') }
        Select-ListChoice $remove 'group_remove_results' 'GG-Ventes'
        if ($ScreenshotDirectory) { Save-Screenshot 'utilisateurs-retirer-groupe' $remove }
        Close-Dialog $remove 'dialog_ok'
        $notice = Wait-ActionNotice "Retirer d'un groupe : ✔ 2 utilisateurs retirés de GG-Ventes"
        if ($notice -ne "Retirer d'un groupe : ✔ 2 utilisateurs retirés de GG-Ventes") { $problems.Add("after removing, the notice says '$notice'") }
        $removed = (Get-GroupChange 'Remove-ADGroupMember' $queriesBefore) -join ' | '
        if ($removed -ne 'GG-Ventes: Jean Bertrand;Julie Bertrand') { $problems.Add("removals: $removed") }
    }

    Invoke-Check 'Utilisateurs: the action row still fits at Grande and Très grande text' {
        param($problems)
        Test-ToolbarFit 'user' 'user_copy' $problems
    }

    Invoke-Check 'Utilisateurs: the Ordinateurs tab goes back to the computers' {
        param($problems)
        Invoke-Element (Find-Control 'tab_computers')
        Start-Sleep -Milliseconds 400
        if (-not (Find-ShownControl 'prefix')) { $problems.Add("the computers' search box isn't back") }
        if (Find-ShownControl 'user_query') { $problems.Add("the users' search box is still shown") }
    }
}

function Test-ToolbarFit([string]$Prefix, [string]$LastButton, $Problems) {
    # A page's action row at Grande and Très grande text (Paramètres › Apparence › Texte), then back to Normale: its last
    # button ends before the selection text starts.
    $settingsWindow = Open-SettingsSection 'appearance'
    try {
        foreach ($size in 'text_size_large', 'text_size_larger') {
            Invoke-Element (Get-DialogPart $settingsWindow $size)
            Start-Sleep -Milliseconds 700
            $last = (Find-Control $LastButton).Current.BoundingRectangle
            $selection = (Find-Control "$($Prefix)_selection").Current.BoundingRectangle
            if ($last.Right -gt $selection.Left) { $Problems.Add("$size : the buttons run into the selection text ($($last.Right) > $($selection.Left))") }
            if ($ScreenshotDirectory) { Save-Screenshot "$($Prefix)-barre-$size" }
        }
    }
    finally {
        Invoke-Element (Get-DialogPart $settingsWindow 'text_size_normal')
        Start-Sleep -Milliseconds 500
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }
}

function Wait-UserComputer {
    # After Ordinateurs de l'utilisateur: until the Ordinateurs page shows and its search has ended.
    for ($i = 0; $i -lt 20 -and -not (Find-ShownControl 'prefix'); $i++) { Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 200
    Wait-SearchEnd
}

function Test-UserComputer($Problems, [int]$QueriesBefore, [string]$Expected) {
    # What Ordinateurs de l'utilisateur searched (Julie Bertrand's description in every domain, from AD only) and found.
    $term = (Find-Control 'search_term').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    if ($term -ne 'Julie Bertrand') { $Problems.Add("the description box holds '$term'") }
    $names = (Get-ResultName) -join ', '
    if ($names -ne $Expected) { $Problems.Add("found: '$names'") }
    $sent = @(Get-LoggedQuery | Select-Object -Skip $QueriesBefore)
    $servers = @($sent | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object Server | Sort-Object -Unique) -join ', '
    if ($servers -ne 'demo.local, nord.demo.local') { $Problems.Add("computers searched on: '$servers'") }
    $other = @($sent | Where-Object Command -notlike 'Get-AD*' | ForEach-Object Command | Sort-Object -Unique) -join ', '
    if ($other) { $Problems.Add("sent besides AD reads: $other") }
}

# The submenus of the Utilisateurs grid's right-click menu, and their items.
$userMenuGroups = [ordered]@{
    'Groupes' = 'Comparer les groupes…', 'Ajouter à un groupe…', "Retirer d'un groupe…"
    'Copier'  = "Copier l'identifiant", 'Copier le nom', 'Copier le courriel', 'Copier les lignes'
}

function Open-UserMenuItem([string]$Name) {
    # The item $Name of the Utilisateurs grid's right-click menu, opened by the context menu key (sent again when it's
    # missed, as for the computers), in its submenu when it has one. A disabled submenu is returned for its items:
    # they can't be reached, so they read as disabled.
    $group = @($userMenuGroups.Keys | Where-Object { $userMenuGroups[$_] -contains $Name })[0]
    $top = if ($group) { $group } else { $Name }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        (Find-Control 'user_grid').SetFocus()
        Send-Key 0x5D
        for ($i = 0; $i -lt 10; $i++) {
            $item = @(Get-OpenMenuItem | Where-Object { $_.Current.Name -eq $top })[0]
            if ($item) { break }
            Start-Sleep -Milliseconds 200
        }
        if ($item) { break }
    }
    if (-not $item) { throw "No '$top' in the right-click menu." }
    if (-not $group -or -not $item.Current.IsEnabled) { return $item }
    $item.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    for ($i = 0; $i -lt 20; $i++) {
        $found = @(Get-OpenMenuItem | Where-Object { $_.Current.Name -eq $Name })[0]
        if ($found) { return $found }
        Start-Sleep -Milliseconds 150
    }
    throw "No '$Name' in the '$group' submenu."
}

function Test-UserListUnanswered {
    # Run with nord.demo.local down (#236): a list searched in every domain can't call pbertrand, of nord, truly not
    # found, so the banner says which domain didn't answer. The next search, in demo.local alone, no longer says it.
    Invoke-Check "Utilisateurs: Liste d'identifiants with a domain down says the entries not found may be in it" {
        param($problems)
        Show-UserPage
        $rows = @(Invoke-UserSearch 'Tous les domaines' "Liste d'identifiants" 'jbertrand; pbertrand; inconnu')
        $names = ($rows | ForEach-Object { ($_ -split ' \| ')[1] }) -join ', '
        if ($names -ne 'Julie Bertrand') { $problems.Add("rows: $($rows -join ' // ')") }
        $count = (Find-Control 'user_count').Current.Name
        if ($count -notlike '*(erreur : nord.demo.local)') { $problems.Add("the count says '$count'") }
        $notFound = Find-ShownControl 'user_not_found_text'
        $said = if ($notFound) { $notFound.Current.Name } else { '(not shown)' }
        if ($said -ne '2 introuvables : pbertrand, inconnu · sans réponse de nord.demo.local') { $problems.Add("the entries not found say '$said'") }

        $null = Invoke-UserSearch 'demo.local' "Liste d'identifiants" 'pbertrand'
        $notFound = Find-ShownControl 'user_not_found_text'
        $said = if ($notFound) { $notFound.Current.Name } else { '(not shown)' }
        if ($said -ne '1 introuvable : pbertrand') { $problems.Add("in demo.local alone, the entries not found say '$said'") }
    }
}

function Test-UserSearchReplace {
    # Run with nord.demo.local taking 8 s per call (#237): during a search there, a recent search or Entrée replaces it,
    # and its own rows show at once, instead of being dropped while the slow one goes on.
    Invoke-Check 'Utilisateurs: during a slow search, a recent search replaces it and its rows show' {
        param($problems)
        Show-UserPage
        $rows = @(Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert')
        if ($rows.Count -ne 2) { $problems.Add("the first search found $($rows.Count) rows"); return }
        $watch = Start-SlowPageSearch 'user' 'nord.demo.local' 'Nom, identifiant ou courriel' 'a'
        try {
            $item = @(Get-RecentMenuItem 'user_recent') | Where-Object { $_.Current.Name -eq 'Nom, identifiant ou courriel « bert »  —  demo.local' } | Select-Object -First 1
            if (-not $item) { Close-Menu; $problems.Add('no « bert » in the recent searches'); return }
            $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Wait-PageSearch 'user'
            if ($watch.ElapsedMilliseconds -ge 6000) { $problems.Add("the recent search ended after $($watch.ElapsedMilliseconds) ms, with the slow one") }
            $state = "$(Get-ComboText 'user_domain') | $((Find-Control 'user_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value)"
            if ($state -ne 'demo.local | bert') { $problems.Add("after picking « bert », the boxes: $state") }
            $names = @(Get-DialogRow (Find-Control 'user_grid') | ForEach-Object { ($_ -split ' \| ')[1] }) -join ', '
            $count = (Find-Control 'user_count').Current.Name
            if ($names -ne 'Jean Bertrand, Julie Bertrand' -or $count -ne '2 utilisateurs') { $problems.Add("after picking « bert », rows: '$names', count: '$count'") }
        }
        finally { if (Find-ShownControl 'user_cancel') { Invoke-Element (Find-Control 'user_cancel'); Wait-PageSearch 'user' } }
    }

    Invoke-Check 'Utilisateurs: during a slow search, Entrée in the box replaces it and its rows show' {
        param($problems)
        Show-UserPage
        $watch = Start-SlowPageSearch 'user' 'nord.demo.local' 'Nom, identifiant ou courriel' 'a'
        try {
            Select-ComboItem 'user_domain' 'demo.local'
            $box = Find-Control 'user_query'
            $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('durand')
            $box.SetFocus()
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            Wait-PageSearch 'user'
            if ($watch.ElapsedMilliseconds -ge 6000) { $problems.Add("Entrée's search ended after $($watch.ElapsedMilliseconds) ms, with the slow one") }
            $names = @(Get-DialogRow (Find-Control 'user_grid') | ForEach-Object { ($_ -split ' \| ')[1] }) -join ', '
            $count = (Find-Control 'user_count').Current.Name
            if ($names -ne 'Marc Durand' -or $count -ne '1 utilisateur') { $problems.Add("after Entrée, rows: '$names', count: '$count'") }
            $recent = @(Get-RecentMenuItem 'user_recent')[0].Current.Name
            Close-Menu
            if ($recent -ne 'Nom, identifiant ou courriel « durand »  —  demo.local') { $problems.Add("the recent search first is '$recent'") }
        }
        finally { if (Find-ShownControl 'user_cancel') { Invoke-Element (Find-Control 'user_cancel'); Wait-PageSearch 'user' } }
    }
}

function Show-UserPage {
    # The Utilisateurs tab, until its page shows (right after the app starts, a click can be lost).
    for ($i = 0; $i -lt 3 -and -not (Find-ShownControl 'user_query'); $i++) {
        Invoke-Element (Find-Control 'tab_users')
        for ($j = 0; $j -lt 10 -and -not (Find-ShownControl 'user_query'); $j++) { Start-Sleep -Milliseconds 200 }
    }
}

function Open-UserDetail([string]$Type, [string]$Text, [string]$Name) {
    # Propriétés… of a user found by a search of the Utilisateurs page: the window.
    $null = Invoke-UserSearch 'demo.local' $Type $Text
    Select-UserRow $Name
    Invoke-Element (Find-Control 'user_details')
    # Not $window: that's the main window, which Find-Control searches.
    $details = Wait-Dialog "Propriétés de $Name"
    Wait-DetailRead $details
    $details
}

function Wait-DetailRead($Window) {
    # A Propriétés window reads AD in the background, its status « Lecture » meanwhile: until it clears (10 s at most),
    # then a moment for the cards to be drawn.
    for ($i = 0; $i -lt 100 -and $Window.Current.ItemStatus -eq 'Lecture'; $i++) { Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 200
}

function Get-UserDetailText($Window, [string]$Key) {
    Wait-DetailRead $Window
    (Get-DialogPart $Window "user_detail_$Key").Current.Name
}

function Get-UserDetailGroup($Window) {
    # The groups the window lists, each « name | membership ».
    Wait-DetailRead $Window
    $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    @($Window.FindAll($Descendants, $isText) | Where-Object { $_.Current.AutomationId -match '^user_group_\d+$' } |
        Sort-Object { $_.Current.BoundingRectangle.Top } | ForEach-Object { $_.Current.Name })
}

function Close-UserDetail($Details) {
    # Propriétés has no Fermer: closed like its × does. It's a window of its own (the main one stays enabled meanwhile):
    # until it's gone from the main window's.
    $name = $Details.Current.Name
    $Details.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    for ($i = 0; $i -lt 20 -and @(Get-AppWindow | Where-Object { $_.Current.Name -eq $name }).Count; $i++) { Start-Sleep -Milliseconds 150 }
    Start-Sleep -Milliseconds 300
}

function Test-DetailFoldBarInView($Details, [string]$Prefix, $Problems) {
    # Propriétés made short, its cards scrolled to the end: Tout développer and Tout réduire, like the title bar's
    # buttons, are still in the window, above the cards rather than among them (#270: they scrolled away with the
    # cards). Scrolled back.
    $Details.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern).Resize(700, 420)
    Start-Sleep -Milliseconds 400
    $scrollPart = Get-DialogPart $Details "$($Prefix)_scroll"
    $scroll = $scrollPart.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
    if (-not $scroll.Current.VerticallyScrollable) { $Problems.Add('made short, its cards do not scroll'); return }
    $scroll.SetScrollPercent(-1, 100)
    Start-Sleep -Milliseconds 400
    $box = $Details.Current.BoundingRectangle
    $cardsTop = $scrollPart.Current.BoundingRectangle.Top
    foreach ($id in "$($Prefix)_expand_all", "$($Prefix)_collapse_all", 'caption_close') {
        $rect = (Get-DialogPart $Details $id).Current.BoundingRectangle
        if ($rect.Top -lt $box.Top -or $rect.Bottom -gt $cardsTop + 1) { $Problems.Add("scrolled to the end, $id is at ${rect}: not between the window's top ($($box.Top)) and its cards ($cardsTop)") }
    }
    $scroll.SetScrollPercent(-1, 0)
    Start-Sleep -Milliseconds 300
}

function Select-GroupChoice($Dialog, [string[]]$Names) {
    # Ticks these groups in Ajouter à un groupe…'s list (several can be).
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    $list = Get-DialogPart $Dialog 'group_results'
    foreach ($name in $Names) {
        $item = @($list.FindAll($Descendants, $isItem) | Where-Object { $_.Current.Name -eq $name })[0]
        if (-not $item) {
            # Below the list's height: its row isn't made until it's scrolled to.
            $item = $list.GetCurrentPattern([System.Windows.Automation.ItemContainerPattern]::Pattern).FindItemByProperty($null, $AE::NameProperty, $name)
            if ($item) { $item.GetCurrentPattern([System.Windows.Automation.VirtualizedItemPattern]::Pattern).Realize() }
        }
        if (-not $item) { throw "No group '$name' found." }
        $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).AddToSelection()
    }
    Start-Sleep -Milliseconds 200
}

function Close-OwnedDialog($Dialog, [string]$Button) {
    # A dialog over Propriétés: the main window stays disabled meanwhile, so Close-Dialog can't wait for it.
    Invoke-Element (Get-DialogPart $Dialog $Button)
    Start-Sleep -Milliseconds 600
}

function Get-CompareList($Window) {
    # Comparer les groupes…: each list's groups (« name | membership », top to bottom, joined by « , »), the domain
    # each row shows (« name: domain »), the right edge of those domains, and its title, by a, both and b.
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    $isDomain = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'compare_domain')
    $lists = @{}
    foreach ($side in 'a', 'both', 'b') {
        $items = @((Get-DialogPart $Window "compare_list_$side").FindAll($Descendants, $isItem))
        $lists[$side] = @($items | ForEach-Object { $_.Current.Name }) -join ', '
        $domains = @($items | ForEach-Object { $_.FindFirst($Descendants, $isDomain) })
        $lists["domains_$side"] = @(for ($i = 0; $i -lt $items.Count; $i++) {
            $name = ($items[$i].Current.Name -split ' [|] ')[0]
            if ($domains[$i]) { "${name}: $($domains[$i].Current.Name)" } else { "${name}: (none)" }
        }) -join ', '
        $lists["right_$side"] = @($domains | Where-Object { $_ } | ForEach-Object { [Math]::Round($_.Current.BoundingRectangle.Right) } | Sort-Object -Unique)
        $lists["head_$side"] = (Get-DialogPart $Window "compare_head_$side").Current.Name
    }
    $lists
}

function Test-UserDetail {
    # The fake AD: Marc Durand locked out (5 bad passwords; the domain locks at 5), Julie Bertrand in GG-Accueil and
    # GG-VPN, in Utilisateurs du domaine (primary) and DL-Partage-Accueil through GG-Accueil, Léa Perrin whose account
    # expires in 20 days, Hugo Tremblay in 11 groups. Admins du domaine can't be changed.
    Show-UserPage

    Invoke-Check 'Propriétés: the lockout as the PDC counts it, and Déverrouiller there' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $details = Open-UserDetail 'Verrouillés' '' 'Marc Durand'
        if ((Get-UserDetailText $details 'lockout') -notlike 'Verrouillé depuis le *') { $problems.Add("Verrouillage says '$(Get-UserDetailText $details 'lockout')'") }
        if ((Get-UserDetailText $details 'bad_count') -ne '5 (le compte se verrouille à 5)') { $problems.Add("Mauvais mots de passe says '$(Get-UserDetailText $details 'bad_count')'") }
        $reads = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -eq 'Get-ADUser' -and $_.Identity })
        if (-not $reads.Count -or $reads[0].Server -ne 'dc1.demo.local') { $problems.Add("the user was read on: $(@($reads | ForEach-Object Server) -join ', ')") }
        if ($ScreenshotDirectory) { Save-Screenshot 'utilisateurs-proprietes' $details }
        # A search replaces the page's rows while the window is open: it doesn't wait for it to close.
        $rows = @(Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert')
        if (-not $rows.Count -or @($rows | Where-Object { $_ -like '*Marc Durand*' }).Count) { $problems.Add("the search while Propriétés is open shows: $($rows -join ' // ')") }
        Invoke-Element (Get-DialogPart $details 'user_detail_unlock')
        Start-Sleep -Milliseconds 600
        if (-not @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Unlock-ADAccount').Count) { $problems.Add('Déverrouiller sent nothing') }
        if ((Get-UserDetailText $details 'lockout') -ne 'Non verrouillé') { $problems.Add("after Déverrouiller, Verrouillage says '$(Get-UserDetailText $details 'lockout')'") }
        # Shown again, Marc's row follows; and while the page shows him, so does his row at once.
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'mdurand'
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike 'Actif | Marc Durand | *') { $problems.Add("the page's row says '$row'") }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: the main window stays usable while it is open, and Propriétés… again brings the same window to the front' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        if (-not (Test-WindowEnabled)) { $problems.Add('the main window is disabled while Propriétés is open') }
        Invoke-Element (Find-Control 'user_details')
        Start-Sleep -Milliseconds 600
        $count = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Julie Bertrand' }).Count
        if ($count -ne 1) { $problems.Add("Propriétés… again: $count windows") }
        Close-UserDetail $details
    }

    Invoke-Check "Propriétés: Courriel, Identifiant and the UPN have a Copier button; a user without an email has none for it" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        Set-Clipboard -Value 'avant'
        Invoke-Element (Get-DialogPart $details 'user_detail_copy_mail')
        Start-Sleep -Milliseconds 400
        if ((Get-Clipboard) -ne 'jbertrand@demo.local') { $problems.Add("Courriel's button copied '$(Get-Clipboard)'") }
        $toast = (Get-DialogPart $details 'user_detail_status').Current.Name
        if ($toast -ne 'Courriel copié.') { $problems.Add("the toast says '$toast'") }
        Invoke-Element (Get-DialogPart $details 'user_detail_copy_login')
        Start-Sleep -Milliseconds 400
        if ((Get-Clipboard) -ne 'jbertrand') { $problems.Add("Identifiant's button copied '$(Get-Clipboard)'") }
        if (-not (Get-DialogPart $details 'user_detail_copy_upn')) { $problems.Add('the UPN has no Copier button') }
        Close-UserDetail $details

        $details = Open-UserDetail 'Description contient' 'sauvegarde' 'Sauvegarde'
        if (Get-DialogPart $details 'user_detail_copy_mail') { $problems.Add('a user without an email has a Copier button for it') }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: Désactiver… after a confirmation, Activer, and Nouveau mot de passe…, the window and the row following' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'lefebvre' 'Luc Lefebvre'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_detail_toggle')
        $confirm = Wait-OwnedDialog $details 'Désactiver'
        if ((Get-DialogText $confirm) -notlike 'Désactiver Luc Lefebvre ?*') { $problems.Add("the confirmation says '$(Get-DialogText $confirm)'") }
        Close-OwnedDialog $confirm 'dialog_ok'
        if ((Get-UserDetailText $details 'state') -ne 'Désactivé') { $problems.Add("after Désactiver…, État says '$(Get-UserDetailText $details 'state')'") }
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike 'Désactivé | Luc Lefebvre | *') { $problems.Add("after Désactiver…, the page's row says '$row'") }
        Invoke-Element (Get-DialogPart $details 'user_detail_toggle')
        Start-Sleep -Milliseconds 600
        if ((Get-UserDetailText $details 'state') -ne 'Actif') { $problems.Add("after Activer, État says '$(Get-UserDetailText $details 'state')'") }
        $sent = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*able-ADAccount' | ForEach-Object Command) -join ' | '
        if ($sent -ne 'Disable-ADAccount | Enable-ADAccount') { $problems.Add("sent: $sent") }

        Invoke-Element (Get-DialogPart $details 'user_detail_reset')
        $reset = Wait-OwnedDialog $details 'Nouveau mot de passe'
        Close-OwnedDialog $reset 'dialog_ok'
        $shown = Wait-OwnedDialog $details 'Mot de passe réinitialisé'
        if (-not $shown) { $problems.Add('no new password shown over Propriétés') }
        else { Close-OwnedDialog $shown 'dialog_cancel' }
        if ((Get-UserDetailText $details 'password_expiry') -ne 'À changer à la connexion') { $problems.Add("after Nouveau mot de passe…, Expiration says '$(Get-UserDetailText $details 'password_expiry')'") }
        Close-UserDetail $details
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike 'Actif | Luc Lefebvre | * | À changer à la connexion | *') { $problems.Add("then the page's row says '$row'") }
    }

    Invoke-Check "Propriétés: Nouveau mot de passe… on the page while it's open, then Actualiser there: both show the new password's state" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'lperrin' 'Léa Perrin'
        if ((Get-UserDetailText $details 'password_expiry') -eq 'À changer à la connexion') { throw 'Léa Perrin is already to change at the next logon.' }
        Select-UserRow 'Léa Perrin'
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog 'Nouveau mot de passe'
        Start-Sleep -Milliseconds 300
        $toggle = (Get-DialogPart $dialog 'reset_must_change').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle.Current.ToggleState -ne 'On') { $toggle.Toggle() }
        Invoke-Element (Get-DialogPart $dialog 'dialog_ok')
        $shown = Wait-Dialog 'Mot de passe réinitialisé'
        Start-Sleep -Milliseconds 300
        Close-Dialog $shown 'dialog_cancel'
        # The window's copy of the row is the one from before: read again, it doesn't put it back on the page.
        Invoke-Element (Get-DialogPart $details 'user_detail_refresh')
        Start-Sleep -Milliseconds 600
        if ((Get-UserDetailText $details 'password_expiry') -ne 'À changer à la connexion') { $problems.Add("after Actualiser, Expiration says '$(Get-UserDetailText $details 'password_expiry')'") }
        $row = @(Get-DialogRow (Find-Control 'user_grid'))[0]
        if ($row -notlike '* | Léa Perrin | * | À changer à la connexion | *') { $problems.Add("after Actualiser, the page's row says '$row'") }
        Close-UserDetail $details
    }

    Invoke-Check "Propriétés: Désactiver… and Activer on the page, while the account's Propriétés is open, show in it at once" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'lperrin' 'Léa Perrin'
        Select-UserRow 'Léa Perrin'
        Invoke-Element (Find-Control 'user_toggle')
        Close-Dialog (Wait-Dialog 'Désactiver') 'dialog_ok'
        $null = Wait-ActionNotice 'Désactivé : ✔ lperrin'
        Start-Sleep -Milliseconds 600
        if ((Get-UserDetailText $details 'state') -ne 'Désactivé') { $problems.Add("after Désactiver… on the page, État says '$(Get-UserDetailText $details 'state')'") }
        Invoke-Element (Find-Control 'user_toggle')
        $null = Wait-ActionNotice 'Activé : ✔ lperrin'
        Start-Sleep -Milliseconds 600
        if ((Get-UserDetailText $details 'state') -ne 'Actif') { $problems.Add("after Activer on the page, État says '$(Get-UserDetailText $details 'state')'") }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: centered over the main window, maximized too; a group opened from it a little lower and to the right; all above the taskbar, the main window low on the screen too' {
        param($problems)
        Add-Type -AssemblyName System.Windows.Forms
        $workArea = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int]$window.Current.BoundingRectangle.Left + 50, [int]$window.Current.BoundingRectangle.Top + 10)).WorkingArea
        # Within the work area, to 1 px for rounding: the old shift of 28 over a maximized main window went 8 px under
        # the taskbar.
        $outside = {
            param($box)
            $box.Left -lt $workArea.Left - 1 -or $box.Top -lt $workArea.Top - 1 -or $box.Right -gt $workArea.Right + 1 -or $box.Bottom -gt $workArea.Bottom + 1
        }
        # The window and a group opened from it, the group a little to the right and as much lower as the screen leaves
        # room for.
        $checkPair = {
            param([string]$Case)
            $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
            $box = $details.Current.BoundingRectangle
            if (& $outside $box) { $problems.Add("$($Case): Julie's window at $box leaves the work area $workArea") }
            $null = Invoke-Element (Get-DialogPart $details 'user_group_open_0')
            $group = Wait-Dialog 'Propriétés de GG-Accueil'
            Start-Sleep -Milliseconds 400
            $inner = $group.Current.BoundingRectangle
            if (& $outside $inner) { $problems.Add("$($Case): GG-Accueil at $inner leaves the work area $workArea") }
            $dx = [int]($inner.Left - $box.Left)
            $dy = [int]($inner.Top - $box.Top)
            if ($dx -ne 28 -or $dy -lt 0 -or $dy -gt 28) { $problems.Add("$($Case): GG-Accueil opened at $dx, $dy from Julie's window") }
            $null = Close-OwnedWindow $group
            $null = Close-UserDetail $details
            $box
        }
        $pattern = $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
        $transform = $window.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern)
        $before = $window.Current.BoundingRectangle
        try {
            $pattern.SetWindowVisualState('Maximized')
            Start-Sleep -Milliseconds 600
            $main = $window.Current.BoundingRectangle
            $box = & $checkPair 'over the maximized main window'
            $dx = [int](($box.Left + $box.Width / 2) - ($main.Left + $main.Width / 2))
            $dy = [int](($box.Top + $box.Height / 2) - ($main.Top + $main.Height / 2))
            if ([Math]::Abs($dx) -gt 20 -or [Math]::Abs($dy) -gt 20) { $problems.Add("over the maximized main window, off its center by $dx, $dy") }

            # The main window low on the screen, its bottom past the taskbar: Propriétés stays above it.
            $pattern.SetWindowVisualState('Normal')
            Start-Sleep -Milliseconds 400
            $transform.Move($before.Left, $workArea.Bottom - $before.Height / 2)
            Start-Sleep -Milliseconds 500
            $null = & $checkPair 'the main window low on the screen'
        }
        finally {
            $pattern.SetWindowVisualState('Normal')
            $transform.Move($before.Left, $before.Top)
            Start-Sleep -Milliseconds 400
        }
    }

    Invoke-Check "Propriétés: a member whose window is open already comes to the front, without being read again" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        Invoke-Element (Get-DialogPart $details 'user_group_open_0')
        $group = Wait-Dialog 'Propriétés de GG-Accueil'
        Wait-DetailRead $group
        $queriesBefore = @(Get-LoggedQuery).Count
        $julie = @(Get-DetailList $group 'group_member') | ForEach-Object { $_ } | Select-Object -First 1
        if ($julie -notlike 'Julie Bertrand |*') { throw "GG-Accueil's first member is '$julie'" }
        Invoke-Element (Get-DialogPart $group 'group_member_open_0')
        Start-Sleep -Milliseconds 600
        $count = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Julie Bertrand' }).Count
        if ($count -ne 1) { $problems.Add("Julie opened again: $count windows") }
        $reads = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADUser').Count
        if ($reads) { $problems.Add("Julie was read $reads times") }
        Close-OwnedWindow $group
        Close-UserDetail $details
    }

    Invoke-Check 'Comparer les groupes…: two users of the page side by side, filtered, copied and exported; a group opens from it' {
        param($problems)
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        Select-UserRow 'Julie Bertrand'
        if ((Find-Control 'user_compare').Current.IsEnabled) { $problems.Add('Comparer les groupes… is enabled for one user') }
        Select-UserRow 'Jean Bertrand' -Add
        Invoke-Element (Find-Control 'user_compare')
        $compare = Wait-Dialog 'Groupes de Julie Bertrand et de Jean Bertrand'
        Start-Sleep -Milliseconds 400
        $lists = Get-CompareList $compare
        if ($lists.a -ne 'DL-Partage-Accueil | Héritée, GG-Accueil | Directe') { $problems.Add("Seulement Julie: $($lists.a)") }
        if ($lists.both -ne 'GG-VPN | Directe, Utilisateurs du domaine | Principale') { $problems.Add("Les deux: $($lists.both)") }
        if ($lists.b) { $problems.Add("Seulement Jean: $($lists.b)") }
        $heads = "$($lists.head_a) / $($lists.head_both) / $($lists.head_b)"
        if ($heads -ne 'Seulement Julie Bertrand (2) / Les deux (2) / Seulement Jean Bertrand (0)') { $problems.Add("titles: $heads") }
        # Each group's domain, on every row, lined up at the list's right edge.
        if ($lists.domains_a -ne 'DL-Partage-Accueil: demo.local, GG-Accueil: demo.local') { $problems.Add("Seulement Julie's domains: $($lists.domains_a)") }
        if ($lists.domains_both -ne 'GG-VPN: demo.local, Utilisateurs du domaine: demo.local') { $problems.Add("Les deux's domains: $($lists.domains_both)") }
        foreach ($side in 'a', 'both') {
            if (@($lists["right_$side"]).Count -ne 1) { $problems.Add("the domains of list $side end at: $($lists["right_$side"] -join ', ')") }
        }
        if ($ScreenshotDirectory) { Save-Screenshot 'utilisateurs-comparer-groupes' $compare }

        (Get-DialogPart $compare 'compare_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('vpn')
        Start-Sleep -Milliseconds 300
        $lists = Get-CompareList $compare
        if ($lists.a -or $lists.both -ne 'GG-VPN | Directe' -or $lists.head_both -ne 'Les deux (1 / 2)') { $problems.Add("filtered on vpn: '$($lists.a)' / '$($lists.both)' ($($lists.head_both))") }
        Set-Clipboard -Value 'avant'
        Invoke-Element (Get-DialogPart $compare 'compare_copy')
        Start-Sleep -Milliseconds 300
        $copied = (Get-Clipboard) -join ' | '
        if ($copied -ne 'Groupes de Julie Bertrand et de Jean Bertrand |  | Seulement Julie Bertrand (0) |  | Les deux (1) |   GG-VPN (Directe) |  | Seulement Jean Bertrand (0)') { $problems.Add("copied: $copied") }
        Remove-Item -LiteralPath $exportFile -ErrorAction SilentlyContinue
        Invoke-Element (Get-DialogPart $compare 'compare_export')
        Start-Sleep -Milliseconds 400
        $exported = @(Read-Export | ForEach-Object { "$($_.Groupe) | $($_.Domaine) | $($_.jbertrand) | $($_.jebertrand)" }) -join ' // '
        if ($exported -ne 'GG-VPN | demo.local | Directe | Directe') { $problems.Add("exported: $exported") }

        # Entrée on a group opens its Propriétés.
        (Get-DialogPart $compare 'compare_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
        Start-Sleep -Milliseconds 300
        $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
        $accueil = @((Get-DialogPart $compare 'compare_list_a').FindAll($Descendants, $isItem) | Where-Object { $_.Current.Name -eq 'GG-Accueil | Directe' })[0]
        $accueil.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        $accueil.SetFocus()
        Send-Key 0x0D $compare
        $group = Wait-Dialog 'Propriétés de GG-Accueil'
        Close-OwnedWindow $group
        # Closed, the group's Propriétés gives the focus back to the comparison it was opened from.
        if (-not (Test-Foreground $compare)) { $problems.Add("after the group's Propriétés closed, the comparison isn't in front (foreground: $([RepereFocus]::GetForegroundWindow()))") }

        # Asked again: the same window comes to the front.
        Invoke-Element (Find-Control 'user_compare')
        Start-Sleep -Milliseconds 800
        $count = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Groupes de Julie Bertrand et de Jean Bertrand' }).Count
        if ($count -ne 1) { $problems.Add("Comparer les groupes… again: $count windows") }
        Close-UserDetail $compare
        if (-not (Test-Foreground $window)) { $problems.Add("after the comparison closed, the main window isn't in front") }
    }

    Invoke-Check 'Comparer avec… in Propriétés › Groupes: the other user found by a search, in another domain too' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        Invoke-Element (Get-DialogPart $details 'user_group_compare')
        $pick = Wait-OwnedDialog $details 'Comparer les groupes'
        (Get-DialogPart $pick 'compare_user_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('bert')
        Start-Sleep -Milliseconds 900
        $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
        $found = @((Get-DialogPart $pick 'compare_user_results').FindAll($Descendants, $isItem) | ForEach-Object { $_.Current.Name }) -join ', '
        if ($found -ne 'Jean Bertrand | jebertrand, Paul Bertrand | pbertrand') { $problems.Add("found: $found") }
        # One user can be chosen (the first is, at first): Paul selected in its place.
        $paul = @((Get-DialogPart $pick 'compare_user_results').FindAll($Descendants, $isItem) | Where-Object { $_.Current.Name -eq 'Paul Bertrand | pbertrand' })[0]
        $paul.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 200
        Close-OwnedDialog $pick 'dialog_ok'
        $compare = Wait-OwnedDialog $details 'Groupes de Julie Bertrand et de Paul Bertrand'
        Start-Sleep -Milliseconds 400
        $lists = Get-CompareList $compare
        if ($lists.a -ne 'DL-Partage-Accueil | Héritée, GG-Accueil | Directe, GG-VPN | Directe, Utilisateurs du domaine | Principale') { $problems.Add("Seulement Julie: $($lists.a)") }
        if ($lists.both) { $problems.Add("Les deux: $($lists.both)") }
        if ($lists.b -ne 'Utilisateurs du domaine | Principale') { $problems.Add("Seulement Paul (nord.demo.local's group): $($lists.b)") }
        # Two groups of one name, told apart by their domain, shown the same way on both sides.
        if ($lists.domains_a -notlike '*Utilisateurs du domaine: demo.local' -or $lists.domains_a -like '*(none)*') { $problems.Add("Seulement Julie's domains: $($lists.domains_a)") }
        if ($lists.domains_b -ne 'Utilisateurs du domaine: nord.demo.local') { $problems.Add("Seulement Paul's domains: $($lists.domains_b)") }
        if ($ScreenshotDirectory) { Save-Screenshot 'utilisateurs-comparer-domaines' $compare }
        Close-UserDetail $compare
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: the groups, direct, primary and inherited; two added at once, two removed after one confirmation, one refused' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        $groups = (Get-UserDetailGroup $details) -join ', '
        if ($groups -ne 'GG-Accueil | Directe, GG-VPN | Directe, Utilisateurs du domaine | Principale, DL-Partage-Accueil | Héritée') { $problems.Add("groups: $groups") }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_group_add')
        $add = Wait-OwnedDialog $details 'Ajouter à un groupe'
        # GG-VPN, the only « vpn » group, is hers already: left out, and said, rather than « aucun groupe ».
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('vpn')
        Start-Sleep -Milliseconds 900
        $hint = (Get-DialogPart $add 'group_hint').Current.Name
        if ($hint -ne 'Déjà membre de chaque groupe dont le nom contient « vpn ».') { $problems.Add("for vpn, the list says '$hint'") }
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('gg')
        Start-Sleep -Milliseconds 900
        Select-GroupChoice $add 'GG-Ventes', 'GG-Logiciel-Office'
        Close-OwnedDialog $add 'dialog_ok'
        Wait-LoggedCommand 'Add-ADGroupMember' $queriesBefore 2
        $added = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Add-ADGroupMember' | ForEach-Object Identity | Sort-Object) -join ' | '
        if ($added -ne 'CN=GG-Logiciel-Office,OU=Groupes,DC=demo,DC=local | CN=GG-Ventes,OU=Groupes,DC=demo,DC=local') { $problems.Add("additions: $added") }
        $groups = (Get-UserDetailGroup $details) -join ', '
        if ($groups -ne 'GG-Accueil | Directe, GG-Logiciel-Office | Directe, GG-Ventes | Directe, GG-VPN | Directe, Utilisateurs du domaine | Principale, DL-Partage-Accueil | Héritée') { $problems.Add("after adding, the groups: $groups") }

        foreach ($name in 'GG-VPN', 'GG-Logiciel-Office') {
            $details.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, "Choisir $name")).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        }
        Start-Sleep -Milliseconds 200
        $label = (Get-DialogPart $details 'user_group_remove_label').Current.Name
        if ($label -ne 'Retirer (2)…') { $problems.Add("the button says '$label'") }
        Invoke-Element (Get-DialogPart $details 'user_group_remove')
        $confirm = Wait-OwnedDialog $details 'Retirer du groupe'
        if ((Get-DialogText $confirm) -notlike 'Retirer Julie Bertrand de 2 groupes ?*GG-*GG-*') { $problems.Add("the confirmation says '$(Get-DialogText $confirm)'") }
        Close-OwnedDialog $confirm 'dialog_ok'
        Wait-LoggedCommand 'Remove-ADGroupMember' $queriesBefore 2
        $removed = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Remove-ADGroupMember').Count
        if ($removed -ne 2) { $problems.Add("removals sent: $removed") }
        $groups = (Get-UserDetailGroup $details) -join ', '
        if ($groups -ne 'GG-Accueil | Directe, GG-Ventes | Directe, Utilisateurs du domaine | Principale, DL-Partage-Accueil | Héritée') { $problems.Add("then the groups: $groups") }

        # Admins du domaine is offered, marked Privilégié (#233); ticked, Ajouter asks again, red, Annuler the default:
        # Enter adds nothing. Confirmed the second time, AD refuses it.
        $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
        foreach ($answer in 'enter', 'ok') {
            Invoke-Element (Get-DialogPart $details 'user_group_add')
            $add = Wait-OwnedDialog $details 'Ajouter à un groupe'
            (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('admins')
            Start-Sleep -Milliseconds 900
            $marked = @((Get-DialogPart $add 'group_results').FindAll($Descendants, $isText) | Where-Object { $_.Current.Name -eq 'Privilégié' -and -not $_.Current.IsOffscreen }).Count
            if ($answer -eq 'enter' -and $marked -ne 1) { $problems.Add("Admins du domaine shows $marked Privilégié marks") }
            Select-GroupChoice $add 'Admins du domaine'
            Close-OwnedDialog $add 'dialog_ok'
            $confirm = Wait-OwnedDialog $details 'Ajouter à un groupe'
            $text = Get-DialogText $confirm
            if ($text -notlike 'Ajouter Julie Bertrand à Admins du domaine ?*Admins du domaine est un groupe privilégié*') { $problems.Add("the privileged group's confirmation says '$text'") }
            $queriesBefore = @(Get-LoggedQuery).Count
            if ($answer -eq 'enter') {
                Send-Key 0x0D $confirm
                Start-Sleep -Milliseconds 600
                if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Add-ADGroupMember').Count) { $problems.Add('Enter added her to Admins du domaine') }
            }
            else { Close-OwnedDialog $confirm 'dialog_ok' }
        }
        $report = Wait-OwnedDialog $details 'Ajouter à un groupe'
        $text = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($text -ne '✖ jbertrand : non ajouté à Admins du domaine (Droits insuffisants pour cette opération)') { $problems.Add("the refusal says '$text'") }
        Close-OwnedDialog $report 'dialog_cancel'
        # HR's fields are read only: nothing in the window can be typed into.
        $isEdit = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
        if (@($details.FindAll($Descendants, $isEdit)).Count) { $problems.Add('the window has a box to type in') }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: a long Groupes has a box to filter it, by name or description, without accents; a group ticked stays ticked and counted while hidden; Échap clears the box, then closes (#322)' {
        param($problems)
        # Hugo Tremblay is in 10 Atelier-… groups and Utilisateurs du domaine.
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'htremblay' 'Hugo Tremblay'
        $all = @(Get-UserDetailGroup $details).Count
        if ($all -ne 11) { $problems.Add("$all groups listed") }
        $box = Get-DialogPart $details 'user_group_filter'
        if (-not $box) { $problems.Add('Groupes has no box to filter it'); Close-UserDetail $details; return }
        $value = $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $pick = { $details.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Choisir Atelier-Bois')) }
        (& $pick).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 200
        $value.SetValue('metal')
        Start-Sleep -Milliseconds 300
        $groups = (Get-UserDetailGroup $details) -join ', '
        if ($groups -ne 'Atelier-Métal | Directe') { $problems.Add("for « metal », the groups: $groups") }
        $label = (Get-DialogPart $details 'user_group_remove_label').Current.Name
        if ($label -ne 'Retirer (1)…') { $problems.Add("Atelier-Bois ticked and hidden, the button says '$label'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'proprietes-groupes-filtre' $details }
        # At Grande and Très grande text, the box grows with its text, and stays within the window (a card's panel is a
        # Border, which UI Automation doesn't show).
        $settingsWindow = Open-SettingsSection 'appearance'
        try {
            foreach ($size in @(@('text_size_large', 1.15), @('text_size_larger', 1.3))) {
                Invoke-Element (Get-DialogPart $settingsWindow $size[0])
                Start-Sleep -Milliseconds 700
                $rect = $box.Current.BoundingRectangle
                $frame = $details.Current.BoundingRectangle
                if ($rect.Left -lt $frame.Left -or $rect.Right -gt $frame.Right -or $rect.Height -lt 28 * $size[1]) { $problems.Add("$($size[0]): the box is at $rect, in a window at $frame") }
                if ($ScreenshotDirectory) {
                    # The cards scrolled until the box is at the top of what shows, then back.
                    $scrollPart = Get-DialogPart $details 'user_detail_scroll'
                    $scroll = $scrollPart.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
                    for ($i = 0; $i -lt 20 -and $box.Current.BoundingRectangle.Top -gt $scrollPart.Current.BoundingRectangle.Top + 80 -and $scroll.Current.VerticalScrollPercent -lt 100; $i++) {
                        $scroll.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount, [System.Windows.Automation.ScrollAmount]::SmallIncrement)
                        Start-Sleep -Milliseconds 50
                    }
                    Start-Sleep -Milliseconds 200
                    Save-Screenshot "proprietes-groupes-filtre-$($size[0])" $details
                    $scroll.SetScrollPercent(-1, 0)
                }
            }
        }
        finally {
            Invoke-Element (Get-DialogPart $settingsWindow 'text_size_normal')
            Start-Sleep -Milliseconds 500
            $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
            Start-Sleep -Milliseconds 300
        }
        $value.SetValue('MENUISERIE')
        Start-Sleep -Milliseconds 300
        $groups = (Get-UserDetailGroup $details) -join ', '
        if ($groups -ne 'Atelier-Bois | Directe') { $problems.Add("for « MENUISERIE » (its description), the groups: $groups") }
        $value.SetValue('zzz')
        Start-Sleep -Milliseconds 300
        $none = Get-DialogPart $details 'user_group_filter_none'
        if (@(Get-UserDetailGroup $details).Count -or -not $none -or $none.Current.Name -ne 'Aucun groupe.') { $problems.Add("for « zzz », the groups: $((Get-UserDetailGroup $details) -join ', '), and the line: $(if ($none) { $none.Current.Name } else { '(not shown)' })") }
        $box.SetFocus()
        Send-Key 0x1B $details
        $shown = @(Get-UserDetailGroup $details).Count
        if ($shown -ne 11 -or $value.Current.Value) { $problems.Add("after Échap, the box holds '$($value.Current.Value)' and $shown groups are listed") }
        $state = (& $pick).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
        if ($state -ne 'On') { $problems.Add("after the filter, Atelier-Bois is $state") }
        if (-not @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Hugo Tremblay' }).Count) { $problems.Add('Échap in the box closed the window') }
        Send-Key 0x1B $details
        Start-Sleep -Milliseconds 300
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Hugo Tremblay' }).Count) { $problems.Add('Échap, the box empty, left the window open'); Close-UserDetail $details }
    }

    Invoke-Check "Propriétés: Ajouter à un groupe searches the other domains when the user's has none, adds the user to one, and Retirer takes it out" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_group_add')
        $add = Wait-OwnedDialog $details 'Ajouter à un groupe'
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('nord')
        Start-Sleep -Milliseconds 900
        # nord.demo.local's Personnel-Nord is global: not offered.
        $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
        $names = @((Get-DialogPart $add 'group_results').FindAll($Descendants, $isItem) | ForEach-Object { $_.Current.Name }) -join ', '
        if ($names -ne 'DL-Imprimantes-Nord, GU-Postes-Nord') { $problems.Add("offered: $names") }
        $note = (Get-DialogPart $add 'group_note').Current.Name
        if ($note -ne 'Aucun dans demo.local : voici ceux des autres domaines.') { $problems.Add("the note says '$note'") }
        Select-GroupChoice $add 'DL-Imprimantes-Nord'
        Close-OwnedDialog $add 'dialog_ok'
        Wait-LoggedCommand 'Add-ADGroupMember' $queriesBefore
        $added = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Add-ADGroupMember' | ForEach-Object { "$($_.Server) $($_.Identity)" }) -join ' | '
        if ($added -ne 'nord.demo.local CN=DL-Imprimantes-Nord,OU=Groupes,DC=nord,DC=demo,DC=local') { $problems.Add("additions: $added") }
        if (@(Get-UserDetailGroup $details) -notcontains 'DL-Imprimantes-Nord | Directe') { $problems.Add("after adding, the groups: $((Get-UserDetailGroup $details) -join ', ')") }

        $details.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Choisir DL-Imprimantes-Nord')).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 200
        Invoke-Element (Get-DialogPart $details 'user_group_remove')
        $confirm = Wait-OwnedDialog $details 'Retirer du groupe'
        Close-OwnedDialog $confirm 'dialog_ok'
        Wait-LoggedCommand 'Remove-ADGroupMember' $queriesBefore
        $removed = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Remove-ADGroupMember' | ForEach-Object { "$($_.Server) $($_.Identity)" }) -join ' | '
        if ($removed -ne 'nord.demo.local CN=DL-Imprimantes-Nord,OU=Groupes,DC=nord,DC=demo,DC=local') { $problems.Add("removals: $removed") }
        if (@(Get-UserDetailGroup $details) -contains 'DL-Imprimantes-Nord | Directe') { $problems.Add('after Retirer, DL-Imprimantes-Nord is still listed') }

        # With the box ticked, the other domains are searched too, after the user's: Windows' own groups left out.
        Invoke-Element (Get-DialogPart $details 'user_group_add')
        $add = Wait-OwnedDialog $details 'Ajouter à un groupe'
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('postes')
        Start-Sleep -Milliseconds 900
        (Get-DialogPart $add 'group_other_domains').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 900
        $names = @((Get-DialogPart $add 'group_results').FindAll($Descendants, $isItem) | ForEach-Object { $_.Current.Name }) -join ', '
        if ($names -ne 'GG-Postes-Accueil, GU-Postes-Nord') { $problems.Add("with the other domains, offered: $names") }
        # Ajouter follows the ticks: none at first, one ticked, then none again once another search empties the list.
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is enabled before a group is ticked') }
        Select-GroupChoice $add 'GG-Postes-Accueil'
        if (-not (Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is disabled with a group ticked') }
        (Get-DialogPart $add 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('nord')
        Start-Sleep -Milliseconds 900
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter stays enabled after another search leaves nothing ticked') }
        Close-OwnedDialog $add 'dialog_cancel'
        Close-UserDetail $details
    }

    Invoke-Check "Propriétés: a user whose inherited groups can't be read (tokenGroups refused) still opens, and says so" {
        param($problems)
        $details = Open-UserDetail 'Description contient' 'sauvegarde' 'Sauvegarde'
        $groups = (Get-UserDetailGroup $details) -join ', '
        if ($groups -ne 'Utilisateurs du domaine | Principale, Groupes hérités | Héritée') { $problems.Add("groups: $groups") }
        if ((Get-UserDetailText $details 'login') -ne 'svc-sauvegarde') { $problems.Add("the login says '$(Get-UserDetailText $details 'login')'") }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: a card folds by its whole header, and stays folded the next time' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        # The header's toggle reaches the card's actions (Groupes: Retirer…), as in Caractéristiques.
        $toggle = (Get-DialogPart $details 'user_section_groupes').Current.BoundingRectangle
        $action = (Get-DialogPart $details 'user_group_remove').Current.BoundingRectangle
        if ($action.Left - $toggle.Right -gt 16) { $problems.Add("the header stops $([int]($action.Left - $toggle.Right)) px before Retirer…") }
        (Get-DialogPart $details 'user_section_groupes').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 300
        if (@(Get-UserDetailGroup $details).Count) { $problems.Add('folded, Groupes still shows its groups') }
        Close-UserDetail $details
        $saved = Read-SavedSetting 'apparence.json'
        if (@($saved.FoldedSections) -notcontains 'groupes') { $problems.Add("apparence.json holds FoldedSections: $(@($saved.FoldedSections) -join ', ')") }
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        if (@(Get-UserDetailGroup $details).Count) { $problems.Add('opened again, Groupes is unfolded') }
        (Get-DialogPart $details 'user_section_groupes').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 300
        if (-not @(Get-UserDetailGroup $details).Count) { $problems.Add("unfolded, Groupes doesn't show its groups") }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: Tout réduire folds every card and Tout développer unfolds them, kept for the next window, both in reach however far the cards are scrolled' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        Test-DetailFoldBarInView $details 'user_detail' $problems
        Invoke-Element (Get-DialogPart $details 'user_detail_collapse_all')
        Start-Sleep -Milliseconds 300
        if (@(Get-UserDetailGroup $details).Count) { $problems.Add('after Tout réduire, Groupes still shows its groups') }
        if (Get-DialogPart $details 'user_detail_state') { $problems.Add('after Tout réduire, Compte still shows its values') }
        $folded = @((Read-SavedSetting 'apparence.json').FoldedSections | Sort-Object) -join ', '
        if ($folded -ne 'compte, groupes, identite, motdepasse, organisation, profil, verrouillage') { $problems.Add("after Tout réduire, FoldedSections: $folded") }
        Close-UserDetail $details
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        if (Get-DialogPart $details 'user_detail_state') { $problems.Add('opened again, Compte is unfolded') }
        Invoke-Element (Get-DialogPart $details 'user_detail_expand_all')
        Start-Sleep -Milliseconds 300
        if (-not @(Get-UserDetailGroup $details).Count -or -not (Get-DialogPart $details 'user_detail_mail')) { $problems.Add("after Tout développer, a card is still folded") }
        $folded = @((Read-SavedSetting 'apparence.json').FoldedSections) -join ', '
        if ($folded) { $problems.Add("after Tout développer, FoldedSections: $folded") }
        Close-UserDetail $details
    }

    Invoke-Check "Propriétés: Ordinateurs searches the user's computers on the Ordinateurs page, and the window stays open" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_detail_computers')
        Wait-UserComputer
        Test-UserComputer $problems $queriesBefore 'NRD-02'
        $toast = (Get-DialogPart $details 'user_detail_status').Current.Name
        if ($toast -ne 'Recherche lancée dans Ordinateurs.') { $problems.Add("the toast says '$toast'") }
        if (-not @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Julie Bertrand' }).Count) { $problems.Add('Propriétés closed') }
        Close-UserDetail $details
        Show-UserPage
    }

    Invoke-Check "Propriétés: the account's expiration, cleared, then set to the end of a day 3 months away" {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'lperrin' 'Léa Perrin'
        if ((Get-UserDetailText $details 'expiry') -notlike 'Fin du * (dans 20 jours)') { $problems.Add("Expiration says '$(Get-UserDetailText $details 'expiry')'") }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_detail_expiry_edit')
        $dialog = Wait-OwnedDialog $details 'Expiration du compte'
        (Get-DialogPart $dialog 'expiry_never').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Close-OwnedDialog $dialog 'dialog_ok'
        Wait-LoggedCommand 'Clear-ADAccountExpiration' $queriesBefore
        if (-not @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Clear-ADAccountExpiration').Count) { $problems.Add("N'expire jamais sent nothing") }
        if ((Get-UserDetailText $details 'expiry') -ne "N'expire jamais") { $problems.Add("then Expiration says '$(Get-UserDetailText $details 'expiry')'") }

        Invoke-Element (Get-DialogPart $details 'user_detail_expiry_edit')
        $dialog = Wait-OwnedDialog $details 'Expiration du compte'
        Invoke-Element (Get-DialogPart $dialog 'expiry_3')
        Close-OwnedDialog $dialog 'dialog_ok'
        Wait-LoggedCommand 'Set-ADAccountExpiration' $queriesBefore
        $set = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADAccountExpiration')
        $expected = (Get-Date).Date.AddMonths(3).AddDays(1).ToString('yyyy-MM-dd HH:mm')
        if ($set.Count -ne 1 -or $set[0].DateTime -ne $expected) { $problems.Add("expirations set: $($set | ConvertTo-Json -Compress), expected $expected") }
        if ((Get-UserDetailText $details 'expiry') -notlike 'Fin du *') { $problems.Add("then Expiration says '$(Get-UserDetailText $details 'expiry')'") }
        Close-UserDetail $details
    }

    Invoke-Check 'Propriétés: Modifier… in Organisation, Enregistrer, the card and the page''s row following; Échap cancels an edit (#138)' {
        param($problems)
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_edit_organisation')
        Start-Sleep -Milliseconds 300
        $title = Get-DialogPart $details 'user_field_title'
        if (-not $title) { $problems.Add('Modifier… shows no Poste box') }
        else {
            $shown = $title.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            if ($shown -ne "Agente d'accueil") { $problems.Add("the Poste box holds '$shown'") }
            $title.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('  Coordonnatrice ')
            Invoke-Element (Get-DialogPart $details 'user_save_organisation')
            Wait-LoggedCommand 'Set-ADUser' $queriesBefore
            $sets = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADUser')
            if ($sets.Count -ne 1 -or $sets[0].Replace -ne 'title=Coordonnatrice' -or $sets[0].Clear -or $sets[0].Server -ne 'dc1.demo.local') { $problems.Add("sent: $($sets | ConvertTo-Json -Compress)") }
            # Poste's value shares its id with the window's title (the user's name), found first.
            Wait-DetailRead $details
            $isTitle = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'user_detail_title')
            $titles = @($details.FindAll($Descendants, $isTitle) | ForEach-Object { $_.Current.Name })
            if ($titles -notcontains 'Coordonnatrice') { $problems.Add("then Poste says '$($titles -join ' / ')'") }
            if (Get-DialogPart $details 'user_field_title') { $problems.Add('the card stays in its edit once saved') }
            $row = @(Get-DialogRow (Find-Control 'user_grid') | Where-Object { $_ -like '*Julie Bertrand*' })[0]
            if ($row -notlike '*| Coordonnatrice |*') { $problems.Add("the page's row says '$row'") }
        }
        # Échap cancels the edit, sending nothing, then closes the window.
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_edit_identite')
        Start-Sleep -Milliseconds 300
        (Get-DialogPart $details 'user_field_given_name').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Juliette')
        Send-Key 0x1B $details
        if (Get-DialogPart $details 'user_field_given_name') { $problems.Add('Échap left the edit open') }
        if (-not @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Julie Bertrand' }).Count) { $problems.Add('Échap closed the window while a card was edited') }
        if ((Get-UserDetailText $details 'given_name') -ne 'Julie') { $problems.Add("after Échap, Prénom says '$(Get-UserDetailText $details 'given_name')'") }
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADUser').Count) { $problems.Add('Échap sent a Set-ADUser') }
        Send-Key 0x1B $details
        Start-Sleep -Milliseconds 300
        if (@(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de Julie Bertrand' }).Count) { $problems.Add('Échap again left the window open'); Close-UserDetail $details }
    }

    Invoke-Check 'Propriétés: Modifier… names what it refuses before sending, and the field AD refuses, keeping what was typed (#138)' {
        param($problems)
        # Jean Bertrand's employee number is one the current user has no right on (the fake AD's DenyAttributes).
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jebertrand' 'Jean Bertrand'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'user_edit_profil')
        Start-Sleep -Milliseconds 300
        (Get-DialogPart $details 'user_field_home_drive').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('HH')
        Invoke-Element (Get-DialogPart $details 'user_save_profil')
        Start-Sleep -Milliseconds 300
        $said = (Get-DialogPart $details 'user_edit_error_profil').Current.Name
        if ($said -ne 'Lecteur : une lettre de A à Z (ex. H:).') { $problems.Add("Profil's error says '$said'") }
        Invoke-Element (Get-DialogPart $details 'user_cancel_profil')
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Set-ADUser').Count) { $problems.Add('a wrong drive was sent') }

        Invoke-Element (Get-DialogPart $details 'user_edit_identite')
        Start-Sleep -Milliseconds 300
        (Get-DialogPart $details 'user_field_given_name').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Jean-Marc')
        (Get-DialogPart $details 'user_field_employee').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('99')
        Invoke-Element (Get-DialogPart $details 'user_save_identite')
        Wait-LoggedCommand 'Set-ADUser' $queriesBefore 3
        Wait-DetailRead $details
        $said = (Get-DialogPart $details 'user_edit_error_identite').Current.Name
        if ($said -notlike "Numéro d'employé : non enregistré (Droits insuffisants pour cette opération)*Enregistré : Prénom.") { $problems.Add("Identité's error says '$said'") }
        $kept = (Get-DialogPart $details 'user_field_employee')
        if (-not $kept -or $kept.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ne '99') { $problems.Add('what was typed in the field refused is lost') }
        Invoke-Element (Get-DialogPart $details 'user_cancel_identite')
        if ((Get-UserDetailText $details 'given_name') -ne 'Jean-Marc') { $problems.Add("then Prénom says '$(Get-UserDetailText $details 'given_name')'") }
        Close-UserDetail $details
    }
}

function Show-GroupPage {
    # The Groupes tab, until its page shows.
    for ($i = 0; $i -lt 3 -and -not (Find-ShownControl 'group_query'); $i++) {
        Invoke-Element (Find-Control 'tab_groups')
        for ($j = 0; $j -lt 10 -and -not (Find-ShownControl 'group_query'); $j++) { Start-Sleep -Milliseconds 200 }
    }
}

function Invoke-GroupSearch([string]$Domain, [string]$Type, [string]$Text) {
    # A search of the Groupes page, once it has answered: its rows (name | type | scope | description | domain when
    # several | OU).
    if ($Domain) { Select-ComboItem 'group_domain' $Domain }
    Select-ComboItem 'group_search_type' $Type
    (Find-Control 'group_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    Invoke-Element (Find-Control 'group_search')
    for ($i = 0; $i -lt 40 -and -not (Find-Control 'group_search').Current.IsEnabled; $i++) { Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 200
    @(Get-DialogRow (Find-Control 'group_grid'))
}

function Select-GroupRow([string]$Name, [switch]$Add) {
    # Selects the row of the Groupes page whose Nom is $Name (-Add: adds it to the selection, like Ctrl + click).
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    $row = @((Find-Control 'group_grid').FindAll($Descendants, $isRow) | Where-Object { @($_.FindAll($Descendants, $isCell) | ForEach-Object { $_.Current.Name }) -contains $Name })[0]
    if (-not $row) { throw "No '$Name' row." }
    $pattern = $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if ($Add) { $pattern.AddToSelection() } else { $pattern.Select() }
    Start-Sleep -Milliseconds 200
}

function Open-GroupMenuItem([string]$Name) {
    # The item $Name of the Groupes grid's right-click menu, opened by the context menu key (sent again when it's missed).
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        (Find-Control 'group_grid').SetFocus()
        Send-Key 0x5D
        for ($i = 0; $i -lt 10; $i++) {
            $item = @(Get-OpenMenuItem | Where-Object { $_.Current.Name -eq $Name })[0]
            if ($item) { return $item }
            Start-Sleep -Milliseconds 200
        }
    }
    throw "No '$Name' in the right-click menu."
}

function Open-GroupDetail([string]$Type, [string]$Text, [string]$Name, [string]$Domain = 'demo.local') {
    # Propriétés… of a group found by a search of the Groupes page: the window.
    $null = Invoke-GroupSearch $Domain $Type $Text
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    $row = @((Find-Control 'group_grid').FindAll($Descendants, $isRow) | Where-Object { @($_.FindAll($Descendants, $isCell) | ForEach-Object { $_.Current.Name }) -contains $Name })[0]
    if (-not $row) { throw "No '$Name' row." }
    $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 200
    Invoke-Element (Find-Control 'group_details')
    $details = Wait-Dialog "Propriétés de $Name"
    Wait-DetailRead $details
    $details
}

function Wait-PageSearch([string]$Prefix) {
    # Until a page's Rechercher is back (the search ended), then a moment for the grid.
    Start-Sleep -Milliseconds 200
    for ($i = 0; $i -lt 50 -and -not (Find-Control "$($Prefix)_search").Current.IsEnabled; $i++) { Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 300
}

function Test-SearchLimit {
    # With REPERE_SEARCH_LIMIT at 1: the computers', users' and groups' searches each ask AD for 2 (one more, to tell),
    # show 1 row, say the limit was reached in amber, and offer Tout afficher, which runs the search as it was asked
    # (not what the boxes hold since) without the limit, and is gone after.
    Invoke-Check 'Ordinateurs: past the limit, the first rows and « limite atteinte », then Tout afficher shows them all' {
        param($problems)
        Select-Domain 'demo.local'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-PrefixSearch 'ORD'
        $sizes = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object ResultSetSize)
        if (($sizes -join ',') -ne '2') { $problems.Add("ResultSetSize asked: '$($sizes -join ',')', expected 2") }
        $count = (Find-Control 'results_count').Current.Name
        if (@(Get-ResultName).Count -ne 1 -or $count -notlike '1 ordinateur · limite de 1 atteinte : précisez la recherche, ou Tout afficher*') { $problems.Add("rows: $(@(Get-ResultName).Count), count: '$count'") }
        if (-not (Find-ShownControl 'results_show_all')) { $problems.Add('Tout afficher is not shown') }
        # The boxes changed meanwhile: Tout afficher runs the search that was made.
        Set-Text 'prefix' 'NRD'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'results_show_all')
        Start-Sleep -Milliseconds 300
        Wait-SearchEnd
        $asked = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer')
        if ($asked.Count -ne 1 -or $asked[0].ResultSetSize -or $asked[0].Filter -notlike "Name -like '*ORD*'*") { $problems.Add("Tout afficher asked: $($asked | ConvertTo-Json -Compress)") }
        $count = (Find-Control 'results_count').Current.Name
        if (@(Get-ResultName).Count -ne 12 -or $count -ne '12 ordinateurs') { $problems.Add("after Tout afficher, rows: $(@(Get-ResultName).Count), count: '$count'") }
        if (Find-ShownControl 'results_show_all') { $problems.Add('Tout afficher is still shown') }
    }

    Invoke-Check 'Ordinateurs: Tout afficher keeps the column filters' {
        param($problems)
        Invoke-PrefixSearch 'ORD'
        # Nom contains « ORD-0 »: the rows Tout afficher adds are kept when they contain it too.
        Open-ColumnFilterList 'ComputerName'
        Set-Text 'colfilter_search' 'ORD-0'
        Start-Sleep -Milliseconds 200
        Close-ColumnFilterList
        Invoke-Element (Find-Control 'results_show_all')
        Start-Sleep -Milliseconds 300
        Wait-SearchEnd
        # ORD-01 to ORD-12: ORD-10 to ORD-12 don't contain ORD-0.
        $count = (Find-Control 'results_count').Current.Name
        if (@(Get-ResultName).Count -ne 9 -or $count -ne '12 ordinateurs · 9 affichés') { $problems.Add("rows: $(@(Get-ResultName).Count), count: '$count'") }
        $button = (Find-Control 'column_filters_text').Current.Name
        if ($button -ne 'Filtres (1)') { $problems.Add("the button says '$button'") }
    }

    Invoke-Check 'Utilisateurs: past the limit, one Bertrand and « limite atteinte », then Tout afficher shows both' {
        param($problems)
        Show-UserPage
        $rows = @(Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert')
        $count = (Find-Control 'user_count').Current.Name
        if ($rows.Count -ne 1 -or $count -notlike '1 utilisateur · limite de 1 atteinte*') { $problems.Add("rows: $($rows.Count), count: '$count'") }
        Invoke-Element (Find-Control 'user_show_all')
        Wait-PageSearch 'user'
        $rows = @(Get-DialogRow (Find-Control 'user_grid'))
        $count = (Find-Control 'user_count').Current.Name
        if ($rows.Count -ne 2 -or $count -ne '2 utilisateurs') { $problems.Add("after Tout afficher, rows: $($rows.Count), count: '$count'") }
        if (Find-ShownControl 'user_show_all') { $problems.Add('Tout afficher is still shown') }
    }

    Invoke-Check 'Groupes: in every domain, only the domain past the limit named, then Tout afficher shows them all' {
        param($problems)
        Show-GroupPage
        # demo.local has several groups with a g, nord.demo.local one (GU-Postes-Nord): only demo.local is named.
        $rows = @(Invoke-GroupSearch 'Tous les domaines' 'Nom contient' 'g')
        $count = (Find-Control 'group_count').Current.Name
        if ($rows.Count -ne 2 -or $count -notlike '2 groupes · limite de 1 atteinte (demo.local) : *') { $problems.Add("rows: $($rows.Count), count: '$count'") }
        Invoke-Element (Find-Control 'group_show_all')
        Wait-PageSearch 'group'
        $rows = @(Get-DialogRow (Find-Control 'group_grid'))
        $count = (Find-Control 'group_count').Current.Name
        if ($rows.Count -le 2 -or $count -like '*limite*') { $problems.Add("after Tout afficher, rows: $($rows.Count), count: '$count'") }
    }
}

function Start-SlowPageSearch([string]$Prefix, [string]$Domain, [string]$Type, [string]$Text) {
    # A search of the Utilisateurs or Groupes page in a domain that takes 8 s, without waiting for it: returns a
    # stopwatch started at the click, once Annuler shows.
    Select-ComboItem "$($Prefix)_domain" $Domain
    Select-ComboItem "$($Prefix)_search_type" $Type
    (Find-Control "$($Prefix)_query").GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-Element (Find-Control "$($Prefix)_search")
    while (-not (Find-ShownControl "$($Prefix)_cancel")) {
        if ($watch.ElapsedMilliseconds -ge 5000) { throw "Annuler didn't show up after Rechercher ($Prefix)." }
        Start-Sleep -Milliseconds 20
    }
    $watch
}

function Stop-SlowPageSearch([string]$Prefix, [string]$Domain, [string]$Type, [string]$Text) {
    # A search of the Utilisateurs or Groupes page in a domain that takes 8 s, cancelled with Annuler a second after it
    # started: before that domain answers.
    $watch = Start-SlowPageSearch $Prefix $Domain $Type $Text
    Wait-Elapsed $watch 1000
    Invoke-Element (Find-Control "$($Prefix)_cancel")
    Wait-PageSearch $Prefix
}

function Test-ShowAllAfterCancel {
    # Run with REPERE_SEARCH_LIMIT at 1 and nord.demo.local taking 8 s per call (#235): a search past the limit, then
    # another, cancelled before its domain answered, which leaves the first one's rows and Tout afficher. Tout afficher
    # then runs the first search without the limit, not the one cancelled.
    Invoke-Check 'Ordinateurs: after a search cancelled before any domain answered, Tout afficher runs the search shown' {
        param($problems)
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD'
        $count = (Find-Control 'results_count').Current.Name
        if ($count -notlike '1 ordinateur · limite de 1 atteinte*') { $problems.Add("the first search shows '$count'"); return }
        $watch = Start-SlowSearch 'nord.demo.local' 'NRD'
        try {
            Wait-Elapsed $watch 1000
            (Find-Control 'cancel_search').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Wait-SearchEnd 5
        }
        finally { Stop-RunningSearch }
        $count = (Find-Control 'results_count').Current.Name
        if ($count -notlike '1 ordinateur · limite de 1 atteinte*') { $problems.Add("after the cancel, the count is '$count'") }
        if (-not (Find-ShownControl 'results_show_all')) { $problems.Add('Tout afficher is gone after the cancel'); return }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'results_show_all')
        Start-Sleep -Milliseconds 300
        Wait-SearchEnd 5
        $asked = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer')
        if ($asked.Count -ne 1 -or $asked[0].Server -ne 'demo.local' -or $asked[0].ResultSetSize -or $asked[0].Filter -notlike "Name -like '*ORD*'*") {
            $problems.Add("Tout afficher asked: $($asked | ConvertTo-Json -Compress)")
        }
        $count = (Find-Control 'results_count').Current.Name
        if (@(Get-ResultName).Count -ne 12 -or $count -ne '12 ordinateurs') { $problems.Add("after Tout afficher, rows: $(@(Get-ResultName).Count), count: '$count'") }
    }

    Invoke-Check 'Utilisateurs: after a search cancelled before any domain answered, Tout afficher runs the search shown' {
        param($problems)
        Show-UserPage
        $rows = @(Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert')
        $count = (Find-Control 'user_count').Current.Name
        if ($rows.Count -ne 1 -or $count -notlike '1 utilisateur · limite de 1 atteinte*') { $problems.Add("the first search: rows: $($rows.Count), count: '$count'"); return }
        Stop-SlowPageSearch 'user' 'nord.demo.local' 'Nom, identifiant ou courriel' 'a'
        $rows = @(Get-DialogRow (Find-Control 'user_grid'))
        $count = (Find-Control 'user_count').Current.Name
        if ($rows.Count -ne 1 -or $count -notlike '1 utilisateur · limite de 1 atteinte*') { $problems.Add("after the cancel, rows: $($rows.Count), count: '$count'") }
        if (-not (Find-ShownControl 'user_show_all')) { $problems.Add('Tout afficher is gone after the cancel'); return }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'user_show_all')
        Wait-PageSearch 'user'
        $asked = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADUser')
        if ($asked.Count -ne 1 -or $asked[0].Server -ne 'demo.local' -or $asked[0].ResultSetSize -or $asked[0].LDAPFilter -notmatch '\(anr=bert\)') {
            $problems.Add("Tout afficher asked: $($asked | ConvertTo-Json -Compress)")
        }
        $rows = @(Get-DialogRow (Find-Control 'user_grid'))
        $count = (Find-Control 'user_count').Current.Name
        if ($rows.Count -ne 2 -or $count -ne '2 utilisateurs') { $problems.Add("after Tout afficher, rows: $($rows.Count), count: '$count'") }
    }

    Invoke-Check 'Groupes: after a search cancelled before any domain answered, Tout afficher runs the search shown' {
        param($problems)
        Show-GroupPage
        $rows = @(Invoke-GroupSearch 'demo.local' 'Nom contient' 'g')
        $count = (Find-Control 'group_count').Current.Name
        if ($rows.Count -ne 1 -or $count -notlike '1 groupe · limite de 1 atteinte*') { $problems.Add("the first search: rows: $($rows.Count), count: '$count'"); return }
        Stop-SlowPageSearch 'group' 'nord.demo.local' 'Nom contient' 'e'
        if (-not (Find-ShownControl 'group_show_all')) { $problems.Add('Tout afficher is gone after the cancel'); return }
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'group_show_all')
        Wait-PageSearch 'group'
        $asked = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -eq 'Get-ADGroup' -and $_.LDAPFilter })
        if ($asked.Count -ne 1 -or $asked[0].Server -ne 'demo.local' -or $asked[0].ResultSetSize -or $asked[0].LDAPFilter -notmatch '\(name=\*g\*\)') {
            $problems.Add("Tout afficher asked: $($asked | ConvertTo-Json -Compress)")
        }
        $rows = @(Get-DialogRow (Find-Control 'group_grid'))
        $count = (Find-Control 'group_count').Current.Name
        if ($rows.Count -le 1 -or $count -like '*limite*' -or $count -like '*erreur*') { $problems.Add("after Tout afficher, rows: $($rows.Count), count: '$count'") }
    }
}

function Close-OwnedWindow($Window) {
    # A Propriétés opened from another one (a group's from a user's or a group's), closed like its × does; then a
    # moment for the one it was opened from to read itself again.
    Close-UserDetail $Window
    Start-Sleep -Milliseconds 400
}

function Get-DetailList($Window, [string]$Prefix) {
    # A Propriétés list (group_member, group_parent): each item's « name | … », top to bottom.
    Wait-DetailRead $Window
    $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    @($Window.FindAll($Descendants, $isText) | Where-Object { $_.Current.AutomationId -match "^$($Prefix)_\d+$" } |
        Sort-Object { $_.Current.BoundingRectangle.Top } | ForEach-Object { $_.Current.Name })
}

function Select-ListChoice($Dialog, [string]$List, [string[]]$Names) {
    # Ticks these items in a dialog's list of choices.
    $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    foreach ($name in $Names) {
        $item = @((Get-DialogPart $Dialog $List).FindAll($Descendants, $isItem) | Where-Object { $_.Current.Name -eq $name })[0]
        if (-not $item) { throw "No '$name' in $List." }
        $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).AddToSelection()
    }
    Start-Sleep -Milliseconds 200
}

function Test-GroupPage {
    # The fake AD's groups: in demo.local, GG-Accueil (Julie Bertrand and Léa Perrin, managed by Nathalie Lévy) inside
    # DL-Partage-Accueil, GG-Projet-2019 empty, and Utilisateurs du domaine, everyone's primary group.
    Invoke-Check 'Groupes: its tab shows the page, and « gg » in demo.local finds its GG groups with their type and scope' {
        param($problems)
        Show-GroupPage
        if (Find-ShownControl 'prefix') { $problems.Add("the computers' search box is still shown") }
        $domains = Get-ComboItemName 'group_domain'
        if (($domains -join ' | ') -ne (@('Tous les domaines') + $fakeDomains -join ' | ')) { $problems.Add("the Domaine list holds: $($domains -join ' | ')") }
        $queriesBefore = @(Get-LoggedQuery).Count
        $rows = @(Invoke-GroupSearch 'demo.local' 'Nom contient' 'gg')
        $names = ($rows | ForEach-Object { ($_ -split ' \| ')[0] }) -join ', '
        if ($names -ne 'GG-Accueil, GG-GPO-Kiosques, GG-Logiciel-Office, GG-Postes-Accueil, GG-Projet-2019, GG-Ventes, GG-VPN') { $problems.Add("groups: $names") }
        if ($rows[0] -ne "GG-Accueil | Sécurité | Globale | Personnel de l'accueil | Groupes") { $problems.Add("GG-Accueil's row: $($rows[0])") }
        $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADGroup' | ForEach-Object { "$($_.Server) $($_.LDAPFilter)" })
        if (($searches -join ' | ') -ne 'demo.local (&(objectCategory=group)(name=*gg*))') { $problems.Add("searches: $($searches -join ' | ')") }
        $count = (Find-Control 'group_count').Current.Name
        if ($count -ne '7 groupes') { $problems.Add("the count says '$count'") }
        $tip = (Find-Control 'group_time').Current.HelpText -split "`n"
        if ($tip.Count -ne 2 -or $tip[0] -notmatch '^demo\.local : AD [\d  ]+ ms, lignes [\d  ]+ ms \(7 groupes\)$' -or $tip[1] -notmatch '^Grille : [\d  ]+ ms$') {
            $problems.Add("the search time's tooltip says: $($tip -join ' // ')")
        }
        if ($ScreenshotDirectory) { Save-Screenshot 'groupes' }
    }

    Invoke-Check 'Groupes: Exporter saves the groups shown as CSV, and Colonnes offers the hidden ones' {
        param($problems)
        Remove-Item $exportFile -ErrorAction SilentlyContinue
        Invoke-Element (Find-Control 'group_export')
        for ($i = 0; $i -lt 20 -and -not (Test-Path $exportFile); $i++) { Start-Sleep -Milliseconds 150 }
        $rows = @(Import-Csv -LiteralPath $exportFile -Delimiter (Get-Culture).TextInfo.ListSeparator -Encoding utf8)
        $accueil = @($rows | Where-Object Nom -eq 'GG-Accueil')[0]
        if ($rows.Count -ne 7 -or $accueil.'Géré par' -ne 'Nathalie Lévy' -or $accueil.'Nom distinctif' -ne 'CN=GG-Accueil,OU=Groupes,DC=demo,DC=local') {
            $problems.Add("$($rows.Count) lines, GG-Accueil's: $($accueil | ConvertTo-Json -Compress)")
        }
        Invoke-Element (Find-Control 'group_columns')
        $items = @()
        for ($i = 0; $i -lt 20 -and -not $items.Count; $i++) { Start-Sleep -Milliseconds 150; $items = @(Get-OpenMenuItem) }
        $names = ($items | ForEach-Object { $_.Current.Name }) -join ', '
        Close-Menu
        if ($names -ne 'Nom pré-Windows 2000, Type, Étendue, Description, Courriel, Géré par, Domaine, Emplacement, Réinitialiser les colonnes') { $problems.Add("menu items: $names") }
    }

    Invoke-Check "Groupes: the search box's tooltip follows the search type" {
        param($problems)
        $tips = [ordered]@{
            'Description contient' = 'Une partie de la description (Ctrl+F)'
            'Sans membres' = 'Facultatif : une partie du nom du groupe (Ctrl+F)'
            'Liste de noms' = 'Noms entiers, séparés par des virgules (Ctrl+F)'
            'Nom contient' = 'Une partie du nom du groupe (Ctrl+F)'
        }
        foreach ($type in $tips.Keys) {
            Select-ComboItem 'group_search_type' $type
            $tip = (Find-Control 'group_query').Current.HelpText
            if ($tip -ne $tips[$type]) { $problems.Add("$type's tooltip: '$tip'") }
        }
    }

    Invoke-Check 'Groupes: Sans membres without text lists the empty groups of the domain, not the primary groups' {
        param($problems)
        # Ordinateurs du domaine, Utilisateurs du domaine and Labo-Principal (ORD-08's) list no member, and aren't empty.
        $rows = @(Invoke-GroupSearch 'demo.local' 'Sans membres' '')
        $names = ($rows | ForEach-Object { ($_ -split ' \| ')[0] }) -join ', '
        if ($names -ne "Administrateurs de l'entreprise, Admins du domaine, GG-Projet-2019") { $problems.Add("groups: $names") }
    }

    Invoke-Check 'Groupes: Propriétés of a group lists its members (a limited search, and one by name), the groups it is in, and who manages it' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $details = Open-GroupDetail 'Nom contient' 'accueil' 'GG-Accueil'
        $members = (Get-DetailList $details 'group_member') -join ', '
        if ($members -ne 'Julie Bertrand | Utilisateur | Directe, Léa Perrin | Utilisateur | Directe') { $problems.Add("members: $members") }
        # Never the whole group: a search of its members (memberOf), then of those whose primary group it is, 201 at most.
        $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADObject' | ForEach-Object { "$($_.LDAPFilter) $($_.ResultSetSize)" }) -join ' | '
        if ($searches -ne '(&(memberOf=CN=GG-Accueil,OU=Groupes,DC=demo,DC=local)) 201 | (&(primaryGroupID=1110)) 199') { $problems.Add("member searches: $searches") }
        $queriesBefore = @(Get-LoggedQuery).Count
        (Get-DialogPart $details 'group_member_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('jul')
        Start-Sleep -Milliseconds 1000
        $members = (Get-DetailList $details 'group_member') -join ', '
        $status = (Get-DialogPart $details 'group_member_status').Current.Name
        if ($members -ne 'Julie Bertrand | Utilisateur | Directe' -or $status -ne '1 membre dont le nom commence par « jul ».') { $problems.Add("searching « jul »: $members ($status)") }
        $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADObject' | ForEach-Object LDAPFilter)
        if ($searches[0] -ne '(&(memberOf=CN=GG-Accueil,OU=Groupes,DC=demo,DC=local)(|(name=jul*)(sAMAccountName=jul*)(displayName=jul*)(givenName=jul*)(sn=jul*)))') { $problems.Add("then the searches: $($searches -join ' | ')") }
        $parents = (Get-DetailList $details 'group_parent') -join ', '
        if ($parents -ne 'DL-Partage-Accueil | Sécurité') { $problems.Add("member of: $parents") }
        $manager = (Get-DialogPart $details 'group_detail_managed_by').Current.Name
        if ($manager -ne 'Nathalie Lévy') { $problems.Add("Géré par says '$manager'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'groupes-proprietes' $details }
        Close-UserDetail $details

        # Utilisateurs du domaine: AD lists no member, Get-ADGroupMember gives those whose primary group it is, without a box.
        $details = Open-GroupDetail 'Nom contient' 'utilisateurs' 'Utilisateurs du domaine'
        $members = @(Get-DetailList $details 'group_member')
        if ($members.Count -ne 9 -or $members -notcontains 'Julie Bertrand | Utilisateur | Principale') { $problems.Add("its members: $($members -join ', ')") }
        $picks = @($details.FindAll($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::CheckBox)))
        if ($picks.Count) { $problems.Add("$($picks.Count) of its members can be ticked") }
        Close-UserDetail $details
    }

    Invoke-Check "Groupes: a group's Propriétés has Tout réduire and Tout développer too, in reach however far the cards are scrolled" {
        param($problems)
        $details = Open-GroupDetail 'Nom contient' 'accueil' 'GG-Accueil'
        Test-DetailFoldBarInView $details 'group_detail' $problems
        Invoke-Element (Get-DialogPart $details 'group_detail_collapse_all')
        Start-Sleep -Milliseconds 300
        $folded = @((Read-SavedSetting 'apparence.json').FoldedSections | Sort-Object) -join ', '
        if ($folded -ne 'groupe, membrede, membres') { $problems.Add("after Tout réduire, FoldedSections: $folded") }
        if (Get-DialogPart $details 'group_detail_managed_by') { $problems.Add('after Tout réduire, Groupe still shows its values') }
        Invoke-Element (Get-DialogPart $details 'group_detail_expand_all')
        Start-Sleep -Milliseconds 300
        $folded = @((Read-SavedSetting 'apparence.json').FoldedSections) -join ', '
        if ($folded) { $problems.Add("after Tout développer, FoldedSections: $folded") }
        if (-not (Get-DialogPart $details 'group_detail_managed_by')) { $problems.Add("after Tout développer, Groupe doesn't show its values") }
        Close-UserDetail $details
    }

    Invoke-Check 'Groupes: a group in Membre de opens in its own window, one already open comes to the front, the window it was opened from reads itself again when it closes, and a user among the members opens too' {
        param($problems)
        $details = Open-GroupDetail 'Nom contient' 'accueil' 'GG-Accueil'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'group_parent_open_0')
        $parent = Wait-Dialog 'Propriétés de DL-Partage-Accueil'
        Start-Sleep -Milliseconds 400
        $members = (Get-DetailList $parent 'group_member') -join ', '
        if ($members -ne 'GG-Accueil | Groupe | Directe, Nadia Moreau | Utilisateur | Directe') { $problems.Add("DL-Partage-Accueil's members: $members") }
        if (-not (Test-WindowEnabled)) { $problems.Add('the main window is disabled while Propriétés are open') }
        # GG-Accueil is open already: its window comes to the front, no second one.
        Invoke-Element (Get-DialogPart $parent 'group_member_open_0')
        Start-Sleep -Milliseconds 600
        $count = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Propriétés de GG-Accueil' }).Count
        if ($count -ne 1) { $problems.Add("GG-Accueil opened again: $count windows") }
        Close-OwnedWindow $parent
        # Whose members were read, and where, in order: the window opening, then the one it was opened from once it
        # closed. Each in its own domain, on its PDC, where its changes go (#256; a domain local group's members of other
        # domains come from its member list).
        $read = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -eq 'Get-ADObject' -and $_.LDAPFilter -match '^\(&\(memberOf=CN=([^,]+),' } |
            ForEach-Object { "$($Matches[1]) on $($_.Server)" }) -join ', '
        if ($read -ne 'DL-Partage-Accueil on dc1.demo.local, GG-Accueil on dc1.demo.local') { $problems.Add("members read for: $read") }
        if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -eq 'Get-ADGroup' -and $_.Properties -match 'tokenGroups' }).Count) { $problems.Add("a group's tokenGroups was read") }

        # A user among the members opens in the user's Propriétés, though the Utilisateurs page was never shown.
        Invoke-Element (Get-DialogPart $details 'group_member_open_0')
        $user = Wait-Dialog 'Propriétés de Julie Bertrand'
        $login = Get-UserDetailText $user 'login'
        if ($login -ne 'jbertrand') { $problems.Add("Julie's window says her login is '$login'") }
        Close-OwnedWindow $user
        Close-UserDetail $details

        # The same from a user's Groupes card.
        Show-UserPage
        $details = Open-UserDetail 'Nom, identifiant ou courriel' 'jbertrand' 'Julie Bertrand'
        Invoke-Element (Get-DialogPart $details 'user_group_open_0')
        $group = Wait-Dialog 'Propriétés de GG-Accueil'
        Start-Sleep -Milliseconds 400
        if ((Get-DetailList $group 'group_member') -notcontains 'Julie Bertrand | Utilisateur | Directe') { $problems.Add("from Julie, GG-Accueil's members: $((Get-DetailList $group 'group_member') -join ', ')") }
        Close-OwnedWindow $group
        Close-UserDetail $details
        Show-GroupPage
    }

    Invoke-Check 'Groupes: at most 10 Propriétés windows at once; the 11th says so, and Tout fermer closes them all' {
        param($problems)
        $null = Invoke-GroupSearch 'Tous les domaines' 'Nom contient' 'e'
        $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
        $rows = @((Find-Control 'group_grid').FindAll($Descendants, $isRow))
        if ($rows.Count -lt 11) { throw "only $($rows.Count) groups to open" }
        for ($i = 0; $i -lt 10; $i++) {
            $rows[$i].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
            Start-Sleep -Milliseconds 150
            Invoke-Element (Find-Control 'group_details')
            Start-Sleep -Milliseconds 300
        }
        $open = @(Get-AppWindow | Where-Object { $_.Current.Name -like 'Propriétés de *' }).Count
        if ($open -ne 10) { $problems.Add("$open windows open after 10 Propriétés…") }
        $rows[10].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 150
        Invoke-Element (Find-Control 'group_details')
        $dialog = Wait-Dialog 'Propriétés'
        if ((Get-DialogText $dialog) -notlike "10 fenêtres Propriétés sont ouvertes*C'est le maximum*") { $problems.Add("the limit says '$(Get-DialogText $dialog)'") }
        Invoke-Element (Get-DialogPart $dialog 'dialog_ok')
        for ($i = 0; $i -lt 20 -and @(Get-AppWindow | Where-Object { $_.Current.Name -like 'Propriétés*' }).Count; $i++) { Start-Sleep -Milliseconds 200 }
        $left = @(Get-AppWindow | Where-Object { $_.Current.Name -like 'Propriétés*' }).Count
        if ($left) { $problems.Add("after Tout fermer, $left windows are left") }
    }

    Invoke-Check 'Groupes: across domains, a universal group lists its members through the global catalog, a domain local one its members of another domain, and Membre de the groups of other domains' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $details = Open-GroupDetail 'Nom contient' 'postes-nord' 'GU-Postes-Nord' 'nord.demo.local'
        $members = (Get-DetailList $details 'group_member') -join ', '
        if ($members -ne 'GG-Postes-Accueil | Groupe | Directe, ORD-01 | Ordinateur | Directe, ORD-04 | Ordinateur | Directe') { $problems.Add("GU-Postes-Nord's members: $members") }
        $searches = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object { $_.Command -eq 'Get-ADObject' -and $_.LDAPFilter -like '*memberOf=*' } | ForEach-Object Server) -join ', '
        if ($searches -ne 'dc1.demo.local:3268') { $problems.Add("its members searched on: $searches") }
        Close-UserDetail $details

        # Nadia Moreau, of nord.demo.local, is in DL-Partage-Accueil, of demo.local: its members list her, and her
        # Groupes list it, though nord's DC doesn't know it.
        $details = Open-GroupDetail 'Nom contient' 'partage' 'DL-Partage-Accueil'
        $nadia = @(Get-DetailList $details 'group_member') -match '^Nadia Moreau'
        if ($nadia -ne 'Nadia Moreau | Utilisateur | Directe') { $problems.Add("DL-Partage-Accueil's members: $((Get-DetailList $details 'group_member') -join ', ')") }
        Invoke-Element (Get-DialogPart $details 'group_member_open_1')
        $user = Wait-Dialog 'Propriétés de Nadia Moreau'
        Start-Sleep -Milliseconds 400
        $groups = (Get-UserDetailGroup $user) -join ', '
        if ($groups -notlike '*DL-Partage-Accueil | Directe*') { $problems.Add("Nadia's groups: $groups") }
        Close-OwnedWindow $user
        Close-UserDetail $details
    }

    Invoke-Check 'Groupes: a user and a computer added at once, then both removed after one confirmation' {
        param($problems)
        $details = Open-GroupDetail 'Nom contient' 'projet' 'GG-Projet-2019'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Get-DialogPart $details 'group_member_add')
        $add = Wait-OwnedDialog $details 'Ajouter des membres'
        # What's ticked stays while another name is searched, and Ajouter with it.
        (Get-DialogPart $add 'member_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('lefeb')
        Start-Sleep -Milliseconds 900
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is enabled before a member is ticked') }
        Select-ListChoice $add 'member_results' 'Luc Lefebvre'
        (Get-DialogPart $add 'member_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('ORD-03')
        Start-Sleep -Milliseconds 900
        if (-not (Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is disabled after another search, Luc Lefebvre still ticked') }
        Select-ListChoice $add 'member_results' 'ORD-03'
        Close-OwnedDialog $add 'dialog_ok'
        # GG-Projet-2019 still has the adminCount it had as an administration group: the card asks again, red, as
        # Ajouter à un groupe does (#233), naming the two accounts.
        $confirm = Wait-OwnedDialog $details 'Ajouter à un groupe'
        if ((Get-DialogText $confirm) -notlike 'Ajouter 2 comptes à GG-Projet-2019 ?*GG-Projet-2019 est un groupe privilégié*') { $problems.Add("the confirmation says '$(Get-DialogText $confirm)'") }
        Close-OwnedDialog $confirm 'dialog_ok'
        Wait-LoggedCommand 'Add-ADGroupMember' $queriesBefore 2
        $added = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Add-ADGroupMember' | ForEach-Object { "$($_.Identity) <- $($_.Members)" }) -join ' | '
        $group = 'CN=GG-Projet-2019,OU=Groupes,DC=demo,DC=local'
        if ($added -ne "$group <- CN=Luc Lefebvre,OU=Utilisateurs,DC=demo,DC=local | $group <- CN=ORD-03,OU=Postes,DC=demo,DC=local") { $problems.Add("additions: $added") }
        $members = (Get-DetailList $details 'group_member') -join ', '
        if ($members -ne 'ORD-03 | Ordinateur | Directe, Luc Lefebvre | Utilisateur | Directe') { $problems.Add("then the members: $members") }

        foreach ($name in 'ORD-03', 'Luc Lefebvre') {
            $details.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, "Choisir $name")).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        }
        Start-Sleep -Milliseconds 200
        $label = (Get-DialogPart $details 'group_member_remove_label').Current.Name
        if ($label -ne 'Retirer (2)…') { $problems.Add("the button says '$label'") }
        Invoke-Element (Get-DialogPart $details 'group_member_remove')
        $confirm = Wait-OwnedDialog $details 'Retirer du groupe'
        if ((Get-DialogText $confirm) -notlike 'Retirer 2 membres de GG-Projet-2019 ?*ORD-03*Luc Lefebvre*') { $problems.Add("the confirmation says '$(Get-DialogText $confirm)'") }
        Close-OwnedDialog $confirm 'dialog_ok'
        Wait-LoggedCommand 'Remove-ADGroupMember' $queriesBefore 2
        $removed = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Remove-ADGroupMember').Count
        if ($removed -ne 2) { $problems.Add("removals sent: $removed") }
        if (@(Get-DetailList $details 'group_member').Count) { $problems.Add("then the members: $((Get-DetailList $details 'group_member') -join ', ')") }
        Close-UserDetail $details
    }

    Invoke-Check 'Groupes: Ajouter des membres… is for one group at a time, in the toolbar and the right-click menu' {
        param($problems)
        $null = Invoke-GroupSearch 'demo.local' 'Nom contient' 'gg'
        Select-GroupRow 'GG-Projet-2019'
        $button = Find-Control 'group_add_members'
        if (-not $button.Current.IsEnabled) { $problems.Add('Ajouter des membres… is disabled for one group') }
        if ($button.Current.HelpText -notlike '*un groupe à la fois*') { $problems.Add("its tooltip says '$($button.Current.HelpText)'") }
        $menuEnabled = (Open-GroupMenuItem 'Ajouter des membres…').Current.IsEnabled
        Close-Menu
        if (-not $menuEnabled) { $problems.Add("the menu's Ajouter des membres… is disabled for one group") }
        Select-GroupRow 'GG-Accueil' -Add
        if ($button.Current.IsEnabled) { $problems.Add('Ajouter des membres… is enabled for two groups') }
        $menuEnabled = (Open-GroupMenuItem 'Ajouter des membres…').Current.IsEnabled
        Close-Menu
        if ($menuEnabled) { $problems.Add("the menu's Ajouter des membres… is enabled for two groups") }
        if ((Find-Control 'group_details').Current.IsEnabled) { $problems.Add('Propriétés… is enabled for two groups') }
    }

    Invoke-Check 'Groupes: Ajouter des membres… adds without opening Propriétés, which an open one reads again, and leaves out the members it lists' {
        param($problems)
        $details = Open-GroupDetail 'Nom contient' 'ventes' 'GG-Ventes'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'group_add_members')
        $add = Wait-Dialog 'Ajouter des membres'
        $text = Get-DialogText $add
        if ($text -notlike 'Ajouter des membres à GG-Ventes*Cochez un ou plusieurs comptes de demo.local.*') { $problems.Add("the picker says '$text'") }
        (Get-DialogPart $add 'member_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('lefeb')
        Start-Sleep -Milliseconds 900
        if ((Get-DialogPart $add 'dialog_ok').Current.IsEnabled) { $problems.Add('Ajouter is enabled before a member is ticked') }
        Select-ListChoice $add 'member_results' 'Luc Lefebvre'
        Close-Dialog $add 'dialog_ok'
        Wait-LoggedCommand 'Add-ADGroupMember' $queriesBefore
        $added = (Get-GroupChange 'Add-ADGroupMember' $queriesBefore) -join ' | '
        if ($added -ne 'GG-Ventes: Luc Lefebvre') { $problems.Add("additions: $added") }
        $notice = Wait-ActionNotice 'Ajouter des membres : ✔ Luc Lefebvre ajouté à GG-Ventes.'
        if ($notice -ne 'Ajouter des membres : ✔ Luc Lefebvre ajouté à GG-Ventes.') { $problems.Add("after adding, the notice says '$notice'") }
        # Its Propriétés, open meanwhile, reads itself again.
        $members = ''
        for ($i = 0; $i -lt 20 -and $members -notlike '*Luc Lefebvre | Utilisateur | Directe*'; $i++) { Start-Sleep -Milliseconds 250; $members = (Get-DetailList $details 'group_member') -join ', ' }
        if ($members -notlike '*Luc Lefebvre | Utilisateur | Directe*Marc Durand*' -and $members -notlike '*Marc Durand*Luc Lefebvre | Utilisateur | Directe*') { $problems.Add("the open Propriétés lists: $members") }
        # Marc Durand is listed there, so the picker doesn't offer him.
        Invoke-Element (Find-Control 'group_add_members')
        $add = Wait-Dialog 'Ajouter des membres'
        (Get-DialogPart $add 'member_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('durand')
        Start-Sleep -Milliseconds 900
        $hint = (Get-DialogPart $add 'member_hint').Current.Name
        if ($hint -ne 'Aucun compte dont le nom commence par « durand ».') { $problems.Add("searching « durand » again: '$hint'") }
        Close-Dialog $add 'dialog_cancel'
        # The right-click menu opens the same picker.
        Invoke-Element (Open-GroupMenuItem 'Ajouter des membres…')
        $add = Wait-Dialog 'Ajouter des membres'
        Close-Dialog $add 'dialog_cancel'

        $details.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Choisir Luc Lefebvre')).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 200
        Invoke-Element (Get-DialogPart $details 'group_member_remove')
        $confirm = Wait-OwnedDialog $details 'Retirer du groupe'
        Close-OwnedDialog $confirm 'dialog_ok'
        Wait-LoggedCommand 'Remove-ADGroupMember' $queriesBefore
        $members = (Get-DetailList $details 'group_member') -join ', '
        if ($members -like '*Luc Lefebvre*') { $problems.Add("after removing him, the members: $members") }
        Close-UserDetail $details
    }

    Invoke-Check 'Groupes: Ajouter des membres… to a privileged group asks again, red, Annuler the default; AD refuses it' {
        param($problems)
        $null = Invoke-GroupSearch 'demo.local' 'Nom contient' 'Admins du domaine'
        Select-GroupRow 'Admins du domaine'
        foreach ($answer in 'enter', 'ok') {
            Invoke-Element (Find-Control 'group_add_members')
            $add = Wait-Dialog 'Ajouter des membres'
            (Get-DialogPart $add 'member_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('lefeb')
            Start-Sleep -Milliseconds 900
            Select-ListChoice $add 'member_results' 'Luc Lefebvre'
            Close-Dialog $add 'dialog_ok'
            $confirm = Wait-Dialog 'Ajouter à un groupe'
            $text = Get-DialogText $confirm
            if ($text -notlike 'Ajouter Luc Lefebvre à Admins du domaine ?*Admins du domaine est un groupe privilégié*') { $problems.Add("the privileged group's confirmation says '$text'") }
            $queriesBefore = @(Get-LoggedQuery).Count
            if ($answer -eq 'enter') {
                Send-Key 0x0D $confirm
                Start-Sleep -Milliseconds 600
                if (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Add-ADGroupMember').Count) { $problems.Add('Enter added him to Admins du domaine') }
            }
            else { Close-Dialog $confirm 'dialog_ok' }
        }
        $report = Wait-Dialog 'Ajouter des membres'
        $text = (Get-DialogPart $report 'dialog_message').Current.Name
        if ($text -ne '✖ Luc Lefebvre : non ajouté à Admins du domaine (Droits insuffisants pour cette opération)') { $problems.Add("the refusal says '$text'") }
        Close-Dialog $report 'dialog_cancel'
    }

    Invoke-Check 'Groupes: the action row still fits at Grande and Très grande text' {
        param($problems)
        Test-ToolbarFit 'group' 'group_copy' $problems
    }

    Invoke-Check 'Groupes: Liste de noms finds whole names, each once, and lists those found nowhere' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        $rows = @(Invoke-GroupSearch 'demo.local' 'Liste de noms' 'gg-accueil; Admins du domaine; DEMO\GG-VPN; GG-Accueil; GG-Absent')
        $names = ($rows | ForEach-Object { ($_ -split ' \| ')[0] }) -join ', '
        if ($names -ne 'Admins du domaine, GG-Accueil, GG-VPN') { $problems.Add("rows: $($rows -join ' // ')") }
        $filter = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADGroup' | ForEach-Object LDAPFilter) -join ' | '
        if ($filter -ne '(&(objectCategory=group)(|(name=gg-accueil)(sAMAccountName=gg-accueil)(name=Admins du domaine)(sAMAccountName=Admins du domaine)(name=GG-VPN)(sAMAccountName=GG-VPN)(name=GG-Absent)(sAMAccountName=GG-Absent)))') {
            $problems.Add("searches: $filter")
        }
        $notFound = Find-ShownControl 'group_not_found_text'
        $said = if ($notFound) { $notFound.Current.Name } else { '(not shown)' }
        if ($said -ne '1 introuvable : GG-Absent') { $problems.Add("the names not found say '$said'") }
        $null = Invoke-GroupSearch 'demo.local' 'Nom contient' 'vpn'
        if (Find-ShownControl 'group_not_found') { $problems.Add('after another search, the names not found still show') }
    }
}

function Test-GroupListUnanswered {
    # Run with nord.demo.local down (#236): a list searched in every domain can't call Personnel-Nord, of nord, truly not
    # found, so the banner says which domain didn't answer. The next search, in demo.local alone, no longer says it.
    Invoke-Check 'Groupes: Liste de noms with a domain down says the names not found may be in it' {
        param($problems)
        Show-GroupPage
        $rows = @(Invoke-GroupSearch 'Tous les domaines' 'Liste de noms' 'GG-VPN; Personnel-Nord')
        $names = ($rows | ForEach-Object { ($_ -split ' \| ')[0] }) -join ', '
        if ($names -ne 'GG-VPN') { $problems.Add("rows: $($rows -join ' // ')") }
        $count = (Find-Control 'group_count').Current.Name
        if ($count -notlike '*(erreur : nord.demo.local)') { $problems.Add("the count says '$count'") }
        $notFound = Find-ShownControl 'group_not_found_text'
        $said = if ($notFound) { $notFound.Current.Name } else { '(not shown)' }
        if ($said -ne '1 introuvable : Personnel-Nord · sans réponse de nord.demo.local') { $problems.Add("the names not found say '$said'") }

        $null = Invoke-GroupSearch 'demo.local' 'Liste de noms' 'Personnel-Nord'
        $notFound = Find-ShownControl 'group_not_found_text'
        $said = if ($notFound) { $notFound.Current.Name } else { '(not shown)' }
        if ($said -ne '1 introuvable : Personnel-Nord') { $problems.Add("in demo.local alone, the names not found say '$said'") }
    }
}

function Read-SavedSetting([string]$File) {
    try { Get-Content (Join-Path $env:APPDATA "Repere\$File") -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json } catch { $null }
}

function Send-CtrlKey([int]$VirtualKey) {
    # Ctrl held for real, since WPF reads it from the keyboard and a posted key can't press it. Only Ctrl goes to the
    # system, to the window in front (Repère's, once it has the focus): the key itself is posted to Repère's window.
    $window.SetFocus()
    [RepereWindows]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    try { Send-Key $VirtualKey }
    finally { [RepereWindows]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero) }
}

function Open-NextName([ValidateSet('button', 'key', 'menu')][string]$Via = 'button', [switch]$KeepSelection) {
    # Prochain nom… as it's opened: the action bar's button, Ctrl+N, or the results' right-click menu. The button and the
    # key open on the series of the computer selected, or on the last format used with none: so the selection is cleared
    # first, unless -KeepSelection (the menu needs a row selected, which it keeps).
    if ($Via -ne 'menu' -and -not $KeepSelection) { Clear-ResultSelection }
    switch ($Via) {
        'button' { Invoke-Element (Find-Control 'act_next_name') }
        'key' { Send-CtrlKey 0x4E }
        'menu' { Invoke-ResultMenuItem 'Prochain nom de cette série…' }
    }
    Wait-Dialog 'Prochain nom'
}

function Set-DialogText($Dialog, [string]$AutomationId, [string]$Text) {
    (Get-DialogPart $Dialog $AutomationId).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
}

function Get-DialogPartName($Dialog, [string]$AutomationId) {
    # A text block's text; '' when it isn't shown.
    $part = Get-DialogPart $Dialog $AutomationId
    if ($part) { $part.Current.Name } else { '' }
}

function Wait-NextName($Dialog, [string]$Expected) {
    # The name shown, once it's $Expected or after 8 s: a read runs after the last key, in the background.
    $shown = ''
    for ($i = 0; $i -lt 32; $i++) {
        $shown = Get-DialogPartName $Dialog 'next_name'
        if ($shown -ceq $Expected) { break }
        Start-Sleep -Milliseconds 250
    }
    $shown
}

function Test-NextName {
    # Prochain nom…, from the fake AD without SCCM: a series offered, the blocks clicked, a name that doesn't vary, the
    # options, Copier and the recent format.
    Invoke-Check 'Prochain nom: AD''s series offered, then the next names and how many are taken' {
        param($problems)
        $dialog = Open-NextName
        # The first time, the Ordinateurs page's domain alone, not all of them (#221); nord.demo.local ticked by hand,
        # which is saved for the checks after this one.
        $ticked = @(0, 1 | ForEach-Object { (Get-DialogPart $dialog "next_domain_$_").GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState })
        if ("$ticked" -ne 'On Off') { $problems.Add("demo.local and nord.demo.local open as '$ticked', not 'On Off'") }
        (Get-DialogPart $dialog 'next_domain_1').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 300
        if ((@((Read-SavedSetting 'prochainnom.json').Domains) -join ',') -ne 'demo.local,nord.demo.local') { $problems.Add("ticked, prochainnom.json holds the domains '$((Read-SavedSetting 'prochainnom.json').Domains)'") }
        Set-DialogText $dialog 'next_format' 'ORD'
        for ($i = 0; $i -lt 32 -and -not (Get-DialogPart $dialog 'next_series_0'); $i++) { Start-Sleep -Milliseconds 250 }
        $series = Get-DialogPart $dialog 'next_series_0'
        if (-not $series) { throw "no series offered for ORD" }
        # 12 names, as « déjà pris » says below; ORD-01 is in both domains, which the tooltip says.
        if ($series.Current.Name -ne 'ORD-##  ·  12') { $problems.Add("the series offered reads '$($series.Current.Name)'") }
        if ($series.Current.HelpText -notlike '13 ordinateurs*') { $problems.Add("the series' tooltip reads '$($series.Current.HelpText)'") }
        Invoke-Element $series
        $name = Wait-NextName $dialog 'ORD-13'
        if ($name -ne 'ORD-13') { $problems.Add("next name '$name', expected ORD-13") }
        $more = Get-DialogPartName $dialog 'next_more'
        if ($more -ne 'ORD-14, ORD-15') { $problems.Add("then '$more'") }
        $count = Get-DialogPartName $dialog 'next_count_text'
        if ($count -ne '99 noms possibles, 12 déjà pris') { $problems.Add("the count says '$count'") }
        if ((Get-DialogPart $dialog 'next_sccm_check').Current.IsEnabled) { $problems.Add('Vérifier dans SCCM is enabled without a site') }
        if (-not (Get-DialogPart $dialog 'next_sccm_setup')) { $problems.Add('no way to Paramètres without a site') }
        if ($ScreenshotDirectory) { Save-Screenshot 'prochain-nom' $dialog }
        Close-Dialog $dialog 'dialog_cancel'
        $type = Get-ComboText 'search_type'
        if ($type -ne 'Description contient') { $problems.Add("closed, the search type is '$type'") }
        Invoke-PrefixSearch 'ORD-0'
        if ((Get-ResultName) -notcontains 'ORD-01') { $problems.Add('the search doesn''t work after Prochain nom…') }
    }

    Invoke-Check 'Prochain nom: the search types no longer list it, and ↓ on the last one opens nothing' {
        param($problems)
        $types = @(Get-ComboItemName 'search_type')
        if ($types -contains 'Prochain nom…') { $problems.Add('the search types still list Prochain nom…') }
        if ($types[-1] -ne 'ID de clé BitLocker') { $problems.Add("the search types end with '$($types[-1])'") }
        Select-SearchType 'ID de clé BitLocker'
        (Find-Control 'search_type').SetFocus()
        # ↑ first: it shows the keys reach the list.
        Send-Key 0x26
        if ((Get-ComboText 'search_type') -ne 'Adresse IP') { $problems.Add("after ↑, the search type is '$(Get-ComboText 'search_type')'") }
        Send-Key 0x28
        Send-Key 0x28
        Start-Sleep -Milliseconds 600
        $type = Get-ComboText 'search_type'
        if ($type -ne 'ID de clé BitLocker') { $problems.Add("after ↓, the search type is '$type'") }
        if (-not (Test-WindowEnabled)) { $problems.Add('a window opened'); Close-OpenDialog }
        Select-SearchType 'Description contient'
    }

    Invoke-Check 'Prochain nom: AAA varies, LABO doesn''t, and a click switches a block' {
        param($problems)
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'ORD-AAA-##'
        $name = Wait-NextName $dialog 'ORD-AAA-01'
        if ($name -ne 'ORD-AAA-01') { $problems.Add("ORD-AAA-## gives '$name'") }
        if ((Get-DialogPartName $dialog 'next_block_text_2') -ne '@@@') { $problems.Add("the AAA block reads '$(Get-DialogPartName $dialog 'next_block_text_2')'") }
        Invoke-Element (Get-DialogPart $dialog 'next_block_2')
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPartName $dialog 'next_block_text_2') -ne 'AAA') { $problems.Add("clicked, the AAA block reads '$(Get-DialogPartName $dialog 'next_block_text_2')'") }
        Set-DialogText $dialog 'next_format' 'LABO-###'
        $name = Wait-NextName $dialog 'LABO-001'
        if ($name -ne 'LABO-001') { $problems.Add("LABO-### gives '$name'") }
        if ((Get-DialogPartName $dialog 'next_block_text_0') -ne 'LABO') { $problems.Add("the LABO block reads '$(Get-DialogPartName $dialog 'next_block_text_0')'") }
        Invoke-Element (Get-DialogPart $dialog 'next_block_0')
        Start-Sleep -Milliseconds 300
        $problem = Get-DialogPartName $dialog 'next_problem'
        if ($problem -ne 'Un modèle commence par un texte fixe, ex. ORD-####.') { $problems.Add("LABO clicked varying says '$problem'") }
        # The field follows the blocks, and isn't read again: LABO stays a block that can be fixed back.
        $typed = (Get-DialogPart $dialog 'next_format').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($typed -ne '@@@@-###') { $problems.Add("LABO clicked varying, the field reads '$typed'") }
        Invoke-Element (Get-DialogPart $dialog 'next_block_0')
        $name = Wait-NextName $dialog 'LABO-001'
        if ($name -ne 'LABO-001') { $problems.Add("LABO clicked fixed again gives '$name'") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Prochain nom: a name that doesn''t vary is checked as it is' {
        param($problems)
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'SERVEUR'
        $name = Wait-NextName $dialog 'SERVEUR'
        if ($name -ne 'SERVEUR') { $problems.Add("SERVEUR gives '$name'") }
        if ((Get-DialogPartName $dialog 'next_result_label') -ne 'Ce nom exact') { $problems.Add("labelled '$(Get-DialogPartName $dialog 'next_result_label')'") }
        if ((Get-DialogPartName $dialog 'next_count_text') -ne 'Libre dans l''AD.') { $problems.Add("SERVEUR: '$(Get-DialogPartName $dialog 'next_count_text')'") }
        Set-DialogText $dialog 'next_format' 'ORD-01'
        $null = Wait-NextName $dialog 'ORD-13'
        Invoke-Element (Get-DialogPart $dialog 'next_block_2')
        $name = Wait-NextName $dialog 'ORD-01'
        if ($name -ne 'ORD-01') { $problems.Add("ORD-01 fixed gives '$name'") }
        if ((Get-DialogPartName $dialog 'next_count_text') -ne 'Déjà pris dans l''AD.') { $problems.Add("ORD-01: '$(Get-DialogPartName $dialog 'next_count_text')'") }
        if ((Get-DialogPart $dialog 'next_copy').Current.IsEnabled) { $problems.Add('Copier offers a name that''s taken') }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Prochain nom: an unusable format says why, and offers nothing to copy' {
        param($problems)
        $dialog = Open-NextName
        foreach ($case in @(@('ORD 01', 'Lettres, chiffres, - et _ seulement.'), @('12345', 'Un nom ne peut pas être fait que de chiffres.'), @('ORD-####-ABCDEFGH', 'Un nom a 15 caractères au plus.'))) {
            Set-DialogText $dialog 'next_format' $case[0]
            Start-Sleep -Milliseconds 300
            $problem = Get-DialogPartName $dialog 'next_problem'
            if ($problem -ne $case[1]) { $problems.Add("'$($case[0])' says '$problem'") }
            if ((Get-DialogPart $dialog 'next_copy').Current.IsEnabled) { $problems.Add("'$($case[0])' can be copied") }
        }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Prochain nom: Options change the names, and are kept with the recent format' {
        param($problems)
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'ORD-##'
        $null = Wait-NextName $dialog 'ORD-13'
        (Get-DialogPart $dialog 'next_options').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 300
        Set-DialogText $dialog 'next_from' 'ORD-50'
        $name = Wait-NextName $dialog 'ORD-50'
        if ($name -ne 'ORD-50') { $problems.Add("from ORD-50 gives '$name'") }
        Set-DialogText $dialog 'next_from' 'PC-50'
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPartName $dialog 'next_problem') -notlike 'Commencer à*') { $problems.Add("a start that doesn't fit says '$(Get-DialogPartName $dialog 'next_problem')'") }
        Set-DialogText $dialog 'next_from' ''
        Set-DialogText $dialog 'next_how_many' '1'
        Set-DialogText $dialog 'next_exclude' '3'
        $name = Wait-NextName $dialog 'ORD-14'
        if ($name -ne 'ORD-14') { $problems.Add("without 3 gives '$name'") }
        if (Get-DialogPartName $dialog 'next_more') { $problems.Add("Combien 1 still shows '$(Get-DialogPartName $dialog 'next_more')'") }
        Invoke-Element (Get-DialogPart $dialog 'next_copy')
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPartName $dialog 'next_status') -ne 'ORD-14 copié.') { $problems.Add("the status says '$(Get-DialogPartName $dialog 'next_status')'") }
        if (-not (Get-DialogPart $dialog 'next_recent')) { $problems.Add('no recent format after Copier') }
        Close-Dialog $dialog 'dialog_cancel'
        $saved = Read-SavedSetting 'prochainnom.json'
        if ($saved.Count -ne 1 -or $saved.Exclude -ne '3') { $problems.Add("prochainnom.json holds: $($saved | ConvertTo-Json -Compress -Depth 2)") }
        $dialog = Open-NextName
        $name = Wait-NextName $dialog 'ORD-14'
        if ($name -ne 'ORD-14') { $problems.Add("opened again, it shows '$name'") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    # What follows leaves ORD-## the last format used (no Copier), with 3 left out, so the last format reads ORD-14 and
    # a computer of nord.demo.local, NRD-01, gives another series: NRD-03 is out, NRD-04 the first one free.
    Invoke-Check 'Prochain nom: the button is enabled without a selection and opens on the last format; Ctrl+N does the same' {
        param($problems)
        Invoke-PrefixSearch 'ORD-0'
        Clear-ResultSelection
        $button = Find-Control 'act_next_name'
        if (-not $button.Current.IsEnabled) { $problems.Add('the button is disabled without a selection') }
        foreach ($via in 'button', 'key') {
            $dialog = Open-NextName $via
            $name = Wait-NextName $dialog 'ORD-14'
            $typed = (Get-DialogPart $dialog 'next_format').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            if ($name -ne 'ORD-14' -or $typed -ne 'ORD-##') { $problems.Add("$via, with no selection: the name is '$name' on '$typed', not ORD-14 on ORD-##") }
            Close-Dialog $dialog 'dialog_cancel'
        }
        # Several selected: no series to take, the last format again.
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-02'
        if (-not $button.Current.IsEnabled) { $problems.Add('the button is disabled with two computers selected') }
        $dialog = Open-NextName -KeepSelection
        $name = Wait-NextName $dialog 'ORD-14'
        if ($name -ne 'ORD-14') { $problems.Add("with two selected, the name is '$name', not ORD-14") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Prochain nom: the right-click item, the button and Ctrl+N open on the selected computer''s series' {
        param($problems)
        Select-Domain 'nord.demo.local'
        Invoke-PrefixSearch 'NRD'
        Select-ResultRow 'NRD-01'
        foreach ($via in 'menu', 'button', 'key') {
            $dialog = Open-NextName $via -KeepSelection
            $name = Wait-NextName $dialog 'NRD-04'
            $typed = (Get-DialogPart $dialog 'next_format').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            $series = (0..2 | ForEach-Object { Get-DialogPartName $dialog "next_block_text_$_" }) -join ''
            if ($name -ne 'NRD-04' -or $typed -ne 'NRD-01' -or $series -ne 'NRD-##') { $problems.Add("$via : the name is '$name' on '$typed' read as '$series', not NRD-04 on NRD-01 read as NRD-##") }
            Close-Dialog $dialog 'dialog_cancel'
        }
        # Only used names join the recent formats: this one wasn't, and the last format is still the one before.
        $recent = @((Read-SavedSetting 'prochainnom.json').Recent)
        if ($recent.Count -ne 1) { $problems.Add("prochainnom.json holds $($recent.Count) recent formats, not 1") }
        Clear-ResultSelection
        $dialog = Open-NextName
        $name = Wait-NextName $dialog 'ORD-14'
        if ($name -ne 'ORD-14') { $problems.Add("then, with no selection, it opens on '$name', not ORD-14") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    Invoke-Check 'Prochain nom: the right-click item is enabled for one computer only' {
        param($problems)
        $enabled = {
            $null = Open-ResultMenu
            $item = @(Open-MenuGroup 'Active Directory') | Where-Object { $_.Current.Name -eq 'Prochain nom de cette série…' } | Select-Object -First 1
            $state = if ($item) { $item.Current.IsEnabled } else { '(not listed)' }
            Close-MenuGroup 'Active Directory'
            Close-Menu
            $state
        }
        Select-ResultRow 'NRD-01'
        if ((& $enabled) -ne $true) { $problems.Add("with one computer selected, the item is $(& $enabled)") }
        Add-ResultRow 'NRD-02'
        if ((& $enabled) -ne $false) { $problems.Add("with two computers selected, the item is $(& $enabled)") }
        Select-Domain 'demo.local'
    }
}

function Set-SccmSetting([string]$Site, [string]$Server) {
    # A site in parametres.json, for the next start.
    $folder = Join-Path $env:APPDATA 'Repere'
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    @{ SccmSite = $Site; SccmServer = $Server } | ConvertTo-Json | Set-Content (Join-Path $folder 'parametres.json') -Encoding utf8
}

# A parametres.json an admin wrote by hand, with a typo: a DN with a single \ before its comma, which isn't JSON.
$script:BrokenSettings = '{ "MoveRoots": ["OU=Postes\,DC=demo,DC=local"], "SccmSite": "DEM", "Language": "en" }'

function Test-UnreadableSetting {
    # Started with $BrokenSettings as parametres.json: Repère says so in a toast, and doesn't write over it (#243).
    Invoke-Check 'Paramètres: a parametres.json that can''t be read is said in a toast at start, and left as it is' {
        param($problems)
        $expected = "Paramètres : ✖ parametres.json illisible, valeurs par défaut. Le fichier est gardé dans $(Join-Path $env:APPDATA 'Repere') pour être corrigé."
        $notice = Wait-ActionNotice $expected
        if ($notice -ne $expected) { $problems.Add("the status bar says '$notice'") }
        $file = Join-Path $env:APPDATA 'Repere\parametres.json'
        $text = (Get-Content -LiteralPath $file -Raw).Trim()
        if ($text -ne $script:BrokenSettings) { $problems.Add("parametres.json now holds: $text") }
        if (Test-Path -LiteralPath "$file.illisible") { $problems.Add('parametres.json was moved aside with nothing saved') }
    }
}

function Get-NextNameQueryCount {
    @(Get-LoggedQuery | Where-Object Command -EQ 'Get-ADComputer').Count
}

function Wait-NextNameQuery([int]$Before) {
    # Whether AD was read since $Before, within 4 s.
    for ($i = 0; $i -lt 16; $i++) {
        if ((Get-NextNameQueryCount) -gt $Before) { return $true }
        Start-Sleep -Milliseconds 250
    }
    $false
}

function Test-NextNameWindow {
    # Rechercher and the window's room, on the format Test-NextName left (ORD-##, ORD-14 first).
    Invoke-Check 'Prochain nom: Rechercher and Enter read AD again, without Tout copier' {
        param($problems)
        $dialog = Open-NextName
        $null = Wait-NextName $dialog 'ORD-14'
        if (Get-DialogPart $dialog 'next_copy_all') { $problems.Add('Tout copier is still there') }
        Start-Sleep -Milliseconds 500
        $before = Get-NextNameQueryCount
        Invoke-Element (Get-DialogPart $dialog 'next_search')
        if (-not (Wait-NextNameQuery $before)) { $problems.Add('Rechercher didn''t read AD') }
        if ((Wait-NextName $dialog 'ORD-14') -ne 'ORD-14') { $problems.Add('Rechercher lost the name') }
        Start-Sleep -Milliseconds 500
        $before = Get-NextNameQueryCount
        (Get-DialogPart $dialog 'next_format').SetFocus()
        Send-Key 0x0D $dialog
        if (-not (Wait-NextNameQuery $before)) { $problems.Add('Enter didn''t read AD') }
        Close-Dialog $dialog 'dialog_cancel'
    }
    Invoke-Check 'Prochain nom: the same height whatever it shows, on the screen with Options, no gap once maximized' {
        param($problems)
        $dialog = Open-NextName
        $height = { [int]$dialog.Current.BoundingRectangle.Height }
        $opened = & $height
        Set-DialogText $dialog 'next_format' ''
        Start-Sleep -Milliseconds 300
        if ((& $height) -ne $opened) { $problems.Add("empty, the window is $(& $height) pixels high, not $opened") }
        Set-DialogText $dialog 'next_format' 'ORD-##'
        $null = Wait-NextName $dialog 'ORD-14'
        Start-Sleep -Milliseconds 300
        if ((& $height) -ne $opened) { $problems.Add("with the names, the window is $(& $height) pixels high, not $opened") }
        $options = (Get-DialogPart $dialog 'next_options').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $options.Toggle()
        Start-Sleep -Milliseconds 800
        if ((& $height) -ne $opened) { $problems.Add("with Options, the window is $(& $height) pixels high, not $opened") }
        $screen = $AE::RootElement.Current.BoundingRectangle
        $bottom = $dialog.Current.BoundingRectangle.Bottom
        if ($bottom -gt $screen.Bottom) { $problems.Add("with Options, the window ends at $bottom on a screen of $($screen.Bottom)") }
        # Options scroll the field out of view: closed, for where the field sits.
        $options.Toggle()
        Start-Sleep -Milliseconds 500
        if ((& $height) -ne $opened) { $problems.Add("Options closed, the window is $(& $height) pixels high, not $opened") }
        $field = { (Get-DialogPart $dialog 'next_format').Current.BoundingRectangle.Top - $dialog.Current.BoundingRectangle.Top }
        $normal = & $field
        $state = $dialog.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
        $state.SetWindowVisualState('Maximized')
        Start-Sleep -Milliseconds 800
        $maximized = & $field
        # Maximized, the window's edges are past the screen: 8 pixels at 100 %, more at a larger scale.
        if ($maximized -gt $normal + 24) { $problems.Add("maximized, the field is $maximized pixels down, not $normal") }
        $state.SetWindowVisualState('Normal')
        Start-Sleep -Milliseconds 800
        if ((& $field) -ne $normal) { $problems.Add("restored, the field is $(& $field) pixels down, not $normal") }
        Close-Dialog $dialog 'dialog_cancel'
    }
    # Last: it saves an SCCM site, which changes the names (the next session starts without it).
    Invoke-Check 'Prochain nom: Configurer… opens Paramètres › SCCM, and Prochain nom comes back on its format once it''s closed' {
        param($problems)
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'LABO-###'
        $null = Wait-NextName $dialog 'LABO-001'
        Invoke-Element (Get-DialogPart $dialog 'next_sccm_setup')
        $settingsWindow = Wait-Dialog 'Paramètres'
        Set-DialogText $settingsWindow 'settings_sccm_site' 'DEM'
        Set-DialogText $settingsWindow 'settings_sccm_server' 'sccm.demo.local'
        # Saved as Paramètres closes, before Prochain nom comes back and reads it.
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        $dialog = Wait-Dialog 'Prochain nom'
        $typed = (Get-DialogPart $dialog 'next_format').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($typed -ne 'LABO-###') { $problems.Add("back from Paramètres, the field reads '$typed'") }
        $check = Get-DialogPart $dialog 'next_sccm_check'
        if (-not $check.Current.IsEnabled) { $problems.Add('back from Paramètres, Vérifier dans SCCM is still disabled') }
        elseif ($check.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -ne 'On') { $problems.Add('back from Paramètres, Vérifier dans SCCM isn''t ticked') }
        Close-Dialog $dialog 'dialog_cancel'
        # Closed from itself, it stays closed: the main window is usable again.
        Start-Sleep -Milliseconds 500
        if (-not (Test-WindowEnabled)) { $problems.Add('Prochain nom opened again on its own'); Close-OpenDialog }
    }
}

function Test-NextNameDomains {
    # Five domains, three of them unknown: they're in the button's list, which a box filters, the choice is kept for next
    # time, and the note says the reason once.
    Invoke-Check 'Prochain nom: many domains go in a list, and share one reason' {
        param($problems)
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'ORD-##'
        $null = Wait-NextName $dialog 'ORD-13'
        $count = { Get-DialogPartName $dialog 'next_domains_text' }
        # The first time, the Ordinateurs page's domain alone (#221).
        if ((& $count) -ne 'Domaines : 1 sur 5') { $problems.Add("opened, the button says '$(& $count)'") }
        # The list is a popup, which closes when the window loses the focus (another window on the desktop): opened again
        # before each step when it has, and it can take a moment to show, and to be listed under the window.
        $openList = {
            for ($i = 0; $i -lt 24 -and -not (Get-DialogPart $dialog 'next_domains_filter'); $i++) {
                if ($i % 8 -eq 0) { Invoke-Element (Get-DialogPart $dialog 'next_domains_button') }
                Start-Sleep -Milliseconds 250
            }
            if (-not (Get-DialogPart $dialog 'next_domains_filter')) { throw 'the domains'' list didn''t open' }
        }
        # The filter hides the others, in any case, and Tous ticks only those it shows. Closing empties the filter: the
        # whole step again when the list closed meanwhile.
        $filtered = $false
        for ($try = 0; $try -lt 3 -and -not $filtered; $try++) {
            & $openList
            Set-DialogText $dialog 'next_domains_filter' 'B.DEMO'
            Start-Sleep -Milliseconds 300
            $shown = @(0..4 | Where-Object { Get-DialogPart $dialog "next_domain_$_" })
            $all = Get-DialogPart $dialog 'next_domains_all'
            if (-not $all) { continue }
            Invoke-Element $all
            Start-Sleep -Milliseconds 400
            $filtered = [bool](Get-DialogPart $dialog 'next_domains_filter')
        }
        if ("$shown" -ne '3') { $problems.Add("B.DEMO shows the domains '$shown', not b.demo.local (3) alone") }
        if ((& $count) -ne 'Domaines : 2 sur 5') { $problems.Add("Tous on b.demo.local alone, the button says '$(& $count)'") }
        # Échap empties the filter first, the list staying open.
        Send-Key 0x1B $dialog
        Start-Sleep -Milliseconds 400
        if (-not (Get-DialogPart $dialog 'next_domains_none')) { $problems.Add('Échap closed the list, not the filter') }
        elseif (-not (Get-DialogPart $dialog 'next_domain_0')) { $problems.Add('Échap left the filter on') }
        & $openList
        Invoke-Element (Get-DialogPart $dialog 'next_domains_all')
        Start-Sleep -Milliseconds 400
        if ((& $count) -ne 'Tous les domaines (5)') { $problems.Add("the button says '$(& $count)'") }
        for ($i = 0; $i -lt 20 -and -not (Get-DialogPartName $dialog 'next_domain_note'); $i++) { Start-Sleep -Milliseconds 250 }
        $note = Get-DialogPartName $dialog 'next_domain_note'
        if ($note -notlike 'Non vérifié dans : a.demo.local, b.demo.local, c.demo.local (*' -or $note -like '*;*') { $problems.Add("the note says '$note'") }
        & $openList
        Invoke-Element (Get-DialogPart $dialog 'next_domains_none')
        Start-Sleep -Milliseconds 400
        if ((& $count) -ne 'Domaines : 0 sur 5') { $problems.Add("after Aucun, the button says '$(& $count)'") }
        if ((Get-DialogPart $dialog 'next_copy').Current.IsEnabled) { $problems.Add('no domain, and Copier offers a name') }
        & $openList
        Invoke-Element (Get-DialogPart $dialog 'next_domains_all')
        $null = Wait-NextName $dialog 'ORD-13'
        if ((& $count) -ne 'Tous les domaines (5)') { $problems.Add("after Tous, the button says '$(& $count)'") }
        Send-Key 0x1B $dialog
        Start-Sleep -Milliseconds 400
        if (-not (Get-DialogPart $dialog 'next_format')) { $problems.Add('Échap closed the window, not the list') }
        elseif (Get-DialogPart $dialog 'next_domains_none') { $problems.Add('Échap left the list open') }
        Close-Dialog $dialog 'dialog_cancel'
        # Opened again, the last choice.
        $dialog = Open-NextName
        if ((& $count) -ne 'Tous les domaines (5)') { $problems.Add("opened again, the button says '$(& $count)'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-NextNameSccm {
    # With the fake SCCM's site in Paramètres: what SCCM has is avoided, and each of its answers reads as itself.
    Invoke-Check 'Prochain nom with SCCM: a name only SCCM has is avoided, and the check says so' {
        param($problems)
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'ORD-##'
        $name = Wait-NextName $dialog 'ORD-15'
        if ($name -ne 'ORD-15') { $problems.Add("next name '$name', expected ORD-15 past SCCM's ORD-13 and ORD-14") }
        $result = Get-DialogPartName $dialog 'next_sccm_result'
        if ($result -ne 'Pas dans SCCM.') { $problems.Add("SCCM: '$result'") }
        $count = Get-DialogPartName $dialog 'next_count_text'
        if ($count -ne '99 noms possibles, 14 déjà pris : 12 dans l''AD, 2 seulement dans SCCM') { $problems.Add("with SCCM, the count says '$count'") }
        Set-DialogText $dialog 'next_format' 'VIEUX-01'
        $null = Wait-NextName $dialog 'VIEUX-02'
        Invoke-Element (Get-DialogPart $dialog 'next_block_2')
        $null = Wait-NextName $dialog 'VIEUX-01'
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPartName $dialog 'next_sccm_result') -ne 'Dans SCCM.') { $problems.Add("VIEUX-01: '$(Get-DialogPartName $dialog 'next_sccm_result')'") }
        if ((Get-DialogPartName $dialog 'next_count_text') -ne 'Libre dans l''AD.') { $problems.Add("VIEUX-01 in AD: '$(Get-DialogPartName $dialog 'next_count_text')'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-NextNameFailure {
    # SCCM and a domain that don't answer: the names of what did answer, each failure said, and never « not in SCCM ».
    Invoke-Check 'Prochain nom: SCCM or a domain that doesn''t answer is said, not taken for free' {
        param($problems)
        $dialog = Open-NextName
        # The SCCM session left demo.local alone ticked: nord.demo.local, the domain down, too.
        $nord = (Get-DialogPart $dialog 'next_domain_1').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($nord.Current.ToggleState -ne 'On') { $nord.Toggle() }
        Set-DialogText $dialog 'next_format' 'ORD-##'
        $name = Wait-NextName $dialog 'ORD-13'
        if ($name -ne 'ORD-13') { $problems.Add("next name '$name', from AD alone") }
        $result = Get-DialogPartName $dialog 'next_sccm_result'
        if ($result -ne 'Vérification SCCM impossible : sccm.demo.local ne répond pas. Non vérifié dans SCCM.') { $problems.Add("SCCM: '$result'") }
        if ((Get-DialogPartName $dialog 'next_domain_note') -notlike 'Non vérifié dans : nord.demo.local (*') { $problems.Add("the domain note says '$(Get-DialogPartName $dialog 'next_domain_note')'") }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-SettingsOpen {
    # Whether Paramètres is shown, 1 s after a close: closing only hides it, and a hidden window isn't listed.
    Start-Sleep -Milliseconds 1000
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Paramètres'))
    [bool]$window.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
}

function Close-SettingsWindow($SettingsWindow) {
    $SettingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
}

function Get-DialogValue($Dialog, [string]$AutomationId) {
    (Get-DialogPart $Dialog $AutomationId).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
}

function Set-LeftDialogText($Dialog, [string]$AutomationId, [string]$Text, [string]$Next) {
    # A box typed into, then left for $Next, as the keyboard would: what's saved as the box is left.
    $box = Get-DialogPart $Dialog $AutomationId
    $box.SetFocus()
    $box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    (Get-DialogPart $Dialog $Next).SetFocus()
    Start-Sleep -Milliseconds 300
}

function Test-SettingsSaving {
    # Paramètres › SCCM and Redémarrage, with the fake SCCM's site saved: what's typed is saved as a box, the section or
    # Paramètres is left, with no Enregistrer; what can't be is said under its box, and keeps Paramètres open once.
    # Redémarrer… needs a computer shown.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'

    Invoke-Check 'Paramètres › SCCM: a box left saves it, and Tester saves first, then says whether the site answers' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'sccm'
        if (Get-DialogPart $settingsWindow 'settings_sccm_save') { $problems.Add('SCCM still has an Enregistrer button') }
        if ((Get-DialogValue $settingsWindow 'settings_sccm_site') -ne 'DEM') { $problems.Add('the saved site isn''t shown') }
        $test = { Get-DialogPartName $settingsWindow 'settings_sccm_test_status' }
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_sccm_test')
        for ($i = 0; $i -lt 32 -and (& $test) -ne 'Le site DEM répond.'; $i++) { Start-Sleep -Milliseconds 250 }
        if ((& $test) -ne 'Le site DEM répond.') { $problems.Add("Tester says '$(& $test)'") }
        # Typed, not left: Tester saves it before asking.
        Set-DialogText $settingsWindow 'settings_sccm_site' 'ZZZ'
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_sccm_test')
        $expected = 'Vérification SCCM impossible : le site ZZZ est introuvable sur sccm.demo.local.'
        for ($i = 0; $i -lt 32 -and (& $test) -ne $expected; $i++) { Start-Sleep -Milliseconds 250 }
        if ((& $test) -ne $expected) { $problems.Add("Tester, another site, says '$(& $test)'") }
        if ((Read-SavedSetting 'parametres.json').SccmSite -ne 'ZZZ') { $problems.Add('Tester didn''t save the site first') }
        # A bad code: said under its box, not saved.
        Set-LeftDialogText $settingsWindow 'settings_sccm_site' 'P0' 'settings_sccm_test'
        $problem = Get-DialogPartName $settingsWindow 'settings_sccm_site_problem'
        if ($problem -notlike 'Le code du site*') { $problems.Add("a bad code says '$problem' under its box") }
        if (Get-DialogPartName $settingsWindow 'settings_sccm_server_problem') { $problems.Add('a bad code is said under the server too') }
        if (Get-DialogPartName $settingsWindow 'settings_sccm_status') { $problems.Add("beside a bad code, it still says '$(Get-DialogPartName $settingsWindow 'settings_sccm_status')'") }
        if ((Read-SavedSetting 'parametres.json').SccmSite -ne 'ZZZ') { $problems.Add('a bad code was saved') }
        # Lowercase: saved, and shown, in capitals.
        Set-LeftDialogText $settingsWindow 'settings_sccm_site' 'dem' 'settings_sccm_test'
        if (Get-DialogPartName $settingsWindow 'settings_sccm_site_problem') { $problems.Add('the problem stays once the code is fixed') }
        if ((Read-SavedSetting 'parametres.json').SccmSite -cne 'DEM') { $problems.Add("leaving the box saved '$((Read-SavedSetting 'parametres.json').SccmSite)'") }
        if ((Get-DialogValue $settingsWindow 'settings_sccm_site') -cne 'DEM') { $problems.Add("saved, the box shows '$(Get-DialogValue $settingsWindow 'settings_sccm_site')'") }
        $status = Get-DialogPartName $settingsWindow 'settings_sccm_status'
        if ($status) { $problems.Add("saved, it still says '$status'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'parametres-sccm' $settingsWindow }
        Close-SettingsWindow $settingsWindow
        if (Test-SettingsOpen) { $problems.Add('Paramètres stayed open with nothing left to save') }
    }

    Invoke-Check 'Paramètres › SCCM: both boxes emptied and the section left turns SCCM off, and says so' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'sccm'
        # From one box to the other: the site alone isn't refused meanwhile.
        Set-LeftDialogText $settingsWindow 'settings_sccm_site' '' 'settings_sccm_server'
        if (Get-DialogPartName $settingsWindow 'settings_sccm_server_problem') { $problems.Add('going from the site to the server already says what''s missing') }
        (Get-DialogPart $settingsWindow 'settings_sccm_server').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
        (Get-DialogPart $settingsWindow 'nav_shortcuts').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 300
        $saved = Read-SavedSetting 'parametres.json'
        if ($saved.SccmSite -or $saved.SccmServer) { $problems.Add("parametres.json still holds $($saved.SccmSite) on $($saved.SccmServer)") }
        (Get-DialogPart $settingsWindow 'nav_sccm').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 300
        $status = Get-DialogPartName $settingsWindow 'settings_sccm_status'
        if ($status -ne 'SCCM désactivé : « Prochain nom… » ne vérifiera que dans l''AD.') { $problems.Add("emptied, it says '$status'") }
        # Typed again and Paramètres closed: saved as it closes.
        Set-DialogText $settingsWindow 'settings_sccm_site' 'DEM'
        Set-DialogText $settingsWindow 'settings_sccm_server' 'sccm.demo.local'
        Close-SettingsWindow $settingsWindow
        if (Test-SettingsOpen) { $problems.Add('Paramètres stayed open') }
        $saved = Read-SavedSetting 'parametres.json'
        if ("$($saved.SccmSite) $($saved.SccmServer)" -ne 'DEM sccm.demo.local') { $problems.Add("closing saved $($saved.SccmSite) on $($saved.SccmServer)") }
    }

    Invoke-Check 'Paramètres › SCCM: a bad server keeps Paramètres open once, says why, and the next close drops it' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'sccm'
        Set-DialogText $settingsWindow 'settings_sccm_server' 'sccm demo'
        Close-SettingsWindow $settingsWindow
        if (-not (Test-SettingsOpen)) { $problems.Add('Paramètres closed with a server it couldn''t save') }
        else {
            $problem = Get-DialogPartName $settingsWindow 'settings_sccm_server_problem'
            if ($problem -notlike 'Le serveur est un nom*') { $problems.Add("under the server: '$problem'") }
            $status = Get-DialogPartName $settingsWindow 'settings_sccm_status'
            if ($status -notlike 'Pas enregistré*') { $problems.Add("kept open, it says '$status'") }
            Close-SettingsWindow $settingsWindow
            if (Test-SettingsOpen) { $problems.Add('the second close didn''t close Paramètres') }
        }
        if ((Read-SavedSetting 'parametres.json').SccmServer -ne 'sccm.demo.local') { $problems.Add('the bad server was saved') }
        $settingsWindow = Open-SettingsSection 'sccm'
        if ((Get-DialogValue $settingsWindow 'settings_sccm_server') -ne 'sccm.demo.local') { $problems.Add("reopened, the server box holds '$(Get-DialogValue $settingsWindow 'settings_sccm_server')'") }
        if (Get-DialogPartName $settingsWindow 'settings_sccm_server_problem') { $problems.Add('reopened, the problem is still shown') }
        Close-SettingsWindow $settingsWindow
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Paramètres › Redémarrage: saved with no Enregistrer, and the defaults saved are those Redémarrer… proposes' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'restart'
        if (Get-DialogPart $settingsWindow 'settings_restart_save') { $problems.Add('Redémarrage still has an Enregistrer button') }
        Set-DialogText $settingsWindow 'settings_restart_amount' '2'
        # The unit is saved as it's chosen, with the delay typed.
        Select-ComboItem 'settings_restart_unit' 'heures'
        Start-Sleep -Milliseconds 300
        $saved = Read-SavedSetting 'redemarrage.json'
        if ("$($saved.Amount) $($saved.Unit)" -ne '2 heures') { $problems.Add("the unit chosen saved $($saved.Amount) $($saved.Unit)") }
        Set-DialogText $settingsWindow 'settings_restart_message' 'Maintenance dans {délai}.'
        Start-Sleep -Milliseconds 200
        $preview = (Get-DialogPart $settingsWindow 'settings_restart_preview').Current.Name
        if ($preview -ne 'Maintenance dans 2 heures.') { $problems.Add("the preview says '$preview'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'parametres-redemarrage' $settingsWindow }
        # Not left yet: saved as Paramètres closes.
        Close-SettingsWindow $settingsWindow
        Start-Sleep -Milliseconds 300
        $saved = Read-SavedSetting 'redemarrage.json'
        if ("$($saved.Amount) $($saved.Unit) $($saved.Message)" -ne '2 heures Maintenance dans {délai}.') { $problems.Add("redemarrage.json holds: $($saved | ConvertTo-Json -Compress)") }
        $dialog = Open-RestartDialog 'ORD-01'
        $shown = "$(Get-RestartPart $dialog 'restart_amount') $(Get-ComboText 'restart_unit') $(Get-RestartPart $dialog 'restart_message')"
        if ($shown -ne '2 heures Maintenance dans {délai}.') { $problems.Add("Redémarrer… proposes: $shown") }
        Close-Dialog $dialog 'restart_cancel'
    }

    Invoke-Check 'Paramètres › Redémarrage: coming back to the section counts {heure} from now, not from when Paramètres opened' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'restart'
        Set-DialogText $settingsWindow 'settings_restart_message' '{heure}'
        Start-Sleep -Milliseconds 200
        $before = (Get-DialogPart $settingsWindow 'settings_restart_preview').Current.Name
        (Get-DialogPart $settingsWindow 'nav_shortcuts').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        # The preview shows the minutes: wait for the clock's to turn.
        $minute = (Get-Date).Minute
        while ((Get-Date).Minute -eq $minute) { Start-Sleep -Milliseconds 250 }
        (Get-DialogPart $settingsWindow 'nav_restart').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 400
        $after = (Get-DialogPart $settingsWindow 'settings_restart_preview').Current.Name
        if ($after -eq $before) { $problems.Add("a minute later, the preview still says '$after'") }
        if ((Read-SavedSetting 'redemarrage.json').Message -ne '{heure}') { $problems.Add('leaving the section didn''t save the message') }
        Close-SettingsWindow $settingsWindow
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Paramètres › Redémarrage: Valeurs par défaut is saved; a delay too long keeps Paramètres open once, and isn''t saved' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'restart'
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_restart_reset')
        Start-Sleep -Milliseconds 300
        $saved = Read-SavedSetting 'redemarrage.json'
        if ("$($saved.Amount) $($saved.Unit)" -ne '5 minutes' -or $saved.Message -notlike 'Votre ordinateur va redémarrer*') { $problems.Add("Valeurs par défaut saved: $($saved | ConvertTo-Json -Compress)") }
        if ((Get-DialogPartName $settingsWindow 'settings_restart_status') -notlike 'Enregistré*') { $problems.Add("Valeurs par défaut says '$(Get-DialogPartName $settingsWindow 'settings_restart_status')'") }
        Set-DialogText $settingsWindow 'settings_restart_amount' '99999'
        Close-SettingsWindow $settingsWindow
        if (-not (Test-SettingsOpen)) { $problems.Add('Paramètres closed with a delay it couldn''t save') }
        else {
            $status = Get-DialogPartName $settingsWindow 'settings_restart_status'
            if ($status -notlike 'Pas enregistré*') { $problems.Add("kept open, it says '$status'") }
            Close-SettingsWindow $settingsWindow
            if (Test-SettingsOpen) { $problems.Add('the second close didn''t close Paramètres') }
        }
        if ((Read-SavedSetting 'redemarrage.json').Amount -ne 5) { $problems.Add("the delay too long was saved: $((Read-SavedSetting 'redemarrage.json').Amount)") }
    }
}

function Test-SettingsWindow {
    # Paramètres, in a session of its own: Déplacer vers saves the OUs chosen, which Déplacer vers… then offers, also
    # after a restart; Raccourcis lists the keys. SCCM and Redémarrage: Test-SettingsSaving.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'
    $postes = 'OU=Postes,DC=demo,DC=local'

    Invoke-Check 'Paramètres: six sections, Apparence first' {
        param($problems)
        Invoke-Element (Find-Control 'settings')
        $settingsWindow = Wait-Dialog 'Paramètres'
        $isItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
        $names = @((Get-DialogPart $settingsWindow 'settings_nav').FindAll($Descendants, $isItem) | ForEach-Object { $_.Current.Name }) -join ', '
        if ($names -ne 'Apparence, Déplacer vers, Redémarrage, Mots de passe, SCCM, Raccourcis') { $problems.Add("sections: $names") }
        if (-not (Get-DialogPart $settingsWindow 'create_theme')) { $problems.Add("it doesn't open on the themes") }
        if (-not (Test-WindowEnabled)) { $problems.Add('the main window is disabled') }
    }

    Invoke-Check 'Paramètres › Déplacer vers: the OUs start closed, the page itself never scrolls, and a maximized window leaves the cards as they are' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        $postesItem = Get-MoveRootItem $settingsWindow 'Postes'
        $state = $postesItem.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState
        if ($state -ne 'Collapsed') { $problems.Add("Postes is $state") }
        if (Get-DialogPart $settingsWindow 'settings_scroll') { $problems.Add('the scrolling of the other sections is shown') }
        $tree = (Get-DialogPart $settingsWindow 'move_roots_tree').Current.BoundingRectangle
        $window = $settingsWindow.Current.BoundingRectangle
        # As tall as its OUs: five rows here, not the window's height. Compared with a row and with the other card, whose
        # text is about 270 wide: the display's scale changes them all. The tree's column stops at 640.
        $row = $postesItem.Current.BoundingRectangle.Height
        if ($tree.Height -gt 6.5 * $row) { $problems.Add("the tree is $([int]$tree.Height) px high for five OUs of $([int]$row) px") }
        $textWidth = (Get-DialogPart $settingsWindow 'move_roots_summary').Current.BoundingRectangle.Width
        $pattern = $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
        try {
            $pattern.SetWindowVisualState('Maximized')
            Start-Sleep -Milliseconds 500
            $wide = (Get-DialogPart $settingsWindow 'move_roots_tree').Current.BoundingRectangle
            if ([Math]::Abs($wide.Height - $tree.Height) -gt 2) { $problems.Add("maximized, the tree goes from $([int]$tree.Height) to $([int]$wide.Height) px high") }
            if ($wide.Width -gt 2.4 * $textWidth) { $problems.Add("maximized, the tree is $([int]$wide.Width) px wide, beside a text $([int]$textWidth) px wide") }
        }
        finally { $pattern.SetWindowVisualState('Normal'); Start-Sleep -Milliseconds 400 }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Paramètres › Déplacer vers: the filter shows the OUs it finds with their parents, says when it finds none, and leaves the tree as it was' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        $filter = (Get-DialogPart $settingsWindow 'move_roots_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $filter.SetValue('Entree')
        Start-Sleep -Milliseconds 300
        if (-not (Get-MoveRootBox $settingsWindow 'Communs-Entree')) { $problems.Add("Communs-Entree isn't shown") }
        foreach ($hidden in 'Serveurs', 'Kiosques') {
            $box = $settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $hidden))
            if ($box) { $problems.Add("$hidden is still shown") }
        }
        $filter.SetValue('zzz')
        Start-Sleep -Milliseconds 300
        $status = Get-DialogPartName $settingsWindow 'move_roots_status'
        if ($status -ne 'Aucune OU ne correspond.') { $problems.Add("with no OU found, it says '$status'") }
        $filter.SetValue('')
        Start-Sleep -Milliseconds 300
        if (Get-DialogPartName $settingsWindow 'move_roots_status') { $problems.Add('the message stays once the filter is empty') }
        $state = (Get-MoveRootItem $settingsWindow 'Postes').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState
        if ($state -ne 'Collapsed') { $problems.Add("once the filter is empty, Postes is $state") }
        # Paramètres is only hidden when it's closed: the filter goes all the same.
        $filter.SetValue('Entree')
        Start-Sleep -Milliseconds 300
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
        $settingsWindow = Open-SettingsSection 'move'
        $left = (Get-DialogPart $settingsWindow 'move_roots_filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($left) { $problems.Add("reopened, the filter holds '$left'") }
        if (-not $settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Serveurs'))) { $problems.Add("reopened, Serveurs isn't shown") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Paramètres › Déplacer vers: an OU opened stays opened after another section' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        $states = [System.Windows.Automation.ExpandCollapsePattern]::Pattern
        (Get-MoveRootItem $settingsWindow 'Postes').GetCurrentPattern($states).Expand()
        Start-Sleep -Milliseconds 300
        (Get-DialogPart $settingsWindow 'nav_restart').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 300
        (Get-DialogPart $settingsWindow 'nav_move').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 300
        $item = Get-MoveRootItem $settingsWindow 'Postes'
        if ($item.GetCurrentPattern($states).Current.ExpandCollapseState -ne 'Expanded') { $problems.Add('Postes closed') }
        $item.GetCurrentPattern($states).Collapse()
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Paramètres › Déplacer vers: a ticked OU is saved, ticks those under it, and is the only one Déplacer vers… offers' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        $summary = (Get-DialogPart $settingsWindow 'move_roots_summary').Current.Name
        if ($summary -notlike 'Toutes les OU*') { $problems.Add("at first, the summary says '$summary'") }
        (Get-MoveRootBox $settingsWindow 'Postes').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 400
        (Get-MoveRootItem $settingsWindow 'Postes').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        Start-Sleep -Milliseconds 300
        $saved = @((Read-SavedSetting 'parametres.json').MoveRoots)
        if (($saved -join ' | ') -ne $postes) { $problems.Add("parametres.json holds: $($saved -join ' | ')") }
        $states = "Postes $(Get-BoxState (Get-MoveRootBox $settingsWindow 'Postes')) | Communs $(Get-BoxState (Get-MoveRootBox $settingsWindow 'Communs')) | Kiosques $(Get-BoxState (Get-MoveRootBox $settingsWindow 'Kiosques'))"
        if ($states -ne 'Postes On | Communs On (grisée) | Kiosques Off') { $problems.Add("boxes: $states") }
        $summary = (Get-DialogPart $settingsWindow 'move_roots_summary').Current.Name
        if ($summary -notlike '*Un domaine sans case cochée*') { $problems.Add("with two domains, the summary says '$summary'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'parametres-deplacer' $settingsWindow }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
        Select-ResultRow 'ORD-06'
        $dialog = Open-MoveDialog 'act_move'
        $top = (Get-MoveTreeItem $dialog -TopLevel) -join ', '
        # ORD-06 is in Postes already.
        if ($top -ne 'Postes (actuel)') { $problems.Add("Déplacer vers… offers at the top: $top") }
        Close-Dialog $dialog 'move_cancel'
    }

    Invoke-Check 'Paramètres › Déplacer vers: the OUs chosen come back after a restart, and unticking them offers every OU again' {
        param($problems)
        Stop-App
        Start-App -KeepSettings
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-0'
        $settingsWindow = Open-SettingsSection 'move'
        $box = Get-MoveRootBox $settingsWindow 'Postes'
        if ((Get-BoxState $box) -ne 'On') { $problems.Add("after the restart, Postes is $(Get-BoxState $box)") }
        $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Milliseconds 400
        $saved = @((Read-SavedSetting 'parametres.json').MoveRoots)
        if ($saved.Count) { $problems.Add("parametres.json still holds: $($saved -join ' | ')") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
        Select-ResultRow 'ORD-06'
        $dialog = Open-MoveDialog 'act_move'
        $top = @(Get-MoveTreeItem $dialog -TopLevel)
        if ($top -notcontains 'Kiosques' -or $top -notcontains 'Postes (actuel)') { $problems.Add("Déplacer vers… offers at the top: $($top -join ', ')") }
        Close-Dialog $dialog 'move_cancel'
    }

    Invoke-Check 'Paramètres › Déplacer vers: the OUs chosen are listed beside the tree, and come off one at a time or all at once' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'move'
        foreach ($name in 'Postes', 'Kiosques', 'Serveurs') {
            (Get-MoveRootBox $settingsWindow $name).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
            Start-Sleep -Milliseconds 300
        }
        $remove = $settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Retirer Kiosques'))
        if (-not $remove) { throw "No button to take Kiosques off." }
        $remove.SetFocus()
        Invoke-Element $remove
        Start-Sleep -Milliseconds 400
        $focused = $AE::FocusedElement.Current.Name
        if ($focused -ne 'Retirer Postes') { $problems.Add("once Kiosques is off, the keyboard is on '$focused'") }
        $saved = @((Read-SavedSetting 'parametres.json').MoveRoots)
        if (($saved -join ' | ') -notmatch '^OU=Postes,DC=demo,DC=local \| OU=Serveurs,DC=demo,DC=local$') { $problems.Add("parametres.json holds: $($saved -join ' | ')") }
        if ((Get-BoxState (Get-MoveRootBox $settingsWindow 'Kiosques')) -ne 'Off') { $problems.Add("Kiosques is $(Get-BoxState (Get-MoveRootBox $settingsWindow 'Kiosques'))") }
        Invoke-Element (Get-DialogPart $settingsWindow 'move_roots_clear')
        Start-Sleep -Milliseconds 400
        $focused = $AE::FocusedElement.Current.AutomationId
        if ($focused -ne 'move_roots_filter') { $problems.Add("after Tout décocher, the keyboard is on '$focused'") }
        $saved = @((Read-SavedSetting 'parametres.json').MoveRoots)
        if ($saved.Count) { $problems.Add("after Tout décocher, parametres.json holds: $($saved -join ' | ')") }
        if ((Get-BoxState (Get-MoveRootBox $settingsWindow 'Postes')) -ne 'Off') { $problems.Add("Postes is $(Get-BoxState (Get-MoveRootBox $settingsWindow 'Postes'))") }
        if (Get-DialogPart $settingsWindow 'move_roots_clear') { $problems.Add('Tout décocher stays with no OU chosen') }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 300
    }

    Invoke-Check 'Paramètres › Apparence: the font, text size and weight apply to every window, are saved, and Par défaut undoes them' {
        param($problems)
        # The size scales each window's content as a whole: the delete button grows with it. The window may grow to fit
        # the larger bar: it's put back to its size before comparing, where the buttons show no label.
        $rect = $window.Current.BoundingRectangle
        $before = (Find-Control 'act_remove').Current.BoundingRectangle.Width
        $settingsWindow = Open-SettingsSection 'appearance'
        # A short list, Segoe UI first: Windows' fonts, and those shipped in fonts\ even when they aren't installed.
        $fontBox = Get-DialogPart $settingsWindow 'text_font'
        $expand = $fontBox.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        $expand.Expand()
        Start-Sleep -Milliseconds 400
        $listItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
        $fonts = @($fontBox.FindAll($Descendants, $listItem) | ForEach-Object { $_.Current.Name })
        $expand.Collapse()
        $missing = @('Segoe UI', 'Verdana', 'Consolas', 'Atkinson Hyperlegible Next', 'Inter', 'JetBrains Mono', 'Cascadia Mono' | Where-Object { $_ -notin $fonts })
        if ($fonts[0] -ne 'Segoe UI' -or $missing -or $fonts.Count -gt 11) { $problems.Add("the fonts offered are: $($fonts -join ', ')") }
        Select-ComboItem 'text_font' 'Verdana'
        Invoke-Element (Get-DialogPart $settingsWindow 'text_size_larger')
        Invoke-Element (Get-DialogPart $settingsWindow 'text_weight_Bold')
        Start-Sleep -Milliseconds 500
        $saved = Read-SavedSetting 'apparence.json'
        if ("$($saved.FontFamily) $($saved.TextScale) $($saved.FontWeight)" -ne 'Verdana 1.3 Bold') { $problems.Add("apparence.json holds: FontFamily '$($saved.FontFamily)', TextScale '$($saved.TextScale)', FontWeight '$($saved.FontWeight)'") }
        $after = (Find-Control 'act_remove').Current.BoundingRectangle.Width
        if ($after -lt $before * 1.25) { $problems.Add("the delete button is $after wide, $before before: the size didn't follow") }
        if ($ScreenshotDirectory) { Save-Screenshot 'parametres-texte' $settingsWindow }
        # Par défaut can be clicked while the text isn't the default, and no longer once it is (#186).
        if (-not (Get-DialogPart $settingsWindow 'text_reset').Current.IsEnabled) { $problems.Add('with Verdana, 130 % and Grasse, Par défaut is disabled') }
        Invoke-Element (Get-DialogPart $settingsWindow 'text_reset')
        Start-Sleep -Milliseconds 500
        $saved = Read-SavedSetting 'apparence.json'
        if ($saved.PSObject.Properties['FontFamily'] -or $saved.PSObject.Properties['TextScale'] -or $saved.PSObject.Properties['FontWeight']) { $problems.Add("after Par défaut, apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)") }
        if ((Get-DialogPart $settingsWindow 'text_reset').Current.IsEnabled) { $problems.Add('after Par défaut, it can still be clicked') }
        Set-WindowState 'Normal' $rect.Width $rect.Height
        $reset = (Find-Control 'act_remove').Current.BoundingRectangle.Width
        if ([Math]::Abs($reset - $before) -gt 1) { $problems.Add("after Par défaut, the delete button is $reset wide, $before before") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check 'In a wider font, the window at its narrowest still shows the whole selection text, its buttons square' {
        param($problems)
        # JetBrains Mono is wider than Segoe UI: the action bar is too, and the window's minimum width follows. Vérifier en
        # ligne, Caractéristiques and Désactiver lose their label there, their name in their tooltip.
        $rect = $window.Current.BoundingRectangle
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-0'
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-03'
        Add-ResultRow 'ORD-04'
        $settingsWindow = Open-SettingsSection 'appearance'
        Select-ComboItem 'text_font' 'JetBrains Mono'
        Start-Sleep -Milliseconds 500
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        try {
            Set-WindowState 'Normal' 400 $rect.Height
            $bounds = $window.Current.BoundingRectangle
            $text = Find-Control 'selection_text'
            if ($text.Current.Name -ne '3 ordinateurs sélectionnés') { $problems.Add("the selection text says '$($text.Current.Name)'") }
            if ($text.Current.BoundingRectangle.Right -gt $bounds.Right) { $problems.Add("in a window $($bounds.Width) wide, the selection text ends at $($text.Current.BoundingRectangle.Right), past its edge at $($bounds.Right)") }
            $shown = @('act_ping_label', 'act_specs_label', 'act_toggle_text' | Where-Object { Find-ShownControl $_ })
            if ($shown.Count) { $problems.Add("in a window $($bounds.Width) wide, labels shown: $($shown -join ', ')") }
            $tip = (Find-Control 'act_ping').Current.HelpText
            if (-not $tip.StartsWith('Vérifier en ligne')) { $problems.Add("square, Vérifier en ligne's tooltip says '$tip'") }
            $tip = (Find-Control 'act_toggle').Current.HelpText
            if ($tip -ne 'Désactiver…') { $problems.Add("square, Désactiver's tooltip says '$tip'") }
            $width = (Find-Control 'act_specs').Current.BoundingRectangle.Width
            $square = (Find-Control 'act_edit').Current.BoundingRectangle.Width
            if ([Math]::Abs($width - $square) -gt 1) { $problems.Add("square, Caractéristiques is $width wide, the icon buttons $square") }
            if ($ScreenshotDirectory) { Save-Screenshot 'fenetre-etroite' }
        }
        finally {
            Set-WindowState 'Normal' $rect.Width $rect.Height
            $settingsWindow = Open-SettingsSection 'appearance'
            Invoke-Element (Get-DialogPart $settingsWindow 'text_reset')
            Start-Sleep -Milliseconds 500
            $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        }
    }

    Invoke-Check 'Paramètres › Mots de passe: each choice is saved, « toujours le même » without a password says a generated one is used, and the eye shows the password' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'passwords'
        (Get-DialogPart $settingsWindow 'settings_password_default').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 300
        $saved = Read-SavedSetting 'motdepasse.json'
        if ($saved.Mode -ne 'Default') { $problems.Add("after Toujours le même, motdepasse.json holds: $($saved | ConvertTo-Json -Compress)") }
        $status = (Get-DialogPart $settingsWindow 'settings_password_status').Current.Name
        if ($status -notlike 'Entrez le mot de passe par défaut*') { $problems.Add("the status says '$status'") }
        # The eye: typed in plain text, it's saved as from the PasswordBox; emptied, then hidden again.
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_password_show')
        Start-Sleep -Milliseconds 300
        $plain = Get-DialogPart $settingsWindow 'settings_password_text'
        if (-not $plain) { $problems.Add("after the eye, the password isn't shown") }
        else {
            $plain.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Pomme-Nuage-47')
            Start-Sleep -Milliseconds 300
            $saved = Read-SavedSetting 'motdepasse.json'
            $default = if ($saved.Default) { [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString -String $saved.Default)).Password }
            if ($default -ne 'Pomme-Nuage-47') { $problems.Add("typed shown, the saved password is '$default'") }
            if ($ScreenshotDirectory) { Save-Screenshot 'parametres-mots-de-passe' $settingsWindow }
            $plain.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
        }
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_password_hide')
        Start-Sleep -Milliseconds 300
        if ((Get-DialogPart $settingsWindow 'settings_password_text') -or -not (Get-DialogPart $settingsWindow 'settings_password_show')) { $problems.Add('after hiding it, the password is still shown') }
        # Shown when Paramètres closes: hidden again the next time it opens.
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_password_show')
        Start-Sleep -Milliseconds 300
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 400
        $settingsWindow = Open-SettingsSection 'passwords'
        if ((Get-DialogPart $settingsWindow 'settings_password_text') -or -not (Get-DialogPart $settingsWindow 'settings_password_show')) { $problems.Add('after closing Paramètres with the password shown, it is still shown') }
        (Get-DialogPart $settingsWindow 'settings_password_must_change').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        (Get-DialogPart $settingsWindow 'settings_password_generated').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 300
        $saved = Read-SavedSetting 'motdepasse.json'
        if ($saved.Mode -ne 'Generated' -or $saved.MustChange -ne $false -or $saved.Default) { $problems.Add("then motdepasse.json holds: $($saved | ConvertTo-Json -Compress)") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check 'A newer Repère on GitHub: Paramètres'' button names it, and Paramètres links to it' {
        param($problems)
        $tip = ''
        for ($i = 0; $i -lt 40 -and $tip -notlike 'Repère 99.0.0*'; $i++) { Start-Sleep -Milliseconds 250; $tip = (Find-Control 'settings').Current.HelpText }
        if ($tip -ne 'Repère 99.0.0 est disponible : voir Paramètres.') { $problems.Add("Paramètres' button says '$tip'") }
        $settingsWindow = Open-SettingsSection 'shortcuts'
        $link = Get-DialogPart $settingsWindow 'settings_update_link'
        if (-not $link -or $link.Current.Name -ne 'Repère 99.0.0 est disponible : le télécharger') { $problems.Add("the link says '$(if ($link) { $link.Current.Name })'") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check 'Paramètres › Raccourcis lists the keyboard shortcuts' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'shortcuts'
        foreach ($text in 'Ctrl+F', 'Ctrl+N', 'F5', '↓ ↑', 'Suppr', 'Copier les noms sélectionnés (les identifiants sur Utilisateurs), ou le texte sélectionné', 'F2', 'Double-clic',
                          'Caractéristiques…', 'Propriétés…', 'Annuler la modification en cours, puis fermer la fenêtre') {
            if (-not $settingsWindow.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $text))) { $problems.Add("'$text' isn't listed") }
        }
        # F2 and Suppr only under Ordinateurs, the one page that has them: after its title, before the next group's.
        $texts = @($settingsWindow.FindAll($Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name } | Where-Object { $_ })
        $computers = [array]::LastIndexOf([string[]]$texts, 'Ordinateurs')
        $specs = [array]::LastIndexOf([string[]]$texts, 'Caractéristiques')
        foreach ($key in 'F2', 'Suppr') {
            $at = [array]::IndexOf([string[]]$texts, $key)
            if (-not ($at -gt $computers -and $at -lt $specs) -or [array]::LastIndexOf([string[]]$texts, $key) -ne $at) { $problems.Add("'$key' isn't listed under Ordinateurs alone") }
        }
        if ([array]::IndexOf([string[]]$texts, 'Propriétés') -lt 0) { $problems.Add("there's no Propriétés group") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }
}

function Get-DensityMeasure([string]$Grid = 'data_grid', [string]$SearchButton = 'button') {
    # On screen: a grid's first row, the search button beside it, and that row's first text (whose height is the
    # text's, not the row's).
    $isRow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)
    $isCell = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'CellTextBlock')
    $row = @((Find-Control $Grid).FindAll($Descendants, $isRow) | Sort-Object { $_.Current.BoundingRectangle.Top })[0]
    if (-not $row) { throw "$Grid has no row." }
    @{ Row    = $row.Current.BoundingRectangle.Height
       Search = (Find-Control $SearchButton).Current.BoundingRectangle.Height
       Text   = @($row.FindAll($Descendants, $isCell) | Where-Object { $_.Current.Name })[0].Current.BoundingRectangle.Height }
}

function Get-DensityChoice($SettingsWindow) {
    # The density toggled on in Paramètres › Apparence, by its id.
    @('density_compact', 'density_normal', 'density_airy' | Where-Object {
        (Get-DialogPart $SettingsWindow $_).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On'
    }) -join ', '
}

function Get-ChangelogText($Dialog) {
    # Every text Nouveautés shows: its subtitle, its sections' names, its headlines, « et 6 autres ».
    $isText = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    @($Dialog.FindAll($Descendants, $isText) | ForEach-Object { $_.Current.Name })
}

function Test-ChangelogClosed($Owner) {
    # Whether Nouveautés, over $Owner (the main window), has closed within 3 s. A window: Paramètres' link has the same
    # name.
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window),
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Nouveautés'))
    for ($i = 0; $i -lt 20; $i++) {
        if (-not $Owner.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)) { return $true }
        Start-Sleep -Milliseconds 150
    }
    $false
}

function Test-ChangelogContent($Dialog, [string]$Current, [string[]]$Sections, $Problems) {
    # Nouveautés shows $Current's notes only: its version in the subtitle, its sections ($Sections, from CHANGELOG.md)
    # with headlines, and Voir le détail.
    $texts = @(Get-ChangelogText $Dialog)
    if (-not ($texts -like "Repère $Current — *")) { $Problems.Add("its subtitle isn't Repère ${Current}: $($texts[0..1] -join ' / ')") }
    $missing = @($Sections | Where-Object { $_ -notin $texts })
    if ($missing) { $Problems.Add("sections missing: $($missing -join ', ')") }
    $other = @($texts | Where-Object { $_ -match '^(Repère )?\d+\.\d+\.\d+ — ' -and $_ -notlike "Repère $Current — *" })
    if ($other) { $Problems.Add("it shows another version: $($other -join ', ')") }
    if ($texts.Count -lt $Sections.Count * 2 + 1) { $Problems.Add("too few headlines: $($texts -join ' | ')") }
    if (-not (Get-DialogPart $Dialog 'changelog_detail')) { $Problems.Add('it has no Voir le détail') }
}

function Test-ChangelogFit {
    # At Très grande in Verdana bold (the widest text), Nouveautés' Voir le détail and Fermer stay in the window, one
    # after the other. Repère starts again with that apparence.json; the session removes it after.
    Restart-App '{ "TextScale": 1.3, "FontFamily": "Verdana", "FontWeight": "Bold" }'
    Invoke-Check "Nouveautés at Très grande, Verdana gras: Voir le détail and Fermer fit in it" {
        param($problems)
        $dialog = Wait-Dialog 'Nouveautés'
        if ($ScreenshotDirectory) { Save-Screenshot 'nouveautes-tres-grande' $dialog }
        $box = $dialog.Current.BoundingRectangle
        $right = $null
        foreach ($id in 'changelog_detail', 'dialog_cancel') {
            $rect = (Get-DialogPart $dialog $id).Current.BoundingRectangle
            if ($rect.Left -lt $box.Left + 8 -or $rect.Right -gt $box.Right - 8 -or $rect.Bottom -gt $box.Bottom) { $problems.Add("$id spans $($rect.Left)-$($rect.Right), the window $($box.Left)-$($box.Right)") }
            if ($null -ne $right -and $rect.Left -lt $right) { $problems.Add("$id overlaps the one before it") }
            $right = $rect.Right
        }
        Invoke-Element (Get-DialogPart $dialog 'dialog_cancel')
    }
}

function Test-Changelog([string]$Current, [string[]]$Sections) {
    # #9: started after an update (the session gives the version seen before), Nouveautés opens with this version's
    # headlines only, this version saved as seen in parametres.json, and its X closes it. It has no box to stop it.
    # Paramètres' « Nouveautés » opens it again, one window however often it's clicked.
    $settingsFile = Join-Path $env:APPDATA 'Repere\parametres.json'
    Invoke-Check "Nouveautés: opens at start after an update with this version's headlines, saved as seen; its X closes it" {
        param($problems)
        $dialog = Wait-Dialog 'Nouveautés'
        if ($ScreenshotDirectory) { Save-Screenshot 'nouveautes' $dialog }
        Test-ChangelogContent $dialog $Current $Sections $problems
        $close = Get-DialogPart $dialog 'caption_close'
        if (-not $close) { $problems.Add('it has no X') }
        if (Get-DialogPart $dialog 'changelog_hide') { $problems.Add('it still has « Ne plus afficher »') }
        $saved = if (Test-Path $settingsFile) { Get-Content $settingsFile -Raw | ConvertFrom-Json }
        if (-not $saved -or $saved.SeenVersion -ne $Current) {
            $problems.Add("parametres.json holds: $(if ($saved) { $saved | ConvertTo-Json -Compress })")
        }
        if ($close) {
            Invoke-Element $close
            if (-not (Test-ChangelogClosed $window)) { $problems.Add("its X didn't close it") }
        }
    }

    Invoke-Check "Nouveautés: Paramètres' link opens it again, once however often it's clicked" {
        param($problems)
        $settingsWindow = Open-SettingsSection 'shortcuts'
        $link = Get-DialogPart $settingsWindow 'settings_changelog_link'
        Invoke-Element $link
        $null = Wait-Dialog 'Nouveautés'
        Invoke-Element $link
        Start-Sleep -Milliseconds 600
        $isChangelog = [System.Windows.Automation.AndCondition]::new(
            [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window),
            [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'Nouveautés'))
        $open = @($window.FindAll([System.Windows.Automation.TreeScope]::Children, $isChangelog)).Count
        if ($open -ne 1) { $problems.Add("two clicks leave $open windows open") }
        $dialog = Wait-Dialog 'Nouveautés'
        Test-ChangelogContent $dialog $Current $Sections $problems
        Invoke-Element (Get-DialogPart $dialog 'dialog_cancel')
        if (-not (Test-ChangelogClosed $window)) { $problems.Add("Fermer didn't close it") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check "Nouveautés: a section chosen in its column goes to it and stays chosen; « et 6 autres » shows the others in their place" {
        param($problems)
        $settingsWindow = Open-SettingsSection 'shortcuts'
        Invoke-Element (Get-DialogPart $settingsWindow 'settings_changelog_link')
        $dialog = Wait-Dialog 'Nouveautés'
        $items = @(0..($Sections.Count - 1) | ForEach-Object { Get-DialogPart $dialog "changelog_nav_$_" } | Where-Object { $_ })
        $chosen = { param($item) $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }
        if ($items.Count -ne $Sections.Count) { $problems.Add("$($items.Count) items in the column for $($Sections.Count) sections") }
        elseif ($Sections.Count -ge 2) {
            if (-not (& $chosen $items[0])) { $problems.Add('the first section isn''t chosen at first') }
            $scroll = (Get-DialogPart $dialog 'changelog_scroll').GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
            $items[-1].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
            Start-Sleep -Milliseconds 500
            $selected = @($items | Where-Object { & $chosen $_ })
            if ($selected.Count -ne 1 -or $selected[0].Current.AutomationId -ne $items[-1].Current.AutomationId) { $problems.Add("after the last section, the ones chosen are: $($selected.Current.AutomationId -join ', ')") }
            if ($scroll.Current.VerticallyScrollable -and $scroll.Current.VerticalScrollPercent -lt 99) { $problems.Add("the last section scrolled to $($scroll.Current.VerticalScrollPercent) %") }
            if ($ScreenshotDirectory) { Save-Screenshot 'nouveautes-section' $dialog }
        }
        $more = $null
        foreach ($index in 0..($Sections.Count - 1)) { if (-not $more) { $more = Get-DialogPart $dialog "changelog_more_$index" } }
        if (-not $more) { $problems.Add('no section has « et N autres »') }
        else {
            $name = $more.Current.Name
            $id = $more.Current.AutomationId
            $others = if ($name -match '\d+') { [int]$Matches[0] } else { 1 }
            $before = @(Get-ChangelogText $dialog).Count
            Invoke-Element $more
            Start-Sleep -Milliseconds 500
            $after = @(Get-ChangelogText $dialog).Count
            # Its own text goes, its others' headlines come.
            if ($after - $before -ne $others - 1) { $problems.Add("« $name » added $($after - $before + 1) headlines") }
            if (Get-DialogPart $dialog $id) { $problems.Add("« $name » is still there") }
        }
        Invoke-Element (Get-DialogPart $dialog 'dialog_cancel')
        if (-not (Test-ChangelogClosed $window)) { $problems.Add("Fermer didn't close it") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }
}

function Test-Density {
    # Densité, in a session of its own from no apparence.json: each density sets the grids' rows and the search row,
    # not the text, and is saved (Normale, the default, isn't); Texte's Par défaut leaves it; it comes back after a
    # restart, and a density that isn't offered opens on Normale. Sizes on screen are compared to Normale's (40 px
    # rows, a 38 px search row), so the screen's scaling doesn't matter.
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'
    $normal = Get-DensityMeasure
    $scale = $normal.Row / 40
    $densities = @{ Id = 'compact'; Name = 'Compacte'; Row = 32; Search = 32 }, @{ Id = 'airy'; Name = 'Aérée'; Row = 48; Search = 44 },
                 @{ Id = 'normal'; Name = ''; Row = 40; Search = 38 }

    Invoke-Check 'Paramètres › Apparence › Densité: each density sets the rows and the search row, not the text, and is saved' {
        param($problems)
        $settingsWindow = Open-SettingsSection 'appearance'
        if ((Get-DensityChoice $settingsWindow) -ne 'density_normal') { $problems.Add("at first, the density chosen is '$(Get-DensityChoice $settingsWindow)'") }
        foreach ($density in $densities) {
            Invoke-Element (Get-DialogPart $settingsWindow "density_$($density.Id)")
            Start-Sleep -Milliseconds 500
            $shown = Get-DensityMeasure
            if ([Math]::Abs($shown.Row - $density.Row * $scale) -gt 2) { $problems.Add("$($density.Id): the rows are $($shown.Row) high, expected $($density.Row * $scale)") }
            if ([Math]::Abs($shown.Search - $density.Search * $scale) -gt 2) { $problems.Add("$($density.Id): Rechercher is $($shown.Search) high, expected $($density.Search * $scale)") }
            if ([Math]::Abs($shown.Text - $normal.Text) -gt 1) { $problems.Add("$($density.Id): the text is $($shown.Text) high, $($normal.Text) before") }
            if ((Get-DensityChoice $settingsWindow) -ne "density_$($density.Id)") { $problems.Add("$($density.Id): the density toggled on is '$(Get-DensityChoice $settingsWindow)'") }
            $saved = Read-SavedSetting 'apparence.json'
            $savedDensity = if ($saved -and $saved.PSObject.Properties['Density']) { $saved.Density } else { '' }
            if ($savedDensity -ne $density.Name) { $problems.Add("$($density.Id): apparence.json holds Density '$savedDensity'") }
            if ($ScreenshotDirectory) { Save-Screenshot "densite-$($density.Id)" }
        }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check "Paramètres › Apparence › Densité: Texte's Par défaut leaves it as it is" {
        param($problems)
        $settingsWindow = Open-SettingsSection 'appearance'
        Invoke-Element (Get-DialogPart $settingsWindow 'density_airy')
        Invoke-Element (Get-DialogPart $settingsWindow 'text_size_large')
        Start-Sleep -Milliseconds 500
        Invoke-Element (Get-DialogPart $settingsWindow 'text_reset')
        Start-Sleep -Milliseconds 500
        $saved = Read-SavedSetting 'apparence.json'
        if ($saved.Density -ne 'Aérée' -or $saved.PSObject.Properties['TextScale']) { $problems.Add("after Par défaut, apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)") }
        if ((Get-DensityChoice $settingsWindow) -ne 'density_airy') { $problems.Add("after Par défaut, the density toggled on is '$(Get-DensityChoice $settingsWindow)'") }
        $shown = Get-DensityMeasure
        if ([Math]::Abs($shown.Row - 48 * $scale) -gt 2) { $problems.Add("after Par défaut, the rows are $($shown.Row) high, expected $(48 * $scale)") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check 'Paramètres › Apparence › Densité: Aérée comes back after a restart, on both pages' {
        param($problems)
        Stop-App
        Start-App -KeepSettings
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-0'
        $shown = Get-DensityMeasure
        if ([Math]::Abs($shown.Row - 48 * $scale) -gt 2) { $problems.Add("after the restart, the rows are $($shown.Row) high, expected $(48 * $scale)") }
        Show-UserPage
        $null = Invoke-UserSearch 'demo.local' 'Nom, identifiant ou courriel' 'bert'
        $users = Get-DensityMeasure 'user_grid' 'user_search'
        if ([Math]::Abs($users.Row - 48 * $scale) -gt 2) { $problems.Add("on Utilisateurs, the rows are $($users.Row) high, expected $(48 * $scale)") }
        if ([Math]::Abs($users.Search - 44 * $scale) -gt 2) { $problems.Add("on Utilisateurs, Rechercher is $($users.Search) high, expected $(44 * $scale)") }
        Invoke-Element (Find-Control 'tab_computers')
        Start-Sleep -Milliseconds 300
        $settingsWindow = Open-SettingsSection 'appearance'
        if ((Get-DensityChoice $settingsWindow) -ne 'density_airy') { $problems.Add("after the restart, the density toggled on is '$(Get-DensityChoice $settingsWindow)'") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    }

    Invoke-Check "Paramètres › Apparence › Densité: a density that isn't offered opens on Normale, and isn't rewritten" {
        param($problems)
        $settings = '{ "Theme": "Clair", "Density": "Énorme" }'
        Restart-App $settings
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-0'
        $shown = Get-DensityMeasure
        if ([Math]::Abs($shown.Row - $normal.Row) -gt 1) { $problems.Add("the rows are $($shown.Row) high, $($normal.Row) at Normale") }
        $settingsWindow = Open-SettingsSection 'appearance'
        if ((Get-DensityChoice $settingsWindow) -ne 'density_normal') { $problems.Add("the density toggled on is '$(Get-DensityChoice $settingsWindow)'") }
        $settingsWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        $saved = (Get-Content $appearanceFile -Raw -Encoding utf8).Trim()
        if ($saved -ne $settings) { $problems.Add("apparence.json was rewritten: $saved") }
    }
}

function Get-HolderWindow($Element) {
    # The window that holds an element: the main window, or a popup (the Apparence menu is a window of its own).
    $holder = $Element
    while ($holder -and -not $holder.Current.NativeWindowHandle) { $holder = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($holder) }
    $holder
}

function Invoke-Element($Element) {
    # Buttons have the Invoke pattern. Toggle buttons (the tint choices) only have Toggle, which flips them
    # without a click, and Repère applies a choice on its click: they get the keyboard focus and Space instead, posted
    # to the window that holds them (Paramètres).
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        return
    }
    $Element.SetFocus()
    Send-Key 0x20 (Get-HolderWindow $Element)
}

function Find-PopupControl([string]$AutomationId, [string]$Opener) {
    # A control of a window Repère opens from a button (Paramètres, whose Apparence section holds the theme gallery and
    # editor): it can take a moment to show. It's opened with its button, and again now and then if the control
    # doesn't show up.
    $condition = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId)
    for ($i = 0; $i -lt 24; $i++) {
        foreach ($top in Get-AppWindow) {
            $found = $top.FindFirst($Descendants, $condition)
            if ($found) { return $found }
        }
        if ($i % 8 -eq 0) { Invoke-Element (Find-Control $Opener) }
        Start-Sleep -Milliseconds 250
    }
    throw "'$AutomationId' not found after opening '$Opener'."
}

function Find-ShownPopupControl([string]$AutomationId) {
    # A control of an open popup, without opening or closing it: $null when it isn't shown, since WPF leaves
    # collapsed controls out of UI Automation.
    $condition = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId)
    foreach ($top in Get-AppWindow) {
        $found = $top.FindFirst($Descendants, $condition)
        if ($found -and -not $found.Current.IsOffscreen) { return $found }
    }
}

function Find-PopupElement([string]$AutomationId) {
    # A control of an open window, in view or scrolled out of it (the theme editor's colors run past the bottom), after
    # a moment for it to show: $null when it's collapsed, since WPF leaves collapsed controls out of UI Automation.
    $condition = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, $AutomationId)
    for ($i = 0; $i -lt 4; $i++) {
        foreach ($top in Get-AppWindow) {
            $found = $top.FindFirst($Descendants, $condition)
            if ($found) { return $found }
        }
        Start-Sleep -Milliseconds 250
    }
}

function Wait-ShownPopupControl([string]$AutomationId) {
    # Find-ShownPopupControl, waiting a few seconds for the control to show.
    for ($i = 0; $i -lt 20; $i++) {
        $found = Find-ShownPopupControl $AutomationId
        if ($found) { return $found }
        Start-Sleep -Milliseconds 250
    }
}

function Invoke-PopupControl([string]$AutomationId) {
    Invoke-Element (Find-PopupControl $AutomationId 'settings')
}

function Get-PopupText([string]$AutomationId) {
    (Find-PopupControl $AutomationId 'settings').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
}

function Set-PopupText([string]$AutomationId, [string]$Text) {
    (Find-PopupControl $AutomationId 'settings').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
}

function Get-SliderValue([string]$AutomationId) {
    (Find-PopupControl $AutomationId 'settings').GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value
}

function Set-SliderValue([string]$AutomationId, [double]$Value) {
    (Find-PopupControl $AutomationId 'settings').GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue($Value)
}

function Get-ToggleState([string]$AutomationId) {
    (Find-PopupControl $AutomationId 'settings').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
}

function Test-GalleryShown {
    # The menu's two pages are panels, which UI Automation doesn't list: Créer un thème stands for the gallery, and
    # Enregistrer for the editor. Waits a few seconds for the gallery, without opening it.
    [bool](Wait-ShownPopupControl 'create_theme')
}

function Open-Editor([string]$Button) {
    # Créer un thème, theme_copy or theme_edit, then waits for the editor.
    Invoke-PopupControl $Button
    if (-not (Wait-ShownPopupControl 'editor_save')) { throw "The theme editor didn't open after '$Button'." }
}

function Close-ColorPicker {
    # Échap, posted to the picker's own window (a popup): it closes, its color kept.
    $condition = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'picker_hex')
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    foreach ($top in Get-AppWindow) {
        $box = $top.FindFirst($Descendants, $condition)
        if (-not $box) { continue }
        $box.SetFocus()
        $popup = $box
        while ($popup -and $popup.Current.ControlType -ne [System.Windows.Automation.ControlType]::Window) { $popup = $walker.GetParent($popup) }
        if ($popup) { Send-Key 0x1B $popup }
    }
}

function Get-EditorState {
    # What the theme editor shows, on one line: title | name | color | tint | whether Supprimer is there.
    $tint = @(foreach ($id in 'editor_tint_neutre', 'editor_tint_teinte', 'editor_tint_intense') {
        if ((Get-ToggleState $id) -eq 'On') { (Find-PopupControl $id 'settings').Current.Name }
    }) -join '+'
    $delete = if (Find-ShownPopupControl 'editor_delete') { 'Supprimer' } else { 'sans Supprimer' }
    '{0} | {1} | {2} | {3} | {4}' -f (Find-PopupControl 'editor_title' 'settings').Current.Name, (Get-PopupText 'editor_name'), (Get-PopupText 'editor_accent'), $tint, $delete
}

function Get-ThemeRow {
    # The rows of the list of themes, by name, as UI Automation lists them once it's been opened. The rows of the user's
    # own themes follow « Mes thèmes ».
    $list = Find-PopupControl 'theme_list' 'settings'
    $expand = $list.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $expand.Expand()
    Start-Sleep -Milliseconds 300
    $listItem = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    @($list.FindAll($Descendants, $listItem) | ForEach-Object { $_.Current.Name })
    $expand.Collapse()
    Start-Sleep -Milliseconds 200
}

function Find-ThemeRow($List, [string]$Name) {
    # A row of the open list of themes.
    $byName = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, $Name),
        [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem))
    for ($i = 0; $i -lt 20; $i++) {
        $row = $List.FindFirst($Descendants, $byName)
        if ($row) { return $row }
        Start-Sleep -Milliseconds 150
    }
    throw "'$Name' not found in the list of themes."
}

function Select-Theme([string]$Name) {
    # Picks a theme in the list, as a click on its row does.
    $list = Find-PopupControl 'theme_list' 'settings'
    $expand = $list.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $expand.Expand()
    (Find-ThemeRow $list $Name).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    if ($expand.Current.ExpandCollapseState -eq 'Expanded') { $expand.Collapse() }
    for ($i = 0; $i -lt 20 -and (Get-ChosenScheme) -ne $Name; $i++) { Start-Sleep -Milliseconds 100 }
}

function Wait-WindowBackground($Target, [string]$Color) {
    # The color drawn near a window's bottom right corner, past its content, its theme's background: as #RRGGBB, once
    # it's $Color, or what it is after a few seconds.
    Initialize-WindowImage
    for ($i = 0; $i -lt 30; $i++) {
        $image = Get-WindowImage $Target
        $pixel = $image.Bitmap.GetPixel($image.Bitmap.Width - 24, $image.Bitmap.Height - 24)
        $image.Bitmap.Dispose()
        $drawn = '#{0:X2}{1:X2}{2:X2}' -f $pixel.R, $pixel.G, $pixel.B
        if ($drawn -eq $Color) { break }
        Start-Sleep -Milliseconds 100
    }
    $drawn
}

function Get-ChosenScheme {
    # The theme selected in the list, by name.
    $list = Find-PopupControl 'theme_list' 'settings'
    $selection = $list.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()
    if ($selection.Count) { $selection[0].Current.Name }
}

function Get-ChosenMode {
    # The mode toggle that's on (one, normally): theme_system, theme_light or theme_dark.
    $null = Find-PopupControl 'create_theme' 'settings'
    'theme_system', 'theme_light', 'theme_dark' | Where-Object { (Get-ToggleState $_) -eq 'On' }
}

function Get-CustomThemeCard {
    # The rows of the user's own themes, in order, by name.
    $rows = @(Get-ThemeRow)
    $heading = [array]::IndexOf($rows, 'Mes thèmes')
    if ($heading -ge 0) { $rows[($heading + 1)..($rows.Count - 1)] }
}

function Read-SavedAppearance {
    # apparence.json's settings, or $null when there's none.
    try { Get-Content $appearanceFile -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json } catch { $null }
}

function Wait-SavedAppearance([scriptblock]$Done) {
    # apparence.json once $Done (given its settings) is true, or what it holds after a few seconds.
    $saved = $null
    for ($i = 0; $i -lt 20; $i++) {
        $saved = Read-SavedAppearance
        if ($saved -and (& $Done $saved)) { break }
        Start-Sleep -Milliseconds 250
    }
    $saved
}

function Format-SavedTheme($Saved) {
    # The themes of one's own in apparence.json, on one line: Id Name Accent Tint | ...
    @($Saved.CustomThemes | ForEach-Object { "$($_.Id) $($_.Name) $($_.Accent) $($_.Tint)" }) -join ' | '
}

function Restart-App([string]$Settings) {
    # Closes Repère and starts it again, after writing $Settings to apparence.json when there are some.
    Stop-App
    if ($Settings) { Set-Content $appearanceFile $Settings -Encoding utf8 }
    Start-App
}

function Test-ActionBar {
    # The buttons above the search follow the selection like the right-click menu. Nothing here changes the fake AD:
    # act_toggle is only clicked where every row is enabled (so it can only ask to disable), then cancelled.
    $actionButtons = 'act_rdp', 'act_remote_more', 'act_ping', 'act_specs', 'act_toggle', 'act_edit', 'act_move', 'act_groups', 'act_bitlocker', 'act_laps', 'act_copy', 'act_remove'
    Select-Domain 'demo.local'
    Invoke-PrefixSearch 'ORD-0'

    Invoke-Check 'Action bar: every action is disabled without a selection' {
        param($problems)
        Clear-ResultSelection
        $selection = (Find-Control 'selection_text').Current.Name
        if ($selection -ne 'Aucune sélection') { $problems.Add("selection text is '$selection'") }
        foreach ($id in $actionButtons) {
            if ((Find-Control $id).Current.IsEnabled) { $problems.Add("$id is enabled") }
        }
    }

    Invoke-Check 'Action bar: an enabled computer offers every action, and Désactiver…' {
        param($problems)
        Select-ResultRow 'ORD-01'
        foreach ($id in $actionButtons) {
            if (-not (Find-Control $id).Current.IsEnabled) { $problems.Add("$id is disabled") }
        }
        $toggleText = (Find-Control 'act_toggle_text').Current.Name
        if ($toggleText -ne 'Désactiver…') { $problems.Add("the toggle button reads '$toggleText'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'actions-1-selection' }
    }

    Invoke-Check 'Action bar: a disabled computer turns Désactiver… into Activer' {
        param($problems)
        # Only read: clicking it would enable ORD-07 without confirmation.
        Select-ResultRow 'ORD-07'
        $toggleText = (Find-Control 'act_toggle_text').Current.Name
        if ($toggleText -ne 'Activer') { $problems.Add("the toggle button reads '$toggleText'") }
        if (-not (Find-Control 'act_toggle').Current.IsEnabled) { $problems.Add('act_toggle is disabled') }
    }

    Invoke-Check 'Action bar: Vérifier en ligne checks the selected computer' {
        param($problems)
        Select-ResultRow 'ORD-01'
        Invoke-Element (Find-Control 'act_ping')
        $notice = Wait-ActionNotice 'En ligne : ✔ ORD-01 : en ligne (ping) — 10.0.1.11'
        if ($notice -ne 'En ligne : ✔ ORD-01 : en ligne (ping) — 10.0.1.11') { $problems.Add("the status bar says '$notice'") }
        if ((Get-ResultCell 'ORD-01' 7) -ne '✔ 10.0.1.11') { $problems.Add("the En ligne cell says '$(Get-ResultCell 'ORD-01' 7)'") }
    }

    Invoke-Check 'Action bar: Mot de passe LAPS shows the selected computer''s password' {
        param($problems)
        Select-ResultRow 'ORD-04'
        Invoke-Element (Find-Control 'act_laps')
        $dialog = Wait-Dialog 'Mot de passe LAPS'
        $message = Get-DialogText $dialog
        if ($message -notlike '*ORD-04 — LAPS hérité, expire le *') { $problems.Add("the dialog says '$message'") }
        Close-Dialog $dialog 'dialog_cancel'
    }

    # ORD-02, ORD-06 and ORD-10 ("Salle ...") are all enabled.
    Invoke-PrefixSearch '' 'salle'
    Invoke-Check 'Action bar: Désactiver… asks first, and Annuler changes nothing' {
        param($problems)
        Select-ResultRow 'ORD-06'
        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-Element (Find-Control 'act_toggle')
        $dialog = Wait-Dialog 'Désactiver'
        $message = Get-DialogText $dialog
        if ($message -notlike 'Désactiver ORD-06 ?*') { $problems.Add("the dialog says '$message'") }
        Close-Dialog $dialog 'dialog_cancel'
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -like '*-ADAccount') { $problems.Add('the account was changed') }
        if ((Get-ResultCell 'ORD-06' 0) -ne 'Activé') { $problems.Add("ORD-06 shows '$(Get-ResultCell 'ORD-06' 0)'") }
    }
}

function Wait-ResultsCount([string]$Expected) {
    # After the filter box changes, Repère shows the rows, updates the action bar, then the label: returns the label
    # once it reads $Expected, or after a few seconds.
    for ($i = 0; $i -lt 20; $i++) {
        $label = (Find-Control 'results_count').Current.Name
        if ($label -eq $Expected) { break }
        Start-Sleep -Milliseconds 250
    }
    $label
}

function Test-NotFoundWidth {
    # Liste de noms: as many names not found as fit on the banner's line, then how many more; fewer once the window is
    # narrower (#190). The banner's text is its whole text, not what the ellipsis would leave.
    Invoke-Check 'Liste de noms lists as many names not found as fit, then how many more, fewer in a narrower window' {
        param($problems)
        $names = @(1..40 | ForEach-Object { 'ORD-{0}' -f (900 + $_) })
        $before = $window.Current.BoundingRectangle
        try {
            Set-WindowState 'Normal' 1400 800
            Select-Domain 'demo.local'
            Select-SearchType 'Description contient'
            Reset-AdvancedSearch
            Set-Text 'prefix' ''
            Set-Text 'search_term' ($names -join ' ')
            Select-SearchType 'Liste de noms'
            Invoke-Search
            $shown = {
                param([string]$Width)
                $said = (Find-Control 'results_not_found_text').Current.Name
                if ($said -notmatch '^40 introuvables : (?<list>.+) \(\+(?<more>\d+)\)$') { $problems.Add("$Width, the banner says '$said'"); return 0 }
                $listed = @($Matches.list -split ', ')
                $first = @($names | Select-Object -First $listed.Count)
                if (($listed -join ' ') -ne ($first -join ' ') -or $listed.Count + [int]$Matches.more -ne 40) { $problems.Add("$Width, the banner says '$said'") }
                $listed.Count
            }
            $wide = & $shown 'wide'
            Set-WindowState 'Normal' 1000 800
            $narrow = & $shown 'narrower'
            if ($narrow -lt 1 -or $narrow -ge $wide) { $problems.Add("$wide names shown in the wide window, $narrow in the narrower one") }
        }
        finally { Set-WindowState 'Normal' ([int]$before.Width) ([int]$before.Height) }
    }
}

function Test-FilterBox {
    Invoke-Check 'The filter box narrows the results without a new search' {
        param($problems)
        Invoke-PrefixSearch 'ORD'
        $queriesBefore = @(Get-LoggedQuery).Count
        try {
            Set-Text 'filter' 'salle'
            $label = Wait-ResultsCount '12 ordinateurs · 3 affichés'
            if ($label -ne '12 ordinateurs · 3 affichés') { $problems.Add("filtered label is '$label'") }
            $shown = (Get-ResultName) -join ', '
            if ($shown -ne 'ORD-02, ORD-06, ORD-10') { $problems.Add("filtered rows: $shown") }
            if ($ScreenshotDirectory) { Save-Screenshot 'filtre' }
        }
        finally {
            # Emptied even after a failure, since the filter also applies to the next searches.
            Set-Text 'filter' ''
        }
        $label = Wait-ResultsCount '12 ordinateurs'
        if ($label -ne '12 ordinateurs') { $problems.Add("label is '$label' once the filter is emptied, expected '12 ordinateurs'") }
        if (Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer') { $problems.Add('the filter searched AD again') }
    }
}

function Get-EmptyGrid {
    # What the empty grid says, its criteria line, and the links it offers, as « text | criteria | links ».
    $criteria = Find-ShownControl 'grid_empty_criteria'
    $links = @(foreach ($id in 'grid_empty_all_domains_link', 'grid_empty_no_advanced_link', 'grid_empty_clear_filter_link') {
        $link = Find-ShownControl $id
        if ($link) { $link.Current.Name }
    })
    "$((Find-Control 'grid_empty_text').Current.Name) | $(if ($criteria) { $criteria.Current.Name }) | $($links -join ', ')"
}

function Invoke-EmptyLink([string]$AutomationId) {
    # A link of the empty grid, then the search it starts, if any.
    Invoke-Element (Find-Control $AutomationId)
    Start-Sleep -Milliseconds 300
    Wait-SearchEnd
}

function Test-EmptySearch {
    # A search that finds nothing says what it looked for and where, and offers the searches to try next (#193).
    Invoke-Check 'Ordinateurs: a search that finds nothing names it and its domain, and offers every domain' {
        param($problems)
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'zzz'
        $empty = Get-EmptyGrid
        $expected = 'Aucun ordinateur trouvé dans demo.local. | Nom contient « zzz » | Chercher dans tous les domaines'
        if ($empty -ne $expected) { $problems.Add("the empty grid says '$empty', expected '$expected'") }

        $queriesBefore = @(Get-LoggedQuery).Count
        Invoke-EmptyLink 'grid_empty_all_domains_link'
        $servers = (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object { $_.Server }) | Sort-Object) -join ', '
        if ($servers -ne 'demo.local, nord.demo.local') { $problems.Add("Chercher dans tous les domaines searched: $servers") }
        $domain = Get-ComboText 'domain'
        if ($domain -ne 'Tous les domaines') { $problems.Add("after it, the domain list shows '$domain'") }
        $empty = Get-EmptyGrid
        $expected = 'Aucun ordinateur trouvé dans tous les domaines. | Nom contient « zzz » | '
        if ($empty -ne $expected) { $problems.Add("then the empty grid says '$empty', expected '$expected'") }
        Select-Domain 'demo.local'
    }

    Invoke-Check 'Ordinateurs: a search the advanced criteria leave empty names them, and searches again without them' {
        param($problems)
        Select-Domain 'demo.local'
        Select-SearchType 'Description contient'
        Set-AdvancedSearch @{ State = 'disabled'; System = 'zzz' }
        Set-Text 'prefix' 'ORD'
        Set-Text 'search_term' "d'accueil"
        Invoke-Search
        $empty = Get-EmptyGrid
        $expected = "Aucun ordinateur trouvé dans demo.local. | Nom contient « ORD » · Description contient « d'accueil » · désactivés · système « zzz » | Chercher dans tous les domaines, Retirer les critères avancés"
        if ($empty -ne $expected) { $problems.Add("the empty grid says '$empty', expected '$expected'") }

        # Without its criteria, ORD-01 « Bureau d'accueil » is found. Typed since, the link searches what found
        # nothing, not what the boxes hold.
        Set-Text 'prefix' 'autre'
        Invoke-EmptyLink 'grid_empty_no_advanced_link'
        $state = "$((Find-Control 'prefix').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value) | $((Find-Control 'advanced_text').Current.Name)"
        if ($state -ne 'ORD | Avancée') { $problems.Add("after Retirer les critères avancés, the name and Avancée say '$state'") }
        $rows = (Get-ResultName) -join ', '
        if ($rows -ne 'ORD-01') { $problems.Add("without the criteria, rows: $rows") }
        Reset-AdvancedSearch
    }

    Invoke-Check 'Ordinateurs: a filter that hides every row says so, and Effacer le filtre shows them again' {
        param($problems)
        Invoke-PrefixSearch 'ORD'
        try {
            Set-Text 'filter' 'zzzz'
            $null = Wait-ResultsCount '12 ordinateurs · 0 affiché'
            $empty = Get-EmptyGrid
            $expected = 'Aucun ordinateur ne correspond au filtre. |  | Effacer le filtre'
            if ($empty -ne $expected) { $problems.Add("the empty grid says '$empty', expected '$expected'") }
            Invoke-EmptyLink 'grid_empty_clear_filter_link'
            $label = Wait-ResultsCount '12 ordinateurs'
            if ($label -ne '12 ordinateurs') { $problems.Add("after Effacer le filtre, the label is '$label'") }
            $filter = (Find-Control 'filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            if ($filter) { $problems.Add("after Effacer le filtre, the filter box holds '$filter'") }
        }
        finally { Set-Text 'filter' '' }
    }
}

function Test-ParallelSearch {
    # Run with demo.local and nord.demo.local both taking 2 s per call: one after the other, they would take over 4 s.
    Invoke-Check 'Tous les domaines searches the domains in parallel' {
        param($problems)
        $queriesBefore = @(Get-LoggedQuery).Count
        Select-Domain 'Tous les domaines'
        Invoke-PrefixSearch 'ORD-01'
        $label = (Find-Control 'results_count').Current.Name
        if ($label -ne '2 ordinateurs') { $problems.Add("label is '$label', expected '2 ordinateurs'") }
        $shown = (@(Get-ResultRow | ForEach-Object { "$($_[1]) in $($_[5])" }) | Sort-Object) -join ', '
        if ($shown -ne 'ORD-01 in demo.local, ORD-01 in nord.demo.local') { $problems.Add("rows shown: $shown") }
        $duration = Get-SearchDuration
        if ($null -eq $duration -or $duration -ge 3500) {
            $problems.Add("search time reads '$((Find-Control 'search_time').Current.Name)', expected under 3 500 ms")
        }
        $servers = (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object Server) | Sort-Object) -join ', '
        if ($servers -ne ($fakeDomains -join ', ')) { $problems.Add("searches sent to: $servers; expected $($fakeDomains -join ', ')") }
        if ($ScreenshotDirectory) { Save-Screenshot 'recherche-parallele' }
    }

    Invoke-Check 'Mot de passe LAPS reads in the background: the window stays usable, and asking twice opens one window' {
        param($problems)
        Select-ResultRow 'ORD-01'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Element (Find-Control 'act_laps')
        Invoke-Element (Find-Control 'act_laps')
        $count = (Find-Control 'results_count').Current.Name
        if ($watch.ElapsedMilliseconds -ge 1500 -or $count -ne '2 ordinateurs') { $problems.Add("the window answered after $($watch.ElapsedMilliseconds) ms, its count reading '$count'") }
        if (-not (Test-WindowEnabled) -or @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Mot de passe LAPS' }).Count) { $problems.Add('the LAPS window opened before AD answered') }
        $dialog = Wait-Dialog 'Mot de passe LAPS'
        Start-Sleep -Milliseconds 1500
        $open = @(Get-AppWindow | Where-Object { $_.Current.Name -eq 'Mot de passe LAPS' }).Count
        if ($open -ne 1) { $problems.Add("$open LAPS windows") }
        if (@(Get-LapsSection $dialog)[0] -notlike 'ORD-01 — Windows LAPS*') { $problems.Add("its card reads: $(@(Get-LapsSection $dialog)[0])") }
        Close-Dialog $dialog 'dialog_cancel'
    }
}

function Test-SearchCancel {
    # Run with nord.demo.local taking 8 s per call, demo.local answering at once. No check waits for nord to answer:
    # each one cancels its search, and then must be done well before the 8 s.
    Invoke-Check 'During a search the window stays usable, and the label names the domain still searched' {
        param($problems)
        if (Find-ShownControl 'cancel_search') { $problems.Add('Annuler is shown before any search') }
        # Rows from a previous search, which the filter box then works on.
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-1'
        $watch = Start-SlowSearch 'Tous les domaines' 'ORD-01'
        try {
            if ((Find-Control 'button').Current.IsEnabled) { $problems.Add('Rechercher is enabled during the search') }
            # Typed during the search: the window answers at once, not once the search is done.
            $typing = [System.Diagnostics.Stopwatch]::StartNew()
            Set-Text 'filter' 'salle'
            $typed = (Find-Control 'filter').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            Set-Text 'filter' ''
            $typing.Stop()
            if ($typed -ne 'salle') { $problems.Add("the filter box holds '$typed', expected 'salle'") }
            if ($typing.ElapsedMilliseconds -ge 1000) { $problems.Add("the filter box took $($typing.ElapsedMilliseconds) ms to answer") }
            # Still under a second: just « Recherche… », even after the filter box changed.
            $label = (Find-Control 'results_count').Current.Name
            if ($watch.ElapsedMilliseconds -lt 950 -and $label -ne 'Recherche…') { $problems.Add("label is '$label' during the first second, expected 'Recherche…'") }
            # After a second, the domains still searched: demo.local has answered, nord.demo.local hasn't.
            Wait-Elapsed $watch 1500
            $expected = 'Recherche… (en attente : nord.demo.local)'
            for ($i = 0; $i -lt 10 -and ($label = (Find-Control 'results_count').Current.Name) -ne $expected; $i++) { Start-Sleep -Milliseconds 100 }
            if ($label -ne $expected) { $problems.Add("label is '$label' after 1.5 s, expected '$expected'") }
            if ($ScreenshotDirectory) { Save-Screenshot 'recherche-en-cours' }
            if (-not (Test-SearchRunning)) { $problems.Add("the search ended before nord.demo.local's 8 s") }
        }
        finally {
            Set-Text 'filter' ''
            Stop-RunningSearch
        }
    }

    # Annuler and Échap stop nord.demo.local and show what demo.local found.
    $cancels = @(
        @{ Name = 'Annuler shows what the other domains found and names the cancelled one'
           Cancel = { (Find-Control 'cancel_search').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } }
        @{ Name = 'Échap cancels the search too'
           Cancel = { (Find-Control 'prefix').SetFocus(); Send-Key 0x1B } }
    )
    foreach ($cancel in $cancels) {
        Invoke-Check $cancel.Name {
            param($problems)
            $queriesBefore = @(Get-LoggedQuery).Count
            $watch = Start-SlowSearch 'Tous les domaines' 'ORD-01'
            try {
                Wait-Elapsed $watch 1000
                & $cancel.Cancel
                Wait-SearchEnd 5
                $ended = $watch.ElapsedMilliseconds
                if ($ended -ge 4000) { $problems.Add("the search ended $ended ms after the click, expected well before nord.demo.local's 8 s") }
                $label = (Find-Control 'results_count').Current.Name
                if ($label -ne '1 ordinateur (annulé : nord.demo.local)') { $problems.Add("label is '$label', expected '1 ordinateur (annulé : nord.demo.local)'") }
                $tooltip = (Find-Control 'results_count').Current.HelpText
                if ($tooltip -ne 'nord.demo.local : recherche annulée') { $problems.Add("the label's tooltip is '$tooltip'") }
                $shown = (@(Get-ResultRow | ForEach-Object { "$($_[1]) in $($_[5])" }) | Sort-Object) -join ', '
                if ($shown -ne 'ORD-01 in demo.local') { $problems.Add("rows shown: $shown; expected demo.local's ORD-01") }
                if (-not (Find-Control 'button').Current.IsEnabled) { $problems.Add('Rechercher is still disabled') }
                if (Find-ShownControl 'cancel_search') { $problems.Add('Annuler is still shown') }
                $servers = (@(Get-LoggedQuery | Select-Object -Skip $queriesBefore | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object Server) | Sort-Object) -join ', '
                if ($servers -ne ($fakeDomains -join ', ')) { $problems.Add("searches sent to: $servers; expected $($fakeDomains -join ', ')") }
                if ($ScreenshotDirectory -and $cancel.Name -like 'Annuler*') { Save-Screenshot 'recherche-annulee' }
            }
            finally {
                Stop-RunningSearch
            }
        }
    }

    Invoke-Check 'Cancelled before any domain answered, the previous results stay' {
        # Also: the waiting label names the domain of a single-domain search.
        param($problems)
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-1'
        $label = (Find-Control 'results_count').Current.Name
        if ($label -ne '3 ordinateurs') { $problems.Add("the first search shows '$label', expected '3 ordinateurs'"); return }
        $watch = Start-SlowSearch 'nord.demo.local' 'ORD'
        try {
            # A single domain is named too once it takes over a second.
            Wait-Elapsed $watch 1500
            $expected = 'Recherche… (en attente : nord.demo.local)'
            for ($i = 0; $i -lt 10 -and ($label = (Find-Control 'results_count').Current.Name) -ne $expected; $i++) { Start-Sleep -Milliseconds 100 }
            if ($label -ne $expected) { $problems.Add("label is '$label' after 1.5 s, expected '$expected'") }
            (Find-Control 'cancel_search').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Wait-SearchEnd 5
            $label = (Find-Control 'results_count').Current.Name
            if ($label -ne '3 ordinateurs') { $problems.Add("label is '$label', expected the previous '3 ordinateurs'") }
            $shown = (Get-ResultName) -join ', '
            if ($shown -ne 'ORD-10, ORD-11, ORD-12') { $problems.Add("rows shown: $shown; expected the previous ORD-10, ORD-11, ORD-12") }
            $scope = (Find-Control 'results_scope').Current.Name
            if ($scope -ne 'dans demo.local') { $problems.Add("scope reads '$scope', expected the previous 'dans demo.local'") }
            $time = (Find-Control 'search_time').Current.Name
            if ($time -ne 'recherche annulée') { $problems.Add("search time reads '$time', expected 'recherche annulée'") }
        }
        finally {
            Stop-RunningSearch
        }
    }

    Invoke-Check 'A search right after a cancel works, at full speed' {
        param($problems)
        $watch = Start-SlowSearch 'nord.demo.local' 'ORD'
        try {
            Wait-Elapsed $watch 300
            (Find-Control 'cancel_search').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Wait-SearchEnd 5
        }
        finally {
            Stop-RunningSearch
        }
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD-0'
        $label = (Find-Control 'results_count').Current.Name
        if ($label -ne '9 ordinateurs') { $problems.Add("label is '$label', expected '9 ordinateurs'") }
        $duration = Get-SearchDuration
        if ($null -eq $duration -or $duration -ge 1500) {
            $problems.Add("search time reads '$((Find-Control 'search_time').Current.Name)', expected under 1 500 ms")
        }
    }

    Invoke-Check 'Utilisateurs: Annuler stops the domain still searched, and shows those that answered' {
        param($problems)
        Invoke-Element (Find-Control 'tab_users')
        Start-Sleep -Milliseconds 500
        if (Find-ShownControl 'user_cancel') { $problems.Add('Annuler is shown before any search') }
        Select-ComboItem 'user_domain' 'Tous les domaines'
        Select-ComboItem 'user_search_type' 'Nom, identifiant ou courriel'
        (Find-Control 'user_query').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('bert')
        Invoke-Element (Find-Control 'user_search')
        Start-Sleep -Milliseconds 800
        $cancel = Find-ShownControl 'user_cancel'
        if (-not $cancel) { throw 'Annuler is not shown during the search' }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Element $cancel
        for ($i = 0; $i -lt 40 -and -not (Find-Control 'user_search').Current.IsEnabled; $i++) { Start-Sleep -Milliseconds 100 }
        if ($watch.ElapsedMilliseconds -ge 3000) { $problems.Add("stopped after $($watch.ElapsedMilliseconds) ms") }
        if (Find-ShownControl 'user_cancel') { $problems.Add('Annuler is still shown') }
        $count = (Find-Control 'user_count').Current.Name
        if ($count -notlike '*(erreur : nord.demo.local)*') { $problems.Add("the count says '$count'") }
        if (-not @(Get-DialogRow (Find-Control 'user_grid')).Count) { $problems.Add("demo.local's rows aren't shown") }
    }
}

function Test-GalleryKept {
    # After a change of mode: Fluent redraws the windows, Paramètres included. A moment for that, then whether the
    # gallery is still shown, without opening Paramètres (Find-PopupControl would).
    Start-Sleep -Milliseconds 1000
    Test-GalleryShown
}

function Test-Appearance {
    # Restarts the app, so it runs last. The settings go to the test's own APPDATA ($appearanceFile), still empty here:
    # nothing has been saved yet. The checks follow each other: a theme of one's own is created, kept over a restart,
    # renamed, then deleted, and themes and modes are picked. Then Repère is started with settings from older versions,
    # and with as many themes of one's own as it allows.
    $presetNames = 'Repère', 'Graphite', 'Marine', 'Lagon', 'Mousse', 'Terracotta', 'Framboise', 'Sable', 'Contraste élevé'
    Invoke-Check 'Apparence: at first start the mode follows Windows and nothing is saved' {
        param($problems)
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_system') { $problems.Add("mode: '$mode', expected theme_system") }
        if (Test-Path $appearanceFile) { $problems.Add("apparence.json was written: $(Get-Content $appearanceFile -Raw)") }
    }

    Invoke-Check "Apparence: the list holds the presets, Repère chosen, and no theme of one's own yet" {
        param($problems)
        $rows = @(Get-ThemeRow) -join ', '
        if ($rows -ne ($presetNames -join ', ')) { $problems.Add("the list holds: $rows") }
        foreach ($removed in 'scheme_Repere', 'scheme_Repere_light', 'scheme_Repere_dark', 'copy_Repere', 'theme_edit', 'theme_delete', 'custom_empty') {
            if (Find-ShownPopupControl $removed) { $problems.Add("$removed is shown") }
        }
        if (-not (Find-ShownPopupControl 'theme_copy')) { $problems.Add('the chosen preset has no copy button') }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Repère') { $problems.Add("chosen: '$chosen', expected Repère") }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards) { $problems.Add("themes of one's own shown: $cards") }
        # The buttons say what can be done: no note under Mes thèmes.
        $note = Find-ShownPopupControl 'theme_own_note'
        if ($note) { $problems.Add("under Mes thèmes, on a preset: '$($note.Current.Name)'") }
        if (-not (Find-PopupControl 'create_theme' 'settings').Current.IsEnabled) { $problems.Add('Créer un thème is disabled') }
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-1-galerie' (Wait-Dialog 'Paramètres') }
    }

    Invoke-Check "Apparence: copying a preset opens the editor on « <name> (copie) », its color and its palettes; Annuler saves nothing" {
        param($problems)
        Open-Editor 'theme_copy'
        $state = Get-EditorState
        $expected = 'Nouveau thème | Repère (copie) | 6A48F2 | Teinté | sans Supprimer'
        if ($state -ne $expected) { $problems.Add("the editor shows '$state', expected '$expected'") }
        # The copy takes Repère's own palettes, so it looks the same: each of their 22 colors is filled in per mode, its
        # dark accent too, which the note under the accent names. The light accent is the color above, and the selected
        # row and the text on the accent come from it.
        $toggle = (Find-PopupControl 'editor_colors_toggle_text' 'settings').Current.Name
        if ($toggle -ne '45 couleurs personnalisées') { $problems.Add("the colors button reads '$toggle', expected 45 couleurs personnalisées") }
        $note = Find-PopupElement 'editor_accent_note'
        if (-not $note -or $note.Current.Name -ne 'Sombre : son propre accent, #7553FF, défini dans les couleurs personnalisées. Une couleur choisie ici le remplace.') { $problems.Add("the note under the accent reads '$(if ($note) { $note.Current.Name })'") }
        Invoke-PopupControl 'editor_colors_toggle'
        $boxes = foreach ($id in 'editor_color_Bg_dark', 'editor_color_Text_light', 'editor_color_Chrome_light', 'editor_color_WarnText_dark', 'editor_color_Accent_dark', 'editor_color_Accent_light', 'editor_color_Selection_dark', 'editor_color_OnAccent_light') { Get-PopupText $id }
        if (($boxes -join ' | ') -ne '16121C | 241D2D | FFFFFF | F2C46B | 7553FF |  |  | ') { $problems.Add("the copy's colors are: $($boxes -join ' | ')") }
        Invoke-PopupControl 'editor_cancel'
        if (-not (Test-GalleryShown)) { $problems.Add("Annuler didn't go back to the gallery") }
        if (Test-Path $appearanceFile) { $problems.Add("apparence.json was written: $(Get-Content $appearanceFile -Raw)") }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Repère') { $problems.Add("chosen: '$chosen', expected Repère") }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards) { $problems.Add("themes of one's own shown: $cards") }
    }

    Invoke-Check 'Apparence: the sliders follow the color typed, and the color follows the sliders and the quick colors' {
        param($problems)
        # A new theme starts from the current one, Repère.
        Open-Editor 'create_theme'
        $state = Get-EditorState
        $expected = 'Nouveau thème |  | 6A48F2 | Teinté | sans Supprimer'
        if ($state -ne $expected) { $problems.Add("the new theme's editor shows '$state', expected '$expected'") }
        # #FFE600: hue 54, saturation 100, lightness 50.
        Set-PopupText 'editor_accent' 'ffe600'
        $hsl = foreach ($slider in 'editor_hue', 'editor_saturation', 'editor_lightness') { Get-SliderValue $slider }
        if ([Math]::Abs($hsl[0] - 54) -gt 1 -or [Math]::Abs($hsl[1] - 100) -gt 1 -or [Math]::Abs($hsl[2] - 50) -gt 1) {
            $problems.Add("after ffe600, the sliders read $($hsl -join ', '), expected 54, 100, 50")
        }
        # Hue 200 at full saturation and half lightness: #00AAFF.
        Set-SliderValue 'editor_hue' 200
        $accent = Get-PopupText 'editor_accent'
        if ($accent -ne '00AAFF') { $problems.Add("after the hue slider moved to 200, the color reads '$accent', expected 00AAFF") }
        # The box holds the digits only: a # pasted with them is dropped.
        Set-PopupText 'editor_accent' '#0b7a68'
        $accent = Get-PopupText 'editor_accent'
        if ($accent -ne '0b7a68') { $problems.Add("after #0b7a68 was pasted, the color reads '$accent', expected 0b7a68") }
        # The square opens the picker, under it: its hue slider and its code write in the box.
        Invoke-PopupControl 'pick_accent'
        Set-SliderValue 'picker_hue' 200
        $picked = Get-PopupText 'picker_hex'
        $accent = Get-PopupText 'editor_accent'
        if ($accent -ne $picked -or $accent -eq '0b7a68') { $problems.Add("after the picker's hue moved to 200, the picker reads '$picked' and the color '$accent'") }
        if ($ScreenshotDirectory) {
            # The picker is a popup of Paramètres: the first window above its hue slider.
            $popup = Find-PopupControl 'picker_hue' 'settings'
            while ($popup -and $popup.Current.ControlType -ne [System.Windows.Automation.ControlType]::Window) { $popup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($popup) }
            Save-Screenshot 'apparence-selecteur' $popup
        }
        Set-PopupText 'picker_hex' '#FFE600'
        $accent = Get-PopupText 'editor_accent'
        $hue = Get-SliderValue 'editor_hue'
        if ($accent -ne 'FFE600' -or [Math]::Abs($hue - 54) -gt 1) { $problems.Add("after #FFE600 in the picker, the color reads '$accent' and the hue $hue, expected FFE600 and 54") }
        Close-ColorPicker
        # Lagon's #0B7A68: hue 170, saturation 83, lightness 26.
        Invoke-PopupControl 'editor_pick_Lagon'
        $accent = Get-PopupText 'editor_accent'
        $hue = Get-SliderValue 'editor_hue'
        if ($accent -ne '0B7A68' -or [Math]::Abs($hue - 170) -gt 1) { $problems.Add("after the Lagon quick color, the color reads '$accent' and the hue $hue, expected 0B7A68 and 170") }
        Invoke-PopupControl 'editor_back'
        if (-not (Test-GalleryShown)) { $problems.Add("the back button didn't go back to the gallery") }
        if (Test-Path $appearanceFile) { $problems.Add("apparence.json was written: $(Get-Content $appearanceFile -Raw)") }
    }

    Invoke-Check "Apparence: the quick accent is both modes', replacing a mode's own; one set in Couleurs afterwards is used as typed, with a warning when it's hard to see" {
        param($problems)
        Open-Editor 'theme_copy'
        Invoke-PopupControl 'editor_colors_toggle'
        # The copy's own dark accent: a quick accent chosen replaces it, so both modes take it, and the note no longer
        # names an accent of a mode's own.
        Set-PopupText 'editor_accent' '1f5ccc'
        $boxes = "$(Get-PopupText 'editor_color_Accent_light')/$(Get-PopupText 'editor_color_Accent_dark')"
        if ($boxes -ne '/') { $problems.Add("after the quick accent changed, the accent boxes hold '$boxes', expected both empty") }
        $note = Find-PopupElement 'editor_accent_note'
        if ($note -and $note.Current.Name -like '*propre accent*') { $problems.Add("after the quick accent changed, the note reads '$($note.Current.Name)'") }
        if (Find-PopupElement 'editor_contrast') { $problems.Add("the quick accent alone gives a warning: '$((Find-PopupElement 'editor_contrast').Current.Name)'") }
        # A pale yellow set for the light mode: kept as typed, named under the accent, and said to be hard to see.
        Set-PopupText 'editor_color_Accent_light' 'ffe600'
        $warning = Find-PopupElement 'editor_contrast'
        $said = if ($warning) { $warning.Current.Name } else { '' }
        if ($said -notlike "Clair : l'accent ressort peu (*:1, 3:1 conseillé) ; la sélection et le focus se verront mal.*") { $problems.Add("the warning reads '$said'") }
        $note = (Find-PopupElement 'editor_accent_note').Current.Name
        if ($note -notlike 'Clair : son propre accent, #FFE600, défini dans les couleurs personnalisées. Une couleur choisie ici le remplace.*') { $problems.Add("with the light one set, the note reads '$note'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-accents' (Wait-Dialog 'Paramètres') }
        # A quick accent chosen again empties the light one's box too, and its warning goes.
        Invoke-PopupControl 'editor_pick_Lagon'
        $light = Get-PopupText 'editor_color_Accent_light'
        if ($light) { $problems.Add("after the Lagon quick color, the light accent box holds '$light'") }
        Start-Sleep -Milliseconds 300
        if (Find-PopupElement 'editor_contrast') { $problems.Add("the warning stays once the quick accent is chosen: '$((Find-PopupElement 'editor_contrast').Current.Name)'") }
        Invoke-PopupControl 'editor_cancel'
        if (Test-Path $appearanceFile) { $problems.Add("apparence.json was written: $(Get-Content $appearanceFile -Raw)") }
    }

    Invoke-Check 'Apparence: a new theme, pale and Intense, is saved, chosen and added to the list' {
        param($problems)
        # A new theme starts from the current one: from Marine, it's Intense. Picking a theme leaves the mode as it is.
        Select-Theme 'Marine'
        $saved = Wait-SavedAppearance { param($s) $s.Scheme -eq 'Marine' }
        if ($saved.Theme -ne 'Système' -or $saved.Scheme -ne 'Marine') { $problems.Add("after Marine was picked, apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)") }
        Open-Editor 'create_theme'
        Set-PopupText 'editor_name' 'Soleil'
        # Too pale to stand out on the light mode: Repère adjusts it per mode rather than refusing it.
        Set-PopupText 'editor_accent' 'ffe600'
        $state = Get-EditorState
        $expected = 'Nouveau thème | Soleil | ffe600 | Intense | sans Supprimer'
        if ($state -ne $expected) { $problems.Add("the editor shows '$state', expected '$expected'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-2-editeur' (Wait-Dialog 'Paramètres') }
        Invoke-PopupControl 'editor_save'
        if (-not (Test-GalleryShown)) { $problems.Add("Enregistrer didn't go back to the gallery") }
        $saved = Wait-SavedAppearance { param($s) $s.Scheme -eq 'c1' }
        $themes = Format-SavedTheme $saved
        # Saved by the editor: its colors of one's own (none yet) are used as typed.
        if ($saved.Scheme -ne 'c1' -or $saved.Theme -ne 'Système' -or $themes -ne 'c1 Soleil #FFE600 Intense' -or $saved.CustomThemes[0].Exact -ne $true) {
            $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)")
        }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards -ne 'Soleil') { $problems.Add("themes of one's own shown: '$cards', expected Soleil") }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Soleil') { $problems.Add("chosen: '$chosen', expected Soleil") }
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_system') { $problems.Add("mode: '$mode', expected theme_system") }
        $note = Find-ShownPopupControl 'theme_own_note'
        if ($note) { $problems.Add("under Mes thèmes, on a theme of one's own: '$($note.Current.Name)'") }
        foreach ($shown in 'theme_edit', 'theme_delete') { if (-not (Find-ShownPopupControl $shown)) { $problems.Add("$shown isn't shown for a theme of one's own") } }
        if (Find-ShownPopupControl 'theme_copy') { $problems.Add("theme_copy is shown for a theme of one's own") }
    }

    Invoke-Check 'Apparence: an invalid color is refused and nothing is saved' {
        param($problems)
        $before = Get-Content $appearanceFile -Raw
        Open-Editor 'theme_edit'
        Set-PopupText 'editor_accent' 'zz'
        Invoke-PopupControl 'editor_save'
        $errorText = Wait-ShownPopupControl 'editor_error'
        if (-not $errorText) { $problems.Add("the error message isn't shown") }
        elseif ($errorText.Current.Name -ne 'Couleur invalide. Exemple : #7553FF') { $problems.Add("the error message reads '$($errorText.Current.Name)'") }
        if (-not (Find-ShownPopupControl 'editor_save')) { $problems.Add('the editor closed') }
        Start-Sleep -Milliseconds 500
        $after = Get-Content $appearanceFile -Raw
        if ($after -ne $before) { $problems.Add("apparence.json changed: $after") }
        Invoke-PopupControl 'editor_cancel'
        if (-not (Test-GalleryShown)) { $problems.Add("Annuler didn't go back to the gallery") }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards -ne 'Soleil') { $problems.Add("themes of one's own shown: '$cards', expected Soleil") }
    }

    Invoke-Check 'Apparence: Clair saves the mode and keeps the theme, and the page stays open' {
        param($problems)
        # From Windows' mode: when it's dark, the mode changes, Fluent rebuilds the window, which stays open.
        Select-Theme 'Marine'
        Invoke-PopupControl 'theme_light'
        $saved = Wait-SavedAppearance { param($s) $s.Theme -eq 'Clair' -and $s.Scheme -eq 'Marine' }
        if ($saved.Theme -ne 'Clair' -or $saved.Scheme -ne 'Marine' -or (Format-SavedTheme $saved) -ne 'c1 Soleil #FFE600 Intense') {
            $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)")
        }
        if (-not (Test-GalleryKept)) { $problems.Add('the Apparence page closed') }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Marine') { $problems.Add("chosen: '$chosen', expected Marine") }
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_light') { $problems.Add("mode: '$mode', expected theme_light") }
    }

    Invoke-Check 'Apparence: a theme picked keeps the mode chosen' {
        param($problems)
        Select-Theme 'Lagon'
        $saved = Wait-SavedAppearance { param($s) $s.Scheme -eq 'Lagon' }
        if ($saved.Theme -ne 'Clair' -or $saved.Scheme -ne 'Lagon') { $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)") }
        if (-not (Test-GalleryShown)) { $problems.Add('the Apparence page closed') }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Lagon') { $problems.Add("chosen: '$chosen', expected Lagon") }
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_light') { $problems.Add("mode: '$mode', expected theme_light") }
    }

    Invoke-Check 'Apparence: going through the open list tries each theme, saves nothing, and the theme chosen comes back' {
        param($problems)
        $before = Get-Content $appearanceFile -Raw
        $list = Find-PopupControl 'theme_list' 'settings'
        $settingsWindow = Wait-Dialog 'Paramètres'
        $expand = $list.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        $expand.Expand()
        # The mouse and the arrows both move the focus to the row, which is all the list goes by. The window itself is
        # what's looked at: Framboise's light background, then Lagon's again.
        (Find-ThemeRow $list 'Framboise').SetFocus()
        for ($i = 0; $i -lt 20 -and $list.Current.ItemStatus -ne 'Aperçu : Framboise'; $i++) { Start-Sleep -Milliseconds 100 }
        if ($list.Current.ItemStatus -ne 'Aperçu : Framboise') { $problems.Add("trying Framboise, the list says '$($list.Current.ItemStatus)'") }
        $drawn = Wait-WindowBackground $settingsWindow '#FAF4F7'
        if ($drawn -ne '#FAF4F7') { $problems.Add("trying Framboise, the window's background is $drawn, expected #FAF4F7") }
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-essai' $settingsWindow }
        $expand.Collapse()
        for ($i = 0; $i -lt 20 -and $list.Current.ItemStatus; $i++) { Start-Sleep -Milliseconds 100 }
        if ($list.Current.ItemStatus) { $problems.Add("closed, the list still says '$($list.Current.ItemStatus)'") }
        $drawn = Wait-WindowBackground $settingsWindow '#F0F6F5'
        if ($drawn -ne '#F0F6F5') { $problems.Add("closed, the window's background is $drawn, expected Lagon's #F0F6F5") }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Lagon') { $problems.Add("chosen: '$chosen', expected Lagon") }
        $after = Get-Content $appearanceFile -Raw
        if ($after -ne $before) { $problems.Add("apparence.json changed: $after") }
    }

    Invoke-Check "Apparence: Sombre and Graphite are saved, and used at the next start with the theme of one's own" {
        param($problems)
        # From light: the mode changes, and the page must stay open.
        Select-Theme 'Graphite'
        Invoke-PopupControl 'theme_dark'
        $saved = Wait-SavedAppearance { param($s) $s.Theme -eq 'Sombre' -and $s.Scheme -eq 'Graphite' }
        if ($saved.Theme -ne 'Sombre' -or $saved.Scheme -ne 'Graphite' -or (Format-SavedTheme $saved) -ne 'c1 Soleil #FFE600 Intense') {
            $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)")
        }
        if (-not (Test-GalleryKept)) { $problems.Add('the Apparence page closed when the mode changed') }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Graphite') { $problems.Add("chosen: '$chosen', expected Graphite") }
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_dark') { $problems.Add("mode: '$mode', expected theme_dark") }
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-3-sombre-graphite' (Wait-Dialog 'Paramètres') }

        Restart-App
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Graphite') { $problems.Add("after a restart, chosen: '$chosen', expected Graphite") }
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_dark') { $problems.Add("after a restart, mode: '$mode', expected theme_dark") }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards -ne 'Soleil') { $problems.Add("after a restart, themes of one's own shown: '$cards', expected Soleil") }
    }

    Invoke-Check 'Apparence: editing a theme renames it, and Entrée saves' {
        param($problems)
        Select-Theme 'Soleil'
        Open-Editor 'theme_edit'
        $state = Get-EditorState
        $expected = 'Modifier le thème | Soleil | FFE600 | Intense | Supprimer'
        if ($state -ne $expected) { $problems.Add("the editor shows '$state', expected '$expected'") }
        if (Find-ShownPopupControl 'editor_error') { $problems.Add('an error message is shown') }
        Set-PopupText 'editor_name' 'Soleil levant'
        $nameBox = Find-PopupControl 'editor_name' 'settings'
        $nameBox.SetFocus()
        Send-Key 0x0D (Get-HolderWindow $nameBox)
        if (-not (Test-GalleryShown)) { $problems.Add("Entrée didn't save and go back to the gallery") }
        $saved = Wait-SavedAppearance { param($s) (Format-SavedTheme $s) -eq 'c1 Soleil levant #FFE600 Intense' }
        if ($saved.Theme -ne 'Sombre' -or $saved.Scheme -ne 'c1' -or (Format-SavedTheme $saved) -ne 'c1 Soleil levant #FFE600 Intense') {
            $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)")
        }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards -ne 'Soleil levant') { $problems.Add("themes of one's own shown: '$cards', expected Soleil levant") }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Soleil levant') { $problems.Add("chosen: '$chosen', expected Soleil levant") }
    }

    Invoke-Check 'Apparence: the editor has a single preview, of the mode in use, which goes to the mode of a color changed' {
        param($problems)
        Open-Editor 'theme_edit'
        $mockUp = [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'pv_text')
        $count = @(foreach ($top in Get-AppWindow) { $top.FindAll($Descendants, $mockUp) }).Count
        if ($count -ne 1) { $problems.Add("$count previews are shown") }
        $shown = "$(Get-ToggleState 'editor_preview_light')/$(Get-ToggleState 'editor_preview_dark')"
        if ($shown -ne 'Off/On') { $problems.Add("in dark mode, the preview's toggles read $shown, expected Off/On") }
        Invoke-PopupControl 'editor_preview_light'
        $shown = "$(Get-ToggleState 'editor_preview_light')/$(Get-ToggleState 'editor_preview_dark')"
        if ($shown -ne 'On/Off') { $problems.Add("after Clair, the preview's toggles read $shown, expected On/Off") }
        Invoke-PopupControl 'editor_colors_toggle'
        Set-PopupText 'editor_color_Text_dark' 'F5F0E6'
        $shown = "$(Get-ToggleState 'editor_preview_light')/$(Get-ToggleState 'editor_preview_dark')"
        if ($shown -ne 'Off/On') { $problems.Add("after a dark color changed, the preview's toggles read $shown, expected Off/On") }
        Invoke-PopupControl 'editor_cancel'
        if (-not (Test-GalleryShown)) { $problems.Add("Annuler didn't go back to the gallery") }
    }

    Invoke-Check "Apparence: a theme's own colors, per mode: folded at first, a warning for hard-to-read text, a wrong color refused, then saved" {
        param($problems)
        Open-Editor 'theme_edit'
        if (Find-PopupElement 'editor_color_Text_dark') { $problems.Add('the colors are shown before Personnaliser les couleurs') }
        $toggle = (Find-PopupControl 'editor_colors_toggle_text' 'settings').Current.Name
        if ($toggle -ne 'Personnaliser les couleurs') { $problems.Add("the colors button reads '$toggle'") }
        Invoke-PopupControl 'editor_colors_toggle'
        # A dark text on the dark mode: still allowed, with a warning, which goes once the text reads again.
        Set-PopupText 'editor_color_Text_dark' '444444'
        $warning = Find-PopupElement 'editor_contrast'
        if (-not $warning -or $warning.Current.Name -notlike 'Sombre : « Texte » se lit mal sur « * » (*:1, 4,5:1 conseillé).') { $problems.Add("the warning reads '$(if ($warning) { $warning.Current.Name })'") }
        Set-PopupText 'editor_color_Text_dark' 'F5F0E6'
        Start-Sleep -Milliseconds 300
        if (Find-PopupElement 'editor_contrast') { $problems.Add("the warning stays once the text reads: '$((Find-PopupElement 'editor_contrast').Current.Name)'") }
        # Through the picker this time: its square opens it on the automatic color, and its code goes in the box.
        Invoke-PopupControl 'pick_Bg_light'
        Set-PopupText 'picker_hex' 'fffbe8'
        $picked = Get-PopupText 'editor_color_Bg_light'
        if ($picked -ne 'FFFBE8') { $problems.Add("the picker wrote '$picked' in the light background's box, expected FFFBE8") }
        Close-ColorPicker
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-4-couleurs' (Wait-Dialog 'Paramètres') }
        Set-PopupText 'editor_color_Surface_light' 'zz'
        Invoke-PopupControl 'editor_save'
        $errorText = Find-PopupElement 'editor_error'
        $expected = 'Couleur invalide pour « Listes et cartes » (clair). Exemple : #1E1E1E, ou vide pour la couleur automatique.'
        if (-not $errorText -or $errorText.Current.Name -ne $expected) { $problems.Add("the error message reads '$(if ($errorText) { $errorText.Current.Name })', expected '$expected'") }
        # Emptied, the box is automatic again.
        Set-PopupText 'editor_color_Surface_light' ''
        Invoke-PopupControl 'editor_save'
        if (-not (Test-GalleryShown)) { $problems.Add("Enregistrer didn't save and go back to the gallery") }
        $saved = Wait-SavedAppearance { param($s) $s.CustomThemes[0].Colors.Light.Bg -eq '#FFFBE8' }
        $colors = $saved.CustomThemes[0].Colors
        if ((Format-SavedTheme $saved) -ne 'c1 Soleil levant #FFE600 Intense' -or $colors.Light.Bg -ne '#FFFBE8' -or $colors.Dark.Text -ne '#F5F0E6' -or
            @($colors.Light.PSObject.Properties).Count -ne 1 -or @($colors.Dark.PSObject.Properties).Count -ne 1) {
            $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 6)")
        }
        # Opened again: folded, the button counts them; unfolded, each box holds its color, the others stay empty.
        Open-Editor 'theme_edit'
        $toggle = (Find-PopupControl 'editor_colors_toggle_text' 'settings').Current.Name
        if ($toggle -ne '2 couleurs personnalisées') { $problems.Add("the colors button reads '$toggle', expected 2 couleurs personnalisées") }
        Invoke-PopupControl 'editor_colors_toggle'
        $boxes = foreach ($id in 'editor_color_Bg_light', 'editor_color_Text_dark', 'editor_color_Surface_light') { Get-PopupText $id }
        if (($boxes -join ' | ') -ne 'FFFBE8 | F5F0E6 | ') { $problems.Add("the boxes hold: $($boxes -join ' | ')") }
        Invoke-PopupControl 'editor_cancel'
    }

    # Both Supprimer ask first (#188), Annuler by default. The editor's names the theme as saved, not as typed, and
    # leaves the editor as it was when it isn't confirmed.
    Invoke-Check "Apparence: the editor's Supprimer asks first, and Entrée or Annuler keep the theme" {
        param($problems)
        $settingsWindow = Wait-Dialog 'Paramètres'
        Open-Editor 'theme_edit'
        Set-PopupText 'editor_name' 'Pas encore enregistré'
        Invoke-PopupControl 'editor_delete'
        $confirm = Wait-OwnedDialog $settingsWindow 'Supprimer le thème'
        $expected = "Supprimer le thème « Soleil levant » ?`n`nIl ne pourra pas être récupéré. Repère reprendra son thème."
        if ((Get-DialogText $confirm) -ne $expected) { $problems.Add("the confirmation says '$(Get-DialogText $confirm)'") }
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-5-supprimer' $confirm }
        Send-Key 0x0D $confirm
        Start-Sleep -Milliseconds 600
        $count = @((Read-SavedAppearance).CustomThemes).Count
        if ($count -ne 1) { $problems.Add("after Entrée, apparence.json holds $count themes of one's own") }
        if (-not (Find-ShownPopupControl 'editor_save')) { $problems.Add('after Entrée, the editor closed') }
        elseif ((Get-PopupText 'editor_name') -ne 'Pas encore enregistré') { $problems.Add("after Entrée, the editor's name is '$(Get-PopupText 'editor_name')'") }
        Invoke-PopupControl 'editor_cancel'
        if ($ScreenshotDirectory) { Save-Screenshot 'apparence-mes-themes' $settingsWindow }
        Invoke-PopupControl 'theme_delete'
        Close-OwnedDialog (Wait-OwnedDialog $settingsWindow 'Supprimer le thème') 'dialog_cancel'
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards -ne 'Soleil levant') { $problems.Add("after Annuler, themes of one's own shown: '$cards'") }
        if ((Get-ChosenScheme) -ne 'Soleil levant') { $problems.Add("after Annuler, chosen: '$(Get-ChosenScheme)'") }
    }

    Invoke-Check "Apparence: Supprimer, confirmed, deletes the chosen theme, brings Repère back and says so" {
        param($problems)
        $settingsWindow = Wait-Dialog 'Paramètres'
        Invoke-PopupControl 'theme_delete'
        $confirm = Wait-OwnedDialog $settingsWindow 'Supprimer le thème'
        $text = Get-DialogText $confirm
        if ($text -notlike 'Supprimer le thème « Soleil levant » ?*') { $problems.Add("the confirmation says '$text'") }
        Close-OwnedDialog $confirm 'dialog_ok'
        if (-not (Test-GalleryShown)) { $problems.Add("the gallery isn't shown after the deletion") }
        $saved = Wait-SavedAppearance { param($s) -not @($s.CustomThemes).Count }
        if ($saved.Theme -ne 'Sombre' -or $saved.Scheme -ne 'Repere' -or @($saved.CustomThemes).Count) {
            $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)")
        }
        $cards = (Get-CustomThemeCard) -join ', '
        if ($cards) { $problems.Add("themes of one's own shown: $cards") }
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Repère') { $problems.Add("chosen: '$chosen', expected Repère") }
        $note = (Find-PopupControl 'theme_own_note' 'settings').Current.Name
        if ($note -ne 'Thème « Soleil levant » supprimé : Repère a repris son thème.') { $problems.Add("under Mes thèmes, after the deletion: '$note'") }
    }

    Invoke-Check 'Apparence: the language picked is saved for the next start, and the page says so' {
        param($problems)
        $settingsWindow = Wait-Dialog 'Paramètres'
        Select-ComboItem 'language_list' 'English'
        Start-Sleep -Milliseconds 500
        $saved = Read-SavedSetting 'parametres.json'
        if ($saved.Language -ne 'en') { $problems.Add("after English, parametres.json holds: $($saved | ConvertTo-Json -Compress)") }
        Select-ComboItem 'language_list' 'Langue de Windows'
        Start-Sleep -Milliseconds 500
        $saved = Read-SavedSetting 'parametres.json'
        if ($saved.Language -ne '') { $problems.Add("after Langue de Windows, parametres.json holds: $($saved | ConvertTo-Json -Compress)") }
        if (-not (Get-DialogPart $settingsWindow 'language_list')) { $problems.Add("the language's list isn't in Paramètres") }
    }

    Invoke-Check 'Apparence: Selon le système is saved, and follows Windows again' {
        param($problems)
        Invoke-PopupControl 'theme_system'
        $saved = Wait-SavedAppearance { param($s) $s.Theme -eq 'Système' }
        if ($saved.Theme -ne 'Système') { $problems.Add("apparence.json holds: $($saved | ConvertTo-Json -Compress -Depth 4)") }
        if (-not (Test-GalleryKept)) { $problems.Add('the Apparence page closed when the mode changed') }
        $mode = (Get-ChosenMode) -join ', '
        if ($mode -ne 'theme_system') { $problems.Add("mode: '$mode', expected theme_system") }
    }

    # Settings saved before the themes: a mode, a dark style (Violet or Gris) and an accent (a preset's name or #RRGGBB).
    # Mode: the toggle on. Editor: what the editor of the theme made from them shows. Nothing is saved at start:
    # apparence.json keeps the old settings until a theme is picked.
    $oldSettings = @(
        @{ Name = 'Apparence: old settings with a named accent open on the matching preset'
           Settings = '{ "Theme": "Sombre", "DarkStyle": "Violet", "Accent": "Sarcelle" }'
           Mode = 'theme_dark'; Chosen = 'Lagon'; Cards = '' }
        @{ Name = "Apparence: old settings with the Gris dark style become a theme of one's own, « Gris », neutral"
           Settings = '{ "DarkStyle": "Gris", "Accent": "Violet" }'
           Mode = 'theme_system'; Chosen = 'Gris'; Cards = 'Gris'; Editor = 'Modifier le thème | Gris | 6A48F2 | Neutre | Supprimer' }
        @{ Name = "Apparence: old settings with a color of one's own become a theme, « Personnalisé », tinted"
           Settings = '{ "Theme": "Clair", "DarkStyle": "Violet", "Accent": "#2e7d32" }'
           Mode = 'theme_light'; Chosen = 'Personnalisé'; Cards = 'Personnalisé'; Editor = 'Modifier le thème | Personnalisé | 2E7D32 | Teinté | Supprimer' }
        # Presets renamed or removed since: Océan is now Marine, and Iris, gone, gives way to Repère.
        @{ Name = 'Apparence: a saved preset that was renamed opens on its new name'
           Settings = '{ "Theme": "Sombre", "Scheme": "Ocean" }'
           Mode = 'theme_dark'; Chosen = 'Marine'; Cards = '' }
        @{ Name = 'Apparence: a saved preset that was removed opens on Repère'
           Settings = '{ "Theme": "Clair", "Scheme": "Iris" }'
           Mode = 'theme_light'; Chosen = 'Repère'; Cards = '' }
    )
    foreach ($old in $oldSettings) {
        Invoke-Check $old.Name {
            param($problems)
            Restart-App $old.Settings
            $mode = (Get-ChosenMode) -join ', '
            if ($mode -ne $old.Mode) { $problems.Add("mode: '$mode', expected $($old.Mode)") }
            $chosen = Get-ChosenScheme
            if ($chosen -ne $old.Chosen) { $problems.Add("chosen: '$chosen', expected $($old.Chosen)") }
            $cards = (Get-CustomThemeCard) -join ', '
            if ($cards -ne $old.Cards) { $problems.Add("themes of one's own shown: '$cards', expected '$($old.Cards)'") }
            if ($old.Editor) {
                Open-Editor 'theme_edit'
                $state = Get-EditorState
                if ($state -ne $old.Editor) { $problems.Add("the editor shows '$state', expected '$($old.Editor)'") }
                Invoke-PopupControl 'editor_cancel'
            }
            $saved = (Get-Content $appearanceFile -Raw -Encoding utf8).Trim()
            if ($saved -ne $old.Settings) { $problems.Add("apparence.json was rewritten: $saved") }
        }
    }

    Invoke-Check "Apparence: at 8 themes of one's own none can be added, and a theme that no longer exists falls back to Repère" {
        param($problems)
        $themes = @(foreach ($number in 1..8) { [ordered]@{ Id = "c$number"; Name = "Thème $number"; Accent = '#3A6BD6'; Tint = 'Teinté' } })
        Restart-App ([ordered]@{ Theme = 'Clair'; Scheme = 'c9'; CustomThemes = $themes } | ConvertTo-Json -Depth 4)
        $before = Get-Content $appearanceFile -Raw
        $chosen = Get-ChosenScheme
        if ($chosen -ne 'Repère') { $problems.Add("chosen: '$chosen', expected Repère") }
        $cards = @(Get-CustomThemeCard)
        if ($cards.Count -ne 8) { $problems.Add("themes of one's own shown: $($cards -join ', ')") }
        if ((Find-PopupControl 'create_theme' 'settings').Current.IsEnabled) { $problems.Add('Créer un thème is enabled') }
        # A copy still opens the editor, but can't be saved.
        Open-Editor 'theme_copy'
        Invoke-PopupControl 'editor_save'
        $errorText = Wait-ShownPopupControl 'editor_error'
        $expected = '8 thèmes au plus : supprimez-en un pour en créer un autre.'
        if (-not $errorText -or $errorText.Current.Name -ne $expected) { $problems.Add("the error message reads '$(if ($errorText) { $errorText.Current.Name })', expected '$expected'") }
        Start-Sleep -Milliseconds 500
        $after = Get-Content $appearanceFile -Raw
        if ($after -ne $before) { $problems.Add("apparence.json changed: $after") }
        Invoke-PopupControl 'editor_cancel'
    }
}

function Write-Result([string]$Name, [System.Collections.Generic.List[string]]$Problems) {
    # A failure is only reported if the desktop is still usable: a locked screen or a disconnected session makes any check
    # fail ("The right-click menu didn't open."), which says nothing about Repère.
    if ($Problems.Count) { Assert-DesktopUsable }
    $script:checks++
    if ($Problems.Count) {
        $script:failed++
        Write-Host "FAIL  $Name" -ForegroundColor Red
        $Problems | ForEach-Object { Write-Host "      $_" }
    }
    else {
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
}

function Test-Scenario([hashtable]$Scenario, [int]$Number) {
    $queriesBefore = @(Get-LoggedQuery).Count

    # Fill in the term while its box is enabled, then switch to the scenario's search type.
    $domain = if ($Scenario.Domain) { $Scenario.Domain } else { 'demo.local' }
    if (-not $Scenario.SingleDomain) { Select-Domain $domain }
    Select-SearchType 'Description contient'
    if ($Scenario.Advanced) { Set-AdvancedSearch $Scenario.Advanced } else { Reset-AdvancedSearch }
    Set-Text 'prefix' $Scenario.Prefix
    Set-Text 'search_term' $Scenario.Term
    Select-SearchType $Scenario.Type
    Invoke-Search

    $label = (Find-Control 'results_count').Current.Name
    $queries = @(Get-LoggedQuery | Select-Object -Skip $queriesBefore)
    $problems = [System.Collections.Generic.List[string]]::new()
    $hint = Find-ShownControl 'search_hint_text'
    if ($Scenario.Message) {
        # Said under the search field, not in the count.
        $hintText = if ($hint) { $hint.Current.Name }
        if ($hintText -ne $Scenario.Message) { $problems.Add("the hint under the field says '$hintText', expected '$($Scenario.Message)'") }
        # Queried: asked for once AD answered (Adresse IP, a name finding too many computers).
        if ($queries.Count -and -not $Scenario.Queried) { $problems.Add("AD was queried: $(($queries | ForEach-Object { Format-Query $_ }) -join ' | ')") }
        # A search that ran and asks for more: its count, with no error.
        if ($Scenario.Label -and $label -notlike $Scenario.Label) { $problems.Add("label is '$label', expected '$($Scenario.Label)'") }
        # The box to fill has the focus: the second one for a list, an address or a key, the name's otherwise.
        if ($Scenario.Focus) {
            $focused = [System.Windows.Automation.AutomationElement]::FocusedElement.Current.AutomationId
            if ($focused -ne $Scenario.Focus) { $problems.Add("the focus is on '$focused', expected '$($Scenario.Focus)'") }
        }
    }
    elseif ($hint) { $problems.Add("a hint shows under the field: '$($hint.Current.Name)'") }
    else {
        # Every domain searched gets the filter, with -Server. '' = the whole domain. @() so that SearchBases = @() stays empty.
        $searchedDomains = if ($domain -eq 'Tous les domaines') { $fakeDomains } else { @($domain) }
        $expectedQueries = @(foreach ($searchedDomain in $searchedDomains) {
            $searchBases = @(if ($Scenario.ContainsKey('SearchBases')) { $Scenario.SearchBases } elseif ($Scenario.Advanced -and $Scenario.Advanced.Scope -eq 'name') { $commonSearchBases[$searchedDomain] } else { '' })
            $filter = if ($Scenario.Filter -is [scriptblock]) { & $Scenario.Filter } else { $Scenario.Filter }
            $searchBases | ForEach-Object { Format-Query @{ Command = 'Get-ADComputer'; Filter = $filter; SearchBase = $_; Server = $searchedDomain } }
        }) | Sort-Object
        $sentQueries = @($queries | Where-Object Command -eq 'Get-ADComputer' | ForEach-Object { Format-Query $_ } | Sort-Object)
        if (($sentQueries -join ' | ') -ne ($expectedQueries -join ' | ')) {
            $problems.Add("queries sent: $($sentQueries -join ' | '); expected: $($expectedQueries -join ' | ')")
        }
        $expectedCount = if ($Scenario.Rows) { @($Scenario.Rows).Count } else { $Scenario.Count }
        # French uses the singular for 0 and 1.
        $expectedLabel = if ($Scenario.Label) { $Scenario.Label } elseif ($expectedCount -le 1) { "$expectedCount ordinateur" } else { "$expectedCount ordinateurs" }
        if ($label -notlike $expectedLabel) { $problems.Add("label is '$label', expected '$expectedLabel'") }
        if ($Scenario.Label -and @(Get-ResultName).Count -ne $expectedCount) { $problems.Add("$(@(Get-ResultName).Count) rows shown, expected $expectedCount") }
        if ($Scenario.ShownDomains) {
            $shownDomains = (@(Get-ResultRow | ForEach-Object { $_[5] }) | Sort-Object) -join ', '
            $expected = (@($Scenario.ShownDomains) | Sort-Object) -join ', '
            if ($shownDomains -ne $expected) { $problems.Add("Domaine column shows: $shownDomains; expected: $expected") }
        }
        if ($Scenario.Rows) {
            $shown = (Get-ResultName) -join ', '
            $expected = (@($Scenario.Rows) | Sort-Object) -join ', '
            if ($shown -ne $expected) { $problems.Add("rows shown: $shown; expected: $expected") }
        }
        if ($Scenario.Cells) {
            $shownRows = @{}
            foreach ($cells in (Get-ResultRow)) { $shownRows[$cells[1]] = $cells }
            foreach ($name in $Scenario.Cells.Keys) {
                $cells = $shownRows[$name]
                if (-not $cells) { $problems.Add("$name isn't shown"); continue }
                $shown = $cells -join ' | '
                $expected = $Scenario.Cells[$name] -join ' | '
                if ($shown -ne $expected) { $problems.Add("$name shows '$shown', expected '$expected'") }
            }
        }
    }
    # Liste de noms: the names not found, in the banner above the grid; any other search hides it. A search asking for
    # more under its field didn't run: the previous results stay, with their banner.
    $notFoundText = Find-ShownControl 'results_not_found_text'
    $notFoundSaid = if ($notFoundText) { $notFoundText.Current.Name }
    if (-not $Scenario.Message -and $notFoundSaid -ne $Scenario.NotFound) { $problems.Add("the names not found say '$notFoundSaid', expected '$($Scenario.NotFound)'") }
    if ($Scenario.Copied -and $notFoundText) {
        Set-Clipboard -Value 'avant'
        Invoke-Element (Find-Control 'results_not_found_copy')
        $notice = Wait-ActionNotice "Copié dans le presse-papiers : ✔ $($Scenario.Copied)"
        if ($notice -ne "Copié dans le presse-papiers : ✔ $($Scenario.Copied)") { $problems.Add("after Copier, the notice says '$notice'") }
        $copied = @(Get-Clipboard | Where-Object { $_ }) -join ' | '
        if ($copied -ne $Scenario.Copied) { $problems.Add("Copier copied '$copied', expected '$($Scenario.Copied)'") }
    }
    if ($Scenario.Empty) {
        # What the empty grid says.
        $empty = (Find-Control 'grid_empty_text').Current.Name
        if ($empty -ne $Scenario.Empty) { $problems.Add("the empty grid says '$empty', expected '$($Scenario.Empty)'") }
    }
    if ($Scenario.ContainsKey('TermEnabled')) {
        # A box the type doesn't use is collapsed, out of UI Automation's tree.
        $termBox = $window.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'search_term'))
        $termEnabled = [bool]($termBox -and -not $termBox.Current.IsOffscreen)
        if ($termEnabled -ne $Scenario.TermEnabled) { $problems.Add("term box shown is $termEnabled, expected $($Scenario.TermEnabled)") }
    }

    if ($ScreenshotDirectory) { Save-Screenshot ('{0:00}-{1}' -f $Number, ($Scenario.Name -replace '[^\w]+', '-')) }
    Write-Result $Scenario.Name $problems
}

function Get-ColumnHeader {
    $isHeader = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::HeaderItem)
    (@((Find-Control 'data_grid').FindAll($Descendants, $isHeader) | ForEach-Object { $_.Current.Name } | Where-Object { $_ })) -join ', '
}

$script:StrictErrorFiles = [System.Collections.Generic.List[string]]::new()

function Show-StrictError {
    # Repère's errors in strict mode, from the files of each start: one line each, where it happened (file:line) and its
    # message, then how many times. A check of its own, failed when there are any.
    $seen = [ordered]@{}
    foreach ($file in $script:StrictErrorFiles) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        # pwsh writes its redirected errors in the console's code page (850 on a French Windows).
        $lines = @(Get-Content -LiteralPath $file -Encoding ([System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)))
        for ($i = 0; $i -lt $lines.Count; $i++) {
            # Repère's own line for an error it caught (Strict: file:line message), or PowerShell's for one it didn't,
            # its message after the underline (~~~) of the code.
            if ($lines[$i] -match '^Strict: (?<where>.+\.ps1:\d+) (?<text>.*)$') {
                $where = Split-Path $Matches.where -Leaf
                $message = $Matches.text.Trim()
            }
            elseif ($lines[$i] -match '^[\w-]+: (?<where>.+\.ps1:\d+)\s*$') {
                $where = Split-Path $Matches.where -Leaf
                $message = ''
                for ($j = $i + 1; $j -lt [Math]::Min($i + 8, $lines.Count) - 1; $j++) {
                    if ($lines[$j] -like '*~*' -and $lines[$j + 1] -match '^\s+\|\s+(?<text>.+)$') { $message = $Matches.text.Trim(); break }
                }
            }
            else { continue }
            $key = "$where  $message"
            $seen[$key] = 1 + $(if ($seen.Contains($key)) { $seen[$key] } else { 0 })
        }
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
    }
    $script:checks++
    if (-not $seen.Count) { Write-Host 'PASS  Strict mode: Repère wrote no error'; return }
    $script:failed++
    Write-Host "FAIL  Strict mode: Repère wrote $($seen.Count) distinct error(s)" -ForegroundColor Red
    foreach ($key in $seen.Keys) { Write-Host "      $key$(if ($seen[$key] -gt 1) { "  ($($seen[$key]) times)" })" }
}

$wantedSessions = $Only
function Test-Session([string]$Name) {
    # Whether this session runs: every one, or those of -Only.
    $runs = -not $wantedSessions -or $wantedSessions -contains $Name
    if ($runs) { $script:currentSession = $Name }
    $runs
}

$previousLog = $env:REPERE_FAKEAD_LOG
$previousNoCommonOU = $env:REPERE_FAKEAD_NO_COMMON_OU
$previousUnreachable = $env:REPERE_FAKEAD_UNREACHABLE
$previousSlow = $env:REPERE_FAKEAD_SLOW
$previousSpecsDelay = $env:REPERE_FAKEAD_SPECS_DELAY
# Exporter saves here instead of asking where.
$previousExportPath = $env:REPERE_EXPORT_PATH
$previousStrict = $env:REPERE_STRICT
if ($Strict) { $env:REPERE_STRICT = '1' }
$exportFile = Join-Path ([IO.Path]::GetTempPath()) "repere-export-$PID.csv"
$env:REPERE_EXPORT_PATH = $exportFile
$env:REPERE_FAKEAD_LOG = $queryLog
Remove-Item $queryLog -ErrorAction SilentlyContinue
# Repère reads and saves its Apparence settings in %APPDATA%\Repere: an empty folder of its own keeps the user's
# settings out of the tests, and the tests out of the user's settings.
$previousAppData = $env:APPDATA
$testAppData = Join-Path ([IO.Path]::GetTempPath()) "repere-appdata-$PID"
$appearanceFile = Join-Path $testAppData 'Repere\apparence.json'
Remove-Item $testAppData -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $testAppData | Out-Null
$env:APPDATA = $testAppData
$pwsh = (Get-Process -Id $PID).Path
$app = $null
$window = $null
$checks = 0
$failed = 0
$desktopProblem = $null
$currentSession = $null
try {
    if (Test-Session 'Search') {
        Start-App
        $startProblems = [System.Collections.Generic.List[string]]::new()
        if (-not $window.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::NameProperty, 'AD fictif'))) {
            $startProblems.Add("no 'AD fictif' label")
        }
        $initialLabel = (Find-Control 'results_count').Current.Name
        if ($initialLabel) { $startProblems.Add("before any search, the label is '$initialLabel', expected nothing") }
        $headers = Get-ColumnHeader
        $expectedHeaders = 'Compte, Nom, Description, Dernière connexion, Système, Domaine, Emplacement'
        if ($headers -ne $expectedHeaders) { $startProblems.Add("columns are: $headers; expected: $expectedHeaders") }
        $selectedDomain = Get-ComboText 'domain'
        if ($selectedDomain -ne 'demo.local') { $startProblems.Add("Domaine list starts on '$selectedDomain', expected the user's domain, demo.local") }
        Write-Result 'Window opens on the fake AD, with every column, the user''s domain and 0 ordinateur' $startProblems

        $number = 0
        foreach ($scenario in $scenarios) {
            $number++
            Test-Scenario $scenario $number
        }

        # The OUs a name finds rarely change, so Repère looks them up once per domain and name, on the first search
        # there: Communs in both domains, Labo in demo.local.
        $lookups = @(Get-LoggedQuery | Where-Object Command -eq 'Get-ADOrganizationalUnit')
        $lookupProblems = [System.Collections.Generic.List[string]]::new()
        $lookedUp = (@($lookups | ForEach-Object { "$($_.Filter) on $($_.Server)" }) | Sort-Object) -join ' | '
        $expected = "Name -like 'Communs*' on demo.local | Name -like 'Communs*' on nord.demo.local | Name -like 'Labo*' on demo.local"
        if ($lookedUp -ne $expected) { $lookupProblems.Add("OU lookups: $lookedUp; expected: $expected") }
        Write-Result 'OU nommées looks the OUs up once per domain and name per session' $lookupProblems
        Test-ActionBar
        Test-TitleBar
        Test-ActionLabel
        Test-FilterBox
        Test-EmptySearch
        Test-NotFoundWidth
        Test-Export
        Stop-App
    }

    if (Test-Session 'Address') {
        Start-App '-ExtraFakeComputers 301'
        foreach ($scenario in $addressScenarios) {
            $number++
            Test-Scenario $scenario $number
        }
        Stop-App
    }

    if (Test-Session 'Unreachable') {
        $env:REPERE_FAKEAD_NO_COMMON_OU = '1'
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        Start-App
        foreach ($scenario in $secondSessionScenarios) {
            $number++
            Test-Scenario $scenario $number
        }
        Stop-App
        $env:REPERE_FAKEAD_NO_COMMON_OU = $previousNoCommonOU
        $env:REPERE_FAKEAD_UNREACHABLE = $previousUnreachable
    }

    if (Test-Session 'Parallel') {
        # The searches run in the background, one domain per runspace. With slow domains: both searched at once, a LAPS
        # password read without freezing the window, then a window that stays usable during a search, which can be
        # cancelled.
        $env:REPERE_FAKEAD_SLOW = 'demo.local=2000;nord.demo.local=2000'
        Start-App
        Test-ParallelSearch
        Stop-App
        $env:REPERE_FAKEAD_SLOW = 'nord.demo.local=8000'
        Start-App
        Test-SearchCancel
        Stop-App
        $env:REPERE_FAKEAD_SLOW = $previousSlow
    }

    if (Test-Session 'Actions') {
        # Utilisateurs connectés… gives each computer 3 s, and ORD-12's quser doesn't answer.
        $env:REPERE_SESSION_TIMEOUT = '3'
        $env:REPERE_FAKEAD_QUSER_HANG = 'ord-12.demo.local'
        Start-App
        Test-ResultMenu
        Test-SpecsWindow
        Test-GroupsDialog
        Test-ShadowSession
        Test-Shortcut
        # Last: it moves computers.
        Test-MoveDialog
        Stop-App
        $env:REPERE_SESSION_TIMEOUT = $null
        $env:REPERE_FAKEAD_QUSER_HANG = $null
    }

    if (Test-Session 'SpecsDelay') {
        # Every CIM query of the Caractéristiques window takes 400 ms: a reading lasts several seconds. This session also
        # limits Déplacer vers… to Postes and the OUs under it.
        $env:REPERE_FAKEAD_SPECS_DELAY = '400'
        Start-App '-MoveRoots "OU=Postes,DC=demo,DC=local"'
        Test-SpecsCancel
        Test-MoveRoot
        Test-MoveRootImposed
        Stop-App
        $env:REPERE_FAKEAD_SPECS_DELAY = $previousSpecsDelay
    }

    if (Test-Session 'MoveRootsLong') {
        $env:REPERE_FAKEAD_EXTRA_OUS = '40'
        $env:REPERE_FAKEAD_SLOW = 'nord.demo.local=1500'
        $longRoots = (@(1..20 | ForEach-Object { 'OU=Site-{0:00},OU=Postes,DC=nord,DC=demo,DC=local' -f $_ }) + 'OU={Bureau-1,DC=nord,DC=demo,DC=local') -join ';'
        Start-App "-MoveRoots `"$longRoots`""
        Test-MoveRootLong
        Stop-App
        $env:REPERE_FAKEAD_EXTRA_OUS = $null
        $env:REPERE_FAKEAD_SLOW = $previousSlow
    }

    if (Test-Session 'SingleDomain') {
        # With a single domain in -Domains, there's nothing to choose: no Domaine list or column.
        Start-App '-Domains nord.demo.local'
        $singleProblems = [System.Collections.Generic.List[string]]::new()
        if ($window.FindFirst($Descendants, [System.Windows.Automation.PropertyCondition]::new($AE::AutomationIdProperty, 'domain'))) {
            $singleProblems.Add('the Domaine list is shown')
        }
        $headers = Get-ColumnHeader
        $expectedHeaders = 'Compte, Nom, Description, Dernière connexion, Système, Emplacement'
        if ($headers -ne $expectedHeaders) { $singleProblems.Add("columns are: $headers; expected: $expectedHeaders") }
        Write-Result 'With a single domain, no Domaine list or column' $singleProblems
        $number++
        Test-Scenario $singleDomainScenario $number
        Stop-App
    }

    if (Test-Session 'Appearance') {
        # From no settings at all: the sessions before this one save apparence.json too (the columns of the Utilisateurs
        # page, once it has been shown), and the first checks expect that nothing has been saved yet.
        Remove-Item $appearanceFile -ErrorAction SilentlyContinue
        Start-App
        Test-Appearance
        Stop-App
    }

    if (Test-Session 'Column') {
        # The columns, saved in apparence.json: last, from no settings at all.
        Remove-Item $appearanceFile -ErrorAction SilentlyContinue
        Start-App
        Test-Column
        Test-ColumnFilter
        Stop-App
    }

    if (Test-Session 'Restart') {
        # Redémarrer…, whose defaults are saved in redemarrage.json.
        Start-App
        Test-RestartDialog
        Stop-App
    }

    if (Test-Session 'Safeguards') {
        # What Repère never does to a domain controller, the computer it runs on, or the account running it.
        # SALLE-REU2: ORD-10's account, whose CN was renamed in ADUC. Repère must know it by its account, not its name.
        $env:REPERE_FAKEAD_COMPUTER = 'SALLE-REU2.demo.local'
        $env:REPERE_FAKEAD_USER = 'jebertrand@demo.local'
        $env:REPERE_TYPE_TO_CONFIRM_ABOVE = '2'
        Start-App
        Test-Safeguard
        Stop-App
        $env:REPERE_FAKEAD_COMPUTER = $null
        $env:REPERE_FAKEAD_USER = $null
        $env:REPERE_TYPE_TO_CONFIRM_ABOVE = $null
        # Then with nord.demo.local slow: the guard asks AD without freezing the window.
        $env:REPERE_FAKEAD_SLOW = 'nord.demo.local=2000'
        Start-App
        Test-SafeguardInBackground
        Stop-App
        $env:REPERE_FAKEAD_SLOW = $previousSlow
    }

    if (Test-Session 'Advanced') {
        # Recherche avancée: its popup and the OU tree it opens.
        Start-App
        Test-AdvancedSearch
        Stop-App
    }

    if (Test-Session 'SearchMemory') {
        # The search settings and recent searches, saved in recherche.json.
        Start-App
        Test-SearchMemory
        Stop-App
    }

    if (Test-Session 'UserPage') {
        # Utilisateurs: the users' page, in a session of its own (it unlocks and resets passwords).
        Start-App
        Test-UserPage
        Stop-App
        # Then with nord.demo.local down: a list searched in every domain.
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        Start-App
        Test-UserListUnanswered
        Stop-App
        $env:REPERE_FAKEAD_UNREACHABLE = $previousUnreachable
        # Then with nord.demo.local slow: a search there replaced by a recent search, or Entrée.
        $env:REPERE_FAKEAD_SLOW = 'nord.demo.local=8000'
        Start-App
        Test-UserSearchReplace
        Stop-App
        $env:REPERE_FAKEAD_SLOW = $previousSlow
    }

    if (Test-Session 'UserDetail') {
        # Propriétés of a user: lockout, groups and expiration, from the fake AD as it starts.
        Start-App
        Test-UserDetail
        Stop-App
    }

    if (Test-Session 'GroupPage') {
        # Groupes: the groups' page and a group's Propriétés (its members added and removed), from the fake AD as it starts.
        Start-App
        Test-GroupPage
        Stop-App
        # Then with nord.demo.local down: a list searched in every domain.
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        Start-App
        Test-GroupListUnanswered
        Stop-App
        $env:REPERE_FAKEAD_UNREACHABLE = $previousUnreachable
    }

    if ($wantedSessions -contains 'Shadow') {
        # Prendre la main… and Utilisateurs connectés… alone, as Actions sets them up. Only with -Only: Actions runs them
        # already.
        $env:REPERE_SESSION_TIMEOUT = '3'
        $env:REPERE_FAKEAD_QUSER_HANG = 'ord-12.demo.local'
        Start-App
        Test-ShadowSession
        Stop-App
        $env:REPERE_SESSION_TIMEOUT = $null
        $env:REPERE_FAKEAD_QUSER_HANG = $null
    }
    if ($wantedSessions -contains 'Remote') {
        # The remote actions alone, for a change to them: Vérifier en ligne, Forcer les stratégies and PowerShell à
        # distance, on computers that answer and on ones that don't. Only with -Only: Actions runs them already.
        Start-App
        Test-RemoteActions $script:ResultMenuItems
        # Then its prompts to turn WinRM on, at larger text sizes.
        Test-WinRMPromptFit $script:ResultMenuItems[12]
        Stop-App
    }

    if (Test-Session 'WinRMError') {
        # Activer WinRM when a step fails once WinRM is on (#316).
        # Each CIM query takes 1.5 s, so the notice shown while WinRM is turned on can be seen.
        $env:REPERE_FAKEAD_WINRM_ON_ERROR = '1'
        $env:REPERE_FAKEAD_SPECS_DELAY = '1500'
        Start-App
        Test-WinRMEnableError $script:ResultMenuItems[12]
        Stop-App
        $env:REPERE_FAKEAD_WINRM_ON_ERROR = $null
        $env:REPERE_FAKEAD_SPECS_DELAY = $previousSpecsDelay
    }

    if (Test-Session 'Specs') {
        # Caractéristiques alone (Actions runs it too, after the right-click menu): for a change to that window.
        Start-App
        Test-SpecsWindow
        Stop-App
    }

    if (Test-Session 'Limit') {
        # The searches' limit, 1 instead of 2 000 (the sample data is small): each page says it was reached, and Tout
        # afficher runs the same search without it.
        $previousLimit = $env:REPERE_SEARCH_LIMIT
        $env:REPERE_SEARCH_LIMIT = '1'
        Start-App
        Test-SearchLimit
        Stop-App
        # Then with nord.demo.local slow: a search there cancelled before it answers.
        $env:REPERE_FAKEAD_SLOW = 'nord.demo.local=8000'
        Start-App
        Test-ShowAllAfterCancel
        Stop-App
        $env:REPERE_FAKEAD_SLOW = $previousSlow
        $env:REPERE_SEARCH_LIMIT = $previousLimit
    }

    if (Test-Session 'Settings') {
        # Paramètres: Déplacer vers (parametres.json) and Raccourcis; SCCM and Redémarrage are SettingsSave. GitHub's latest
        # release is given: a newer Repère than any.
        $env:REPERE_UPDATE_RELEASE = '{"tag_name":"v99.0.0","html_url":"https://github.com/reperedev/Repere/releases/tag/v99.0.0"}'
        Start-App
        Test-SettingsWindow
        Stop-App
        $env:REPERE_UPDATE_RELEASE = $null
    }

    if (Test-Session 'Changelog') {
        # Nouveautés (#9): started as after an update from the version before this one (CHANGELOG.md's second entry);
        # it shows the first entry's sections.
        $changelogLines = [System.IO.File]::ReadAllLines((Join-Path (Split-Path $PSScriptRoot) 'CHANGELOG.md'))
        $changelogStarts = @(for ($i = 0; $i -lt $changelogLines.Count; $i++) { if ($changelogLines[$i] -match '^## \d+\.\d+\.\d+\b') { $i } })
        $changelogVersions = @($changelogStarts | ForEach-Object { [regex]::Match($changelogLines[$_], '\d+\.\d+\.\d+').Value })
        $changelogSections = @($changelogLines[$changelogStarts[0]..$changelogStarts[1]] | Where-Object { $_ -match '^### ' } | ForEach-Object { $_.Substring(4).Trim() })
        $env:REPERE_CHANGELOG_SEEN = $changelogVersions[1]
        Start-App
        Test-Changelog $changelogVersions[0] $changelogSections
        Test-ChangelogFit
        Stop-App
        Remove-Item $appearanceFile -ErrorAction SilentlyContinue
        $env:REPERE_CHANGELOG_SEEN = $null
    }

    if (Test-Session 'SettingsSave') {
        # Paramètres › SCCM (parametres.json, the fake SCCM's site saved first) and Redémarrage (redemarrage.json).
        Remove-Item (Join-Path $env:APPDATA 'Repere\redemarrage.json') -ErrorAction SilentlyContinue
        # First a parametres.json that can't be read, then the fake SCCM's site over it.
        New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA 'Repere') | Out-Null
        Set-Content (Join-Path $env:APPDATA 'Repere\parametres.json') $script:BrokenSettings -Encoding utf8
        Start-App -KeepSettings
        Test-UnreadableSetting
        Stop-App
        Set-SccmSetting 'DEM' 'sccm.demo.local'
        Start-App -KeepSettings
        Test-SettingsSaving
        Stop-App
    }

    if (Test-Session 'Copy') {
        Start-App
        Test-Copy
        Stop-App
    }

    if (Test-Session 'CopyButton') {
        # The copy buttons of Clés BitLocker, Supprimer de l'AD, Mot de passe LAPS and Propriétés.
        Start-App
        Test-CopyButton
        Stop-App
    }

    if (Test-Session 'UnusedBox') {
        # The boxes a choice makes useless: Ordinateurs, Nouveau mot de passe, Prochain nom.
        Start-App
        Test-UnusedBox
        Stop-App
    }

    if (Test-Session 'BitLocker') {
        # Clés BitLocker for several computers, some without a key.
        Start-App
        Test-BitLockerNote
        Stop-App
    }

    if (Test-Session 'NextName') {
        # Prochain nom…: without SCCM, with many domains, with the fake SCCM's site, then with it and a domain down.
        Start-App
        Test-NextName
        Test-NextNameWindow
        Stop-App
        Start-App '-Domains demo.local,nord.demo.local,a.demo.local,b.demo.local,c.demo.local'
        Test-NextNameDomains
        Stop-App
        Remove-Item (Join-Path $env:APPDATA 'Repere\prochainnom.json') -ErrorAction SilentlyContinue
        Set-SccmSetting 'DEM' 'sccm.demo.local'
        Start-App -KeepSettings
        Test-NextNameSccm
        Stop-App
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        Start-App -KeepSettings
        Test-NextNameFailure
        Stop-App
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $previousUnreachable
    }

    if (Test-Session 'Density') {
        # Densité, saved in apparence.json: from no settings at all.
        Remove-Item $appearanceFile -ErrorAction SilentlyContinue
        Start-App
        Test-Density
    }
}
catch {
    # An unusable desktop is reported below, once Repère is closed; any other error is the script's own.
    if (-not $desktopProblem) { throw }
}
finally {
    Stop-App
    Remove-Item $queryLog -ErrorAction SilentlyContinue
    $env:APPDATA = $previousAppData
    Remove-Item $testAppData -Recurse -Force -ErrorAction SilentlyContinue
    $env:REPERE_FAKEAD_LOG = $previousLog
    $env:REPERE_FAKEAD_NO_COMMON_OU = $previousNoCommonOU
    $env:REPERE_FAKEAD_UNREACHABLE = $previousUnreachable
    $env:REPERE_FAKEAD_SLOW = $previousSlow
    $env:REPERE_FAKEAD_SPECS_DELAY = $previousSpecsDelay
    $env:REPERE_EXPORT_PATH = $previousExportPath
    $env:REPERE_STRICT = $previousStrict
    Remove-Item $exportFile -ErrorAction SilentlyContinue
}

if ($desktopProblem) {
    # One message instead of the failures a locked or disconnected desktop would cause: the checks that ran before it
    # are real, the one it interrupted and those after it didn't run.
    Write-Host ''
    Write-Host "STOPPED  The desktop can't be used for the UI tests: $desktopProblem." -ForegroundColor Yellow
    Write-Host "         The run stopped in the $currentSession session, after $checks checks ($($checks - $failed) passed); what it hadn't run yet says nothing about Repère."
    Write-Host '         Unlock the screen or reconnect the session, leave the desktop alone, then run the tests again. To run only the session it stopped in:'
    Write-Host "         pwsh -NoProfile -File tests\Test-RepereUI.ps1 -Only $currentSession"
    exit 2
}
if ($Strict) { Show-StrictError }
Write-Host ''
Write-Host "$($checks - $failed)/$checks passed" -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
exit [int]($failed -gt 0)
