# Reads a computer's hardware, OS and network specs over CIM (WinRM when its port answers, else DCOM), with the current user's rights:
# no agent is needed on the computer, but its administrators group must include the user. Dot-sourced by the
# Caractéristiques window (SpecsWindow.ps1), in a background runspace. Can also run on its own:
#
#   pwsh -File .\PCSpecs.ps1 PC-12345 -AsText
#
# Each section is read on its own: one that fails (no battery, access denied on root\wmi) doesn't keep the others
# from being returned. Its error goes in the result's Errors instead of being thrown. With the fake AD, its module
# replaces the CIM and network commands used here, so the same code reads the fake computers.

[CmdletBinding()]
param(
    # The computer: a DNS name, a NetBIOS name or an IPv4 address. Empty or '.' for this computer.
    [Parameter(Position = 0)]
    [string]$ComputerName = '.',
    [ValidateRange(3, 120)]
    [int]$TimeoutSeconds = 15,
    # A text report instead of an object.
    [switch]$AsText
)

# The text is in Repère's language: Tr (Language.ps1) is the main script's, or given to the reading's runspace
# (SpecsWindow.ps1). Run on its own, without it, the text stays in French. Not a function statement: dot-sourced with
# the main script, this file would define Tr a second time.
if (-not (Get-Command Tr -CommandType Function -ErrorAction Ignore)) { $null = New-Item -Path function:Tr -Value { param([string]$Text) $Text } }

function Test-PCNameValid([string]$Name) {
    # A host name or an IPv4 address: rejects anything that could be abused in a query.
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 253) { return $false }
    $Name -match '^(?!-)[A-Za-z0-9\-\.]+(?<!-)$'
}

function Get-PCSpecsLocalName {
    # This computer's names (Names: NetBIOS and DNS host name) and its FQDN (Fqdn: the host name and the primary DNS
    # suffix), as Windows keeps them, without a DNS query: cheap enough for each reading, and in its runspace too. Not
    # $env:USERDNSDOMAIN: it's the user's domain, which in a forest isn't always the computer's. Never throws: without
    # them, the NetBIOS name alone, and no FQDN, so no DNS name is taken for this computer.
    $hostName, $domainName = try {
        # Windows reads them only when asked, so the properties can fail as well as the call.
        $properties = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        "$($properties.HostName)".TrimEnd('.'), "$($properties.DomainName)".Trim('.')
    }
    catch { '', '' }
    @{
        Names = @($env:COMPUTERNAME, $hostName | Where-Object { $_ })
        Fqdn  = @(if ($hostName -and $domainName) { "$hostName.$domainName" })
    }
}

function Test-PCSpecsLocal([string]$ComputerName) {
    # Whether the computer to read is this one, read without the network: '', '.' or localhost, one of its names alone,
    # or its FQDN, in any case and with or without a trailing dot. A DNS name is compared whole: PC-001.lyon.corp, read
    # from PC-001.paris.corp, is another computer with the same first label.
    $name = $ComputerName.Trim().TrimEnd('.')
    if ($name -in '', 'localhost') { return $true }
    $local = Get-PCSpecsLocalName
    if ($name.Contains('.')) { return $local.Fqdn -contains $name }
    $local.Names -contains $name
}

function Format-Byte([Nullable[double]]$Bytes) {
    if ($null -eq $Bytes -or $Bytes -le 0) { return Tr 'N/D' }
    $gb = $Bytes / 1GB
    if ($gb -ge 1000) { return ((Tr '{0:N2} To') -f ($gb / 1024)) }
    if ($gb -ge 10) { return ((Tr '{0:N0} Go') -f $gb) }
    (Tr '{0:N1} Go') -f $gb
}

function Get-CleanValue($Value) {
    # OEM boards often ship SMBIOS placeholders instead of real values.
    $text = "$Value".Trim()
    $placeholders = '^(|0+|N/?A|None|Default string|To be filled by O\.E\.M\.|System (Serial Number|Product Name|Manufacturer|SKU)|SKU|Not Applicable|Not Specified|Invalid)$'
    if ($text -match $placeholders) { return Tr 'N/D' }
    $text
}

function Get-UniqueText($Values) {
    # The values without the empty ones and the repeats (same text in any case, around spaces too), in their order.
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        $text = "$value".Trim()
        if ($text -and $seen.Add($text)) { $text }
    }
}

function Join-Unique($Values, [string]$Separator = ', ') {
    $unique = @(Get-UniqueText $Values)
    if (-not $unique.Count) { return Tr 'N/D' }
    $unique -join $Separator
}

# JEDEC manufacturer codes (JEP106), as SMBIOS gives them for the memory modules whose maker is not spelled out: the
# bank's number (its continuation count, with a parity bit) and the maker's id, in either order. A short list of the
# makers met most; a code not in it is shown as it is.
$script:MemoryMakers = @{
    '80CE' = 'Samsung';  'CE00' = 'Samsung'
    '802C' = 'Micron';   '2C00' = 'Micron'
    '80AD' = 'SK hynix'; 'AD00' = 'SK hynix'
    '0198' = 'Kingston'; '9801' = 'Kingston'
    '859B' = 'Crucial';  '9B85' = 'Crucial'
    '029E' = 'Corsair';  '9E02' = 'Corsair'
    '04CD' = 'G.Skill';  'CD04' = 'G.Skill'
    '04CB' = 'A-DATA';   'CB04' = 'A-DATA'
}

function ConvertTo-PCMemoryMaker($Manufacturer) {
    # A memory module's maker: its name for a JEDEC code of the list, the text as it is otherwise, and nothing when
    # SMBIOS has no real value (empty, Unknown, Undefined, zeros, OEM placeholders).
    $text = "$Manufacturer".Trim([char]0, ' ', "`t")
    if ($text -match '^(|0+|Unknown|Undefined|N/?A|None|Not (Specified|Available)|Manufacturer\d*|Mfg\d*|To be filled by O\.E\.M\.|Default string)$') { return $null }
    $code = ($text -replace '^0x', '').ToUpperInvariant()
    if ($code -match '^[0-9A-F]{4}$' -and $script:MemoryMakers.ContainsKey($code)) { return $script:MemoryMakers[$code] }
    $text
}

function ConvertTo-PCMemoryPartNumber($PartNumber) {
    # A memory module's part number, without the spaces SMBIOS pads it with, and nothing when it has no real value.
    $text = "$PartNumber".Trim([char]0, ' ', "`t")
    if ($text -match '^(|0+|Unknown|Undefined|N/?A|None|Not (Specified|Available)|Part ?Num(ber)?\d*|Array\d+_PartNumber|To be filled by O\.E\.M\.|Default string)$') { return $null }
    $text
}

function ConvertTo-PCMemory($Modules) {
    # What the modules (Win32_PhysicalMemory) say of who made them: Maker and Part, each one value for all the modules
    # (two of the same make say it once), or $null when none says (the window and the report leave the row out).
    $read = { param($Module, [string]$Name) $property = $Module.PSObject.Properties[$Name]; if ($property) { $property.Value } }
    $makers = @(Get-UniqueText @($Modules | ForEach-Object { ConvertTo-PCMemoryMaker (& $read $_ 'Manufacturer') }))
    $parts = @(Get-UniqueText @($Modules | ForEach-Object { ConvertTo-PCMemoryPartNumber (& $read $_ 'PartNumber') }))
    @{ Maker = if ($makers) { $makers -join ' / ' }; Part = if ($parts) { $parts -join ' / ' } }
}

function Format-PCCpuName([string]$Name, [bool]$ClockShown = $true) {
    # A processor's model as Windows spells it, without what the other rows say or what only adds noise: (R) and (TM),
    # the word CPU, « 6-Core Processor » (Cœurs / threads says it), and « @ 2.60GHz » when Vitesse de base shows the
    # speed (-ClockShown), extra spaces.
    $clean = $Name -replace '\((R|TM)\)', '' -replace '\bCPU\b', '' -replace '\s+(\d+|Dual|Quad)-Core\b', '' -replace '\s+Processor\b', ''
    if ($ClockShown) { $clean = $clean -replace '\s*@\s*\d+([.,]\d+)?\s*[GM]Hz\s*$', '' }
    $clean = ($clean -replace '\s+', ' ').Trim()
    if ($clean) { $clean } else { ($Name -replace '\s+', ' ').Trim() }
}

function Get-PCCpuVendor($Manufacturer, [string]$Model) {
    # A processor's maker, for a row of its own: Intel for GenuineIntel, AMD for AuthenticAMD, else as Windows says it.
    # Nothing when the model already names it (« Intel Core i7-1365U »), or when Windows says none.
    $text = "$Manufacturer".Trim()
    if ($text -match '^(|0+|Unknown|Undefined|N/?A|None|To be filled by O\.E\.M\.)$') { return $null }
    $maker = if ($text -match '^GenuineIntel$') { 'Intel' } elseif ($text -match '^AuthenticAMD$|^Advanced Micro Devices') { 'AMD' } else { $text }
    if ($Model -match "(?i)\b$([regex]::Escape($maker))\b") { return $null }
    $maker
}

