# Groups with the fake AD: a group's members (Read-GroupMember), the groups of a computer, user or group
# (Get-ObjectGroup, Read-TokenGroup) and the domain of a SID (Get-DomainOfSid), checked by what they return and by the
# queries the fake AD logs.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    # 250 more computers in demo.local: Ordinateurs du domaine then has 261 members, more than a list shows.
    Import-RepereFakeAD -ExtraComputers 250

    function Get-TestGroup([string]$Name, [string]$Domain = 'demo.local') {
        # A group as the Propriétés window passes it to Read-GroupMember: its row (domain and DN) and the group read.
        $found = Get-ADGroup -Server $Domain -LDAPFilter "(&(objectCategory=group)(name=$Name))"
        if (@($found).Count -ne 1) { throw "No group $Name in $Domain." }
        @{
            Row = [pscustomobject]@{ Domain = $Domain; DistinguishedName = $found.DistinguishedName; Name = $found.Name }
            Group = Get-ADGroup -Server $Domain -Identity $found.DistinguishedName -Properties Description, MemberOf
        }
    }

    function Get-TestUser([string]$Name, [string]$Domain = 'demo.local', [string[]]$Properties = @('MemberOf', 'PrimaryGroup')) {
        $found = Get-ADUser -Server $Domain -LDAPFilter "(&(objectCategory=person)(objectClass=user)(anr=$Name))"
        if (@($found).Count -ne 1) { throw "No user $Name in $Domain." }
        Get-ADUser -Server $Domain -Identity $found.DistinguishedName -Properties $Properties
    }

    function Get-MemberText($Members) {
        # Each member as « Membership Kind: Name (Domain) », in the list's order.
        @($Members.List | ForEach-Object { "$($_.Membership) $($_.Kind): $($_.Name) ($($_.Domain))" })
    }

    function Get-GroupText($Groups) {
        # Each group as « Membership: Name (Domain) », in the order returned.
        @($Groups | ForEach-Object { "$($_.Membership): $($_.Name) ($($_.Domain))" })
    }

    function Get-LoggedQuery([string]$Command) {
        @(Read-FakeADLog | Where-Object Command -eq $Command)
    }

    function Reset-TestSession {
        # Before each test: an empty log, and what a session keeps found again.
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        Clear-FakeADLog
        $script:GlobalCatalog = $null
        $script:DomainSidMap.Clear()
        $script:DomainCache.Clear()
        $script:GroupServers = @{}
        $script:GroupServersDown = @{}
        $script:MemberListMax = 200
        $script:MemberForeignMax = 50
        $script:domainList = 'demo.local', 'nord.demo.local'
    }

    function Clear-TestSession {
        $env:REPERE_FAKEAD_LOG = $null
        $env:REPERE_FAKEAD_NO_GC = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $null
    }
}
Describe 'Read-GroupMember' {
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It 'Lists 200 members at most, and says there are more (Truncated)' {
        $test = Get-TestGroup 'Ordinateurs du domaine'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        $members.List.Count | Should -Be 200
        $members.Truncated | Should -BeTrue
        @($members.List | Where-Object { $_.Membership -ne 'Principale' -or $_.Kind -ne 'Ordinateur' }) | Should -BeNullOrEmpty
        # Each search asks AD for one more than it can show, never for the whole group.
        @(Get-LoggedQuery 'Get-ADObject').ResultSetSize | Should -Be @(201, 201)
    }

    It 'Is not truncated when every member fits, to the last one' {
        $test = Get-TestGroup 'Utilisateurs du domaine'
        $script:MemberListMax = 9
        $members = Read-GroupMember $test.Row $test.Group ''
        $members.List.Count | Should -Be 9
        $members.Truncated | Should -BeFalse
        $script:MemberListMax = 8
        (Read-GroupMember $test.Row $test.Group '').Truncated | Should -BeTrue
    }

    It 'Lists the accounts whose primary group it is, after the direct members' {
        $test = Get-TestGroup 'Utilisateurs du domaine'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        Get-MemberText $members | Should -Be @(
            'Principale Utilisateur: Hugo Tremblay (demo.local)'
            'Principale Utilisateur: Jean Bertrand (demo.local)', 'Principale Utilisateur: Julie Bertrand (demo.local)'
            'Principale Utilisateur: Léa Perrin (demo.local)', 'Principale Utilisateur: Luc Lefebvre (demo.local)'
            'Principale Utilisateur: Marc Durand (demo.local)', 'Principale Utilisateur: Nathalie Lévy (demo.local)'
            'Principale Utilisateur: Sauvegarde (demo.local)', 'Principale Utilisateur: Sophie Rey (demo.local)'
        )
        $members.Truncated | Should -BeFalse
        $members.Problem | Should -BeNullOrEmpty
        (Get-LoggedQuery 'Get-ADObject')[-1].LDAPFilter | Should -BeExactly '(&(primaryGroupID=513))'
    }

    It 'Lists a global group: its users, their login and OU, in its domain only' {
        $test = Get-TestGroup 'GG-Accueil'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        Get-MemberText $members | Should -Be @('Directe Utilisateur: Julie Bertrand (demo.local)', 'Directe Utilisateur: Léa Perrin (demo.local)')
        $members.List[0].Login | Should -BeExactly 'jbertrand'
        $members.List[0].OUPath | Should -BeExactly 'Utilisateurs'
        $members.List[0].DistinguishedName | Should -BeExactly 'CN=Julie Bertrand,OU=Utilisateurs,DC=demo,DC=local'
        @(Get-LoggedQuery 'Get-ADObject').Server | Sort-Object -Unique | Should -BeExactly 'demo.local'
    }

    It 'Asks AD for the members whose name or login starts with the text, escaped, not by ANR' {
        $test = Get-TestGroup 'GG-Accueil'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group 'jul'
        Get-MemberText $members | Should -Be @('Directe Utilisateur: Julie Bertrand (demo.local)')
        $members.Filter | Should -BeExactly 'jul'
        # ANR would also find the office, the email addresses and phonetic forms (#250).
        $jul = '(|(name=jul*)(sAMAccountName=jul*)(displayName=jul*)(givenName=jul*)(sn=jul*))'
        @(Get-LoggedQuery 'Get-ADObject').LDAPFilter | Should -Be @(
            "(&(memberOf=CN=GG-Accueil,OU=Groupes,DC=demo,DC=local)$jul)", "(&(primaryGroupID=1110)$jul)"
        )
        Get-MemberText (Read-GroupMember $test.Row $test.Group 'lper') | Should -Be @('Directe Utilisateur: Léa Perrin (demo.local)')
        Clear-FakeADLog
        (Read-GroupMember $test.Row $test.Group 'Bertrand (*').List | Should -BeNullOrEmpty
        (Get-LoggedQuery 'Get-ADObject')[0].LDAPFilter | Should -BeExactly ('(&(memberOf=CN=GG-Accueil,OU=Groupes,DC=demo,DC=local)' +
            '(|(name=Bertrand \28\2a*)(sAMAccountName=Bertrand \28\2a*)(displayName=Bertrand \28\2a*)(givenName=Bertrand \28\2a*)(sn=Bertrand \28\2a*)))')
    }

    It 'Searches among the primary group members too' {
        $test = Get-TestGroup 'Utilisateurs du domaine'
        Get-MemberText (Read-GroupMember $test.Row $test.Group 'bert') | Should -Be @(
            'Principale Utilisateur: Jean Bertrand (demo.local)', 'Principale Utilisateur: Julie Bertrand (demo.local)'
        )
    }

    It "Lists a universal group's members of every domain through the global catalog, found once" {
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        Get-MemberText $members | Should -Be @(
            'Directe Groupe: GG-Postes-Accueil (demo.local)', 'Directe Ordinateur: ORD-01 (nord.demo.local)', 'Directe Ordinateur: ORD-04 (demo.local)'
        )
        $members.Problem | Should -BeNullOrEmpty
        $search = (Get-LoggedQuery 'Get-ADObject')[0]
        $search.Server | Should -BeExactly 'dc1.demo.local:3268'
        $search.SearchBase | Should -BeExactly ''
        $null = Read-GroupMember $test.Row $test.Group ''
        @(Get-LoggedQuery 'Get-ADDomainController').Count | Should -Be 1
    }

    It 'Searches each domain when no global catalog answers, and says members may be missing' {
        $env:REPERE_FAKEAD_NO_GC = '1'
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        # A DC of demo.local doesn't know the member list of a group of nord.demo.local.
        Get-MemberText $members | Should -Be @('Directe Ordinateur: ORD-01 (nord.demo.local)')
        $members.Problem | Should -BeLike '*aucun catalogue global ne répond*'
        @(Get-LoggedQuery 'Get-ADObject' | Where-Object LDAPFilter -like '(&(memberOf=*').Server | Should -Be @('nord.demo.local', 'demo.local')
    }

    It 'Looks for a global catalog again at the next read after a lookup that failed' {
        $env:REPERE_FAKEAD_NO_GC = '1'
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        (Read-GroupMember $test.Row $test.Group '').Problem | Should -BeLike '*aucun catalogue global ne répond*'
        $env:REPERE_FAKEAD_NO_GC = $null
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        $members.Problem | Should -BeNullOrEmpty
        $members.List.Count | Should -Be 3
        @(Get-LoggedQuery 'Get-ADDomainController').Count | Should -Be 1
        $members.Catalog | Should -BeExactly 'dc1.demo.local:3268'
    }

    It 'Looks for another global catalog once when the one kept does not answer, and asks it instead' {
        $script:GlobalCatalog = 'gc-ancien.demo.local:3268'
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        $members.Problem | Should -BeNullOrEmpty
        $members.List.Count | Should -Be 3
        @(Get-LoggedQuery 'Get-ADObject' | Where-Object LDAPFilter -like '(&(memberOf=*').Server | Should -Be @('gc-ancien.demo.local:3268', 'dc1.demo.local:3268')
        @(Get-LoggedQuery 'Get-ADDomainController').Count | Should -Be 1
        $members.Catalog | Should -BeExactly 'dc1.demo.local:3268'
    }

    It 'Forgets a global catalog whose search fails, for the next read to look again' {
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        $members = Read-GroupMember $test.Row $test.Group ''
        $members.Problem | Should -BeLike 'dc1.demo.local:3268 : *'
        $members.ContainsKey('Catalog') | Should -BeTrue
        $members.Catalog | Should -BeNullOrEmpty
        # The window's thread forgets it too; a read that used none leaves what it keeps.
        $script:GlobalCatalog = 'dc1.demo.local:3268'
        Save-GlobalCatalog $members
        $script:GlobalCatalog | Should -BeNullOrEmpty
        $script:GlobalCatalog = 'dc1.demo.local:3268'
        Save-GlobalCatalog (Read-GroupMember (Get-TestGroup 'GG-Accueil').Row (Get-TestGroup 'GG-Accueil').Group '')
        $script:GlobalCatalog | Should -BeExactly 'dc1.demo.local:3268'
    }

    It 'Looks for no global catalog with a single domain' {
        $script:domainList = @('nord.demo.local')
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        $null = Read-GroupMember $test.Row $test.Group ''
        Get-LoggedQuery 'Get-ADDomainController' | Should -BeNullOrEmpty
    }

    It "Lists a domain local group's member of another domain, read in its domain" {
        $test = Get-TestGroup 'DL-Partage-Accueil'
        Clear-FakeADLog
        $members = Read-GroupMember $test.Row $test.Group ''
        Get-MemberText $members | Should -Be @('Directe Groupe: GG-Accueil (demo.local)', 'Directe Utilisateur: Nadia Moreau (nord.demo.local)')
        ($members.List | Where-Object Name -eq 'Nadia Moreau').Login | Should -BeExactly 'nmoreau'
        $read = @(Get-LoggedQuery 'Get-ADObject' | Where-Object Identity)
        $read.Server | Should -BeExactly 'nord.demo.local'
        $read.Identity | Should -BeExactly 'CN=Nadia Moreau,OU=Utilisateurs,DC=nord,DC=demo,DC=local'
    }

    It 'Keeps the members of another domain whose name starts with the text' {
        $test = Get-TestGroup 'DL-Partage-Accueil'
        Get-MemberText (Read-GroupMember $test.Row $test.Group 'nad') | Should -Be @('Directe Utilisateur: Nadia Moreau (nord.demo.local)')
        Get-MemberText (Read-GroupMember $test.Row $test.Group 'gg') | Should -Be @('Directe Groupe: GG-Accueil (demo.local)')
    }

    It 'Reads 50 members of other domains at most, then says there are more' {
        $test = Get-TestGroup 'DL-Partage-Accueil'
        $script:MemberForeignMax = 0
        $members = Read-GroupMember $test.Row $test.Group ''
        Get-MemberText $members | Should -Be @('Directe Groupe: GG-Accueil (demo.local)')
        $members.Truncated | Should -BeTrue
    }

    It 'Names a member of another domain by its DN when its domain can not be read' {
        $test = Get-TestGroup 'DL-Partage-Accueil'
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        # Its kind unknown (« Autre »), sorted as such.
        Get-MemberText (Read-GroupMember $test.Row $test.Group '') | Should -Be @('Directe Autre: Nadia Moreau (nord.demo.local)', 'Directe Groupe: GG-Accueil (demo.local)')
    }
}

