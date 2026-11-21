# Troubleshooting

*[Français](../fr/depannage.md) · [Back to the README](../../README.en.md)*

What Repère's messages mean, and what to do.

## At startup

**"Repère requires PowerShell 7.5 or later"**
Repère.cmd offers to install it with winget: answer **O** (Oui, yes). Without winget, install PowerShell 7.5 yourself (`winget install --id Microsoft.PowerShell --source winget`, or from the Microsoft Store), then start Repère.cmd again.

**"ActiveDirectory module not found"**
Install the RSAT tools for Active Directory. On Windows 10 and 11: Settings › System › Optional features › Add a feature › *RSAT: Active Directory Domain Services tools*.

**"This computer isn't joined to a domain"**
Repère needs Active Directory: open it on a computer in the domain.

**"WMI isn't answering"**
Repère can't tell whether the computer is joined to a domain. Restarting the *Windows Management Instrumentation* service (Winmgmt), or the computer, often fixes it.

**"Unknown launch option"**
The shortcut's target holds an option Repère doesn't know, or a list with spaces. Write `-Domains a.local,b.local`, with no space after the commas. The options are in [Administration](administration.md#launch-options).

**Nothing opens after the double-click**
The first start after Windows starts can take about fifteen seconds; Repère's startup screen shows meanwhile. If it doesn't show, run Repère.cmd from a command prompt to see the message.

**The startup screen's bar doesn't move**
Windows's animations are turned off (Settings › Accessibility › Visual effects). Over Remote Desktop, Windows turns them off too unless the connection is fast: in Remote Desktop Connection, **Show Options › Experience**, choose **LAN (10 Mbps or higher)** or check **Menu and window animation**.

## Searching

**"No computers found"**
The message says where Repère searched. Try **Search all domains**, check the search type (**Name contains** or **Description contains**), or **Remove the advanced criteria** if **Advanced** is on.

**"Narrow the search, or Show all"**
The search found more results than the limit. Add letters, or click **Show all**: the same search, without a limit, may take a while.

**"No answer from…" or "Search canceled"**
A domain or domain controller didn't answer in time. The other domains' results still show; search again with F5.

**A name from the list isn't found**
Names not found show above the results, with **Copy**. Search for them without a domain (`ORD-01`, not `DEMO\ORD-01$`), or in **All domains**.

## Acting on a computer

**"Off or unreachable"**
The computer doesn't answer ping: it's off, off the network, or a firewall blocks it. **Check online** tests it again.

**Specifications or Remote PowerShell: "WinRM"**
WinRM isn't on on the computer. Repère offers to turn it on for the operation, then puts it back as it was. For Specifications, **Read over DCOM** reads without WinRM, more slowly.

**"Access denied"**
Your account isn't allowed to do this on that computer or in that OU. Repère acts with your rights: ask your domain administrator for them.

**Take control doesn't work**
Take control needs settings in the domain: see [Administration](administration.md#take-control).

**No BitLocker key, or no LAPS password**
A notification says so. Either AD has none for this computer, or your account isn't allowed to read them. An encrypted Windows LAPS password also needs the right to decrypt it.

**"Left out"**
Repère never disables, deletes or moves a domain controller, or the computer it runs on. A computer protected from accidental deletion isn't moved.

**Next name: "Couldn't check SCCM"**
The SCCM site isn't set, the Configuration Manager console is missing on this computer, or your account can't read SCCM. The reason is shown; **Settings › SCCM › Test** helps find which. The names offered then come from AD alone.

## Settings

**"parametres.json" can't be read**
The file was edited by hand and has a mistake. Repère keeps it as it is and uses the defaults. Fix it in `%APPDATA%\Repere`, or save a setting: the file is then set aside as `parametres.json.illisible`.

**Repère is in French (or English) and you want the other language**
**Settings › Appearance › Language**, or the `-Language en` or `-Language fr` launch option.

**Get the default window, themes or searches back**
Close Repère and delete the matching file in `%APPDATA%\Repere` (see [Administration](administration.md#where-repère-keeps-its-settings)).

## Anything else?

Open an issue in the [Issues](https://github.com/reperedev/Repere/issues), with the exact message and what you were doing.
