---
name: windows-powershell7-setup
description: Detect the PowerShell actually used by Codex on Windows, install PowerShell 7 via MSI when missing, switch the agent to it when it is installed but unused, then verify. Use when asked to check/upgrade the PowerShell version, when a Windows command behaves unexpectedly, or when an agent must confirm it runs PowerShell 7.
---

# Windows PowerShell 7 Setup

## Purpose
On Windows "PowerShell" is ambiguous: the system default `powershell.exe` is Windows PowerShell 5.1 (edition `Desktop`), while modern tooling wants PowerShell 7 (`pwsh`, edition `Core`). Detect what the agent actually runs, then make it use PowerShell 7 and verify.

## Decision order (check the agent first, not the system)
1. Check what the agent itself runs: `scripts/check-powershell7.ps1`. It prints the agent's shell version/edition/path, whether PowerShell 7 is installed locally, and the next action.
2. If the agent is already PowerShell 7 (Core) -> done.
3. If the agent is NOT PowerShell 7:
   - PowerShell 7 already installed but unused -> switch the agent to `pwsh`, then verify.
   - PowerShell 7 not installed -> install it (see `references/install-powershell7.md`), then verify.
4. Verify: re-run `scripts/check-powershell7.ps1` until it reports PowerShell 7 (Core).

## Switch the agent to pwsh (installed but unused)
- Ensure `pwsh` is on PATH ahead of `powershell.exe`; confirm with `Get-Command pwsh`.
- Configure Codex to invoke `pwsh` rather than `powershell` (the exact setting varies by Codex version; the agent here already uses its bundled `pwsh.exe`).
- Re-run the check script to confirm.

## Smart tooling (scripts/)
- `scripts/check-powershell7.ps1` — version detection + next-action decision.
- `scripts/analyze-powershell-history.ps1` — scan the agent's local run history for PowerShell errors and token waste.
- `scripts/srg.ps1` — safe ripgrep wrapper (argv passing, no shell escaping, bounded output).

## Key facts
- PowerShell 7 reports `$PSVersionTable.PSEdition -eq 'Core'`; 5.1 reports `Desktop`.
- Standard MSI path: `C:\Program Files\PowerShell\7\pwsh.exe`; winget path: `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`.
- Codex's exec often uses its own bundled `pwsh.exe` (under `codex-primary-runtime\dependencies\native\powershell\pwsh.exe`); that is the shell the agent actually uses.

## Constraints
- Detection/analysis scripts are read-only; run them freely.
- Installing software or switching the shell needs approval + network; request approval first.
