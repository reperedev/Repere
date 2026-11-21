# The splash: Repère's logo and a moving bar, shown as soon as PowerShell has loaded WPF, a second or so after the
# double-click, while the main window is made: two seconds more, up to fifteen the first time after Windows
# starts, when nothing is in memory yet. It shows that Repère is coming, so a second double-click doesn't start a
# second Repère. Dot-sourced by the main script.
#
# On a thread of its own, a runspace's: the main window's thread is busy until that window shows, so a splash on it
# wouldn't be drawn again, and Windows would show it as not responding after five seconds. That runspace has no
# commands (an empty InitialSessionState, opened in a few milliseconds), only .NET, and nothing crosses between the two
# threads but $State, a synchronized hashtable. It never stops Repère: without it, the main window shows as before.
#
# A bare HwndSource, not a Window: Repère's handlers for every Window (Theme.ps1, Register-UiText) would run for a Window
# of this thread too, on the main runspace, where its objects can't be touched. It never takes the focus (a window
# that can't be activated, without a taskbar button), so the main window and Repère's dialogs get it as they do
# without it. It can be dragged out of the way, though, by any part of it.

$script:Splash = $null

# Run on the splash's runspace. $Name is the name shown and $Title its window's, for UI Automation (not the main
# window's, which the UI tests find it by); $AppearancePath is apparence.json.
$script:SplashScript = {
    param($State, [string]$Name, [string]$Title, [string]$AppearancePath, [string]$LogoPath)
    try {
        # An error on this thread closes the splash, and only it: unhandled, it would stop Repère.
        $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $dispatcher.add_UnhandledException({
            param($splashDispatcher, $failure)
            $failure.Handled = $true
            $State.Error = "$($failure.Exception)"
            $null = $splashDispatcher.BeginInvokeShutdown('Normal')
        })

        # The Windows calls the splash needs, defined with Reflection.Emit as Taskbar.ps1 does (Add-Type would compile
        # them, a quarter to half a second): finding the screen it opens on, placing and showing the window without
        # activating it, moving it when it's dragged, and rounding its corners on Windows 11. Points go as arrays of two
        # ints, rectangles of four, and MONITORINFO of ten, rather than as structures this assembly would have to define.
        $assembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([System.Reflection.AssemblyName]::new('RepereSplash'), 'Run')
        $nativeType = $assembly.DefineDynamicModule('RepereSplash').DefineType('RepereSplash.Native', 'Public, Class, Abstract, Sealed')
        foreach ($call in @(@('user32.dll', 'GetCursorPos', [int], @(, [int[]])),
                            @('user32.dll', 'MonitorFromRect', [IntPtr], @([int[]], [uint32])),
                            @('user32.dll', 'GetMonitorInfo', [int], @([IntPtr], [int[]])),
                            @('user32.dll', 'SetWindowPos', [int], @([IntPtr], [IntPtr], [int], [int], [int], [int], [uint32])),
                            @('user32.dll', 'ReleaseCapture', [int], [type[]]::new(0)),
                            @('user32.dll', 'SendMessage', [int], @([IntPtr], [int], [IntPtr], [IntPtr])),
                            @('user32.dll', 'AllowSetForegroundWindow', [int], @(, [int])),
                            @('user32.dll', 'SetForegroundWindow', [int], @(, [IntPtr])),
                            @('dwmapi.dll', 'DwmSetWindowAttribute', [int], @([IntPtr], [int], [int].MakeByRefType(), [int])))) {
            $method = $nativeType.DefinePInvokeMethod($call[1], $call[0], 'Public, Static, PinvokeImpl', 'Standard', $call[2], [type[]]$call[3], 'Winapi', 'Unicode')
            $method.SetImplementationFlags('PreserveSig')
        }
        $native = $nativeType.CreateType()
        # Where the mouse pointer is as Repère is launched, in pixels: the screen the splash and the main window open on
        # (Get-RepereLaunchCursor), the one just used to launch it.
        $cursor = [int[]]::new(2)
        if ($native::GetCursorPos($cursor) -ne 0) { $State.Cursor = $cursor }

        # Light or dark, as the main window will be: apparence.json's mode (Read-Appearance), Windows's for apps when it's
        # Système (Get-ThemeVariant). Read with a regex, without ConvertFrom-Json, which this runspace doesn't have: only
        # Clair and Sombre matter.
        $saved = try { [System.IO.File]::ReadAllText($AppearancePath) } catch { '' }
        $dark = if ($saved -match '"Theme"\s*:\s*"(Clair|Sombre)"') { $Matches[1] -eq 'Sombre' }
                else { [Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 1) -eq 0 }
        # The colors of Repère's own theme (Theme.ps1's RepereLight and RepereDark palettes, and its accents), the logo's,
        # whatever theme the main window has; Windows's own in high contrast.
        $brush = { param([int]$Rgb) $value = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb($Rgb -shr 16, ($Rgb -shr 8) -band 255, $Rgb -band 255)); $value.Freeze(); $value }
        $colors = if ([System.Windows.SystemParameters]::HighContrast) {
            @{ Surface = [System.Windows.SystemColors]::WindowBrush; Border = [System.Windows.SystemColors]::WindowTextBrush; Text = [System.Windows.SystemColors]::WindowTextBrush
               Track = [System.Windows.SystemColors]::GrayTextBrush; Accent = [System.Windows.SystemColors]::HighlightBrush }
        }
        elseif ($dark) { @{ Surface = & $brush 0x241E2C; Border = & $brush 0x3B3247; Text = & $brush 0xEEEAF3; Track = & $brush 0x3B3247; Accent = & $brush 0x7553FF } }
        else { @{ Surface = & $brush 0xFFFFFF; Border = & $brush 0xDED7E8; Text = & $brush 0x241D2D; Track = & $brush 0xEAE5F0; Accent = & $brush 0x6A48F2 } }

        # Each element with a style of its own, an empty one: none of the application's (the main thread's) is looked up
        # from this thread.
        $element = { param([type]$Type) $value = $Type::new(); $value.Style = [System.Windows.Style]::new($Type); $value }
        # The logo (compass.png) read at three times its size, sharp up to 300 % scaling, rather than whole (1024 pixels).
        $logo = & $element ([System.Windows.Controls.Image])
        $logo.Width = 64
        $logo.Height = 64
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($logo, 'HighQuality')
        $image = [System.Windows.Media.Imaging.BitmapImage]::new()
        $image.BeginInit()
        $image.UriSource = [Uri]$LogoPath
        $image.DecodePixelWidth = 192
        # Read whole as it loads: otherwise WPF keeps the file open, and an update can't replace it.
        $image.CacheOption = 'OnLoad'
        $image.EndInit()
        $image.Freeze()
        $logo.Source = $image
        $label = & $element ([System.Windows.Controls.TextBlock])
        $label.Text = $Name
        $label.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
        $label.FontSize = 20
        $label.FontWeight = [System.Windows.FontWeights]::SemiBold
        $label.Foreground = $colors.Text
        $label.HorizontalAlignment = 'Center'
        $label.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
        # The bar: a third of its track, crossing it again and again, at 30 frames a second (half WPF's usual), which is
        # enough for it and leaves the processor to the main window.
        $track = & $element ([System.Windows.Controls.Border])
        $track.Width = 120
        $track.Height = 4
        $track.Background = $colors.Track
        $track.Clip = [System.Windows.Media.RectangleGeometry]::new([System.Windows.Rect]::new(0, 0, 120, 4), 2, 2)
        $track.Margin = [System.Windows.Thickness]::new(0, 18, 0, 0)
        $bar = & $element ([System.Windows.Controls.Border])
        $bar.Width = 40
        $bar.CornerRadius = [System.Windows.CornerRadius]::new(2)
        $bar.Background = $colors.Accent
        $bar.HorizontalAlignment = 'Left'
        $shift = [System.Windows.Media.TranslateTransform]::new(-40, 0)
        $bar.RenderTransform = $shift
        $track.Child = $bar
        $move = [System.Windows.Media.Animation.DoubleAnimation]::new(-40, 120, [System.Windows.Duration]::new([timespan]::FromMilliseconds(1300)))
        $move.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $move.EasingFunction = [System.Windows.Media.Animation.SineEase]@{ EasingMode = 'EaseInOut' }
        [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($move, 30)
        # Still, in the middle, when Windows's animations are turned off (Accessibilité › Effets visuels).
        if ([System.Windows.SystemParameters]::ClientAreaAnimation) { $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $move) }
        else { $shift.X = 40 }
        $panel = & $element ([System.Windows.Controls.StackPanel])
        $panel.HorizontalAlignment = 'Center'
        $panel.VerticalAlignment = 'Center'
        foreach ($child in $logo, $label, $track) { $null = $panel.Children.Add($child) }
        # The card, edge to edge: Windows 11 draws its own border over the edge, and its shadow (CS_DROPSHADOW).
        $card = & $element ([System.Windows.Controls.Border])
        $card.Background = $colors.Surface
        $card.BorderBrush = $colors.Border
        $card.BorderThickness = [System.Windows.Thickness]::new(1)
        $card.Cursor = [System.Windows.Input.Cursors]::AppStarting
        $card.Child = $panel
        # Moved by dragging it anywhere, as by a title bar (WM_NCLBUTTONDOWN on HTCAPTION, which Windows moves it for),
        # still without taking the focus. While it's held, it stays even once the main window has drawn, until let go.
        $card.add_MouseLeftButtonDown({
            param($sender, $press)
            $press.Handled = $true
            $null = $native::ReleaseCapture()
            # Returns once it's let go.
            $null = $native::SendMessage($source.Handle, 0x00A1, [IntPtr]2, [IntPtr]::Zero)
            # The press went to this thread, not the main window's: Windows now lets only this thread bring a window in
            # front, and the main window would open behind the others (a maximized one). It hands that on to Repère
            # (AllowSetForegroundWindow); once the main window is shown (Close-RepereSplash gives it), it brings it in
            # front itself. Moved first: whichever thread is last sees the other's part.
            $null = $native::AllowSetForegroundWindow([Environment]::ProcessId)
            $State.Moved = $true
            if ($State.MainWindow -ne [IntPtr]::Zero) { $null = $native::SetForegroundWindow($State.MainWindow) }
        })

        # The window, hidden until it's placed: a popup (WS_POPUP) that can't be activated and has no taskbar button
        # (WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW), with a shadow (CS_DROPSHADOW).
        $parameters = [System.Windows.Interop.HwndSourceParameters]::new($Title)
        $parameters.WindowStyle = 0x80000000
        $parameters.ExtendedWindowStyle = 0x08000080
        $parameters.WindowClassStyle = 0x00020000
        $source = [System.Windows.Interop.HwndSource]::new($parameters)
        # Its size is set below; otherwise, given none, it would take its content's.
        $source.SizeToContent = 'Manual'
        $source.RootVisual = $card
        # Its size and place in WPF's units, as the main window's: 280 by 184, centered on the work area (the screen
        # without its taskbar) of the screen under the mouse pointer, as the main window will be. Without the pointer
        # (none read), on the main screen's.
        $width = 280
        $height = 184
        # In pixels for Windows, at the scale WPF draws at: the system's, as Repère is aware of the system's DPI and not of
        # each screen's (Get-ScreenWorkArea). Windows gives it every screen's rectangle and the pointer at that scale too,
        # so one scale converts both ways.
        $scale = $source.CompositionTarget.TransformToDevice
        $area = [System.Windows.SystemParameters]::WorkArea
        if ($State.Cursor) {
            $monitor = $native::MonitorFromRect([int[]]@($cursor[0], $cursor[1], ($cursor[0] + 1), ($cursor[1] + 1)), 2)   # MONITOR_DEFAULTTONEAREST
            # MONITORINFO: its own size, the screen's rectangle, its work area's (rcWork), then flags.
            $info = [int[]]::new(10)
            $info[0] = 40
            if ($monitor -ne [IntPtr]::Zero -and $native::GetMonitorInfo($monitor, $info) -ne 0) {
                $area = [System.Windows.Rect]::new($info[5] / $scale.M11, $info[6] / $scale.M22, ($info[7] - $info[5]) / $scale.M11, ($info[8] - $info[6]) / $scale.M22)
            }
        }
        $x = $area.Left + $area.Width / 2
        $y = $area.Top + $area.Height / 2
        $corner = 2   # DWMWCP_ROUND; refused before Windows 11, which leaves the corners square.
        $null = $native::DwmSetWindowAttribute($source.Handle, 33, [ref]$corner, 4)

        # Closed by Close-RepereSplash from the main thread (BeginInvokeShutdown, which takes the window with it); before
        # it shows, when it was asked to close already. Shown on top, without taking the focus (SWP_NOACTIVATE,
        # SWP_SHOWWINDOW).
        $State.Dispatcher = $dispatcher
        if ($State.Closing) { return }
        $null = $native::SetWindowPos($source.Handle, [IntPtr]::Zero, [int](($x - $width / 2) * $scale.M11), [int](($y - $height / 2) * $scale.M22),
                                      [int]($width * $scale.M11), [int]($height * $scale.M22), 0x0050)
        [System.Windows.Threading.Dispatcher]::Run()
    }
    catch { $State.Error = "$_" }
}.ToString()

