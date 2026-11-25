# The Utilisateurs and Groupes pages' search (SearchPage.ps1), on the users' page with only the controls a search reads:
# what Tout afficher runs again after a search cancelled before any domain answered (#235), a search asked for while
# another runs (#237), the cancelled jobs the page's timer disposes of (#237), and the width a column resized keeps
# (#277).

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    # ComputerPage.ps1 loads only with the window: Remove-StoppedJob alone, from its source.
    $computerPage = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerPage.ps1')
    $definition = $computerPage.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-StoppedJob' }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    # What the main script and ComputerPage.ps1 (not loaded without the window) give every page: the cancelled jobs
    # still ending, the row builder the search runspaces are passed (unused by the scripts here), the domains offered,
    # ConvertTo-Visibility, and Save-SearchSetting (nothing saved here).
    $script:search = @{ Current = $null; Stopping = [System.Collections.Generic.List[object]]::new(); Dialogs = 0 }
    $script:rowBuilderScript = ''
    $script:showDomains = $true
    $script:defaultDomain = 'demo.local'
    function ConvertTo-Visibility([bool]$Visible) {
        if ($Visible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    function Save-SearchSetting {}

    function New-TestPage([string]$Script) {
        # The users' page, its rows those of a search for « bert » in demo.local that found more than the limit, and
        # $Script as its search runspaces' script.
        $root = [System.Windows.Markup.XamlReader]::Parse(@'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <ComboBox x:Name="user_domain"/>
  <ComboBox x:Name="user_search_type"/>
  <TextBox x:Name="user_query"/>
  <Border x:Name="user_search_hint"><TextBlock/></Border>
  <Button x:Name="user_search"/>
  <Button x:Name="user_cancel"/>
  <Button x:Name="user_show_all"/>
  <Button x:Name="user_export"/>
  <TextBlock x:Name="user_count"/>
  <TextBlock x:Name="user_time"/>
  <Border x:Name="user_not_found"/>
  <Border x:Name="user_empty"/>
</StackPanel>
'@)
        foreach ($domain in @(Tr 'Tous les domaines') + $script:domainList) { $null = $root.FindName('user_domain').Items.Add($domain) }
        foreach ($type in $script:UserPage.Types.Keys) { $null = $root.FindName('user_search_type').Items.Add($type) }
        $root.FindName('user_search_type').SelectedItem = Tr 'Nom, identifiant ou courriel'
        $page = $script:UserPage.Clone()
        $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new([object[]]@([pscustomobject]@{ Name = 'Bertrand' }))
        $page.Root = $root; $page.Script = $Script; $page.Search = $null; $page.Timer = [System.Windows.Threading.DispatcherTimer]::new()
        $page.Rows = $rows; $page.View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($rows); $page.Errors = [ordered]@{}; $page.NotFound = @()
        $page.Truncated = @{ Domains = @('demo.local'); Limit = 1; MultiDomain = $false }
        $page.LastRequest = @{ Filter = '(anr=bert)'; Domains = @('demo.local'); Extra = @{}; Type = (Tr 'Nom, identifiant ou courriel'); Text = 'bert'; Limit = 1 }
        $page
    }

    function Start-WiderSearch($Page) {
        # Rechercher, for « a » in every domain.
        $Page.Root.FindName('user_domain').SelectedItem = Tr 'Tous les domaines'
        $Page.Root.FindName('user_query').Text = 'a'
        Invoke-PageSearch $Page
    }

    function Wait-StoppedJob {
        foreach ($job in @($script:search.Stopping)) {
            $null = $job.Handle.AsyncWaitHandle.WaitOne(10000)
            $job.Shell.Dispose()
        }
        $script:search.Stopping.Clear()
    }
}

Describe 'Tout afficher after a search cancelled before any domain answered (#235)' {
    BeforeEach { $script:SavedPageSearchSettings = $script:PageSearchSettings.Clone() }
    AfterEach {
        Wait-StoppedJob
        if ($script:searchPool) { $script:searchPool.Dispose(); $script:searchPool = $null }
        $script:PageSearchSettings = $script:SavedPageSearchSettings
    }

    It 'Runs the search shown again, when the runspaces were not ready yet' {
        # A pool not opened: the search has no job yet when it's cancelled.
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 2)
        $page = New-TestPage ''
        $shown = $page.LastRequest
        Start-WiderSearch $page
        $page.Search.Request.Text | Should -BeExactly 'a'
        Stop-PageSearch $page
        $page.Search | Should -BeNullOrEmpty
        $page.LastRequest.Text | Should -BeExactly 'bert'
        [object]::ReferenceEquals($page.LastRequest, $shown) | Should -BeTrue
        $page.Root.FindName('user_show_all').Visibility | Should -Be 'Visible'
        Show-PageAll $page
        $page.Search.Request.Filter | Should -BeExactly '(anr=bert)'
        @($page.Search.Request.Domains) | Should -Be @('demo.local')
        $page.Search.Request.Limit | Should -Be 0
        $page.Search.Request.KeepFilters | Should -BeTrue
        Stop-PageSearch $page
    }

    It 'Runs the search shown again, when every domain was stopped before it answered' {
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 2)
        $script:searchPool.Open()
        # Each domain takes long enough to be stopped first.
        $page = New-TestPage 'param($Domain, $LdapFilter, $RowBuilder, $Limit, $LockedOnly, $Today, $Clock) Start-Sleep -Seconds 30'
        $shown = $page.LastRequest
        Start-WiderSearch $page
        @($page.Search.Jobs).Count | Should -Be 2
        Stop-PageSearch $page
        $page.LastRequest.Text | Should -BeExactly 'bert'
        [object]::ReferenceEquals($page.LastRequest, $shown) | Should -BeTrue
        $page.Root.FindName('user_count').Text | Should -BeLike '1 utilisateur · limite de 1 atteinte*'
        $page.Root.FindName('user_show_all').Visibility | Should -Be 'Visible'
        Show-PageAll $page
        $page.Search.Request.Filter | Should -BeExactly '(anr=bert)'
        $page.Search.Request.Limit | Should -Be 0
        Stop-PageSearch $page
    }
}

