# Every parameter by name: a stray word on the command line is reported as such, rather than taken as a number of fake
# computers. What PowerShell would refuse before any of this script runs (an option it doesn't know, a value too many,
# a language Repère doesn't have) is taken in and refused below instead, in a dialog: started by Repère.cmd, whose
# console is hidden, PowerShell's own refusal shows nowhere.
[CmdletBinding(PositionalBinding = $false)]
param(
    # Use the fake AD (FakeAD\FakeAD.psm1) even on a computer joined to a domain.
    [switch]$FakeAD,

    # With the fake AD, adds this many computers to demo.local (PC-001, PC-002…) to try large results.
    [int]$ExtraFakeComputers = 0,

    # The domains offered in the Domaine list, in this order, e.g. -Domains corp.example.com,child.corp.example.com
    # (no spaces with pwsh -File). Empty = every domain of the user's forest.
    [string[]]$Domains = @(),

    # Where « Déplacer vers… » can move computers: these OUs and those under them, separated by semicolons, e.g.
    # -MoveRoots "OU=Postes,DC=corp,DC=example,DC=com;OU=Kiosques,DC=corp,DC=example,DC=com". Empty = every OU
    # (except Domain Controllers) and the default computers container.
    [string[]]$MoveRoots = @(),

    # The language of the windows, fr or en, instead of the one chosen in Paramètres (by default, Windows's). Checked
    # below, not by a ValidateSet.
    [string]$Language = '',

    # Don't ask GitHub whether a newer Repère is out (it's asked once at each start, otherwise).
    [switch]$NoUpdateCheck,

    # What the command line has besides the parameters above: an option misspelled, or a word too many, as the space in
    # -Domains a.local, b.local makes. Refused below, by name.
    [Parameter(ValueFromRemainingArguments, DontShow)]
    [string[]]$UnknownArguments = @()
)

# Repère's version, shown in Paramètres; tools\New-RepereRelease.ps1 names the release after it (CHANGELOG.md says
# what each one brought).
$script:RepereVersion = '0.15.1'

# For the UI tests' -Strict: a variable never set, or a property an object doesn't have, is an error instead of a
# silent $null.
if ($env:REPERE_STRICT) {
    Set-StrictMode -Version Latest
    # Room for every error of a session in $Error, written as they come (Write-StrictError).
    Set-Variable -Name MaximumErrorCount -Value 32768 -Scope Global
}

# What stops Repère before its window opens: said in the console, and in a dialog too, since launched from a shortcut
# the console closes as soon as Repère exits (Repère.cmd hides it from the start). No dialog where nobody could close
# it (a service, a task run without a session, pwsh -NonInteractive). Written for any PowerShell, since it also tells an
# older one to upgrade. Defined before any other file loads, for the trap below: until Language.ps1 has loaded, there's
# no Tr, and the title is the French one.
function Exit-Repere([string]$Message) {
    $Host.UI.WriteErrorLine($Message)
    # The splash (Splash.ps1), once it's shown, goes first.
    if (Get-Command Close-RepereSplash -ErrorAction Ignore) { Close-RepereSplash }
    if ([Environment]::UserInteractive -and -not ([Environment]::GetCommandLineArgs() -match '^-noni')) {
        Add-Type -AssemblyName PresentationFramework
        $title = if (Get-Command Tr -ErrorAction Ignore) { Tr 'Repère' } else { 'Repère' }
        $null = [System.Windows.MessageBox]::Show($Message, $title, 'OK', 'Error')
    }
    exit 1
}

# An error that stops a statement before the window shows (a file that doesn't parse, a module that doesn't load, a
# bug) stops Repère, and says why, with where: otherwise the script would carry on to a window half made, or end
# without a word where nobody sees its console. A trap covers the whole script wherever it's written; once the window
# shows, it does nothing, and an error is written and the script carries on as without it (the event handlers' errors
# are the Dispatcher's, below). With a PowerShell older than 7.5, what it can't run is left to the version check below,
# which says what to do about it.
$script:RepereStarting = $true
trap {
    if ($script:RepereStarting -and $PSVersionTable.PSVersion -ge [version]'7.5') {
        # A parse error's message already says where; for the others, the line that failed, as the console shows it.
        $reason = $_.Exception.Message
        if ($_.Exception -isnot [System.Management.Automation.ParseException] -and $_.InvocationInfo) { $reason += "`n$($_.InvocationInfo.PositionMessage)" }
        $text = if (Get-Command Tr -ErrorAction Ignore) { Tr "Repère n'a pas pu démarrer : {0}" } else { "Repère n'a pas pu démarrer : {0}" }
        Exit-Repere ($text -f $reason)
    }
}

# The settings files (Settings.ps1), then Repère's language (Language.ps1), saved there: first, so that the text made
# as the other files load, and the reasons to stop below, are in it. A -Language Repère doesn't have is refused below,
# in the language chosen in Paramètres.
. "$PSScriptRoot\Settings.ps1"
. "$PSScriptRoot\Language.ps1"
Initialize-Language $(if ($Language -in 'fr', 'en') { $Language } else { '' })

# The window uses WPF's Fluent theme, which comes with PowerShell 7.5 (.NET 9) and later. Repère.cmd offers to install
# it; started some other way (pwsh -File by hand), Repère only says what's needed, and installs nothing unasked.
if ($PSVersionTable.PSVersion -lt [version]'7.5') {
    Exit-Repere ((Tr 'Repère demande PowerShell 7.5 ou plus récent (installé : {0}). Installez-le avec winget install --id Microsoft.PowerShell --source winget, puis relancez Repère : pwsh -File "{1}"') -f $PSVersionTable.PSVersion, $PSCommandPath)
}

# The launch options PowerShell let through (see the param block): a shortcut's target is where they're mistyped.
if ($Language -and $Language -notin 'fr', 'en') {
    Exit-Repere ((Tr 'Langue inconnue pour -Language : « {0} ». Repère est en français (-Language fr) ou en anglais (-Language en).') -f $Language)
}
if ($UnknownArguments.Count) {
    Exit-Repere ((Tr 'Option de lancement inconnue : {0}. Les options sont -Domains, -MoveRoots, -Language et -NoUpdateCheck ; une liste s''écrit sans espace après les virgules, comme -Domains a.local,b.local. Vérifiez la cible du raccourci.') -f ($UnknownArguments -join ' '))
}

Add-Type -AssemblyName PresentationFramework
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Exit-Repere ((Tr 'La fenêtre de Repère demande un thread STA : relancez Repère sans -MTA (pwsh -File "{0}").') -f $PSCommandPath)
}
# Repère's own button in the taskbar, not PowerShell's: set before any window opens.
. "$PSScriptRoot\Taskbar.ps1"
Set-RepereAppId
# The splash, on a thread of its own, while the rest loads and the window is made: closed once the window has drawn.
. "$PSScriptRoot\Splash.ps1"
Show-RepereSplash "$PSScriptRoot\compass.png"

# AD's English error messages in French when Repère is (ConvertTo-FrenchError), for everything that shows text.
. "$PSScriptRoot\Errors.ps1"
# Colors, icons, shared styles and the Apparence menu (theme and accent color).
. "$PSScriptRoot\Theme.ps1"
Initialize-Theme
# The Caractéristiques window, opened from the results.
. "$PSScriptRoot\SpecsWindow.ps1"
# Redémarrer… and Annuler le redémarrage.
. "$PSScriptRoot\RestartDialog.ps1"
# Groupes….
. "$PSScriptRoot\GroupsDialog.ps1"
. "$PSScriptRoot\BitLockerDialog.ps1"
. "$PSScriptRoot\LapsDialog.ps1"
# Prendre la main….
. "$PSScriptRoot\ShadowSession.ps1"
# What Forcer les stratégies and PowerShell à distance run on a computer without WinRM.
. "$PSScriptRoot\RemoteAccess.ps1"
# Paramètres.
. "$PSScriptRoot\SettingsWindow.ps1"
# Nouveautés: what a new version brought, at its first start and from Paramètres.
. "$PSScriptRoot\Changelog.ps1"
# The Propriétés windows' and dialogs' reads, on the search runspaces.
. "$PSScriptRoot\Background.ps1"
# What asks SCCM (Prochain nom…, Paramètres › SCCM).
. "$PSScriptRoot\Sccm.ps1"
# The results grids' column filters (each page's).
. "$PSScriptRoot\ColumnFilter.ps1"
# Selecting a cell's text in the results grids.
. "$PSScriptRoot\GridText.ps1"
# Recherche avancée: the Ordinateurs search's criteria, wired by ComputerPage.ps1.
. "$PSScriptRoot\AdvancedSearch.ps1"
# The Utilisateurs and Groupes pages: what they share, then each.
. "$PSScriptRoot\SearchPage.ps1"
. "$PSScriptRoot\UserPage.ps1"
. "$PSScriptRoot\UserDetails.ps1"
. "$PSScriptRoot\GroupPage.ps1"
. "$PSScriptRoot\GroupDetails.ps1"
# Propriétés… of a computer (the Ordinateurs page), in the same window.
. "$PSScriptRoot\ComputerDetails.ps1"
# Comparer les groupes… of two users.
. "$PSScriptRoot\GroupCompare.ps1"
# Ajouter à un groupe… and Retirer d'un groupe… for the users or computers selected.
. "$PSScriptRoot\SelectionGroups.ps1"
# Prochain nom…: the next free name of a series, in AD and SCCM.
. "$PSScriptRoot\NextName.ps1"

# Off a domain there's no AD to search, so use the fake AD (demo.local and nord.demo.local) to try the app out.
# This checks domain membership, not whether a DC answers, so an unreachable domain still shows an error. The fake AD
# is only in a clone of the repository: the release zip leaves it out. A WMI that doesn't answer (its repository
# damaged, its service stopped) is said as such: its $null would read as a computer off a domain. -FakeAD does
# without it.
$computerSystem = try { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop }
catch {
    if (-not $FakeAD) {
        Exit-Repere ((Tr 'Repère ne peut pas savoir si cet ordinateur est joint à un domaine : WMI ne répond pas (Win32_ComputerSystem : {0}). Redémarrer le service Infrastructure de gestion Windows (Winmgmt), ou l''ordinateur, règle souvent ce problème.') -f $_.Exception.Message)
    }
    $null
}
$useFakeAD = $FakeAD -or -not $computerSystem.PartOfDomain
if ($useFakeAD -and -not (Test-Path -LiteralPath "$PSScriptRoot\FakeAD\FakeAD.psm1")) {
    if ($FakeAD) { Exit-Repere (Tr "AD fictif introuvable : les données d'exemple ne sont que dans le dépôt, pas dans le zip de la release.") }
    Exit-Repere (Tr "Cet ordinateur n'est pas joint à un domaine : Repère a besoin d'Active Directory.")
}
if ($useFakeAD) {
    Write-Host (Tr 'AD fictif utilisé (ordinateur hors domaine ou -FakeAD).')
    if ($ExtraFakeComputers -gt 0) { $env:REPERE_FAKEAD_EXTRA_COMPUTERS = $ExtraFakeComputers }
    Import-Module "$PSScriptRoot\FakeAD\FakeAD.psm1" -ErrorAction Stop
}
else {
    # The ActiveDirectory module takes a second or two to load: it's loaded once the window shows (Repère's own
    # commands only need it for the actions; each search runspace loads its own copy in the background). Without the
    # AD: drive, which contacts a DC as the module loads (here and in each search runspace).
    $env:ADPS_LoadDefaultDrive = 0
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Exit-Repere (Tr 'Module ActiveDirectory introuvable : installez les outils RSAT pour Active Directory.')
    }
}

