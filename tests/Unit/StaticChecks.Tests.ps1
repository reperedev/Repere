# Static checks over the repo's own files (StaticAnalysis.ps1), for mistakes it has made: how its files are encoded,
# and names that collide because PowerShell ignores their case. First the checks on samples of those mistakes, then on
# the repo.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    . (Join-Path $PSScriptRoot 'StaticAnalysis.ps1')
    $script:SourceFiles = @(Get-RepereSourcePath | ForEach-Object { @{ Path = $_; Name = $_.Substring($script:RepereRoot.Length + 1) } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    . (Join-Path $PSScriptRoot 'StaticAnalysis.ps1')
    # The main script and every file it dot-sources share one scope.
    $script:SharedScripts = @(@($script:RepereMainScript) + @(Get-RepereDotSourcedPath -Recurse) | ForEach-Object { Get-ParsedScript $_ })

    # Script variables that several of those files set on purpose, in the same case, each with why (lower case).
    $script:SharedVariables = @(
        # The OUs Déplacer vers… offers: the main script reads them (-MoveRoots, or parametres.json), Paramètres
        # (SettingsWindow.ps1, Set-MoveRoot) changes them.
        'moverootlist'
        # The language chosen in Paramètres: Language.ps1 reads it as Repère starts, Paramètres › Apparence (Theme.ps1)
        # changes it, and SettingsWindow.ps1 saves it.
        'languagechoice'
    )

    # Parameters overwritten under another case and accepted, each a « Function:variable »: none (the four found when
    # these checks came were renamed: Show-Dialog's $cancelIsDefault, Get-DetailCardXaml's $note, $count and $footer).
    $script:OverwrittenParameters = @()
}

Describe 'The checks, on samples of the mistakes' {
    It 'Find-EncodingProblem: <Case>' -ForEach @(
        @{ Case = 'one byte order mark and CRLF'; Bytes = [byte[]](0xEF, 0xBB, 0xBF, 0x23, 0x0D, 0x0A, 0x31, 0x0D, 0x0A); Expected = $null }
        @{ Case = 'no byte order mark'; Bytes = [byte[]](0x23, 0x0D, 0x0A); Expected = 'a.ps1: no UTF-8 byte order mark' }
        @{ Case = 'a byte order mark written twice'; Bytes = [byte[]](0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x23, 0x0D, 0x0A); Expected = 'a.ps1: byte order mark written twice' }
        @{ Case = 'an LF alone, line 2'; Bytes = [byte[]](0xEF, 0xBB, 0xBF, 0x23, 0x0D, 0x0A, 0x31, 0x0A); Expected = 'a.ps1:2 LF without CR' }
        @{ Case = 'a CR alone'; Bytes = [byte[]](0xEF, 0xBB, 0xBF, 0x23, 0x0D, 0x31); Expected = 'a.ps1:1 CR without LF' }
    ) {
        Find-EncodingProblem 'a.ps1' $Bytes | Should -Be $Expected
    }

    It 'Find-DuplicateFunction: a function defined again in another file, in another case' {
        $one = ConvertTo-ParsedScript 'One.ps1' "function Get-DomainOfDN { }`nfunction Get-Other { }"
        $two = ConvertTo-ParsedScript 'Two.ps1' 'function get-domainofdn { }'
        Find-DuplicateFunction $one, $two | Should -BeExactly 'Get-DomainOfDN / get-domainofdn defined 2 times: One.ps1:1, Two.ps1:1'
        Find-DuplicateFunction $one | Should -BeNullOrEmpty
    }

    It 'Find-ScriptVariableClash: $script:BackgroundTimer replaced by $backgroundTimer of another file' {
        $background = ConvertTo-ParsedScript 'Background.ps1' '$script:BackgroundTimer = [System.Windows.Threading.DispatcherTimer]::new()'
        $main = ConvertTo-ParsedScript 'Main.ps1' "if (`$true) {`n    `$backgroundTimer = [System.Windows.Threading.DispatcherTimer]::new()`n}"
        Find-ScriptVariableClash $background, $main | Should -BeExactly '$BackgroundTimer / $backgroundTimer set in several files: Background.ps1:1, Main.ps1:2'
    }

    It 'Find-ScriptVariableClash: the same name, a dot-sourced script parameter, and the allowlist' {
        $one = ConvertTo-ParsedScript 'One.ps1' 'param([string]$ComputerName = ".")'
        $two = ConvertTo-ParsedScript 'Two.ps1' 'function Set-Target { $script:ComputerName = "PC-1" }'
        Find-ScriptVariableClash $one, $two | Should -BeExactly '$ComputerName set in several files: One.ps1:1, Two.ps1:1'
        Find-ScriptVariableClash $one, $two -Allowed 'computername' | Should -BeNullOrEmpty
    }

    It 'Find-ScriptVariableClash: not the variables of a function or a script block' {
        $one = ConvertTo-ParsedScript 'One.ps1' '$results = @{}'
        $two = ConvertTo-ParsedScript 'Two.ps1' "function Get-Result { `$results = 1 }`n`$button.Add_Click({ `$results = 2 })`n`$job = { `$Results = 3 }"
        Find-ScriptVariableClash $one, $two | Should -BeNullOrEmpty
    }

    It 'Find-ParameterCaseAssignment: <Case>' -ForEach @(
        @{ Case = 'a parameter $Inherited overwritten by $inherited'; Code = 'function Get-ObjectGroup($Object, $Inherited) { $inherited = Read-TokenGroup }'
           Expected = 'Sample.ps1:1: $inherited overwrites the parameter $Inherited of Get-ObjectGroup' }
        @{ Case = 'in a param block, by a foreach'; Code = "function Get-Row {`n    param([string[]]`$Keys)`n    foreach (`$keys in 1) { }`n}"
           Expected = 'Sample.ps1:3: $keys overwrites the parameter $Keys of Get-Row' }
        @{ Case = 'in a script block with parameters'; Code = "`$readMany = {`n    param([string[]]`$Keys)`n    `$keys = @()`n}"
           Expected = 'Sample.ps1:3: $keys overwrites the parameter $Keys of script block at line 1' }
        @{ Case = 'in ForEach-Object, which runs in the same scope'; Code = 'function Get-Row($Row) { 1, 2 | ForEach-Object { $row = $_ } }'
           Expected = 'Sample.ps1:1: $row overwrites the parameter $Row of Get-Row' }
        @{ Case = 'the parameter in its own case'; Code = 'function Get-Row([string]$Filter) { $Filter = $Filter.Trim() }'; Expected = $null }
        @{ Case = 'an event handler, which has its own scope'; Code = 'function Show-Row($State) { $button.Add_Click({ param($b) $state = $b.Tag }) }'; Expected = $null }
        @{ Case = 'a nested function with its own parameter'; Code = 'function Show-Row($State) { function Get-Inner($state) { $state = 1 } }'; Expected = $null }
        @{ Case = 'a script block called with &'; Code = 'function Get-Row($Row) { & { $row = 1 } }'; Expected = $null }
        @{ Case = 'the allowlist'; Code = 'function Get-Row($Row) { $row = 1 }'; Allowed = 'Get-Row:row'; Expected = $null }
    ) {
        Find-ParameterCaseAssignment (ConvertTo-ParsedScript 'Sample.ps1' $Code) $Allowed | Should -Be $Expected
    }

    It 'Find-DispatcherStringArgument: <Case>' -ForEach @(
        @{ Case = 'a priority as a string'; Code = "`$d.Dispatcher.BeginInvoke([Action]{ Get-Row }, 'Input')"
           Expected = 'Sample.ps1:1: BeginInvoke given a string after its delegate; a priority must be a DispatcherPriority' }
        @{ Case = 'a DispatcherPriority'; Code = '$d.Dispatcher.BeginInvoke([Action]{ Get-Row }, [System.Windows.Threading.DispatcherPriority]::Input)'; Expected = $null }
        @{ Case = 'a delegate alone'; Code = '$d.Dispatcher.BeginInvoke([Action]{ Get-Row })'; Expected = $null }
        @{ Case = 'another method''s strings'; Code = "`$list.Insert(0, 'x')"; Expected = $null }
    ) {
        Find-DispatcherStringArgument (ConvertTo-ParsedScript 'Sample.ps1' $Code) | Should -Be $Expected
    }

    It 'Find-ButtonTagData: <Case>' -ForEach @(
        @{ Case = 'a variable named button'; Code = '$button.Tag = $i'
           Expected = "Sample.ps1:1: a button's Tag is its corner radius; put what its click needs in CommandParameter" }
        @{ Case = 'a new Button'; Code = "`$ok = [System.Windows.Controls.Button]::new()`n`$ok.Tag = @{}"
           Expected = "Sample.ps1:2: a button's Tag is its corner radius; put what its click needs in CommandParameter" }
        @{ Case = 'a copy button found by name'; Code = "`$copy = `$body.FindName(`"bitlocker_copy_`$i`")`n`$copy.Tag = `$row"
           Expected = "Sample.ps1:2: a button's Tag is its corner radius; put what its click needs in CommandParameter" }
        @{ Case = 'FindName of a button, set at once'; Code = "`$shown.FindName('user_new_password_copy').Tag = `$Password"
           Expected = "Sample.ps1:1: a button's Tag is its corner radius; put what its click needs in CommandParameter" }
        @{ Case = 'its CommandParameter'; Code = '$button.CommandParameter = $i'; Expected = $null }
        @{ Case = 'a menu item'; Code = "`$copy = [System.Windows.Controls.MenuItem]::new()`n`$copy.Tag = `$box"; Expected = $null }
        @{ Case = 'a check box found by name'; Code = "`$box = `$body.FindName(`"bitlocker_key_`$i`")`n`$box.Tag = `$row"; Expected = $null }
    ) {
        Find-ButtonTagData (ConvertTo-ParsedScript 'Sample.ps1' $Code) | Should -Be $Expected
    }
}

Describe "The repo's files: encoding" {
    It '<Name> has one UTF-8 byte order mark and CRLF line endings' -ForEach $script:SourceFiles {
        Find-EncodingProblem $Name ([System.IO.File]::ReadAllBytes($Path)) | Should -BeNullOrEmpty
    }
}

Describe 'The main script and the files it dot-sources: one scope' {
    It 'Finds the files it dot-sources' {
        $script:SharedScripts.Count | Should -BeGreaterThan 5
        $script:SharedScripts.Name | Should -Contain 'Background.ps1'
        $script:SharedScripts.Name | Should -Contain 'PCSpecs.ps1'
    }

    It 'Has no syntax error' {
        $script:SharedScripts | Where-Object Errors | ForEach-Object { "$($_.Name): $($_.Errors[0].Message)" } | Should -BeNullOrEmpty
    }

    It 'Defines no function twice, names ignoring case' {
        Find-DuplicateFunction $script:SharedScripts | Should -BeNullOrEmpty
    }

    It 'Sets no script variable in two files, names ignoring case' {
        Find-ScriptVariableClash $script:SharedScripts $script:SharedVariables | Should -BeNullOrEmpty
    }
}

Describe "The repo's files: parameters" {
    It '<Name> overwrites no parameter under another case' -ForEach @($script:SourceFiles | Where-Object { $_.Path -notlike '*.psd1' }) {
        Find-ParameterCaseAssignment (Get-ParsedScript $Path) $script:OverwrittenParameters | Should -BeNullOrEmpty
    }

    It '<Name> gives a Dispatcher no priority as a string' -ForEach @($script:SourceFiles | Where-Object { $_.Path -notlike '*.psd1' }) {
        Find-DispatcherStringArgument (Get-ParsedScript $Path) | Should -BeNullOrEmpty
    }

    It '<Name> keeps no data in a button''s Tag, its corner radius' -ForEach @($script:SourceFiles | Where-Object { $_.Path -notlike '*.psd1' }) {
        Find-ButtonTagData (Get-ParsedScript $Path) | Should -BeNullOrEmpty
    }
}
