# What Repère keeps from one launch to the next, in %APPDATA%\Repere: a JSON file per part, so a file that can't be
# read only loses its own part. apparence.json (Theme.ps1), parametres.json (Paramètres' Déplacer vers and the
# language: SettingsWindow.ps1, Language.ps1), recherche.json (ComputerPage.ps1, SearchPage.ps1), redemarrage.json
# (RestartDialog.ps1), motdepasse.json (UserPage.ps1), fenetre.json and version.json (the main script). Each file's own
# code says what its values may be, and keeps its defaults for the others; Read-JsonSetting and Save-JsonSetting read
# and write them all the same way. prochainnom.json is Prochain nom…'s (NextName.ps1), and parametres.json also holds
# its SCCM site. Dot-sourced by the main script, first.

$script:SettingsFolder = Join-Path $env:APPDATA 'Repere'
# The files that were there but couldn't be read this run, by name, each with why (apparence.json -> its JSON error):
# the main script says so in a toast once the window shows, since the console is hidden, and Save-JsonSetting moves
# each aside before writing it. All read on the main runspace: the background ones never read settings files.
$script:UnreadableSettings = [ordered]@{}

function Get-SettingPath([string]$Name) {
    # A settings file's path, by its name (apparence.json).
    Join-Path $script:SettingsFolder $Name
}

function Read-JsonSetting([string]$Path, [string[]]$Property, [ref]$Unreadable) {
    # The file's settings: only $Property, each $null when the file doesn't have it (an older or newer Repère wrote it),
    # strict mode or not; all of them without $Property. $null when the file is missing or empty: its defaults. A file
    # that can't be read gives $null too, and says so in the console and in $script:UnreadableSettings rather than
    # silently. -Unreadable tells the two apart: $true when the file is there but can't be read (a hand-edited
    # parametres.json with a JSON mistake), which a save mustn't take for no settings at all (#243).
    if ($Unreadable) { $Unreadable.Value = $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        # An empty file, or « null », reads as nothing.
        if (-not "$text".Trim()) { return }
        $saved = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "$(Split-Path $Path -Leaf) illisible, valeurs par défaut : $_"
        $script:UnreadableSettings[(Split-Path $Path -Leaf)] = "$_"
        if ($Unreadable) { $Unreadable.Value = $true }
        return
    }
    if ($null -eq $saved) { return }
    if ($Property) { $saved | Select-Object $Property } else { $saved }
}

function Save-JsonSetting([string]$Path, $Setting, [int]$Depth = 2, [switch]$Merge) {
    # $Setting (a hashtable, ordered for a file that reads well) as the file, its folder made first. -Merge: the file's
    # other settings are kept as they are (parametres.json, which Paramètres and the language both write). Not being able
    # to save (a read-only profile) mustn't get in the way: said in the console.
    try {
        # A file that's there but can't be read has settings this save can't keep: it's moved aside, as it is, to
        # <name>.illisible (the last one kept), rather than written over (#243), as the toast at start says. Read again
        # for -Merge, which needs its settings anyway, and for a file this run found unreadable (fenetre.json is saved
        # at every close, whole): it may have been corrected since. Not Move-Item: onto a folder of that name, it
        # would move the file into it. When it can't be moved, nothing is saved.
        $name = Split-Path $Path -Leaf
        $unreadable = $false
        $saved = if ($Merge -or $script:UnreadableSettings.Contains($name)) { Read-JsonSetting $Path -Unreadable ([ref]$unreadable) }
        if ($unreadable) {
            [System.IO.File]::Move($Path, "$Path.illisible", $true)
            # Moved: the next save of it writes it as any other.
            $script:UnreadableSettings.Remove($name)
        }
        if ($Merge) {
            $settings = [ordered]@{}
            if ($saved) { foreach ($property in $saved.PSObject.Properties) { $settings[$property.Name] = $property.Value } }
            foreach ($key in $Setting.Keys) { $settings[$key] = $Setting[$key] }
            $Setting = $settings
        }
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $Path) -ErrorAction Stop
        # Beside it first: stopped halfway, the file stays whole.
        $Setting | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath "$Path.tmp" -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath "$Path.tmp" -Destination $Path -Force -ErrorAction Stop
    }
    catch {
        Write-Host "$(Split-Path $Path -Leaf) non enregistré : $_"
        Remove-Item -LiteralPath "$Path.tmp" -ErrorAction Ignore
    }
}
