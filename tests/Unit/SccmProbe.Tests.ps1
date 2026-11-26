# tools\Test-SccmInventory.ps1, run as its user would, in a pwsh of its own, on a fake Configuration Manager console made
# here: what it finds, and above all that none of the site's values comes out. Every value of the fake site holds
# « secret », so that one word is enough to look for.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Probe = Join-Path $script:RepereRoot 'tools\Test-SccmInventory.ps1'
    $script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) "repere-sccm-probe-$PID"
    $module = Join-Path $script:Folder 'modules\ConfigurationManager'
    $null = New-Item -ItemType Directory -Force -Path $module, (Join-Path $script:Folder 'appdata\Repere'), (Join-Path $script:Folder 'empty'), (Join-Path $script:Folder 'temp')
    Set-Content -LiteralPath (Join-Path $script:Folder 'appdata\Repere\parametres.json') -Value '{"SccmSite":"ZQ9","SccmServer":"cmsecret.secret.test"}'
    "@{ RootModule = 'ConfigurationManager.psm1'; ModuleVersion = '5.1'; FunctionsToExport = '*' }" | Set-Content (Join-Path $module 'ConfigurationManager.psd1')
    @'
# Rows as the console's objects are: their columns in PropertyNames, their values by an indexer, which throws for a
# value that's « refused ».
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
public class ProbeValue {
    private readonly object held;
    public ProbeValue(object value) { held = value; }
    public object ObjectValue { get { if ("refused".Equals(held)) throw new UnauthorizedAccessException("secret refusal"); return held; } }
}
public class ProbeRow {
    private readonly Dictionary<string, object> values = new Dictionary<string, object>();
    public string[] PropertyNames { get { var names = new string[values.Count]; values.Keys.CopyTo(names, 0); return names; } }
    public ProbeValue this[string name] { get { return new ProbeValue(values[name]); } }
    public void Put(string name, object value) { values[name] = value; }
}
"@
function ConvertTo-ProbeRow($Table) {
    if (-not $env:PROBE_CONSOLE_ROWS) { return [pscustomobject]$Table }
    $row = [ProbeRow]::new()
    foreach ($key in $Table.Keys) { $row.Put($key, $Table[$key]) }
    $row
}
$script:Mounted = @{}
if ($env:PROBE_AUTO_SERVER) { $script:Mounted['ZQ9'] = $env:PROBE_AUTO_SERVER }
$script:OnDrive = $false
function Get-PSDrive {
    [CmdletBinding()] param([string]$Name, [string]$PSProvider)
    foreach ($key in @($script:Mounted.Keys)) { if (-not $Name -or $Name -eq $key) { [pscustomobject]@{ Name = $key; Root = "\\$($script:Mounted[$key])" } } }
}
function Remove-PSDrive { [CmdletBinding()] param([string]$Name, [string]$PSProvider, [switch]$Force) $script:Mounted.Remove($Name) }
function New-PSDrive {
    [CmdletBinding()] param([string]$Name, [string]$PSProvider, [string]$Root, [string]$Scope)
    if ($env:PROBE_UNREACHABLE) { throw [System.Runtime.InteropServices.COMException]::new('cmsecret is unavailable, says secret', 0x800706BA) }
    $script:Mounted[$Name] = $Root
}
function Set-Location {
    [CmdletBinding()] param([Parameter(Position = 0)] [string]$Path)
    $script:OnDrive = $false
    if ($Path -ne 'ZQ9:\') { return }
    if (-not $script:Mounted.Count) { throw 'secret: no drive' }
    $script:OnDrive = $true
}
function Get-CMDevice {
    [CmdletBinding()] param([string]$Name, [switch]$Resource, [switch]$Fast)
    if ($Name -eq 'PC-SECRET1' -and -not $env:PROBE_HIDDEN) { [pscustomobject]@{ Name = $Name } }
}
function Invoke-CMWmiQuery {
    [CmdletBinding()] param([string]$Query, [string]$Option)
    Add-Content -LiteralPath $env:PROBE_LOG -Value $Query
    # The module's own code can write to the console.
    [Console]::WriteLine('secret, from the module itself')
    if (-not $script:OnDrive) { throw 'secret: not on the drive' }
    if ($Option -and $env:PROBE_NO_FAST) { throw 'secret: no Fast' }
    if ($Query -match 'REPERE_NONE|RepereNone') { throw [System.InvalidOperationException]::new('secret query failed on cmsecret.secret.test') }
    if ($env:PROBE_SLOW -and $Query -match 'PHYSICAL_MEMORY') { Start-Sleep -Seconds 30 }
    # A native call, which nothing stops.
    if ($env:PROBE_STUCK -and $Query -match $env:PROBE_STUCK) { [System.Threading.Thread]::Sleep(90000) }
    if ($env:PROBE_HIDDEN) { return }
    if ($env:PROBE_NO_RSYSTEM -and $Query -match 'SMS_R_System') { return }
    switch -Regex ($Query) {
        "FROM SMS_R_System WHERE Name = 'PC-SECRET1'" {
            # An older record, obsolete, before the one to read.
            foreach ($id in 16777111, 16777222) {
                ConvertTo-ProbeRow ([ordered]@{ ResourceID = [uint32]$id; Name = 'PC-SECRET1'; SID = 'S-1-5-21-111-222-333-4444'; FullDomainName = 'secret.test'; Obsolete = [int]($id -eq 16777111)
                        IPAddresses = [string[]]('10.secret', '10.secret2'); CreationDate = [datetime]'2026-01-02'; secretExtension = 'secret' })
            }
        }
        "FROM SMS_R_System WHERE SID = 'S-1-5-21-111-222-333-4444'" { ConvertTo-ProbeRow ([ordered]@{ ResourceID = 1 }) }
        'FROM SMS_CombinedDeviceResources WHERE Name' { if ($env:PROBE_NO_RSYSTEM) { ConvertTo-ProbeRow ([ordered]@{ ResourceID = [uint32]16777222 }) } }
        'G_System_PC_BIOS WHERE (ResourceID = 16777222|ResourceID IN)' { ConvertTo-ProbeRow ([ordered]@{ ResourceID = 1; SerialNumber = "SECRET'\1"; ReleaseDate = '20250102000000.000000+***'; Manufacturer = $(if ($env:PROBE_CONSOLE_ROWS) { 'refused' }) }) }
        "G_System_PC_BIOS WHERE SerialNumber = 'SECRET\\'\\\\1'" { ConvertTo-ProbeRow ([ordered]@{ ResourceID = 1 }) }
        'WORKSTATION_STATUS WHERE ResourceID = 16777222' { ConvertTo-ProbeRow ([ordered]@{ LastHardwareScan = [datetime]::Now.AddDays(-5) }) }
        'CH_Summary WHERE ResourceID = 16777222' { ConvertTo-ProbeRow ([ordered]@{ LastHW = [datetime]::Now.AddDays(-5).AddHours(3) }) }
        'G_System_LOGICAL_DISK ' { ConvertTo-ProbeRow ([ordered]@{ DeviceID = 'secret:'; Size = [uint64]243000; FreeSpace = $null }); ConvertTo-ProbeRow ([ordered]@{ DeviceID = 'secret2:'; Size = [uint64]99; FreeSpace = [uint64]12 }) }
        'ADD_REMOVE_PROGRAMS_64' { 1..300 | ForEach-Object { ConvertTo-ProbeRow ([ordered]@{ DisplayName = "Secret $_"; InstallDate = '20260102' }) } }
    }
}
Export-ModuleMember -Function Get-PSDrive, Remove-PSDrive, New-PSDrive, Set-Location, Get-CMDevice, Invoke-CMWmiQuery
'@ | Set-Content (Join-Path $module 'ConfigurationManager.psm1')

    function Invoke-ProbeRun([hashtable]$Environment = @{}, [string[]]$Arguments = @('-ComputerName', 'PC-SECRET1')) {
        # The probe's output, as one text, with every stream in it, its file (File), and what it asked the site (Queries).
        $log = Join-Path $script:Folder 'queries.txt'
        Set-Content -LiteralPath $log -Value $null
        $temp = Join-Path $script:Folder 'temp'
        $all = @{ APPDATA = Join-Path $script:Folder 'appdata'; PSModulePath = Join-Path $script:Folder 'modules'; SMS_ADMIN_UI_PATH = $null; PROBE_LOG = $log; TEMP = $temp; TMP = $temp }
        foreach ($name in $Environment.Keys) { $all[$name] = $Environment[$name] }
        $saved = @{}
        foreach ($name in $all.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $all[$name]) }
        try { $text = (& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $script:Probe @Arguments *>&1 | Out-String) }
        finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) } }
        $file = Join-Path $temp 'SccmProbe.txt'
        # Without its colours.
        [pscustomobject]@{
            Text = $text -replace '\x1b\[[0-9;]*m'; Queries = @(Get-Content -LiteralPath $log | Where-Object { $_ })
            File = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw }
        }
    }
    # What a pasted output must not hold: the fake site's values, its site code and its ids.
    $script:Leak = '(?i)secret|ZQ9|16777\d|243000|1-5-21-'
}

