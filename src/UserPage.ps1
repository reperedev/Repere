# Utilisateurs: the main window's second page (its tab in the title bar). Users are found by name, login or email (AD's
# ambiguous name resolution) or from a pasted list of them, or listed when locked out or disabled, in one domain or all
# of them, in the background like computers. Their actions: Déverrouiller, and Nouveau mot de passe… (a reset), whose
# temporary password is generated (easy to dictate) or the one set in Paramètres › Mots de passe. Deleting users is
# deliberately left out.
# Its search, count, filter, Exporter, Copier, keys and columns are those of Groupes too (SearchPage.ps1): the page
# hashtable says what's the users'. Dot-sourced by the main script, after Theme.ps1 and SearchPage.ps1; uses its
# search runspaces ($searchPool), domains and dialogs.
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

$script:PasswordSettingPath = Get-SettingPath 'motdepasse.json'

# The search types: the LDAP clause each adds, whether it needs text (« Verrouillés » alone lists every locked account
# of the domain), what its text matches (AD's ambiguous name resolution, or the description), and what the scope then
# says. Every search is for people: (objectCategory=person)(objectClass=user). LockedOnly: only the accounts still
# locked (the search script's). Each type's name is both what the type box shows and its key there, in this run's
# language: it's never saved.
$script:UserSearchTypes = [ordered]@{
    (Tr 'Nom, identifiant ou courriel') = @{ Id = 'Name'; Clause = ''; NeedsText = $true; Match = '(anr={0})'; Prompt = (Tr 'Entrez un nom, un identifiant ou un courriel')
                                             Tag = (Tr 'Nom, identifiant ou courriel (ex. bert)'); Tip = (Tr "Le début du prénom, du nom, de l'identifiant ou du courriel (Ctrl+F)") }
    (Tr 'Verrouillés')                  = @{ Id = 'Locked'; Clause = '(lockoutTime>=1)'; NeedsText = $false; Match = '(anr={0})'; LockedOnly = $true; ScopeText = (Tr 'verrouillés')
                                             Tag = (Tr 'Nom (facultatif)'); Tip = (Tr "Facultatif : le début du nom, de l'identifiant ou du courriel (Ctrl+F)") }
    (Tr 'Désactivés')                   = @{ Id = 'Disabled'; Clause = '(userAccountControl:1.2.840.113556.1.4.803:=2)'; NeedsText = $false; Match = '(anr={0})'; ScopeText = (Tr 'désactivés')
                                             Tag = (Tr 'Nom (facultatif)'); Tip = (Tr "Facultatif : le début du nom, de l'identifiant ou du courriel (Ctrl+F)") }
    (Tr 'Description contient')         = @{ Id = 'Description'; Clause = ''; NeedsText = $true; Match = '(description=*{0}*)'; Prompt = (Tr 'Entrez une partie de la description')
                                             Tag = (Tr 'Description (ex. sauvegarde)'); Tip = (Tr 'Une partie de la description (Ctrl+F)') }
    # Each entry as it is (indexed attributes, an exact match): with an @, a UPN or an email; with a space (one per
    # line), the display name or the account's name; otherwise a login.
    (Tr "Liste d'identifiants")         = @{ Id = 'List'; Clause = ''; NeedsText = $true; List = 'ConvertTo-UserEntryList'
                                             ListMatch = {
                                                 param($Entry)
                                                 if ($Entry -match '\s') { "(displayName=$Entry)(name=$Entry)" }
                                                 elseif ($Entry.Contains('@')) { "(userPrincipalName=$Entry)(mail=$Entry)" }
                                                 else { "(sAMAccountName=$Entry)" }
                                             }
                                             Prompt = (Tr 'Entrez les identifiants ou les courriels (ex. jbertrand, lperrin@demo.local)')
                                             TooMany = (Tr 'Au plus {0} identifiants à la fois ({1} entrés)')
                                             Tag = (Tr 'Identifiants, courriels ou noms, séparés par des virgules (ex. jbertrand, Léa Perrin)')
                                             Tip = (Tr 'Identifiants, courriels ou noms entiers, séparés par des virgules (Ctrl+F)') }
}

# The words of a generated password: short, common, without accents, so it reads and types easily on any keyboard.
$script:PasswordWords = 'Pomme', 'Nuage', 'Soleil', 'Lune', 'Jardin', 'Bateau', 'Plage', 'Neige', 'Orange', 'Citron', 'Fleur', 'Arbre',
    'Piano', 'Velo', 'Train', 'Avion', 'Lapin', 'Tigre', 'Cerise', 'Prune', 'Tomate', 'Melon', 'Olive', 'Biscuit', 'Gateau', 'Sucre',
    'Cafe', 'Ocean', 'Vague', 'Sable', 'Roche', 'Colline', 'Pont', 'Route', 'Phare', 'Moulin', 'Ferme', 'Hibou', 'Renard', 'Castor',
    'Canard', 'Mouton', 'Cheval', 'Panda', 'Koala', 'Tulipe', 'Violon', 'Guitare', 'Tambour', 'Fusee', 'Comete', 'Planete', 'Etoile',
    'Montagne', 'Riviere', 'Prairie', 'Erable', 'Sapin', 'Bouleau', 'Cactus'
# In English: as short and common, and spelled as they sound (no homophone, like Sun or Rose, nor silent letter).
$script:PasswordWordsEnglish = 'Apple', 'Banana', 'Cherry', 'Lemon', 'Orange', 'Melon', 'Olive', 'Peach', 'Grape', 'Mango', 'Cookie', 'Sugar',
    'Coffee', 'Honey', 'Pepper', 'Cloud', 'Snow', 'Ocean', 'River', 'Lake', 'Hill', 'Forest', 'Valley', 'Bridge', 'Garden', 'Farm',
    'Beach', 'Sand', 'Rock', 'Planet', 'Comet', 'Rocket', 'Star', 'Moon', 'Piano', 'Guitar', 'Violin', 'Drum', 'Train', 'Boat', 'Bike',
    'Tiger', 'Rabbit', 'Panda', 'Koala', 'Zebra', 'Lion', 'Duck', 'Turtle', 'Kitten', 'Tulip', 'Maple', 'Cactus', 'Candle', 'Pillow',
    'Basket', 'Button', 'Pencil', 'Window', 'Silver'

function New-TemporaryPassword {
    # Three words and two digits, e.g. Pomme-Nuage-Lapin-47: 20 characters or so, with capitals, small letters, digits and
    # a symbol, which Windows' complexity rules ask for, yet easy to dictate. Only a start: the person always changes it
    # at the next logon (Show-UserResetDialog). Drawn with a cryptographic generator. The words are in this run's language.
    $words = if ($script:UILanguage -eq 'en') { $script:PasswordWordsEnglish } else { $script:PasswordWords }
    $pick = { $words[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($words.Count)] }
    $first = & $pick
    do { $second = & $pick } while ($second -eq $first)
    do { $third = & $pick } while ($third -eq $first -or $third -eq $second)
    "$first-$second-$third-$([System.Security.Cryptography.RandomNumberGenerator]::GetInt32(10, 100))"
}

function Read-PasswordSetting {
    # Paramètres › Mots de passe: Mode (Generated, or Default: always the same temporary password), the default password
    # itself (kept encrypted for the Windows account, DPAPI; $null when none or unreadable), and MustChange (« doit le
    # changer à sa prochaine connexion » for a password typed in « Autre », on by default: the other two always are).
    $setting = @{ Mode = 'Generated'; Default = $null; MustChange = $true }
    $saved = Read-JsonSetting $script:PasswordSettingPath Mode, MustChange, Default
    if (-not $saved) { return $setting }
    if ($saved.Mode -eq 'Default') { $setting.Mode = 'Default' }
    if ($null -ne $saved.MustChange) { $setting.MustChange = [bool]$saved.MustChange }
    if ($saved.Default) {
        # Encrypted for another Windows account, or on another computer: none, and said in the console.
        try {
            $secure = ConvertTo-SecureString -String ([string]$saved.Default) -ErrorAction Stop
            $setting.Default = [System.Net.NetworkCredential]::new('', $secure).Password
        }
        catch { Write-Host "motdepasse.json : mot de passe par défaut illisible ici : $_" }
    }
    $setting
}

function Save-PasswordSetting($Setting) {
    $protected = $null
    if ($Setting.Default) {
        $secure = [securestring]::new()
        foreach ($char in $Setting.Default.ToCharArray()) { $secure.AppendChar($char) }
        $protected = ConvertFrom-SecureString -SecureString $secure
    }
    Save-JsonSetting $script:PasswordSettingPath ([ordered]@{ Mode = $Setting.Mode; MustChange = [bool]$Setting.MustChange; Default = $protected })
}

