# Clés BitLocker…: the recovery keys stored in AD for the selected computers, in a window of their own, to read, copy,
# and delete those no longer needed (a key left by an earlier installation of Windows, or by a disk replaced since).
# Only AD's copy is deleted: the disk keeps its key. Dot-sourced by the main script, after Theme.ps1.

# The window: a header like Caractéristiques', the keys in a card per disk (built by Update-BitLockerBody), and the
# ticked keys' actions at the bottom.
$script:BitLockerDialogXaml = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
           Background="{DynamicResource R.Bg}" TextElement.Foreground="{DynamicResource R.Text}">
  <!-- Also the window's title bar (Set-WindowChrome), its buttons at the end. -->
  <Border x:Name="title_bar" DockPanel.Dock="Top" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,0,0,1" Padding="16,12,0,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <!-- A DockPanel, not a horizontal StackPanel: the text gets the width left by Copier, and trims to it. -->
      <DockPanel VerticalAlignment="Center">
        <Border DockPanel.Dock="Left" Width="38" Height="38" CornerRadius="8" Background="{DynamicResource R.Selection}" TextElement.Foreground="{DynamicResource R.AccentText}">
          <Grid HorizontalAlignment="Center" VerticalAlignment="Center">{{icon:drivelock:20}}</Grid>
        </Border>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock x:Name="bitlocker_title" FontSize="17" FontWeight="{DynamicResource R.FontWeightTitle}" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="bitlocker_summary" Style="{StaticResource Txt.Muted}" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </DockPanel>
      <Button x:Name="bitlocker_copy" Grid.Column="1" VerticalAlignment="Center" Margin="16,0,0,0"
              ToolTip="Les clés cochées, ou toutes, colonnes séparées par des tabulations (à coller dans Excel)">
        <StackPanel Orientation="Horizontal">{{icon:copy}}<TextBlock Text="Copier" Margin="8,0,0,0"/></StackPanel>
      </Button>
      <StackPanel x:Name="caption_buttons" Grid.Column="2" Orientation="Horizontal" Margin="12,-12,0,-12"/>
    </Grid>
  </Border>
  <Border DockPanel.Dock="Bottom" Background="{DynamicResource R.Chrome}" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,1,0,0" Padding="16,12">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button x:Name="bitlocker_select_old" Content="Sélectionner les anciennes" ToolTip="Coche toutes les clés sauf la plus récente de chaque disque"/>
      <TextBlock x:Name="bitlocker_selection" Grid.Column="1" Style="{StaticResource Txt.Muted}" FontSize="12" Margin="14,0,14,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <Button x:Name="bitlocker_delete" Style="{StaticResource Btn.Danger}" IsEnabled="False" ToolTip="Supprimer de l'AD les clés cochées (Suppr)">
          <StackPanel Orientation="Horizontal">{{icon:trash}}<TextBlock x:Name="bitlocker_delete_label" Text="Supprimer…" Margin="8,0,0,0"/></StackPanel>
        </Button>
        <Button x:Name="dialog_cancel" Style="{StaticResource Btn.Primary}" MinWidth="90" Margin="8,0,0,0" IsDefault="True" IsCancel="True" Content="Fermer"/>
      </StackPanel>
    </Grid>
  </Border>
  <ScrollViewer x:Name="bitlocker_scroll" VerticalScrollBarVisibility="Auto">
    <ContentControl x:Name="bitlocker_body" Margin="16,14,16,4" Focusable="False"/>
  </ScrollViewer>
</DockPanel>
'@

function ConvertTo-BitLockerKeyId([string]$Text) {
    # A key ID as typed from BitLocker's recovery screen (6F1C2E7A, 6F1C2E7A-0B9D-…, with braces or spaces), as the
    # start of the one in AD's objects' names: upper case, hyphens where a GUID has them. $null when it isn't the start
    # of a key ID, or is shorter than the 8 characters the screen shows at least.
    $hex = ($Text -replace '[\s{}-]', '').ToUpperInvariant()
    if ($hex -notmatch '^[0-9A-F]{8,32}$') { return $null }
    $parts = foreach ($span in @(@(0, 8), @(8, 4), @(12, 4), @(16, 4), @(20, 12))) {
        if ($hex.Length -gt $span[0]) { $hex.Substring($span[0], [Math]::Min($span[1], $hex.Length - $span[0])) }
    }
    @($parts) -join '-'
}

