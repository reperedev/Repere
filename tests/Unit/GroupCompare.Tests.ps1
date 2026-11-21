# Comparer les groupes… without its window: the groups of two users as one list (Compare-UserGroup), how each belongs
# to a group (Get-GroupCompareMembership), Copier's text (Get-GroupCompareText), then with the fake AD both users' groups
# (Read-UserGroupCompare) and the other user's search (Get-CompareUserChoice).

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD

    function New-TestGroup([string]$Name, [string]$Membership, [string]$DistinguishedName = "CN=$Name,OU=Groupes,DC=demo,DC=local") {
        # A group as Get-ObjectGroup returns it.
        [pscustomobject]@{ Name = $Name; Type = 'Sécurité'; Scope = 'Globale'; Membership = $Membership; Domain = 'demo.local'; Description = ''; DistinguishedName = $DistinguishedName }
    }

    function Get-TestRow([string]$Login, [string]$Domain = 'demo.local') {
        # A user as the comparison takes it: a row of the Utilisateurs page.
        $user = Get-ADUser -Server $Domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$Login))"
        [pscustomobject]@{ Name = [string]$user.Name; Login = $Login; Domain = $Domain; DistinguishedName = [string]$user.DistinguishedName }
    }

    function Get-SideText($Entries) {
        # Each group as « Side Name: A/B », in the order returned.
        @($Entries | ForEach-Object { "$($_.Side) $($_.Name): $($_.A)/$($_.B)" })
    }
}

Describe 'Compare-UserGroup' {
    It 'Puts each group on its side, by name, with how each user belongs to it' {
        $a = @((New-TestGroup 'GG-VPN' 'Directe'), (New-TestGroup 'GG-Accueil' 'Directe'), (New-TestGroup 'DL-Partage' 'Héritée'))
        $b = @((New-TestGroup 'GG-VPN' 'Héritée'), (New-TestGroup 'GG-Ventes' 'Directe'))
        Get-SideText (Compare-UserGroup $a $b) | Should -Be @('A DL-Partage: Héritée/', 'A GG-Accueil: Directe/', 'B GG-Ventes: /Directe', 'Both GG-VPN: Directe/Héritée')
    }

    It 'Says Héritée for A when that is how A belongs' {
        $entry = @(Compare-UserGroup @(New-TestGroup 'DL-Partage' 'Héritée') @())[0]
        $entry.A | Should -BeExactly 'Héritée'
        $entry.B | Should -BeNullOrEmpty
        $entry.Side | Should -BeExactly 'A'
    }

    It 'Takes two spellings of a DN for one group' {
        $entries = @(Compare-UserGroup @(New-TestGroup 'GG-VPN' 'Directe') @(New-TestGroup 'GG-VPN' 'Directe' 'cn=GG-VPN,ou=Groupes,dc=demo,dc=local'))
        $entries.Count | Should -Be 1
        $entries[0].Side | Should -BeExactly 'Both'
    }

    It 'Keeps a group that could not be read (no DN) by its name' {
        $unread = [pscustomobject]@{ Name = 'Groupes hérités'; Type = ''; Scope = ''; Membership = 'Héritée'; Domain = 'demo.local'; Description = 'non lus : refusé'; DistinguishedName = '' }
        $entries = @(Compare-UserGroup @($unread) @(New-TestGroup 'GG-VPN' 'Directe'))
        Get-SideText $entries | Should -Be @('B GG-VPN: /Directe', 'A Groupes hérités: Héritée/')
    }

    It 'Gives nothing for two users without groups' {
        @(Compare-UserGroup @() @()).Count | Should -Be 0
    }
}

