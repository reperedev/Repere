@echo off
rem Starts Repere with PowerShell 7 and no console window: double-click this file, or a shortcut to it (whose target
rem can add Repere's parameters, e.g. -Domains a.local,b.local). Repere shows its own errors in a dialog.
setlocal
set "REPERE_DIR=%~dp0"
rem Repere needs PowerShell 7.5 or later (WPF's Fluent theme): missing and too old are asked about here, in this
rem console, while it's still seen. Once started headless below, nothing Repere's script writes would be.
set "PWSH_FOUND="
call :findpwsh
if defined PWSH goto run

call :findlanguage %*
if "%REPERE_LANG%"=="en" goto english
set "TEXT_NEEDS=Repere demande PowerShell 7.5 ou plus recent (installe :"
set "TEXT_NONE=introuvable"
set "TEXT_KEYS=ON"
set "TEXT_ASK=L'installer maintenant avec winget ? (O/N) "
set "TEXT_STILL=PowerShell 7.5 ou plus recent reste introuvable apres winget (code"
set "TEXT_MANUAL=Installez PowerShell 7.5 ou plus recent, puis relancez Repere :"
set "TEXT_OR=ou telechargez-le ici :"
set "TEXT_PAUSE=Appuyez sur une touche pour continuer..."
goto ask
:english
set "TEXT_NEEDS=Repere requires PowerShell 7.5 or later (installed:"
set "TEXT_NONE=none"
set "TEXT_KEYS=YN"
set "TEXT_ASK=Install it now with winget? (Y/N) "
set "TEXT_STILL=PowerShell 7.5 or later still not found after winget (code"
set "TEXT_MANUAL=Install PowerShell 7.5 or later, then start Repere again:"
set "TEXT_OR=or download it here:"
set "TEXT_PAUSE=Press any key to continue..."
:ask
if not defined PWSH_FOUND set "PWSH_FOUND=%TEXT_NONE%"
echo %TEXT_NEEDS% %PWSH_FOUND%).
where winget.exe >nul 2>nul
if errorlevel 1 goto manual
choice /c %TEXT_KEYS% /n /m "%TEXT_ASK%"
if errorlevel 2 goto manual
rem In this console, so that its progress and any prompt are seen.
winget install --id Microsoft.PowerShell --source winget
set "WINGET_EXIT=%errorlevel%"
rem winget now installs the Microsoft Store's package, the MSI before: whichever it installed, and whatever its exit
rem code says, Repere starts if a PowerShell recent enough is there now.
call :findpwsh
if defined PWSH goto run
echo.
echo %TEXT_STILL% %WINGET_EXIT%).
goto manual

:manual
echo.
echo %TEXT_MANUAL%
echo     winget install --id Microsoft.PowerShell --source winget
echo %TEXT_OR% https://aka.ms/powershell-release?tag=stable
echo %TEXT_PAUSE%
pause >nul
exit /b 1

:run
rem Files downloaded from the Internet are marked, and PowerShell then refuses to load them, before Repere could say
rem why: unmark this folder's files once, on the first launch. The mark is read by cmd itself (no dir or find to start).
((set /p REPERE_ZONE=) <"%REPERE_DIR%src\Repere - Recherche PC AD par description.ps1:Zone.Identifier") 2>nul && "%PWSH%" -NoProfile -NonInteractive -Command "Get-ChildItem -LiteralPath $env:REPERE_DIR -Recurse | Unblock-File"
start "" conhost.exe --headless "%PWSH%" -NoProfile -File "%REPERE_DIR%src\Repere - Recherche PC AD par description.ps1" %*
exit /b 0