function Get-BitLockerBodyXaml($State) {
    # The keys, a card per disk: its keys newest first, each with a box to tick, its date, a badge (the newest of the
    # disk, probably the one it uses, or an older one), its ID and its recovery password with a button to copy it.
    $x = { param($value) ConvertTo-XamlValue $value }
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add(@'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid Margin="2,0,2,12" TextElement.Foreground="{DynamicResource R.Muted}">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Margin="0,1,8,0" VerticalAlignment="Top">{{icon:info:14}}</Border>
    <TextBlock Grid.Column="1" FontSize="12" TextWrapping="Wrap" Text="La clé la plus récente de chaque disque est sans doute celle qu'il utilise. Supprimer une clé n'efface que sa copie dans l'AD."/>
  </Grid>
'@)
    if ($State.Notes) {
        $parts.Add(@"
  <Border Margin="0,0,0,12" Padding="12,9" CornerRadius="8" BorderThickness="1" Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}">
    <TextBlock x:Name="bitlocker_notes" FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource R.WarnText}" Text="$(& $x (ConvertTo-FrenchError ($State.Notes -join "`n")))"/>
  </Border>
"@)
    }
    if (-not $State.Rows.Count) {
        $parts.Add(@'
  <Border Style="{StaticResource Card}" Padding="16,22" Margin="0,0,0,12">
    <TextBlock Style="{StaticResource Txt.Muted}" HorizontalAlignment="Center" Text="Plus aucune clé BitLocker n'est enregistrée dans l'AD."/>
  </Border>
'@)
    }
    $several = @($State.Rows | ForEach-Object ComputerDN | Select-Object -Unique).Count -gt 1
    # The disks as Update-BitLockerStatus numbered them: a key without a volume is a card of its own.
    foreach ($disk in @($State.Rows | Group-Object { "$($_.ComputerDN)|$($_.DiskNumber)" })) {
        $first = $disk.Group[0]
        $title = if ($first.DiskCount -gt 1) { (Tr 'Disque {0}') -f $first.DiskNumber } else { Tr 'Disque' }
        if ($several) { $title = "$($first.ComputerName) · $title" }
        $count = if ($disk.Count -eq 1) { Tr '1 clé' } else { (Tr '{0} clés') -f $disk.Count }
        $volume = if ($first.VolumeId) {
            "<TextBlock Grid.Column=`"2`" Style=`"{StaticResource Txt.Faint}`" FontSize=`"12`" VerticalAlignment=`"Center`" Text=`"$(& $x ('Volume ' + $first.VolumeId.Split('-')[0].ToUpperInvariant()))`" ToolTip=`"$(& $x ((Tr 'Identifiant du volume : {0}') -f $first.VolumeId))`"/>"
        }
        else {
            "<TextBlock Grid.Column=`"2`" Style=`"{StaticResource Txt.Faint}`" FontSize=`"12`" VerticalAlignment=`"Center`" Text=`"$(& $x (Tr 'Volume inconnu'))`" ToolTip=`"$(& $x (Tr "L'AD n'indique pas le volume de cette clé : elle compte pour un disque à part, et Sélectionner les anciennes ne la coche pas."))`"/>"
        }
        $parts.Add(@"
  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
    <StackPanel>
      <Grid Margin="16,11,16,10">
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Border TextElement.Foreground="{DynamicResource R.Muted}" VerticalAlignment="Center">{{icon:harddrive}}</Border>
          <TextBlock Text="$(& $x $title)" FontWeight="{DynamicResource R.FontWeightStrong}" Margin="9,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Text="· $count" Style="{StaticResource Txt.Muted}" Margin="6,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        $volume
      </Grid>
"@)
        foreach ($row in $disk.Group) {
            $i = $State.Rows.IndexOf($row)
            # The card's last row follows its rounded corners, so a ticked row's color stays inside.
            $corners = if ($row -eq $disk.Group[-1]) { '0,0,7,7' } else { '0' }
            $badge = if ($row.Latest) {
                '<Border CornerRadius="5" Padding="7,1" Margin="10,0,0,0" VerticalAlignment="Center" Background="{DynamicResource R.Selection}"><TextBlock Text="La plus récente" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}" Foreground="{DynamicResource R.AccentText}"/></Border>'
            }
            else {
                '<Border CornerRadius="5" Padding="7,1" Margin="10,0,0,0" VerticalAlignment="Center" BorderThickness="1" Background="{DynamicResource R.Control}" BorderBrush="{DynamicResource R.Border}"><TextBlock Text="Ancienne" FontSize="11.5" Foreground="{DynamicResource R.Muted}"/></Border>'
            }
            # The key the last search looked for by its ID (ID de clé BitLocker).
            if ($State.Sought -and $row.KeyId.StartsWith($State.Sought, [System.StringComparison]::OrdinalIgnoreCase)) {
                $badge += '<Border CornerRadius="5" Padding="7,1" Margin="6,0,0,0" VerticalAlignment="Center" Background="{DynamicResource R.WarnBg}"><TextBlock Text="ID cherché" FontSize="11.5" FontWeight="{DynamicResource R.FontWeightStrong}" Foreground="{DynamicResource R.WarnText}"/></Border>'
            }
            $password = if ($row.Readable) {
                @"
          <Border Grid.Column="1" Style="{StaticResource Field}" Padding="10,6" Margin="16,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="$(& $x $row.Password)" FontFamily="Consolas" FontSize="13"/>
          </Border>
          <Button x:Name="bitlocker_copy_$i" Grid.Column="2" Style="{StaticResource Btn.Mini}" Margin="6,0,0,0" VerticalAlignment="Center"
                  ToolTip="Copier le mot de passe de récupération" AutomationProperties.Name="Copier le mot de passe de récupération">{{icon:copy:14}}</Button>
"@
            }
            else {
                '<TextBlock Grid.Column="1" Grid.ColumnSpan="2" Margin="16,0,32,0" VerticalAlignment="Center" FontStyle="Italic" Style="{StaticResource Txt.Muted}" Text="Mot de passe non lisible (droits insuffisants)"/>'
            }
            $parts.Add(@"
      <Border x:Name="bitlocker_row_$i" BorderBrush="{DynamicResource R.Border}" BorderThickness="0,1,0,0" CornerRadius="$corners" Padding="16,10" Background="Transparent">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <CheckBox x:Name="bitlocker_key_$i" VerticalAlignment="Center" VerticalContentAlignment="Center" AutomationProperties.Name="$(& $x $row.Summary)">
            <!-- The recovery password takes its full width: at a large text size, the badges go under the date and the ID
                 trims, whole in its tooltip, rather than being cut. -->
            <StackPanel Margin="4,0,0,0">
              <WrapPanel>
                <TextBlock Text="$(& $x $row.DateLabel)" FontWeight="{DynamicResource R.FontWeightStrong}" VerticalAlignment="Center" Margin="0,0,0,2"/>
                $badge
              </WrapPanel>
              <TextBlock Style="{StaticResource Txt.Muted}" FontSize="12" Margin="0,1,0,0" TextTrimming="CharacterEllipsis" ToolTip="$(& $x $row.KeyId)"><Run Text="ID "/><Run Text="$(& $x $row.KeyId)" FontFamily="Consolas"/></TextBlock>
            </StackPanel>
          </CheckBox>
$password
        </Grid>
      </Border>
"@)
        }
        $parts.Add('    </StackPanel>')
        $parts.Add('  </Border>')
    }
    $parts.Add('</StackPanel>')
    Expand-Icon ($parts -join "`n")
}

function Update-BitLockerStatus($Rows) {
    # The newest key of each disk (each volume) is probably the one the disk uses; the others are older ones. A key
    # whose volume AD doesn't say is a disk of its own: keys like that may be those of different disks (C: and D:, the
    # old ones of Windows Vista, some saved by a script), and one taken for another's older key would be ticked by
    # Sélectionner les anciennes, though its disk still uses it. So is a key whose name isn't a date (When is
    # MinValue): nothing says it's older than the others, so it's never one to tick. Each computer's disks are
    # numbered newest first, those keys last.
    foreach ($computer in @($Rows | Group-Object ComputerDN)) {
        $disks = @($computer.Group | Group-Object { if ($_.VolumeId -and $_.When -ne [datetimeoffset]::MinValue) { $_.VolumeId } else { $_.DistinguishedName } } |
            Sort-Object { ($_.Group | Sort-Object When -Descending)[0].When } -Descending)
        for ($n = 0; $n -lt $disks.Count; $n++) {
            $newest = $disks[$n].Group | Sort-Object When -Descending | Select-Object -First 1
            foreach ($row in $disks[$n].Group) {
                $row.Latest = $row -eq $newest
                $row.DiskNumber = $n + 1
                $row.DiskCount = $disks.Count
                $status = if ($row.Latest) { Tr 'La plus récente' } else { Tr 'Ancienne' }
                $row.Summary = "$($row.ComputerName) | $($row.DateLabel) | $status | $($row.KeyId) | $($row.Password)"
            }
        }
    }
    # Shown in that order: by computer, then disk, newest key first.
    $order = @($Rows | Sort-Object ComputerOrder, DiskNumber, @{ Expression = 'When'; Descending = $true })
    $Rows.Clear()
    foreach ($row in $order) { $Rows.Add($row) }
}

function Update-BitLockerBody($State) {
    # Builds the cards again (after a deletion), and wires their boxes and copy buttons.
    Update-BitLockerStatus $State.Rows
    $body = [System.Windows.Markup.XamlReader]::Parse((Get-BitLockerBodyXaml $State))
    $State.Body.Content = $body
    for ($i = 0; $i -lt $State.Rows.Count; $i++) {
        $box = $body.FindName("bitlocker_key_$i")
        $box.Tag = $State.Rows[$i]
        $box.IsChecked = $State.Rows[$i].Selected
        $box.Add_Checked({ param($control) Set-BitLockerKeySelected $control $true })
        $box.Add_Unchecked({ param($control) Set-BitLockerKeySelected $control $false })
        $copy = $body.FindName("bitlocker_copy_$i")
        if ($copy) {
            $copy.CommandParameter = $State.Rows[$i]
            $copy.Add_Click({
                param($button)
                $key = $button.CommandParameter
                $copied = Set-SecretClipboard $key.Password
                Show-CopyFeedback $button $copied
                $state = [System.Windows.Window]::GetWindow($button).Tag
                $id = $key.KeyId.Split('-')[0]
                $state.Selection.Text = if ($copied) { (Tr 'Mot de passe de la clé {0} copié') -f $id } else { (Tr 'Clé {0} non copiée : presse-papiers occupé par un autre programme') -f $id }
            })
        }
        Set-BitLockerRowLook $body $i $State.Rows[$i].Selected
    }
    $names = $State.Names
    $State.Title.Text = if ($names.Count -eq 1) { $names[0] } else { (Tr '{0} ordinateurs') -f $names.Count }
    $diskCount = @($State.Rows | Group-Object { "$($_.ComputerDN)|$($_.DiskNumber)" }).Count
    $keys = if ($State.Rows.Count -eq 1) { Tr '1 clé' } else { (Tr '{0} clés') -f $State.Rows.Count }
    $disks = if ($diskCount -eq 1) { Tr '1 disque' } else { (Tr '{0} disques') -f $diskCount }
    $State.Summary.Text = if ($State.Rows.Count) { (Tr "Clés de récupération BitLocker enregistrées dans l'AD · {0} sur {1}") -f $keys, $disks } else { Tr "Clés de récupération BitLocker enregistrées dans l'AD" }
    Update-BitLockerFooter $State
}

function Set-BitLockerRowLook($Body, [int]$Index, [bool]$Selected) {
    # A ticked key's row takes the selection's color.
    $row = $Body.FindName("bitlocker_row_$Index")
    if ($Selected) { $row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'R.Selection') }
    else { $row.Background = [System.Windows.Media.Brushes]::Transparent }
}

function Set-BitLockerKeySelected($Box, [bool]$Selected) {
    $state = [System.Windows.Window]::GetWindow($Box).Tag
    $Box.Tag.Selected = $Selected
    Set-BitLockerRowLook $state.Body.Content $state.Rows.IndexOf($Box.Tag) $Selected
    Update-BitLockerFooter $state
}

function Update-BitLockerFooter($State) {
    # The buttons and the count, as the ticked keys say. Supprimer waits while keys are being deleted.
    $count = @($State.Rows | Where-Object Selected).Count
    $State.Delete.IsEnabled = $count -gt 0 -and -not $State['Removing']
    $State.DeleteLabel.Text = switch ($count) { 0 { Tr 'Supprimer…' } 1 { Tr 'Supprimer la clé…' } default { (Tr 'Supprimer {0} clés…') -f $count } }
    $State.Selection.Text = switch ($count) { 0 { Tr 'Aucune clé cochée' } 1 { Tr '1 clé cochée' } default { (Tr '{0} clés cochées') -f $count } }
    $State.SelectOld.IsEnabled = [bool]@($State.Rows | Where-Object { -not $_.Latest }).Count
}

function Remove-BitLockerKey($State) {
    # Confirms, then deletes the ticked keys from AD, one at a time; a key that can't be deleted stays listed.
    $keys = @($State.Rows | Where-Object Selected)
    if (-not $keys.Count -or $State['Removing']) { return }
    $question = if ($keys.Count -eq 1) { Tr "Supprimer cette clé BitLocker de l'AD ?" } else { (Tr "Supprimer ces {0} clés BitLocker de l'AD ?") -f $keys.Count }
    $message = Tr "Seule la copie enregistrée dans l'AD est supprimée : le disque garde sa clé. Si elle protège encore un disque, elle ne pourra plus être retrouvée ici le jour où il faudra le déverrouiller. Cette action est définitive."
    $readAs = "$question`n`n$message"
    # A disk's newest key among them: said in an amber strip, as it's probably the one the disk uses.
    $newest = @($keys | Where-Object Latest | ForEach-Object ComputerName | Select-Object -Unique)
    $warning = $null
    if ($newest.Count) {
        $text = (Tr "⚠ La sélection comprend la clé la plus récente d'un disque de {0} : c'est probablement celle qu'il utilise.") -f ($newest -join ', ')
        $readAs += "`n`n$text"
        $warning = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Padding="12,9" CornerRadius="8" BorderThickness="1" Background="{DynamicResource R.WarnBg}" BorderBrush="{DynamicResource R.WarnBorder}">
  <TextBlock FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource R.WarnText}" Text="$([System.Security.SecurityElement]::Escape($text))"/>
</Border>
"@))
    }
    $details = ($keys | ForEach-Object { "$($_.ComputerName)  $($_.DateLabel)  ID $($_.KeyId)`n  $($_.Password)" }) -join "`n`n"
    Show-Dialog -Title (Tr 'Supprimer des clés BitLocker') -Heading $question -Message $message -MessageName $readAs -Icon 'trash' -Tone 'danger' -Content $warning `
        -Details $details -DetailsLabel (Tr 'Clés supprimées (à copier avant au besoin)') -SecretDetails -OkText (Tr 'Supprimer') -CancelIsDefault -Owner $State.Window -State @{ Keys = $keys; Dialog = $State } -OnOk {
        param($confirm)
        Start-BitLockerRemoval $confirm.Dialog $confirm.Keys
    }
}

function Start-BitLockerRemoval($State, $Keys) {
    # The keys deleted in the background (Remove-BitLockerKeyList, Start-ADWrite): the window usable meanwhile, its
    # pointer saying it runs, Supprimer waiting (Update-BitLockerFooter). The keys' passwords stay on this thread: the
    # runspace gets each key's DN and domain only. Then Complete-BitLockerRemoval.
    $Keys = @($Keys)
    $State.Removing = $true
    Update-BitLockerFooter $State
    try {
        $started = Start-ADWrite -Keys @($Keys | ForEach-Object { "BitLocker|$($_.Domain)|$($_.DistinguishedName)" }) -Command 'Remove-BitLockerKeyList' `
            -Arguments @(, @($Keys | ForEach-Object { [pscustomobject]@{ Domain = [string]$_.Domain; DistinguishedName = [string]$_.DistinguishedName } })) `
            -Count $Keys.Count -Window $State.Window -Context @{ State = $State; Keys = $Keys } -OnDone {
            param($write, $outcome)
            Complete-BitLockerRemoval $write.State $write.Keys $outcome
        }
    }
    catch { $started = $false; Write-Host ((Tr 'Clés BitLocker non supprimées : {0}') -f $_) }
    if (-not $started) {
        $State.Removing = $false
        Update-BitLockerFooter $State
    }
}

function Remove-BitLockerKeyList($Keys) {
    # On a search runspace: each key deleted from AD, one at a time, in its domain. Each one's Problem as it goes
    # (Add-WriteProgress, by index), $null once deleted.
    $Keys = @($Keys)
    for ($i = 0; $i -lt $Keys.Count; $i++) {
        $key = $Keys[$i]
        $problem = try {
            Remove-ADObject -Server $key.Domain -Identity $key.DistinguishedName -Confirm:$false -ErrorAction Stop
            $null
        }
        catch { $_.Exception.Message }
        Add-WriteProgress $i @{ Problem = $problem }
    }
}

function Complete-BitLockerRemoval($State, $Keys, $Outcome) {
    # The keys deleted leave the list; one that can't be deleted stays listed, as does one perhaps deleted (the DC
    # didn't answer in time: Get-WriteAnswer), which its line says to check. Then the report, over the window, or the
    # main one once it has closed.
    $State.Removing = $false
    $report = for ($i = 0; $i -lt $Keys.Count; $i++) {
        $key = $Keys[$i]
        $shortId = "$($key.KeyId)".Split('-')[0]
        $answer = Get-WriteAnswer $Outcome $i
        if ($answer.Unsure) { (Tr '⚠ {0} : clé {1} peut-être supprimée ({2}), vérifiez') -f $key.ComputerName, $shortId, $Outcome.Problem }
        elseif ($answer.Problem) { (Tr '✖ {0} : clé {1} non supprimée ({2})') -f $key.ComputerName, $shortId, $answer.Problem }
        else {
            $State.Rows.Remove($key) | Out-Null
            (Tr '✔ {0} : clé {1}') -f $key.ComputerName, $shortId
        }
    }
    $open = $State.Window.IsVisible
    if ($open) { Update-BitLockerBody $State }
    Show-ActionReport @($report) (Tr 'Supprimer des clés BitLocker') -Owner $(if ($open) { $State.Window }) -Many (Tr '✔ {0} clés') -Outcome (Tr 'Clé supprimée'), (Tr 'Clés supprimées')
}

function Show-BitLockerDialog($Computers, $Owner, $Icon) {
    # Reads every computer's keys in the background, then the window.
    Start-WindowRead -Kind 'BitLocker' -Command 'Read-BitLockerRow' -Arguments @(, @(ConvertTo-ReadComputer $Computers)) -Functions 'Get-BitLockerKey' -Timeout (Get-ReadTimeout @($Computers).Count) `
        -Context @{ Computers = $Computers; Owner = $Owner; Icon = $Icon } -OnDone {
        param($context, $read, $problem)
        if ($problem -or -not $read) {
            $reason = if ($problem) { $problem } else { Tr 'AD n''a rien renvoyé' }
            $failed = @($context.Computers | ForEach-Object { (Tr '{0} : clés BitLocker non lues ({1})') -f $_.ComputerName, $reason })
            $read = @{ Rows = [System.Collections.Generic.List[object]]::new(); Missing = @(); Failed = $failed }
        }
        Show-BitLockerWindow $context.Computers $read $context.Owner $context.Icon
    }
}

function Read-BitLockerRow($Computers) {
    # On a search runspace: the keys of every computer as the window's rows; Missing, the names of the computers
    # without a key; Failed, a line for each whose keys couldn't be read.
    $rows = [System.Collections.Generic.List[object]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    $computerOrder = 0
    foreach ($computer in $Computers) {
        $computerOrder++
        try {
            $keys = @(Get-BitLockerKey $computer.DistinguishedName $computer.Domain)
            if (-not $keys.Count) {
                $missing.Add($computer.ComputerName)
                continue
            }
            foreach ($key in $keys) {
                $rows.Add([pscustomobject]@{
                    ComputerName      = $computer.ComputerName
                    ComputerDN        = $computer.DistinguishedName
                    ComputerOrder     = $computerOrder
                    Domain            = $computer.Domain
                    When              = $key.When
                    Date              = $key.Date
                    DateLabel         = $key.DateLabel
                    KeyId             = $key.KeyId
                    VolumeId          = $key.VolumeId
                    Readable          = [bool]$key.RecoveryPassword
                    Password          = if ($key.RecoveryPassword) { $key.RecoveryPassword } else { Tr 'non lisible (droits insuffisants)' }
                    DistinguishedName = $key.DistinguishedName
                    Latest            = $false
                    DiskNumber        = 0
                    DiskCount         = 0
                    Summary           = ''
                    Selected          = $false
                })
            }
        }
        catch {
            $failed.Add(((Tr '{0} : clés BitLocker non lues ({1})') -f $computer.ComputerName, $_.Exception.Message))
        }
    }
    @{ Rows = $rows; Missing = @($missing); Failed = @($failed) }
}

function Show-BitLockerWindow($Computers, $Read, $Owner, $Icon) {
    # The keys Read-BitLockerRow read. Without any key to list, no window: a toast says there's none, or, when some
    # couldn't be read, the report of an action that failed says which and why.
    $rows = $Read.Rows
    $missing = @($Read.Missing)
    if (-not $rows.Count) {
        $lines = @($missing | ForEach-Object { (Tr '{0} : aucune clé BitLocker') -f $_ }) + @($Read.Failed | ForEach-Object { "✖ $_" })
        Show-ActionReport $lines (Tr 'Clés BitLocker') -Owner $Owner -Many (Tr 'Aucune clé BitLocker pour {0} ordinateurs')
        return
    }

    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-Icon $script:BitLockerDialogXaml))
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = Tr 'Clés BitLocker'
    $dialog.Icon = $Icon
    $dialog.Owner = $Owner
    $dialog.Width = 900
    $dialog.MinWidth = 760
    $dialog.SizeToContent = 'Height'
    $dialog.ShowInTaskbar = $false
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'R.Bg')
    $dialog.Content = $root
    Set-WindowChrome $dialog -TitleBar $root.FindName('title_bar') -ButtonHost $root.FindName('caption_buttons')
    Register-WindowHeightCap $dialog

    # Above the keys: the computers without one on a single line, then each whose keys couldn't be read.
    $notes = @(if ($missing.Count) { (Tr 'Clé BitLocker manquante : {0}') -f ($missing -join ', ') }) + @($Read.Failed)
    $state = @{
        Window = $dialog; Rows = $rows; Notes = $notes; Names = @($Computers | ForEach-Object ComputerName); Sought = $script:BitLockerKeySought
        Body = $root.FindName('bitlocker_body'); Title = $root.FindName('bitlocker_title'); Summary = $root.FindName('bitlocker_summary')
        Selection = $root.FindName('bitlocker_selection'); Delete = $root.FindName('bitlocker_delete')
        DeleteLabel = $root.FindName('bitlocker_delete_label'); SelectOld = $root.FindName('bitlocker_select_old')
    }
    $dialog.Tag = $state
    Update-BitLockerBody $state

    $state.SelectOld.Add_Click({
        param($button)
        # Ticks the old keys and only them: each box's Checked or Unchecked updates its row.
        $state = [System.Windows.Window]::GetWindow($button).Tag
        for ($i = 0; $i -lt $state.Rows.Count; $i++) {
            $state.Body.Content.FindName("bitlocker_key_$i").IsChecked = -not $state.Rows[$i].Latest
        }
    })
    $state.Delete.Add_Click({ param($button) Remove-BitLockerKey ([System.Windows.Window]::GetWindow($button).Tag) })
    $root.FindName('bitlocker_copy').Add_Click({
        param($button)
        # The keys ticked, or all of them, with a header line, separated by tabs: pasted in Excel, each value lands in
        # its column, as text (Format-RowLine).
        $state = [System.Windows.Window]::GetWindow($button).Tag
        $keys = @($state.Rows | Where-Object Selected)
        if (-not $keys.Count) { $keys = @($state.Rows) }
        $header = (Tr 'Ordinateur'), (Tr 'Disque'), 'Date', (Tr 'Statut'), (Tr 'ID de la clé'), (Tr 'Mot de passe de récupération')
        $lines = @($header -join "`t") + @(foreach ($key in $keys) {
            $status = if ($key.Latest) { Tr 'La plus récente' } else { Tr 'Ancienne' }
            Format-RowLine @($key.ComputerName, $key.DiskNumber, $key.Date, $status, $key.KeyId, $key.Password)
        })
        $copied = Set-SecretClipboard ($lines -join [Environment]::NewLine)
        Show-CopyFeedback $button $copied
        $state.Selection.Text = if (-not $copied) { Tr 'Non copié : le presse-papiers est occupé par un autre programme' }
                                elseif ($keys.Count -eq 1) { Tr '1 clé copiée' } else { (Tr '{0} clés copiées') -f $keys.Count }
    })
    # Suppr deletes the ticked keys, as it removes the selected computers in the main window.
    $dialog.Add_PreviewKeyDown({
        param($window, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Delete -and $window.Tag.Delete.IsEnabled) {
            $e.Handled = $true
            Remove-BitLockerKey $window.Tag
        }
    })

    $script:search.Dialogs++
    try { $null = $dialog.ShowDialog() }
    finally { $script:search.Dialogs-- }
}
