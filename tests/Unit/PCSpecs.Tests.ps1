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

Describe 'Windows'' support: Get-WindowsRelease, its alerts and the Système column' {
    BeforeAll {
        # Past the table's newest build, whatever it is once new releases are added: a release this Repère doesn't know.
        $script:NewerBuild = ($script:WindowsReleases.Keys | Measure-Object -Maximum).Maximum + 100
        $script:UnknownNote = "Repère ne connaît pas encore cette version de Windows : sa fin de support n'est pas connue."
        $script:EsuNote = 'Un ordinateur inscrit aux mises à jour de sécurité étendues (ESU) reste à jour pour la sécurité.'

        function Get-BuildAlert([int]$Build, [string]$OSName) {
            # The alert on Numéro de build for a computer of this build, as Caractéristiques shows it.
            $specs = [pscustomobject]@{ General = [pscustomobject]@{ UptimeDays = $null; Build = $Build; OSName = $OSName }; Disk = $null; Battery = $null }
            @(Get-PCSpecAlert $specs | Where-Object Field -eq 'BuildNumber')
        }
    }

    It 'Names a known build, with its end of support for its edition' {
        $release = Get-WindowsRelease 26100 'Windows 11 Professionnel'
        $release.Name | Should -BeExactly 'Windows 11 24H2'
        $release.End | Should -Be ([datetime]'2026-10-13')
        $release.Note | Should -BeNullOrEmpty
        (Get-WindowsRelease 26100 'Windows 11 Entreprise').End | Should -Be ([datetime]'2027-10-12')
        $system = Get-SystemInfo 'Windows 11 Professionnel' '10.0 (26100)' ([datetime]'2026-01-01')
        $system.Short | Should -BeExactly 'Win 11 24H2'
        $system.Tip | Should -BeExactly 'Windows 11 Professionnel 10.0 (26100)'
        $system.Outdated | Should -BeFalse
        (Get-SystemInfo 'Windows 11 Professionnel' '10.0 (26100)' ([datetime]'2026-11-01')).Outdated | Should -BeTrue
    }

    It 'Says a known build past its end of support in an alert, and one near it as a warning' {
        $past = Get-BuildAlert 22621 'Windows 11 Professionnel'
        $past.Level | Should -BeExactly 'crit'
        $past.Message | Should -BeExactly "Windows 11 22H2 n'est plus supporté depuis le 2024-10-08."
    }

    It 'Shows a build newer than the table''s neutrally: named by its build, never out of support, no alert, and says Repère does not know it' {
        $release = Get-WindowsRelease $NewerBuild 'Windows 11 Professionnel'
        $release.Name | Should -BeExactly "Windows 11 (build $NewerBuild)"
        $release.End | Should -BeNullOrEmpty
        $release.Note | Should -BeExactly $UnknownNote
        # Even years from now: Repère can't say it's out of support.
        $system = Get-SystemInfo 'Windows 11 Professionnel' "10.0 ($NewerBuild)" ([datetime]'2040-01-01')
        $system.Short | Should -BeExactly "Win 11 (build $NewerBuild)"
        $system.Full | Should -BeExactly "Windows 11 Professionnel 10.0 ($NewerBuild)"
        $system.Tip | Should -BeExactly "Windows 11 Professionnel 10.0 ($NewerBuild)`n$UnknownNote"
        $system.Outdated | Should -BeFalse
        Get-BuildAlert $NewerBuild 'Windows 11 Professionnel' | Should -BeNullOrEmpty
    }

    It 'Says it under the build in Caractéristiques, for a computer whose release the table does not have' {
        (Get-PCSpec 'ord-01.demo.local').General.BuildNumber | Should -BeExactly '10.0.26200 (build 26200)'
        # ord-01 is on 26200: without it, the table's newest is older.
        $saved = $script:WindowsReleases[26200]
        $script:WindowsReleases.Remove(26200)
        try { $specs = Get-PCSpec 'ord-01.demo.local' }
        finally { $script:WindowsReleases[26200] = $saved }
        $specs.General.BuildNumber | Should -BeExactly "10.0.26200 (build 26200)`n$UnknownNote"
        @($specs.Alerts | Where-Object Field -eq 'BuildNumber') | Should -BeNullOrEmpty
    }

    It 'Takes a build older than the table''s oldest for a Windows 10 out of support, as before' {
        $release = Get-WindowsRelease 18363 'Windows 10 Professionnel'
        $release.Name | Should -BeExactly 'Windows 10 (build 18363)'
        $release.End | Should -Be ([datetime]'2025-10-14')
        $system = Get-SystemInfo 'Windows 10 Professionnel' '10.0 (18363)' ([datetime]'2026-01-01')
        $system.Short | Should -BeExactly 'Win 10 (build 18363)'
        $system.Outdated | Should -BeTrue
        $alert = Get-BuildAlert 18363 'Windows 10 Professionnel'
        $alert.Level | Should -BeExactly 'crit'
        $alert.Message | Should -BeExactly "Windows 10 (build 18363) n'est plus supporté depuis le 2025-10-14."
    }

    It 'Leaves a build between the table''s it does not know unnamed and unflagged, as before' {
        Get-WindowsRelease 22100 'Windows 11 Professionnel' | Should -BeNullOrEmpty
        $system = Get-SystemInfo 'Windows 11 Professionnel' '10.0 (22100)' ([datetime]'2026-01-01')
        $system.Short | Should -BeExactly 'Win 11 (build 22100)'
        $system.Outdated | Should -BeFalse
    }

    It 'Leaves LTSC and servers out, their support following other rules: <OSName>' -ForEach @(
        @{ OSName = 'Windows 10 Entreprise LTSC'; Version = '10.0 (17763)'; Build = 17763; Short = 'Win 10 (build 17763)' }
        @{ OSName = 'Windows 10 Enterprise LTSB'; Version = '10.0 (14393)'; Build = 14393; Short = 'Win 10 (build 14393)' }
        @{ OSName = 'Windows Server 2022 Standard'; Version = '10.0 (20348)'; Build = 20348; Short = 'Server 2022' }
    ) {
        Get-WindowsRelease $Build $OSName | Should -BeNullOrEmpty
        $system = Get-SystemInfo $OSName $Version ([datetime]'2040-01-01')
        $system.Short | Should -BeExactly $Short
        $system.Tip | Should -BeExactly "$OSName $Version"
        $system.Outdated | Should -BeFalse
        Get-BuildAlert $Build $OSName | Should -BeNullOrEmpty
    }

    It 'Says Windows 10 22H2 out of support, and that ESU keeps a computer enrolled in it up to date' {
        $alert = Get-BuildAlert 19045 'Windows 10 Professionnel'
        $alert.Level | Should -BeExactly 'crit'
        $alert.Message | Should -BeExactly "Windows 10 22H2 n'est plus supporté depuis le 2025-10-14. $EsuNote"
        $system = Get-SystemInfo 'Windows 10 Professionnel' '10.0 (19045)' ([datetime]'2026-01-01')
        $system.Short | Should -BeExactly 'Win 10 22H2'
        $system.Outdated | Should -BeTrue
        $system.Tip | Should -BeExactly "Windows 10 Professionnel 10.0 (19045)`n$EsuNote"
    }
}

