# Nouveautés (Changelog.ps1): which versions of CHANGELOG.md it reads, when it opens at start, and how it reads a line's
# Markdown.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    $script:Sample = Join-Path ([System.IO.Path]::GetTempPath()) 'repere-changelog-test.md'
    Set-Content -LiteralPath $script:Sample -Encoding utf8 -Value @(
        '# Journal des versions', '', '## À venir', '- Pas encore sorti.', '',
        '## 0.16.0 — 2026-12-01', '', '### Ordinateurs', '- **Un point** gras.', '  - Un sous-point.', '  Un paragraphe du point.', '',
        '## 0.15.0 — 2026-11-19', '- Le 0.15.0.', '',
        '## 0.14.2 — 2026-11-10', '- Le 0.14.2.'
    )
}

AfterAll { Remove-Item -LiteralPath $script:Sample -ErrorAction SilentlyContinue }

Describe 'Read-ChangelogEntry' {
    It 'Reads each version, newest first, without « À venir »' {
        $entries = @(Read-ChangelogEntry $script:Sample)
        ($entries | ForEach-Object { "$($_.Version)" }) -join ', ' | Should -BeExactly '0.16.0, 0.15.0, 0.14.2'
        $entries[0].Heading | Should -BeExactly '0.16.0 — 2026-12-01'
        @($entries[0].Lines | Where-Object { $_ }) -join '|' | Should -BeExactly '### Ordinateurs|- **Un point** gras.|  - Un sous-point.|  Un paragraphe du point.'
    }

    It 'Reads nothing from a file that is not there' {
        @(Read-ChangelogEntry (Join-Path $script:Sample 'absent.md')).Count | Should -Be 0
    }

    It "Reads the repo's own CHANGELOG.md, this version's entry included" {
        $versions = @(Read-ChangelogEntry $script:ChangelogPath | ForEach-Object { "$($_.Version)" })
        # The main script's version: it isn't loaded here.
        $version = [regex]::Match((Get-Content -LiteralPath $script:RepereMainScript -Raw), "RepereVersion = '([\d.]+)'").Groups[1].Value
        $version | Should -Not -BeNullOrEmpty
        $versions | Should -Contain $version
    }
}

Describe 'Get-ChangelogStart and Select-ChangelogEntry: what opens at start' {
    BeforeAll {
        function Get-Shown($Saved, [bool]$HadSettings, [string]$Current = '0.16.0') {
            $from = Get-ChangelogStart $Saved $HadSettings $Current
            if ($null -eq $from) { return 'nothing' }
            (Select-ChangelogEntry @(Read-ChangelogEntry $script:Sample) $from $Current | ForEach-Object { "$($_.Version)" }) -join ', '
        }
    }

    It 'After an update: every version since the one seen' {
        Get-Shown ([pscustomobject]@{ SeenVersion = '0.14.2'; ShowChangelog = $null }) $true | Should -BeExactly '0.16.0, 0.15.0'
    }

    It 'The same version again, or an older one: nothing' {
        Get-Shown ([pscustomobject]@{ SeenVersion = '0.16.0'; ShowChangelog = $null }) $true | Should -BeExactly 'nothing'
        Get-Shown ([pscustomobject]@{ SeenVersion = '0.17.0'; ShowChangelog = $null }) $true | Should -BeExactly 'nothing'
    }

    It 'From a Repère that saved no version (0.15.0 and before): this version only' {
        Get-Shown ([pscustomobject]@{ SeenVersion = $null; ShowChangelog = $null }) $true | Should -BeExactly '0.16.0'
        Get-Shown $null $true | Should -BeExactly '0.16.0'
    }

    It 'A new install: nothing' {
        Get-Shown $null $false | Should -BeExactly 'nothing'
    }

    It '« Ne plus afficher »: nothing, whatever the version seen' {
        Get-Shown ([pscustomobject]@{ SeenVersion = '0.14.2'; ShowChangelog = $false }) $true | Should -BeExactly 'nothing'
        Get-Shown ([pscustomobject]@{ SeenVersion = '0.14.2'; ShowChangelog = $true }) $true | Should -BeExactly '0.16.0, 0.15.0'
    }

    It 'A version seen that does not read as one counts as none' {
        Get-Shown ([pscustomobject]@{ SeenVersion = 'abc'; ShowChangelog = $null }) $true | Should -BeExactly '0.16.0'
    }

    It 'A version with no entry yet (a build between releases): nothing to show' {
        Get-Shown ([pscustomobject]@{ SeenVersion = '0.16.0'; ShowChangelog = $null }) $true '0.16.1' | Should -BeExactly ''
    }
}

Describe 'ConvertFrom-ChangelogLine and ConvertFrom-ChangelogInline: the Markdown read' {
    It '<Line>' -ForEach @(
        @{ Line = '### Ordinateurs'; Expected = 'Section 0 Ordinateurs' }
        @{ Line = '#### Apparence'; Expected = 'Subsection 0 Apparence' }
        @{ Line = '- Un point.'; Expected = 'Point 0 Un point.' }
        @{ Line = '  - Un sous-point.'; Expected = 'Point 1 Un sous-point.' }
        @{ Line = '  Un paragraphe du point.'; Expected = 'Text 1 Un paragraphe du point.' }
        @{ Line = 'Première version publiée.'; Expected = 'Text 0 Première version publiée.' }
        @{ Line = '*Déplacer vers* reste.'; Expected = 'Text 0 *Déplacer vers* reste.' }
    ) {
        $item = ConvertFrom-ChangelogLine $Line
        "$($item.Kind) $($item.Level) $($item.Text)" | Should -BeExactly $Expected
    }

    It 'A blank line is nothing' {
        ConvertFrom-ChangelogLine '   ' | Should -BeNullOrEmpty
    }

    It 'Bold, italic and code, the rest as it is' {
        $parts = ConvertFrom-ChangelogInline '**Prochain nom…** et *Déplacer vers* (`10.0.1.*`), 2 * 3'
        ($parts | ForEach-Object { "$($_.Kind):$($_.Text)" }) -join '|' | Should -BeExactly 'Bold:Prochain nom…|Plain: et |Italic:Déplacer vers|Plain: (|Code:10.0.1.*|Plain:), 2 * 3'
    }
}
