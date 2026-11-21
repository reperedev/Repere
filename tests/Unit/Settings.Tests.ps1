# What Repère keeps from one launch to the next, read back as it opens: the main window's size and place
# (fenetre.json), and the other windows kept within their screen's work area; the Utilisateurs and Groupes pages'
# search and recent searches (recherche.json); the names a
# Liste de noms search reads; and whether GitHub's latest release is newer than this Repère.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    # Two screens side by side, 1920 × 1080 each.
    $script:Screens = [System.Windows.Rect]::new(0, 0, 3840, 1080)
}

Describe 'Get-WindowPlacement' {
    BeforeAll {
        # The work area of the second screen, right of the main one, its taskbar taking the bottom 48.
        $script:Area = [System.Windows.Rect]::new(1920, 0, 1920, 1032)
        function Get-Placed($Saved) {
            $placement = Get-WindowPlacement $Saved $Area 1180 760 1100 520
            "$($placement.Left) $($placement.Top) $($placement.Width) $($placement.Height) $($placement.Maximized)"
        }
    }

    It 'Opens centered on the screen it was launched on, at its saved size, wherever it was closed' {
        Get-Placed ([pscustomobject]@{ Left = 10; Top = 10; Width = 1300; Height = 800 }) | Should -BeExactly '2230 116 1300 800 False'
    }

    It 'Opens maximized when it was closed maximized' {
        Get-Placed ([pscustomobject]@{ Width = 1300; Height = 800; Maximized = $true }) | Should -BeExactly '2230 116 1300 800 True'
    }

    It 'Is at least its minimum size, and at most the work area' {
        Get-Placed ([pscustomobject]@{ Width = 600; Height = 5000 }) | Should -BeExactly '2330 0 1100 1032 False'
    }

    It 'Reads the numbers as JSON writes them, whatever the culture' {
        Get-Placed ('{"Width":1300.5,"Height":800}' | ConvertFrom-Json) | Should -BeExactly '2229.75 116 1300.5 800 False'
    }

    It 'Opens at its default size when <Case>' -ForEach @(
        @{ Case = 'nothing was saved'; Saved = $null }
        @{ Case = 'a size is missing'; Saved = [pscustomobject]@{ Width = 1300 } }
        @{ Case = 'a size is not a number'; Saved = [pscustomobject]@{ Width = 'grand'; Height = 800 } }
        @{ Case = 'a size is zero'; Saved = [pscustomobject]@{ Width = 0; Height = 800 } }
    ) {
        Get-Placed $Saved | Should -BeExactly '2290 136 1180 760 False'
    }
}

Describe 'Get-RectInArea: a window kept above the taskbar' {
    BeforeAll {
        # A 1920 × 1080 screen whose taskbar takes the bottom 48.
        $script:Area = [System.Windows.Rect]::new(0, 0, 1920, 1032)
    }

    It '<Case>' -ForEach @(
        @{ Case = 'Leaves alone a window within the work area'; Rect = 100, 100, 880, 800; Expected = '100 100 880 800' }
        @{ Case = 'Moves up a window whose bottom is under the taskbar'; Rect = 100, 300, 880, 800; Expected = '100 232 880 800' }
        @{ Case = 'Moves left a window past the right edge'; Rect = 1500, 100, 880, 800; Expected = '1040 100 880 800' }
        @{ Case = 'Moves down and right a window above or left of the screen, its title bar back in reach'; Rect = -50, -20, 880, 800; Expected = '0 0 880 800' }
        @{ Case = 'Shrinks a window taller than the work area, at its top'; Rect = 100, 40, 880, 1200; Expected = '100 0 880 1032' }
    ) {
        $fit = Get-RectInArea ([System.Windows.Rect]::new($Rect[0], $Rect[1], $Rect[2], $Rect[3])) $Area
        "$($fit.Left) $($fit.Top) $($fit.Width) $($fit.Height)" | Should -BeExactly $Expected
    }

    It 'Keeps to a second screen, left of the main one or above it' {
        $fit = Get-RectInArea ([System.Windows.Rect]::new(-1000, -500, 880, 800)) ([System.Windows.Rect]::new(-1280, -1024, 1280, 984))
        "$($fit.Left) $($fit.Top)" | Should -BeExactly '-1000 -840'
    }
}

