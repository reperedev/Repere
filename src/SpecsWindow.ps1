# The Caractéristiques window: a computer's hardware, Windows and network, read over CIM (PCSpecs.ps1) in a background
# runspace and shown section by section as they arrive. Opened from the results, one window per computer: several can
# stay open side by side, and opening one again brings it to the front. Dot-sourced by the main script, after
# Theme.ps1 (styles and icons).
#
# Control names double as UI Automation ids for tests\Test-RepereUI.ps1: each value is spec_<Section>_<Property>.

. "$PSScriptRoot\PCSpecs.ps1"

$script:SpecsCollectorPath = "$PSScriptRoot\PCSpecs.ps1"

# Each section's fields, by column (their labels come from $SpecsSections): a column is one subject, what's asked for
# most at its top, and the columns go from the most asked to the least. The report follows the same order. Réseau and
# Processeur have three columns, for their long values to fit on a line. The disks and the monitors are drawn in code,
# and the programs are in a grid of their own.
$script:SpecsLayout = [ordered]@{
    General   = @(@('ComputerName', 'LoggedOnUser', 'LastBoot'), @('Manufacturer', 'Model', 'SerialNumber'), @('OSName', 'BuildNumber', 'OSType'), @('Bios', 'SKU'))
    Network   = @(@('IPAddress', 'DNS'), @('LinkType', 'Adapter', 'MAC'), @('FQDN', 'Domain'))
    Processor = @(@('Name', 'Vendor', 'Extra'), @('Cores', 'Architecture'), @('BaseClock', 'L3Cache'))
    Memory    = @(@('Total', 'Type'), @('Speed', 'Physical'), @('Maker', 'Part'))
    Disk      = @(, @(, 'Storage'))
    Monitor   = @(, @(, 'Count'))
    Battery   = @(@(, 'Capacity'), @(, 'PowerStatus'), @(, 'Health'), @(, 'Cycles'))
    Dock      = @(@('Status', 'Model'), @('Firmware', 'Driver'), @(, 'Devices'))
    Software  = @()
}

# The open windows, by computer (domain|DN), and the readings stopped by Annuler or by closing their window, disposed
# once they end (a query stuck on an unreachable computer may only end on its own).
$script:SpecsWindows = @{}
$script:SpecsStopping = [System.Collections.Generic.List[object]]::new()

# Runs in the reading's own runspace: the fake AD's module first, when it's used, so the collector reads its computers;
# Tr and Get-TextCulture (Language.ps1), so its text is in Repère's language.
$script:SpecsJobScript = {
    param([string]$Collector, [string]$FakeModule, [string]$Target, $Queue, [string]$LanguageScript)
    if ($FakeModule) { Import-Module $FakeModule }
    . ([scriptblock]::Create($LanguageScript))
    # Its numbers (-f) in the language's conventions, not Windows's: 1.60 GHz in English, 1,60 GHz in French.
    [System.Threading.Thread]::CurrentThread.CurrentCulture = Get-TextCulture
    . $Collector
    Get-PCSpec -ComputerName $Target -SectionQueue $Queue
}.ToString()

function ConvertTo-XamlText([string]$Text) {
    # Escaped, and kept as it is in English (Language.ps1): disk models and volume labels are data.
    ConvertTo-XamlValue $Text
}

function Get-SpecsFieldXaml([string]$Section, [string]$Field) {
    # A label and its value, in a read-only text box so it can be selected and copied.
    $label = ConvertTo-XamlText $script:SpecsSections[$Section].Fields[$Field]
    "<StackPanel Margin=`"0,0,18,14`"><TextBlock Style=`"{StaticResource Spec.Label}`" Text=`"$label`"/>" +
    "<TextBox x:Name=`"spec_$($Section)_$Field`" Style=`"{StaticResource Spec.Value}`" AutomationProperties.Name=`"$label`" Text=`"…`"/></StackPanel>"
}

function Get-SpecsSectionXaml([string]$Key) {
    # A card: its header opens or closes it (with a summary when it's closed) and copies it; then its fields.
    $title = ConvertTo-XamlText $script:SpecsSections[$Key].Title
    $copyName = ConvertTo-XamlText ((Tr 'Copier la section {0}') -f $script:SpecsSections[$Key].Title)
    $columns = foreach ($column in $script:SpecsLayout[$Key]) {
        "<StackPanel>$(($column | ForEach-Object { Get-SpecsFieldXaml $Key $_ }) -join '')</StackPanel>"
    }
    $body = if ($Key -eq 'Disk') { "<StackPanel>$columns<StackPanel x:Name=`"disk_panel`" Margin=`"0,0,0,14`"/></StackPanel>" }
            elseif ($Key -eq 'Monitor') { "<StackPanel>$columns<StackPanel x:Name=`"monitor_panel`"/></StackPanel>" }
            elseif ($Key -eq 'Software') { $script:SpecsSoftwareXaml }
            else { "<UniformGrid Columns=`"$($script:SpecsLayout[$Key].Count)`">$($columns -join '')</UniformGrid>" }
    @"
<Border x:Name="card_$Key" Style="{StaticResource Card}" Margin="0,0,0,12">
  <StackPanel>
    <Grid Margin="6">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button x:Name="toggle_$Key" Style="{StaticResource Btn.Ghost}" HorizontalContentAlignment="Left" Padding="8,6" AutomationProperties.Name="$title">
        <StackPanel Orientation="Horizontal">
          <Border x:Name="chevron_$Key" RenderTransformOrigin="0.5,0.5" TextElement.Foreground="{DynamicResource R.Muted}"><Border.RenderTransform><RotateTransform/></Border.RenderTransform>{{icon:chevron:14}}</Border>
          <TextBlock Text="$title" FontSize="14" FontWeight="{DynamicResource R.FontWeightTitle}" Foreground="{DynamicResource R.AccentText}" Margin="10,0,0,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="summary_$Key" Style="{StaticResource Txt.Muted}" FontWeight="{DynamicResource R.FontWeight}" Margin="14,0,0,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
        </StackPanel>
      </Button>
      <Button x:Name="copy_$Key" Grid.Column="1" Style="{StaticResource Btn.Mini}" VerticalAlignment="Center" ToolTip="Copier cette section" AutomationProperties.Name="$copyName">{{icon:copy:14}}</Button>
    </Grid>
    <Border x:Name="body_$Key" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,1,0,0" Padding="18,14,18,0">$body</Border>
  </StackPanel>
</Border>
"@
}

