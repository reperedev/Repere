# Fake AD used when this computer isn't joined to a domain (or with -FakeAD), so Repère can be
# tried out and tested without a real Active Directory. Provides the AD cmdlets Repère uses. Changes
# (descriptions, deletions) only last until the app closes.
#
# Repère searches in background runspaces, each importing this module: the computers are kept once per process
# (New-FakeADStore), so every runspace sees the same AD and the changes made from the window.
#
# For the UI tests:
# - $env:REPERE_FAKEAD_LOG: a file path; each call is appended to it as a JSON line (Command and its parameters).
# - $env:REPERE_FAKEAD_NO_COMMON_OU: when set, the Communs OUs don't exist.
# - $env:REPERE_FAKEAD_UNREACHABLE: a domain name; every call to it fails as if its DCs were down. Or a DC's name
#   (dc1.demo.local, the PDC; dc2 and dc3 too): only the calls to that DC fail, and the DC locator finds the next one.
#   Several, separated by semicolons.
# - $env:REPERE_FAKEAD_SLOW: domain=milliseconds pairs separated by semicolons, e.g. nord.demo.local=3000; every call
#   to that domain takes that long, like a slow DC.
#
# - $env:REPERE_FAKEAD_SPECS_DELAY: milliseconds; each CIM query of the Caractéristiques window takes that long, like
#   a computer slow to answer.
# - $env:REPERE_FAKEAD_QUSER_HANG: a computer's DNS name; quser on it doesn't answer for 2 minutes.
# - $env:REPERE_FAKEAD_WINRM_ON_ERROR: when set, turning WinRM on fails once it's on: deleting the task that turned it
#   on throws, as Unregister-ScheduledTask -Confirm:$false did over DCOM (#316), for any other such failure.
#
# For trying large results (the main script's -ExtraFakeComputers sets it):
# - $env:REPERE_FAKEAD_EXTRA_COMPUTERS: a number of extra computers in demo.local, PC-001, PC-002 and so on.
# - $env:REPERE_FAKEAD_EXTRA_OUS: a number of extra OUs under demo.local's Postes, Site_01, Site_02 and so on.
#
# The fake computers don't exist on the network either: the module also replaces the commands the online check and the
# Caractéristiques window use to reach them (Test-Connection, Resolve-DnsName and the CIM commands), and the scheduled
# tasks that Forcer les stratégies and PowerShell à distance create there.

# The errors are thrown as Windows throws them, with their types and codes: Repère knows them by those (Get-ErrorKind,
# Test-GroupRefusal, Test-ServerDown), not by their text, which is in Windows' language. ADException and
# ADServerDownException stand in for the ActiveDirectory module's, by their names and ErrorCode (a Win32 code).
class ADException : System.InvalidOperationException {
    [int]$ErrorCode
    ADException([string]$Message, [int]$ErrorCode) : base($Message) { $this.ErrorCode = $ErrorCode }
}

class ADServerDownException : System.Exception {
    ADServerDownException([string]$Message) : base($Message) { }
}

function New-FakeCimError([string]$Message, [int64]$Code) {
    # A CimException as CIM gives one: its message, and its code (an HRESULT) in its error data, as error_Code and
    # MessageId.
    $data = CimCmdlets\New-CimInstance -ClassName MSFT_WmiError -Namespace root/cimv2 -ClientOnly -Property @{
        error_Code = [uint32]$Code; Message = $Message; MessageID = 'HRESULT 0x{0:x8}' -f $Code; CIMStatusCode = [uint32]1
    }
    [Microsoft.Management.Infrastructure.CimException]::new($data)
}

function New-FakeRemotingError([string]$Message, [int]$Code) {
    # PowerShell's remoting error, with WinRM's code (5: access denied).
    $failure = [System.Management.Automation.Remoting.PSRemotingTransportException]::new($Message)
    $failure.ErrorCode = $Code
    $failure
}

# One forest with two domains: demo.local and its child nord.demo.local. Like the real AD, a command without
# -Server goes to the user's domain (demo.local), and a search of demo.local doesn't return nord's objects. Across
# domains, a group's membership is known in the group's domain only (its member list), and for a universal group in
# the global catalog too (dc1.demo.local:3268, which searches the whole forest).
$script:Domains = [ordered]@{
    'demo.local'      = 'DC=demo,DC=local'
    'nord.demo.local' = 'DC=nord,DC=demo,DC=local'
}
$script:DefaultDomain = 'demo.local'
# Each domain's SID: its objects' SIDs start with it (Get-ADDomain's DomainSID).
$script:DomainSids = @{ 'demo.local' = 'S-1-5-21-1111-2222-3333'; 'nord.demo.local' = 'S-1-5-21-4444-5555-6666' }

# The Communs OUs cover what the Communs search must handle: one inside another, one elsewhere in the
# tree, and Labo-Communs, which isn't one (its name doesn't start with "Communs"). nord has its own. The others are
# destinations for « Déplacer vers… », Domain Controllers included (Repère doesn't offer it).
$script:OrganizationalUnits = @(
    'OU=Postes,DC=demo,DC=local'
    'OU=Communs,OU=Postes,DC=demo,DC=local'
    'OU=Communs-Entree,OU=Communs,OU=Postes,DC=demo,DC=local'
    'OU=Labo-Communs,OU=Postes,DC=demo,DC=local'
    'OU=Kiosques,DC=demo,DC=local'
    'OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local'
    'OU=Ordinateurs désactivés,DC=demo,DC=local'
    'OU=Serveurs,DC=demo,DC=local'
    'OU=Domain Controllers,DC=demo,DC=local'
    'OU=Postes,DC=nord,DC=demo,DC=local'
    'OU=Communs,OU=Postes,DC=nord,DC=demo,DC=local'
    'OU=Domain Controllers,DC=nord,DC=demo,DC=local'
) | ForEach-Object { [pscustomobject]@{ Name = ($_ -split ',')[0] -replace '^OU=', ''; DistinguishedName = $_ } }
$extraOuCount = 0
if ([int]::TryParse("$env:REPERE_FAKEAD_EXTRA_OUS", [ref]$extraOuCount) -and $extraOuCount -gt 0) {
    $script:OrganizationalUnits += 1..$extraOuCount | ForEach-Object { $name = 'Site_{0:00}' -f $_; [pscustomobject]@{ Name = $name; DistinguishedName = "OU=$name,OU=Postes,DC=demo,DC=local" } }
}

# The fake computers that are on the network, for the online check: ord-01 answers ping, ord-04 blocks it but has
# Remote Desktop (3389) open. ord-08 answers ping only, behind a firewall that closes WinRM and DCOM too. The others
# don't answer.
$script:OnlineHosts = @{
    'ord-01.demo.local' = 'ping'
    'ord-04.demo.local' = '3389'
    'ord-08.demo.local' = 'ping'
}

