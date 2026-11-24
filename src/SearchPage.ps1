# What the Utilisateurs and Groupes pages share: their search (in the background, one domain or all of them), the count
# under the grid, the filter box, Exporter, Copier, Propriétés…, their keys (Ctrl+F, F5, Entrée, Ctrl+C) and their
# columns. Each page is a hashtable ($script:UserPage, UserPage.ps1; $script:GroupPage, GroupPage.ps1) holding its state
# (its Root once built, whether it's Shown, its Rows and their View, the Search under way and its Timer, the Filter
# box's text and its FilterTimer, the domains' Errors, MultiDomain, a list's entries NotFound and the Unanswered domains
# where they may be) and what differs between the pages, as data:
#   Prefix        the start of its control names (user_query, group_grid…), which double as UI Automation ids.
#   (The count's and the empty grid's words, « 1 utilisateur », « Aucun groupe trouvé », are $script:PageCountTexts',
#   by Prefix: English doesn't make them from a noun as French does.)
#   Types         its search types: its Id (saved), the LDAP Clause each adds, whether it NeedsText (and Prompt when it's
#                 missing), the Match its text adds ({0}: the text, escaped), the query box's Tag, and ScopeText for the scope.
#                 A list (Liste d'identifiants, Liste de noms) has List instead of Match: the function that reads its
#                 entries from the text, ListMatch (the clauses of one entry, escaped, ORed with the others') and TooMany.
#   SearchSetting its key in $PageSearchSettings: the search it was left on and its recent searches.
#   Ldap          the filter every search makes ({0}: the type's clauses); Script, the search runspace's script, given
#                 Domain, LdapFilter, RowBuilder, Limit, what Parameters returns for the type and, for a list, its
#                 Entries. It returns Domain, Rows, Error, Truncated (more than Limit found: the first Limit kept) and,
#                 for a list, the entries its rows Matched.
#   Action        the function that follows the selection (its buttons); Detail, the one that opens Propriétés…
#                 for a row, which has RowProperty (a double-click on a header has none).
#   Copy          the property Copier and Ctrl+C copy; Copied, each property's words for several rows.
#   Export        Exporter's Title and FileName; its Fields and Last, what the columns write (Get-ExportField).
#   Setting, Hidden, Columns   its columns (Initialize-PageColumn).
#   FilterSpecs   what its columns' filters read (a script block giving Initialize-ColumnFilter's Specs), and
#                 ColumnFilter, its filters once made (ColumnFilter.ps1).
# Dot-sourced by the main script, after Theme.ps1 (Expand-Icon, Save-Appearance) and before UserPage.ps1 and
# GroupPage.ps1; uses the main script's search runspaces ($searchPool), domains and dialogs, and ComputerPage.ps1's row
# builder.

# The pages built, by prefix: their controls' handlers find their page by name (Get-ControlPage).
$script:SearchPages = @{}
# The rows a search shows per domain at most, every page's (the computers' too): a search that finds more says so, and
# Tout afficher runs it again without the limit. A one-letter prefix or « Description contient e » would otherwise make
# a DC send a whole domain. $env:REPERE_SEARCH_LIMIT, for the UI tests, sets another (the sample data is small).
$script:SearchLimit = if ($env:REPERE_SEARCH_LIMIT) { [int]$env:REPERE_SEARCH_LIMIT } else { 2000 }
# How long a domain's search may go without AD sending anything back, in seconds, counted from when it starts on a
# runspace (one waiting for a free runspace isn't counted). Past it, the domain is stopped as Annuler stops it, and the
# other domains' rows show. Only until it answers: once AD sends its first object (or ends a query that found none), the
# search takes as long as it needs. A whole domain is sent in pages of a few hundred objects as AD finds them, so Tout
# afficher on a big domain isn't cut short. A DC that answers sends its first page within seconds. 20 seconds leave
# room for the slowest case, a filter it has no index for (Nom contient, Description contient) that matches few
# objects in a big domain: it scans until the page is full or the domain ends. Twenty seconds with nothing at all
# means the DC has stopped answering, or the network drops what goes to it (Windows gives up on such a connection after
# about 21). The AD module's own wait is longer, and the other domains' rows would wait for it.
$script:SearchAnswerTimeout = 20

function New-SearchClock {
    # What a domain's search says of itself from its runspace, for its time limit (Test-SearchTimedOut): when it
    # Started, and whether AD has Answered yet. The search scripts take it as -Clock.
    [hashtable]::Synchronized(@{ Started = $null; Answered = $false })
}

function Test-SearchTimedOut($Job, [datetime]$Now = [datetime]::UtcNow, [int]$Timeout = $script:SearchAnswerTimeout) {
    # Whether a domain's search, still running, started $Timeout seconds ago or more without AD having answered.
    $clock = $Job['Clock']
    [bool]($clock -and $Job.Handle -and -not $Job.Handle.IsCompleted -and -not $Job['Cancelled'] -and -not $Job['TimedOut'] -and
           $clock.Started -and -not $clock.Answered -and ($Now - [datetime]$clock.Started).TotalSeconds -ge $Timeout)
}

function Stop-SilentSearch($Jobs) {
    # The domains of a search that haven't answered in time (Test-SearchTimedOut): stopped as Annuler stops them, not
    # waited for (Remove-StoppedJob disposes of them once they end), and TimedOut, for the search's result to say so.
    foreach ($job in @($Jobs | Where-Object { Test-SearchTimedOut $_ })) {
        $job.TimedOut = $true
        $null = $job.Shell.BeginStop($null, $null)
        $script:search.Stopping.Add($job)
    }
}

function Get-SearchTimeoutText {
    # Why a domain has no rows when it didn't answer in time, in the count's tooltip and the search's error.
    (Tr 'pas de réponse après {0} secondes (contrôleur de domaine injoignable ?)') -f $script:SearchAnswerTimeout
}
# Each page's count and empty grid, by its prefix: one row, several ({0}: how many), none, and none for a text ({0});
# and in the search time's tooltip, a domain's line as screen readers read it (Format-SearchTiming) and the rows'
# column (Get-SearchTimingTable).
$script:PageCountTexts = @{
    user  = @{ One = Tr '1 utilisateur'; Many = Tr '{0} utilisateurs'; None = Tr 'Aucun utilisateur trouvé.'; NoneFor = Tr 'Aucun utilisateur trouvé pour « {0} ».'
               Timing = Tr '{0} : AD {1} ms, lignes {2} ms ({3} utilisateurs)'; Column = Tr 'Utilisateurs' }
    group = @{ One = Tr '1 groupe'; Many = Tr '{0} groupes'; None = Tr 'Aucun groupe trouvé.'; NoneFor = Tr 'Aucun groupe trouvé pour « {0} ».'
               Timing = Tr '{0} : AD {1} ms, lignes {2} ms ({3} groupes)'; Column = Tr 'Groupes' }
}
# The pages whose columns are saved when Repère closes.
$script:ColumnPages = [System.Collections.Generic.List[object]]::new()
# Each page's search as it was left, by its SearchSetting (Users, Groups): its Domain ('*': all of them), its search Type
# (the type's Id) and its Recent searches (each a Domain, Type and Text, the last one first). Kept in recherche.json
# with the computers' (ComputerPage.ps1: Read-SearchSetting, Save-SearchSetting).
$script:PageSearchSettings = @{ Users = $null; Groups = $null }
$script:MaxPageRecent = 10
# Liste d'identifiants and Liste de noms: the entries one search takes at most (an LDAP filter's length), as the
# computers' Liste de noms.
$script:MaxPageListEntries = 200

function Get-LdapText([string]$Text) {
    # A value as an LDAP filter takes it: *, (, ), \ and NUL escaped, so a name with a parenthesis stays a name.
    $Text.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
}

function ConvertTo-ComputerNameList([string]$Text) {
    # Computer names as pasted from a ticket or a spreadsheet (Ordinateurs › Liste de noms): separated by spaces, commas,
    # semicolons or line breaks, each once whatever its case, without a domain (DEMO\ORD-01, ord-01.demo.local) or the
    # account's trailing $.
    $names = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($part in $Text -split '[\s,;]+') {
        $name = $part -replace '^.*\\', '' -replace '\..*$', '' -replace '\$$', ''
        if ($name -and $seen.Add($name)) { $names.Add($name) }
    }
    # Each name on its own: @() around the call makes the list, empty when there's none.
    $names
}

function ConvertTo-SearchAddress([string]$Text) {
    # Ordinateurs › Adresse IP: the address typed, written the way the DNS gives it back (Address), or why it can't be
    # searched (Problem). IPv4 needs its four numbers: .NET reads « 10.0.1 » as 10.0.0.1 and « 10.1 » as 10.0.0.1, so
    # a part of an address would quietly search another one. A subnet or a range (10.0.1., 10.0.1.*, 10.0.1.0/24) isn't
    # searched either: each computer would have to be looked up in the DNS. 'Incomplete' for those, 'Invalid' for
    # anything else. Leading zeros are read as decimal (010 is 10), not octal as some parsers do.
    $value = "$Text".Trim()
    if ($value -match ':') {
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($value, [ref]$parsed) -and $parsed.AddressFamily -eq 'InterNetworkV6') { return @{ Address = $parsed.ToString(); Problem = $null } }
        return @{ Address = $null; Problem = 'Invalid' }
    }
    $parts = @($value -split '\.')
    $numbers = @($parts | Where-Object { $_ -match '^\d{1,3}$' -and [int]$_ -le 255 })
    if ($parts.Count -eq 4 -and $numbers.Count -eq 4) {
        return @{ Address = ([System.Net.IPAddress]::new([byte[]]@($parts | ForEach-Object { [int]$_ }))).ToString(); Problem = $null }
    }
    # The start of an address (fewer than four numbers, or a dot at the end), or a range (with * / or -): numbers up to
    # 255 and those signs only. Five numbers, an empty one between two dots or 300 are just not an address.
    $tooBig = @([regex]::Matches($value, '\d+') | Where-Object { $_.Value.Length -gt 3 -or [int]$_.Value -gt 255 })
    $partial = $value -match '[*/-]' -or $parts.Count -lt 4 -or ($parts.Count -eq 4 -and $value.EndsWith('.') -and $value -notmatch '\.\.')
    if ($value -match '^\d[\d.*/-]*$' -and -not $tooBig.Count -and $partial) { return @{ Address = $null; Problem = 'Incomplete' } }
    @{ Address = $null; Problem = 'Invalid' }
}