Describe 'Get-ObjectGroup' {
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It "Lists a computer's direct groups, its primary group and those it is in through others, each in its domain" {
        $groups = Get-ComputerGroup ([pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = 'CN=ORD-01,OU=Postes,DC=demo,DC=local' })
        Get-GroupText $groups | Should -Be @(
            'Directe: GG-Logiciel-Office (demo.local)', 'Directe: GG-Postes-Accueil (demo.local)', 'Directe: Liste-Inventaire (demo.local)'
            'Principale: Ordinateurs du domaine (demo.local)'
            'Héritée: DL-Imprimantes-Accueil (demo.local)', 'Héritée: GU-Postes-Nord (nord.demo.local)'
        )
        $list = $groups | Where-Object Name -eq 'Liste-Inventaire'
        $list.Type | Should -BeExactly 'Distribution'
        $list.Scope | Should -BeExactly 'Globale'
        ($groups | Where-Object Name -eq 'GU-Postes-Nord').Scope | Should -BeExactly 'Universelle'
        ($groups | Where-Object Name -eq 'DL-Imprimantes-Accueil').Type | Should -BeExactly 'Sécurité'
    }

    It 'Reads the groups in batches, one search per domain and kind, not one per group' {
        $computer = Get-ADComputer -Server demo.local -Identity 'CN=ORD-01,OU=Postes,DC=demo,DC=local' -Properties MemberOf, PrimaryGroup, tokenGroups
        Clear-FakeADLog
        $null = Get-ObjectGroup $computer 'demo.local'
        $queries = Get-LoggedQuery 'Get-ADGroup'
        # The 3 direct groups at once, the primary one, the groups of nord.demo.local that list it, and the 2 inherited
        # ones, each in its domain.
        $queries.Count | Should -Be 5
        @($queries | Where-Object Identity).Identity | Should -BeExactly 'CN=Ordinateurs du domaine,CN=Users,DC=demo,DC=local'
        @($queries | Where-Object LDAPFilter -like '(|(distinguishedName=*').Server | Should -BeExactly 'demo.local'
        @($queries | Where-Object LDAPFilter -like '(member=*').Server | Should -BeExactly 'nord.demo.local'
        @($queries | Where-Object LDAPFilter -like '(|(objectSid=*').Server | Sort-Object | Should -Be @('demo.local', 'nord.demo.local')
        # Each domain's SID, to know where an inherited group is: read once.
        @(Get-LoggedQuery 'Get-ADDomain').Server | Should -Be @('demo.local', 'nord.demo.local')
    }

    It 'Reads 50 groups per search, and those not found one by one, saying why' {
        $real = @(Get-ADGroup -Server demo.local -LDAPFilter '(objectCategory=group)').DistinguishedName
        $absent = @(1..(60 - $real.Count) | ForEach-Object { "CN=GG-Absent-$_,OU=Groupes,DC=demo,DC=local" })
        $object = [pscustomobject]@{ DistinguishedName = 'CN=ORD-99,OU=Postes,DC=demo,DC=local'; MemberOf = @($real) + $absent; PrimaryGroup = $null }
        Clear-FakeADLog
        $groups = @(Get-ObjectGroup $object 'demo.local' @{ Sids = @(); Problem = $null })
        $groups.Count | Should -Be 60
        $queries = Get-LoggedQuery 'Get-ADGroup'
        @($queries | Where-Object LDAPFilter -like '(|(distinguishedName=*').Count | Should -Be 2
        @($queries | Where-Object Identity).Count | Should -Be $absent.Count
        @($groups | Where-Object Type).Count | Should -Be $real.Count
        $missing = $groups | Where-Object Name -eq 'CN=GG-Absent-1,OU=Groupes,DC=demo,DC=local'
        $missing.Description | Should -BeLike 'non lu : Objet « CN=GG-Absent-1,*introuvable*'
        $missing.Membership | Should -BeExactly 'Directe'
    }

    It "Lists the groups of another domain that list it, once, as direct" {
        $groups = Get-ComputerGroup ([pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = 'CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local' })
        # GU-Postes-Nord is in its tokenGroups too: it isn't listed again as inherited.
        Get-GroupText $groups | Should -Be @(
            'Directe: GG-GPO-Kiosques (demo.local)', 'Directe: GU-Postes-Nord (nord.demo.local)', 'Principale: Ordinateurs du domaine (demo.local)'
        )
    }

    It "Lists a user of nord.demo.local in a domain local group of demo.local" {
        $user = Get-TestUser 'Nadia Moreau' 'nord.demo.local' 'MemberOf', 'PrimaryGroup', 'tokenGroups'
        Get-GroupText (Get-ObjectGroup $user 'nord.demo.local') | Should -Be @(
            'Directe: DL-Partage-Accueil (demo.local)', 'Principale: Utilisateurs du domaine (nord.demo.local)'
        )
    }

    It 'Says in one row when the domain of another can not be searched' {
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        $user = Get-TestUser 'Julie Bertrand' -Properties 'MemberOf', 'PrimaryGroup', 'tokenGroups'
        $rows = @(Get-ObjectGroup $user 'demo.local' | Where-Object Domain -eq 'nord.demo.local')
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -BeExactly 'nord.demo.local'
        $rows[0].Description | Should -BeLike 'groupes de ce domaine non lus : Le serveur ne répond pas*'
    }

    It 'Searches no other domain in a forest of one' {
        $script:domainList = @('demo.local')
        $user = Get-TestUser 'Julie Bertrand' -Properties 'MemberOf', 'PrimaryGroup', 'tokenGroups'
        Clear-FakeADLog
        $null = Get-ObjectGroup $user 'demo.local'
        @(Get-LoggedQuery 'Get-ADGroup').Server | Where-Object { $_ -ne 'demo.local' } | Should -BeNullOrEmpty
    }

    It "Lists a group's own groups: direct only, without a primary group or tokenGroups" {
        $test = Get-TestGroup 'GG-Accueil'
        Get-GroupText (Get-ObjectGroup $test.Group 'demo.local') | Should -Be @('Directe: DL-Partage-Accueil (demo.local)')
    }

    It 'Says in one « Groupes hérités » row that tokenGroups was refused, the other groups still listed' {
        $user = Get-TestUser 'svc-sauvegarde'
        $inherited = Read-TokenGroup { Get-ADUser -Server demo.local -Identity $user.DistinguishedName -Properties tokenGroups -ErrorAction Stop }
        $groups = @(Get-ObjectGroup $user 'demo.local' $inherited)
        Get-GroupText $groups | Should -Be @('Principale: Utilisateurs du domaine (demo.local)', 'Héritée: Groupes hérités (demo.local)')
        $groups[-1].Description | Should -BeExactly 'non lus : Droits insuffisants pour cette opération'
    }
}

