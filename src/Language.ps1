# Repère's language: French, the text as the code has it, or English. In English, each French text is replaced by its
# translation from Language.en.psd1 as it's shown: Tr for the code's text, ConvertTo-LocalXaml for the windows' XAML
# (Expand-Icon calls it). A text without a translation stays in French; tests\Unit\Language.Tests.ps1 checks the code
# shows none. The table is the process's (AppDomain data), so Tr works the same on the background runspaces, which get
# it from the row builder ($rowBuilderScript) or from $LanguageScript. Dot-sourced by the main script, first, so that
# the other files' text, made as they load, is in the language already.

# Where the choice is kept: parametres.json, with the other settings of Paramètres (SettingsWindow.ps1 writes it).
$script:LanguageSettingPath = Get-SettingPath 'parametres.json'
# The choice saved in Paramètres: 'fr', 'en', or '' for Windows's language. Read by Initialize-Language.
$script:LanguageChoice = ''
# The language of this run, 'fr' or 'en'. A choice made in Paramètres applies at the next launch.
$script:UILanguage = 'fr'

function Read-SavedLanguage([ref]$Unreadable) {
    # The choice saved in Paramètres: 'fr', 'en' or '' (Windows's); $null when nothing is saved, as before Repère had
    # languages, and when parametres.json can't be read: -Unreadable then says which (Read-JsonSetting's).
    $broken = $false
    $saved = Read-JsonSetting $script:LanguageSettingPath -Unreadable ([ref]$broken)
    if ($Unreadable) { $Unreadable.Value = $broken }
    $language = if ($saved) { $saved.PSObject.Properties['Language'] }
    if ($language -and [string]$language.Value -in 'fr', 'en', '') { return [string]$language.Value }
    $null
}

function Save-LanguageChoice([string]$Choice) {
    # $Choice in parametres.json, the rest of the file as it is (SettingsWindow.ps1's Save-SettingFile writes the same).
    Save-JsonSetting $script:LanguageSettingPath @{ Language = $Choice } -Merge
}

function Resolve-Language([string]$Choice) {
    # 'fr' or 'en': the choice, or else Windows's display language (French gives French, any other English).
    if ($Choice -in 'fr', 'en') { return $Choice }
    if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'fr') { 'fr' } else { 'en' }
}

function Read-TextTable([string]$Path) {
    # Language.en.psd1 as a table, French -> English, case and accents counting. Refuses an entry that isn't
    # @('français', 'English'), or a French text there twice.
    $data = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    $table = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($pair in @($data.Text)) {
        if ($pair -isnot [array] -or $pair.Count -ne 2 -or $pair[0] -isnot [string] -or $pair[1] -isnot [string] -or -not $pair[1]) {
            throw "$Path : chaque entrée est @('français', 'English'), pas : $($pair -join ' | ')"
        }
        if ($table.ContainsKey($pair[0])) { throw "$Path : « $($pair[0]) » y est deux fois." }
        $table[$pair[0]] = $pair[1]
    }
    $table
}

function Initialize-Language([string]$Language, [switch]$ReadOnly) {
    # This run's language: -Language when given, else the choice saved in Paramètres, else Windows's. In English, the
    # table goes in the process's data, where Tr reads it on every runspace. Without a usable Language.en.psd1, French,
    # rather than no window at all. -ReadOnly: nothing is saved (PCSpecs.ps1 run on its own).
    $unreadable = $false
    $script:LanguageChoice = Read-SavedLanguage ([ref]$unreadable)
    if ($null -eq $script:LanguageChoice) {
        # The first run of a Repère with languages. Someone who used it before (settings in %APPDATA%\Repere) keeps
        # French, what they had, whatever Windows's language; a new install follows Windows. Saved, so the next runs
        # don't take the settings this run writes for those of an earlier version. Not when parametres.json is there
        # but can't be read: that's no first run, and the file, left as it is, keeps its Déplacer vers and SCCM for
        # whoever corrects it (#243).
        $folder = Split-Path $script:LanguageSettingPath
        $script:LanguageChoice = if (Get-ChildItem -LiteralPath $folder -Filter *.json -ErrorAction SilentlyContinue) { 'fr' } else { '' }
        if (-not $unreadable -and -not $ReadOnly) { Save-LanguageChoice $script:LanguageChoice }
    }
    $script:UILanguage = Resolve-Language $(if ($Language) { $Language } else { $script:LanguageChoice })
    $table = $null
    if ($script:UILanguage -eq 'en') {
        try { $table = Read-TextTable (Join-Path $PSScriptRoot 'Language.en.psd1') }
        catch {
            Write-Host "Anglais indisponible, Repère reste en français (English unavailable) : $_"
            $script:UILanguage = 'fr'
        }
    }
    [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $table)
}

function Tr([string]$Text) {
    # $Text in this run's language: its English translation, or $Text itself in French or when there's none. For a
    # text with values in it, a format string: (Tr 'Désactiver {0} ordinateurs ?') -f $count.
    $table = [System.AppDomain]::CurrentDomain.GetData('Repere.TextTable')
    if (-not $table) { return $Text }
    $english = $null
    if ($table.TryGetValue($Text, [ref]$english)) { $english } else { $Text }
}

