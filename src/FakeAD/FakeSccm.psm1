# Fake ConfigurationManager module, for what asks SCCM with the fake AD. Loaded in place of the real one, in the runspace
# of its own where $script:SccmLinkScript (Sccm.ps1) runs: that script is then the same, down to the site's drive.
# The site is DEM on sccm.demo.local. All of it is invented, down to the serial numbers:
# - ORD-01, which AD has too, with a full inventory; ORD-13 and ORD-14, which AD doesn't have, as a reinstalled or deleted
#   computer leaves: the first last scanned long ago, the second without a client, so never; VIEUX-01, which AD never had,
#   obsolete;
# - DOUBLE-01, twice, both current; RENTRE-01, an obsolete record and the current one, made since with another SID;
# - this computer, for Paramètres › SCCM › Tester.
#
# For the tests:
# - $env:REPERE_FAKEAD_SCCM_UNREACHABLE: when set, the site doesn't answer, whether it's being mounted or already is.
# - $env:REPERE_FAKEAD_SCCM_DELAY: seconds; each query takes that long.
# - $env:REPERE_FAKEAD_SCCM_ERROR: a message; mounting the site writes it as an error that doesn't stop the command,
#   as the console does when the site's version isn't its own.
# - $env:REPERE_FAKEAD_SCCM_MOUNTED: a server; the module mounts the site on it by itself, as the console's last one.
# - $env:REPERE_FAKEAD_SCCM_LIMITED: names separated by commas; the account sees no other device, and no error says so.
# - $env:REPERE_FAKEAD_SCCM_REFUSED: a regex; a query it matches is refused.
# - $env:REPERE_FAKEAD_SCCM_STUCK: seconds; each query takes that long, and can't be stopped meanwhile.
# - $env:REPERE_FAKEAD_SCCM_DEAD: set once a runspace has the site open; its queries fail as a dead link does, with this
#   HRESULT, 'wql' (the console's own error for a query) or a text, and only a runspace opened since answers.
# - $env:REPERE_FAKEAD_SCCM_NOCOLUMN: a column no class has, as on a site that doesn't collect it.
# - $env:REPERE_FAKEAD_SCCM_BREAK: set, a query closes its own runspace, as a module that crashes it.
# - $env:REPERE_FAKEAD_SCCM_LOG: a file that gets each query.

$script:Server = 'sccm.demo.local'
$script:Site = 'DEM'
# Whether the location is the site's drive: the real cmdlets refuse to run anywhere else.
$script:OnSiteDrive = $false
# The server the site's drive is on, '' until it's mounted.
$script:MountedServer = "$env:REPERE_FAKEAD_SCCM_MOUNTED"
$script:DeadAtOpening = "$env:REPERE_FAKEAD_SCCM_DEAD"

# The console's own error for a query the site refuses.
if (-not ('FakeSccm.WqlQueryException' -as [type])) {
    Add-Type -TypeDefinition 'namespace FakeSccm { public class WqlQueryException : System.Exception { public WqlQueryException(string message) : base(message) { } } }'
}

function New-Device([int64]$Id, [string]$Name, [string]$Sid, [hashtable]$More = @{}) {
    # A SMS_R_System record, current and with a client unless $More says otherwise.
    $device = [ordered]@{
        ResourceID = [uint32]$Id; Name = $Name; SID = $Sid; FullDomainName = 'demo.local'; ResourceDomainORWorkgroup = 'DEMO'
        Active = 1; Client = 1; ClientVersion = '5.00.9999.1000'; Obsolete = 0; Decommissioned = 0
    }
    foreach ($key in $More.Keys) { $device[$key] = $More[$key] }
    $device
}

