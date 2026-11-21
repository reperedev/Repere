# Comparer les groupes…: the groups of two users side by side, in a window of three lists (Seulement A, Les deux,
# Seulement B), to see why one has an access the other hasn't. From the Utilisateurs page (two users selected) or a
# user's Propriétés › Groupes (Comparer avec…, the other user picked by a search). Each group says how each user
# belongs to it (Directe, Principale, Héritée, as in Propriétés) and opens its Propriétés. Dot-sourced by the main
# script, after GroupsDialog.ps1 (Get-ObjectGroup), UserDetails.ps1 and GroupDetails.ps1.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

function Read-UserGroupList($Row) {
    # The groups of one user (Get-ObjectGroup), read in its domain, as its Propriétés reads them.
    $user = Get-ADUser -Server $Row.Domain -Identity $Row.DistinguishedName -Properties MemberOf, PrimaryGroup -ErrorAction Stop
    $inherited = Read-TokenGroup { Get-ADUser -Server $Row.Domain -Identity $Row.DistinguishedName -Properties tokenGroups -ErrorAction Stop }
    @(Get-ObjectGroup $user $Row.Domain $inherited)
}

function Read-UserGroupCompare($RowA, $RowB) {
    # Both users' groups, on a search runspace (Show-UserGroupCompare).
    @{ A = @(Read-UserGroupList $RowA); B = @(Read-UserGroupList $RowB) }
}

function Compare-UserGroup($GroupsA, $GroupsB) {
    # The groups of A and B as one list, by name: each group once (by its DN whatever its case, or by its name for a row
    # that couldn't be read), with A and B how each belongs to it (a Membership id, $null when not), and Side: A, Both
    # or B.
    $byKey = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($side in 'A', 'B') {
        foreach ($group in @(if ($side -eq 'A') { $GroupsA } else { $GroupsB })) {
            if (-not $group) { continue }
            $key = if ($group.DistinguishedName) { [string]$group.DistinguishedName } else { "name:$($group.Name)" }
            if (-not $byKey.Contains($key)) {
                $byKey[$key] = [pscustomobject]@{
                    Name = [string]$group.Name; Type = [string]$group.Type; Scope = [string]$group.Scope; Domain = [string]$group.Domain
                    Description = [string]$group.Description; DistinguishedName = [string]$group.DistinguishedName; A = $null; B = $null; Side = ''
                }
            }
            $entry = $byKey[$key]
            if (-not $entry.$side) { $entry.$side = [string]$group.Membership }
        }
    }
    foreach ($entry in $byKey.Values) { $entry.Side = if ($entry.A -and $entry.B) { 'Both' } elseif ($entry.A) { 'A' } else { 'B' } }
    @($byKey.Values | Sort-Object Name)
}

function Get-GroupCompareLabel([string]$Login, [string]$Domain, [bool]$SameLogin) {
    # How a user is named in the window and its CSV: its login, with its domain when the other user has the same login.
    if ($SameLogin) { return "$Login ($Domain)" }
    $Login
}

function Get-GroupCompareMembership($Entry, [string]$LabelA, [string]$LabelB) {
    # How the users belong to a group, in this run's language: « Directe » for one side, or both alike; otherwise
    # « jbertrand : Directe, jebertrand : Héritée ».
    if ($Entry.Side -ne 'Both') { return Tr $(if ($Entry.A) { $Entry.A } else { $Entry.B }) }
    if ($Entry.A -eq $Entry.B) { return Tr $Entry.A }
    (Tr '{0} : {1}, {2} : {3}') -f $LabelA, (Tr $Entry.A), $LabelB, (Tr $Entry.B)
}

function Get-GroupCompareText($Entries, [string]$NameA, [string]$NameB, [string]$LabelA, [string]$LabelB) {
    # Copier: the three lists as text, each under its title and count, a group per line with how the users belong to
    # it.
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(((Tr 'Groupes de {0} et de {1}') -f $NameA, $NameB))
    foreach ($side in 'A', 'Both', 'B') {
        $shown = @($Entries | Where-Object Side -eq $side)
        $title = switch ($side) { 'A' { (Tr 'Seulement {0}') -f $NameA } 'Both' { Tr 'Les deux' } 'B' { (Tr 'Seulement {0}') -f $NameB } }
        $lines.Add('')
        $lines.Add("$title ($($shown.Count))")
        foreach ($entry in $shown) { $lines.Add("  $($entry.Name) ($(Get-GroupCompareMembership $entry $LabelA $LabelB))") }
    }
    $lines -join [Environment]::NewLine
}