Describe 'Caractéristiques from SCCM''s inventory (ConvertFrom-SccmInventory)' {
    BeforeAll {
        $script:Now = Get-Date
        function New-SccmRow([hashtable]$Values) { [pscustomobject]$Values }
        function New-SccmRead([hashtable]$Rows, [hashtable]$Failed = @{}, [int]$Count = 1, [string]$Answer = 'Found') {
            # Get-SccmSpec' answer: every section of SccmSections, read with these rows (none for one not given), or
            # failed with its reason.
            $inventory = [ordered]@{}
            foreach ($name in 'Scan', 'System', 'Bios', 'Windows', 'Network', 'Processor', 'Memory', 'Module', 'Disk', 'Volume', 'Program', 'Program64') {
                $inventory[$name] = if ($Failed.ContainsKey($name)) { @{ Read = $false; Reason = $Failed[$name]; Rows = @() } }
                                    else { @{ Read = $true; Reason = ''; Rows = @($Rows[$name] | Where-Object { $_ }) } }
            }
            @{ Answer = $Answer; Reason = ''; Count = $Count; Inventory = $inventory }
        }
        function Get-FullRow {
            @{
                Scan      = New-SccmRow @{ LastHardwareScan = $script:Now.AddDays(-3) }
                System    = New-SccmRow @{ Name = 'PC-7'; Domain = 'demo.local'; Manufacturer = 'Contoso'; Model = 'Bureau 5000'; UserName = 'DEMO\mroy' }
                Bios      = New-SccmRow @{ SerialNumber = 'SN-7'; SMBIOSBIOSVersion = '1.2'; ReleaseDate = [datetime]'2025-03-01' }
                Windows   = New-SccmRow @{ Caption = 'Microsoft Windows 10 Pro'; Version = '10.0.19045'; BuildNumber = '19045'; OSArchitecture = '64-bit'; LastBootUpTime = $script:Now.AddDays(-60) }
                Network   = @(
                    New-SccmRow @{ Description = 'Wi-Fi'; IPAddress = @('192.0.2.30'); MACAddress = 'AA'; DefaultIPGateway = $null; DNSServerSearchOrder = $null; Index = 1; IPEnabled = 1 }
                    New-SccmRow @{ Description = 'Ethernet'; IPAddress = @('192.0.2.7', 'fe80::7'); MACAddress = 'BB'; DefaultIPGateway = @('192.0.2.1'); DNSServerSearchOrder = @('192.0.2.2', '192.0.2.3'); Index = 2; IPEnabled = 1 }
                    New-SccmRow @{ Description = 'Off'; IPAddress = $null; MACAddress = 'CC'; DefaultIPGateway = $null; DNSServerSearchOrder = $null; Index = 3; IPEnabled = 0 }
                )
                Processor = New-SccmRow @{ Name = 'Contoso CPU 5 @ 3.10GHz'; Manufacturer = 'GenuineIntel'; MaxClockSpeed = 3100; NumberOfCores = 4; NumberOfLogicalProcessors = 8; Architecture = 9 }
                Memory    = New-SccmRow @{ TotalPhysicalMemory = 16777216 }
                Module    = @(
                    New-SccmRow @{ Capacity = 8192; Speed = 3200; MemoryType = 26; Manufacturer = 'Contoso'; PartNumber = 'M-8' }
                    New-SccmRow @{ Capacity = 8192; Speed = 3200; MemoryType = 26; Manufacturer = 'Contoso'; PartNumber = 'M-8' }
                )
                Disk      = New-SccmRow @{ Index = 0; Model = 'Contoso SSD'; Size = 488000; InterfaceType = 'SCSI' }
                Volume    = @(
                    New-SccmRow @{ DeviceID = 'C:'; DriveType = 3; Size = 100000; FreeSpace = 5000; VolumeName = 'Windows' }
                    New-SccmRow @{ DeviceID = 'E:'; DriveType = 2; Size = 1000; FreeSpace = 1000; VolumeName = 'USB' }
                )
                Program   = New-SccmRow @{ DisplayName = 'Contoso Agent'; Version = '3.1'; Publisher = 'Contoso'; InstallDate = '20260110' }
                Program64 = New-SccmRow @{ DisplayName = 'Contoso Office'; Version = '16.0'; Publisher = 'Contoso'; InstallDate = $null }
            }
        }
    }

    It 'Gives a live reading''s shape, from SCCM, dated by its last inventory' {
        $specs = ConvertFrom-SccmInventory (New-SccmRead (Get-FullRow)) 'PC-7'
        Get-PCSpecSource $specs | Should -BeExactly 'SCCM'
        $specs.Reachable | Should -BeTrue
        $specs.ScanDate | Should -Be $script:Now.AddDays(-3)
        @($specs.Missing) | Should -Be @('Monitor', 'Battery', 'Dock')
        $specs.Errors.Count | Should -Be 0
        $specs.General.ComputerName | Should -BeExactly 'PC-7'
        $specs.General.LoggedOnUser | Should -BeExactly 'DEMO\mroy'
        $specs.General.SerialNumber | Should -BeExactly 'SN-7'
        $specs.General.OSName | Should -BeExactly 'Windows 10 Pro'
        $specs.General.Build | Should -Be 19045
        $specs.General.UptimeDays | Should -BeNullOrEmpty
        $specs.General.Mobile | Should -BeNullOrEmpty
        $specs.Processor.Cores | Should -BeExactly '4 / 8'
        $specs.Processor.Vendor | Should -BeExactly 'Intel'
        $specs.Memory.Total | Should -BeExactly (Format-Byte (16GB))
        $specs.Memory.Type | Should -BeExactly 'DDR4'
        $specs.Memory.Physical | Should -BeExactly "2 × $(Format-Byte (8GB))"
        @($specs.Software.Programs.Name) | Should -Be @('Contoso Agent', 'Contoso Office')
    }

    It 'Takes the architecture from AddressWidth when the site has no Architecture: <Expected>' -ForEach @(
        @{ Width = 64; SystemType = 'x64-based PC'; Expected = 'x64' }
        @{ Width = 64; SystemType = 'ARM64-based PC'; Expected = 'ARM64' }
        @{ Width = 32; SystemType = $null; Expected = 'x86' }
        @{ Width = $null; SystemType = 'x64-based PC'; Expected = 'N/D' }
    ) {
        $rows = Get-FullRow
        $rows.Processor = New-SccmRow @{ Name = 'Contoso CPU 5'; Manufacturer = 'GenuineIntel'; MaxClockSpeed = 3100; NumberOfCores = 4; NumberOfLogicalProcessors = 8; Architecture = $null; AddressWidth = $Width }
        $rows.System | Add-Member SystemType $SystemType
        $specs = ConvertFrom-SccmInventory (New-SccmRead $rows) 'PC-7'
        $specs.Errors.Count | Should -Be 0
        $specs.Processor.Architecture | Should -BeExactly $Expected
    }

    It 'Takes the adapter with a gateway first, the others with their name, and leaves out those without an address' {
        $network = (ConvertFrom-SccmInventory (New-SccmRead (Get-FullRow)) 'PC-7').Network
        $network.IPAddress | Should -BeExactly "192.0.2.7`n192.0.2.30 (Wi-Fi)"
        $network.Adapter | Should -BeExactly 'Ethernet'
        $network.MAC | Should -BeExactly 'BB'
        $network.DNS | Should -BeExactly "192.0.2.2`n192.0.2.3"
        $network.FQDN | Should -BeExactly 'PC-7.demo.local'
    }

    It 'Reads addresses given as one text with commas, as some sites do' {
        $rows = Get-FullRow
        $rows.Network = New-SccmRow @{ Description = 'Ethernet'; IPAddress = '192.0.2.7, fe80::7'; MACAddress = 'BB'; DefaultIPGateway = '192.0.2.1'; DNSServerSearchOrder = '192.0.2.2, 192.0.2.3'; Index = 1; IPEnabled = 'True' }
        $network = (ConvertFrom-SccmInventory (New-SccmRead $rows) 'PC-7').Network
        $network.IPAddress | Should -BeExactly '192.0.2.7'
        $network.DNS | Should -BeExactly "192.0.2.2`n192.0.2.3"
    }

    It 'Puts the volumes on the disk when there''s one, and apart when there are several (SCCM doesn''t say which is where)' {
        $one = (ConvertFrom-SccmInventory (New-SccmRead (Get-FullRow)) 'PC-7').Disk
        @($one.Drives).Count | Should -Be 1
        @($one.Drives[0].Volumes.Drive) | Should -Be @('C:')
        $one.Drives[0].VolumesApart | Should -BeFalse
        $rows = Get-FullRow
        $rows.Disk = @((New-SccmRow @{ Index = 0; Model = 'A'; Size = 1000; InterfaceType = 'SCSI' }), (New-SccmRow @{ Index = 1; Model = 'B'; Size = 2000; InterfaceType = 'SCSI' }))
        $two = (ConvertFrom-SccmInventory (New-SccmRead $rows) 'PC-7').Disk
        @($two.Drives.Model) | Should -Be @('A', 'B', 'Volumes')
        $two.Drives[0].VolumesApart | Should -BeTrue
        @($two.Drives[2].Volumes.Drive) | Should -Be @('C:')
        $two.DiskCount | Should -Be 2
    }

    It 'Says a class that couldn''t be read as its section''s error, and reads the others' {
        $specs = ConvertFrom-SccmInventory (New-SccmRead (Get-FullRow) @{ Processor = 'accès refusé'; Bios = 'refusée' }) 'PC-7'
        $specs.Errors['Processor'] | Should -BeExactly 'accès refusé'
        $specs.Errors['General'] | Should -BeExactly 'refusée'
        $specs.Processor | Should -BeNullOrEmpty
        $specs.General | Should -BeNullOrEmpty
        $specs.Network | Should -Not -BeNullOrEmpty
        @($specs.Missing) | Should -Not -Contain 'Processor'
    }

    It 'Says a section whose classes are all empty isn''t in the inventory, not that it failed' {
        $rows = Get-FullRow
        $rows.Program = $null
        $rows.Program64 = $null
        $specs = ConvertFrom-SccmInventory (New-SccmRead $rows) 'PC-7'
        $specs.Software | Should -BeNullOrEmpty
        @($specs.Missing) | Should -Contain 'Software'
        $specs.Errors.Keys | Should -Not -Contain 'Software'
    }

    It 'Reads the total memory without the modules, which not every site collects' {
        $rows = Get-FullRow
        $rows.Module = $null
        $memory = (ConvertFrom-SccmInventory (New-SccmRead $rows @{ Module = 'classe inconnue' }) 'PC-7').Memory
        $memory.Total | Should -BeExactly (Format-Byte (16GB))
        $memory.Physical | Should -BeExactly 'N/D'
    }

    It 'Keeps the end of Windows'' support and a full disk, dated, and drops « not restarted », wrong by the inventory''s age' {
        $alerts = @((ConvertFrom-SccmInventory (New-SccmRead (Get-FullRow)) 'PC-7').Alerts)
        $date = Format-TextDate $script:Now.AddDays(-3) -Day
        @($alerts.Field) | Should -Be @('BuildNumber', 'Volume:C:')
        foreach ($alert in $alerts) { $alert.Message | Should -BeLike "* (inventaire du $date)" }
    }

    It 'Has no date when SCCM doesn''t say when it inventoried the computer' {
        $rows = Get-FullRow
        $rows.Scan = $null
        $specs = ConvertFrom-SccmInventory (New-SccmRead $rows) 'PC-7'
        $specs.ScanDate | Should -BeNullOrEmpty
        @($specs.Alerts).Count | Should -Be 2
        foreach ($alert in $specs.Alerts) { $alert.Message | Should -Not -BeLike '*inventaire du*' }
        $specs.ScanFailure | Should -BeExactly ''
        $lines = @((Format-PCSpecReport $specs) -split "`r?`n")
        $lines[0] | Should -BeLike 'Caractéristiques de PC-7 — inventaire SCCM sans date, lu le *'
        $lines[1] | Should -BeExactly "SCCM ne dit pas quand il l'a fait."
    }

    It 'Says why the date couldn''t be read, which is no section''s error' {
        $rows = Get-FullRow
        $rows.Scan = $null
        $specs = ConvertFrom-SccmInventory (New-SccmRead $rows @{ Scan = 'Accès refusé' }) 'PC-7'
        $specs.ScanDate | Should -BeNullOrEmpty
        $specs.ScanFailure | Should -BeExactly 'Accès refusé'
        $specs.Errors.Count | Should -Be 0
        $specs.General | Should -Not -BeNullOrEmpty
        $lines = @((Format-PCSpecReport $specs) -split "`r?`n")
        $lines[0] | Should -BeLike 'Caractéristiques de PC-7 — inventaire SCCM sans date, lu le *'
        $lines[1] | Should -BeExactly "La date de l'inventaire n'a pas été lue : Accès refusé."
        (Format-PCSpecReport $specs) | Should -Not -BeLike '*date inconnue*'
    }

    It 'Leaves out the empty rows SCCM may give, and says a section that isn''t in the answer wasn''t read' {
        $read = New-SccmRead (Get-FullRow)
        $read.Inventory.Program.Rows = @($null, (New-SccmRow @{ DisplayName = 'Contoso Agent'; Version = '3.1'; Publisher = 'Contoso'; InstallDate = '20260110' }), $null)
        $read.Inventory.Program64.Rows = @($null)
        $read.Inventory.Remove('Processor')
        $specs = ConvertFrom-SccmInventory $read 'PC-7'
        @($specs.Software.Programs.Name) | Should -Be @('Contoso Agent')
        $specs.Errors['Processor'] | Should -BeExactly "SCCM n'a pas été lu"
        $specs.Processor | Should -BeNullOrEmpty
    }

    It 'Says a section, or the date, that failed without a reason as failed all the same' {
        $read = New-SccmRead (Get-FullRow) @{ Disk = ''; Scan = '' }
        $specs = ConvertFrom-SccmInventory $read 'PC-7'
        $specs.Errors['Disk'] | Should -BeExactly "SCCM n'a pas dit pourquoi"
        $specs.Disk | Should -BeNullOrEmpty
        $specs.ScanFailure | Should -BeExactly "SCCM n'a pas dit pourquoi"
    }

    It 'Is Doubtful when the record may be another computer''s, even alone, and the report says so' -ForEach @(
        @{ Answer = 'Found'; Count = 1; Doubtful = $false; Line = $null }
        @{ Answer = 'Ambiguous'; Count = 1; Doubtful = $true; Line = "Repère n'est pas sûr que cette fiche SCCM soit celle de cet ordinateur." }
        @{ Answer = 'Ambiguous'; Count = 2; Doubtful = $true; Latest = $true; Skipped = ''; Line = 'SCCM a 2 fiches qui peuvent être cet ordinateur : voici la plus récente.' }
        @{ Answer = 'Ambiguous'; Count = 2; Doubtful = $true; Latest = $false; Skipped = 'Empty'; Line = 'SCCM a 2 fiches qui peuvent être cet ordinateur : voici la plus récente qui a un inventaire.' }
        @{ Answer = 'Ambiguous'; Count = 2; Doubtful = $true; Latest = $false; Skipped = 'Unread'; Line = 'SCCM a 2 fiches qui peuvent être cet ordinateur : la plus récente n''a pas pu être lue, voici la suivante qui a un inventaire.' }
    ) {
        $read = New-SccmRead (Get-FullRow) -Count $Count -Answer $Answer
        # Without Latest, as before Get-SccmSpec gave it: the latest.
        if ($Count -gt 1) { $read.Latest, $read.LatestSkipped = $Latest, $Skipped }
        $specs = ConvertFrom-SccmInventory $read 'PC-7'
        $specs.Doubtful | Should -Be $Doubtful
        $specs.Candidates | Should -Be $Count
        $lines = @((Format-PCSpecReport $specs) -split "`r?`n")
        $said = @($lines | Where-Object { $_ -match 'fiche' })
        if ($Line) { $said | Should -Be @($Line) } else { $said | Should -BeNullOrEmpty }
    }

    It 'Says in the report where it comes from, the last user, what isn''t inventoried, and the records it may be' {
        $report = Format-PCSpecReport (ConvertFrom-SccmInventory (New-SccmRead (Get-FullRow) -Count 2 -Answer 'Ambiguous') 'PC-7')
        $lines = @($report -split "`r?`n")
        $lines[0] | Should -BeLike "Caractéristiques de PC-7 — inventaire SCCM du $(Format-TextDate $script:Now.AddDays(-3) -Day), lu le *"
        $lines | Should -Contain 'SCCM a 2 fiches qui peuvent être cet ordinateur : voici la plus récente.'
        $lines | Should -Contain "Pas dans l'inventaire SCCM : Écrans, Batterie, Station d'accueil."
        $lines | Should -Contain '  Dernier utilisateur : DEMO\mroy'
        $lines | Should -Not -Contain '[Écrans]'
    }

    It 'Leaves a live reading''s report as it was' {
        $report = Format-PCSpecReport (Get-PCSpec 'ord-01.demo.local')
        Get-PCSpecSource (Get-PCSpec 'ord-01.demo.local') | Should -BeExactly 'Live'
        $report | Should -Not -BeLike '*SCCM*'
        $report | Should -BeLike '*Utilisateur connecté : *'
    }
}