function Add-ListEntry($Entries, $Seen, [string]$Text) {
    # One entry of a list pasted on the Utilisateurs or Groupes page: without its quotes, a stray comma and its domain
    # (DEMO\jdoe), and once whatever its case.
    $entry = $Text.Trim().Trim('"', "'", ',').Trim() -replace '^[^\\\s]+\\(?=\S)', ''
    if ($entry -and $Seen.Add($entry)) { $Entries.Add($entry) }
}

function ConvertTo-UserEntryList([string]$Text) {
    # Users as pasted from an email, a ticket or a spreadsheet (Utilisateurs › Liste d'identifiants), in the first way
    # that fits: one per line or between semicolons, whole entries, which may be display names (Jean Bertrand); on one
    # line, addresses as Outlook copies them, « Jean Bertrand <jdoe@demo.com> », their emails (a comma can be inside
    # « "Bertrand, Jean" »); entries between commas, whole too (Jean Bertrand, Léa Perrin); otherwise logins (jdoe,
    # DEMO\jdoe), UPNs or emails separated by spaces.
    $entries = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $address = '<([^<>\s]+@[^<>\s]+)>'
    $parts = if ($Text -match '[\r\n;]') { $Text -split '[\r\n;]+' }
             elseif ($Text -match $address) { @([regex]::Matches($Text, $address) | ForEach-Object { $_.Value }) }
             elseif ($Text.Contains(',')) { $Text -split ',' }
             else { $Text -split '\s+' }
    foreach ($part in $parts) { Add-ListEntry $entries $seen $(if ($part -match $address) { $Matches[1] } else { $part }) }
    $entries
}

function ConvertTo-GroupEntryList([string]$Text) {
    # Group names as pasted (Groupes › Liste de noms): one per line or between semicolons; on one line, between commas.
    # Never between spaces: group names often have some.
    $entries = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($part in $Text -split $(if ($Text -match '[\r\n;]') { '[\r\n;]+' } else { ',' })) { Add-ListEntry $entries $seen $part }
    $entries
}

function Get-ListText([string[]]$Entries, [int]$Shown = 3) {
    # A list's first entries, then how many more: « a, b, c (+12) ».
    (@($Entries | Select-Object -First $Shown) -join ', ') + $(if ($Entries.Count -gt $Shown) { " (+$($Entries.Count - $Shown))" })
}

function Get-ControlPage($Control) {
    # The page a control belongs to, by its name's prefix (user_query: the users').
    $script:SearchPages[($Control.Name -split '_', 2)[0]]
}

function Show-SearchHint($Hint, [string]$Text, $Under, $Field, $Focus) {
    # What a search is missing, said where the eye already is rather than down in the count: in $Hint (a page's
    # …search_hint, in a Canvas under its search row), just under $Under (a box or a button; the field's start without
    # one), the $Field it's about outlined in red, and the box to fill ($Focus) focused, its text selected to retype.
    # It stays until the search changes (Hide-SearchHint).
    $canvas = $Hint.Parent
    $Hint.Child.Text = $Text
    $Hint.MaxWidth = [math]::Max(120, $canvas.ActualWidth)
    $Hint.Visibility = 'Visible'
    $Hint.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $left = if ($Under) { $Under.TranslatePoint([System.Windows.Point]::new(0, 0), $canvas).X } else { 0 }
    # Kept inside the row: under the last button, it ends where the row does.
    [System.Windows.Controls.Canvas]::SetLeft($Hint, [math]::Max(0, [math]::Min($left, $canvas.ActualWidth - $Hint.DesiredSize.Width)))
    if ($Hint.Tag -and $Hint.Tag -ne $Field) { $Hint.Tag.ClearValue([System.Windows.Controls.Border]::BorderBrushProperty) }
    $Hint.Tag = $Field
    # Its own value outranks the style's, the accent of the focused field included.
    if ($Field) { $Field.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'R.DangerText') }
    if ($Focus -and $Focus.IsEnabled) {
        $null = $Focus.Focus()
        $Focus.SelectAll()
    }
}

function Hide-SearchHint($Hint) {
    # The search changed (a box, the type, the domain) or runs: what was missing no longer is, or will be said again.
    if ($Hint.Visibility -ne 'Visible') { return }
    $Hint.Visibility = 'Collapsed'
    if ($Hint.Tag) { $Hint.Tag.ClearValue([System.Windows.Controls.Border]::BorderBrushProperty) }
    $Hint.Tag = $null
}

function Initialize-SearchPage($Page, $HostControl, [string]$Xaml) {
    # Builds a page the first time its tab is chosen, and wires what every page has. The page's own buttons are wired
    # by its Initialize-…Page.
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $Xaml))
    $HostControl.Content = $root
    $Page.Root = $root
    $prefix = $Page.Prefix
    $script:SearchPages[$prefix] = $Page

    $domainBox = $root.FindName("$($prefix)_domain")
    if ($script:showDomains) {
        # Tous les domaines first, as on the Ordinateurs page.
        foreach ($domain in @(Tr 'Tous les domaines') + $script:domainList) { $null = $domainBox.Items.Add($domain) }
        $domainBox.SelectedItem = $script:defaultDomain
    }
    else { $domainBox.Visibility = 'Collapsed' }
    $typeBox = $root.FindName("$($prefix)_search_type")
    foreach ($type in $Page.Types.Keys) { $null = $typeBox.Items.Add($type) }
    $typeBox.SelectedIndex = 0
    $typeBox.Add_SelectionChanged({
        param($box)
        $page = Get-ControlPage $box
        # The box's placeholder and tooltip say what this type matches.
        $type = $page.Types[[string]$box.SelectedItem]
        $query = $page.Root.FindName("$($page.Prefix)_query")
        $query.Tag = $type['Tag']
        $query.ToolTip = $type['Tip']
        Hide-SearchHint $page.Root.FindName("$($page.Prefix)_search_hint")
        Save-PageSearchChoice $page
    })
    # The domain and search type it was left on.
    $saved = Get-PageSearchSetting $Page
    Select-PageSearch $Page $saved.Domain $saved.Type
    $domainBox.Add_SelectionChanged({
        param($box)
        $page = Get-ControlPage $box
        Hide-SearchHint $page.Root.FindName("$($page.Prefix)_search_hint")
        Save-PageSearchChoice $page
    })
    # What a search was missing goes once something's typed.
    $root.FindName("$($prefix)_query").Add_TextChanged({
        param($box)
        $page = Get-ControlPage $box
        Hide-SearchHint $page.Root.FindName("$($page.Prefix)_search_hint")
    })

    $Page.Rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $grid = $root.FindName("$($prefix)_grid")
    $grid.ItemsSource = $Page.Rows
    $Page.View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Page.Rows)
    # The filter box and the column filters (Initialize-PageColumn), once both are set up.
    $grid.Add_SelectionChanged({ param($grid) & (Get-ControlPage $grid).Action })

    $root.FindName("$($prefix)_search").Add_Click({ param($button) Invoke-PageSearch (Get-ControlPage $button) })
    $root.FindName("$($prefix)_cancel").Add_Click({ param($button) Stop-PageSearch (Get-ControlPage $button) })
    # Entrée in the search box searches (the computers' Rechercher stays the window's default button); ↓ opens the recent
    # searches, as the field's button does.
    $root.FindName("$($prefix)_query").Add_KeyDown({
        param($box, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Invoke-PageSearch (Get-ControlPage $box) }
    })
    $root.FindName("$($prefix)_query").Add_PreviewKeyDown({
        param($box, $e)
        if ($e.Key -eq 'Down' -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::None) {
            Open-PageRecentMenu (Get-ControlPage $box)
            $e.Handled = $true
        }
    })
    # A list's lines pasted in that one-line box (a column from Excel, a ticket's lines) stay apart: a semicolon between
    # each, which keeps a name with spaces whole, and after the text already before them.
    [System.Windows.DataObject]::AddPastingHandler($root.FindName("$($prefix)_query"), [System.Windows.DataObjectPastingEventHandler]{
        param($box, $e)
        $page = Get-ControlPage $box
        if (-not $page.Types[[string]$page.Root.FindName("$($page.Prefix)_search_type").SelectedItem]['List']) { return }
        if (-not $e.DataObject.GetDataPresent([System.Windows.DataFormats]::UnicodeText)) { return }
        $text = [string]$e.DataObject.GetData([System.Windows.DataFormats]::UnicodeText)
        if ($text -notmatch '[\r\n\t]') { return }
        $joined = @($text -split '[\r\n\t]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join '; '
        if ($box.Text.Substring(0, $box.SelectionStart) -match '[^\s;,]\s*$') { $joined = "; $joined" }
        $data = [System.Windows.DataObject]::new()
        $data.SetData([System.Windows.DataFormats]::UnicodeText, $joined)
        $e.DataObject = $data
    })
    $root.FindName("$($prefix)_not_found_copy").Add_Click({ param($button) Copy-PageNotFound (Get-ControlPage $button) })
    $recentButton = $root.FindName("$($prefix)_recent")
    $recentButton.ContextMenu.Tag = $Page
    $recentButton.Add_Click({ param($button) Open-PageRecentMenu (Get-ControlPage $button) })
    $recentButton.Add_ContextMenuOpening({ param($button) Update-PageRecentMenu (Get-ControlPage $button) })
    # Each filter redraws the grid, slow with thousands of rows: then it waits for a pause in the typing, as the
    # computers' does (ComputerPage.ps1), so a word typed quickly costs one redraw rather than one per letter.
    $Page.FilterTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $Page.FilterTimer.Interval = [timespan]::FromMilliseconds(200)
    $Page.FilterTimer.Tag = $Page
    $Page.FilterTimer.Add_Tick({
        param($timer)
        $timer.Stop()
        Update-PageFilter $timer.Tag
    })
    $root.FindName("$($prefix)_filter").Add_TextChanged({
        param($box)
        $page = Get-ControlPage $box
        $page.Filter = "$($box.Text)".Trim().ToLowerInvariant()
        $page.FilterTimer.Stop()
        if ($page.Rows.Count -ge 1000) { $page.FilterTimer.Start() } else { Update-PageFilter $page }
    })
    foreach ($name in "$($prefix)_details", "$($prefix)_menu_details") { $root.FindName($name).Add_Click({ param($control) Show-PageDetail (Get-ControlPage $control) }) }
    # A double-click on a row opens its Propriétés (one on a header has no row behind it).
    $grid.Add_MouseDoubleClick({
        param($grid, $e)
        $page = Get-ControlPage $grid
        $context = $e.OriginalSource.DataContext
        if ($context -and $context.PSObject.Properties[$page.RowProperty]) { Show-PageDetail $page }
    })
    foreach ($name in "$($prefix)_copy", "$($prefix)_menu_copy") {
        $root.FindName($name).Add_Click({ param($control) $page = Get-ControlPage $control; Copy-PageText $page $page.Copy })
    }
    $root.FindName("$($prefix)_menu_copy_rows").Add_Click({ param($control) Copy-PageRow (Get-ControlPage $control) })
    $root.FindName("$($prefix)_export").Add_Click({ param($button) Export-PageRow (Get-ControlPage $button) })
    $root.FindName("$($prefix)_show_all").Add_Click({ param($button) Show-PageAll (Get-ControlPage $button) })
    $grid.Add_PreviewKeyDown({
        param($grid, $e)
        if (Enter-GridByKey $grid $e) { return }
        if ($e.Key -eq [System.Windows.Input.Key]::C -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            $e.Handled = $true
            $page = Get-ControlPage $grid
            Copy-PageText $page $page.Copy
        }
        elseif ($e.Key -eq [System.Windows.Input.Key]::C -and [System.Windows.Input.Keyboard]::Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)) {
            $e.Handled = $true
            Copy-PageRow (Get-ControlPage $grid)
        }
    })
    Initialize-GridText $grid

    # The search's timer has no name: it carries its page.
    $Page.Timer = [System.Windows.Threading.DispatcherTimer]::new()
    $Page.Timer.Interval = [timespan]::FromMilliseconds(40)
    $Page.Timer.Tag = $Page
    $Page.Timer.Add_Tick({ param($timer) Update-PageSearch $timer.Tag })
    Initialize-PageColumn $Page
    & $Page.Action
}

