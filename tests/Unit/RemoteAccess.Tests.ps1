# What Forcer les stratégies and PowerShell à distance run on a computer without WinRM (RemoteAccess.ps1): the commands
# that turn WinRM on and put it back, and the scheduled tasks that run them, on the fake AD's computers. ord-01 has
# WinRM; ord-04 doesn't, but answers on DCOM; ord-06 answers neither.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    Import-RepereFakeAD
    $env:REPERE_FAKEAD_LOG = Join-Path ([System.IO.Path]::GetTempPath()) "repere-remote-tests-$PID.log"
    # The technician, after whom the firewall rule and the task that puts WinRM back are named.
    $script:User = $env:USERNAME
    $env:USERNAME = 'technicien'
    $script:Rule = 'Repere-WinRM-technicien'

    function Get-TaskCall {
        # The scheduled task commands the fake AD received, as « Command TaskName », a gpupdate or WinRM-on task's
        # random end left out.
        @(Read-FakeADLog | Where-Object { $_.Command -like '*ScheduledTask' -or $_.Command -eq 'Remove-CimInstance' } | ForEach-Object { "$($_.Command) $($_.TaskName -replace '-[0-9a-f]{8}$', '')" })
    }
}

AfterAll {
    Clear-FakeADLog
    $env:REPERE_FAKEAD_LOG = $null
    $env:USERNAME = $script:User
}

Describe 'Get-WinRMEnableArgument and Get-WinRMRestoreArgument' {
    It 'Only does what WinRM lacks, and puts back only that: <Case>' -ForEach @(
        @{ Case = 'off, as on a client nobody set up'; State = @{ StartMode = 'Manual'; Running = $false; Listener = $false }
           Enable = '/c net.exe start WinRM && cscript.exe //nologo %windir%\System32\winrm.vbs create winrm/config/Listener?Address=*+Transport=HTTP && netsh.exe advfirewall firewall add rule name=Repere-WinRM-technicien dir=in action=allow protocol=TCP localport=5985 profile=any remoteip=10.0.0.5'
           Restore = '/c netsh.exe advfirewall firewall delete rule name=Repere-WinRM-technicien & (netsh.exe advfirewall firewall show rule name=all | findstr.exe /i /l Repere-WinRM >nul || (net.exe start WinRM & cscript.exe //nologo %windir%\System32\winrm.vbs delete winrm/config/Listener?Address=*+Transport=HTTP & net.exe stop WinRM /y)) & (netsh.exe advfirewall firewall show rule name=Repere-WinRM-technicien >nul || schtasks.exe /Delete /TN \Repere-WinRM-technicien /F)' }
        @{ Case = 'disabled'; State = @{ StartMode = 'Disabled'; Running = $false; Listener = $false }
           Enable = '/c sc.exe config WinRM start= demand && net.exe start WinRM && cscript.exe //nologo %windir%\System32\winrm.vbs create winrm/config/Listener?Address=*+Transport=HTTP && netsh.exe advfirewall firewall add rule name=Repere-WinRM-technicien dir=in action=allow protocol=TCP localport=5985 profile=any remoteip=10.0.0.5'
           Restore = '/c netsh.exe advfirewall firewall delete rule name=Repere-WinRM-technicien & (netsh.exe advfirewall firewall show rule name=all | findstr.exe /i /l Repere-WinRM >nul || (net.exe start WinRM & cscript.exe //nologo %windir%\System32\winrm.vbs delete winrm/config/Listener?Address=*+Transport=HTTP & net.exe stop WinRM /y & sc.exe config WinRM start= disabled)) & (netsh.exe advfirewall firewall show rule name=Repere-WinRM-technicien >nul || schtasks.exe /Delete /TN \Repere-WinRM-technicien /F)' }
        @{ Case = 'running with its listener, only the firewall closed'; State = @{ StartMode = 'Auto'; Running = $true; Listener = $true }
           Enable = '/c netsh.exe advfirewall firewall add rule name=Repere-WinRM-technicien dir=in action=allow protocol=TCP localport=5985 profile=any remoteip=10.0.0.5'
           Restore = '/c netsh.exe advfirewall firewall delete rule name=Repere-WinRM-technicien & (netsh.exe advfirewall firewall show rule name=Repere-WinRM-technicien >nul || schtasks.exe /Delete /TN \Repere-WinRM-technicien /F)' }
    ) {
        $winrm = [pscustomobject]$State
        Get-WinRMEnableArgument $winrm @('10.0.0.5') | Should -BeExactly $Enable
        Get-WinRMRestoreArgument $winrm | Should -BeExactly $Restore
        # What the restore puts back is what another technician's Repère reads back from it.
        $back = Get-WinRMRestoreState $Restore
        "$($back.StartMode -eq 'Disabled') $($back.Running) $($back.Listener)" | Should -Be "$($State.StartMode -eq 'Disabled') $($State.Running) $($State.Listener)"
    }

    It 'Names the rule and the task after the technician, with only what a command line takes unquoted: <User>' -ForEach @(
        @{ User = 'jdupont'; Name = 'Repere-WinRM-jdupont' }
        @{ User = 'jean.dupont-2_a'; Name = 'Repere-WinRM-jean.dupont-2_a' }
        @{ User = 'Hélène "x" & calc'; Name = 'Repere-WinRM-H_l_ne__x____calc' }
    ) {
        Get-WinRMRuleName $User | Should -BeExactly $Name
    }

    It 'Lets in only addresses, written back by .NET: no zone, nothing else reaches the command line' {
        $winrm = [pscustomobject]@{ StartMode = 'Auto'; Running = $true; Listener = $true }
        Get-WinRMEnableArgument $winrm @('10.0.0.5', 'fe80::1%12', '10.0.0.5', '10.0.0.6 & calc', 'fd00:10::5') |
            Should -BeLike '* remoteip=10.0.0.5,fe80::1,fd00:10::5'
    }

    It 'Refuses to let in no address at all' {
        { Get-WinRMEnableArgument $null @('nope') } | Should -Throw '*aucune adresse IP*'
    }
}

