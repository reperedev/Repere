# Runs, against a real domain, the Active Directory commands Repère's Utilisateurs and Groupes use, and a computer's
# groups, LAPS and BitLocker reads, with the same parameters, and says for each whether it works and how long it took:
# what the UI tests can't check, as they run on the fake AD. Read only, unless -Write is given with a test account and
# a test group (unlock, disable and enable, expiration, membership, and with -ResetPassword a new password).
#
# Nothing secret is shown or saved: no password (the one -ResetPassword sets is random and never printed), no LAPS
# password, no BitLocker key: only whether one exists and can be read. Names and paths of AD objects are shown: remove what you don't want to share before
# pasting the report.
#
#   .\tests\Test-RepereAD.ps1 -User jbertrand -Group GG-Accueil
#   .\tests\Test-RepereAD.ps1 -User jbertrand -Group GG-Accueil -Write -TestUser test.repere -TestGroup GG-Test-Repere
#   .\tests\Test-RepereAD.ps1 -FakeAD          (the same checks on the fake AD, to try the script itself)
[CmdletBinding()]
param(
    # A user to read (login), and a group whose name contains this text.
    [string]$User = $env:USERNAME,
    [string]$Group = 'Utilisateurs du domaine',
    # A computer to read its groups, LAPS and BitLocker (its name); the computer running the script by default.
    [string]$Computer = $env:COMPUTERNAME,
    # The domain searched; the user's by default.
    [string]$Domain,
    # Changes, on these only: a test account (login) and a test group (name), made for the purpose.
    [switch]$Write,
    [string]$TestUser,
    [string]$TestGroup,
    # With -Write: also resets the test account's password (random, never shown; to be changed at the next logon).
    [switch]$ResetPassword,
    # The fake AD instead of a real domain.
    [switch]$FakeAD,
    # Where the report is also saved, as text.
    [string]$Report = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('Repere_verification_{0:yyyy-MM-dd_HHmm}.txt' -f (Get-Date)))
)

$ErrorActionPreference = 'Stop'
if ($Write -and (-not $TestUser -or -not $TestGroup)) { throw '-Write needs -TestUser and -TestGroup: an account and a group made for testing.' }
if ($FakeAD) { Import-Module (Join-Path $PSScriptRoot '..\src\FakeAD\FakeAD.psm1') -Force } else { Import-Module ActiveDirectory }

$lines = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()

function Write-Line([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    $lines.Add($Text)
}

function Invoke-Step([string]$Name, [scriptblock]$Step) {
    # One check: its result's summary (what the step returns), or its error; and its time.
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $detail = & $Step
        $watch.Stop()
        $results.Add([pscustomobject]@{ Name = $Name; Ok = $true })
        Write-Line ("OK     {0,6} ms  {1}{2}" -f $watch.ElapsedMilliseconds, $Name, $(if ($detail) { " : $detail" })) 'Green'
    }
    catch {
        $watch.Stop()
        $results.Add([pscustomobject]@{ Name = $Name; Ok = $false })
        Write-Line ("ÉCHEC  {0,6} ms  {1} : {2}" -f $watch.ElapsedMilliseconds, $Name, $_.Exception.Message) 'Red'
    }
}

function Get-LdapText([string]$Text) {
    # As UserPage.ps1 escapes a value in an LDAP filter.
    $Text.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
}

function Get-DomainOfDN([string]$DistinguishedName) {
    (@($DistinguishedName -split '(?<!\\),' | Where-Object { $_ -like 'DC=*' } | ForEach-Object { $_.Substring(3) })) -join '.'
}

# What Repère reads, as in UserPage.ps1 (the search) and UserDetails.ps1 (Propriétés).
$searchProperties = 'DisplayName', 'GivenName', 'Surname', 'mail', 'Title', 'Department', 'Description', 'Enabled', 'LockedOut', 'LastLogonDate',
                    'PasswordExpired', 'PasswordNeverExpires', 'PasswordLastSet', 'msDS-UserPasswordExpiryTimeComputed', 'UserPrincipalName'
