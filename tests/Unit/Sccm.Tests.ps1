# What asks SCCM (Sccm.ps1), with the fake SCCM: the runspace the reads share, the four answers about a computer, its
# inventory, and Paramètres › SCCM › Tester. The names Prochain nom… asks for are NextName.Tests.ps1's.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    $script:FakeSccmModule = Join-Path $script:RepereSource 'FakeAD\FakeSccm.psm1'
    $script:Site = @{ Site = 'DEM'; Server = 'sccm.demo.local' }
    $script:Id = 16777217

    function Reset-Sccm {
        # As Repère starts: no runspace, no rest, the fake site as it is by default.
        foreach ($name in 'UNREACHABLE', 'DELAY', 'ERROR', 'MOUNTED', 'LIMITED', 'REFUSED', 'NOCOLUMN', 'LOG', 'STUCK', 'DEAD', 'BREAK') { [Environment]::SetEnvironmentVariable("REPERE_FAKEAD_SCCM_$name", $null) }
        Close-SccmRunspace $script:SccmLink
        $script:SccmLink.RestUntil = [datetime]::MinValue
        $script:SccmTimeoutSeconds, $script:SccmQuerySeconds, $script:SccmTotalSeconds = 60, 20, 120
    }

    function Open-SearchPool {
        # Search runspaces as Repère's, for the reads started in the background; Close-SearchPool puts back what they changed.
        $script:rowBuilderScript = $script:LanguageScript + [Environment]::NewLine + [string](Get-RepereRowBuilder)
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 4)
        $script:searchPool.Open()
        $script:SavedFakeAD = if (Test-Path variable:script:fakeADModule) { $script:fakeADModule }
        $script:fakeADModule = Join-Path $script:RepereSource 'FakeAD\FakeAD.psm1'
    }

    function Close-SearchPool {
        $script:fakeADModule = $script:SavedFakeAD
        $script:searchPool.Dispose()
        $script:searchPool = $null
    }

    function Start-PoolRead([string]$Command, [object[]]$Arguments, $Context) {
        # A read on a search runspace, and where its answer goes: Result, Problem, Ended.
        $done = @{ Result = $null; Problem = $null; Ended = $false }
        Start-BackgroundRead -Command $Command -Arguments $Arguments -Functions (Get-SccmReadFunction) -Variables (Get-SccmReadVariable) -Context $Context -OnDone {
            param($context, $result, $problem)
            $done.Result, $done.Problem, $done.Ended = $result, $problem, $true
        }.GetNewClosure()
        $done
    }

    function Wait-PoolRead($Done) { for ($i = 0; $i -lt 150 -and @($Done | Where-Object { -not $_.Ended }).Count; $i++) { Start-Sleep -Milliseconds 100; Complete-BackgroundRead } }

    function Wait-SccmBusy { for ($i = 0; $i -lt 50 -and $script:SccmLink.Gate.CurrentCount; $i++) { Start-Sleep -Milliseconds 100 }; $script:SccmLink.Gate.CurrentCount | Should -Be 0 }

    function Clear-Sccm { for ($i = 0; $i -lt 150 -and $script:SccmStopping.Count; $i++) { Clear-SccmStopping; Start-Sleep -Milliseconds 100 } }

    function Get-Find([string]$Name) { Find-SccmDevice $script:Site -Name $Name }

    function New-Record([int64]$Id, [string]$Name = 'PC-1', [hashtable]$More = @{}) {
        $record = [ordered]@{ ResourceID = $Id; Name = $Name; SID = ''; FullDomainName = ''; ResourceDomainORWorkgroup = ''; Active = 1; Client = 1; ClientVersion = ''; Obsolete = 0; Decommissioned = 0 }
        foreach ($key in $More.Keys) { $record[$key] = $More[$key] }
        [pscustomobject]$record
    }
}

AfterAll {
    Reset-Sccm
    Clear-Sccm
}

Describe 'The four answers about a computer' {
    BeforeEach { Reset-Sccm }

    It 'Found: one record' {
        $answer = Select-SccmDevice (Get-Find 'ORD-01') 'ORD-01'
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.ResourceID | Should -Be $script:Id
    }

    It 'Not found: SCCM answered, with no record' {
        $answer = Select-SccmDevice (Get-Find 'INCONNU-01') 'INCONNU-01'
        $answer.Answer | Should -BeExactly 'NotFound'
        $answer.Device | Should -BeNullOrEmpty
    }

    It 'Not found, the same, for a computer the account can''t see' {
        $env:REPERE_FAKEAD_SCCM_LIMITED = 'ORD-13'
        (Select-SccmDevice (Get-Find 'ORD-01') 'ORD-01').Answer | Should -BeExactly 'NotFound'
        (Select-SccmDevice (Get-Find 'ORD-13') 'ORD-13').Answer | Should -BeExactly 'Found'
    }

    It 'Ambiguous: two current records, the latest first' {
        $answer = Select-SccmDevice (Get-Find 'DOUBLE-01') 'DOUBLE-01'
        $answer.Answer | Should -BeExactly 'Ambiguous'
        @($answer.Candidates.ResourceID) | Should -Be 16777222, 16777221
        $answer.Device.ResourceID | Should -Be 16777222
    }

    It 'Not checked, with the reason: <Case>' -ForEach @(
        @{ Case = 'a server that doesn''t answer'; Variable = 'UNREACHABLE'; Value = '1'; Reason = 'sccm.demo.local ne répond pas' }
        @{ Case = 'a query refused'; Variable = 'REFUSED'; Value = 'SMS_R_System'; Reason = 'Accès refusé' }
    ) {
        [Environment]::SetEnvironmentVariable("REPERE_FAKEAD_SCCM_$Variable", $Value)
        $answer = Select-SccmDevice (Get-Find 'ORD-01') 'ORD-01'
        $answer.Answer | Should -BeExactly 'NotChecked'
        $answer.Reason | Should -BeExactly $Reason
        $answer.Device | Should -BeNullOrEmpty
    }
}