Describe 'Copier in Groupes… (#248)' {
    BeforeEach {
        Reset-TestSession
        Mock Show-CopyFeedback { }
        $script:button = [System.Windows.Controls.Button]::new()
        # The window's state, its view as the rows it shows, the row of a domain not searched among them.
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        $user = Get-TestUser 'Julie Bertrand' -Properties 'MemberOf', 'PrimaryGroup', 'tokenGroups'
        $rows = @(Get-ObjectGroup $user 'demo.local' | ForEach-Object { $_ | Add-Member -NotePropertyName MembershipText -NotePropertyValue $_.Membership -PassThru })
        $script:state = @{ View = $rows }
    }
    AfterEach { Clear-TestSession }

    It 'Copies the rows shown under a header line, and says so on the button' {
        Mock Set-ClipboardText { $true }
        Copy-GroupsWindow $script:state $script:button
        Should -Invoke Set-ClipboardText -Times 1 -Exactly -ParameterFilter {
            $lines = $Text -split [Environment]::NewLine
            $lines[0] -ceq "Groupe`tType`tÉtendue`tAppartenance`tDomaine`tDescription" -and $lines.Count -eq $script:state.View.Count + 1 -and
                $lines -like "nord.demo.local`t`t`tDirecte`tnord.demo.local`tgroupes de ce domaine non lus : *"
        }
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and $Copied }
    }

    It 'Says « Copie impossible » on the button when another program holds the clipboard' {
        Mock Set-ClipboardText { $false }
        Copy-GroupsWindow $script:state $script:button
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and -not $Copied }
    }
}