:findpwsh
rem PWSH: the first PowerShell 7.5 or later of the one on the PATH, the Microsoft Store's (its alias, where winget
rem installs it now) and the MSI's. A console opened before an installation doesn't have it on its PATH yet, and an
rem older PowerShell can come first on it. PWSH_FOUND: the version of an older one found, for the message.
set "PWSH="
rem The one found last time comes first, as long as it's there and unchanged: no version to ask then.
set "PWSH_CHECKED="
if exist "%APPDATA%\Repere\pwsh.txt" set /p PWSH_CHECKED=<"%APPDATA%\Repere\pwsh.txt"
for /f "tokens=1 delims=*" %%p in ("%PWSH_CHECKED%") do call :trypwsh "%%~p"
if not defined PWSH for %%i in (pwsh.exe) do if not "%%~$PATH:i"=="" call :trypwsh "%%~$PATH:i"
if not defined PWSH call :trypwsh "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not defined PWSH call :trypwsh "%ProgramFiles%\PowerShell\7\pwsh.exe"
exit /b 0

:trypwsh
if not exist "%~1" exit /b 0
rem Asking its version starts PowerShell once more (a quarter of a second): not for the pwsh.exe already found recent
rem enough, known by its path, date and size (an update changes its date), kept in %APPDATA%\Repere\pwsh.txt between
rem asterisks, which no path has.
set "PWSH_STAMP=%~f1*%~t1*%~z1"
set "PWSH_CHECKED="
if exist "%APPDATA%\Repere\pwsh.txt" set /p PWSH_CHECKED=<"%APPDATA%\Repere\pwsh.txt"
if "%PWSH_CHECKED%"=="%PWSH_STAMP%" goto pwshok
rem Its version as pwsh -v says it ("PowerShell 7.5.4"): quicker than starting PowerShell to ask it. The path is
rem expanded by the command's own cmd, and call keeps that cmd from taking the path's quotes for its own, so a space,
rem a comma or a parenthesis in it does no harm.
set "PWSH_TRY=%~1"
set "PWSH_VERSION="
for /f "tokens=2" %%v in ('call "%%PWSH_TRY%%" -v 2^>nul') do set "PWSH_VERSION=%%v"
set "PWSH_MAJOR=0"
set "PWSH_MINOR=0"
for /f "tokens=1,2 delims=.-" %%a in ("%PWSH_VERSION%") do (
    set /a "PWSH_MAJOR=%%a" 2>nul
    set /a "PWSH_MINOR=%%b" 2>nul
)
if %PWSH_MAJOR% gtr 7 goto pwshnew
if %PWSH_MAJOR% equ 7 if %PWSH_MINOR% geq 5 goto pwshnew
if defined PWSH_VERSION set "PWSH_FOUND=%PWSH_VERSION%"
exit /b 0
:pwshnew
if not exist "%APPDATA%\Repere" mkdir "%APPDATA%\Repere" 2>nul
>"%APPDATA%\Repere\pwsh.txt" 2>nul echo %PWSH_STAMP%
:pwshok
set "PWSH=%~1"
exit /b 0

:findlanguage
rem REPERE_LANG: the language of the questions above, fr or en, as Repere would choose its own (Language.ps1): -Language
rem when the shortcut gives it, else the one saved in its settings, else French for someone who used it before, else
rem Windows's. Windows PowerShell, which every Windows has, reads it; French without it.
set "REPERE_LANG="
:nextargument
if "%~1"=="" goto checklanguage
if /i "%~1"=="-Language" set "REPERE_LANG=%~2"
if /i "%~1"=="-Language:fr" set "REPERE_LANG=fr"
if /i "%~1"=="-Language:en" set "REPERE_LANG=en"
shift
goto nextargument
:checklanguage
if /i "%REPERE_LANG%"=="fr" set "REPERE_LANG=fr"& exit /b 0
if /i "%REPERE_LANG%"=="en" set "REPERE_LANG=en"& exit /b 0
set "REPERE_LANG=fr"
for /f "delims=" %%l in ('powershell.exe -NoProfile -NonInteractive -Command "$folder = Join-Path $env:APPDATA 'Repere'; $choice = $null; try { $choice = (Get-Content -LiteralPath (Join-Path $folder 'parametres.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json).Language } catch { }; if ($null -eq $choice -and (Test-Path (Join-Path $folder '*.json'))) { $choice = 'fr' }; if ($choice -notin 'fr', 'en') { $choice = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') { 'fr' } else { 'en' } }; $choice" 2^>nul') do set "REPERE_LANG=%%l"
exit /b 0
