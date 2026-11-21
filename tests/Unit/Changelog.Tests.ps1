# Nouveautés (Changelog.ps1): which entry of CHANGELOG.md it reads, when it opens at start, and the headlines it
# shows of it.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    $script:Sample = Join-Path ([System.IO.Path]::GetTempPath()) 'repere-changelog-test.md'
    Set-Content -LiteralPath $script:Sample -Encoding utf8 -Value @(
        '# Journal des versions', '', '## À venir', '- Pas encore sorti.', '',
        '## 0.16.0 — 2026-12-01', '',
        '### Ordinateurs', '- **Un** : premier point.', '  - Un sous-point.', '  Un paragraphe du point.', '- Deuxième. Son détail.',
        '#### Caractéristiques', '- Troisième.', '- Quatrième.', '- Cinquième.', '',
        '### Groupes', '- Seul point.',
        '## 0.15.0 — 2026-11-19', '- Le 0.15.0.'
    )
}

AfterAll { Remove-Item -LiteralPath $script:Sample -ErrorAction SilentlyContinue }

Describe 'Read-ChangelogEntry and Get-ChangelogEntry' {
    It 'Reads each version, newest first, without « À venir »' {
        $entries = @(Read-ChangelogEntry $script:Sample)
        ($entries | ForEach-Object { "$($_.Version)" }) -join ', ' | Should -BeExactly '0.16.0, 0.15.0'
        $entries[0].Heading | Should -BeExactly '0.16.0 — 2026-12-01'
    }

    It "Gets one version's entry, none for a version it doesn't have or a file that isn't there" {
        (Get-ChangelogEntry $script:Sample '0.15.0').Heading | Should -BeExactly '0.15.0 — 2026-11-19'
        Get-ChangelogEntry $script:Sample '0.16.1' | Should -BeNullOrEmpty
        Get-ChangelogEntry (Join-Path $script:Sample 'absent.md') '0.16.0' | Should -BeNullOrEmpty
    }

    It "Gets this version's entry from the repo's own CHANGELOG.md" {
        # The main script's version: it isn't loaded here.
        $version = [regex]::Match((Get-Content -LiteralPath $script:RepereMainScript -Raw), "RepereVersion = '([\d.]+)'").Groups[1].Value
        $version | Should -Not -BeNullOrEmpty
        Get-ChangelogEntry $script:ChangelogPath $version | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-ChangelogStart: whether it opens at start' {
    It '<Name>' -ForEach @(
        @{ Name = 'After an update'; Seen = '0.15.0'; Show = $null; Had = $true; Expected = $true }
        @{ Name = 'The same version again'; Seen = '0.16.0'; Show = $null; Had = $true; Expected = $false }
        @{ Name = 'An older version than the one seen'; Seen = '0.17.0'; Show = $null; Had = $true; Expected = $false }
        @{ Name = 'After a Repère that saved no version (0.15.0 and before)'; Seen = $null; Show = $null; Had = $true; Expected = $true }
        @{ Name = 'A new install'; Seen = $null; Show = $null; Had = $false; Expected = $false }
        @{ Name = '« Ne plus afficher »'; Seen = '0.15.0'; Show = $false; Had = $true; Expected = $false }
        @{ Name = '« Ne plus afficher » unticked'; Seen = '0.15.0'; Show = $true; Had = $true; Expected = $true }
    ) {
        Test-ChangelogStart ([pscustomobject]@{ SeenVersion = $Seen; ShowChangelog = $Show }) $Had '0.16.0' | Should -Be $Expected
    }

    It 'Without parametres.json: as after a Repère that saved no version' {
        Test-ChangelogStart $null $true '0.16.0' | Should -BeTrue
        Test-ChangelogStart $null $false '0.16.0' | Should -BeFalse
    }

    It 'A version seen that does not read as one counts as none: <Seen>' -ForEach @(
        @{ Seen = 'abc' }, @{ Seen = '0.15' }, @{ Seen = '99999999999.0.0' }
    ) {
        Get-ChangelogSeen ([pscustomobject]@{ SeenVersion = $Seen }) | Should -BeNullOrEmpty
        Test-ChangelogStart ([pscustomobject]@{ SeenVersion = $Seen; ShowChangelog = $null }) $true '0.16.0' | Should -BeTrue
    }
}

Describe 'Get-ChangelogSummary: the headlines it shows' {
    It "Each section with its first points' headlines and how many others; a #### section counts in its ###" {
        $summary = @(Get-ChangelogSummary (Get-ChangelogEntry $script:Sample '0.16.0') 3)
        ($summary | ForEach-Object { "$($_.Name): $($_.Headlines -join ' / ') (+$($_.Others))" }) -join ' | ' |
            Should -BeExactly 'Ordinateurs: **Un** : premier point / Deuxième / Troisième (+2) | Groupes: Seul point (+0)'
    }

    It "Points before any section are in one without a name" {
        $summary = @(Get-ChangelogSummary (Get-ChangelogEntry $script:Sample '0.15.0'))
        $summary.Count | Should -Be 1
        $summary[0].Name | Should -BeExactly ''
        $summary[0].Headlines | Should -BeExactly 'Le 0.15.0'
    }

    It "Every version of the repo's CHANGELOG.md has headlines" {
        foreach ($entry in Read-ChangelogEntry $script:ChangelogPath) {
            @(Get-ChangelogSummary $entry | ForEach-Object Headlines | Where-Object { $_ }).Count | Should -BeGreaterThan 0 -Because $entry.Heading
        }
    }
}

Describe 'Get-ChangelogHeadline: a point cut to its headline' {
    It '<Text>' -ForEach @(
        @{ Text = '**Le texte tapé ne saute plus d''un pixel** en Bureau à distance, surtout en Compacte.'; Expected = '**Le texte tapé ne saute plus d''un pixel**' }
        @{ Text = '**Le texte ne saute plus** en Bureau à distance. La suite.'; Expected = '**Le texte ne saute plus** en Bureau à distance' }
        @{ Text = '**La fenêtre s''ouvre devant** : elle s''ouvrait derrière.'; Expected = '**La fenêtre s''ouvre devant**' }
        @{ Text = '**Propriétés** : au-delà de 10 groupes, une case. Les cases cochées le restent.'; Expected = '**Propriétés** : au-delà de 10 groupes, une case' }
        @{ Text = '**L''info-bulle du temps de recherche** (« en 1 234 ms ») est un petit tableau : un domaine par ligne.'; Expected = '**L''info-bulle du temps de recherche** (« en 1 234 ms ») est un petit tableau' }
        @{ Text = '**Caractéristiques** copie et exporte « Libellé : valeur », sans espaces, pour que le texte reste droit.'; Expected = '**Caractéristiques** copie et exporte « Libellé : valeur »' }
        @{ Text = '**Prochain nom…** a son bouton dans la barre d''actions, son raccourci **Ctrl+N** et un clic droit.'; Expected = '**Prochain nom…** a son bouton dans la barre d''actions' }
        @{ Text = '**Le clic droit** range **Comparer les groupes…**, **Ajouter à un groupe…** et **Retirer** dans **Groupes**, et les copies.'; Expected = '**Le clic droit** range **Comparer les groupes…**, **Ajouter à un groupe…** et **Retirer** dans **Groupes**' }
        @{ Text = 'Le filtre `10.0.1.* : x` reste ; le reste.'; Expected = 'Le filtre `10.0.1.* : x` reste' }
        @{ Text = 'PowerShell 7.6 ou plus récent'; Expected = 'PowerShell 7.6 ou plus récent' }
    ) {
        Get-ChangelogHeadline $Text | Should -BeExactly $Expected
    }
}

Describe 'ConvertFrom-ChangelogInline: the Markdown of a headline' {
    It '<Text>' -ForEach @(
        @{ Text = '**Prochain nom…** et *Déplacer vers* (`10.0.1.*`), 2 * 3'; Expected = 'Bold Plain:Prochain nom…|Plain: et |Italic:Déplacer vers|Plain: (|Code:10.0.1.*|Plain:), 2 * 3' }
        @{ Text = '**Un `parametres.json` illisible** reste.'; Expected = 'Bold Plain:Un |Bold Code:parametres.json|Bold Plain: illisible|Plain: reste.' }
    ) {
        (ConvertFrom-ChangelogInline $Text | ForEach-Object { "$(if ($_.Bold) { 'Bold ' })$($_.Kind):$($_.Text)" }) -join '|' | Should -BeExactly $Expected
    }
}
