# Prochain nom…: how a text reads as a format, what makes one unusable, and the names a series gives (NextName.ps1).
# The window itself is tested by Test-RepereUI.ps1's NextName session.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')

    function Get-Series([string]$Text, [string]$Exclude = '') { New-NameSeries @(ConvertTo-NameFormat $Text) $Exclude }
    function Get-Name([string]$Text, [string[]]$Taken = @(), [int]$Count = 1) { (Get-NextName -Series (Get-Series $Text) -TakenName $Taken -Count $Count).Names }

    # A Random that draws a limited number of times, so that drawing forever fails a test instead of hanging it. With
    # Zeros, every draw is 0, a number that's never a name in a series whose counter has a 0.
    if (-not ('BoundedRandom' -as [type])) {
        Add-Type -TypeDefinition @'
public class BoundedRandom : System.Random {
    public int Left;
    public bool Zeros;
    public BoundedRandom(int seed, int left, bool zeros) : base(seed) { Left = left; Zeros = zeros; }
    public override void NextBytes(byte[] buffer) {
        if (Left-- <= 0) { throw new System.InvalidOperationException("Too many draws"); }
        if (Zeros) { System.Array.Clear(buffer, 0, buffer.Length); } else { base.NextBytes(buffer); }
    }
}
'@
    }
}

Describe 'ConvertTo-NameFormat' {
    It '<Typed> reads as <Expected>' -ForEach @(
        @{ Typed = 'ORD-0143'; Expected = 'ORD-####' }
        @{ Typed = 'ORD-####'; Expected = 'ORD-####' }
        @{ Typed = 'ORD-@@@-####'; Expected = 'ORD-@@@-####' }
        @{ Typed = 'ORD-AAA-####'; Expected = 'ORD-@@@-####' }
        @{ Typed = 'ord-aaa-####'; Expected = 'ORD-@@@-####' }
        @{ Typed = 'PC-XX-###'; Expected = 'PC-@@-###' }
        @{ Typed = 'LABO-###'; Expected = 'LABO-###' }
        @{ Typed = 'LAPTOP-0012'; Expected = 'LAPTOP-####' }
        @{ Typed = 'PORTABLE-###'; Expected = 'PORTABLE-###' }
        @{ Typed = 'KIOSQUE-07'; Expected = 'KIOSQUE-##' }
        @{ Typed = 'ORD-24-0143'; Expected = 'ORD-24-####' }
        @{ Typed = 'ORD-MTL-0143'; Expected = 'ORD-MTL-####' }
        @{ Typed = 'ORD@@@'; Expected = 'ORD@@@' }
        @{ Typed = 'ORD0143'; Expected = 'ORD####' }
        @{ Typed = 'SALLE-A-###'; Expected = 'SALLE-A-###' }
        @{ Typed = 'SERVEUR'; Expected = 'SERVEUR' }
        @{ Typed = '  ORD-01  '; Expected = 'ORD-##' }
    ) {
        Get-NameFormatText @(ConvertTo-NameFormat $Typed) | Should -BeExactly $Expected
    }

    It 'Only letter and digit blocks can be switched, not separators, # or @' {
        @(ConvertTo-NameFormat 'ORD-0143-##').Locked -join ',' | Should -BeExactly 'False,True,False,True,True'
    }

    It 'Asks AD for the text before the first varying block' {
        Get-NameFormatStart @(ConvertTo-NameFormat 'ORD-MTL-####') | Should -BeExactly 'ORD-MTL-'
        Get-NameFormatStart @(ConvertTo-NameFormat 'ORD-AAA-####') | Should -BeExactly 'ORD-'
        Get-NameFormatStart @(ConvertTo-NameFormat '@@-##') | Should -BeExactly ''
    }
}

