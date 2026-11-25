# Prendre la main…: joins the session of the person at the computer (mstsc /shadow), instead of opening a new one as
# Bureau à distance does. The sessions are listed with quser, in the background; the user picks one, and whether to
# control it or only watch. Utilisateurs connectés… lists the same sessions, for each selected computer, without
# joining any. Dot-sourced by the main script, after Theme.ps1.
#
# On the domain, this needs the GPO « Définir les règles de contrôle à distance des sessions utilisateur des services
# Bureau à distance », AllowRemoteRPC = 1 on the computers, the « Remote Desktop - Shadow (TCP-In) » firewall rule,
# and being an administrator of the computer (see the README).

# Lists the computer's sessions: quser's text, its output and errors together. quser writes in the console's code
# page. With the fake AD, its module's quser answers for the fake computers. A quser that hasn't answered within
# $TimeoutSeconds (0: no limit) is stopped, and comes back TimedOut: one waiting on RPC would otherwise run on, long
# after Repère has said the computer doesn't answer.
$script:SessionQueryScript = {
    param([string]$HostName, [string]$FakeModule, [int]$TimeoutSeconds)
    if ($FakeModule) {
        Import-Module $FakeModule
        return [pscustomobject]@{ Text = (quser "/server:$HostName" 2>&1 | Out-String); TimedOut = $false }
    }
    $start = [System.Diagnostics.ProcessStartInfo]::new('quser.exe')
    $start.ArgumentList.Add("/server:$HostName")
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardOutput = $true
    $encoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    $start.StandardErrorEncoding = $encoding
    $start.StandardOutputEncoding = $encoding
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        $errors = $process.StandardError.ReadToEndAsync()
        $output = $process.StandardOutput.ReadToEndAsync()
        if ($TimeoutSeconds -gt 0 -and -not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { Write-Verbose "quser déjà terminé : $_" }
            return [pscustomobject]@{ Text = ''; TimedOut = $true }
        }
        $process.WaitForExit()
        [pscustomobject]@{ Text = "$($output.Result)$($errors.Result)"; TimedOut = $false }
    }
    finally { $process.Dispose() }
}.ToString()

function ConvertFrom-QuserOutput([string[]]$Lines) {
    # quser's lines, as sessions: UserName, SessionName (console, rdp-tcp#3, or empty for a disconnected one), Id,
    # Active, State (as quser says it, in Windows' language: Active, Actif, Disc, Déco), Idle and LogonTime. The header
    # and the error lines don't match: their third column isn't a number.
    foreach ($line in $Lines) {
        if ($line -notmatch '^\s?>?(?<user>\S+)\s+(?:(?<session>\S+)\s+)?(?<id>\d+)\s+(?<state>\S+)\s+(?<idle>\S+)\s+(?<logon>\S.*?)\s*$') { continue }
        # Kept apart: the next -match replaces $Matches.
        $parts = $Matches.Clone()
        [pscustomobject]@{
            UserName    = $parts.user
            # By key: a disconnected session has no name, nor its group in $Matches.
            SessionName = "$($parts['session'])"
            Id          = [int]$parts.id
            Active      = $parts.state -match '^Acti[fv]'
            State       = $parts.state
            Idle        = if ($parts.idle -in 'none', 'aucun', '.') { '' } else { $parts.idle }
            LogonTime   = $parts.logon
        }
    }
}

