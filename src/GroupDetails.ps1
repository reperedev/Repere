# Propriétés… of a group (the Groupes page): its members, the groups it belongs to and the group itself, in the window a
# user's Propriétés uses (UserDetails.ps1: Show-DetailWindow, the cards, chips and lists). Members can be added (users,
# computers and groups of its domain) and removed (the direct ones ticked, after a confirmation); the rest is read only.
# A group can hold thousands of members: they're never read whole, but $MemberListMax at a time, and found by a search
# that AD runs. A group or a user listed in its cards opens in its own Propriétés, on top: that's how nesting is
# followed, one level at a time. Dot-sourced by the main script, after GroupsDialog.ps1 (Get-ObjectGroup), UserDetails.ps1 and
# GroupPage.ps1.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

# A member's kind, from its objectClass, and how many members are read and shown at most. The kind is a key, compared
# and sorted on, in French in every language: Tr says it.
$script:MemberKinds = @{ user = 'Utilisateur'; inetOrgPerson = 'Utilisateur'; computer = 'Ordinateur'; group = 'Groupe'; contact = 'Contact'; foreignSecurityPrincipal = 'Externe' }
$script:MemberListMax = 200
# A member's kind as Get-GroupMemberObject reads it in its domain (any other: its class read there first).
$script:MemberReadKinds = @{ Utilisateur = 'User'; Ordinateur = 'Computer'; Groupe = 'Group' }
# A domain local group's members of other domains are read one by one: this many at most per list.
$script:MemberForeignMax = 50
# The forest's global catalog, once found (Get-GlobalCatalog).
$script:GlobalCatalog = $null

function Read-GroupDetail($Row, [string]$Filter, [string]$Server) {
    # Everything the window shows, read in the group's domain (on a search runspace: Start-DetailRead): the group
    # (without its member list), its members as Read-GroupMember finds them, and the groups it belongs to directly
    # (MemberOf). Not tokenGroups, which a hardened domain can refuse and which leaves out distribution groups: a parent
    # group's own Propriétés shows what it is in. The global catalog found or forgotten meanwhile comes back with the
    # members (Read-GroupMember), for the next reads. $Server: the DC its changes go to (Get-UserServer: the PDC), so the window read again shows them (#256). One that
    # doesn't answer: another DC that does instead (Get-DomainFallback), and Down says which, for the window's thread
    # to send the next changes there (Register-ServerDown).
    $domain = $Row.Domain
    if (-not $Server) { $Server = $domain }
    $down = $null
    $properties = 'Description', 'mail', 'ManagedBy', 'whenCreated', 'whenChanged', 'MemberOf'
    $group = try { Get-ADGroup -Server $Server -Identity $Row.DistinguishedName -Properties $properties -ErrorAction Stop }
             catch {
                 if ($Server -eq $domain -or -not (Test-ServerDown $_)) { throw }
                 $problem = $_.Exception.Message
                 $other = Get-DomainFallback $domain $Server
                 $down = @{ Server = $Server; Problem = $problem; Fallback = $other }
                 $Server = $other
                 Get-ADGroup -Server $Server -Identity $Row.DistinguishedName -Properties $properties -ErrorAction Stop
             }
    @{
        Row = $Row; Group = $group; Members = Read-GroupMember $Row $group $Filter $Server
        Parents = @(Get-ObjectGroup $group $domain | Where-Object DistinguishedName -ne $group.DistinguishedName); Server = $Server; Down = $down
    }
}

function Get-GlobalCatalog([switch]$Again) {
    # A global catalog of the forest (its host and port 3268), '' when none is found. The one found is kept for the next
    # reads, until a search on it fails (Read-GroupMember forgets it); a lookup that failed isn't, so the next read looks
    # again rather than going domain by domain for the rest of the session (#250). -Again: looks past the one kept, and
    # past the DC locator's own cache (-ForceDiscover), which would give the same one back.
    if ($Again -or -not $script:GlobalCatalog) {
        $script:GlobalCatalog = try { "$(@((Get-ADDomainController -Discover -Service GlobalCatalog -ForceDiscover:$Again -ErrorAction Stop).HostName)[0]):3268" } catch { $null }
    }
    [string]$script:GlobalCatalog
}

function Save-GlobalCatalog($Members) {
    # The global catalog a read on a search runspace found or forgot (Read-GroupMember's Catalog, there only when it
    # used one), kept on this thread for the next reads.
    if ($Members -is [hashtable] -and $Members.ContainsKey('Catalog')) { $script:GlobalCatalog = $Members.Catalog }
}