Describe 'Get-NameFormatProblem' {
    It '<Case>' -ForEach @(
        @{ Case = 'Nothing typed'; Typed = ''; Expected = 'Tapez un nom ou un modèle.' }
        @{ Case = 'More than 15 characters'; Typed = 'ORD-####-ABCDEFGH'; Expected = 'Un nom a 15 caractères au plus.' }
        @{ Case = 'A space'; Typed = 'ORD 01'; Expected = 'Lettres, chiffres, - et _ seulement.' }
        @{ Case = 'A dot'; Typed = 'ORD.01'; Expected = 'Lettres, chiffres, - et _ seulement.' }
        @{ Case = 'An accent'; Typed = 'ÉCOLE-01'; Expected = 'Lettres, chiffres, - et _ seulement.' }
        @{ Case = 'Only digits'; Typed = '12345'; Expected = 'Un nom ne peut pas être fait que de chiffres.' }
        @{ Case = 'Only # '; Typed = '####'; Expected = 'Un nom ne peut pas être fait que de chiffres.' }
        @{ Case = 'No fixed start'; Typed = '##-LAB'; Expected = 'Un modèle commence par un texte fixe, ex. ORD-####.' }
    ) {
        Get-NameFormatProblem @(ConvertTo-NameFormat $Typed) | Should -BeExactly $Expected
    }

    It 'A good format has none' {
        Get-NameFormatProblem @(ConvertTo-NameFormat 'ORD_01-####') | Should -BeNullOrEmpty
    }

    It 'Exclure can''t leave a varying block without characters' {
        Get-NameFormatProblem @(ConvertTo-NameFormat 'ORD-#') '0123456789' | Should -BeExactly 'Exclure ne laisse plus aucun caractère à ce modèle.'
        Get-NameFormatProblem @(ConvertTo-NameFormat 'ORD-AA-1') '0123456789' | Should -BeNullOrEmpty
    }
}

