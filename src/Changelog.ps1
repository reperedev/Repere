# Nouveautés: what this version brought, as the headlines of its CHANGELOG.md entry (in the zip, beside src), in a
# window of its own once the main window shows, the first time a newer Repère starts (#9). Each section lists its
# first points' headlines and how many others it has; « Voir le détail » opens the version's release on GitHub, which
# is that whole entry. Its box « Ne plus afficher » stops it (ShowChangelog in parametres.json); Paramètres'
# « Nouveautés » opens it whenever. Dot-sourced by the main script, after SettingsWindow.ps1.

$script:ChangelogPath = Join-Path (Split-Path $PSScriptRoot) 'CHANGELOG.md'
$script:ChangelogSettingPath = Get-SettingPath 'parametres.json'
$script:ChangelogReleaseUrl = 'https://github.com/reperedev/Repere/releases/tag/v{0}'
# The headlines a section lists; « et 6 autres » says how many more it has.
$script:ChangelogShown = 3
# The window open (Show-ChangelogWindow), if one is.
$script:ChangelogWindow = $null

$script:ChangelogXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
           Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <!-- Also the window's title bar (Set-WindowChrome), its buttons at the end: Fermer's X among them. -->
  <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="16,12,0,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
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
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <!-- Saved as it's clicked: the next versions don't open this window at start. Paramètres' « Nouveautés » still does. -->
      <CheckBox x:Name="changelog_hide" VerticalAlignment="Center" Margin="0,0,16,0" Content="Ne plus afficher"/>
      <TextBlock Grid.Column="1" VerticalAlignment="Center" Margin="0,0,14,0"><Hyperlink x:Name="changelog_detail" AutomationProperties.AutomationId="changelog_detail">Voir le détail</Hyperlink></TextBlock>
      <Button x:Name="dialog_cancel" Grid.Column="3" Style="{StaticResource Btn.Primary}" MinWidth="90" IsDefault="True" IsCancel="True" Content="Fermer"/>
    </Grid>
  </Border>
  <ScrollViewer x:Name="changelog_scroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <StackPanel x:Name="changelog_body" Margin="20,14,20,16"/>
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
    # $HadSettings), the same version again, an older one, nor after « Ne plus afficher » (ShowChangelog false).
    if ($Saved -and $Saved.ShowChangelog -eq $false) { return $false }
    $seen = Get-ChangelogSeen $Saved
    if ($seen) { return $seen -lt [version]$Current }
    $HadSettings
}

function Get-ChangelogHeadline([string]$Text) {
    # A point's headline, kept short: the sentence in bold that starts it (6 words or more), else its first sentence, up
    # to « . », « : » or « ; », or a comma once it has 8 words; never inside bold, « » or `code`. Past a short name in
    # bold that starts it (3 words at most): « **Propriétés** : au-delà de 10 groupes… » keeps its words.
    if ($Text -match '^\*\*([^*]+)\*\*' -and @($Matches[1].Trim() -split '\s+').Count -ge 6) { return $Matches[0] }
    $quote = 0
    $code = $false
    $bold = $false
    for ($i = 0; $i -lt $Text.Length - 1; $i++) {
        $char = $Text[$i]
        if ($char -eq '`') { $code = -not $code; continue }
        if ($code) { continue }
        if ($char -eq '*' -and $Text[$i + 1] -eq '*') { $bold = -not $bold; $i++; continue }
        if ($char -eq [char]0xAB) { $quote++; continue }  # «
        if ($char -eq [char]0xBB) { $quote--; continue }  # »
        if ($bold -or $quote -gt 0 -or $Text[$i + 1] -ne ' ') { continue }
        $end = $char -eq '.' -or ($char -in ':', ';' -and $i -gt 0 -and $Text[$i - 1] -eq ' ')
        if (-not $end -and $char -ne ',') { continue }
        $head = $Text.Substring(0, $i).TrimEnd()
        $words = @(($head -replace '\*\*|`') -split '\s+' | Where-Object { $_ }).Count
        if ($end -and ($head -notmatch '^\*\*[^*]+\*\*$' -or $words -gt 3)) { return $head }
        if (-not $end -and $words -ge 8) { return $head }
    }
    $Text.Trim().TrimEnd('.')
}

