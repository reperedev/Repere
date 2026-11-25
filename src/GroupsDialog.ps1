# Groupes…: the AD groups a computer belongs to, in a window of their own. Its direct groups (memberOf), its primary
# group (usually Ordinateurs du domaine, which memberOf leaves out), and the security groups it belongs to through
# other groups (tokenGroups). Viewing only. Dot-sourced by the main script, after Theme.ps1.

# A group's type and scope as the lists show them, in this run's language: only shown, sorted and filtered, never
# compared (GroupCategory and GroupScope are).
$script:GroupTypes = @{ Security = (Tr 'Sécurité'); Distribution = (Tr 'Distribution') }
$script:GroupScopes = @{ Global = (Tr 'Globale'); DomainLocal = (Tr 'Domaine local'); Universal = (Tr 'Universelle') }

function Get-DomainOfDN([string]$DistinguishedName) {
    # CN=GG-Office,OU=Groupes,DC=demo,DC=local -> demo.local.
    (@($DistinguishedName -split '(?<!\\),' | Where-Object { $_ -like 'DC=*' } | ForEach-Object { $_.Substring(3) })) -join '.'
}

function Get-ComputerGroup($Computer) {
    $object = Get-ADComputer -Server $Computer.Domain -Identity $Computer.DistinguishedName -Properties MemberOf, PrimaryGroup -ErrorAction Stop
    Get-ObjectGroup $object $Computer.Domain (Read-TokenGroup { Get-ADComputer -Server $Computer.Domain -Identity $Computer.DistinguishedName -Properties tokenGroups -ErrorAction Stop })
}

function Read-TokenGroup([scriptblock]$Read) {
    # tokenGroups on its own, after the rest: a hardened domain can refuse it to whoever reads, and that then only leaves
    # out the inherited groups (Problem says why) instead of the whole object.
    try { @{ Sids = @((& $Read).tokenGroups | Where-Object { $_ } | ForEach-Object { [string]$_ }); Problem = $null } }
    catch { @{ Sids = @(); Problem = $_.Exception.Message } }
}

# Each domain's SID, read once a session (Get-DomainOfSid): shared with the reads' runspaces, hence synchronized.
$script:DomainSidMap = [hashtable]::Synchronized(@{})

function Get-DomainOfSid([string]$Sid, [string]$Default) {
    # The domain a group's SID is of: the one whose SID starts it (without its last part). $Default when none (a SID of
    # another forest, or of a domain that can't be read).
    foreach ($domain in @($script:domainList)) {
        if ($script:DomainSidMap.ContainsKey("domain:$domain")) { continue }
        $script:DomainSidMap["domain:$domain"] = $true
        try { $script:DomainSidMap[[string](Get-ADDomain -Server $domain -ErrorAction Stop).DomainSID] = $domain }
        catch { Write-Verbose "SID de $domain non lu : $_" }
    }
    $prefix = $Sid.Substring(0, [Math]::Max(0, $Sid.LastIndexOf('-')))
    if ($script:DomainSidMap.ContainsKey($prefix)) { $script:DomainSidMap[$prefix] } else { $Default }
}

