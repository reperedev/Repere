# Ajouter à un groupe… and Retirer d'un groupe… for a selection, without their dialogs, with the fake AD: the members
# put in (Add-SelectionGroupMember) or taken out (Read-SelectionDirectGroup, Remove-SelectionGroupMember) one call per
# group, a line per member and group, and what the status bar and the heading say.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')

    function Get-TestUserMember([string[]]$Logins) {
        # Users as the Utilisateurs page selects them, then as the group changes take them.
        $rows = foreach ($login in $Logins) {
            $domain = if ($login -eq 'pbertrand') { 'nord.demo.local' } else { 'demo.local' }
            $user = Get-ADUser -Server $domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$login))"
            [pscustomobject]@{ Name = [string]$user.Name; Login = $login; Domain = $domain; DistinguishedName = [string]$user.DistinguishedName }
        }
        @(ConvertTo-GroupMember $rows 'User')
    }

    function Get-TestGroupItem([string]$Name, [string]$Domain = 'demo.local') {
        # A group as the picker lists it.
        $group = Get-ADGroup -Server $Domain -LDAPFilter "(&(objectCategory=group)(name=$Name))"
        [pscustomobject]@{ Name = [string]$group.Name; DistinguishedName = [string]$group.DistinguishedName; Details = '' }
    }

    function Get-GroupMemberDN([string]$Name, [string]$Domain = 'demo.local') {
        $dn = (Get-TestGroupItem $Name $Domain).DistinguishedName
        @((Get-ADGroup -Server $Domain -Identity $dn -Properties member).member)
    }

    function Get-LoggedCall([string]$Command) {
        # Each call as « group: member;member », by the group's name.
        @(Read-FakeADLog | Where-Object Command -eq $Command | ForEach-Object { "$(Get-DnName $_.Identity): $(@($_.Members -split ';' | ForEach-Object { Get-DnName $_ }) -join ';')" })
    }
}

