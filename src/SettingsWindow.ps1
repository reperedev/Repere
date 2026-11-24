# Paramètres: one window for what Repère lets the user set, in sections chosen on the left: Apparence (the mode, the themes
# and their editor, the text and the language, Theme.ps1), Déplacer vers (the OUs offered by « Déplacer vers… », which it
# picks in a tree, beside the ones chosen), Redémarrage (the defaults of
# « Redémarrer… », RestartDialog.ps1), SCCM (the site Prochain nom… asks, NextName.ps1) and Raccourcis (the keyboard shortcuts, to read). Built the first time it's
# opened, then hidden rather than closed. Dot-sourced by the main script, after Theme.ps1 and
# RestartDialog.ps1; the Déplacer vers section uses the OU lookup of ComputerActions.ps1 (Get-MoveTarget, $ouCache).
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1.

$script:SettingsPath = Get-SettingPath 'parametres.json'
# The window, its section, and the Déplacer vers section's state: the domain shown, its tree's check boxes by DN, the
# lookup of its OUs (Job), and whether -MoveRoots imposes the OUs. CloseAnyway: closing was refused once for what
# SCCM or Redémarrage can't save, and nothing changed since: the next close lets it go.
$script:Settings = @{
    Window = $null; Root = $null; Exiting = $false; Imposed = $false; CloseAnyway = $false
    MoveDomain = $null; MoveBoxes = @{}; UpdatingBoxes = $false; MoveJob = $null; MoveTimer = $null; Restart = $null; PasswordEye = $null
}

# A newer release of Repère than this one, once the main script found one on GitHub: its Version and Url (its page).
$script:NewerRelease = $null

function Get-NewerRelease($Release, [string]$Current) {
    # GitHub's latest release (its tag_name, v1.2.3 or 1.2.3, and html_url) when it's newer than $Current: its Version
    # and Url. $null when it isn't, or doesn't read as one (only a page of github.com is opened).
    if (-not $Release) { return }
    $Release = $Release | Select-Object tag_name, html_url
    if ("$($Release.tag_name)" -notmatch '^v?(\d+\.\d+\.\d+)$') { return }
    $latest = [version]$Matches[1]
    if ($latest -le [version]$Current -or "$($Release.html_url)" -notmatch '^https://github\.com/') { return }
    @{ Version = $latest.ToString(); Url = [string]$Release.html_url }
}

function Read-ReleaseCheck([string]$Path, [datetime]$Now) {
    # GitHub's answer as the last check saved it (version.json), while it's less than a day old: its tag_name and
    # html_url. $null otherwise, or when it can't be read: GitHub is asked again. $Now in UTC.
    $saved = Read-JsonSetting $Path CheckedTicks, tag_name, html_url
    if (-not $saved) { return }
    $ticks = 0L
    if (-not [int64]::TryParse("$($saved.CheckedTicks)", [ref]$ticks) -or $ticks -gt $Now.Ticks -or ($Now.Ticks - $ticks) -ge [timespan]::TicksPerDay) { return }
    $saved
}

function Save-ReleaseCheck([string]$Path, $Release, [datetime]$Now) {
    # GitHub's answer (its tag_name and html_url), and when it was given ($Now, UTC): Repère asks again a day later.
    Save-JsonSetting $Path ([ordered]@{ CheckedTicks = $Now.Ticks; tag_name = [string]$Release.tag_name; html_url = [string]$Release.html_url })
}

function Update-ReleaseNotice($Release = $script:NewerRelease) {
    # A newer Repère ($Release, kept): a dot on Paramètres' button, which names it, and in Paramètres a link to its page,
    # under the version (now, or when Paramètres is first built).
    $script:NewerRelease = $Release
    if (-not $Release) { return }
    $script:root.FindName('settings_update_dot').Visibility = 'Visible'
    $script:root.FindName('settings').ToolTip = (Tr 'Repère {0} est disponible : voir Paramètres.') -f $Release.Version
    $settings = $script:Settings.Root
    if (-not $settings) { return }
    $settings.FindName('settings_update_text').Text = (Tr 'Repère {0} est disponible : le télécharger') -f $Release.Version
    $settings.FindName('settings_update').Visibility = 'Visible'
}

function Read-SavedMoveRoot {
    # The OUs saved for Déplacer vers… (their DNs), or none.
    $saved = Read-JsonSetting $script:SettingsPath MoveRoots
    @(if ($saved) { $saved.MoveRoots | Where-Object { $_ } | ForEach-Object { [string]$_ } })
}

function Save-SettingFile {
    # Language: the choice of Paramètres (Language.ps1), '' for Windows's. OUs imposed by -MoveRoots aren't saved: those
    # saved stay as they were.
    $roots = @($script:moveRootList)
    if ($script:Settings.Imposed) { $roots = @(Read-SavedMoveRoot) }
    Save-JsonSetting $script:SettingsPath ([ordered]@{ MoveRoots = $roots; Language = $script:LanguageChoice }) -Merge
}

# The sections, in order: their key, title and icon.
$script:SettingsSections = [ordered]@{
    appearance = @{ Title = (Tr 'Apparence'); Icon = 'palette' }
    move       = @{ Title = (Tr 'Déplacer vers'); Icon = 'move' }
    restart    = @{ Title = (Tr 'Redémarrage'); Icon = 'power' }
    passwords  = @{ Title = (Tr 'Mots de passe'); Icon = 'password' }
    sccm       = @{ Title = (Tr 'SCCM'); Icon = 'server' }
    shortcuts  = @{ Title = (Tr 'Raccourcis'); Icon = 'keyboard' }
}

