# Ajouter à un groupe… and Retirer d'un groupe… for the rows selected on the Utilisateurs and Ordinateurs pages: many
# users or computers into, or out of, several groups at once, rather than one Propriétés at a time. Adding uses the
# group picker of a user's Propriétés (New-GroupPickerContent); removing offers the groups at least one of them is a
# direct member of. Their groups are read in batches (Read-SelectionMemberOf), then one AD call per group, and a line per
# object and group (Show-ActionReport). Dot-sourced by the main script after UserDetails.ps1 (the picker),
# GroupsDialog.ps1 (Get-DomainOfDN) and SearchPage.ps1 (Get-LdapText).
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

function ConvertTo-GroupMember($Rows, [string]$Kind) {
    # The rows selected, as the group changes take them: Label (the login, or the computer's name, in the report), Name
    # (in a heading), Domain, DistinguishedName, Kind ('User' or 'Computer'), and the Row.
    foreach ($row in $Rows) {
        if ($Kind -eq 'Computer') { @{ Label = $row.ComputerName; Name = $row.ComputerName; Domain = $row.Domain; DistinguishedName = $row.DistinguishedName; Kind = $Kind; Row = $row } }
        else { @{ Label = $row.Login; Name = $row.Name; Domain = $row.Domain; DistinguishedName = $row.DistinguishedName; Kind = $Kind; Row = $row } }
    }
}

function Get-GroupMemberObject($Member, [string]$Server, [hashtable]$Read) {
    # What the DC of a group's domain ($Server) takes for $Member (Domain, DistinguishedName, Kind: User, Computer, Group,
    # or none when unknown): its DN when it's of that domain; otherwise the account as read in its own (once, kept in
    # $Read), since a DC can't find another domain's account by DN. Read with its class's cmdlet, which brings the SID AD
    # names it by; of another class (a contact, with no SID), it can't be given: said. Also used by a group's Propriétés
    # (Remove-GroupMemberList).
    if (-not $Server -or $Server -eq $Member.Domain) { return $Member.DistinguishedName }
    if (-not $Read.ContainsKey($Member.DistinguishedName)) {
        $at = @{ Server = $Member.Domain; Identity = $Member.DistinguishedName; ErrorAction = 'Stop' }
        $kind = $Member.Kind
        if ($kind -notin 'User', 'Computer', 'Group') {
            # Listed by its DN only: its class first.
            $class = [string](Get-ADObject @at).ObjectClass
            $kind = switch ($class) { { $_ -in 'user', 'inetOrgPerson' } { 'User' } 'computer' { 'Computer' } 'group' { 'Group' } }
            if (-not $kind) { throw ((Tr "objet {0} d'un autre domaine : seuls les utilisateurs, les ordinateurs et les groupes sont pris en charge") -f $class) }
        }
        $Read[$Member.DistinguishedName] = switch ($kind) {
            'Computer' { Get-ADComputer @at }
            'User' { Get-ADUser @at }
            'Group' { Get-ADGroup @at }
        }
    }
    $Read[$Member.DistinguishedName]
}

function Read-SelectionAccount($Members, [hashtable]$Read) {
    # The accounts going into a group of another domain, read in their own (Get-GroupMemberObject takes them from
    # $Read): one search per domain and kind, by their DNs, 100 at a time, rather than one by one. One a search doesn't
    # return is read alone when it's needed, and said then if it can't be.
    foreach ($batch in @($Members | Group-Object { "$($_.Domain)|$($_.Kind)" })) {
        $all = @($batch.Group)
        for ($start = 0; $start -lt $all.Count; $start += 100) {
            $filter = Get-SelectionDnFilter @($all[$start..([Math]::Min($start + 99, $all.Count - 1))])
            $found = try {
                if ($all[0].Kind -eq 'Computer') { @(Get-ADComputer -Server $all[0].Domain -LDAPFilter $filter -ErrorAction Stop) }
                else { @(Get-ADUser -Server $all[0].Domain -LDAPFilter $filter -ErrorAction Stop) }
            }
            catch { @() }
            foreach ($object in $found) { $Read[[string]$object.DistinguishedName] = $object }
        }
    }
}