Describe 'Get-WinRMState' {
    It "Reads ord-04's WinRM: started by hand, stopped, no listener" {
        $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
        $state = Get-WinRMState $session
        "$($state.StartMode) $($state.Running) $($state.Listener)" | Should -Be 'Manual False False'
    }
}

Describe 'Invoke-PolicyUpdateTask' {
    BeforeEach { Clear-FakeADLog }

    It 'Runs gpupdate for the computer as SYSTEM through a task, then deletes it' {
        Invoke-PolicyUpdateTask 'ord-01.demo.local' | Should -Be 0
        Get-TaskCall | Should -Be 'Register-ScheduledTask Repere-gpupdate', 'Start-ScheduledTask Repere-gpupdate', 'Remove-CimInstance Repere-gpupdate'
        $register = @(Read-FakeADLog | Where-Object Command -eq 'Register-ScheduledTask')[0]
        "$($register.Execute) $($register.Arguments) as $($register.UserId)" | Should -Be 'gpupdate.exe /target:computer /force /wait:120 as S-1-5-18'
    }

    It 'Says why a computer that answers neither WinRM nor DCOM was not reached' {
        { Invoke-PolicyUpdateTask 'ord-06.demo.local' } | Should -Throw 'WinRM : *| DCOM : The RPC server is unavailable.'
        Get-TaskCall | Should -BeNullOrEmpty
    }

    It 'Deletes the task even when it never ends' {
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = [uint32]0x41301 } }
        Mock Start-Sleep {}
        $session = New-RemoteCimSession 'ord-01.demo.local'
        { Invoke-RemoteTask -CimSession $session -Name 'Repere-test' -Execute 'cmd.exe' -Argument '/c rem' -TimeoutSeconds 0 } | Should -Throw "*n'a pas fini*"
        Get-TaskCall | Should -Contain 'Remove-CimInstance Repere-test'
    }

    It 'Deletes the task over DCOM too, without the -Confirm a DCOM session refuses (#316)' {
        $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
        Invoke-RemoteTask -CimSession $session -Name 'Repere-test' -Execute 'cmd.exe' -Argument '/c rem' | Should -Be 0
        Get-TaskCall | Should -Be 'Register-ScheduledTask Repere-test', 'Start-ScheduledTask Repere-test', 'Remove-CimInstance Repere-test'
        Get-ScheduledTask -CimSession $session -TaskName 'Repere-test' -ErrorAction Ignore | Should -BeNullOrEmpty
    }

    It 'Refuses -Confirm over DCOM as PowerShell 7.6 and later do, so the test above means something' {
        $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
        $null = Register-ScheduledTask -CimSession $session -TaskName 'Repere-test' -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c rem') -Force
        { Unregister-ScheduledTask -CimSession $session -TaskName 'Repere-test' -Confirm:$false -ErrorAction Ignore } | Should -Throw 'The CancellationTokenSource has been disposed.'
        Get-ScheduledTask -CimSession $session -TaskName 'Repere-test' | Remove-CimInstance -CimSession $session
    }
}

