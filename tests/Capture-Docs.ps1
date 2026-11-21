# Takes the documentation's screenshots again, on the sample data, all in the same look: the dark Repère theme, the
# « ORD » search in demo.local with ORD-01 selected; in French for docs\fr, in English (-Language en) for docs\en.
# Reuses Test-RepereUI.ps1's helpers (its functions only), so it drives the window the same way: don't use the mouse
# or keyboard meanwhile.
#
#   .\tests\Capture-Docs.ps1                      (every screenshot, in French, into docs\fr\images)
#   .\tests\Capture-Docs.ps1 -Language en         (in English, into docs\en\images)
#   .\tests\Capture-Docs.ps1 -Only menu, groupes  (only these)
[CmdletBinding()]
param(
    # Where the screenshots go, each <name>.png: docs\<language>\images by default.
    [string]$OutDir,
    # Repère's language in the screenshots.
    [ValidateSet('fr', 'en')]
    [string]$Language = 'fr',
    # Only these: apercu, avancee, menu, bitlocker, laps, prochain-nom, caracteristiques, prendre-la-main, apparence,
    # utilisateurs, reinitialiser, proprietes, groupes.
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutDir) { $OutDir = Join-Path $repo "docs\$Language\images" }

# In English, every name the window is driven by is Language.en.psd1's English for it: T in the captures below, and
# the helpers' own names translated as they're loaded. Case and accents count, as in Repère.
$script:English = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
if ($Language -eq 'en') {
    foreach ($pair in (Import-PowerShellDataFile (Join-Path $repo 'src\Language.en.psd1')).Text) { $script:English[$pair[0]] = $pair[1] }
}
function T([string]$Text) {
    if ($Language -ne 'en') { return $Text }
    if (-not $script:English.ContainsKey($Text)) { throw "No English for '$Text' in Language.en.psd1." }
    $script:English[$Text]
}
function Get-EnglishString([System.Management.Automation.Language.Ast]$String) {
    # A string's text in English, quoted, or $null when Language.en.psd1 has none: a constant as it is, and a string
    # with variables ("$Name sélectionné") as Tr is given it ('{0} sélectionné'), its variables put back in its English.
    if ($String -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        if ($String.StringConstantType -notin 'SingleQuoted', 'DoubleQuoted' -or -not $script:English.ContainsKey($String.Value)) { return $null }
        return "'" + ($script:English[$String.Value] -replace "'", "''") + "'"
    }
    if ($String.StringConstantType -ne 'DoubleQuoted') { return $null }
    $inner = $String.Extent.Text.Substring(1, $String.Extent.Text.Length - 2)
    $parts = @($String.NestedExpressions | Sort-Object { $_.Extent.StartOffset })
    for ($index = $parts.Count - 1; $index -ge 0; $index--) {
        $start = $parts[$index].Extent.StartOffset - $String.Extent.StartOffset - 1
        $inner = $inner.Remove($start, $parts[$index].Extent.Text.Length).Insert($start, "{$index}")
    }
    if (-not $script:English.ContainsKey($inner)) { return $null }
    $english = $script:English[$inner] -replace '`', '``' -replace '"', '`"' -replace '\$', '`$'
    for ($index = 0; $index -lt $parts.Count; $index++) { $english = $english.Replace("{$index}", $parts[$index].Extent.Text) }
    '"' + $english + '"'
}

