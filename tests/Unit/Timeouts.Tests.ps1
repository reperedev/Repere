# The time limits on what waits for a DC, without the window: a background read stopped once its DC hasn't answered in
# time (Start-BackgroundRead), a domain's search stopped while AD hasn't sent anything (Test-SearchTimedOut,
# Stop-SilentSearch, the search scripts' clock), and the users' changes run in the background (Start-ADWrite), which
# say « may have been made » rather than « failed » when their DC stops answering.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD
    # What the main script gives (not loaded here): the window's pointer, the toast and the reports, kept, not shown.
    $script:win = [pscustomobject]@{ Cursor = $null }
    $script:Shown = [System.Collections.Generic.List[string]]::new()
    function Show-ActionNotice { $script:Shown.Add("Notice: $($args -join ' ')") }
    function Hide-ActionNotice {}
    function Show-ActionReport { param([string[]]$Lines, [string]$Title, $Owner, [string]$Many, [string[]]$Outcome) $script:Shown.Add("Report: $Title | $($Lines -join ' | ')") }
    function Show-Dialog { param([string]$Title, [string]$Message, $Owner, [string]$Icon, [string]$Tone) $script:Shown.Add("Dialog: $Title | $Message") }
    # The password's dialog builds XAML from the window's styles: what it's given is kept instead.
    function Show-NewPassword { param($Row, [string]$Password, [bool]$MustChange, [string[]]$Problems, $Owner, [switch]$Unsure, [int]$Timeout) $script:Shown.Add("Password: $Password | Unsure=$([bool]$Unsure) | $($Problems -join ' ; ')") }

    function Start-TestPool {
        # A search runspace with the fake AD, as Repère opens them; the row builder is the language's (Tr).
        $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $state.ImportPSModule((Join-Path $script:RepereSource 'FakeAD\FakeAD.psm1'))
        $script:rowBuilderScript = $script:LanguageScript
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 4, $state, $Host)
        $script:searchPool.Open()
    }

    function Wait-Read {
        # The reads under way, until they end, then their OnDone, as the window's timer runs it.
        for ($i = 0; $i -lt 200 -and @($script:BackgroundReadList | Where-Object { -not $_.Handle.IsCompleted }).Count; $i++) { Start-Sleep -Milliseconds 50 }
        Complete-BackgroundRead
    }

    function Wait-ReadStarted {
        # Until every read has started on its runspace, so its time limit counts.
        for ($i = 0; $i -lt 200 -and @($script:BackgroundReadList | Where-Object { -not $_.Clock.Started }).Count; $i++) { Start-Sleep -Milliseconds 20 }
    }

    function Clear-Stopped {
        # The reads stopped at their limit, waited for and disposed of.
        foreach ($read in @($script:BackgroundStopping)) { $null = $read.Handle.AsyncWaitHandle.WaitOne(10000) }
        Complete-BackgroundRead
    }

    function New-UserRow([string]$Domain, [string]$Filter) {
        # A row of the Utilisateurs page for a user of the fake AD, locked and enabled as the page shows it.
        $user = Get-ADUser -Server $Domain -LDAPFilter $Filter | Select-Object -First 1
        [pscustomobject]@{
            Login = [string]$user.SamAccountName; Name = [string]$user.Name; Domain = $Domain; DistinguishedName = [string]$user.DistinguishedName
            IsLocked = $true; IsEnabled = $true; State = 'Verrouillé'; PasswordNeverExpires = $false
            Password = ''; PasswordTone = ''; PasswordTip = ''; PasswordSort = [int64]0; PasswordState = ''
        }
    }
}