Describe 'Which record is this computer' {
    BeforeEach { Reset-Sccm }

    BeforeAll { function Select-Record($Records, [string]$Sid, [string]$Domain) { Select-SccmDevice @{ Checked = $true; Reason = ''; Devices = @($Records) } 'PC-1' $Sid $Domain } }

    It 'The one with its SID, whatever the others are' {
        $answer = Select-Record @((New-Record 1 -More @{ SID = 'S-1' }), (New-Record 9 -More @{ SID = 'S-2' }), (New-Record 8)) 'S-1'
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.ResourceID | Should -Be 1
    }

    It 'One with another SID is never taken for it, only a candidate' {
        (Select-Record @(New-Record 1 -More @{ SID = 'S-2' }) 'S-1').Answer | Should -BeExactly 'Ambiguous'
    }

    It 'One without a SID is, before one with another' {
        $answer = Select-Record @((New-Record 1), (New-Record 9 -More @{ SID = 'S-2' })) 'S-1'
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.ResourceID | Should -Be 1
    }

    It 'Not one of another domain: <Full> <Short> for <Domain>, <Expected>' -ForEach @(
        @{ Full = 'a.local'; Short = 'A'; Domain = 'a.local'; Expected = 'Found' }
        @{ Full = 'b.local'; Short = 'B'; Domain = 'a.local'; Expected = 'NotFound' }
        @{ Full = ''; Short = 'A'; Domain = 'a.local'; Expected = 'Found' }
        @{ Full = ''; Short = 'B'; Domain = 'a.local'; Expected = 'Ambiguous' }
        @{ Full = ''; Short = ''; Domain = 'a.local'; Expected = 'Found' }
        @{ Full = 'b.local'; Short = 'B'; Domain = ''; Expected = 'Found' }
    ) {
        (Select-Record @(New-Record 1 -More @{ FullDomainName = $Full; ResourceDomainORWorkgroup = $Short }) '' $Domain).Answer | Should -BeExactly $Expected
    }

    It 'A short domain name that isn''t the DNS name''s start may still be its own: only a candidate' {
        (Select-Record @(New-Record 1 -More @{ ResourceDomainORWorkgroup = 'CORP' }) '' 'contoso.com').Answer | Should -BeExactly 'Ambiguous'
        (Select-Record @(New-Record 1 -More @{ FullDomainName = 'contoso.com' }) '' 'CORP').Answer | Should -BeExactly 'Ambiguous'
        # Unless the SID says so.
        (Select-Record @(New-Record 1 -More @{ ResourceDomainORWorkgroup = 'CORP'; SID = 'S-1' }) 'S-1' 'contoso.com').Answer | Should -BeExactly 'Found'
    }

    It 'An obsolete record with its SID, not before a current one without' {
        $answer = Select-Record @((New-Record 9 -More @{ SID = 'S-1'; Obsolete = 1 }), (New-Record 1)) 'S-1'
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.ResourceID | Should -Be 1
    }

    It 'An obsolete record, and a current one with another SID: neither is taken for it' {
        (Select-Record @((New-Record 1 -More @{ Obsolete = 1 }), (New-Record 2 -More @{ SID = 'S-2' })) 'S-1').Answer | Should -BeExactly 'Ambiguous'
        $answer = Select-Record @((New-Record 1 -More @{ SID = 'S-1'; Obsolete = 1 }), (New-Record 2 -More @{ SID = 'S-2' })) 'S-1'
        $answer.Answer | Should -BeExactly 'Ambiguous'
        $answer.Candidates.Count | Should -Be 2
    }

    It 'A decommissioned record counts as an obsolete one' {
        $answer = Select-Record @((New-Record 9 -More @{ Decommissioned = 1 }), (New-Record 1))
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.ResourceID | Should -Be 1
    }

    It 'The current record rather than an obsolete one, which counts when it''s alone' {
        $answer = Select-SccmDevice (Get-Find 'RENTRE-01') 'RENTRE-01'
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.ResourceID | Should -Be 16777224
        $answer = Select-SccmDevice (Get-Find 'VIEUX-01') 'VIEUX-01'
        $answer.Answer | Should -BeExactly 'Found'
        $answer.Device.Obsolete | Should -Be 1
    }

    It 'Of several names asked together, its own only' {
        $find = Find-SccmDevice $script:Site -Name 'ORD-01', 'ORD-13', 'INCONNU-01', 'ord-01'
        $find.Devices.Count | Should -Be 2
        (Select-SccmDevice $find 'ord-13').Device.ResourceID | Should -Be 16777218
        (Select-SccmDevice $find 'INCONNU-01').Answer | Should -BeExactly 'NotFound'
    }
}

