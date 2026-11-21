# Repère's small helpers, which need neither a window nor AD: LDAP escaping, the generated passwords, the names and
# paths taken from a DN, French lists and dates, the row builder's ages and OU paths, quser's sessions as
# Utilisateurs connectés… shows them, the theme editor's color boxes and picker, the box of secrets to copy, and a copied secret's clearing.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
}

Describe 'Format-RowLine' {
    It 'Puts a tab between the values, an empty one included' {
        Format-RowLine @('ORD-01', $null, 'Activé') | Should -Be "ORD-01`t`tActivé"
    }
    It 'Keeps a value with a line break or a tab on its line' {
        Format-RowLine @("Salle 1`r`n  étage 2", "a`tb") | Should -Be "Salle 1 étage 2`ta b"
    }
    It 'Keeps a value Excel would read as a formula as text, as Exporter does' {
        Format-RowLine @('=HYPERLINK("x")', 'ORD-01', '-1', '+33 1', '@SUM(A1)', 'a=b') |
            Should -BeExactly "'=HYPERLINK(`"x`")`tORD-01`t'-1`t'+33 1`t'@SUM(A1)`ta=b"
    }
    It 'Keeps a value that starts with a tab or a line break as text, flattened' {
        Format-RowLine @("`t=1", "`r`n=2") | Should -BeExactly "' =1`t' =2"
    }
}

Describe 'Protect-SpreadsheetText' {
    It 'Gives a value per value, an empty one and a list included' {
        $values = Protect-SpreadsheetText @($null, '=a', @('b', 'c'), 'd')
        $values.Count | Should -Be 4
        $values[0] | Should -BeNullOrEmpty
        $values[1] | Should -BeExactly "'=a"
        $values[2] | Should -Be @('b', 'c')
        $values[3] | Should -BeExactly 'd'
    }
    It 'Leaves the other values as they are, a date included' {
        $date = Get-Date
        (Protect-SpreadsheetText @($date))[0] | Should -BeOfType [datetime]
    }
}

Describe 'Get-LdapText' {
    # Named by the result: a NUL in a test's name breaks the XML report of -CI.
    It 'Escapes the value as <Expected>' -ForEach @(
        @{ Text = 'Bertrand'; Expected = 'Bertrand' }
        @{ Text = 'GG-*'; Expected = 'GG-\2a' }
        @{ Text = 'Ventes (Nord)'; Expected = 'Ventes \28Nord\29' }
        @{ Text = 'C:\partage'; Expected = 'C:\5cpartage' }
        # The backslash first: the escapes' own backslashes aren't escaped again.
        @{ Text = '\*'; Expected = '\5c\2a' }
        @{ Text = "a$([char]0)b"; Expected = 'a\00b' }
        @{ Text = 'CN=Lévy\, Nathalie,OU=Utilisateurs,DC=demo,DC=local'; Expected = 'CN=Lévy\5c, Nathalie,OU=Utilisateurs,DC=demo,DC=local' }
    ) {
        Get-LdapText $Text | Should -BeExactly $Expected
    }

    It 'Turns an empty value into an empty string' {
        Get-LdapText '' | Should -BeExactly ''
    }
}

Describe 'ConvertTo-BitLockerKeyId' {
    It 'Reads « <Text> » as the start of a key ID: <Expected>' -ForEach @(
        @{ Text = '6f1c2e7a'; Expected = '6F1C2E7A' }
        @{ Text = ' 6F1C2E7A-0B9D '; Expected = '6F1C2E7A-0B9D' }
        @{ Text = '6F1C2E7A0B9D4C55'; Expected = '6F1C2E7A-0B9D-4C55' }
        @{ Text = '{6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61}'; Expected = '6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61' }
        @{ Text = '6F1C2E7A0B9D4C559E3B1D2A4F8B7C61'; Expected = '6F1C2E7A-0B9D-4C55-9E3B-1D2A4F8B7C61' }
    ) {
        ConvertTo-BitLockerKeyId $Text | Should -BeExactly $Expected
    }

    It 'Refuses « <Text> »: shorter than the 8 characters the screen shows, not hexadecimal, or too long' -ForEach @(
        @{ Text = '6F1C2E7' }, @{ Text = '' }, @{ Text = 'ORD-0123' }, @{ Text = '6F1C2E7A*' }, @{ Text = '6F1C2E7A0B9D4C559E3B1D2A4F8B7C61AB' }
    ) {
        ConvertTo-BitLockerKeyId $Text | Should -BeNullOrEmpty
    }
}