Describe 'Get-NextName' {
    BeforeAll { $script:Taken = 'ORD-0141', 'ord-0142', 'ORD-0143', 'ORD-LABO', 'ORD-12345', 'ORD-MTL-0009' }

    It 'After the highest, whatever the case and without the names that don''t fit' {
        Get-Name 'ORD-####' $Taken 2 | Should -BeExactly 'ORD-0144', 'ORD-0145'
    }

    It 'A new series starts at 1' {
        Get-Name 'NEUF-###' $Taken 2 | Should -BeExactly 'NEUF-001', 'NEUF-002'
    }

    It 'Fixed letters are a series of their own' {
        Get-Name 'ORD-MTL-0143' $Taken | Should -BeExactly 'ORD-MTL-0010'
    }

    It 'Letters carry over, past 0000' {
        Get-Name 'ORD-AAA-####' 'ORD-AAA-9999' 2 | Should -BeExactly 'ORD-AAB-0001', 'ORD-AAB-0002'
    }

    It 'Letters after the digits' {
        Get-Name 'O-##@' 'O-01Z' | Should -BeExactly 'O-02A'
        Get-Name 'O-##@' 'O-99Z' | Should -BeNullOrEmpty
    }

    It 'Stops at a full series' {
        Get-Name 'O-#' 'O-9' | Should -BeNullOrEmpty
        Get-Name 'O-#' 'O-8' 5 | Should -BeExactly 'O-9'
    }

    It 'Several groups of digits count as one, the last never all zeros' {
        Get-Name 'O-##-##' 'O-01-99' | Should -BeExactly 'O-02-01'
    }

    It 'A name that doesn''t vary is checked as it is' {
        Get-Name 'SERVEUR' $Taken | Should -BeExactly 'SERVEUR'
        Get-Name 'ORD-LABO' $Taken | Should -BeNullOrEmpty
    }

    It 'An AAA clicked fixed only looks at its own letters' {
        $blocks = @(ConvertTo-NameFormat 'ORD-AAA-####')
        $blocks[2].Varies = $false
        (Get-NextName -Series (New-NameSeries $blocks) -TakenName 'ORD-AAA-0004', 'ORD-AAB-0100').Names | Should -BeExactly 'ORD-AAA-0005'
    }

    It 'Fills the gaps when asked' {
        (Get-NextName -Series (Get-Series 'O-##') -TakenName 'O-01', 'O-02', 'O-05' -Count 3 -FillGaps).Names | Should -BeExactly 'O-03', 'O-04', 'O-06'
    }

    It 'Starts from a name, or after the highest above it' {
        (Get-NextName -Series (Get-Series 'O-###') -TakenName 'O-001' -From 'O-500').Names | Should -BeExactly 'O-500'
        (Get-NextName -Series (Get-Series 'O-###') -TakenName 'O-600' -From 'O-500').Names | Should -BeExactly 'O-601'
    }

    It 'Leaves out the characters excluded, and the names that have them' {
        $series = Get-Series 'O-@#' 'ABI0'
        (Get-NextName -Series $series -Count 2).Names | Should -BeExactly 'O-C1', 'O-C2'
        (Get-NextName -Series $series -TakenName 'O-C9', 'O-Z0').Names | Should -BeExactly 'O-D1'
    }

    It 'Says how many of the names are in the series' {
        (Get-NextName -Series (Get-Series 'ORD-####') -TakenName ($Taken + 'ORD-0143')).Taken | Should -Be 3
    }

    It 'Counts the names a format can make' {
        (Get-Series 'ORD-####').Count | Should -Be 9999
        (Get-Series 'ORD-AAA-####').Count | Should -Be ([bigint]175742424)
        (Get-Series 'SERVEUR').Count | Should -Be 1
    }

    It 'A counter that Exclure leaves only 0 counts as it is, never with a name the series can''t have' {
        $series = Get-Series 'ORD-@@@-#' '123456789'
        $series.Count | Should -Be 17576
        (Get-NextName -Series $series -Count 3).Names | Should -BeExactly 'ORD-AAA-0', 'ORD-AAB-0', 'ORD-AAC-0'
        (Get-NextName -Series $series -TakenName 'ORD-AAA-0', 'ORD-AAB-0' -Count 2).Names | Should -BeExactly 'ORD-AAC-0', 'ORD-AAD-0'
        (Get-NextName -Series $series -TakenName 'ORD-AAA-0', 'ORD-AAC-0' -Count 2 -FillGaps).Names | Should -BeExactly 'ORD-AAB-0', 'ORD-AAD-0'
    }

    It 'ORD-# with only 0 left has ORD-0, and is full once it''s taken' {
        $series = Get-Series 'ORD-#' '123456789'
        $series.Count | Should -Be 1
        (Get-NextName -Series $series).Names | Should -BeExactly 'ORD-0'
        (Get-NextName -Series $series -Random ([BoundedRandom]::new(1, 0, $false))).Names | Should -BeExactly 'ORD-0'
        (Get-NextName -Series $series -TakenName 'ORD-0').Names | Should -BeNullOrEmpty
        (Get-NextName -Series $series -TakenName 'ORD-0' -Random ([BoundedRandom]::new(1, 0, $false))).Names | Should -BeNullOrEmpty
    }

    It 'Never gives a number past the zeros that isn''t a name' {
        $series = Get-Series 'O-@-#'
        Get-NameSeriesValid $series ([bigint]10) | Should -Be 11
        # A series where no number is a name, as the counter with only 0 was: past the series, not a wrong name.
        $series.Size = [bigint]1
        Get-NameSeriesValid $series ([bigint]10) | Should -Be $series.Space
    }

    It 'Never enumerates a large series' {
        $series = Get-Series 'AAAAAAA-#######'
        $last = 'ZZZZZZZ-9999998'
        (Get-NextName -Series $series -TakenName $last -Count 2).Names | Should -BeExactly 'ZZZZZZZ-9999999'
    }

    Context 'At random' {
        It 'Gives free names, different ones, the same for the same seed' {
            $series = Get-Series 'ORD-####'
            $names = (Get-NextName -Series $series -TakenName $Taken -Count 20 -Random ([System.Random]::new(7))).Names
            $names.Count | Should -Be 20
            @($names | Select-Object -Unique).Count | Should -Be 20
            $names | Where-Object { $_ -in $Taken } | Should -BeNullOrEmpty
            $names | ForEach-Object { $_ | Should -Match '^ORD-[0-9]{4}$' }
            (Get-NextName -Series $series -TakenName $Taken -Count 20 -Random ([System.Random]::new(7))).Names | Should -BeExactly $names
        }

        It 'Finds the last free names of a nearly full series' {
            $taken = 1..98 | ForEach-Object { 'O-{0:00}' -f $_ }
            ((Get-NextName -Series (Get-Series 'O-##') -TakenName $taken -Count 5 -Random ([System.Random]::new(1))).Names | Sort-Object) -join ',' | Should -BeExactly 'O-99'
        }

        It 'Stays quick on a very large series, without the all-zero names' {
            $names = (Get-NextName -Series (Get-Series 'AAAAAAA-#') -Count 30 -Random ([System.Random]::new(3))).Names
            $names.Count | Should -Be 30
            $names | Where-Object { $_ -like '*-0' } | Should -BeNullOrEmpty
        }

        It 'Ends when Exclure leaves the counter only 0' {
            $names = (Get-NextName -Series (Get-Series 'ORD-@@@-#' '123456789') -Count 3 -Random ([BoundedRandom]::new(5, 1000, $false))).Names
            $names.Count | Should -Be 3
            @($names | Select-Object -Unique).Count | Should -Be 3
            $names | ForEach-Object { $_ | Should -Match '^ORD-[A-Z]{3}-0$' }
        }

        It 'Draws nothing from a full series' {
            $taken = 1..9 | ForEach-Object { "O-$_" }
            (Get-NextName -Series (Get-Series 'O-#') -TakenName $taken -Count 3 -Random ([BoundedRandom]::new(1, 0, $false))).Names | Should -BeNullOrEmpty
        }

        It 'Finds the free names of a large series where they''re rare' {
            # 0 and 1 for the counter: half the numbers are all zeros, and all names but two are taken.
            $free = 'O-AB-1', 'O-QZ-1'
            $taken = foreach ($first in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ') {
                foreach ($second in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ') { "O-$first$second-1" }
            }
            $taken = @($taken | Where-Object { $_ -notin $free }) + 'O-AA-0'
            $series = Get-Series 'O-@@-#' '23456789'
            $series.Count | Should -Be 676
            ((Get-NextName -Series $series -TakenName $taken -Count 5 -Random ([BoundedRandom]::new(2, 1000, $false))).Names | Sort-Object) -join ',' | Should -BeExactly ($free -join ',')
        }

        It 'Stops drawing when luck runs out, and gives the lowest free names instead' {
            # Every draw is O-AAAA-0, never a name: past its draws, the series still has names to give.
            $random = [BoundedRandom]::new(1, 1000, $true)
            (Get-NextName -Series (Get-Series 'O-@@@@-#') -TakenName 'O-AAAA-1' -Count 2 -Random $random).Names | Should -BeExactly 'O-AAAA-2', 'O-AAAA-3'
            $random.Left | Should -BeGreaterThan 0
        }
    }
}

Describe 'Get-NameSeriesChoice' {
    It 'Offers the series in use, the most used first, and no name without digits' {
        $choices = @(Get-NameSeriesChoice 'ORD' 'ORD-0001', 'ord-0002', 'ORD-MTL-0001', 'ORD-LABO', 'LABO-01')
        $choices.Format -join ',' | Should -BeExactly 'ORD-####,ORD-MTL-####'
        $choices.Count | Should -Be 2
        $choices[0].PSObject.Properties['Count'].Value | Should -Be 2
    }

    It 'Counts a name in two domains once, as « déjà pris » does, and its computers apart' {
        $choice = @(Get-NameSeriesChoice 'ORD' 'ORD-01', 'ORD-02', 'ord-01')[0]
        "$($choice.PSObject.Properties['Count'].Value) $($choice.Accounts)" | Should -BeExactly '2 3'
    }

    It 'Stops at the pattern part of what''s typed' {
        Get-NameTypedStart 'ord-##' | Should -BeExactly 'ORD-'
        Get-NameTypedStart 'ORD-@@-##' | Should -BeExactly 'ORD-'
    }
}

Describe 'Get-FailedDomainText' {
    It 'says a reason once, with its domains' {
        $failed = @(@{ Domain = 'a.local'; Reason = 'Rien' }, @{ Domain = 'b.local'; Reason = 'Refusé' }, @{ Domain = 'c.local'; Reason = 'Rien' })
        Get-FailedDomainText $failed | Should -Be 'b.local (Refusé) ; a.local, c.local (Rien)'
    }
}

Describe 'What SCCM is asked' {
    It 'A site code has 3 letters or digits, and a server is a name' {
        Get-SccmSettingProblem 'P01' 'sccm.demo.local' | Should -BeNullOrEmpty
        Get-SccmSettingProblem 'P0' 'sccm.demo.local' | Should -Not -BeNullOrEmpty
        Get-SccmSettingProblem 'P01' 'sccm demo' | Should -Not -BeNullOrEmpty
        Get-SccmSettingProblem 'P01' '' | Should -Not -BeNullOrEmpty
    }

    It 'Each box has its own problem, for Paramètres to say under it' {
        $problem = Get-SccmFieldProblem 'P0' 'sccm.demo.local'
        $problem.Site | Should -BeLike 'Le code du site*'
        $problem.Server | Should -BeNullOrEmpty
        $problem = Get-SccmFieldProblem 'P01' 'sccm demo'
        $problem.Site | Should -BeNullOrEmpty
        $problem.Server | Should -BeLike 'Le serveur est un nom*'
        $problem = Get-SccmFieldProblem '' ''
        $problem.Site | Should -Not -BeNullOrEmpty
        $problem.Server | Should -Not -BeNullOrEmpty
        # The site's comes first when both are wrong.
        Get-SccmSettingProblem 'P0' 'sccm demo' | Should -BeLike 'Le code du site*'
    }

    Context 'With the fake SCCM' {
        BeforeAll {
            $script:FakeSccmModule = Join-Path $script:RepereSource 'FakeAD\FakeSccm.psm1'
            $script:Site = @{ Site = 'DEM'; Server = 'sccm.demo.local' }
        }

        AfterAll { $env:REPERE_FAKEAD_SCCM_UNREACHABLE = $null; $env:REPERE_FAKEAD_SCCM_ERROR = $null }

        It 'Finds the names that start with the text' {
            $check = Get-SccmCheck $Site 'ORD-'
            $check.Checked | Should -BeTrue
            $check.Names | Should -Contain 'ORD-14'
        }

        It 'Says none when SCCM has none, not a failure' {
            $check = Get-SccmCheck $Site 'INCONNU-'
            $check.Checked | Should -BeTrue
            $check.Names | Should -BeNullOrEmpty
        }

        It 'A site that doesn''t exist is a failure with its reason' {
            $check = Get-SccmCheck @{ Site = 'ZZZ'; Server = 'sccm.demo.local' } 'ORD-'
            $check.Checked | Should -BeFalse
            $check.Reason | Should -BeExactly 'le site ZZZ est introuvable sur sccm.demo.local'
        }

        It 'A server that doesn''t answer is a failure, never an empty list' {
            $env:REPERE_FAKEAD_SCCM_UNREACHABLE = '1'
            $check = Get-SccmCheck $Site 'ORD-'
            $env:REPERE_FAKEAD_SCCM_UNREACHABLE = $null
            $check.Checked | Should -BeFalse
            $check.Reason | Should -BeExactly 'sccm.demo.local ne répond pas'
        }

        It 'A console older than the site says so in one line, with the version, and stays not checked (#329)' {
            $env:REPERE_FAKEAD_SCCM_ERROR = 'A new version of the console is available (5.2603.1035.1900). Cmdlets may not function as expected or may corrupt your site''s configuration if they are a different version than your site.'
            try { $check = Get-SccmCheck $Site 'ORD-' }
            finally { $env:REPERE_FAKEAD_SCCM_ERROR = $null }
            $check.Checked | Should -BeFalse
            $check.Names | Should -BeNullOrEmpty
            $check.Reason | Should -BeExactly 'la console Configuration Manager doit être mise à jour (version 5.2603.1035.1900)'
        }

        It 'Any other error gives its first sentence, never PowerShell''s « La commande… s''est arrêtée » (#329)' {
            # The second: an error already wrapped, as a French Windows words it.
            $cases = @(
                , @("Something went wrong on the site. More about it here.`nA second line.", 'Something went wrong on the site')
                , @('La commande en cours d''exécution s''est arrêtée, car la variable de préférence « ErrorActionPreference » ou le paramètre commun est défini sur stop : Le site refuse la demande. Détails.', 'Le site refuse la demande')
            )
            foreach ($case in $cases) {
                $env:REPERE_FAKEAD_SCCM_ERROR = $case[0]
                try { $check = Get-SccmCheck $Site 'ORD-' }
                finally { $env:REPERE_FAKEAD_SCCM_ERROR = $null }
                $check.Checked | Should -BeFalse
                $check.Reason | Should -BeExactly $case[1]
                $check.Reason | Should -Not -Match 'ErrorActionPreference|running command stopped|s.est arrêtée'
            }
        }

        It 'A site too slow is a failure once the time is up, without waiting for it' {
            $saved = $script:SccmTimeoutSeconds
            $script:SccmTimeoutSeconds = 1
            $env:REPERE_FAKEAD_SCCM_DELAY = '30'
            try {
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                $check = Get-SccmCheck $Site 'ORD-'
                $watch.Elapsed.TotalSeconds | Should -BeLessThan 10
                $check.Checked | Should -BeFalse
                $check.Reason | Should -BeExactly 'SCCM n''a pas répondu en 1 secondes'
            }
            finally {
                $script:SccmTimeoutSeconds = $saved
                $env:REPERE_FAKEAD_SCCM_DELAY = $null
            }
        }

        It 'A check out of time leaves no runspace behind once stopped (#240)' {
            $saved = $script:SccmTimeoutSeconds
            $script:SccmTimeoutSeconds = 1
            $env:REPERE_FAKEAD_SCCM_DELAY = '30'
            # The timer's ticks, until the stops have completed: the test before left one too.
            $sweep = {
                for ($i = 0; $i -lt 100 -and $script:SccmStopping.Count; $i++) {
                    Start-Sleep -Milliseconds 100
                    Clear-SccmStopping
                }
            }
            try {
                & $sweep
                $before = @(Get-Runspace).Count
                foreach ($try in 1..3) { (Get-SccmCheck $Site 'ORD-').Checked | Should -BeFalse }
                @(Get-Runspace).Count | Should -BeGreaterThan $before
                & $sweep
                $script:SccmStopping.Count | Should -Be 0
                @(Get-Runspace).Count | Should -Be $before
            }
            finally {
                $script:SccmTimeoutSeconds = $saved
                $env:REPERE_FAKEAD_SCCM_DELAY = $null
            }
        }

        It 'A check still stopping is left for the next tick, never disposed while it runs' {
            $shell = [powershell]::Create()
            $stop = [pscustomobject]@{ IsCompleted = $false }
            $script:SccmStopping.Enqueue(@{ Shell = $shell; Stop = $stop })
            try {
                Clear-SccmStopping
                $script:SccmStopping.Count | Should -Be 1
                # A disposed shell throws.
                { $null = $shell.AddScript('1') } | Should -Not -Throw
            }
            finally {
                $entry = $null
                $null = $script:SccmStopping.TryDequeue([ref]$entry)
                $shell.Dispose()
            }
        }
    }

    Context 'Finding the module' {
        BeforeAll {
            $script:SavedAdminUi = $env:SMS_ADMIN_UI_PATH
            $script:FakeSccmModule = $null
            $script:Site = @{ Site = 'DEM'; Server = 'sccm.demo.local' }
            # The console's real module has the last word: these two are for a computer without it.
            $script:HasConsole = [bool](Get-Module -ListAvailable ConfigurationManager)
        }

        AfterAll { $env:SMS_ADMIN_UI_PATH = $script:SavedAdminUi }

        It 'Without the console, says so' {
            if ($HasConsole) { Set-ItResult -Skipped -Because 'this computer has the console' }
            $env:SMS_ADMIN_UI_PATH = $null
            $check = Get-SccmCheck $Site 'ORD-'
            $check.Checked | Should -BeFalse
            $check.Reason | Should -BeExactly 'la console Configuration Manager n''est pas installée sur cet ordinateur'
        }

        It 'Finds it from SMS_ADMIN_UI_PATH, a folder under the module''s' {
            if ($HasConsole) { Set-ItResult -Skipped -Because 'this computer has the console' }
            $bin = Join-Path $TestDrive 'AdminConsole\bin'
            New-Item -ItemType Directory -Force -Path (Join-Path $bin 'i386') | Out-Null
            Copy-Item (Join-Path $script:RepereSource 'FakeAD\FakeSccm.psm1') (Join-Path $bin 'ConfigurationManager.psm1')
            "@{ RootModule = 'ConfigurationManager.psm1'; ModuleVersion = '1.0'; FunctionsToExport = '*' }" | Set-Content (Join-Path $bin 'ConfigurationManager.psd1')
            $env:SMS_ADMIN_UI_PATH = Join-Path $bin 'i386'
            $check = Get-SccmCheck $Site 'VIEUX-'
            $check.Checked | Should -BeTrue
            $check.Names | Should -BeExactly 'VIEUX-01'
        }
    }
}

Describe 'A read a change made useless (#240)' {
    BeforeAll {
        $script:rowBuilderScript = ''
        $script:searchPool = [runspacefactory]::CreateRunspacePool(1, 2)
        $script:searchPool.Open()
        # A DC, or SCCM, that takes its time.
        function Wait-SlowRead { Start-Sleep -Seconds 30 }
    }

    AfterAll {
        $script:searchPool.Dispose()
        $script:searchPool = $null
    }

    It 'Is stopped, not left holding a search runspace until it answers' {
        $state = @{ ReadId = 4 }
        $done = @{ Problem = $null }
        Start-BackgroundRead -Command 'Wait-SlowRead' -Context @{ State = $state; Id = $state.ReadId } -OnDone {
            param($context, $read, $problem)
            $done.Problem = $problem
        }.GetNewClosure()
        $read = $script:BackgroundReadList[$script:BackgroundReadList.Count - 1]
        Stop-NextNameRead $state
        $state.ReadId | Should -Be 5
        $read.Handle.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
        Complete-BackgroundRead
        $done.Problem | Should -Not -BeNullOrEmpty
    }
}

Describe 'The domains ticked as the window opens (#221)' {
    It '<Case>' -ForEach @(
        @{ Case = 'the last choice, what''s still offered of it, in the list''s spelling'; Saved = @('B.LOCAL', 'gone.local', 'c.local'); Preferred = 'a.local'; Expected = 'b.local,c.local' }
        @{ Case = 'the page''s domain, not all of them, the first time'; Saved = @(); Preferred = 'b.local'; Expected = 'b.local' }
        @{ Case = 'the page''s domain when none of the last choice is offered any more'; Saved = @('gone.local'); Preferred = 'c.local'; Expected = 'c.local' }
        @{ Case = 'the first domain when the page''s isn''t offered'; Saved = @(); Preferred = 'Tous les domaines'; Expected = 'a.local' }
    ) {
        @(Get-NextNameDomainChoice @('a.local', 'b.local', 'c.local') $Saved $Preferred) -join ',' | Should -BeExactly $Expected
    }

    It 'A single domain is ticked whatever was saved' {
        @(Get-NextNameDomainChoice @('a.local') @('b.local') '') -join ',' | Should -BeExactly 'a.local'
    }
}

Describe 'The domains'' filter box (#221)' {
    It 'shows <Domain> for « <Filter> »: <Expected>' -ForEach @(
        @{ Domain = 'nord.demo.local'; Filter = ''; Expected = $true }
        @{ Domain = 'nord.demo.local'; Filter = 'NORD'; Expected = $true }
        @{ Domain = 'nord.demo.local'; Filter = ' demo. '; Expected = $true }
        @{ Domain = 'nord.demo.local'; Filter = 'sud'; Expected = $false }
    ) {
        Test-NextNameDomainShown $Domain $Filter | Should -Be $Expected
    }
}

Describe 'Prochainnom.json' {
    BeforeAll {
        $script:SavedPath = $script:NextNameSettingPath
        $script:NextNameSettingPath = Join-Path $TestDrive 'prochainnom.json'
    }

    AfterAll { $script:NextNameSettingPath = $script:SavedPath }

    It 'Without a file, the defaults' {
        $setting = Read-NextNameSetting
        "$($setting.Count) $($setting.Random) $($setting.FillGaps) $($setting.Sccm) $($setting.Recent.Count)" | Should -BeExactly '3 False False True 0'
    }

    It 'Keeps a block clicked fixed, which the text alone wouldn''t give back' {
        $blocks = @(ConvertTo-NameFormat 'ORD-AAA-####')
        $blocks[2].Varies = $false
        $recent = @(Add-RecentNameFormat $blocks @())
        Save-JsonSetting $script:NextNameSettingPath ([ordered]@{ Recent = @($recent | ForEach-Object { , @($_) }); Count = 5 }) -Depth 5
        $setting = Read-NextNameSetting
        $setting.Count | Should -Be 5
        $setting.Recent.Count | Should -Be 1
        Get-NameFormatText $setting.Recent[0] | Should -BeExactly 'ORD-AAA-####'
    }

    It 'Leaves out what isn''t a format, and what isn''t offered' {
        '{"Recent":[[{"Kind":"Nope","Length":1}]],"Count":999,"Exclude":"a b"}' | Set-Content $script:NextNameSettingPath
        $setting = Read-NextNameSetting
        "$($setting.Count) [$($setting.Exclude)] $($setting.Recent.Count)" | Should -BeExactly '3 [] 0'
    }

    It 'Keeps the domains ticked, and leaves out what isn''t a name (#221)' {
        '{"Domains":["a.local","",3,"B.local"]}' | Set-Content $script:NextNameSettingPath
        (Read-NextNameSetting).Domains -join ',' | Should -BeExactly 'a.local,B.local'
    }

    It 'A format used again comes first, once, and the list stops at its limit' {
        $recent = @()
        foreach ($text in 'A-#', 'B-#', 'C-#', 'D-#', 'E-#', 'F-#', 'G-#', 'H-#', 'I-#', 'B-#') { $recent = @(Add-RecentNameFormat @(ConvertTo-NameFormat $text) $recent) }
        ($recent | ForEach-Object { Get-NameFormatText $_ }) -join ',' | Should -BeExactly 'B-#,I-#,H-#,G-#,F-#,E-#,D-#,C-#'
    }
}

Describe 'SCCM''s failures known by their codes, whatever Windows'' language' {
    BeforeAll { $script:SavedSccmModule = $script:FakeSccmModule }
    AfterAll { $script:FakeSccmModule = $script:SavedSccmModule }

    It '<Case>' -ForEach @(
        @{ Case = 'a site that is not on its server (WMI''s invalid namespace)'; Message = 'Ungültiger Namespace'; Code = '0x8004100E'; Reason = 'le site DEM est introuvable sur sccm.demo.local' }
        # Without « RPC » in its words: the old text match would have found it there.
        @{ Case = 'a server that does not answer (RPC)'; Message = 'Der Server ist nicht verfügbar.'; Code = '0x800706BA'; Reason = 'sccm.demo.local ne répond pas' }
    ) {
        # A console that fails as a German Windows says it: neither the English nor the French text Repère knows.
        $module = Join-Path $TestDrive "GermanSccm-$($Code).psm1"
        Set-Content -LiteralPath $module -Encoding utf8BOM -Value @"
function Get-PSDrive { [CmdletBinding()] param([string]`$Name, [string]`$PSProvider) }
function New-PSDrive { [CmdletBinding()] param([string]`$Name, [string]`$PSProvider, [string]`$Root, [string]`$Scope) throw [System.Runtime.InteropServices.COMException]::new('$Message', $Code) }
Export-ModuleMember -Function Get-PSDrive, New-PSDrive
"@
        $script:FakeSccmModule = $module
        $check = Get-SccmCheck @{ Site = 'DEM'; Server = 'sccm.demo.local' } 'ORD-'
        $check.Checked | Should -BeFalse
        $check.Reason | Should -BeExactly $Reason
    }
}