# The computer Repère runs on and the account running it, each with its Domain: Repère won't disable, delete or move
# them (ComputerActions.ps1, UserPage.ps1), which would cut its user off. With the fake AD, none, unless the UI tests
# name them ($env:REPERE_FAKEAD_COMPUTER, ORD-02.demo.local; $env:REPERE_FAKEAD_USER, login@demo.local).
# The computer's CN, the name the rows show, isn't always its name: renamed in ADUC, created under another one, or
# renamed in the domain and not restarted yet. So Computer holds its names, the one it has and the one it takes at its
# next restart (already its name in AD), and ComputerDN its DN as Windows wrote it at its last policy refresh: both from
# the registry, which takes no time. AD is asked only when an action needs it (Get-SelfComputerDN), not at launch.
$script:Self = if (-not $useFakeAD) {
    # A value that isn't there (policy never applied) still writes an error with SilentlyContinue: caught instead.
    $pendingName = try { Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop } catch { $null }
    $policyDN = try { Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine' -Name Distinguished-Name -ErrorAction Stop } catch { $null }
    @{ Computer = @([string]$computerSystem.Name, [string]$pendingName | Where-Object { $_ } | Sort-Object -Unique); ComputerDN = [string]$policyDN
       ComputerDomain = [string]$computerSystem.Domain; User = [string]$env:USERNAME; UserDomain = [string]$env:USERDNSDOMAIN }
}
else {
    $computer = "$env:REPERE_FAKEAD_COMPUTER" -split '\.', 2
    $user = "$env:REPERE_FAKEAD_USER" -split '@', 2
    @{ Computer = @($computer[0] | Where-Object { $_ }); ComputerDN = ''; ComputerDomain = $computer[-1]; User = $user[0]; UserDomain = $user[-1] }
}

function Test-SelfAccount([string]$Name, [string]$Domain, [switch]$Computer) {
    # Whether this is the computer Repère runs on (-Computer), by one of its names, or the account running it. Never
    # with an empty name. A computer's DN says it better (Get-ComputerGuard): its CN isn't always its name.
    $self = $script:Self
    $selfNames = if ($Computer) { $self.Computer } else { $self.User }
    $selfDomain = if ($Computer) { $self.ComputerDomain } else { $self.UserDomain }
    [bool]$Name -and $Domain -eq $selfDomain -and @($selfNames) -contains $Name
}

# The domains to search: -Domains, or every domain of the forest. With pwsh -File, "a.local,b.local" arrives
# as one string, so it's split here.
$domainList = @($Domains -split ',' | ForEach-Object Trim | Where-Object { $_ })
# A DN has commas of its own, so the roots are separated by semicolons. Without -MoveRoots, those chosen in Paramètres.
$moveRootList = @($MoveRoots -split ';' | ForEach-Object Trim | Where-Object { $_ })
$Settings.Imposed = [bool]$moveRootList.Count
if (-not $Settings.Imposed) { $moveRootList = @(Read-SavedMoveRoot) }
if (-not $domainList.Count) {
    try {
        # The real forest through .NET, which doesn't need the ActiveDirectory module (it isn't loaded yet).
        $domainList = if ($useFakeAD) { @((Get-ADForest -Current LoggedOnUser -ErrorAction Stop).Domains) }
                      else {
                          Add-Type -AssemblyName System.DirectoryServices
                          @([System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Domains | ForEach-Object { [string]$_.Name })
                      }
    }
    catch {
        # Off the network the forest can't be read: offer only the user's domain, whose searches then show the error.
        Write-Host ((Tr 'Domaines de la forêt non lus : {0}') -f $_)
        $domainList = @(if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN.ToLowerInvariant() } else { $computerSystem.Domain })
    }
}
# Start on the user's own domain when it's offered.
$defaultDomain = $domainList | Where-Object { $_ -eq $env:USERDNSDOMAIN } | Select-Object -First 1
if (-not $defaultDomain) { $defaultDomain = $domainList[0] }
# The Domaine list and column only show when there's a choice to make.
$showDomains = $domainList.Count -gt 1
Write-Host ((Tr 'Domaines : {0}') -f ($domainList -join ', '))

# Searches run in background runspaces, so the window stays responsive and can cancel them, and each domain is
# searched on its own runspace, in parallel (up to 4 at once). The runspaces load the AD module once, in the
# background, while the window opens. They follow the process's execution policy as it is, without being given it:
# Get-ExecutionPolicy would load its module first, a tenth of a second of the start.
$searchModule = if ($useFakeAD) { "$PSScriptRoot\FakeAD\FakeAD.psm1" } else { 'ActiveDirectory' }
$searchSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
$searchSessionState.ImportPSModule($searchModule)
# Spare runspaces (up to twice as many) for the next searches while a cancelled query stuck on a DC ends on its own.
$searchThreadCount = [Math]::Min([Math]::Max($domainList.Count, 1), 4)
$searchPool = [runspacefactory]::CreateRunspacePool($searchThreadCount, 2 * $searchThreadCount, $searchSessionState, $Host)
$null = $searchPool.BeginOpen($null, $null)

# The window: an app bar, the actions on the selected computers, the search, then the results.
# {{icon:name}} is replaced by that icon (Theme.ps1). The bars' gaps and the search row's, the buttons' and the rows'
# heights follow the density chosen (Theme.ps1, Set-UiDensity).
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.
$windowXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <Grid>
  <DockPanel>

    <!-- The app bar is also the window's title bar (Set-WindowChrome): dragging it moves the window, and the window's buttons
         end it. -->
    <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Height="52" Padding="16,0,0,0">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Image x:Name="logo" Width="26" Height="26"/>
          <TextBlock Text="Repère" FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" VerticalAlignment="Center" Margin="10,0,0,0"/>
          <!-- Makes it obvious that the results don't come from the real AD. -->
          <Border x:Name="fake_ad_badge" Style="{StaticResource Pill.Warn}" VerticalAlignment="Center" Margin="10,0,0,0" Visibility="Collapsed"><TextBlock Text="AD fictif"/></Border>
          <!-- The pages: computers, users (UserPage.ps1) or groups (GroupPage.ps1). Ctrl+1, Ctrl+2 and Ctrl+3 too. -->
          <StackPanel Orientation="Horizontal" Margin="24,0,0,0" VerticalAlignment="Center">
            <ToggleButton x:Name="tab_computers" Style="{StaticResource Toggle.Tab}" IsChecked="True" ToolTip="Ordinateurs (Ctrl+1)" AutomationProperties.Name="Ordinateurs">
              <StackPanel Orientation="Horizontal">{{icon:monitor:15}}<TextBlock Text="Ordinateurs" Margin="7,0,0,0"/></StackPanel>
            </ToggleButton>
            <ToggleButton x:Name="tab_users" Style="{StaticResource Toggle.Tab}" Margin="4,0,0,0" ToolTip="Utilisateurs (Ctrl+2)" AutomationProperties.Name="Utilisateurs">
              <StackPanel Orientation="Horizontal">{{icon:user:15}}<TextBlock Text="Utilisateurs" Margin="7,0,0,0"/></StackPanel>
            </ToggleButton>
            <ToggleButton x:Name="tab_groups" Style="{StaticResource Toggle.Tab}" Margin="4,0,0,0" ToolTip="Groupes (Ctrl+3)" AutomationProperties.Name="Groupes">
              <StackPanel Orientation="Horizontal">{{icon:users:15}}<TextBlock Text="Groupes" Margin="7,0,0,0"/></StackPanel>
            </ToggleButton>
          </StackPanel>
        </StackPanel>
        <!-- Paramètres: the themes, Déplacer vers, Redémarrage and Raccourcis, in a window of their own (SettingsWindow.ps1). -->
        <Button x:Name="settings" Grid.Column="2" Style="{StaticResource Btn.Ghost}" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            {{icon:settings}}<TextBlock Text="Paramètres" Margin="8,0,0,0"/>
            <!-- A newer Repère is out: Paramètres says which, with a link to it (Update-ReleaseNotice). -->
            <Ellipse x:Name="settings_update_dot" Width="7" Height="7" Margin="5,0,0,0" VerticalAlignment="Top" Fill="{DynamicResource R.Accent}" Visibility="Collapsed"/>
          </StackPanel>
        </Button>
        <StackPanel x:Name="caption_buttons" Grid.Column="3" Orientation="Horizontal" Margin="12,0,0,0"/>
      </Grid>
    </Border>

    <!-- What an action did (Show-ActionNotice): a bar along the bottom of the window, under the page's status bar, for a
         few seconds, longer while the mouse is on it or its text is long. It covers no row: the page gets shorter by its
         height while it shows. It reads as « Désactivé : ✔ ORD-10 » for UI Automation (action_notice). -->
    <Border x:Name="toast" DockPanel.Dock="Bottom" Padding="16,6,8,6" Background="{DynamicResource R.Surface}"
            BorderBrush="{DynamicResource R.BorderStrong}" BorderThickness="0,1,0,0" Visibility="Collapsed">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border x:Name="toast_icon" Width="22" Height="22" CornerRadius="6" VerticalAlignment="Center"/>
        <!-- « Titre : texte » on one line, wrapped to a second rather than cut (« hors ligne (pas de réponse au ping ni
             aux ports 445 et 3389) » whole); beyond, the tooltip has it all. -->
        <TextBlock x:Name="action_notice" Grid.Column="1" Margin="10,0,8,0" VerticalAlignment="Center" FontSize="12"
                   TextWrapping="Wrap" TextTrimming="CharacterEllipsis" MaxHeight="34">
          <Run x:Name="toast_title" FontWeight="{DynamicResource R.FontWeightStrong}"/><Run x:Name="toast_text" Foreground="{DynamicResource R.Muted}"/>
        </TextBlock>
        <Button x:Name="toast_close" Grid.Column="2" Style="{StaticResource Btn.Mini}" VerticalAlignment="Center" ToolTip="Fermer" AutomationProperties.Name="Fermer la notification">{{icon:x:12}}</Button>
      </Grid>
    </Border>

    <!-- The page shown: the computers' (below), the users' or the groups' (users_page, groups_page, filled by UserPage.ps1
         and GroupPage.ps1 when first shown). -->
    <Grid>
    <DockPanel x:Name="computers_page">

    <!-- The same actions as the right-click menu, for the selected computers. The arrows of the split buttons open their menu.
         The icon buttons show their label too when the window is wide enough; when it's narrow, Vérifier en ligne,
         Caractéristiques and Désactiver lose theirs (Update-ActionLabel). -->
    <Grid x:Name="action_row" DockPanel.Dock="Top" Margin="{DynamicResource R.ActionRowMargin}">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel x:Name="action_bar" Orientation="Horizontal">
        <StackPanel Orientation="Horizontal">
          <Button x:Name="act_rdp" Style="{StaticResource Btn.Primary}" Tag="6,0,0,6" ToolTip="Un ordinateur à la fois" ToolTipService.ShowOnDisabled="True">
            <StackPanel Orientation="Horizontal">{{icon:monitor}}<TextBlock Text="Bureau à distance" Margin="8,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="act_remote_more" Style="{StaticResource Btn.Primary}" Tag="0,6,6,0" Padding="9,6" Margin="1,0,0,0" ToolTip="Autres outils à distance">
            {{icon:chevron:12}}
            <Button.ContextMenu>
              <ContextMenu>
                <MenuItem x:Name="act_shadow" Header="Prendre la main…"><MenuItem.Icon>{{icon:screenshare}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_sessions" Header="Utilisateurs connectés…"><MenuItem.Icon>{{icon:user}}</MenuItem.Icon></MenuItem>
                <Separator/>
                <MenuItem x:Name="act_compmgmt" Header="Gestion de l'ordinateur"><MenuItem.Icon>{{icon:sliders}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_c_share" Header="Ouvrir C$"><MenuItem.Icon>{{icon:folder}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_pwsh" Header="PowerShell à distance"><MenuItem.Icon>{{icon:terminal}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_services" Header="Services"><MenuItem.Icon>{{icon:server}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_events" Header="Observateur d'événements"><MenuItem.Icon>{{icon:list}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_gpupdate" Header="Forcer les stratégies (gpupdate)"><MenuItem.Icon>{{icon:refresh}}</MenuItem.Icon></MenuItem>
                <Separator/>
                <MenuItem x:Name="act_restart" Header="Redémarrer…"><MenuItem.Icon>{{icon:power}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="act_restart_cancel" Header="Annuler le redémarrage"><MenuItem.Icon>{{icon:xcircle}}</MenuItem.Icon></MenuItem>
              </ContextMenu>
            </Button.ContextMenu>
          </Button>
        </StackPanel>
        <Button x:Name="act_ping" Margin="8,0,0,0" ToolTip="Dans la colonne En ligne, avec l'adresse IP (Ctrl+A pour tous les ordinateurs)" ToolTipService.ShowOnDisabled="True">
          <StackPanel Orientation="Horizontal">{{icon:activity}}<TextBlock x:Name="act_ping_label" Text="Vérifier en ligne" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <Button x:Name="act_specs" Margin="8,0,0,0" ToolTip="Matériel, Windows et réseau de l'ordinateur (un à la fois, ou double-clic)" ToolTipService.ShowOnDisabled="True">
          <StackPanel Orientation="Horizontal">{{icon:cpu}}<TextBlock x:Name="act_specs_label" Text="Caractéristiques" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <!-- Désactiver… or Activer, as the selected computers are (Update-MenuItem). -->
        <Button x:Name="act_toggle" Margin="8,0,0,0" ToolTipService.ShowOnDisabled="True">
          <StackPanel Orientation="Horizontal">
            <Grid x:Name="act_toggle_disable_icon">{{icon:ban}}</Grid>
            <Grid x:Name="act_toggle_enable_icon" Visibility="Collapsed">{{icon:checkcircle}}</Grid>
            <TextBlock x:Name="act_toggle_text" Text="Désactiver…" Margin="8,0,0,0"/>
          </StackPanel>
        </Button>
        <Button x:Name="act_edit" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Modifier la description… (F2)" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:pencil}}<TextBlock x:Name="act_edit_label" Text="Description" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <Button x:Name="act_move" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Déplacer vers…" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:move}}<TextBlock x:Name="act_move_label" Text="Déplacer" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <Button x:Name="act_groups" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Groupes… (un ordinateur à la fois)" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:users}}<TextBlock x:Name="act_groups_label" Text="Groupes" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <!-- The one button that needs no selection: with none, Prochain nom… opens on the last format used. -->
        <Button x:Name="act_next_name" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Prochain nom libre d'une série… (Ctrl+N)"><StackPanel Orientation="Horizontal">{{icon:list}}<TextBlock x:Name="act_next_name_label" Text="Prochain nom" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <Button x:Name="act_bitlocker" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Clés BitLocker…" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:drivelock}}<TextBlock x:Name="act_bitlocker_label" Text="BitLocker" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <Button x:Name="act_laps" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Mot de passe LAPS…" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:key}}<TextBlock x:Name="act_laps_label" Text="LAPS" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <Button x:Name="act_copy" Style="{StaticResource Btn.Icon}" Margin="8,0,0,0" ToolTip="Copier le nom (Ctrl+C)" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock x:Name="act_copy_label" Text="Copier" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
        <Button x:Name="act_remove" Style="{StaticResource Btn.IconDanger}" Margin="8,0,0,0" ToolTip="Supprimer de l'AD… (Suppr)" ToolTipService.ShowOnDisabled="True"><StackPanel Orientation="Horizontal">{{icon:trash}}<TextBlock x:Name="act_remove_label" Text="Supprimer" Margin="8,0,0,0" Visibility="Collapsed"/></StackPanel></Button>
      </StackPanel>
      <TextBlock x:Name="selection_text" Grid.Column="2" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Text="Aucune sélection"/>
    </Grid>

    <!-- Search: the domain and search type, then the name prefix and the description in one field. Above the rows below
         it (ZIndex), for what a search is missing (search_hint). -->
    <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.SearchRowMargin}" Panel.ZIndex="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="10"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel x:Name="scope_panel" Orientation="Horizontal">
        <ComboBox x:Name="domain" MinWidth="170" Height="{DynamicResource R.BarHeight}" Margin="0,0,6,0" VerticalContentAlignment="Center" ToolTip="Domaine" ItemContainerStyle="{StaticResource Combo.Item}"/>
        <ComboBox x:Name="search_type" MinWidth="210" Height="{DynamicResource R.BarHeight}" VerticalContentAlignment="Center" ItemContainerStyle="{StaticResource Combo.Item}"/>
      </StackPanel>
      <Border x:Name="search_field" Grid.Column="2" Style="{StaticResource Field}" Height="{DynamicResource R.BarHeight}">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="2*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="3*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border Margin="12,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:search}}</Border>
          <TextBox x:Name="prefix" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Nom contient…" ToolTip="Partie du nom des ordinateurs, ex. ORD- (Ctrl+F)"/>
          <Border x:Name="search_divider" Grid.Column="2" Width="1" Background="{DynamicResource R.Border}" Margin="4,9"/>
          <TextBox x:Name="search_term" Grid.Column="3" Style="{StaticResource Text.Bare}" Tag="Description (ex. accueil)" ToolTip="Une partie de la description"/>
          <!-- The last searches, to run one again (or ↓ in either box). -->
          <Button x:Name="recent_searches" Grid.Column="4" Style="{StaticResource Btn.Mini}" Margin="0,0,5,0" ToolTip="Recherches récentes (↓)" AutomationProperties.Name="Recherches récentes">
            {{icon:history:15}}
            <Button.ContextMenu><ContextMenu x:Name="recent_menu"/></Button.ContextMenu>
          </Button>
        </Grid>
      </Border>
      <!-- Recherche avancée (AdvancedSearch.ps1): its criteria in a popup, out of the way; the button says how many are set. -->
      <Button x:Name="advanced" Grid.Column="4" Height="{DynamicResource R.BarHeight}" Padding="12,0" ToolTip="Recherche avancée : emplacement, état, système, dernière connexion">
        <StackPanel Orientation="Horizontal">{{icon:sliders}}<TextBlock x:Name="advanced_text" Text="Avancée" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <!-- Buttons rather than lists: a list's drop-down would close this popup. Its notes don't widen it. -->
      <Popup x:Name="advanced_popup" Grid.Column="4" PlacementTarget="{Binding ElementName=advanced}" Placement="Custom" StaysOpen="False" AllowsTransparency="True">
        <Border x:Name="advanced_panel" Style="{StaticResource Card}" Padding="14" MinWidth="380" Margin="0,4,10,10">
          <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Opacity="0.25"/></Border.Effect>
          <!-- Scrolls when the room under Avancée is short, at a large text size (Set-AdvancedPopupRoom). -->
          <ScrollViewer x:Name="advanced_scroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <StackPanel>
            <TextBlock FontWeight="{DynamicResource R.FontWeightStrong}" Margin="2,0,0,10" Text="Recherche avancée"/>
            <TextBlock Style="{StaticResource Txt.Muted}" Margin="2,0,0,6" Text="Emplacement"/>
            <Border BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Height="{DynamicResource R.ControlHeight}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <RadioButton x:Name="advanced_scope_all" GroupName="advanced_scope" Style="{StaticResource Toggle.Seg}" Tag="5,0,0,5" Padding="10,0" Content="Partout"/>
                <RadioButton x:Name="advanced_scope_ou" GroupName="advanced_scope" Style="{StaticResource Toggle.Seg}" Grid.Column="1" Padding="10,0" Content="Une OU"/>
                <RadioButton x:Name="advanced_scope_name" GroupName="advanced_scope" Style="{StaticResource Toggle.Seg}" Grid.Column="2" Tag="0,5,5,0" Padding="10,0" Content="OU nommées"/>
              </Grid>
            </Border>
            <Grid x:Name="advanced_ou_row" Margin="0,8,0,0" Visibility="Collapsed">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Border Margin="2,0,8,0" VerticalAlignment="Center" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:folder:14}}</Border>
              <TextBlock x:Name="advanced_ou_text" Grid.Column="1" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
              <Button x:Name="advanced_ou_pick" Grid.Column="2" Margin="8,0,0,0" Content="Choisir…" ToolTip="Choisir l'OU où chercher"/>
            </Grid>
            <Grid x:Name="advanced_name_row" Margin="0,8,0,0" Visibility="Collapsed">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <TextBlock Style="{StaticResource Txt.Muted}" Margin="2,0,8,0" VerticalAlignment="Center" Text="Nom commence par"/>
              <TextBox x:Name="advanced_ou_name" Grid.Column="1" AutomationProperties.Name="Nom des OU commence par"/>
            </Grid>
            <TextBlock x:Name="advanced_scope_note" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="0,6,0,0" Padding="2,0,0,0" TextWrapping="Wrap" Visibility="Collapsed"
                       Width="{Binding ActualWidth, ElementName=advanced_footer}" Text="Et les OU qu'elles contiennent."/>
            <TextBlock Style="{StaticResource Txt.Muted}" Margin="2,14,0,6" Text="Compte"/>
            <Border BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Height="{DynamicResource R.ControlHeight}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <RadioButton x:Name="advanced_state_all" GroupName="advanced_state" Style="{StaticResource Toggle.Seg}" Tag="5,0,0,5" Padding="10,0" Content="Tous"/>
                <RadioButton x:Name="advanced_state_enabled" GroupName="advanced_state" Style="{StaticResource Toggle.Seg}" Grid.Column="1" Padding="10,0" Content="Activés"/>
                <RadioButton x:Name="advanced_state_disabled" GroupName="advanced_state" Style="{StaticResource Toggle.Seg}" Grid.Column="2" Tag="0,5,5,0" Padding="10,0" Content="Désactivés"/>
              </Grid>
            </Border>
            <TextBlock Style="{StaticResource Txt.Muted}" Margin="2,14,0,6" Text="Système contient"/>
            <Border Style="{StaticResource Field}" Height="{DynamicResource R.ControlHeight}">
              <TextBox x:Name="advanced_system" Style="{StaticResource Text.Bare}" Tag="ex. Windows 10, Server" AutomationProperties.Name="Système contient"/>
            </Border>
            <Grid Margin="2,14,0,6">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Style="{StaticResource Txt.Muted}" Text="Dernière connexion il y a"/>
              <!-- AD updates lastLogonTimestamp only every 9 to 14 days. -->
              <TextBlock Grid.Column="1" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="12,0,0,0" VerticalAlignment="Bottom" Text="à 2 semaines près"/>
            </Grid>
            <Border BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Height="{DynamicResource R.ControlHeight}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <RadioButton x:Name="advanced_logon_any" GroupName="advanced_logon" Style="{StaticResource Toggle.Seg}" Tag="5,0,0,5" Padding="10,0" Content="Peu importe"/>
                <RadioButton x:Name="advanced_logon_atleast" GroupName="advanced_logon" Style="{StaticResource Toggle.Seg}" Grid.Column="1" Padding="10,0" Content="Plus de"/>
                <RadioButton x:Name="advanced_logon_less" GroupName="advanced_logon" Style="{StaticResource Toggle.Seg}" Grid.Column="2" Tag="0,5,5,0" Padding="10,0" Content="Moins de"/>
              </Grid>
            </Border>
            <Grid x:Name="advanced_logon_amount" Margin="0,8,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="96"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <TextBox x:Name="advanced_logon_number" MaxLength="3" AutomationProperties.Name="Durée"/>
              <Border Grid.Column="1" Margin="8,0,0,0" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Height="{DynamicResource R.ControlHeight}">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <RadioButton x:Name="advanced_logon_unit0" GroupName="advanced_unit" Style="{StaticResource Toggle.Seg}" Tag="5,0,0,5" Padding="8,0" Content="jours"/>
                  <RadioButton x:Name="advanced_logon_unit1" GroupName="advanced_unit" Style="{StaticResource Toggle.Seg}" Grid.Column="1" Padding="8,0" Content="semaines"/>
                  <RadioButton x:Name="advanced_logon_unit2" GroupName="advanced_unit" Style="{StaticResource Toggle.Seg}" Grid.Column="2" Padding="8,0" Content="mois"/>
                  <RadioButton x:Name="advanced_logon_unit3" GroupName="advanced_unit" Style="{StaticResource Toggle.Seg}" Grid.Column="3" Tag="0,5,5,0" Padding="8,0" Content="ans"/>
                </Grid>
              </Border>
            </Grid>
            <CheckBox x:Name="advanced_logon_never" Margin="2,10,0,0" Content="Inclure « Jamais »"/>
            <Grid x:Name="advanced_footer" Margin="0,14,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*" MinWidth="16"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Button x:Name="advanced_reset" Style="{StaticResource Btn.Ghost}" Content="Réinitialiser" ToolTip="Retirer tous les critères"/>
              <Button x:Name="advanced_search" Grid.Column="2" Style="{StaticResource Btn.Primary}" Content="Rechercher"/>
            </Grid>
          </StackPanel>
          </ScrollViewer>
        </Border>
      </Popup>
      <!-- IsDefault: Entrée lance la recherche. -->
      <Button x:Name="button" Grid.Column="6" Style="{StaticResource Btn.Primary}" Height="{DynamicResource R.BarHeight}" IsDefault="True" ToolTip="Entrée, ou F5 pour relancer la dernière recherche">
        <StackPanel Orientation="Horizontal">{{icon:search}}<TextBlock Text="Rechercher" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <!-- Shown while a search runs. -->
      <Button x:Name="cancel_search" Grid.Column="7" Height="{DynamicResource R.BarHeight}" Margin="8,0,0,0" Visibility="Collapsed" Content="Annuler" ToolTip="Arrêter la recherche (Échap)"/>
      <!-- What a search is missing, just under the box it's about (Show-SearchHint), over the row below and letting its
           clicks through: gone as soon as the search changes. -->
      <Canvas Grid.Column="2" Grid.ColumnSpan="6" VerticalAlignment="Bottom" Height="0" IsHitTestVisible="False">
        <Border x:Name="search_hint" Canvas.Top="6" Visibility="Collapsed" Padding="10,5" CornerRadius="6" BorderThickness="1"
                Background="{DynamicResource R.DangerBg}" BorderBrush="{DynamicResource R.DangerBorder}">
          <Border.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.2"/></Border.Effect>
          <TextBlock x:Name="search_hint_text" Foreground="{DynamicResource R.DangerText}" FontSize="12" TextWrapping="Wrap"/>
        </Border>
      </Canvas>
    </Grid>

    <Grid DockPanel.Dock="Top" Margin="{DynamicResource R.ResultsBarMargin}">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="Ordinateurs" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
        <TextBlock x:Name="results_scope" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="8,0,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <!-- The columns to show (the same menu as a right-click on a column header). -->
        <!-- The rows shown, after the filter and in the grid's order, saved as CSV. -->
        <Button x:Name="export" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" IsEnabled="False" ToolTip="Enregistrer les ordinateurs affichés en CSV (pour Excel)" ToolTipService.ShowOnDisabled="True">
          <StackPanel Orientation="Horizontal">{{icon:download}}<TextBlock Text="Exporter" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <Button x:Name="columns" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" ToolTip="Afficher ou masquer des colonnes (ou clic droit sur un en-tête)">
          <StackPanel Orientation="Horizontal">{{icon:columns}}<TextBlock Text="Colonnes" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <!-- The columns' filters in their headers (ColumnFilter.ps1): shown or hidden; a filtered column's always shows. -->
        <ToggleButton x:Name="column_filters" Height="{DynamicResource R.ControlHeight}" Margin="0,0,8,0" ToolTip="Afficher ou masquer les filtres dans les en-têtes des colonnes">
          <StackPanel Orientation="Horizontal">{{icon:filter}}<TextBlock x:Name="column_filters_text" Text="Filtres" Margin="8,0,0,0"/></StackPanel>
        </ToggleButton>
        <!-- Narrows down the rows already found, without a new search. -->
        <Border Style="{StaticResource Field}" Width="260" Height="{DynamicResource R.ControlHeight}">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
            <TextBox x:Name="filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les résultats"/>
          </Grid>
        </Border>
      </StackPanel>
    </Grid>

    <!-- Liste de noms: the names no domain had, to copy (as on Utilisateurs and Groupes, SearchPage.ps1's
         Update-PageNotFound). Each as it was searched: without its domain or a trailing $. -->
    <Border x:Name="results_not_found" DockPanel.Dock="Top" Visibility="Collapsed" Margin="16,0,16,10" Padding="12,6" CornerRadius="8" BorderThickness="1"
            Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border Margin="0,0,8,0" TextElement.Foreground="{DynamicResource R.WarnText}">{{icon:warning}}</Border>
        <TextBlock x:Name="results_not_found_text" Grid.Column="1" Foreground="{DynamicResource R.WarnText}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"
                   ToolTip="Les noms tels que cherchés : sans domaine (DEMO\, .demo.local) ni $ final"/>
        <Button x:Name="results_not_found_copy" Grid.Column="2" Style="{StaticResource Btn.Warn}" Margin="12,-2,0,-2"
                ToolTip="Copier les introuvables, un par ligne" AutomationProperties.Name="Copier">
          <StackPanel Orientation="Horizontal">{{icon:copy:13}}<TextBlock Text="Copier" Margin="6,0,0,0"/></StackPanel>
        </Button>
      </Grid>
    </Border>

    <!-- The count stays whole in a narrow window; the hint is cut short instead. -->
    <Border DockPanel.Dock="Bottom" Padding="{DynamicResource R.StatusPadding}">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal">
          <!-- Empty until the first search: « 0 ordinateur » would read as a search that found nothing. -->
          <TextBlock x:Name="results_count" Style="{StaticResource Txt.Muted}" FontSize="12"/>
          <!-- How long the last search took, in its own text so the count stays as the tests read it. -->
          <TextBlock x:Name="search_time" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="4,0,0,0"/>
          <!-- When a domain found more than the limit: the same search again, without it. -->
          <Button x:Name="results_show_all" Style="{StaticResource Btn.Ghost}" Visibility="Collapsed" Margin="8,-4,0,-4" Padding="8,2" MinHeight="0" FontSize="12"
                  Foreground="{DynamicResource R.AccentText}" Content="Tout afficher" ToolTip="La même recherche, sans limite : peut prendre un moment"/>
        </StackPanel>
        <TextBlock x:Name="status_hint" Grid.Column="1" Margin="16,0,0,0" Style="{StaticResource Txt.Faint}" FontSize="12" HorizontalAlignment="Right"
                   TextTrimming="CharacterEllipsis" Text="Clic droit sur un ordinateur : toutes les actions"/>
      </Grid>
    </Border>

    <Border Style="{StaticResource Card}" Margin="16,0">
      <Grid>
        <DataGrid x:Name="data_grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True" CanUserResizeColumns="True"
                  CanUserReorderColumns="True" CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Extended" SelectionUnit="FullRow"
                  GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{DynamicResource R.Border}" HeadersVisibility="Column"
                  Background="Transparent" RowBackground="Transparent" Foreground="{DynamicResource R.Text}" BorderThickness="0" RowHeight="{DynamicResource R.RowHeight}" Margin="1"
                  RowStyle="{StaticResource Grid.Row}" CellStyle="{StaticResource Grid.Cell}" ColumnHeaderStyle="{StaticResource Grid.Header}"
                  EnableRowVirtualization="True" VirtualizingPanel.VirtualizationMode="Recycling">
          <DataGrid.Columns>
            <DataGridTemplateColumn Header="Compte" SortMemberPath="Disabled" Width="105">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <!-- The AD account, not whether the computer is online: a monitor with a check (enabled, muted) or with a
                       cross (disabled, red). The row holds a single value, Disabled: null for an enabled computer,
                       « Désactivé » otherwise. The icons sit in a text block so screen readers (and the UI tests) read
                       Activé or Désactivé. The texts between tags, not in Value or TargetNullValue attributes, so that
                       they're translated (Language.ps1). -->
                  <TextBlock x:Name="CellTextBlock" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <AutomationProperties.Name><Binding Path="Disabled"><Binding.TargetNullValue>Activé</Binding.TargetNullValue></Binding></AutomationProperties.Name>
                    <TextBlock.Style>
                      <Style TargetType="TextBlock">
                        <Setter Property="Foreground" Value="{DynamicResource R.DangerText}"/>
                        <Setter Property="ToolTip"><Setter.Value>Compte désactivé dans l'AD</Setter.Value></Setter>
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding Disabled}" Value="{x:Null}">
                            <Setter Property="Foreground" Value="{DynamicResource R.Muted}"/><Setter Property="ToolTip"><Setter.Value>Compte activé dans l'AD</Setter.Value></Setter>
                          </DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </TextBlock.Style>
                    <InlineUIContainer BaselineAlignment="Center">
                      <Grid>
                        <Grid>
                          <Grid.Style>
                            <Style TargetType="Grid">
                              <Setter Property="Visibility" Value="Collapsed"/>
                              <Style.Triggers><DataTrigger Binding="{Binding Disabled}" Value="{x:Null}"><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers>
                            </Style>
                          </Grid.Style>
                          {{icon:monitorcheck:18}}
                        </Grid>
                        <Grid>
                          <Grid.Style>
                            <Style TargetType="Grid">
                              <Style.Triggers><DataTrigger Binding="{Binding Disabled}" Value="{x:Null}"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers>
                            </Style>
                          </Grid.Style>
                          {{icon:monitoroff:18}}
                        </Grid>
                      </Grid>
                    </InlineUIContainer>
                  </TextBlock>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="Nom" Binding="{Binding ComputerName}" SortMemberPath="ComputerName" Width="110" ElementStyle="{StaticResource Grid.Text.Strong}"/>
            <DataGridTemplateColumn Header="Description" SortMemberPath="Description" Width="2*">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <!-- No description: the row holds null, shown as « Aucune description ». -->
                  <TextBlock>
                    <TextBlock.Text><Binding Path="Description"><Binding.TargetNullValue>Aucune description</Binding.TargetNullValue></Binding></TextBlock.Text>
                    <TextBlock.Style>
                      <Style TargetType="TextBlock" BasedOn="{StaticResource Grid.Text}">
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding Description}" Value="{x:Null}">
                            <Setter Property="Foreground" Value="{DynamicResource R.Faint}"/><Setter Property="FontStyle" Value="Italic"/>
                          </DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </TextBlock.Style>
                  </TextBlock>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTemplateColumn Header="Dernière connexion" SortMemberPath="LastLogon" Width="160">
              <DataGridTemplateColumn.HeaderStyle>
                <Style TargetType="DataGridColumnHeader" BasedOn="{StaticResource Grid.Header}">
                  <Setter Property="ToolTip"><Setter.Value>À 2 semaines près</Setter.Value></Setter>
                </Style>
              </DataGridTemplateColumn.HeaderStyle>
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <TextBlock Text="{Binding LastLogonAgo}">
                    <TextBlock.ToolTip><Binding Path="LastLogonTip"><Binding.TargetNullValue>Jamais</Binding.TargetNullValue></Binding></TextBlock.ToolTip>
                    <TextBlock.Style>
                      <Style TargetType="TextBlock" BasedOn="{StaticResource Grid.Text}">
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding IsStale}" Value="True"><Setter Property="Foreground" Value="{DynamicResource R.WarnText}"/></DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </TextBlock.Style>
                  </TextBlock>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTemplateColumn Header="Système" SortMemberPath="OSBuild" Width="130">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <!-- Win 11 24H2, the full value in the tooltip, with what Repère adds about its support (a release it
                       doesn't know yet, ESU). In orange once its support has ended; « Inconnu » when AD doesn't know
                       (never logged on). Sorted by build. -->
                  <TextBlock ToolTip="{Binding OSTip}">
                    <TextBlock.Text><Binding Path="OSShort"><Binding.TargetNullValue>Inconnu</Binding.TargetNullValue></Binding></TextBlock.Text>
                    <TextBlock.Style>
                      <Style TargetType="TextBlock" BasedOn="{StaticResource Grid.Text}">
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding IsOutdated}" Value="True"><Setter Property="Foreground" Value="{DynamicResource R.WarnText}"/></DataTrigger>
                          <DataTrigger Binding="{Binding OSShort}" Value="{x:Null}">
                            <Setter Property="Foreground" Value="{DynamicResource R.Faint}"/><Setter Property="FontStyle" Value="Italic"/>
                          </DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </TextBlock.Style>
                  </TextBlock>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="Domaine" Binding="{Binding Domain}" SortMemberPath="Domain" Width="150" ElementStyle="{StaticResource Grid.Text}"/>
            <DataGridTemplateColumn Header="Emplacement" SortMemberPath="ShortPath" Width="2*">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <!-- The OU path, its domain being in Domaine. Hovering it shows the whole path, then the distinguished name. -->
                  <TextBlock Text="{Binding OUPath}" Style="{StaticResource Grid.Text}">
                    <TextBlock.ToolTip>
                      <ToolTip>
                        <StackPanel>
                          <TextBlock FontWeight="{DynamicResource R.FontWeightStrong}">
                            <TextBlock.Text><MultiBinding StringFormat="{}{0} › {1}"><Binding Path="Domain"/><Binding Path="OUPath"/></MultiBinding></TextBlock.Text>
                          </TextBlock>
                          <TextBlock Text="{Binding DistinguishedName}" FontSize="11.5" Margin="0,3,0,0" Opacity="0.75"/>
                        </StackPanel>
                      </ToolTip>
                    </TextBlock.ToolTip>
                  </TextBlock>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <!-- Filled by Vérifier en ligne, which shows it: a badge (green En ligne, red Hors ligne, grey while it checks)
                 and the address, how it answered in the tooltip. Hidden at each launch, empty after each search. The address
                 reads as « ✔ 10.0.1.11 » for UI Automation (Online). -->
            <DataGridTemplateColumn Header="En ligne" SortMemberPath="Online" Width="250">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0" ToolTip="{Binding OnlineTip}">
                    <StackPanel.Style>
                      <Style TargetType="StackPanel">
                        <Style.Triggers><DataTrigger Binding="{Binding Online}" Value="{x:Null}"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers>
                      </Style>
                    </StackPanel.Style>
                    <Border CornerRadius="9" Padding="7,1,9,1" VerticalAlignment="Center" BorderThickness="1">
                      <Border.Style>
                        <Style TargetType="Border">
                          <Setter Property="Background" Value="{DynamicResource R.Control}"/><Setter Property="BorderBrush" Value="{DynamicResource R.Border}"/>
                          <Setter Property="TextElement.Foreground" Value="{DynamicResource R.Muted}"/>
                          <Style.Triggers>
                            <DataTrigger Binding="{Binding IsOnline}" Value="True">
                              <Setter Property="Background" Value="{DynamicResource R.SuccessBg}"/><Setter Property="BorderBrush" Value="{DynamicResource R.SuccessBorder}"/>
                              <Setter Property="TextElement.Foreground" Value="{DynamicResource R.SuccessText}"/>
                            </DataTrigger>
                            <DataTrigger Binding="{Binding IsOnline}" Value="False">
                              <Setter Property="Background" Value="{DynamicResource R.DangerBg}"/><Setter Property="BorderBrush" Value="{DynamicResource R.DangerBorder}"/>
                              <Setter Property="TextElement.Foreground" Value="{DynamicResource R.DangerText}"/>
                            </DataTrigger>
                          </Style.Triggers>
                        </Style>
                      </Border.Style>
                      <StackPanel Orientation="Horizontal">
                        <Ellipse Width="7" Height="7" Margin="0,0,6,0" VerticalAlignment="Center" Fill="{Binding (TextElement.Foreground), RelativeSource={RelativeSource Self}}"/>
                        <TextBlock Text="{Binding OnlineLabel}" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}" VerticalAlignment="Center"/>
                      </StackPanel>
                    </Border>
                    <TextBlock Text="{Binding OnlineAddress}" AutomationProperties.Name="{Binding Online}" Style="{StaticResource Grid.Text}" Margin="8,0,0,0"
                               Foreground="{DynamicResource R.Muted}"/>
                  </StackPanel>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
          </DataGrid.Columns>
          <DataGrid.ContextMenu>
            <!-- Grouped in submenus, Active Directory first. A group is enabled while one of its items is (Update-MenuItem). -->
            <ContextMenu>
              <MenuItem x:Name="menu_group_ad" Header="Active Directory" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:user}}</MenuItem.Icon>
                <MenuItem x:Name="menu_properties" Header="Propriétés…" InputGestureText="Alt+Entrée" FontWeight="{DynamicResource R.FontWeightStrong}"><MenuItem.Icon>{{icon:monitor}}</MenuItem.Icon></MenuItem>
                <Separator />
                <MenuItem x:Name="menu_edit_description" Header="Modifier la description…" InputGestureText="F2"><MenuItem.Icon>{{icon:pencil}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_move" Header="Déplacer vers…"><MenuItem.Icon>{{icon:move}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_groups" Header="Groupes…"><MenuItem.Icon>{{icon:users}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_groups_add" Header="Ajouter à un groupe…"><MenuItem.Icon>{{icon:userplus}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_groups_remove" Header="Retirer d'un groupe…"><MenuItem.Icon>{{icon:userminus}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_next_name" Header="Prochain nom de cette série…" InputGestureText="Ctrl+N"><MenuItem.Icon>{{icon:list}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_enable" Header="Activer"><MenuItem.Icon>{{icon:checkcircle}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_disable" Header="Désactiver…"><MenuItem.Icon>{{icon:ban}}</MenuItem.Icon></MenuItem>
                <Separator />
                <MenuItem x:Name="menu_remove" Header="Supprimer de l'AD…"><MenuItem.InputGestureText>Suppr</MenuItem.InputGestureText><MenuItem.Icon>{{icon:trash}}</MenuItem.Icon></MenuItem>
              </MenuItem>
              <MenuItem x:Name="menu_group_keys" Header="Clés et mots de passe" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:key}}</MenuItem.Icon>
                <MenuItem x:Name="menu_bitlocker" Header="Clés BitLocker…"><MenuItem.Icon>{{icon:drivelock}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_laps" Header="Mot de passe LAPS…"><MenuItem.Icon>{{icon:key}}</MenuItem.Icon></MenuItem>
              </MenuItem>
              <MenuItem x:Name="menu_group_remote" Header="Outils à distance" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:monitor}}</MenuItem.Icon>
                <MenuItem x:Name="menu_rdp" Header="Bureau à distance"><MenuItem.Icon>{{icon:monitor}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_shadow" Header="Prendre la main…"><MenuItem.Icon>{{icon:screenshare}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_sessions" Header="Utilisateurs connectés…"><MenuItem.Icon>{{icon:user}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_ping" Header="Vérifier en ligne"><MenuItem.Icon>{{icon:activity}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_specs" Header="Caractéristiques…"><MenuItem.Icon>{{icon:cpu}}</MenuItem.Icon></MenuItem>
                <Separator />
                <MenuItem x:Name="menu_compmgmt" Header="Gestion de l'ordinateur"><MenuItem.Icon>{{icon:sliders}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_c_share" Header="Ouvrir C$"><MenuItem.Icon>{{icon:folder}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_pwsh" Header="PowerShell à distance"><MenuItem.Icon>{{icon:terminal}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_services" Header="Services"><MenuItem.Icon>{{icon:server}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_events" Header="Observateur d'événements"><MenuItem.Icon>{{icon:list}}</MenuItem.Icon></MenuItem>
                <Separator />
                <MenuItem x:Name="menu_gpupdate" Header="Forcer les stratégies (gpupdate)"><MenuItem.Icon>{{icon:refresh}}</MenuItem.Icon></MenuItem>
              </MenuItem>
              <MenuItem x:Name="menu_group_restart" Header="Redémarrage" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:power}}</MenuItem.Icon>
                <MenuItem x:Name="menu_restart" Header="Redémarrer…"><MenuItem.Icon>{{icon:power}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_restart_cancel" Header="Annuler le redémarrage"><MenuItem.Icon>{{icon:xcircle}}</MenuItem.Icon></MenuItem>
              </MenuItem>
              <MenuItem x:Name="menu_group_copy" Header="Copier" HeaderTemplate="{StaticResource Menu.GroupHeader}"><MenuItem.Icon>{{icon:copy}}</MenuItem.Icon>
                <MenuItem x:Name="menu_copy" Header="Copier le nom" InputGestureText="Ctrl+C"><MenuItem.Icon>{{icon:copy}}</MenuItem.Icon></MenuItem>
                <MenuItem x:Name="menu_copy_one_line" Header="Copier les noms sur une ligne"/>
                <MenuItem x:Name="menu_copy_rows" Header="Copier les lignes"><MenuItem.InputGestureText>Ctrl+Maj+C</MenuItem.InputGestureText></MenuItem>
              </MenuItem>
            </ContextMenu>
          </DataGrid.ContextMenu>
        </DataGrid>
        <!-- Over the grid when it shows no row (Update-EmptyState): why, what was searched, and what to try next. Only
             the links take clicks: the rest lets them through to the grid (its right-click menu). -->
        <StackPanel x:Name="grid_empty" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="16,30,16,0">
          <Border HorizontalAlignment="Center" TextElement.Foreground="{DynamicResource R.Faint}" IsHitTestVisible="False">{{icon:search:28}}</Border>
          <TextBlock x:Name="grid_empty_text" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,8,0,0" IsHitTestVisible="False"
                     Text="Entrez une partie d'un nom ou une description, puis Rechercher."/>
          <TextBlock x:Name="grid_empty_criteria" Style="{StaticResource Txt.Faint}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="640" FontSize="12"
                     Margin="0,4,0,0" Visibility="Collapsed" IsHitTestVisible="False"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">
            <TextBlock x:Name="grid_empty_all_domains" Visibility="Collapsed" Margin="8,0">
              <Hyperlink x:Name="grid_empty_all_domains_link" AutomationProperties.AutomationId="grid_empty_all_domains_link"><Run Text="Chercher dans tous les domaines"/></Hyperlink>
            </TextBlock>
            <TextBlock x:Name="grid_empty_no_advanced" Visibility="Collapsed" Margin="8,0">
              <Hyperlink x:Name="grid_empty_no_advanced_link" AutomationProperties.AutomationId="grid_empty_no_advanced_link"><Run Text="Retirer les critères avancés"/></Hyperlink>
            </TextBlock>
            <TextBlock x:Name="grid_empty_clear_filter" Visibility="Collapsed" Margin="8,0">
              <Hyperlink x:Name="grid_empty_clear_filter_link" AutomationProperties.AutomationId="grid_empty_clear_filter_link"><Run Text="Effacer le filtre"/></Hyperlink>
            </TextBlock>
          </StackPanel>
        </StackPanel>
      </Grid>
    </Border>
    </DockPanel>
    <ContentControl x:Name="users_page" Visibility="Collapsed" Focusable="False"/>
    <ContentControl x:Name="groups_page" Visibility="Collapsed" Focusable="False"/>
    </Grid>
  </DockPanel>

  </Grid>
</Border>
'@

$root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $windowXaml))

# The windows' icon, from compass.ico: Windows takes the size drawn for the taskbar, the title bar or Alt+Tab from it,
# rather than shrinking a large image. The logo, an image in a window, comes from compass.png.
# Read whole as they load (OnLoad): otherwise WPF keeps the files open while Repère runs, and an update can't replace them.
$windowIcon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]"$PSScriptRoot\compass.ico", 'None', 'OnLoad')
$script:logoImage = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]"$PSScriptRoot\compass.png", 'None', 'OnLoad')
$win = [System.Windows.Window]::new()
$win.Title = Tr 'Repère'
$win.Icon = $windowIcon
# The splash goes once the window has drawn, in front of it by then (Splash.ps1).
$win.Add_ContentRendered({ param($window) Close-RepereSplash $window })
# What a pin of Repère's taskbar button starts: Repère with the options it was started with, not PowerShell.
$script:relaunchCommand = try { Get-RepereRelaunchCommand (Get-Process -Id $PID).Path $PSCommandPath $PSBoundParameters }
catch { Write-Verbose "Épinglage non configuré : $_" }
$win.Add_SourceInitialized({
    if (-not $script:relaunchCommand) { return }
    try { Set-RepereRelaunch $script:win $script:relaunchCommand (Get-RepereTaskbarIcon "$PSScriptRoot\compass.ico") }
    catch { Write-Verbose "Épinglage non configuré : $_" }
})
$win.Width = 1180
$win.Height = 760
$win.MinHeight = 520
# Wide enough for the action bar (its buttons square, and the selection text) and the search row. It
# grows with the text size (Theme.ps1, Set-WindowMinSize), and with a wider font, as the action bar measures it
# (Update-ActionLabel).
$win.MinWidth = if ($showDomains) { 1142 } else { 1122 }
# Its size as it was closed, maximized or not, and the page it showed, in %APPDATA%\Repere\fenetre.json
# (Save-WindowSetting). Always centered on the screen Repère was launched on, the one under the mouse pointer, where the
# splash was: not where it was closed.
$windowSettingPath = Get-SettingPath 'fenetre.json'
$windowSetting = Read-JsonSetting $windowSettingPath Width, Height, Maximized, Page
$placement = Get-WindowPlacement $windowSetting (Get-CursorWorkArea (Get-RepereLaunchCursor)) $win.Width $win.Height $win.MinWidth $win.MinHeight
$win.WindowStartupLocation = 'Manual'
$win.Left = $placement.Left
$win.Top = $placement.Top
$win.Width = $placement.Width
$win.Height = $placement.Height
if ($placement.Maximized) { $win.WindowState = 'Maximized' }
$win.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
$win.Content = $root
$root.FindName('logo').Source = $script:logoImage
Set-WindowChrome $win -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')

