# A user's Propriétés, without its window: the texts of the Compte and Verrouillage cards (Get-UserDetailSection), from
# fake user objects, then from users of the fake AD as Read-UserDetail reads them.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD
    $script:French = [System.Globalization.CultureInfo]::GetCultureInfo('fr-CA')

    function New-TestDetail([hashtable]$User = @{}, $Policy) {
        # What Read-UserDetail returns, for a user enabled, not locked, whose account never expires, unless $User says
        # otherwise. Every property Read-UserDetail asks AD for is there, empty or not, as AD returns them (strict mode
        # fails on a missing one).
        $properties = [ordered]@{
            Enabled = $true; LockedOut = $false; AccountLockoutTime = $null; AccountExpirationDate = $null; badPwdCount = 0
            LastBadPasswordAttempt = $null; LastLogonDate = $null; whenCreated = $null; whenChanged = $null; PasswordLastSet = $null
            DisplayName = $null; GivenName = $null; Surname = $null; SamAccountName = $null; UserPrincipalName = $null; mail = $null
            EmployeeID = $null; Description = $null; Title = $null; Department = $null; Company = $null; Office = $null; Manager = $null
            OfficePhone = $null; MobilePhone = $null; HomeDirectory = $null; HomeDrive = $null; ProfilePath = $null; ScriptPath = $null
        }
        foreach ($key in $User.Keys) { $properties[$key] = $User[$key] }
        @{ User = [pscustomobject]$properties; Row = [pscustomobject]@{ Password = 'Expire dans 40 jours'; PasswordTone = $null }; Policy = $Policy }
    }

    function Get-SectionRow($Detail, [string]$Title, [string]$Id) {
        # One row of a card: label, value, id and tone.
        foreach ($row in (Get-UserDetailSection $Detail)[$Title]) { if ($row[2] -eq $Id) { return , $row } }
        throw "No row $Id in $Title."
    }

    function Get-Day([int]$Days) {
        # A day from today, as the cards write it.
        (Get-Date).Date.AddDays($Days).ToString('d', $script:French)
    }

    $script:Policy = [pscustomobject]@{ LockoutThreshold = 5; LockoutDuration = [timespan]'00:30:00'; LockoutObservationWindow = [timespan]'00:15:00' }
}

Describe "Get-UserDetailSection: the account's expiration" {
    # AD keeps the start of the day after the account's last day: an expiration at midnight tonight means today is its
    # last day.
    It "Says « N'expire jamais » without an expiration" {
        $row = Get-SectionRow (New-TestDetail) 'Compte' 'expiry'
        $row[1] | Should -BeExactly "N'expire jamais"
        $row[3] | Should -BeNullOrEmpty
    }

    It 'Says since when an expired account ended, in red' {
        $row = Get-SectionRow (New-TestDetail @{ AccountExpirationDate = (Get-Date).Date.AddDays(-3) }) 'Compte' 'expiry'
        $row[1] | Should -BeExactly "Expiré depuis le $(Get-Day -4)"
        $row[3] | Should -BeExactly 'danger'
    }

    It 'Says an account that expired at midnight ended yesterday' {
        $row = Get-SectionRow (New-TestDetail @{ AccountExpirationDate = (Get-Date).Date }) 'Compte' 'expiry'
        $row[1] | Should -BeExactly "Expiré depuis le $(Get-Day -1)"
        $row[3] | Should -BeExactly 'danger'
    }

    It 'Names its last day, « <When> », <Days> days from today (<Look>)' -ForEach @(
        @{ Days = 0; When = "aujourd'hui"; Tone = 'warn'; Look = 'amber' }
        @{ Days = 1; When = 'demain'; Tone = 'warn'; Look = 'amber' }
        @{ Days = 5; When = 'dans 5 jours'; Tone = 'warn'; Look = 'amber' }
        @{ Days = 14; When = 'dans 14 jours'; Tone = 'warn'; Look = 'amber' }
        @{ Days = 15; When = 'dans 15 jours'; Tone = ''; Look = 'no color' }
        @{ Days = 120; When = 'dans 120 jours'; Tone = ''; Look = 'no color' }
    ) {
        $row = Get-SectionRow (New-TestDetail @{ AccountExpirationDate = (Get-Date).Date.AddDays($Days + 1) }) 'Compte' 'expiry'
        $row[1] | Should -BeExactly "Fin du $(Get-Day $Days) ($When)"
        "$($row[3])" | Should -BeExactly $Tone
    }
}

