# Groupes: the main window's third page (its tab in the title bar). Groups are found by name or description, or from a
# pasted list of names, or listed when they have no member, in one domain or all of them, in the background like users.
# Propriétés… opens a group: its members, added or removed, and the groups it belongs to (GroupDetails.ps1); Ajouter des
# membres… adds to one group without opening it (the same picker). Deleting groups is left out, like users.
# Its search, count, filter, Exporter, Copier, keys and columns are those of Utilisateurs (SearchPage.ps1): the page
# hashtable says what's the groups'. Dot-sourced by the main script, after SearchPage.ps1 and GroupsDialog.ps1.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

# The search types: the LDAP clause each adds, whether it needs text (« Sans membres » alone lists every group of the
# domain that lists no member), what its text matches, and what the scope then says. Name and description are matched
# anywhere: groups are named GG-…, DL-… and the like. Each type is known by its name as shown, in this run's language
# (the search type box lists the keys, and gives back the one chosen): none is saved.
$script:GroupSearchTypes = [ordered]@{
    (Tr 'Nom contient')         = @{ Id = 'Name'; Clause = ''; NeedsText = $true; Match = '(name=*{0}*)'; Prompt = (Tr "Entrez une partie du nom d'un groupe")
                                     Tag = (Tr 'Une partie du nom (ex. vpn)'); Tip = (Tr 'Une partie du nom du groupe (Ctrl+F)') }
    (Tr 'Description contient') = @{ Id = 'Description'; Clause = ''; NeedsText = $true; Match = '(description=*{0}*)'; Prompt = (Tr 'Entrez une partie de la description')
                                     Tag = (Tr 'Une partie de la description (ex. imprimantes)'); Tip = (Tr 'Une partie de la description (Ctrl+F)') }
    (Tr 'Sans membres')         = @{ Id = 'Empty'; Clause = '(!(member=*))'; NeedsText = $false; Match = '(name=*{0}*)'; ScopeText = (Tr 'sans membres'); Tag = (Tr 'Nom (facultatif)')
                                     Tip = (Tr 'Facultatif : une partie du nom du groupe (Ctrl+F)') }
    # Whole names, or pre-Windows 2000 names.
    (Tr 'Liste de noms')        = @{ Id = 'List'; Clause = ''; NeedsText = $true; List = 'ConvertTo-GroupEntryList'
                                     ListMatch = { param($Entry) "(name=$Entry)(sAMAccountName=$Entry)" }
                                     Prompt = (Tr 'Entrez les noms des groupes (ex. GG-Accueil, GG-VPN)')
                                     TooMany = (Tr 'Au plus {0} noms à la fois ({1} entrés)')
                                     Tag = (Tr 'Noms séparés par des virgules (ex. GG-Accueil, GG-VPN)')
                                     Tip = (Tr 'Noms entiers, séparés par des virgules (Ctrl+F)') }
}

