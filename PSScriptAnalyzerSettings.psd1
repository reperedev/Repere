# PSScriptAnalyzer settings, picked up by Invoke-ScriptAnalyzer (and the Lint workflow) when it runs on this folder.
@{
    ExcludeRules = @(
        # Repère is a GUI script: Write-Host is its console log, not output meant for a pipeline.
        'PSAvoidUsingWriteHost'
        # Set-RowState, Remove-ResultRow and the like are internal UI helpers, not cmdlets: -WhatIf / -Confirm would
        # mean nothing there. The AD changes themselves are confirmed in the UI.
        'PSUseShouldProcessForStateChangingFunctions'
        # Internal helpers called with positional arguments, like the rest of the code.
        'PSAvoidUsingPositionalParameters'
        # The fake AD's commands mimic the real ones; their comments say what they support.
        'PSProvideCommentHelp'
    )
}