Describe 'Start-BackgroundRead: a time limit for a DC that stops answering' {
    BeforeAll {
        $script:rowBuilderScript = ''
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 2)
        $script:searchPool.Open()
        function Wait-SlowRead { Start-Sleep -Seconds 30 }
        function Get-QuickRead { 'lu' }
    }

    AfterAll {
        Clear-Stopped
        $script:searchPool.Dispose()
        $script:searchPool = $null
    }

    It 'Stops a read past its limit, without waiting for it, and tells its OnDone why' {
        $done = @{ Count = 0 }
        Start-BackgroundRead -Command 'Wait-SlowRead' -Timeout 1 -OnDone {
            param($context, $read, $problem, $timedOut)
            $done.Count++; $done.Read = $read; $done.Problem = $problem; $done.TimedOut = $timedOut
        }.GetNewClosure()
        $read = $script:BackgroundReadList[$script:BackgroundReadList.Count - 1]
        Wait-ReadStarted
        Complete-BackgroundRead
        $done.Count | Should -Be 0
        Start-Sleep -Milliseconds 1100
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Complete-BackgroundRead
        $watch.ElapsedMilliseconds | Should -BeLessThan 1000
        $done.Count | Should -Be 1
        $done.TimedOut | Should -BeTrue
        $done.Read | Should -BeNullOrEmpty
        $done.Problem | Should -BeExactly 'pas de réponse du contrôleur de domaine après 1 secondes'
        $script:BackgroundReadList.Contains($read) | Should -BeFalse
        # Disposed of once it has ended (a sleep stops at once: by the same tick), the timer going on until then.
        ($script:BackgroundStopping.Contains($read) -or $read.Handle.IsCompleted) | Should -BeTrue
        $read.Handle.AsyncWaitHandle.WaitOne(10000) | Should -BeTrue
        Complete-BackgroundRead
        $script:BackgroundStopping.Count | Should -Be 0
        $done.Count | Should -Be 1
    }

    It 'Gives a read that ends in time its result, $TimedOut $false' {
        $done = @{}
        Start-BackgroundRead -Command 'Get-QuickRead' -OnDone { param($context, $read, $problem, $timedOut) $done.Read = $read; $done.TimedOut = $timedOut }.GetNewClosure()
        Wait-Read
        $done.Read | Should -BeExactly 'lu'
        $done.TimedOut | Should -BeFalse
    }

    It 'Never starts a read waiting for the runspaces that an OnDone stopped earlier in the same tick' {
        # Both wait for runspaces still to open; the first, stopped, stops the second from its OnDone, in the tick
        # that finds them open.
        $opened = $script:searchPool
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 2)
        try {
            $script:StopTest = @{ First = @{ Id = 1 }; Second = @{ Id = 2 }; Done = @{} }
            Start-BackgroundRead -Command 'Get-QuickRead' -Context $script:StopTest.First -OnDone {
                param($context, $read, $problem)
                Stop-BackgroundRead $script:StopTest.Second
            }
            Start-BackgroundRead -Command 'Get-QuickRead' -Context $script:StopTest.Second -OnDone {
                param($context, $read, $problem)
                $script:StopTest.Done.Read = $read; $script:StopTest.Done.Problem = $problem
            }
            $second = $script:BackgroundReadList[$script:BackgroundReadList.Count - 1]
            Stop-BackgroundRead $script:StopTest.First
            $script:searchPool.Open()
            Complete-BackgroundRead
            $second.Stopped | Should -BeTrue
            $second.Handle | Should -BeNullOrEmpty
            Complete-BackgroundRead
            $script:BackgroundReadList.Contains($second) | Should -BeFalse
            $script:StopTest.Done.Read | Should -BeNullOrEmpty
            $script:StopTest.Done.Problem | Should -BeExactly ([System.Management.Automation.PipelineStoppedException]::new().Message)
        }
        finally {
            $script:BackgroundReadTimer.Stop()
            $script:searchPool.Dispose()
            $script:searchPool = $opened
        }
    }

    It 'Ends a read started from a window its OnDone opened, while that window is open' {
        # ShowDialog's loop, as a dispatcher frame; the window's thread ticks the timer.
        $state = @{ Frame = [System.Windows.Threading.DispatcherFrame]::new(); Inner = [System.Windows.Threading.DispatcherFrame]::new(); Read = $null; InTime = $null }
        $later = {
            # Gives up on a frame after 5 seconds: « not in time ».
            param($frame)
            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [timespan]::FromSeconds(5)
            $timer.Tag = $frame
            $timer.Add_Tick({ param($timer) $timer.Stop(); $timer.Tag.Continue = $false })
            $timer.Start()
            $timer
        }
        $script:NestedRead = $state
        $script:NestedLimit = $later
        Start-BackgroundRead -Command 'Get-QuickRead' -OnDone {
            $limit = & $script:NestedLimit $script:NestedRead.Inner
            Start-BackgroundRead -Command 'Get-QuickRead' -OnDone {
                param($context, $read)
                $script:NestedRead.Read = $read
                $script:NestedRead.Inner.Continue = $false
            }
            [System.Windows.Threading.Dispatcher]::PushFrame($script:NestedRead.Inner)
            $limit.Stop()
            $script:NestedRead.InTime = $null -ne $script:NestedRead.Read
            $script:NestedRead.Frame.Continue = $false
        }
        $limit = & $later $state.Frame
        $limit.Interval = [timespan]::FromSeconds(10)
        [System.Windows.Threading.Dispatcher]::PushFrame($state.Frame)
        $limit.Stop()
        $script:BackgroundReadTimer.Stop()
        $state.InTime | Should -BeTrue
        $state.Read | Should -BeExactly 'lu'
    }

    It 'Counts from when the read starts on its runspace, and never with a limit of 0' {
        $handle = [pscustomobject]@{ IsCompleted = $false }
        $now = [datetime]::UtcNow
        Test-ReadTimedOut @{ Timeout = 120; Handle = $handle; Clock = @{ Started = $now.AddSeconds(-121) } } $now | Should -BeTrue
        Test-ReadTimedOut @{ Timeout = 120; Handle = $handle; Clock = @{ Started = $now.AddSeconds(-119) } } $now | Should -BeFalse
        # Waiting for a free runspace, or not started yet: not counted.
        Test-ReadTimedOut @{ Timeout = 120; Handle = $handle; Clock = @{ Started = $null } } $now | Should -BeFalse
        Test-ReadTimedOut @{ Timeout = 120; Handle = $null; Clock = @{ Started = $now.AddHours(-1) } } $now | Should -BeFalse
        Test-ReadTimedOut @{ Timeout = 0; Handle = $handle; Clock = @{ Started = $now.AddHours(-1) } } $now | Should -BeFalse
        Test-ReadTimedOut @{ Timeout = 120; Handle = [pscustomobject]@{ IsCompleted = $true }; Clock = @{ Started = $now.AddHours(-1) } } $now | Should -BeFalse
    }
}