Describe 'Get-GroupCompareMembership and Get-GroupCompareText' {
    BeforeAll {
        $script:Entries = @(Compare-UserGroup @((New-TestGroup 'GG-VPN' 'Directe'), (New-TestGroup 'GG-Accueil' 'Directe'), (New-TestGroup 'Utilisateurs du domaine' 'Principale')) `
                                               @((New-TestGroup 'GG-VPN' 'Héritée'), (New-TestGroup 'Utilisateurs du domaine' 'Principale')))
    }

    It 'Names the membership once when both belong alike, or each user by login otherwise' {
        $byName = @{}
        foreach ($entry in $script:Entries) { $byName[$entry.Name] = Get-GroupCompareMembership $entry 'jbertrand' 'jebertrand' }
        $byName['GG-Accueil'] | Should -BeExactly 'Directe'
        $byName['Utilisateurs du domaine'] | Should -BeExactly 'Principale'
        $byName['GG-VPN'] | Should -BeExactly 'jbertrand : Directe, jebertrand : Héritée'
    }

    It 'Copies the three lists, each with its count' {
        $text = Get-GroupCompareText $script:Entries 'Julie Bertrand' 'Jean Bertrand' 'jbertrand' 'jebertrand'
        $text -split [Environment]::NewLine | Should -Be @(
            'Groupes de Julie Bertrand et de Jean Bertrand'
            ''
            'Seulement Julie Bertrand (1)'
            '  GG-Accueil (Directe)'
            ''
            'Les deux (2)'
            '  GG-VPN (jbertrand : Directe, jebertrand : Héritée)'
            '  Utilisateurs du domaine (Principale)'
            ''
            'Seulement Jean Bertrand (0)'
        )
    }

    It 'Names a user by login, with its domain when both have the same login' {
        Get-GroupCompareLabel 'jbertrand' 'demo.local' $false | Should -BeExactly 'jbertrand'
        Get-GroupCompareLabel 'jbertrand' 'nord.demo.local' $true | Should -BeExactly 'jbertrand (nord.demo.local)'
    }
}

Describe 'Read-UserGroupCompare, with the fake AD' {
    It 'Shows what Julie Bertrand has that Jean Bertrand has not' {
        $read = Read-UserGroupCompare (Get-TestRow 'jbertrand') (Get-TestRow 'jebertrand')
        Get-SideText (Compare-UserGroup $read.A $read.B) | Should -Be @(
            'A DL-Partage-Accueil: Héritée/'
            'A GG-Accueil: Directe/'
            'Both GG-VPN: Directe/Directe'
            'Both Utilisateurs du domaine: Principale/Principale'
        )
    }

    It 'Fails for a user who is not there' {
        $gone = [pscustomobject]@{ Name = 'Personne'; Login = 'personne'; Domain = 'demo.local'; DistinguishedName = 'CN=Personne,OU=Utilisateurs,DC=demo,DC=local' }
        { Read-UserGroupCompare (Get-TestRow 'jbertrand') $gone } | Should -Throw
    }
}

Describe 'Get-CompareUserChoice, with the fake AD' {
    It 'Finds the users the text names in every domain, the window user left out, by name' {
        $julie = Get-TestRow 'jbertrand'
        $found = @((Get-CompareUserChoice @('demo.local', 'nord.demo.local') 'bert' $julie.DistinguishedName).Items)
        @($found | ForEach-Object Name) | Should -Be @('Jean Bertrand', 'Paul Bertrand')
        $found[1].Row.Domain | Should -BeExactly 'nord.demo.local'
        $found[1].Row.Login | Should -BeExactly 'pbertrand'
        $found[1].Details | Should -BeExactly 'pbertrand · nord.demo.local · Magasinier'
    }

    It 'Passes over a domain that cannot be searched, and fails when none can' {
        @((Get-CompareUserChoice @('demo.local', 'absent.local') 'perrin' '').Items).Name | Should -Be @('Léa Perrin')
        { Get-CompareUserChoice @('absent.local') 'perrin' '' } | Should -Throw
    }

    It 'Names the domain that could not be searched, with why, for the note under the list (#248)' {
        try {
            $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
            $found = Get-CompareUserChoice @('demo.local', 'nord.demo.local') 'bert' (Get-TestRow 'jbertrand').DistinguishedName
            @($found.Items | ForEach-Object Name) | Should -Be @('Jean Bertrand')
            @($found.Unsearched).Domain | Should -BeExactly 'nord.demo.local'
            @($found.Unsearched).Problem | Should -BeLike 'Unable to contact the server*'
        }
        finally { $env:REPERE_FAKEAD_UNREACHABLE = $null }
        @((Get-CompareUserChoice @('demo.local', 'nord.demo.local') 'bert' '').Unsearched) | Should -BeNullOrEmpty
    }
}

Describe 'Copier in the comparison window (#248)' {
    BeforeEach {
        Mock Show-CopyFeedback { }
        $script:button = [System.Windows.Controls.Button]::new()
        $entries = @(Compare-UserGroup @((New-TestGroup 'GG-VPN' 'Directe'), (New-TestGroup 'GG-Accueil' 'Directe')) @(New-TestGroup 'GG-VPN' 'Directe'))
        # The window's state, its lists' views as the groups they show.
        $script:state = @{
            Views = @{ A = @($entries | Where-Object Side -eq 'A' | ForEach-Object { @{ Entry = $_ } }); Both = @($entries | Where-Object Side -eq 'Both' | ForEach-Object { @{ Entry = $_ } }); B = @() }
            RowA = @{ Name = 'Julie Bertrand' }; RowB = @{ Name = 'Jean Bertrand' }; LabelA = 'jbertrand'; LabelB = 'jebertrand'
            Status = [System.Windows.Controls.TextBlock]::new()
        }
    }

    It 'Copies the groups shown, and says so on the button and the status line' {
        Mock Set-ClipboardText { $true }
        Copy-GroupCompare $script:state $script:button
        Should -Invoke Set-ClipboardText -Times 1 -Exactly -ParameterFilter { $Text -like 'Groupes de Julie Bertrand et de Jean Bertrand*GG-Accueil*GG-VPN*' }
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and $Copied }
        $script:state.Status.Text | Should -BeExactly '2 groupes copiés.'
    }

    It 'Says « Copie impossible » on the button, and no groups copied, when another program holds the clipboard' {
        Mock Set-ClipboardText { $false }
        Copy-GroupCompare $script:state $script:button
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and -not $Copied }
        $script:state.Status.Text | Should -BeExactly 'Non copié : le presse-papiers est occupé par un autre programme.'
    }
}
