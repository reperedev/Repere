# The actions on the selected computers (the Ordinateurs page), from the action bar or the right-click menu, with the
# current user's AD rights: Propriétés… (ComputerDetails.ps1), Modifier la description, Déplacer vers…, Groupes…, Ajouter à un groupe… and Retirer d'un
# groupe… (SelectionGroups.ps1), Prochain nom de cette série… (NextName.ps1), Clés BitLocker…, Mot de passe LAPS…,
# Activer / Désactiver, Supprimer de l'AD, Vérifier en ligne, Caractéristiques, Prendre la main…, Utilisateurs
# connectés…, the remote tools, Forcer les stratégies, Redémarrer… and Copier le nom; those that take a while run in the
# background. Also what the dialogs read: BitLocker keys (BitLockerDialog.ps1), LAPS passwords (LapsDialog.ps1), the
# OUs of a domain (SettingsWindow.ps1's Déplacer vers).
# Dot-sourced by the main script after ComputerPage.ps1 (the rows, the grid) and the dialogs (Show-Dialog,
# Show-ActionReport, Show-ActionNotice): it finds the action bar's and the menu's controls and wires them as it loads.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

$selectionText = $root.FindName('selection_text')

$menuProperties      = $root.FindName('menu_properties')
$menuEditDescription = $root.FindName('menu_edit_description')
$menuMove            = $root.FindName('menu_move')
$menuGroupsItem      = $root.FindName('menu_groups')
$menuGroupsAdd       = $root.FindName('menu_groups_add')
$menuGroupsRemove    = $root.FindName('menu_groups_remove')
$menuNextName        = $root.FindName('menu_next_name')
$menuBitLocker       = $root.FindName('menu_bitlocker')
$menuLaps            = $root.FindName('menu_laps')
$menuEnable          = $root.FindName('menu_enable')
$menuDisable         = $root.FindName('menu_disable')
$menuRemove          = $root.FindName('menu_remove')
$menuPing            = $root.FindName('menu_ping')
$menuSpecs           = $root.FindName('menu_specs')
$menuRdp             = $root.FindName('menu_rdp')
$menuShadow          = $root.FindName('menu_shadow')
$menuSessions        = $root.FindName('menu_sessions')
$menuCompMgmt        = $root.FindName('menu_compmgmt')
$menuCShare          = $root.FindName('menu_c_share')
$menuPwsh            = $root.FindName('menu_pwsh')
$menuServices        = $root.FindName('menu_services')
$menuEvents          = $root.FindName('menu_events')
$menuGpupdate        = $root.FindName('menu_gpupdate')
$menuRestart         = $root.FindName('menu_restart')
$menuRestartCancel   = $root.FindName('menu_restart_cancel')
$menuCopy            = $root.FindName('menu_copy')
$menuCopyOneLine     = $root.FindName('menu_copy_one_line')
$menuCopyRows        = $root.FindName('menu_copy_rows')
$menuGroups          = 'menu_group_ad', 'menu_group_keys', 'menu_group_remote', 'menu_group_restart', 'menu_group_copy' | ForEach-Object { $root.FindName($_) }
$actRdp        = $root.FindName('act_rdp')
$actShadow     = $root.FindName('act_shadow')
$actSessions   = $root.FindName('act_sessions')
$actRemoteMore = $root.FindName('act_remote_more')
$actCompMgmt   = $root.FindName('act_compmgmt')
$actCShare     = $root.FindName('act_c_share')
$actPwsh       = $root.FindName('act_pwsh')
$actServices   = $root.FindName('act_services')
$actEvents     = $root.FindName('act_events')
$actGpupdate   = $root.FindName('act_gpupdate')
$actRestart    = $root.FindName('act_restart')
$actRestartCancel = $root.FindName('act_restart_cancel')
$actPing       = $root.FindName('act_ping')
$actSpecs      = $root.FindName('act_specs')
$actToggle     = $root.FindName('act_toggle')
$actToggleText = $root.FindName('act_toggle_text')
$actToggleDisableIcon = $root.FindName('act_toggle_disable_icon')
$actToggleEnableIcon  = $root.FindName('act_toggle_enable_icon')
$actEdit       = $root.FindName('act_edit')
$actMove       = $root.FindName('act_move')
$actGroups     = $root.FindName('act_groups')
$actNextName   = $root.FindName('act_next_name')
$actBitLocker  = $root.FindName('act_bitlocker')
$actLaps       = $root.FindName('act_laps')
$actCopy       = $root.FindName('act_copy')
$actRemove     = $root.FindName('act_remove')

$actRemoteMore.Add_Click({ Open-ButtonMenu $actRemoteMore })

function Get-SelectedComputer {
    # The selected rows, as a copy: editing or removing rows changes the selection.
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $dataGrid.SelectedItems) { $selected.Add($row) }
    , $selected
}

function ConvertTo-ReadComputer($Computers) {
    # What a background read needs of each computer (Start-WindowRead): a copy of the row's name, DN and domain, rather
    # than the row the grid shows.
    foreach ($computer in $Computers) { @{ ComputerName = $computer.ComputerName; OU = $computer.OU; Domain = $computer.Domain } }
}

# Without -Server, AD commands go to the user's domain, so every action passes the domain the row was found in
# (-Server $computer.Domain). Otherwise a computer of another domain is "not found".

# How AD says a computer can't be deleted because it holds objects: its error code, its text being in Windows' language
# (Test-GroupRefusal).
$script:ComputerNotLeaf = @{ Pattern = 'leaf object|objet feuille'; Code = 8213 }

function Remove-ComputerFromAD([string]$DistinguishedName, [string]$Server) {
    # The computer first: one that holds nothing is gone, and one AD refuses for any other reason (rights) keeps
    # everything. When the objects it holds are what's in the way, they're removed one at a time, BitLocker's keys last,
    # then the computer, a leaf object by then. Returns how many objects it held.

    # Checked before anything is removed: a protected computer keeps its BitLocker information too.
    # The protection is reported, never removed. A domain controller is refused again here, whatever its row said:
    # the objects under it (its RID Set) would go first, even if AD then refused to delete it. So is the computer Repère
    # runs on, by its account as AD has it now (Get-ComputerGuard): its CN isn't always its name. Only without one, by
    # the DN Windows wrote, which may be another computer's by now. Without $Self (not passed to this runspace), it
    # can't say which computer is its own: refused, rather than deleted.
    if (-not $script:Self) { throw (Tr "l'ordinateur où Repère est ouvert inconnu, non supprimé") }
    $computer = Get-ADObject -Server $Server -Identity $DistinguishedName -Properties ProtectedFromAccidentalDeletion, PrimaryGroupID, sAMAccountName -ErrorAction Stop
    if ([int]$computer.PrimaryGroupID -in 516, 521) {
        throw (Tr 'contrôleur de domaine, non supprimé')
    }
    $account = [string]$computer.sAMAccountName -replace '\$$'
    $isSelf = if ($account) { Test-SelfAccount $account (Get-DomainOfDN $DistinguishedName) -Computer }
              else { [bool]$script:Self.ComputerDN -and $script:Self.ComputerDN -eq $DistinguishedName }
    if ($isSelf) {
        throw (Tr "l'ordinateur où Repère est ouvert, non supprimé")
    }
    if ($computer.ProtectedFromAccidentalDeletion) {
        throw (Tr 'protégé contre la suppression accidentelle, non supprimé')
    }
    try {
        Remove-ADComputer -Server $Server -Identity $DistinguishedName -Confirm:$false -ErrorAction Stop
        return 0
    }
    catch { if (-not (Test-GroupRefusal $_.Exception $script:ComputerNotLeaf)) { throw } }

    # BitLocker's keys last: a child that can't be deleted then leaves them where they are.
    $children = @(Get-ADObject -Server $Server -Filter * -SearchBase $DistinguishedName -SearchScope OneLevel -ErrorAction Stop |
        Sort-Object { @($_.ObjectClass)[-1] -eq 'msFVE-RecoveryInformation' })
    foreach ($child in $children) {
        try {
            Remove-ADObject -Server $Server -Identity $child.DistinguishedName -Confirm:$false -ErrorAction Stop
        }
        catch {
            throw ((Tr "impossible de supprimer l'objet {0} qu'il contient, ordinateur non supprimé : {1}") -f $child.Name, $_.Exception.Message)
        }
    }
    Remove-ADComputer -Server $Server -Identity $DistinguishedName -Confirm:$false -ErrorAction Stop
    $children.Count
}

function Get-BitLockerKey([string]$DistinguishedName, [string]$Server) {
    # The BitLocker recovery information stored under a computer. Each object is named "<date>{<key ID>}", and says
    # which volume it's for (msFVE-VolumeGuid, 16 bytes). Reading the recovery password needs extra AD rights; without
    # them it's empty. When sorts: the moment in UTC, seconds kept, as two keys of a disk can be saved in the same minute
    # (a key renewed right after the installation) or an hour apart that the local time shows the other way round (the
    # autumn's change of time). A name that isn't a date has none (MinValue): it sorts last, and Update-BitLockerStatus
    # makes its key a disk of its own rather than an old one. Date is the local time as text, for a spreadsheet
    # (yyyy-MM-dd HH:mm, or the name's text when it isn't a date); DateLabel is shown.
    $keys = Get-ADObject -Server $Server -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -SearchBase $DistinguishedName -SearchScope OneLevel -Properties 'msFVE-RecoveryPassword', 'msFVE-VolumeGuid' -ErrorAction Stop
    foreach ($key in $keys) {
        $date, $keyId = $key.Name, ''
        $label = $date
        $when = [datetimeoffset]::MinValue
        if ($key.Name -match '^(?<date>.+?)\{(?<id>[^}]+)\}$') {
            $keyId = $Matches.id
            $date = $label = $Matches.date
            $parsed = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($date, [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$parsed)) {
                $when = $parsed.ToUniversalTime()
                $date = $parsed.LocalDateTime.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
                $label = Format-TextDate $parsed.LocalDateTime
            }
        }
        $volume = $key.'msFVE-VolumeGuid'
        [pscustomobject]@{
            When              = $when
            Date              = $date
            DateLabel         = $label
            KeyId             = $keyId
            RecoveryPassword  = $key.'msFVE-RecoveryPassword'
            VolumeId          = if ($volume -is [byte[]] -and $volume.Length -eq 16) { [guid]::new($volume).ToString() } else { '' }
            DistinguishedName = $key.DistinguishedName
        }
    }
}

function Format-BitLockerKey($Computers, [switch]$WithOthers) {
    # The keys of each computer, as text to show (and copy) before anything happens to them. -WithOthers (Supprimer de
    # l'AD): the other objects under it too, deleted with it (a Hyper-V entry, what some software keeps there), each
    # with its kind; Others then says how many there are.
    $others = 0
    $sections = foreach ($computer in $Computers) {
        try {
            $keys = @(Get-BitLockerKey $computer.OU $computer.Domain | Sort-Object When -Descending)
            $more = @(if ($WithOthers) {
                Get-ADObject -Server $computer.Domain -Filter "-not (objectClass -eq 'msFVE-RecoveryInformation')" -SearchBase $computer.OU -SearchScope OneLevel -ErrorAction Stop
            })
            $others += $more.Count
            $also = if ($more.Count) { "`n  " + ((Tr 'Aussi supprimé : {0}') -f (@($more | ForEach-Object { "$($_.Name) ($(@($_.ObjectClass)[-1]))" }) -join ', ')) }
            if (-not $keys.Count) {
                ((Tr '{0} : aucune clé BitLocker') -f $computer.ComputerName) + $also
                continue
            }
            $lines = foreach ($key in $keys) {
                $password = if ($key.RecoveryPassword) { $key.RecoveryPassword } else { Tr 'non lisible (droits insuffisants)' }
                "  {0}  ID {1}`n  {2}`n    {3}" -f $key.DateLabel, $key.KeyId, (Tr 'Mot de passe de récupération :'), $password
            }
            "$($computer.ComputerName)`n$($lines -join "`n`n")$also"
        }
        catch {
            (Tr '{0} : clés BitLocker non lues ({1})') -f $computer.ComputerName, $_.Exception.Message
        }
    }
    if ($WithOthers) { @{ Text = $sections -join "`n`n"; Others = $others } } else { $sections -join "`n`n" }
}

function Read-ComputerContent($Computers) {
    # On a search runspace: what Supprimer de l'AD says goes with the computers.
    Format-BitLockerKey $Computers -WithOthers
}

# Supprimer de l'AD for more computers than this asks for their number to be typed: one OK can't delete a whole search.
# $env:REPERE_TYPE_TO_CONFIRM_ABOVE, for the UI tests, sets another (the sample data is small).
$script:TypeToConfirmAbove = if ($env:REPERE_TYPE_TO_CONFIRM_ABOVE) { [int]$env:REPERE_TYPE_TO_CONFIRM_ABOVE } else { 25 }

function Get-DomainControllerDN([string]$Domain) {
    # The DNs of a domain's controllers: its computers whose primary group is Domain Controllers (516), or Read-only
    # Domain Controllers (521). One query, when an action needs it: not read from each computer a search finds, which
    # AD's module makes slow.
    $controllers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($controller in Get-ADObject -Server $Domain -LDAPFilter '(|(primaryGroupID=516)(primaryGroupID=521))' -ErrorAction Stop) {
        $null = $controllers.Add($controller.DistinguishedName)
    }
    , $controllers
}