Describe 'Read-TokenGroup' {
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It 'Gives the SIDs as text, without a problem' {
        $user = Get-TestUser 'Julie Bertrand'
        $inherited = Read-TokenGroup { Get-ADUser -Server demo.local -Identity $user.DistinguishedName -Properties tokenGroups -ErrorAction Stop }
        $inherited.Problem | Should -BeNullOrEmpty
        $inherited.Sids | Should -Be @('S-1-5-21-1111-2222-3333-1110', 'S-1-5-21-1111-2222-3333-1111', 'S-1-5-21-1111-2222-3333-513', 'S-1-5-21-1111-2222-3333-1113')
        $inherited.Sids | ForEach-Object { $_ | Should -BeOfType [string] }
    }

    It 'Gives no SID and the reason when the read is refused' {
        $inherited = Read-TokenGroup { throw 'Insufficient access rights to perform the operation' }
        @($inherited.Sids).Count | Should -Be 0
        $inherited.Problem | Should -BeExactly 'Insufficient access rights to perform the operation'
    }
}

Describe 'Get-DomainOfSid' {
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It 'Finds the domain of <Sid>' -ForEach @(
        @{ Sid = 'S-1-5-21-1111-2222-3333-1110'; Expected = 'demo.local' }
        @{ Sid = 'S-1-5-21-4444-5555-6666-1201'; Expected = 'nord.demo.local' }
        @{ Sid = 'S-1-5-21-4444-5555-6666-513'; Expected = 'nord.demo.local' }
        # Another forest's, or a well-known SID: the default.
        @{ Sid = 'S-1-5-21-7777-8888-9999-1105'; Expected = 'défaut' }
        @{ Sid = 'S-1-5-32-544'; Expected = 'défaut' }
    ) {
        Get-DomainOfSid $Sid 'défaut' | Should -BeExactly $Expected
    }

    It "Reads each domain's SID once a session" {
        $null = Get-DomainOfSid 'S-1-5-21-1111-2222-3333-1110' 'demo.local'
        $null = Get-DomainOfSid 'S-1-5-21-4444-5555-6666-1201' 'demo.local'
        $null = Get-DomainOfSid 'S-1-5-21-7777-8888-9999-1105' 'demo.local'
        @(Get-LoggedQuery 'Get-ADDomain').Server | Should -Be @('demo.local', 'nord.demo.local')
    }

    It 'Gives the default for the SIDs of a domain that can not be read' {
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        Get-DomainOfSid 'S-1-5-21-4444-5555-6666-1201' 'demo.local' | Should -BeExactly 'demo.local'
        Get-DomainOfSid 'S-1-5-21-1111-2222-3333-1110' 'nord.demo.local' | Should -BeExactly 'demo.local'
    }
}