function Get-SessionQueryProblem([string]$Text) {
    # Why quser listed no session: nobody is logged on (Problem is $false), or what to check. quser says only text, in
    # Windows' language, and the same exit code for all: its errors are known by the codes that text holds in every
    # language (« Error 0x000006BA enumerating sessionnames », « Error [1722]: … »). Nobody logged on has no code, so it's
    # known by its text alone, in English or French; and so are the errors, as a last resort, without their code.
    switch -Regex ($Text) {
        '0x00000005|\[5\]' { return @{ Problem = $true; Message = Tr "Accès refusé : il faut être administrateur de l'ordinateur." } }
        '0x000006BA|\[1722\]' {
            return @{ Problem = $true; Message = Tr "L'ordinateur ne répond pas : il est éteint ou injoignable, ou il refuse les requêtes de sessions à distance (AllowRemoteRPC à 0, ou pare-feu)." }
        }
        'No User exists|Aucun utilisateur' { return @{ Problem = $false; Message = Tr "Personne n'a de session ouverte sur cet ordinateur." } }
        # Its accents matched by any letter: this pattern isn't shown.
        'Access is denied|Acc.s refus.' { return @{ Problem = $true; Message = Tr "Accès refusé : il faut être administrateur de l'ordinateur." } }
        'RPC' {
            return @{ Problem = $true; Message = Tr "L'ordinateur ne répond pas : il est éteint ou injoignable, ou il refuse les requêtes de sessions à distance (AllowRemoteRPC à 0, ou pare-feu)." }
        }
        default { return @{ Problem = $true; Message = Tr 'Les sessions ouvertes sur cet ordinateur n''ont pas pu être lues.' } }
    }
}

function Select-ShadowSession($Sessions) {
    # The session selected when the dialog opens: the first active one, in quser's order. $null selects none.
    @($Sessions | Where-Object Active)[0]
}

$script:ShadowDialogXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Padding="18" Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <StackPanel Width="600">
    <TextBlock x:Name="shadow_question" FontSize="15" FontWeight="{DynamicResource R.FontWeightStrong}" TextWrapping="Wrap"/>
    <TextBlock Style="{StaticResource Txt.Muted}" Margin="0,6,0,0" TextWrapping="Wrap"
               Text="Vous voyez l'écran en même temps que la personne, qui doit d'abord accepter."/>
    <Border Style="{StaticResource Card}" Margin="0,14,0,0">
      <DataGrid x:Name="shadow_grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="False" CanUserResizeColumns="True"
                CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Single" SelectionUnit="FullRow" HeadersVisibility="Column"
                GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{DynamicResource R.Border}" Background="Transparent" RowBackground="Transparent"
                Foreground="{DynamicResource R.Text}" BorderThickness="0" RowHeight="34" Margin="1" MaxHeight="240"
                RowStyle="{StaticResource Grid.Row}" CellStyle="{StaticResource Grid.Cell}" ColumnHeaderStyle="{StaticResource Grid.Header}">
        <DataGrid.Columns>
          <DataGridTextColumn Header="Utilisateur" Binding="{Binding UserName}" Width="*" ElementStyle="{StaticResource Grid.Text.Strong}"/>
          <DataGridTextColumn Header="Session" Binding="{Binding SessionName}" Width="100" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="ID" Binding="{Binding Id}" Width="44" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="État" Binding="{Binding State}" Width="74" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Inactivité" Binding="{Binding Idle}" Width="84" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Ouverte le" Binding="{Binding LogonTime}" Width="130" ElementStyle="{StaticResource Grid.Text}"/>
        </DataGrid.Columns>
      </DataGrid>
    </Border>
    <TextBlock x:Name="shadow_problem" Margin="0,10,0,0" TextWrapping="Wrap" Foreground="{DynamicResource R.WarnText}" Visibility="Collapsed"/>
    <CheckBox x:Name="shadow_control" Margin="0,14,0,0" IsChecked="True" Content="Contrôler la souris et le clavier (sinon, voir seulement)"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="shadow_ok" Style="{StaticResource Btn.Primary}" MinWidth="110" IsDefault="True">
        <StackPanel Orientation="Horizontal">{{icon:screenshare}}<TextBlock Text="Prendre la main" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="dialog_cancel" MinWidth="90" Margin="8,0,0,0" IsCancel="True" Content="Annuler"/>
    </StackPanel>
  </StackPanel>
</Border>
'@

function Update-ShadowDialog($State) {
    # A disconnected session has no screen to show: it can't be joined.
    $session = $State.Grid.SelectedItem
    $problem = if (-not $session) { Tr 'Choisissez une session.' }
               elseif (-not $session.Active) { (Tr "La session de {0} est déconnectée : il n'y a pas d'écran à voir. Elle peut être rejointe une fois que la personne se reconnecte.") -f $session.UserName }
    $State.Problem.Text = $problem
    $State.Problem.Visibility = ConvertTo-Visibility ([bool]$problem)
    $State.Ok.IsEnabled = -not $problem
}