Describe 'Add-SelectionGroupMember, with the fake AD' {
    BeforeEach {
        # Each test from the same AD: they change it.
        Import-RepereFakeAD
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        Clear-FakeADLog
    }
    AfterEach { $env:REPERE_FAKEAD_LOG = $null }

    It 'Adds them all with one call per group, and says who was in already, without reading the groups' {
        $members = Get-TestUserMember 'jbertrand', 'jebertrand', 'lperrin'
        Clear-FakeADLog
        $lines = @(Add-SelectionGroupMember @((Get-TestGroupItem 'GG-VPN'), (Get-TestGroupItem 'GG-Ventes')) $members)
        $lines | Should -Be @(
            '✔ jbertrand : déjà dans GG-VPN'
            '✔ jebertrand : déjà dans GG-VPN'
            '✔ lperrin : ajouté à GG-VPN'
            '✔ jbertrand : ajouté à GG-Ventes'
            '✔ jebertrand : ajouté à GG-Ventes'
            '✔ lperrin : ajouté à GG-Ventes'
        )
        Get-LoggedCall 'Add-ADGroupMember' | Should -Be @('GG-VPN: Léa Perrin', 'GG-Ventes: Julie Bertrand;Jean Bertrand;Léa Perrin')
        # Who's in was known from their own groups, one search for the three: no group's members were read.
        @(Read-FakeADLog | Where-Object Command -eq 'Get-ADObject').Count | Should -Be 1
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Get-ADGroup' -and $_.Identity }).Count | Should -Be 0
        Get-GroupMemberDN 'GG-Ventes' | Should -Contain $members[2].DistinguishedName
    }

    It 'Tries each one alone when AD refuses the call, so the others still go in' {
        # A global group of demo.local can't take Paul Bertrand, of nord.demo.local.
        $members = Get-TestUserMember 'jbertrand', 'pbertrand', 'lperrin'
        $lines = @(Add-SelectionGroupMember @(Get-TestGroupItem 'GG-Ventes') $members)
        $lines[0] | Should -BeExactly '✔ jbertrand : ajouté à GG-Ventes'
        $lines[1] | Should -BeLike '✖ pbertrand : non ajouté à GG-Ventes (*cross-domain*)'
        $lines[2] | Should -BeExactly '✔ lperrin : ajouté à GG-Ventes'
        @(Get-LoggedCall 'Add-ADGroupMember').Count | Should -Be 4
    }

    It "Gives a group of another domain those of its own by DN, the others as read in theirs" {
        $members = Get-TestUserMember 'jbertrand', 'pbertrand'
        $lines = @(Add-SelectionGroupMember @(Get-TestGroupItem 'DL-Imprimantes-Nord' 'nord.demo.local') $members)
        $lines | Should -Be @('✔ jbertrand : ajouté à DL-Imprimantes-Nord', '✔ pbertrand : ajouté à DL-Imprimantes-Nord')
        Get-GroupMemberDN 'DL-Imprimantes-Nord' 'nord.demo.local' | Should -Contain $members[0].DistinguishedName
        # Julie Bertrand read in her domain once, by a search rather than alone.
        $reads = @(Read-FakeADLog | Where-Object Command -eq 'Get-ADUser' | Select-Object -Skip 2)
        @($reads | Where-Object Identity).Count | Should -Be 0
        @($reads | Where-Object { $_.LDAPFilter -like '(|(distinguishedName=CN=Julie Bertrand,*' -and $_.Server -eq 'demo.local' }).Count | Should -Be 1
    }

    It 'Counts one found already in by AD as done, and tries the others alone' {
        $pending = @(foreach ($login in 'a', 'b', 'c') { @{ Member = @{ Label = $login }; As = $login } })
        $script:Calls = 0
        $change = { param($Accounts) $script:Calls++; if (@($Accounts) -contains 'b') { throw 'The specified account name is already a member of the group' } }
        $lines = @(Invoke-GroupMemberBatch $pending $change '✔ {0} : ajouté à {1}' '✖ {0} : non ajouté à {1} ({2})' 'G' $script:GroupAlreadyIn)
        $lines | Should -Be @('✔ a : ajouté à G', '✔ b : ajouté à G', '✔ c : ajouté à G')
        $script:Calls | Should -Be 4
    }

    It 'Says each member was not added to a group it may not change, without trying them one by one' {
        $lines = @(Add-SelectionGroupMember @(Get-TestGroupItem 'Admins du domaine') (Get-TestUserMember 'jbertrand', 'lperrin'))
        $lines | Should -HaveCount 2
        $lines | ForEach-Object { $_ | Should -BeLike '✖ * : non ajouté à Admins du domaine (*access rights*)' }
        @(Get-LoggedCall 'Add-ADGroupMember').Count | Should -Be 1
    }

    It 'Puts computers in a group, by their DN' {
        $rows = Get-ADComputer -Server 'demo.local' -Filter "Name -like 'ORD-0*'" | Where-Object Name -in 'ORD-01', 'ORD-02' | Sort-Object Name |
            ForEach-Object { [pscustomobject]@{ ComputerName = $_.Name; OU = $_.DistinguishedName; Domain = 'demo.local' } }
        $lines = @(Add-SelectionGroupMember @(Get-TestGroupItem 'GG-Postes-Accueil') @(ConvertTo-GroupMember $rows 'Computer'))
        $lines | Should -Be @('✔ ORD-01 : déjà dans GG-Postes-Accueil', '✔ ORD-02 : ajouté à GG-Postes-Accueil')
    }
}