function Test-PCSpecsPort([string]$Target, [int]$Port, [int]$TimeoutMilliseconds = 2000) {
    # Whether the computer accepts a connection on the port within the time. The fake AD answers for its computers.
    if (Get-Command Test-ComputerPort -ErrorAction Ignore) { return [bool](Test-ComputerPort $Target $Port $TimeoutMilliseconds) }
    $client = [System.Net.Sockets.TcpClient]::new()
    try { $client.ConnectAsync($Target, $Port).Wait($TimeoutMilliseconds) }
    catch { $false }
    finally { $client.Dispose() }
}

function New-PCSpecsCimSession([string]$Target, [int]$Timeout) {
    # The session (Session) and how it connects (Protocol): WinRM when its port answers, otherwise DCOM at once. A
    # firewall that drops WinRM's port would make WinRM wait for its time limit before DCOM was tried.
    $common = @{ ComputerName = $Target; OperationTimeoutSec = $Timeout; ErrorAction = 'Stop' }
    $wsmanError = Tr 'le port 5985 ne répond pas'
    if (Test-PCSpecsPort $Target 5985) {
        try { return @{ Session = New-CimSession @common; Protocol = 'WinRM' } }
        catch { $wsmanError = $_.Exception.Message.Trim() }
    }
    try { @{ Session = New-CimSession @common -SessionOption (New-CimSessionOption -Protocol Dcom); Protocol = 'DCOM' } }
    catch {
        # The WinRM error is usually the more meaningful one.
        throw (Tr 'WinRM : {0} | DCOM : {1}') -f $wsmanError, $_.Exception.Message.Trim()
    }
}

# The programs' entries in the registry's Uninstall keys, read on the computer itself, in one call (Invoke-Command,
# over WinRM), or here for this computer: the computer's (64-bit and 32-bit) and those of the users whose session is
# open. Each a Scope (Computer or User) and the values the list reads, as text ($null when not set). Windows
# PowerShell 5.1 runs it too.
$script:UninstallEntryReader = {
    $uninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $roots = @(
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = $uninstall; Scope = 'Computer' }
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Computer' }
    )
    foreach ($sid in [Microsoft.Win32.Registry]::Users.GetSubKeyNames()) {
        if ($sid -match '^S-1-5-21-[\d-]+$') { $roots += @{ Hive = [Microsoft.Win32.Registry]::Users; Path = "$sid\$uninstall"; Scope = 'User' } }
    }
    foreach ($root in $roots) {
        # A user's key may not be readable: the others still are.
        $parent = try { $root.Hive.OpenSubKey($root.Path) } catch { $null }
        if (-not $parent) { continue }
        foreach ($name in $parent.GetSubKeyNames()) {
            $key = try { $parent.OpenSubKey($name) } catch { $null }
            if (-not $key) { continue }
            $entry = [ordered]@{ Scope = $root.Scope }
            foreach ($value in 'DisplayName', 'DisplayVersion', 'Publisher', 'InstallDate', 'SystemComponent', 'ParentKeyName') {
                $read = $key.GetValue($value)
                $entry[$value] = if ($null -ne $read) { "$read".Trim() } else { $null }
            }
            $key.Close()
            [pscustomobject]$entry
        }
        $parent.Close()
    }
}

function ConvertFrom-PCInstallDate($Value) {
    # An Uninstall entry's InstallDate as a [datetime], or $null when it isn't surely one: rather nothing than a wrong
    # date. Windows writes yyyyMMdd (20240815), as text or as a number; some installers write yyyy-MM-dd, or the date in
    # their own locale's form (15/08/2024, 8/15/2024), read only when the day and the month can't be swapped (one of
    # them over 12, or both the same). A date that doesn't exist (20241399), or before 1980 (0, 19700101: a default
    # value), is none.
    $text = "$Value".Trim()
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $date = [datetime]::MinValue
    $read = if ($text -match '^\d{8}$') {
        [datetime]::TryParseExact($text, 'yyyyMMdd', $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$date)
    }
    elseif ($text -match '^\d{4}-\d{2}-\d{2}$') {
        [datetime]::TryParseExact($text, 'yyyy-MM-dd', $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$date)
    }
    elseif ($text -match '^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$') {
        $first = [int]$Matches[1]
        $second = [int]$Matches[2]
        $year = [int]$Matches[3]
        $day, $month = if ($first -eq $second -or ($first -gt 12 -and $second -le 12)) { $first, $second }
        elseif ($second -gt 12 -and $first -le 12) { $second, $first }
        else { 0, 0 }
        if ($year -ge 1980 -and $day -ge 1 -and $month -ge 1 -and $month -le 12 -and $day -le [datetime]::DaysInMonth($year, $month)) {
            $date = [datetime]::new($year, $month, $day)
            $true
        }
        else { $false }
    }
    else { $false }
    if ($read -and $date.Year -ge 1980) { $date } else { $null }
}

function ConvertTo-PCSoftware($Entries) {
    # Logiciels, from the Uninstall entries (Get-PCSpec): without system components, updates of other programs and
    # entries without a name, as Windows lists them; a program in both the 64-bit and 32-bit keys, or installed for two
    # users, once. InstallDate is yyyy-MM-dd, for sorting and the JSON export, or empty; InstallDateText is how Repère
    # shows dates (Format-TextDate), in the grid and what's copied from it.
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $programs = foreach ($entry in @($Entries)) {
        if (-not $entry.DisplayName -or $null -ne $entry.ParentKeyName -or $entry.SystemComponent -eq '1') { continue }
        $installed = ConvertFrom-PCInstallDate $entry.InstallDate
        [pscustomobject]@{
            Name            = $entry.DisplayName
            Version         = $entry.DisplayVersion
            Publisher       = $entry.Publisher
            InstallDate     = if ($installed) { $installed.ToString('yyyy-MM-dd', $invariant) } else { '' }
            InstallDateText = if ($installed) { Format-TextDate $installed -Day } else { '' }
            Scope           = if ($entry.Scope -eq 'User') { Tr 'Utilisateur' } else { Tr 'Ordinateur' }
        }
    }
    $programs = @($programs | Sort-Object Name, Version, Scope -Unique)
    [pscustomobject]@{
        Programs = $programs
        Count    = if ($programs.Count -eq 1) { Tr '1 logiciel' } else { (Tr '{0} logiciels') -f $programs.Count }
        List     = if ($programs.Count) { ($programs | ForEach-Object { (@($_.Name, $_.Version, $(if ($_.Publisher) { "($($_.Publisher))" })) | Where-Object { $_ }) -join ' ' }) -join "`n" } else { Tr 'Aucun' }
    }
}

function ConvertTo-PCBatteryHealth($Full, $Static, $Portable) {
    # Santé (Text) and its % (Percent, $null when unknown), from root\wmi's BatteryFullChargedCapacity and
    # BatteryStaticData, matched by InstanceName and added up when there are two batteries. Many firmwares answer « Not
    # supported » to BatteryStaticData, or a DesignedCapacity of 0: the original capacity from SMBIOS
    # (Win32_PortableBattery) instead. Without it, the full charge alone; so too for a % no battery has (units mixed up).
    $charged = @($Full | Where-Object { $_ -and $_.FullChargedCapacity -gt 0 })
    if (-not $charged.Count) { return [pscustomobject]@{ Text = Tr 'N/D'; Percent = $null } }
    $designs = @{}
    foreach ($instance in @($Static | Where-Object { $_ -and $_.DesignedCapacity -gt 0 })) { $designs["$($instance.InstanceName)"] = [double]$instance.DesignedCapacity }
    $fullTotal = [double]($charged | Measure-Object FullChargedCapacity -Sum).Sum
    $designTotal = 0
    if (@($charged | Where-Object { $designs.ContainsKey("$($_.InstanceName)") }).Count -eq $charged.Count) {
        foreach ($instance in $charged) { $designTotal += $designs["$($instance.InstanceName)"] }
    }
    else {
        $smbios = @($Portable | Where-Object { $_ -and $_.DesignCapacity -gt 0 })
        if ($smbios.Count -eq $charged.Count) { $designTotal = [double]($smbios | Measure-Object DesignCapacity -Sum).Sum }
    }
    $percent = if ($designTotal -gt 0) { [math]::Round($fullTotal / $designTotal * 100) }
    if ($null -eq $percent -or $percent -lt 1 -or $percent -gt 150) {
        return [pscustomobject]@{ Text = (Tr '{0:N0} mWh (capacité d''origine inconnue)') -f $fullTotal; Percent = $null }
    }
    [pscustomobject]@{ Text = (Tr '{0:N0} % ({1:N0} / {2:N0} mWh)') -f $percent, $fullTotal, $designTotal; Percent = $percent }
}