function Read-GroupMember($Row, $Group, [string]$Filter, [string]$Server) {
    # The group's members, $MemberListMax at most, each search asking AD for one more to tell whether there are others
    # (Truncated). $Filter, the start of a name or login, goes to AD with them: a group of thousands is never read
    # whole. Not ANR, which also matches the office, the email addresses and phonetic forms (« mont » would find
    # everyone in Montréal and fill the list): the name, login, display name, first or last name that starts with it
    # (#250). A DC knows only its own domain's member lists, so where the direct members are found depends on the
    # group's scope:
    # - global: its domain, where all of them are;
    # - universal, in a forest of several domains: a global catalog, every domain at once; when none answers, each
    #   domain, and Problem says members of other domains may be missing. The one kept from an earlier read may have
    #   gone down since: when its search fails, another is looked for once and asked instead. One whose search fails
    #   isn't kept, and Catalog says what is, for the window's thread (Save-GlobalCatalog);
    # - domain local: its domain, then its members of other domains from its own member list, each read in its domain,
    #   $MemberForeignMax at most (such groups usually hold a few global groups); the search keeps those whose name
    #   starts with the text.
    # Then the accounts whose primary group it is (primaryGroupID, its domain). A member from another forest (a foreign
    # security principal, found in its domain) is named by its account, DOMAINE\nom, when Windows can translate its SID.
    # A search that fails is said in Problem. Its domain asked on $Server (Read-GroupDetail's), any of its DCs without.
    $at = if ($Server) { $Server } else { $Row.Domain }
    $text = if ($Filter) {
        $value = Get-LdapText $Filter
        "(|$(@('name', 'sAMAccountName', 'displayName', 'givenName', 'sn' | ForEach-Object { "($_=$value*)" }) -join ''))"
    } else { '' }
    $max = $script:MemberListMax
    $memberOf = "(&(memberOf=$(Get-LdapText $Group.DistinguishedName))$text)"
    $scope = [string]$Group.GroupScope
    $others = @($script:domainList | Where-Object { $_ -and $_ -ne $Row.Domain })
    $found = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[string]]::new()
    $state = @{ Truncated = $false }
    $add = {
        param($Object, [string]$Membership)
        $dn = [string]$Object.DistinguishedName
        $class = [string]$Object.ObjectClass
        $name = [string]$Object.Name
        if ($class -eq 'foreignSecurityPrincipal') {
            $name = try { ([System.Security.Principal.SecurityIdentifier]$name).Translate([System.Security.Principal.NTAccount]).Value } catch { $name }
        }
        $kind = $script:MemberKinds[$class]
        $found.Add([pscustomobject]@{
            Name = $name; Login = [string]$Object.sAMAccountName; Kind = if ($kind) { $kind } else { 'Autre' }
            Membership = $Membership; Domain = Get-DomainOfDN $dn; OUPath = Get-OUPath $dn; DistinguishedName = $dn
        })
    }
    $search = {
        param([string]$Server, [string]$LdapFilter, [string]$Membership, [bool]$Forest)
        $left = $max - $found.Count
        if ($left -le 0) { $state.Truncated = $true; return }
        $where = if ($Forest) { @{ SearchBase = '' } } else { @{} }
        try {
            $objects = @(Get-ADObject -Server $Server -LDAPFilter $LdapFilter -Properties sAMAccountName -ResultSetSize ($left + 1) @where -ErrorAction Stop)
            if ($objects.Count -gt $left) { $state.Truncated = $true; $objects = $objects[0..($left - 1)] }
            foreach ($object in $objects) { & $add $object $Membership }
        }
        catch { $problems.Add(((Tr '{0} : {1}') -f $Server, $_.Exception.Message)) }
    }

    $result = @{}
    if ($scope -eq 'Universal' -and $others.Count) {
        $kept = [bool]$script:GlobalCatalog
        $catalog = Get-GlobalCatalog
        if ($catalog) {
            $before = $problems.Count
            & $search $catalog $memberOf 'Directe' $true
            if ($problems.Count -gt $before -and $kept) {
                $problems.RemoveAt($before)
                $catalog = Get-GlobalCatalog -Again
                if ($catalog) { & $search $catalog $memberOf 'Directe' $true }
            }
            if ($problems.Count -gt $before) { $script:GlobalCatalog = $null }
        }
        $result.Catalog = $script:GlobalCatalog
        if (-not $catalog) {
            $problems.Add((Tr "aucun catalogue global ne répond : des membres d'autres domaines peuvent manquer"))
            foreach ($domain in @($at) + $others) { & $search $domain $memberOf 'Directe' $false }
        }
    }
    else { & $search $at $memberOf 'Directe' $false }

    if ($scope -eq 'DomainLocal' -and $others.Count -and $found.Count -lt $max) {
        try {
            $foreign = @((Get-ADGroup -Server $at -Identity $Group.DistinguishedName -Properties member -ErrorAction Stop).member | Where-Object {
                (Get-DomainOfDN $_) -ne $Row.Domain -and (-not $Filter -or (Get-DnName $_).StartsWith($Filter, [System.StringComparison]::OrdinalIgnoreCase))
            })
            $left = [Math]::Min($max - $found.Count, $script:MemberForeignMax)
            if ($foreign.Count -gt $left) { $state.Truncated = $true; $foreign = @($foreign | Select-Object -First $left) }
            foreach ($dn in $foreign) {
                try { & $add (Get-ADObject -Server (Get-DomainOfDN $dn) -Identity $dn -Properties sAMAccountName -ErrorAction Stop) 'Directe' }
                catch { & $add ([pscustomobject]@{ Name = Get-DnName $dn; DistinguishedName = $dn; ObjectClass = ''; sAMAccountName = '' }) 'Directe' }
            }
        }
        catch { $problems.Add(((Tr "membres d'autres domaines : {0}") -f $_.Exception.Message)) }
    }

    $rid = ([string]$Group.SID -split '-')[-1]
    & $search $at "(&(primaryGroupID=$rid)$text)" 'Principale' $false
    $order = @{ Directe = 0; Principale = 1 }
    $result.List = @($found | Sort-Object { $order[$_.Membership] }, Kind, Name)
    $result.Truncated = $state.Truncated
    $result.Filter = $Filter
    $result.Problem = $problems -join (Tr ' ; ')
    $result
}