Describe 'The tasks'' dates, whatever the technician''s culture' {
    # In a custom date format, ':' is the culture's time separator and the calendar is the culture's: fi-FI writes
    # 14.30.00, th-TH the Buddhist year 2569. The Task Scheduler reads neither.
    BeforeEach {
        $script:Culture = [cultureinfo]::CurrentCulture
        Clear-FakeADLog
    }
    AfterEach { [cultureinfo]::CurrentCulture = $script:Culture }

    It 'Has a gpupdate task end in 30 minutes, as an XML date, in <Culture>' -ForEach @(
        @{ Culture = 'fi-FI' }
        @{ Culture = 'th-TH' }
    ) {
        # Registering is as far as it needs to go: the trigger is kept, and the task never started.
        Mock Get-Date { [datetime]::new(2026, 11, 11, 14, 0, 0, [System.DateTimeKind]::Utc) }
        Mock Register-ScheduledTask { $script:Trigger = $Trigger; throw 'registered' }
        [cultureinfo]::CurrentCulture = $Culture
        $session = New-RemoteCimSession 'ord-01.demo.local'
        { Invoke-RemoteTask -CimSession $session -Name 'Repere-test' -Execute 'cmd.exe' -Argument '/c rem' } | Should -Throw 'registered'
        $script:Trigger.EndBoundary | Should -BeExactly '2026-11-11T14:30:00Z'
    }

    It 'Reads back when the computer puts WinRM back on its own, in <Culture>' -ForEach @(
        @{ Culture = 'fi-FI' }
        @{ Culture = 'th-TH' }
    ) {
        [cultureinfo]::CurrentCulture = $Culture
        $until = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
        try {
            # Turned on already: the time comes from the task's trigger, as the computer gives it.
            $again = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.6') 4
            [math]::Abs(($again - $until).TotalSeconds) | Should -BeLessThan 1
        }
        finally { Restore-TemporaryWinRM 'ord-04.demo.local' }
    }
}

