# Clés BitLocker…: which key of each disk is the newest, the one Sélectionner les anciennes leaves unticked
# (BitLockerDialog.ps1), as Get-BitLockerKey reads and sorts the keys (ComputerActions.ps1). The window itself is
# tested by Test-RepereUI.ps1's BitLocker session.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')

    # ComputerActions.ps1 loads only with the window: the functions alone, from its source.
    $actions = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerActions.ps1')
    foreach ($name in 'Get-BitLockerKey', 'Format-BitLockerKey') {
        $definition = $actions.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    # AD's command, for the tests to mock: neither the fake AD nor the real one is loaded here.
    function Get-ADObject { param([string]$Server, [string]$Filter, [string]$SearchBase, [string]$SearchScope, [string[]]$Properties) }

    $script:Computer = 'CN=ORD-50,OU=Postes,DC=demo,DC=local'
    $script:VolumeC = ([guid]'5A0C3E91-2B7D-4F18-9C6A-0E4D8B1F7A23').ToByteArray()

    function New-TestKey([string]$Date, [string]$Id, $Volume) {
        # A key as AD has it under the computer: named after its date and ID, its volume as 16 bytes or none.
        [pscustomobject]@{
            Name                     = "$Date{$Id}"
            ObjectClass              = 'msFVE-RecoveryInformation'
            'msFVE-RecoveryPassword' = '111111-222222-333333-444444-555555-666666-777777-888888'
            'msFVE-VolumeGuid'       = $Volume
            DistinguishedName        = "CN=$Date{$Id},$script:Computer"
        }
    }

    function Get-TestRow($Keys) {
        # The window's rows for one computer whose keys are $Keys, as Clés BitLocker… shows them.
        $script:TestKeys = $Keys
        Mock Get-ADObject { $script:TestKeys }
        $rows = (Read-BitLockerRow @([pscustomobject]@{ ComputerName = 'ORD-50'; DistinguishedName = $script:Computer; Domain = 'demo.local' })).Rows
        Update-BitLockerStatus $rows
        , $rows
    }
}

Describe 'Clés BitLocker: the newest key of each disk' {
    It "Counts each key whose volume AD doesn't say as a disk of its own, never an old key" {
        $rows = Get-TestRow @(
            New-TestKey '2026-01-15T09:30:00-05:00' '6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61' $script:VolumeC
            New-TestKey '2024-03-02T11:05:00-05:00' 'A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54' $script:VolumeC
            New-TestKey '2009-05-10T08:00:00-04:00' '11111111-0000-0000-0000-000000000001' $null
            New-TestKey '2010-02-20T15:45:00-05:00' '22222222-0000-0000-0000-000000000002' ([byte[]](1, 2, 3))
        )
        # Sélectionner les anciennes ticks the keys that aren't Latest: only C:'s 2024 one.
        @($rows | Where-Object { -not $_.Latest } | ForEach-Object KeyId) | Should -Be @('A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54')
        @($rows | ForEach-Object { "$($_.DiskNumber)/$($_.DiskCount) $($_.KeyId.Split('-')[0])" }) | Should -Be @(
            '1/3 6F1C2E7A', '1/3 A2E47C19', '2/3 22222222', '3/3 11111111'
        )
    }

    It 'Shows each key without a volume in a card of its own, marked Volume inconnu' {
        $state = @{
            Rows   = Get-TestRow @(
                New-TestKey '2009-05-10T08:00:00-04:00' '11111111-0000-0000-0000-000000000001' $null
                New-TestKey '2010-02-20T15:45:00-05:00' '22222222-0000-0000-0000-000000000002' $null
            )
            Notes  = @()
            Sought = $null
        }
        $xaml = Get-BitLockerBodyXaml $state
        ([regex]::Matches($xaml, [regex]::Escape('Style="{StaticResource Card}"'))).Count | Should -Be 2
        # Its text escaped as the code's own (&#86;olume inconnu), which ConvertTo-LocalXaml leaves as it is.
        ([regex]::Matches($xaml, 'Text="&#86;olume inconnu"')).Count | Should -Be 2
        @($state.Rows | Where-Object Latest).Count | Should -Be 2
    }

    It "Counts a key whose name isn't a date as a disk of its own, shown last and never an old key" {
        $rows = Get-TestRow @(
            New-TestKey 'pas une date' 'CCCCCCCC-0000-0000-0000-000000000003' $script:VolumeC
            New-TestKey '2026-01-15T09:30:00-05:00' '6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61' $script:VolumeC
            New-TestKey '2024-03-02T11:05:00-05:00' 'A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54' $script:VolumeC
        )
        # Sélectionner les anciennes ticks the keys that aren't Latest: only C:'s 2024 one.
        @($rows | Where-Object { -not $_.Latest } | ForEach-Object KeyId) | Should -Be @('A2E47C19-5D3B-4F60-B8E1-7C9A0D2F6E54')
        @($rows | ForEach-Object { "$($_.DiskNumber)/$($_.DiskCount) $($_.Latest) $($_.KeyId.Split('-')[0])" }) | Should -Be @(
            '1/2 True 6F1C2E7A', '1/2 False A2E47C19', '2/2 True CCCCCCCC'
        )
    }

    It 'Takes the later of two keys saved in the same minute, seconds apart, as the newest' {
        $rows = Get-TestRow @(
            New-TestKey '2026-03-04T10:15:05-05:00' 'AAAAAAAA-0000-0000-0000-000000000001' $script:VolumeC
            New-TestKey '2026-03-04T10:15:50-05:00' 'BBBBBBBB-0000-0000-0000-000000000002' $script:VolumeC
        )
        @($rows | ForEach-Object { "$($_.Latest) $($_.KeyId.Split('-')[0])" }) | Should -Be @('True BBBBBBBB', 'False AAAAAAAA')
    }

    It 'Takes the later key as the newest across the autumn change of time, whatever the local time says' {
        # 01:10 EST is 06:10 UTC, 40 minutes after 01:30 EDT (05:30 UTC), though its local hour reads earlier.
        $rows = Get-TestRow @(
            New-TestKey '2025-11-02T01:10:00-05:00' 'BBBBBBBB-0000-0000-0000-000000000002' $script:VolumeC
            New-TestKey '2025-11-02T01:30:00-04:00' 'AAAAAAAA-0000-0000-0000-000000000001' $script:VolumeC
        )
        @($rows | ForEach-Object { "$($_.Latest) $($_.KeyId.Split('-')[0])" }) | Should -Be @('True BBBBBBBB', 'False AAAAAAAA')
    }
}