Describe 'Get-UserDetailSection: the lockout' {
    It 'Says since when a locked account is, in red' {
        $detail = New-TestDetail @{ LockedOut = $true; AccountLockoutTime = [datetime]'2026-10-23 08:20' }
        $row = Get-SectionRow $detail 'Verrouillage' 'lockout'
        $row[1] | Should -BeExactly 'Verrouillé depuis le 2026-10-23 à 08 h 20'
        $row[3] | Should -BeExactly 'danger'
        $state = Get-SectionRow $detail 'Compte' 'state'
        $state[1] | Should -BeExactly 'Verrouillé'
        $state[3] | Should -BeExactly 'danger'
    }

    It 'Says « Verrouillé » alone when AD has no lockout time' {
        (Get-SectionRow (New-TestDetail @{ LockedOut = $true }) 'Verrouillage' 'lockout')[1] | Should -BeExactly 'Verrouillé'
    }

    It 'Says « Non verrouillé » otherwise, an active account in no tone' {
        $detail = New-TestDetail
        $row = Get-SectionRow $detail 'Verrouillage' 'lockout'
        $row[1] | Should -BeExactly 'Non verrouillé'
        $row[3] | Should -BeNullOrEmpty
        $state = Get-SectionRow $detail 'Compte' 'state'
        $state[1] | Should -BeExactly 'Actif'
        $state[3] | Should -BeNullOrEmpty
    }

    It 'Says a disabled account is disabled, even when it is locked too' {
        $state = Get-SectionRow (New-TestDetail @{ Enabled = $false; LockedOut = $true }) 'Compte' 'state'
        $state[1] | Should -BeExactly 'Désactivé'
        $state[3] | Should -BeExactly 'danger'
    }

    It "Counts the bad passwords against the domain's threshold, and says its policy" {
        $detail = New-TestDetail @{ badPwdCount = 2; LastBadPasswordAttempt = [datetime]'2026-10-22 07:58' } $script:Policy
        (Get-SectionRow $detail 'Verrouillage' 'bad_count')[1] | Should -BeExactly '2 (le compte se verrouille à 5)'
        (Get-SectionRow $detail 'Verrouillage' 'bad_last')[1] | Should -BeExactly '2026-10-22 à 07 h 58'
        (Get-SectionRow $detail 'Verrouillage' 'policy')[1] | Should -BeExactly '5 mauvais mots de passe en 15 min : verrouillé 30 min'
    }

    It 'Says a lockout without a duration lasts until someone unlocks the account' {
        $policy = [pscustomobject]@{ LockoutThreshold = 3; LockoutDuration = [timespan]::Zero; LockoutObservationWindow = [timespan]'00:30:00' }
        (Get-SectionRow (New-TestDetail -Policy $policy) 'Verrouillage' 'policy')[1] | Should -BeExactly "3 mauvais mots de passe en 30 min : verrouillé jusqu'au déverrouillage manuel"
    }

    It 'Says when the domain locks no account: <Case>' -ForEach @(
        @{ Case = 'no policy read'; Policy = $null }
        @{ Case = 'a threshold of 0'; Policy = [pscustomobject]@{ LockoutThreshold = 0; LockoutDuration = [timespan]'00:30:00'; LockoutObservationWindow = [timespan]'00:30:00' } }
    ) {
        $detail = New-TestDetail @{ badPwdCount = 2 } $Policy
        (Get-SectionRow $detail 'Verrouillage' 'bad_count')[1] | Should -BeExactly '2'
        (Get-SectionRow $detail 'Verrouillage' 'policy')[1] | Should -BeExactly 'Le domaine ne verrouille pas les comptes après de mauvais mots de passe.'
    }
}