Describe 'Enable-TemporaryWinRM and Restore-TemporaryWinRM' {
    BeforeEach { Clear-FakeADLog }

    It 'Registers the task that puts WinRM back first, turns WinRM on, then puts it back with that task' {
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeFalse
        $until = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
        $until | Should -BeGreaterThan (Get-Date).AddHours(3.9)
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeTrue
        Get-TaskCall | Should -Be "Register-ScheduledTask $script:Rule", 'Register-ScheduledTask Repere-WinRM-on', 'Start-ScheduledTask Repere-WinRM-on', 'Remove-CimInstance Repere-WinRM-on'
        $restore = @(Read-FakeADLog | Where-Object { $_.TaskName -eq $script:Rule })[0]
        "$($restore.UserId) $($restore.Triggers -join ',')" | Should -Be 'S-1-5-18 Once,Boot'

        Restore-TemporaryWinRM 'ord-04.demo.local'
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeFalse
        (Get-TaskCall)[-1] | Should -Be "Start-ScheduledTask $script:Rule"
        $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
        Get-ScheduledTask -CimSession $session -TaskName $script:Rule -ErrorAction Ignore | Should -BeNullOrEmpty
        Test-WinRMRule $session $script:Rule | Should -BeFalse
    }

    It 'Two technicians on a computer: the first one done leaves the other''s session, the last one puts WinRM back' {
        try {
            $env:USERNAME = 'alice'
            $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
            $env:USERNAME = 'bob'
            Clear-FakeADLog
            $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.6') 4
            # WinRM is on, by Alice: Bob's task puts back what hers found.
            $register = @(Read-FakeADLog | Where-Object Command -eq 'Register-ScheduledTask')
            $register[0].TaskName | Should -Be 'Repere-WinRM-bob'
            $register[0].Arguments | Should -BeLike '/c netsh.exe advfirewall firewall delete rule name=Repere-WinRM-bob & *net.exe stop WinRM /y*'
            $register[1].Arguments | Should -BeLike '/c netsh.exe advfirewall firewall add rule name=Repere-WinRM-bob * remoteip=10.0.0.6'

            $env:USERNAME = 'alice'
            Restore-TemporaryWinRM 'ord-04.demo.local'
            Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeTrue
            $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
            Test-WinRMRule $session 'Repere-WinRM-alice' | Should -BeFalse
            Test-WinRMRule $session 'Repere-WinRM-bob' | Should -BeTrue

            $env:USERNAME = 'bob'
            Restore-TemporaryWinRM 'ord-04.demo.local'
            Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeFalse
            @(Get-ScheduledTask -CimSession $session -TaskName 'Repere-WinRM*' -ErrorAction Ignore) | Should -BeNullOrEmpty
        }
        finally {
            foreach ($user in 'alice', 'bob') { $env:USERNAME = $user; Restore-TemporaryWinRM 'ord-04.demo.local' }
            $env:USERNAME = 'technicien'
        }
    }

    It 'Leaves WinRM on while an older Repère''s rule is left, and puts back what its task found' {
        # As an older Repère left it: its rule and its task, both plain Repere-WinRM, which put everything back.
        $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
        $old = '/c netsh.exe advfirewall firewall delete rule name=Repere-WinRM & net.exe start WinRM & cscript.exe //nologo %windir%\System32\winrm.vbs delete winrm/config/Listener?Address=*+Transport=HTTP & net.exe stop WinRM /y & schtasks.exe /Delete /TN \Repere-WinRM /F'
        $null = Register-ScheduledTask -CimSession $session -TaskName 'Repere-WinRM' -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $old) -Force
        $null = Register-ScheduledTask -CimSession $session -TaskName 'Repere-old-on' -Force -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c net.exe start WinRM && netsh.exe advfirewall firewall add rule name=Repere-WinRM dir=in')
        Start-ScheduledTask -CimSession $session -TaskName 'Repere-old-on'
        Get-ScheduledTask -CimSession $session -TaskName 'Repere-old-on' | Remove-CimInstance -CimSession $session
        try {
            Clear-FakeADLog
            $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.6') 4
            @(Read-FakeADLog | Where-Object Command -eq 'Register-ScheduledTask')[0].Arguments | Should -BeLike '*net.exe start WinRM & *winrm.vbs delete * & net.exe stop WinRM /y*'
            Restore-TemporaryWinRM 'ord-04.demo.local'
            Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeTrue
        }
        finally {
            # The older Repère, done too.
            Start-ScheduledTask -CimSession $session -TaskName 'Repere-WinRM'
        }
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeFalse
    }

    It 'Says so when its rule is still there, and keeps the task, which tries again on its own' {
        $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
        # netsh failed: the rule stays, and so does the task (its schtasks /Delete runs only once the rule is gone).
        $script:KeepRule = $true
        Mock Start-ScheduledTask { (Get-ScheduledTask -CimSession $CimSession -TaskName $TaskName).LastRunTime = Get-Date } -ParameterFilter { $script:KeepRule -and $TaskName -eq $script:Rule }
        Mock Start-Sleep {}
        { Restore-TemporaryWinRM 'ord-04.demo.local' } | Should -Throw "la règle de pare-feu $script:Rule n'a pas pu être supprimée"
        $session = New-RemoteCimSession 'ord-04.demo.local' -DcomOnly
        Get-ScheduledTask -CimSession $session -TaskName $script:Rule -ErrorAction Ignore | Should -Not -BeNullOrEmpty
        $script:KeepRule = $false
        Restore-TemporaryWinRM 'ord-04.demo.local'
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeFalse
    }

    It 'Turned on already by Repère: only lets these addresses in, and keeps the task that puts it back' {
        $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
        Clear-FakeADLog
        $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.6') 4
        Get-TaskCall | Should -Be 'Register-ScheduledTask Repere-WinRM-on', 'Start-ScheduledTask Repere-WinRM-on', 'Remove-CimInstance Repere-WinRM-on'
        @(Read-FakeADLog | Where-Object Command -eq 'Register-ScheduledTask')[0].Arguments | Should -BeLike '/c netsh.exe advfirewall firewall add rule * remoteip=10.0.0.6'
        Restore-TemporaryWinRM 'ord-04.demo.local'
    }

    It 'Puts back what it changed when turning WinRM on fails' {
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = [uint32]5 } } -ParameterFilter { $TaskName -like 'Repere-WinRM-on-*' }
        { Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4 } | Should -Throw "*WinRM n'a pas pu être activé (code 5)*"
        (Get-TaskCall)[-1] | Should -Be "Start-ScheduledTask $script:Rule"
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeFalse
    }

    It 'Turns WinRM on after a try that failed and left its task' {
        $script:FailWinRM = $true
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = [uint32]5 } } -ParameterFilter { $script:FailWinRM -and $TaskName -like 'Repere-WinRM-on-*' }
        Mock Start-ScheduledTask { } -ParameterFilter { $script:FailWinRM -and $TaskName -eq $script:Rule }
        Mock Get-WinRMState { [pscustomobject]@{ StartMode = 'Manual'; Running = $false; Listener = $false } }
        { Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4 } | Should -Throw
        $script:FailWinRM = $false
        Clear-FakeADLog
        $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
        @(Read-FakeADLog | Where-Object Command -eq 'Register-ScheduledTask')[0].Arguments | Should -BeLike '/c net.exe start WinRM && * && netsh.exe advfirewall firewall add rule *'
        Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeTrue
        Restore-TemporaryWinRM 'ord-04.demo.local'
    }

    It 'Returns once WinRM itself answers, not as soon as its port does' {
        # The port opens with the firewall rule; WinRM answers this account two tries later.
        $script:WSManTries = 0
        Mock Test-WSMan { $script:WSManTries++; if ($script:WSManTries -lt 3) { throw 'The WS-Management service cannot process the request.' } }
        Mock Start-Sleep {}
        try {
            $null = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
            $script:WSManTries | Should -Be 3
            Should -Invoke Test-WSMan -Times 3 -Exactly -ParameterFilter { $ComputerName -eq 'ord-04.demo.local' -and $Authentication -eq 'Default' }
        }
        finally { Restore-TemporaryWinRM 'ord-04.demo.local' }
    }

    It 'Gives up waiting for WinRM after 20 tries, and leaves it on for what needs it to say why' {
        Mock Test-WSMan { throw 'Access is denied.' }
        Mock Start-Sleep {}
        try {
            $until = Enable-TemporaryWinRM 'ord-04.demo.local' @('10.0.0.5') 4
            $until | Should -BeGreaterThan (Get-Date).AddHours(3.9)
            Should -Invoke Test-WSMan -Times 20 -Exactly
            Test-RemotePort 'ord-04.demo.local' 5985 | Should -BeTrue
        }
        finally { Restore-TemporaryWinRM 'ord-04.demo.local' }
    }

    It 'Has nothing to put back once the task ran on its own' {
        { Restore-TemporaryWinRM 'ord-04.demo.local' } | Should -Not -Throw
        Get-TaskCall | Should -BeNullOrEmpty
    }
}

