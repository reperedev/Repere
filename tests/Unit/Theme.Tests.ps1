# The colors of a theme, without a window (Get-ThemeBrush): its quick accent made visible in each mode, the colors of
# one's own used as they're set (a mode's accent too, for a theme saved by the editor since 0.13), and those mixed from
# them following unless set; then a theme of one's own read back from apparence.json (Read-Appearance).

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')

    function New-TestTheme([string]$Accent = '#0B7A68', [hashtable]$Light = @{}, [hashtable]$Dark = @{}, [switch]$Exact) {
        # A theme of one's own as apparence.json holds it once read: its quick accent, its colors per mode.
        $theme = @{ Id = 'c1'; Name = 'Test'; Accent = $Accent; Tint = 'Neutre' }
        $colors = @{}
        if ($Light.Count) { $colors.Light = $Light }
        if ($Dark.Count) { $colors.Dark = $Dark }
        if ($colors.Count) { $theme.Colors = $colors }
        if ($Exact) { $theme.Exact = $true }
        $theme
    }
}

Describe 'Get-ThemeBrush: the quick accent and the colors of one''s own' {
    It 'Makes the quick accent visible in each mode, as before' {
        # #FFE600, pale yellow: about 1.3:1 on the light theme's lists.
        $theme = New-TestTheme '#FFE600' -Exact
        $light = (Get-ThemeBrush 'Light' $theme)['R.Accent']
        $light | Should -BeExactly (Get-ThemeAccent '#FFE600' (Get-SchemePalette $theme 'Light') $false)
        Get-Contrast $light (Get-SchemePalette $theme 'Light').Surface | Should -BeGreaterOrEqual 3
    }

    It "Uses a mode's own accent as it's set, even one hard to see, and leaves the other mode to the quick accent" {
        $theme = New-TestTheme '#0B7A68' -Light @{ Accent = '#FFE600' } -Exact
        (Get-ThemeBrush 'Light' $theme)['R.Accent'] | Should -BeExactly '#FFE600'
        (Get-ThemeBrush 'Dark' $theme)['R.Accent'] | Should -BeExactly (Get-ThemeAccent '#0B7A68' (Get-SchemePalette $theme 'Dark') $true)
    }

    It "Still makes a mode's own accent visible for a theme saved before 0.13, so it looks as it did" {
        $theme = New-TestTheme -Light @{ Accent = '#FFE600' }
        (Get-ThemeBrush 'Light' $theme)['R.Accent'] | Should -BeExactly (Get-ThemeAccent '#FFE600' (Get-SchemePalette $theme 'Light') $false)
    }

    It "Keeps a preset's accents as they were: each mode's, made visible" {
        foreach ($variant in 'Light', 'Dark') {
            $preset = $script:Presets.Lagon
            $expected = Get-ThemeAccent $preset.Accents[$variant] (Get-SchemePalette $preset $variant) ($variant -eq 'Dark')
            (Get-ThemeBrush $variant $preset)['R.Accent'] | Should -BeExactly $expected
        }
    }

    It 'Uses every color set as it is, the shades mixed from the accent included' {
        $set = @{ Accent = '#FFE600'; OnAccent = '#FFFFFF'; AccentHover = '#112233'; AccentPressed = '#223344'; AccentText = '#FFE600'
                  Selection = '#334455'; SelectionHover = '#445566'; Chrome = '#556677'; ControlHover = '#667788'; WarnText = '#778899' }
        $c = Get-ThemeBrush 'Light' (New-TestTheme -Light $set -Exact)
        foreach ($key in $set.Keys) { $c["R.$key"] | Should -BeExactly $set[$key] -Because $key }
    }

    It 'Mixes a shade again from a color set, unless the shade is set too' {
        $mixed = Get-ThemeBrush 'Dark' (New-TestTheme -Dark @{ Bg = '#000000'; Surface = '#202020' } -Exact)
        $mixed['R.Chrome'] | Should -BeExactly (Merge-Color '#000000' '#202020' 0.5)
        $kept = Get-ThemeBrush 'Dark' (New-TestTheme -Dark @{ Bg = '#000000'; Surface = '#202020'; Chrome = '#ABCDEF' } -Exact)
        $kept['R.Chrome'] | Should -BeExactly '#ABCDEF'
    }

    It 'Has a box in the editor for every color it draws with' {
        $drawn = @((Get-ThemeBrush 'Light' $script:Presets.Repere).Keys | ForEach-Object { $_.Substring(2) } | Sort-Object)
        @($script:ThemeColors.Keys | Sort-Object) | Should -Be $drawn
        @($script:ThemeColorGroups.Values | ForEach-Object { $_ } | Sort-Object) | Should -Be $drawn
    }
}

