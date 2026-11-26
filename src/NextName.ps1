# Prochain nom…: the next free name of a series of computers, in AD and, when Paramètres knows the site, in SCCM.
# The format is shown rather than written: one field takes a real name or a pattern (ConvertTo-NameFormat), or a click
# picks a series AD already has (Get-NameSeriesChoice), and each block of the format can then be clicked to fix it or
# make it vary. A format is a list of blocks, never a text: the generator only reads that list, so a block clicked fixed
# stays so in the recent formats.
#
# A block is a hashtable: Kind (Text, Digits, Letters), Length, Text (as typed, '' for # and @), Varies, and Locked
# when a click can't change it (separators, # and @). A series (New-NameSeries) is a format made ready to count: its
# varying characters are the digits of one number in a mixed base, the rightmost moving fastest like an odometer, so
# even ORD-AAAA-#### is never enumerated (Get-NextName).
#
# prochainnom.json keeps the recent formats and the options. Nothing is reserved or written: AD and SCCM are only read.
# Dot-sourced by the main script, after SettingsWindow.ps1, Background.ps1 and Sccm.ps1; the action bar's button, the results' right-click
# menu and Ctrl+N open the window (ComputerActions.ps1).
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

$script:NextNameSettingPath = Get-SettingPath 'prochainnom.json'
# The recent formats kept, the names asked for at most, and how long a name can be (Windows' NetBIOS limit).
$script:NextNameRecentLimit = 8
$script:NextNameCountLimit = 50
# Up to this many domains are ticked in the window; past it, in a list of their own.
$script:NextNameDomainsInPlace = 3
# How many times in a row SCCM may be asked for the next names, all the last ones it had, before Prochain nom… stops.
$script:NextNameSccmRounds = 10
$script:NameLengthLimit = 15
# The window's height at the usual text size: a format's series, blocks, three names and SCCM's line, without scrolling.
$script:NextNameHeight = 680
# The window's state while it's open: its controls (Root), the format (Blocks), the last read and those under way.
$script:NextNameDialog = $null
# After Configurer…, the way back once Paramètres closes (Resume-NextNameDialog): the owner, the icon and the format.
$script:NextNameReturn = $null
$script:NextNameReturnHooked = $false

function ConvertTo-NameFormat([string]$Text) {
    # What's typed, as blocks, in capitals (AD ignores case): runs of digits, letters, separators, # and @. # and @ vary,
    # and so do AA or XXX alone in their block, how people write « letters here ». Other letters are fixed, so LAPTOP or
    # LABO need no escape. With nothing varying yet, the text is a real name: its last group of digits counts.
    $blocks = @(foreach ($run in [regex]::Matches($Text.Trim().ToUpperInvariant(), '#+|@+|[0-9]+|[A-Z]+|[^0-9A-Z#@]+')) {
            $value = $run.Value
            if ($value[0] -eq '#') { @{ Kind = 'Digits'; Length = $value.Length; Text = ''; Varies = $true; Locked = $true } }
            elseif ($value[0] -eq '@') { @{ Kind = 'Letters'; Length = $value.Length; Text = ''; Varies = $true; Locked = $true } }
            elseif ($value -match '^[0-9]') { @{ Kind = 'Digits'; Length = $value.Length; Text = $value; Varies = $false; Locked = $false } }
            elseif ($value -match '^[A-Z]') { @{ Kind = 'Letters'; Length = $value.Length; Text = $value; Varies = ($value -cmatch '^(A{2,}|X{2,})$'); Locked = $false } }
            else { @{ Kind = 'Text'; Length = $value.Length; Text = $value; Varies = $false; Locked = $true } }
        })
    if (-not @($blocks | Where-Object { $_.Varies }).Count) {
        $last = @($blocks | Where-Object { $_.Kind -eq 'Digits' }) | Select-Object -Last 1
        if ($last) { $last.Varies = $true }
    }
    $blocks
}

function Get-NameFormatText($Blocks) {
    # A format as text: ORD-@@@-####, or with its fixed text. To read only: ConvertTo-NameFormat wouldn't give back a
    # block clicked fixed.
    -join @(foreach ($block in @($Blocks)) {
            if (-not $block.Varies) { $block.Text }
            elseif ($block.Kind -eq 'Digits') { '#' * $block.Length }
            else { '@' * $block.Length }
        })
}

function Get-NameFormatStart($Blocks) {
    # The text before the first varying block: what AD and SCCM are asked for.
    -join @(foreach ($block in @($Blocks)) {
            if ($block.Varies) { break }
            $block.Text
        })
}