function Get-UserPasswordText {
    # The texts of Get-UserPasswordState, looked up once for a search's thousands of rows.
    @{
        Never = Tr "N'expire jamais"; NeverTip = Tr "Le mot de passe n'expire jamais."
        Change = Tr 'À changer à la connexion'; ChangeTip = Tr 'Le mot de passe devra être changé à la prochaine connexion.'
        At = Tr '{0} à {1}'
        ExpiresTip = Tr 'Expire le {0}.'; Expired = Tr 'Expiré'; ExpiredTip = Tr 'Expiré le {0}.'
        Today = Tr "Expire aujourd'hui"; Tomorrow = Tr 'Expire demain'; InDays = Tr 'Expire dans {0} jours'; On = Tr 'Expire le {0}'
        Soon = Tr 'Expire dans 14 jours ou moins'; Later = Tr 'Expire dans plus de 14 jours'
        Culture = Get-TextCulture
    }
}

function Get-UserPasswordState($User, [datetime]$Today, [hashtable]$Text) {
    # Mot de passe, for a row of the page: when it expires, from msDS-UserPasswordExpiryTimeComputed (0: to change at
    # the next logon; the largest value: never). Its tone and sort key are what the code goes by, the text only shown;
    # its state is what the column's filter lists. In a search's runspace for each row, and for the row a Propriétés
    # window reads again (Update-UserDetail).
    $expiry = [int64]$User.'msDS-UserPasswordExpiryTimeComputed'
    $password, $tone, $tip, $sort, $state = if ($User.PasswordNeverExpires -or $expiry -eq [int64]::MaxValue) {
        $Text.Never, '', $Text.NeverTip, [int64]::MaxValue, $Text.Never
    }
    elseif ($expiry -le 0) { $Text.Change, 'warn', $Text.ChangeTip, [int64]0, $Text.Change }
    else {
        $culture = $Text.Culture
        $date = [datetime]::FromFileTime($expiry)
        $days = [int][Math]::Floor(($date.Date - $Today).TotalDays)
        $exact = $Text.At -f $date.ToString('d', $culture), $date.ToString('t', $culture)
        $expires = $Text.ExpiresTip -f $exact
        if ($date -lt (Get-Date)) { $Text.Expired, 'danger', ($Text.ExpiredTip -f $exact), $expiry, $Text.Expired }
        elseif ($days -le 0) { $Text.Today, 'warn', $expires, $expiry, $Text.Soon }
        elseif ($days -eq 1) { $Text.Tomorrow, 'warn', $expires, $expiry, $Text.Soon }
        elseif ($days -le 14) { ($Text.InDays -f $days), $(if ($days -le 7) { 'warn' } else { '' }), $expires, $expiry, $Text.Soon }
        else { ($Text.On -f $date.ToString('d', $culture)), '', $expires, $expiry, $Text.Later }
    }
    @{ Password = $password; PasswordTone = $tone; PasswordTip = $tip; PasswordSort = $sort; PasswordState = $state }
}

# A user search, in a search runspace: the users of one domain, as rows. The row builder's helpers (Format-Age,
# Get-OUPath) come from ComputerPage.ps1's $rowBuilderScript; Get-UserPasswordText and Get-UserPasswordState are
# written into it (where it says so), as the window has them too.
$script:UserSearchScript = {
    param([string]$Domain, [string]$LdapFilter, [bool]$LockedOnly, [string]$RowBuilder, [datetime]$Today, [int]$Limit, [string[]]$Entries, $Clock)
    # {{password functions}}
    try {
        if (-not (Get-Command Format-Age -ErrorAction SilentlyContinue)) { . ([scriptblock]::Create($RowBuilder)) }
        # The page's time limit counts from here, until AD answers: its first user, or the end of a query that found
        # none (New-SearchClock). Without a clock (Find-UserRow), no limit.
        if ($Clock) { $Clock.Started = [datetime]::UtcNow }
        $heard = { process { if ($Clock -and -not $Clock.Answered) { $Clock.Answered = $true }; $_ } end { if ($Clock) { $Clock.Answered = $true } } }
        $properties = 'DisplayName', 'GivenName', 'Surname', 'mail', 'Title', 'Department', 'Description', 'Enabled', 'LockedOut', 'LastLogonDate',
                      'PasswordExpired', 'PasswordNeverExpires', 'PasswordLastSet', 'msDS-UserPasswordExpiryTimeComputed', 'UserPrincipalName'
        # $Limit at most (none when 0): AD is asked for one more, to tell there are others. Not with LockedOnly: AD can't
        # tell who's still locked, and the limit counts only them.
        $bounded = if ($Limit -gt 0 -and -not $LockedOnly) { @{ ResultSetSize = $Limit + 1 } } else { @{} }
        # How long AD took, then the rows: said in the search time's tooltip.
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $users = @(Get-ADUser -Server $Domain -LDAPFilter $LdapFilter -Properties $properties @bounded -ErrorAction Stop | & $heard)
        $queryTime = $watch.ElapsedMilliseconds
        # lockoutTime stays set after the lockout duration has passed: LockedOut says whether it's still locked.
        if ($LockedOnly) { $users = @($users | Where-Object LockedOut) }
        $truncated = $Limit -gt 0 -and $users.Count -gt $Limit
        if ($truncated) { $users = @($users | Select-Object -First $Limit) }
        # The rows' texts, looked up once rather than for each of thousands of rows.
        $text = @{ Disabled = Tr 'Désactivé'; Locked = Tr 'Verrouillé'; Active = Tr 'Actif' }
        $passwordText = Get-UserPasswordText
        $rows = foreach ($user in $users) {
            $name = if ($user.DisplayName) { [string]$user.DisplayName } else { [string]$user.Name }
            # Only shown (and sorted): what the code goes by is IsEnabled and IsLocked.
            $state = if (-not $user.Enabled) { $text.Disabled } elseif ($user.LockedOut) { $text.Locked } else { $text.Active }
            $password = Get-UserPasswordState $user $Today $passwordText
            $lastLogon = $user.LastLogonDate
            $row = [pscustomobject]@{
                Name              = $name
                Login             = [string]$user.SamAccountName
                Title             = [string]$user.Title
                Department        = [string]$user.Department
                Description       = [string]$user.Description
                Mail              = [string]$user.mail
                Domain            = $Domain
                DistinguishedName = [string]$user.DistinguishedName
                OUPath            = Get-OUPath ([string]$user.DistinguishedName)
                State             = $state
                IsEnabled         = [bool]$user.Enabled
                IsLocked          = [bool]$user.LockedOut
                LastLogon         = if ($lastLogon) { $lastLogon.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
                LastLogonAgo      = Format-Age $lastLogon $Today
                LastLogonTip      = Format-TextDate $lastLogon
                IsStale           = -not $lastLogon -or ($Today - $lastLogon.Date).TotalDays -ge 90
                Password          = $password.Password
                PasswordTone      = $password.PasswordTone
                PasswordTip       = $password.PasswordTip
                PasswordSort      = $password.PasswordSort
                PasswordState     = $password.PasswordState
                # AD refuses « must change it at the next logon » for such an account (Nouveau mot de passe…).
                PasswordNeverExpires = [bool]$user.PasswordNeverExpires
                Text              = ''
            }
            $row.Text = "$($row.Name) $($row.Login) $($row.Title) $($row.Department) $($row.Description) $($row.Mail) $($row.OUPath)".ToLowerInvariant()
            $row
        }
        $rows = @($rows | Sort-Object Name)
        # Liste d'identifiants: the entries these users answer to, as the filter matched them (whatever their case).
        $matched = @()
        if ($Entries) {
            $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($user in $users) {
                foreach ($key in $user.SamAccountName, $user.UserPrincipalName, $user.mail, $user.DisplayName, $user.Name) { if ($key) { $null = $keys.Add([string]$key) } }
            }
            $matched = @($Entries | Where-Object { $keys.Contains($_) })
        }
        [pscustomobject]@{ Domain = $Domain; Rows = $rows; Error = $null; Truncated = $truncated; Matched = $matched
                           Timing = @{ Query = $queryTime; Rows = $watch.ElapsedMilliseconds - $queryTime; Count = $rows.Count } }
    }
    catch {
        [pscustomobject]@{ Domain = $Domain; Rows = @(); Error = $_.Exception.Message; Truncated = $false; Matched = @(); Timing = $null }
    }
}.ToString().Replace('# {{password functions}}', (@(foreach ($name in 'Get-UserPasswordText', 'Get-UserPasswordState') {
    "function $name {$([Environment]::NewLine)$((Get-Item "function:$name").Definition)$([Environment]::NewLine)}"
}) -join [Environment]::NewLine))

# The page once built (Initialize-UserPage), whether it's shown, its rows and the search under way, and what makes it
# the users' page (SearchPage.ps1 says what each key is). Its columns: see Initialize-PageColumn (Hidden are hidden
# until chosen in Colonnes).
$script:UserPage = @{ Root = $null; Shown = $false; Rows = $null; View = $null; Search = $null; Timer = $null; Filter = ''; FilterTimer = $null; Errors = $null; MultiDomain = $false
                      LastRequest = $null; Truncated = $null; NotFound = @(); Unanswered = @(); TimedOut = @()
                      Prefix = 'user'; Types = $script:UserSearchTypes; SearchSetting = 'Users'
                      Ldap = '(&(objectCategory=person)(objectClass=user){0})'; Script = $script:UserSearchScript
                      # The date the ages are counted from: the same for every domain of a search.
                      Parameters = { param($Type) @{ LockedOnly = [bool]$Type['LockedOnly']; Today = (Get-Date).Date } }
                      Action = 'Update-UserAction'; Detail = 'Show-UserDetail'; RowProperty = 'Login'
                      Copy = 'Login'; Copied = @{ Login = (Tr 'identifiants'); Name = (Tr 'noms'); Mail = (Tr 'courriels') }
                      # The columns shown, each under its header (Get-ExportField). Dernière connexion writes the date
                      # its sort key is (yyyy-MM-dd HH:mm), not the age shown. Mot de passe, what it shows (« Expire
                      # dans 3 jours » is only true today) then, in a column of its own, when it expires, the same way:
                      # empty when it never does or is to be changed at the next logon. The distinguished name last,
                      # always: Domaine shows only after a search of several domains.
                      Export = @{
                          Title = (Tr 'Exporter les utilisateurs'); FileName = (Tr 'Repere_utilisateurs_{0:yyyy-MM-dd}.csv')
                          Fields = @{
                              PasswordSort = @{ Value = 'Password' }, @{ Header = (Tr 'Expiration du mot de passe'); Value = {
                                  param($Row)
                                  # The expiry's file time (Get-UserPasswordState); 0 and the largest value aren't dates.
                                  $expiry = [int64]$Row.PasswordSort
                                  if ($expiry -gt 0 -and $expiry -lt [int64]::MaxValue) { [datetime]::FromFileTime($expiry).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) }
                              } }
                          }
                          Last = , @{ Header = (Tr 'Nom distinctif'); Value = 'DistinguishedName' }
                      }
                      Setting = 'UserColumns'; Hidden = 'Mail', 'Description'
                      # Nom's and Identifiant's filters by the text they contain, Dernière connexion's by how long ago,
                      # Mot de passe's by state (ColumnFilter.ps1).
                      ColumnFilter = $null
                      FilterSpecs = { @{
                          Name         = @{ Mode = 'Text' }
                          Login        = @{ Mode = 'Text' }
                          LastLogon    = @{ Mode = 'Age' }
                          PasswordSort = @{ Property = 'PasswordState'; Order = (Tr 'Expiré'), (Tr 'Expire dans 14 jours ou moins'), (Tr 'Expire dans plus de 14 jours'), (Tr 'À changer à la connexion'), (Tr "N'expire jamais") }
                      } }
                      Columns = @{ ByKey = [ordered]@{}; Shown = @{}; Items = @{}; Default = $null; Loaded = ''; Updating = $false; Menu = $null } }