function Get-ObjectGroup($Object, [string]$Domain, $Inherited) {
    # The groups of a computer, user or group read with MemberOf, PrimaryGroup and tokenGroups, each with its Name, Type, Scope,
    # Membership (Directe, Principale or Héritée: a key, compared and sorted on, in French in every language; Tr says
    # it), Domain, Description and DistinguishedName, read in the domain that
    # holds each group. A group that can't be read is listed by its DN or SID, with the reason in its description (as
    # the lists show it), rather than left out. A group's MemberOf and PrimaryGroup are read the same way (it
    # has no primary group, nor tokenGroups when not asked for: a property missing is read as none, strict mode or
    # not). The groups are read 50 at a time, not one by one. $Inherited: the tokenGroups read on their own
    # (Read-TokenGroup), or those of $Object; their groups are read in the domain each is of, and one row says why they
    # couldn't be read.
    $seen = @{}
    $row = {
        param($Group, [string]$Membership)
        $seen[[string]$Group.SID] = $true
        [pscustomobject]@{
            Name        = [string]$Group.Name
            Type        = $script:GroupTypes[[string]$Group.GroupCategory]
            Scope       = $script:GroupScopes[[string]$Group.GroupScope]
            Membership  = $Membership
            Domain      = Get-DomainOfDN $Group.DistinguishedName
            Description = [string]$Group.Description
            DistinguishedName = [string]$Group.DistinguishedName
        }
    }
    $read = {
        param([string]$Identity, [string]$Server, [string]$Membership)
        try { & $row (Get-ADGroup -Server $Server -Identity $Identity -Properties Description -ErrorAction Stop) $Membership }
        catch {
            [pscustomobject]@{ Name = $Identity; Type = ''; Scope = ''; Membership = $Membership; Domain = $Server; Description = (Tr 'non lu : {0}') -f (ConvertTo-FrenchError $_.Exception.Message); DistinguishedName = $Identity }
        }
    }
    # Many groups at once: up to 50 per search, by DN or by SID (an OR of them), each in its server; those a search
    # doesn't return are read one by one, so the reason they can't be is said.
    $readMany = {
        param([string[]]$Keys, [string]$Attribute, [string]$Membership, [scriptblock]$ServerOf)
        $byServer = [ordered]@{}
        foreach ($key in $Keys) {
            $server = & $ServerOf $key
            if (-not $byServer.Contains($server)) { $byServer[$server] = [System.Collections.Generic.List[string]]::new() }
            $byServer[$server].Add($key)
        }
        foreach ($server in $byServer.Keys) {
            $serverKeys = @($byServer[$server])
            for ($start = 0; $start -lt $serverKeys.Count; $start += 50) {
                $chunk = @($serverKeys[$start..([Math]::Min($start + 49, $serverKeys.Count - 1))])
                $found = @{}
                try {
                    $filter = "(|$(-join ($chunk | ForEach-Object { "($Attribute=$(Get-LdapText $_))" })))"
                    foreach ($group in @(Get-ADGroup -Server $server -LDAPFilter $filter -Properties Description -ErrorAction Stop)) {
                        $found[$(if ($Attribute -eq 'objectSid') { [string]$group.SID } else { [string]$group.DistinguishedName })] = $true
                        & $row $group $Membership
                    }
                }
                catch { Write-Verbose "Groupes lus un par un ($server) : $_" }
                foreach ($key in $chunk) { if (-not $found.ContainsKey($key)) { & $read $key $server $Membership } }
            }
        }
    }
    $groups = @(
        & $readMany @($object.MemberOf | Where-Object { $_ } | ForEach-Object { [string]$_ }) 'distinguishedName' 'Directe' { param($dn) Get-DomainOfDN $dn }
        $primary = $object.PSObject.Properties['PrimaryGroup']
        if ($primary -and $primary.Value) { & $read $primary.Value (Get-DomainOfDN $primary.Value) 'Principale' }
    )
    # The groups of the forest's other domains that list it: a DC knows only its own domain's member lists, so MemberOf
    # leaves out a domain local group of another domain, and a universal one when the DC isn't a global catalog. One
    # search per other domain (none with a single domain); a domain that can't be searched is said in a row.
    $listed = @{}
    foreach ($group in $groups) { $listed[[string]$group.DistinguishedName] = $true }
    $groups += @(foreach ($other in @($script:domainList | Where-Object { $_ -and $_ -ne $Domain })) {
        try {
            foreach ($group in @(Get-ADGroup -Server $other -LDAPFilter "(member=$(Get-LdapText ([string]$object.DistinguishedName)))" -Properties Description -ErrorAction Stop)) {
                if (-not $listed.ContainsKey([string]$group.DistinguishedName)) { & $row $group 'Directe' }
            }
        }
        catch { [pscustomobject]@{ Name = $other; Type = ''; Scope = ''; Membership = 'Directe'; Domain = $other; Description = (Tr 'groupes de ce domaine non lus : {0}') -f (ConvertTo-FrenchError $_.Exception.Message); DistinguishedName = $other } }
    })
    # tokenGroups: every security group, nested ones included. Those not already listed come through other groups. A
    # group's Propriétés doesn't read it: none then.
    $tokens = $object.PSObject.Properties['tokenGroups']
    $sids = if ($Inherited) { $Inherited.Sids } elseif ($tokens) { @($tokens.Value | Where-Object { $_ } | ForEach-Object { [string]$_ }) } else { @() }
    $unseen = @($sids | Where-Object { -not $seen.ContainsKey($_) })
    # (Not $inherited: that's $Inherited, names ignoring case.)
    $throughOthers = @(& $readMany $unseen 'objectSid' 'Héritée' { param($sid) Get-DomainOfSid $sid $Domain })
    if ($Inherited -and $Inherited.Problem) {
        $throughOthers += [pscustomobject]@{ Name = (Tr 'Groupes hérités'); Type = ''; Scope = ''; Membership = 'Héritée'; Domain = $Domain; Description = (Tr 'non lus : {0}') -f (ConvertTo-FrenchError $Inherited.Problem); DistinguishedName = '' }
    }
    $order = @{ Directe = 0; Principale = 1; 'Héritée' = 2 }
    @($groups) + @($throughOthers) | Sort-Object { $order[$_.Membership] }, Name
}