Describe 'Finding devices' {
    BeforeEach { Reset-Sccm }

    It 'Asks by batches, and a batch that fails fails the whole: none of it looks missing' {
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'batches.txt'
        $names = @(1..120 | ForEach-Object { "X-$_" }) + 'ORD-01'
        $find = Find-SccmDevice $script:Site -Name $names
        $find.Checked | Should -BeTrue
        $find.Devices.Name | Should -BeExactly 'ORD-01'
        @(Get-Content $env:REPERE_FAKEAD_SCCM_LOG).Count | Should -Be 3
        # The last batch alone: what the others gave isn't an answer.
        $env:REPERE_FAKEAD_SCCM_REFUSED = "'ORD-01'"
        $find = Find-SccmDevice $script:Site -Name (@('ORD-13') + $names)
        $find.Checked | Should -BeFalse
        $find.Devices | Should -BeNullOrEmpty
        (Select-SccmDevice $find 'ORD-13').Answer | Should -BeExactly 'NotChecked'
    }

    It 'A record whose <Column> can''t be read is no answer, rather than no record' -ForEach @(@{ Column = 'Name' }, @{ Column = 'ResourceID' }) {
        $link = $script:SccmLinkScript
        $script:SccmLinkScript = [scriptblock]::Create(([string]$link).Replace('$values[$name] = $row.$name', "if (`$name -ne '$Column') { `$values[`$name] = `$row.`$name }"))
        try { $find = Get-Find 'ORD-01' }
        finally { $script:SccmLinkScript = $link }
        $find.Checked | Should -BeFalse
        $find.Reason | Should -BeExactly 'sa réponse n''est pas lisible'
    }

    It 'All the columns are only asked for when the site refuses their names, not when it refuses the account' {
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'columns.txt'
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'R_System'
        (Get-Find 'ORD-01').Checked | Should -BeFalse
        @(Get-Content $env:REPERE_FAKEAD_SCCM_LOG).Count | Should -Be 1
    }

    It 'By serial number, and every record that has it' {
        (Find-SccmDevice $script:Site -Serial 'DEMO0001').Devices.Name | Should -BeExactly 'ORD-01'
        @((Find-SccmDevice $script:Site -Serial 'DEMO0021').Devices).Count | Should -Be 2
        $none = Find-SccmDevice $script:Site -Serial 'NONE'
        $none.Checked | Should -BeTrue
        $none.Devices | Should -BeNullOrEmpty
    }

    It 'A text that could change the query isn''t asked, and isn''t called not found: <Text>' -ForEach @(@{ Text = "' OR Name LIKE '%" }, @{ Text = "\' OR Name = 'ORD-01" }, @{ Text = 'A\' }) {
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'injection.txt'
        $find = Find-SccmDevice $script:Site -Name $Text, 'ORD-01'
        $find.Devices.Name | Should -BeExactly 'ORD-01'
        $answer = Select-SccmDevice $find $Text
        $answer.Answer | Should -BeExactly 'NotChecked'
        $answer.Reason | Should -BeExactly 'Repère ne cherche pas dans SCCM un nom avec ces caractères'
        $serial = Find-SccmDevice $script:Site -Serial $Text
        $serial.Checked | Should -BeFalse
        $serial.Reason | Should -BeExactly 'Repère ne cherche pas dans SCCM un numéro de série avec ces caractères'
        Get-Content $env:REPERE_FAKEAD_SCCM_LOG | Should -Not -Match ([regex]::Escape($Text))
    }

    It 'Still escapes what it sends: <Text>' -ForEach @(@{ Text = "A'B"; Expected = "A\'B" }, @{ Text = 'A\B'; Expected = 'A\\B' }) {
        ConvertTo-SccmText $Text | Should -BeExactly $Expected
    }

    It 'A column the site doesn''t have is empty, the others are read' {
        $env:REPERE_FAKEAD_SCCM_NOCOLUMN = 'SID'
        $find = Get-Find 'ORD-01'
        $find.Checked | Should -BeTrue
        $find.Devices[0].SID | Should -BeNullOrEmpty
        $find.Devices[0].ResourceID | Should -Be $script:Id
    }

    It 'Only ever reads' {
        $text = Get-Content (Join-Path $script:RepereSource 'Sccm.ps1') -Raw
        [regex]::Matches($text, '\b\w+-CM\w+') | ForEach-Object Value | Select-Object -Unique | Sort-Object | Should -Be 'Invoke-CMWmiQuery'
    }
}

Describe 'The inventory' {
    BeforeEach { Reset-Sccm }

    It 'Reads every section, with the columns asked for' {
        $inventory = Get-SccmInventory $script:Site $script:Id
        @($inventory.Keys) | Should -Be @($script:SccmSections.Keys)
        foreach ($name in $inventory.Keys) {
            $inventory[$name].Read | Should -BeTrue -Because $name
            $inventory[$name].Rows.Count | Should -BeGreaterThan 0 -Because $name
            @($inventory[$name].Rows[0].PSObject.Properties.Name) | Should -Be @($script:SccmSections[$name].Columns)
        }
        $inventory.Scan.Rows[0].LastHardwareScan | Should -BeOfType [datetime]
        $inventory.Network.Rows.Count | Should -Be 2
    }

    It 'A device without inventory is read, with no row' {
        $inventory = Get-SccmInventory $script:Site 16777219 -Section 'Scan', 'System'
        $inventory.Scan.Read | Should -BeTrue
        $inventory.Scan.Rows | Should -BeNullOrEmpty
    }

    It 'A class refused fails alone' {
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'PROCESSOR'
        $inventory = Get-SccmInventory $script:Site $script:Id -Section 'System', 'Processor', 'Disk'
        $inventory.Processor.Read | Should -BeFalse
        $inventory.Processor.Reason | Should -BeExactly 'Accès refusé'
        $inventory.System.Read | Should -BeTrue
        $inventory.Disk.Read | Should -BeTrue
    }

    It 'A class the site doesn''t have fails alone' {
        $saved = $script:SccmSections.Processor.Class
        $script:SccmSections.Processor.Class = 'SMS_G_System_NONE'
        try { $inventory = Get-SccmInventory $script:Site $script:Id -Section 'Processor', 'Disk' }
        finally { $script:SccmSections.Processor.Class = $saved }
        $inventory.Processor.Read | Should -BeFalse
        # Even as the first query of all: the site itself was opened.
        $inventory.Disk.Read | Should -BeTrue
    }

    It 'Once SCCM stops answering, the rest isn''t tried, and says the same reason' {
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'lost.txt'
        $env:REPERE_FAKEAD_SCCM_DELAY = '30'
        $script:SccmTimeoutSeconds = 2
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $inventory = Get-SccmInventory $script:Site $script:Id -Section 'System', 'Processor', 'Disk'
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 10
        foreach ($name in $inventory.Keys) {
            $inventory[$name].Read | Should -BeFalse
            $inventory[$name].Reason | Should -BeExactly 'SCCM n''a pas répondu en 2 secondes'
        }
        @(Get-Content $env:REPERE_FAKEAD_SCCM_LOG).Count | Should -Be 1
    }

    It 'The state of several devices, only those asked for' {
        $summary = Get-SccmSummary $script:Site 16777217, 16777218
        $summary.Checked | Should -BeTrue
        @($summary.Devices.Name) | Should -Be 'ORD-01', 'ORD-13'
        $summary.Devices[0].PrimaryUser | Should -BeExactly 'DEMO\mroy'
        $script:SccmBatchSize = 1
        $env:REPERE_FAKEAD_SCCM_REFUSED = '16777218'
        try { $summary = Get-SccmSummary $script:Site 16777217, 16777218 }
        finally { $script:SccmBatchSize = 50 }
        $summary.Checked | Should -BeFalse
        $summary.Devices | Should -BeNullOrEmpty
    }

    It 'Out of time, keeps what was read, and says the rest wasn''t' {
        $null = Get-Find 'ORD-01'
        $env:REPERE_FAKEAD_SCCM_DELAY = '1'
        $script:SccmTotalSeconds = 2
        $inventory = Get-SccmInventory $script:Site $script:Id
        $inventory.Scan.Read | Should -BeTrue
        $inventory.Scan.Rows.Count | Should -Be 1
        $inventory.Program64.Read | Should -BeFalse
        $inventory.Program64.Reason | Should -Match 'SCCM n''a pas répondu en \d+ secondes|la lecture n''avait plus le temps de le demander'
    }

    It 'A query is cut short at the end of its question, even with time of its own left' {
        $null = Get-Find 'ORD-01'
        $env:REPERE_FAKEAD_SCCM_DELAY = '8'
        $script:SccmTotalSeconds = 2
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        (Get-Find 'ORD-01').Reason | Should -BeExactly 'SCCM n''a pas répondu en 2 secondes'
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 5
    }

    It 'A query cut short by the end of its question doesn''t make SCCM rest' {
        $null = Get-Find 'ORD-01'
        $env:REPERE_FAKEAD_SCCM_DELAY = '3'
        $script:SccmTotalSeconds = 2
        (Get-Find 'ORD-01').Checked | Should -BeFalse
        $env:REPERE_FAKEAD_SCCM_DELAY = $null
        $script:SccmTotalSeconds = 120
        (Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic).Checked | Should -BeTrue
    }

    It 'A hung site that had its time is rested, even when its question ends with it' {
        # The first read, which has more time than the question has left.
        $script:SccmTimeoutSeconds, $script:SccmQuerySeconds, $script:SccmTotalSeconds = 10, 1, 2
        $env:REPERE_FAKEAD_SCCM_DELAY = '5'
        (Get-SccmName $script:Site 'ORD-01').Checked | Should -BeFalse
        $env:REPERE_FAKEAD_SCCM_DELAY = $null
        $script:SccmTotalSeconds = 120
        (Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic).Checked | Should -BeFalse
    }

    It 'A link that died with what looks like refusals ends the inventory, and is opened again' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $env:REPERE_FAKEAD_SCCM_DEAD = 'wql'
        $inventory = Get-SccmInventory $script:Site $script:Id
        @($inventory.Values | Where-Object { $_.Read }).Count | Should -Be 0
        $inventory.Program64.Reason | Should -BeExactly $inventory.Bios.Reason
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'dead.txt'
        (Get-Find 'ORD-01').Checked | Should -BeTrue
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeFalse
    }

    It 'A site that doesn''t collect a few classes in a row keeps the runspace' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'FROM \w*(PROCESSOR|MEMORY|DISK) '
        $inventory = Get-SccmInventory $script:Site $script:Id
        @($inventory.Values | Where-Object { -not $_.Read }).Count | Should -Be 5
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeTrue
    }

    It 'Behind a read that doesn''t end, waits its turn once, not for each section' {
        $script:SccmTimeoutSeconds = 1
        $script:SccmLink.Gate.Wait(0) | Should -BeTrue
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try { $inventory = Get-SccmInventory $script:Site $script:Id }
        finally { $null = $script:SccmLink.Gate.Release() }
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 4
        @($inventory.Values | Where-Object { $_.Read }).Count | Should -Be 0
    }
}