Describe 'New-TemporaryPassword' {
    BeforeAll {
        # Many of them, each check listing those that fail it.
        $script:Passwords = @(1..300 | ForEach-Object { New-TemporaryPassword })
        $script:Parts = @($script:Passwords | ForEach-Object { , ($_ -split '-') })
    }

    It 'Is three words and two digits, Word-Word-Word-NN' {
        $script:Passwords | Where-Object { $_ -cnotmatch '^[A-Z][a-z]+-[A-Z][a-z]+-[A-Z][a-z]+-\d\d$' } | Should -BeNullOrEmpty
    }

    It 'Takes its words from the list, three different ones' {
        $script:Parts | Where-Object { @($_[0..2] | Where-Object { $_ -notin $script:PasswordWords }).Count } | ForEach-Object { $_ -join '-' } | Should -BeNullOrEmpty
        $script:Parts | Where-Object { @($_[0..2] | Select-Object -Unique).Count -ne 3 } | ForEach-Object { $_ -join '-' } | Should -BeNullOrEmpty
    }

    It 'Ends with a number from 10 to 99' {
        $script:Parts | Where-Object { [int]$_[3] -lt 10 -or [int]$_[3] -gt 99 } | ForEach-Object { $_ -join '-' } | Should -BeNullOrEmpty
    }

    It 'Is long enough for the fake domain, which wants 10 characters' {
        $script:Passwords | Where-Object Length -lt 10 | Should -BeNullOrEmpty
    }

    It 'Varies from one password to the next' {
        @($script:Passwords | Select-Object -Unique).Count | Should -BeGreaterThan 250
    }
}

Describe 'Get-DomainOfDN' {
    It 'Finds the domain of <DistinguishedName>' -ForEach @(
        @{ DistinguishedName = 'CN=GG-Office,OU=Groupes,DC=demo,DC=local'; Expected = 'demo.local' }
        @{ DistinguishedName = 'CN=ORD-01,OU=Postes,DC=nord,DC=demo,DC=local'; Expected = 'nord.demo.local' }
        @{ DistinguishedName = 'CN=Lévy\, Nathalie,OU=Utilisateurs,DC=nord,DC=demo,DC=local'; Expected = 'nord.demo.local' }
        @{ DistinguishedName = 'DC=demo,DC=local'; Expected = 'demo.local' }
        @{ DistinguishedName = 'S-1-5-21-1111-2222-3333-1110'; Expected = '' }
        @{ DistinguishedName = ''; Expected = '' }
    ) {
        Get-DomainOfDN $DistinguishedName | Should -BeExactly $Expected
    }
}

Describe 'Get-DnName' {
    It 'Names <DistinguishedName>' -ForEach @(
        @{ DistinguishedName = 'CN=Nathalie Lévy,OU=Utilisateurs,DC=demo,DC=local'; Expected = 'Nathalie Lévy' }
        @{ DistinguishedName = 'CN=Lévy\, Nathalie,OU=Utilisateurs,DC=demo,DC=local'; Expected = 'Lévy, Nathalie' }
        @{ DistinguishedName = 'OU=Postes,DC=demo,DC=local'; Expected = 'Postes' }
        @{ DistinguishedName = 'CN=GG-Accueil'; Expected = 'GG-Accueil' }
    ) {
        Get-DnName $DistinguishedName | Should -BeExactly $Expected
    }

    It 'Gives $null without a DN' {
        Get-DnName '' | Should -BeNullOrEmpty
        Get-DnName $null | Should -BeNullOrEmpty
    }
}