Describe 'Get-SpecsCheckWarning: what Caractéristiques says when a computer can''t be read' {
    BeforeAll {
        # ComputerActions.ps1 loads only with the window: the function alone, from its source.
        $source = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerActions.ps1')
        $definition = $source.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-SpecsCheckWarning' }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    It 'Says in a toast that <Case>' -ForEach @(
        @{ Case = 'it is off'; Answer = @{ State = 'Offline'; Ping = $false }; Notice = '✖ ORD-06 : hors ligne (pas de réponse au ping, ni à WinRM ni à DCOM)' }
        @{ Case = 'it is not in the DNS'; Answer = @{ State = 'NoDns' }; Notice = "✖ ORD-06 : introuvable (son nom n'est pas dans le DNS)" }
    ) {
        $warning = Get-SpecsCheckWarning 'ORD-06' ([pscustomobject]$Answer) ''
        $warning.Notice | Should -BeExactly $Notice
        $warning['Heading'] | Should -BeNullOrEmpty
    }

    It '<Case>' -ForEach @(
        @{ Case = 'access denied over DCOM, WinRM closed'; Answer = @{ State = 'Failed'; WinRMError = $null; DcomError = 'Access is denied.' }
           Heading = 'Impossible de lire ORD-06'; Message = "Accès refusé : il faut être administrateur de l'ordinateur."; Icon = 'lock'
           Details = "WinRM : le port 5985 ne répond pas`nDCOM : Access is denied." }
        @{ Case = 'WinRM and DCOM both fail'; Answer = @{ State = 'Failed'; WinRMError = 'WinRM cannot complete the operation.'; DcomError = 'The RPC server is unavailable.' }
           Heading = 'Impossible de lire ORD-06'; Message = 'La connexion a échoué, par WinRM comme par DCOM.'; Icon = 'info'
           Details = "WinRM : WinRM cannot complete the operation.`nDCOM : The RPC server is unavailable." }
        @{ Case = 'WinRM closed, DCOM fails'; Answer = @{ State = 'Failed'; WinRMError = $null; DcomError = 'The RPC server is unavailable.' }
           Heading = 'Impossible de lire ORD-06'; Message = 'WinRM est fermé, et la connexion par DCOM a échoué.'; Icon = 'info'
           Details = "WinRM : le port 5985 ne répond pas`nDCOM : The RPC server is unavailable." }
    ) {
        $warning = Get-SpecsCheckWarning 'ORD-06' ([pscustomobject]$Answer) ''
        $warning.Heading | Should -BeExactly $Heading
        $warning.Message | Should -BeExactly $Message
        $warning.Icon | Should -BeExactly $Icon
        if ($Details) { $warning['Details'] | Should -BeExactly $Details } else { $warning['Details'] | Should -BeNullOrEmpty }
    }

    It 'Says in a toast that it timed out after 30 s, and shows any other error as Windows'' message' {
        $timedOut = Get-SpecsCheckWarning 'ORD-06' $null 'pas de réponse après 30 secondes (ordinateur éteint ou injoignable ?)'
        $timedOut.Notice | Should -BeExactly '✖ ORD-06 : pas de réponse après 30 secondes (ordinateur éteint ou injoignable ?)'
        $other = Get-SpecsCheckWarning 'ORD-06' $null 'Boom'
        $other.Message | Should -BeExactly "La vérification n'a pas abouti."
        $other.Details | Should -BeExactly 'Boom'
    }

    It 'Says nothing when the computer can be read, only needs WinRM turned on, or answers ping only (<Case>)' -ForEach @(
        @{ Case = 'Ready'; Answer = @{ State = 'Ready' } }
        @{ Case = 'NoWinRM'; Answer = @{ State = 'NoWinRM' } }
        @{ Case = 'ping only'; Answer = @{ State = 'Offline'; Ping = $true } }
    ) {
        Get-SpecsCheckWarning 'ORD-06' ([pscustomobject]$Answer) '' | Should -BeNullOrEmpty
    }
}

Describe 'Test-RemoteUnreachable: the failures said in a toast rather than a report' {
    BeforeAll {
        $source = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerActions.ps1')
        $definition = $source.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-RemoteUnreachable' }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    It '<Failure> → <Expected>' -ForEach @(
        @{ Failure = "WinRM : WinRM ne peut pas terminer l'opération. | DCOM : Le serveur RPC n'est pas disponible."; Expected = $true }
        @{ Failure = 'The RPC server is unavailable. (Exception from HRESULT: 0x800706BA)'; Expected = $true }
        @{ Failure = 'pas de réponse après 300 secondes (ordinateur éteint ou injoignable ?)'; Expected = $true }
        @{ Failure = "Accès refusé. | DCOM : Le serveur RPC n'est pas disponible."; Expected = $false }
        @{ Failure = 'WinRM cannot process the request: Kerberos authentication failed.'; Expected = $false }
        @{ Failure = 'Boom'; Expected = $false }
    ) {
        Test-RemoteUnreachable $Failure | Should -Be $Expected
    }
}