# The keyboard shortcuts, as Raccourcis lists them: where, the keys, what they do. Each row behind a comma, so the
# rows stay apart instead of running into one list.
$script:SettingsShortcuts = @(
    ,@((Tr 'Fenêtre principale'), 'Ctrl+1, Ctrl+2, Ctrl+3', (Tr 'Ordinateurs, Utilisateurs, Groupes'))
    ,@((Tr 'Fenêtre principale'), 'Ctrl+F', (Tr 'Aller au champ de recherche'))
    ,@((Tr 'Fenêtre principale'), (Tr 'Entrée'), (Tr 'Rechercher'))
    ,@((Tr 'Fenêtre principale'), 'F5', (Tr 'Relancer la recherche'))
    ,@((Tr 'Fenêtre principale'), 'Ctrl+N', (Tr 'Prochain nom… (page Ordinateurs)'))
    ,@((Tr 'Fenêtre principale'), (Tr 'Échap'), (Tr 'Arrêter la recherche'))
    ,@((Tr 'Fenêtre principale'), (Tr '↓ (champ de recherche)'), (Tr 'Recherches récentes'))
    ,@((Tr 'Résultats'), '↓ ↑', (Tr 'Parcourir les résultats'))
    ,@((Tr 'Résultats'), 'Ctrl+A', (Tr 'Tout sélectionner'))
    ,@((Tr 'Résultats'), 'Ctrl+C', (Tr 'Copier les noms sélectionnés (les identifiants sur Utilisateurs), ou le texte sélectionné'))
    ,@((Tr 'Résultats'), (Tr 'Ctrl+Maj+C'), (Tr 'Copier les lignes sélectionnées'))
    ,@((Tr 'Résultats'), (Tr 'Glisser sur un texte'), (Tr 'Sélectionner ce texte, pour en copier une partie'))
    ,@((Tr 'Résultats'), (Tr 'Clic droit ou Maj+F10'), (Tr 'Toutes les actions'))
    # Only the Ordinateurs grid has F2 and Suppr (ComputerActions.ps1); Utilisateurs and Groupes have neither.
    ,@((Tr 'Ordinateurs'), 'F2', (Tr 'Modifier la description…'))
    ,@((Tr 'Ordinateurs'), (Tr 'Suppr'), (Tr "Supprimer de l'AD… (avec confirmation)"))
    ,@((Tr 'Ordinateurs'), (Tr 'Double-clic'), (Tr 'Caractéristiques…'))
    ,@((Tr 'Ordinateurs'), (Tr 'Alt+Entrée'), (Tr 'Propriétés…'))
    ,@((Tr 'Caractéristiques'), 'F5', (Tr 'Lire de nouveau'))
    ,@((Tr 'Caractéristiques'), 'Ctrl+C', (Tr 'Copier le rapport'))
    ,@((Tr 'Caractéristiques'), (Tr 'Échap'), (Tr 'Arrêter la lecture, puis fermer la fenêtre'))
    ,@((Tr 'Utilisateurs et Groupes'), (Tr 'Double-clic'), (Tr 'Propriétés…'))
    # Show-DetailWindow (UserDetails.ps1), for a user, a group or a computer.
    ,@((Tr 'Propriétés'), 'F5', (Tr 'Lire de nouveau'))
    ,@((Tr 'Propriétés'), (Tr 'Échap'), (Tr 'Annuler la modification en cours, puis fermer la fenêtre'))
)