function Get-SelectionDnFilter($Members) {
    # An LDAP filter that finds these objects by their DNs.
    '(|' + (@($Members | ForEach-Object { "(distinguishedName=$(Get-LdapText $_.DistinguishedName))" }) -join '') + ')'
}

# How AD says a change of a group's members can't be made: that this account may not change the group (for every
# member at once: 8344, insufficient rights, or 5, access denied), that a member is already in it, or isn't (as wanted,
# then). By their Win32 error codes, their text being in Windows' language; the text, in English or French, only for
# an error without a code.
# Their French in a French Windows, its accents matched by any letter: these patterns aren't shown.
$script:GroupDenied = @{ Pattern = 'Insufficient access rights|Access is denied|Acc.s refus.|0x80070005|droits d.acc.s insuffisants'; Code = 8344, 5 }
$script:GroupAlreadyIn = @{ Pattern = 'already a member|d.j. membre'; Code = 1378 }
$script:GroupNotIn = @{ Pattern = 'is not a member|n.est pas membre'; Code = 1377 }

function Test-GroupRefusal($Exception, $Refusal) {
    # Whether AD's refusal is this one: one of its Win32 codes, as ADException's ErrorCode, Win32Exception's
    # NativeErrorCode, or an HRESULT 0x8007xxxx (an UnauthorizedAccessException's is 0x80070005). Its text otherwise,
    # for an error that has none of these.
    $codes = @(foreach ($name in 'ErrorCode', 'NativeErrorCode') {
        $property = $Exception.PSObject.Properties[$name]
        if ($property -and ($property.Value -is [int] -or $property.Value -is [uint32])) { [int64]$property.Value }
    })
    $hresult = [int64]$Exception.HResult -band 0xFFFFFFFFL
    if (($hresult -band 0xFFFF0000L) -eq 0x80070000L) { $codes += $hresult -band 0xFFFF }
    if (@($codes | Where-Object { $_ -in $Refusal.Code }).Count) { return $true }
    "$($Exception.Message)" -match $Refusal.Pattern
}

# The DC each domain's reads and changes go to (Get-GroupServerMap), and those found not answering
# (Invoke-OnGroupServer): given to the search runspace a change runs on, by the window's thread.
$script:GroupServers = @{}
$script:GroupServersDown = @{}

function Get-GroupServerMap($Domains) {
    # On the window's thread, before the selection's groups are read or changed: each domain's DC (Get-UserServer: its
    # PDC, where a user's Propriétés reads its groups, or the DC used in its place), so the window read again shows the
    # change (#256). For Invoke-OnGroupServer, on a search runspace, which can't keep that choice itself.
    $map = @{}
    foreach ($domain in @($Domains | Where-Object { $_ } | Select-Object -Unique)) { $map[$domain] = Get-UserServer $domain }
    $map
}

function Invoke-OnGroupServer([string]$Domain, [scriptblock]$Call, $Value) {
    # & $Call $Value <server>: on $Domain's DC of $script:GroupServers (Get-GroupServerMap), its domain (any DC) without
    # one. One that doesn't answer: another DC that does (Get-DomainFallback) instead, for this call and the rest of the
    # change, so each doesn't wait for it; $script:GroupServersDown says which, for the window's thread to read from it
    # next (Register-GroupServerDown).
    $server = if ($script:GroupServers) { $script:GroupServers[$Domain] }
    if (-not $server) { $server = $Domain }
    try { & $Call $Value $server }
    catch {
        if ($server -eq $Domain -or -not (Test-ServerDown $_)) { throw }
        $problem = $_.Exception.Message
        $other = Get-DomainFallback $Domain $server
        if ($null -eq $script:GroupServersDown) { $script:GroupServersDown = @{} }
        $script:GroupServersDown[$Domain] = @{ Server = $server; Problem = $problem; Fallback = $other }
        if ($null -eq $script:GroupServers) { $script:GroupServers = @{} }
        $script:GroupServers[$Domain] = $other
        & $Call $Value $other
    }
}