$script:Now = [datetime]::Now
# This computer's domain, as Paramètres › SCCM › Tester looks for it.
$script:HereDomain = try { [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName } catch { '' }
if (-not $script:HereDomain) { $script:HereDomain = 'demo.local' }
$script:Devices = @(
    New-Device 16777217 'ORD-01' 'S-1-5-21-1-2-3-9001'
    New-Device 16777218 'ORD-13' 'S-1-5-21-1-2-3-9013'
    New-Device 16777219 'ORD-14' 'S-1-5-21-1-2-3-9014' @{ Client = 0; Active = 0; ClientVersion = $null }
    New-Device 16777220 'VIEUX-01' 'S-1-5-21-1-2-3-9020' @{ Obsolete = 1 }
    New-Device 16777221 'DOUBLE-01' '' @{ FullDomainName = $null; ResourceDomainORWorkgroup = $null }
    New-Device 16777222 'DOUBLE-01' '' @{ FullDomainName = $null; ResourceDomainORWorkgroup = $null }
    New-Device 16777223 'RENTRE-01' 'S-1-5-21-1-2-3-9023' @{ Obsolete = 1 }
    New-Device 16777224 'RENTRE-01' 'S-1-5-21-1-2-3-9024'
    New-Device 16777230 "$env:COMPUTERNAME" '' @{ FullDomainName = $script:HereDomain }
)

function New-Row([int64]$Id, [hashtable]$Values) {
    $row = [ordered]@{ ResourceID = [uint32]$Id; GroupID = [uint32]1; RevisionID = [uint32]1; TimeStamp = $script:Now }
    foreach ($key in $Values.Keys) { $row[$key] = $Values[$key] }
    $row
}

# The inventory, by class: ORD-01's in full, and a computer system for the others that have a client.
$script:Classes = @{
    SMS_R_System                               = $script:Devices
    SMS_G_System_WORKSTATION_STATUS            = @(
        New-Row 16777217 @{ LastHardwareScan = $script:Now.AddDays(-2) }
        New-Row 16777218 @{ LastHardwareScan = $script:Now.AddDays(-45) }
        New-Row 16777224 @{ LastHardwareScan = $script:Now.AddDays(-1) }
    )
    SMS_G_System_COMPUTER_SYSTEM               = @(
        New-Row 16777217 @{ Name = 'ORD-01'; Domain = 'demo.local'; DomainRole = 1; Manufacturer = 'Contoso'; Model = 'Bureau 5000'; UserName = 'DEMO\mroy'; SystemType = 'x64-based PC' }
        New-Row 16777218 @{ Name = 'ORD-13'; Domain = 'demo.local'; DomainRole = 1; Manufacturer = 'Contoso'; Model = 'Portable 300'; UserName = $null; SystemType = 'x64-based PC' }
        New-Row 16777230 @{ Name = "$env:COMPUTERNAME"; Domain = 'demo.local'; DomainRole = 1; Manufacturer = 'Contoso'; Model = 'Portable 300'; UserName = $null; SystemType = 'x64-based PC' }
    )
    SMS_G_System_PC_BIOS                       = @(
        New-Row 16777217 @{ SerialNumber = 'DEMO0001'; SMBIOSBIOSVersion = '1.14.0'; ReleaseDate = [datetime]'2025-03-01'; Manufacturer = 'Contoso' }
        # A quote and a backslash, as no maker writes them, for the queries' escaping.
        New-Row 16777218 @{ SerialNumber = "DEMO'\13"; SMBIOSBIOSVersion = '1.2.0'; ReleaseDate = [datetime]'2022-03-01'; Manufacturer = 'Contoso' }
        # The same serial number under two records.
        New-Row 16777221 @{ SerialNumber = 'DEMO0021'; SMBIOSBIOSVersion = '1.2.0'; ReleaseDate = $null; Manufacturer = 'Contoso' }
        New-Row 16777222 @{ SerialNumber = 'DEMO0021'; SMBIOSBIOSVersion = '1.2.0'; ReleaseDate = $null; Manufacturer = 'Contoso' }
    )
    SMS_G_System_OPERATING_SYSTEM              = @(
        New-Row 16777217 @{ Caption = 'Microsoft Windows 11 Enterprise'; Version = '10.0.26100'; BuildNumber = '26100'; OSArchitecture = '64-bit'; InstallDate = $script:Now.AddDays(-200); LastBootUpTime = $script:Now.AddDays(-9); TotalVisibleMemorySize = [uint64]16500000 }
    )
    SMS_G_System_NETWORK_ADAPTER_CONFIGURATION = @(
        New-Row 16777217 @{ Description = 'Contoso Ethernet'; IPAddress = '192.0.2.11, fe80::1'; MACAddress = '00:00:5E:00:53:01'; DefaultIPGateway = '192.0.2.1'; DNSServerSearchOrder = '192.0.2.2, 192.0.2.3'; DNSDomain = 'demo.local'; DHCPEnabled = 1; Index = 1; IPEnabled = 1 }
        New-Row 16777217 @{ Description = 'Contoso Wi-Fi'; IPAddress = $null; MACAddress = '00:00:5E:00:53:02'; DefaultIPGateway = $null; DNSServerSearchOrder = $null; DNSDomain = $null; DHCPEnabled = 1; Index = 2; IPEnabled = 0 }
    )
    SMS_G_System_PROCESSOR                     = @(
        New-Row 16777217 @{ Name = 'Contoso CPU 7'; Manufacturer = 'Contoso'; MaxClockSpeed = [uint32]2400; NumberOfCores = [uint32]8; NumberOfLogicalProcessors = [uint32]16; Architecture = 9; AddressWidth = 64 }
    )
    SMS_G_System_X86_PC_MEMORY                 = @(New-Row 16777217 @{ TotalPhysicalMemory = [uint64]16500000 })
    SMS_G_System_PHYSICAL_MEMORY               = @(
        New-Row 16777217 @{ BankLabel = 'BANK 0'; DeviceLocator = 'DIMM 1'; Capacity = [uint64]8192; Speed = 4800; MemoryType = 0; FormFactor = 8; Manufacturer = 'Contoso'; PartNumber = 'DEMO-8' }
        New-Row 16777217 @{ BankLabel = 'BANK 1'; DeviceLocator = 'DIMM 2'; Capacity = [uint64]8192; Speed = 4800; MemoryType = 0; FormFactor = 8; Manufacturer = 'Contoso'; PartNumber = 'DEMO-8' }
    )
    SMS_G_System_DISK                          = @(New-Row 16777217 @{ Index = 0; Model = 'Contoso SSD 512'; Caption = 'Contoso SSD 512'; Size = [uint64]488000; InterfaceType = 'SCSI' })
    SMS_G_System_LOGICAL_DISK                  = @(New-Row 16777217 @{ DeviceID = 'C:'; DriveType = 3; Size = [uint64]487000; FreeSpace = [uint64]210000; FileSystem = 'NTFS'; VolumeName = 'Windows' })
    SMS_G_System_ADD_REMOVE_PROGRAMS           = @(New-Row 16777217 @{ DisplayName = 'Contoso Agent'; Version = '3.1'; Publisher = 'Contoso'; InstallDate = '20260110'; ProdID = 'ContosoAgent' })
    SMS_G_System_ADD_REMOVE_PROGRAMS_64        = @(
        New-Row 16777217 @{ DisplayName = 'Contoso Office'; Version = '16.0'; Publisher = 'Contoso'; InstallDate = '20260111'; ProdID = 'ContosoOffice' }
        New-Row 16777217 @{ DisplayName = 'Contoso PDF'; Version = '8.2'; Publisher = 'Contoso'; InstallDate = $null; ProdID = 'ContosoPdf' }
    )
    SMS_CombinedDeviceResources                = @(
        New-Row 16777217 @{ Name = 'ORD-01'; Domain = 'DEMO'; SerialNumber = 'DEMO0001'; SiteCode = 'DEM'; IsClient = $true; IsActive = $true; ClientVersion = '5.00.9999.1000'; ClientActiveStatus = 1; DeviceOSBuild = '10.0.26100.1'; LastActiveTime = $script:Now.AddHours(-5); LastHardwareScan = $script:Now.AddDays(-2); LastPolicyRequest = $script:Now.AddHours(-5); LastLogonUser = 'mroy'; PrimaryUser = 'DEMO\mroy' }
        New-Row 16777218 @{ Name = 'ORD-13'; Domain = 'DEMO'; SerialNumber = "DEMO'\13"; SiteCode = 'DEM'; IsClient = $true; IsActive = $false; ClientVersion = '5.00.9999.1000'; ClientActiveStatus = 0; DeviceOSBuild = $null; LastActiveTime = $script:Now.AddDays(-45); LastHardwareScan = $script:Now.AddDays(-45); LastPolicyRequest = $null; LastLogonUser = $null; PrimaryUser = $null }
        New-Row 16777219 @{ Name = 'ORD-14'; Domain = 'DEMO'; SerialNumber = $null; SiteCode = $null; IsClient = $false; IsActive = $false; ClientVersion = $null; ClientActiveStatus = $null; DeviceOSBuild = $null; LastActiveTime = $null; LastHardwareScan = $null; LastPolicyRequest = $null; LastLogonUser = $null; PrimaryUser = $null }
    )
}

function Get-PSDrive {
    # The site's drive, once it's mounted. The real module can mount one by itself (REPERE_FAKEAD_SCCM_MOUNTED).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Standing in for the CMSite provider is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PSProvider', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([string]$Name, [string]$PSProvider)

    if ($script:MountedServer -and (-not $Name -or $Name -eq $script:Site)) { [pscustomobject]@{ Name = $script:Site; Root = "\\$($script:MountedServer)" } }
}

function New-PSDrive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Standing in for the CMSite provider is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Scope', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([string]$Name, [string]$PSProvider, [string]$Root, [string]$Scope)

    if ($PSProvider -ne 'CMSite') { throw "Provider '$PSProvider' not found." }
    # With their codes, as Windows gives them: Repère knows them by those (Get-ErrorKind), not by their text.
    if ($Root -ne $script:Server) { throw [System.Runtime.InteropServices.COMException]::new('The RPC server is unavailable.', 0x800706BA) }
    Assert-Reachable
    if ($Name -ne $script:Site) { throw [System.Runtime.InteropServices.COMException]::new('Invalid namespace', 0x8004100E) }
    if ($env:REPERE_FAKEAD_SCCM_ERROR) {
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new($env:REPERE_FAKEAD_SCCM_ERROR), 'FakeSccmError', 'InvalidOperation', $Name))
    }
    $script:MountedServer = $Root
    [pscustomobject]@{ Name = $Name; Root = $Root }
}