function New-FakeADStore {
    # The computers and the objects they hold, in a synchronized hashtable. LogLock: one log line at a time.
    # Last logons are relative to today so the data never looks frozen in time. $null = never logged on.
    $today = (Get-Date).Date
    $computers = @(
        [pscustomobject]@{ Name = 'ORD-01'; Description = "Bureau d'accueil";          Enabled = $true;  LastLogonDate = $today.AddDays(-1) + [timespan]'08:15';   DistinguishedName = 'CN=ORD-01,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-02'; Description = 'Salle de réunion 1';        Enabled = $true;  LastLogonDate = $today.AddDays(-3) + [timespan]'13:40';   DistinguishedName = 'CN=ORD-02,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-03'; Description = $null;                       Enabled = $true;  LastLogonDate = $null;                                    DistinguishedName = 'CN=ORD-03,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-04'; Description = 'Poste commun cafétéria'; Enabled = $true;  LastLogonDate = $today.AddDays(-1) + [timespan]'06:55';   DistinguishedName = 'CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-05'; Description = $null;                       Enabled = $false; LastLogonDate = $today.AddDays(-210) + [timespan]'16:20'; DistinguishedName = 'CN=ORD-05,OU=Communs,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-06'; Description = "Salle de pause";           Enabled = $true;  LastLogonDate = $today.AddDays(-6) + [timespan]'09:05';   DistinguishedName = 'CN=ORD-06,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-07'; Description = $null;                       Enabled = $false; LastLogonDate = $null;                                    DistinguishedName = 'CN=ORD-07,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-08'; Description = 'Laboratoire';               Enabled = $true;  LastLogonDate = $today.AddDays(-45) + [timespan]'11:30';  DistinguishedName = 'CN=ORD-08,OU=Labo-Communs,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-09'; Description = 'Poste des ventes';          Enabled = $false; LastLogonDate = $today.AddDays(-120) + [timespan]'07:45'; DistinguishedName = 'CN=ORD-09,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-10'; Description = 'Salle de réunion 2';        Enabled = $true;  LastLogonDate = $today.AddDays(-2) + [timespan]'15:10';   DistinguishedName = 'CN=ORD-10,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-11'; Description = 'Poste commun entrée';    Enabled = $true;  LastLogonDate = $today.AddDays(-4) + [timespan]'07:00';   DistinguishedName = 'CN=ORD-11,OU=Communs-Entree,OU=Communs,OU=Postes,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'ORD-12'; Description = $null;                       Enabled = $true;  LastLogonDate = $today.AddDays(-30) + [timespan]'10:00';  DistinguishedName = 'CN=ORD-12,OU=Postes,DC=demo,DC=local' }
        # nord.demo.local: its ORD-01 has the same name as demo.local's, so an action must reach the right one.
        [pscustomobject]@{ Name = 'ORD-01'; Description = 'Accueil Nord';              Enabled = $true;  LastLogonDate = $today.AddDays(-2) + [timespan]'08:40';   DistinguishedName = 'CN=ORD-01,OU=Postes,DC=nord,DC=demo,DC=local' }
        [pscustomobject]@{ Name = 'NRD-01'; Description = 'Poste commun Nord';      Enabled = $true;  LastLogonDate = $today.AddDays(-1) + [timespan]'07:20';   DistinguishedName = 'CN=NRD-01,OU=Communs,OU=Postes,DC=nord,DC=demo,DC=local' }
        # NRD-02's description names a user of demo.local: Ordinateurs de l'utilisateur searches every domain.
        [pscustomobject]@{ Name = 'NRD-02'; Description = 'Portable Julie Bertrand';   Enabled = $false; LastLogonDate = $null;                                    DistinguishedName = 'CN=NRD-02,OU=Postes,DC=nord,DC=demo,DC=local' }
    )

    # Extra computers for large results: some without a description, disabled, never logged on, or in an Communs OU.
    $extraCount = 0
    if ([int]::TryParse("$env:REPERE_FAKEAD_EXTRA_COMPUTERS", [ref]$extraCount) -and $extraCount -gt 0) {
        $places = 'Accueil', 'Bureau', 'Salle de réunion', 'Laboratoire', 'Poste vendeur', 'Kiosque'
        $digits = [Math]::Max(3, "$extraCount".Length)
        $computers += foreach ($n in 1..$extraCount) {
            $name = "PC-{0:D$digits}" -f $n
            $ou = if ($n % 25 -eq 0) { 'OU=Communs,OU=Postes' } else { 'OU=Postes' }
            [pscustomobject]@{
                Name              = $name
                Description       = if ($n % 10 -eq 0) { $null } else { "$($places[$n % $places.Count]) $n" }
                Enabled           = $n % 7 -ne 0
                LastLogonDate     = if ($n % 13 -eq 0) { $null } else { $today.AddDays(-($n * 37 % 400)) + [timespan]'08:00' }
                DistinguishedName = "CN=$name,$ou,DC=demo,DC=local"
            }
        }
    }
    # demo.local's domain controller, last: the other computers keep their numbers (and so their addresses). Every
    # computer's primary group: Ordinateurs du domaine (515), Contrôleurs de domaine (516) for DC1, and Labo-Principal
    # (1106) for ORD-08, a group that lists no member and isn't empty. Repère never disables, deletes or
    # moves a domain controller.
    $computers += [pscustomobject]@{ Name = 'DC1'; Description = 'Contrôleur de domaine'; Enabled = $true; LastLogonDate = $today + [timespan]'06:00'; DistinguishedName = 'CN=DC1,OU=Domain Controllers,DC=demo,DC=local' }
    foreach ($computer in $computers) { $computer | Add-Member PrimaryGroupID $(switch ($computer.Name) { 'DC1' { 516 } 'ORD-08' { 1106 } default { 515 } }) }
    # Each computer's account (sAMAccountName): its name followed by $, but for ORD-10, once SALLE-REU2 and renamed in
    # ADUC, which changes only the CN. The UI tests run Repère on SALLE-REU2, which must know ORD-10 is itself.
    foreach ($computer in $computers) { $computer | Add-Member SamAccountName $(if ($computer.Name -eq 'ORD-10') { 'SALLE-REU2$' } else { "$($computer.Name)$" }) }

    # Cases the right-click menu must handle: ORD-07 is protected from accidental deletion, and the current
    # user can't change ORD-12 (access denied).
    foreach ($computer in $computers) {
        $computer | Add-Member ProtectedFromAccidentalDeletion ($computer.Name -eq 'ORD-07')
        $computer | Add-Member DenyWrite ($computer.Name -eq 'ORD-12')
    }

    # LAPS passwords, as the current user sees their attributes (expirations are FILETIMEs, relative to today):
    # - ORD-01: Windows LAPS, in clear (msLAPS-Password holds JSON: n the account, t when it was set, p the password);
    # - ORD-04: legacy LAPS;
    # - ORD-12: legacy LAPS the user can't read: the password is confidential, so only its expiration shows;
    # - ORD-06: Windows LAPS encrypted for others: the user can't decrypt it;
    # - nord.demo.local's ORD-01: Windows LAPS encrypted for the user (FakeLapsDecrypted: what decryption gives).
    $lapsComputers = @(
        @{ DN = 'CN=ORD-01,OU=Postes,DC=demo,DC=local'; Days = 18; Time = '14:00'; Account = 'Administrateur'; Password = 'Vq7#mR2t!xL9pW4z' }
        @{ DN = 'CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local'; Days = 9; Time = '03:30'; Legacy = $true; Password = 'K3n$8vTq2Lm+Hd' }
        @{ DN = 'CN=ORD-12,OU=Postes,DC=demo,DC=local'; Days = 21; Time = '22:00'; Legacy = $true }
        @{ DN = 'CN=ORD-06,OU=Postes,DC=demo,DC=local'; Days = 5; Time = '10:15'; Encrypted = $true }
        @{ DN = 'CN=ORD-01,OU=Postes,DC=nord,DC=demo,DC=local'; Days = 12; Time = '08:00'; Encrypted = $true; Account = 'Administrateur'; Password = 'Nord-8fK2#qZ7wB' }
    )
    foreach ($laps in $lapsComputers) {
        $computer = $computers | Where-Object DistinguishedName -eq $laps.DN
        $expires = ($today.AddDays($laps.Days) + [timespan]$laps.Time).ToFileTime()
        if ($laps.Legacy) {
            $computer | Add-Member 'ms-Mcs-AdmPwdExpirationTime' $expires
            if ($laps.Password) { $computer | Add-Member 'ms-Mcs-AdmPwd' $laps.Password }
            continue
        }
        $computer | Add-Member 'msLAPS-PasswordExpirationTime' $expires
        $content = @{ n = $laps.Account; t = '{0:x}' -f $today.AddDays($laps.Days - 30).ToFileTimeUtc(); p = $laps.Password } | ConvertTo-Json -Compress
        if ($laps.Encrypted) {
            $computer | Add-Member 'msLAPS-EncryptedPassword' ([byte[]](1..64 | ForEach-Object { ($_ * 37) % 256 }))
            $computer | Add-Member FakeLapsDecrypted $(if ($laps.Password) { $content })
        }
        else {
            $computer | Add-Member 'msLAPS-Password' $content
        }
    }

    # DNS names (<name>.<domain>), as AD returns them by default, and the address the fake DNS gives each: 10.0.1.x in
    # demo.local, 10.0.2.x in nord. ORD-03 never logged on, so it has neither: the remote actions then use its name,
    # which the DNS doesn't know. The extra computers (PC-001…) are in 10.1.x.x, each its own: they don't take the
    # sample computers' addresses, which the IP search's checks look for.
    $number = 0
    $extra = 0
    foreach ($computer in $computers) {
        $number++
        $domainName = ($computer.DistinguishedName -split ',' | Where-Object { $_ -like 'DC=*' } | ForEach-Object { $_.Substring(3) }) -join '.'
        $hasDns = $computer.Name -ne 'ORD-03'
        $computer | Add-Member DNSHostName $(if ($hasDns) { "$($computer.Name).$domainName".ToLowerInvariant() })
        $subnet = if ($domainName -eq 'nord.demo.local') { 2 } else { 1 }
        $address = if ($computer.Name -like 'PC-*') { $extra++; "10.1.$([math]::Floor($extra / 250)).$(1 + $extra % 250)" } else { "10.0.$subnet.$(10 + $number % 240)" }
        $computer | Add-Member IPAddress $(if ($hasDns) { $address })
    }

    # The Windows version AD keeps for each computer (operatingSystem, operatingSystemVersion), for the Système column:
    # current and old Windows 11, Windows 10 past its end of support, an unknown build and a server. Computers that never
    # logged on have none. ORD-01 and ORD-04 match their Caractéristiques.
    $systems = @{
        'ORD-01' = 'Windows 11 Professionnel', '10.0 (26200)'; 'ORD-02' = 'Windows 11 Professionnel', '10.0 (26100)'
        'ORD-04' = 'Windows 10 Professionnel', '10.0 (19045)'; 'ORD-05' = 'Windows 10 Entreprise', '10.0 (19045)'
        'ORD-06' = 'Windows 11 Professionnel', '10.0 (26100)'; 'ORD-08' = 'Windows 11 Éducation', '10.0 (22631)'
        'ORD-09' = 'Windows 10 Professionnel', '10.0 (19044)'; 'ORD-10' = 'Windows 11 Professionnel', '10.0 (26300)'
        'ORD-11' = 'Windows 11 Entreprise', '10.0 (22631)'; 'ORD-12' = 'Windows Server 2022 Standard', '10.0 (20348)'
        'NRD-01' = 'Windows 10 Professionnel', '10.0 (19045)'; 'DC1' = 'Windows Server 2022 Datacenter', '10.0 (20348)'
    }
    $extraSystems = @(('Windows 11 Professionnel', '10.0 (26100)'), ('Windows 11 Professionnel', '10.0 (26200)'), ('Windows 10 Professionnel', '10.0 (19045)'), ('Windows 11 Entreprise', '10.0 (22631)'))
    $number = 0
    foreach ($computer in $computers) {
        $number++
        $system = if (-not $computer.LastLogonDate) { $null }
                  elseif ($computer.DistinguishedName -like '*DC=nord,*' -and $computer.Name -eq 'ORD-01') { 'Windows 11 Professionnel', '10.0 (26100)' }
                  elseif ($systems.ContainsKey($computer.Name)) { $systems[$computer.Name] }
                  else { $extraSystems[$number % $extraSystems.Count] }
        $computer | Add-Member OperatingSystem $(if ($system) { $system[0] })
        $computer | Add-Member OperatingSystemVersion $(if ($system) { $system[1] })
    }

    # lastLogonTimestamp (what LastLogonDate is read from, as a FILETIME) and whenCreated, for the inactive search.
    # ORD-03 never logged on because it was joined to the domain 5 days ago: that search leaves it out. The other
    # computers that never logged on were created long ago.
    foreach ($computer in $computers) {
        $computer | Add-Member lastLogonTimestamp $(if ($computer.LastLogonDate) { [int64]$computer.LastLogonDate.ToFileTimeUtc() })
        $computer | Add-Member whenCreated $(if ($computer.Name -eq 'ORD-03') { $today.AddDays(-5) } else { $today.AddYears(-2) })
    }
    # What a computer's Propriétés shows besides: when its account's password was last set (a computer on the domain
    # changes it every 30 days, so one off for long has an old one: 12 days before its last logon, or when it joined),
    # when it last changed, who manages ORD-01, and where ORD-01 and ORD-02 are (location).
    foreach ($computer in $computers) {
        $computer | Add-Member Location $(switch ($computer.DistinguishedName) { 'CN=ORD-01,OU=Postes,DC=demo,DC=local' { 'Bâtiment A, accueil' } 'CN=ORD-02,OU=Postes,DC=demo,DC=local' { 'Bâtiment A, bureau 204' } })
        $computer | Add-Member PasswordLastSet $(if ($computer.LastLogonDate) { $computer.LastLogonDate.Date.AddDays(-12) + [timespan]'07:45' } else { $computer.whenCreated })
        $computer | Add-Member whenChanged $(if ($computer.Name -eq 'ORD-03') { $computer.whenCreated } else { $today.AddDays(-3) + [timespan]'15:20' })
        $computer | Add-Member ManagedBy $(if ($computer.Name -eq 'ORD-01' -and $computer.DistinguishedName -like '*,DC=demo,DC=local' -and $computer.DistinguishedName -notlike '*DC=nord*') { 'CN=Nathalie Lévy,OU=Utilisateurs,DC=demo,DC=local' })
    }

    # Objects held by a computer: ORD-09 and ORD-07 (the protected one) have BitLocker recovery information,
    # so they aren't leaf objects. ORD-06 is a Hyper-V virtual machine, with the entry Hyper-V keeps under it, and DC1
    # holds its RID Set, as a domain controller does. ORD-09 has two disks: C: (its key replaced in January, the 2024 one left behind) and
    # D:. The current user can neither read nor delete ORD-07's key (no rights).
    $volumeC = ([guid]'5A0C3E91-2B7D-4F18-9C6A-0E4D8B1F7A23').ToByteArray()
    $volumeD = ([guid]'B83F6D02-9E41-4A7C-8D25-61F0C9E3A4B7').ToByteArray()
    $childObjects = @(
        [pscustomobject]@{
            Name                     = '2026-01-15T09:30:00-05:00{6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61}'
            ObjectClass              = 'msFVE-RecoveryInformation'
            'msFVE-RecoveryPassword' = '418649-302104-655721-128930-583011-472560-090288-361757'
            'msFVE-VolumeGuid'       = $volumeC
            DistinguishedName        = 'CN=2026-01-15T09:30:00-05:00{6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61},CN=ORD-09,OU=Postes,DC=demo,DC=local'
        }
        [pscustomobject]@{
            Name                     = '2024-03-02T11:05:00-05:00{A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54}'
            ObjectClass              = 'msFVE-RecoveryInformation'
            'msFVE-RecoveryPassword' = '207152-660011-394580-512237-081664-725903-466312-150898'
            'msFVE-VolumeGuid'       = $volumeC
            DistinguishedName        = 'CN=2024-03-02T11:05:00-05:00{A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54},CN=ORD-09,OU=Postes,DC=demo,DC=local'
        }
        [pscustomobject]@{
            Name                     = '2025-06-20T16:40:00-04:00{C93B8E05-1F6A-4D27-A0B4-3E8F5C7D9A16}'
            ObjectClass              = 'msFVE-RecoveryInformation'
            'msFVE-RecoveryPassword' = '533841-102498-719620-284317-650650-097185-381194-626701'
            'msFVE-VolumeGuid'       = $volumeD
            DistinguishedName        = 'CN=2025-06-20T16:40:00-04:00{C93B8E05-1F6A-4D27-A0B4-3E8F5C7D9A16},CN=ORD-09,OU=Postes,DC=demo,DC=local'
        }
        [pscustomobject]@{
            Name                     = '2025-11-03T14:12:00-05:00{0D8B5F21-7A3C-4E9A-8C16-5B2E9F4A3D70}'
            ObjectClass              = 'msFVE-RecoveryInformation'
            'msFVE-RecoveryPassword' = $null
            'msFVE-VolumeGuid'       = $null
            DistinguishedName        = 'CN=2025-11-03T14:12:00-05:00{0D8B5F21-7A3C-4E9A-8C16-5B2E9F4A3D70},CN=ORD-07,OU=Postes,DC=demo,DC=local'
            DenyDelete               = $true
        }
        [pscustomobject]@{
            Name                     = 'Windows Virtual Machine'
            ObjectClass              = 'serviceConnectionPoint'
            'msFVE-RecoveryPassword' = $null
            'msFVE-VolumeGuid'       = $null
            DistinguishedName        = 'CN=Windows Virtual Machine,CN=ORD-06,OU=Postes,DC=demo,DC=local'
        }
        [pscustomobject]@{
            Name                     = 'Windows Virtual Machine'
            ObjectClass              = 'serviceConnectionPoint'
            'msFVE-RecoveryPassword' = $null
            'msFVE-VolumeGuid'       = $null
            DistinguishedName        = 'CN=Windows Virtual Machine,CN=ORD-12,OU=Postes,DC=demo,DC=local'
        }
        [pscustomobject]@{
            Name                     = 'RID Set'
            ObjectClass              = 'rIDSet'
            'msFVE-RecoveryPassword' = $null
            'msFVE-VolumeGuid'       = $null
            DistinguishedName        = 'CN=RID Set,CN=DC1,OU=Domain Controllers,DC=demo,DC=local'
        }
    )
    # Groups, for Groupes…: each domain's Ordinateurs du domaine (the primary group of every computer but DC1 and
    # ORD-08, RID 515), software and GPO filtering groups, Labo-Principal (ORD-08's primary group, so it lists no member
    # and isn't empty), a domain local group that holds a global one (so ORD-01 belongs to it through that one), a
    # distribution list, and a universal group of nord.demo.local that holds computers of both domains. There's no
    # Contrôleurs de domaine (516): DC1's Groupes… shows no primary group.
    $sid = $script:DomainSids
    $demo = 'DC=demo,DC=local'
    $nord = 'DC=nord,DC=demo,DC=local'
    $groups = @(
        @{ Name = 'Ordinateurs du domaine'; Base = "CN=Users,$demo"; Domain = 'demo.local'; Rid = 515; Category = 'Security'; Scope = 'Global'; Description = 'Tous les ordinateurs joints au domaine'; Members = @() }
        @{ Name = 'GG-Logiciel-Office'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1101; Category = 'Security'; Scope = 'Global'; Description = 'Déploiement de Microsoft 365 Apps'
           Members = "CN=ORD-01,OU=Postes,$demo", "CN=ORD-02,OU=Postes,$demo", "CN=ORD-06,OU=Postes,$demo" }
        @{ Name = 'GG-Postes-Accueil'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1102; Category = 'Security'; Scope = 'Global'; Description = "Postes de l'accueil"
           Members = @("CN=ORD-01,OU=Postes,$demo") }
        @{ Name = 'DL-Imprimantes-Accueil'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1103; Category = 'Security'; Scope = 'DomainLocal'; Description = "Accès aux imprimantes de l'accueil"
           Members = @("CN=GG-Postes-Accueil,OU=Groupes,$demo") }
        @{ Name = 'GG-GPO-Kiosques'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1104; Category = 'Security'; Scope = 'Global'; Description = 'Filtre de la GPO des kiosques'
           Members = "CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,$demo", "CN=ORD-11,OU=Communs-Entree,OU=Communs,OU=Postes,$demo" }
        @{ Name = 'Labo-Principal'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1106; Category = 'Security'; Scope = 'Global'; Description = 'Groupe principal du laboratoire'; Members = @() }
        @{ Name = 'Liste-Inventaire'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1105; Category = 'Distribution'; Scope = 'Global'; Description = 'Inventaire annuel'; Mail = 'inventaire@demo.local'
           Members = @("CN=ORD-01,OU=Postes,$demo") }
        @{ Name = 'Ordinateurs du domaine'; Base = "CN=Users,$nord"; Domain = 'nord.demo.local'; Rid = 515; Category = 'Security'; Scope = 'Global'; Description = 'Tous les ordinateurs joints au domaine'; Members = @() }
        @{ Name = 'GU-Postes-Nord'; Base = "OU=Groupes,$nord"; Domain = 'nord.demo.local'; Rid = 1201; Category = 'Security'; Scope = 'Universal'; Description = "Postes gérés par l'équipe Nord"
           Members = "CN=ORD-01,OU=Postes,$nord", "CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,$demo", "CN=GG-Postes-Accueil,OU=Groupes,$demo" }
    ) | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name; DistinguishedName = "CN=$($_.Name),$($_.Base)"; SID = "$($sid[$_.Domain])-$($_.Rid)"; SamAccountName = $_.Name
            mail = $_.Mail; ManagedBy = $_.ManagedBy; whenCreated = $today.AddYears(-3) + [timespan]'09:00'; whenChanged = $today.AddDays(-12) + [timespan]'14:00'
            GroupCategory = $_.Category; GroupScope = $_.Scope; Description = $_.Description; Members = @($_.Members); isCriticalSystemObject = $_.Rid -lt 1000
            adminCount = $_.AdminCount
        }
    }
    # Users, for the Utilisateurs page. Their password expires 90 days after it was set (msDS-UserPasswordExpiryTimeComputed,
    # a FILETIME; never for a service account). The cases it must show: two Bertrands in demo.local and one in nord (so
    # « bert » finds three), Marc Durand locked out, Sophie Rey disabled, Luc Lefebvre's password expired, Jean Bertrand's
    # about to (and his employee number, which the current user can't change: DenyAttributes), Nathalie Lévy, whose
    # password the current user can't reset (DenyWrite), and Hugo Tremblay, in enough groups for Groupes' filter (#322).
    $people = @(
        @{ Given = 'Julie'; Surname = 'Bertrand'; Login = 'jbertrand'; Title = "Agente d'accueil"; Department = 'Accueil'; Logon = -1; PasswordSet = -20; Domain = $demo }
        @{ Given = 'Jean'; Surname = 'Bertrand'; Login = 'jebertrand'; Title = 'Technicien'; Department = 'Informatique'; Logon = 0; PasswordSet = -87; Domain = $demo; DenyAttributes = 'employeeID' }
        @{ Given = 'Marc'; Surname = 'Durand'; Login = 'mdurand'; Title = 'Représentant'; Department = 'Ventes'; Logon = -2; PasswordSet = -30; Domain = $demo; Locked = $true }
        @{ Given = 'Sophie'; Surname = 'Rey'; Login = 'srey'; Title = 'Comptable'; Department = 'Finances'; Logon = -200; PasswordSet = -230; Domain = $demo; Disabled = $true }
        @{ Given = 'Luc'; Surname = 'Lefebvre'; Login = 'llefebvre'; Title = 'Commis'; Department = 'Entretien'; Logon = -95; PasswordSet = -100; Domain = $demo }
        @{ Given = 'Nathalie'; Surname = 'Lévy'; Login = 'nlevy'; Title = 'Directrice'; Department = 'Direction'; Logon = -1; PasswordSet = -10; Domain = $demo; DenyWrite = $true }
        @{ Given = $null; Surname = $null; Name = 'Sauvegarde'; Login = 'svc-sauvegarde'; Description = 'Compte de service de la sauvegarde'; Logon = 0; PasswordSet = -400; Domain = $demo; NeverExpires = $true; Base = 'OU=Comptes de service'; DenyTokenGroups = $true }
        @{ Given = 'Nadia'; Surname = 'Moreau'; Login = 'nmoreau'; Title = "Agente d'accueil"; Department = 'Accueil Nord'; Logon = -2; PasswordSet = -15; Domain = $nord }
        @{ Given = 'Paul'; Surname = 'Bertrand'; Login = 'pbertrand'; Title = 'Magasinier'; Department = 'Entrepôt'; Logon = -6; PasswordSet = -40; Domain = $nord }
        @{ Given = 'Léa'; Surname = 'Perrin'; Login = 'lperrin'; Title = 'Stagiaire'; Department = 'Accueil'; Logon = -3; PasswordSet = -12; Domain = $demo; Expires = 20 }
        @{ Given = 'Hugo'; Surname = 'Tremblay'; Login = 'htremblay'; Title = "Chef d'atelier"; Department = 'Atelier'; Logon = -1; PasswordSet = -25; Domain = $demo }
    )
    $users = foreach ($person in $people) {
        $name = if ($person.Name) { $person.Name } else { "$($person.Given) $($person.Surname)" }
        $dns = (($person.Domain -replace 'DC=', '') -split ',') -join '.'
        $passwordSet = $today.AddDays($person.PasswordSet) + [timespan]'09:00'
        [pscustomobject]@{
            Name = $name; DisplayName = $name; GivenName = $person.Given; Surname = $person.Surname; SamAccountName = $person.Login
            UserPrincipalName = "$($person.Login)@$dns"; mail = if ($person.Given) { "$($person.Login)@$dns" }
            Title = $person.Title; Department = $person.Department; Description = $person.Description
            Enabled = -not $person.Disabled; LockedOut = [bool]$person.Locked; lockoutTime = if ($person.Locked) { $today.AddHours(-1).ToFileTime() } else { 0 }
            LastLogonDate = $today.AddDays($person.Logon) + [timespan]'08:30'; PasswordLastSet = $passwordSet; PasswordNeverExpires = [bool]$person.NeverExpires
            'msDS-UserPasswordExpiryTimeComputed' = if ($person.NeverExpires) { [int64]::MaxValue } else { $passwordSet.AddDays(90).ToFileTime() }
            PasswordExpired = -not $person.NeverExpires -and $passwordSet.AddDays(90) -lt (Get-Date)
            DistinguishedName = "CN=$name,$(if ($person.Base) { $person.Base } else { 'OU=Utilisateurs' }),$($person.Domain)"
            DenyWrite = [bool]$person.DenyWrite
            # The attributes the current user can't change on it (Set-ADUser), as a help desk delegated only some.
            DenyAttributes = @($person.DenyAttributes | Where-Object { $_ })
            # Its tokenGroups can't be read, as a hardened domain refuses them to whoever reads.
            DenyTokenGroups = [bool]$person.DenyTokenGroups
            # The account's expiration: the start of the day after its last day, as AD keeps it (none: never).
            AccountExpirationDate = if ($person.Expires) { $today.AddDays($person.Expires + 1) } else { $null }
            # The lockout: bad passwords (counted by each DC; the PDC's count is the one that locks), and when.
            badPwdCount = if ($person.Locked) { 5 } elseif ($person.Login -eq 'jbertrand') { 2 } else { 0 }
            LastBadPasswordAttempt = if ($person.Locked) { (Get-Date).AddMinutes(-40) } elseif ($person.Login -eq 'jbertrand') { $today.AddDays(-1) + [timespan]'07:58' } else { $null }
            AccountLockoutTime = if ($person.Locked) { (Get-Date).AddMinutes(-40) } else { $null }
            whenCreated = $today.AddYears(-2) + [timespan]'10:00'; whenChanged = $today.AddDays(-3) + [timespan]'15:20'
            EmployeeID = if ($person.Given) { "10$($person.Login.Length)$($person.Surname.Length)4" }
            Company = if ($person.Given) { 'Entreprise Démo' }; Office = if ($person.Department) { "$($person.Department), rez-de-chaussée" }
            Manager = if ($person.Given -and $person.Login -ne 'nlevy') { "CN=Nathalie Lévy,OU=Utilisateurs,$demo" }
            OfficePhone = if ($person.Given) { "555 555-01$($person.Login.Length)$($person.Surname.Length)" }; MobilePhone = $null
            HomeDirectory = if ($person.Given) { "\\fichiers\home$\$($person.Login)" }; HomeDrive = if ($person.Given) { 'H:' }
            ProfilePath = $null; ScriptPath = if ($person.Given) { 'logon.bat' }
        }
    }
    # Groups of users: each domain's Utilisateurs du domaine (every user's primary group, RID 513), Admins du domaine
    # (which the current user can't change), and groups for the accueil (managed by Nathalie Lévy), the VPN and the care
    # staff; DL-Partage-Accueil holds GG-Accueil, so its members belong to it through that one, and Nadia Moreau, of
    # nord.demo.local. GG-Projet-2019 is empty. For Ajouter à un groupe from another domain: nord.demo.local's
    # Personnel-Nord (global: refuses an account of another domain), DL-Imprimantes-Nord (domain local: takes one), and
    # the groups Windows creates (isCriticalSystemObject: a RID under 1000), Administrateurs (built-in, domain local) and
    # demo.local's Administrateurs de l'entreprise (universal). AD's protected groups keep adminCount = 1 (Admins du
    # domaine, Administrateurs de l'entreprise, Administrateurs), and so does GG-Projet-2019, once nested in Admins du
    # domaine: AD doesn't clear it when a group stops being protected. The workshop's groups hold Hugo Tremblay alone,
    # named so that no other test's search finds them (no « gg », « nord », « postes »…), with accents to filter without.
    $user = @{}
    foreach ($entry in $users) { $user[$entry.SamAccountName] = $entry.DistinguishedName }
    $workshop = @(
        @('Atelier-Bois', 1120, 'Global', 'Menuiserie'), @('Atelier-Métal', 1121, 'Global', 'Soudure et découpe'), @('Atelier-Peinture', 1122, 'Global', 'Cabine de peinture')
        @('Atelier-Outillage', 1123, 'DomainLocal', 'Prêt des outils'), @('Atelier-Sécurité', 1124, 'Global', 'Équipements de protection'), @('Atelier-Horaires', 1125, 'Global', 'Quarts de travail')
        @('Atelier-Stock', 1126, 'Global', 'Pièces de rechange'), @('Atelier-Véhicules', 1127, 'Global', 'Chariots et camions')
        @('Atelier-Formation', 1128, 'Global', 'Cours obligatoires'), @('Atelier-Rapports', 1129, 'DomainLocal', 'Rapports mensuels')
    ) | ForEach-Object { @{ Name = $_[0]; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = $_[1]; Category = 'Security'; Scope = $_[2]; Description = $_[3]; Members = @($user.htremblay) } }
    $groups += @(
        @{ Name = 'Utilisateurs du domaine'; Base = "CN=Users,$demo"; Domain = 'demo.local'; Rid = 513; Category = 'Security'; Scope = 'Global'; Description = 'Tous les utilisateurs du domaine'; Members = @() }
        @{ Name = 'Admins du domaine'; Base = "CN=Users,$demo"; Domain = 'demo.local'; Rid = 512; Category = 'Security'; Scope = 'Global'; Description = 'Administrateurs désignés du domaine'; Members = @(); DenyWrite = $true; AdminCount = 1 }
        @{ Name = 'GG-Accueil'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1110; Category = 'Security'; Scope = 'Global'; Description = "Personnel de l'accueil"; ManagedBy = "CN=Nathalie Lévy,OU=Utilisateurs,$demo"
           Members = $user.jbertrand, $user.lperrin }
        @{ Name = 'GG-VPN'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1111; Category = 'Security'; Scope = 'Global'; Description = 'Accès au VPN'
           Members = $user.jbertrand, $user.jebertrand }
        @{ Name = 'GG-Ventes'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1112; Category = 'Security'; Scope = 'Global'; Description = 'Personnel des ventes'
           Members = @($user.mdurand) }
        @{ Name = 'DL-Partage-Accueil'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1113; Category = 'Security'; Scope = 'DomainLocal'; Description = "Partage de fichiers de l'accueil"
           Members = "CN=GG-Accueil,OU=Groupes,$demo", $user.nmoreau }
        @{ Name = 'GG-Projet-2019'; Base = "OU=Groupes,$demo"; Domain = 'demo.local'; Rid = 1114; Category = 'Security'; Scope = 'Global'; Description = 'Ancien projet de numérisation'; Members = @(); AdminCount = 1 }
        @{ Name = 'Utilisateurs du domaine'; Base = "CN=Users,$nord"; Domain = 'nord.demo.local'; Rid = 513; Category = 'Security'; Scope = 'Global'; Description = 'Tous les utilisateurs du domaine'; Members = @() }
        @{ Name = "Administrateurs de l'entreprise"; Base = "CN=Users,$demo"; Domain = 'demo.local'; Rid = 519; Category = 'Security'; Scope = 'Universal'; Description = "Administrateurs désignés de l'entreprise"; Members = @(); DenyWrite = $true; AdminCount = 1 }
        @{ Name = 'Administrateurs'; Base = "CN=Builtin,$nord"; Domain = 'nord.demo.local'; Rid = 544; Category = 'Security'; Scope = 'DomainLocal'; Description = "Les administrateurs ont un accès complet à l'ordinateur ou au domaine"; Members = @(); AdminCount = 1 }
        @{ Name = 'Personnel-Nord'; Base = "OU=Groupes,$nord"; Domain = 'nord.demo.local'; Rid = 1210; Category = 'Security'; Scope = 'Global'; Description = "Personnel de l'équipe Nord"; Members = @() }
        @{ Name = 'DL-Imprimantes-Nord'; Base = "OU=Groupes,$nord"; Domain = 'nord.demo.local'; Rid = 1211; Category = 'Security'; Scope = 'DomainLocal'; Description = "Accès aux imprimantes de l'équipe Nord"
           Members = @("CN=Personnel-Nord,OU=Groupes,$nord") }
        $workshop
    ) | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name; DistinguishedName = "CN=$($_.Name),$($_.Base)"; SID = "$($sid[$_.Domain])-$($_.Rid)"; SamAccountName = $_.Name
            mail = $_.Mail; ManagedBy = $_.ManagedBy; whenCreated = $today.AddYears(-3) + [timespan]'09:00'; whenChanged = $today.AddDays(-12) + [timespan]'14:00'
            GroupCategory = $_.Category; GroupScope = $_.Scope; Description = $_.Description; Members = @($_.Members); DenyWrite = [bool]$_.DenyWrite
            isCriticalSystemObject = $_.Rid -lt 1000; adminCount = $_.AdminCount
        }
    }
    # The computers' scheduled tasks (by computer and name), where WinRM runs (ord-01 has it, ord-04 doesn't until
    # PowerShell à distance turns it on), and the firewall rules PowerShell à distance added (by computer, their names).
    [hashtable]::Synchronized(@{ Computers = $computers; ChildObjects = $childObjects; Groups = @($groups); Users = @($users); LogLock = [object]::new()
                                 Tasks = [hashtable]::Synchronized(@{}); WinRM = [hashtable]::Synchronized(@{ 'ord-01.demo.local' = $true }); WinRMRules = [hashtable]::Synchronized(@{}) })
}