function Get-TypedSearch($Controls) {
    # What the search's boxes hold, to know whether someone went on typing while it ran.
    @($Controls | Where-Object { $_ -is [System.Windows.Controls.TextBox] } | ForEach-Object { $_.Text }) -join "`n"
}

function Set-ResultFocus($Grid, $SearchControls, [string]$Typed) {
    # After a search: nothing is selected, so no action is ready to act on a row nobody chose, but the keys go to the
    # grid, so ↓ or ↑ starts from the first or last row right away (Enter-GridByKey). No row stays current either: a
    # row kept from before (Tout afficher, F5) would be where ↓ went on from, out of sight.
    # The keys stay put if the search's controls are no longer where they are: someone typing the next search while this
    # one ran, or who went to another control, or to another page or window. The search's button has no focus to give:
    # it's disabled while the search runs, which leaves the focus nowhere.
    $Grid.UnselectAll()
    # An empty cell: the struct has no parameterless constructor PowerShell can call.
    $Grid.CurrentCell = [Activator]::CreateInstance([System.Windows.Controls.DataGridCellInfo])
    if (-not $Grid.Items.Count -or -not $Grid.IsVisible -or -not [System.Windows.Window]::GetWindow($Grid).IsActive) { return }
    $focus = [System.Windows.Input.Keyboard]::FocusedElement
    $inSearch = -not $focus -or $focus -is [System.Windows.Window] -or $focus -in $SearchControls -or $Grid.IsKeyboardFocusWithin
    if (-not $inSearch -or (Get-TypedSearch $SearchControls) -ne $Typed) { return }
    $Grid.ScrollIntoView($Grid.Items[0])
    $null = $Grid.Focus()
}

function Enter-GridByKey($Grid, $e) {
    # ↓, Page suivante or Début in a grid where nothing is selected, and no row is current to go on from: the first row
    # is selected with the keys in it, and the keys go on from there; ↑, Page précédente or Fin: the last row. A grid with
    # no current cell ignores them (Set-GridFocus). Returns whether it was one.
    if ($e.Key -notin 'Down', 'Up', 'PageDown', 'PageUp', 'Home', 'End' -or [System.Windows.Input.Keyboard]::Modifiers -ne [System.Windows.Input.ModifierKeys]::None) { return $false }
    if ($Grid.SelectedItems.Count -or -not $Grid.Items.Count) { return $false }
    if ($null -ne $Grid.CurrentItem -and $Grid.Items.Contains($Grid.CurrentItem)) { return $false }
    $item = if ($e.Key -in 'Down', 'PageDown', 'Home') { $Grid.Items[0] } else { $Grid.Items[$Grid.Items.Count - 1] }
    $Grid.SelectedItem = $item
    $Grid.ScrollIntoView($item)
    Set-GridFocus $Grid $item
    $e.Handled = $true
    $true
}

function Set-GridFocus($Grid, $Item) {
    # The keys in that row's first cell, because a grid's keys start from its current cell: on the grid itself, ↓ has
    # nowhere to go from. A row scrolled out of sight has no cell: the grid takes them, and stays where it's scrolled.
    $column = @($Grid.Columns | Where-Object { $_.Visibility -eq 'Visible' } | Sort-Object DisplayIndex)[0]
    if (-not $Item -or -not $column -or -not $Grid.Items.Contains($Item)) { $null = $Grid.Focus(); return }
    $Grid.CurrentCell = [System.Windows.Controls.DataGridCellInfo]::new($Item, $column)
    $Grid.UpdateLayout()
    $row = $Grid.ItemContainerGenerator.ContainerFromItem($Item)
    $cell = if ($row) { $column.GetCellContent($row).Parent }
    $null = if ($cell) { $cell.Focus() } else { $Grid.Focus() }
}

function Get-PageSearchControl($Page) { $Page.Root.FindName("$($Page.Prefix)_query"), $Page.Root.FindName("$($Page.Prefix)_search") }

function Invoke-PageKey($Page, $e) {
    # The window's keys while the page shows: Échap stops a search, Ctrl+F the search box, F5 the search again.
    $root = $Page.Root
    if ($e.Key -eq 'Escape' -and $Page.Search) {
        Stop-PageSearch $Page
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'F' -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        $box = $root.FindName("$($Page.Prefix)_query")
        $null = $box.Focus()
        $box.SelectAll()
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'F5' -and -not $Page.Search) {
        Invoke-PageSearch $Page
        $e.Handled = $true
    }
}

function Invoke-PageSearch($Page) {
    $root = $Page.Root
    $prefix = $Page.Prefix
    $typeName = [string]$root.FindName("$($prefix)_search_type").SelectedItem
    $type = $Page.Types[$typeName]
    $queryBox = $root.FindName("$($prefix)_query")
    $text = "$($queryBox.Text)".Trim()
    $count = $root.FindName("$($prefix)_count")
    $hint = $root.FindName("$($prefix)_search_hint")
    Hide-SearchHint $hint
    # A list: its entries, each once, 200 at most.
    $entries = @()
    $problem = if ($type.NeedsText -and -not $text) { $type.Prompt }
    if (-not $problem -and $type['List']) {
        $entries = @(& $type.List $text)
        $problem = if (-not $entries.Count) { $type.Prompt } elseif ($entries.Count -gt $script:MaxPageListEntries) { $type.TooMany -f $script:MaxPageListEntries, $entries.Count }
    }
    if ($problem) {
        # Under the box, which gets the focus; the count still tells the rows shown.
        Show-SearchHint $hint $problem $queryBox $root.FindName("$($prefix)_search_field") $queryBox
        return
    }
    $count.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
    $clause = $type.Clause
    if ($type['List']) { $clause += "(|$(-join @(foreach ($entry in $entries) { & $type.ListMatch (Get-LdapText $entry) })))" }
    elseif ($text) { $clause += $type.Match -f (Get-LdapText $text) }
    $filter = $Page.Ldap -f $clause
    $domain = if ($script:showDomains) { [string]$root.FindName("$($prefix)_domain").SelectedItem } else { $script:defaultDomain }
    $domains = @(if ($domain -eq (Tr 'Tous les domaines')) { $script:domainList } else { $domain })
    # One search at a time, as on Ordinateurs: this one replaces the one under way (Entrée, a recent search), whose
    # boxes no longer say what it searched. Dropped instead, it went on and showed its rows under this one's boxes.
    if ($Page.Search) { Stop-PageSearch $Page }
    $state = Get-PageSearchState $Page
    Add-PageRecent $Page @{ Domain = $state.Domain; Type = $state.Type; Text = $text }

    # The page's own parameters, worked out once for the whole search (the users': the date the ages are counted from).
    $extra = if ($Page.Parameters) { & $Page.Parameters $type } else { @{} }
    # A list's entries, for the search to say which ones its rows matched.
    if ($type['List']) { $extra.Entries = [string[]]$entries }
    # Kept as it was asked, for Tout afficher: the boxes may have changed by then. It becomes the page's LastRequest once
    # a domain has answered (Complete-PageSearch).
    Start-PageSearch $Page @{ Filter = $filter; Domains = $domains; Extra = $extra; Type = $typeName; Text = $text; Limit = $script:SearchLimit }
}

