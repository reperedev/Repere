# A computer's Propriétés, without its window: what Read-ComputerDetail reads of the fake AD's computers, and what the
# cards, the chips and Copier make of it (Get-ComputerDetailSection, Get-ComputerDetailChipXaml, Get-ComputerDetailText).

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD
    $env:REPERE_FAKEAD_LOG = Join-Path ([System.IO.Path]::GetTempPath()) "repere-computer-detail-tests-$PID.log"

    function Read-TestComputer([string]$Name, [string]$Domain = 'demo.local') {
        # Propriétés of a computer of the fake AD, read as the window reads it.
        $computer = Get-ADComputer -Server $Domain -Filter "Name -eq '$Name'" | Select-Object -First 1
        $row = [pscustomobject]@{ Name = $Name; Domain = $Domain; DistinguishedName = [string]$computer.DistinguishedName; Computer = $null }
        Read-ComputerDetail $row $Domain
    }

    function Get-SectionRow($Detail, [string]$Title, [string]$Id) {
        # One row of a card: label, value, id and tone.
        foreach ($row in (Get-ComputerDetailSection $Detail)[$Title]) { if ($row[2] -eq $Id) { return , $row } }
        throw "No row $Id in $Title."
    }
}

AfterAll {
    Clear-FakeADLog
    $env:REPERE_FAKEAD_LOG = $null
}

Describe 'Read-ComputerDetail' {
    It 'reads ORD-01: its Windows LAPS expiration, not its password, and who manages it' {
        $detail = Read-TestComputer 'ORD-01'
        $detail.Laps.Kind | Should -BeExactly 'Windows LAPS'
        $detail.Laps.Expires | Should -Not -BeNullOrEmpty
        $detail.BitLocker.Count | Should -Be 0
        $detail.BitLocker.Problem | Should -BeNullOrEmpty
        $detail.Computer.ManagedBy | Should -BeLike 'CN=Nathalie Lévy,*'
        # Only what the window shows: no LAPS attribute, and so no password, kept.
        @($detail.Computer.PSObject.Properties.Name | Where-Object { $_ -like '*LAPS*' -or $_ -like 'ms-Mcs-*' }) | Should -BeNullOrEmpty
        (Get-ComputerDetailText @{ Row = $detail.Row; Detail = $detail }) | Should -Not -Match ([regex]::Escape('Vq7#mR2t!xL9pW4z'))
    }

    It 'lists its groups as Groupes… does: direct, primary, then inherited' {
        $groups = @((Read-TestComputer 'ORD-01').Groups | ForEach-Object { "$($_.Name) | $($_.Membership)" })
        $groups | Should -Be @(
            'GG-Logiciel-Office | Directe', 'GG-Postes-Accueil | Directe', 'Liste-Inventaire | Directe', 'Ordinateurs du domaine | Principale'
            'DL-Imprimantes-Accueil | Héritée', 'GU-Postes-Nord | Héritée')
    }

    It 'counts the BitLocker keys a computer holds, without their recovery passwords' {
        $detail = Read-TestComputer 'ORD-09'
        $detail.BitLocker.Count | Should -Be 3
        (Get-SectionRow $detail 'Sécurité' 'bitlocker')[1] | Should -BeExactly '3 clés'
        (Get-SectionRow $detail 'Sécurité' 'laps')[1] | Should -BeExactly 'Aucun mot de passe'
    }

    It 'says a legacy LAPS password exists, with its expiration' {
        (Get-SectionRow (Read-TestComputer 'ORD-04') 'Sécurité' 'laps')[1] | Should -BeLike 'LAPS hérité · expire le *'
    }

    It 'reads the computer from the server it is given, not only from its domain' {
        Clear-FakeADLog
        $null = Read-TestComputer 'ORD-02'
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Get-ADComputer' -and $_.Identity }).Server | Select-Object -Unique | Should -Be 'demo.local'
    }
}