# The first runspace to import the module creates the store; the others find it in the process's AppDomain.
[System.Threading.Monitor]::Enter([System.AppDomain]::CurrentDomain)
try {
    $script:Store = [System.AppDomain]::CurrentDomain.GetData('Repere.FakeAD')
    if (-not $script:Store) {
        $script:Store = New-FakeADStore
        [System.AppDomain]::CurrentDomain.SetData('Repere.FakeAD', $script:Store)
    }
}
finally {
    [System.Threading.Monitor]::Exit([System.AppDomain]::CurrentDomain)
}

function ConvertFrom-FakeADFilter {
    # Parses the filters Repère builds, like a real AD would: clauses  Attribute -like|-eq '...'  (Enabled -eq 'True'
    # or 'False' too),  Attribute -lt|-le|-gt|-ge <number>  (lastLogonTimestamp) and  whenCreated -lt $Variable  (a
    # date, read from $SessionState, the caller's, as AD reads a variable where it's called), combined with -and, -or,
    # -not and parentheses, with '' for a quote inside a value. Returns a tree that Test-FakeADFilter evaluates; anything
    # else fails like a real AD parse error. * alone matches every object ($null).
    param([string]$Filter, [System.Management.Automation.SessionState]$SessionState)

    if ($Filter.Trim() -eq '*') { return $null }
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Filter, "\s*(\(|\)|-and\b|-or\b|-not\b|-like\b|-eq\b|-lt\b|-le\b|-gt\b|-ge\b|'(?:[^']|'')*'|\d+|\$\w+|[A-Za-z][\w-]*)", 'IgnoreCase')) {
        $tokens.Add($match.Groups[1].Value)
    }
    if ((($tokens -join '') -replace '\s', '').Length -ne ($Filter -replace '\s', '').Length) { throw "Error parsing query: '$Filter'" }
    $state = @{ Tokens = $tokens; Position = 0; Filter = $Filter; SessionState = $SessionState }
    $tree = Read-FakeADExpression $state
    if ($state.Position -ne $tokens.Count) { throw "Error parsing query: '$Filter'" }
    $tree
}

function Get-FakeADToken($State) {
    if ($State.Position -lt $State.Tokens.Count) { $State.Tokens[$State.Position] }
}

function Read-FakeADExpression($State) {
    # expression := and (-or and)*
    $left = Read-FakeADAnd $State
    while ((Get-FakeADToken $State) -eq '-or') {
        $State.Position++
        $left = @{ Kind = 'or'; Left = $left; Right = Read-FakeADAnd $State }
    }
    $left
}

function Read-FakeADAnd($State) {
    # and := unary (-and unary)*
    $left = Read-FakeADUnary $State
    while ((Get-FakeADToken $State) -eq '-and') {
        $State.Position++
        $left = @{ Kind = 'and'; Left = $left; Right = Read-FakeADUnary $State }
    }
    $left
}

function Read-FakeADUnary($State) {
    # unary := -not unary | ( expression ) | Attribute operator value
    $token = Get-FakeADToken $State
    if ($token -eq '-not') {
        $State.Position++
        return @{ Kind = 'not'; Operand = Read-FakeADUnary $State }
    }
    if ($token -eq '(') {
        $State.Position++
        $inner = Read-FakeADExpression $State
        if ((Get-FakeADToken $State) -ne ')') { throw "Error parsing query: '$($State.Filter)'" }
        $State.Position++
        return $inner
    }
    $attribute = $token
    $operator = $State.Tokens[$State.Position + 1]
    $value = $State.Tokens[$State.Position + 2]
    $State.Position += 3
    if ($attribute -notmatch '^(Name|Description|dNSHostName|DistinguishedName|objectClass|lastLogonTimestamp|whenCreated|Enabled|OperatingSystem)$' -or $null -eq $value) { throw "Error parsing query: '$($State.Filter)'" }
    if ($operator -in '-like', '-eq' -and $value -match "^'(.*)'$") {
        return @{ Kind = 'clause'; Attribute = $attribute; Operator = $operator; Value = $Matches[1] -replace "''", "'" }
    }
    if ($operator -in '-lt', '-le', '-gt', '-ge' -and $value -match '^\d+$') {
        return @{ Kind = 'clause'; Attribute = $attribute; Operator = $operator; Value = [int64]$value }
    }
    if ($operator -in '-lt', '-le', '-gt', '-ge' -and $attribute -eq 'whenCreated' -and $value -match '^\$(\w+)$') {
        $date = if ($State.SessionState) { $State.SessionState.PSVariable.GetValue($Matches[1]) }
        if ($date -isnot [datetime]) { throw "Variable: '$($Matches[1])' found in expression: $value is not defined." }
        return @{ Kind = 'clause'; Attribute = $attribute; Operator = $operator; Value = $date }
    }
    throw "Error parsing query: '$($State.Filter)'"
}