function Get-NameAlphabet([string]$Kind, [string]$Exclude) {
    # The characters a varying block of this kind can use, less those excluded.
    $all = if ($Kind -eq 'Digits') { '0123456789' } else { 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' }
    $excluded = $Exclude.ToUpperInvariant()
    -join @($all.ToCharArray() | Where-Object { $excluded.IndexOf($_) -lt 0 })
}

function Get-NameFormatProblem($Blocks, [string]$Exclude = '') {
    # What makes this format unusable, in words; nothing when it's fine.
    $format = @($Blocks)
    $length = 0
    foreach ($block in $format) { $length += $block.Length }
    if (-not $length) { return Tr 'Tapez un nom ou un modèle.' }
    if ($length -gt $script:NameLengthLimit) { return (Tr 'Un nom a {0} caractères au plus.') -f $script:NameLengthLimit }
    if (@($format | Where-Object { $_.Kind -eq 'Text' -and $_.Text -notmatch '^[-_]+$' }).Count) { return Tr 'Lettres, chiffres, - et _ seulement.' }
    if (-not @($format | Where-Object { $_.Kind -ne 'Digits' }).Count) { return Tr 'Un nom ne peut pas être fait que de chiffres.' }
    foreach ($block in $format) {
        if ($block.Varies -and -not (Get-NameAlphabet $block.Kind $Exclude)) { return Tr 'Exclure ne laisse plus aucun caractère à ce modèle.' }
    }
    # Without it, AD and SCCM would be asked for every computer they have.
    if (-not (Get-NameFormatStart $format)) { return Tr 'Un modèle commence par un texte fixe, ex. ORD-####.' }
}

function New-NameSeries($Blocks, [string]$Exclude = '') {
    # A format ready to count: Regex (the names of the series), Slots (each varying character's Offset, Alphabet and
    # Base, left to right), Template (the name, its varying characters blank), Space (how many numbers) and Count (how
    # many names). The last group of digits is never all zeros, ORD-0000 being no one's first name: Step is the place of
    # that group in the number and Size how many values it has, 0 without such a group. Not when Exclure leaves it only
    # 0: all zeros is then its one value, and ORD-0 a name like any other, or no number would be one.
    $pattern = [System.Text.StringBuilder]::new('^')
    $slots = [System.Collections.Generic.List[object]]::new()
    $template = [System.Text.StringBuilder]::new()
    $counter = @($Blocks | Where-Object { $_.Varies -and $_.Kind -eq 'Digits' }) | Select-Object -Last 1
    $counterEnd = -1
    foreach ($block in @($Blocks)) {
        if (-not $block.Varies) {
            $null = $pattern.Append([regex]::Escape($block.Text))
            $null = $template.Append($block.Text)
            continue
        }
        $alphabet = Get-NameAlphabet $block.Kind $Exclude
        $null = $pattern.Append("[$alphabet]{$($block.Length)}")
        for ($i = 0; $i -lt $block.Length; $i++) {
            $slots.Add(@{ Offset = $template.Length + $i; Alphabet = $alphabet; Base = [bigint]$alphabet.Length })
        }
        $null = $template.Append([string]::new([char]'?', $block.Length))
        if ([object]::ReferenceEquals($block, $counter) -and $alphabet.Length -gt 1 -and $alphabet[0] -eq '0') { $counterEnd = $slots.Count }
    }
    $space, $step, $size = [bigint]1, [bigint]1, [bigint]0
    for ($i = $slots.Count - 1; $i -ge 0; $i--) {
        $space *= $slots[$i].Base
        if ($i -ge $counterEnd -and $counterEnd -ge 0) { $step *= $slots[$i].Base }
    }
    if ($counterEnd -ge 0) { $size = [bigint]::Pow($slots[$counterEnd - 1].Base, $counter.Length) }
    $count = if ($size) { $space - [bigint]::Divide($space, $size) } else { $space }
    @{
        Regex = [regex]::new("$pattern\z", 'IgnoreCase, CultureInvariant')
        Slots = $slots.ToArray(); Template = $template.ToString(); Space = $space; Count = $count; Step = $step; Size = $size
    }
}

function Get-NameSeriesNumber($Series, [string]$Name) {
    # A name of the series, as its number.
    $number = [bigint]0
    $upper = $Name.ToUpperInvariant()
    foreach ($slot in $Series.Slots) { $number = $number * $slot.Base + $slot.Alphabet.IndexOf($upper[$slot.Offset]) }
    $number
}

function Get-NameSeriesName($Series, [bigint]$Number) {
    # A number below the series' Space, as its name.
    $name = $Series.Template.ToCharArray()
    for ($i = $Series.Slots.Length - 1; $i -ge 0; $i--) {
        $slot = $Series.Slots[$i]
        $remainder = [bigint]::Remainder($Number, $slot.Base)
        $Number = [bigint]::Divide($Number, $slot.Base)
        $name[$slot.Offset] = $slot.Alphabet[[int]$remainder]
    }
    -join $name
}

function Test-NameSeriesNumber($Series, [bigint]$Number) {
    # Whether a number is a name: its last group of digits isn't all zeros.
    -not $Series.Size -or -not [bigint]::Remainder([bigint]::Divide($Number, $Series.Step), $Series.Size).IsZero
}

function Get-NameSeriesValid($Series, [bigint]$Number) {
    # $Number when it's a name, otherwise the next one that is: past the zeros, the characters after them at their first.
    # With the rule on, the counter has two digits at least to choose from and that one always is; should it not be,
    # Space, past the series, so that no caller hands out a name that isn't one.
    if (Test-NameSeriesNumber $Series $Number) { return $Number }
    $next = $Number - [bigint]::Remainder($Number, $Series.Step) + $Series.Step
    if (Test-NameSeriesNumber $Series $next) { $next } else { $Series.Space }
}

function Get-NameSeriesRandom($Series, [System.Random]$Random) {
    # A number below the series' Space. Eight more bytes than it needs, so the remainder's bias doesn't matter.
    $bytes = [byte[]]::new($Series.Space.GetByteCount() + 9)
    $Random.NextBytes($bytes)
    $bytes[-1] = 0
    [bigint]::Remainder([bigint]::new($bytes), $Series.Space)
}

function Get-NextName {
    # The free names of a series, $Count at most: Names, and Taken, how many of $TakenName are in the series (a name in
    # two domains once). In order, after the highest taken or, with -FillGaps, the lowest free; from $From, a name of the
    # series, when given. With $Random, at random among the free ones. Without varying block, the only name, if it's
    # free. $Skip: names taken elsewhere (SCCM's), never given, but which don't move where the series goes on from.
    param(
        [Parameter(Mandatory)] $Series,
        [string[]]$TakenName = @(),
        [string[]]$Skip = @(),
        [int]$Count = 1,
        [switch]$FillGaps,
        [string]$From,
        [System.Random]$Random
    )
    $taken = [System.Collections.Generic.HashSet[bigint]]::new()
    # The taken that are names: an all-zero one matches the Regex, but isn't one of the series' Count.
    $takenNames = 0
    foreach ($name in $TakenName) {
        if (-not $Series.Regex.IsMatch($name)) { continue }
        $used = Get-NameSeriesNumber $Series $name
        if ($taken.Add($used) -and (Test-NameSeriesNumber $Series $used)) { $takenNames++ }
    }
    $skipped = [System.Collections.Generic.HashSet[bigint]]::new()
    foreach ($name in $Skip) { if ($Series.Regex.IsMatch($name)) { $null = $skipped.Add((Get-NameSeriesNumber $Series $name)) } }
    $names = [System.Collections.Generic.List[string]]::new()
    # Full: nothing to look for, and drawing would never end.
    if ($Series.Count -le $takenNames) { }
    elseif (-not $Series.Slots.Length) { $names.Add($Series.Template) }
    elseif ($Random) {
        # Count, not Space: the all-zero numbers are drawn too, and never kept.
        if ($Series.Count -le 2 * $takenNames + 1024) {
            # Small, or mostly taken: drawing could take long. All the names in a random order, then the free ones: the
            # same order whatever is skipped, so that a name SCCM has only gives way to the next one.
            $all = @(for ($number = [bigint]0; $number -lt $Series.Space; $number += 1) { if (Test-NameSeriesNumber $Series $number) { $number } })
            for ($i = $all.Count - 1; $i -gt 0; $i--) {
                $j = $Random.Next($i + 1)
                $all[$i], $all[$j] = $all[$j], $all[$i]
            }
            foreach ($number in $all) {
                if ($names.Count -ge $Count) { break }
                if (-not $taken.Contains($number) -and -not $skipped.Contains($number)) { $names.Add((Get-NameSeriesName $Series $number)) }
            }
        }
        else {
            # More than half the names are free, and names are half the numbers at least: a quarter of the draws or more
            # hit. Still, never more draws than this, on the UI thread; out of luck, the rest are the lowest free ones.
            for ($draw = 0; $names.Count -lt $Count -and $draw -lt 50 * $Count; $draw++) {
                $number = Get-NameSeriesRandom $Series $Random
                if ((Test-NameSeriesNumber $Series $number) -and -not $skipped.Contains($number) -and $taken.Add($number)) { $names.Add((Get-NameSeriesName $Series $number)) }
            }
            for ($number = Get-NameSeriesValid $Series ([bigint]0); $names.Count -lt $Count -and $number -lt $Series.Space; $number = Get-NameSeriesValid $Series ($number + 1)) {
                if (-not $skipped.Contains($number) -and $taken.Add($number)) { $names.Add((Get-NameSeriesName $Series $number)) }
            }
            # What was drawn isn't what AD has: Taken says the series' names.
            return @{ Names = $names.ToArray(); Taken = $taken.Count - $names.Count }
        }
    }
    else {
        $number = Get-NameSeriesValid $Series ([bigint]0)
        if ($From) { $number = Get-NameSeriesValid $Series (Get-NameSeriesNumber $Series $From) }
        if (-not $FillGaps) {
            foreach ($used in $taken) {
                if ($used -ge $number) { $number = Get-NameSeriesValid $Series ($used + 1) }
            }
        }
        while ($names.Count -lt $Count -and $number -lt $Series.Space) {
            if (-not $taken.Contains($number) -and -not $skipped.Contains($number)) { $names.Add((Get-NameSeriesName $Series $number)) }
            $number = Get-NameSeriesValid $Series ($number + 1)
        }
    }
    @{ Names = $names.ToArray(); Taken = $taken.Count }
}

function Get-NameTypedStart([string]$Text) {
    # What's typed before any # or @, in capitals: the series to offer start with it.
    ($Text.Trim() -replace '[#@].*$', '').ToUpperInvariant()
}

function Get-NameSeriesChoice([string]$Start, [string[]]$Name, [int]$Limit = 6) {
    # The series these names follow that start with $Start, the most used first: each its Format (ORD-####), Count (its
    # names, as « déjà pris » counts them) and Accounts (its computers: a name in two domains is two). A name without
    # digits is no series.
    $names = @{}
    $accounts = @{}
    foreach ($item in $Name) {
        if ($item -notmatch '\d' -or -not $item.StartsWith($Start, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $upper = $item.ToUpperInvariant()
        $format = [regex]::Replace($upper, '\d', '#')
        if (-not $names.ContainsKey($format)) { $names[$format] = [System.Collections.Generic.HashSet[string]]::new() }
        $null = $names[$format].Add($upper)
        $accounts[$format] = 1 + [int]$accounts[$format]
    }
    $names.GetEnumerator() | Sort-Object @{ Expression = { $_.Value.Count }; Descending = $true }, Name | Select-Object -First $Limit |
        ForEach-Object { [pscustomobject]@{ Format = $_.Name; Count = $_.Value.Count; Accounts = $accounts[$_.Name] } }
}

function Read-NextNameSetting {
    # The options as prochainnom.json keeps them; what's missing or not offered keeps its default.
    $setting = @{ Recent = @(); Random = $false; FillGaps = $false; Count = 3; Exclude = ''; Sccm = $true; Domains = @() }
    $saved = Read-JsonSetting $script:NextNameSettingPath Recent, Random, FillGaps, Count, Exclude, Sccm, Domains
    if (-not $saved) { return $setting }
    # The domains ticked last time; whether they're still offered is the window's to say (Get-NextNameDomainChoice).
    $setting.Domains = @($saved.Domains | Where-Object { $_ -is [string] -and $_ })
    $setting.Random = $saved.Random -eq $true
    $setting.FillGaps = $saved.FillGaps -eq $true
    $setting.Sccm = $saved.Sccm -ne $false
    $count = 0
    if ([int]::TryParse("$($saved.Count)", [ref]$count) -and $count -ge 1 -and $count -le $script:NextNameCountLimit) { $setting.Count = $count }
    if ("$($saved.Exclude)" -match '^[A-Za-z0-9]*$') { $setting.Exclude = "$($saved.Exclude)".ToUpperInvariant() }
    $setting.Recent = @(foreach ($format in @($saved.Recent | Where-Object { $_ })) {
            $blocks = ConvertFrom-SavedNameFormat $format
            if ($blocks) { , $blocks }
        })
    $setting
}

function ConvertFrom-SavedNameFormat($Saved) {
    # A format as the file keeps it, or nothing when a block isn't one Repère would have made.
    $blocks = @(foreach ($block in @($Saved)) {
            $read = $block | Select-Object Kind, Length, Text, Varies, Locked
            if ($read.Kind -notin 'Text', 'Digits', 'Letters' -or $read.Length -isnot [ValueType] -or [int]$read.Length -lt 1) { return }
            @{ Kind = [string]$read.Kind; Length = [int]$read.Length; Text = [string]$read.Text; Varies = $read.Varies -eq $true; Locked = $read.Locked -eq $true }
        })
    if ($blocks.Count -and -not (Get-NameFormatProblem $blocks)) { $blocks }
}

function Add-RecentNameFormat($Blocks, $Recent) {
    # The recent formats with this one first: once, however it's written, and no more than the limit.
    $text = Get-NameFormatText $Blocks
    $others = @($Recent | Where-Object { (Get-NameFormatText $_) -ne $text })
    @(, @($Blocks)) + @($others | ForEach-Object { , @($_) }) | Select-Object -First $script:NextNameRecentLimit
}

function Get-FailedDomainText($Failed) {
    # The domains that didn't answer, those with the same reason together: a network down is one reason, not one a domain.
    @($Failed | Group-Object { $_.Reason } | ForEach-Object {
            $domains = @($_.Group | ForEach-Object { $_.Domain }) -join ', '
            (Tr '{0} ({1})') -f $domains, $_.Name
        }) -join (Tr ' ; ')
}

function Get-NextNameRead([string]$Start, [string[]]$Domains) {
    # On a search runspace: the names that start with $Start in each domain, in the same list since a name is taken in
    # any of them, and the domains that didn't answer (Failed). SCCM is asked apart, for the names given only
    # (Start-NextNameSccmCheck).
    $names = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($domain in $Domains) {
        try {
            foreach ($computer in Get-ADComputer -Filter "Name -like '$Start*'" -Server $domain -ErrorAction Stop) { $names.Add($computer.Name) }
        }
        catch { $failed.Add(@{ Domain = $domain; Reason = ConvertTo-FrenchError $_.Exception.Message }) }
    }
    @{ Names = $names.ToArray(); Failed = $failed.ToArray() }
}

$script:NextNameXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
           Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <!-- Also the window's title bar (Set-WindowChrome), its buttons at the end. -->
  <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="16,12,0,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Border Width="38" Height="38" CornerRadius="8" Background="{DynamicResource R.Selection}" TextElement.Foreground="{DynamicResource R.AccentText}">
          <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:monitorcheck:20}}</Grid>
        </Border>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" Text="Prochain nom"/>
        </StackPanel>
      </StackPanel>
      <StackPanel x:Name="caption_buttons" Grid.Column="1" Orientation="Horizontal" Margin="12,-12,0,-12"/>
    </Grid>
  </Border>
  <Border DockPanel.Dock="Bottom" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,1,0,0" Padding="16,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="next_status" Style="{StaticResource Txt.Muted}" FontSize="12" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,14,0"
                 Text="Les noms ne sont pas réservés."/>
      <Button x:Name="next_copy" Grid.Column="1" Style="{StaticResource Btn.Primary}" Margin="0,0,8,0" MinWidth="90" IsEnabled="False" Content="Copier" ToolTip="Le premier nom"/>
      <Button x:Name="dialog_cancel" Grid.Column="2" MinWidth="90" IsCancel="True" Content="Fermer"/>
    </Grid>
  </Border>
  <ScrollViewer x:Name="next_scroll" VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="16,14,16,14">
      <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Un nom existant ou un modèle"/>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border Style="{StaticResource Field}" Height="{DynamicResource R.BarHeight}">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBox x:Name="next_format" Style="{StaticResource Text.Bare}" FontFamily="Consolas" Tag="ORD-0143, ORD-####, ORD-AAA-####" AutomationProperties.Name="Un nom existant ou un modèle"/>
            <Button x:Name="next_recent" Grid.Column="1" Style="{StaticResource Btn.Mini}" Margin="0,0,5,0" Visibility="Collapsed" ToolTip="Modèles récents" AutomationProperties.Name="Modèles récents">
              {{icon:history:15}}
              <Button.ContextMenu><ContextMenu x:Name="next_recent_menu"/></Button.ContextMenu>
            </Button>
          </Grid>
        </Border>
        <Button x:Name="next_search" Grid.Column="1" Height="{DynamicResource R.BarHeight}" Padding="12,0" Margin="8,0,0,0" IsDefault="True" ToolTip="Relit l'AD, et SCCM s'il est coché" AutomationProperties.Name="Rechercher">
          <StackPanel Orientation="Horizontal">{{icon:search}}<TextBlock Text="Rechercher" Margin="8,0,0,0"/></StackPanel>
        </Button>
      </Grid>
      <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap" Text="# est un chiffre, @ une lettre."/>

      <StackPanel x:Name="next_series_panel" Visibility="Collapsed" Margin="0,12,0,0">
        <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Déjà dans l'AD"/>
        <WrapPanel x:Name="next_series"/>
      </StackPanel>

      <StackPanel x:Name="next_blocks_panel" Visibility="Collapsed" Margin="0,12,0,0">
        <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Cliquez un bloc pour le fixer ou le faire varier"/>
        <WrapPanel x:Name="next_blocks"/>
      </StackPanel>

      <WrapPanel x:Name="next_domains" Margin="0,12,0,0"/>
      <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
        <!-- Past a few domains: the button says how many are ticked, and they're ticked in its popup. -->
        <Button x:Name="next_domains_button" Margin="0,0,14,0" Visibility="Collapsed" ToolTip="Les domaines où chercher">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="next_domains_text" VerticalAlignment="Center"/>
            <Border Margin="8,0,0,0" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:chevron:12}}</Border>
          </StackPanel>
        </Button>
        <Popup x:Name="next_domains_popup" PlacementTarget="{Binding ElementName=next_domains_button}" Placement="Bottom" StaysOpen="False" AllowsTransparency="True">
          <Border Style="{StaticResource Card}" Padding="12" MinWidth="260" Margin="0,4,10,10">
            <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Opacity="0.25"/></Border.Effect>
            <StackPanel>
              <!-- Hides the domains that don't contain it, without unticking them; Tous and Aucun then apply to those shown. -->
              <Border Style="{StaticResource Field}" Height="{DynamicResource R.BarHeight}" Margin="0,0,0,8">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
                  <TextBox x:Name="next_domains_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les domaines" AutomationProperties.Name="Filtrer les domaines"
                           ToolTip="Échap efface le filtre ; ↓ va aux domaines"/>
                  <Button x:Name="next_domains_filter_clear" Grid.Column="2" Style="{StaticResource Btn.Mini}" Margin="0,0,5,0" Visibility="Collapsed" Focusable="False"
                          ToolTip="Effacer le filtre" AutomationProperties.Name="Effacer le filtre">{{icon:x:12}}</Button>
                </Grid>
              </Border>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Button x:Name="next_domains_all" MinWidth="70" Content="Tous"/>
                <Button x:Name="next_domains_none" MinWidth="70" Margin="6,0,0,0" Content="Aucun"/>
              </StackPanel>
              <ScrollViewer x:Name="next_domains_scroll" MaxHeight="280" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="next_domains_list"/>
              </ScrollViewer>
            </StackPanel>
          </Border>
        </Popup>
        <CheckBox x:Name="next_sccm_check" VerticalAlignment="Center" Content="Vérifier dans SCCM"/>
        <Button x:Name="next_sccm_setup" Margin="10,0,0,0" Visibility="Collapsed" Content="Configurer…" ToolTip="Le site SCCM, dans Paramètres"/>
      </StackPanel>

      <Border Style="{StaticResource Card}" Padding="14,10" Margin="0,12,0,0">
        <StackPanel>
          <TextBlock x:Name="next_result_label" Style="{StaticResource Txt.Muted}" Text="Prochain nom libre"/>
          <TextBlock x:Name="next_name" FontFamily="Consolas" FontSize="22" FontWeight="{DynamicResource R.FontWeightTitle}" Margin="0,2,0,0"/>
          <TextBlock x:Name="next_more" FontFamily="Consolas" TextWrapping="Wrap" Margin="0,2,0,0" Visibility="Collapsed"/>
          <TextBlock x:Name="next_count_text" Style="{StaticResource Txt.Muted}" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed"/>
          <TextBlock x:Name="next_problem" Foreground="{DynamicResource R.WarnText}" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed"/>
          <TextBlock x:Name="next_domain_note" Foreground="{DynamicResource R.WarnText}" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed"/>
          <TextBlock x:Name="next_sccm_result" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed"/>
        </StackPanel>
      </Border>

      <ToggleButton x:Name="next_options" HorizontalAlignment="Left" Margin="0,12,0,0" Content="Options"/>
      <Grid x:Name="next_options_panel" Margin="0,10,0,0" Visibility="Collapsed">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Ordre"/>
          <ComboBox x:Name="next_order" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Ordre">
            <ComboBoxItem Content="Séquentiel"/>
            <ComboBoxItem Content="Aléatoire"/>
          </ComboBox>
        </StackPanel>
        <StackPanel Grid.Column="2">
          <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Quand il y a des trous"/>
          <ComboBox x:Name="next_gaps" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Quand il y a des trous">
            <ComboBoxItem Content="Après le plus haut"/>
            <ComboBoxItem Content="Le plus bas libre"/>
          </ComboBox>
        </StackPanel>
        <StackPanel Grid.Row="1" Margin="0,10,0,0">
          <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Commencer à"/>
          <TextBox x:Name="next_from" FontFamily="Consolas" AutomationProperties.Name="Commencer à" ToolTip="Un nom de la série, ex. ORD-0500"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Grid.Column="2" Margin="0,10,0,0">
          <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Exclure"/>
          <TextBox x:Name="next_exclude" FontFamily="Consolas" AutomationProperties.Name="Exclure" ToolTip="Les caractères à éviter là où le nom varie, ex. IO0"/>
        </StackPanel>
        <StackPanel Grid.Row="2" Margin="0,10,0,0">
          <TextBlock Style="{StaticResource Txt.Label}" Margin="0,0,0,4" Text="Combien"/>
          <TextBox x:Name="next_how_many" AutomationProperties.Name="Combien"/>
        </StackPanel>
      </Grid>
    </StackPanel>
  </ScrollViewer>
