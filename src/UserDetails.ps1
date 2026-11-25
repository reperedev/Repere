# Propriétés… of a user (the Utilisateurs page): everything about the account, in a window of its own, a card per
# subject. What can be changed there: the account's state (Activer, Désactiver…) and expiration, its password
# (Nouveau mot de passe…), its groups (added or removed), a lockout (Déverrouiller, with its details read on the
# PDC), and the values of Identité, Organisation and Profil (Modifier… in the card, #138); the login, the UPN and the
# dates stay read only. Each card folds by its header. The window, its cards, chips and lists serve a group's
# Propriétés too (GroupDetails.ps1). Dot-sourced by the main script, after Theme.ps1, GroupsDialog.ps1 (Get-ObjectGroup) and
# UserPage.ps1.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

# The dates' culture, this run's language's (Language.ps1).
$script:UserDetailCulture = Get-TextCulture

$script:UserDetailXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
           Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <!-- Also the window's title bar (Set-WindowChrome): a slim caption row with its buttons, then the user, initials in a
       circle, and chips for what calls for attention. -->
  <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
        <Image x:Name="user_detail_icon" Width="16" Height="16" Margin="0,0,10,0"/>
        <TextBlock x:Name="user_detail_caption" FontSize="12" Foreground="{DynamicResource R.Muted}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
      <StackPanel x:Name="caption_buttons" Grid.Column="1" Orientation="Horizontal"/>
      <Grid Grid.Row="1" Grid.ColumnSpan="2" Margin="28,6,28,20">
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border Width="56" Height="56" CornerRadius="28" VerticalAlignment="Top" Background="{DynamicResource R.Selection}">
          <Grid>
            <TextBlock x:Name="user_detail_initials" FontSize="20" FontWeight="{DynamicResource R.FontWeightTitle}" Foreground="{DynamicResource R.AccentText}"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Border x:Name="user_detail_glyph" Visibility="Collapsed" HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource R.AccentText}">{{icon:users:26}}</Border>
          </Grid>
        </Border>
        <StackPanel Grid.Column="1" Margin="16,0,0,0" VerticalAlignment="Center">
          <TextBlock x:Name="user_detail_title" FontSize="21" FontWeight="{DynamicResource R.FontWeightTitle}" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="user_detail_subtitle" Style="{StaticResource Txt.Muted}" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
          <ContentControl x:Name="user_detail_chips" Focusable="False"/>
        </StackPanel>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Top" Margin="16,0,0,0">
          <!-- While AD is read, in the background (Start-DetailRead). -->
          <TextBlock x:Name="user_detail_reading" Text="Lecture…" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="0,0,12,0" Visibility="Collapsed"/>
          <!-- A user's only (Show-UserDetail): their computers, by the description. -->
          <Button x:Name="user_detail_computers" Margin="0,0,8,0" Visibility="Collapsed" ToolTip="Les ordinateurs dont la description contient son nom">
            <StackPanel Orientation="Horizontal">{{icon:monitor}}<TextBlock Text="Ordinateurs" Margin="8,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="user_detail_refresh" ToolTip="Lire de nouveau (F5)">
            <StackPanel Orientation="Horizontal">{{icon:refresh}}<TextBlock Text="Actualiser" Margin="8,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="user_detail_copy" Margin="8,0,0,0" ToolTip="Tout, en texte">
            <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
          </Button>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
  <!-- Tout développer and Tout réduire, as in Caractéristiques: above the cards but outside what scrolls, so they stay
       in reach however far down the cards are scrolled (#270). They act on the cards shown (Register-DetailFoldBar). -->
  <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" HorizontalAlignment="Right" Margin="28,8,28,4">
    <StackPanel.Resources>
      <Style x:Key="Detail.Link" TargetType="Button" BasedOn="{StaticResource Btn.Ghost}">
        <Setter Property="MinHeight" Value="0"/><Setter Property="Padding" Value="8,3"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeight}"/>
        <Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource R.Muted}"/>
      </Style>
    </StackPanel.Resources>
    <Button x:Name="user_detail_expand_all" Style="{StaticResource Detail.Link}" Content="Tout développer"/>
    <Button x:Name="user_detail_collapse_all" Style="{StaticResource Detail.Link}" Content="Tout réduire"/>
  </StackPanel>
  <!-- No bottom bar: Échap or the title bar's × close the window. What a change did shows in a toast, bottom right. -->
  <Grid>
    <ScrollViewer x:Name="user_detail_scroll" VerticalScrollBarVisibility="Auto">
      <ContentControl x:Name="user_detail_body" Margin="28,0,28,16" Focusable="False"/>
    </ScrollViewer>
    <Border x:Name="user_detail_toast" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,28,20" Padding="12,9,14,9" MaxWidth="460"
            CornerRadius="10" BorderThickness="1" Background="{DynamicResource R.Surface}" BorderBrush="{DynamicResource R.BorderStrong}" Visibility="Collapsed">
      <Border.Effect><DropShadowEffect BlurRadius="20" ShadowDepth="4" Direction="270" Opacity="0.3"/></Border.Effect>
      <StackPanel Orientation="Horizontal">
        <Border Width="26" Height="26" CornerRadius="7" VerticalAlignment="Center" Background="{DynamicResource R.SuccessBg}" TextElement.Foreground="{DynamicResource R.SuccessText}">
          <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:check:14}}</Grid>
        </Border>
        <TextBlock x:Name="user_detail_status" Margin="10,0,0,0" VerticalAlignment="Center" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
  </Grid>
</DockPanel>
'@

function Get-DnName([string]$DistinguishedName) {
    # CN=Nathalie Lévy,OU=Utilisateurs,… -> Nathalie Lévy.
    if (-not $DistinguishedName) { return $null }
    ($DistinguishedName -split '(?<!\\),')[0] -replace '^\w+=', '' -replace '\\([,+"\\<>;=#])', '$1'
}

function Read-UserDetail($Row, $Known, [datetime]$Started = [datetime]::UtcNow) {
    # Everything the window shows, read in the user's domain (on a search runspace: Start-DetailRead). The lockout's
    # details (badPwdCount, the last bad password) are read on the PDC: each DC counts the bad passwords sent to it, and
    # the PDC's count is the one that locks. $Known: what $DomainCache keeps of the domain (its PDC, its password policy,
    # whether the PDC was found down), as of $Started (UTC). A PDC that doesn't answer, now or a few minutes ago
    # (Get-PdcFallback): the account read from one other DC (Get-DomainFallback; found again, once, when that one
    # doesn't answer either), and PdcProblem says why, for the lockout card; any other error on the PDC fails the read.
    # Server: where it was read, the DC the changes go to meanwhile (Get-UserServer, once Update-UserDetail keeps it).
    $domain = $Row.Domain
    $fallback = Get-PdcFallback $Known
    $pdc = if ($Known -and $Known.Pdc) { $Known.Pdc }
           elseif (-not $fallback) { try { [string](Get-ADDomain -Server $domain -ErrorAction Stop).PDCEmulator } catch { $null } }
    $properties = 'DisplayName', 'GivenName', 'Surname', 'UserPrincipalName', 'mail', 'EmployeeID', 'Title', 'Department', 'Company', 'Office', 'Manager',
                  'OfficePhone', 'MobilePhone', 'Description', 'Enabled', 'LockedOut', 'AccountLockoutTime', 'badPwdCount', 'LastBadPasswordAttempt',
                  'LastLogonDate', 'PasswordLastSet', 'PasswordExpired', 'PasswordNeverExpires', 'msDS-UserPasswordExpiryTimeComputed',
                  'AccountExpirationDate', 'whenCreated', 'whenChanged', 'HomeDirectory', 'HomeDrive', 'ProfilePath', 'ScriptPath', 'MemberOf',
                  'PrimaryGroup'
    $user, $pdcProblem, $pdcDown = $null, $null, $null
    if ($fallback) { $server, $pdcProblem, $pdcDown = $fallback, $Known.PdcProblem, $Known.PdcDown }
    elseif ($pdc) {
        try {
            $user = Get-ADUser -Server $pdc -Identity $Row.DistinguishedName -Properties $properties -ErrorAction Stop
            $server = $pdc
        }
        catch {
            if (-not (Test-ServerDown $_)) { throw }
            $server, $pdcProblem, $pdcDown = (Get-DomainFallback $domain $pdc), $_.Exception.Message, [datetime]::UtcNow
        }
    }
    else { $server = $domain }
    if ($null -eq $user) {
        try { $user = Get-ADUser -Server $server -Identity $Row.DistinguishedName -Properties $properties -ErrorAction Stop }
        catch {
            # The DC in the PDC's place doesn't answer either: another one, found once.
            if (-not $pdcDown -or $server -eq $domain -or -not (Test-ServerDown $_)) { throw }
            $other = Get-DomainFallback $domain $pdc
            if ($other -eq $server) { throw }
            $server, $pdcDown = $other, [datetime]::UtcNow
            $user = Get-ADUser -Server $server -Identity $Row.DistinguishedName -Properties $properties -ErrorAction Stop
        }
    }
    $inherited = Read-TokenGroup { Get-ADUser -Server $server -Identity $Row.DistinguishedName -Properties tokenGroups -ErrorAction Stop }
    # A PDC found by Get-UserServer comes without the policy.
    $policy = if ($Known -and $Known.Policy) { $Known.Policy } else { try { Get-ADDefaultDomainPasswordPolicy -Server $domain -ErrorAction Stop } catch { $null } }
    # By Membership, an id (Get-ObjectGroup): shown translated.
    $order = @{ Directe = 0; Principale = 1; 'Héritée' = 2 }
    @{
        Row = $Row; User = $user; Pdc = $pdc; Server = $server; PdcProblem = $pdcProblem; PdcDown = $pdcDown; Started = $Started; Policy = $policy
        Groups = @(Get-ObjectGroup $user $domain $inherited | Sort-Object { $order[$_.Membership] }, Name)
    }
}

function Get-UserDetailSection($Detail) {
    # The cards, as [ordered] title -> rows (label, value, id); a value of $null shows « — ». The titles are ids, in
    # French (Get-DetailCardXaml shows them in this run's language); the labels and values are in this run's language.
    $user = $Detail.User
    $row = $Detail.Row
    $now = Get-Date
    $state = if (-not $user.Enabled) { Tr 'Désactivé' } elseif ($user.LockedOut) { Tr 'Verrouillé' } else { Tr 'Actif' }
    $expires = $user.AccountExpirationDate
    $expiry = if (-not $expires) { Tr "N'expire jamais" }
              elseif ($expires -le $now) { (Tr 'Expiré depuis le {0}') -f (Format-TextDate $expires.AddDays(-1) -Day) }
              else {
                  # Counted to the last day, the one the window names.
                  $days = ($expires.AddDays(-1).Date - $now.Date).Days
                  $when = switch ($days) { 0 { Tr "aujourd'hui" } 1 { Tr 'demain' } default { (Tr 'dans {0} jours') -f $days } }
                  (Tr 'Fin du {0} ({1})') -f (Format-TextDate $expires.AddDays(-1) -Day), $when
              }
    # What calls for attention takes the warning's color (amber), or the danger's (red) when the account can't be used.
    $stateTone = if (-not $user.Enabled -or $user.LockedOut) { 'danger' }
    $expiryTone = if (-not $expires) { '' } elseif ($expires -le $now) { 'danger' } elseif (($expires.AddDays(-1).Date - $now.Date).Days -le 14) { 'warn' } else { '' }
    $lockout = if ($user.LockedOut) {
        if ($user.AccountLockoutTime) { (Tr 'Verrouillé depuis le {0}') -f (Format-TextDate $user.AccountLockoutTime) } else { Tr 'Verrouillé' }
    } else { Tr 'Non verrouillé' }
    $threshold = if ($Detail.Policy -and $Detail.Policy.LockoutThreshold) { [int]$Detail.Policy.LockoutThreshold }
    $bad = [int]$user.badPwdCount
    $badText = if ($threshold) { (Tr '{0} (le compte se verrouille à {1})') -f $bad, $threshold } else { "$bad" }
    $policyText = if ($threshold) {
        $duration = [timespan]$Detail.Policy.LockoutDuration
        $window = [int]([timespan]$Detail.Policy.LockoutObservationWindow).TotalMinutes
        if ($duration.TotalMinutes -gt 0) {
            (Tr '{0} mauvais mots de passe en {1} min : verrouillé {2} min') -f $threshold, $window, [int]$duration.TotalMinutes
        }
        else { (Tr '{0} mauvais mots de passe en {1} min : verrouillé jusqu''au déverrouillage manuel') -f $threshold, $window }
    } else { Tr 'Le domaine ne verrouille pas les comptes après de mauvais mots de passe.' }
    $homeFolder = if ($user.HomeDirectory) { (@($user.HomeDrive, $user.HomeDirectory | Where-Object { $_ }) -join ' → ') }
    [ordered]@{
        Compte = @(
            , @((Tr 'État'), $state, 'state', $stateTone)
            , @((Tr 'Expiration du compte'), $expiry, 'expiry', $expiryTone)
            , @((Tr 'Dernière connexion'), $(Format-TextDate $user.LastLogonDate), 'last_logon')
            , @((Tr 'Créé'), $(Format-TextDate $user.whenCreated), 'created')
            , @((Tr 'Modifié'), $(Format-TextDate $user.whenChanged), 'changed')
        )
        Verrouillage = @(
            , @((Tr 'Verrouillage'), $lockout, 'lockout', $(if ($user.LockedOut) { 'danger' }))
            , @((Tr 'Mauvais mots de passe'), $badText, 'bad_count')
            , @((Tr 'Dernier mauvais mot de passe'), $(Format-TextDate $user.LastBadPasswordAttempt), 'bad_last')
            , @((Tr 'Stratégie du domaine'), $policyText, 'policy')
        )
        'Mot de passe' = @(
            , @((Tr 'Dernier changement'), $(Format-TextDate $user.PasswordLastSet), 'password_set')
            , @((Tr 'Expiration'), $row.Password, 'password_expiry', $row.PasswordTone)
        )
        Identité = @(
            , @((Tr 'Nom complet'), $user.DisplayName, 'display_name')
            , @((Tr 'Prénom'), $user.GivenName, 'given_name')
            , @((Tr 'Nom'), $user.Surname, 'surname')
            , @((Tr 'Identifiant'), $user.SamAccountName, 'login')
            , @((Tr 'Nom principal (UPN)'), $user.UserPrincipalName, 'upn')
            , @((Tr 'Courriel'), $user.mail, 'mail')
            , @((Tr "Numéro d'employé"), $user.EmployeeID, 'employee')
        )
        Organisation = @(
            , @((Tr 'Poste'), $user.Title, 'title')
            , @((Tr 'Service'), $user.Department, 'department')
            , @((Tr 'Société'), $user.Company, 'company')
            , @((Tr 'Bureau'), $user.Office, 'office')
            , @((Tr 'Responsable'), $(Get-DnName $user.Manager), 'manager')
            , @((Tr 'Téléphone'), $user.OfficePhone, 'phone')
            , @((Tr 'Mobile'), $user.MobilePhone, 'mobile')
            , @((Tr 'Description'), $user.Description, 'description')
        )
        Profil = @(
            , @((Tr 'Dossier de base'), $homeFolder, 'home')
            , @((Tr 'Profil itinérant'), $user.ProfilePath, 'profile')
            , @((Tr "Script d'ouverture de session"), $user.ScriptPath, 'script')
        )
    }
}

function Get-UserDetailChipXaml($Detail) {
    # The header's chips: what needs attention, each in its tone. Verrouillé, désactivé, then the account's or the
    # password's expiration when it's near or past. An account that's fine has none: Compte › État says it's enabled,
    # and a chip saying so pushed the others to a second line at a large text size.
    $user = $Detail.User
    $row = $Detail.Row
    $chips = [System.Collections.Generic.List[object]]::new()
    if ($user.LockedOut) { $chips.Add(@((Tr 'Verrouillé'), 'Danger', 'lock')) }
    if (-not $user.Enabled) { $chips.Add(@((Tr 'Compte désactivé'), 'Danger', 'ban')) }
    $expires = $user.AccountExpirationDate
    if ($expires) {
        $days = ($expires.AddDays(-1).Date - (Get-Date).Date).Days
        if ($expires -le (Get-Date)) { $chips.Add(@((Tr 'Compte expiré'), 'Danger', 'calendar')) }
        elseif ($days -le 14) {
            $when = switch ($days) { 0 { Tr "Expire aujourd'hui" } 1 { Tr 'Expire demain' } default { (Tr 'Expire dans {0} jours') -f $days } }
            $chips.Add(@($when, 'Warn', 'calendar'))
        }
    }
    if ($row.PasswordTone -and $row.Password) {
        $chips.Add(@(((Tr 'Mot de passe : {0}') -f "$($row.Password.Substring(0, 1).ToLower())$($row.Password.Substring(1))"), $(if ($row.PasswordTone -eq 'danger') { 'Danger' } else { 'Warn' }), 'password'))
    }
    ConvertTo-DetailChipXaml $chips
}

function ConvertTo-DetailChipXaml($Chips) {
    # Chips, each a text, a tone (Danger, Warn, Success, or Neutral: the controls' colors) and an icon, in a row that
    # wraps.
    $x = { param($value) ConvertTo-XamlValue $value }
    $parts = foreach ($chip in $Chips) {
        $brushes = if ($chip[1] -eq 'Neutral') { 'R.Control', 'R.Border', 'R.Text' } else { "R.$($chip[1])Bg", "R.$($chip[1])Border", "R.$($chip[1])Text" }
        "<Border CornerRadius=`"12`" Height=`"24`" Padding=`"9,0,11,0`" Margin=`"0,10,8,0`" BorderThickness=`"1`" Background=`"{DynamicResource $($brushes[0])}`" BorderBrush=`"{DynamicResource $($brushes[1])}`"" +
        " TextElement.Foreground=`"{DynamicResource $($brushes[2])}`"><StackPanel Orientation=`"Horizontal`">{{icon:$($chip[2]):12}}" +
        "<TextBlock Text=`"$(& $x $chip[0])`" FontSize=`"12`" FontWeight=`"{DynamicResource R.FontWeightStrong}`" Margin=`"6,0,0,0`" VerticalAlignment=`"Center`"/></StackPanel></Border>"
    }
    Expand-Icon "<WrapPanel xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`">$($parts -join '')</WrapPanel>"
}