$detailProperties = 'DisplayName', 'GivenName', 'Surname', 'UserPrincipalName', 'mail', 'EmployeeID', 'Title', 'Department', 'Company', 'Office', 'Manager',
                    'OfficePhone', 'MobilePhone', 'Description', 'Enabled', 'LockedOut', 'AccountLockoutTime', 'badPwdCount', 'LastBadPasswordAttempt',
                    'LastLogonDate', 'PasswordLastSet', 'PasswordExpired', 'PasswordNeverExpires', 'msDS-UserPasswordExpiryTimeComputed',
                    'AccountExpirationDate', 'whenCreated', 'whenChanged', 'HomeDirectory', 'HomeDrive', 'ProfilePath', 'ScriptPath', 'MemberOf',
                    'PrimaryGroup', 'tokenGroups'

Write-Line "Vérification de Repère sur l'AD — $(Get-Date -Format 'yyyy-MM-dd HH:mm'), PowerShell $($PSVersionTable.PSVersion)$(if ($FakeAD) { ', AD fictif' })" 'Cyan'
Write-Line "Lecture seule : $(-not $Write)" 'Cyan'
Write-Line ''

# The forest, the domain and its PDC.
$state = @{ Domains = @(); Pdc = $null; User = $null; Group = $null; Catalog = $null; Computer = $null; PrimaryRids = @() }
Invoke-Step 'Get-ADForest : les domaines de la forêt' {
    $forest = Get-ADForest
    $state.Domains = @($forest.Domains | ForEach-Object { [string]$_ })
    if (-not $Domain) { $script:Domain = if ($FakeAD) { 'demo.local' } else { [string](Get-ADDomain).DNSRoot } }
    "$($state.Domains.Count) domaine(s) : $($state.Domains -join ', ')"
}
if (-not $Domain) { $Domain = 'demo.local' }
$others = @($state.Domains | Where-Object { $_ -ne $Domain })
Invoke-Step "Get-ADDomain -Server $Domain : le PDC (Verrouillage y est lu)" {
    $state.Pdc = [string](Get-ADDomain -Server $Domain).PDCEmulator
    $state.Pdc
}
Invoke-Step 'Get-ADDefaultDomainPasswordPolicy : la stratégie de verrouillage' {
    $policy = Get-ADDefaultDomainPasswordPolicy -Server $Domain
    "seuil $($policy.LockoutThreshold), durée $($policy.LockoutDuration), fenêtre $($policy.LockoutObservationWindow)"
}

Write-Line ''
Write-Line 'Utilisateurs' 'Cyan'
Invoke-Step "Recherche (anr=$User), avec les propriétés de la grille" {
    $found = @(Get-ADUser -Server $Domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(anr=$(Get-LdapText $User)))" -Properties $searchProperties)
    $state.User = $found | Where-Object SamAccountName -eq $User | Select-Object -First 1
    if (-not $state.User) { $state.User = $found | Select-Object -First 1 }
    $missing = @($searchProperties | Where-Object { $state.User -and -not $state.User.PSObject.Properties[$_] })
    "$($found.Count) trouvé(s)$(if ($missing) { " ; propriétés absentes : $($missing -join ', ')" })"
}
Invoke-Step "Recherche par identifiant (sAMAccountName=$User), comme Utilisateurs connectés…" {
    $found = @(Get-ADUser -Server $Domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$(Get-LdapText $User)))" -Properties $searchProperties)
    "$($found.Count) trouvé(s)"
}
Invoke-Step 'Recherche Verrouillés (lockoutTime>=1)' { "$(@(Get-ADUser -Server $Domain -LDAPFilter '(&(objectCategory=person)(objectClass=user)(lockoutTime>=1))' -Properties LockedOut | Where-Object LockedOut).Count) compte(s) verrouillé(s)" }
Invoke-Step 'Recherche Désactivés (userAccountControl, bit 2)' { "$(@(Get-ADUser -Server $Domain -LDAPFilter '(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2))').Count) compte(s)" }
if ($state.User) {
    $userDn = [string]$state.User.DistinguishedName
    Invoke-Step "Propriétés de $($state.User.SamAccountName), lues sur le PDC (tokenGroups compris)" {
        $detail = Get-ADUser -Server $(if ($state.Pdc) { $state.Pdc } else { $Domain }) -Identity $userDn -Properties $detailProperties
        $state.UserDetail = $detail
        "MemberOf : $(@($detail.MemberOf).Count), tokenGroups : $(@($detail.tokenGroups).Count), mauvais mots de passe : $($detail.badPwdCount), expiration du mot de passe : $(if ($detail.'msDS-UserPasswordExpiryTimeComputed') { 'lue' } else { 'absente' })"
    }
    Invoke-Step 'Ses groupes directs, lus un par un (Get-ADGroup -Identity)' {
        $read = foreach ($dn in @($state.UserDetail.MemberOf)) { $null = Get-ADGroup -Server (Get-DomainOfDN $dn) -Identity $dn -Properties Description; 1 }
        "$(@($read).Count) groupe(s)"
    }
    Invoke-Step 'Ses groupes hérités (tokenGroups), résolus dans son domaine' {
        $unresolved = 0
        foreach ($sid in @($state.UserDetail.tokenGroups)) { try { $null = Get-ADGroup -Server $Domain -Identity ([string]$sid) } catch { $unresolved++ } }
        "$(@($state.UserDetail.tokenGroups).Count) SID, $unresolved non résolu(s) dans $Domain"
    }
    foreach ($other in $others) {
        Invoke-Step "Groupes de $other qui le listent (member=…)" { "$(@(Get-ADGroup -Server $other -LDAPFilter "(member=$(Get-LdapText $userDn))" -Properties Description).Count) groupe(s)" }
    }
}