function ConvertFrom-SavedPageSearch($Saved) {
    # A page's search as recherche.json holds it (Read-SearchSetting): what this version knows, $null when there's none.
    if (-not $Saved) { return }
    $Saved = $Saved | Select-Object Domain, Type, Recent
    $setting = @{ Domain = [string]$Saved.Domain; Type = [string]$Saved.Type; Recent = [System.Collections.Generic.List[object]]::new() }
    foreach ($entry in @($Saved.Recent | Where-Object { $_ } | Select-Object Domain, Type, Text)) {
        if ($setting.Recent.Count -ge $script:MaxPageRecent) { break }
        $setting.Recent.Add([ordered]@{ Domain = [string]$entry.Domain; Type = [string]$entry.Type; Text = [string]$entry.Text })
    }
    $setting
}

function Get-PageSearchSetting($Page) {
    # The page's search as it was left, made empty the first time.
    $key = $Page.SearchSetting
    if (-not $script:PageSearchSettings[$key]) {
        $script:PageSearchSettings[$key] = @{ Domain = ''; Type = ''; Recent = [System.Collections.Generic.List[object]]::new() }
    }
    $script:PageSearchSettings[$key]
}

function Get-PageSearchState($Page) {
    # The domain ('*': all of them) and the search type's Id the page's boxes show, as they're saved.
    $root = $Page.Root
    $domain = if ($script:showDomains) { [string]$root.FindName("$($Page.Prefix)_domain").SelectedItem } else { $script:defaultDomain }
    $type = $Page.Types[[string]$root.FindName("$($Page.Prefix)_search_type").SelectedItem]
    @{ Domain = $(if ($domain -eq (Tr 'Tous les domaines')) { '*' } else { $domain }); Type = $(if ($type) { $type.Id } else { '' }) }
}

function Save-PageSearchChoice($Page) {
    # A domain or search type chosen: kept for the next launch (recherche.json is written when Repère closes).
    $saved = Get-PageSearchSetting $Page
    $state = Get-PageSearchState $Page
    $saved.Domain = $state.Domain
    $saved.Type = $state.Type
}

function Select-PageSearch($Page, [string]$Domain, [string]$Type) {
    # Shows a domain and a search type in the page's boxes; one no longer offered leaves the box as it is.
    $root = $Page.Root
    if ($script:showDomains -and $Domain) {
        $name = if ($Domain -eq '*') { Tr 'Tous les domaines' } else { $Domain }
        $box = $root.FindName("$($Page.Prefix)_domain")
        if ($box.Items.Contains($name)) { $box.SelectedItem = $name }
    }
    foreach ($key in $Page.Types.Keys) {
        if ($Type -and $Page.Types[$key].Id -eq $Type) { $root.FindName("$($Page.Prefix)_search_type").SelectedItem = $key }
    }
}

function Add-PageRecent($Page, $Entry) {
    # A search made: first of the page's recent searches (the same one earlier in the list is removed), and saved.
    $saved = Get-PageSearchSetting $Page
    $saved.Domain = $Entry.Domain
    $saved.Type = $Entry.Type
    $key = "$($Entry.Domain)|$($Entry.Type)|$($Entry.Text)"
    foreach ($old in @($saved.Recent)) {
        if ("$($old.Domain)|$($old.Type)|$($old.Text)" -eq $key) { $null = $saved.Recent.Remove($old) }
    }
    $saved.Recent.Insert(0, [ordered]@{ Domain = $Entry.Domain; Type = $Entry.Type; Text = $Entry.Text })
    while ($saved.Recent.Count -gt $script:MaxPageRecent) { $saved.Recent.RemoveAt($saved.Recent.Count - 1) }
    Save-SearchSetting
}

function Format-RecentPart([string]$Label, [string]$Text) {
    # One part of a recent search: the search type in words, then its text (Description contient « accueil »).
    (Tr '{0} « {1} »') -f $Label, $Text
}

function Join-RecentSearch([object[]]$Parts, [string]$Domain) {
    # A recent search as the three pages' menus say it: its parts, then the domain shown, when there are several.
    # Nom contient « ORD » · Description commence par « acc »  —  Tous les domaines.
    $text = @($Parts | Where-Object { $_ }) -join ' · '
    if ($script:showDomains) { $text += "  —  $Domain" }
    $text
}

function Set-RecentHeader($Item, [string]$Text) {
    # A recent search's menu item: a text block as its header, so an underscore in a name isn't taken for an access key.
    # A long one (Recherche avancée criteria, a long name) is cut with an ellipsis, and its tooltip says it whole; one
    # that fits has none.
    $header = [System.Windows.Controls.TextBlock]::new()
    $header.Text = $Text
    $header.MaxWidth = 560
    $header.TextTrimming = 'CharacterEllipsis'
    $Item.Header = $header
    $Item.ToolTip = $Text
    $Item.Add_ToolTipOpening({
        param($item, $e)
        $block = $item.Header
        $typeface = [System.Windows.Media.Typeface]::new($block.FontFamily, $block.FontStyle, $block.FontWeight, $block.FontStretch)
        $formatted = [System.Windows.Media.FormattedText]::new($block.Text, [System.Globalization.CultureInfo]::CurrentUICulture, $block.FlowDirection,
                                                                $typeface, $block.FontSize, [System.Windows.Media.Brushes]::Black,
                                                                [System.Windows.Media.VisualTreeHelper]::GetDpi($block).PixelsPerDip)
        # A pixel to spare, for the rounding of the layout.
        if ($formatted.WidthIncludingTrailingWhitespace -le $block.ActualWidth + 1) { $e.Handled = $true }
    })
}

function Format-PageRecent($Page, $Entry) {
    # The search type in words, then its text: Nom contient « vpn »  —  demo.local, Verrouillés · Nom « bert ». A list
    # says it's one: « liste : a, b, c (+12) », as the computers' Liste de noms. $null for a type this version doesn't
    # have.
    $typeName = @($Page.Types.Keys | Where-Object { $Page.Types[$_].Id -eq $Entry.Type })
    if (-not $typeName) { return }
    $type = $Page.Types[$typeName[0]]
    $parts = @(
        if ($type['List']) { (Tr 'liste : {0}') -f (Get-ListText @(& $type['List'] $Entry.Text)) }
        elseif ($type.NeedsText -and $Entry.Text) { Format-RecentPart $typeName[0] $Entry.Text }
        else {
            # Verrouillés, Désactivés, Sans membres: their box only narrows them down, by name.
            $typeName[0]
            if ($Entry.Text) { Format-RecentPart (Tr 'Nom') $Entry.Text }
        }
    )
    Join-RecentSearch $parts $(if ($Entry.Domain -eq '*') { Tr 'Tous les domaines' } else { $Entry.Domain })
}

function Update-PageRecentMenu($Page) {
    # The page's recent searches, filled when the menu opens; picking one runs it again.
    $menu = $Page.Root.FindName("$($Page.Prefix)_recent_menu")
    $menu.Items.Clear()
    $entries = @((Get-PageSearchSetting $Page).Recent | Where-Object { Format-PageRecent $Page $_ })
    if (-not $entries.Count) {
        $empty = [System.Windows.Controls.MenuItem]::new()
        $empty.Header = Tr 'Aucune recherche récente'
        $empty.IsEnabled = $false
        $null = $menu.Items.Add($empty)
        return
    }
    foreach ($entry in $entries) {
        $item = [System.Windows.Controls.MenuItem]::new()
        Set-RecentHeader $item (Format-PageRecent $Page $entry)
        $item.Tag = $entry
        $item.Add_Click({ param($item) Use-PageRecent $item.Parent.Tag $item.Tag })
        $null = $menu.Items.Add($item)
    }
    $null = $menu.Items.Add([System.Windows.Controls.Separator]::new())
    $clear = [System.Windows.Controls.MenuItem]::new()
    $clear.Header = Tr 'Effacer les recherches récentes'
    $clear.Name = "$($Page.Prefix)_recent_clear"
    $clear.Add_Click({
        param($item)
        (Get-PageSearchSetting $item.Parent.Tag).Recent.Clear()
        Save-SearchSetting
    })
    $null = $menu.Items.Add($clear)
}

function Open-PageRecentMenu($Page) {
    # Under the whole search field, from its left edge, as the computers' are.
    Update-PageRecentMenu $Page
    $menu = $Page.Root.FindName("$($Page.Prefix)_recent_menu")
    $menu.PlacementTarget = $Page.Root.FindName("$($Page.Prefix)_search_field")
    $menu.Placement = 'Bottom'
    $menu.IsOpen = $true
}

function Use-PageRecent($Page, $Entry) {
    # The search as it was, run again.
    Select-PageSearch $Page $Entry.Domain $Entry.Type
    $Page.Root.FindName("$($Page.Prefix)_query").Text = $Entry.Text
    Invoke-PageSearch $Page
}

function Show-PageAll($Page) {
    # Tout afficher: the search whose rows are shown again, as it was asked, without the limit.
    if ($Page.Search -or -not $Page.LastRequest) { return }
    $request = $Page.LastRequest.Clone()
    $request.Limit = 0
    # The same search: the column filters stay.
    $request.KeepFilters = $true
    Start-PageSearch $Page $request
}

