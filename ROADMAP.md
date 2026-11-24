# Roadmap

What Repère needs to grow from a helpdesk console into an IT asset management tool, while staying agentless and
without a database of its own. From the review of 0.15.1 (2026-11-23).

How to use this file: tick an item when it ships, and add the version or PR after it, for example
`- [x] **P1** … — 0.16.0 (#14)`. Each item has an ID, so commits, PRs and the changelog can name it. Items stay in
place once done, so the IDs don't move.

**Start with:** M1 (audit log), then I2 (Specifications over a selection).

## Polish: rough edges in what exists

- [x] **P1. No frozen window on user writes.** Unlock, New password and Enable/Disable
  ([UserPage.ps1:612](src/UserPage.ps1:612), :842), BitLocker key deletion
  ([BitLockerDialog.ps1:277](src/BitLockerDialog.ps1:277)) and the PDC lookup
  ([UserDetails.ps1:1747](src/UserDetails.ps1:1747)) run on the window's thread: a slow DC hangs the window. Move them
  to the background, as computer writes already are.
  - Done in 0.16.0 (branch `polish-p1-p7`): user, computer and group writes, BitLocker deletion and the PDC lookup.
    Still on the window's thread: two reads, `Get-GroupServerMap` and the privileged-group check in Add members.
- [x] **P2. A timeout on AD searches and background reads.** Only actions on remote computers have one
  (`Start-BackgroundAction`). An unreachable domain waits for the AD defaults or for Esc.
  - Done in 0.16.0 (branch `polish-p1-p7`): searches 20 s without an answer, reads 30 s, writes 45 s + 5 s per
    object, with "may have been made, check" on a write.
- [ ] **P3. Faster name search on large domains.** The name box always runs `Name -like '*x*'`
  ([ComputerPage.ps1:889](src/ComputerPage.ps1:889)), which AD can't use its index for. The same goes for
  descriptions, groups ([GroupPage.ps1:15](src/GroupPage.ps1:15)) and BitLocker IDs
  ([ComputerPage.ps1:700](src/ComputerPage.ps1:700)). Make "starts with" the default, keep "contains" as a choice, and
  fix the header comment of ComputerPage.ps1, which says "start of their name".
- [x] **P4. Export follows the grid.** Export always writes the same 9 columns
  ([ComputerPage.ps1:1435](src/ComputerPage.ps1:1435)), never **Online** or the IP. Export the columns shown, in their
  order.
  - Done in 0.16.0 (branch `polish-p1-p7`): on all three pages, for Export and Copy rows, the DN always last.
- [ ] **P5. Honest last logon.** `lastLogonTimestamp` lags by up to about 14 days, so "today" or "yesterday" says more
  than AD knows. Show "less than 2 weeks" under that.
- [x] **P6. Windows support table.** [PCSpecs.ps1:978](src/PCSpecs.ps1:978) is maintained by hand. A build newer than
  the table is never flagged, and Windows 10 ESU is ignored. At least flag an unknown newer build as "to check", and
  add a release-checklist step to update the table.
  - Done in 0.16.0 (branch `polish-p1-p7`): a newer build shows neutrally with its number, 22H2 notes ESU, and
    `New-RepereRelease.ps1` warns when the newest release has under 12 months of support left.
  - [ ] Still to do: add the next Windows 11 release (26H2?) with its official dates. The warning already fires.
- [x] **P7. Errors recognised by code, not text.** Some errors are matched by their French or English message
  ([ComputerActions.ps1:674](src/ComputerActions.ps1:674), [NextName.ps1:318](src/NextName.ps1:318)), which partly
  breaks on Windows in another language. Match HRESULTs or error IDs.
  - Done in 0.16.0 (branch `polish-p1-p7`): `Get-ErrorKind` (Errors.ps1). Still text-based, with no code to use:
    quser's "No User exists", SCCM's "new version of the console", and `ConvertTo-FrenchError`, which only rewords.
- [ ] **P8. No French left in English mode.** The Repère.cmd prompts (including the O/N `choice`), the changelog
  (French only), PCSpecs run on its own, and the console `Write-Host` messages.
- [ ] **P9. Trustworthy releases.** Sign the scripts (Authenticode), or at least put the SHA-256 that
  `tools/New-RepereRelease.ps1` already prints into the release notes. Repère.cmd unblocks the whole folder on first
  launch.