Describe 'Get-RemoteFailureReason: « injoignable » only when Windows says the computer was not reached' {
    BeforeAll {
        $source = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerActions.ps1')
        $definition = $source.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-RemoteFailureReason' }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    It '<Failure>' -ForEach @(
        @{ Failure = 'WinRM : WinRM cannot complete the operation. | DCOM : The RPC server is unavailable.'; Expected = 'ordinateur injoignable (WinRM : WinRM cannot complete the operation. | DCOM : The RPC server is unavailable.)' }
        @{ Failure = "DCOM : Le serveur RPC n'est pas disponible."; Expected = "ordinateur injoignable (DCOM : Le serveur RPC n'est pas disponible.)" }
        @{ Failure = 'The client cannot connect to the destination specified in the request. (0x80338012)'; Expected = 'ordinateur injoignable (The client cannot connect to the destination specified in the request. (0x80338012))' }
        @{ Failure = 'The WS-Management service cannot process the request.'; Expected = 'ordinateur injoignable (The WS-Management service cannot process the request.)' }
        @{ Failure = 'DCOM : Access is denied.'; Expected = "accès refusé (il faut être administrateur de l'ordinateur)" }
        # Repère's own messages, about a computer it reached.
        @{ Failure = "WinRM n'a pas pu être activé (code 1)"; Expected = "WinRM n'a pas pu être activé (code 1)" }
        @{ Failure = "la tâche Repere-WinRM-technicien n'a pas fini après 30 secondes"; Expected = "la tâche Repere-WinRM-technicien n'a pas fini après 30 secondes" }
        @{ Failure = "la règle de pare-feu Repere-WinRM-technicien n'a pas pu être supprimée"; Expected = "la règle de pare-feu Repere-WinRM-technicien n'a pas pu être supprimée" }
        @{ Failure = 'WinRM a été activé mais ne répond pas : un autre pare-feu bloque sans doute le port 5985.'; Expected = 'WinRM a été activé mais ne répond pas : un autre pare-feu bloque sans doute le port 5985.' }
    ) {
        Get-RemoteFailureReason $Failure | Should -BeExactly $Expected
    }
}

