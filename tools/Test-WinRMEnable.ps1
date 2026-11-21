# Tries Activer WinRM (#316) on a real computer, outside Repere's window: the same functions (src\RemoteAccess.ps1),
# run the same way (a background runspace, as Start-BackgroundAction does), then what the fix does when that fails
# (asks WinRM whether it answers), then a request over WinRM, then WinRM put back as it was. Each scheduled task
# command is listed as it runs, and the one that fails says why.
#
# Run it in PowerShell 7.5 or later, as an administrator of the computer, on a computer where WinRM is off:
#   pwsh -File tools\Test-WinRMEnable.ps1 -ComputerName ORD-05.domaine.local
# Should it stop halfway, the task Repere-WinRM-<you> it leaves on the computer puts WinRM back after -Hours, or at
# the computer's next start.

param(
    [Parameter(Mandatory)] [string]$ComputerName,
    [int]$Hours = 1
)
$ErrorActionPreference = 'Stop'

# Repere's messages, as they are (no translation needed here).
function Tr([string]$Text) { $Text }
$script:LanguageScript = 'function Tr([string]$Text) { $Text }'
. (Join-Path $PSScriptRoot '..\src\RemoteAccess.ps1')

function Write-Step([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }

function Invoke-InRunspace([string]$Script, [hashtable]$Parameters) {
    # As Start-BackgroundAction / Update-BackgroundAction (ComputerActions.ps1): its output, and the error the way
    # Repere reads it (EndInvoke's exception, else the error stream's first record), with where it came from.
    $shell = [powershell]::Create([System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2())
    $null = $shell.AddScript($Script).AddParameters($Parameters)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $handle = $shell.BeginInvoke()
    while (-not $handle.IsCompleted) { Start-Sleep -Milliseconds 250 }
    $result = [ordered]@{ Output = $null; Failure = $null; Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1) }
    try {
        $result.Output = @($shell.EndInvoke($handle))
        if ($shell.Streams.Error.Count) {
            $record = $shell.Streams.Error[0]
            $result.Failure = $record.Exception.Message
            Write-Host "  error type : $($record.Exception.GetType().FullName)" -ForegroundColor Yellow
            Write-Host "  where      :`n$($record.ScriptStackTrace -replace '(?m)^', '    ')" -ForegroundColor Yellow
            if ($record.Exception.InnerException) { Write-Host "  inner      : $($record.Exception.InnerException)" -ForegroundColor Yellow }
            Write-Host "  .NET stack :`n$("$($record.Exception.StackTrace)" -replace '(?m)^', '    ')" -ForegroundColor DarkYellow
        }
    }
    catch {
        # Thrown by EndInvoke itself: the runspace's pipeline failed, not a command in it.
        $thrown = $_.Exception.InnerException ?? $_.Exception
        $result.Failure = $thrown.Message
        $innermost = $thrown
        while ($innermost.InnerException) { $innermost = $innermost.InnerException }
        Write-Host "  error type : $($innermost.GetType().FullName)" -ForegroundColor Yellow
        if ($thrown -is [System.Management.Automation.IContainsErrorRecord] -and $thrown.ErrorRecord.ScriptStackTrace) {
            Write-Host "  where      :`n$($thrown.ErrorRecord.ScriptStackTrace -replace '(?m)^', '    ')" -ForegroundColor Yellow
        }
        Write-Host "  .NET stack :`n$("$($innermost.StackTrace)" -replace '(?m)^', '    ')" -ForegroundColor DarkYellow
    }
    finally {
        if ($shell.Streams.Information.Count) {
            Write-Host '  calls (seconds since the start):' -ForegroundColor Gray
            foreach ($line in $shell.Streams.Information) { Write-Host "    $($line.MessageData)" -ForegroundColor Gray }
        }
        $shell.Dispose()
    }
    [pscustomobject]$result
}

# Each scheduled task command Repere's functions run, logged when it starts and when it fails, to tell which one
# throws: the same command (ScheduledTasks\…), with the same parameters, behind a function of its name.
$callLog = {
    # Loaded first: loaded by the first call, the modules' commands would replace these.
    Import-Module ScheduledTasks, CimCmdlets
    $script:CallWatch = [System.Diagnostics.Stopwatch]::StartNew()
    function Write-CallLog([string]$Text) { Write-Information ('{0,6:0.0}  {1}' -f $script:CallWatch.Elapsed.TotalSeconds, $Text) }
    function Invoke-Logged([string]$Name, $Parameters, [string]$Module = 'ScheduledTasks', [string]$TaskName = $Parameters['TaskName']) {
        $what = "$Name $TaskName"
        Write-CallLog $what
        try { & "$Module\$Name" @Parameters }
        catch {
            $exception = $_.Exception
            while ($exception.InnerException) { $exception = $exception.InnerException }
            Write-CallLog "  FAILED: $what : $($exception.GetType().Name): $($exception.Message)"
            throw
        }
    }
    function Get-ScheduledTask { [CmdletBinding()] param($CimSession, $TaskName, $TaskPath) Invoke-Logged Get-ScheduledTask $PSBoundParameters }
    function Get-ScheduledTaskInfo { [CmdletBinding()] param($CimSession, $TaskName, $TaskPath) Invoke-Logged Get-ScheduledTaskInfo $PSBoundParameters }
    function Start-ScheduledTask { [CmdletBinding()] param($CimSession, $TaskName, $TaskPath) Invoke-Logged Start-ScheduledTask $PSBoundParameters }
    function Unregister-ScheduledTask { [CmdletBinding(SupportsShouldProcess)] param($CimSession, $TaskName, $TaskPath) Invoke-Logged Unregister-ScheduledTask $PSBoundParameters }
    function Register-ScheduledTask {
        [CmdletBinding()] param($CimSession, $TaskName, $TaskPath, $Action, $Trigger, $Settings, $Principal, $Description, [switch]$Force)
        Invoke-Logged Register-ScheduledTask $PSBoundParameters
    }
    function Remove-CimInstance {
        [CmdletBinding()] param([Parameter(ValueFromPipeline)] $InputObject, $CimSession)
        process { Invoke-Logged Remove-CimInstance $PSBoundParameters CimCmdlets $InputObject.TaskName }
    }
}.ToString()

$common = @{ HostName = $ComputerName; FakeModule = ''; RemoteAccessScript = $script:RemoteAccessScript }

Write-Step "PowerShell $($PSVersionTable.PSVersion), $ComputerName"
if (Test-RemotePort $ComputerName 5985) {
    Write-Host "WinRM's port 5985 already answers on $ComputerName : Repere wouldn't offer Activer WinRM there. Pick a computer where WinRM is off." -ForegroundColor Red
    exit 1
}
Write-Host 'Port 5985 closed: WinRM is off, as expected.'

Write-Step '1. Activer WinRM, as Repere runs it'
$enable = Invoke-InRunspace {
    param([string]$HostName, [int]$Hours, [string]$FakeModule, [string]$RemoteAccessScript, [string]$CallLog)
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($RemoteAccessScript))
    . ([scriptblock]::Create($CallLog))
    [pscustomobject]@{ Until = Enable-TemporaryWinRM $HostName (Get-LocalAddress) $Hours }
}.ToString() ($common + @{ Hours = $Hours; CallLog = $callLog })
if ($enable.Failure) { Write-Host "FAILED after $($enable.Seconds) s: $($enable.Failure)" -ForegroundColor Red }
else { Write-Host "OK after $($enable.Seconds) s. The computer puts WinRM back on its own at $(@($enable.Output)[-1].Until)." -ForegroundColor Green }

