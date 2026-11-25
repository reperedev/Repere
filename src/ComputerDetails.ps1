# Propriétés… of a computer (the Ordinateurs page, #1): what AD knows of it, in the window a user's Propriétés uses
# (UserDetails.ps1: Show-DetailWindow, the cards, chips and lists), read from AD only, so it opens for a computer that
# is off (Caractéristiques, which reads the computer itself, stays the double-click). Its cards: Ordinateur (with
# Activer / Désactiver…, Description… and Déplacer…, the page's own actions and checks), Système, Connexion, Sécurité
# (whether it has a LAPS password and BitLocker keys, without reading the password: Mot de passe LAPS… and Clés
# BitLocker… open them), and Groupes, each opening its group's Propriétés. Dot-sourced by the main script, after
# GroupDetails.ps1; the actions it calls (ComputerActions.ps1) are loaded with the window.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

# Days after which a date of Connexion takes the warning's color: the last logon as the grid's « probably unused »
# (IsStale), and the account's password, which a computer on the domain changes every 30 days, once two changes are
# missed.
$script:ComputerLogonStaleDays = 90
$script:ComputerPasswordStaleDays = 60

function Read-ComputerDetail($Row, [string]$Server) {
    # Everything the window shows, read on a search runspace (Start-DetailRead) in the computer's domain, on $Server
    # (Get-UserServer: the PDC, where the window's changes go, so it shows them once read again). One that doesn't
    # answer: another DC (Get-DomainFallback), and Down says which (Register-ServerDown). Every attribute, as Mot de
    # passe LAPS… reads them (a LAPS attribute the schema doesn't have would fail a query that names it), then only
    # what the window shows: never a LAPS password, only when it expires. Its groups as Groupes… reads them, and how many
    # BitLocker keys it holds (their recovery passwords aren't read).
    $domain = $Row.Domain
    if (-not $Server) { $Server = $domain }
    $down = $null
    $dn = [string]$Row.DistinguishedName
    $read = try { Get-ADComputer -Server $Server -Identity $dn -Properties * -ErrorAction Stop }
            catch {
                if ($Server -eq $domain -or -not (Test-ServerDown $_)) { throw }
                $other = Get-DomainFallback $domain $Server
                $down = @{ Server = $Server; Problem = $_.Exception.Message; Fallback = $other }
                $Server = $other
                Get-ADComputer -Server $Server -Identity $dn -Properties * -ErrorAction Stop
            }
    $computer = $read | Select-Object Name, SamAccountName, DNSHostName, Description, Enabled, OperatingSystem, OperatingSystemVersion, whenCreated,
        whenChanged, Location, ManagedBy, LastLogonDate, PasswordLastSet, MemberOf, PrimaryGroup, PrimaryGroupID, ProtectedFromAccidentalDeletion, DistinguishedName
    # Only the attributes that have a value come back: the others read as none, strict mode or not.
    $expiry = $read | Select-Object 'msLAPS-PasswordExpirationTime', 'ms-Mcs-AdmPwdExpirationTime'
    $laps = if ($expiry.'msLAPS-PasswordExpirationTime') { @{ Kind = 'Windows LAPS'; Expires = $expiry.'msLAPS-PasswordExpirationTime' } }
            elseif ($expiry.'ms-Mcs-AdmPwdExpirationTime') { @{ Kind = Tr 'LAPS hérité'; Expires = $expiry.'ms-Mcs-AdmPwdExpirationTime' } }
            else { @{ Kind = $null; Expires = $null } }
    $keys = try {
        @{ Count = @(Get-ADObject -Server $Server -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -SearchBase $dn -SearchScope OneLevel -ErrorAction Stop).Count; Problem = $null }
    }
    catch { @{ Count = 0; Problem = $_.Exception.Message } }
    $inherited = Read-TokenGroup { Get-ADComputer -Server $Server -Identity $dn -Properties tokenGroups -ErrorAction Stop }
    @{
        Row = $Row; Computer = $computer; Laps = $laps; BitLocker = $keys; Server = $Server; Down = $down
        Groups = @(Get-ObjectGroup $computer $domain $inherited)
    }
}

function Get-ComputerDetailAge($Date, [int]$StaleDays) {
    # A date of Connexion, Text « 2026-11-02 à 08 h 30 (il y a 21 jours) », and its Tone: amber past $StaleDays, or
    # never.
    if (-not $Date) { return @{ Text = Tr 'Jamais'; Tone = 'warn' } }
    $today = (Get-Date).Date
    @{
        Text = '{0} ({1})' -f (Format-TextDate $Date), (Format-Age $Date $today)
        Tone = if (($today - $Date.Date).TotalDays -ge $StaleDays) { 'warn' }
    }
}