</DockPanel>
'@

function Show-NextNameBlock {
    # The blocks as Repère understood them: those that vary colored, digits filled and letters outlined. A letter or
    # digit block is a button that switches it.
    $state = $script:NextNameDialog
    $panel = $state.Root.FindName('next_blocks')
    $panel.Children.Clear()
    $state.Root.FindName('next_blocks_panel').Visibility = ConvertTo-Visibility ($state.Blocks.Count -gt 0)
    for ($i = 0; $i -lt $state.Blocks.Count; $i++) {
        $block = $state.Blocks[$i]
        $label = if ($block.Varies) {
            if ($block.Kind -eq 'Digits') { if ($block.Length -gt 1) { (Tr '{0} chiffres') -f $block.Length } else { Tr '1 chiffre' } }
            elseif ($block.Length -gt 1) { (Tr '{0} lettres') -f $block.Length } else { Tr '1 lettre' }
        }
        elseif ($block.Kind -eq 'Text') { Tr 'séparateur' }
        else { Tr 'fixe' }
        $shown = Get-NameFormatText @(, $block)
        $text = [System.Windows.Controls.TextBlock]@{ Text = $shown; FontFamily = 'Consolas'; FontSize = 14; HorizontalAlignment = 'Center'; Name = "next_block_text_$i" }
        $note = [System.Windows.Controls.TextBlock]@{ Text = $label; FontSize = 11; HorizontalAlignment = 'Center' }
        $stack = [System.Windows.Controls.StackPanel]::new()
        $null = $stack.Children.Add($text)
        $null = $stack.Children.Add($note)
        $back, $edge, $color = if (-not $block.Varies) { 'R.Control', 'R.Border', 'R.Text' } elseif ($block.Kind -eq 'Digits') { 'R.Selection', 'R.Accent', 'R.AccentText' } else { 'R.Surface', 'R.Accent', 'R.AccentText' }
        if ($block.Locked) {
            $item = [System.Windows.Controls.Border]@{ Child = $stack; BorderThickness = 1; CornerRadius = 6; Padding = '9,4' }
            $item.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, $color)
            $item.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $back)
            $item.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, $edge)
        }
        else {
            $item = [System.Windows.Controls.Button]@{ Content = $stack; Padding = '9,4'; Name = "next_block_$i"; Tag = '6'; DataContext = $i }
            [System.Windows.Automation.AutomationProperties]::SetName($item, "$shown, $label")
            $item.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $color)
            $item.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, $back)
            $item.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, $edge)
            $item.Add_Click({
                param($button)
                $current = $script:NextNameDialog
                $chosen = $current.Blocks[[int]$button.DataContext]
                $chosen.Varies = -not $chosen.Varies
                # The field says the format the blocks now stand for, so it doesn't contradict them, and an edit goes
                # on from it. Without being read again: that would undo a block clicked fixed when nothing else varies.
                $field = $current.Root.FindName('next_format')
                $current.Updating = $true
                $field.Text = Get-NameFormatText $current.Blocks
                $field.CaretIndex = $field.Text.Length
                $current.Updating = $false
                Update-NextNameRead
                Show-NextNameBlock
            })
        }
        $item.Margin = '0,0,4,4'
        $null = $panel.Children.Add($item)
    }
}