$script:GroupCompareXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Padding="18" Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <Border.Resources>
    <Style x:Key="Compare.List" TargetType="ListBox" BasedOn="{StaticResource {x:Type ListBox}}">
      <Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
      <Setter Property="ItemContainerStyle">
        <Setter.Value>
          <Style TargetType="ListBoxItem" BasedOn="{StaticResource {x:Type ListBoxItem}}">
            <Setter Property="Foreground" Value="{DynamicResource R.Text}"/><Setter Property="Padding" Value="10,6"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="AutomationProperties.Name" Value="{Binding Automation}"/>
          </Style>
        </Setter.Value>
      </Setter>
      <Setter Property="ItemTemplate">
        <Setter.Value>
          <DataTemplate>
            <StackPanel Margin="2,2">
              <!-- The group's domain at the row's right, every time: groups of two domains can have one name. -->
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Text="{Binding Name}" FontWeight="{DynamicResource R.FontWeightStrong}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
                <Border Grid.Column="1" Style="{StaticResource Badge.Quiet}" Margin="8,0,0,0" Visibility="{Binding DomainShown}">
                  <TextBlock Text="{Binding Domain}" AutomationProperties.AutomationId="compare_domain"/>
                </Border>
              </Grid>
              <TextBlock Text="{Binding Membership}" FontSize="12" Foreground="{DynamicResource R.AccentText}" TextTrimming="CharacterEllipsis"/>
              <TextBlock Text="{Binding Details}" FontSize="12" Opacity="0.75" TextTrimming="CharacterEllipsis" ToolTip="{Binding Details}"/>
            </StackPanel>
          </DataTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Border.Resources>
  <DockPanel>
    <StackPanel DockPanel.Dock="Top">
      <TextBlock x:Name="compare_title" FontSize="15" FontWeight="{DynamicResource R.FontWeightStrong}" TextWrapping="Wrap"/>
      <TextBlock x:Name="compare_summary" Style="{StaticResource Txt.Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
      <Border Style="{StaticResource Field}" Height="34" Margin="0,12,0,10" HorizontalAlignment="Left" Width="300">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
          <TextBox x:Name="compare_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les groupes"/>
        </Grid>
      </Border>
    </StackPanel>
    <Grid DockPanel.Dock="Bottom" Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="compare_status" Style="{StaticResource Txt.Muted}" FontSize="12" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="compare_export" MinWidth="90" ToolTip="Enregistrer les groupes affichés en CSV (pour Excel)">
          <StackPanel Orientation="Horizontal">{{icon:download}}<TextBlock Text="Exporter" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <Button x:Name="compare_copy" MinWidth="90" Margin="8,0,0,0" ToolTip="Les trois listes, en texte">
          <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <Button x:Name="dialog_cancel" Style="{StaticResource Btn.Primary}" MinWidth="90" Margin="8,0,0,0" IsCancel="True" Content="Fermer"/>
      </StackPanel>
    </Grid>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Style="{StaticResource Card}">
        <DockPanel>
          <TextBlock x:Name="compare_head_a" DockPanel.Dock="Top" Margin="12,10,12,6" FontWeight="{DynamicResource R.FontWeightStrong}" TextTrimming="CharacterEllipsis"/>
          <ListBox x:Name="compare_list_a" Style="{StaticResource Compare.List}"/>
        </DockPanel>
      </Border>
      <Border Grid.Column="2" Style="{StaticResource Card}">
        <DockPanel>
          <TextBlock x:Name="compare_head_both" DockPanel.Dock="Top" Margin="12,10,12,6" FontWeight="{DynamicResource R.FontWeightStrong}" TextTrimming="CharacterEllipsis"/>
          <ListBox x:Name="compare_list_both" Style="{StaticResource Compare.List}"/>
        </DockPanel>
      </Border>
      <Border Grid.Column="4" Style="{StaticResource Card}">
        <DockPanel>
          <TextBlock x:Name="compare_head_b" DockPanel.Dock="Top" Margin="12,10,12,6" FontWeight="{DynamicResource R.FontWeightStrong}" TextTrimming="CharacterEllipsis"/>
          <ListBox x:Name="compare_list_b" Style="{StaticResource Compare.List}"/>
        </DockPanel>
      </Border>
    </Grid>
  </DockPanel>
