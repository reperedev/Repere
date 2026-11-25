# Ordinateurs: the main window's first page. Computers are found by the start of their name and their description (or
# part of their name, their IP address, a BitLocker key), with the Recherche avancée's criteria (AdvancedSearch.ps1:
# an OU, their state, their system, their last logon), in one domain or all of them, each domain in a search runspace
# of its own; the last searches come back from recherche.json.
# Then their rows (the row builder, $rowBuilderScript, whose Format-Age and Get-OUPath the Utilisateurs and Groupes
# searches use too), the results grid, its filter, its columns (apparence.json) and Exporter. What's done to the
# selected computers is in ComputerActions.ps1.
# Dot-sourced by the main script once its window is built ($root, $win, ConvertTo-Visibility, Open-ButtonMenu) and its
# search runspaces opened ($searchPool): it finds the page's controls and wires them as it loads.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

$dataGrid      = $root.FindName('data_grid')
$resultsCount  = $root.FindName('results_count')
$searchTime    = $root.FindName('search_time')
$showAllButton = $root.FindName('results_show_all')
$showAllButton.Add_Click({ Show-AllResult })
$exportButton  = $root.FindName('export')
$resultsScope  = $root.FindName('results_scope')
# Liste de noms: the names not found, above the grid with Copier (Update-ComputerNotFound).
$root.FindName('results_not_found_copy').Add_Click({ Copy-PageNotFound @{ NotFound = $script:results.NotFound } })
$gridEmpty     = $root.FindName('grid_empty')
$gridEmptyText = $root.FindName('grid_empty_text')
# A search that found nothing: what it was, and the next ones to try (Update-EmptyState).
$gridEmptyCriteria = $root.FindName('grid_empty_criteria')
$gridEmptyLinks = @{ AllDomains = $root.FindName('grid_empty_all_domains'); NoAdvanced = $root.FindName('grid_empty_no_advanced'); ClearFilter = $root.FindName('grid_empty_clear_filter') }
$root.FindName('grid_empty_all_domains_link').Add_Click({ Search-EmptyAgain -AllDomains })
$root.FindName('grid_empty_no_advanced_link').Add_Click({ Search-EmptyAgain -NoAdvanced })
$root.FindName('grid_empty_clear_filter_link').Add_Click({ Clear-ResultFilter })
$filterBox     = $root.FindName('filter')
$searchButton  = $root.FindName('button')
$cancelSearchButton = $root.FindName('cancel_search')
$textBoxPrefix = $root.FindName('prefix')
$textBoxSearchTerm = $root.FindName('search_term')
$comboBoxSearch = $root.FindName('search_type')
# What a search is missing (Show-SearchHint), under the field or the box it's about; it goes as soon as the search
# changes: a box, the type (below), the domain or the Recherche avancée.
$searchField   = $root.FindName('search_field')
$searchHint    = $root.FindName('search_hint')
$textBoxPrefix, $textBoxSearchTerm | ForEach-Object { $_.Add_TextChanged({ Hide-SearchHint $script:searchHint }) }
$root.FindName('domain').Add_SelectionChanged({ Hide-SearchHint $script:searchHint })
$root.FindName('advanced_popup').Add_Opened({ Hide-SearchHint $script:searchHint })
# The lists below show their choices in the run's language, while the code and recherche.json know each by its id, its
# French text: a search saved in one language comes back in the other. Each list's choices: id -> text shown.
function Set-SearchBoxShown([bool]$Prefix, [bool]$SearchTerm) {
    # The search field's two boxes, or the one a search type uses, alone across the field: no box sits there unused.
    # A box hidden keeps what was typed in it, back with the box. Its column goes to 0, so the other takes its space.
    $columns = $script:textBoxPrefix.Parent.ColumnDefinitions
    $columns[1].Width = if ($Prefix) { [System.Windows.GridLength]::new(2, 'Star') } else { [System.Windows.GridLength]::new(0) }
    $columns[3].Width = if ($SearchTerm) { [System.Windows.GridLength]::new(3, 'Star') } else { [System.Windows.GridLength]::new(0) }
    $script:textBoxPrefix.Visibility = ConvertTo-Visibility $Prefix
    $script:textBoxSearchTerm.Visibility = ConvertTo-Visibility $SearchTerm
    $script:root.FindName('search_divider').Visibility = ConvertTo-Visibility ($Prefix -and $SearchTerm)
}

function Get-SearchBox {
    # The box Ctrl+F goes to: the name's, or the other when a search type hides it (Liste de noms).
    if ($script:textBoxPrefix.Visibility -eq 'Visible') { $script:textBoxPrefix } else { $script:textBoxSearchTerm }
}

function Get-ListChoice($ComboBox, $Choices) {
    # The id of the choice the list shows; a domain's name is its own id.
    $shown = [string]$ComboBox.SelectedItem
    foreach ($id in $Choices.Keys) { if ($Choices[$id] -ceq $shown) { return $id } }
    $shown
}

function Select-ListChoice($ComboBox, $Choices, [string]$Id) {
    # Shows the choice $Id in the list. $false when the list doesn't offer it (a value from another version).
    $shown = if ($Choices.Contains($Id)) { $Choices[$Id] } else { $Id }
    if (-not $ComboBox.Items.Contains($shown)) { return $false }
    $ComboBox.SelectedItem = $shown
    $true
}

function Get-ChoiceText($Choices, [string]$Id) {
    # The text shown for an id (a domain's name for a domain).
    if ($Choices.Contains($Id)) { $Choices[$Id] } else { $Id }
}

$comboBoxDomain = $root.FindName('domain')

