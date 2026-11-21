# Repère's look: the palettes, the themes (presets and the user's own), the icons, the shared styles and Paramètres'
# Apparence section (mode and theme, saved in %APPDATA%\Repere\apparence.json). Dot-sourced by the main script.
#
# A theme has an accent color and a light and a dark palette. Each preset has its own hand-tuned palettes and an accent
# for each of them; a theme of one's own starts from the neutral LightGrey and DarkGrey palettes, tinted toward its
# accent (Tint: Neutre, Teinté or Intense, see Get-SchemePalette).
#
# WPF's Fluent theme (Application.ThemeMode) draws the controls left as they are: combo boxes, menus, scroll bars and
# tooltips. Its styles read its own colors directly, so they can't be recolored: the controls that show the palette or
# the accent (buttons, toggles, text boxes, list items, the grid) get Repère's own styles instead, from the
# application's resources, which win over Fluent's and also reach the dialogs and menus.

# DarkGrey and LightGrey: neutral, for the themes of one's own. Then each preset's dark and light palettes (<Key>Dark,
# <Key>Light). Every text color is at least 4.5:1 on Surface, Bg, Control and a selected row, and the status colors on
# their own backgrounds too (Faint, for placeholders and hints, is 3:1 or more). Hover, press, BorderStrong and RowHover
# are mixed from the others the way the neutral palettes' are.
$script:Palettes = @{
    DarkGrey = [ordered]@{
        Bg = '#121212'; Chrome = '#181818'; Surface = '#1E1E1E'; Input = '#161616'
        Control = '#2A2A2A'; ControlHover = '#333333'; ControlPressed = '#242424'
        Border = '#383838'; BorderStrong = '#4D4D4D'
        Text = '#EDEDED'; Muted = '#A6A6A6'; Faint = '#7A7A7A'; RowHover = '#262626'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    LightGrey = [ordered]@{
        Bg = '#F4F4F5'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#F2F2F3'; ControlPressed = '#E8E8EA'
        Border = '#DADADD'; BorderStrong = '#C2C2C7'
        Text = '#222225'; Muted = '#66666D'; Faint = '#8E8E95'; RowHover = '#F5F5F6'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    RepereDark = [ordered]@{
        Bg = '#16121C'; Chrome = '#1D1824'; Surface = '#241E2C'; Input = '#1A1520'
        Control = '#2E2738'; ControlHover = '#362E42'; ControlPressed = '#292232'
        Border = '#3B3247'; BorderStrong = '#50485C'
        Text = '#EEEAF3'; Muted = '#A69BB3'; Faint = '#7D7289'; RowHover = '#2A2333'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    RepereLight = [ordered]@{
        Bg = '#F6F4FA'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#F2EFF6'; ControlPressed = '#EAE5F0'
        Border = '#DED7E8'; BorderStrong = '#C2BBCC'
        Text = '#241D2D'; Muted = '#685D76'; Faint = '#938A9F'; RowHover = '#F9F7FC'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    GraphiteDark = [ordered]@{
        Bg = '#111214'; Chrome = '#17181B'; Surface = '#1C1D20'; Input = '#141517'
        Control = '#26282C'; ControlHover = '#2D2F34'; ControlPressed = '#212226'
        Border = '#313338'; BorderStrong = '#47494E'
        Text = '#ECECEE'; Muted = '#A3A5AB'; Faint = '#7B7D84'; RowHover = '#222427'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    GraphiteLight = [ordered]@{
        Bg = '#F3F3F5'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#F0F0F2'; ControlPressed = '#E6E7EA'
        Border = '#D9DADE'; BorderStrong = '#BDBEC2'
        Text = '#1D1E21'; Muted = '#5F616A'; Faint = '#8C8E96'; RowHover = '#F7F7F8'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    MarineDark = [ordered]@{
        Bg = '#0D131E'; Chrome = '#121A27'; Surface = '#17202F'; Input = '#0F1622'
        Control = '#1F2A3D'; ControlHover = '#263247'; ControlPressed = '#1B2536'
        Border = '#29364D'; BorderStrong = '#404C61'
        Text = '#E6ECF5'; Muted = '#93A2BA'; Faint = '#6C7B93'; RowHover = '#1C2637'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    MarineLight = [ordered]@{
        Bg = '#F1F4F9'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#EDF1F6'; ControlPressed = '#E2E8F0'
        Border = '#D2DBE8'; BorderStrong = '#B6BFCC'
        Text = '#18202F'; Muted = '#56637A'; Faint = '#8592A6'; RowHover = '#F5F7FB'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    LagonDark = [ordered]@{
        Bg = '#0C1615'; Chrome = '#111D1C'; Surface = '#152321'; Input = '#0E1918'
        Control = '#1C2E2B'; ControlHover = '#223834'; ControlPressed = '#182826'
        Border = '#263D39'; BorderStrong = '#3D524E'
        Text = '#E2EFEC'; Muted = '#8FABA6'; Faint = '#678580'; RowHover = '#192A27'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    LagonLight = [ordered]@{
        Bg = '#F0F6F5'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#EBF3F1'; ControlPressed = '#DEEBE8'
        Border = '#CDE0DC'; BorderStrong = '#B1C5C1'
        Text = '#132D29'; Muted = '#52716C'; Faint = '#7F9A96'; RowHover = '#F4F9F8'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    MousseDark = [ordered]@{
        Bg = '#121510'; Chrome = '#181C15'; Surface = '#1D2219'; Input = '#141812'
        Control = '#262D21'; ControlHover = '#2E3528'; ControlPressed = '#22281D'
        Border = '#323A2B'; BorderStrong = '#484F41'
        Text = '#E8ECE2'; Muted = '#A0A895'; Faint = '#78806D'; RowHover = '#22291E'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    MousseLight = [ordered]@{
        Bg = '#F5F5EF'; Chrome = '#FFFFFD'; Surface = '#FFFFFD'; Input = '#FFFFFD'
        Control = '#FFFFFD'; ControlHover = '#F1F1EB'; ControlPressed = '#E8E9DF'
        Border = '#DBDDCF'; BorderStrong = '#BFC2B4'
        Text = '#21261B'; Muted = '#5F6654'; Faint = '#8C9180'; RowHover = '#F8F8F3'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    TerracottaDark = [ordered]@{
        Bg = '#191311'; Chrome = '#201916'; Surface = '#261E1A'; Input = '#1B1512'
        Control = '#312621'; ControlHover = '#3A2E28'; ControlPressed = '#2C221E'
        Border = '#3F322B'; BorderStrong = '#544841'
        Text = '#F2E9E4'; Muted = '#B39F94'; Faint = '#8A766C'; RowHover = '#2D231E'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    TerracottaLight = [ordered]@{
        Bg = '#FAF5F2'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#F6F0EC'; ControlPressed = '#F1E6E0'
        Border = '#E9D9CF'; BorderStrong = '#CDBDB4'
        Text = '#2D201A'; Muted = '#725F56'; Faint = '#9E8B82'; RowHover = '#FCF8F6'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    FramboiseDark = [ordered]@{
        Bg = '#191115'; Chrome = '#20171C'; Surface = '#261C22'; Input = '#1B1318'
        Control = '#31242B'; ControlHover = '#3B2B33'; ControlPressed = '#2C2026'
        Border = '#402F38'; BorderStrong = '#55454E'
        Text = '#F3E7ED'; Muted = '#B598A6'; Faint = '#8B707D'; RowHover = '#2D2127'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    FramboiseLight = [ordered]@{
        Bg = '#FAF4F7'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#F7EEF2'; ControlPressed = '#F2E4EA'
        Border = '#EBD5DF'; BorderStrong = '#CEB9C3'
        Text = '#2D1B24'; Muted = '#745C68'; Faint = '#A08A95'; RowHover = '#FCF7F9'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    SableDark = [ordered]@{
        Bg = '#191612'; Chrome = '#201C17'; Surface = '#25211B'; Input = '#1B1814'
        Control = '#2F2A22'; ControlHover = '#373128'; ControlPressed = '#2A261E'
        Border = '#3C352B'; BorderStrong = '#514A40'
        Text = '#EFE8DC'; Muted = '#ADA190'; Faint = '#847969'; RowHover = '#2B261F'
        SuccessBg = '#17301F'; SuccessText = '#7ED9A8'; SuccessBorder = '#25543A'
        DangerBg = '#3D1E22'; DangerText = '#F59A9A'; DangerBorder = '#6A2E36'
        WarnBg = '#33280F'; WarnText = '#F2C46B'; WarnBorder = '#634B1C'
    }
    SableLight = [ordered]@{
        Bg = '#F7F3EC'; Chrome = '#FFFDF9'; Surface = '#FFFDF9'; Input = '#FFFDF9'
        Control = '#FFFDF9'; ControlHover = '#F3EEE5'; ControlPressed = '#ECE5D9'
        Border = '#E2D8C8'; BorderStrong = '#C6BDAE'
        Text = '#2A231A'; Muted = '#6C6051'; Faint = '#998D7D'; RowHover = '#F9F6F0'
        SuccessBg = '#E2F4EA'; SuccessText = '#1F6E43'; SuccessBorder = '#B8E0C9'
        DangerBg = '#FCE6E8'; DangerText = '#A3262E'; DangerBorder = '#F2BFC4'
        WarnBg = '#FFF1D6'; WarnText = '#9A5B00'; WarnBorder = '#F0D49A'
    }
    ContrasteDark = [ordered]@{
        Bg = '#000000'; Chrome = '#000000'; Surface = '#0A0A0A'; Input = '#000000'
        Control = '#141414'; ControlHover = '#616161'; ControlPressed = '#0F0F0F'
        Border = '#8A8A8A'; BorderStrong = '#FFFFFF'
        Text = '#FFFFFF'; Muted = '#D6D6D6'; Faint = '#B0B0B0'; RowHover = '#101010'
        SuccessBg = '#002B12'; SuccessText = '#7CFFB2'; SuccessBorder = '#7CFFB2'
        DangerBg = '#330000'; DangerText = '#FF8A8A'; DangerBorder = '#FF8A8A'
        WarnBg = '#332200'; WarnText = '#FFB347'; WarnBorder = '#FFB347'
    }
    ContrasteLight = [ordered]@{
        Bg = '#FFFFFF'; Chrome = '#FFFFFF'; Surface = '#FFFFFF'; Input = '#FFFFFF'
        Control = '#FFFFFF'; ControlHover = '#B7B7B7'; ControlPressed = '#898989'
        Border = '#4A4A4A'; BorderStrong = '#000000'
        Text = '#000000'; Muted = '#2E2E2E'; Faint = '#555555'; RowHover = '#FFFFFF'
        SuccessBg = '#FFFFFF'; SuccessText = '#0B5D2A'; SuccessBorder = '#0B5D2A'
        DangerBg = '#FFFFFF'; DangerText = '#A00000'; DangerBorder = '#A00000'
        WarnBg = '#FFFFFF'; WarnText = '#8A4B00'; WarnBorder = '#8A4B00'
    }
}

# How much of the accent goes into each color of the neutral palettes, for a « Teinté » background (Intense: 1.8 times
# as much, Neutre: none). Colors not listed (the white surfaces of the light theme, the status colors) stay as they are.
$script:TintAmounts = @{
    Dark  = @{ Bg = 0.07; Chrome = 0.07; Surface = 0.08; Input = 0.07; Control = 0.09; ControlHover = 0.1; ControlPressed = 0.08
               Border = 0.12; BorderStrong = 0.13; RowHover = 0.09; Text = 0.03; Muted = 0.08; Faint = 0.1 }
    Light = @{ Bg = 0.05; ControlHover = 0.05; ControlPressed = 0.08; Border = 0.12; BorderStrong = 0.14; RowHover = 0.04
               Text = 0.08; Muted = 0.12; Faint = 0.12 }
}
$script:Tints = [ordered]@{ Neutre = 0; 'Teinté' = 1; Intense = 1.8 }

# The presets, in the order shown. Accents: one per variant, each 3:1 or more against its background and 4.5:1 or more
# with the text on it (white, or dark on the lighter dark-theme accents). Accent, the light one, is the color a copy of
# the preset starts from in the editor.
$script:Presets = [ordered]@{
    Repere     = @{ Name = 'Repère'; Accent = '#6A48F2'; Tint = 'Teinté'; Accents = @{ Light = '#6A48F2'; Dark = '#7553FF' }; Palettes = @{ Light = 'RepereLight'; Dark = 'RepereDark' } }
    Graphite   = @{ Name = 'Graphite'; Accent = '#454E61'; Tint = 'Neutre'; Accents = @{ Light = '#454E61'; Dark = '#A9B4C8' }; Palettes = @{ Light = 'GraphiteLight'; Dark = 'GraphiteDark' } }
    Marine     = @{ Name = (Tr 'Marine'); Accent = '#1F5CCC'; Tint = 'Intense'; Accents = @{ Light = '#1F5CCC'; Dark = '#5E8EF2' }; Palettes = @{ Light = 'MarineLight'; Dark = 'MarineDark' } }
    Lagon      = @{ Name = (Tr 'Lagon'); Accent = '#0B7A68'; Tint = 'Teinté'; Accents = @{ Light = '#0B7A68'; Dark = '#3DC4A9' }; Palettes = @{ Light = 'LagonLight'; Dark = 'LagonDark' } }
    Mousse     = @{ Name = (Tr 'Mousse'); Accent = '#3D6A28'; Tint = 'Teinté'; Accents = @{ Light = '#3D6A28'; Dark = '#92C46E' }; Palettes = @{ Light = 'MousseLight'; Dark = 'MousseDark' } }
    Terracotta = @{ Name = 'Terracotta'; Accent = '#B4441C'; Tint = 'Teinté'; Accents = @{ Light = '#B4441C'; Dark = '#F28C5E' }; Palettes = @{ Light = 'TerracottaLight'; Dark = 'TerracottaDark' } }
    Framboise  = @{ Name = (Tr 'Framboise'); Accent = '#B01F5C'; Tint = 'Teinté'; Accents = @{ Light = '#B01F5C'; Dark = '#F26DA0' }; Palettes = @{ Light = 'FramboiseLight'; Dark = 'FramboiseDark' } }
    Sable      = @{ Name = (Tr 'Sable'); Accent = '#87561A'; Tint = 'Teinté'; Accents = @{ Light = '#87561A'; Dark = '#DDA65E' }; Palettes = @{ Light = 'SableLight'; Dark = 'SableDark' } }
    Contraste  = @{ Name = (Tr 'Contraste élevé'); Accent = '#0037A8'; Tint = 'Neutre'; Accents = @{ Light = '#0037A8'; Dark = '#FFD400' }; Palettes = @{ Light = 'ContrasteLight'; Dark = 'ContrasteDark' } }
}
# Presets that were renamed or removed, and the one a saved choice of them now opens on.
$script:RenamedPresets = @{ Ocean = 'Marine'; Foret = 'Mousse'; Braise = 'Terracotta'; Rose = 'Framboise'; Iris = 'Repere' }
# The colors a theme of one's own can set in each mode (its Colors.Light and Colors.Dark, by key): every color Repère
# draws with, and the editor's label for each (Accent's is the same in English), in the groups of its Couleurs table.
# One left out comes from the quick settings, the accent and the Fond, as in a theme that sets none; one set is used as
# it is, and those mixed from it follow unless they're set too (Set-ThemeColor, Get-ThemeBrush).
$script:ThemeColorGroups = [ordered]@{
    (Tr 'Fenêtre et listes')           = 'Bg', 'Chrome', 'Surface', 'RowHover', 'Selection', 'SelectionHover'
    (Tr 'Texte')                       = 'Text', 'Muted', 'Faint'
    (Tr 'Boutons, champs et bordures') = 'Control', 'ControlHover', 'ControlPressed', 'Input', 'Border', 'BorderStrong'
    'Accent'                           = 'Accent', 'AccentHover', 'AccentPressed', 'AccentText', 'OnAccent'
    (Tr 'États')                       = 'SuccessBg', 'SuccessText', 'SuccessBorder', 'WarnBg', 'WarnText', 'WarnBorder', 'DangerBg', 'DangerText', 'DangerBorder'
}
$script:ThemeColors = [ordered]@{
    Bg = (Tr 'Fond de la fenêtre'); Chrome = (Tr 'Barre de titre'); Surface = (Tr 'Listes et cartes'); RowHover = (Tr 'Ligne survolée')
    Selection = (Tr 'Ligne sélectionnée'); SelectionHover = (Tr 'Ligne sélectionnée survolée')
    Text = (Tr 'Texte'); Muted = (Tr 'Texte secondaire'); Faint = (Tr 'Texte discret')
    Control = (Tr 'Boutons'); ControlHover = (Tr 'Boutons survolés'); ControlPressed = (Tr 'Boutons enfoncés'); Input = (Tr 'Champs de saisie')
    Border = (Tr 'Bordures'); BorderStrong = (Tr 'Bordures marquées')
    Accent = 'Accent'; AccentHover = (Tr 'Accent survolé'); AccentPressed = (Tr 'Accent enfoncé'); AccentText = (Tr "Texte couleur d'accent"); OnAccent = (Tr "Texte sur l'accent")
    SuccessBg = (Tr 'Succès : fond'); SuccessText = (Tr 'Succès : texte'); SuccessBorder = (Tr 'Succès : bordure')
    WarnBg = (Tr 'Avertissement : fond'); WarnText = (Tr 'Avertissement : texte'); WarnBorder = (Tr 'Avertissement : bordure')
    DangerBg = (Tr 'Erreur : fond'); DangerText = (Tr 'Erreur : texte'); DangerBorder = (Tr 'Erreur : bordure')
}
# How many themes of their own a user can keep (two rows of the gallery).
$script:MaxCustomThemes = 8

# Outline icons on a 24-unit grid, drawn with a 2-unit round stroke in the text color around them.
$script:Icons = @{
    search = 'M4,11 A7,7 0 1 1 18,11 A7,7 0 1 1 4,11 Z M20,20 L16,16'
    monitor = 'M5,4 H19 A2,2 0 0 1 21,6 V14 A2,2 0 0 1 19,16 H5 A2,2 0 0 1 3,14 V6 A2,2 0 0 1 5,4 Z M8,20 H16 M12,16 V20'
    activity = 'M3,12 H7 L10,5 L14,19 L17,12 H21'
    ban = 'M3,12 A9,9 0 1 1 21,12 A9,9 0 1 1 3,12 Z M5.7,5.7 L18.3,18.3'
    checkcircle = 'M3,12 A9,9 0 1 1 21,12 A9,9 0 1 1 3,12 Z M8,12.5 L11,15.5 L16.5,9'
    check = 'M5,12.5 L10,17.5 L19,7.5'
    pencil = 'M4,20 H8 L19,9 A2.83,2.83 0 0 0 15,5 L4,16 Z M13.5,6.5 L17.5,10.5'
    lock = 'M6,11 H18 A2,2 0 0 1 20,13 V19 A2,2 0 0 1 18,21 H6 A2,2 0 0 1 4,19 V13 A2,2 0 0 1 6,11 Z M8,11 V7 A4,4 0 0 1 16,7 V11 M12,15 V17'
    key = 'M3,15.5 A4.5,4.5 0 1 1 12,15.5 A4.5,4.5 0 1 1 3,15.5 Z M10.7,12.3 L20,3 M15.5,7.5 L18.5,10.5 M18,5 L21,8'
    copy = 'M11,8 H18 A2,2 0 0 1 20,10 V18 A2,2 0 0 1 18,20 H11 A2,2 0 0 1 9,18 V10 A2,2 0 0 1 11,8 Z M15,8 V6 A2,2 0 0 0 13,4 H6 A2,2 0 0 0 4,6 V13 A2,2 0 0 0 6,15 H9'
    trash = 'M4,7 H20 M10,11 V17 M14,11 V17 M6,7 L7,19 A2,2 0 0 0 9,21 H15 A2,2 0 0 0 17,19 L18,7 M9,7 V4 A1,1 0 0 1 10,3 H14 A1,1 0 0 1 15,4 V7'
    chevron = 'M6,9 L12,15 L18,9'
    filter = 'M4,5 H20 L14,12.5 V19 L10,17 V12.5 Z'
    palette = 'M12,3 A9,9 0 1 0 12,21 A1.8,1.8 0 0 0 13.5,18.2 A1.8,1.8 0 0 1 15,15.5 H17 A4,4 0 0 0 21,11.5 C21,6.8 17,3 12,3 Z M7.5,11 L7.51,11 M10,7 L10.01,7 M15,7 L15.01,7'
    user = 'M8,7 A4,4 0 1 1 16,7 A4,4 0 1 1 8,7 Z M4,21 V20 A6,6 0 0 1 10,14 H14 A6,6 0 0 1 20,20 V21'
    userplus = 'M5,7 A4,4 0 1 1 13,7 A4,4 0 1 1 5,7 Z M2,21 V19 A4,4 0 0 1 6,15 H12 A4,4 0 0 1 16,19 V21 M19,8 V14 M22,11 H16'
    userminus = 'M5,7 A4,4 0 1 1 13,7 A4,4 0 1 1 5,7 Z M2,21 V19 A4,4 0 0 1 6,15 H12 A4,4 0 0 1 16,19 V21 M22,11 H16'
    folder = 'M3,7 A2,2 0 0 1 5,5 H9 L11,7 H19 A2,2 0 0 1 21,9 V17 A2,2 0 0 1 19,19 H5 A2,2 0 0 1 3,17 Z'
    sliders = 'M4,6 H13 M17,6 H20 M15,4 V8 M4,12 H7 M11,12 H20 M9,10 V14 M4,18 H11 M15,18 H20 M13,16 V20'
    sun = 'M8,12 A4,4 0 1 1 16,12 A4,4 0 1 1 8,12 Z M12,2.5 V4.5 M12,19.5 V21.5 M2.5,12 H4.5 M19.5,12 H21.5 M5.3,5.3 L6.7,6.7 M17.3,17.3 L18.7,18.7 M5.3,18.7 L6.7,17.3 M17.3,6.7 L18.7,5.3'
    moon = 'M20,14.5 A8.5,8.5 0 1 1 9.5,4 A6.5,6.5 0 0 0 20,14.5 Z'
    plus = 'M12,5 V19 M5,12 H19'
    back = 'M19,12 H5 M11,6 L5,12 L11,18'
    monitorcheck = 'M12,16 H4 A1,1 0 0 1 3,15 V5 A1,1 0 0 1 4,4 H20 A1,1 0 0 1 21,5 V12.5 M7,20 H11 M9,16 V20 M15,19 L17,21 L21,17'
    monitoroff = 'M8,4 H20 A1,1 0 0 1 21,5 V15 A1,1 0 0 1 20,16 M16,16 H4 A1,1 0 0 1 3,15 V5 A1,1 0 0 1 4,4 M7,20 H17 M9,16 V20 M15,16 V20 M3,3 L21,21'
    users ='M15,20 V18.5 A3.5,3.5 0 0 0 11.5,15 H5.5 A3.5,3.5 0 0 0 2,18.5 V20 M5,8 A3.5,3.5 0 1 1 12,8 A3.5,3.5 0 1 1 5,8 Z M17,15.3 A3.5,3.5 0 0 1 22,18.5 V20 M15.5,4.7 A3.5,3.5 0 0 1 15.5,11.3'
    power = 'M12,3 V12 M17.66,6.34 A8,8 0 1 1 6.34,6.34'
    terminal = 'M4,7 L9,12 L4,17 M12,18 H20'
    server = 'M5,4 H19 A1,1 0 0 1 20,5 V9 A1,1 0 0 1 19,10 H5 A1,1 0 0 1 4,9 V5 A1,1 0 0 1 5,4 Z M5,14 H19 A1,1 0 0 1 20,15 V19 A1,1 0 0 1 19,20 H5 A1,1 0 0 1 4,19 V15 A1,1 0 0 1 5,14 Z M8,7 H8.01 M8,17 H8.01'
    list = 'M9,6 H20 M9,12 H20 M9,18 H20 M4.5,6 H4.51 M4.5,12 H4.51 M4.5,18 H4.51'
    xcircle = 'M3,12 A9,9 0 1 1 21,12 A9,9 0 1 1 3,12 Z M15,9 L9,15 M9,9 L15,15'
    columns ='M5,4 H19 A1,1 0 0 1 20,5 V19 A1,1 0 0 1 19,20 H5 A1,1 0 0 1 4,19 V5 A1,1 0 0 1 5,4 Z M9.5,4 V20 M14.5,4 V20'
    move = 'M3,7 A2,2 0 0 1 5,5 H9 L11,7 H19 A2,2 0 0 1 21,9 V17 A2,2 0 0 1 19,19 H5 A2,2 0 0 1 3,17 Z M8.5,13 H15.5 M13,10.5 L15.5,13 L13,15.5'
    cpu = 'M7,5 H17 A2,2 0 0 1 19,7 V17 A2,2 0 0 1 17,19 H7 A2,2 0 0 1 5,17 V7 A2,2 0 0 1 7,5 Z M9,9 H15 V15 H9 Z M9,2 V5 M15,2 V5 M9,19 V22 M15,19 V22 M2,9 H5 M2,15 H5 M19,9 H22 M19,15 H22'
    refresh = 'M21,12 A9,9 0 1 1 18.36,5.64 L21,8 M21,3 V8 H16'
    download = 'M21,15 V19 A2,2 0 0 1 19,21 H5 A2,2 0 0 1 3,19 V15 M7,10 L12,15 L17,10 M12,15 V3'
    settings = 'M10.325,4.317 c.426,-1.756 2.924,-1.756 3.35,0 a1.724,1.724 0 0 0 2.573,1.066 c1.543,-.94 3.31,.826 2.37,2.37 a1.724,1.724 0 0 0 1.065,2.572 c1.756,.426 1.756,2.924 0,3.35 a1.724,1.724 0 0 0 -1.066,2.573 c.94,1.543 -.826,3.31 -2.37,2.37 a1.724,1.724 0 0 0 -2.572,1.065 c-.426,1.756 -2.924,1.756 -3.35,0 a1.724,1.724 0 0 0 -2.573,-1.066 c-1.543,.94 -3.31,-.826 -2.37,-2.37 a1.724,1.724 0 0 0 -1.065,-2.572 c-1.756,-.426 -1.756,-2.924 0,-3.35 a1.724,1.724 0 0 0 1.066,-2.573 c-.94,-1.543 .826,-3.31 2.37,-2.37 c1,.608 2.296,.07 2.572,-1.065 Z M9,12 A3,3 0 1 0 15,12 A3,3 0 1 0 9,12 Z'
    keyboard = 'M4,6 H20 A2,2 0 0 1 22,8 V16 A2,2 0 0 1 20,18 H4 A2,2 0 0 1 2,16 V8 A2,2 0 0 1 4,6 Z M6,10 H6.01 M10,10 H10.01 M14,10 H14.01 M18,10 H18.01 M6,14 H6.01 M18,14 H18.01 M10,14 H14'
    history = 'M12,8 V12 L14,14 M3.05,11 A9,9 0 1 1 3.55,15 M3.05,20 V15 H8.05'
    screenshare = 'M21,12 V15 A1,1 0 0 1 20,16 H4 A1,1 0 0 1 3,15 V5 A1,1 0 0 1 4,4 H13 M7,20 H17 M9,16 V20 M15,16 V20 M17,4 H21 V8 M16,9 L21,4'
    harddrive = 'M22,12 H2 M5.45,5.11 L2,12 V18 A2,2 0 0 0 4,20 H20 A2,2 0 0 0 22,18 V12 L18.55,5.11 A2,2 0 0 0 16.76,4 H7.24 A2,2 0 0 0 5.45,5.11 Z M6,16 H6.01 M10,16 H10.01'
    drivelock = 'M10,15 H4 A2,2 0 0 1 2,13 V6 A2,2 0 0 1 4,4 H20 A2,2 0 0 1 22,6 V8 M6,9.5 H6.01 M13,15 H21 A1,1 0 0 1 22,16 V21 A1,1 0 0 1 21,22 H13 A1,1 0 0 1 12,21 V16 A1,1 0 0 1 13,15 Z M14.5,15 V13 A2.5,2.5 0 0 1 19.5,13 V15'
    info = 'M3,12 A9,9 0 1 1 21,12 A9,9 0 1 1 3,12 Z M12,16 V12 M12,8 H12.01'
    x = 'M18,6 L6,18 M6,6 L18,18'
    warning = 'M10.27,4 L2.27,18 A2,2 0 0 0 4,21 H20 A2,2 0 0 0 21.73,18 L13.73,4 A2,2 0 0 0 10.27,4 Z M12,9 V13 M12,17 H12.01'
    calendar = 'M8,2 V6 M16,2 V6 M3,10 H21 M5,4 H19 A2,2 0 0 1 21,6 V20 A2,2 0 0 1 19,22 H5 A2,2 0 0 1 3,20 V6 A2,2 0 0 1 5,4 Z'
    unlock = 'M5,11 H19 A2,2 0 0 1 21,13 V20 A2,2 0 0 1 19,22 H5 A2,2 0 0 1 3,20 V13 A2,2 0 0 1 5,11 Z M7,11 V7 A5,5 0 0 1 16.9,6'
    password = 'M4,7 H20 A2,2 0 0 1 22,9 V15 A2,2 0 0 1 20,17 H4 A2,2 0 0 1 2,15 V9 A2,2 0 0 1 4,7 Z M12,12 H12.01 M17,12 H17.01 M7,12 H7.01'
    eye = 'M2,12 C4.5,7 8,5 12,5 C16,5 19.5,7 22,12 C19.5,17 16,19 12,19 C8,19 4.5,17 2,12 Z M9,12 A3,3 0 1 0 15,12 A3,3 0 1 0 9,12 Z'
    eyeoff = 'M2,12 C4.5,7 8,5 12,5 C16,5 19.5,7 22,12 C19.5,17 16,19 12,19 C8,19 4.5,17 2,12 Z M9,12 A3,3 0 1 0 15,12 A3,3 0 1 0 9,12 Z M3,3 L21,21'
    open = 'M14,4 H20 V10 M20,4 L11,13 M18,14 V19 A1,1 0 0 1 17,20 H5 A1,1 0 0 1 4,19 V7 A1,1 0 0 1 5,6 H10'
}

$script:AppearancePath = Get-SettingPath 'apparence.json'
# Theme: the mode (Système, Clair or Sombre). Scheme: the theme's key, a preset's or one of CustomThemes' Id (c1, c2…).
# CustomThemes: the user's own, each an Id, a Name, an Accent (#RRGGBB) and a Tint. Columns: the results grid's columns
# as the user left them (each a Key, Visible, Width, Unit and Index), $null until they're changed; ComputerPage.ps1
# checks them. UserColumns and GroupColumns: the same for the Utilisateurs and Groupes pages (UserPage.ps1, GroupPage.ps1).
# FoldedSections: the cards folded in a user's or a group's Propriétés (UserDetails.ps1), by key. HiddenColumnFilters:
# the pages (Computers, Users, Groups) whose Filtres button is off (ColumnFilter.ps1). Density: one of Densities' names.
$script:Appearance = @{ Theme = 'Système'; Scheme = 'Repere'; CustomThemes = [System.Collections.Generic.List[object]]::new(); Columns = $null
                        UserColumns = $null; GroupColumns = $null; FoldedSections = @(); HiddenColumnFilters = @()
                        FontFamily = 'Segoe UI'; TextScale = 1.0; FontWeight = 'SemiBold'; Density = 'Normale' }
# The weights offered: Normale (ordinary text semi-bold, Windows' regular weight being thin on screen) and Grasse.
# Names and labels (Strong) and titles (Title) go one step further, so they keep standing out.
$script:FontWeights = [ordered]@{
    SemiBold = @{ Label = 'Normale'; Text = 'SemiBold'; Strong = 'Bold'; Title = 'Bold' }
    Bold     = @{ Label = 'Grasse'; Text = 'Bold'; Strong = 'Black'; Title = 'Black' }
}
# The fonts offered (Paramètres › Apparence), each its name and its family: Windows' own, then those shipped in fonts\
# (OFL licences beside them), loaded from there so that nothing has to be installed. A font this computer doesn't have
# (Segoe UI Variable before Windows 11, a font removed from fonts\) isn't offered.
$script:FontChoices = [ordered]@{
    'Segoe UI' = 'Segoe UI'; 'Segoe UI Variable' = 'Segoe UI Variable Text'; Calibri = 'Calibri'; Verdana = 'Verdana'
    Tahoma = 'Tahoma'; Bahnschrift = 'Bahnschrift'; Consolas = 'Consolas'; 'Atkinson Hyperlegible Next' = 'Atkinson Hyperlegible Next'
    Inter = 'Inter'; 'JetBrains Mono' = 'JetBrains Mono'; 'Cascadia Mono' = 'Cascadia Mono'
}
$script:FontFolder = Join-Path $PSScriptRoot 'fonts'
$script:FontFamilies = $null
# The text sizes offered (Paramètres › Apparence), as a scale of every window's content: its text, icons and spacing.
$script:TextScales = [ordered]@{ Normale = 1.0; Grande = 1.15; 'Très grande' = 1.3 }
# The densities offered (Paramètres › Apparence): the height of the grids' rows (Row) and headers (Header), of the
# search row's fields and buttons (Bar) and of the other buttons and fields (Control), the vertical padding of buttons
# (Button) and list items (Item), and the gaps above the action bar, the search row and the results' bar (Gaps) and
# around the status line (Status). Widths stay as they are, so the action bar's labels fit as before; the text keeps its
# size (TextScales). Each one's Id names its toggle (density_<Id>), and its Note says what it does, under its name.
$script:Densities = [ordered]@{
    Compacte = @{ Id = 'compact'; Note = (Tr 'Lignes de 32 px'); Row = 32; Header = 32; Bar = 32; Control = 30; Button = 3; Item = 4; Gaps = 10, 8, 12, 6; Status = 5 }
    Normale  = @{ Id = 'normal'; Note = (Tr 'Lignes de 40 px'); Row = 40; Header = 38; Bar = 38; Control = 34; Button = 6; Item = 7; Gaps = 14, 12, 16, 8; Status = 8 }
    'Aérée'  = @{ Id = 'airy'; Note = (Tr 'Lignes de 48 px'); Row = 48; Header = 44; Bar = 44; Control = 40; Button = 9; Item = 10; Gaps = 18, 16, 20, 10; Status = 11 }
}
# The languages offered (Paramètres › Apparence), each by its own name, in every language, then the choice saved in
# parametres.json (Language.ps1), '' for Windows's. It applies at the next launch.
$script:LanguageChoices = [ordered]@{ (Tr 'Langue de Windows') = ''; (Tr 'Français') = 'fr'; English = 'en' }
# One scale shared by every window, menu and tooltip, so a new size applies to all of them at once.
$script:UiScale = [System.Windows.Media.ScaleTransform]::new(1, 1)
# The variant the colors were last built for, so Système can follow Windows when the window is activated.
$script:CurrentVariant = $null
# What the text boxes' bitmap was last made for (Set-TextCache): its scale, '' for none.
$script:TextCacheKey = $null

#region Colors

function ConvertFrom-HexColor([string]$Hex) {
    $h = $Hex.TrimStart('#')
    [int[]]@([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Merge-Color([string]$From, [string]$To, [double]$Amount) {
    # $Amount of $To mixed into $From.
    $a = ConvertFrom-HexColor $From
    $b = ConvertFrom-HexColor $To
    '#' + ((0..2 | ForEach-Object { '{0:X2}' -f [int][Math]::Round($a[$_] + ($b[$_] - $a[$_]) * $Amount) }) -join '')
}

function Get-Contrast([string]$A, [string]$B) {
    # WCAG contrast ratio, from 1 to 21.
    $luminance = foreach ($hex in $A, $B) {
        $c = ConvertFrom-HexColor $hex | ForEach-Object {
            $v = $_ / 255
            if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) }
        }
        0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2]
    }
    ([Math]::Max($luminance[0], $luminance[1]) + 0.05) / ([Math]::Min($luminance[0], $luminance[1]) + 0.05)
}

function Get-ThemeAccent([string]$Accent, $Palette, [bool]$IsDark) {
    # Any accent the user picks, made visible in this theme: darkened on the light background, lightened on a dark one,
    # just enough to stand out at 3:1, so selected rows, a checked toggle button (Filtres) and focus borders don't vanish.
    $against = if ($IsDark) { $Palette.Bg } else { $Palette.Surface }
    $toward = if ($IsDark) { '#FFFFFF' } else { '#000000' }
    $adjusted = $Accent
    for ($i = 1; $i -le 20 -and (Get-Contrast $adjusted $against) -lt 3; $i++) { $adjusted = Merge-Color $Accent $toward ($i / 20) }
    $adjusted
}

function ConvertTo-Hsl([string]$Hex) {
    # Hue (0-360), saturation and lightness (0-100), for the editor's sliders.
    $r, $g, $b = ConvertFrom-HexColor $Hex | ForEach-Object { $_ / 255 }
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2
    $h = $s = 0
    $d = $max - $min
    if ($d -gt 0) {
        $s = if ($l -gt 0.5) { $d / (2 - $max - $min) } else { $d / ($max + $min) }
        $h = if ($max -eq $r) { (($g - $b) / $d) % 6 } elseif ($max -eq $g) { ($b - $r) / $d + 2 } else { ($r - $g) / $d + 4 }
        $h = ($h * 60 + 360) % 360
    }
    @{ H = [Math]::Round($h); S = [Math]::Round($s * 100); L = [Math]::Round($l * 100) }
}

function ConvertFrom-Hsl([double]$H, [double]$S, [double]$L) {
    $S = $S / 100
    $L = $L / 100
    $c = (1 - [Math]::Abs(2 * $l - 1)) * $s
    $x = $c * (1 - [Math]::Abs((($H / 60) % 2) - 1))
    $m = $l - $c / 2
    $r, $g, $b = switch ([int][Math]::Floor(($H % 360) / 60)) {
        0 { $c, $x, 0 } 1 { $x, $c, 0 } 2 { 0, $c, $x } 3 { 0, $x, $c } 4 { $x, 0, $c } default { $c, 0, $x }
    }
    '#' + ((($r, $g, $b) | ForEach-Object { '{0:X2}' -f [int][Math]::Round(($_ + $m) * 255) }) -join '')
}

function Get-ThemeColor($Spec, [string]$Variant) {
    # The colors a theme of one's own sets in this variant, by key (empty for a preset, which has no Colors).
    $colors = if ($Spec -is [System.Collections.IDictionary]) { $Spec['Colors'] } elseif ($Spec.PSObject.Properties['Colors']) { $Spec.Colors }
    if ($colors -and $colors[$Variant]) { $colors[$Variant] } else { @{} }
}

function Set-ThemeColor($Palette, $Colors, [bool]$IsDark) {
    # A copy of the palette with a theme's own colors, and the shades mixed from them redone the way the presets' are.
    $p = [ordered]@{}
    foreach ($key in $Palette.Keys) { $p[$key] = $Palette[$key] }
    foreach ($key in $Colors.Keys) { if ($p.Contains($key)) { $p[$key] = $Colors[$key] } }
    # A shade is mixed again from a color it comes from that the theme sets, unless the theme sets the shade itself.
    $derive = { param([string]$Key, [string[]]$From) -not $Colors.Contains($Key) -and @($From | Where-Object { $Colors.Contains($_) }).Count -gt 0 }
    if (& $derive 'Chrome' 'Bg', 'Surface') { $p.Chrome = if ($IsDark) { Merge-Color $p.Bg $p.Surface 0.5 } else { $p.Surface } }
    if (& $derive 'ControlHover' 'Control', 'Border', 'Surface') { $p.ControlHover = Merge-Color $p.Control $p.Border $(if ($IsDark) { 0.65 } else { 0.4 }) }
    if (& $derive 'ControlPressed' 'Control', 'Border', 'Surface') {
        $p.ControlPressed = if ($IsDark) { Merge-Color $p.Control $p.Surface 0.5 } else { Merge-Color $p.Control $p.Border 0.65 }
    }
    if (& $derive 'BorderStrong' 'Border', 'Text') { $p.BorderStrong = Merge-Color $p.Border $p.Text $(if ($IsDark) { 0.12 } else { 0.15 }) }
    if (& $derive 'Faint' 'Muted', 'Surface') { $p.Faint = Merge-Color $p.Muted $p.Surface 0.3 }
    if (& $derive 'RowHover' 'Surface', 'Control', 'Bg') { $p.RowHover = if ($IsDark) { Merge-Color $p.Surface $p.Control 0.6 } else { Merge-Color $p.Surface $p.Bg 0.7 } }
    $p
}

function Get-SchemePalette($Spec, [string]$Variant) {
    # A theme's palette for Light or Dark: a preset's own, or the neutral one tinted toward the theme's accent, with the
    # colors a theme of one's own sets.
    $colors = Get-ThemeColor $Spec $Variant
    # By key: a theme of one's own has no Palettes, nor Accents (Get-ThemeBrush).
    if ($Spec['Palettes']) { return $script:Palettes[$Spec['Palettes'][$Variant]] }
    $base = if ($Variant -eq 'Dark') { $script:Palettes.DarkGrey } else { $script:Palettes.LightGrey }
    $strength = $script:Tints[[string]$Spec.Tint]
    $amounts = $script:TintAmounts[$Variant]
    $p = [ordered]@{}
    foreach ($key in $base.Keys) {
        $amount = [double]$amounts[$key] * $strength
        $p[$key] = if ($amount -gt 0) { Merge-Color $base[$key] $Spec.Accent $amount } else { $base[$key] }
    }
    # A tinted text that reads less well than 4.5:1 on the lists or the window's background goes back to the neutral
    # one; the secondary text is mixed toward the text until it reads, keeping its tint.
    $reads = { param([string]$Color) [Math]::Min((Get-Contrast $Color $p.Surface), (Get-Contrast $Color $p.Bg)) -ge 4.5 }
    if (-not (& $reads $p.Text)) { $p.Text = $base.Text }
    $muted = $p.Muted
    for ($i = 1; $i -le 10 -and -not (& $reads $p.Muted); $i++) { $p.Muted = Merge-Color $muted $p.Text ($i / 10) }
    if ($colors.Count) { $p = Set-ThemeColor $p $colors ($Variant -eq 'Dark') }
    $p
}

function Get-ThemeBrush([string]$Variant, $Spec) {
    # Every color of a theme in one variant, palette and accent shades included, as R.<name> => hex.
    $isDark = $Variant -eq 'Dark'
    $p = Get-SchemePalette $Spec $Variant
    $own = Get-ThemeColor $Spec $Variant
    $source = if ($own.Contains('Accent')) { $own.Accent } elseif ($Spec['Accents']) { $Spec['Accents'][$Variant] } else { $Spec.Accent }
    # The quick accent (the theme's Accent, a preset's) is made visible in each mode. A mode's own, set in the editor's
    # Couleurs, is used as typed by a theme saved since 0.13 (Exact), which warns instead when it's hard to see; one of a
    # theme saved before is made visible, as it was then.
    $Accent = if ($own.Contains('Accent') -and $Spec['Exact']) { $own.Accent } else { Get-ThemeAccent $source $p $isDark }
    $c = [ordered]@{}
    foreach ($key in $p.Keys) { $c[$key] = $p[$key] }
    $c.Accent = $Accent
    # What's mixed from the accent, unless the theme sets it. The text on the accent: white, or dark when that reads
    # better (a light custom accent), black when neither reads at 4.5:1 (a mid-tone one; one of the two always does).
    $c.OnAccent = if ($own.Contains('OnAccent')) { $own.OnAccent }
                  elseif ((Get-Contrast $Accent '#FFFFFF') -ge 4.5) { '#FFFFFF' }
                  elseif ((Get-Contrast $Accent '#17121C') -ge 4.5) { '#17121C' }
                  elseif ((Get-Contrast $Accent '#FFFFFF') -ge (Get-Contrast $Accent '#000000')) { '#FFFFFF' } else { '#000000' }
    # Hover and press darken the accent, or lighten it when darkening would make its text hard to read.
    foreach ($state in @{ Key = 'AccentHover'; Amount = 0.12 }, @{ Key = 'AccentPressed'; Amount = 0.18 }) {
        if ($own.Contains($state.Key)) { $c[$state.Key] = $own[$state.Key]; continue }
        $shade = Merge-Color $Accent '#000000' $state.Amount
        if ((Get-Contrast $shade $c.OnAccent) -lt 4.5) { $shade = Merge-Color $Accent '#FFFFFF' $state.Amount }
        $c[$state.Key] = $shade
    }
    # Accent-colored text is lightened or darkened until it reads on the surface.
    $text = $Accent
    $toward = if ($isDark) { '#FFFFFF' } else { '#000000' }
    for ($i = 1; $i -le 10 -and (Get-Contrast $text $p.Surface) -lt 4.5; $i++) { $text = Merge-Color $Accent $toward ($i / 10) }
    $c.AccentText = if ($own.Contains('AccentText')) { $own.AccentText } else { $text }
    # The selected row: the accent mixed into the surface, less of it when the text would read less than 4.5:1 there (a
    # light accent in the dark mode), down to 6 %. Not for a text that doesn't read on the surface itself (the theme's
    # own, which the editor warns of): the selection would only vanish.
    $start = if ($isDark) { 0.26 } else { 0.13 }
    $amount = $start
    if ((Get-Contrast $p.Text $p.Surface) -ge 4.5) {
        $steps = [Math]::Floor(($start - 0.06) / 0.04 + 1e-9)
        for ($step = 1; $step -le $steps -and (Get-Contrast $p.Text (Merge-Color $p.Surface $Accent $amount)) -lt 4.5; $step++) { $amount = $start - 0.04 * $step }
    }
    $c.Selection = if ($own.Contains('Selection')) { $own.Selection } else { Merge-Color $p.Surface $Accent $amount }
    # The selected row under the pointer, a little stronger.
    $c.SelectionHover = if ($own.Contains('SelectionHover')) { $own.SelectionHover }
                        elseif ($own.Contains('Selection')) { Merge-Color $own.Selection $Accent 0.12 }
                        else { Merge-Color $p.Surface $Accent ($amount + $(if ($isDark) { 0.08 } else { 0.06 })) }

    $brushes = [ordered]@{}
    foreach ($key in $c.Keys) { $brushes["R.$key"] = $c[$key] }
    $brushes
}

function Update-ThemeResource([string]$Scheme = $script:Appearance.Scheme) {
    # Replaces each color in the application's resources (every DynamicResource follows), then switches Fluent's
    # controls to the same variant. -Scheme: a theme to show rather than the one chosen (Show-ThemePreview).
    $variant = Get-ThemeVariant
    $brushes = Get-ThemeBrush $variant (Get-SchemeSpec $Scheme)
    $app = [System.Windows.Application]::Current
    foreach ($key in $brushes.Keys) {
        $brush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($brushes[$key]))
        $brush.Freeze()
        $app.Resources[$key] = $brush
    }
    $mode = if ($variant -eq 'Dark') { [System.Windows.ThemeMode]::Dark } else { [System.Windows.ThemeMode]::Light }
    if ($app.ThemeMode -ne $mode) { $app.ThemeMode = $mode }
    Set-FluentAccent $brushes $variant
    $script:CurrentVariant = $variant
}

# The Fluent brushes replaced by Set-FluentAccent, removed before the next theme's.
$script:FluentAccentKeys = [System.Collections.Generic.List[object]]::new()

function Set-FluentAccent($Brushes, [string]$Variant) {
    # Fluent's own controls (check boxes, radio buttons, sliders, toggles, the focused text box's border, list
    # selections, links) take Windows' accent color, not the theme's. Their brushes are replaced at the application's
    # level, each by the theme's color for its role. They're found by their color in Fluent's dictionary for the mode,
    # which the replacements don't change: its fill shade (lighter in dark mode, darker in light mode), Windows' accent
    # itself, and the other shades for text and links.
    $app = [System.Windows.Application]::Current
    foreach ($key in $script:FluentAccentKeys) { $app.Resources.Remove($key) }
    $script:FluentAccentKeys.Clear()
    $sc = [System.Windows.SystemColors]
    $shades = @($sc::AccentColor, $sc::AccentColorLight1, $sc::AccentColorLight2, $sc::AccentColorLight3, $sc::AccentColorDark1, $sc::AccentColorDark2, $sc::AccentColorDark3)
    # What's drawn on the accent: the tick of a check box, the dot of a radio button, a toggle's knob, an accent button's text.
    $onAccent = '^(CheckBoxCheckGlyphForeground(Pressed)?|RadioButtonCheckGlyphFill|ToggleSwitchKnobFillOn(PointerOver|Pressed)?|TextOnAccentFillColorPrimaryBrush|AccentButtonForeground(PointerOver|Pressed)?)$'
    $dictionaries = foreach ($dictionary in $app.Resources.MergedDictionaries) { $dictionary; $dictionary.MergedDictionaries }
    foreach ($dictionary in $dictionaries) {
        foreach ($key in @($dictionary.Keys)) {
            # Reading a resource builds it: only a named one can be one of these brushes, so the styles, templates and
            # menus (keyed by type, or named so) aren't built just to be skipped, a tenth of a second at each change.
            if ($key -isnot [string] -or $key -match '(Style|Template|ContextMenu|FocusVisual)$') { continue }
            $brush = $dictionary[$key]
            if ($brush -isnot [System.Windows.Media.SolidColorBrush]) { continue }
            $name = "$key"
            $role = if ($name -match $onAccent) { 'R.OnAccent' }
                    elseif ($shades -notcontains $brush.Color) { continue }
                    elseif ($name -match 'ListBoxItem|DataGridRow') { 'R.Selection' }
                    elseif ($name -match '^AccentTextFill|Hyperlink') { 'R.AccentText' }
                    else { 'R.Accent' }
            $replacement = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($Brushes[$role]))
            $replacement.Freeze()
            $app.Resources[$key] = $replacement
            $script:FluentAccentKeys.Add($key)
        }
    }
}

#endregion

#region Appearance settings

function Test-AccentColor([string]$Accent) {
    # Any #RRGGBB color: Get-ThemeAccent makes the quick accent visible in each mode, and the editor warns when a color
    # of one's own is hard to see (Update-EditorColor).
    $Accent -match '^#[0-9A-Fa-f]{6}\z'
}

function Get-SchemeSpec([string]$Key) {
    # A theme by its key: a preset, one of the user's, or Repère's when it no longer exists.
    if ($script:Presets.Contains($Key)) { return $script:Presets[$Key] }
    foreach ($theme in $script:Appearance.CustomThemes) {
        if ($theme.Id -eq $Key) { return $theme }
    }
    $script:Presets.Repere
}

function Read-Appearance {
    try {
        # Every setting this version knows, $null when the file doesn't have it (an older or newer Repère wrote it):
        # strict mode or not, a setting that's missing then reads as none.
        $saved = Read-JsonSetting $script:AppearancePath Theme, Scheme, CustomThemes, Columns, UserColumns, GroupColumns, FoldedSections, HiddenColumnFilters, FontFamily, FontWeight, TextScale, Density, Accent, DarkStyle
        if (-not $saved) { return }
        if ($saved.Theme -in 'Système', 'Clair', 'Sombre') { $script:Appearance.Theme = $saved.Theme }
        foreach ($theme in @($saved.CustomThemes | Where-Object { $_ } | Select-Object Id, Name, Accent, Tint, Colors, Exact)) {
            if ("$($theme.Id)" -notmatch '^c\d+$' -or -not (Test-AccentColor $theme.Accent)) { continue }
            $entry = @{
                Id     = [string]$theme.Id
                Name   = if ("$($theme.Name)".Trim()) { "$($theme.Name)".Trim() } else { Tr 'Mon thème' }
                Accent = ([string]$theme.Accent).ToUpperInvariant()
                Tint   = if ($script:Tints.Contains([string]$theme.Tint)) { [string]$theme.Tint } else { 'Teinté' }
            }
            $colors = ConvertFrom-SavedThemeColor $theme.Colors
            if ($colors) { $entry.Colors = $colors }
            # Saved by the editor since 0.13: a mode's own accent is used as typed (Get-ThemeBrush).
            if ($theme.Exact -eq $true) { $entry.Exact = $true }
            $script:Appearance.CustomThemes.Add($entry)
        }
        if ($saved.Columns) { $script:Appearance.Columns = @($saved.Columns) }
        if ($saved.UserColumns) { $script:Appearance.UserColumns = @($saved.UserColumns) }
        if ($saved.GroupColumns) { $script:Appearance.GroupColumns = @($saved.GroupColumns) }
        if ($saved.FoldedSections) { $script:Appearance.FoldedSections = @($saved.FoldedSections | ForEach-Object { [string]$_ }) }
        if ($saved.HiddenColumnFilters) { $script:Appearance.HiddenColumnFilters = @($saved.HiddenColumnFilters | ForEach-Object { [string]$_ }) }
        # A font that isn't offered stays Segoe UI; one no longer found is drawn in Segoe UI (Set-UiText).
        if ($script:FontChoices.Contains("$($saved.FontFamily)".Trim())) { $script:Appearance.FontFamily = "$($saved.FontFamily)".Trim() }
        if ($script:FontWeights.Contains([string]$saved.FontWeight)) { $script:Appearance.FontWeight = [string]$saved.FontWeight }
        $scale = 0.0
        if ([double]::TryParse("$($saved.TextScale)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$scale) -and
            @($script:TextScales.Values | Where-Object { [Math]::Abs($_ - $scale) -lt 0.001 }).Count) { $script:Appearance.TextScale = $scale }
        # A density that isn't offered stays Normale.
        $density = @($script:Densities.Keys | Where-Object { $_ -eq "$($saved.Density)".Trim() })
        if ($density.Count) { $script:Appearance.Density = $density[0] }
        if ($saved.Scheme) {
            # A renamed preset opens on its new name; a theme that no longer exists falls back to Repère's.
            $key = [string]$saved.Scheme
            if ($script:RenamedPresets.Contains($key)) { $key = $script:RenamedPresets[$key] }
            if ($script:Presets.Contains($key) -or @($script:Appearance.CustomThemes | Where-Object { $_.Id -eq $key }).Count) {
                $script:Appearance.Scheme = $key
            }
        }
        elseif ($saved.Accent) {
            # Settings from before the themes: an accent (a preset's name or #RRGGBB) and a dark style (Violet or Gris).
            $presetOf = @{ Violet = 'Repere'; Bleu = 'Marine'; Sarcelle = 'Lagon'; Vert = 'Mousse'; Orange = 'Terracotta'; Rose = 'Framboise'; Graphite = 'Graphite' }
            $accent = [string]$saved.Accent
            $hex = if ($presetOf.Contains($accent)) { $script:Presets[$presetOf[$accent]].Accent } elseif (Test-AccentColor $accent) { $accent.ToUpperInvariant() }
            if ($saved.DarkStyle -eq 'Gris' -and $accent -ne 'Graphite' -and $hex) {
                $script:Appearance.Scheme = Add-CustomTheme (Tr 'Gris') $hex 'Neutre'
            }
            elseif ($presetOf.Contains($accent)) {
                $script:Appearance.Scheme = $presetOf[$accent]
            }
            elseif ($hex) {
                $script:Appearance.Scheme = Add-CustomTheme (Tr 'Personnalisé') $hex 'Teinté'
            }
        }
    }
    catch {
        # A value that isn't what this version expects: keep the defaults from there.
        Write-Verbose "Apparence par défaut : $_"
    }
}

function ConvertFrom-SavedThemeColor($Saved) {
    # A theme's own colors as saved: per mode, only those known, each a #RRGGBB. $null when none is left.
    $colors = @{}
    if ($Saved) { $Saved = $Saved | Select-Object Light, Dark }
    foreach ($variant in 'Light', 'Dark') {
        $set = @{}
        if ($Saved -and $Saved.$variant) {
            foreach ($property in $Saved.$variant.PSObject.Properties) {
                if ($script:ThemeColors.Contains($property.Name) -and (Test-AccentColor "$($property.Value)")) { $set[$property.Name] = "$($property.Value)".ToUpperInvariant() }
            }
        }
        if ($set.Count) { $colors[$variant] = $set }
    }
    if ($colors.Count) { $colors }
}

function Add-CustomTheme([string]$Name, [string]$Accent, [string]$Tint, $Colors, [switch]$Exact) {
    # Adds one of the user's themes (with its own colors, if any) and returns its Id. -Exact: saved by the editor, whose
    # colors of one's own are used as typed.
    $numbers = @($script:Appearance.CustomThemes | ForEach-Object { [int]$_.Id.Substring(1) })
    $id = 'c' + ((@($numbers + 0) | Measure-Object -Maximum).Maximum + 1)
    $theme = @{ Id = $id; Name = $Name; Accent = $Accent; Tint = $Tint }
    if ($Colors -and $Colors.Count) { $theme.Colors = $Colors }
    if ($Exact) { $theme.Exact = $true }
    $script:Appearance.CustomThemes.Add($theme)
    $id
}

function Save-Appearance {
    $settings = [ordered]@{
        Theme = $script:Appearance.Theme; Scheme = $script:Appearance.Scheme; CustomThemes = @($script:Appearance.CustomThemes)
    }
    if ($script:Appearance.Columns) { $settings.Columns = @($script:Appearance.Columns) }
    if ($script:Appearance.UserColumns) { $settings.UserColumns = @($script:Appearance.UserColumns) }
    if ($script:Appearance.GroupColumns) { $settings.GroupColumns = @($script:Appearance.GroupColumns) }
    if (@($script:Appearance.FoldedSections).Count) { $settings.FoldedSections = @($script:Appearance.FoldedSections) }
    if (@($script:Appearance.HiddenColumnFilters).Count) { $settings.HiddenColumnFilters = @($script:Appearance.HiddenColumnFilters) }
    # Only when changed: settings saved with the defaults stay as they were.
    if ($script:Appearance.FontFamily -ne 'Segoe UI') { $settings.FontFamily = $script:Appearance.FontFamily }
    if ($script:Appearance.TextScale -ne 1.0) { $settings.TextScale = $script:Appearance.TextScale }
    if ($script:Appearance.FontWeight -ne 'SemiBold') { $settings.FontWeight = $script:Appearance.FontWeight }
    if ($script:Appearance.Density -ne 'Normale') { $settings.Density = $script:Appearance.Density }
    # Deep enough for a theme's own colors: CustomThemes, a theme, Colors, a mode, a color.
    Save-JsonSetting $script:AppearancePath $settings -Depth 6
}

function Get-ThemeVariant {
    # 'Light' or 'Dark'. Système reads Windows' setting for apps.
    switch ($script:Appearance.Theme) {
        'Clair' { 'Light' }
        'Sombre' { 'Dark' }
        default {
            $light = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue
            if ($light -eq 0) { 'Dark' } else { 'Light' }
        }
    }
}

#endregion

#region Styles and icons

function Get-IconXaml([string]$Name, [int]$Size = 16) {
    # The stroke follows the inherited text color, so an icon in a button follows its hover, disabled and accent states.
    "<Viewbox Width=`"$Size`" Height=`"$Size`" VerticalAlignment=`"Center`"><Canvas Width=`"24`" Height=`"24`"><Path Data=`"$($script:Icons[$Name])`" Stroke=`"{Binding (TextElement.Foreground), RelativeSource={RelativeSource Self}}`" StrokeThickness=`"2`" StrokeStartLineCap=`"Round`" StrokeEndLineCap=`"Round`" StrokeLineJoin=`"Round`"/></Canvas></Viewbox>"
}

function Expand-Icon([string]$Xaml) {
    # {{icon:name}} or {{icon:name:size}} -> the icon's XAML; and the text in this run's language (Language.ps1).
    ConvertTo-LocalXaml ($Xaml -replace '\{\{icon:(\w+)(?::(\d+))?\}\}', {
            $size = if ($_.Groups[2].Success) { [int]$_.Groups[2].Value } else { 16 }
            Get-IconXaml $_.Groups[1].Value $size
        })
}

function Set-TextBoxUse([System.Windows.Controls.Control]$Box, [bool]$Used, [string]$Why) {
    # A text box (or password box) that a choice makes useless, or useful again (#183). Unused, it's disabled, which its
    # style greys like a disabled segmented choice, what's typed kept and shown faint, and $Why is its tooltip,
    # shown even though it's disabled, and what Narrator reads. Used again, its own tooltip is back.
    if (-not $Box.Resources.Contains('Repere.OwnToolTip')) { $Box.Resources['Repere.OwnToolTip'] = [string]$Box.ToolTip }
    [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($Box, $true)
    $Box.IsEnabled = $Used
    $own = $Box.Resources['Repere.OwnToolTip']
    $Box.ToolTip = if (-not $Used) { $Why } elseif ($own) { $own } else { $null }
    [System.Windows.Automation.AutomationProperties]::SetHelpText($Box, $(if ($Used) { '' } else { $Why }))
}

function Register-PasswordEye([System.Windows.Controls.PasswordBox]$Box, [System.Windows.Controls.TextBox]$Text, [System.Windows.Controls.Button]$Show, [System.Windows.Controls.Button]$Hide) {
    # A password typed hidden, with an eye: $Show puts it in $Text, in plain text, to check its spelling, and what's
    # typed there goes to $Box, the one read; $Hide hides it again. $Text sits over $Box, collapsed; $Hide, collapsed.
    $parts = @{ Box = $Box; Text = $Text; Show = $Show; Hide = $Hide }
    $Show.CommandParameter = $parts
    $Hide.CommandParameter = $parts
    $Text.Resources['Repere.PasswordEye'] = $parts
    $Show.Add_Click({ param($button) Set-PasswordShown $button.CommandParameter $true })
    $Hide.Add_Click({ param($button) Set-PasswordShown $button.CommandParameter $false })
    $Text.Add_TextChanged({
        param($text)
        $box = $text.Resources['Repere.PasswordEye'].Box
        if ($text.Visibility -eq 'Visible' -and $box.Password -ne $text.Text) { $box.Password = $text.Text }
    })
    $parts
}

function Set-EyeButton([System.Windows.Controls.Button]$Show, [System.Windows.Controls.Button]$Hide, [bool]$Shown) {
    # A password's eye: Afficher while it's hidden, Masquer while it's shown (Set-PasswordShown, Mot de passe LAPS).
    $Show.Visibility = ConvertTo-Visibility (-not $Shown)
    $Hide.Visibility = ConvertTo-Visibility $Shown
}

function Set-PasswordShown($Parts, [bool]$Shown) {
    # Register-PasswordEye's password in plain text, focused at its end, or hidden again: $Text is then emptied, the
    # password stays only in the PasswordBox.
    if ($Shown) { $Parts.Text.Text = $Parts.Box.Password }
    $Parts.Text.Visibility = ConvertTo-Visibility $Shown
    $Parts.Box.Visibility = ConvertTo-Visibility (-not $Shown)
    if (-not $Shown) { $Parts.Text.Text = '' }
    Set-EyeButton $Parts.Show $Parts.Hide $Shown
    if ($Shown) {
        $null = $Parts.Text.Focus()
        $Parts.Text.CaretIndex = $Parts.Text.Text.Length
    }
}

# The copy button showing what its copy did (Show-CopyFeedback), and what it looked like before.
$script:CopyFeedback = @{ Button = $null; Content = $null; ToolTip = $null; Name = $null; MinWidth = 0; Timer = [System.Windows.Threading.DispatcherTimer]::new() }
$script:CopyFeedback.Timer.Interval = [timespan]::FromMilliseconds(1500)
$script:CopyFeedback.Timer.Add_Tick({ Reset-CopyFeedback })

function Show-CopyFeedback([System.Windows.Controls.Button]$Button, [bool]$Copied) {
    # What a copy did, on the button clicked (#200): for 1.5 seconds its copy icon is a ✔ in the success color, or a ✖
    # in red when another program held the clipboard, and its text (when it has one), tooltip and name say « Copié » or
    # « Copie impossible », which Narrator reads. Only the last button shows it: another copy puts the one before back
    # first. It stays the same button, so the focus stays on it, and it keeps its width.
    Reset-CopyFeedback
    $feedback = $script:CopyFeedback
    $label = if ($Copied) { Tr 'Copié' } else { Tr 'Copie impossible' }
    $content = $Button.Content
    $icon = if ($content -is [System.Windows.Controls.Viewbox]) { $content }
            elseif ($content -is [System.Windows.Controls.Panel]) { $content.Children | Where-Object { $_ -is [System.Windows.Controls.Viewbox] } | Select-Object -First 1 }
    $size = if ($icon) { [int]$icon.Width } else { 14 }
    $markXaml = Get-IconXaml $(if ($Copied) { 'check' } else { 'x' }) $size
    $mark = [System.Windows.Markup.XamlReader]::Parse($markXaml.Replace('<Viewbox ', '<Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" '))
    $feedback.Button = $Button
    $feedback.Content = $content
    $feedback.ToolTip = $Button.ToolTip
    $feedback.Name = [System.Windows.Automation.AutomationProperties]::GetName($Button)
    $feedback.MinWidth = $Button.MinWidth
    $Button.MinWidth = $Button.ActualWidth
    if ($content -is [System.Windows.Controls.Panel]) {
        $panel = [System.Windows.Controls.StackPanel]::new()
        $panel.Orientation = 'Horizontal'
        $text = [System.Windows.Controls.TextBlock]::new()
        $text.Text = $label
        $text.Margin = '8,0,0,0'
        $null = $panel.Children.Add($mark)
        $null = $panel.Children.Add($text)
        $Button.Content = $panel
    }
    else { $Button.Content = $mark }
    $Button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $(if ($Copied) { 'R.SuccessText' } else { 'R.DangerText' }))
    $Button.ToolTip = $label
    [System.Windows.Automation.AutomationProperties]::SetName($Button, $label)
    [System.Windows.Automation.AutomationProperties]::SetLiveSetting($Button, [System.Windows.Automation.AutomationLiveSetting]::Polite)
    $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($Button)
    if ($peer) { $peer.RaiseAutomationEvent([System.Windows.Automation.Peers.AutomationEvents]::LiveRegionChanged) }
    $feedback.Timer.Start()
}

function Reset-CopyFeedback {
    # The copy button back to its own look (Show-CopyFeedback), unless its window closed or its list was built again.
    $feedback = $script:CopyFeedback
    $feedback.Timer.Stop()
    $button = $feedback.Button
    $content = $feedback.Content
    $feedback.Button = $null
    $feedback.Content = $null
    if (-not $button -or -not [System.Windows.PresentationSource]::FromVisual($button)) { return }
    $button.Content = $content
    $button.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
    $button.ToolTip = $feedback.ToolTip
    $button.MinWidth = $feedback.MinWidth
    if ($feedback.Name) { [System.Windows.Automation.AutomationProperties]::SetName($button, $feedback.Name) }
    else { $button.ClearValue([System.Windows.Automation.AutomationProperties]::NameProperty) }
    $button.ClearValue([System.Windows.Automation.AutomationProperties]::LiveSettingProperty)
}

# The application's resources: the R.* colors are added by Update-ThemeResource. Styles without a key apply to every
# control of that type; the others are picked with Style="{StaticResource …}". Buttons and toggles share one template
# whose corner radius is the Tag (« 6 », or « 6,0,0,6 » for the left half of a split button), so what a button's click
# needs goes in its CommandParameter, never its Tag (a Tag that isn't a radius falls back to 6); a text box's Tag is its
# placeholder.
$script:SharedResources = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

<!-- A submenu's name in a right-click menu, kept clear of its arrow, which Fluent puts right after the longest name
     (« Clés et mots de passe › » touched in a wide font, #275). The header stays a string, its UI Automation name. -->
<DataTemplate x:Key="Menu.GroupHeader"><TextBlock Text="{Binding}" Margin="0,0,16,0"/></DataTemplate>

<Style x:Key="FocusRing">
  <Setter Property="Control.Template">
    <Setter.Value>
      <ControlTemplate><Rectangle Margin="-3" RadiusX="8" RadiusY="8" Stroke="{DynamicResource R.Accent}" StrokeThickness="2" SnapsToDevicePixels="True"/></ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<ControlTemplate x:Key="ButtonTemplate" TargetType="ButtonBase">
  <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
          CornerRadius="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}, FallbackValue=6}" SnapsToDevicePixels="True">
    <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                      VerticalAlignment="{TemplateBinding VerticalContentAlignment}" RecognizesAccessKey="True"/>
  </Border>
</ControlTemplate>

<Style TargetType="Button">
  <Setter Property="Template" Value="{StaticResource ButtonTemplate}"/>
  <Setter Property="Background" Value="{DynamicResource R.Control}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="{DynamicResource R.ButtonPadding}"/>
  <Setter Property="MinHeight" Value="{DynamicResource R.ControlHeight}"/>
  <Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/>
  <Setter Property="Tag" Value="6"/>
  <Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="VerticalContentAlignment" Value="Center"/>
  <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="BorderBrush" Value="{DynamicResource R.BorderStrong}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlPressed}"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Background" Value="{DynamicResource R.Control}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/><Setter Property="Foreground" Value="{DynamicResource R.Faint}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Btn.Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Background" Value="{DynamicResource R.Accent}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.Accent}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.OnAccent}"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.AccentHover}"/><Setter Property="BorderBrush" Value="{DynamicResource R.AccentHover}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{DynamicResource R.AccentPressed}"/><Setter Property="BorderBrush" Value="{DynamicResource R.AccentPressed}"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Background" Value="{DynamicResource R.Control}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/><Setter Property="Foreground" Value="{DynamicResource R.Faint}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Btn.Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Foreground" Value="{DynamicResource R.DangerText}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.DangerBorder}"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.DangerBg}"/><Setter Property="BorderBrush" Value="{DynamicResource R.DangerBorder}"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/><Setter Property="Foreground" Value="{DynamicResource R.Faint}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Btn.Ghost" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderBrush" Value="Transparent"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="BorderBrush" Value="Transparent"/></Trigger>
  </Style.Triggers>
</Style>

<!-- A button on a warning banner (the names not found): in the banner's amber, outlined, filled with its border's color
     when hovered. -->
<Style x:Key="Btn.Warn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.WarnBorder}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.WarnText}"/>
  <Setter Property="Padding" Value="10,3"/><Setter Property="MinHeight" Value="0"/><Setter Property="FontSize" Value="12"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.WarnBorder}"/><Setter Property="BorderBrush" Value="{DynamicResource R.WarnBorder}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{DynamicResource R.WarnBorder}"/><Setter Property="BorderBrush" Value="{DynamicResource R.WarnText}"/></Trigger>
  </Style.Triggers>
</Style>

<!-- An icon button: as high as the others, as wide whatever the density, so the action bar's labels fit as before. -->
<Style x:Key="Btn.Icon" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Width" Value="34"/><Setter Property="Height" Value="{DynamicResource R.ControlHeight}"/><Setter Property="Padding" Value="0"/>
</Style>

<Style x:Key="Btn.IconDanger" TargetType="Button" BasedOn="{StaticResource Btn.Danger}">
  <Setter Property="Width" Value="34"/><Setter Property="Height" Value="{DynamicResource R.ControlHeight}"/><Setter Property="Padding" Value="0"/>
</Style>

<Style x:Key="Btn.Swatch" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Padding" Value="3"/><Setter Property="MinHeight" Value="0"/><Setter Property="Tag" Value="15"/>
  <Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Margin" Value="0,0,2,0"/>
</Style>

<Style TargetType="ToggleButton">
  <Setter Property="Template" Value="{StaticResource ButtonTemplate}"/>
  <Setter Property="Background" Value="{DynamicResource R.Control}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="{DynamicResource R.ButtonPadding}"/>
  <Setter Property="MinHeight" Value="{DynamicResource R.ControlHeight}"/>
  <Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/>
  <Setter Property="Tag" Value="6"/>
  <Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="VerticalContentAlignment" Value="Center"/>
  <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="BorderBrush" Value="{DynamicResource R.BorderStrong}"/></Trigger>
    <!-- On (Filtres, Options): a state, in the selection's colors with an accent border like the page tabs, not the
         accent fill of the window's main button (#184). -->
    <Trigger Property="IsChecked" Value="True"><Setter Property="Background" Value="{DynamicResource R.Selection}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Accent}"/><Setter Property="Foreground" Value="{DynamicResource R.AccentText}"/></Trigger>
    <MultiTrigger>
      <MultiTrigger.Conditions><Condition Property="IsChecked" Value="True"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions>
      <Setter Property="Background" Value="{DynamicResource R.SelectionHover}"/><Setter Property="BorderBrush" Value="{DynamicResource R.AccentHover}"/>
    </MultiTrigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="{DynamicResource R.Faint}"/></Trigger>
  </Style.Triggers>
</Style>

<!-- A page tab of the title bar (Ordinateurs, Utilisateurs): quiet, the page shown in the selection's colors. -->
<Style x:Key="Toggle.Tab" TargetType="ToggleButton" BasedOn="{StaticResource {x:Type ToggleButton}}">
  <Setter Property="Tag" Value="6"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Background" Value="Transparent"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Muted}"/><Setter Property="Padding" Value="12,6"/><Setter Property="MinHeight" Value="0"/>
  <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="Foreground" Value="{DynamicResource R.Text}"/></Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter Property="Background" Value="{DynamicResource R.Selection}"/><Setter Property="Foreground" Value="{DynamicResource R.AccentText}"/></Trigger>
  </Style.Triggers>
</Style>

<!-- One part of a segmented choice (Dernière connexion, its units). -->
<Style x:Key="Toggle.Seg" TargetType="ToggleButton" BasedOn="{StaticResource {x:Type ToggleButton}}">
  <Setter Property="Tag" Value="0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Background" Value="Transparent"/>
  <Setter Property="Padding" Value="0,6"/><Setter Property="MinHeight" Value="0"/><Setter Property="HorizontalAlignment" Value="Stretch"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/></Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter Property="Background" Value="{DynamicResource R.Accent}"/><Setter Property="Foreground" Value="{DynamicResource R.OnAccent}"/></Trigger>
    <MultiTrigger>
      <MultiTrigger.Conditions><Condition Property="IsChecked" Value="True"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions>
      <Setter Property="Background" Value="{DynamicResource R.AccentHover}"/>
    </MultiTrigger>
    <!-- Disabled (Dernière connexion on « Peu importe », #274): the choice kept shows, muted, not in the accent. -->
    <MultiTrigger>
      <MultiTrigger.Conditions><Condition Property="IsChecked" Value="True"/><Condition Property="IsEnabled" Value="False"/></MultiTrigger.Conditions>
      <Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="Foreground" Value="{DynamicResource R.Faint}"/>
    </MultiTrigger>
  </Style.Triggers>
</Style>

<!-- Paramètres › Apparence's choices, on a Pick.Track: the one chosen is outlined in the accent rather than filled, so a
     page of them doesn't compete with the accent of the theme being looked at. -->
<Style x:Key="Pick.Track" TargetType="Border">
  <Setter Property="Background" Value="{DynamicResource R.Bg}"/><Setter Property="CornerRadius" Value="6"/><Setter Property="Padding" Value="2"/>
  <Setter Property="Height" Value="{DynamicResource R.ControlHeight}"/>
</Style>
<Style x:Key="Toggle.Pick" TargetType="ToggleButton">
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/><Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderBrush" Value="Transparent"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeight}"/>
  <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ToggleButton">
        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1.5" CornerRadius="4">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/></Trigger>
    <Trigger Property="IsChecked" Value="True">
      <Setter Property="Background" Value="{DynamicResource R.Control}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Accent}"/>
      <Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/>
    </Trigger>
  </Style.Triggers>
</Style>

<Style TargetType="TextBox">
  <Setter Property="Background" Value="{DynamicResource R.Input}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="CaretBrush" Value="{DynamicResource R.Text}"/>
  <Setter Property="SelectionBrush" Value="{DynamicResource R.Accent}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="8,0"/>
  <Setter Property="MinHeight" Value="{DynamicResource R.ControlHeight}"/>
  <Setter Property="VerticalContentAlignment" Value="Center"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="TextBox">
        <Border x:Name="Frame" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" SnapsToDevicePixels="True">
          <!-- R.TextCache: the text drawn the same way at every key over Remote Desktop (Set-TextCache). -->
          <Grid Margin="{TemplateBinding Padding}" CacheMode="{DynamicResource R.TextCache}">
            <ScrollViewer x:Name="PART_ContentHost" Focusable="False" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                          HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>
            <!-- The hint, a little after where the text starts: the caret, drawn there, stays clear of its first letter. -->
            <TextBlock x:Name="Placeholder" Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" Foreground="{DynamicResource R.Faint}"
                       Margin="8,0,0,0" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" IsHitTestVisible="False" Visibility="Collapsed"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="Text" Value=""><Setter TargetName="Placeholder" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Frame" Property="BorderBrush" Value="{DynamicResource R.BorderStrong}"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Frame" Property="BorderBrush" Value="{DynamicResource R.Accent}"/></Trigger>
          <!-- A box that a choice makes useless (#183): greyed like a disabled segmented choice (Dernière connexion's
               units), its frame kept, what's typed or its hint shown faint. Its tooltip says why (Set-TextBoxUse). -->
          <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="Frame" Property="Background" Value="{DynamicResource R.Control}"/>
            <Setter TargetName="Frame" Property="BorderBrush" Value="{DynamicResource R.Border}"/>
            <Setter Property="Foreground" Value="{DynamicResource R.Faint}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<!-- A password box, drawn as a text box (without a hint: a PasswordBox doesn't say whether it's empty); unused, greyed the
     same way. Its eye is Register-PasswordEye. -->
<Style TargetType="PasswordBox">
  <Setter Property="Background" Value="{DynamicResource R.Input}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="CaretBrush" Value="{DynamicResource R.Text}"/>
  <Setter Property="SelectionBrush" Value="{DynamicResource R.Accent}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="8,0"/>
  <Setter Property="MinHeight" Value="{DynamicResource R.ControlHeight}"/>
  <Setter Property="VerticalContentAlignment" Value="Center"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="PasswordBox">
        <Border x:Name="Frame" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" SnapsToDevicePixels="True">
          <Grid Margin="{TemplateBinding Padding}" CacheMode="{DynamicResource R.TextCache}">
            <ScrollViewer x:Name="PART_ContentHost" Focusable="False" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                          HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Frame" Property="BorderBrush" Value="{DynamicResource R.BorderStrong}"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Frame" Property="BorderBrush" Value="{DynamicResource R.Accent}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="Frame" Property="Background" Value="{DynamicResource R.Control}"/>
            <Setter TargetName="Frame" Property="BorderBrush" Value="{DynamicResource R.Border}"/>
            <Setter Property="Foreground" Value="{DynamicResource R.Faint}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<!-- A text box drawn by the Field border around it. -->
<Style x:Key="Text.Bare" TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
  <Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>
  <Setter Property="MinHeight" Value="0"/><Setter Property="Padding" Value="4,0"/>
</Style>

<Style x:Key="Combo.Item" TargetType="ComboBoxItem">
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="Padding" Value="{DynamicResource R.ItemPadding}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ComboBoxItem">
        <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" Margin="4,1" CornerRadius="4"><ContentPresenter/></Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsHighlighted" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/></Trigger>
    <Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{DynamicResource R.Selection}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Txt.Muted" TargetType="TextBlock"><Setter Property="Foreground" Value="{DynamicResource R.Muted}"/></Style>
<Style x:Key="Txt.Faint" TargetType="TextBlock"><Setter Property="Foreground" Value="{DynamicResource R.Faint}"/></Style>
<Style x:Key="Txt.Label" TargetType="TextBlock"><Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource R.Muted}"/></Style>

<Style x:Key="Card" TargetType="Border">
  <Setter Property="Background" Value="{DynamicResource R.Surface}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="8"/>
</Style>
<Style x:Key="Field" TargetType="Border">
  <Setter Property="Background" Value="{DynamicResource R.Input}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="6"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="BorderBrush" Value="{DynamicResource R.BorderStrong}"/></Trigger>
    <Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter Property="BorderBrush" Value="{DynamicResource R.Accent}"/></Trigger>
  </Style.Triggers>
</Style>
<!-- A key, as Paramètres › Raccourcis shows it. -->
<Style x:Key="Pill.Key" TargetType="Border">
  <Setter Property="CornerRadius" Value="5"/><Setter Property="Padding" Value="8,2"/><Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Background" Value="{DynamicResource R.Control}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Style.Resources>
    <Style TargetType="TextBlock"><Setter Property="FontSize" Value="12"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/></Style>
  </Style.Resources>
</Style>

<Style x:Key="Pill.Warn" TargetType="Border">
  <Setter Property="CornerRadius" Value="5"/><Setter Property="Padding" Value="7,1"/><Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Background" Value="{DynamicResource R.WarnBg}"/><Setter Property="BorderBrush" Value="{DynamicResource R.WarnBorder}"/>
  <Style.Resources>
    <Style TargetType="TextBlock"><Setter Property="FontSize" Value="11.5"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/><Setter Property="Foreground" Value="{DynamicResource R.WarnText}"/></Style>
  </Style.Resources>
</Style>

<!-- A label on a row (#199): what a member or a group is (Utilisateur, Directe, Sécurité), in Propriétés,
     Caractéristiques and Comparer les groupes. Small corners, no bold and no accent, so it doesn't read as a button.
     Badge: Text on Control; Badge.Quiet, outlined: Muted on the card. Both pairs are checked by the theme editor. -->
<Style x:Key="Badge" TargetType="Border">
  <Setter Property="CornerRadius" Value="4"/><Setter Property="Padding" Value="6,1"/><Setter Property="BorderThickness" Value="1"/>
  <Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="Background" Value="{DynamicResource R.Control}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
  <Setter Property="TextElement.Foreground" Value="{DynamicResource R.Text}"/><Setter Property="TextElement.FontSize" Value="11.5"/>
  <Setter Property="TextElement.FontWeight" Value="{DynamicResource R.FontWeight}"/>
</Style>
<Style x:Key="Badge.Quiet" TargetType="Border" BasedOn="{StaticResource Badge}">
  <Setter Property="Background" Value="Transparent"/><Setter Property="TextElement.Foreground" Value="{DynamicResource R.Muted}"/>
</Style>

<!-- A column's filter, in its header (ColumnFilter.ps1): a funnel, filled once the column is filtered (BorderBrush). Its
     tooltip is set by the code, in the run's language. It takes the click: no sort, no drag. -->
<Style x:Key="Grid.FilterButton" TargetType="Button">
  <Setter Property="Width" Value="22"/><Setter Property="Height" Value="22"/><Setter Property="Margin" Value="4,0,-4,0"/>
  <Setter Property="Focusable" Value="False"/><Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Faint}"/>
  <Setter Property="ToolTip" Value="{DynamicResource R.FilterTip}"/>
  <Setter Property="AutomationProperties.Name" Value="{DynamicResource R.FilterTip}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border Background="{TemplateBinding Background}" CornerRadius="4">
          <Viewbox Width="12" Height="12">
            <Canvas Width="24" Height="24">
              <Path Data="M4,5 H20 L14,12.5 V19 L10,17 V12.5 Z" Fill="{TemplateBinding BorderBrush}" Stroke="{TemplateBinding Foreground}" StrokeThickness="2.2" StrokeLineJoin="Round"/>
            </Canvas>
          </Viewbox>
        </Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="Foreground" Value="{DynamicResource R.Text}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Grid.Header" TargetType="DataGridColumnHeader">
  <Setter Property="Background" Value="{DynamicResource R.Surface}"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Muted}"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/>
  <Setter Property="MinHeight" Value="{DynamicResource R.HeaderHeight}"/>
  <Setter Property="Padding" Value="12,0"/>
  <Setter Property="HorizontalContentAlignment" Value="Left"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="DataGridColumnHeader">
        <Grid>
          <Border Background="{TemplateBinding Background}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1">
            <Grid Margin="{TemplateBinding Padding}">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
              <Path x:Name="SortArrow" Grid.Column="1" Margin="6,1,0,0" Width="8" Height="5" Stretch="Fill" VerticalAlignment="Center" HorizontalAlignment="Left"
                    Data="M0,0 L4,5 L8,0" Stroke="{TemplateBinding Foreground}" StrokeThickness="1.5" Visibility="Collapsed"/>
              <!-- The column's filter, by the header's Tag (ColumnFilter.ps1): Filter shows it, Active fills it. -->
              <Button x:Name="FilterButton" Grid.Column="2" Style="{StaticResource Grid.FilterButton}" Visibility="Collapsed"
                      AutomationProperties.AutomationId="{Binding Column.SortMemberPath, RelativeSource={RelativeSource TemplatedParent}, StringFormat=colfilter_{0}}"/>
            </Grid>
          </Border>
          <!-- Where the column ends: a thin line, in the accent under the pointer where it can be dragged to resize. The
               left grip resizes the previous column, so it lights up this header's left edge, next to that column's line. -->
          <Border x:Name="RightEdge" HorizontalAlignment="Right" Width="1" Margin="0,10" Background="{DynamicResource R.Border}" IsHitTestVisible="False"/>
          <Border x:Name="LeftEdge" HorizontalAlignment="Left" Width="2" Margin="0,6" Background="Transparent" IsHitTestVisible="False"/>
          <Thumb x:Name="PART_LeftHeaderGripper" HorizontalAlignment="Left" Width="6" Opacity="0" Cursor="SizeWE"/>
          <Thumb x:Name="PART_RightHeaderGripper" HorizontalAlignment="Right" Width="6" Opacity="0" Cursor="SizeWE"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger SourceName="PART_RightHeaderGripper" Property="IsMouseOver" Value="True">
            <Setter TargetName="RightEdge" Property="Background" Value="{DynamicResource R.Accent}"/><Setter TargetName="RightEdge" Property="Width" Value="2"/><Setter TargetName="RightEdge" Property="Margin" Value="0,6"/>
          </Trigger>
          <Trigger SourceName="PART_LeftHeaderGripper" Property="IsMouseOver" Value="True"><Setter TargetName="LeftEdge" Property="Background" Value="{DynamicResource R.Accent}"/></Trigger>
          <Trigger Property="SortDirection" Value="Ascending"><Setter TargetName="SortArrow" Property="Visibility" Value="Visible"/><Setter TargetName="SortArrow" Property="Data" Value="M0,5 L4,0 L8,5"/></Trigger>
          <Trigger Property="SortDirection" Value="Descending"><Setter TargetName="SortArrow" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{DynamicResource R.Text}"/></Trigger>
          <Trigger Property="Tag" Value="Filter"><Setter TargetName="FilterButton" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="Tag" Value="Active">
            <Setter TargetName="FilterButton" Property="Visibility" Value="Visible"/>
            <Setter TargetName="FilterButton" Property="Foreground" Value="{DynamicResource R.AccentText}"/><Setter TargetName="FilterButton" Property="BorderBrush" Value="{DynamicResource R.AccentText}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<!-- The grid resets a row's Background to its own RowBackground, so hover and selection are drawn by the template. -->
<Style x:Key="Grid.Row" TargetType="DataGridRow">
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="DataGridRow">
        <Border x:Name="RowBorder" Background="Transparent" SnapsToDevicePixels="True">
          <DataGridCellsPresenter ItemsPanel="{TemplateBinding ItemsPanel}" SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="RowBorder" Property="Background" Value="{DynamicResource R.RowHover}"/></Trigger>
          <Trigger Property="IsSelected" Value="True"><Setter TargetName="RowBorder" Property="Background" Value="{DynamicResource R.Selection}"/></Trigger>
          <MultiTrigger>
            <MultiTrigger.Conditions><Condition Property="IsSelected" Value="True"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions>
            <Setter TargetName="RowBorder" Property="Background" Value="{DynamicResource R.SelectionHover}"/>
          </MultiTrigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<!-- The row draws the selection; cells stay transparent, with no focus box. -->
<Style x:Key="Grid.Cell" TargetType="DataGridCell">
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderThickness" Value="0"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="DataGridCell">
        <Border Background="{TemplateBinding Background}"><ContentPresenter VerticalAlignment="Center"/></Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<!-- The text of a cell. Every cell's text is named CellTextBlock, for the UI tests. -->
<Style x:Key="Grid.Text" TargetType="TextBlock">
  <Setter Property="Margin" Value="12,0"/>
  <Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
  <Setter Property="AutomationProperties.AutomationId" Value="CellTextBlock"/>
</Style>

<!-- A grid column of names: its text a step bolder than the rest, as the chosen weight says. -->
<Style x:Key="Grid.Text.Strong" TargetType="TextBlock" BasedOn="{StaticResource Grid.Text}">
  <Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/>
</Style>

<!-- The title bar's buttons (Set-WindowChrome), drawn like Windows 11's: Segoe Fluent Icons' glyphs (Segoe MDL2 Assets
     on Windows 10), the theme's hover, red for Fermer. -->
<Style x:Key="Btn.Caption" TargetType="Button">
  <Setter Property="Width" Value="46"/><Setter Property="Focusable" Value="False"/><Setter Property="IsTabStop" Value="False"/>
  <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/><Setter Property="FontSize" Value="10"/>
  <Setter Property="FontWeight" Value="Normal"/><Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{DynamicResource R.Control}"/></Trigger>
  </Style.Triggers>
</Style>
<Style x:Key="Btn.CaptionClose" TargetType="Button" BasedOn="{StaticResource Btn.Caption}">
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#C42B1C"/><Setter Property="Foreground" Value="White"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="#B22A1D"/><Setter Property="Foreground" Value="White"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Btn.Mini" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
  <Setter Property="Width" Value="26"/><Setter Property="Height" Value="26"/><Setter Property="MinHeight" Value="0"/>
  <Setter Property="Padding" Value="0"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/>
  <Setter Property="Foreground" Value="{DynamicResource R.Muted}"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource R.ControlHover}"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Foreground" Value="{DynamicResource R.Text}"/></Trigger>
  </Style.Triggers>
</Style>

<!-- An OU of the « Déplacer vers… » tree: an arrow to open it, a folder and its name. The tree items are made in code. -->
<Style x:Key="Tree.Item" TargetType="TreeViewItem">
  <Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
  <Setter Property="Padding" Value="2,3"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="HeaderTemplate">
    <Setter.Value>
      <DataTemplate>
        <StackPanel Orientation="Horizontal">
          <Viewbox Width="15" Height="15" VerticalAlignment="Center">
            <Canvas Width="24" Height="24">
              <Path Data="M3,7 A2,2 0 0 1 5,5 H9 L11,7 H19 A2,2 0 0 1 21,9 V17 A2,2 0 0 1 19,19 H5 A2,2 0 0 1 3,17 Z" Stroke="{DynamicResource R.Muted}"
                    StrokeThickness="2" StrokeLineJoin="Round"/>
            </Canvas>
          </Viewbox>
          <TextBlock Text="{Binding}" Margin="7,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
      </DataTemplate>
    </Setter.Value>
  </Setter>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="TreeViewItem">
        <StackPanel>
          <Border x:Name="Row" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <!-- MinHeight: the app's toggle style would make every row 34 high. -->
              <ToggleButton x:Name="Expander" Focusable="False" ClickMode="Press" MinHeight="0" Padding="0"
                            IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="Transparent" Width="20" Height="20">
                      <Path x:Name="Arrow" Data="M5,3 L9,7 L5,11" Stroke="{DynamicResource R.Muted}" StrokeThickness="1.5" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsChecked" Value="True"><Setter TargetName="Arrow" Property="Data" Value="M3,5 L7,9 L11,5"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Grid.Column="1" ContentSource="Header" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ItemsPresenter x:Name="ItemsHost" Margin="18,0,0,0"/>
        </StackPanel>
        <ControlTemplate.Triggers>
          <Trigger Property="IsExpanded" Value="False"><Setter TargetName="ItemsHost" Property="Visibility" Value="Collapsed"/></Trigger>
          <Trigger Property="HasItems" Value="False"><Setter TargetName="Expander" Property="Visibility" Value="Hidden"/></Trigger>
          <Trigger SourceName="Row" Property="IsMouseOver" Value="True"><Setter TargetName="Row" Property="Background" Value="{DynamicResource R.RowHover}"/></Trigger>
          <Trigger Property="IsSelected" Value="True"><Setter TargetName="Row" Property="Background" Value="{DynamicResource R.Selection}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<!-- A slider over a color gradient (the Background), for the theme editor. -->
<Style x:Key="Slider.Color" TargetType="Slider">
  <Setter Property="Height" Value="22"/>
  <Setter Property="IsMoveToPointEnabled" Value="True"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Slider">
        <Grid Background="Transparent">
          <Border Height="10" CornerRadius="5" Background="{TemplateBinding Background}" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" VerticalAlignment="Center"/>
          <Track x:Name="PART_Track">
            <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton>
            <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton>
            <Track.Thumb>
              <Thumb>
                <Thumb.Template>
                  <ControlTemplate TargetType="Thumb">
                    <Ellipse x:Name="Knob" Width="18" Height="18" Fill="White" Stroke="#59000000" StrokeThickness="1.5"/>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Knob" Property="Stroke" Value="{DynamicResource R.Accent}"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </Thumb.Template>
              </Thumb>
            </Track.Thumb>
          </Track>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="PART_Track" Property="Opacity" Value="0.85"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

</ResourceDictionary>
'@

# Each open window's minimum size at the normal text size, by window, as it was built. ContentMinWidth: the width its
# content was measured to need, in the font and text size shown (Set-WindowContentWidth), when it says so.
$script:BaseMinSize = @{}
$script:ContentMinWidth = @{}

function Get-OfferedFont {
    # The fonts offered that this computer has, by name: installed ones as they are, the others from fonts\. Looked
    # for once.
    if ($null -ne $script:FontFamilies) { return $script:FontFamilies }
    $installed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($family in [System.Windows.Media.Fonts]::SystemFontFamilies) { $null = $installed.Add($family.Source) }
    $shipped = @{}
    if (Test-Path -LiteralPath $script:FontFolder) {
        $folder = [Uri]::new((Join-Path $script:FontFolder ''))
        foreach ($family in [System.Windows.Media.Fonts]::GetFontFamilies($folder)) {
            foreach ($name in $family.FamilyNames.Values) { $shipped[$name] = [System.Windows.Media.FontFamily]::new($folder, "./#$name") }
        }
    }
    $script:FontFamilies = [ordered]@{}
    foreach ($choice in $script:FontChoices.GetEnumerator()) {
        if ($installed.Contains($choice.Value)) { $script:FontFamilies[$choice.Key] = [System.Windows.Media.FontFamily]::new($choice.Value) }
        elseif ($shipped.ContainsKey($choice.Value)) { $script:FontFamilies[$choice.Key] = $shipped[$choice.Value] }
    }
    $script:FontFamilies
}

function Set-UiText {
    # The font and text size chosen, for every window: the font through R.FontFamily, the size through the shared scale.
    # Segoe UI, always there, isn't looked for.
    $resources = [System.Windows.Application]::Current.Resources
    $family = if ($script:Appearance.FontFamily -ne 'Segoe UI') { (Get-OfferedFont)[$script:Appearance.FontFamily] }
    if (-not $family) { $family = [System.Windows.Media.FontFamily]::new('Segoe UI') }
    $resources['R.FontFamily'] = $family
    # Each level takes the font's nearest weight, the lighter one when two are as near: WPF would take the heavier, and a
    # font without semi-bold (JetBrains Mono) would draw Normale and Grasse alike.
    $weights = $script:FontWeights[$script:Appearance.FontWeight]
    $converter = [System.Windows.FontWeightConverter]::new()
    $available = @($family.GetTypefaces() | Where-Object Style -eq 'Normal' | ForEach-Object { $_.Weight.ToOpenTypeWeight() } | Sort-Object -Unique)
    foreach ($level in 'Text', 'Strong', 'Title') {
        $key = if ($level -eq 'Text') { 'R.FontWeight' } else { "R.FontWeight$level" }
        $wanted = ([System.Windows.FontWeight]$converter.ConvertFromString($weights[$level])).ToOpenTypeWeight()
        $nearest = $available | Sort-Object { [Math]::Abs($_ - $wanted) }, { $_ } | Select-Object -First 1
        $resources[$key] = [System.Windows.FontWeight]::FromOpenTypeWeight($(if ($nearest) { $nearest } else { $wanted }))
    }
    $script:UiScale.ScaleX = $script:Appearance.TextScale
    $script:UiScale.ScaleY = $script:Appearance.TextScale
    foreach ($window in @($script:BaseMinSize.Keys)) { Set-WindowMinSize $window }
    foreach ($window in @($script:WindowChromes.Keys)) { Update-WindowCaption $window }
    Set-TextCache
}

function Set-TextCache {
    # Over Remote Desktop, WPF draws in software and redraws only what changed. Text that doesn't fall on a whole pixel
    # (Inter, Bahnschrift, Verdana, Tahoma: Segoe UI happens to) then comes out half a pixel higher or lower from one
    # key to the next, and the text being typed jumps (#313). Drawn into a bitmap of their own (R.TextCache, the text
    # boxes' and password boxes'), at the text size and the screen's scale so it stays as sharp, it comes out the same
    # each time. Only then: the graphics card, which doesn't do it, keeps drawing text as it does. Checked again as the
    # main window is activated (Register-ThemeFollow), since a Repère started at the desk can be reached over Remote
    # Desktop later.
    $software = ([System.Windows.Media.RenderCapability]::Tier -shr 16) -eq 0 -or [System.Windows.SystemParameters]::IsRemoteSession -or
        [System.Windows.Media.RenderOptions]::ProcessRenderMode -eq 'SoftwareOnly'
    $dpi = 1.0
    $main = [System.Windows.Application]::Current.MainWindow
    if ($main -and [System.Windows.PresentationSource]::FromVisual($main)) { $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($main).DpiScaleY }
    $scale = $script:Appearance.TextScale * $dpi
    $key = if ($software) { "$scale" } else { '' }
    if ($key -eq $script:TextCacheKey) { return }
    $script:TextCacheKey = $key
    $cache = $null
    if ($software) {
        $cache = [System.Windows.Media.BitmapCache]::new($scale)
        $cache.SnapsToDevicePixels = $true
        $cache.Freeze()
    }
    [System.Windows.Application]::Current.Resources['R.TextCache'] = $cache
}

function Set-UiDensity {
    # The density chosen, for every window: the R.* sizes the shared styles and the pages take their heights, vertical
    # paddings and gaps from. The text keeps the size Set-UiText gives it.
    $resources = [System.Windows.Application]::Current.Resources
    $density = $script:Densities[$script:Appearance.Density]
    $resources['R.RowHeight'] = [double]$density.Row
    $resources['R.HeaderHeight'] = [double]$density.Header
    $resources['R.BarHeight'] = [double]$density.Bar
    $resources['R.ControlHeight'] = [double]$density.Control
    $resources['R.ButtonPadding'] = [System.Windows.Thickness]::new(12, $density.Button, 12, $density.Button)
    $resources['R.ItemPadding'] = [System.Windows.Thickness]::new(10, $density.Item, 10, $density.Item)
    $actionGap, $searchGap, $resultsGap, $gridGap = $density.Gaps
    $resources['R.ActionRowMargin'] = [System.Windows.Thickness]::new(16, $actionGap, 16, 0)
    $resources['R.SearchRowMargin'] = [System.Windows.Thickness]::new(16, $searchGap, 16, 0)
    $resources['R.ResultsBarMargin'] = [System.Windows.Thickness]::new(16, $resultsGap, 16, $gridGap)
    $resources['R.StatusPadding'] = [System.Windows.Thickness]::new(16, $density.Status, 16, $density.Status)
}

function Set-WindowMinSize($Window) {
    # A larger text needs a larger window: its minimum size grows with it (within the screen), which widens it when it's
    # narrower, so the action bar or a dialog's buttons aren't cut off. A wider font too: the width its content was
    # measured to need, when it's more.
    $base = $script:BaseMinSize[$Window]
    if (-not $base) { return }
    $area = [System.Windows.SystemParameters]::WorkArea
    $width = $base.Width * $script:Appearance.TextScale
    if ($script:ContentMinWidth.ContainsKey($Window)) { $width = [Math]::Max($width, $script:ContentMinWidth[$Window]) }
    $Window.MinWidth = [Math]::Min($width, $area.Width)
    $Window.MinHeight = [Math]::Min($base.Height * $script:Appearance.TextScale, $area.Height)
}

function Set-WindowContentWidth($Window, [double]$Width) {
    # The width a window's content needs, as measured in the font and text size shown (the main window's action bar,
    # Update-ActionLabel): its minimum width is at least that.
    if ($script:ContentMinWidth[$Window] -eq $Width) { return }
    $script:ContentMinWidth[$Window] = $Width
    Set-WindowMinSize $Window
}

function Get-WindowPlacement($Saved, [System.Windows.Rect]$Area, [double]$Width, [double]$Height, [double]$MinWidth, [double]$MinHeight) {
    # The main window's size and place as it opens: always centered on $Area, the work area of the screen Repère was
    # launched on (Get-CursorWorkArea), wherever it was closed. Its size as saved (fenetre.json), or $Width by $Height
    # without a usable one; at least its minimum size, at most $Area's. Maximized if it was closed maximized.
    $size = @{ Width = $Width; Height = $Height }
    if ($Saved) {
        $Saved = $Saved | Select-Object Width, Height, Maximized
        $read = @{}
        foreach ($name in 'Width', 'Height') {
            $value = 0.0
            if ([double]::TryParse("$($Saved.$name)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and
                -not [double]::IsNaN($value) -and -not [double]::IsInfinity($value) -and $value -gt 0) { $read[$name] = $value }
        }
        if ($read.Count -eq 2) { $size = $read }
    }
    $placement = @{
        Width = [Math]::Max($MinWidth, [Math]::Min($size.Width, $Area.Width))
        Height = [Math]::Max($MinHeight, [Math]::Min($size.Height, $Area.Height))
        Maximized = [bool]($Saved -and $Saved.Maximized -eq $true)
    }
    $placement.Left = $Area.Left + ($Area.Width - $placement.Width) / 2
    $placement.Top = $Area.Top + ($Area.Height - $placement.Height) / 2
    $placement
}

#region Title bar

# Each window draws its own title bar, in the theme's colors, instead of Windows' (Set-WindowChrome): by window, its
# WindowChrome, the part of its content that serves as title bar, and its buttons.
$script:WindowChromes = @{}
$script:MaximizedPadding = 4

# A title bar for a window without a header of its own: its icon, its title, then its buttons.
$script:TitleBarXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Height="32">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel x:Name="title_caption" Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
    <Image x:Name="title_icon" Width="16" Height="16" Margin="0,0,10,0"/>
    <TextBlock x:Name="title_text" FontSize="12" Foreground="{DynamicResource R.Muted}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
  </StackPanel>
  <StackPanel x:Name="caption_buttons" Grid.Column="1" Orientation="Horizontal"/>
</Grid>
'@

function Set-WindowChrome {
    # Replaces the window's title bar with its own: $TitleBar, the header at the top of its content (the main window,
    # Caractéristiques, Clés BitLocker), its buttons added to $ButtonHost; without one, a slim title bar is added above
    # the content. Dragging it moves the window, a double-click maximizes it, a right-click opens the window menu, and
    # the edges still resize it. Call once its content and ResizeMode are set.
    param(
        [Parameter(Mandatory)] [System.Windows.Window]$Window,
        [System.Windows.FrameworkElement]$TitleBar,
        [System.Windows.Controls.Panel]$ButtonHost
    )
    $caption = $null
    if (-not $TitleBar) {
        $TitleBar = [System.Windows.Markup.XamlReader]::Parse($script:TitleBarXaml)
        $ButtonHost = $TitleBar.FindName('caption_buttons')
        $caption = $TitleBar.FindName('title_caption')
        $icon = $TitleBar.FindName('title_icon')
        if ($Window.Icon) { $icon.Source = $Window.Icon } else { $icon.Visibility = 'Collapsed' }
        $title = [System.Windows.Data.Binding]::new('Title')
        $title.Source = $Window
        $null = $TitleBar.FindName('title_text').SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $title)
        $content = $Window.Content
        $Window.Content = $null
        $dock = [System.Windows.Controls.DockPanel]::new()
        [System.Windows.Controls.DockPanel]::SetDock($TitleBar, 'Top')
        $null = $dock.Children.Add($TitleBar)
        $null = $dock.Children.Add($content)
        $Window.Content = $dock
    }
    # The buttons: Réduire for a window in the taskbar (a dialog reduced on its own would leave the main window blocked),
    # Agrandir when it can be resized, and Fermer.
    $resizable = $Window.ResizeMode -in 'CanResize', 'CanResizeWithGrip'
    $buttons = [ordered]@{}
    if ($Window.ResizeMode -ne 'NoResize' -and $Window.ShowInTaskbar) { $buttons.caption_minimize = @{ Glyph = 0xE921; Tip = (Tr 'Réduire') } }
    if ($resizable) { $buttons.caption_maximize = @{ Glyph = 0xE922; Tip = (Tr 'Agrandir') } }
    $buttons.caption_close = @{ Glyph = 0xE8BB; Tip = (Tr 'Fermer') }
    $maximize = $null
    foreach ($name in $buttons.Keys) {
        $button = [System.Windows.Controls.Button]::new()
        $button.Name = $name
        $button.Content = [string][char]$buttons[$name].Glyph
        $button.ToolTip = $buttons[$name].Tip
        [System.Windows.Automation.AutomationProperties]::SetName($button, $buttons[$name].Tip)
        $button.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, $(if ($name -eq 'caption_close') { 'Btn.CaptionClose' } else { 'Btn.Caption' }))
        $button.Add_Click({
            param($control)
            $window = [System.Windows.Window]::GetWindow($control)
            switch ($control.Name) {
                'caption_minimize' { [System.Windows.SystemCommands]::MinimizeWindow($window) }
                'caption_maximize' {
                    if ($window.WindowState -eq 'Maximized') { [System.Windows.SystemCommands]::RestoreWindow($window) }
                    else { [System.Windows.SystemCommands]::MaximizeWindow($window) }
                }
                'caption_close' { [System.Windows.SystemCommands]::CloseWindow($window) }
            }
        })
        $null = $ButtonHost.Children.Add($button)
        if ($name -eq 'caption_maximize') { $maximize = $button }
    }
    # What's clickable in the title bar stays so; the rest of it moves the window.
    $clickable = {
        param($element)
        if ($element -is [System.Windows.Controls.Control]) { [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($element, $true) }
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($element)) {
            if ($child -is [System.Windows.DependencyObject]) { & $clickable $child }
        }
    }
    & $clickable $TitleBar

    $chrome = [System.Windows.Shell.WindowChrome]::new()
    $chrome.CaptionHeight = 32
    $chrome.CornerRadius = [System.Windows.CornerRadius]::new(0)
    $chrome.GlassFrameThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $chrome.UseAeroCaptionButtons = $false
    $chrome.ResizeBorderThickness = if ($resizable) { [System.Windows.SystemParameters]::WindowResizeBorderThickness } else { [System.Windows.Thickness]::new(0) }
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($Window, $chrome)
    $script:WindowChromes[$Window] = @{ Chrome = $chrome; TitleBar = $TitleBar; Buttons = $ButtonHost; Caption = $caption; Maximize = $maximize }

    $TitleBar.Add_SizeChanged({ param($bar) Update-WindowCaption ([System.Windows.Window]::GetWindow($bar)) })
    $Window.Add_StateChanged({ param($window) Update-WindowCaption $window })
    # An inactive window's title bar fades, as Windows does.
    $Window.Add_Activated({ param($window) Set-WindowCaptionFade $window $false })
    $Window.Add_Deactivated({ param($window) Set-WindowCaptionFade $window $true })
    $Window.Add_Closed({ param($window) $script:WindowChromes.Remove($window) })
    # A window sized to its content counts Windows' own title bar and frame the first time: measured again once shown,
    # it loses that room (which would stay black, bottom and right).
    if ($Window.SizeToContent -ne 'Manual') {
        $Window.Add_ContentRendered({
            param($window)
            $sizing = $window.SizeToContent
            $window.SizeToContent = 'Manual'
            $window.SizeToContent = $sizing
        })
    }
    # A window opened over another (every one but the main window, which opens where it was closed) stays within the
    # work area of its screen, as it's placed, before it's drawn. WPF already keeps a window centered over its owner on
    # the owner's screen, but neither shrinks one taller than that screen nor checks a place set by hand.
    $Window.Add_SourceInitialized({ param($window) if ($window.Owner) { Set-WindowInWorkArea $window } })
    Update-WindowCaption $Window
}

#region Screens

# Whether System.Windows.Forms is loaded, for its screens (Get-ScreenWorkArea): the first time it's needed.
$script:FormsScreen = $false

function Get-ScreenWorkArea([System.Windows.Rect]$Rect = [System.Windows.Rect]::Empty) {
    # The work area (the screen without its taskbar, wherever that is) of the screen that holds most of $Rect, or the
    # nearest one, as Windows picks a window's screen: in WPF's units, as a window's Left, Top, Width and Height.
    # SystemParameters.WorkArea is only the main screen's. Without $Rect, or before a window has a place: the main
    # screen's. Repère runs aware of the system's DPI (pwsh), not of each screen's: one scale for every screen.
    $main = [System.Windows.SystemParameters]::WorkArea
    if ($Rect.IsEmpty -or [double]::IsNaN($Rect.X) -or [double]::IsNaN($Rect.Y) -or [double]::IsNaN($Rect.Width) -or [double]::IsNaN($Rect.Height)) { return $main }
    if (-not $script:FormsScreen) {
        Add-Type -AssemblyName System.Windows.Forms
        $script:FormsScreen = $true
    }
    $scale = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / [System.Windows.SystemParameters]::PrimaryScreenWidth
    $pixels = [System.Drawing.Rectangle]::new([int]($Rect.X * $scale), [int]($Rect.Y * $scale),
                                              [Math]::Max(1, [int]($Rect.Width * $scale)), [Math]::Max(1, [int]($Rect.Height * $scale)))
    $area = [System.Windows.Forms.Screen]::FromRectangle($pixels).WorkingArea
    [System.Windows.Rect]::new($area.X / $scale, $area.Y / $scale, $area.Width / $scale, $area.Height / $scale)
}

function Get-CursorWorkArea([int[]]$Pixel) {
    # The work area of the screen under the mouse pointer, in WPF's units, for the main window to open centered on: the
    # pointer at $Pixel, where it was as Repère was launched (Get-RepereLaunchCursor, in pixels), or where it is now.
    if (-not $script:FormsScreen) {
        Add-Type -AssemblyName System.Windows.Forms
        $script:FormsScreen = $true
    }
    $point = if ($Pixel -and $Pixel.Count -eq 2) { [System.Drawing.Point]::new($Pixel[0], $Pixel[1]) } else { [System.Windows.Forms.Cursor]::Position }
    $scale = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / [System.Windows.SystemParameters]::PrimaryScreenWidth
    $area = [System.Windows.Forms.Screen]::FromPoint($point).WorkingArea
    [System.Windows.Rect]::new($area.X / $scale, $area.Y / $scale, $area.Width / $scale, $area.Height / $scale)
}

function Get-RectInArea([System.Windows.Rect]$Rect, [System.Windows.Rect]$Area) {
    # $Rect moved into $Area, the least it can be: up or left until its bottom and right are in, then down or right
    # until its top and left are, so its title bar can always be reached. Larger than $Area, it's shrunk to it.
    $width = [Math]::Min($Rect.Width, $Area.Width)
    $height = [Math]::Min($Rect.Height, $Area.Height)
    $left = [Math]::Max($Area.Left, [Math]::Min($Rect.Left, $Area.Right - $width))
    $top = [Math]::Max($Area.Top, [Math]::Min($Rect.Top, $Area.Bottom - $height))
    [System.Windows.Rect]::new($left, $top, $width, $height)
}

function Set-WindowInWorkArea([System.Windows.Window]$Window) {
    # A window kept within the work area of the screen it's on (Get-ScreenWorkArea), above or beside the taskbar: moved
    # first, then shrunk if it's still too large, its minimum size with it (a large text on a small screen). A window
    # that sizes itself to its content isn't shrunk: Update-WindowHeightCap keeps it shorter than the screen. Maximized
    # or minimized, Windows places it.
    if ($Window.WindowState -ne 'Normal') { return }
    $width = if ($Window.ActualWidth -gt 0) { $Window.ActualWidth } else { $Window.Width }
    $height = if ($Window.ActualHeight -gt 0) { $Window.ActualHeight } else { $Window.Height }
    if ([double]::IsNaN($Window.Left) -or [double]::IsNaN($Window.Top) -or [double]::IsNaN($width) -or [double]::IsNaN($height)) { return }
    $place = [System.Windows.Rect]::new($Window.Left, $Window.Top, $width, $height)
    $fit = Get-RectInArea $place (Get-ScreenWorkArea $place)
    if ($fit.Width -lt $width -and $Window.SizeToContent -notin 'Width', 'WidthAndHeight') {
        $Window.MinWidth = [Math]::Min($Window.MinWidth, $fit.Width)
        $Window.Width = $fit.Width
    }
    if ($fit.Height -lt $height -and $Window.SizeToContent -notin 'Height', 'WidthAndHeight') {
        $Window.MinHeight = [Math]::Min($Window.MinHeight, $fit.Height)
        $Window.Height = $fit.Height
    }
    if ($fit.Left -ne $Window.Left) { $Window.Left = $fit.Left }
    if ($fit.Top -ne $Window.Top) { $Window.Top = $fit.Top }
}

#endregion

function Update-WindowHeightCap([System.Windows.Window]$Window) {
    # While the window sizes itself to its content, it stays shorter than its screen, on it, and its content scrolls.
    # Sized by hand or maximized, the content has all the window's room: a fixed MaxHeight inside the window would leave
    # a band above and below it, WPF centring an element in a larger slot.
    $place = if ($Window.IsLoaded) { [System.Windows.Rect]::new($Window.Left, $Window.Top, $Window.ActualWidth, $Window.ActualHeight) } else { [System.Windows.Rect]::Empty }
    $area = Get-ScreenWorkArea $place
    $sizing = $Window.WindowState -eq 'Normal' -and $Window.SizeToContent -ne 'Manual'
    $Window.Content.MaxHeight = if ($sizing) { ($area.Height - 40) / $script:UiScale.ScaleY } else { [double]::PositiveInfinity }
    # Grown past the bottom of its screen: up.
    if ($sizing -and $Window.IsLoaded) { Set-WindowInWorkArea $Window }
}

function Register-WindowHeightCap([System.Windows.Window]$Window) {
    # A window with SizeToContent whose content scrolls: Update-WindowHeightCap, now and as its size or state changes.
    Update-WindowHeightCap $Window
    $Window.Add_SizeChanged({ param($window) Update-WindowHeightCap $window })
    $Window.Add_StateChanged({ param($window) Update-WindowHeightCap $window })
}

function Register-OwnerFocus([System.Windows.Window]$Window) {
    # A window that leaves its owner usable (Propriétés, Caractéristiques, Comparer les groupes, Paramètres): when it
    # closes, or hides, while it's the active window, Windows gives the focus to the next window in its own order, which
    # can be another application's: Repère then goes behind it, as if minimized. The window it was opened from is
    # activated first: its Tag's ReturnTo (a group's Propriétés opened from Comparer les groupes is owned by the main
    # window, so it outlives the comparison), while that's shown, otherwise its owner. Not while Repère closes.
    $Window.Add_Closing({
        param($window)
        if (-not $window.IsActive -or $script:Settings.Exiting) { return }
        $back = if ($window.Tag -is [hashtable] -and $window.Tag['ReturnTo'] -is [System.Windows.Window]) { $window.Tag['ReturnTo'] }
        if (-not $back -or -not $back.IsVisible) { $back = $window.Owner }
        if ($back -and $back.IsVisible -and $back.WindowState -ne 'Minimized') { $null = $back.Activate() }
    })
}

function Update-WindowCaption($Window) {
    # The part that moves the window is as tall as the title bar, at the text size chosen (which scales the content).
    # Maximized, Windows puts the window's edges off the screen: the content keeps clear of them, and Agrandir becomes
    # Restaurer.
    $entry = $script:WindowChromes[$Window]
    if (-not $entry) { return }
    $height = if ($entry.TitleBar.ActualHeight) { $entry.TitleBar.ActualHeight } elseif ($entry.TitleBar.Height -gt 0) { $entry.TitleBar.Height } else { 32 }
    $entry.Chrome.CaptionHeight = $height * $script:UiScale.ScaleY
    $maximized = $Window.WindowState -eq 'Maximized'
    if ($Window.Content -is [System.Windows.FrameworkElement]) {
        # The edge Windows hides: its resize border and the padding around it (4 pixels at 100 %).
        $edge = [System.Windows.SystemParameters]::WindowResizeBorderThickness.Left + $script:MaximizedPadding
        $Window.Content.Margin = [System.Windows.Thickness]::new($(if ($maximized) { $edge } else { 0 }))
    }
    if ($entry.Maximize) {
        $entry.Maximize.Content = [string][char]$(if ($maximized) { 0xE923 } else { 0xE922 })
        $entry.Maximize.ToolTip = if ($maximized) { Tr 'Restaurer' } else { Tr 'Agrandir' }
        [System.Windows.Automation.AutomationProperties]::SetName($entry.Maximize, $entry.Maximize.ToolTip)
    }
}

function Set-WindowCaptionFade($Window, [bool]$Faded) {
    $entry = $script:WindowChromes[$Window]
    if (-not $entry) { return }
    $opacity = if ($Faded) { 0.55 } else { 1.0 }
    $entry.Buttons.Opacity = $opacity
    if ($entry.Caption) { $entry.Caption.Opacity = $opacity }
}

#endregion

function Register-UiText {
    # Every window, right-click menu and tooltip takes the chosen font and weight, and its content the shared scale, as it opens:
    # registered once for the whole application, so windows built anywhere follow. Text set to another font on purpose
    # (Consolas for BitLocker keys and LAPS passwords) keeps it.
    $follow = {
        param($element)
        $element.SetResourceReference([System.Windows.Controls.Control]::FontFamilyProperty, 'R.FontFamily')
        $element.SetResourceReference([System.Windows.Controls.Control]::FontWeightProperty, 'R.FontWeight')
        $content = if ($element -is [System.Windows.Window]) { $element.Content } else { $element }
        if ($content -is [System.Windows.FrameworkElement]) { $content.LayoutTransform = $script:UiScale }
        # A menu and its submenus on whole pixels: an icon at a fractional place could come out a pixel taller on one
        # redraw than on the next, as the pointer went over the items (#275). Not a ContextMenu style: one in the
        # application's resources would replace Fluent's.
        if ($element -is [System.Windows.Controls.ContextMenu]) { $element.UseLayoutRounding = $true }
        if ($element -is [System.Windows.Window] -and -not $script:BaseMinSize.ContainsKey($element)) {
            $script:BaseMinSize[$element] = @{ Width = $element.MinWidth; Height = $element.MinHeight }
            Set-WindowMinSize $element
            $element.Add_Closed({ param($window) $script:BaseMinSize.Remove($window); $script:ContentMinWidth.Remove($window) })
        }
    }
    [System.Windows.EventManager]::RegisterClassHandler([System.Windows.Window], [System.Windows.FrameworkElement]::LoadedEvent, [System.Windows.RoutedEventHandler]$follow)
    [System.Windows.EventManager]::RegisterClassHandler([System.Windows.Controls.ContextMenu], [System.Windows.Controls.ContextMenu]::OpenedEvent, [System.Windows.RoutedEventHandler]$follow)
    [System.Windows.EventManager]::RegisterClassHandler([System.Windows.Controls.ToolTip], [System.Windows.Controls.ToolTip]::OpenedEvent, [System.Windows.RoutedEventHandler]$follow)
}

function Initialize-Theme {
    # Creates the application (one per process), gives it the shared styles, then the saved appearance's colors, font,
    # text size and density. Call once, before any window.
    Read-Appearance
    $app = [System.Windows.Application]::Current
    if (-not $app) { $app = [System.Windows.Application]::new() }
    $app.Resources = [System.Windows.Markup.XamlReader]::Parse($script:SharedResources)
    # What a disabled text box shows in its place (the TextBox style), in this run's language: SharedResources isn't
    # translated.
    Set-UiText
    Set-UiDensity
    Register-UiText
    try {
        Update-ThemeResource
    }
    catch {
        # A hand-edited settings file shouldn't keep Repère from starting.
        Write-Host "Thème ignoré : $_"
        $script:Appearance.Scheme = 'Repere'
        Update-ThemeResource
    }
}

#endregion

#region Apparence menu

# The theme editor: the theme being edited (Id, $null for a new one), its background tint, the mode its preview shows,
# and whether the color controls are being updated from code (so their change events don't loop).
$script:Editor = @{ Id = $null; Tint = 'Teinté'; PreviewVariant = 'Light'; Updating = $false; Colors = @{ Light = @{}; Dark = @{} } }
# The mode toggles of Paramètres › Apparence, and the mode each one saves.
$script:ThemeModes = [ordered]@{ theme_system = 'Système'; theme_light = 'Clair'; theme_dark = 'Sombre' }
# The list of themes: the variant its colors were drawn for, and whether it's being filled from code (its selection
# then picks nothing).
$script:ThemeList = @{ Variant = $null; Updating = $false }
# The theme tried while the list is open: the one to try once the highlight settles (Key), the one showing (Shown, $null
# when it's the chosen one) and the timer between the two, so that running down the list doesn't recolor every row.
$script:ThemePreview = @{ Key = $null; Shown = $null; Timer = $null }

function New-Color([string]$Hex, [byte]$Alpha = 255) {
    $rgb = ConvertFrom-HexColor $Hex
    [System.Windows.Media.Color]::FromArgb($Alpha, $rgb[0], $rgb[1], $rgb[2])
}

function New-ThemeListItem([string]$Key, $Spec, [string]$Variant) {
    # A row of the list of themes: its name, and its background and accent in this mode, as hex for the list's bindings.
    $c = Get-ThemeBrush $Variant $Spec
    [pscustomobject]@{ Key = $Key; Name = $Spec.Name; Border = $c['R.BorderStrong']; Bg = $c['R.Bg']; Accent = $c['R.Accent'] }
}

function Update-ThemeList {
    # Fills the list: the presets, then the user's themes under their heading, each in the mode in use. The theme chosen
    # is selected by Update-AppearancePanel.
    $list = $script:AppearanceRoot.FindName('theme_list')
    $variant = if ($script:CurrentVariant -eq 'Dark') { 'Dark' } else { 'Light' }
    $script:ThemeList.Variant = $script:CurrentVariant
    $script:ThemeList.Updating = $true
    try {
        $list.Items.Clear()
        foreach ($key in $script:Presets.Keys) { $list.Items.Add((New-ThemeListItem $key $script:Presets[$key] $variant)) | Out-Null }
        if ($script:Appearance.CustomThemes.Count) {
            $heading = [System.Windows.Controls.ComboBoxItem]::new()
            $heading.Content = [System.Windows.Markup.XamlReader]::Parse("<StackPanel xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`"><Border Height=`"1`" Margin=`"-8,0,-8,6`" Background=`"{DynamicResource R.Border}`"/><TextBlock Text=`"$(ConvertTo-XamlValue (Tr 'Mes thèmes'))`" FontSize=`"12`" Foreground=`"{DynamicResource R.Muted}`"/></StackPanel>")
            $heading.IsEnabled = $false
            [System.Windows.Automation.AutomationProperties]::SetName($heading, (Tr 'Mes thèmes'))
            $list.Items.Add($heading) | Out-Null
        }
        foreach ($theme in $script:Appearance.CustomThemes) { $list.Items.Add((New-ThemeListItem $theme.Id $theme $variant)) | Out-Null }
    }
    finally { $script:ThemeList.Updating = $false }
}

function Get-PreviewXaml {
    # A small mock-up of the window, colored by Update-EditorPreview in the mode it shows.
    @"
<Border x:Name="pv_bg" CornerRadius="8" Padding="10" BorderThickness="1" Margin="0,0,0,10">
  <StackPanel>
    <Border x:Name="pv_surface" CornerRadius="6" Padding="8,6" BorderThickness="1">
      <StackPanel>
        <TextBlock x:Name="pv_text" Text="ORD-01   Bureau d'accueil" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}"/>
        <Border x:Name="pv_row" CornerRadius="3" Padding="4,2" Margin="-4,4,-4,0"><TextBlock x:Name="pv_rowtext" Text="ORD-02   Salle de réunion" FontSize="11.5"/></Border>
        <TextBlock x:Name="pv_muted" Text="12 ordinateurs en 64 ms" FontSize="11" Margin="0,4,0,0"/>
      </StackPanel>
    </Border>
    <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
      <Border x:Name="pv_button" CornerRadius="5" Padding="10,4"><TextBlock x:Name="pv_buttontext" Text="Rechercher" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}"/></Border>
      <Border x:Name="pv_control" CornerRadius="5" Padding="10,4" Margin="6,0,0,0" BorderThickness="1"><TextBlock x:Name="pv_controltext" Text="Filtres" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}"/></Border>
    </StackPanel>
  </StackPanel>
</Border>
"@
}

function Get-HexBoxXaml([string]$Name, [string]$ReadAs, [string]$ToolTip) {
    # A color's box, inside a Field border: its # is drawn before it, so only the six digits are typed (Repair-HexBox
    # drops a # typed or pasted).
    $tip = if ($ToolTip) { " ToolTip=`"$ToolTip`"" }
    "<Grid><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition Width=`"*`"/></Grid.ColumnDefinitions>" +
    "<TextBlock Text=`"#`" Foreground=`"{DynamicResource R.Muted}`" Margin=`"8,0,0,0`" VerticalAlignment=`"Center`"/>" +
    "<TextBox x:Name=`"$Name`" Grid.Column=`"1`" Style=`"{StaticResource Text.Bare}`" Padding=`"2,0,4,0`" VerticalAlignment=`"Center`" AutomationProperties.Name=`"$ReadAs`"$tip/></Grid>"
}

function Get-PickXaml($Choices) {
    # A row of toggles on their track: each choice its name, its text and, if any, its tooltip.
    $toggles = foreach ($choice in $Choices) {
        $tip = if ($choice.Count -gt 2) { " ToolTip=`"$($choice[2])`"" }
        "<ToggleButton x:Name=`"$($choice[0])`" Style=`"{StaticResource Toggle.Pick}`" Content=`"$($choice[1])`"$tip/>"
    }
    "<Border Style=`"{StaticResource Pick.Track}`"><UniformGrid Rows=`"1`">$($toggles -join '')</UniformGrid></Border>"
}

function Get-SettingRowXaml([string]$Title, [string]$Note, [string]$Control, [string]$NoteName, [switch]$First) {
    # A setting of Paramètres › Apparence, in a card: its name and what it does on the left, its control on the right.
    # -NoteName: the note is set in code. A row without a note is its name alone, and a note set to '' in code hides.
    # Rows after the first have a line above them.
    $line = if (-not $First) { '<Border Height="1" Background="{DynamicResource R.Border}"/>' }
    $name = if ($NoteName) { " x:Name=`"$NoteName`"" }
    $text = if ($Note) { " Text=`"$Note`"" }
    $noteXaml = if ($Note -or $NoteName) {
        @"
    <TextBlock$name$text FontSize="12" TextWrapping="Wrap">
      <TextBlock.Style>
        <Style TargetType="TextBlock" BasedOn="{StaticResource Txt.Muted}">
          <Style.Triggers><Trigger Property="Text" Value=""><Setter Property="Visibility" Value="Collapsed"/></Trigger></Style.Triggers>
        </Style>
      </TextBlock.Style>
    </TextBlock>
"@
    }
    @"
$line<Grid MinHeight="56" Margin="16,6">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="24"/><ColumnDefinition Width="340"/></Grid.ColumnDefinitions>
  <StackPanel VerticalAlignment="Center">
    <TextBlock Text="$Title" FontWeight="{DynamicResource R.FontWeightStrong}"/>
$noteXaml
  </StackPanel>
  <Border Grid.Column="2" VerticalAlignment="Center">$Control</Border>
</Grid>
"@
}

function Get-AppearanceXaml {
    # Paramètres › Apparence: the settings, in rows grouped in cards, and the theme editor, one page shown at a time.
    $picks = foreach ($key in $script:Presets.Keys) {
        $preset = $script:Presets[$key]
        "<Button x:Name=`"editor_pick_$key`" Style=`"{StaticResource Btn.Swatch}`" ToolTip=`"$($preset.Name)`" AutomationProperties.Name=`"$($preset.Name)`"><Border Width=`"20`" Height=`"20`" CornerRadius=`"10`" Background=`"$($preset.Accent)`"/></Button>"
    }
    # Couleurs: a row per color a theme can set, by group, its light and dark box side by side. An empty box shows, in
    # grey, the color it gets from the accent and the Fond (Update-EditorColor).
    $colorRows = foreach ($key in $script:ThemeColors.Keys) {
        $group = @($script:ThemeColorGroups.Keys | Where-Object { $script:ThemeColorGroups[$_][0] -eq $key })
        if ($group) { "<TextBlock Style=`"{StaticResource Txt.Faint}`" FontSize=`"12`" FontWeight=`"{DynamicResource R.FontWeightStrong}`" Text=`"$($group[0])`" Margin=`"0,10,0,0`"/>" }
        $label = $script:ThemeColors[$key]
        $cells = foreach ($variant in @(@('light', (Tr 'clair'), 1), @('dark', (Tr 'sombre'), 3))) {
            "<Grid Grid.Column=`"$($variant[2])`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition Width=`"*`"/></Grid.ColumnDefinitions>" +
            "<Button x:Name=`"pick_${key}_$($variant[0])`" Style=`"{StaticResource Btn.Swatch}`" Padding=`"0`" Margin=`"0`" VerticalAlignment=`"Center`" ToolTip=`"Choisir la couleur`" AutomationProperties.Name=`"Choisir la couleur`">" +
            "<Border x:Name=`"editor_swatch_${key}_$($variant[0])`" Width=`"22`" Height=`"22`" CornerRadius=`"5`" BorderBrush=`"{DynamicResource R.BorderStrong}`" BorderThickness=`"1`"/></Button>" +
            "<Border Grid.Column=`"1`" Style=`"{StaticResource Field}`" Margin=`"6,0,0,0`" Height=`"28`">$(Get-HexBoxXaml "editor_color_${key}_$($variant[0])" "$label, $($variant[1])" 'Vide : couleur automatique')</Border></Grid>"
        }
        "<Grid Margin=`"0,4,0,0`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"*`"/><ColumnDefinition Width=`"118`"/><ColumnDefinition Width=`"8`"/><ColumnDefinition Width=`"118`"/></Grid.ColumnDefinitions>" +
        "<TextBlock Text=`"$label`" VerticalAlignment=`"Center`" TextTrimming=`"CharacterEllipsis`" ToolTip=`"$label`"/>$($cells -join '')</Grid>"
    }
    $sliders = foreach ($slider in @(@('hue', (Tr 'Teinte'), 360), @('saturation', 'Saturation', 100), @('lightness', (Tr 'Luminosité'), 100))) {
        "<Grid Margin=`"0,4,0,0`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"80`"/><ColumnDefinition Width=`"*`"/></Grid.ColumnDefinitions><TextBlock Style=`"{StaticResource Txt.Label}`" Text=`"$($slider[1])`" VerticalAlignment=`"Center`"/><Slider x:Name=`"editor_$($slider[0])`" Grid.Column=`"1`" Style=`"{StaticResource Slider.Color}`" Minimum=`"0`" Maximum=`"$($slider[2])`" SmallChange=`"1`" LargeChange=`"10`" AutomationProperties.Name=`"$($slider[1])`"/></Grid>"
    }
    # The list of themes: each one's background and accent in the mode chosen, then its name. Going through it open tries
    # each theme (Show-ThemePreview); only picking one keeps it. Typing a name's first letters goes to it.
    $themeList = @"
<ComboBox x:Name="theme_list" Height="{DynamicResource R.ControlHeight}" FontFamily="Segoe UI" AutomationProperties.Name="Thème"
          IsTextSearchEnabled="True" TextSearch.TextPath="Name" MaxDropDownHeight="420">
  <ComboBox.ItemContainerStyle>
    <Style TargetType="ComboBoxItem" BasedOn="{StaticResource Combo.Item}">
      <Setter Property="AutomationProperties.Name" Value="{Binding Name}"/>
    </Style>
  </ComboBox.ItemContainerStyle>
  <ComboBox.ItemTemplate>
    <DataTemplate>
      <StackPanel Orientation="Horizontal">
        <Grid Width="27" Height="16" VerticalAlignment="Center">
          <Ellipse Width="16" Height="16" HorizontalAlignment="Left" Fill="{Binding Bg}" Stroke="{Binding Border}"/>
          <Ellipse Width="16" Height="16" HorizontalAlignment="Right" Fill="{Binding Accent}" Stroke="{Binding Border}"/>
        </Grid>
        <TextBlock Text="{Binding Name}" VerticalAlignment="Center" Margin="10,0,0,0"/>
      </StackPanel>
    </DataTemplate>
  </ComboBox.ItemTemplate>
</ComboBox>
"@
    # A theme can always be created. A preset can also be copied into a new theme; one of the user's edited or deleted.
    # For a preset, Créer and Copier take half the row each. For one of the user's, Créer takes its text's width and
    # Modifier and Supprimer share the rest equally (Update-AppearancePanel sets the columns).
    $themeActions = @"
<Grid x:Name="theme_actions">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Button x:Name="create_theme" Content="Créer un thème" ToolTipService.ShowOnDisabled="True"/>
  <Button x:Name="theme_copy" Grid.Column="1" Content="Copier celui-ci" Margin="8,0,0,0" ToolTip="Créer un thème à partir de celui-ci"/>
  <Button x:Name="theme_edit" Grid.Column="1" Content="Modifier" Margin="8,0,0,0" ToolTip="Modifier ce thème"/>
  <Button x:Name="theme_delete" Grid.Column="2" Content="Supprimer" Margin="8,0,0,0" ToolTip="Supprimer ce thème"/>
</Grid>
"@
    # Each font's name, in that font. Typing a name's first letters goes to it.
    $fontList = @"
<ComboBox x:Name="text_font" Height="{DynamicResource R.ControlHeight}" FontFamily="Segoe UI" AutomationProperties.Name="Police"
          IsTextSearchEnabled="True" TextSearch.TextPath="Name" MaxDropDownHeight="420">
  <ComboBox.ItemContainerStyle>
    <Style TargetType="ComboBoxItem" BasedOn="{StaticResource Combo.Item}">
      <Setter Property="AutomationProperties.Name" Value="{Binding Name}"/>
    </Style>
  </ComboBox.ItemContainerStyle>
  <ComboBox.ItemTemplate>
    <DataTemplate><TextBlock Text="{Binding Name}" FontFamily="{Binding Family}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/></DataTemplate>
  </ComboBox.ItemTemplate>
</ComboBox>
"@
    $languageList = "<ComboBox x:Name=`"language_list`" Height=`"{DynamicResource R.ControlHeight}`" FontFamily=`"Segoe UI`" ItemContainerStyle=`"{StaticResource Combo.Item}`" AutomationProperties.Name=`"Langue`"/>"
    Expand-Icon @"
<Grid>
  <!-- All of it in Segoe UI whatever font is chosen: a font that can't be read must not hide the way back. Each list is
       given it too, for its popup. -->
  <StackPanel x:Name="gallery_page" TextElement.FontFamily="Segoe UI">
    <TextBlock Text="Apparence" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>

    <TextBlock Text="Couleurs" FontSize="13" FontWeight="{DynamicResource R.FontWeightStrong}" Foreground="{DynamicResource R.Muted}" Margin="0,14,0,6"/>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        $(Get-SettingRowXaml (Tr 'Mode') '' (Get-PickXaml @(@('theme_system', (Tr 'Selon le système')), @('theme_light', (Tr 'Clair')), @('theme_dark', (Tr 'Sombre')))) -First)
        $(Get-SettingRowXaml (Tr 'Thème') '' $themeList)
        $(Get-SettingRowXaml (Tr 'Mes thèmes') '' $themeActions 'theme_own_note')
      </StackPanel>
    </Border>

    <Grid Margin="0,14,0,6">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock Text="Texte" FontSize="13" FontWeight="{DynamicResource R.FontWeightStrong}" Foreground="{DynamicResource R.Muted}" VerticalAlignment="Bottom"/>
      <!-- Outlined, so it reads as a button beside the heading (#186); disabled while the text is already the default. -->
      <Button x:Name="text_reset" Grid.Column="1" Padding="10,3" MinHeight="0" Content="Par défaut" ToolTip="Segoe UI, taille et épaisseur normales"
              ToolTipService.ShowOnDisabled="True"/>
    </Grid>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        $(Get-SettingRowXaml (Tr 'Police') '' $fontList -First)
        $(Get-SettingRowXaml (Tr 'Taille') (Tr 'Texte et icônes') (Get-PickXaml @(@('text_size_normal', (Tr 'Normale'), '100 %'), @('text_size_large', (Tr 'Grande'), '115 %'), @('text_size_larger', (Tr 'Très grande'), '130 %'))))
        $(Get-SettingRowXaml (Tr 'Épaisseur') '' (Get-PickXaml @(@('text_weight_SemiBold', (Tr 'Normale'), (Tr 'Texte semi-gras, titres et noms en gras')), @('text_weight_Bold', (Tr 'Grasse'), (Tr 'Texte en gras, titres et noms plus gras encore')))))
      </StackPanel>
    </Border>

    <TextBlock Text="Affichage et langue" FontSize="13" FontWeight="{DynamicResource R.FontWeightStrong}" Foreground="{DynamicResource R.Muted}" Margin="0,14,0,6"/>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        $(Get-SettingRowXaml (Tr 'Densité') '' (Get-PickXaml @(@('density_compact', (Tr 'Compacte')), @('density_normal', (Tr 'Normale')), @('density_airy', (Tr 'Aérée')))) 'density_note' -First)
        $(Get-SettingRowXaml (Tr 'Langue') (Tr 'Au prochain lancement') $languageList)
      </StackPanel>
    </Border>
  </StackPanel>

  <Grid x:Name="editor_page" Visibility="Collapsed">
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="20"/><ColumnDefinition Width="230"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.ColumnSpan="3" Orientation="Horizontal" Margin="0,0,0,14">
      <Button x:Name="editor_back" Style="{StaticResource Btn.Mini}" Width="30" Height="30" ToolTip="Retour aux thèmes" AutomationProperties.Name="Retour aux thèmes">{{icon:back:16}}</Button>
      <TextBlock x:Name="editor_title" Text="Nouveau thème" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}" VerticalAlignment="Center" Margin="8,0,0,0"/>
    </StackPanel>

    <StackPanel Grid.Row="1">
      <TextBlock Style="{StaticResource Txt.Label}" Text="Nom" Margin="0,0,0,6"/>
      <TextBox x:Name="editor_name" MaxLength="30" Tag="Mon thème" AutomationProperties.Name="Nom"/>
      <TextBlock Style="{StaticResource Txt.Label}" Text="Couleur d'accent" Margin="0,14,0,6"/>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Button x:Name="pick_accent" Style="{StaticResource Btn.Swatch}" Padding="0" Margin="0" ToolTip="Choisir la couleur" AutomationProperties.Name="Choisir la couleur">
          <Border x:Name="editor_swatch" Width="34" Height="34" CornerRadius="6" BorderBrush="{DynamicResource R.Border}" BorderThickness="1"/>
        </Button>
        <Border Grid.Column="1" Style="{StaticResource Field}" Margin="8,0,0,0" Height="34">$(Get-HexBoxXaml 'editor_accent' "Couleur d'accent")</Border>
      </Grid>
      $($sliders -join '')
      <WrapPanel Margin="76,8,0,0">$($picks -join '')</WrapPanel>
      <!-- How the accent shows in a mode, when not as typed: that mode's own, or adjusted to stand out (Get-ThemeAdvice). -->
      <TextBlock x:Name="editor_accent_note" Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed"/>
      <TextBlock Style="{StaticResource Txt.Label}" Text="Fond" Margin="0,14,0,6"/>
      $(Get-PickXaml @(@('editor_tint_neutre', (Tr 'Neutre'), (Tr 'Gris neutres')), @('editor_tint_teinte', (Tr 'Teinté'), (Tr "Gris teintés de la couleur d'accent")), @('editor_tint_intense', (Tr 'Intense'), (Tr 'Fonds nettement colorés'))))
      <!-- Folded when the editor opens, so that it stays short (and its buttons in view) for an accent alone. -->
      <Button x:Name="editor_colors_toggle" Style="{StaticResource Btn.Ghost}" HorizontalAlignment="Left" Padding="8,3" MinHeight="0" Margin="-8,12,0,0">
        <StackPanel Orientation="Horizontal">{{icon:palette:14}}<TextBlock x:Name="editor_colors_toggle_text" Text="Personnaliser les couleurs" Margin="6,0,0,0"/></StackPanel>
      </Button>
      <StackPanel x:Name="editor_colors" Visibility="Collapsed">
        <Grid Margin="0,8,0,2">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="8"/><ColumnDefinition Width="118"/></Grid.ColumnDefinitions>
          <TextBlock Style="{StaticResource Txt.Label}" Text="Couleurs"/>
          <TextBlock Grid.Column="1" Style="{StaticResource Txt.Faint}" FontSize="12" Text="Clair" Margin="28,0,0,0"/>
          <TextBlock Grid.Column="3" Style="{StaticResource Txt.Faint}" FontSize="12" Text="Sombre" Margin="28,0,0,0"/>
        </Grid>
        $($colorRows -join '')
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"
                   Text="Une case vide suit l'accent et le fond (en gris)."/>
      </StackPanel>
      <!-- Contrast warnings, one per line (Update-EditorColor): they don't stop the theme from being saved. -->
      <Border x:Name="editor_contrast_panel" Visibility="Collapsed" Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,10,0,0">
        <StackPanel>
          <TextBlock Text="Contraste faible" Foreground="{DynamicResource R.WarnText}" FontSize="12" FontWeight="{DynamicResource R.FontWeightStrong}"/>
          <TextBlock x:Name="editor_contrast" Foreground="{DynamicResource R.WarnText}" FontSize="12" TextWrapping="Wrap" LineHeight="18" Margin="0,2,0,0"/>
          <TextBlock Text="Le thème peut quand même être enregistré." Foreground="{DynamicResource R.WarnText}" FontSize="11.5" Opacity="0.8" TextWrapping="Wrap" Margin="0,4,0,0"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="editor_error" Foreground="{DynamicResource R.DangerText}" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed"/>
    </StackPanel>

    <StackPanel Grid.Row="1" Grid.Column="2">
      <TextBlock Style="{StaticResource Txt.Label}" Text="Aperçu" Margin="0,0,0,6"/>
      <!-- One mock-up, of the mode in use at first; a color changed in Couleurs shows it in that color's mode. -->
      $(Get-PickXaml @(@('editor_preview_light', (Tr 'Clair')), @('editor_preview_dark', (Tr 'Sombre'))))
      <Border Height="8"/>
      $(Get-PreviewXaml)
      <TextBlock Style="{StaticResource Txt.Faint}" FontSize="11.5" TextWrapping="Wrap" Text="L'accent est ajusté dans chaque mode pour rester visible."/>
    </StackPanel>

    <Grid Grid.Row="2" Grid.ColumnSpan="3" Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button x:Name="editor_delete" Style="{StaticResource Btn.Danger}" Content="Supprimer" Visibility="Collapsed"/>
      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <Button x:Name="editor_cancel" Content="Annuler" MinWidth="90"/>
        <Button x:Name="editor_save" Style="{StaticResource Btn.Primary}" Content="Enregistrer" MinWidth="110" Margin="8,0,0,0"/>
      </StackPanel>
    </Grid>
  </Grid>

  <!-- The color picker, under the square clicked (the accent's or a color's): saturation across and brightness down,
       the hue below, then the code. It writes in that square's box (Open-ColorPicker). Outside the editor's page, so
       that its keys don't reach the page's (Entrée saves the theme). -->
  <Popup x:Name="color_popup" StaysOpen="False" Placement="Bottom" AllowsTransparency="True" PopupAnimation="Fade" VerticalOffset="4">
    <Border x:Name="picker_panel" Background="{DynamicResource R.Surface}" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,10,10">
      <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="2" Opacity="0.25"/></Border.Effect>
      <StackPanel Width="240">
        <Grid x:Name="picker_area" Height="150" Background="Transparent" Cursor="Cross" AutomationProperties.Name="Saturation et luminosité">
          <!-- The three layers square, rounded once together: each rounded on its own, the hue showed at the corners. -->
          <Grid>
            <Grid.Clip><RectangleGeometry Rect="0,0,240,150" RadiusX="6" RadiusY="6"/></Grid.Clip>
            <Border x:Name="picker_hue_fill"/>
            <Border>
              <Border.Background><LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5"><GradientStop Color="#FFFFFFFF" Offset="0"/><GradientStop Color="#00FFFFFF" Offset="1"/></LinearGradientBrush></Border.Background>
            </Border>
            <Border>
              <Border.Background><LinearGradientBrush StartPoint="0.5,0" EndPoint="0.5,1"><GradientStop Color="#00000000" Offset="0"/><GradientStop Color="#FF000000" Offset="1"/></LinearGradientBrush></Border.Background>
            </Border>
          </Grid>
          <Border CornerRadius="6" BorderBrush="{DynamicResource R.Border}" BorderThickness="1"/>
          <Canvas IsHitTestVisible="False">
            <Ellipse x:Name="picker_thumb" Width="14" Height="14" Stroke="White" StrokeThickness="2">
              <Ellipse.Effect><DropShadowEffect BlurRadius="3" ShadowDepth="0" Opacity="0.6"/></Ellipse.Effect>
            </Ellipse>
          </Canvas>
        </Grid>
        <!-- Every hue, at full saturation and brightness: the square's color at its top right. -->
        <Slider x:Name="picker_hue" Style="{StaticResource Slider.Color}" Minimum="0" Maximum="360" SmallChange="1" LargeChange="10" Margin="0,10,0,0" AutomationProperties.Name="Teinte">
          <Slider.Background>
            <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
              <GradientStop Color="#FF0000" Offset="0"/><GradientStop Color="#FFFF00" Offset="0.1667"/><GradientStop Color="#00FF00" Offset="0.3333"/>
              <GradientStop Color="#00FFFF" Offset="0.5"/><GradientStop Color="#0000FF" Offset="0.6667"/><GradientStop Color="#FF00FF" Offset="0.8333"/>
              <GradientStop Color="#FF0000" Offset="1"/>
            </LinearGradientBrush>
          </Slider.Background>
        </Slider>
        <Grid Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border x:Name="picker_preview" Width="24" Height="24" CornerRadius="12" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" VerticalAlignment="Center"/>
          <Border Grid.Column="1" Style="{StaticResource Field}" Margin="8,0,0,0" Height="30">$(Get-HexBoxXaml 'picker_hex' 'Code de la couleur')</Border>
          <Button x:Name="picker_auto" Grid.Column="2" Style="{StaticResource Btn.Ghost}" Margin="6,0,0,0" Padding="8,3" MinHeight="0" Content="Automatique" ToolTip="Vider la case : la couleur tirée de l'accent et du fond"/>
        </Grid>
      </StackPanel>
    </Border>
  </Popup>
</Grid>
"@
}

function Select-FontItem($FontBox) {
    # Selects the chosen font in Texte's list, or Segoe UI when it isn't there.
    $items = @($FontBox.Items)
    $FontBox.SelectedItem = @(@($items | Where-Object Name -eq $script:Appearance.FontFamily) + @($items | Where-Object Name -eq 'Segoe UI'))[0]
}

function Connect-AppearancePanel($Root) {
    # Fills the list of themes and wires the editor, in Paramètres. Changes apply at once and are saved. Each handler finds what to apply from
    # the name of the control clicked.
    $script:AppearanceRoot = $Root
    foreach ($name in $script:ThemeModes.Keys) {
        $Root.FindName($name).Add_Click({ param($control) Set-ThemeMode $script:ThemeModes[$control.Name] })
    }
    Connect-ThemeList $Root
    $Root.FindName('create_theme').Add_Click({ Open-ThemeEditor })
    $Root.FindName('theme_copy').Add_Click({ Open-ThemeEditor -FromPreset $script:AppearanceRoot.FindName('theme_list').SelectedItem.Key })
    $Root.FindName('theme_edit').Add_Click({ Open-ThemeEditor -Id $script:AppearanceRoot.FindName('theme_list').SelectedItem.Key })
    $Root.FindName('theme_delete').Add_Click({ Remove-CustomTheme $script:AppearanceRoot.FindName('theme_list').SelectedItem.Key })

    # The editor. The hex box and the sliders follow each other; every change redraws the preview.
    $Root.FindName('editor_accent').Add_TextChanged({
        param($box)
        if ((Repair-HexBox $box) -or $script:Editor.Updating) { return }
        $hex = ConvertTo-HexInput $box.Text
        if ($hex) { Set-EditorColor $hex -FromText }
    })
    # A color's square opens the picker, which writes in its box.
    $Root.FindName('pick_accent').Add_Click({ param($button) Open-ColorPicker $button })
    foreach ($key in $script:ThemeColors.Keys) {
        foreach ($variant in 'light', 'dark') { $Root.FindName("pick_${key}_$variant").Add_Click({ param($button) Open-ColorPicker $button }) }
    }
    $area = $Root.FindName('picker_area')
    $area.Add_MouseLeftButtonDown({
        param($control, $e)
        $null = $control.CaptureMouse()
        Set-PickerPoint $control ($e.GetPosition($control))
    })
    $area.Add_MouseMove({
        param($control, $e)
        if ($control.IsMouseCaptured) { Set-PickerPoint $control ($e.GetPosition($control)) }
    })
    $area.Add_MouseLeftButtonUp({ param($control) $control.ReleaseMouseCapture() })
    $Root.FindName('picker_hue').Add_ValueChanged({
        param($slider)
        if ($script:ColorPicker.Updating) { return }
        $script:ColorPicker.H = $slider.Value
        Set-PickerColor (ConvertFrom-Hsv $script:ColorPicker.H $script:ColorPicker.S $script:ColorPicker.V) -Keep -Write
    })
    $Root.FindName('picker_hex').Add_TextChanged({
        param($box)
        if ((Repair-HexBox $box) -or $script:ColorPicker.Updating) { return }
        $hex = ConvertTo-HexInput $box.Text
        if ($hex) { Set-PickerColor $hex -FromText -Write }
    })
    $Root.FindName('picker_auto').Add_Click({
        $script:ColorPicker.Box.Text = ''
        $script:AppearanceRoot.FindName('color_popup').IsOpen = $false
    })
    # Échap and Entrée close it, its color kept.
    $Root.FindName('picker_panel').Add_PreviewKeyDown({
        $e = $args[1]
        if ($e.Key -in 'Escape', 'Return') {
            $script:AppearanceRoot.FindName('color_popup').IsOpen = $false
            $e.Handled = $true
        }
    })
    foreach ($name in 'editor_hue', 'editor_saturation', 'editor_lightness') {
        $Root.FindName($name).Add_ValueChanged({
            if ($script:Editor.Updating) { return }
            $root = $script:AppearanceRoot
            Set-EditorColor (ConvertFrom-Hsl $root.FindName('editor_hue').Value $root.FindName('editor_saturation').Value $root.FindName('editor_lightness').Value) -FromSlider
        })
    }
    foreach ($key in $script:Presets.Keys) {
        $Root.FindName("editor_pick_$key").Add_Click({
            param($button)
            Set-EditorColor $script:Presets[$button.Name.Substring('editor_pick_'.Length)].Accent
        })
    }
    $Root.FindName('editor_colors_toggle').Add_Click({
        $panel = $script:AppearanceRoot.FindName('editor_colors')
        $panel.Visibility = if ($panel.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
        Update-EditorPreview
    })
    # A color box: empty, the automatic color; a color, that one; anything else waits until it's one (Save-ThemeEditor
    # names it).
    foreach ($key in $script:ThemeColors.Keys) {
        foreach ($variant in 'light', 'dark') {
            $Root.FindName("editor_color_${key}_$variant").Add_TextChanged({
                param($box)
                if ((Repair-HexBox $box) -or $script:Editor.Updating) { return }
                $null, $null, $colorKey, $mode = $box.Name -split '_'
                $variant = if ($mode -eq 'light') { 'Light' } else { 'Dark' }
                $own = $script:Editor.Colors[$variant]
                $text = "$($box.Text)".Trim()
                if (-not $text) { $own.Remove($colorKey) }
                elseif (ConvertTo-HexInput $text) { $own[$colorKey] = ConvertTo-HexInput $text }
                else { return }
                # The preview goes to the mode of the color changed, so the change shows.
                $script:Editor.PreviewVariant = $variant
                Update-EditorPreview
            })
        }
    }
    foreach ($name in 'editor_tint_neutre', 'editor_tint_teinte', 'editor_tint_intense') {
        $Root.FindName($name).Add_Click({
            param($control)
            $script:Editor.Tint = @{ editor_tint_neutre = 'Neutre'; editor_tint_teinte = 'Teinté'; editor_tint_intense = 'Intense' }[$control.Name]
            Update-EditorPreview
        })
    }
    foreach ($name in 'editor_preview_light', 'editor_preview_dark') {
        $Root.FindName($name).Add_Click({
            param($control)
            $script:Editor.PreviewVariant = if ($control.Name -eq 'editor_preview_dark') { 'Dark' } else { 'Light' }
            Update-EditorPreview
        })
    }
    # Texte: the fonts offered, then the size and weight. Each change applies to every window at once, and is saved.
    $fontBox = $Root.FindName('text_font')
    foreach ($font in (Get-OfferedFont).GetEnumerator()) { $fontBox.Items.Add([pscustomobject]@{ Name = $font.Key; Family = $font.Value }) | Out-Null }
    Select-FontItem $fontBox
    $fontBox.Add_SelectionChanged({
        $font = $script:AppearanceRoot.FindName('text_font').SelectedItem.Name
        if (-not $font -or $font -eq $script:Appearance.FontFamily) { return }
        $script:Appearance.FontFamily = $font
        Update-TextSetting
        Set-UiText
        Save-Appearance
    })
    foreach ($name in 'text_size_normal', 'text_size_large', 'text_size_larger') {
        $Root.FindName($name).Add_Click({
            param($control)
            $script:Appearance.TextScale = @{ text_size_normal = 1.0; text_size_large = 1.15; text_size_larger = 1.3 }[$control.Name]
            Update-TextSetting
            Set-UiText
            Save-Appearance
        })
    }
    foreach ($weight in $script:FontWeights.Keys) {
        $Root.FindName("text_weight_$weight").Add_Click({
            param($control)
            $script:Appearance.FontWeight = $control.Name.Substring('text_weight_'.Length)
            Update-TextSetting
            Set-UiText
            Save-Appearance
        })
    }
    # Densité: the same, through Set-UiDensity.
    foreach ($density in $script:Densities.Values) {
        $Root.FindName("density_$($density.Id)").Add_Click({
            param($control)
            $script:Appearance.Density = @($script:Densities.Keys | Where-Object { "density_$($script:Densities[$_].Id)" -eq $control.Name })[0]
            Update-TextSetting
            Set-UiDensity
            Save-Appearance
        })
    }
    # Langue: saved with Paramètres' other settings (SettingsWindow.ps1), for the next launch.
    $languageBox = $Root.FindName('language_list')
    foreach ($name in $script:LanguageChoices.Keys) { $languageBox.Items.Add($name) | Out-Null }
    $languageBox.Add_SelectionChanged({
        param($box)
        if (-not $box.SelectedItem) { return }
        $choice = $script:LanguageChoices[[string]$box.SelectedItem]
        if ($choice -eq $script:LanguageChoice) { return }
        $script:LanguageChoice = $choice
        Save-SettingFile
    })
    $Root.FindName('text_reset').Add_Click({
        $script:Appearance.FontFamily = 'Segoe UI'
        $script:Appearance.TextScale = 1.0
        $script:Appearance.FontWeight = 'SemiBold'
        Select-FontItem $script:AppearanceRoot.FindName('text_font')
        Update-TextSetting
        Set-UiText
        Save-Appearance
    })
    Update-TextSetting
    $Root.FindName('editor_save').Add_Click({ Save-ThemeEditor })
    $Root.FindName('editor_delete').Add_Click({ Remove-EditedTheme })
    $Root.FindName('editor_cancel').Add_Click({ Show-ThemeGallery })
    $Root.FindName('editor_back').Add_Click({ Show-ThemeGallery })
    # Entrée saves the theme, instead of reaching the window's default button (Rechercher).
    $Root.FindName('editor_page').Add_PreviewKeyDown({
        $e = $args[1]
        if ($e.Key -eq 'Return') {
            Save-ThemeEditor
            $e.Handled = $true
        }
    })
    Update-AppearancePanel
}

function Connect-ThemeList($Root) {
    # The list of themes: picking one keeps it, and going through the open list, with the mouse or the arrows, tries each
    # one until the list closes.
    $list = $Root.FindName('theme_list')
    Update-ThemeList
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(120)
    $timer.Add_Tick({ Show-ThemePreview })
    $script:ThemePreview.Timer = $timer
    $list.Add_SelectionChanged({
        param($box)
        if ($script:ThemeList.Updating -or -not $box.SelectedItem) { return }
        Stop-ThemePreview -Keep
        Set-Scheme $box.SelectedItem.Key
    })
    # The open list moves the focus to the row highlighted, by the mouse or the arrows.
    $list.Add_GotFocus({
        param($box, $e)
        $row = $e.OriginalSource
        if (-not $box.IsDropDownOpen -or $row -isnot [System.Windows.Controls.ComboBoxItem]) { return }
        $script:ThemePreview.Key = $row.DataContext.Key
        $script:ThemePreview.Timer.Stop()
        $script:ThemePreview.Timer.Start()
    })
    $list.Add_DropDownClosed({ Stop-ThemePreview })
}

function Show-ThemePreview {
    # The theme highlighted, on every window, unsaved. The row of the theme chosen shows it again.
    $preview = $script:ThemePreview
    $preview.Timer.Stop()
    $key = $preview.Key
    $shown = if ($preview.Shown) { $preview.Shown } else { $script:Appearance.Scheme }
    if (-not $key -or $key -eq $shown) { return }
    Update-ThemeResource $key
    $preview.Shown = if ($key -ne $script:Appearance.Scheme) { $key }
    # Only drawn: screen readers (and the UI tests) read this instead.
    $status = if ($preview.Shown) { (Tr 'Aperçu : {0}') -f (Get-SchemeSpec $key).Name } else { '' }
    [System.Windows.Automation.AutomationProperties]::SetItemStatus($script:AppearanceRoot.FindName('theme_list'), $status)
}

function Stop-ThemePreview([switch]$Keep) {
    # The list closed: the theme chosen comes back. -Keep: what's about to be chosen follows, with no need to.
    $preview = $script:ThemePreview
    $preview.Timer.Stop()
    $preview.Key = $null
    if ($preview.Shown -and -not $Keep) { Update-ThemeResource }
    $preview.Shown = $null
    [System.Windows.Automation.AutomationProperties]::SetItemStatus($script:AppearanceRoot.FindName('theme_list'), '')
}

function Register-ThemeFollow($Window) {
    # Système follows Windows: when it changed while Repère was in the background, the colors follow on return. So does
    # the text boxes' bitmap, for a session reached since over Remote Desktop (Set-TextCache).
    $Window.Add_Activated({
        if ($script:Appearance.Theme -eq 'Système' -and (Get-ThemeVariant) -ne $script:CurrentVariant) {
            Update-ThemeResource
            Update-AppearancePanel
        }
        Set-TextCache
    })
}

function Update-TextSetting {
    # The size, the weight and the density chosen are those toggled on, the density's note says what it does, and the
    # language chosen is the one selected.
    $root = $script:AppearanceRoot
    $scales = @{ text_size_normal = 1.0; text_size_large = 1.15; text_size_larger = 1.3 }
    foreach ($name in $scales.Keys) { $root.FindName($name).IsChecked = [Math]::Abs($scales[$name] - $script:Appearance.TextScale) -lt 0.001 }
    foreach ($weight in $script:FontWeights.Keys) { $root.FindName("text_weight_$weight").IsChecked = $weight -eq $script:Appearance.FontWeight }
    foreach ($density in $script:Densities.Keys) { $root.FindName("density_$($script:Densities[$density].Id)").IsChecked = $density -eq $script:Appearance.Density }
    $root.FindName('density_note').Text = $script:Densities[$script:Appearance.Density].Note
    # Par défaut has nothing to do once the font, size and weight are the defaults: its state says so (#186).
    $root.FindName('text_reset').IsEnabled = $script:Appearance.FontFamily -ne 'Segoe UI' -or $script:Appearance.TextScale -ne 1.0 -or $script:Appearance.FontWeight -ne 'SemiBold'
    $root.FindName('language_list').SelectedItem = @($script:LanguageChoices.Keys | Where-Object { $script:LanguageChoices[$_] -eq $script:LanguageChoice })[0]
}

function ConvertTo-HexInput([string]$Text) {
    # The color typed, with or without its #, as #RRGGBB; $null if it isn't one.
    $hex = "$Text".Trim()
    if ($hex -notmatch '^#') { $hex = "#$hex" }
    if (Test-AccentColor $hex) { $hex.ToUpperInvariant() }
}

function Repair-HexBox($Box) {
    # A color's box holds the six digits only, its # being drawn before it: a # (or a space) typed or pasted is
    # dropped, and so is what's past the sixth character. $true when the box was changed: its TextChanged then runs
    # again, with what's left.
    $clean = "$($Box.Text)" -replace '[#\s]', ''
    if ($clean.Length -gt 6) { $clean = $clean.Substring(0, 6) }
    if ($clean -ceq $Box.Text) { return $false }
    $Box.Text = $clean
    $Box.CaretIndex = $clean.Length
    $true
}

function ConvertTo-HexDigit([string]$Hex) {
    # #RRGGBB as its box shows it, without the #.
    "$Hex".TrimStart('#')
}

function ConvertTo-Hsv([string]$Hex) {
    # Hue (0-360), saturation and value (0-100), for the color picker's square: saturation across, value down.
    $r, $g, $b = ConvertFrom-HexColor $Hex | ForEach-Object { $_ / 255 }
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $d = $max - [Math]::Min($r, [Math]::Min($g, $b))
    $h = 0
    if ($d -gt 0) {
        $h = if ($max -eq $r) { (($g - $b) / $d) % 6 } elseif ($max -eq $g) { ($b - $r) / $d + 2 } else { ($r - $g) / $d + 4 }
        $h = ($h * 60 + 360) % 360
    }
    @{ H = $h; S = $(if ($max -gt 0) { $d / $max * 100 } else { 0 }); V = $max * 100 }
}

function ConvertFrom-Hsv([double]$H, [double]$S, [double]$V) {
    $S = $S / 100
    $V = $V / 100
    $c = $V * $S
    $x = $c * (1 - [Math]::Abs((($H / 60) % 2) - 1))
    $m = $V - $c
    $r, $g, $b = switch ([int][Math]::Floor(($H % 360) / 60)) {
        0 { $c, $x, 0 } 1 { $x, $c, 0 } 2 { 0, $c, $x } 3 { 0, $x, $c } 4 { $x, 0, $c } default { $c, 0, $x }
    }
    '#' + ((($r, $g, $b) | ForEach-Object { '{0:X2}' -f [int][Math]::Round(($_ + $m) * 255) }) -join '')
}

# The color picker: the box it writes in (the accent's or a color's), its color as hue, saturation and value, and
# whether it's being drawn (its controls' events then do nothing).
$script:ColorPicker = @{ Box = $null; H = 0.0; S = 0.0; V = 0.0; Updating = $false }

function Open-ColorPicker($Button) {
    # Under a color's square: its box's color, or for an empty box the automatic one it shows in grey.
    $root = $script:AppearanceRoot
    $isAccent = $Button.Name -eq 'pick_accent'
    $box = $root.FindName($(if ($isAccent) { 'editor_accent' } else { 'editor_color_' + $Button.Name.Substring('pick_'.Length) }))
    $hex = ConvertTo-HexInput $box.Text
    if (-not $hex) { $hex = ConvertTo-HexInput "$($box.Tag)" }
    if (-not $hex) { $hex = $script:Editor.Accent }
    $script:ColorPicker.Box = $box
    $root.FindName('picker_auto').Visibility = if ($isAccent) { 'Collapsed' } else { 'Visible' }
    Set-PickerColor $hex
    $popup = $root.FindName('color_popup')
    $popup.PlacementTarget = $Button
    $popup.IsOpen = $true
    $hexBox = $root.FindName('picker_hex')
    $null = $hexBox.Focus()
    $hexBox.SelectAll()
}

function Set-PickerColor([string]$Hex, [switch]$FromText, [switch]$Keep, [switch]$Write) {
    # The picker's color: its square's hue, the thumb, the hue slider, the code and the preview. -FromText: the code was
    # typed (it stays as it is). -Keep: the hue, saturation and value are already set (from the square or the slider),
    # rather than read back from $Hex, which would lose the hue of a grey. -Write: also in the box it was opened for.
    $root = $script:AppearanceRoot
    $picker = $script:ColorPicker
    if (-not $Keep) {
        $hsv = ConvertTo-Hsv $Hex
        # A grey has no hue: the square keeps the one it had.
        if ($hsv.S -gt 0) { $picker.H = $hsv.H }
        $picker.S = $hsv.S
        $picker.V = $hsv.V
    }
    $picker.Updating = $true
    try {
        $root.FindName('picker_hue').Value = $picker.H
        if (-not $FromText) { $root.FindName('picker_hex').Text = ConvertTo-HexDigit $Hex }
    }
    finally { $picker.Updating = $false }
    $root.FindName('picker_hue_fill').Background = [System.Windows.Media.SolidColorBrush]::new((New-Color (ConvertFrom-Hsv $picker.H 100 100)))
    $root.FindName('picker_preview').Background = [System.Windows.Media.SolidColorBrush]::new((New-Color $Hex))
    $area = $root.FindName('picker_area')
    $width = if ($area.ActualWidth -gt 0) { $area.ActualWidth } else { 240 }
    $height = if ($area.ActualHeight -gt 0) { $area.ActualHeight } else { 150 }
    $thumb = $root.FindName('picker_thumb')
    [System.Windows.Controls.Canvas]::SetLeft($thumb, $picker.S / 100 * $width - $thumb.Width / 2)
    [System.Windows.Controls.Canvas]::SetTop($thumb, (1 - $picker.V / 100) * $height - $thumb.Height / 2)
    if ($Write) { $picker.Box.Text = ConvertTo-HexDigit $Hex }
}

function Set-PickerPoint($Area, $Point) {
    # A click or a drag on the square: saturation from left to right, value from top to bottom.
    $picker = $script:ColorPicker
    $picker.S = [Math]::Min([Math]::Max($Point.X / $Area.ActualWidth, 0), 1) * 100
    $picker.V = (1 - [Math]::Min([Math]::Max($Point.Y / $Area.ActualHeight, 0), 1)) * 100
    Set-PickerColor (ConvertFrom-Hsv $picker.H $picker.S $picker.V) -Keep -Write
}

function Set-Scheme([string]$Key) {
    # A theme, in the mode chosen.
    $script:Appearance.Scheme = $Key
    Update-ThemeResource
    Update-AppearancePanel
    Save-Appearance
}

function Set-ThemeMode([string]$Mode) {
    # Système, Clair or Sombre. The list's colors follow (Update-AppearancePanel).
    $script:Appearance.Theme = $Mode
    Update-ThemeResource
    Update-AppearancePanel
    Save-Appearance
}

function Update-AppearancePanel {
    # The chosen mode and theme, its colors in the list following the mode in use (also while following Windows), and the
    # buttons of that theme. Nothing to do until Paramètres is built.
    $root = $script:AppearanceRoot
    if (-not $root) { return }
    foreach ($name in $script:ThemeModes.Keys) { $root.FindName($name).IsChecked = $script:ThemeModes[$name] -eq $script:Appearance.Theme }
    if ($script:ThemeList.Variant -ne $script:CurrentVariant) { Update-ThemeList }
    $list = $root.FindName('theme_list')
    $rows = @($list.Items | Where-Object { $_ -isnot [System.Windows.Controls.ComboBoxItem] })
    $chosen = @(@($rows | Where-Object Key -eq $script:Appearance.Scheme) + @($rows | Where-Object Key -eq 'Repere'))[0]
    $script:ThemeList.Updating = $true
    try { $list.SelectedItem = $chosen }
    finally { $script:ThemeList.Updating = $false }
    $isCustom = -not $script:Presets.Contains($chosen.Key)
    $root.FindName('theme_copy').Visibility = ConvertTo-Visibility (-not $isCustom)
    foreach ($name in 'theme_edit', 'theme_delete') { $root.FindName($name).Visibility = ConvertTo-Visibility $isCustom }
    $columns = $root.FindName('theme_actions').ColumnDefinitions
    $columns[0].Width = if ($isCustom) { [System.Windows.GridLength]::Auto } else { [System.Windows.GridLength]::new(1, 'Star') }
    $columns[2].Width = if ($isCustom) { [System.Windows.GridLength]::new(1, 'Star') } else { [System.Windows.GridLength]::Auto }
    foreach ($action in @(@('theme_copy', 'Copier {0}'), @('theme_edit', 'Modifier {0}'), @('theme_delete', 'Supprimer {0}'))) {
        [System.Windows.Automation.AutomationProperties]::SetName($root.FindName($action[0]), (Tr $action[1]) -f $chosen.Name)
    }
    # The buttons say what can be done: the note only says what just happened (a theme deleted), until the next change.
    $root.FindName('theme_own_note').Text = ''
    $count = $script:Appearance.CustomThemes.Count
    $create = $root.FindName('create_theme')
    $create.IsEnabled = $count -lt $script:MaxCustomThemes
    $create.ToolTip = if ($create.IsEnabled) { $null } else { (Tr '{0} thèmes au plus : supprimez-en un pour en créer un autre.') -f $script:MaxCustomThemes }
}

function Show-ThemeGallery {
    $root = $script:AppearanceRoot
    $root.FindName('editor_page').Visibility = 'Collapsed'
    $root.FindName('gallery_page').Visibility = 'Visible'
}

function Open-ThemeEditor([string]$Id, [string]$FromPreset) {
    # Edits one of the user's themes (-Id), or starts a new one: from a preset (-FromPreset) or from the current theme.
    $root = $script:AppearanceRoot
    if ($Id) {
        $spec = Get-SchemeSpec $Id
        $title = Tr 'Modifier le thème'
        $name = $spec.Name
    }
    elseif ($FromPreset) {
        $spec = $script:Presets[$FromPreset]
        $title = Tr 'Nouveau thème'
        $name = (Tr '{0} (copie)') -f $spec.Name
    }
    else {
        $spec = Get-SchemeSpec $script:Appearance.Scheme
        $title = Tr 'Nouveau thème'
        $name = ''
    }
    $script:Editor.Id = $Id
    $script:Editor.Tint = [string]$spec.Tint
    $script:Editor.PreviewVariant = if ($script:CurrentVariant -eq 'Dark') { 'Dark' } else { 'Light' }
    # The theme's own colors; a copy of a preset starts from the preset's palettes, so that it looks the same.
    $script:Editor.Colors = @{ Light = @{}; Dark = @{} }
    foreach ($variant in 'Light', 'Dark') {
        $own = Get-ThemeColor $spec $variant
        foreach ($key in $own.Keys) { $script:Editor.Colors[$variant][$key] = $own[$key] }
        if ($FromPreset) {
            $palette = $script:Palettes[$spec.Palettes[$variant]]
            foreach ($key in $script:ThemeColors.Keys) { if ($palette.Contains($key)) { $script:Editor.Colors[$variant][$key] = $palette[$key] } }
            if ($spec.Accents[$variant] -ne $spec.Accent) { $script:Editor.Colors[$variant].Accent = (Get-ThemeBrush $variant $spec)['R.Accent'] }
        }
        # A theme saved before 0.13 made its own accent visible: it's filled in as it showed, so that saved as typed it
        # looks the same.
        elseif ($Id -and -not $spec['Exact'] -and $own.Contains('Accent')) { $script:Editor.Colors[$variant].Accent = (Get-ThemeBrush $variant $spec)['R.Accent'] }
    }
    $root.FindName('editor_colors').Visibility = 'Collapsed'
    $script:Editor.Updating = $true
    try {
        foreach ($variant in 'Light', 'Dark') {
            foreach ($key in $script:ThemeColors.Keys) {
                $root.FindName("editor_color_${key}_$($variant.ToLowerInvariant())").Text = ConvertTo-HexDigit $script:Editor.Colors[$variant][$key]
            }
        }
    }
    finally {
        $script:Editor.Updating = $false
    }
    $root.FindName('editor_title').Text = $title
    $root.FindName('editor_name').Text = $name
    $root.FindName('editor_delete').Visibility = if ($Id) { 'Visible' } else { 'Collapsed' }
    $root.FindName('editor_error').Visibility = 'Collapsed'
    Set-EditorColor $spec.Accent -Initial
    $root.FindName('gallery_page').Visibility = 'Collapsed'
    $root.FindName('editor_page').Visibility = 'Visible'
    $null = $root.FindName('editor_name').Focus()
}

function Set-EditorColor([string]$Hex, [switch]$FromText, [switch]$FromSlider, [switch]$Initial) {
    # The editor's color, shown in the hex box and the sliders (except the one it came from), then the preview. It's the
    # accent of both modes: a color chosen replaces a mode's own accent (its Accent box in Couleurs is emptied), so each
    # mode takes this one, made visible there (Get-ThemeBrush). -Initial: the theme's, as the editor opens, which keeps
    # them.
    $root = $script:AppearanceRoot
    $script:Editor.Updating = $true
    try {
        if (-not $Initial) {
            foreach ($variant in 'Light', 'Dark') {
                if ($script:Editor.Colors[$variant].Contains('Accent')) {
                    $script:Editor.Colors[$variant].Remove('Accent')
                    $root.FindName("editor_color_Accent_$($variant.ToLowerInvariant())").Text = ''
                }
            }
        }
        if (-not $FromText) { $root.FindName('editor_accent').Text = ConvertTo-HexDigit $Hex }
        if (-not $FromSlider) {
            $hsl = ConvertTo-Hsl $Hex
            $root.FindName('editor_hue').Value = $hsl.H
            $root.FindName('editor_saturation').Value = $hsl.S
            $root.FindName('editor_lightness').Value = $hsl.L
        }
        Update-SliderGradient
    }
    finally {
        $script:Editor.Updating = $false
    }
    $script:Editor.Accent = $Hex
    $root.FindName('editor_swatch').Background = [System.Windows.Media.SolidColorBrush]::new((New-Color $Hex))
    Update-EditorPreview
}

function Update-SliderGradient {
    # Each slider shows the colors it leads to: every hue, then this hue from grey to vivid, and from black to white.
    $root = $script:AppearanceRoot
    $h = $root.FindName('editor_hue').Value
    $s = $root.FindName('editor_saturation').Value
    $gradients = @{
        editor_hue        = @(0, 60, 120, 180, 240, 300, 360 | ForEach-Object { ConvertFrom-Hsl $_ 85 55 })
        editor_saturation = @((ConvertFrom-Hsl $h 0 50), (ConvertFrom-Hsl $h 100 50))
        editor_lightness  = @('#000000', (ConvertFrom-Hsl $h $s 50), '#FFFFFF')
    }
    foreach ($name in $gradients.Keys) {
        $colors = $gradients[$name]
        $brush = [System.Windows.Media.LinearGradientBrush]::new()
        $brush.StartPoint = [System.Windows.Point]::new(0, 0.5)
        $brush.EndPoint = [System.Windows.Point]::new(1, 0.5)
        for ($i = 0; $i -lt $colors.Count; $i++) {
            $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new((New-Color $colors[$i]), $i / ($colors.Count - 1)))
        }
        $root.FindName($name).Background = $brush
    }
}

function Update-EditorPreview {
    # The mock-up, in the theme being edited and the mode it shows.
    $root = $script:AppearanceRoot
    foreach ($name in 'editor_tint_neutre', 'editor_tint_teinte', 'editor_tint_intense') {
        $root.FindName($name).IsChecked = @{ editor_tint_neutre = 'Neutre'; editor_tint_teinte = 'Teinté'; editor_tint_intense = 'Intense' }[$name] -eq $script:Editor.Tint
    }
    $root.FindName('editor_preview_light').IsChecked = $script:Editor.PreviewVariant -eq 'Light'
    $root.FindName('editor_preview_dark').IsChecked = $script:Editor.PreviewVariant -eq 'Dark'
    $spec = @{ Accent = $script:Editor.Accent; Tint = $script:Editor.Tint; Colors = $script:Editor.Colors; Exact = $true }
    # Each mode's colors worked out once, for the Couleurs table and the mock-up: every keystroke and slider move
    # redraws them.
    $brushes = @{ Light = Get-ThemeBrush 'Light' $spec; Dark = Get-ThemeBrush 'Dark' $spec }
    Update-EditorColor $spec $brushes
    $c = $brushes[$script:Editor.PreviewVariant]
    $paint = @{
        pv_bg          = @{ Background = 'R.Bg'; BorderBrush = 'R.Border' }
        pv_surface     = @{ Background = 'R.Surface'; BorderBrush = 'R.Border' }
        pv_text        = @{ Foreground = 'R.Text' }
        pv_row         = @{ Background = 'R.Selection' }
        pv_rowtext     = @{ Foreground = 'R.Text' }
        pv_muted       = @{ Foreground = 'R.Muted' }
        pv_button      = @{ Background = 'R.Accent' }
        pv_buttontext  = @{ Foreground = 'R.OnAccent' }
        pv_control     = @{ Background = 'R.Control'; BorderBrush = 'R.Border' }
        pv_controltext = @{ Foreground = 'R.Text' }
    }
    foreach ($name in $paint.Keys) {
        $element = $root.FindName($name)
        foreach ($property in $paint[$name].Keys) {
            $element.$property = [System.Windows.Media.SolidColorBrush]::new((New-Color $c[$paint[$name][$property]]))
        }
    }
}

function Get-ThemeAdvice($Spec, $Brushes) {
    # What the editor says about a theme, per mode (Light, then Dark), from each mode's colors (Get-ThemeBrush, by
    # variant). Notes: how the quick accent shows in a mode, when not as typed: replaced there by the mode's own, or
    # lightened or darkened to stand out. Warnings: the text that reads worst, under 4.5:1 on what it's drawn on; the
    # accent, under 3:1 on the background (as Get-ThemeAccent measures it); the text on the accent, under 4.5:1.
    $culture = Get-TextCulture
    $notes = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($variant in 'Light', 'Dark') {
        $c = $Brushes[$variant]
        $mode = if ($variant -eq 'Light') { Tr 'Clair' } else { Tr 'Sombre' }
        $accent = $c['R.Accent'].ToUpperInvariant()
        if ((Get-ThemeColor $Spec $variant).Contains('Accent')) {
            $notes.Add(((Tr '{0} : son propre accent, {1}, défini dans les couleurs personnalisées. Une couleur choisie ici le remplace.') -f $mode, $accent))
        }
        elseif ($accent -ne $Spec.Accent.ToUpperInvariant()) {
            $format = if ($variant -eq 'Dark') { Tr '{0} : éclairci en {1} pour rester visible.' } else { Tr '{0} : assombri en {1} pour rester visible.' }
            $notes.Add(($format -f $mode, $accent))
        }
        $pairs = foreach ($pair in @(@('Text', 'Surface'), @('Text', 'Bg'), @('Text', 'Control'), @('Text', 'Selection'), @('Muted', 'Surface'), @('Muted', 'Bg'))) {
            [pscustomobject]@{ Text = $pair[0]; On = $pair[1]; Ratio = Get-Contrast $c["R.$($pair[0])"] $c["R.$($pair[1])"] }
        }
        $worst = $pairs | Sort-Object Ratio | Select-Object -First 1
        if ($worst.Ratio -lt 4.5) {
            $warnings.Add([string]::Format($culture, (Tr '{0} : « {1} » se lit mal sur « {2} » ({3:N1}:1, 4,5:1 conseillé).'), $mode, $script:ThemeColors[$worst.Text], $script:ThemeColors[$worst.On], $worst.Ratio))
        }
        $against = if ($variant -eq 'Dark') { 'Bg' } else { 'Surface' }
        $ratio = Get-Contrast $c['R.Accent'] $c["R.$against"]
        if ($ratio -lt 3) {
            $warnings.Add([string]::Format($culture, (Tr '{0} : l''accent ressort peu ({1:N1}:1, 3:1 conseillé) ; la sélection et le focus se verront mal.'), $mode, $ratio))
        }
        $ratio = Get-Contrast $c['R.Accent'] $c['R.OnAccent']
        if ($ratio -lt 4.5) {
            $warnings.Add([string]::Format($culture, (Tr '{0} : le texte des boutons d''accent se lit mal ({1:N1}:1, 4,5:1 conseillé).'), $mode, $ratio))
        }
    }
    @{ Notes = @($notes); Warnings = @($warnings) }
}

function Update-EditorColor($Spec, $Brushes) {
    # The Couleurs table: each swatch shows the color in use, and an empty box the automatic one, in grey. Then, under the
    # quick accent, how it shows in each mode, and the contrast warnings (Get-ThemeAdvice): the theme is still saved, its
    # colors as typed. $Brushes: each mode's colors (Get-ThemeBrush), by variant.
    $root = $script:AppearanceRoot
    foreach ($variant in 'Light', 'Dark') {
        $v = $variant.ToLowerInvariant()
        $c = $Brushes[$variant]
        foreach ($key in $script:ThemeColors.Keys) {
            $root.FindName("editor_swatch_${key}_$v").Background = [System.Windows.Media.SolidColorBrush]::new((New-Color $c["R.$key"]))
            $root.FindName("editor_color_${key}_$v").Tag = ConvertTo-HexDigit $c["R.$key"]
        }
    }
    $advice = Get-ThemeAdvice $Spec $Brushes
    $root.FindName('editor_contrast').Text = $advice.Warnings -join "`n"
    $root.FindName('editor_contrast_panel').Visibility = ConvertTo-Visibility ([bool]$advice.Warnings.Count)
    $note = $root.FindName('editor_accent_note')
    $note.Text = $advice.Notes -join "`n"
    $note.Visibility = ConvertTo-Visibility ([bool]$advice.Notes.Count)
    # Folded, the button says how many colors the theme sets.
    $count = $Spec.Colors.Light.Count + $Spec.Colors.Dark.Count
    $root.FindName('editor_colors_toggle_text').Text = if ($root.FindName('editor_colors').Visibility -eq 'Visible') { Tr 'Masquer les couleurs' }
                                                       elseif ($count -eq 1) { Tr '1 couleur personnalisée' }
                                                       elseif ($count) { (Tr '{0} couleurs personnalisées') -f $count }
                                                       else { Tr 'Personnaliser les couleurs' }
}

function Save-ThemeEditor {
    # Saves the theme being edited and makes it the current one.
    $root = $script:AppearanceRoot
    $errorText = $root.FindName('editor_error')
    $hex = ConvertTo-HexInput $root.FindName('editor_accent').Text
    $invalid = foreach ($variant in @(@('light', (Tr 'clair')), @('dark', (Tr 'sombre')))) {
        foreach ($key in $script:ThemeColors.Keys) {
            $text = "$($root.FindName("editor_color_${key}_$($variant[0])").Text)".Trim()
            if ($text -and -not (ConvertTo-HexInput $text)) { (Tr '« {0} » ({1})') -f $script:ThemeColors[$key], $variant[1] }
        }
    }
    $message = if (-not $hex) { Tr 'Couleur invalide. Exemple : #7553FF' }
               elseif (@($invalid).Count) { (Tr 'Couleur invalide pour {0}. Exemple : #1E1E1E, ou vide pour la couleur automatique.') -f @($invalid)[0] }
               elseif (-not $script:Editor.Id -and $script:Appearance.CustomThemes.Count -ge $script:MaxCustomThemes) { (Tr '{0} thèmes au plus : supprimez-en un pour en créer un autre.') -f $script:MaxCustomThemes }
    if ($message) {
        $errorText.Text = $message
        $errorText.Visibility = 'Visible'
        return
    }
    $name = "$($root.FindName('editor_name').Text)".Trim()
    if (-not $name) { $name = Tr 'Mon thème' }
    # Only the modes with colors of their own are kept.
    $colors = @{}
    foreach ($variant in 'Light', 'Dark') {
        if ($script:Editor.Colors[$variant].Count) { $colors[$variant] = $script:Editor.Colors[$variant].Clone() }
    }
    if ($script:Editor.Id) {
        $theme = Get-SchemeSpec $script:Editor.Id
        $theme.Name = $name
        $theme.Accent = $hex
        $theme.Tint = $script:Editor.Tint
        $theme.Exact = $true
        if ($colors.Count) { $theme.Colors = $colors } else { $theme.Remove('Colors') }
        $id = $script:Editor.Id
    }
    else {
        $id = Add-CustomTheme $name $hex $script:Editor.Tint $colors -Exact
    }
    $script:Appearance.Scheme = $id
    Update-ThemeList
    Show-ThemeGallery
    Update-ThemeResource
    Update-AppearancePanel
    Save-Appearance
}

function Remove-EditedTheme {
    Remove-CustomTheme $script:Editor.Id
}

function Remove-CustomTheme([string]$Id) {
    # Deletes one of the user's themes (the list's Supprimer or the editor's), once confirmed: it can't be recovered, and
    # Annuler is the default, as for the other deletions. It's named as saved, not as the editor may have it unsaved, and
    # found by its Id, so two themes of the same name can't be mixed up. If it was the current one, Repère's comes back:
    # the confirmation says so beforehand, and the note under Mes thèmes afterwards.
    $theme = Get-SchemeSpec $Id
    $current = $script:Appearance.Scheme -eq $Id
    $message = if ($current) { Tr 'Il ne pourra pas être récupéré. Repère reprendra son thème.' } else { Tr 'Il ne pourra pas être récupéré.' }
    Show-Dialog -Title (Tr 'Supprimer le thème') -Heading ((Tr 'Supprimer le thème « {0} » ?') -f $theme.Name) -Message $message -Icon 'trash' -Tone 'danger' `
        -OkText (Tr 'Supprimer') -CancelIsDefault -Owner $script:Settings.Window -State @{ Theme = $theme; Current = $current } -OnOk {
        param($state)
        $script:Appearance.CustomThemes.Remove($state.Theme) | Out-Null
        if ($state.Current) { $script:Appearance.Scheme = 'Repere' }
        Update-ThemeList
        Show-ThemeGallery
        Update-ThemeResource
        Update-AppearancePanel
        Save-Appearance
        # Until the next change of theme or mode, the note says what happened instead of what can be done.
        $script:AppearanceRoot.FindName('theme_own_note').Text = if ($state.Current) { (Tr 'Thème « {0} » supprimé : Repère a repris son thème.') -f $state.Theme.Name } else { (Tr 'Thème « {0} » supprimé.') -f $state.Theme.Name }
    }
}

#endregion
