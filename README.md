# Windows PowerShell 7 Setup

An agent skill for Windows that detects the PowerShell the agent actually uses, installs PowerShell 7 (MSI) when the machine has no global install, switches the agent to it when it is installed-but-unused, and verifies the result. It also ships smart tooling for safe, low-token PowerShell usage on Windows.

Supported hosts: **Codex** (primary) and **CodeBuddy Code**. One skill, one set of scripts — host differences live in `skill/scripts/agent-context.ps1` and `skill/references/<host>-tools.md`.

## What it does

1. `check-powershell7.ps1` — decide, using **global** installs as the verdict: no global PS7 (install the MSI), global PS7 present but the agent is on 5.1 or on an agent-bundled copy (repoint it), or done. Prints the switch lever and a paste-ready value for the detected host.
2. `analyze-powershell-history.ps1` — scan agent run history for PowerShell errors (ParserError, PS7-only syntax on 5.1, sandbox/ACL denials, missing commands) and report remediation. `-Agent all` scans every host on the machine.
3. `srg.ps1` — safe ripgrep wrapper: argv passing (no shell escaping for spaces/Chinese/backslashes), bounded output, `-Literal`, `-OutFile`, `-Count`, `-Files`. Falls back to a host's vendored `rg.exe` when `rg` is not on PATH.

## Install

```powershell
powershell -File install.ps1              # auto-detect the running host
powershell -File install.ps1 -Agent all   # install for every host present
```

Destination is `<agent home>/skills/windows-powershell7-setup` — `$CODEX_HOME` or `~/.codex` for Codex, `$CODEBUDDY_CONFIG_DIR` or `~/.codebuddy` for CodeBuddy Code. Add `-Clean` to wipe the destination first instead of copying over it.

## Windows gotchas this skill encodes

- PowerShell 7 can be present without being installed globally: Codex ships its own at `%USERPROFILE%\.cache\codex-runtimes\*\dependencies\native\powershell\pwsh.exe`. Counting that as a global install reports a false "already done" and skips the install; it is private to that agent and vanishes on its next upgrade.
- `.ps1` files with non-ASCII **must** be UTF-8 with BOM, or PowerShell 5.1 decodes them in the ANSI code page and dies with `ParserError`.
- 5.1 writes stdout in the console code page, so agents charset-guess it and get it wrong on mostly-ASCII lines. `force-utf8-output.ps1` pins output to UTF-8.
- `&&`, `||`, `??`, `?.` and ternary are PowerShell 7 only. On 5.1 they raise `is not a valid statement separator in this version`.


## Layout

```text
.
├── install.ps1
├── skill/
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   ├── scripts/
│   │   ├── check-powershell7.ps1
│   │   ├── analyze-powershell-history.ps1
│   │   ├── srg.ps1
│   │   ├── pwsh-discovery.ps1       # global vs bundled PS7 discovery (no BOM: ASCII only)
│   │   ├── agent-context.ps1        # host detection + paths (no BOM: ASCII only)
│   │   └── force-utf8-output.ps1    # pin stdout to UTF-8 (no BOM: ASCII only)
│   └── references/
│       ├── install-powershell7.md
│       └── codebuddy-tools.md       # CodeBuddy Code path/setting mapping
├── README.md
└── LICENSE
```

## License
MIT — see [LICENSE](LICENSE).