# Each search type, and what its second box asks for (Adresse IP uses it too).
$searchTermHints = [ordered]@{
    'Description contient' = (Tr 'Description (ex. accueil)'); 'Description commence par' = (Tr 'Description (ex. accueil)')
    'Description termine par' = (Tr 'Description (ex. accueil)'); 'Sans description' = (Tr 'Description (ex. accueil)')
    'Liste de noms' = (Tr 'Noms séparés par des espaces ou des virgules (ex. ORD-01, ORD-04)')
    'Adresse IP' = (Tr 'Adresse IP (ex. 10.0.1.14)')
    'ID de clé BitLocker' = (Tr 'ID de la clé, au moins 8 caractères (ex. 6F1C2E7A)')
}
# The same box's tooltip: what each type matches. Ctrl+F comes to it only when the name's box is hidden (Liste de noms).
$searchTermTips = [ordered]@{
    'Description contient' = (Tr 'Une partie de la description'); 'Description commence par' = (Tr 'Le début de la description')
    'Description termine par' = (Tr 'La fin de la description'); 'Sans description' = $null
    'Liste de noms' = (Tr 'Noms entiers, séparés par des espaces ou des virgules (Ctrl+F)')
    'Adresse IP' = (Tr "L'adresse IP entière, IPv4 ou IPv6")
    'ID de clé BitLocker' = (Tr "Le début de l'ID de la clé, au moins 8 caractères")
}
$searchChoices = [ordered]@{
    'Description contient' = (Tr 'Description contient'); 'Description commence par' = (Tr 'Description commence par')
    'Description termine par' = (Tr 'Description termine par'); 'Sans description' = (Tr 'Sans description')
    'Liste de noms' = (Tr 'Liste de noms'); 'Adresse IP' = (Tr 'Adresse IP')
    'ID de clé BitLocker' = (Tr 'ID de clé BitLocker')
}
# Liste de noms: the names one search takes at most (an AD filter has a length limit).
$maxListNames = 200
# The key ID the last search looked for (ID de clé BitLocker), which Clés BitLocker… points out; $null after any other.
$script:BitLockerKeySought = $null
foreach ($searchType in $searchChoices.Values) {
    $comboBoxSearch.Items.Add($searchType) | Out-Null
}
$null = Select-ListChoice $comboBoxSearch $searchChoices 'Description contient'
$comboBoxSearch.Add_SelectionChanged({
    Hide-SearchHint $script:searchHint
    # The description doesn't apply when looking for computers without one.
    # Liste de noms: the names in the second box, whole; the name's box doesn't apply.
    $type = Get-ListChoice $comboBoxSearch $searchChoices
    Set-SearchBoxShown -Prefix ($type -ne 'Liste de noms') -SearchTerm ($type -ne 'Sans description')
    $textBoxSearchTerm.Tag = $searchTermHints[$type]
    $textBoxSearchTerm.ToolTip = $searchTermTips[$type]
    # Adresse IP and ID de clé BitLocker need only the second box: the name's only narrows them down.
    $textBoxPrefix.Tag = if ($type -in 'Adresse IP', 'ID de clé BitLocker') { Tr 'Nom contient… (facultatif)' } else { Tr 'Nom contient…' }
})
# Lines pasted in the second box (a column of names from Excel or a ticket) stay apart in that one-line box: a comma
# between each.
[System.Windows.DataObject]::AddPastingHandler($textBoxSearchTerm, [System.Windows.DataObjectPastingEventHandler]{
    param($box, $e)
    if (-not $e.DataObject.GetDataPresent([System.Windows.DataFormats]::UnicodeText)) { return }
    $text = [string]$e.DataObject.GetData([System.Windows.DataFormats]::UnicodeText)
    if ($text -notmatch '[\r\n\t]') { return }
    $data = [System.Windows.DataObject]::new()
    $data.SetData([System.Windows.DataFormats]::UnicodeText, (@($text -split '[\r\n\t]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ', '))
    $e.DataObject = $data
})

$domainChoices = [ordered]@{ 'Tous les domaines' = (Tr 'Tous les domaines') }
$comboBoxDomain.Items.Add($domainChoices['Tous les domaines']) | Out-Null
foreach ($domain in $domainList) {
    $comboBoxDomain.Items.Add($domain) | Out-Null
}
$comboBoxDomain.SelectedItem = $defaultDomain
if (-not $showDomains) {
    # A single domain: no list, and the search type stands alone.
    $root.FindName('scope_panel').Children.Remove($comboBoxDomain)
}

# The search settings and the recent searches, in %APPDATA%\Repere\recherche.json: the domain, the search type and
# the Recherche avancée's criteria (Advanced) come back at the next launch, and the last searches are offered by the
# search field's button (Recherches récentes), most recent first. Each is a Domain, Type, Prefix, Term and Advanced
# (its criteria, $null without any). The Utilisateurs and Groupes pages' are kept there too, as Users and Groups
# ($PageSearchSettings, SearchPage.ps1). A file saved before the advanced search has Inactifs depuis instead
# (Inactive, with its search type): it's read as a criterion.
$searchSettingsPath = Get-SettingPath 'recherche.json'
$recentSearches = [System.Collections.Generic.List[object]]::new()
$maxRecentSearches = 10

function Read-SearchSetting {
    # A file that's missing or can't be read leaves the defaults; values that no longer exist are left out.
    $saved = Read-JsonSetting $searchSettingsPath Domain, SearchType, Advanced, Inactive, Recent, Users, Groups
    if (-not $saved) { return }
    # The Utilisateurs and Groupes pages' (SearchPage.ps1), applied when each is built.
    foreach ($key in 'Users', 'Groups') { $script:PageSearchSettings[$key] = ConvertFrom-SavedPageSearch $saved.$key }
    if ($showDomains) { $null = Select-ListChoice $comboBoxDomain $domainChoices ([string]$saved.Domain) }
    $null = Select-ListChoice $comboBoxSearch $searchChoices ([string]$saved.SearchType)
    $inactive = if ($saved.SearchType -eq 'Inactifs depuis') { [string]$saved.Inactive }
    Set-AdvancedSearch (ConvertFrom-SavedAdvancedSearch $saved.Advanced $inactive)
    foreach ($entry in @($saved.Recent | Where-Object { $_ } | Select-Object Domain, Type, Prefix, Term, Advanced, Inactive)) {
        # Inactifs depuis was a search type: it's Description contient now, with its duration as a criterion. So was
        # Nom contient: its text is in the name's box now, after the start of the name it was searched with.
        $type = [string]$entry.Type
        $prefix = [string]$entry.Prefix
        $term = [string]$entry.Term
        $inactive = $null
        if ($type -eq 'Inactifs depuis') { $inactive = [string]$entry.Inactive; $type = 'Description contient' }
        elseif ($type -eq 'Nom contient') { $prefix = @($prefix, $term | Where-Object { $_ }) -join '*'; $term = ''; $type = 'Description contient' }
        if (-not $searchChoices.Contains($type) -or $recentSearches.Count -ge $maxRecentSearches) { continue }
        $criteria = ConvertFrom-SavedAdvancedSearch $entry.Advanced $inactive
        $recentSearches.Add([ordered]@{
            Domain = [string]$entry.Domain; Type = $type; Prefix = $prefix; Term = $term
            Advanced = ConvertTo-SavedAdvancedSearch $criteria
        })
    }
}

function Save-SearchSetting {
    $settings = [ordered]@{
        Domain = Get-ListChoice $comboBoxDomain $domainChoices; SearchType = Get-ListChoice $comboBoxSearch $searchChoices
        Advanced = ConvertTo-SavedAdvancedSearch $script:AdvancedSearch -Always; Recent = @($recentSearches)
    }
    foreach ($key in 'Users', 'Groups') {
        $page = $script:PageSearchSettings[$key]
        if ($page) { $settings[$key] = [ordered]@{ Domain = $page.Domain; Type = $page.Type; Recent = @($page.Recent) } }
    }
    Save-JsonSetting $searchSettingsPath $settings -Depth 5
}

function Add-RecentSearch($Entry) {
    # First in the list; the same search earlier in it is removed.
    $key = $Entry | ConvertTo-Json -Compress
    foreach ($old in @($recentSearches)) { if (($old | ConvertTo-Json -Compress) -eq $key) { $recentSearches.Remove($old) | Out-Null } }
    $recentSearches.Insert(0, $Entry)
    while ($recentSearches.Count -gt $maxRecentSearches) { $recentSearches.RemoveAt($recentSearches.Count - 1) }
    Save-SearchSetting
}

function Get-ComputerSearchPart($Entry, [switch]$WithDomain) {
    # What a search looked for, as the recent searches and the empty grid (#193) say it: each search type in words, then
    # its text (Nom contient « ORD », Description commence par « acc »), then the Recherche avancée's criteria. A list and
    # an address say what they are: « liste : a, b, c (+12) », « IP 10.0.1.14 ». -WithDomain: an OU chosen says its
    # domain.
    $type = [string]$Entry.Type
    $parts = @(if ($Entry.Prefix) { Format-RecentPart (Tr 'Nom contient') $Entry.Prefix })
    $parts += switch ($type) {
        'Sans description' { $searchChoices[$type] }
        'Liste de noms' { (Tr 'liste : {0}') -f (Get-ListText @(ConvertTo-ComputerNameList $Entry.Term)) }
        'Adresse IP' { "IP $($Entry.Term)" }
        # Description contient, commence par, termine par (none when only the name was searched); ID de clé BitLocker.
        default { if ($Entry.Term) { Format-RecentPart $searchChoices[$type] $Entry.Term } }
    }
    if ($Entry.Advanced) { $parts += @(Format-AdvancedSearch (ConvertFrom-SavedAdvancedSearch $Entry.Advanced) -WithDomain:$WithDomain) }
    $parts | Where-Object { $_ }
}

function Format-RecentSearch($Entry) {
    # As Utilisateurs and Groupes say theirs (Join-RecentSearch): its parts, then the domain:
    # Nom contient « ORD » · Description commence par « acc » · OU Communs…  —  demo.local. $null for a type this
    # version doesn't have.
    if (-not $searchChoices.Contains([string]$Entry.Type)) { return }
    Join-RecentSearch @(Get-ComputerSearchPart $Entry -WithDomain:$showDomains) (Get-ChoiceText $domainChoices $Entry.Domain)
}

function Update-RecentMenu {
    # The menu, filled when it opens.
    $menu = $script:recentMenu
    $menu.Items.Clear()
    $entries = @($script:recentSearches | Where-Object { Format-RecentSearch $_ })
    if (-not $entries.Count) {
        $empty = [System.Windows.Controls.MenuItem]::new()
        $empty.Header = Tr 'Aucune recherche récente'
        $empty.IsEnabled = $false
        $menu.Items.Add($empty) | Out-Null
        return
    }
    foreach ($entry in $entries) {
        $item = [System.Windows.Controls.MenuItem]::new()
        Set-RecentHeader $item (Format-RecentSearch $entry)
        $item.Tag = $entry
        $item.Add_Click({ param($item) Use-RecentSearch $item.Tag })
        $menu.Items.Add($item) | Out-Null
    }
    $menu.Items.Add([System.Windows.Controls.Separator]::new()) | Out-Null
    $clear = [System.Windows.Controls.MenuItem]::new()
    $clear.Header = Tr 'Effacer les recherches récentes'
    $clear.Name = 'recent_clear'
    $clear.Add_Click({
        $script:recentSearches.Clear()
        Save-SearchSetting
    })
    $menu.Items.Add($clear) | Out-Null
}

function Use-RecentSearch($Entry) {
    # Fills in the search as it was, then runs it. A domain that's no longer offered leaves the current one.
    if ($showDomains) { $null = Select-ListChoice $comboBoxDomain $domainChoices $Entry.Domain }
    $null = Select-ListChoice $comboBoxSearch $searchChoices $Entry.Type
    Set-AdvancedSearch (ConvertFrom-SavedAdvancedSearch $Entry.Advanced)
    $textBoxPrefix.Text = $Entry.Prefix
    $textBoxSearchTerm.Text = $Entry.Term
    Invoke-Search
}

$recentButton = $root.FindName('recent_searches')
$recentMenu = $root.FindName('recent_menu')
function Open-RecentMenu {
    # Under the whole search field, from its left edge, rather than under the small button at its right end.
    Update-RecentMenu
    $script:recentMenu.PlacementTarget = $script:root.FindName('search_field')
    $script:recentMenu.Placement = 'Bottom'
    $script:recentMenu.IsOpen = $true
}
$recentButton.Add_Click({ Open-RecentMenu })
$recentButton.Add_ContextMenuOpening({ Update-RecentMenu })
# ↓ in the name or description box opens the list too.
foreach ($box in $textBoxPrefix, $textBoxSearchTerm) {
    $box.Add_PreviewKeyDown({
        $e = $args[1]
        if ($e.Key -eq 'Down' -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::None) {
            Open-RecentMenu
            $e.Handled = $true
        }
    })
}
Read-SearchSetting
# The settings as they are when Repère closes.
$win.Add_Closing({ Save-SearchSetting })

# The OUs a name finds in each domain (Recherche avancée's OU nommées), by domain and name: looked up on the first
# search there and kept for the session (they rarely change). A hashtable so the search can fill it in.
$namedOUs = @{}

# The rows of the last search (Rows), and the grid's view of them (View), which sorts them and applies the filter box.
# Each row holds what the grid shows and what the actions need. Failed: every domain failed. ErrorText / ErrorDetails:
# the domains that failed, kept so filtering doesn't hide them. Query: the filter box's text, as the view's filter reads it.
$results = @{
    Rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new(); View = $null; Query = ''
    Searched = $false; Failed = $false; ErrorText = ''; ErrorDetails = ''; Today = (Get-Date).Date
    # TextStale: the rows' text no longer matches the columns shown; it's rebuilt when the filter box next needs it.
    TextStale = $false
    # The search whose rows are shown as it was asked (for Tout afficher), and the domains where it found more than its
    # limit. Set once a domain has answered, with Shown: a search cancelled before any did leaves the rows of the one
    # before, which Tout afficher must run again, not the cancelled one (#235).
    LastSearch = $null; Truncated = $null
    # That search as it ran (its jobs, its time…), and its domains that answered.
    Shown = $null; Answered = @()
    # Liste de noms: the names it didn't find, and the domains that didn't answer (which may have them).
    NotFound = @(); Unanswered = @()
    # Adresse IP: what the name's box needs to look the address up (Show-AddressNeed), when nothing was found.
    Need = $null
}
# The column filters (ColumnFilter.ps1), set up with the columns, and the view's filter: the filter box and them.
$computerFilter = $null
$rowFilter = $null

# How a computer found becomes a row of the grid: what it shows and what the actions need. In one piece of code that
# the search runspaces load too, so each builds its domain's rows in the background (thousands take a second or more),
# and the window here, for the rest (Get-ShortPath). Today: the date the ages are counted from, the same for a whole
# search. TextProperties: the properties the filter box searches (Get-TextProperty).
$rowBuilderScript = {
    function Format-Age($Date, [datetime]$Today) {
        # How long ago, the way the column shows it.
        if (-not $Date) { return Tr 'Jamais' }
        $days = [int][Math]::Floor(($Today - $Date.Date).TotalDays)
        $months = [int][Math]::Floor($days / 30)
        if ($days -le 0) { Tr "aujourd'hui" }
        elseif ($days -eq 1) { Tr 'hier' }
        elseif ($days -lt 30) { (Tr 'il y a {0} jours') -f $days }
        # « mois » is the same for one or more in French, not in English.
        elseif ($days -lt 60) { Tr 'il y a 1 mois' }
        elseif ($days -lt 365) { (Tr 'il y a {0} mois') -f $months }
        elseif ($days -lt 730) { Tr 'il y a 1 an' }
        else { (Tr 'il y a {0} ans') -f [int][Math]::Floor($days / 365) }
    }

    function Get-ShortPath([string]$DistinguishedName) {
        # CN=ORD-05,OU=Communs,OU=Postes,DC=demo,DC=local -> demo.local/Postes/Communs. Containers such as
        # CN=Computers are kept too; only the computer itself is left out. A plain loop: it runs for every row.
        $parts = $DistinguishedName -split '(?<!\\),'
        $domain = [System.Collections.Generic.List[string]]::new()
        $path = [System.Collections.Generic.List[string]]::new()
        for ($i = $parts.Count - 1; $i -ge 1; $i--) {
            $part = $parts[$i]
            if ($part.StartsWith('DC=', [System.StringComparison]::OrdinalIgnoreCase)) { $domain.Insert(0, $part.Substring(3)) }
            else { $path.Add(($part.Substring($part.IndexOf('=') + 1) -replace '\\([,+"\\<>;=#])', '$1')) }
        }
        $path.Insert(0, $domain -join '.')
        $path -join '/'
    }

    function Get-OUPath([string]$DistinguishedName) {
        # CN=ORD-05,OU=Communs,OU=Postes,DC=demo,DC=local -> Postes › Communs: the Emplacement column, whose
        # domain is in the Domaine column. Containers such as CN=Computers are kept.
        $parts = $DistinguishedName -split '(?<!\\),'
        $path = [System.Collections.Generic.List[string]]::new()
        for ($i = $parts.Count - 1; $i -ge 1; $i--) {
            $part = $parts[$i]
            if (-not $part.StartsWith('DC=', [System.StringComparison]::OrdinalIgnoreCase)) { $path.Add(($part.Substring($part.IndexOf('=') + 1) -replace '\\([,+"\\<>;=#])', '$1')) }
        }
        $path -join ' › '
    }

    function Get-SystemInfo([string]$OperatingSystem, [string]$Version, [datetime]$Today) {
        # The Système column: a short name (Win 11 24H2, Server 2022), the full value for the tooltip, the build to sort
        # by, and whether its support has ended (same table as the Caractéristiques alerts, PCSpecs.ps1). Tip, the
        # tooltip: the full value, then what Repère adds about its support (a release it doesn't know yet, ESU). All
        # empty when AD doesn't know.
        if (-not $OperatingSystem) { return @{ Short = $null; Full = $null; Tip = $null; Build = $null; Outdated = $false } }
        $build = if ($Version -match '\((\d+)\)') { [int]$Matches[1] } else { 0 }
        $full = "$OperatingSystem $Version".Trim()
        if ($OperatingSystem -match 'Server (\d{4}(?: R2)?)') {
            return @{ Short = "Server $($Matches[1])"; Full = $full; Tip = $full; Build = $build; Outdated = $false }
        }
        $major = if ($build -ge 22000) { '11' } elseif ($OperatingSystem -match 'Windows (\d+)') { $Matches[1] } else { '' }
        $release = Get-WindowsRelease $build $OperatingSystem
        $short = if ($release -and $release.Name -match ' (\d{2}H\d)$') { "Win $major $($Matches[1])" }
                 elseif ($build) { "Win $major (build $build)" }
                 else { $OperatingSystem }
        $tip = if ($release -and $release.Note) { "$full`n$($release.Note)" } else { $full }
        # A release Repère doesn't know has no End: neutral, never out of support.
        @{ Short = $short; Full = $full; Tip = $tip; Build = $build; Outdated = [bool]($release -and $release.End -and $release.End -lt $Today) }
    }

    function New-ResultRow($Computer, [string]$Domain, [datetime]$Today, [string[]]$TextProperties, [hashtable]$Cache = @{}) {
        # Cache: what's worked out once per search and shared by many computers (a handful of Windows versions, a few
        # dozen OUs), rather than once per computer.
        $description = if ($Computer.Description) { [string]$Computer.Description } else { $null }
        $enabled = [bool]$Computer.Enabled
        $lastLogonDate = $Computer.LastLogonDate
        $systemKey = "os|$($Computer.OperatingSystem)|$($Computer.OperatingSystemVersion)"
        $system = $Cache[$systemKey]
        if (-not $system) { $system = $Cache[$systemKey] = Get-SystemInfo $Computer.OperatingSystem $Computer.OperatingSystemVersion $Today }
        # The computer's own name isn't part of its Emplacement: computers of the same OU share it.
        $dn = [string]$Computer.DistinguishedName
        $pathKey = "ou|$(($dn -split '(?<!\\),', 2)[-1])"
        $shortPath = $Cache[$pathKey]
        if ($null -eq $shortPath) { $shortPath = $Cache[$pathKey] = Get-ShortPath $dn }
        $ouPath = $Cache["path|$pathKey"]
        if ($null -eq $ouPath) { $ouPath = $Cache["path|$pathKey"] = Get-OUPath $dn }
        $row = [pscustomobject]@{
            ComputerName = [string]$Computer.Name
            Domain       = $Domain
            DistinguishedName = $dn
            # Domain/OU, for the messages and the export; OUPath (Postes › Communs) is what the grid shows.
            ShortPath    = $shortPath
            OUPath       = $ouPath
            # Sorts in date order. Null when it never logged on: shown as « Jamais » and sorted with the oldest.
            LastLogon    = if ($lastLogonDate) { $lastLogonDate.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
            LastLogonAgo = Format-Age $lastLogonDate $Today
            LastLogonTip = Format-TextDate $lastLogonDate
            # Its step, for the column's filter.
            # Not seen for 3 months or more, or never: probably unused.
            IsStale      = -not $lastLogonDate -or ($Today - $lastLogonDate.Date).TotalDays -ge 90
            # Null without a description: the grid shows « Aucune description » and sorts it first.
            Description  = $description
            # One value for the Compte column: null when enabled (sorted first), « Désactivé » otherwise.
            Disabled     = if ($enabled) { $null } else { Tr 'Désactivé' }
            IsOn         = $enabled
            # For the remote actions: the DNS name already includes the domain; without one, the name.
            HostName     = if ($Computer.DNSHostName) { [string]$Computer.DNSHostName } else { [string]$Computer.Name }
            # Système: null when AD doesn't know (« Inconnu », sorted first).
            OSShort      = $system.Short
            OSFull       = $system.Full
            OSTip        = $system.Tip
            OSBuild      = $system.Build
            IsOutdated   = $system.Outdated
            # En ligne: empty until Vérifier en ligne (IsOnline $null), « … » while it checks.
            Online       = $null
            OnlineTip    = $null
            IsOnline     = $null
            OnlineLabel  = $null
            OnlineAddress = $null
            # What the filter box searches: the visible columns' text (Update-RowText).
            Text         = ''
        }
        $row.Text = "$(foreach ($property in $TextProperties) { $row.$property })".ToLowerInvariant()
        $row
    }
}.ToString()
# Tr and Get-TextCulture (Language.ps1) with it, for the text the runspaces make.
$rowBuilderScript = $script:LanguageScript + [Environment]::NewLine + $rowBuilderScript
. ([scriptblock]::Create($rowBuilderScript))
# The Recherche avancée's popup, with the criteria read above: once Get-OUPath is there, which says an OU chosen.
Initialize-AdvancedSearch $root

# The text the filter box searches, by column key: only the visible columns', so a row never matches on text that
# can't be seen. Nom is always shown.
$searchedColumns = [ordered]@{ ComputerName = , 'ComputerName'; Description = , 'Description'; OSBuild = 'OSShort', 'OSFull'; ShortPath = , 'ShortPath' }

function Get-TextProperty {
    # The properties of a row the filter box searches: the visible columns'.
    foreach ($key in $searchedColumns.Keys) {
        if ($key -eq 'ComputerName' -or $gridColumns.Shown[$key]) { $searchedColumns[$key] }
    }
}

function Update-RowText($Row) {
    $Row.Text = "$(foreach ($property in Get-TextProperty) { $Row.$property })".ToLowerInvariant()
}

function Update-AllRowText {
    # Every row's text, the visible columns worked out once for all of them.
    $properties = @(Get-TextProperty)
    foreach ($row in $results.Rows) { $row.Text = "$(foreach ($property in $properties) { $row.$property })".ToLowerInvariant() }
    $results.TextStale = $false
}

# The rows don't tell the grid when they change: after changing some, Update-ChangedRow redraws them (Refresh) and
# sorts and filters them again.
function Set-RowDescription($Row, [string]$Description) {
    $Row.Description = if ($Description) { $Description } else { $null }
    Save-RowChange $Row.DistinguishedName 'Description' $Row.Description
    Update-RowText $Row
}

function Set-RowState($Row, [bool]$Enabled) {
    $Row.Disabled = if ($Enabled) { $null } else { Tr 'Désactivé' }
    $Row.IsOn = $Enabled
    Save-RowChange $Row.DistinguishedName 'Enabled' $Enabled
}

function Update-ChangedRow {
    # Redrawing makes new rows: the keys would go with the old ones, and the arrows stop working.
    $hadKeys = $dataGrid.IsKeyboardFocusWithin
    if ($results.View) { $results.View.Refresh() }
    if ($results.Searched -and -not $results.Failed -and -not $search.Current) { Set-ResultCount $results.Rows.Count }
    Update-EmptyState
    Update-MenuItem
    if ($hadKeys) { Set-GridFocus $dataGrid $(if ($dataGrid.CurrentItem) { $dataGrid.CurrentItem } else { $dataGrid.SelectedItem }) }
}

function Get-ShownCount {
    if ($results.View) { $results.View.Count } else { 0 }
}

function Update-ShownResult {
    # Shows the rows of the last search that match the filter box and the column filters.
    $results.Query = "$($filterBox.Text)".Trim().ToLowerInvariant()
    if ($results.Query -and $results.TextStale) { Update-AllRowText }
    if ($results.View) {
        $results.View.Filter = if ($results.Query -or $computerFilter.List.Count) { $rowFilter } else { $null }
    }
    Update-EmptyState
    Update-MenuItem
}

function Show-ResultRow([System.Collections.ObjectModel.ObservableCollection[object]]$Rows, [switch]$KeepFilters) {
    # Puts the rows of a new search in the grid, sorted like the previous ones: the grid forgets its sort when it gets
    # new rows. A new search clears the column filters; Tout afficher keeps them (KeepFilters).
    # With no sort chosen, the rows keep the search's own order (sorted in the background, Get-SearchSort), and its
    # column's header has the arrow. Only the arrow: a sort of the view would be kept as if it had been chosen.
    if (-not $KeepFilters -and $computerFilter.Active.Count) { Clear-ColumnFilter $computerFilter }
    $sorts = @($dataGrid.Items.SortDescriptions)
    $results.Rows = $Rows
    $dataGrid.ItemsSource = $Rows
    $results.View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Rows)
    foreach ($sort in $sorts) { $results.View.SortDescriptions.Add($sort) }
    $sortedBy = if ($sorts.Count) { $sorts[0].PropertyName } elseif ($results.LastSearch) { @($results.LastSearch['SortBy'])[0] }
    foreach ($column in $dataGrid.Columns) {
        # Not @(…)[0]: in strict mode, an empty array has no [0].
        $sort = $sorts | Where-Object PropertyName -eq $column.SortMemberPath | Select-Object -First 1
        $column.SortDirection = if ($sort) { $sort.Direction }
                                elseif (-not $sorts.Count -and $sortedBy -and $column.SortMemberPath -eq $sortedBy) { [System.ComponentModel.ListSortDirection]::Ascending }
                                else { $null }
    }
    Update-ShownResult
}

function Update-EmptyState {
    # The hint over the grid when it has no rows to show: why, and for a search that found nothing, what it looked for
    # and where, with the searches to try next (#193). Of the search shown, not one under way.
    $shownCount = Get-ShownCount
    $gridEmpty.Visibility = ConvertTo-Visibility ($shownCount -eq 0)
    $shown = $results.Shown
    $found = $results.Searched -and $shown -and -not ($results.Rows.Count -or $results.Failed -or $results.Need -or $shown['ForUser'])
    $gridEmptyText.Text = if ($results.Rows.Count) { Tr 'Aucun ordinateur ne correspond au filtre.' }
                          elseif ($results.Failed) { Tr 'La recherche a échoué : voir le message en bas.' }
                          elseif ($results.Need) { (Tr 'Aucun nom DNS pour {0}.') -f $results.Need.Address }
                          elseif ($results.Searched -and $shown -and $shown['ForUser']) { (Tr 'Aucun ordinateur dont la description contient « {0} ».') -f $shown.ForUser }
                          elseif ($found) {
                              # Where it looked: the domains that answered (one that didn't is named in the count).
                              $answered = @($results.Answered)
                              if ($answered.Count -gt 1 -and $answered.Count -eq @($shown.Domains).Count) { Tr 'Aucun ordinateur trouvé dans tous les domaines.' }
                              else { (Tr 'Aucun ordinateur trouvé dans {0}.') -f ($answered -join ', ') }
                          }
                          elseif ($results.Searched) { Tr 'Aucun ordinateur trouvé.' }
                          else { Tr "Entrez une partie d'un nom ou une description, puis Rechercher." }
    # What it looked for, as the recent searches say it, without the domain: the line above says where.
    $criteria = if ($found -and $shown.Entry) { @(Get-ComputerSearchPart $shown.Entry) -join ' · ' }
    $gridEmptyCriteria.Text = $criteria
    $gridEmptyCriteria.Visibility = ConvertTo-Visibility ([bool]$criteria)
    # The same search in every domain: when it ran in one of several, and not in an OU (of that domain only).
    $entry = if ($found) { $shown.Entry }
    $gridEmptyLinks.AllDomains.Visibility = ConvertTo-Visibility ([bool]$entry -and $showDomains -and $domainList.Count -gt 1 -and
                                                                  @($shown.Domains).Count -eq 1 -and $shown.Advanced.Scope -ne 'OU')
    # Without the Recherche avancée's criteria: when they narrowed it, and the boxes are enough to search on their own.
    $gridEmptyLinks.NoAdvanced.Visibility = ConvertTo-Visibility ([bool]$entry -and (Get-AdvancedSearchCount $shown.Advanced) -gt 0 -and
                                                                  ($entry.Prefix -or ($entry.Type -ne 'Sans description' -and $entry.Term)))
    # Rows the filter box or the column filters hide, every one.
    $gridEmptyLinks.ClearFilter.Visibility = ConvertTo-Visibility ($results.Rows.Count -gt 0 -and $shownCount -eq 0)
    # Exporter needs rows to save.
    $script:exportButton.IsEnabled = $shownCount -gt 0
}

function Search-EmptyAgain([switch]$AllDomains, [switch]$NoAdvanced) {
    # The search that found nothing, again: in every domain, or without its advanced criteria. The boxes are filled in
    # as it was (as a recent search is), so they say what's searched, whatever was typed since.
    $entry = $results.Shown.Entry
    if (-not $entry) { return }
    $again = [ordered]@{}
    foreach ($key in $entry.Keys) { $again[$key] = $entry[$key] }
    if ($AllDomains) { $again.Domain = 'Tous les domaines' }
    if ($NoAdvanced) { $again.Advanced = $null }
    Use-RecentSearch $again
}

function Clear-ResultFilter {
    # Effacer le filtre, when the filter box or the column filters hide every row: all of them shown again.
    if ($computerFilter) { Clear-ColumnFilter $computerFilter }
    $filterBox.Text = ''
    $script:filterTimer.Stop()
    Invoke-FilterChange
}

function Set-CountError([bool]$IsError) {
    # Errors in red; otherwise back to the style's muted color.
    if ($IsError) { $resultsCount.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.DangerText') }
    else { $resultsCount.ClearValue([System.Windows.Controls.TextBlock]::ForegroundProperty) }
}

function Set-ResultCount([int]$Count) {
    # French uses the singular for 0 and 1, English for 1 only.
    if ($Count -eq 1 -or ($Count -eq 0 -and (Get-TextCulture).TwoLetterISOLanguageName -eq 'fr')) {
        $text = (Tr '{0} ordinateur') -f $Count
    }
    else {
        $text = (Tr '{0} ordinateurs') -f $Count
    }
    $shown = Get-ShownCount
    if ($results.View -and $shown -ne $Count) {
        $text += ' · ' + $(if ($shown -le 1) { (Tr '{0} affiché') -f $shown } else { (Tr '{0} affichés') -f $shown })
    }
    # More found than the limit (SearchPage.ps1's Get-SearchLimitText): said in amber, and Tout afficher offered.
    $limited = Get-SearchLimitText $results.Truncated
    if ($limited) { $text += " · $limited" }
    # The domains that failed in the last search stay shown, in red with their errors in the tooltip.
    if ($results.ErrorText) {
        $text += " $(ConvertTo-FrenchError $results.ErrorText)"
        $resultsCount.ToolTip = ConvertTo-FrenchError $results.ErrorDetails
    }
    else {
        $resultsCount.ToolTip = $null
    }
    $resultsCount.Text = $text
    Set-CountError ([bool]$results.ErrorText)
    if ($limited -and -not $results.ErrorText) { $resultsCount.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.WarnText') }
    $script:showAllButton.Visibility = if ($limited) { 'Visible' } else { 'Collapsed' }
}

function Update-ComputerNotFound {
    # Liste de noms: the names no domain had, in the banner above the grid that Utilisateurs and Groupes have too
    # (SearchPage.ps1's Update-PageNotFound). When a domain didn't answer, a name may only be missing because of it:
    # the banner says which.
    Update-PageNotFound @{ Root = $script:root; Prefix = 'results'; NotFound = $script:results.NotFound; Unanswered = $script:results.Unanswered }
}

function Show-SearchTime($Watch, $Details) {
    # "en 1 234 ms" next to the count: the whole search, from the click to the rows shown. $Details, its tooltip: where
    # the time went (SearchPage.ps1's Get-SearchTimingTable: each domain's AD query and rows, then the grid).
    Set-SearchTimingTip $searchTime $Details
    $searchTime.Text = (Tr 'en {0} ms') -f $Watch.ElapsedMilliseconds.ToString('N0', (Get-TextCulture))
}

function Show-AddressNeed($Need) {
    # Adresse IP without a DNS name for the address: not an error, but what the search needs to look the address up
    # among the computers the name finds. Said under Nom contient…, which gets the focus, its text selected to refine.
    $text = if ($Need.Kind -eq 'NarrowerName') { (Tr 'Plus de 300 ordinateurs contiennent « {0} » : précisez le nom pour y chercher {1}') -f $Need.Prefix, $Need.Address }
            else { (Tr "Aucun nom DNS pour {0} : entrez une partie du nom, l'adresse sera cherchée parmi ces ordinateurs") -f $Need.Address }
    Show-SearchHint $script:searchHint $text $script:textBoxPrefix $script:searchField $script:textBoxPrefix
}

function Show-SearchError([string]$Text, [string]$Details) {
    # The search's error, in French when AD's message has a translation (ConvertTo-FrenchError).
    $resultsCount.Text = ConvertTo-FrenchError $Text
    $resultsCount.ToolTip = if ($Details) { ConvertTo-FrenchError $Details } else { $null }
    Set-CountError $true
}

# Searches one domain, in a background runspace. Returns what it found, or its error, as one object. SearchBase: the
# OU searched (with the OUs under it) instead of the whole domain. OUName: the OUs whose name starts so are searched
# instead (with theirs); NamedOUs are those OUs when already known, otherwise $null and they're looked up (and returned
# to be kept).
# Address: for « Adresse IP », the computer the DNS names for it (PTR). Without such a name, the computers the name's box
# finds are each looked up instead, keeping those whose name gives the address: slower, so only with a prefix, and 300
# computers at most. Without a prefix, or past 300, Need says what the name's box needs (Name, NarrowerName): the page
# asks for it under the box, as it isn't an error.
# KeyId: for « ID de clé BitLocker », the computers holding a recovery key whose ID starts so.
# The rows are built here too, sorted on SortBy (Get-SearchSort), with the row builder and PCSpecs.ps1 (Windows'
# releases), for Today and with the text the filter box searches (TextProperties).
$domainSearchScript = {
    param([string]$Domain, [string]$Filter, [string]$SearchBase, [string]$OUName, $NamedOUs, $CreatedBefore, [string]$Address, [string]$KeyId, [bool]$HasPrefix,
          [string]$RowBuilder, [string]$SpecsPath, [datetime]$Today, [string[]]$TextProperties, [int]$Limit, [string[]]$SortBy, $Clock)
    try {
        # Loaded once per runspace: they stay for its next searches. The row builder first: its Tr says the errors below.
        if (-not (Get-Command New-ResultRow -ErrorAction SilentlyContinue)) { . ([scriptblock]::Create($RowBuilder)) }
        if (-not (Get-Command Get-WindowsRelease -ErrorAction SilentlyContinue)) { . $SpecsPath }
        # The page's time limit counts from here, until AD answers: its first object, or the end of a query that found
        # none (New-SearchClock). The DNS isn't AD: its lookups, each with its own short wait, don't count as an answer.
        if ($Clock) { $Clock.Started = [datetime]::UtcNow }
        $heard = { process { if ($Clock -and -not $Clock.Answered) { $Clock.Answered = $true }; $_ } end { if ($Clock) { $Clock.Answered = $true } } }
        $hostNames = @()
        # Whether a DNS name gives the address searched.
        $hasAddress = {
            param($name)
            $records = if ($name) { @(try { Resolve-DnsName -Name $name -Type A_AAAA -QuickTimeout -ErrorAction Stop } catch { Write-Verbose "$name : $_" }) }
            @($records | Where-Object { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress -eq $Address }).Count -gt 0
        }
        if ($Address) {
            $hostNames = @(try {
                Resolve-DnsName -Name $Address -Type PTR -QuickTimeout -ErrorAction Stop |
                    Where-Object { $_.PSObject.Properties['NameHost'] -and $_.NameHost } | ForEach-Object { [string]$_.NameHost }
            }
            catch { Write-Verbose "Pas de nom DNS pour $Address : $_" })
            # A PTR record can be old (DHCP gave the address to another computer since): only a name that still gives
            # the address counts.
            $hostNames = @($hostNames | Where-Object { & $hasAddress $_ })
            $plainFilter = $Filter
            if ($hostNames.Count) {
                $Filter += " -and ($(@($hostNames | ForEach-Object { "dNSHostName -eq '$($_ -replace "'", "''")'" }) -join ' -or '))"
            }
            elseif (-not $HasPrefix) {
                # Not an error: the search needs a part of the name to look the address up among those computers, which
                # the page asks for under its box (Need).
                return [pscustomobject]@{ Domain = $Domain; NamedOUs = $NamedOUs; Rows = @(); Error = $null; Need = 'Name'; Truncated = $false; Timing = $null }
            }
        }
        if ($KeyId) {
            # A recovery key is an object under its computer, named "<date>{<key ID>}": those whose ID starts so, then
            # the computers above them (the key's DN without its own CN). No key: no computer, and no error.
            $keys = @(Get-ADObject -Server $Domain -LDAPFilter "(&(objectClass=msFVE-RecoveryInformation)(name=*{$KeyId*))" -ErrorAction Stop | & $heard)
            $owners = @($keys | ForEach-Object { $_.DistinguishedName -replace '^CN=(?:\\.|[^,\\])+,', '' } | Select-Object -Unique)
            if (-not $owners.Count) { return [pscustomobject]@{ Domain = $Domain; NamedOUs = $NamedOUs; Rows = @(); Error = $null; Truncated = $false; Timing = $null } }
            $Filter += " -and ($(@($owners | ForEach-Object { "DistinguishedName -eq '$($_ -replace "'", "''")'" }) -join ' -or '))"
        }
        # $Limit computers at most (none when 0), AD asked for one more to tell there are others. Without a DNS name for
        # the address, each computer found is looked up in the DNS, one query each: 300 at most, and a more precise name is
        # asked for beyond.
        $dnsEach = $Address -and -not $hostNames.Count
        $bounded = if ($dnsEach) { @{ ResultSetSize = 301 } } elseif ($Limit -gt 0) { @{ ResultSetSize = $Limit + 1 } } else { @{} }
        # AD can't filter on the DN, so an OU is searched from it (-SearchBase) instead of the whole domain.
        $bases = $null
        if ($SearchBase) { $bases = @($SearchBase) }
        elseif ($OUName) {
            # The OUs the name finds (and their sub-OUs). With none there are no results: never fall back to a
            # domain-wide search.
            if ($null -eq $NamedOUs) {
                $ouDNs = @(Get-ADOrganizationalUnit -Server $Domain -Filter "Name -like '$($OUName -replace "'", "''")*'" -ErrorAction Stop | & $heard | ForEach-Object DistinguishedName)
                # Skip OUs inside another one found: that OU's subtree search already covers them.
                $NamedOUs = @($ouDNs | Where-Object {
                    $dn = $_
                    -not ($ouDNs | Where-Object { $dn.EndsWith(",$_", [System.StringComparison]::OrdinalIgnoreCase) })
                })
            }
            $bases = $NamedOUs
        }
        # Only what the rows read. The first read of some properties (whenCreated, PrimaryGroupID) costs AD's module some
        # 20 ms per computer: a thousand computers' rows took 20 s with PrimaryGroupID. Whether a computer is a domain
        # controller is asked when an action needs it (Get-ComputerGuard); CreatedBefore is compared by AD itself, in the
        # filter, which reads the variable of that name here (Get-AdvancedSearchFilter).
        $properties = 'Description', 'DistinguishedName', 'LastLogonDate', 'OperatingSystem', 'OperatingSystemVersion'
        # How long AD took, then the rows: said in the search time's tooltip, for a search that's slow.
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $find = {
            param($With)
            if ($null -ne $bases) {
                foreach ($ou in $bases) { Get-ADComputer -Server $Domain -Filter $With -SearchBase $ou -Properties $properties @bounded -ErrorAction Stop | & $heard }
            }
            else { Get-ADComputer -Server $Domain -Filter $With -Properties $properties @bounded -ErrorAction Stop | & $heard }
        }
        $computers = & $find $Filter
        # The name the DNS gives isn't among the computers the name's box finds here (not in AD, or in another domain):
        # each of those is looked up, as without a name.
        if ($hostNames.Count -and $HasPrefix -and -not @($computers).Count) {
            $hostNames = @()
            $dnsEach = $true
            $bounded = @{ ResultSetSize = 301 }
            $computers = & $find $plainFilter
        }
        # (Several OUs: each was asked for one more, so together they can have more again.)
        $truncated = -not $dnsEach -and $Limit -gt 0 -and @($computers).Count -gt $Limit
        if ($truncated) { $computers = @($computers | Select-Object -First $Limit) }
        if ($dnsEach) {
            if (@($computers).Count -gt 300) {
                # The name is too broad to look each computer up: a more precise one is asked for, as above.
                return [pscustomobject]@{ Domain = $Domain; NamedOUs = $NamedOUs; Rows = @(); Error = $null; Need = 'NarrowerName'; Truncated = $false; Timing = $null }
            }
            $computers = @($computers | Where-Object { & $hasAddress $_.DNSHostName })
        }
        $queryTime = $watch.ElapsedMilliseconds
        $cache = @{}
        $rows = foreach ($computer in @($computers)) { New-ResultRow $computer $Domain $Today $TextProperties $cache }
        $rows = @($rows | Sort-Object $SortBy)
        [pscustomobject]@{
            Domain    = $Domain
            NamedOUs  = $NamedOUs
            Rows      = $rows
            Error     = $null
            Truncated = $truncated
            Timing    = @{ Query = $queryTime; Rows = $watch.ElapsedMilliseconds - $queryTime; Count = $rows.Count }
        }
    }
    catch {
        [pscustomobject]@{ Domain = $Domain; NamedOUs = $null; Rows = @(); Error = $_.Exception.Message; Truncated = $false; Timing = $null }
    }
}.ToString()

