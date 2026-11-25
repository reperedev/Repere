# The fake AD's own behaviour, which Repère's UI tests and the tests here rely on: the LDAP filters it understands for
# users, groups and a group's members, and where memberships are known in a forest of two domains (a DC knows its own
# domain's member lists; the global catalog, dc1.demo.local:3268, the universal groups' of the whole forest).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    Import-RepereFakeAD

    $script:Person = '(objectCategory=person)(objectClass=user)'
    $script:Accueil = 'CN=GG-Accueil,OU=Groupes,DC=demo,DC=local'
    $script:PostesNord = 'CN=GU-Postes-Nord,OU=Groupes,DC=nord,DC=demo,DC=local'
    $script:PartageAccueil = 'CN=DL-Partage-Accueil,OU=Groupes,DC=demo,DC=local'
    $script:Nadia = 'CN=Nadia Moreau,OU=Utilisateurs,DC=nord,DC=demo,DC=local'
}

Describe 'Fake AD: users by LDAP filter' {
    It 'Finds by the start of a name, login or email (anr), in the domain asked: <Text> in <Domain>' -ForEach @(
        @{ Text = 'bert'; Domain = 'demo.local'; Expected = @('Jean Bertrand', 'Julie Bertrand') }
        @{ Text = 'bert'; Domain = 'nord.demo.local'; Expected = @('Paul Bertrand') }
        @{ Text = 'julie b'; Domain = 'demo.local'; Expected = @('Julie Bertrand') }
        @{ Text = 'mdur'; Domain = 'demo.local'; Expected = @('Marc Durand') }
        @{ Text = 'nlevy@'; Domain = 'demo.local'; Expected = @('Nathalie Lévy') }
    ) {
        @(Get-ADUser -Server $Domain -LDAPFilter "(&$script:Person(anr=$Text))" | Sort-Object Name).Name | Should -Be $Expected
    }

    It 'Finds the locked, the disabled accounts and a description' {
        (Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(lockoutTime>=1))").Name | Should -BeExactly 'Marc Durand'
        (Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(userAccountControl:1.2.840.113556.1.4.803:=2))").Name | Should -BeExactly 'Sophie Rey'
        (Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(description=*sauvegarde*))").SamAccountName | Should -BeExactly 'svc-sauvegarde'
    }

    It 'Finds one user by its DN, and reads escaped values' {
        (Get-ADUser -Server nord.demo.local -LDAPFilter "(&$script:Person(distinguishedName=$script:Nadia))").Name | Should -BeExactly 'Nadia Moreau'
        Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(anr=\2a))" | Should -BeNullOrEmpty
    }

    It 'Refuses a clause it does not know, as a parse error' {
        { Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(telephoneNumber=555*))" } | Should -Throw 'Error parsing query*'
    }

    It 'Gives tokenGroups only when asked for, and refuses it for svc-sauvegarde' {
        $dn = 'CN=Julie Bertrand,OU=Utilisateurs,DC=demo,DC=local'
        (Get-ADUser -Server demo.local -Identity $dn -Properties MemberOf).PSObject.Properties['tokenGroups'] | Should -BeNullOrEmpty
        (Get-ADUser -Server demo.local -Identity $dn -Properties tokenGroups).tokenGroups | Should -Not -BeNullOrEmpty
        $service = 'CN=Sauvegarde,OU=Comptes de service,DC=demo,DC=local'
        { Get-ADUser -Server demo.local -Identity $service -Properties tokenGroups } | Should -Throw 'Insufficient access rights*'
        (Get-ADUser -Server demo.local -Identity $service -Properties MemberOf).SamAccountName | Should -BeExactly 'svc-sauvegarde'
    }

    It 'Refuses tokenGroups in a search, as a real domain does: only one object read by its DN has it' {
        { Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(anr=julie))" -Properties tokenGroups } | Should -Throw '*only supported for base searches*'
        { Get-ADComputer -Server demo.local -Filter "Name -eq 'ORD-01'" -Properties tokenGroups } | Should -Throw '*only supported for base searches*'
        { Get-ADGroup -Server demo.local -LDAPFilter '(&(objectCategory=group)(name=*vpn*))' -Properties tokenGroups } | Should -Throw '*only supported for base searches*'
        { Get-ADObject -Server demo.local -LDAPFilter "(memberOf=$script:Accueil)" -Properties tokenGroups } | Should -Throw '*only supported for base searches*'
        (Get-ADUser -Server demo.local -LDAPFilter "(&$script:Person(anr=julie))" -Properties MemberOf).Name | Should -BeExactly 'Julie Bertrand'
    }

    It 'Answers on a DC of the domain (dc1.demo.local), and fails on an unknown server' {
        (Get-ADUser -Server dc1.demo.local -Identity 'CN=Marc Durand,OU=Utilisateurs,DC=demo,DC=local').LockedOut | Should -BeTrue
        { Get-ADUser -Server sud.demo.local -LDAPFilter "(&$script:Person(anr=bert))" } | Should -Throw 'Unable to contact the server*'
    }
}