Describe 'The add dialogs, searched at each pause in the typing' {
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It 'Ajouter des membres asks AD for no more than it shows: 50, and those already members' {
        # demo.local's 250 extra computers all start with PC-.
        $found = Get-GroupMemberChoice 'demo.local' 'PC' @('CN=PC-001,OU=Postes,DC=demo,DC=local', 'CN=PC-002,OU=Postes,DC=demo,DC=local')
        @($found.Items).Count | Should -Be 50
        @(Get-LoggedQuery 'Get-ADUser').ResultSetSize | Should -Be 52
        @(Get-LoggedQuery 'Get-ADComputer').ResultSetSize | Should -Be 52
        @(Get-LoggedQuery 'Get-ADGroup').ResultSetSize | Should -Be 52
    }

    It 'Ajouter à un groupe asks AD for no more than it shows: 50, and the groups the user is in' {
        $found = Get-UserGroupChoice 'demo.local' 'accueil' @('CN=GG-Accueil,OU=Groupes,DC=demo,DC=local')
        @($found.Items).Name | Should -Be @('DL-Imprimantes-Accueil', 'DL-Partage-Accueil', 'GG-Postes-Accueil')
        @(Get-LoggedQuery 'Get-ADGroup').ResultSetSize | Should -Be 51
    }

    It "Ajouter à un groupe searches the other domains when the user's has none: their domain local and universal groups" {
        # nord.demo.local's Personnel-Nord is global: left out.
        $found = Get-UserGroupChoice 'demo.local' 'nord' @()
        @($found.Items).Name | Should -Be @('DL-Imprimantes-Nord', 'GU-Postes-Nord')
        @($found.Items)[0].Details | Should -BeExactly "nord.demo.local · Sécurité, Domaine local · Accès aux imprimantes de l'équipe Nord"
        $found.OthersOnly | Should -BeTrue
        @(Get-LoggedQuery 'Get-ADGroup').Server | Should -Be @('demo.local', 'nord.demo.local')
        Clear-FakeADLog
        $found = Get-UserGroupChoice 'demo.local' 'accueil' @()
        $found.OthersOnly | Should -BeFalse
        @(Get-LoggedQuery 'Get-ADGroup').Server | Should -Be @('demo.local')
    }

    It 'Ajouter à un groupe searches them too when asked, after the groups of the user''s domain, those of Windows left out' {
        # nord.demo.local's own built-in Administrateurs is listed; demo.local's Admins du domaine (global) and
        # Administrateurs de l'entreprise (made by Windows) aren't.
        $found = Get-UserGroupChoice 'nord.demo.local' 'admin' @() $true
        @($found.Items).Name | Should -Be @('Administrateurs')
        @(Get-LoggedQuery 'Get-ADGroup').Server | Should -Be @('nord.demo.local', 'demo.local')
        $found = Get-UserGroupChoice 'demo.local' 'postes' @('CN=GG-Postes-Accueil,OU=Groupes,DC=demo,DC=local') $true
        @($found.Items).Name | Should -Be @('GU-Postes-Nord')
        $found.OthersOnly | Should -BeTrue
    }

    It "Ajouter à un groupe offers the user's domain's privileged groups, marked: protected by AD, or an administration group by its RID (#233)" {
        $found = Get-UserGroupChoice 'demo.local' 'admin' @()
        @($found.Items | ForEach-Object { "$($_.Name): $($_.Privileged)" }) | Should -Be @("Administrateurs de l'entreprise: True", 'Admins du domaine: True')
        @(Get-LoggedQuery 'Get-ADGroup').Properties | Should -Be @('Description,adminCount')
        # A group Windows creates isn't privileged for that alone: Utilisateurs du domaine (RID 513) is routine.
        $found = Get-UserGroupChoice 'demo.local' 'utilisateurs' @()
        @($found.Items | ForEach-Object { "$($_.Name): $($_.Privileged)" }) | Should -Contain 'Utilisateurs du domaine: False'
        # GG-Projet-2019 keeps the adminCount of a group once protected: marked all the same; the other GG- groups aren't.
        $found = Get-UserGroupChoice 'demo.local' 'gg-' @()
        @($found.Items | Where-Object Privileged | ForEach-Object Name) | Should -Be @('GG-Projet-2019')
        @($found.Items).Count | Should -BeGreaterThan 1
        # In the other domains, those made by Windows stay left out; their other groups are read the same way.
        $found = Get-UserGroupChoice 'nord.demo.local' 'admin' @() $true
        @($found.Items | ForEach-Object { "$($_.Name): $($_.Privileged)" }) | Should -Be @('Administrateurs: True')
        @(Get-LoggedQuery 'Get-ADGroup' | Select-Object -Last 1).Properties | Should -BeExactly 'Description,adminCount'
    }

    It 'An administration group is known by its RID, without adminCount (SDProp not run yet), and only those (#233)' {
        foreach ($rid in 512, 516, 518, 519, 521, 526, 527) { Test-AdminGroupSid "S-1-5-21-1-2-3-$rid" | Should -BeTrue }
        foreach ($rid in 544, 548, 549, 550, 551, 552) { Test-AdminGroupSid "S-1-5-32-$rid" | Should -BeTrue }
        # Utilisateurs et Invités du domaine, Éditeurs de certificats, Utilisateurs du Bureau à distance, a group made by hand.
        foreach ($sid in 'S-1-5-21-1-2-3-513', 'S-1-5-21-1-2-3-514', 'S-1-5-21-1-2-3-517', 'S-1-5-32-555', 'S-1-5-21-1-2-3-1512', '') { Test-AdminGroupSid $sid | Should -BeFalse }
    }

    It 'Ajouter à un groupe marks an administration group without adminCount by its RID, and DnsAdmins by its name (#233)' {
        Mock Get-ADGroup {
            foreach ($group in @(('Opérateurs de sauvegarde', 'CN=Builtin', 'S-1-5-32-551'), ('DnsAdmins', 'CN=Users', 'S-1-5-21-1-2-3-1101'), ('GG-Opérations', 'OU=Groupes', 'S-1-5-21-1-2-3-1102'))) {
                [pscustomobject]@{ Name = $group[0]; DistinguishedName = "CN=$($group[0]),$($group[1]),DC=demo,DC=local"; SID = $group[2]; SamAccountName = $group[0]
                                   GroupCategory = 'Security'; GroupScope = 'DomainLocal'; Description = '' }
            }
        }
        $found = Get-UserGroupChoice 'demo.local' 'o' @()
        @($found.Items | ForEach-Object { "$($_.Name): $($_.Privileged)" }) | Should -Be @('DnsAdmins: True', 'GG-Opérations: False', 'Opérateurs de sauvegarde: True')
    }

    It 'Ajouter à un groupe says which other domain could not be searched' {
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        $found = Get-UserGroupChoice 'demo.local' 'nord' @()
        @($found.Items).Count | Should -Be 0
        @($found.Unsearched).Domain | Should -BeExactly 'nord.demo.local'
        @($found.Unsearched).Problem | Should -BeLike 'Unable to contact the server*'
    }

    It 'Ajouter à un groupe searches no other domain in a forest of one' {
        $script:domainList = @('demo.local')
        $found = Get-UserGroupChoice 'demo.local' 'nord' @() $true
        @($found.Items).Count | Should -Be 0
        @(Get-LoggedQuery 'Get-ADGroup').Server | Should -Be @('demo.local')
    }
}

