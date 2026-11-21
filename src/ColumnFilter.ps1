# Column filters: a results grid's rows narrowed down by the values of its columns, as in Excel. The funnel of a column's
# header (or Filtrer cette colonne…, a right-click on it) opens the column's filter, by the column's Mode:
#   Values  the values the column holds, each with how many rows have it, to tick. Text typed in the list's search with
#           every value it finds left ticked makes a Contains rule instead: rows added later (Tout afficher) are kept
#           when they contain it too.
#   Text    only that text (names, all different: a list would hold every row).
#   Age     a date column's: at least or less than so many days, weeks, months or years ago, with or without the rows
#           that have none (« Jamais »). Counted as the advanced search counts: from midnight, that long ago.
# The rows shown are those every filtered column keeps and the filter box finds. A filtered column's funnel always
# shows, in the accent; the others while the Filtres button is on (kept in apparence.json, per page). A new search
# clears the filters (Tout afficher keeps them), and so does hiding a filtered column. Ordinateurs (ComputerPage.ps1),
# Utilisateurs and Groupes (SearchPage.ps1) each have theirs.
#
# A grid's filters are a hashtable (Initialize-ColumnFilter): its Grid; the Prefix of its controls' names (user_ for
# the users', none for the computers'); each column's Specs, by key (its SortMemberPath): its Mode, the row Property
# its values are read from, the Empty label of a row that has none, and the Order of its values when it isn't
# alphabetical; the Active filters, by key (New-ColumnFilterRule's) and as a List for New-RowFilter; whether the
# funnels are Shown; the page's Setting in apparence.json; the page's filter box text, $Holder[$QueryKey]; and
# OnChange, given the filters once they change, which shows the page's rows and count again. A header draws its funnel
# by its Tag (Theme.ps1's Grid.Header): Filter, Active, or none. Dot-sourced by the main script after Theme.ps1.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

# Each grid's filters, by the names of the controls that act on them (the grid, the Filtres button, the menu items).
$script:ColumnFilters = @{}
# The filter Filtrer cette colonne… opens once the menu has closed (Open-PendingColumnFilter).
$script:PendingColumnFilter = $null
# The list whose Tout sélectionner and OK are about to follow its values (Request-ColumnFilterAll).
$script:PendingColumnFilterAll = $null