Describe 'Fake AD: groups by LDAP filter' {
    It 'Finds by a part of the name or the description, and by the start of the name (anr)' {
        (Get-ADGroup -Server demo.local -LDAPFilter '(&(objectCategory=group)(name=*vpn*))').Name | Should -BeExactly 'GG-VPN'
        (Get-ADGroup -Server demo.local -LDAPFilter '(&(objectCategory=group)(description=*imprimantes*))').Name | Should -BeExactly 'DL-Imprimantes-Accueil'
        @(Get-ADGroup -Server demo.local -LDAPFilter '(&(objectCategory=group)(anr=gg-a))' | Sort-Object Name).Name | Should -Be @('GG-Accueil')
    }

    It 'Finds the groups without members, the primary groups among them' {
        $empty = @(Get-ADGroup -Server demo.local -LDAPFilter '(&(objectCategory=group)(!(member=*)))').Name
        $empty | Should -Contain 'GG-Projet-2019'
        $empty | Should -Contain 'Utilisateurs du domaine'
        $empty | Should -Not -Contain 'GG-Accueil'
    }

    It 'Finds the groups that list an object, in the domain asked only' {
        (Get-ADGroup -Server demo.local -LDAPFilter "(member=$script:Nadia)").Name | Should -BeExactly 'DL-Partage-Accueil'
        Get-ADGroup -Server nord.demo.local -LDAPFilter "(member=$script:Nadia)" | Should -BeNullOrEmpty
    }

    It 'Finds several groups at once, by DN or by SID (an OR of them)' {
        @(Get-ADGroup -Server demo.local -LDAPFilter "(|(distinguishedName=$script:Accueil)(distinguishedName=$script:PartageAccueil)(distinguishedName=$script:PostesNord))" | Sort-Object Name).Name |
            Should -Be @('DL-Partage-Accueil', 'GG-Accueil')
        @(Get-ADGroup -Server nord.demo.local -LDAPFilter '(|(objectSid=S-1-5-21-4444-5555-6666-1201)(objectSid=S-1-5-21-1111-2222-3333-1110))').Name | Should -Be @('GU-Postes-Nord')
    }

    It 'Reads one group by its DN or its SID, in its own domain only' {
        (Get-ADGroup -Server demo.local -Identity 'S-1-5-21-1111-2222-3333-1110').Name | Should -BeExactly 'GG-Accueil'
        (Get-ADGroup -Server demo.local -Identity $script:Accueil -Properties member).member.Count | Should -Be 2
        { Get-ADGroup -Server demo.local -Identity $script:PostesNord } | Should -Throw 'Cannot find an object*'
    }
}