function Show-NextNameSeries([string[]]$Name) {
    # The series AD has that start with what's typed, a click choosing one.
    $state = $script:NextNameDialog
    $panel = $state.Root.FindName('next_series')
    $panel.Children.Clear()
    $choices = @(Get-NameSeriesChoice (Get-NameTypedStart $state.Root.FindName('next_format').Text) $Name)
    $state.Root.FindName('next_series_panel').Visibility = ConvertTo-Visibility ($choices.Count -gt 0)
    $i = 0
    foreach ($choice in $choices) {
        # A text block: as a button's content, a _ would be an access key.
        $text = [System.Windows.Controls.TextBlock]@{ Text = "$($choice.Format)  ·  $($choice.Count)"; FontFamily = 'Consolas' }
        $button = [System.Windows.Controls.Button]@{ Content = $text; Name = "next_series_$i"; Margin = '0,0,4,4'; DataContext = $choice.Format }
        # The number is of names, as « déjà pris » below: the same name in two domains is two computers, said here.
        if ($choice.Accounts -gt $choice.Count) { $button.ToolTip = [string]::Format((Get-TextCulture), (Tr '{0:N0} ordinateurs : des noms sont dans plusieurs domaines'), $choice.Accounts) }
        [System.Windows.Automation.AutomationProperties]::SetName($button, $text.Text)
        $button.Add_Click({ param($clicked) $script:NextNameDialog.Root.FindName('next_format').Text = [string]$clicked.DataContext })
        $null = $panel.Children.Add($button)
        $i++
    }
}