function Get-SettingsWindowXaml {
    $nav = foreach ($key in $script:SettingsSections.Keys) {
        $section = $script:SettingsSections[$key]
        "<ListBoxItem x:Name=`"nav_$key`" AutomationProperties.Name=`"$($section.Title)`" Padding=`"10,8`"><StackPanel Orientation=`"Horizontal`">{{icon:$($section.Icon):16}}<TextBlock Text=`"$($section.Title)`" Margin=`"10,0,0,0`" FontWeight=`"{DynamicResource R.FontWeightStrong}`"/></StackPanel></ListBoxItem>"
    }
    $groups = $script:SettingsShortcuts | ForEach-Object { $_[0] } | Select-Object -Unique
    $shortcuts = foreach ($group in $groups) {
        "<TextBlock Style=`"{StaticResource Txt.Label}`" Text=`"$group`" Margin=`"0,16,0,6`"/>"
        foreach ($shortcut in $script:SettingsShortcuts | Where-Object { $_[0] -eq $group }) {
            $keys = [System.Security.SecurityElement]::Escape($shortcut[1])
            $action = [System.Security.SecurityElement]::Escape($shortcut[2])
            "<Grid Margin=`"0,0,0,6`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"230`"/><ColumnDefinition Width=`"*`"/></Grid.ColumnDefinitions>" +
            "<Border HorizontalAlignment=`"Left`" Style=`"{StaticResource Pill.Key}`"><TextBlock Text=`"$keys`" FontWeight=`"{DynamicResource R.FontWeightStrong}`"/></Border>" +
            "<TextBlock Grid.Column=`"1`" Text=`"$action`" VerticalAlignment=`"Center`" TextWrapping=`"Wrap`"/></Grid>"
        }
    }
    Expand-Icon @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

  <Border Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,1,0" Padding="10,24,10,18">
    <StackPanel>
      <TextBlock Text="Paramètres" FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" Margin="10,0,0,16"/>
      <ListBox x:Name="settings_nav" Background="Transparent" BorderThickness="0" AutomationProperties.Name="Sections" ItemContainerStyle="{StaticResource Nav.Item}">
        $($nav -join "`n        ")
      </ListBox>
      <TextBlock x:Name="settings_version" Text="Repère $($script:RepereVersion)" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="10,18,0,0"/>
      <!-- What this version brought (Show-ChangelogWindow), when CHANGELOG.md has its entry. -->
      <TextBlock x:Name="settings_changelog" FontSize="12" Margin="10,4,10,0">
        <Hyperlink x:Name="settings_changelog_link" AutomationProperties.AutomationId="settings_changelog_link">Nouveautés</Hyperlink>
      </TextBlock>
      <!-- A newer Repère is out (Update-ReleaseNotice): which, with a link to its page. -->
      <TextBlock x:Name="settings_update" Visibility="Collapsed" FontSize="12" Margin="10,4,10,0" TextWrapping="Wrap">
        <Hyperlink x:Name="settings_update_link" AutomationProperties.AutomationId="settings_update_link"><Run x:Name="settings_update_text"/></Hyperlink>
      </TextBlock>
    </StackPanel>
  </Border>

  <!-- No title bar across the window: the sections' column runs to the top, its « Paramètres » as the title, and the
       window's buttons end a strip above the section shown, which moves the window (Set-WindowChrome). -->
  <DockPanel Grid.Column="1">
  <Grid x:Name="title_bar" DockPanel.Dock="Top" Height="32">
    <StackPanel x:Name="caption_buttons" Orientation="Horizontal" HorizontalAlignment="Right"/>
  </Grid>
  <Grid>
  <ScrollViewer x:Name="settings_scroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <Grid Margin="26,0,26,22">

      <Grid x:Name="section_appearance">{{APPEARANCE}}</Grid>

      <StackPanel x:Name="section_restart" Visibility="Collapsed">
        <TextBlock Text="Redémarrage" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"
                   Text="Le délai et le message que « Redémarrer… » propose."/>
        <TextBlock Style="{StaticResource Txt.Label}" Margin="0,16,0,4" Text="Délai"/>
        <StackPanel Orientation="Horizontal">
          <TextBox x:Name="settings_restart_amount" Width="90" AutomationProperties.Name="Délai"/>
          <ComboBox x:Name="settings_restart_unit" Width="130" Margin="8,0,0,0" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Unité"/>
        </StackPanel>
        <Grid Margin="0,14,0,4">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBlock Style="{StaticResource Txt.Label}" Text="Message affiché"/>
          <TextBlock x:Name="settings_restart_length" Grid.Column="1" Style="{StaticResource Txt.Faint}" FontSize="12"/>
        </Grid>
        <TextBox x:Name="settings_restart_message" TextWrapping="Wrap" AcceptsReturn="False" MinHeight="64" Padding="8,6" VerticalContentAlignment="Top" AutomationProperties.Name="Message"/>
        <!-- Its text, starting with a brace, is set in code (Initialize-SettingsWindow): XAML's own text isn't translated then. -->
        <TextBlock x:Name="settings_restart_fields" Style="{StaticResource Txt.Faint}" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/>
        <TextBlock Style="{StaticResource Txt.Label}" Margin="0,12,0,4" Text="Aperçu"/>
        <Border Background="{DynamicResource R.Surface}" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Padding="10,8">
          <TextBlock x:Name="settings_restart_preview" TextWrapping="Wrap"/>
        </Border>
        <TextBlock x:Name="settings_restart_problem" Margin="0,10,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        <!-- Saved as each box is left, as the unit changes, and as the section or Paramètres is left (Save-RestartChoice). -->
        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
          <Button x:Name="settings_restart_reset" Content="Valeurs par défaut" ToolTip="5 minutes et le message de Repère"/>
          <TextBlock x:Name="settings_restart_status" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="12,0,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </StackPanel>

      <!-- What « Nouveau mot de passe… » proposes for a user (UserPage.ps1, motdepasse.json). Each change is saved. -->
      <StackPanel x:Name="section_passwords" Visibility="Collapsed">
        <TextBlock Text="Mots de passe" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"
                   Text="Ce que « Nouveau mot de passe… » propose. La personne devra le changer à sa prochaine connexion."/>
        <RadioButton x:Name="settings_password_generated" GroupName="password" Margin="0,16,0,0" Content="Générer un mot de passe facile à dicter"/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="28,2,0,0"
                   Text="Ex. Pomme-Nuage-Lapin-47, conforme à la complexité de Windows."/>
        <RadioButton x:Name="settings_password_default" GroupName="password" Margin="0,12,0,0" Content="Toujours le même mot de passe temporaire"/>
        <StackPanel Orientation="Horizontal" Margin="28,6,0,0">
          <Grid Width="260">
            <PasswordBox x:Name="settings_password_value" AutomationProperties.Name="Mot de passe par défaut"/>
            <TextBox x:Name="settings_password_text" Visibility="Collapsed" FontFamily="Consolas" VerticalContentAlignment="Center" AutomationProperties.Name="Mot de passe par défaut"/>
          </Grid>
          <Button x:Name="settings_password_show" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" ToolTip="Afficher le mot de passe" AutomationProperties.Name="Afficher le mot de passe">{{icon:eye:14}}</Button>
          <Button x:Name="settings_password_hide" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Masquer le mot de passe" AutomationProperties.Name="Masquer le mot de passe">{{icon:eyeoff:14}}</Button>
        </StackPanel>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="28,4,0,0"
                   Text="Gardé chiffré, pour votre compte sur cet ordinateur."/>
        <!-- The two above are always temporary (UserPage.ps1, Register-ResetMustChange): this is for one typed in « Autre ». -->
        <CheckBox x:Name="settings_password_must_change" Margin="0,16,0,0" Content="Un mot de passe tapé (« Autre ») doit aussi être changé"/>
        <TextBlock x:Name="settings_password_status" Style="{StaticResource Txt.Muted}" Margin="0,12,0,0" TextWrapping="Wrap"/>
      </StackPanel>

      <!-- Where « Prochain nom… » also looks (parametres.json). Its check reads, it writes nothing to SCCM. Saved as the
           two boxes are left, and as the section or Paramètres is left (Save-SccmChoice); each box's problem under it. -->
      <StackPanel x:Name="section_sccm" Visibility="Collapsed">
        <TextBlock Text="SCCM" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"
                   Text="Pour que « Prochain nom… » vérifie aussi dans SCCM."/>
        <TextBlock Style="{StaticResource Txt.Label}" Margin="0,16,0,4" Text="Code du site"/>
        <TextBox x:Name="settings_sccm_site" Width="120" HorizontalAlignment="Left" MaxLength="3" CharacterCasing="Upper" AutomationProperties.Name="Code du site"/>
        <TextBlock x:Name="settings_sccm_site_problem" Foreground="{DynamicResource R.DangerText}" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        <TextBlock Style="{StaticResource Txt.Label}" Margin="0,14,0,4" Text="Serveur"/>
        <TextBox x:Name="settings_sccm_server" Width="340" HorizontalAlignment="Left" AutomationProperties.Name="Serveur"/>
        <TextBlock x:Name="settings_sccm_server_problem" Foreground="{DynamicResource R.DangerText}" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        <TextBlock Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0"
                   Text="Le fournisseur SMS, souvent le serveur du site principal. Il faut la console Configuration Manager."/>
        <TextBlock x:Name="settings_sccm_status" Style="{StaticResource Txt.Muted}" Margin="0,12,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        <Grid Margin="0,16,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Button x:Name="settings_sccm_test" VerticalAlignment="Top" Content="Tester" ToolTip="Demande à ce site un nom qui n'existe pas"/>
          <TextBlock x:Name="settings_sccm_test_status" Grid.Column="1" Style="{StaticResource Txt.Muted}" VerticalAlignment="Center" Margin="12,0,0,0" TextWrapping="Wrap"/>
        </Grid>
      </StackPanel>

      <StackPanel x:Name="section_shortcuts" Visibility="Collapsed">
        <TextBlock Text="Raccourcis" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
        $($shortcuts -join "`n        ")
      </StackPanel>

    </Grid>
  </ScrollViewer>

  <!-- Outside the scrolling of the other sections: the title and the lists stay, and each card scrolls its own OUs. A
       card is as tall as its OUs, up to what the window leaves; the tree's column stops growing with a maximized window. -->
  <DockPanel x:Name="section_move" Visibility="Collapsed" Margin="26,0,26,22">
    <TextBlock DockPanel.Dock="Top" Text="Déplacer vers" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}"/>
    <TextBlock DockPanel.Dock="Top" Style="{StaticResource Txt.Faint}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"
               Text="Les OU où « Déplacer vers… » peut déplacer des ordinateurs."/>
    <Border DockPanel.Dock="Top" x:Name="move_roots_imposed" Visibility="Collapsed" Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,12,0,0">
      <ScrollViewer x:Name="move_roots_imposed_scroll" MaxHeight="84" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <TextBlock x:Name="move_roots_imposed_text" TextWrapping="Wrap"/>
      </ScrollViewer>
    </Border>
    <Grid Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*" MaxWidth="640"/><ColumnDefinition Width="14"/><ColumnDefinition Width="300"/></Grid.ColumnDefinitions>
      <Border Style="{StaticResource Card}" VerticalAlignment="Top">
        <DockPanel>
          <Grid DockPanel.Dock="Top" Margin="10">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <ComboBox x:Name="move_roots_domain" Width="190" Height="34" Margin="0,0,8,0" ItemContainerStyle="{StaticResource Combo.Item}" AutomationProperties.Name="Domaine"/>
            <Border Grid.Column="1" Style="{StaticResource Field}" Height="34">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
                <TextBox x:Name="move_roots_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer les OU" AutomationProperties.Name="Filtrer les OU"/>
              </Grid>
            </Border>
          </Grid>
          <Border DockPanel.Dock="Top" Height="1" Background="{DynamicResource R.Border}"/>
          <Grid Margin="4">
            <TreeView x:Name="move_roots_tree" Background="Transparent" BorderThickness="0" VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.ScrollUnit="Pixel"/>
            <TextBlock x:Name="move_roots_status" Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" VerticalAlignment="Center"
                       TextWrapping="Wrap" TextAlignment="Center" Margin="16" Text="Chargement des OU…"/>
          </Grid>
        </DockPanel>
      </Border>
      <Border Grid.Column="2" Style="{StaticResource Card}" VerticalAlignment="Top">
        <DockPanel>
          <StackPanel DockPanel.Dock="Top" Margin="14,12,14,10">
            <TextBlock Text="OU proposées" FontWeight="{DynamicResource R.FontWeightStrong}"/>
            <TextBlock x:Name="move_roots_summary" Style="{StaticResource Txt.Muted}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"/>
          </StackPanel>
          <Button DockPanel.Dock="Bottom" x:Name="move_roots_clear" Visibility="Collapsed" HorizontalAlignment="Left" Margin="14,6,14,12" Content="Tout décocher"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel x:Name="move_roots_chosen"/>
          </ScrollViewer>
        </DockPanel>
      </Border>
    </Grid>
  </DockPanel>
  </Grid>
  </DockPanel>