# A group search, in a search runspace: the groups of one domain, as rows. Their members aren't read (a group can hold
# thousands): its Propriétés lists them, a few at a time. Get-OUPath comes from ComputerPage.ps1's $rowBuilderScript.
$script:GroupSearchScript = {
    param([string]$Domain, [string]$LdapFilter, [string]$RowBuilder, [int]$Limit, [string[]]$Entries, [bool]$Empty, $Clock)
    try {
        if (-not (Get-Command Get-OUPath -ErrorAction SilentlyContinue)) { . ([scriptblock]::Create($RowBuilder)) }
        # The page's time limit counts from here, until AD answers: its first object, or the end of a query that found
        # none (New-SearchClock).
        if ($Clock) { $Clock.Started = [datetime]::UtcNow }
        $heard = { process { if ($Clock -and -not $Clock.Answered) { $Clock.Answered = $true }; $_ } end { if ($Clock) { $Clock.Answered = $true } } }
        # As GroupsDialog.ps1's $GroupTypes and $GroupScopes say them (Tr: the row builder's).
        $types = @{ Security = (Tr 'Sécurité'); Distribution = (Tr 'Distribution') }
        $scopes = @{ Global = (Tr 'Globale'); DomainLocal = (Tr 'Domaine local'); Universal = (Tr 'Universelle') }
        # $Limit at most (none when 0): AD is asked for one more, to tell there are others.
        $bounded = if ($Limit -gt 0) { @{ ResultSetSize = $Limit + 1 } } else { @{} }
        # How long AD took, then the rows: said in the search time's tooltip.
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        # Sans membres: AD doesn't list an account in its primary group's member, the account names that group by its
        # RID (primaryGroupID). So Utilisateurs du domaine, Ordinateurs du domaine and Contrôleurs de domaine list no
        # member, and aren't empty. The RIDs this domain's accounts have as primary group are read first: the accounts
        # whose primary group isn't one of the usual four (few), then one account at most for each of those four. A
        # group whose RID is one of them isn't shown. Every account has a primary group: one AD sends without it is one
        # whose primaryGroupID this user can't read (AD takes it as absent, so the (!(…)) clauses let it through), and
        # the domain's search fails, as it does when a search fails: a group isn't said empty when that can't be told.
        # Each RID is one group of this domain, so AD is asked for as many more groups as there are RIDs: the limit is
        # still that of the groups shown.
        $primary = [System.Collections.Generic.HashSet[string]]::new()
        if ($Empty) {
            $usual = '513', '515', '516', '521'
            $unusual = "(&(objectClass=user)$(-join @(foreach ($rid in $usual) { "(!(primaryGroupID=$rid))" })))"
            foreach ($account in @(Get-ADObject -Server $Domain -LDAPFilter $unusual -Properties primaryGroupID -ErrorAction Stop | & $heard)) {
                $rid = $account.PSObject.Properties['primaryGroupID']
                if (-not $rid -or "$($rid.Value)" -eq '') { throw ((Tr 'Groupe principal illisible pour {0} : impossible de dire quels groupes sont vides.') -f $account.Name) }
                $null = $primary.Add("$($rid.Value)")
            }
            foreach ($rid in $usual) {
                if (@(Get-ADObject -Server $Domain -LDAPFilter "(&(objectClass=user)(primaryGroupID=$rid))" -ResultSetSize 1 -ErrorAction Stop).Count) { $null = $primary.Add($rid) }
            }
            if ($Limit -gt 0) { $bounded.ResultSetSize = $Limit + 1 + $primary.Count }
        }
        $groups = @(Get-ADGroup -Server $Domain -LDAPFilter $LdapFilter -Properties Description, mail, ManagedBy @bounded -ErrorAction Stop | & $heard)
        # A domain's own groups (S-1-5-21-…), not the built-in ones (S-1-5-32-…), which are no one's primary group.
        if ($Empty) { $groups = @($groups | Where-Object { -not ("$($_.SID)" -match '^S-1-5-21-.+-(\d+)$' -and $primary.Contains($Matches[1])) }) }
        $queryTime = $watch.ElapsedMilliseconds
        $truncated = $Limit -gt 0 -and $groups.Count -gt $Limit
        if ($truncated) { $groups = @($groups | Select-Object -First $Limit) }
        $rows = foreach ($group in $groups) {
            # Géré par: the manager's name, from its DN (CN=Nathalie Lévy,OU=… -> Nathalie Lévy).
            $manager = if ($group.ManagedBy -match '^CN=((?:[^,\\]|\\.)+)') { $Matches[1] -replace '\\([,+"\\<>;=#])', '$1' }
            $row = [pscustomobject]@{
                Name              = [string]$group.Name
                SamAccountName    = [string]$group.SamAccountName
                Type              = $types[[string]$group.GroupCategory]
                Scope             = $scopes[[string]$group.GroupScope]
                Description       = [string]$group.Description
                Mail              = [string]$group.mail
                ManagedBy         = [string]$manager
                Domain            = $Domain
                DistinguishedName = [string]$group.DistinguishedName
                OUPath            = Get-OUPath ([string]$group.DistinguishedName)
                Text              = ''
            }
            $row.Text = "$($row.Name) $($row.SamAccountName) $($row.Type) $($row.Scope) $($row.Description) $($row.Mail) $($row.ManagedBy) $($row.OUPath)".ToLowerInvariant()
            $row
        }
        $rows = @($rows | Sort-Object Name)
        # Liste de noms: the entries these groups answer to, by name or pre-Windows 2000 name (whatever their case).
        $matched = @()
        if ($Entries) {
            $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($group in $groups) { foreach ($key in $group.Name, $group.SamAccountName) { if ($key) { $null = $keys.Add([string]$key) } } }
            $matched = @($Entries | Where-Object { $keys.Contains($_) })
        }
        [pscustomobject]@{ Domain = $Domain; Rows = $rows; Error = $null; Truncated = $truncated; Matched = $matched
                           Timing = @{ Query = $queryTime; Rows = $watch.ElapsedMilliseconds - $queryTime; Count = $rows.Count } }
    }
    catch {
        [pscustomobject]@{ Domain = $Domain; Rows = @(); Error = $_.Exception.Message; Truncated = $false; Matched = @(); Timing = $null }
    }
}.ToString()