function Get-ComputerDetailSection($Detail) {
    # The cards, as [ordered] title -> rows (label, value, id, tone), as a user's (Get-UserDetailSection).
    $computer = $Detail.Computer
    $system = Get-SystemInfo $computer.OperatingSystem $computer.OperatingSystemVersion (Get-Date).Date
    $systemText = if ($system.Short -and $system.Outdated) { (Tr '{0} (plus supporté)') -f $system.Short } else { $system.Short }
    $logon = Get-ComputerDetailAge $computer.LastLogonDate $script:ComputerLogonStaleDays
    $password = Get-ComputerDetailAge $computer.PasswordLastSet $script:ComputerPasswordStaleDays
    $laps = if ($Detail.Laps.Kind) { @($Detail.Laps.Kind, (Format-LapsDate $Detail.Laps.Expires)) -join ' · ' } else { Tr 'Aucun mot de passe' }
    $keys = $Detail.BitLocker
    $keysText = if ($keys.Problem) { (Tr 'non lues : {0}') -f (ConvertTo-FrenchError $keys.Problem) }
                elseif ($keys.Count -eq 0) { Tr 'Aucune clé' }
                elseif ($keys.Count -eq 1) { Tr '1 clé' }
                else { (Tr '{0} clés') -f $keys.Count }
    # Its role as AD's Général says it: by its primary group for a domain controller, else by its Windows.
    $role = switch ([int]$computer.PrimaryGroupID) {
        516 { Tr 'Contrôleur de domaine' }
        521 { Tr 'Contrôleur de domaine en lecture seule' }
        default { if ("$($computer.OperatingSystem)" -match 'Server') { Tr 'Serveur' } else { Tr 'Poste de travail' } }
    }
    $dn = [string]$computer.DistinguishedName
    $protected = [bool]$computer.ProtectedFromAccidentalDeletion
    [ordered]@{
        Ordinateur = @(
            , @((Tr 'Nom'), $computer.Name, 'name')
            , @((Tr 'Nom pré-Windows 2000'), $computer.SamAccountName, 'sam')
            , @((Tr 'Nom DNS'), $computer.DNSHostName, 'dns')
            , @((Tr 'Rôle'), $role, 'role')
            , @((Tr 'Description'), $computer.Description, 'description')
            , @((Tr 'État'), $(if ($computer.Enabled) { Tr 'Actif' } else { Tr 'Désactivé' }), 'state', $(if (-not $computer.Enabled) { 'danger' }))
        )
        Gestion = @(
            , @((Tr 'Emplacement physique'), $computer.Location, 'physical')
            , @((Tr 'Géré par'), $(Get-DnName $computer.ManagedBy), 'managed_by')
        )
        Système = @(
            , @((Tr 'Système'), $systemText, 'system', $(if ($system.Outdated) { 'warn' }))
            , @((Tr 'Version'), $system.Full, 'version')
        )
        Connexion = @(
            , @((Tr 'Dernière connexion'), $logon.Text, 'last_logon', $logon.Tone)
            , @((Tr 'Mot de passe du compte'), $password.Text, 'password_set', $password.Tone)
        )
        Sécurité = @(
            , @('LAPS', $laps, 'laps')
            , @('BitLocker', $keysText, 'bitlocker')
        )
        # AD's Objet: where it is, its canonical name (made from its DN, as AD makes it), its dates and its protection.
        Objet = @(
            , @((Tr 'Emplacement'), (Get-OUPath $dn), 'location')
            , @((Tr 'Nom canonique'), "$(Get-ShortPath $dn)/$($computer.Name)", 'canonical')
            , @((Tr 'Créé'), $(Format-TextDate $computer.whenCreated), 'created')
            , @((Tr 'Modifié'), $(Format-TextDate $computer.whenChanged), 'changed')
            , @((Tr 'Protection'), $(if ($protected) { Tr 'Protégé contre la suppression accidentelle' } else { Tr 'Non protégé' }), 'protected')
        )
    }
}

function Get-ComputerDetailChipXaml($Detail) {
    # The header's chips: what needs attention. Désactivé, a Windows past its support, and a computer not seen on the
    # domain for a while (or never).
    $computer = $Detail.Computer
    $chips = [System.Collections.Generic.List[object]]::new()
    if (-not $computer.Enabled) { $chips.Add(@((Tr 'Désactivé'), 'Danger', 'ban')) }
    $system = Get-SystemInfo $computer.OperatingSystem $computer.OperatingSystemVersion (Get-Date).Date
    if ($system.Outdated) { $chips.Add(@((Tr 'Windows plus supporté'), 'Warn', 'cpu')) }
    $today = (Get-Date).Date
    if (-not $computer.LastLogonDate) { $chips.Add(@((Tr 'Jamais connecté'), 'Warn', 'activity')) }
    elseif (($today - $computer.LastLogonDate.Date).TotalDays -ge $script:ComputerLogonStaleDays) {
        $chips.Add(@(((Tr 'Connecté {0}') -f (Format-Age $computer.LastLogonDate $today)), 'Warn', 'activity'))
    }
    ConvertTo-DetailChipXaml $chips
}

