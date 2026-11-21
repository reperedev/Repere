# Selecting a cell's text in the results grids (Ordinateurs, Utilisateurs, Groupes), to copy part of it. A TextBlock
# can't be selected, and a text box in every cell would cost the grids their speed and take their clicks: a press on a
# row, its double-click, its right-click and a drag across rows stay the grid's. Instead, one read-only text box lies
# over the cell's text once the mouse drags sideways on it, in the row it pressed: it holds the selection, Ctrl+C copies
# it, and it goes when anything else happens (a click elsewhere, Échap, a scroll, another selection). While it's there
# the keys are the text box's, so a Suppr meant for the text never asks to remove the computer.
# Dot-sourced by the main script after Theme.ps1; each grid calls Initialize-GridText once it's built.

# Each grid's state, by its name: its Grid, its Box and the Press being watched; the Block the box covers and the Anchor
# of the selection while it's there; Dragging while the mouse selects.
$script:GridTexts = @{}

function Get-GridPress($Element) {
    # The TextBlock and the row under a press, or nothing outside a row. Its source can be a Run, which isn't a Visual.
    $block = $null
    while ($Element -and $Element -isnot [System.Windows.Controls.Primitives.DataGridRowsPresenter]) {
        if ($Element -is [System.Windows.Controls.DataGridRow]) {
            if ($block) { return @{ Block = $block; Row = $Element } }
            return
        }
        if (-not $block -and $Element -is [System.Windows.Controls.TextBlock]) { $block = $Element }
        $Element = if ($Element -is [System.Windows.Media.Visual]) { [System.Windows.Media.VisualTreeHelper]::GetParent($Element) }
                   else { [System.Windows.LogicalTreeHelper]::GetParent($Element) }
    }
}

function Get-GridTextIndex($Box, [System.Windows.Point]$Point) {
    # The gap between two characters nearest a point: GetCharacterIndexFromPoint gives the character under it, which
    # could never select the last one.
    $index = $Box.GetCharacterIndexFromPoint($Point, $true)
    if ($index -lt 0) { return 0 }
    $left = $Box.GetRectFromCharacterIndex($index).Left
    $right = $Box.GetRectFromCharacterIndex($index, $true).Left
    if ($Point.X -gt ($left + $right) / 2) { $index + 1 } else { $index }
}

function Open-GridText($State, $Press) {
    # The box exactly over the text, which it replaces while it's there, then the mouse is its own.
    $box = $State.Box
    $block = $Press.Block
    foreach ($property in 'FontFamily', 'FontSize', 'FontWeight', 'FontStyle', 'FontStretch', 'Foreground') { $box.$property = $block.$property }
    $box.Text = $block.Text
    $box.Visibility = 'Visible'
    $box.Width = $block.ActualWidth
    $box.Height = $block.ActualHeight
    $layer = $box.Parent
    $corner = $block.TranslatePoint([System.Windows.Point]::new(0, 0), $layer)
    [System.Windows.Controls.Canvas]::SetLeft($box, $corner.X)
    [System.Windows.Controls.Canvas]::SetTop($box, $corner.Y)
    $box.UpdateLayout()
    # The text box starts its text a little after its edge: moved back by as much, and wider, for the text not to jump.
    $inset = $box.GetRectFromCharacterIndex(0).Left
    $box.Width = $block.ActualWidth + 2 * $inset
    [System.Windows.Controls.Canvas]::SetLeft($box, $corner.X - $inset)
    $box.UpdateLayout()
    $block.Opacity = 0
    $State.Block = $block
    $State.Anchor = Get-GridTextIndex $box ($block.TranslatePoint($Press.Point, $box))
    $State.Dragging = $true
    $null = $box.Focus()
    $null = $box.CaptureMouse()
}

function Close-GridText($State) {
    if (-not $State.Block) { return }
    $State.Block.ClearValue([System.Windows.UIElement]::OpacityProperty)
    $State.Block = $null
    $State.Dragging = $false
    $box = $State.Box
    $box.ReleaseMouseCapture()
    $box.Visibility = 'Collapsed'
    $box.Clear()
}

function Update-GridTextDrag($State, $Point) {
    # From where the press began to the mouse. Text cut short by its column scrolls as the mouse goes past its edge.
    $box = $State.Box
    if ($Point.X -gt $box.ActualWidth) { $box.ScrollToHorizontalOffset($box.HorizontalOffset + 8) }
    elseif ($Point.X -lt 0) { $box.ScrollToHorizontalOffset([Math]::Max(0, $box.HorizontalOffset - 8)) }
    $index = Get-GridTextIndex $box $Point
    $box.Select([Math]::Min($State.Anchor, $index), [Math]::Abs($index - $State.Anchor))
}

