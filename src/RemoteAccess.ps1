# Forcer les stratégies and PowerShell à distance on a computer where WinRM doesn't answer, without PsExec: what has to
# run there goes through a scheduled task, created over CIM (WinRM, else DCOM, the connection Caractéristiques falls back
# to), run as SYSTEM, then deleted. It needs being an administrator of the computer. Dot-sourced by the main script,
# after Language.ps1; the background actions (ComputerActions.ps1) run the same functions from $RemoteAccessScript.
#
# PowerShell à distance turns WinRM on for the technician's session only: the service, its HTTP listener, and a firewall
# rule that lets only this computer's addresses in. Before changing anything, it registers on the computer a task that
# puts back what it changed (Repere-WinRM-<user>, as the rule): Repère runs it when its last terminal to that computer
# closes, and the task runs on its own after a few hours or when the computer starts, should Repère not be there to
# (closed, crashed, network lost). It deletes the technician's rule, and puts the service and its listener back only
# once no other Repère rule is left (another technician's session), then deletes itself.
#
# With the fake AD, its module replaces the CIM, scheduled task and port commands used here.

$script:RemoteAccessScript = {
    function New-RemoteCimSession([string]$HostName, [int]$TimeoutSeconds = 15, [switch]$DcomOnly) {
        # WinRM first, then DCOM, which domain computers usually answer without any setup. -DcomOnly: WinRM is known not
        # to answer.
        $common = @{ ComputerName = $HostName; OperationTimeoutSec = $TimeoutSeconds; ErrorAction = 'Stop' }
        $wsmanError = $null
        if (-not $DcomOnly) {
            try { return New-CimSession @common }
            catch { $wsmanError = $_ }
        }
        try { New-CimSession @common -SessionOption (New-CimSessionOption -Protocol Dcom) }
        catch {
            # The messages, said as one, and the errors kept with them for their codes (Get-ErrorKind, Errors.ps1).
            $message = if ($wsmanError) { (Tr 'WinRM : {0} | DCOM : {1}') -f $wsmanError.Exception.Message.Trim(), $_.Exception.Message.Trim() }
                       else { (Tr 'DCOM : {0}') -f $_.Exception.Message.Trim() }
            $failure = [System.Exception]::new($message, $_.Exception)
            $failure.Data['Repere.Causes'] = @($wsmanError, $_)
            throw $failure
        }
    }

    function Test-RemotePort([string]$HostName, [int]$Port, [int]$TimeoutMilliseconds = 2000) {
        # Whether the computer accepts a connection on the port within the time. The fake AD answers for its computers.
        if (Get-Command Test-ComputerPort -ErrorAction Ignore) { return [bool](Test-ComputerPort $HostName $Port $TimeoutMilliseconds) }
        $client = [System.Net.Sockets.TcpClient]::new()
        try { $client.ConnectAsync($HostName, $Port).Wait($TimeoutMilliseconds) }
        catch { $false }
        finally { $client.Dispose() }
    }

    function Get-RemoteTaskDescription([string]$What) {
        # Who asked, for whoever finds the task on the computer.
        (Tr 'Repère : {0}, par {1} depuis {2}') -f $What, "$env:USERDOMAIN\$env:USERNAME", $env:COMPUTERNAME
    }

    function New-RemoteTaskSetting([timespan]$TimeLimit) {
        # A laptop on battery runs it too: tasks are set not to by default.
        New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit $TimeLimit
    }

    function Invoke-RemoteTask {
        # Runs one command on the computer as SYSTEM, through a task registered for it, and returns its exit code once
        # it ends. The task is deleted after; should Repère not get to it, it expires in 30 minutes and Windows deletes
        # it then.
        param($CimSession, [string]$Name, [string]$Execute, [string]$Argument, [string]$Description, [int]$TimeoutSeconds = 150)
        $task = @{ CimSession = $CimSession; TaskName = $Name; TaskPath = '\' }
        $now = Get-Date
        # In the past, by more than the 5 minutes a domain's clocks can differ, so it never starts on its own.
        $trigger = New-ScheduledTaskTrigger -Once -At $now.AddMinutes(-10)
        # The Task Scheduler reads it as an XML date, whatever the technician's culture: in a custom format, ':' is the
        # culture's time separator (fi-FI writes 14.30.00) and the calendar is the culture's (th-TH writes the year 2569).
        $trigger.EndBoundary = $now.AddMinutes(30).ToUniversalTime().ToString("yyyy-MM-dd'T'HH':'mm':'ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        $settings = New-RemoteTaskSetting (New-TimeSpan -Minutes 5)
        $settings.DeleteExpiredTaskAfter = 'PT0S'
        $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $action = New-ScheduledTaskAction -Execute $Execute -Argument $Argument
        $null = Register-ScheduledTask @task -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $Description -Force -ErrorAction Stop
        try {
            Start-ScheduledTask @task -ErrorAction Stop
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($true) {
                Start-Sleep -Milliseconds 500
                $info = Get-ScheduledTaskInfo @task -ErrorAction Stop
                # 0x41301: still running; 0x41303: not started yet.
                if ($info.LastTaskResult -notin 0x41301, 0x41303 -and (Get-ScheduledTask @task -ErrorAction Stop).State -ne 'Running') { return [long]$info.LastTaskResult }
                if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw (Tr "la tâche planifiée n'a pas fini après {0} secondes") -f $TimeoutSeconds }
            }
        }
        finally {
            # Deleted as Unregister-ScheduledTask does it (cim:DeleteInstance), without its confirmation: it asks (there's
            # no one to answer here) unless given -Confirm:$false, which a DCOM session refuses (« does not support the
            # -Confirm switch »). PowerShell 7.6 and later report that as « The CancellationTokenSource has been
            # disposed », whatever -ErrorAction says, after the task did its work (#316).
            # Only the task of that very name: Get-ScheduledTask's name is a pattern (WQL's LIKE, where _ stands for any
            # character).
            Get-ScheduledTask @task -ErrorAction Ignore | Where-Object { $_.TaskName -eq $Name -and $_.TaskPath -eq '\' } |
                Remove-CimInstance -CimSession $CimSession -ErrorAction Ignore
        }
    }

    function Invoke-PolicyUpdateTask([string]$HostName) {
        # gpupdate for the computer's policies, run by a task: the exit code, 0 when they were applied. Without
        # /target:computer, SYSTEM's own user policies would be updated too, for nothing.
        $session = New-RemoteCimSession $HostName
        try {
            Invoke-RemoteTask -CimSession $session -Name "Repere-gpupdate-$([guid]::NewGuid().ToString('N').Substring(0, 8))" -Execute 'gpupdate.exe' `
                -Argument '/target:computer /force /wait:120' -Description (Get-RemoteTaskDescription 'gpupdate')
        }
        finally { Remove-CimSession $session -ErrorAction Ignore }
    }

    function Get-WinRMState($CimSession) {
        # What PowerShell à distance changes, as it is before: the service's start mode (Auto, Manual, Disabled) and
        # whether it runs, and whether WinRM has an HTTP listener already, its own or a GPO's.
        $service = Get-CimInstance -CimSession $CimSession -ClassName Win32_Service -Filter "Name = 'WinRM'" -ErrorAction Stop | Select-Object -First 1
        if (-not $service) { throw (Tr "le service WinRM n'existe pas sur cet ordinateur") }
        $hklm = [uint32]2147483650
        $registry = @{ CimSession = $CimSession; Namespace = 'root\cimv2'; ClassName = 'StdRegProv'; ErrorAction = 'Stop' }
        $listeners = Invoke-CimMethod @registry -MethodName EnumKey -Arguments @{ hDefKey = $hklm; sSubKeyName = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener' }
        $policy = Invoke-CimMethod @registry -MethodName GetDWORDValue -Arguments @{ hDefKey = $hklm; sSubKeyName = 'SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'; sValueName = 'AllowAutoConfig' }
        $ownListener = $listeners.ReturnValue -eq 0 -and [bool]@($listeners.sNames | Where-Object { $_ -like '*+HTTP' }).Count
        $policyListener = $policy.ReturnValue -eq 0 -and $policy.uValue -eq 1
        [pscustomobject]@{ StartMode = [string]$service.StartMode; Running = $service.State -eq 'Running'; Listener = $ownListener -or $policyListener }
    }

    function Get-WinRMRuleName([string]$User = $env:USERNAME) {
        # The technician's firewall rule, and the task that puts WinRM back, both by this name: each technician's
        # restore deletes only their own rule, and another's session on the same computer stays. It reaches netsh's and
        # schtasks' command lines unquoted, so anything but ASCII letters, digits, '.', '_' and '-' is replaced.
        'Repere-WinRM-' + ($User -replace '[^A-Za-z0-9._-]', '_')
    }

    function Get-WinRMEnableArgument($State, [string[]]$Addresses, [string]$RuleName = (Get-WinRMRuleName)) {
        # cmd.exe's arguments to turn WinRM on, as far as it isn't: each step only if the next can run (&&), so the exit
        # code is the first failure's, then the firewall rule for these addresses. Each address is checked and written
        # back by .NET: nothing else can reach the command line.
        $ips = @(foreach ($text in $Addresses) {
            $ip = $null
            if ([System.Net.IPAddress]::TryParse("$text", [ref]$ip)) { [System.Net.IPAddress]::new($ip.GetAddressBytes()).ToString() }
        }) | Select-Object -Unique
        if (-not @($ips).Count) { throw (Tr 'aucune adresse IP de cet ordinateur à laisser passer') }
        $steps = @(
            if ($State -and $State.StartMode -eq 'Disabled') { 'sc.exe config WinRM start= demand' }
            if ($State -and -not $State.Running) { 'net.exe start WinRM' }
            if ($State -and -not $State.Listener) { 'cscript.exe //nologo %windir%\System32\winrm.vbs create winrm/config/Listener?Address=*+Transport=HTTP' }
            "netsh.exe advfirewall firewall add rule name=$RuleName dir=in action=allow protocol=TCP localport=5985 profile=any remoteip=$($ips -join ',')"
        )
        '/c ' + ($steps -join ' && ')
    }

    function Get-WinRMRestoreArgument($State, [string]$RuleName = (Get-WinRMRuleName)) {
        # cmd.exe's arguments to put back what Get-WinRMEnableArgument changed, every step whatever the others do (&).
        # The service and its listener only once findstr finds no Repère rule left: another technician's, or an older
        # Repère's (plain Repere-WinRM), whose session still needs them. The listener can only be deleted while the
        # service runs, which it may not when this runs as the computer starts. The task deletes itself only once its
        # rule is gone (netsh's show fails): otherwise it stays, and runs again at its time or when the computer starts.
        $service = @(
            if (-not $State.Listener) { 'net.exe start WinRM', 'cscript.exe //nologo %windir%\System32\winrm.vbs delete winrm/config/Listener?Address=*+Transport=HTTP' }
            if (-not $State.Running) { 'net.exe stop WinRM /y' }
            if ($State.StartMode -eq 'Disabled') { 'sc.exe config WinRM start= disabled' }
        )
        $steps = @(
            "netsh.exe advfirewall firewall delete rule name=$RuleName"
            if ($service) { "(netsh.exe advfirewall firewall show rule name=all | findstr.exe /i /l Repere-WinRM >nul || ($($service -join ' & ')))" }
            "(netsh.exe advfirewall firewall show rule name=$RuleName >nul || schtasks.exe /Delete /TN \$RuleName /F)"
        )
        '/c ' + ($steps -join ' & ')
    }

    function Get-WinRMRestoreState([string]$Argument) {
        # What WinRM was before Repère turned it on, read back from what a task of Get-WinRMRestoreArgument (this
        # version's or an older one's) puts back. Only Disabled matters of the start mode.
        [pscustomobject]@{
            StartMode = if ($Argument -match 'start= disabled') { 'Disabled' } else { 'Manual' }
            Running   = $Argument -notmatch 'net\.exe stop WinRM'
            Listener  = $Argument -notmatch 'winrm\.vbs delete'
        }
    }

    function Test-WinRMRule($CimSession, [string]$Name) {
        # Whether the computer's firewall has a rule by that name (netsh's name is the rule's DisplayName).
        [bool]@(Get-CimInstance -CimSession $CimSession -Namespace 'root\StandardCimv2' -ClassName MSFT_NetFirewallRule -Filter "DisplayName = '$Name'" -ErrorAction Stop).Count
    }

    function Enable-TemporaryWinRM([string]$HostName, [string[]]$Addresses, [int]$Hours = 4) {
        # Turns WinRM on until Restore-TemporaryWinRM, or $Hours, or the computer's next start, then waits for it to
        # answer. Returns when the computer puts it back on its own (local time).
        $session = New-RemoteCimSession $HostName -DcomOnly
        $name = Get-WinRMRuleName
        try {
            $restore = @{ CimSession = $session; TaskName = $name; TaskPath = '\' }
            $existing = Get-ScheduledTask @restore -ErrorAction Ignore
            $state = Get-WinRMState $session
            if ($existing) {
                # Turned on by this technician already (a terminal this Repère lost track of), or tried and failed, its
                # task staying: that task puts back what it found, and only what's missing is done now.
                $until = @($existing.Triggers | ForEach-Object { $_.StartBoundary } | Where-Object { $_ } | ForEach-Object { ([datetimeoffset]$_).LocalDateTime })[0]
            }
            else {
                # Turned on by other technicians (or an older Repère, whose task is plain Repere-WinRM): what WinRM is now
                # is their doing, and what to put back once the last of them is done is what their tasks found. Repère
                # only turns things on, so whatever one of them found off was off.
                $found = @($state) + @(Get-ScheduledTask -CimSession $session -TaskName 'Repere-WinRM*' -TaskPath '\' -ErrorAction Ignore |
                    Where-Object { "$(@($_.Actions)[0].Arguments)" -like '*firewall delete rule*' } | ForEach-Object { Get-WinRMRestoreState @($_.Actions)[0].Arguments })
                $before = [pscustomobject]@{
                    StartMode = if ($found.StartMode -contains 'Disabled') { 'Disabled' } else { $state.StartMode }
                    Running   = $found.Running -notcontains $false
                    Listener  = $found.Listener -notcontains $false
                }
                # Registered first, so that it can put back what the next step changes even when that step fails halfway.
                $until = (Get-Date).AddHours($Hours)
                $later = New-ScheduledTaskTrigger -Once -At $until
                $boot = New-ScheduledTaskTrigger -AtStartup
                $settings = New-RemoteTaskSetting (New-TimeSpan -Minutes 10)
                # A computer asleep at that time does it when it wakes up.
                $settings.StartWhenAvailable = $true
                $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
                $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument (Get-WinRMRestoreArgument $before $name)
                $null = Register-ScheduledTask @restore -Action $action -Trigger $later, $boot -Settings $settings -Principal $principal `
                    -Description (Get-RemoteTaskDescription (Tr 'remet WinRM comme avant PowerShell à distance')) -Force -ErrorAction Stop
            }
            $code = Invoke-RemoteTask -CimSession $session -Name "Repere-WinRM-on-$([guid]::NewGuid().ToString('N').Substring(0, 8))" -Execute 'cmd.exe' `
                -Argument (Get-WinRMEnableArgument $state $Addresses $name) -Description (Get-RemoteTaskDescription (Tr 'active WinRM pour PowerShell à distance')) -TimeoutSeconds 60
            if ($code -ne 0) {
                if (-not $existing) { Start-ScheduledTask @restore -ErrorAction Ignore }
                throw (Tr "WinRM n'a pas pu être activé (code {0})") -f $code
            }
        }
        finally { Remove-CimSession $session -ErrorAction Ignore }
        # The listener may take a moment to accept connections.
        $open = $false
        for ($i = 0; $i -lt 15 -and -not $open; $i++) {
            $open = Test-RemotePort $HostName 5985 1000
            if (-not $open) { Start-Sleep -Milliseconds 500 }
        }
        if (-not $open) {
            if ($existing) { throw (Tr 'WinRM a été activé mais ne répond pas : un autre pare-feu bloque sans doute le port 5985.') }
            Restore-TemporaryWinRM $HostName
            throw (Tr 'WinRM a été activé mais ne répond pas : un autre pare-feu bloque sans doute le port 5985. Il a été remis comme avant.')
        }
        # The port accepting a connection only says the firewall lets it through: what needs WinRM (the terminal's
        # Enter-PSSession) opens once WinRM itself answers this account, 20 tries a second apart. After that, it opens
        # all the same, and says what Windows says.
        for ($i = 0; $i -lt 20 -and -not (Test-RemoteWinRM $HostName); $i++) { Start-Sleep -Seconds 1 }
        $until
    }

    function Test-RemoteWinRM([string]$HostName) {
        # Whether WinRM answers a request with the technician's account, as Enter-PSSession and New-CimSession reach it.
        try {
            $null = Test-WSMan -ComputerName $HostName -Authentication Default -ErrorAction Stop
            $true
        }
        catch { $false }
    }

    function Restore-TemporaryWinRM([string]$HostName) {
        # Runs the technician's task on the computer now, and waits for it to end. Nothing to do when it's gone already
        # (it ran on its own). The task's exit code says nothing (its steps run whatever the others do), so its rule is
        # checked after: when it's still there, the task stayed, and the computer tries again at its time or next start.
        $session = New-RemoteCimSession $HostName -DcomOnly
        try {
            $name = Get-WinRMRuleName
            $restore = @{ CimSession = $session; TaskName = $name; TaskPath = '\' }
            if (-not (Get-ScheduledTask @restore -ErrorAction Ignore)) { return }
            # A task that keeps its rule doesn't delete itself: it ended once it no longer runs and has run since.
            $lastRun = (Get-ScheduledTaskInfo @restore -ErrorAction Stop).LastRunTime
            Start-ScheduledTask @restore -ErrorAction Stop
            $ended = $false
            for ($i = 0; $i -lt 60 -and -not $ended; $i++) {
                Start-Sleep -Milliseconds 500
                $task = Get-ScheduledTask @restore -ErrorAction Ignore
                $ended = -not $task -or ($task.State -ne 'Running' -and (Get-ScheduledTaskInfo @restore -ErrorAction Ignore).LastRunTime -ne $lastRun)
            }
            if (-not $ended) { throw (Tr "la tâche {0} n'a pas fini après {1} secondes") -f $name, 30 }
            if (Test-WinRMRule $session $name) { throw (Tr "la règle de pare-feu {0} n'a pas pu être supprimée") -f $name }
        }
        finally { Remove-CimSession $session -ErrorAction Ignore }
    }

    function Get-LocalAddress {
        # This computer's addresses, which the firewall rule lets in: the computer sees the connection come from one
        # of them (a VPN's included).
        @(Get-NetIPAddress -AddressState Preferred -ErrorAction Stop | ForEach-Object { $_.IPAddress } |
            Where-Object { -not [System.Net.IPAddress]::IsLoopback([System.Net.IPAddress]::Parse($_)) } | Select-Object -Unique)
    }
}.ToString()
. ([scriptblock]::Create($script:RemoteAccessScript))

# For a background runspace, which has none of the script's functions: Tr, then these.
$script:RemoteAccessScript = $script:LanguageScript + [Environment]::NewLine + $script:RemoteAccessScript