$script:UserPageXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <!-- What can be done to the selected users. -->
  <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.ActionRowMargin}">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal">
      <Button x:Name="user_details" Style="{StaticResource Btn.Primary}" Margin="0,0,8,0" IsEnabled="False" ToolTip="Tout le compte, ses groupes et son expiration (double-clic)">
        <StackPanel Orientation="Horizontal">{{icon:user}}<TextBlock Text="Propriétés…" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="user_unlock" IsEnabled="False" ToolTip="Déverrouiller les comptes sélectionnés qui sont verrouillés">
        <StackPanel Orientation="Horizontal">{{icon:unlock}}<TextBlock Text="Déverrouiller" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="user_reset" Margin="8,0,0,0" IsEnabled="False" ToolTip="Un mot de passe généré, celui par défaut ou un autre (un utilisateur à la fois)">
        <StackPanel Orientation="Horizontal">{{icon:password}}<TextBlock Text="Nouveau mot de passe…" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <!-- Désactiver… the selected accounts, or Activer when all of them are disabled (as the computers' button). -->
      <Button x:Name="user_toggle" Margin="8,0,0,0" IsEnabled="False" ToolTip="Désactiver les comptes sélectionnés, ou les activer s'ils sont tous désactivés">
        <StackPanel Orientation="Horizontal">
          <Grid x:Name="user_toggle_disable_icon">{{icon:ban}}</Grid>
          <Grid x:Name="user_toggle_enable_icon" Visibility="Collapsed">{{icon:checkcircle}}</Grid>
          <TextBlock x:Name="user_toggle_text" Text="Désactiver…" Margin="8,0,0,0"/>
        </StackPanel>
      </Button>
      <Button x:Name="user_compare" Margin="8,0,0,0" IsEnabled="False" ToolTip="Les groupes de deux utilisateurs sélectionnés, côte à côte">
        <StackPanel Orientation="Horizontal">{{icon:columns}}<TextBlock Text="Comparer les groupes…" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="user_groups_add" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" IsEnabled="False" ToolTip="Ajouter à un groupe… (les utilisateurs sélectionnés)">{{icon:userplus}}</Button>
      <Button x:Name="user_groups_remove" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" IsEnabled="False" ToolTip="Retirer d'un groupe… (les utilisateurs sélectionnés)">{{icon:userminus}}</Button>
      <Button x:Name="user_copy" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" IsEnabled="False" ToolTip="Copier l'identifiant (Ctrl+C)">{{icon:copy}}</Button>
    </StackPanel>
    <TextBlock x:Name="user_selection" Grid.Column="2" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Text="Aucune sélection"/>
  </Grid>

  <!-- The search: the domain, what to look for, the text. Entrée searches. Above the rows below it (ZIndex), for what a
       search is missing (user_search_hint). -->
  <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.SearchRowMargin}" Panel.ZIndex="1">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/>
      <ColumnDefinition Width="10"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <ComboBox x:Name="user_domain" MinWidth="170" Height="{DynamicResource R.BarHeight}" Margin="0,0,6,0" VerticalContentAlignment="Center" ToolTip="Domaine" ItemContainerStyle="{StaticResource Combo.Item}"/>
    <ComboBox x:Name="user_search_type" Grid.Column="1" MinWidth="230" Height="{DynamicResource R.BarHeight}" VerticalContentAlignment="Center" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Type de recherche"/>
    <Border x:Name="user_search_field" Grid.Column="3" Style="{StaticResource Field}" Height="{DynamicResource R.BarHeight}">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border Margin="12,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search}}</Border>
        <TextBox x:Name="user_query" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Nom, identifiant ou courriel (ex. bert)"
                 ToolTip="Le début du prénom, du nom, de l'identifiant ou du courriel (Ctrl+F)"/>
        <!-- The last searches, to run one again (or ↓ in the box). -->
        <Button x:Name="user_recent" Grid.Column="2" Style="{StaticResource Btn.Mini}" Margin="0,0,5,0" ToolTip="Recherches récentes (↓)" AutomationProperties.Name="Recherches récentes">
          {{icon:history:15}}
          <Button.ContextMenu><ContextMenu x:Name="user_recent_menu"/></Button.ContextMenu>
        </Button>
      </Grid>
    </Border>
    <Button x:Name="user_search" Grid.Column="5" Style="{StaticResource Btn.Primary}" Height="{DynamicResource R.BarHeight}" ToolTip="Entrée, ou F5 pour relancer la dernière recherche">
      <StackPanel Orientation="Horizontal">{{icon:search}}<TextBlock Text="Rechercher" Margin="8,0,0,0"/></StackPanel>
    </Button>
    <!-- Shown while a search runs. -->
    <Button x:Name="user_cancel" Grid.Column="6" Height="{DynamicResource R.BarHeight}" Margin="8,0,0,0" Visibility="Collapsed" Content="Annuler" ToolTip="Arrêter la recherche (Échap)"/>
    <!-- What a search is missing, just under the box (Show-SearchHint), over the row below: gone once the search changes. -->
    <Canvas Grid.Column="3" Grid.ColumnSpan="4" VerticalAlignment="Bottom" Height="0" IsHitTestVisible="False">
      <Border x:Name="user_search_hint" Canvas.Top="6" Visibility="Collapsed" Padding="10,5" CornerRadius="6" BorderThickness="1"
              Background="{DynamicResource R.DangerBg}" BorderBrush="{DynamicResource R.DangerBorder}">
        <Border.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.2"/></Border.Effect>
        <TextBlock x:Name="user_search_hint_text" Foreground="{DynamicResource R.DangerText}" FontSize="12" TextWrapping="Wrap"/>
      </Border>
    </Canvas>
  </Grid>

  <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.ResultsBarMargin}">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
      <TextBlock Text="Utilisateurs" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
      <TextBlock x:Name="user_scope" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="8,0,0,0"/>
    </StackPanel>
    <StackPanel Grid.Column="2" Orientation="Horizontal">
      <!-- The users shown, after the filter and in the grid's order, as CSV (like the computers' Exporter). -->
      <Button x:Name="user_export" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" IsEnabled="False" ToolTip="Enregistrer les utilisateurs affichés en CSV (pour Excel)" ToolTipService.ShowOnDisabled="True">
        <StackPanel Orientation="Horizontal">{{icon:download}}<TextBlock Text="Exporter" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <Button x:Name="user_columns" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" ToolTip="Afficher ou masquer des colonnes (ou clic droit sur un en-tête)">
        <StackPanel Orientation="Horizontal">{{icon:columns}}<TextBlock Text="Colonnes" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <ToggleButton x:Name="user_column_filters" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" ToolTip="Afficher ou masquer les filtres dans les en-têtes des colonnes">
        <StackPanel Orientation="Horizontal">{{icon:filter}}<TextBlock x:Name="user_column_filters_text" Text="Filtres" Margin="8,0,0,0"/></StackPanel>
      </ToggleButton>
      <Border Style="{StaticResource Field}" Width="260" Height="{DynamicResource R.ControlHeight}">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
          <TextBox x:Name="user_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les résultats"/>
        </Grid>
      </Border>
    </StackPanel>
  </Grid>

  <!-- Liste d'identifiants: the entries no domain had, to copy. -->
  <Border x:Name="user_not_found" DockPanel.Dock="Top" Visibility="Collapsed" Margin="16,0,16,10" Padding="12,6" CornerRadius="8" BorderThickness="1"
          Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Border Margin="0,0,8,0" TextElement.Foreground="{DynamicResource R.WarnText}">{{icon:warning}}</Border>
      <TextBlock x:Name="user_not_found_text" Grid.Column="1" Foreground="{DynamicResource R.WarnText}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
      <Button x:Name="user_not_found_copy" Grid.Column="2" Style="{StaticResource Btn.Warn}" Margin="12,-2,0,-2"
              ToolTip="Copier les introuvables, un par ligne" AutomationProperties.Name="Copier">
        <StackPanel Orientation="Horizontal">{{icon:copy:13}}<TextBlock Text="Copier" Margin="6,0,0,0"/></StackPanel>
      </Button>
    </Grid>
  </Border>

  <Border DockPanel.Dock="Bottom" Padding="{DynamicResource R.StatusPadding}">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="user_count" Style="{StaticResource Txt.Muted}" FontSize="12"/>
        <TextBlock x:Name="user_time" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="4,0,0,0"/>
        <!-- When a domain found more than the limit: the same search again, without it. -->
        <Button x:Name="user_show_all" Style="{StaticResource Btn.Ghost}" Visibility="Collapsed" Margin="8,-4,0,-4" Padding="8,2" MinHeight="0" FontSize="12"
                Foreground="{DynamicResource R.AccentText}" Content="Tout afficher" ToolTip="La même recherche, sans limite : peut prendre un moment"/>
      </StackPanel>
      <TextBlock Grid.Column="1" Margin="16,0,0,0" Style="{StaticResource Txt.Faint}" FontSize="12" Text="Clic droit sur un utilisateur : toutes les actions"/>
    </Grid>
  </Border>

  <Border Style="{StaticResource Card}" Margin="16,0">
    <Grid>
      <DataGrid x:Name="user_grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True" CanUserResizeColumns="True" CanUserReorderColumns="False"
                CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Extended" SelectionUnit="FullRow" HeadersVisibility="Column"
                GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{DynamicResource R.Border}" Background="Transparent" RowBackground="Transparent"
                Foreground="{DynamicResource R.Text}" BorderThickness="0" RowHeight="{DynamicResource R.RowHeight}" Margin="1"
                RowStyle="{StaticResource Grid.Row}" CellStyle="{StaticResource Grid.Cell}" ColumnHeaderStyle="{StaticResource Grid.Header}">
        <DataGrid.Columns>
          <!-- État: grey text for an active account; a badge, amber when locked, red when disabled (the last trigger wins:
               disabled and locked is red), by IsLocked and IsEnabled, the text being in this run's language. -->
          <!-- The columns share the width; their minimums (about 1040 in all) fit the narrowest window, Domaine shown. -->
          <DataGridTemplateColumn Header="État" SortMemberPath="State" Width="105" MinWidth="90">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <Border HorizontalAlignment="Left" VerticalAlignment="Center" Margin="4,0,0,0" CornerRadius="9" Padding="8,1" BorderThickness="1">
                  <Border.Style>
                    <Style TargetType="Border">
                      <Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/>
                      <Setter Property="TextElement.Foreground" Value="{DynamicResource R.Muted}"/>
                      <Style.Triggers>
                        <DataTrigger Binding="{Binding IsLocked}" Value="True">
                          <Setter Property="Background" Value="{DynamicResource R.WarnBg}"/><Setter Property="BorderBrush" Value="{DynamicResource R.WarnBorder}"/>
                          <Setter Property="TextElement.Foreground" Value="{DynamicResource R.WarnText}"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding IsEnabled}" Value="False">
                          <Setter Property="Background" Value="{DynamicResource R.DangerBg}"/><Setter Property="BorderBrush" Value="{DynamicResource R.DangerBorder}"/>
                          <Setter Property="TextElement.Foreground" Value="{DynamicResource R.DangerText}"/>
                        </DataTrigger>
                      </Style.Triggers>
                    </Style>
                  </Border.Style>
                  <TextBlock Text="{Binding State}" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}" AutomationProperties.AutomationId="CellTextBlock"/>
                </Border>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTextColumn Header="Nom" Binding="{Binding Name}" SortMemberPath="Name" Width="1.5*" MinWidth="130" ElementStyle="{StaticResource Grid.Text.Strong}"/>
          <DataGridTextColumn Header="Identifiant" Binding="{Binding Login}" SortMemberPath="Login" Width="*" MinWidth="115" ElementStyle="{StaticResource Grid.Text}"/>
          <!-- Courriel and Description: hidden until chosen in Colonnes. -->
          <DataGridTextColumn Header="Courriel" Binding="{Binding Mail}" SortMemberPath="Mail" Width="1.5*" MinWidth="140" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Poste" Binding="{Binding Title}" SortMemberPath="Title" Width="1.3*" MinWidth="100" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Service" Binding="{Binding Department}" SortMemberPath="Department" Width="*" MinWidth="85" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTextColumn Header="Description" Binding="{Binding Description}" SortMemberPath="Description" Width="1.5*" MinWidth="120" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTemplateColumn Header="Dernière connexion" SortMemberPath="LastLogon" Width="160" MinWidth="160">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding LastLogonAgo}" ToolTip="{Binding LastLogonTip}">
                  <TextBlock.Style>
                    <Style TargetType="TextBlock" BasedOn="{StaticResource Grid.Text}">
                      <Style.Triggers><DataTrigger Binding="{Binding IsStale}" Value="True"><Setter Property="Foreground" Value="{DynamicResource R.WarnText}"/></DataTrigger></Style.Triggers>
                    </Style>
                  </TextBlock.Style>
                </TextBlock>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTemplateColumn Header="Mot de passe" SortMemberPath="PasswordSort" Width="165" MinWidth="165">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding Password}" ToolTip="{Binding PasswordTip}">
                  <TextBlock.Style>
                    <Style TargetType="TextBlock" BasedOn="{StaticResource Grid.Text}">
                      <Style.Triggers>
                        <DataTrigger Binding="{Binding PasswordTone}" Value="warn"><Setter Property="Foreground" Value="{DynamicResource R.WarnText}"/></DataTrigger>
                        <DataTrigger Binding="{Binding PasswordTone}" Value="danger"><Setter Property="Foreground" Value="{DynamicResource R.DangerText}"/></DataTrigger>
                      </Style.Triggers>
                    </Style>
                  </TextBlock.Style>
                </TextBlock>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTextColumn Header="Domaine" Binding="{Binding Domain}" SortMemberPath="Domain" Width="125" MinWidth="125" ElementStyle="{StaticResource Grid.Text}"/>
          <DataGridTemplateColumn Header="Emplacement" SortMemberPath="OUPath" Width="*" MinWidth="105">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding OUPath}" ToolTip="{Binding DistinguishedName}" Style="{StaticResource Grid.Text}"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
        </DataGrid.Columns>
        <DataGrid.ContextMenu>
          <!-- The account's actions in reach; the groups' and the copies in submenus, as on Ordinateurs. A submenu is
               enabled while one of its items is (Update-UserAction). -->
          <ContextMenu>
            <MenuItem x:Name="user_menu_details" Header="Propriétés…" FontWeight="{DynamicResource R.FontWeightStrong}"><MenuItem.Icon>{{icon:user}}</MenuItem.Icon></MenuItem>
            <MenuItem x:Name="user_menu_computers" Header="Ordinateurs de l'utilisateur"><MenuItem.Icon>{{icon:monitor}}</MenuItem.Icon></MenuItem>
            <MenuItem x:Name="user_menu_group_groups" Header="Groupes" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:users}}</MenuItem.Icon>
              <MenuItem x:Name="user_menu_compare" Header="Comparer les groupes…"><MenuItem.Icon>{{icon:columns}}</MenuItem.Icon></MenuItem>
              <MenuItem x:Name="user_menu_groups_add" Header="Ajouter à un groupe…"><MenuItem.Icon>{{icon:userplus}}</MenuItem.Icon></MenuItem>
              <MenuItem x:Name="user_menu_groups_remove" Header="Retirer d'un groupe…"><MenuItem.Icon>{{icon:userminus}}</MenuItem.Icon></MenuItem>
            </MenuItem>
            <Separator/>
            <MenuItem x:Name="user_menu_unlock" Header="Déverrouiller"><MenuItem.Icon>{{icon:unlock}}</MenuItem.Icon></MenuItem>
            <MenuItem x:Name="user_menu_reset" Header="Nouveau mot de passe…"><MenuItem.Icon>{{icon:password}}</MenuItem.Icon></MenuItem>
            <MenuItem x:Name="user_menu_enable" Header="Activer"><MenuItem.Icon>{{icon:checkcircle}}</MenuItem.Icon></MenuItem>
            <MenuItem x:Name="user_menu_disable" Header="Désactiver…"><MenuItem.Icon>{{icon:ban}}</MenuItem.Icon></MenuItem>
            <Separator/>
            <MenuItem x:Name="user_menu_group_copy" Header="Copier" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:copy}}</MenuItem.Icon>
              <MenuItem x:Name="user_menu_copy" Header="Copier l'identifiant" InputGestureText="Ctrl+C"><MenuItem.Icon>{{icon:copy}}</MenuItem.Icon></MenuItem>
              <MenuItem x:Name="user_menu_copy_name" Header="Copier le nom"/>
              <MenuItem x:Name="user_menu_copy_mail" Header="Copier le courriel"/>
              <MenuItem x:Name="user_menu_copy_rows" Header="Copier les lignes"><MenuItem.InputGestureText>Ctrl+Maj+C</MenuItem.InputGestureText></MenuItem>
            </MenuItem>
          </ContextMenu>
        </DataGrid.ContextMenu>
      </DataGrid>
      <!-- Before the first search, and when nothing is found. -->
      <StackPanel x:Name="user_empty" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False">
        <Border HorizontalAlignment="Center" TextElement.Foreground="{DynamicResource R.Faint}">{{icon:user:26}}</Border>
        <TextBlock x:Name="user_empty_text" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" Margin="0,10,0,0"
                   Text="Entrez un nom, un identifiant ou un courriel, puis Rechercher."/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" HorizontalAlignment="Center" Margin="0,4,0,0"
                   Text="« Verrouillés » sans texte liste tous les comptes verrouillés du domaine."/>
      </StackPanel>
    </Grid>
  </Border>