</Grid>
"@
}

function Initialize-SettingsWindow {
    # Builds the window and wires its sections, for Show-SettingsWindow.
    $root = [System.Windows.Markup.XamlReader]::Parse((Get-SettingsWindowXaml).Replace('{{APPEARANCE}}', (Get-AppearanceXaml)))
    $window = [System.Windows.Window]::new()
    $window.Title = Tr 'Paramètres'
    $window.Icon = $script:windowIcon
    $window.Width = 980
    $window.Height = [Math]::Min(760, [System.Windows.SystemParameters]::WorkArea.Height - 40)
    $window.MinWidth = 900
    $window.MinHeight = 520
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'CenterOwner'
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $window.Content = $root
    Set-WindowChrome $window -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    # Before the Closing that hides it instead: hidden, it hands the focus on as a closed window does.
    Register-OwnerFocus $window
    $script:Settings.Window = $window
    $script:Settings.Root = $root
    Connect-AppearancePanel $root

    # Closing only hides it, until Repère itself closes. Échap closes it too. What SCCM and Redémarrage have typed is
    # saved first; what can't be (Save-PendingSetting) keeps the window open on it once, and goes the second time.
    $window.Add_Closing({
        param($settingsWindow, $e)
        $unsaved = Save-PendingSetting
        if ($script:Settings.Exiting) { return }
        $e.Cancel = $true
        if ($unsaved -and -not $script:Settings.CloseAnyway) {
            # Showing the section first: showing Redémarrage counts as a change, which would let the next close go.
            $script:Settings.Root.FindName("nav_$unsaved").IsSelected = $true
            Show-UnsavedSetting $unsaved
            $script:Settings.CloseAnyway = $true
            return
        }
        $script:Settings.CloseAnyway = $false
        if ($script:Settings.PasswordEye) { Set-PasswordShown $script:Settings.PasswordEye $false }
        $settingsWindow.Hide()
    })
    $window.Add_KeyDown({
        $e = $args[1]
        if ($e.Key -eq 'Escape') { $script:Settings.Window.Close(); $e.Handled = $true }
    })

    Connect-PasswordSetting $root
    Connect-SccmSetting $root
    $root.FindName('settings_update_link').Add_Click({ if ($script:NewerRelease) { Start-Process $script:NewerRelease.Url } })
    Update-ReleaseNotice
    $root.FindName('settings_changelog').Visibility = ConvertTo-Visibility ([bool](Get-ChangelogEntry $script:ChangelogPath $script:RepereVersion))
    $root.FindName('settings_changelog_link').Add_Click({ Show-ChangelogWindow (Get-ChangelogEntry $script:ChangelogPath $script:RepereVersion) })

    $nav = $root.FindName('settings_nav')
    # Leaving SCCM or Redémarrage saves what was typed there (what can't be stays typed, its problem shown).
    $nav.Add_SelectionChanged({
        $item = $script:Settings.Root.FindName('settings_nav').SelectedItem
        if ($item) {
            $null = Save-PendingSetting
            Show-SettingsSection $item.Name.Substring('nav_'.Length)
        }
    })

    # Déplacer vers: the domains, then each one's OUs, looked up in the background when it's shown.
    $domainBox = $root.FindName('move_roots_domain')
    foreach ($domain in $script:domainList) { $domainBox.Items.Add($domain) | Out-Null }
    $domainBox.Visibility = ConvertTo-Visibility ($script:domainList.Count -gt 1)
    $domainBox.Add_SelectionChanged({ Show-MoveRootDomain ([string]$script:Settings.Root.FindName('move_roots_domain').SelectedItem) })
    $root.FindName('move_roots_filter').Add_TextChanged({ Update-MoveRootFilter })
    $root.FindName('move_roots_clear').Add_Click({
        $script:moveRootList = @()
        Save-SettingFile
        Update-MoveRootCheck
        Set-MoveRootFocus 0
    })
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(50)
    $timer.Add_Tick({ Update-MoveRootLoad })
    $script:Settings.MoveTimer = $timer
    if ($script:Settings.Imposed) {
        $root.FindName('move_roots_imposed').Visibility = 'Visible'
        $root.FindName('move_roots_imposed_text').Text = (Tr 'Imposées par -MoveRoots sur la ligne de commande : {0}. Elles ne peuvent pas être changées ici.') -f ($script:moveRootList -join (Tr ' ; '))
    }

    # Redémarrage: the same checks and preview as the restart dialog (Get-RestartChoice), on this section's controls.
    $controls = @{
        restart_amount = $root.FindName('settings_restart_amount'); restart_unit = $root.FindName('settings_restart_unit')
        restart_message = $root.FindName('settings_restart_message'); restart_preview = $root.FindName('settings_restart_preview')
        restart_length = $root.FindName('settings_restart_length'); restart_problem = $root.FindName('settings_restart_problem')
        restart_status = $root.FindName('settings_restart_status')
    }
    # Filling: the boxes are being set as a whole (Reset-RestartSetting, Valeurs par défaut), not saved one by one.
    $script:Settings.Restart = @{ Controls = $controls; Filling = $false }
    $root.FindName('settings_restart_fields').Text = Tr '{délai} et {heure} sont remplacés.'
    foreach ($unit in $script:RestartUnits.Keys) { $controls.restart_unit.Items.Add($script:RestartUnitTexts[$unit]) | Out-Null }
    $controls.restart_amount.Add_PreviewTextInput({ $e = $args[1]; if ($e.Text -notmatch '^\d+$') { $e.Handled = $true } })
    $controls.restart_amount.Add_TextChanged({ Update-RestartSetting })
    $controls.restart_message.Add_TextChanged({ Update-RestartSetting })
    $controls.restart_unit.Add_SelectionChanged({
        Update-RestartSetting
        if (-not $script:Settings.Restart.Filling) { $null = Save-RestartChoice }
    })
    foreach ($box in $controls.restart_amount, $controls.restart_message) {
        $box.Add_LostKeyboardFocus({ $null = Save-RestartChoice })
        $box.Add_KeyDown({ if ($args[1].Key -eq 'Return') { $null = Save-RestartChoice } })
    }
    $root.FindName('settings_restart_reset').Add_Click({
        $state = $script:Settings.Restart
        $c = $state.Controls
        $state.Filling = $true
        try {
            $c.restart_amount.Text = '5'
            $c.restart_unit.SelectedItem = $script:RestartUnitTexts['minutes']
            $c.restart_message.Text = $script:RestartDefaultMessage
        }
        finally { $state.Filling = $false }
        $null = Save-RestartChoice
    })
    $nav.SelectedIndex = 0
}