function Start-PageSearch($Page, $Request) {
    # One job per domain, on the search runspaces (Start-PageJob); Update-PageSearch shows their rows once all have answered.
    $root = $Page.Root
    $prefix = $Page.Prefix
    $root.FindName("$($prefix)_count").SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
    $Page.Search = @{ Typed = Get-TypedSearch (Get-PageSearchControl $Page); Jobs = @(); Request = $Request; Domains = $Request.Domains; Watch = [System.Diagnostics.Stopwatch]::StartNew(); Type = $Request.Type; Text = $Request.Text; Limit = $Request.Limit; KeepFilters = [bool]$Request['KeepFilters']
                      Entries = @(if ($Request.Extra['Entries']) { $Request.Extra['Entries'] }) }
    Start-PageJob $Page
    Set-PageSearching $Page $true
    $root.FindName("$($prefix)_show_all").Visibility = 'Collapsed'
    $root.FindName("$($prefix)_not_found").Visibility = 'Collapsed'
    $root.FindName("$($prefix)_count").Text = Tr 'Recherche…'
    $root.FindName("$($prefix)_time").Text = ''
    Set-SearchTimingTip $root.FindName("$($prefix)_time") $null
    $Page.Timer.Start()
}

function Start-PageJob($Page) {
    # The search's jobs, once the runspaces are ready (they may still be loading the AD module right after start).
    $current = $Page.Search
    if ($current.Jobs.Count -or $script:searchPool.RunspacePoolStateInfo.State -ne 'Opened') { return }
    $request = $current.Request
    $current.Jobs = @(foreach ($searched in $request.Domains) {
        $shell = [powershell]::Create()
        $shell.RunspacePool = $script:searchPool
        $clock = New-SearchClock
        $null = $shell.AddScript($Page.Script).AddParameters(@{ Domain = $searched; LdapFilter = $request.Filter; RowBuilder = $script:rowBuilderScript; Limit = $request.Limit; Clock = $clock } + $request.Extra)
        @{ Domain = $searched; Shell = $shell; Handle = $shell.BeginInvoke(); Cancelled = $false; TimedOut = $false; Clock = $clock }
    })
}

function Set-PageSearching($Page, [bool]$Searching) {
    # As on Ordinateurs: Rechercher waits while a search runs, and Annuler (or Échap) stops it.
    $Page.Root.FindName("$($Page.Prefix)_search").IsEnabled = -not $Searching
    $Page.Root.FindName("$($Page.Prefix)_cancel").Visibility = ConvertTo-Visibility $Searching
}

function Update-PageSearch($Page) {
    # On each tick: disposes the cancelled jobs that have ended, starts the jobs when the runspaces are ready, and shows
    # the results once every domain has answered.
    Remove-StoppedJob
    $search = $Page.Search
    # No search: the timer goes on only while cancelled jobs are still ending, so they're disposed even when no search of
    # Ordinateurs runs, whose timer was the only one to dispose of them.
    if (-not $search) {
        if (-not $script:search.Stopping.Count) { $Page.Timer.Stop() }
        return
    }
    if ($script:searchPool.RunspacePoolStateInfo.State -eq 'Broken') {
        $Page.Timer.Stop()
        $Page.Search = $null
        Set-PageSearching $Page $false
        $count = $Page.Root.FindName("$($Page.Prefix)_count")
        $count.Text = (Tr 'Erreur: recherche impossible ({0})') -f $script:searchPool.RunspacePoolStateInfo.Reason.Message
        $count.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.DangerText')
        return
    }
    Start-PageJob $Page
    # A domain that hasn't answered in time is stopped: the others' rows don't wait for it.
    Stop-SilentSearch $search.Jobs
    if (-not $search.Jobs.Count -or @($search.Jobs | Where-Object { -not $_.Handle.IsCompleted -and -not $_['TimedOut'] }).Count) { return }
    Complete-PageSearch $Page
    # Its ticks dispose of the domains stopped once they've ended, as after Annuler.
    if ($script:search.Stopping.Count) { $Page.Timer.Start() }
}

function Stop-PageSearch($Page) {
    # Annuler: the domains that haven't answered are stopped; those that have are shown.
    $search = $Page.Search
    if (-not $search) { return }
    foreach ($job in $search.Jobs) {
        if (-not $job.Handle.IsCompleted -and -not $job['TimedOut']) {
            $job.Cancelled = $true
            # Not waited for: a query stuck on an unreachable DC may only end on its own (Remove-StoppedJob).
            $null = $job.Shell.BeginStop($null, $null)
            $script:search.Stopping.Add($job)
        }
    }
    Complete-PageSearch $Page
    # Its ticks dispose of the jobs stopped once they've ended (Update-PageSearch).
    if ($script:search.Stopping.Count) { $Page.Timer.Start() }
}

function Format-SearchTiming([string]$Domain, $Timing, [string]$Format) {
    # A domain's line of the search time's tooltip, as screen readers read it. $Format: the Utilisateurs and Groupes
    # pages', which name their own rows.
    $culture = Get-TextCulture
    if (-not $Format) { $Format = Tr '{0} : AD {1} ms, lignes {2} ms ({3} ordinateurs)' }
    $Format -f $Domain, ([long]$Timing.Query).ToString('N0', $culture), ([long]$Timing.Rows).ToString('N0', $culture), ([int]$Timing.Count).ToString('N0', $culture)
}

function Get-SearchTimingTable([System.Collections.IDictionary]$Timings, [long]$GridTime, $Words) {
    # The search time's tooltip, every page's: where the time went, as a table, each domain's AD query, rows and count
    # under their column's name, then the grid's time. One line per domain in a sentence wrapped at the tooltip's width
    # read poorly with long domain names (#334). $Timings: each domain's Timing, by name. $Words: the page's
    # PageCountTexts, $null for the computers. Lines: the same as sentences, for screen readers.
    $culture = Get-TextCulture
    $format = if ($Words) { $Words.Timing }
    $column = if ($Words) { $Words.Column } else { Tr 'Ordinateurs' }
    $domains = [System.Collections.Generic.List[object]]::new()
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($domain in $Timings.Keys) {
        $timing = $Timings[$domain]
        $domains.Add([pscustomobject]@{
            Name  = $domain
            Cells = @("$(([long]$timing.Query).ToString('N0', $culture)) ms", "$(([long]$timing.Rows).ToString('N0', $culture)) ms", ([int]$timing.Count).ToString('N0', $culture))
        })
        $lines.Add((Format-SearchTiming $domain $timing $format))
    }
    $grid = "$($GridTime.ToString('N0', $culture)) ms"
    $lines.Add(((Tr 'Grille : {0} ms') -f $GridTime.ToString('N0', $culture)))
    [pscustomobject]@{ Columns = @('AD', (Tr 'Lignes'), $column); Domains = $domains.ToArray(); Grid = $grid; Lines = $lines.ToArray() }
}

function Add-SearchTimingCell($Table, [string]$Text, [int]$Row, [int]$Column) {
    # A cell of the search time's tooltip: the names on the left, the numbers right-aligned so their digits line up.
    $cell = [System.Windows.Controls.TextBlock]::new()
    $cell.Text = $Text
    $cell.Margin = if ($Column) { '16,1,0,1' } else { '0,1,0,1' }
    if ($Column) { $cell.HorizontalAlignment = 'Right' }
    [System.Windows.Controls.Grid]::SetRow($cell, $Row)
    [System.Windows.Controls.Grid]::SetColumn($cell, $Column)
    $null = $Table.Children.Add($cell)
    $cell
}

function New-SearchTimingTip($Table) {
    # Get-SearchTimingTable's table, drawn: the columns' names muted, a line above the grid's time. A long domain name
    # wraps at its dots rather than widening the tooltip. Wider than Fluent's 320 at most: the columns would leave the
    # names hardly any room.
    $grid = [System.Windows.Controls.Grid]::new()
    $columns = 1 + $Table.Columns.Count
    for ($i = 0; $i -lt $columns; $i++) { $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }) }
    for ($i = 0; $i -lt $Table.Domains.Count + 3; $i++) { $grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::Auto }) }
    for ($i = 0; $i -lt $Table.Columns.Count; $i++) {
        $header = Add-SearchTimingCell $grid $Table.Columns[$i] 0 ($i + 1)
        $header.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
    }
    $row = 1
    foreach ($domain in $Table.Domains) {
        # A zero-width space after each dot: where the name may wrap.
        $name = Add-SearchTimingCell $grid ($domain.Name -replace '\.', ".$([char]0x200B)") $row 0
        $name.MaxWidth = 300
        $name.TextWrapping = 'Wrap'
        for ($i = 0; $i -lt $domain.Cells.Count; $i++) { $null = Add-SearchTimingCell $grid $domain.Cells[$i] $row ($i + 1) }
        $row++
    }
    $line = [System.Windows.Controls.Border]::new()
    $line.Height = 1
    $line.Margin = '0,4,0,4'
    $line.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'R.Border')
    [System.Windows.Controls.Grid]::SetRow($line, $row)
    [System.Windows.Controls.Grid]::SetColumnSpan($line, $columns)
    $null = $grid.Children.Add($line)
    $null = Add-SearchTimingCell $grid (Tr 'Grille') ($row + 1) 0
    $null = Add-SearchTimingCell $grid $Table.Grid ($row + 1) 1
    $tip = [System.Windows.Controls.ToolTip]::new()
    $tip.MaxWidth = 640
    $tip.Content = $grid
    $tip
}

function Set-SearchTimingTip($Target, $Table) {
    # The search time's tooltip, or none ($Table $null). A table isn't text screen readers (and the UI tests) can read:
    # its lines are given as the help text instead.
    $Target.ToolTip = if ($Table) { New-SearchTimingTip $Table } else { $null }
    if ($Table) { [System.Windows.Automation.AutomationProperties]::SetHelpText($Target, ($Table.Lines -join "`n")) }
    else { $Target.ClearValue([System.Windows.Automation.AutomationProperties]::HelpTextProperty) }
}

