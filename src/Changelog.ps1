# Nouveautés: what this version brought, as the headlines of its CHANGELOG.md entry (in the zip, beside src), in a
# window of its own once the main window shows, the first time a newer Repère starts (#9). Each section lists its
# first points' headlines and how many others it has; « Voir le détail » opens the version's release on GitHub, which
# is that whole entry. It opens once per version, for everyone; Paramètres' « Nouveautés » opens it whenever.
# Dot-sourced by the main script, after SettingsWindow.ps1.

$script:ChangelogPath = Join-Path (Split-Path $PSScriptRoot) 'CHANGELOG.md'
$script:ChangelogSettingPath = Get-SettingPath 'parametres.json'
$script:ChangelogReleaseUrl = 'https://github.com/reperedev/Repere/releases/tag/v{0}'
# The headlines a section lists; « et 6 autres » says how many more it has.
$script:ChangelogShown = 3
# The window open (Show-ChangelogWindow), if one is; its list, and its tabs (Add-ChangelogTab), each its Tab and the
# Card it goes to. ChangelogJump: a tab's click is scrolling, which leaves its tab checked.
$script:ChangelogWindow = $null
$script:ChangelogScroll = $null
$script:ChangelogTabs = [System.Collections.Generic.List[object]]::new()
$script:ChangelogJump = $false

$script:ChangelogXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
           Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <!-- Also the window's title bar (Set-WindowChrome), its buttons at the end: Fermer's X among them. -->
  <!-- Its sections' tabs under the title (changelog_tabs, with 2 sections or more): a click goes to the section, and the
       one read is checked as the list scrolls. -->
  <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="16,12,0,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <WrapPanel x:Name="changelog_tabs" Grid.Row="1" Grid.ColumnSpan="2" Margin="-4,10,16,-4" Visibility="Collapsed"/>
      <DockPanel VerticalAlignment="Center">
        <Border DockPanel.Dock="Left" Width="38" Height="38" CornerRadius="8" Background="{DynamicResource R.Selection}" TextElement.Foreground="{DynamicResource R.AccentText}">
          <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:info:20}}</Grid>
        </Border>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" TextTrimming="CharacterEllipsis" Text="Nouveautés"/>
          <TextBlock x:Name="changelog_subtitle" Style="{StaticResource Txt.Muted}" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </DockPanel>
      <StackPanel x:Name="caption_buttons" Grid.Column="1" Orientation="Horizontal" Margin="12,-12,0,-12"/>
    </Grid>
  </Border>
  <Border DockPanel.Dock="Bottom" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,1,0,0" Padding="16,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock VerticalAlignment="Center" Margin="0,0,14,0"><Hyperlink x:Name="changelog_detail" AutomationProperties.AutomationId="changelog_detail">Voir le détail</Hyperlink></TextBlock>
      <Button x:Name="dialog_cancel" Grid.Column="2" Style="{StaticResource Btn.Primary}" MinWidth="90" IsDefault="True" IsCancel="True" Content="Fermer"/>
    </Grid>
  </Border>
  <ScrollViewer x:Name="changelog_scroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <StackPanel x:Name="changelog_body" Margin="16,14,16,6"/>
  </ScrollViewer>
</DockPanel>
'@

function Read-ChangelogEntry([string]$Path) {
    # The versions CHANGELOG.md describes, as it lists them (newest first): each its Version, its Heading (« 0.15.0 —
    # 2026-11-19 ») and its Lines. Not « À venir », which isn't out yet. None when the file can't be read (a copy of
    # src without it).
    $lines = try { [System.IO.File]::ReadAllLines($Path) } catch { @() }
    $entry = $null
    foreach ($line in $lines) {
        if ($line -match '^## ') {
            $entry = $null
            if ($line -match '^## (\d+\.\d+\.\d+)\b') {
                $entry = [pscustomobject]@{ Version = [version]$Matches[1]; Heading = $line.Substring(3).Trim(); Lines = [System.Collections.Generic.List[string]]::new() }
                $entry
            }
        }
        elseif ($entry) { $entry.Lines.Add($line) }
    }
}