Write-Step '2. Does WinRM answer now? (what the fix asks before reporting a failure)'
$answer = Invoke-InRunspace {
    param([string]$HostName, [string]$FakeModule, [string]$RemoteAccessScript)
    . ([scriptblock]::Create($RemoteAccessScript))
    (Test-RemotePort $HostName 5985) -and (Test-RemoteWinRM $HostName)
}.ToString() $common
$answers = -not $answer.Failure -and [bool]@($answer.Output)[-1]
if ($answers) { Write-Host 'Yes: with the fix, Repere goes on and opens the terminal or Caracteristiques.' -ForegroundColor Green }
else { Write-Host 'No: with the fix, Repere still says WinRM non active, with the error of step 1.' -ForegroundColor Red }

if ($answers) {
    Write-Step '3. A request over WinRM (what the terminal and Caracteristiques need)'
    try {
        $name = Invoke-Command -ComputerName $ComputerName -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
        Write-Host "OK: Invoke-Command answered from $name." -ForegroundColor Green
    }
    catch { Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Step '4. WinRM put back as it was'
$restore = Invoke-InRunspace {
    param([string]$HostName, [string]$FakeModule, [string]$RemoteAccessScript, [string]$CallLog)
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($RemoteAccessScript))
    . ([scriptblock]::Create($CallLog))
    Restore-TemporaryWinRM $HostName
}.ToString() ($common + @{ CallLog = $callLog })
if ($restore.Failure) { Write-Host "FAILED: $($restore.Failure.TrimEnd('.')). The computer will do it itself, at the latest at its next start." -ForegroundColor Red }
else { Write-Host "OK. Port 5985 answers now: $(Test-RemotePort $ComputerName 5985)." -ForegroundColor Green }