function Complete-PageSearch($Page) {
    # The domains' rows, sorted by name, and the domains that failed or were stopped said in the count.
    $search = $Page.Search
    $Page.Timer.Stop()
    $Page.Search = $null
    $search.Watch.Stop()
    $found = [System.Collections.Generic.List[object]]::new()
    $errors = [ordered]@{}
    $truncated = [System.Collections.Generic.List[string]]::new()
    $words = $script:PageCountTexts[$Page.Prefix]
    # Where the time went, as on Ordinateurs: each domain's AD query and rows, by domain, then the grid
    # (Get-SearchTimingTable).
    $timings = [ordered]@{}
    # A list: the entries some domain's rows matched.
    $matched = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # The domains stopped as they didn't answer in time (Stop-SilentSearch): an error the count names apart.
    $timedOut = [System.Collections.Generic.List[string]]::new()
    foreach ($job in $search.Jobs) {
        if ($job['TimedOut']) {
            $errors[$job.Domain] = Get-SearchTimeoutText
            $timedOut.Add($job.Domain)
            continue
        }
        if ($job.Cancelled) {
            $errors[$job.Domain] = Tr 'recherche annulée'
            continue
        }
        try {
            $answer = @($job.Shell.EndInvoke($job.Handle))[0]
            if ($answer.Error) { $errors[$job.Domain] = $answer.Error } else { foreach ($row in $answer.Rows) { $found.Add($row) } }
            foreach ($entry in @($answer.Matched)) { if ($entry) { $null = $matched.Add($entry) } }
            if ($answer.Truncated) { $truncated.Add($job.Domain) }
            if ($answer.Timing) { $timings[$job.Domain] = $answer.Timing }
        }
        catch { $errors[$job.Domain] = $_.Exception.Message }
        finally { $job.Shell.Dispose() }
    }
    $shownIn = [System.Diagnostics.Stopwatch]::StartNew()
    $root = $Page.Root
    $prefix = $Page.Prefix
    Set-PageSearching $Page $false
    # No domain answered: stopped before any did, so the previous rows stay, and with them the search Tout afficher runs
    # again (#235): the one stopped isn't the page's LastRequest.
    if (-not @($search.Jobs | Where-Object { -not $_.Cancelled }).Count) {
        $root.FindName("$($prefix)_time").Text = Tr 'recherche annulée'
        if ($Page.Truncated) {
            Update-PageNotFound $Page
            Update-PageCount $Page
        }
        else { $root.FindName("$($prefix)_count").Text = '' }
        return
    }
    $Page.LastRequest = $search.Request
    # A new search clears the column filters; Tout afficher keeps them.
    if (-not $search.KeepFilters -and $Page.ColumnFilter.Active.Count) { Clear-ColumnFilter $Page.ColumnFilter }
    Set-PageRow $Page @($found | Sort-Object Name)
    $Page.MultiDomain = $search.Domains.Count -gt 1
    Update-PageColumn $Page
    $scope = if ($search.Domains.Count -gt 1) { (Tr 'dans {0} domaines') -f $search.Domains.Count } else { (Tr 'dans {0}') -f $search.Domains[0] }
    $scopeText = $Page.Types[$search.Type]['ScopeText']
    if ($scopeText) { $scope += ", $scopeText" }
    $root.FindName("$($prefix)_scope").Text = $scope
    $Page.Errors = $errors
    $Page.TimedOut = @($timedOut)
    $Page.Truncated = @{ Domains = @($truncated); Limit = $search.Limit; MultiDomain = $search.Domains.Count -gt 1 }
    # A list says its entries not found above the grid rather than in it.
    $root.FindName("$($prefix)_empty_text").Text = if ($search.Text -and -not $search.Entries.Count) { $words.NoneFor -f $search.Text } else { $words.None }
    $Page.NotFound = @($search.Entries | Where-Object { -not $matched.Contains($_) })
    # The domains that failed or were stopped (#236): those entries may be there after all, so the banner says so rather
    # than calling them truly not found. Set on each search that shows rows, as NotFound is: a search stopped before any
    # domain answered keeps the previous rows, and with them the previous search's banner and its domains.
    $Page.Unanswered = @($errors.Keys)
    Update-PageNotFound $Page
    Update-PageCount $Page
    Set-ResultFocus $root.FindName("$($prefix)_grid") (Get-PageSearchControl $Page) $search.Typed
    & $Page.Action
    $time = $root.FindName("$($prefix)_time")
    $time.Text = (Tr 'en {0} ms') -f $search.Watch.ElapsedMilliseconds.ToString('N0', (Get-TextCulture))
    Set-SearchTimingTip $time (Get-SearchTimingTable $timings $shownIn.ElapsedMilliseconds $words)
}

function Set-PageRow($Page, [object[]]$Rows) {
    # A search's rows, all at once as on Ordinateurs (Show-ResultRow): added one by one, the view would filter and sort at
    # each. The new view keeps the old one's filter and sort, which the grid forgets when it gets new rows.
    $grid = $Page.Root.FindName("$($Page.Prefix)_grid")
    $old = $Page.View
    $Page.Rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new([object[]]$Rows)
    $grid.ItemsSource = $Page.Rows
    $Page.View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Page.Rows)
    $Page.View.Filter = $old.Filter
    foreach ($sort in @($old.SortDescriptions)) {
        $Page.View.SortDescriptions.Add($sort)
        foreach ($column in $grid.Columns) {
            if ($column.SortMemberPath -eq $sort.PropertyName) { $column.SortDirection = $sort.Direction }
        }
    }
}

function Get-SearchLimitText($Truncated) {
    # What the count adds when a search found more than its limit (a hashtable: Domains, Limit, MultiDomain), or $null:
    # « limite de 2 000 atteinte », with the domains when several were searched.
    if (-not $Truncated -or -not @($Truncated.Domains).Count) { return }
    $limit = ([int]$Truncated.Limit).ToString('N0', (Get-TextCulture))
    $text = (Tr 'limite de {0} atteinte') -f $limit
    if ($Truncated.MultiDomain) { $text += " ($(@($Truncated.Domains) -join ', '))" }
    (Tr '{0} : précisez la recherche, ou Tout afficher') -f $text
}

function Update-PageCount($Page) {
    # The count of rows shown (after the filter box and the column filters), and the domains that couldn't be searched.
    $root = $Page.Root
    $shown = @($Page.View).Count
    $total = $Page.Rows.Count
    $words = $script:PageCountTexts[$Page.Prefix]
    $text = if ($total -eq 1) { $words.One } else { $words.Many -f $total }
    if ($shown -ne $total) { $text = (Tr '{0} sur {1}') -f $shown, $text }
    $errors = $Page.Errors
    $count = $root.FindName("$($Page.Prefix)_count")
    # More found than the limit: said in amber (in red with an error), and Tout afficher offered.
    $limited = Get-SearchLimitText $Page.Truncated
    if ($limited) { $text += " · $limited" }
    if ($errors -and $errors.Count) {
        # The domains that didn't answer in time apart from those that failed: they may answer if searched again.
        $late = @($Page['TimedOut'] | Where-Object { $_ })
        $failed = @($errors.Keys | Where-Object { $late -notcontains $_ })
        $parts = @(
            if ($failed.Count) { (Tr '(erreur : {0})') -f ($failed -join ', ') }
            if ($late.Count) { (Tr '(sans réponse : {0})') -f ($late -join ', ') }
        )
        $text += ' ' + ($parts -join ' ')
        $count.ToolTip = ConvertTo-FrenchError (@($errors.Keys | ForEach-Object { (Tr '{0} : {1}') -f $_, $errors[$_] }) -join "`n")
        $count.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.DangerText')
    }
    else {
        $count.ToolTip = $null
        $count.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($limited) { 'R.WarnText' } else { 'R.Muted' }))
    }
    $root.FindName("$($Page.Prefix)_show_all").Visibility = if ($limited) { 'Visible' } else { 'Collapsed' }
    $count.Text = $text
    $root.FindName("$($Page.Prefix)_empty").Visibility = if ($shown) { 'Collapsed' } else { 'Visible' }
    $root.FindName("$($Page.Prefix)_export").IsEnabled = $shown -gt 0
}

function Update-PageNotFound($Page) {
    # A list's entries no domain had, in the order they were given, above the grid in amber: as many as fit on the
    # banner's line, then how many more (Copier copies them all, one per line). Unanswered: the domains that failed or
    # were cancelled, where those entries may be after all.
    $notFound = @($Page.NotFound)
    $root = $Page.Root
    $root.FindName("$($Page.Prefix)_not_found").Visibility = if ($notFound.Count) { 'Visible' } else { 'Collapsed' }
    if (-not $notFound.Count) { return }
    $block = $root.FindName("$($Page.Prefix)_not_found_text")
    # The first time: fitted again whenever the banner's width changes (the window resized, or the banner shown).
    if ($null -eq $block.Tag) { $block.Add_SizeChanged({ param($sender, $e) if ($e.WidthChanged) { Set-NotFoundText $sender } }) }
    $block.Tag = @{ NotFound = $notFound; Unanswered = @($Page.Unanswered | Where-Object { $_ }) }
    Set-NotFoundText $block
}

function Get-NotFoundText([string[]]$NotFound, [string[]]$Unanswered, [int]$Shown) {
    # The banner's text with the first $Shown entries: « 3 introuvables : a, b (+1) · sans réponse de nord.demo.local ».
    $listed = Get-ListText $NotFound $Shown
    $text = if ($NotFound.Count -eq 1) { (Tr '1 introuvable : {0}') -f $listed } else { (Tr '{0} introuvables : {1}') -f $NotFound.Count, $listed }
    if ($Unanswered.Count) { $text += ' · ' + ((Tr 'sans réponse de {0}') -f ($Unanswered -join ', ')) }
    $text
}