AfterAll { Remove-Item -LiteralPath $script:Folder -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'The SCCM probe' {
    Context 'On a site that answers, <Case>' -ForEach @(
        @{ Case = 'its rows as plain objects'; Rows = $null; Plain = 'True' }
        @{ Case = 'its rows as the console''s objects'; Rows = '1'; Plain = 'False' }
    ) {
        BeforeAll { $script:Run = Invoke-ProbeRun @{ PROBE_CONSOLE_ROWS = $Rows } }

        It 'Prints none of its values, on screen or in the file' {
            $script:Run.Text | Should -Not -Match $script:Leak
            $script:Run.File | Should -Match '== Summary'
            $script:Run.File | Should -Not -Match $script:Leak
        }

        It 'Runs every section without an error of its own' {
            $script:Run.Text | Should -Not -Match 'PROBE ERROR'
            foreach ($title in 'Console', 'Finding the computer', 'With and without', 'Inventory', 'Dates', 'The other reads', 'How a wrong query', 'The drive', 'Summary') {
                $script:Run.Text | Should -Match "== $title"
            }
        }

        It 'Finds the computer and reads its current record' {
            $script:Run.Text | Should -Match 'SMS_R_System by name, first time .* 2 record\(s\)'
            $script:Run.Text | Should -Match "not obsolete: 1; \`$row\.Column works: $Plain; FullDomainName: a DNS name; ResourceID: read"
            $script:Run.Text | Should -Match 'SMS_R_System by SID .* 1 record\(s\)'
            $script:Run.Text | Should -Match 'A name that doesn''t exist .* 0 row\(s\)'
            $script:Run.Text | Should -Match 'Below: with -Option Fast'
        }

        It 'Says each column''s type, and how many rows have it' {
            $script:Run.Text | Should -Match 'SID +String, SID +2/2'
            $script:Run.Text | Should -Match 'IPAddresses +String\[\] +2/2'
            $script:Run.Text | Should -Match 'ReleaseDate +String, WMI date, no offset +1/1'
            $script:Run.Text | Should -Match 'Size +UInt64, 6 digit\(s\) +2/2'
            $script:Run.Text | Should -Match 'FreeSpace +UInt64, 2 digit\(s\) +1/2'
            $script:Run.Text | Should -Match 'InstallDate +String, 8 digits +300/300'
            $script:Run.Text | Should -Match 'CreationDate +DateTime Unspecified +2/2'
            $script:Run.Text | Should -Match 'NOT THERE: .*TimeStamp'
        }

        It 'Tells a column it can''t read from an empty one' {
            $script:Run.Text | Should -Match $(if ($Rows) { 'Manufacturer +UNREADABLE \(UnauthorizedAccessException\) +0/1' } else { 'Manufacturer +empty +0/1' })
        }

        It 'Only counts the other columns, of a device and of the inventory' {
            $script:Run.Text | Should -Match 'others: 1\b'
            $script:Run.Text | Should -Not -Match 'others: [A-Za-z]'
        }

        It 'Sums up each use, a class without rows as empty' {
            $script:Run.Text | Should -Match 'Software +ADD_REMOVE_PROGRAMS empty; ADD_REMOVE_PROGRAMS_64 300 row\(s\); INSTALLED_SOFTWARE empty'
        }

        It 'Compares the dates by the hours between them' {
            $script:Run.Text | Should -Match 'Last hardware scan .* 5 day\(s\) ago'
            $script:Run.Text | Should -Match 'to CH_Summary.LastHW: 3[.,]0 h'
        }

        It 'Searches by serial number, escaped' { $script:Run.Text | Should -Match 'PC_BIOS by serial number .* 1 computer\(s\)' }

        It 'Says what a wrong query''s error is, by its type and code' { $script:Run.Text | Should -Match 'A class that doesn''t exist .* ERROR .*InvalidOperationException 0x80131509' }

        It 'Only reads, never a whole class' {
            $script:Run.Queries.Count | Should -BeGreaterThan 30
            $script:Run.Queries | Where-Object { $_ -notmatch '^SELECT .* WHERE ' } | Should -BeNullOrEmpty
        }
    }

    It 'On a drive the module mounted on another server, says so, and tries the one of Settings last' {
        $run = Invoke-ProbeRun @{ PROBE_AUTO_SERVER = 'othersecret.secret.test' }
        $run.Text | Should -Match 'this site''s: True; on the server of Settings: NO, another server'
        $run.Text | Should -Match '(?s)== Inventory.*Its drive taken off .* yes.*Mounted on the server of Settings .* yes'
        $run.Text | Should -Match 'A query through it .* 2 record\(s\)'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'When the server of Settings doesn''t answer, still reads through the module''s drive' {
        $run = Invoke-ProbeRun @{ PROBE_AUTO_SERVER = 'othersecret.secret.test'; PROBE_UNREACHABLE = '1' }
        $run.Text | Should -Match 'ADD_REMOVE_PROGRAMS_64 300 row\(s\)'
        $run.Text | Should -Match 'Mounted on the server of Settings .* ERROR .*COMException 0x800706BA'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'On a computer the account can''t see, says so and skips its inventory' {
        $run = Invoke-ProbeRun @{ PROBE_HIDDEN = '1' }
        $run.Text | Should -Match 'SMS_R_System by name, first time .* 0 record\(s\)'
        $run.Text | Should -Match 'SMS_CombinedDeviceResources by name .* 0 record\(s\)'
        $run.Text | Should -Match 'this is what limited access'
        $run.Text | Should -Not -Match '== Inventory'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'A read that fails isn''t taken for limited access' {
        $run = Invoke-ProbeRun @{ PROBE_STUCK = 'FROM SMS_R_System WHERE Name' } -Arguments '-ComputerName', 'PC-SECRET1', '-Limit', '2', '-StopLimit', '1'
        $run.Text | Should -Not -Match 'limited access'
        $run.Text | Should -Match 'isn''t known'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'Reads the inventory of a computer only another class gives' {
        $run = Invoke-ProbeRun @{ PROBE_NO_RSYSTEM = '1' }
        $run.Text | Should -Match 'which SMS_R_System didn''t give'
        $run.Text | Should -Match 'ADD_REMOVE_PROGRAMS_64 300 row\(s\)'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'On a server that doesn''t answer, gives the error''s code and stops' {
        $run = Invoke-ProbeRun @{ PROBE_UNREACHABLE = '1' }
        $run.Text | Should -Match 'At the site''s drive.* ERROR .*COMException 0x800706BA'
        $run.Text | Should -Match 'Stopped: the site''s drive can''t be used'
        $run.Text | Should -Not -Match $script:Leak
    }

    It '-Detail adds the errors'' messages, marked as not to paste, and not in the file' {
        $run = Invoke-ProbeRun @{ PROBE_UNREACHABLE = '1' } -Arguments '-ComputerName', 'PC-SECRET1', '-Detail'
        $run.Text | Should -Match '\(don''t paste\) cmsecret is unavailable'
        $run.File | Should -Not -Match $script:Leak
    }

    It 'Goes without -Option Fast when it fails' {
        $run = Invoke-ProbeRun @{ PROBE_NO_FAST = '1' }
        $run.Text | Should -Match 'Below: without -Option Fast'
        $run.Text | Should -Match 'ADD_REMOVE_PROGRAMS_64 300 row\(s\)'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'Past the limit, stops the query and goes on' {
        $run = Invoke-ProbeRun @{ PROBE_SLOW = '1' } -Arguments '-ComputerName', 'PC-SECRET1', '-Limit', '3'
        $run.Text | Should -Match 'G_PHYSICAL_MEMORY .* NO ANSWER in 3 s; stopped in \d+ ms'
        $run.Text | Should -Match 'ADD_REMOVE_PROGRAMS_64 300 row\(s\)'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'A query that can''t be stopped costs only itself: a new runspace goes on' {
        $run = Invoke-ProbeRun @{ PROBE_STUCK = 'SYSTEM_ENCLOSURE' } -Arguments '-ComputerName', 'PC-SECRET1', '-Limit', '3', '-StopLimit', '1'
        $run.Text | Should -Match 'G_SYSTEM_ENCLOSURE .* NO ANSWER in 3 s; did not stop in 1 s'
        $run.Text | Should -Match 'a new runspace, to go on\) .* yes'
        $run.Text | Should -Match 'ADD_REMOVE_PROGRAMS_64 300 row\(s\)'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'Names the inventory''s other columns with -ColumnNames, and still none of the values' {
        $run = Invoke-ProbeRun -Arguments '-ComputerName', 'PC-SECRET1', '-ColumnNames'
        $run.Text | Should -Match 'others: ResourceID'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'Without the console, says so and stops' {
        if (Get-Module -ListAvailable ConfigurationManager) { Set-ItResult -Skipped -Because 'this computer has the console' }
        $run = Invoke-ProbeRun @{ PSModulePath = Join-Path $script:Folder 'empty' }
        $run.Text | Should -Match 'from none'
        $run.Text | Should -Match 'Stopped: no console module'
    }

    It 'Takes a name with its domain, and keeps it out' {
        $run = Invoke-ProbeRun -Arguments '-ComputerName', 'PC-SECRET1.secret.test'
        $run.Text | Should -Match 'SMS_R_System by name, first time .* 2 record'
        $run.Text | Should -Not -Match $script:Leak
    }

    It 'Without a site, asks for one, and shows no path' {
        $run = Invoke-ProbeRun @{ APPDATA = Join-Path $script:Folder 'empty' }
        $run.Text | Should -Match 'No valid SCCM site'
        $run.Text | Should -Not -Match ':\\'
    }

    It 'Refuses <Given>, without repeating it' -ForEach @(
        @{ Given = 'no computer'; Arguments = @('-Detail') }
        @{ Given = 'a name that could change a query'; Arguments = '-ComputerName', "secret' OR Name LIKE '%" }
        @{ Given = 'a server that isn''t one'; Arguments = '-ComputerName', 'PC-SECRET1', '-Site', 'ZQ9', '-Server', 'https://secret' }
    ) {
        $run = Invoke-ProbeRun -Arguments $Arguments
        $run.Text | Should -Match 'give -'
        $run.Text | Should -Not -Match $script:Leak
        $run.Queries | Should -BeNullOrEmpty
    }
}