Describe 'Caractéristiques from SCCM (Get-SccmSpec)' {
    BeforeEach { Reset-Sccm }

    It 'Finds the computer and reads its inventory' {
        $read = Get-SccmSpec $script:Site 'ORD-06' 'demo.local'
        $read.Answer | Should -BeExactly 'Found'
        $read.Count | Should -Be 1
        $read.Inventory.System.Rows[0].Name | Should -BeExactly 'ORD-06'
        $read.Inventory.Scan.Rows[0].LastHardwareScan | Should -BeOfType [datetime]
    }

    It 'Reads no inventory of a computer SCCM has no record of' {
        $log = Join-Path $TestDrive 'specs-notfound.log'
        $env:REPERE_FAKEAD_SCCM_LOG = $log
        $read = Get-SccmSpec $script:Site 'ORD-09' 'demo.local'
        $read.Answer | Should -BeExactly 'NotFound'
        $read.Inventory | Should -BeNullOrEmpty
        # The log was written, by the search for its record: no inventory query isn't no query at all.
        Get-Content $log | Should -Match "FROM SMS_R_System WHERE Name IN \('ORD-09'\)"
        @(Get-Content $log | Where-Object { $_ -match 'SMS_G_System' }) | Should -BeNullOrEmpty
    }

    It 'Says a record SCCM never inventoried has no inventory, not an empty one' {
        $read = Get-SccmSpec $script:Site 'ORD-14' 'demo.local' 'S-1-5-21-1-2-3-9014'
        $read.Answer | Should -BeExactly 'NoInventory'
        $read.Reason | Should -BeExactly "SCCM n'a pas d'inventaire de cet ordinateur"
        $read.Inventory | Should -BeNullOrEmpty
        [int64]$read.Device.ResourceID | Should -Be 16777219
    }

    It 'Keeps an inventory whose sections failed, even with no row: its errors are to be seen' {
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'PC_BIOS'
        $read = Get-SccmSpec $script:Site 'ORD-14' 'demo.local' 'S-1-5-21-1-2-3-9014'
        $read.Answer | Should -BeExactly 'Found'
        $read.Inventory.Bios.Read | Should -BeFalse
        $read.Inventory.Bios.Reason | Should -BeExactly 'Accès refusé'
    }

    It 'Has no inventory with a date alone, or with a class refused that no section shows: <Name>' -ForEach @(
        @{ Name = 'RENTRE-01'; Refused = $null }
        @{ Name = 'ORD-14'; Refused = 'WORKSTATION_STATUS|PHYSICAL_MEMORY' }
    ) {
        $env:REPERE_FAKEAD_SCCM_REFUSED = $Refused
        $read = Get-SccmSpec $script:Site $Name 'demo.local'
        $read.Answer | Should -BeExactly 'NoInventory'
        $read.Reason | Should -BeExactly "SCCM n'a pas d'inventaire de cet ordinateur"
        $read.Inventory | Should -BeNullOrEmpty
    }

    It 'Reads the latest of several records, and says how many there are' {
        $read = Get-SccmSpec $script:Site 'DOUBLE-01' 'demo.local'
        $read.Answer | Should -BeExactly 'Ambiguous'
        $read.Count | Should -Be 2
        [int64]$read.Device.ResourceID | Should -Be 16777222
        $read.Latest | Should -BeTrue
        $read.Inventory | Should -Not -BeNullOrEmpty
    }

    It 'Reads an older record when the latest has no inventory, and says it isn''t the latest' {
        $read = Get-SccmSpec $script:Site 'DOUBLE-02' 'demo.local'
        $read.Answer | Should -BeExactly 'Ambiguous'
        $read.Count | Should -Be 2
        [int64]$read.Device.ResourceID | Should -Be 16777226
        $read.Latest | Should -BeFalse
        $read.LatestSkipped | Should -BeExactly 'Empty'
        $read.Inventory.System.Rows[0].Name | Should -BeExactly 'DOUBLE-02'
    }

    It 'Prefers an older record with rows to the latest whose sections failed' {
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'COMPUTER_SYSTEM'
        $read = Get-SccmSpec $script:Site 'DOUBLE-02' 'demo.local'
        [int64]$read.Device.ResourceID | Should -Be 16777226
        $read.Inventory.Bios.Rows[0].SerialNumber | Should -BeExactly 'DEMO0026'
        $read.Inventory.System.Read | Should -BeFalse
        # Not known empty: the note says it couldn't be read.
        $read.Latest | Should -BeFalse
        $read.LatestSkipped | Should -BeExactly 'Unread'
    }

    It 'Doesn''t show a record of which nothing was read after an empty latest: says it couldn''t be read' {
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'ResourceID = 16777226'
        $read = Get-SccmSpec $script:Site 'DOUBLE-02' 'demo.local'
        $read.Answer | Should -BeExactly 'NoInventory'
        $read.Reason | Should -BeExactly "SCCM n'a d'inventaire d'aucune fiche lue de cet ordinateur (1 sur 2) ; la suivante n'a pas pu être lue"
        $read.Inventory | Should -BeNullOrEmpty
    }

    It 'Doesn''t start another record without time for a whole inventory, and says it wasn''t read' {
        # Less time left than a query is given: the next record's queries would be cut short, and blamed on SCCM.
        $script:SccmQuerySeconds, $script:SccmTotalSeconds = 40, 30
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'specs-time.log'
        $read = Get-SccmSpec $script:Site 'DOUBLE-02' 'demo.local'
        $read.Answer | Should -BeExactly 'NoInventory'
        $read.Reason | Should -BeExactly "SCCM n'a d'inventaire d'aucune fiche lue de cet ordinateur (1 sur 2) ; la suivante n'a pas pu être lue"
        Get-Content $env:REPERE_FAKEAD_SCCM_LOG -Raw | Should -Match 'ResourceID = 16777227'
        Get-Content $env:REPERE_FAKEAD_SCCM_LOG -Raw | Should -Not -Match 'ResourceID = 16777226'
    }

    It 'Doesn''t ask for the next record when nothing of the latest could be read' {
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'SMS_G_System'
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'specs-refused.log'
        $read = Get-SccmSpec $script:Site 'DOUBLE-02' 'demo.local'
        [int64]$read.Device.ResourceID | Should -Be 16777227
        $read.Latest | Should -BeTrue
        $read.Inventory.System.Read | Should -BeFalse
        Get-Content $env:REPERE_FAKEAD_SCCM_LOG -Raw | Should -Match 'ResourceID = 16777227'
        Get-Content $env:REPERE_FAKEAD_SCCM_LOG -Raw | Should -Not -Match 'ResourceID = 16777226'
    }

    It 'Says none of several records has an inventory, or none of those read: <Tries> of 2' -ForEach @(
        @{ Tries = 3; Reason = "SCCM n'a d'inventaire d'aucune des 2 fiches de cet ordinateur" }
        @{ Tries = 1; Reason = "SCCM n'a d'inventaire d'aucune fiche lue de cet ordinateur (1 sur 2)" }
    ) {
        # DOUBLE-01's records only have a BIOS: as content alone, the processor, neither has one.
        $saved = $script:SccmContentSections, $script:SccmSpecTries
        $script:SccmContentSections, $script:SccmSpecTries = @('Processor'), $Tries
        try { $read = Get-SccmSpec $script:Site 'DOUBLE-01' 'demo.local' }
        finally { $script:SccmContentSections, $script:SccmSpecTries = $saved }
        $read.Answer | Should -BeExactly 'NoInventory'
        $read.Count | Should -Be 2
        $read.Reason | Should -BeExactly $Reason
        $read.Inventory | Should -BeNullOrEmpty
    }

    It 'Decides an inventory by the sections Caractéristiques shows, their rows or their failure' {
        # The classes ConvertFrom-SccmInventory's sections are made from: their failure is a section's error.
        $file = Join-Path $script:RepereSource 'PCSpecs.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $convert = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertFrom-SccmInventory' }, $true)
        $calls = @($convert.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq 'Ampersand' -and $node.CommandElements[0].Extent.Text -eq '$section' }, $false))
        $calls.Count | Should -BeGreaterThan 0
        $classes = @($calls | ForEach-Object { $_.CommandElements[2].SafeGetValue() } | ForEach-Object { $_ })
        @($classes | Sort-Object) | Should -Be @($script:SccmContentSections | Sort-Object)
        @($script:SccmContentSections | Where-Object { $_ -notin $script:SccmSections.Keys }) | Should -BeNullOrEmpty
    }

    It 'Says why when SCCM doesn''t answer, and reads nothing' {
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
        $read = Get-SccmSpec $script:Site 'ORD-06' 'demo.local'
        $read.Answer | Should -BeExactly 'NotChecked'
        $read.Reason | Should -BeExactly 'sccm.demo.local ne répond pas'
        $read.Inventory | Should -BeNullOrEmpty
    }

    It 'Is a read the search runspaces can run, with every function of Sccm.ps1 and PCSpecs.ps1 it calls' {
        $listed = @(Get-SccmReadFunction)
        $listed | Should -Contain 'Get-SccmSpec'
        # The top-level functions only: Read-SccmRow is the link runspace's own ($SccmLinkScript).
        $defined = @{}
        foreach ($name in 'Sccm.ps1', 'PCSpecs.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepereSource $name), [ref]$null, [ref]$null)
            foreach ($function in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $defined[$function.Name] = $function }
        }
        # Every listed function's callees, transitively: a read can start from any of them. Those of other files
        # (Get-ErrorKind) aren't looked into.
        $defined.ContainsKey('Get-SccmSpec') | Should -BeTrue
        $missing = foreach ($name in $listed | Where-Object { $defined.ContainsKey($_) }) {
            foreach ($call in $defined[$name].Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $called = $call.GetCommandName()
                if ($called -and $defined.ContainsKey($called) -and $called -notin $listed) { "$name calls $called" }
            }
        }
        @($missing) | Should -BeNullOrEmpty
    }

    It 'Is given every script variable the functions it runs read' {
        $listed = @(Get-SccmReadFunction)
        # Get-SccmReadVariable's keys as written, without calling it: it needs the fake AD's path set.
        $given = @()
        # Given otherwise: FrenchErrors by Start-BackgroundRead itself.
        $elsewhere = 'FrenchErrors'
        $used = @{}
        foreach ($name in 'Sccm.ps1', 'PCSpecs.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepereSource $name), [ref]$null, [ref]$null)
            $variables = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-SccmReadVariable' }, $false)
            if ($variables) { $given = @($variables.Body.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true).KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text }) }
            foreach ($function in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $listed }, $false)) {
                foreach ($variable in $function.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.IsScript }, $true)) {
                    $used[$variable.VariablePath.UserPath -replace '^script:'] = $function.Name
                }
            }
        }
        $used.Count | Should -BeGreaterThan 0
        $given | Should -Contain 'SccmLink'
        @($used.Keys | Where-Object { $_ -notin $given -and $_ -notin $elsewhere } | ForEach-Object { "$($used[$_]) reads `$script:$_" }) | Should -BeNullOrEmpty
    }
}

