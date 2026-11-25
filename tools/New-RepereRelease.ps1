# Builds Repère's release: dist\Repere-<version>.zip, holding only what Repère needs to run (the main script and every
# file it dot-sources, its English text, the Repère.cmd launcher, the icon, the fonts), the changelogs and the
# licences; not the README and its screenshots, the tests, the tools or the sample data (FakeAD). The version is the
# main script's $script:RepereVersion. Only files git tracks go in, as they are in the last commit: it refuses when one
# of them has uncommitted changes, so a zip always matches a commit. The release notes are that version's CHANGELOG.md
# entry and nothing else: it writes them to dist\Repere-<version>.md (for gh release create --notes-file), and refuses
# when CHANGELOG.md has no entry for it.
#
#   .\tools\New-RepereRelease.ps1
[CmdletBinding()]
param(
    # Where the zip goes.
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mainName = 'Repere - Recherche PC AD par description.ps1'

function Get-DotSourcedName([string]$Path) {
    # The files a script dot-sources as . "$PSScriptRoot\Name.ps1", and those they dot-source in turn, by name.
    $tokens = $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "$Path doesn't parse: $($errors[0].Message)" }
    $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq 'Dot' }, $true)
    foreach ($command in $commands) {
        $target = $command.CommandElements[0]
        if ($target -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and $target.Value -match '^\$PSScriptRoot[\\/](.+\.ps1)$') {
            $Matches[1]
            Get-DotSourcedName (Join-Path (Split-Path $Path) $Matches[1])
        }
    }
}

# The version, as the main script sets it.
$mainPath = Join-Path $repo "src\$mainName"
$versionLine = Select-String -LiteralPath $mainPath -Pattern "^\`$script:RepereVersion = '(?<version>\d+\.\d+\.\d+)'" | Select-Object -First 1
if (-not $versionLine) { throw "No `$script:RepereVersion = '<x.y.z>' in $mainName." }
$version = $versionLine.Matches[0].Groups['version'].Value

# The release notes: this version's CHANGELOG.md entry, without its heading (the release's title names the version).
$changelog = @(Get-Content -LiteralPath (Join-Path $repo 'CHANGELOG.md') -Encoding utf8)
$start = [array]::FindIndex($changelog, [Predicate[string]] { param($line) $line -match "^## $([regex]::Escape($version))(\s|$)" })
if ($start -lt 0) { throw "No '## $version' entry in CHANGELOG.md: add what this version changes first." }
$end = [array]::FindIndex($changelog, $start + 1, [Predicate[string]] { param($line) $line -match '^## ' })
if ($end -lt 0) { $end = $changelog.Count }
# What's new in English is CHANGELOG.en.md's: the same version must be in it.
if (-not (Select-String -LiteralPath (Join-Path $repo 'CHANGELOG.en.md') -Pattern "^## $([regex]::Escape($version))(\s|$)" -Quiet)) {
    throw "No '## $version' entry in CHANGELOG.en.md: translate this version's changes first."
}
$notes = if ($end -gt $start + 1) { ($changelog[($start + 1)..($end - 1)] -join "`r`n").Trim() }
if (-not $notes) { throw "CHANGELOG.md's $version entry is empty." }

# The Windows releases' table (PCSpecs.ps1), which says which computers are out of support: a warning, not a refusal,
# when it looks stale. A Windows 11 release is supported 24 months for Home and Pro, and a new one ships every year: so
# while the table is up to date, its newest release's end for Pro is more than a year away. Less than that, a release
# has most likely shipped since, which the table doesn't have: its computers then show only their build, without an end
# of support.
$releaseEnds = @(Select-String -LiteralPath (Join-Path $repo 'src\PCSpecs.ps1') -Pattern "^\s*\d{5} = @\{ Name = '[^']+'; Pro = \[datetime\]'(\d{4}-\d{2}-\d{2})'" |
    ForEach-Object { [datetime]::ParseExact($_.Matches[0].Groups[1].Value, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) })
if (-not $releaseEnds.Count) { Write-Warning "Table des versions de Windows introuvable dans src\PCSpecs.ps1 (`$script:WindowsReleases) : vérifiez-la à la main." }
else {
    $newestEnd = ($releaseEnds | Measure-Object -Maximum).Maximum
    if ($newestEnd -lt (Get-Date).Date.AddMonths(12)) {
        Write-Warning ("La version de Windows la plus récente de src\PCSpecs.ps1 (`$script:WindowsReleases) n'est plus supportée (Pro) après le {0:yyyy-MM-dd}, dans moins d'un an : une version plus récente est sans doute sortie. Ajoutez-la d'après learn.microsoft.com/windows/release-health." -f $newestEnd)
    }
}

# What goes in: the scripts by what the main one dot-sources, the folders and files by what git tracks.
# Names as they are (Repère.cmd, not "Rep\303\250re.cmd"), read as UTF-8 whatever the console's code page.
$consoleEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $tracked = @(git -C $repo -c core.quotepath=off ls-files)
}
finally { [Console]::OutputEncoding = $consoleEncoding }
if ($LASTEXITCODE) { throw 'git ls-files failed: run this from a clone of the repository.' }
$scripts = @($mainName) + @(Get-DotSourcedName $mainPath | Select-Object -Unique) | ForEach-Object { "src/$_" }
$files = @($scripts) + @($tracked | Where-Object { $_ -match '^src/fonts/' -or $_ -in 'Repère.cmd', 'src/Language.en.psd1', 'src/compass.png', 'src/compass.ico', 'LICENSE', 'CHANGELOG.md', 'CHANGELOG.en.md' })
$files = @($files | ForEach-Object { $_ -replace '\\', '/' } | Select-Object -Unique)
$missing = @($files | Where-Object { $tracked -notcontains $_ })
if ($missing) { throw "Not tracked by git: $($missing -join ', ')." }
$changed = @(git -C $repo status --porcelain -- $files)
if ($changed) { throw "Uncommitted changes, commit them first:`n$($changed -join "`n")" }

# A folder named after the release, zipped: extracted, it gives Repere-<version>\ with everything in it.
$name = "Repere-$version"
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "repere-release-$PID"
$folder = Join-Path $staging $name
Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
try {
    foreach ($file in $files) {
        $target = Join-Path $folder $file
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        # The working tree's copy: as committed, since none of these files has changes.
        Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $target
    }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $zip = Join-Path (Resolve-Path $OutDir).Path "$name.zip"
    Remove-Item -LiteralPath $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path $folder -DestinationPath $zip -CompressionLevel Optimal
}
finally { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
$notesPath = Join-Path (Split-Path $zip) "$name.md"
Set-Content -LiteralPath $notesPath -Value $notes -Encoding utf8NoBOM

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Write-Host "$zip"
Write-Host "  version $version, $($files.Count) fichiers ($($scripts.Count) scripts), $([Math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)) Mo"
Write-Host "  SHA-256 $hash"
Write-Host "$notesPath"
Write-Host "  notes de la release : l'entrée $version de CHANGELOG.md"