- [ ] **P10. More tests in CI.** Run `tests/Test-RepereUI.ps1` in CI, and add unit tests for `Set-UserPassword`,
  `Invoke-ComputerWrite`, `Get-LapsPassword` and `ConvertTo-FrenchError`.
- [ ] **P11. Small things.** A `*` typed into a description search acts as a wildcard
  ([ComputerPage.ps1:886](src/ComputerPage.ps1:886)). The host name is put unquoted into the remote PowerShell
  command ([ComputerActions.ps1:1040](src/ComputerActions.ps1:1040)). A computer row's `OU` property holds its DN
  ([ComputerPage.ps1:408](src/ComputerPage.ps1:408)). The export file name uses the translated "All domains".

## Improve: existing features

- [ ] **I1. More in Specifications.** TPM (present, version, ready), Secure Boot, BitLocker state on the device,
  patch level (UBR) and last hotfix, OS install date, local administrators, disk health, Windows 11 readiness, system
  UUID. One CIM query each, over the WinRM/DCOM path that exists.
- [ ] **I2. Specifications over a selection.** The action needs exactly one computer
  ([ComputerActions.ps1:403](src/ComputerActions.ps1:403)). Read many at once with the 48-at-a-time parallel loop the
  online check already uses, with progress and cancel, and show the result as a table to export as CSV. This also
  answers "which PCs have program X installed?". The biggest step toward inventory.
- [ ] **I3. More AD columns.** whenCreated, pwdLastSet, ManagedBy, Location, LAPS presence and expiry, BitLocker key
  count, out of support. Some cost about 20 ms per computer
  ([ComputerPage.ps1:725](src/ComputerPage.ps1:725)): read them only when their column is shown or a filter uses them.
- [ ] **I4. More advanced-search criteria.** Created before/after, password not changed for N days, has/no LAPS,
  has/no BitLocker key, ManagedBy, out of support, servers or DCs only, member of a group, OS build.
- [ ] **I5. A user's computers from better sources.** Today it only matches the user's name in computer descriptions
  ([ComputerPage.ps1:946](src/ComputerPage.ps1:946)). Add ManagedBy, SCCM user-device affinity and the last user
  Specifications saw.
- [ ] **I6. SCCM inventory.** SCCM is used only to check whether a name is taken
  ([NextName.ps1:277](src/NextName.ps1:277)). Read its hardware and software inventory (SMS_G_System_*) for computers
  that are off, from an agent that's already deployed.
- [ ] **I7. Group members.** Lists stop at 200 ([GroupDetails.ps1:14](src/GroupDetails.ps1:14)) and nested groups
  open one level at a time. Add a full recursive view and a members export.
- [ ] **I8. User searches done by AD.** "Inactive for N days" and "password expires within N days" as search criteria,
  not only as a filter on the first 2000 results.

## Missing: new features, by priority

- [ ] **M1. Audit log.** Nothing is recorded today, not even LAPS or BitLocker reveals
  ([LapsDialog.ps1:32](src/LapsDialog.ps1:32)). An append-only JSON-lines log of who, what, when, on which object,
  and the value before the change: locally, optionally in a shared folder, and in the event log. A window to read it.
- [ ] **M2. Undo** for description edits, moves and group changes, from the audit log's "before" values.
- [ ] **M3. Alternate credentials.** Run with a separate admin account (`-Credential`, or a prompt at startup)
  instead of `runas` on Repère.cmd.
- [ ] **M4. Headless reports.** For example `-Report Stale -Output x.csv`, from the same search engine, to run as a
  scheduled task.
- [ ] **M5. Snapshots without a database.** Save inventory exports (I2) to a folder and compare two of them: hardware
  changed, software added or removed, computers gone.
- [ ] **M6. Stale-computer workflow.** Find, disable, stamp the description with who and when, move to a quarantine
  OU, then delete after N days.
- [ ] **M7. Reconciliation.** In AD but not in DNS, DNS records without a computer, in SCCM but not in AD (and the
  reverse), the same name in several domains.
- [ ] **M8. Team configuration.** A shared settings path or a policy (registry/GPO) for Move to, SCCM, the restart
  message and saved searches, instead of each user's `%APPDATA%` only.
- [ ] **M9. Your own actions.** PowerShell scripts that admins add to the right-click menu, with tokens such as
  `{ComputerName}` and `{DistinguishedName}`.
- [ ] **M10. Summary counts.** Computers per OS, out of support, stale, per OU or domain.
