# Repère in the taskbar as itself, not as PowerShell. Repère runs in pwsh.exe, so Windows groups its windows with
# PowerShell's, under pwsh's icon, and a pin would start a bare PowerShell. An AppUserModelID of its own, set before any
# window opens (Set-RepereAppId), gives it its own button with its own icon; and its main window tells Windows what a pin
# starts (Set-RepereRelaunch): Repère, with the options it was started with, under its name and compass.ico.
#
# Both are Windows calls that PowerShell can't make by itself. Add-Type would compile them, a quarter to half a second
# at every start: Reflection.Emit defines them in a few milliseconds instead. Neither ever stops Repère: without them,
# it's grouped with PowerShell, as before.

# What groups Repère's windows, and the shortcuts that start it.
$script:RepereAppId = 'Repere.App'
# The Windows calls' types, defined at the first Get-RepereNativeType. Set here so that reading it before then is no
# error under strict mode, where a variable never set is one.
$script:RepereNative = $null

function Get-RepereNativeType {
    # The Windows calls, defined once: Shell, the static methods of shell32.dll; PropertyStore, the COM interface
    # IPropertyStore, its methods in the order of their slots, every pointer as an IntPtr.
    if ($script:RepereNative) { return $script:RepereNative }
    $assembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([System.Reflection.AssemblyName]::new('RepereNative'), 'Run')
    $module = $assembly.DefineDynamicModule('RepereNative')

    $shellType = $module.DefineType('RepereNative.Shell', 'Public, Class, Abstract, Sealed')
    $pinvoke = { param($Name, [type[]]$Parameters)
        $method = $shellType.DefinePInvokeMethod($Name, 'shell32.dll', 'Public, Static, PinvokeImpl', 'Standard', [int], $Parameters, 'Winapi', 'Unicode')
        $method.SetImplementationFlags('PreserveSig')
    }
    & $pinvoke 'SetCurrentProcessExplicitAppUserModelID' @([string])
    & $pinvoke 'SHGetPropertyStoreForWindow' @([IntPtr], [guid].MakeByRefType(), [IntPtr].MakeByRefType())
    $shell = $shellType.CreateType()

    $storeType = $module.DefineType('RepereNative.IPropertyStore', 'Public, Interface, Abstract, Import')
    $storeType.SetCustomAttribute([System.Reflection.Emit.CustomAttributeBuilder]::new(
        [System.Runtime.InteropServices.GuidAttribute].GetConstructor([type[]]@([string])), [object[]]@('886d8eeb-8cf2-4446-8d02-cdba1dbdcf99')))
    $storeType.SetCustomAttribute([System.Reflection.Emit.CustomAttributeBuilder]::new(
        [System.Runtime.InteropServices.InterfaceTypeAttribute].GetConstructor([type[]]@([System.Runtime.InteropServices.ComInterfaceType])),
        [object[]]@([System.Runtime.InteropServices.ComInterfaceType]::InterfaceIsIUnknown)))
    $slots = [ordered]@{ GetCount = @([IntPtr]); GetAt = @([uint32], [IntPtr]); GetValue = @([IntPtr], [IntPtr]); SetValue = @([IntPtr], [IntPtr]); Commit = @() }
    foreach ($name in $slots.Keys) {
        $method = $storeType.DefineMethod($name, 'Public, Abstract, Virtual, HideBySig, NewSlot', [int], [type[]]$slots[$name])
        $method.SetImplementationFlags('PreserveSig')
    }
    $script:RepereNative = @{ Shell = $shell; PropertyStore = $storeType.CreateType() }
    $script:RepereNative
}

function Set-RepereAppId {
    # Before the first window: a window opened earlier stays grouped with PowerShell.
    try {
        $result = (Get-RepereNativeType).Shell::SetCurrentProcessExplicitAppUserModelID($script:RepereAppId)
        if ($result) { Write-Verbose ('AppUserModelID non défini : 0x{0:X8}' -f $result) }
    }
    catch { Write-Verbose "AppUserModelID non défini : $_" }
}

function Get-RepereTaskbarIcon([string]$IconPath, [string]$Folder = (Join-Path $env:LOCALAPPDATA 'Repere')) {
    # The icon the taskbar shows, as a copy named after its contents (compass-<hash>.ico). Windows keeps the icons it
    # has read by their path and doesn't read a file again when it changes: a new icon under the same name would show
    # the old one, even after Repère restarts. A new icon is a new name, read afresh. Copied once per icon; the copies
    # of older icons stay, as a pin made back then may still point to them. Without a copy, the icon itself.
    try {
        $hash = (Get-FileHash -LiteralPath $IconPath -Algorithm SHA256 -ErrorAction Stop).Hash.Substring(0, 12).ToLowerInvariant()
        $copy = Join-Path $Folder "compass-$hash.ico"
        if (-not (Test-Path -LiteralPath $copy)) {
            $null = New-Item -ItemType Directory -Force -Path $Folder -ErrorAction Stop
            Copy-Item -LiteralPath $IconPath -Destination $copy -ErrorAction Stop
        }
        $copy
    }
    catch {
        Write-Verbose "Icône de la barre des tâches non copiée : $_"
        $IconPath
    }
}