function Get-UserDetailXaml($Detail) {
    # The cards: Compte (with Activer or Désactiver…, and the expiration's Modifier…), Verrouillage (with Déverrouiller),
    # Mot de passe (with Nouveau mot de passe…), Groupes (with Ajouter à un groupe… and Retirer… for the direct ones
    # ticked), then Identité, Organisation and Profil, each with Modifier… (its values as text until then, and its
    # fields after, Get-UserEditXaml).
    # Each folds by its header (FoldedSections, kept in apparence.json).
    $sections = Get-UserDetailSection $Detail
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($script:DetailPanelXaml)
    $locked = [bool]$Detail.User.LockedOut
    # Activer for a disabled account, Désactiver… for an enabled one, as on the page.
    $toggle = if ($Detail.User.Enabled) {
        '<Button x:Name="user_detail_toggle" ToolTip="Désactiver le compte"><StackPanel Orientation="Horizontal">{{icon:ban:14}}<TextBlock Text="Désactiver…" Margin="8,0,0,0"/></StackPanel></Button>'
    }
    else { '<Button x:Name="user_detail_toggle" ToolTip="Activer le compte"><StackPanel Orientation="Horizontal">{{icon:checkcircle:14}}<TextBlock Text="Activer" Margin="8,0,0,0"/></StackPanel></Button>' }
    foreach ($title in $sections.Keys) {
        $action = switch ($title) {
            'Compte' {
                "<StackPanel Grid.Column=`"2`" Orientation=`"Horizontal`">$toggle" +
                '<Button x:Name="user_detail_expiry_edit" Margin="8,0,0,0" ToolTip="Changer la date d''expiration du compte"><StackPanel Orientation="Horizontal">{{icon:calendar:14}}<TextBlock Text="Modifier l''expiration…" Margin="8,0,0,0"/></StackPanel></Button></StackPanel>'
            }
            'Mot de passe' { '<Button x:Name="user_detail_reset" Grid.Column="2" ToolTip="Un mot de passe généré, celui par défaut ou un autre"><StackPanel Orientation="Horizontal">{{icon:password:14}}<TextBlock Text="Nouveau mot de passe…" Margin="8,0,0,0"/></StackPanel></Button>' }
            # Déverrouiller is the one accent button, while there's something to unlock.
            'Verrouillage' { "<Button x:Name=`"user_detail_unlock`" Grid.Column=`"2`" IsEnabled=`"$locked`"$(if ($locked) { ' Style="{StaticResource Btn.Primary}"' })><StackPanel Orientation=`"Horizontal`">{{icon:unlock:14}}<TextBlock Text=`"Déverrouiller`" Margin=`"8,0,0,0`"/></StackPanel></Button>" }
            # Modifier…, then Annuler and Enregistrer in its place while the card is edited (Show-UserCardEdit).
            { $script:UserEditFields.Contains($_) } {
                $key = $script:DetailSectionKeys[$title]
                "<StackPanel Grid.Column=`"2`" Orientation=`"Horizontal`">" +
                "<Button x:Name=`"user_edit_$key`" ToolTip=`"Modifier ces valeurs dans l'AD`"><StackPanel Orientation=`"Horizontal`">{{icon:pencil:14}}<TextBlock Text=`"Modifier…`" Margin=`"8,0,0,0`"/></StackPanel></Button>" +
                "<Button x:Name=`"user_cancel_$key`" Visibility=`"Collapsed`" Content=`"Annuler`" ToolTip=`"Annuler les modifications (Échap)`"/>" +
                "<Button x:Name=`"user_save_$key`" Visibility=`"Collapsed`" Margin=`"8,0,0,0`" Style=`"{StaticResource Btn.Primary}`" ToolTip=`"Enregistrer dans l'AD (Entrée)`">" +
                "<StackPanel Orientation=`"Horizontal`">{{icon:check:14}}<TextBlock Text=`"Enregistrer`" Margin=`"8,0,0,0`"/></StackPanel></Button></StackPanel>"
            }
        }
        # The lockout's counts are the PDC's; read elsewhere, they may differ, so the card says it, and why.
        $note, $footer = $null, $null
        if ($title -eq 'Verrouillage') {
            if ($Detail.PdcProblem) {
                $note = Tr 'non lu sur le PDC'
                $footer = (Tr "Le PDC {0} n'a pas répondu ({1}) : lu sur un autre contrôleur de domaine, dont le nombre de mauvais mots de passe peut différer.") -f $Detail.Pdc, "$(ConvertTo-FrenchError $Detail.PdcProblem)".TrimEnd('.')
            }
            elseif ($Detail.Pdc) { $note = (Tr 'lu sur {0}') -f $Detail.Pdc }
        }
        $tone = if ($title -eq 'Verrouillage' -and $locked) { 'danger' }
        $body = Get-DetailRowsXaml $sections[$title] -Copy $script:UserDetailCopy
        # A card that can be edited: its values as text (user_view_<key>), and its fields, hidden until Modifier….
        if ($script:UserEditFields.Contains($title)) {
            $body = "<StackPanel x:Name=`"user_view_$($script:DetailSectionKeys[$title])`">$body</StackPanel>$(Get-UserEditXaml $title)"
        }
        $parts.Add((Get-DetailCardXaml $title $body $action $note -Footer $footer -Tone $tone))
        # The groups after Mot de passe: what can be changed comes first.
        if ($title -eq 'Mot de passe') { $parts.Add((Get-UserGroupXaml $Detail)) }
    }
    $parts.Add('</StackPanel>')
    Expand-Icon ($parts -join "`n")
}

# The values of a user's Propriétés that have a Copier button, by id: one is often asked for alone.
$script:UserDetailCopy = 'login', 'upn', 'mail'

# The cards, a user's, a group's then a computer's (its Groupes are a user's), by title: the key each is folded by
# (FoldedSections), and its icon. A title is an id, in French (Get-DetailCardXaml shows it in this run's language);
# found by its translation too.
$script:DetailSectionKeys = @{ Compte = 'compte'; Verrouillage = 'verrouillage'; 'Mot de passe' = 'motdepasse'; Groupes = 'groupes'; Identité = 'identite'; Organisation = 'organisation'; Profil = 'profil'
                               Groupe = 'groupe'; Membres = 'membres'; 'Membre de' = 'membrede'
                               Ordinateur = 'ordinateur'; Gestion = 'gestion'; Système = 'systeme'; Connexion = 'connexion'; Sécurité = 'securite'; Objet = 'objet' }
$script:DetailSectionIcons = @{ Compte = 'user'; Verrouillage = 'lock'; 'Mot de passe' = 'password'; Groupes = 'users'; Identité = 'list'; Organisation = 'users'; Profil = 'folder'
                                Groupe = 'info'; Membres = 'users'; 'Membre de' = 'list'
                                Ordinateur = 'monitor'; Gestion = 'sliders'; Système = 'cpu'; Connexion = 'activity'; Sécurité = 'key'; Objet = 'info' }
foreach ($sectionTitle in @($script:DetailSectionKeys.Keys)) {
    $script:DetailSectionKeys[(Tr $sectionTitle)] = $script:DetailSectionKeys[$sectionTitle]
    $script:DetailSectionIcons[(Tr $sectionTitle)] = $script:DetailSectionIcons[$sectionTitle]
}

# The start of the cards' panel, with the style of a card's header: its chevron, icon and title, which fold or unfold
# the card. Tout développer and Tout réduire are the window's ($UserDetailXaml), out of what scrolls.
$script:DetailPanelXaml = @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <StackPanel.Resources>
    <Style x:Key="Toggle.Fold" TargetType="ToggleButton">
      <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="{DynamicResource R.Text}"/>
      <Setter Property="Padding" Value="8,5,10,5"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="Back" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter VerticalAlignment="Center"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Back" Property="Background" Value="{DynamicResource R.ControlHover}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </StackPanel.Resources>
'@

function Get-DetailCardXaml([string]$Title, [string]$Body, [string]$Action, [string]$Note, [string]$Count, [string]$Footer, [string]$Tone) {
    # A card: its header (the fold toggle with the chevron, the icon in its tile, the title, $Count and $Note, then
    # $Action), then $Body and $Footer, hidden while the card is folded. $Tone: 'danger' (a red border, a red tile) or
    # 'readonly' (a quiet tile, « lecture seule » at the end of the header). $Title: the card's id ($DetailSectionKeys),
    # shown in this run's language.
    $x = { param($value) ConvertTo-XamlValue $value }
    $key = $script:DetailSectionKeys[$Title]
    $shownTitle = Tr $Title
    $open = $key -notin @($script:Appearance.FoldedSections)
    $tile = switch ($Tone) {
        'danger' { 'R.DangerBg', 'R.DangerText' }
        'readonly' { 'R.Control', 'R.Muted' }
        default { 'R.Control', 'R.AccentText' }
    }
    $border = if ($Tone -eq 'danger') { ' BorderBrush="{DynamicResource R.DangerBorder}"' }
    $noteXaml = if ($Note) { "<TextBlock Style=`"{StaticResource Txt.Muted}`" FontSize=`"12`" VerticalAlignment=`"Center`" Margin=`"10,0,0,0`" Text=`"$(& $x $Note)`"/>" }
    $countXaml = if ($Count) {
        "<Border CornerRadius=`"10`" Padding=`"8,1`" Margin=`"8,0,0,0`" VerticalAlignment=`"Center`" Background=`"{DynamicResource R.Control}`">" +
        "<TextBlock Text=`"$(& $x $Count)`" Style=`"{StaticResource Txt.Muted}`" FontSize=`"12`" FontWeight=`"{DynamicResource R.FontWeightStrong}`"/></Border>"
    }
    $readOnly = if ($Tone -eq 'readonly') {
        "<StackPanel Grid.Column=`"1`" Orientation=`"Horizontal`" HorizontalAlignment=`"Right`" VerticalAlignment=`"Center`" Margin=`"0,0,12,0`" IsHitTestVisible=`"False`" TextElement.Foreground=`"{DynamicResource R.Muted}`">" +
        "{{icon:lock:12}}<TextBlock Text=`"lecture seule`" FontSize=`"12`" Margin=`"6,0,0,0`"/></StackPanel>"
    }
    $footerXaml = if ($Footer) { "<TextBlock Style=`"{StaticResource Txt.Muted}`" FontSize=`"12`" Margin=`"14,4,14,6`" TextWrapping=`"Wrap`" Text=`"$(& $x $Footer)`"/>" }
    @"
  <Border Style="{StaticResource Card}" CornerRadius="10" Margin="0,0,0,8"$border>
    <StackPanel>
      <Grid Margin="6,3,8,3">
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <!-- The whole header folds the card, up to its actions (as in Caractéristiques); « lecture seule » lets clicks through. -->
        <ToggleButton x:Name="user_section_$key" Grid.ColumnSpan="2" Margin="0,0,8,0" Style="{StaticResource Toggle.Fold}" IsChecked="$open" MinHeight="34" ToolTip="Replier ou déplier" AutomationProperties.Name="$(& $x $shownTitle)">
          <StackPanel Orientation="Horizontal">
            <Border x:Name="user_section_chevron_$key" TextElement.Foreground="{DynamicResource R.Muted}" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
              <Border.RenderTransform><RotateTransform Angle="$(if ($open) { 0 } else { -90 })"/></Border.RenderTransform>
              {{icon:chevron:12}}
            </Border>
            <Border Width="28" Height="28" CornerRadius="7" Margin="10,0,0,0" VerticalAlignment="Center" Background="{DynamicResource $($tile[0])}" TextElement.Foreground="{DynamicResource $($tile[1])}">
              <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:$($script:DetailSectionIcons[$Title]):16}}</Grid>
            </Border>
            <TextBlock Text="$(& $x $shownTitle)" FontSize="14" FontWeight="{DynamicResource R.FontWeightStrong}" Margin="10,0,0,0" VerticalAlignment="Center"/>
            $countXaml
            $noteXaml
          </StackPanel>
        </ToggleButton>
        $readOnly
        $Action
      </Grid>
      <!-- The card's content in a panel of its own, a shade apart from the header (the window's background). -->
      <Border x:Name="user_section_body_$key" Visibility="$(if ($open) { 'Visible' } else { 'Collapsed' })" Margin="8,0,8,6" Padding="0,6,0,2"
              CornerRadius="8" Background="{DynamicResource R.Bg}" BorderBrush="{DynamicResource R.Border}" BorderThickness="1">
        <StackPanel>
$Body
$footerXaml
        </StackPanel>
      </Border>
    </StackPanel>
  </Border>
"@
}

function Get-DetailRowsXaml($Rows, [string]$Prefix = 'user_detail', [string[]]$Copy = @()) {
    # A label and its value per row (the value named $Prefix_<id>); a missing value is a faint « — », one that calls
    # for attention amber or red. The ids in $Copy, when they have a value, have a small Copier button after it
    # ($Prefix_copy_<id>; Register-DetailCopy wires it, and a right-click on the value).
    $x = { param($value) ConvertTo-XamlValue $value }
    $lines = for ($i = 0; $i -lt $Rows.Count; $i++) {
        $entry = $Rows[$i]
        $missing = $null -eq $entry[1] -or "$($entry[1])" -eq ''
        $value = if ($missing) { '—' } else { [string]$entry[1] }
        # Its tone, the fourth element, when it has one.
        $tone = if ($entry.Count -gt 3) { $entry[3] }
        $color = if ($missing) { ' Style="{StaticResource Txt.Faint}"' }
                 elseif ($tone -eq 'warn') { ' Foreground="{DynamicResource R.WarnText}"' }
                 elseif ($tone -eq 'danger') { ' Foreground="{DynamicResource R.DangerText}"' }
        $label = "<TextBlock Grid.Row=`"$i`" Style=`"{StaticResource Txt.Muted}`" Text=`"$(& $x $entry[0])`" Margin=`"0,0,12,4`"/>"
        if ($missing -or $Copy -notcontains $entry[2]) {
            $label + "<TextBlock x:Name=`"$($Prefix)_$($entry[2])`" Grid.Row=`"$i`" Grid.Column=`"1`" Text=`"$(& $x $value)`" TextWrapping=`"Wrap`" Margin=`"0,0,0,4`"$color/>"
            continue
        }
        # The button's margins keep the row as high as the others.
        $copyName = (Tr 'Copier {0}') -f $entry[0]
        $label + "<StackPanel Grid.Row=`"$i`" Grid.Column=`"1`" Orientation=`"Horizontal`" Margin=`"0,0,0,4`">" +
        "<TextBlock x:Name=`"$($Prefix)_$($entry[2])`" Text=`"$(& $x $value)`" VerticalAlignment=`"Center`"$color/>" +
        "<Button x:Name=`"$($Prefix)_copy_$($entry[2])`" Style=`"{StaticResource Btn.Mini}`" Margin=`"6,-4,0,-4`" VerticalAlignment=`"Center`" ToolTip=`"Copier`"" +
        " AutomationProperties.Name=`"$(& $x $copyName)`">{{icon:copy:14}}</Button></StackPanel>"
    }
    $definitions = '<RowDefinition Height="Auto"/>' * $Rows.Count
    "      <Grid Margin=`"14,0,14,2`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"210`"/><ColumnDefinition Width=`"*`"/></Grid.ColumnDefinitions><Grid.RowDefinitions>$definitions</Grid.RowDefinitions>$($lines -join '')</Grid>"
}

function Get-UserGroupXaml($Detail) {
    # Groupes: each group, how the user belongs to it (Directe, Principale, Héritée through another group), its type and
    # description. The direct ones have a box to tick: Retirer… takes the user out of those ticked. Comparer avec…
    # (another user's groups, GroupCompare.ps1) and Ajouter à un groupe… in the header. A long list has a box to find
    # a group by its name or its detail (#322), in the groups read: no search of AD.
    # Membership is an id, in French: shown translated. Only a group that was read has a box (#249): a row that says
    # why groups couldn't be (Get-ObjectGroup) has no type, and Retirer… would fail on it; « groupes de ce domaine non
    # lus » has a domain's name for its DN.
    $items = foreach ($group in $Detail.Groups) {
        $kind = @($group.Type, $group.Scope, $(if ($group.Domain -ne $Detail.Row.Domain) { $group.Domain })) | Where-Object { $_ }
        $membership = Tr $group.Membership
        @{
            Name = $group.Name; Badge = $membership; CanPick = $group.Membership -eq 'Directe' -and [bool]$group.Type; Automation = "$($group.Name) | $membership"
            Target = if ($group.Type) { $group }
            Detail = (@($kind -join ', ') + @($group.Description | Where-Object { $_ })) -join ' · '
            Tone = switch ($group.Membership) { 'Directe' { 'accent' } 'Principale' { 'neutral' } default { 'outline' } }
        }
    }
    $rows = Get-DetailListXaml @($items) 'user_group' (Tr 'À retirer') -FilterTip (Tr 'Filtrer les groupes') -NoMatch (Tr 'Aucun groupe.')
    $action = @'
<StackPanel Grid.Column="2" Orientation="Horizontal">
  <Button x:Name="user_group_remove" IsEnabled="False" ToolTip="Retirer des groupes directs cochés">
    <StackPanel Orientation="Horizontal">{{icon:trash:14}}<TextBlock x:Name="user_group_remove_label" Text="Retirer…" Margin="8,0,0,0"/></StackPanel>
  </Button>
  <Button x:Name="user_group_compare" Margin="8,0,0,0" ToolTip="Ses groupes et ceux d'un autre utilisateur, côte à côte">
    <StackPanel Orientation="Horizontal">{{icon:columns:14}}<TextBlock Text="Comparer avec…" Margin="8,0,0,0"/></StackPanel>
  </Button>
  <Button x:Name="user_group_add" Margin="8,0,0,0"><StackPanel Orientation="Horizontal">{{icon:plus:14}}<TextBlock Text="Ajouter à un groupe…" Margin="8,0,0,0"/></StackPanel></Button>
</StackPanel>
'@
    # The rows closer to the panel's edge than the other cards' text.
    Get-DetailCardXaml 'Groupes' $rows $action -Count $Detail.Groups.Count `
        -Footer (Tr 'Prend effet à la prochaine ouverture de session.')
}

# The fewest items a list has for Get-DetailListXaml to give it a box to filter it: a shorter one is read at a glance.
$script:DetailFilterMin = 11

function Get-DetailListXaml($Items, [string]$Prefix, [string]$PickTip, [string]$FilterTip, [string]$NoMatch) {
    # A card's list: per item, its Name (named $Prefix_<i>, read by UI Automation as its Automation text), its Detail
    # (muted, on the right) and a Badge in its Tone (accent, neutral or outline). An item that CanPick has a box
    # ($Prefix_pick_<i>); ticked, its row takes the selection's color. An item that is a group or a user (Target) has a
    # button to open its Propriétés ($Prefix_open_<i>; Register-DetailOpen wires it, and the row's right-click and
    # double-click).
    # Given a $FilterTip, a list of $DetailFilterMin items or more starts with a box to filter it ($Prefix_filter, the
    # tip its placeholder; Register-DetailFilter wires it), and ends with $NoMatch ($Prefix_filter_none), hidden until
    # the box matches no row. Each row's Tag holds its name and detail, what the box matches.
    # The rows sit closer to the panel's edge than the other cards' text.
    $x = { param($value) ConvertTo-XamlValue $value }
    $filter = $FilterTip -and $Items.Count -ge $script:DetailFilterMin
    $rows = for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        # The badge, a label rather than a button (#199): filled for a direct membership or a group's type, outlined and
        # muted otherwise. Its word says which, not its color.
        $badge = if ($item.Tone -in 'accent', 'neutral') { 'Badge' } else { 'Badge.Quiet' }
        # By key: a read-only list's items (Membre de) have no CanPick.
        $pick, $style = if ($item['CanPick']) {
            "<CheckBox x:Name=`"$($Prefix)_pick_$i`" VerticalAlignment=`"Center`" ToolTip=`"$(& $x $PickTip)`" AutomationProperties.Name=`"$(& $x ((Tr 'Choisir {0}') -f $item.Name))`"/>"
            "<Border.Style><Style TargetType=`"Border`"><Setter Property=`"Background`" Value=`"Transparent`"/><Style.Triggers>" +
            "<DataTrigger Binding=`"{Binding IsChecked, ElementName=$($Prefix)_pick_$i}`" Value=`"True`"><Setter Property=`"Background`" Value=`"{DynamicResource R.Selection}`"/></DataTrigger>" +
            "</Style.Triggers></Style></Border.Style>"
        }
        $open = if ($item.Target) {
            $openTip = (Tr 'Propriétés de {0} (ou double-clic)') -f $item.Name
            $openName = (Tr 'Propriétés de {0}') -f $item.Name
            "<Button x:Name=`"$($Prefix)_open_$i`" Grid.Column=`"4`" Style=`"{StaticResource Btn.Mini}`" Margin=`"6,0,0,0`" VerticalAlignment=`"Center`"" +
            " ToolTip=`"$(& $x $openTip)`" AutomationProperties.Name=`"$(& $x $openName)`">{{icon:open:14}}</Button>"
        }
        @"
      <Border x:Name="$($Prefix)_row_$i" Tag="$(& $x "$($item.Name) $($item.Detail)")" BorderBrush="{DynamicResource R.Border}" BorderThickness="$(if ($i) { '0,1,0,0' } else { '0' })" CornerRadius="6" Margin="4,0" Padding="10,0" MinHeight="36">
        $style
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          $pick
          <TextBlock x:Name="$($Prefix)_$i" Grid.Column="1" Text="$(& $x $item.Name)" VerticalAlignment="Center" AutomationProperties.Name="$(& $x $item.Automation)"/>
          <TextBlock Grid.Column="2" Style="{StaticResource Txt.Muted}" FontSize="12" Margin="16,0,12,0" HorizontalAlignment="Right" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"
                     Text="$(& $x $item.Detail)"/>
          <!-- Sized to its word, in a column as wide on every row, so the buttons after it line up. -->
          <Border Grid.Column="3" Width="84">
            <Border Style="{StaticResource $badge}" HorizontalAlignment="Right"><TextBlock Text="$(& $x $item.Badge)"/></Border>
          </Border>
          $open
        </Grid>
      </Border>
"@
    }
    $list = "<StackPanel Margin=`"0,-4,0,0`">$($rows -join "`n")</StackPanel>"
    if (-not $filter) { return $list }
    # The box as Membres has its search, its icon a filter's: it hides rows here, rather than asking AD.
    @"
      <Border Style="{StaticResource Field}" Height="34" Margin="12,0,12,8">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
          <TextBox x:Name="$($Prefix)_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="$(& $x $FilterTip)" AutomationProperties.Name="$(& $x $FilterTip)"/>
        </Grid>
      </Border>
$list
      <TextBlock x:Name="$($Prefix)_filter_none" Visibility="Collapsed" Style="{StaticResource Txt.Muted}" Margin="14,0,14,8" Text="$(& $x $NoMatch)"/>
"@
}

