# Install PowerShell 7 (MSI)

Run when `scripts/check-powershell7.ps1` reports `global : 否`. A `bundled :` path does **not**
satisfy this skill and does not let you skip the install — it is private to one agent's runtime
cache and disappears when that agent upgrades. At most it is a stopgap to unblock the current agent.

This downloads and installs software and needs network + elevation; request the user's approval first.

## Option A - direct MSI
Download the latest x64 MSI from the official GitHub releases:
https://github.com/PowerShell/PowerShell/releases/latest
(asset name like `PowerShell-7.4.x-win-x64.msi`), then run it.

## Option B - winget
```
winget install --id Microsoft.PowerShell --source winget
```
Use `--source winget` as shown: it installs the same machine-wide MSI. The Microsoft Store variant
lands in `%LOCALAPPDATA%\Microsoft\WindowsApps` as a user-scope app instead.

## After install
- PowerShell 7 installs to `C:\Program Files\PowerShell\7\pwsh.exe`.
- Re-run `scripts/check-powershell7.ps1` — it must now report a `global :` path with `scope=machine`.
- Then switch the agent to `pwsh` and re-run the check. Installing the MSI does not by itself change
  which exe the agent launches.