$script:GroupsDialogXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Padding="18" Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <DockPanel>
    <StackPanel DockPanel.Dock="Top">
      <TextBlock x:Name="groups_title" FontSize="15" FontWeight="{DynamicResource R.FontWeightStrong}" TextWrapping="Wrap"/>
      <TextBlock x:Name="groups_summary" Style="{StaticResource Txt.Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
      <Border Style="{StaticResource Field}" Height="34" Margin="0,12,0,10" HorizontalAlignment="Left" Width="300">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
          <TextBox x:Name="groups_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les groupes"/>
        </Grid>
      </Border>
    </StackPanel>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="groups_copy" MinWidth="90" ToolTip="Une ligne par groupe, colonnes séparées par des tabulations (à coller dans Excel)">
        <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="dialog_cancel" Style="{StaticResource Btn.Primary}" MinWidth="90" Margin="8,0,0,0" IsDefault="True" IsCancel="True" Content="Fermer"/>
    </StackPanel>
    <Border Style="{StaticResource Card}">
      <DataGrid x:Name="groups_grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True" CanUserResizeColumns="True"
                CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Extended" SelectionUnit="FullRow" HeadersVisibility="Column"
                GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{DynamicResource R.Border}" Background="Transparent" RowBackground="Transparent"
                Foreground="{DynamicResource R.Text}" BorderThickness="0" RowHeight="34" Margin="1" Height="320"
                RowStyle="{StaticResource Grid.Row}" CellStyle="{StaticResource Grid.Cell}" ColumnHeaderStyle="{StaticResource Grid.Header}">
        <DataGrid.Columns>
          <DataGridTextColumn Header="Groupe" Binding="{Binding Name}" Width="190" ElementStyle="{StaticResource Grid.Text.Strong}"/>
          <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="95" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Étendue" Binding="{Binding Scope}" Width="110" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Appartenance" Binding="{Binding MembershipText}" Width="110" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Domaine" Binding="{Binding Domain}" Width="130" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="*" ElementStyle="{StaticResource Grid.Text}"/>
        </DataGrid.Columns>
      </DataGrid>
    </Border>
  </DockPanel>
</Border>
'@

function Read-ComputerGroup($Computer) {
    # On a search runspace: the computer's groups, as one object (a read gives back the last one written).
    @{ Groups = @(Get-ComputerGroup $Computer) }
}

function Show-GroupsDialog($Computer, $Owner, $Icon) {
    # Reads the groups first, in the background: a slow domain doesn't freeze the window, and an error is reported like
    # the other actions instead of an empty window.
    Start-WindowRead -Kind 'Groups' -Command 'Read-ComputerGroup' -Arguments @(ConvertTo-ReadComputer $Computer) `
        -Functions 'Get-ComputerGroup', 'Get-ObjectGroup', 'Read-TokenGroup', 'Get-DomainOfSid', 'Get-DomainOfDN', 'Get-LdapText' `
        -Variables (Get-DetailReadVariable) -Context @{ Computer = $Computer; Owner = $Owner; Icon = $Icon } -OnDone {
        param($context, $read, $problem)
        if ($problem -or -not $read) {
            $reason = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
            Show-ActionReport @((Tr '✖ {0} : groupes non lus ({1})') -f $context.Computer.ComputerName, $reason) -Title (Tr 'Groupes')
            return
        }
        Show-GroupsWindow $context.Computer @($read.Groups) $context.Owner $context.Icon
    }
}

