# Install PowerShell 7 (MSI)

Only run when `scripts/check-powershell7.ps1` reports PowerShell 7 is not installed.

This downloads and installs software and needs network + elevation; request the user's approval first.

## Option A - winget (preferred)
winget install --id Microsoft.PowerShell --source winget

## Option B - direct MSI
Download the latest x64 MSI from the official GitHub releases:
https://github.com/PowerShell/PowerShell/releases/latest
(asset name like `PowerShell-7.4.x-win-x64.msi`), then run it.

## After install
- PowerShell 7 installs to `C:\Program Files\PowerShell\7\pwsh.exe`.
- Run `scripts/check-powershell7.ps1` again to confirm, and switch the agent to `pwsh` if it is still using 5.1.
