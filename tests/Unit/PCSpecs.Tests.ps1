# Caractéristiques' reading (PCSpecs.ps1), on the fake AD's computers: how it connects (WinRM when its port answers,
# DCOM at once otherwise), how long each part took, and the software, read in one WinRM call or value by value through
# the remote registry, which give the same list. ord-01 has WinRM; ord-04 doesn't, but answers on DCOM; ord-06
# answers neither. And which names are this computer's, read without the network.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD

    function Get-ProgramLine($Specs) {
        @($Specs.Software.Programs | ForEach-Object { "$($_.Name) | $($_.Version) | $($_.Publisher) | $($_.InstallDate) | $($_.Scope)" })
    }
}

AfterAll {
    $env:REPERE_FAKEAD_NO_REMOTING = $null
}

Describe 'New-PCSpecsCimSession' {
    It 'Connects over WinRM when its port answers, over DCOM at once when it does not: <HostName>' -ForEach @(
        @{ HostName = 'ord-01.demo.local'; Protocol = 'WinRM' }
        @{ HostName = 'ord-04.demo.local'; Protocol = 'DCOM' }
    ) {
        (New-PCSpecsCimSession $HostName 15).Protocol | Should -BeExactly $Protocol
    }

    It 'Says the WinRM port did not answer, and why DCOM failed' {
        { New-PCSpecsCimSession 'ord-06.demo.local' 15 } | Should -Throw 'WinRM : le port 5985 ne répond pas | DCOM : The RPC server is unavailable.'
    }
}

Describe 'Get-PCSpec' {
    It 'Reads the software in one WinRM call where WinRM answers, value by value elsewhere, and times each part' {
        $winrm = Get-PCSpec 'ord-01.demo.local'
        $winrm.Protocol | Should -BeExactly 'WinRM'
        $winrm.SoftwareVia | Should -BeExactly 'WinRM'
        $winrm.Software.Count | Should -BeExactly '7 logiciels'
        @($winrm.Timings.Keys) | Should -Be @('Connexion', 'General', 'Network', 'Processor', 'Memory', 'Disk', 'Monitor', 'Battery', 'Dock', 'Software')
        $dcom = Get-PCSpec 'ord-04.demo.local'
        $dcom.Protocol | Should -BeExactly 'DCOM'
        $dcom.SoftwareVia | Should -BeExactly 'Registry'
        $dcom.Software.Count | Should -BeExactly '3 logiciels'
    }

    It 'Falls back on the registry, with the same list, when WinRM answers but refuses PowerShell''s remoting' {
        $env:REPERE_FAKEAD_NO_REMOTING = $null
        $winrm = Get-PCSpec 'ord-01.demo.local'
        $env:REPERE_FAKEAD_NO_REMOTING = '1'
        try { $registry = Get-PCSpec 'ord-01.demo.local' }
        finally { $env:REPERE_FAKEAD_NO_REMOTING = $null }
        $registry.SoftwareVia | Should -BeExactly 'Registry'
        $registry.Errors.Contains('Software') | Should -BeFalse
        Get-ProgramLine $registry | Should -Be (Get-ProgramLine $winrm)
    }

    It 'Reads the battery''s health from SMBIOS when its firmware does not support BatteryStaticData' {
        $battery = (Get-PCSpec 'ord-01.demo.local').Battery
        $battery.HealthPercent | Should -BeExactly 62
        $battery.Health | Should -BeExactly ('{0:N0} % ({1:N0} / {2:N0} mWh)' -f 62, 33480, 54000)
        $battery.Cycles | Should -BeExactly '412'
    }

    It 'Finds the Dell dock of a laptop, and none on a desktop, in the order the window shows (#271)' {
        $laptop = Get-PCSpec 'ord-01.demo.local'
        $laptop.General.Mobile | Should -BeTrue
        $laptop.Dock.Connected | Should -BeTrue
        $laptop.Dock.Model | Should -BeExactly 'Station Dell (modèle inconnu)'
        $laptop.Dock.Firmware | Should -BeExactly 'Non communiqué par Windows (révision USB 01.01)'
        $laptop.Dock.Driver | Should -BeExactly 'Pilote standard de Windows (10.0.26100.1)'
        # Not the ThinkPad dock's audio, no longer connected.
        $laptop.Dock.Devices | Should -BeExactly "Generic USB Hub (USB 413C:B06E)`nGeneric SuperSpeed USB Hub (USB 413C:B06F)"
        @($laptop.PSObject.Properties.Name | Where-Object { $_ -in 'Monitor', 'Battery', 'Dock', 'Software' }) | Should -Be @('Monitor', 'Battery', 'Dock', 'Software')
        $desktop = Get-PCSpec 'ord-04.demo.local'
        $desktop.General.Mobile | Should -BeFalse
        $desktop.Dock.Connected | Should -BeFalse
        $desktop.Dock.Status | Should -BeExactly 'Aucune station détectée'
    }

    It 'Reads a computer with this one''s name in another domain over the network, not this one (#242)' {
        $specs = Get-PCSpec "$env:COMPUTERNAME.lyon.invalid"
        $specs.Protocol | Should -BeNullOrEmpty
        $specs.Errors.Connexion | Should -BeLike "*'$env:COMPUTERNAME.lyon.invalid' introuvable dans le DNS*"
    }

    It 'Times the connection even when it fails' {
        $specs = Get-PCSpec 'ord-06.demo.local'
        $specs.Reachable | Should -BeFalse
        @($specs.Timings.Keys) | Should -Be @('Connexion')
    }
}