# The page once built (Initialize-GroupPage), whether it's shown, its rows and the search under way, and what makes it
# the groups' page (SearchPage.ps1 says what each key is); its columns as the users' (Initialize-PageColumn).
$script:GroupPage = @{ Root = $null; Shown = $false; Rows = $null; View = $null; Search = $null; Timer = $null; Filter = ''; FilterTimer = $null; Errors = $null; MultiDomain = $false
                       LastRequest = $null; Truncated = $null; NotFound = @(); Unanswered = @(); TimedOut = @()
                       Prefix = 'group'; Types = $script:GroupSearchTypes; SearchSetting = 'Groups'
                       Ldap = '(&(objectCategory=group){0})'; Script = $script:GroupSearchScript
                       # Sans membres: leave out the groups that are someone's primary group.
                       Parameters = { param($Type) @{ Empty = $Type.Id -eq 'Empty' } }
                       Action = 'Update-GroupAction'; Detail = 'Show-GroupDetail'; RowProperty = 'Scope'
                       Copy = 'Name'; Copied = @{ Name = (Tr 'noms'); DistinguishedName = (Tr 'noms distinctifs') }
                       # The columns shown, each under its header and as it shows (Get-ExportField), then the
                       # distinguished name, always: Domaine shows only after a search of several domains.
                       Export = @{
                           Title = (Tr 'Exporter les groupes'); FileName = (Tr 'Repere_groupes_{0:yyyy-MM-dd}.csv')
                           Fields = @{}; Last = , @{ Header = (Tr 'Nom distinctif'); Value = 'DistinguishedName' }
                       }
                       Setting = 'GroupColumns'; Hidden = 'SamAccountName', 'Mail', 'ManagedBy'
                       # Each column's filter reads its own value, Nom's and Nom pré-Windows 2000's the text they contain (ColumnFilter.ps1).
                       ColumnFilter = $null; FilterSpecs = { @{ Name = @{ Mode = 'Text' }; SamAccountName = @{ Mode = 'Text' } } }
                       Columns = @{ ByKey = [ordered]@{}; Shown = @{}; Items = @{}; Default = $null; Loaded = ''; Updating = $false; Menu = $null } }