function Get-SelfComputerDN {
    # The DNs AD has now for the computer Repère runs on: the account of each of its names ($script:Self.Computer,
    # followed by $), which renaming the object in ADUC doesn't change, unlike its CN. One query, when an action needs it,
    # as for the domain controllers. When AD can't answer, none: Windows' DN and the names are left (Get-ComputerGuard),
    # said in the console only: AD answered the controllers' query to that domain just before, so it's rare, and the DN
    # Windows wrote is still there.
    $self = $script:Self
    $names = @($self.Computer | Where-Object { $_ })
    if (-not $names.Count -or -not $self.ComputerDomain) { return }
    $filter = '(|' + (($names | ForEach-Object { "(sAMAccountName=$(Get-LdapText "$_`$"))" }) -join '') + ')'
    try {
        foreach ($account in Get-ADObject -Server $self.ComputerDomain -LDAPFilter $filter -ErrorAction Stop) { [string]$account.DistinguishedName }
    }
    catch { Write-Host "Compte de cet ordinateur non lu dans AD, reconnu par son DN et son nom: $_" }
}

function Get-ComputerGuard($Computers) {
    # The computers an action that would cut them off (Désactiver, Supprimer, Déplacer) leaves alone, each « name
    # (why) » (Skipped): domain controllers, asked to AD once per domain (Get-DomainControllerDN), and the computer
    # Repère runs on. The others: Allowed. When AD can't say which are its controllers, none of that domain's computers
    # is allowed.
    # The computer Repère runs on is known by its DN, compared as AD does, whatever the case: the DN AD has for its
    # account, asked once and only when a computer of its domain is selected (Get-SelfComputerDN), its domain read from
    # the row's DN, since the row's Domain may be a DC's name (-Domains). Without an answer, the DN Windows wrote at its
    # last policy refresh; not with one, since after a rename in ADUC that DN may be a new computer's. Then by its names
    # (Test-SelfAccount), for when neither is known.
    $allowed = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $controllers = @{}
    $selfDN = @($script:Self.ComputerDN | Where-Object { $_ })
    $askedSelf = $false
    foreach ($computer in $Computers) {
        if (-not $controllers.ContainsKey($computer.Domain)) {
            $controllers[$computer.Domain] = try { Get-DomainControllerDN $computer.Domain } catch { [string]$_.Exception.Message }
        }
        $known = $controllers[$computer.Domain]
        if ($known -isnot [string] -and -not $askedSelf -and (Get-DomainOfDN $computer.OU) -eq $script:Self.ComputerDomain) {
            $askedSelf = $true
            $fromAD = @(Get-SelfComputerDN)
            if ($fromAD.Count) { $selfDN = $fromAD }
        }
        $why = if ($known -is [string]) { (Tr 'contrôleur de domaine ou non, AD ne le dit pas : {0}') -f (ConvertTo-FrenchError $known) }
               elseif ($known.Contains($computer.OU)) { Tr 'contrôleur de domaine' }
               elseif ($selfDN -contains $computer.OU -or (Test-SelfAccount $computer.ComputerName $computer.Domain -Computer)) { Tr "l'ordinateur où Repère est ouvert" }
        if ($why) { $skipped.Add("$($computer.ComputerName) ($why)") } else { $allowed.Add($computer) }
    }
    @{ Allowed = @($allowed); Skipped = @($skipped) }
}

function Read-ComputerGuard($Computers, [bool]$WithContents) {
    # On a search runspace: Get-ComputerGuard, whose queries would otherwise hold the window for a slow or unreachable
    # DC's timeout. The computers are copies (ConvertTo-ReadComputer), so those allowed come back by their place in the
    # selection (Allowed), for the window's thread to take its own rows. With $WithContents (Supprimer de l'AD), what
    # goes with those allowed too (Read-ComputerContent): one read before its confirmation, not two.
    for ($i = 0; $i -lt $Computers.Count; $i++) { $Computers[$i].Index = $i }
    $guard = Get-ComputerGuard $Computers
    $contents = if ($WithContents -and $guard.Allowed.Count) { Read-ComputerContent $guard.Allowed }
    @{ Allowed = @($guard.Allowed | ForEach-Object { $_.Index }); Skipped = @($guard.Skipped); Contents = $contents }
}

function Start-ComputerGuard([string]$Title, [string]$Icon, $Computers, [scriptblock]$OnAllowed, [switch]$WithContents, [System.Windows.Window]$Owner, $Context) {
    # Désactiver, Supprimer de l'AD and Déplacer vers: their guard read in the background (Read-ComputerGuard), the
    # window usable meanwhile, then on the window's thread & $OnAllowed $allowed $skipped $contents $Context, or
    # Show-ComputerGuard when every computer is left alone. One at a time: another click on any of the three while it
    # reads is ignored (Start-WindowRead), so a double click asks once. A read that fails allows nothing: each computer
    # is said not done, as a domain AD can't say the controllers of is refused. $Owner: the window what it says opens
    # over (a computer's Propriétés), the main one without.
    $Computers = @($Computers)
    if (-not $Computers.Count) { return }
    Start-WindowRead -Kind 'ComputerGuard' -Command 'Read-ComputerGuard' -Arguments @(@(ConvertTo-ReadComputer $Computers), [bool]$WithContents) `
        -Functions 'Get-ComputerGuard', 'Get-DomainControllerDN', 'Get-SelfComputerDN', 'Test-SelfAccount', 'Get-DomainOfDN', 'Get-LdapText', 'Read-ComputerContent', 'Format-BitLockerKey', 'Get-BitLockerKey' `
        -Variables @{ Self = $script:Self } -Context @{ Computers = $Computers; Title = $Title; Icon = $Icon; OnAllowed = $OnAllowed; Owner = $Owner; Context = $Context } -OnDone {
        param($context, $guard, $problem)
        if ($problem -or -not $guard) {
            $reason = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
            Show-ActionReport @($context.Computers | ForEach-Object { (Tr '✖ {0} : {1}') -f $_.ComputerName, $reason }) $context.Title -Owner $context.Owner
            return
        }
        $allowed = @($guard.Allowed | ForEach-Object { $context.Computers[$_] })
        if (-not $allowed.Count) {
            if ($guard.Skipped.Count) { Show-ComputerGuard $context.Title $context.Icon $guard.Skipped $context.Owner }
            return
        }
        & $context.OnAllowed $allowed @($guard.Skipped) $guard.Contents $context.Context
    }
}

function Show-ComputerGuard([string]$Title, [string]$Icon, [string[]]$Skipped, [System.Windows.Window]$Owner) {
    # Every computer selected is one the action leaves alone: said, and nothing else happens.
    Show-Dialog -Title $Title -Icon $Icon -Tone 'warn' -Heading ((Tr '{0} : rien à faire') -f $Title) -Owner $Owner `
        -Message ((Tr 'Repère ne touche pas à ces ordinateurs, pour ne pas couper le domaine ou votre session : {0}.') -f ($Skipped -join ', '))
}

function Get-ComputerGuardNote([string[]]$Skipped) {
    # What a confirmation adds when some of the computers selected are left alone.
    if ($Skipped.Count) { "`n`n" + ((Tr 'Laissés de côté : {0}.') -f ($Skipped -join ', ')) }
}

# Windows LAPS's Get-LapsADPassword comes with Windows 11 22H2, Windows 10 and Server 2019 since April 2023. Without it,
# only legacy LAPS passwords can be read.
$hasLapsCommand = [bool](Get-Command Get-LapsADPassword -ErrorAction SilentlyContinue)

function Get-LapsPassword([string]$DistinguishedName, [string]$Server) {
    # The computer's local administrator password: Kind (Windows LAPS or LAPS hérité, $null without one), Account,
    # Password, Expires, and Problem when it can't be shown, all in the run's language (LapsDialog.ps1 compares Kind
    # and Expires with their Tr text). Windows LAPS first, which decrypts an encrypted password
    # when the user is allowed to. Then the attributes themselves: legacy LAPS, and which password exists but can't be
    # read (its expiration can be, its password is confidential).
    $windowsError = $null
    if ($hasLapsCommand) {
        try {
            # Nothing for a computer without a Windows LAPS password: then the attributes below.
            $laps = Get-LapsADPassword -Identity $DistinguishedName -Domain $Server -AsPlainText -ErrorAction Stop | Select-Object -First 1
            if ($laps) {
                $kind = if ("$($laps.Source)" -like 'Legacy*') { Tr 'LAPS hérité' } else { 'Windows LAPS' }
                if ($laps.Password) {
                    return [pscustomobject]@{ Kind = $kind; Account = $laps.Account; Password = $laps.Password; Expires = Format-LapsDate $laps.ExpirationTimestamp; Problem = $null }
                }
                if ("$($laps.Source)" -like 'Encrypted*') {
                    return [pscustomobject]@{ Kind = (Tr 'Windows LAPS (chiffré)'); Account = $laps.Account; Password = $null; Expires = Format-LapsDate $laps.ExpirationTimestamp; Problem = (Tr 'chiffré, non déchiffrable avec vos droits') }
                }
            }
        }
        catch {
            $windowsError = $_.Exception.Message
        }
    }

    # Every attribute rather than the LAPS ones by name: a name the schema doesn't have (legacy LAPS never installed)
    # would fail the whole query.
    # Only the attributes that have a value come back: the others read as none, strict mode or not.
    $computer = Get-ADComputer -Server $Server -Identity $DistinguishedName -Properties * -ErrorAction Stop |
        Select-Object 'ms-Mcs-AdmPwd', 'ms-Mcs-AdmPwdExpirationTime', 'msLAPS-PasswordExpirationTime'
    if ($computer.'ms-Mcs-AdmPwd') {
        # Legacy LAPS doesn't keep the account's name: it's the built-in one unless a GPO names another.
        return [pscustomobject]@{ Kind = (Tr 'LAPS hérité'); Account = (Tr 'administrateur intégré (ou celui de la GPO LAPS)'); Password = $computer.'ms-Mcs-AdmPwd'; Expires = Format-LapsDate $computer.'ms-Mcs-AdmPwdExpirationTime'; Problem = $null }
    }
    $windowsExpires = Format-LapsDate $computer.'msLAPS-PasswordExpirationTime'
    if ($windowsExpires) {
        $problem = if ($windowsError) { (Tr 'non lu ({0})') -f $windowsError }
                   elseif (-not $hasLapsCommand) { Tr 'non lisible sans Get-LapsADPassword (module LAPS de Windows)' }
                   else { Tr 'non lisible (droits insuffisants)' }
        return [pscustomobject]@{ Kind = 'Windows LAPS'; Account = $null; Password = $null; Expires = $windowsExpires; Problem = $problem }
    }
    $legacyExpires = Format-LapsDate $computer.'ms-Mcs-AdmPwdExpirationTime'
    if ($legacyExpires) {
        return [pscustomobject]@{ Kind = (Tr 'LAPS hérité'); Account = $null; Password = $null; Expires = $legacyExpires; Problem = (Tr 'non lisible (droits insuffisants)') }
    }
    # Neither expiration is set, so there's no password (Get-LapsADPassword may have failed only for that).
    [pscustomobject]@{ Kind = $null; Account = $null; Password = $null; Expires = $null; Problem = $null }
}

function Update-MenuItem {
    # Follows the selection (and the rows' state) rather than the menu opening, so the items are already right
    # when it opens. Activer / Désactiver are greyed out when every selected computer is already in that state.
    $selected = Get-SelectedComputer
    $count = $selected.Count
    $hasSelection = $count -gt 0
    $canEnable = $canDisable = $false
    foreach ($row in $selected) {
        if ($row.IsOn) { $canDisable = $true } else { $canEnable = $true }
    }
    # One computer at a time, so a large selection can't open a window per computer.
    $single = $count -eq 1
    $menuProperties.IsEnabled = $single
    $menuEditDescription.IsEnabled = $hasSelection
    $menuMove.IsEnabled = $hasSelection
    $menuGroupsItem.IsEnabled = $single
    $menuGroupsAdd.IsEnabled = $hasSelection
    $menuGroupsRemove.IsEnabled = $hasSelection
    $menuNextName.IsEnabled = $single
    $menuBitLocker.IsEnabled = $hasSelection
    $menuLaps.IsEnabled = $hasSelection
    $menuEnable.IsEnabled = $canEnable
    $menuDisable.IsEnabled = $canDisable
    $menuRemove.IsEnabled = $hasSelection
    $menuPing.IsEnabled = $hasSelection
    $menuSessions.IsEnabled = $hasSelection
    $menuSpecs.IsEnabled = $single
    $menuRdp.IsEnabled = $single
    $menuCompMgmt.IsEnabled = $single
    $menuCShare.IsEnabled = $single
    foreach ($item in $menuShadow, $menuPwsh, $menuServices, $menuEvents, $menuGpupdate, $menuRestart, $menuRestartCancel) { $item.IsEnabled = $single }
    foreach ($item in $menuCopy, $menuCopyOneLine, $menuCopyRows) { $item.IsEnabled = $hasSelection }
    # A submenu is enabled while one of its items is.
    foreach ($group in $menuGroups) {
        $group.IsEnabled = [bool]@($group.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] -and $_.IsEnabled }).Count
    }
    # The action bar offers the same. Its Désactiver button becomes Activer when every selected computer is disabled
    # (with some of each, Activer is in the right-click menu).
    $actRdp.IsEnabled = $single
    $actRemoteMore.IsEnabled = $single
    $actCompMgmt.IsEnabled = $single
    $actCShare.IsEnabled = $single
    foreach ($item in $actShadow, $actPwsh, $actServices, $actEvents, $actGpupdate, $actRestart, $actRestartCancel) { $item.IsEnabled = $single }
    $actPing.IsEnabled = $hasSelection
    $actSessions.IsEnabled = $hasSelection
    $actSpecs.IsEnabled = $single
    $actToggle.IsEnabled = $hasSelection
    $offerEnable = $canEnable -and -not $canDisable
    $actToggleDisableIcon.Visibility = ConvertTo-Visibility (-not $offerEnable)
    $actToggleEnableIcon.Visibility = ConvertTo-Visibility $offerEnable
    $actToggleText.Text = if ($offerEnable) { Tr 'Activer' } else { Tr 'Désactiver…' }
    $actEdit.IsEnabled = $hasSelection
    $actMove.IsEnabled = $hasSelection
    $actGroups.IsEnabled = $single
    # act_next_name is never disabled: with none or several selected, it opens on the last format used.
    $actBitLocker.IsEnabled = $hasSelection
    $actLaps.IsEnabled = $hasSelection
    $actCopy.IsEnabled = $hasSelection
    $actRemove.IsEnabled = $hasSelection
    $selectionText.Text = switch ($count) {
        0 { Tr 'Aucune sélection' }
        1 { (Tr '{0} sélectionné') -f $selected[0].ComputerName }
        default { (Tr '{0} ordinateurs sélectionnés') -f $count }
    }
}

# The fake AD's computers don't exist on the network: it provides its own Test-Connection and Resolve-DnsName, which
# the online check loads in each of its parallel runspaces, and the commands the other remote tools use.
$fakeADModule = if ($useFakeAD) { "$PSScriptRoot\FakeAD\FakeAD.psm1" }

# Vérifier en ligne: ping first; many networks block it, so an open file sharing (445) or Remote Desktop (3389) port also
# counts. The two ports are tried together, only when the ping gets no answer: the same connections as one after the
# other, but a computer that's off takes 2 s instead of 3. In parallel with a short timeout, 48 computers at a time (it
# only waits on the network: 96 computers that are off take 4.5 s rather than 12 at 16, for about 50 MB more), in the
# background: each computer's answer comes out as soon as it's known
# (Id, How it answered or $null, and the address its name resolves to, IPv4 when it has one, even when it's offline: a
# name that still points to an old address is worth seeing; '' when the DNS doesn't know the name, said by the window,
# which has the language).
$onlineCheckScript = {
    param($Computers, [string]$FakeModule)
    $Computers | ForEach-Object -ThrottleLimit 48 -Parallel {
        if ($using:FakeModule) { Import-Module $using:FakeModule }
        $address = try {
            $ips = @(Resolve-DnsName -Name $_.HostName -Type A_AAAA -QuickTimeout -ErrorAction Stop | Where-Object { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress } | ForEach-Object { [string]$_.IPAddress } | Select-Object -Unique)
            $ipv4 = @($ips | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
            if ($ipv4.Count) { $ipv4 -join ', ' } elseif ($ips.Count) { $ips -join ', ' } else { '' }
        }
        catch { '' }
        $how = $null
        if (Test-Connection -TargetName $_.HostName -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction SilentlyContinue) {
            $how = 'ping'
        }
        else {
            # Both ports at once, the first that accepts a connection within 1 s. The fake AD answers for its computers.
            $hostName = $_.HostName
            $port = $null
            if (Get-Command Test-ComputerPort -ErrorAction SilentlyContinue) { $port = Test-ComputerPort $hostName 445, 3389 1000 }
            else {
                $attempts = foreach ($tcpPort in 445, 3389) {
                    $client = [System.Net.Sockets.TcpClient]::new()
                    @{ Port = $tcpPort; Client = $client; Task = $client.ConnectAsync($hostName, $tcpPort) }
                }
                try {
                    $watch = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($true) {
                        $port = @($attempts | Where-Object { $_.Task.Status -eq 'RanToCompletion' } | ForEach-Object { $_.Port })[0]
                        $pending = @($attempts | Where-Object { -not $_.Task.IsCompleted })
                        $left = 1000 - $watch.ElapsedMilliseconds
                        if ($port -or -not $pending.Count -or $left -le 0) { break }
                        $null = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($pending | ForEach-Object { $_.Task }), [int]$left)
                    }
                }
                finally { foreach ($attempt in $attempts) { $attempt.Client.Dispose() } }
            }
            if ($port) { $how = "port $port" }
        }
        [pscustomobject]@{ Id = $_.Id; How = $how; Address = $address }
    }
}.ToString()

# The checks under way: each its PowerShell, the answers read so far, and its rows by Id.
$onlineChecks = [System.Collections.Generic.List[object]]::new()
$onlineTimer = [System.Windows.Threading.DispatcherTimer]::new()
$onlineTimer.Interval = [timespan]::FromMilliseconds(150)

function Start-OnlineCheck($Computers, [switch]$Quiet) {
    # Shows En ligne if it's hidden, marks the rows as being checked, then checks them in the background. Quiet: no toast
    # at the end, for a check nobody asked for (Show-SearchResult).
    if (-not $gridColumns.Shown['Online']) {
        $gridColumns.Shown['Online'] = $true
        Update-ColumnVisibility
    }
    $rows = @{}
    $inputs = for ($i = 0; $i -lt $Computers.Count; $i++) {
        $row = $Computers[$i]
        $rows[$i] = $row
        $row.Online = '…'
        $row.OnlineTip = Tr 'Vérification…'
        $row.IsOnline = $null
        $row.OnlineLabel = Tr 'Vérification…'
        $row.OnlineAddress = ''

        [pscustomobject]@{ Id = $i; HostName = $row.HostName }
    }
    Update-ChangedRow
    $shell = [powershell]::Create()
    $null = $shell.AddScript($onlineCheckScript).AddParameters(@{ Computers = @($inputs); FakeModule = $fakeADModule })
    $output = [System.Management.Automation.PSDataCollection[psobject]]::new()
    $noInput = [System.Management.Automation.PSDataCollection[psobject]]::new()
    $noInput.Complete()
    $onlineChecks.Add(@{ Shell = $shell; Handle = $shell.BeginInvoke($noInput, $output); Output = $output; Read = 0; Rows = $rows; Lines = [System.Collections.Generic.List[string]]::new(); Quiet = [bool]$Quiet
                       Stale = $false; Drawn = [System.Diagnostics.Stopwatch]::StartNew() })
    $onlineTimer.Start()
}

function Update-OnlineCheck {
    # On each tick: the answers that came, in their rows; then, once a check has ended, its summary in the status bar.
    foreach ($check in @($onlineChecks)) {
        $changed = $false
        while ($check.Read -lt $check.Output.Count) {
            $answer = $check.Output[$check.Read]
            $check.Read++
            $row = $check.Rows[[int]$answer.Id]
            $address = if ($answer.Address) { [string]$answer.Address } else { Tr 'nom DNS introuvable' }
            $row.IsOnline = [bool]$answer.How
            $row.Online = if ($answer.How) { "✔ $address" } else { "✖ $address" }
            $row.OnlineTip = if ($answer.How) { (Tr 'En ligne ({0})') -f $answer.How } else { Tr 'Hors ligne : pas de réponse au ping ni aux ports 445 et 3389' }
            $row.OnlineLabel = if ($answer.How) { Tr 'En ligne' } else { Tr 'Hors ligne' }
            $row.OnlineAddress = $address
            $check.Lines.Add($(if ($answer.How) { (Tr '✔ {0} : en ligne ({1}) — {2}') -f $row.ComputerName, $answer.How, $address }
                               else { (Tr '✖ {0} : hors ligne (pas de réponse au ping ni aux ports 445 et 3389) — {1}') -f $row.ComputerName, $address }))
            $changed = $true
        }
        if ($check.Handle.IsCompleted -and $check.Read -ge $check.Output.Count) {
            $onlineChecks.Remove($check) | Out-Null
            try { $null = $check.Shell.EndInvoke($check.Handle) } catch { Write-Host "Vérifier en ligne : $_" }
            finally { $check.Shell.Dispose() }
            # A computer the check couldn't answer for (an error) isn't left « … ».
            foreach ($row in $check.Rows.Values) {
                if ($row.Online -eq '…') {
                    $row.Online = '✖ ' + (Tr 'non vérifié'); $row.OnlineTip = Tr 'La vérification a échoué.'; $row.IsOnline = $false
                    $row.OnlineLabel = Tr 'Échec'; $row.OnlineAddress = Tr 'non vérifié'; $changed = $true
                }
            }
            $online = @($check.Lines | Where-Object { $_.StartsWith('✔') }).Count
            $sorted = @($check.Lines | Where-Object { $_.StartsWith('✖') }) + @($check.Lines | Where-Object { $_.StartsWith('✔') })
            # Headed by the answer: « Hors ligne » and why, for one; « 2 en ligne sur 4 » and which aren't, for several.
            $offline = @($check.Rows.Values | Where-Object { -not $_.IsOnline } | ForEach-Object ComputerName | Sort-Object)
            $heading, $text = if ($check.Lines.Count -eq 1) {
                $(if ($online) { Tr 'En ligne' } else { Tr 'Hors ligne' }), $check.Lines[0]
            }
            else {
                ((Tr '{0} en ligne sur {1}') -f $online, $check.Rows.Count), $(if ($offline.Count) { (Tr 'Hors ligne : {0}') -f ($offline -join ', ') } else { Tr '✔ Tous en ligne' })
            }
            if (-not $check.Quiet) { Show-ActionNotice $heading $text ($sorted -join "`n") }
        }
        # Each redraw goes through every row: thousands of them get one a second, and one more when the check ends.
        if ($changed) { $check.Stale = $true }
        if ($check.Stale -and ($script:results.Rows.Count -lt 1000 -or $check.Drawn.ElapsedMilliseconds -ge 1000 -or -not $onlineChecks.Contains($check))) {
            $check.Stale = $false
            $check.Drawn.Restart()
            Update-ChangedRow
        }
    }
    if (-not $onlineChecks.Count) { $onlineTimer.Stop() }
}
$onlineTimer.Add_Tick({ Update-OnlineCheck })

function Start-RemoteTool([string]$Title, [string]$FilePath, [string]$Arguments) {
    # Starts the tool without waiting for it. With the fake AD, the computers don't exist: shows the command instead.
    if ($useFakeAD) {
        Show-Dialog -Title $Title -Message ((Tr "AD fictif : rien n'est lancé.") + "`n`n$FilePath $Arguments")
        return
    }
    try {
        Start-Process -FilePath $FilePath -ArgumentList $Arguments -ErrorAction Stop
    }
    catch {
        Show-Dialog -Title $Title -Icon 'xcircle' -Tone 'danger' -Message ((Tr 'Impossible de lancer {0} : {1}') -f $FilePath, $_.Exception.Message)
    }
}

# Actions that can take a while on a remote computer run in their own runspace: the window stays usable, and a timer
# hands each one's output (or error) to its OnDone script block once it ends, or after its time limit.
$backgroundActions = [System.Collections.Generic.List[object]]::new()
$backgroundTimer = [System.Windows.Threading.DispatcherTimer]::new()
$backgroundTimer.Interval = [timespan]::FromMilliseconds(250)

function Start-BackgroundAction([string]$Script, [hashtable]$Parameters, [int]$TimeoutSeconds, [scriptblock]$OnDone, $State) {
    # The runspace follows the process's execution policy, as the search runspaces do (the main script).
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $shell = [powershell]::Create($sessionState)
    $null = $shell.AddScript($Script).AddParameters($Parameters)
    $script:backgroundActions.Add(@{ Shell = $shell; Handle = $shell.BeginInvoke(); Watch = [System.Diagnostics.Stopwatch]::StartNew()
                                     Timeout = $TimeoutSeconds; OnDone = $OnDone; State = $State })
    $script:backgroundTimer.Start()
}

function Update-BackgroundAction {
    foreach ($action in @($script:backgroundActions)) {
        $timedOut = -not $action.Handle.IsCompleted -and $action.Watch.Elapsed.TotalSeconds -ge $action.Timeout
        if (-not $action.Handle.IsCompleted -and -not $timedOut) { continue }
        # Already collected by a tick that ran while an OnDone's window was open (ShowDialog lets the timer run).
        if (-not $script:backgroundActions.Remove($action)) { continue }
        $output = $null
        $failure = $null
        if ($timedOut) {
            # Not waited for: Remove-StoppedJob disposes it once it has ended on its own.
            $null = $action.Shell.BeginStop($null, $null)
            $script:search.Stopping.Add($action)
            $failure = (Tr 'pas de réponse après {0} secondes (ordinateur éteint ou injoignable ?)') -f $action.Timeout
        }
        else {
            try {
                $output = @($action.Shell.EndInvoke($action.Handle))
                if ($action.Shell.Streams.Error.Count) { $failure = $action.Shell.Streams.Error[0].Exception.Message }
            }
            catch { $failure = $_.Exception.InnerException.Message; if (-not $failure) { $failure = $_.Exception.Message } }
            finally { $action.Shell.Dispose() }
        }
        & $action.OnDone $output $failure $action.State
    }
    if (-not $script:backgroundActions.Count) { $script:backgroundTimer.Stop() }
}
$backgroundTimer.Add_Tick({ Update-BackgroundAction })

# Forcer les stratégies: Invoke-GPUpdate when the GPMC tools are installed (a task on the computer runs gpupdate /force
# for the computer and in each user session, at once). Without them, or when it fails (its connection, the remote
# Task Scheduler's, is often closed by the firewall), Repère's own task, created over CIM, which runs gpupdate for the
# computer only (RemoteAccess.ps1). Returns the method used and gpupdate's exit code. With the fake AD, Repère's task,
# on its fake computers.
$policyUpdateScript = {
    param([string]$HostName, [string]$FakeModule, [string]$RemoteAccessScript)
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($RemoteAccessScript))
    $gpmcError = $null
    if ($FakeModule) { Import-Module $FakeModule }
    elseif (Get-Module -ListAvailable GroupPolicy) {
        try {
            Import-Module GroupPolicy -WarningAction SilentlyContinue
            Invoke-GPUpdate -Computer $HostName -Force -RandomDelayInMinutes 0
            return [pscustomobject]@{ Method = 'Invoke-GPUpdate'; ExitCode = 0 }
        }
        catch { $gpmcError = $_.Exception.Message.Trim() }
    }
    try { $code = Invoke-PolicyUpdateTask $HostName }
    catch {
        if ($gpmcError) { throw "Invoke-GPUpdate : $gpmcError | $($_.Exception.Message.Trim())" }
        throw
    }
    [pscustomobject]@{ Method = 'Task'; ExitCode = $code }
}.ToString()

