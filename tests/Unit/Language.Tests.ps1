# Repère in English (Language.ps1, Language.en.psd1): the table loads, Tr and ConvertTo-LocalXaml translate, and every
# text the windows show has its English (Find-UntranslatedText, StaticAnalysis.ps1). French stays the language of the
# other tests: nothing here leaves the table in the process.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    # Repère's own files: the main script and what it dot-sources.
    $script:ShownFiles = @(@($script:RepereMainScript) + @(Get-RepereDotSourcedPath -Recurse) | ForEach-Object { @{ Path = $_; Name = Split-Path $_ -Leaf } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    . (Join-Path $PSScriptRoot 'StaticAnalysis.ps1')
    # Language.ps1 reads and saves its choice through Settings.ps1.
    . (Join-Path $script:RepereSource 'Settings.ps1')
    . (Join-Path $script:RepereSource 'Language.ps1')
    $script:Table = Read-TextTable (Join-Path $script:RepereSource 'Language.en.psd1')

    # French text left in French on purpose, each a « File.ps1|text », with why.
    $script:FrenchKept = @(
        # Language.en.psd1's own mistakes, for whoever edits it, before any language is loaded.
        "Language.ps1|`$Path : chaque entrée est @('français', 'English'), pas : `$(`$pair -join ' | ')"
        'Language.ps1|$Path : « $($pair[0]) » y est deux fois.'
        # Exit-Repere's title and the startup trap's text when Settings.ps1 or Language.ps1 itself didn't load: no Tr
        # yet. Through Tr otherwise.
        'Repere - Recherche PC AD par description.ps1|Repère'
        "Repere - Recherche PC AD par description.ps1|Repère n'a pas pu démarrer : {0}"
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Accès refusé'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Droits insuffisants pour cette opération'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Le serveur ne répond pas : il n''existe pas, il est arrêté ou les services Web Active Directory n''y fonctionnent pas'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Aucun contrôleur de domaine avec les services Web Active Directory trouvé'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Le serveur ne répond pas'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Opération non effectuée : utilisateur non authentifié'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Mot de passe refusé par la stratégie du domaine (longueur, complexité ou historique)'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Objet « ${identity} » introuvable dans « ${base} »'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Objet introuvable dans l''annuaire : « ${object} »'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Nom d''objet mal formé'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Un objet de ce nom existe déjà à cet endroit'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Déjà membre du groupe'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Opération possible seulement sur un objet sans objets enfants'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Contrainte de l''annuaire non respectée'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Trop de résultats : limite de la requête dépassée'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Opération possible seulement sur un objet lu par son chemin (recherche de base)'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Délai d''attente dépassé'
        # French of an AD error message: used only when Repère is in French; in English the message stays as AD says it
        'Errors.ps1|Chemin réseau introuvable'
        # a recent search's name prefix and an ellipsis: no words, the same in English
        'ComputerPage.ps1|$($Entry.Prefix)…'
        # A search type's id, saved in recherche.json like the others (Description contient…): shown through its Tr text.
        'ComputerPage.ps1|ID de clé BitLocker'
        # the En ligne cell while it checks: also the value Update-OnlineCheck compares ($row.Online -eq '…')
        'ComputerActions.ps1|…'
        # a pattern matched on Windows' error text (WinRM / Invoke-GPUpdate), in Windows' language: data
        'ComputerActions.ps1|Accès refusé|Access is denied|0x80070005'
        # the French placeholder in the restart message (redemarrage.json, the user's text): still replaced in English,
        # as is {delay}
        'RestartDialog.ps1|{délai}'
        # a pattern matched on quser's output, in Windows' language: data
        'ShadowSession.ps1|0x00000005|Access is denied|Accès refusé'
        # a session state as quser says it (Disc, Déco), in Windows' language: data
        'ShadowSession.ps1|^(Disc|Déco)'
        # A group membership id (Get-ObjectGroup, GroupsDialog.ps1), compared and used to sort; shown through Tr
        # $group.Membership
        'UserDetails.ps1|Héritée'
        # A card id: the key of Get-UserDetailSection, $DetailSectionKeys and $DetailSectionIcons; Get-DetailCardXaml
        # shows it through Tr
        'UserDetails.ps1|Identité'
        # Membership key (with Directe, Principale): compared, counted and sorted on here and in UserDetails.ps1,
        # asserted by the tests; shown through Tr (MembershipText)
        'GroupsDialog.ps1|Héritée'
        # A tint id (Tints, a theme's Tint): saved in apparence.json; the editor's toggle shows its own XAML text
        'Theme.ps1|Teinté'
        # The Repère preset's name: the app's name, the same in English
        'Theme.ps1|Repère'
        # A mode id (Appearance.Theme, with Clair and Sombre): saved in apparence.json, never shown
        'Theme.ps1|Système'
        # A key of TextScales, never shown (the toggle shows its own XAML text; the scale is what is saved)
        'Theme.ps1|Très grande'
        # A density id (Densities, Appearance.Density): saved in apparence.json; the toggle shows its own XAML text
        'Theme.ps1|Aérée'
        # A value's placeholder while it's read, compared to find the values not read when the reading is canceled; not
        # a word
        'SpecsWindow.ps1|…'
        # A regex on the edition name Windows gives (Win32_OperatingSystem.Caption), English or French: data
        'PCSpecs.ps1|Enterprise|Education|Entreprise|Éducation'
    )
}

AfterAll { [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $null) }

Describe 'Language.en.psd1' {
    It 'Loads: pairs, each French text once' {
        $script:Table.Count | Should -BeGreaterThan 0
    }

    It 'Refuses a French text twice, or an entry that is not a pair' -ForEach @(
        @{ Case = 'twice'; Content = "@{ Text = @(@('Copier', 'Copy'), @('Copier', 'Copy it')) }"; Expected = '*deux fois*' }
        @{ Case = 'not a pair'; Content = "@{ Text = @(@('Copier', 'Copy'), @('Coller')) }"; Expected = '*chaque entrée*' }
    ) {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) "repere-language-$Case.psd1"
        Set-Content -LiteralPath $path -Value $Content -Encoding utf8
        try { { Read-TextTable $path } | Should -Throw -ExpectedMessage $Expected }
        finally { Remove-Item -LiteralPath $path }
    }
}