function Get-ChangelogEntry([string]$Path, [string]$Version) {
    # $Version's entry in CHANGELOG.md; $null when it has none (a build between releases) or can't be read. Read whole
    # first: Read-ChangelogEntry gives an entry at its heading, and fills its Lines after.
    @(Read-ChangelogEntry $Path) | Where-Object Version -EQ ([version]$Version) | Select-Object -First 1
}

function Get-ChangelogSeen($Saved) {
    # parametres.json's SeenVersion ($Saved, $null without the file) as a version: $null without one, or with one that
    # doesn't read as x.y.z (edited by hand, too big for a version).
    $seen = $null
    if ($Saved -and "$($Saved.SeenVersion)" -match '^\d+\.\d+\.\d+$' -and [version]::TryParse($Saved.SeenVersion, [ref]$seen)) { return $seen }
    $null
}

function Test-ChangelogStart($Saved, [bool]$HadSettings, [string]$Current) {
    # Whether this start opens Nouveautés: the first start of a version newer than the one seen ($Saved, see
    # Get-ChangelogSeen), or of this one after a Repère that saved none (0.15.0 and earlier). Not a new install (no
    # $HadSettings), the same version again, nor an older one.
    $seen = Get-ChangelogSeen $Saved
    if ($seen) { return $seen -lt [version]$Current }
    $HadSettings
}

# The first comma after these doesn't end a headline: what comes before it only sets the scene (« Apr\u00e8s une action
# réussie sur plusieurs utilisateurs, la notification… »). In \u: the code is ASCII.
$script:ChangelogSceneWord = '^(Apr\u00e8s|Avant|Quand|Lorsque|Si|D\u00e8s|Depuis|Pendant|Sans|Avec|Dans|Pour|Hors|Au|Aux|En|Sur|Sous)\b'

function Get-ChangelogWordCount([string]$Text) { @(($Text -replace '\*\*|`') -split '\s+' | Where-Object { $_ }).Count }

function Test-ChangelogLabel([string]$Head) {
    # Whether $Head only names what the point is about, so a « : » after it doesn't end the headline: a name in bold of 3
    # words at most (« **Propriétés** »), names in bold one after the other (« **Propriétés**, **Caractéristiques** et
    # **Comparer les groupes** »), or 2 words at most (« Actions »).
    $bolds = [regex]::Matches($Head, '\*\*[^*]+\*\*').Count
    $rest = $Head -replace '\*\*[^*]+\*\*'
    if ($bolds -ge 2) { return $rest -match '^(\s*(,|et)\s*)*$' }
    if ($bolds -eq 1) { return -not $rest.Trim() -and (Get-ChangelogWordCount $Head) -le 3 }
    (Get-ChangelogWordCount $Head) -le 2
}

function Get-ChangelogHeadline([string]$Text) {
    # A point's headline, kept short: the sentence in bold that starts it (6 words or more), else its first sentence, up
    # to « . », « : » or « ; », or a comma once it has 8 words; never inside bold, « », ( ) or `code`. A « : » past a
    # name that starts it (Test-ChangelogLabel) doesn't end it: « **Propriétés** : au-delà de 10 groupes… ». Not its asides
    # in ( ), which are detail, unless they're all it says of its name (« **Utilisateurs connectés…** (clic droit) »).
    if ($Text -match '^\*\*([^*]+)\*\*' -and @($Matches[1].Trim() -split '\s+').Count -ge 6) { return $Matches[0] }
    $quote = 0
    $paren = 0
    $code = $false
    $bold = $false
    # Where each aside starts and ends: ( ) outside bold, « » and code.
    $asides = [System.Collections.Generic.List[int[]]]::new()
    $aside = -1
    $commas = 0
    $cut = $Text.Length
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { '' }
        if ($char -eq '`') { $code = -not $code; continue }
        if ($code) { continue }
        if ($char -eq '*' -and $next -eq '*') { $bold = -not $bold; $i++; continue }
        if ($char -eq [char]0xAB) { $quote++; continue }  # «
        if ($char -eq [char]0xBB) { $quote--; continue }  # »
        if ($char -eq '(') {
            if ($paren -eq 0 -and -not $bold -and $quote -le 0) { $aside = $i }
            $paren++
            continue
        }
        if ($char -eq ')' -and $paren -gt 0) {
            $paren--
            if ($paren -eq 0 -and $aside -ge 0) { $asides.Add(@($aside, $i)); $aside = -1 }
            continue
        }
        if ($bold -or $quote -gt 0 -or $paren -gt 0 -or $next -ne ' ') { continue }
        $end = $char -eq '.' -or ($char -in ':', ';' -and $i -gt 0 -and $Text[$i - 1] -eq ' ')
        if (-not $end -and $char -ne ',') { continue }
        $head = Remove-ChangelogAside $Text.Substring(0, $i).TrimEnd() $asides
        if ($end -and -not ($char -eq ':' -and (Test-ChangelogLabel $head))) { $cut = $i; break }
        if ($end) { continue }
        $commas++
        if ((Get-ChangelogWordCount $head) -ge 8 -and ($commas -gt 1 -or ($head -replace '\*\*') -notmatch $script:ChangelogSceneWord)) { $cut = $i; break }
    }
    $head = $Text.Substring(0, $cut).Trim()
    $short = Remove-ChangelogAside $head $asides
    if (Test-ChangelogLabel $short.TrimEnd('.', ':', ' ')) { $short = $head }
    # A name and its « : » alone, its list below (« **Caractéristiques** : »): the name.
    $short.TrimEnd('.', ':', ';', ' ')
}