Write-Line ''
Write-Line 'Groupes' 'Cyan'
Invoke-Step "Recherche (name=*$Group*), avec les propriétés de la grille" {
    $found = @(Get-ADGroup -Server $Domain -LDAPFilter "(&(objectCategory=group)(name=*$(Get-LdapText $Group)*))" -Properties Description, mail, ManagedBy)
    $state.Group = $found | Where-Object Name -eq $Group | Select-Object -First 1
    if (-not $state.Group) { $state.Group = $found | Select-Object -First 1 }
    "$($found.Count) trouvé(s)"
}
# Sans membres: the primary groups in use are read first (the accounts whose primary group is unusual: every account is
# read on the DC; then one account at most for each usual one), and the groups that are one of them aren't shown. An
# account sent without primaryGroupID is one whose primary group can't be read: Repère then fails the search.
Invoke-Step 'Sans membres : comptes dont le groupe principal est inhabituel (le DC lit tous les comptes)' {
    $accounts = @(Get-ADObject -Server $Domain -LDAPFilter '(&(objectClass=user)(!(primaryGroupID=513))(!(primaryGroupID=515))(!(primaryGroupID=516))(!(primaryGroupID=521)))' -Properties primaryGroupID)
    $unreadable = @($accounts | Where-Object { "$($_.primaryGroupID)" -eq '' })
    $state.PrimaryRids = @($accounts | Where-Object { "$($_.primaryGroupID)" -ne '' } | ForEach-Object { "$($_.primaryGroupID)" } | Sort-Object -Unique)
    "$($accounts.Count) compte(s), groupes principaux : $(if ($state.PrimaryRids) { $state.PrimaryRids -join ', ' } else { 'aucun' }), illisibles : $($unreadable.Count)"
}
Invoke-Step 'Sans membres : un compte au plus par groupe principal habituel (513, 515, 516, 521)' {
    $used = @(foreach ($rid in '513', '515', '516', '521') { if (@(Get-ADObject -Server $Domain -LDAPFilter "(&(objectClass=user)(primaryGroupID=$rid))" -ResultSetSize 1).Count) { $rid } })
    $state.PrimaryRids = @($state.PrimaryRids) + $used
    "utilisés : $($used -join ', ')"
}
Invoke-Step 'Recherche Sans membres (!(member=*)), sans les groupes principaux' {
    $found = @(Get-ADGroup -Server $Domain -LDAPFilter '(&(objectCategory=group)(!(member=*)))')
    $primary = @($found | Where-Object { "$($_.SID)" -match '^S-1-5-21-.+-(\d+)$' -and @($state.PrimaryRids) -contains $Matches[1] })
    "$($found.Count - $primary.Count) groupe(s), sans $($primary.Count) groupe(s) principal(aux) : $(($primary | ForEach-Object Name) -join ', ')"
}
if ($state.Group) {
    $groupDn = [string]$state.Group.DistinguishedName
    Invoke-Step "Propriétés de $($state.Group.Name) (sans tokenGroups ni la liste des membres)" {
        $state.GroupDetail = Get-ADGroup -Server $Domain -Identity $groupDn -Properties Description, mail, ManagedBy, whenCreated, whenChanged, MemberOf
        "$($state.GroupDetail.GroupScope), $($state.GroupDetail.GroupCategory), MemberOf : $(@($state.GroupDetail.MemberOf).Count)"
    }
    Invoke-Step 'Ses membres : (memberOf=…), 201 au plus' {
        $members = @(Get-ADObject -Server $Domain -LDAPFilter "(&(memberOf=$(Get-LdapText $groupDn)))" -Properties sAMAccountName -ResultSetSize 201)
        "$($members.Count)$(if ($members.Count -gt 200) { ' (plus de 200 : la liste dit de chercher)' }) ; types : $((@($members | Group-Object ObjectClass | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', ')"
    }
    Invoke-Step 'Ses membres dont le nom commence par « a » (anr), 201 au plus' {
        "$(@(Get-ADObject -Server $Domain -LDAPFilter "(&(memberOf=$(Get-LdapText $groupDn))(anr=a))" -Properties sAMAccountName -ResultSetSize 201).Count)"
    }
    Invoke-Step 'Ceux dont c''est le groupe principal (primaryGroupID), 201 au plus' {
        $rid = ([string]$state.Group.SID -split '-')[-1]
        "RID $rid : $(@(Get-ADObject -Server $Domain -LDAPFilter "(&(primaryGroupID=$rid))" -Properties sAMAccountName -ResultSetSize 201).Count)"
    }
    Invoke-Step 'tokenGroups sur un groupe (Repère ne le lit plus pour un groupe : pour information)' {
        "$(@((Get-ADGroup -Server $Domain -Identity $groupDn -Properties tokenGroups).tokenGroups).Count) SID"
    }
    foreach ($other in $others) {
        Invoke-Step "Groupes de $other qui listent ce groupe (member=…)" { "$(@(Get-ADGroup -Server $other -LDAPFilter "(member=$(Get-LdapText $groupDn))").Count) groupe(s)" }
    }
}