</Border>
'@

# The comparison windows open, by pair of users (their DNs, whatever their case), and the pairs being read: asked
# again, the open one comes to the front, and one being read isn't read twice.
$script:GroupCompareWindows = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

function Show-UserGroupCompare($RowA, $RowB, [System.Windows.Window]$Owner) {
    # Reads both users' groups in the background, $Owner (the main window, or a Propriétés) waiting meanwhile, then
    # opens the window over it; why they couldn't be read, otherwise.
    if (-not $Owner) { $Owner = $script:win }
    $key = "$($RowA.Domain)|$($RowA.DistinguishedName)|$($RowB.Domain)|$($RowB.DistinguishedName)"
    $open = $null
    if ($script:GroupCompareWindows.TryGetValue($key, [ref]$open)) {
        # Being read: nothing to bring yet.
        if ($open -is [System.Windows.Window]) {
            if ($open.WindowState -eq 'Minimized') { $open.WindowState = 'Normal' }
            $null = $open.Activate()
        }
        return
    }
    $script:GroupCompareWindows[$key] = $true
    $Owner.Cursor = [System.Windows.Input.Cursors]::AppStarting
    try {
        Start-BackgroundRead -Command 'Read-UserGroupCompare' -Arguments @($RowA, $RowB) `
            -Functions 'Read-UserGroupList', 'Get-ObjectGroup', 'Read-TokenGroup', 'Get-DomainOfSid', 'Get-DomainOfDN', 'Get-LdapText' `
            -Variables (Get-DetailReadVariable) -Context @{ A = $RowA; B = $RowB; Owner = $Owner; Key = $key } -OnDone {
            param($context, $result, $problem)
            $owner = $context.Owner
            $owner.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
            $null = $script:GroupCompareWindows.Remove($context.Key)
            # Closed meanwhile (a Propriétés): over the main window.
            if (-not $owner.IsVisible) { $owner = $script:win }
            if ($problem -or -not $result) {
                $why = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
                Show-Dialog -Title (Tr 'Comparer les groupes') -Message ((Tr '✖ Groupes de {0} et de {1} non lus ({2})') -f $context.A.Name, $context.B.Name, $why) -Owner $owner
                return
            }
            New-GroupCompareWindow $context.A $context.B @(Compare-UserGroup $result.A $result.B) $owner $context.Key
        }
    }
    catch {
        $Owner.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
        $null = $script:GroupCompareWindows.Remove($key)
        Show-Dialog -Title (Tr 'Comparer les groupes') -Message ((Tr '✖ Groupes de {0} et de {1} non lus ({2})') -f $RowA.Name, $RowB.Name, $_.Exception.Message) -Owner $Owner
    }
}