function Get-GroupDetailSection($Detail) {
    # The group's card, as the user's: rows of label, value and id.
    $group = $Detail.Group
    [ordered]@{
        Groupe = @(
            , @((Tr 'Nom'), $group.Name, 'name')
            , @((Tr 'Nom pré-Windows 2000'), $group.SamAccountName, 'sam')
            , @((Tr 'Type'), $script:GroupTypes[[string]$group.GroupCategory], 'type')
            , @((Tr 'Étendue'), $script:GroupScopes[[string]$group.GroupScope], 'scope')
            , @((Tr 'Description'), $group.Description, 'description')
            , @((Tr 'Courriel'), $group.mail, 'mail')
            , @((Tr 'Géré par'), $(Get-DnName $group.ManagedBy), 'managed_by')
            , @((Tr 'Nom distinctif'), $group.DistinguishedName, 'dn')
            , @((Tr 'Créé'), $(Format-TextDate $group.whenCreated), 'created')
            , @((Tr 'Modifié'), $(Format-TextDate $group.whenChanged), 'changed')
        )
    }
}

function Get-GroupDetailChipXaml($Detail) {
    # The header's chips: its type and scope, and « Vide » when it has no member (as far as a search without a name
    # tells).
    $group = $Detail.Group
    $chips = [System.Collections.Generic.List[object]]::new()
    $security = [string]$group.GroupCategory -eq 'Security'
    $chips.Add(@($script:GroupTypes[[string]$group.GroupCategory], 'Neutral', $(if ($security) { 'lock' } else { 'list' })))
    $chips.Add(@($script:GroupScopes[[string]$group.GroupScope], 'Neutral', 'users'))
    $members = $Detail.Members
    if (-not $members.List.Count -and -not $members.Filter -and -not $members.Problem) { $chips.Add(@((Tr 'Vide'), 'Warn', 'info')) }
    ConvertTo-DetailChipXaml $chips
}

function Get-GroupDetailXaml($Detail) {
    # The cards: Membres (Ajouter des membres…, and Retirer… for the direct ones ticked), Membre de, then the group
    # itself, read only. Each folds by its header, like a user's.
    $sections = Get-GroupDetailSection $Detail
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($script:DetailPanelXaml.Replace('user_detail_', 'group_detail_'))
    $parts.Add((Get-GroupMemberXaml $Detail))
    $parts.Add((Get-GroupParentXaml $Detail))
    $parts.Add((Get-DetailCardXaml 'Groupe' (Get-DetailRowsXaml $sections.Groupe 'group_detail') -Tone 'readonly'))
    $parts.Add('</StackPanel>')
    Expand-Icon ($parts -join "`n")
}

function Get-GroupMemberXaml($Detail) {
    # Membres: a box to search a member by the start of its name (AD runs the search), then the list
    # (Get-GroupMemberListXaml, replaced as the search changes).
    $x = { param($value) ConvertTo-XamlValue $value }
    $body = @"
      <Border Style="{StaticResource Field}" Height="34" Margin="12,0,12,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search:14}}</Border>
          <TextBox x:Name="group_member_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Text="$(& $x $Detail.Members.Filter)"
                   Tag="Chercher un membre (ex. bert)"/>
        </Grid>
      </Border>
      <ContentControl x:Name="group_member_list" Focusable="False"/>
"@
    $footer = if ([string]$Detail.Group.GroupCategory -eq 'Security') { Tr 'Prend effet à la prochaine ouverture de session (au redémarrage pour un ordinateur).' }
    $action = @'
<StackPanel Grid.Column="2" Orientation="Horizontal">
  <Button x:Name="group_member_remove" IsEnabled="False" ToolTip="Retirer les membres directs cochés">
    <StackPanel Orientation="Horizontal">{{icon:trash:14}}<TextBlock x:Name="group_member_remove_label" Text="Retirer…" Margin="8,0,0,0"/></StackPanel>
  </Button>
  <Button x:Name="group_member_add" Margin="8,0,0,0"><StackPanel Orientation="Horizontal">{{icon:plus:14}}<TextBlock Text="Ajouter des membres…" Margin="8,0,0,0"/></StackPanel></Button>
</StackPanel>
'@
    Get-DetailCardXaml 'Membres' $body $action -Footer $footer
}

function Get-GroupMemberListXaml($Detail) {
    # The members found: each one's kind, login and location; the direct ones have a box to tick, those whose primary
    # group it is don't (AD doesn't take them out of it). Under them, how many, and what to do when there are more.
    $members = $Detail.Members
    $items = foreach ($member in $members.List) {
        $where = @($member.Login, $(if ($member.Domain -ne $Detail.Row.Domain) { $member.Domain }), $member.OUPath) | Where-Object { $_ }
        if ($member.Membership -eq 'Principale') { $where += Tr 'groupe principal' }
        # Kind and Membership are keys: shown through Tr.
        $kind = Tr $member.Kind
        @{
            Name = $member.Name; Badge = $kind; Detail = $where -join ' · '; Tone = if ($member.Membership -eq 'Directe') { 'accent' } else { 'outline' }
            CanPick = $member.Membership -eq 'Directe'; Automation = "$($member.Name) | $kind | $(Tr $member.Membership)"
            Target = if ($member.Kind -in 'Groupe', 'Utilisateur') { $member }
        }
    }
    $count = $members.List.Count
    $filter = $members.Filter
    $status = if ($members.Truncated -and $filter) { (Tr 'Les {0} premiers membres dont le nom commence par « {1} » : précisez la recherche.') -f $count, $filter }
              elseif ($members.Truncated) { (Tr 'Les {0} premiers membres : cherchez un nom pour trouver les autres.') -f $count }
              elseif (-not $count -and $filter) { (Tr 'Aucun membre dont le nom commence par « {0} ».') -f $filter }
              elseif (-not $count) { Tr 'Aucun membre.' }
              elseif ($count -eq 1 -and $filter) { (Tr '1 membre dont le nom commence par « {0} ».') -f $filter }
              elseif ($count -eq 1) { Tr '1 membre.' }
              elseif ($filter) { (Tr '{0} membres dont le nom commence par « {1} ».') -f $count, $filter }
              else { (Tr '{0} membres.') -f $count }
    if ($members.Problem) { $status += ' ' + ((Tr 'Non lus : {0}') -f (ConvertTo-FrenchError $members.Problem)) }
    $list = if ($count) { Get-DetailListXaml @($items) 'group_member' (Tr 'À retirer') } else { '' }
    $x = { param($value) ConvertTo-XamlValue $value }
    Expand-Icon @"
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
$list
  <TextBlock x:Name="group_member_status" Style="{StaticResource Txt.Muted}" FontSize="12" Margin="14,$(if ($count) { 8 } else { 0 }),14,0" TextWrapping="Wrap" Text="$(& $x $status)"/>
</StackPanel>
"@
}