function Test-DetailFilterMatch([string]$Text, [string]$Filter) {
    # Whether $Text holds what was typed in a list's box ($Filter), whatever the case and the accents: « metal » finds
    # Atelier-Métal, as one types without them. An empty box matches every row.
    $Filter = $Filter.Trim()
    if (-not $Filter) { return $true }
    $options = [System.Globalization.CompareOptions]::IgnoreCase -bor [System.Globalization.CompareOptions]::IgnoreNonSpace
    [System.Globalization.CultureInfo]::InvariantCulture.CompareInfo.IndexOf($Text, $Filter, $options) -ge 0
}

function Register-DetailFilter($Root, [string]$Prefix, $State) {
    # The box of a list that has one (Get-DetailListXaml), as it's typed into: the rows it doesn't match are hidden,
    # not built again, so a box ticked stays ticked, and counted by Retirer (n)…, while its row is hidden. Échap clears
    # it; empty, Échap goes on to the window (which closes). What it holds is kept in $State, for the cards built again
    # (a Retirer…, F5).
    $box = $Root.FindName("$($Prefix)_filter")
    if (-not $box) { return }
    $box.Text = [string]$State["$($Prefix)_filter"]
    Update-DetailFilter $box
    $box.Add_TextChanged({
        param($control)
        [System.Windows.Window]::GetWindow($control).Tag["$($control.Name)"] = $control.Text
        Update-DetailFilter $control
    })
    $box.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape -and $control.Text) { $e.Handled = $true; $control.Clear() }
    })
}

function Update-DetailFilter($Box) {
    # The rows its text matches shown, the others hidden; the first one shown without the line above it, as the
    # list's first row. The list's line for no match ($Prefix_filter_none) when none is.
    $prefix = $Box.Name -replace '_filter$'
    $shown = 0
    for ($i = 0; ($row = $Box.FindName("$($prefix)_row_$i")); $i++) {
        $match = Test-DetailFilterMatch ([string]$row.Tag) $Box.Text
        $row.Visibility = if ($match) { 'Visible' } else { 'Collapsed' }
        if (-not $match) { continue }
        $row.BorderThickness = [System.Windows.Thickness]::new(0, $(if ($shown) { 1 } else { 0 }), 0, 0)
        $shown++
    }
    $Box.FindName("$($prefix)_filter_none").Visibility = if ($shown) { 'Collapsed' } else { 'Visible' }
}

function Register-DetailOpen($Root, [string]$Prefix, $Targets) {
    # The groups and users of a card's list ($Targets, in its order: each with a Name, DistinguishedName and Domain,
    # and Kind « Utilisateur » for a user; $null for an item that doesn't open): their button, a right-click on their row
    # (Propriétés…) and a double-click open them.
    for ($i = 0; $i -lt @($Targets).Count; $i++) {
        $target = @($Targets)[$i]
        $button = $Root.FindName("$($Prefix)_open_$i")
        if (-not $target -or -not $button) { continue }
        $button.CommandParameter = $target
        $button.Add_Click({ param($control) Open-DetailTarget $control })
        $row = $Root.FindName("$($Prefix)_row_$i")
        $row.Tag = $target
        $menu = [System.Windows.Controls.ContextMenu]::new()
        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = Tr 'Propriétés…'
        $item.Tag = $target
        $item.Add_Click({ param($control) Open-DetailTarget $control })
        $null = $menu.Items.Add($item)
        $row.ContextMenu = $menu
        # A double-click on a box ticks it twice, and stays there.
        $row.Add_MouseLeftButtonDown({ param($control, $e) if ($e.ClickCount -eq 2) { $e.Handled = $true; Open-DetailTarget $control } })
    }
}

function Open-DetailTarget($Control) {
    # Propriétés of a group or a user listed in a window's card, in a window of its own (Show-DetailWindow); the window
    # it was opened from reads itself again once that one closes (the other window may have changed a membership). A
    # menu item finds its window through the row it opened on. A user is read first, as the Utilisateurs page reads its
    # rows.
    $anchor = if ($Control -is [System.Windows.Controls.MenuItem]) { $Control.Parent.PlacementTarget } else { $Control }
    $window = [System.Windows.Window]::GetWindow($anchor)
    $target = if ($Control -is [System.Windows.Controls.Button]) { $Control.CommandParameter } else { $Control.Tag }
    # A member has a Kind (an id, in French); a group of Membre de or of a user's Groupes (Get-ObjectGroup) has none.
    $kind = $target.PSObject.Properties['Kind']
    # While a user is read, the window waits: another click, on a user or a group, is ignored.
    if ($window.Cursor -eq [System.Windows.Input.Cursors]::Wait) { return }
    if ($kind -and $kind.Value -eq 'Utilisateur') {
        # Already open, or no room for it: not read for nothing.
        if (Show-OpenDetailWindow (Get-DetailWindowKey 'user_detail' $target)) { return }
        if (-not (Test-DetailWindowRoom ([string]$target.Name) $window)) { return }
        # Read in the background, the window waiting meanwhile.
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        $filter = "(&(objectCategory=person)(objectClass=user)(distinguishedName=$(Get-LdapText ([string]$target.DistinguishedName))))"
        try {
            Start-UserRowRead $filter @([string]$target.Domain) -Context @{ Window = $window; Target = $target } -OnDone {
                param($context, $row, $problem)
                $window = $context.Window
                $window.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
                # Closed meanwhile: nothing to open from.
                if (-not $window.IsVisible) { return }
                if (-not $row) {
                    $why = if ($problem) { $problem } else { (Tr 'introuvable dans {0}') -f $context.Target.Domain }
                    Show-Dialog -Title (Tr 'Propriétés') -Message ((Tr '✖ {0} : propriétés non lues ({1})') -f $context.Target.Name, $why) -Owner $window
                    return
                }
                Show-UserDetail $row $window $window.Icon
            }
        }
        catch {
            # Not started: the window doesn't wait for it.
            $window.ClearValue([System.Windows.FrameworkElement]::CursorProperty)
            Show-Dialog -Title (Tr 'Propriétés') -Message ((Tr '✖ {0} : propriétés non lues ({1})') -f $target.Name, $_.Exception.Message) -Owner $window
        }
        return
    }
    $row = [pscustomobject]@{ Name = [string]$target.Name; Domain = [string]$target.Domain; DistinguishedName = [string]$target.DistinguishedName; OUPath = Get-OUPath ([string]$target.DistinguishedName) }
    Show-GroupDetail $row $window $window.Icon
}

function Show-DetailNotice($State, [string]$Text) {
    # What a change did, in a toast over the window's bottom right corner for a few seconds; AD's English errors in
    # French.
    $State.Status.Text = ConvertTo-FrenchError $Text
    $toast = $State.Toast
    $toast.Visibility = 'Visible'
    $duration = [System.Windows.Duration]::new([timespan]::FromMilliseconds(180))
    $toast.BeginAnimation([System.Windows.UIElement]::OpacityProperty, [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, $duration))
    $State.ToastTimer.Stop()
    $State.ToastTimer.Start()
}