function Show-Page([string]$Name) {
    # Ordinateurs, Utilisateurs or Groupes (the last two built the first time they're shown). Entrée searches on the
    # page shown: the computers' Rechercher is the window's default button only on theirs.
    $users = $Name -eq 'users'
    $groups = $Name -eq 'groups'
    if ($users -and -not $script:UserPage.Root) { Initialize-UserPage $script:root.FindName('users_page') }
    if ($groups -and -not $script:GroupPage.Root) { Initialize-GroupPage $script:root.FindName('groups_page') }
    $script:UserPage.Shown = $users
    $script:GroupPage.Shown = $groups
    $computers = -not $users -and -not $groups
    $script:root.FindName('computers_page').Visibility = ConvertTo-Visibility $computers
    $script:root.FindName('users_page').Visibility = ConvertTo-Visibility $users
    $script:root.FindName('groups_page').Visibility = ConvertTo-Visibility $groups
    $script:root.FindName('tab_computers').IsChecked = $computers
    $script:root.FindName('tab_users').IsChecked = $users
    $script:root.FindName('tab_groups').IsChecked = $groups
    $script:searchButton.IsDefault = $computers
    $focus = if ($users) { $script:UserPage.Root.FindName('user_query') } elseif ($groups) { $script:GroupPage.Root.FindName('group_query') } else { $script:textBoxPrefix }
    $null = $focus.Focus()
}
$root.FindName('tab_computers').Add_Click({ Show-Page 'computers' })
$root.FindName('tab_users').Add_Click({ Show-Page 'users' })
$root.FindName('tab_groups').Add_Click({ Show-Page 'groups' })
Register-ThemeFollow $win