Describe 'Read-UserDetail with the fake AD' {
    BeforeAll {
        function Read-TestUser([string]$Name) {
            $user = Get-ADUser -Server demo.local -LDAPFilter "(&(objectCategory=person)(objectClass=user)(anr=$Name))" | Select-Object -First 1
            Read-UserDetail ([pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = $user.DistinguishedName; Password = ''; PasswordTone = $null }) $null
        }
    }

    BeforeEach {
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        Clear-FakeADLog
    }

    AfterEach {
        $env:REPERE_FAKEAD_LOG = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $null
    }

    It "Reads the lockout on the domain's PDC, Marc Durand locked by 5 bad passwords" {
        $detail = Read-TestUser 'Marc Durand'
        $detail.Pdc | Should -BeExactly 'dc1.demo.local'
        $detail.Server | Should -BeExactly 'dc1.demo.local'
        $detail.PdcProblem | Should -BeNullOrEmpty
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Get-ADUser' -and $_.Identity }).Server | Sort-Object -Unique | Should -BeExactly 'dc1.demo.local'
        (Get-SectionRow $detail 'Verrouillage' 'lockout')[1] | Should -BeLike 'Verrouillé depuis le *'
        (Get-SectionRow $detail 'Verrouillage' 'bad_count')[1] | Should -BeExactly '5 (le compte se verrouille à 5)'
        (Get-SectionRow $detail 'Verrouillage' 'policy')[1] | Should -BeExactly '5 mauvais mots de passe en 30 min : verrouillé 30 min'
    }

    It "Reads the account from one other DC when the PDC doesn't answer, and says so on the lockout card" {
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        $detail = Read-TestUser 'Marc Durand'
        $detail.Pdc | Should -BeExactly 'dc1.demo.local'
        $detail.Server | Should -BeExactly 'dc2.demo.local'
        $detail.PdcProblem | Should -BeLike 'Unable to contact the server*'
        $detail.PdcDown | Should -BeOfType [datetime]
        # Tried on the PDC once, then every read on the DC the locator found, not the domain's name (any DC each time).
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Get-ADUser' -and $_.Identity } | ForEach-Object Server) | Should -Be @('dc1.demo.local', 'dc2.demo.local', 'dc2.demo.local')
        (Get-SectionRow $detail 'Verrouillage' 'bad_count')[1] | Should -BeExactly '5 (le compte se verrouille à 5)'
        # The card's texts, as XAML attributes (ConvertTo-XamlValue): decoded.
        $xaml = [System.Net.WebUtility]::HtmlDecode((Get-UserDetailXaml $detail))
        $xaml | Should -BeLike '*Text="non lu sur le PDC"*'
        $xaml | Should -BeLike "*Le PDC dc1.demo.local n'a pas répondu (Le serveur ne répond pas : *) : lu sur un autre contrôleur de domaine*"
        $xaml | Should -Not -BeLike '*lu sur dc1.demo.local*'
    }

    It 'Fails as before on any other error from the PDC, without reading elsewhere' {
        $row = [pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = 'CN=Personne,OU=Utilisateurs,DC=demo,DC=local'; Password = ''; PasswordTone = $null }
        { Read-UserDetail $row $null } | Should -Throw '*CN=Personne*'
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Get-ADUser' -and $_.Identity } | ForEach-Object Server) | Should -Be @('dc1.demo.local')
    }

    It 'Says Léa Perrin expires in 20 days' {
        (Get-SectionRow (Read-TestUser 'Léa Perrin') 'Compte' 'expiry')[1] | Should -BeExactly "Fin du $(Get-Day 20) (dans 20 jours)"
    }

    It 'Lists the groups of Julie Bertrand: two direct, the primary one and one inherited' {
        $groups = (Read-TestUser 'Julie Bertrand').Groups
        @($groups | ForEach-Object { "$($_.Membership): $($_.Name)" }) | Should -Be @(
            'Directe: GG-Accueil', 'Directe: GG-VPN', 'Principale: Utilisateurs du domaine', 'Héritée: DL-Partage-Accueil'
        )
    }

    It 'Gives no box to the row of a domain not searched, which still says why, nor to « Groupes hérités » (#249)' {
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        $detail = Read-TestUser 'Julie Bertrand'
        # tokenGroups refused: the « Groupes hérités » row too.
        $detail.Groups = @($detail.Groups) + [pscustomobject]@{ Name = 'Groupes hérités'; Type = ''; Scope = ''; Membership = 'Héritée'; Domain = 'demo.local'; Description = 'non lus : Accès refusé'; DistinguishedName = '' }
        $groups = @($detail.Groups)
        $xaml = [System.Net.WebUtility]::HtmlDecode((Get-UserGroupXaml $detail))
        $picked = @(for ($i = 0; $i -lt $groups.Count; $i++) { if ($xaml -like "*x:Name=`"user_group_pick_$i`"*") { $groups[$i].Name } })
        $picked | Should -Be @('GG-Accueil', 'GG-VPN')
        $unread = [array]::IndexOf(@($groups | ForEach-Object Name), 'nord.demo.local')
        $unread | Should -BeGreaterThan -1
        $xaml | Should -BeLike "*x:Name=`"user_group_$unread`" Grid.Column=`"1`" Text=`"nord.demo.local`"*"
        $xaml | Should -BeLike '*groupes de ce domaine non lus : Le serveur ne répond pas*'
    }

    It 'Gives Groupes a box to filter it for Hugo Tremblay (11 groups), not for Julie Bertrand (4) (#322)' {
        $hugo = Read-TestUser 'Hugo Tremblay'
        @($hugo.Groups).Count | Should -Be 11
        $xaml = [System.Net.WebUtility]::HtmlDecode((Get-UserGroupXaml $hugo))
        $xaml | Should -BeLike '*x:Name="user_group_filter"*Tag="Filtrer les groupes"*'
        $xaml | Should -BeLike '*x:Name="user_group_filter_none"*Text="Aucun groupe."*'
        # What the box matches: each row's name and detail.
        $metal = [array]::IndexOf(@($hugo.Groups | ForEach-Object Name), 'Atelier-Métal')
        $xaml | Should -BeLike "*x:Name=`"user_group_row_$metal`" Tag=`"Atelier-Métal Sécurité, Globale · Soudure et découpe`"*"
        Get-UserGroupXaml (Read-TestUser 'Julie Bertrand') | Should -Not -BeLike '*user_group_filter*'
    }
}

Describe "Groupes' filter (#322)" {
    It "Matches '<Filter>' in '<Text>': <Expected>" -ForEach @(
        @{ Text = 'Atelier-Métal Sécurité, Globale · Soudure et découpe'; Filter = 'metal'; Expected = $true }
        @{ Text = 'Atelier-Metal'; Filter = 'MÉTAL'; Expected = $true }
        @{ Text = 'Atelier-Bois Sécurité, Globale · Menuiserie'; Filter = 'menuis'; Expected = $true }
        @{ Text = 'Atelier-Bois Sécurité, Globale · Menuiserie'; Filter = '  bois  '; Expected = $true }
        @{ Text = 'Atelier-Bois Sécurité, Globale · Menuiserie'; Filter = 'domaine local'; Expected = $false }
        @{ Text = 'Atelier-Bois'; Filter = ''; Expected = $true }
        @{ Text = ''; Filter = 'bois'; Expected = $false }
    ) {
        Test-DetailFilterMatch $Text $Filter | Should -Be $Expected
    }

    It 'Hides the rows it does not match, a ticked one still ticked, and says when none is left' {
        $list = [System.Windows.Markup.XamlReader]::Parse(@'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <TextBox x:Name="user_group_filter"/>
  <Border x:Name="user_group_row_0" Tag="Atelier-Bois Menuiserie"><CheckBox x:Name="user_group_pick_0" IsChecked="True"/></Border>
  <Border x:Name="user_group_row_1" Tag="Atelier-Métal Soudure" BorderThickness="0,1,0,0"/>
  <Border x:Name="user_group_row_2" Tag="Atelier-Stock Pièces" BorderThickness="0,1,0,0"/>
  <TextBlock x:Name="user_group_filter_none" Visibility="Collapsed"/>
</StackPanel>
'@)
        $box = $list.FindName('user_group_filter')
        $shown = { @(0..2 | Where-Object { $list.FindName("user_group_row_$_").Visibility -eq 'Visible' }) -join ',' }
        $box.Text = 'metal'
        Update-DetailFilter $box
        & $shown | Should -BeExactly '1'
        $list.FindName('user_group_pick_0').IsChecked | Should -BeTrue
        # The first row shown has no line above it, as the list's first row.
        $list.FindName('user_group_row_1').BorderThickness.Top | Should -Be 0
        $list.FindName('user_group_filter_none').Visibility | Should -Be 'Collapsed'
        $box.Text = 'zzz'
        Update-DetailFilter $box
        & $shown | Should -BeExactly ''
        $list.FindName('user_group_filter_none').Visibility | Should -Be 'Visible'
        $box.Text = ''
        Update-DetailFilter $box
        & $shown | Should -BeExactly '0,1,2'
        $list.FindName('user_group_row_1').BorderThickness.Top | Should -Be 1
        $list.FindName('user_group_pick_0').IsChecked | Should -BeTrue
    }
}

Describe "A user's changes go to the DC its Propriétés read from" {
    # The fake AD is one store: it can't show a change missing on the PDC. What it can show is that the changes go to
    # the server the reads use (Read-UserDetail's Server), so a window read again at once sees them.
    BeforeAll {
        $script:Marc = (Get-ADUser -Server demo.local -LDAPFilter '(anr=Marc Durand)' | Select-Object -First 1).DistinguishedName
        $script:MarcRow = [pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = $script:Marc; Password = ''; PasswordTone = $null }
    }

    BeforeEach {
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        Clear-FakeADLog
        $script:DomainCache.Clear()
    }

    AfterEach {
        $env:REPERE_FAKEAD_LOG = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $null
        $script:DomainCache.Clear()
    }

    It "Sends a change from the page to the domain's PDC, looked up once, where Propriétés then reads it" {
        $server = Invoke-UserChange 'demo.local' { param($server) Enable-ADAccount -Server $server -Identity $script:Marc -ErrorAction Stop }
        $server | Should -BeExactly 'dc1.demo.local'
        $null = Invoke-UserChange 'demo.local' { param($server) Enable-ADAccount -Server $server -Identity $script:Marc -ErrorAction Stop }
        @(Read-FakeADLog | Where-Object Command -eq 'Get-ADDomain').Count | Should -Be 1
        $detail = Read-UserDetail $script:MarcRow $script:DomainCache['demo.local']
        $detail.Server | Should -BeExactly $server
        @(Read-FakeADLog | Where-Object Command -eq 'Enable-ADAccount' | ForEach-Object Server) | Should -Be @($server, $server)
        # The PDC found for a change comes without the policy: Propriétés reads it.
        (Get-SectionRow $detail 'Verrouillage' 'policy')[1] | Should -BeLike '5 mauvais mots de passe*'
    }

    It 'Sends a change where the next read goes, for a window opened during an outage too, once the PDC is tried again' {
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = [datetime]::UtcNow.AddMinutes(-4); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        (Read-UserDetail $script:MarcRow $script:DomainCache['demo.local']).Server | Should -BeExactly 'dc2.demo.local'
        # Five minutes on, the PDC back: the window's change and its read again both go to the PDC, not the DC it read on.
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = [datetime]::UtcNow.AddMinutes(-6); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        Clear-FakeADLog
        Invoke-UserChange 'demo.local' { param($server) Enable-ADAccount -Server $server -Identity $script:Marc -ErrorAction Stop } |
            Should -BeExactly 'dc1.demo.local'
        (Read-UserDetail $script:MarcRow $script:DomainCache['demo.local']).Server | Should -BeExactly 'dc1.demo.local'
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Enable-ADAccount' -or ($_.Command -eq 'Get-ADUser' -and $_.Identity) } | ForEach-Object Server | Sort-Object -Unique) |
            Should -Be @('dc1.demo.local')
    }

    It "Makes the change on one other DC when the PDC doesn't answer, and the next ones there without trying the PDC" {
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        $server = Invoke-UserChange 'demo.local' { param($server) Unlock-ADAccount -Server $server -Identity $script:Marc -ErrorAction Stop }
        $server | Should -BeExactly 'dc2.demo.local'
        $null = Invoke-UserChange 'demo.local' { param($server) Unlock-ADAccount -Server $server -Identity $script:Marc -ErrorAction Stop }
        @(Read-FakeADLog | Where-Object Command -eq 'Unlock-ADAccount' | ForEach-Object Server) | Should -Be @('dc1.demo.local', 'dc2.demo.local', 'dc2.demo.local')
        (Get-ADUser -Server demo.local -Identity $script:Marc -Properties LockedOut).LockedOut | Should -BeFalse
        # Propriétés reads there too, the PDC not tried, and its card says why.
        Clear-FakeADLog
        $detail = Read-UserDetail $script:MarcRow $script:DomainCache['demo.local']
        $detail.Server | Should -BeExactly 'dc2.demo.local'
        $detail.PdcProblem | Should -BeLike 'Unable to contact the server*'
        @(Read-FakeADLog | Where-Object { $_.Server -like 'dc1.*' }) | Should -BeNullOrEmpty
    }

    It "Finds another DC once when the one in the PDC's place stops answering too, for the changes and the reads" {
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local;dc2.demo.local'
        $stale = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = [datetime]::UtcNow.AddMinutes(-1); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        $script:DomainCache['demo.local'] = $stale
        Invoke-UserChange 'demo.local' { param($server) Enable-ADAccount -Server $server -Identity $script:Marc -ErrorAction Stop } |
            Should -BeExactly 'dc3.demo.local'
        @(Read-FakeADLog | Where-Object Command -eq 'Enable-ADAccount' | ForEach-Object Server) | Should -Be @('dc2.demo.local', 'dc3.demo.local')
        $script:DomainCache['demo.local'].Fallback | Should -BeExactly 'dc3.demo.local'
        # Why the PDC isn't used stays the PDC's.
        $script:DomainCache['demo.local'].PdcProblem | Should -BeExactly 'down'
        # A read that began with the old entry finds the new DC too, rather than failing.
        $detail = Read-UserDetail $script:MarcRow $stale
        $detail.Server | Should -BeExactly 'dc3.demo.local'
        $detail.PdcProblem | Should -BeExactly 'down'
    }

    It 'Tries the PDC again 5 minutes after it failed' {
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = [datetime]::UtcNow.AddMinutes(-4); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        Get-UserServer 'demo.local' | Should -BeExactly 'dc2.demo.local'
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = [datetime]::UtcNow.AddMinutes(-6); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        Get-UserServer 'demo.local' | Should -BeExactly 'dc1.demo.local'
    }

    It 'Keeps a PDC found down by a change made while a read went on, over what the read found' {
        $started = [datetime]::UtcNow.AddSeconds(-10)
        $read = @{ Pdc = 'dc1.demo.local'; Policy = $script:Policy; Server = 'dc1.demo.local'; PdcDown = $null; PdcProblem = $null; Started = $started }
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $started.AddSeconds(5); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        Update-DomainCache 'demo.local' $read
        $script:DomainCache['demo.local'].Fallback | Should -BeExactly 'dc2.demo.local'
        $script:DomainCache['demo.local'].Policy | Should -Be $script:Policy
        # Found down before the read began: the read, which reached the PDC, is newer.
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $started.AddSeconds(-5); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        Update-DomainCache 'demo.local' $read
        $script:DomainCache['demo.local'].PdcDown | Should -BeNullOrEmpty
        $script:DomainCache['demo.local'].Fallback | Should -BeNullOrEmpty
    }

    It 'Uses the domain rather than a DC the locator finds that is the PDC' {
        Get-DomainFallback 'demo.local' 'dc1.demo.local' | Should -BeExactly 'demo.local'
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        Get-DomainFallback 'demo.local' 'dc1.demo.local' | Should -BeExactly 'dc2.demo.local'
    }

    It "Falls back the same for a group of the user's domain, not for another domain's" {
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $null; PdcProblem = $null; Fallback = $null }
        $group = 'CN=GG-VPN,OU=Groupes,DC=demo,DC=local'
        $server, $member = Get-UserAsMember $script:MarcRow $group @{}
        $null = Invoke-UserChange 'demo.local' { param($server) Add-ADGroupMember -Server $server -Identity $group -Members $member -ErrorAction Stop } $server
        @(Read-FakeADLog | Where-Object Command -eq 'Add-ADGroupMember' | ForEach-Object Server)[-1] | Should -BeExactly 'dc2.demo.local'
        $script:DomainCache['demo.local'].Fallback | Should -BeExactly 'dc2.demo.local'
        (Get-ADGroup -Server demo.local -Identity $group -Properties member).member | Should -Contain $script:Marc
        $null = Invoke-UserChange 'demo.local' { param($server) Remove-ADGroupMember -Server $server -Identity $group -Members $member -Confirm:$false -ErrorAction Stop } $server
        # Another domain's DC that doesn't answer isn't the PDC: its error stands.
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        { Invoke-UserChange 'demo.local' { param($server) Get-ADGroup -Server $server -Identity 'CN=GU-Postes-Nord,OU=Groupes,DC=nord,DC=demo,DC=local' -ErrorAction Stop } 'nord.demo.local' } |
            Should -Throw 'Unable to contact the server*'
    }

    It 'Throws any other error, without trying elsewhere' {
        $script:Tries = 0
        { Invoke-UserChange 'demo.local' { param($server) $script:Tries++; throw "Access is denied ($server)" } } | Should -Throw 'Access is denied (dc1.demo.local)'
        $script:Tries | Should -Be 1
    }

    It "Uses the domain when its PDC can't be looked up, without looking it up again for a while" {
        $env:REPERE_FAKEAD_UNREACHABLE = 'demo.local'
        Get-UserServer 'demo.local' | Should -BeExactly 'demo.local'
        Get-UserServer 'demo.local' | Should -BeExactly 'demo.local'
        @(Read-FakeADLog | Where-Object Command -eq 'Get-ADDomain').Count | Should -Be 1
    }

    It 'Knows a DC that did not answer, even wrapped in another error' {
        $down = [System.Exception]::new('Unable to contact the server. This may be because this server does not exist.')
        $wrapped = [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new('Failed.', $down), 'Test', 'NotSpecified', $null)
        Test-ServerDown $wrapped | Should -BeTrue
        Test-ServerDown ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Access is denied'), 'Test', 'NotSpecified', $null)) | Should -BeFalse
    }

    It 'Has no change to a user that names its server other than through Invoke-UserChange' {
        # Each write of UserDetails.ps1 and UserPage.ps1 to a user takes the server Invoke-UserChange gives it.
        $writes = 'Unlock-ADAccount|Enable-ADAccount|Disable-ADAccount|Set-ADAccountPassword|Set-ADUser|Set-ADAccountExpiration|Clear-ADAccountExpiration|Add-ADGroupMember|Remove-ADGroupMember'
        $found = foreach ($name in 'UserDetails.ps1', 'UserPage.ps1') {
            Select-String -LiteralPath (Join-Path $script:RepereSource $name) -Pattern "\b($writes)\b.*-Server\s+(?!\`$server\b)\S+" |
                ForEach-Object { "$($name):$($_.LineNumber): $($_.Line.Trim())" }
        }
        @($found) | Should -BeNullOrEmpty
    }
}

Describe 'Ajouter à un groupe: a second, red confirmation for a privileged group (#233)' {
    BeforeAll {
        # Show-Dialog is the main script's, which the tests don't load: one that keeps what it's asked to show, and
        # answers OK when $script:Answer says so.
        function Show-Dialog {
            param([string]$Title, [string]$Heading, [string[]]$Names, [string]$Icon, [string]$Tone, $Owner, [string]$Message, [string]$OkText,
                  [switch]$CancelIsDefault, [hashtable]$State, [scriptblock]$OnOk)
            $script:Shown.Add(@{ Heading = $Heading; Names = $Names; Tone = $Tone; Message = $Message; OkText = $OkText; CancelIsDefault = [bool]$CancelIsDefault })
            if ($script:Answer) { & $OnOk $State }
        }
        $script:Privileged = [pscustomobject]@{ Name = 'Admins du domaine'; Privileged = $true }
        $script:Plain = [pscustomobject]@{ Name = 'GG-VPN'; Privileged = $false }
    }

    BeforeEach {
        $script:Shown = [System.Collections.Generic.List[object]]::new()
        $script:Answer = $false
        $script:Added = $null
        $script:OnOk = { param($dialog) $script:Added = $dialog.Groups }
    }

    It 'Adds at once when no group ticked is privileged, as before' {
        Confirm-PrivilegedGroup @($script:Plain) 'Julie Bertrand' $null @{ Groups = @($script:Plain) } $script:OnOk
        $script:Shown | Should -BeNullOrEmpty
        @($script:Added).Name | Should -Be @('GG-VPN')
    }

    It 'Names the privileged group, in red, Annuler the default, and adds nothing when cancelled' {
        Confirm-PrivilegedGroup @($script:Plain, $script:Privileged) 'Julie Bertrand' $null @{ Groups = @($script:Plain, $script:Privileged) } $script:OnOk
        $script:Shown | Should -HaveCount 1
        $script:Shown[0].Heading | Should -BeExactly 'Ajouter Julie Bertrand à Admins du domaine ?'
        $script:Shown[0].Message | Should -BeLike "Admins du domaine est un groupe privilégié de l'AD : *droits sur tout le domaine. GG-VPN est ajouté aussi."
        $script:Shown[0].Names | Should -BeNullOrEmpty
        $script:Shown[0].Tone | Should -BeExactly 'danger'
        $script:Shown[0].CancelIsDefault | Should -BeTrue
        $script:Shown[0].OkText | Should -BeExactly 'Ajouter'
        $script:Added | Should -BeNullOrEmpty
    }

    It 'Adds every group ticked once confirmed, and names several privileged ones as chips' {
        $script:Answer = $true
        $other = [pscustomobject]@{ Name = 'GG-Projet-2019'; Privileged = $true }
        Confirm-PrivilegedGroup @($script:Privileged, $script:Plain, $other) '3 ordinateurs' $null @{ Groups = @($script:Privileged, $script:Plain, $other) } $script:OnOk
        $script:Shown[0].Heading | Should -BeExactly 'Ajouter 3 ordinateurs à 2 groupes privilégiés ?'
        $script:Shown[0].Names | Should -Be @('Admins du domaine', 'GG-Projet-2019')
        $script:Shown[0].Message | Should -BeLike 'Ces groupes sont des groupes privilégiés *domaine. GG-VPN est ajouté aussi.'
        @($script:Added).Name | Should -Be @('Admins du domaine', 'GG-VPN', 'GG-Projet-2019')
    }
}

Describe 'Propriétés: Tout développer and Tout réduire stay in reach (#270)' {
    It 'Puts them in the window, above the cards and outside what scrolls, as Caractéristiques does' {
        $window = [xml]$script:UserDetailXaml
        $names = [System.Xml.XmlNamespaceManager]::new($window.NameTable)
        $names.AddNamespace('p', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
        $names.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
        foreach ($name in 'user_detail_expand_all', 'user_detail_collapse_all') {
            $button = $window.SelectSingleNode("//p:Button[@x:Name='$name']", $names)
            $button | Should -Not -BeNullOrEmpty -Because "$name is the window's"
            $button.SelectSingleNode('ancestor::p:ScrollViewer', $names) | Should -BeNullOrEmpty -Because "$name must not scroll away"
        }
    }

    It "Leaves them out of the cards' panel, a user's and a group's, which scrolls" {
        $script:DetailPanelXaml | Should -Not -BeLike '*_expand_all*'
        $script:DetailPanelXaml | Should -Not -BeLike '*_collapse_all*'
    }

    It 'Does nothing, and saves nothing, while a message stands in place of the cards' {
        Mock Save-Appearance {}
        Set-DetailSectionAll (New-DetailMessage 'Lecture…') $false
        Should -Invoke Save-Appearance -Times 0 -Exactly
    }
}

Describe 'Nouveau mot de passe…: « doit le changer » held for a generated password and the default one (#234)' {
    BeforeEach {
        # The dialog's three choices and its box, as Show-UserResetDialog has them: the box as Paramètres says, here
        # unticked, for a password typed in « Autre ».
        $script:Content = [System.Windows.Markup.XamlReader]::Parse(@"
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <RadioButton x:Name="reset_generated" GroupName="reset234"/>
  <RadioButton x:Name="reset_default" GroupName="reset234"/>
  <RadioButton x:Name="reset_custom" GroupName="reset234"/>
  <CheckBox x:Name="reset_must_change"/>
</StackPanel>
"@)
        $script:Box = $script:Content.FindName('reset_must_change')
        $script:Box.IsChecked = $false
        function Select-Choice([string]$Name) { $script:Content.FindName("reset_$Name").IsChecked = $true }
        function Get-BoxState { "$($script:Box.IsChecked) $(if ($script:Box.IsEnabled) { 'enabled' } else { 'held' })" }
    }

    It 'Holds it ticked when the dialog opens on <Choice>' -ForEach @(
        @{ Choice = 'generated' }, @{ Choice = 'default' }
    ) {
        Select-Choice $Choice
        Register-ResetMustChange $script:Content
        Get-BoxState | Should -BeExactly 'True held'
    }

    It 'Leaves it as Paramètres says for Autre' {
        Select-Choice 'custom'
        Register-ResetMustChange $script:Content
        Get-BoxState | Should -BeExactly 'False enabled'
    }

    It 'Holds it from the default password to a generated one and back, then gives back what it was for Autre' {
        Select-Choice 'default'
        Register-ResetMustChange $script:Content
        Select-Choice 'generated'
        Get-BoxState | Should -BeExactly 'True held'
        Select-Choice 'default'
        Get-BoxState | Should -BeExactly 'True held'
        Select-Choice 'custom'
        Get-BoxState | Should -BeExactly 'False enabled'
    }

    It 'Keeps what was ticked for Autre after the default password' {
        Select-Choice 'custom'
        Register-ResetMustChange $script:Content
        $script:Box.IsChecked = $true
        Select-Choice 'default'
        $script:Box.IsChecked | Should -BeTrue
        Select-Choice 'custom'
        Get-BoxState | Should -BeExactly 'True enabled'
    }

    It 'Set-ResetMustChange asked twice for the same state changes nothing' {
        Set-ResetMustChange $script:Box $true
        Set-ResetMustChange $script:Box $true
        Set-ResetMustChange $script:Box $false
        Get-BoxState | Should -BeExactly 'False enabled'
    }
}

Describe 'Modifier… in Identité, Organisation and Profil: what Enregistrer sends (#138)' {
    BeforeAll {
        $script:Julie = New-TestDetail @{
            DisplayName = 'Julie Bertrand'; GivenName = 'Julie'; Surname = 'Bertrand'; SamAccountName = 'jbertrand'; mail = 'jbertrand@demo.local'
            Title = "Agente d'accueil"; Department = 'Accueil'; Manager = 'CN=Nathalie Lévy,OU=Utilisateurs,DC=demo,DC=local'; OfficePhone = '555 555-0198'
            HomeDrive = 'H:'; HomeDirectory = '\\fichiers\home$\jbertrand'; ScriptPath = 'logon.bat'
        }
        function Get-TypedValue([string]$Card, [hashtable]$Typed = @{}) {
            # What the card's boxes hold once Modifier… is clicked (AD's values), then what's typed over them.
            $values = @{}
            foreach ($field in $script:UserEditFields[$Card]) { if ($field['Attribute']) { $values[$field.Id] = Get-UserEditValue $script:Julie.User $field } }
            foreach ($id in $Typed.Keys) { $values[$id] = $Typed[$id] }
            $values
        }
    }

    It 'Sends nothing for values left as they were' {
        $change = Get-UserEditChange 'Organisation' $script:Julie.User (Get-TypedValue 'Organisation') 'jbertrand'
        $change.Fields | Should -BeNullOrEmpty
        $change.Problems | Should -BeNullOrEmpty
    }

    It 'Replaces only the values changed, trimmed, and clears the ones emptied' {
        $change = Get-UserEditChange 'Organisation' $script:Julie.User (Get-TypedValue 'Organisation' @{ title = '  Chef d''équipe '; phone = ''; company = 'Entreprise' }) 'jbertrand'
        @($change.Fields | ForEach-Object { $_.Id }) | Should -Be @('title', 'company', 'phone')
        $change.Replace.Keys | Sort-Object | Should -Be @('company', 'title')
        $change.Replace['title'] | Should -BeExactly "Chef d'équipe"
        $change.Clear | Should -Be @('telephoneNumber')
        $change.Problems | Should -BeNullOrEmpty
    }

    It 'Counts a change of case as a change, but not in the manager''s DN' {
        $change = Get-UserEditChange 'Organisation' $script:Julie.User (Get-TypedValue 'Organisation' @{ department = 'ACCUEIL'; manager = 'cn=nathalie lévy,ou=utilisateurs,dc=demo,dc=local' }) 'jbertrand'
        @($change.Fields | ForEach-Object { $_.Id }) | Should -Be @('department')
    }

    It 'Never sends the login or the UPN' {
        $change = Get-UserEditChange 'Identité' $script:Julie.User (Get-TypedValue 'Identité' @{ login = 'autre'; upn = 'autre@demo.local'; given_name = 'Julia' }) 'jbertrand'
        $change.Replace.Keys | Should -Be @('givenName')
    }

    It 'Names a value longer than AD takes, and an email that is not one' {
        $change = Get-UserEditChange 'Identité' $script:Julie.User (Get-TypedValue 'Identité' @{ employee = '12345678901234567'; mail = 'julie.bertrand' }) 'jbertrand'
        @($change.Problems | ForEach-Object { $_.Id }) | Should -Be @('mail', 'employee')
        $change.Problems[0].Text | Should -BeExactly 'Courriel : adresse invalide (ex. prenom.nom@domaine.com).'
        $change.Problems[1].Text | Should -BeExactly "Numéro d'employé : 16 caractères au plus (il y en a 17)."
    }

    It 'Leaves a value AD has already, however long, to AD: only what changed is checked' {
        $long = New-TestDetail @{ Description = 'x' * 2000 }
        $change = Get-UserEditChange 'Organisation' $long.User @{ description = 'x' * 2000; title = 'Commise' } 'jbertrand'
        $change.Problems | Should -BeNullOrEmpty
        $change.Replace.Keys | Should -Be @('title')
    }

    It 'Writes a drive letter as AD keeps it, and %username% as the login' {
        $change = Get-UserEditChange 'Profil' $script:Julie.User (Get-TypedValue 'Profil' @{ home_drive = 'p'; home = '\\fichiers\perso$\%USERNAME%'; profile = '\\fichiers\profils\%username%' }) 'jbertrand'
        $change.Problems | Should -BeNullOrEmpty
        $change.Replace['homeDrive'] | Should -BeExactly 'P:'
        $change.Replace['homeDirectory'] | Should -BeExactly '\\fichiers\perso$\jbertrand'
        $change.Replace['profilePath'] | Should -BeExactly '\\fichiers\profils\jbertrand'
    }

    It 'Refuses <Case>' -ForEach @(
        @{ Case = 'a drive that is not a letter'; Typed = @{ home_drive = 'HH' }; Id = 'home_drive'; Text = 'Lecteur : une lettre de A à Z (ex. H:).' }
        @{ Case = 'a drive without a home folder'; Typed = @{ home = '' }; Id = 'home_drive'; Text = 'Lecteur : un lecteur demande un dossier de base.' }
        @{ Case = 'a drive mapped to a local path'; Typed = @{ home = 'D:\Perso' }; Id = 'home'; Text = 'Dossier de base : avec un lecteur, un chemin réseau, \\serveur\partage\…' }
        @{ Case = 'a home folder that is no path'; Typed = @{ home_drive = ''; home = 'fichiers\home' }; Id = 'home'; Text = 'Dossier de base : un chemin réseau, \\serveur\partage\…, ou local, C:\…' }
        @{ Case = 'a roaming profile that is not on the network'; Typed = @{ profile = 'C:\Profils\julie' }; Id = 'profile'; Text = 'Profil itinérant : un chemin réseau, \\serveur\partage\…' }
        @{ Case = 'a share without a folder'; Typed = @{ profile = '\\fichiers' }; Id = 'profile'; Text = 'Profil itinérant : un chemin réseau, \\serveur\partage\…' }
        @{ Case = 'a logon script with a wildcard'; Typed = @{ script = 'logon*.bat' }; Id = 'script'; Text = "Script d'ouverture de session : caractères interdits dans un chemin (* ? `" < > |)." }
    ) {
        $change = Get-UserEditChange 'Profil' $script:Julie.User (Get-TypedValue 'Profil' $Typed) 'jbertrand'
        @($change.Problems | ForEach-Object { $_.Id }) | Should -Be @($Id)
        $change.Problems[0].Text | Should -BeExactly $Text
    }

    It 'Takes a local home folder without a drive, and a drive and folder both emptied' {
        (Get-UserEditChange 'Profil' $script:Julie.User (Get-TypedValue 'Profil' @{ home_drive = ''; home = 'D:\Perso\julie' }) 'jbertrand').Problems | Should -BeNullOrEmpty
        $change = Get-UserEditChange 'Profil' $script:Julie.User (Get-TypedValue 'Profil' @{ home_drive = ''; home = '' }) 'jbertrand'
        $change.Problems | Should -BeNullOrEmpty
        $change.Clear | Should -Be @('homeDrive', 'homeDirectory')
    }
}

Describe 'Modifier…: Enregistrer on the fake AD, one Set-ADUser per card, and a field AD refuses named (#138)' {
    BeforeEach {
        Import-RepereFakeAD
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        Clear-FakeADLog
        $script:DomainCache.Clear()
        function Get-TestRow([string]$Login) {
            $user = Get-ADUser -Server demo.local -LDAPFilter "(sAMAccountName=$Login)" | Select-Object -First 1
            [pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = $user.DistinguishedName; Login = $Login }
        }
        function Get-TestUser($Row) { Get-ADUser -Server demo.local -Identity $Row.DistinguishedName -Properties * }
    }

    AfterEach {
        $env:REPERE_FAKEAD_LOG = $null
        $script:DomainCache.Clear()
        Import-RepereFakeAD
    }

    It 'Sends the card in one Set-ADUser, to the DC Propriétés reads from' {
        $row = Get-TestRow 'jbertrand'
        $change = Get-UserEditChange 'Organisation' (Get-TestUser $row) @{ title = 'Chef'; department = 'Accueil'; company = 'Entreprise Démo'; office = 'Accueil, rez-de-chaussée'
                                                                           manager = ''; phone = '555 555-0199'; mobile = '555 555-0100'; description = '' } 'jbertrand'
        $result = Save-UserEditChange $row $change
        $result.Failed | Should -BeNullOrEmpty
        $result.Saved | Should -Be @('title', 'manager', 'phone', 'mobile')
        $sets = @(Read-FakeADLog | Where-Object Command -eq 'Set-ADUser')
        $sets | Should -HaveCount 1
        $sets[0].Server | Should -BeExactly 'dc1.demo.local'
        $sets[0].Replace | Should -BeExactly 'mobile=555 555-0100;telephoneNumber=555 555-0199;title=Chef'
        $sets[0].Clear | Should -BeExactly 'manager'
        $user = Get-TestUser $row
        $user.Title | Should -BeExactly 'Chef'
        $user.Manager | Should -BeNullOrEmpty
        $user.MobilePhone | Should -BeExactly '555 555-0100'
    }

    It 'Saves the fields AD takes and names the one it refuses, then sends nothing more for those saved' {
        # Jean Bertrand's employee number is one the current user has no right on (DenyAttributes).
        $row = Get-TestRow 'jebertrand'
        $typed = @{ display_name = 'Jean Bertrand'; given_name = 'Jean-Marc'; surname = 'Bertrand'; mail = 'jmbertrand@demo.local'; employee = '99' }
        $change = Get-UserEditChange 'Identité' (Get-TestUser $row) $typed 'jebertrand'
        $result = Save-UserEditChange $row $change
        $result.Saved | Should -Be @('given_name', 'mail')
        $result.Failed | Should -HaveCount 1
        $result.Failed[0].Id | Should -BeExactly 'employee'
        $result.Failed[0].Label | Should -BeExactly "Numéro d'employé"
        $result.Failed[0].Problem | Should -BeExactly 'Insufficient access rights to perform the operation'
        $user = Get-TestUser $row
        $user.GivenName | Should -BeExactly 'Jean-Marc'
        $user.mail | Should -BeExactly 'jmbertrand@demo.local'
        $user.EmployeeID | Should -Not -Be '99'
        # The whole card first, refused whole as AD's one LDAP change is; then each field alone.
        @(Read-FakeADLog | Where-Object Command -eq 'Set-ADUser') | Should -HaveCount 4
        # Enregistrer again, as the card kept what was typed: only the field refused is sent.
        (Get-UserEditChange 'Identité' (Get-TestUser $row) $typed 'jebertrand').Replace.Keys | Should -Be @('employeeID')
    }

    It 'Saves nothing, and names each field, for an account the current user cannot change' {
        $row = Get-TestRow 'nlevy'
        $change = Get-UserEditChange 'Organisation' (Get-TestUser $row) @{ title = 'Directrice générale'; department = 'Direction'; company = 'Entreprise Démo'; office = 'Direction, rez-de-chaussée'
                                                                           manager = ''; phone = '555 555-0154'; mobile = ''; description = '' } 'nlevy'
        $result = Save-UserEditChange $row $change
        $result.Saved | Should -BeNullOrEmpty
        @($result.Failed | ForEach-Object { $_.Id }) | Should -Be @('title')
        (Get-TestUser $row).Title | Should -BeExactly 'Directrice'
    }

    It 'Has the fake AD refuse a whole Set-ADUser for one attribute, as AD does' {
        $row = Get-TestRow 'jebertrand'
        { Set-ADUser -Server demo.local -Identity $row.DistinguishedName -Replace @{ title = 'Chef'; employeeID = '1' } -ErrorAction Stop } |
            Should -Throw 'Insufficient access rights*'
        { Set-ADUser -Server demo.local -Identity $row.DistinguishedName -Replace @{ title = 'x' * 129 } -ErrorAction Stop } | Should -Throw 'A value for the attribute*'
        { Set-ADUser -Server demo.local -Identity $row.DistinguishedName -Replace @{ manager = 'CN=Personne,DC=demo,DC=local' } -ErrorAction Stop } | Should -Throw 'The name reference is invalid'
        (Get-TestUser $row).Title | Should -BeExactly 'Technicien'
    }

    It 'Finds a manager by the start of a name in each domain, not the user himself' {
        $julie = (Get-TestRow 'jbertrand').DistinguishedName
        $found = Get-UserManagerChoice @('demo.local', 'nord.demo.local') 'bert' $julie
        @($found.Items | ForEach-Object { $_.Name }) | Should -Be @('Jean Bertrand', 'Paul Bertrand')
        $found.Items[1].Details | Should -BeExactly 'pbertrand · Magasinier · Entrepôt · nord.demo.local'
        $found.Unsearched | Should -BeNullOrEmpty
    }
}