Describe "Fake AD: a group's members by LDAP filter" {
    It 'Finds the members (memberOf), the accounts of a primary group (primaryGroupID) and by a name (anr)' {
        @(Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:Accueil))" | Sort-Object Name).Name | Should -Be @('Julie Bertrand', 'Léa Perrin')
        @(Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:Accueil)(anr=lper))").sAMAccountName | Should -Be @('lperrin')
        @(Get-ADObject -Server nord.demo.local -LDAPFilter '(&(primaryGroupID=513))' | Sort-Object Name).Name | Should -Be @('Nadia Moreau', 'Paul Bertrand')
        @(Get-ADObject -Server nord.demo.local -LDAPFilter '(&(primaryGroupID=515))' | Sort-Object Name).Name | Should -Be @('NRD-01', 'NRD-02', 'ORD-01')
    }

    It 'Finds the members whose name, login, display name, first or last name starts with a text, in an OR' {
        $starts = { param($Text) "(|(name=$Text*)(sAMAccountName=$Text*)(displayName=$Text*)(givenName=$Text*)(sn=$Text*))" }
        @(Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:Accueil)$(& $starts 'lper'))").sAMAccountName | Should -Be @('lperrin')
        @(Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:Accueil)$(& $starts 'BERT'))").Name | Should -Be @('Julie Bertrand')
        @(Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:Accueil)$(& $starts 'blay'))") | Should -BeNullOrEmpty
        # An escaped * is a character of the name, not a start.
        Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:Accueil)$(& $starts '\2a'))" | Should -BeNullOrEmpty
        # Without a *, the whole value.
        @(Get-ADObject -Server demo.local -LDAPFilter '(&(objectClass=user)(sAMAccountName=lperrin))').Name | Should -Be @('Léa Perrin')
    }

    It "Finds a domain's controllers, an OR of primary groups, in that domain only" {
        @(Get-ADObject -Server demo.local -LDAPFilter '(|(primaryGroupID=516)(primaryGroupID=521))').Name | Should -Be @('DC1')
        Get-ADObject -Server nord.demo.local -LDAPFilter '(|(primaryGroupID=516)(primaryGroupID=521))' | Should -BeNullOrEmpty
    }

    It 'Returns -ResultSetSize objects at most' {
        @(Get-ADObject -Server demo.local -LDAPFilter '(&(primaryGroupID=515))' -ResultSetSize 5).Count | Should -Be 5
    }

    It 'Sans membres: users and computers whose primary group is none of the usual ones, with it; groups have none' {
        $found = @(Get-ADObject -Server demo.local -LDAPFilter '(&(objectClass=user)(!(primaryGroupID=513))(!(primaryGroupID=515))(!(primaryGroupID=516))(!(primaryGroupID=521)))' -Properties primaryGroupID)
        @($found | ForEach-Object { "$($_.Name) $($_.primaryGroupID)" }) | Should -Be @('ORD-08 1106')
        @(Get-ADObject -Server demo.local -LDAPFilter '(&(primaryGroupID=*))' | Where-Object ObjectClass -eq 'group') | Should -BeNullOrEmpty
        @(Get-ADObject -Server demo.local -LDAPFilter '(&(objectClass=user)(primaryGroupID=513))' -ResultSetSize 1).ObjectClass | Should -Be 'user'
    }

    It 'Gives each member its class and login' {
        $member = Get-ADObject -Server nord.demo.local -LDAPFilter "(&(memberOf=$script:PostesNord))"
        $member.ObjectClass | Should -BeExactly 'computer'
        $member.sAMAccountName | Should -BeExactly 'ORD-01$'
    }

    It 'Reads one object by its DN, in its domain' {
        (Get-ADObject -Server nord.demo.local -Identity $script:Nadia).ObjectClass | Should -BeExactly 'user'
        { Get-ADObject -Server demo.local -Identity $script:Nadia } | Should -Throw 'Cannot find an object*'
    }
}

Describe 'Fake AD: computers by creation date' {
    It "Compares whenCreated with a date variable of the caller's, like AD: ORD-03, joined 5 days ago, is newer than <Days> days ago" -ForEach @(
        @{ Days = 90; Expected = @('ORD-05', 'ORD-07') }
        @{ Days = -1; Expected = @('ORD-03', 'ORD-05', 'ORD-07') }
    ) {
        $CreatedBefore = (Get-Date).Date.AddDays(-$Days)
        $filter = "Name -like 'ORD-0*' -and -not (Description -like '*') -and whenCreated -lt `$CreatedBefore"
        @(Get-ADComputer -Server demo.local -Filter $filter | Sort-Object Name).Name | Should -Be $Expected
    }

    It 'Refuses a variable that is not set, as AD does' {
        { Get-ADComputer -Server demo.local -Filter 'whenCreated -lt $NotSetAnywhere' } | Should -Throw "Variable: 'NotSetAnywhere' found in expression*"
    }
}

Describe 'Fake AD: BitLocker recovery information by its ID' {
    It 'Finds the keys whose ID starts so, in the domain asked: <Id> in <Domain>' -ForEach @(
        @{ Domain = 'demo.local'; Id = '6F1C2E7A'; Expected = @('CN=ORD-09,OU=Postes,DC=demo,DC=local') }
        @{ Domain = 'demo.local'; Id = 'A2E47C19-5D3B'; Expected = @('CN=ORD-09,OU=Postes,DC=demo,DC=local') }
        @{ Domain = 'demo.local'; Id = '0D8B5F21'; Expected = @('CN=ORD-07,OU=Postes,DC=demo,DC=local') }
        @{ Domain = 'demo.local'; Id = 'FFFFFFFF'; Expected = @() }
        @{ Domain = 'nord.demo.local'; Id = '6F1C2E7A'; Expected = @() }
    ) {
        $keys = @(Get-ADObject -Server $Domain -LDAPFilter "(&(objectClass=msFVE-RecoveryInformation)(name=*{$Id*))")
        @($keys | ForEach-Object { $_.DistinguishedName.Substring($_.DistinguishedName.IndexOf('},') + 2) }) | Should -Be $Expected
        @($keys | Where-Object ObjectClass -ne 'msFVE-RecoveryInformation').Count | Should -Be 0
    }
}