function Show-ShadowDialog($Computer, $Sessions, $Owner, $Icon) {
    # Returns the Id of the session to join and whether to Control it, or $null for Annuler.
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:ShadowDialogXaml))
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = Tr 'Prendre la main'
    $dialog.Icon = $Icon
    $dialog.Owner = $Owner
    $dialog.SizeToContent = 'WidthAndHeight'
    $dialog.ResizeMode = 'NoResize'
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.Content = $root
    Set-WindowChrome $dialog

    $state = @{ Grid = $root.FindName('shadow_grid'); Problem = $root.FindName('shadow_problem'); Ok = $root.FindName('shadow_ok'); Control = $root.FindName('shadow_control') }
    $dialog.Tag = $state
    $root.FindName('shadow_question').Text = if (@($Sessions).Count -eq 1) { (Tr 'Une session est ouverte sur {0} :') -f $Computer.ComputerName }
                                             else { (Tr '{0} sessions sont ouvertes sur {1} :') -f @($Sessions).Count, $Computer.ComputerName }
    $state.Grid.ItemsSource = @($Sessions)
    $state.Grid.SelectedItem = Select-ShadowSession $Sessions
    Update-ShadowDialog $state

    $state.Grid.Add_SelectionChanged({ param($grid) Update-ShadowDialog ([System.Windows.Window]::GetWindow($grid).Tag) })
    $state.Ok.Add_Click({ param($button) [System.Windows.Window]::GetWindow($button).DialogResult = $true })
    $dialog.Add_ContentRendered({ param($window) $null = $window.Tag.Grid.Focus() })

    $script:search.Dialogs++
    try { $confirmed = $dialog.ShowDialog() }
    finally { $script:search.Dialogs-- }
    $session = $state.Grid.SelectedItem
    if (-not $confirmed -or -not $session -or -not $session.Active) { return $null }
    @{ Id = $session.Id; Control = [bool]$state.Control.IsChecked }
}

function Start-ShadowSession($Computer, [string]$FakeModule) {
    # Lists the sessions in the background (an unreachable computer takes a while to fail), then the dialog, then
    # mstsc /shadow. The window stays usable meanwhile.
    # quser is stopped at its time; the whole is given a little more, to hear it.
    $parameters = @{ HostName = $Computer.HostName; FakeModule = $FakeModule; TimeoutSeconds = $script:SessionQueryTimeout }
    Start-BackgroundAction $script:SessionQueryScript $parameters ($script:SessionQueryTimeout + 5) {
        param($output, $failure, $computer)
        $name = $computer.ComputerName
        $title = Tr 'Prendre la main'
        $answer = @($output)[-1]
        if (-not $failure -and $answer -and $answer.TimedOut) { $failure = (Tr 'pas de réponse après {0} secondes (ordinateur éteint ou injoignable ?)') -f $script:SessionQueryTimeout }
        # No answer in time: a toast, as Vérifier en ligne says it. An RPC error stays a dialog below: the computer may
        # be on and only refuse to list its sessions (AllowRemoteRPC), which is worth reading.
        if ($failure -and (Test-RemoteUnreachable $failure)) {
            Show-UnreachableNotice $title $name $failure
            return
        }
        if ($failure) {
            Show-ActionReport @((Tr '✖ {0} : {1}') -f $name, $failure) -Title $title
            return
        }
        $text = "$($answer.Text)".Trim()
        $sessions = @(ConvertFrom-QuserOutput ($text -split '\r?\n'))
        if (-not $sessions.Count) {
            $reason = Get-SessionQueryProblem $text
            if ($reason.Problem) { Show-Dialog -Title $title -Message ((Tr '✖ {0} : {1}') -f $name, $reason.Message) -Details $text }
            else { Show-Dialog -Title $title -Message ((Tr '{0} : {1}') -f $name, $reason.Message) }
            return
        }
        $choice = Show-ShadowDialog $computer $sessions $win $windowIcon
        if (-not $choice) { return }
        $arguments = "/v:$($computer.HostName) /shadow:$($choice.Id)"
        if ($choice.Control) { $arguments += ' /control' }
        Start-RemoteTool $title 'mstsc.exe' $arguments
    } $Computer
}