Describe 'A user put in or out of a group of another domain' {
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It "Gives that domain's DC the user as read in its own (it can't find it by DN), read once" {
        $row = [pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = 'CN=Julie Bertrand,OU=Utilisateurs,DC=demo,DC=local' }
        $group = 'CN=DL-Imprimantes-Nord,OU=Groupes,DC=nord,DC=demo,DC=local'
        { Add-ADGroupMember -Server nord.demo.local -Identity $group -Members $row.DistinguishedName } | Should -Throw 'Cannot find an object*'
        $account = @{}
        $server, $member = Get-UserAsMember $row $group $account
        $server | Should -BeExactly 'nord.demo.local'
        Add-ADGroupMember -Server $server -Identity $group -Members $member
        (Get-ADGroup -Server nord.demo.local -Identity $group -Properties member).member | Should -Contain $row.DistinguishedName
        Remove-ADGroupMember -Server $server -Identity $group -Members $member -Confirm:$false
        (Get-ADGroup -Server nord.demo.local -Identity $group -Properties member).member | Should -Not -Contain $row.DistinguishedName
        # A global group of that domain refuses it, as AD does.
        { Add-ADGroupMember -Server $server -Identity 'CN=Personnel-Nord,OU=Groupes,DC=nord,DC=demo,DC=local' -Members $member } | Should -Throw 'A global group cannot have a cross-domain member.'
        # A group of its own domain: its DN, as before.
        $server, $member = Get-UserAsMember $row 'CN=GG-VPN,OU=Groupes,DC=demo,DC=local' $account
        $server | Should -BeExactly 'demo.local'
        $member | Should -BeExactly $row.DistinguishedName
        @(Get-LoggedQuery 'Get-ADUser').Count | Should -Be 1
    }
}
Describe 'The Groupes search: Sans membres' {
    # The page's search as a search runspace runs it ($GroupSearchScript). A group that lists no member may be someone's
    # primary group: AD names it by RID (primaryGroupID), not in its member list, so it isn't empty.
    BeforeAll {
        function Invoke-GroupSearchScript([string]$Domain, [string]$Clause, [bool]$Empty, [int]$Limit = 0) {
            & ([scriptblock]::Create($script:GroupSearchScript)) -Domain $Domain -LdapFilter "(&(objectCategory=group)$Clause)" -RowBuilder '' -Limit $Limit -Empty $Empty
        }
    }
    BeforeEach { Reset-TestSession }
    AfterEach { Clear-TestSession }

    It "Leaves out Utilisateurs du domaine, Ordinateurs du domaine, and a group that is a computer's primary group" {
        # Labo-Principal lists no member: it's ORD-08's primary group.
        $found = Invoke-GroupSearchScript 'demo.local' '(!(member=*))' $true
        $found.Error | Should -BeNullOrEmpty
        @($found.Rows.Name) | Should -Be @("Administrateurs de l'entreprise", 'Admins du domaine', 'GG-Projet-2019')
    }

    It "Reads each domain's own primary groups" {
        @((Invoke-GroupSearchScript 'nord.demo.local' '(!(member=*))' $true).Rows.Name) | Should -Be @('Administrateurs', 'Personnel-Nord')
    }

    It 'Reads the unusual primary groups in one search, and one account at most for each usual one' {
        $null = Invoke-GroupSearchScript 'demo.local' '(!(member=*))' $true
        @(Get-LoggedQuery 'Get-ADObject' | ForEach-Object { "$($_.LDAPFilter) $($_.ResultSetSize)" }) | Should -Be @(
            '(&(objectClass=user)(!(primaryGroupID=513))(!(primaryGroupID=515))(!(primaryGroupID=516))(!(primaryGroupID=521))) '
            '(&(objectClass=user)(primaryGroupID=513)) 1', '(&(objectClass=user)(primaryGroupID=515)) 1'
            '(&(objectClass=user)(primaryGroupID=516)) 1', '(&(objectClass=user)(primaryGroupID=521)) 1'
        )
    }

    It 'Applies the limit to the groups shown, not to those AD found' {
        # demo.local's primary groups: 513, 515, 516 (DC1) and 1106 (ORD-08); no read-only DC (521). AD is asked for
        # four more groups than the limit and one, as four of them may be left out.
        $found = Invoke-GroupSearchScript 'demo.local' '(!(member=*))' $true 3
        @($found.Rows.Name) | Should -Be @("Administrateurs de l'entreprise", 'Admins du domaine', 'GG-Projet-2019')
        $found.Truncated | Should -BeFalse
        @(Get-LoggedQuery 'Get-ADGroup').ResultSetSize | Should -Be 8
        Clear-FakeADLog
        $found = Invoke-GroupSearchScript 'demo.local' '(!(member=*))' $true 2
        $found.Rows.Count | Should -Be 2
        $found.Truncated | Should -BeTrue
    }

    It "Fails the domain's search when the primary groups can't be read, rather than call groups empty" {
        Mock Get-ADObject { throw 'Insufficient access rights to perform the operation' }
        $found = Invoke-GroupSearchScript 'demo.local' '(!(member=*))' $true
        $found.Error | Should -BeExactly 'Insufficient access rights to perform the operation'
        $found.Rows | Should -BeNullOrEmpty
    }

    It "Fails it too when an account's primary group can't be read: AD sends the account without it" {
        # A delegated ACL that hides primaryGroupID: AD takes it as absent, so the (!(…)) clauses let the account through.
        Mock Get-ADObject { [pscustomobject]@{ Name = 'Compte caché'; DistinguishedName = 'CN=Compte caché,OU=Utilisateurs,DC=demo,DC=local'; ObjectClass = 'user' } } -ParameterFilter { $LDAPFilter -like '*(!(primaryGroupID=513))*' }
        $found = Invoke-GroupSearchScript 'demo.local' '(!(member=*))' $true
        $found.Error | Should -BeExactly 'Groupe principal illisible pour Compte caché : impossible de dire quels groupes sont vides.'
        $found.Rows | Should -BeNullOrEmpty
    }

    It 'Leaves the other types as they were: a primary group is found by its name' {
        $found = Invoke-GroupSearchScript 'demo.local' '(name=*du domaine*)' $false
        @($found.Rows.Name) | Should -Be @('Admins du domaine', 'Ordinateurs du domaine', 'Utilisateurs du domaine')
        @(Get-LoggedQuery 'Get-ADObject') | Should -BeNullOrEmpty
    }
}