Describe 'A column resized keeps its width (#277)' {
    BeforeAll {
        function New-TestGrid {
            # A window with a grid like the users' page: pixel columns and star ones, Domaine among them to hide.
            $window = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="1000" Height="300" Left="-3000" Top="0" ShowActivated="False" ShowInTaskbar="False">
  <DataGrid AutoGenerateColumns="False" CanUserResizeColumns="True">
    <DataGrid.Columns>
      <DataGridTextColumn Header="État" Width="105"/>
      <DataGridTextColumn Header="Nom" Width="1.5*" MinWidth="130"/>
      <DataGridTextColumn Header="Identifiant" Width="*" MinWidth="95"/>
      <DataGridTextColumn Header="Domaine" Width="125"/>
      <DataGridTextColumn Header="Emplacement" Width="*" MinWidth="105"/>
    </DataGrid.Columns>
  </DataGrid>
</Window>
'@)
            $window.Show()
            $window.UpdateLayout()
            # The grid works out its columns' room once the dispatcher has run what the layout queued.
            $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
            Register-ColumnResize $window.Content
            $window
        }

        function Get-Gripper($Grid, [string]$Header, [string]$Edge) {
            # A column header's left or right edge, the thumb a drag or a double-click resizes the column with.
            $found = [System.Collections.Generic.Stack[object]]::new()
            $found.Push($Grid)
            while ($found.Count) {
                $element = $found.Pop()
                if ($element -is [System.Windows.Controls.Primitives.DataGridColumnHeader] -and $element.Column -and "$($element.Column.Header)" -eq $Header) {
                    return $element.Template.FindName("PART_$($Edge)HeaderGripper", $element)
                }
                for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($element); $i++) { $found.Push([System.Windows.Media.VisualTreeHelper]::GetChild($element, $i)) }
            }
        }

        function Invoke-HeaderDrag($Grid, [string]$Header, [string]$Edge, [double]$By) {
            # What a drag of the header's edge does: WPF's own resizing, step by step, then the edge let go.
            $gripper = Get-Gripper $Grid $Header $Edge
            $gripper.RaiseEvent([System.Windows.Controls.Primitives.DragStartedEventArgs]::new(0, 0))
            for ($i = 0; $i -lt 5; $i++) {
                $gripper.RaiseEvent([System.Windows.Controls.Primitives.DragDeltaEventArgs]::new($By / 5, 0))
                $Grid.UpdateLayout()
            }
            $gripper.RaiseEvent([System.Windows.Controls.Primitives.DragCompletedEventArgs]::new($By, 0, $false))
            $Grid.UpdateLayout()
        }

        function Get-TestColumn($Grid, [string]$Header) { @($Grid.Columns | Where-Object { "$($_.Header)" -eq $Header })[0] }
    }

    It 'Keeps the width a star column was dragged to when another column is hidden or the window narrows' {
        $window = New-TestGrid
        try {
            $grid = $window.Content
            $name = Get-TestColumn $grid 'Nom'
            Invoke-HeaderDrag $grid 'Nom' 'Right' 80
            $chosen = $name.ActualWidth
            $name.Width.UnitType | Should -Be 'Pixel'
            (Get-SavedColumnWidth $name).Unit | Should -BeExactly 'Pixel'
            (Get-SavedColumnWidth $name).Width | Should -Be ([Math]::Round($chosen, 2))
            # Domaine hidden (a search of one domain), then a narrower window: Nom stays as wide, the stars share the rest.
            (Get-TestColumn $grid 'Domaine').Visibility = 'Collapsed'
            $window.Width = 900
            $window.UpdateLayout()
            $name.ActualWidth | Should -Be $chosen
            (Get-TestColumn $grid 'Identifiant').Width.IsStar | Should -BeTrue
        }
        finally { $window.Close() }
    }

    It 'Resizes the column shown before a header from its left edge' {
        $window = New-TestGrid
        try {
            $grid = $window.Content
            Invoke-HeaderDrag $grid 'Identifiant' 'Left' 60
            (Get-TestColumn $grid 'Nom').Width.UnitType | Should -Be 'Pixel'
            (Get-TestColumn $grid 'Identifiant').Width.IsStar | Should -BeTrue
        }
        finally { $window.Close() }
    }

    It 'Saves a column fitted to its content as wide as it shows' {
        $window = New-TestGrid
        try {
            $grid = $window.Content
            $gripper = Get-Gripper $grid 'Nom' 'Right'
            $click = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, 'Left')
            $click.RoutedEvent = [System.Windows.Controls.Control]::MouseDoubleClickEvent
            $gripper.RaiseEvent($click)
            $grid.UpdateLayout()
            $name = Get-TestColumn $grid 'Nom'
            $name.Width.IsAuto | Should -BeTrue
            $saved = Get-SavedColumnWidth $name
            $saved.Unit | Should -BeExactly 'Pixel'
            $saved.Width | Should -Be ([Math]::Round($name.ActualWidth, 2))
            $saved.Width | Should -BeGreaterOrEqual 30
        }
        finally { $window.Close() }
    }
}