function Show-SettingsWindow([string]$Section) {
    # Shows the window (on a section, when given), or brings it to the front. Built the first time.
    if (-not $script:Settings.Window) { Initialize-SettingsWindow }
    $window = $script:Settings.Window
    if (-not $window.Owner) { $window.Owner = $script:win; $window.Icon = $script:windowIcon }
    # What couldn't be saved was left on closing: the sections show what's saved, before another is chosen (which
    # saves what the one left holds).
    if (-not $window.IsVisible) {
        Reset-RestartSetting
        Reset-SccmSetting
    }
    if ($Section) { $script:Settings.Root.FindName("nav_$Section").IsSelected = $true }
    if (-not $window.IsVisible) {
        Show-ThemeGallery
        $script:Settings.Root.FindName('move_roots_filter').Clear()
        $window.Show()
    }
    if ($window.WindowState -eq 'Minimized') { $window.WindowState = 'Normal' }
    $null = $window.Activate()
}

function Show-SettingsSection([string]$Key) {
    foreach ($name in $script:SettingsSections.Keys) {
        $script:Settings.Root.FindName("section_$name").Visibility = ConvertTo-Visibility ($name -eq $Key)
    }
    # Déplacer vers is beside the scrolling of the other sections.
    $scroll = $script:Settings.Root.FindName('settings_scroll')
    $scroll.Visibility = ConvertTo-Visibility ($Key -ne 'move')
    $scroll.ScrollToTop()
    # The window may have been open a while: {heure} counts from now, not from when it opened.
    if ($Key -eq 'restart') { Update-RestartSetting }
    if ($Key -eq 'move') {
        $domainBox = $script:Settings.Root.FindName('move_roots_domain')
        # The tree stays as it was left, its branches opened included: read again only if it has no OUs yet.
        if (-not $domainBox.SelectedItem) { $domainBox.SelectedItem = $script:defaultDomain }
        elseif (-not $script:Settings.MoveBoxes.Count) { Show-MoveRootDomain ([string]$domainBox.SelectedItem) }
    }
}