function Get-GroupParentXaml($Detail) {
    # Membre de: the groups it belongs to directly, each with its type; read only. Each opens in its own Propriétés,
    # which shows what that one belongs to in turn. A long list has a box to filter it, as a user's Groupes.
    $items = foreach ($parent in $Detail.Parents) {
        $kind = @($parent.Scope, $(if ($parent.Domain -ne $Detail.Row.Domain) { $parent.Domain })) | Where-Object { $_ }
        @{
            Name = $parent.Name; Badge = $parent.Type; Tone = 'accent'; Target = if ($parent.Type) { $parent }
            Detail = (@($kind -join ', ') + @($parent.Description | Where-Object { $_ })) -join ' · '; Automation = "$($parent.Name) | $($parent.Type)"
        }
    }
    $body = if ($Detail.Parents.Count) { Get-DetailListXaml @($items) 'group_parent' '' -FilterTip (Tr 'Filtrer les groupes') -NoMatch (Tr 'Aucun groupe.') }
            else { '<TextBlock Style="{StaticResource Txt.Muted}" Margin="14,0,14,8" Text="Membre d''aucun groupe."/>' }
    Get-DetailCardXaml 'Membre de' $body -Count $Detail.Parents.Count -Tone 'readonly'
}

function Update-GroupDetail($State, $Detail) {
    # Reads the group again in the background (Start-DetailRead), its members by the name searched, unless $Detail was
    # just read: then rebuilds the cards.
    if (-not $Detail) { Start-DetailRead $State; return }
    $State.Detail = $Detail
    Save-GlobalCatalog $Detail.Members
    # The PDC didn't answer the read: kept as down, and the changes go where it read instead.
    Register-ServerDown $State.Row.Domain $Detail.Down
    $group = $State.Detail.Group
    $row = $State.Row
    $State.Title.Text = $row.Name
    $State.Subtitle.Text = (@([string]$group.Description, $row.Domain, $row.OUPath) | Where-Object { $_ }) -join ' · '
    $State.Initials.Visibility = 'Collapsed'
    $State.Glyph.Visibility = 'Visible'
    $State.Chips.Content = [System.Windows.Markup.XamlReader]::Parse((Get-GroupDetailChipXaml $State.Detail))
    $body = [System.Windows.Markup.XamlReader]::Parse((Get-GroupDetailXaml $State.Detail))
    $State.Body.Content = $body
    $body.FindName('group_member_add').Add_Click({ param($button) Show-GroupMemberAddDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('group_member_remove').Add_Click({ param($button) Remove-GroupMember ([System.Windows.Window]::GetWindow($button).Tag) })
    # The search: once the typing pauses, or at Entrée.
    $filter = $body.FindName('group_member_filter')
    $filter.Add_TextChanged({ param($box) $state = [System.Windows.Window]::GetWindow($box).Tag; $state.FilterTimer.Stop(); $state.FilterTimer.Start() })
    $filter.Add_KeyDown({
        param($box, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Update-GroupMemberSearch ([System.Windows.Window]::GetWindow($box).Tag) }
    })
    Show-GroupMemberList $State
    Register-DetailOpen $body 'group_parent' $State.Detail.Parents
    Register-DetailFilter $body 'group_parent' $State
    Register-DetailSection $body
}

function Update-GroupMemberSearch($State) {
    # The members whose name starts with the text of the search box, asked of AD again, in the background; an answer
    # for a text since changed is left.
    $State.FilterTimer.Stop()
    $text = "$($State.Body.Content.FindName('group_member_filter').Text)".Trim()
    if ($text -eq $State.MemberFilter -and $State.Detail.Members.Filter -eq $text) { return }
    $State.MemberFilter = $text
    Set-DetailReading $State $true
    Start-UserServerRead -Command 'Read-GroupMember' -Arguments @($State.Row, $State.Detail.Group, $text, $null) -Domain $State.Row.Domain -At 3 -Functions (Get-GroupReadFunction) `
        -Variables (Get-DetailReadVariable) -Context @{ State = $State; Text = $text } -OnDone {
        param($context, $members, $problem)
        $state = $context.State
        if ($state['Closed'] -or $state.MemberFilter -ne $context.Text) { return }
        if (-not $state.Reading) { Set-DetailReading $state $false }
        Save-GlobalCatalog $members
        if ($problem -or -not $members) { Show-DetailNotice $state ((Tr 'Recherche impossible : {0}') -f $(if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' })); return }
        $state.Detail.Members = $members
        Show-GroupMemberList $state
    }
}

function Get-GroupReadFunction {
    # The functions a group's reads need on their runspace.
    'Read-GroupMember', 'Get-GlobalCatalog', 'Get-ObjectGroup', 'Get-DomainOfSid', 'Get-DomainOfDN', 'Get-LdapText', 'Get-DnName', 'Test-ServerDown', 'Get-DomainFallback'
}

function Get-GroupDetailRead($State) {
    # What Start-DetailRead runs for a group: read where its changes go (Get-UserServer, argument 2), looked up on the
    # read's runspace when it isn't known yet (Start-UserServerRead), which gives that choice back to this thread.
    @{ Command = 'Read-GroupDetail'; Arguments = @($State.Row, $State.MemberFilter, $null); Domain = $State.Row.Domain; At = 2; Functions = Get-GroupReadFunction }
}

function Show-GroupMemberList($State) {
    # The members found, in their card, their boxes wired to Retirer….
    $list = [System.Windows.Markup.XamlReader]::Parse((Get-GroupMemberListXaml $State.Detail))
    $State.Body.Content.FindName('group_member_list').Content = $list
    $State.Picks = [System.Collections.Generic.List[object]]::new()
    $members = $State.Detail.Members.List
    for ($i = 0; $i -lt $members.Count; $i++) {
        $pick = $list.FindName("group_member_pick_$i")
        if (-not $pick) { continue }
        $pick.Tag = $members[$i]
        $State.Picks.Add($pick)
        $pick.Add_Checked({ param($box) Update-GroupMemberPick ([System.Windows.Window]::GetWindow($box).Tag) })
        $pick.Add_Unchecked({ param($box) Update-GroupMemberPick ([System.Windows.Window]::GetWindow($box).Tag) })
    }
    Register-DetailOpen $list 'group_member' @($members | ForEach-Object { if ($_.Kind -in 'Groupe', 'Utilisateur') { $_ } else { $null } })
    Update-GroupMemberPick $State
}

function Update-GroupMemberPick($State) {
    # Retirer… says how many members are ticked, and waits for one.
    $count = @($State.Picks | Where-Object IsChecked).Count
    $State.Body.Content.FindName('group_member_remove').IsEnabled = $count -gt 0
    $State.Body.Content.FindName('group_member_remove_label').Text = if ($count) { (Tr 'Retirer ({0})…') -f $count } else { Tr 'Retirer…' }
}

function Show-GroupMemberAddDialog($State) {
    # Ajouter des membres… of a group's Propriétés: the window reads itself again, and says what was added.
    $row = $State.Row
    Show-GroupMemberPicker $row $State.Window (Get-GroupListedMember $State) $State {
        param($state, $result)
        # Added in the background (Start-GroupMemberWrite): closed meanwhile, what failed is said over the main window.
        $open = -not $state['Closed']
        if ($open) { Update-GroupDetail $state }
        $text = Get-GroupMemberAddText $state.Row $result
        if ($text -and $open) { Show-DetailNotice $state $text }
        if ($result.Failed) { Show-Dialog -Title (Tr 'Ajouter des membres') -Message ($result.Failed -join "`n") -Owner (Get-DetailOwner $state) }
    }
}

function Get-GroupListedMember($State) {
    # The distinguished names of the direct members a Propriétés lists (none: not open, or not read yet), which the
    # picker leaves out; the group itself is left out by the picker.
    if (-not $State -or -not $State.Detail) { return @() }
    @($State.Detail.Members.List | Where-Object Membership -eq 'Directe' | ForEach-Object DistinguishedName)
}

function Get-GroupMemberAddText($Row, $Result) {
    # What an addition did, for its notice: « Julie Bertrand ajouté à GG-Accueil. », $null when nothing was added.
    $added = @($Result.Added)
    if (-not $added.Count) { return $null }
    $text = if ($added.Count -eq 1) { Tr '{0} ajouté à {1}.' } else { Tr '{0} ajoutés à {1}.' }
    $text -f (Join-FrenchList $added), $Row.Name
}

function Show-GroupMemberPicker($Row, $Owner, [string[]]$Listed, $Context, [scriptblock]$OnDone) {
    # Ajouter des membres…, from a group's Propriétés or from the Groupes page: the users, computers and groups of the
    # group's domain whose name starts with the text, those $Listed (its direct members) and itself left out; each one
    # ticked is added, after a second confirmation when the group is a privileged one (Confirm-PrivilegedGroup, #233).
    # Then & $OnDone $Context $result (Add-GroupMemberList).
    $content = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border Style="{StaticResource Field}" Height="34">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search:14}}</Border>
      <TextBox x:Name="member_query" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Début du nom ou de l'identifiant (ex. bert, ORD-1)"/>
    </Grid>
  </Border>
  <Border Style="{StaticResource Card}" Margin="0,10,0,0" Height="240">
    <Grid>
      <ListBox x:Name="member_results" Background="Transparent" BorderThickness="0" SelectionMode="Multiple" AutomationProperties.Name="Comptes trouvés">
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
              <!-- Ticked as the account is chosen: a click on the row ticks or unticks it. -->
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
      <TextBlock x:Name="member_hint" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" Margin="16"
                 Text="Tapez le début d'un nom : utilisateurs, ordinateurs ou groupes."/>
    </Grid>
  </Border>