function New-GroupCompareWindow($RowA, $RowB, $Entries, [System.Windows.Window]$Owner, [string]$Key) {
    # The window: the three lists, the filter, Copier, Exporter and Fermer (or Échap). A window of its own, as
    # Propriétés: the window it opened over stays usable. A group opens its Propriétés by a double-click, Entrée or its
    # right-click menu.
    $same = [string]$RowA.Login -eq [string]$RowB.Login
    $labelA = Get-GroupCompareLabel $RowA.Login $RowA.Domain $same
    $labelB = Get-GroupCompareLabel $RowB.Login $RowB.Domain $same
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:GroupCompareXaml))
    $window = [System.Windows.Window]::new()
    $window.Title = (Tr 'Groupes de {0} et de {1}') -f $RowA.Name, $RowB.Name
    $window.Icon = $script:windowIcon
    $window.Owner = $Owner
    $window.Width = 1100
    $window.Height = [Math]::Min(700, [System.Windows.SystemParameters]::WorkArea.Height - 40)
    $window.MinWidth = 760
    $window.MinHeight = 400
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'CenterOwner'
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $window.Content = $root
    Set-WindowChrome $window
    Register-OwnerFocus $window

    $root.FindName('compare_title').Text = $window.Title
    # The lists' titles say how many groups each has.
    $root.FindName('compare_summary').Text = (Tr 'Sous chaque groupe, comment {0} et {1} y appartiennent : Directe, Principale ou Héritée (par un autre groupe). Double-clic sur un groupe : ses propriétés.') -f $labelA, $labelB
    # Each group as the lists show it: its domain beside its name, how the users belong to it, then its type, scope and
    # description.
    $items = foreach ($entry in $Entries) {
        $membership = Get-GroupCompareMembership $entry $labelA $labelB
        $kind = @($entry.Type, $entry.Scope) | Where-Object { $_ }
        [pscustomobject]@{
            Name = $entry.Name; Membership = $membership; Side = $entry.Side; Entry = $entry; Automation = "$($entry.Name) | $membership"
            Domain = $entry.Domain; DomainShown = ConvertTo-Visibility ([bool]$entry.Domain)
            Details = (@($kind -join ', ') + @($entry.Description | Where-Object { $_ }) | Where-Object { $_ }) -join ' · '
            Text = "$($entry.Name) $($entry.Description) $($entry.Type) $($entry.Scope) $($entry.Domain) $membership".ToLowerInvariant()
        }
    }
    $state = @{ Filter = ''; Views = @{}; Heads = @{}; Entries = $Entries; RowA = $RowA; RowB = $RowB; LabelA = $labelA; LabelB = $labelB; Key = $Key; Status = $root.FindName('compare_status') }
    $window.Tag = $state
    foreach ($side in 'A', 'Both', 'B') {
        $suffix = switch ($side) { 'A' { 'a' } 'Both' { 'both' } 'B' { 'b' } }
        $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        foreach ($item in @($items | Where-Object Side -eq $side)) { $rows.Add($item) }
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($rows)
        $view.Filter = [Predicate[object]]{ param($item) -not $state.Filter -or $item.Text.Contains($state.Filter) }.GetNewClosure()
        $state.Views[$side] = $view
        $state.Heads[$side] = $root.FindName("compare_head_$suffix")
        $list = $root.FindName("compare_list_$suffix")
        $list.ItemsSource = $rows
        [System.Windows.Automation.AutomationProperties]::SetName($list, $(switch ($side) { 'A' { (Tr 'Seulement {0}') -f $RowA.Name } 'Both' { Tr 'Les deux' } 'B' { (Tr 'Seulement {0}') -f $RowB.Name } }))
        $list.Add_MouseDoubleClick({
            param($control, $e)
            # On a group, not on the list's scroll bar or its empty part.
            if ($control.ContainerFromElement($e.OriginalSource)) { Open-GroupCompareItem $control }
        })
        $list.Add_KeyDown({ param($control, $e) if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Open-GroupCompareItem $control } })
        $menu = [System.Windows.Controls.ContextMenu]::new()
        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = Tr 'Propriétés…'
        $item.Add_Click({ param($control) Open-GroupCompareItem $control.Parent.PlacementTarget })
        $null = $menu.Items.Add($item)
        $list.ContextMenu = $menu
    }
    Update-GroupCompareHead $state

    $root.FindName('compare_filter').Add_TextChanged({
        param($box)
        $state = [System.Windows.Window]::GetWindow($box).Tag
        $state.Filter = "$($box.Text)".Trim().ToLowerInvariant()
        foreach ($view in $state.Views.Values) { $view.Refresh() }
        Update-GroupCompareHead $state
    })
    $root.FindName('compare_copy').Add_Click({ param($button) Copy-GroupCompare ([System.Windows.Window]::GetWindow($button).Tag) $button })
    $root.FindName('compare_export').Add_Click({ param($button) Export-GroupCompare ([System.Windows.Window]::GetWindow($button)) })
    $root.FindName('dialog_cancel').Add_Click({ param($button) [System.Windows.Window]::GetWindow($button).Close() })
    $window.Add_Closed({ param($control) $null = $script:GroupCompareWindows.Remove($control.Tag.Key) })
    $root.Add_Loaded({ param($panel) $null = $panel.FindName('compare_filter').Focus() })
    $script:GroupCompareWindows[$Key] = $window
    $window.Show()
}