function Get-HelperText([System.Management.Automation.Language.Ast]$Node) {
    # The helper's text, in English: each string Language.en.psd1 has an English text for replaced by it.
    $text = $Node.Extent.Text
    if ($Language -ne 'en') { return $text }
    $strings = $Node.FindAll({ param($part) $part -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                                            $part -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
    # Outermost first in each place, from the end, so that an offset never moves before it's used.
    $done = -1
    foreach ($string in @($strings | Sort-Object { $_.Extent.StartOffset }, { -$_.Extent.Text.Length } -Descending)) {
        if ($done -ge 0 -and $string.Extent.EndOffset -gt $done) { continue }
        $english = Get-EnglishString $string
        if ($null -eq $english) { continue }
        $start = $string.Extent.StartOffset - $Node.Extent.StartOffset
        $text = $text.Remove($start, $string.Extent.Text.Length).Insert($start, $english)
        $done = $string.Extent.StartOffset
    }
    # What a helper doesn't build as Tr does: the language Repère starts in, and the end of a reading, by pattern.
    $patterns = [ordered]@{
        '-Language fr'                     = '-Language en'
        "'^(Lu en|Échec|Lecture annulée)'" = "'^(Read in|Reading failed|Failed|Reading canceled)'"
    }
    foreach ($french in $patterns.Keys) { $text = $text.Replace($french, $patterns[$french]) }
    $text
}

$testFile = Join-Path $repo 'tests\Test-RepereUI.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($testFile, [ref]$null, [ref]$null)
$functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Parent -eq $ast.EndBlock }, $false)
$helpers = ($functions | ForEach-Object { Get-HelperText $_ }) -join "`n`n"
# Each name these helpers build or match by pattern must still be there, or the English screenshots would wait in vain.
if ($Language -eq 'en') {
    foreach ($french in '-Language fr', "'^(Lu en|Échec|Lecture annulée)'") {
        if (-not ($functions.Extent.Text -match [regex]::Escape($french))) { throw "Test-RepereUI.ps1 no longer has $($french): update Get-HelperText." }
    }
}
. ([scriptblock]::Create($helpers))
# The menu helpers know the submenus by name.
foreach ($statement in $ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$menuGroups' }) {
    . ([scriptblock]::Create((Get-HelperText $statement)))
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
if (-not ('RepereWindows' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RepereWindows {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
}
'@
}
$AE = [System.Windows.Automation.AutomationElement]
$Descendants = [System.Windows.Automation.TreeScope]::Descendants
# What Test-RepereUI.ps1's helpers read: the app, its window's name, the pwsh to start it with, where screenshots go.
$script:appScript = Join-Path $repo 'src\Repere - Recherche PC AD par description.ps1'
$script:windowName = "$(T 'Repère') ($(T 'AD fictif'))"
$script:pwsh = (Get-Process -Id $PID).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:ScreenshotDirectory = (Resolve-Path $OutDir).Path

function Test-Wanted([string]$Name) { -not $Only -or $Only -contains $Name }

function Invoke-Capture([string[]]$Names) {
    # Starts Repère on the sample data with settings of its own (the dark Repère theme), takes these screenshots and
    # closes it.
    $Names = @($Names | Where-Object { Test-Wanted $_ })
    if (-not $Names) { return }
    $previousAppData = $env:APPDATA
    $appData = Join-Path ([IO.Path]::GetTempPath()) "repere-capture-appdata-$PID"
    New-Item -ItemType Directory -Force -Path (Join-Path $appData 'Repere') | Out-Null
    '{"Theme":"Sombre","Scheme":"Repere"}' | Set-Content (Join-Path $appData 'Repere\apparence.json') -Encoding utf8
    $env:APPDATA = $appData
    $env:REPERE_FAKEAD_LOG = Join-Path ([IO.Path]::GetTempPath()) "repere-capture-$PID.log"
    try {
        Start-App
        Start-Sleep -Seconds 2
        Select-Domain 'demo.local'
        Invoke-PrefixSearch 'ORD'
        Select-ResultRow 'ORD-01'
        Start-Sleep -Milliseconds 500
        foreach ($name in $Names) {
            & $script:Captures[$name]
            Write-Host $name
        }
    }
    finally {
        Stop-App
        $env:APPDATA = $previousAppData
        Remove-Item $env:REPERE_FAKEAD_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:REPERE_FAKEAD_LOG -ErrorAction SilentlyContinue
        Remove-Item $appData -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Each screenshot, in this order: the computer page's with ORD-01 selected, then Utilisateurs' and Groupes'.
$script:Captures = [ordered]@{
    'apercu'           = { Save-Screenshot 'apercu' }
    'avancee'          = {
        # Avancée's popup: OUs named Communs, disabled, logged on less than 2 weeks ago. Its criteria are taken
        # back off after, for the next screenshots.
        Open-AdvancedSearch
        Select-AdvancedButton 'scope_name'
        Set-Text 'advanced_ou_name' 'Communs'
        Select-AdvancedButton 'state_disabled'
        Select-AdvancedButton 'logon_less'
        Set-Text 'advanced_logon_number' '2'
        Select-AdvancedButton 'logon_unit1'
        Start-Sleep -Milliseconds 500
        Save-Screenshot 'avancee'
        Invoke-Element (Find-Control 'advanced_reset')
        Close-AdvancedSearch
        Start-Sleep -Milliseconds 300
    }
    'menu'             = {
        # The right-click menu with Outils à distance open. A submenu's popup belongs to the menu's popup: every
        # window under the main one, for Save-Screenshot to draw them all.
        $null = Open-ResultMenu
        $null = Open-MenuGroup (T 'Outils à distance')
        function Get-AppWindow {
            $isWindow = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
            @($window.FindAll($Descendants, $isWindow))
        }
        Start-Sleep -Milliseconds 1200
        Save-Screenshot 'menu'
        Close-Menu
    }
    'bitlocker'        = {
        # ORD-09's keys: two disks, one with an old key.
        Select-ResultRow 'ORD-09'
        Invoke-ResultMenuItem (T 'Clés BitLocker…')
        $dialog = Wait-Dialog (T 'Clés BitLocker')
        Start-Sleep -Milliseconds 600
        Save-Screenshot 'bitlocker' $dialog
        $dialog.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Wait-DialogsClosed
    }
    'laps'             = {
        # The LAPS passwords of ORD-01 (Windows LAPS) and ORD-04 (legacy LAPS).
        Select-ResultRow 'ORD-01'
        Add-ResultRow 'ORD-04'
        Invoke-ResultMenuItem (T 'Mot de passe LAPS…')
        $dialog = Wait-Dialog (T 'Mot de passe LAPS')
        Start-Sleep -Milliseconds 600
        Save-Screenshot 'laps' $dialog
        $dialog.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Wait-DialogsClosed
        # ORD-01 alone can't be selected while it's one of two: another row first.
        Select-ResultRow 'ORD-09'
    }
    'prochain-nom'     = {
        # The next ORD-## names, the series offered and the blocks shown.
        $dialog = Open-NextName
        Set-DialogText $dialog 'next_format' 'ORD-##'
        $null = Wait-NextName $dialog 'ORD-13'
        Start-Sleep -Milliseconds 600
        Save-Screenshot 'prochain-nom' $dialog
        Close-Dialog $dialog 'dialog_cancel'
    }
    'caracteristiques' = {
        # ORD-01's Caractéristiques: every section closed to its summary, but Écrans.
        Select-ResultRow 'ORD-01'
        Invoke-Element (Find-Control 'act_specs')
        $specsWindow = Wait-SpecsWindow 'ORD-01'
        Invoke-Element (Get-DialogPart $specsWindow 'spec_collapse_all')
        Start-Sleep -Milliseconds 300
        Invoke-Element (Get-DialogPart $specsWindow 'toggle_Monitor')
        Start-Sleep -Milliseconds 800
        Save-Screenshot 'caracteristiques' $specsWindow
        Close-SpecsWindow $specsWindow
    }
    'prendre-la-main'  = {
        # ORD-01's two sessions.
        Select-ResultRow 'ORD-01'
        Invoke-ResultMenuItem (T 'Prendre la main…')
        $dialog = Wait-Dialog (T 'Prendre la main')
        Start-Sleep -Milliseconds 600
        Save-Screenshot 'prendre-la-main' $dialog
        Close-Dialog $dialog 'dialog_cancel'
    }
    'apparence'        = {
        # Paramètres › Apparence: the mode and the list of themes.
        $null = Find-PopupControl 'theme_list' 'settings'
        $settings = Wait-Dialog (T 'Paramètres')
        Start-Sleep -Milliseconds 800
        Save-Screenshot 'apparence' $settings
        $settings.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        Start-Sleep -Milliseconds 500
    }
    'utilisateurs'     = {
        # The Bertrand of both domains, Julie selected.
        Show-UserPage
        Start-Sleep -Milliseconds 400
        $null = Invoke-UserSearch (T 'Tous les domaines') (T 'Nom, identifiant ou courriel') 'bert'
        Select-UserRow 'Julie Bertrand'
        Start-Sleep -Milliseconds 400
        Save-Screenshot 'utilisateurs'
    }
    'reinitialiser'    = {
        # Luc Lefebvre's new password, a generated one.
        Show-UserPage
        $null = Invoke-UserSearch 'demo.local' (T 'Nom, identifiant ou courriel') 'lefebvre'
        Select-UserRow 'Luc Lefebvre'
        Invoke-Element (Find-Control 'user_reset')
        $dialog = Wait-Dialog (T 'Nouveau mot de passe')
        Start-Sleep -Milliseconds 500
        Save-Screenshot 'reinitialiser' $dialog
        Close-Dialog $dialog 'dialog_cancel'
    }
    'proprietes'       = {
        # Marc Durand's Propriétés: a locked account.
        Show-UserPage
        $details = Open-UserDetail (T 'Nom, identifiant ou courriel') 'durand' 'Marc Durand'
        Start-Sleep -Milliseconds 500
        Save-Screenshot 'proprietes' $details
        Close-UserDetail $details
    }
    'groupes'          = {
        # GG-Accueil's Propriétés: its members, the group it's in, who manages it.
        Show-GroupPage
        $details = Open-GroupDetail (T 'Nom contient') 'accueil' 'GG-Accueil'
        Start-Sleep -Milliseconds 500
        Save-Screenshot 'groupes' $details
        Close-UserDetail $details
    }
}
$unknown = @($Only | Where-Object { $_ -and -not $script:Captures.Contains($_) })
if ($unknown) { throw "Unknown screenshot: $($unknown -join ', '). Known: $($script:Captures.Keys -join ', ')." }

$script:app = $null
$script:window = $null
Invoke-Capture @($script:Captures.Keys)