function Connect-SccmSetting($Root) {
    # SCCM: the site saved shown, then what's typed saved as the two boxes are left (nothing typed: no site, and
    # Prochain nom… checks AD alone, which is said). Tester saves first, then asks that site.
    Reset-SccmSetting
    foreach ($name in 'settings_sccm_site', 'settings_sccm_server') {
        $box = $Root.FindName($name)
        # A box's problem goes as it's retyped, and so do « SCCM désactivé » and a test's answer, about what it held then.
        $box.Add_TextChanged({
            param($changed)
            Show-SccmProblem $changed.Name.Substring('settings_sccm_'.Length) ''
            Show-SccmStatus ''
            $script:Settings.Root.FindName('settings_sccm_test_status').Text = ''
            $script:Settings.CloseAnyway = $false
        })
        # From one box to the other, the pair isn't left yet: a site typed before its server isn't refused meanwhile.
        $box.Add_LostKeyboardFocus({
            $next = $args[1].NewFocus
            if ($next -is [System.Windows.FrameworkElement] -and $next.Name -in 'settings_sccm_site', 'settings_sccm_server') { return }
            $null = Save-SccmChoice
        })
        $box.Add_KeyDown({ if ($args[1].Key -eq 'Return') { $null = Save-SccmChoice } })
    }
    $Root.FindName('settings_sccm_test').Add_Click({
        param($button)
        $parts = $script:Settings.Root
        $status = $parts.FindName('settings_sccm_test_status')
        # What's tested is what's saved, so the answer is about the site Prochain nom… will ask.
        if ((Save-SccmChoice) -eq 'Problem') { $status.Text = ''; return }
        $site, $server = (Get-SccmSettingField)
        if (-not $site -and -not $server) { $status.Text = Tr 'Entrez un site et son serveur pour les tester.'; return }
        $status.Text = Tr 'Test en cours…'
        # One test at a time: a site that doesn't answer holds a search runspace up to SccmTimeoutSeconds, and a few
        # clicks would hold them all, the main window's searches then waiting. Tester comes back with the answer,
        # whatever it is.
        $button.IsEnabled = $false
        try {
            Start-BackgroundRead -Command 'Get-SccmCheck' -Arguments @(@{ Site = $site.ToUpperInvariant(); Server = $server }, 'REPERE-TEST-') `
                -Variables (Get-SccmReadVariable) -Timeout ($script:ReadTimeout + $script:SccmTimeoutSeconds) -Context @{ Site = $site.ToUpperInvariant(); Button = $button } -OnDone {
                param($context, $check, $problem)
                # Even with Paramètres closed meanwhile: it's only hidden, and the next opening can test again.
                $context.Button.IsEnabled = $true
                Start-SccmStopSweep
                # Repère may be closing by the time the answer comes.
                if (-not $script:Settings.Root) { return }
                $reason = if ($problem) { ConvertTo-FrenchError $problem } elseif (-not $check.Checked) { $check.Reason }
                $script:Settings.Root.FindName('settings_sccm_test_status').Text = if ($reason) { (Tr 'Vérification SCCM impossible : {0}.') -f $reason } else { (Tr 'Le site {0} répond.') -f $context.Site }
            }
        }
        catch {
            # Not started: the next click can try again.
            $button.IsEnabled = $true
            throw
        }
    })
}

function Get-SccmSettingField {
    # The site code and the server as typed in Paramètres › SCCM.
    $Root = $script:Settings.Root
    $Root.FindName('settings_sccm_site').Text.Trim()
    $Root.FindName('settings_sccm_server').Text.Trim()
}

function Get-SavedSccmField {
    # The site code and the server parametres.json holds, as typed there: '' for each it doesn't.
    $saved = Read-JsonSetting $script:SettingsPath SccmSite, SccmServer
    if ($saved) { ([string]$saved.SccmSite).Trim().ToUpperInvariant(); ([string]$saved.SccmServer).Trim() } else { ''; '' }
}

function Reset-SccmSetting {
    # The section shows the site saved, without problems or messages from before.
    $root = $script:Settings.Root
    $site, $server = (Get-SavedSccmField)
    $root.FindName('settings_sccm_site').Text = $site
    $root.FindName('settings_sccm_server').Text = $server
    foreach ($field in 'site', 'server') { Show-SccmProblem $field '' }
    foreach ($name in 'settings_sccm_status', 'settings_sccm_test_status') { $root.FindName($name).Text = '' }
    $root.FindName('settings_sccm_status').Visibility = 'Collapsed'
}

function Show-SccmProblem([string]$Field, [string]$Text) {
    # What's wrong with one box ('site' or 'server'), under it, the box outlined in red; '' takes both away.
    $root = $script:Settings.Root
    $box = $root.FindName("settings_sccm_$Field")
    $line = $root.FindName("settings_sccm_$($Field)_problem")
    $line.Text = $Text
    $line.Visibility = ConvertTo-Visibility ([bool]$Text)
    if ($Text) { $box.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'R.DangerText') }
    else { $box.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty) }
}

function Show-SccmStatus([string]$Text, [string]$Brush = 'R.Muted') {
    $status = $script:Settings.Root.FindName('settings_sccm_status')
    $status.Text = $Text
    $status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    $status.Visibility = ConvertTo-Visibility ([bool]$Text)
}

function Save-SccmChoice {
    # Saves the site and server typed, when they differ from those saved. 'Saved', 'Same', or 'Problem' when they
    # can't be: each box's problem under it. Both empty is no site: Prochain nom… then checks AD alone, said here.
    $site, $server = (Get-SccmSettingField)
    $site = $site.ToUpperInvariant()
    $savedSite, $savedServer = (Get-SavedSccmField)
    $problem = if ($site -or $server) { Get-SccmFieldProblem $site $server } else { @{ Site = $null; Server = $null } }
    Show-SccmProblem 'site' $problem.Site
    Show-SccmProblem 'server' $problem.Server
    if ($problem.Site -or $problem.Server) { return 'Problem' }
    # Saved in capitals, and shown so: a code typed in another way than the keyboard's (pasted, UI Automation).
    $siteBox = $script:Settings.Root.FindName('settings_sccm_site')
    if ($siteBox.Text -cne $site) { $siteBox.Text = $site }
    if ($site -ceq $savedSite -and $server -eq $savedServer) { return 'Same' }
    Save-JsonSetting $script:SettingsPath ([ordered]@{ SccmSite = $site; SccmServer = $server }) -Merge
    # Saved goes without saying, as in the rest of Paramètres; only a site taken away is said.
    if ($site) { Show-SccmStatus '' }
    else { Show-SccmStatus (Tr 'SCCM désactivé : « Prochain nom… » ne vérifiera que dans l''AD.') 'R.WarnText' }
    'Saved'
}

function Save-PendingSetting {
    # Saves what SCCM and Redémarrage have typed, as the section or Paramètres is left. The section ('sccm' or
    # 'restart') that holds what can't be saved, the one shown first; nothing when all of it is saved.
    $problems = @(
        if ((Save-SccmChoice) -eq 'Problem') { 'sccm' }
        if ((Save-RestartChoice) -eq 'Problem') { 'restart' }
    )
    $shown = foreach ($key in $problems) { if ($script:Settings.Root.FindName("section_$key").Visibility -eq 'Visible') { $key } }
    if ($shown) { return $shown } elseif ($problems) { return $problems[0] }
}

function Show-UnsavedSetting([string]$Key) {
    # Closing with what can't be saved: said in its section, and the window stays. Closing again lets it go.
    $text = Tr 'Pas enregistré : corrigez ce qui est en rouge, ou fermez de nouveau pour abandonner ces changements.'
    if ($Key -eq 'sccm') { Show-SccmStatus $text 'R.WarnText' }
    else {
        $status = $script:Settings.Restart.Controls.restart_status
        $status.Text = $text
        $status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.WarnText')
    }
}

function Connect-PasswordSetting($Root) {
    # Mots de passe: the saved choice shown, then each change saved at once (UpdatingPassword: while it's shown).
    $setting = Read-PasswordSetting
    $script:Settings.UpdatingPassword = $true
    $Root.FindName("settings_password_$(if ($setting.Mode -eq 'Default') { 'default' } else { 'generated' })").IsChecked = $true
    if ($setting.Default) { $Root.FindName('settings_password_value').Password = $setting.Default }
    $Root.FindName('settings_password_must_change').IsChecked = $setting.MustChange
    $script:Settings.UpdatingPassword = $false
    foreach ($name in 'settings_password_generated', 'settings_password_default', 'settings_password_must_change') {
        $Root.FindName($name).Add_Checked({ Save-PasswordChoice })
    }
    $Root.FindName('settings_password_must_change').Add_Unchecked({ Save-PasswordChoice })
    $Root.FindName('settings_password_value').Add_PasswordChanged({ Save-PasswordChoice })
    # The eye: what's typed in plain text goes to the PasswordBox, which saves it.
    $script:Settings.PasswordEye = Register-PasswordEye $Root.FindName('settings_password_value') $Root.FindName('settings_password_text') `
        $Root.FindName('settings_password_show') $Root.FindName('settings_password_hide')
    Update-PasswordStatus
}

function Save-PasswordChoice {
    if ($script:Settings.UpdatingPassword) { return }
    $root = $script:Settings.Root
    Save-PasswordSetting @{
        Mode       = if ($root.FindName('settings_password_default').IsChecked) { 'Default' } else { 'Generated' }
        Default    = $root.FindName('settings_password_value').Password
        MustChange = [bool]$root.FindName('settings_password_must_change').IsChecked
    }
    Update-PasswordStatus
}

function Update-PasswordStatus {
    # « Toujours le même » without a password: Nouveau mot de passe… generates one meanwhile.
    $root = $script:Settings.Root
    $status = $root.FindName('settings_password_status')
    if ($root.FindName('settings_password_default').IsChecked -and -not $root.FindName('settings_password_value').Password) {
        $status.Text = Tr 'Entrez le mot de passe par défaut : sans lui, un mot de passe est généré.'
        $status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.WarnText')
    }
    else {
        $status.Text = ''
    }
}

function Reset-RestartSetting {
    # The section shows the defaults saved (or Repère's).
    $saved = Read-RestartSetting
    $state = $script:Settings.Restart
    $c = $state.Controls
    $state.Filling = $true
    try {
        $c.restart_amount.Text = [string]$saved.Amount
        $c.restart_unit.SelectedItem = $script:RestartUnitTexts[$saved.Unit]
        $c.restart_message.Text = $saved.Message
    }
    finally { $state.Filling = $false }
    $c.restart_status.Text = ''
    Update-RestartSetting
}

function Save-RestartChoice {
    # Saves the delay and message typed, when they differ from those saved. 'Saved', 'Same', or 'Problem' when they
    # can't be (Get-RestartChoice's error, already shown under the message by Update-RestartSetting).
    $state = $script:Settings.Restart
    $c = $state.Controls
    if ($state.Filling -or $null -eq $c.restart_unit.SelectedItem) { return 'Same' }
    $choice = Get-RestartChoice $state
    if ($choice.Error) { return 'Problem' }
    $saved = Read-RestartSetting
    if ($choice.Amount -eq $saved.Amount -and $choice.Unit -eq $saved.Unit -and $choice.Message -ceq $saved.Message) { return 'Same' }
    Save-RestartSetting $choice.Amount $choice.Unit $choice.Message
    $c.restart_status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'R.Muted')
    $c.restart_status.Text = [string]::Format((Get-TextCulture), (Tr 'Enregistré ({0:HH:mm:ss}).'), (Get-Date))
    'Saved'
}

function Update-RestartSetting {
    # After each change: the preview, the length, the problem if any, and whether it can be saved.
    $state = $script:Settings.Restart
    $c = $state.Controls
    if ($null -eq $c.restart_unit.SelectedItem) { return }
    $choice = Get-RestartChoice $state
    if ($null -ne $choice.Seconds) {
        $preview = Expand-RestartMessage $choice.Message $choice.Amount $choice.Unit (Get-Date)
        $c.restart_preview.Text = if ($preview) { $preview } else { Tr '(aucun message)' }
        $c.restart_length.Text = "$($preview.Length) / $($script:RestartMaxMessage)"
    }
    else {
        $c.restart_preview.Text = ''
        $c.restart_length.Text = ''
    }
    $problem = if ($choice.Error) { $choice.Error } else { $choice.Warning }
    $c.restart_problem.Text = $problem
    $c.restart_problem.Visibility = ConvertTo-Visibility ([bool]$problem)
    $c.restart_problem.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($choice.Error) { 'R.DangerText' } else { 'R.WarnText' }))
    $c.restart_status.Text = ''
    $script:Settings.CloseAnyway = $false
}

