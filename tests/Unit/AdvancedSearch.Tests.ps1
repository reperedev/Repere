# The Recherche avancée's logic (AdvancedSearch.ps1), without its popup: what the criteria add to the AD filter, how
# they're kept in recherche.json and read back (older files' Inactifs depuis too), and how they're said.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')

    function New-Criteria([hashtable]$Set = @{}) {
        $criteria = New-AdvancedSearch
        foreach ($key in $Set.Keys) { $criteria[$key] = $Set[$key] }
        $criteria
    }

    $script:Today = [datetime]'2026-10-29 15:30'
    $script:Cutoff90 = ([datetime]'2026-07-31').ToFileTimeUtc()
}

Describe 'Get-AdvancedSearchFilter' {
    It 'Adds nothing without a criterion, nor for the emplacement (the search''s base)' {
        $filter = Get-AdvancedSearchFilter (New-Criteria @{ Scope = 'OUName' }) $Today
        $filter.Filter | Should -BeExactly ''
        $filter.CreatedBefore | Should -BeNullOrEmpty
    }

    It 'Compte: the enabled or the disabled computers' {
        (Get-AdvancedSearchFilter (New-Criteria @{ State = 'Enabled' }) $Today).Filter | Should -BeExactly " -and Enabled -eq 'True'"
        (Get-AdvancedSearchFilter (New-Criteria @{ State = 'Disabled' }) $Today).Filter | Should -BeExactly " -and Enabled -eq 'False'"
    }

    It 'Système: the text the operating system contains, its quotes doubled' {
        (Get-AdvancedSearchFilter (New-Criteria @{ System = "Server d'essai" }) $Today).Filter | Should -BeExactly " -and OperatingSystem -like '*Server d''essai*'"
    }

    It 'Au moins with Jamais: not logged on since midnight that long ago, or never, and those created since left out' {
        $filter = Get-AdvancedSearchFilter (New-Criteria @{ Logon = 'AtLeast'; Number = 90; Unit = 0; Never = $true }) $Today
        $filter.Filter | Should -BeExactly " -and (lastLogonTimestamp -lt $Cutoff90 -or (-not (lastLogonTimestamp -like '*') -and whenCreated -lt `$CreatedBefore))"
        $filter.CreatedBefore | Should -Be ([datetime]'2026-07-31')
    }

    It 'Au moins without Jamais, and Moins de with or without it' {
        (Get-AdvancedSearchFilter (New-Criteria @{ Logon = 'AtLeast'; Never = $false }) $Today).Filter | Should -BeExactly " -and lastLogonTimestamp -lt $Cutoff90"
        $less = Get-AdvancedSearchFilter (New-Criteria @{ Logon = 'Less'; Never = $false }) $Today
        $less.Filter | Should -BeExactly " -and lastLogonTimestamp -ge $Cutoff90"
        $less.CreatedBefore | Should -BeNullOrEmpty
        (Get-AdvancedSearchFilter (New-Criteria @{ Logon = 'Less'; Never = $true }) $Today).Filter |
            Should -BeExactly " -and (lastLogonTimestamp -ge $Cutoff90 -or -not (lastLogonTimestamp -like '*'))"
    }

    It 'Counts weeks, months and years as the column filters do' {
        $cutoff = ([datetime]'2026-04-29').ToFileTimeUtc()
        (Get-AdvancedSearchFilter (New-Criteria @{ Logon = 'Less'; Number = 6; Unit = 2; Never = $false }) $Today).Filter | Should -BeExactly " -and lastLogonTimestamp -ge $cutoff"
    }

    It 'Puts the criteria in a set order' {
        (Get-AdvancedSearchFilter (New-Criteria @{ State = 'Disabled'; System = '10'; Logon = 'AtLeast'; Never = $false }) $Today).Filter |
            Should -BeExactly " -and Enabled -eq 'False' -and OperatingSystem -like '*10*' -and lastLogonTimestamp -lt $Cutoff90"
    }
}

Describe 'Get-AdvancedSearchCount and Get-AdvancedSearchProblem' {
    It 'Counts each criterion set' {
        Get-AdvancedSearchCount (New-AdvancedSearch) | Should -Be 0
        Get-AdvancedSearchCount (New-Criteria @{ Scope = 'OUName'; State = 'Enabled'; System = 'x'; Logon = 'Less' }) | Should -Be 4
    }

    It 'Asks for an OU, a name or a number when one is missing' -TestCases @(
        @{ Set = @{ Scope = 'OU' }; Problem = "Choisissez l'OU où chercher (Recherche avancée)" }
        @{ Set = @{ Scope = 'OUName'; OUName = ' ' }; Problem = 'Entrez le début du nom des OU (Recherche avancée)' }
        @{ Set = @{ Scope = 'OUName' }; Problem = 'Entrez le début du nom des OU (Recherche avancée)' }
        @{ Set = @{ Logon = 'AtLeast'; Number = 0 }; Problem = 'Entrez un nombre de 1 à 999 pour la dernière connexion (Recherche avancée)' }
    ) {
        param($Set, $Problem)
        Get-AdvancedSearchProblem (New-Criteria $Set) | Should -BeExactly $Problem
    }

    It 'Has nothing to say about criteria that can be searched, or a number left without Dernière connexion' {
        Get-AdvancedSearchProblem (New-Criteria @{ Scope = 'OU'; OU = 'OU=Postes,DC=demo,DC=local'; OUDomain = 'demo.local'; Number = 0 }) | Should -BeNullOrEmpty
    }
}