Describe 'How often the site inventories computers (Paramètres › SCCM)' {
    It 'Takes <Days> as <Problem>' -ForEach @(
        @{ Days = ''; Problem = '' }
        @{ Days = '1'; Problem = '' }
        @{ Days = ' 90 '; Problem = '' }
        @{ Days = '0'; Problem = 'Un nombre de jours, de 1 à 90.' }
        @{ Days = '91'; Problem = 'Un nombre de jours, de 1 à 90.' }
        @{ Days = 'sept'; Problem = 'Un nombre de jours, de 1 à 90.' }
    ) {
        "$(Get-SccmDaysProblem $Days)" | Should -BeExactly $Problem
    }

    It 'Is read with the site, 7 days unless a valid number is saved' {
        $saved = $script:SettingsPath
        try {
            $script:SettingsPath = Join-Path $TestDrive 'parametres-days.json'
            '{ "SccmSite": "DEM", "SccmServer": "sccm.demo.local" }' | Set-Content $script:SettingsPath
            (Read-SccmSetting).InventoryDays | Should -Be 7
            '{ "SccmSite": "DEM", "SccmServer": "sccm.demo.local", "SccmInventoryDays": 14 }' | Set-Content $script:SettingsPath
            (Read-SccmSetting).InventoryDays | Should -Be 14
            '{ "SccmSite": "DEM", "SccmServer": "sccm.demo.local", "SccmInventoryDays": 400 }' | Set-Content $script:SettingsPath
            (Read-SccmSetting).InventoryDays | Should -Be 7
            # Edited by hand: what passes as a number is read as one, not an error.
            '{ "SccmSite": "DEM", "SccmServer": "sccm.demo.local", "SccmInventoryDays": [14] }' | Set-Content $script:SettingsPath
            (Read-SccmSetting).InventoryDays | Should -Be 14
            '{ "SccmSite": "DEM", "SccmServer": "sccm.demo.local", "SccmInventoryDays": " 21 " }' | Set-Content $script:SettingsPath
            (Read-SccmSetting).InventoryDays | Should -Be 21
            '{ "SccmSite": "DEM", "SccmServer": "sccm.demo.local", "SccmInventoryDays": [14, 21] }' | Set-Content $script:SettingsPath
            (Read-SccmSetting).InventoryDays | Should -Be 7
        }
        finally { $script:SettingsPath = $saved }
    }
}