Describe 'Join-FrenchList' {
    It 'Joins <Count> items as « <Expected> »' -ForEach @(
        @{ Count = 0; Items = @(); Expected = '' }
        @{ Count = 1; Items = @('GG-VPN'); Expected = 'GG-VPN' }
        @{ Count = 2; Items = @('GG-VPN', 'GG-Accueil'); Expected = 'GG-VPN et GG-Accueil' }
        @{ Count = 3; Items = @('GG-VPN', 'GG-Accueil', 'GG-Ventes'); Expected = 'GG-VPN, GG-Accueil et GG-Ventes' }
    ) {
        Join-FrenchList $Items | Should -BeExactly $Expected
    }
}

Describe 'Format-TextDate' {
    It 'Writes a date and its time as fr-CA does' {
        Format-TextDate ([datetime]'2026-01-15 09:30') | Should -BeExactly '2026-01-15 à 09 h 30'
        Format-TextDate ([datetime]'2026-07-01 17:05') | Should -BeExactly '2026-07-01 à 17 h 05'
    }

    It 'Writes the day only with -Day' {
        Format-TextDate ([datetime]'2026-12-31 23:59') -Day | Should -BeExactly '2026-12-31'
    }

    It 'Gives $null for no date, or what is not one' {
        Format-TextDate $null | Should -BeNullOrEmpty
        Format-TextDate '2026-01-15' | Should -BeNullOrEmpty
    }
}

Describe 'Format-Age' {
    BeforeAll {
        $script:Today = [datetime]'2026-10-23'
    }

    It 'Says « <Expected> » <Days> days after' -ForEach @(
        @{ Days = 0; Expected = "aujourd'hui" }
        # A date ahead (a DC's clock ahead of ours) is still today.
        @{ Days = -2; Expected = "aujourd'hui" }
        @{ Days = 1; Expected = 'hier' }
        @{ Days = 2; Expected = 'il y a 2 jours' }
        @{ Days = 29; Expected = 'il y a 29 jours' }
        @{ Days = 30; Expected = 'il y a 1 mois' }
        @{ Days = 89; Expected = 'il y a 2 mois' }
        @{ Days = 364; Expected = 'il y a 12 mois' }
        @{ Days = 365; Expected = 'il y a 1 an' }
        @{ Days = 729; Expected = 'il y a 1 an' }
        @{ Days = 730; Expected = 'il y a 2 ans' }
        @{ Days = 1200; Expected = 'il y a 3 ans' }
    ) {
        Format-Age $script:Today.AddDays(-$Days) $script:Today | Should -BeExactly $Expected
    }

    It 'Counts days, not hours: late yesterday is « hier »' {
        Format-Age $script:Today.AddMinutes(-1) $script:Today.AddHours(8) | Should -BeExactly 'hier'
    }

    It 'Says « Jamais » without a date' {
        Format-Age $null $script:Today | Should -BeExactly 'Jamais'
    }
}

Describe 'Get-OUPath and Get-ShortPath' {
    It 'Shows <DistinguishedName> as « <OUPath> » and <ShortPath>' -ForEach @(
        @{ DistinguishedName = 'CN=ORD-05,OU=Communs,OU=Postes,DC=demo,DC=local'; OUPath = 'Postes › Communs'; ShortPath = 'demo.local/Postes/Communs' }
        @{ DistinguishedName = 'CN=ORD-01,OU=Postes,DC=nord,DC=demo,DC=local'; OUPath = 'Postes'; ShortPath = 'nord.demo.local/Postes' }
        # Containers are kept; only the object itself is left out.
        @{ DistinguishedName = 'CN=ORD-13,CN=Computers,DC=demo,DC=local'; OUPath = 'Computers'; ShortPath = 'demo.local/Computers' }
        @{ DistinguishedName = 'CN=Paul Bertrand,OU=Ventes\, Nord,DC=nord,DC=demo,DC=local'; OUPath = 'Ventes, Nord'; ShortPath = 'nord.demo.local/Ventes, Nord' }
        @{ DistinguishedName = 'CN=Lévy\, Nathalie,OU=Utilisateurs,DC=demo,DC=local'; OUPath = 'Utilisateurs'; ShortPath = 'demo.local/Utilisateurs' }
        @{ DistinguishedName = 'CN=krbtgt,DC=demo,DC=local'; OUPath = ''; ShortPath = 'demo.local' }
    ) {
        Get-OUPath $DistinguishedName | Should -BeExactly $OUPath
        Get-ShortPath $DistinguishedName | Should -BeExactly $ShortPath
    }
}