</DockPanel>
'@

function Initialize-UserPage($HostControl) {
    # Builds the page the first time its tab is chosen (Initialize-SearchPage), then wires what only users have.
    Initialize-SearchPage $script:UserPage $HostControl $script:UserPageXaml
    $root = $script:UserPage.Root
    foreach ($name in 'user_unlock', 'user_menu_unlock') { $root.FindName($name).Add_Click({ Invoke-UserUnlock }) }
    foreach ($name in 'user_reset', 'user_menu_reset') { $root.FindName($name).Add_Click({ Show-UserResetDialog }) }
    $root.FindName('user_menu_enable').Add_Click({ Invoke-UserEnable })
    $root.FindName('user_menu_disable').Add_Click({ Invoke-UserDisable })
    $root.FindName('user_toggle').Add_Click({
        # Activer when every selected account is disabled; otherwise Désactiver… those that aren't.
        $selected = Get-PageSelection $script:UserPage
        if (@($selected | Where-Object IsEnabled).Count) { Invoke-UserDisable } else { Invoke-UserEnable }
    })
    $root.FindName('user_menu_copy_name').Add_Click({ Copy-PageText $script:UserPage 'Name' })
    $root.FindName('user_menu_copy_mail').Add_Click({ Copy-PageText $script:UserPage 'Mail' })
    $root.FindName('user_menu_computers').Add_Click({ Find-UserComputer @(Get-PageSelection $script:UserPage)[0].Name })
    # Comparer les groupes…, for two users (GroupCompare.ps1).
    foreach ($name in 'user_compare', 'user_menu_compare') {
        $root.FindName($name).Add_Click({
            $selected = Get-PageSelection $script:UserPage
            if ($selected.Count -eq 2) { Show-UserGroupCompare $selected[0] $selected[1] $script:win }
        })
    }
    # Ajouter à un groupe… and Retirer d'un groupe…, for every user selected (SelectionGroups.ps1).
    foreach ($name in 'user_groups_add', 'user_menu_groups_add') {
        $root.FindName($name).Add_Click({ Show-SelectionGroupAdd @(ConvertTo-GroupMember (Get-PageSelection $script:UserPage) 'User') })
    }
    foreach ($name in 'user_groups_remove', 'user_menu_groups_remove') {
        $root.FindName($name).Add_Click({ Show-SelectionGroupRemove @(ConvertTo-GroupMember (Get-PageSelection $script:UserPage) 'User') })
    }
}