function Get-RemoteFailureReason([string]$Failure) {
    # Why a remote action failed, from Windows' message, in its language. « Injoignable » only for Windows' transport
    # errors: Repère's own messages name WinRM and Repere-WinRM too, about a computer that was reached.
    switch -Regex ($Failure) {
        'Accès refusé|Access is denied|0x80070005' { return Tr "accès refusé (il faut être administrateur de l'ordinateur)" }
        'serveur RPC n.est pas disponible|RPC server is unavailable|0x800706BA|0x80338012|WS-Management service cannot process' { return (Tr 'ordinateur injoignable ({0})') -f $Failure }
        default { return $Failure }
    }
}

function Test-RemoteUnreachable([string]$Failure) {
    # Whether a remote action failed only because the computer didn't answer (off, or behind a firewall): Windows' « RPC
    # server unavailable », or no answer in time. That's said in a toast, as Vérifier en ligne says it; a refusal or
    # another error stays a report, with Windows' message.
    $timedOut = [regex]::Escape((Tr 'pas de réponse après {0} secondes (ordinateur éteint ou injoignable ?)')).Replace('\{0}', '\d+')
    $Failure -notmatch 'Accès refusé|Access is denied|0x80070005' -and
        $Failure -match "serveur RPC n.est pas disponible|RPC server is unavailable|0x800706BA|^$timedOut$"
}

function Show-UnreachableNotice([string]$Title, [string]$Name, [string]$Reason, [string]$Details, [switch]$Persist) {
    # « ✖ ORD-05 : hors ligne (…) » in a toast, with the action's name as its heading: nothing to choose or to close, as
    # for a computer with no BitLocker key. Details (Windows' messages) in its tooltip. Persist: it stays until closed.
    Show-ActionNotice $Title ((Tr '✖ {0} : {1}') -f $Name, $Reason) $Details -Persist:$Persist
}

# The computers whose policies are being updated, so a second click doesn't run gpupdate there again.
$script:PolicyUpdates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Start-PolicyUpdate($Computer) {
    # gpupdate can take up to 2 minutes: « ORD-05 : en cours… » stays in the bar at the bottom from the click, then
    # turns into the outcome, in a word, with the rest in its tooltip. A failure stays until it's closed, since the
    # technician may have moved on meanwhile.
    $title = Tr 'Forcer les stratégies'
    $running = (Tr '{0} : en cours…') -f $Computer.ComputerName
    $waitTip = Tr "gpupdate peut prendre jusqu'à 2 minutes."
    Show-ActionNotice $title $running $waitTip -Persist
    if (-not $script:PolicyUpdates.Add($Computer.HostName)) { return }
    # Up to 2 minutes for gpupdate, after the connections tried before it.
    Start-BackgroundAction $policyUpdateScript @{ HostName = $Computer.HostName; FakeModule = $fakeADModule; RemoteAccessScript = $script:RemoteAccessScript } 300 {
        param($output, $failure, $computer)
        $null = $script:PolicyUpdates.Remove($computer.HostName)
        $name = $computer.ComputerName
        $title = Tr 'Forcer les stratégies'
        if ($failure -and (Test-RemoteUnreachable $failure)) {
            Show-UnreachableNotice $title $name (Tr 'injoignable (ni WinRM ni DCOM ne répondent : ordinateur éteint, ou pare-feu)') $failure -Persist
            return
        }
        if ($failure) {
            Show-ActionNotice $title ((Tr '✖ {0} : {1}') -f $name, (Get-RemoteFailureReason $failure)) $failure -Persist
            return
        }
        $result = @($output)[-1]
        if ($result.Method -eq 'Invoke-GPUpdate') {
            Show-ActionNotice $title ((Tr '✔ {0} : mise à jour lancée') -f $name) (Tr "Pour l'ordinateur et chaque session ouverte.")
        }
        # Repère's task: the sessions of logged-on users weren't refreshed.
        elseif ($result.ExitCode -eq 0) {
            Show-ActionNotice $title ((Tr "✔ {0} : stratégies de l'ordinateur à jour") -f $name) (Tr 'Les sessions des utilisateurs les recevront à leur prochaine mise à jour.')
        }
        else {
            Show-ActionNotice $title ((Tr '✖ {0} : gpupdate a échoué (code {1})') -f $name, $result.ExitCode) (Tr "Le journal Système de l'ordinateur dit pourquoi (source GroupPolicy).") -Persist
        }
    } $Computer
}