# Across domains: a global catalog, a universal group's members through it, a domain local group's member list.
if ($others.Count) {
    Write-Line ''
    Write-Line 'Plusieurs domaines' 'Cyan'
    Invoke-Step 'Get-ADDomainController -Discover -Service GlobalCatalog' {
        $state.Catalog = "$(@((Get-ADDomainController -Discover -Service GlobalCatalog).HostName)[0]):3268"
        $state.Catalog
    }
    # One group of each scope, from whichever domain has one.
    $pick = {
        param([int]$Bit)
        @(foreach ($searched in @($Domain) + $others) {
            try { Get-ADGroup -Server $searched -LDAPFilter "(&(objectCategory=group)(groupType:1.2.840.113556.1.4.803:=$Bit))" -ResultSetSize 1 } catch { Write-Verbose "$searched : $_" }
        }) | Select-Object -First 1
    }
    $universal = & $pick 8
    if (-not $universal) { Write-Line "INFO              aucun groupe universel : la recherche sur le catalogue global n'est pas essayée" 'Yellow' }
    if ($state.Catalog -and $universal) {
        Invoke-Step "Membres de $($universal.Name) (universel) sur le catalogue global, toute la forêt (-SearchBase '')" {
            $members = @(Get-ADObject -Server $state.Catalog -SearchBase '' -LDAPFilter "(&(memberOf=$(Get-LdapText $universal.DistinguishedName)))" -Properties sAMAccountName -ResultSetSize 201)
            "$($members.Count) ; domaines : $((@($members | ForEach-Object { Get-DomainOfDN $_.DistinguishedName } | Sort-Object -Unique)) -join ', ')"
        }
    }
    $local = & $pick 4
    if ($local) {
        Invoke-Step "Liste de membres de $($local.Name) (domaine local), ceux d'autres domaines lus dans le leur" {
            $localDomain = Get-DomainOfDN $local.DistinguishedName
            $foreign = @((Get-ADGroup -Server $localDomain -Identity $local.DistinguishedName -Properties member).member | Where-Object { (Get-DomainOfDN $_) -ne $localDomain })
            foreach ($dn in @($foreign | Select-Object -First 5)) { $null = Get-ADObject -Server (Get-DomainOfDN $dn) -Identity $dn -Properties sAMAccountName }
            "$($foreign.Count) membre(s) d'autres domaines"
        }
    }
}