Describe "Retirer… in a group's Propriétés: members of other domains" {
    # Remove-GroupMemberList with the rows Read-GroupMember lists. The group's DC finds only its own domain's objects by
    # DN, as the real one does (FakeAD's Get-FakeADMemberDN): one of another domain goes as read in its own. Last in the
    # file, and on a fresh fake AD each time: these tests change member lists the others read.
    BeforeEach { Import-RepereFakeAD; Reset-TestSession }
    AfterEach { Clear-TestSession }

    It 'Removes the members of a universal group, of mixed domains, at once: those of another domain read in theirs' {
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        $members = @((Read-GroupMember $test.Row $test.Group '').List | Where-Object Membership -eq 'Directe')
        Get-MemberText @{ List = $members } | Should -Be @(
            'Directe Groupe: GG-Postes-Accueil (demo.local)', 'Directe Ordinateur: ORD-01 (nord.demo.local)', 'Directe Ordinateur: ORD-04 (demo.local)'
        )
        $ord04 = $members[2].DistinguishedName
        { Remove-ADGroupMember -Server nord.demo.local -Identity $test.Row.DistinguishedName -Members $ord04 -Confirm:$false } | Should -Throw 'Cannot find an object*'
        Clear-FakeADLog
        $result = Remove-GroupMemberList $test.Row $members
        @($result.Removed) | Should -Be @('GG-Postes-Accueil', 'ORD-01', 'ORD-04')
        $result.Failed | Should -BeNullOrEmpty
        # Each read with its kind's cmdlet (its SID with it), in its domain; ORD-01, of the group's, by DN.
        @(Get-LoggedQuery 'Get-ADGroup' | ForEach-Object { "$($_.Server) $($_.Identity)" }) | Should -Be @('demo.local CN=GG-Postes-Accueil,OU=Groupes,DC=demo,DC=local')
        @(Get-LoggedQuery 'Get-ADComputer' | ForEach-Object { "$($_.Server) $($_.Identity)" }) | Should -Be @("demo.local $ord04")
        # On the group's domain's PDC, where its Propriétés reads it again (#256).
        @(Get-LoggedQuery 'Remove-ADGroupMember').Server | Sort-Object -Unique | Should -BeExactly 'dc1.nord.demo.local'
        (Get-ADGroup -Server nord.demo.local -Identity $test.Row.DistinguishedName -Properties member).member | Should -BeNullOrEmpty
    }

    It "Says which members of another domain could not be read there, trying that domain once, and removes the others" {
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        $members = @((Read-GroupMember $test.Row $test.Group '').List | Where-Object Membership -eq 'Directe')
        $env:REPERE_FAKEAD_UNREACHABLE = 'demo.local'
        Clear-FakeADLog
        $result = Remove-GroupMemberList $test.Row $members
        @($result.Removed) | Should -Be @('ORD-01')
        @($result.Failed) | Should -HaveCount 2
        $result.Failed[0] | Should -BeLike '✖ GG-Postes-Accueil : non retiré de GU-Postes-Nord (Unable to contact the server*'
        $result.Failed[1] | Should -BeExactly ($result.Failed[0] -replace '^✖ GG-Postes-Accueil', '✖ ORD-04')
        # demo.local asked once: ORD-04 isn't read after GG-Postes-Accueil couldn't be.
        @(Read-FakeADLog | Where-Object { $_.Command -like 'Get-AD*' -and $_.Command -ne 'Get-ADDomain' } | ForEach-Object { "$($_.Command) $($_.Server)" }) | Should -Be @('Get-ADGroup demo.local')
        $env:REPERE_FAKEAD_UNREACHABLE = $null
        @((Get-ADGroup -Server nord.demo.local -Identity $test.Row.DistinguishedName -Properties member).member | Sort-Object) |
            Should -Be @(@($members[0].DistinguishedName, $members[2].DistinguishedName) | Sort-Object)
    }

    It "Still reads a domain's next member when one of its members alone could not be found" {
        $test = Get-TestGroup 'GU-Postes-Nord' 'nord.demo.local'
        $members = @((Read-GroupMember $test.Row $test.Group '').List | Where-Object Membership -eq 'Directe')
        # GG-Postes-Accueil deleted since the list was read.
        $gone = [pscustomobject]@{ Name = 'GG-Supprimé'; Kind = 'Groupe'; Membership = 'Directe'; Domain = 'demo.local'; DistinguishedName = 'CN=GG-Supprimé,OU=Groupes,DC=demo,DC=local' }
        $result = Remove-GroupMemberList $test.Row @($gone, $members[2])
        @($result.Removed) | Should -Be @('ORD-04')
        @($result.Failed) | Should -HaveCount 1
        $result.Failed[0] | Should -BeLike '✖ GG-Supprimé : non retiré de GU-Postes-Nord (*'
    }

    It 'Removes a member of another domain listed by its DN only, read with its class''s cmdlet' {
        # Its domain unreachable when the list was read: « Autre », its kind unknown.
        $test = Get-TestGroup 'DL-Partage-Accueil'
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        $member = @((Read-GroupMember $test.Row $test.Group 'nad').List)
        Get-MemberText @{ List = $member } | Should -Be @('Directe Autre: Nadia Moreau (nord.demo.local)')
        $env:REPERE_FAKEAD_UNREACHABLE = $null
        Clear-FakeADLog
        @((Remove-GroupMemberList $test.Row $member).Removed) | Should -Be @('Nadia Moreau')
        # Its class first, then the user as Get-ADUser reads it (with its SID), both in its domain.
        $dn = 'CN=Nadia Moreau,OU=Utilisateurs,DC=nord,DC=demo,DC=local'
        @(Read-FakeADLog | Where-Object { $_.Command -like 'Get-AD*' -and $_.Command -ne 'Get-ADDomain' } | ForEach-Object { "$($_.Command) $($_.Server) $($_.Identity)" }) |
            Should -Be @("Get-ADObject nord.demo.local $dn", "Get-ADUser nord.demo.local $dn")
        (Get-ADGroup -Server demo.local -Identity $test.Row.DistinguishedName -Properties member).member | Should -Be @('CN=GG-Accueil,OU=Groupes,DC=demo,DC=local')
    }

    It 'Says a contact of another domain can not be removed this way, without trying' {
        $test = Get-TestGroup 'DL-Partage-Accueil'
        $dn = 'CN=Marie Contact,OU=Contacts,DC=nord,DC=demo,DC=local'
        Mock Get-ADObject { [pscustomobject]@{ Name = 'Marie Contact'; DistinguishedName = 'CN=Marie Contact,OU=Contacts,DC=nord,DC=demo,DC=local'; ObjectClass = 'contact' } }
        $member = [pscustomobject]@{ Name = 'Marie Contact'; Kind = 'Contact'; Membership = 'Directe'; Domain = 'nord.demo.local'; DistinguishedName = $dn }
        Clear-FakeADLog
        $result = Remove-GroupMemberList $test.Row @($member)
        $result.Removed | Should -BeNullOrEmpty
        @($result.Failed) | Should -Be @("✖ Marie Contact : non retiré de DL-Partage-Accueil (objet contact d'un autre domaine : seuls les utilisateurs, les ordinateurs et les groupes sont pris en charge)")
        Get-LoggedQuery 'Remove-ADGroupMember' | Should -BeNullOrEmpty
    }

    It 'Removes a foreign security principal by its DN, as before: it is in the group''s domain' {
        $test = Get-TestGroup 'DL-Partage-Accueil'
        $dn = 'CN=S-1-5-21-9999-8888-7777-1105,CN=ForeignSecurityPrincipals,DC=demo,DC=local'
        Add-ADGroupMember -Server demo.local -Identity $test.Row.DistinguishedName -Members $dn
        $member = [pscustomobject]@{ Name = 'AUTRE\mdupont'; Kind = 'Externe'; Membership = 'Directe'; Domain = Get-DomainOfDN $dn; DistinguishedName = $dn }
        Clear-FakeADLog
        @((Remove-GroupMemberList $test.Row @($member)).Removed) | Should -Be @('AUTRE\mdupont')
        @(Read-FakeADLog | Where-Object { $_.Command -like 'Get-AD*' -and $_.Command -ne 'Get-ADDomain' }) | Should -BeNullOrEmpty
        (Get-ADGroup -Server demo.local -Identity $test.Row.DistinguishedName -Properties member).member | Should -Not -Contain $dn
    }
}