$script:ColumnFilterXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="colfilter_panel" Style="{StaticResource Card}" Padding="10" MinWidth="300" Margin="0,2,10,10">
  <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Opacity="0.25"/></Border.Effect>
  <DockPanel>
    <TextBlock x:Name="colfilter_title" DockPanel.Dock="Top" FontWeight="{DynamicResource R.FontWeightStrong}" Margin="2,0,0,8" TextTrimming="CharacterEllipsis"/>
    <Border x:Name="colfilter_search_field" DockPanel.Dock="Top" Style="{StaticResource Field}" Height="{DynamicResource R.ControlHeight}">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Margin="10,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search:14}}</Border>
        <TextBox x:Name="colfilter_search" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Rechercher une valeur"/>
      </Grid>
    </Border>
    <!-- A date column's filter: how long ago, at least or less than. Buttons rather than lists: a list's drop-down
         would close this popup. Its buttons can widen the card, not its note. -->
    <StackPanel x:Name="colfilter_age" DockPanel.Dock="Top" Visibility="Collapsed">
      <TextBlock Style="{StaticResource Txt.Muted}" Margin="2,0,0,6" Text="Dernière connexion il y a"/>
      <Border BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Height="{DynamicResource R.ControlHeight}">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <RadioButton x:Name="colfilter_age_atleast" GroupName="colfilter_direction" Style="{StaticResource Toggle.Seg}" Tag="5,0,0,5" Padding="10,0" Content="Plus de"/>
          <RadioButton x:Name="colfilter_age_less" GroupName="colfilter_direction" Style="{StaticResource Toggle.Seg}" Grid.Column="1" Tag="0,5,5,0" Padding="10,0" Content="Moins de"/>
        </Grid>
      </Border>
      <Grid Margin="0,8,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="64"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <TextBox x:Name="colfilter_age_number" MaxLength="3" AutomationProperties.Name="Durée"/>
        <Border Grid.Column="1" Margin="8,0,0,0" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Height="{DynamicResource R.ControlHeight}">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <RadioButton x:Name="colfilter_age_unit0" GroupName="colfilter_unit" Style="{StaticResource Toggle.Seg}" Tag="5,0,0,5" Padding="8,0" Content="jours"/>
            <RadioButton x:Name="colfilter_age_unit1" GroupName="colfilter_unit" Style="{StaticResource Toggle.Seg}" Grid.Column="1" Padding="8,0" Content="semaines"/>
            <RadioButton x:Name="colfilter_age_unit2" GroupName="colfilter_unit" Style="{StaticResource Toggle.Seg}" Grid.Column="2" Padding="8,0" Content="mois"/>
            <RadioButton x:Name="colfilter_age_unit3" GroupName="colfilter_unit" Style="{StaticResource Toggle.Seg}" Grid.Column="3" Tag="0,5,5,0" Padding="8,0" Content="ans"/>
          </Grid>
        </Border>
      </Grid>
      <CheckBox x:Name="colfilter_age_never" Margin="2,10,0,0" Content="Inclure « Jamais »"/>
      <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" Margin="0,10,0,0" Padding="2,0,0,0" TextWrapping="Wrap" Width="{Binding ActualWidth, ElementName=colfilter_footer}"
                 Text="À 2 semaines près."/>
    </StackPanel>
    <!-- What OK keeps once text is typed: the rows whose column contains it. -->
    <TextBlock x:Name="colfilter_hint" DockPanel.Dock="Top" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="0,8,0,0" Padding="2,0,0,0" TextWrapping="Wrap" Visibility="Collapsed"
               Width="{Binding ActualWidth, ElementName=colfilter_footer}"/>
    <CheckBox x:Name="colfilter_all" DockPanel.Dock="Top" Margin="6,8,0,4" Content="Tout sélectionner"/>
    <!-- The buttons set the card's width (wider at a large text size); the list only takes it. -->
    <Grid x:Name="colfilter_footer" DockPanel.Dock="Bottom" Margin="0,10,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*" MinWidth="16"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button x:Name="colfilter_clear" Style="{StaticResource Btn.Ghost}" Content="Effacer le filtre" ToolTip="Afficher de nouveau toutes les valeurs de cette colonne"/>
      <Button x:Name="colfilter_cancel" Grid.Column="2" Margin="0,0,8,0" Content="Annuler"/>
      <Button x:Name="colfilter_ok" Grid.Column="3" Style="{StaticResource Btn.Primary}" MinWidth="64" Content="OK"/>
    </Grid>
    <Grid x:Name="colfilter_list_area" MinHeight="64" MaxHeight="260" Width="{Binding ActualWidth, ElementName=colfilter_footer}">
      <ListBox x:Name="colfilter_values" BorderThickness="0" Background="Transparent" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
               VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" AutomationProperties.Name="Valeurs">
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Padding" Value="4,1"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem"><ContentPresenter Margin="{TemplateBinding Padding}"/></ControlTemplate>
              </Setter.Value>
            </Setter>
            <Style.Triggers>
              <!-- Fluent's scroll bar lies over the list's right edge, and widens under the mouse: once the list
                   scrolls, the counts end before it. -->
              <DataTrigger Binding="{Binding ComputedVerticalScrollBarVisibility, RelativeSource={RelativeSource AncestorType=ScrollViewer}}" Value="Visible">
                <Setter Property="Padding" Value="4,1,18,1"/>
              </DataTrigger>
            </Style.Triggers>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <CheckBox IsChecked="{Binding Checked, Mode=TwoWay}" AutomationProperties.Name="{Binding Label}" AutomationProperties.AutomationId="ValueBox">
                <TextBlock Text="{Binding Label}" TextTrimming="CharacterEllipsis"/>
              </CheckBox>
              <TextBlock Grid.Column="1" Text="{Binding Count}" Style="{StaticResource Txt.Faint}" FontSize="11.5" Margin="8,0,4,0" VerticalAlignment="Center"/>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
      <TextBlock x:Name="colfilter_none" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" Text="Aucune valeur ne correspond."/>
    </Grid>
  </DockPanel>
</Border>
'@