# PowerShell à distance and Caractéristiques: the computers where Repère turned WinRM on, each with what uses it there
# (Holders: the terminals open to it, and the Caractéristiques windows, done once they've exited or closed), when the
# computer puts WinRM back on its own (Until), and the title its report has (Title). Once the last one is done, Repère
# puts it back.
$script:WinRMLeases = @{}
$winrmTimer = [System.Windows.Threading.DispatcherTimer]::new()
$winrmTimer.Interval = [timespan]::FromSeconds(2)

# Whether the computer answers on WinRM's port, or else on DCOM's (RPC, 135), through which Repère can turn WinRM on;
# when neither does, whether it answers ping (Ping: it's on, and a firewall may only be slow or strict), or not (None).
$winrmCheckScript = {
    param([string]$HostName, [string]$FakeModule, [string]$RemoteAccessScript)
    if ($FakeModule) { Import-Module $FakeModule }
    . ([scriptblock]::Create($RemoteAccessScript))
    if (Test-RemotePort $HostName 5985) { return 'WinRM' }
    if (Test-RemotePort $HostName 135) { return 'DCOM' }
    if (Test-Connection -TargetName $HostName -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction SilentlyContinue) { return 'Ping' }
    'None'
}.ToString()

$winrmEnableScript = {
    param([string]$HostName, [int]$Hours, [string]$FakeModule, [string]$RemoteAccessScript)
    $ErrorActionPreference = 'Stop'
    if ($FakeModule) { Import-Module $FakeModule }
    . ([scriptblock]::Create($RemoteAccessScript))
    [pscustomobject]@{ Until = Enable-TemporaryWinRM $HostName (Get-LocalAddress) $Hours }
}.ToString()

# Whether WinRM answers this account now: its port, then WinRM itself.
$winrmAnswerScript = {
    param([string]$HostName, [string]$FakeModule, [string]$RemoteAccessScript)
    if ($FakeModule) { Import-Module $FakeModule }
    . ([scriptblock]::Create($RemoteAccessScript))
    (Test-RemotePort $HostName 5985) -and (Test-RemoteWinRM $HostName)
}.ToString()

$winrmRestoreScript = {
    param([string]$HostName, [string]$FakeModule, [string]$RemoteAccessScript)
    $ErrorActionPreference = 'Stop'
    if ($FakeModule) { Import-Module $FakeModule }
    . ([scriptblock]::Create($RemoteAccessScript))
    Restore-TemporaryWinRM $HostName
}.ToString()

function Start-RemotePowerShell($Computer) {
    # A new PowerShell window (the one Repère runs in), already in a session on the computer. When WinRM doesn't
    # answer there, Repère offers to turn it on for the session. Its name comes from AD and goes into that window's
    # command line: only what a host name can hold gets there.
    if ($Computer.HostName -notmatch '^[A-Za-z0-9._-]+\z') {
        Show-ActionReport @((Tr '✖ {0} : {1}') -f $Computer.ComputerName, ((Tr "nom d'ordinateur invalide : '{0}'") -f $Computer.HostName)) -Title (Tr 'PowerShell à distance')
        return
    }
    if ($script:WinRMLeases.ContainsKey($Computer.HostName)) {
        Open-RemoteTerminal $Computer
        return
    }
    Start-BackgroundAction $winrmCheckScript @{ HostName = $Computer.HostName; FakeModule = $fakeADModule; RemoteAccessScript = $script:RemoteAccessScript } 15 {
        param($output, $failure, $computer)
        $title = Tr 'PowerShell à distance'
        $answer = if (-not $failure) { "$(@($output)[-1])" }
        $hours = 4
        if ($answer -eq 'None') { Show-UnreachableNotice $title $computer.ComputerName (Tr 'hors ligne (pas de réponse au ping, ni à WinRM ni à DCOM)') }
        elseif ($failure -and (Test-RemoteUnreachable $failure)) { Show-UnreachableNotice $title $computer.ComputerName $failure }
        elseif ($failure) { Show-ActionReport @((Tr '✖ {0} : {1}') -f $computer.ComputerName, $failure) -Title $title }
        elseif ($answer -eq 'WinRM') { Open-RemoteTerminal $computer }
        elseif ($answer -eq 'Ping') {
            # On, but neither port answered in time: a firewall, or a slow network. Turning WinRM on goes through DCOM,
            # so it may fail too; that failure is then reported.
            $message = Tr "Ni WinRM ni DCOM n'ont répondu : un pare-feu les bloque peut-être. Repère peut essayer d'activer WinRM pour cette session. Il est remis comme avant à la fermeture du terminal."
            Request-TemporaryWinRM $computer $title $message 'terminal' $hours 'Terminal' -Heading ((Tr '{0} répond au ping, mais pas à Repère') -f $computer.ComputerName)
        }
        else {
            $message = Tr "Repère peut l'activer pour cette session. Il est remis comme avant à la fermeture du terminal."
            Request-TemporaryWinRM $computer $title $message 'terminal' $hours 'Terminal'
        }
    } $Computer
}

function Request-TemporaryWinRM($Computer, [string]$Title, [string]$Message, [string]$Icon, [int]$Hours, [string]$OpenWith, [string]$AltText, [string]$Heading) {
    # Asks to turn WinRM on for a while, then turns it on in the background and opens what needed it (OpenWith: Terminal,
    # or Specs, the Caractéristiques window). AltText: a way to go on without it, which opens the same over DCOM.
    # Heading: « WinRM n'est pas activé sur ORD-04 » unless it's said otherwise (a computer that only answers ping).
    if (-not $Heading) { $Heading = (Tr "WinRM n'est pas activé sur {0}") -f $Computer.ComputerName }
    $state = @{ Computer = $Computer; Hours = $Hours; Title = $Title; OpenWith = $OpenWith }
    Show-Dialog -Title $Title -Heading $Heading -Message $Message -Icon $Icon -Tone 'warn' `
        -OkText (Tr 'Activer WinRM') -AltText $AltText -State $state -OnAlt { param($state) Open-WinRMClient $state.Computer $state.OpenWith } -OnOk {
        param($state)
        # Turning it on takes up to a minute: « ORD-05 : activation de WinRM… » stays in the bar at the bottom, and the
        # pointer says something runs, until the terminal or the window opens, or the failure is said.
        Show-ActionNotice $state.Title ((Tr '{0} : activation de WinRM…') -f $state.Computer.ComputerName) (Tr "Repère active WinRM, puis attend qu'il réponde : jusqu'à une minute.") -Persist
        $null = $script:WinRMEnabling.Add($state.Computer.HostName)
        $script:win.Cursor = [System.Windows.Input.Cursors]::AppStarting
        $parameters = @{ HostName = $state.Computer.HostName; Hours = $state.Hours; FakeModule = $script:fakeADModule; RemoteAccessScript = $script:RemoteAccessScript }
        Start-BackgroundAction $script:winrmEnableScript $parameters 150 {
            param($output, $failure, $state)
            $computer = $state.Computer
            if (-not $failure) {
                Complete-WinRMEnable $computer
                Add-WinRMLease $computer @($output)[-1].Until $state.Title
                Open-WinRMClient $computer $state.OpenWith
                return
            }
            # A step can fail once WinRM is on already (#316: « The CancellationTokenSource has been disposed », from
            # PowerShell, after the task had turned it on), and a second click then worked. So WinRM is asked first:
            # when it answers, Repère goes on, as that click would; otherwise it says why turning it on failed.
            $state.Failure = $failure
            $parameters = @{ HostName = $computer.HostName; FakeModule = $script:fakeADModule; RemoteAccessScript = $script:RemoteAccessScript }
            Start-BackgroundAction $script:winrmAnswerScript $parameters 30 {
                param($answer, $answerFailure, $state)
                $computer = $state.Computer
                Complete-WinRMEnable $computer
                if ($answerFailure -or -not ($answer -and [bool]@($answer)[-1])) {
                    Show-ActionReport @((Tr "✖ {0} : WinRM non activé ({1})") -f $computer.ComputerName, (Get-RemoteFailureReason $state.Failure)) -Title $state.Title
                    return
                }
                Write-Host "Activer WinRM ($($computer.HostName)) : $($state.Failure), mais WinRM répond."
                # When the computer puts it back on its own isn't known: the task that does it says so, not the failure.
                Add-WinRMLease $computer $null $state.Title
                Open-WinRMClient $computer $state.OpenWith
            } $state
        } $state
    }
}

# The computers where WinRM is being turned on, for the pointer: it says something runs until the last one is done.
$script:WinRMEnabling = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Complete-WinRMEnable($Computer) {
    # Turning WinRM on is over there: its notice goes, and the pointer once no other computer is left.
    $null = $script:WinRMEnabling.Remove($Computer.HostName)
    if ($script:WinRMEnabling.Count) { return }
    Hide-ActionNotice
    if (-not $script:SpecsChecks.Count) { $script:win.ClearValue([System.Windows.FrameworkElement]::CursorProperty) }
}

function Add-WinRMLease($Computer, $Until, [string]$Title) {
    # WinRM turned on by Repère: put back once what uses it there is done. Turned on twice at once (two clicks before it
    # answered): one lease, with both.
    if ($script:WinRMLeases.ContainsKey($Computer.HostName)) { return }
    $script:WinRMLeases[$Computer.HostName] = @{ Computer = $Computer; Holders = [System.Collections.Generic.List[object]]::new(); Until = $Until; Title = $Title }
}

function Open-WinRMClient($Computer, [string]$OpenWith) {
    # What Request-TemporaryWinRM asked WinRM for, now that it's on (or without it, over DCOM).
    if ($OpenWith -eq 'Specs') { Open-SpecsWindow $Computer }
    else { Open-RemoteTerminal $Computer }
}

# Caractéristiques, before its window opens: whether the computer can be read, in a few seconds when it can't. Its name
# in the DNS, then WinRM's port and DCOM's (RPC, 135) at once, 2 s at most; when one answers, a CIM session through it
# and one small reading, which says whether this account may read the computer. Returns State: Ready (over WinRM, or
# over DCOM when WinRM's port answers but WinRM doesn't), NoWinRM (WinRM's port is closed, DCOM reads: Repère can turn
# WinRM on), Failed with WinRMError and DcomError (Windows' messages; WinRMError $null when its port is closed), Offline
# with Ping (neither port answers; whether ping does), or NoDns.
$specsCheckScript = {
    param([string]$HostName, [string]$FakeModule)
    if ($FakeModule) { Import-Module $FakeModule }
    if ($HostName -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        try { $null = Resolve-DnsName -Name $HostName -QuickTimeout -ErrorAction Stop }
        catch { return [pscustomobject]@{ State = 'NoDns' } }
    }
    # The fake AD answers for its computers.
    $open = @()
    if (Get-Command Test-ComputerPort -ErrorAction SilentlyContinue) { $open = @(foreach ($port in 5985, 135) { if (Test-ComputerPort $HostName @($port) 2000) { $port } }) }
    else {
        $attempts = foreach ($port in 5985, 135) {
            $client = [System.Net.Sockets.TcpClient]::new()
            @{ Port = $port; Client = $client; Task = $client.ConnectAsync($HostName, $port) }
        }
        try {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($true) {
                # Once WinRM's port answers, DCOM's isn't waited for.
                $pending = @($attempts | Where-Object { -not $_.Task.IsCompleted })
                $left = 2000 - $watch.ElapsedMilliseconds
                if ($attempts[0].Task.Status -eq 'RanToCompletion' -or -not $pending.Count -or $left -le 0) { break }
                $null = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($pending | ForEach-Object { $_.Task }), [int]$left)
            }
            $open = @($attempts | Where-Object { $_.Task.Status -eq 'RanToCompletion' } | ForEach-Object { $_.Port })
        }
        finally { foreach ($attempt in $attempts) { $attempt.Client.Dispose() } }
    }
    if (-not $open.Count) {
        $ping = Test-Connection -TargetName $HostName -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction SilentlyContinue
        return [pscustomobject]@{ State = 'Offline'; Ping = [bool]$ping }
    }

    $read = {
        param([switch]$Dcom)
        $parameters = @{ ComputerName = $HostName; OperationTimeoutSec = 10; ErrorAction = 'Stop' }
        if ($Dcom) { $parameters.SessionOption = New-CimSessionOption -Protocol Dcom }
        $session = New-CimSession @parameters
        try { $null = Get-CimInstance -CimSession $session -ClassName Win32_OperatingSystem -OperationTimeoutSec 10 -ErrorAction Stop }
        finally { Remove-CimSession $session -ErrorAction SilentlyContinue }
    }
    $winrmError = $null
    if ($open -contains 5985) {
        try { & $read; return [pscustomobject]@{ State = 'Ready'; Protocol = 'WinRM' } }
        catch { $winrmError = $_.Exception.Message.Trim() }
    }
    # WinRM's port closed, or WinRM refused: DCOM, as the window would (whether 135 answered in time or not).
    try { & $read -Dcom }
    catch { return [pscustomobject]@{ State = 'Failed'; WinRMError = $winrmError; DcomError = $_.Exception.Message.Trim() } }
    if ($winrmError) { return [pscustomobject]@{ State = 'Ready'; Protocol = 'DCOM' } }
    [pscustomobject]@{ State = 'NoWinRM' }
}.ToString()

# The computers whose Caractéristiques are being checked, so a second click doesn't check them again.
$script:SpecsChecks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Start-SpecsCheck($Computer) {
    # Caractéristiques: its window opens once the computer answers and can be read. Until then, a toast says Repère is
    # reaching it (and the pointer that it's working); a computer that's off says so within a few seconds, and one
    # without WinRM offers to turn it on, as PowerShell à distance does. A window already open comes to the front at
    # once.
    if (Show-OpenSpecsWindow $Computer) { return }
    if (-not $script:SpecsChecks.Add($Computer.HostName)) { return }
    Show-ActionNotice (Tr 'Caractéristiques') ((Tr 'Connexion à {0}…') -f $Computer.ComputerName) -Persist
    $script:win.Cursor = [System.Windows.Input.Cursors]::AppStarting
    Start-BackgroundAction $script:specsCheckScript @{ HostName = $Computer.HostName; FakeModule = $script:fakeADModule } 30 {
        param($output, $failure, $computer)
        $null = $script:SpecsChecks.Remove($computer.HostName)
        if (-not $script:SpecsChecks.Count) {
            $script:win.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
            Hide-ActionNotice
        }
        $title = Tr 'Caractéristiques'
        $answer = if (-not $failure) { @($output)[-1] }
        $name = $computer.ComputerName
        # Why it can't be read. Off, or not in the DNS: a toast, which takes the place of « Connexion à… », as
        # Vérifier en ligne says it. Otherwise a warning rather than a failure report (nothing went wrong in Repère): a
        # heading, one short line, and Windows' own messages, when there are some, in a box that can be copied. Notice
        # and Details are read by key: some warnings have none, and strict mode refuses a missing key read as a property.
        $warning = Get-SpecsCheckWarning $name $answer $failure
        if ($warning -and $warning['Notice']) {
            Show-ActionNotice $title $warning.Notice
            return
        }
        if ($warning) {
            $details = $warning['Details']
            Show-Dialog -Title $title -Heading $warning.Heading -Message $warning.Message -Icon $warning.Icon -Tone 'warn' `
                -Details $details -DetailsLabel $(if ($details) { Tr 'Message de Windows' })
            return
        }
        if ($answer.State -eq 'Ready') {
            Open-SpecsWindow $computer
            return
        }
        $hours = 4
        if ($answer.State -eq 'Offline') {
            # It answers ping, but neither port answered in time: a firewall, or a slow network. Turning WinRM on goes
            # through DCOM, as Lire par DCOM does, so either may fail too; that failure is then reported.
            $message = Tr "Ni WinRM ni DCOM n'ont répondu : un pare-feu les bloque peut-être. Repère peut essayer d'activer WinRM pour cette lecture, ou de lire par DCOM. WinRM est remis comme avant à la fermeture de la fenêtre."
            Request-TemporaryWinRM $computer $title $message 'cpu' $hours 'Specs' (Tr 'Lire par DCOM') -Heading ((Tr '{0} répond au ping, mais pas à Repère') -f $name)
            return
        }
        $message = Tr "Repère peut l'activer pour cette lecture. Il est remis comme avant à la fermeture de la fenêtre."
        Request-TemporaryWinRM $computer $title $message 'cpu' $hours 'Specs' (Tr 'Lire par DCOM')
    } $Computer
}