function Get-ComputerDetailXaml($Detail) {
    # The cards: Ordinateur (Activer or Désactiver…, Description…, Déplacer…), Système and Connexion (read only),
    # Sécurité (Mot de passe LAPS… and Clés BitLocker…, each while there's something to show), then Groupes.
    $sections = Get-ComputerDetailSection $Detail
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($script:DetailPanelXaml.Replace('user_detail_', 'computer_detail_'))
    $toggle = if ($Detail.Computer.Enabled) {
        '<Button x:Name="computer_detail_toggle" ToolTip="Désactiver l''ordinateur"><StackPanel Orientation="Horizontal">{{icon:ban:14}}<TextBlock Text="Désactiver…" Margin="8,0,0,0"/></StackPanel></Button>'
    }
    else { '<Button x:Name="computer_detail_toggle" ToolTip="Activer l''ordinateur"><StackPanel Orientation="Horizontal">{{icon:checkcircle:14}}<TextBlock Text="Activer" Margin="8,0,0,0"/></StackPanel></Button>' }
    $hasLaps = [bool]$Detail.Laps.Kind
    $hasKeys = $Detail.BitLocker.Count -gt 0 -or [bool]$Detail.BitLocker.Problem
    foreach ($title in $sections.Keys) {
        $action = switch ($title) {
            'Ordinateur' {
                "<StackPanel Grid.Column=`"2`" Orientation=`"Horizontal`">$toggle" +
                '<Button x:Name="computer_detail_edit" Margin="8,0,0,0" ToolTip="Modifier la description"><StackPanel Orientation="Horizontal">{{icon:pencil:14}}<TextBlock Text="Description…" Margin="8,0,0,0"/></StackPanel></Button>' +
                '<Button x:Name="computer_detail_move" Margin="8,0,0,0" ToolTip="Déplacer vers une autre OU"><StackPanel Orientation="Horizontal">{{icon:move:14}}<TextBlock Text="Déplacer…" Margin="8,0,0,0"/></StackPanel></Button></StackPanel>'
            }
            'Sécurité' {
                "<StackPanel Grid.Column=`"2`" Orientation=`"Horizontal`">" +
                "<Button x:Name=`"computer_detail_laps_open`" IsEnabled=`"$hasLaps`"><StackPanel Orientation=`"Horizontal`">{{icon:key:14}}<TextBlock Text=`"Mot de passe LAPS…`" Margin=`"8,0,0,0`"/></StackPanel></Button>" +
                "<Button x:Name=`"computer_detail_bitlocker_open`" Margin=`"8,0,0,0`" IsEnabled=`"$hasKeys`"><StackPanel Orientation=`"Horizontal`">{{icon:drivelock:14}}<TextBlock Text=`"Clés BitLocker…`" Margin=`"8,0,0,0`"/></StackPanel></Button></StackPanel>"
            }
            'Gestion' {
                '<StackPanel Grid.Column="2" Orientation="Horizontal">' +
                '<Button x:Name="computer_detail_physical_edit" ToolTip="Modifier l''emplacement physique"><StackPanel Orientation="Horizontal">{{icon:pencil:14}}<TextBlock Text="Emplacement…" Margin="8,0,0,0"/></StackPanel></Button>' +
                '<Button x:Name="computer_detail_manager" Margin="8,0,0,0" ToolTip="Choisir qui gère l''ordinateur"><StackPanel Orientation="Horizontal">{{icon:user:14}}<TextBlock Text="Géré par…" Margin="8,0,0,0"/></StackPanel></Button></StackPanel>'
            }
            # Protéger at once; Ne plus protéger… asks first (Invoke-ComputerProtection).
            'Objet' {
                if ($Detail.Computer.ProtectedFromAccidentalDeletion) {
                    '<Button x:Name="computer_detail_protect" Grid.Column="2" ToolTip="Permettre de le supprimer ou de le déplacer"><StackPanel Orientation="Horizontal">{{icon:unlock:14}}<TextBlock Text="Ne plus protéger…" Margin="8,0,0,0"/></StackPanel></Button>'
                }
                else { '<Button x:Name="computer_detail_protect" Grid.Column="2" ToolTip="Empêcher de le supprimer ou de le déplacer"><StackPanel Orientation="Horizontal">{{icon:lock:14}}<TextBlock Text="Protéger" Margin="8,0,0,0"/></StackPanel></Button>' }
            }
        }
        $tone = if ($title -in 'Système', 'Connexion') { 'readonly' } elseif ($title -eq 'Ordinateur' -and -not $Detail.Computer.Enabled) { 'danger' }
        $parts.Add((Get-DetailCardXaml $title (Get-DetailRowsXaml $sections[$title] 'computer_detail' -Copy 'dns') $action -Tone $tone))
        # The groups after Sécurité: what can be changed before what's only read (Objet's protection aside).
        if ($title -eq 'Sécurité') { $parts.Add((Get-ComputerGroupXaml $Detail)) }
    }
    $parts.Add('</StackPanel>')
    Expand-Icon ($parts -join "`n")
}