function Initialize-ColumnFilter {
    # A grid's filters, wired to its funnels, its Filtres button ($Toggle) and its column menu ($Menu, the header's
    # right-click): Filtrer cette colonne… and Effacer les filtres go first in it. The filter box's text, lowercase, is
    # $Holder[$QueryKey] (the page's). Call once the headers have their styles.
    param($Grid, [string]$Prefix, [hashtable]$Specs, $Toggle, $Menu, [string]$Setting, $Holder, [string]$QueryKey, [scriptblock]$OnChange)
    # The funnel's tooltip, which the shared header template (not translated itself) takes from here.
    [System.Windows.Application]::Current.Resources['R.FilterTip'] = Tr 'Filtrer cette colonne'
    $state = @{
        Grid = $Grid; Prefix = $Prefix; Specs = @{}; Active = [ordered]@{}; List = @(); Setting = $Setting; OnChange = $OnChange
        Holder = $Holder; QueryKey = $QueryKey
        Shown = $Setting -notin @($script:Appearance.HiddenColumnFilters); Toggle = $Toggle; Bases = @{}; Styles = @{}
        Popup = $null; Parts = $null; Key = $null; Title = ''; Items = $null; ItemView = $null; Search = ''; Updating = $false; AllPending = $false; MenuItems = $null
    }
    foreach ($column in $Grid.Columns) {
        $key = $column.SortMemberPath
        $spec = @{ Mode = 'Values'; Property = $key; Empty = (Tr '(vide)'); Order = $null }
        if ($Specs -and $Specs.ContainsKey($key)) { foreach ($name in @($Specs[$key].Keys)) { $spec[$name] = $Specs[$key][$name] } }
        $state.Specs[$key] = $spec
        # The header's own style, if any (with its tooltip), else the grid's: the funnel's styles are based on it.
        $state.Bases[$key] = $column.HeaderStyle
    }
    $script:ColumnFilters[$Grid.Name] = $state

    # A click on a funnel: its header's column, not a sort (the funnel takes the click).
    $Grid.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($grid, $e)
        $button = $e.OriginalSource
        if ($button -isnot [System.Windows.Controls.Button] -or $button.Name -ne 'FilterButton') { return }
        $e.Handled = $true
        $header = $button.TemplatedParent
        Open-ColumnFilter $script:ColumnFilters[$grid.Name] $header
    })

    $script:ColumnFilters[$Toggle.Name] = $state
    $Toggle.IsChecked = $state.Shown
    # Turned on or off by a click or a screen reader.
    $toggled = {
        param($toggle)
        $state = $script:ColumnFilters[$toggle.Name]
        $state.Shown = [bool]$toggle.IsChecked
        $hidden = [System.Collections.Generic.List[string]]::new()
        foreach ($setting in @($script:Appearance.HiddenColumnFilters)) { if ($setting -and $setting -ne $state.Setting) { $hidden.Add($setting) } }
        if (-not $state.Shown) { $hidden.Add($state.Setting) }
        $script:Appearance.HiddenColumnFilters = @($hidden)
        Save-Appearance
        Update-ColumnFilterHeader $state
    }
    $Toggle.Add_Checked($toggled)
    $Toggle.Add_Unchecked($toggled)

    $filterItem = [System.Windows.Controls.MenuItem]::new()
    $filterItem.Header = Tr 'Filtrer cette colonne…'
    $filterItem.Name = "$($Prefix)column_filter"
    $filterItem.Add_Click({
        param($item)
        if (-not $item.Tag) { return }
        # Once the menu has closed: it would otherwise close the list as it opens.
        $script:PendingColumnFilter = @{ State = $script:ColumnFilters[$item.Name]; Header = $item.Tag }
        $null = $item.Dispatcher.BeginInvoke([Action]{ Open-PendingColumnFilter })
    })
    $clearItem = [System.Windows.Controls.MenuItem]::new()
    $clearItem.Header = Tr 'Effacer les filtres'
    $clearItem.Name = "$($Prefix)column_filter_clear"
    $clearItem.Add_Click({
        param($item)
        $state = $script:ColumnFilters[$item.Name]
        if (-not $state.Active.Count) { return }
        Clear-ColumnFilter $state
        & $state.OnChange $state
    })
    foreach ($item in $filterItem, $clearItem) { $script:ColumnFilters[$item.Name] = $state }
    $Menu.Items.Insert(0, $filterItem)
    $Menu.Items.Insert(1, $clearItem)
    $Menu.Items.Insert(2, [System.Windows.Controls.Separator]::new())
    $state.MenuItems = @{ Filter = $filterItem; Clear = $clearItem; Separator = $Menu.Items[2] }
    # Filtrer cette colonne… on a header only (not from the Colonnes button), and Effacer les filtres while there are some.
    $Menu.Add_Opened({
        param($menu)
        $state = $script:ColumnFilters[$menu.Items[0].Name]
        $target = $menu.PlacementTarget
        $header = if ($target -is [System.Windows.Controls.Primitives.DataGridColumnHeader] -and $target.Column) { $target }
        $state.MenuItems.Filter.Tag = $header
        $state.MenuItems.Filter.Visibility = ConvertTo-Visibility ([bool]$header)
        $state.MenuItems.Clear.Visibility = ConvertTo-Visibility ($state.Active.Count -gt 0)
        $state.MenuItems.Separator.Visibility = ConvertTo-Visibility ($header -or $state.Active.Count)
    })

    Update-ColumnFilterHeader $state
    $state
}