function Get-NextNameDomain {
    # The domains ticked.
    $state = $script:NextNameDialog
    @($state.DomainBoxes | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.DataContext })
}

function Show-NextNameDomainCount {
    # What the domains' button says: all of them, or how many of how many.
    $state = $script:NextNameDialog
    $total = $state.DomainBoxes.Count
    $ticked = @(Get-NextNameDomain).Count
    $state.Root.FindName('next_domains_text').Text = if ($ticked -eq $total) { (Tr 'Tous les domaines ({0})') -f $total } else { (Tr 'Domaines : {0} sur {1}') -f $ticked, $total }
}

function Get-NextNameDomainChoice([string[]]$Domain, [string[]]$Saved, [string]$Preferred) {
    # The domains ticked as the window opens, in $Domain's spelling: those ticked last time that are still offered (a
    # domain gone from the forest, or left out with -Domains, is dropped). With none of them, $Preferred alone when it's
    # offered (the Ordinateurs page's domain, or the user's own), otherwise the first: searching every domain of a big
    # forest is slow, and rarely what's wanted.
    $kept = @($Domain | Where-Object { $_ -and $Saved -contains $_ })
    if ($kept.Count) { return $kept }
    $offered = @($Domain | Where-Object { $_ -and $_ -eq $Preferred })
    if ($offered.Count) { return @($offered[0]) }
    @($Domain | Where-Object { $_ } | Select-Object -First 1)
}