# Utilisateurs connectés…: the same quser on each computer, 16 at a time. Each computer's text comes back by its Id.
# Each has $Timeout seconds of its own: one that doesn't answer comes back TimedOut, and doesn't hold up the others.
# quser.exe is stopped at $Timeout (SessionQueryScript); the query is waited for a little longer, to hear it.
$script:ConnectedUserScript = {
    param($Computers, [string]$Query, [string]$FakeModule, [int]$Timeout)
    $Computers | ForEach-Object -ThrottleLimit 16 -Parallel {
        $computer = $_
        $shell = [powershell]::Create()
        $null = $shell.AddScript($using:Query).AddArgument($computer.HostName).AddArgument($using:FakeModule).AddArgument($using:Timeout)
        $handle = $shell.BeginInvoke()
        if ($handle.AsyncWaitHandle.WaitOne([timespan]::FromSeconds($using:Timeout + 3))) {
            $answer = try { @($shell.EndInvoke($handle))[0] } catch { [pscustomobject]@{ Text = $_.Exception.Message; TimedOut = $false } }
            $shell.Dispose()
            [pscustomobject]@{ Id = $computer.Id; Text = "$($answer.Text)".Trim(); TimedOut = [bool]$answer.TimedOut }
        }
        else {
            # The fake AD's quser, which isn't a process to stop: left to end on its own.
            $null = $shell.BeginStop($null, $null)
            [pscustomobject]@{ Id = $computer.Id; Text = ''; TimedOut = $true }
        }
    }
}.ToString()
# How long each computer has to answer Utilisateurs connectés…. $env:REPERE_SESSION_TIMEOUT, for the UI tests, sets
# another.
$script:SessionQueryTimeout = if ($env:REPERE_SESSION_TIMEOUT) { [int]$env:REPERE_SESSION_TIMEOUT } else { 25 }

function Format-SessionIdle([string]$Idle) {
    # quser's idle time, readable: 12 (minutes), 1:05 (hours and minutes), 2+03:10 (days). Otherwise as quser says it.
    switch -Regex ($Idle) {
        '^(\d+)$' { return '{0} min' -f [int]$Matches[1] }
        '^(\d+):(\d+)$' { return '{0} h {1} min' -f [int]$Matches[1], [int]$Matches[2] }
        '^(\d+)\+(\d+):\d+$' { return (Tr '{0} j {1} h') -f [int]$Matches[1], [int]$Matches[2] }
        default { return $Idle }
    }
}

function Format-SessionAbout($Session) {
    # What the report says of a session, after its user: « active, console, inactive depuis 12 min, ouverte le … ».
    $state = if ($Session.Active) { Tr 'active' } elseif ($Session.State -match '^(Disc|Déco)') { Tr 'déconnectée' } else { $Session.State }
    @(
        $state
        if ($Session.SessionName) { $Session.SessionName }
        if ($Session.Idle) { (Tr 'inactive depuis {0}') -f (Format-SessionIdle $Session.Idle) }
        (Tr 'ouverte le {0}') -f $Session.LogonTime
    ) -join ', '
}

function Format-ConnectedUser([string]$Name, [string]$Text, [int]$TimedOutAfter) {
    # A computer's line in the report, from its quser text: « ✔ ORD-01 : accueil (active, console, …) · jebertrand
    # (déconnectée, …) », « ORD-08 : Personne n'a de session… » (no mark), or « ✖ ORD-06 : Accès refusé… ».
    # $TimedOutAfter: the seconds it was given, when it didn't answer within them.
    if ($TimedOutAfter) { return (Tr '✖ {0} : {1}') -f $Name, ((Tr 'pas de réponse après {0} secondes (ordinateur éteint ou injoignable ?)') -f $TimedOutAfter) }
    $sessions = @(ConvertFrom-QuserOutput ($Text -split '\r?\n'))
    if (-not $sessions.Count) {
        $reason = Get-SessionQueryProblem $Text
        if ($reason.Problem) { return (Tr '✖ {0} : {1}') -f $Name, $reason.Message }
        return (Tr '{0} : {1}') -f $Name, $reason.Message
    }
    $users = foreach ($session in $sessions) { '{0} ({1})' -f $session.UserName, (Format-SessionAbout $session) }
    (Tr '✔ {0} : {1}') -f $Name, ($users -join ' · ')
}