function New-ColumnFilterRule($Spec, [string]$Kind) {
    # A column's filter, of one Kind: Values (the Allowed ones, a set), Contains (its Text) or Age (rows dated before
    # the Cutoff when AtLeast, from it otherwise, and those without a date when Never; the Number and Unit it was made
    # from, to show them again). Every key always there: the row filter reads them without checking.
    @{ Kind = $Kind; Property = $Spec.Property; Empty = $Spec.Empty; Allowed = $null; Text = ''
       Cutoff = ''; AtLeast = $true; Never = $true; Number = 0; Unit = 0 }
}

function Get-AgeCutoff([int]$Number, [int]$Unit, [datetime]$Today) {
    # Midnight, that long ago: $Number days, weeks, months or years ($Unit 0 to 3). From midnight, so it's the same all
    # day. A column's Age filter and the advanced search's Dernière connexion (AdvancedSearch.ps1) both count so.
    switch ($Unit) {
        0 { $Today.Date.AddDays(-$Number) }
        1 { $Today.Date.AddDays(-7 * $Number) }
        2 { $Today.Date.AddMonths(-$Number) }
        default { $Today.Date.AddYears(-$Number) }
    }
}

function Get-ColumnFilterCutoff([int]$Number, [int]$Unit, [datetime]$Today) {
    # An Age filter's cutoff, as the rows write their dates (yyyy-MM-dd HH:mm, which sorts as text). The same as the
    # advanced search's, so « au moins 90 jours » keeps what that search finds.
    (Get-AgeCutoff $Number $Unit $Today).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

function New-RowFilter($State) {
    # The predicate of a grid's view: a row the filter box finds (its text against the row's Text) and that every
    # filtered column keeps. Run for each row: no function is called (Get-ColumnFilterChoice has the same loop).
    $holder = $State.Holder
    $queryKey = $State.QueryKey
    [Predicate[object]]{
        param($row)
        $query = $holder[$queryKey]
        if ($query -and -not $row.Text.Contains($query)) { return $false }
        foreach ($filter in $State.List) {
            $value = $row.($filter.Property)
            if ($filter.Kind -eq 'Age') {
                if ($null -eq $value -or '' -eq $value) { if (-not $filter.Never) { return $false } }
                elseif (([string]::CompareOrdinal($value, $filter.Cutoff) -lt 0) -ne $filter.AtLeast) { return $false }
                continue
            }
            if ($null -eq $value -or '' -eq $value) { $value = $filter.Empty }
            if ($filter.Kind -eq 'Contains') { if (([string]$value).IndexOf($filter.Text, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }
            elseif (-not $filter.Allowed.Contains([string]$value)) { return $false }
        }
        $true
    }.GetNewClosure()
}

function Get-ColumnFilterChoice($State, [string]$Key, [string]$Query) {
    # A column's list: each value of the rows the filter box ($Query) and the other columns' filters let through, as
    # Excel does, once whatever its case, with how many rows have it, and ticked when the column's filter keeps it (or
    # it has none). The empty value first, then in the column's Order, then alphabetical. A plain loop: thousands of
    # rows.
    $spec = $State.Specs[$Key]
    $others = @(foreach ($other in $State.Active.Keys) { if ($other -ne $Key) { $State.Active[$other] } })
    $property = $spec.Property
    $counts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $State.Grid.ItemsSource) {
        if ($Query -and -not $row.Text.Contains($Query)) { continue }
        $through = $true
        foreach ($filter in $others) {
            $value = $row.($filter.Property)
            if ($filter.Kind -eq 'Age') {
                if ($null -eq $value -or '' -eq $value) { if (-not $filter.Never) { $through = $false; break } }
                elseif (([string]::CompareOrdinal($value, $filter.Cutoff) -lt 0) -ne $filter.AtLeast) { $through = $false; break }
                continue
            }
            if ($null -eq $value -or '' -eq $value) { $value = $filter.Empty }
            if ($filter.Kind -eq 'Contains') { if (([string]$value).IndexOf($filter.Text, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { $through = $false; break } }
            elseif (-not $filter.Allowed.Contains([string]$value)) { $through = $false; break }
        }
        if (-not $through) { continue }
        $value = $row.$property
        $value = if ($null -eq $value -or '' -eq $value) { $spec.Empty } else { [string]$value }
        $count = 0
        $null = $counts.TryGetValue($value, [ref]$count)
        $counts[$value] = $count + 1
    }
    $culture = Get-TextCulture
    $order = @($spec.Order | Where-Object { $_ -and $counts.ContainsKey($_) })
    $rest = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $counts.Keys) { if ($value -ne $spec.Empty -and $order -notcontains $value) { $rest.Add($value) } }
    $rest.Sort([System.StringComparer]::Create($culture, $true))
    $active = $State.Active[$Key]
    foreach ($value in @(if ($counts.ContainsKey($spec.Empty)) { $spec.Empty }) + $order + $rest) {
        $checked = if (-not $active) { $true }
        elseif ($active.Kind -eq 'Contains') { $value.IndexOf($active.Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
        else { $active.Allowed.Contains($value) }
        [pscustomobject]@{ Label = $value; Count = $counts[$value].ToString('N0', $culture); Checked = $checked }
    }
}

function Update-ColumnFilterHeader($State) {
    # Each header's funnel, by its Tag: Active when its column is filtered, Filter while the Filtres button is on, none
    # otherwise. A style per column and state, based on the header's own, made once.
    foreach ($column in $State.Grid.Columns) {
        $key = $column.SortMemberPath
        $tag = if ($State.Active.Contains($key)) { 'Active' } elseif ($State.Shown) { 'Filter' }
        if (-not $tag) { $column.HeaderStyle = $State.Bases[$key]; continue }
        $styleKey = "$key|$tag"
        if (-not $State.Styles.ContainsKey($styleKey)) {
            $base = if ($State.Bases[$key]) { $State.Bases[$key] } else { $State.Grid.ColumnHeaderStyle }
            $style = [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader], $base)
            $style.Setters.Add([System.Windows.Setter]::new([System.Windows.FrameworkElement]::TagProperty, $tag))
            $State.Styles[$styleKey] = $style
        }
        $column.HeaderStyle = $State.Styles[$styleKey]
    }
    # The Filtres button says how many columns are filtered.
    $text = $State.Toggle.FindName("$($State.Prefix)column_filters_text")
    $text.Text = if ($State.Active.Count) { (Tr 'Filtres ({0})') -f $State.Active.Count } else { Tr 'Filtres' }
}

function Clear-ColumnFilter($State, [string]$Key) {
    # One column's filter, or all of them. The caller shows the rows again (OnChange), unless new ones replace them.
    if ($Key) { $State.Active.Remove($Key) } else { $State.Active.Clear() }
    $State.List = @($State.Active.Values)
    Update-ColumnFilterHeader $State
}

function Sync-ColumnFilter($State) {
    # A filtered column that's no longer shown is no longer filtered: nothing would say it is. Returns whether one was.
    if (-not $State) { return $false }
    $hidden = @($State.Active.Keys | Where-Object { $key = $_; @($State.Grid.Columns | Where-Object { $_.SortMemberPath -eq $key -and $_.Visibility -ne 'Visible' }).Count })
    foreach ($key in $hidden) { $State.Active.Remove($key) }
    if ($hidden.Count) {
        $State.List = @($State.Active.Values)
        Update-ColumnFilterHeader $State
    }
    $hidden.Count -gt 0
}

function Open-PendingColumnFilter {
    $pending = $script:PendingColumnFilter
    $script:PendingColumnFilter = $null
    if ($pending) { Open-ColumnFilter $pending.State $pending.Header }
}

function Get-ColumnFilterPopup($State) {
    # The list's popup, made the first time: in the grid's panel, so it takes the window's font and text size.
    if ($State.Popup) { return $State.Popup }
    $xaml = (Expand-Icon $script:ColumnFilterXaml).Replace('colfilter_', "$($State.Prefix)colfilter_")
    $content = [System.Windows.Markup.XamlReader]::Parse($xaml)
    $popup = [System.Windows.Controls.Primitives.Popup]::new()
    $popup.Name = "$($State.Prefix)colfilter_popup"
    $popup.Child = $content
    $popup.StaysOpen = $false
    $popup.AllowsTransparency = $true
    $popup.Placement = 'Bottom'
    $null = $State.Grid.Parent.Children.Add($popup)
    $part = { param($name) $content.FindName("$($State.Prefix)colfilter_$name") }
    $State.Parts = @{
        Title = & $part 'title'; SearchField = & $part 'search_field'; Search = & $part 'search'; Hint = & $part 'hint'
        All = & $part 'all'; ListArea = & $part 'list_area'; List = & $part 'values'; None = & $part 'none'
        Age = & $part 'age'; AtLeast = & $part 'age_atleast'; Less = & $part 'age_less'; Number = & $part 'age_number'; Never = & $part 'age_never'
        # Get-ColumnFilterCutoff's Unit is its button's place: jours, semaines, mois, ans.
        Units = @(0..3 | ForEach-Object { & $part "age_unit$_" })
        Ok = & $part 'ok'; Cancel = & $part 'cancel'; Clear = & $part 'clear'
    }
    $State.Popup = $popup
    foreach ($control in @($State.Parts.Values | Where-Object { $_ -isnot [array] }) + $content + $popup) { $script:ColumnFilters[$control.Name] = $State }

    $State.Parts.Search.Add_TextChanged({
        param($box)
        $state = $script:ColumnFilters[$box.Name]
        $state.Search = "$($box.Text)".Trim()
        if ($state.ItemView) { $state.ItemView.Refresh() }
        Update-ColumnFilterAll $state
    })
    $State.Parts.Number.Add_TextChanged({ param($box) Update-ColumnFilterAll $script:ColumnFilters[$box.Name] })
    # « Jamais » goes with « plus de » (never logged on is as inactive as can be), not with « moins de ».
    $directionChosen = {
        param($button)
        $state = $script:ColumnFilters[$button.Name]
        if (-not $state.Updating) { $state.Parts.Never.IsChecked = $button -eq $state.Parts.AtLeast }
    }
    $State.Parts.AtLeast.Add_Checked($directionChosen)
    $State.Parts.Less.Add_Checked($directionChosen)
    # Tout sélectionner ticked or unticked, by a click or a screen reader (not by Update-ColumnFilterAll): every value
    # shown follows.
    $allChanged = {
        param($box)
        $state = $script:ColumnFilters[$box.Name]
        if ($state.Updating) { return }
        foreach ($item in $state.ItemView) { $item.Checked = [bool]$box.IsChecked }
        # The items don't tell the list they changed: it draws them again.
        $state.ItemView.Refresh()
        Update-ColumnFilterAll $state
    }
    $State.Parts.All.Add_Checked($allChanged)
    $State.Parts.All.Add_Unchecked($allChanged)
    # A value ticked or unticked, or drawn again as the list scrolls: Tout sélectionner and OK follow, once for all the
    # values that changed together, and once their bindings have updated the items.
    $valueChanged = [System.Windows.RoutedEventHandler]{ param($list, $e) Request-ColumnFilterAll $script:ColumnFilters[$list.Name] }
    $State.Parts.List.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $valueChanged)
    $State.Parts.List.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $valueChanged)
    $State.Parts.Ok.Add_Click({ param($button) Save-ColumnFilter $script:ColumnFilters[$button.Name] })
    $State.Parts.Cancel.Add_Click({ param($button) $script:ColumnFilters[$button.Name].Popup.IsOpen = $false })
    $State.Parts.Clear.Add_Click({
        param($button)
        $state = $script:ColumnFilters[$button.Name]
        $state.Popup.IsOpen = $false
        if (-not $state.Active.Contains($state.Key)) { return }
        Clear-ColumnFilter $state $state.Key
        & $state.OnChange $state
    })
    # Entrée applies (but on a button, which does its own), Échap closes.
    $content.Add_PreviewKeyDown({
        param($content, $e)
        $state = $script:ColumnFilters[$content.Name]
        if ($e.Key -eq 'Escape') { $state.Popup.IsOpen = $false; $e.Handled = $true }
        elseif ($e.Key -eq 'Return' -and [System.Windows.Input.Keyboard]::FocusedElement -isnot [System.Windows.Controls.Primitives.ButtonBase] -and $state.Parts.Ok.IsEnabled) {
            Save-ColumnFilter $state
            $e.Handled = $true
        }
    })
    $popup.Add_Opened({
        param($popup)
        $state = $script:ColumnFilters[$popup.Name]
        if ($state.Specs[$state.Key].Mode -eq 'Age') {
            $null = $state.Parts.Number.Focus()
            $state.Parts.Number.SelectAll()
        }
        else { $null = $state.Parts.Search.Focus() }
    })
    $popup
}

function Open-ColumnFilter($State, $Header) {
    # A column's filter, under its header, as its Mode has it: what it's filtered by now, or everything.
    if (-not $State -or -not $Header -or -not $Header.Column) { return }
    $column = $Header.Column
    $popup = Get-ColumnFilterPopup $State
    $parts = $State.Parts
    $State.Key = $column.SortMemberPath
    $State.Title = [string]$column.Header
    $mode = $State.Specs[$State.Key].Mode
    $active = $State.Active[$State.Key]
    $State.Search = ''
    $State.Items = $null
    $State.ItemView = $null
    $parts.List.ItemsSource = $null
    $parts.SearchField.Visibility = ConvertTo-Visibility ($mode -ne 'Age')
    $parts.Age.Visibility = ConvertTo-Visibility ($mode -eq 'Age')
    $parts.All.Visibility = ConvertTo-Visibility ($mode -eq 'Values')
    $parts.ListArea.Visibility = ConvertTo-Visibility ($mode -eq 'Values')
    $parts.Search.Tag = if ($mode -eq 'Text') { Tr 'Contient…' } else { Tr 'Rechercher une valeur' }
    if ($mode -eq 'Values') {
        $query = Get-ColumnFilterQuery $State
        $State.Items = [System.Collections.Generic.List[object]]::new()
        # Tens of thousands of rows (Tout afficher) take a second or two.
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        try { foreach ($item in @(Get-ColumnFilterChoice $State $State.Key $query)) { $State.Items.Add($item) } }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
        $State.ItemView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($State.Items)
        # The search in the list, anywhere in a value, as a Contains rule finds it.
        $State.ItemView.Filter = [Predicate[object]]{
            param($item)
            -not $State.Search -or $item.Label.IndexOf($State.Search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        }.GetNewClosure()
        $parts.List.ItemsSource = $State.Items
    }
    if ($mode -eq 'Age') {
        # As filtered now, else 90 days or more, with « Jamais » (Inactifs depuis' first duration).
        $rule = if ($active) { $active } else { New-ColumnFilterRule $State.Specs[$State.Key] 'Age' }
        $State.Updating = $true
        try {
            $parts.AtLeast.IsChecked = $rule.AtLeast
            $parts.Less.IsChecked = -not $rule.AtLeast
            $parts.Units[$rule.Unit].IsChecked = $true
            $parts.Never.IsChecked = $rule.Never
        }
        finally { $State.Updating = $false }
        $parts.Number.Text = if ($active) { [string]$rule.Number } else { '90' }
    }
    # A Contains rule shows its text, and the values it finds.
    $parts.Search.Text = if ($active -and $active.Kind -eq 'Contains') { $active.Text } else { '' }
    $parts.Title.Text = (Tr 'Filtrer : {0}') -f $State.Title
    $parts.Clear.IsEnabled = $State.Active.Contains($State.Key)
    Update-ColumnFilterAll $State
    $popup.PlacementTarget = $Header
    $popup.IsOpen = $true
}

function Get-ColumnFilterNumber($State) {
    # An Age filter's number, from 1 to 999, or 0 when it isn't one.
    $number = 0
    if (-not [int]::TryParse("$($State.Parts.Number.Text)".Trim(), [ref]$number) -or $number -lt 1 -or $number -gt 999) { return 0 }
    $number
}

function Get-ColumnFilterQuery($State) {
    # The filter box's text, as the page keeps it (lowercase).
    [string]$State.Holder[$State.QueryKey]
}

function Update-ColumnFilterAll($State) {
    # OK and the hint follow what's typed or ticked. Values: Tout sélectionner follows the values shown (ticked when all
    # are, empty when none is, in between otherwise), and OK needs one ticked. Text: an empty text clears the filter.
    # Age: OK needs a number.
    $mode = $State.Specs[$State.Key].Mode
    $hint = ''
    if ($mode -eq 'Age') {
        $ok = (Get-ColumnFilterNumber $State) -gt 0
        if (-not $ok) { $hint = Tr 'Entrez un nombre de 1 à 999.' }
    }
    elseif ($mode -eq 'Text') {
        $ok = $true
        $hint = if ($State.Search) { (Tr 'OK : {0} contient « {1} »') -f $State.Title, $State.Search } else { Tr 'Tapez le texte que cette colonne doit contenir.' }
    }
    else {
        $shown = @($State.ItemView)
        $checked = @($shown | Where-Object Checked).Count
        $State.Updating = $true
        try { $State.Parts.All.IsChecked = if ($shown.Count -and $checked -eq $shown.Count) { $true } elseif ($checked) { $null } else { $false } }
        finally { $State.Updating = $false }
        $State.Parts.All.IsEnabled = $shown.Count -gt 0
        $State.Parts.None.Visibility = ConvertTo-Visibility (-not $shown.Count)
        $ok = $checked -gt 0
        # Every value found still ticked: OK keeps what contains the text, not only these values.
        if ($State.Search -and $checked -eq $shown.Count -and $ok) { $hint = (Tr 'OK : {0} contient « {1} »') -f $State.Title, $State.Search }
    }
    $State.Parts.Ok.IsEnabled = $ok
    $State.Parts.Hint.Text = $hint
    $State.Parts.Hint.Visibility = ConvertTo-Visibility ([bool]$hint)
}

function Request-ColumnFilterAll($State) {
    # Update-ColumnFilterAll, once the values ticked together are all ticked.
    if ($State.AllPending) { return }
    $State.AllPending = $true
    $script:PendingColumnFilterAll = $State
    $null = $State.Popup.Dispatcher.BeginInvoke([Action]{
        $state = $script:PendingColumnFilterAll
        $state.AllPending = $false
        Update-ColumnFilterAll $state
    })
}

function Save-ColumnFilter($State) {
    # OK. Values: the values ticked among those shown (a search in the list keeps only what it found, as Excel does),
    # or what contains the search when all it found are ticked; all of a column's values ticked, without a search: no
    # filter. Text: what contains it, or no filter without text. Age: that long ago, from today.
    $spec = $State.Specs[$State.Key]
    $rule = $null
    if ($spec.Mode -eq 'Age') {
        $number = Get-ColumnFilterNumber $State
        if (-not $number) { return }
        $rule = New-ColumnFilterRule $spec 'Age'
        $rule.Number = $number
        $rule.Unit = [Math]::Max(0, [array]::IndexOf($State.Parts.Units, @($State.Parts.Units | Where-Object IsChecked)[0]))
        $rule.AtLeast = -not $State.Parts.Less.IsChecked
        $rule.Never = [bool]$State.Parts.Never.IsChecked
        $rule.Cutoff = Get-ColumnFilterCutoff $number $rule.Unit (Get-Date)
    }
    elseif ($spec.Mode -eq 'Text') {
        if ($State.Search) { $rule = New-ColumnFilterRule $spec 'Contains'; $rule.Text = $State.Search }
    }
    else {
        $shown = @($State.ItemView)
        $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $shown) { if ($item.Checked) { $null = $allowed.Add($item.Label) } }
        if (-not $allowed.Count) { return }
        if ($State.Search -and $allowed.Count -eq $shown.Count) { $rule = New-ColumnFilterRule $spec 'Contains'; $rule.Text = $State.Search }
        elseif ($State.Search -or $allowed.Count -ne $State.Items.Count) { $rule = New-ColumnFilterRule $spec 'Values'; $rule.Allowed = $allowed }
    }
    $State.Popup.IsOpen = $false
    if ($rule) { $State.Active[$State.Key] = $rule } else { $State.Active.Remove($State.Key) }
    $State.List = @($State.Active.Values)
    Update-ColumnFilterHeader $State
    & $State.OnChange $State
}