function Test-PCMobileChassis($ChassisTypes, $PCSystemType) {
    # Whether the computer is a laptop ($true), a desktop or a server ($false), or $null when Windows doesn't say. First
    # its enclosure's chassis types (SMBIOS, Win32_SystemEnclosure), which its maker sets: 8 Portable, 9 Laptop,
    # 10 Notebook, 11 Hand Held, 14 Sub Notebook, 30 Tablet, 31 Convertible and 32 Detachable are mobile; the desktop,
    # tower, all-in-one, mini PC and rack types aren't. When they say neither (1 Other and 2 Unknown, as virtual machines
    # and many custom-built computers say), Windows' power profile (Win32_ComputerSystem.PCSystemType, from ACPI):
    # 2 Mobile and 8 Slate are mobile, 1 Desktop, 3 Workstation and the servers' and appliances' aren't, 0 says nothing.
    $types = @($ChassisTypes | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
    if (@($types | Where-Object { $_ -in 8, 9, 10, 11, 14, 30, 31, 32 }).Count) { return $true }
    if (@($types | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 34, 35, 36 }).Count) { return $false }
    $powerProfile = "$PCSystemType"
    if ($powerProfile -in '2', '8') { return $true }
    if ($powerProfile -in '1', '3', '4', '5', '6', '7') { return $false }
    $null
}

function ConvertTo-PCDock($Devices, [scriptblock]$ReadDriver) {
    # Station d'accueil, from the PnP devices on USB (Win32_PnPEntity): whether a dock is connected (Connected, Status),
    # its model, firmware and driver, and the devices that show it (Devices). ReadDriver: given the device that names the
    # dock, its driver's Version and Provider (Get-PCSpec asks the device itself); it may fail, which leaves N/D.
    #
    # What claims a dock, and what doesn't. Windows has no class that says « a dock is connected », so this is read from
    # the devices a dock brings, and a dock is claimed on strong evidence only:
    # - Only devices present now. Win32_PnPEntity also lists those seen before (Present false, or error 45, « not
    #   connected »): a laptop docked yesterday still has its dock's.
    # - Only devices on USB (DeviceID USB\…, USB4 too), where USB-C and Thunderbolt docks show theirs. The ACPI
    #   « Docking station » device some laptops' firmware declares says nothing reliable about a dock being there, so it
    #   is never taken for one.
    # - Strong: a device whose name has the word dock or docking, as docks name their audio, network or hub
    #   (« ThinkPad USB-C Dock Gen2 USB Audio », « HP USB-C Dock G5 »); or a USB id only docks use: Dell's 413C:B06E and
    #   413C:B06F, the hubs of its WD19 family's docks (as fwupd lists them), which Windows names as a generic hub.
    # - Hints, never a dock: devices docks often have, but other things too. A USB network adapter (a dongle's too) and a
    #   DisplayLink device (a USB display adapter's too). Without strong evidence, they're listed as hints, so an
    #   unknown dock still shows what's detectable, and the status says no dock is recognized rather than none.
    # Model: the names that say dock, without their part's suffix (USB Audio, Ethernet, Hub…), else the maker of the
    # known id. Windows doesn't expose a dock's firmware version (its maker's tool reads it): the USB revision (bcdDevice)
    # of the device that names it is shown, as that; and the driver Windows loaded for it, the maker's or Windows' own.
    $value = { param($Object, [string]$Name) $property = $Object.PSObject.Properties[$Name]; if ($property) { $property.Value } }
    $knownIds = @{ '413C:B06E' = 'Dell'; '413C:B06F' = 'Dell' }
    $strong = [System.Collections.Generic.List[object]]::new()
    $hints = [System.Collections.Generic.List[object]]::new()
    foreach ($device in @($Devices)) {
        if (-not $device) { continue }
        $deviceId = "$(& $value $device 'DeviceID')"
        if ($deviceId -notmatch '^USB') { continue }
        if ((& $value $device 'Present') -eq $false -or "$(& $value $device 'ConfigManagerErrorCode')" -eq '45') { continue }
        $name = "$(& $value $device 'Name')".Trim()
        $id = if ($deviceId -match '^USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') { "$($Matches[1]):$($Matches[2])".ToUpperInvariant() } else { '' }
        $entry = [pscustomobject]@{ Device = $device; Name = $name; Id = $id; Named = $name -match '\bdock(ing)?\b' }
        if ($entry.Named -or ($id -and $knownIds.ContainsKey($id))) { $strong.Add($entry) }
        elseif ("$(& $value $device 'PNPClass')" -eq 'Net' -or $name -match 'DisplayLink' -or $id -like '17E9:*') { $hints.Add($entry) }
    }
    $notAvailable = Tr 'N/D'
    $label = { param($Entry) if ($Entry.Id) { "$($Entry.Name) (USB $($Entry.Id))" } else { $Entry.Name } }
    # The same device twice (a hub or an audio part has an entry per function or per port, with one name and one USB
    # id) is listed once, in the hints and the dock's devices alike.
    $seenHints = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $hints = @($hints | Where-Object { $seenHints.Add((& $label $_)) })
    if (-not $strong.Count) {
        $lines = if ($hints.Count) { @(Tr 'Indices seulement, pas la preuve d''une station :') + @($hints | ForEach-Object { '  ' + (& $label $_) }) }
        return [pscustomobject]@{
            Connected = $false
            Status    = if ($hints.Count) { Tr 'Aucune station reconnue' } else { Tr 'Aucune station détectée' }
            Model     = $notAvailable
            Firmware  = $notAvailable
            Driver    = $notAvailable
            Devices   = if ($lines) { $lines -join "`n" } else { Tr 'Aucun' }
        }
    }

    $named = @($strong | Where-Object Named)
    $main = if ($named.Count) { $named[0] } else { $strong[0] }
    $suffix = '\s+(USB\s+)?(Audio(\s+(Module|Headset|Device))?|(Gigabit\s+)?Ethernet(\s+Adapter)?|GbE|Hub|Billboard(\s+Device)?)$'
    $model = if ($named.Count) { Join-Unique @($named | ForEach-Object { $_.Name -replace $suffix, '' }) }
             else { (Tr 'Station {0} (modèle inconnu)') -f $knownIds[$main.Id] }
    # A USB hardware id ends with the device's revision, as BCD: REV_0102 is 01.02.
    $revision = @(& $value $main.Device 'HardwareID') | ForEach-Object { if ("$_" -match '&REV_([0-9A-F]{2})([0-9A-F]{2})') { "$($Matches[1]).$($Matches[2])" } } | Select-Object -First 1
    $driver = $notAvailable
    if ($ReadDriver) {
        try {
            $read = & $ReadDriver $main.Device
            if ($read -and $read.Version) {
                $driver = if ("$($read.Provider)" -match '^Microsoft') { (Tr 'Pilote standard de Windows ({0})') -f $read.Version }
                          elseif ($read.Provider) { '{0} ({1})' -f $read.Version, $read.Provider }
                          else { $read.Version }
            }
        }
        catch { Write-Verbose "Pilote de la station d'accueil : $_" }
    }
    [pscustomobject]@{
        Connected = $true
        Status    = Tr 'Connectée'
        Model     = $model
        Firmware  = if ($revision) { (Tr 'Non communiqué par Windows (révision USB {0})') -f $revision } else { Tr 'Non communiqué par Windows' }
        Driver    = $driver
        # A device that is the model alone (a dock with one part named) gives its USB id only: its name is the Modèle row.
        Devices   = (Get-UniqueText @($strong | ForEach-Object { if ($_.Id -and $_.Name -eq $model) { "USB $($_.Id)" } else { & $label $_ } })) -join "`n"
    }
}

function Test-PCSpecSectionShown([string]$Key, $Data, $Mobile, [bool]$Read = $true) {
    # Whether a section is shown, in the window and in the report (Copier, Exporter). All of them are, except Batterie
    # and Station d'accueil: a laptop's ($Mobile, General's), or another computer's when it has one (a battery, a dock
    # found), since a desktop's would only say it has none. Before they're read (-Read:$false), only a laptop's, so a
    # desktop's never shows and goes. One that couldn't be read is shown, its — saying so, unless the computer is surely
    # not a laptop.
    if ($Key -notin 'Battery', 'Dock') { return $true }
    if ($Mobile -eq $true) { return $true }
    if (-not $Read) { return $false }
    if (-not $Data) { return $Mobile -ne $false }
    if ($Key -eq 'Battery') { [bool]$Data.Present } else { [bool]$Data.Connected }
}