function Get-ChangelogSummary($Entry, [int]$Shown = $script:ChangelogShown) {
    # The entry as the window shows it: each section (### ; a #### one counts in it) with the Headlines of its first
    # $Shown points, and how many Others it has. Not the sub-points nor the paragraphs, which are the detail.
    $section = $null
    foreach ($line in $Entry.Lines) {
        if ($line -match '^###\s+(.+)$') {
            if ($section) { $section }
            $section = [pscustomobject]@{ Name = $Matches[1].Trim(); Headlines = [System.Collections.Generic.List[string]]::new(); Others = 0 }
        }
        elseif ($line -match '^[-*]\s+(.+)$') {
            if (-not $section) { $section = [pscustomobject]@{ Name = ''; Headlines = [System.Collections.Generic.List[string]]::new(); Others = 0 } }
            if ($section.Headlines.Count -lt $Shown) { $section.Headlines.Add((Get-ChangelogHeadline $Matches[1])) }
            else { $section.Others++ }
        }
    }
    if ($section) { $section }
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

function New-ChangelogBody($Summary) {
    # The sections one after the other: the name in bold, its headlines with a bullet (a dot Narrator doesn't read),
    # then « et 6 autres » in the muted color.
    $panel = [System.Windows.Controls.StackPanel]::new()
    $first = $true
    foreach ($section in $Summary) {
        if ($section.Name) {
            $name = New-ChangelogText $section.Name
            $name.FontSize = 13
            $name.SetResourceReference([System.Windows.Controls.TextBlock]::FontWeightProperty, 'R.FontWeightStrong')
            $name.Margin = [System.Windows.Thickness]::new(0, $(if ($first) { 0 } else { 14 }), 0, 2)
            $null = $panel.Children.Add($name)
        }
        $first = $false
        foreach ($headline in $section.Headlines) {
            $row = [System.Windows.Controls.DockPanel]::new()
            $row.Margin = [System.Windows.Thickness]::new(0, 5, 0, 0)
            $bullet = [System.Windows.Shapes.Ellipse]::new()
            $bullet.Width = 5
            $bullet.Height = 5
            $bullet.VerticalAlignment = 'Top'
            $bullet.Margin = [System.Windows.Thickness]::new(3, 6, 8, 0)
            $bullet.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'R.Muted')
            [System.Windows.Controls.DockPanel]::SetDock($bullet, 'Left')
            $null = $row.Children.Add($bullet)
            $null = $row.Children.Add((New-ChangelogText $headline))
            $null = $panel.Children.Add($row)
        }
        if ($section.Others) {
            $others = [System.Windows.Controls.TextBlock]::new()
            $others.Text = if ($section.Others -eq 1) { Tr 'et 1 autre' } else { (Tr 'et {0} autres') -f $section.Others }
            $others.Margin = [System.Windows.Thickness]::new(16, 4, 0, 0)
            $others.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
            $null = $panel.Children.Add($others)
        }
    }
    $panel
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
    Set-WindowChrome $window -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-WindowHeightCap $window
    Register-OwnerFocus $window
    # The version and its date. The notes are in French only.
    $root.FindName('changelog_subtitle').Text = if ($script:UILanguage -eq 'en') { (Tr 'Repère {0}, journal en français') -f $Entry.Heading } else { (Tr 'Repère {0}') -f $Entry.Heading }
    $null = $root.FindName('changelog_body').Children.Add((New-ChangelogBody @(Get-ChangelogSummary $Entry)))
    $script:ChangelogDetailUrl = $script:ChangelogReleaseUrl -f $Entry.Version
    $root.FindName('changelog_detail').Add_Click({ Start-Process $script:ChangelogDetailUrl })
    $saved = Read-JsonSetting $script:ChangelogSettingPath ShowChangelog
    $hide = $root.FindName('changelog_hide')
    # As saved, before it's wired: then each change is saved, however it's made (a click, Espace, Narrator).
    $hide.IsChecked = [bool]($saved -and $saved.ShowChangelog -eq $false)
    $save = { param($box) Save-JsonSetting $script:ChangelogSettingPath ([ordered]@{ ShowChangelog = -not $box.IsChecked }) -Merge }
    $hide.Add_Checked($save)
    $hide.Add_Unchecked($save)
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
        $saved = Read-JsonSetting $script:ChangelogSettingPath SeenVersion, ShowChangelog ([ref]$unreadable)
        if ($unreadable) { return }
        $hadSettings = [bool]$script:windowSetting
        if ($script:useFakeAD) {
            if (-not $env:REPERE_CHANGELOG_SEEN) { return }
            $saved = [pscustomobject]@{ SeenVersion = $env:REPERE_CHANGELOG_SEEN; ShowChangelog = $(if ($saved) { $saved.ShowChangelog }) }
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