function Show-MoveRootDomain([string]$Domain) {
    # A domain's OUs: from the session's cache, or looked up in the background (the tree says so meanwhile).
    if (-not $Domain) { return }
    $script:Settings.MoveDomain = $Domain
    # A lookup of another domain is no longer wanted; one of this domain goes on.
    $job = $script:Settings.MoveJob
    if ($job -and $job.Domain -ne $Domain) {
        $script:Settings.MoveTimer.Stop()
        Stop-OuLoad @{ Job = $job }
        $script:Settings.MoveJob = $null
    }
    $root = $script:Settings.Root
    $root.FindName('move_roots_tree').Items.Clear()
    $script:Settings.MoveBoxes = @{}
    Update-MoveRootChosen
    if ($script:ouCache.ContainsKey($Domain)) {
        Update-MoveRootTree
        return
    }
    $status = $root.FindName('move_roots_status')
    $status.Text = Tr 'Chargement des OU…'
    $status.Visibility = 'Visible'
    $script:Settings.MoveTimer.Start()
}

function Update-MoveRootLoad {
    # On each tick: starts the lookup once the runspaces are ready, then fills the tree, or shows the error.
    $settings = $script:Settings
    if (-not $settings.MoveJob) {
        if ($script:searchPool.RunspacePoolStateInfo.State -ne 'Opened') { return }
        $shell = [powershell]::Create()
        $shell.RunspacePool = $script:searchPool
        $null = $shell.AddScript($script:ouLoadScript).AddParameter('Domain', $settings.MoveDomain)
        $settings.MoveJob = @{ Shell = $shell; Handle = $shell.BeginInvoke(); Domain = $settings.MoveDomain }
        return
    }
    if (-not $settings.MoveJob.Handle.IsCompleted) { return }
    $settings.MoveTimer.Stop()
    $job = $settings.MoveJob
    $settings.MoveJob = $null
    try { $answer = @($job.Shell.EndInvoke($job.Handle))[0] }
    catch { $answer = [pscustomobject]@{ Error = $_.Exception.Message } }
    finally { $job.Shell.Dispose() }
    if ($answer.Error) {
        $settings.Root.FindName('move_roots_status').Text = (Tr 'OU non lues : {0}') -f $answer.Error
        return
    }
    $script:ouCache[$job.Domain] = $answer
    Update-MoveRootTree
}