Describe 'Read-SelectionDirectGroup and Remove-SelectionGroupMember, with the fake AD' {
    BeforeEach {
        Import-RepereFakeAD
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        Clear-FakeADLog
    }
    AfterEach { $env:REPERE_FAKEAD_LOG = $null }

    It 'Offers the groups one of them is a direct member of, each with those in it' {
        $members = Get-TestUserMember 'jbertrand', 'jebertrand'
        $read = Read-SelectionDirectGroup $members
        @($read.Groups | ForEach-Object { "$($_.Name): $(@($_.Members | ForEach-Object Label) -join ',')" }) | Should -Be @('GG-Accueil: jbertrand', 'GG-VPN: jbertrand,jebertrand')
        $read.Groups[0].Domain | Should -BeExactly 'demo.local'
        $read.Unread | Should -BeNullOrEmpty
    }

    It 'Says who could not be read, and offers the groups of the others' {
        $gone = @(ConvertTo-GroupMember @([pscustomobject]@{ Name = 'Personne'; Login = 'personne'; Domain = 'demo.local'; DistinguishedName = 'CN=Personne,OU=Utilisateurs,DC=demo,DC=local' }) 'User')
        $read = Read-SelectionDirectGroup (@(Get-TestUserMember 'lperrin') + $gone)
        @($read.Groups.Name) | Should -Be @('GG-Accueil')
        $read.Unread.Count | Should -Be 1
        $read.Unread[0].Member.Label | Should -BeExactly 'personne'
        $read.Unread[0].Problem | Should -BeLike "Cannot find an object with identity: 'CN=Personne,*' under: 'demo.local'."
    }

    It 'Reads them with one search per domain, by their DNs, rather than one by one' {
        $members = Get-TestUserMember 'jbertrand', 'jebertrand', 'pbertrand'
        Clear-FakeADLog
        $read = Read-SelectionDirectGroup $members
        @($read.Groups | ForEach-Object { "$($_.Name): $(@($_.Members | ForEach-Object Label) -join ',')" }) | Should -Be @('GG-Accueil: jbertrand', 'GG-VPN: jbertrand,jebertrand')
        $searches = @(Read-FakeADLog | Where-Object Command -eq 'Get-ADObject')
        @($searches | ForEach-Object Server | Sort-Object) | Should -Be @('demo.local', 'nord.demo.local')
        $searches[0].LDAPFilter | Should -BeLike '(|(distinguishedName=CN=*)(distinguishedName=CN=*))'
        @(Read-FakeADLog | Where-Object { $_.Command -in 'Get-ADUser', 'Get-ADComputer' }).Count | Should -Be 0
    }

    It 'Asks for 100 objects at most per search' {
        Import-RepereFakeAD -ExtraComputers 150
        Clear-FakeADLog
        $rows = Get-ADComputer -Server 'demo.local' -Filter "Name -like 'PC-*'" | ForEach-Object { [pscustomobject]@{ ComputerName = $_.Name; OU = $_.DistinguishedName; Domain = 'demo.local' } }
        @($rows).Count | Should -Be 150
        $read = Read-SelectionDirectGroup @(ConvertTo-GroupMember $rows 'Computer')
        $read.Unread | Should -BeNullOrEmpty
        @(Read-FakeADLog | Where-Object Command -eq 'Get-ADObject').Count | Should -Be 2
    }

    It 'Takes those of the selection in a group out of it with one call, the others left in' {
        $members = Get-TestUserMember 'jbertrand', 'jebertrand'
        $read = Read-SelectionDirectGroup $members
        Clear-FakeADLog
        $lines = @(Remove-SelectionGroupMember @($read.Groups | Where-Object Name -eq 'GG-VPN'))
        $lines | Should -Be @('✔ jbertrand : retiré de GG-VPN', '✔ jebertrand : retiré de GG-VPN')
        Get-LoggedCall 'Remove-ADGroupMember' | Should -Be @('GG-VPN: Julie Bertrand;Jean Bertrand')
        Get-GroupMemberDN 'GG-VPN' | Should -BeNullOrEmpty
        # Léa Perrin, in GG-Accueil but not selected, stays there.
        Get-GroupMemberDN 'GG-Accueil' | Should -HaveCount 2
    }
}