function Show-RepereSplash([string]$LogoPath) {
    # Not where no one would see a window (a service, a task run without a session).
    if (-not [Environment]::UserInteractive) { return }
    try {
        $state = [hashtable]::Synchronized(@{ Closing = $false; Dispatcher = $null; Error = $null; Cursor = $null; Moved = $false; MainWindow = [IntPtr]::Zero })
        # Empty, it would run no script at all (NoLanguage).
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
        $sessionState.LanguageMode = 'FullLanguage'
        $runspace = [runspacefactory]::CreateRunspace($sessionState)
        $runspace.ApartmentState = 'STA'
        $runspace.Open()
        $shell = [powershell]::Create()
        $shell.Runspace = $runspace
        $null = $shell.AddScript($script:SplashScript).AddArgument($state).AddArgument((Tr 'Repère')).AddArgument((Tr 'Démarrage de Repère…'))
        $null = $shell.AddArgument((Get-SettingPath 'apparence.json')).AddArgument($LogoPath)
        $script:Splash = @{ State = $state; Shell = $shell; Run = $shell.BeginInvoke() }
    }
    catch { Write-Verbose "Écran de démarrage non affiché : $_" }
}

function Get-RepereLaunchCursor {
    # Where the mouse pointer was as Repère was launched, in pixels, as the splash read it: the main window opens
    # centered on that screen (Get-CursorWorkArea), where the splash was. $null without a splash, or before it read it.
    if ($script:Splash) { $script:Splash.State.Cursor }
}

function Close-RepereSplash([System.Windows.Window]$Window) {
    # Once the main window has drawn (its ContentRendered, $Window), or before a reason to stop is shown (Exit-Repere).
    # Never having had the focus, the splash has none to hand on: the window or dialog has it as without a splash.
    # Moved, though, the splash's thread brings $Window in front (its handle given here), or has let it come in front.
    $splash = $script:Splash
    if (-not $splash) { return }
    $script:Splash = $null
    if ($Window) {
        $splash.State.MainWindow = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
        # Let go after it showed, before it was given: shown behind, then let to come in front.
        if ($splash.State.Moved -and -not $Window.IsActive) { $null = $Window.Activate() }
    }
    $splash.State.Closing = $true
    if ($splash.State.Dispatcher) { $null = $splash.State.Dispatcher.BeginInvokeShutdown('Normal') }
    # What went wrong on its thread, if anything, for the console: the splash didn't show, or went early.
    if ($splash.State.Error) { Write-Verbose "Écran de démarrage : $($splash.State.Error)" }
}