function Test-FakeADLike {
    # AD's -like only knows the * wildcard (a literal * is \2a and a backslash \5c), and never matches an attribute that
    # isn't set.
    param($Value, [string]$Pattern)

    if ($null -eq $Value) { return $false }
    $parts = foreach ($part in $Pattern -split '\*') { [regex]::Escape(($part -replace '\\2a', '*' -replace '\\5c', '\')) }
    $regex = '^' + ($parts -join '.*') + '$'
    return [regex]::IsMatch($Value, $regex, 'IgnoreCase')
}

function Test-FakeADFilter($Tree, $Object) {
    # Whether an object matches a parsed filter. Like AD, a clause on an attribute that isn't set is false.
    switch ($Tree.Kind) {
        'and' { return (Test-FakeADFilter $Tree.Left $Object) -and (Test-FakeADFilter $Tree.Right $Object) }
        'or' { return (Test-FakeADFilter $Tree.Left $Object) -or (Test-FakeADFilter $Tree.Right $Object) }
        'not' { return -not (Test-FakeADFilter $Tree.Operand $Object) }
    }
    $value = $Object.($Tree.Attribute)
    if ($Tree.Operator -notin '-like', '-eq' -and $null -ne $value) {
        # A number (lastLogonTimestamp), or a date (whenCreated).
        $value = if ($Tree.Value -is [datetime]) { [datetime]$value } else { [int64]$value }
    }
    switch ($Tree.Operator) {
        '-like' { Test-FakeADLike $value $Tree.Value }
        '-eq' { $null -ne $value -and [string]::Equals([string]$value, $Tree.Value, [System.StringComparison]::OrdinalIgnoreCase) }
        '-lt' { $null -ne $value -and $value -lt $Tree.Value }
        '-le' { $null -ne $value -and $value -le $Tree.Value }
        '-gt' { $null -ne $value -and $value -gt $Tree.Value }
        '-ge' { $null -ne $value -and $value -ge $Tree.Value }
    }
}

function Select-FakeADObject {
    # The objects that match a filter. $SessionState: the caller's, for the variables a filter names.
    param([object[]]$InputObject, [string]$Filter, [System.Management.Automation.SessionState]$SessionState)

    $tree = ConvertFrom-FakeADFilter $Filter $SessionState
    foreach ($object in $InputObject) {
        if (-not $tree -or (Test-FakeADFilter $tree $object)) { $object }
    }
}
function Get-FakeADOrganizationalUnitList {
    if ($env:REPERE_FAKEAD_NO_COMMON_OU) {
        $script:OrganizationalUnits | Where-Object { $_.Name -notlike 'Communs*' }
    }
    else {
        $script:OrganizationalUnits
    }
}

function Write-FakeADLog([hashtable]$Entry) {
    # Searches of several domains log at the same time, from their own runspaces.
    if ($env:REPERE_FAKEAD_LOG) {
        $line = ($Entry | ConvertTo-Json -Compress) + [Environment]::NewLine
        [System.Threading.Monitor]::Enter($script:Store.LogLock)
        try { [System.IO.File]::AppendAllText($env:REPERE_FAKEAD_LOG, $line) }
        finally { [System.Threading.Monitor]::Exit($script:Store.LogLock) }
    }
}

function Resolve-FakeADDomain([string]$Server) {
    # The domain a command goes to: -Server (a domain, or one of its DCs: dc1.demo.local, its PDC, dc2 or dc3), or the
    # user's domain. Returns its DN.
    if (-not $Server) { $Server = $script:DefaultDomain }
    $Server = $Server -replace ':3268$', ''
    # A DC's name (dc1.demo.local, the PDC) takes that DC down alone: its domain itself, and its other DCs, still answer.
    $unreachable = @("$env:REPERE_FAKEAD_UNREACHABLE" -split ';' | Where-Object { $_ })
    $down = $unreachable -contains $Server
    if ($Server -match '^dc[1-3]\.' -and $script:Domains.Contains($Server.Substring(4))) { $Server = $Server.Substring(4) }
    if ($down -or -not $script:Domains.Contains($Server) -or $unreachable -contains $Server) {
        throw [ADServerDownException]::new('Unable to contact the server. This may be because this server does not exist, it is currently down, or it does not have the Active Directory Web Services running.')
    }
    foreach ($pair in "$env:REPERE_FAKEAD_SLOW" -split ';') {
        $domain, $milliseconds = $pair -split '=', 2
        if ($domain.Trim() -eq $Server -and [int]::TryParse("$milliseconds", [ref]$null)) { Start-Sleep -Milliseconds ([int]$milliseconds) }
    }
    $script:Domains[$Server]
}

function Test-FakeADInDomain([string]$DistinguishedName, [string]$DomainDN) {
    # Whether an object belongs to this domain: demo.local's DN ends nord's DNs too, so the domain is the
    # longest DN that ends the object's DN.
    $owner = $script:Domains.Values |
        Where-Object { $DistinguishedName.EndsWith(",$_", [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    $owner -eq $DomainDN
}

function Find-FakeADComputer([string]$Identity, [string]$DomainDN) {
    # Repère passes the DN as -Identity. A computer of another domain isn't found, as in the real AD.
    $computer = $script:Store.Computers | Where-Object { $_.DistinguishedName -eq $Identity -and (Test-FakeADInDomain $_.DistinguishedName $DomainDN) }
    if (-not $computer) { throw "Cannot find an object with identity: '$Identity' under: '$DomainDN'." }
    $computer
}

function Add-FakeADMembership($Copy, [string]$DomainDN, [int]$PrimaryRid) {
    # What Groupes… reads, added to a copy of a computer, user or group: its direct groups (MemberOf: those of the domain
    # asked, as a DC that isn't a global catalog knows them), its primary group (a computer's own RID, 513 for users),
    # and the SIDs of every security group it belongs to, nested ones included (tokenGroups: global and universal groups
    # of any domain, domain local ones of its own).
    $direct = @($script:Store.Groups | Where-Object { $_.Members -contains $Copy.DistinguishedName -and (Test-FakeADInDomain $_.DistinguishedName $DomainDN) })
    $primary = $script:Store.Groups | Where-Object { $_.SID -like "*-$PrimaryRid" -and (Test-FakeADInDomain $_.DistinguishedName $DomainDN) }
    $counts = { param($group) $group.GroupCategory -eq 'Security' -and ($group.GroupScope -ne 'DomainLocal' -or (Test-FakeADInDomain $group.DistinguishedName $DomainDN)) }
    $security = [System.Collections.Generic.List[object]]::new()
    $listing = @($script:Store.Groups | Where-Object { $_.Members -contains $Copy.DistinguishedName })
    foreach ($group in @($listing) + @($primary)) { if ((& $counts $group) -and -not $security.Contains($group)) { $security.Add($group) } }
    for ($i = 0; $i -lt $security.Count; $i++) {
        foreach ($outer in $script:Store.Groups) {
            if ((& $counts $outer) -and $outer.Members -contains $security[$i].DistinguishedName -and -not $security.Contains($outer)) { $security.Add($outer) }
        }
    }
    $Copy | Add-Member MemberOf @($direct | ForEach-Object DistinguishedName) -Force
    $Copy | Add-Member PrimaryGroup $primary.DistinguishedName -Force
    $Copy | Add-Member tokenGroups @($security | ForEach-Object SID) -Force
    $Copy
}

function Assert-FakeADBaseSearch([string[]]$Properties) {
    # tokenGroups asked for in a search (a filter) rather than of one object by its DN: AD computes it only for one
    # object, and refuses the search, as it did on a real domain.
    if ($Properties -contains 'tokenGroups') { throw 'The requested search operation is only supported for base searches' }
}

function Find-FakeADGroup([string]$Identity, [string]$DomainDN) {
    $group = $script:Store.Groups | Where-Object { ($_.DistinguishedName -eq $Identity -or $_.SID -eq $Identity) -and (Test-FakeADInDomain $_.DistinguishedName $DomainDN) }
    if (-not $group) { throw "Cannot find an object with identity: '$Identity' under: '$DomainDN'." }
    $group
}

function Get-FakeADChildObject([string]$ParentDN) {
    $script:Store.ChildObjects | Where-Object { $_.DistinguishedName.Substring($_.DistinguishedName.IndexOf(',') + 1) -eq $ParentDN }
}

function Remove-FakeADComputer([string]$Identity, [string]$DomainDN, [switch]$Recursive) {
    $computer = Find-FakeADComputer $Identity $DomainDN
    if ($computer.ProtectedFromAccidentalDeletion) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    if ($computer.PSObject.Properties['DenyWrite'] -and $computer.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $children = @(Get-FakeADChildObject $Identity)
    if ($children.Count -and -not $Recursive) {
        throw [ADException]::new('The directory service can perform the requested operation only on a leaf object', 8213)
    }
    $script:Store.ChildObjects = @($script:Store.ChildObjects | Where-Object { $children -notcontains $_ })
    # Replaced, not changed in place: a search may be reading the current list from another runspace.
    $script:Store.Computers = @($script:Store.Computers | Where-Object { $_ -ne $computer })
}

function Test-FakeLdapUser($User, [string]$Filter) {
    # The LDAP filters the Utilisateurs page builds: (&(objectCategory=person)(objectClass=user)…) with (anr=…),
    # (lockoutTime>=1), (userAccountControl:1.2.840.113556.1.4.803:=2) for disabled accounts, (description=*…*), and
    # (distinguishedName=…) for one user opened from a group's members, and an OR of logins, UPNs, emails and names
    # (Liste d'identifiants).
    # anr matches the start of the first name, last name, display name, login or email, or of « first last ».
    # An OR inside the AND: whether one of its clauses matches, then taken out of it.
    foreach ($inner in [regex]::Matches($Filter, '\(\|(?:\([^()]+\))+\)')) {
        if (-not @([regex]::Matches($inner.Value, '\([^()|]+\)') | Where-Object { Test-FakeLdapUser $User $_.Value }).Count) { return $false }
        $Filter = $Filter.Replace($inner.Value, '')
    }
    foreach ($clause in [regex]::Matches($Filter, '\(([^()&|!]+)\)')) {
        $text = $clause.Groups[1].Value
        $value = if ($text -match '^[^=<>]+[<>]?=(.*)$') { $Matches[1] -replace '\\2a', '*' -replace '\\28', '(' -replace '\\29', ')' -replace '\\5c', '\' } else { '' }
        $matched = switch -Regex ($text) {
            '^objectCategory=person$' { $true }
            '^objectClass=user$' { $true }
            '^anr=' {
                $candidates = @($User.GivenName, $User.Surname, $User.DisplayName, $User.SamAccountName, $User.mail, "$($User.GivenName) $($User.Surname)", "$($User.Surname) $($User.GivenName)")
                [bool]@($candidates | Where-Object { $_ -and $_.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase) }).Count
            }
            '^lockoutTime>=1$' { [int64]$User.lockoutTime -ge 1 }
            '^userAccountControl:1\.2\.840\.113556\.1\.4\.803:=2$' { -not $User.Enabled }
            '^description=' { Test-FakeADLike $User.Description $value }
            '^distinguishedName=' { $User.DistinguishedName -eq $value }
            '^sAMAccountName=' { $User.SamAccountName -eq $value }
            '^userPrincipalName=' { $User.UserPrincipalName -eq $value }
            '^mail=' { $User.mail -and $User.mail -eq $value }
            '^displayName=' { $User.DisplayName -and $User.DisplayName -eq $value }
            '^name=' { $User.Name -eq $value }
            default { throw "Error parsing query: '$Filter'" }
        }
        if (-not $matched) { return $false }
    }
    $true
}

function Find-FakeADUser([string]$Identity, [string]$DomainDN) {
    $user = $script:Store.Users | Where-Object { $_.DistinguishedName -eq $Identity -and (Test-FakeADInDomain $_.DistinguishedName $DomainDN) }
    if (-not $user) { throw "Cannot find an object with identity: '$Identity' under: '$DomainDN'." }
    $user
}

function Get-ADUser {
    # A search with -LDAPFilter, or one user by its DN (-Identity).
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [string]$LDAPFilter,

        [Parameter(Mandatory, ParameterSetName = 'Identity')]
        [string]$Identity,

        # A search's results at most, as AD stops sending them (logged, for the tests that check a search is bounded).
        [Parameter(ParameterSetName = 'Filter')]
        [int]$ResultSetSize = [int]::MaxValue,

        [string[]]$Properties,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADUser'; LDAPFilter = $LDAPFilter; Identity = $Identity; Server = $Server
                       ResultSetSize = $(if ($PSBoundParameters.ContainsKey('ResultSetSize')) { $ResultSetSize }) }
    $domainDN = Resolve-FakeADDomain $Server
    if ($Identity) {
        $user = Find-FakeADUser $Identity $domainDN
        if ($Properties -contains 'tokenGroups' -and $user.DenyTokenGroups) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
        $copy = Add-FakeADMembership ($user | Select-Object *) $domainDN 513
        # tokenGroups only when asked for, like the real cmdlet's constructed attributes.
        if ($Properties -notcontains 'tokenGroups') { $copy.PSObject.Properties.Remove('tokenGroups') }
        return $copy
    }
    Assert-FakeADBaseSearch $Properties
    $script:Store.Users | Where-Object { (Test-FakeADInDomain $_.DistinguishedName $domainDN) -and (Test-FakeLdapUser $_ $LDAPFilter) } |
        Select-Object -First $ResultSetSize | Select-Object *
}

function Unlock-ADAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Unlock-ADAccount'; Identity = $Identity; Server = $Server }
    $user = Find-FakeADUser $Identity (Resolve-FakeADDomain $Server)
    if ($user.DenyWrite) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    $user.LockedOut = $false
    $user.lockoutTime = 0
}

function Set-ADAccountPassword {
    # Like a domain whose policy wants at least 10 characters. The password itself is never logged: only its length.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [switch]$Reset,
        [securestring]$NewPassword,
        [string]$Server
    )

    $length = if ($NewPassword) { $NewPassword.Length } else { 0 }
    Write-FakeADLog @{ Command = 'Set-ADAccountPassword'; Identity = $Identity; Reset = [bool]$Reset; Length = $length; Server = $Server }
    $user = Find-FakeADUser $Identity (Resolve-FakeADDomain $Server)
    if ($user.DenyWrite) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    if ($length -lt 10) { throw 'The password does not meet the length, complexity, or history requirement of the domain.' }
    $user.PasswordLastSet = Get-Date
    $user.PasswordExpired = $false
    $user.'msDS-UserPasswordExpiryTimeComputed' = if ($user.PasswordNeverExpires) { [int64]::MaxValue } else { (Get-Date).AddDays(90).ToFileTime() }
}

# The attributes Set-ADUser's -Replace and -Clear change (Propriétés' Modifier…, #138), by their LDAP name in lower
# case: the property the fake user keeps it as, and the most characters AD takes (the schema's rangeUpper; 0: none).
$script:FakeUserAttributes = @{
    givenname = 'GivenName', 64; sn = 'Surname', 64; displayname = 'DisplayName', 256; mail = 'mail', 256; employeeid = 'EmployeeID', 16
    title = 'Title', 128; department = 'Department', 64; company = 'Company', 64; physicaldeliveryofficename = 'Office', 128; manager = 'Manager', 0
    telephonenumber = 'OfficePhone', 64; mobile = 'MobilePhone', 64; description = 'Description', 1024
    homedirectory = 'HomeDirectory', 0; homedrive = 'HomeDrive', 0; profilepath = 'ProfilePath', 0; scriptpath = 'ScriptPath', 0
}

function Set-ADUser {
    # « Must change the password at next logon » (pwdLastSet to 0, which AD shows as an expiry of 0), refused as AD does
    # for a password that never expires; and the attributes of $FakeUserAttributes, -Replace'd or -Clear'ed. Like AD's
    # one LDAP modify, written whole or not at all: refused for a user the current one can't change (DenyWrite), an
    # attribute it has no right on (the user's DenyAttributes), a value longer than AD takes, or a manager that isn't a
    # user.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [bool]$ChangePasswordAtLogon,
        [hashtable]$Replace,
        [string[]]$Clear,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Set-ADUser'; Identity = $Identity; ChangePasswordAtLogon = $ChangePasswordAtLogon; Server = $Server
                       Replace = $(if ($Replace) { @($Replace.Keys | Sort-Object | ForEach-Object { "$_=$($Replace[$_])" }) -join ';' }); Clear = $Clear -join ',' }
    $user = Find-FakeADUser $Identity (Resolve-FakeADDomain $Server)
    if ($user.DenyWrite) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    $denied = @($user.PSObject.Properties['DenyAttributes'] | ForEach-Object { $_.Value })
    $writes = @(@($Replace.Keys) + @($Clear) | Where-Object { $_ })
    foreach ($name in $writes) {
        $attribute = $script:FakeUserAttributes[$name.ToLowerInvariant()]
        if (-not $attribute) { throw "The specified directory service attribute or value does not exist: $name" }
        if ($denied -contains $name) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
        if ($Replace -and $Replace.ContainsKey($name)) {
            $value = [string]$Replace[$name]
            if ($attribute[1] -and $value.Length -gt $attribute[1]) { throw 'A value for the attribute was not in the acceptable range of values' }
            if ($name -eq 'manager' -and -not @($script:Store.Users | Where-Object DistinguishedName -eq $value).Count) { throw 'The name reference is invalid' }
        }
    }
    foreach ($name in $writes) {
        $user.($script:FakeUserAttributes[$name.ToLowerInvariant()][0]) = if ($Replace -and $Replace.ContainsKey($name)) { [string]$Replace[$name] } else { $null }
    }
    if ($ChangePasswordAtLogon -and $user.PasswordNeverExpires) {
        throw "ChangePasswordAtLogon can not be set to `$true for an account that also has the PasswordNeverExpires property set to true."
    }
    if ($ChangePasswordAtLogon) {
        $user.PasswordLastSet = $null
        $user.PasswordExpired = $true
        $user.'msDS-UserPasswordExpiryTimeComputed' = 0
    }
}

function Get-ADForest {
    # Only the domain list Repère reads.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Current', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param(
        [string]$Current,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADForest'; Server = $Server }
    $null = Resolve-FakeADDomain $Server
    [pscustomobject]@{ Name = $script:DefaultDomain; Domains = @($script:Domains.Keys) }
}

function Get-ADDomain {
    # Only what Repère reads: the domain's DN, its default computers container, its PDC and its SID.
    [CmdletBinding()]
    param(
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADDomain'; Server = $Server }
    $domainDN = Resolve-FakeADDomain $Server
    $root = if ($Server) { $Server } else { $script:DefaultDomain }
    $name = @($script:Domains.Keys | Where-Object { $script:Domains[$_] -eq $domainDN })[0]
    [pscustomobject]@{ DistinguishedName = $domainDN; DNSRoot = $root; ComputersContainer = "CN=Computers,$domainDN"; PDCEmulator = "dc1.$root"; DomainSID = $script:DomainSids[$name] }
}

function Get-ADComputer {
    # A search with -Filter, one with -LDAPFilter (the computers a selection names by DN: Test-FakeLdapMember), or one
    # computer by its DN (-Identity).
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter(Mandatory, ParameterSetName = 'LDAPFilter')]
        [string]$LDAPFilter,

        [Parameter(Mandatory, ParameterSetName = 'Identity')]
        [string]$Identity,

        # Searches this OU and everything under it instead of the whole domain.
        [Parameter(ParameterSetName = 'Filter')]
        [string]$SearchBase,

        # A search's results at most (logged, for the tests that check a search is bounded).
        [Parameter(ParameterSetName = 'Filter')]
        [int]$ResultSetSize = [int]::MaxValue,

        # Accepted for compatibility: the fake computers already have every property.
        [string[]]$Properties,

        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADComputer'; Filter = $Filter; LDAPFilter = $LDAPFilter; Identity = $Identity; SearchBase = $SearchBase; Server = $Server
                       ResultSetSize = $(if ($PSBoundParameters.ContainsKey('ResultSetSize')) { $ResultSetSize }) }
    $domainDN = Resolve-FakeADDomain $Server
    if ($LDAPFilter) {
        return $script:Store.Computers | Where-Object {
            (Test-FakeADInDomain $_.DistinguishedName $domainDN) -and (Test-FakeLdapMember ([pscustomobject]@{ DistinguishedName = $_.DistinguishedName; ObjectClass = 'computer'; Name = $_.Name; sAMAccountName = $_.SamAccountName; PrimaryGroupID = $_.PrimaryGroupID }) $LDAPFilter $domainDN)
        } | Select-Object *
    }
    if ($Identity) {
        # A copy, with what Groupes… reads: its direct groups (MemberOf), its primary group, and the SIDs of every
        # security group it belongs to, nested ones included (tokenGroups).
        $computer = Find-FakeADComputer $Identity $domainDN
        $copy = Add-FakeADMembership ($computer | Select-Object *) $domainDN $computer.PrimaryGroupID
        if ($Properties -notcontains 'tokenGroups') { $copy.PSObject.Properties.Remove('tokenGroups') }
        return $copy
    }
    Assert-FakeADBaseSearch $Properties
    $computers = $script:Store.Computers | Where-Object { Test-FakeADInDomain $_.DistinguishedName $domainDN }
    if ($SearchBase) {
        $ouDNs = @(Get-FakeADOrganizationalUnitList | Where-Object { Test-FakeADInDomain $_.DistinguishedName $domainDN }).DistinguishedName
        if ($SearchBase -ne $domainDN -and $ouDNs -notcontains $SearchBase) {
            throw "Directory object not found: '$SearchBase'"
        }
        $computers = $computers | Where-Object { $_.DistinguishedName.EndsWith(",$SearchBase", [System.StringComparison]::OrdinalIgnoreCase) }
    }
    Select-FakeADObject $computers $Filter $PSCmdlet.SessionState | Select-Object -First $ResultSetSize
}

function Get-ADOrganizationalUnit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Filter,

        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADOrganizationalUnit'; Filter = $Filter; Server = $Server }
    $domainDN = Resolve-FakeADDomain $Server
    Select-FakeADObject @(Get-FakeADOrganizationalUnitList | Where-Object { Test-FakeADInDomain $_.DistinguishedName $domainDN }) $Filter
}

function Test-FakeLdapMember($Object, [string]$Filter, [string]$DomainDN, [switch]$GlobalCatalog) {
    # The LDAP filters of a group's Propriétés: (memberOf=<group DN>) for its members, (primaryGroupID=<RID>) for the
    # accounts whose primary group it is (513 for users, a computer's own: 515 for most), (primaryGroupID=*) for those
    # that have one, (objectClass=user) (users and computers) for Sans membres, and (anr=…), the start of a name or login.
    # A member searched by the start of its name: (name=jul*), and the same for sAMAccountName, displayName, givenName and
    # sn, in an OR. An OR of (distinguishedName=…): the objects a selection names (Retirer d'un groupe…).
    # memberOf is known where the group's member list is: a DC of its domain, or the global catalog for a universal one.
    # A filter that starts with (| matches when any of its clauses does: (|(primaryGroupID=516)(primaryGroupID=521)), a
    # domain's controllers. Otherwise all of them must, a (!(…)) must not match (Sans membres: the accounts whose
    # primary group isn't a usual one), and a (|(…)(…)) must, by any of its clauses (a member's name searched).
    $any = $Filter.StartsWith('(|')
    if (-not $any) {
        foreach ($inner in [regex]::Matches($Filter, '\(!(\([^()]+\))\)')) {
            if (Test-FakeLdapMember $Object $inner.Groups[1].Value $DomainDN -GlobalCatalog:$GlobalCatalog) { return $false }
            $Filter = $Filter.Replace($inner.Value, '')
        }
        foreach ($inner in [regex]::Matches($Filter, '\(\|(?:\([^()]+\))+\)')) {
            if (-not (Test-FakeLdapMember $Object $inner.Value $DomainDN -GlobalCatalog:$GlobalCatalog)) { return $false }
            $Filter = $Filter.Replace($inner.Value, '')
        }
    }
    foreach ($clause in [regex]::Matches($Filter, '\(([^()&|!]+)\)')) {
        $text = $clause.Groups[1].Value
        $value = if ($text -match '^[^=]+=(.*)$') { $Matches[1] } else { '' }
        # A value that ends with a * not escaped (\2a) is the start of one: name=jul*.
        $starts = $value.Length -gt 1 -and $value.EndsWith('*')
        if ($starts) { $value = $value.Substring(0, $value.Length - 1) }
        $value = $value -replace '\\2a', '*' -replace '\\28', '(' -replace '\\29', ')' -replace '\\5c', '\'
        # A user's primary group is always Utilisateurs du domaine (513); a group has none.
        $primaryGroup = if ($Object.PSObject.Properties['PrimaryGroupID']) { $Object.PrimaryGroupID } elseif ($Object.ObjectClass -eq 'user') { 513 }
        $matched = switch -Regex ($text) {
            '^memberOf=' {
                [bool]@($script:Store.Groups | Where-Object {
                    $_.DistinguishedName -eq $value -and $_.Members -contains $Object.DistinguishedName -and
                    $(if ($GlobalCatalog) { $_.GroupScope -eq 'Universal' } else { Test-FakeADInDomain $_.DistinguishedName $DomainDN })
                }).Count
            }
            # Has one at all; break: switch -Regex would also run the next case, and two answers count as a match.
            '^primaryGroupID=\*$' { $null -ne $primaryGroup; break }
            '^primaryGroupID=' { $null -ne $primaryGroup -and "$primaryGroup" -eq $value }
            # Users and computers (a computer is a user to AD).
            '^objectClass=user$' { $Object.ObjectClass -in 'user', 'computer' }
            '^(name|sAMAccountName|displayName|givenName|sn)=' {
                $actual = [string]$Object.(@{ name = 'Name'; sAMAccountName = 'sAMAccountName'; displayName = 'DisplayName'; givenName = 'GivenName'; sn = 'Surname' }[$Matches[1]])
                if ($starts) { $actual -and $actual.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase) } else { $actual -eq $value }
            }
            '^distinguishedName=' { $Object.DistinguishedName -eq $value }
            '^anr=' { [bool]@($Object.Name, $Object.sAMAccountName, $Object.GivenName, $Object.Surname | Where-Object { $_ -and $_.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase) }).Count }
            default { throw "Error parsing query: '$Filter'" }
        }
        if ($any -and $matched) { return $true }
        if (-not $any -and -not $matched) { return $false }
    }
    -not $any
}

