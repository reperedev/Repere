# Exporter and Copier les lignes, on the three pages (Get-ExportField, SearchPage.ps1): the columns the grid shows, in
# its order and under its headers, what a column writes when the grid shows less than the value (Compte's icon,
# Système's short name, En ligne's badge, Mot de passe's « Expire dans 3 jours »), the distinguished name always last,
# and the CSV a page saves (UTF-8 with a BOM, the list separator, the rows in the grid's order). Grids made in code, as
# the pages' have them: no window.

BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadRepere.ps1')
    # ComputerPage.ps1 loads only with the window: Get-ComputerExportField alone, from its source.
    $computerPage = Get-RepereScriptAst (Join-Path $script:RepereSource 'ComputerPage.ps1')
    $definition = $computerPage.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ComputerExportField' }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))

    function New-TestGrid([string[]]$Columns, [string[]]$Hidden = @(), [string]$Name = 'grid') {
        # A grid with these columns, each « key=Header », in this order; $Hidden collapsed.
        $grid = [System.Windows.Controls.DataGrid]::new()
        $grid.Name = $Name
        foreach ($entry in $Columns) {
            $key, $header = $entry -split '=', 2
            $column = [System.Windows.Controls.DataGridTextColumn]::new()
            $column.SortMemberPath = $key
            $column.Header = $header
            if ($key -in $Hidden) { $column.Visibility = 'Collapsed' }
            $grid.Columns.Add($column)
        }
        $grid
    }

    function New-ComputerRow([hashtable]$Values = @{}) {
        # A computer's row with what the export reads, as the row builder makes it.
        $row = [ordered]@{
            ComputerName = 'ORD-02'; Description = 'Salle 1'; Disabled = $null; IsOn = $true; LastLogon = '2026-11-20 08:15'; LastLogonAgo = 'il y a 3 jours'
            OSShort = 'Win 11 24H2'; OSFull = 'Windows 11 Professionnel 10.0 (26100)'; OSBuild = 26100; Domain = 'demo.local'
            ShortPath = 'demo.local/Postes/Communs'; OUPath = 'Postes › Communs'; OU = 'CN=ORD-02,OU=Communs,OU=Postes,DC=demo,DC=local'
            Online = $null; OnlineLabel = $null; OnlineAddress = $null
        }
        foreach ($key in $Values.Keys) { $row[$key] = $Values[$key] }
        [pscustomobject]$row
    }

    $script:computerColumns = 'Disabled=Compte', 'ComputerName=Nom', 'Description=Description', 'LastLogon=Dernière connexion', 'OSBuild=Système',
                              'Domain=Domaine', 'ShortPath=Emplacement', 'Online=En ligne'
}