function Update-UserAction {
    # The actions follow the selection: Déverrouiller when a selected account is locked, Réinitialiser for one user,
    # Activer and Désactiver… for those it applies to, Comparer les groupes… for two, the groups' changes for any.
    $root = $script:UserPage.Root
    $selected = Get-PageSelection $script:UserPage
    $locked = @($selected | Where-Object IsLocked).Count
    foreach ($name in 'user_unlock', 'user_menu_unlock') { $root.FindName($name).IsEnabled = $locked -gt 0 }
    $enabled = @($selected | Where-Object IsEnabled).Count
    $root.FindName('user_menu_disable').IsEnabled = $enabled -gt 0
    $root.FindName('user_menu_enable').IsEnabled = $enabled -lt $selected.Count
    $root.FindName('user_toggle').IsEnabled = $selected.Count -gt 0
    $offerEnable = $selected.Count -gt 0 -and -not $enabled
    $root.FindName('user_toggle_disable_icon').Visibility = if ($offerEnable) { 'Collapsed' } else { 'Visible' }
    $root.FindName('user_toggle_enable_icon').Visibility = if ($offerEnable) { 'Visible' } else { 'Collapsed' }
    $root.FindName('user_toggle_text').Text = if ($offerEnable) { Tr 'Activer' } else { Tr 'Désactiver…' }
    foreach ($name in 'user_reset', 'user_menu_reset', 'user_details', 'user_menu_details', 'user_menu_computers') { $root.FindName($name).IsEnabled = $selected.Count -eq 1 }
    foreach ($name in 'user_compare', 'user_menu_compare') { $root.FindName($name).IsEnabled = $selected.Count -eq 2 }
    foreach ($name in 'user_copy', 'user_menu_copy', 'user_menu_copy_name', 'user_menu_copy_rows', 'user_groups_add', 'user_menu_groups_add', 'user_groups_remove', 'user_menu_groups_remove', 'user_menu_group_groups', 'user_menu_group_copy') { $root.FindName($name).IsEnabled = $selected.Count -gt 0 }
    # Copier le courriel once a selected user has one.
    $root.FindName('user_menu_copy_mail').IsEnabled = @($selected | Where-Object Mail).Count -gt 0
    $root.FindName('user_selection').Text = switch ($selected.Count) {
        0 { Tr 'Aucune sélection' }
        1 { (Tr '{0} sélectionné') -f $selected[0].Name }
        default { (Tr '{0} utilisateurs sélectionnés') -f $selected.Count }
    }
}

function Update-UserRow {
    # A row changed (unlocked, password reset): the grid shows it again, and the actions follow. Not before the page
    # is built: a user opened from a group's members has a row of its own.
    if (-not $script:UserPage.View) { return }
    $script:UserPage.View.Refresh()
    Update-UserAction
}

function Sync-UserPageRow($Row) {
    # A Propriétés window changed its copy of a row (unlocked, enabled, password reset, its name, email, title…
    # edited): the page's row of the same account, when the page still shows it, takes the same state and values, then
    # the grid shows it again.
    $rows = $script:UserPage['Rows']
    if ($rows) {
        foreach ($shown in @($rows | Where-Object { $_.DistinguishedName -eq $Row.DistinguishedName -and $_.Domain -eq $Row.Domain })) {
            foreach ($name in 'State', 'IsEnabled', 'IsLocked', 'Password', 'PasswordTone', 'PasswordTip', 'PasswordSort', 'PasswordState', 'PasswordNeverExpires',
                              'Name', 'Title', 'Department', 'Description', 'Mail', 'Text') {
                $shown.$name = $Row.$name
            }
        }
    }
    Update-UserRow
}

function Find-UserRow([string]$LdapFilter, [string[]]$Domains, [string]$SearchScript, [string]$RowBuilder, [datetime]$Today) {
    # In a search runspace (Start-UserRowRead): the first user the filter finds in these domains, looked in in this
    # order, as the page's search makes its rows (what Propriétés… reads). Its Row, or $null with the last domain's
    # Problem (none when no domain has the user).
    $problem = $null
    foreach ($domain in $Domains) {
        $answer = & ([scriptblock]::Create($SearchScript)) -Domain $domain -LdapFilter $LdapFilter -LockedOnly $false -RowBuilder $RowBuilder -Today $Today
        if ($answer.Error) { $problem = $answer.Error; continue }
        if (@($answer.Rows).Count) { return @{ Row = @($answer.Rows)[0]; Problem = $null } }
    }
    @{ Row = $null; Problem = $problem }
}