function Get-ADObject {
    # Only what Repère asks for: one object by -Identity, the objects directly under a computer, the BitLocker recovery
    # information an ID finds, or the users, computers and groups an -LDAPFilter finds (a group's members), -ResultSetSize
    # at most: in the domain asked, or in the whole
    # forest from the global catalog (-Server <dc>:3268, -SearchBase ''). -Properties: as the real cmdlet's.
    [CmdletBinding()]
    param(
        [string]$Identity,
        [string]$Filter,
        [string]$LDAPFilter,
        [string]$SearchBase,
        [string]$SearchScope,
        [string[]]$Properties,
        [int]$ResultSetSize = [int]::MaxValue,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADObject'; Identity = $Identity; Filter = $Filter; LDAPFilter = $LDAPFilter; SearchBase = $SearchBase; SearchScope = $SearchScope
                       ResultSetSize = $(if ($PSBoundParameters.ContainsKey('ResultSetSize')) { $ResultSetSize }); Server = $Server }
    $domainDN = Resolve-FakeADDomain $Server
    $globalCatalog = $Server -match ':3268$'
    if (-not $Identity) { Assert-FakeADBaseSearch $Properties }
    if ($LDAPFilter -match '^\(&\(objectClass=msFVE-RecoveryInformation\)\(name=\*\{([0-9A-F-]+)\*\)\)$') {
        # ID de clé BitLocker: the recovery information of the domain asked whose name holds {<the ID's start>.
        $id = $Matches[1]
        return $script:Store.ChildObjects | Where-Object {
            $_.ObjectClass -eq 'msFVE-RecoveryInformation' -and $_.Name -like "*{$id*" -and (Test-FakeADInDomain $_.DistinguishedName $domainDN)
        } | Select-Object -First $ResultSetSize | Select-Object Name, DistinguishedName, ObjectClass
    }
    if ($LDAPFilter) {
        $objects = @(
            foreach ($user in $script:Store.Users) { [pscustomobject]@{ Name = $user.Name; DistinguishedName = $user.DistinguishedName; ObjectClass = 'user'; sAMAccountName = $user.SamAccountName; DisplayName = $user.DisplayName; GivenName = $user.GivenName; Surname = $user.Surname; PrimaryGroupID = 513 } }
            foreach ($computer in $script:Store.Computers) { [pscustomobject]@{ Name = $computer.Name; DistinguishedName = $computer.DistinguishedName; ObjectClass = 'computer'; sAMAccountName = $computer.SamAccountName; PrimaryGroupID = $computer.PrimaryGroupID } }
            foreach ($group in $script:Store.Groups) { [pscustomobject]@{ Name = $group.Name; DistinguishedName = $group.DistinguishedName; ObjectClass = 'group'; sAMAccountName = $group.SamAccountName; PrimaryGroupID = $null } }
        )
        # -Properties primaryGroupID: only when asked for, as the real cmdlet's.
        $read = @('Name', 'DistinguishedName', 'ObjectClass', 'sAMAccountName') + @(if ($Properties -contains 'primaryGroupID') { 'PrimaryGroupID' })
        $matched = $objects | Where-Object { ($globalCatalog -or (Test-FakeADInDomain $_.DistinguishedName $domainDN)) -and (Test-FakeLdapMember $_ $LDAPFilter $domainDN -GlobalCatalog:$globalCatalog) } |
            Select-Object -First $ResultSetSize | Select-Object $read
        # -Properties MemberOf: each one's direct groups, as the domain asked knows them (Add-FakeADMembership).
        if ($Properties -notcontains 'MemberOf') { return $matched }
        return $matched | ForEach-Object {
            $dn = $_.DistinguishedName
            $_ | Add-Member -NotePropertyName MemberOf -NotePropertyValue @($script:Store.Groups | Where-Object { $_.Members -contains $dn -and (Test-FakeADInDomain $_.DistinguishedName $domainDN) } | ForEach-Object DistinguishedName) -PassThru
        }
    }
    if ($Identity) {
        $user = $script:Store.Users | Where-Object { $_.DistinguishedName -eq $Identity -and (Test-FakeADInDomain $_.DistinguishedName $domainDN) }
        $group = $script:Store.Groups | Where-Object { $_.DistinguishedName -eq $Identity -and (Test-FakeADInDomain $_.DistinguishedName $domainDN) }
        if ($user) { return [pscustomobject]@{ Name = $user.Name; DistinguishedName = $user.DistinguishedName; ObjectClass = 'user'; sAMAccountName = $user.SamAccountName } }
        if ($group) { return [pscustomobject]@{ Name = $group.Name; DistinguishedName = $group.DistinguishedName; ObjectClass = 'group'; sAMAccountName = $group.SamAccountName } }
        $computer = Find-FakeADComputer $Identity $domainDN
        return [pscustomobject]@{
            Name                            = $computer.Name
            DistinguishedName               = $computer.DistinguishedName
            ObjectClass                     = 'computer'
            sAMAccountName                  = $computer.SamAccountName
            ProtectedFromAccidentalDeletion = $computer.ProtectedFromAccidentalDeletion
            PrimaryGroupID                  = $computer.PrimaryGroupID
        }
    }
    if ($SearchScope -ne 'OneLevel') { throw 'The fake AD only lists the objects directly under a computer (-SearchScope OneLevel).' }
    $null = Find-FakeADComputer $SearchBase $domainDN
    Select-FakeADObject @(Get-FakeADChildObject $SearchBase) $Filter
}

function Set-ADComputer {
    # The description, and what a computer's Propriétés changes: its physical location and who manages it (a DN).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [string]$Description,
        [string]$Location,
        [string]$ManagedBy,
        [string[]]$Clear,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Set-ADComputer'; Identity = $Identity; Description = $Description; Location = $Location; ManagedBy = $ManagedBy; Clear = $Clear -join ','; Server = $Server }
    $computer = Find-FakeADComputer $Identity (Resolve-FakeADDomain $Server)
    if ($computer.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    if ($Clear -contains 'Description') { $computer.Description = $null }
    elseif ($PSBoundParameters.ContainsKey('Description')) { $computer.Description = $Description }
    if ($Clear -contains 'location') { $computer.Location = $null }
    elseif ($PSBoundParameters.ContainsKey('Location')) { $computer.Location = $Location }
    if ($Clear -contains 'managedBy') { $computer.ManagedBy = $null }
    elseif ($PSBoundParameters.ContainsKey('ManagedBy')) { $computer.ManagedBy = $ManagedBy }
}

function Set-ADObject {
    # A computer's protection from accidental deletion (its Propriétés › Objet).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [Parameter(Mandatory)]
        [bool]$ProtectedFromAccidentalDeletion,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Set-ADObject'; Identity = $Identity; ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion; Server = $Server }
    $computer = Find-FakeADComputer $Identity (Resolve-FakeADDomain $Server)
    if ($computer.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $computer.ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion
}

function Enable-ADAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Enable-ADAccount'; Identity = $Identity; Server = $Server }
    $account = Find-FakeADAccount $Identity (Resolve-FakeADDomain $Server)
    if ($account.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $account.Enabled = $true
}

function Find-FakeADAccount([string]$Identity, [string]$DomainDN) {
    # A computer or a user, by its DN: what Enable-ADAccount and Disable-ADAccount take.
    $user = $script:Store.Users | Where-Object { $_.DistinguishedName -eq $Identity }
    if ($user) { Find-FakeADUser $Identity $DomainDN } else { Find-FakeADComputer $Identity $DomainDN }
}

function Disable-ADAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Disable-ADAccount'; Identity = $Identity; Server = $Server }
    $account = Find-FakeADAccount $Identity (Resolve-FakeADDomain $Server)
    if ($account.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $account.Enabled = $false
}

function Remove-ADComputer {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Remove-ADComputer'; Identity = $Identity; Server = $Server }
    $domainDN = Resolve-FakeADDomain $Server
    if ($PSCmdlet.ShouldProcess($Identity)) { Remove-FakeADComputer $Identity $domainDN }
}

function Remove-ADObject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [switch]$Recursive,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Remove-ADObject'; Identity = $Identity; Recursive = [bool]$Recursive; Server = $Server }
    $domainDN = Resolve-FakeADDomain $Server
    if (-not $PSCmdlet.ShouldProcess($Identity)) { return }
    # An object held by a computer (BitLocker recovery information), or a computer.
    $child = $script:Store.ChildObjects | Where-Object { $_.DistinguishedName -eq $Identity -and (Test-FakeADInDomain $_.DistinguishedName $domainDN) }
    if ($child) {
        if ($child.DenyDelete) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
        $script:Store.ChildObjects = @($script:Store.ChildObjects | Where-Object { $_ -ne $child })
    }
    elseif ($script:Store.ChildObjects | Where-Object DistinguishedName -eq $Identity) {
        throw "Cannot find an object with identity: '$Identity' under: '$domainDN'."
    }
    else {
        Remove-FakeADComputer $Identity $domainDN -Recursive:$Recursive
    }
}

function Get-LapsADPassword {
    # Windows LAPS's own cmdlet: the password in msLAPS-Password, or in msLAPS-EncryptedPassword decrypted when the
    # user is allowed to (Password and Account are then empty, DecryptionStatus Unauthorized). Nothing for a computer
    # without a Windows LAPS password.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Fake passwords, returned as SecureString like the real cmdlet.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Identity,

        [string]$Domain,

        [switch]$AsPlainText
    )

    Write-FakeADLog @{ Command = 'Get-LapsADPassword'; Identity = "$Identity"; Domain = $Domain; AsPlainText = [bool]$AsPlainText }
    $domainDN = Resolve-FakeADDomain $Domain
    foreach ($name in $Identity) {
        $computer = Find-FakeADComputer $name $domainDN
        if ($computer.'msLAPS-Password') {
            $source, $status, $content = 'CleartextPassword', 'NotApplicable', $computer.'msLAPS-Password'
        }
        elseif ($computer.'msLAPS-EncryptedPassword') {
            $content = $computer.FakeLapsDecrypted
            $source, $status = 'EncryptedPassword', $(if ($content) { 'Success' } else { 'Unauthorized' })
        }
        else {
            continue
        }
        $decoded = if ($content) { $content | ConvertFrom-Json }
        $password = if ($decoded) { if ($AsPlainText) { $decoded.p } else { ConvertTo-SecureString $decoded.p -AsPlainText -Force } }
        [pscustomobject]@{
            ComputerName        = $computer.Name
            DistinguishedName   = $computer.DistinguishedName
            Account             = if ($decoded) { $decoded.n }
            Password            = $password
            PasswordUpdateTime  = if ($decoded) { [datetime]::FromFileTimeUtc([Convert]::ToInt64($decoded.t, 16)).ToLocalTime() }
            ExpirationTimestamp = [datetime]::FromFileTime($computer.'msLAPS-PasswordExpirationTime')
            Source              = $source
            DecryptionStatus    = $status
            AuthorizedDecryptor = if ($source -eq 'EncryptedPassword') { 'DEMO\Admins LAPS' } else { 'NotApplicable' }
        }
    }
}

function Move-ADObject {
    # Moves a computer (and the objects it holds) to an OU or the default computers container of its domain.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Move-ADObject'; Identity = $Identity; TargetPath = $TargetPath; Server = $Server }
    $domainDN = Resolve-FakeADDomain $Server
    $computer = Find-FakeADComputer $Identity $domainDN
    if ($computer.ProtectedFromAccidentalDeletion) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    if ($computer.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $targets = @(@(Get-FakeADOrganizationalUnitList | Where-Object { Test-FakeADInDomain $_.DistinguishedName $domainDN }).DistinguishedName) + "CN=Computers,$domainDN"
    if ($targets -notcontains $TargetPath) { throw "Directory object not found: '$TargetPath'" }
    if (-not $PSCmdlet.ShouldProcess($Identity)) { return }
    $newDN = "CN=$($computer.Name),$TargetPath"
    foreach ($child in Get-FakeADChildObject $Identity) {
        $child.DistinguishedName = $child.DistinguishedName.Substring(0, $child.DistinguishedName.Length - $Identity.Length) + $newDN
    }
    $computer.DistinguishedName = $newDN
}

function Test-Connection {
    # Replaces the real one for the fake computers, which don't exist on the network. Only what Repère uses:
    # one ping or one TCP port, with -Quiet. Not logged: the online check calls it from parallel runspaces.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [CmdletBinding()]
    param(
        [string]$TargetName,
        [int]$TcpPort,
        [int]$Count,
        [int]$TimeoutSeconds,
        [switch]$Quiet
    )

    $online = $script:OnlineHosts[$TargetName]
    if ($PSBoundParameters.ContainsKey('TcpPort')) { $online -eq [string]$TcpPort } else { $online -eq 'ping' }
}

function Test-ComputerPort {
    # The ports Vérifier en ligne tries together on the fake computers: the first one open, or $null. Only ord-04 has
    # one (3389). For PowerShell à distance: WinRM (5985) on the computers where it runs (ord-01, and ord-04 once
    # Repère turns it on), DCOM (135) on those that answer CIM (ord-01 and ord-04).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TimeoutMilliseconds', Justification = 'Same parameters as the real one.')]
    param([string]$HostName, [int[]]$Ports, [int]$TimeoutMilliseconds)
    foreach ($port in $Ports) {
        if ($script:OnlineHosts[$HostName] -eq [string]$port) { return $port }
        if ($port -eq 5985 -and $script:Store.WinRM[$HostName]) { return $port }
        if ($port -eq 135 -and (Get-FakeCimData $HostName)) { return $port }
    }
    $null
}

function Resolve-DnsName {
    # The fake DNS: a computer's DNS name gives its address (ord-01 has an IPv6 one too), and with -Type PTR an address
    # gives the name back, except ord-04's (no PTR record: the IP search then looks up each computer's name). Like the
    # real one, a name or address it doesn't know is an error. Only what Repère uses: -Name and -Type.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'QuickTimeout', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [string]$Type,
        [switch]$QuickTimeout
    )

    if ($Type -eq 'PTR') {
        $computer = $script:Store.Computers | Where-Object { $_.IPAddress -and $_.IPAddress -eq $Name -and $_.DNSHostName -ne 'ord-04.demo.local' } | Select-Object -First 1
        if (-not $computer) { throw "$Name : DNS name does not exist" }
        return [pscustomobject]@{ Name = $Name; Type = 'PTR'; NameHost = $computer.DNSHostName }
    }
    $computer = $script:Store.Computers | Where-Object { $_.DNSHostName -and $_.DNSHostName -eq $Name } | Select-Object -First 1
    if (-not $computer) { throw "$Name : DNS name does not exist" }
    [pscustomobject]@{ Name = $Name; Type = 'A'; IPAddress = $computer.IPAddress }
    if ($Name -eq 'ord-01.demo.local') { [pscustomobject]@{ Name = $Name; Type = 'AAAA'; IPAddress = 'fd00:10::11' } }
}