function Get-PCSpec {
    # The specs of a computer: General, Network, Processor, Memory, Disk, Monitor, Battery, Dock and Software, in the
    # order shown, each $null when it couldn't be read (its error is in Errors), plus Reachable, the Alerts and when they
    # were read. How long each took
    # (Timings, in ms, Connexion first), how it connected (Protocol: WinRM, DCOM or Local) and how the software was read
    # (SoftwareVia: WinRM in one call, Registry value by value, or Local). SectionQueue: each section is added to it as
    # soon as it's read (Name, Data, Error), so a window can show them one by one; « Connexion » first.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SectionQueue', Justification = 'Read by the $report script block.')]
    [CmdletBinding()]
    param(
        [string]$ComputerName = '.',
        [int]$TimeoutSeconds = 15,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$SectionQueue
    )
    Set-StrictMode -Version Latest

    $isLocal = Test-PCSpecsLocal $ComputerName
    $result = [ordered]@{
        Query     = $ComputerName
        Timestamp = Get-Date
        Reachable = $false
        Errors    = [ordered]@{}
        Alerts    = @()
        General   = $null
        Network   = $null
        Processor = $null
        Memory    = $null
        Disk      = $null
        Monitor   = $null
        Battery   = $null
        Dock      = $null
        Software  = $null
        Timings   = [ordered]@{}
        Protocol  = $null
        SoftwareVia = $null
    }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $report = {
        param([string]$Name, $Data, $ErrorText)
        if ($SectionQueue) { $SectionQueue.Enqueue([pscustomobject]@{ Name = $Name; Data = $Data; Error = $ErrorText }) }
    }

    $session = $null
    try {
        if ($isLocal) {
            $session = New-CimSession -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
            $result.Protocol = 'Local'
        }
        else {
            if (-not (Test-PCNameValid $ComputerName)) { throw (Tr "nom d'ordinateur invalide : '{0}'") -f $ComputerName }
            if ($ComputerName -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                try { $null = Resolve-DnsName -Name $ComputerName -QuickTimeout -ErrorAction Stop }
                catch { throw (Tr "nom '{0}' introuvable dans le DNS.") -f $ComputerName }
            }
            # Ping may be blocked while WinRM or DCOM works, so a failed ping alone isn't fatal.
            $pingOk = Test-Connection -TargetName $ComputerName -Count 1 -TimeoutSeconds 2 -Quiet -ErrorAction SilentlyContinue
            try {
                $connection = New-PCSpecsCimSession -Target $ComputerName -Timeout $TimeoutSeconds
                $session = $connection.Session
                $result.Protocol = $connection.Protocol
            }
            catch {
                $hint = if (-not $pingOk) { Tr "l'ordinateur semble hors ligne (pas de réponse au ping). " }
                        else { Tr "l'ordinateur répond au ping : vérifiez WinRM, le pare-feu et vos droits d'administrateur. " }
                throw "$hint$($_.Exception.Message)"
            }
        }
        $result.Reachable = $true
        $result.Timings.Connexion = $watch.ElapsedMilliseconds
        & $report 'Connexion' $null $null
    }
    catch {
        $result.Errors.Connexion = (Tr 'Impossible de joindre {0} : {1}') -f $ComputerName, $_.Exception.Message.Trim()
        $result.Timings.Connexion = $watch.ElapsedMilliseconds
        & $report 'Connexion' $null $result.Errors.Connexion
        return [pscustomobject]$result
    }

    function Invoke-Cim([string]$ClassName, [string]$Namespace = 'root\cimv2', [string]$Filter) {
        $parameters = @{ CimSession = $session; ClassName = $ClassName; Namespace = $Namespace; OperationTimeoutSec = $TimeoutSeconds; ErrorAction = 'Stop' }
        if ($Filter) { $parameters.Filter = $Filter }
        Get-CimInstance @parameters
    }

    function Invoke-Section([string]$Name, [scriptblock]$Script) {
        # Reads one section; its error is kept without stopping the others.
        $sectionWatch = [System.Diagnostics.Stopwatch]::StartNew()
        try { $result[$Name] = & $Script }
        catch { $result.Errors[$Name] = $_.Exception.Message.Trim() }
        $result.Timings[$Name] = $sectionWatch.ElapsedMilliseconds
        & $report $Name $result[$Name] $result.Errors[$Name]
    }

    try {
        Invoke-Section General {
            $cs = Invoke-Cim Win32_ComputerSystem | Select-Object -First 1
            $os = Invoke-Cim Win32_OperatingSystem | Select-Object -First 1
            $bios = try { Invoke-Cim Win32_BIOS | Select-Object -First 1 } catch { $null }
            $product = try { Invoke-Cim Win32_ComputerSystemProduct | Select-Object -First 1 } catch { $null }
            $serial = if ($bios) { Get-CleanValue $bios.SerialNumber } else { Tr 'N/D' }
            # Lenovo puts the model's friendly name in Win32_ComputerSystemProduct.Version.
            $model = Get-CleanValue $cs.Model
            if ($product -and $cs.Manufacturer -match 'LENOVO' -and $product.Version) { $model = "$($product.Version) ($($cs.Model))" }
            if ($model -eq (Tr 'N/D')) {
                # Custom-built computers: the motherboard's model.
                $board = try { Invoke-Cim Win32_BaseBoard | Select-Object -First 1 } catch { $null }
                if ($board) { $model = Get-CleanValue "$($board.Product)" }
            }
            # Win32_ComputerSystem.UserName is empty for Remote Desktop sessions: the owners of explorer.exe instead.
            $user = "$($cs.UserName)"
            if (-not $user) {
                try {
                    $owners = Invoke-Cim Win32_Process -Filter "Name = 'explorer.exe'" | ForEach-Object {
                        $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction Stop
                        if ($owner.User) { if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User } }
                    }
                    $user = Join-Unique $owners
                }
                catch { $user = Tr 'N/D' }
                if ($user -eq (Tr 'N/D')) { $user = Tr 'Aucun utilisateur connecté' }
            }

            $bootText = Tr 'N/D'
            if ($os.LastBootUpTime) {
                $up = (Get-Date) - $os.LastBootUpTime
                $ago = if ($up.TotalDays -ge 1) { (Tr '{0} j {1} h') -f [int][math]::Floor($up.TotalDays), $up.Hours }
                       elseif ($up.TotalHours -ge 1) { '{0} h {1} min' -f [int][math]::Floor($up.TotalHours), $up.Minutes }
                       else { '{0} min' -f [int][math]::Floor($up.TotalMinutes) }
                $bootText = (Tr '{0} (il y a {1})') -f (Format-TextDate $os.LastBootUpTime), $ago
            }

            # Whether it's a laptop, for Batterie and Station d'accueil, which a desktop doesn't show. One small class.
            $enclosures = try { @(Invoke-Cim Win32_SystemEnclosure) } catch { @() }
            $mobile = Test-PCMobileChassis @($enclosures | ForEach-Object { $_.ChassisTypes }) $cs.PCSystemType

            $biosText = Tr 'N/D'
            if ($bios) {
                $biosVersion = Get-CleanValue $bios.SMBIOSBIOSVersion
                $biosText = if ($bios.ReleaseDate) { '{0} ({1})' -f $biosVersion, (Format-TextDate $bios.ReleaseDate -Day) } else { $biosVersion }
            }

            [pscustomobject]@{
                ComputerName = $cs.Name
                LoggedOnUser = $user
                Bios         = $biosText
                LastBoot     = $bootText
                UptimeDays   = if ($os.LastBootUpTime) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1) } else { $null }
                Build        = [int]$os.BuildNumber
                SerialNumber = $serial
                OSType       = "Windows $($os.OSArchitecture)"
                SKU          = Get-CleanValue $cs.SystemSKUNumber
                OSName       = ($os.Caption -replace '^Microsoft\s+', '')
                BuildNumber  = "$($os.Version) (build $($os.BuildNumber))"
                Manufacturer = Get-CleanValue $cs.Manufacturer
                Model        = $model
                # $true for a laptop or a tablet, $false for a desktop or a server, $null when Windows doesn't say.
                Mobile       = $mobile
            }
        }

        Invoke-Section Network {
            $ipv4 = '^\d{1,3}(\.\d{1,3}){3}$'
            $configs = @(Invoke-Cim Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' |
                Where-Object { $_.IPAddress | Where-Object { $_ -match $ipv4 -and $_ -notlike '169.254.*' } })
            $cs = Invoke-Cim Win32_ComputerSystem | Select-Object -First 1

            # Each adapter's name, medium and link speed, by InterfaceIndex.
            $adapters = @{}
            try {
                foreach ($adapter in Invoke-Cim MSFT_NetAdapter -Namespace 'root\StandardCimv2') {
                    $medium = switch ([int]$adapter.NdisPhysicalMedium) {
                        14 { 'Ethernet' } 9 { 'Wi-Fi' } 10 { 'Bluetooth' } 8 { Tr 'Cellulaire' }
                        default { if ($adapter.Virtual) { Tr 'Virtuelle' } else { Tr 'Autre' } }
                    }
                    $adapters[[int]$adapter.InterfaceIndex] = [pscustomobject]@{
                        Name = $adapter.Name; Description = $adapter.InterfaceDescription; Medium = $medium
                        Speed = [double]$adapter.ReceiveLinkSpeed; Virtual = [bool]$adapter.Virtual
                    }
                }
            }
            catch {
                # Older systems: Win32_NetworkAdapter is less precise but always there.
                foreach ($adapter in Invoke-Cim Win32_NetworkAdapter -Filter 'NetEnabled = TRUE') {
                    $medium = if ($adapter.Name -match 'Wi-?Fi|Wireless|802\.11|WLAN') { 'Wi-Fi' }
                              elseif ($adapter.PhysicalAdapter) { 'Ethernet' } else { Tr 'Virtuelle' }
                    $adapters[[int]$adapter.InterfaceIndex] = [pscustomobject]@{
                        Name = $adapter.NetConnectionID; Description = $adapter.Name; Medium = $medium
                        Speed = [double]$adapter.Speed; Virtual = -not $adapter.PhysicalAdapter
                    }
                }
            }

            $formatSpeed = {
                param([double]$BitsPerSecond)
                if ($BitsPerSecond -le 0) { return $null }
                if ($BitsPerSecond -ge 1e9) { '{0:0.#} Gbit/s' -f ($BitsPerSecond / 1e9) } else { '{0:N0} Mbit/s' -f ($BitsPerSecond / 1e6) }
            }

            # The main adapter: the one with a default gateway, physical before virtual, then the lowest metric.
            $ranked = @($configs | Sort-Object @{ Expression = { -not $_.DefaultIPGateway } },
                                               @{ Expression = { $a = $adapters[[int]$_.InterfaceIndex]; [bool]($a -and $a.Virtual) } },
                                               @{ Expression = { [int]$_.IPConnectionMetric } })
            $primary = $ranked | Select-Object -First 1
            $primaryAdapter = if ($primary) { $adapters[[int]$primary.InterfaceIndex] } else { $null }

            # The other adapters' addresses say which adapter they belong to.
            $ipLines = foreach ($config in $ranked) {
                $ips = @($config.IPAddress | Where-Object { $_ -match $ipv4 })
                $adapter = $adapters[[int]$config.InterfaceIndex]
                $label = if ($adapter) { $adapter.Name } else { $config.Description }
                if ($config -eq $primary) { $ips -join ', ' } else { "$($ips -join ', ') ($label)" }
            }

            $adapterText = Tr 'N/D'
            $link = Tr 'N/D'
            if ($primary) {
                $adapterText = if ($primaryAdapter) { "$($primaryAdapter.Name) — $($primaryAdapter.Description)" } else { $primary.Description }
                if ($primaryAdapter) { $link = Join-Unique @($primaryAdapter.Medium, (& $formatSpeed $primaryAdapter.Speed)) ' · ' }
            }

            $fqdn = if ($cs.PartOfDomain -and $cs.DNSHostName) { "$($cs.DNSHostName).$($cs.Domain)" } else { $cs.DNSHostName }
            [pscustomobject]@{
                IPAddress = if ($ipLines) { @($ipLines) -join "`n" } else { Tr 'N/D' }
                Adapter   = $adapterText
                LinkType  = $link
                MAC       = if ($primary -and $primary.MACAddress) { $primary.MACAddress } else { Tr 'N/D' }
                DNS       = if ($primary) { Join-Unique ($primary.DNSServerSearchOrder) "`n" } else { Tr 'N/D' }
                FQDN      = if ($fqdn) { $fqdn } else { Tr 'N/D' }
                Domain    = if ($cs.PartOfDomain) { $cs.Domain } else { (Tr '{0} (groupe de travail)') -f $cs.Domain }
            }
        }

        Invoke-Section Processor {
            $cpus = @(Invoke-Cim Win32_Processor)
            if (-not $cpus.Count) { throw (Tr 'aucun processeur retourné.') }
            $first = $cpus[0]
            $cores = ($cpus | Measure-Object NumberOfCores -Sum).Sum
            $threads = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
            $architecture = switch ($first.Architecture) { 0 { 'x86' } 5 { 'ARM' } 9 { 'x64' } 12 { 'ARM64' } default { (Tr 'Inconnue ({0})') -f $first.Architecture } }
            $l3 = ($cpus | Measure-Object L3CacheSize -Sum).Sum
            # Only what the other rows don't say: the sockets when there are several, the current speed when it isn't
            # the base speed. Otherwise the row is left out, as the maker's when the model names it.
            $extra = @()
            if ($cpus.Count -gt 1) { $extra += ((Tr 'Sockets : {0}') -f $cpus.Count) }
            if ($first.CurrentClockSpeed -and $first.CurrentClockSpeed -ne $first.MaxClockSpeed) { $extra += ((Tr 'Actuelle : {0:N2} GHz') -f ($first.CurrentClockSpeed / 1000)) }
            $model = Format-PCCpuName $first.Name ([bool]$first.MaxClockSpeed)
            [pscustomobject]@{
                Name         = $model
                Vendor       = Get-PCCpuVendor $first.Manufacturer $model
                Architecture = $architecture
                Cores        = "$cores / $threads"
                BaseClock    = if ($first.MaxClockSpeed) { '{0:N2} GHz' -f ($first.MaxClockSpeed / 1000) } else { Tr 'N/D' }
                L3Cache      = if ($l3 -gt 0) { if ($l3 -ge 1024) { (Tr '{0:N0} Mo') -f ($l3 / 1024) } else { (Tr '{0} Ko') -f $l3 } } else { Tr 'N/D' }
                Extra        = if ($extra) { $extra -join ' · ' }
            }
        }

        Invoke-Section Memory {
            $modules = @(Invoke-Cim Win32_PhysicalMemory)
            if (-not $modules.Count) { throw (Tr 'aucun module mémoire retourné.') }
            $total = ($modules | Measure-Object Capacity -Sum).Sum
            $typeNames = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 35 = 'LPDDR5' }
            $types = $modules | ForEach-Object {
                $type = [int]$_.SMBIOSMemoryType
                if ($typeNames.ContainsKey($type)) { $typeNames[$type] } elseif ($type -in 0, 2) { $null } else { "Type $type" }
            }
            $speeds = $modules | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Where-Object { $_ }
            $layout = ($modules | Group-Object Capacity | ForEach-Object { "$($_.Count) × $(Format-Byte ([double]$_.Name))" }) -join ' + '
            $made = ConvertTo-PCMemory $modules
            [pscustomobject]@{
                Total    = Format-Byte $total
                Speed    = if ($speeds) { "$(Join-Unique $speeds ' / ') MT/s" } else { Tr 'N/D' }
                Type     = Join-Unique $types
                Physical = $layout
                Maker    = $made.Maker
                Part     = $made.Part
            }
        }

        Invoke-Section Disk {
            $storage = 'root\Microsoft\Windows\Storage'
            $systemDrive = (Invoke-Cim Win32_OperatingSystem | Select-Object -First 1).SystemDrive

            # Fixed volumes (C:, D:…) and how full they are.
            $volumes = @(Invoke-Cim Win32_LogicalDisk -Filter 'DriveType = 3' | Sort-Object DeviceID | ForEach-Object {
                $size = [double]$_.Size
                $free = [double]$_.FreeSpace
                $percent = if ($size -gt 0) { [math]::Round((($size - $free) / $size) * 100) } else { 0 }
                [pscustomobject]@{
                    Drive       = $_.DeviceID
                    Label       = "$($_.VolumeName)"
                    IsSystem    = $_.DeviceID -eq $systemDrive
                    Size        = $size
                    Free        = $free
                    UsedPercent = $percent
                    Text        = (Tr '{0} / {1} · {2} libres ({3} %)') -f (Format-Byte ($size - $free)), (Format-Byte $size), (Format-Byte $free), $percent
                }
            })

            # Physical disks, and which volume is on which disk.
            $mediaTypes = @{ 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
            $busTypes = @{ 3 = 'ATA'; 7 = 'USB'; 8 = 'RAID'; 10 = 'SAS'; 11 = 'SATA'; 17 = 'NVMe'; 16 = 'Storage Spaces' }
            $drives = @()
            $diskOfVolume = @{}
            try {
                foreach ($partition in Invoke-Cim MSFT_Partition -Namespace $storage) {
                    $letter = "$($partition.DriveLetter)".Trim([char]0, ' ')
                    if ($letter) { $diskOfVolume["$($letter):"] = "$($partition.DiskNumber)" }
                }
                $drives = @(Invoke-Cim MSFT_PhysicalDisk -Namespace $storage | ForEach-Object {
                    [pscustomobject]@{
                        Number = "$($_.DeviceId)"
                        Model  = "$($_.FriendlyName)".Trim()
                        Size   = [double]$_.Size
                        Tech   = Join-Unique @($mediaTypes[[int]$_.MediaType], $busTypes[[int]$_.BusType]) ' '
                    }
                })
            }
            catch { $drives = @() }
            if (-not $drives.Count) {
                # Storage namespace unavailable (old Windows, rights): the disks, without their volumes.
                $drives = @(Invoke-Cim Win32_DiskDrive | ForEach-Object {
                    [pscustomobject]@{ Number = "$($_.Index)"; Model = "$($_.Model)".Trim(); Size = [double]$_.Size; Tech = Get-CleanValue $_.InterfaceType }
                })
            }
            if (-not $drives.Count -and -not $volumes.Count) { throw (Tr 'aucun disque retourné.') }

            $drives = @($drives | ForEach-Object {
                $number = $_.Number
                $onDisk = @($volumes | Where-Object { $diskOfVolume[$_.Drive] -eq $number })
                $_ | Add-Member -NotePropertyMembers @{
                    Volumes  = $onDisk
                    IsSystem = [bool]($onDisk | Where-Object IsSystem)
                    SizeText = Format-Byte $_.Size
                } -PassThru
            } | Sort-Object @{ Expression = { -not $_.IsSystem } }, @{ Expression = { [int]$_.Number } })

            # Volumes that couldn't be placed on a disk are still shown.
            $orphans = @($volumes | Where-Object { -not $diskOfVolume.ContainsKey($_.Drive) })
            if ($orphans.Count) {
                $drives += [pscustomobject]@{
                    Number = ''; Model = 'Volumes'; Size = 0; Tech = ''; Volumes = $orphans
                    IsSystem = [bool]($orphans | Where-Object IsSystem); SizeText = ''
                }
            }

            $size = ($volumes | Measure-Object Size -Sum).Sum
            $free = ($volumes | Measure-Object Free -Sum).Sum
            $details = foreach ($drive in $drives) {
                $flags = Join-Unique @($drive.Tech, $(if ($drive.IsSystem) { Tr 'système' })) ', '
                $head = if ($drive.SizeText) { "$($drive.Model) — $($drive.SizeText)" } else { $drive.Model }
                if ($flags -ne (Tr 'N/D')) { $head += " ($flags)" }
                $head
                foreach ($volume in $drive.Volumes) { "  $($volume.Drive) $($volume.Text)" }
            }

            [pscustomobject]@{
                Drives    = $drives
                DiskCount = @($drives | Where-Object Number).Count
                Storage   = if ($size -gt 0) { (Tr '{0} (utilisé {1} / libre {2})') -f (Format-Byte $size), (Format-Byte ($size - $free)), (Format-Byte $free) } else { Tr 'N/D' }
                Details   = $details -join "`n"
            }
        }

        Invoke-Section Monitor {
            # The monitors connected now (a laptop's own screen too), as their EDID tells Windows (root\wmi): the
            # manufacturer's code, the model, the serial number, the size in cm (shown as a diagonal in inches), and the
            # preferred mode, which is the screen's native resolution. A monitor no longer connected isn't Active.
            $wmi = 'root\wmi'
            $ids = @(Invoke-Cim WmiMonitorID -Namespace $wmi | Where-Object { $_.Active -ne $false })
            # The details, by monitor: one class that can't be read only leaves its values N/D.
            $byInstance = {
                param([string]$Class)
                $table = @{}
                try { foreach ($item in @(Invoke-Cim $Class -Namespace $wmi)) { $table["$($item.InstanceName)"] = $item } } catch { Write-Verbose "$($Class) : $_" }
                $table
            }
            $sizes = & $byInstance WmiMonitorBasicDisplayParams
            $modes = & $byInstance WmiMonitorListedSupportedSourceModes
            $links = & $byInstance WmiMonitorConnectionParams
            # EDID text: UTF-16 codes, padded with zeros.
            $decode = { param($Codes) (-join @($Codes | Where-Object { $_ } | ForEach-Object { [char][int]$_ })).Trim() }
            # The PNP codes of the usual makers; another shows as it is.
            $makers = @{
                ACI = 'Asus'; ACR = 'Acer'; AOC = 'AOC'; APP = 'Apple'; AUO = 'AU Optronics'; AUS = 'Asus'; BNQ = 'BenQ'; BOE = 'BOE'
                CMN = 'Innolux'; CMO = 'Chi Mei'; DEL = 'Dell'; ENC = 'Eizo'; FUS = 'Fujitsu'; GBT = 'Gigabyte'; GSM = 'LG'; HKC = 'HKC'
                HPN = 'HP'; HSD = 'HannStar'; HWP = 'HP'; IVM = 'Iiyama'; IVO = 'InfoVision'; LEN = 'Lenovo'; LGD = 'LG Display'
                MEI = 'Panasonic'; MSI = 'MSI'; NEC = 'NEC'; PHL = 'Philips'; SAM = 'Samsung'; SDC = 'Samsung Display'; SHP = 'Sharp'
                SNY = 'Sony'; VSC = 'ViewSonic'
            }
            $monitors = @(foreach ($id in $ids) {
                $instance = "$($id.InstanceName)"
                $code = & $decode $id.ManufacturerName
                $maker = if ($makers.ContainsKey($code)) { $makers[$code] } elseif ($code) { $code } else { Tr 'N/D' }
                # VideoOutputTechnology: how it's connected. 6, 11 and 13 (and the internal flag, 0x80000000) are a
                # laptop's own screen.
                $technology = if ($links.ContainsKey($instance)) { [int64]$links[$instance].VideoOutputTechnology } else { -1 }
                $internal = $technology -in 6, 11, 13, 2147483648
                $connection = if ($internal) { Tr 'Intégré' }
                              else { switch ($technology) { 0 { 'VGA' } 4 { 'DVI' } 5 { 'HDMI' } 10 { 'DisplayPort' } 12 { 'UDI' } 15 { 'Miracast' } 16 { Tr 'Indirect (USB)' } default { '' } } }
                # Its name as the monitor gives it, else its product code (a laptop's own screen often has no name),
                # after its maker unless the name starts with it.
                $friendly = & $decode $id.UserFriendlyName
                $model = if ($friendly) { $friendly } else { & $decode $id.ProductCodeID }
                $name = if ($maker -eq (Tr 'N/D') -or $model -like "$maker*") { $model } else { "$maker $model".Trim() }
                $size = Tr 'N/D'
                if ($sizes.ContainsKey($instance)) {
                    # In whole centimeters: the diagonal is close, not exact (15,6 po reads as about 15).
                    $width = [double]$sizes[$instance].MaxHorizontalImageSize
                    $height = [double]$sizes[$instance].MaxVerticalImageSize
                    if ($width -gt 0 -and $height -gt 0) { $size = (Tr '≈ {0:N0} po ({1} × {2} cm)') -f ([Math]::Sqrt($width * $width + $height * $height) / 2.54), $width, $height }
                }
                $resolution = Tr 'N/D'
                if ($modes.ContainsKey($instance)) {
                    $list = @($modes[$instance].MonitorSourceModes)
                    $index = [int]$modes[$instance].PreferredMonitorSourceModeIndex
                    if ($index -ge 0 -and $index -lt $list.Count) { $resolution = '{0} × {1}' -f $list[$index].HorizontalActivePixels, $list[$index].VerticalActivePixels }
                }
                [pscustomobject]@{
                    Instance     = $instance
                    Name         = $name
                    Manufacturer = $maker
                    Model        = if ($model) { $model } else { Tr 'N/D' }
                    Serial       = Get-CleanValue (& $decode $id.SerialNumberID)
                    Size         = $size
                    Resolution   = $resolution
                    Connection   = $connection
                    Internal     = $internal
                }
            })
            # The laptop's own screen first, then as Windows numbers them.
            $monitors = @($monitors | Sort-Object @{ Expression = { -not $_.Internal } }, Instance)
            $details = foreach ($monitor in $monitors) {
                if ($monitor.Connection) { "$($monitor.Name) — $($monitor.Connection)" } else { $monitor.Name }
                '  ' + ((Tr 'Taille : {0}') -f $monitor.Size)
                '  ' + ((Tr 'Résolution native : {0}') -f $monitor.Resolution)
                '  ' + ((Tr 'Numéro de série : {0}') -f $monitor.Serial)
            }
            [pscustomobject]@{
                Monitors = $monitors
                Count    = switch ($monitors.Count) { 0 { Tr 'Aucun écran détecté' } 1 { Tr '1 écran' } default { (Tr '{0} écrans') -f $monitors.Count } }
                Details  = if ($monitors.Count) { $details -join "`n" } else { Tr 'Aucun' }
            }
        }

        Invoke-Section Battery {
            $batteries = @(Invoke-Cim Win32_Battery)
            if (-not $batteries.Count) {
                return [pscustomobject]@{ Present = $false; Capacity = Tr 'Aucune batterie'; Health = Tr 'N/D'; HealthPercent = $null; PowerStatus = Tr 'Secteur'; Cycles = Tr 'N/D' }
            }
            $statuses = @{
                1 = Tr 'Sur batterie'; 2 = Tr 'Secteur'; 3 = Tr 'Chargée'; 4 = Tr 'Faible'; 5 = Tr 'Critique'; 6 = Tr 'En charge'
                7 = Tr 'En charge (élevée)'; 8 = Tr 'En charge (faible)'; 9 = Tr 'En charge (critique)'; 11 = Tr 'Partiellement chargée'
            }
            $battery = $batteries[0]
            # Each class on its own: one the firmware doesn't support leaves the others.
            $full = try { @(Invoke-Cim BatteryFullChargedCapacity -Namespace 'root\wmi') } catch { @() }
            $static = try { @(Invoke-Cim BatteryStaticData -Namespace 'root\wmi') } catch { @() }
            $portable = try { @(Invoke-Cim Win32_PortableBattery) } catch { @() }
            $health = ConvertTo-PCBatteryHealth $full $static $portable
            # Many firmwares report 0 or 0xFFFFFFFF when they don't count cycles.
            $counts = try { @(Invoke-Cim BatteryCycleCount -Namespace 'root\wmi') } catch { @() }
            $count = $counts | Where-Object { $_ -and $_.CycleCount -gt 0 -and $_.CycleCount -lt 100000 } | Select-Object -First 1
            $cycles = if ($count) { "$($count.CycleCount)" } else { Tr 'N/D' }
            [pscustomobject]@{
                Present       = $true
                Capacity      = (Tr '{0} %') -f $battery.EstimatedChargeRemaining
                Health        = $health.Text
                HealthPercent = $health.Percent
                PowerStatus   = if ($statuses.ContainsKey([int]$battery.BatteryStatus)) { $statuses[[int]$battery.BatteryStatus] } else { (Tr 'Statut {0}') -f $battery.BatteryStatus }
                Cycles        = $cycles
            }
        }

        Invoke-Section Dock {
            # The devices Windows sees on USB (where USB-C and Thunderbolt docks show theirs too), in one query that
            # leaves out the hundreds of others; ConvertTo-PCDock tells a dock from them. The driver of the device that
            # names the dock is asked for alone, through the device itself: the class of signed drivers would be listed
            # whole, which takes seconds.
            $devices = @(Invoke-Cim Win32_PnPEntity -Filter "DeviceID LIKE 'USB%'")
            ConvertTo-PCDock $devices {
                param($Device)
                $keys = [string[]]@('DEVPKEY_Device_DriverVersion', 'DEVPKEY_Device_DriverProvider')
                $answer = Invoke-CimMethod -InputObject $Device -MethodName GetDeviceProperties -Arguments @{ devicePropertyKeys = $keys } -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
                $properties = @{}
                foreach ($property in @($answer.deviceProperties)) { if ($property) { $properties["$($property.KeyName)"] = "$($property.Data)".Trim() } }
                @{ Version = $properties['DEVPKEY_Device_DriverVersion']; Provider = $properties['DEVPKEY_Device_DriverProvider'] }
            }
        }

        Invoke-Section Software {
            # The programs « Applications installées » lists: the Uninstall keys of the computer (64-bit and 32-bit) and
            # of the users whose session is open ($UninstallEntryReader, ConvertTo-PCSoftware). Read on the computer in
            # one call when WinRM answers (or here for this computer). Otherwise, or when that call fails (PowerShell's
            # remoting refused), through StdRegProv, which works over DCOM too, one call per key and value: a few
            # hundred calls, so seconds rather than a fraction of one.
            $entries = $null
            if ($result.Protocol -eq 'Local') {
                $entries = @(& $script:UninstallEntryReader)
                $result.SoftwareVia = 'Local'
            }
            elseif ($result.Protocol -eq 'WinRM') {
                try {
                    $option = New-PSSessionOption -OpenTimeout ($TimeoutSeconds * 1000) -OperationTimeout 120000
                    $entries = @(Invoke-Command -ComputerName $ComputerName -ScriptBlock $script:UninstallEntryReader -SessionOption $option -ErrorAction Stop)
                    $result.SoftwareVia = 'WinRM'
                }
                catch { Write-Verbose "Logiciels lus par le registre à distance ($ComputerName) : $_" }
            }
            if ($null -eq $entries) {
                $result.SoftwareVia = 'Registry'
                $hklm = [uint32]2147483650
                $hku = [uint32]2147483651
                $uninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
                $registry = {
                    param([string]$Method, [hashtable]$Arguments)
                    $answer = Invoke-CimMethod -CimSession $session -Namespace 'root\cimv2' -ClassName StdRegProv -MethodName $Method -Arguments $Arguments -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
                    # 2: the key or value doesn't exist (no 32-bit programs, say), which isn't an error.
                    if ($answer.ReturnValue -notin 0, 2) { throw (Tr 'registre illisible ({0}, code {1}).') -f $Method, $answer.ReturnValue }
                    $answer
                }
                $roots = @(
                    @{ Hive = $hklm; Path = $uninstall; Scope = 'Computer' }
                    @{ Hive = $hklm; Path = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Computer' }
                )
                foreach ($sid in @((& $registry EnumKey @{ hDefKey = $hku; sSubKeyName = '' }).sNames)) {
                    if ($sid -match '^S-1-5-21-[\d-]+$') { $roots += @{ Hive = $hku; Path = "$sid\$uninstall"; Scope = 'User' } }
                }
                $entries = @(foreach ($root in $roots) {
                    foreach ($key in @((& $registry EnumKey @{ hDefKey = $root.Hive; sSubKeyName = $root.Path }).sNames)) {
                        if (-not $key) { continue }
                        $path = "$($root.Path)\$key"
                        # One call lists a key's values, then only those it has are read, and none of a key the list
                        # leaves out anyway.
                        $values = & $registry EnumValues @{ hDefKey = $root.Hive; sSubKeyName = $path }
                        $types = @{}
                        if ($values.sNames) { for ($i = 0; $i -lt $values.sNames.Count; $i++) { $types[$values.sNames[$i]] = $values.Types[$i] } }
                        if (-not $types.ContainsKey('DisplayName') -or $types.ContainsKey('ParentKeyName')) { continue }
                        # Each value read by the method of its type, as text: some installers write SystemComponent as
                        # text, or a date as a number, and reading it as another type fails (type mismatch, 2147749893).
                        $read = {
                            param([string]$Name)
                            $method, $property = switch ($types[$Name]) {
                                1 { 'GetStringValue', 'sValue' }
                                2 { 'GetExpandedStringValue', 'sValue' }
                                4 { 'GetDWORDValue', 'uValue' }
                                11 { 'GetQWORDValue', 'uValue' }
                            }
                            if ($method) { "$((& $registry $method @{ hDefKey = $root.Hive; sSubKeyName = $path; sValueName = $Name }).$property)".Trim() }
                        }
                        $system = & $read SystemComponent
                        if ($system -eq '1') { continue }
                        [pscustomobject]@{
                            Scope = $root.Scope; DisplayName = & $read DisplayName; DisplayVersion = & $read DisplayVersion; Publisher = & $read Publisher
                            InstallDate = & $read InstallDate; SystemComponent = $system; ParentKeyName = $null
                        }
                    }
                })
            }
            ConvertTo-PCSoftware $entries
        }
    }
    finally {
        if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }
    }

    $result.Alerts = @(Get-PCSpecAlert $result)
    [pscustomobject]$result
}

