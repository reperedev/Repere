# Checks on Repère's code itself, through PowerShell's parser, for mistakes this repo has made: a byte order mark
# written twice, LF line endings, and names that collide because PowerShell ignores their case (Background.ps1's
# $script:BackgroundTimer replaced by the main script's $backgroundTimer; a parameter $Inherited overwritten by a
# local $inherited). Each Find- function returns its findings as text, one per problem; none when all is well.
# Dot-sourced by StaticChecks.Tests.ps1, which also runs them on samples of the mistakes.

function Get-ParsedScript([string]$Path) {
    # A file as the checks take it: its name, relative to src or else to the repo when it's in them, and its syntax tree.
    $tokens = $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $base = @($script:RepereSource, $script:RepereRoot) | Where-Object { $_ -and $Path.StartsWith("$_\", [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    $name = if ($base) { $Path.Substring($base.Length + 1) } else { $Path }
    [pscustomobject]@{ Name = $name; Ast = $ast; Errors = $errors }
}

function ConvertTo-ParsedScript([string]$Name, [string]$Code) {
    # A sample, for the checks' own tests.
    $tokens = $errors = $null
    [pscustomobject]@{ Name = $Name; Ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors); Errors = $errors }
}

function Get-RepereSourcePath {
    # The repo's PowerShell files: those git tracks, and the new ones it would add (not yet committed, so a local run
    # checks what CI will; not those .gitignore leaves out); or every one outside .git and .claude when git can't say.
    $files = @(git -C $script:RepereRoot ls-files --cached --others --exclude-standard -- '*.ps1' '*.psm1' '*.psd1' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $files.Count) { return $files | ForEach-Object { Join-Path $script:RepereRoot $_ } }
    Get-ChildItem -LiteralPath $script:RepereRoot -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.FullName.Substring($script:RepereRoot.Length) -notmatch '^[\\/]\.(git|claude)[\\/]' } | ForEach-Object FullName
}

function Find-EncodingProblem([string]$Name, [byte[]]$Bytes) {
    # One UTF-8 byte order mark, exactly (twice, the second reads as a character and PowerShell runs the first line as a
    # command), and CRLF line endings only.
    $bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    if (-not $bom) { "${Name}: no UTF-8 byte order mark" }
    elseif ($Bytes.Length -ge 6 -and $Bytes[3] -eq 0xEF -and $Bytes[4] -eq 0xBB -and $Bytes[5] -eq 0xBF) { "${Name}: byte order mark written twice" }
    $line = 1
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 0x0A) {
            if ($i -eq 0 -or $Bytes[$i - 1] -ne 0x0D) { "${Name}:$line LF without CR"; return }
            $line++
        }
        elseif ($Bytes[$i] -eq 0x0D -and ($i + 1 -ge $Bytes.Length -or $Bytes[$i + 1] -ne 0x0A)) { "${Name}:$line CR without LF"; return }
    }
}

function Find-DuplicateFunction([object[]]$Script) {
    # Functions defined twice among scripts that share a scope, names ignoring case: the last one loaded silently wins.
    $definitions = foreach ($file in $Script) {
        foreach ($function in $file.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            [pscustomobject]@{ Name = $function.Name; Where = "$($file.Name):$($function.Extent.StartLineNumber)" }
        }
    }
    foreach ($group in $definitions | Group-Object { $_.Name.ToLowerInvariant() } | Where-Object Count -gt 1) {
        "$(@($group.Group.Name | Select-Object -Unique) -join ' / ') defined $($group.Count) times: $($group.Group.Where -join ', ')"
    }
}

function Get-AssignedVariable($Target) {
    # The variables an assignment's left side sets: $a, [int]$a, $a, $b = …; not $a.b or $a[0], which change an object.
    if ($Target -is [System.Management.Automation.Language.ConvertExpressionAst] -or $Target -is [System.Management.Automation.Language.AttributedExpressionAst]) { return Get-AssignedVariable $Target.Child }
    if ($Target -is [System.Management.Automation.Language.VariableExpressionAst]) { return $Target }
    if ($Target -is [System.Management.Automation.Language.ArrayLiteralAst]) { foreach ($element in $Target.Elements) { Get-AssignedVariable $element } }
}

function Test-TopLevel($Node, $Root) {
    # Whether a statement runs in its script's own scope: not in a function nor in a script block (an event handler, a
    # job's script). An if, a loop or a try is still top level.
    for ($parent = $Node.Parent; $parent -and $parent -ne $Root; $parent = $parent.Parent) {
        if ($parent -is [System.Management.Automation.Language.ScriptBlockAst]) { return $false }
    }
    $true
}

