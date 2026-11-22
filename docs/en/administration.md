# Administration

*[Français](../fr/administration.md) · [Back to the README](../../README.en.md)*

To install Repère for a team, set it up, and know what it asks of the domain.

## Installing for a team

A release's zip holds everything needed: extract it to a shared folder or on each computer, and hand out a shortcut to **Repère.cmd**. Repère.cmd:

- finds a PowerShell 7.5 or later, and offers to install it with winget when there's none;
- unblocks the downloaded files, so that Windows doesn't refuse to run them;
- starts Repère without a console window.

Each person keeps their own settings (see below). Repère acts with the rights of whoever opens it: it needs no service account and nothing installed on the domain controllers.

## Launch options

They go in the shortcut's target, after `Repère.cmd`:

```
"C:\Tools\Repere\Repère.cmd" -Domains a.local,b.local
```

| Option | Effect |
|---|---|
| `-Domains a.local,b.local` | The domains offered. By default, the whole forest. |
| `-MoveRoots "OU=Workstations,DC=…;OU=Kiosks,DC=…"` | Limits **Move to…** to these OUs, instead of those in **Settings**. Handy for a shared shortcut. |
| `-Language fr` or `-Language en` | Repère in French or in English. Without it, Repère uses the language chosen in **Settings**, or Windows's on the first start. |
| `-NoUpdateCheck` | Doesn't look for a new version. |

A list is written without spaces after the commas.

## What the domain must allow

Repère needs no more rights than the console: each action works if your account can do it in *Active Directory Users and Computers*.

| To | You need |
|---|---|
| Search | to read AD (any domain user). |
| Edit the description, move, enable, disable, delete | the matching rights on the computer's OU. |
| BitLocker keys | to read BitLocker recovery information; deleting it needs the right to delete those objects. |
| LAPS password | to read these computers' LAPS password and, for encrypted Windows LAPS, to decrypt it. |
| Users: unlock, new password, groups | the rights delegated to support on these accounts and groups. |
| Remote tools, Specifications, Restart | to be an administrator of the computer. Specifications and Remote PowerShell use WinRM, or DCOM. |
| Next name with SCCM | the Configuration Manager console on the computer Repère runs on, and read access to SCCM. |

### WinRM

**Specifications**, **Remote PowerShell** and **Force policy update** go through WinRM. When it isn't on on the target computer, Repère offers to turn it on for the operation, then puts it back as it was. **Read over DCOM** reads the specifications without WinRM.

### Take control

You need to be an administrator of the computer, and:

- the policy *Set rules for remote control of Remote Desktop Services user sessions* (Computer Configuration › Administrative Templates › Windows Components › Remote Desktop Services › Remote Desktop Session Host › Connections);
- `AllowRemoteRPC = 1` (DWORD) in `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server`, to list the sessions;
- the *Remote Desktop - Shadow (TCP-In)* firewall rule.

## Where Repère keeps its settings

In `%APPDATA%\Repere`, one file per part, so that a damaged file only loses its own:

| File | Holds |
|---|---|
| `apparence.json` | the mode, the theme and your themes, the font, the text size, the density |
| `parametres.json` | **Move to**, the SCCM site, the language, and the last version started, to show **What's new** once per update |
| `recherche.json` | the domain, the search type and the recent searches |
| `redemarrage.json` | the delay and message of **Restart…** |
| `motdepasse.json` | the password choice, and the default password, encrypted for your Windows account |
| `prochainnom.json` | the recent patterns, the domains checked and the options of **Next name…** |
| `fenetre.json` | the window's size and place, and the page shown |

Deleting a file while Repère is closed puts its part back to the defaults. A file that can't be read is kept as it is, and set aside as `.illisible` at the next save.

## Updates

At startup, Repère asks GitHub for the latest release; if there's a newer one, a dot shows on **Settings**, with a link to download it. Nothing installs on its own: replace the folder with the new zip's, and the settings stay. `-NoUpdateCheck` turns this check off.

## For developers

The repository also holds what the zip doesn't:

- `src\FakeAD`: a sample AD to try Repère without a domain (`-FakeAD`, from the repository only);
- `tests`: the unit tests (Pester) and the UI tests (`Test-RepereUI.ps1`);
- `tests\Capture-Docs.ps1`: takes this documentation's screenshots again, in French and in English (`-Language en`);
- `tools\New-RepereRelease.ps1`: builds a release's zip and its notes, taken from the [changelog](../../CHANGELOG.md).