# The programs: a filter, how many are shown, and a grid that can be sorted, in its own scroll area.
$script:SpecsSoftwareXaml = @'
<StackPanel Margin="0,0,0,14">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Style="{StaticResource Field}" Height="34" Width="300">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Margin="11,0,2,0" TextElement.Foreground="{DynamicResource R.Muted}">{{icon:filter:14}}</Border>
        <TextBox x:Name="software_filter" Grid.Column="1" Style="{StaticResource Text.Bare}" Tag="Filtrer par nom, éditeur ou version" AutomationProperties.Name="Filtrer les logiciels"/>
      </Grid>
    </Border>
    <TextBlock x:Name="software_count" Grid.Column="1" Style="{StaticResource Txt.Muted}" Margin="14,0,0,0" VerticalAlignment="Center"/>
  </Grid>
  <Border BorderBrush="{DynamicResource R.Border}" BorderThickness="1" CornerRadius="6" Margin="0,10,0,0">
    <DataGrid x:Name="software_grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True" CanUserResizeColumns="True"
              CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Extended" SelectionUnit="FullRow" HeadersVisibility="Column"
              GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{DynamicResource R.Border}" Background="Transparent" RowBackground="Transparent"
              Foreground="{DynamicResource R.Text}" BorderThickness="0" RowHeight="30" Margin="1" Height="320"
              RowStyle="{StaticResource Grid.Row}" CellStyle="{StaticResource Grid.Cell}" ColumnHeaderStyle="{StaticResource Grid.Header}">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="*" MinWidth="200" ElementStyle="{StaticResource Grid.Text.Strong}"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="130" ElementStyle="{StaticResource Grid.Text}"/>
        <DataGridTextColumn Header="Éditeur" Binding="{Binding Publisher}" Width="190" ElementStyle="{StaticResource Grid.Text}"/>
        <DataGridTextColumn Header="Installé le" Binding="{Binding InstallDateText}" SortMemberPath="InstallDate" Width="95" ElementStyle="{StaticResource Grid.Text}"/>
        <DataGridTextColumn Header="Pour" Binding="{Binding Scope}" Width="95" ElementStyle="{StaticResource Grid.Text}"/>
      </DataGrid.Columns>
    </DataGrid>
  </Border>
</StackPanel>
'@

function Get-SpecsWindowXaml {
    # The app bar (the computer, and the actions on the report), a status line, then the sections, with the banners for
    # errors and alerts under them.
    $sections = ($script:SpecsSections.Keys | ForEach-Object { Get-SpecsSectionXaml $_ }) -join "`n"
    @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <Border.Resources>
    <Style x:Key="Spec.Label" TargetType="TextBlock"><Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource R.Muted}"/></Style>
    <!-- A value: read-only text that can be selected, without a frame. -->
    <Style x:Key="Spec.Value" TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
      <Setter Property="IsReadOnly" Value="True"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="0"/><Setter Property="MinHeight" Value="0"/><Setter Property="Margin" Value="-2,3,0,0"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeightStrong}"/><Setter Property="VerticalContentAlignment" Value="Top"/>
    </Style>
    <Style x:Key="Spec.Banner" TargetType="TextBox" BasedOn="{StaticResource Spec.Value}">
      <Setter Property="Margin" Value="0"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeight}"/>
      <!-- A long list scrolls in its banner rather than taking a small window's sections. -->
      <Setter Property="MaxHeight" Value="110"/><Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
    </Style>
    <!-- The labels of a disk or a screen: the same badges as Propriétés (#199), Système or Interne filled. -->
    <Style x:Key="Spec.Chip" TargetType="Border" BasedOn="{StaticResource Badge.Quiet}"><Setter Property="Margin" Value="8,0,0,0"/></Style>
    <Style x:Key="Spec.Chip.Accent" TargetType="Border" BasedOn="{StaticResource Badge}"><Setter Property="Margin" Value="8,0,0,0"/></Style>
    <Style x:Key="Spec.Link" TargetType="Button" BasedOn="{StaticResource Btn.Ghost}">
      <Setter Property="MinHeight" Value="0"/><Setter Property="Padding" Value="8,3"/><Setter Property="FontWeight" Value="{DynamicResource R.FontWeight}"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource R.Muted}"/>
    </Style>
  </Border.Resources>
  <DockPanel>

    <!-- Also the window's title bar (Set-WindowChrome), its buttons at the end. -->
    <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="16,10,0,10">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <!-- A DockPanel, not a horizontal StackPanel: the text gets the width left by the buttons, and trims to it. -->
        <DockPanel VerticalAlignment="Center">
          <Border DockPanel.Dock="Left" Width="38" Height="38" CornerRadius="8" Background="{DynamicResource R.Selection}" TextElement.Foreground="{DynamicResource R.AccentText}">
            <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:cpu:20}}</Grid>
          </Border>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock x:Name="spec_title" FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="spec_subtitle" Style="{StaticResource Txt.Muted}" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
        </DockPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0">
          <Button x:Name="spec_cancel" Margin="0,0,8,0" Visibility="Collapsed" Content="Annuler" ToolTip="Arrêter la lecture (Échap)"/>
          <Button x:Name="spec_refresh" ToolTip="Lire de nouveau (F5)">
            <StackPanel Orientation="Horizontal">{{icon:refresh}}<TextBlock Text="Actualiser" Margin="8,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="spec_copy" Margin="8,0,0,0" ToolTip="Copier le rapport (Ctrl+C)">
            <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="spec_export" Margin="8,0,0,0" ToolTip="Enregistrer en JSON et en texte dans Documents\PCSpecs">
            <StackPanel Orientation="Horizontal">{{icon:download}}<TextBlock Text="Exporter" Margin="8,0,0,0"/></StackPanel>
          </Button>
          <Button x:Name="spec_open_folder" Style="{StaticResource Btn.Ghost}" Margin="8,0,0,0" Visibility="Collapsed" ToolTip="Afficher le dernier export dans l'Explorateur">
            <StackPanel Orientation="Horizontal">{{icon:folder}}<TextBlock Text="Ouvrir le dossier" Margin="8,0,0,0"/></StackPanel>
          </Button>
        </StackPanel>
        <StackPanel x:Name="caption_buttons" Grid.Column="2" Orientation="Horizontal" Margin="12,-10,0,-10"/>
      </Grid>
    </Border>

    <Grid DockPanel.Dock="Top" Margin="16,10,16,8">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="spec_status" Style="{StaticResource Txt.Muted}" FontSize="12" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel x:Name="spec_toolbar" Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="spec_expand_all" Style="{StaticResource Spec.Link}" Content="Tout développer"/>
        <Button x:Name="spec_collapse_all" Style="{StaticResource Spec.Link}" Content="Tout réduire"/>
      </StackPanel>
    </Grid>

    <!-- The banners, known once the reading ends: under the sections, so the view only gets shorter from below and
         nothing being read moves; and always in sight while scrolling. -->
    <StackPanel DockPanel.Dock="Bottom" Margin="16,0,16,0">
      <Border x:Name="spec_error" Visibility="Collapsed" Background="{DynamicResource R.DangerBg}" BorderBrush="{DynamicResource R.DangerBorder}" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
        <TextBox x:Name="spec_error_text" Style="{StaticResource Spec.Banner}" Foreground="{DynamicResource R.DangerText}"/>
      </Border>
      <!-- Several alerts: the first, and Tout voir for the list (Update-SpecsAlertBanner). -->
      <Border x:Name="spec_alert" Visibility="Collapsed" Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBlock x:Name="spec_alert_summary" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
          <TextBox x:Name="spec_alert_text" Style="{StaticResource Spec.Banner}"/>
          <Button x:Name="spec_alert_toggle" Grid.Column="1" Style="{StaticResource Spec.Link}" Margin="12,-4,-8,-4" VerticalAlignment="Top" Visibility="Collapsed"/>
        </Grid>
      </Border>
    </StackPanel>

    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <StackPanel Margin="16,0,16,16">
        <StackPanel x:Name="spec_empty" Visibility="Collapsed" HorizontalAlignment="Center" Margin="0,36,0,0">
          <Border HorizontalAlignment="Center" TextElement.Foreground="{DynamicResource R.Faint}">{{icon:cpu:32}}</Border>
          <TextBlock Text="Caractéristiques non lues" FontSize="15" FontWeight="{DynamicResource R.FontWeightTitle}" HorizontalAlignment="Center" Margin="0,10,0,0"/>
          <TextBlock x:Name="spec_empty_text" Style="{StaticResource Txt.Muted}" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="520" Margin="0,6,0,0"/>
        </StackPanel>
        <StackPanel x:Name="spec_sections">