Describe 'Get-ErrorKind: an error known by its codes, whatever Windows'' language' {
    BeforeAll {
        # Windows' errors in German: neither the French nor the English text Repère used to match.
        function New-CimError([string]$Message, [int64]$Code) {
            # A CimException as CIM gives one, its code in its error data.
            $data = CimCmdlets\New-CimInstance -ClassName MSFT_WmiError -Namespace root/cimv2 -ClientOnly -Property @{
                error_Code = [uint32]$Code; Message = $Message; MessageID = 'HRESULT 0x{0:x8}' -f $Code; CIMStatusCode = [uint32]1
            }
            [Microsoft.Management.Infrastructure.CimException]::new($data)
        }
        function New-RemotingError([string]$Message, [int]$Code) {
            $failure = [System.Management.Automation.Remoting.PSRemotingTransportException]::new($Message)
            $failure.ErrorCode = $Code
            $failure
        }
    }

    It '<Case>: <Expected>' -ForEach @(
        @{ Case = 'UnauthorizedAccessException'; Failure = { [System.UnauthorizedAccessException]::new('Zugriff verweigert') }; Expected = 'AccessDenied' }
        @{ Case = 'Win32 code 5'; Failure = { [System.ComponentModel.Win32Exception]::new(5, 'Zugriff verweigert') }; Expected = 'AccessDenied' }
        @{ Case = 'HRESULT 0x80070005'; Failure = { [System.Runtime.InteropServices.COMException]::new('Zugriff verweigert', 0x80070005) }; Expected = 'AccessDenied' }
        @{ Case = 'WinRM''s access denied'; Failure = { New-RemotingError 'Verbindung mit dem Remoteserver fehlgeschlagen: Zugriff verweigert' 5 }; Expected = 'AccessDenied' }
        @{ Case = 'HRESULT 0x800706BA'; Failure = { [System.Runtime.InteropServices.COMException]::new('Der RPC-Server ist nicht verfügbar.', 0x800706BA) }; Expected = 'RpcUnavailable' }
        @{ Case = 'Win32 code 1722'; Failure = { [System.ComponentModel.Win32Exception]::new(1722, 'Der RPC-Server ist nicht verfügbar.') }; Expected = 'RpcUnavailable' }
        @{ Case = 'CIM over DCOM'; Failure = { New-CimError 'Der RPC-Server ist nicht verfügbar.' 0x800706BAL }; Expected = 'RpcUnavailable' }
        @{ Case = 'CIM over WinRM'; Failure = { New-CimError 'Der Client kann keine Verbindung mit dem in der Anforderung angegebenen Ziel herstellen.' 0x80338012L }; Expected = 'WinRMUnreachable' }
        @{ Case = 'PowerShell''s remoting'; Failure = { New-RemotingError 'Der Client kann keine Verbindung herstellen.' 0x80338012 }; Expected = 'WinRMUnreachable' }
        @{ Case = 'WMI''s invalid namespace'; Failure = { [System.Runtime.InteropServices.COMException]::new('Ungültiger Namespace', 0x8004100E) }; Expected = 'InvalidNamespace' }
        @{ Case = 'the FullyQualifiedErrorId of a CIM error'; Failure = { [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Der RPC-Server ist nicht verfügbar.'), 'HRESULT 0x800706ba,Microsoft.Management.Infrastructure.CimCmdlets.NewCimSessionCommand', 'ConnectionError', $null) }; Expected = 'RpcUnavailable' }
        @{ Case = 'wrapped in another exception'; Failure = { [System.Exception]::new('Fehler', [System.UnauthorizedAccessException]::new('Zugriff verweigert')) }; Expected = 'AccessDenied' }
    ) {
        Get-ErrorKind (& $Failure) | Should -Be $Expected
    }

    It 'Knows nothing of a text, nor of an error without a code it knows, whatever its words' {
        Get-ErrorKind 'Access is denied' | Should -BeNullOrEmpty
        Get-ErrorKind ([System.Exception]::new('Accès refusé')) | Should -BeNullOrEmpty
        Get-ErrorKind ([System.ComponentModel.Win32Exception]::new(2, 'Das System kann die angegebene Datei nicht finden.')) | Should -BeNullOrEmpty
        Get-ErrorKind $null | Should -BeNullOrEmpty
    }

    It 'Finds the codes of an error thrown on another runspace, through what PowerShell wraps it in' {
        $shell = [powershell]::Create()
        $null = $shell.AddScript({ $ErrorActionPreference = 'Stop'; throw [System.Runtime.InteropServices.COMException]::new('Der RPC-Server ist nicht verfügbar.', 0x800706BA) })
        try { $null = $shell.Invoke(); $kinds = 'no error' }
        catch { $kinds = @(Get-ErrorKind $_) }
        finally { $shell.Dispose() }
        $kinds | Should -Be 'RpcUnavailable'
    }

    It 'Finds every cause Repère joined into one message' {
        $failure = [System.Exception]::new('WinRM : Zugriff verweigert | DCOM : Der RPC-Server ist nicht verfügbar.', [System.ComponentModel.Win32Exception]::new(1722))
        $failure.Data['Repere.Causes'] = @([System.UnauthorizedAccessException]::new('Zugriff verweigert'), $null)
        @(Get-ErrorKind $failure) | Sort-Object | Should -Be 'AccessDenied', 'RpcUnavailable'
    }

    It 'Keeps the kinds with the message as Add-ErrorKind gives it, and the text as it is' {
        $failure = Add-ErrorKind 'Der RPC-Server ist nicht verfügbar.' ([System.ComponentModel.Win32Exception]::new(1722))
        "$failure" | Should -BeExactly 'Der RPC-Server ist nicht verfügbar.'
        Get-ErrorKind $failure | Should -Be 'RpcUnavailable'
        $plain = Add-ErrorKind 'Boom' ([System.Exception]::new('Boom'))
        $plain | Should -BeOfType [string]
        $plain.PSObject.Properties['ErrorKind'] | Should -BeNullOrEmpty
    }

    It 'Gets them from the fake computers'' errors, as from a real one''s: <Case>' -ForEach @(
        @{ Case = 'neither WinRM nor DCOM answers'; Expected = 'RpcUnavailable' }
    ) {
        try { $null = New-RemoteCimSession 'ord-06.demo.local'; $caught = $null }
        catch { $caught = $_ }
        $caught.Exception.Message | Should -BeLike 'WinRM : WinRM cannot complete the operation.* | DCOM : The RPC server is unavailable.'
        Get-ErrorKind $caught | Should -Be $Expected
    }

    Context 'In what the remote actions say' {
        BeforeAll {
            $source = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerActions.ps1')
            foreach ($name in 'Test-RemoteUnreachable', 'Get-RemoteFailureReason', 'Get-SpecsCheckWarning') {
                $definition = $source.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
                . ([scriptblock]::Create($definition.Extent.Text))
            }
            $script:Rpc = Add-ErrorKind 'DCOM : Der RPC-Server ist nicht verfügbar.' ([System.ComponentModel.Win32Exception]::new(1722))
            $script:Denied = Add-ErrorKind 'DCOM : Zugriff verweigert' ([System.UnauthorizedAccessException]::new('Zugriff verweigert'))
            $script:WinRM = Add-ErrorKind 'Der Client kann keine Verbindung herstellen.' (New-RemotingError 'Der Client kann keine Verbindung herstellen.' 0x80338012)
            $both = [System.Exception]::new('WinRM : Zugriff verweigert | DCOM : Der RPC-Server ist nicht verfügbar.', [System.ComponentModel.Win32Exception]::new(1722))
            $both.Data['Repere.Causes'] = @([System.UnauthorizedAccessException]::new('Zugriff verweigert'))
            $script:Both = Add-ErrorKind $both.Message $both
            $script:Namespace = Add-ErrorKind 'Ungültiger Namespace' ([System.Runtime.InteropServices.COMException]::new('Ungültiger Namespace', 0x8004100E))
        }

        It 'Says in a toast a computer that does not answer RPC, and only that' {
            Test-RemoteUnreachable $Rpc | Should -BeTrue
            Test-RemoteUnreachable $Denied | Should -BeFalse
            Test-RemoteUnreachable $WinRM | Should -BeFalse
            Test-RemoteUnreachable $Both | Should -BeFalse
            Test-RemoteUnreachable $Namespace | Should -BeFalse
        }

        It 'Says why in French: <Case>' -ForEach @(
            @{ Case = 'RPC'; Name = 'Rpc'; Expected = 'ordinateur injoignable (DCOM : Der RPC-Server ist nicht verfügbar.)' }
            @{ Case = 'access denied'; Name = 'Denied'; Expected = "accès refusé (il faut être administrateur de l'ordinateur)" }
            @{ Case = 'WinRM'; Name = 'WinRM'; Expected = 'ordinateur injoignable (Der Client kann keine Verbindung herstellen.)' }
            @{ Case = 'access denied over WinRM, RPC over DCOM'; Name = 'Both'; Expected = "accès refusé (il faut être administrateur de l'ordinateur)" }
            @{ Case = 'another code'; Name = 'Namespace'; Expected = 'Ungültiger Namespace' }
        ) {
            Get-RemoteFailureReason (Get-Variable -Scope Script -Name $Name -ValueOnly) | Should -BeExactly $Expected
        }

        It 'Says Caractéristiques'' access denied by the errors'' codes: <Case>' -ForEach @(
            @{ Case = 'denied over DCOM'; Dcom = { [System.ComponentModel.Win32Exception]::new(5, 'Zugriff verweigert') }; Message = "Accès refusé : il faut être administrateur de l'ordinateur."; Icon = 'lock' }
            @{ Case = 'RPC over DCOM'; Dcom = { [System.ComponentModel.Win32Exception]::new(1722, 'Der RPC-Server ist nicht verfügbar.') }; Message = 'WinRM est fermé, et la connexion par DCOM a échoué.'; Icon = 'info' }
        ) {
            $cause = & $Dcom
            $answer = [pscustomobject]@{ State = 'Failed'; WinRMError = $null; DcomError = $cause.Message; Causes = @($null, $cause) }
            $warning = Get-SpecsCheckWarning 'ORD-06' $answer ''
            $warning.Message | Should -BeExactly $Message
            $warning.Icon | Should -BeExactly $Icon
            $warning.Details | Should -BeExactly "WinRM : le port 5985 ne répond pas`nDCOM : $($cause.Message)"
        }
    }
}
Describe 'Get-SessionQueryProblem: why quser listed no session, by the codes in its text' {
    It '<Case>' -ForEach @(
        @{ Case = 'access denied, in German'; Text = "Fehler 0x00000005 beim Aufzählen der Sitzungsnamen`nFehler [5]:Zugriff verweigert"; Problem = $true; Message = "Accès refusé : il faut être administrateur de l'ordinateur." }
        @{ Case = 'RPC, in German'; Text = "Fehler 0x000006BA beim Aufzählen der Sitzungsnamen`nFehler [1722]:Der Server ist nicht verfügbar."; Problem = $true; Message = "L'ordinateur ne répond pas : il est éteint ou injoignable, ou il refuse les requêtes de sessions à distance (AllowRemoteRPC à 0, ou pare-feu)." }
        @{ Case = 'RPC, in French'; Text = "Erreur 0x000006BA lors de l'énumération des noms de sessions`nErreur [1722]:Le serveur RPC n'est pas disponible."; Problem = $true; Message = "L'ordinateur ne répond pas : il est éteint ou injoignable, ou il refuse les requêtes de sessions à distance (AllowRemoteRPC à 0, ou pare-feu)." }
        # quser gives no code when nobody is logged on: its text, in English or French.
        @{ Case = 'nobody, in English'; Text = 'No User exists for *'; Problem = $false; Message = "Personne n'a de session ouverte sur cet ordinateur." }
        @{ Case = 'nobody, in French'; Text = 'Aucun utilisateur pour *'; Problem = $false; Message = "Personne n'a de session ouverte sur cet ordinateur." }
        @{ Case = 'anything else'; Text = 'Etwas ist schiefgelaufen'; Problem = $true; Message = 'Les sessions ouvertes sur cet ordinateur n''ont pas pu être lues.' }
    ) {
        $reason = Get-SessionQueryProblem $Text
        $reason.Problem | Should -Be $Problem
        $reason.Message | Should -BeExactly $Message
    }
}