Describe 'Get-SelectionGroupSummary and Get-SelectionGroupHeading' {
    BeforeAll {
        $script:One = @(@{ Label = 'jbertrand'; Name = 'Julie Bertrand'; Kind = 'User' })
        $script:Three = @(1..3 | ForEach-Object { @{ Label = "ORD-0$_"; Name = "ORD-0$_"; Kind = 'Computer' } })
    }

    It 'Names the member and the groups for one, counts them for many' {
        (Get-SelectionGroupSummary $script:One @('GG-VPN', 'GG-Ventes')) -f 2 | Should -BeExactly '✔ jbertrand dans GG-VPN et GG-Ventes'
        (Get-SelectionGroupSummary $script:Three @('GG-Postes-Accueil')) -f 3 | Should -BeExactly '✔ 3 ordinateurs dans GG-Postes-Accueil'
        (Get-SelectionGroupSummary $script:Three @('A', 'B') -Remove) -f 6 | Should -BeExactly '✔ 3 ordinateurs retirés de 2 groupes'
    }

    It 'Keeps the braces of a group name through the report formatting it' {
        (Get-SelectionGroupSummary $script:One @('GG-{Test}')) -f 1 | Should -BeExactly '✔ jbertrand dans GG-{Test}'
    }

    It 'Says who in the heading' {
        Get-SelectionGroupHeading $script:One | Should -BeExactly 'Ajouter Julie Bertrand à des groupes'
        Get-SelectionGroupHeading $script:Three -Remove | Should -BeExactly 'Retirer 3 ordinateurs de groupes'
    }

    It "Says who a privileged group's confirmation is for (Get-SelectionGroupWho)" {
        Get-SelectionGroupWho $script:One | Should -BeExactly 'Julie Bertrand'
        Get-SelectionGroupWho $script:Three | Should -BeExactly '3 ordinateurs'
        Get-SelectionGroupWho @($script:One[0], $script:One[0]) | Should -BeExactly '2 utilisateurs'
    }
}

Describe "The selection's groups read and changed on each domain's PDC (#256)" {
    # Where a user's Propriétés reads its groups. The servers chosen on the window's thread (Get-GroupServerMap) as
    # Start-SelectionGroupChange gives them to its runspace, then what the change found kept there (Register-GroupServerDown).
    BeforeEach {
        Import-RepereFakeAD
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        $script:DomainCache.Clear()
        $script:GroupServers = Get-GroupServerMap 'demo.local', 'nord.demo.local'
        $script:GroupServersDown = @{}
        Clear-FakeADLog
    }
    AfterEach {
        $env:REPERE_FAKEAD_LOG = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $null
        $script:GroupServers = @{}
        $script:GroupServersDown = @{}
    }

    It "Chooses each domain's PDC" {
        $script:GroupServers['demo.local'] | Should -BeExactly 'dc1.demo.local'
        $script:GroupServers['nord.demo.local'] | Should -BeExactly 'dc1.nord.demo.local'
    }

    It 'Reads their groups and adds them on the PDC' {
        $members = Get-TestUserMember 'jbertrand', 'lperrin'
        Clear-FakeADLog
        $null = Add-SelectionGroupMember @(Get-TestGroupItem 'GG-Ventes') $members
        @(Read-FakeADLog | Where-Object Command -in 'Get-ADObject', 'Add-ADGroupMember' | ForEach-Object { "$($_.Command) $($_.Server)" }) |
            Should -Be @('Get-ADObject dc1.demo.local', 'Add-ADGroupMember dc1.demo.local')
        $script:GroupServersDown.Count | Should -Be 0
    }

    It 'Reads their direct groups and removes them on the PDC' {
        $members = Get-TestUserMember 'jbertrand'
        $read = Read-SelectionDirectGroup $members
        $null = Remove-SelectionGroupMember @($read.Groups | Where-Object Name -eq 'GG-VPN')
        @(Read-FakeADLog | Where-Object Command -in 'Get-ADObject', 'Remove-ADGroupMember' | ForEach-Object { "$($_.Command) $($_.Server)" }) |
            Should -Be @('Get-ADObject dc1.demo.local', 'Remove-ADGroupMember dc1.demo.local')
    }

    It "Goes to another DC for the rest of the change when the PDC doesn't answer, and says which for the window to keep" {
        $members = Get-TestUserMember 'jbertrand', 'lperrin'
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        Clear-FakeADLog
        $lines = @(Add-SelectionGroupMember @((Get-TestGroupItem 'GG-Ventes'), (Get-TestGroupItem 'GG-VPN')) $members)
        $lines | Should -Contain '✔ lperrin : ajouté à GG-Ventes'
        $lines | Should -Contain '✔ lperrin : ajouté à GG-VPN'
        # The PDC tried once (the read of their groups), then one other DC for everything else.
        $servers = @(Read-FakeADLog | Where-Object Command -in 'Get-ADObject', 'Add-ADGroupMember' | ForEach-Object Server)
        $servers[0] | Should -BeExactly 'dc1.demo.local'
        @($servers | Select-Object -Skip 1 | Sort-Object -Unique) | Should -BeExactly 'dc2.demo.local'
        $script:GroupServers['demo.local'] | Should -BeExactly 'dc2.demo.local'
        $script:GroupServersDown['demo.local'].Server | Should -BeExactly 'dc1.demo.local'
        $script:GroupServersDown['demo.local'].Fallback | Should -BeExactly 'dc2.demo.local'
        # On the window's thread: the PDC kept as down, the DC the change went to used for the next ones.
        Register-GroupServerDown $script:GroupServersDown
        Get-UserServer 'demo.local' | Should -BeExactly 'dc2.demo.local'
    }

    It 'Throws what is not a DC down, without trying elsewhere' {
        $calls = [System.Collections.Generic.List[string]]::new()
        { Invoke-OnGroupServer 'demo.local' { param($Value, $Server) $calls.Add($Server); throw "Access is denied ($Value)" } 'x' } | Should -Throw 'Access is denied (x)'
        @($calls) | Should -Be @('dc1.demo.local')
        $script:GroupServersDown.Count | Should -Be 0
    }
}

