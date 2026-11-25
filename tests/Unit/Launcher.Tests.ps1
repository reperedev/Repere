# Repère.cmd's questions (PowerShell 7.5 missing): the language they're in, as Repère would choose its own, and the same
# text in both. Its :findlanguage run by cmd in a script of its own, with settings of the test's own.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Launcher = Get-Content -LiteralPath (Join-Path $script:RepereRoot 'Repère.cmd') -Raw
    $script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) "repere-launcher-$PID"
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:Folder 'Repere')
    $part = $script:Launcher.Substring($script:Launcher.IndexOf(':findlanguage' + "`r`n"))
    Set-Content -LiteralPath (Join-Path $script:Folder 'language.cmd') -Encoding ascii -NoNewline -Value (
        "@echo off`r`nsetlocal`r`ncall :findlanguage %*`r`necho [%REPERE_LANG%]`r`nexit /b 0`r`n`r`n$part")

    function Get-LauncherLanguage([string]$Arguments) {
        $saved = $env:APPDATA
        $env:APPDATA = $script:Folder
        try { (cmd.exe /d /c "`"$(Join-Path $script:Folder 'language.cmd')`" $Arguments") -join '|' }
        finally { $env:APPDATA = $saved }
    }
    function Set-Saved([string]$Json) {
        $path = Join-Path $script:Folder 'Repere\parametres.json'
        Remove-Item -Path (Join-Path $script:Folder 'Repere\*.json')
        if ($Json) { Set-Content -LiteralPath $path -Value $Json -Encoding utf8 }
    }
}

AfterAll { Remove-Item -LiteralPath $script:Folder -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'The language of the launcher''s questions' {
    It '<Case>' -ForEach @(
        @{ Case = '-Language wins over the one saved'; Saved = '{"Language":"fr"}'; Arguments = '-Domains a.local,b.local -Language en'; Expected = '[en]' }
        @{ Case = '-Language in another case, with a colon'; Saved = '{"Language":"en"}'; Arguments = '-language:FR'; Expected = '[fr]' }
        @{ Case = 'the one saved, English'; Saved = '{"MoveRoots":["OU=Café,DC=demo"],"Language":"en"}'; Arguments = '-Domains a.local'; Expected = '[en]' }
        @{ Case = 'the one saved, French'; Saved = '{"Language":"fr"}'; Arguments = ''; Expected = '[fr]' }
        @{ Case = 'a -Language Repère does not have: the one saved'; Saved = '{"Language":"en"}'; Arguments = '-Language de'; Expected = '[en]' }
        @{ Case = 'settings of a Repère without languages: French'; Saved = '{"MoveRoots":[]}'; Arguments = ''; Expected = '[fr]' }
        @{ Case = 'settings that can not be read: French'; Saved = '{ "Language": '; Arguments = ''; Expected = '[fr]' }
    ) {
        Set-Saved $Saved
        Get-LauncherLanguage $Arguments | Should -BeExactly $Expected
    }

    It "Windows's, without settings or as Paramètres says" {
        $windows = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') { '[fr]' } else { '[en]' }
        Set-Saved ''
        Get-LauncherLanguage '' | Should -BeExactly $windows
        Set-Saved '{"Language":""}'
        Get-LauncherLanguage '' | Should -BeExactly $windows
    }
}

Describe 'The launcher''s text' {
    It 'Has the same texts in French and in English, and only ASCII, which any console shows' {
        $names = @([regex]::Matches($script:Launcher, '(?m)^set "(TEXT_\w+)=') | ForEach-Object { $_.Groups[1].Value })
        $names.Count | Should -BeGreaterThan 0
        @($names | Group-Object | Where-Object Count -NE 2).Name | Should -BeNullOrEmpty
        $used = @([regex]::Matches($script:Launcher, '%(TEXT_\w+)%') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $used | Should -Be @($names | Sort-Object -Unique)
        $script:Launcher | Should -Not -Match '[^\x00-\x7F]'
    }
}