Describe 'Format-SessionIdle' {
    It 'Reads quser''s « <Idle> » as « <Expected> »' -ForEach @(
        @{ Idle = '12'; Expected = '12 min' }
        @{ Idle = '1:05'; Expected = '1 h 5 min' }
        @{ Idle = '2+03:10'; Expected = '2 j 3 h' }
        @{ Idle = '?'; Expected = '?' }
    ) {
        Format-SessionIdle $Idle | Should -BeExactly $Expected
    }
}

Describe 'Format-ConnectedUser' {
    It 'Lists each session of a French Windows, active or disconnected' {
        $text = @(
            ' UTILISATEUR           SESSION            ID  ÉTAT    TEMPS INACT TEMPS SESSION'
            '>accueil               console             1  Actif           12  27/10/2026 07:58'
            ' tech.martin                               3  Déco          1:05  26/10/2026 16:20'
        ) -join "`r`n"
        Format-ConnectedUser 'ORD-01' $text |
            Should -BeExactly '✔ ORD-01 : accueil (active, console, inactive depuis 12 min, ouverte le 27/10/2026 07:58) · tech.martin (déconnectée, inactive depuis 1 h 5 min, ouverte le 26/10/2026 16:20)'
    }

    It 'Reads an English Windows'' quser, without an idle time' {
        $text = @(
            ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
            '>jdoe                  rdp-tcp#0           2  Active      none   10/27/2026 7:58 AM'
        ) -join "`n"
        Format-ConnectedUser 'ORD-04' $text | Should -BeExactly '✔ ORD-04 : jdoe (active, rdp-tcp#0, ouverte le 10/27/2026 7:58 AM)'
    }

    It 'Says nobody is logged on, without a mark' {
        Format-ConnectedUser 'ORD-08' 'Aucun utilisateur pour *' | Should -BeExactly "ORD-08 : Personne n'a de session ouverte sur cet ordinateur."
    }

    It 'Reports « <Text> » as a failure' -ForEach @(
        @{ Text = "Erreur 0x00000005 lors de l'énumération des noms de sessions`nErreur [5]:Accès refusé."; Expected = "✖ ORD-06 : Accès refusé*" }
        @{ Text = "Error 0x000006BA enumerating sessionnames`nError [1722]:The RPC server is unavailable."; Expected = "✖ ORD-06 : L'ordinateur ne répond pas*" }
        @{ Text = ''; Expected = "✖ ORD-06 : Les sessions ouvertes sur cet ordinateur n'ont pas pu être lues." }
    ) {
        Format-ConnectedUser 'ORD-06' $Text | Should -BeLike $Expected
    }

    It 'Says a computer that had no answer within its time didn''t answer' {
        Format-ConnectedUser 'ORD-12' '' 25 | Should -BeExactly '✖ ORD-12 : pas de réponse après 25 secondes (ordinateur éteint ou injoignable ?)'
    }
}