function Get-SpecsCheckWarning([string]$Name, $Answer, [string]$Failure) {
    # What Caractéristiques says when the computer can't be read ($Answer from $specsCheckScript, or the background
    # action's $Failure): Notice, the toast's line, when it's only off, too slow or not in the DNS; otherwise Heading,
    # Message (one short line), Icon and Details (Windows' messages, or nothing). $null when it can be read, when WinRM
    # only needs turning on, or when it answers ping only (Repère then offers to turn WinRM on, or to read over DCOM).
    $cannotRead = (Tr 'Impossible de lire {0}') -f $Name
    if ($Failure -or -not $Answer) {
        $timedOut = (Tr 'pas de réponse après {0} secondes (ordinateur éteint ou injoignable ?)') -f 30
        if ($Failure -eq $timedOut) { return @{ Notice = (Tr '✖ {0} : {1}') -f $Name, $timedOut } }
        return @{ Heading = $cannotRead; Message = Tr "La vérification n'a pas abouti."; Icon = 'info'; Details = $(if ($Failure) { $Failure } else { Tr 'Erreur inattendue.' }) }
    }
    switch ($Answer.State) {
        'NoDns' { return @{ Notice = (Tr "✖ {0} : introuvable (son nom n'est pas dans le DNS)") -f $Name } }
        'Offline' {
            if ($Answer.Ping) { return $null }
            return @{ Notice = (Tr '✖ {0} : {1}') -f $Name, (Tr 'hors ligne (pas de réponse au ping, ni à WinRM ni à DCOM)') }
        }
        'Failed' {
            # Both messages, WinRM's first: its port closed says so.
            $winrm = if ($Answer.WinRMError) { $Answer.WinRMError } else { Tr 'le port 5985 ne répond pas' }
            $details = ((Tr 'WinRM : {0}') -f $winrm) + "`n" + ((Tr 'DCOM : {0}') -f $Answer.DcomError)
            if ("$($Answer.WinRMError) $($Answer.DcomError)" -match 'Accès refusé|Access is denied|0x80070005') {
                return @{ Heading = $cannotRead; Message = Tr "Accès refusé : il faut être administrateur de l'ordinateur."; Icon = 'lock'; Details = $details }
            }
            $message = if ($Answer.WinRMError) { Tr 'La connexion a échoué, par WinRM comme par DCOM.' } else { Tr 'WinRM est fermé, et la connexion par DCOM a échoué.' }
            return @{ Heading = $cannotRead; Message = $message; Icon = 'info'; Details = $details }
        }
    }
    $null
}

function Open-SpecsWindow($Computer) {
    # The window, once the computer answered; it keeps WinRM on while it's open when Repère turned it on there.
    Show-SpecsWindow $Computer $script:win $script:windowIcon $script:fakeADModule
    $lease = $script:WinRMLeases[$Computer.HostName]
    $window = $script:SpecsWindows["$($Computer.Domain)|$($Computer.OU)"]
    if (-not $lease -or -not $window) { return }
    if (-not $lease.Holders.Contains($window.Tag)) { $lease.Holders.Add($window.Tag) }
    Update-WinRMLease
}

function Open-RemoteTerminal($Computer) {
    # With the fake AD, nothing is started: the dialog shows the command, and closing it stands for closing the terminal.
    $title = Tr 'PowerShell à distance'
    $path = (Get-Process -Id $PID).Path
    $arguments = "-NoExit -Command `"Enter-PSSession -ComputerName $($Computer.HostName)`""
    $lease = $script:WinRMLeases[$Computer.HostName]
    $process = $null
    if ($useFakeAD) { Show-Dialog -Title $title -Message ((Tr "AD fictif : rien n'est lancé.") + "`n`n$path $arguments") }
    else {
        try { $process = Start-Process -FilePath $path -ArgumentList $arguments -PassThru -ErrorAction Stop }
        catch { Show-Dialog -Title $title -Icon 'xcircle' -Tone 'danger' -Message ((Tr 'Impossible de lancer {0} : {1}') -f $path, $_.Exception.Message) }
    }
    if (-not $lease) { return }
    if ($process) { $lease.Holders.Add($process) }
    Update-WinRMLease
}

function Test-WinRMHolderDone($Holder) {
    # A terminal that exited, or a Caractéristiques window that closed (its state, SpecsWindow.ps1).
    if ($Holder -is [System.Diagnostics.Process]) { return $Holder.HasExited }
    [bool]$Holder.Closed
}

function Update-WinRMLease {
    # The terminals and windows that closed are let go; WinRM is put back on a computer that has none left.
    foreach ($hostName in @($script:WinRMLeases.Keys)) {
        $lease = $script:WinRMLeases[$hostName]
        foreach ($holder in @($lease.Holders)) { if (Test-WinRMHolderDone $holder) { $null = $lease.Holders.Remove($holder) } }
        if ($lease.Holders.Count) { continue }
        $script:WinRMLeases.Remove($hostName)
        $parameters = @{ HostName = $hostName; FakeModule = $script:fakeADModule; RemoteAccessScript = $script:RemoteAccessScript }
        Start-BackgroundAction $script:winrmRestoreScript $parameters 90 {
            param($output, $failure, $lease)
            $name = $lease.Computer.ComputerName
            $line = if (-not $failure) { (Tr '✔ {0} : WinRM remis comme avant') -f $name }
                    elseif ($lease.Until) { (Tr "✖ {0} : WinRM pas encore remis comme avant ({1}). L'ordinateur le fera vers {2}, ou à son prochain démarrage.") -f $name, (Get-RemoteFailureReason $failure), $lease.Until.ToString('HH:mm') }
                    else { (Tr "✖ {0} : WinRM pas encore remis comme avant ({1}). L'ordinateur le fera de lui-même, au plus tard à son prochain démarrage.") -f $name, (Get-RemoteFailureReason $failure) }
            Show-ActionReport @($line) -Title $lease.Title
        } $lease
    }
    if ($script:WinRMLeases.Count) { $script:winrmTimer.Start() } else { $script:winrmTimer.Stop() }
}
$winrmTimer.Add_Tick({ Update-WinRMLease })

function Invoke-ComputerWrite([string]$Action, $Computers, $Value, [string]$Server) {
    # On a search runspace: the change, one computer at a time, each in its domain. Results, in their order: each one's
    # Problem ($null when it went well) and how many Children it held. $Server: the DC a Propriétés reads from (its
    # domain's PDC: Get-UserServer), for its one computer, so the window read again shows the change; when it doesn't
    # answer, any DC of the domain.
    @{ Results = @(foreach ($computer in $Computers) {
        $change = {
            param([string]$At)
            switch ($Action) {
                'Enable' { $null = Enable-ADAccount -Server $At -Identity $computer.OU -ErrorAction Stop; 0 }
                'Disable' { $null = Disable-ADAccount -Server $At -Identity $computer.OU -ErrorAction Stop; 0 }
                'Description' {
                    if ($Value) { $null = Set-ADComputer -Server $At -Identity $computer.OU -Description $Value -ErrorAction Stop }
                    else { $null = Set-ADComputer -Server $At -Identity $computer.OU -Clear Description -ErrorAction Stop }
                    0
                }
                'Move' {
                    # Checked first, as for a deletion: the protection forbids moves too, and is reported, never removed.
                    $object = Get-ADObject -Server $At -Identity $computer.OU -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop
                    if ($object.ProtectedFromAccidentalDeletion) { throw (Tr 'protégé contre la suppression accidentelle, non déplacé') }
                    $null = Move-ADObject -Server $At -Identity $computer.OU -TargetPath $Value -ErrorAction Stop
                    0
                }
                'Remove' { Remove-ComputerFromAD $computer.OU $At }
            }
        }
        try {
            $at = if ($Server) { $Server } else { $computer.Domain }
            $children = try { & $change $at }
                        catch {
                            if ($at -eq $computer.Domain -or -not (Test-ServerDown $_)) { throw }
                            & $change $computer.Domain
                        }
            @{ Problem = $null; Children = [int]$children }
        }
        catch { @{ Problem = $_.Exception.Message; Children = 0 } }
    }) }
}

function Start-ComputerWrite([string]$Action, $Computers, $Value, [string]$Title, [scriptblock]$Done, [string[]]$Lines, [string[]]$Outcome, [hashtable]$Detail) {
    # A change to many computers, in the background (Invoke-ComputerWrite): a slow DC doesn't freeze the window, and a
    # search that ends waits, as for a dialog, before replacing the rows it's changing. Then, on the window's thread,
    # & $Done $computer $result $Value for each that went well, which updates its row and gives its line of the report.
    # $Lines: lines the report starts with. $Outcome: the notice's heading when all went well (Show-ActionReport).
    # $Detail: the computer's Propriétés it was made from, which reads it again and says what it did
    # (Complete-ComputerDetailChange); made on the DC it reads from.
    $server = if ($Detail) { Get-UserServer @($Computers)[0].Domain }
    $script:search.Dialogs++
    try {
        Start-WindowRead -Kind "$Action $([guid]::NewGuid())" -Command 'Invoke-ComputerWrite' -Arguments @($Action, @(ConvertTo-ReadComputer $Computers), $Value, $server) `
            -Functions 'Remove-ComputerFromAD', 'Test-GroupRefusal', 'Test-SelfAccount', 'Get-DomainOfDN', 'Test-ServerDown' -Variables @{ ComputerNotLeaf = $script:ComputerNotLeaf; Self = $script:Self } `
            -Context @{ Computers = @($Computers); Value = $Value; Title = $Title; Done = $Done; Lines = $Lines; Outcome = $Outcome; Detail = $Detail } -OnDone {
            param($write, $read, $problem)
            $script:search.Dialogs--
            $answers = @(if ($read) { $read.Results })
            $report = @(if ($write.Lines) { $write.Lines }) + @(for ($i = 0; $i -lt $write.Computers.Count; $i++) {
                $computer = $write.Computers[$i]
                $why = if ($problem) { $problem } elseif ($i -ge $answers.Count) { Tr 'AD n''a rien renvoyé' } else { $answers[$i].Problem }
                if ($why) { (Tr '✖ {0} : {1}') -f $computer.ComputerName, $why }
                else { & $write.Done $computer $answers[$i] $write.Value }
            })
            Update-ChangedRow
            if ($write.Detail) { Complete-ComputerDetailChange $write.Detail $report $write.Title $write.Outcome }
            else { Show-ActionReport $report $write.Title -Outcome $write.Outcome }
        }
    }
    catch {
        $script:search.Dialogs--
        throw
    }
}

function Set-ComputerEnabled($Computers, [bool]$Enabled, [hashtable]$Detail) {
    # Enables or disables each computer in its domain, then updates its row (Compte column). $Detail: from its
    # Propriétés (Start-ComputerWrite).
    Start-ComputerWrite $(if ($Enabled) { 'Enable' } else { 'Disable' }) $Computers $Enabled $(if ($Enabled) { Tr 'Activer' } else { Tr 'Désactiver' }) {
        param($computer, $result, $value)
        Set-RowState $computer $value
        "✔ $($computer.ComputerName)"
    } -Outcome $(if ($Enabled) { (Tr 'Activé'), (Tr 'Activés') } else { (Tr 'Désactivé'), (Tr 'Désactivés') }) -Detail $Detail
}

function Request-ComputerDisable($Computers, [hashtable]$Detail) {
    # Désactiver…: the enabled ones, after the guard (never a domain controller nor this computer) and a confirmation,
    # Annuler the default: reversible, but it cuts the computer off the domain. Over its Propriétés, from there ($Detail).
    $owner = if ($Detail) { $Detail.Window }
    Start-ComputerGuard (Tr 'Désactiver') 'ban' @($Computers | Where-Object { $_.IsOn }) -Owner $owner -Context $Detail {
        param($selected, $skipped, $contents, $detail)
        $names = @($selected | ForEach-Object { $_.ComputerName })
        $heading = if ($names.Count -eq 1) { (Tr 'Désactiver {0} ?') -f $names[0] } else { (Tr 'Désactiver {0} ordinateurs ?') -f $names.Count }
        $message = (Tr "Un ordinateur désactivé ne peut plus s'authentifier au domaine : les utilisateurs du domaine ne peuvent plus s'y connecter. On peut le réactiver ensuite (Activer).") + (Get-ComputerGuardNote $skipped)
        Show-Dialog -Title (Tr 'Désactiver') -Heading $heading -Names $(if ($names.Count -gt 1) { $names }) -Message $message -Icon 'ban' -Tone 'danger' -OkText (Tr 'Désactiver') -CancelIsDefault `
            -Owner $(if ($detail) { $detail.Window }) -State @{ Selected = $selected; Detail = $detail } -OnOk {
            param($state)
            Set-ComputerEnabled $state.Selected $false $state.Detail
        }
    }
}