Describe "A group's Propriétés reads and changes its members on its domain's PDC (#256)" {
    # Where a user's Propriétés reads its groups (Get-UserServer): a change sent to any DC would show there, and in the
    # group's window read again, only once replicated. On a fresh fake AD each time: these tests change member lists.
    BeforeEach { Import-RepereFakeAD; Reset-TestSession }
    AfterEach { Clear-TestSession }

    It 'Reads the group and its members on the server it is given' {
        $test = Get-TestGroup 'GG-Accueil'
        $server = Get-UserServer 'demo.local'
        $server | Should -BeExactly 'dc1.demo.local'
        Clear-FakeADLog
        $detail = Read-GroupDetail $test.Row '' $server
        $detail.Server | Should -BeExactly 'dc1.demo.local'
        $detail.Down | Should -BeNullOrEmpty
        @($detail.Members.List).Count | Should -BeGreaterThan 0
        @(Get-LoggedQuery 'Get-ADGroup' | Where-Object Identity -eq $test.Row.DistinguishedName | ForEach-Object Server) | Should -Contain 'dc1.demo.local'
        # The member searches (memberOf, primaryGroupID) too.
        @(Get-LoggedQuery 'Get-ADObject' | ForEach-Object Server | Sort-Object -Unique) | Should -BeExactly 'dc1.demo.local'
    }

    It 'Reads on another DC when its PDC does not answer, and says which for the changes to go there' {
        $test = Get-TestGroup 'GG-Accueil'
        $server = Get-UserServer 'demo.local'
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        $detail = Read-GroupDetail $test.Row '' $server
        $detail.Server | Should -BeExactly 'dc2.demo.local'
        $detail.Down.Server | Should -BeExactly 'dc1.demo.local'
        $detail.Down.Fallback | Should -BeExactly 'dc2.demo.local'
        $detail.Down.Problem | Should -BeLike 'Unable to contact the server*'
        # What Update-GroupDetail does with it: the PDC kept as down, the DC read from used in its place.
        Register-ServerDown 'demo.local' $detail.Down
        Get-UserServer 'demo.local' | Should -BeExactly 'dc2.demo.local'
    }

    It 'Leaves a DC a change has chosen since, rather than one a read started earlier found' {
        $null = Get-UserServer 'demo.local'
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local;dc2.demo.local'
        # A change found dc1 and then dc2 down meanwhile, and went to dc3.
        $null = Set-PdcDown 'demo.local' 'dc1.demo.local' 'down'
        $null = Set-PdcDown 'demo.local' 'dc2.demo.local' 'down'
        Get-UserServer 'demo.local' | Should -BeExactly 'dc3.demo.local'
        Register-ServerDown 'demo.local' @{ Server = 'dc1.demo.local'; Problem = 'down'; Fallback = 'dc2.demo.local' }
        Get-UserServer 'demo.local' | Should -BeExactly 'dc3.demo.local'
    }

    It 'Throws what is not a DC down, without trying elsewhere' {
        $row = [pscustomobject]@{ Domain = 'demo.local'; DistinguishedName = 'CN=GG-Absent,OU=Groupes,DC=demo,DC=local'; Name = 'GG-Absent' }
        Clear-FakeADLog
        { Read-GroupDetail $row '' 'dc1.demo.local' } | Should -Throw
        @(Get-LoggedQuery 'Get-ADGroup' | ForEach-Object Server) | Should -Be @('dc1.demo.local')
    }

    It 'Removes a member of its own domain on the PDC, and on another DC when the PDC does not answer' {
        $test = Get-TestGroup 'GG-VPN'
        $members = @((Read-GroupMember $test.Row $test.Group '').List | Where-Object Membership -eq 'Directe')
        $null = Get-UserServer 'demo.local'
        Clear-FakeADLog
        @((Remove-GroupMemberList $test.Row @($members[0])).Removed) | Should -Be @($members[0].Name)
        @(Get-LoggedQuery 'Remove-ADGroupMember' | ForEach-Object Server) | Should -Be @('dc1.demo.local')
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        Clear-FakeADLog
        @((Remove-GroupMemberList $test.Row @($members[1])).Removed) | Should -Be @($members[1].Name)
        # Tried on the PDC first (the fake AD logs only the call that answers), then made on the DC in its place.
        @(Get-LoggedQuery 'Remove-ADGroupMember' | ForEach-Object Server) | Should -Be @('dc2.demo.local')
        Get-UserServer 'demo.local' | Should -BeExactly 'dc2.demo.local'
    }
}