Describe 'A color''s box and the color picker (theme editor)' {
    It 'Repair-HexBox keeps the six digits: <Typed> reads <Expected>' -ForEach @(
        @{ Typed = '#1E1E1E'; Expected = '1E1E1E'; Changed = $true }
        @{ Typed = ' #1e1e1e '; Expected = '1e1e1e'; Changed = $true }
        @{ Typed = '1E1E1E7'; Expected = '1E1E1E'; Changed = $true }
        @{ Typed = '1E1E'; Expected = '1E1E'; Changed = $false }
        @{ Typed = ''; Expected = ''; Changed = $false }
    ) {
        $box = [System.Windows.Controls.TextBox]::new()
        $box.Text = $Typed
        Repair-HexBox $box | Should -Be $Changed
        $box.Text | Should -BeExactly $Expected
    }

    It 'ConvertTo-Hsv and ConvertFrom-Hsv give the same color back: <Hex>' -ForEach @(
        @{ Hex = '#27C8F5' }, @{ Hex = '#6A48F2' }, @{ Hex = '#000000' }, @{ Hex = '#FFFFFF' }, @{ Hex = '#808080' }, @{ Hex = '#FF0000' }
    ) {
        $hsv = ConvertTo-Hsv $Hex
        ConvertFrom-Hsv $hsv.H $hsv.S $hsv.V | Should -BeExactly $Hex
    }

    It 'ConvertFrom-Hsv: the square''s corners at hue 200' {
        @((ConvertFrom-Hsv 200 100 100), (ConvertFrom-Hsv 200 0 100), (ConvertFrom-Hsv 200 100 0)) -join ' ' | Should -BeExactly '#00AAFF #FFFFFF #000000'
    }
}

Describe 'A box of secrets to copy (Register-SecretCopy: the keys a deletion takes with it)' {
    BeforeEach {
        # Set-SecretClipboard as it is; only the clipboard itself is left out.
        Mock Set-ClipboardData { $true }
        Mock Show-CopyFeedback { }
        $script:box = [System.Windows.Controls.TextBox]::new()
        $script:box.IsReadOnly = $true
        $script:box.Text = "ORD-09`n  418649-302104`n`nORD-07`n  207152-660011"
        $script:button = [System.Windows.Controls.Button]::new()
        Register-SecretCopy $script:box $script:button
        # WPF's own copy makes its data object through this event: raised, it ran.
        $script:wpfCopies = [System.Collections.Generic.List[bool]]::new()
        [System.Windows.DataObject]::AddCopyingHandler($script:box, [System.Windows.DataObjectCopyingEventHandler]{ param($source, $e) $script:wpfCopies.Add($e.IsDragDrop) })
        $script:copy = [System.Windows.Input.ApplicationCommands]::Copy
    }

    It 'Ctrl+C with nothing selected copies all of it as a secret, and WPF''s own copy never runs' {
        Mock Set-SecretClipboard { $true }
        $script:copy.CanExecute($null, $script:box) | Should -BeTrue
        $script:copy.Execute($null, $script:box)
        Should -Invoke Set-SecretClipboard -Times 1 -Exactly -ParameterFilter { $Text -ceq $script:box.Text }
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and $Copied }
        $script:wpfCopies.Count | Should -Be 0
    }

    It 'Ctrl+C copies only the selection when there is one' {
        Mock Set-SecretClipboard { $true }
        $script:box.Select(9, 13)
        $script:copy.Execute($null, $script:box)
        Should -Invoke Set-SecretClipboard -Times 1 -Exactly -ParameterFilter { $Text -ceq '418649-302104' }
        $script:wpfCopies.Count | Should -Be 0
    }

    It 'Its Copier button copies all of it, even with part of it selected' {
        Mock Set-SecretClipboard { $true }
        $script:box.Select(9, 13)
        $script:button.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        Should -Invoke Set-SecretClipboard -Times 1 -Exactly -ParameterFilter { $Text -ceq $script:box.Text }
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and $Copied }
    }

    It 'With the clipboard held, says « Copie impossible » on the button and tries no other copy' {
        # The one try is the secret one, with the formats that keep it out of the clipboard history.
        Mock Set-ClipboardData { $false }
        $script:copy.Execute($null, $script:box)
        Should -Invoke Set-ClipboardData -Times 1 -Exactly -ParameterFilter {
            $Data.GetData([System.Windows.DataFormats]::UnicodeText) -ceq $script:box.Text -and $Data.GetDataPresent('ExcludeClipboardContentFromMonitorProcessing')
        }
        Should -Invoke Show-CopyFeedback -Times 1 -Exactly -ParameterFilter { $Button -eq $script:button -and -not $Copied }
        $script:wpfCopies.Count | Should -Be 0
        # Nothing to clear a minute later: nothing was copied.
        $script:SecretClipboard.Text | Should -BeNullOrEmpty
    }

    It 'Refuses the data object a drag of the selection makes, and any other copy of WPF''s' -ForEach @(
        @{ Drag = $true }, @{ Drag = $false }
    ) {
        $e = [System.Windows.DataObjectCopyingEventArgs]::new([System.Windows.DataObject]::new('418649-302104'), $Drag)
        $script:box.RaiseEvent($e)
        $e.CommandCancelled | Should -BeTrue
    }
}