function quser {
    # The sessions open on the fake computers, as a French Windows' quser lists them, for Prendre la main…: ord-01 has
    # the person at the desk (a local account) and the disconnected session of a technician of the domain (Jean
    # Bertrand), ord-04 its kiosk account (signed in on its own, through Remote Desktop), nobody is logged on ord-08, and ord-06
    # refuses the query (not an administrator). The others don't answer. Its errors come out as text, as quser's would
    # through 2>&1. Only what Repère uses: /server:<name>.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Replaces quser.exe, by its name.')]
    param()
    $server = "$(@($args) -match '^/server:')" -replace '^/server:', ''
    Write-FakeADLog @{ Command = 'quser'; Server = $server }
    # A computer whose RPC never answers: quser waits, much longer than Repère does.
    if ($server -and $server -eq $env:REPERE_FAKEAD_QUSER_HANG) { Start-Sleep -Seconds 120 }
    $today = (Get-Date).Date
    $header = ' UTILISATEUR           SESSION            ID  ÉTAT    TEMPS INACT TEMPS SESSION'
    $line = {
        param($User, $Session, $Id, $State, $Idle, [datetime]$Logon)
        [string]::Format([cultureinfo]'fr-FR', ' {0,-21} {1,-18} {2,2}  {3,-7} {4,10}  {5:dd/MM/yyyy HH:mm}', $User, $Session, $Id, $State, $Idle, $Logon)
    }
    switch ($server) {
        'ord-01.demo.local' {
            $header
            & $line 'accueil' 'console' 1 'Actif' '12' ($today + [timespan]'07:58')
            & $line 'jebertrand' '' 3 'Déco' '1:05' ($today.AddDays(-1) + [timespan]'16:20')
        }
        'ord-04.demo.local' {
            $header
            & $line 'kiosque' 'rdp-tcp#0' 2 'Actif' 'aucun' ($today.AddDays(-2) + [timespan]'06:55')
        }
        'ord-08.demo.local' { 'Aucun utilisateur pour *' }
        'ord-06.demo.local' { "Erreur 0x00000005 lors de l'énumération des noms de sessions`nErreur [5]:Accès refusé." }
        default { "Erreur 0x000006BA lors de l'énumération des noms de sessions`nErreur [1722]:Le serveur RPC n'est pas disponible." }
    }
}

function ConvertTo-FakeEdidText([string]$Text, [int]$Length = 16) {
    # A text as WmiMonitorID gives it: its UTF-16 codes, padded with zeros.
    $codes = [System.Collections.Generic.List[uint16]]::new()
    foreach ($char in $Text.ToCharArray()) { $codes.Add([uint16]$char) }
    while ($codes.Count -lt $Length) { $codes.Add(0) }
    [uint16[]]$codes.ToArray()
}

function New-FakeMonitor([string]$Instance, [string]$Maker, [string]$Name, [string]$Code, [string]$Serial, [int]$Width, [int]$Height, [int]$Pixels, [int]$Lines, [int64]$Output, [bool]$Active = $true) {
    # A monitor's four root\wmi classes, by class name: its EDID, its size in cm, its modes (the preferred one second)
    # and how it's connected (VideoOutputTechnology).
    @{
        WmiMonitorID                         = [pscustomobject]@{
            InstanceName = $Instance; Active = $Active; ManufacturerName = ConvertTo-FakeEdidText $Maker; UserFriendlyName = ConvertTo-FakeEdidText $Name 13
            ProductCodeID = ConvertTo-FakeEdidText $Code; SerialNumberID = ConvertTo-FakeEdidText $Serial
        }
        WmiMonitorBasicDisplayParams         = [pscustomobject]@{ InstanceName = $Instance; MaxHorizontalImageSize = [byte]$Width; MaxVerticalImageSize = [byte]$Height }
        WmiMonitorListedSupportedSourceModes = [pscustomobject]@{
            InstanceName = $Instance; PreferredMonitorSourceModeIndex = [uint16]1
            MonitorSourceModes = @(
                [pscustomobject]@{ HorizontalActivePixels = [uint16]1024; VerticalActivePixels = [uint16]768 }
                [pscustomobject]@{ HorizontalActivePixels = [uint16]$Pixels; VerticalActivePixels = [uint16]$Lines }
            )
        }
        WmiMonitorConnectionParams           = [pscustomobject]@{ InstanceName = $Instance; VideoOutputTechnology = [uint32]$Output }
    }
}

function New-FakePnPDevice([string]$Name, [string]$DeviceId, [string]$Class, [string]$Revision, [bool]$Present = $true, [string]$DriverVersion = '10.0.26100.1', [string]$DriverProvider = 'Microsoft') {
    # A device as Win32_PnPEntity gives it: its hardware ids are its DeviceID's first part, with its revision and
    # without. One no longer connected isn't Present, with error 45. Its driver is what the fake GetDeviceProperties
    # answers.
    $hardware = $DeviceId.Split('\')[0..1] -join '\'
    [pscustomobject]@{
        Name = $Name; DeviceID = $DeviceId; PNPClass = $Class; Present = $Present; ConfigManagerErrorCode = [uint32]$(if ($Present) { 0 } else { 45 })
        HardwareID = [string[]]@("$hardware&REV_$Revision", $hardware); DriverVersion = $DriverVersion; DriverProvider = $DriverProvider
    }
}

function Join-FakeMonitor($Monitors) {
    # The monitors' classes, each with every monitor's instance.
    $classes = @{}
    foreach ($class in 'WmiMonitorID', 'WmiMonitorBasicDisplayParams', 'WmiMonitorListedSupportedSourceModes', 'WmiMonitorConnectionParams') {
        $classes[$class] = @($Monitors | ForEach-Object { $_[$class] })
    }
    $classes
}

# The computers the Caractéristiques window can read (WinRM answers): ord-01, a laptop with a worn battery (whose
# firmware doesn't support BatteryStaticData, so its original capacity comes from SMBIOS), a nearly full C: and no
# restart for 20 days; ord-04, a kiosk without brand or serial number (motherboard model instead),
# still on Windows 10, whose C: is full and where the adapters and the storage namespace can't be read (so the window
# falls back to the older classes). The others don't answer.
#
# Their registry, for the Logiciels section, holds the Uninstall keys (each a path and its values). ord-01: programs in
# the 64-bit and 32-bit keys (Chrome in both), one installed for the logged-on user only, and keys Windows doesn't list
# (two system components, one marked by text, an update of Office, a key without a name); 7-Zip's InstallDate is a
# number, Adobe's in its installer's locale (30/09/2026), Dell's a digit short (2025610), so not a date. HKU also has the system's and a _Classes key, which aren't users. ord-04: no 32-bit key at all, which isn't an error.
#
# Their monitors, for the Écrans section (root\wmi, made by New-FakeMonitor). ord-01, docked: its own screen (no name in its EDID), a Dell on
# DisplayPort, a Samsung on HDMI, and an LG no longer connected. ord-04: a ViewSonic on VGA, without a serial number,
# whose size can't be read.
#
# Their chassis and USB devices, for Batterie and Station d'accueil. ord-01, a laptop on a Dell dock: the dock's two hubs
# (known by their USB ids, named as generic hubs by Windows), its Realtek network adapter, a mouse, and the audio of a
# ThinkPad dock no longer connected. ord-04, a desktop: a keyboard and a mouse.
function Get-FakeCimData([string]$HostName) {
    $now = Get-Date
    $uninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $uninstall32 = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    $user = 'S-1-5-21-1111-2222-3333-1105'
    $monitors = switch ($HostName) {
        'ord-01.demo.local' {
            Join-FakeMonitor @(
                New-FakeMonitor 'DISPLAY\DELA1D0\5&2b4a3c1&0&UID4357_0' 'DEL' 'DELL P2422H' 'A1D0' 'CN0J5H2X7C' 53 30 1920 1080 10
                New-FakeMonitor 'DISPLAY\AUO25A4\4&1f0c5e2&0&UID8388688_0' 'AUO' '' '25A4' '0' 31 17 1920 1200 11
                New-FakeMonitor 'DISPLAY\SAM0D44\5&2b4a3c1&0&UID4358_0' 'SAM' 'S24F350' '0D44' 'H4ZN301234' 52 29 1920 1080 5
                New-FakeMonitor 'DISPLAY\GSM5B7F\5&2b4a3c1&0&UID4359_0' 'GSM' 'LG ULTRAGEAR' '5B7F' '305NTAB1C234' 60 34 2560 1440 10 $false
            )
        }
        'ord-04.demo.local' {
            $classes = Join-FakeMonitor @(New-FakeMonitor 'DISPLAY\VSC9E2F\5&3c1a2b&0&UID256_0' 'VSC' 'VA2405-H' '9E2F' '' 52 29 1920 1080 0)
            $classes.WmiMonitorBasicDisplayParams = 'Access denied'
            $classes
        }
    }
    $data = switch ($HostName) {
        'ord-01.demo.local' {
            @{
                Win32_ComputerSystem               = [pscustomobject]@{ Name = 'ORD-01'; Manufacturer = 'Dell Inc.'; Model = 'Latitude 5440'; SystemSKUNumber = '0C0F'; UserName = 'DEMO\accueil'; PartOfDomain = $true; Domain = 'demo.local'; DNSHostName = 'ORD-01'; PCSystemType = [uint16]2 }
                Win32_OperatingSystem              = [pscustomobject]@{ Caption = 'Microsoft Windows 11 Professionnel'; OSArchitecture = '64 bits'; Version = '10.0.26200'; BuildNumber = '26200'; LastBootUpTime = $now.AddDays(-20).AddHours(-3); SystemDrive = 'C:' }
                Win32_BIOS                         = [pscustomobject]@{ SerialNumber = '7H2KQ54'; SMBIOSBIOSVersion = '1.21.0'; ReleaseDate = [datetime]'2025-06-10' }
                Win32_ComputerSystemProduct        = [pscustomobject]@{ Version = '' }
                Win32_BaseBoard                    = [pscustomobject]@{ Product = '0VKXJ9' }
                Win32_Process                      = [pscustomobject]@{ Name = 'explorer.exe'; Owner = 'DEMO\accueil' }
                Win32_Service                      = [pscustomobject]@{ Name = 'WinRM'; StartMode = 'Auto'; State = 'Running' }
                Win32_NetworkAdapterConfiguration  = @(
                    [pscustomobject]@{ IPEnabled = $true; IPAddress = @('10.0.1.11', 'fd00:10::11'); InterfaceIndex = 12; DefaultIPGateway = @('10.0.1.1'); IPConnectionMetric = 35; Description = 'Intel(R) Wi-Fi 6E AX211 160MHz'; MACAddress = '3C:21:9C:4E:7A:10'; DNSServerSearchOrder = @('10.0.0.10', '10.0.0.11') }
                    [pscustomobject]@{ IPEnabled = $true; IPAddress = @('172.20.48.1'); InterfaceIndex = 31; DefaultIPGateway = $null; IPConnectionMetric = 5000; Description = 'Hyper-V Virtual Ethernet Adapter'; MACAddress = '00:15:5D:01:22:0A'; DNSServerSearchOrder = $null }
                )
                MSFT_NetAdapter                    = @(
                    [pscustomobject]@{ InterfaceIndex = 12; Name = 'Wi-Fi'; InterfaceDescription = 'Intel(R) Wi-Fi 6E AX211 160MHz'; NdisPhysicalMedium = 9; Virtual = $false; ReceiveLinkSpeed = 1201000000 }
                    [pscustomobject]@{ InterfaceIndex = 31; Name = 'vEthernet (Default Switch)'; InterfaceDescription = 'Hyper-V Virtual Ethernet Adapter'; NdisPhysicalMedium = 0; Virtual = $true; ReceiveLinkSpeed = 10000000000 }
                )
                Win32_NetworkAdapter               = @()
                Win32_Processor                    = [pscustomobject]@{ Name = '13th Gen Intel(R) Core(TM) i5-1345U'; Manufacturer = 'GenuineIntel'; Architecture = 9; NumberOfCores = 10; NumberOfLogicalProcessors = 12; L3CacheSize = 12288; CurrentClockSpeed = 2400; MaxClockSpeed = 1600 }
                Win32_PhysicalMemory               = @(
                    # Samsung, as its JEDEC code, with a part number padded with spaces as SMBIOS gives it.
                    [pscustomobject]@{ Capacity = 8GB; SMBIOSMemoryType = 34; ConfiguredClockSpeed = 5200; Speed = 5600; Manufacturer = '80CE'; PartNumber = 'M425R1GB4BB0-CWM   ' }
                    [pscustomobject]@{ Capacity = 8GB; SMBIOSMemoryType = 34; ConfiguredClockSpeed = 5200; Speed = 5600; Manufacturer = '80CE'; PartNumber = 'M425R1GB4BB0-CWM   ' }
                )
                Win32_LogicalDisk                  = [pscustomobject]@{ DriveType = 3; DeviceID = 'C:'; VolumeName = 'Windows'; Size = 510GB; FreeSpace = 71GB }
                MSFT_Partition                     = @(
                    [pscustomobject]@{ DriveLetter = ''; DiskNumber = 0 }
                    [pscustomobject]@{ DriveLetter = 'C'; DiskNumber = 0 }
                )
                MSFT_PhysicalDisk                  = [pscustomobject]@{ DeviceId = '0'; FriendlyName = 'KXG80ZNV512G KIOXIA'; Size = 512GB; MediaType = 4; BusType = 17 }
                Win32_DiskDrive                    = [pscustomobject]@{ Index = 0; Model = 'KXG80ZNV512G KIOXIA'; Size = 512GB; InterfaceType = 'SCSI' }
                Win32_Battery                      = [pscustomobject]@{ EstimatedChargeRemaining = 87; BatteryStatus = 2 }
                BatteryFullChargedCapacity         = [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; FullChargedCapacity = 33480 }
                BatteryStaticData                  = 'Not supported'
                Win32_PortableBattery              = [pscustomobject]@{ DesignCapacity = 54000 }
                BatteryCycleCount                  = [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; CycleCount = 412 }
                Win32_SystemEnclosure              = [pscustomobject]@{ ChassisTypes = [uint16[]]@(10) }
                Win32_PnPEntity                    = @(
                    New-FakePnPDevice 'Generic USB Hub' 'USB\VID_413C&PID_B06E\6&2C7A1F3B&0&1' 'USB' '0101'
                    New-FakePnPDevice 'Generic SuperSpeed USB Hub' 'USB\VID_413C&PID_B06F\6&1E5D2A9C&0&2' 'USB' '0101'
                    # The same hub seen again on another port: listed once.
                    New-FakePnPDevice 'Generic USB Hub' 'USB\VID_413C&PID_B06E\6&2C7A1F3B&0&5' 'USB' '0101'
                    New-FakePnPDevice 'Realtek USB GbE Family Controller' 'USB\VID_0BDA&PID_8153\301000001' 'Net' '3100' -DriverVersion '1153.12.20.1011' -DriverProvider 'Realtek'
                    New-FakePnPDevice 'USB Input Device' 'USB\VID_046D&PID_C077\5&3A8B21F&0&3' 'HIDClass' '7200'
                    New-FakePnPDevice 'ThinkPad USB-C Dock Gen2 USB Audio' 'USB\VID_17EF&PID_A396&MI_00\7&1B2C3D4E&0&0000' 'MEDIA' '3109' -Present $false
                )
                Registry                           = @{
                    "HKLM\$uninstall\{90160000-0011-0000-1000-0000000FF1CE}" = @{ DisplayName = 'Microsoft 365 Apps for enterprise - fr-fr'; DisplayVersion = '16.0.19127.20154'; Publisher = 'Microsoft Corporation'; InstallDate = '20260912' }
                    "HKLM\$uninstall\Google Chrome"                           = @{ DisplayName = 'Google Chrome'; DisplayVersion = '141.0.7390.66'; Publisher = 'Google LLC'; InstallDate = '20261008' }
                    "HKLM\$uninstall\7-Zip"                                   = @{ DisplayName = '7-Zip 24.08 (x64)'; DisplayVersion = '24.08'; Publisher = 'Igor Pavlov'; InstallDate = [uint32]20240815 }
                    "HKLM\$uninstall\{4A9F3E2B-7C1D-4F8A-B6E5-2D9C0A1B3F47}" = @{ DisplayName = 'Dell Command | Update'; DisplayVersion = '5.5.0'; Publisher = 'Dell Inc.'; InstallDate = '2025610' }
                    "HKLM\$uninstall\{6F320B93-EE3C-4826-85E0-ADF79F8D4C61}" = @{ DisplayName = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211'; DisplayVersion = '14.44.35211.0'; Publisher = 'Microsoft Corporation'; InstallDate = '20260402' }
                    "HKLM\$uninstall\{D5D19E2F-7189-42FE-8103-92CD1FA457C2}" = @{ DisplayName = 'Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.44.35211'; DisplayVersion = '14.44.35211'; Publisher = 'Microsoft Corporation'; SystemComponent = [uint32]1 }
                    "HKLM\$uninstall\Pilote-Audio"                            = @{ DisplayName = 'Pilote audio Realtek'; DisplayVersion = '6.0.9733.1'; Publisher = 'Realtek'; SystemComponent = '1' }
                    "HKLM\$uninstall\{90160000-0011-0000-1000-0000000FF1CE}_Office16.PROPLUS_{KB5002700}" = @{ DisplayName = 'Mise à jour de sécurité pour Microsoft Office (KB5002700)'; ParentKeyName = 'Office16.PROPLUS' }
                    "HKLM\$uninstall\AddressBook"                             = @{}
                    "HKLM\$uninstall32\{AC76BA86-7AD7-1036-7B44-AC0F074E4100}" = @{ DisplayName = 'Adobe Acrobat Reader'; DisplayVersion = '25.001.20756'; Publisher = 'Adobe'; InstallDate = '30/09/2026' }
                    "HKLM\$uninstall32\Google Chrome"                         = @{ DisplayName = 'Google Chrome'; DisplayVersion = '141.0.7390.66'; Publisher = 'Google LLC'; InstallDate = '20261008' }
                    "HKU\$user\$uninstall\ZoomUMX"                            = @{ DisplayName = 'Zoom Workplace'; DisplayVersion = '6.4.3 (60103)'; Publisher = 'Zoom Video Communications, Inc.'; InstallDate = '20261001' }
                    "HKU\$($user)_Classes\$uninstall\Phantom"                 = @{ DisplayName = 'Pas un utilisateur' }
                    "HKU\S-1-5-18\$uninstall\Phantom"                         = @{ DisplayName = 'Pas un utilisateur' }
                }
            }
        }
        'ord-04.demo.local' {
            @{
                Win32_ComputerSystem               = [pscustomobject]@{ Name = 'ORD-04'; Manufacturer = 'To be filled by O.E.M.'; Model = 'System Product Name'; SystemSKUNumber = 'SKU'; UserName = ''; PartOfDomain = $true; Domain = 'demo.local'; DNSHostName = 'ORD-04'; PCSystemType = [uint16]1 }
                Win32_OperatingSystem              = [pscustomobject]@{ Caption = 'Microsoft Windows 10 Professionnel'; OSArchitecture = '64 bits'; Version = '10.0.19045'; BuildNumber = '19045'; LastBootUpTime = $now.AddDays(-2).AddHours(-5); SystemDrive = 'C:' }
                Win32_BIOS                         = [pscustomobject]@{ SerialNumber = 'Default string'; SMBIOSBIOSVersion = '2.10'; ReleaseDate = [datetime]'2021-03-02' }
                Win32_ComputerSystemProduct        = [pscustomobject]@{ Version = 'System Version' }
                Win32_BaseBoard                    = [pscustomobject]@{ Product = 'PRIME B460M-A' }
                # Signed in on its own through Remote Desktop: no UserName, so the owner of explorer.exe.
                Win32_Process                      = [pscustomobject]@{ Name = 'explorer.exe'; Owner = 'DEMO\kiosque' }
                # WinRM off, as on a Windows client nobody set up.
                Win32_Service                      = [pscustomobject]@{ Name = 'WinRM'; StartMode = 'Manual'; State = $(if ($script:Store.WinRM[$HostName]) { 'Running' } else { 'Stopped' }) }
                Win32_NetworkAdapterConfiguration  = [pscustomobject]@{ IPEnabled = $true; IPAddress = @('10.0.1.14'); InterfaceIndex = 7; DefaultIPGateway = @('10.0.1.1'); IPConnectionMetric = 25; Description = 'Realtek PCIe GbE Family Controller'; MACAddress = '04:D9:F5:8A:31:C2'; DNSServerSearchOrder = @('10.0.0.10') }
                MSFT_NetAdapter                    = 'Access denied'
                Win32_NetworkAdapter               = [pscustomobject]@{ NetEnabled = $true; InterfaceIndex = 7; Name = 'Realtek PCIe GbE Family Controller'; NetConnectionID = 'Ethernet'; PhysicalAdapter = $true; Speed = 1000000000 }
                Win32_Processor                    = [pscustomobject]@{ Name = 'Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz'; Manufacturer = 'GenuineIntel'; Architecture = 9; NumberOfCores = 4; NumberOfLogicalProcessors = 8; L3CacheSize = 6144; CurrentClockSpeed = 3600; MaxClockSpeed = 3600 }
                Win32_PhysicalMemory               = [pscustomobject]@{ Capacity = 8GB; SMBIOSMemoryType = 26; ConfiguredClockSpeed = 2666; Speed = 2666; Manufacturer = 'Undefined'; PartNumber = '                    ' }
                Win32_LogicalDisk                  = [pscustomobject]@{ DriveType = 3; DeviceID = 'C:'; VolumeName = ''; Size = 237GB; FreeSpace = 14GB }
                MSFT_Partition                     = 'Access denied'
                MSFT_PhysicalDisk                  = 'Access denied'
                Win32_DiskDrive                    = [pscustomobject]@{ Index = 0; Model = 'SanDisk SDSSDA240G'; Size = 240GB; InterfaceType = 'IDE' }
                Win32_Battery                      = @()
                BatteryFullChargedCapacity         = 'Not supported'
                BatteryStaticData                  = 'Not supported'
                Win32_PortableBattery              = @()
                BatteryCycleCount                  = 'Not supported'
                Win32_SystemEnclosure              = [pscustomobject]@{ ChassisTypes = [uint16[]]@(3) }
                Win32_PnPEntity                    = @(
                    New-FakePnPDevice 'USB Input Device' 'USB\VID_046D&PID_C31C\5&2F1A3B4&0&1' 'HIDClass' '6400'
                    New-FakePnPDevice 'USB Input Device' 'USB\VID_046D&PID_C077\5&2F1A3B4&0&2' 'HIDClass' '7200'
                )
                Registry                           = @{
                    "HKLM\$uninstall\Google Chrome"           = @{ DisplayName = 'Google Chrome'; DisplayVersion = '139.0.7258.155'; Publisher = 'Google LLC'; InstallDate = '20260820' }
                    "HKLM\$uninstall\Borne-Accueil"           = @{ DisplayName = "Borne d'accueil"; DisplayVersion = '2.3'; Publisher = 'Service informatique'; InstallDate = '20240115' }
                    "HKLM\$uninstall\VLC media player"        = @{ DisplayName = 'VLC media player'; DisplayVersion = '3.0.21'; Publisher = 'VideoLAN' }
                    "HKU\S-1-5-18\Software\Microsoft"          = @{}
                }
            }
        }
    }
    if ($data -and $monitors) { foreach ($class in $monitors.Keys) { $data[$class] = $monitors[$class] } }
    $data
}

function New-CimSessionOption {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates nothing.')]
    [CmdletBinding()]
    param([string]$Protocol)

    [pscustomobject]@{ Protocol = $Protocol }
}

function New-CimSession {
    # A fake session to a fake computer that answers, which the fake Get-CimInstance reads. The others fail like a
    # computer that's off or blocks WinRM (and DCOM).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OperationTimeoutSec', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [int]$OperationTimeoutSec,
        $SessionOption
    )

    if (-not $ComputerName -or -not (Get-FakeCimData $ComputerName)) {
        if ($SessionOption -and $SessionOption.Protocol -eq 'Dcom') { throw (New-FakeCimError 'The RPC server is unavailable.' 0x800706BAL) }
        throw (New-FakeCimError "WinRM cannot complete the operation. Verify that the specified computer name is valid, that the computer is accessible over the network, and that a firewall exception for the WinRM service is enabled and allows access from this computer." 0x80338126L)
    }
    $protocol = if ($SessionOption -and $SessionOption.Protocol -eq 'Dcom') { 'Dcom' } else { 'WSMan' }
    [pscustomobject]@{ FakeHost = $ComputerName; Data = Get-FakeCimData $ComputerName; Protocol = $protocol }
}

function Test-WSMan {
    # Whether WinRM answers, for PowerShell à distance once Repère turns it on: on the fake computers where it runs
    # (ord-01, and ord-04 once turned on). Anything else: the real cmdlet.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [string]$Authentication
    )

    if (-not $ComputerName -or -not (Get-FakeCimData $ComputerName)) { return Microsoft.WSMan.Management\Test-WSMan @PSBoundParameters }
    if (-not $script:Store.WinRM[$ComputerName]) { throw "WinRM cannot complete the operation. Verify that the specified computer name is valid, that the computer is accessible over the network, and that a firewall exception for the WinRM service is enabled and allows access from this computer." }
    [pscustomobject]@{ ProductVendor = 'Microsoft Corporation'; ProductVersion = 'OS: 0.0.0 SP: 0.0 Stack: 3.0' }
}