# The search under way ($null when none): its stopwatch, filter and domains, one job per domain (its PowerShell, the
# handle of its run, and whether it was cancelled), the results count as it was before (Before), and the changes made
# to rows while it ran (Changes, by DN), which its results get too. A timer follows the jobs from the window's thread.
# Stopping: cancelled jobs, disposed once they end. Dialogs: how many are open (the results wait for them to close).
# Script-scoped names below: event handlers run in the scope active when they fire (e.g. inside Show-Dialog).
$search = @{ Current = $null; Stopping = [System.Collections.Generic.List[object]]::new(); Dialogs = 0 }
$searchTimer = [System.Windows.Threading.DispatcherTimer]::new()
$searchTimer.Interval = [timespan]::FromMilliseconds(20)

function Set-Searching([bool]$Searching) {
    # Rechercher waits while a search runs; Annuler (or Échap) stops it.
    $script:searchButton.IsEnabled = -not $Searching
    $script:cancelSearchButton.Visibility = ConvertTo-Visibility $Searching
}

function Save-RowChange([string]$DistinguishedName, [string]$Property, $Value) {
    # A change made to a row while a search runs: the search may have read that computer before it.
    if ($script:search.Current) { $script:search.Current.Changes["$DistinguishedName|$Property"] = $Value }
}