# Each Windows build's release and end of servicing (Home and Pro, then Enterprise and Education), from
# learn.microsoft.com/windows/release-health: to update when new versions ship. Used by the alerts and by the results'
# Système column.
$script:WindowsReleases = @{
    19044 = @{ Name = 'Windows 10 21H2'; Pro = [datetime]'2023-06-13'; Ent = [datetime]'2024-06-11' }
    19045 = @{ Name = 'Windows 10 22H2'; Pro = [datetime]'2025-10-14'; Ent = [datetime]'2025-10-14' }
    22000 = @{ Name = 'Windows 11 21H2'; Pro = [datetime]'2023-10-10'; Ent = [datetime]'2024-10-08' }
    22621 = @{ Name = 'Windows 11 22H2'; Pro = [datetime]'2024-10-08'; Ent = [datetime]'2025-10-14' }
    22631 = @{ Name = 'Windows 11 23H2'; Pro = [datetime]'2025-11-11'; Ent = [datetime]'2026-11-10' }
    26100 = @{ Name = 'Windows 11 24H2'; Pro = [datetime]'2026-10-13'; Ent = [datetime]'2027-10-12' }
    26200 = @{ Name = 'Windows 11 25H2'; Pro = [datetime]'2027-10-12'; Ent = [datetime]'2028-10-10' }
}