function Get-RepereRelaunchCommand([string]$PwshPath, [string]$ScriptPath, [System.Collections.IDictionary]$Options) {
    # What a pin starts: Repère as Repère.cmd starts it, without a console (conhost --headless), with the options it was
    # started with ($Options: the script's bound parameters, as PowerShell has them).
    $arguments = foreach ($name in 'FakeAD', 'ExtraFakeComputers', 'Domains', 'MoveRoots', 'Language', 'NoUpdateCheck') {
        # By its keys: $PSBoundParameters, a Dictionary, has no Contains of its own.
        if ($Options.Keys -notcontains $name) { continue }
        $value = $Options[$name]
        if ($value -is [System.Management.Automation.SwitchParameter]) { if ($value.IsPresent) { "-$name" } ; continue }
        # The lists as the script reads them back: domains between commas, OUs between semicolons.
        $text = if ($name -eq 'MoveRoots') { @($value) -join ';' } elseif ($name -eq 'Domains') { @($value) -join ',' } else { [string]$value }
        if ($text) { "-$name `"$($text.Replace('"', ''))`"" }
    }
    # The Store's PowerShell runs from a folder named after its version, gone at its next update: its alias instead,
    # which follows it.
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
    if ($PwshPath -like '*\WindowsApps\*' -and (Test-Path -LiteralPath $alias)) { $PwshPath = $alias }
    $command = "`"$env:windir\System32\conhost.exe`" --headless `"$PwshPath`" -NoProfile -File `"$ScriptPath`""
    (@($command) + @($arguments)) -join ' '
}

function Set-RepereRelaunch([System.Windows.Window]$Window, [string]$Command, [string]$IconPath) {
    # A pin of $Window starts $Command, named Repère, with $IconPath's icon. Windows reads the three together from the
    # window's property store, under the AppUserModelID that Set-RepereAppId gave the process, set on the window too.
    $handle = [System.Windows.Interop.WindowInteropHelper]::new($Window).EnsureHandle()
    $native = Get-RepereNativeType
    $iid = [guid]'886d8eeb-8cf2-4446-8d02-cdba1dbdcf99'
    $pointer = [IntPtr]::Zero
    $result = $native.Shell::SHGetPropertyStoreForWindow($handle, [ref]$iid, [ref]$pointer)
    if ($result -or $pointer -eq [IntPtr]::Zero) { throw ('SHGetPropertyStoreForWindow : 0x{0:X8}' -f $result) }
    $store = [System.Runtime.InteropServices.Marshal]::GetTypedObjectForIUnknown($pointer, $native.PropertyStore)
    [void][System.Runtime.InteropServices.Marshal]::Release($pointer)
    # PKEY_AppUserModel_*: the format {9F4C2855-…} and each property's number. Each value a PROPVARIANT of type
    # VT_LPWSTR (31): its type in its first two bytes, the string's address 8 bytes in; IPropertyStore copies it.
    $format = [guid]'9f4c2855-9f79-4b39-a8d0-e1d42de1d5f3'
    # By number, in a list: an ordered hashtable would read an integer key as a position.
    $values = @(@(5, $script:RepereAppId), @(2, $Command), @(4, (Tr 'Repère')), @(3, "$IconPath,0"))
    $key = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(20)
    $variant = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(24)
    try {
        foreach ($pair in $values) {
            $id = $pair[0]
            [System.Runtime.InteropServices.Marshal]::Copy($format.ToByteArray(), 0, $key, 16)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($key, 16, $id)
            [System.Runtime.InteropServices.Marshal]::Copy([byte[]]::new(24), 0, $variant, 24)
            [System.Runtime.InteropServices.Marshal]::WriteInt16($variant, 0, 31)
            $text = [System.Runtime.InteropServices.Marshal]::StringToCoTaskMemUni($pair[1])
            try {
                [System.Runtime.InteropServices.Marshal]::WriteIntPtr($variant, 8, $text)
                $result = $native.PropertyStore.GetMethod('SetValue').Invoke($store, @($key, $variant))
                if ($result) { throw ('IPropertyStore.SetValue({0}) : 0x{1:X8}' -f $id, $result) }
            }
            finally { [System.Runtime.InteropServices.Marshal]::FreeCoTaskMem($text) }
        }
        $result = $native.PropertyStore.GetMethod('Commit').Invoke($store, @())
        if ($result) { throw ('IPropertyStore.Commit : 0x{0:X8}' -f $result) }
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($key)
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($variant)
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($store)
    }
}