function Register-GroupServerDown($Down) {
    # On the window's thread, after a read or change of the selection's groups: each DC Invoke-OnGroupServer found not
    # answering kept as such, and the one it used instead for the next changes and Propriétés (Register-ServerDown).
    if (-not $Down) { return }
    foreach ($domain in @($Down.Keys)) { Register-ServerDown $domain $Down[$domain] }
}

function Invoke-GroupMemberBatch($Pending, [scriptblock]$Change, [string]$Done, [string]$Failed, [string]$GroupName, $Settled, [string]$Domain) {
    # $Change with every pending member at once (each @{ Member; As }: As is what AD takes) and the DC of the group's
    # $Domain (Invoke-OnGroupServer), then a line each: $Done ({0} the member, {1} the group), or $Failed ({2} why). AD
    # takes the whole call or none of it. Refused for the group (access): said for each member, without trying again.
    # Otherwise each member is tried alone, so one it can't take (an account of another domain, for a global group)
    # doesn't keep the others out; one already as wanted ($Settled, a refusal of Test-GroupRefusal: already in it, for an
    # addition) is $Done.
    if (-not $Pending.Count) { return }
    try {
        Invoke-OnGroupServer $Domain $Change @($Pending | ForEach-Object { $_.As })
        foreach ($item in $Pending) { $Done -f $item.Member.Label, $GroupName }
        return
    }
    catch {
        $why = $_.Exception.Message
        if ($Pending.Count -eq 1 -or (Test-GroupRefusal $_.Exception $script:GroupDenied)) {
            if ($Pending.Count -eq 1 -and $Settled -and (Test-GroupRefusal $_.Exception $Settled)) { return $Done -f $Pending[0].Member.Label, $GroupName }
            foreach ($item in $Pending) { $Failed -f $item.Member.Label, $GroupName, $why }
            return
        }
    }
    foreach ($item in $Pending) {
        try {
            Invoke-OnGroupServer $Domain $Change @($item.As)
            $Done -f $item.Member.Label, $GroupName
        }
        catch {
            if ($Settled -and (Test-GroupRefusal $_.Exception $Settled)) { $Done -f $item.Member.Label, $GroupName }
            else { $Failed -f $item.Member.Label, $GroupName, $_.Exception.Message }
        }
    }
}

function Add-SelectionGroupMember($Groups, $Members) {
    # Each member into each group ($Groups: the picker's items, Name and DistinguishedName): one Add-ADGroupMember per
    # group with those not in it yet, then a line per member and group. AD refuses the whole call when one is already
    # in, so those are left out first and said: by the members' own groups, read once for every group in batches
    # (Read-SelectionMemberOf), however big the group. A group of another domain lists its members of other domains only
    # in its own member, as foreign security principals: its member is read for those. One found in after all (its
    # primary group, which memberOf leaves out) counts as done.
    $read = @{}
    $memberOf = (Read-SelectionMemberOf $Members).MemberOf
    $foreign = @($Members | Where-Object { $domain = $_.Domain; @($Groups | Where-Object { (Get-DomainOfDN $_.DistinguishedName) -ne $domain }).Count })
    if ($foreign.Count) { Read-SelectionAccount $foreign $read }
    foreach ($group in $Groups) {
        $dn = [string]$group.DistinguishedName
        $groupDomain = Get-DomainOfDN $dn
        $root = (@($dn -split '(?<!\\),' | Where-Object { $_ -like 'DC=*' })) -join ','
        # Read only when a member of another domain needs it; unread, AD says it.
        $present = $null
        $pending = [System.Collections.Generic.List[object]]::new()
        foreach ($member in $Members) {
            try { $as = Get-GroupMemberObject $member $groupDomain $read }
            catch { (Tr '✖ {0} : non ajouté à {1} ({2})') -f $member.Label, $group.Name, $_.Exception.Message; continue }
            $in = if ($member.Domain -eq $groupDomain) {
                $groupsOf = $null
                $memberOf.TryGetValue($member.DistinguishedName, [ref]$groupsOf) -and @($groupsOf) -contains $dn
            }
            else {
                if ($null -eq $present) {
                    $present = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    try {
                        $values = (Invoke-OnGroupServer $groupDomain { param($Identity, $Server) Get-ADGroup -Server $Server -Identity $Identity -Properties member -ErrorAction Stop } $dn).member
                        foreach ($value in @($values)) { $null = $present.Add([string]$value) }
                    }
                    catch { Write-Verbose "Membres de $dn non lus : $_" }
                }
                $sid = if ($as -isnot [string] -and $as.PSObject.Properties['SID']) { [string]$as.SID }
                $present.Contains($member.DistinguishedName) -or ($sid -and $present.Contains("CN=$sid,CN=ForeignSecurityPrincipals,$root"))
            }
            if ($in) { (Tr '✔ {0} : déjà dans {1}') -f $member.Label, $group.Name }
            else { $pending.Add(@{ Member = $member; As = $as }) }
        }
        $change = { param($Accounts, $Server) Add-ADGroupMember -Server $Server -Identity $dn -Members $Accounts -ErrorAction Stop }.GetNewClosure()
        Invoke-GroupMemberBatch $pending $change (Tr '✔ {0} : ajouté à {1}') (Tr '✖ {0} : non ajouté à {1} ({2})') $group.Name $script:GroupAlreadyIn $groupDomain
    }
}