function Start-UserRowRead([string]$LdapFilter, [string[]]$Domains, [scriptblock]$OnDone, $Context) {
    # One user, for one opened from elsewhere (a group's members, Utilisateurs connectés…), read in the background: a
    # slow or unreachable DC doesn't freeze the window. Then & $OnDone $Context $Row $Problem on the window's thread:
    # $Row is $null when it wasn't found, $Problem why it couldn't be read, if that's why.
    Start-BackgroundRead -Command 'Find-UserRow' -Arguments @($LdapFilter, $Domains, $script:UserSearchScript, $script:rowBuilderScript, (Get-Date).Date) `
        -Context @{ OnDone = $OnDone; Context = $Context } -OnDone {
            param($read, $result, $problem)
            $row = if ($result) { $result.Row }
            if (-not $problem -and $result) { $problem = $result.Problem }
            # Once the reads' timer tick is over: what $OnDone opens may wait for a dialog (the limit of Propriétés
            # windows), and the timer must go on collecting reads meanwhile.
            $script:UserRowReads.Enqueue(@{ OnDone = $read.OnDone; Context = $read.Context; Row = $row; Problem = $problem })
            $null = $script:win.Dispatcher.BeginInvoke([Action]{ Complete-UserRowRead })
        }
}

function Complete-UserRowRead {
    # Start-UserRowRead's $OnDone, for the next user read.
    if (-not $script:UserRowReads.Count) { return }
    $done = $script:UserRowReads.Dequeue()
    & $done.OnDone $done.Context $done.Row $done.Problem
}
$script:UserRowReads = [System.Collections.Generic.Queue[object]]::new()

function Invoke-UserUnlock {
    # Unlocking only gives the account back the use of its password: no confirmation, a report (Start-UserAccountWrite).
    # The selection held first: piped as it comes, the list would go through as one object.
    $selected = Get-PageSelection $script:UserPage
    $locked = @($selected | Where-Object IsLocked)
    if (-not $locked.Count) { return }
    Start-UserAccountWrite 'Unlock' $locked
}

function Start-UserAccountWrite([string]$Action, $Rows) {
    # Déverrouiller, Activer or Désactiver from the page, in the background (Invoke-UserAccountWrite, Start-ADWrite):
    # each account on the DC its Propriétés read from (Invoke-UserChange), the window usable meanwhile, the bar at its
    # bottom saying it's under way. An account already being changed so is left out. Then Complete-UserAccountWrite.
    $Rows = @($Rows | Where-Object { -not (Test-ADWriteBusy (Get-UserWriteKey $Action $_)) })
    if (-not $Rows.Count) { return }
    $title = switch ($Action) { 'Unlock' { Tr 'Déverrouiller' } 'Enable' { Tr 'Activer' } default { Tr 'Désactiver' } }
    $started = Start-ADWrite -Keys @($Rows | ForEach-Object { Get-UserWriteKey $Action $_ }) -Command 'Invoke-UserAccountWrite' -Arguments @($Action, @(ConvertTo-WriteUser $Rows)) `
        -Count $Rows.Count -Context @{ Action = $Action; Rows = $Rows; Title = $title } -OnDone {
        param($write, $outcome)
        Complete-UserAccountWrite $write $outcome
    }
    $who = if ($Rows.Count -eq 1) { $Rows[0].Login } else { (Tr '{0} utilisateurs') -f $Rows.Count }
    if ($started) { Show-ActionNotice $title ((Tr '{0} : en cours…') -f $who) -Persist }
}

function Complete-UserAccountWrite($Write, $Outcome) {
    # Start-UserAccountWrite's change: the rows of the accounts changed (État), their open Propriétés read again, and a
    # line each in the report: done, failed, or perhaps done (the DC didn't answer in time, Get-WriteAnswer).
    $report = for ($i = 0; $i -lt $Write.Rows.Count; $i++) {
        $row = $Write.Rows[$i]
        $answer = Get-WriteAnswer $Outcome $i
        if (-not $answer.Problem -and -not $answer.Unsure) {
            if ($Write.Action -eq 'Unlock') {
                $row.IsLocked = $false
                # Verrouillé until now, unless disabled (which State says first).
                if ($row.IsEnabled) { $row.State = Tr 'Actif' }
            }
            else {
                $row.IsEnabled = $Write.Action -eq 'Enable'
                $row.State = if (-not $row.IsEnabled) { Tr 'Désactivé' } elseif ($row.IsLocked) { Tr 'Verrouillé' } else { Tr 'Actif' }
            }
        }
        Get-WriteLine $row.Login $answer $Outcome.Timeout
    }
    Update-UserRow
    Update-OpenUserDetail $Write.Rows
    # « en cours… » is over; a dialog wouldn't replace it.
    Hide-ActionNotice
    $done = switch ($Write.Action) { 'Unlock' { (Tr 'Déverrouillé'), (Tr 'Déverrouillés') } 'Enable' { (Tr 'Activé'), (Tr 'Activés') } default { (Tr 'Désactivé'), (Tr 'Désactivés') } }
    Show-ActionReport @($report) $Write.Title -Many (Tr '✔ {0} utilisateurs') -Outcome $done
}

function Invoke-UserEnable {
    # Only the disabled ones; enabling gives the account back, so there's no confirmation. The selection held first: piped
    # as it comes, the list would go through as one object.
    $all = Get-PageSelection $script:UserPage
    $selected = @($all | Where-Object { -not $_.IsEnabled })
    if ($selected.Count) { Set-UserEnabled $selected $true }
}