# An error in an event handler is said in a toast and in the console, instead of closing the window.
$win.Dispatcher.Add_UnhandledException({
    $e = $args[1]
    Write-Host ((Tr 'Erreur : {0}') -f $e.Exception.Message)
    $e.Handled = $true
    try { Show-ActionNotice (Tr 'Erreur') "✖ $($e.Exception.Message)" $e.Exception.Message }
    catch { Write-Host ((Tr 'Erreur : {0}') -f $_) }
})

if ($useFakeAD) {
    $win.Title = Tr 'Repère (AD fictif)'
    $root.FindName('fake_ad_badge').Visibility = 'Visible'
}

# The toast that says an action went well (Show-ActionNotice, below), and Paramètres' button.
$actionNotice  = $root.FindName('action_notice')
$toast         = $root.FindName('toast')
$toastTitle    = $root.FindName('toast_title')
$toastIcon     = $root.FindName('toast_icon')
$toastText     = $root.FindName('toast_text')
$settingsButton = $root.FindName('settings')

function ConvertTo-Visibility([bool]$Visible) {
    if ($Visible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
}

$settingsButton.Add_Click({ Show-SettingsWindow })

function Open-ButtonMenu($Button) {
    # The arrow of a split button opens its menu under it.
    $Button.ContextMenu.PlacementTarget = $Button
    $Button.ContextMenu.Placement = 'Bottom'
    $Button.ContextMenu.IsOpen = $true
}

# The Ordinateurs page: the search and its recent searches, the results grid, its filter, columns and Exporter.
. "$PSScriptRoot\ComputerPage.ps1"

# The window's keys: the pages', then the page shown's. On the computers' (ComputerPage.ps1), Échap stops a search,
# unless something else used it (an open list or menu closes first).
$win.Add_KeyDown({
    $e = $args[1]
    # Ctrl+1, Ctrl+2 and Ctrl+3: the pages. On the users' or the groups' page, its own keys.
    $pages = @{ D1 = 'computers'; NumPad1 = 'computers'; D2 = 'users'; NumPad2 = 'users'; D3 = 'groups'; NumPad3 = 'groups' }
    if ([System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control -and $pages.ContainsKey([string]$e.Key)) {
        Show-Page $pages[[string]$e.Key]
        $e.Handled = $true
        return
    }
    if ($script:UserPage.Shown) {
        Invoke-PageKey $script:UserPage $e
        return
    }
    if ($script:GroupPage.Shown) {
        Invoke-PageKey $script:GroupPage $e
        return
    }
    # Échap closes Avancée's popup first (its keyboard can be back in the window, after the OU tree).
    if ($e.Key -eq 'Escape' -and $script:AdvancedSearchUi.Parts.Popup.IsOpen) {
        $script:AdvancedSearchUi.Parts.Popup.IsOpen = $false
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'Escape' -and $script:search.Current) {
        Stop-Search
        $e.Handled = $true
    }
    # Ctrl+F: the search box. F5: the search again, as the boxes say (not while one runs).
    elseif ($e.Key -eq 'F' -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        $box = Get-SearchBox
        $null = $box.Focus()
        $box.SelectAll()
        $e.Handled = $true
    }
    elseif ($e.Key -eq 'F5' -and -not $script:search.Current) {
        Invoke-Search
        $e.Handled = $true
    }
    # Ctrl+N: Prochain nom…, as its button does. Past the pages' keys above, so it's the Ordinateurs page's alone.
    elseif ($e.Key -eq 'N' -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        & $script:actions.NextName
        $e.Handled = $true
    }
})

# Actions on the selected computers, from the action bar or the right-click menu, with the current user's AD rights.

function Show-Dialog {
    # A small window over the main one, which waits for it: an icon, a heading and its explanation, then what the
    # dialog shows. With -OkText, the OK button closes the dialog, then runs -OnOk with -State (plus State.TextBox with
    # -WithTextBox). Without it, there's only a Fermer button. -AltText: a second way to go on, between OK and
    # Annuler, which closes the dialog and runs -OnAlt with -State (Lire par DCOM, rather than Activer WinRM).
    # -Names: the computers concerned, as chips. -Details: a read-only box (BitLocker keys), so it can be selected and
    # copied, under -DetailsLabel; with -SecretDetails, a Copier button by the label, and the box's own copy, copy it
    # as every other secret (Register-SecretCopy). -Content: any element of the caller's (a report's rows).
    # -TypeToConfirm: OK only once that's typed (a box to type it in, dialog_confirm), for what touches many objects at
    # once. -PickFrom: a list of -Content's whose ticks OK acts on, so OK waits for one (and for the number, with
    # -TypeToConfirm).
    # For UI Automation and the tests, the message keeps reading as one text: heading, names, then message.
    param(
        [string]$Title,
        [string]$Message,
        [string]$Heading,
        [string[]]$Names,
        [string]$Icon = 'info',
        [ValidateSet('accent', 'danger', 'warn', 'success')] [string]$Tone = 'accent',
        [string]$OkText,
        [scriptblock]$OnOk,
        [string]$AltText,
        [scriptblock]$OnAlt,
        [hashtable]$State = @{},
        [switch]$WithTextBox,
        [string]$Text,
        [string]$Details,
        [string]$DetailsLabel,
        [switch]$SecretDetails,
        [System.Windows.UIElement]$Content,
        [string]$MessageName,
        [switch]$CancelIsDefault,
        [string]$TypeToConfirm,
        [System.Windows.Controls.ListBox]$PickFrom,
        # The window it opens over: the main one, or a window of its own (Clés BitLocker).
        [System.Windows.Window]$Owner
    )

    # AD's English errors in what the dialog says, in French (in English, as AD says them).
    $Heading = ConvertTo-FrenchError $Heading
    $Message = ConvertTo-FrenchError $Message
    $MessageName = ConvertTo-FrenchError $MessageName
    $Details = ConvertTo-FrenchError $Details

    if (-not $PSBoundParameters.ContainsKey('Tone') -and $Message) {
        # A message that reports a failure or a success says so with its icon.
        if ($Message.StartsWith('✖')) { $Tone, $Icon = 'danger', 'xcircle' }
        elseif ($Message.StartsWith('✔')) { $Tone, $Icon = 'success', 'checkcircle' }
    }

    $dialog = [System.Windows.Window]::new()
    $dialog.Title = $Title
    $dialog.Icon = $windowIcon
    $dialog.Owner = if ($Owner) { $Owner } else { $win }
    # Wider with details, so a 55-character BitLocker recovery password fits on one line.
    $dialog.Width = if ($Details -or $Content) { 660 } else { 460 }
    $dialog.SizeToContent = 'Height'
    $dialog.ResizeMode = 'NoResize'
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.SetResourceReference([System.Windows.Window]::ForegroundProperty, 'R.Text')

    # The icon's tile takes the tone's colors: the accent's, red for what can't be undone, amber for a warning.
    $colors = @{
        accent  = 'R.Selection', 'R.AccentText'
        danger  = 'R.DangerBg', 'R.DangerText'
        warn    = 'R.WarnBg', 'R.WarnText'
        success = 'R.SuccessBg', 'R.SuccessText'
    }[$Tone]
    $x = { param($value) ConvertTo-XamlValue $value }
    $chips = if ($Names) {
        $shown = @($Names | Select-Object -First 15 | ForEach-Object {
            "<Border Style=`"{StaticResource Pill.Key}`" Margin=`"0,0,6,6`"><TextBlock Text=`"$(& $x $_)`"/></Border>"
        })
        if ($Names.Count -gt 15) { $shown += "<TextBlock Style=`"{StaticResource Txt.Muted}`" FontSize=`"12`" VerticalAlignment=`"Center`" Margin=`"2,0,0,6`" Text=`"$(& $x ((Tr 'et {0} autres') -f ($Names.Count - 15)))`"/>" }
        "<WrapPanel Margin=`"0,10,0,0`">$($shown -join '')</WrapPanel>"
    }
    $layout = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="20,6,20,18">
  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <Border Width="36" Height="36" CornerRadius="8" VerticalAlignment="Top" Margin="0,0,14,0" Background="{DynamicResource $($colors[0])}" TextElement.Foreground="{DynamicResource $($colors[1])}">
    <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:$($Icon):18}}</Grid>
  </Border>
  <StackPanel x:Name="dialog_body" Grid.Column="1">
    <TextBlock x:Name="dialog_heading" FontSize="15" FontWeight="{DynamicResource R.FontWeightStrong}" TextWrapping="Wrap" Margin="0,0,0,4"/>
    <TextBlock x:Name="dialog_message" TextWrapping="Wrap"/>
    $chips
  </StackPanel>
</Grid>
"@))
    $body = $layout.FindName('dialog_body')
    $headingBlock = $layout.FindName('dialog_heading')
    $messageBlock = $layout.FindName('dialog_message')
    # Without a heading, the message is the dialog's main text.
    if ($Heading) {
        $headingBlock.Text = $Heading
        $messageBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
    }
    else { $headingBlock.Visibility = 'Collapsed' }
    $messageBlock.Text = $Message
    if (-not $Message) { $messageBlock.Visibility = 'Collapsed' }
    $fullText = if ($MessageName) { $MessageName } else { @($Heading, $(if ($Names) { Format-ComputerList $Names }), $Message | Where-Object { $_ }) -join "`n`n" }
    [System.Windows.Automation.AutomationProperties]::SetName($messageBlock, $fullText)
    # The message reads as the window's text even when only the heading shows.
    if (-not $Message) {
        $messageBlock.Visibility = 'Visible'
        $messageBlock.Height = 0
    }

    if ($Content) {
        if ($Content -is [System.Windows.FrameworkElement]) { $Content.Margin = '0,14,0,0' }
        $null = $body.Children.Add($Content)
    }
    if ($Details) {
        if ($DetailsLabel -or $SecretDetails) {
            $label = [System.Windows.Controls.TextBlock]::new()
            $label.Text = $DetailsLabel
            $label.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Txt.Label')
            $label.TextWrapping = 'Wrap'
            $label.VerticalAlignment = 'Center'
            $labelRow = [System.Windows.Controls.DockPanel]::new()
            $labelRow.Margin = '0,14,0,6'
            if ($SecretDetails) {
                # By the label, so copying the keys first is the obvious thing to do.
                $copyButton = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="dialog_details_copy" Style="{StaticResource Btn.Ghost}" Padding="8,2" MinHeight="0" FontSize="12" Margin="8,-4,0,-4"
        ToolTip="Tout, hors de l'historique du Presse-papiers et effacé après une minute" AutomationProperties.Name="Copier">
  <StackPanel Orientation="Horizontal">{{icon:copy:14}}<TextBlock Text="Copier" Margin="6,0,0,0"/></StackPanel>
</Button>
'@))
                [System.Windows.Controls.DockPanel]::SetDock($copyButton, 'Right')
                $null = $labelRow.Children.Add($copyButton)
            }
            $null = $labelRow.Children.Add($label)
            $null = $body.Children.Add($labelRow)
        }
        $detailsBox = [System.Windows.Controls.TextBox]::new()
        $detailsBox.Name = 'dialog_details'
        $detailsBox.Text = $Details
        $detailsBox.IsReadOnly = $true
        $detailsBox.AcceptsReturn = $true
        $detailsBox.TextWrapping = 'Wrap'
        $detailsBox.FontFamily = 'Consolas'
        $detailsBox.MaxHeight = 320
        $detailsBox.Padding = '10,8'
        $detailsBox.VerticalContentAlignment = 'Top'
        $detailsBox.VerticalScrollBarVisibility = 'Auto'
        $detailsBox.Margin = if ($DetailsLabel -or $SecretDetails) { '0' } else { '0,14,0,0' }
        $null = $body.Children.Add($detailsBox)
        if ($SecretDetails) { Register-SecretCopy $detailsBox $copyButton }
    }
    if ($WithTextBox) {
        $textBox = [System.Windows.Controls.TextBox]::new()
        $textBox.Name = 'dialog_text'
        $textBox.Text = $Text
        $textBox.Margin = '0,14,0,0'
        $null = $body.Children.Add($textBox)
        $State.TextBox = $textBox
        $dialog.Tag = $textBox
        $dialog.Add_ContentRendered({ param($window) $null = $window.Tag.Focus(); $window.Tag.SelectAll() })
    }

    # The default button (Enter) is the accent one. When a risky action keeps Annuler as the default, its own
    # button is red.
    $cancelFirst = $CancelIsDefault -or -not $OkText
    $buttons = [System.Windows.Controls.StackPanel]::new()
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,20,0,0'
    if ($OkText) {
        $okButton = [System.Windows.Controls.Button]::new()
        $okButton.Name = 'dialog_ok'
        $okButton.Content = $OkText
        $okButton.MinWidth = 90
        $okButton.IsDefault = -not $cancelFirst
        $okButton.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, $(if ($cancelFirst) { 'Btn.Danger' } else { 'Btn.Primary' }))
        $okButton.Add_Click({ param($button) [System.Windows.Window]::GetWindow($button).DialogResult = $true })
        # What OK waits for (Update-DialogOk): both keys always there, strict mode refusing one that isn't.
        $okButton.CommandParameter = @{ Expected = $TypeToConfirm; Pick = $PickFrom }
        $null = $buttons.Children.Add($okButton)
        if ($PickFrom) {
            $PickFrom.Add_SelectionChanged({ param($list) Update-DialogOk $list })
            $okButton.IsEnabled = $PickFrom.SelectedItems.Count -gt 0
        }
        if ($TypeToConfirm) {
            $label = [System.Windows.Controls.TextBlock]::new()
            $label.Text = (Tr 'Pour confirmer, tapez {0} :') -f $TypeToConfirm
            $label.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Txt.Label')
            $label.Margin = '0,14,0,6'
            $null = $body.Children.Add($label)
            $confirmBox = [System.Windows.Controls.TextBox]::new()
            $confirmBox.Name = 'dialog_confirm'
            [System.Windows.Automation.AutomationProperties]::SetName($confirmBox, $label.Text)
            $confirmBox.Add_TextChanged({ param($box) Update-DialogOk $box })
            $null = $body.Children.Add($confirmBox)
            $okButton.IsEnabled = $false
            $dialog.Add_ContentRendered({ $null = $confirmBox.Focus() }.GetNewClosure())
        }
    }
    if ($OkText -and $AltText) {
        # Closes the dialog like Annuler, then says it was chosen.
        $altButton = [System.Windows.Controls.Button]::new()
        $altButton.Name = 'dialog_alt'
        $altButton.Content = $AltText
        $altButton.MinWidth = 90
        $altButton.Margin = '8,0,0,0'
        $altButton.CommandParameter = $State
        $altButton.Add_Click({
            param($button)
            $button.CommandParameter.ChoseAlt = $true
            [System.Windows.Window]::GetWindow($button).DialogResult = $false
        })
        $null = $buttons.Children.Add($altButton)
    }
    $cancelButton = [System.Windows.Controls.Button]::new()
    $cancelButton.Name = 'dialog_cancel'
    $cancelButton.Content = if ($OkText) { Tr 'Annuler' } else { Tr 'Fermer' }
    $cancelButton.MinWidth = 90
    $cancelButton.Margin = '8,0,0,0'
    # Escape and this button close the dialog without OK.
    $cancelButton.IsCancel = $true
    $cancelButton.IsDefault = $cancelFirst
    if ($cancelFirst) { $cancelButton.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Btn.Primary') }
    $null = $buttons.Children.Add($cancelButton)
    $null = $body.Children.Add($buttons)
    $buttons.Name = 'dialog_buttons'
    # The dialog's width is fixed, and a larger text or a wider font scales its content: buttons that no longer fit
    # beside each other (Activer WinRM, Lire par DCOM and Annuler at Grande) widen it, as it opens, by what they lack.
    $dialog.Add_Loaded({ param($window) Update-DialogButtonWidth $window })
    $dialog.Content = $layout
    Set-WindowChrome $dialog

    # While it's open, a search that ends waits before replacing the rows it acts on.
    $script:search.Dialogs++
    try { $confirmed = $dialog.ShowDialog() }
    finally { $script:search.Dialogs-- }
    # ChoseAlt by key: it's only there once the Alt button is clicked, and strict mode refuses it read as a property.
    if ($confirmed -and $OnOk) { & $OnOk $State }
    elseif ($OnAlt -and $State['ChoseAlt']) { & $OnAlt $State }
}

function Update-DialogOk([System.Windows.DependencyObject]$Part) {
    # Show-Dialog's OK, once a part of the dialog ($Part) changes: enabled when the number is typed (-TypeToConfirm)
    # and something is ticked (-PickFrom), as asked. A list emptied by a new search unticks what it had: OK follows.
    $dialog = [System.Windows.Window]::GetWindow($Part)
    if (-not $dialog) { return }
    $ok = [System.Windows.LogicalTreeHelper]::FindLogicalNode($dialog, 'dialog_ok')
    if (-not $ok) { return }
    $confirm = [System.Windows.LogicalTreeHelper]::FindLogicalNode($dialog, 'dialog_confirm')
    $typed = -not $confirm -or "$($confirm.Text)".Trim() -eq $ok.CommandParameter['Expected']
    $pick = $ok.CommandParameter['Pick']
    $ok.IsEnabled = $typed -and (-not $pick -or $pick.SelectedItems.Count -gt 0)
}

function Update-DialogButtonWidth([System.Windows.Window]$Dialog) {
    # Show-Dialog's buttons, once laid out: when they need more room than the dialog's body has, its minimum width grows
    # by what they lack (at the text size shown), and it stays centered where it was placed, within its screen. A row
    # of buttons measures each one at the width it needs, margins included. The font and the scale were only just given
    # to the dialog (Register-UiText, on the same Loaded): laid out again first, so the sizes are in them.
    $row = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Dialog, 'dialog_buttons')
    if (-not $row -or -not $row.Parent) { return }
    $Dialog.UpdateLayout()
    $needed = 0.0
    foreach ($button in $row.Children) { $needed += $button.DesiredSize.Width }
    $missing = $needed - $row.Parent.ActualWidth
    if ($missing -le 0) { return }
    $before = $Dialog.ActualWidth
    Set-WindowContentWidth $Dialog ([Math]::Ceiling($before + $missing * $script:UiScale.ScaleX))
    if (-not [double]::IsNaN($Dialog.Left)) { $Dialog.Left -= [Math]::Max(0, $Dialog.MinWidth - $before) / 2 }
    Set-WindowInWorkArea $Dialog
}

function Format-ComputerList([string[]]$Lines) {
    # Long lists are cut short so the dialog stays on screen.
    $text = ($Lines | Select-Object -First 15) -join "`n"
    if ($Lines.Count -gt 15) { $text += "`n" + ((Tr '… et {0} autres') -f ($Lines.Count - 15)) }
    $text
}

function New-ReportList([string[]]$Lines) {
    # A report's lines as rows: a red, amber or green mark, the computer, and what happened to it. Lines like
    # « ✖ ORD-07 : protégé contre la suppression accidentelle », « ⚠ jdupont : pas de réponse du contrôleur de domaine… »
    # (a change that may have been made: Get-WriteUnsureText) or « ✔ ORD-09 (avec 2 objets enfants) ».
    $x = { param($value) ConvertTo-XamlValue $value }
    $rows = foreach ($line in @($Lines | Select-Object -First 15)) {
        $failed = $line.StartsWith('✖')
        $unsure = $line.StartsWith('⚠')
        $rest = $line.TrimStart('✖', '✔', '⚠').Trim()
        $name, $detail = if ($rest -match '^(?<name>\S+)\s*(?::\s*(?<detail>.*)|(?<detail>\(.*\)))?$') { $Matches.name, $Matches.detail } else { $rest, '' }
        $icon = if ($failed) { 'xcircle' } elseif ($unsure) { 'warning' } elseif ($line.StartsWith('✔')) { 'checkcircle' } else { 'info' }
        $color = if ($failed) { 'R.DangerText' } elseif ($unsure) { 'R.WarnText' } elseif ($line.StartsWith('✔')) { 'R.SuccessText' } else { 'R.Muted' }
        @"
<Border BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="12,9">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border VerticalAlignment="Top" Margin="0,1,10,0" TextElement.Foreground="{DynamicResource $color}">{{icon:$($icon):16}}</Border>
    <TextBlock Grid.Column="1" Text="$(& $x $name)" FontWeight="{DynamicResource R.FontWeightStrong}" Margin="0,0,10,0"/>
    <TextBlock Grid.Column="2" Text="$(& $x $detail)" Style="{StaticResource Txt.Muted}" TextWrapping="Wrap"/>
  </Grid>
</Border>
"@
    }
    if ($Lines.Count -gt 15) { $rows += "<TextBlock Style=`"{StaticResource Txt.Muted}`" FontSize=`"12`" Margin=`"12,8`" Text=`"$(& $x ((Tr '… et {0} autres') -f ($Lines.Count - 15)))`"/>" }
    [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Style="{StaticResource Card}" ClipToBounds="True">
  <ScrollViewer MaxHeight="320" VerticalScrollBarVisibility="Auto"><StackPanel>$($rows -join "`n")</StackPanel></ScrollViewer>
</Border>
"@))
}

function Show-ActionReport([string[]]$Lines, [string]$Title, [System.Windows.Window]$Owner, [string]$Many, [string[]]$Outcome) {
    # When everything went well, a notice in the status bar is enough: nothing to read or close. Otherwise a dialog,
    # failures first, so a long list can't hide them: a row per computer (or user, or key). AD's English errors in
    # French. $Many: the notice for several lines that went well ({0}: how many), « ✔ 3 ordinateurs » by default; the
    # users' and the keys' say theirs. $Outcome: the notice's heading, what was done rather than the action's name
    # (« Activé », for one line; « Activés », for several), the dialog's keeping the action's (« Activer : échec »).
    # A line marked ⚠ is a change that may have been made (its DC didn't answer in time): it's neither, so it's said
    # in the dialog too, after the failures, and without failures the dialog says to check rather than that it failed.
    $Lines = @($Lines | ForEach-Object { ConvertTo-FrenchError $_ })
    $failed = @($Lines | Where-Object { $_.StartsWith('✖') })
    $unsure = @($Lines | Where-Object { $_.StartsWith('⚠') })
    if (-not $failed.Count -and -not $unsure.Count) {
        if (-not $Many) { $Many = Tr '✔ {0} ordinateurs' }
        $heading = if (-not $Outcome) { $Title } elseif ($Lines.Count -eq 1) { $Outcome[0] } else { $Outcome[-1] }
        Show-ActionNotice $heading $(if ($Lines.Count -eq 1) { $Lines[0] } else { $Many -f $Lines.Count }) ($Lines -join "`n")
        return
    }
    $sorted = $failed + $unsure + @($Lines | Where-Object { -not $_.StartsWith('✖') -and -not $_.StartsWith('⚠') })
    if (-not $failed.Count) {
        $heading = if ($unsure.Count -eq $Lines.Count) { (Tr '{0} : à vérifier') -f $Title } else { (Tr '{0} : {1} à vérifier sur {2}') -f $Title, $unsure.Count, $Lines.Count }
        Show-Dialog -Title $Title -Heading $heading -Icon 'warning' -Tone 'warn' -Content (New-ReportList $sorted) -MessageName (Format-ComputerList $sorted) -Owner $Owner
        return
    }
    $heading = if ($Lines.Count -eq 1) { (Tr '{0} : échec') -f $Title }
               elseif ($failed.Count -eq 1) { (Tr '{0} : 1 échec sur {1}') -f $Title, $Lines.Count }
               else { (Tr '{0} : {1} échecs sur {2}') -f $Title, $failed.Count, $Lines.Count }
    Show-Dialog -Title $Title -Heading $heading -Icon 'xcircle' -Tone 'danger' -Content (New-ReportList $sorted) -MessageName (Format-ComputerList $sorted) -Owner $Owner
}

# The toast hides after a while, unless the mouse is on it or it's kept (Persist); its × closes it at once.
$noticeTimer = [System.Windows.Threading.DispatcherTimer]::new()
$noticeTimer.Interval = [timespan]::FromSeconds(6)
$noticeTimer.Add_Tick({
    $script:noticeTimer.Stop()
    $script:toast.Visibility = 'Collapsed'
})
$toast.Add_MouseEnter({ $script:noticeTimer.Stop() })
$noticePersists = $false
$toast.Add_MouseLeave({ if (-not $script:noticePersists) { $script:noticeTimer.Start() } })
$root.FindName('toast_close').Add_Click({
    $script:noticeTimer.Stop()
    $script:toast.Visibility = 'Collapsed'
})

function Get-LastShownSelection($Grid) {
    # The selected item lowest in the grid among those whose row shows whole, or $null: what the notice bar must not
    # hide as it makes the grid shorter.
    if (-not $Grid -or -not $Grid.IsVisible -or $Grid.SelectedItems.Count -eq 0) { return $null }
    $last, $lowest = $null, -1.0
    foreach ($item in $Grid.SelectedItems) {
        $row = $Grid.ItemContainerGenerator.ContainerFromItem($item)
        if (-not $row -or -not $row.IsVisible) { continue }
        $top = $row.TranslatePoint([System.Windows.Point]::new(0, 0), $Grid).Y
        $bottom = $top + $row.ActualHeight
        if ($top -ge 0 -and $bottom -le $Grid.ActualHeight -and $bottom -gt $lowest) { $last, $lowest = $item, $bottom }
    }
    $last
}

function Show-ActionNotice([string]$Title, [string]$Text, [string]$Details, [switch]$Persist) {
    # « Désactivé » and « ORD-10 » in the bar at the bottom of the window for a few seconds, with a green check (a red
    # mark when it says ✖, the accent for a summary such as « 2 en ligne sur 4 »); Details (each computer's line) in its
    # tooltip. AD's English errors in French. Persist: it stays until Hide-ActionNotice or the next notice, for what's still under way
    # (« Connexion à ORD-01… »).
    $Text = ConvertTo-FrenchError $Text
    $Details = ConvertTo-FrenchError $Details
    $icon, $colors = if ($Text.StartsWith('✔')) { 'check', ('R.SuccessBg', 'R.SuccessText') }
                     elseif ($Text.StartsWith('✖')) { 'x', ('R.DangerBg', 'R.DangerText') }
                     else { 'info', ('R.Selection', 'R.AccentText') }
    # The window's own parts (script:): called from a dialog's OK, a name like $root could be the dialog's.
    $tile = $script:toastIcon
    $tile.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $colors[0])
    $tile.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, $colors[1])
    $tile.Child = [System.Windows.Markup.XamlReader]::Parse((Get-IconXaml $icon 13).Replace('<Viewbox ', '<Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" '))
    $script:toastTitle.Text = (Tr '{0} : {1}') -f $Title, ''
    $script:toastText.Text = $Text.TrimStart('✔', '✖').Trim()
    [System.Windows.Automation.AutomationProperties]::SetName($script:actionNotice, ((Tr '{0} : {1}') -f $Title, $Text))
    # Narrator reads it as it shows, as it would a dialog: at once for a failure, after what it's saying for the rest.
    $live = if ($Text.StartsWith('✖')) { 'Assertive' } else { 'Polite' }
    [System.Windows.Automation.AutomationProperties]::SetLiveSetting($script:actionNotice, $live)
    $toast = $script:toast
    # The whole text in the tooltip too when it's long enough for its 2 lines to cut it (about 110 characters a line
    # in the narrowest window, at 130 % text).
    $toast.ToolTip = if ($Details -and $Details -ne $Text) { $Details } elseif ($Title.Length + $Text.Length -gt 200) { $Text }
    # The bar makes the page shorter from the bottom: the last selected row that showed whole is brought back into view
    # once the grid has its new height, so the rows the action was on stay readable.
    $grid = if ($script:UserPage.Shown) { $script:UserPage.Root.FindName('user_grid') }
            elseif ($script:GroupPage.Shown) { $script:GroupPage.Root.FindName('group_grid') }
            else { $script:dataGrid }
    $keep = Get-LastShownSelection $grid
    # It slides up a little as it fades in.
    $toast.Visibility = 'Visible'
    # Once shown: a collapsed text isn't in UI Automation, so its event would reach no one.
    $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($script:actionNotice)
    if ($peer) { $peer.RaiseAutomationEvent([System.Windows.Automation.Peers.AutomationEvents]::LiveRegionChanged) }
    if ($null -ne $keep) {
        $null = $script:win.Dispatcher.BeginInvoke([Action]{ $grid.ScrollIntoView($keep) }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Loaded)
    }
    $duration = [System.Windows.Duration]::new([timespan]::FromMilliseconds(180))
    $toast.BeginAnimation([System.Windows.UIElement]::OpacityProperty, [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, $duration))
    $slide = [System.Windows.Media.TranslateTransform]::new()
    $toast.RenderTransform = $slide
    $slide.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, [System.Windows.Media.Animation.DoubleAnimation]::new(8, 0, $duration))
    $script:noticeTimer.Stop()
    # Time to read it: 6 seconds, a second more per 25 characters past 60, up to 15.
    $script:noticeTimer.Interval = [timespan]::FromSeconds([math]::Min(15, 6 + [math]::Max(0, ($Title.Length + $Text.Length - 60) / 25)))
    $script:noticePersists = [bool]$Persist
    if (-not $Persist) { $script:noticeTimer.Start() }
}

function Hide-ActionNotice {
    # The toast that Persist kept, once what it said is over. A notice shown since then stays its few seconds.
    if (-not $script:noticePersists) { return }
    $script:noticePersists = $false
    $script:toast.Visibility = 'Collapsed'
}

# What can be done to the selected computers: the action bar, the right-click menu and the actions behind them.
. "$PSScriptRoot\ComputerActions.ps1"

# The ActiveDirectory module, once the window is shown and idle: the actions then don't wait for it.
if (-not $useFakeAD) {
    $win.Add_ContentRendered({
        $null = $script:win.Dispatcher.BeginInvoke([Action]{
            try { Import-Module ActiveDirectory -Global -ErrorAction Stop }
            catch { Write-Host ((Tr 'Module ActiveDirectory non chargé : {0}') -f $_) }
        }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    })
}

# Paramètres is built the first time it's opened (most launches never do). When Repère closes, it closes with it.
$win.Add_Closing({
    $script:Settings.Exiting = $true
    if ($script:Settings.Window) { $script:Settings.Window.Close() }
    Save-WindowSetting
    Clear-SecretClipboard -Closing
})

function Save-WindowSetting {
    # The window's size (its normal one when it's maximized or reduced), and the page shown. Not its place: it opens
    # centered on the screen it's launched on.
    $bounds = if ($script:win.WindowState -eq 'Normal') { [System.Windows.Rect]::new($script:win.Left, $script:win.Top, $script:win.ActualWidth, $script:win.ActualHeight) } else { $script:win.RestoreBounds }
    $setting = [ordered]@{}
    if (-not $bounds.IsEmpty) { $setting.Width = [Math]::Round($bounds.Width); $setting.Height = [Math]::Round($bounds.Height) }
    $setting.Maximized = $script:win.WindowState -eq 'Maximized'
    $setting.Page = if ($script:UserPage.Shown) { 'users' } elseif ($script:GroupPage.Shown) { 'groups' } else { 'computers' }
    Save-JsonSetting $script:windowSettingPath $setting
}

# A newer Repère: GitHub's latest release, asked once the window shows, in the background, and at most once a day (its
# answer kept in version.json: GitHub limits how often an address may ask, and a team often shares one). Nothing is
# said when there's none, or when GitHub can't be reached (no Internet, a proxy): it's asked again at the next start.
# Not with the fake AD (a demo, the tests), unless $env:REPERE_UPDATE_RELEASE gives GitHub's answer (the UI tests', not
# kept); never with -NoUpdateCheck.
$updateCheckScript = {
    param([string]$Answer)
    if ($Answer) { return $Answer | ConvertFrom-Json }
    Invoke-RestMethod -Uri 'https://api.github.com/repos/reperedev/Repere/releases/latest' -Headers @{ 'User-Agent' = 'Repere' } -TimeoutSec 10 -ErrorAction Stop
}.ToString()
$releaseCheckPath = Get-SettingPath 'version.json'
if (-not $NoUpdateCheck -and (-not $useFakeAD -or $env:REPERE_UPDATE_RELEASE)) {
    $lastCheck = if (-not $env:REPERE_UPDATE_RELEASE) { Read-ReleaseCheck $releaseCheckPath ([datetime]::UtcNow) }
    if ($lastCheck) { Update-ReleaseNotice (Get-NewerRelease $lastCheck $script:RepereVersion) }
    else {
        $win.Add_ContentRendered({
            Start-BackgroundAction $script:updateCheckScript @{ Answer = "$env:REPERE_UPDATE_RELEASE" } 20 {
                param($output, $failure)
                if ($failure) { Write-Verbose "Nouvelle version non vérifiée : $failure"; return }
                $release = @($output)[0]
                if (-not $env:REPERE_UPDATE_RELEASE) { Save-ReleaseCheck $script:releaseCheckPath $release ([datetime]::UtcNow) }
                Update-ReleaseNotice (Get-NewerRelease $release $script:RepereVersion)
            }
        })
    }
}

# A settings file that's there but couldn't be read (a JSON mistake in a hand-edited parametres.json): this run has its
# defaults, and a toast says so once the window shows, kept until it's closed, rather than only the hidden console
# (#243). Its JSON error is in the tooltip. The file stays as it is; a save of parametres.json moves it aside first
# (Save-JsonSetting).
if ($script:UnreadableSettings.Count) {
    $win.Add_ContentRendered({
        $names = @($script:UnreadableSettings.Keys) -join ', '
        $errors = @(foreach ($name in $script:UnreadableSettings.Keys) { "$name : $($script:UnreadableSettings[$name])" }) -join "`n"
        Show-ActionNotice (Tr 'Paramètres') ('✖ ' + ((Tr '{0} illisible, valeurs par défaut. Le fichier est gardé dans {1} pour être corrigé.') -f $names, $script:SettingsFolder)) $errors -Persist
    })
}

# Nouveautés: the first start of a newer Repère shows what it brought (Changelog.ps1).
Start-Changelog

# The page shown when Repère closed comes back (Ordinateurs otherwise), once the window is there.
if ($windowSetting -and $windowSetting.Page -in 'users', 'groups') {
    $win.Add_Loaded({ Show-Page $script:windowSetting.Page })
}

# For the UI tests' -Strict: the errors strict mode raised, on the error output where they collect them, each its file
# and line, within half a second (a test that fails may leave a dialog open, and Repère is then stopped, not closed).
# One inside an event handler only stops its statement, and the window carries on: $Error still keeps it.
if ($env:REPERE_STRICT) {
    $script:StrictErrorIds = 'PropertyNotFoundStrict', 'VariableIsUndefined', 'System.IndexOutOfRangeException', 'NullArrayIndex', 'InvokeMethodOnNull', 'NullArray',
                             'CommandNotFoundException'
    $script:StrictErrorsWritten = [System.Collections.Generic.HashSet[object]]::new()
    function Write-StrictError {
        foreach ($record in @($Error)) {
            if ($record -isnot [System.Management.Automation.ErrorRecord] -or -not $script:StrictErrorsWritten.Add($record)) { continue }
            if ($script:StrictErrorIds -contains $record.FullyQualifiedErrorId) {
                [Console]::Error.WriteLine("Strict: $($record.InvocationInfo.ScriptName):$($record.InvocationInfo.ScriptLineNumber) $($record.Exception.Message)")
            }
        }
    }
    $script:StrictErrorTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:StrictErrorTimer.Interval = [timespan]::FromMilliseconds(500)
    $script:StrictErrorTimer.Add_Tick({ Write-StrictError })
    $script:StrictErrorTimer.Start()
}

# Started: from here, the trap at the top lets an error be written and the script carry on.
$script:RepereStarting = $false
$null = $win.ShowDialog()

if ($env:REPERE_STRICT) { Write-StrictError }