$script:GroupPageXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <!-- What can be done to the selected groups. -->
  <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.ActionRowMargin}">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal">
      <Button x:Name="group_details" Style="{StaticResource Btn.Primary}" Margin="0,0,8,0" IsEnabled="False" ToolTip="Le groupe, ses membres et les groupes dont il est membre (double-clic)">
        <StackPanel Orientation="Horizontal">{{icon:users}}<TextBlock Text="Propriétés…" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="group_add_members" Margin="0,0,8,0" IsEnabled="False" ToolTip="Ajouter des membres… (un groupe à la fois)" ToolTipService.ShowOnDisabled="True">
        <StackPanel Orientation="Horizontal">{{icon:userplus}}<TextBlock Text="Ajouter des membres…" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="group_copy" Style="{StaticResource Btn.Icon}" IsEnabled="False" ToolTip="Copier le nom (Ctrl+C)">{{icon:copy}}</Button>
    </StackPanel>
    <TextBlock x:Name="group_selection" Grid.Column="2" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Text="Aucune sélection"/>
  </Grid>

  <!-- The search: the domain, what to look for, the text. Entrée searches. Above the rows below it (ZIndex), for what a
       search is missing (group_search_hint). -->
  <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.SearchRowMargin}" Panel.ZIndex="1">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/>
      <ColumnDefinition Width="10"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <ComboBox x:Name="group_domain" MinWidth="170" Height="{DynamicResource R.BarHeight}" Margin="0,0,6,0" VerticalContentAlignment="Center" ToolTip="Domaine" ItemContainerStyle="{StaticResource Combo.Item}"/>
    <ComboBox x:Name="group_search_type" Grid.Column="1" MinWidth="230" Height="{DynamicResource R.BarHeight}" VerticalContentAlignment="Center" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Type de recherche"/>
    <Border x:Name="group_search_field" Grid.Column="3" Style="{StaticResource Field}" Height="{DynamicResource R.BarHeight}">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border Margin="12,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search}}</Border>
        <TextBox x:Name="group_query" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Une partie du nom (ex. vpn)"
                 ToolTip="Une partie du nom du groupe (Ctrl+F)"/>
        <!-- The last searches, to run one again (or ↓ in the box). -->
        <Button x:Name="group_recent" Grid.Column="2" Style="{StaticResource Btn.Mini}" Margin="0,0,5,0" ToolTip="Recherches récentes (↓)" AutomationProperties.Name="Recherches récentes">
          {{icon:history:15}}
          <Button.ContextMenu><ContextMenu x:Name="group_recent_menu"/></Button.ContextMenu>
        </Button>
      </Grid>
    </Border>
    <Button x:Name="group_search" Grid.Column="5" Style="{StaticResource Btn.Primary}" Height="{DynamicResource R.BarHeight}" ToolTip="Entrée, ou F5 pour relancer la dernière recherche">
      <StackPanel Orientation="Horizontal">{{icon:search}}<TextBlock Text="Rechercher" Margin="8,0,0,0"/></StackPanel>
    </Button>
    <!-- Shown while a search runs. -->
    <Button x:Name="group_cancel" Grid.Column="6" Height="{DynamicResource R.BarHeight}" Margin="8,0,0,0" Visibility="Collapsed" Content="Annuler" ToolTip="Arrêter la recherche (Échap)"/>
    <!-- What a search is missing, just under the box (Show-SearchHint), over the row below: gone once the search changes. -->
    <Canvas Grid.Column="3" Grid.ColumnSpan="4" VerticalAlignment="Bottom" Height="0" IsHitTestVisible="False">
      <Border x:Name="group_search_hint" Canvas.Top="6" Visibility="Collapsed" Padding="10,5" CornerRadius="6" BorderThickness="1"
              Background="{DynamicResource R.DangerBg}" BorderBrush="{DynamicResource R.DangerBorder}">
        <Border.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.2"/></Border.Effect>
        <TextBlock x:Name="group_search_hint_text" Foreground="{DynamicResource R.DangerText}" FontSize="12" TextWrapping="Wrap"/>
      </Border>
    </Canvas>
  </Grid>

  <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.ResultsBarMargin}">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
      <TextBlock Text="Groupes" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
      <TextBlock x:Name="group_scope" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="8,0,0,0"/>
    </StackPanel>
    <StackPanel Grid.Column="2" Orientation="Horizontal">
      <Button x:Name="group_export" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" IsEnabled="False" ToolTip="Enregistrer les groupes affichés en CSV (pour Excel)" ToolTipService.ShowOnDisabled="True">
        <StackPanel Orientation="Horizontal">{{icon:download}}<TextBlock Text="Exporter" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="group_columns" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" ToolTip="Afficher ou masquer des colonnes (ou clic droit sur un en-tête)">
        <StackPanel Orientation="Horizontal">{{icon:columns}}<TextBlock Text="Colonnes" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <ToggleButton x:Name="group_column_filters" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" ToolTip="Afficher ou masquer les filtres dans les en-têtes des colonnes">
        <StackPanel Orientation="Horizontal">{{icon:filter}}<TextBlock x:Name="group_column_filters_text" Text="Filtres" Margin="8,0,0,0"/></StackPanel>
      </ToggleButton>
      <Border Style="{StaticResource Field}" Width="260" Height="{DynamicResource R.ControlHeight}">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
          <TextBox x:Name="group_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les résultats"/>
        </Grid>
      </Border>
    </StackPanel>
  </Grid>

  <!-- Liste de noms: the names no domain had, to copy. -->
  <Border x:Name="group_not_found" DockPanel.Dock="Top" Visibility="Collapsed" Margin="16,0,16,10" Padding="12,6" CornerRadius="8" BorderThickness="1"
          Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Border Margin="0,0,8,0" TextElement.Foreground="{DynamicResource R.WarnText}">{{icon:warning}}</Border>
      <TextBlock x:Name="group_not_found_text" Grid.Column="1" Foreground="{DynamicResource R.WarnText}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
      <Button x:Name="group_not_found_copy" Grid.Column="2" Style="{StaticResource Btn.Warn}" Margin="12,-2,0,-2"
              ToolTip="Copier les introuvables, un par ligne" AutomationProperties.Name="Copier">
        <StackPanel Orientation="Horizontal">{{icon:copy:13}}<TextBlock Text="Copier" Margin="6,0,0,0"/></StackPanel>
      </Button>
    </Grid>
  </Border>

  <Border DockPanel.Dock="Bottom" Padding="{DynamicResource R.StatusPadding}">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="group_count" Style="{StaticResource Txt.Muted}" FontSize="12"/>
        <TextBlock x:Name="group_time" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="4,0,0,0"/>
        <!-- When a domain found more than the limit: the same search again, without it. -->
        <Button x:Name="group_show_all" Style="{StaticResource Btn.Ghost}" Visibility="Collapsed" Margin="8,-4,0,-4" Padding="8,2" MinHeight="0" FontSize="12"
                Foreground="{DynamicResource R.AccentText}" Content="Tout afficher" ToolTip="La même recherche, sans limite : peut prendre un moment"/>
      </StackPanel>
      <TextBlock Grid.Column="1" Margin="16,0,0,0" Style="{StaticResource Txt.Faint}" FontSize="12" Text="Clic droit sur un groupe : toutes les actions"/>
    </Grid>
  </Border>

  <Border Style="{StaticResource Card}" Margin="16,0">
    <Grid>
      <DataGrid x:Name="group_grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True" CanUserResizeColumns="True" CanUserReorderColumns="False"
                CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Extended" SelectionUnit="FullRow" HeadersVisibility="Column"
                GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{DynamicResource R.Border}" Background="Transparent" RowBackground="Transparent"
                Foreground="{DynamicResource R.Text}" BorderThickness="0" RowHeight="{DynamicResource R.RowHeight}" Margin="1"
                RowStyle="{StaticResource Grid.Row}" CellStyle="{StaticResource Grid.Cell}" ColumnHeaderStyle="{StaticResource Grid.Header}">
        <DataGrid.Columns>
          <DataGridTextColumn Header="Nom" Binding="{Binding Name}" SortMemberPath="Name" Width="1.5*" MinWidth="140" ElementStyle="{StaticResource Grid.Text.Strong}"/>
          <!-- Nom pré-Windows 2000, Courriel and Géré par: hidden until chosen in Colonnes. -->
          <DataGridTextColumn Header="Nom pré-Windows 2000" Binding="{Binding SamAccountName}" SortMemberPath="SamAccountName" Width="*" MinWidth="120" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Type" Binding="{Binding Type}" SortMemberPath="Type" Width="105" MinWidth="95" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Étendue" Binding="{Binding Scope}" SortMemberPath="Scope" Width="120" MinWidth="105" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Description" Binding="{Binding Description}" SortMemberPath="Description" Width="2*" MinWidth="140" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Courriel" Binding="{Binding Mail}" SortMemberPath="Mail" Width="1.3*" MinWidth="130" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Géré par" Binding="{Binding ManagedBy}" SortMemberPath="ManagedBy" Width="*" MinWidth="110" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Domaine" Binding="{Binding Domain}" SortMemberPath="Domain" Width="125" MinWidth="125" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTemplateColumn Header="Emplacement" SortMemberPath="OUPath" Width="*" MinWidth="105">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding OUPath}" ToolTip="{Binding DistinguishedName}" Style="{StaticResource Grid.Text}"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
        </DataGrid.Columns>
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="group_menu_details" Header="Propriétés…" FontWeight="{DynamicResource R.FontWeightStrong}"><MenuItem.Icon>{{icon:users}}</MenuItem.Icon></MenuItem>
            <MenuItem x:Name="group_menu_add_members" Header="Ajouter des membres…"><MenuItem.Icon>{{icon:userplus}}</MenuItem.Icon></MenuItem>
            <Separator/>
            <!-- The copies in a submenu, as on Ordinateurs and Utilisateurs. -->
            <MenuItem x:Name="group_menu_group_copy" Header="Copier" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:copy}}</MenuItem.Icon>
              <MenuItem x:Name="group_menu_copy" Header="Copier le nom" InputGestureText="Ctrl+C"><MenuItem.Icon>{{icon:copy}}</MenuItem.Icon></MenuItem>
              <MenuItem x:Name="group_menu_copy_dn" Header="Copier le nom distinctif"/>
              <MenuItem x:Name="group_menu_copy_rows" Header="Copier les lignes"><MenuItem.InputGestureText>Ctrl+Maj+C</MenuItem.InputGestureText></MenuItem>
            </MenuItem>
          </ContextMenu>
        </DataGrid.ContextMenu>
      </DataGrid>
      <!-- Before the first search, and when nothing is found. -->
      <StackPanel x:Name="group_empty" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False">
        <Border HorizontalAlignment="Center" TextElement.Foreground="{DynamicResource R.Faint}">{{icon:users:26}}</Border>
        <TextBlock x:Name="group_empty_text" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" Margin="0,10,0,0"
                   Text="Entrez une partie du nom d'un groupe, puis Rechercher."/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" HorizontalAlignment="Center" Margin="0,4,0,0"
                   Text="« Sans membres » sans texte liste les groupes vides du domaine."/>
      </StackPanel>
    </Grid>
  </Border>
