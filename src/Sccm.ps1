# SCCM (Configuration Manager), only ever read: the one file that knows how it's reached. Prochain nom… (NextName.ps1) and
# Paramètres › SCCM › Tester ask it through the functions below; none of them holds a query of its own.
#
# The site is reached through the console's PowerShell module, in a runspace of its own ($SccmLink) kept from one read to
# the next: the module takes seconds to load, its cmdlets only run from the site's drive, a location the search runspaces
# mustn't keep, and a site that doesn't answer can be left behind. One query at a time (Invoke-SccmRead).
#
# Four answers, never confused (Select-SccmDevice): Found, NotFound, Ambiguous, NotChecked with its reason. SCCM can show
# an account only some devices, and then answers with fewer rows, not with an error: what's found is certain, and what
# isn't is only « introuvable (avec vos accès) ».
#
# Only WQL (Invoke-CMWmiQuery): the console's other cmdlets stop at its limit of results, 1000 by default, with only a
# warning, which WQL doesn't (checked on a real site, 2026-11-26).
#
# Everything that asks SCCM runs on a search runspace (Start-BackgroundRead), given Get-SccmReadFunction and
# Get-SccmReadVariable. Dot-sourced by the main script, after Background.ps1.

# How long SCCM has to answer, in seconds: the first time, the module loading with it, then a query alone.
$script:SccmTimeoutSeconds = 60
$script:SccmQuerySeconds = 20
# And a question of several queries, waiting for another read included: what's read by then is kept.
$script:SccmTotalSeconds = 120
# How long reads nobody clicked for leave SCCM alone once it failed to answer, in seconds.
$script:SccmRestSeconds = 120
# How long the link's runspace is kept, in minutes: opening the site again is when the console says it's older than
# the site, which may be upgraded while Repère is open.
$script:SccmRenewMinutes = 60
# How long something let go of may take to stop or close before it's left to the process's end, in minutes.
$script:SccmStopMinutes = 10
# How many computers a query asks for at most.
$script:SccmBatchSize = 50

# The runspace the reads share, the search runspaces' too (Get-SccmReadVariable): Gate lets one read at a time in; Ready
# once the module and the site's drive are there; until RestUntil, reads nobody clicked for get RestReason at once.
# Refusals: the queries refused since the last that wasn't. OpenedAt: when the runspace was made; Renew: the next read
# makes a new one (Paramètres › SCCM › Tester).
$script:SccmLink = [hashtable]::Synchronized(@{
    Gate = [System.Threading.SemaphoreSlim]::new(1, 1); Runspace = $null; Ready = $false; Site = ''; Server = ''; Module = ''
    RestUntil = [datetime]::MinValue; RestReason = ''; Refusals = 0; OpenedAt = [datetime]::MinValue; Renew = $false
})
# What's let go of: each a runspace to close, with the module it loaded, and for a read that ran out of time or was
# stopped (Invoke-SccmRead) its shell and the handle of its stop. Both can take as long as SCCM does, so the read doesn't
# wait for them, and the timer disposes of them once they're done (Clear-SccmStopping). The search runspaces add to this
# same queue, up to a moment after their read is given up on: the timer goes on that many ticks with nothing to do.
$script:SccmStopping = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:SccmStopTicks = 0
$script:SccmStopTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:SccmStopTimer.Interval = [timespan]::FromSeconds(1)
$script:SccmStopTimer.Add_Tick({ Clear-SccmStopping })

# A device's record, and what its state adds (Get-SccmSummary).
$script:SccmDeviceColumns = 'ResourceID', 'Name', 'SID', 'FullDomainName', 'ResourceDomainORWorkgroup', 'Active', 'Client', 'ClientVersion', 'Obsolete', 'Decommissioned'
$script:SccmSummaryColumns = 'ResourceID', 'Name', 'Domain', 'SerialNumber', 'SiteCode', 'IsClient', 'IsActive', 'ClientVersion', 'ClientActiveStatus', 'DeviceOSBuild',
'LastActiveTime', 'LastHardwareScan', 'LastPolicyRequest', 'LastLogonUser', 'PrimaryUser'
# The inventory, by section: each its class and the columns Repère reads.
$script:SccmSections = [ordered]@{
    Scan      = @{ Class = 'SMS_G_System_WORKSTATION_STATUS'; Columns = @('LastHardwareScan') }
    System    = @{ Class = 'SMS_G_System_COMPUTER_SYSTEM'; Columns = 'Name', 'Domain', 'DomainRole', 'Manufacturer', 'Model', 'UserName', 'SystemType' }
    Bios      = @{ Class = 'SMS_G_System_PC_BIOS'; Columns = 'SerialNumber', 'SMBIOSBIOSVersion', 'ReleaseDate', 'Manufacturer' }
    Windows   = @{ Class = 'SMS_G_System_OPERATING_SYSTEM'; Columns = 'Caption', 'Version', 'BuildNumber', 'OSArchitecture', 'InstallDate', 'LastBootUpTime', 'TotalVisibleMemorySize' }
    Network   = @{ Class = 'SMS_G_System_NETWORK_ADAPTER_CONFIGURATION'; Columns = 'Description', 'IPAddress', 'MACAddress', 'DefaultIPGateway', 'DNSServerSearchOrder', 'DNSDomain', 'DHCPEnabled', 'Index', 'IPEnabled' }
    Processor = @{ Class = 'SMS_G_System_PROCESSOR'; Columns = 'Name', 'Manufacturer', 'MaxClockSpeed', 'NumberOfCores', 'NumberOfLogicalProcessors', 'Architecture', 'AddressWidth' }
    Memory    = @{ Class = 'SMS_G_System_X86_PC_MEMORY'; Columns = @('TotalPhysicalMemory') }
    Module    = @{ Class = 'SMS_G_System_PHYSICAL_MEMORY'; Columns = 'BankLabel', 'DeviceLocator', 'Capacity', 'Speed', 'MemoryType', 'FormFactor', 'Manufacturer', 'PartNumber' }
    Disk      = @{ Class = 'SMS_G_System_DISK'; Columns = 'Index', 'Model', 'Caption', 'Size', 'InterfaceType' }
    Volume    = @{ Class = 'SMS_G_System_LOGICAL_DISK'; Columns = 'DeviceID', 'DriveType', 'Size', 'FreeSpace', 'FileSystem', 'VolumeName' }
    Program   = @{ Class = 'SMS_G_System_ADD_REMOVE_PROGRAMS'; Columns = 'DisplayName', 'Version', 'Publisher', 'InstallDate', 'ProdID' }
    Program64 = @{ Class = 'SMS_G_System_ADD_REMOVE_PROGRAMS_64'; Columns = 'DisplayName', 'Version', 'Publisher', 'InstallDate', 'ProdID' }
}