Describe 'A search asked for while another runs (#237)' {
    BeforeEach {
        $script:SavedPageSearchSettings = $script:PageSearchSettings.Clone()
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 4)
        $script:searchPool.Open()
    }
    AfterEach {
        Wait-StoppedJob
        if ($script:searchPool) { $script:searchPool.Dispose(); $script:searchPool = $null }
        $script:PageSearchSettings = $script:SavedPageSearchSettings
    }

    It 'Replaces it, from Entrée or Rechercher, and is the recent search first' {
        $page = New-TestPage 'param($Domain, $LdapFilter, $RowBuilder, $Limit, $LockedOnly, $Today, $Clock) Start-Sleep -Seconds 30'
        Start-WiderSearch $page
        $running = @($page.Search.Jobs)
        $page.Root.FindName('user_domain').SelectedItem = 'demo.local'
        $page.Root.FindName('user_query').Text = 'durand'
        Invoke-PageSearch $page
        $page.Search.Request.Text | Should -BeExactly 'durand'
        @($page.Search.Request.Domains) | Should -Be @('demo.local')
        # The one replaced was stopped, its jobs left to Remove-StoppedJob.
        foreach ($job in $running) {
            $job.Cancelled | Should -BeTrue
            $script:search.Stopping.Contains($job) | Should -BeTrue
        }
        (Get-PageSearchSetting $page).Recent[0].Text | Should -BeExactly 'durand'
        Stop-PageSearch $page
    }

    It 'Replaces it with a recent search' {
        $page = New-TestPage 'param($Domain, $LdapFilter, $RowBuilder, $Limit, $LockedOnly, $Today, $Clock) Start-Sleep -Seconds 30'
        Start-WiderSearch $page
        $type = $script:UserPage.Types[(Tr 'Nom, identifiant ou courriel')].Id
        Use-PageRecent $page @{ Domain = 'demo.local'; Type = $type; Text = 'bert' }
        $page.Search.Request.Text | Should -BeExactly 'bert'
        @($page.Search.Request.Domains) | Should -Be @('demo.local')
        $recent = (Get-PageSearchSetting $page).Recent[0]
        "$($recent.Domain)|$($recent.Type)|$($recent.Text)" | Should -BeExactly "demo.local|$type|bert"
        Stop-PageSearch $page
    }

    It 'Disposes of the jobs it stopped on its own timer, which then stops' {
        # Stopped, the jobs end a moment later, as a query does once its DC lets go: they're waited for, then a tick.
        $page = New-TestPage 'param($Domain, $LdapFilter, $RowBuilder, $Limit, $LockedOnly, $Today, $Clock) Start-Sleep -Seconds 30'
        Start-WiderSearch $page
        Stop-PageSearch $page
        $stopped = @($script:search.Stopping)
        $stopped.Count | Should -Be 2
        $page.Timer.IsEnabled | Should -BeTrue
        foreach ($job in $stopped) { $job.Handle.AsyncWaitHandle.WaitOne(10000) | Should -BeTrue }
        Update-PageSearch $page
        $script:search.Stopping.Count | Should -Be 0
        $page.Timer.IsEnabled | Should -BeFalse
    }
}