Describe 'Tr and ConvertTo-LocalXaml' {
    BeforeAll {
        $sample = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        $sample['Copier'] = 'Copy'
        $sample['Supprimer…'] = 'Delete…'
        $sample['Mot de passe & clés'] = 'Password & keys'
        $sample['Rechercher un nom'] = 'Search for a name'
    }
    AfterEach { [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $null) }

    It 'In French, gives the text as it is' {
        Tr 'Copier' | Should -BeExactly 'Copier'
        ConvertTo-LocalXaml '<TextBlock Text="Copier"/>' | Should -BeExactly '<TextBlock Text="Copier"/>'
        (Get-TextCulture).Name | Should -Be 'fr-CA'
    }

    It 'In English, translates; a text with no entry stays as it is, case counting' {
        [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $sample)
        Tr 'Copier' | Should -BeExactly 'Copy'
        Tr 'copier' | Should -BeExactly 'copier'
        Tr 'Coller' | Should -BeExactly 'Coller'
        (Get-TextCulture).Name | Should -Be 'en-US'
    }

    It 'Translates the XAML text: attributes, a text box placeholder, text between tags, escaped' {
        [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $sample)
        $xaml = '<StackPanel><Button Content="Copier" ToolTip="Supprimer…"/><TextBox Tag="Rechercher un nom"/><Border Tag="Copier"/>' +
            '<TextBlock> Mot de passe &amp; clés </TextBlock><TextBlock Text="{Binding Copier}"/></StackPanel>'
        ConvertTo-LocalXaml $xaml | Should -BeExactly ('<StackPanel><Button Content="Copy" ToolTip="Delete…"/><TextBox Tag="Search for a name"/><Border Tag="Copier"/>' +
            '<TextBlock> Password &amp; keys </TextBlock><TextBlock Text="{Binding Copier}"/></StackPanel>')
    }

    It 'Leaves the values the code put in the XAML as they are (ConvertTo-XamlValue): AD data that reads like a text' {
        [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $sample)
        $value = ConvertTo-XamlValue 'Copier'
        $value | Should -BeExactly '&#67;opier'
        ConvertTo-LocalXaml "<TextBlock Text=`"$value`"/><Run>$value</Run>" | Should -BeExactly "<TextBlock Text=`"$value`"/><Run>$value</Run>"
        ([System.Windows.Markup.XamlReader]::Parse("<TextBlock xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" Text=`"$value`"/>")).Text | Should -BeExactly 'Copier'
        ConvertTo-XamlValue '<Tom & "Jerry">' | Should -BeExactly '&#60;Tom &amp; &quot;Jerry&quot;&gt;'
        ConvertTo-XamlValue '' | Should -BeExactly ''
        # Line breaks kept: an attribute's own newline reads as a space.
        ConvertTo-XamlValue "a`r`nb" | Should -BeExactly '&#97;&#13;&#10;b'
        ([xml]"<a b=`"$(ConvertTo-XamlValue "x`ny")`"/>").a.b | Should -BeExactly "x`ny"
        @(Get-XamlText "<TextBlock Text=`"$value`"/>").Count | Should -Be 0
        # Still a value behind XAML's {} escape (#227).
        $brace = ConvertTo-XamlValue '{Copier}'
        ConvertTo-LocalXaml "<TextBlock Text=`"$brace`"/>" | Should -BeExactly "<TextBlock Text=`"$brace`"/>"
        @(Get-XamlText "<TextBlock Text=`"$brace`"/>").Count | Should -Be 0
    }

    It 'Get-XamlText: the texts to translate, not comments, bindings or icons' {
        $xaml = '<Grid><!-- a -> b --><TextBlock Text="{Binding Name}"/><Button Content="Copier">{{icon:copy}}</Button><Run>Mot de passe &amp; clés</Run></Grid>'
        @(Get-XamlText $xaml) | Should -Be @('Copier', 'Mot de passe & clés')
    }
}

Describe 'Initialize-Language: the language of a run' {
    BeforeEach {
        # A settings folder of the test's own, never the user's.
        $script:SavedAppData = $env:APPDATA
        $env:APPDATA = Join-Path ([System.IO.Path]::GetTempPath()) "repere-language-appdata-$PID"
        Remove-Item -LiteralPath $env:APPDATA -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA 'Repere')
        $script:LanguageSettingPath = Join-Path $env:APPDATA 'Repere\parametres.json'
        function Read-SavedFile { Get-Content -LiteralPath $script:LanguageSettingPath -Raw | ConvertFrom-Json }
    }
    AfterEach {
        [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $null)
        Remove-Item -LiteralPath $env:APPDATA -Recurse -Force -ErrorAction SilentlyContinue
        $env:APPDATA = $script:SavedAppData
        $script:LanguageSettingPath = Join-Path $env:APPDATA 'Repere\parametres.json'
    }

    It 'Someone who used an earlier Repère keeps French at its first run, saved with their other settings' {
        '{"MoveRoots":["OU=Postes,DC=demo,DC=local"]}' | Set-Content -LiteralPath $script:LanguageSettingPath -Encoding utf8
        Initialize-Language ''
        $script:LanguageChoice | Should -BeExactly 'fr'
        $script:UILanguage | Should -BeExactly 'fr'
        (Read-SavedFile).Language | Should -BeExactly 'fr'
        @((Read-SavedFile).MoveRoots) | Should -Be @('OU=Postes,DC=demo,DC=local')
    }

    It "A new install follows Windows's language, and says so in parametres.json for the next runs" {
        Initialize-Language ''
        $script:LanguageChoice | Should -BeExactly ''
        $script:UILanguage | Should -BeExactly (Resolve-Language '')
        (Read-SavedFile).Language | Should -BeExactly ''
        # The settings this run writes don't make the next one take it for an earlier version's.
        '{"Theme":"Sombre"}' | Set-Content -LiteralPath (Join-Path $env:APPDATA 'Repere\apparence.json') -Encoding utf8
        Initialize-Language ''
        $script:LanguageChoice | Should -BeExactly ''
    }

    It 'A parametres.json that can''t be read is no first run: left as it is, not written over with the language' {
        # An admin's typo: a DN with a single \ before its comma.
        $broken = '{ "MoveRoots": ["OU=Postes\,DC=demo,DC=local"], "SccmSite": "DEM", "Language": "en" }'
        $broken | Set-Content -LiteralPath $script:LanguageSettingPath -Encoding utf8
        Initialize-Language '' 6>$null
        (Get-Content -LiteralPath $script:LanguageSettingPath -Raw).Trim() | Should -BeExactly $broken
        Test-Path -LiteralPath "$script:LanguageSettingPath.illisible" | Should -BeFalse
        # Someone who used Repère before: French, as at any first run, until the file is corrected.
        $script:LanguageChoice | Should -BeExactly 'fr'
    }

    It '-Language wins over the choice saved, for this run only' {
        '{"Language":"fr"}' | Set-Content -LiteralPath $script:LanguageSettingPath -Encoding utf8
        Initialize-Language 'en'
        $script:UILanguage | Should -BeExactly 'en'
        Tr 'Copier' | Should -BeExactly 'Copy'
        (Read-SavedFile).Language | Should -BeExactly 'fr'
    }

    It 'Without a usable Language.en.psd1, stays in French rather than not starting' {
        $folder = Join-Path ([System.IO.Path]::GetTempPath()) "repere-language-broken-$PID"
        $null = New-Item -ItemType Directory -Force -Path $folder
        Copy-Item -LiteralPath (Join-Path $script:RepereSource 'Language.ps1') -Destination $folder
        Set-Content -LiteralPath (Join-Path $folder 'Language.en.psd1') -Value "@{ Text = @(@('Copier', 'Copy') " -Encoding utf8
        try {
            . (Join-Path $folder 'Language.ps1')
            Initialize-Language 'en' 6>$null
            $script:UILanguage | Should -BeExactly 'fr'
            Tr 'Copier' | Should -BeExactly 'Copier'
        }
        finally { Remove-Item -LiteralPath $folder -Recurse -Force }
    }
}

Describe 'Every text shown has its English' {
    It '<Name>' -ForEach $script:ShownFiles {
        Find-UntranslatedText (Get-ParsedScript $Path) $script:Table $script:FrenchKept | Should -BeNullOrEmpty
    }
}
