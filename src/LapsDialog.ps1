# Mot de passe LAPS…: the local administrator password of the selected computers, in a window of their own, a card per
# computer. The password is hidden until shown, and can be copied without being shown. Nothing is kept: it only lives
# in the window. Dot-sourced by the main script, after Theme.ps1 (Get-LapsPassword is ComputerActions.ps1's).

$script:LapsDialogXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
           Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <!-- Also the window's title bar (Set-WindowChrome), its buttons at the end. -->
  <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="16,12,0,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <!-- A DockPanel, not a horizontal StackPanel: the text gets the width left by Copier, and trims to it. -->
      <DockPanel VerticalAlignment="Center">
        <Border DockPanel.Dock="Left" Width="38" Height="38" CornerRadius="8" Background="{DynamicResource R.Selection}" TextElement.Foreground="{DynamicResource R.AccentText}">
          <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:key:20}}</Grid>
        </Border>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock x:Name="laps_title" FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" TextTrimming="CharacterEllipsis"/>
          <TextBlock Style="{StaticResource Txt.Muted}" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis" Text="Administrateur local (LAPS)"/>
        </StackPanel>
      </DockPanel>
      <Button x:Name="laps_copy_all" Grid.Column="1" VerticalAlignment="Center" Margin="16,0,0,0" ToolTip="Tout, en texte : ordinateurs, comptes, expirations et mots de passe">
        <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <StackPanel x:Name="caption_buttons" Grid.Column="2" Orientation="Horizontal" Margin="12,-12,0,-12"/>
    </Grid>
  </Border>
  <Border DockPanel.Dock="Bottom" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,1,0,0" Padding="16,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="laps_status" Style="{StaticResource Txt.Muted}" FontSize="12" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,14,0"
                 Text="Ni enregistré ni journalisé."/>
      <Button x:Name="dialog_cancel" Grid.Column="1" Style="{StaticResource Btn.Primary}" MinWidth="90" IsDefault="True" IsCancel="True" Content="Fermer"/>
    </Grid>
  </Border>
  <ScrollViewer x:Name="laps_scroll" VerticalScrollBarVisibility="Auto">
    <StackPanel x:Name="laps_body" Margin="16,14,16,4"/>
  </ScrollViewer>
</DockPanel>
'@

function Get-LapsEntry($Computer) {
    # A computer's LAPS password, and its text as Copier gives it: its name and kind, the account, then the password or
    # why it can't be shown, AD's English errors in French. ReadAs: that text as UI Automation reads the card.
    try {
        $laps = Get-LapsPassword $Computer.OU $Computer.Domain
        if ($laps.Problem) { $laps.Problem = ConvertTo-FrenchError $laps.Problem }
        if (-not $laps.Kind) {
            $text = (Tr '{0} : aucun mot de passe LAPS') -f $Computer.ComputerName
            return [pscustomobject]@{ Name = $Computer.ComputerName; Laps = $null; Error = $null; Text = $text; ReadAs = $text }
        }
        $title = "$($Computer.ComputerName) — $($laps.Kind)"
        if ($laps.Expires) { $title += ", $($laps.Expires)" }
        $lines = @($title)
        if ($laps.Account) { $lines += '  ' + ((Tr 'Compte : {0}') -f $laps.Account) }
        # What UI Automation reads of the card leaves the password out: the card hides it.
        $readAs = $lines -join "`n"
        if (-not $laps.Password) { $readAs += "`n  " + ((Tr 'Mot de passe : {0}') -f $laps.Problem) }
        $lines += if ($laps.Password) { '  ' + (Tr 'Mot de passe :') + "`n    $($laps.Password)" } else { '  ' + ((Tr 'Mot de passe : {0}') -f $laps.Problem) }
        [pscustomobject]@{ Name = $Computer.ComputerName; Laps = $laps; Error = $null; Text = $lines -join "`n"; ReadAs = $readAs }
    }
    catch {
        $reason = ConvertTo-FrenchError $_.Exception.Message
        $text = (Tr '{0} : mot de passe LAPS non lu ({1})') -f $Computer.ComputerName, $reason
        [pscustomobject]@{ Name = $Computer.ComputerName; Laps = $null; Error = $reason; Text = $text; ReadAs = $text }
    }
}