function Initialize-GridText($Grid) {
    # The box, on a layer over the grid: without a background, the layer lets the mouse through to the grid.
    $box = [System.Windows.Controls.TextBox]::new()
    $box.Name = "$($Grid.Name)_text"
    $box.IsReadOnly = $true
    $box.IsInactiveSelectionHighlightEnabled = $true
    $box.Visibility = 'Collapsed'
    $box.AcceptsReturn = $false
    $box.VerticalContentAlignment = 'Center'
    $layer = [System.Windows.Controls.Canvas]::new()
    $layer.ClipToBounds = $true
    $layer.Margin = $Grid.Margin
    $null = $layer.Children.Add($box)
    $null = $Grid.Parent.Children.Add($layer)
    $box.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'Text.Bare')
    $box.Padding = [System.Windows.Thickness]::new(0)
    $state = @{ Grid = $Grid; Box = $box; Press = $null; Block = $null; Anchor = 0; Dragging = $false }
    $box.Tag = $state
    $script:GridTexts[$Grid.Name] = $state

    # Its own menu, in Repère's language: the grid's actions aren't about this text.
    $menu = [System.Windows.Controls.ContextMenu]::new()
    $copy = [System.Windows.Controls.MenuItem]::new()
    $copy.Header = Tr 'Copier'
    $copy.InputGestureText = 'Ctrl+C'
    $copy.Tag = $box
    $copy.Add_Click({ param($item) $item.Tag.Copy() })
    $null = $menu.Items.Add($copy)
    $box.ContextMenu = $menu
    $box.Add_ContextMenuOpening({ param($control) $control.ContextMenu.Items[0].IsEnabled = $control.SelectionLength -gt 0 })

    $Grid.Add_PreviewMouseLeftButtonDown({
        param($grid, $e)
        $state = $script:GridTexts[$grid.Name]
        Close-GridText $state
        $state.Press = $null
        if ($e.ClickCount -ne 1 -or [System.Windows.Input.Keyboard]::Modifiers -ne [System.Windows.Input.ModifierKeys]::None) { return }
        $press = Get-GridPress $e.OriginalSource
        if (-not $press -or -not $press.Block.Text) { return }
        $press.Point = $e.GetPosition($press.Block)
        $state.Press = $press
    })
    $Grid.Add_PreviewMouseMove({
        param($grid, $e)
        $state = $script:GridTexts[$grid.Name]
        $press = $state.Press
        if (-not $press) { return }
        # Out of the row first: the grid's drag across rows.
        $inRow = $e.GetPosition($press.Row).Y
        if ($e.LeftButton -ne 'Pressed' -or $inRow -lt 0 -or $inRow -gt $press.Row.ActualHeight) { $state.Press = $null; return }
        $moved = [Math]::Abs($e.GetPosition($press.Block).X - $press.Point.X)
        if ($moved -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance) { return }
        $state.Press = $null
        # A press in a selection of several rows has just made it one: the others go with it.
        if (-not $press.Row.IsSelected -or $grid.SelectedItems.Count -ne 1) { return }
        Open-GridText $state $press
    })
    $box.Add_PreviewMouseMove({
        param($control, $e)
        $state = $control.Tag
        if (-not $state.Dragging) { return }
        Update-GridTextDrag $state $e.GetPosition($control)
        $e.Handled = $true
    })
    $box.Add_PreviewMouseLeftButtonUp({
        param($control, $e)
        $state = $control.Tag
        if (-not $state.Dragging) { return }
        $state.Dragging = $false
        $control.ReleaseMouseCapture()
        $e.Handled = $true
        # A drag that ended where it began selected nothing: the keys go back to the grid.
        if (-not $control.SelectionLength) {
            Close-GridText $state
            $null = $state.Grid.Focus()
        }
    })
    $box.Add_PreviewKeyDown({
        param($control, $e)
        if ($e.Key -ne 'Escape') { return }
        $state = $control.Tag
        Close-GridText $state
        $null = $state.Grid.Focus()
        $e.Handled = $true
    })
    # No NewFocus: another window was chosen, and the text stays selected for the return. Its menu takes the focus too.
    $box.Add_LostKeyboardFocus({
        param($control, $e)
        if ($e.NewFocus -and -not $control.ContextMenu.IsOpen) { Close-GridText $control.Tag }
    })
    $Grid.Add_SelectionChanged({ param($grid) Close-GridText $script:GridTexts[$grid.Name] })
    $Grid.Add_SizeChanged({ param($grid) Close-GridText $script:GridTexts[$grid.Name] })
    $Grid.AddHandler([System.Windows.Controls.ScrollViewer]::ScrollChangedEvent, [System.Windows.Controls.ScrollChangedEventHandler]{
        param($grid)
        Close-GridText $script:GridTexts[$grid.Name]
    })
}
