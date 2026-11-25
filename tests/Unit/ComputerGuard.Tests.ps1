# What Désactiver, Supprimer de l'AD and Déplacer vers leave alone (ComputerActions.ps1's Get-ComputerGuard, and
# Remove-ComputerFromAD's last check): the computer Repère runs on, whose CN isn't always its name. In the fake AD,
# ORD-10's account is SALLE-REU2$: its CN was renamed in ADUC. The UI tests' Safeguards session runs it on the window.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD
    $env:REPERE_FAKEAD_LOG = Join-Path ([System.IO.Path]::GetTempPath()) "repere-guard-tests-$PID.log"

    # ComputerActions.ps1 loads only with the window, and Test-SelfAccount is the main script's: the functions alone,
    # from their source.
    $actions = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerActions.ps1')
    $main = Get-RepereScriptAst $script:RepereMainScript
    foreach ($function in @(
        @{ Ast = $actions; Name = 'Get-DomainControllerDN' }, @{ Ast = $actions; Name = 'Get-SelfComputerDN' },
        @{ Ast = $actions; Name = 'Get-ComputerGuard' }, @{ Ast = $actions; Name = 'Remove-ComputerFromAD' },
        @{ Ast = $main; Name = 'Test-SelfAccount' }, @{ Ast = (Get-RepereScriptAst (Join-Path $script:RepereSource 'GroupsDialog.ps1')); Name = 'Get-DomainOfDN' })) {
        $definition = $function.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $function.Name }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $script:ComputerNotLeaf = @{ Pattern = 'leaf object|objet feuille'; Code = 8213 }

    function New-GuardRow([string]$Name, [string]$Domain = 'demo.local', [string]$OU = 'Postes') {
        # A row as the grid has it, of what the guard reads.
        $base = ($Domain -split '\.' | ForEach-Object { "DC=$_" }) -join ','
        [pscustomobject]@{ ComputerName = $Name; Domain = $Domain; DistinguishedName = "CN=$Name,OU=$OU,$base" }
    }

    function Set-Self([string[]]$Names, [string]$DN = '', [string]$Domain = 'demo.local') {
        # The computer Repère runs on, as the main script reads it: its names, the DN Windows wrote, its domain.
        $script:Self = @{ Computer = @($Names); ComputerDN = $DN; ComputerDomain = $Domain; User = ''; UserDomain = '' }
    }

    function Get-AccountQuery {
        # The queries for the computer's own account the fake AD received.
        @(Read-FakeADLog | Where-Object { $_.Command -eq 'Get-ADObject' -and $_.LDAPFilter -like '*sAMAccountName=*' })
    }
}

AfterAll {
    Clear-FakeADLog
    $env:REPERE_FAKEAD_LOG = $null
}