function Get-WindowsRelease([int]$Build, [string]$OSName) {
    # A client Windows build's release name (Windows 11 24H2) and end of support for its edition, or $null for a build
    # the table doesn't know, LTSC and servers (whose support follows other rules). Older Windows 10 builds have all
    # reached their end.
    if ($OSName -match 'LTSC|LTSB|Server' -or $Build -le 0) { return $null }
    $release = $script:WindowsReleases[$Build]
    if ($release) {
        $end = if ($OSName -match 'Enterprise|Education|Entreprise|Éducation') { $release.Ent } else { $release.Pro }
        return [pscustomobject]@{ Name = $release.Name; End = $end }
    }
    if ($Build -lt 19044) { return [pscustomobject]@{ Name = "Windows 10 (build $Build)"; End = [datetime]'2025-10-14' } }
}

function Get-PCSpecAlert($Specs) {
    # What deserves attention: each a Section, a Field (a section's property, or Volume:C: for a volume), a Level
    # (warn or crit) and a Message.

    # Thresholds: % used per volume, days since the last restart, % of the battery's original capacity, and how many
    # days before Windows' end of support to warn.
    $limits = @{ DiskWarn = 80; DiskCrit = 90; UptimeWarn = 14; UptimeCrit = 30; BatteryWarn = 70; BatteryCrit = 50; EndOfSupportWarnDays = 90 }
    $new = { param($Section, $Field, $Level, $Message) [pscustomobject]@{ Section = $Section; Field = $Field; Level = $Level; Message = $Message } }

    $general = $Specs.General
    if ($general) {
        if ($null -ne $general.UptimeDays) {
            $days = [int]$general.UptimeDays
            if ($general.UptimeDays -ge $limits.UptimeCrit) { & $new General LastBoot crit ((Tr 'Pas redémarré depuis {0} jours.') -f $days) }
            elseif ($general.UptimeDays -ge $limits.UptimeWarn) { & $new General LastBoot warn ((Tr 'Pas redémarré depuis {0} jours.') -f $days) }
        }
        $release = Get-WindowsRelease $general.Build $general.OSName
        if ($release) {
            $label = $release.Name
            $end = $release.End
            $daysLeft = ($end - (Get-Date)).TotalDays
            if ($daysLeft -lt 0) { & $new General BuildNumber crit ((Tr "{0} n'est plus supporté depuis le {1}.") -f $label, (Format-TextDate $end -Day)) }
            elseif ($daysLeft -le $limits.EndOfSupportWarnDays) { & $new General BuildNumber warn ((Tr '{0} : fin de support le {1}.') -f $label, (Format-TextDate $end -Day)) }
        }
    }

    if ($Specs.Disk) {
        foreach ($volume in @($Specs.Disk.Drives | ForEach-Object { $_.Volumes })) {
            if (-not $volume) { continue }
            $message = (Tr 'Volume {0} plein à {1} % ({2} libres).') -f $volume.Drive, $volume.UsedPercent, (Format-Byte $volume.Free)
            if ($volume.UsedPercent -ge $limits.DiskCrit) { & $new Disk "Volume:$($volume.Drive)" crit $message }
            elseif ($volume.UsedPercent -ge $limits.DiskWarn) { & $new Disk "Volume:$($volume.Drive)" warn $message }
        }
    }

    $battery = $Specs.Battery
    if ($battery -and $null -ne $battery.HealthPercent) {
        $message = (Tr "Batterie usée : {0} % de sa capacité d'origine.") -f $battery.HealthPercent
        if ($battery.HealthPercent -lt $limits.BatteryCrit) { & $new Battery Health crit $message }
        elseif ($battery.HealthPercent -lt $limits.BatteryWarn) { & $new Battery Health warn $message }
    }
}