function Set-NotFoundText($Block) {
    # As many entries as fit on $Block's one line (its width is the banner's, less Copier: the text doesn't change it).
    # At least one, trimmed with an ellipsis in a very narrow window. Not laid out yet (the banner just shown): every
    # entry, until its width is known.
    $notFound = @($Block.Tag.NotFound)
    $unanswered = @($Block.Tag.Unanswered)
    $width = $Block.ActualWidth
    if ($width -le 0) {
        $Block.Text = Get-NotFoundText $notFound $unanswered $notFound.Count
        return
    }
    $typeface = [System.Windows.Media.Typeface]::new($Block.FontFamily, $Block.FontStyle, $Block.FontWeight, $Block.FontStretch)
    $pixelsPerDip = [System.Windows.Media.VisualTreeHelper]::GetDpi($Block).PixelsPerDip
    $culture = [System.Globalization.CultureInfo]::CurrentUICulture
    $fits = {
        param([int]$Shown)
        $formatted = [System.Windows.Media.FormattedText]::new((Get-NotFoundText $notFound $unanswered $Shown), $culture, $Block.FlowDirection, $typeface,
                                                                $Block.FontSize, [System.Windows.Media.Brushes]::Black, $pixelsPerDip)
        # A pixel to spare, for the rounding of the layout: the last entry isn't cut by the ellipsis.
        $formatted.WidthIncludingTrailingWhitespace -le $width - 1
    }
    # The most that fit: one more entry makes the text longer, so they're searched by halves.
    $low = 1
    $high = $notFound.Count
    while ($low -lt $high) {
        $middle = [int][math]::Ceiling(($low + $high) / 2)
        if (& $fits $middle) { $low = $middle } else { $high = $middle - 1 }
    }
    $Block.Text = Get-NotFoundText $notFound $unanswered $low
}

function Copy-PageNotFound($Page) {
    $notFound = @($Page.NotFound)
    if (-not $notFound.Count) { return }
    Set-Clipboard -Value ($notFound -join [Environment]::NewLine)
    Show-ActionNotice (Tr 'Copié dans le presse-papiers') $(if ($notFound.Count -eq 1) { "✔ $($notFound[0])" } else { (Tr '✔ {0} {1} copiés') -f $notFound.Count, (Tr 'introuvables') })
}

function Protect-SpreadsheetText([object[]]$Values) {
    # A row's values on their way to Excel, in a CSV file or pasted: a value Excel would read as a formula (AD's data, a
    # description that starts with =) stays text, behind an apostrophe. Excel evaluates pasted tab-separated text as if
    # it were typed. The other values come back as they are, not as text: Exporter writes the dates in the culture's way.
    # One array, a value per index: sent down the pipeline, a $null or a list among the values would shift the others.
    $protected = [object[]]::new($Values.Count)
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $protected[$i] = $Values[$i]
        if ("$($Values[$i])" -match '^[=+\-@\t\r]') { $protected[$i] = "'$($Values[$i])" }
    }
    , $protected
}

function Format-RowLine([object[]]$Values) {
    # A row's values on one line of the clipboard, a tab between each, for Excel: a line break or a tab in a value would
    # make it two rows or two columns once pasted, and a formula would be evaluated (Protect-SpreadsheetText).
    @((Protect-SpreadsheetText $Values) | ForEach-Object { "$_" -replace '\s*[\r\n\t]+\s*', ' ' }) -join "`t"
}

filter Protect-CsvValue {
    # A row on its way to a CSV file, its values kept from being read as formulas (Protect-SpreadsheetText).
    $properties = @($_.PSObject.Properties)
    $values = [object[]]::new($properties.Count)
    for ($i = 0; $i -lt $properties.Count; $i++) { $values[$i] = $properties[$i].Value }
    $values = Protect-SpreadsheetText $values
    for ($i = 0; $i -lt $properties.Count; $i++) { $properties[$i].Value = $values[$i] }
    $_
}

function Get-ExportField($Columns, [System.Collections.IDictionary]$Fields = @{}, [object[]]$Last = @()) {
    # What Exporter writes and Copier les lignes copies, on every page (the computers' too): the grid's columns as it
    # shows them, the ones chosen in Colonnes, in the order they're shown (a header dragged moves its column), each
    # under its header as shown, in this run's language. $Columns: the grid's (each with its SortMemberPath, Header,
    # Visibility and DisplayIndex). A column writes the row property it sorts by (its SortMemberPath), except those
    # in $Fields, by key: what the grid shows there isn't the value (an icon, an age, a short name), or isn't all of
    # it, so each gives the fields it writes instead (a Header of its own, or the column's; a Value, a row property or
    # a script block given the row). $Last: written after them whatever is shown, for what tells a row apart and
    # where it is once in a spreadsheet, the distinguished name. A column hidden in the grid stays out of the file:
    # what was hidden on purpose isn't wanted there either.
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($column in @($Columns | Where-Object { "$($_.Visibility)" -eq 'Visible' } | Sort-Object { [int]$_.DisplayIndex })) {
        $key = [string]$column.SortMemberPath
        $specs = if ($null -ne $Fields -and $Fields.Contains($key)) { $Fields[$key] } else { @{ Value = $key } }
        foreach ($spec in @($specs)) { $list.Add(@{ Header = $(if ($spec['Header']) { [string]$spec['Header'] } else { [string]$column.Header }); Value = $spec['Value'] }) }
    }
    foreach ($spec in @($Last)) {
        # Unless a column shows it already.
        if ($spec -and -not @($list | Where-Object { $_.Header -eq $spec['Header'] }).Count) { $list.Add(@{ Header = [string]$spec['Header']; Value = $spec['Value'] }) }
    }
    , $list.ToArray()
}

function ConvertTo-ExportRow($Rows, [object[]]$Fields) {
    # The rows as Exporter writes them: one object each, a property per field (Get-ExportField), in its order.
    foreach ($row in @($Rows)) {
        $line = [ordered]@{}
        foreach ($field in $Fields) { $line[$field.Header] = if ($field.Value -is [scriptblock]) { & $field.Value $row } else { $row.($field.Value) } }
        [pscustomobject]$line
    }
}

function Get-RowClipboardText($Rows, [object[]]$Fields) {
    # Copier les lignes: the rows as Exporter writes them, a line each and a tab between the columns (Format-RowLine),
    # to paste into Excel or a ticket. Without the header: a paste goes under the rows already there.
    $lines = foreach ($line in @(ConvertTo-ExportRow $Rows $Fields)) {
        $properties = @($line.PSObject.Properties)
        $values = [object[]]::new($properties.Count)
        for ($i = 0; $i -lt $properties.Count; $i++) { $values[$i] = $properties[$i].Value }
        Format-RowLine $values
    }
    @($lines) -join [Environment]::NewLine
}

function Get-PageExportField($Page) {
    # A page's columns as Exporter writes them: its grid's, with what its Export says (Fields, Last).
    Get-ExportField $Page.Root.FindName("$($Page.Prefix)_grid").Columns $Page.Export.Fields $Page.Export.Last
}

function Copy-PageRow($Page) {
    # Copier les lignes: the selected rows as Exporter writes them, to paste into Excel or a ticket.
    $selected = Get-PageSelection $Page
    if (-not $selected.Count) { return }
    Set-Clipboard -Value (Get-RowClipboardText $selected (Get-PageExportField $Page))
    Show-ActionNotice (Tr 'Copié dans le presse-papiers') $(if ($selected.Count -eq 1) { Tr '✔ 1 ligne copiée' } else { (Tr '✔ {0} lignes copiées') -f $selected.Count })
}

function Export-PageRow($Page) {
    # Exporter: the rows shown (after the filter, in the grid's order) as CSV for French Excel, like the computers': UTF-8
    # with a BOM, the culture's list separator, the columns shown (Get-ExportField), exact dates.
    # $env:REPERE_EXPORT_PATH, for the UI tests, saves there without asking.
    $rows = @(foreach ($row in $Page.View) { $row })
    if (-not $rows.Count) { return }
    $export = $Page.Export
    $path = $env:REPERE_EXPORT_PATH
    if (-not $path) {
        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Title = $export.Title
        $dialog.Filter = Tr 'Fichiers CSV (*.csv)|*.csv'
        # The date in the Gregorian calendar whatever the culture's (-f would write 2569 in th-TH), so exports sort by name.
        $dialog.FileName = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $export.FileName, (Get-Date))
        $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if (-not $dialog.ShowDialog($script:win)) { return }
        $path = $dialog.FileName
    }
    $time = $Page.Root.FindName("$($Page.Prefix)_time")
    try {
        $lines = ConvertTo-ExportRow $rows (Get-PageExportField $Page) | Protect-CsvValue | ConvertTo-Csv -Delimiter (Get-Culture).TextInfo.ListSeparator -UseQuotes AsNeeded
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8BOM -ErrorAction Stop
        $time.Text = if ($rows.Count -eq 1) { Tr '· 1 ligne exportée' } else { (Tr '· {0} lignes exportées') -f $rows.Count }
        # The file's path in place of the search's times, which go with the text they explained.
        Set-SearchTimingTip $time $null
        $time.ToolTip = $path
    }
    catch {
        Show-Dialog -Title $export.Title -Icon 'xcircle' -Tone 'danger' -Message ((Tr "Impossible d'enregistrer {0} : {1}") -f $path, $_.Exception.Message)
    }
}

function Get-PageSelection($Page) {
    # The selected rows, as a copy: actions change the rows.
    , @($Page.Root.FindName("$($Page.Prefix)_grid").SelectedItems | ForEach-Object { $_ })
}

function Show-PageDetail($Page) {
    # Propriétés…, for one row ($Page.Detail: Show-UserDetail, UserDetails.ps1, or Show-GroupDetail, GroupDetails.ps1).
    $selected = Get-PageSelection $Page
    if ($selected.Count -ne 1) { return }
    & $Page.Detail $selected[0] $script:win $script:windowIcon
}

function Copy-PageText($Page, [string]$Property) {
    # The selected rows' $Property, one per line; the rows without one (a user without an email) are left out. The
    # selection held first: piped as it comes, the list would go through as one object.
    $selected = Get-PageSelection $Page
    $selected = @($selected | Where-Object { "$($_.$Property)" })
    if (-not $selected.Count) { return }
    Set-Clipboard -Value (@($selected | ForEach-Object { $_.$Property }) -join [Environment]::NewLine)
    Show-ActionNotice (Tr 'Copié dans le presse-papiers') $(if ($selected.Count -eq 1) { "✔ $($selected[0].$Property)" } else { (Tr '✔ {0} {1} copiés') -f $selected.Count, $Page.Copied[$Property] })
}