function Get-ScriptVariable($File) {
    # The script-scope variables a file sets: its parameters (a dot-sourced script's become its caller's variables),
    # what it assigns at top level, and every $script: assignment, wherever it is.
    $root = $File.Ast
    foreach ($parameter in @($root.ParamBlock.Parameters)) {
        if ($parameter) { [pscustomobject]@{ Name = $parameter.Name.VariablePath.UserPath; Where = "$($File.Name):$($parameter.Extent.StartLineNumber)" } }
    }
    foreach ($assignment in $root.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        foreach ($variable in @(Get-AssignedVariable $assignment.Left)) {
            $path = $variable.VariablePath
            if (-not $path.IsVariable) { continue }
            $name = $path.UserPath -replace '^(script|local|private):', ''
            $scriptScope = $path.UserPath -match '^script:' -or (($path.IsUnqualified -or $path.UserPath -match '^(local|private):') -and (Test-TopLevel $assignment $root))
            if ($scriptScope -and $name -ne 'null') { [pscustomobject]@{ Name = $name; Where = "$($File.Name):$($assignment.Extent.StartLineNumber)" } }
        }
    }
}

function Find-ScriptVariableClash([object[]]$Script, [string[]]$Allowed = @()) {
    # A script-scope variable set by two of the scripts that share a scope, under the same name or names that differ
    # only by case: one replaces the other. $Allowed: names shared on purpose.
    $variables = foreach ($file in $Script) { foreach ($variable in Get-ScriptVariable $file) { $variable | Add-Member File $file.Name -PassThru } }
    foreach ($group in $variables | Group-Object { $_.Name.ToLowerInvariant() }) {
        if (@($group.Group.File | Select-Object -Unique).Count -lt 2 -or $group.Name -in $Allowed) { continue }
        "`$$(@($group.Group.Name | Select-Object -Unique) -join ' / $') set in several files: $(@($group.Group.Where | Select-Object -Unique) -join ', ')"
    }
}

function Test-SameScopeBlock($Block) {
    # Whether a script block nested in a function runs in the function's own scope: those of ForEach-Object and
    # Where-Object do; one called with &, an event handler or a job's script has a scope of its own.
    $command = $Block.Parent.Parent
    if ($Block.Parent -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $command -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
    $command.GetCommandName() -in 'ForEach-Object', 'Where-Object', '%', '?', 'foreach', 'where'
}

function Find-UntranslatedText($File, $Table, [string[]]$Allowed = @()) {
    # The French text a file shows that Language.en.psd1 ($Table) can't put in English: a Tr text it has no entry for, Tr
    # given a string with variables in it (a format string is how: (Tr 'a {0}') -f $x), a window's XAML text it has no
    # entry for (Get-XamlText, Language.ps1), and a string with a French letter (é, à, ç, «, …) given neither to Tr nor
    # in XAML. Not Write-Host's text, which goes to the console. $Allowed: « File.ps1|text » strings left in French on
    # purpose.
    $trArguments = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($call in $File.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Tr' }, $true)) {
        $argument = $call.CommandElements[1]
        if (-not $argument) { continue }
        $null = $trArguments.Add($argument)
        $line = "$($File.Name):$($argument.Extent.StartLineNumber)"
        if ($argument -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and $argument.NestedExpressions.Count) {
            "${line}: Tr given a string with variables, $($argument.Extent.Text): use a format string"
        }
        elseif ($argument -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $argument -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            if (-not $Table.ContainsKey($argument.Value)) { "${line}: no translation for Tr « $($argument.Value) »" }
        }
    }
    $strings = $File.Ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
    }, $true)
    foreach ($string in $strings) {
        if ($trArguments.Contains($string)) { continue }
        $line = "$($File.Name):$($string.Extent.StartLineNumber)"
        # XAML: a tag (not a regex's named group, (?<name>…)).
        if ($string.Value -match '(?<!\?)<[A-Za-z][\w.:]*[\s/>]') {
            foreach ($text in Get-XamlText $string.Value) {
                # Text made by the code ($(…) in the string) is checked where it's made.
                if ($text -notmatch '\$' -and -not $Table.ContainsKey($text)) { "${line}: no translation for the XAML text « $text »" }
            }
            continue
        }
        if ($string.Value -notmatch '[àâçéèêëîïôûùüÿœÀÂÇÉÈÊËÎÏÔÛÙÜŒ«»…]') { continue }
        $command = $string.Parent
        while ($command -and $command -isnot [System.Management.Automation.Language.CommandAst] -and $command -isnot [System.Management.Automation.Language.StatementBlockAst]) { $command = $command.Parent }
        if ($command -is [System.Management.Automation.Language.CommandAst] -and $command.GetCommandName() -in 'Write-Host', 'Write-Verbose', 'Write-Debug') { continue }
        if ("$($File.Name)|$($string.Value)" -in $Allowed) { continue }
        "${line}: French text outside Tr « $($string.Value) »"
    }
}