function Get-LapsCardXaml($Entry, [int]$Index) {
    # A computer's card: its name, a badge for the kind of LAPS and the expiration, then the account and the password.
    # Its name reads as ReadAs for UI Automation, its line breaks written so XML keeps them.
    $x = { param($value) ConvertTo-XamlValue $value }
    $laps = $Entry.Laps
    $badge = ''
    $expires = ''
    $rows = ''
    if ($laps) {
        # The kind and the expiration are Get-LapsPassword's text (ComputerActions.ps1), in this run's language.
        $tone = if ($laps.Kind -eq (Tr 'Windows LAPS (chiffré)')) { 'R.WarnBg', 'R.WarnText' } elseif ($laps.Kind -eq 'Windows LAPS') { 'R.Selection', 'R.AccentText' } else { 'R.Control', 'R.Muted' }
        $badge = "<Border CornerRadius=`"5`" Padding=`"7,1`" Margin=`"10,0,0,0`" VerticalAlignment=`"Center`" Background=`"{DynamicResource $($tone[0])}`"><TextBlock Text=`"$(& $x $laps.Kind)`" FontSize=`"11.5`" FontWeight=`"{DynamicResource R.FontWeightStrong}`" Foreground=`"{DynamicResource $($tone[1])}`"/></Border>"
        if ($laps.Expires) {
            $color = if ($laps.Expires -like ((Tr 'a expiré le {0}') -f '*')) { 'R.WarnText' } else { 'R.Muted' }
            $expires = "<TextBlock Grid.Column=`"1`" FontSize=`"12`" VerticalAlignment=`"Center`" Foreground=`"{DynamicResource $color}`" Text=`"$(& $x ($laps.Expires.Substring(0, 1).ToUpper() + $laps.Expires.Substring(1)))`"/>"
        }
        $account = if ($laps.Account) { & $x $laps.Account } else { '—' }
        $password = if ($laps.Password) {
            @"
        <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal" Margin="0,8,0,0">
          <Border Style="{StaticResource Field}" Padding="10,6" MinWidth="240">
            <TextBlock x:Name="laps_password_$Index" FontFamily="Consolas" FontSize="14" VerticalAlignment="Center"/>
          </Border>
          <Button x:Name="laps_show_$Index" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" ToolTip="Afficher le mot de passe" AutomationProperties.Name="Afficher le mot de passe">{{icon:eye:14}}</Button>
          <Button x:Name="laps_hide_$Index" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Masquer le mot de passe" AutomationProperties.Name="Masquer le mot de passe">{{icon:eyeoff:14}}</Button>
          <Button x:Name="laps_copy_$Index" Style="{StaticResource Btn.Mini}" Margin="2,0,0,0" VerticalAlignment="Center" ToolTip="Copier le mot de passe" AutomationProperties.Name="Copier le mot de passe">{{icon:copy:14}}</Button>
        </StackPanel>
"@
        }
        else {
            "<TextBlock Grid.Row=`"1`" Grid.Column=`"1`" Margin=`"0,8,0,0`" FontStyle=`"Italic`" TextWrapping=`"Wrap`" Foreground=`"{DynamicResource R.WarnText}`" Text=`"$(& $x ($laps.Problem.Substring(0, 1).ToUpper() + $laps.Problem.Substring(1)))`"/>"
        }
        $rows = @"
      <Grid Margin="16,0,16,14">
        <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Style="{StaticResource Txt.Muted}" Text="Compte" VerticalAlignment="Center"/>
        <TextBlock Grid.Column="1" Text="$account" TextWrapping="Wrap"/>
        <TextBlock Grid.Row="1" Style="{StaticResource Txt.Muted}" Text="Mot de passe" Margin="0,8,0,0" VerticalAlignment="Center"/>
$password
      </Grid>
"@
    }
    else {
        $text = if ($Entry.Error) { (Tr 'Mot de passe LAPS non lu : {0}') -f $Entry.Error } else { Tr 'Aucun mot de passe LAPS' }
        $color = if ($Entry.Error) { 'R.WarnText' } else { 'R.Muted' }
        $rows = "<TextBlock Margin=`"16,0,16,14`" TextWrapping=`"Wrap`" Foreground=`"{DynamicResource $color}`" Text=`"$(& $x $text)`"/>"
    }
    @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Style="{StaticResource Card}" Margin="0,0,0,12">
  <StackPanel>
    <Grid Margin="16,12,16,10">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="laps_section_$Index" Text="$(& $x $Entry.Name)" FontSize="14" FontWeight="{DynamicResource R.FontWeightStrong}" VerticalAlignment="Center"
                   AutomationProperties.Name="$(& $x $Entry.ReadAs)"/>
        $badge
      </StackPanel>
      $expires
    </Grid>
$rows
  </StackPanel>
</Border>
"@
}

function Set-LapsPasswordShown($State, [int]$Index, [bool]$Shown) {
    # Hidden: a row of dots, the same length whatever the password. Shown: in Consolas, its digits in the accent color
    # and its symbols in amber, so 0 and O, or 1, l and I, read apart when it's dictated.
    $block = $State.Cards[$Index].FindName("laps_password_$Index")
    $block.Inlines.Clear()
    if (-not $Shown) {
        $dots = [System.Windows.Documents.Run]::new([string]::new([char]0x25CF, 12))
        $dots.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'R.Muted')
        $block.Inlines.Add($dots)
    }
    else {
        foreach ($char in $State.Entries[$Index].Laps.Password.ToCharArray()) {
            $run = [System.Windows.Documents.Run]::new([string]$char)
            $color = if ([char]::IsDigit($char)) { 'R.AccentText' } elseif ([char]::IsLetter($char)) { 'R.Text' } else { 'R.WarnText' }
            $run.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, $color)
            $block.Inlines.Add($run)
        }
    }
    Set-EyeButton $State.Cards[$Index].FindName("laps_show_$Index") $State.Cards[$Index].FindName("laps_hide_$Index") $Shown
}

