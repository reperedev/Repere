# The column filters' logic (ColumnFilter.ps1), without a grid: which rows each kind of filter lets through, what a
# column's list holds, and an Age filter's cutoff.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')

    function New-FilterState($Rows, [hashtable]$Specs = @{}) {
        # A grid's filters as Initialize-ColumnFilter makes them, with only what the logic reads.
        $state = @{ Grid = [pscustomobject]@{ ItemsSource = $Rows }; Specs = @{}; Active = [ordered]@{}; List = @(); Holder = @{ Query = '' }; QueryKey = 'Query' }
        foreach ($key in 'State', 'Name', 'Description', 'OS', 'LastLogon') {
            $spec = @{ Mode = 'Values'; Property = $key; Empty = '(vide)'; Order = $null }
            if ($Specs.ContainsKey($key)) { foreach ($name in $Specs[$key].Keys) { $spec[$name] = $Specs[$key][$name] } }
            $state.Specs[$key] = $spec
        }
        $state
    }

    function Set-Filter($State, [string]$Key, [string[]]$Allowed) {
        $rule = New-ColumnFilterRule $State.Specs[$Key] 'Values'
        $rule.Allowed = [System.Collections.Generic.HashSet[string]]::new([string[]]$Allowed, [System.StringComparer]::OrdinalIgnoreCase)
        $State.Active[$Key] = $rule
        $State.List = @($State.Active.Values)
    }

    function Set-ContainsFilter($State, [string]$Key, [string]$Text) {
        $rule = New-ColumnFilterRule $State.Specs[$Key] 'Contains'
        $rule.Text = $Text
        $State.Active[$Key] = $rule
        $State.List = @($State.Active.Values)
    }

    function Set-AgeFilter($State, [string]$Cutoff, [bool]$AtLeast, [bool]$Never) {
        $rule = New-ColumnFilterRule $State.Specs['LastLogon'] 'Age'
        $rule.Cutoff = $Cutoff; $rule.AtLeast = $AtLeast; $rule.Never = $Never
        $State.Active['LastLogon'] = $rule
        $State.List = @($State.Active.Values)
    }

    function Get-Through($State) {
        $filter = New-RowFilter $State
        (@($Rows | Where-Object { $filter.Invoke($_) }).Name) -join ', '
    }

    function New-Row([string]$Name, [string]$State, $Description, [string]$OS, [string]$LastLogon) {
        [pscustomobject]@{ Name = $Name; State = $State; Description = $Description; OS = $OS; LastLogon = $LastLogon; Text = "$Name $Description".ToLowerInvariant() }
    }

    $script:Rows = @(
        New-Row 'ORD-01' 'Actif' 'Accueil' 'Win 11 24H2' '2026-10-20 08:15'
        New-Row 'ORD-02' 'Désactivé' $null 'Win 10 22H2' $null
        New-Row 'ORD-03' 'Actif' 'accueil' 'Win 10 22H2' '2026-07-30 23:59'
        New-Row 'ORD-04' 'Actif' '' 'Win 11 24H2' '2026-07-31 00:00'
    )
}

Describe 'New-RowFilter' {
    It 'Lets every row through without a filter' {
        $state = New-FilterState $Rows
        $filter = New-RowFilter $state
        @($Rows | Where-Object { $filter.Invoke($_) }).Count | Should -Be 4
    }

    It 'Keeps the rows whose value is allowed in every filtered column, whatever its case' {
        $state = New-FilterState $Rows
        Set-Filter $state 'State' 'ACTIF'
        Set-Filter $state 'OS' 'Win 10 22H2'
        $filter = New-RowFilter $state
        (@($Rows | Where-Object { $filter.Invoke($_) }).Name) -join ', ' | Should -BeExactly 'ORD-03'
    }

    It 'Reads a missing or empty value as the column''s empty label' {
        $state = New-FilterState $Rows @{ Description = @{ Empty = 'Aucune description' } }
        Set-Filter $state 'Description' 'Aucune description'
        $filter = New-RowFilter $state
        (@($Rows | Where-Object { $filter.Invoke($_) }).Name) -join ', ' | Should -BeExactly 'ORD-02, ORD-04'
    }

    It 'Adds the filter box, as the page keeps its text' {
        $state = New-FilterState $Rows
        Set-Filter $state 'State' 'Actif'
        $filter = New-RowFilter $state
        $state.Holder.Query = 'accueil'
        (@($Rows | Where-Object { $filter.Invoke($_) }).Name) -join ', ' | Should -BeExactly 'ORD-01, ORD-03'
    }
}