Describe 'Get-BitLockerKey' {
    It "Reads each key's moment in UTC, seconds kept, and keeps its date as text for a spreadsheet" {
        Mock Get-ADObject { New-TestKey '2026-03-04T10:15:50-05:00' 'BBBBBBBB-0000-0000-0000-000000000002' $script:VolumeC }
        $key = Get-BitLockerKey $script:Computer 'demo.local'
        $key.When | Should -Be ([datetimeoffset]'2026-03-04T15:15:50+00:00')
        $key.When.Offset | Should -Be ([timespan]::Zero)
        $key.Date | Should -BeExactly ([datetimeoffset]'2026-03-04T10:15:50-05:00').LocalDateTime.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
        $key.VolumeId | Should -Be '5a0c3e91-2b7d-4f18-9c6a-0e4d8b1f7a23'
    }

    It 'Gives a name that is not a date no moment, its text kept as its date' {
        Mock Get-ADObject { New-TestKey 'pas une date' 'CCCCCCCC-0000-0000-0000-000000000003' $script:VolumeC }
        $key = Get-BitLockerKey $script:Computer 'demo.local'
        $key.When | Should -Be ([datetimeoffset]::MinValue)
        $key.Date | Should -BeExactly 'pas une date'
        $key.KeyId | Should -BeExactly 'CCCCCCCC-0000-0000-0000-000000000003'
    }

    It "Lists Supprimer de l'AD's keys newest first, to the second" {
        $script:TestKeys = @(
            New-TestKey '2026-03-04T10:15:05-05:00' 'AAAAAAAA-0000-0000-0000-000000000001' $script:VolumeC
            New-TestKey '2026-03-04T10:15:50-05:00' 'BBBBBBBB-0000-0000-0000-000000000002' $script:VolumeC
        )
        Mock Get-ADObject { $script:TestKeys }
        $text = Format-BitLockerKey @([pscustomobject]@{ ComputerName = 'ORD-50'; DistinguishedName = $script:Computer; Domain = 'demo.local' })
        $text.IndexOf('BBBBBBBB') | Should -BeLessThan $text.IndexOf('AAAAAAAA')
    }
}