function New-ConnectedUserList($Entries) {
    # The report's rows, as New-ReportList draws them ($Entries: each a Computer, its Line and its Sessions, in the
    # order shown), where each user signed in is a link to their Propriétés, and a computer with an active session
    # offers Prendre la main….
    $card = New-ReportList @($Entries | ForEach-Object Line)
    $details = @(Find-ReportDetail $card)
    for ($i = 0; $i -lt [Math]::Min($Entries.Count, $details.Count); $i++) {
        $entry = $Entries[$i]
        if (-not @($entry.Sessions).Count) { continue }
        $detail = $details[$i]
        $detail.Inlines.Clear()
        $first = $true
        foreach ($session in $entry.Sessions) {
            if (-not $first) { $detail.Inlines.Add([System.Windows.Documents.Run]::new(' · ')) }
            $first = $false
            $link = [System.Windows.Documents.Hyperlink]::new([System.Windows.Documents.Run]::new($session.UserName))
            $link.Tag = @{ Login = $session.UserName; Domain = $entry.Computer.Domain }
            $link.ToolTip = Tr 'Propriétés…'
            [System.Windows.Automation.AutomationProperties]::SetAutomationId($link, "session_user_$($i)_$($session.Id)")
            $link.Add_Click({ param($link) Register-SessionLink $link })
            $detail.Inlines.Add($link)
            $detail.Inlines.Add([System.Windows.Documents.Run]::new(" ($(Format-SessionAbout $session))"))
        }
        if (@($entry.Sessions | Where-Object Active).Count) {
            $detail.Inlines.Add([System.Windows.Documents.LineBreak]::new())
            $shadow = [System.Windows.Documents.Hyperlink]::new([System.Windows.Documents.Run]::new((Tr 'Prendre la main…')))
            $shadow.Tag = $entry.Computer
            [System.Windows.Automation.AutomationProperties]::SetAutomationId($shadow, "session_shadow_$i")
            $shadow.Add_Click({ param($link) Register-SessionLink $link })
            $detail.Inlines.Add($shadow)
        }
    }
    $card
}

function Register-SessionLink($Link) {
    # A link of the report clicked: followed once the click has returned, since what it opens waits (a modal window), and
    # a click through UI Automation would wait with it.
    $script:SessionLinkClicked = $Link
    $null = $Link.Dispatcher.BeginInvoke([Action]{ Invoke-SessionLink })
}

function Invoke-SessionLink {
    # A user's link opens their Propriétés over the report; Prendre la main… closes the report, then lists the
    # computer's sessions over the main window.
    $link = $script:SessionLinkClicked
    $script:SessionLinkClicked = $null
    if (-not $link) { return }
    $report = [System.Windows.Window]::GetWindow($link.Parent)
    if ($link.Tag -is [hashtable]) {
        Open-SessionUser $link.Tag.Login $link.Tag.Domain $report
        return
    }
    $report.Close()
    Start-ShadowSession $link.Tag $script:fakeADModule
}
$script:SessionLinkClicked = $null

function Find-ReportDetail($Element) {
    # The detail text of each row of a report (New-ReportList), in order: the third column of each row's grid.
    foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Element)) {
        if ($child -is [System.Windows.Controls.TextBlock] -and [System.Windows.Controls.Grid]::GetColumn($child) -eq 2) { $child }
        elseif ($child -is [System.Windows.DependencyObject]) { Find-ReportDetail $child }
    }
}

