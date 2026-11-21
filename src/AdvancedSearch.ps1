# Recherche avancée: the Ordinateurs search's criteria that AD applies itself, on top of the search type, the start of
# the name and the description. Its button in the search bar (Avancée, with how many criteria are set) opens them in a
# popup; they stay until changed, and come back at the next launch (recherche.json):
#   Emplacement         Partout, one OU (Choisir…, with the OUs under it) or the OUs whose name starts with a text
#                       (empty until one is typed, and the OUs under them).
#   Compte                Tous, Activés or Désactivés.
#   Système contient    a text of the operating system AD keeps (Windows 10, Server…).
#   Dernière connexion  at least or less than so many days, weeks, months or years ago, with or without the computers
#                       that never logged on (« Jamais »). Counted as a column's Age filter counts (Get-AgeCutoff).
# A search can then go without the start of the name or a description: what the criteria narrow down, the limit bounds.
# Unlike the column filters (ColumnFilter.ps1), they narrow what AD sends, not the rows already found.
#
# The criteria are a hashtable (New-AdvancedSearch): Scope (All, OU, OUName), OU and OUDomain (the OU chosen and its
# domain), OUName, State (All, Enabled, Disabled), System, Logon (Any, AtLeast, Less), Number (0 when what's typed
# isn't one from 1 to 999), Unit (0 to 3: jours, semaines, mois, ans) and Never. Dot-sourced by the main script before
# its window; ComputerPage.ps1 wires the popup (Initialize-AdvancedSearch) once the window is built.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

# The criteria shown in the popup, and searched by Rechercher.
$script:AdvancedSearch = $null
# The popup's controls once found, whether they're being set from the criteria (their events then wait), and when the
# popup last closed (a click on Avancée that closed it doesn't open it again).
$script:AdvancedSearchUi = @{ Parts = $null; Updating = $false; ClosedAt = [datetime]::MinValue }

function New-AdvancedSearch {
    # No criterion: every computer the search type finds, anywhere.
    @{ Scope = 'All'; OU = ''; OUDomain = ''; OUName = ''; State = 'All'; System = ''; Logon = 'Any'; Number = 90; Unit = 0; Never = $true }
}

function Set-AdvancedSearch($Criteria) {
    # The criteria to search (recherche.json's, a recent search's), shown in the popup once it's wired.
    $script:AdvancedSearch = $Criteria
    if ($script:AdvancedSearchUi.Parts) { Show-AdvancedSearch }
}

function Get-AdvancedSearchCount($Criteria) {
    # How many criteria are set (the button says so).
    @(($Criteria.Scope -ne 'All'), ($Criteria.State -ne 'All'), [bool]$Criteria.System, ($Criteria.Logon -ne 'Any')).Where({ $_ }).Count
}

function ConvertFrom-SavedAdvancedSearch($Saved, [string]$Inactive) {
    # The criteria as recherche.json keeps them; what's missing or not offered keeps its default, strict mode or not.
    # Without any (a search saved before the advanced search): its Inactifs depuis duration (90 jours, 180 jours or
    # 1 an), as a criterion.
    $criteria = New-AdvancedSearch
    if (-not $Saved) {
        $old = @{ '90 jours' = 90, 0; '180 jours' = 180, 0; '1 an' = 1, 3 }
        if ($Inactive -and $old.ContainsKey($Inactive)) {
            $criteria.Logon = 'AtLeast'
            $criteria.Number, $criteria.Unit = $old[$Inactive]
        }
        return $criteria
    }
    # A recent search's, as it was kept (a hashtable), or as read from the file.
    $from = if ($Saved -is [System.Collections.IDictionary]) { [pscustomobject]$Saved } else { $Saved }
    $read = $from | Select-Object Scope, OU, OUDomain, OUName, State, System, Logon, Number, Unit, Never
    if ("$($read.OUName)".Trim()) { $criteria.OUName = "$($read.OUName)".Trim() }
    if ($read.OU -and $read.OUDomain) { $criteria.OU = [string]$read.OU; $criteria.OUDomain = [string]$read.OUDomain }
    if ($read.Scope -ceq 'OUName' -or ($read.Scope -ceq 'OU' -and $criteria.OU)) { $criteria.Scope = [string]$read.Scope }
    if ($read.State -cin 'Enabled', 'Disabled') { $criteria.State = [string]$read.State }
    $criteria.System = "$($read.System)".Trim()
    if ($read.Logon -cin 'AtLeast', 'Less') { $criteria.Logon = [string]$read.Logon }
    $number = 0
    if ([int]::TryParse("$($read.Number)", [ref]$number) -and $number -ge 1 -and $number -le 999) { $criteria.Number = $number }
    $unit = 0
    if ([int]::TryParse("$($read.Unit)", [ref]$unit) -and $unit -ge 0 -and $unit -le 3) { $criteria.Unit = $unit }
    if ($null -ne $read.Never) { $criteria.Never = $read.Never -eq $true }
    $criteria
}