Describe 'Format-AdvancedSearch' {
    It 'Says each criterion set, in order' {
        $criteria = New-Criteria @{ Scope = 'OU'; OU = 'OU=Communs,OU=Postes,DC=demo,DC=local'; OUDomain = 'demo.local'; State = 'Disabled'; System = 'Windows 10'; Logon = 'AtLeast' }
        (Format-AdvancedSearch $criteria) -join ' · ' | Should -BeExactly 'OU Postes › Communs · désactivés · système « Windows 10 » · inactifs depuis 90 jours'
        @(Format-AdvancedSearch $criteria -WithDomain)[0] | Should -BeExactly 'OU Postes › Communs (demo.local)'
    }

    It 'Says the last logon each way, in the singular for 1' -TestCases @(
        @{ Set = @{ Scope = 'OUName'; OUName = 'Communs'; Logon = 'AtLeast'; Never = $false; Number = 1; Unit = 3 }; Text = 'OU Communs… · inactifs depuis 1 an, sauf jamais connectés' }
        @{ Set = @{ State = 'Enabled'; Logon = 'Less'; Never = $false; Number = 2; Unit = 1 }; Text = 'activés · connectés depuis moins de 2 semaines' }
        @{ Set = @{ Logon = 'Less'; Never = $true; Number = 1; Unit = 2 }; Text = 'connectés depuis moins de 1 mois, ou jamais' }
    ) {
        param($Set, $Text)
        (Format-AdvancedSearch (New-Criteria $Set)) -join ' · ' | Should -BeExactly $Text
    }

    It 'Says nothing without a criterion' {
        @(Format-AdvancedSearch (New-AdvancedSearch)).Count | Should -Be 0
    }
}

Describe 'ConvertFrom-SavedAdvancedSearch and ConvertTo-SavedAdvancedSearch' {
    It 'Reads back what it keeps, from the file or as a recent search keeps it' {
        $criteria = New-Criteria @{ Scope = 'OU'; OU = 'OU=Postes,DC=demo,DC=local'; OUDomain = 'demo.local'; State = 'Enabled'; System = 'Server'; Logon = 'Less'; Number = 3; Unit = 1; Never = $false }
        $saved = ConvertTo-SavedAdvancedSearch $criteria
        foreach ($read in (ConvertFrom-SavedAdvancedSearch $saved), (ConvertFrom-SavedAdvancedSearch ($saved | ConvertTo-Json | ConvertFrom-Json))) {
            ($read | ConvertTo-Json -Compress) | Should -BeExactly ($criteria | ConvertTo-Json -Compress)
        }
    }

    It 'Keeps nothing for a recent search without a criterion, and everything for the settings' {
        ConvertTo-SavedAdvancedSearch (New-AdvancedSearch) | Should -BeNullOrEmpty
        @((ConvertTo-SavedAdvancedSearch (New-Criteria @{ OUName = 'Kiosque' }) -Always).Keys) -join ',' | Should -BeExactly 'Scope,OU,OUDomain,OUName,State,System,Logon,Number,Unit,Never'
    }

    It 'Leaves out what it doesn''t offer, and an OU without its domain' {
        $read = ConvertFrom-SavedAdvancedSearch ([pscustomobject]@{ Scope = 'OU'; OU = 'OU=Postes,DC=demo,DC=local'; State = 'Locked'; Logon = 'atleast'; Number = 1000; Unit = 7; OUName = '' })
        "$($read.Scope) $($read.OU) $($read.State) $($read.Logon) $($read.Number) $($read.Unit) $($read.OUName)" | Should -BeExactly 'All  All Any 90 0 '
    }

    It 'Reads an older search''s Inactifs depuis as a criterion' -TestCases @(
        @{ Inactive = ''; Expected = 'All Any 90 0' }
        @{ Inactive = '180 jours'; Expected = 'All AtLeast 180 0' }
        @{ Inactive = '1 an'; Expected = 'All AtLeast 1 3' }
        @{ Inactive = '2 ans'; Expected = 'All Any 90 0' }
    ) {
        param($Inactive, $Expected)
        $read = ConvertFrom-SavedAdvancedSearch $null $Inactive
        "$($read.Scope) $($read.Logon) $($read.Number) $($read.Unit)" | Should -BeExactly $Expected
        $read.Never | Should -BeTrue
    }
}