# The sections, in the order shown, with their fields: each a property and its label, in this run's language (the
# keys are the ids, the same in every language).
$script:SpecsSections = [ordered]@{
    General   = @{ Title = Tr 'Général';    Fields = [ordered]@{ ComputerName = Tr "Nom d'ordinateur"; LoggedOnUser = Tr 'Utilisateur connecté'; LastBoot = Tr 'Dernier démarrage'; Manufacturer = Tr 'Fabricant'; Model = Tr 'Modèle'; SerialNumber = Tr 'Numéro de série'; OSName = Tr "Système d'exploitation"; BuildNumber = Tr 'Numéro de build'; OSType = Tr "Type d'OS"; Bios = 'BIOS (version / date)'; SKU = Tr 'SKU système' } }
    Network   = @{ Title = Tr 'Réseau';     Fields = [ordered]@{ IPAddress = Tr 'Adresse IP'; DNS = Tr 'Serveurs DNS'; LinkType = Tr 'Type de lien'; Adapter = Tr 'Carte réseau'; MAC = Tr 'Adresse MAC'; FQDN = 'FQDN'; Domain = Tr 'Domaine' } }
    Processor = @{ Title = Tr 'Processeur'; Fields = [ordered]@{ Name = Tr 'Modèle'; Vendor = Tr 'Fabricant'; Extra = Tr 'Autres infos'; Cores = Tr 'Cœurs / threads'; Architecture = 'Architecture'; BaseClock = Tr 'Vitesse de base'; L3Cache = Tr 'Cache L3' } }
    Memory    = @{ Title = Tr 'Mémoire';    Fields = [ordered]@{ Total = Tr 'Capacité totale'; Type = 'Type'; Speed = Tr 'Vitesse'; Physical = 'Modules'; Maker = Tr 'Fabricant'; Part = Tr 'Référence' } }
    Disk      = @{ Title = Tr 'Disques';    Fields = [ordered]@{ Storage = Tr 'Stockage total'; Details = Tr 'Disques' } }
    Monitor   = @{ Title = Tr 'Écrans';     Fields = [ordered]@{ Count = Tr 'Écrans connectés'; Details = Tr 'Écrans' } }
    Battery   = @{ Title = Tr 'Batterie';   Fields = [ordered]@{ Capacity = Tr 'Charge'; PowerStatus = Tr 'Alimentation'; Health = Tr 'Santé'; Cycles = Tr 'Cycles de charge' } }
    Dock      = @{ Title = Tr "Station d'accueil"; Fields = [ordered]@{ Status = Tr 'État'; Model = Tr 'Modèle'; Firmware = Tr 'Micrologiciel'; Driver = Tr 'Pilote'; Devices = Tr 'Périphériques détectés' } }
    Software  = @{ Title = Tr 'Logiciels';  Fields = [ordered]@{ Count = Tr 'Logiciels installés'; List = Tr 'Liste' } }
}