function Invoke-UserDisable {
    # Only the enabled ones. Reversible, but the person can no longer sign in, so Annuler is the default. Never the
    # account running Repère (Test-SelfAccount): it would lock its user out.
    $all = Get-PageSelection $script:UserPage
    $enabled = @($all | Where-Object IsEnabled)
    $own = @($enabled | Where-Object { Test-SelfAccount $_.Login $_.Domain })
    $selected = @($enabled | Where-Object { $own -notcontains $_ })
    if (-not $selected.Count) {
        if ($own.Count) {
            Show-Dialog -Title (Tr 'Désactiver') -Icon 'ban' -Tone 'warn' -Heading ((Tr '{0} : rien à faire') -f (Tr 'Désactiver')) `
                -Message ((Tr "Repère ne désactive pas votre propre compte ({0}) : vous ne pourriez plus ouvrir de session.") -f $own[0].Login)
        }
        return
    }
    $names = @($selected | ForEach-Object { $_.Name })
    $heading = if ($names.Count -eq 1) { (Tr 'Désactiver {0} ?') -f $names[0] } else { (Tr 'Désactiver {0} utilisateurs ?') -f $names.Count }
    $message = Tr 'Un compte désactivé ne peut plus ouvrir de session. Rien n''est perdu : Activer le rétablit.'
    if ($own.Count) { $message += "`n`n" + ((Tr 'Laissé de côté : {0} (votre compte).') -f $own[0].Login) }
    Show-Dialog -Title (Tr 'Désactiver') -Heading $heading -Names $(if ($names.Count -gt 1) { $names }) -Message $message -Icon 'ban' -Tone 'danger' -OkText (Tr 'Désactiver') -CancelIsDefault -State @{ Selected = $selected } -OnOk {
        param($state)
        Set-UserEnabled $state.Selected $false
    }
}

function Set-UserEnabled($Rows, [bool]$Enabled) {
    # Enables or disables each account in its domain, in the background (Start-UserAccountWrite), then its row (État),
    # and says how it went.
    Start-UserAccountWrite $(if ($Enabled) { 'Enable' } else { 'Disable' }) $Rows
}

function Set-ResetMustChange($Box, [bool]$Forced) {
    # « Doit le changer »: ticked and held while the password is a generated one or the default one, then back to what
    # it was. Asked for the state it's already in, it changes nothing: going from one of those two to the other keeps
    # what was ticked before them, whichever radio button says it changed first.
    if ($Forced -eq (-not $Box.IsEnabled)) { return }
    if ($Forced) {
        $Box.Tag = $Box.IsChecked
        $Box.IsChecked = $true
    }
    else { $Box.IsChecked = $Box.Tag }
    $Box.IsEnabled = -not $Forced
}

function Register-ResetMustChange($Content) {
    # A generated password is only a start, and the default one is the same for every reset and known to every
    # technician: either is always changed at the next logon, so « doit le changer » is held while one is chosen. Read
    # from the three choices after each change, so it follows the one chosen whatever the order of their events.
    $update = {
        param($radio)
        $root = $radio.Parent
        $forced = [bool]$root.FindName('reset_generated').IsChecked -or [bool]$root.FindName('reset_default').IsChecked
        Set-ResetMustChange $root.FindName('reset_must_change') $forced
    }
    foreach ($name in 'reset_generated', 'reset_default', 'reset_custom') {
        $choice = $Content.FindName($name)
        $choice.Add_Checked($update)
        $choice.Add_Unchecked($update)
    }
    & $update $Content.FindName('reset_custom')
}

function Set-ResetCustomUse($Eye, [bool]$Used, [switch]$Focus) {
    # « Autre »'s password box (Register-PasswordEye's $Eye) and its eye: used while « Autre » is chosen; unused, hidden
    # again, what's typed kept for when it's chosen again, and no eye (its place kept, so nothing moves).
    if (-not $Used) { Set-PasswordShown $Eye $false }
    Set-TextBoxUse $Eye.Box $Used (Tr 'Choisissez « Autre » pour taper le mot de passe.')
    $Eye.Show.Visibility = if ($Used) { 'Visible' } else { 'Hidden' }
    if ($Focus) { $null = $Eye.Box.Focus() }
}

function Show-UserResetDialog($Row, [System.Windows.Window]$Owner, $Detail) {
    # Nouveau mot de passe…, for one user: the new password (generated, the default one of Paramètres, or
    # typed), whether they must change it at their next logon, and unlocking the account at the same time. For the
    # page's selected user, or $Row from its Propriétés: $Owner is that window, and $Detail its state, read again after.
    if (-not $Row) {
        $selected = Get-PageSelection $script:UserPage
        if ($selected.Count -ne 1) { return }
        $Row = $selected[0]
    }
    $setting = Read-PasswordSetting
    $hasDefault = [bool]$setting.Default
    $generated = New-TemporaryPassword
    $content = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <TextBlock Style="{StaticResource Txt.Label}" Text="Nouveau mot de passe" Margin="0,0,0,6"/>
  <RadioButton x:Name="reset_generated" GroupName="reset" Content="Généré, facile à dicter"/>
  <StackPanel Orientation="Horizontal" Margin="28,6,0,0">
    <Border Style="{StaticResource Field}" Padding="10,6" MinWidth="220">
      <TextBlock x:Name="reset_generated_value" FontFamily="Consolas" FontSize="14"/>
    </Border>
    <Button x:Name="reset_regenerate" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" ToolTip="Un autre" AutomationProperties.Name="Générer un autre mot de passe">{{icon:refresh:14}}</Button>
  </StackPanel>
  <RadioButton x:Name="reset_default" GroupName="reset" Margin="0,10,0,0"/>
  <RadioButton x:Name="reset_custom" GroupName="reset" Content="Autre" Margin="0,10,0,0"/>
  <StackPanel Orientation="Horizontal" Margin="28,6,0,0">
    <Grid Width="260">
      <PasswordBox x:Name="reset_custom_value" FontFamily="Consolas" IsEnabled="False" AutomationProperties.Name="Autre mot de passe"/>
      <TextBox x:Name="reset_custom_text" Visibility="Collapsed" FontFamily="Consolas" AutomationProperties.Name="Autre mot de passe"/>
    </Grid>
    <Button x:Name="reset_custom_show" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" Visibility="Hidden" ToolTip="Afficher le mot de passe" AutomationProperties.Name="Afficher le mot de passe">{{icon:eye:14}}</Button>
    <Button x:Name="reset_custom_hide" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Masquer le mot de passe" AutomationProperties.Name="Masquer le mot de passe">{{icon:eyeoff:14}}</Button>
  </StackPanel>
  <CheckBox x:Name="reset_must_change" Content="Doit le changer à sa prochaine connexion" Margin="0,16,0,0"/>
  <TextBlock x:Name="reset_must_change_note" Style="{StaticResource Txt.Muted}" Margin="28,4,0,0" TextWrapping="Wrap" Visibility="Collapsed"
             Text="Le mot de passe de ce compte n'expire jamais : AD ne permet pas de demander de le changer. Ni un mot de passe généré ni celui par défaut ne sont donc proposés."/>
  <CheckBox x:Name="reset_unlock" Content="Déverrouiller aussi le compte" Margin="0,8,0,0"/>
</StackPanel>
'@))
    $content.FindName('reset_generated_value').Text = $generated
    $default = $content.FindName('reset_default')
    $default.Content = if ($hasDefault) { Tr 'Le mot de passe par défaut (Paramètres)' } else { Tr 'Le mot de passe par défaut : aucun dans Paramètres › Mots de passe' }
    $default.IsEnabled = $hasDefault
    if ($setting.Mode -eq 'Default' -and $hasDefault) { $default.IsChecked = $true } else { $content.FindName('reset_generated').IsChecked = $true }
    # What Paramètres says, for a password typed in « Autre »: the generated one and the default one hold it ticked.
    $mustChange = $content.FindName('reset_must_change')
    $mustChange.IsChecked = $setting.MustChange
    # AD refuses it for a password that never expires (Set-ADUser -ChangePasswordAtLogon): not offered, and why.
    if ($row.PasswordNeverExpires) {
        $mustChange.IsChecked = $false
        $mustChange.IsEnabled = $false
        $content.FindName('reset_must_change_note').Visibility = 'Visible'
    }
    $unlock = $content.FindName('reset_unlock')
    $unlock.IsChecked = $row.IsLocked
    $unlock.Visibility = if ($row.IsLocked) { 'Visible' } else { 'Collapsed' }
    $content.FindName('reset_regenerate').Add_Click({
        param($button)
        $button.Parent.FindName('reset_generated_value').Text = New-TemporaryPassword
    })
    # « Autre »: typed hidden, like every password, with an eye to check its spelling.
    $custom = $content.FindName('reset_custom')
    $custom.CommandParameter = Register-PasswordEye $content.FindName('reset_custom_value') $content.FindName('reset_custom_text') `
        $content.FindName('reset_custom_show') $content.FindName('reset_custom_hide')
    $custom.Add_Checked({ param($radio) Set-ResetCustomUse $radio.CommandParameter $true -Focus })
    $custom.Add_Unchecked({ param($radio) Set-ResetCustomUse $radio.CommandParameter $false })
    Set-ResetCustomUse $custom.CommandParameter ([bool]$custom.IsChecked)
    # A generated password and the default one are always changed at the next logon (Register-ResetMustChange). An
    # account AD can't ask that of (its password never expires) is offered neither: only one typed in « Autre ».
    if ($row.PasswordNeverExpires) {
        $content.FindName('reset_generated').IsEnabled = $false
        $content.FindName('reset_regenerate').IsEnabled = $false
        $default.IsEnabled = $false
        $custom.IsChecked = $true
    }
    else { Register-ResetMustChange $content }

    Show-Dialog -Title (Tr 'Nouveau mot de passe') -Heading ((Tr 'Réinitialiser le mot de passe de {0} ?') -f $row.Name) -Icon 'password' -Tone 'warn' `
        -Message ((Tr 'Identifiant : {0}') -f $row.Login) -Content $content -Owner $Owner `
        -OkText (Tr 'Réinitialiser') -CancelIsDefault -State @{ Row = $row; Content = $content; Default = $setting.Default; Owner = $Owner; Detail = $Detail } -OnOk {
        param($state)
        $content = $state.Content
        $password = if ($content.FindName('reset_default').IsChecked) { $state.Default }
                    elseif ($content.FindName('reset_custom').IsChecked) { $content.FindName('reset_custom_value').Password }
                    else { $content.FindName('reset_generated_value').Text }
        Set-UserPassword $state.Row $password ([bool]$content.FindName('reset_must_change').IsChecked) ([bool]$content.FindName('reset_unlock').IsChecked) $state.Owner $state.Detail
    }
}

function Set-NewPasswordShown($Eye, [bool]$Shown) {
    # Mot de passe réinitialisé's password: hidden, a row of dots the same length whatever the password (as Mot de passe
    # LAPS); shown, the password itself, to read out or select.
    if ($Shown) {
        $Eye.Box.Text = $Eye.Password
        $Eye.Box.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
    }
    else {
        $Eye.Box.Text = [string]::new([char]0x25CF, 12)
        $Eye.Box.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'R.Muted')
    }
    Set-EyeButton $Eye.Show $Eye.Hide $Shown
}

function Set-UserPassword {
    # Sets the password, then « must change it », then unlocks, in the background (Set-UserPasswordWrite, Start-ADWrite):
    # $Owner (the main window when $null) stays usable meanwhile, its pointer saying it runs. Then
    # Complete-UserPassword says the password once, or why it failed. The password goes to AD as a SecureString and
    # isn't kept anywhere. From a user's Propriétés ($Detail, its state), the window reads the account again.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'A temporary password the technician reads out to the person: it is shown on purpose.')]
    param($Row, [string]$Password, [bool]$MustChange, [bool]$Unlock, [System.Windows.Window]$Owner, $Detail)
    if (-not $Password) {
        Show-Dialog -Title (Tr 'Nouveau mot de passe') -Message ((Tr "✖ {0} : aucun mot de passe entré, rien n'a changé.") -f $Row.Login) -Owner $Owner
        return
    }
    $secure = [securestring]::new()
    foreach ($char in $Password.ToCharArray()) { $secure.AppendChar($char) }
    $secure.MakeReadOnly()
    $started = Start-ADWrite -Keys @(Get-UserWriteKey 'Password' $Row) -Command 'Set-UserPasswordWrite' -Arguments @((ConvertTo-WriteUser $Row), $secure, $MustChange, $Unlock) `
        -Window $Owner -Context @{ Row = $Row; Password = $Password; MustChange = $MustChange; Unlock = $Unlock; Owner = $Owner; Detail = $Detail } -OnDone {
        param($write, $outcome)
        Complete-UserPassword $write $outcome
    }
    # A reset already under way: this password isn't sent, so the person mustn't be given it.
    if (-not $started) {
        Show-Dialog -Title (Tr 'Nouveau mot de passe') -Message ((Tr '✖ {0} : mot de passe non réinitialisé ({1})') -f $Row.Login, (Tr 'une réinitialisation est déjà en cours')) -Owner $Owner
    }
}

function Set-UserPasswordWrite($Row, [securestring]$Secure, [bool]$MustChange, [bool]$Unlock) {
    # On a search runspace (Set-UserPassword): the password, then « must change it », then the unlock, each on the DC
    # the account's Propriétés read from (Invoke-UserChange): the domain's PDC, or the DC in its place, where a PDC
    # down during the password leaves the rest. The others only once the password is set. Each step's Problem as it
    # goes (Add-WriteProgress: Password, MustChange, Unlock), $null when done.
    $problem = try {
        $null = Invoke-UserChange $Row.Domain { param($server) Set-ADAccountPassword -Server $server -Identity $Row.DistinguishedName -Reset -NewPassword $Secure -ErrorAction Stop }
        $null
    }
    catch { $_.Exception.Message }
    Add-WriteProgress 'Password' @{ Problem = $problem }
    if ($problem) { return }
    if ($MustChange) {
        $problem = try {
            $null = Invoke-UserChange $Row.Domain { param($server) Set-ADUser -Server $server -Identity $Row.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop }
            $null
        }
        catch { $_.Exception.Message }
        Add-WriteProgress 'MustChange' @{ Problem = $problem }
    }
    if ($Unlock) {
        $problem = try {
            $null = Invoke-UserChange $Row.Domain { param($server) Unlock-ADAccount -Server $server -Identity $Row.DistinguishedName -ErrorAction Stop }
            $null
        }
        catch { $_.Exception.Message }
        Add-WriteProgress 'Unlock' @{ Problem = $problem }
    }
}

function Complete-UserPassword($Write, $Outcome) {
    # Set-UserPassword's change: why the password wasn't set; or the row as it now is, the account's Propriétés read
    # again, and the password, once (Show-NewPassword). When the DC didn't answer in time before saying whether the
    # password was set, it may have been: the password is shown all the same, saying so, since the person would
    # otherwise have one no one knows.
    $row = $Write.Row
    $detail = $Write.Detail
    # A Propriétés it was reset from that has closed meanwhile: said over the main window.
    $owner = if ($detail -and $detail['Closed']) { $null } else { $Write.Owner }
    $password = Get-WriteAnswer $Outcome 'Password'
    if ($password.Problem) {
        Show-Dialog -Title (Tr 'Nouveau mot de passe') -Message ((Tr '✖ {0} : mot de passe non réinitialisé ({1})') -f $row.Login, $password.Problem) -Owner $owner
        return
    }
    $problems = [System.Collections.Generic.List[string]]::new()
    if (-not $password.Unsure) {
        if ($Write.MustChange) {
            $answer = Get-WriteAnswer $Outcome 'MustChange'
            if ($answer.Unsure) { $problems.Add(((Tr '« doit le changer » peut-être non appliqué ({0})') -f $Outcome.Problem)) }
            elseif ($answer.Problem) { $problems.Add(((Tr '« doit le changer » non appliqué ({0})') -f $answer.Problem)) }
            else {
                $row.Password, $row.PasswordTone, $row.PasswordTip, $row.PasswordSort, $row.PasswordState = (Tr 'À changer à la connexion'), 'warn', (Tr 'Le mot de passe devra être changé à la prochaine connexion.'), [int64]0, (Tr 'À changer à la connexion')
            }
        }
        else {
            # For the column's filter, what a new password is: one that expires later, unless it never does.
            $row.Password, $row.PasswordTone, $row.PasswordTip = (Tr 'Réinitialisé'), '', (Tr 'Réinitialisé à l''instant.')
            $row.PasswordState = if ($row.PasswordNeverExpires) { Tr "N'expire jamais" } else { Tr 'Expire dans plus de 14 jours' }
        }
        if ($Write.Unlock) {
            $answer = Get-WriteAnswer $Outcome 'Unlock'
            if ($answer.Unsure) { $problems.Add(((Tr 'compte peut-être non déverrouillé ({0})') -f $Outcome.Problem)) }
            elseif ($answer.Problem) { $problems.Add(((Tr 'compte non déverrouillé ({0})') -f $answer.Problem)) }
            else {
                $row.IsLocked = $false
                # Verrouillé until now, unless disabled (which State says first).
                if ($row.IsEnabled) { $row.State = Tr 'Actif' }
            }
        }
    }
    # From Propriétés, $Row is the window's copy: the page's row of the account follows at once, not only once the
    # window has read it again.
    Sync-UserPageRow $row
    # The window it was reset from reads itself again; reset on the page, the account's open one does.
    if ($detail -and -not $detail['Closed']) { Update-UserDetail $detail } else { Update-OpenUserDetail $row }
    Show-NewPassword $row $Write.Password $Write.MustChange @($problems) $owner -Unsure:$password.Unsure -Timeout $Outcome.Timeout
}

function Show-NewPassword {
    # Mot de passe réinitialisé: the password, once, over $Owner, with what of « must change it » and the unlock wasn't
    # done ($Problems). -Unsure: the DC didn't answer in time ($Timeout seconds) before saying whether it was set.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'A temporary password the technician reads out to the person: it is shown on purpose.')]
    param($Row, [string]$Password, [bool]$MustChange, [string[]]$Problems, [System.Windows.Window]$Owner, [switch]$Unsure, [int]$Timeout)
    # The password, once, to give to the person: large, in Consolas, hidden until its eye shows it (someone may be
    # looking at the screen), with a button to copy it. Set once the XAML is read, as it is: it isn't text to translate.
    $shown = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Orientation="Horizontal">
  <Border Style="{StaticResource Field}" Padding="12,8">
    <TextBox x:Name="user_new_password" Style="{StaticResource Text.Bare}" IsReadOnly="True" FontFamily="Consolas" FontSize="18" MinWidth="240"
             AutomationProperties.Name="Nouveau mot de passe"/>
  </Border>
  <Button x:Name="user_new_password_show" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" ToolTip="Afficher le mot de passe" AutomationProperties.Name="Afficher le mot de passe">{{icon:eye:14}}</Button>
  <Button x:Name="user_new_password_hide" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Masquer le mot de passe" AutomationProperties.Name="Masquer le mot de passe">{{icon:eyeoff:14}}</Button>
  <Button x:Name="user_new_password_copy" Margin="8,0,0,0" VerticalAlignment="Center" ToolTip="Copier le mot de passe">
    <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
  </Button>
</StackPanel>
'@))
    $eye = @{ Box = $shown.FindName('user_new_password'); Show = $shown.FindName('user_new_password_show'); Hide = $shown.FindName('user_new_password_hide'); Password = $Password }
    $eye.Show.CommandParameter = $eye
    $eye.Hide.CommandParameter = $eye
    $eye.Show.Add_Click({ param($button) Set-NewPasswordShown $button.CommandParameter $true })
    $eye.Hide.Add_Click({ param($button) Set-NewPasswordShown $button.CommandParameter $false })
    Set-NewPasswordShown $eye $false
    $shown.FindName('user_new_password_copy').CommandParameter = $Password
    $shown.FindName('user_new_password_copy').Add_Click({ param($button) Show-CopyFeedback $button (Set-SecretClipboard ([string]$button.CommandParameter)) })
    $message = if ($Unsure) { (Tr "Le contrôleur de domaine n'a pas répondu en {0} secondes : le mot de passe a peut-être été réinitialisé. Vérifiez-le (Propriétés, Actualiser) ; s'il l'a été, c'est celui-ci. Il n'est gardé nulle part.") -f $Timeout }
               elseif ($MustChange) { Tr "Communiquez-le à la personne. Elle devra le changer à sa prochaine connexion. Il n'est gardé nulle part." }
               else { Tr "Communiquez-le à la personne. Il reste valable tel quel. Il n'est gardé nulle part." }
    $Problems = @($Problems | Where-Object { $_ })
    if ($Problems.Count) { $message += "`n`n⚠ $($Problems -join (Tr ' ; '))." }
    $warn = $Unsure -or $Problems.Count
    Show-Dialog -Title (Tr 'Mot de passe réinitialisé') -Heading ((Tr 'Nouveau mot de passe de {0}') -f $Row.Name) -Icon $(if ($Unsure) { 'warning' } else { 'checkcircle' }) -Tone $(if ($warn) { 'warn' } else { 'success' }) `
        -Message $message -Content $shown -Owner $Owner
}