$sections
        </StackPanel>
      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</Border>
"@
}

function Get-SpecsState($Element) {
    # The state of the window that holds a control (its Tag).
    [System.Windows.Window]::GetWindow($Element).Tag
}

function Set-SpecsLevel($Element, [string]$Level) {
    # An alert's color on a value: warn or crit, or back to the style's.
    switch ($Level) {
        'crit' { $Element.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'R.DangerText') }
        'warn' { $Element.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'R.WarnText') }
        default { $Element.ClearValue([System.Windows.Controls.Control]::ForegroundProperty) }
    }
}

function Get-SpecsSummary([string]$Key, $Data, $Alerts) {
    # One line for a closed section.
    if (-not $Data) { return Tr 'Non lue' }
    $notAvailable = Tr 'N/D'
    $join = { ($args | Where-Object { $_ -and $_ -ne $notAvailable }) -join ' · ' }
    $text = switch ($Key) {
        General   { & $join "$($Data.Manufacturer) $($Data.Model)".Replace($notAvailable, '').Trim() $(if ($Data.SerialNumber -and $Data.SerialNumber -ne $notAvailable) { (Tr 'série {0}') -f $Data.SerialNumber }) $Data.OSName }
        Network   { & $join (("$($Data.IPAddress)" -split "`n")[0]) $Data.LinkType }
        Processor { & $join $Data.Name ((Tr '{0} cœurs / threads') -f $Data.Cores) }
        Memory    { & $join $Data.Total $Data.Type }
        Disk      { & $join $(if ($Data.DiskCount -eq 1) { Tr '1 disque' } else { (Tr '{0} disques') -f $Data.DiskCount }) $Data.Storage }
        Battery   { if ($Data.Present) { & $join $Data.Capacity $(if ($null -ne $Data.HealthPercent) { (Tr 'santé {0} %') -f $Data.HealthPercent }) } else { Tr 'Aucune batterie' } }
        Monitor   { & $join $Data.Count (@($Data.Monitors | ForEach-Object Name) -join ', ') }
        Dock      { if ($Data.Connected) { & $join $Data.Status $Data.Model } else { $Data.Status } }
        Software  { $Data.Count }
    }
    if (@($Alerts | Where-Object { $_.Section -eq $Key }).Count) { $text = "⚠ $text" }
    $text
}