function Initialize-PageColumn($Page) {
    # A page's grid columns (Utilisateurs, Groupes), like the computers': shown or hidden (Colonnes, or a right-click on a
    # column header), moved by dragging their header, resized, and kept in apparence.json ($Page.Setting). Each column's
    # key is its SortMemberPath; the controls are named after $Page.Prefix. Nom is always shown; Domaine only after a
    # search of several domains.
    $columns = $Page.Columns
    $prefix = $Page.Prefix
    $grid = $Page.Root.FindName("$($prefix)_grid")
    $grid.CanUserReorderColumns = $true
    Register-ColumnResize $grid
    $columns.Menu = [System.Windows.Controls.ContextMenu]::new()
    $columns.Menu.Tag = $Page
    foreach ($column in $grid.Columns) {
        $columns.ByKey[$column.SortMemberPath] = $column
        $columns.Shown[$column.SortMemberPath] = $column.SortMemberPath -notin $Page.Hidden
    }
    foreach ($key in $columns.ByKey.Keys) {
        if ($key -eq 'Name' -or ($key -eq 'Domain' -and -not $script:showDomains)) { continue }
        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = [string]$columns.ByKey[$key].Header
        $item.Name = "$($prefix)_column_$key"
        $item.Tag = $key
        $item.IsCheckable = $true
        $item.StaysOpenOnClick = $true
        $toggled = {
            param($item)
            $page = $item.Parent.Tag
            if ($page.Columns.Updating) { return }
            $page.Columns.Shown[$item.Tag] = $item.IsChecked
            Update-PageColumn $page
        }
        $item.Add_Checked($toggled)
        $item.Add_Unchecked($toggled)
        $columns.Items[$key] = $item
        $null = $columns.Menu.Items.Add($item)
    }
    $null = $columns.Menu.Items.Add([System.Windows.Controls.Separator]::new())
    $reset = [System.Windows.Controls.MenuItem]::new()
    $reset.Header = Tr 'Réinitialiser les colonnes'
    $reset.Name = "$($prefix)_column_reset"
    $reset.Add_Click({ param($item) Set-PageColumnLayout $item.Parent.Tag $item.Parent.Tag.Columns.Default })
    $null = $columns.Menu.Items.Add($reset)
    # The same menu on every column header (a header with its own style gets it too) and on the Colonnes button.
    $headerStyle = [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader], $grid.ColumnHeaderStyle)
    $headerStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.FrameworkElement]::ContextMenuProperty, $columns.Menu))
    $grid.ColumnHeaderStyle = $headerStyle
    # The column filters, in the same menu, then the view's filter.
    $Page.ColumnFilter = Initialize-ColumnFilter -Grid $grid -Prefix "$($prefix)_" -Specs (& $Page.FilterSpecs) -Toggle $Page.Root.FindName("$($prefix)_column_filters") `
        -Menu $columns.Menu -Setting $Page.SearchSetting -Holder $Page -QueryKey 'Filter' -OnChange { param($state) Update-PageFilter $state.Holder }
    $Page.View.Filter = New-RowFilter $Page.ColumnFilter
    $button = $Page.Root.FindName("$($prefix)_columns")
    $button.ContextMenu = $columns.Menu
    $button.Add_Click({ param($control) Open-ButtonMenu $control })
    $columns.Menu.Add_Closed({
        param($menu)
        $menu.ClearValue([System.Windows.Controls.ContextMenu]::PlacementTargetProperty)
        $menu.ClearValue([System.Windows.Controls.ContextMenu]::PlacementProperty)
    })
    $columns.Default = Get-PageColumnLayout $Page
    $saved = $script:Appearance[$Page.Setting]
    if ($saved) {
        try { Set-PageColumnLayout $Page $saved }
        catch {
            Write-Host "Colonnes ignorées ($($Page.Setting)) : $_"
            Set-PageColumnLayout $Page $columns.Default
        }
    }
    else { Update-PageColumn $Page }
    $columns.Loaded = Get-PageColumnLayout $Page | ConvertTo-Json -Compress
    # Saved when Repère closes, only if they changed.
    $script:ColumnPages.Add($Page)
    if ($script:ColumnPages.Count -eq 1) { $script:win.Add_Closing({ Save-PageColumn }) }
}

function Save-PageColumn {
    $changed = $false
    foreach ($page in $script:ColumnPages) {
        $layout = Get-PageColumnLayout $page
        if (($layout | ConvertTo-Json -Compress) -ne $page.Columns.Loaded) {
            $script:Appearance[$page.Setting] = $layout
            $changed = $true
        }
    }
    if ($changed) { Save-Appearance }
}

function Get-PageColumnLayout($Page) {
    $columns = $Page.Columns
    @(foreach ($key in $columns.ByKey.Keys) {
        $column = $columns.ByKey[$key]
        $width = Get-SavedColumnWidth $column
        [ordered]@{ Key = $key; Visible = [bool]$columns.Shown[$key]; Width = $width.Width; Unit = $width.Unit; Index = $column.DisplayIndex }
    })
}

function Get-SavedColumnWidth($Column) {
    # A column's width as it's saved (#277): a share of the room (Star) or pixels as they are. A column fitted to its
    # content by a double-click on its header's edge is Auto, which a saved layout doesn't restore (it would come back
    # at its default width): it's saved as wide as it shows.
    $width = $Column.Width
    if ($width.IsStar -or $width.IsAbsolute) { return @{ Width = [Math]::Round($width.Value, 2); Unit = [string]$width.UnitType } }
    @{ Width = [Math]::Round($Column.ActualWidth, 2); Unit = 'Pixel' }
}

function Register-ColumnResize($Grid) {
    # A column the user resizes keeps the width given (#277). WPF leaves a resized star column a share of the room, so
    # its width changed again with the window, a column shown or hidden (Domaine, En ligne) or the scroll bar: once its
    # header's edge is let go, it's that many pixels. The other star columns share what's left, so the grid still fills.
    # (The header marks the event handled: the grid asks for it all the same.)
    $Grid.AddHandler([System.Windows.Controls.Primitives.Thumb]::DragCompletedEvent, [System.Windows.Controls.Primitives.DragCompletedEventHandler]{
        param($grid, $e)
        Set-ResizedColumnPixel $grid $e.OriginalSource
    }, $true)
}

function Set-ResizedColumnPixel($Grid, $Gripper) {
    # The column a header's gripper resized: its own (the right edge), or the one shown before it (the left edge). The
    # grid's other thumbs (its scroll bars, the rows' headers) aren't in a column header and are left alone.
    $header = $Gripper.TemplatedParent
    if ($header -isnot [System.Windows.Controls.Primitives.DataGridColumnHeader] -or -not $header.Column) { return }
    $column = $header.Column
    if ($Gripper.Name -eq 'PART_LeftHeaderGripper') {
        $column = $Grid.Columns | Where-Object { $_.Visibility -eq 'Visible' -and $_.DisplayIndex -lt $header.Column.DisplayIndex } |
            Sort-Object DisplayIndex | Select-Object -Last 1
    }
    if ($column -and $column.Width.IsStar -and $column.ActualWidth -gt 0) {
        $column.Width = [System.Windows.Controls.DataGridLength]::new($column.ActualWidth, 'Pixel')
    }
}

function Set-PageColumnLayout($Page, $Layout) {
    # A saved layout: the order, then each column's visibility and width (what doesn't make sense is left out).
    $columns = $Page.Columns
    $known = @($Layout | Where-Object { $_ -and $columns.ByKey.Contains([string]$_.Key) } | Sort-Object { [int]$_.Index })
    $knownKeys = @($known | ForEach-Object { [string]$_.Key })
    $order = @($knownKeys) + @($columns.ByKey.Keys | Where-Object { $_ -notin $knownKeys })
    for ($i = 0; $i -lt $order.Count; $i++) { $columns.ByKey[$order[$i]].DisplayIndex = $i }
    foreach ($entry in $known) {
        $key = [string]$entry.Key
        if ($key -ne 'Name') { $columns.Shown[$key] = [bool]$entry.Visible }
        $width = 0.0
        if ([double]::TryParse("$($entry.Width)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$width)) {
            if ($entry.Unit -eq 'Pixel' -and $width -ge 30) { $columns.ByKey[$key].Width = [System.Windows.Controls.DataGridLength]::new($width, 'Pixel') }
            elseif ($entry.Unit -eq 'Star' -and $width -gt 0) { $columns.ByKey[$key].Width = [System.Windows.Controls.DataGridLength]::new($width, 'Star') }
        }
    }
    Update-PageColumn $Page
}

function Update-PageColumn($Page) {
    # Shows the columns chosen and ticks them in the menu. Domaine only shows after a search of several domains.
    $columns = $Page.Columns
    $columns.Updating = $true
    try {
        foreach ($key in $columns.ByKey.Keys) {
            $shown = $key -eq 'Name' -or ($columns.Shown[$key] -and ($key -ne 'Domain' -or $Page.MultiDomain))
            $columns.ByKey[$key].Visibility = if ($shown) { 'Visible' } else { 'Collapsed' }
            if ($columns.Items.Contains($key)) { $columns.Items[$key].IsChecked = [bool]$columns.Shown[$key] }
        }
    }
    finally { $columns.Updating = $false }
    # A filtered column now hidden is no longer filtered.
    if (Sync-ColumnFilter $Page.ColumnFilter) { Update-PageFilter $Page }
}

function Update-PageFilter($Page) {
    # The rows the filter box and the column filters let through, and their count.
    $Page.View.Refresh()
    Update-PageCount $Page
}