function Remove-ChangelogAside([string]$Head, $Asides) {
    # $Head without the asides ($Asides, where each starts and ends) it has whole, nor the space before each.
    $whole = @($Asides | Where-Object { $_[1] -lt $Head.Length })
    if (-not $whole) { return $Head }
    $text = [System.Text.StringBuilder]::new()
    $from = 0
    foreach ($aside in $whole) {
        $null = $text.Append($Head, $from, $aside[0] - $from)
        $from = $aside[1] + 1
    }
    $null = $text.Append($Head, $from, $Head.Length - $from)
    ($text.ToString() -replace '  +', ' ' -replace ' ([,.])', '$1').Trim()
}

function Get-ChangelogSummary($Entry, [int]$Shown = $script:ChangelogShown) {
    # The entry as the window shows it: each section (### ; a #### one counts in it) with the Headlines of its first
    # $Shown points, and those of the Rest, which « et 6 autres » shows (Others, how many). Not the sub-points nor the
    # paragraphs, which are the detail; but a point that's only a name and « : » (« **Caractéristiques** : ») has its
    # first sub-point's headline after it.
    $all = $null
    $section = $null
    $sections = [System.Collections.Generic.List[object]]::new()
    $named = -1
    foreach ($line in $Entry.Lines) {
        if ($line -match '^###\s+(.+)$') {
            $all = [System.Collections.Generic.List[string]]::new()
            $sections.Add([pscustomobject]@{ Name = $Matches[1].Trim(); All = $all })
            $named = -1
        }
        elseif ($line -match '^[-*]\s+(.+)$') {
            $text = $Matches[1]
            if ($null -eq $all) {
                $all = [System.Collections.Generic.List[string]]::new()
                $sections.Add([pscustomobject]@{ Name = ''; All = $all })
            }
            $headline = Get-ChangelogHeadline $text
            $all.Add($headline)
            $named = if ($text -match '\s:\s*$' -and (Test-ChangelogLabel $headline)) { $all.Count - 1 } else { -1 }
        }
        elseif ($named -ge 0 -and $line -match '^\s+[-*]\s+(.+)$') {
            $all[$named] = "$($all[$named]) : $(Get-ChangelogHeadline $Matches[1])"
            $named = -1
        }
    }
    foreach ($section in $sections) {
        $count = [Math]::Min($Shown, $section.All.Count)
        [pscustomobject]@{
            Name = $section.Name
            Headlines = [System.Collections.Generic.List[string]]$section.All.GetRange(0, $count)
            Rest = [System.Collections.Generic.List[string]]$section.All.GetRange($count, $section.All.Count - $count)
            Others = $section.All.Count - $count
        }
    }
}