Describe 'Test-GroupRefusal: AD''s refusals known by their codes, whatever Windows'' language' {
    BeforeAll {
        # An ADException as the ActiveDirectory module throws it: its Win32 code in ErrorCode, its text in German.
        $script:NewADError = {
            param([string]$Message, [int]$Code)
            $failure = [System.InvalidOperationException]::new($Message)
            Add-Member -InputObject $failure -NotePropertyName ErrorCode -NotePropertyValue $Code
            $failure
        }
    }

    It '<Case>: <Expected>' -ForEach @(
        @{ Case = 'already a member, 1378'; Refusal = 'GroupAlreadyIn'; Failure = { & $NewADError 'Das angegebene Konto ist bereits Mitglied der Gruppe' 1378 }; Expected = $true }
        @{ Case = 'not a member, 1377'; Refusal = 'GroupNotIn'; Failure = { & $NewADError 'Das angegebene Konto ist kein Mitglied der Gruppe' 1377 }; Expected = $true }
        @{ Case = 'insufficient rights, 8344'; Refusal = 'GroupDenied'; Failure = { & $NewADError 'Unzureichende Zugriffsrechte' 8344 }; Expected = $true }
        @{ Case = 'access denied, an UnauthorizedAccessException'; Refusal = 'GroupDenied'; Failure = { [System.UnauthorizedAccessException]::new('Zugriff verweigert') }; Expected = $true }
        @{ Case = 'access denied, a Win32 code'; Refusal = 'GroupDenied'; Failure = { [System.ComponentModel.Win32Exception]::new(5, 'Zugriff verweigert') }; Expected = $true }
        @{ Case = 'another refusal'; Refusal = 'GroupAlreadyIn'; Failure = { & $NewADError 'Unzureichende Zugriffsrechte' 8344 }; Expected = $false }
        @{ Case = 'no code, in German'; Refusal = 'GroupDenied'; Failure = { [System.Exception]::new('Zugriff verweigert') }; Expected = $false }
        @{ Case = 'no code, in French: its text'; Refusal = 'GroupAlreadyIn'; Failure = { [System.Exception]::new('Le compte spécifié est déjà membre du groupe') }; Expected = $true }
        @{ Case = 'no code, in English: its text'; Refusal = 'GroupDenied'; Failure = { [System.Exception]::new('Insufficient access rights to perform the operation') }; Expected = $true }
    ) {
        Test-GroupRefusal (& $Failure) (Get-Variable -Scope Script -Name $Refusal -ValueOnly) | Should -Be $Expected
    }

    It 'Knows the fake AD''s refusals by their codes, as a real AD''s' {
        # A member the group already has: nothing changes.
        $group = Get-TestGroupItem 'GG-Ventes'
        $member = @(Get-GroupMemberDN 'GG-Ventes')[0]
        $member | Should -Not -BeNullOrEmpty
        try { Add-ADGroupMember -Server 'demo.local' -Identity $group.DistinguishedName -Members $member -ErrorAction Stop; $caught = $null }
        catch { $caught = $_.Exception }
        $caught.ErrorCode | Should -Be 1378
        Test-GroupRefusal $caught @{ Pattern = 'never matched'; Code = 1378 } | Should -BeTrue
    }
}