# Redémarrer… and Annuler le redémarrage: a restart scheduled with Windows' own command, shutdown.exe, after a delay and
# with a message. Windows shows the message on the computer's screen in its own box (« Vous allez être déconnecté »),
# with a Fermer button only: no countdown, and the user can't refuse. The delay and the message are chosen in a dialog,
# with defaults the technician can save. Dot-sourced by the main script, after Theme.ps1.
#
# shutdown.exe reaches the computer through the same file sharing connection (port 445) as Ouvrir C$, and needs
# administrator rights there. It runs in the background: against a computer that's off, it can take a while.

$script:RestartSettingsPath = Get-SettingPath 'redemarrage.json'
# Each unit and its length in seconds. Windows takes up to 10 years; more than 7 days is more likely a typo.
# The unit's key is its id, saved in redemarrage.json; the lists show RestartUnitTexts' text, in the run's language
# (Get-RestartUnit reads either).
$script:RestartUnits = [ordered]@{ secondes = 1; minutes = 60; heures = 3600; jours = 86400 }
$script:RestartUnitTexts = [ordered]@{ secondes = (Tr 'secondes'); minutes = (Tr 'minutes'); heures = (Tr 'heures'); jours = (Tr 'jours') }
$script:RestartMaxSeconds = 7 * 86400
# Windows' limit for the message (/c).
$script:RestartMaxMessage = 512
# In the run's language. A message saved in redemarrage.json is the technician's own text: it stays as it was typed.
$script:RestartDefaultMessage = Tr 'Votre ordinateur va redémarrer dans {délai} (vers {heure}) pour une intervention du support informatique. Enregistrez votre travail.'
# The message's placeholders, French or English in either language: a message saved in one works in the other.
$script:RestartDelayTags = '{délai}', '{delay}'
$script:RestartTimeTags = '{heure}', '{time}'
# The shutdown.exe commands under way: their process, what they do and for which computer. A timer reports each one
# when it ends.
$script:ShutdownJobs = [System.Collections.Generic.List[object]]::new()
$script:ShutdownTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:ShutdownTimer.Interval = [timespan]::FromMilliseconds(250)

function Read-RestartSetting {
    # The saved defaults (Amount, Unit, Message), or Repère's own: 5 minutes and the default message.
    $settings = @{ Amount = 5; Unit = 'minutes'; Message = $script:RestartDefaultMessage }
    # Missing or unreadable: Repère's defaults.
    $saved = Read-JsonSetting $script:RestartSettingsPath Amount, Unit, Message
    if (-not $saved) { return $settings }
    $amount = 0
    if ([int]::TryParse("$($saved.Amount)", [ref]$amount) -and $amount -ge 0) { $settings.Amount = $amount }
    if ($script:RestartUnits.Contains([string]$saved.Unit)) { $settings.Unit = [string]$saved.Unit }
    if ($null -ne $saved.Message) { $settings.Message = [string]$saved.Message }
    $settings
}

function Save-RestartSetting([int]$Amount, [string]$Unit, [string]$Message) {
    Save-JsonSetting $script:RestartSettingsPath ([ordered]@{ Amount = $Amount; Unit = $Unit; Message = $Message })
}

function Get-RestartUnit($ComboBox) {
    # The id of the unit a list shows: by its text, or the id itself (a list filled with the ids).
    $shown = [string]$ComboBox.SelectedItem
    foreach ($unit in $script:RestartUnitTexts.Keys) { if ($script:RestartUnitTexts[$unit] -ceq $shown) { return $unit } }
    $shown
}

function Format-RestartDelay([int]$Amount, [string]$Unit) {
    # « 5 minutes », « 1 heure », « 30 secondes ». The singular for 1, and in French for 0 too.
    $one = $Amount -eq 1 -or ($Amount -eq 0 -and (Get-TextCulture).TwoLetterISOLanguageName -eq 'fr')
    $format = switch ($Unit) {
        secondes { if ($one) { Tr '{0} seconde' } else { Tr '{0} secondes' } }
        minutes { if ($one) { Tr '{0} minute' } else { Tr '{0} minutes' } }
        heures { if ($one) { Tr '{0} heure' } else { Tr '{0} heures' } }
        jours { if ($one) { Tr '{0} jour' } else { Tr '{0} jours' } }
    }
    $format -f $Amount
}