</DockPanel>
'@

function Initialize-GroupPage($HostControl) {
    # Builds the page the first time its tab is chosen (Initialize-SearchPage), then wires what only groups have.
    Initialize-SearchPage $script:GroupPage $HostControl $script:GroupPageXaml
    $script:GroupPage.Root.FindName('group_menu_copy_dn').Add_Click({ Copy-PageText $script:GroupPage 'DistinguishedName' })
    foreach ($name in 'group_add_members', 'group_menu_add_members') { $script:GroupPage.Root.FindName($name).Add_Click({ Invoke-GroupMemberAdd }) }
}

function Invoke-GroupMemberAdd {
    # Ajouter des membres… to the selected group: the picker of its Propriétés (Show-GroupMemberPicker), with the same
    # rules and messages. Its Propriétés, if open, reads itself again afterwards, and leaves out the members it lists.
    $selected = Get-PageSelection $script:GroupPage
    if ($selected.Count -ne 1) { return }
    $open = $script:DetailWindows[(Get-DetailWindowKey 'group_detail' $selected[0])]
    Show-GroupMemberPicker $selected[0] $script:win $(if ($open) { Get-GroupListedMember $open.Tag } else { @() }) $selected[0] {
        param($row, $result)
        Update-OpenGroupDetail @($row)
        $text = Get-GroupMemberAddText $row $result
        if ($text) { Show-ActionNotice (Tr 'Ajouter des membres') "✔ $text" }
        if ($result.Failed) { Show-Dialog -Title (Tr 'Ajouter des membres') -Message ($result.Failed -join "`n") -Owner $script:win }
    }
}

function Update-GroupAction {
    # Propriétés… and Ajouter des membres… for one group; Copier for any.
    $root = $script:GroupPage.Root
    $selected = Get-PageSelection $script:GroupPage
    foreach ($name in 'group_details', 'group_menu_details', 'group_add_members', 'group_menu_add_members') { $root.FindName($name).IsEnabled = $selected.Count -eq 1 }
    foreach ($name in 'group_copy', 'group_menu_copy', 'group_menu_copy_dn', 'group_menu_copy_rows', 'group_menu_group_copy') { $root.FindName($name).IsEnabled = $selected.Count -gt 0 }
    $root.FindName('group_selection').Text = switch ($selected.Count) {
        0 { Tr 'Aucune sélection' }
        1 { (Tr '{0} sélectionné') -f $selected[0].Name }
        default { (Tr '{0} groupes sélectionnés') -f $selected.Count }
    }
}