function Read-SelectionMemberOf($Members) {
    # Each member's direct groups (memberOf, as its domain's DC has it: groups of that domain; the primary group isn't
    # there): MemberOf, the group DNs by member DN. Unread: each member that couldn't be read (Member, Problem). One
    # search per domain, by their DNs, 100 at a time: 200 computers are two queries, not 200. On the DC the changes go
    # to (Invoke-OnGroupServer), so a group just left isn't offered again.
    $memberOf = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $unread = [System.Collections.Generic.List[object]]::new()
    foreach ($domain in @($Members | Group-Object { $_.Domain })) {
        $all = @($domain.Group)
        for ($start = 0; $start -lt $all.Count; $start += 100) {
            $chunk = @($all[$start..([Math]::Min($start + 99, $all.Count - 1))])
            try { $found = @(Invoke-OnGroupServer $domain.Name { param($Filter, $Server) Get-ADObject -Server $Server -LDAPFilter $Filter -Properties MemberOf -ErrorAction Stop } (Get-SelectionDnFilter $chunk)) }
            catch {
                $why = $_.Exception.Message
                foreach ($member in $chunk) { $unread.Add(@{ Member = $member; Problem = $why }) }
                continue
            }
            foreach ($object in $found) { $memberOf[[string]$object.DistinguishedName] = [string[]]@($object.MemberOf | ForEach-Object { [string]$_ }) }
            foreach ($member in $chunk) {
                # As AD says it when one is read by its DN.
                if (-not $memberOf.ContainsKey($member.DistinguishedName)) {
                    $unread.Add(@{ Member = $member; Problem = "Cannot find an object with identity: '$($member.DistinguishedName)' under: '$($domain.Name)'." })
                }
            }
        }
    }
    @{ MemberOf = $memberOf; Unread = @($unread) }
}

function Read-SelectionDirectGroup($Members) {
    # The groups at least one member is a direct member of (Read-SelectionMemberOf; the primary group can't be removed):
    # Groups, each with its Name, DistinguishedName, Domain and the Members in it, by name. Unread: each member that
    # couldn't be read (Member, Problem). Run in the background (Start-BackgroundRead).
    $read = Read-SelectionMemberOf $Members
    $groups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $Members) {
        $groupsOf = $null
        if (-not $read.MemberOf.TryGetValue($member.DistinguishedName, [ref]$groupsOf)) { continue }
        foreach ($dn in $groupsOf) {
            if (-not $groups.ContainsKey($dn)) {
                $groups[$dn] = @{ Name = Get-DnName $dn; DistinguishedName = $dn; Domain = Get-DomainOfDN $dn; Members = [System.Collections.Generic.List[object]]::new() }
            }
            $groups[$dn].Members.Add($member)
        }
    }
    @{ Groups = @($groups.Values | Sort-Object { $_.Name }); Unread = $read.Unread; Down = $script:GroupServersDown }
}