Describe 'Test-PCSpecsLocal' {
    # The technician's computer is PC-001.paris.corp; PC-001.lyon.corp is another one, with the same first label.
    BeforeAll {
        Mock Get-PCSpecsLocalName { @{ Names = @('PC-001'); Fqdn = @('PC-001.paris.corp') } }
    }

    It 'Takes <Name> for this computer: <Local>' -ForEach @(
        @{ Name = ''; Local = $true }
        @{ Name = '.'; Local = $true }
        @{ Name = 'LocalHost.'; Local = $true }
        @{ Name = 'pc-001'; Local = $true }
        @{ Name = 'pc-001.PARIS.corp'; Local = $true }
        @{ Name = 'PC-001.paris.corp.'; Local = $true }
        @{ Name = 'PC-001.lyon.corp'; Local = $false }
        @{ Name = 'PC-001.paris.corp.lyon'; Local = $false }
        @{ Name = 'PC-002'; Local = $false }
        @{ Name = '10.0.1.14'; Local = $false }
    ) {
        Test-PCSpecsLocal $Name | Should -Be $Local
    }

    It 'Takes no DNS name for this computer when it has no primary DNS suffix' {
        Mock Get-PCSpecsLocalName { @{ Names = @('PC-001'); Fqdn = @() } }
        Test-PCSpecsLocal 'PC-001' | Should -BeTrue
        Test-PCSpecsLocal 'PC-001.paris.corp' | Should -BeFalse
    }
}

Describe 'Get-PCSpecsLocalName' {
    It 'Gives this computer''s NetBIOS name, and an FQDN only with a domain' {
        $local = Get-PCSpecsLocalName
        $local.Names | Should -Contain $env:COMPUTERNAME
        foreach ($fqdn in $local.Fqdn) { $fqdn | Should -Match '^[^.]+\.[^.]' }
    }
}

Describe 'ConvertTo-PCBatteryHealth' {
    BeforeAll {
        function New-FullCharge($Name, $Capacity) { [pscustomobject]@{ InstanceName = $Name; FullChargedCapacity = $Capacity } }
        function New-StaticData($Name, $Capacity) { [pscustomobject]@{ InstanceName = $Name; DesignedCapacity = $Capacity } }
        function New-PortableBattery($Capacity) { [pscustomobject]@{ DesignCapacity = $Capacity } }
    }

    It 'Divides the full charge by the original capacity, root\wmi''s before SMBIOS''s' {
        $health = ConvertTo-PCBatteryHealth @(New-FullCharge 'BAT0' 40000) @(New-StaticData 'BAT0' 50000) @(New-PortableBattery 80000)
        $health.Percent | Should -BeExactly 80
        $health.Text | Should -BeExactly ('{0:N0} % ({1:N0} / {2:N0} mWh)' -f 80, 40000, 50000)
    }

    It 'Takes SMBIOS''s original capacity when BatteryStaticData gives none or 0' -ForEach @(
        @{ Case = 'none'; Static = @() }
        @{ Case = '0'; Static = @([pscustomobject]@{ InstanceName = 'BAT0'; DesignedCapacity = 0 }) }
    ) {
        (ConvertTo-PCBatteryHealth @(New-FullCharge 'BAT0' 30000) $Static @(New-PortableBattery 60000)).Percent | Should -BeExactly 50
    }

    It 'Adds up two batteries, each with its own original capacity' {
        $health = ConvertTo-PCBatteryHealth @((New-FullCharge 'BAT0' 20000), (New-FullCharge 'BAT1' 10000)) @((New-StaticData 'BAT1' 20000), (New-StaticData 'BAT0' 20000)) @()
        $health.Percent | Should -BeExactly 75
    }

    It 'Does not pair one original capacity with two batteries' {
        (ConvertTo-PCBatteryHealth @((New-FullCharge 'BAT0' 20000), (New-FullCharge 'BAT1' 10000)) @(New-StaticData 'BAT0' 20000) @(New-PortableBattery 20000)).Percent | Should -BeNullOrEmpty
    }

    It 'Gives the full charge alone when the original capacity is unknown or makes no sense: <Case>' -ForEach @(
        @{ Case = 'unknown'; Design = $null }
        @{ Case = 'mAh instead of mWh'; Design = 4000 }
    ) {
        $smbios = if ($Design) { @(New-PortableBattery $Design) } else { @() }
        $health = ConvertTo-PCBatteryHealth @(New-FullCharge 'BAT0' 33480) @() $smbios
        $health.Percent | Should -BeNullOrEmpty
        $health.Text | Should -BeExactly ('{0:N0} mWh (capacité d''origine inconnue)' -f 33480)
    }

    It 'Says N/D without a full charge' {
        (ConvertTo-PCBatteryHealth @() @(New-StaticData 'BAT0' 50000) @(New-PortableBattery 50000)).Text | Should -BeExactly 'N/D'
    }
}

