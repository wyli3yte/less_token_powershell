# Windows PowerShell 7 Setup

**Your agent is probably running Windows PowerShell 5.1 right now** — quietly failing on `&&`, `??` and UTF-8 output.

This skill detects the PowerShell your agent actually uses, gets a **global** PowerShell 7 onto the machine, switches the agent onto it, and verifies the result.

```text
before   标记"&&"不是此版本中的有效语句分隔符。      <- ParserError on 5.1
after    7.6.5 / Core                                <- same command, global pwsh 7
```

## Highlights

- **One install, every agent and every terminal.** It targets a *global* pwsh 7, not one agent's private copy.
- **It won't call a bundled copy "done."** Codex ships its own pwsh 7; that copy vanishes when Codex upgrades, so it's reported as reference only.
- **It prints the next action**, with a paste-ready value for *your* host: install, switch, or done.
- **One skill, three hosts.** Codex, CodeBuddy Code and Claude Code share a single copy — host differences live in one library, no forks.
- **It measures what 5.1 already cost you.** Scans past sessions for ParserError and PS7-syntax-on-5.1 failures across every host.
- **It ships safe Windows tooling.** `srg.ps1` passes argv instead of shell-escaping, so spaces, CJK and backslashes stop breaking searches.

## Install

```powershell
powershell -File install.ps1              # every host present on the machine
powershell -File install.ps1 -Agent auto  # only the host running this process
```

| Host | Installed to | Shell override it prints |
|---|---|---|
| Codex | `$CODEX_HOME/skills/...` (`~/.codex`) | none needed — its exec already launches pwsh |
| CodeBuddy Code | `~/.codebuddy/skills/...` | `CODEBUDDY_POWERSHELL_PATH` |
| Claude Code | `~/.claude/skills/...` | none — its Bash tool is Git Bash; it benefits from pwsh 7 on PATH |

Add `-Clean` to wipe the destination before copying (destructive).

## Verify in one command

```powershell
powershell -File skill\scripts\check-powershell7.ps1
```

It prints the agent's own shell, every **global** pwsh 7 (the verdict), any **bundled** copy (reference only), and the next action:

```text
=== 1) Agent 实际使用的 shell(本进程) ===
Agent  : codebuddy
Version: 7.6.5
Edition: Core
ExePath: C:\Program Files\PowerShell\7\pwsh.exe
FileVer: 7.6.5.500
=== 2) 全局 PowerShell 7 (判定依据) ===
global  : C:\Program Files\PowerShell\7\pwsh.exe  (v7.6.5)  [scope=machine, via=machine-path]
=== 2b) agent 私有副本(仅参考，不算全局) ===
bundled : C:\Users\<user>\.cache\codex-runtimes\...\pwsh.exe  (v7.6.4)
=== 3) 判断 ===
NEXT: 已是全局 PowerShell 7 (Core)，无需处理。
```

Only a `global :` path counts as done. Anything else prints the exact command to fix it.

## The scripts

| Script | Reach for it when |
|---|---|
| `check-powershell7.ps1` | You need the verdict: missing → install, installed-but-unused → switch, or done. |
| `analyze-powershell-history.ps1` | You want to know what 5.1 already cost you. `-Agent all -Days 30` scans every host. |
| `srg.ps1` | You need ripgrep with argv passing and bounded output: `-Literal`, `-OutFile`, `-Count`, `-Files`. |

All three take `-Agent auto|codex|codebuddy|claude|all`, and all three run on 5.1 themselves — that is the point.

## Proof: before and after on a real machine

Captured 2026-09-02 on Windows 11 with all three hosts present. Same probes, run before and after.

### Without the skill

```powershell
powershell.exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString() + " / " + $PSVersionTable.PSEdition'
# 5.1.26100.9168 / Desktop

powershell.exe -NoProfile -Command "1 -eq 1 && 'ok'"
# 标记"&&"不是此版本中的有效语句分隔符。   ("&&" is not a valid statement separator — ParserError)
```

What that cost in real sessions:

```powershell
powershell -File skill\scripts\analyze-powershell-history.ps1 -Agent all -Days 30
```

```text
=== [codex] PowerShell 历史问题扫描(近 30 天, 276 个会话文件) ===
语法错误 (ParserError)               : 37 个文件命中
PS7 语法跑在 5.1 上                  : 0 个文件命中
命令不存在                            : 32 个文件命中
非零退出码                            : 108 个文件命中
sandbox/权限拒绝 (deny/ACL)          : 253 个文件命中
进程创建失败                           : 105 个文件命中
=== [codebuddy] PowerShell 历史问题扫描(近 30 天, 14 个会话文件) ===
语法错误 (ParserError)               : 3 个文件命中
PS7 语法跑在 5.1 上                  : 3 个文件命中
命令不存在                            : 3 个文件命中
非零退出码                            : 6 个文件命中
sandbox/权限拒绝 (deny/ACL)          : 2 个文件命中
=== [claude] PowerShell 历史问题扫描(近 30 天, 0 个会话文件) ===
    (未找到 *.jsonl 会话日志；确认该 agent 是否在本机用过，或用 -AgentHome 指定目录)
```

3 of CodeBuddy's 14 sessions hit PS7-on-5.1 syntax failures — sessions spent retrying commands that could never parse.

### With the skill

Install the MSI (machine scope), point the agent's shell at it, restart, re-run the check. Then the same probe, in the agent's own shell:

```powershell
$PSVersionTable.PSVersion.ToString() + ' / ' + $PSVersionTable.PSEdition; 1 -eq 1 && 'ok'
# 7.6.5 / Core
# True
# ok
```

| Probe | Without skill (5.1 default) | With skill (global PS7) |
|---|---|---|
| Version / edition | 5.1.26100.9168 / Desktop | 7.6.5 / Core |
| `1 -eq 1 && 'ok'` | ParserError, exit 1 | `True` / `ok` |
| PS7-on-5.1 failures in history | 3 of 14 sessions | 0 new (count sessions after the switch) |

Re-run the scan a few weeks later: sessions created after the switch should add **zero** new "PS7 语法跑在 5.1 上" hits. Old hits never disappear — the scan reads historical transcripts.

## Why 5.1 is the default trap

- PowerShell 7 can be present without being installed globally: Codex ships its own at `%USERPROFILE%\.cache\codex-runtimes\*\dependencies\native\powershell\pwsh.exe`. Count it as global and you get a false "already done" that skips the install this skill exists to perform.
- `&&`, `||`, `??`, `?.` and ternary are PowerShell 7 only. On 5.1 they raise `is not a valid statement separator in this version`.
- `.ps1` files containing non-ASCII **must** be UTF-8 **with BOM**, or 5.1 decodes them in the ANSI code page and dies with `ParserError` — including the scripts meant to diagnose it.
- 5.1 writes stdout in the console code page, so agents charset-guess it and get it wrong on mostly-ASCII lines. `force-utf8-output.ps1` pins output to UTF-8.

<details>
<summary>Repository layout</summary>

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
│       ├── codebuddy-tools.md       # CodeBuddy Code path/setting mapping
│       └── claude-tools.md          # Claude Code path/setting mapping
├── README.md
└── LICENSE
```

</details>

## License

MIT — see [LICENSE](LICENSE).