function Remove-SelectionGroupMember($Groups) {
    # Each group ticked, the members of the selection in it out of it (Read-SelectionDirectGroup's Members): one
    # Remove-ADGroupMember per group, then a line per member and group.
    $read = @{}
    foreach ($group in $Groups) {
        $dn = [string]$group.DistinguishedName
        $groupDomain = Get-DomainOfDN $dn
        $pending = [System.Collections.Generic.List[object]]::new()
        foreach ($member in $group.Members) {
            try { $pending.Add(@{ Member = $member; As = Get-GroupMemberObject $member $groupDomain $read }) }
            catch { (Tr '✖ {0} : non retiré de {1} ({2})') -f $member.Label, $group.Name, $_.Exception.Message }
        }
        $change = { param($Accounts, $Server) Remove-ADGroupMember -Server $Server -Identity $dn -Members $Accounts -Confirm:$false -ErrorAction Stop }.GetNewClosure()
        Invoke-GroupMemberBatch $pending $change (Tr '✔ {0} : retiré de {1}') (Tr '✖ {0} : non retiré de {1} ({2})') $group.Name $script:GroupNotIn $groupDomain
    }
}

function Get-SelectionGroupSummary($Members, [string[]]$GroupNames, [switch]$Remove) {
    # The status bar's notice when every line went well: « ✔ jbertrand dans GG-VPN et GG-Ventes », « ✔ 3 utilisateurs
    # retirés de 2 groupes ». Show-ActionReport formats it with the lines' count: its braces doubled.
    $Members = @($Members)
    $groups = if ($GroupNames.Count -eq 1) { $GroupNames[0] } else { (Tr '{0} groupes') -f $GroupNames.Count }
    $text = if ($Members.Count -eq 1) {
        $format = if ($Remove) { Tr '✔ {0} retiré de {1}' } else { Tr '✔ {0} dans {1}' }
        $format -f $Members[0].Label, (Join-FrenchList $GroupNames)
    }
    else {
        $format = switch ("$($Members[0].Kind)$([bool]$Remove)") {
            'ComputerTrue' { Tr '✔ {0} ordinateurs retirés de {1}' }
            'ComputerFalse' { Tr '✔ {0} ordinateurs dans {1}' }
            'UserTrue' { Tr '✔ {0} utilisateurs retirés de {1}' }
            default { Tr '✔ {0} utilisateurs dans {1}' }
        }
        $format -f $Members.Count, $groups
    }
    $text.Replace('{', '{{').Replace('}', '}}')
}

function Get-SelectionGroupHeading($Members, [switch]$Remove) {
    # « Ajouter Julie Bertrand à des groupes », « Retirer 3 ordinateurs de groupes ».
    $Members = @($Members)
    if ($Members.Count -eq 1) {
        $format = if ($Remove) { Tr 'Retirer {0} de groupes' } else { Tr 'Ajouter {0} à des groupes' }
        return $format -f $Members[0].Name
    }
    $format = switch ("$($Members[0].Kind)$([bool]$Remove)") {
        'ComputerTrue' { Tr 'Retirer {0} ordinateurs de groupes' }
        'ComputerFalse' { Tr 'Ajouter {0} ordinateurs à des groupes' }
        'UserTrue' { Tr 'Retirer {0} utilisateurs de groupes' }
        default { Tr 'Ajouter {0} utilisateurs à des groupes' }
    }
    $format -f $Members.Count
}

function Complete-SelectionGroupChange($Members, [string[]]$Lines, [string]$Title, [string[]]$GroupNames, [switch]$Remove) {
    # After the change: the users' open Propriétés read themselves again, and the report.
    if ($Members[0].Kind -eq 'User') { Update-OpenUserDetail @($Members | ForEach-Object { $_.Row }) }
    Show-ActionReport @($Lines) $Title -Many (Get-SelectionGroupSummary $Members $GroupNames -Remove:$Remove)
}