function Update-GroupCompareHead($State) {
    # Each list's title, with how many groups it shows (of how many, while filtered).
    $names = @{ A = (Tr 'Seulement {0}') -f $State.RowA.Name; Both = Tr 'Les deux'; B = (Tr 'Seulement {0}') -f $State.RowB.Name }
    foreach ($side in 'A', 'Both', 'B') {
        $view = $State.Views[$side]
        $shown = @(foreach ($item in $view) { $item }).Count
        $all = $view.SourceCollection.Count
        $State.Heads[$side].Text = if ($State.Filter -and $shown -ne $all) { "$($names[$side]) ($shown / $all)" } else { "$($names[$side]) ($all)" }
    }
}

function Get-GroupCompareShown($State) {
    # The groups the lists show (after the filter), in their order: what Copier and Exporter take.
    foreach ($side in 'A', 'Both', 'B') { foreach ($item in $State.Views[$side]) { $item.Entry } }
}

function Copy-GroupCompare($State, [System.Windows.Controls.Button]$Button) {
    # Copier: the groups shown as text (Get-GroupCompareText). The button and the status line say whether they were
    # copied (#248): another program can hold the clipboard, and nothing then is.
    $shown = @(Get-GroupCompareShown $State)
    $copied = Set-ClipboardText (Get-GroupCompareText $shown $State.RowA.Name $State.RowB.Name $State.LabelA $State.LabelB)
    Show-CopyFeedback $Button $copied
    $State.Status.Text = if (-not $copied) { Tr 'Non copié : le presse-papiers est occupé par un autre programme.' }
                         elseif ($shown.Count -eq 1) { Tr '1 groupe copié.' }
                         else { (Tr '{0} groupes copiés.') -f $shown.Count }
}

function Open-GroupCompareItem($List) {
    # Propriétés of the group chosen in a list, over the comparison; a group that couldn't be read (no type) doesn't open.
    $item = $List.SelectedItem
    if (-not $item -or -not $item.Entry.Type) { return }
    $entry = $item.Entry
    $row = [pscustomobject]@{ Name = $entry.Name; Domain = $entry.Domain; DistinguishedName = $entry.DistinguishedName; OUPath = Get-OUPath $entry.DistinguishedName }
    Show-GroupDetail $row ([System.Windows.Window]::GetWindow($List)) $script:windowIcon
}

function Export-GroupCompare([System.Windows.Window]$Window) {
    # Exporter: the groups shown as CSV, as the pages export (UTF-8 with a BOM, the culture's list separator): the group,
    # its domain, then how each user belongs to it (empty when not). $env:REPERE_EXPORT_PATH, for the UI tests, saves
    # there without asking.
    $state = $Window.Tag
    $shown = @(Get-GroupCompareShown $state)
    if (-not $shown.Count) { return }
    $title = Tr 'Exporter la comparaison'
    $path = $env:REPERE_EXPORT_PATH
    if (-not $path) {
        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Title = $title
        $dialog.Filter = Tr 'Fichiers CSV (*.csv)|*.csv'
        # The date in the Gregorian calendar whatever the culture's (-f would write 2569 in th-TH), so exports sort by name.
        $dialog.FileName = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, (Tr 'Repere_groupes_{0}_{1}_{2:yyyy-MM-dd}.csv'),
            ($state.RowA.Login -replace '[^\w\.\-]+', '-'), ($state.RowB.Login -replace '[^\w\.\-]+', '-'), (Get-Date))
        $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if (-not $dialog.ShowDialog($Window)) { return }
        $path = $dialog.FileName
    }
    try {
        $group, $domain = (Tr 'Groupe'), (Tr 'Domaine')
        $lines = $shown | ForEach-Object {
            [pscustomobject][ordered]@{
                $group = $_.Name; $domain = $_.Domain
                ($state.LabelA) = if ($_.A) { Tr $_.A } else { '' }
                ($state.LabelB) = if ($_.B) { Tr $_.B } else { '' }
            }
        } | Protect-CsvValue | ConvertTo-Csv -Delimiter (Get-Culture).TextInfo.ListSeparator -UseQuotes AsNeeded
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8BOM -ErrorAction Stop
        $state.Status.Text = if ($shown.Count -eq 1) { Tr '1 ligne exportée' } else { (Tr '{0} lignes exportées') -f $shown.Count }
        $state.Status.ToolTip = $path
    }
    catch {
        Show-Dialog -Title $title -Icon 'xcircle' -Tone 'danger' -Message ((Tr "Impossible d'enregistrer {0} : {1}") -f $path, $_.Exception.Message) -Owner $Window
    }
}

