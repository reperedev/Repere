# What stops Repère as it starts says why (#244): a launch option it doesn't have, and a file that doesn't load. The
# main script itself, started as Repère.cmd starts it, with -NonInteractive, where Exit-Repere writes its message on
# the error output and shows no dialog. Its settings in a folder of the test's own, in French, whatever Windows's
# language.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:AppData = Join-Path ([System.IO.Path]::GetTempPath()) "repere-startup-appdata-$PID"
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:AppData 'Repere')
    Set-Content -LiteralPath (Join-Path $script:AppData 'Repere\parametres.json') -Value '{"Language":"fr"}' -Encoding utf8

    function Invoke-Repere([string]$Script = $script:RepereMainScript, [string[]]$Arguments) {
        # The script's exit code and error output. Stopped after a minute: a start that doesn't stop opens its window.
        $start = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $Script) + $Arguments) { $start.ArgumentList.Add($argument) }
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardError = $true
        $start.RedirectStandardOutput = $true
        $start.Environment['APPDATA'] = $script:AppData
        $null = $start.Environment.Remove('REPERE_STRICT')
        $process = [System.Diagnostics.Process]::Start($start)
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            throw "Repère didn't stop: $($output.Result)"
        }
        $process.WaitForExit()
        # Only what the message has in ASCII is compared: pwsh writes its errors in the console's code page.
        [pscustomobject]@{ ExitCode = $process.ExitCode; Errors = $errors.Result }
    }
}

AfterAll { Remove-Item -LiteralPath $script:AppData -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'A launch option Repère does not have' {
    It '<Case> says what is wrong, in the language chosen' -ForEach @(
        @{ Case = '-Language de'; Arguments = '-FakeAD', '-Language', 'de'; Expected = '*Langue inconnue pour -Language*de*' }
        @{ Case = 'a space after a comma in -Domains'; Arguments = '-FakeAD', '-Domains', 'a.local,', 'b.local'; Expected = '*Option de lancement inconnue : b.local.*' }
        @{ Case = 'an option misspelled, in English'; Arguments = '-FakeAD', '-Language', 'en', '-Domainz', 'a.local'; Expected = '*Unknown launch option: -Domainz a.local.*' }
    ) {
        $result = Invoke-Repere -Arguments $Arguments
        $result.ExitCode | Should -Be 1
        $result.Errors | Should -BeLike $Expected
    }
}

Describe 'A file that does not load' {
    BeforeAll {
        # A copy of src with GridText.ps1 broken (a brace never closed), dot-sourced in the middle of the start.
        $script:Copy = Join-Path ([System.IO.Path]::GetTempPath()) "repere-startup-src-$PID"
        Remove-Item -LiteralPath $script:Copy -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $script:RepereSource -Destination $script:Copy -Recurse
        [System.IO.File]::AppendAllText((Join-Path $script:Copy 'GridText.ps1'), "function Get-Broken {`r`n")
    }
    AfterAll { Remove-Item -LiteralPath $script:Copy -Recurse -Force -ErrorAction SilentlyContinue }

    It 'Stops Repère and says which file, instead of opening a window half made' {
        $result = Invoke-Repere -Script (Join-Path $script:Copy (Split-Path $script:RepereMainScript -Leaf)) -Arguments '-FakeAD'
        $result.ExitCode | Should -Be 1
        $result.Errors | Should -BeLike "*n'a pas pu d*GridText.ps1*"
    }
}