Describe 'The computers'' Exporter and Copier les lignes' {
    It 'Writes the columns shown, in their order, a column hidden left out, the distinguished name last' {
        $grid = New-TestGrid $script:computerColumns -Hidden 'Description', 'Online'
        # Système dragged before Nom.
        $grid.Columns[4].DisplayIndex = 1
        $fields = Get-ComputerExportField $grid.Columns
        @($fields.Header) | Should -Be @('Compte', 'Système', 'Version de Windows', 'Nom', 'Dernière connexion', 'Domaine', 'Emplacement', 'Nom distinctif')
        $row = @(ConvertTo-ExportRow @(New-ComputerRow) $fields)[0]
        @($row.PSObject.Properties.Value) | Should -Be @('Activé', 'Win 11 24H2', 'Windows 11 Professionnel 10.0 (26100)', 'ORD-02', '2026-11-20 08:15', 'demo.local',
                                                         'Postes › Communs', 'CN=ORD-02,OU=Communs,OU=Postes,DC=demo,DC=local')
    }

    It 'Writes Désactivé for a disabled computer, and empty values for what AD doesn''t know' {
        $grid = New-TestGrid $script:computerColumns -Hidden 'Online'
        $row = @(ConvertTo-ExportRow @(New-ComputerRow @{ Disabled = 'Désactivé'; IsOn = $false; Description = $null; LastLogon = $null; OSShort = $null; OSFull = $null }) (Get-ComputerExportField $grid.Columns))[0]
        $row.Compte | Should -BeExactly 'Désactivé'
        $row.Description | Should -BeNullOrEmpty
        $row.'Dernière connexion' | Should -BeNullOrEmpty
        $row.'Système' | Should -BeNullOrEmpty
    }

    It 'Writes En ligne, once shown, as the answer and the address; empty for a computer not checked' {
        $grid = New-TestGrid $script:computerColumns
        $fields = Get-ComputerExportField $grid.Columns
        @($fields.Header)[-3..-1] | Should -Be @('En ligne', 'Adresse IP', 'Nom distinctif')
        $rows = @(ConvertTo-ExportRow @((New-ComputerRow @{ OnlineLabel = 'En ligne'; OnlineAddress = '10.0.1.12' }), (New-ComputerRow @{ ComputerName = 'ORD-03' })) $fields)
        "$($rows[0].'En ligne') | $($rows[0].'Adresse IP')" | Should -BeExactly 'En ligne | 10.0.1.12'
        "$($rows[1].'En ligne')$($rows[1].'Adresse IP')" | Should -BeExactly ''
    }

    It 'In English, the headers the grid shows and those Exporter adds, and Enabled' {
        [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', (Read-TextTable (Join-Path $script:RepereSource 'Language.en.psd1')))
        try {
            # The grid's headers come translated from its XAML (ConvertTo-LocalXaml).
            $grid = New-TestGrid 'Disabled=Account', 'ComputerName=Name', 'OSBuild=OS', 'Online=Online'
            $fields = Get-ComputerExportField $grid.Columns
            @($fields.Header) | Should -Be @('Account', 'Name', 'OS', 'Windows version', 'Online', 'IP address', 'Distinguished name')
            @(ConvertTo-ExportRow @(New-ComputerRow) $fields)[0].Account | Should -BeExactly 'Enabled'
        }
        finally { [System.AppDomain]::CurrentDomain.SetData('Repere.TextTable', $null) }
    }

    It 'Copies the same columns, a tab between them, without the header, a formula kept as text' {
        $grid = New-TestGrid $script:computerColumns -Hidden 'Disabled', 'LastLogon', 'OSBuild', 'Domain', 'ShortPath', 'Online'
        $rows = (New-ComputerRow), (New-ComputerRow @{ ComputerName = 'ORD-05'; Description = '=HYPERLINK("x")'; OU = 'CN=ORD-05,DC=demo,DC=local' })
        Get-RowClipboardText $rows (Get-ComputerExportField $grid.Columns) |
            Should -BeExactly ("ORD-02`tSalle 1`tCN=ORD-02,OU=Communs,OU=Postes,DC=demo,DC=local" + [Environment]::NewLine + "ORD-05`t'=HYPERLINK(`"x`")`tCN=ORD-05,DC=demo,DC=local")
    }
}

Describe 'The Utilisateurs and Groupes pages'' Exporter and Copier les lignes' {
    BeforeAll {
        function New-TestPage($Page, [string[]]$Columns, [string[]]$Hidden, $Rows) {
            # A copy of $Page (the users' or the groups'): a grid of these columns, these rows, and the controls Exporter uses.
            $copy = $Page.Clone()
            $root = [System.Windows.Controls.StackPanel]::new()
            $grid = New-TestGrid $Columns $Hidden "$($copy.Prefix)_grid"
            $time = [System.Windows.Controls.TextBlock]::new()
            $time.Name = "$($copy.Prefix)_time"
            $null = $root.Children.Add($grid)
            $null = $root.Children.Add($time)
            [System.Windows.NameScope]::SetNameScope($root, [System.Windows.NameScope]::new())
            $root.RegisterName($grid.Name, $grid)
            $root.RegisterName($time.Name, $time)
            $copy.Root = $root
            $copy.Rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new([object[]]@($Rows))
            $copy.View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($copy.Rows)
            $copy
        }

        function New-UserRow([string]$Login, [int64]$Expiry, [string]$Shown) {
            [pscustomobject]@{
                Name = "Nom $Login"; Login = $Login; Mail = "$Login@demo.local"; Title = 'Technicienne'; Department = 'Informatique'; Description = ''
                State = 'Actif'; LastLogon = '2026-11-02 09:30'; LastLogonAgo = 'il y a 3 semaines'; Password = $Shown; PasswordSort = $Expiry
                Domain = 'demo.local'; OUPath = 'Utilisateurs'; DistinguishedName = "CN=$Login,OU=Utilisateurs,DC=demo,DC=local"
            }
        }

        $script:userColumns = 'State=État', 'Name=Nom', 'Login=Identifiant', 'Mail=Courriel', 'Title=Poste', 'Department=Service', 'Description=Description',
                              'LastLogon=Dernière connexion', 'PasswordSort=Mot de passe', 'Domain=Domaine', 'OUPath=Emplacement'
        $script:expiry = [datetime]::new(2026, 12, 4, 17, 45, 0, [System.DateTimeKind]::Local)
        $script:exportFile = Join-Path ([System.IO.Path]::GetTempPath()) "repere-export-test-$PID.csv"
    }

    AfterAll {
        Remove-Item -LiteralPath $script:exportFile -ErrorAction SilentlyContinue
        $env:REPERE_EXPORT_PATH = $null
    }

    It 'Users: Mot de passe writes what it shows, then when it expires; Courriel hidden, left out' {
        $rows = (New-UserRow 'jbertrand' $script:expiry.ToFileTime() 'Expire le 04/12/2026'), (New-UserRow 'lperrin' ([int64]::MaxValue) "N'expire jamais"), (New-UserRow 'pbertrand' 0 'À changer à la connexion')
        $page = New-TestPage $script:UserPage $script:userColumns @('Mail', 'Description', 'Domain') $rows
        $fields = Get-PageExportField $page
        @($fields.Header) | Should -Be @('État', 'Nom', 'Identifiant', 'Poste', 'Service', 'Dernière connexion', 'Mot de passe', 'Expiration du mot de passe', 'Emplacement', 'Nom distinctif')
        $lines = @(ConvertTo-ExportRow $rows $fields)
        "$($lines[0].'Mot de passe') | $($lines[0].'Expiration du mot de passe')" | Should -BeExactly 'Expire le 04/12/2026 | 2026-12-04 17:45'
        $lines[1].'Expiration du mot de passe' | Should -BeNullOrEmpty
        $lines[2].'Expiration du mot de passe' | Should -BeNullOrEmpty
        $lines[0].'Nom distinctif' | Should -BeExactly 'CN=jbertrand,OU=Utilisateurs,DC=demo,DC=local'
    }

    It 'Users: saves the rows shown, in the grid''s order, as CSV with a BOM and the list separator' {
        $rows = (New-UserRow 'jbertrand' 0 'À changer à la connexion'), (New-UserRow 'aleroy' 0 'À changer à la connexion'), (New-UserRow 'zmartin' 0 'À changer à la connexion')
        $page = New-TestPage $script:UserPage $script:userColumns @('State', 'Title', 'Department', 'Description', 'LastLogon', 'PasswordSort', 'Domain', 'OUPath') $rows
        $page.View.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Login', 'Descending'))
        $page.View.Filter = [Predicate[object]]{ param($row) $row.Login -ne 'aleroy' }
        Remove-Item -LiteralPath $script:exportFile -ErrorAction SilentlyContinue
        $env:REPERE_EXPORT_PATH = $script:exportFile
        Export-PageRow $page
        $bytes = [System.IO.File]::ReadAllBytes($script:exportFile)
        @($bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        $separator = (Get-Culture).TextInfo.ListSeparator
        Get-Content -LiteralPath $script:exportFile -Encoding utf8 -TotalCount 1 | Should -BeExactly (@('Nom', 'Identifiant', 'Courriel', 'Nom distinctif') -join $separator)
        $saved = @(Import-Csv -LiteralPath $script:exportFile -Delimiter $separator -Encoding utf8)
        @($saved | ForEach-Object { "$($_.Identifiant) | $($_.Courriel) | $($_.'Nom distinctif')" }) | Should -Be @(
            'zmartin | zmartin@demo.local | CN=zmartin,OU=Utilisateurs,DC=demo,DC=local'
            'jbertrand | jbertrand@demo.local | CN=jbertrand,OU=Utilisateurs,DC=demo,DC=local'
        )
        $page.Root.FindName('user_time').Text | Should -BeExactly '· 2 lignes exportées'
    }

    It 'Groups: the columns shown, Domaine once shown, and the distinguished name last' {
        $row = [pscustomobject]@{ Name = 'GG-Accueil'; SamAccountName = 'GG-Accueil'; Type = 'Sécurité'; Scope = 'Globale'; Description = 'Accueil'; Mail = ''; ManagedBy = 'Nathalie Lévy'
                                  Domain = 'demo.local'; DistinguishedName = 'CN=GG-Accueil,OU=Groupes,DC=demo,DC=local'; OUPath = 'Groupes' }
        $columns = 'Name=Nom', 'SamAccountName=Nom pré-Windows 2000', 'Type=Type', 'Scope=Étendue', 'Description=Description', 'Mail=Courriel', 'ManagedBy=Géré par',
                   'Domain=Domaine', 'OUPath=Emplacement'
        $page = New-TestPage $script:GroupPage $columns @('SamAccountName', 'Mail', 'Description') @($row)
        $text = Get-RowClipboardText @($row) (Get-PageExportField $page)
        $text | Should -BeExactly "GG-Accueil`tSécurité`tGlobale`tNathalie Lévy`tdemo.local`tGroupes`tCN=GG-Accueil,OU=Groupes,DC=demo,DC=local"
    }
}