function Get-ComputerGroupXaml($Detail) {
    # Groupes, as Groupes… lists them (direct, primary, inherited): each group read opens its Propriétés. The direct ones
    # have a box to tick, for Retirer…; Ajouter à un groupe… in the header, as a user's. A long list has a box to filter
    # it. Only a group that was read has a box: a row that says why groups couldn't be has no type.
    $items = foreach ($group in $Detail.Groups) {
        $kind = @($group.Type, $group.Scope, $(if ($group.Domain -ne $Detail.Row.Domain) { $group.Domain })) | Where-Object { $_ }
        $membership = Tr $group.Membership
        @{
            Name = $group.Name; Badge = $membership; Automation = "$($group.Name) | $membership"; Target = if ($group.Type) { $group }
            CanPick = $group.Membership -eq 'Directe' -and [bool]$group.Type
            Detail = (@($kind -join ', ') + @($group.Description | Where-Object { $_ })) -join ' · '
            Tone = switch ($group.Membership) { 'Directe' { 'accent' } 'Principale' { 'neutral' } default { 'outline' } }
        }
    }
    $body = if ($Detail.Groups.Count) { Get-DetailListXaml @($items) 'computer_group' (Tr 'À retirer') -FilterTip (Tr 'Filtrer les groupes') -NoMatch (Tr 'Aucun groupe.') }
            else { '<TextBlock Style="{StaticResource Txt.Muted}" Margin="14,0,14,8" Text="Membre d''aucun groupe."/>' }
    $action = @'
<StackPanel Grid.Column="2" Orientation="Horizontal">
  <Button x:Name="computer_group_remove" IsEnabled="False" ToolTip="Retirer des groupes directs cochés">
    <StackPanel Orientation="Horizontal">{{icon:trash:14}}<TextBlock x:Name="computer_group_remove_label" Text="Retirer…" Margin="8,0,0,0"/></StackPanel>
  </Button>
  <Button x:Name="computer_group_add" Margin="8,0,0,0"><StackPanel Orientation="Horizontal">{{icon:plus:14}}<TextBlock Text="Ajouter à un groupe…" Margin="8,0,0,0"/></StackPanel></Button>
</StackPanel>
'@
    Get-DetailCardXaml 'Groupes' $body $action -Count $Detail.Groups.Count -Footer (Tr "Prend effet au prochain redémarrage de l'ordinateur.")
}