Describe 'A copied secret cleared from the clipboard (Clear-SecretClipboard), even when another program holds it then' {
    BeforeEach {
        # Copied as it is; only the clipboard itself is left out. Remove-ClipboardSecret throws the way WPF does when
        # the clipboard is held, as many times as $script:held says.
        Mock Set-ClipboardData { $true }
        Set-SecretClipboard 'Tulipe-Orage-Banquise-42' | Should -BeTrue
        $script:held = 0
        Mock Remove-ClipboardSecret { if ($script:held-- -gt 0) { throw 'OpenClipboard a échoué (0x800401D0 CLIPBRD_E_CANT_OPEN)' } }
    }

    AfterEach {
        $script:SecretClipboard.Timer.Stop()
        $script:SecretClipboard.Text = $null
    }

    It 'A minute after the copy, clears it and forgets it' {
        $script:SecretClipboard.Timer.Interval | Should -Be ([timespan]::FromMinutes(1))
        Clear-SecretClipboard
        Should -Invoke Remove-ClipboardSecret -Times 1 -Exactly -ParameterFilter { $Text -ceq 'Tulipe-Orage-Banquise-42' }
        $script:SecretClipboard.Text | Should -BeNullOrEmpty
        $script:SecretClipboard.Timer.IsEnabled | Should -BeFalse
    }

    It 'Held at that moment, keeps it and tries again two seconds later: the retry clears it' {
        $script:held = 1
        Clear-SecretClipboard
        $script:SecretClipboard.Text | Should -BeExactly 'Tulipe-Orage-Banquise-42'
        $script:SecretClipboard.Timer.IsEnabled | Should -BeTrue
        $script:SecretClipboard.Timer.Interval | Should -Be ([timespan]::FromSeconds(2))
        Clear-SecretClipboard
        Should -Invoke Remove-ClipboardSecret -Times 2 -Exactly -ParameterFilter { $Text -ceq 'Tulipe-Orage-Banquise-42' }
        $script:SecretClipboard.Text | Should -BeNullOrEmpty
        $script:SecretClipboard.Timer.IsEnabled | Should -BeFalse
        # The next copy waits its minute again.
        $script:SecretClipboard.Timer.Interval | Should -Be ([timespan]::FromMinutes(1))
    }

    It 'Stops trying after five retries, and keeps it for the closing, which clears it' {
        $script:held = 100
        foreach ($try in 1..6) { Clear-SecretClipboard }
        Should -Invoke Remove-ClipboardSecret -Times 6 -Exactly
        $script:SecretClipboard.Timer.IsEnabled | Should -BeFalse
        $script:SecretClipboard.Text | Should -BeExactly 'Tulipe-Orage-Banquise-42'
        $script:held = 0
        Clear-SecretClipboard -Closing
        $script:SecretClipboard.Text | Should -BeNullOrEmpty
    }

    It 'When Repère closes, tries three times in a row before giving up, and starts no timer' -ForEach @(
        @{ Held = 2; Cleared = $true }, @{ Held = 3; Cleared = $false }
    ) {
        $script:held = $Held
        Clear-SecretClipboard -Closing
        Should -Invoke Remove-ClipboardSecret -Times 3 -Exactly
        [bool]$script:SecretClipboard.Text | Should -Be (-not $Cleared)
        $script:SecretClipboard.Timer.IsEnabled | Should -BeFalse
    }

    It 'A new copy while the last one is being tried again waits its own minute' {
        $script:held = 1
        Clear-SecretClipboard
        Set-SecretClipboard 'Castor-Velours-Rivage-17' | Should -BeTrue
        $script:SecretClipboard.Timer.Interval | Should -Be ([timespan]::FromMinutes(1))
        $script:SecretClipboard.Failed | Should -Be 0
    }
}