</StackPanel>
'@))
    # Those listed are left out of the choices (one not listed is refused by AD, and said).
    $already = @($Listed) + $Row.DistinguishedName
    $content.Tag = @{ Domain = $Row.Domain; Already = $already; Timer = $null }
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(300)
    $timer.Tag = $content
    $timer.Add_Tick({ param($tick) $tick.Stop(); Find-GroupMemberChoice $tick.Tag })
    $content.Tag.Timer = $timer
    # Searched once the typing pauses, so each letter doesn't query AD.
    $content.FindName('member_query').Add_TextChanged({ param($box) $timer = $box.Parent.Parent.Parent.Tag.Timer; $timer.Stop(); $timer.Start() })
    $content.FindName('member_query').Add_KeyDown({
        $e = $args[1]
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Find-GroupMemberChoice $args[0].Parent.Parent.Parent }
    })
    $content.Add_Loaded({ param($panel) $null = $panel.FindName('member_query').Focus() })

    Show-Dialog -Title (Tr 'Ajouter des membres') -Heading ((Tr 'Ajouter des membres à {0}') -f $Row.Name) -Icon 'users' -Owner $Owner `
        -Message ((Tr 'Cochez un ou plusieurs comptes de {0}.') -f $Row.Domain) -Content $content -PickFrom $content.FindName('member_results') -OkText (Tr 'Ajouter') `
        -State @{ Row = $Row; Owner = $Owner; Context = $Context; OnDone = $OnDone; Content = $content; Members = @() } -OnOk {
        param($dialog)
        $dialog.Members = @($dialog.Content.FindName('member_results').SelectedItems)
        if (-not $dialog.Members.Count) { return }
        # The group is read again for its adminCount and SID: a group row doesn't carry them. One that can't be read
        # is added to as any other: AD says what it refuses.
        $group = try { Get-ADGroup -Server $dialog.Row.Domain -Identity $dialog.Row.DistinguishedName -Properties adminCount -ErrorAction Stop } catch { $null }
        $target = [pscustomobject]@{ Name = $dialog.Row.Name; Privileged = [bool]($group -and (Test-PrivilegedGroup $group)) }
        $who = if ($dialog.Members.Count -eq 1) { [string]$dialog.Members[0].Name } else { (Tr '{0} comptes') -f $dialog.Members.Count }
        Confirm-PrivilegedGroup @($target) $who $dialog.Owner $dialog {
            param($dialog)
            Start-GroupMemberWrite $true $dialog.Row $dialog.Members $dialog.Owner $dialog.Context $dialog.OnDone
        }
    }
}