function Invoke-Search([string]$ForUser) {
    # $ForUser: the user whose computers are searched for (Find-UserComputer), named when none is found.
    $searchTime.Text = ''
    Set-SearchTimingTip $searchTime $null
    Hide-SearchHint $searchHint

    $searchType    = Get-ListChoice $comboBoxSearch $searchChoices
    $noDescription = $searchType -eq 'Sans description'
    $byAddress     = $searchType -eq 'Adresse IP'
    $byKey         = $searchType -eq 'ID de clé BitLocker'
    $byList        = $searchType -eq 'Liste de noms'
    # Liste de noms leaves the name's box aside (it's disabled, and may still hold old text).
    $prefixText    = if ($byList) { '' } else { "$($textBoxPrefix.Text)" }
    # Trimmed once, so a pasted description with a stray space is searched as the recent search and the empty grid's
    # criteria show it: the filter, the saved entry and the sort all use this text.
    $termText      = "$($textBoxSearchTerm.Text)".Trim()
    $hasPrefix     = -not [string]::IsNullOrWhiteSpace($prefixText)
    $hasSearchTerm = -not [string]::IsNullOrWhiteSpace($termText)

    # What's missing is said under its box, which gets the focus: the second one for a list, an address or a key, the
    # name's for Sans description, and the whole field when either box will do.
    $missing = {
        param([string]$Text, $Box)
        Show-SearchHint $script:searchHint $Text $Box $script:searchField $(if ($Box) { $Box } else { $script:textBoxPrefix })
    }

    # Liste de noms: those names, whole, each once.
    $names = @()
    if ($byList) {
        $names = @(ConvertTo-ComputerNameList $termText)
        if (-not $names.Count) {
            & $missing (Tr 'Entrez les noms des ordinateurs (ex. ORD-01, ORD-04)') $textBoxSearchTerm
            return
        }
        if ($names.Count -gt $maxListNames) {
            & $missing ((Tr 'Au plus {0} noms à la fois ({1} entrés)') -f $maxListNames, $names.Count) $textBoxSearchTerm
            return
        }
    }
    # Adresse IP and ID de clé BitLocker search by what's in the second box, whatever else is filled in: that's what
    # they ask for first.
    # Adresse IP: a whole IPv4 or IPv6 address (ConvertTo-SearchAddress), written the way the DNS gives it back. Not a
    # subnet or a range: each computer would be looked up in the DNS, which a scan of the network looks like.
    $address = $null
    if ($byAddress) {
        $parsed = ConvertTo-SearchAddress $termText
        if (-not $parsed.Address) {
            $text = if ($parsed.Problem -eq 'Incomplete') { Tr "Entrez l'adresse entière, ses quatre nombres (ex. 10.0.1.14) : pas un sous-réseau ni une plage" }
                    else { Tr 'Entrez une adresse IP (ex. 10.0.1.14)' }
            & $missing $text $textBoxSearchTerm
            return
        }
        $address = $parsed.Address
    }
    # ID de clé BitLocker: the start of the ID BitLocker's recovery screen shows, 8 characters at least.
    $keyId = $null
    if ($byKey) {
        $keyId = ConvertTo-BitLockerKeyId $termText
        if (-not $keyId) {
            & $missing (Tr "Entrez au moins les 8 premiers caractères de l'ID de la clé (ex. 6F1C2E7A)") $textBoxSearchTerm
            return
        }
    }

    # The Recherche avancée's criteria, once they can be searched: said under its button.
    $advanced = $script:AdvancedSearch
    $problem = Get-AdvancedSearchProblem $advanced
    if ($problem) {
        Show-SearchHint $searchHint $problem $script:AdvancedSearchUi.Parts.Button
        return
    }
    $narrowed = (Get-AdvancedSearchCount $advanced) -gt 0

    # Without a name, the search would cover every computer in the domain. "Sans description"
    # needs the name itself, since its description box is disabled (and may still hold old text).
    # The advanced search's criteria narrow it down instead.
    if ($noDescription -and -not ($hasPrefix -or $narrowed)) {
        & $missing (Tr 'Entrez une partie du nom') $textBoxPrefix
        return
    }
    # The other types: the name or the description, either one.
    if (-not ($hasPrefix -or $hasSearchTerm -or $narrowed)) {
        & $missing (Tr 'Entrez une partie du nom ou une description') $null
        return
    }
    $script:BitLockerKeySought = $keyId

    # Double single quotes so input like "d'accueil" doesn't break the AD filter.
    $prefix     = $prefixText.Trim() -replace "'", "''"
    $searchTerm = Get-ADFilterText $termText

    # The name's box: that text anywhere in the name. The other box narrows it down, so both have to match.
    $filter = if ($hasPrefix) { "Name -like '*$prefix*'" } else { "Name -like '*'" }
    if ($noDescription) {
        $filter += " -and -not (Description -like '*')"
    }
    elseif ($byList) {
        $filter += ' -and (' + (@($names | ForEach-Object { "Name -eq '$($_ -replace "'", "''")'" }) -join ' -or ') + ')'
    }
    elseif ($byAddress -or $byKey) {
        # Not on the description: each domain's search looks the address (Address) or the key (KeyId) up itself, in the
        # background.
    }
    elseif ($hasSearchTerm) {
        $descFilterPart = switch ($searchType) {
            'Description commence par' { "$searchTerm*" }
            'Description termine par'  { "*$searchTerm" }
            default                    { "*$searchTerm*" }
        }
        $filter += " -and Description -like '$descFilterPart'"
    }
    # Otherwise filter on the name only, so computers without a description are included.
    # Then the advanced search's Compte, Système and Dernière connexion.
    $criteria = Get-AdvancedSearchFilter $advanced (Get-Date)
    $filter += $criteria.Filter

    # Each domain is searched on its own (-Server), so one that can't be reached doesn't hide the others' results. An
    # OU chosen is searched in its domain only.
    $selectedDomain = if ($showDomains) { Get-ListChoice $comboBoxDomain $domainChoices } else { $defaultDomain }
    [string[]]$searchedDomains = @(if ($advanced.Scope -eq 'OU') { $advanced.OUDomain }
                                   elseif ($selectedDomain -eq 'Tous les domaines') { $domainList } else { $selectedDomain })

    # One search at a time: this one replaces the one under way (a recent search, Avancée's Rechercher).
    if ($script:search.Current) { Stop-Search }

    # Kept with what this search type uses only: a description left in its disabled box isn't part of it.
    $entry = [ordered]@{
        Domain = $selectedDomain; Type = $searchType; Prefix = $prefixText.Trim()
        Term = if ($noDescription) { '' } else { $termText }
        Advanced = ConvertTo-SavedAdvancedSearch $advanced
    }
    Add-RecentSearch $entry

    Start-ComputerSearch @{
        Filter = $filter; Domains = $searchedDomains; CreatedBefore = $criteria.CreatedBefore
        SearchBase = if ($advanced.Scope -eq 'OU') { $advanced.OU } else { '' }; OUName = if ($advanced.Scope -eq 'OUName') { $advanced.OUName } else { '' }
        Advanced = $advanced.Clone(); Address = $address; KeyId = $keyId; HasPrefix = $hasPrefix; Prefix = $prefixText.Trim(); Limit = $script:SearchLimit
        Names = $names; ForUser = $ForUser; Entry = $entry
        SortBy = Get-SearchSort $(if (-not ($noDescription -or $byList -or $byAddress -or $byKey) -and $hasSearchTerm) { $termText })
    }
}

function Get-SearchSort([string]$Description) {
    # The order a search's rows come in: by description when one was searched for, since that's what was looked
    # for, otherwise by name, as on Utilisateurs and Groupes. Then by name and domain, so the same name in two domains
    # keeps one order. The grid's arrow shows the first (Show-ResultRow).
    if ($Description) { 'Description', 'ComputerName', 'Domain' } else { 'ComputerName', 'Domain' }
}

function Find-UserComputer([string]$Name) {
    # Ordinateurs de l'utilisateur: the computers whose description holds a user's name, in every domain, as a search of
    # the page (kept in the recent searches, filterable, exportable). From AD only: no computer is asked who's signed in
    # (Utilisateurs connectés… does that, for the computers selected). The page's other criteria are cleared, so none
    # hides one of them.
    if ($script:search.Current) { Stop-Search }
    Show-Page 'computers'
    if ($showDomains) { $null = Select-ListChoice $comboBoxDomain $domainChoices 'Tous les domaines' }
    $null = Select-ListChoice $comboBoxSearch $searchChoices 'Description contient'
    Set-AdvancedSearch (New-AdvancedSearch)
    $textBoxPrefix.Text = ''
    $textBoxSearchTerm.Text = $Name
    $filterBox.Text = ''
    Invoke-Search -ForUser $Name
}

function Show-AllResult {
    # Tout afficher: the search whose rows are shown again, as it was asked, without the limit.
    $last = $script:results.LastSearch
    if ($script:search.Current -or -not $last) { return }
    $request = $last.Clone()
    $request.Limit = 0
    # The same search: the column filters stay.
    $request.KeepFilters = $true
    Start-ComputerSearch $request
}

function Get-ComputerSearchControl { $textBoxPrefix, $textBoxSearchTerm, $script:searchButton }

function Start-ComputerSearch($Request) {
    # A search as asked ($Request: Filter, Domains, SearchBase, OUName, CreatedBefore, Advanced, Address, KeyId, HasPrefix, Prefix, Limit), one job
    # per domain; Update-Search shows the rows once all have answered. The previous rows stay until the new ones are ready.
    # The request becomes the last search only once a domain has answered (Complete-Search).
    $script:showAllButton.Visibility = 'Collapsed'
    $search.Current = $Request.Clone()
    $search.Current.Request = $Request
    $search.Current.Watch = [System.Diagnostics.Stopwatch]::StartNew()
    $search.Current.Typed = Get-TypedSearch (Get-ComputerSearchControl)
    $search.Current.Jobs = @()
    $search.Current.Changes = @{}
    $search.Current.Today = (Get-Date).Date
    $search.Current.TextProperties = @(Get-TextProperty)
    $search.Current.Before = @{
        Text = $resultsCount.Text; ToolTip = $resultsCount.ToolTip
        IsError = $resultsCount.ReadLocalValue([System.Windows.Controls.TextBlock]::ForegroundProperty) -ne [System.Windows.DependencyProperty]::UnsetValue
    }
    $resultsCount.Text = Tr 'Recherche…'
    $resultsCount.ToolTip = $null
    Set-CountError $false
    $root.FindName('results_not_found').Visibility = 'Collapsed'
    Set-Searching $true
    Start-DomainSearch
    $searchTimer.Start()
}

function Start-DomainSearch {
    # One job per domain, once the runspaces are ready (they may still be loading the AD module right after start).
    $current = $script:search.Current
    if ($current.Jobs.Count -or $script:searchPool.RunspacePoolStateInfo.State -ne 'Opened') { return }
    $current.Jobs = @(foreach ($domain in $current.Domains) {
        $shell = [powershell]::Create()
        $shell.RunspacePool = $script:searchPool
        $knownOUs = if ($current.OUName -and $script:namedOUs.ContainsKey("$domain|$($current.OUName)")) { , $script:namedOUs["$domain|$($current.OUName)"] } else { $null }
        $clock = New-SearchClock
        $null = $shell.AddScript($script:domainSearchScript).AddParameters(@{
            Domain = $domain; Filter = $current.Filter; SearchBase = $current.SearchBase; OUName = $current.OUName; NamedOUs = $knownOUs; CreatedBefore = $current.CreatedBefore
            Address = $current.Address; KeyId = $current.KeyId; HasPrefix = $current.HasPrefix
            RowBuilder = $script:rowBuilderScript; SpecsPath = $script:SpecsCollectorPath; Today = $current.Today; TextProperties = $current.TextProperties
            Limit = $current.Limit; SortBy = $current.SortBy; Clock = $clock
        })
        @{ Domain = $domain; Shell = $shell; Handle = $shell.BeginInvoke(); Cancelled = $false; TimedOut = $false; Clock = $clock }
    })
}

function Remove-StoppedJob {
    # Cancelled jobs are disposed once their query has ended.
    foreach ($job in @($script:search.Stopping)) {
        if ($job.Handle.IsCompleted) {
            $job.Shell.Dispose()
            $script:search.Stopping.Remove($job) | Out-Null
        }
    }
}

function Update-Search {
    # On each tick of the timer: starts the jobs when the runspaces are ready, names the domains still searched after a
    # second, and shows the results once every domain has answered and no dialog is open.
    Remove-StoppedJob
    $current = $script:search.Current
    if (-not $current) { $script:searchTimer.Stop(); return }
    if ($script:searchPool.RunspacePoolStateInfo.State -eq 'Broken') {
        $script:searchTimer.Stop()
        $script:search.Current = $null
        Set-Searching $false
        Show-SearchError ((Tr 'Erreur: recherche impossible ({0})') -f $script:searchPool.RunspacePoolStateInfo.Reason.Message)
        return
    }
    Start-DomainSearch
    if (-not $current.Jobs.Count) { return }
    # A domain that hasn't answered in time is stopped: the others' rows don't wait for it.
    Stop-SilentSearch $current.Jobs
    $pending = @($current.Jobs | Where-Object { -not $_.Handle.IsCompleted -and -not $_.TimedOut })
    if ($pending.Count) {
        if ($current.Watch.ElapsedMilliseconds -ge 1000) {
            $script:resultsCount.Text = (Tr 'Recherche… (en attente : {0})') -f (@($pending | ForEach-Object { $_.Domain }) -join ', ')
        }
        return
    }
    # Every domain answered: the search time stops here. A dialog acts on the rows shown: they're replaced once it's
    # closed.
    $current.Watch.Stop()
    if ($script:search.Dialogs -gt 0) {
        $script:resultsCount.Text = Tr 'Recherche…'
        return
    }
    Complete-Search
}

function Stop-Search {
    # Annuler: the domains that haven't answered are stopped; those that have are shown.
    $current = $script:search.Current
    if (-not $current) { return }
    foreach ($job in $current.Jobs) {
        if (-not $job.Handle.IsCompleted -and -not $job.TimedOut) {
            $job.Cancelled = $true
            # Not waited for: a query stuck on an unreachable DC may only end on its own. The pool has spare runspaces
            # for the next searches meanwhile.
            $null = $job.Shell.BeginStop($null, $null)
            $script:search.Stopping.Add($job)
        }
    }
    Complete-Search
}

function Restore-ResultCount($Before) {
    # Back to the count (or message) shown before the search.
    if ($script:results.Searched -and -not $script:results.Failed) {
        Set-ResultCount $script:results.Rows.Count
        Update-ComputerNotFound
        return
    }
    $script:resultsCount.Text = $Before.Text
    $script:resultsCount.ToolTip = $Before.ToolTip
    Set-CountError $Before.IsError
}

$script:OnlineForLoneResult = $false
function Show-SearchResult($Typed) {
    # A search that found one computer found the one sought, so whether it's online shows in its row. En ligne, if this is
    # what showed it, goes with the lone result: it would stay for the rest of the session, empty and wide, without anyone
    # having asked for it. The keys last (Set-ResultFocus): changing the columns would lose them.
    if ((Get-ShownCount) -eq 1) {
        if (-not $gridColumns.Shown['Online']) { $script:OnlineForLoneResult = $true }
        Start-OnlineCheck @($dataGrid.Items[0]) -Quiet
    }
    elseif ($script:OnlineForLoneResult) {
        $script:OnlineForLoneResult = $false
        $gridColumns.Shown['Online'] = $false
        Update-ColumnVisibility
    }
    Set-ResultFocus $dataGrid (Get-ComputerSearchControl) $Typed
}

function Complete-Search {
    $current = $script:search.Current
    $script:searchTimer.Stop()
    $script:search.Current = $null
    Set-Searching $false

    $found = [System.Collections.Generic.List[object]]::new()
    # Each domain's AD query and rows, by domain, for the search time's tooltip.
    $timings = [ordered]@{}
    $errors = [ordered]@{}
    $cancelled = [System.Collections.Generic.List[string]]::new()
    $truncated = [System.Collections.Generic.List[string]]::new()
    # Adresse IP: the domains that need (more of) the name to look the address up, rather than an error.
    $needs = [System.Collections.Generic.List[string]]::new()
    # The domains stopped as they didn't answer in time (Stop-SilentSearch): an error, named apart.
    $timedOut = [System.Collections.Generic.List[string]]::new()
    foreach ($job in $current.Jobs) {
        if ($job.TimedOut) {
            $errors[$job.Domain] = Get-SearchTimeoutText
            $timedOut.Add($job.Domain)
            continue
        }
        if ($job.Cancelled) {
            $cancelled.Add($job.Domain)
            continue
        }
        try {
            $answer = @($job.Shell.EndInvoke($job.Handle))[0]
        }
        catch {
            $answer = [pscustomobject]@{ Domain = $job.Domain; NamedOUs = $null; Rows = @(); Error = $_.Exception.Message; Truncated = $false }
        }
        finally {
            $job.Shell.Dispose()
        }
        if ($answer.Error) {
            Write-Host ((Tr 'Erreur de recherche AD ({0}) : {1}') -f $job.Domain, $answer.Error)
            $errors[$job.Domain] = $answer.Error
            continue
        }
        if ($current.OUName -and $null -ne $answer.NamedOUs) { $script:namedOUs["$($job.Domain)|$($current.OUName)"] = @($answer.NamedOUs) }
        if ($answer.Truncated) { $truncated.Add($job.Domain) }
        if ($answer.PSObject.Properties['Need'] -and $answer.Need) { $needs.Add($answer.Need) }
        if ($answer.PSObject.Properties['Timing'] -and $answer.Timing) { $timings[$job.Domain] = $answer.Timing }
        $found.Add($answer.Rows)
    }

    # What was changed from the window during the search wins over what the search read (rarely anything).
    if ($current.Changes.Count) {
        foreach ($domainRows in @($found)) {
            foreach ($row in @($domainRows)) {
                $dn = $row.DistinguishedName
                if ($current.Changes.ContainsKey("$dn|Removed")) { $row | Add-Member Removed $true -Force; continue }
                # Moved during the search: the changes made after the move are kept under its new DN.
                if ($current.Changes.ContainsKey("$dn|DistinguishedName")) {
                    $dn = $current.Changes["$dn|DistinguishedName"]
                    Set-RowLocation $row $dn
                    if ($current.Changes.ContainsKey("$dn|Removed")) { $row | Add-Member Removed $true -Force; continue }
                }
                if ($current.Changes.ContainsKey("$dn|Description")) { Set-RowDescription $row $current.Changes["$dn|Description"] }
                if ($current.Changes.ContainsKey("$dn|Enabled")) { Set-RowState $row ([bool]$current.Changes["$dn|Enabled"]) }
            }
        }
    }

    # No domain answered: cancelled before any did (or before the runspaces were ready), so the previous results stay,
    # and with them the search Tout afficher runs again.
    $succeeded = $current.Jobs.Count - $cancelled.Count - $errors.Count
    if ($succeeded -le 0 -and -not $errors.Count) {
        Restore-ResultCount $current.Before
        $script:searchTime.Text = Tr 'recherche annulée'
        return
    }

    # If anything unexpected fails, show an empty grid and the error rather than the previous rows.
    try {
        $searchedDomains = $current.Domains
        $script:results.Searched = $true
        $script:results.Shown = $current
        $script:results.LastSearch = $current.Request
        $script:results.Answered = @($current.Domains | Where-Object { -not $errors.Contains($_) -and -not $cancelled.Contains($_) })
        $script:results.Failed = $false
        $script:results.ErrorText = ''
        $script:results.ErrorDetails = ''
        $script:results.NotFound = @()
        $script:results.Unanswered = @()
        $script:results.Need = $null
        $script:results.Truncated = @{ Domains = @($truncated); Limit = $current.Limit; MultiDomain = $current.Domains.Count -gt 1 }
        $script:results.Today = $current.Today
        $script:resultsScope.Text = if ($searchedDomains.Count -gt 1) { (Tr 'dans {0} domaines') -f $searchedDomains.Count } else { (Tr 'dans {0}') -f $searchedDomains[0] }
        # The criteria searched: an OU chosen already says its domain in « dans ».
        foreach ($part in @(Format-AdvancedSearch $current.Advanced)) { $script:resultsScope.Text += ", $part" }
        if ($current.Address) { $script:resultsScope.Text += ', ' + ((Tr 'adresse {0}') -f $current.Address) }
        if (@($current.Names).Count) { $script:resultsScope.Text += ', ' + ((Tr 'liste de noms ({0})') -f @($current.Names).Count) }
        $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $details = @(@($errors.Keys | ForEach-Object { (Tr '{0} : {1}') -f $_, $errors[$_] }) + @($cancelled | ForEach-Object { (Tr '{0} : recherche annulée') -f $_ })) -join "`n"

        # Every domain that answered failed (the others were cancelled): the search failed.
        if ($succeeded -le 0) {
            $script:results.Failed = $true
            Show-ResultRow $rows
            Update-ComputerNotFound
            $message = if ($errors.Count -eq 1) { (Tr 'Erreur: {0}') -f @($errors.Values)[0] } else { Tr 'Erreur dans tous les domaines' }
            if ($cancelled.Count) { $message += ' ' + ((Tr '(annulé : {0})') -f ($cancelled -join ', ')) }
            Show-SearchError $message $(if ($errors.Count -gt 1 -or $cancelled.Count) { $details })
            Show-SearchTime $current.Watch
            return
        }

        # Some domains answered, others failed or were cancelled: show what was found and say which ones are missing.
        $missing = @()
        $failed = @($errors.Keys | Where-Object { -not $timedOut.Contains($_) })
        if ($failed.Count) { $missing += (Tr 'erreur : {0}') -f ($failed -join ', ') }
        if ($timedOut.Count) { $missing += (Tr 'sans réponse : {0}') -f ($timedOut -join ', ') }
        if ($cancelled.Count) { $missing += (Tr 'annulé : {0}') -f ($cancelled -join ', ') }
        if ($missing.Count) {
            $script:results.ErrorText = "($($missing -join (Tr ' ; ')))"
            $script:results.ErrorDetails = $details
        }
        # Each domain's rows come sorted (SortBy); several domains' are sorted together. The rows removed during the
        # search are left out (only looked for when something changed meanwhile).
        # @(): an empty result stays an empty list rather than becoming $null.
        $all = @(if ($found.Count -eq 1 -and -not $current.Changes.Count) { $found[0] }
                 else { foreach ($domainRows in $found) { foreach ($row in $domainRows) { if (-not $row.PSObject.Properties['Removed']) { $row } } } })
        if ($found.Count -gt 1) { $all = @($all | Sort-Object $current.SortBy) }
        # All at once: adding thousands of rows one by one takes a while.
        $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new([object[]]$all)
        # The columns shown changed during the search: the filter box searches the new ones.
        $script:results.TextStale = (@(Get-TextProperty) -join ',') -ne ($current.TextProperties -join ',')
        # Liste de noms: the names no domain had, in the order they were given.
        $foundNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($all | ForEach-Object { [string]$_.ComputerName }), [System.StringComparer]::OrdinalIgnoreCase)
        $script:results.NotFound = @($current.Names | Where-Object { -not $foundNames.Contains($_) })
        $script:results.Unanswered = @(@($errors.Keys) + @($cancelled))
        # Adresse IP without a DNS name: when no domain found the computer and one needs the name, it's asked for under
        # its box. A domain that found it is the answer: nothing is asked then. (A search has a name or not, so its
        # domains need the same thing.)
        if ($needs.Count -and -not $all.Count) { $script:results.Need = @{ Kind = $needs[0]; Address = $current.Address; Prefix = $current.Prefix } }
        $shownIn = [System.Diagnostics.Stopwatch]::StartNew()
        Show-ResultRow $rows -KeepFilters:([bool]$current['KeepFilters'])
        Set-ResultCount $rows.Count
        Update-ComputerNotFound
        $table = Get-SearchTimingTable $timings $shownIn.ElapsedMilliseconds
        Show-SearchResult $current.Typed
        Show-SearchTime $current.Watch $table
        if ($script:results.Need) { Show-AddressNeed $script:results.Need }
    }
    catch {
        Write-Host ((Tr 'Erreur de recherche : {0}') -f $_)
        $script:results.Failed = $true
        $script:results.NotFound = @()
        Show-ResultRow ([System.Collections.ObjectModel.ObservableCollection[object]]::new())
        Update-ComputerNotFound
        Show-SearchError ((Tr 'Erreur: {0}') -f $_.Exception.Message)
        Show-SearchTime $current.Watch
    }
}

$searchTimer.Add_Tick({ Update-Search })
$searchButton.Add_Click({ Invoke-Search })
$cancelSearchButton.Add_Click({ Stop-Search })

# A search still running when the window closes is stopped with it. The runspaces aren't waited for: a query stuck on
# an unreachable DC would keep the process alive, and they end with it.
$win.Add_Closed({
    if ($script:search.Current) { Stop-Search }
})

function Invoke-FilterChange {
    Update-ShownResult
    # During a search, the count says « Recherche… » until it ends.
    if ($results.Searched -and $results.Rows.Count -and -not $search.Current) { Set-ResultCount $results.Rows.Count }
}
# Each filter redraws the grid, about 0.15 s with thousands of rows: then it waits for a pause in the typing, so a word
# typed quickly costs one redraw rather than one per letter. Smaller results follow each key at once.
$filterTimer = [System.Windows.Threading.DispatcherTimer]::new()
$filterTimer.Interval = [timespan]::FromMilliseconds(200)
$filterTimer.Add_Tick({
    $script:filterTimer.Stop()
    Invoke-FilterChange
})
$filterBox.Add_TextChanged({
    $script:filterTimer.Stop()
    if ($results.Rows.Count -ge 1000) { $script:filterTimer.Start() } else { Invoke-FilterChange }
})

# The grid's columns: shown or hidden (Colonnes, or a right-click on a column header), moved by dragging their header,
# resized, and kept that way in apparence.json. Each column's key is its SortMemberPath. Nom is always shown, and
# Domaine only when there's more than one domain. Shown: the user's choice for each column. Default: the layout before
# any change, for Réinitialiser. Loaded: the layout at start, so it's only saved when it changed.
$gridColumns = @{ ByKey = [ordered]@{}; Shown = @{}; Items = @{}; Default = $null; Loaded = ''; Updating = $false; Menu = [System.Windows.Controls.ContextMenu]::new() }
foreach ($column in $dataGrid.Columns) {
    $gridColumns.ByKey[$column.SortMemberPath] = $column
    $gridColumns.Shown[$column.SortMemberPath] = $column.SortMemberPath -ne 'Online'
}

function Get-ColumnLayout {
    # En ligne is saved hidden: it only has something to show after Vérifier en ligne.
    @(foreach ($key in $gridColumns.ByKey.Keys) {
        $column = $gridColumns.ByKey[$key]
        $width = Get-SavedColumnWidth $column
        [ordered]@{ Key = $key; Visible = [bool]$gridColumns.Shown[$key] -and $key -ne 'Online'; Width = $width.Width; Unit = $width.Unit; Index = $column.DisplayIndex }
    })
}
# A column resized keeps its width (SearchPage.ps1).
Register-ColumnResize $dataGrid

function Update-ColumnVisibility {
    # Shows the columns chosen, ticks them in the menu, then filters the rows again: the filter box searches the
    # visible columns only.
    $gridColumns.Updating = $true
    try {
        foreach ($key in $gridColumns.ByKey.Keys) {
            $shown = $key -eq 'ComputerName' -or ($gridColumns.Shown[$key] -and ($key -ne 'Domain' -or $showDomains))
            $gridColumns.ByKey[$key].Visibility = ConvertTo-Visibility $shown
            if ($gridColumns.Items.Contains($key)) { $gridColumns.Items[$key].IsChecked = [bool]$gridColumns.Shown[$key] }
        }
    }
    finally { $gridColumns.Updating = $false }
    # A filtered column now hidden is no longer filtered.
    $unfiltered = Sync-ColumnFilter $computerFilter
    # The rows' text, which the filter box searches: rebuilt now when something is filtered (thousands of rows take a
    # moment), otherwise when the filter box next needs it.
    if ($results.Query) {
        Update-AllRowText
        if ($results.View) { $results.View.Refresh() }
    }
    else { $results.TextStale = $true }
    if ($unfiltered) { Update-ShownResult }
    Update-EmptyState
    if ($results.Searched -and $results.Rows.Count -and -not $search.Current) { Set-ResultCount $results.Rows.Count }
}

function Set-ColumnLayout($Layout) {
    # A saved layout: the order first (the columns it doesn't know, from a later version, keep their default place after
    # the others), then each column's visibility and width. Values that don't make sense are left out.
    $known = @($Layout | Where-Object { $_ -and $gridColumns.ByKey.Contains([string]$_.Key) } | Sort-Object { [int]$_.Index })
    $knownKeys = @($known | ForEach-Object { [string]$_.Key })
    $order = @($knownKeys) + @($gridColumns.ByKey.Keys | Where-Object { $_ -notin $knownKeys })
    for ($i = 0; $i -lt $order.Count; $i++) { $gridColumns.ByKey[$order[$i]].DisplayIndex = $i }
    foreach ($entry in $known) {
        $key = [string]$entry.Key
        if ($key -ne 'ComputerName') { $gridColumns.Shown[$key] = [bool]$entry.Visible }
        $width = 0.0
        if ([double]::TryParse("$($entry.Width)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$width)) {
            if ($entry.Unit -eq 'Pixel' -and $width -ge 30) { $gridColumns.ByKey[$key].Width = [System.Windows.Controls.DataGridLength]::new($width, 'Pixel') }
            elseif ($entry.Unit -eq 'Star' -and $width -gt 0) { $gridColumns.ByKey[$key].Width = [System.Windows.Controls.DataGridLength]::new($width, 'Star') }
        }
    }
    Update-ColumnVisibility
}

# The menu: a ticked item per column that can be hidden, then Réinitialiser. It stays open while columns are ticked.
foreach ($key in $gridColumns.ByKey.Keys) {
    if ($key -eq 'ComputerName' -or ($key -eq 'Domain' -and -not $showDomains)) { continue }
    $item = [System.Windows.Controls.MenuItem]::new()
    $item.Header = [string]$gridColumns.ByKey[$key].Header
    $item.Name = "column_$key"
    $item.Tag = $key
    $item.IsCheckable = $true
    $item.StaysOpenOnClick = $true
    # Ticked or unticked by a click or a screen reader. Not when Update-ColumnVisibility ticks it.
    $toggled = {
        param($item)
        if ($script:gridColumns.Updating) { return }
        $script:gridColumns.Shown[$item.Tag] = $item.IsChecked
        Update-ColumnVisibility
    }
    $item.Add_Checked($toggled)
    $item.Add_Unchecked($toggled)
    $gridColumns.Items[$key] = $item
    $gridColumns.Menu.Items.Add($item) | Out-Null
}
$gridColumns.Menu.Items.Add([System.Windows.Controls.Separator]::new()) | Out-Null
$resetColumns = [System.Windows.Controls.MenuItem]::new()
$resetColumns.Header = Tr 'Réinitialiser les colonnes'
$resetColumns.Name = 'column_reset'
$resetColumns.Add_Click({ Set-ColumnLayout $script:gridColumns.Default })
$gridColumns.Menu.Items.Add($resetColumns) | Out-Null

# The same menu on every column header (a header with its own style gets it too) and on the Colonnes button.
$headerStyle = [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader], $dataGrid.ColumnHeaderStyle)
$headerStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.FrameworkElement]::ContextMenuProperty, $gridColumns.Menu))
$dataGrid.ColumnHeaderStyle = $headerStyle
foreach ($column in $dataGrid.Columns) {
    if ($column.HeaderStyle) {
        $style = [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader], $column.HeaderStyle)
        $style.Setters.Add([System.Windows.Setter]::new([System.Windows.FrameworkElement]::ContextMenuProperty, $gridColumns.Menu))
        $column.HeaderStyle = $style
    }
}
$columnsButton = $root.FindName('columns')
$columnsButton.ContextMenu = $gridColumns.Menu
$columnsButton.Add_Click({ Open-ButtonMenu $columnsButton })
# Opened from the button, the menu is placed under it: once closed, it goes back to opening where it's right-clicked.
$gridColumns.Menu.Add_Closed({
    param($menu)
    $menu.ClearValue([System.Windows.Controls.ContextMenu]::PlacementTargetProperty)
    $menu.ClearValue([System.Windows.Controls.ContextMenu]::PlacementProperty)
})