Describe 'What AD hands over that the code has to take' {
    It 'Paths lose every escape of a DN, not only the comma''s' {
        Get-OUPath 'CN=PC1,OU=R\+D\#1,OU=A\=B\, C,DC=demo,DC=local' | Should -BeExactly 'A=B, C › R+D#1'
        Get-ShortPath 'CN=PC1,OU=R\+D,DC=demo,DC=local' | Should -BeExactly 'demo.local/R+D'
        Get-DnName 'CN=R\+D\, équipe,OU=X,DC=demo,DC=local' | Should -BeExactly 'R+D, équipe'
    }

    It 'A XAML value leaves out what XML can''t hold, and {{ for Expand-Icon' {
        [xml]"<a b=`"$(ConvertTo-XamlValue "Poste`vaccueil`u{1}")`"/>" | Should -Not -BeNullOrEmpty
        ConvertTo-XamlValue "`v" | Should -BeExactly ''
        ConvertTo-XamlValue 'a{{icon:x}}' | Should -BeExactly '&#97;&#123;&#123;icon:x}}'
    }

    # XML decodes &#123; before XAML reads the attribute: without XAML's {} escape, {x} was a markup extension (#227).
    It 'A XAML value starting with a brace reads as itself, through Expand-Icon: <Name>' -ForEach @(
        @{ Name = '{x}'; Value = '{x}' }
        @{ Name = 'x:Static'; Value = '{x:Static SystemParameters.PrimaryScreenWidth}' }
        @{ Name = '{}'; Value = '{}' }
        @{ Name = 'a lone brace'; Value = '{' }
        @{ Name = '{{'; Value = '{{' }
        @{ Name = 'an icon placeholder'; Value = '{{icon:copy}}' }
        @{ Name = 'a brace in the middle'; Value = 'a{b}' }
        # XAML reads a CR LF as a LF.
        @{ Name = 'on two lines'; Value = "{Temporaire}`naccueil" }
    ) {
        $xaml = Expand-Icon "<TextBlock xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" Text=`"$(ConvertTo-XamlValue $Value)`"/>"
        [System.Windows.Markup.XamlReader]::Parse($xaml).Text | Should -BeExactly $Value
    }

    It 'XAML''s {} escape only for a value starting with a brace' {
        ConvertTo-XamlValue '{x}' | Should -BeExactly '{}&#123;x}'
        ConvertTo-XamlValue 'a{b}' | Should -BeExactly '&#97;{b}'
        ConvertTo-XamlValue ' {x}' | Should -BeExactly '&#32;{x}'
    }


    It 'A last logon of 999 years makes a filter, not an error' {
        $criteria = New-AdvancedSearch
        $criteria.Logon = 'AtLeast'
        $criteria.Number = 999
        $criteria.Unit = 3
        (Get-AdvancedSearchFilter $criteria (Get-Date)).Filter | Should -Match 'lastLogonTimestamp -lt \d+'
    }

    It 'A CSV value Excel would read as a formula stays text' {
        $row = [pscustomobject]@{ A = '=HYPERLINK("x")'; B = '-1'; C = 'ORD-01'; D = $null } | Protect-CsvValue
        $row.A | Should -BeExactly "'=HYPERLINK(`"x`")"
        $row.B | Should -BeExactly "'-1"
        $row.C | Should -BeExactly 'ORD-01'
        $row.D | Should -BeNullOrEmpty
    }

    It 'A CSV value keeps its column when another is empty or a list' {
        $row = [pscustomobject][ordered]@{ A = $null; B = @('x', 'y'); C = '=z'; D = 4 } | Protect-CsvValue
        $row.A | Should -BeNullOrEmpty
        $row.B | Should -Be @('x', 'y')
        $row.C | Should -BeExactly "'=z"
        $row.D | Should -BeOfType [int]
    }

}

Describe 'What a pin of the taskbar button starts (Get-RepereRelaunchCommand)' {
    It 'Starts Repère without a console, with the options it was started with, its lists as the script reads them' {
        $options = @{ Domains = @('a.local', 'b.local'); MoveRoots = @('OU=Postes,DC=x', 'OU=Kiosques,DC=x'); NoUpdateCheck = [switch]$true }
        Get-RepereRelaunchCommand 'C:\pwsh\pwsh.exe' 'C:\Repère\src\Repere.ps1' $options |
            Should -BeExactly "`"$env:windir\System32\conhost.exe`" --headless `"C:\pwsh\pwsh.exe`" -NoProfile -File `"C:\Repère\src\Repere.ps1`" -Domains `"a.local,b.local`" -MoveRoots `"OU=Postes,DC=x;OU=Kiosques,DC=x`" -NoUpdateCheck"
    }

    It 'Leaves out a switch that is off and an empty value, and a quote that would end the value' {
        $command = Get-RepereRelaunchCommand 'p.exe' 's.ps1' @{ FakeAD = [switch]$false; Language = ''; Domains = @('a"b.local') }
        $command | Should -BeLike '* -File "s.ps1" -Domains "ab.local"'
    }

    It 'Points the taskbar at a copy of the icon named after its contents, so a new icon is read afresh (Get-RepereTaskbarIcon)' {
        $folder = Join-Path $TestDrive 'icons'
        $icon = Join-Path $TestDrive 'compass.ico'
        Set-Content -LiteralPath $icon -Value 'first' -NoNewline
        $first = Get-RepereTaskbarIcon $icon $folder
        $first | Should -BeLike "$folder\compass-*.ico"
        Get-Content -LiteralPath $first -Raw | Should -BeExactly 'first'
        Get-RepereTaskbarIcon $icon $folder | Should -BeExactly $first
        Set-Content -LiteralPath $icon -Value 'second' -NoNewline
        $second = Get-RepereTaskbarIcon $icon $folder
        $second | Should -Not -Be $first
        Get-Content -LiteralPath $second -Raw | Should -BeExactly 'second'
    }

    It 'Falls back on the icon itself when it can''t be copied' {
        Get-RepereTaskbarIcon (Join-Path $TestDrive 'missing.ico') (Join-Path $TestDrive 'icons') | Should -BeExactly (Join-Path $TestDrive 'missing.ico')
    }

    It 'Takes the script''s $PSBoundParameters as the main script passes them' {
        function Get-Bound { param([string[]]$Domains, [switch]$NoUpdateCheck) $PSBoundParameters }
        Get-RepereRelaunchCommand 'p.exe' 's.ps1' (Get-Bound -Domains 'a.local' -NoUpdateCheck) | Should -BeLike '* -Domains "a.local" -NoUpdateCheck'
    }
}

Describe 'The Windows calls behind the taskbar button (Get-RepereNativeType)' {
    It 'Defines the types at the first call, under strict mode, and only once' {
        # Taskbar.ps1 loaded again, as at Repère's start: nothing cached yet. A cache variable never set made the first
        # call fail under strict mode, which Set-RepereAppId's try/catch hid: Repère lost its own taskbar button.
        Set-StrictMode -Version Latest
        . (Join-Path $script:RepereSource 'Taskbar.ps1')
        $native = Get-RepereNativeType
        $native.Shell.GetMethod('SetCurrentProcessExplicitAppUserModelID') | Should -Not -BeNullOrEmpty
        $native.PropertyStore.IsInterface | Should -BeTrue
        [object]::ReferenceEquals((Get-RepereNativeType), $native) | Should -BeTrue
    }
}