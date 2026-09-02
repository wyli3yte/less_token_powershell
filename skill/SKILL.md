---
name: less-token-powershell
description: Use when a Windows command fails with ParserError, MissingEndCurlyBrace, 'is not a valid statement separator in this version' / '不是此版本中的有效语句分隔符', or Exit Code 1 despite working in a terminal; when an agent must confirm whether it runs PowerShell 7 (Core) or 5.1 (Desktop); when PS7-only syntax (&&, ||, ??, ternary) behaves differently in the agent; or when asked to check, install or switch PowerShell on Windows.
---

# Less PowerShell Token Tax

## Purpose
On Windows "PowerShell" is ambiguous: the system default `powershell.exe` is Windows PowerShell 5.1 (edition `Desktop`), while modern tooling wants PowerShell 7 (`pwsh`, edition `Core`). Every PS7-only command that fails on 5.1 is a round-trip that costs tokens and returns nothing, so the point is not tidiness — it is removing a recurring, per-session tax.

The goal is a **global** PowerShell 7 — one install that serves every agent and every terminal — and then an agent that actually uses it.

## Announce on trigger
Open the **first** reply of an activation with one line, then answer normally:
`[less-token-powershell] 触发: <what you saw> — <one-line conclusion>`
Only when the skill actually does something (detect, install, switch, measure). Skip it on later
turns and when you are merely answering a PowerShell question. ~15 tokens, once, versus thousands
per retry it prevents.

## Platform adaptation
This document is written against Codex paths and settings. The scripts themselves are host-aware
(`-Agent auto|codex|codebuddy|claude|all`, resolved by `scripts/agent-context.ps1`), so do not fork them.
For another host, read its mapping file and substitute:

- CodeBuddy Code -> `references/codebuddy-tools.md`
- Claude Code -> `references/claude-tools.md`

## Decision order
1. Run `scripts/check-powershell7.ps1`. It prints the agent's own shell, every **global** PowerShell 7 (this is the verdict), any **agent-bundled** copy (reference only), and the next action.
2. No global PowerShell 7 -> install it (`references/install-powershell7.md`). A bundled copy does not count as done: it lives in one agent's runtime cache and vanishes when that agent upgrades. Point the current agent at it if you need to unblock work now, but still install.
3. Global PowerShell 7 exists, agent still on 5.1 -> switch the agent to it.
4. Global PowerShell 7 exists, agent on a bundled copy -> repoint the agent at the global path.
5. Verify: re-run the check until it reports a `global :` path *and* the agent is PowerShell 7 (Core).

## Switch the agent to pwsh (installed but unused)
- Point the agent's shell setting at the pwsh 7 exe rather than `powershell.exe`. The setting is
  host-specific: Codex varies by version (its exec already launches a bundled `pwsh.exe`);
  CodeBuddy Code uses `CODEBUDDY_POWERSHELL_PATH`. `check-powershell7.ps1` prints the right lever
  and a ready-to-paste value for the detected host.
- Putting `pwsh` on PATH ahead of `powershell.exe` also helps, but it is not sufficient: a host
  that resolves an absolute exe path ignores PATH order entirely.
- Re-run the check script to confirm.


## Smart tooling (scripts/)
- `scripts/check-powershell7.ps1` — version detection + next-action decision, host-aware.
- `scripts/pwsh-discovery.ps1` — library: `Get-GlobalPwshPath` / `Get-BundledPwshPath` / `Get-PwshVersion`. Global and bundled are discovered separately and never merged.
- `scripts/analyze-powershell-history.ps1` — scan agent run history for PowerShell errors and token waste. `-Agent all` covers every host on the machine; `-Days N` bounds the window.
- `-Tokens` (opt-in, off by default) adds a token ledger measured from the transcripts' real `usage` fields — not an estimate. It streams JSON, so a big codex tree takes minutes; `-MaxFileMB 256` (default) skips huge files and says so, `-MaxFileMB 0` forces them. Output grows by ~270 tokens and surfaces the waste it measures.
- `scripts/srg.ps1` — safe ripgrep wrapper (argv passing, no shell escaping, bounded output). Resolves `rg` from PATH, then from a host's vendored copy.
- `scripts/token-attribution.ps1` — library: `Test-PsFailureLine` / `Get-TokenAttribution` / `Get-SkillSelfCost`. Turns transcripts into a token ledger. Host usage fields differ (codex per-turn delta, claude per request, codebuddy **cumulative counter** that must be diffed, never summed).
- `scripts/agent-context.ps1` — library: which host is running, and where its skills/logs live. All host-specific paths live here. Also `Write-SkillBanner`, the one-line marker the scripts print; silence it with `LESS_TOKEN_POWERSHELL_QUIET=1`.
- `scripts/force-utf8-output.ps1` — library: pins stdout to UTF-8 so 5.1 output does not get charset-guessed.

## Key facts
- PowerShell 7 reports `$PSVersionTable.PSEdition -eq 'Core'`; 5.1 reports `Desktop`.
- Standard MSI path (machine scope): `C:\Program Files\PowerShell\7\pwsh.exe`. `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` is the Store/user-scope variant.
- **PowerShell 7 can exist on the machine without being installed globally.** Some agents ship their own copy; Codex's lives at `%USERPROFILE%\.cache\codex-runtimes\*\dependencies\native\powershell\pwsh.exe` (measured: v7.6.4). Counting it as a global install produces a false "already done" verdict and skips the install that this skill exists to perform. `Get-BundledPwshPath` in `scripts/pwsh-discovery.ps1` holds these locations, kept apart from `Get-GlobalPwshPath`.
- The shell the agent actually uses is host-specific: Codex's exec launches its bundled `pwsh.exe`, whereas CodeBuddy Code auto-detects and lands on the system 5.1. Two agents on one machine can therefore disagree about "the" PowerShell version. Always trust `check-powershell7.ps1` over assumptions.

- A `.ps1` containing non-ASCII must be saved as **UTF-8 with BOM**. Without the BOM, 5.1 decodes it in the ANSI code page and fails with `ParserError` / `MissingEndCurlyBrace` — including the scripts meant to diagnose 5.1.
- 5.1 writes stdout in the console code page, not UTF-8. Dot-source `scripts/force-utf8-output.ps1` in any script that prints non-ASCII.
- Run these scripts **in-process** (`& script.ps1`), not as `powershell.exe -File script.ps1 | ...`. A 5.1 child writes UTF-8, but a parent session still on CP936 mis-decodes those redirected bytes and the report comes back as mojibake — the very charset-guessing this skill exists to end. A global PS7 is what makes the in-process path the default.
- `is not a valid statement separator in this version` (zh-CN: `不是此版本中的有效语句分隔符`) is the signature of PS7-only syntax (`&&`, `||`, `??`, ternary) running on 5.1 — a direct trigger for this skill.

## Constraints
- Detection/analysis scripts are read-only; run them freely.
- Installing software or switching the shell needs approval + network; request approval first.
- Deleting a host's sandbox/ACL state file to force a rebuild is destructive; confirm with the user before doing it.