function Test-NextNameDomainShown([string]$Domain, [string]$Filter) {
    # Whether the filter box shows this domain: it contains what's typed, whatever its case.
    $text = $Filter.Trim()
    -not $text -or $Domain.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Set-NextNameDomainFilter {
    # The filter box changed: the domains that don't match are hidden, still ticked or not as they were.
    $state = $script:NextNameDialog
    $root = $state.Root
    $filter = [string]$root.FindName('next_domains_filter').Text
    # The list keeps the height it had, so the popup doesn't shrink under the pointer as the domains are filtered.
    $scroll = $root.FindName('next_domains_scroll')
    if ($filter -and -not $scroll.MinHeight) { $scroll.MinHeight = $scroll.ActualHeight }
    foreach ($box in $state.DomainBoxes) { $box.Visibility = ConvertTo-Visibility (Test-NextNameDomainShown ([string]$box.DataContext) $filter) }
    $root.FindName('next_domains_filter_clear').Visibility = ConvertTo-Visibility ([bool]$filter)
}

function Update-NextNameDomainChoice {
    # A domain ticked or unticked: the button says so, the choice is saved for next time, and the names read again.
    $state = $script:NextNameDialog
    if ($state.Updating) { return }
    Show-NextNameDomainCount
    Save-NextNameSetting
    Update-NextNameRead
}

function Set-NextNameDomain([bool]$Ticked) {
    # Tous or Aucun: one read for all the boxes the filter shows; those it hides keep their tick.
    $state = $script:NextNameDialog
    $state.Updating = $true
    foreach ($box in $state.DomainBoxes) { if ($box.Visibility -eq 'Visible') { $box.IsChecked = $Ticked } }
    $state.Updating = $false
    Update-NextNameDomainChoice
}

function Update-NextNameRead {
    # Something the result depends on changed: the result at once when the last read covers it, otherwise a read, a
    # moment after the last key.
    $state = $script:NextNameDialog
    if ($state.Updating) { return }
    $state.Timer.Stop()
    # A draw of its own, kept while SCCM is asked about it.
    $state.Seed = $state.Random.Next()
    $exclude = $state.Root.FindName('next_exclude').Text
    $domains = @(Get-NextNameDomain)
    $typed = $state.Root.FindName('next_format').Text.Trim()
    $start = Get-NameFormatStart $state.Blocks
    $state.Wanted = @{ Start = $start; Domains = $domains; Key = $domains -join ',' }
    $read = $state.Read
    $covered = $read -and $read.Key -eq $state.Wanted.Key -and $start.StartsWith($read.Start, [System.StringComparison]::Ordinal)
    if ($typed.Length -lt 2 -or -not $domains.Count -or (Get-NameFormatProblem $state.Blocks $exclude) -or $covered) {
        Stop-NextNameRead $state
        Show-NextNameResult
        return
    }
    Stop-NextNameRead $state
    Show-NextNameResult -Reading
    $state.Timer.Start()
}

function Stop-NextNameRead($State) {
    # A change made the read under way useless: ReadId tells its OnDone so, and it's stopped, so that a slow DC or SCCM
    # doesn't keep a search runspace, which the main window's searches wait for, until it answers.
    $State.ReadId++
    Stop-BackgroundRead $State
}

function Start-NextNameRead {
    # The read Update-NextNameRead asked for. A later change makes its answer useless: ReadId says so.
    $state = $script:NextNameDialog
    $state.Timer.Stop()
    if (-not $state -or $state.Closed) { return }
    $wanted = $state.Wanted
    Stop-NextNameRead $state
    Start-BackgroundRead -Command 'Get-NextNameRead' -Arguments @($wanted.Start, $wanted.Domains) `
        -Context @{ State = $state; Id = $state.ReadId; Wanted = $wanted } -OnDone {
        param($context, $read, $problem)
        $state = $context.State
        if ($state.Closed -or $context.Id -ne $state.ReadId) { return }
        if ($problem -or -not $read) {
            $state.Read = $null
            Show-NextNameResult -Problem $(if ($problem) { ConvertTo-FrenchError $problem } else { Tr 'AD n''a rien renvoyé' })
            return
        }
        $state.Read = @{ Key = $context.Wanted.Key; Start = $context.Wanted.Start; Names = @($read.Names); Failed = @($read.Failed) }
        Show-NextNameResult
    }
}

function Reset-NextNameSccm($State) {
    # What SCCM said of names, forgotten (Rechercher, or its box ticked again), and its check under way let go of:
    # Taken, the names SCCM has, Free, those it doesn't (with the account's access), Reason when it couldn't be asked,
    # Rounds, how many times in a row it was asked for the names given.
    if ($State.SccmCheck) { Stop-BackgroundRead $State.SccmCheck }
    $State.SccmCheck = $null
    $State.SccmNames = @{
        Taken = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Free = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Reason = ''; Rounds = 0
    }
}

function Start-NextNameSccmCheck($State, [string[]]$Name) {
    # Asks SCCM which of these names it has, by their names, so that no answer comes near its limit of rows. What it says
    # is kept until Rechercher (SccmNames), whatever changes meanwhile: a name SCCM has stays one. One check at a time,
    # which a change doesn't stop; once it's answered, the names shown are worked out again, and the next is asked if
    # they still need it.
    if ($State.SccmCheck -or -not $Name.Count) { return }
    $context = @{ Dialog = $State; Known = $State.SccmNames; Name = $Name }
    $State.SccmCheck = $context
    Start-BackgroundRead -Command 'Get-SccmName' -Arguments @($State.Sccm, $Name) `
        -Functions (Get-SccmReadFunction) -Variables (Get-SccmReadVariable) -Timeout (Get-SccmReadTimeout) -Context $context -OnDone {
        param($context, $read, $problem)
        # It may have run out of time, or been stopped.
        Start-SccmStopSweep
        $state = $context.Dialog
        if ([object]::ReferenceEquals($state.SccmCheck, $context)) { $state.SccmCheck = $null }
        if ($state.Closed -or -not [object]::ReferenceEquals($state.SccmNames, $context.Known)) { return }
        $known = $context.Known
        if ($problem -or -not $read) { $known.Reason = if ($problem) { ConvertTo-FrenchError $problem } else { Tr 'sa réponse n''est pas lisible' } }
        elseif (-not $read.Checked) { $known.Reason = $read.Reason }
        else {
            $have = @($read.Names)
            foreach ($name in $context.Name) { if ($name -in $have) { $null = $known.Taken.Add($name) } else { $null = $known.Free.Add($name) } }
            $known.Rounds++
        }
        Show-NextNameResult
    }
}

function Start-NextNameSearch {
    # Rechercher: a new read now, even when the last one covers this format, for a computer added since, and SCCM asked
    # again.
    $state = $script:NextNameDialog
    $state.Read = $null
    Reset-NextNameSccm $state
    Update-NextNameRead
    if ($state.Timer.IsEnabled) { Start-NextNameRead }
}

function Get-NextNameCount {
    # How many names are asked for, or 0 when what's typed can't be: Combien says so.
    $count = 0
    $state = $script:NextNameDialog
    if ([int]::TryParse($state.Root.FindName('next_how_many').Text, [ref]$count) -and $count -ge 1 -and $count -le $script:NextNameCountLimit) { return $count }
    0
}

function Show-NextNameResult {
    # The names for this format from the last read, or why there are none, and what SCCM said. Also the series offered,
    # which come from the same read.
    param([switch]$Reading, [string]$Problem = '')
    $state = $script:NextNameDialog
    $root = $state.Root
    $set = {
        param($name, $text)
        $block = $root.FindName($name)
        $block.Text = $text
        $block.Visibility = ConvertTo-Visibility ([bool]$text)
    }
    $names = @()
    $exclude = $root.FindName('next_exclude').Text
    $random = $root.FindName('next_order').SelectedIndex -eq 1
    $varies = @($state.Blocks | Where-Object { $_.Varies }).Count -gt 0
    $root.FindName('next_result_label').Text = if ($state.Blocks.Count -and -not $varies) { Tr 'Ce nom exact' } else { Tr 'Prochain nom libre' }
    $root.FindName('next_gaps').IsEnabled = -not $random
    Set-TextBoxUse $root.FindName('next_from') (-not $random) (Tr 'En ordre aléatoire, il n''y a pas de point de départ.')
    $root.FindName('next_name').Text = ''
    foreach ($name in 'next_more', 'next_count_text', 'next_domain_note', 'next_sccm_result') { & $set $name '' }
    $typed = $root.FindName('next_format').Text.Trim()
    $read = $state.Read
    $covered = $read -and $state.Wanted -and $read.Key -eq $state.Wanted.Key -and (Get-NameFormatStart $state.Blocks).StartsWith($read.Start, [System.StringComparison]::Ordinal)
    if ($Problem) { }
    elseif (-not $typed) { }
    elseif ($typed.Length -lt 2) { $Problem = Tr 'Tapez au moins 2 caractères.' }
    elseif (Get-NameFormatProblem $state.Blocks $exclude) { $Problem = Get-NameFormatProblem $state.Blocks $exclude }
    elseif (-not @(Get-NextNameDomain).Count) { $Problem = Tr 'Cochez au moins un domaine.' }
    elseif (-not (Get-NextNameCount)) { $Problem = (Tr 'Combien : de 1 à {0}.') -f $script:NextNameCountLimit }
    elseif ($Reading -or -not $covered) { $root.FindName('next_name').Text = Tr 'Lecture…' }
    elseif (-not $read.Names.Count -and $read.Failed.Count -eq @(Get-NextNameDomain).Count) {
        $Problem = (Tr 'Aucun domaine n''a répondu : {0}') -f (Get-FailedDomainText $read.Failed)
    }
    else {
        $series = New-NameSeries $state.Blocks $exclude
        # SCCM is asked only about the names to give (Start-NextNameSccmCheck): one it has is skipped, without moving
        # where the series goes on from, and what it hasn't said yet holds the names back.
        $sccm = if ($root.FindName('next_sccm_check').IsChecked) { $state.Sccm }
        $known = $state.SccmNames
        $from = $root.FindName('next_from').Text.Trim()
        if ($from -and -not $random -and $varies -and -not $series.Regex.IsMatch($from)) { $Problem = Tr 'Commencer à : ce nom ne suit pas le modèle.' }
        else {
            $count = Get-NextNameCount
            # With SCCM, the next ones too, asked with them: should it have some, one answer is most often enough.
            $options = @{ Series = $series; TakenName = @($read.Names); Count = $(if ($sccm) { [math]::Max($count, $script:SccmBatchSize) } else { $count }) }
            if ($sccm) { $options.Skip = @($known.Taken) }
            # The same draw from one answer of SCCM to the next: only the names it has give way.
            if ($random) { $options.Random = [System.Random]::new($state.Seed) }
            elseif ($varies) {
                $options.FillGaps = $root.FindName('next_gaps').SelectedIndex -eq 1
                if ($from) { $options.From = $from }
            }
            $found = Get-NextName @options
            $names = @($found.Names | Select-Object -First $count)
            $shown = if ($varies) { $names } else { @($series.Template) }
            $unknown = @($(if ($varies) { $found.Names } else { $shown }) | Where-Object { -not $known.Taken.Contains($_) -and -not $known.Free.Contains($_) })
            $asking = $sccm -and -not $known.Reason -and @($shown | Where-Object { $_ -in $unknown }).Count -gt 0
            if ($asking -and $known.Rounds -ge $script:NextNameSccmRounds) {
                $known.Reason = Tr 'trop de noms de suite sont déjà dans SCCM'
                $asking = $false
            }
            if ($asking) {
                $root.FindName('next_name').Text = Tr 'Lecture…'
                Start-NextNameSccmCheck $state $unknown
                $names = @()
            }
            else {
                $known.Rounds = 0
                if ($varies) {
                    if ($names.Count) {
                        $root.FindName('next_name').Text = $names[0]
                        & $set 'next_more' ($names | Select-Object -Skip 1 | Join-String -Separator ', ')
                    }
                    else { $Problem = Tr 'Cette série est pleine.' }
                    & $set 'next_count_text' ([string]::Format((Get-TextCulture), (Tr '{0:N0} noms possibles, {1:N0} déjà pris'), $series.Count, $found.Taken))
                }
                else {
                    $root.FindName('next_name').Text = $series.Template
                    $inAd = @($read.Names | Where-Object { $series.Regex.IsMatch($_) }).Count -gt 0
                    & $set 'next_count_text' $(if ($inAd) { Tr 'Déjà pris dans l''AD.' } else { Tr 'Libre dans l''AD.' })
                }
                Show-NextNameSccm $sccm $known $series $shown $varies
            }
        }
        if ($read.Failed.Count) { & $set 'next_domain_note' ((Tr 'Non vérifié dans : {0}') -f (Get-FailedDomainText $read.Failed)) }
    }
    if ($covered) { Show-NextNameSeries @($read.Names) } else { Show-NextNameSeries @() }
    & $set 'next_problem' $Problem
    $state.Names = @($names)
    $root.FindName('next_copy').IsEnabled = $names.Count -gt 0
}

function Show-NextNameSccm($Sccm, $Known, $Series, [string[]]$Name, [bool]$Varies) {
    # What SCCM said of the names given, in its three cases, which never read alike: in SCCM, not found there (with the
    # account's access: SCCM doesn't say what it hides), and couldn't be asked. The names it has were skipped.
    if (-not $Sccm) { return }
    $block = $script:NextNameDialog.Root.FindName('next_sccm_result')
    $block.Visibility = 'Visible'
    if ($Known.Reason) {
        $block.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'R.WarnText')
        $block.Text = (Tr 'Vérification SCCM impossible : {0}. Non vérifié dans SCCM.') -f $Known.Reason
        return
    }
    $block.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'R.Muted')
    if (-not $Varies) { $block.Text = if ($Known.Taken.Contains($Series.Template)) { Tr 'Dans SCCM.' } else { Tr 'Introuvable dans SCCM (avec vos accès).' } }
    elseif (-not $Name.Count) { $block.Text = '' }
    else { $block.Text = Tr 'Introuvable dans SCCM (avec vos accès).' }
    $block.Visibility = ConvertTo-Visibility ([bool]$block.Text)
}