Describe 'Get-ThemeAdvice: what the editor says under the accent and about contrast' {
    BeforeAll {
        function Get-TestAdvice($Theme) {
            Get-ThemeAdvice $Theme @{ Light = Get-ThemeBrush 'Light' $Theme; Dark = Get-ThemeBrush 'Dark' $Theme }
        }
    }

    It 'Warns of nothing for a theme left to its automatic colors, whatever its accent and background' {
        $warned = foreach ($tint in 'Neutre', 'Teinté', 'Intense') {
            foreach ($hue in 0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330) {
                foreach ($lightness in 25, 50, 75) {
                    $theme = New-TestTheme (ConvertFrom-Hsl $hue 85 $lightness) -Exact
                    $theme.Tint = $tint
                    (Get-TestAdvice $theme).Warnings | ForEach-Object { "$tint $($theme.Accent): $_" }
                }
            }
        }
        $warned | Should -BeNullOrEmpty
    }

    It 'Says nothing of an accent shown as typed in both modes, and how it was adjusted in a mode where it was not' {
        (Get-TestAdvice (New-TestTheme '#6A48F2' -Exact)).Notes | Should -BeNullOrEmpty
        $theme = New-TestTheme '#1C50BE' -Exact
        $dark = (Get-ThemeBrush 'Dark' $theme)['R.Accent']
        $dark | Should -Not -Be '#1C50BE'
        (Get-TestAdvice $theme).Notes | Should -Be @("Sombre : éclairci en $dark pour rester visible.")
        $light = (Get-ThemeBrush 'Light' (New-TestTheme '#FFE600' -Exact))['R.Accent']
        (Get-TestAdvice (New-TestTheme '#FFE600' -Exact)).Notes | Should -Be @("Clair : assombri en $light pour rester visible.")
    }

    It "Names a mode's own accent, and warns when it barely stands out from the background" {
        $advice = Get-TestAdvice (New-TestTheme '#1C50BE' -Dark @{ Accent = '#2a3f80' } -Exact)
        $advice.Notes | Should -Be @('Sombre : son propre accent, #2A3F80, défini dans les couleurs personnalisées. Une couleur choisie ici le remplace.')
        $advice.Warnings.Count | Should -Be 1
        $advice.Warnings[0] | Should -BeLike 'Sombre : l''accent ressort peu (1,?:1, 3:1 conseillé) ; la sélection et le focus se verront mal.'
    }

    It 'Warns of the text that reads worst, and of the text on the accent, in its mode' {
        $advice = Get-TestAdvice (New-TestTheme -Dark @{ Text = '#444444'; OnAccent = '#0B7A68' } -Exact)
        $advice.Warnings.Count | Should -Be 2
        $advice.Warnings[0] | Should -BeLike 'Sombre : « Texte » se lit mal sur « * » (*:1, 4,5:1 conseillé).'
        $advice.Warnings[1] | Should -BeLike 'Sombre : le texte des boutons d''accent se lit mal (*:1, 4,5:1 conseillé).'
    }
}

Describe 'Read-Appearance: the themes of one''s own' {
    BeforeEach {
        $script:Appearance.CustomThemes.Clear()
        $script:SavedPath = $script:AppearancePath
        $script:AppearancePath = Join-Path $TestDrive 'apparence.json'
    }
    AfterEach {
        $script:AppearancePath = $script:SavedPath
        $script:Appearance.CustomThemes.Clear()
        $script:Appearance.Scheme = 'Repere'
    }

    It 'Opens a theme saved by 0.12.0 as it was: its dark accent kept and made visible' {
        Set-Content -LiteralPath $script:AppearancePath -Encoding utf8 -Value '{"Theme":"Clair","Scheme":"c1","CustomThemes":[{"Id":"c1","Name":"Lagon (copie)","Accent":"#0B7A68","Tint":"Teinté","Colors":{"Dark":{"Accent":"#3DC4A9","Bg":"#0E1A18","Nope":"#000000"}}}]}'
        Read-Appearance
        $theme = $script:Appearance.CustomThemes[0]
        $theme.Contains('Exact') | Should -BeFalse
        $theme.Colors.Dark.Accent | Should -BeExactly '#3DC4A9'
        $theme.Colors.Dark.Contains('Nope') | Should -BeFalse
        (Get-ThemeBrush 'Dark' $theme)['R.Accent'] | Should -BeExactly (Get-ThemeAccent '#3DC4A9' (Get-SchemePalette $theme 'Dark') $true)
    }

    It 'Reads a theme saved by the editor back with its colors, as typed' {
        Set-Content -LiteralPath $script:AppearancePath -Encoding utf8 -Value '{"Scheme":"c1","CustomThemes":[{"Id":"c1","Name":"Soleil","Accent":"#0B7A68","Tint":"Intense","Exact":true,"Colors":{"Light":{"Accent":"#FFE600","Chrome":"#FFF8C0"}}}]}'
        Read-Appearance
        $theme = $script:Appearance.CustomThemes[0]
        $theme.Exact | Should -BeTrue
        $c = Get-ThemeBrush 'Light' $theme
        $c['R.Accent'] | Should -BeExactly '#FFE600'
        $c['R.Chrome'] | Should -BeExactly '#FFF8C0'
    }
}
