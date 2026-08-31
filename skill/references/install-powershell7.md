# Install PowerShell 7 (MSI)

Run when `scripts/check-powershell7.ps1` reports `global : 否`. A `bundled :` path does **not**
satisfy this skill and does not let you skip the install — it is private to one agent's runtime
cache and disappears when that agent upgrades. At most it is a stopgap to unblock the current agent.

This downloads and installs software and needs network + elevation; request the user's approval first.

## Option A - direct MSI (preferred)
Get the x64 MSI from the official releases: https://github.com/PowerShell/PowerShell/releases/latest
(asset `PowerShell-<ver>-win-x64.msi`). Each release also publishes a SHA256 per asset — check it.
Then run the MSI elevated. From China this download is often ~100 KB/s; it supports HTTP Range, so
resume rather than restarting.

## Option B - winget (check the installer type first)
```
winget show --id Microsoft.PowerShell --source winget
winget install --id Microsoft.PowerShell --source winget
```
Measured 2026-09-01: the `Microsoft.PowerShell` manifest at 7.6.5 ships **only** an `msixbundle`, so
this installs the MSIX and not the MSI, and `--installer-type msi` answers "no applicable installer".
Run `winget show` first instead of assuming winget gives you an MSI.

## MSI vs MSIX, and why this skill wants the MSI
| | MSI | MSIX/Store |
|---|---|---|
| exe path | `C:\Program Files\PowerShell\7\pwsh.exe`, no version in it | `C:\Program Files\WindowsApps\Microsoft.PowerShell_<ver>_x64__8wekyb3d8bbwe\pwsh.exe`, moves on every update |
| reachable as `pwsh` | real exe on PATH | only via the execution alias `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, which Windows can drop |
| scope | machine | per-user |
| uninstall entry | yes | none |

A host's shell setting stores an absolute path, so the MSI's stable version-less path is what you
want. If you are stuck on the MSIX, point at the alias, not the versioned directory.

## After install
- Re-run `scripts/check-powershell7.ps1` — it must report a `global :` path with `scope=machine`.
- Then switch the agent to `pwsh` and re-run the check. Installing the MSI does not by itself change
  which exe the agent launches.
- To drop a superseded MSIX afterwards: `Get-AppxPackage -Name Microsoft.PowerShell | Remove-AppxPackage`.