function Save-NextNameSetting {
    # The options as they're set, and the recent formats. What can't be read keeps what was saved.
    $state = $script:NextNameDialog
    $root = $state.Root
    $count = Get-NextNameCount
    $setting = [ordered]@{
        Recent = @($state.Recent | ForEach-Object { , @($_) }); Random = $root.FindName('next_order').SelectedIndex -eq 1
        FillGaps = $root.FindName('next_gaps').SelectedIndex -eq 1; Count = $(if ($count) { $count } else { 3 })
        Exclude = $root.FindName('next_exclude').Text; Sccm = [bool]$root.FindName('next_sccm_check').IsChecked
        Domains = @(Get-NextNameDomain)
    }
    if (-not $state.Sccm) { $setting.Sccm = $state.SavedSccm }
    Save-JsonSetting $script:NextNameSettingPath $setting -Depth 5
}

function Update-NextNameRecent {
    # The recent formats' menu, each with its blocks as they were.
    $state = $script:NextNameDialog
    $menu = $state.Root.FindName('next_recent_menu')
    $menu.Items.Clear()
    $state.Root.FindName('next_recent').Visibility = ConvertTo-Visibility ($state.Recent.Count -gt 0)
    foreach ($format in $state.Recent) {
        # A text block: as a menu item's header, a _ would be an access key.
        $item = [System.Windows.Controls.MenuItem]@{ Header = [System.Windows.Controls.TextBlock]@{ Text = (Get-NameFormatText $format) }; DataContext = @{ Blocks = @($format) } }
        $item.Add_Click({ param($clicked) Set-NextNameFormat $clicked.DataContext.Blocks })
        $null = $menu.Items.Add($item)
    }
}

function Set-NextNameFormat($Blocks) {
    # A saved format in the field: its blocks are the ones used, not what the field's text would give.
    $state = $script:NextNameDialog
    $state.Updating = $true
    $state.Root.FindName('next_format').Text = Get-NameFormatText $Blocks
    $state.Updating = $false
    $state.Blocks = @(foreach ($block in $Blocks) { $block.Clone() })
    Show-NextNameBlock
    Update-NextNameRead
}

function Copy-NextName {
    # The first name; the format joins the recent ones, used at last.
    $state = $script:NextNameDialog
    if (-not $state.Names.Count) { return }
    Set-Clipboard -Value $state.Names[0]
    $state.Root.FindName('next_status').Text = (Tr '{0} copié.') -f $state.Names[0]
    $state.Recent = @(Add-RecentNameFormat $state.Blocks $state.Recent)
    Update-NextNameRecent
}

function Resume-NextNameDialog {
    # Paramètres hidden after Configurer…: Prochain nom again, on the format it had. Not when Repère is closing, nor
    # when Prochain nom was opened again meanwhile (that dropped the way back).
    $back = $script:NextNameReturn
    if (-not $back -or $script:Settings.Exiting) { $script:NextNameReturn = $null; return }
    # Once Paramètres is hidden, not within its own change of visibility.
    $null = $back.Owner.Dispatcher.BeginInvoke([Action]{
        $back = $script:NextNameReturn
        if ($back) { Show-NextNameDialog $back.Owner $back.Icon $back.Blocks }
    })
}