function Invoke-Command {
    # Caractéristiques' Logiciels read in one call over WinRM: a fake computer's Uninstall entries, as PCSpecs.ps1's
    # $UninstallEntryReader returns them, from its fake registry, on the computers where WinRM runs. The others fail like
    # WinRM, and so do they all with $env:REPERE_FAKEAD_NO_REMOTING (WinRM up, PowerShell's remoting refused). Anything
    # else: the real cmdlet.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [CmdletBinding()]
    param(
        [string[]]$ComputerName,
        [scriptblock]$ScriptBlock,
        $SessionOption
    )

    $data = if ($ComputerName) { Get-FakeCimData $ComputerName[0] }
    if (-not $data) { return Microsoft.PowerShell.Core\Invoke-Command @PSBoundParameters }
    if ($env:REPERE_FAKEAD_NO_REMOTING) { throw (New-FakeRemotingError "Connecting to remote server $($ComputerName[0]) failed with the following error message : Access is denied." 5) }
    if (-not $script:Store.WinRM[$ComputerName[0]]) { throw (New-FakeRemotingError "Connecting to remote server $($ComputerName[0]) failed with the following error message : WinRM cannot complete the operation." 53) }
    $registry = $data['Registry']
    if ($registry -is [string]) { throw $registry }
    foreach ($path in $registry.Keys) {
        $scope = if ($path -match '^HKLM\\Software\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$') { 'Computer' }
                 elseif ($path -match '^HKU\\S-1-5-21-[\d-]+\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$') { 'User' }
        if (-not $scope) { continue }
        $values = $registry[$path]
        $entry = [ordered]@{ Scope = $scope }
        foreach ($name in 'DisplayName', 'DisplayVersion', 'Publisher', 'InstallDate', 'SystemComponent', 'ParentKeyName') {
            $entry[$name] = if ($values.ContainsKey($name)) { "$($values[$name])".Trim() } else { $null }
        }
        [pscustomobject]$entry
    }
}

function Remove-CimSession {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CimSession', Justification = 'Nothing to close.')]
    [CmdletBinding()]
    param([Parameter(Position = 0)] $CimSession)
}

function Get-CimInstance {
    # Reads a fake computer's classes through a fake session. Filter: one  Property = value  or  Property LIKE 'text%'
    # clause. A class given as text fails with that text (access denied, not supported). Without a fake session, the
    # real cmdlet.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [CmdletBinding()]
    param(
        $CimSession,
        [Parameter(Position = 0)]
        [string]$ClassName,
        [string]$Namespace,
        [string]$Filter,
        [int]$OperationTimeoutSec
    )

    if (-not ($CimSession -and $CimSession.PSObject.Properties['FakeHost'])) {
        return CimCmdlets\Get-CimInstance @PSBoundParameters
    }
    $delay = 0
    if ([int]::TryParse("$env:REPERE_FAKEAD_SPECS_DELAY", [ref]$delay) -and $delay -gt 0) { Start-Sleep -Milliseconds $delay }
    # The firewall rules PowerShell à distance added, as they are now (Restore-TemporaryWinRM checks its own is gone).
    if ($ClassName -eq 'MSFT_NetFirewallRule') { $instances = @($script:Store.WinRMRules[$CimSession.FakeHost] | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ DisplayName = $_ } }) }
    elseif (-not $CimSession.Data.ContainsKey($ClassName)) { throw "Invalid class: $ClassName" }
    else { $instances = $CimSession.Data[$ClassName] }
    if ($instances -is [string]) { throw $instances }
    foreach ($instance in @($instances)) {
        if ($Filter) {
            if ($Filter -notmatch "^\s*(?<property>\w+)\s*(?<operator>=|LIKE)\s*'?(?<value>[^']*)'?\s*$") { throw "Invalid query: $Filter" }
            $value = "$($instance.($Matches.property))"
            # WQL's % is any text, and its other wildcards aren't used here.
            if ($Matches.operator -eq 'LIKE') { if ($value -notlike $Matches.value.Replace('%', '*')) { continue } }
            elseif ($Matches.value -eq 'TRUE') { if ($value -ne 'True') { continue } }
            elseif ($value -ne $Matches.value) { continue }
        }
        $instance
    }
}

function Invoke-CimMethod {
    # GetOwner, on a fake process: its owner as Domain and User. StdRegProv's EnumKey, EnumValues, GetStringValue and
    # GetDWORDValue, on a fake computer's registry through a fake session: ReturnValue 2 when the key or the value
    # doesn't exist, as the real one answers.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Namespace', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OperationTimeoutSec', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param(
        $InputObject,
        $CimSession,
        [string]$Namespace,
        [string]$ClassName,
        [string]$MethodName,
        [hashtable]$Arguments,
        [int]$OperationTimeoutSec
    )

    if ($ClassName -eq 'StdRegProv') {
        if (-not ($CimSession -and $CimSession.PSObject.Properties['FakeHost'])) { throw 'StdRegProv: no fake session.' }
        $registry = $CimSession.Data['Registry']
        if ($registry -is [string]) { throw $registry }
        $hive = @{ 2147483650 = 'HKLM'; 2147483651 = 'HKU' }[[int64]$Arguments.hDefKey]
        $path = (@($hive, $Arguments.sSubKeyName) | Where-Object { $_ }) -join '\'
        $values = $registry[$path]
        switch ($MethodName) {
            'EnumKey' {
                # WinRM's listener, once Repère has turned it on.
                if ($path -like '*\WSMAN\Listener' -and $script:Store.WinRM[$CimSession.FakeHost]) { return [pscustomobject]@{ ReturnValue = [uint32]0; sNames = [string[]]@('*+HTTP') } }
                $prefix = "$path\"
                $names = @($registry.Keys | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object { $_.Substring($prefix.Length).Split('\')[0] } | Select-Object -Unique)
                if (-not $names.Count -and $null -eq $values) { return [pscustomobject]@{ ReturnValue = [uint32]2; sNames = $null } }
                return [pscustomobject]@{ ReturnValue = [uint32]0; sNames = [string[]]$names }
            }
            'EnumValues' {
                if ($null -eq $values) { return [pscustomobject]@{ ReturnValue = [uint32]2; sNames = $null; Types = $null } }
                $names = [string[]]@($values.Keys)
                # A number is a REG_DWORD (4), anything else a REG_SZ (1).
                return [pscustomobject]@{ ReturnValue = [uint32]0; sNames = $names; Types = [int[]]@($names | ForEach-Object { if ($values[$_] -is [string]) { 1 } else { 4 } }) }
            }
            'GetStringValue' {
                if ($null -eq $values -or -not $values.ContainsKey($Arguments.sValueName)) { return [pscustomobject]@{ ReturnValue = [uint32]2; sValue = $null } }
                # 2147749893: the value is of another type.
                if ($values[$Arguments.sValueName] -isnot [string]) { return [pscustomobject]@{ ReturnValue = [uint32]2147749893; sValue = $null } }
                return [pscustomobject]@{ ReturnValue = [uint32]0; sValue = $values[$Arguments.sValueName] }
            }
            'GetDWORDValue' {
                if ($null -eq $values -or -not $values.ContainsKey($Arguments.sValueName)) { return [pscustomobject]@{ ReturnValue = [uint32]2; uValue = $null } }
                if ($values[$Arguments.sValueName] -is [string]) { return [pscustomobject]@{ ReturnValue = [uint32]2147749893; uValue = $null } }
                return [pscustomobject]@{ ReturnValue = [uint32]0; uValue = [uint32]$values[$Arguments.sValueName] }
            }
            default { throw "Method not supported: $MethodName" }
        }
    }
    # GetDeviceProperties, on a fake PnP device (New-FakePnPDevice): its driver's version and provider, as
    # Win32_PnPDeviceProperty instances.
    if ($MethodName -eq 'GetDeviceProperties' -and $InputObject.PSObject.Properties['DriverVersion']) {
        $known = @{ DEVPKEY_Device_DriverVersion = $InputObject.DriverVersion; DEVPKEY_Device_DriverProvider = $InputObject.DriverProvider }
        return [pscustomobject]@{ deviceProperties = @(foreach ($key in $Arguments.devicePropertyKeys) { [pscustomobject]@{ KeyName = $key; Data = $known[$key] } }) }
    }
    if ($MethodName -ne 'GetOwner' -or -not $InputObject.PSObject.Properties['Owner']) { throw "Method not supported: $MethodName" }
    $domain, $user = $InputObject.Owner -split '\\', 2
    [pscustomobject]@{ Domain = $domain; User = $user }
}

# The scheduled tasks Forcer les stratégies and PowerShell à distance create on a fake computer (RemoteAccess.ps1),
# through a fake session. Starting one does at once what its command would: gpupdate succeeds, and the commands that
# turn WinRM on and put it back add and delete their firewall rule (Store.WinRMRules), WinRM running (Store.WinRM) while
# a Repère rule is left; the one that puts it back deletes itself once its rule is gone, as its schtasks /Delete would.
# The New-ScheduledTask* commands too, so the real ScheduledTasks module never loads over these.
function New-ScheduledTaskAction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates nothing.')]
    [CmdletBinding()]
    param([string]$Execute, [string]$Argument)
    [pscustomobject]@{ Execute = $Execute; Arguments = $Argument }
}

function New-ScheduledTaskTrigger {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates nothing.')]
    [CmdletBinding()]
    param([switch]$Once, [datetime]$At, [switch]$AtStartup)
    [pscustomobject]@{
        Kind          = if ($AtStartup) { 'Boot' } else { 'Once' }
        # As Windows writes it, whatever the culture: Enable-TemporaryWinRM reads it back.
        StartBoundary = if ($Once) { $At.ToUniversalTime().ToString("yyyy-MM-dd'T'HH':'mm':'ss'Z'", [cultureinfo]::InvariantCulture) }
        EndBoundary   = $null
    }
}

function New-ScheduledTaskSettingsSet {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates nothing.')]
    [CmdletBinding()]
    param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, [timespan]$ExecutionTimeLimit)
    [pscustomobject]@{
        DisallowStartIfOnBatteries = -not $AllowStartIfOnBatteries; StopIfGoingOnBatteries = -not $DontStopIfGoingOnBatteries
        ExecutionTimeLimit = $ExecutionTimeLimit; StartWhenAvailable = $false; DeleteExpiredTaskAfter = $null
    }
}

function New-ScheduledTaskPrincipal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates nothing.')]
    [CmdletBinding()]
    param([string]$UserId, [string]$LogonType, [string]$RunLevel)
    [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType; RunLevel = $RunLevel }
}

function Get-FakeTaskKey($CimSession, [string]$TaskPath, [string]$TaskName) {
    if (-not ($CimSession -and $CimSession.PSObject.Properties['FakeHost'])) { throw 'ScheduledTasks: no fake session.' }
    "$($CimSession.FakeHost)|$TaskPath$TaskName"
}