# The column filters: each column's values as the grid shows them (Compte's « Activé », Système's short name,
# Emplacement's path), Nom's by the text it contains, Dernière connexion's by how long ago, En ligne's once checked.
$computerFilter = Initialize-ColumnFilter -Grid $dataGrid -Prefix '' -Toggle $root.FindName('column_filters') -Menu $gridColumns.Menu -Setting 'Computers' `
    -Holder $results -QueryKey 'Query' -OnChange { Invoke-FilterChange } -Specs @{
        Disabled     = @{ Empty = (Tr 'Activé') }
        ComputerName = @{ Mode = 'Text' }
        Description  = @{ Empty = (Tr 'Aucune description') }
        LastLogon    = @{ Mode = 'Age' }
        OSBuild      = @{ Property = 'OSShort'; Empty = (Tr 'Inconnu') }
        ShortPath    = @{ Property = 'OUPath' }
        Online       = @{ Property = 'OnlineLabel'; Empty = (Tr 'Non vérifié') }
    }
$rowFilter = New-RowFilter $computerFilter

$gridColumns.Default = Get-ColumnLayout
if ($script:Appearance.Columns) {
    try { Set-ColumnLayout $script:Appearance.Columns }
    catch {
        # A hand-edited settings file shouldn't keep Repère from starting.
        Write-Host ((Tr 'Colonnes ignorées : {0}') -f $_)
        Set-ColumnLayout $gridColumns.Default
    }
}
else {
    Update-ColumnVisibility
}
# Taken once the grid is shown, when its columns have their final order.
$win.Add_ContentRendered({ if (-not $script:gridColumns.Loaded) { $script:gridColumns.Loaded = Get-ColumnLayout | ConvertTo-Json -Compress } })

# Saved when Repère closes, only if the columns changed since it started (moved, resized, shown or hidden).
$win.Add_Closing({
    $layout = Get-ColumnLayout
    if ($script:gridColumns.Loaded -and ($layout | ConvertTo-Json -Compress) -ne $script:gridColumns.Loaded) {
        $script:Appearance.Columns = $layout
        Save-Appearance
    }
})

function Get-ComputerExportField($Columns) {
    # The grid's columns as Exporter writes them and Copier les lignes copies them (Get-ExportField): those shown, in
    # their order, under their headers. A column writes the property it sorts by, except where the grid shows less:
    # - Compte, an icon: Activé or Désactivé, the words screen readers read.
    # - Système, a short name (Win 11 24H2): it, then the whole value of its tooltip (Version de Windows), whose build
    #   a spreadsheet sorts and counts the updates by.
    # - Emplacement, the OU path it shows (Postes › Communs), its domain being in Domaine and the distinguished name.
    # - En ligne, a badge and an address: in two columns, the answer (En ligne, Hors ligne) to filter by and the
    #   address to sort by; empty for a computer Vérifier en ligne hasn't checked.
    # Dernière connexion writes its sort key, the date as yyyy-MM-dd HH:mm, rather than the age shown (« il y a 3
    # mois » is only true today): Excel reads it as a date whatever its language, and it sorts as text too.
    # The distinguished name last, always: what tells two computers apart, and says their domain and OU, with Domaine
    # and Emplacement hidden.
    $enabled = Tr 'Activé'
    $fields = @{
        Disabled  = @{ Value = { param($Row) if ($Row.Disabled) { $Row.Disabled } else { $enabled } }.GetNewClosure() }
        OSBuild   = @{ Value = 'OSShort' }, @{ Header = (Tr 'Version de Windows'); Value = 'OSFull' }
        ShortPath = @{ Value = 'OUPath' }
        Online    = @{ Value = 'OnlineLabel' }, @{ Header = (Tr 'Adresse IP'); Value = 'OnlineAddress' }
    }
    Get-ExportField $Columns $fields @(@{ Header = (Tr 'Nom distinctif'); Value = 'DistinguishedName' })
}

function Get-ComputerExportRow($Rows) {
    # The rows as Exporter writes them, a property per column (Get-ComputerExportField).
    ConvertTo-ExportRow $Rows (Get-ComputerExportField $dataGrid.Columns)
}

function Get-ComputerExportName([datetime]$Date) {
    # The file name Exporter proposes: the domain of the search whose rows are shown, or none for several (not the list's
    # « Tous les domaines », nor the domain chosen there since). The date in the Gregorian calendar whatever the culture's
    # (-f would write 2569 in th-TH), so exports sort by name.
    $searched = @(if ($results.LastSearch) { $results.LastSearch.Domains })
    $scope = if ($searched.Count -eq 1) { '_' + ([string]$searched[0] -replace '[^\w\.\-]+', '-').ToLowerInvariant() } else { '' }
    [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, (Tr 'Repere_ordinateurs{0}_{1:yyyy-MM-dd}.csv'), $scope, $Date)
}

function Export-ShownRow {
    # Exporter: the rows shown (after the filter, in the grid's order) and the columns shown (Get-ComputerExportField)
    # as CSV, ready for French Excel: UTF-8 with a BOM so the accents show, and the culture's list separator (« ; » in
    # French).
    # $env:REPERE_EXPORT_PATH, for the UI tests, saves there without asking.
    $rows = @(if ($results.View) { foreach ($row in $results.View) { $row } })
    if (-not $rows.Count) { return }
    $path = $env:REPERE_EXPORT_PATH
    if (-not $path) {
        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Title = Tr 'Exporter les ordinateurs'
        $dialog.Filter = Tr 'Fichiers CSV (*.csv)|*.csv'
        $dialog.FileName = Get-ComputerExportName (Get-Date)
        $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if (-not $dialog.ShowDialog($win)) { return }
        $path = $dialog.FileName
    }
    try {
        $lines = Get-ComputerExportRow $rows | Protect-CsvValue | ConvertTo-Csv -Delimiter (Get-Culture).TextInfo.ListSeparator -UseQuotes AsNeeded
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8BOM -ErrorAction Stop
        $searchTime.Text = if ($rows.Count -eq 1) { Tr '· 1 ligne exportée' } else { (Tr '· {0} lignes exportées') -f $rows.Count }
        # The file's path in place of the search's times, which go with the text they explained.
        Set-SearchTimingTip $searchTime $null
        $searchTime.ToolTip = $path
    }
    catch {
        Show-Dialog -Title (Tr 'Exporter les ordinateurs') -Icon 'xcircle' -Tone 'danger' -Message ((Tr "Impossible d'enregistrer {0} : {1}") -f $path, $_.Exception.Message)
    }
}
$exportButton.Add_Click({ Export-ShownRow })