function Find-DispatcherStringArgument($File) {
    # A Dispatcher's Invoke or BeginInvoke given an [Action] then a string (a priority as 'Input'): PowerShell picks the
    # (Delegate, params Object[]) overload, the string becomes the action's argument, and the action fails when it runs
    # (« Parameter count mismatch »). The priority is written [System.Windows.Threading.DispatcherPriority]::Input.
    $calls = $File.Ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and "$($node.Member)" -in 'Invoke', 'BeginInvoke' -and
        @($node.Arguments).Count -ge 2 -and $node.Arguments[0] -is [System.Management.Automation.Language.ConvertExpressionAst] -and
        @($node.Arguments | Select-Object -Skip 1 | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }).Count
    }, $true)
    foreach ($call in $calls) { "$($File.Name):$($call.Extent.StartLineNumber): $($call.Member) given a string after its delegate; a priority must be a DispatcherPriority" }
}

function Find-ButtonTagData($File) {
    # A button's Tag set in code: Theme.ps1's button template takes its corner radius from the Tag, so data there makes
    # the button square, or rounded by 12 for a 12 (#225). What its click needs goes in its CommandParameter. A button
    # here: a variable named …button…, FindName of a name ending in _copy, _show, _hide, _open, _expand_all or
    # _collapse_all (with an index or not), or a variable set to one of those or to [System.Windows.Controls.Button]::new().
    $isButtonName = '(_copy|_show|_hide|_open|_expand_all|_collapse_all)([_"'']|$)'
    $made = @($File.Ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        ("$($node.Right)" -match '^\[System\.Windows\.Controls\.Button\]::new\(' -or ("$($node.Right)" -match '\.FindName\(' -and "$($node.Right)" -match $isButtonName))
    }, $true) | ForEach-Object { $_.Left.VariablePath.UserPath.ToLowerInvariant() })
    $sets = $File.Ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.MemberExpressionAst] -and "$($node.Left.Member)" -eq 'Tag'
    }, $true)
    foreach ($set in $sets) {
        $target = $set.Left.Expression
        $isButton = if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $name = $target.VariablePath.UserPath.ToLowerInvariant()
            $name -match 'button' -or $made -contains $name
        }
        elseif ($target -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and "$($target.Member)" -eq 'FindName') {
            "$($target.Arguments[0])".Trim('"', "'") -match $isButtonName
        }
        if ($isButton) { "$($File.Name):$($set.Extent.StartLineNumber): a button's Tag is its corner radius; put what its click needs in CommandParameter" }
    }
}

function Find-ParameterCaseAssignment($File, [string[]]$Allowed = @()) {
    # In a function, or a script block with parameters, an assignment (or a foreach) to a variable named as one of its
    # parameters but in another case: it is that parameter, overwritten, while it reads as a new variable. $Allowed:
    # « Function:variable » entries.
    $owners = $File.Ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
        ($node -is [System.Management.Automation.Language.ScriptBlockAst] -and $node.ParamBlock -and $node.Parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst])
    }, $true)
    foreach ($owner in $owners) {
        $isFunction = $owner -is [System.Management.Automation.Language.FunctionDefinitionAst]
        $body = if ($isFunction) { $owner.Body } else { $owner }
        $ownerName = if ($isFunction) { $owner.Name } else { "script block at line $($owner.Extent.StartLineNumber)" }
        $parameters = @(@($(if ($isFunction) { $owner.Parameters }), $body.ParamBlock.Parameters) | ForEach-Object { $_ } | Where-Object { $_ } | ForEach-Object { $_.Name.VariablePath.UserPath })
        if (-not $parameters.Count) { continue }
        $targets = $body.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -or $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)
        foreach ($target in $targets) {
            # Only what runs in the owner's own scope.
            $own = $true
            for ($parent = $target.Parent; $parent -and $parent -ne $body; $parent = $parent.Parent) {
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                    ($parent -is [System.Management.Automation.Language.ScriptBlockAst] -and -not (Test-SameScopeBlock $parent))) { $own = $false; break }
            }
            if (-not $own) { continue }
            $variables = if ($target -is [System.Management.Automation.Language.ForEachStatementAst]) { $target.Variable } else { Get-AssignedVariable $target.Left }
            foreach ($variable in @($variables)) {
                $name = $variable.VariablePath.UserPath
                $parameter = $parameters | Where-Object { $_ -ieq $name -and $_ -cne $name } | Select-Object -First 1
                if ($parameter -and "${ownerName}:$name" -notin $Allowed) {
                    "$($File.Name):$($target.Extent.StartLineNumber): `$$name overwrites the parameter `$$parameter of $ownerName"
                }
            }
        }
    }
}