function Show-UserCompareDialog($State) {
    # Comparer avec… (a user's Propriétés › Groupes): the other user, found by the start of a name, login or email in
    # every domain (AD's ambiguous name resolution), the window's user left out; OK compares their groups.
    $content = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border Style="{StaticResource Field}" Height="34">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search:14}}</Border>
      <TextBox x:Name="compare_user_query" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Nom, identifiant ou courriel (ex. bert)"/>
    </Grid>
  </Border>
  <Border Style="{StaticResource Card}" Margin="0,10,0,0" Height="220">
    <Grid>
      <ListBox x:Name="compare_user_results" Background="Transparent" BorderThickness="0" SelectionMode="Single" AutomationProperties.Name="Utilisateurs trouvés">
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem" BasedOn="{StaticResource {x:Type ListBoxItem}}">
            <Setter Property="Foreground" Value="{DynamicResource R.Text}"/><Setter Property="Padding" Value="10,6"/>
            <Setter Property="AutomationProperties.Name" Value="{Binding Automation}"/>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <StackPanel Margin="2,2">
              <TextBlock Text="{Binding Name}" FontWeight="{DynamicResource R.FontWeightStrong}"/>
              <TextBlock Text="{Binding Details}" FontSize="12" Opacity="0.75" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
      <TextBlock x:Name="compare_user_hint" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" Margin="16"
                 Text="Tapez le début d'un nom, d'un identifiant ou d'un courriel."/>
    </Grid>
  </Border>
  <TextBlock x:Name="compare_user_note" Style="{StaticResource Txt.Muted}" Margin="0,8,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
</StackPanel>
'@))
    $row = $State.Row
    $content.Tag = @{ Except = [string]$row.DistinguishedName; Timer = $null }
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(300)
    $timer.Tag = $content
    $timer.Add_Tick({ param($tick) $tick.Stop(); Find-CompareUserChoice $tick.Tag })
    $content.Tag.Timer = $timer
    # Searched once the typing pauses, so each letter doesn't query AD.
    $query = $content.FindName('compare_user_query')
    $query.Add_TextChanged({ param($box) $timer = $box.Parent.Parent.Parent.Tag.Timer; $timer.Stop(); $timer.Start() })
    $query.Add_KeyDown({
        $e = $args[1]
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Find-CompareUserChoice $args[0].Parent.Parent.Parent }
    })
    $content.Add_Loaded({ param($panel) $null = $panel.FindName('compare_user_query').Focus() })

    Show-Dialog -Title (Tr 'Comparer les groupes') -Heading ((Tr 'Comparer les groupes de {0} avec…') -f $row.Name) -Icon 'columns' -Owner $State.Window `
        -Message (Tr "Choisissez l'autre utilisateur : ses groupes et ceux-ci, côte à côte.") -Content $content -OkText (Tr 'Comparer') `
        -State @{ Detail = $State; Content = $content } -OnOk {
        param($dialog)
        $other = $dialog.Content.FindName('compare_user_results').SelectedItem
        if (-not $other) { return }
        $state = $dialog.Detail
        Show-UserGroupCompare $state.Row $other.Row $state.Window
    }
}

