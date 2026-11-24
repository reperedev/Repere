# Reads that would freeze the window on a slow DC (a Propriétés window's, its member search, the dialogs' searches, the
# LAPS passwords and BitLocker keys) run
# on the search runspaces ($searchPool, which load the AD module), and their result comes back on the window's thread.
# A runspace has none of the script's functions or variables: Start-BackgroundRead sends the ones a read needs, and
# the row builder's helpers (Get-OUPath…). Dot-sourced by the main script, before the pages.

# The reads under way: each its PowerShell, the handle of its result, and what to do with it; and the timer that
# collects those that ended, made as the script loads like the window's other timers. (Not $BackgroundTimer: the main
# script has one, and variable names ignore case.)
$script:BackgroundReadList = [System.Collections.Generic.List[object]]::new()
$script:BackgroundReadTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:BackgroundReadTimer.Interval = [timespan]::FromMilliseconds(40)
$script:BackgroundReadTimer.Add_Tick({ Complete-BackgroundRead })

# How long a read may wait for its DC, in seconds, counted from when it starts on a runspace (one waiting for a free
# runspace isn't counted). A read is a few queries on one object, which a DC that answers gives in a second or two. A
# DC that's down makes Windows give up on the connection after about 21 seconds (TCP's retries), and the first read of
# a domain may then try another DC (Get-UserServer): 30 seconds leave room for that, and a read still waiting after it
# has a DC that stopped answering, not a slow one. A read that waits on something else as well (SCCM, with its own
# limit) asks for more time.
$script:ReadTimeout = 30
# The seconds a read of several computers gets for each one after its first (Get-ReadTimeout).
$script:ReadTimeoutEach = 2

function Get-ReadTimeout([int]$Count = 1) {
    # How long a read of $Count computers may wait, in seconds (Mot de passe LAPS…, Clés BitLocker…, the guard read of
    # Désactiver, Supprimer and Déplacer): they're read one after the other on one runspace. The first gets a read's 30
    # seconds, for a DC found down and the one asked in its place; each other one 2 seconds more, as it goes to a DC
    # that answers, in well under a second. 200 computers then get under 7 minutes, never stopped for being many.
    $script:ReadTimeout + $script:ReadTimeoutEach * [Math]::Max(0, $Count - 1)
}
# The reads stopped at their time limit: each one's PowerShell and the handle of its result, disposed once it ends. A
# call stuck on a DC may only return on its own, so it isn't waited for.
$script:BackgroundStopping = [System.Collections.Generic.List[object]]::new()

function Get-ReadTimeoutProblem([int]$Seconds) {
    # What a read's OnDone is told when its DC didn't answer in time.
    (Tr 'pas de réponse du contrôleur de domaine après {0} secondes') -f $Seconds
}

function Test-ReadTimedOut($Read, [datetime]$Now = [datetime]::UtcNow) {
    # Whether a read under way has run out of time: started on its runspace ($Read.Clock.Started, set there) at least
    # $Read.Timeout seconds ago, and not ended. A Timeout of 0 never runs out.
    $started = $Read.Clock.Started
    [bool]($Read.Timeout -gt 0 -and $Read.Handle -and -not $Read.Handle.IsCompleted -and $started -and ($Now - [datetime]$started).TotalSeconds -ge $Read.Timeout)
}