Describe 'Get-ComputerDetailSection and its chips' {
    It 'a computer that never logged on: Jamais, in amber, and a chip' {
        $detail = Read-TestComputer 'ORD-03'
        $logon = Get-SectionRow $detail 'Connexion' 'last_logon'
        $logon[1] | Should -BeExactly 'Jamais'
        $logon[3] | Should -BeExactly 'warn'
        # A chip's text starts with a character reference (ConvertTo-XamlValue).
        Get-ComputerDetailChipXaml $detail | Should -Match 'amais connecté'
    }

    It 'a Windows past its support: said in Système, in amber, and a chip' {
        $detail = Read-TestComputer 'ORD-04'
        $system = Get-SectionRow $detail 'Système' 'system'
        $system[1] | Should -BeExactly 'Win 10 22H2 (plus supporté)'
        $system[3] | Should -BeExactly 'warn'
        Get-ComputerDetailChipXaml $detail | Should -Match 'indows plus supporté'
    }

    It 'a disabled computer: Désactivé, in red, and a chip' {
        $detail = Read-TestComputer 'ORD-01'
        $detail.Computer.Enabled = $false
        (Get-SectionRow $detail 'Ordinateur' 'state')[3] | Should -BeExactly 'danger'
        Get-ComputerDetailChipXaml $detail | Should -Match 'sactiv'
    }

    It 'a computer on the domain lately, on a supported Windows: no chip, its dates in the default color' {
        $detail = Read-TestComputer 'ORD-01'
        (Get-SectionRow $detail 'Connexion' 'last_logon')[3] | Should -BeNullOrEmpty
        (Get-SectionRow $detail 'Connexion' 'password_set')[3] | Should -BeNullOrEmpty
        Get-ComputerDetailChipXaml $detail | Should -Not -Match '<Border'
    }

    It 'Général, Gestion and Objet as AD has them: role, pre-Windows 2000 name, location, canonical name, protection' {
        $detail = Read-TestComputer 'ORD-01'
        (Get-SectionRow $detail 'Ordinateur' 'sam')[1] | Should -BeExactly 'ORD-01$'
        (Get-SectionRow $detail 'Ordinateur' 'role')[1] | Should -BeExactly 'Poste de travail'
        (Get-SectionRow $detail 'Gestion' 'physical')[1] | Should -BeExactly 'Bâtiment A, accueil'
        (Get-SectionRow $detail 'Gestion' 'managed_by')[1] | Should -BeExactly 'Nathalie Lévy'
        (Get-SectionRow $detail 'Objet' 'canonical')[1] | Should -BeExactly 'demo.local/Postes/ORD-01'
        (Get-SectionRow $detail 'Objet' 'protected')[1] | Should -BeExactly 'Non protégé'
        (Get-SectionRow (Read-TestComputer 'ORD-07') 'Objet' 'protected')[1] | Should -BeExactly 'Protégé contre la suppression accidentelle'
        (Get-SectionRow (Read-TestComputer 'DC1') 'Ordinateur' 'role')[1] | Should -BeExactly 'Contrôleur de domaine'
        (Get-SectionRow (Read-TestComputer 'ORD-12') 'Ordinateur' 'role')[1] | Should -BeExactly 'Serveur'
    }

    It 'builds its cards' {
        $detail = Read-TestComputer 'ORD-01'
        $xaml = Get-ComputerDetailXaml $detail
        foreach ($name in 'computer_detail_toggle', 'computer_detail_edit', 'computer_detail_move', 'computer_detail_laps_open', 'computer_detail_bitlocker_open', 'computer_detail_physical_edit',
                          'computer_detail_manager', 'computer_detail_protect', 'computer_group_0', 'computer_group_pick_0', 'computer_group_add', 'computer_group_remove') {
            $xaml | Should -Match "x:Name=`"$name`""
        }
        # Mot de passe LAPS… while it has one; Clés BitLocker… waits for a key.
        $xaml | Should -Match 'x:Name="computer_detail_laps_open" IsEnabled="True"'
        $xaml | Should -Match 'x:Name="computer_detail_bitlocker_open" Margin="8,0,0,0" IsEnabled="False"'
        # Each name once: XAML refuses a name twice, and the window would show no card (a button named as a value).
        $twice = @([regex]::Matches($xaml, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
        $twice | Should -BeNullOrEmpty
    }
}

Describe 'Sync-ComputerDetailRow' {
    It 'brings the row the window acts on up to what was read' {
        $detail = Read-TestComputer 'ORD-02'
        $copy = [pscustomobject]@{ ComputerName = 'ORD-02'; OU = $detail.Row.DistinguishedName; Description = 'ancienne'; IsOn = $false; Disabled = 'Désactivé' }
        $detail.Row.Computer = $copy
        Sync-ComputerDetailRow @{ Row = $detail.Row; Detail = $detail }
        $copy.Description | Should -BeExactly ([string]$detail.Computer.Description)
        $copy.IsOn | Should -BeTrue
        $copy.Disabled | Should -BeNullOrEmpty
    }
}