Write-Line ''
Write-Line 'Ajouter des membres, Ajouter à un groupe, Groupes d''un ordinateur' 'Cyan'
Invoke-Step 'Utilisateurs (anr), ordinateurs (Name -like), groupes (anr) qui commencent par « a »' {
    $users = @(Get-ADUser -Server $Domain -LDAPFilter '(&(objectCategory=person)(objectClass=user)(anr=a))').Count
    $computers = @(Get-ADComputer -Server $Domain -Filter "Name -like 'a*'").Count
    $groups = @(Get-ADGroup -Server $Domain -LDAPFilter '(&(objectCategory=group)(anr=a))').Count
    "$users utilisateur(s), $computers ordinateur(s), $groups groupe(s)"
}
Invoke-Step 'Groupes dont le nom contient « a » (Get-ADGroup -Filter, Ajouter à un groupe)' { "$(@(Get-ADGroup -Server $Domain -Filter "Name -like '*a*'" -Properties Description).Count)" }
Invoke-Step "Groupes de l'ordinateur $Computer (MemberOf, PrimaryGroup, tokenGroups)" {
    $found = Get-ADComputer -Server $Domain -Filter "Name -eq '$($Computer -replace "'", "''")'" | Select-Object -First 1
    if (-not $found) { throw "$Computer introuvable dans $Domain" }
    $state.Computer = $found
    $detail = Get-ADComputer -Server $Domain -Identity $found.DistinguishedName -Properties MemberOf, PrimaryGroup, tokenGroups
    "MemberOf : $(@($detail.MemberOf).Count), tokenGroups : $(@($detail.tokenGroups).Count)"
}

# LAPS and BitLocker, as ComputerActions.ps1 reads them: what exists and whether it can be read, never the value.
Write-Line ''
Write-Line "LAPS et BitLocker de l'ordinateur $Computer (ce qui existe et s'il est lisible, jamais la valeur)" 'Cyan'
if ($state.Computer) {
    $computerDn = [string]$state.Computer.DistinguishedName
    if (Get-Command Get-LapsADPassword -ErrorAction SilentlyContinue) {
        Invoke-Step 'Get-LapsADPassword (Windows LAPS ; le mot de passe reste chiffré en mémoire)' {
            # Without -AsPlainText: the password, if any, stays a SecureString, and only whether there is one is said.
            $laps = Get-LapsADPassword -Identity $computerDn -Domain $Domain | Select-Object -First 1
            if (-not $laps) { 'aucun' } else { "source $($laps.Source), compte $(if ($laps.Account) { 'lu' } else { 'absent' }), mot de passe $(if ($laps.Password) { 'lisible' } else { 'non lisible' }), expiration $(if ($laps.ExpirationTimestamp) { 'lue' } else { 'absente' })" }
        }
    }
    else { Write-Line 'INFO              Get-LapsADPassword absent : Repère ne lit alors que le LAPS hérité' 'Yellow' }
    Invoke-Step 'Get-ADComputer -Properties * : les attributs LAPS (hérité et Windows)' {
        $all = Get-ADComputer -Server $Domain -Identity $computerDn -Properties *
        $said = foreach ($name in 'ms-Mcs-AdmPwd', 'ms-Mcs-AdmPwdExpirationTime', 'msLAPS-PasswordExpirationTime', 'msLAPS-Password', 'msLAPS-EncryptedPassword') {
            "$name $(if ($all.PSObject.Properties[$name] -and $all.$name) { 'présent' } else { 'absent' })"
        }
        $said -join ', '
    }
    Invoke-Step "Clés BitLocker sous l'ordinateur (msFVE-RecoveryInformation, un niveau)" {
        $keys = @(Get-ADObject -Server $Domain -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -SearchBase $computerDn -SearchScope OneLevel -Properties 'msFVE-RecoveryPassword', 'msFVE-VolumeGuid')
        "$($keys.Count) clé(s), $(@($keys | Where-Object { $_.'msFVE-RecoveryPassword' }).Count) mot(s) de passe de récupération lisible(s)"
    }
}