function Find-CompareUserChoice($Content) {
    # The users the text finds (25 at most), in every domain, searched in the background; a result for a text since
    # changed is left. The note under the list names each domain that couldn't be searched, so a user of it isn't
    # taken for missing from AD.
    $text = "$($Content.FindName('compare_user_query').Text)".Trim()
    $list = $Content.FindName('compare_user_results')
    $hint = $Content.FindName('compare_user_hint')
    if (-not $text) {
        $list.Items.Clear()
        $hint.Text = Tr "Tapez le début d'un nom, d'un identifiant ou d'un courriel."
        $hint.Visibility = 'Visible'
        $Content.FindName('compare_user_note').Visibility = 'Collapsed'
        return
    }
    if (-not $list.Items.Count) { $hint.Text = Tr 'Recherche…'; $hint.Visibility = 'Visible' }
    Start-BackgroundRead -Command 'Get-CompareUserChoice' -Arguments @(@($script:domainList | Where-Object { $_ }), $text, $Content.Tag.Except) -Functions 'Get-LdapText' `
        -Context @{ Content = $Content; Text = $text } -OnDone {
        param($context, $found, $problem)
        $content = $context.Content
        if ("$($content.FindName('compare_user_query').Text)".Trim() -ne $context.Text) { return }
        $list = $content.FindName('compare_user_results')
        $hint = $content.FindName('compare_user_hint')
        $note = $content.FindName('compare_user_note')
        $list.Items.Clear()
        $note.Visibility = 'Collapsed'
        if ($problem) { $hint.Text = (Tr 'Recherche impossible : {0}') -f (ConvertTo-FrenchError $problem); $hint.Visibility = 'Visible'; return }
        foreach ($item in @($found.Items)) { $null = $list.Items.Add($item) }
        if ($list.Items.Count) { $list.SelectedIndex = 0 }
        $hint.Text = (Tr 'Aucun utilisateur pour « {0} ».') -f $context.Text
        $hint.Visibility = if ($list.Items.Count) { 'Collapsed' } else { 'Visible' }
        $lines = @(foreach ($miss in @($found.Unsearched)) { (Tr '{0} non cherché : {1}') -f $miss.Domain, (ConvertTo-FrenchError $miss.Problem) })
        if ($lines.Count) { $note.Text = $lines -join "`n"; $note.Visibility = 'Visible' }
    }
}

function Get-CompareUserChoice([string[]]$Domains, [string]$Text, [string]$Except) {
    # On a search runspace: the users of $Domains that $Text finds (AD's ambiguous name resolution), $Except (the
    # window's user) left out, 25 at most, by name, as Items (one object: a read gives back the last one written);
    # each with the row the comparison needs. A domain that can't be searched is passed over, unless none can be, and
    # given back in Unsearched with why (as Get-UserGroupChoice does), for the note under the list.
    $filter = "(&(objectCategory=person)(objectClass=user)(anr=$(Get-LdapText $Text)))"
    $problem = $null
    $unsearched = [System.Collections.Generic.List[object]]::new()
    $items = @(foreach ($domain in $Domains) {
        try {
            foreach ($user in @(Get-ADUser -Server $domain -LDAPFilter $filter -Properties DisplayName, Title -ResultSetSize 26 -ErrorAction Stop)) {
                if ([string]$user.DistinguishedName -eq $Except) { continue }
                $name = if ($user.DisplayName) { [string]$user.DisplayName } else { [string]$user.Name }
                [pscustomobject]@{
                    Name = $name; Automation = "$name | $($user.SamAccountName)"
                    Details = (@([string]$user.SamAccountName, $domain, [string]$user.Title) | Where-Object { $_ }) -join ' · '
                    Row = [pscustomobject]@{ Name = $name; Login = [string]$user.SamAccountName; Domain = $domain; DistinguishedName = [string]$user.DistinguishedName }
                }
            }
        }
        catch {
            $problem = $_.Exception.Message
            $unsearched.Add(@{ Domain = $domain; Problem = $problem })
        }
    })
    if (-not $items.Count -and $problem) { throw $problem }
    @{ Items = @($items | Sort-Object Name | Select-Object -First 25); Unsearched = @($unsearched) }
}