function Add-GroupMemberList($Row, $Members) {
    # The members ($Members: the picker's items) into the group, one by one, as Added (their names) and Failed (a line
    # for each AD refused). On a search runspace (Start-GroupMemberWrite): each one's Problem as it goes too
    # (Add-WriteProgress, by index).
    $added = [System.Collections.Generic.List[string]]::new()
    $Members = @($Members)
    $failed = for ($i = 0; $i -lt $Members.Count; $i++) {
        $member = $Members[$i]
        try {
            # On the DC the window reads again (Invoke-UserChange: the PDC), so the member shows at once (#256).
            $null = Invoke-UserChange $Row.Domain { param($server) Add-ADGroupMember -Server $server -Identity $Row.DistinguishedName -Members $member.DistinguishedName -ErrorAction Stop }
            $added.Add($member.Name)
            Add-WriteProgress $i @{ Problem = $null }
        }
        catch {
            Add-WriteProgress $i @{ Problem = $_.Exception.Message }
            (Tr '✖ {0} : non ajouté à {1} ({2})') -f $member.Name, $Row.Name, $_.Exception.Message
        }
    }
    @{ Added = @($added); Failed = @($failed) }
}

function Start-GroupMemberWrite([bool]$Add, $Row, $Members, $Window, $Context, [scriptblock]$OnDone) {
    # Ajouter des membres… ($Add) or Retirer… of a group, in the background (Add-GroupMemberList,
    # Remove-GroupMemberList, Start-ADWrite): $Window, the window it was asked from, stays usable, its pointer saying it
    # runs; a member already being added or removed is left out. Then, on the window's thread, & $OnDone $Context
    # $result: Added or Removed, the names done; Failed, a line for each refused, or perhaps done (its DC didn't answer
    # in time: Get-WriteAnswer).
    $key = { param($member) "Member|$($Row.Domain)|$($Row.DistinguishedName)|$($member.DistinguishedName)" }
    $pending = @($Members | Where-Object { -not (Test-ADWriteBusy (& $key $_)) })
    if (-not $pending.Count) { return }
    # Copies, as a runspace needs them: a picker's item has neither Domain nor Kind.
    $copies = @(foreach ($member in $pending) {
        $has = $member.PSObject.Properties
        [pscustomobject]@{
            Name = [string]$member.Name; DistinguishedName = [string]$member.DistinguishedName
            Domain = [string]$(if ($has['Domain']) { $member.Domain }); Kind = [string]$(if ($has['Kind']) { $member.Kind })
        }
    })
    $group = [pscustomobject]@{ Name = [string]$Row.Name; Domain = [string]$Row.Domain; DistinguishedName = [string]$Row.DistinguishedName }
    $null = Start-ADWrite -Keys @($pending | ForEach-Object { & $key $_ }) -Command $(if ($Add) { 'Add-GroupMemberList' } else { 'Remove-GroupMemberList' }) `
        -Arguments @($group, $copies) -Functions 'Get-GroupMemberObject' -Variables @{ MemberReadKinds = $script:MemberReadKinds } -Count $copies.Count -Window $Window `
        -Context @{ Add = $Add; Group = $group; Members = $copies; Context = $Context; OnDone = $OnDone } -OnDone {
        param($write, $outcome)
        Complete-GroupMemberWrite $write $outcome
    }
}

function Complete-GroupMemberWrite($Write, $Outcome) {
    # Start-GroupMemberWrite's change: each member's line from what it did (Get-WriteAnswer), then its OnDone.
    $done = [System.Collections.Generic.List[string]]::new()
    $failed = @(for ($i = 0; $i -lt $Write.Members.Count; $i++) {
        $member = $Write.Members[$i]
        $answer = Get-WriteAnswer $Outcome $i
        if ($answer.Unsure) { (Tr '⚠ {0} : {1}') -f $member.Name, (Get-WriteUnsureText $Outcome.Timeout) }
        elseif ($answer.Problem) {
            $format = if ($Write.Add) { Tr '✖ {0} : non ajouté à {1} ({2})' } else { Tr '✖ {0} : non retiré de {1} ({2})' }
            $format -f $member.Name, $Write.Group.Name, $answer.Problem
        }
        else { $done.Add($member.Name) }
    })
    $result = if ($Write.Add) { @{ Added = @($done); Failed = $failed } } else { @{ Removed = @($done); Failed = $failed } }
    & $Write.OnDone $Write.Context $result
}