function Update-MoveRootTree {
    # Every OU of the domain that Déplacer vers… could offer (Domain Controllers left out), each with a check box, under
    # its parent, sorted by name. Closed, but for the parents of the OUs chosen: those show.
    $settings = $script:Settings
    $root = $settings.Root
    $tree = $root.FindName('move_roots_tree')
    $tree.Items.Clear()
    $targets = @(Get-MoveTarget $settings.MoveDomain -All)
    $items = @{}
    $settings.MoveBoxes = @{}
    foreach ($target in $targets) {
        $box = [System.Windows.Controls.CheckBox]::new()
        # A text block: a check box's string takes _ for an access key, in the text and in the name it gives screen readers.
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $target.Name
        $box.Content = $label
        $box.Tag = $target.DN
        [System.Windows.Automation.AutomationProperties]::SetName($box, $target.Name)
        # Not the 32 of the app's check boxes: a tree of OUs reads as a list, and a long one fits more of them.
        $box.MinHeight = 0
        $box.MinWidth = 0
        # Ticked or unticked by a click, the keyboard or a screen reader; not when Update-MoveRootCheck sets it.
        $toggled = {
            param($box)
            if ($script:Settings.UpdatingBoxes) { return }
            Set-MoveRoot ([string]$box.Tag) ([bool]$box.IsChecked)
        }
        $box.Add_Checked($toggled)
        $box.Add_Unchecked($toggled)
        $item = [System.Windows.Controls.TreeViewItem]::new()
        $item.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Tree.Item')
        # The style's header shows text: the check box shows itself instead.
        $item.HeaderTemplate = $null
        $item.Header = $box
        [System.Windows.Automation.AutomationProperties]::SetName($item, $target.Name)
        $items[$target.DN] = $item
        $settings.MoveBoxes[$target.DN] = $box
    }
    foreach ($target in ($targets | Sort-Object Name)) {
        $parent = $items[(Get-ParentDN $target.DN)]
        if ($parent) { $parent.Items.Add($items[$target.DN]) | Out-Null } else { $tree.Items.Add($items[$target.DN]) | Out-Null }
    }
    foreach ($dn in @($script:moveRootList) | Where-Object { $items[$_] }) {
        for ($parent = $items[$dn].Parent; $parent -is [System.Windows.Controls.TreeViewItem]; $parent = $parent.Parent) { $parent.IsExpanded = $true }
    }
    $status = $root.FindName('move_roots_status')
    $status.Visibility = ConvertTo-Visibility (-not $targets.Count)
    if (-not $targets.Count) { $status.Text = Tr 'Aucune OU dans ce domaine.' }
    Update-MoveRootCheck
    Update-MoveRootFilter
}

function Update-MoveRootFilter {
    # The tree shows the OUs the filter finds, and says so when it finds none.
    $root = $script:Settings.Root
    $found = Set-OuFilter $root.FindName('move_roots_tree').Items "$($root.FindName('move_roots_filter').Text)".Trim()
    if (-not $script:Settings.MoveBoxes.Count) { return }
    $status = $root.FindName('move_roots_status')
    $status.Visibility = ConvertTo-Visibility (-not $found)
    if (-not $found) { $status.Text = Tr 'Aucune OU ne correspond.' }
}

function Update-MoveRootCheck {
    # The boxes follow the OUs chosen: an OU under a chosen one is offered with it, so it shows ticked and can't be
    # unticked on its own. With -MoveRoots, nothing can be changed.
    $roots = @($script:moveRootList)
    $script:Settings.UpdatingBoxes = $true
    try {
        foreach ($dn in $script:Settings.MoveBoxes.Keys) {
            $box = $script:Settings.MoveBoxes[$dn]
            $chosen = $roots -contains $dn
            $under = [bool]@($roots | Where-Object { $_ -ne $dn -and (Test-UnderDN $dn $_) }).Count
            $box.IsChecked = $chosen -or $under
            $box.IsEnabled = -not $under -and -not $script:Settings.Imposed
        }
    }
    finally { $script:Settings.UpdatingBoxes = $false }
    Update-MoveRootChosen
}

function Update-MoveRootChosen {
    # The card of the OUs chosen, whatever their domain: what Déplacer vers… then offers (each domain has its own limit:
    # Get-MoveTarget), and a row to take each one off (-MoveRoots: to read only).
    $root = $script:Settings.Root
    $roots = @($script:moveRootList)
    $root.FindName('move_roots_summary').Text = if (-not $roots.Count) { Tr 'Toutes les OU, sauf Domain Controllers. Cochez-en pour limiter la liste.' }
                                                elseif ($script:domainList.Count -gt 1) { Tr 'Les OU cochées et celles qu''elles contiennent. Un domaine sans case cochée les propose toutes.' }
                                                elseif ($roots.Count -eq 1) { Tr 'Cette OU et celles qu''elle contient.' }
                                                else { Tr 'Ces OU et celles qu''elles contiennent.' }
    $list = $root.FindName('move_roots_chosen')
    $list.Children.Clear()
    foreach ($dn in $roots | Sort-Object { Get-ShortPath "CN=x,$_" }) { $list.Children.Add((New-MoveRootRow $dn)) | Out-Null }
    $root.FindName('move_roots_clear').Visibility = ConvertTo-Visibility ($roots.Count -and -not $script:Settings.Imposed)
}

function New-MoveRootRow([string]$DistinguishedName) {
    # A row of the OUs chosen: its name, where it is, and the button that takes it off.
    $path = Get-ShortPath $DistinguishedName
    $name = (($DistinguishedName -split '(?<!\\),')[0] -replace '^\w+=', '') -replace '\\(.)', '$1'
    $row = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="14,0,8,8" ToolTip="$(ConvertTo-XamlValue $path)">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel VerticalAlignment="Center">
    <TextBlock Text="$(ConvertTo-XamlValue $name)" FontWeight="{DynamicResource R.FontWeightStrong}" TextTrimming="CharacterEllipsis"/>
    <TextBlock Text="$(ConvertTo-XamlValue $path)" Style="{StaticResource Txt.Muted}" FontSize="12" TextTrimming="CharacterEllipsis"/>
  </StackPanel>
  <Button Grid.Column="1" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center" ToolTip="Retirer" AutomationProperties.Name="$(ConvertTo-XamlValue ((Tr 'Retirer {0}') -f $name))">{{icon:x:12}}</Button>
</Grid>
"@))
    $button = $row.Children[1]
    $button.Visibility = ConvertTo-Visibility (-not $script:Settings.Imposed)
    $button.CommandParameter = $DistinguishedName
    $button.Add_Click({
        param($button)
        $index = $script:Settings.Root.FindName('move_roots_chosen').Children.IndexOf($button.Parent)
        Set-MoveRoot ([string]$button.CommandParameter) $false
        Set-MoveRootFocus $index
    })
    $row
}

function Set-MoveRootFocus([int]$Index) {
    # The button that had the keyboard is gone with its row: the row now in its place takes it, or the last one, or the
    # filter when none is left.
    $root = $script:Settings.Root
    $rows = $root.FindName('move_roots_chosen')
    $rows.UpdateLayout()
    $target = if ($rows.Children.Count) { $rows.Children[[Math]::Min($Index, $rows.Children.Count - 1)].Children[1] } else { $root.FindName('move_roots_filter') }
    $null = $target.Focus()
}

function Set-MoveRoot([string]$DistinguishedName, [bool]$Chosen) {
    # Adds an OU (the chosen ones under it are then redundant) or removes it, saves, and redraws the boxes.
    if ($script:Settings.Imposed) { return }
    $roots = @($script:moveRootList | Where-Object { $_ -ne $DistinguishedName })
    if ($Chosen) { $roots = @($roots | Where-Object { -not (Test-UnderDN $_ $DistinguishedName) }) + $DistinguishedName }
    $script:moveRootList = $roots
    Save-SettingFile
    Update-MoveRootCheck
}