function Request-ComputerMove($Computers, [hashtable]$Detail) {
    # Déplacer vers…: one domain at a time, as AD only moves a computer within its own domain. Never a domain controller
    # (out of Domain Controllers, its policy no longer applies) nor the computer Repère runs on. Over its Propriétés,
    # from there ($Detail).
    $owner = if ($Detail) { $Detail.Window }
    Start-ComputerGuard (Tr 'Déplacer') 'move' $Computers -Owner $owner -Context $Detail {
        param($selected, $skipped, $contents, $detail)
        $domains = @($selected | ForEach-Object { $_.Domain } | Select-Object -Unique)
        if ($domains.Count -gt 1) {
            Show-Dialog -Title (Tr 'Déplacer') -Icon 'move' -Tone 'warn' -Message ((Tr 'Les ordinateurs sélectionnés sont dans {0} domaines ({1}). Un ordinateur ne se déplace que dans son domaine : déplacez-les un domaine à la fois.') -f $domains.Count, ($domains -join ', '))
            return
        }
        Show-MoveDialog $selected $skipped $detail
    }
}

function Show-ComputerDescriptionDialog($Computers, [hashtable]$Detail) {
    # Modifier la description: one computer's, its own text to change, or several at once, replaced by the same. Over
    # its Propriétés, from there ($Detail).
    $names = @($Computers | ForEach-Object { $_.ComputerName })
    if ($names.Count -eq 1) {
        $heading = (Tr 'Description de {0}') -f $names[0]
        $message = ''
        $text = $Computers[0].Description
        $readAs = (Tr 'Description de {0} :') -f $names[0]
    }
    else {
        $heading = (Tr 'Description de {0} ordinateurs') -f $names.Count
        $message = Tr 'Leur description sera remplacée par celle-ci. Vide pour l''effacer.'
        $text = ''
        $readAs = ((Tr 'La description de ces {0} ordinateurs sera remplacée :') -f $names.Count) + "`n" + (Format-ComputerList $names)
    }
    Show-Dialog -Title (Tr 'Modifier la description') -Heading $heading -Names $(if ($names.Count -gt 1) { $names }) -Message $message -MessageName $readAs -Icon 'pencil' -WithTextBox -Text $text -OkText (Tr 'Enregistrer') `
        -Owner $(if ($Detail) { $Detail.Window }) -State @{ Selected = $Computers; Detail = $Detail } -OnOk {
        param($state)
        # An empty description clears it.
        $description = "$($state.TextBox.Text)".Trim()
        Start-ComputerWrite 'Description' $state.Selected $description (Tr 'Modifier la description') {
            param($computer, $result, $value)
            Set-RowDescription $computer $value
            "✔ $($computer.ComputerName)"
        } -Outcome (Tr 'Description modifiée'), (Tr 'Descriptions modifiées') -Detail $state.Detail
    }
}

# Déplacer vers…: the OUs of each domain, looked up in the background the first time they're needed and kept for the
# session, by domain: DomainDN, Computers (the default computers container), OUs (Name, DistinguishedName).
$ouCache = @{}

# Looks up a domain's OUs and its default computers container, in a background runspace. Returns them, or Error.
$ouLoadScript = {
    param([string]$Domain)
    try {
        $domainInfo = Get-ADDomain -Server $Domain -ErrorAction Stop
        [pscustomobject]@{
            DomainDN  = [string]$domainInfo.DistinguishedName
            Computers = [string]$domainInfo.ComputersContainer
            OUs       = @(Get-ADOrganizationalUnit -Server $Domain -Filter * -ErrorAction Stop | Select-Object Name, DistinguishedName)
            Error     = $null
        }
    }
    catch {
        [pscustomobject]@{ Error = $_.Exception.Message }
    }
}.ToString()

# The move dialog's window. Names double as UI Automation ids.
$moveDialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Déplacer vers…" Width="540" Height="580" MinWidth="440" MinHeight="420" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="{DynamicResource R.Bg}" Foreground="{DynamicResource R.Text}">
  <Grid Margin="20,6,20,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <!-- Like the other dialogs: an icon, what's moved and where from. The heading reads as the whole message for UI
         Automation (move_message). -->
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Width="36" Height="36" CornerRadius="8" VerticalAlignment="Top" Margin="0,0,14,0" Background="{DynamicResource R.Selection}" TextElement.Foreground="{DynamicResource R.AccentText}">
        <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:move:18}}</Grid>
      </Border>
      <StackPanel Grid.Column="1">
        <TextBlock x:Name="move_message" FontSize="15" FontWeight="{DynamicResource R.FontWeightStrong}" TextWrapping="Wrap"/>
        <TextBlock x:Name="move_from" Style="{StaticResource Txt.Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
        <WrapPanel x:Name="move_names" Margin="0,10,0,0" Visibility="Collapsed"/>
        <!-- Chercher dans une OU, with several domains: the domain whose OUs are shown. -->
        <ComboBox x:Name="move_domain" MinWidth="200" Margin="0,10,0,0" HorizontalAlignment="Left" ItemContainerStyle="{StaticResource Combo.Item}"
                  AutomationProperties.Name="Domaine" Visibility="Collapsed"/>
      </StackPanel>
    </Grid>
    <Border Grid.Row="1" Style="{StaticResource Field}" Height="34" Margin="0,14,0,8">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
        <TextBox x:Name="move_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les OU" AutomationProperties.Name="Filtrer les OU"/>
      </Grid>
    </Border>
    <Border Grid.Row="2" Style="{StaticResource Card}" Padding="4">
      <Grid>
        <TreeView x:Name="move_tree" Background="Transparent" BorderThickness="0"/>
        <TextBlock x:Name="move_status" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center"
                   TextWrapping="Wrap" TextAlignment="Center" Margin="16" Text="Chargement des OU…"/>
      </Grid>
    </Border>
    <!-- The destination, highlighted once chosen (Set-MoveTarget). It reads as « Destination : domain/OU » for UI
         Automation. -->
    <Border x:Name="move_target_box" Grid.Row="3" Margin="0,10,0,0" Padding="12,9" CornerRadius="8" BorderThickness="1"
            Background="{DynamicResource R.Surface}" BorderBrush="{DynamicResource R.Border}">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border x:Name="move_target_icon" Margin="0,0,10,0" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:folder}}</Border>
        <TextBlock x:Name="move_target" Grid.Column="1" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" TextWrapping="Wrap" Text="Choisissez l'OU de destination."/>
      </Grid>
    </Border>
    <Grid x:Name="move_note" Grid.Row="4" Margin="2,10,0,0" TextElement.Foreground="{DynamicResource R.Faint}">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Margin="0,1,8,0" VerticalAlignment="Top">{{icon:info:14}}</Border>
      <TextBlock Grid.Column="1" FontSize="12" TextWrapping="Wrap" Text="Les stratégies de groupe appliquées à un ordinateur changent avec son OU."/>
    </Grid>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="move_ok" Style="{StaticResource Btn.Primary}" Content="Déplacer" MinWidth="100" IsDefault="True" IsEnabled="False"/>
      <Button x:Name="move_cancel" Content="Annuler" MinWidth="90" Margin="8,0,0,0" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

# The move dialog while it's open: its window and tree, the computers, their domain, their OU when they share one
# (CurrentDN), the destination chosen (Target), the tree's items by DN, and the lookup of the domain's OUs (Job).
# Pick: the same dialog as Chercher dans une OU (Show-OuPicker), for the Recherche avancée: no computers, every OU
# offered, and the OU searched now as CurrentDN.
$move = @{ Current = $null }

function Set-MoveTarget($Dialog, [string]$Text, [string]$ReadAs, [bool]$Chosen) {
    # The destination strip: the accent's colors once an OU is chosen. It reads as $ReadAs (« Destination :
    # domain/OU ») for UI Automation.
    $box = $Dialog.FindName('move_target')
    $box.Text = $Text
    [System.Windows.Automation.AutomationProperties]::SetName($box, $ReadAs)
    $strip = $Dialog.FindName('move_target_box')
    $strip.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $(if ($Chosen) { 'R.Selection' } else { 'R.Surface' }))
    $strip.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, $(if ($Chosen) { 'R.Selection' } else { 'R.Border' }))
    $box.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($Chosen) { 'R.Text' } else { 'R.Muted' }))
    if ($Chosen) { $box.SetResourceReference([System.Windows.Controls.TextBlock]::FontWeightProperty, 'R.FontWeightStrong') }
    else { $box.SetResourceReference([System.Windows.Controls.TextBlock]::FontWeightProperty, 'R.FontWeight') }
    $Dialog.FindName('move_target_icon').SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, $(if ($Chosen) { 'R.AccentText' } else { 'R.Muted' }))
}

function Get-ParentDN([string]$DistinguishedName) {
    # CN=ORD-01,OU=Postes,DC=demo,DC=local -> OU=Postes,DC=demo,DC=local. A comma escaped in a name is kept.
    $parts = $DistinguishedName -split '(?<!\\),', 2
    if ($parts.Count -gt 1) { $parts[1] } else { '' }
}

function Test-UnderDN([string]$DistinguishedName, [string]$Root) {
    $DistinguishedName -eq $Root -or $DistinguishedName.EndsWith(",$Root", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-MoveTarget([string]$Domain, [switch]$All) {
    # The destinations offered in a domain: its OUs and default computers container, except Domain Controllers (never
    # a place for a workstation). With -MoveRoots (or the OUs chosen in Paramètres), only those roots and what's under
    # them, unless -All (Paramètres lists them all to choose from). Each domain has its own: by the DN's domain, as the
    # DN of an OU of a child domain ends like its parent's.
    $info = $script:ouCache[$Domain]
    $hidden = "OU=Domain Controllers,$($info.DomainDN)"
    $domainName = Get-DomainOfDN $info.DomainDN
    $roots = @(if (-not $All) { foreach ($root in $script:moveRootList) { if ((Get-DomainOfDN $root) -eq $domainName) { $root } } })
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($ou in $info.OUs) { $targets.Add([pscustomobject]@{ Name = [string]$ou.Name; DN = [string]$ou.DistinguishedName }) }
    if ($info.Computers -and -not ($targets | Where-Object DN -eq $info.Computers)) {
        $targets.Add([pscustomobject]@{ Name = (($info.Computers -split '(?<!\\),')[0] -replace '^\w+=', ''); DN = $info.Computers })
    }
    foreach ($target in $targets) {
        if (Test-UnderDN $target.DN $hidden) { continue }
        if ($roots.Count -and -not @(foreach ($root in $roots) { if (Test-UnderDN $target.DN $root) { $root } }).Count) { continue }
        $target
    }
}

function Update-OuTree {
    # Fills the tree once the domain's OUs are known: each OU under its parent (at the top when its parent isn't
    # offered), sorted by name, opened down to the computers' current OU, which is marked « (actuel) ».
    $state = $script:move.Current
    $targets = @(Get-MoveTarget $state.Domain -All:$state.Pick)
    $items = @{}
    foreach ($target in $targets) {
        $item = [System.Windows.Controls.TreeViewItem]::new()
        $item.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Tree.Item')
        $item.Header = if ($target.DN -eq $state.CurrentDN) { (Tr '{0} (actuel)') -f $target.Name } else { $target.Name }
        $item.Tag = $target.DN
        # Set on each item: the current OU's bold would otherwise pass to the OUs under it.
        $item.SetResourceReference([System.Windows.Controls.Control]::FontWeightProperty, $(if ($target.DN -eq $state.CurrentDN) { 'R.FontWeightStrong' } else { 'R.FontWeight' }))
        [System.Windows.Automation.AutomationProperties]::SetName($item, $item.Header)
        $items[$target.DN] = $item
    }
    $state.Tree.Items.Clear()
    foreach ($target in ($targets | Sort-Object Name)) {
        $parent = $items[(Get-ParentDN $target.DN)]
        if ($parent) { $parent.Items.Add($items[$target.DN]) | Out-Null } else { $state.Tree.Items.Add($items[$target.DN]) | Out-Null }
    }
    $state.Items = $items
    # No current OU (computers from several OUs): nothing to show (a $null key fails, strict mode or not).
    $current = if ($state.CurrentDN) { $items[$state.CurrentDN] }
    if ($current) {
        for ($parent = $current.Parent; $parent -is [System.Windows.Controls.TreeViewItem]; $parent = $parent.Parent) { $parent.IsExpanded = $true }
        $null = $state.Dialog.Dispatcher.BeginInvoke([Action]{ $script:move.Current.Items[$script:move.Current.CurrentDN].BringIntoView() }, [System.Windows.Threading.DispatcherPriority]::Loaded)
    }
    $state.Status.Visibility = if ($targets.Count) { 'Collapsed' } else { 'Visible' }
    if (-not $targets.Count) { $state.Status.Text = Tr 'Aucune OU à proposer dans ce domaine.' }
}

# Whether each OU was open before a filter opened or closed it. Weak: a tree built again leaves nothing behind.
$script:ouOpenBeforeFilter = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()

function Test-OuSelectedWithin($Item) {
    foreach ($child in $Item.Items) { if ($child.IsSelected -or (Test-OuSelectedWithin $child)) { return $true } }
    $false
}

function Set-OuFilter($Items, [string]$Text) {
    # Shows the OUs whose name contains the text, and their parents, opened. Returns whether any of them matched. By the
    # name each item reads as: the header of Paramètres' tree is a check box. Each item remembers whether it was open, for
    # when the text is erased. The OU selected is the destination, and closing a branch around it selects the branch: an
    # OU the filter hides is unselected first (children before parents), and erasing the text leaves its parents open.
    $any = $false
    foreach ($item in $Items) {
        $childMatch = Set-OuFilter $item.Items $Text
        $match = -not $Text -or ([System.Windows.Automation.AutomationProperties]::GetName($item)).IndexOf($Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        $item.Visibility = if ($match -or $childMatch) { 'Visible' } else { 'Collapsed' }
        if ($item.IsSelected -and -not ($match -or $childMatch)) { $item.IsSelected = $false }
        $open = $null
        $remembered = $script:ouOpenBeforeFilter.TryGetValue($item, [ref]$open)
        if ($Text) {
            if (-not $remembered) { $script:ouOpenBeforeFilter.Add($item, $item.IsExpanded) }
            $item.IsExpanded = $childMatch
        }
        elseif ($remembered) {
            $item.IsExpanded = $open -or (Test-OuSelectedWithin $item)
            $null = $script:ouOpenBeforeFilter.Remove($item)
        }
        if ($match -or $childMatch) { $any = $true }
    }
    $any
}

function Update-OuLoad {
    # On each tick of the dialog's timer: starts the lookup of the domain's OUs once the runspaces are ready, then fills
    # the tree, or shows the error.
    $state = $script:move.Current
    if (-not $state) { return }
    if (-not $state.Job) {
        if ($script:searchPool.RunspacePoolStateInfo.State -ne 'Opened') { return }
        $shell = [powershell]::Create()
        $shell.RunspacePool = $script:searchPool
        $null = $shell.AddScript($script:ouLoadScript).AddParameter('Domain', $state.Domain)
        $state.Job = @{ Shell = $shell; Handle = $shell.BeginInvoke(); Done = $false }
        return
    }
    if ($state.Job.Done -or -not $state.Job.Handle.IsCompleted) { return }
    $state.Timer.Stop()
    try { $answer = @($state.Job.Shell.EndInvoke($state.Job.Handle))[0] }
    catch { $answer = [pscustomobject]@{ Error = $_.Exception.Message } }
    finally {
        $state.Job.Shell.Dispose()
        $state.Job.Done = $true
    }
    if ($answer.Error) {
        $state.Status.Text = (Tr 'OU non lues : {0}') -f $answer.Error
        return
    }
    $script:ouCache[$state.Domain] = $answer
    Update-OuTree
}

function Stop-OuLoad($State) {
    # A lookup of OUs no longer wanted (another domain chosen, or the dialog closed before they came): disposed when
    # it's over, or stopped and left with the cancelled searches, which the next search disposes once they've ended
    # (Remove-StoppedJob: one stuck on a DC may only end on its own).
    $job = $State.Job
    $State.Job = $null
    if (-not $job -or $job.Done) { return }
    if ($job.Handle.IsCompleted) { $job.Shell.Dispose(); return }
    $null = $job.Shell.BeginStop($null, $null)
    $script:search.Stopping.Add($job)
}

function Show-MoveDialog($Computers, [string[]]$Skipped, [hashtable]$Detail) {
    # Asks where to move the computers (all in one domain), then moves them. $Skipped: those selected that it leaves
    # alone (Get-ComputerGuard), said under the heading. $Detail: a computer's Propriétés, which it opens over.
    $dialog = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:moveDialogXaml))
    $dialog.Owner = if ($Detail) { $Detail.Window } else { $script:win }
    $dialog.Icon = $script:windowIcon
    Set-WindowChrome $dialog
    $currentOUs = @($Computers | ForEach-Object { Get-ParentDN $_.OU } | Select-Object -Unique)
    $state = @{
        Dialog = $dialog; Tree = $dialog.FindName('move_tree'); Status = $dialog.FindName('move_status')
        Computers = $Computers; Domain = $Computers[0].Domain; Items = @{}; Target = $null; Job = $null; Pick = $false
        CurrentDN = if ($currentOUs.Count -eq 1) { $currentOUs[0] } else { $null }
    }
    $script:move.Current = $state
    # The heading, where they come from, and several computers as chips (their OU in the tooltip). The heading reads as
    # the whole message for UI Automation.
    $heading = $dialog.FindName('move_message')
    if ($Computers.Count -eq 1) {
        $heading.Text = (Tr 'Déplacer {0}') -f $Computers[0].ComputerName
        $dialog.FindName('move_from').Text = (Tr "Depuis {0} · {1}. Choisissez l'OU de destination.") -f $Computers[0].OUPath, $state.Domain
        $readAs = (Tr 'Déplacer {0} ({1}) vers :') -f $Computers[0].ComputerName, $Computers[0].ShortPath
    }
    else {
        $heading.Text = (Tr 'Déplacer {0} ordinateurs') -f $Computers.Count
        $dialog.FindName('move_from').Text = (Tr "De {0}. Choisissez l'OU de destination.") -f $state.Domain
        $readAs = ((Tr 'Déplacer ces {0} ordinateurs de {1} vers :') -f $Computers.Count, $state.Domain) + "`n" +
            (Format-ComputerList @($Computers | ForEach-Object { "$($_.ComputerName)   $($_.ShortPath)" }))
        $names = $dialog.FindName('move_names')
        foreach ($computer in @($Computers | Select-Object -First 15)) {
            $chip = [System.Windows.Markup.XamlReader]::Parse("<Border xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" Style=`"{StaticResource Pill.Key}`" Margin=`"0,0,6,6`"><TextBlock Text=`"$(ConvertTo-XamlValue $computer.ComputerName)`"/></Border>")
            $chip.ToolTip = $computer.OUPath
            $null = $names.Children.Add($chip)
        }
        $names.Visibility = 'Visible'
    }
    if ($Skipped.Count) {
        $from = $dialog.FindName('move_from')
        $from.Text += (Get-ComputerGuardNote $Skipped) -replace '^\s+', ' '
        $readAs += (Get-ComputerGuardNote $Skipped)
    }
    [System.Windows.Automation.AutomationProperties]::SetName($heading, $readAs)

    Initialize-OuDialog $state
    # While it's open, a search that ends waits before replacing the rows it acts on.
    $script:search.Dialogs++
    try { $confirmed = $dialog.ShowDialog() }
    finally {
        $script:search.Dialogs--
        $state.Timer.Stop()
        Stop-OuLoad $state
        $script:move.Current = $null
    }
    if ($confirmed -and $state.Target) { Move-Computer $Computers $state.Target $Detail }
}