Describe 'Fake AD: a DC knows its own domain, the global catalog the forest' {
    It "A DC lists only its domain's members of a universal group" {
        @(Get-ADObject -Server nord.demo.local -LDAPFilter "(&(memberOf=$script:PostesNord))").Name | Should -Be @('ORD-01')
        Get-ADObject -Server demo.local -LDAPFilter "(&(memberOf=$script:PostesNord))" | Should -BeNullOrEmpty
    }

    It 'The global catalog lists its members of every domain' {
        $members = @(Get-ADObject -Server 'dc1.demo.local:3268' -SearchBase '' -LDAPFilter "(&(memberOf=$script:PostesNord))" | Sort-Object Name)
        $members.DistinguishedName | Should -Be @(
            'CN=GG-Postes-Accueil,OU=Groupes,DC=demo,DC=local', 'CN=ORD-01,OU=Postes,DC=nord,DC=demo,DC=local', 'CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local'
        )
    }

    It "The global catalog doesn't know a domain local group's members" {
        Get-ADObject -Server 'dc1.demo.local:3268' -SearchBase '' -LDAPFilter "(&(memberOf=$script:PartageAccueil))" | Should -BeNullOrEmpty
    }

    It "An object's MemberOf, read on its DC, leaves out the groups of the other domain" {
        (Get-ADComputer -Server demo.local -Identity 'CN=ORD-04,OU=Communs-Kiosques,OU=Kiosques,DC=demo,DC=local' -Properties MemberOf).MemberOf |
            Should -Be @('CN=GG-GPO-Kiosques,OU=Groupes,DC=demo,DC=local')
        (Get-ADUser -Server nord.demo.local -Identity $script:Nadia -Properties MemberOf).MemberOf | Should -BeNullOrEmpty
    }

    It 'tokenGroups holds the universal groups of any domain, and the domain local ones of its own' {
        $sids = (Get-ADComputer -Server demo.local -Identity 'CN=ORD-01,OU=Postes,DC=demo,DC=local' -Properties tokenGroups).tokenGroups
        $sids | Should -Contain 'S-1-5-21-4444-5555-6666-1201'
        $sids | Should -Contain 'S-1-5-21-1111-2222-3333-1103'
        (Get-ADUser -Server nord.demo.local -Identity $script:Nadia -Properties tokenGroups).tokenGroups | Should -Not -Contain 'S-1-5-21-1111-2222-3333-1113'
    }

    It 'Finds the global catalog, unless told none answers' {
        (Get-ADDomainController -Discover -Service GlobalCatalog).HostName | Should -Be @('dc1.demo.local')
        $env:REPERE_FAKEAD_NO_GC = '1'
        try { { Get-ADDomainController -Discover -Service GlobalCatalog } | Should -Throw }
        finally { $env:REPERE_FAKEAD_NO_GC = $null }
    }

    It "Gives each domain's SID and PDC" {
        $domain = Get-ADDomain -Server nord.demo.local
        $domain.DomainSID | Should -BeExactly 'S-1-5-21-4444-5555-6666'
        $domain.PDCEmulator | Should -BeExactly 'dc1.nord.demo.local'
    }
}

Describe 'Fake AD: its log' {
    It 'Writes each command and its parameters as a JSON line when REPERE_FAKEAD_LOG is set' {
        $env:REPERE_FAKEAD_LOG = Join-Path $TestDrive 'fakead.log'
        try {
            $null = Get-ADGroup -Server demo.local -LDAPFilter '(&(objectCategory=group)(name=*vpn*))' -Properties Description
            $null = Get-ADObject -Server 'dc1.demo.local:3268' -SearchBase '' -LDAPFilter "(&(memberOf=$script:PostesNord))" -ResultSetSize 201
            $log = @(Read-FakeADLog)
        }
        finally { $env:REPERE_FAKEAD_LOG = $null }
        $log.Count | Should -Be 2
        $log[0].Command | Should -BeExactly 'Get-ADGroup'
        $log[0].Server | Should -BeExactly 'demo.local'
        $log[0].Properties | Should -BeExactly 'Description'
        $log[1].Command | Should -BeExactly 'Get-ADObject'
        $log[1].ResultSetSize | Should -Be 201
    }

}

Describe 'Fake AD: computers by a -like filter' {
    It 'Reads * as any text, \2a as a star and \5c as a backslash' {
        InModuleScope FakeAD {
            Test-FakeADLike 'Salle 1 * prêt' '*1*prêt*' | Should -BeTrue
            Test-FakeADLike 'Salle 1 * prêt' '*\2a*' | Should -BeTrue
            Test-FakeADLike 'Salle 1 prêt' '*\2a*' | Should -BeFalse
            Test-FakeADLike 'Salle 1 prêt' '*1\2aprêt*' | Should -BeFalse
            Test-FakeADLike 'DEMO\jbertrand' '*demo\5cj*' | Should -BeTrue
            Test-FakeADLike $null '*' | Should -BeFalse
        }
    }
}