Describe 'The runspace the reads share' {
    BeforeEach { Reset-Sccm }

    It 'Is kept from one read to the next, and opened again for another site' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $null = Get-Find 'ORD-13'
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeTrue
        $other = Find-SccmDevice @{ Site = 'ZZZ'; Server = 'sccm.demo.local' } -Name 'ORD-01'
        $other.Reason | Should -BeExactly 'le site ZZZ est introuvable sur sccm.demo.local'
        (Get-Find 'ORD-01').Checked | Should -BeTrue
    }

    It 'A query that''s refused keeps it, a server that stops answering doesn''t' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'R_System'
        (Get-Find 'ORD-01').Checked | Should -BeFalse
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeTrue
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
        (Get-Find 'ORD-01').Checked | Should -BeFalse
        $script:SccmLink.Runspace | Should -BeNullOrEmpty
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = $env:REPERE_FAKEAD_SCCM_REFUSED = $null
        (Get-Find 'ORD-01').Checked | Should -BeTrue
    }

    It 'A first read may take longer than the next ones' {
        $script:SccmTimeoutSeconds, $script:SccmQuerySeconds = 10, 1
        $env:REPERE_FAKEAD_SCCM_DELAY = '2'
        (Get-Find 'ORD-01').Checked | Should -BeTrue
        (Get-Find 'ORD-01').Reason | Should -BeExactly 'SCCM n''a pas répondu en 1 secondes'
    }

    It 'After a failure, only a read nobody clicked for leaves SCCM alone' {
        $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'rest.txt'
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
        (Get-Find 'ORD-01').Checked | Should -BeFalse
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = $null
        $find = Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic
        $find.Checked | Should -BeFalse
        $find.Reason | Should -BeExactly 'sccm.demo.local ne répond pas'
        Test-Path $env:REPERE_FAKEAD_SCCM_LOG | Should -BeFalse
        (Get-Find 'ORD-01').Checked | Should -BeTrue
        (Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic).Checked | Should -BeTrue
    }

    It 'One read at a time: the next one waits its turn, and says so when it doesn''t come' {
        $script:SccmTimeoutSeconds = 1
        $script:SccmLink.Gate.Wait(0) | Should -BeTrue
        try { $find = Get-Find 'ORD-01' }
        finally { $null = $script:SccmLink.Gate.Release() }
        $find.Checked | Should -BeFalse
        $find.Reason | Should -BeExactly 'une autre lecture de SCCM n''est pas terminée'
        $script:SccmTimeoutSeconds = 60
        (Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic).Checked | Should -BeTrue
    }

    It 'A link that died is opened again by the next read: <Failure>' -ForEach @(
        @{ Failure = '0x800706BE' }, @{ Failure = '0x80010108' }, @{ Failure = 'This command cannot be run from the current drive.' }, @{ Failure = 'The RPC server is unavailable.' }
    ) {
        $null = Get-Find 'ORD-01'
        $env:REPERE_FAKEAD_SCCM_DEAD = $Failure
        (Get-Find 'ORD-01').Checked | Should -BeFalse
        $script:SccmLink.Runspace | Should -BeNullOrEmpty
        (Get-Find 'ORD-01').Checked | Should -BeTrue
    }

    It 'Too many queries refused in a row open it again too, without resting' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $env:REPERE_FAKEAD_SCCM_REFUSED = 'R_System'
        foreach ($try in 1, 2) { (Get-Find 'ORD-01').Checked | Should -BeFalse }
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeTrue
        $null = Get-Find 'ORD-01'
        $script:SccmLink.Runspace | Should -BeNullOrEmpty
        $env:REPERE_FAKEAD_SCCM_REFUSED = $null
        (Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic).Checked | Should -BeTrue
    }

    It 'A runspace that breaks during a query is said, never thrown' {
        $null = Get-Find 'ORD-01'
        $env:REPERE_FAKEAD_SCCM_BREAK = '1'
        { $script:Broken = Get-Find 'ORD-01' } | Should -Not -Throw
        $script:Broken.Checked | Should -BeFalse
        $script:Broken.Reason | Should -Not -BeNullOrEmpty
        $env:REPERE_FAKEAD_SCCM_BREAK = $null
        (Get-Find 'ORD-01').Checked | Should -BeTrue
    }

    It 'Is made again after a while, and for Tester, so that the console''s version is checked again' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $script:SccmLink.OpenedAt = [datetime]::UtcNow.AddMinutes(-61)
        $null = Get-Find 'ORD-01'
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeFalse
        $second = $script:SccmLink.Runspace
        $null = Get-SccmTest $script:Site
        [object]::ReferenceEquals($script:SccmLink.Runspace, $second) | Should -BeFalse
        $env:REPERE_FAKEAD_SCCM_ERROR = 'A new version of the console is available (5.2603.1035.1900). Cmdlets may not function as expected.'
        (Get-SccmTest $script:Site).Reason | Should -BeExactly 'la console Configuration Manager doit être mise à jour (version 5.2603.1035.1900)'
    }

    It 'What doesn''t stop or close in time is left to the end of the process, and the timer stops' {
        $shell = [powershell]::Create()
        $stop = [pscustomobject]@{ IsCompleted = $false }
        Clear-Sccm
        $script:SccmStopping.Enqueue(@{ Shell = $shell; Stop = $stop; Runspace = $null; Since = [datetime]::UtcNow.AddMinutes(-11) })
        $script:SccmStopping.Enqueue(@{ Shell = $shell; Stop = $stop; Runspace = $null; Since = [datetime]::UtcNow })
        try {
            Clear-SccmStopping
            $script:SccmStopping.Count | Should -Be 1
        }
        finally {
            $entry = $null
            while ($script:SccmStopping.TryDequeue([ref]$entry)) { }
            $shell.Dispose()
        }
    }

    It 'A runspace that can''t be opened is said, never thrown, and the next read makes another' {
        $make = (Get-Item function:New-SccmRunspace).Definition
        Set-Item function:New-SccmRunspace { $runspace = [runspacefactory]::CreateRunspace(); $runspace.Dispose(); $runspace }
        try { { $script:Unopened = Get-Find 'ORD-01' } | Should -Not -Throw }
        finally { Set-Item function:New-SccmRunspace ([scriptblock]::Create($make)) }
        $script:Unopened.Checked | Should -BeFalse
        $script:Unopened.Reason | Should -Not -BeNullOrEmpty
        $script:SccmLink.Runspace | Should -BeNullOrEmpty
        $script:SccmLink.Gate.CurrentCount | Should -Be 1
        (Get-Find 'ORD-01').Checked | Should -BeTrue
        Clear-Sccm
    }

    It 'A runspace still busy with something else isn''t used' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $other = [powershell]::Create()
        $other.Runspace = $first
        $null = $other.AddScript('Start-Sleep -Seconds 3')
        $running = $other.BeginInvoke()
        try {
            (Get-Find 'ORD-01').Checked | Should -BeTrue
            [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeFalse
        }
        finally {
            $null = $running.AsyncWaitHandle.WaitOne(5000)
            $other.Dispose()
            Clear-Sccm
        }
    }

    It 'A site that couldn''t be opened leaves nothing that looks open' {
        $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
        $null = Get-Find 'ORD-01'
        $script:SccmLink.Ready | Should -BeFalse
        $script:SccmLink.Runspace | Should -BeNullOrEmpty
    }

    It 'Out of time on a query that can''t be stopped, rests, and the next read has a runspace of its own' {
        $null = Get-Find 'ORD-01'
        $first = $script:SccmLink.Runspace
        $script:SccmQuerySeconds = 1
        $env:REPERE_FAKEAD_SCCM_STUCK = '4'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        (Get-Find 'ORD-01').Reason | Should -BeExactly 'SCCM n''a pas répondu en 1 secondes'
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 3
        $env:REPERE_FAKEAD_SCCM_STUCK = $null
        (Find-SccmDevice $script:Site -Name 'ORD-01' -Automatic).Checked | Should -BeFalse
        (Get-Find 'ORD-01').Checked | Should -BeTrue
        [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeFalse
        # And it's closed once the query has ended, not before.
        "$($first.RunspaceStateInfo.State)" | Should -BeExactly 'Opened'
        Clear-Sccm
        $script:SccmStopping.Count | Should -Be 0
        "$($first.RunspaceStateInfo.State)" | Should -BeExactly 'Closed'
    }

    It 'Automatic reads waiting behind one that fails don''t each try the site' {
        Open-SearchPool
        try {
            $env:REPERE_FAKEAD_SCCM_LOG = Join-Path $TestDrive 'queue.txt'
            $null = Get-Find 'ORD-01'
            $env:REPERE_FAKEAD_SCCM_DELAY = '1'
            $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
            function Find-Automatic($Sccm) { Find-SccmDevice $Sccm -Name 'ORD-01' -Automatic }
            $reads = @(foreach ($i in 1..3) { Start-PoolRead 'Find-Automatic' @(, $script:Site) })
            Wait-PoolRead $reads
            foreach ($read in $reads) { $read.Result.Reason | Should -BeExactly 'sccm.demo.local ne répond pas' }
            @(Get-Content $env:REPERE_FAKEAD_SCCM_LOG).Count | Should -Be 2
        }
        finally { Close-SearchPool }
    }

    It 'Reads at the same time take turns, and all get their own answer' {
        Open-SearchPool
        try {
            $names = 'ORD-01', 'ORD-13', 'ORD-14', 'RENTRE-01'
            $reads = @(foreach ($name in $names) { Start-PoolRead 'Find-SccmDevice' @($script:Site, $name) })
            Wait-PoolRead $reads
            for ($i = 0; $i -lt 4; $i++) {
                $reads[$i].Problem | Should -BeNullOrEmpty
                @($reads[$i].Result.Devices.Name | Select-Object -Unique) | Should -Be $names[$i]
            }
        }
        finally { Close-SearchPool }
    }

    It 'A read that''s stopped gives back its turn, and the runspace it had, when its query stops' {
        Open-SearchPool
        try {
            $null = Get-Find 'ORD-01'
            $first = $script:SccmLink.Runspace
            $env:REPERE_FAKEAD_SCCM_DELAY = '30'
            $state = @{ Id = 1 }
            $read = Start-PoolRead 'Find-SccmDevice' @($script:Site, 'ORD-13') $state
            Wait-SccmBusy
            Start-Sleep -Milliseconds 300
            Stop-BackgroundRead $state
            Wait-PoolRead $read
            $script:SccmLink.Gate.CurrentCount | Should -Be 1
            [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeTrue
            $env:REPERE_FAKEAD_SCCM_DELAY = $null
            (Get-Find 'ORD-01').Checked | Should -BeTrue
        }
        finally { Close-SearchPool }
    }

    It 'A read that''s stopped on a query that doesn''t gives back its turn, not the runspace' {
        Open-SearchPool
        try {
            $null = Get-Find 'ORD-01'
            $first = $script:SccmLink.Runspace
            $env:REPERE_FAKEAD_SCCM_STUCK = '5'
            $state = @{ Id = 1 }
            $read = Start-PoolRead 'Find-SccmDevice' @($script:Site, 'ORD-13') $state
            Wait-SccmBusy
            Start-Sleep -Milliseconds 300
            Stop-BackgroundRead $state
            Wait-PoolRead $read
            $script:SccmLink.Gate.CurrentCount | Should -Be 1
            $env:REPERE_FAKEAD_SCCM_STUCK = $null
            (Get-Find 'ORD-01').Checked | Should -BeTrue
            [object]::ReferenceEquals($script:SccmLink.Runspace, $first) | Should -BeFalse
            Clear-Sccm
            "$($first.RunspaceStateInfo.State)" | Should -BeExactly 'Closed'
        }
        finally { Close-SearchPool }
    }

    It 'A stop that comes while the runspace is let go of doesn''t keep the turn' {
        # The same end, slowed down: Close-SccmRunspace taking 2 s, the read stopped meanwhile.
        $close = (Get-Item function:Close-SccmRunspace).Definition
        Open-SearchPool
        try {
            Clear-Sccm
            $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
            Set-Item function:Close-SccmRunspace ([scriptblock]::Create("$close`nif (`$runspace) { Start-Sleep -Seconds 2 }"))
            $state = @{ Id = 1 }
            $read = Start-PoolRead 'Find-SccmDevice' @($script:Site, 'ORD-13') $state
            for ($i = 0; $i -lt 100 -and -not $script:SccmStopping.Count; $i++) { Start-Sleep -Milliseconds 50 }
            $script:SccmLink.Gate.CurrentCount | Should -Be 0
            Stop-BackgroundRead $state
            Wait-PoolRead $read
            $script:SccmLink.Gate.CurrentCount | Should -Be 1
        }
        finally {
            Set-Item function:Close-SccmRunspace ([scriptblock]::Create($close))
            Close-SearchPool
        }
    }

    It 'Closing goes on a moment after a read is given up on' {
        $script:SccmStopTimer.Stop()
        Start-SccmStopSweep
        try {
            Clear-SccmStopping
            $script:SccmStopTimer.IsEnabled | Should -BeTrue
            foreach ($tick in 1..10) { Clear-SccmStopping }
            $script:SccmStopTimer.IsEnabled | Should -BeFalse
        }
        finally { $script:SccmStopTimer.Stop() }
    }

    It 'Ends before its background read is given up on, with its own reason' {
        Get-SccmReadTimeout | Should -BeGreaterThan ($script:ReadTimeout + $script:SccmTotalSeconds)
    }

    It 'Answers on a search runspace, with only what it''s given, in words too' {
        Open-SearchPool
        try {
            $read = Start-PoolRead 'Get-SccmTest' @(, $script:Site)
            Wait-PoolRead $read
            $read.Problem | Should -BeNullOrEmpty
            $read.Result.Checked | Should -BeTrue
            $read.Result.Inventory | Should -BeExactly 'Readable'
            $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
            $read = Start-PoolRead 'Get-SccmTest' @(, $script:Site)
            Wait-PoolRead $read
            $read.Result.Reason | Should -BeExactly 'sccm.demo.local ne répond pas'
        }
        finally { Close-SearchPool }
    }
}

Describe 'Paramètres › SCCM › Tester' {
    BeforeEach { Reset-Sccm }

    It 'Says <Expected>' -ForEach @(
        @{ Variable = 'NONE'; Value = ''; Expected = 'Le site DEM répond. L''inventaire de cet ordinateur est lisible.' }
        @{ Variable = 'MOUNTED'; Value = 'autre.demo.local'; Expected = 'Le site DEM répond, mais par autre.demo.local : la console s''y connecte d''elle-même. L''inventaire de cet ordinateur est lisible.' }
        @{ Variable = 'MOUNTED'; Value = 'SCCM'; Expected = 'Le site DEM répond. L''inventaire de cet ordinateur est lisible.' }
        @{ Variable = 'LIMITED'; Value = 'ORD-01'; Expected = 'Le site DEM répond. Inventaire non vérifié : cet ordinateur est introuvable dans SCCM (avec vos accès).' }
        @{ Variable = 'REFUSED'; Value = 'COMPUTER_SYSTEM'; Expected = 'Le site DEM répond. L''inventaire de cet ordinateur n''est pas lisible : Accès refusé.' }
        @{ Variable = 'UNREACHABLE'; Value = '1'; Expected = 'Vérification SCCM impossible : sccm.demo.local ne répond pas.' }
    ) {
        [Environment]::SetEnvironmentVariable("REPERE_FAKEAD_SCCM_$Variable", $Value)
        try { Format-SccmTest (Get-SccmTest $script:Site) $script:Site | Should -BeExactly $Expected }
        finally { [Environment]::SetEnvironmentVariable("REPERE_FAKEAD_SCCM_$Variable", $null) }
    }

    It 'Says a computer SCCM has without inventory has none' {
        Format-SccmTest (Get-SccmTest $script:Site 'ORD-14' 'demo.local') $script:Site | Should -BeExactly 'Le site DEM répond. Cet ordinateur y est, sans inventaire (avec vos accès).'
    }

    It 'Reads nothing of a computer SCCM only has an obsolete record of' {
        Format-SccmTest (Get-SccmTest $script:Site 'VIEUX-01' 'demo.local') $script:Site | Should -BeExactly 'Le site DEM répond. Inventaire non vérifié : SCCM n''a de cet ordinateur qu''une fiche obsolète.'
    }

    It 'Takes this computer''s AD domain, or nothing out of one' {
        $domain = Get-SccmDomain
        $system = Get-CimInstance Win32_ComputerSystem
        $domain | Should -BeExactly $(if ($system.PartOfDomain) { $system.Domain } else { '' })
    }

    It 'Reads nothing of a computer SCCM has several records of, nor of one in another domain' {
        Format-SccmTest (Get-SccmTest $script:Site 'DOUBLE-01' 'demo.local') $script:Site | Should -BeExactly 'Le site DEM répond. Inventaire non vérifié : SCCM a plusieurs fiches qui peuvent être cet ordinateur.'
        (Get-SccmTest $script:Site 'ORD-01' 'autre.local').Inventory | Should -BeExactly 'NoDevice'
    }

    It '<One> and <Two> are one server''s names: <Expected>' -ForEach @(
        @{ One = 'sccm.demo.local'; Two = 'SCCM.demo.local'; Expected = $true }
        @{ One = 'sccm'; Two = 'sccm.demo.local'; Expected = $true }
        @{ One = 'sccm.a.local'; Two = 'sccm.b.local'; Expected = $false }
        @{ One = 'sccm'; Two = 'sccm2'; Expected = $false }
    ) { Test-SccmServer $One $Two | Should -Be $Expected }
}
