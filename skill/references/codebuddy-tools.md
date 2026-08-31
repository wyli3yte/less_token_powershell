# CodeBuddy Code adaptation

SKILL.md is written against Codex. On CodeBuddy Code, substitute the following. Everything
else in the skill applies unchanged.

| SKILL.md reference | CodeBuddy Code equivalent |
|---|---|
| `$CODEX_HOME`, `~/.codex` | `$CODEBUDDY_CONFIG_DIR`, `~/.codebuddy` |
| Skill install dir `$CODEX_HOME/skills/<name>` | `~/.codebuddy/skills/<name>` |
| Session logs `$CODEX_HOME/sessions/**/*.jsonl` | `~/.codebuddy/projects/<project-slug>/*.jsonl` — no `sessions/` level |
| Codex's bundled `pwsh.exe` | CodeBuddy Code bundles none. Its PowerShell tool auto-detects and lands on the **system** `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` (5.1, `Desktop`) |
| "Configure Codex to invoke `pwsh`" | Set `CODEBUDDY_POWERSHELL_PATH` to the pwsh 7 exe (takes priority over auto-detection), then restart the agent |
| `scripts/srg.ps1` | Prefer the built-in `Grep` tool — it is already ripgrep. Raw `rg` is **not on PATH**; it ships at `%APPDATA%\npm\node_modules\@tencent-ai\codebuddy-code\vendor\ripgrep\x64-win32\rg.exe`. `srg.ps1` falls back to that copy automatically |
| Codex sandbox denials (`deny-read ACLs`, `helper_unknown_error`) | `SANDBOX PERMISSION DENIED`; escalate with the tool's `dangerouslyDisableSandbox` (asks the user) rather than deleting sandbox state |

## The scripts are already host-aware

`scripts/agent-context.ps1` resolves the host and its paths, so no script is forked per platform:

```powershell
scripts\check-powershell7.ps1                        # -Agent auto (detects the running host)
scripts\analyze-powershell-history.ps1 -Agent all    # scan every host present on the machine
scripts\analyze-powershell-history.ps1 -Agent codebuddy -Days 7
scripts\srg.ps1 "pat" "dir" -RgPath <path-to-rg.exe> # only if auto-resolution misses
```

Detection order: `CODEBUDDY_SESSION_ID`/`CODEBUDDY_PROJECT_DIR` -> `CODEX_HOME` -> exe path ->
whichever home directory exists. `-CodexHome` still works as an alias of `-AgentHome`.

## Why 5.1 is the default here

Because the PowerShell tool resolves to the system executable, the Windows PowerShell 5.1
hazards are the **default** on CodeBuddy Code, not an edge case:

- No `&&`, `||`, `??`, `?.`, or ternary. Use `;` and `if ($?) { ... }`. Signature of getting this
  wrong: `is not a valid statement separator in this version` / `不是此版本中的有效语句分隔符`.
- `.ps1` files containing non-ASCII **must** be UTF-8 with BOM. Without it, 5.1 decodes them in
  the ANSI code page and dies with `ParserError` / `MissingEndCurlyBrace`.
- 5.1 writes stdout in the console code page (CP936 on a zh-CN box), which the agent then has to
  charset-guess — and it guesses wrong on lines that are mostly ASCII with a few CJK bytes. Every
  user-facing script here dot-sources `scripts/force-utf8-output.ps1` to pin output to UTF-8.

Installing PowerShell 7 removes all three. Until then, treat them as standing constraints.

## Switching to PowerShell 7 without installing anything

If Codex is also on this machine, its bundled pwsh 7 is a valid target — no MSI download needed:

```powershell
# Discover it (check-powershell7.ps1 prints this line ready to paste)
scripts\check-powershell7.ps1

# Then set the override and restart the agent
setx CODEBUDDY_POWERSHELL_PATH "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
```

Trade-off: that directory is Codex's runtime cache. It is versioned (`codex-primary-runtime`) and
can be replaced or pruned when Codex upgrades, which would leave `CODEBUDDY_POWERSHELL_PATH`
pointing at nothing. Use it to unblock immediately; install the system MSI for a stable path.


## Documented environment variables

| Variable | Effect |
|---|---|
| `CODEBUDDY_POWERSHELL_PATH` | Explicit PowerShell exe path; wins over auto-detection. This is the "switch the agent to pwsh" lever |
| `CODEBUDDY_USE_POWERSHELL_TOOL` | `0` disables the PowerShell tool (enabled by default on Windows) |
| `CODEBUDDY_CONFIG_DIR` | Relocates config/data, i.e. the `~/.codebuddy` equivalent of `CODEX_HOME` |
| `USE_BUILTIN_RIPGREP` | `0` uses a system `rg` instead of the bundled one |
| `CODEBUDDY_CODE_SHELL` | Overrides shell auto-detection (`bash`, `zsh`, `sh`, `powershell`) |
