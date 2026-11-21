# Loads Repère's code without its window, dot-sourced by a test file's BeforeAll: WPF first (some files make WPF
# objects as they load, timers and brushes), every file the main script dot-sources before its window, in its order, and the row
# builder's helpers; then the forest's domains as the fake AD has them. The settings' paths point to a folder that
# doesn't exist while the files load, so nothing of the user's own (%APPDATA%\Repere) is read.

. (Join-Path $PSScriptRoot 'TestSetup.ps1')
# Strict mode: a variable never set, or a property an object doesn't have, is an error instead of a silent $null.
Set-StrictMode -Version Latest
Add-Type -AssemblyName PresentationFramework
$script:SavedAppData = $env:APPDATA
$env:APPDATA = Join-Path ([System.IO.Path]::GetTempPath()) 'repere-unit-tests-appdata'
try {
    foreach ($repereFile in Get-RepereDotSourcedPath -BeforeWindow) { . $repereFile }
    . (Get-RepereRowBuilder)
}
finally { $env:APPDATA = $script:SavedAppData }
$script:domainList = 'demo.local', 'nord.demo.local'