function Format-RestartTime([datetime]$When, [datetime]$Now) {
    # « 21 h 50 » today, « demain à 08 h 00 », otherwise « le 2026-10-18 à 08 h 00 ».
    $culture = Get-TextCulture
    $time = $When.ToString((Tr "HH' h 'mm"), $culture)
    if ($When.Date -eq $Now.Date) { $time }
    elseif ($When.Date -eq $Now.Date.AddDays(1)) { (Tr 'demain à {0}') -f $time }
    else { (Tr 'le {0} à {1}') -f $When.ToString('d', $culture), $time }
}

function Expand-RestartMessage([string]$Message, [int]$Amount, [string]$Unit, [datetime]$Now) {
    # The message as Windows will show it: {délai} and {heure} ({delay} and {time}) replaced, since Windows' box has
    # no countdown.
    $when = $Now.AddSeconds($Amount * $script:RestartUnits[$Unit])
    $delay = Format-RestartDelay $Amount $Unit
    $time = Format-RestartTime $when $Now
    foreach ($tag in $script:RestartDelayTags) { $Message = $Message.Replace($tag, $delay) }
    foreach ($tag in $script:RestartTimeTags) { $Message = $Message.Replace($tag, $time) }
    $Message
}

function Format-CommandLine([string]$FilePath, [string[]]$Arguments) {
    # The command as it would be typed, for the fake AD's report.
    $quoted = foreach ($argument in $Arguments) { if ($argument -match '\s' -or -not $argument) { "`"$argument`"" } else { $argument } }
    (@($FilePath) + @($quoted)) -join ' '
}

$script:RestartDialogXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Padding="18" Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <StackPanel Width="540">
    <TextBlock x:Name="restart_question" FontSize="15" FontWeight="{DynamicResource R.FontWeightStrong}" TextWrapping="Wrap"/>
    <TextBlock Style="{StaticResource Txt.Muted}" Margin="0,6,0,0" TextWrapping="Wrap"
               Text="Windows affiche le message, puis redémarre sans enregistrer le travail en cours. L'utilisateur ne peut pas l'empêcher."/>

    <TextBlock Style="{StaticResource Txt.Label}" Margin="0,16,0,4" Text="Délai"/>
    <StackPanel Orientation="Horizontal">
      <TextBox x:Name="restart_amount" Width="90" AutomationProperties.Name="Délai"/>
      <ComboBox x:Name="restart_unit" Width="140" Height="34" Margin="8,0,0,0" VerticalContentAlignment="Center" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Unité"/>
      <TextBlock x:Name="restart_when" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="12,0,0,0"/>
    </StackPanel>

    <Grid Margin="0,14,0,4">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock Style="{StaticResource Txt.Label}" Text="Message affiché"/>
      <TextBlock x:Name="restart_length" Grid.Column="1" Style="{StaticResource Txt.Faint}" FontSize="12"/>
    </Grid>
    <TextBox x:Name="restart_message" TextWrapping="Wrap" MinHeight="64" Padding="8,6" VerticalContentAlignment="Top" AutomationProperties.Name="Message"/>
    <!-- Its text is set by Show-RestartDialog: starting with {, it isn't translated with the XAML (Language.ps1). -->
    <TextBlock x:Name="restart_hint" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/>

    <TextBlock Style="{StaticResource Txt.Label}" Margin="0,12,0,4" Text="Aperçu"/>
    <Border Background="{DynamicResource R.Surface}" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Padding="10,8">
      <TextBlock x:Name="restart_preview" TextWrapping="Wrap"/>
    </Border>

    <TextBlock x:Name="restart_problem" Margin="0,10,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
    <CheckBox x:Name="restart_save" Margin="0,14,0,0" Content="Enregistrer comme valeurs par défaut"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="restart_ok" Style="{StaticResource Btn.Danger}" MinWidth="110">
        <StackPanel Orientation="Horizontal">{{icon:power}}<TextBlock Text="Redémarrer" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <!-- Entrée and Échap: Annuler. -->
      <Button x:Name="restart_cancel" Style="{StaticResource Btn.Primary}" MinWidth="90" Margin="8,0,0,0" IsDefault="True" IsCancel="True" Content="Annuler"/>
    </StackPanel>
  </StackPanel>
</Border>
'@

function Get-RestartChoice($State) {
    # What the dialog holds: the delay (Amount, Unit, Seconds), the message as typed, and the first problem, if any
    # (Error stops the restart, Warning doesn't).
    $c = $State.Controls
    $choice = @{ Amount = $null; Unit = Get-RestartUnit $c.restart_unit; Seconds = $null; Message = "$($c.restart_message.Text)"; Error = $null; Warning = $null }
    $amount = 0
    if ("$($c.restart_amount.Text)".Trim() -notmatch '^\d{1,7}$' -or -not [int]::TryParse("$($c.restart_amount.Text)".Trim(), [ref]$amount)) {
        $choice.Error = Tr 'Entrez un délai en nombre entier.'
        return $choice
    }
    $choice.Amount = $amount
    $choice.Seconds = $amount * $script:RestartUnits[$choice.Unit]
    if ($choice.Seconds -gt $script:RestartMaxSeconds) {
        $choice.Error = Tr 'Le délai est de 7 jours au plus.'
        # It may be past any date: nothing to preview.
        $choice.Seconds = $null
    }
    elseif ((Expand-RestartMessage $choice.Message $amount $choice.Unit (Get-Date)).Length -gt $script:RestartMaxMessage) {
        $choice.Error = (Tr 'Le message dépasse {0} caractères, la limite de Windows.') -f $script:RestartMaxMessage
    }
    elseif ($choice.Seconds -eq 0) { $choice.Warning = Tr "Redémarrage immédiat : l'utilisateur n'aura pas le temps de lire le message." }
    $choice
}

function Update-RestartDialog($State) {
    # After each change: the time, the preview, the length, and whether Redémarrer is allowed.
    $c = $State.Controls
    $choice = Get-RestartChoice $State
    $now = Get-Date
    if ($null -ne $choice.Seconds) {
        $c.restart_when.Text = if ($choice.Seconds -eq 0) { Tr 'maintenant' } else { (Tr 'vers {0}') -f (Format-RestartTime $now.AddSeconds($choice.Seconds) $now) }
        $preview = Expand-RestartMessage $choice.Message $choice.Amount $choice.Unit $now
        $c.restart_preview.Text = if ($preview) { $preview } else { Tr '(aucun message)' }
        $c.restart_length.Text = "$($preview.Length) / $($script:RestartMaxMessage)"
    }
    else {
        $c.restart_when.Text = ''
        $c.restart_preview.Text = ''
        $c.restart_length.Text = ''
    }
    $problem = if ($choice.Error) { $choice.Error } else { $choice.Warning }
    $c.restart_problem.Text = $problem
    $c.restart_problem.Visibility = ConvertTo-Visibility ([bool]$problem)
    $c.restart_problem.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($choice.Error) { 'R.DangerText' } else { 'R.WarnText' }))
    $c.restart_ok.IsEnabled = -not $choice.Error
}

function Show-RestartDialog($Computer, $Owner, $Icon) {
    # Asks for the delay and the message. Returns the Seconds and the Message to send (placeholders replaced when
    # Redémarrer is clicked), or $null for Annuler. Saves them as defaults when asked to.
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:RestartDialogXaml))
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = (Tr 'Redémarrer {0}') -f $Computer.ComputerName
    $dialog.Icon = $Icon
    $dialog.Owner = $Owner
    $dialog.SizeToContent = 'WidthAndHeight'
    $dialog.ResizeMode = 'NoResize'
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.Content = $root
    Set-WindowChrome $dialog

    $controls = @{}
    foreach ($name in 'restart_question', 'restart_amount', 'restart_unit', 'restart_when', 'restart_length', 'restart_message', 'restart_preview', 'restart_problem', 'restart_save', 'restart_ok', 'restart_cancel') {
        $controls[$name] = $root.FindName($name)
    }
    $state = @{ Controls = $controls }
    $dialog.Tag = $state

    $defaults = Read-RestartSetting
    $controls.restart_question.Text = (Tr 'Redémarrer {0} ({1}) ?') -f $Computer.ComputerName, $Computer.HostName
    $root.FindName('restart_hint').Text = Tr '{délai} et {heure} sont remplacés.'
    foreach ($unit in $script:RestartUnits.Keys) { $controls.restart_unit.Items.Add($script:RestartUnitTexts[$unit]) | Out-Null }
    $controls.restart_unit.SelectedItem = $script:RestartUnitTexts[$defaults.Unit]
    $controls.restart_amount.Text = [string]$defaults.Amount
    $controls.restart_message.Text = $defaults.Message
    Update-RestartDialog $state

    # The delay box takes digits only.
    $controls.restart_amount.Add_PreviewTextInput({ $e = $args[1]; if ($e.Text -notmatch '^\d+$') { $e.Handled = $true } })
    $update = { param($control) Update-RestartDialog ([System.Windows.Window]::GetWindow($control).Tag) }
    $controls.restart_amount.Add_TextChanged($update)
    $controls.restart_message.Add_TextChanged($update)
    $controls.restart_unit.Add_SelectionChanged($update)
    $controls.restart_ok.Add_Click({ param($button) [System.Windows.Window]::GetWindow($button).DialogResult = $true })
    $dialog.Add_ContentRendered({
        param($window)
        $box = $window.Tag.Controls.restart_amount
        $null = $box.Focus()
        $box.SelectAll()
    })

    # While it's open, a search that ends waits before replacing the rows.
    $script:search.Dialogs++
    try { $confirmed = $dialog.ShowDialog() }
    finally { $script:search.Dialogs-- }
    if (-not $confirmed) { return $null }

    $choice = Get-RestartChoice $state
    if ($choice.Error) { return $null }
    if ($controls.restart_save.IsChecked) { Save-RestartSetting $choice.Amount $choice.Unit $choice.Message }
    @{ Seconds = $choice.Seconds; Message = Expand-RestartMessage $choice.Message $choice.Amount $choice.Unit (Get-Date) }
}

function Get-ShutdownReport([string]$Kind, [string]$Name, [int]$Code, [string]$ErrorText) {
    # One report line from shutdown.exe's exit code, with Windows' own message when it isn't a known case.
    switch ($Code) {
        0 { if ($Kind -eq 'abort') { (Tr '✔ {0} : redémarrage annulé') -f $Name } else { (Tr '✔ {0} : redémarrage prévu, message affiché') -f $Name } }
        1116 { (Tr "✖ {0} : aucun redémarrage n'était prévu") -f $Name }
        1190 { (Tr '✖ {0} : un redémarrage est déjà prévu (Annuler le redémarrage pour le remplacer)') -f $Name }
        5 { (Tr "✖ {0} : accès refusé (il faut être administrateur de l'ordinateur)") -f $Name }
        53 { (Tr '✖ {0} : chemin réseau introuvable (ordinateur éteint ou injoignable ?)') -f $Name }
        -1 { (Tr '✖ {0} : pas de réponse après une minute (ordinateur éteint ou injoignable ?)') -f $Name }
        default {
            $detail = if ($ErrorText) { $ErrorText.Trim() } else { "code $Code" }
            ((Tr '✖ {0} : {1}') -f $Name, $detail)
        }
    }
}

function Start-Shutdown([string]$Title, [string]$Kind, $Computer, [string[]]$Arguments) {
    # Runs shutdown.exe in the background and reports it when it ends. With the fake AD, nothing is run: the command
    # is shown instead.
    if ($useFakeAD) {
        Show-Dialog -Title $Title -Message ((Tr "AD fictif : rien n'est lancé.") + "`n`n" + (Format-CommandLine 'shutdown.exe' $Arguments))
        return
    }
    try {
        $start = [System.Diagnostics.ProcessStartInfo]::new('shutdown.exe')
        foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardError = $true
        $start.RedirectStandardOutput = $true
        # shutdown.exe writes in the console's code page.
        $encoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $start.StandardErrorEncoding = $encoding
        $start.StandardOutputEncoding = $encoding
        $process = [System.Diagnostics.Process]::Start($start)
        $job = @{ Title = $Title; Kind = $Kind; Name = $Computer.ComputerName; Process = $process; Watch = [System.Diagnostics.Stopwatch]::StartNew()
                  Error = $process.StandardError.ReadToEndAsync(); Output = $process.StandardOutput.ReadToEndAsync() }
        $script:ShutdownJobs.Add($job)
        $script:ShutdownTimer.Start()
    }
    catch {
        Show-Dialog -Title $Title -Icon 'xcircle' -Tone 'danger' -Message ((Tr 'Impossible de lancer {0} : {1}') -f 'shutdown.exe', $_.Exception.Message)
    }
}

function Update-ShutdownJob {
    # On each tick: reports the commands that ended, or gave no answer within a minute.
    foreach ($job in @($script:ShutdownJobs)) {
        # Already reported by a tick that ran while a report's window was open (ShowDialog lets the timer run).
        if (-not $script:ShutdownJobs.Contains($job)) { continue }
        $code = $null
        if ($job.Process.HasExited) { $code = $job.Process.ExitCode }
        elseif ($job.Watch.Elapsed.TotalSeconds -ge 60) {
            try { $job.Process.Kill() } catch { Write-Verbose "shutdown.exe déjà terminé : $_" }
            $code = -1
        }
        if ($null -eq $code) { continue }
        $script:ShutdownJobs.Remove($job) | Out-Null
        $errorText = if ($job.Error.IsCompleted) { "$($job.Error.Result) $($job.Output.Result)" } else { '' }
        $job.Process.Dispose()
        $line = Get-ShutdownReport $job.Kind $job.Name $code $errorText
        # Off or unreachable (no network path, or no answer within a minute): a toast, as Vérifier en ligne says it.
        if ($code -in 53, -1) { Show-ActionNotice $job.Title $line $errorText.Trim() }
        else { Show-ActionReport @($line) -Title $job.Title }
    }
    if (-not $script:ShutdownJobs.Count) { $script:ShutdownTimer.Stop() }
}
$script:ShutdownTimer.Add_Tick({ Update-ShutdownJob })

function Invoke-ComputerRestart($Computer, $Owner, $Icon) {
    # Redémarrer…: the dialog, then shutdown /r /m \\<host> /t <seconds> /c <message>. /f closes the apps without
    # asking (Windows adds it itself as soon as there's a delay).
    $choice = Show-RestartDialog $Computer $Owner $Icon
    if (-not $choice) { return }
    $arguments = @('/r', '/f', '/m', "\\$($Computer.HostName)", '/t', [string]$choice.Seconds)
    if ($choice.Message) { $arguments += '/c', $choice.Message }
    Start-Shutdown (Tr 'Redémarrer') 'restart' $Computer $arguments
}

function Stop-ComputerRestart($Computer) {
    # Annuler le redémarrage: shutdown /a /m \\<host>, while the delay runs.
    Start-Shutdown (Tr 'Annuler le redémarrage') 'abort' $Computer @('/a', '/m', "\\$($Computer.HostName)")
}