Describe 'How old an SCCM inventory is (Get-SccmScanAge)' {
    It 'Is <Level> after <Age> days, with an inventory every 7 days' -ForEach @(
        @{ Age = 0; Level = 'info'; Text = "aujourd'hui" }
        @{ Age = 1; Level = 'info'; Text = 'hier' }
        @{ Age = 14; Level = 'info'; Text = 'il y a 14 jours' }
        @{ Age = 15; Level = 'warn'; Text = 'il y a 15 jours' }
        @{ Age = 28; Level = 'warn'; Text = 'il y a 28 jours' }
        @{ Age = 29; Level = 'crit'; Text = 'il y a 29 jours' }
    ) {
        $now = [datetime]'2026-11-26T12:00:00'
        $age = Get-SccmScanAge $now.AddDays(-$Age) 7 $now
        $age.Level | Should -BeExactly $Level
        $age.Text | Should -BeExactly $Text
    }

    It 'Follows how often the site inventories computers' {
        $now = [datetime]'2026-11-26T12:00:00'
        (Get-SccmScanAge $now.AddDays(-15) 30 $now).Level | Should -BeExactly 'info'
        (Get-SccmScanAge $now.AddDays(-3) 1 $now).Level | Should -BeExactly 'warn'
    }

    It 'Is very old when SCCM doesn''t say when' {
        (Get-SccmScanAge $null 7).Level | Should -BeExactly 'crit'
    }
}