function Find-GroupMemberChoice($Content) {
    # The users (by name, login or email: AD's ambiguous name resolution), computers and groups whose name starts with
    # the text, in the group's domain: 50 at most, users first, searched in the background. Those ticked stay, at the
    # top, so a user and a computer can be added at once. An answer for a text since changed is left.
    $text = "$($Content.FindName('member_query').Text)".Trim()
    $hint = $Content.FindName('member_hint')
    if (-not $text) {
        Show-GroupMemberChoice $Content @()
        $hint.Text = Tr "Tapez le début d'un nom : utilisateurs, ordinateurs ou groupes."
        $hint.Visibility = if ($Content.FindName('member_results').Items.Count) { 'Collapsed' } else { 'Visible' }
        return
    }
    if (-not $Content.FindName('member_results').Items.Count) { $hint.Text = Tr 'Recherche…'; $hint.Visibility = 'Visible' }
    Start-BackgroundRead -Command 'Get-GroupMemberChoice' -Arguments @($Content.Tag.Domain, $text, $Content.Tag.Already) -Functions 'Get-LdapText' `
        -Variables (Get-DetailReadVariable) -Context @{ Content = $Content; Text = $text } -OnDone {
        param($context, $found, $problem)
        $content = $context.Content
        if ("$($content.FindName('member_query').Text)".Trim() -ne $context.Text) { return }
        $hint = $content.FindName('member_hint')
        if ($problem) { $hint.Text = (Tr 'Recherche impossible : {0}') -f (ConvertTo-FrenchError $problem); $hint.Visibility = 'Visible'; return }
        Show-GroupMemberChoice $content @($found.Items)
        $hint.Text = (Tr 'Aucun compte dont le nom commence par « {0} ».') -f $context.Text
        $hint.Visibility = if ($content.FindName('member_results').Items.Count) { 'Collapsed' } else { 'Visible' }
    }
}

function Show-GroupMemberChoice($Content, $Items) {
    # The list: what's ticked first (still ticked), then $Items not among them.
    $list = $Content.FindName('member_results')
    $kept = @($list.SelectedItems)
    $list.Items.Clear()
    foreach ($item in $kept) {
        $null = $list.Items.Add($item)
        $null = $list.SelectedItems.Add($item)
    }
    $keptNames = @($kept | ForEach-Object DistinguishedName)
    foreach ($item in $Items) { if ($keptNames -notcontains $item.DistinguishedName) { $null = $list.Items.Add($item) } }
}

function Get-GroupMemberChoice([string]$Domain, [string]$Text, [string[]]$Already) {
    # The users, computers and groups of $Domain whose name starts with $Text, those in $Already left out: as Items.
    # It runs at each pause in the typing, from the first letter: each search asks AD for no more than can be shown (50,
    # and those in $Already, left out after), so « a » doesn't make the DC send every account that starts with it.
    $ldap = Get-LdapText $Text
    $size = 50 + @($Already).Count
    $found = @(
        Get-ADUser -Server $Domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(anr=$ldap))" -ResultSetSize $size -ErrorAction Stop |
            ForEach-Object { @{ Object = $_; Kind = Tr 'Utilisateur'; Login = $_.SamAccountName } }
        Get-ADComputer -Server $Domain -Filter "Name -like '$($Text -replace "'", "''")*'" -ResultSetSize $size -ErrorAction Stop |
            ForEach-Object { @{ Object = $_; Kind = Tr 'Ordinateur'; Login = '' } }
        Get-ADGroup -Server $Domain -LDAPFilter "(&(objectCategory=group)(anr=$ldap))" -ResultSetSize $size -ErrorAction Stop |
            ForEach-Object { @{ Object = $_; Kind = Tr 'Groupe'; Login = '' } }
    ) | Where-Object { $Already -notcontains [string]$_.Object.DistinguishedName } | Select-Object -First 50
    @{ Items = @(foreach ($entry in $found) {
        $dn = [string]$entry.Object.DistinguishedName
        [pscustomobject]@{ Name = [string]$entry.Object.Name; DistinguishedName = $dn; Details = (@($entry.Kind, $entry.Login, (Get-OUPath $dn)) | Where-Object { $_ }) -join ' · ' }
    }) }
}

function Remove-GroupMember($State) {
    # Retirer…: the direct members ticked out of the group, after one confirmation that names them.
    $row = $State.Row
    $members = @($State.Picks | Where-Object IsChecked | ForEach-Object Tag)
    if (-not $members.Count) { return }
    $names = @($members | ForEach-Object Name)
    $one = $members.Count -eq 1
    $heading = if ($one) { (Tr 'Retirer {0} de {1} ?') -f $names[0], $row.Name } else { (Tr 'Retirer {0} membres de {1} ?') -f $members.Count, $row.Name }
    $message = if ([string]$State.Detail.Group.GroupCategory -eq 'Security') {
        if ($one) { Tr 'Il perd les accès donnés par ce groupe à la prochaine ouverture de session (au redémarrage pour un ordinateur).' }
        else { Tr 'Ils perdent les accès donnés par ce groupe à la prochaine ouverture de session (au redémarrage pour un ordinateur).' }
    }
    elseif ($one) { Tr 'Il ne recevra plus ce qui est envoyé à la liste.' }
    else { Tr 'Ils ne recevront plus ce qui est envoyé à la liste.' }
    Show-Dialog -Title (Tr 'Retirer du groupe') -Heading $heading -Names $(if ($members.Count -gt 1) { $names }) -Icon 'users' -Tone 'danger' -Owner $State.Window `
        -Message $message -OkText (Tr 'Retirer') -CancelIsDefault -State @{ Detail = $State; Members = $members } -OnOk {
        param($dialog)
        $state = $dialog.Detail
        # In the background (Start-GroupMemberWrite), then the window read again. Closed meanwhile: what failed is
        # said over the main window.
        Start-GroupMemberWrite $false $state.Row $dialog.Members $state.Window $state {
            param($state, $result)
            $removed = @($result.Removed)
            $open = -not $state['Closed']
            if ($open) { Update-GroupDetail $state }
            if ($removed.Count -and $open) {
                $text = if ($removed.Count -eq 1) { Tr '{0} retiré de {1}.' } else { Tr '{0} retirés de {1}.' }
                Show-DetailNotice $state ($text -f (Join-FrenchList $removed), $state.Row.Name)
            }
            if ($result.Failed.Count) { Show-Dialog -Title (Tr 'Retirer du groupe') -Message ($result.Failed -join "`n") -Owner (Get-DetailOwner $state) }
        }
    }
}