# The fields shown only when they have a value, in the window and in the report: what a computer doesn't always say
# (the processor's maker when its model names it, the memory's maker and part number when SMBIOS has none).
$script:SpecsOptionalFields = @{
    Processor = 'Vendor', 'Extra'
    Memory    = 'Maker', 'Part'
}

function Format-PCSpecReport($Specs, [string]$Section) {
    # The specs as text, to copy or export, with the sections the window shows, in its order (Test-PCSpecSectionShown).
    # -Section: only that section (General, Network…).
    $text = [System.Text.StringBuilder]::new()
    $name = if ($Specs.General -and $Specs.General.ComputerName) { $Specs.General.ComputerName } else { $Specs.Query }
    $null = $text.AppendLine(((Tr 'Caractéristiques de {0} — {1}') -f $name, (Format-TextDate $Specs.Timestamp)))
    $keys = if ($Section) { @($Section) } else { @($script:SpecsSections.Keys) }
    # « Label : value », with no padding to line the values up: pasted where the font is proportional (Teams, Outlook,
    # a ticket), padded columns no longer line up (#315). A value on several lines starts under its label, indented.
    $mobile = if ($Specs.General) { $Specs.General.Mobile }
    foreach ($key in $keys) {
        $data = $Specs.$key
        if (-not $data -or -not (Test-PCSpecSectionShown $key $data $mobile)) { continue }
        $null = $text.AppendLine().AppendLine("[$($script:SpecsSections[$key].Title)]")
        foreach ($field in $script:SpecsSections[$key].Fields.GetEnumerator()) {
            if ($field.Key -in $script:SpecsOptionalFields[$key] -and -not "$($data.($field.Key))") { continue }
            $lines = @("$($data.($field.Key))" -split "`r?`n")
            if ($lines.Count -gt 1) {
                $null = $text.AppendLine('  ' + ((Tr '{0} : {1}') -f $field.Value, '').TrimEnd())
                foreach ($line in $lines) { $null = $text.AppendLine("    $line") }
            }
            else { $null = $text.AppendLine('  ' + ((Tr '{0} : {1}') -f $field.Value, $lines[0])) }
        }
    }
    $alerts = @($Specs.Alerts | Where-Object { $_ -and (-not $Section -or $_.Section -eq $Section) })
    if ($alerts.Count) {
        $null = $text.AppendLine().AppendLine((Tr '[Alertes]'))
        foreach ($alert in $alerts) { $null = $text.AppendLine("  $(if ($alert.Level -eq 'crit') { '[!!]' } else { '[!] ' }) $($alert.Message)") }
    }
    if (-not $Section -and $Specs.Errors.Count) {
        $null = $text.AppendLine().AppendLine((Tr '[Erreurs]'))
        # Each under its section's key (General…), or Connexion, which is also a key.
        foreach ($entry in $Specs.Errors.GetEnumerator()) {
            $null = $text.AppendLine('  ' + ((Tr '{0} : {1}') -f $(if ($entry.Key -eq 'Connexion') { Tr 'Connexion' } else { $entry.Key }), $entry.Value))
        }
    }
    $text.ToString()
}

# Run on its own (not dot-sourced): reads the computer given.
if ($MyInvocation.InvocationName -ne '.') {
    $specs = Get-PCSpec -ComputerName $ComputerName -TimeoutSeconds $TimeoutSeconds
    if ($AsText) { Format-PCSpecReport $specs } else { $specs }
}