Describe 'Get-ComputerGuard: the computer Repère runs on, whatever its CN' {
    BeforeEach { Clear-FakeADLog }

    It 'Knows it by its account when its CN is another name (ORD-10, renamed in ADUC from SALLE-REU2)' {
        Set-Self 'SALLE-REU2'
        $guard = Get-ComputerGuard @((New-GuardRow 'ORD-10'), (New-GuardRow 'ORD-11' -OU 'Communs-Entree,OU=Communs,OU=Postes'))
        $guard.Skipped | Should -Be @("ORD-10 (l'ordinateur où Repère est ouvert)")
        @($guard.Allowed.ComputerName) | Should -Be @('ORD-11')
    }

    It 'Knows it by the name it takes at its next restart: renamed in the domain, it already has it in AD' {
        Set-Self 'ANCIEN-NOM', 'SALLE-REU2'
        (Get-ComputerGuard @(New-GuardRow 'ORD-10')).Skipped | Should -Be @("ORD-10 (l'ordinateur où Repère est ouvert)")
        @(Get-AccountQuery)[0].LDAPFilter | Should -BeExactly '(|(sAMAccountName=ANCIEN-NOM$)(sAMAccountName=SALLE-REU2$))'
    }

    It 'Knows it by the DN Windows wrote, whatever its case, when AD has no account of its name' {
        Set-Self 'PC-INCONNU' 'cn=ord-06,ou=postes,dc=demo,dc=local'
        $guard = Get-ComputerGuard @((New-GuardRow 'ORD-06'), (New-GuardRow 'ORD-02'))
        $guard.Skipped | Should -Be @("ORD-06 (l'ordinateur où Repère est ouvert)")
        @($guard.Allowed.ComputerName) | Should -Be @('ORD-02')
    }

    It 'Leaves alone a computer the DN Windows wrote now names, once AD says which account is its own (renamed in ADUC, then a new computer under its old CN)' {
        Set-Self 'SALLE-REU2' 'CN=ORD-06,OU=Postes,DC=demo,DC=local'
        $guard = Get-ComputerGuard @((New-GuardRow 'ORD-06'), (New-GuardRow 'ORD-10'))
        $guard.Skipped | Should -Be @("ORD-10 (l'ordinateur où Repère est ouvert)")
        @($guard.Allowed.ComputerName) | Should -Be @('ORD-06')
    }

    It 'Asks AD for its account when the row''s Domain is a DC''s name, its domain read from the DN' {
        Set-Self 'SALLE-REU2'
        Mock Get-DomainControllerDN { , [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
        $row = New-GuardRow 'ORD-10'
        $row.Domain = 'dc1.demo.local'
        (Get-ComputerGuard @($row)).Skipped | Should -Be @("ORD-10 (l'ordinateur où Repère est ouvert)")
        @(Get-AccountQuery).Count | Should -Be 1
    }

    It 'Still knows it by its name when AD can''t say which account is its own' {
        Set-Self 'ORD-02'
        Mock Get-ADObject { throw 'The server is not operational' } -ParameterFilter { $LDAPFilter -like '*sAMAccountName=*' }
        Mock Write-Host { }
        $guard = Get-ComputerGuard @((New-GuardRow 'ORD-02'), (New-GuardRow 'ORD-10'))
        $guard.Skipped | Should -Be @("ORD-02 (l'ordinateur où Repère est ouvert)")
        @($guard.Allowed.ComputerName) | Should -Be @('ORD-10')
        Should -Invoke Write-Host -Times 1 -Exactly
    }

    It 'Asks AD once for many computers, and not at all when none is in its domain' {
        Set-Self 'SALLE-REU2'
        $null = Get-ComputerGuard @((New-GuardRow 'ORD-01'), (New-GuardRow 'ORD-02'), (New-GuardRow 'ORD-10'))
        @(Get-AccountQuery).Count | Should -Be 1
        Clear-FakeADLog
        $guard = Get-ComputerGuard @((New-GuardRow 'ORD-01' 'nord.demo.local'), (New-GuardRow 'NRD-01' 'nord.demo.local' 'Communs,OU=Postes'))
        Get-AccountQuery | Should -BeNullOrEmpty
        $guard.Skipped | Should -BeNullOrEmpty
    }

    It 'Leaves a computer of the same name in another domain alone' {
        Set-Self 'ORD-01'
        $guard = Get-ComputerGuard @((New-GuardRow 'ORD-01'), (New-GuardRow 'ORD-01' 'nord.demo.local'))
        $guard.Skipped | Should -Be @("ORD-01 (l'ordinateur où Repère est ouvert)")
        @($guard.Allowed.Domain) | Should -Be @('nord.demo.local')
    }

    It 'Still leaves out a domain controller first' {
        Set-Self 'DC1'
        (Get-ComputerGuard @(New-GuardRow 'DC1' -OU 'Domain Controllers')).Skipped | Should -Be @('DC1 (contrôleur de domaine)')
    }
}

Describe 'Remove-ComputerFromAD: the computer Repère runs on, refused again as AD has it' {
    BeforeEach { Clear-FakeADLog }

    It 'Refuses it, known by its account, its CN being another name, and deletes nothing' {
        Set-Self 'SALLE-REU2'
        { Remove-ComputerFromAD 'CN=ORD-10,OU=Postes,DC=demo,DC=local' 'dc1.demo.local' } | Should -Throw "l'ordinateur où Repère est ouvert, non supprimé"
        @(Read-FakeADLog | Where-Object Command -like 'Remove-*') | Should -BeNullOrEmpty
    }

    It 'Refuses by the DN Windows wrote only when AD gives no account' {
        Set-Self 'PC-INCONNU' 'CN=ORD-10,OU=Postes,DC=demo,DC=local'
        Mock Get-ADObject { [pscustomobject]@{ ProtectedFromAccidentalDeletion = $false; PrimaryGroupID = 515; sAMAccountName = $null } } -ParameterFilter { $Identity -and $Properties -contains 'sAMAccountName' }
        { Remove-ComputerFromAD 'CN=ORD-10,OU=Postes,DC=demo,DC=local' 'demo.local' } | Should -Throw "l'ordinateur où Repère est ouvert, non supprimé"
        @(Read-FakeADLog | Where-Object Command -like 'Remove-*') | Should -BeNullOrEmpty
    }

    It 'Deletes the computer the DN Windows wrote now names, when AD says its account is another''s' {
        Set-Self 'PC-INCONNU' 'CN=ORD-06,OU=Postes,DC=demo,DC=local'
        { $null = Remove-ComputerFromAD 'CN=ORD-06,OU=Postes,DC=demo,DC=local' 'demo.local' } | Should -Not -Throw
    }

    It 'Refuses everything when it can''t tell which computer is its own (Self not passed to the runspace)' {
        $script:Self = $null
        { Remove-ComputerFromAD 'CN=ORD-03,OU=Postes,DC=demo,DC=local' 'demo.local' } | Should -Throw "l'ordinateur où Repère est ouvert inconnu, non supprimé"
        @(Read-FakeADLog | Where-Object Command -like 'Remove-*') | Should -BeNullOrEmpty
    }

    It 'Deletes another computer' {
        Set-Self 'SALLE-REU2'
        Remove-ComputerFromAD 'CN=ORD-03,OU=Postes,DC=demo,DC=local' 'demo.local' | Should -Be 0
        @(Read-FakeADLog | Where-Object Command -eq 'Remove-ADComputer').Identity | Should -Be @('CN=ORD-03,OU=Postes,DC=demo,DC=local')
    }
}

Describe 'Start-ComputerGuard: the guard read in the background, the window usable meanwhile (#247)' {
    BeforeAll {
        # What the window gives Start-WindowRead and the guard's answers: its pointer, the dialogs (kept, not shown), and
        # a search runspace with the fake AD, as Repère opens them. The fake AD made again: the checks above deleted
        # ORD-06, whose contents one of these reads.
        Import-RepereFakeAD
        foreach ($name in 'Read-ComputerGuard', 'Start-ComputerGuard', 'ConvertTo-ReadComputer', 'Show-ComputerGuard', 'Read-ComputerContent', 'Format-BitLockerKey', 'Get-BitLockerKey') {
            $definition = $actions.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:win = [pscustomobject]@{ Cursor = $null }
        $script:rowBuilderScript = $script:LanguageScript
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        function Show-Dialog { $script:Shown.Add("Dialog: $($args -join ' ')") }
        function Show-ActionReport { $script:Shown.Add("Report: $($args -join ' ')") }
        $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $state.ImportPSModule((Join-Path $script:RepereSource 'FakeAD\FakeAD.psm1'))
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 2, $state, $Host)
        $script:searchPool.Open()

        function Wait-Guard {
            # The reads under way, until they end, then their OnDone, as the window's timer runs it.
            for ($i = 0; $i -lt 200 -and @($script:BackgroundReadList | Where-Object { -not $_.Handle.IsCompleted }).Count; $i++) { Start-Sleep -Milliseconds 50 }
            Complete-BackgroundRead
        }
    }

    AfterAll {
        $script:searchPool.Dispose()
        $script:searchPool = $null
    }

    BeforeEach {
        $script:Shown.Clear()
        $script:Allowed = [System.Collections.Generic.List[object]]::new()
        Set-Self 'SALLE-REU2'
    }

    AfterEach {
        $env:REPERE_FAKEAD_SLOW = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $null
    }

    It 'Returns at once while a slow DC answers, then gives the rows allowed and those left alone' {
        $env:REPERE_FAKEAD_SLOW = 'demo.local=1500'
        $rows = @((New-GuardRow 'DC1' -OU 'Domain Controllers'), (New-GuardRow 'ORD-10'), (New-GuardRow 'ORD-02'))
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Start-ComputerGuard 'Désactiver' 'ban' $rows { param($selected, $skipped) $script:Allowed.Add(@{ Selected = $selected; Skipped = $skipped }) }
        $watch.ElapsedMilliseconds | Should -BeLessThan 1000
        $script:Allowed.Count | Should -Be 0
        Wait-Guard
        $script:Allowed.Count | Should -Be 1
        $script:Allowed[0].Selected.Count | Should -Be 1
        [object]::ReferenceEquals($script:Allowed[0].Selected[0], $rows[2]) | Should -BeTrue
        $script:Allowed[0].Skipped | Should -Be @('DC1 (contrôleur de domaine)', "ORD-10 (l'ordinateur où Repère est ouvert)")
        $script:WindowReadList.Count | Should -Be 0
    }

    It 'Asks once when clicked twice while it reads' {
        $env:REPERE_FAKEAD_SLOW = 'demo.local=500'
        $rows = @(New-GuardRow 'ORD-02')
        Start-ComputerGuard 'Déplacer' 'move' $rows { param($selected) $script:Allowed.Add($selected) }
        Start-ComputerGuard 'Déplacer' 'move' $rows { param($selected) $script:Allowed.Add($selected) }
        Wait-Guard
        $script:Allowed.Count | Should -Be 1
    }

    It 'Allows none of a domain AD can''t say the controllers of, and says why' {
        $env:REPERE_FAKEAD_UNREACHABLE = 'nord.demo.local'
        Start-ComputerGuard 'Désactiver' 'ban' @(New-GuardRow 'ORD-01' 'nord.demo.local') { param($selected) $script:Allowed.Add($selected) }
        Wait-Guard
        $script:Allowed.Count | Should -Be 0
        $script:Shown.Count | Should -Be 1
        $script:Shown[0] | Should -BeLike 'Dialog:*rien à faire*ORD-01 (contrôleur de domaine ou non, AD ne le dit pas :*'
    }

    It 'Reads what goes with the computers allowed, for Supprimer de l''AD, in the same read' {
        Start-ComputerGuard "Supprimer de l'AD" 'trash' @((New-GuardRow 'ORD-10'), (New-GuardRow 'ORD-06')) -WithContents {
            param($selected, $skipped, $contents)
            $script:Allowed.Add(@{ Selected = $selected; Contents = $contents })
        }
        Wait-Guard
        @($script:Allowed[0].Selected.ComputerName) | Should -Be @('ORD-06')
        $script:Allowed[0].Contents.Text | Should -BeLike 'ORD-06 : aucune clé BitLocker*Aussi supprimé : Windows Virtual Machine (serviceConnectionPoint)*'
        $script:Allowed[0].Contents.Others | Should -Be 1
    }

    It 'Leaves the window''s thread out of it: Get-ComputerGuard is only called by the background read' {
        $callers = @($actions.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Get-ComputerGuard' }, $true) | ForEach-Object {
            $parent = $_.Parent
            while ($parent -and $parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $parent = $parent.Parent }
            if ($parent) { $parent.Name } else { '(script)' }
        })
        $callers | Should -Be @('Read-ComputerGuard')
    }
}

Describe 'The selection the actions read' {
    It 'Is never wrapped by @() around the call, which would make it one item: the guard would let every computer through' {
        # Get-SelectedComputer and Get-PageSelection return their list as one object (, $list): stored in a variable,
        # it's the list; inside @(), a list of one list.
        $wrapped = foreach ($path in Get-ChildItem -LiteralPath $script:RepereSource -Filter *.ps1) {
            $ast = Get-RepereScriptAst $path.FullName
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ArrayExpressionAst] -and $node.Extent.Text -match '^@\(\s*(Get-SelectedComputer|Get-PageSelection\s+\S+)\s*\)$' -and
                    $node.Parent -isnot [System.Management.Automation.Language.IndexExpressionAst] }, $true) |
                ForEach-Object { "$($path.Name):$($_.Extent.StartLineNumber)" }
        }
        $wrapped | Should -BeNullOrEmpty
    }
}