function Update-ComputerDetail($State, $Detail) {
    # Reads the computer again in the background (Start-DetailRead), unless $Detail was just read: then rebuilds the
    # cards, and the page's row follows (Sync-ComputerDetailRow).
    if (-not $Detail) { Start-DetailRead $State; return }
    $State.Detail = $Detail
    # The PDC didn't answer the read: kept as down, and the changes go where it read instead.
    Register-ServerDown $State.Row.Domain $Detail.Down
    Sync-ComputerDetailRow $State
    $computer = $Detail.Computer
    $row = $State.Row
    $State.Title.Text = $row.Name
    $State.Subtitle.Text = (@([string]$computer.Description, $row.Domain, (Get-OUPath $row.DistinguishedName)) | Where-Object { $_ }) -join ' · '
    $State.Initials.Visibility = 'Collapsed'
    $State.Glyph.Visibility = 'Visible'
    $State.Chips.Content = [System.Windows.Markup.XamlReader]::Parse((Get-ComputerDetailChipXaml $Detail))
    $body = [System.Windows.Markup.XamlReader]::Parse((Get-ComputerDetailXaml $Detail))
    $State.Body.Content = $body
    $body.FindName('computer_detail_toggle').Add_Click({ param($button) Invoke-ComputerDetailAction ([System.Windows.Window]::GetWindow($button).Tag) 'Toggle' })
    $body.FindName('computer_detail_edit').Add_Click({ param($button) Invoke-ComputerDetailAction ([System.Windows.Window]::GetWindow($button).Tag) 'Description' })
    $body.FindName('computer_detail_move').Add_Click({ param($button) Invoke-ComputerDetailAction ([System.Windows.Window]::GetWindow($button).Tag) 'Move' })
    $body.FindName('computer_detail_laps_open').Add_Click({ param($button) Invoke-ComputerDetailAction ([System.Windows.Window]::GetWindow($button).Tag) 'Laps' })
    $body.FindName('computer_detail_bitlocker_open').Add_Click({ param($button) Invoke-ComputerDetailAction ([System.Windows.Window]::GetWindow($button).Tag) 'BitLocker' })
    $body.FindName('computer_detail_physical_edit').Add_Click({ param($button) Show-ComputerLocationDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('computer_detail_manager').Add_Click({ param($button) Show-ComputerManagerDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('computer_detail_protect').Add_Click({ param($button) Invoke-ComputerProtection ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('computer_group_add').Add_Click({ param($button) Show-ComputerGroupAddDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('computer_group_remove').Add_Click({ param($button) Remove-ComputerGroup ([System.Windows.Window]::GetWindow($button).Tag) })
    $State.Picks = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Detail.Groups.Count; $i++) {
        $pick = $body.FindName("computer_group_pick_$i")
        if (-not $pick) { continue }
        $pick.Tag = $Detail.Groups[$i]
        $State.Picks.Add($pick)
        $pick.Add_Checked({ param($box) Update-ComputerGroupPick ([System.Windows.Window]::GetWindow($box).Tag) })
        $pick.Add_Unchecked({ param($box) Update-ComputerGroupPick ([System.Windows.Window]::GetWindow($box).Tag) })
    }
    Register-DetailOpen $body 'computer_group' $Detail.Groups
    Register-DetailFilter $body 'computer_group' $State
    Register-DetailSection $body
    Register-DetailCopy $body (Get-ComputerDetailSection $Detail) @('dns') 'computer_detail'
}

function Get-ComputerDetailTarget($State) {
    # The row an action of the window acts on: the page's own, while its grid lists that computer (so its row changes
    # with it), else the window's copy.
    $dn = [string]$State.Row.DistinguishedName
    $rows = if (Test-Path variable:script:results) { @($script:results.Rows) } else { @() }
    $shown = $rows | Where-Object { [string]::Equals([string]$_.DistinguishedName, $dn, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($shown) { $State.Row.Computer = $shown }
    $State.Row.Computer
}

function Sync-ComputerDetailRow($State) {
    # What was just read, on the row the window acts on, and on the page's when it lists the computer: its
    # description and state, as a change made elsewhere (ADUC, another Repère) leaves them. The grid redrawn only when
    # one of them differs.
    $computer = $State.Detail.Computer
    $target = Get-ComputerDetailTarget $State
    $description = if ($computer.Description) { [string]$computer.Description } else { $null }
    $enabled = [bool]$computer.Enabled
    if ($target.Description -eq $description -and [bool]$target.IsOn -eq $enabled) { return }
    if (Get-Command Set-RowDescription -ErrorAction SilentlyContinue) {
        Set-RowDescription $target $description
        Set-RowState $target $enabled
        Update-ChangedRow
        return
    }
    $target.Description = $description
    $target.IsOn = $enabled
    $target.Disabled = if ($enabled) { $null } else { Tr 'Désactivé' }
}

function Invoke-ComputerDetailAction($State, [string]$Action) {
    # The window's buttons: the page's actions on its computer, their dialogs over the window, their report in its toast
    # (or a dialog over it for a failure: Complete-ComputerDetailChange), with the page's checks (a domain controller or
    # the computer Repère runs on are left alone). Mot de passe LAPS… and Clés BitLocker… open their window over it.
    if (-not $State.Detail) { return }
    $target = Get-ComputerDetailTarget $State
    switch ($Action) {
        'Toggle' { if ($State.Detail.Computer.Enabled) { Request-ComputerDisable @($target) $State } else { Set-ComputerEnabled @($target) $true $State } }
        'Description' { Show-ComputerDescriptionDialog @($target) $State }
        'Move' { Request-ComputerMove @($target) $State }
        'Laps' { Show-LapsDialog @($target) $State.Window $State.Window.Icon }
        'BitLocker' { Show-BitLockerDialog @($target) $State.Window $State.Window.Icon }
    }
}

function Complete-ComputerDetailChange($State, [string[]]$Lines, [string]$Title, [string[]]$Outcome) {
    # What a change made from the window did (Start-ComputerWrite): a failure in a dialog over it, a success in its toast,
    # once it has read the computer again. Moved, it's known by its new DN. Closed meanwhile: reported as the page's.
    if ($State['Closed']) { Show-ActionReport $Lines $Title -Outcome $Outcome; return }
    $row = $State.Row
    $row.DistinguishedName = [string]$row.Computer.DistinguishedName
    $key = Get-DetailWindowKey 'computer_detail' $row
    if ($key -ne $State.Key) {
        $script:DetailWindows.Remove($State.Key)
        $State.Key = $key
        $script:DetailWindows[$key] = $State.Window
    }
    if (@($Lines | Where-Object { "$_".StartsWith('✖') }).Count) { Show-ActionReport $Lines $Title -Owner $State.Window -Outcome $Outcome }
    elseif ($Outcome) { $State.NoticeAfterRead = "$($Outcome[0])." }
    Update-ComputerDetail $State
}

function Invoke-ComputerDetailChange($State, [string]$Title, [string]$Command, [hashtable]$Parameters, [string]$Done) {
    # A change the window makes itself (Emplacement…, Géré par…, the protection): & $Command -Server <DC> @Parameters,
    # in the background (Invoke-DetailChange, Start-ADWrite), on the DC it reads from (Invoke-UserChange: the PDC, or
    # the DC in its place). The window stays usable, its pointer saying it runs; the same change asked again
    # meanwhile is ignored. Then Complete-ComputerDetailWrite.
    $row = $State.Row
    $null = Start-ADWrite -Keys @("$Title|$($row.Domain)|$($row.DistinguishedName)") -Command 'Invoke-DetailChange' -Arguments @([string]$row.Domain, $Command, $Parameters) `
        -Window $State.Window -Context @{ State = $State; Title = $Title; Done = $Done } -OnDone {
        param($write, $outcome)
        Complete-ComputerDetailWrite $write.State $write.Title $write.Done (Get-WriteAnswer $outcome 0) $outcome.Timeout
    }
}

function Invoke-DetailChange([string]$Domain, [string]$Command, [hashtable]$Parameters) {
    # On a search runspace: & $Command -Server <DC> @Parameters, for an object of $Domain, on the DC its Propriétés
    # reads from (Invoke-UserChange). Its Problem (Add-WriteProgress, as step 0), $null when done.
    $problem = try {
        $null = Invoke-UserChange $Domain { param($server) & $Command -Server $server @Parameters -ErrorAction Stop }
        $null
    }
    catch { $_.Exception.Message }
    Add-WriteProgress 0 @{ Problem = $problem }
}

function Complete-ComputerDetailWrite($State, [string]$Title, [string]$Done, $Answer, [int]$Timeout) {
    # Invoke-ComputerDetailChange's change: done, $Done in the toast once the window has read the computer again; or
    # why not, in a dialog over it; or perhaps done, its DC not having answered in time, which the dialog says to
    # check. Closed meanwhile: a failure is said over the main window.
    $name = $State.Row.Name
    $owner = Get-DetailOwner $State
    if ($Answer.Unsure) { Show-Dialog -Title $Title -Icon 'warning' -Tone 'warn' -Message ((Tr '⚠ {0} : {1}') -f $name, (Get-WriteUnsureText $Timeout)) -Owner $owner }
    elseif ($Answer.Problem) { Show-Dialog -Title $Title -Message ((Tr '✖ {0} : {1}') -f $name, $Answer.Problem) -Owner $owner }
    elseif (-not $State['Closed']) { $State.NoticeAfterRead = $Done }
    if (-not $State['Closed']) { Update-ComputerDetail $State }
}

function Show-ComputerLocationDialog($State) {
    # Emplacement…: the physical location (AD's location attribute), as text; empty clears it.
    Show-Dialog -Title (Tr 'Emplacement physique') -Heading ((Tr 'Emplacement physique de {0}') -f $State.Row.Name) -Icon 'pencil' -Owner $State.Window `
        -WithTextBox -Text ([string]$State.Detail.Computer.Location) -OkText (Tr 'Enregistrer') -State @{ Detail = $State } -OnOk {
        param($dialog)
        $place = "$($dialog.TextBox.Text)".Trim()
        $dn = [string]$dialog.Detail.Row.DistinguishedName
        $change = if ($place) { @{ Identity = $dn; Location = $place } } else { @{ Identity = $dn; Clear = 'location' } }
        Invoke-ComputerDetailChange $dialog.Detail (Tr 'Emplacement physique') 'Set-ADComputer' $change `
            $(if ($place) { Tr 'Emplacement physique enregistré.' } else { Tr 'Emplacement physique effacé.' })
    }
}

function Show-ComputerManagerDialog($State) {
    # Géré par…: the person found by the start of a name, login or email (New-ManagerPickerContent), saved at once;
    # Aucun, while someone is named, clears it.
    $content = New-ManagerPickerContent $State.Row.Domain ''
    $list = $content.FindName('manager_results')
    $clear = if ($State.Detail.Computer.ManagedBy) { Tr 'Aucun' }
    Show-Dialog -Title (Tr 'Géré par') -Heading ((Tr 'Qui gère {0} ?') -f $State.Row.Name) -Icon 'user' -Owner $State.Window -Content $content -PickFrom $list `
        -OkText (Tr 'Choisir') -AltText $clear -State @{ Detail = $State; List = $list } -OnOk {
        param($dialog)
        $dialog.List.Parent.Parent.Parent.Tag.Timer.Stop()
        $picked = $dialog.List.SelectedItem
        if (-not $picked) { return }
        $manager = [string]$picked.DistinguishedName
        $dn = [string]$dialog.Detail.Row.DistinguishedName
        Invoke-ComputerDetailChange $dialog.Detail (Tr 'Géré par') 'Set-ADComputer' @{ Identity = $dn; ManagedBy = $manager } ((Tr 'Géré par {0}.') -f $picked.Name)
    } -OnAlt {
        param($dialog)
        $dialog.List.Parent.Parent.Parent.Tag.Timer.Stop()
        $dn = [string]$dialog.Detail.Row.DistinguishedName
        Invoke-ComputerDetailChange $dialog.Detail (Tr 'Géré par') 'Set-ADComputer' @{ Identity = $dn; Clear = 'managedBy' } (Tr 'Géré par : effacé.')
    }
}

function Invoke-ComputerProtection($State) {
    # Protéger, at once; Ne plus protéger… after a confirmation, Annuler the default: the protection is what stops a
    # deletion or a move by mistake.
    if (-not $State.Detail.Computer.ProtectedFromAccidentalDeletion) { Set-ComputerDetailProtection $State $true; return }
    Show-Dialog -Title (Tr 'Protection') -Heading ((Tr 'Ne plus protéger {0} ?') -f $State.Row.Name) -Icon 'unlock' -Tone 'warn' -Owner $State.Window `
        -Message (Tr 'Il pourra être supprimé ou déplacé.') -OkText (Tr 'Ne plus protéger') -CancelIsDefault -State @{ Detail = $State } -OnOk {
        param($dialog)
        Set-ComputerDetailProtection $dialog.Detail $false
    }
}

function Set-ComputerDetailProtection($State, [bool]$Protect) {
    $dn = [string]$State.Row.DistinguishedName
    Invoke-ComputerDetailChange $State (Tr 'Protection') 'Set-ADObject' @{ Identity = $dn; ProtectedFromAccidentalDeletion = $Protect } `
        $(if ($Protect) { Tr 'Protégé contre la suppression accidentelle.' } else { Tr 'Plus protégé contre la suppression accidentelle.' })
}

function Update-ComputerGroupPick($State) {
    # Retirer… says how many groups are ticked, and waits for one.
    $count = @($State.Picks | Where-Object IsChecked).Count
    $State.Body.Content.FindName('computer_group_remove').IsEnabled = $count -gt 0
    $State.Body.Content.FindName('computer_group_remove_label').Text = if ($count) { (Tr 'Retirer ({0})…') -f $count } else { Tr 'Retirer…' }
}

function Show-ComputerGroupAddDialog($State) {
    # Ajouter à un groupe…: the picker of a user's (New-GroupPickerContent), the groups it's in left out, with the second
    # confirmation for a privileged group (Confirm-PrivilegedGroup).
    $row = $State.Row
    $content = New-GroupPickerContent $row.Domain @($State.Detail.Groups | Where-Object Membership -in 'Directe', 'Principale' | ForEach-Object DistinguishedName)
    Show-Dialog -Title (Tr 'Ajouter à un groupe') -Heading ((Tr 'Ajouter {0} à des groupes') -f $row.Name) -Icon 'users' -Owner $State.Window `
        -Message ((Tr 'Cochez un ou plusieurs groupes de {0}.') -f $row.Domain) -Content $content -PickFrom $content.FindName('group_results') -OkText (Tr 'Ajouter') `
        -State @{ Detail = $State; Content = $content; Groups = @() } -OnOk {
        param($dialog)
        $dialog.Groups = @($dialog.Content.FindName('group_results').SelectedItems)
        if (-not $dialog.Groups.Count) { return }
        Confirm-PrivilegedGroup $dialog.Groups $dialog.Detail.Row.Name $dialog.Detail.Window $dialog { param($dialog) Set-ComputerGroupList $dialog.Detail $dialog.Groups $true }
    }
}

function Remove-ComputerGroup($State) {
    # Retirer…: the computer out of the direct groups ticked, after one confirmation that names them.
    $row = $State.Row
    $groups = @($State.Picks | Where-Object IsChecked | ForEach-Object Tag)
    if (-not $groups.Count) { return }
    $names = @($groups | ForEach-Object Name)
    $heading, $message = if ($groups.Count -eq 1) {
        ((Tr 'Retirer {0} de {1} ?') -f $row.Name, $names[0]), (Tr 'Il perd les accès donnés par ce groupe à son prochain redémarrage.')
    }
    else { ((Tr 'Retirer {0} de {1} groupes ?') -f $row.Name, $groups.Count), (Tr 'Il perd les accès donnés par ces groupes à son prochain redémarrage.') }
    Show-Dialog -Title (Tr 'Retirer du groupe') -Heading $heading -Names $(if ($groups.Count -gt 1) { $names }) -Icon 'users' -Tone 'danger' -Owner $State.Window `
        -Message $message -OkText (Tr 'Retirer') -CancelIsDefault -State @{ Detail = $State; Groups = $groups } -OnOk {
        param($dialog)
        Set-ComputerGroupList $dialog.Detail $dialog.Groups $false
    }
}

function Set-ComputerGroupList($State, $Groups, [bool]$Add) {
    # The computer into ($Add) or out of each group, one at a time so one refused doesn't stop the others, in the
    # background (Invoke-UserGroupWrite, Start-ADWrite): the window usable meanwhile, a group already being changed for
    # it left out. A group of another domain gets the computer as read in its own domain, which that domain's DC can't
    # find by DN (Get-ComputerAsMember). Then Complete-ComputerGroupWrite.
    $row = $State.Row
    $key = { param($group) "Group|$($row.Domain)|$($row.DistinguishedName)|$($group.DistinguishedName)" }
    $pending = @($Groups | Where-Object { -not (Test-ADWriteBusy (& $key $_)) })
    if (-not $pending.Count) { return }
    $copies = @($pending | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; DistinguishedName = [string]$_.DistinguishedName } })
    $computer = [pscustomobject]@{ Name = [string]$row.Name; Domain = [string]$row.Domain; DistinguishedName = [string]$row.DistinguishedName }
    $null = Start-ADWrite -Keys @($pending | ForEach-Object { & $key $_ }) -Command 'Invoke-UserGroupWrite' -Arguments @($computer, $copies, $Add, 'Get-ComputerAsMember') `
        -Functions 'Get-ComputerAsMember', 'Get-DomainOfDN' -Count $copies.Count -Window $State.Window -Context @{ State = $State; Groups = $copies; Add = $Add } -OnDone {
        param($write, $outcome)
        Complete-ComputerGroupWrite $write.State $write.Groups $write.Add $outcome
    }
}

function Complete-ComputerGroupWrite($State, $Groups, [bool]$Add, $Outcome) {
    # Set-ComputerGroupList's change: the window read again, a notice of the groups that took, and a dialog of the
    # others, refused or perhaps done (the DC didn't answer in time: Get-WriteAnswer). Closed meanwhile: said over the
    # main window.
    $name = $State.Row.Name
    $done = [System.Collections.Generic.List[string]]::new()
    $lines = for ($i = 0; $i -lt $Groups.Count; $i++) {
        $group = $Groups[$i]
        $answer = Get-WriteAnswer $Outcome $i
        if ($answer.Unsure) { (Tr '⚠ {0} : {1}') -f $group.Name, (Get-WriteUnsureText $Outcome.Timeout) }
        elseif ($answer.Problem) {
            $format = if ($Add) { Tr '✖ {0} : non ajouté à {1} ({2})' } else { Tr '✖ {0} : non retiré de {1} ({2})' }
            $format -f $name, $group.Name, $answer.Problem
        }
        else { $done.Add($group.Name) }
    }
    if (-not $State['Closed']) {
        if ($done.Count) { $State.NoticeAfterRead = $(if ($Add) { Tr '{0} ajouté à {1}.' } else { Tr '{0} retiré de {1}.' }) -f $name, (Join-FrenchList $done) }
        Update-ComputerDetail $State
    }
    if ($lines) { Show-Dialog -Title $(if ($Add) { Tr 'Ajouter à un groupe' } else { Tr 'Retirer du groupe' }) -Message (@($lines) -join "`n") -Owner (Get-DetailOwner $State) }
}

function Get-ComputerAsMember($Row, [string]$Group, [hashtable]$Account) {
    # As Get-UserAsMember, for a computer: the server and the member Add-ADGroupMember and Remove-ADGroupMember take.
    $server = Get-DomainOfDN $Group
    if (-not $server -or $server -eq $Row.Domain) { return $Row.Domain, [string]$Row.DistinguishedName }
    if (-not $Account['Computer']) { $Account.Computer = Get-ADComputer -Server $Row.Domain -Identity $Row.DistinguishedName -ErrorAction Stop }
    $server, $Account.Computer
}

function Get-ComputerDetailText($State) {
    # Copier: every card as text, then the groups with how the computer belongs to them.
    $sections = Get-ComputerDetailSection $State.Detail
    $lines = @("$($State.Row.Name) ($($State.Row.Domain))", '')
    foreach ($title in $sections.Keys) {
        $lines += Tr $title
        foreach ($entry in $sections[$title]) { $lines += '  ' + ((Tr '{0} : {1}') -f $entry[0], $(if ("$($entry[1])") { $entry[1] } else { '—' })) }
        $lines += ''
    }
    $lines += Tr 'Groupes'
    foreach ($group in $State.Detail.Groups) { $lines += "  $($group.Name) ($(Tr $group.Membership))" }
    $lines -join [Environment]::NewLine
}

function Get-ComputerDetailRead($State) {
    # What Start-DetailRead runs for a computer: read where its changes go (Get-UserServer, argument 1), looked up on
    # the read's runspace when it isn't known yet (Start-UserServerRead).
    @{ Command = 'Read-ComputerDetail'; Arguments = @($State.Row, $null); Domain = $State.Row.Domain; At = 1
       Functions = 'Get-ObjectGroup', 'Read-TokenGroup', 'Get-DomainOfSid', 'Get-DomainOfDN', 'Get-LdapText', 'Test-ServerDown', 'Get-DomainFallback' }
}

function Show-ComputerDetail($Computer, $Owner, $Icon) {
    # The window opens at once, « Lecture… »; the computer is read in the background. A row of the page ($Computer):
    # the window keeps a copy, and acts on the page's row while the grid lists it (Get-ComputerDetailTarget).
    $row = [pscustomobject]@{
        Name = [string]$Computer.ComputerName; Domain = [string]$Computer.Domain; DistinguishedName = [string]$Computer.DistinguishedName; Computer = $Computer.PSObject.Copy()
    }
    Show-DetailWindow @{ Row = $row; Detail = $null; Update = 'Update-ComputerDetail'; Read = 'Get-ComputerDetailRead'; CopyText = 'Get-ComputerDetailText' } `
        'computer_detail' ((Tr 'Propriétés de {0}') -f $row.Name) $Owner $Icon -Glyph 'monitor'
}