Describe 'Get-ScreenWorkArea' {
    It 'Is the main screen''s work area for a window on it, and without a place yet' {
        $main = [System.Windows.SystemParameters]::WorkArea
        $inside = [System.Windows.Rect]::new($main.Left + 10, $main.Top + 10, 200, 100)
        foreach ($rect in $inside, [System.Windows.Rect]::Empty, [System.Windows.Rect]::new([double]::NaN, [double]::NaN, 880, 800)) {
            $area = Get-ScreenWorkArea $rect
            "$([int]$area.Left) $([int]$area.Top) $([int]$area.Width) $([int]$area.Height)" | Should -BeExactly "$([int]$main.Left) $([int]$main.Top) $([int]$main.Width) $([int]$main.Height)"
        }
    }
}

Describe 'Get-CursorWorkArea' {
    It 'Is the main screen''s work area for a pointer on it' {
        $main = [System.Windows.SystemParameters]::WorkArea
        $area = Get-CursorWorkArea @(10, 10)
        "$([int]$area.Left) $([int]$area.Top) $([int]$area.Width) $([int]$area.Height)" | Should -BeExactly "$([int]$main.Left) $([int]$main.Top) $([int]$main.Width) $([int]$main.Height)"
    }

    It 'Is a screen''s work area without a pointer read (where it is now)' {
        (Get-CursorWorkArea $null).Width | Should -BeGreaterThan 0
    }
}

Describe 'Get-NewerRelease' {
    It 'Names a newer release: <Tag>' -ForEach @(
        @{ Tag = 'v0.10.0'; Expected = '0.10.0' }
        @{ Tag = '0.9.3'; Expected = '0.9.3' }
        @{ Tag = 'v1.0.0'; Expected = '1.0.0' }
    ) {
        $release = Get-NewerRelease ([pscustomobject]@{ tag_name = $Tag; html_url = "https://github.com/reperedev/Repere/releases/tag/$Tag" }) '0.9.2'
        "$($release.Version) $($release.Url)" | Should -BeExactly "$Expected https://github.com/reperedev/Repere/releases/tag/$Tag"
    }

    It 'Says nothing for <Case>' -ForEach @(
        @{ Case = 'this version'; Release = @{ tag_name = 'v0.9.2'; html_url = 'https://github.com/reperedev/Repere/releases/tag/v0.9.2' } }
        @{ Case = 'an older one'; Release = @{ tag_name = 'v0.9.1'; html_url = 'https://github.com/reperedev/Repere/releases/tag/v0.9.1' } }
        @{ Case = 'a tag that isn''t a version'; Release = @{ tag_name = 'nightly'; html_url = 'https://github.com/reperedev/Repere/releases/tag/nightly' } }
        @{ Case = 'a page outside GitHub'; Release = @{ tag_name = 'v9.0.0'; html_url = 'https://example.com/repere' } }
        @{ Case = 'an answer without them'; Release = @{ message = 'API rate limit exceeded' } }
    ) {
        Get-NewerRelease ([pscustomobject]$Release) '0.9.2' | Should -BeNullOrEmpty
    }
}

