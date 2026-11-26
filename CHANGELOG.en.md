# Changelog

Versions before 0.15.1 are described in French only, in [CHANGELOG.md](CHANGELOG.md).

## 0.16.0 — coming soon

### Computers, Users and Groups
- **The window no longer freezes during a change**: unlocking, **New password…**, enabling or disabling, adding or removing groups, **Save** in **Properties** and deleting BitLocker keys run in the background. You can keep searching; the same action started again on the same accounts meanwhile is ignored.
  - A domain controller that doesn't answer within 45 seconds is no longer waited for: the report says "may have been made, check", in orange, rather than a failure, because the change may have gone through.
- **A domain that doesn't answer no longer stops the search**: without an answer after 20 seconds, it's left out, the other domains are shown and the count says "(no answer: 1)", with the domain in the tooltip. A controller that has started answering has no limit, even with **Show all**.
  - **Properties**, **LAPS password** and **BitLocker keys** say the same after 30 seconds, instead of waiting without end.
- **Export and Copy rows follow the grid**: the columns shown, in their order, under their headers, and the distinguished name last. A hidden column is no longer exported: by default, **Email** on Users and **Managed by** on Groups.
- **Windows errors are understood in every language**: access denied, computer unreachable, WinRM closed or SCCM site not found are recognized by their code, no longer only by their French or English text.
- **SCCM**: "Not in SCCM" becomes "Free in SCCM (with your access)", because SCCM may hide computers from your account. **Settings › SCCM › Test** also says whether this computer's inventory can be read, and through which server the site answers when it isn't the one in Settings. The console is loaded only once: the next checks are faster.
- **Next name…** no longer asks SCCM for the whole series, only for the names it's about to offer: the console stopped its answer at 1,000 computers, and a large series could make a name SCCM had look free. A name SCCM has is skipped, without changing where the series goes on from, and the count line counts AD's names only.
- **What's new is in English** when Repère is, from this version on, as are the launcher's questions (PowerShell 7.5 missing) and the console's messages.

### Computers
- **Disable** and **Move to…** again leave out a domain controller, or the computer Repère runs on, when several computers are selected: they were only spared when selected alone.
- **Export** gives **Online** and the IP address when the column is shown, the location as the grid shows it (`Postes › Communs`) and the exact date of the last logon. The file it suggests is named after the domain searched, `Repere_computers_demo.local_2026-11-24.csv`, or after none when there were several.
- **A Windows release newer than Repère** shows by its number ("Windows 11 (build 26300)"), without an alert or a color: the tooltip and **Specifications** say that its end of support isn't known yet.
- **Windows 10 22H2**: the end-of-support alert reminds you that a computer enrolled in Extended Security Updates (ESU) still gets security updates.
- **A `*` in a description search is a star**, and no longer any text. A `\` is found too.

## 0.15.1 — 2026-11-23

### Computers, Users and Groups
- **What's new**: a window sums up what changed the first time a new version starts. **Settings › What's new** opens it again.
- **The window opens in the center of the mouse's screen**, in front of other programs, at its usual size.
- **The search time's tooltip** gives one domain per line, with the times aligned.

### Computers
- **Properties…** (right-click › Active Directory, or Alt+Enter): a computer's AD properties, even when it's off. You can change the description, the state, the OU, the location, **Managed by**, the groups and the protection from deletion there.
- **Next name…** and **Settings › SCCM** say in one line when to update the Configuration Manager console.

### Users
- **The new password is hidden** after **New password…**: the eye shows it, **Copy** copies it.

### Users and Groups
- **Properties**: past 10 groups, a box filters **Groups** and **Member of** by name or description.