function ConvertFrom-ChangelogInline([string]$Text, [bool]$Bold = $false) {
    # A line's Markdown as parts, each its Text, its Kind (Italic for *…*, Code for `…`, else Plain) and whether it's
    # Bold (**…**, which can hold code: « **Un `parametres.json` illisible** »).
    foreach ($part in [regex]::Split($Text, '(\*\*.+?\*\*|`[^`]+`|\*[^*\s][^*]*\*)')) {
        if (-not $part) { continue }
        if (-not $Bold -and $part.Length -gt 4 -and $part.StartsWith('**') -and $part.EndsWith('**')) {
            ConvertFrom-ChangelogInline $part.Substring(2, $part.Length - 4) $true
            continue
        }
        $kind = 'Plain'
        if ($part.Length -gt 2 -and $part.StartsWith('`') -and $part.EndsWith('`')) { $kind = 'Code' }
        elseif ($part.Length -gt 2 -and $part.StartsWith('*') -and $part.EndsWith('*')) { $kind = 'Italic' }
        [pscustomobject]@{ Kind = $kind; Bold = $Bold; Text = $(if ($kind -eq 'Plain') { $part } else { $part.Substring(1, $part.Length - 2) }) }
    }
}

function New-ChangelogText([string]$Text) {
    # A wrapping text block of a headline, its Markdown as bold, italic and Consolas runs.
    $block = [System.Windows.Controls.TextBlock]::new()
    $block.TextWrapping = 'Wrap'
    foreach ($part in ConvertFrom-ChangelogInline $Text) {
        $run = [System.Windows.Documents.Run]::new($part.Text)
        if ($part.Bold) { $run.SetResourceReference([System.Windows.Documents.TextElement]::FontWeightProperty, 'R.FontWeightStrong') }
        if ($part.Kind -eq 'Italic') { $run.FontStyle = 'Italic' }
        if ($part.Kind -eq 'Code') { $run.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas') }
        $block.Inlines.Add($run)
    }
    $block
}

function New-ChangelogRow([string]$Headline) {
    # A headline after its bullet (a dot Narrator doesn't read).
    $row = [System.Windows.Controls.DockPanel]::new()
    $row.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
    $bullet = [System.Windows.Shapes.Ellipse]::new()
    $bullet.Width = 5
    $bullet.Height = 5
    $bullet.VerticalAlignment = 'Top'
    $bullet.Margin = [System.Windows.Thickness]::new(2, 7, 9, 0)
    $bullet.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'R.AccentText')
    [System.Windows.Controls.DockPanel]::SetDock($bullet, 'Left')
    $null = $row.Children.Add($bullet)
    $null = $row.Children.Add((New-ChangelogText $Headline))
    $row
}

function New-ChangelogBody($Summary) {
    # Each section in a card (its Tag, the section): its name in bold, its headlines, then « et 6 autres », a link that
    # shows the others in their place.
    $panel = [System.Windows.Controls.StackPanel]::new()
    $index = 0
    foreach ($section in $Summary) {
        $card = [System.Windows.Controls.Border]::new()
        $card.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Card')
        $card.Padding = [System.Windows.Thickness]::new(14, 10, 14, 12)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        $card.Tag = $section
        $stack = [System.Windows.Controls.StackPanel]::new()
        $card.Child = $stack
        if ($section.Name) {
            $name = New-ChangelogText $section.Name
            $name.FontSize = 13.5
            $name.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
            $name.SetResourceReference([System.Windows.Controls.TextBlock]::FontWeightProperty, 'R.FontWeightStrong')
            $null = $stack.Children.Add($name)
        }
        foreach ($headline in $section.Headlines) { $null = $stack.Children.Add((New-ChangelogRow $headline)) }
        if ($section.Others) {
            $more = [System.Windows.Controls.TextBlock]::new()
            $more.Margin = [System.Windows.Thickness]::new(16, 6, 0, 0)
            $link = [System.Windows.Documents.Hyperlink]::new([System.Windows.Documents.Run]::new($(if ($section.Others -eq 1) { Tr 'et 1 autre' } else { (Tr 'et {0} autres') -f $section.Others })))
            [System.Windows.Automation.AutomationProperties]::SetAutomationId($link, "changelog_more_$index")
            $link.Tag = @{ Panel = $stack; Block = $more; Rest = $section.Rest }
            $link.Add_Click({
                param($link)
                $data = $link.Tag
                $at = $data.Panel.Children.IndexOf($data.Block)
                $data.Panel.Children.RemoveAt($at)
                foreach ($headline in $data.Rest) { $data.Panel.Children.Insert($at, (New-ChangelogRow $headline)); $at++ }
            })
            $null = $more.Inlines.Add($link)
            $null = $stack.Children.Add($more)
        }
        $null = $panel.Children.Add($card)
        $index++
    }
    $panel
}