Describe "The search time's tooltip, a table (#334)" {
    BeforeAll {
        # Two domains, one with a long name, as the search runspaces time them; and a number as the page writes it.
        $script:timings = [ordered]@{
            'demo.local'                                 = @{ Query = 1234; Rows = 56; Count = 2 }
            'succursale-europe.filiale.entreprise.local' = @{ Query = 7; Rows = 0; Count = 1500 }
        }
        function Format-TestNumber([long]$Number) { $Number.ToString('N0', (Get-TextCulture)) }
    }

    It 'Puts each domain on a row, its times and count under their column, then the grid' {
        $table = Get-SearchTimingTable $script:timings 89 $script:PageCountTexts['user']
        @($table.Columns) | Should -Be @('AD', 'Lignes', 'Utilisateurs')
        @($table.Domains.Name) | Should -Be @('demo.local', 'succursale-europe.filiale.entreprise.local')
        @($table.Domains[0].Cells) | Should -Be @("$(Format-TestNumber 1234) ms", '56 ms', '2')
        @($table.Domains[1].Cells) | Should -Be @('7 ms', '0 ms', (Format-TestNumber 1500))
        $table.Grid | Should -BeExactly '89 ms'
    }

    It 'Keeps the sentences for screen readers, the computers'' by default' {
        $table = Get-SearchTimingTable $script:timings 89 $null
        $table.Columns[2] | Should -BeExactly 'Ordinateurs'
        @($table.Lines) | Should -Be @("demo.local : AD $(Format-TestNumber 1234) ms, lignes 56 ms (2 ordinateurs)",
                                       "succursale-europe.filiale.entreprise.local : AD 7 ms, lignes 0 ms ($(Format-TestNumber 1500) ordinateurs)",
                                       'Grille : 89 ms')
        (Get-SearchTimingTable ([ordered]@{}) 3 $script:PageCountTexts['group']).Lines | Should -Be @('Grille : 3 ms')
    }

    It 'Draws the table, a long name wrapping at its dots, and gives its lines as the help text; $null clears both' {
        $target = [System.Windows.Controls.TextBlock]::new()
        $table = Get-SearchTimingTable $script:timings 89 $script:PageCountTexts['group']
        Set-SearchTimingTip $target $table
        $target.ToolTip | Should -BeOfType [System.Windows.Controls.ToolTip]
        $grid = $target.ToolTip.Content
        $grid.ColumnDefinitions.Count | Should -Be 4
        $cell = { param($Row, $Column) @($grid.Children | Where-Object { [System.Windows.Controls.Grid]::GetRow($_) -eq $Row -and [System.Windows.Controls.Grid]::GetColumn($_) -eq $Column -and $_ -is [System.Windows.Controls.TextBlock] })[0] }
        (& $cell 0 3).Text | Should -BeExactly 'Groupes'
        $long = & $cell 2 0
        $long.Text | Should -BeExactly "succursale-europe.$([char]0x200B)filiale.$([char]0x200B)entreprise.$([char]0x200B)local"
        $long.TextWrapping | Should -Be 'Wrap'
        (& $cell 2 3).Text | Should -BeExactly (Format-TestNumber 1500)
        (& $cell 2 3).HorizontalAlignment | Should -Be 'Right'
        # The line, then the grid's time under the AD column.
        @($grid.Children | Where-Object { $_ -is [System.Windows.Controls.Border] -and [System.Windows.Controls.Grid]::GetRow($_) -eq 3 }).Count | Should -Be 1
        "$((& $cell 4 0).Text) | $((& $cell 4 1).Text)" | Should -BeExactly 'Grille | 89 ms'
        [System.Windows.Automation.AutomationProperties]::GetHelpText($target) | Should -BeExactly ($table.Lines -join "`n")
        Set-SearchTimingTip $target $null
        $target.ToolTip | Should -BeNullOrEmpty
        [System.Windows.Automation.AutomationProperties]::GetHelpText($target) | Should -BeNullOrEmpty
    }
}

Describe 'Get-ADFilterText: a text typed, in a -like clause of -Filter' {
    It '<Text>' -ForEach @(
        @{ Text = 'accueil'; Expected = 'accueil' }
        @{ Text = 'a*b'; Expected = 'a\2ab' }
        @{ Text = 'DEMO\jbertrand'; Expected = 'DEMO\5cjbertrand' }
        # The backslash first: an escape typed is that text, not the star.
        @{ Text = '\2a'; Expected = '\5c2a' }
        @{ Text = "salle d'accueil (2e)"; Expected = "salle d''accueil (2e)" }
    ) {
        Get-ADFilterText $Text | Should -BeExactly $Expected
    }

    It 'Finds that text only, in the fake AD' {
        $all = @(Get-ADComputer -Server demo.local -Filter "Description -like '*'")
        $all.Count | Should -BeGreaterThan 0
        @(Get-ADComputer -Server demo.local -Filter "Description -like '*$(Get-ADFilterText '*')*'").Count | Should -Be @($all | Where-Object { "$($_.Description)".Contains('*') }).Count
    }
}