function Invoke-SelectionGroupChange([string]$Command, [object[]]$Arguments) {
    # On a search runspace: the change's report, as one object (a read gives back the last one written), and the DCs
    # found not answering (Invoke-OnGroupServer).
    @{ Lines = @(& $Command @Arguments); Down = $script:GroupServersDown }
}

function Start-SelectionGroupChange([string]$Command, [object[]]$Arguments, $Members, [string]$Title, [string[]]$GroupNames, [switch]$Remove) {
    # The change in the background, many objects being many AD calls, then the report. On each domain's DC chosen here
    # (Get-GroupServerMap): the groups' ($Arguments' first, each with its DistinguishedName) and the members'.
    $domains = @(@($Arguments[0]) | ForEach-Object { Get-DomainOfDN ([string]$_.DistinguishedName) }) + @($Members | ForEach-Object { $_.Domain })
    # The report comes whole at the end: a DC that doesn't answer within the changes' time limit (Get-WriteTimeout, a
    # call per group then per member at worst) leaves every member's change unsure, which their lines say.
    $timeout = Get-WriteTimeout (@($Arguments[0]).Count * [Math]::Max(1, @($Members).Count))
    Start-WindowRead -Kind "$Command $([guid]::NewGuid())" -Command 'Invoke-SelectionGroupChange' -Arguments @($Command, $Arguments) -Timeout $timeout `
        -Functions $Command, 'Get-GroupMemberObject', 'Read-SelectionMemberOf', 'Read-SelectionAccount', 'Get-SelectionDnFilter', 'Invoke-GroupMemberBatch', 'Test-GroupRefusal', 'Get-DomainOfDN', 'Get-LdapText', 'Invoke-OnGroupServer', 'Test-ServerDown', 'Get-DomainFallback' `
        -Variables @{ GroupDenied = $script:GroupDenied; GroupAlreadyIn = $script:GroupAlreadyIn; GroupNotIn = $script:GroupNotIn; GroupServers = Get-GroupServerMap $domains; GroupServersDown = @{} } `
        -Context @{ Members = $Members; Title = $Title; GroupNames = $GroupNames; Remove = [bool]$Remove; Timeout = $timeout } -OnDone {
        param($context, $read, $problem, $timedOut)
        if ($timedOut) {
            Show-ActionReport @($context.Members | ForEach-Object { (Tr '⚠ {0} : {1}') -f $_.Label, (Get-WriteUnsureText $context.Timeout) }) $context.Title
            if ($context.Members[0].Kind -eq 'User') { Update-OpenUserDetail @($context.Members | ForEach-Object { $_.Row }) }
            return
        }
        if ($problem -or -not $read) {
            $why = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
            Show-ActionReport @($context.Members | ForEach-Object { (Tr '✖ {0} : {1}') -f $_.Label, $why }) $context.Title
            return
        }
        Register-GroupServerDown $read.Down
        Complete-SelectionGroupChange $context.Members @($read.Lines) $context.Title $context.GroupNames -Remove:$context.Remove
    }
}

function Show-SelectionGroupAdd($Members) {
    # Ajouter à un groupe…: the picker of a user's Propriétés, the first object's domain first; each group ticked
    # takes them all. More objects than Supprimer de l'AD lets go with one OK: their number to type. A privileged group
    # ticked: a second confirmation (Confirm-PrivilegedGroup).
    $Members = @($Members)
    if (-not $Members.Count) { return }
    $first = $Members[0]
    $content = New-GroupPickerContent $first.Domain @()
    $message = if ($first.Kind -eq 'Computer') { Tr "Les groupes du domaine {0} : cochez-en un ou plusieurs. L'appartenance prend effet au prochain redémarrage de l'ordinateur." }
               else { Tr "Les groupes du domaine {0} : cochez-en un ou plusieurs. L'appartenance prend effet à la prochaine ouverture de session." }
    $typed = if ($Members.Count -gt $script:TypeToConfirmAbove) { [string]$Members.Count }
    Show-Dialog -Title (Tr 'Ajouter à un groupe') -Heading (Get-SelectionGroupHeading $Members) -Names $(if ($Members.Count -gt 1) { @($Members | ForEach-Object { $_.Label }) }) `
        -Icon 'users' -Message ($message -f $first.Domain) -Content $content -PickFrom $content.FindName('group_results') -OkText (Tr 'Ajouter') -TypeToConfirm $typed -Owner $script:win `
        -State @{ Members = $Members; Content = $content; Groups = @() } -OnOk {
        param($dialog)
        $dialog.Groups = @($dialog.Content.FindName('group_results').SelectedItems)
        if (-not $dialog.Groups.Count) { return }
        Confirm-PrivilegedGroup $dialog.Groups (Get-SelectionGroupWho $dialog.Members) $script:win $dialog {
            param($dialog)
            Start-SelectionGroupChange 'Add-SelectionGroupMember' @($dialog.Groups, $dialog.Members) $dialog.Members (Tr 'Ajouter à un groupe') @($dialog.Groups | ForEach-Object { $_.Name })
        }
    }
}

function Get-SelectionGroupWho($Members) {
    # Who a privileged group's confirmation names: « Julie Bertrand », « 3 ordinateurs », « 2 utilisateurs ».
    $Members = @($Members)
    if ($Members.Count -eq 1) { return [string]$Members[0].Name }
    $format = if ($Members[0].Kind -eq 'Computer') { Tr '{0} ordinateurs' } else { Tr '{0} utilisateurs' }
    $format -f $Members.Count
}

$script:SelectionGroupReading = $false

function Show-SelectionGroupRemove($Members) {
    # Retirer d'un groupe…: their direct groups, read in the background (the cursor says so), then a dialog to tick those
    # to leave. One read at a time.
    $Members = @($Members)
    if (-not $Members.Count -or $script:SelectionGroupReading) { return }
    $script:SelectionGroupReading = $true
    $script:win.Cursor = [System.Windows.Input.Cursors]::AppStarting
    try {
        # Read where the changes go (Get-GroupServerMap), so a group just left isn't offered again.
        $servers = @{ GroupServers = Get-GroupServerMap @($Members | ForEach-Object { $_.Domain }); GroupServersDown = @{} }
        Start-BackgroundRead -Command 'Read-SelectionDirectGroup' -Arguments @(, $Members) -Functions 'Read-SelectionMemberOf', 'Get-SelectionDnFilter', 'Get-DnName', 'Get-DomainOfDN', 'Get-LdapText', 'Invoke-OnGroupServer', 'Test-ServerDown', 'Get-DomainFallback' `
            -Variables ((Get-DetailReadVariable) + $servers) -Context @{ Members = $Members } -OnDone {
            param($context, $read, $problem)
            $script:SelectionGroupReading = $false
            $script:win.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
            if ($problem -or -not $read) {
                $why = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
                Show-ActionReport @($context.Members | ForEach-Object { (Tr '✖ {0} : groupes non lus ({1})') -f $_.Label, $why }) (Tr "Retirer d'un groupe")
                return
            }
            Register-GroupServerDown $read.Down
            $unread = @($read.Unread | ForEach-Object { (Tr '✖ {0} : groupes non lus ({1})') -f $_.Member.Label, $_.Problem })
            Show-SelectionGroupRemoveDialog $context.Members @($read.Groups) $unread
        }
    }
    catch {
        $script:SelectionGroupReading = $false
        $script:win.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
        Show-ActionReport @($Members | ForEach-Object { (Tr '✖ {0} : groupes non lus ({1})') -f $_.Label, $_.Exception.Message }) (Tr "Retirer d'un groupe")
    }
}