function Register-ScheduledTask {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real one.')]
    [CmdletBinding()]
    param($CimSession, [string]$TaskName, [string]$TaskPath = '\', $Action, $Trigger, $Settings, $Principal, [string]$Description, [switch]$Force)
    $key = Get-FakeTaskKey $CimSession $TaskPath $TaskName
    if ($script:Store.Tasks.ContainsKey($key) -and -not $Force) { throw 'Cannot create a file when that file already exists.' }
    $first = @($Action)[0]
    Write-FakeADLog @{ Command = 'Register-ScheduledTask'; Server = $CimSession.FakeHost; TaskName = $TaskName; Execute = $first.Execute; Arguments = $first.Arguments
                       UserId = $Principal.UserId; Triggers = @($Trigger | ForEach-Object { $_.Kind }) }
    $task = [pscustomobject]@{
        TaskName = $TaskName; TaskPath = $TaskPath; State = 'Ready'; Actions = @($Action); Triggers = @($Trigger); Settings = $Settings
        Principal = $Principal; Description = $Description; LastTaskResult = [uint32]0x41303; LastRunTime = $null
    }
    $script:Store.Tasks[$key] = $task
    $task
}

function Get-ScheduledTask {
    # A name with * gives every task it matches, as the real one does.
    [CmdletBinding()]
    param($CimSession, [string]$TaskName, [string]$TaskPath = '\')
    if ($TaskName.Contains('*')) {
        $pattern = Get-FakeTaskKey $CimSession $TaskPath $TaskName
        foreach ($key in @($script:Store.Tasks.Keys)) { if ($key -like $pattern) { $script:Store.Tasks[$key] } }
        return
    }
    $task = $script:Store.Tasks[(Get-FakeTaskKey $CimSession $TaskPath $TaskName)]
    if (-not $task) { Write-Error "No MSFT_ScheduledTask objects found with property 'TaskName' equal to '$TaskName'."; return }
    $task
}

function Get-ScheduledTaskInfo {
    [CmdletBinding()]
    param($CimSession, [string]$TaskName, [string]$TaskPath = '\')
    $task = Get-ScheduledTask -CimSession $CimSession -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    [pscustomobject]@{ TaskName = $TaskName; LastTaskResult = $task.LastTaskResult; LastRunTime = $task.LastRunTime }
}

function Start-ScheduledTask {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real one.')]
    [CmdletBinding()]
    param($CimSession, [string]$TaskName, [string]$TaskPath = '\')
    $key = Get-FakeTaskKey $CimSession $TaskPath $TaskName
    $task = Get-ScheduledTask -CimSession $CimSession -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    $hostName = $CimSession.FakeHost
    Write-FakeADLog @{ Command = 'Start-ScheduledTask'; Server = $hostName; TaskName = $TaskName }
    $command = "$($task.Actions[0].Execute) $($task.Actions[0].Arguments)"
    $rules = @($script:Store.WinRMRules[$hostName] | Where-Object { $_ })
    if ($command -match 'firewall add rule name=(\S+)') { $rules += $Matches[1] }
    if ($command -match 'firewall delete rule name=(\S+)') { $deleted = $Matches[1]; $rules = @($rules | Where-Object { $_ -ne $deleted }) }
    if ($command -match 'firewall (add|delete) rule') {
        $script:Store.WinRMRules[$hostName] = $rules
        $script:Store.WinRM[$hostName] = [bool]@($rules | Where-Object { $_ -like 'Repere-WinRM*' }).Count
    }
    $task.LastTaskResult = [uint32]0
    $task.LastRunTime = Get-Date
    # Only once its rule is gone, when it says so (show rule name=… || schtasks /Delete).
    if ($command -match 'schtasks\.exe /Delete' -and -not ($command -match 'show rule name=(\S+) >nul \|\|' -and $rules -contains $Matches[1])) { $script:Store.Tasks.Remove($key) }
}

function Unregister-ScheduledTask {
    # As the real one: it asks first (ConfirmImpact High), and a DCOM session refuses -Confirm, which PowerShell 7.6 and
    # later report as a disposed CancellationTokenSource, whatever -ErrorAction says (#316).
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param($CimSession, [string]$TaskName, [string]$TaskPath = '\')
    if ($PSBoundParameters.ContainsKey('Confirm') -and $CimSession.Protocol -eq 'Dcom') { throw [System.ObjectDisposedException]::new($null, 'The CancellationTokenSource has been disposed.') }
    $key = Get-FakeTaskKey $CimSession $TaskPath $TaskName
    if (-not $script:Store.Tasks.ContainsKey($key)) { Write-Error "No MSFT_ScheduledTask objects found with property 'TaskName' equal to '$TaskName'."; return }
    Write-FakeADLog @{ Command = 'Unregister-ScheduledTask'; Server = $CimSession.FakeHost; TaskName = $TaskName }
    if ($PSCmdlet.ShouldProcess($TaskName)) { $script:Store.Tasks.Remove($key) }
    if ($env:REPERE_FAKEAD_WINRM_ON_ERROR -and $TaskName -like 'Repere-WinRM-on-*') { throw [System.ObjectDisposedException]::new($null, 'The CancellationTokenSource has been disposed.') }
}

function Remove-CimInstance {
    # A fake task deleted as Invoke-RemoteTask deletes it (Get-ScheduledTask | Remove-CimInstance: the cim:DeleteInstance
    # of Unregister-ScheduledTask, without its confirmation). Anything else: the real cmdlet.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Replacing it for the fake computers is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)] $InputObject, $CimSession)
    process {
        if (-not ($CimSession -and $CimSession.PSObject.Properties['FakeHost'])) { return CimCmdlets\Remove-CimInstance @PSBoundParameters }
        $key = Get-FakeTaskKey $CimSession $InputObject.TaskPath $InputObject.TaskName
        if (-not $script:Store.Tasks.ContainsKey($key)) { Write-Error 'The system cannot find the file specified.'; return }
        Write-FakeADLog @{ Command = 'Remove-CimInstance'; Server = $CimSession.FakeHost; TaskName = $InputObject.TaskName }
        $script:Store.Tasks.Remove($key)
        if ($env:REPERE_FAKEAD_WINRM_ON_ERROR -and $InputObject.TaskName -like 'Repere-WinRM-on-*') { throw [System.ObjectDisposedException]::new($null, 'The CancellationTokenSource has been disposed.') }
    }
}

function Test-FakeLdapGroup($Group, [string]$Filter) {
    # The LDAP filters the Groupes page and Ajouter des membres… build: (&(objectCategory=group)…) with (name=*…*),
    # (description=*…*), (anr=…) (the start of the name), (!(member=*)) for the groups that list no member, and
    # (member=<DN>) for the groups that list an object, groupType's scope bits, and an OR of (distinguishedName=…) or
    # (objectSid=…) for several groups at once, and of (name=…) and (sAMAccountName=…) (Liste de noms). Ajouter à un groupe's search in other domains: an OR of scope bits and
    # (!(isCriticalSystemObject=TRUE)) inside its AND.
    # An OR of clauses (several groups at once): whether one of them matches.
    if ($Filter.StartsWith('(|')) {
        foreach ($clause in [regex]::Matches($Filter, '\(([^()&|!]+)\)')) { if (Test-FakeLdapGroup $Group "($($clause.Groups[1].Value))") { return $true } }
        return $false
    }
    if ($Filter.Contains('(!(member=*))')) {
        if (@($Group.Members).Count) { return $false }
        $Filter = $Filter.Replace('(!(member=*))', '')
    }
    # An OR or a NOT inside the AND: tested on its own, then taken out of it.
    foreach ($inner in [regex]::Matches($Filter, '\(\|(?:\([^()]+\))+\)')) {
        if (-not (Test-FakeLdapGroup $Group $inner.Value)) { return $false }
        $Filter = $Filter.Replace($inner.Value, '')
    }
    foreach ($inner in [regex]::Matches($Filter, '\(!(\([^()]+\))\)')) {
        if (Test-FakeLdapGroup $Group $inner.Groups[1].Value) { return $false }
        $Filter = $Filter.Replace($inner.Value, '')
    }
    foreach ($clause in [regex]::Matches($Filter, '\(([^()&|!]+)\)')) {
        $text = $clause.Groups[1].Value
        $value = if ($text -match '^[^=<>]+=(.*)$') { $Matches[1] -replace '\\2a', '*' -replace '\\28', '(' -replace '\\29', ')' -replace '\\5c', '\' } else { '' }
        $matched = switch -Regex ($text) {
            '^objectCategory=group$' { $true }
            '^name=' { Test-FakeADLike $Group.Name $value }
            '^sAMAccountName=' { $Group.SamAccountName -eq $value }
            '^description=' { Test-FakeADLike $Group.Description $value }
            '^anr=' { [bool]@($Group.Name, $Group.SamAccountName | Where-Object { $_ -and $_.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase) }).Count }
            '^member=' { $Group.Members -contains $value }
            # groupType's bits: 4 domain local, 8 universal (tests\Test-RepereAD.ps1 picks one of each).
            '^groupType:1\.2\.840\.113556\.1\.4\.803:=4$' { $Group.GroupScope -eq 'DomainLocal' }
            '^groupType:1\.2\.840\.113556\.1\.4\.803:=8$' { $Group.GroupScope -eq 'Universal' }
            '^isCriticalSystemObject=TRUE$' { [bool]$Group.isCriticalSystemObject }
            '^distinguishedName=' { $Group.DistinguishedName -eq $value }
            '^objectSid=' { $Group.SID -eq $value }
            default { throw "Error parsing query: '$Filter'" }
        }
        if (-not $matched) { return $false }
    }
    $true
}

function Get-ADDomainController {
    # Only -Discover: -Service GlobalCatalog, the forest's global catalog, dc1 of its root domain; -DomainName, the
    # first of that domain's DCs that answers, dc1, dc2 or dc3 ($env:REPERE_FAKEAD_UNREACHABLE).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Discover', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Writable', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ForceDiscover', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param(
        [switch]$Discover,
        [string[]]$Service,
        [string]$DomainName,
        [switch]$Writable,
        [switch]$ForceDiscover
    )

    Write-FakeADLog @{ Command = 'Get-ADDomainController'; Service = $Service -join ','; DomainName = $DomainName }
    if ($DomainName) {
        $null = Resolve-FakeADDomain $DomainName
        $unreachable = @("$env:REPERE_FAKEAD_UNREACHABLE" -split ';' | Where-Object { $_ })
        $name = 1..3 | ForEach-Object { "dc$_.$DomainName" } | Where-Object { $unreachable -notcontains $_ } | Select-Object -First 1
        if (-not $name) { throw 'Unable to find a default server with Active Directory Web Services running.' }
        return [pscustomobject]@{ HostName = @($name); Domain = $DomainName }
    }
    if ($Service -notcontains 'GlobalCatalog') { throw 'The fake AD only finds a global catalog.' }
    if ($env:REPERE_FAKEAD_NO_GC) { throw 'Unable to find a default server with Active Directory Web Services running.' }
    [pscustomobject]@{ HostName = @("dc1.$(@($script:Domains.Keys)[0])"); Domain = @($script:Domains.Keys)[0] }
}

function Get-ADGroup {
    # One group of the domain, by its DN or its SID (with MemberOf, and tokenGroups when asked for), or the groups a
    # -Filter (by name) or an -LDAPFilter finds. A group of another domain isn't found there, as in the real AD.
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Identity')]
        [string]$Identity,
        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [string]$Filter,
        [Parameter(Mandatory, ParameterSetName = 'LDAPFilter')]
        [string]$LDAPFilter,
        [Parameter(ParameterSetName = 'Filter')]
        [Parameter(ParameterSetName = 'LDAPFilter')]
        [int]$ResultSetSize = [int]::MaxValue,
        [string[]]$Properties,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Get-ADGroup'; Identity = $Identity; Filter = $Filter; LDAPFilter = $LDAPFilter; Properties = $Properties -join ','; Server = $Server
                       ResultSetSize = $(if ($PSBoundParameters.ContainsKey('ResultSetSize')) { $ResultSetSize }) }
    $domainDN = Resolve-FakeADDomain $Server
    $read = 'Name', 'DistinguishedName', 'SID', 'GroupCategory', 'GroupScope', 'Description', 'SamAccountName', 'mail', 'ManagedBy', 'whenCreated', 'whenChanged',
            @{ Name = 'member'; Expression = { @($_.Members) } }
    # Not among the cmdlet's default properties: only when asked for, as the real cmdlet returns them.
    $read += @('isCriticalSystemObject', 'adminCount' | Where-Object { $Properties -contains $_ })
    $inDomain = @($script:Store.Groups | Where-Object { Test-FakeADInDomain $_.DistinguishedName $domainDN })
    if ($Filter -or $LDAPFilter) { Assert-FakeADBaseSearch $Properties }
    if ($Filter) { return Select-FakeADObject $inDomain $Filter | Select-Object -First $ResultSetSize | Select-Object $read }
    if ($LDAPFilter) { return $inDomain | Where-Object { Test-FakeLdapGroup $_ $LDAPFilter } | Select-Object -First $ResultSetSize | Select-Object $read }
    $copy = Add-FakeADMembership (Find-FakeADGroup $Identity $domainDN | Select-Object $read) $domainDN 0
    # tokenGroups only when asked for, like the real cmdlet's constructed attributes.
    if ($Properties -notcontains 'tokenGroups') { $copy.PSObject.Properties.Remove('tokenGroups') }
    $copy
}

function Get-FakeADMemberDN($Member, [string]$DomainDN) {
    # A member as Add-ADGroupMember and Remove-ADGroupMember take it: an object read with Get-AD… (its DN), or a DN,
    # which the group's DC finds in its own domain only, as the real one does.
    if ($Member -isnot [string]) { return [string]$Member.DistinguishedName }
    if (-not (Test-FakeADInDomain $Member $DomainDN)) { throw "Cannot find an object with identity: '$Member' under: '$DomainDN'." }
    $Member
}

function Add-ADGroupMember {
    # Members: DNs of the group's domain, or objects (an account of another domain, which a global group refuses).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [Parameter(Mandatory)]
        [object[]]$Members,
        [string]$Server
    )

    $domainDN = Resolve-FakeADDomain $Server
    Write-FakeADLog @{ Command = 'Add-ADGroupMember'; Identity = $Identity; Members = @($Members | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.DistinguishedName } }) -join ';'; Server = $Server }
    $group = Find-FakeADGroup $Identity $domainDN
    if ($group.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $dns = @(foreach ($member in $Members) { Get-FakeADMemberDN $member $domainDN })
    foreach ($dn in $dns) {
        if ($group.Members -contains $dn) { throw [ADException]::new('The specified account name is already a member of the group', 1378) }
        if ($group.GroupScope -eq 'Global' -and -not (Test-FakeADInDomain $dn $domainDN)) { throw 'A global group cannot have a cross-domain member.' }
    }
    $group.Members = @($group.Members) + $dns
}

function Remove-ADGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [Parameter(Mandatory)]
        [object[]]$Members,
        [string]$Server
    )

    $domainDN = Resolve-FakeADDomain $Server
    Write-FakeADLog @{ Command = 'Remove-ADGroupMember'; Identity = $Identity; Members = @($Members | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.DistinguishedName } }) -join ';'; Server = $Server }
    $group = Find-FakeADGroup $Identity $domainDN
    if (-not $PSCmdlet.ShouldProcess($Identity)) { return }
    if ($group.DenyWrite) { throw [ADException]::new('Insufficient access rights to perform the operation', 8344) }
    $dns = @(foreach ($member in $Members) { Get-FakeADMemberDN $member $domainDN })
    $group.Members = @($group.Members | Where-Object { $dns -notcontains $_ })
}

function Get-ADDefaultDomainPasswordPolicy {
    # The fake domains' lockout policy: 5 bad passwords within 30 minutes lock the account for 30 minutes.
    [CmdletBinding()]
    param([string]$Server)

    Write-FakeADLog @{ Command = 'Get-ADDefaultDomainPasswordPolicy'; Server = $Server }
    $null = Resolve-FakeADDomain $Server
    [pscustomobject]@{ LockoutThreshold = 5; LockoutDuration = [timespan]'00:30:00'; LockoutObservationWindow = [timespan]'00:30:00'; MinPasswordLength = 10 }
}

function Set-ADAccountExpiration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [Parameter(Mandatory)]
        [datetime]$DateTime,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Set-ADAccountExpiration'; Identity = $Identity; DateTime = $DateTime.ToString('yyyy-MM-dd HH:mm'); Server = $Server }
    $user = Find-FakeADUser $Identity (Resolve-FakeADDomain $Server)
    if ($user.DenyWrite) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    $user.AccountExpirationDate = $DateTime
}

function Clear-ADAccountExpiration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,
        [string]$Server
    )

    Write-FakeADLog @{ Command = 'Clear-ADAccountExpiration'; Identity = $Identity; Server = $Server }
    $user = Find-FakeADUser $Identity (Resolve-FakeADDomain $Server)
    if ($user.DenyWrite) { throw [System.UnauthorizedAccessException]::new('Access is denied') }
    $user.AccountExpirationDate = $null
}

Export-ModuleMember -Function Set-ADObject, Add-ADGroupMember, Remove-ADGroupMember, Get-ADDomainController, Get-ADDefaultDomainPasswordPolicy, Set-ADAccountExpiration, Clear-ADAccountExpiration, Get-ADUser, Unlock-ADAccount, Set-ADAccountPassword, Set-ADUser, Get-ADGroup, Get-ADForest, Get-ADDomain, Move-ADObject, Get-ADComputer, Get-LapsADPassword, Get-ADOrganizationalUnit, Get-ADObject, Set-ADComputer, Enable-ADAccount, Disable-ADAccount, Remove-ADComputer, Remove-ADObject, Test-Connection, Resolve-DnsName, New-CimSessionOption, New-CimSession, Invoke-Command, Remove-CimSession, Get-CimInstance, Invoke-CimMethod, Test-WSMan, quser, Test-ComputerPort, New-ScheduledTaskAction, New-ScheduledTaskTrigger, New-ScheduledTaskSettingsSet, New-ScheduledTaskPrincipal, Register-ScheduledTask, Get-ScheduledTask, Get-ScheduledTaskInfo, Start-ScheduledTask, Unregister-ScheduledTask, Remove-CimInstance