Describe 'Read-ReleaseCheck and Save-ReleaseCheck: GitHub asked once a day' {
    BeforeAll {
        $script:CheckPath = Join-Path ([System.IO.Path]::GetTempPath()) "repere-version-$PID.json"
        $script:Saved = [datetime]::new(2026, 10, 28, 9, 0, 0, [System.DateTimeKind]::Utc)
    }
    AfterAll { Remove-Item -LiteralPath $script:CheckPath -ErrorAction SilentlyContinue }

    It 'Gives back the answer saved, the same day' {
        Save-ReleaseCheck $CheckPath ([pscustomobject]@{ tag_name = 'v0.10.0'; html_url = 'https://github.com/reperedev/Repere/releases/tag/v0.10.0'; other = 1 }) $Saved
        $check = Read-ReleaseCheck $CheckPath $Saved.AddHours(23)
        "$($check.tag_name) $($check.html_url)" | Should -BeExactly 'v0.10.0 https://github.com/reperedev/Repere/releases/tag/v0.10.0'
    }

    It 'Asks again <Case>' -ForEach @(
        @{ Case = 'a day later'; Hours = 24 }
        @{ Case = 'when the clock went back'; Hours = -1 }
    ) {
        Save-ReleaseCheck $CheckPath ([pscustomobject]@{ tag_name = 'v0.10.0'; html_url = 'https://github.com/x' }) $Saved
        Read-ReleaseCheck $CheckPath $Saved.AddHours($Hours) | Should -BeNullOrEmpty
    }

    It 'Asks again when nothing was saved, or it can''t be read' {
        Remove-Item -LiteralPath $CheckPath -ErrorAction SilentlyContinue
        Read-ReleaseCheck $CheckPath $Saved | Should -BeNullOrEmpty
        Set-Content -LiteralPath $CheckPath -Value '{ pas du json' -Encoding utf8
        Read-ReleaseCheck $CheckPath $Saved | Should -BeNullOrEmpty
    }

    It 'Asks again when the file holds « <Text> » (a write cut short)' -ForEach @(
        @{ Text = '' }
        @{ Text = 'null' }
        @{ Text = '[]' }
        @{ Text = '42' }
    ) {
        Set-Content -LiteralPath $CheckPath -Value $Text -Encoding utf8 -NoNewline
        Read-ReleaseCheck $CheckPath $Saved | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-ComputerNameList' {
    It 'Reads « <Text> » as <Expected>' -ForEach @(
        @{ Text = 'ORD-01 ORD-04'; Expected = 'ORD-01|ORD-04' }
        @{ Text = 'ORD-01, ord-04;ORD-07'; Expected = 'ORD-01|ord-04|ORD-07' }
        @{ Text = "ORD-01`r`nORD-04`r`n`r`n"; Expected = 'ORD-01|ORD-04' }
        # Once each, whatever its case: the first spelling.
        @{ Text = 'ORD-01 ord-01 ORD-01'; Expected = 'ORD-01' }
        # A domain or the account's $ left out.
        @{ Text = 'DEMO\ORD-01 ord-04.demo.local ORD-07$'; Expected = 'ORD-01|ord-04|ORD-07' }
    ) {
        (ConvertTo-ComputerNameList $Text) -join '|' | Should -BeExactly $Expected
    }

    It 'Finds no name in « <Text> »' -ForEach @(
        @{ Text = '' }
        @{ Text = ' , ; ' }
    ) {
        @(ConvertTo-ComputerNameList $Text).Count | Should -Be 0
    }
}

Describe 'ConvertTo-SearchAddress: Adresse IP searches a whole address only (#163)' {
    It 'Searches « <Text> » as <Expected>' -ForEach @(
        @{ Text = '10.0.1.14'; Expected = '10.0.1.14' }
        @{ Text = '  10.0.1.14 '; Expected = '10.0.1.14' }
        # Leading zeros are decimal, not octal.
        @{ Text = '010.000.001.014'; Expected = '10.0.1.14' }
        @{ Text = '10.0.1.0'; Expected = '10.0.1.0' }
        @{ Text = 'FD00:10::11'; Expected = 'fd00:10::11' }
        @{ Text = '::1'; Expected = '::1' }
    ) {
        $parsed = ConvertTo-SearchAddress $Text
        "$($parsed.Address)|$($parsed.Problem)" | Should -BeExactly "$Expected|"
    }

    # .NET would read the first ones as 255.255.0.255, 10.0.0.1 and 0.0.0.10: another address than the one meant.
    It 'Refuses the start of an address or a range, « <Text> », as incomplete' -ForEach @(
        @{ Text = '255.255.255' }
        @{ Text = '10.1' }
        @{ Text = '10' }
        @{ Text = '10.0.1.' }
        @{ Text = '10.0.' }
        @{ Text = '10.0.1.*' }
        @{ Text = '10.0.*' }
        @{ Text = '10.0.1.0/24' }
        @{ Text = '10.0.1.1-20' }
    ) {
        $parsed = ConvertTo-SearchAddress $Text
        "$($parsed.Address)|$($parsed.Problem)" | Should -BeExactly '|Incomplete'
    }

    It 'Refuses « <Text> », which is not an address' -ForEach @(
        @{ Text = '' }
        @{ Text = 'accueil' }
        @{ Text = 'ORD-01' }
        @{ Text = '10.0.1.300' }
        @{ Text = '10.0.1.14.5' }
        @{ Text = '10..1.14' }
        @{ Text = '1000.0.1.14' }
        @{ Text = 'fd00::10::11' }
    ) {
        $parsed = ConvertTo-SearchAddress $Text
        "$($parsed.Address)|$($parsed.Problem)" | Should -BeExactly '|Invalid'
    }
}

Describe 'ConvertTo-UserEntryList and ConvertTo-GroupEntryList' {
    It 'Users: reads « <Text> » as <Expected>' -ForEach @(
        @{ Text = 'jbertrand lperrin'; Expected = 'jbertrand|lperrin' }
        @{ Text = 'jbertrand, LPerrin@demo.local,  DEMO\mdurand'; Expected = 'jbertrand|LPerrin@demo.local|mdurand' }
        # One per line or between semicolons: whole, so a display name stays one.
        @{ Text = "Jean Bertrand`r`njbertrand`r`n`r`n"; Expected = 'Jean Bertrand|jbertrand' }
        @{ Text = 'Jean Bertrand; lperrin ;'; Expected = 'Jean Bertrand|lperrin' }
        # As Outlook copies its addresses: their emails.
        @{ Text = '"Bertrand, Julie" <jbertrand@demo.local>; Léa Perrin <lperrin@demo.local>'; Expected = 'jbertrand@demo.local|lperrin@demo.local' }
        @{ Text = 'Léa Perrin <lperrin@demo.local>'; Expected = 'lperrin@demo.local' }
        # On one line, with commas: each address, even with a comma in its name.
        @{ Text = '"Bertrand, Julie" <jbertrand@demo.local>, Léa Perrin <lperrin@demo.local>'; Expected = 'jbertrand@demo.local|lperrin@demo.local' }
        # On one line, between commas: whole entries, so display names stay whole.
        @{ Text = 'Jean Bertrand, Léa Perrin'; Expected = 'Jean Bertrand|Léa Perrin' }
        # Once each, whatever its case: the first spelling.
        @{ Text = 'jbertrand JBERTRAND demo\jbertrand'; Expected = 'jbertrand' }
    ) {
        (ConvertTo-UserEntryList $Text) -join '|' | Should -BeExactly $Expected
    }

    It 'Groups: reads « <Text> » as <Expected>' -ForEach @(
        @{ Text = 'GG-Accueil; GG-VPN'; Expected = 'GG-Accueil|GG-VPN' }
        @{ Text = "Utilisateurs du domaine`r`nDEMO\GG-VPN`r`ngg-vpn"; Expected = 'Utilisateurs du domaine|GG-VPN' }
        # On one line, between commas, as pasted from an email; never between spaces.
        @{ Text = 'GG-Accueil, GG-VPN'; Expected = 'GG-Accueil|GG-VPN' }
        @{ Text = 'Admins du domaine, Utilisateurs du domaine,'; Expected = 'Admins du domaine|Utilisateurs du domaine' }
        @{ Text = 'Admins du domaine'; Expected = 'Admins du domaine' }
    ) {
        (ConvertTo-GroupEntryList $Text) -join '|' | Should -BeExactly $Expected
    }

    It 'Finds no entry in « <Text> »' -ForEach @(
        @{ Text = '' }
        @{ Text = ' , ; ' }
        @{ Text = "`r`n ; `"`" " }
    ) {
        @(ConvertTo-UserEntryList $Text).Count | Should -Be 0
        @(ConvertTo-GroupEntryList $Text).Count | Should -Be 0
    }
}

Describe 'A page''s search as recherche.json keeps it' {
    BeforeAll {
        $script:showDomains = $true
        $script:Page = @{ Types = $script:UserSearchTypes }
    }

    It 'ConvertFrom-SavedPageSearch keeps what it knows, and 10 recent searches at most' {
        $recent = @(1..12 | ForEach-Object { [pscustomobject]@{ Domain = 'demo.local'; Type = 'Name'; Text = "nom$_"; Other = 1 } })
        $setting = ConvertFrom-SavedPageSearch ([pscustomobject]@{ Domain = '*'; Type = 'Locked'; Recent = $recent; Other = 1 })
        "$($setting.Domain) $($setting.Type) $($setting.Recent.Count) $($setting.Recent[0].Text) $($setting.Recent[0].Keys -join ',')" |
            Should -BeExactly '* Locked 10 nom1 Domain,Type,Text'
    }

    It 'ConvertFrom-SavedPageSearch: none saved is none' {
        ConvertFrom-SavedPageSearch $null | Should -BeNullOrEmpty
    }

    It 'Format-PageRecent: <Expected>' -ForEach @(
        # Each search type in words, the first one too, as the computers' recent searches say theirs.
        @{ Entry = @{ Domain = 'demo.local'; Type = 'Name'; Text = 'bert' }; Expected = 'Nom, identifiant ou courriel « bert »  —  demo.local' }
        @{ Entry = @{ Domain = '*'; Type = 'Locked'; Text = '' }; Expected = 'Verrouillés  —  Tous les domaines' }
        # A type that needs no text: what its box was given narrows it down by name.
        @{ Entry = @{ Domain = '*'; Type = 'Disabled'; Text = 'bert' }; Expected = 'Désactivés · Nom « bert »  —  Tous les domaines' }
        @{ Entry = @{ Domain = 'demo.local'; Type = 'Description'; Text = 'sauvegarde' }; Expected = 'Description contient « sauvegarde »  —  demo.local' }
        # A list: its first entries, then how many more.
        @{ Entry = @{ Domain = '*'; Type = 'List'; Text = 'jbertrand, lperrin, mdurand, srey, nlevy' }; Expected = 'liste : jbertrand, lperrin, mdurand (+2)  —  Tous les domaines' }
    ) {
        Format-PageRecent $Page $Entry | Should -BeExactly $Expected
    }

    It 'Format-PageRecent, the groups'' search types: <Expected>' -ForEach @(
        @{ Entry = @{ Domain = 'demo.local'; Type = 'Name'; Text = 'vpn' }; Expected = 'Nom contient « vpn »  —  demo.local' }
        @{ Entry = @{ Domain = 'demo.local'; Type = 'Empty'; Text = 'GG' }; Expected = 'Sans membres · Nom « GG »  —  demo.local' }
    ) {
        Format-PageRecent @{ Types = $script:GroupSearchTypes } $Entry | Should -BeExactly $Expected
    }

    It 'Format-PageRecent: no domain said when only one is offered' {
        $script:showDomains = $false
        try { Format-PageRecent $Page @{ Domain = 'demo.local'; Type = 'Locked'; Text = '' } | Should -BeExactly 'Verrouillés' }
        finally { $script:showDomains = $true }
    }

    It 'Format-PageRecent: nothing for a search type this version doesn''t have' {
        Format-PageRecent $Page @{ Domain = 'demo.local'; Type = 'Gone'; Text = 'x' } | Should -BeNullOrEmpty
    }
}

Describe 'Read-JsonSetting and Save-JsonSetting: every settings file read and written the same way' {
    BeforeEach {
        # A folder of the test's own, new for each test (TestDrive).
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid())
        $script:File = Join-Path $script:Folder 'Repere\essai.json'
    }

    It 'Saves a file in a folder that doesn''t exist yet, and reads back only the settings asked for' {
        Save-JsonSetting $File ([ordered]@{ Amount = 5; Unit = 'minutes'; Other = 'x' })
        $saved = Read-JsonSetting $File Amount, Unit, Missing
        "$($saved.Amount) $($saved.Unit) [$($saved.Missing)]" | Should -BeExactly '5 minutes []'
        @($saved.PSObject.Properties.Name) | Should -Be @('Amount', 'Unit', 'Missing')
    }

    It 'Reads every setting when none is named' {
        Save-JsonSetting $File ([ordered]@{ A = 1; B = 2 })
        @((Read-JsonSetting $File).PSObject.Properties.Name) | Should -Be @('A', 'B')
    }

    It 'Gives nothing, and says nothing, for a file that <Case>' -ForEach @(
        @{ Case = 'is missing'; Text = $null }
        @{ Case = 'is empty'; Text = '' }
        @{ Case = 'holds null'; Text = 'null' }
    ) {
        if ($null -ne $Text) {
            $null = New-Item -ItemType Directory -Force -Path (Split-Path $File)
            Set-Content -LiteralPath $File -Value $Text -Encoding utf8
        }
        Mock Write-Host { }
        Read-JsonSetting $File Amount | Should -BeNullOrEmpty
        Should -Invoke Write-Host -Times 0
    }

    It 'Gives nothing for a file that can''t be read, and says so' {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $File)
        Set-Content -LiteralPath $File -Value '{ "Amount": 5,' -Encoding utf8
        Mock Write-Host { }
        Read-JsonSetting $File Amount | Should -BeNullOrEmpty
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -like 'essai.json illisible, valeurs par défaut : *' }
    }

    It '-Unreadable tells a file that''s there but can''t be read from one that''s missing, empty or read' {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $File)
        Mock Write-Host { }
        $unreadable = $true
        $null = Read-JsonSetting $File -Unreadable ([ref]$unreadable)
        $unreadable | Should -BeFalse
        Set-Content -LiteralPath $File -Value '' -Encoding utf8
        $unreadable = $true
        $null = Read-JsonSetting $File -Unreadable ([ref]$unreadable)
        $unreadable | Should -BeFalse
        Set-Content -LiteralPath $File -Value '{ "Amount": 5 }' -Encoding utf8
        (Read-JsonSetting $File Amount -Unreadable ([ref]$unreadable)).Amount | Should -Be 5
        $unreadable | Should -BeFalse
        Set-Content -LiteralPath $File -Value '{ "Amount": 5,' -Encoding utf8
        Read-JsonSetting $File Amount -Unreadable ([ref]$unreadable) | Should -BeNullOrEmpty
        $unreadable | Should -BeTrue
        # Kept for the toast the main script shows at start, with its JSON error.
        $script:UnreadableSettings['essai.json'] | Should -Not -BeNullOrEmpty
    }

    It '-Merge doesn''t write over a file that can''t be read: it''s moved aside, as it is, to .illisible' {
        # A DN hand-written with a single \ before its comma: not JSON.
        $broken = '{ "MoveRoots": ["OU=Postes\,DC=demo,DC=local"], "SccmSite": "DEM" }'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $File)
        Set-Content -LiteralPath $File -Value $broken -Encoding utf8
        Mock Write-Host { }
        Save-JsonSetting $File @{ Language = 'fr' } -Merge
        (Get-Content -LiteralPath "$File.illisible" -Raw).Trim() | Should -BeExactly $broken
        @((Read-JsonSetting $File).PSObject.Properties.Name) | Should -Be @('Language')
    }

    It 'A file this run couldn''t read is moved aside to .illisible by its next save, not written over, -Merge or not' {
        # As fenetre.json, saved whole at every close.
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $File)
        Set-Content -LiteralPath $File -Value '{ "Left": 10,' -Encoding utf8
        Mock Write-Host { }
        $null = Read-JsonSetting $File Left
        Save-JsonSetting $File ([ordered]@{ Left = 20 })
        (Get-Content -LiteralPath "$File.illisible" -Raw).Trim() | Should -BeExactly '{ "Left": 10,'
        (Read-JsonSetting $File Left).Left | Should -Be 20
        # Moved once: the next save writes the file as any other, and leaves .illisible as it is.
        $script:UnreadableSettings.Contains('essai.json') | Should -BeFalse
        Save-JsonSetting $File ([ordered]@{ Left = 30 })
        (Read-JsonSetting $File Left).Left | Should -Be 30
        (Get-Content -LiteralPath "$File.illisible" -Raw).Trim() | Should -BeExactly '{ "Left": 10,'
    }

    It '-Merge saves nothing when a file that can''t be read can''t be moved aside either' {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $File)
        Set-Content -LiteralPath $File -Value '{ "Amount": 5,' -Encoding utf8
        # .illisible's place is a folder that isn't empty: the file can't be moved there.
        $null = New-Item -ItemType Directory -Force -Path (Join-Path "$File.illisible" 'dedans')
        Mock Write-Host { }
        Save-JsonSetting $File @{ Amount = 1 } -Merge
        (Get-Content -LiteralPath $File -Raw).Trim() | Should -BeExactly '{ "Amount": 5,'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -like 'essai.json non enregistré : *' }
    }

    It '-Merge keeps the file''s other settings, and replaces those given' {
        Save-JsonSetting $File ([ordered]@{ MoveRoots = @('OU=Postes,DC=demo,DC=local'); Language = 'en' })
        Save-JsonSetting $File @{ Language = 'fr' } -Merge
        $saved = Read-JsonSetting $File
        "$($saved.Language) $(@($saved.MoveRoots) -join ',')" | Should -BeExactly 'fr OU=Postes,DC=demo,DC=local'
    }

    It 'Says so, without stopping, when the file can''t be written' {
        # The folder's place is a file: no folder can be made there.
        $null = New-Item -ItemType Directory -Force -Path $Folder
        Set-Content -LiteralPath (Join-Path $Folder 'Repere') -Value 'pas un dossier'
        Mock Write-Host { }
        { Save-JsonSetting $File @{ A = 1 } } | Should -Not -Throw
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -like 'essai.json non enregistré : *' }
    }

    It 'Every settings file is in the same folder' {
        @($AppearancePath, $PasswordSettingPath, $RestartSettingsPath, $SettingsPath, $LanguageSettingPath) | ForEach-Object { Split-Path $_ } |
            Select-Object -Unique | Should -BeExactly $SettingsFolder
    }
}
