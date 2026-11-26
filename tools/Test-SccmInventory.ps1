# Asks an SCCM site what Repère could read from it, before Repère reads anything: which server answers, which classes
# and columns this site has, how long a query takes, and what an error, a refusal or a missing device looks like.
# Read-only: it only queries. Not part of Repère: one file, to copy to a computer that has the Configuration Manager
# console.
#
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Test-SccmInventory.ps1 -ComputerName <a computer SCCM has inventoried>
#
# The site and the server are those of Repère's Settings > SCCM, unless -Site and -Server say otherwise. Run it again
# on a computer your account can't see in SCCM, if there's one: that shows what limited access looks like.
#
# What it prints is meant to be pasted elsewhere: column names, types, counts and durations. No value: no computer,
# user, serial number, server or site code. An error is its types and codes, never its message. A site can add columns
# of its own to the inventory: they're only counted, unless -ColumnNames prints their names too (without the names the
# probe was given and this computer's and account's). Read the output once before you paste it. It's also in
# %TEMP%\SccmProbe.txt, line by line, should the window close. -Detail adds the errors' own messages on screen, which
# name servers: for you, not to paste.
#Requires -Version 7.2
[CmdletBinding()]
param(
    # Checked below, with a message that doesn't repeat what was typed, as a parameter's own check does.
    [string]$ComputerName,
    [string]$Site,
    [string]$Server,
    # How long a query may take, in seconds. Loading the console's module has twice that.
    [int]$Limit = 60,
    # How long one past it may take to stop, in seconds.
    [int]$StopLimit = 10,
    # The names of the columns a site added to the inventory, not only how many.
    [switch]$ColumnNames,
    [switch]$Detail
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- What is printed -------------------------------------------------------------------------------------------------

$script:OutFile = Join-Path ([System.IO.Path]::GetTempPath()) 'SccmProbe.txt'
try { [System.IO.File]::WriteAllText($script:OutFile, '') } catch { $script:OutFile = $null }

function Write-Line([string]$Text = '') {
    # One line of the output, as pipeline output so it can be redirected, and in the file.
    Write-Output $Text
    if ($script:OutFile) { try { [System.IO.File]::AppendAllText($script:OutFile, "$Text`r`n") } catch { $script:OutFile = $null } }
}

$script:Hidden = [ordered]@{}
function Add-Hidden([string]$Text, [string]$Label) {
    # A name never to print. Under 3 characters, it would replace parts of ordinary words.
    if ($Text.Trim().Length -ge 3 -and -not $script:Hidden.Contains($Text)) { $script:Hidden[$Text] = "<$Label>" }
}

function Hide-Name([string]$Text) {
    # For what comes from the site or from an error; the probe's own words are left alone. The longest names first: a
    # server's full name before its short one.
    foreach ($name in @($script:Hidden.Keys | Sort-Object Length -Descending)) {
        $Text = [regex]::Replace($Text, "(?<!\w)$([regex]::Escape($name))(?!\w)", $script:Hidden[$name], 'IgnoreCase, CultureInvariant')
    }
    $Text
}

function Get-FailureException($Failure) {
    if ($Failure -is [System.Management.Automation.ErrorRecord]) { $Failure.Exception } else { $Failure }
}

function Get-InnerFailure($Failure) {
    # What's inside an exception: an error that stopped a command is in the exception that stopped it.
    if ($Failure.InnerException) { $Failure.InnerException }
    elseif ($Failure -is [System.Management.Automation.ActionPreferenceStopException] -and $Failure.ErrorRecord) { $Failure.ErrorRecord.Exception }
}

function Get-FailureId($Failure) {
    # An error's id, when it's an identifier and a command's name: the id of an error thrown as a text is that text.
    $record = if ($Failure -is [System.Management.Automation.ErrorRecord]) { $Failure }
              elseif ($Failure -is [System.Management.Automation.IContainsErrorRecord]) { $Failure.ErrorRecord }
    if ($record -and $record.FullyQualifiedErrorId -match '^\w+,[\w.]+$') { $record.FullyQualifiedErrorId }
}

function Format-Failure($Failure) {
    # An error as its types and codes, from the outside in, then its ids.
    $parts = [System.Collections.Generic.List[string]]::new()
    $ids = [System.Collections.Generic.List[string]]::new()
    $id = Get-FailureId $Failure
    if ($id) { $ids.Add($id) }
    $item = Get-FailureException $Failure
    for ($depth = 0; $item -and $depth -lt 6; $depth++) {
        $text = '{0} 0x{1:X8}' -f $item.GetType().Name, $item.HResult
        foreach ($name in 'ErrorCode', 'NativeErrorCode', 'ExtendStatusErrorCode') {
            $property = $item.PSObject.Properties[$name]
            # A number, or an enum's name.
            if ($property -and $property.Value -is [ValueType]) { $text += " $name=$($property.Value)" }
        }
        $parts.Add($text)
        $id = Get-FailureId $item
        if ($id -and -not $ids.Contains($id)) { $ids.Add($id) }
        $item = Get-InnerFailure $item
    }
    "$($parts -join ' > ')$(if ($ids.Count) { " [$($ids -join '; ')]" })"
}

function Get-FailureMessage($Failure) {
    $item = Get-FailureException $Failure
    while ($inner = Get-InnerFailure $item) { $item = $inner }
    $item.Message
}

# --- The site, as Repère has it --------------------------------------------------------------------------------------

# A name with its domain is taken without it: SCCM's Name is the short one.
$ComputerName = ($ComputerName.Trim() -split '\.')[0]
if ($ComputerName -notmatch '^[A-Za-z0-9_-]{1,63}$') { Write-Output 'Give -ComputerName: the name of a computer SCCM has inventoried (letters, digits, - and _).'; exit 1 }
if ($Limit -lt 1 -or $Limit -gt 600 -or $StopLimit -lt 1 -or $StopLimit -gt 600) { Write-Output 'Give -Limit and -StopLimit from 1 to 600 seconds.'; exit 1 }
if (-not $Site -or -not $Server) {
    $path = Join-Path "$env:APPDATA" 'Repere\parametres.json'
    $saved = try { Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable } catch { $null }
    if ($saved -is [System.Collections.IDictionary]) {
        if (-not $Site) { $Site = "$($saved['SccmSite'])".Trim() }
        if (-not $Server) { $Server = "$($saved['SccmServer'])".Trim() }
    }
}
if ($Site -notmatch '^[A-Za-z0-9]{3}$' -or $Server -notmatch '^[A-Za-z0-9_.-]{1,255}$') {
    Write-Output 'No valid SCCM site in Settings > SCCM: give -Site (3 characters) and -Server (a server''s name).'
    exit 1
}
$Site = $Site.ToUpperInvariant()

Add-Hidden $ComputerName 'computer'
Add-Hidden $Server 'server'
Add-Hidden ($Server -split '\.')[0] 'server'
Add-Hidden $Site 'site'
Add-Hidden "$env:USERNAME" 'user'
Add-Hidden "$env:USERDOMAIN" 'domain'
Add-Hidden "$env:USERDNSDOMAIN" 'domain'
Add-Hidden "$env:COMPUTERNAME" 'this computer'

# --- One runspace, kept open: every step runs in it, as Repère's reads would -----------------------------------------

function New-ProbeRunspace {
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $runspace
}

$script:Runspace = New-ProbeRunspace
# A query that doesn't stop holds its runspace (Stuck): it's left there (Abandoned), and another takes over
# (Restore-Probe).
$script:Stuck = $false
$script:Abandoned = 0
# -Option Fast for the queries, once it's known to work (Compare-Option).
$script:Fast = $false

# What the steps share. Rows are read there, so that only names, types and counts come out.
$script:Helpers = {
    $ErrorActionPreference = 'Stop'

    function Get-RowName($Row) {
        # A row's columns: the console's own list of them when the object has one, else its properties.
        $names = @()
        try {
            $base = $Row.PSObject.BaseObject
            $list = $base.GetType().GetProperty('PropertyNames')
            if ($list) { $names = @($list.GetValue($base)) }
        }
        catch { $names = @() }
        if (-not $names.Count) { $names = @($Row.PSObject.Properties | Where-Object { $_.MemberType -in 'Property', 'NoteProperty' } | ForEach-Object Name) }
        $names | Where-Object { $_ -and $_ -notmatch '^(__|PS[A-Z])' -and $_ -ne 'SmsProviderObjectPath' } | Sort-Object -Unique
    }

    function Get-RowValue($Row, [string]$Name) {
        # As Repère would read it ($row.Name), else by the console's own indexer.
        $property = $Row.PSObject.Properties[$Name]
        if ($property -and $null -ne $property.Value) { return , $property.Value }
        try { return , $Row[$Name].ObjectValue } catch { return $null }
    }

    function Get-ReadFailure($Row, [string]$Name) {
        # Why a column that reads as nothing can't be read, as its error's type; '' when it's only empty. PowerShell says
        # nothing of a property that throws.
        $base = $Row.PSObject.BaseObject
        $indexer = $base.GetType().GetProperty('Item', [type[]]@([string]))
        if (-not $indexer) { return '' }
        try {
            $held = $indexer.GetValue($base, @($Name))
            $getter = if ($null -ne $held) { $held.GetType().GetProperty('ObjectValue') }
            if ($getter) { $null = $getter.GetValue($held) }
            ''
        }
        catch {
            $failure = $_.Exception
            while ($failure.InnerException) { $failure = $failure.InnerException }
            $failure.GetType().Name
        }
    }

    function Get-ColumnShape($Value) {
        # What a column holds, without any of it: its type, how many rows have it, and how a date or a number is written.
        # $Value: a list of the rows' values.
        $filled = [System.Collections.Generic.List[object]]::new()
        foreach ($each in $Value) { if ($null -ne $each -and "$each" -ne '') { $filled.Add($each) } }
        $shape = ''
        if ($filled.Count) {
            $first = $filled[0]
            $shape = if ($first -is [array]) { "$($first.GetType().GetElementType().Name)[]" } else { $first.GetType().Name }
            if ($first -is [string]) {
                if ($first -match '^\d{14}\.\d{6}[+-]\d{3}$') { $shape = 'String, WMI date, offset' }
                elseif ($first -match '^\d{14}\.\d{6}[+-]\*{3}$') { $shape = 'String, WMI date, no offset' }
                elseif ($first -match '^S-1-5-21-') { $shape = 'String, SID' }
                elseif ($first -match '^\d{8}$') { $shape = 'String, 8 digits' }
                elseif ($first -match '^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}') { $shape = 'String, other date' }
            }
            elseif ($first -is [datetime]) { $shape = "DateTime $($first.Kind)" }
            elseif ($first -is [ValueType] -and $first -isnot [bool]) {
                $digits = 0
                foreach ($each in $filled) { $digits = [math]::Max($digits, "$each".TrimStart('-').Length) }
                $shape += ", $digits digit(s)"
            }
        }
        [pscustomobject]@{ Shape = $shape; Filled = $filled.Count }
    }

    function Get-RowSummary($Row, [int]$QueryMs) {
        # Rows as their number and columns. $Row: a list of them.
        $columns = [ordered]@{}
        if ($Row.Count) {
            foreach ($name in @(Get-RowName $Row[0])) {
                $values = [System.Collections.Generic.List[object]]::new()
                foreach ($each in $Row) { $values.Add((Get-RowValue $each $name)) }
                $shape = Get-ColumnShape $values
                if (-not $shape.Filled) {
                    $failure = Get-ReadFailure $Row[0] $name
                    if ($failure) { $shape.Shape = "UNREADABLE ($failure)" }
                }
                $columns[$name] = $shape
            }
        }
        [pscustomobject]@{ Rows = $Row.Count; Columns = $columns; QueryMs = $QueryMs }
    }

    function Get-Row([string]$Query, [bool]$Fast) {
        # A query's rows, as one list: a row alone is never unrolled into what it may hold.
        $rows = [System.Collections.Generic.List[object]]::new()
        $options = @{}
        if ($Fast) { $options['Option'] = 'Fast' }
        Invoke-CMWmiQuery -Query $Query @options | ForEach-Object { if ($null -ne $_) { $rows.Add($_) } }
        , $rows
    }

    function ConvertTo-SiteDate($Value) {
        # A date as the site gives it, whichever time zone it's in.
        if ($Value -is [datetime]) { return $Value }
        if ("$Value" -match '^\d{14}\.') { return [datetime]::ParseExact("$Value".Substring(0, 14), 'yyyyMMddHHmmss', [cultureinfo]::InvariantCulture) }
    }

    function ConvertTo-WqlText([string]$Text) { $Text.Replace('\', '\\').Replace("'", "\'") }
}

function Invoke-Step([scriptblock]$Script, [hashtable]$With = @{}, [int]$Seconds = $Limit) {
    # Runs $Script in the runspace: its output (Value, the last one), or why not (Text, Failure), and how long it took.
    # Past the limit it's asked to stop; one that doesn't keeps the runspace (Stuck).
    $result = [pscustomobject]@{ Ok = $false; Ms = 0; Value = $null; Failure = $null; Text = ''; Warnings = 0 }
    if ($script:Stuck) { $result.Text = 'NOT RUN: an earlier step holds the runspace'; return $result }
    $shell = [powershell]::Create()
    $shell.Runspace = $script:Runspace
    $null = $shell.AddScript([string]$script:Helpers, $false).AddStatement().AddScript([string]$Script).AddParameters($With)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    # What the module's own code writes to the console would go past everything above.
    $consoleOut, $consoleError = [Console]::Out, [Console]::Error
    [Console]::SetOut([System.IO.TextWriter]::Null)
    [Console]::SetError([System.IO.TextWriter]::Null)
    try {
        $handle = $shell.BeginInvoke()
        if ($handle.AsyncWaitHandle.WaitOne($Seconds * 1000)) {
            try {
                $output = @($shell.EndInvoke($handle))
                $result.Ok = $true
                if ($output.Count) { $result.Value = $output[-1] }
            }
            catch {
                # EndInvoke's own exception holds the script's.
                $result.Failure = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_ }
                $result.Text = "ERROR $(Hide-Name (Format-Failure $result.Failure))"
            }
            $result.Ms = $watch.ElapsedMilliseconds
            $result.Warnings = $shell.Streams.Warning.Count
            $shell.Dispose()
        }
        else {
            $result.Ms = $watch.ElapsedMilliseconds
            $stop = $shell.BeginStop($null, $null)
            $script:Stuck = -not $stop.AsyncWaitHandle.WaitOne($StopLimit * 1000)
            $result.Text = "NO ANSWER in $Seconds s; $(if ($script:Stuck) { "did not stop in $StopLimit s" } else { "stopped in $($watch.ElapsedMilliseconds - $result.Ms) ms" })"
            if (-not $script:Stuck) { $shell.Dispose() }
        }
    }
    finally {
        [Console]::SetOut($consoleOut)
        [Console]::SetError($consoleError)
    }
    $result
}

function Write-Step([string]$Label, $Step, [string]$Found) {
    # A step's line: how long it took, then what it found, or why not. After one that kept the runspace, a new one.
    $text = if ($Step.Ok) { $Found } else { $Step.Text }
    if ($Step.Warnings) { $text += " ($($Step.Warnings) warning(s))" }
    Write-Line ('  {0,-40} {1,7} ms  {2}' -f $Label, $Step.Ms, $text)
    if ($Detail -and $Step.Failure) { Write-Output "      (don't paste) $(Get-FailureMessage $Step.Failure)" }
    if ($script:Stuck) { Restore-Probe }
}

function Invoke-Query([string]$Query, [switch]$Plain) {
    # A query's rows summed up, with -Option Fast once it's known to work, unless -Plain.
    Invoke-Step -With @{ Query = $Query; Fast = ($script:Fast -and -not $Plain) } -Script {
        param([string]$Query, [bool]$Fast)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $rows = Get-Row $Query $Fast
        Get-RowSummary $rows $watch.ElapsedMilliseconds
    }
}

function Get-RowCount($Step) { if ($Step.Ok -and $Step.Value) { $Step.Value.Rows } else { 0 } }

function Format-Count($Step, [string]$Unit = 'row(s)') {
    # « 12 row(s), 80 ms in the query »: the rest of a step's time is reading its columns, which Repère does less of.
    $count = Get-RowCount $Step
    "$count $Unit$(if ($count) { ", $($Step.Value.QueryMs) ms in the query" })"
}

function Write-ColumnList($Summary, [string[]]$Wanted, [switch]$CountOther) {
    # The columns Repère wants, each with its type and how many rows have it, then how many others (their names with
    # -ColumnNames).
    $found = @($Wanted | Where-Object { $Summary.Columns.Contains($_) })
    foreach ($name in $found) {
        $column = $Summary.Columns[$name]
        Write-Line ('      {0,-30} {1,-26} {2}/{3}' -f $name, $(if ($column.Shape) { $column.Shape } else { 'empty' }), $column.Filled, $Summary.Rows)
    }
    $missing = @($Wanted | Where-Object { $_ -notin $found })
    if ($missing.Count) { Write-Line "      NOT THERE: $($missing -join ', ')" }
    $others = @($Summary.Columns.Keys | Where-Object { $_ -notin $Wanted })
    if ($others.Count) { Write-Line "      others: $(if ($CountOther -or -not $ColumnNames) { $others.Count } else { Hide-Name ($others -join ', ') })" }
}

# --- The probe -------------------------------------------------------------------------------------------------------

# Each class with the columns Repère would read, for a section of Specifications or for something else (Use).
$script:ClassList = @(
    @{ Name = 'SMS_G_System_WORKSTATION_STATUS'; Use = 'Scan date'; Columns = 'LastHardwareScan', 'TimeStamp', 'TimeZoneOffset' }
    @{ Name = 'SMS_G_System_COMPUTER_SYSTEM'; Use = 'General'; Columns = 'Name', 'Domain', 'DomainRole', 'Manufacturer', 'Model', 'UserName', 'SystemType' }
    @{ Name = 'SMS_G_System_COMPUTER_SYSTEM_PRODUCT'; Use = 'General'; Columns = 'Name', 'Version', 'IdentifyingNumber', 'UUID' }
    @{ Name = 'SMS_G_System_PC_BIOS'; Use = 'General'; Columns = 'SerialNumber', 'SMBIOSBIOSVersion', 'ReleaseDate', 'Manufacturer' }
    @{ Name = 'SMS_G_System_OPERATING_SYSTEM'; Use = 'General'; Columns = 'Caption', 'Version', 'BuildNumber', 'InstallDate', 'LastBootUpTime', 'TotalVisibleMemorySize' }
    @{ Name = 'SMS_G_System_SYSTEM_ENCLOSURE'; Use = 'General'; Columns = 'ChassisTypes', 'SerialNumber', 'SMBIOSAssetTag' }
    @{ Name = 'SMS_G_System_NETWORK_ADAPTER_CONFIGURATION'; Use = 'Network'; Columns = 'IPAddress', 'MACAddress', 'DefaultIPGateway', 'DNSServerSearchOrder', 'DNSHostName', 'DNSDomain', 'Index', 'IPEnabled' }
    @{ Name = 'SMS_G_System_NETWORK_ADAPTER'; Use = 'Network'; Columns = 'Name', 'AdapterType', 'MACAddress', 'DeviceID', 'Speed' }
    @{ Name = 'SMS_G_System_PROCESSOR'; Use = 'Processor'; Columns = 'Name', 'Manufacturer', 'MaxClockSpeed', 'NumberOfCores', 'NumberOfLogicalProcessors', 'Architecture', 'AddressWidth' }
    @{ Name = 'SMS_G_System_X86_PC_MEMORY'; Use = 'Memory'; Columns = @('TotalPhysicalMemory') }
    @{ Name = 'SMS_G_System_PHYSICAL_MEMORY'; Use = 'Memory'; Columns = 'Capacity', 'Speed', 'MemoryType', 'SMBIOSMemoryType', 'FormFactor', 'Manufacturer', 'PartNumber', 'BankLabel' }
    @{ Name = 'SMS_G_System_DISK'; Use = 'Disks'; Columns = 'Model', 'Caption', 'Size', 'InterfaceType', 'Index' }
    @{ Name = 'SMS_G_System_LOGICAL_DISK'; Use = 'Disks'; Columns = 'DeviceID', 'DriveType', 'Size', 'FreeSpace', 'FileSystem', 'VolumeName' }
    @{ Name = 'SMS_G_System_ADD_REMOVE_PROGRAMS'; Use = 'Software'; Columns = 'DisplayName', 'Version', 'Publisher', 'InstallDate', 'ProdID' }
    @{ Name = 'SMS_G_System_ADD_REMOVE_PROGRAMS_64'; Use = 'Software'; Columns = 'DisplayName', 'Version', 'Publisher', 'InstallDate', 'ProdID' }
    @{ Name = 'SMS_G_System_INSTALLED_SOFTWARE'; Use = 'Software'; Columns = 'ARPDisplayName', 'ProductName', 'ProductVersion', 'Publisher', 'InstallDate' }
    @{ Name = 'SMS_G_System_DESKTOP_MONITOR'; Use = 'Monitors'; Columns = 'Name', 'DeviceID', 'MonitorManufacturer', 'PNPDeviceID' }
    @{ Name = 'SMS_G_System_BATTERY'; Use = 'Battery'; Columns = 'Name', 'EstimatedChargeRemaining', 'DesignCapacity' }
    @{ Name = 'SMS_G_System_PORTABLE_BATTERY'; Use = 'Battery'; Columns = 'Name', 'DesignCapacity' }
    @{ Name = 'SMS_G_System_USB_DEVICE'; Use = 'Dock'; Columns = 'Name', 'DeviceID' }
    @{ Name = 'SMS_G_System_SYSTEM_CONSOLE_USAGE'; Use = 'Last user'; Columns = 'TopConsoleUser', 'TimeStamp' }
    @{ Name = 'SMS_CombinedDeviceResources'; Use = 'SCCM card'; Columns = 'ClientActiveStatus', 'LastActiveTime', 'LastHardwareScan', 'SerialNumber', 'PrimaryUser', 'CurrentLogonUser', 'IsActive', 'CNIsOnline', 'CNLastOnlineTime', 'UserName', 'UserDomainName', 'IsObsolete', 'IsClient', 'LastDDR', 'LastPolicyRequest' }
    @{ Name = 'SMS_CH_Summary'; Use = 'SCCM card'; Columns = 'ClientActiveStatus', 'ClientState', 'LastActiveTime', 'LastHW', 'LastOnline' }
    @{ Name = 'SMS_UserMachineRelationship'; Use = 'Primary user'; Columns = 'UniqueUserName', 'Types', 'Sources', 'IsActive', 'CreationTime' }
)
$script:RecordColumns = 'ResourceID', 'Name', 'NetbiosName', 'SID', 'FullDomainName', 'ResourceDomainORWorkgroup', 'DistinguishedName', 'Active', 'Client',
'ClientVersion', 'Obsolete', 'Decommissioned', 'CreationDate', 'LastLogonUserName', 'LastLogonUserDomain', 'LastLogonTimestamp', 'OperatingSystemNameandVersion',
'Build', 'ADSiteName', 'SystemOUName', 'AgentName', 'AgentTime', 'IPAddresses', 'MACAddresses', 'SMBIOSGUID', 'SMSUniqueIdentifier'

# What the sections share: whether the site's drive is in use (Ready), the computer's ResourceID once found (Id, which
# never comes out), and what each class gave, by use (Outcome).
$script:State = @{ Ready = $false; Id = 0; Outcome = [ordered]@{} }

# Loads the console's module and goes to the site's drive as Repère does: the drive the module mounted by itself, if
# there's one.
$script:OpenScript = {
    param([string]$Site, [string]$Server)
    if (Get-Module -ListAvailable ConfigurationManager) { Import-Module ConfigurationManager }
    else { Import-Module (Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1') }
    if (-not (Get-PSDrive -Name $Site -PSProvider CMSite -ErrorAction SilentlyContinue)) { $null = New-PSDrive -Name $Site -PSProvider CMSite -Root $Server -Scope Global }
    Set-Location "$($Site):\"
}

function Restore-Probe {
    # A new runspace, at the site's drive, after a query that kept the one before. Three at most.
    $script:Abandoned++
    if ($script:Abandoned -gt 3 -or -not $script:State.Ready) { return }
    $script:Runspace = New-ProbeRunspace
    $script:Stuck = $false
    $step = Invoke-Step -Seconds ($Limit * 2) -With @{ Site = $Site; Server = $Server } -Script $script:OpenScript
    Write-Line ('  {0,-40} {1,7} ms  {2}' -f '(a new runspace, to go on)', $step.Ms, $(if ($step.Ok) { 'yes' } else { $step.Text }))
    if (-not $step.Ok) { $script:Stuck = $true }
}

function Show-Console {
    Write-Line "  PowerShell $($PSVersionTable.PSVersion), $(if ([Environment]::Is64BitProcess) { '64' } else { '32' })-bit, culture $([cultureinfo]::CurrentCulture.Name)"
    $step = Invoke-Step -Seconds ($Limit * 2) -Script {
        $via = if (Get-Module -ListAvailable ConfigurationManager) { 'PSModulePath' } elseif ($env:SMS_ADMIN_UI_PATH) { 'SMS_ADMIN_UI_PATH' } else { 'none' }
        if ($via -eq 'PSModulePath') { Import-Module ConfigurationManager }
        elseif ($via -ne 'none') { Import-Module (Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1') }
        $module = Get-Module ConfigurationManager
        [pscustomobject]@{
            Via = $via; Version = "$(if ($module) { $module.Version })"
            # Through Windows PowerShell, its objects would only be copies, and its drive out of reach.
            Proxy = [bool](Get-PSSession -Name WinPSCompatSession -ErrorAction SilentlyContinue)
            Query = [bool](Get-Command Invoke-CMWmiQuery -ErrorAction SilentlyContinue)
        }
    }
    $module = $step.Value
    Write-Step 'Module loaded' $step $(if ($module) { "version $($module.Version), from $($module.Via), Windows PowerShell proxy: $($module.Proxy), Invoke-CMWmiQuery: $($module.Query)" })
    if (-not $module -or $module.Via -eq 'none') { Write-Line '  Stopped: no console module to query with.'; return }

    $step = Invoke-Step -With @{ Site = $Site; Server = $Server } -Script {
        param([string]$Site, [string]$Server)
        $all = @(Get-PSDrive -PSProvider CMSite -ErrorAction SilentlyContinue)
        $drive = @($all | Where-Object Name -eq $Site)
        $root = if ($drive.Count) { "$($drive[0].Root)".Trim('\') } else { '' }
        [pscustomobject]@{
            Drives = $all.Count; Mounted = [bool]$drive.Count
            Same = if (-not $drive.Count) { '-' } elseif (-not $root) { 'not said' } elseif ($root -eq $Server) { 'yes' }
                   elseif (($root -split '\.')[0] -eq ($Server -split '\.')[0]) { 'yes, written differently' } else { 'NO, another server' }
        }
    }
    $drive = $step.Value
    Write-Step 'Drives the module mounted by itself' $step $(if ($drive) { "$($drive.Drives); this site's: $($drive.Mounted); on the server of Settings: $($drive.Same)" })
    $step = Invoke-Step -With @{ Site = $Site; Server = $Server } -Script $script:OpenScript
    Write-Step 'At the site''s drive, as Next name goes' $step 'yes'
    $script:State.Ready = $step.Ok
    if (-not $step.Ok) { Write-Line '  Stopped: the site''s drive can''t be used.' }
}

function Show-Computer {
    $byName = "SELECT * FROM SMS_R_System WHERE Name = '$ComputerName'"
    # The record to read: of those not obsolete, the latest. Chosen by whichever of the two reads answers.
    $pick = {
        param([string]$Query)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $rows = Get-Row $Query $false
        $summary = Get-RowSummary $rows $watch.ElapsedMilliseconds
        $best = $null; $bestId = -1; $bestCurrent = $false; $current = 0
        foreach ($row in $rows) {
            $isCurrent = "$(Get-RowValue $row 'Obsolete')" -notin '1', 'True' -and "$(Get-RowValue $row 'Decommissioned')" -notin '1', 'True'
            if ($isCurrent) { $current++ }
            $id = [int64]("$(Get-RowValue $row 'ResourceID')" -as [int64])
            if ($null -eq $best -or ($isCurrent -and -not $bestCurrent) -or ($isCurrent -eq $bestCurrent -and $id -gt $bestId)) { $best = $row; $bestId = $id; $bestCurrent = $isCurrent }
        }
        $domain = "$(if ($null -ne $best) { Get-RowValue $best 'FullDomainName' })"
        $global:RepereProbeSid = "$(if ($null -ne $best) { Get-RowValue $best 'SID' })"
        [pscustomobject]@{
            Rows = $summary.Rows; Columns = $summary.Columns; QueryMs = $summary.QueryMs; Current = $current
            Id = [math]::Max([int64]$bestId, [int64]0)
            Domain = if (-not $domain) { 'empty' } elseif ($domain.Contains('.')) { 'a DNS name' } else { 'a short name' }
            # Whether $row.Column works, or only the console's own way in.
            Plain = $null -ne $best -and [bool]$best.PSObject.Properties['ResourceID']
        }
    }
    $first = Invoke-Step -With @{ Query = $byName } -Script $pick
    Write-Step 'SMS_R_System by name, first time' $first (Format-Count $first 'record(s)')
    $again = Invoke-Step -With @{ Query = $byName } -Script $pick
    Write-Step 'SMS_R_System by name, again' $again (Format-Count $again 'record(s)')
    $read = if ($again.Ok) { $again } else { $first }
    if (Get-RowCount $read) {
        $record = $read.Value
        Write-Line "      not obsolete: $($record.Current); `$row.Column works: $($record.Plain); FullDomainName: $($record.Domain); ResourceID: $(if ($record.Id) { 'read' } else { 'NOT READABLE' })"
        # The others are only counted: a site can discover AD attributes of its own there.
        Write-ColumnList $record -CountOther -Wanted $script:RecordColumns
        $script:State.Id = $record.Id
    }
    # The ways to look for a computer don't all apply the account's limits: each one's answer, whatever the others say.
    foreach ($way in @(
            @{ Label = 'Get-CMDevice -Resource'; Parameters = @{ Resource = $true } }
            @{ Label = 'Get-CMDevice -Fast'; Parameters = @{ Fast = $true } })) {
        $step = Invoke-Step -With @{ Name = $ComputerName; Parameters = $way.Parameters } -Script {
            param([string]$Name, [hashtable]$Parameters)
            $count = 0
            Get-CMDevice -Name $Name @Parameters | ForEach-Object { if ($null -ne $_) { $count++ } }
            $count
        }
        Write-Step $way.Label $step "$($step.Value) record(s)"
    }
    foreach ($class in 'SMS_Resource', 'SMS_CombinedDeviceResources') {
        $step = Invoke-Step -With @{ Query = "SELECT ResourceID FROM $class WHERE Name = '$ComputerName'" } -Script {
            param([string]$Query)
            $rows = Get-Row $Query $false
            $id = [int64]0
            foreach ($row in $rows) { $id = [math]::Max($id, [int64]("$(Get-RowValue $row 'ResourceID')" -as [int64])) }
            [pscustomobject]@{ Rows = $rows.Count; Id = $id }
        }
        Write-Step "$class by name" $step "$(Get-RowCount $step) record(s)"
        if (-not $script:State.Id -and (Get-RowCount $step) -and $step.Value.Id) {
            $script:State.Id = $step.Value.Id
            Write-Line '      (read below with this record, which SMS_R_System didn''t give)'
        }
    }
    if ($script:State.Id) { return }
    Write-Line
    if ($read.Ok -and -not (Get-RowCount $read)) {
        Write-Line '  SCCM answered, with no record your account can see. If SCCM has this computer, this is what limited access'
        Write-Line '  looks like. Otherwise, run the probe on another computer.'
    }
    else { Write-Line '  Whether SCCM has this computer isn''t known: the reads above failed, or gave no ResourceID.' }
}

function Compare-Option {
    # The same queries with and without -Option Fast, then the rest with Fast if it answered them all.
    $id = $script:State.Id
    $works = $true
    foreach ($query in @(
            @{ Label = 'G_WORKSTATION_STATUS'; Text = "SELECT * FROM SMS_G_System_WORKSTATION_STATUS WHERE ResourceID = $id" }
            @{ Label = 'G_ADD_REMOVE_PROGRAMS_64'; Text = "SELECT * FROM SMS_G_System_ADD_REMOVE_PROGRAMS_64 WHERE ResourceID = $id" }
            @{ Label = 'G_PC_BIOS, two columns'; Text = "SELECT ResourceID, SerialNumber FROM SMS_G_System_PC_BIOS WHERE ResourceID = $id" })) {
        foreach ($fast in $false, $true) {
            $script:Fast = $fast
            $step = Invoke-Query $query.Text
            $script:Fast = $false
            if ($fast -and -not $step.Ok) { $works = $false }
            Write-Step "$($query.Label)$(if ($fast) { ', Fast' })" $step "$(Format-Count $step)$(if (Get-RowCount $step) { ", $($step.Value.Columns.Count) column(s)" })"
        }
    }
    $script:Fast = $works
    Write-Line "  Below: $(if ($works) { 'with' } else { 'without' }) -Option Fast"
}

function Show-Inventory {
    foreach ($class in $script:ClassList) {
        $query = "SELECT * FROM $($class.Name) WHERE ResourceID = $($script:State.Id)"
        $label = $class.Name -replace '^SMS_G_System_', 'G_'
        $step = Invoke-Query $query
        Write-Step $label $step "$(Format-Count $step)  [$($class.Use)]"
        if ($step.Failure -and $script:Fast) {
            $step = Invoke-Query $query -Plain
            Write-Step "$label, not Fast" $step "$(Format-Count $step)  [$($class.Use)]"
        }
        $rows = Get-RowCount $step
        if ($rows) { Write-ColumnList $step.Value $class.Columns }
        $state = if ($rows) { "$rows row(s)" } elseif ($step.Ok) { 'empty' } elseif ($step.Failure) { 'error' } else { 'no answer' }
        if (-not $script:State.Outcome.Contains($class.Use)) { $script:State.Outcome[$class.Use] = [System.Collections.Generic.List[string]]::new() }
        $script:State.Outcome[$class.Use].Add("$($class.Name -replace '^SMS_(G_System_)?') $state")
    }
}

function Show-Date {
    # Whether the dates are the computer's, the site's or UTC: from the hours between them, never the dates.
    $step = Invoke-Step -With @{ Id = $script:State.Id; Fast = $script:Fast } -Script {
        param([int64]$Id, [bool]$Fast)
        $read = {
            param([string]$Column, [string]$Class)
            try { foreach ($row in (Get-Row "SELECT * FROM $Class WHERE ResourceID = $Id" $Fast)) { return ConvertTo-SiteDate (Get-RowValue $row $Column) } }
            catch { return $null }
        }
        $hours = { param($From, $To) if ($From -and $To) { '{0:0.0} h' -f ($To - $From).TotalHours } else { '-' } }
        $scan = & $read 'LastHardwareScan' 'SMS_G_System_WORKSTATION_STATUS'
        $active = & $read 'LastActiveTime' 'SMS_CombinedDeviceResources'
        $now = [datetime]::Now
        $universal = [datetime]::UtcNow
        [pscustomobject]@{
            Days = if ($scan) { "$([math]::Round(($now - $scan).TotalDays)) day(s) ago" } else { 'none' }
            Lines = @(
                "to CombinedDeviceResources: $(& $hours $scan (& $read 'LastHardwareScan' 'SMS_CombinedDeviceResources')); to CH_Summary.LastHW: $(& $hours $scan (& $read 'LastHW' 'SMS_CH_Summary'))"
                "CombinedDeviceResources.LastActiveTime to now: $(& $hours $active $now); to now in UTC: $(& $hours $active $universal)"
            )
        }
    }
    Write-Step 'Last hardware scan' $step "$(if ($step.Ok -and $step.Value) { $step.Value.Days })"
    if ($step.Ok -and $step.Value) { foreach ($line in $step.Value.Lines) { Write-Line "      $line" } }
}

function Show-OtherRead {
    $ids = @(0..49 | ForEach-Object { $script:State.Id + $_ }) -join ','
    $step = Invoke-Query "SELECT ResourceID, LastHardwareScan FROM SMS_G_System_WORKSTATION_STATUS WHERE ResourceID IN ($ids)"
    Write-Step '50 scan dates at once (IN)' $step (Format-Count $step)
    $step = Invoke-Query "SELECT ResourceID, SerialNumber FROM SMS_G_System_PC_BIOS WHERE ResourceID IN ($ids)"
    Write-Step '50 serial numbers at once (IN)' $step (Format-Count $step)
    $step = Invoke-Query "SELECT ResourceID, Name FROM SMS_R_System WHERE Name = '$ComputerName'"
    Write-Step 'SMS_R_System by name, two columns' $step "$(Format-Count $step 'record(s)')$(if (Get-RowCount $step) { ", $($step.Value.Columns.Count) column(s) given" })"
    $step = Invoke-Step -With @{ Fast = $script:Fast } -Script {
        param([bool]$Fast)
        # Not there in a runspace that took over.
        $sid = Get-Variable RepereProbeSid -Scope Global -ValueOnly -ErrorAction SilentlyContinue
        if (-not $sid) { return 'no SID to look for' }
        "$((Get-Row "SELECT ResourceID FROM SMS_R_System WHERE SID = '$(ConvertTo-WqlText $sid)'" $Fast).Count) record(s)"
    }
    Write-Step 'SMS_R_System by SID' $step "$($step.Value)"
    # The serial number stays in the runspace: only how many computers have it comes out.
    $step = Invoke-Step -With @{ Id = $script:State.Id; Fast = $script:Fast } -Script {
        param([int64]$Id, [bool]$Fast)
        $serial = ''
        foreach ($row in (Get-Row "SELECT SerialNumber FROM SMS_G_System_PC_BIOS WHERE ResourceID = $Id" $Fast)) { $serial = "$(Get-RowValue $row 'SerialNumber')".Trim() }
        if (-not $serial) { return 'no serial number to look for' }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $count = (Get-Row "SELECT ResourceID FROM SMS_G_System_PC_BIOS WHERE SerialNumber = '$(ConvertTo-WqlText $serial)'" $Fast).Count
        "$count computer(s), $($watch.ElapsedMilliseconds) ms in the query"
    }
    Write-Step 'PC_BIOS by serial number' $step "$($step.Value)"
}

function Show-Wrong {
    foreach ($query in @(
            @{ Label = 'A name that doesn''t exist'; Text = "SELECT ResourceID FROM SMS_R_System WHERE Name = 'REPERE-TEST-NONE'" }
            @{ Label = 'A quote in a name, as \'''; Text = "SELECT ResourceID FROM SMS_R_System WHERE Name = 'REPERE\'TEST'" }
            @{ Label = 'A quote in a name, as '''''; Text = "SELECT ResourceID FROM SMS_R_System WHERE Name = 'REPERE''TEST'" }
            @{ Label = 'A class that doesn''t exist'; Text = 'SELECT * FROM SMS_G_System_REPERE_NONE WHERE ResourceID = 1' }
            @{ Label = 'A column that doesn''t exist'; Text = "SELECT RepereNone FROM SMS_R_System WHERE Name = '$ComputerName'" })) {
        $step = Invoke-Query $query.Text
        Write-Step $query.Label $step "no error, $(Format-Count $step)"
    }
}

function Show-Drive {
    # Last, in a runspace of its own: whether Repère can make sure of the server it was given, by taking the module's
    # drive off and mounting its own. In this probe only.
    if (-not $script:Stuck) { $script:Runspace.Dispose() }
    $script:Runspace = New-ProbeRunspace
    $script:Stuck = $false
    $step = Invoke-Step -Seconds ($Limit * 2) -With @{ Site = $Site; Server = $Server } -Script $script:OpenScript
    Write-Step 'A second runspace at the drive' $step 'yes'
    if (-not $step.Ok) { return }
    $step = Invoke-Step -With @{ Site = $Site } -Script {
        param([string]$Site)
        Set-Location $env:SystemRoot
        Remove-PSDrive -Name $Site -PSProvider CMSite -Force
    }
    Write-Step 'Its drive taken off' $step 'yes'
    if (-not $step.Ok) { return }
    $step = Invoke-Step -With @{ Site = $Site; Server = $Server } -Script {
        param([string]$Site, [string]$Server)
        if (Get-PSDrive -Name $Site -PSProvider CMSite -ErrorAction SilentlyContinue) { return 'the one taken off is still there' }
        $null = New-PSDrive -Name $Site -PSProvider CMSite -Root $Server -Scope Global
        Set-Location "$($Site):\"
        'yes'
    }
    Write-Step 'Mounted on the server of Settings' $step "$($step.Value)"
    if (-not $step.Ok -or $step.Value -ne 'yes') { return }
    $step = Invoke-Query "SELECT ResourceID FROM SMS_R_System WHERE Name = '$ComputerName'"
    Write-Step 'A query through it' $step (Format-Count $step 'record(s)')
}

function Show-Summary {
    foreach ($use in $script:State.Outcome.Keys) { Write-Line ('  {0,-14} {1}' -f $use, ($script:State.Outcome[$use] -join '; ')) }
}

function Invoke-Probe {
    Write-Line 'SCCM probe 1. Read it once before you paste it: no value should be in it.'
    # What each section needs from those before it; one that fails doesn't stop the next ones.
    foreach ($section in @(
            @{ Title = 'Console'; Run = 'Show-Console'; Needs = '' }
            @{ Title = 'Finding the computer'; Run = 'Show-Computer'; Needs = 'Ready' }
            @{ Title = 'With and without -Option Fast'; Run = 'Compare-Option'; Needs = 'Id' }
            @{ Title = 'Inventory'; Run = 'Show-Inventory'; Needs = 'Id' }
            @{ Title = 'Dates'; Run = 'Show-Date'; Needs = 'Id' }
            @{ Title = 'The other reads planned'; Run = 'Show-OtherRead'; Needs = 'Id' }
            @{ Title = 'How a wrong query answers'; Run = 'Show-Wrong'; Needs = 'Ready' }
            @{ Title = 'The drive, on the server of Settings'; Run = 'Show-Drive'; Needs = 'Ready' }
            @{ Title = 'Summary'; Run = 'Show-Summary'; Needs = 'Id' })) {
        if ($section.Needs -and -not $script:State[$section.Needs]) { continue }
        Write-Line
        Write-Line "== $($section.Title)"
        try { & $section.Run }
        catch { Write-Line "  PROBE ERROR, line $($_.InvocationInfo.ScriptLineNumber): $(Hide-Name (Format-Failure $_))" }
    }
}

Invoke-Probe
if ($script:OutFile) { Write-Output ''; Write-Output 'Also in %TEMP%\SccmProbe.txt' }
if (-not $script:Abandoned) { $script:Runspace.Dispose(); exit 0 }
# A query that never stopped would hold the process's end. Only a process pwsh -File started is the probe's own to end.
if (@([Environment]::GetCommandLineArgs() | Where-Object { $_ -in '-File', '-f' }).Count) { [Console]::Out.Flush(); [Environment]::Exit(2) }
Write-Output 'A query is still running: close this window once you have the output.'