# What runs in the link's runspace. The first time, the console's own steps: its module (it adds it to PSModulePath since
# version 2111; before that, SMS_ADMIN_UI_PATH says where it is; $FakeModule stands in for it with the fake AD), then the
# site's drive. Then $Read, a script as a text, with $With as its parameters; and the server that answers, which may not
# be the one asked for: the module mounts the site the console last used by itself.
$script:SccmLinkScript = {
    param([string]$Site, [string]$Server, [string]$FakeModule, [string]$Read, [hashtable]$With)
    $ErrorActionPreference = 'Stop'
    if (-not $global:RepereSccmServer) {
        if ($FakeModule) { Import-Module $FakeModule }
        elseif (Get-Module -ListAvailable ConfigurationManager) { Import-Module ConfigurationManager }
        elseif ($env:SMS_ADMIN_UI_PATH) { Import-Module (Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1') }
        else { throw 'ConfigurationManager module not found' }
        if (-not (Get-PSDrive -Name $Site -PSProvider CMSite -ErrorAction SilentlyContinue)) {
            $null = New-PSDrive -Name $Site -PSProvider CMSite -Root $Server -Scope Global
        }
        Set-Location "$($Site):\"
        $drive = Get-PSDrive -Name $Site -PSProvider CMSite -ErrorAction SilentlyContinue | Select-Object -First 1
        $root = if ($drive) { "$($drive.Root)".Trim('\') }
        $global:RepereSccmServer = if ($root) { $root } else { $Server }
    }
    function Read-SccmRow([string]$Class, [string[]]$Column, [string]$Where) {
        # A query's rows as plain objects with these columns, $null for one the site doesn't have or can't give. A site
        # that refuses the columns by their names is asked for all it has: an inventory class has those it collects.
        $rows = $null
        try { $rows = @(Invoke-CMWmiQuery -Query "SELECT $($Column -join ', ') FROM $Class WHERE $Where" -WarningAction SilentlyContinue) }
        catch {
            if ($_.Exception.GetType().Name -ne 'WqlQueryException') { throw }
            $rows = @(Invoke-CMWmiQuery -Query "SELECT * FROM $Class WHERE $Where" -WarningAction SilentlyContinue)
        }
        foreach ($row in $rows) {
            if ($null -eq $row) { continue }
            $values = [ordered]@{}
            foreach ($name in $Column) {
                $values[$name] = $null
                try { $values[$name] = $row.$name } catch { Write-Verbose "$name : $_" }
            }
            [pscustomobject]$values
        }
    }
    @{ Server = $global:RepereSccmServer; Output = @(& ([scriptblock]::Create($Read)) @With) }
}

function Get-SccmReadFunction {
    # The functions a read needs on a search runspace to ask SCCM, as Start-BackgroundRead's -Functions.
    'Invoke-SccmRead', 'New-SccmRunspace', 'Close-SccmRunspace', 'Get-SccmFailureReason', 'Test-SccmRefusal', 'Get-SccmDeadline', 'Get-SccmDomain', 'Test-SccmText', 'Get-ErrorKind', 'ConvertTo-SccmText', 'Get-SccmName', 'Find-SccmDevice', 'Select-SccmDevice',
    'Read-SccmBatch', 'Get-SccmInventory', 'Get-SccmSummary', 'Get-SccmTest', 'Test-SccmServer'
}

function Get-SccmReadVariable {
    # And its variables, as Start-BackgroundRead's -Variables.
    @{
        SccmTimeoutSeconds = $script:SccmTimeoutSeconds; SccmQuerySeconds = $script:SccmQuerySeconds; SccmTotalSeconds = $script:SccmTotalSeconds; SccmRestSeconds = $script:SccmRestSeconds; SccmBatchSize = $script:SccmBatchSize
        SccmRenewMinutes = $script:SccmRenewMinutes; ReadTimeout = $script:ReadTimeout
        SccmLink = $script:SccmLink; SccmStopping = $script:SccmStopping; SccmLinkScript = [string]$script:SccmLinkScript
        SccmDeviceColumns = $script:SccmDeviceColumns; SccmSummaryColumns = $script:SccmSummaryColumns; SccmSections = $script:SccmSections
        FakeSccmModule = $(if ($script:fakeADModule) { Join-Path (Split-Path $script:fakeADModule) 'FakeSccm.psm1' })
    }
}

function Get-SccmReadTimeout {
    # The time limit of a read that may ask SCCM, for Start-BackgroundRead: the reads' own, then SCCM's and a margin, so
    # that SCCM's own limit, which says what it's about, comes first.
    $script:ReadTimeout + $script:SccmTotalSeconds + 10
}

function Get-SccmDeadline {
    # When a question asked now has to end.
    [datetime]::UtcNow.AddSeconds($script:SccmTotalSeconds)
}

function Invoke-SccmRead {
    # Runs $Read (a script, as a text) in the link's runspace: Checked is $true with its Output and the Server that
    # answered, or $false with the Reason why SCCM couldn't be asked, and Lost when what follows would fail the same.
    # $Seconds: the most it may take, by default SccmQuerySeconds, or SccmTimeoutSeconds when the module has to load; never
    # past $Until, the end of the question it's a part of. -Automatic: a read nobody clicked for, which leaves alone for a
    # while a site that didn't answer. -MayRefuse: a query the site may well refuse (a class it doesn't collect), which
    # isn't counted among the refusals that make the link look dead. -Vital: a query that has to work, whose refusal
    # means the link is dead.
    param($Sccm, [string]$Read, [hashtable]$With = @{}, [int]$Seconds, [datetime]$Until = (Get-SccmDeadline), [switch]$Automatic, [switch]$MayRefuse, [switch]$Vital)
    $link = $script:SccmLink
    $result = @{ Checked = $false; Reason = ''; Output = @(); Server = ''; Lost = $false }
    $held, $shell, $handle, $runspace, $keep, $timedOut, $cut = $false, $null, $null, $null, $false, $false, $false
    # The turn given back in a finally of its own: a stop that comes while the other one lets go of the runspace would
    # skip the rest of it.
    try {
        try {
            # In short waits, so that a read that's stopped doesn't wait for its turn.
            $turn = [datetime]::UtcNow.AddSeconds($script:SccmTimeoutSeconds)
            if ($Until -lt $turn) { $turn = $Until }
            while (-not $held) {
                $held = $link.Gate.Wait(100)
                if (-not $held -and [datetime]::UtcNow -ge $turn) {
                    $result.Reason = Tr 'une autre lecture de SCCM n''est pas terminée'
                    $result.Lost = $true
                    return $result
                }
            }
            # Another site, or none yet.
            if ($link.Site -ne $Sccm.Site -or $link.Server -ne $Sccm.Server -or $link.Module -ne "$script:FakeSccmModule") {
                Close-SccmRunspace $link
                $link.Site, $link.Server, $link.Module = $Sccm.Site, $Sccm.Server, "$script:FakeSccmModule"
                $link.RestUntil = [datetime]::MinValue
            }
            # Once it's its turn: the read before it may be the one that failed.
            if ($Automatic -and [datetime]::UtcNow -lt $link.RestUntil) {
                $result.Reason = $link.RestReason
                $result.Lost = $true
                return $result
            }
            if ($link.Runspace -and ("$($link.Runspace.RunspaceStateInfo.State)" -ne 'Opened' -or "$($link.Runspace.RunspaceAvailability)" -ne 'Available' -or $link.Renew -or
                    [datetime]::UtcNow -ge $link.OpenedAt.AddMinutes($script:SccmRenewMinutes))) { Close-SccmRunspace $link }
            $link.Renew = $false
            if (-not $Seconds) { $Seconds = if ($link.Ready) { $script:SccmQuerySeconds } else { $script:SccmTimeoutSeconds } }
            $left = [int][math]::Ceiling(($Until - [datetime]::UtcNow).TotalSeconds)
            if ($left -le 0) {
                $result.Reason = Tr 'la lecture n''avait plus le temps de le demander'
                $result.Lost = $true
                return $result
            }
            # Cut short by the question's end, below what a query is given anyway: running out of it then says nothing of
            # SCCM. With that much time or more, SCCM had its chance.
            if ($left -lt $Seconds) { $Seconds = $left; $cut = $left -lt $script:SccmQuerySeconds }
            # Whatever fails from here on is said as SCCM not checked, never thrown at the read that asked.
            $fail = {
                param($failure)
                $result.Reason = Get-SccmFailureReason $failure $Sccm
                $result.Lost = $true
                $result
            }
            if (-not $link.Runspace) {
                $link.Ready = $false
                $link.Refusals = 0
                $link.OpenedAt = [datetime]::UtcNow
                $link.Runspace = New-SccmRunspace
                try { $link.Runspace.Open() }
                catch {
                    Close-SccmRunspace $link
                    return & $fail $_
                }
            }
            $runspace = $link.Runspace
            $shell = [powershell]::Create()
            $shell.Runspace = $runspace
            $null = $shell.AddScript([string]$script:SccmLinkScript).AddArgument($Sccm.Site).AddArgument($Sccm.Server).AddArgument($script:FakeSccmModule).AddArgument($Read).AddArgument($With)
            $limit = [datetime]::UtcNow.AddSeconds($Seconds)
            try { $handle = $shell.BeginInvoke() }
            catch { return & $fail $_ }
            while (-not $handle.IsCompleted -and [datetime]::UtcNow -lt $limit) { $null = $handle.AsyncWaitHandle.WaitOne(100) }
            if (-not $handle.IsCompleted) {
                $timedOut = $true
                $result.Reason = (Tr 'SCCM n''a pas répondu en {0} secondes') -f $Seconds
                $result.Lost = $true
            }
            else {
                try {
                    $answer = @($shell.EndInvoke($handle))[-1]
                    if ($answer -is [psobject]) { $answer = $answer.PSObject.BaseObject }
                    $result.Checked = $true
                    $result.Output = @($answer['Output'])
                    $result.Server = "$($answer['Server'])"
                    $link.Ready = $keep = $true
                    $link.Refusals = 0
                    $link.RestUntil = [datetime]::MinValue
                }
                catch {
                    $result.Reason = Get-SccmFailureReason $_ $Sccm
                    # Only a query that's refused leaves the link as it was, even the first one, once the site is open
                    # ($SccmLinkScript). After any other error (a server that stopped answering, a site that couldn't be
                    # opened, a link that died as the computer slept), or too many refusals in a row, which may be such
                    # an error in another's clothes, the next read opens the site again.
                    $failure = $_
                    # A runspace that broke can't say anything any more.
                    $link.Ready = try { [bool]$runspace.SessionStateProxy.GetVariable('RepereSccmServer') } catch { $false }
                    $refused = $link.Ready -and -not $Vital -and (Test-SccmRefusal $failure)
                    if (-not $MayRefuse) { $link.Refusals++ }
                    $keep = $refused -and $link.Refusals -lt 3
                    $result.Lost = -not $refused
                }
            }
            if ($result.Lost -and -not ($timedOut -and $cut)) {
                $link.RestReason = $result.Reason
                $link.RestUntil = [datetime]::UtcNow.AddSeconds($script:SccmRestSeconds)
            }
            $result
        }
        finally {
            # Out of time, or the read that asked was stopped: the shell is stopped without waiting, and disposed by the
            # window's timer once it has, never before (nothing then runs on it). A read that was only stopped, not out
            # of time, gets a second to let go: the runspace and its module then serve the next one.
            if ($handle -and -not $handle.IsCompleted) {
                $stop = $shell.BeginStop($null, $null)
                if ($timedOut -or -not $link.Ready -or -not $stop.AsyncWaitHandle.WaitOne(1000)) { Close-SccmRunspace $link $shell $stop }
                else {
                    try { $shell.EndStop($stop) } catch { Write-Verbose "Lecture SCCM arrêtée : $_" }
                    $shell.Dispose()
                }
            }
            elseif ($shell) {
                if (-not $keep) { Close-SccmRunspace $link }
                $shell.Dispose()
            }
        }
    }
    finally { if ($held) { $null = $link.Gate.Release() } }
}

function New-SccmRunspace {
    # The link's runspace, not opened yet: one thread for all its reads, as in the console's own window.
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace
}

function Close-SccmRunspace($Link, $Shell, $Stop) {
    # Lets go of the link's runspace: the timer closes it (Clear-SccmStopping), as the module may take its time to leave,
    # and once what it runs, if anything ($Shell), has stopped.
    $runspace = $Link.Runspace
    $Link.Runspace = $null
    $Link.Ready = $false
    if ($runspace -and $null -ne $script:SccmStopping) { $script:SccmStopping.Enqueue(@{ Shell = $Shell; Stop = $Stop; Runspace = $runspace; Since = [datetime]::UtcNow }) }
}

function Test-SccmRefusal($Failure) {
    # Whether an error is about the query asked (the site refuses it, or the account's access does) rather than about
    # reaching the site: the console's own error for a query, or access denied, without an RPC code inside.
    $kinds = @(Get-ErrorKind $Failure)
    if ($kinds -contains 'RpcUnavailable') { return $false }
    $refused = $kinds -contains 'AccessDenied'
    $pending = [System.Collections.Generic.Queue[object]]::new()
    $pending.Enqueue($Failure.Exception)
    for ($i = 0; $pending.Count -and $i -lt 20; $i++) {
        $item = $pending.Dequeue()
        # The RPC call failed; the object it was made to is gone.
        if (('{0:X8}' -f $item.HResult) -in '800706BE', '80010108') { return $false }
        if ($item.GetType().Name -eq 'WqlQueryException') { $refused = $true }
        if ($item.InnerException) { $pending.Enqueue($item.InnerException) }
        if ($item -is [System.Management.Automation.RuntimeException] -and $item.ErrorRecord -and $item.ErrorRecord.Exception) { $pending.Enqueue($item.ErrorRecord.Exception) }
    }
    $refused
}

function Get-SccmFailureReason($Failure, $Sccm) {
    # Why SCCM couldn't be asked, in words, from the error of a read (EndInvoke's). The module's own error: an error it
    # writes stops the script (ErrorActionPreference), and comes wrapped in PowerShell's « La commande en cours
    # d'exécution s'est arrêtée, car… : », which says nothing more (#329).
    $inner = if ($Failure.Exception.InnerException) { $Failure.Exception.InnerException } else { $Failure.Exception }
    $message = if ($inner -is [System.Management.Automation.ActionPreferenceStopException] -and $inner.ErrorRecord) { $inner.ErrorRecord.Exception.Message } else { $inner.Message }
    $message = "$message".Trim() -replace '^(?:The running command stopped because|La commande en cours d.ex.cution s.est arr.t.e)[^:]*:\s*'
    # A site not found, or a server that doesn't answer: by the error's codes (Get-ErrorKind), whatever Windows'
    # language, then by its text in English or French. The module not found is Repère's own text ($SccmLinkScript), the
    # same in every language. The console's version has no code of its own Repère knows: its text only.
    $kinds = @(Get-ErrorKind $Failure)
    if ($message -match 'ConfigurationManager module not found') { return Tr 'la console Configuration Manager n''est pas installée sur cet ordinateur' }
    # The site was upgraded, not this console: its cmdlets could harm the site, so SCCM stays not checked.
    if ($message -match '(?:A new version of the console is available|nouvelle version de la console est disponible)\s*\((?<version>[\d.]+)\)') {
        return (Tr 'la console Configuration Manager doit être mise à jour (version {0})') -f $Matches.version
    }
    if ($kinds -contains 'InvalidNamespace') { return (Tr 'le site {0} est introuvable sur {1}') -f $Sccm.Site, $Sccm.Server }
    if ($kinds -contains 'RpcUnavailable') { return (Tr '{0} ne répond pas') -f $Sccm.Server }
    if (-not $kinds.Count -and $message -match 'namespace|espace de noms') { return (Tr 'le site {0} est introuvable sur {1}') -f $Sccm.Site, $Sccm.Server }
    if (-not $kinds.Count -and $message -match 'RPC') { return (Tr '{0} ne répond pas') -f $Sccm.Server }
    # Any other: its first sentence, without its period (the line that shows it adds its own).
    $first = @((ConvertTo-FrenchError $message) -split '\r?\n')[0].Trim()
    if ($first -match '^(.+?)[.!?](?:\s|$)') { $first = $Matches[1] }
    $first.TrimEnd('.')
}

function Clear-SccmStopping {
    # The timer's tick: what has stopped is closed, what has closed is disposed of, and the rest waits for the next tick;
    # the timer stops once nothing is left for a while. What hasn't stopped or closed after SccmStopMinutes (a call that
    # never returns) is left to the process's end, which is all that can stop it. On the window's thread, so nothing it
    # does throws or waits.
    $queue = $script:SccmStopping
    for ($left = $queue.Count; $left -gt 0; $left--) {
        $entry = $null
        if (-not $queue.TryDequeue([ref]$entry)) { break }
        $stale = $entry['Since'] -and [datetime]::UtcNow -ge ([datetime]$entry['Since']).AddMinutes($script:SccmStopMinutes)
        if ($entry.Stop -and -not $entry.Stop.IsCompleted) {
            if ($stale) { Write-Verbose 'Lecture SCCM toujours en cours : laissée à la fin de Repère' } else { $queue.Enqueue($entry) }
            continue
        }
        if ($entry.Shell) {
            try { $entry.Shell.EndStop($entry.Stop) } catch { Write-Verbose "Lecture SCCM arrêtée : $_" }
            try { $entry.Shell.Dispose() } catch { Write-Verbose "Lecture SCCM non libérée : $_" }
            $entry.Shell = $entry.Stop = $null
        }
        try {
            $state = "$($entry.Runspace.RunspaceStateInfo.State)"
            if ($state -eq 'Opened') { $entry.Runspace.CloseAsync() }
            if ($state -notin 'Opened', 'Closing') { $entry.Runspace.Dispose() }
            elseif (-not $stale) { $queue.Enqueue($entry) }
        }
        catch { Write-Verbose "Runspace SCCM non libéré : $_" }
    }
    if ($queue.Count) { return }
    $script:SccmStopTicks--
    if ($script:SccmStopTicks -le 0) { $script:SccmStopTimer.Stop() }
}

function Start-SccmStopSweep {
    # A read that may have asked SCCM has ended (its OnDone), or been given up on: what it lets go of is closed, now or
    # in the moment it takes to.
    $script:SccmStopTicks = 10
    $script:SccmStopTimer.Start()
}

function ConvertTo-SccmText([string]$Text) {
    # A text inside a query's quotes, for = and IN (not LIKE, whose wildcards are others). What's asked for has passed
    # Test-SccmText too: whether the provider reads these escapes as WQL says isn't checked on a real site.
    $Text.Replace('\', '\\').Replace("'", "\'")
}

function Test-SccmText([string]$Text, [switch]$Serial) {
    # Whether a name, or a serial number, is one Repère asks SCCM for: letters, digits, - _ and . (a serial number also
    # spaces and / : # +), never a quote or a backslash, which only escaping would keep from changing the query.
    if ($Serial) { $Text -match '^[\p{L}\p{N} _./:#+-]{1,64}$' } else { $Text -match '^[\p{L}\p{N}_.-]{1,64}$' }
}

function Get-SccmName($Sccm, [string[]]$Name, [datetime]$Until = (Get-SccmDeadline)) {
    # Which of these names SCCM has a record of, whatever its state (Prochain nom…): Checked is $true with those Names, as
    # given, or $false with the Reason why they couldn't be asked. Never an empty list for a check that failed. By their
    # exact names, a few at a time: the series' own is never read whole.
    $find = Find-SccmDevice $Sccm -Name $Name -Until $Until
    $check = @{ Checked = $find.Checked; Reason = $find.Reason; Names = @() }
    if ($find.Checked -and @($find.Skipped).Count) { $check.Checked = $false; $check.Reason = Tr 'Repère ne cherche pas dans SCCM un nom avec ces caractères' }
    if (-not $check.Checked) { return $check }
    $have = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($device in $find.Devices) { $null = $have.Add([string]$device.Name) }
    $check.Names = @($Name | Where-Object { $have.Contains($_) })
    $check
}

function Read-SccmBatch {
    # The rows of $Class whose $Field is one of $Value (texts already in quotes, or numbers), SccmBatchSize values at a
    # time: Checked with its Rows and the Server that answered, or the Reason why not. A part that fails fails the whole,
    # as what wasn't read would look missing.
    param($Sccm, [object[]]$Value, [string]$Field, [string]$Class, [string[]]$Column, [datetime]$Until = (Get-SccmDeadline), [switch]$Automatic)
    $result = @{ Checked = $true; Reason = ''; Rows = @(); Server = '' }
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Value.Count; $i += $script:SccmBatchSize) {
        $part = @($Value | Select-Object -Skip $i -First $script:SccmBatchSize)
        $read = Invoke-SccmRead $Sccm -Until $Until -Automatic:$Automatic -With @{ Class = $Class; Where = "$Field IN ($($part -join ','))"; Column = $Column } -Read @'
param([string]$Class, [string]$Where, [string[]]$Column)
Read-SccmRow $Class $Column $Where
'@
        if (-not $read.Checked) { $result.Checked = $false; $result.Reason = $read.Reason; return $result }
        $result.Server = $read.Server
        foreach ($row in $read.Output) { $rows.Add($row) }
    }
    $result.Rows = $rows.ToArray()
    $result
}

function Find-SccmDevice {
    # The records SCCM has of computers, by name or by serial number: Checked with its Devices (Read-SccmRow's, with
    # SccmDeviceColumns) and the Server that answered, or the Reason why not. A name can have several, or none the
    # account can see: Select-SccmDevice says which. Skipped: the names not asked for (Test-SccmText).
    param($Sccm, [string[]]$Name = @(), [string]$Serial, [datetime]$Until = (Get-SccmDeadline), [switch]$Automatic)
    $result = @{ Checked = $true; Reason = ''; Devices = @(); Server = ''; Skipped = @($Name | Where-Object { $_ -and -not (Test-SccmText $_) }) }
    $wanted = @($Name | Where-Object { $_ -and (Test-SccmText $_) } | Select-Object -Unique | ForEach-Object { "'$(ConvertTo-SccmText $_)'" })
    $field = 'Name'
    if ($Serial -and -not (Test-SccmText $Serial -Serial)) {
        $result.Checked = $false
        $result.Reason = Tr 'Repère ne cherche pas dans SCCM un numéro de série avec ces caractères'
        return $result
    }
    if ($Serial) {
        $read = Invoke-SccmRead $Sccm -Until $Until -Automatic:$Automatic -With @{ Where = "SerialNumber = '$(ConvertTo-SccmText $Serial)'" } -Read @'
param([string]$Where)
Read-SccmRow 'SMS_G_System_PC_BIOS' @('ResourceID') $Where
'@
        if (-not $read.Checked) { $result.Checked = $false; $result.Reason = $read.Reason; return $result }
        $result.Server = $read.Server
        if (@($read.Output | Where-Object { -not $_.ResourceID }).Count) { $result.Checked = $false; $result.Reason = Tr 'sa réponse n''est pas lisible'; return $result }
        $field = 'ResourceID'
        $wanted = @($read.Output | ForEach-Object { [int64]$_.ResourceID } | Select-Object -Unique)
    }
    if (-not $wanted.Count) { return $result }
    $read = Read-SccmBatch $Sccm $wanted $field 'SMS_R_System' $script:SccmDeviceColumns -Until $Until -Automatic:$Automatic
    if (-not $read.Checked) { $result.Checked = $false; $result.Reason = $read.Reason; return $result }
    $result.Server = $read.Server
    # A record without its name would look like no record.
    if (@($read.Rows | Where-Object { -not $_.ResourceID -or -not $_.Name }).Count) { $result.Checked = $false; $result.Reason = Tr 'sa réponse n''est pas lisible'; return $result }
    $result.Devices = @($read.Rows)
    $result
}

function Select-SccmDevice($Find, [string]$Name, [string]$Sid, [string]$Domain) {
    # Which of Find-SccmDevice's records is this computer: its Answer (Found, NotFound, Ambiguous, NotChecked), the
    # Device (the latest of the candidates when there are several), all the Candidates, and the Reason of a NotChecked.
    # $Domain: the DNS name. Records SCCM itself calls obsolete or decommissioned only count when there's no other. Then a
    # record with the computer's SID is it; otherwise, the one with its name, and its domain when both are known. Never a
    # guess: a record with another SID (a computer of that name since rejoined, or another one), or whose short domain
    # name may not be this domain's, is only a candidate. Only a DNS domain that's another rules a record out.
    $answer = @{ Answer = 'NotChecked'; Device = $null; Candidates = @(); Reason = $Find.Reason }
    if (-not $Find.Checked) { return $answer }
    if ($Name -in @($Find['Skipped'])) { $answer.Reason = Tr 'Repère ne cherche pas dans SCCM un nom avec ces caractères'; return $answer }
    $ranked = @(foreach ($device in $Find.Devices) {
            if ("$($device.Name)" -ne $Name) { continue }
            $full, $short, $id = "$($device.FullDomainName)", "$($device.ResourceDomainORWorkgroup)", "$($device.SID)"
            $rank = if ($Sid -and $id -eq $Sid) { 'Sure' }
            elseif ($Domain -and $full -and $full -ne $Domain -and $full.Contains('.') -and $Domain.Contains('.')) { continue }
            elseif ($Sid -and $id) { 'Doubtful' }
            # A short name is NetBIOS', most often the first part of the DNS name, but not always.
            elseif (-not $Domain -or (-not $full -and -not $short) -or $full -eq $Domain -or (-not $full -and $short -in $Domain, ($Domain -split '\.')[0])) { 'Likely' }
            else { 'Doubtful' }
            [pscustomobject]@{ Device = $device; Rank = $rank; Current = "$($device.Obsolete)" -notin '1', 'True' -and "$($device.Decommissioned)" -notin '1', 'True' }
        })
    $current = @($ranked | Where-Object Current)
    $kept = if ($current.Count) { $current } else { $ranked }
    $best = 'Sure', 'Likely', 'Doubtful' | Where-Object { $_ -in @($kept | ForEach-Object Rank) } | Select-Object -First 1
    # When no current record is this computer's for sure, an obsolete one that is stays a candidate.
    if ($best -eq 'Doubtful') { $kept = @($kept) + @($ranked | Where-Object { -not $_.Current -and $_.Rank -eq 'Sure' }) }
    else { $kept = @($kept | Where-Object Rank -EQ $best) }
    $answer.Candidates = @($kept | ForEach-Object Device | Sort-Object { [int64]$_.ResourceID } -Descending)
    $answer.Device = $answer.Candidates | Select-Object -First 1
    $answer.Answer = if (-not $answer.Candidates.Count) { 'NotFound' } elseif ($best -eq 'Doubtful' -or $answer.Candidates.Count -gt 1) { 'Ambiguous' } else { 'Found' }
    $answer
}

function Get-SccmInventory {
    # A device's inventory, by section (SccmSections): each Read with its Rows, or not with the Reason. A class the site
    # doesn't collect, or doesn't show this account, fails alone; once SCCM stops answering, or the time is up, the rest
    # isn't tried, and what was read is kept.
    param($Sccm, [int64]$ResourceId, [string[]]$Section = @($script:SccmSections.Keys), [datetime]$Until = (Get-SccmDeadline), [switch]$Automatic)
    $result = [ordered]@{}
    $lost = ''
    $failed = 0
    foreach ($name in $Section) {
        if ($lost) { $result[$name] = @{ Read = $false; Reason = $lost; Rows = @() }; continue }
        # Three sections refused in a row may be a link that died with an error that looks like a refusal: its record,
        # which it read before, tells which.
        if ($failed -ge 3) {
            $failed = 0
            $alive = Invoke-SccmRead $Sccm -Until $Until -Automatic:$Automatic -Vital -With @{ Id = $ResourceId } -Read @'
param([int64]$Id)
Read-SccmRow 'SMS_R_System' @('ResourceID') "ResourceID = $Id"
'@
            if (-not $alive.Checked) { $lost = $alive.Reason; $result[$name] = @{ Read = $false; Reason = $lost; Rows = @() }; continue }
        }
        $read = Invoke-SccmRead $Sccm -Until $Until -Automatic:$Automatic -MayRefuse -Read @'
param([string]$Class, [string[]]$Column, [int64]$Id)
Read-SccmRow $Class $Column "ResourceID = $Id"
'@ -With @{ Class = $script:SccmSections[$name].Class; Column = $script:SccmSections[$name].Columns; Id = $ResourceId }
        $result[$name] = @{ Read = $read.Checked; Reason = $read.Reason; Rows = @($read.Output) }
        if ($read.Lost) { $lost = $read.Reason }
        $failed = if ($read.Checked) { 0 } else { $failed + 1 }
    }
    $result
}

function Get-SccmSummary {
    # The state of devices already found: Checked with its Devices (SccmSummaryColumns), or the Reason why not. By
    # ResourceID only: whether this class keeps to what the account may see isn't sure, but Find-SccmDevice's does.
    param($Sccm, [int64[]]$ResourceId, [datetime]$Until = (Get-SccmDeadline), [switch]$Automatic)
    $result = @{ Checked = $true; Reason = ''; Devices = @() }
    if (-not $ResourceId.Count) { return $result }
    $read = Read-SccmBatch $Sccm @($ResourceId | Select-Object -Unique) 'ResourceID' 'SMS_CombinedDeviceResources' $script:SccmSummaryColumns -Until $Until -Automatic:$Automatic
    if (-not $read.Checked) { $result.Checked = $false; $result.Reason = $read.Reason; return $result }
    $result.Devices = @($read.Rows)
    $result
}

function Test-SccmServer([string]$Server, [string]$Other) {
    # Whether two names are one server's, with or without its domain.
    $Server -eq $Other -or (($Server.Contains('.') -xor $Other.Contains('.')) -and ($Server -split '\.')[0] -eq ($Other -split '\.')[0])
}

function Get-SccmDomain {
    # The DNS name of this computer's AD domain, '' out of one: not its DNS suffix, which may be another name.
    try {
        $system = Get-CimInstance Win32_ComputerSystem -Property Domain, PartOfDomain -ErrorAction Stop
        if ($system.PartOfDomain) { return [string]$system.Domain }
        return ''
    }
    catch { "$env:USERDNSDOMAIN" }
}

function Get-SccmTest($Sccm, [string]$ComputerName = $env:COMPUTERNAME, [string]$Domain = (Get-SccmDomain)) {
    # Paramètres › SCCM › Tester: whether the site answers (Checked, or the Reason), by which Server (OtherServer when
    # it's not the one asked for), and whether this computer's inventory can be read: Inventory is Readable, Empty,
    # Failed (InventoryReason), Ambiguous when SCCM has several records that may be it, Obsolete when it has only one
    # that SCCM itself calls obsolete or decommissioned, or NoDevice when the account
    # doesn't see it, which says nothing of the rest. The site is opened afresh, so that a console older than the site
    # is said now.
    $test = @{ Checked = $false; Reason = ''; Server = ''; OtherServer = $false; Inventory = ''; InventoryReason = '' }
    $until = Get-SccmDeadline
    $script:SccmLink.Renew = $true
    $find = Find-SccmDevice $Sccm -Name $ComputerName -Until $until
    $test.Reason = $find.Reason
    if (-not $find.Checked) { return $test }
    $test.Checked = $true
    $test.Server = $find.Server
    $test.OtherServer = -not (Test-SccmServer $find.Server $Sccm.Server)
    $answer = Select-SccmDevice $find $ComputerName -Domain $Domain
    if ($answer.Answer -eq 'NotFound') { $test.Inventory = 'NoDevice'; return $test }
    if ($answer.Answer -ne 'Found') { $test.Inventory = 'Ambiguous'; return $test }
    $device = $answer.Device
    if ("$($device.Obsolete)" -in '1', 'True' -or "$($device.Decommissioned)" -in '1', 'True') { $test.Inventory = 'Obsolete'; return $test }
    $system = (Get-SccmInventory $Sccm $device.ResourceID -Section 'System' -Until $until).System
    $test.Inventory = if (-not $system.Read) { 'Failed' } elseif ($system.Rows.Count) { 'Readable' } else { 'Empty' }
    $test.InventoryReason = $system.Reason
    $test
}

function Format-SccmTest($Test, $Sccm) {
    # Get-SccmTest's answer, as Paramètres says it.
    if (-not $Test.Checked) { return (Tr 'Vérification SCCM impossible : {0}.') -f $Test.Reason }
    $site = if ($Test.OtherServer) { (Tr 'Le site {0} répond, mais par {1} : la console s''y connecte d''elle-même.') -f $Sccm.Site, $Test.Server } else { (Tr 'Le site {0} répond.') -f $Sccm.Site }
    $inventory = switch ($Test.Inventory) {
        'Readable' { Tr 'L''inventaire de cet ordinateur est lisible.' }
        'Empty' { Tr 'Cet ordinateur y est, sans inventaire (avec vos accès).' }
        'Failed' { (Tr 'L''inventaire de cet ordinateur n''est pas lisible : {0}.') -f $Test.InventoryReason }
        'Ambiguous' { Tr 'Inventaire non vérifié : SCCM a plusieurs fiches qui peuvent être cet ordinateur.' }
        'Obsolete' { Tr 'Inventaire non vérifié : SCCM n''a de cet ordinateur qu''une fiche obsolète.' }
        default { Tr 'Inventaire non vérifié : cet ordinateur est introuvable dans SCCM (avec vos accès).' }
    }
    "$site $inventory"
}

function Read-SccmSetting {
    # The site saved in Paramètres, as the reads take it, or $null without one.
    $saved = Read-JsonSetting $script:SettingsPath SccmSite, SccmServer
    if (-not $saved -or -not $saved.SccmSite -or -not $saved.SccmServer) { return }
    if (Get-SccmSettingProblem $saved.SccmSite $saved.SccmServer) { return }
    @{ Site = ([string]$saved.SccmSite).ToUpperInvariant(); Server = [string]$saved.SccmServer }
}

function Get-SccmSettingProblem([string]$Site, [string]$Server) {
    # What's wrong with a site code and server, in words (the site's first); nothing when they're fine.
    $problem = Get-SccmFieldProblem $Site $Server
    if ($problem.Site) { $problem.Site } elseif ($problem.Server) { $problem.Server }
}

function Get-SccmFieldProblem([string]$Site, [string]$Server) {
    # What's wrong with each: Site and Server, $null for one that's fine. Paramètres says each under its box.
    @{
        Site   = if ($Site -notmatch '^[A-Za-z0-9]{3}$') { Tr 'Le code du site a 3 lettres ou chiffres, ex. P01.' }
        Server = if ($Server -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { Tr 'Le serveur est un nom, ex. sccm.exemple.local.' }
    }
}