function Get-TextCulture {
    # The culture for dates and numbers shown: fr-CA in French, en-US in English.
    $name = if ([System.AppDomain]::CurrentDomain.GetData('Repere.TextTable')) { 'en-US' } else { 'fr-CA' }
    [System.Globalization.CultureInfo]::GetCultureInfo($name)
}

function Format-TextDate($Date, [switch]$Day) {
    # A date as Repère shows it, in the culture's short form: « 2026-01-15 à 09 h 30 », -Day « 2026-01-15 » (fr-CA), or
    # $null. The CSV exports keep yyyy-MM-dd HH:mm, which sorts.
    if (-not $Date -or $Date -isnot [datetime]) { return $null }
    $culture = Get-TextCulture
    if ($Day) { return $Date.ToString('d', $culture) }
    (Tr '{0} à {1}') -f $Date.ToString('d', $culture), $Date.ToString('t', $culture)
}

# The XAML text a window shows: these attributes' values, a text box's Tag (its placeholder, Theme.ps1), and the text
# between tags (<TextBlock>…</TextBlock>, <Run>…</Run>). Not other Tags, which the code reads as values.
$script:XamlTextPatterns = @(
    '(?<=\s(?:Text|Content|Header|ToolTip|Title|AutomationProperties\.Name|AutomationProperties\.HelpText)=")[^"]*(?=")'
    '(?<=<TextBox\b[^>]*?\sTag=")[^"]*(?=")'
    '(?<=>)[^<>]+(?=<)'
)

function ConvertTo-XamlValue([string]$Value) {
    # $Value for a XAML attribute, escaped, and marked as a value the code put there: its first character as a
    # character reference (&#85;tilisateurs reads as Utilisateurs), which ConvertTo-LocalXaml leaves as it is. For
    # AD's data, and for text the code has put in this run's language already (Tr): a group named
    # « Utilisateurs », or a department « Service », stays as it is in English. What XML can't hold is left out (control
    # characters pasted from another tool, half of a surrogate pair), and {{ is written so Expand-Icon doesn't read it.
    # Line breaks are character references: an attribute's own would read as spaces. A value starting with { gets
    # XAML's escape, {} before it: XML decodes &#123; before XAML reads the attribute, which would take {Temporaire}
    # for a markup extension and fail to build the window (#227). So the value must be a whole attribute: the
    # escape only applies at its start, and anywhere else (after other text, or between tags) {} would show.
    $Value = $Value -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]', ''
    if (-not $Value) { return '' }
    $first = [char]::ConvertToUtf32($Value, 0)
    $rest = $Value.Substring($(if ($first -gt 0xFFFF) { 2 } else { 1 }))
    $(if ($first -eq 0x7B) { '{}' }) + "&#$first;" + [System.Security.SecurityElement]::Escape($rest).Replace('{{', '&#123;&#123;').Replace("`r", '&#13;').Replace("`n", '&#10;')
}

function Test-XamlValue([string]$Raw) {
    # Whether a XAML text, as it is written, was put there by ConvertTo-XamlValue (a character reference in it).
    $Raw -match '&#x?[0-9a-fA-F]+;'
}

function Get-XamlText([string]$Xaml) {
    # The texts of $Xaml that ConvertTo-LocalXaml translates, decoded (&amp; -> &), for the tests: those with a letter,
    # not a markup extension ({Binding …}), not a {{icon:…}} placeholder, and not a value (ConvertTo-XamlValue). Not
    # the comments' text.
    $Xaml = [regex]::Replace($Xaml, '(?s)<!--.*?-->', '')
    foreach ($pattern in $script:XamlTextPatterns) {
        foreach ($match in [regex]::Matches($Xaml, $pattern)) {
            if (Test-XamlValue $match.Value) { continue }
            $text = [System.Net.WebUtility]::HtmlDecode($match.Value).Trim()
            if ($text -match '\p{L}' -and $text -notmatch '^\{' -and $text -notmatch '\{\{icon:') { $text }
        }
    }
}

function ConvertTo-LocalXaml([string]$Xaml) {
    # $Xaml with its texts in this run's language (Get-XamlText says which): each one the table has, replaced, the
    # space around it kept; not the values the code put there (ConvertTo-XamlValue). In French, $Xaml as it is.
    $table = [System.AppDomain]::CurrentDomain.GetData('Repere.TextTable')
    if (-not $table) { return $Xaml }
    foreach ($pattern in $script:XamlTextPatterns) {
        $Xaml = [regex]::Replace($Xaml, $pattern, {
                param($match)
                $raw = $match.Value
                if (Test-XamlValue $raw) { return $raw }
                $text = [System.Net.WebUtility]::HtmlDecode($raw).Trim()
                if (-not $text -or -not $table.ContainsKey($text)) { return $raw }
                $lead = $raw.Substring(0, $raw.Length - $raw.TrimStart().Length)
                $trail = $raw.Substring($raw.TrimEnd().Length)
                $lead + [System.Security.SecurityElement]::Escape($table[$text]) + $trail
            })
    }
    $Xaml
}

# Tr, Get-TextCulture and Format-TextDate for a runspace that has none of the script's functions: dot-sourced there,
# as . ([scriptblock]::Create($LanguageScript)). The row builder starts with it.
$script:LanguageScript = @(
    foreach ($name in 'Tr', 'Get-TextCulture', 'Format-TextDate') { "function $name {$([Environment]::NewLine)$((Get-Item "function:$name").Definition)$([Environment]::NewLine)}" }
) -join [Environment]::NewLine