function Show-SpecsDisk($State, $Disk, $Alerts) {
    # One block per physical disk (its model, type, size), then a bar per volume, in the alert's color when it's full.
    # Parsed on its own, before it's in the window: the window's styles are DynamicResource here.
    $panel = $State.Controls['disk_panel']
    $panel.Children.Clear()
    if (-not $Disk) { return }
    $levels = @{}
    foreach ($alert in @($Alerts | Where-Object { $_.Section -eq 'Disk' })) { $levels[$alert.Field] = $alert.Level }
    foreach ($drive in $Disk.Drives) {
        $chips = ''
        if ($drive.Tech -and $drive.Tech -ne (Tr 'N/D')) { $chips += "<Border Style=`"{DynamicResource Spec.Chip}`"><TextBlock Text=`"$(ConvertTo-XamlText $drive.Tech)`"/></Border>" }
        if ($drive.IsSystem) { $chips += "<Border Style=`"{DynamicResource Spec.Chip.Accent}`"><TextBlock Text=`"$(ConvertTo-XamlText (Tr 'Système'))`"/></Border>" }
        $rows = foreach ($volume in $drive.Volumes) {
            $level = $levels["Volume:$($volume.Drive)"]
            $fill = switch ($level) { 'crit' { 'R.DangerText' } 'warn' { 'R.WarnText' } default { 'R.Accent' } }
            $used = [Math]::Min([Math]::Max([int]$volume.UsedPercent, 0), 100)
            $name = if ($volume.Label) { "$($volume.Drive) $($volume.Label)" } else { $volume.Drive }
            $id = 'vol_' + ($volume.Drive -replace '[^A-Za-z0-9]', '')
            @"
<Grid Margin="0,10,0,0">
  <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <TextBlock Text="$(ConvertTo-XamlText $name)" FontWeight="{DynamicResource R.FontWeightStrong}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="$(ConvertTo-XamlText $name)"/>
  <Border Grid.Column="1" Height="8" CornerRadius="4" Background="{DynamicResource R.Input}" BorderBrush="{DynamicResource R.Border}" BorderThickness="1" VerticalAlignment="Center">
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="$used*"/><ColumnDefinition Width="$(100 - $used)*"/></Grid.ColumnDefinitions>
      <Border CornerRadius="3" Background="{DynamicResource $fill}"/></Grid>
  </Border>
  <TextBox x:Name="$id" Grid.Column="2" Style="{DynamicResource Spec.Value}" Margin="14,0,0,0" VerticalAlignment="Center" Text="$(ConvertTo-XamlText $volume.Text)" AutomationProperties.Name="$(ConvertTo-XamlText $volume.Drive)"/>
</Grid>
"@
        }
        if (-not $rows) { $rows = "<TextBlock Style=`"{StaticResource Txt.Muted}`" Margin=`"0,8,0,0`" Text=`"$(ConvertTo-XamlText (Tr 'Aucun volume monté'))`"/>" }
        $size = if ($drive.SizeText) { "<TextBlock Style=`"{StaticResource Txt.Muted}`" Margin=`"8,0,0,0`" VerticalAlignment=`"Center`" Text=`"$(ConvertTo-XamlText $drive.SizeText)`"/>" }
        $xaml = @"
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,0,0,14">
  <WrapPanel><TextBlock Text="$(ConvertTo-XamlText $drive.Model)" FontWeight="{DynamicResource R.FontWeightStrong}" VerticalAlignment="Center"/>$chips$size</WrapPanel>
  $($rows -join "`n")
</StackPanel>
"@
        # Its text is translated where it's made, not here: the rest is the disks' own names.
        $block = [System.Windows.Markup.XamlReader]::Parse($xaml)
        # Volume text boxes are found by name, for the tests.
        foreach ($volume in $drive.Volumes) {
            $id = 'vol_' + ($volume.Drive -replace '[^A-Za-z0-9]', '')
            $box = $block.FindName($id)
            if ($box) { Set-SpecsLevel $box $levels["Volume:$($volume.Drive)"] }
        }
        $panel.Children.Add($block) | Out-Null
    }
}

function Show-SpecsMonitor($State, $Section) {
    # One block per monitor of the Écrans section: its name, how it's connected, then its size, native resolution, serial
    # number and maker, each in a text box that can be selected (mon_<n>_<Property>, for the tests). Parsed on its own,
    # like the disks'.
    $panel = $State.Controls['monitor_panel']
    $panel.Children.Clear()
    if (-not $Section) { return }
    $fields = [ordered]@{ Size = Tr 'Taille'; Resolution = Tr 'Résolution native'; Serial = Tr 'Numéro de série'; Manufacturer = Tr 'Fabricant' }
    $number = 0
    foreach ($monitor in @($Section.Monitors)) {
        $number++
        $chips = ''
        if ($monitor.Connection) {
            $style = if ($monitor.Internal) { 'Spec.Chip.Accent' } else { 'Spec.Chip' }
            $chips = "<Border Style=`"{DynamicResource $style}`"><TextBlock Text=`"$(ConvertTo-XamlText $monitor.Connection)`"/></Border>"
        }
        $values = foreach ($field in $fields.GetEnumerator()) {
            $label = ConvertTo-XamlText $field.Value
            "<StackPanel Margin=`"0,0,18,0`"><TextBlock Style=`"{DynamicResource Spec.Label}`" Text=`"$label`"/>" +
            "<TextBox x:Name=`"mon_$($number)_$($field.Key)`" Style=`"{DynamicResource Spec.Value}`" AutomationProperties.Name=`"$label`" Text=`"$(ConvertTo-XamlText "$($monitor.($field.Key))")`"/></StackPanel>"
        }
        $xaml = @"
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,0,0,14">
  <WrapPanel><TextBlock x:Name="mon_$($number)_Name" Text="$(ConvertTo-XamlText $monitor.Name)" FontWeight="{DynamicResource R.FontWeightStrong}" VerticalAlignment="Center"/>$chips</WrapPanel>
  <UniformGrid Columns="4" Margin="0,8,0,0">$($values -join '')</UniformGrid>
</StackPanel>
"@
        $panel.Children.Add([System.Windows.Markup.XamlReader]::Parse($xaml)) | Out-Null
    }
}

function Show-SpecsSoftware($State, $Software) {
    # The programs in the grid, through a view that the filter box narrows (what's typed there stays for the next
    # reading).
    # Assigned directly: through an if's output, PowerShell would unroll the view into a plain list of programs.
    $State.Software = $null
    if ($Software) { $State.Software = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($Software.Programs)) }
    $State.Controls['software_grid'].ItemsSource = $State.Software
    if ($State.Software) {
        $State.Software.Filter = [Predicate[object]]{
            param($program)
            $query = $State.SoftwareFilter
            -not $query -or "$($program.Name) $($program.Publisher) $($program.Version)".ToLowerInvariant().Contains($query)
        }.GetNewClosure()
    }
    Update-SpecsSoftwareCount $State
}

function Update-SpecsSoftwareCount($State) {
    $count = $State.Controls['software_count']
    if (-not $State.Software) { $count.Text = ''; return }
    $total = @($State.Software.SourceCollection).Count
    $shown = @($State.Software).Count
    $count.Text = if ($shown -ne $total) { (Tr '{0} sur {1}') -f $shown, $total } elseif ($total -eq 1) { Tr '1 logiciel' } else { (Tr '{0} logiciels') -f $total }
}

function Set-SpecsSection($State, [string]$Key, $Data, $Alerts) {
    # A section's values: N/D when Windows didn't say, — when the section couldn't be read.
    foreach ($column in $script:SpecsLayout[$Key]) {
        foreach ($field in $column) {
            $box = $State.Controls["spec_$($Key)_$field"]
            $value = if ($Data) { "$($Data.$field)" }
            $box.Text = if (-not $Data) { '—' } elseif ($value) { $value } else { Tr 'N/D' }
            # A field only shown when it has a value (SpecsOptionalFields) goes with its label; before the reading, and
            # when the section couldn't be read, it stays, as the others do.
            if ($field -in $script:SpecsOptionalFields[$Key]) { $box.Parent.Visibility = ConvertTo-Visibility (-not $Data -or [bool]$value) }
            $level = $Alerts | Where-Object { $_.Section -eq $Key -and $_.Field -eq $field } | ForEach-Object Level | Select-Object -First 1
            Set-SpecsLevel $box $level
        }
    }
    if ($Key -eq 'Disk') { Show-SpecsDisk $State $Data $Alerts }
    if ($Key -eq 'Monitor') { Show-SpecsMonitor $State $Data }
    if ($Key -eq 'Software') { Show-SpecsSoftware $State $Data }
    $State.Summaries[$Key] = Get-SpecsSummary $Key $Data $Alerts
    Update-SpecsSectionHeader $State $Key
    # Général says whether it's a laptop (it's read first), which Batterie and Station d'accueil wait for.
    if ($Key -eq 'General') { $State.Mobile = if ($Data) { $Data.Mobile } else { $null } }
    $State.Read[$Key] = $Data
    Update-SpecsOptionalCard $State
}

function Update-SpecsOptionalCard($State) {
    # Batterie and Station d'accueil: shown for a laptop, else only once read and when there's one
    # (Test-PCSpecSectionShown), so a desktop's never appears to go again.
    foreach ($key in 'Battery', 'Dock') {
        $shown = Test-PCSpecSectionShown $key $State.Read[$key] $State.Mobile $State.Read.ContainsKey($key)
        $State.Controls["card_$key"].Visibility = ConvertTo-Visibility $shown
    }
}

function Update-SpecsSectionHeader($State, [string]$Key) {
    # Open: the chevron points down. Closed: it points right, and the summary follows the title.
    $expanded = $State.Expanded[$Key]
    $State.Controls["body_$Key"].Visibility = ConvertTo-Visibility $expanded
    $State.Controls["chevron_$Key"].RenderTransform.Angle = if ($expanded) { 0 } else { -90 }
    $summary = $State.Controls["summary_$Key"]
    $summary.Text = $State.Summaries[$Key]
    $summary.Visibility = ConvertTo-Visibility (-not $expanded -and $summary.Text)
}

function Set-SpecsBusy($State, [bool]$Busy) {
    $State.Controls['spec_cancel'].Visibility = ConvertTo-Visibility $Busy
    $State.Controls['spec_refresh'].IsEnabled = -not $Busy
    $hasData = -not $Busy -and [bool]$State.Last
    $State.Controls['spec_copy'].IsEnabled = $hasData
    $State.Controls['spec_export'].IsEnabled = $hasData
}

function Set-SpecsView($State, [bool]$Failed) {
    # Either the sections, or the empty state when the computer couldn't be read.
    $State.Controls['spec_sections'].Visibility = ConvertTo-Visibility (-not $Failed)
    $State.Controls['spec_toolbar'].Visibility = ConvertTo-Visibility (-not $Failed)
    $State.Controls['spec_empty'].Visibility = ConvertTo-Visibility $Failed
}

function Show-SpecsBanner($State, [string]$Name, [string[]]$Lines) {
    $State.Controls["spec_$Name"].Visibility = ConvertTo-Visibility ([bool]$Lines)
    $State.Controls["spec_$($Name)_text"].Text = $Lines -join "`n"
    if ($Name -eq 'alert') {
        $State.AlertLines = @($Lines)
        Update-SpecsAlertBanner $State
    }
}

function Update-SpecsAlertBanner($State) {
    # Several alerts: the first alone, and Tout voir for the list. The banner stays in sight under the sections, so it
    # takes their room: a line rather than one per alert (three took about 100 px at 130 %). Each section shows its ⚠,
    # and the status line counts them. Opened, the list stays open for the window's next readings.
    $lines = @($State.AlertLines)
    $folded = $lines.Count -gt 1 -and -not $State.AlertsOpen
    $controls = $State.Controls
    $controls['spec_alert_summary'].Text = if ($lines) { $lines[0] } else { '' }
    $controls['spec_alert_summary'].Visibility = ConvertTo-Visibility $folded
    $controls['spec_alert_text'].Visibility = ConvertTo-Visibility (-not $folded)
    $controls['spec_alert_toggle'].Visibility = ConvertTo-Visibility ($lines.Count -gt 1)
    $controls['spec_alert_toggle'].Content = if ($folded) { (Tr 'Tout voir ({0})') -f $lines.Count } else { Tr 'Replier' }
}

function Show-SpecsReading($State, $Specs) {
    # A complete reading: every section with its alerts, the banners and the header.
    $alerts = @($Specs.Alerts | Where-Object { $_ })
    Set-SpecsView $State $false
    foreach ($key in $script:SpecsSections.Keys) { Set-SpecsSection $State $key $Specs.$key $alerts }
    $sorted = @($alerts | Where-Object Level -eq 'crit') + @($alerts | Where-Object Level -ne 'crit')
    Show-SpecsBanner $State 'alert' @($sorted | ForEach-Object { "$(if ($_.Level -eq 'crit') { '⛔' } else { '⚠' })  $($_.Message)" })
    Show-SpecsBanner $State 'error' @($Specs.Errors.GetEnumerator() | ForEach-Object { (Tr '{0} non lu : {1}') -f $script:SpecsSections[$_.Key].Title, $_.Value })
    Set-SpecsSubtitle $State ((Tr 'lu le {0}') -f (Format-TextDate $Specs.Timestamp))
}

function Set-SpecsSubtitle($State, [string]$When) {
    $computer = $State.Computer
    $text = (@($computer.HostName, $computer.Description, $When) | Where-Object { $_ }) -join ' · '
    # All of it in the tooltip, for when it's trimmed (a long description, a large text size).
    $State.Controls['spec_subtitle'].Text = $text
    $State.Controls['spec_subtitle'].ToolTip = if ($text) { $text } else { $null }
}

function Show-SpecsFailure($State, [string]$Message) {
    # The computer couldn't be read: no sections, the error, and what to check.
    $State.Last = $null
    Set-SpecsView $State $true
    Show-SpecsBanner $State 'alert' @()
    Show-SpecsBanner $State 'error' @(ConvertTo-FrenchError $Message)
    $State.Controls['spec_empty_text'].Text = Tr "Vérifiez qu'il est allumé, que WinRM y est activé et que vous en êtes administrateur."
    Set-SpecsSubtitle $State ''
}

function Remove-StoppedSpecsJob {
    foreach ($job in @($script:SpecsStopping)) {
        if ($job.Handle.IsCompleted) {
            $job.Shell.Dispose()
            $script:SpecsStopping.Remove($job) | Out-Null
        }
    }
}

function Start-SpecsReading($State) {
    # Reads the computer in its own runspace. The timer shows the sections as they arrive, then the whole reading.
    Remove-StoppedSpecsJob
    $queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    # The runspace follows the process's execution policy, as the search runspaces do (the main script).
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $shell = [powershell]::Create($sessionState)
    $null = $shell.AddScript($script:SpecsJobScript).AddParameters(@{
        Collector = $script:SpecsCollectorPath; FakeModule = $State.FakeModule; Target = $State.Computer.HostName; Queue = $queue
        LanguageScript = $script:LanguageScript
    })
    $State.Job = @{ Shell = $shell; Handle = $shell.BeginInvoke(); Queue = $queue; Watch = [System.Diagnostics.Stopwatch]::StartNew(); Read = 0 }

    Set-SpecsView $State $false
    Show-SpecsBanner $State 'error' @()
    Show-SpecsBanner $State 'alert' @()
    foreach ($box in $State.Values) {
        $box.Text = '…'
        Set-SpecsLevel $box $null
    }
    $State.Controls['disk_panel'].Children.Clear()
    $State.Controls['monitor_panel'].Children.Clear()
    Show-SpecsSoftware $State $null
    $State.Controls['software_count'].Text = '…'
    foreach ($key in $script:SpecsSections.Keys) {
        $State.Summaries[$key] = Tr 'Lecture…'
        Update-SpecsSectionHeader $State $key
    }
    $State.Mobile = $null
    $State.Read = @{}
    Update-SpecsOptionalCard $State
    $State.Controls['spec_status'].Text = (Tr 'Connexion à {0}…') -f $State.Computer.HostName
    $State.Controls['spec_status'].ToolTip = $null
    Set-SpecsBusy $State $true
    $State.Timer.Start()
}

function Show-SpecsProgress($State, $Item) {
    if ($Item.Name -eq 'Connexion') {
        if (-not $Item.Error) { $State.Controls['spec_status'].Text = Tr 'Lecture des caractéristiques…' }
        return
    }
    Set-SpecsSection $State $Item.Name $Item.Data @()
    $State.Job.Read++
    $State.Controls['spec_status'].Text = (Tr 'Lecture des caractéristiques… ({0} sur {1})') -f $State.Job.Read, $script:SpecsSections.Count
}

function Update-SpecsReading($State) {
    # On each tick: the sections read since the last one, then the end of the reading.
    $job = $State.Job
    if (-not $job) { $State.Timer.Stop(); return }
    $item = $null
    while ($job.Queue.TryDequeue([ref]$item)) { Show-SpecsProgress $State $item }
    if (-not $job.Handle.IsCompleted) { return }
    while ($job.Queue.TryDequeue([ref]$item)) { Show-SpecsProgress $State $item }
    Complete-SpecsReading $State
}

function Format-SpecsTiming($Specs) {
    # The status's tooltip: how long the connection and each section took, how it connected, and how the software was
    # read (in one WinRM call, or value by value).
    $culture = Get-TextCulture
    $ways = @{ WinRM = 'WinRM'; DCOM = 'DCOM'; Local = (Tr 'cet ordinateur') }
    $software = @{ WinRM = (Tr 'en un appel WinRM'); Registry = (Tr 'par le registre à distance, valeur par valeur'); Local = (Tr 'sur cet ordinateur') }
    $lines = foreach ($name in $Specs.Timings.Keys) {
        $ms = ([long]$Specs.Timings[$name]).ToString('N0', $culture)
        $how = if ($name -eq 'Connexion' -and $Specs.Protocol) { $ways[$Specs.Protocol] }
               elseif ($name -eq 'Software' -and $Specs.SoftwareVia) { $software[$Specs.SoftwareVia] }
        $title = if ($name -eq 'Connexion') { Tr 'Connexion' } else { $script:SpecsSections[$name].Title }
        $line = (Tr '{0} : {1} ms') -f $title, $ms
        if ($how) { "$line ($how)" } else { $line }
    }
    $lines -join "`n"
}

function Complete-SpecsReading($State) {
    $job = $State.Job
    $State.Timer.Stop()
    $State.Job = $null
    $job.Watch.Stop()
    $specs = $null
    $failure = $null
    try {
        $specs = @($job.Shell.EndInvoke($job.Handle))[-1]
        if (-not $specs -and $job.Shell.Streams.Error.Count) { $failure = $job.Shell.Streams.Error[0].Exception.Message }
    }
    catch {
        $failure = $_.Exception.Message
    }
    finally {
        $job.Shell.Dispose()
    }

    if (-not $specs -or -not $specs.Reachable) {
        $message = if ($specs) { $specs.Errors['Connexion'] } elseif ($failure) { (Tr 'Erreur inattendue : {0}') -f $failure } else { Tr 'Erreur inattendue.' }
        Show-SpecsFailure $State $message
        $State.Controls['spec_status'].Text = Tr 'Échec de la lecture.'
        $State.Controls['spec_status'].ToolTip = if ($specs) { Format-SpecsTiming $specs } else { $null }
        Set-SpecsBusy $State $false
        return
    }

    $State.Last = $specs
    Show-SpecsReading $State $specs
    $notes = @(((Tr 'Lu en {0} s') -f $job.Watch.Elapsed.TotalSeconds.ToString('0.0', (Get-TextCulture))))
    $alertCount = @($specs.Alerts | Where-Object { $_ }).Count
    if ($alertCount) { $notes += if ($alertCount -eq 1) { Tr '1 alerte' } else { (Tr '{0} alertes') -f $alertCount } }
    if ($specs.Errors.Count) { $notes += if ($specs.Errors.Count -eq 1) { Tr '1 section non lue' } else { (Tr '{0} sections non lues') -f $specs.Errors.Count } }
    $State.Controls['spec_status'].Text = $notes -join ' · '
    $State.Controls['spec_status'].ToolTip = Format-SpecsTiming $specs
    Set-SpecsBusy $State $false
}

function Stop-SpecsReading($State, [switch]$Closing) {
    # Annuler, Échap or closing the window. Not waited for: the reading is disposed once it ends on its own.
    $job = $State.Job
    if (-not $job) { return }
    $State.Timer.Stop()
    $State.Job = $null
    $null = $job.Shell.BeginStop($null, $null)
    $script:SpecsStopping.Add($job)
    if ($Closing) { return }
    if ($State.Last) {
        Show-SpecsReading $State $State.Last
        $State.Controls['spec_status'].Text = Tr 'Lecture annulée : voici la lecture précédente.'
    }
    else {
        # What was read stays; the rest says it wasn't.
        foreach ($box in $State.Values) { if ($box.Text -eq '…') { $box.Text = '—' } }
        if ($State.Controls['software_count'].Text -eq '…') { $State.Controls['software_count'].Text = '—' }
        foreach ($key in $script:SpecsSections.Keys) {
            if ($State.Summaries[$key] -eq (Tr 'Lecture…')) { $State.Summaries[$key] = Tr 'Non lue'; Update-SpecsSectionHeader $State $key }
        }
        $State.Controls['spec_status'].Text = Tr 'Lecture annulée.'
    }
    Set-SpecsBusy $State $false
}

function Copy-SpecsReport($State, [string]$Section) {
    # The report, or one section, as text.
    if (-not $State.Last) { return }
    Set-Clipboard -Value (Format-PCSpecReport $State.Last $Section)
    $what = if ($Section) { (Tr 'Section « {0} » copiée') -f $script:SpecsSections[$Section].Title } else { Tr 'Rapport copié' }
    $State.Controls['spec_status'].Text = "$what ($('{0:HH:mm:ss}' -f (Get-Date)))."
}

function Export-SpecsReport($State) {
    # Documents\PCSpecs\<name>_<date>.json and .txt.
    $specs = $State.Last
    if (-not $specs) { return }
    try {
        $folder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PCSpecs'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $name = if ($specs.General -and $specs.General.ComputerName) { $specs.General.ComputerName } else { $State.Computer.ComputerName }
        # The date in the Gregorian calendar whatever the culture's (-f would write 2569 in th-TH), so reports sort by name.
        $base = Join-Path $folder ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}_{1:yyyyMMdd-HHmmss}', ($name -replace '[^\w\-\.]', '_'), $specs.Timestamp))
        $specs | ConvertTo-Json -Depth 6 | Set-Content -Path "$base.json" -Encoding utf8
        Format-PCSpecReport $specs | Set-Content -Path "$base.txt" -Encoding utf8
        $State.LastExport = "$base.txt"
        $State.Controls['spec_open_folder'].Visibility = 'Visible'
        $State.Controls['spec_status'].Text = (Tr 'Exporté : {0}.json et .txt') -f $base
    }
    catch {
        $State.Controls['spec_status'].Text = (Tr "Échec de l'export : {0}") -f (ConvertTo-FrenchError $_.Exception.Message)
    }
}

function Show-OpenSpecsWindow($Computer) {
    # The window of a computer, brought to the front when it's already open: whether it was.
    $open = $script:SpecsWindows["$($Computer.Domain)|$($Computer.OU)"]
    if (-not $open) { return $false }
    if ($open.WindowState -eq 'Minimized') { $open.WindowState = 'Normal' }
    $null = $open.Activate()
    $true
}

function Show-SpecsWindow($Computer, $Owner, $Icon, [string]$FakeModule) {
    # Opens the window of a computer (a row of the results), or brings it to the front when it's already open. The
    # action checks first that the computer answers (Start-SpecsCheck, ComputerActions.ps1).
    if (Show-OpenSpecsWindow $Computer) { return }
    $key = "$($Computer.Domain)|$($Computer.OU)"

    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon (Get-SpecsWindowXaml)))
    $window = [System.Windows.Window]::new()
    $window.Title = (Tr 'Caractéristiques — {0}') -f $Computer.ComputerName
    $window.Icon = $Icon
    $window.Owner = $Owner
    $window.Width = 980
    $window.Height = [Math]::Min(900, [System.Windows.SystemParameters]::WorkArea.Height - 40)
    $window.MinWidth = 760
    $window.MinHeight = 420
    $window.WindowStartupLocation = 'CenterOwner'
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $window.Content = $root
    Set-WindowChrome $window -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-OwnerFocus $window

    $controls = @{}
    $names = 'spec_title', 'spec_subtitle', 'spec_cancel', 'spec_refresh', 'spec_copy', 'spec_export', 'spec_open_folder', 'spec_status',
             'spec_toolbar', 'spec_expand_all', 'spec_collapse_all', 'spec_error', 'spec_error_text', 'spec_alert', 'spec_alert_text', 'spec_alert_summary', 'spec_alert_toggle',
             'spec_empty', 'spec_empty_text', 'spec_sections', 'disk_panel', 'monitor_panel', 'software_filter', 'software_count', 'software_grid'
    foreach ($name in $names) { $controls[$name] = $root.FindName($name) }
    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($section in $script:SpecsSections.Keys) {
        foreach ($part in 'card', 'toggle', 'copy', 'body', 'chevron', 'summary') { $controls["$($part)_$section"] = $root.FindName("$($part)_$section") }
        foreach ($field in $script:SpecsLayout[$section] | ForEach-Object { $_ }) {
            $box = $root.FindName("spec_$($section)_$field")
            $controls["spec_$($section)_$field"] = $box
            $values.Add($box)
        }
    }
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(50)
    $state = @{
        Key = $key; Window = $window; Computer = $Computer; FakeModule = $FakeModule; Controls = $controls; Values = $values
        Timer = $timer; Job = $null; Last = $null; LastExport = $null; Expanded = @{}; Summaries = @{}; Software = $null; SoftwareFilter = ''
        # Whether it's a laptop (General's Mobile) and each section read so far, by key: Update-SpecsOptionalCard.
        Mobile = $null; Read = @{}
        # The alerts of the banner, and whether its list is open (Update-SpecsAlertBanner).
        AlertLines = @(); AlertsOpen = $false
        # Once the window closed: WinRM, when Repère turned it on for the window, can be put back (Update-WinRMLease).
        Closed = $false
    }
    # The programs are a long list: closed at first, with their count in the summary.
    foreach ($section in $script:SpecsSections.Keys) { $state.Expanded[$section] = $section -ne 'Software' }
    $window.Tag = $state
    $timer.Tag = $state
    $controls['spec_title'].Text = $Computer.ComputerName
    Set-SpecsSubtitle $state ''

    $timer.Add_Tick({ param($timer) Update-SpecsReading $timer.Tag })
    $controls['spec_refresh'].Add_Click({ param($control) Start-SpecsReading (Get-SpecsState $control) })
    $controls['spec_cancel'].Add_Click({ param($control) Stop-SpecsReading (Get-SpecsState $control) })
    $controls['spec_copy'].Add_Click({ param($control) Copy-SpecsReport (Get-SpecsState $control) })
    $controls['spec_export'].Add_Click({ param($control) Export-SpecsReport (Get-SpecsState $control) })
    $controls['spec_alert_toggle'].Add_Click({
        param($control)
        $state = Get-SpecsState $control
        $state.AlertsOpen = -not $state.AlertsOpen
        Update-SpecsAlertBanner $state
    })
    $controls['spec_open_folder'].Add_Click({
        param($control)
        $file = (Get-SpecsState $control).LastExport
        # Explorer with the exported file selected.
        if ($file -and (Test-Path -LiteralPath $file)) { Start-Process explorer.exe -ArgumentList "/select,`"$file`"" }
    })
    $controls['software_filter'].Add_TextChanged({
        param($box)
        $state = Get-SpecsState $box
        $state.SoftwareFilter = "$($box.Text)".Trim().ToLowerInvariant()
        if ($state.Software) { $state.Software.Refresh() }
        Update-SpecsSoftwareCount $state
    })
    $controls['spec_expand_all'].Add_Click({
        param($control)
        $state = Get-SpecsState $control
        foreach ($section in $script:SpecsSections.Keys) { $state.Expanded[$section] = $true; Update-SpecsSectionHeader $state $section }
    })
    $controls['spec_collapse_all'].Add_Click({
        param($control)
        $state = Get-SpecsState $control
        foreach ($section in $script:SpecsSections.Keys) { $state.Expanded[$section] = $false; Update-SpecsSectionHeader $state $section }
    })
    foreach ($section in $script:SpecsSections.Keys) {
        # The section's key is in the button's name (its Tag is the corner radius).
        $controls["toggle_$section"].Add_Click({
            param($control)
            $state = Get-SpecsState $control
            $key = $control.Name.Substring('toggle_'.Length)
            $state.Expanded[$key] = -not $state.Expanded[$key]
            Update-SpecsSectionHeader $state $key
            # Opened by the user (not by Tout développer): brought into view once laid out, Logiciels above all, which
            # opens below the fold. Its header goes to the top when it's taller than the view.
            if ($state.Expanded[$key]) {
                $card = $state.Controls["card_$key"]
                $null = $card.Dispatcher.BeginInvoke([Action]{ $card.BringIntoView() }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Loaded)
            }
        })
        $controls["copy_$section"].Add_Click({ param($control) Copy-SpecsReport (Get-SpecsState $control) $control.Name.Substring('copy_'.Length) })
    }

    # F5 reads again, Ctrl+C copies the report (unless some text is selected: the text box copies it and handles the
    # key), Échap stops a reading, or closes the window.
    $window.Add_KeyDown({
        param($specsWindow, $e)
        $state = $specsWindow.Tag
        $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        if ($e.Key -eq 'F5' -and -not $state.Job) { Start-SpecsReading $state; $e.Handled = $true }
        elseif ($e.Key -eq 'C' -and $ctrl) { Copy-SpecsReport $state; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape') {
            if ($state.Job) { Stop-SpecsReading $state } else { $specsWindow.Close() }
            $e.Handled = $true
        }
    })
    $window.Add_Closed({
        param($specsWindow)
        $state = $specsWindow.Tag
        Stop-SpecsReading $state -Closing
        $state.Closed = $true
        $script:SpecsWindows.Remove($state.Key)
    })

    # Each new window a little lower and to the right of the previous ones, so they don't hide each other.
    $offset = 28 * $script:SpecsWindows.Count
    $script:SpecsWindows[$key] = $window
    $window.Show()
    # Kept within the work area of its screen (Set-WindowInWorkArea): at its edge, over the previous one.
    if ($offset) {
        $window.Left += $offset
        $window.Top += $offset
        Set-WindowInWorkArea $window
    }
    Start-SpecsReading $state
}