function Start-BackgroundRead {
    # Runs $Command with $Arguments on a search runspace, with $Functions defined there and $Variables as its
    # script-scope variables; then, on the window's thread, & $OnDone $Context $Result $Problem $TimedOut ($Problem: the
    # error's message, or $null). $Timeout: the most seconds it may run ($script:ReadTimeout by default, 0 for no
    # limit). Past it, the read is stopped, and $OnDone gets no result, Get-ReadTimeoutProblem as its problem and
    # $TimedOut $true.
    param(
        [Parameter(Mandatory)] [string]$Command,
        [object[]]$Arguments = @(),
        [string[]]$Functions = @(),
        [hashtable]$Variables = @{},
        [Parameter(Mandatory)] [scriptblock]$OnDone,
        $Context,
        [int]$Timeout = $script:ReadTimeout
    )
    # ConvertTo-FrenchError (Errors.ps1) on every one: a read says why a part of it couldn't be read.
    $Functions = @($Functions) + 'ConvertTo-FrenchError'
    $Variables = @{ FrenchErrors = $script:FrenchErrors } + $Variables
    $definitions = foreach ($name in @($Command) + $Functions | Select-Object -Unique) {
        "function $name {$([Environment]::NewLine)$((Get-Item "function:$name").Definition)$([Environment]::NewLine)}"
    }
    # When it starts on its runspace, for its time limit (Test-ReadTimedOut).
    $clock = [hashtable]::Synchronized(@{ Started = $null })
    $script = @"
param(`$Variables, `$Arguments, `$RowBuilder, `$Clock)
`$Clock.Started = [datetime]::UtcNow
. ([scriptblock]::Create(`$RowBuilder))
foreach (`$name in `$Variables.Keys) { Set-Variable -Scope Script -Name `$name -Value `$Variables[`$name] }
$($definitions -join [Environment]::NewLine)
& '$Command' @Arguments
"@
    $shell = [powershell]::Create()
    $shell.RunspacePool = $script:searchPool
    $null = $shell.AddScript($script).AddArgument($Variables).AddArgument($Arguments).AddArgument($script:rowBuilderScript).AddArgument($clock)
    # Asked while the runspaces are still opening (right after launch): started by the timer once they have.
    $handle = if ("$($script:searchPool.RunspacePoolStateInfo.State)" -notin 'BeforeOpen', 'Opening') { $shell.BeginInvoke() }
    $script:BackgroundReadList.Add(@{ Shell = $shell; Handle = $handle; OnDone = $OnDone; Context = $Context; Timeout = $Timeout; Clock = $clock })
    $script:BackgroundReadTimer.Start()
}

function Complete-BackgroundRead {
    # The reads that ran out of time: stopped without waiting for them, and their OnDone told why at once.
    foreach ($read in @($script:BackgroundReadList | Where-Object { Test-ReadTimedOut $_ })) {
        if (-not $script:BackgroundReadList.Remove($read)) { continue }
        $null = $read.Shell.BeginStop($null, $null)
        $script:BackgroundStopping.Add($read)
        try { & $read.OnDone $read.Context $null (Get-ReadTimeoutProblem $read.Timeout) $true }
        catch { Write-Host "Lecture en arrière-plan : $_" }
    }
    foreach ($read in @($script:BackgroundStopping | Where-Object { $_.Handle.IsCompleted })) {
        if ($script:BackgroundStopping.Remove($read)) { $read.Shell.Dispose() }
    }
    # Those that waited for the runspaces, which have opened or never will: the error then goes to their OnDone.
    if ("$($script:searchPool.RunspacePoolStateInfo.State)" -notin 'BeforeOpen', 'Opening') {
        foreach ($read in @($script:BackgroundReadList | Where-Object { -not $_.Handle })) {
            try { $read.Handle = $read.Shell.BeginInvoke() }
            catch {
                $why = $_.Exception.Message
                $null = $script:BackgroundReadList.Remove($read)
                $read.Shell.Dispose()
                try { & $read.OnDone $read.Context $null $why $false }
                catch { Write-Host "Lecture en arrière-plan : $_" }
            }
        }
    }
    # The reads that ended: their result (the last object written), or their error, to their OnDone.
    foreach ($read in @($script:BackgroundReadList | Where-Object { $_.Handle -and $_.Handle.IsCompleted })) {
        # Already collected by a tick that ran while an OnDone's window was open (ShowDialog lets the timer run).
        if (-not $script:BackgroundReadList.Remove($read)) { continue }
        $result, $problem = $null, $null
        try {
            $result = @($read.Shell.EndInvoke($read.Handle)) | Select-Object -Last 1
            # A hashtable comes back inside a PSObject.
            if ($result -is [psobject] -and $result.PSObject.BaseObject -is [hashtable]) { $result = $result.PSObject.BaseObject }
        }
        catch { $problem = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        finally { $read.Shell.Dispose() }
        try { & $read.OnDone $read.Context $result $problem $false }
        catch { Write-Host "Lecture en arrière-plan : $_" }
    }
    # Going on while a read stopped hasn't ended, so it's disposed of.
    if (-not $script:BackgroundReadList.Count -and -not $script:BackgroundStopping.Count) { $script:BackgroundReadTimer.Stop() }
}

function Stop-BackgroundRead($Context) {
    # The reads under way for $Context (a Propriétés window that closed), or with it as their context's State (its
    # members' search): stopped, so a slow DC doesn't keep a runspace busy for nothing. Their OnDone still runs, with
    # the stop as their problem, once the timer collects them.
    $mine = {
        param($read)
        [object]::ReferenceEquals($read.Context, $Context) -or ($read.Context -is [hashtable] -and [object]::ReferenceEquals($read.Context['State'], $Context))
    }
    foreach ($read in @($script:BackgroundReadList | Where-Object { $_.Handle -and -not $_.Handle.IsCompleted -and (& $mine $_) })) {
        $null = $read.Shell.BeginStop($null, $null)
    }
}

# A password or a recovery key copied: kept out of Windows' clipboard history and its sync to other devices, and cleared
# after a minute, or when Repère closes, while it's still what the clipboard holds. A clipboard another program holds
# then (rdpclip and clipboard managers often do) is tried again every RetryDelay, up to Retries times, and again when
# Repère closes: Text stays set until a try succeeds.
$script:SecretClipboard = @{
    Text = $null; Timer = [System.Windows.Threading.DispatcherTimer]::new()
    Delay = [timespan]::FromMinutes(1); RetryDelay = [timespan]::FromSeconds(2); Retries = 5; Failed = 0
}
$script:SecretClipboard.Timer.Interval = $script:SecretClipboard.Delay
$script:SecretClipboard.Timer.Add_Tick({ Clear-SecretClipboard })

function Set-ClipboardData([System.Windows.DataObject]$Data) {
    # $true once it's in the clipboard; $false when another program still holds the clipboard after WPF's own retries
    # (ten, 100 ms apart): the copy button then says so (Show-CopyFeedback) rather than the window freezing longer.
    try {
        [System.Windows.Clipboard]::SetDataObject($Data, $true)
        $true
    }
    catch {
        Write-Verbose "Presse-papiers occupé : $_"
        $false
    }
}

function Set-ClipboardText([string]$Text) {
    # Text that isn't a secret (a value of Propriétés): $true once copied, $false when the clipboard is held.
    $data = [System.Windows.DataObject]::new()
    $data.SetText($Text)
    Set-ClipboardData $data
}

function Set-SecretClipboard([string]$Text) {
    # $true once copied. Never copied any other way when the clipboard is held ($false): without these formats, the
    # password or key would stay in the clipboard history and could go to the user's other devices.
    $data = [System.Windows.DataObject]::new()
    $data.SetText($Text)
    foreach ($format in 'ExcludeClipboardContentFromMonitorProcessing', 'CanIncludeInClipboardHistory', 'CanUploadToCloudClipboard') {
        $data.SetData($format, [System.IO.MemoryStream]::new([byte[]](0, 0, 0, 0)))
    }
    if (-not (Set-ClipboardData $data)) { return $false }
    # A new minute for the new secret, even while the last one was being tried again: it's no longer in the clipboard.
    $script:SecretClipboard.Text = $Text
    $script:SecretClipboard.Failed = 0
    $script:SecretClipboard.Timer.Stop()
    $script:SecretClipboard.Timer.Interval = $script:SecretClipboard.Delay
    $script:SecretClipboard.Timer.Start()
    $true
}

function Register-SecretCopy([System.Windows.Controls.TextBox]$Box, [System.Windows.Controls.Button]$Button) {
    # A box that shows secrets for the user to copy (Show-Dialog's -SecretDetails: the BitLocker keys a deletion takes
    # with it). Ctrl+C, Ctrl+Insert and its menu's Copier (all ApplicationCommands.Copy) copy through
    # Set-SecretClipboard (Copy-SecretText): what's selected, or all of it. $Button always copies all of it: the keys
    # are about to be deleted, and a selection left over shouldn't make it copy part of them. WPF's own copy, which
    # would leave the keys in the clipboard history, never runs: the command is handled before it, and its data
    # object, which a drag of the selection also makes, is refused.
    $Box.Resources['Repere.SecretCopy'] = $Button
    $Button.CommandParameter = $Box
    $Button.Add_Click({ param($button) $null = Copy-SecretText $button.CommandParameter -All })
    [System.Windows.Input.CommandManager]::AddPreviewCanExecuteHandler($Box, [System.Windows.Input.CanExecuteRoutedEventHandler]{
        param($box, $e)
        # Even with nothing selected, as it then copies all.
        if ($e.Command -eq [System.Windows.Input.ApplicationCommands]::Copy) { $e.CanExecute = $true; $e.Handled = $true }
    })
    [System.Windows.Input.CommandManager]::AddPreviewExecutedHandler($Box, [System.Windows.Input.ExecutedRoutedEventHandler]{
        param($box, $e)
        if ($e.Command -eq [System.Windows.Input.ApplicationCommands]::Copy) { $e.Handled = $true; $null = Copy-SecretText $box }
    })
    [System.Windows.DataObject]::AddCopyingHandler($Box, [System.Windows.DataObjectCopyingEventHandler]{ param($box, $e) $e.CancelCommand() })
}

function Copy-SecretText([System.Windows.Controls.TextBox]$Box, [switch]$All) {
    # Register-SecretCopy's box to the clipboard, as a secret: its selection, or all of it (always, with -All). Its
    # Copier button shows what the copy did, from the keyboard too: « Copie impossible » when another program holds
    # the clipboard, and nothing copied any other way.
    $text = if ($Box.SelectionLength -and -not $All) { $Box.SelectedText } else { $Box.Text }
    $copied = Set-SecretClipboard $text
    $button = $Box.Resources['Repere.SecretCopy']
    if ($button) { Show-CopyFeedback $button $copied }
    $copied
}

function Remove-ClipboardSecret([string]$Text) {
    # The clipboard emptied when it still holds $Text; a copy made since is left alone. Throws when another program
    # holds the clipboard, after WPF's own retries (ten, 100 ms apart, for each of the read and the clear).
    if ([System.Windows.Clipboard]::GetText() -ceq $Text) { [System.Windows.Clipboard]::Clear() }
}

function Clear-SecretClipboard([switch]$Closing) {
    # The timer's tick, a minute after the copy, and Repère's closing (-Closing). Text is forgotten only once the
    # clipboard was read, and cleared if it still held the secret: forgotten before, a clipboard held at that moment
    # left the secret in it for good. A tick that fails comes back RetryDelay later, Retries times, then waits for the
    # closing, which tries three times in a row before giving up: each try already waits up to two seconds in WPF.
    $secret = $script:SecretClipboard
    $secret.Timer.Stop()
    if (-not $secret.Text) { return }
    $tries = if ($Closing) { 3 } else { 1 }
    for ($try = 1; $try -le $tries; $try++) {
        try {
            Remove-ClipboardSecret $secret.Text
            $secret.Text = $null
            $secret.Failed = 0
            $secret.Timer.Interval = $secret.Delay
            return
        }
        catch { Write-Verbose "Presse-papiers non effacé : $_" }
    }
    if ($Closing) { return }
    $secret.Failed++
    if ($secret.Failed -gt $secret.Retries) { return }
    $secret.Timer.Interval = $secret.RetryDelay
    $secret.Timer.Start()
}

# The reads the main window waits on (Mot de passe LAPS…, Clés BitLocker…), by kind.
$script:WindowReadList = [System.Collections.Generic.HashSet[string]]::new()
# The windows waiting on something in the background, and how many things each (Enter-BusyWindow): their pointer says
# so meanwhile, the window still usable. By reference: a Propriétés window that closed may still be waited on.
$script:BusyWindows = [System.Collections.Generic.Dictionary[object, int]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)

function Enter-BusyWindow($Window) {
    # One more thing $Window waits on: its pointer says something runs in the background (AppStarting).
    if (-not $Window) { return }
    $count = 0
    $null = $script:BusyWindows.TryGetValue($Window, [ref]$count)
    $script:BusyWindows[$Window] = $count + 1
    $Window.Cursor = [System.Windows.Input.Cursors]::AppStarting
}

function Exit-BusyWindow($Window) {
    # One thing less: its usual pointer back once it waits on nothing.
    if (-not $Window) { return }
    $count = 0
    if (-not $script:BusyWindows.TryGetValue($Window, [ref]$count)) { return }
    if ($count -gt 1) { $script:BusyWindows[$Window] = $count - 1; return }
    $null = $script:BusyWindows.Remove($Window)
    $Window.Cursor = $null
}

function Start-WindowRead {
    # A read whose result opens a window: Start-BackgroundRead, the main window usable meanwhile, its pointer saying
    # something runs in the background. The same kind asked again while it runs is ignored: one window, not two.
    # $Timeout: as Start-BackgroundRead's; $OnDone is told $TimedOut too.
    param(
        [Parameter(Mandatory)] [string]$Kind,
        [Parameter(Mandatory)] [string]$Command,
        [object[]]$Arguments = @(),
        [string[]]$Functions = @(),
        [hashtable]$Variables = @{},
        [Parameter(Mandatory)] [scriptblock]$OnDone,
        $Context,
        [int]$Timeout = $script:ReadTimeout
    )
    if (-not $script:WindowReadList.Add($Kind)) { return }
    Enter-BusyWindow $script:win
    try {
        Start-BackgroundRead -Command $Command -Arguments $Arguments -Functions $Functions -Variables $Variables -Timeout $Timeout `
            -Context @{ Kind = $Kind; OnDone = $OnDone; Context = $Context } -OnDone {
            param($read, $result, $problem, $timedOut)
            $null = $script:WindowReadList.Remove($read.Kind)
            Exit-BusyWindow $script:win
            & $read.OnDone $read.Context $result $problem $timedOut
        }
    }
    catch {
        # Not started: the next click can try again.
        $null = $script:WindowReadList.Remove($Kind)
        Exit-BusyWindow $script:win
        throw
    }
}