Describe "A domain's search: stopped while AD hasn't answered in time" {
    BeforeAll {
        $script:search = @{ Current = $null; Stopping = [System.Collections.Generic.List[object]]::new(); Dialogs = 0 }
        function New-TestJob($Started, [bool]$Answered, [bool]$Completed = $false) {
            @{ Domain = 'demo.local'; Handle = [pscustomobject]@{ IsCompleted = $Completed }; Cancelled = $false; TimedOut = $false
               Clock = @{ Started = $Started; Answered = $Answered } }
        }
    }

    It 'Times out a search that started <Seconds> s ago, AD answered: <Answered> -> <Expected>' -ForEach @(
        @{ Seconds = 21; Answered = $false; Expected = $true }
        @{ Seconds = 19; Answered = $false; Expected = $false }
        # Tout afficher on a big domain: AD answers at once, then takes its time.
        @{ Seconds = 600; Answered = $true; Expected = $false }
    ) {
        $now = [datetime]::UtcNow
        Test-SearchTimedOut (New-TestJob $now.AddSeconds(-$Seconds) $Answered) $now 20 | Should -Be $Expected
    }

    It 'Leaves a search waiting for a runspace, one ended, cancelled or already stopped' {
        $now = [datetime]::UtcNow
        Test-SearchTimedOut (New-TestJob $null $false) $now 60 | Should -BeFalse
        Test-SearchTimedOut (New-TestJob $now.AddHours(-1) $false $true) $now 60 | Should -BeFalse
        $cancelled = New-TestJob $now.AddHours(-1) $false
        $cancelled.Cancelled = $true
        Test-SearchTimedOut $cancelled $now 60 | Should -BeFalse
        $stopped = New-TestJob $now.AddHours(-1) $false
        $stopped.TimedOut = $true
        Test-SearchTimedOut $stopped $now 60 | Should -BeFalse
        # A job made without a clock (an older caller) has no limit.
        Test-SearchTimedOut @{ Handle = [pscustomobject]@{ IsCompleted = $false } } $now 60 | Should -BeFalse
    }

    It "Marks the clock from the users' search script: started, then answered by AD" {
        $clock = New-SearchClock
        $answer = & ([scriptblock]::Create($script:UserSearchScript)) -Domain 'demo.local' -LdapFilter '(anr=Marc Durand)' -LockedOnly $false -RowBuilder '' -Today (Get-Date).Date -Limit 10 -Clock $clock
        $answer.Error | Should -BeNullOrEmpty
        $clock.Started | Should -Not -BeNullOrEmpty
        $clock.Answered | Should -BeTrue
    }

    It 'Counts a query that found nothing as an answer, and a DC that is down as none' {
        $clock = New-SearchClock
        $null = & ([scriptblock]::Create($script:GroupSearchScript)) -Domain 'demo.local' -LdapFilter '(&(objectCategory=group)(name=zzz-aucun*))' -RowBuilder '' -Limit 10 -Clock $clock
        $clock.Answered | Should -BeTrue
        $env:REPERE_FAKEAD_UNREACHABLE = 'demo.local'
        try {
            $clock = New-SearchClock
            $answer = & ([scriptblock]::Create($script:GroupSearchScript)) -Domain 'demo.local' -LdapFilter '(objectCategory=group)' -RowBuilder '' -Limit 10 -Clock $clock
            $answer.Error | Should -BeLike 'Unable to contact the server*'
            $clock.Answered | Should -BeFalse
        }
        finally { $env:REPERE_FAKEAD_UNREACHABLE = $null }
    }

    It 'Stops a silent domain as Annuler does, not waiting for it, and leaves the others' {
        $pool = [runspacefactory]::CreateRunspacePool(1, 2)
        $pool.Open()
        try {
            $jobs = foreach ($seconds in 30, 0) {
                $shell = [powershell]::Create()
                $shell.RunspacePool = $pool
                $clock = New-SearchClock
                $null = $shell.AddScript('param($Clock, $Seconds) $Clock.Started = [datetime]::UtcNow.AddMinutes(-5); if (-not $Seconds) { $Clock.Answered = $true }; Start-Sleep -Seconds 3').AddParameters(@{ Clock = $clock; Seconds = $seconds })
                @{ Domain = "d$seconds"; Shell = $shell; Handle = $shell.BeginInvoke(); Cancelled = $false; TimedOut = $false; Clock = $clock }
            }
            for ($i = 0; $i -lt 100 -and @($jobs | Where-Object { -not $_.Clock.Started }).Count; $i++) { Start-Sleep -Milliseconds 20 }
            Stop-SilentSearch $jobs
            $jobs[0].TimedOut | Should -BeTrue
            $jobs[1].TimedOut | Should -BeFalse
            $script:search.Stopping.Contains($jobs[0]) | Should -BeTrue
            $script:search.Stopping.Contains($jobs[1]) | Should -BeFalse
            $jobs[0].Handle.AsyncWaitHandle.WaitOne(10000) | Should -BeTrue
        }
        finally {
            foreach ($job in $jobs) { $null = $job.Handle.AsyncWaitHandle.WaitOne(10000); $job.Shell.Dispose() }
            $script:search.Stopping.Clear()
            $pool.Dispose()
        }
    }

    It 'Says the domains that did not answer in time apart from those that failed, in the count and its tooltip' {
        $root = [System.Windows.Markup.XamlReader]::Parse(@'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Button x:Name="user_show_all"/><Button x:Name="user_export"/><TextBlock x:Name="user_count"/><Border x:Name="user_empty"/>
</StackPanel>
'@)
        $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new([object[]]@([pscustomobject]@{ Name = 'Bertrand' }))
        $page = @{ Root = $root; Prefix = 'user'; Rows = $rows; View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($rows); Truncated = $null
                   Errors = [ordered]@{ 'demo.local' = 'Access is denied'; 'nord.demo.local' = (Get-SearchTimeoutText) }; TimedOut = @('nord.demo.local') }
        Update-PageCount $page
        $count = $root.FindName('user_count')
        $count.Text | Should -BeExactly '1 utilisateur (erreur : demo.local) (sans réponse : nord.demo.local)'
        $count.ToolTip | Should -BeLike '*nord.demo.local : pas de réponse après 20 secondes (contrôleur de domaine injoignable ?)*'
    }
}

Describe "A user's changes in the background, on the DC its Propriétés reads from" {
    BeforeAll {
        Start-TestPool
        $script:Marc = New-UserRow 'demo.local' '(anr=Marc Durand)'
        $script:Nadia = New-UserRow 'nord.demo.local' '(anr=Nadia Moreau)'
    }

    AfterAll {
        Clear-Stopped
        $script:searchPool.Dispose()
        $script:searchPool = $null
    }

    BeforeEach {
        $script:Shown.Clear()
        $script:DomainCache.Clear()
        $script:ReadTimeout = 30; $script:WriteTimeoutFirst = 45
        foreach ($row in $script:Marc, $script:Nadia) { $row.IsLocked = $true; $row.State = 'Verrouillé' }
    }

    AfterEach {
        $env:REPERE_FAKEAD_SLOW = $null
        $env:REPERE_FAKEAD_UNREACHABLE = $null
        $script:ReadTimeout = 30; $script:WriteTimeoutFirst = 45
        $script:WriteTimeoutEach = 5
        Clear-Stopped
    }

    It 'Returns at once while a slow DC answers, ignores the same click meanwhile, then updates the row and reports' {
        $env:REPERE_FAKEAD_SLOW = 'demo.local=1000'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Start-UserAccountWrite 'Unlock' @($script:Marc)
        $watch.ElapsedMilliseconds | Should -BeLessThan 800
        $script:win.Cursor | Should -Be ([System.Windows.Input.Cursors]::AppStarting)
        $script:Shown | Should -HaveCount 1
        $script:Shown[0] | Should -BeLike 'Notice: Déverrouiller mdurand : en cours…*'
        $reads = $script:BackgroundReadList.Count
        Start-UserAccountWrite 'Unlock' @($script:Marc)
        $script:BackgroundReadList.Count | Should -Be $reads
        $script:Marc.IsLocked | Should -BeTrue
        Wait-Read
        $script:Marc.IsLocked | Should -BeFalse
        $script:Marc.State | Should -BeExactly 'Actif'
        $script:Shown[-1] | Should -BeExactly 'Report: Déverrouiller | ✔ mdurand'
        $script:win.Cursor | Should -BeNullOrEmpty
        Test-ADWriteBusy (Get-UserWriteKey 'Unlock' $script:Marc) | Should -BeFalse
        # The PDC it looked up on its runspace is the window's now, for the next changes and Propriétés.
        $script:DomainCache['demo.local'].Pdc | Should -BeExactly 'dc1.demo.local'
    }

    It "Falls back to another DC when the PDC doesn't answer, and keeps that for the window" {
        $env:REPERE_FAKEAD_UNREACHABLE = 'dc1.demo.local'
        Start-UserAccountWrite 'Disable' @($script:Marc)
        Wait-Read
        $script:Shown[-1] | Should -BeExactly 'Report: Désactiver | ✔ mdurand'
        $script:Marc.IsEnabled | Should -BeFalse
        $script:DomainCache['demo.local'].Fallback | Should -BeExactly 'dc2.demo.local'
        Get-UserServer 'demo.local' | Should -BeExactly 'dc2.demo.local'
        $null = Enable-ADAccount -Server demo.local -Identity $script:Marc.DistinguishedName
        $script:Marc.IsEnabled = $true
    }

    It 'Says a change its DC did not confirm in time may have been made, and what was done before it' {
        # Nadia's domain answers; Marc's DC takes longer than the limit (2 s, for both accounts here).
        $script:WriteTimeoutFirst = 2
        $script:WriteTimeoutEach = 0
        $env:REPERE_FAKEAD_SLOW = 'demo.local=20000'
        Start-UserAccountWrite 'Unlock' @($script:Nadia, $script:Marc)
        Wait-ReadStarted
        Start-Sleep -Milliseconds 2400
        Complete-BackgroundRead
        $report = $script:Shown[-1]
        $report | Should -BeLike 'Report: Déverrouiller | ✔ nmoreau | ⚠ mdurand : pas de réponse du contrôleur de domaine après 2 secondes*'
        $report | Should -BeLike '*la modification a peut-être été faite, vérifiez'
        $script:Nadia.IsLocked | Should -BeFalse
        # Not said to be unlocked: it may not be.
        $script:Marc.IsLocked | Should -BeTrue
        Test-ADWriteBusy (Get-UserWriteKey 'Unlock' $script:Marc) | Should -BeFalse
        $script:win.Cursor | Should -BeNullOrEmpty
    }

    It 'Shows the new password once it is set, the row following, and refuses a second reset meanwhile' {
        $env:REPERE_FAKEAD_SLOW = 'demo.local=500'
        Set-UserPassword $script:Marc 'Tigre-Bleu-42' $true $true $null $null
        Set-UserPassword $script:Marc 'Autre-Mot-7' $true $false $null $null
        $script:Shown[-1] | Should -BeExactly 'Dialog: Nouveau mot de passe | ✖ mdurand : mot de passe non réinitialisé (une réinitialisation est déjà en cours)'
        Wait-Read
        $script:Shown[-1] | Should -BeExactly 'Password: Tigre-Bleu-42 | Unsure=False | '
        $script:Marc.Password | Should -BeExactly 'À changer à la connexion'
        $script:Marc.IsLocked | Should -BeFalse
    }

    It 'Shows the password all the same, saying it may be set, when the DC did not say in time' {
        $script:WriteTimeoutFirst = 1
        $env:REPERE_FAKEAD_SLOW = 'demo.local=20000'
        $script:Marc.Password = 'Expire dans 40 jours'
        Set-UserPassword $script:Marc 'Tigre-Bleu-42' $true $false $null $null
        Wait-ReadStarted
        Start-Sleep -Milliseconds 1300
        Complete-BackgroundRead
        $script:Shown[-1] | Should -BeExactly 'Password: Tigre-Bleu-42 | Unsure=True | '
        $script:Marc.Password | Should -BeExactly 'Expire dans 40 jours'
    }

    It "Looks the PDC up on a read's runspace the first time, keeps it, and gives the read its own result" {
        function Get-TestServer([string]$Server) { "lu sur $Server" }
        $done = @{}
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $env:REPERE_FAKEAD_SLOW = 'demo.local=800'
        Start-UserServerRead -Command 'Get-TestServer' -Arguments @($null) -Domain 'demo.local' -At 0 -Context @{ State = 'fenêtre' } -OnDone {
            param($context, $read) $done.Read = $read; $done.Context = $context
        }.GetNewClosure()
        $watch.ElapsedMilliseconds | Should -BeLessThan 600
        # Found by its State, as Stop-BackgroundRead looks for it.
        $script:BackgroundReadList[$script:BackgroundReadList.Count - 1].Context.State | Should -BeExactly 'fenêtre'
        Wait-Read
        $done.Read | Should -BeExactly 'lu sur dc1.demo.local'
        $done.Context.State | Should -BeExactly 'fenêtre'
        $script:DomainCache['demo.local'].Pdc | Should -BeExactly 'dc1.demo.local'
        Get-KnownUserServer 'demo.local' | Should -BeExactly 'dc1.demo.local'
    }

    It "Makes a computer's Propriétés change in the background, once, then reads the window again" {
        function Update-ComputerDetail { $script:Shown.Add('Relu') }
        $computer = Get-ADComputer -Server demo.local -Filter "Name -eq 'ORD-02'"
        $state = @{ Row = [pscustomobject]@{ Name = 'ORD-02'; Domain = 'demo.local'; DistinguishedName = [string]$computer.DistinguishedName }; Window = [pscustomobject]@{ Cursor = $null }; NoticeAfterRead = $null }
        $env:REPERE_FAKEAD_SLOW = 'demo.local=500'
        Invoke-ComputerDetailChange $state 'Emplacement physique' 'Set-ADComputer' @{ Identity = [string]$computer.DistinguishedName; Location = 'Salle 2' } 'Emplacement physique enregistré.'
        $reads = $script:BackgroundReadList.Count
        Invoke-ComputerDetailChange $state 'Emplacement physique' 'Set-ADComputer' @{ Identity = [string]$computer.DistinguishedName; Location = 'Salle 3' } 'Emplacement physique enregistré.'
        $script:BackgroundReadList.Count | Should -Be $reads
        $state.Window.Cursor | Should -Be ([System.Windows.Input.Cursors]::AppStarting)
        Wait-Read
        $state.NoticeAfterRead | Should -BeExactly 'Emplacement physique enregistré.'
        $script:Shown[-1] | Should -BeExactly 'Relu'
        $state.Window.Cursor | Should -BeNullOrEmpty
        (Get-ADComputer -Server demo.local -Identity $computer.DistinguishedName -Properties Location).Location | Should -BeExactly 'Salle 2'
    }

    It "Adds members to a group in the background, saying which may have been added when its DC stops answering" {
        $group = Get-ADGroup -Server demo.local -Filter "Name -eq 'GG-VPN'"
        $row = [pscustomobject]@{ Name = 'GG-VPN'; Domain = 'demo.local'; DistinguishedName = [string]$group.DistinguishedName }
        $done = @{}
        $script:WriteTimeoutFirst = 1
        $env:REPERE_FAKEAD_SLOW = 'demo.local=20000'
        Start-GroupMemberWrite $true $row @([pscustomobject]@{ Name = 'Marc Durand'; DistinguishedName = $script:Marc.DistinguishedName; Details = '' }) $null 'page' {
            param($context, $result) $done.Context = $context; $done.Result = $result
        }.GetNewClosure()
        Wait-ReadStarted
        Start-Sleep -Milliseconds 1300
        Complete-BackgroundRead
        $done.Context | Should -BeExactly 'page'
        @($done.Result.Added).Count | Should -Be 0
        @($done.Result.Failed) | Should -HaveCount 1
        $done.Result.Failed[0] | Should -BeLike '⚠ Marc Durand : pas de réponse du contrôleur de domaine après 1 secondes*vérifiez'
    }
}

Describe "What a change learnt of the DCs, kept for the window's (Merge-DomainCache)" {
    BeforeEach { $script:DomainCache.Clear() }
    AfterEach { $script:DomainCache.Clear() }

    It 'Keeps an entry the runspace replaced, and leaves one it did not' {
        $kept = @{ Pdc = 'dc1.nord.demo.local'; Policy = 'nord'; PdcDown = $null; PdcProblem = $null; Fallback = $null }
        $script:DomainCache['nord.demo.local'] = $kept
        $sent = $script:DomainCache.Clone()
        $learnt = $sent.Clone()
        $learnt['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $null; PdcProblem = $null; Fallback = $null }
        Merge-DomainCache $sent $learnt
        $script:DomainCache['demo.local'].Pdc | Should -BeExactly 'dc1.demo.local'
        [object]::ReferenceEquals($script:DomainCache['nord.demo.local'], $kept) | Should -BeTrue
    }

    It 'Keeps a PDC the window found down later over what the runspace found, and the policy read meanwhile' {
        $now = [datetime]::UtcNow
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $null; PdcProblem = $null; Fallback = $null }
        $sent = $script:DomainCache.Clone()
        $learnt = $sent.Clone()
        $learnt['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $now.AddSeconds(-10); PdcProblem = 'down'; Fallback = 'dc2.demo.local' }
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = $null; PdcDown = $now; PdcProblem = 'down'; Fallback = 'dc3.demo.local' }
        Merge-DomainCache $sent $learnt
        $script:DomainCache['demo.local'].Fallback | Should -BeExactly 'dc3.demo.local'
        # Found down by the runspace only, the policy a Propriétés read added meanwhile kept with it.
        $script:DomainCache['demo.local'] = @{ Pdc = 'dc1.demo.local'; Policy = 'politique'; PdcDown = $null; PdcProblem = $null; Fallback = $null }
        Merge-DomainCache $sent $learnt
        $script:DomainCache['demo.local'].Fallback | Should -BeExactly 'dc2.demo.local'
        $script:DomainCache['demo.local'].Policy | Should -BeExactly 'politique'
    }
}

Describe 'A report line for a change that may have been made' {
    It 'Is neither done nor failed: <Case>' -ForEach @(
        @{ Case = 'done'; Answer = @{ Problem = $null; Unsure = $false }; Expected = '✔ mdurand' }
        @{ Case = 'failed'; Answer = @{ Problem = 'Access is denied'; Unsure = $false }; Expected = '✖ mdurand : Access is denied' }
        @{ Case = 'unsure'; Answer = @{ Problem = $null; Unsure = $true }; Expected = '⚠ mdurand : pas de réponse du contrôleur de domaine après 120 secondes : la modification a peut-être été faite, vérifiez' }
    ) {
        Get-WriteLine 'mdurand' $Answer 120 | Should -BeExactly $Expected
    }

    It 'Reads each step from the progress, unsure only when the DC stopped answering before it' {
        $progress = @{ 0 = @{ Problem = $null }; 1 = @{ Problem = 'refusé' } }
        $late = @{ Progress = $progress; TimedOut = $true; Problem = 'pas de réponse'; Timeout = 130 }
        (Get-WriteAnswer $late 0).Unsure | Should -BeFalse
        (Get-WriteAnswer $late 1).Problem | Should -BeExactly 'refusé'
        (Get-WriteAnswer $late 2).Unsure | Should -BeTrue
        $broken = @{ Progress = @{}; TimedOut = $false; Problem = 'runspace cassé'; Timeout = 120 }
        (Get-WriteAnswer $broken 0).Problem | Should -BeExactly 'runspace cassé'
        (Get-WriteAnswer $broken 0).Unsure | Should -BeFalse
    }

    It 'Gives a change of more objects more time: 45 s, then 5 s each' {
        Get-WriteTimeout 1 | Should -Be 45
        Get-WriteTimeout 5 | Should -Be 65
    }

    It 'Gives a read of more computers more time: 30 s, then 2 s each' {
        Get-ReadTimeout | Should -Be 30
        Get-ReadTimeout 1 | Should -Be 30
        Get-ReadTimeout 200 | Should -Be 428
    }

    It 'Keeps a BitLocker key perhaps deleted listed, and drops those deleted' {
        function Update-BitLockerBody {}
        $keys = @(
            [pscustomobject]@{ ComputerName = 'ORD-01'; KeyId = 'AAAA-1'; Domain = 'demo.local'; DistinguishedName = 'CN=k1' }
            [pscustomobject]@{ ComputerName = 'ORD-02'; KeyId = 'BBBB-2'; Domain = 'demo.local'; DistinguishedName = 'CN=k2' }
        )
        $rows = [System.Collections.Generic.List[object]]::new([object[]]$keys)
        $state = @{ Rows = $rows; Removing = $true; Window = [pscustomobject]@{ IsVisible = $false } }
        $script:Shown.Clear()
        Complete-BitLockerRemoval $state $keys @{ Progress = @{ 0 = @{ Problem = $null } }; TimedOut = $true; Problem = 'pas de réponse du contrôleur de domaine après 130 secondes'; Timeout = 130 }
        $state.Removing | Should -BeFalse
        @($rows | ForEach-Object ComputerName) | Should -Be @('ORD-02')
        $script:Shown[-1] | Should -BeExactly 'Report: Supprimer des clés BitLocker | ✔ ORD-01 : clé AAAA | ⚠ ORD-02 : clé BBBB peut-être supprimée (pas de réponse du contrôleur de domaine après 130 secondes), vérifiez'
    }
}