function Show-GroupsWindow($Computer, $Groups, $Owner, $Icon) {
    # The groups read (Show-GroupsDialog), in their window.
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:GroupsDialogXaml))
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = (Tr 'Groupes de {0}') -f $Computer.ComputerName
    $dialog.Icon = $Icon
    $dialog.Owner = $Owner
    $dialog.Width = 900
    $dialog.SizeToContent = 'Height'
    $dialog.MinWidth = 640
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.Content = $root
    Set-WindowChrome $dialog

    $count = @{ Directe = @($groups | Where-Object Membership -eq 'Directe').Count; 'Héritée' = @($groups | Where-Object Membership -eq 'Héritée').Count }
    $root.FindName('groups_title').Text = (Tr 'Groupes de {0}') -f $Computer.ComputerName
    # Each count with its own singular and plural (in English; French keeps its « (s) »).
    $direct = if ($count.Directe -eq 1) { Tr '1 groupe(s) direct(s)' } else { (Tr '{0} groupe(s) direct(s)') -f $count.Directe }
    $inherited = if ($count.'Héritée' -eq 1) { Tr '1 groupe(s) de sécurité hérité(s)' } else { (Tr '{0} groupe(s) de sécurité hérité(s)') -f $count.'Héritée' }
    $root.FindName('groups_summary').Text = (Tr "{0}, le groupe principal et {1} par d'autres groupes. Lecture seule.") -f $direct, $inherited

    # Each row with its membership as shown (MembershipText): Membership stays the key.
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($group in $groups) { $rows.Add(($group | Add-Member -NotePropertyName MembershipText -NotePropertyValue (Tr $group.Membership) -Force -PassThru)) }
    $grid = $root.FindName('groups_grid')
    $grid.ItemsSource = $rows
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($rows)
    $state = @{ View = $view; Grid = $grid; Filter = '' }
    $dialog.Tag = $state
    $view.Filter = [Predicate[object]]{
        param($row)
        $query = $state.Filter
        -not $query -or "$($row.Name) $($row.Description) $($row.Type) $($row.Scope) $($row.MembershipText) $($row.Domain)".ToLowerInvariant().Contains($query)
    }.GetNewClosure()

    $root.FindName('groups_filter').Add_TextChanged({
        param($box)
        $state = [System.Windows.Window]::GetWindow($box).Tag
        $state.Filter = "$($box.Text)".Trim().ToLowerInvariant()
        $state.View.Refresh()
    })
    $root.FindName('groups_copy').Add_Click({ param($button) Copy-GroupsWindow ([System.Windows.Window]::GetWindow($button).Tag) $button })

    $script:search.Dialogs++
    try { $null = $dialog.ShowDialog() }
    finally { $script:search.Dialogs-- }
}

function Copy-GroupsWindow($State, [System.Windows.Controls.Button]$Button) {
    # Copier: the groups shown, with a header line, separated by tabs: pasted in Excel, each value lands in its column,
    # and a description that starts with = stays text (Format-RowLine, #251).
    # The button says whether it copied (#248): another program can hold the clipboard, and nothing then is.
    $lines = @((@((Tr 'Groupe'), (Tr 'Type'), (Tr 'Étendue'), (Tr 'Appartenance'), (Tr 'Domaine'), (Tr 'Description')) -join "`t")) + @(foreach ($row in $State.View) {
        Format-RowLine @($row.Name, $row.Type, $row.Scope, $row.MembershipText, $row.Domain, $row.Description)
    })
    Show-CopyFeedback $Button (Set-ClipboardText ($lines -join [Environment]::NewLine))
}