Describe 'Test-PCMobileChassis' {
    It 'Takes chassis <Chassis> with power profile <Profile> for a laptop: <Mobile>' -ForEach @(
        @{ Chassis = @(10); Profile = 2; Mobile = $true }
        @{ Chassis = @(9); Profile = 1; Mobile = $true }
        @{ Chassis = @(31); Profile = 0; Mobile = $true }
        # A laptop on an old dock that SMBIOS lists as an enclosure of its own (12, Docking Station).
        @{ Chassis = @(12, 9); Profile = 2; Mobile = $true }
        @{ Chassis = @(3); Profile = 1; Mobile = $false }
        @{ Chassis = @(35); Profile = 2; Mobile = $false }
        @{ Chassis = @(23); Profile = 4; Mobile = $false }
        # Other or Unknown, as virtual machines and custom-built computers say: Windows' power profile decides.
        @{ Chassis = @(1); Profile = 2; Mobile = $true }
        @{ Chassis = @(2); Profile = 1; Mobile = $false }
        @{ Chassis = @(); Profile = 3; Mobile = $false }
    ) {
        Test-PCMobileChassis $Chassis $Profile | Should -Be $Mobile
    }

    It 'Says nothing when neither the chassis nor the power profile says' {
        Test-PCMobileChassis @(1) 0 | Should -BeNullOrEmpty
        Test-PCMobileChassis $null $null | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-PCDock' {
    # Win32_PnPEntity's USB devices, as sample CIM data: a laptop on a Dell dock, a laptop on a ThinkPad dock, a laptop
    # without a dock but with a USB network adapter, and a desktop with a keyboard and a mouse.
    BeforeAll {
        function New-PnP([string]$Name, [string]$DeviceId, [string]$Class = 'USB', [string]$Revision = '0100', $Present = $true, [uint32]$ErrorCode = 0) {
            $hardware = $DeviceId.Split('\')[0..1] -join '\'
            [pscustomobject]@{ Name = $Name; DeviceID = $DeviceId; PNPClass = $Class; Present = $Present; ConfigManagerErrorCode = $ErrorCode; HardwareID = [string[]]@("$hardware&REV_$Revision", $hardware) }
        }
        $script:Mouse = New-PnP 'USB Input Device' 'USB\VID_046D&PID_C077\5&1&0&3' 'HIDClass'
        $script:Keyboard = New-PnP 'USB Input Device' 'USB\VID_046D&PID_C31C\5&1&0&1' 'HIDClass'
        $script:DellDock = @(
            New-PnP 'Generic USB Hub' 'USB\VID_413C&PID_B06E\6&2C7A1F3B&0&1' 'USB' '0101'
            New-PnP 'Generic SuperSpeed USB Hub' 'USB\VID_413C&PID_B06F\6&1E5D2A9C&0&2' 'USB' '0101'
            New-PnP 'Realtek USB GbE Family Controller' 'USB\VID_0BDA&PID_8153\301000001' 'Net' '3100'
            $script:Mouse
        )
        $script:ThinkPadDock = @(
            New-PnP 'ThinkPad USB-C Dock Gen2 USB Audio' 'USB\VID_17EF&PID_A396&MI_00\7&1&0&0000' 'MEDIA' '3109'
            New-PnP 'ThinkPad USB-C Dock Gen2 Ethernet' 'USB\VID_17EF&PID_A387\301000001' 'Net' '3109'
            $script:Mouse
        )
        $script:NoDock = @(
            New-PnP 'Realtek USB GbE Family Controller' 'USB\VID_0BDA&PID_8153\301000002' 'Net' '3000'
            New-PnP 'DisplayLink USB Device' 'USB\VID_17E9&PID_4301\5&2&0&4' 'USB' '3104'
            $script:Mouse
        )
        $script:Desktop = @($script:Keyboard, $script:Mouse)
        $script:VendorDriver = { param($Device) @{ Version = '6.0.9500.1'; Provider = 'Lenovo' } }
    }

    It 'Finds a Dell dock by its hubs'' USB ids, says what Windows does not tell, and reads the driver of the first' {
        $read = [System.Collections.Generic.List[object]]::new()
        $dock = ConvertTo-PCDock $script:DellDock { param($Device) $read.Add($Device.DeviceID); @{ Version = '10.0.26100.1'; Provider = 'Microsoft' } }.GetNewClosure()
        $dock.Connected | Should -BeTrue
        $dock.Status | Should -BeExactly 'Connectée'
        $dock.Model | Should -BeExactly 'Station Dell (modèle inconnu)'
        $dock.Firmware | Should -BeExactly 'Non communiqué par Windows (révision USB 01.01)'
        $dock.Driver | Should -BeExactly 'Pilote standard de Windows (10.0.26100.1)'
        # The network adapter is only a hint: not listed as the dock's.
        $dock.Devices | Should -BeExactly "Generic USB Hub (USB 413C:B06E)`nGeneric SuperSpeed USB Hub (USB 413C:B06F)"
        @($read) | Should -Be @('USB\VID_413C&PID_B06E\6&2C7A1F3B&0&1')
    }

    It 'Takes the model from the devices that name the dock, without their part''s suffix, with the maker''s driver' {
        $dock = ConvertTo-PCDock $script:ThinkPadDock $script:VendorDriver
        $dock.Connected | Should -BeTrue
        $dock.Model | Should -BeExactly 'ThinkPad USB-C Dock Gen2'
        $dock.Firmware | Should -BeExactly 'Non communiqué par Windows (révision USB 31.09)'
        $dock.Driver | Should -BeExactly '6.0.9500.1 (Lenovo)'
    }

    It 'Does not claim a dock from a USB network adapter or a DisplayLink device, and lists them as hints' {
        $dock = ConvertTo-PCDock $script:NoDock $script:VendorDriver
        $dock.Connected | Should -BeFalse
        $dock.Status | Should -BeExactly 'Aucune station reconnue'
        $dock.Model | Should -BeExactly 'N/D'
        $dock.Devices | Should -BeExactly ("Indices seulement, pas la preuve d'une station :`n  Realtek USB GbE Family Controller (USB 0BDA:8153)`n  DisplayLink USB Device (USB 17E9:4301)")
    }

    It 'Says none on a desktop with a keyboard and a mouse' {
        $dock = ConvertTo-PCDock $script:Desktop $script:VendorDriver
        $dock.Connected | Should -BeFalse
        $dock.Status | Should -BeExactly 'Aucune station détectée'
        $dock.Devices | Should -BeExactly 'Aucun'
    }

    It 'Ignores a dock seen before but not connected now (<Case>), and the firmware''s ACPI docking station' -ForEach @(
        @{ Case = 'not present'; Present = $false; ErrorCode = 0 }
        @{ Case = 'error 45'; Present = $true; ErrorCode = 45 }
    ) {
        $gone = New-PnP 'ThinkPad USB-C Dock Gen2 USB Audio' 'USB\VID_17EF&PID_A396&MI_00\7&1&0&0000' 'MEDIA' '3109' $Present $ErrorCode
        $acpi = New-PnP 'Docking Station' 'ACPI\PNP0C15\1' 'System'
        (ConvertTo-PCDock @($gone, $acpi, $script:Mouse) $script:VendorDriver).Connected | Should -BeFalse
    }

    It 'Lists a device seen twice once, as the fake Dell dock''s hub on two ports' {
        $hub = New-PnP 'Generic USB Hub' 'USB\VID_413C&PID_B06E\6&2C7A1F3B&0&1' 'USB' '0101'
        $again = New-PnP 'generic usb hub ' 'USB\VID_413C&PID_B06E\6&2C7A1F3B&0&5' 'USB' '0101'
        $dock = ConvertTo-PCDock @($hub, $again, $script:DellDock[1]) $script:VendorDriver
        $dock.Devices | Should -BeExactly "Generic USB Hub (USB 413C:B06E)`nGeneric SuperSpeed USB Hub (USB 413C:B06F)"
        (Get-PCSpec 'ord-01.demo.local').Dock.Devices | Should -BeExactly "Generic USB Hub (USB 413C:B06E)`nGeneric SuperSpeed USB Hub (USB 413C:B06F)"
    }

    It 'Does not say the model twice when the dock''s one named device is the model: its USB id only' {
        $only = New-PnP 'HP USB-C Dock G5' 'USB\VID_03F0&PID_0667\5&1&0&2' 'USB' '0201'
        $audio = New-PnP 'HP USB-C Dock G5' 'USB\VID_03F0&PID_0667\5&1&0&3' 'USB' '0201'
        $dock = ConvertTo-PCDock @($only, $audio) $script:VendorDriver
        $dock.Model | Should -BeExactly 'HP USB-C Dock G5'
        $dock.Devices | Should -BeExactly 'USB 03F0:0667'
        # Two names that differ stay as they are.
        $dock = ConvertTo-PCDock $script:ThinkPadDock $script:VendorDriver
        $dock.Devices | Should -BeExactly "ThinkPad USB-C Dock Gen2 USB Audio (USB 17EF:A396)`nThinkPad USB-C Dock Gen2 Ethernet (USB 17EF:A387)"
    }

    It 'Lists a hint seen twice once' {
        $link = New-PnP 'DisplayLink USB Device' 'USB\VID_17E9&PID_4301\5&2&0&5' 'USB' '3104'
        $dock = ConvertTo-PCDock @($script:NoDock + $link) $script:VendorDriver
        @($dock.Devices -split "`n" | Where-Object { $_ -like '*DisplayLink*' }).Count | Should -Be 1
    }

    It 'Says N/D for the driver when it cannot be read, and still finds the dock' {
        $dock = ConvertTo-PCDock $script:ThinkPadDock { throw 'Invalid method' }
        $dock.Connected | Should -BeTrue
        $dock.Driver | Should -BeExactly 'N/D'
    }

    It 'Reads devices without Present or PNPClass, as Windows before 10 gives them' {
        $old = [pscustomobject]@{ Name = 'HP USB-C Dock G5'; DeviceID = 'USB\VID_03F0&PID_076B\1'; HardwareID = $null }
        Set-StrictMode -Version Latest
        $dock = ConvertTo-PCDock @($old) $null
        $dock.Model | Should -BeExactly 'HP USB-C Dock G5'
        $dock.Firmware | Should -BeExactly 'Non communiqué par Windows'
    }
}

Describe 'ConvertTo-PCMemory' {
    It 'Names the maker of JEDEC code <Code>: <Maker>' -ForEach @(
        @{ Code = '80CE'; Maker = 'Samsung' }, @{ Code = 'CE00'; Maker = 'Samsung' }, @{ Code = '80ce'; Maker = 'Samsung' }
        @{ Code = '802C'; Maker = 'Micron' }, @{ Code = '2C00'; Maker = 'Micron' }
        @{ Code = '80AD'; Maker = 'SK hynix' }, @{ Code = 'AD00'; Maker = 'SK hynix' }
        @{ Code = '0198'; Maker = 'Kingston' }, @{ Code = '9801'; Maker = 'Kingston' }
        @{ Code = '859B'; Maker = 'Crucial' }
    ) {
        ConvertTo-PCMemoryMaker $Code | Should -BeExactly $Maker
    }

    It 'Shows a maker as it is when it is a name, or a code not in the list' {
        ConvertTo-PCMemoryMaker 'Kingston' | Should -BeExactly 'Kingston'
        ConvertTo-PCMemoryMaker '  Corsair ' | Should -BeExactly 'Corsair'
        ConvertTo-PCMemoryMaker '1234' | Should -BeExactly '1234'
    }

    It 'Says nothing of a maker or a part number that is empty or a placeholder: <Value>' -ForEach @(
        @{ Value = $null }, @{ Value = '' }, @{ Value = '   ' }, @{ Value = 'Unknown' }, @{ Value = 'Undefined' }
        @{ Value = '0000' }, @{ Value = '0' }, @{ Value = 'Not Specified' }
    ) {
        ConvertTo-PCMemoryMaker $Value | Should -BeNullOrEmpty
        ConvertTo-PCMemoryPartNumber $Value | Should -BeNullOrEmpty
    }

    It 'Says nothing of the placeholders only one of them has' {
        ConvertTo-PCMemoryMaker 'Manufacturer0' | Should -BeNullOrEmpty
        ConvertTo-PCMemoryPartNumber 'PartNum0' | Should -BeNullOrEmpty
    }

    It 'Trims the part number SMBIOS pads with spaces' {
        ConvertTo-PCMemoryPartNumber 'M425R1GB4BB0-CWM    ' | Should -BeExactly 'M425R1GB4BB0-CWM'
        ConvertTo-PCMemoryPartNumber "  KVR26N19S8/8`0`0 " | Should -BeExactly 'KVR26N19S8/8'
    }

    It 'Gives one maker and one part number for modules that agree, all of them for modules that do not, nothing when none says' {
        $same = ConvertTo-PCMemory @(
            [pscustomobject]@{ Manufacturer = '80CE'; PartNumber = 'M425R1GB4BB0-CWM  ' }
            [pscustomobject]@{ Manufacturer = '80CE'; PartNumber = 'M425R1GB4BB0-CWM' }
        )
        $same.Maker | Should -BeExactly 'Samsung'
        $same.Part | Should -BeExactly 'M425R1GB4BB0-CWM'
        $mixed = ConvertTo-PCMemory @(
            [pscustomobject]@{ Manufacturer = '80CE'; PartNumber = 'M425R1GB4BB0-CWM' }
            [pscustomobject]@{ Manufacturer = '802C'; PartNumber = 'MTC8C1084S1SC48BA1' }
        )
        $mixed.Maker | Should -BeExactly 'Samsung / Micron'
        $mixed.Part | Should -BeExactly 'M425R1GB4BB0-CWM / MTC8C1084S1SC48BA1'
        $none = ConvertTo-PCMemory @([pscustomobject]@{ Manufacturer = 'Undefined'; PartNumber = '   ' }, [pscustomobject]@{ Capacity = 1 })
        $none.Maker | Should -BeNullOrEmpty
        $none.Part | Should -BeNullOrEmpty
    }

    It 'Reads the fake computers'' modules, and leaves the rows out of the report when there is nothing to say' {
        $laptop = (Get-PCSpec 'ord-01.demo.local').Memory
        $laptop.Maker | Should -BeExactly 'Samsung'
        $laptop.Part | Should -BeExactly 'M425R1GB4BB0-CWM'
        $desktop = (Get-PCSpec 'ord-04.demo.local').Memory
        $desktop.Maker | Should -BeNullOrEmpty
        $desktop.Part | Should -BeNullOrEmpty
        $report = Format-PCSpecReport (Get-PCSpec 'ord-01.demo.local') 'Memory'
        $report | Should -Match '  Fabricant : Samsung\r?\n'
        $report | Should -Match '  Référence : M425R1GB4BB0-CWM\r?\n'
        $report = Format-PCSpecReport (Get-PCSpec 'ord-04.demo.local') 'Memory'
        $report | Should -Not -Match 'Fabricant|Référence'
    }
}

Describe 'Processor' {
    It 'Cleans the model: <Name>' -ForEach @(
        @{ Name = 'Intel(R) Core(TM) i7-1365U'; Clock = $true; Expected = 'Intel Core i7-1365U' }
        @{ Name = '13th Gen Intel(R) Core(TM) i5-1345U'; Clock = $true; Expected = '13th Gen Intel Core i5-1345U' }
        @{ Name = 'Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz'; Clock = $true; Expected = 'Intel Core i3-10100' }
        @{ Name = 'Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz'; Clock = $false; Expected = 'Intel Core i3-10100 @ 3.60GHz' }
        @{ Name = 'Intel(R) Xeon(R) CPU E5-2680 v4  @ 2.40GHz'; Clock = $true; Expected = 'Intel Xeon E5-2680 v4' }
        @{ Name = 'AMD Ryzen 5 5600X 6-Core Processor             '; Clock = $true; Expected = 'AMD Ryzen 5 5600X' }
        @{ Name = 'AMD Ryzen 5 PRO 5650U with Radeon Graphics'; Clock = $true; Expected = 'AMD Ryzen 5 PRO 5650U with Radeon Graphics' }
    ) {
        Format-PCCpuName $Name $Clock | Should -BeExactly $Expected
    }

    It 'Gives the maker only when the model does not name it: <Manufacturer> with <Model>' -ForEach @(
        @{ Manufacturer = 'GenuineIntel'; Model = 'Intel Core i7-1365U'; Expected = $null }
        @{ Manufacturer = 'AuthenticAMD'; Model = 'AMD Ryzen 5 5600X'; Expected = $null }
        @{ Manufacturer = 'GenuineIntel'; Model = 'Core i7-1365U'; Expected = 'Intel' }
        @{ Manufacturer = 'AuthenticAMD'; Model = 'Ryzen 5 5600X'; Expected = 'AMD' }
        @{ Manufacturer = 'Advanced Micro Devices, Inc.'; Model = 'Ryzen 5 5600X'; Expected = 'AMD' }
        @{ Manufacturer = 'Qualcomm Technologies Inc'; Model = 'Snapdragon X Elite'; Expected = 'Qualcomm Technologies Inc' }
        @{ Manufacturer = 'Unknown'; Model = 'Snapdragon X Elite'; Expected = $null }
        @{ Manufacturer = $null; Model = 'Snapdragon X Elite'; Expected = $null }
    ) {
        Get-PCCpuVendor $Manufacturer $Model | Should -Be $Expected
    }

    It 'Leaves out the maker, and the other info that only repeats, in the fake computers'' sections and reports' {
        $laptop = (Get-PCSpec 'ord-01.demo.local').Processor
        $laptop.Name | Should -BeExactly '13th Gen Intel Core i5-1345U'
        $laptop.Vendor | Should -BeNullOrEmpty
        # Its current speed is not its base speed (1,60 GHz): told.
        $laptop.Extra | Should -BeLike 'Actuelle : 2*40 GHz'
        $desktop = (Get-PCSpec 'ord-04.demo.local').Processor
        $desktop.Name | Should -BeExactly 'Intel Core i3-10100'
        $desktop.Vendor | Should -BeNullOrEmpty
        $desktop.Extra | Should -BeNullOrEmpty
        $desktop.BaseClock | Should -BeLike '3*60 GHz'
        $report = Format-PCSpecReport (Get-PCSpec 'ord-04.demo.local') 'Processor'
        $report | Should -Match '  Modèle : Intel Core i3-10100\r?\n'
        $report | Should -Not -Match 'Fabricant|Autres infos|GenuineIntel'
    }
}

Describe 'Test-PCSpecSectionShown' {
    It 'Shows <Key> for <Case>: <Shown>' -ForEach @(
        @{ Key = 'Battery'; Case = 'a laptop'; Data = [pscustomobject]@{ Present = $true }; Mobile = $true; Read = $true; Shown = $true }
        @{ Key = 'Battery'; Case = 'a laptop without its battery'; Data = [pscustomobject]@{ Present = $false }; Mobile = $true; Read = $true; Shown = $true }
        @{ Key = 'Battery'; Case = 'a laptop, before it is read'; Data = $null; Mobile = $true; Read = $false; Shown = $true }
        @{ Key = 'Battery'; Case = 'a desktop'; Data = [pscustomobject]@{ Present = $false }; Mobile = $false; Read = $true; Shown = $false }
        @{ Key = 'Battery'; Case = 'a desktop on a UPS Windows sees as a battery'; Data = [pscustomobject]@{ Present = $true }; Mobile = $false; Read = $true; Shown = $true }
        @{ Key = 'Battery'; Case = 'a computer of unknown chassis, before it is read'; Data = $null; Mobile = $null; Read = $false; Shown = $false }
        @{ Key = 'Battery'; Case = 'a computer of unknown chassis, unreadable'; Data = $null; Mobile = $null; Read = $true; Shown = $true }
        @{ Key = 'Battery'; Case = 'a desktop, unreadable'; Data = $null; Mobile = $false; Read = $true; Shown = $false }
        @{ Key = 'Dock'; Case = 'a laptop without a dock'; Data = [pscustomobject]@{ Connected = $false }; Mobile = $true; Read = $true; Shown = $true }
        @{ Key = 'Dock'; Case = 'a desktop without a dock'; Data = [pscustomobject]@{ Connected = $false }; Mobile = $false; Read = $true; Shown = $false }
        @{ Key = 'Dock'; Case = 'a desktop with a dock'; Data = [pscustomobject]@{ Connected = $true }; Mobile = $false; Read = $true; Shown = $true }
        @{ Key = 'Monitor'; Case = 'a desktop'; Data = [pscustomobject]@{}; Mobile = $false; Read = $true; Shown = $true }
    ) {
        Test-PCSpecSectionShown $Key $Data $Mobile $Read | Should -Be $Shown
    }
}

Describe 'Format-PCSpecReport' {
    It 'Puts Batterie and Station d''accueil after Écrans for a laptop, and leaves them out for a desktop (#271)' {
        $sections = { param($Specs) @((Format-PCSpecReport $Specs) -split "`r?`n" | Where-Object { $_ -match '^\[' }) }
        & $sections (Get-PCSpec 'ord-01.demo.local') | Should -Be @('[Général]', '[Réseau]', '[Processeur]', '[Mémoire]', '[Disques]', '[Écrans]', '[Batterie]', "[Station d'accueil]", '[Logiciels]', '[Alertes]')
        & $sections (Get-PCSpec 'ord-04.demo.local') | Should -Be @('[Général]', '[Réseau]', '[Processeur]', '[Mémoire]', '[Disques]', '[Écrans]', '[Logiciels]', '[Alertes]')
    }

    It 'Writes « Label : value » with no padding, and a value on several lines under its label (#315)' {
        # Padded columns only line up in a monospace font; pasted in Teams or Outlook they don't.
        $lines = @((Format-PCSpecReport (Get-PCSpec 'ord-01.demo.local') 'Network') -split "`r?`n")
        $lines | Should -Contain '  Adresse MAC : 3C:21:9C:4E:7A:10'
        $at = [array]::IndexOf($lines, '  Adresse IP :')
        $at | Should -BeGreaterThan 0
        $lines[($at + 1)..($at + 2)] | Should -Be @('    10.0.1.11', '    172.20.48.1 (vEthernet (Default Switch))')
        @($lines | Where-Object { $_ -match '\S {2,}:' }) | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-PCSoftware' {
    It 'Leaves out system components, updates and nameless entries, lists a program once, and dates a number' {
        $entry = { param($Scope, $Name, $Version, $Date, $System, $Parent) [pscustomobject]@{ Scope = $Scope; DisplayName = $Name; DisplayVersion = $Version; Publisher = 'Éditeur'; InstallDate = $Date; SystemComponent = $System; ParentKeyName = $Parent } }
        $software = ConvertTo-PCSoftware @(
            & $entry Computer 'Chrome' '141' '20261008' $null $null
            & $entry Computer 'Chrome' '141' '20261008' $null $null
            & $entry User 'Zoom' '6.4' '20261001' $null $null
            & $entry Computer 'Runtime' '14' $null '1' $null
            & $entry Computer 'Mise à jour' '1' $null $null ''
            & $entry Computer $null '1' $null $null $null
            & $entry Computer 'Sans date' '2' 'hier' '0' $null
        )
        $software.Count | Should -BeExactly '3 logiciels'
        @($software.Programs | ForEach-Object { "$($_.Name) | $($_.InstallDate) | $($_.Scope)" }) | Should -Be @('Chrome | 2026-10-08 | Ordinateur', 'Sans date |  | Ordinateur', 'Zoom | 2026-10-01 | Utilisateur')
    }

    It 'Says none when there is none' {
        (ConvertTo-PCSoftware @()).List | Should -BeExactly 'Aucun'
    }

    It 'Shows the date as Repère does, in English too, and keeps yyyy-MM-dd to sort on' {
        $entry = [pscustomobject]@{ Scope = 'Computer'; DisplayName = '7-Zip'; DisplayVersion = '24.08'; Publisher = 'Igor Pavlov'; InstallDate = [uint32]20240815; SystemComponent = $null; ParentKeyName = $null }
        $program = (ConvertTo-PCSoftware @($entry)).Programs[0]
        $program.InstallDate | Should -BeExactly '2024-08-15'
        $program.InstallDateText | Should -BeExactly '2024-08-15'
        try {
            [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', [System.Collections.Generic.Dictionary[string, string]]::new())
            $program = (ConvertTo-PCSoftware @($entry)).Programs[0]
            $program.InstallDate | Should -BeExactly '2024-08-15'
            $program.InstallDateText | Should -BeExactly '8/15/2024'
        }
        finally { [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $null) }
    }
}

Describe 'ConvertFrom-PCInstallDate' {
    It 'Reads <Value> as <Expected>' -ForEach @(
        @{ Value = '20240815'; Expected = '2024-08-15' }
        @{ Value = [uint32]20240815; Expected = '2024-08-15' }
        @{ Value = ' 20240815 '; Expected = '2024-08-15' }
        @{ Value = '2024-08-15'; Expected = '2024-08-15' }
        @{ Value = '15/08/2024'; Expected = '2024-08-15' }
        @{ Value = '8/15/2024'; Expected = '2024-08-15' }
        @{ Value = '15.08.2024'; Expected = '2024-08-15' }
        @{ Value = '5/5/2024'; Expected = '2024-05-05' }
    ) {
        (ConvertFrom-PCInstallDate $Value).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) | Should -BeExactly $Expected
    }

    It 'Gives nothing rather than a wrong date for <Value>' -ForEach @(
        @{ Value = $null }
        @{ Value = '' }
        @{ Value = '0' }
        @{ Value = '00000000' }
        @{ Value = '19700101' }
        @{ Value = '2024815' }
        @{ Value = '20241399' }
        @{ Value = '20240230' }
        @{ Value = '8/5/2024' }
        @{ Value = '31/02/2024' }
        @{ Value = '13/13/2024' }
        @{ Value = '15/08/0000' }
        @{ Value = 'hier' }
        @{ Value = '1723680000' }
    ) {
        ConvertFrom-PCInstallDate $Value | Should -BeNullOrEmpty
    }
}