function Show-OuPicker([string]$Domain, [string]$CurrentDN) {
    # Chercher dans une OU (the Recherche avancée's Choisir…): the OU where to search, in $Domain or, with several
    # domains, another chosen in the dialog. Returns the OU chosen (DN, Domain), or nothing.
    $dialog = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:moveDialogXaml))
    $dialog.Owner = $script:win
    $dialog.Icon = $script:windowIcon
    $dialog.Title = Tr 'Chercher dans une OU'
    Set-WindowChrome $dialog
    $state = @{
        Dialog = $dialog; Tree = $dialog.FindName('move_tree'); Status = $dialog.FindName('move_status')
        Computers = @(); Domain = $Domain; Items = @{}; Target = $null; Job = $null; Pick = $true; CurrentDN = $CurrentDN
    }
    $script:move.Current = $state
    $heading = $dialog.FindName('move_message')
    $heading.Text = Tr 'Chercher dans une OU'
    $dialog.FindName('move_from').Text = Tr "Choisissez l'OU : la recherche y prend aussi les OU qu'elle contient."
    $dialog.FindName('move_note').Visibility = 'Collapsed'
    $ok = $dialog.FindName('move_ok')
    $ok.Content = Tr 'Choisir'
    $choose = Tr "Choisissez l'OU où chercher."
    Set-MoveTarget $dialog $choose $choose $false
    if ($script:showDomains) {
        # Another domain: its OUs, from the cache or looked up, and nothing chosen.
        $domains = $dialog.FindName('move_domain')
        foreach ($name in $script:domainList) { $null = $domains.Items.Add($name) }
        $domains.SelectedItem = $Domain
        $domains.Visibility = 'Visible'
        $domains.Add_SelectionChanged({
            $state = $script:move.Current
            $state.Domain = [string]$state.Dialog.FindName('move_domain').SelectedItem
            $state.CurrentDN = $null
            Stop-OuLoad $state
            $state.Tree.Items.Clear()
            $state.Status.Text = Tr 'Chargement des OU…'
            $state.Status.Visibility = 'Visible'
            if ($script:ouCache.ContainsKey($state.Domain)) { Update-OuTree; $null = Set-OuFilter $state.Tree.Items "$($state.Dialog.FindName('move_filter').Text)".Trim() }
            else { $state.Timer.Start() }
        })
    }
    Initialize-OuDialog $state
    try { $confirmed = $dialog.ShowDialog() }
    finally {
        $state.Timer.Stop()
        Stop-OuLoad $state
        $script:move.Current = $null
    }
    if ($confirmed -and $state.Target) { @{ DN = $state.Target; Domain = $state.Domain } }
}

function Initialize-OuDialog($State) {
    # The OU tree's dialog, to move computers or to choose where to search: the destination follows the OU selected,
    # the filter box narrows the tree, and the domain's OUs come from the session's cache or are looked up in the
    # background while it shows.
    $State.Tree.Add_SelectedItemChanged({
        $state = $script:move.Current
        $item = $state.Tree.SelectedItem
        $state.Target = if ($item) { [string]$item.Tag }
        $ok = $state.Dialog.FindName('move_ok')
        if ($state.Pick) {
            $ok.IsEnabled = [bool]$state.Target
            if (-not $state.Target) {
                $choose = Tr "Choisissez l'OU où chercher."
                Set-MoveTarget $state.Dialog $choose $choose $false
                return
            }
            $where = Tr 'Chercher dans : {0}'
            Set-MoveTarget $state.Dialog ($where -f (Get-OUPath "CN=x,$($state.Target)")) ($where -f (Get-ShortPath "CN=x,$($state.Target)")) $true
            return
        }
        if (-not $state.Target) {
            $choose = Tr "Choisissez l'OU de destination."
            Set-MoveTarget $state.Dialog $choose $choose $false
            $ok.IsEnabled = $false
            return
        }
        $already = @($state.Computers | Where-Object { (Get-ParentDN $_.OU) -eq $state.Target }).Count
        $note = if ($already -eq $state.Computers.Count) { ' ' + (Tr '(ils y sont déjà)') } elseif ($already) { ' ' + ((Tr '({0} y sont déjà)') -f $already) }
        $destination = Tr 'Destination : {0}'
        Set-MoveTarget $state.Dialog (($destination -f (Get-OUPath "CN=x,$($state.Target)")) + $note) (($destination -f (Get-ShortPath "CN=x,$($state.Target)")) + $note) $true
        $ok.IsEnabled = $already -lt $state.Computers.Count
    })
    $State.Dialog.FindName('move_filter').Add_TextChanged({
        $state = $script:move.Current
        $null = Set-OuFilter $state.Tree.Items "$($state.Dialog.FindName('move_filter').Text)".Trim()
    })
    $State.Dialog.FindName('move_ok').Add_Click({ $script:move.Current.Dialog.DialogResult = $true })

    $State.Timer = [System.Windows.Threading.DispatcherTimer]::new()
    $State.Timer.Interval = [timespan]::FromMilliseconds(30)
    $State.Timer.Add_Tick({ Update-OuLoad })
    if ($script:ouCache.ContainsKey($State.Domain)) { Update-OuTree } else { $State.Timer.Start() }
}

function Set-RowLocation($Row, [string]$DistinguishedName) {
    Save-RowChange $Row.OU 'DistinguishedName' $DistinguishedName
    $Row.OU = $DistinguishedName
    $Row.ShortPath = Get-ShortPath $DistinguishedName
    $Row.OUPath = Get-OUPath $DistinguishedName
    Update-RowText $Row
}

function Move-Computer($Computers, [string]$Target, [hashtable]$Detail) {
    # Moves each computer to the OU, in its domain, then updates its row (Emplacement column). $Detail: from its
    # Propriétés (Start-ComputerWrite).
    $there = @($Computers | Where-Object { (Get-ParentDN $_.OU) -eq $Target } | ForEach-Object { (Tr '✔ {0} (déjà dans cette OU)') -f $_.ComputerName })
    $moving = @($Computers | Where-Object { (Get-ParentDN $_.OU) -ne $Target })
    # « Déplacé » only when one was: all already there, the notice keeps the action's name.
    Start-ComputerWrite 'Move' $moving $Target (Tr 'Déplacer') {
        param($computer, $result, $value)
        $from = $computer.ShortPath
        Set-RowLocation $computer "$(($computer.OU -split '(?<!\\),', 2)[0]),$value"
        (Tr '✔ {0} : {1} → {2}') -f $computer.ComputerName, $from, $computer.ShortPath
    } $there -Outcome $(if ($moving.Count) { (Tr 'Déplacé'), (Tr 'Déplacés') }) -Detail $Detail
}

$actions = @{}

$actions.Ping = {
    # In the En ligne column, row by row, while the window stays usable (Ctrl+A first checks every row shown).
    $selected = Get-SelectedComputer
    if (-not $selected.Count) { return }
    Start-OnlineCheck $selected
}

$actions.Specs = {
    # A window of its own, which reads the computer in the background: the main window stays usable. It opens once the
    # computer answers.
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-SpecsCheck $selected[0]
}

$actions.Rdp = {
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-RemoteTool (Tr 'Bureau à distance') 'mstsc.exe' "/v:$($selected[0].HostName)"
}

$actions.Shadow = {
    # The person's own session, rather than a new one: one computer at a time.
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-ShadowSession $selected[0] $fakeADModule
}

$actions.Sessions = {
    # Who's logged on, for each selected computer: only read, nothing is joined.
    $selected = Get-SelectedComputer
    if (-not $selected.Count) { return }
    Show-ConnectedUser $selected $fakeADModule
}

$actions.CompMgmt = {
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-RemoteTool (Tr "Gestion de l'ordinateur") 'compmgmt.msc' "/computer=$($selected[0].HostName)"
}

$actions.Pwsh = {
    # Needs WinRM on the computer, which Repère offers to turn on for the session. An error of Enter-PSSession itself
    # (access denied) shows in the terminal.
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-RemotePowerShell $selected[0]
}

$actions.Services = {
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-RemoteTool 'Services' 'services.msc' "/computer=$($selected[0].HostName)"
}

$actions.Events = {
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-RemoteTool (Tr "Observateur d'événements") 'eventvwr.exe' $selected[0].HostName
}

$actions.Gpupdate = {
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-PolicyUpdate $selected[0]
}

$actions.Restart = {
    # One computer at a time: restarting a whole selection by mistake would be costly.
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Invoke-ComputerRestart $selected[0] $win $windowIcon
}

$actions.RestartCancel = {
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Stop-ComputerRestart $selected[0]
}

$actions.CShare = {
    # Needs admin rights on the computer; if they're missing, Explorer shows its own error.
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Start-RemoteTool (Tr 'Ouvrir C$') 'explorer.exe' "\\$($selected[0].HostName)\c$"
}

$actions.Enable = {
    # Only the disabled ones; enabling is harmless, so there's no confirmation.
    $all = Get-SelectedComputer
    $selected = @($all | Where-Object { -not $_.IsOn })
    if (-not $selected.Count) { return }
    Set-ComputerEnabled $selected $true
}

$actions.Disable = {
    # Only the enabled ones (Request-ComputerDisable).
    Request-ComputerDisable @(Get-SelectedComputer)
}

$actions.BitLocker = {
    $selected = Get-SelectedComputer
    if (-not $selected.Count) { return }
    Show-BitLockerDialog $selected $win $windowIcon
}

$actions.Laps = {
    # Only shown, in its own window: nothing is saved or written to AD.
    $selected = Get-SelectedComputer
    if (-not $selected.Count) { return }
    Show-LapsDialog $selected $win $windowIcon
}

$actions.EditDescription = {
    $selected = Get-SelectedComputer
    if (-not $selected.Count) { return }
    Show-ComputerDescriptionDialog @($selected)
}

$actions.Properties = {
    # Propriétés…: what AD knows of one computer, in a window of its own (ComputerDetails.ps1).
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Show-ComputerDetail $selected[0] $win $windowIcon
}