function Update-UserDetail($State, $Detail) {
    # Reads the user again in the background (Start-DetailRead), unless $Detail was just read: then rebuilds the cards,
    # and the row of the Utilisateurs page follows, when it still shows that user (Sync-UserPageRow).
    if (-not $Detail) { Start-DetailRead $State; return }
    $State.Detail = $Detail
    Update-DomainCache $State.Row.Domain $Detail
    $user = $State.Detail.User
    $row = $State.Row
    $row.IsLocked = [bool]$user.LockedOut
    $row.IsEnabled = [bool]$user.Enabled
    $row.State = if (-not $user.Enabled) { Tr 'Désactivé' } elseif ($user.LockedOut) { Tr 'Verrouillé' } else { Tr 'Actif' }
    # Mot de passe as just read, as a search shows it: the window's copy of the row would be the page's old one (a
    # Nouveau mot de passe… there meanwhile).
    $password = Get-UserPasswordState $user (Get-Date).Date (Get-UserPasswordText)
    foreach ($name in $password.Keys) { $row.$name = $password[$name] }
    $row.PasswordNeverExpires = [bool]$user.PasswordNeverExpires
    # What Identité and Organisation may have changed (#138), as the page's search makes its rows.
    $row.Name = if ($user.DisplayName) { [string]$user.DisplayName } else { [string]$user.Name }
    $row.Title = [string]$user.Title
    $row.Department = [string]$user.Department
    $row.Description = [string]$user.Description
    $row.Mail = [string]$user.mail
    $row.Text = "$($row.Name) $($row.Login) $($row.Title) $($row.Department) $($row.Description) $($row.Mail) $($row.OUPath)".ToLowerInvariant()
    Sync-UserPageRow $row
    $State.Title.Text = $row.Name
    $State.Subtitle.Text = "$($row.Login) · $($row.Domain) · $($row.OUPath)"
    # JT for Julie Bertrand: the first letters of the given name and surname, else of the name's first two words.
    $words = @(@($user.GivenName, $user.Surname) | Where-Object { $_ })
    if ($words.Count -lt 2) { $words = @("$($row.Name)" -split '\s+' | Where-Object { $_ } | Select-Object -First 2) }
    $State.Initials.Text = (-join ($words | ForEach-Object { $_.Substring(0, 1) })).ToUpper()
    $State.Chips.Content = [System.Windows.Markup.XamlReader]::Parse((Get-UserDetailChipXaml $State.Detail))
    # What is being typed in a card, kept across the cards built again (Register-UserEdit puts it back).
    Read-UserCardEdit $State
    $body = [System.Windows.Markup.XamlReader]::Parse((Get-UserDetailXaml $State.Detail))
    $State.Body.Content = $body
    $body.FindName('user_detail_expiry_edit').Add_Click({ param($button) Show-UserExpiryDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('user_detail_toggle').Add_Click({ param($button) Invoke-UserDetailToggle ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('user_detail_reset').Add_Click({
        param($button)
        $state = [System.Windows.Window]::GetWindow($button).Tag
        Show-UserResetDialog $state.Row $state.Window $state
    })
    $body.FindName('user_detail_unlock').Add_Click({ param($button) Invoke-UserDetailUnlock ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('user_group_add').Add_Click({ param($button) Show-UserGroupAddDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('user_group_compare').Add_Click({ param($button) Show-UserCompareDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $body.FindName('user_group_remove').Add_Click({ param($button) Remove-UserGroup ([System.Windows.Window]::GetWindow($button).Tag) })
    $State.Picks = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $State.Detail.Groups.Count; $i++) {
        $pick = $body.FindName("user_group_pick_$i")
        if (-not $pick) { continue }
        $pick.Tag = $State.Detail.Groups[$i]
        $State.Picks.Add($pick)
        $pick.Add_Checked({ param($box) Update-UserGroupPick ([System.Windows.Window]::GetWindow($box).Tag) })
        $pick.Add_Unchecked({ param($box) Update-UserGroupPick ([System.Windows.Window]::GetWindow($box).Tag) })
    }
    Register-DetailOpen $body 'user_group' $State.Detail.Groups
    Register-DetailFilter $body 'user_group' $State
    Register-DetailSection $body
    Register-DetailCopy $body (Get-UserDetailSection $State.Detail) $script:UserDetailCopy
    Register-UserEdit $State $body
}

# The values Modifier… changes in Identité, Organisation and Profil (#138), by card, in the order its fields show: per
# field, its id (its value user_detail_<id>, its box user_field_<id>), its label (in this run's language), the LDAP
# attribute Set-ADUser's -Replace and -Clear take, the property Read-UserDetail reads it as, and the most
# characters AD takes (the schema's rangeUpper). Kind: Mail, Manager (a user's DN, picked by a search:
# Show-UserManagerDialog), Drive (a letter), Home (a network path, or a local one without a drive), Unc (a network
# path), Path (the logon script: relative to NETLOGON, or a full path); in Home and Unc, %username% is the login, as
# Utilisateurs et ordinateurs Active Directory has it. A field without an attribute is shown, never changed: the login
# and the UPN (renaming is another, rarer action). A card's id is in French, as Get-UserDetailSection's.
$script:UserEditFields = [ordered]@{
    Identité = @(
        @{ Id = 'display_name'; Label = (Tr 'Nom complet'); Attribute = 'displayName'; Property = 'DisplayName'; Max = 256 }
        @{ Id = 'given_name'; Label = (Tr 'Prénom'); Attribute = 'givenName'; Property = 'GivenName'; Max = 64 }
        @{ Id = 'surname'; Label = (Tr 'Nom'); Attribute = 'sn'; Property = 'Surname'; Max = 64 }
        @{ Id = 'login'; Label = (Tr 'Identifiant'); Property = 'SamAccountName' }
        @{ Id = 'upn'; Label = (Tr 'Nom principal (UPN)'); Property = 'UserPrincipalName' }
        @{ Id = 'mail'; Label = (Tr 'Courriel'); Attribute = 'mail'; Property = 'mail'; Max = 256; Kind = 'Mail' }
        @{ Id = 'employee'; Label = (Tr "Numéro d'employé"); Attribute = 'employeeID'; Property = 'EmployeeID'; Max = 16 }
    )
    Organisation = @(
        @{ Id = 'title'; Label = (Tr 'Poste'); Attribute = 'title'; Property = 'Title'; Max = 128 }
        @{ Id = 'department'; Label = (Tr 'Service'); Attribute = 'department'; Property = 'Department'; Max = 64 }
        @{ Id = 'company'; Label = (Tr 'Société'); Attribute = 'company'; Property = 'Company'; Max = 64 }
        @{ Id = 'office'; Label = (Tr 'Bureau'); Attribute = 'physicalDeliveryOfficeName'; Property = 'Office'; Max = 128 }
        @{ Id = 'manager'; Label = (Tr 'Responsable'); Attribute = 'manager'; Property = 'Manager'; Kind = 'Manager' }
        @{ Id = 'phone'; Label = (Tr 'Téléphone'); Attribute = 'telephoneNumber'; Property = 'OfficePhone'; Max = 64 }
        @{ Id = 'mobile'; Label = (Tr 'Mobile'); Attribute = 'mobile'; Property = 'MobilePhone'; Max = 64 }
        @{ Id = 'description'; Label = (Tr 'Description'); Attribute = 'description'; Property = 'Description'; Max = 1024 }
    )
    Profil = @(
        @{ Id = 'home_drive'; Label = (Tr 'Lecteur'); Attribute = 'homeDrive'; Property = 'HomeDrive'; Kind = 'Drive' }
        @{ Id = 'home'; Label = (Tr 'Dossier de base'); Attribute = 'homeDirectory'; Property = 'HomeDirectory'; Kind = 'Home' }
        @{ Id = 'profile'; Label = (Tr 'Profil itinérant'); Attribute = 'profilePath'; Property = 'ProfilePath'; Kind = 'Unc' }
        @{ Id = 'script'; Label = (Tr "Script d'ouverture de session"); Attribute = 'scriptPath'; Property = 'ScriptPath'; Kind = 'Path' }
    )
}
# A field's card, by the field's id: for Entrée in its box.
$script:UserEditFieldCard = @{}
foreach ($editCard in $script:UserEditFields.Keys) { foreach ($editField in $script:UserEditFields[$editCard]) { $script:UserEditFieldCard[$editField.Id] = $editCard } }

# A network path: \\server\share, then folders.
$script:UncPattern = '^\\\\[^\\/:*?"<>|\s]+\\[^\\/:*?"<>|]+(\\[^\\/:*?"<>|]*)*$'

function Get-UserEditValue($User, $Field) {
    # A field's value as AD has it, as text: '' for none.
    $property = $User.PSObject.Properties[$Field.Property]
    if ($property -and $null -ne $property.Value) { [string]$property.Value } else { '' }
}

function Get-UserEditChange([string]$Card, $User, [hashtable]$Values, [string]$Login) {
    # What Enregistrer sends for a card: each field whose value as typed ($Values, by id; trimmed) differs from AD's
    # ($User), in Replace (attribute -> value) or, emptied, in Clear; Fields, those fields (Id, Label, Attribute), in the
    # card's order. Problems: each value AD would refuse or Windows couldn't use, « Label : why » with its field's Id,
    # checked on the fields changed only, so a value AD already has never holds the others back. The drive and the home
    # folder are checked together when either changed: a drive maps a network path.
    $replace = @{}
    $clear = [System.Collections.Generic.List[string]]::new()
    $fields = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[object]]::new()
    $typed = @{}
    foreach ($field in $script:UserEditFields[$Card]) {
        if (-not $field['Attribute']) { continue }
        $value = "$($Values[$field.Id])".Trim()
        if ($field['Kind'] -eq 'Drive' -and $value -match '^([A-Za-z]):?$') { $value = "$($Matches[1].ToUpperInvariant()):" }
        if ($field['Kind'] -in 'Home', 'Unc') { $value = [regex]::Replace($value, '%username%', $Login.Replace('$', '$$'), 'IgnoreCase') }
        $typed[$field.Id] = $value
    }
    $add = { param($Entry, [string]$Why) $problems.Add(@{ Id = $Entry.Id; Text = ((Tr '{0} : {1}') -f $Entry.Label, $Why) }) }
    $driveChanged = $false
    foreach ($field in $script:UserEditFields[$Card]) {
        if (-not $field['Attribute']) { continue }
        $value = $typed[$field.Id]
        $current = Get-UserEditValue $User $field
        # A DN's case is AD's to keep; any other value, as typed.
        $same = if ($field['Kind'] -eq 'Manager') { $value -eq $current } else { $value -ceq $current }
        if ($same) { continue }
        $fields.Add(@{ Id = $field.Id; Label = $field.Label; Attribute = $field.Attribute })
        if ($value) { $replace[$field.Attribute] = $value } else { $clear.Add($field.Attribute) }
        if ($field['Kind'] -in 'Drive', 'Home') { $driveChanged = $true }
        if (-not $value) { continue }
        if ($field['Max'] -and $value.Length -gt $field.Max) { & $add $field ((Tr '{0} caractères au plus (il y en a {1}).') -f $field.Max, $value.Length); continue }
        switch ($field['Kind']) {
            'Mail' { if ($value -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { & $add $field (Tr 'adresse invalide (ex. prenom.nom@domaine.com).') } }
            'Drive' { if ($value -notmatch '^[A-Z]:$') { & $add $field (Tr 'une lettre de A à Z (ex. H:).') } }
            'Unc' { if ($value -notmatch $script:UncPattern) { & $add $field (Tr 'un chemin réseau, \\serveur\partage\…') } }
            'Path' { if ($value -match '[*?"<>|]') { & $add $field (Tr 'caractères interdits dans un chemin (* ? " < > |).') } }
        }
    }
    if ($driveChanged) {
        $driveField, $homeField = @($script:UserEditFields.Profil | Where-Object { $_.Id -in 'home_drive', 'home' })
        $drive, $folder = $typed['home_drive'], $typed['home']
        if ($drive -match '^[A-Z]:$' -and -not $folder) { & $add $driveField (Tr 'un lecteur demande un dossier de base.') }
        elseif ($drive -match '^[A-Z]:$' -and $folder -notmatch $script:UncPattern) { & $add $homeField (Tr 'avec un lecteur, un chemin réseau, \\serveur\partage\…') }
        elseif (-not $drive -and $folder -and $folder -notmatch $script:UncPattern -and $folder -notmatch '^[A-Za-z]:\\[^/:*?"<>|]*$') {
            & $add $homeField (Tr 'un chemin réseau, \\serveur\partage\…, ou local, C:\…')
        }
    }
    @{ Replace = $replace; Clear = @($clear); Fields = @($fields); Problems = @($problems) }
}

function Save-UserEditChange($Row, $Change) {
    # Enregistrer, on a search runspace (Save-UserCard): a card's changes (Get-UserEditChange) in one Set-ADUser, on the
    # DC the window reads from (Invoke-UserChange). AD writes a Set-ADUser whole or not at all: when it refuses one
    # (rights on one attribute, a value out of range), each field is sent alone, so those AD takes are saved and those
    # it refuses named. Saved: the ids written; Failed: each field refused, with its Id, Label and Problem. A DC that
    # doesn't answer (Invoke-UserChange has tried another already): nothing saved, each field failed for it.
    $whole = @{}
    if ($Change.Replace.Count) { $whole.Replace = $Change.Replace }
    if ($Change.Clear.Count) { $whole.Clear = [string[]]$Change.Clear }
    $ids = @($Change.Fields | ForEach-Object { $_.Id })
    try {
        $null = Invoke-UserChange $Row.Domain { param($server) Set-ADUser -Server $server -Identity $Row.DistinguishedName @whole -ErrorAction Stop }
        return @{ Saved = $ids; Failed = @() }
    }
    catch {
        if ((Test-ServerDown $_) -or $ids.Count -eq 1) {
            $problem = $_.Exception.Message
            return @{ Saved = @(); Failed = @($Change.Fields | ForEach-Object { @{ Id = $_.Id; Label = $_.Label; Problem = $problem } }) }
        }
    }
    $saved = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()
    foreach ($field in $Change.Fields) {
        $one = if ($Change.Clear -contains $field.Attribute) { @{ Clear = [string[]]@($field.Attribute) } } else { @{ Replace = @{ $field.Attribute = $Change.Replace[$field.Attribute] } } }
        try {
            $null = Invoke-UserChange $Row.Domain { param($server) Set-ADUser -Server $server -Identity $Row.DistinguishedName @one -ErrorAction Stop }
            $saved.Add($field.Id)
        }
        catch { $failed.Add(@{ Id = $field.Id; Label = $field.Label; Problem = $_.Exception.Message }) }
    }
    @{ Saved = @($saved); Failed = @($failed) }
}

function Get-UserEditXaml([string]$Card) {
    # A card's fields, hidden until Modifier… (user_form_<key>): its error first (user_edit_error_<key>), then a label and
    # a box per field (user_field_<id>), the login and the UPN as text, Responsable as the name picked, with Choisir… and
    # Aucun. What they hold is set by the code (Show-UserCardEdit), never written in the XAML.
    $x = { param($value) ConvertTo-XamlValue $value }
    $key = $script:DetailSectionKeys[$Card]
    $fields = @($script:UserEditFields[$Card])
    $lines = for ($i = 0; $i -lt $fields.Count; $i++) {
        $field = $fields[$i]
        $label = $field.Label
        "<TextBlock Grid.Row=`"$i`" Style=`"{StaticResource Txt.Muted}`" Text=`"$(& $x $label)`" VerticalAlignment=`"Center`" Margin=`"0,0,12,8`"/>"
        if (-not $field['Attribute']) {
            "<TextBlock x:Name=`"user_field_$($field.Id)`" Grid.Row=`"$i`" Grid.Column=`"1`" VerticalAlignment=`"Center`" TextWrapping=`"Wrap`" Margin=`"0,0,0,8`"/>"
        }
        elseif ($field['Kind'] -eq 'Manager') {
            "<StackPanel Grid.Row=`"$i`" Grid.Column=`"1`" Orientation=`"Horizontal`" Margin=`"0,0,0,8`">" +
            "<TextBlock x:Name=`"user_field_manager`" VerticalAlignment=`"Center`" AutomationProperties.Name=`"$(& $x $label)`"/>" +
            '<Button x:Name="user_manager_pick" Margin="10,0,0,0" Content="Choisir…" ToolTip="Chercher le responsable dans l''AD"/>' +
            '<Button x:Name="user_manager_clear" Margin="6,0,0,0" Content="Aucun" ToolTip="Aucun responsable"/></StackPanel>'
        }
        else {
            $shape = switch ($field['Kind']) {
                'Drive' { ' Width="70" HorizontalAlignment="Left" Tag="H:"' }
                { $_ -in 'Home', 'Unc' } { ' Tag="\\serveur\partage\%username%"' }
            }
            "<TextBox x:Name=`"user_field_$($field.Id)`" Grid.Row=`"$i`" Grid.Column=`"1`" Margin=`"0,0,0,8`"$shape AutomationProperties.Name=`"$(& $x $label)`"/>"
        }
    }
    $hint = if ($Card -eq 'Profil') {
        '<TextBlock Style="{StaticResource Txt.Muted}" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,8" Text="%username% devient l''identifiant. Repère ne crée pas le dossier de base."/>'
    }
    $definitions = '<RowDefinition Height="Auto"/>' * $fields.Count
    "<StackPanel x:Name=`"user_form_$key`" Visibility=`"Collapsed`" Margin=`"14,0,14,6`">" +
    "<TextBlock x:Name=`"user_edit_error_$key`" Visibility=`"Collapsed`" TextWrapping=`"Wrap`" Foreground=`"{DynamicResource R.DangerText}`" Margin=`"0,0,0,10`"/>" +
    "<Grid><Grid.ColumnDefinitions><ColumnDefinition Width=`"210`"/><ColumnDefinition Width=`"*`"/></Grid.ColumnDefinitions><Grid.RowDefinitions>$definitions</Grid.RowDefinitions>$($lines -join '')</Grid>" +
    "$hint</StackPanel>"
}

function Register-UserEdit($State, $Body) {
    # Modifier…, Annuler and Enregistrer of each card that can be edited, Entrée in its boxes (Enregistrer), and
    # Responsable's Choisir… and Aucun; then the cards being edited when the cards were built again show their edit as
    # it was (Show-UserCardEdit).
    if (-not $State['Edits']) { $State.Edits = @{} }
    foreach ($card in $script:UserEditFields.Keys) {
        $key = $script:DetailSectionKeys[$card]
        foreach ($part in 'edit', 'cancel', 'save') { $Body.FindName("user_$($part)_$key").CommandParameter = $card }
        $Body.FindName("user_edit_$key").Add_Click({ param($button) Start-UserCardEdit ([System.Windows.Window]::GetWindow($button).Tag) $button.CommandParameter })
        $Body.FindName("user_cancel_$key").Add_Click({ param($button) Stop-UserCardEdit ([System.Windows.Window]::GetWindow($button).Tag) $button.CommandParameter })
        $Body.FindName("user_save_$key").Add_Click({ param($button) Save-UserCard ([System.Windows.Window]::GetWindow($button).Tag) $button.CommandParameter })
        foreach ($field in $script:UserEditFields[$card]) {
            $box = $Body.FindName("user_field_$($field.Id)")
            if ($box -isnot [System.Windows.Controls.TextBox]) { continue }
            $box.Add_KeyDown({
                param($control, $e)
                if ($e.Key -ne [System.Windows.Input.Key]::Enter) { return }
                $e.Handled = $true
                Save-UserCard ([System.Windows.Window]::GetWindow($control).Tag) $script:UserEditFieldCard[($control.Name -replace '^user_field_', '')]
            })
        }
    }
    $Body.FindName('user_manager_pick').Add_Click({ param($button) Show-UserManagerDialog ([System.Windows.Window]::GetWindow($button).Tag) })
    $Body.FindName('user_manager_clear').Add_Click({ param($button) Set-UserManagerChoice ([System.Windows.Window]::GetWindow($button).Tag) '' '' })
    foreach ($card in @($State.Edits.Keys)) { Show-UserCardEdit $State $card }
}

function Start-UserCardEdit($State, [string]$Card) {
    # Modifier…: the card's fields, each holding AD's value, the first one focused.
    if (-not $State.Detail) { return }
    $user = $State.Detail.User
    $values = @{}
    foreach ($field in $script:UserEditFields[$Card]) { if ($field['Attribute']) { $values[$field.Id] = Get-UserEditValue $user $field } }
    $State.Edits[$Card] = @{ Values = $values; ManagerName = (Get-DnName ([string]$user.Manager)); Error = $null; Bad = @(); Started = [datetime]::UtcNow }
    Show-UserCardEdit $State $Card
    $first = @($script:UserEditFields[$Card] | ForEach-Object { $State.Body.Content.FindName("user_field_$($_.Id)") } | Where-Object { $_ -is [System.Windows.Controls.TextBox] })[0]
    $null = $first.Focus()
    $first.CaretIndex = $first.Text.Length
}

function Show-UserCardEdit($State, [string]$Card) {
    # A card in its edit: unfolded, its fields in place of its values, Annuler and Enregistrer in place of Modifier…, each
    # box holding what was typed ($State.Edits), the card's error said and the fields it names framed in red.
    $body = $State.Body.Content
    $key = $script:DetailSectionKeys[$Card]
    $edit = $State.Edits[$Card]
    $toggle = $body.FindName("user_section_$key")
    if (-not $toggle) { return }
    if (-not $toggle.IsChecked) { $toggle.IsChecked = $true }
    $body.FindName("user_view_$key").Visibility = 'Collapsed'
    $body.FindName("user_form_$key").Visibility = 'Visible'
    $body.FindName("user_edit_$key").Visibility = 'Collapsed'
    foreach ($part in 'cancel', 'save') { $body.FindName("user_$($part)_$key").Visibility = 'Visible' }
    foreach ($field in $script:UserEditFields[$Card]) {
        $control = $body.FindName("user_field_$($field.Id)")
        if ($control -is [System.Windows.Controls.TextBox]) {
            $control.Text = [string]$edit.Values[$field.Id]
            if ($edit.Bad -contains $field.Id) { $control.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'R.DangerBorder') }
            else { $control.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty) }
        }
        elseif ($field['Kind'] -eq 'Manager') {
            $control.Text = if ($edit.Values['manager']) { $edit.ManagerName } else { '—' }
            if ($edit.Bad -contains $field.Id) { $control.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.DangerText') }
            else { $control.ClearValue([System.Windows.Controls.TextBlock]::ForegroundProperty) }
        }
        else {
            $value = Get-UserEditValue $State.Detail.User $field
            $control.Text = if ($value) { $value } else { '—' }
        }
    }
    $message = $body.FindName("user_edit_error_$key")
    $message.Text = if ($edit.Error) { ConvertTo-FrenchError $edit.Error } else { '' }
    $message.Visibility = if ($edit.Error) { 'Visible' } else { 'Collapsed' }
}

function Read-UserCardEdit($State) {
    # What is typed in the cards being edited, into $State.Edits: before Enregistrer, and before the cards are built
    # again (a read), so nothing typed is lost.
    if (-not $State['Edits'] -or -not $State.Edits.Count) { return }
    $body = $State.Body.Content
    if ($body -isnot [System.Windows.FrameworkElement]) { return }
    foreach ($card in @($State.Edits.Keys)) {
        foreach ($field in $script:UserEditFields[$card]) {
            $box = $body.FindName("user_field_$($field.Id)")
            if ($box -is [System.Windows.Controls.TextBox]) { $State.Edits[$card].Values[$field.Id] = $box.Text }
        }
    }
}

function Stop-UserCardEdit($State, [string]$Card) {
    # Annuler, or a card saved whole: its values as text again, what was typed dropped.
    $State.Edits.Remove($Card)
    $body = $State.Body.Content
    $key = $script:DetailSectionKeys[$Card]
    if (-not $body.FindName("user_form_$key")) { return }
    $body.FindName("user_view_$key").Visibility = 'Visible'
    $body.FindName("user_form_$key").Visibility = 'Collapsed'
    foreach ($part in 'cancel', 'save') { $body.FindName("user_$($part)_$key").Visibility = 'Collapsed' }
    $edit = $body.FindName("user_edit_$key")
    $edit.Visibility = 'Visible'
    $null = $edit.Focus()
}

function Undo-UserCardEdit($State) {
    # Échap while a card is edited: that edit cancelled (the card the focus is in, else the last one begun), and $true;
    # $false when there's none (Échap then closes the window). A group's window has no edit.
    if ($State -isnot [hashtable] -or -not $State['Edits'] -or -not $State.Edits.Count) { return $false }
    $focused = [System.Windows.Input.Keyboard]::FocusedElement
    $card = $null
    foreach ($name in @($State.Edits.Keys)) {
        $form = $State.Body.Content.FindName("user_form_$($script:DetailSectionKeys[$name])")
        if ($form -and $focused -is [System.Windows.DependencyObject] -and $form.IsAncestorOf($focused)) { $card = $name }
    }
    if (-not $card) { $card = @($State.Edits.Keys | Sort-Object { $State.Edits[$_].Started })[-1] }
    Stop-UserCardEdit $State $card
    $true
}

function Save-UserCard($State, [string]$Card) {
    # Enregistrer: the card's changes checked first (Get-UserEditChange: nothing is sent while a value is wrong), then
    # sent in the background (Save-UserEditChange, Start-ADWrite), the window usable meanwhile; Enregistrer again while
    # they're sent is ignored. Then Complete-UserCardSave.
    Read-UserCardEdit $State
    $edit = $State.Edits[$Card]
    if (-not $edit -or -not $State.Detail) { return }
    $row = $State.Row
    $change = Get-UserEditChange $Card $State.Detail.User $edit.Values $row.Login
    if ($change.Problems.Count) {
        $edit.Error = @($change.Problems | ForEach-Object { $_.Text }) -join "`n"
        $edit.Bad = @($change.Problems | ForEach-Object { $_.Id })
        Show-UserCardEdit $State $Card
        return
    }
    if (-not $change.Fields.Count) {
        Stop-UserCardEdit $State $Card
        Show-DetailNotice $State (Tr 'Rien à enregistrer : aucune valeur changée.')
        return
    }
    $null = Start-ADWrite -Keys @("Edit|$($row.Domain)|$($row.DistinguishedName)|$Card") -Command 'Save-UserEditChange' -Arguments @((ConvertTo-WriteUser $row), $change) `
        -Window $State.Window -Context @{ State = $State; Card = $Card; Change = $change } -OnDone {
        param($write, $outcome)
        Complete-UserCardSave $write.State $write.Card $write.Change $outcome
    }
}

function Complete-UserCardSave($State, [string]$Card, $Change, $Outcome) {
    # Save-UserCard's changes sent. All saved, the card shows its values again. A field refused, the card stays in its
    # edit with what was typed, its error naming each field AD refused, and those it saved. The DC didn't answer in
    # time: the card stays in its edit, its error saying the values may have been saved. Then the window reads the
    # account again, and the page's row follows (Update-UserDetail). Closed meanwhile: only a failure is said, over
    # the main window.
    $row = $State.Row
    $result = if (-not $Outcome.Problem) { $Outcome.Result }
    $failed = if ($result) { @($result.Failed) } elseif (-not $Outcome.TimedOut) { @($Change.Fields | ForEach-Object { @{ Id = $_.Id; Label = $_.Label; Problem = $Outcome.Problem } }) }
    if ($State['Closed']) {
        if ($Outcome.TimedOut) { Show-Dialog -Title (Tr 'Enregistrer') -Message ((Tr '⚠ {0} : {1}') -f $row.Login, (Get-WriteUnsureText $Outcome.Timeout)) }
        elseif (@($failed).Count) { Show-Dialog -Title (Tr 'Enregistrer') -Message (@($failed | ForEach-Object { (Tr '{0} : non enregistré ({1})') -f $_.Label, "$($_.Problem)".TrimEnd('.') }) -join "`n") }
        return
    }
    # Annuler while they were sent: the card is no longer edited, and only the window read again says what was saved.
    $edit = $State.Edits[$Card]
    if ($Outcome.TimedOut) {
        if ($edit) {
            $edit.Error = (Tr '⚠ {0} : {1}') -f $row.Login, (Get-WriteUnsureText $Outcome.Timeout)
            $edit.Bad = @()
            Show-UserCardEdit $State $Card
        }
        else { Show-Dialog -Title (Tr 'Enregistrer') -Message ((Tr '⚠ {0} : {1}') -f $row.Login, (Get-WriteUnsureText $Outcome.Timeout)) -Owner $State.Window }
    }
    elseif (-not @($failed).Count) {
        if ($edit) { Stop-UserCardEdit $State $Card }
        $notice = (Tr '{0} : enregistré ({1}).') -f $row.Login, (Join-FrenchList @($Change.Fields | ForEach-Object { $_.Label.ToLower($script:UserDetailCulture) }))
        # Repère writes the attribute only, as a script would: the folder itself is the file server's.
        if ($Change.Replace.ContainsKey('homeDirectory')) { $notice += ' ' + (Tr "Le dossier de base n'est pas créé : créez-le sur le serveur, avec les droits de l'utilisateur.") }
        $State.NoticeAfterRead = $notice
    }
    else {
        $lines = @(foreach ($refused in $failed) { (Tr '{0} : non enregistré ({1})') -f $refused.Label, "$($refused.Problem)".TrimEnd('.') })
        $saved = @($Change.Fields | Where-Object { $result -and $result.Saved -contains $_.Id } | ForEach-Object { $_.Label })
        if ($saved.Count) { $lines += (Tr 'Enregistré : {0}.') -f (Join-FrenchList $saved) }
        if ($edit) {
            $edit.Error = $lines -join "`n"
            $edit.Bad = @($failed | ForEach-Object { $_.Id })
            Show-UserCardEdit $State $Card
        }
        else { Show-Dialog -Title (Tr 'Enregistrer') -Message ($lines -join "`n") -Owner $State.Window }
    }
    Update-UserDetail $State
}

function Show-UserManagerDialog($State) {
    # Responsable's Choisir…: the users whose name, login or email starts with what's typed (anr), in each domain of the
    # forest (New-ManagerPickerContent); the one chosen becomes the card's Responsable, saved with its other fields.
    $content = New-ManagerPickerContent $State.Row.Domain ([string]$State.Row.DistinguishedName)
    $list = $content.FindName('manager_results')

    Show-Dialog -Title (Tr 'Responsable') -Heading ((Tr 'Responsable de {0}') -f $State.Row.Name) -Icon 'user' -Owner $State.Window `
        -Message (Tr 'Choisissez la personne : elle est enregistrée avec les autres valeurs de la carte (Enregistrer).') -Content $content -PickFrom $list `
        -OkText (Tr 'Choisir') -State @{ Detail = $State; List = $list } -OnOk {
        param($dialog)
        $timer = $dialog.List.Parent.Parent.Parent.Tag.Timer
        $timer.Stop()
        $picked = $dialog.List.SelectedItem
        if ($picked) { Set-UserManagerChoice $dialog.Detail ([string]$picked.DistinguishedName) ([string]$picked.Name) }
    }
}

function New-ManagerPickerContent([string]$Domain, [string]$Self) {
    # The person picker of a user's Responsable and a computer's Géré par: a search box, and the users whose name,
    # login or email starts with what's typed, in $Domain then the forest's other domains (Find-UserManagerChoice), but
    # $Self (the object whose manager it is); one is chosen (its manager_results' SelectedItem). Its Tag's Timer is
    # stopped once it's closed.
    $content = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border Style="{StaticResource Field}" Height="34">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search:14}}</Border>
      <TextBox x:Name="manager_query" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Nom, identifiant ou courriel"/>
    </Grid>
  </Border>
  <Border Style="{StaticResource Card}" Margin="0,10,0,0" Height="220">
    <Grid>
      <ListBox x:Name="manager_results" Background="Transparent" BorderThickness="0" SelectionMode="Single" AutomationProperties.Name="Utilisateurs trouvés">
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem" BasedOn="{StaticResource {x:Type ListBoxItem}}">
            <Setter Property="Foreground" Value="{DynamicResource R.Text}"/><Setter Property="Padding" Value="10,6"/>
            <Setter Property="AutomationProperties.Name" Value="{Binding Name}"/>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <StackPanel Margin="2,2">
              <TextBlock Text="{Binding Name}" FontWeight="{DynamicResource R.FontWeightStrong}"/>
              <TextBlock Text="{Binding Details}" FontSize="12" Opacity="0.75" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
      <TextBlock x:Name="manager_hint" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" Margin="16"
                 Text="Tapez le début du nom, de l'identifiant ou du courriel."/>
    </Grid>
  </Border>
  <TextBlock x:Name="manager_note" Style="{StaticResource Txt.Muted}" Margin="0,8,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
</StackPanel>
'@))
    $domains = @(@($Domain) + @($script:domainList) | Where-Object { $_ } | Select-Object -Unique)
    $content.Tag = @{ Domains = $domains; Self = $Self; Timer = $null }
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(300)
    $timer.Tag = $content
    $timer.Add_Tick({ param($tick) $tick.Stop(); Find-UserManagerChoice $tick.Tag })
    $content.Tag.Timer = $timer
    # Searched once the typing pauses, so each letter doesn't query AD.
    $content.FindName('manager_query').Add_TextChanged({ param($box) $timer = $box.Parent.Parent.Parent.Tag.Timer; $timer.Stop(); $timer.Start() })
    $content.Add_Loaded({ param($panel) $null = $panel.FindName('manager_query').Focus() })
    $content
}

function Find-UserManagerChoice($Content) {
    # The users the text finds (Get-UserManagerChoice), searched in the background; a result for a text since changed
    # is left. The note under the list names a domain that couldn't be searched.
    $text = "$($Content.FindName('manager_query').Text)".Trim()
    $list = $Content.FindName('manager_results')
    $hint = $Content.FindName('manager_hint')
    if (-not $text) {
        $list.Items.Clear()
        $hint.Text = Tr "Tapez le début du nom, de l'identifiant ou du courriel."
        $hint.Visibility = 'Visible'
        return
    }
    if (-not $list.Items.Count) { $hint.Text = Tr 'Recherche…'; $hint.Visibility = 'Visible' }
    Start-BackgroundRead -Command 'Get-UserManagerChoice' -Arguments @($Content.Tag.Domains, $text, $Content.Tag.Self) -Functions 'Get-LdapText' `
        -Context @{ Content = $Content; Text = $text } -OnDone {
        param($context, $found, $problem)
        $content = $context.Content
        if ("$($content.FindName('manager_query').Text)".Trim() -ne $context.Text) { return }
        $list = $content.FindName('manager_results')
        $hint = $content.FindName('manager_hint')
        $note = $content.FindName('manager_note')
        $list.Items.Clear()
        $note.Visibility = 'Collapsed'
        if ($problem) { $hint.Text = (Tr 'Recherche impossible : {0}') -f (ConvertTo-FrenchError $problem); $hint.Visibility = 'Visible'; return }
        foreach ($item in @($found.Items)) { $null = $list.Items.Add($item) }
        $hint.Text = (Tr 'Aucun utilisateur trouvé pour « {0} ».') -f $context.Text
        $hint.Visibility = if ($list.Items.Count) { 'Collapsed' } else { 'Visible' }
        $lines = @(foreach ($miss in @($found.Unsearched)) { (Tr '{0} non cherché : {1}') -f $miss.Domain, (ConvertTo-FrenchError $miss.Problem) })
        if ($lines.Count) { $note.Text = $lines -join "`n"; $note.Visibility = 'Visible' }
    }
}

function Get-UserManagerChoice([string[]]$Domains, [string]$Text, [string]$Self) {
    # On a search runspace: the users of $Domains whose name, login or email starts with $Text (anr, as the Utilisateurs
    # page searches), 50 at most, but $Self (the account whose manager it is): as Items, each its Name, DistinguishedName
    # and Details (login, title, department, and its domain when there are several). Unsearched: each domain that
    # couldn't be, and why.
    $filter = "(&(objectCategory=person)(objectClass=user)(anr=$(Get-LdapText $Text)))"
    $items = [System.Collections.Generic.List[object]]::new()
    $unsearched = [System.Collections.Generic.List[object]]::new()
    foreach ($domain in $Domains) {
        try {
            foreach ($user in @(Get-ADUser -Server $domain -LDAPFilter $filter -Properties DisplayName, Title, Department -ResultSetSize 50 -ErrorAction Stop)) {
                if ($user.DistinguishedName -eq $Self) { continue }
                $items.Add([pscustomobject]@{
                    Name = if ($user.DisplayName) { [string]$user.DisplayName } else { [string]$user.Name }
                    DistinguishedName = [string]$user.DistinguishedName
                    Details = (@([string]$user.SamAccountName, [string]$user.Title, [string]$user.Department, $(if ($Domains.Count -gt 1) { $domain })) | Where-Object { $_ }) -join ' · '
                })
            }
        }
        catch { $unsearched.Add(@{ Domain = $domain; Problem = $_.Exception.Message }) }
    }
    @{ Items = @($items | Sort-Object Name | Select-Object -First 50); Unsearched = @($unsearched) }
}

function Set-UserManagerChoice($State, [string]$DistinguishedName, [string]$Name) {
    # The Responsable picked (Choisir…), or none (Aucun: an empty DN), into the Organisation card's edit, saved with its
    # other fields.
    Read-UserCardEdit $State
    $edit = $State.Edits['Organisation']
    if (-not $edit) { return }
    $edit.Values['manager'] = $DistinguishedName
    $edit.ManagerName = $Name
    Show-UserCardEdit $State 'Organisation'
}

function Register-DetailCopy($Body, $Sections, [string[]]$Ids, [string]$Prefix = 'user_detail') {
    # The values of $Ids that have a Copier button (Get-DetailRowsXaml): it copies the value, and so does Copier in the
    # value's right-click menu, then the window's toast says what was copied.
    foreach ($entry in @($Sections.Values | ForEach-Object { $_ })) {
        if ($Ids -notcontains $entry[2]) { continue }
        $button = $Body.FindName("$($Prefix)_copy_$($entry[2])")
        if (-not $button) { continue }
        $copy = @{ Value = [string]$entry[1]; Label = [string]$entry[0] }
        $button.CommandParameter = $copy
        $button.Add_Click({ param($control) Copy-DetailValue $control })
        $menu = [System.Windows.Controls.ContextMenu]::new()
        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = Tr 'Copier'
        $item.CommandParameter = $copy
        $item.Add_Click({ param($control) Copy-DetailValue $control })
        $null = $menu.Items.Add($item)
        $Body.FindName("$($Prefix)_$($entry[2])").ContextMenu = $menu
    }
}

function Copy-DetailValue($Control) {
    # A value of Propriétés to the clipboard (Register-DetailCopy); a menu item finds its window through the value it
    # opened on.
    # The Copier button shows what the copy did (Show-CopyFeedback); the menu item has nothing to show it on once closed.
    $anchor = if ($Control -is [System.Windows.Controls.MenuItem]) { $Control.Parent.PlacementTarget } else { $Control }
    $copy = $Control.CommandParameter
    $copied = Set-ClipboardText $copy.Value
    if ($Control -is [System.Windows.Controls.Button]) { Show-CopyFeedback $Control $copied }
    $text = if ($copied) { (Tr '{0} copié.') -f $copy.Label } else { (Tr '{0} non copié : le presse-papiers est occupé par un autre programme.') -f $copy.Label }
    Show-DetailNotice ([System.Windows.Window]::GetWindow($anchor).Tag) $text
}

function Register-DetailSection($Body) {
    # Each card's header folds or unfolds it (Tout développer and Tout réduire, all of them: Register-DetailFoldBar).
    foreach ($key in @($script:DetailSectionKeys.Values | Select-Object -Unique)) {
        $toggle = $Body.FindName("user_section_$key")
        if (-not $toggle) { continue }
        $toggle.Tag = $key
        $toggle.Add_Checked({ param($control) Set-DetailSectionOpen $control $true })
        $toggle.Add_Unchecked({ param($control) Set-DetailSectionOpen $control $false })
    }
}

function Register-DetailFoldBar($Root, [string]$Prefix) {
    # Tout développer and Tout réduire, above the cards: they're the window's, kept across reads, so each click acts on
    # the cards it shows then. Before the cards are read, or when they couldn't be, there's nothing to fold.
    $Root.FindName("$($Prefix)_expand_all").Add_Click({ param($button) Set-DetailSectionAll ([System.Windows.Window]::GetWindow($button).Tag.Body.Content) $true })
    $Root.FindName("$($Prefix)_collapse_all").Add_Click({ param($button) Set-DetailSectionAll ([System.Windows.Window]::GetWindow($button).Tag.Body.Content) $false })
}

function Set-DetailSectionAll($Body, [bool]$Open) {
    # Tout développer or Tout réduire: each card of the window as a click on its header does, apparence.json saved once.
    # Without cards (a message in their place), nothing to do or save.
    if ($Body -isnot [System.Windows.Controls.Panel]) { return }
    $script:DetailSectionBatch = $true
    try {
        foreach ($key in @($script:DetailSectionKeys.Values | Select-Object -Unique)) {
            $toggle = $Body.FindName("user_section_$key")
            if ($toggle) { $toggle.IsChecked = $Open }
        }
    }
    finally { $script:DetailSectionBatch = $false }
    Save-Appearance
}
$script:DetailSectionBatch = $false

function Set-DetailSectionOpen($Toggle, [bool]$Open) {
    # Folds or unfolds a card, and remembers it for the next Propriétés (saved by Set-DetailSectionAll once it has done
    # every card).
    $key = [string]$Toggle.Tag
    $Toggle.FindName("user_section_body_$key").Visibility = if ($Open) { 'Visible' } else { 'Collapsed' }
    $Toggle.FindName("user_section_chevron_$key").RenderTransform.Angle = if ($Open) { 0 } else { -90 }
    $folded = @($script:Appearance.FoldedSections | Where-Object { $_ -ne $key })
    if (-not $Open) { $folded += $key }
    $script:Appearance.FoldedSections = $folded
    if (-not $script:DetailSectionBatch) { Save-Appearance }
}

function Update-UserGroupPick($State) {
    # Retirer… says how many groups are ticked, and waits for one.
    $count = @($State.Picks | Where-Object IsChecked).Count
    $State.Body.Content.FindName('user_group_remove').IsEnabled = $count -gt 0
    $State.Body.Content.FindName('user_group_remove_label').Text = if ($count) { (Tr 'Retirer ({0})…') -f $count } else { Tr 'Retirer…' }
}

function Invoke-UserDetailUnlock($State) {
    # In the background (Start-UserDetailWrite), then the window reads the account again.
    Start-UserDetailWrite $State 'Unlock' (Tr 'Déverrouiller') -Done ((Tr '{0} déverrouillé.') -f $State.Row.Login)
}

function Invoke-UserDetailToggle($State) {
    # Activer, or Désactiver… after the page's confirmation (Annuler the default), with the page's rule: never the
    # account running Repère (Test-SelfAccount). In the background (Start-UserDetailWrite), then the window reads the
    # account again, and the page's row follows.
    $row = $State.Row
    if (-not $State.Detail.User.Enabled) {
        Start-UserDetailWrite $State 'Enable' (Tr 'Activer') -Done ((Tr '{0} activé.') -f $row.Login) -AfterRead
        return
    }
    if (Test-SelfAccount $row.Login $row.Domain) {
        Show-Dialog -Title (Tr 'Désactiver') -Icon 'ban' -Tone 'warn' -Heading ((Tr '{0} : rien à faire') -f (Tr 'Désactiver')) -Owner $State.Window `
            -Message ((Tr "Repère ne désactive pas votre propre compte ({0}) : vous ne pourriez plus ouvrir de session.") -f $row.Login)
        return
    }
    Show-Dialog -Title (Tr 'Désactiver') -Heading ((Tr 'Désactiver {0} ?') -f $row.Name) -Icon 'ban' -Tone 'danger' -Owner $State.Window `
        -Message (Tr 'Un compte désactivé ne peut plus ouvrir de session. Rien n''est perdu : Activer le rétablit.') `
        -OkText (Tr 'Désactiver') -CancelIsDefault -State @{ Detail = $State } -OnOk {
        param($dialog)
        $state = $dialog.Detail
        Start-UserDetailWrite $state 'Disable' (Tr 'Désactiver') -Done ((Tr '{0} désactivé.') -f $state.Row.Login) -AfterRead
    }
}

function Show-UserExpiryDialog($State) {
    # The account's expiration: never, or the end of a day (AD keeps the start of the next one, as Utilisateurs et
    # ordinateurs Active Directory does). « Dans 1 mois » and the like pick a day.
    $row = $State.Row
    $current = $State.Detail.User.AccountExpirationDate
    $content = [System.Windows.Markup.XamlReader]::Parse((ConvertTo-LocalXaml @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <RadioButton x:Name="expiry_never" GroupName="expiry" Content="N'expire jamais"/>
  <RadioButton x:Name="expiry_on" GroupName="expiry" Content="Expire à la fin du" Margin="0,10,0,0"/>
  <StackPanel Orientation="Horizontal" Margin="28,6,0,0">
    <DatePicker x:Name="expiry_date" Width="180" SelectedDateFormat="Long"/>
  </StackPanel>
  <WrapPanel Margin="28,8,0,0">
    <Button x:Name="expiry_1" Content="Dans 1 mois" Margin="0,0,6,6"/>
    <Button x:Name="expiry_3" Content="Dans 3 mois" Margin="0,0,6,6"/>
    <Button x:Name="expiry_6" Content="Dans 6 mois" Margin="0,0,6,6"/>
    <Button x:Name="expiry_12" Content="Dans 1 an" Margin="0,0,6,6"/>
  </WrapPanel>
</StackPanel>
'@))
    $picker = $content.FindName('expiry_date')
    # Its date and calendar in this run's language.
    $picker.Language = [System.Windows.Markup.XmlLanguage]::GetLanguage($script:UserDetailCulture.IetfLanguageTag)
    if ($current) {
        $content.FindName('expiry_on').IsChecked = $true
        $picker.SelectedDate = $current.Date.AddDays(-1)
    }
    else {
        $content.FindName('expiry_never').IsChecked = $true
        $picker.SelectedDate = (Get-Date).Date.AddMonths(3)
    }
    foreach ($months in 1, 3, 6, 12) {
        $button = $content.FindName("expiry_$months")
        $button.CommandParameter = $months
        $button.Add_Click({
            param($button)
            $panel = $button.Parent.Parent
            $panel.FindName('expiry_date').SelectedDate = (Get-Date).Date.AddMonths([int]$button.CommandParameter)
            $panel.FindName('expiry_on').IsChecked = $true
        })
    }
    $picker.Add_SelectedDateChanged({ param($control) $control.Parent.Parent.FindName('expiry_on').IsChecked = $true })

    Show-Dialog -Title (Tr 'Expiration du compte') -Heading ((Tr 'Expiration du compte de {0}') -f $row.Name) -Icon 'calendar' -Owner $State.Window `
        -Message (Tr 'Le compte cesse de fonctionner le lendemain du jour choisi, à minuit.') -Content $content -OkText (Tr 'Enregistrer') `
        -State @{ Detail = $State; Content = $content } -OnOk {
        param($dialog)
        $state = $dialog.Detail
        $row = $state.Row
        $content = $dialog.Content
        $title = Tr 'Expiration du compte'
        $failed = Tr '✖ {0} : expiration non changée ({1})'
        # A date that can't be the account's last day is said before anything is sent.
        if ($content.FindName('expiry_never').IsChecked) {
            Start-UserDetailWrite $state 'NoExpiry' $title -Done ((Tr "Le compte de {0} n'expire plus.") -f $row.Login) -Failed $failed
            return
        }
        $day = $content.FindName('expiry_date').SelectedDate
        $wrong = if (-not $day) { Tr 'aucune date choisie' } elseif ($day.Date -lt (Get-Date).Date) { (Tr 'le {0} est passé') -f (Format-TextDate $day -Day) }
        if ($wrong) {
            Show-Dialog -Title $title -Message ($failed -f $row.Login, $wrong) -Owner $state.Window
            return
        }
        Start-UserDetailWrite $state 'Expiry' $title $day.Date.AddDays(1) -Done ((Tr 'Le compte de {0} expire à la fin du {1}.') -f $row.Login, (Format-TextDate $day -Day)) -Failed $failed
    }
}

function Show-UserGroupAddDialog($State) {
    # Ajouter à un groupe…: the groups of the user's domain whose name contains the text, and of the other domains those
    # that can take the user (New-GroupPickerContent), those it's already in left out; each one ticked is added, after a
    # second confirmation when one is privileged (Confirm-PrivilegedGroup). The change takes effect at the user's next
    # logon.
    $row = $State.Row
    $content = New-GroupPickerContent $row.Domain @($State.Detail.Groups | Where-Object Membership -in 'Directe', 'Principale' | ForEach-Object DistinguishedName)

    Show-Dialog -Title (Tr 'Ajouter à un groupe') -Heading ((Tr 'Ajouter {0} à des groupes') -f $row.Name) -Icon 'users' -Owner $State.Window `
        -Message ((Tr 'Cochez un ou plusieurs groupes de {0}.') -f $row.Domain) -Content $content -PickFrom $content.FindName('group_results') -OkText (Tr 'Ajouter') `
        -State @{ Detail = $State; Content = $content; Groups = @() } -OnOk {
        param($dialog)
        $dialog.Groups = @($dialog.Content.FindName('group_results').SelectedItems)
        if (-not $dialog.Groups.Count) { return }
        Confirm-PrivilegedGroup $dialog.Groups $dialog.Detail.Row.Name $dialog.Detail.Window $dialog { param($dialog) Add-UserGroupList $dialog.Detail $dialog.Groups }
    }
}

function Add-UserGroupList($State, $Groups) {
    # The user into each of $Groups (the picker's items), in the background (Start-UserGroupWrite), then the window
    # read again, a notice of those it's in, and the refusals.
    Start-UserGroupWrite $State $Groups $true
}

function Invoke-UserGroupWrite($Row, $Groups, [bool]$Add, [string]$AsMember = 'Get-UserAsMember') {
    # On a search runspace: the user ($Row, ConvertTo-WriteUser) into or out of each of $Groups (Name,
    # DistinguishedName), each one's Problem as it goes (Add-WriteProgress, by index), $null when done. Through
    # Invoke-UserChange: a group of the user's domain goes where the user's other changes go. $AsMember: what gives
    # the server and the member a group takes (Get-UserAsMember; Get-ComputerAsMember, for a computer's Propriétés).
    $account = @{}
    $Groups = @($Groups)
    for ($i = 0; $i -lt $Groups.Count; $i++) {
        $group = $Groups[$i]
        $problem = try {
            $server, $member = & $AsMember $Row $group.DistinguishedName $account
            if ($Add) { $null = Invoke-UserChange $Row.Domain { param($server) Add-ADGroupMember -Server $server -Identity $group.DistinguishedName -Members $member -ErrorAction Stop } $server }
            else { $null = Invoke-UserChange $Row.Domain { param($server) Remove-ADGroupMember -Server $server -Identity $group.DistinguishedName -Members $member -Confirm:$false -ErrorAction Stop } $server }
            $null
        }
        catch { $_.Exception.Message }
        Add-WriteProgress $i @{ Problem = $problem }
    }
}

function Start-UserGroupWrite($State, $Groups, [bool]$Add) {
    # Ajouter à un groupe or Retirer… of a user's Propriétés, in the background (Invoke-UserGroupWrite): the window
    # usable meanwhile. A group already being changed for this user is left out. Then the window reads the account
    # again, a notice names the groups done, and a dialog the others: refused, or perhaps done (the DC didn't answer
    # in time).
    $row = $State.Row
    $pending = @($Groups | Where-Object { -not (Test-ADWriteBusy "Group|$($row.Domain)|$($row.DistinguishedName)|$($_.DistinguishedName)") })
    if (-not $pending.Count) { return }
    $keys = @($pending | ForEach-Object { "Group|$($row.Domain)|$($row.DistinguishedName)|$($_.DistinguishedName)" })
    $copies = @($pending | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; DistinguishedName = [string]$_.DistinguishedName } })
    $null = Start-ADWrite -Keys $keys -Command 'Invoke-UserGroupWrite' -Arguments @((ConvertTo-WriteUser $row), $copies, $Add) -Functions 'Get-UserAsMember', 'Get-DomainOfDN' `
        -Count $copies.Count -Window $State.Window -Context @{ State = $State; Groups = $copies; Add = $Add } -OnDone {
        param($write, $outcome)
        Complete-UserGroupWrite $write.State $write.Groups $write.Add $outcome
    }
}

function Complete-UserGroupWrite($State, $Groups, [bool]$Add, $Outcome) {
    # Start-UserGroupWrite's change: the window read again, the groups done in its toast, the others in a dialog.
    $login = $State.Row.Login
    $done = [System.Collections.Generic.List[string]]::new()
    $lines = for ($i = 0; $i -lt $Groups.Count; $i++) {
        $group = $Groups[$i]
        $answer = Get-WriteAnswer $Outcome $i
        if ($answer.Unsure) { (Tr '⚠ {0} : {1}') -f $group.Name, (Get-WriteUnsureText $Outcome.Timeout) }
        elseif ($answer.Problem) {
            $format = if ($Add) { Tr '✖ {0} : non ajouté à {1} ({2})' } else { Tr '✖ {0} : non retiré de {1} ({2})' }
            $format -f $login, $group.Name, $answer.Problem
        }
        else { $done.Add($group.Name) }
    }
    $open = -not $State['Closed']
    if ($open) { Update-UserDetail $State }
    if ($done.Count -and $open) {
        $format = if ($Add) { Tr '{0} ajouté à {1}.' } else { Tr '{0} retiré de {1}.' }
        Show-DetailNotice $State ($format -f $login, (Join-FrenchList $done))
    }
    if ($lines) {
        $title = if ($Add) { Tr 'Ajouter à un groupe' } else { Tr 'Retirer du groupe' }
        Show-Dialog -Title $title -Message (@($lines) -join "`n") -Owner (Get-DetailOwner $State)
    }
}

function Confirm-PrivilegedGroup($Groups, [string]$Who, $Owner, [hashtable]$State, [scriptblock]$OnOk) {
    # Ajouter à un groupe's OK, a user's or a selection's: & $OnOk $State. When the groups ticked ($Groups, the picker's
    # items) include a Privileged one (Get-UserGroupChoice), only after a second confirmation, red, that names them,
    # Annuler the default: one tick there can give $Who rights over the whole domain, and Enter, pressed out of habit,
    # mustn't. The other groups ticked are added with them.
    $privileged = @($Groups | Where-Object Privileged)
    if (-not $privileged.Count) { & $OnOk $State; return }
    $names = @($privileged | ForEach-Object { [string]$_.Name })
    # The plain groups ticked with them are added too, Annuler adds none: said, since only the privileged are named.
    $plain = @($Groups | Where-Object { -not $_.Privileged } | ForEach-Object { [string]$_.Name })
    $heading, $message = if ($names.Count -eq 1) {
        ((Tr 'Ajouter {0} à {1} ?') -f $Who, $names[0]),
        ((Tr "{0} est un groupe privilégié de l'AD : ses membres peuvent avoir des droits sur tout le domaine.") -f $names[0])
    }
    else {
        ((Tr 'Ajouter {0} à {1} groupes privilégiés ?') -f $Who, $names.Count),
        (Tr "Ces groupes sont des groupes privilégiés de l'AD : leurs membres peuvent avoir des droits sur tout le domaine.")
    }
    if ($plain.Count) {
        $also = if ($plain.Count -eq 1) { Tr '{0} est ajouté aussi.' } else { Tr '{0} sont ajoutés aussi.' }
        $message += ' ' + ($also -f (Join-FrenchList $plain))
    }
    Show-Dialog -Title (Tr 'Ajouter à un groupe') -Heading $heading -Names $(if ($names.Count -gt 1) { $names }) -Icon 'warning' -Tone 'danger' -Owner $Owner `
        -Message $message -OkText (Tr 'Ajouter') -CancelIsDefault -State $State -OnOk $OnOk
}

function Test-PrivilegedGroup($Group) {
    # Whether $Group (read with adminCount) is one Confirm-PrivilegedGroup asks twice for: the groups AD protects
    # (adminCount), the administration groups by their RID (Test-AdminGroupSid), and DnsAdmins, by its name.
    $protected = $Group.PSObject.Properties['adminCount']
    [bool]($protected -and $protected.Value -ge 1) -or (Test-AdminGroupSid "$($Group.SID)") -or [string]$Group.SamAccountName -eq 'DnsAdmins'
}

function Test-AdminGroupSid([string]$Sid) {
    # Whether $Sid is one of the groups AD protects, by its RID: Admins du domaine (512), Contrôleurs de domaine (516,
    # and 521 read-only), Administrateurs du schéma (518) and de l'entreprise (519), Administrateurs clés (526, 527), and
    # the built-in Administrateurs (544), Opérateurs de compte, de serveur, d'impression et de sauvegarde (548 to 551)
    # and Duplicateurs (552). Under 1000, a RID is one Windows gives the same meaning in every domain, and 544 to 552 only
    # exist under Builtin (S-1-5-32). Their adminCount says it too, but not before SDProp has run, and dsHeuristics can
    # leave the Opérateurs groups out of AdminSDHolder: then they have none.
    [bool]($Sid -match '-(\d+)$' -and [int]$Matches[1] -in 512, 516, 518, 519, 521, 526, 527, 544, 548, 549, 550, 551, 552)
}

function New-GroupPickerContent([string]$Domain, [string[]]$Already) {
    # The group picker of Ajouter à un groupe… (a user's Propriétés, and the pages' selection, SelectionGroups.ps1): a
    # search box and the groups found as the typing pauses (Find-UserGroupChoice), several ticked at once (its
    # group_results' SelectedItems). The groups of $Domain, then of the other domains those that can take its accounts
    # (Get-UserGroupChoice); those in $Already left out.
    $content = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border Style="{StaticResource Field}" Height="34">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search:14}}</Border>
      <TextBox x:Name="group_query" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Nom du groupe (ex. vpn)"/>
    </Grid>
  </Border>
  <Border Style="{StaticResource Card}" Margin="0,10,0,0" Height="220">
    <Grid>
      <ListBox x:Name="group_results" Background="Transparent" BorderThickness="0" SelectionMode="Multiple" AutomationProperties.Name="Groupes trouvés">
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem" BasedOn="{StaticResource {x:Type ListBoxItem}}">
            <Setter Property="Foreground" Value="{DynamicResource R.Text}"/><Setter Property="Padding" Value="10,6"/>
            <Setter Property="AutomationProperties.Name" Value="{Binding Name}"/>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid Margin="2,2">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <!-- Ticked as the group is chosen: a click on the row ticks or unticks it. -->
              <CheckBox IsHitTestVisible="False" Focusable="False" VerticalAlignment="Center" Margin="0,0,8,0"
                        IsChecked="{Binding IsSelected, RelativeSource={RelativeSource AncestorType=ListBoxItem}}"/>
              <StackPanel Grid.Column="1">
                <TextBlock Text="{Binding Name}" FontWeight="{DynamicResource R.FontWeightStrong}"/>
                <TextBlock Text="{Binding Details}" FontSize="12" Opacity="0.75" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <!-- A privileged group (Get-UserGroupChoice): a red badge, as the Utilisateurs page marks a disabled account. -->
              <Border Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0" CornerRadius="9" Padding="8,1" BorderThickness="1"
                      Background="{DynamicResource R.DangerBg}" BorderBrush="{DynamicResource R.DangerBorder}" TextElement.Foreground="{DynamicResource R.DangerText}"
                      ToolTip="Groupe privilégié de l'AD : ses membres peuvent avoir des droits sur tout le domaine.">
                <Border.Style>
                  <Style TargetType="Border">
                    <Setter Property="Visibility" Value="Collapsed"/>
                    <Style.Triggers><DataTrigger Binding="{Binding Privileged}" Value="True"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>
                  </Style>
                </Border.Style>
                <TextBlock Text="Privilégié" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}"/>
              </Border>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
      <TextBlock x:Name="group_hint" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" Margin="16"
                 Text="Tapez une partie du nom du groupe."/>
    </Grid>
  </Border>
  <CheckBox x:Name="group_other_domains" Margin="0,10,0,0" Content="Chercher aussi dans les autres domaines"/>
  <TextBlock x:Name="group_note" Style="{StaticResource Txt.Muted}" Margin="0,8,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
</StackPanel>
'@))
    $content.Tag = @{ Domain = $Domain; Already = @($Already); Timer = $null }
    # In a forest of one domain, there's no other to search.
    $others = $content.FindName('group_other_domains')
    if (-not @($script:domainList | Where-Object { $_ -and $_ -ne $Domain }).Count) { $others.Visibility = 'Collapsed' }
    $others.Add_Checked({ param($box) Find-UserGroupChoice $box.Parent })
    $others.Add_Unchecked({ param($box) Find-UserGroupChoice $box.Parent })
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(300)
    $timer.Tag = $content
    $timer.Add_Tick({ param($tick) $tick.Stop(); Find-UserGroupChoice $tick.Tag })
    $content.Tag.Timer = $timer
    # Searched once the typing pauses, so each letter doesn't query AD.
    $content.FindName('group_query').Add_TextChanged({ param($box) $timer = $box.Parent.Parent.Parent.Tag.Timer; $timer.Stop(); $timer.Start() })
    $content.FindName('group_query').Add_KeyDown({
        $e = $args[1]
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Find-UserGroupChoice $args[0].Parent.Parent.Parent }
    })
    $content.Add_Loaded({ param($panel) $null = $panel.FindName('group_query').Focus() })
    $content
}

function Find-UserGroupChoice($Content) {
    # The groups whose name contains the text (50 at most), in the user's domain, and in the others when it has none or
    # Chercher aussi dans les autres domaines is ticked, searched in the background; a result for a text or a box since
    # changed is left. The note under the list says what it doesn't: that the user's domain had none, or a domain not
    # searched.
    $text = "$($Content.FindName('group_query').Text)".Trim()
    $others = [bool]$Content.FindName('group_other_domains').IsChecked
    $list = $Content.FindName('group_results')
    $hint = $Content.FindName('group_hint')
    if (-not $text) {
        $list.Items.Clear()
        $hint.Text = Tr 'Tapez une partie du nom du groupe.'
        $hint.Visibility = 'Visible'
        $Content.FindName('group_note').Visibility = 'Collapsed'
        return
    }
    if (-not $list.Items.Count) { $hint.Text = Tr 'Recherche…'; $hint.Visibility = 'Visible' }
    Start-BackgroundRead -Command 'Get-UserGroupChoice' -Arguments @($Content.Tag.Domain, $text, $Content.Tag.Already, $others) -Functions 'Get-LdapText', 'Test-AdminGroupSid', 'Test-PrivilegedGroup' `
        -Variables (Get-DetailReadVariable) -Context @{ Content = $Content; Text = $text; Others = $others } -OnDone {
        param($context, $found, $problem)
        $content = $context.Content
        if ("$($content.FindName('group_query').Text)".Trim() -ne $context.Text -or [bool]$content.FindName('group_other_domains').IsChecked -ne $context.Others) { return }
        $list = $content.FindName('group_results')
        $hint = $content.FindName('group_hint')
        $note = $content.FindName('group_note')
        $list.Items.Clear()
        $note.Visibility = 'Collapsed'
        if ($problem) { $hint.Text = (Tr 'Recherche impossible : {0}') -f (ConvertTo-FrenchError $problem); $hint.Visibility = 'Visible'; return }
        foreach ($item in @($found.Items)) { $null = $list.Items.Add($item) }
        # The groups found may all be the user's already, left out: said, so they aren't taken for missing from AD.
        $hint.Text = if ($found['AlreadyIn']) { (Tr 'Déjà membre de chaque groupe dont le nom contient « {0} ».') -f $context.Text }
                     else { (Tr 'Aucun groupe dont le nom contient « {0} ».') -f $context.Text }
        $hint.Visibility = if ($list.Items.Count) { 'Collapsed' } else { 'Visible' }
        $lines = @(
            if ($found.OthersOnly -and $list.Items.Count) { (Tr 'Aucun dans {0} : voici ceux des autres domaines.') -f $content.Tag.Domain }
            foreach ($miss in @($found.Unsearched)) { (Tr '{0} non cherché : {1}') -f $miss.Domain, (ConvertTo-FrenchError $miss.Problem) }
        )
        if ($lines.Count) { $note.Text = $lines -join "`n"; $note.Visibility = 'Visible' }
    }
}

function Get-UserGroupChoice([string]$Domain, [string]$Text, [string[]]$Already, [bool]$OtherDomains) {
    # The groups of $Domain whose name contains $Text, those in $Already left out: as Items, for the list. It runs at each
    # pause in the typing: AD is asked for no more than can be shown (50, and the user's groups, left out after).
    # With $OtherDomains, or when $Domain has none, the other domains' after them, their domain in their details: only
    # those AD lets take an account of another domain (domain local and universal: a global group refuses it), and not
    # the groups Windows creates (isCriticalSystemObject: Administrateurs, Administrateurs de l'entreprise…), which
    # would give the user rights over that domain. OthersOnly: $Domain had none. Unsearched: each other domain that
    # couldn't be searched, and why.
    # $Domain's own are all offered, Admins du domaine and Opérateurs de sauvegarde with the rest, since an admin may need
    # them; Privileged marks those, for the list's mark and Ajouter's red confirmation (Confirm-PrivilegedGroup, #233):
    # the groups AD protects (adminCount, which SDProp sets on Admins du domaine, the Opérateurs groups and the like), and
    # the administration groups by their RID (Test-AdminGroupSid), and DnsAdmins, by its name: AD doesn't protect it and
    # its RID is any, but its members can run code on the DCs. Not every group Windows creates (isCriticalSystemObject):
    # Utilisateurs du Bureau à distance or Invités du domaine are routine, and a red confirmation for them would teach to
    # click through it. AD doesn't clear adminCount once a group is no longer protected: marked all the same, never
    # refused. Nesting isn't followed here: a group nested in a protected one is marked by the adminCount SDProp gives it.
    $size = 50 + @($Already).Count
    $read = 'Description', 'adminCount'
    $item = {
        param($Group, [string]$Where)
        [pscustomobject]@{
            Name = [string]$Group.Name; DistinguishedName = [string]$Group.DistinguishedName
            Details = (@($Where, "$($script:GroupTypes[[string]$Group.GroupCategory]), $($script:GroupScopes[[string]$Group.GroupScope])", [string]$Group.Description) | Where-Object { $_ }) -join ' · '
            Privileged = Test-PrivilegedGroup $Group
        }
    }
    $matched = @(Get-ADGroup -Server $Domain -Filter "Name -like '*$($Text -replace "'", "''")*'" -Properties $read -ResultSetSize $size -ErrorAction Stop)
    $found = @($matched | Where-Object { $Already -notcontains $_.DistinguishedName } | Sort-Object Name | Select-Object -First 50)
    # How many of $Domain's left out, as already joined: with none other, the list says so rather than « aucun groupe ».
    $alreadyIn = $matched.Count - @($matched | Where-Object { $Already -notcontains $_.DistinguishedName }).Count
    $items = @(foreach ($group in $found) { & $item $group '' })
    $unsearched = [System.Collections.Generic.List[object]]::new()
    $others = @($script:domainList | Where-Object { $_ -and $_ -ne $Domain })
    if ($others.Count -and ($OtherDomains -or -not $items.Count)) {
        # groupType's bits: 4 domain local, 8 universal.
        $filter = "(&(objectCategory=group)(name=*$(Get-LdapText $Text)*)(|(groupType:1.2.840.113556.1.4.803:=4)(groupType:1.2.840.113556.1.4.803:=8))(!(isCriticalSystemObject=TRUE)))"
        $items += @(foreach ($other in $others) {
            try {
                Get-ADGroup -Server $other -LDAPFilter $filter -Properties $read -ResultSetSize $size -ErrorAction Stop |
                    Where-Object { $Already -notcontains $_.DistinguishedName } | Sort-Object Name | ForEach-Object { & $item $_ $other }
            }
            catch { $unsearched.Add(@{ Domain = $other; Problem = $_.Exception.Message }) }
        }) | Select-Object -First (50 - $items.Count)
        return @{ Items = $items; OthersOnly = -not $found.Count; Unsearched = @($unsearched); AlreadyIn = $alreadyIn }
    }
    @{ Items = $items; OthersOnly = $false; Unsearched = @(); AlreadyIn = $alreadyIn }
}

function Get-UserAsMember($Row, [string]$Group, [hashtable]$Account) {
    # The server and the member Add-ADGroupMember and Remove-ADGroupMember take to put the user in or out of $Group: its
    # domain's DC, and the user's DN; a group of another domain's DC can't find the user by DN, so it's given the user as
    # read in its own domain (once, kept in $Account). For a group of the user's own domain, the domain's name:
    # Invoke-UserChange then picks its DC (Get-UserServer).
    $server = Get-DomainOfDN $Group
    if (-not $server -or $server -eq $Row.Domain) { return $Row.Domain, $Row.DistinguishedName }
    if (-not $Account['User']) { $Account.User = Get-ADUser -Server $Row.Domain -Identity $Row.DistinguishedName -ErrorAction Stop }
    $server, $Account.User
}

function Join-FrenchList([string[]]$Items) {
    # « A », « A et B », « A, B et C »; in English, A and B.
    if ($Items.Count -le 1) { return "$($Items -join '')" }
    (Tr '{0} et {1}') -f (($Items | Select-Object -First ($Items.Count - 1)) -join ', '), $Items[-1]
}

function Remove-UserGroup($State) {
    # Retirer…: the user out of the direct groups ticked, after one confirmation that names them.
    $row = $State.Row
    $groups = @($State.Picks | Where-Object IsChecked | ForEach-Object Tag)
    if (-not $groups.Count) { return }
    $names = @($groups | ForEach-Object Name)
    $heading, $message = if ($groups.Count -eq 1) {
        ((Tr 'Retirer {0} de {1} ?') -f $row.Name, $names[0]), (Tr 'Il perd les accès donnés par ce groupe à sa prochaine ouverture de session.')
    }
    else {
        ((Tr 'Retirer {0} de {1} groupes ?') -f $row.Name, $groups.Count), (Tr 'Il perd les accès donnés par ces groupes à sa prochaine ouverture de session.')
    }
    Show-Dialog -Title (Tr 'Retirer du groupe') -Heading $heading -Names $(if ($groups.Count -gt 1) { $names }) -Icon 'users' -Tone 'danger' -Owner $State.Window `
        -Message $message -OkText (Tr 'Retirer') -CancelIsDefault `
        -State @{ Detail = $State; Groups = $groups } -OnOk {
        param($dialog)
        # In the background (Start-UserGroupWrite), then the window read again.
        Start-UserGroupWrite $dialog.Detail $dialog.Groups $false
    }
}

function Get-UserDetailText($State) {
    # Copier: every card as text, the groups with how the user belongs to them.
    $sections = Get-UserDetailSection $State.Detail
    $lines = @("$($State.Row.Name) ($($State.Row.Login), $($State.Row.Domain))", '')
    foreach ($title in $sections.Keys) {
        $lines += Tr $title
        foreach ($entry in $sections[$title]) { $lines += '  ' + ((Tr '{0} : {1}') -f $entry[0], $(if ("$($entry[1])") { $entry[1] } else { '—' })) }
        $lines += ''
        if ($title -eq 'Mot de passe') {
            $lines += Tr 'Groupes'
            foreach ($group in $State.Detail.Groups) { $lines += "  $($group.Name) ($(Tr $group.Membership))" }
            $lines += ''
        }
    }
    $lines -join [Environment]::NewLine
}

function Show-UserDetail($Row, $Owner, $Icon) {
    # The window opens at once, « Lecture… »; the user is read in the background. It acts on its own copy of the row:
    # a search may replace the page's rows while it's open (Sync-UserPageRow updates the page's).
    Show-DetailWindow @{ Row = $Row.PSObject.Copy(); Detail = $null; Picks = $null; Update = 'Update-UserDetail'; Read = 'Get-UserDetailRead'; CopyText = 'Get-UserDetailText'; Computers = $true } `
        'user_detail' ((Tr 'Propriétés de {0}') -f $Row.Name) $Owner $Icon
}

function Get-UserDetailRead($State) {
    # What Start-DetailRead runs for a user, and the functions it needs.
    # What the cache knows of the domain, and since when (Update-DomainCache keeps what changed after).
    @{ Command = 'Read-UserDetail'; Arguments = @($State.Row, $script:DomainCache[$State.Row.Domain], [datetime]::UtcNow)
       Functions = 'Get-ObjectGroup', 'Read-TokenGroup', 'Get-DomainOfSid', 'Get-DomainOfDN', 'Get-LdapText', 'Get-PdcFallback', 'Get-DomainFallback', 'Test-ServerDown' }
}

# Per domain, read once a session: its PDC and password policy (they hardly change). While the PDC is kept as down
# (PdcDown, when it failed or the DC in its place was last found, in UTC; PdcProblem, why), Fallback: the DC used in its
# place. An entry is replaced, never changed: a read under way in a runspace holds it.
$script:DomainCache = @{}

function Get-UserServer([string]$Domain) {
    # The DC a user's changes go to, the one Propriétés reads from next (Read-UserDetail, from the same entry): its
    # domain's PDC. Sent to any DC, a change would reach the PDC only later (an unlock, userAccountControl and pwdLastSet
    # aren't replicated at once), and the window, read again at once, would show the account as before. Looked up once
    # a session, on the thread the change itself is made on: a user's changes run on a search runspace (Start-ADWrite),
    # which gives what it looked up back to the window's (Merge-DomainCache). While the PDC is kept as down, the DC
    # used in its place (Get-PdcFallback); the domain itself (any DC) when the PDC can't be looked up, and that is kept
    # for as long, each lookup a wait.
    $known = $script:DomainCache[$Domain]
    $fallback = Get-PdcFallback $known
    if ($fallback) { return $fallback }
    if ($known -and $known.Pdc) { return $known.Pdc }
    $pdc = try { [string](Get-ADDomain -Server $Domain -ErrorAction Stop).PDCEmulator } catch { $null }
    $policy = if ($known) { $known.Policy }
    if (-not $pdc) {
        $script:DomainCache[$Domain] = @{ Pdc = $null; Policy = $policy; PdcDown = [datetime]::UtcNow; PdcProblem = $null; Fallback = $Domain }
        return $Domain
    }
    $script:DomainCache[$Domain] = @{ Pdc = $pdc; Policy = $policy; PdcDown = $null; PdcProblem = $null; Fallback = $null }
    $pdc
}

function Get-KnownUserServer([string]$Domain) {
    # What Get-UserServer gives when it needn't ask AD (the PDC known, or the DC used in its place); $null when it would
    # have to look the PDC up, a wait the window's thread leaves to a search runspace (Start-UserServerRead).
    $known = $script:DomainCache[$Domain]
    $fallback = Get-PdcFallback $known
    if ($fallback) { return $fallback }
    if ($known -and $known.Pdc) { return $known.Pdc }
    $null
}

function Invoke-OnUserServer([string]$Domain, [int]$At, [string]$Command, [object[]]$Arguments) {
    # On a search runspace: & $Command @Arguments, its argument $At the DC Get-UserServer gives for $Domain, looked up
    # here from the window's copy of $DomainCache. Result, and Cache for the window's (Merge-DomainCache).
    $Arguments = @($Arguments)
    $Arguments[$At] = Get-UserServer $Domain
    $result = & $Command @Arguments
    @{ Result = $result; Cache = $script:DomainCache }
}

function Start-UserServerRead {
    # Start-BackgroundRead for a read that goes where $Domain's changes go (Get-UserServer), given as its argument $At:
    # chosen on the window's thread when it's known, or else looked up on the read's runspace (Invoke-OnUserServer), so
    # the first read of a session doesn't freeze the window while AD names the PDC. $OnDone gets the read's own result
    # either way, and Stop-BackgroundRead finds the read by its Context's State as before.
    param(
        [Parameter(Mandatory)] [string]$Command,
        [object[]]$Arguments = @(),
        [string[]]$Functions = @(),
        [hashtable]$Variables = @{},
        [Parameter(Mandatory)] [scriptblock]$OnDone,
        $Context,
        [Parameter(Mandatory)] [string]$Domain,
        [Parameter(Mandatory)] [int]$At
    )
    $known = Get-KnownUserServer $Domain
    if ($known) {
        $Arguments = @($Arguments)
        $Arguments[$At] = $known
        Start-BackgroundRead -Command $Command -Arguments $Arguments -Functions $Functions -Variables $Variables -OnDone $OnDone -Context $Context
        return
    }
    $sent = $script:DomainCache.Clone()
    $state = if ($Context -is [hashtable] -and $Context.ContainsKey('State')) { $Context.State } else { $Context }
    Start-BackgroundRead -Command 'Invoke-OnUserServer' -Arguments @($Domain, $At, $Command, $Arguments) `
        -Functions (@($Command) + $Functions + 'Get-UserServer', 'Get-PdcFallback') -Variables ($Variables + @{ DomainCache = $sent.Clone() }) `
        -Context @{ State = $state; Inner = $Context; Sent = $sent; OnDone = $OnDone } -OnDone {
        param($wrap, $read, $problem, $timedOut)
        if ($read) { Merge-DomainCache $wrap.Sent $read.Cache }
        & $wrap.OnDone $wrap.Inner $(if ($read) { $read.Result }) $problem $timedOut
    }
}

function Update-DomainCache([string]$Domain, $Detail) {
    # What a Propriétés read found of the domain's PDC, kept for the next reads and the changes (Get-UserServer). What
    # a change found meanwhile (a PDC down, a DC found again in its place, after the read's start) is newer: kept.
    if (-not $Detail.Pdc) { return }
    $known = $script:DomainCache[$Domain]
    $down = if ($known -and $known.PdcDown -and $known.PdcDown -gt $Detail.Started) { $known }
            else { @{ PdcDown = $Detail.PdcDown; PdcProblem = $Detail.PdcProblem; Fallback = $(if ($Detail.PdcDown) { $Detail.Server }) } }
    $script:DomainCache[$Domain] = @{ Pdc = $Detail.Pdc; Policy = $Detail.Policy; PdcDown = $down.PdcDown; PdcProblem = $down.PdcProblem; Fallback = $down.Fallback }
}

function Get-PdcFallback($Known) {
    # While the domain's PDC is kept as down ($Known, its $DomainCache entry; for 5 minutes from when it failed), the
    # server used in its place; nothing when the PDC is to be tried.
    if ($Known -and $Known.PdcDown -and ([datetime]::UtcNow - $Known.PdcDown) -lt [timespan]::FromMinutes(5)) { $Known.Fallback }
}

function Get-DomainFallback([string]$Domain, [string]$Pdc) {
    # One writable DC of $Domain that answers, found by the DC locator, for the reads and the changes while its PDC
    # ($Pdc) doesn't: with the domain's name, a change and the read after it could each go to a different DC. The
    # domain's name when none is found, or only the PDC.
    $found = try { [string]@((Get-ADDomainController -Discover -DomainName $Domain -Service ADWS -Writable -ForceDiscover -ErrorAction Stop).HostName)[0] } catch { $null }
    if ($found -and $found -ne $Pdc) { $found } else { $Domain }
}

function Set-PdcDown([string]$Domain, [string]$Failed, [string]$Problem, [string]$Found) {
    # $Failed didn't answer: the domain's PDC, then kept as down for a while (Get-PdcFallback), or the DC used in its
    # place, then found again. Returns the DC to use instead (Get-DomainFallback, or $Found when a search runspace found
    # it already and made its change there: Register-ServerDown); nothing when $Failed is neither (the domain's own
    # name: no other to try) or is found again.
    $known = $script:DomainCache[$Domain]
    if (-not $known -or -not $known.Pdc -or $Failed -eq $Domain -or ($Failed -ne $known.Pdc -and $Failed -ne $known.Fallback)) { return }
    # Why the PDC isn't used, for the lockout card: kept when it's the DC in its place that failed.
    $why = if ($Failed -eq $known.Pdc) { $Problem } else { $known.PdcProblem }
    $fallback = if ($Found) { $Found } else { Get-DomainFallback $Domain $known.Pdc }
    if ($fallback -eq $Failed) { return }
    $script:DomainCache[$Domain] = @{ Pdc = $known.Pdc; Policy = $known.Policy; PdcDown = [datetime]::UtcNow; PdcProblem = $why; Fallback = $fallback }
    $fallback
}

function Register-ServerDown([string]$Domain, $Down) {
    # On the window's thread, what a read or change on a search runspace found (#256): $Down.Server not answering, and
    # the DC it used in its place ($Down.Fallback), kept for the next reads and changes (Set-PdcDown), so they go where
    # that change went. Left when a change has since chosen another DC: it's the newer.
    if (-not $Down) { return }
    $current = Get-PdcFallback $script:DomainCache[$Domain]
    if ($current -and $current -ne $Down.Server) { return }
    $null = Set-PdcDown $Domain $Down.Server $Down.Problem $Down.Fallback
}

function Invoke-UserChange([string]$Domain, [scriptblock]$Change, [string]$Server) {
    # & $Change <server>, for a change to a user of $Domain, on the DC its Propriétés read next (Get-UserServer): the
    # PDC, or while it's kept as down, the DC used in its place. A DC that doesn't answer (Set-PdcDown): the PDC kept as
    # down, or the DC in its place found again, and the change made once more on the one found, so a DC down doesn't
    # stop the changes and the next ones don't wait for it. $Server: only another domain's DC (a group's, from
    # Get-UserAsMember), used as is, nothing to fall back on; $Domain itself counts as none. Any other error is thrown.
    # Returns the server that took it.
    if ($Server -and $Server -ne $Domain) { $null = & $Change $Server; return $Server }
    $Server = Get-UserServer $Domain
    try { $null = & $Change $Server }
    catch {
        if (-not (Test-ServerDown $_)) { throw }
        $other = Set-PdcDown $Domain $Server $_.Exception.Message
        if (-not $other) { throw }
        $Server = $other
        $null = & $Change $Server
    }
    $Server
}

function Test-ServerDown($ErrorRecord) {
    # Whether an AD command failed because its DC didn't answer, not for what it was asked (access, policy…): the AD
    # module's exception in any language, the fake AD's message; either may be wrapped in another exception.
    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        if ($exception.GetType().Name -eq 'ADServerDownException' -or $exception.Message -match '^Unable to contact the server') { return $true }
    }
    $false
}

# Changes to users (and BitLocker keys) run in the background (Start-ADWrite), as the computers' do
# (Start-ComputerWrite): a slow DC, or the PDC looked up for the first time, doesn't freeze the window. On a search
# runspace, Invoke-UserChange picks the DC and falls back as it does on the window's thread, from a copy of
# $DomainCache. What it learns there (a PDC found, or found down) comes back to the window's (Merge-DomainCache). The
# changes under way, by what they change (« Unlock|<domain>|<DN> »): the same change asked for again meanwhile is
# ignored, as a second click on Déverrouiller would only unlock the account twice.
$script:ADWrites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
# What a change on a search runspace has done so far (Add-WriteProgress). When the DC stops answering, the window's
# thread can then tell what was done from what may have been. Set only there.
$script:WriteProgress = $null
# The seconds a change gets for its first object, and for each object after it (Get-WriteTimeout).
$script:WriteTimeoutFirst = 45
$script:WriteTimeoutEach = 5

function Get-WriteTimeout([int]$Count = 1) {
    # How long a change to $Count objects may wait for its DCs, in seconds. The first object gets 45: a PDC that's down
    # takes about 21 seconds to give up on (TCP's retries), then the DC found in its place (Invoke-UserChange) is asked
    # and makes the change. More than a read's 30, since a change cut short is a change Repère can't say was made. Each
    # other object gets 5 seconds more: it goes where the first went, a DC that answers, in well under a second.
    $script:WriteTimeoutFirst + $script:WriteTimeoutEach * [Math]::Max(0, $Count - 1)
}

function Get-WriteUnsureText([int]$Seconds) {
    # A change whose DC didn't answer in time may still have been made there: never said to have failed.
    (Tr 'pas de réponse du contrôleur de domaine après {0} secondes : la modification a peut-être été faite, vérifiez') -f $Seconds
}

function Add-WriteProgress($Key, $Value) {
    # On a search runspace: a step of a change done (its Key, a row's index or the step's name) and how it went
    # (Get-WriteAnswer reads it back).
    if ($null -ne $script:WriteProgress) { $script:WriteProgress[$Key] = $Value }
}

function Get-ADWriteFunction {
    # What a change needs on its search runspace besides its own command: Invoke-UserChange and what it calls.
    'Invoke-UserChange', 'Get-UserServer', 'Get-PdcFallback', 'Set-PdcDown', 'Get-DomainFallback', 'Test-ServerDown', 'Add-WriteProgress'
}

function Invoke-ADWrite([string]$Command, [object[]]$Arguments) {
    # On a search runspace: the change (& $Command @Arguments) as Result, and Cache, the runspace's $DomainCache once
    # it's done, for the window's thread (Merge-DomainCache).
    $result = & $Command @Arguments
    @{ Result = $result; Cache = $script:DomainCache }
}

function Merge-DomainCache($Sent, $Learnt) {
    # On the window's thread: what a change on a search runspace learnt of the domains' DCs ($Learnt, its
    # $DomainCache; $Sent, the copy it was given). Each entry it replaced is kept, unless the window's was meanwhile
    # replaced by a PDC found down later. An entry is replaced, never changed: one the runspace didn't replace is the
    # very one it was sent. The password policy a Propriétés read added meanwhile is kept with it.
    if (-not $Learnt) { return }
    foreach ($domain in @($Learnt.Keys)) {
        $new = $Learnt[$domain]
        $old = $Sent[$domain]
        if ([object]::ReferenceEquals($new, $old)) { continue }
        $current = $script:DomainCache[$domain]
        $replaced = $current -and -not [object]::ReferenceEquals($current, $old)
        if ($replaced -and $current.PdcDown -and (-not $new.PdcDown -or $current.PdcDown -gt $new.PdcDown)) { continue }
        if ($replaced -and -not $new.Policy -and $current.Policy) {
            $new = $new.Clone()
            $new.Policy = $current.Policy
        }
        $script:DomainCache[$domain] = $new
    }
}

function Test-ADWriteBusy([string[]]$Keys) {
    # Whether a change to one of $Keys is under way (Start-ADWrite).
    [bool]@($Keys | Where-Object { $script:ADWrites.Contains($_) }).Count
}

function Start-ADWrite {
    # A change in the background: Invoke-ADWrite, & $Command @Arguments on a search runspace with $Functions defined
    # there. $Window, the window it was asked from (the main one by default), stays usable, its pointer saying
    # something runs. $Keys: what it changes (« Unlock|<domain>|<DN> »); while it runs, a change to one of them is
    # ignored ($false). $Count: how many objects, for its time limit (Get-WriteTimeout). Then, on the window's thread,
    # & $OnDone $Context $Outcome. Result: what $Command returned. Problem: why it couldn't run, or the time limit.
    # TimedOut: the DC didn't answer in time; then Result is $null, what's in Progress (Add-WriteProgress) was done, and
    # the rest may have been (Get-WriteAnswer). Timeout: its time limit, in seconds. $Variables: more of the runspace's
    # script-scope variables, as Start-BackgroundRead's.
    param(
        [Parameter(Mandatory)] [string[]]$Keys,
        [Parameter(Mandatory)] [string]$Command,
        [object[]]$Arguments = @(),
        [string[]]$Functions = @(),
        [int]$Count = 1,
        [Parameter(Mandatory)] [scriptblock]$OnDone,
        $Context,
        $Window,
        [hashtable]$Variables = @{}
    )
    if (Test-ADWriteBusy $Keys) { return $false }
    if (-not $Window) { $Window = $script:win }
    $progress = [hashtable]::Synchronized(@{})
    $sent = $script:DomainCache.Clone()
    $timeout = Get-WriteTimeout $Count
    foreach ($key in $Keys) { $null = $script:ADWrites.Add($key) }
    Enter-BusyWindow $Window
    $write = @{ Keys = $Keys; Window = $Window; Sent = $sent; Progress = $progress; Timeout = $timeout; OnDone = $OnDone; Context = $Context }
    try {
        Start-BackgroundRead -Command 'Invoke-ADWrite' -Arguments @($Command, $Arguments) -Functions (@($Command) + $Functions + (Get-ADWriteFunction)) `
            -Variables ($Variables + @{ DomainCache = $sent.Clone(); WriteProgress = $progress }) -Timeout $timeout -Context $write -OnDone {
            param($write, $read, $problem, $timedOut)
            Complete-ADWrite $write $read $problem $timedOut
        }
    }
    catch {
        # Not started: the next click can try again.
        foreach ($key in $Keys) { $null = $script:ADWrites.Remove($key) }
        Exit-BusyWindow $Window
        throw
    }
    $true
}

function Complete-ADWrite($Write, $Read, [string]$Problem, [bool]$TimedOut) {
    # Start-ADWrite's change ended, or ran out of time: its keys free again, what it learnt of the DCs kept, then its
    # OnDone.
    foreach ($key in $Write.Keys) { $null = $script:ADWrites.Remove($key) }
    Exit-BusyWindow $Write.Window
    if ($Read) { Merge-DomainCache $Write.Sent $Read.Cache }
    if (-not $Problem -and -not $Read) { $Problem = Tr 'AD n''a rien renvoyé' }
    $outcome = @{ Result = $(if ($Read) { $Read.Result }); Problem = $Problem; TimedOut = $TimedOut; Progress = $Write.Progress; Timeout = $Write.Timeout }
    & $Write.OnDone $Write.Context $outcome
}

function Get-WriteAnswer($Outcome, $Key) {
    # What a change's outcome says of one of its steps ($Key, as Add-WriteProgress has it): Problem, why it wasn't done
    # ($null when it was); Unsure, $true when the DC stopped answering before it said; Value, what the step gave.
    if ($Outcome.Progress.ContainsKey($Key)) {
        $value = $Outcome.Progress[$Key]
        return @{ Problem = $value.Problem; Unsure = $false; Value = $value }
    }
    if ($Outcome.TimedOut) { return @{ Problem = $null; Unsure = $true; Value = $null } }
    $why = if ($Outcome.Problem) { $Outcome.Problem } else { Tr 'AD n''a rien renvoyé' }
    @{ Problem = $why; Unsure = $false; Value = $null }
}

function Get-WriteLine([string]$Name, $Answer, [int]$Timeout) {
    # A report's line for one object (Show-ActionReport): « ✔ jdupont », « ✖ jdupont : why », or « ⚠ jdupont : … »
    # when the change may have been made.
    if ($Answer.Unsure) { return (Tr '⚠ {0} : {1}') -f $Name, (Get-WriteUnsureText $Timeout) }
    if ($Answer.Problem) { return (Tr '✖ {0} : {1}') -f $Name, $Answer.Problem }
    "✔ $Name"
}

function Get-UserWriteKey([string]$Action, $Row) {
    # What a change to a user changes, for Start-ADWrite's keys: Activer and Désactiver the same thing, as do the
    # expiration's two choices, so one can't run while the other does.
    $what = switch ($Action) { { $_ -in 'Enable', 'Disable' } { 'Enabled' } { $_ -in 'Expiry', 'NoExpiry' } { 'Expiry' } default { $Action } }
    "$what|$($Row.Domain)|$($Row.DistinguishedName)"
}

function ConvertTo-WriteUser($Rows) {
    # What a change on a search runspace needs of each user: a copy of its login, domain and DN, rather than the page's
    # row, which the window's thread goes on changing.
    foreach ($row in @($Rows)) {
        [pscustomobject]@{ Login = [string]$row.Login; Domain = [string]$row.Domain; DistinguishedName = [string]$row.DistinguishedName }
    }
}

function Invoke-UserAccountWrite([string]$Action, $Rows, $Value) {
    # On a search runspace: $Action for each of $Rows (ConvertTo-WriteUser), in its domain, on the DC its Propriétés
    # reads from (Invoke-UserChange): Unlock, Enable, Disable, Expiry (the account expires at $Value) or NoExpiry. Each
    # one's Problem as it goes (Add-WriteProgress, by index), $null when it went well.
    $Rows = @($Rows)
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $row = $Rows[$i]
        $problem = try {
            $null = Invoke-UserChange $row.Domain {
                param($server)
                switch ($Action) {
                    'Unlock' { Unlock-ADAccount -Server $server -Identity $row.DistinguishedName -ErrorAction Stop }
                    'Enable' { Enable-ADAccount -Server $server -Identity $row.DistinguishedName -ErrorAction Stop }
                    'Disable' { Disable-ADAccount -Server $server -Identity $row.DistinguishedName -ErrorAction Stop }
                    'Expiry' { Set-ADAccountExpiration -Server $server -Identity $row.DistinguishedName -DateTime $Value -ErrorAction Stop }
                    'NoExpiry' { Clear-ADAccountExpiration -Server $server -Identity $row.DistinguishedName -ErrorAction Stop }
                    default { throw "Unknown action: $Action" }
                }
            }
            $null
        }
        catch { $_.Exception.Message }
        Add-WriteProgress $i @{ Problem = $problem }
    }
}

function Get-DetailOwner($State) {
    # The window a Propriétés' change says how it went over: its own, or the main one once it has closed.
    if ($State['Closed']) { $null } else { $State.Window }
}

function Start-UserDetailWrite($State, [string]$Action, [string]$Title, $Value, [string]$Done, [string]$Failed, [switch]$AfterRead) {
    # A change from a user's Propriétés (Invoke-UserAccountWrite's $Action, with $Value), in the background: the window
    # usable meanwhile, its pointer saying it runs; asked for again while it runs, it's ignored. Then $Done in its
    # toast (once the window has read the account again, with -AfterRead), or why not in a dialog over it ($Failed: {0}
    # the login, {1} why; « ✖ {0} : {1} » by default), and the window reads the account again.
    $row = $State.Row
    $null = Start-ADWrite -Keys @(Get-UserWriteKey $Action $row) -Command 'Invoke-UserAccountWrite' -Arguments @($Action, @(ConvertTo-WriteUser $row), $Value) `
        -Window $State.Window -Context @{ State = $State; Title = $Title; Done = $Done; Failed = $Failed; AfterRead = [bool]$AfterRead } -OnDone {
        param($write, $outcome)
        Complete-UserDetailWrite $write (Get-WriteAnswer $outcome 0) $outcome.Timeout
    }
}

function Complete-UserDetailWrite($Write, $Answer, [int]$Timeout) {
    # Start-UserDetailWrite's change done, failed, or perhaps done (its DC didn't answer in time): said, then the
    # window reads the account again, which shows whether it was. Closed meanwhile: a failure is said over the main
    # window, a success in no toast.
    $state = $Write.State
    $login = $state.Row.Login
    $owner = Get-DetailOwner $state
    if ($Answer.Unsure) {
        Show-Dialog -Title $Write.Title -Icon 'warning' -Tone 'warn' -Message ((Tr '⚠ {0} : {1}') -f $login, (Get-WriteUnsureText $Timeout)) -Owner $owner
    }
    elseif ($Answer.Problem) {
        $format = if ($Write.Failed) { $Write.Failed } else { Tr '✖ {0} : {1}' }
        Show-Dialog -Title $Write.Title -Message ($format -f $login, $Answer.Problem) -Owner $owner
    }
    elseif (-not $state['Closed']) {
        if ($Write.AfterRead) { $state.NoticeAfterRead = $Write.Done } else { Show-DetailNotice $state $Write.Done }
    }
    if (-not $state['Closed']) { Update-UserDetail $state }
}

function Get-DetailReadVariable {
    # The script's variables the reads use, for their runspace.
    @{
        domainList = $script:domainList; GroupTypes = $script:GroupTypes; GroupScopes = $script:GroupScopes; MemberKinds = $script:MemberKinds
        MemberListMax = $script:MemberListMax; MemberForeignMax = $script:MemberForeignMax; GlobalCatalog = $script:GlobalCatalog
        DomainSidMap = $script:DomainSidMap
    }
}

function Start-DetailRead($State) {
    # Reads the window's user or group in the background (what $State.Read, a function's name, says to run), with
    # « Lecture… » and Actualiser waiting meanwhile; then $State.Update with what was read. One read at a time: one
    # asked for meanwhile follows it. A first read that fails says why in the window, which stays (Actualiser).
    if ($State['Reading']) { $State.ReadAgain = $true; return }
    $State.Reading = $true
    $State.ReadAgain = $false
    Set-DetailReading $State $true
    $State.RefreshButton.IsEnabled = $false
    try {
        $read = & $State.Read $State
        # A read that goes where the object's changes go (Domain, and the argument At that names the DC) has that DC
        # looked up off the window's thread the first time (Start-UserServerRead).
        if ($read.ContainsKey('At')) { Start-UserServerRead @read -Variables (Get-DetailReadVariable) -Context $State -OnDone ${function:Complete-DetailRead} }
        else { Start-BackgroundRead @read -Variables (Get-DetailReadVariable) -Context $State -OnDone ${function:Complete-DetailRead} }
    }
    catch {
        $State.Reading = $false
        Set-DetailReading $State $false
        $State.RefreshButton.IsEnabled = $true
        $State.Body.Content = New-DetailMessage ((Tr 'Lecture impossible : {0}') -f $_.Exception.Message)
    }
}

function Complete-DetailRead {
    # What a window's read gives: its cards, or why not.
    param($state, $detail, $problem)
    # Closed meanwhile: its read was stopped (Stop-BackgroundRead), and there's nothing to show it in.
    if ($state['Closed']) { return }
    $state.Reading = $false
    Set-DetailReading $state $false
    $state.RefreshButton.IsEnabled = $true
    if ($problem -or -not $detail) {
        $why = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
        if ($state.Detail) { Show-DetailNotice $state ((Tr 'Non relu : {0}') -f $why) }
        else { $state.Body.Content = New-DetailMessage ((Tr 'Propriétés non lues : {0}') -f $why) }
    }
    else {
        & $state.Update $state $detail
        # By key: set only by a change that rereads (NoticeAfterRead), as Reading only once a read started.
        if ($state['NoticeAfterRead']) { Show-DetailNotice $state $state.NoticeAfterRead }
    }
    $state.NoticeAfterRead = $null
    if ($state.ReadAgain) { Start-DetailRead $state }
}

function Set-DetailReading($State, [bool]$On) {
    # « Lecture… » in the header, and the window's status for UI Automation (the UI tests wait for it to clear: a
    # value, in French whatever the language).
    $State.ReadingLabel.Visibility = if ($On) { 'Visible' } else { 'Collapsed' }
    [System.Windows.Automation.AutomationProperties]::SetItemStatus($State.Window, $(if ($On) { 'Lecture' } else { '' }))
}

function New-DetailMessage([string]$Text) {
    # A line in place of the cards: before they're read, or why they couldn't be (in French, ConvertTo-FrenchError).
    $block = [System.Windows.Controls.TextBlock]::new()
    $block.Text = ConvertTo-FrenchError $Text
    $block.TextWrapping = 'Wrap'
    $block.Margin = [System.Windows.Thickness]::new(4, 8, 4, 8)
    $block.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Txt.Muted')
    $block
}

# The Propriétés windows open, users' and groups', by object ($Prefix|domain|DN), in the order they opened; and how
# many can be open at once. Measured with the fake AD: a group's listing 200 members (the most one lists) takes some
# 30 MB, a user's a few, so ten stay around 300 MB at worst.
# By key whatever its case, as AD and Sync-UserPageRow compare names.
$script:DetailWindows = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)
$script:DetailWindowMax = 10

function Get-DetailWindowKey([string]$Prefix, $Row) {
    "$Prefix|$($Row.Domain)|$($Row.DistinguishedName)"
}

function Show-OpenDetailWindow([string]$Key) {
    # The Propriétés window of $Key, when one is open: brought to the front ($true).
    $open = $script:DetailWindows[$Key]
    if (-not $open) { return $false }
    if ($open.WindowState -eq 'Minimized') { $open.WindowState = 'Normal' }
    $null = $open.Activate()
    $true
}

function Test-DetailWindowRoom([string]$Name, $Opener) {
    # Whether another Propriétés may open; at $DetailWindowMax, says so over $Opener, with Tout fermer.
    if ($script:DetailWindows.Count -lt $script:DetailWindowMax) { return $true }
    Show-Dialog -Title (Tr 'Propriétés') -Icon 'info' -Tone 'warn' -Owner $Opener `
        -Heading ((Tr '{0} fenêtres Propriétés sont ouvertes') -f $script:DetailWindows.Count) `
        -Message ((Tr "C'est le maximum : fermez-en une avant d'ouvrir celle de {0}.") -f $Name) `
        -OkText (Tr 'Tout fermer') -OnOk { foreach ($window in @($script:DetailWindows.Values)) { $window.Close() } }
    $false
}

function Update-OpenUserDetail($Rows) {
    # After a change made on the Utilisateurs page: the open Propriétés of these accounts read themselves again.
    foreach ($row in @($Rows)) {
        $open = $script:DetailWindows[(Get-DetailWindowKey 'user_detail' $row)]
        if ($open) { & $open.Tag.Update $open.Tag }
    }
}

function Update-OpenGroupDetail($Rows) {
    # After a change made on the Groupes page: the open Propriétés of these groups read themselves again.
    foreach ($row in @($Rows)) {
        $open = $script:DetailWindows[(Get-DetailWindowKey 'group_detail' $row)]
        if ($open) { & $open.Tag.Update $open.Tag }
    }
}

function Show-DetailWindow($State, [string]$Prefix, [string]$Title, $Opener, $Icon, [string]$Glyph = 'users') {
    # The Propriétés window of a user, a group or a computer, its controls named after $Prefix (user_detail,
    # group_detail, computer_detail): the header, the cards that $State.Update fills (a function's name: called with
    # the state alone, it reads in the background, and again with what was read), Actualiser and F5, Copier
    # ($State.CopyText, a function's name too), and Échap. It opens at once, the cards read after. $Glyph: the icon in
    # the header's circle, for a window without initials (a group's, a computer's).
    # A window of its own, as Caractéristiques: the main window stays usable, and several can be side by side. One per
    # object: opening it again brings it to the front. Owned by the main window, which closes them as it closes;
    # $Opener is the window it was opened from, which it opens over and which, when it's another Propriétés, reads itself
    # again once this one closes. At most $DetailWindowMax at once.
    $key = Get-DetailWindowKey $Prefix $State.Row
    if (Show-OpenDetailWindow $key) { return }
    if (-not (Test-DetailWindowRoom $State.Row.Name $Opener)) { return }
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:UserDetailXaml.Replace('user_detail_', "$($Prefix)_").Replace('{{icon:users:26}}', "{{icon:$($Glyph):26}}")))
    $window = [System.Windows.Window]::new()
    $window.Title = $Title
    $window.Icon = $Icon
    $window.Owner = $script:win
    $window.Width = 880
    $window.Height = [Math]::Min(860, [System.Windows.SystemParameters]::WorkArea.Height - 40)
    $window.MinWidth = 640
    $window.MinHeight = 420
    # Centered over the main window, as WPF places it (maximized, or on another screen, too). Opened from another
    # Propriétés, shown as it is (not maximized): a little lower and to the right of it. Either way within the work area
    # of its screen, above the taskbar (Set-WindowChrome, Set-WindowInWorkArea): at its edge, it's moved back in, so
    # it's only as much lower as the screen leaves room for, or over the other one.
    $window.WindowStartupLocation = 'CenterOwner'
    if ($Opener -and $Opener -ne $script:win -and $Opener.IsVisible -and $Opener.WindowState -eq 'Normal' -and $Opener.Tag -is [hashtable] -and $Opener.Tag['Update']) {
        $window.WindowStartupLocation = 'Manual'
        $window.Left = $Opener.Left + 28
        $window.Top = $Opener.Top + 28
    }
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $window.Content = $root
    $root.FindName("$($Prefix)_caption").Text = $Title
    # The logo as an image: $Icon, the window's icon, holds every size of compass.ico.
    if ($Icon) { $root.FindName("$($Prefix)_icon").Source = $script:logoImage } else { $root.FindName("$($Prefix)_icon").Visibility = 'Collapsed' }
    Set-WindowChrome $window -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-OwnerFocus $window
    Register-DetailFoldBar $root $Prefix

    foreach ($part in 'Body', 'Status', 'Title', 'Subtitle', 'Initials', 'Glyph', 'Chips', 'Toast') {
        $State[$part] = $root.FindName("$($Prefix)_$($part.ToLowerInvariant())")
    }
    $State.Window = $window
    $State.Key = $key
    $State.Opener = if ($Opener -and $Opener.Tag -is [hashtable] -and $Opener.Tag['Update']) { $Opener }
    # Whatever window it was opened from, the focus goes back to it when it closes (Register-OwnerFocus).
    $State.ReturnTo = $Opener
    $State.ReadingLabel = $root.FindName("$($Prefix)_reading")
    $State.RefreshButton = $root.FindName("$($Prefix)_refresh")
    $State.ToastTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $State.ToastTimer.Interval = [timespan]::FromSeconds(5)
    $State.ToastTimer.Tag = $State.Toast
    $State.ToastTimer.Add_Tick({ param($timer) $timer.Stop(); $timer.Tag.Visibility = 'Collapsed' })
    $window.Tag = $State
    $State.Title.Text = $State.Row.Name
    $State.Body.Content = New-DetailMessage (Tr 'Lecture…')
    & $State.Update $State
    $root.FindName("$($Prefix)_refresh").Add_Click({ param($button) $state = [System.Windows.Window]::GetWindow($button).Tag; $state.NoticeAfterRead = Tr 'Relu.'; & $state.Update $state })
    $root.FindName("$($Prefix)_copy").Add_Click({
        param($button)
        $state = [System.Windows.Window]::GetWindow($button).Tag
        if (-not $state.Detail) { return }
        $copied = Set-ClipboardText (& $state.CopyText $state)
        Show-CopyFeedback $button $copied
        Show-DetailNotice $state $(if ($copied) { Tr 'Copié.' } else { Tr 'Non copié : le presse-papiers est occupé par un autre programme.' })
    })
    # Ordinateurs (a user's): the search runs on the main window's Ordinateurs page, under this window, which stays.
    if ($State['Computers']) {
        $computers = $root.FindName("$($Prefix)_computers")
        $computers.Visibility = 'Visible'
        $computers.Add_Click({
            param($button)
            $state = [System.Windows.Window]::GetWindow($button).Tag
            Find-UserComputer $state.Row.Name
            Show-DetailNotice $state (Tr 'Recherche lancée dans Ordinateurs.')
        })
    }
    # F5 reads it again; Échap cancels a card's edit first (Undo-UserCardEdit), then closes it.
    $window.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::F5) { $e.Handled = $true; $control.Tag.NoticeAfterRead = Tr 'Relu.'; & $control.Tag.Update $control.Tag }
        elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $e.Handled = $true
            if (-not (Undo-UserCardEdit $control.Tag)) { $control.Close() }
        }
    })
    $window.Add_Closed({
        param($control)
        $state = $control.Tag
        $state.Closed = $true
        $state.ToastTimer.Stop()
        if ($state['FilterTimer']) { $state.FilterTimer.Stop() }
        Stop-BackgroundRead $state
        $script:DetailWindows.Remove($state.Key)
        # The window it was opened from, still open: it reads itself again (a membership may have changed here). Not
        # while the main window closes them all.
        $opener = $state.Opener
        if ($opener -and $opener.IsVisible -and -not $script:Settings.Exiting) { & $opener.Tag.Update $opener.Tag }
    })

    # Not counted in $search.Dialogs: a search may replace the page's rows meanwhile, since the window has its own.
    $script:DetailWindows[$key] = $window
    $window.Show()
}