function Remove-GroupMemberList($Row, $Members) {
    # Each member (Read-GroupMember's) out of the group, one at a time so one refused doesn't keep the others in:
    # Removed, their names, and Failed, a line each for the others. A member of another domain (a universal or domain
    # local group's) goes as read in its own domain, which the group's DC can't find by DN (Get-GroupMemberObject); a
    # foreign security principal is in the group's domain, by DN as before. A domain that doesn't answer is tried once:
    # its other members fail with the same reason, rather than a timeout each. On a search runspace
    # (Start-GroupMemberWrite): each one's Problem as it goes too (Add-WriteProgress, by index).
    $removed = [System.Collections.Generic.List[string]]::new()
    $read = @{}
    $down = @{}
    $Members = @($Members)
    $failed = @(for ($i = 0; $i -lt $Members.Count; $i++) {
        $member = $Members[$i]
        $why = $down[[string]$member.Domain]
        if (-not $why) {
            try { $as = Get-GroupMemberObject @{ Domain = $member.Domain; DistinguishedName = $member.DistinguishedName; Kind = $script:MemberReadKinds[$member.Kind] } $Row.Domain $read }
            catch {
                $why = $_.Exception.Message
                # Only the domain's silence counts for its others: one member not found says nothing of them.
                if (Test-ServerDown $_) { $down[[string]$member.Domain] = $why }
            }
        }
        if (-not $why) {
            try {
                # On the DC the window reads again (Invoke-UserChange: the PDC), so it shows at once (#256).
                $null = Invoke-UserChange $Row.Domain { param($server) Remove-ADGroupMember -Server $server -Identity $Row.DistinguishedName -Members $as -Confirm:$false -ErrorAction Stop }
                $removed.Add($member.Name)
                Add-WriteProgress $i @{ Problem = $null }
                continue
            }
            catch { $why = $_.Exception.Message }
        }
        Add-WriteProgress $i @{ Problem = $why }
        (Tr '✖ {0} : non retiré de {1} ({2})') -f $member.Name, $Row.Name, $why
    })
    @{ Removed = $removed; Failed = $failed }
}

function Get-GroupDetailText($State) {
    # Copier: the group, the members listed (as searched) and the groups it belongs to, as text.
    $detail = $State.Detail
    $members = $detail.Members
    $count = $members.List.Count
    $filter = $members.Filter
    $heading = if ($members.Truncated -and $filter) { (Tr 'Membres (les {0} premiers) dont le nom commence par « {1} »') -f $count, $filter }
               elseif ($members.Truncated) { (Tr 'Membres (les {0} premiers)') -f $count }
               elseif ($filter) { (Tr 'Membres dont le nom commence par « {0} »') -f $filter }
               else { Tr 'Membres' }
    $lines = @("$($State.Row.Name) ($($State.Row.Domain))", '', $heading)
    # Kind and Membership are keys: said through Tr.
    foreach ($member in $members.List) { $lines += "  $($member.Name) ($((@((Tr $member.Kind), $member.Login, (Tr $member.Membership)) | Where-Object { $_ }) -join ', '))" }
    $lines += '', (Tr 'Membre de')
    foreach ($parent in $detail.Parents) { $lines += "  $($parent.Name) ($(Tr $parent.Membership))" }
    $lines += '', (Tr 'Groupe')
    foreach ($entry in (Get-GroupDetailSection $detail).Groupe) { $lines += '  ' + ((Tr '{0} : {1}') -f $entry[0], $(if ("$($entry[1])") { $entry[1] } else { '—' })) }
    $lines -join [Environment]::NewLine
}

function Show-GroupDetail($Row, $Owner, $Icon) {
    # The window opens at once, « Lecture… »; the group is read in the background.
    $state = @{ Row = $Row; Detail = $null; Picks = $null; Update = 'Update-GroupDetail'; Read = 'Get-GroupDetailRead'; CopyText = 'Get-GroupDetailText'; MemberFilter = '' }
    # The members' search waits for the typing to pause, so each letter doesn't query AD.
    $state.FilterTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $state.FilterTimer.Interval = [timespan]::FromMilliseconds(400)
    $state.FilterTimer.Tag = $state
    $state.FilterTimer.Add_Tick({ param($timer) Update-GroupMemberSearch $timer.Tag })
    Show-DetailWindow $state 'group_detail' ((Tr 'Propriétés de {0}') -f $Row.Name) $Owner $Icon
}