function Get-LapsEntryList($Computers) {
    # On a search runspace: each computer's entry, in their order.
    @{ Entries = @(foreach ($computer in $Computers) { Get-LapsEntry $computer }) }
}

function Show-LapsDialog($Computers, $Owner, $Icon) {
    # Reads every computer's password in the background (nothing is written to AD), then the window.
    Start-WindowRead -Kind 'Laps' -Command 'Get-LapsEntryList' -Arguments @(, @(ConvertTo-ReadComputer $Computers)) `
        -Functions 'Get-LapsEntry', 'Get-LapsPassword', 'Format-LapsDate' -Variables @{ hasLapsCommand = $hasLapsCommand } `
        -Context @{ Computers = $Computers; Owner = $Owner; Icon = $Icon } -OnDone {
        param($context, $read, $problem)
        if ($problem -or -not $read) {
            $reason = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
            Show-ActionReport @($context.Computers | ForEach-Object { (Tr '✖ {0} : {1}') -f $_.ComputerName, $reason }) -Title (Tr 'Mot de passe LAPS')
            return
        }
        # No LAPS at all on any of them: nothing for a window to show. A toast says so, or the report of an action
        # that failed says which couldn't be read.
        $entries = @($read.Entries)
        if (-not @($entries | Where-Object Laps).Count) {
            $lines = @(foreach ($entry in $entries) { if ($entry.Error) { "✖ $($entry.Text)" } else { $entry.Text } })
            Show-ActionReport $lines (Tr 'Mot de passe LAPS') -Owner $context.Owner -Many (Tr 'Aucun mot de passe LAPS pour {0} ordinateurs')
            return
        }
        Show-LapsWindow $entries $context.Owner $context.Icon
    }
}

function Show-LapsWindow($LapsEntries, $Owner, $Icon) {
    # A card per computer's entry (Get-LapsEntry).
    $entries = @($LapsEntries)
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:LapsDialogXaml))
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = Tr 'Mot de passe LAPS'
    $dialog.Icon = $Icon
    $dialog.Owner = $Owner
    $dialog.Width = 620
    $dialog.MinWidth = 520
    $dialog.SizeToContent = 'Height'
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.Content = $root
    Set-WindowChrome $dialog -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-WindowHeightCap $dialog

    $root.FindName('laps_title').Text = if ($entries.Count -eq 1) { $entries[0].Name } else { (Tr '{0} ordinateurs') -f $entries.Count }
    $state = @{ Entries = $entries; Cards = @{}; Status = $root.FindName('laps_status') }
    # The footer says the password isn't kept only when there's one to keep: none of them may be readable.
    if (-not @($entries | Where-Object { $_.Laps -and $_.Laps.Password }).Count) { $state.Status.Text = '' }
    $dialog.Tag = $state
    $body = $root.FindName('laps_body')
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $card = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon (Get-LapsCardXaml $entries[$i] $i)))
        $null = $body.Children.Add($card)
        $state.Cards[$i] = $card
        if (-not ($entries[$i].Laps -and $entries[$i].Laps.Password)) { continue }
        Set-LapsPasswordShown $state $i $false
        foreach ($name in "laps_show_$i", "laps_hide_$i", "laps_copy_$i") {
            $button = $card.FindName($name)
            $button.CommandParameter = $i
            $button.Add_Click({
                param($control)
                $state = [System.Windows.Window]::GetWindow($control).Tag
                $index = [int]$control.CommandParameter
                if ($control.Name -like 'laps_copy_*') {
                    $copied = Set-SecretClipboard $state.Entries[$index].Laps.Password
                    Show-CopyFeedback $control $copied
                    $name = $state.Entries[$index].Name
                    $state.Status.Text = if ($copied) { (Tr 'Mot de passe de {0} copié.') -f $name } else { (Tr 'Mot de passe de {0} non copié : le presse-papiers est occupé par un autre programme.') -f $name }
                }
                else { Set-LapsPasswordShown $state $index ($control.Name -like 'laps_show_*') }
            })
        }
    }
    $root.FindName('laps_copy_all').Add_Click({
        param($button)
        $state = [System.Windows.Window]::GetWindow($button).Tag
        $copied = Set-SecretClipboard (@($state.Entries | ForEach-Object Text) -join "`n`n")
        Show-CopyFeedback $button $copied
        $state.Status.Text = if ($copied) { Tr 'Tout est copié, mots de passe compris.' } else { Tr 'Non copié : le presse-papiers est occupé par un autre programme.' }
    })

    $script:search.Dialogs++
    try { $null = $dialog.ShowDialog() }
    finally { $script:search.Dialogs-- }
}