function Show-SelectionGroupRemoveDialog($Members, $Groups, [string[]]$Unread) {
    # The groups read, each with how many of the selection are in it; those ticked lose them all, after the number is
    # typed for many objects. None: said, with the members that couldn't be read.
    $title = Tr "Retirer d'un groupe"
    if (-not $Groups.Count) {
        if ($Unread.Count) { Show-ActionReport $Unread $title; return }
        Show-Dialog -Title $title -Icon 'users' -Heading ((Tr '{0} : rien à faire') -f $title) -Owner $script:win `
            -Message (Tr "Membre direct d'aucun groupe : le groupe principal (Utilisateurs du domaine, Ordinateurs du domaine) ne se retire pas d'ici.")
        return
    }
    $content = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{StaticResource Card}" MaxHeight="260">
  <ListBox x:Name="group_remove_results" Background="Transparent" BorderThickness="0" SelectionMode="Multiple" AutomationProperties.Name="Groupes directs">
    <ListBox.ItemContainerStyle>
      <Style TargetType="ListBoxItem" BasedOn="{StaticResource {x:Type ListBoxItem}}">
        <Setter Property="Foreground" Value="{DynamicResource R.Text}"/><Setter Property="Padding" Value="10,6"/>
        <Setter Property="AutomationProperties.Name" Value="{Binding Name}"/>
      </Style>
    </ListBox.ItemContainerStyle>
    <ListBox.ItemTemplate>
      <DataTemplate>
        <Grid Margin="2,2">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <!-- Ticked as the group is chosen: a click on the row ticks or unticks it. -->
          <CheckBox IsHitTestVisible="False" Focusable="False" VerticalAlignment="Center" Margin="0,0,8,0"
                    IsChecked="{Binding IsSelected, RelativeSource={RelativeSource AncestorType=ListBoxItem}}"/>
          <StackPanel Grid.Column="1">
            <TextBlock Text="{Binding Name}" FontWeight="{DynamicResource R.FontWeightStrong}"/>
            <TextBlock Text="{Binding Details}" FontSize="12" Opacity="0.75" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
        </Grid>
      </DataTemplate>
    </ListBox.ItemTemplate>
  </ListBox>
</Border>
'@))
    $list = $content.FindName('group_remove_results')
    foreach ($group in $Groups) {
        $count = if ($Members.Count -gt 1) { (Tr 'membre direct : {0} sur {1}') -f $group.Members.Count, $Members.Count }
        $null = $list.Items.Add([pscustomobject]@{ Name = $group.Name; DistinguishedName = $group.DistinguishedName; Members = @($group.Members)
                                                   Details = (@($group.Domain, $count) | Where-Object { $_ }) -join ' · ' })
    }
    $one = $Members.Count -eq 1
    $message = switch ("$($Members[0].Kind)$one") {
        'ComputerTrue' { Tr "Cochez les groupes d'où le retirer : il perd ce qu'ils donnent (accès, logiciels, stratégies) à son prochain redémarrage." }
        'ComputerFalse' { Tr "Cochez les groupes d'où les retirer : ils perdent ce qu'ils donnent (accès, logiciels, stratégies) à leur prochain redémarrage." }
        'UserTrue' { Tr "Cochez les groupes d'où le retirer : il perd ce qu'ils donnent (accès, logiciels, stratégies) à sa prochaine ouverture de session." }
        default { Tr "Cochez les groupes d'où les retirer : ils perdent ce qu'ils donnent (accès, logiciels, stratégies) à leur prochaine ouverture de session." }
    }
    if ($Unread.Count) { $message += "`n`n" + ($Unread -join "`n") }
    $typed = if ($Members.Count -gt $script:TypeToConfirmAbove) { [string]$Members.Count }
    Show-Dialog -Title $title -Heading (Get-SelectionGroupHeading $Members -Remove) -Names $(if (-not $one) { @($Members | ForEach-Object { $_.Label }) }) `
        -Icon 'users' -Tone 'danger' -Message $message -Content $content -PickFrom $list -OkText (Tr 'Retirer') -CancelIsDefault -TypeToConfirm $typed -Owner $script:win `
        -State @{ Members = $Members; Content = $content } -OnOk {
        param($dialog)
        $groups = @($dialog.Content.FindName('group_remove_results').SelectedItems)
        if (-not $groups.Count) { return }
        $members = @($groups | ForEach-Object { $_.Members } | Group-Object { $_.DistinguishedName } | ForEach-Object { $_.Group[0] })
        Start-SelectionGroupChange 'Remove-SelectionGroupMember' @(, $groups) $members (Tr "Retirer d'un groupe") @($groups | ForEach-Object { $_.Name }) -Remove
    }
}