function Add-ChangelogTab($Root, $Body) {
    # A tab per section under the title, with how many points it has, when there are 2 named sections or more; the
    # first checked. Its click goes to its section (Select-ChangelogSection).
    $script:ChangelogTabs = [System.Collections.Generic.List[object]]::new()
    $cards = @($Body.Children | Where-Object { $_.Tag.Name })
    if ($cards.Count -lt 2) { return }
    $strip = $Root.FindName('changelog_tabs')
    $strip.Visibility = 'Visible'
    foreach ($card in $cards) {
        $count = $card.Tag.Headlines.Count + $card.Tag.Others
        $tab = [System.Windows.Controls.Primitives.ToggleButton]::new()
        $tab.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Toggle.Tab')
        $tab.Margin = [System.Windows.Thickness]::new(0, 0, 4, 4)
        $content = [System.Windows.Controls.StackPanel]::new()
        $content.Orientation = 'Horizontal'
        $null = $content.Children.Add([System.Windows.Controls.TextBlock]@{ Text = $card.Tag.Name -replace '\*\*|`' })
        $null = $content.Children.Add([System.Windows.Controls.TextBlock]@{ Text = "$count"; Margin = [System.Windows.Thickness]::new(7, 0, 0, 0); Opacity = 0.7 })
        $tab.Content = $content
        [System.Windows.Automation.AutomationProperties]::SetAutomationId($tab, "changelog_tab_$($script:ChangelogTabs.Count)")
        [System.Windows.Automation.AutomationProperties]::SetName($tab, "$($card.Tag.Name -replace '\*\*|`') ($count)")
        $tab.Add_Click({
            param($tab)
            for ($i = 0; $i -lt $script:ChangelogTabs.Count; $i++) { if ($script:ChangelogTabs[$i].Tab -eq $tab) { Select-ChangelogSection $i } }
        })
        $null = $strip.Children.Add($tab)
        $script:ChangelogTabs.Add(@{ Tab = $tab; Card = $card })
    }
    Set-ChangelogTab 0
}

function Set-ChangelogTab([int]$Index) {
    # Checks the tab of section $Index, and only it.
    for ($i = 0; $i -lt $script:ChangelogTabs.Count; $i++) { $script:ChangelogTabs[$i].Tab.IsChecked = $i -eq $Index }
}

function Select-ChangelogSection([int]$Index) {
    # Scrolls to section $Index, its card at the top (or as far as the list goes), and checks its tab.
    Set-ChangelogTab $Index
    $scroll = $script:ChangelogScroll
    $top = $script:ChangelogTabs[$Index].Card.TranslatePoint([System.Windows.Point]::new(0, 0), $scroll).Y
    $target = [Math]::Max(0, [Math]::Min($scroll.ScrollableHeight, $scroll.VerticalOffset + $top - 10))
    if ([Math]::Abs($target - $scroll.VerticalOffset) -lt 0.5) { return }
    # Its tab stays checked, though the scroll ends in the section after (the last ones can't reach the top).
    $script:ChangelogJump = $true
    $scroll.ScrollToVerticalOffset($target)
}