function Show-NextNameDialog($Owner, $Icon, $Blocks, [string]$PageDomain, [string]$Name) {
    # $Blocks: the format to open on, when coming back from Paramètres. $Name: a computer's, typed in the field as the
    # user would, so it becomes its series (ORD-0143, ORD-####); it joins the recent formats only once used, like any.
    # Without either, the last format used. $PageDomain: the computer's domain or the Ordinateurs page's, ticked the
    # first time when no choice was saved (Get-NextNameDomainChoice).
    $script:NextNameReturn = $null
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:NextNameXaml))
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = Tr 'Prochain nom'
    $dialog.Icon = $Icon
    $dialog.Owner = $Owner
    $dialog.Width = 620
    $dialog.MinWidth = 560
    # A height of its own, not its content's: the series, the blocks, the names and SCCM's line appear as a format is
    # typed, and the buttons would move under the pointer between two clicks. Room for all of them (Options scroll
    # into view), within the screen; at a larger text, more. Opened low on the screen, or on a smaller one, it's moved
    # up or shortened to stay above the taskbar (Set-WindowChrome, Set-WindowInWorkArea).
    $area = [System.Windows.SystemParameters]::WorkArea
    $dialog.Height = [Math]::Min($script:NextNameHeight * $script:UiScale.ScaleY, $area.Height - 40)
    $dialog.MinHeight = [Math]::Min(400, $dialog.Height)
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.Content = $root
    Set-WindowChrome $dialog -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')

    $setting = Read-NextNameSetting
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(300)
    $timer.Add_Tick({ Start-NextNameRead })
    $script:NextNameDialog = @{
        Root = $root; Dialog = $dialog; Blocks = @(); Names = @(); Read = $null; Wanted = $null; ReadId = 0; Timer = $timer; Closed = $false
        Updating = $true; Random = [System.Random]::new(); Seed = 0; Recent = @($setting.Recent); Sccm = (Read-SccmSetting); SavedSccm = $setting.Sccm
        DomainBoxes = @(); OpenSettings = $false; DomainsClosedAt = [datetime]::MinValue; SccmNames = $null; SccmCheck = $null
    }
    $state = $script:NextNameDialog
    Reset-NextNameSccm $state

    # A few domains are ticked in place; more would fill the window: they go in the button's popup.
    $domainCount = @($script:domainList).Count
    $listed = $domainCount -gt $script:NextNameDomainsInPlace
    $domainPanel = $root.FindName($(if ($listed) { 'next_domains_list' } else { 'next_domains' }))
    $root.FindName('next_domains').Visibility = ConvertTo-Visibility ($domainCount -gt 1 -and -not $listed)
    $root.FindName('next_domains_button').Visibility = ConvertTo-Visibility $listed
    $changed = { Update-NextNameDomainChoice }
    $preferred = if (@($script:domainList) -contains $PageDomain) { $PageDomain } else { $script:defaultDomain }
    $ticked = @(Get-NextNameDomainChoice @($script:domainList) $setting.Domains $preferred)
    $i = 0
    $state.DomainBoxes = @(foreach ($domain in $script:domainList) {
            $box = [System.Windows.Controls.CheckBox]@{ Content = [System.Windows.Controls.TextBlock]@{ Text = $domain }; IsChecked = ($ticked -contains $domain); Margin = $(if ($listed) { '0,0,0,6' } else { '0,0,14,0' }); Name = "next_domain_$i"; DataContext = $domain }
            [System.Windows.Automation.AutomationProperties]::SetName($box, $domain)
            $box.Add_Checked($changed)
            $box.Add_Unchecked($changed)
            $null = $domainPanel.Children.Add($box)
            $i++
            $box
        })
    Show-NextNameDomainCount
    $popup = $root.FindName('next_domains_popup')
    $popup.Child.LayoutTransform = $script:UiScale
    # A click on the button opens the popup, or closes it (the click outside it has already, a moment before).
    $root.FindName('next_domains_button').Add_Click({
        $current = $script:NextNameDialog
        if (([datetime]::Now - $current.DomainsClosedAt).TotalMilliseconds -lt 250) { return }
        $current.Root.FindName('next_domains_popup').IsOpen = $true
    })
    # Opened, the filter box has the focus, so a few letters find a domain. Closed, the filter is emptied: reopened, the
    # list shows every domain, none ticked out of sight.
    $popup.Add_Opened({
        $null = $script:NextNameDialog.Root.Dispatcher.BeginInvoke([Action]{
            $current = $script:NextNameDialog
            if ($current) { $null = $current.Root.FindName('next_domains_filter').Focus() }
        }, [System.Windows.Threading.DispatcherPriority]::Input)
    })
    $popup.Add_Closed({
        $current = $script:NextNameDialog
        # The window closing with the popup open closes it too, after the window's state is gone.
        if (-not $current) { return }
        $current.DomainsClosedAt = [datetime]::Now
        $current.Root.FindName('next_domains_filter').Text = ''
    })
    $filterBox = $root.FindName('next_domains_filter')
    $filterBox.Add_TextChanged({ Set-NextNameDomainFilter })
    # ↓ goes from the filter box to the first domain it shows; Tab to Tous, as the boxes come next.
    $filterBox.Add_PreviewKeyDown({
        $e = $args[1]
        if ($e.Key -ne 'Down') { return }
        $first = @($script:NextNameDialog.DomainBoxes | Where-Object { $_.Visibility -eq 'Visible' }) | Select-Object -First 1
        if ($first) { $null = $first.Focus(); $e.Handled = $true }
    })
    $root.FindName('next_domains_filter_clear').Add_Click({
        $box = $script:NextNameDialog.Root.FindName('next_domains_filter')
        $box.Text = ''
        $null = $box.Focus()
    })
    # Échap empties the filter first, then closes the popup, never the window: on the window, since the focus often
    # stays there, and it sees the key before the popup's controls do.
    $dialog.Add_PreviewKeyDown({
        $e = $args[1]
        $parts = $script:NextNameDialog.Root
        $open = $parts.FindName('next_domains_popup')
        if ($e.Key -eq 'Escape' -and $open.IsOpen) {
            $filter = $parts.FindName('next_domains_filter')
            if ($filter.Text) { $filter.Text = '' } else { $open.IsOpen = $false }
            $e.Handled = $true
        }
    })
    $root.FindName('next_domains_all').Add_Click({ Set-NextNameDomain $true })
    $root.FindName('next_domains_none').Add_Click({ Set-NextNameDomain $false })
    $check = $root.FindName('next_sccm_check')
    $check.IsEnabled = [bool]$state.Sccm
    $check.IsChecked = $state.Sccm -and $setting.Sccm
    $root.FindName('next_sccm_setup').Visibility = ConvertTo-Visibility (-not $state.Sccm)
    $root.FindName('next_sccm_setup').Add_Click({
        $script:NextNameDialog.OpenSettings = $true
        $script:NextNameDialog.Dialog.Close()
    })
    # Ticked again: asked again, should it have failed.
    $check.Add_Checked({ Reset-NextNameSccm $script:NextNameDialog; Update-NextNameRead })
    $check.Add_Unchecked({ Update-NextNameRead })
    $root.FindName('next_order').SelectedIndex = [int]$setting.Random
    $root.FindName('next_gaps').SelectedIndex = [int]$setting.FillGaps
    $root.FindName('next_how_many').Text = "$($setting.Count)"
    $root.FindName('next_exclude').Text = $setting.Exclude
    Update-NextNameRecent

    $root.FindName('next_format').Add_TextChanged({
        $current = $script:NextNameDialog
        if ($current.Updating) { return }
        $current.Blocks = @(ConvertTo-NameFormat $current.Root.FindName('next_format').Text)
        Show-NextNameBlock
        Update-NextNameRead
    })
    foreach ($control in 'next_from', 'next_exclude', 'next_how_many') { $root.FindName($control).Add_TextChanged({ Update-NextNameRead }) }
    foreach ($control in 'next_order', 'next_gaps') { $root.FindName($control).Add_SelectionChanged({ Update-NextNameRead }) }
    $root.FindName('next_how_many').Add_PreviewTextInput({ $e = $args[1]; if ($e.Text -notmatch '^\d+$') { $e.Handled = $true } })
    $showOptions = {
        $parts = $script:NextNameDialog.Root
        $panel = $parts.FindName('next_options_panel')
        $panel.Visibility = ConvertTo-Visibility ([bool]$parts.FindName('next_options').IsChecked)
        # Opened at the bottom of a small window: scrolled to, once it's laid out.
        if ($panel.Visibility -eq 'Visible') { $null = $panel.Dispatcher.BeginInvoke([Action]{ $script:NextNameDialog.Root.FindName('next_options_panel').BringIntoView() }, [System.Windows.Threading.DispatcherPriority]::Loaded) }
    }
    $root.FindName('next_options').Add_Checked($showOptions)
    $root.FindName('next_options').Add_Unchecked($showOptions)
    $root.FindName('next_recent').Add_Click({
        param($button)
        $button.ContextMenu.PlacementTarget = $button
        $button.ContextMenu.IsOpen = $true
    })
    $root.FindName('next_search').Add_Click({ Start-NextNameSearch })
    $root.FindName('next_copy').Add_Click({ Copy-NextName })

    # Open on the last format used: most people have one scheme, and its next name is what they came for.
    $state.Updating = $false
    if ($Blocks) { Set-NextNameFormat $Blocks }
    elseif ($Name) {
        # Not Set-NextNameFormat: the field's own reading of a real name, as when it's typed.
        $root.FindName('next_format').Text = $Name
    }
    elseif ($state.Recent.Count) { Set-NextNameFormat $state.Recent[0] }
    else { Update-NextNameRead }
    $dialog.Add_ContentRendered({
        $field = $script:NextNameDialog.Root.FindName('next_format')
        $null = $field.Focus()
        $field.SelectAll()
    })

    $script:search.Dialogs++
    try { $null = $dialog.ShowDialog() }
    finally {
        $script:search.Dialogs--
        $state.Closed = $true
        $timer.Stop()
        Stop-BackgroundRead $state
        if ($state.SccmCheck) { Stop-BackgroundRead $state.SccmCheck }
        Save-NextNameSetting
        $script:NextNameDialog = $null
    }
    if ($state.OpenSettings) {
        # Configurer…: Paramètres › SCCM, then back here once it's closed, with the site it may now have.
        Show-SettingsWindow 'sccm'
        $script:NextNameReturn = @{ Owner = $Owner; Icon = $Icon; Blocks = @(foreach ($block in $state.Blocks) { $block.Clone() }) }
        if (-not $script:NextNameReturnHooked) {
            $script:NextNameReturnHooked = $true
            $script:Settings.Window.Add_IsVisibleChanged({ param($window, $e) if (-not $e.NewValue) { Resume-NextNameDialog } })
        }
    }
}
