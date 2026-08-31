# Codex Windows PowerShell 7 Setup

A Codex skill for Windows that detects the PowerShell the agent actually uses, installs PowerShell 7 (MSI) when missing, switches the agent to it when it is installed-but-unused, and verifies the result. It also ships smart tooling for safe, low-token PowerShell usage on Windows.

## What it does

1. `check-powershell7.ps1` — decide: is the agent already on PowerShell 7? If not, is PS7 installed-but-unused (switch the shell) or not-installed (install the MSI)?
2. `analyze-powershell-history.ps1` — scan the agent's local run history for PowerShell errors (ParserError, sandbox/ACL denials, missing commands) and report remediation.
3. `srg.ps1` — safe ripgrep wrapper: argv passing (no shell escaping for spaces/Chinese/backslashes), bounded output, `-Literal`, `-OutFile`, `-Count`, `-Files`.

## Install

```powershell
powershell -File install.ps1
```

This copies the skill into `$CODEX_HOME/skills/windows-powershell7-setup` (or `~/.codex/skills/...`).

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
│   │   └── srg.ps1
│   └── references/install-powershell7.md
├── README.md
└── LICENSE
```

## License
MIT — see [LICENSE](LICENSE).