function ConvertTo-SavedAdvancedSearch($Criteria, [switch]$Always) {
    # As recherche.json keeps them, in a set order: a recent search that's the same twice is found by its JSON. A
    # recent search without any criterion keeps none ($null); the settings keep them all (-Always), as last left.
    if (-not $Always -and -not (Get-AdvancedSearchCount $Criteria)) { return $null }
    $saved = [ordered]@{}
    foreach ($key in 'Scope', 'OU', 'OUDomain', 'OUName', 'State', 'System', 'Logon', 'Number', 'Unit', 'Never') { $saved[$key] = $Criteria[$key] }
    $saved
}

function Get-AdvancedSearchFilter($Criteria, [datetime]$Today) {
    # What the criteria add to the search's AD filter (Compte, Système, Dernière connexion), each clause after -and, and
    # CreatedBefore: with « au moins » and « Jamais », a computer that never logged on is left out when it's newer than
    # the cutoff (one joined yesterday hasn't logged on yet). AD leaves it out itself: the filter compares whenCreated
    # with $CreatedBefore, the search script's variable of that name, which Get-ADComputer reads where it's called.
    # Read from each computer instead, whenCreated cost the AD module some 20 ms per computer, and came after the limit.
    # The OU is the search's base, not a clause (AD can't filter on the DN). lastLogonTimestamp is the one AD
    # replicates, unlike lastLogon.
    $filter = ''
    $createdBefore = $null
    if ($Criteria.State -eq 'Enabled') { $filter += " -and Enabled -eq 'True'" }
    elseif ($Criteria.State -eq 'Disabled') { $filter += " -and Enabled -eq 'False'" }
    # Double single quotes so input like "d'accueil" doesn't break the AD filter.
    if ($Criteria.System) { $filter += " -and OperatingSystem -like '*$($Criteria.System -replace "'", "''")*'" }
    if ($Criteria.Logon -ne 'Any') {
        $cutoff = Get-AgeCutoff $Criteria.Number $Criteria.Unit $Today
        # 426 years ago or more is before what AD's dates can hold: no logon is that old.
        if ($cutoff -lt [datetime]'1601-01-02') { $cutoff = [datetime]'1601-01-02' }
        $atLeast = $Criteria.Logon -eq 'AtLeast'
        $clause = "lastLogonTimestamp $(if ($atLeast) { '-lt' } else { '-ge' }) $($cutoff.ToFileTimeUtc())"
        if ($Criteria.Never -and $atLeast) {
            $clause = "($clause -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))"
            $createdBefore = $cutoff
        }
        elseif ($Criteria.Never) { $clause = "($clause -or -not (lastLogonTimestamp -like '*'))" }
        $filter += " -and $clause"
    }
    @{ Filter = $filter; CreatedBefore = $createdBefore }
}

function Get-AdvancedSearchProblem($Criteria) {
    # Why the criteria can't be searched, or nothing.
    if ($Criteria.Scope -eq 'OU' -and -not $Criteria.OU) { return Tr "Choisissez l'OU où chercher (Recherche avancée)" }
    if ($Criteria.Scope -eq 'OUName' -and -not "$($Criteria.OUName)".Trim()) { return Tr 'Entrez le début du nom des OU (Recherche avancée)' }
    if ($Criteria.Logon -ne 'Any' -and -not $Criteria.Number) { return Tr 'Entrez un nombre de 1 à 999 pour la dernière connexion (Recherche avancée)' }
}

function Format-AgeAmount([int]$Number, [int]$Unit) {
    # 90 jours, 1 semaine, 6 mois, 1 an.
    if ($Number -eq 1) { return @((Tr '1 jour'), (Tr '1 semaine'), (Tr '1 mois'), (Tr '1 an'))[$Unit] }
    @((Tr '{0} jours'), (Tr '{0} semaines'), (Tr '{0} mois'), (Tr '{0} ans'))[$Unit] -f $Number
}

function Format-AdvancedSearch($Criteria, [switch]$WithDomain) {
    # The criteria set, each in a few words, for the results' scope, the recent searches and the button's tooltip.
    # -WithDomain: an OU chosen says its domain (several are offered).
    if ($Criteria.Scope -eq 'OU' -and $Criteria.OU) {
        $text = (Tr 'OU {0}') -f (Get-OUPath "CN=x,$($Criteria.OU)")
        if ($WithDomain) { $text += " ($($Criteria.OUDomain))" }
        $text
    }
    elseif ($Criteria.Scope -eq 'OUName') { (Tr 'OU {0}…') -f $Criteria.OUName }
    if ($Criteria.State -eq 'Enabled') { Tr 'activés' }
    elseif ($Criteria.State -eq 'Disabled') { Tr 'désactivés' }
    if ($Criteria.System) { (Tr 'système « {0} »') -f $Criteria.System }
    if ($Criteria.Logon -ne 'Any') {
        $amount = Format-AgeAmount $Criteria.Number $Criteria.Unit
        $format = switch ("$($Criteria.Logon) $($Criteria.Never)") {
            'AtLeast True' { Tr 'inactifs depuis {0}' }
            'AtLeast False' { Tr 'inactifs depuis {0}, sauf jamais connectés' }
            'Less True' { Tr 'connectés depuis moins de {0}, ou jamais' }
            default { Tr 'connectés depuis moins de {0}' }
        }
        $format -f $amount
    }
}

function Initialize-AdvancedSearch($Root) {
    # Wires the popup's controls to the criteria ($script:AdvancedSearch, read from recherche.json by then), and shows
    # them. $Root: the main window's content.
    $part = { param($name) $Root.FindName("advanced_$name") }
    $parts = @{
        Button = $Root.FindName('advanced'); Text = & $part 'text'; Popup = & $part 'popup'; Panel = & $part 'panel'
        ScopeAll = & $part 'scope_all'; ScopeOU = & $part 'scope_ou'; ScopeName = & $part 'scope_name'
        OURow = & $part 'ou_row'; OUText = & $part 'ou_text'; OUPick = & $part 'ou_pick'; NameRow = & $part 'name_row'; OUName = & $part 'ou_name'
        ScopeNote = & $part 'scope_note'
        StateAll = & $part 'state_all'; StateEnabled = & $part 'state_enabled'; StateDisabled = & $part 'state_disabled'
        System = & $part 'system'
        LogonAny = & $part 'logon_any'; LogonAtLeast = & $part 'logon_atleast'; LogonLess = & $part 'logon_less'
        Amount = & $part 'logon_amount'; Number = & $part 'logon_number'; Never = & $part 'logon_never'
        Units = @(0..3 | ForEach-Object { & $part "logon_unit$_" })
        Reset = & $part 'reset'; Search = & $part 'search'
    }
    $script:AdvancedSearchUi.Parts = $parts
    if (-not $script:AdvancedSearch) { $script:AdvancedSearch = New-AdvancedSearch }

    # Under Avancée, its right edge on the button's (the card's margin, for its shadow, past it): the button is near the
    # window's right side, and the popup opens towards its middle.
    $parts.Popup.CustomPopupPlacementCallback = [System.Windows.Controls.Primitives.CustomPopupPlacementCallback]{
        param($popupSize, $targetSize, $offset)
        , [System.Windows.Controls.Primitives.CustomPopupPlacement]::new([System.Windows.Point]::new($targetSize.Width - $popupSize.Width + 10, $targetSize.Height), 'Horizontal')
    }

    # A click on Avancée opens the popup, or closes it (the click outside it has already, a moment before).
    $parts.Button.Add_Click({
        $ui = $script:AdvancedSearchUi
        if (([datetime]::Now - $ui.ClosedAt).TotalMilliseconds -lt 250) { return }
        Set-AdvancedPopupRoom
        $ui.Parts.Popup.IsOpen = $true
    })
    $parts.Popup.Add_Closed({ $script:AdvancedSearchUi.ClosedAt = [datetime]::Now })
    # The priority typed: as a string, PowerShell would pick BeginInvoke(Delegate, params Object[]) and pass it to the
    # action as an argument, which then fails (« Parameter count mismatch »).
    $parts.Popup.Add_Opened({ $null = $script:AdvancedSearchUi.Parts.ScopeAll.Dispatcher.BeginInvoke([Action]{ $null = [System.Windows.Input.Keyboard]::Focus((Get-AdvancedSearchFocus)) }, [System.Windows.Threading.DispatcherPriority]::Input) })

    # Any change: the criteria follow, and the button with them.
    $changed = { if (-not $script:AdvancedSearchUi.Updating) { Read-AdvancedSearchControl } }
    foreach ($button in @($parts.ScopeAll, $parts.ScopeName, $parts.StateAll, $parts.StateEnabled, $parts.StateDisabled, $parts.LogonAny, $parts.LogonAtLeast, $parts.LogonLess) + $parts.Units) {
        $button.Add_Checked($changed)
    }
    foreach ($box in $parts.OUName, $parts.System, $parts.Number) { $box.Add_TextChanged($changed) }
    $parts.Never.Add_Checked($changed)
    $parts.Never.Add_Unchecked($changed)
    # « Jamais » goes with « plus de » (never logged on is as inactive as can be), not with « moins de ».
    $parts.LogonAtLeast.Add_Checked({ if (-not $script:AdvancedSearchUi.Updating) { $script:AdvancedSearchUi.Parts.Never.IsChecked = $true } })
    $parts.LogonLess.Add_Checked({ if (-not $script:AdvancedSearchUi.Updating) { $script:AdvancedSearchUi.Parts.Never.IsChecked = $false } })
    # Une OU: the OU chosen, or the tree to choose one when there's none yet.
    $parts.ScopeOU.Add_Checked({
        if ($script:AdvancedSearchUi.Updating) { return }
        if ($script:AdvancedSearch.OU) { Read-AdvancedSearchControl }
        else { $null = $script:AdvancedSearchUi.Parts.ScopeOU.Dispatcher.BeginInvoke([Action]{ Request-AdvancedSearchOU }) }
    })
    $parts.OUPick.Add_Click({ Request-AdvancedSearchOU })
    $parts.Reset.Add_Click({ Set-AdvancedSearch (New-AdvancedSearch) })
    $parts.Search.Add_Click({
        $script:AdvancedSearchUi.Parts.Popup.IsOpen = $false
        Invoke-Search
    })
    # Entrée searches (but on a button, which does its own), Échap closes.
    $parts.Popup.Child.Add_PreviewKeyDown({
        param($panel, $e)
        $ui = $script:AdvancedSearchUi
        if ($e.Key -eq 'Escape') { $ui.Parts.Popup.IsOpen = $false; $e.Handled = $true }
        elseif ($e.Key -eq 'Return' -and [System.Windows.Input.Keyboard]::FocusedElement -isnot [System.Windows.Controls.Primitives.ButtonBase]) {
            $ui.Parts.Popup.IsOpen = $false
            $e.Handled = $true
            Invoke-Search
        }
    })
    Show-AdvancedSearch
}

function Get-AdvancedSearchFocus {
    # Where the popup's keyboard goes as it opens: the emplacement chosen.
    $parts = $script:AdvancedSearchUi.Parts
    switch ($script:AdvancedSearch.Scope) { 'OU' { $parts.ScopeOU } 'OUName' { $parts.ScopeName } default { $parts.ScopeAll } }
}

function Show-AdvancedSearch {
    # The popup's controls and the button, from the criteria.
    $ui = $script:AdvancedSearchUi
    $parts = $ui.Parts
    $criteria = $script:AdvancedSearch
    $ui.Updating = $true
    try {
        $parts.ScopeAll.IsChecked = $criteria.Scope -eq 'All'
        $parts.ScopeOU.IsChecked = $criteria.Scope -eq 'OU'
        $parts.ScopeName.IsChecked = $criteria.Scope -eq 'OUName'
        $parts.OUName.Text = $criteria.OUName
        $parts.StateAll.IsChecked = $criteria.State -eq 'All'
        $parts.StateEnabled.IsChecked = $criteria.State -eq 'Enabled'
        $parts.StateDisabled.IsChecked = $criteria.State -eq 'Disabled'
        $parts.System.Text = $criteria.System
        $parts.LogonAny.IsChecked = $criteria.Logon -eq 'Any'
        $parts.LogonAtLeast.IsChecked = $criteria.Logon -eq 'AtLeast'
        $parts.LogonLess.IsChecked = $criteria.Logon -eq 'Less'
        # A number that isn't one stays as typed.
        if ($criteria.Number) { $parts.Number.Text = [string]$criteria.Number }
        for ($i = 0; $i -lt 4; $i++) { $parts.Units[$i].IsChecked = $i -eq $criteria.Unit }
        $parts.Never.IsChecked = $criteria.Never
    }
    finally { $ui.Updating = $false }
    Update-AdvancedSearchButton
}

function Read-AdvancedSearchControl {
    # The criteria, from the popup's controls.
    $parts = $script:AdvancedSearchUi.Parts
    $criteria = $script:AdvancedSearch
    $criteria.Scope = if ($parts.ScopeOU.IsChecked) { 'OU' } elseif ($parts.ScopeName.IsChecked) { 'OUName' } else { 'All' }
    $criteria.OUName = "$($parts.OUName.Text)".Trim()
    $criteria.State = if ($parts.StateEnabled.IsChecked) { 'Enabled' } elseif ($parts.StateDisabled.IsChecked) { 'Disabled' } else { 'All' }
    $criteria.System = "$($parts.System.Text)".Trim()
    $criteria.Logon = if ($parts.LogonAtLeast.IsChecked) { 'AtLeast' } elseif ($parts.LogonLess.IsChecked) { 'Less' } else { 'Any' }
    $number = 0
    $criteria.Number = if ([int]::TryParse("$($parts.Number.Text)".Trim(), [ref]$number) -and $number -ge 1 -and $number -le 999) { $number } else { 0 }
    for ($i = 0; $i -lt 4; $i++) { if ($parts.Units[$i].IsChecked) { $criteria.Unit = $i } }
    $criteria.Never = [bool]$parts.Never.IsChecked
    Update-AdvancedSearchButton
}

function Update-AdvancedSearchButton {
    # Avancée says how many criteria are set, and its tooltip which; the popup shows what goes with each choice.
    $parts = $script:AdvancedSearchUi.Parts
    $criteria = $script:AdvancedSearch
    $count = Get-AdvancedSearchCount $criteria
    $parts.Text.Text = if ($count) { (Tr 'Avancée ({0})') -f $count } else { Tr 'Avancée' }
    $parts.Button.ToolTip = if ($count) { ((Tr 'Recherche avancée : {0}') -f (@(Format-AdvancedSearch $criteria -WithDomain:$script:showDomains) -join ', ')) }
                            else { Tr 'Recherche avancée : emplacement, état, système, dernière connexion' }
    $parts.OURow.Visibility = ConvertTo-Visibility ($criteria.Scope -eq 'OU')
    $parts.OUText.Text = if ($criteria.OU) {
        $path = Get-OUPath "CN=x,$($criteria.OU)"
        if ($script:showDomains) { "$path · $($criteria.OUDomain)" } else { $path }
    }
    else { Tr 'Aucune OU choisie' }
    $parts.NameRow.Visibility = ConvertTo-Visibility ($criteria.Scope -eq 'OUName')
    $parts.ScopeNote.Visibility = ConvertTo-Visibility ($criteria.Scope -ne 'All')
    $parts.Amount.IsEnabled = $criteria.Logon -ne 'Any'
    $parts.Never.IsEnabled = $criteria.Logon -ne 'Any'
}

function Request-AdvancedSearchOU {
    # Choisir…: the OU where to search, from the tree (Show-OuPicker, ComputerActions.ps1), in the OU's domain, else
    # the one the search shows (the user's with Tous les domaines). The popup closes meanwhile and opens again after.
    # Without an OU (none chosen yet, the tree closed), the emplacement stays what it was: Une OU, just ticked, hasn't
    # been read into the criteria.
    $ui = $script:AdvancedSearchUi
    $criteria = $script:AdvancedSearch
    $ui.Parts.Popup.IsOpen = $false
    $domain = if ($criteria.OUDomain) { $criteria.OUDomain }
              else {
                  $shown = if ($script:showDomains) { Get-ListChoice $script:comboBoxDomain $script:domainChoices } else { $script:defaultDomain }
                  if ($shown -eq 'Tous les domaines') { $script:defaultDomain } else { $shown }
              }
    $chosen = Show-OuPicker $domain $criteria.OU
    if ($chosen) {
        $criteria.OU = $chosen.DN
        $criteria.OUDomain = $chosen.Domain
        $criteria.Scope = 'OU'
    }
    Show-AdvancedSearch
    # Its keyboard may stay in the window, back from the tree: the window's Échap closes it too.
    Set-AdvancedPopupRoom
    $ui.Parts.Popup.IsOpen = $true
}

function Set-AdvancedPopupRoom {
    # The popup as tall as the room under Avancée, down to the bottom of its screen's work area: at a large text size on
    # a small screen, it scrolls rather than running over the taskbar, where Rechercher was hidden. Called as it opens.
    $ui = $script:AdvancedSearchUi
    $button = $ui.Parts.Button
    $source = [System.Windows.PresentationSource]::FromVisual($button)
    if (-not $source -or -not $button.IsVisible) { return }
    # Under the button, in WPF's units: PointToScreen gives the screen's pixels.
    $bottom = $source.CompositionTarget.TransformFromDevice.Transform($button.PointToScreen([System.Windows.Point]::new(0, $button.ActualHeight)))
    $area = Get-ScreenWorkArea ([System.Windows.Rect]::new($bottom.X, $bottom.Y, 1, 1))
    # The card's margin (above it, and below it for its shadow) is in the popup's own units, like MaxHeight: the text size
    # scales both.
    $panel = $ui.Parts.Panel
    $room = ($area.Bottom - $bottom.Y) / $script:UiScale.ScaleY - $panel.Margin.Top - $panel.Margin.Bottom
    $panel.MaxHeight = if ($room -gt 120) { $room } else { [double]::PositiveInfinity }
}
