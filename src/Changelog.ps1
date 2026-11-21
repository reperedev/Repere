# Nouveautés: what the versions since the last start brought, read from CHANGELOG.md (in the zip, beside src), in a
# window of its own once the main window shows, the first time a newer Repère starts (#9). Its box « Ne plus afficher »
# stops that (ShowChangelog in parametres.json); Paramètres' « Nouveautés » opens it whenever, every version listed.
# Dot-sourced by the main script, after SettingsWindow.ps1.

$script:ChangelogPath = Join-Path (Split-Path $PSScriptRoot) 'CHANGELOG.md'
$script:ChangelogSettingPath = Get-SettingPath 'parametres.json'

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
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <!-- Saved as it's clicked: the next versions don't open this window at start. Paramètres' « Nouveautés » still does. -->
      <CheckBox x:Name="changelog_hide" VerticalAlignment="Center" Margin="0,0,14,0" Content="Ne plus afficher après une mise à jour"/>
      <Button x:Name="dialog_cancel" Grid.Column="1" Style="{StaticResource Btn.Primary}" MinWidth="90" IsDefault="True" IsCancel="True" Content="Fermer"/>
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

function Get-ChangelogStart($Saved, [bool]$HadSettings, [string]$Current) {
    # What to show at start, from parametres.json's SeenVersion and ShowChangelog ($Saved, $null without the file): the
    # last version seen, whose newer entries to show; '' for a Repère used before that didn't save it (0.15.0 and
    # earlier), which shows the current version's entry; $null for nothing. A new install (no settings before this
    # start) shows nothing, nor does the same version again, an older one, or « Ne plus afficher ».
    if ($Saved -and $Saved.ShowChangelog -eq $false) { return $null }
    $seen = if ($Saved -and "$($Saved.SeenVersion)" -match '^\d+\.\d+\.\d+$') { [version]$Saved.SeenVersion }
    if ($seen) {
        if ($seen -lt [version]$Current) { return $seen.ToString() }
        return $null
    }
    if ($HadSettings) { return '' }
    $null
}

function Select-ChangelogEntry($Entries, [string]$From, [string]$Current) {
    # The entries newer than $From, up to $Current; only $Current's when $From is ''.
    $top = [version]$Current
    @($Entries | Where-Object { $_.Version -le $top -and $(if ($From) { $_.Version -gt [version]$From } else { $_.Version -eq $top }) })
}

function ConvertFrom-ChangelogLine([string]$Line) {
    # A line of an entry, as the window shows it: Kind Section (###), Subsection (####), Point (- , Level 1 for a
    # sub-point), Text (a paragraph; Level 1 for one under a point, indented), with its Text. $null for a blank line.
    if (-not $Line.Trim()) { return $null }
    if ($Line -match '^(#{3,4})\s+(.+)$') { return [pscustomobject]@{ Kind = $(if ($Matches[1].Length -eq 3) { 'Section' } else { 'Subsection' }); Level = 0; Text = $Matches[2].Trim() } }
    if ($Line -match '^( *)[-*]\s+(.+)$') { return [pscustomobject]@{ Kind = 'Point'; Level = [int]($Matches[1].Length -ge 2); Text = $Matches[2].Trim() } }
    [pscustomobject]@{ Kind = 'Text'; Level = [int]($Line -match '^\s'); Text = $Line.Trim() }
}

function ConvertFrom-ChangelogInline([string]$Text) {
    # A line's Markdown as parts: Kind Bold (**…**), Italic (*…*), Code (`…`) or Plain, each its Text.
    foreach ($part in [regex]::Split($Text, '(\*\*.+?\*\*|`[^`]+`|\*[^*\s][^*]*\*)')) {
        if (-not $part) { continue }
        if ($part.Length -gt 4 -and $part.StartsWith('**') -and $part.EndsWith('**')) { [pscustomobject]@{ Kind = 'Bold'; Text = $part.Substring(2, $part.Length - 4) } }
        elseif ($part.Length -gt 2 -and $part.StartsWith('`') -and $part.EndsWith('`')) { [pscustomobject]@{ Kind = 'Code'; Text = $part.Substring(1, $part.Length - 2) } }
        elseif ($part.Length -gt 2 -and $part.StartsWith('*') -and $part.EndsWith('*')) { [pscustomobject]@{ Kind = 'Italic'; Text = $part.Substring(1, $part.Length - 2) } }
        else { [pscustomobject]@{ Kind = 'Plain'; Text = $part } }
    }
}