function Set-Location {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Standing in for the CMSite provider is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([Parameter(Position = 0)] [string]$Path)

    if ($Path -ne "$($script:Site):\") { throw "Cannot find drive for '$Path'." }
    $script:OnSiteDrive = $true
}

function Assert-Reachable {
    if ($env:REPERE_FAKEAD_SCCM_UNREACHABLE) { throw [System.Runtime.InteropServices.COMException]::new('The RPC server is unavailable.', 0x800706BA) }
}

function Enter-Query([string]$Text) {
    # What every query goes through: the drive, the log, the time it takes, and whether the site answers.
    if (-not $script:OnSiteDrive) { throw 'This command cannot be run from the current drive. To run this command you must first connect to a Configuration Manager drive.' }
    if ($env:REPERE_FAKEAD_SCCM_LOG) { Add-Content -LiteralPath $env:REPERE_FAKEAD_SCCM_LOG -Value $Text }
    $delay = 0
    if ([int]::TryParse("$env:REPERE_FAKEAD_SCCM_DELAY", [ref]$delay) -and $delay -gt 0) { Start-Sleep -Seconds $delay }
    $stuck = 0
    if ([int]::TryParse("$env:REPERE_FAKEAD_SCCM_STUCK", [ref]$stuck) -and $stuck -gt 0) { [System.Threading.Thread]::Sleep($stuck * 1000) }
    if ($env:REPERE_FAKEAD_SCCM_BREAK) {
        $null = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.CloseAsync()
        throw 'Broken'
    }
    if ($env:REPERE_FAKEAD_SCCM_DEAD -and $env:REPERE_FAKEAD_SCCM_DEAD -ne $script:DeadAtOpening) {
        if ($env:REPERE_FAKEAD_SCCM_DEAD -eq 'wql') { throw [FakeSccm.WqlQueryException]::new('Query failed') }
        if ($env:REPERE_FAKEAD_SCCM_DEAD -match '^0x') { throw [System.Runtime.InteropServices.COMException]::new('Dead link', [int]$env:REPERE_FAKEAD_SCCM_DEAD) }
        throw $env:REPERE_FAKEAD_SCCM_DEAD
    }
    Assert-Reachable
}

function Test-Visible([string]$Name) {
    # Whether the account sees a device of this name.
    -not $env:REPERE_FAKEAD_SCCM_LIMITED -or $Name -in ($env:REPERE_FAKEAD_SCCM_LIMITED -split ',')
}

function Get-CMDevice {
    # The devices whose name matches, as -Resource gives them: without it, a real read would take far longer.
    [CmdletBinding()]
    param([string]$Name, [switch]$Resource)

    if (-not $Resource) { throw 'Get-CMDevice without -Resource.' }
    Enter-Query "Get-CMDevice $Name"
    $script:Devices | Where-Object { $_.Name -like $Name -and (Test-Visible $_.Name) } | ForEach-Object { [pscustomobject]@{ Name = $_.Name } }
}

function Invoke-CMWmiQuery {
    # SELECT columns FROM class WHERE column = value, or IN (values): what Repère asks, and nothing else.
    [CmdletBinding()]
    param([string]$Query)

    Enter-Query $Query
    if ($Query -notmatch '^SELECT (?<columns>\*|[\w, ]+) FROM (?<class>\w+) WHERE (?<field>\w+) (?:= (?<values>.+)|IN \((?<values>.+)\))$') { throw [FakeSccm.WqlQueryException]::new("Invalid query: $Query") }
    $columns, $class, $field, $values = $Matches.columns, $Matches.class, $Matches.field, $Matches.values
    if ($env:REPERE_FAKEAD_SCCM_REFUSED -and $Query -match $env:REPERE_FAKEAD_SCCM_REFUSED) { throw [System.UnauthorizedAccessException]::new('Access is denied.') }
    if (-not $script:Classes.ContainsKey($class)) { throw [FakeSccm.WqlQueryException]::new("Unknown class: $class") }
    $rows = $script:Classes[$class]
    $known = @($rows[0].Keys | Where-Object { $_ -ne $env:REPERE_FAKEAD_SCCM_NOCOLUMN })
    $wanted = if ($columns -eq '*') { $known } else { @($columns -split ',\s*') }
    foreach ($column in @($wanted) + $field) { if ($column -notin $known) { throw [FakeSccm.WqlQueryException]::new("Unknown column: $column") } }
    # Numbers, or quoted texts with \ before a quote or another \; anything left over is a query broken by its values.
    $pattern = "(?:'(?:[^'\\]|\\['\\])*'|\d+)"
    if ($values -notmatch "^$pattern(?:,$pattern)*$") { throw [FakeSccm.WqlQueryException]::new("Invalid values: $values") }
    $list = @([regex]::Matches($values, $pattern) | ForEach-Object { if ($_.Value[0] -eq "'") { $_.Value.Substring(1, $_.Value.Length - 2) -replace '\\(.)', '$1' } else { $_.Value } })
    $seen = @($script:Devices | Where-Object { Test-Visible $_.Name } | ForEach-Object { $_.ResourceID })
    foreach ($row in $rows) {
        if ($row.ResourceID -notin $seen -or "$($row[$field])" -notin $list) { continue }
        $given = [ordered]@{}
        foreach ($column in $wanted) { $given[$column] = $row[$column] }
        [pscustomobject]$given
    }
}

Export-ModuleMember -Function Get-PSDrive, New-PSDrive, Set-Location, Get-CMDevice, Invoke-CMWmiQuery