$actions.Remove = {
    # What goes with them, read with the guard before asking, in the background (two queries per computer): the keys,
    # and any other object (the label says there's more).
    Start-ComputerGuard (Tr "Supprimer de l'AD") 'trash' (Get-SelectedComputer) -WithContents {
        param($selected, $skipped, $contents)
        if (-not $contents) {
            Show-ActionReport @($selected | ForEach-Object { (Tr '✖ {0} : {1}') -f $_.ComputerName, (Tr 'AD n''a rien renvoyé') }) (Tr "Supprimer de l'AD")
            return
        }
        $names = @($selected | ForEach-Object { $_.ComputerName })
        $heading = if ($names.Count -eq 1) { (Tr "Supprimer {0} de l'AD ?") -f $names[0] } else { (Tr "Supprimer {0} ordinateurs de l'AD ?") -f $names.Count }
        $message = (Tr "Les objets qu'un ordinateur contient (ex. : informations de récupération BitLocker) sont supprimés d'abord, puis l'ordinateur. Cette action est définitive.") + (Get-ComputerGuardNote $skipped)
        $label = if ($contents.Others) { Tr 'Supprimé avec eux : clés BitLocker (à copier avant au besoin) et autres objets' } else { Tr 'Clés BitLocker supprimées avec lui (à copier avant au besoin)' }
        $typed = if ($selected.Count -gt $script:TypeToConfirmAbove) { [string]$selected.Count }
        Show-Dialog -Title (Tr "Supprimer de l'AD") -Heading $heading -Names $(if ($names.Count -gt 1) { $names }) -Message $message -Icon 'trash' -Tone 'danger' `
            -Details $contents.Text -DetailsLabel $label -SecretDetails -OkText (Tr 'Supprimer') -CancelIsDefault -TypeToConfirm $typed -State @{ Selected = $selected } -OnOk {
            param($state)
            Start-ComputerWrite 'Remove' $state.Selected $null (Tr "Supprimer de l'AD") {
                param($computer, $result)
                $script:results.Rows.Remove($computer) | Out-Null
                Save-RowChange $computer.OU 'Removed' $true
                if ($result.Children -eq 1) { (Tr '✔ {0} (avec 1 objet enfant)') -f $computer.ComputerName }
                elseif ($result.Children -gt 1) { (Tr '✔ {0} (avec {1} objets enfants)') -f $computer.ComputerName, $result.Children }
                else { "✔ $($computer.ComputerName)" }
            } -Outcome (Tr 'Supprimé de l''AD'), (Tr 'Supprimés de l''AD')
        }
    }
}

$actions.Groups = {
    # One computer at a time; viewing only.
    $selected = Get-SelectedComputer
    if ($selected.Count -ne 1) { return }
    Show-GroupsDialog $selected[0] $win $windowIcon
}

# Many computers into or out of groups at once (SelectionGroups.ps1), from the right-click menu: the action bar has no
# room for them at the window's narrowest.
$actions.GroupsAdd = { Show-SelectionGroupAdd @(ConvertTo-GroupMember (Get-SelectedComputer) 'Computer') }
$actions.GroupsRemove = { Show-SelectionGroupRemove @(ConvertTo-GroupMember (Get-SelectedComputer) 'Computer') }

$actions.Move = { Request-ComputerMove @(Get-SelectedComputer) }

$actions.NextName = {
    # Prochain nom… (NextName.ps1) on the series of the computer selected: its name, which the window turns into a
    # format. With none or several, on the last format used. Its domain is the one ticked first, when it's one of those
    # offered (a row's can be a DC's name); otherwise the page's.
    $selected = Get-SelectedComputer
    $name = ''
    $domain = [string]$comboBoxDomain.SelectedItem
    if ($selected.Count -eq 1) {
        $name = [string]$selected[0].ComputerName
        if (@($script:domainList) -contains $selected[0].Domain) { $domain = [string]$selected[0].Domain }
    }
    Show-NextNameDialog $win $windowIcon -Name $name -PageDomain $domain
}

$actions.Copy = {
    # The names, one per line, to paste into a ticket or another tool.
    $names = @(Get-SelectedComputer | ForEach-Object { $_.ComputerName })
    if (-not $names.Count) { return }
    Set-Clipboard -Value ($names -join [Environment]::NewLine)
    $selectionText.Text = if ($names.Count -eq 1) { (Tr '{0} copié') -f $names[0] } else { (Tr '{0} noms copiés') -f $names.Count }
}

$actions.CopyOneLine = {
    # For a one-line field, where line breaks vanish and the names would run together.
    $names = @(Get-SelectedComputer | ForEach-Object { $_.ComputerName })
    if (-not $names.Count) { return }
    Set-Clipboard -Value ($names -join ', ')
    $selectionText.Text = if ($names.Count -eq 1) { (Tr '{0} copié') -f $names[0] } else { (Tr '{0} noms copiés') -f $names.Count }
}

$actions.CopyRows = {
    # The rows as Exporter writes them, a tab between the columns, to paste into Excel or a ticket.
    $selected = Get-SelectedComputer
    if (-not $selected.Count) { return }
    $lines = foreach ($line in @(Get-ComputerExportRow $selected)) { Format-RowLine @($line.PSObject.Properties | ForEach-Object { $_.Value }) }
    Set-Clipboard -Value (@($lines) -join [Environment]::NewLine)
    $selectionText.Text = if ($selected.Count -eq 1) { Tr '1 ligne copiée' } else { (Tr '{0} lignes copiées') -f $selected.Count }
}

$menuProperties.Add_Click($actions.Properties)
$menuEditDescription.Add_Click($actions.EditDescription)
$menuMove.Add_Click($actions.Move)
$menuGroupsItem.Add_Click($actions.Groups)
$menuGroupsAdd.Add_Click($actions.GroupsAdd)
$menuGroupsRemove.Add_Click($actions.GroupsRemove)
$menuNextName.Add_Click($actions.NextName)
$menuBitLocker.Add_Click($actions.BitLocker)
$menuLaps.Add_Click($actions.Laps)
$menuEnable.Add_Click($actions.Enable)
$menuDisable.Add_Click($actions.Disable)
$menuRemove.Add_Click($actions.Remove)
$menuPing.Add_Click($actions.Ping)
$menuSpecs.Add_Click($actions.Specs)
$menuRdp.Add_Click($actions.Rdp)
$menuShadow.Add_Click($actions.Shadow)
$menuSessions.Add_Click($actions.Sessions)
$menuCompMgmt.Add_Click($actions.CompMgmt)
$menuCShare.Add_Click($actions.CShare)
$menuPwsh.Add_Click($actions.Pwsh)
$menuServices.Add_Click($actions.Services)
$menuEvents.Add_Click($actions.Events)
$menuCopy.Add_Click($actions.Copy)
$menuCopyOneLine.Add_Click($actions.CopyOneLine)
$menuCopyRows.Add_Click($actions.CopyRows)
$menuGpupdate.Add_Click($actions.Gpupdate)
$menuRestart.Add_Click($actions.Restart)
$menuRestartCancel.Add_Click($actions.RestartCancel)

$actRdp.Add_Click($actions.Rdp)
$actShadow.Add_Click($actions.Shadow)
$actSessions.Add_Click($actions.Sessions)
$actCompMgmt.Add_Click($actions.CompMgmt)
$actCShare.Add_Click($actions.CShare)
$actPwsh.Add_Click($actions.Pwsh)
$actServices.Add_Click($actions.Services)
$actEvents.Add_Click($actions.Events)
$actGpupdate.Add_Click($actions.Gpupdate)
$actRestart.Add_Click($actions.Restart)
$actRestartCancel.Add_Click($actions.RestartCancel)
$actPing.Add_Click($actions.Ping)
$actSpecs.Add_Click($actions.Specs)
$actToggle.Add_Click({
    # Stored first: piping the function's output would pass the whole list as one item.
    $all = Get-SelectedComputer
    if (@($all | Where-Object { $_.IsOn }).Count) { & $actions.Disable } else { & $actions.Enable }
})
$actEdit.Add_Click($actions.EditDescription)
$actMove.Add_Click($actions.Move)
$actGroups.Add_Click($actions.Groups)
$actNextName.Add_Click($actions.NextName)
$actBitLocker.Add_Click($actions.BitLocker)
$actLaps.Add_Click($actions.Laps)
$actCopy.Add_Click($actions.Copy)

# In the results: Ctrl+C copies the names (rather than the grid's cells) and Ctrl+Maj+C the whole rows, F2 changes the
# description, Suppr asks to remove the computers, as their buttons do, and Alt+Entrée opens Propriétés (as in the
# Explorer).
$dataGrid.Add_PreviewKeyDown({
    $e = $args[1]
    if (Enter-GridByKey $dataGrid $e) { return }
    # ModifierKeys has its own converter: compared with its values, not with names.
    $modifiers = [System.Windows.Input.Keyboard]::Modifiers
    if ($e.Key -eq 'C' -and $modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        & $script:actions.Copy
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'C' -and $modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)) {
        & $script:actions.CopyRows
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'F2' -and $modifiers -eq [System.Windows.Input.ModifierKeys]::None) {
        & $script:actions.EditDescription
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'Delete' -and $modifiers -eq [System.Windows.Input.ModifierKeys]::None) {
        & $script:actions.Remove
        $e.Handled = $true
    }
    # With Alt, WPF says the key as System (only Alt or F10 make one), and which in SystemKey.
    elseif ($e.Key -eq 'System' -and $e.SystemKey -eq 'Return') {
        & $script:actions.Properties
        $e.Handled = $true
    }
})
# A double-click on a row opens its Caractéristiques, as one on a user or a group opens its Propriétés (one on a header
# has no row behind it).
$dataGrid.Add_MouseDoubleClick({
    param($grid, $e)
    $element = $e.OriginalSource
    while ($element -and $element -isnot [System.Windows.Controls.DataGridRow]) {
        $element = if ($element -is [System.Windows.Media.Visual]) { [System.Windows.Media.VisualTreeHelper]::GetParent($element) }
                   else { [System.Windows.LogicalTreeHelper]::GetParent($element) }
    }
    if ($element) { & $script:actions.Specs }
})
$actRemove.Add_Click($actions.Remove)

# The icon buttons' labels, when the whole bar fits beside the selection text with them (room kept for its longest,
# « 12 ordinateurs sélectionnés », so selecting doesn't make them come and go). Without them, the buttons are square.
# When even that doesn't fit, Vérifier en ligne, Caractéristiques and Désactiver lose theirs too and become square, their
# name in their tooltip. The window is never narrower than the bar with every button square and that text: in a wider
# font than Segoe UI (JetBrains Mono), more than its minimum width says.
$actionLabelButtons = @($actEdit, $actMove, $actGroups, $actNextName, $actBitLocker, $actLaps, $actCopy, $actRemove)
$actionTextButtons = @(
    @{ Button = $actPing; Label = $root.FindName('act_ping_label'); Tip = $actPing.ToolTip }
    @{ Button = $actSpecs; Label = $root.FindName('act_specs_label'); Tip = $actSpecs.ToolTip }
    @{ Button = $actToggle; Label = $actToggleText; Tip = $null }
)
$actionLabels = @{ Level = $null; Pending = $false }
function Set-ActionLabel([int]$Level) {
    # 2: every button labelled. 1: the icon buttons square. 0: Vérifier en ligne, Caractéristiques and Désactiver too.
    $Shown = $Level -eq 2
    foreach ($button in $actionLabelButtons) {
        $root.FindName("$($button.Name)_label").Visibility = ConvertTo-Visibility $Shown
        if ($Shown) {
            $button.Width = [double]::NaN
            $button.Padding = [System.Windows.Thickness]::new(12, 0, 12, 0)
        }
        else {
            $button.ClearValue([System.Windows.FrameworkElement]::WidthProperty)
            $button.ClearValue([System.Windows.Controls.Control]::PaddingProperty)
        }
    }
    $square = $Level -eq 0
    foreach ($text in $actionTextButtons) {
        $button = $text.Button
        $text.Label.Visibility = ConvertTo-Visibility (-not $square)
        if ($square) {
            # As wide as the icon buttons (Btn.Icon). Its name above what its tooltip said; Désactiver's follows it as it
            # becomes Activer.
            $button.Width = 34
            $button.Padding = [System.Windows.Thickness]::new(0)
            if ($text.Tip) { $button.ToolTip = "$($text.Label.Text)`n$($text.Tip)" }
            else {
                $binding = [System.Windows.Data.Binding]::new('Text')
                $binding.Source = $text.Label
                $null = $button.SetBinding([System.Windows.FrameworkElement]::ToolTipProperty, $binding)
            }
        }
        else {
            $button.ClearValue([System.Windows.FrameworkElement]::WidthProperty)
            $button.ClearValue([System.Windows.Controls.Control]::PaddingProperty)
            if ($text.Tip) { $button.ToolTip = $text.Tip }
            else { $button.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty) }
        }
    }
}
function Update-ActionLabel {
    $row = $root.FindName('action_row')
    $bar = $root.FindName('action_bar')
    if (-not $row.ActualWidth) { return }
    $actionLabels.Pending = $false
    $unbounded = [System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity)
    # The selection text's longest, in the font shown, then what it says again.
    $said = $selectionText.Text
    $selectionText.Text = (Tr '{0} ordinateurs sélectionnés') -f 12
    $selectionText.Measure($unbounded)
    $textWidth = $selectionText.DesiredSize.Width + 16
    $selectionText.Text = $said
    Set-ActionLabel 0
    $bar.Measure($unbounded)
    $narrow = $bar.DesiredSize.Width
    # The most labels that fit.
    $level = 2
    while ($level) {
        Set-ActionLabel $level
        $bar.Measure($unbounded)
        if ($bar.DesiredSize.Width + $textWidth -le $row.ActualWidth) { break }
        $level--
    }
    if (-not $level) { Set-ActionLabel 0 }
    $actionLabels.Level = $level
    # The window's width for the row's: what's around the row stays, the row needs the bar with every button square and
    # the text (both scaled with the text size, as the row is).
    $scale = $script:Appearance.TextScale
    Set-WindowContentWidth $win ([Math]::Ceiling($win.ActualWidth + ($narrow + $textWidth - $row.ActualWidth) * $scale))
}
$win.Add_SizeChanged({ Update-ActionLabel })
$win.Add_ContentRendered({ Update-ActionLabel })
# Another font or text size (Paramètres) changes the bar's width, not the window's: measured again once it's drawn.
$root.FindName('action_bar').Add_SizeChanged({
    if ($actionLabels.Pending) { return }
    $actionLabels.Pending = $true
    $null = $win.Dispatcher.BeginInvoke([Action]{ Update-ActionLabel }, [System.Windows.Threading.DispatcherPriority]::Background)
})

# A right click selects the row under the pointer first (unless it's already selected), so the menu acts on it.
$dataGrid.Add_PreviewMouseRightButtonDown({
    param($grid, $e)
    $element = $e.OriginalSource
    while ($element -and $element -isnot [System.Windows.Controls.DataGridRow]) {
        $element = if ($element -is [System.Windows.Media.Visual]) { [System.Windows.Media.VisualTreeHelper]::GetParent($element) }
                   else { [System.Windows.LogicalTreeHelper]::GetParent($element) }
    }
    if ($element -and -not $element.IsSelected) {
        $grid.SelectedItems.Clear()
        $element.IsSelected = $true
    }
})

Update-MenuItem
$dataGrid.Add_SelectionChanged({ Update-MenuItem })
Initialize-GridText $dataGrid