function Open-SessionUser([string]$Login, [string]$Domain, $Owner) {
    # A user signed in on a computer: their Propriétés, from the computer's domain first, then the forest's others, read
    # in the background (the report waits meanwhile). A local account of the computer is in none.
    if ($Owner.Cursor -eq [System.Windows.Input.Cursors]::Wait) { return }
    $Owner.Cursor = [System.Windows.Input.Cursors]::Wait
    $filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$(Get-LdapText $Login)))"
    $domains = @(@($Domain) + @($script:domainList | Where-Object { $_ -ne $Domain }) | Where-Object { $_ })
    try {
        Start-UserRowRead $filter $domains -Context @{ Owner = $Owner; Login = $Login } -OnDone {
            param($context, $row, $problem)
            $report = $context.Owner
            $report.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
            if (-not $report.IsVisible) { return }
            if ($row) {
                Show-UserDetail $row $report $script:windowIcon
                return
            }
            # Not found: a local account, unless a domain couldn't be read.
            $message = if ($problem) { (Tr '✖ {0} : propriétés non lues ({1})') -f $context.Login, $problem }
                       else { (Tr "{0} n'est un compte d'aucun domaine de la forêt : sans doute un compte local de l'ordinateur.") -f $context.Login }
            Show-Dialog -Title (Tr 'Utilisateurs connectés') -Icon 'info' -Owner $report -Message $message
        }
    }
    catch {
        # Not started: the report doesn't wait for it.
        $Owner.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
        Show-Dialog -Title (Tr 'Utilisateurs connectés') -Icon 'info' -Owner $Owner -Message ((Tr '✖ {0} : propriétés non lues ({1})') -f $Login, $_.Exception.Message)
    }
}

function Show-ConnectedUser($Computers, [string]$FakeModule) {
    # Who has a session on each computer, read in the background (an unreachable computer takes a while to fail), then
    # one dialog: the computers with sessions first, then those nobody is logged on, then those that couldn't be read.
    $inputs = for ($i = 0; $i -lt $Computers.Count; $i++) { [pscustomobject]@{ Id = $i; HostName = $Computers[$i].HostName } }
    # Each computer has its own time: the whole lasts at most that, per 16, and a little more.
    $timeout = ($script:SessionQueryTimeout + 10) * [math]::Ceiling($Computers.Count / 16)
    $parameters = @{ Computers = @($inputs); Query = $script:SessionQueryScript; FakeModule = $FakeModule; Timeout = $script:SessionQueryTimeout }
    Start-BackgroundAction $script:ConnectedUserScript $parameters $timeout {
        param($output, $failure, $computers)
        $title = Tr 'Utilisateurs connectés'
        if ($failure -and -not @($output).Count) {
            Show-ActionReport @($computers | ForEach-Object { (Tr '✖ {0} : {1}') -f $_.ComputerName, $failure }) -Title $title
            return
        }
        $answers = @{}
        foreach ($answer in @($output)) { $answers[[int]$answer.Id] = $answer }
        $entries = @(for ($i = 0; $i -lt $computers.Count; $i++) {
            $answer = $answers[$i]
            $text = if ($answer) { [string]$answer.Text } else { '' }
            $timedOut = if ($answer -and $answer.TimedOut) { $script:SessionQueryTimeout } else { 0 }
            @{
                Computer = $computers[$i]
                Line     = Format-ConnectedUser $computers[$i].ComputerName $text $timedOut
                Sessions = @(if (-not $timedOut) { ConvertFrom-QuserOutput ($text -split '\r?\n') })
            }
        })
        # Those with sessions first, then those nobody is logged on, then those that couldn't be read.
        $withSessions = @($entries | Where-Object { $_.Line.StartsWith('✔') })
        $sortedEntries = $withSessions + @($entries | Where-Object { -not $_.Line.StartsWith('✔') -and -not $_.Line.StartsWith('✖') }) + @($entries | Where-Object { $_.Line.StartsWith('✖') })
        $sorted = @($sortedEntries | ForEach-Object { $_.Line })
        if ($computers.Count -eq 1) {
            $heading = (Tr 'Qui est connecté à {0} ?') -f $computers[0].ComputerName
            $message = ''
        }
        else {
            $heading = (Tr 'Qui est connecté à ces {0} ordinateurs ?') -f $computers.Count
            $message = (Tr 'Sessions ouvertes sur {0} des {1} ordinateurs.') -f $withSessions.Count, $computers.Count
        }
        Show-Dialog -Title $title -Heading $heading -Message $message -Icon 'user' -Content (New-ConnectedUserList $sortedEntries) `
            -MessageName ((@($heading, $message, (Format-ComputerList $sorted)) -ne '') -join "`n")
    } $Computers
}