function New-ChangelogText([string]$Text, [double]$Size = 0) {
    # A wrapping text block of a line, its Markdown as bold, italic and Consolas runs.
    $block = [System.Windows.Controls.TextBlock]::new()
    $block.TextWrapping = 'Wrap'
    if ($Size) { $block.FontSize = $Size }
    foreach ($part in ConvertFrom-ChangelogInline $Text) {
        $run = [System.Windows.Documents.Run]::new($part.Text)
        switch ($part.Kind) {
            'Bold' { $run.SetResourceReference([System.Windows.Documents.TextElement]::FontWeightProperty, 'R.FontWeightStrong') }
            'Italic' { $run.FontStyle = 'Italic' }
            'Code' { $run.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas') }
        }
        $block.Inlines.Add($run)
    }
    $block
}

function New-ChangelogBody($Entries) {
    # The entries one after the other: the version as a title, its sections in the muted color, its points with a
    # bullet, a sub-point or a paragraph of a point indented under it.
    $panel = [System.Windows.Controls.StackPanel]::new()
    $first = $true
    foreach ($entry in $Entries) {
        $title = New-ChangelogText $entry.Heading 16
        $title.SetResourceReference([System.Windows.Controls.TextBlock]::FontWeightProperty, 'R.FontWeightTitle')
        $title.Margin = [System.Windows.Thickness]::new(0, $(if ($first) { 0 } else { 24 }), 0, 2)
        $first = $false
        $null = $panel.Children.Add($title)
        foreach ($line in $entry.Lines) {
            $item = ConvertFrom-ChangelogLine $line
            if (-not $item) { continue }
            if ($item.Kind -in 'Section', 'Subsection') {
                $block = New-ChangelogText $item.Text $(if ($item.Kind -eq 'Section') { 13.5 } else { 12.5 })
                $block.SetResourceReference([System.Windows.Controls.TextBlock]::FontWeightProperty, 'R.FontWeightStrong')
                $block.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
                $block.Margin = [System.Windows.Thickness]::new(0, $(if ($item.Kind -eq 'Section') { 14 } else { 10 }), 0, 2)
                $null = $panel.Children.Add($block)
                continue
            }
            $block = New-ChangelogText $item.Text
            if ($item.Kind -eq 'Text' -and -not $item.Level) {
                $block.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
                $null = $panel.Children.Add($block)
                continue
            }
            # A point: its bullet, then its text, which wraps under itself. A paragraph under a point lines up with it.
            $row = [System.Windows.Controls.DockPanel]::new()
            $row.Margin = [System.Windows.Thickness]::new(16 * $item.Level, 5, 0, 0)
            $bullet = [System.Windows.Controls.TextBlock]::new()
            $bullet.Width = 16
            if ($item.Kind -eq 'Point') { $bullet.Text = '•' }
            $bullet.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
            [System.Windows.Controls.DockPanel]::SetDock($bullet, 'Left')
            $null = $row.Children.Add($bullet)
            $null = $row.Children.Add($block)
            $null = $panel.Children.Add($row)
        }
    }
    $panel
}

function Show-ChangelogWindow($Entries, $Owner) {
    # The entries, in a window that leaves Repère usable. Its box says whether the next versions open it at start.
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:ChangelogXaml))
    $window = [System.Windows.Window]::new()
    $window.Title = Tr 'Nouveautés'
    $window.Icon = $script:windowIcon
    $window.Owner = $Owner
    $window.Width = 660
    $window.MinWidth = 480
    $window.SizeToContent = 'Height'
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'CenterOwner'
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $window.Content = $root
    Set-WindowChrome $window -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-WindowHeightCap $window
    Register-OwnerFocus $window
    # Its own version: the entries can go back further. The entries are in French only.
    $root.FindName('changelog_subtitle').Text = if ($script:UILanguage -eq 'en') { (Tr 'Repère {0}, journal en français') -f $script:RepereVersion } else { (Tr 'Repère {0}') -f $script:RepereVersion }
    $null = $root.FindName('changelog_body').Children.Add((New-ChangelogBody $Entries))
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
    # At start: the entries since the last version seen, once the main window has drawn and is idle, and this version
    # saved as seen. Not when parametres.json is there but can't be read: left as it is (#243). Not with the fake AD (a
    # demo, the tests), unless $env:REPERE_CHANGELOG_SEEN gives the version seen before (the UI tests').
    $unreadable = $false
    $saved = Read-JsonSetting $script:ChangelogSettingPath SeenVersion, ShowChangelog ([ref]$unreadable)
    if ($unreadable) { return }
    $hadSettings = $script:SettingsBeforeRun
    if ($script:useFakeAD) {
        if (-not $env:REPERE_CHANGELOG_SEEN) { return }
        $saved = [pscustomobject]@{ SeenVersion = $env:REPERE_CHANGELOG_SEEN; ShowChangelog = $(if ($saved) { $saved.ShowChangelog }) }
        $hadSettings = $true
    }
    $from = Get-ChangelogStart $saved $hadSettings $script:RepereVersion
    if (-not $saved -or "$($saved.SeenVersion)" -ne $script:RepereVersion) {
        Save-JsonSetting $script:ChangelogSettingPath ([ordered]@{ SeenVersion = $script:RepereVersion }) -Merge
    }
    if ($null -eq $from) { return }
    $script:ChangelogStartEntries = @(Select-ChangelogEntry @(Read-ChangelogEntry $script:ChangelogPath) $from $script:RepereVersion)
    if (-not $script:ChangelogStartEntries.Count) { return }
    $script:win.Add_ContentRendered({
        $null = $script:win.Dispatcher.BeginInvoke([Action]{ Show-ChangelogWindow $script:ChangelogStartEntries $script:win },
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    })
}
