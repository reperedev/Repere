# Fake ConfigurationManager module, for Prochain nom… with the fake AD. Loaded in place of the real one, in the runspace
# of its own where $script:SccmReadScript (NextName.ps1) runs: that script is then the same, down to the site's drive.
# The site is DEM on sccm.demo.local, with two devices AD doesn't have (ORD-13, ORD-14), as a reinstalled or deleted
# computer leaves, one that AD has too, and one AD never had.
#
# For the UI tests:
# - $env:REPERE_FAKEAD_SCCM_UNREACHABLE: when set, the site doesn't answer.
# - $env:REPERE_FAKEAD_SCCM_DELAY: seconds; Get-CMDevice takes that long.
# - $env:REPERE_FAKEAD_SCCM_ERROR: a message; mounting the site writes it as an error that doesn't stop the command,
#   as the console does when the site's version isn't its own.

$script:Server = 'sccm.demo.local'
$script:Site = 'DEM'
$script:Devices = 'ORD-01', 'ORD-13', 'ORD-14', 'VIEUX-01'
# Whether the location is the site's drive: the real cmdlets refuse to run anywhere else.
$script:OnSiteDrive = $false

function Get-PSDrive {
    # No site's drive yet: the real module can mount one, the fake one never does.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Standing in for the CMSite provider is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([string]$Name, [string]$PSProvider)
}

function New-PSDrive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Standing in for the CMSite provider is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Scope', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([string]$Name, [string]$PSProvider, [string]$Root, [string]$Scope)

    if ($PSProvider -ne 'CMSite') { throw "Provider '$PSProvider' not found." }
    # With their codes, as Windows gives them: Repère knows them by those (Get-ErrorKind), not by their text.
    if ($env:REPERE_FAKEAD_SCCM_UNREACHABLE -or $Root -ne $script:Server) { throw [System.Runtime.InteropServices.COMException]::new('The RPC server is unavailable.', 0x800706BA) }
    if ($Name -ne $script:Site) { throw [System.Runtime.InteropServices.COMException]::new('Invalid namespace', 0x8004100E) }
    if ($env:REPERE_FAKEAD_SCCM_ERROR) {
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new($env:REPERE_FAKEAD_SCCM_ERROR), 'FakeSccmError', 'InvalidOperation', $Name))
    }
    [pscustomobject]@{ Name = $Name; Root = $Root }
}

function Set-Location {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Standing in for the CMSite provider is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Same parameters as the real cmdlet.')]
    [CmdletBinding()]
    param([Parameter(Position = 0)] [string]$Path)

    if ($Path -ne "$($script:Site):\") { throw "Cannot find drive for '$Path'." }
    $script:OnSiteDrive = $true
}

function Get-CMDevice {
    # The devices whose name matches, as -Resource gives them: without it, a real read would take far longer.
    [CmdletBinding()]
    param([string]$Name, [switch]$Resource)

    if (-not $script:OnSiteDrive) { throw 'This command cannot be run from the current drive. To run this command you must first connect to a Configuration Manager drive.' }
    if (-not $Resource) { throw 'Get-CMDevice without -Resource.' }
    $delay = 0
    if ([int]::TryParse("$env:REPERE_FAKEAD_SCCM_DELAY", [ref]$delay) -and $delay -gt 0) { Start-Sleep -Seconds $delay }
    $script:Devices | Where-Object { $_ -like $Name } | ForEach-Object { [pscustomobject]@{ Name = $_ } }
}

Export-ModuleMember -Function Get-PSDrive, New-PSDrive, Set-Location, Get-CMDevice