Describe 'Get-ColumnFilterChoice' {
    It 'Lists each value once whatever its case, with its count, the empty one first, and all ticked without a filter' {
        $state = New-FilterState $Rows
        $choices = @(Get-ColumnFilterChoice $state 'Description' '')
        (@($choices | ForEach-Object { "$($_.Label) $($_.Count) $($_.Checked)" }) -join ' | ') | Should -BeExactly '(vide) 2 True | Accueil 2 True'
    }

    It 'Lists only the values of the rows the other filters and the filter box let through' {
        $state = New-FilterState $Rows
        Set-Filter $state 'State' 'Actif'
        (@(Get-ColumnFilterChoice $state 'OS' '') | ForEach-Object { "$($_.Label) $($_.Count)" }) -join ' | ' | Should -BeExactly 'Win 10 22H2 1 | Win 11 24H2 2'
        (@(Get-ColumnFilterChoice $state 'OS' 'ord-01') | ForEach-Object { "$($_.Label) $($_.Count)" }) -join ' | ' | Should -BeExactly 'Win 11 24H2 1'
    }

    It 'Ticks only what the column''s own filter allows, and lists the values it doesn''t' {
        $state = New-FilterState $Rows
        Set-Filter $state 'OS' 'Win 10 22H2'
        (@(Get-ColumnFilterChoice $state 'OS' '') | ForEach-Object { "$($_.Label) $($_.Checked)" }) -join ' | ' | Should -BeExactly 'Win 10 22H2 True | Win 11 24H2 False'
    }

    It 'Follows the column''s order when it has one' {
        $state = New-FilterState $Rows @{ OS = @{ Order = 'Win 11 24H2', 'Win 10 22H2' } }
        (@(Get-ColumnFilterChoice $state 'OS' '') | ForEach-Object Label) -join ' | ' | Should -BeExactly 'Win 11 24H2 | Win 10 22H2'
    }
}

Describe 'Contains filters' {
    It 'Keeps the rows whose value contains the text, whatever its case' {
        $state = New-FilterState $Rows
        Set-ContainsFilter $state 'Description' 'ACCU'
        Get-Through $state | Should -BeExactly 'ORD-01, ORD-03'
    }

    It 'Reads a missing value as the column''s empty label, as the grid shows it' {
        $state = New-FilterState $Rows @{ Description = @{ Empty = 'Aucune description' } }
        Set-ContainsFilter $state 'Description' 'aucune'
        Get-Through $state | Should -BeExactly 'ORD-02, ORD-04'
    }

    It 'Ticks in its column''s list the values it keeps' {
        $state = New-FilterState $Rows
        Set-ContainsFilter $state 'OS' '11'
        (@(Get-ColumnFilterChoice $state 'OS' '') | ForEach-Object { "$($_.Label) $($_.Checked)" }) -join ' | ' | Should -BeExactly 'Win 10 22H2 False | Win 11 24H2 True'
    }

    It 'Narrows the other columns'' lists' {
        $state = New-FilterState $Rows
        Set-ContainsFilter $state 'Name' '-0'
        Set-Filter $state 'State' 'Actif'
        (@(Get-ColumnFilterChoice $state 'OS' '') | ForEach-Object { "$($_.Label) $($_.Count)" }) -join ' | ' | Should -BeExactly 'Win 10 22H2 1 | Win 11 24H2 2'
    }
}

Describe 'Age filters' {
    It 'At least: the rows dated before the cutoff, and those never logged on with Jamais' {
        $state = New-FilterState $Rows
        Set-AgeFilter $state '2026-07-31 00:00' $true $true
        Get-Through $state | Should -BeExactly 'ORD-02, ORD-03'
        Set-AgeFilter $state '2026-07-31 00:00' $true $false
        Get-Through $state | Should -BeExactly 'ORD-03'
    }

    It 'Less than: the rows dated from the cutoff on, and never logged on only with Jamais' {
        $state = New-FilterState $Rows
        Set-AgeFilter $state '2026-07-31 00:00' $false $false
        Get-Through $state | Should -BeExactly 'ORD-01, ORD-04'
        Set-AgeFilter $state '2026-07-31 00:00' $false $true
        Get-Through $state | Should -BeExactly 'ORD-01, ORD-02, ORD-04'
    }

    It 'Narrows the other columns'' lists' {
        $state = New-FilterState $Rows
        Set-AgeFilter $state '2026-07-31 00:00' $true $false
        (@(Get-ColumnFilterChoice $state 'OS' '') | ForEach-Object { "$($_.Label) $($_.Count)" }) -join ' | ' | Should -BeExactly 'Win 10 22H2 1'
    }
}

Describe 'Get-ColumnFilterCutoff' {
    It 'Is midnight, that long ago, as the rows write their dates' -TestCases @(
        @{ Number = 90; Unit = 0; Cutoff = '2026-07-31 00:00' }
        @{ Number = 2; Unit = 1; Cutoff = '2026-10-15 00:00' }
        @{ Number = 6; Unit = 2; Cutoff = '2026-04-29 00:00' }
        @{ Number = 1; Unit = 3; Cutoff = '2025-10-29 00:00' }
    ) {
        param($Number, $Unit, $Cutoff)
        Get-ColumnFilterCutoff $Number $Unit ([datetime]'2026-10-29 15:30') | Should -BeExactly $Cutoff
    }
}