if ($Write) {
    Write-Line ''
    Write-Line "Changements, sur $TestUser et $TestGroup seulement" 'Yellow'
    Invoke-Step "Le compte de test et le groupe de test, dans $Domain" {
        $state.Test = Get-ADUser -Server $Domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$(Get-LdapText $TestUser)))" -Properties AccountExpirationDate
        $state.TestGroup = Get-ADGroup -Server $Domain -LDAPFilter "(&(objectCategory=group)(name=$(Get-LdapText $TestGroup)))"
        if (-not $state.Test -or -not $state.TestGroup) { throw "$TestUser ou $TestGroup introuvable" }
        "$($state.Test.DistinguishedName) ; $($state.TestGroup.DistinguishedName)"
    }
    $testAccount = $state.Test
    $testList = $state.TestGroup
    $pdc = if ($state.Pdc) { $state.Pdc } else { $Domain }
}
if ($Write -and $testAccount -and $testList) {
    Invoke-Step 'Unlock-ADAccount (sans effet s''il n''est pas verrouillé)' { Unlock-ADAccount -Server $Domain -Identity $testAccount.DistinguishedName; 'fait' }
    Invoke-Step 'Set-ADAccountExpiration (dans un an), puis remise comme avant' {
        $before = $testAccount.AccountExpirationDate
        Set-ADAccountExpiration -Server $Domain -Identity $testAccount.DistinguishedName -DateTime (Get-Date).Date.AddYears(1).AddDays(1)
        $after = (Get-ADUser -Server $pdc -Identity $testAccount.DistinguishedName -Properties AccountExpirationDate).AccountExpirationDate
        if ($before) { Set-ADAccountExpiration -Server $Domain -Identity $testAccount.DistinguishedName -DateTime $before } else { Clear-ADAccountExpiration -Server $Domain -Identity $testAccount.DistinguishedName }
        "posée au $($after.ToString('yyyy-MM-dd HH:mm')), puis $(if ($before) { 'remise' } else { 'effacée' })"
    }
    Invoke-Step 'Disable-ADAccount et Enable-ADAccount, dans l''ordre qui le remet comme avant' {
        $enabled = (Get-ADUser -Server $pdc -Identity $testAccount.DistinguishedName).Enabled
        if ($enabled) {
            Disable-ADAccount -Server $Domain -Identity $testAccount.DistinguishedName
            $between = (Get-ADUser -Server $pdc -Identity $testAccount.DistinguishedName).Enabled
            Enable-ADAccount -Server $Domain -Identity $testAccount.DistinguishedName
        }
        else {
            Enable-ADAccount -Server $Domain -Identity $testAccount.DistinguishedName
            $between = (Get-ADUser -Server $pdc -Identity $testAccount.DistinguishedName).Enabled
            Disable-ADAccount -Server $Domain -Identity $testAccount.DistinguishedName
        }
        if ($between -eq $enabled) { throw "l'état lu sur le PDC n'a pas changé ($between)" }
        "$(if ($enabled) { 'désactivé, puis réactivé' } else { 'activé, puis désactivé de nouveau' })"
    }
    Invoke-Step "Add-ADGroupMember, puis Remove-ADGroupMember ($TestUser dans $TestGroup)" {
        Add-ADGroupMember -Server $Domain -Identity $testList.DistinguishedName -Members $testAccount.DistinguishedName
        $listed = @(Get-ADObject -Server $Domain -LDAPFilter "(&(memberOf=$(Get-LdapText $testList.DistinguishedName))(sAMAccountName=$(Get-LdapText $TestUser)))").Count
        Remove-ADGroupMember -Server $Domain -Identity $testList.DistinguishedName -Members $testAccount.DistinguishedName -Confirm:$false
        "ajouté ($listed trouvé par memberOf), puis retiré"
    }
    if ($ResetPassword) {
        Invoke-Step 'Set-ADAccountPassword -Reset (aléatoire, non affiché), puis Set-ADUser -ChangePasswordAtLogon' {
            $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
            # Drawn straight into the SecureString: 16 letters and digits, then a symbol, a digit and one more symbol.
            $secure = [securestring]::new()
            foreach ($i in 1..16) { $secure.AppendChar($chars[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)]) }
            foreach ($char in '-9!'.ToCharArray()) { $secure.AppendChar($char) }
            Set-ADAccountPassword -Server $Domain -Identity $testAccount.DistinguishedName -Reset -NewPassword $secure
            Set-ADUser -Server $Domain -Identity $testAccount.DistinguishedName -ChangePasswordAtLogon $true
            'fait (à changer à la prochaine connexion)'
        }
    }
}

Write-Line ''
$failures = @($results | Where-Object { -not $_.Ok }).Count
Write-Line "$($results.Count - $failures)/$($results.Count) commandes réussies" $(if ($failures) { 'Red' } else { 'Green' })
try {
    Set-Content -LiteralPath $Report -Value $lines -Encoding utf8BOM
    Write-Host "Rapport enregistré : $Report"
}
catch { Write-Host "Rapport non enregistré : $($_.Exception.Message)" -ForegroundColor Yellow }
exit [int]($failures -gt 0)
