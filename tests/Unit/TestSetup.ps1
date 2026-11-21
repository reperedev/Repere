# What the unit tests share: where Repère's files are, which of them the main script dot-sources (read from its own
# code, so the tests follow a file split in two), the row builder's helpers ($rowBuilderScript, taken from the main
# script without running it) and the fake AD, imported afresh. Dot-sourced by each *.Tests.ps1 file's BeforeAll, which
# then dot-sources Repère's files itself: a function can't dot-source them into its caller's scope.

$script:RepereRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:RepereSource = Join-Path $script:RepereRoot 'src'
$script:RepereMainScript = Join-Path $script:RepereSource 'Repere - Recherche PC AD par description.ps1'

function Get-RepereScriptAst([string]$Path) {
    $tokens = $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "$Path doesn't parse: $($errors[0].Message)" }
    $ast
}

function Get-RepereDotSourcedPath([string]$Path = $script:RepereMainScript, [switch]$Recurse, [switch]$BeforeWindow) {
    # The files a script dot-sources as . "$PSScriptRoot\Name.ps1", in its order; with -Recurse, those they dot-source
    # too (SpecsWindow.ps1 dot-sources PCSpecs.ps1), each after the file that dot-sources it. With -BeforeWindow, only
    # those the main script dot-sources before it makes its window ($win): the ones after (the computer page and its
    # actions) look up the window's controls as they load, so they can't be loaded without it.
    $folder = Split-Path $Path
    $ast = Get-RepereScriptAst $Path
    $commands = $ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq 'Dot'
    }, $true)
    if ($BeforeWindow) {
        $window = $ast.Find({
            param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq 'win'
        }, $false)
        if ($window) { $commands = @($commands | Where-Object { $_.Extent.StartOffset -lt $window.Extent.StartOffset }) }
    }
    foreach ($command in $commands) {
        $target = $command.CommandElements[0]
        if ($target -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and $target.Value -match '^\$PSScriptRoot[\\/](.+\.ps1)$') {
            $file = Join-Path $folder $Matches[1]
            $file
            if ($Recurse) { Get-RepereDotSourcedPath $file -Recurse }
        }
    }
}

function Get-RepereRowBuilder {
    # The row builder's code (Format-Age, Get-OUPath, Get-ShortPath…): the script block assigned to $rowBuilderScript,
    # in whichever of Repère's files holds it, to dot-source.
    foreach ($file in Get-ChildItem -LiteralPath $script:RepereSource -Filter *.ps1) {
        $assignment = (Get-RepereScriptAst $file.FullName).Find({
            param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq 'rowBuilderScript'
        }, $true)
        if ($assignment) {
            $block = $assignment.Right.Find({ param($node) $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true)
            return $block.ScriptBlock.GetScriptBlock()
        }
    }
    throw 'No assignment to $rowBuilderScript found.'
}

function Import-RepereFakeAD([int]$ExtraComputers = 0) {
    # The fake AD, its store made again (it's kept in the process, for the search runspaces): each test file starts from
    # the same AD, whatever an earlier one did. Its log goes to $env:REPERE_FAKEAD_LOG, set by the tests that read it.
    $env:REPERE_FAKEAD_EXTRA_COMPUTERS = if ($ExtraComputers) { $ExtraComputers } else { $null }
    [System.AppDomain]::CurrentDomain.SetData('Repere.FakeAD', $null)
    Import-Module (Join-Path $script:RepereSource 'FakeAD\FakeAD.psm1') -Force -Global -ErrorAction Stop
    $env:REPERE_FAKEAD_EXTRA_COMPUTERS = $null
}

function Read-FakeADLog {
    # The fake AD's log: one object per command it received (Command and its parameters).
    if (-not (Test-Path -LiteralPath $env:REPERE_FAKEAD_LOG)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($env:REPERE_FAKEAD_LOG)) { if ($line) { $line | ConvertFrom-Json } }
}

function Clear-FakeADLog {
    if (Test-Path -LiteralPath $env:REPERE_FAKEAD_LOG) { Remove-Item -LiteralPath $env:REPERE_FAKEAD_LOG }
}
