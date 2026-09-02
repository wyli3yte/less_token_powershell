# Windows PowerShell 7 Setup

An agent skill for Windows that detects the PowerShell the agent actually uses, installs PowerShell 7 (MSI) when the machine has no global install, switches the agent to it when it is installed-but-unused, and verifies the result. It also ships smart tooling for safe, low-token PowerShell usage on Windows.

Supported hosts: **Codex** (primary), **CodeBuddy Code**, and **Claude Code**. One skill, one set of scripts — host differences live in `skill/scripts/agent-context.ps1` and `skill/references/<host>-tools.md`.

## What it does

1. `check-powershell7.ps1` — decide, using **global** installs as the verdict: no global PS7 (install the MSI), global PS7 present but the agent is on 5.1 or on an agent-bundled copy (repoint it), or done. Prints the switch lever and a paste-ready value for the detected host. `-Agent all` reports every host present on the machine in one run.
2. `analyze-powershell-history.ps1` — scan agent run history for PowerShell errors (ParserError, PS7-only syntax on 5.1, sandbox/ACL denials, missing commands) and report remediation. `-Agent all` scans every host on the machine. `-Fast` switches to a single-pass scan (each file read once, patterns precompiled): identical per-pattern counts, roughly 2-5x faster on large histories — measured on 98MB/21 files under 5.1: 9.9s -> 4.0s.
3. `srg.ps1` — safe ripgrep wrapper: argv passing (no shell escaping for spaces/Chinese/backslashes), bounded output, `-Literal`, `-OutFile`, `-Count`, `-Files`. Falls back to a host's vendored `rg.exe` when `rg` is not on PATH. `-MaxLines 0` prints only the total count. rg's stderr no longer aborts the wrapper on 5.1 (warning-only stderr used to throw away the whole match list).

## Install

```powershell
powershell -File install.ps1              # default: install for every host present
powershell -File install.ps1 -Agent auto  # only the host running this process
```

Destination is `<agent home>/skills/windows-powershell7-setup` — `$CODEX_HOME` or `~/.codex` for Codex, `$CODEBUDDY_CONFIG_DIR` or `~/.codebuddy` for CodeBuddy Code, `$CLAUDE_CONFIG_DIR` or `~/.claude` for Claude Code. Add `-Clean` to wipe the destination first instead of copying over it.

## Worked example: before/after verification (real run, 2026-09-02)

A full verification pass captured live on this machine (Windows 11, Codex + CodeBuddy Code + Claude Code).
"Without the skill" = the 5.1 an agent lands on by default; "with the skill" = the state after
following its install/switch flow. Same probes, run before and after.

### Without the skill — the agent's default 5.1

Probing the system shell directly:

```powershell
powershell.exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString() + " / " + $PSVersionTable.PSEdition'
# 5.1.26100.9168 / Desktop

powershell.exe -NoProfile -Command "1 -eq 1 && 'ok'"
# 标记"&&"不是此版本中的有效语句分隔符。   ("&&" is not a valid statement separator — ParserError)
```

Scanning all hosts' real session history for the damage this caused:

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

CodeBuddy's 14 sessions contain 3 PS7-on-5.1 syntax failures — sessions wasted on retries of
commands that could never parse.

### With the skill — install, switch, verify

Following `check-powershell7.ps1`'s NEXT line: install the MSI (machine scope), point the agent's
shell at it, restart, then re-run:

```powershell
powershell -File skill\scripts\check-powershell7.ps1
```

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

The exact same syntax probe, now in the agent's own shell:

```powershell
$PSVersionTable.PSVersion.ToString() + ' / ' + $PSVersionTable.PSEdition; 1 -eq 1 && 'ok'
# 7.6.5 / Core
# True
# ok
```

Same command that died with a ParserError on 5.1 now parses and runs.

### The comparison

| Probe | Without skill (5.1 default) | With skill (global PS7) |
|---|---|---|
| Version / edition | 5.1.26100.9168 / Desktop | 7.6.5 / Core |
| `1 -eq 1 && 'ok'` | ParserError, exit 1 | `True` / `ok` |
| PS7-on-5.1 failures in history | 3 of 14 sessions | 0 new (judge by sessions after the switch) |

Re-run the history scan after a few weeks: sessions created after the switch should add **zero**
new "PS7 语法跑在 5.1 上" hits. (Old hits never disappear — the scan reads historical transcripts.)

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
│       ├── codebuddy-tools.md       # CodeBuddy Code path/setting mapping
│       └── claude-tools.md          # Claude Code path/setting mapping
├── README.md
└── LICENSE
```

## License
MIT — see [LICENSE](LICENSE).