function Update-ChangelogTab($Scroll) {
    # As the list scrolls: the tab of the last section whose card has reached the top, or of the last one at the end.
    if (-not $script:ChangelogTabs.Count) { return }
    $active = 0
    if ($Scroll.ScrollableHeight -gt 0 -and $Scroll.VerticalOffset -ge $Scroll.ScrollableHeight - 1) { $active = $script:ChangelogTabs.Count - 1 }
    else {
        for ($i = 0; $i -lt $script:ChangelogTabs.Count; $i++) {
            if ($script:ChangelogTabs[$i].Card.TranslatePoint([System.Windows.Point]::new(0, 0), $Scroll).Y -le 24) { $active = $i }
        }
    }
    Set-ChangelogTab $active
}
function Show-ChangelogWindow($Entry) {
    # The entry's headlines, in a window that leaves Repère usable. Its box says whether the next versions open it at
    # start. One at a time: opening it again (Paramètres' link) replaces the one open. Over the main window, not
    # Paramètres, which only hides when it closes.
    if ($script:ChangelogWindow -and $script:ChangelogWindow.IsVisible) { $script:ChangelogWindow.Close() }
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:ChangelogXaml))
    $window = [System.Windows.Window]::new()
    $script:ChangelogWindow = $window
    $window.Title = Tr 'Nouveautés'
    $window.Icon = $script:windowIcon
    $window.Owner = $script:win
    $window.Width = 560
    $window.MinWidth = 460
    $window.SizeToContent = 'Height'
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'CenterOwner'
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $window.Content = $root
    # Before the title bar is set: its tabs stay clickable.
    $body = New-ChangelogBody @(Get-ChangelogSummary $Entry)
    $null = $root.FindName('changelog_body').Children.Add($body)
    Add-ChangelogTab $root $body
    $script:ChangelogScroll = $root.FindName('changelog_scroll')
    $script:ChangelogJump = $false
    $script:ChangelogScroll.Add_ScrollChanged({
        param($scroll, $change)
        if (-not $change.VerticalChange) { return }
        if ($script:ChangelogJump) { $script:ChangelogJump = $false; return }
        Update-ChangelogTab $scroll
    })
    Set-WindowChrome $window -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-WindowHeightCap $window
    Register-OwnerFocus $window
    # The version and its date. The notes are in French only.
    $root.FindName('changelog_subtitle').Text = if ($script:UILanguage -eq 'en') { (Tr 'Repère {0}, journal en français') -f $Entry.Heading } else { (Tr 'Repère {0}') -f $Entry.Heading }
    $script:ChangelogDetailUrl = $script:ChangelogReleaseUrl -f $Entry.Version
    $root.FindName('changelog_detail').Add_Click({ Start-Process $script:ChangelogDetailUrl })
    # Fermer and Échap close it as its X does: a window that isn't modal has no DialogResult to close it.
    $root.FindName('dialog_cancel').Add_Click({ param($button) [System.Windows.Window]::GetWindow($button).Close() })
    $window.Show()
}

function Start-Changelog {
    # At start: this version's headlines when Test-ChangelogStart says so, once the main window has drawn and is idle,
    # and this version saved as seen, unless a newer one was (else that one would open again). A new install has no
    # fenetre.json, which every close saves. Not when parametres.json is there but can't be read: left as it is (#243).
    # Not with the fake AD (a demo, the tests), unless $env:REPERE_CHANGELOG_SEEN gives the version seen before (the UI
    # tests'), as from a Repère used before. Whatever goes wrong here, Repère starts.
    try {
        $unreadable = $false
        $saved = Read-JsonSetting $script:ChangelogSettingPath SeenVersion ([ref]$unreadable)
        if ($unreadable) { return }
        $hadSettings = [bool]$script:windowSetting
        if ($script:useFakeAD) {
            if (-not $env:REPERE_CHANGELOG_SEEN) { return }
            $saved = [pscustomobject]@{ SeenVersion = $env:REPERE_CHANGELOG_SEEN }
            $hadSettings = $true
        }
        $show = Test-ChangelogStart $saved $hadSettings $script:RepereVersion
        $seen = Get-ChangelogSeen $saved
        if (-not $seen -or $seen -lt [version]$script:RepereVersion) {
            Save-JsonSetting $script:ChangelogSettingPath ([ordered]@{ SeenVersion = $script:RepereVersion }) -Merge
        }
        if (-not $show) { return }
        $script:ChangelogStartEntry = Get-ChangelogEntry $script:ChangelogPath $script:RepereVersion
        if (-not $script:ChangelogStartEntry) { return }
        $script:win.Add_ContentRendered({
            $null = $script:win.Dispatcher.BeginInvoke([Action]{ Show-ChangelogWindow $script:ChangelogStartEntry },
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        })
    }
    catch { Write-Host "Nouveautés non affichées : $_" }
}
