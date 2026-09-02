<div align="center">

# Less PowerShell Token Tax

**Every PowerShell 7 command that dies on Windows PowerShell 5.1 costs a retry — and a retry costs tokens. This skill deletes the cause, not the symptom.**

It detects the PowerShell each agent actually uses, gets one **global** PowerShell 7 onto the machine, and switches Codex, CodeBuddy Code and Claude Code onto it from a single copy. One install, every agent, every terminal: `&&`, `??` and UTF-8 output just parse, and the retry tax stops.

<p>
  <a href="https://github.com/wyli3yte/less_token_powershell/stargazers"><img src="https://img.shields.io/github/stars/wyli3yte/less_token_powershell?style=flat&color=yellow" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wyli3yte/less_token_powershell?style=flat" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/platform-Windows-0078d4?style=flat" alt="Platform: Windows">
  <img src="https://img.shields.io/badge/runs%20on-PowerShell%205.1-2da44e?style=flat" alt="Runs on PowerShell 5.1">
</p>

<p>
  <a href="#the-problem"><strong>The problem</strong></a> ·
  <a href="#quick-install"><strong>Install</strong></a> ·
  <a href="#verify-in-one-command"><strong>Verify</strong></a> ·
  <a href="#proof-before-and-after-on-a-real-machine"><strong>Proof</strong></a> ·
  <a href="#faq"><strong>FAQ</strong></a> ·
  <a href="#reference"><strong>Reference</strong></a>
</p>

</div>

---

## At a glance

| | |
|---|---|
| Hosts covered | **3** — Codex, CodeBuddy Code, Claude Code, from one copy |
| User-facing scripts | **3** (+3 libraries), all host-aware via `-Agent` |
| Minimum shell to run it | **Windows PowerShell 5.1** — the scripts work on the thing they diagnose |
| The pass condition | **a global pwsh 7**, never an agent's private copy |
| Time to install | one command, under a minute |
| What it removes | the retry tax — PS7-only syntax failing on 5.1, charset guesswork, false "already installed" verdicts |

## The problem

Ask three agents on one Windows machine "which PowerShell are you on?" and you get three different answers — and two of them are wrong in a way that looks like success.

| State | What you see | What it costs you | Verdict |
|---|---|---|---|
| System **5.1** (the default for most agents) | `标记"&&"不是此版本中的有效语句分隔符。` on the first PS7-only command | every PS7-only command is a wasted round-trip: error text in, no result out, retry | **not done** |
| An agent's **bundled** pwsh 7 (Codex ships one) | everything works — until that agent upgrades and the path disappears | nothing today, the whole session tomorrow when the path vanishes mid-task | **not done** |
| A **global** pwsh 7 | PS7 syntax parses, the path is stable, every agent and terminal benefits | nothing — the tax is gone | **done** |

> [!IMPORTANT]
> **A bundled pwsh 7 is not a global install.** It lives in one agent's runtime cache, it is versioned by that agent, and it vanishes when the agent upgrades. Counting it as done produces a false "already installed" verdict — and skips the install this skill exists to perform.

## The solution: global first

The skill stops at the first rung that applies, and prints the next action every time:

```
1. Run check-powershell7.ps1            -> the verdict, in three sections
2. No global pwsh 7?                    -> install the MSI (machine scope)
3. Global pwsh 7, agent still on 5.1?   -> switch the agent, restart
4. Agent on a bundled copy?             -> repoint it at the global path
5. Re-run the check                     -> until it prints a global path AND Core
```

Every step is a decision the script makes for you, with a paste-ready value for *your* host.

## Why this skill?

Because "the PowerShell version" is not one fact on a Windows machine — and every wrong answer is billed per retry. A `ParserError` is not a cheap failure: the error text, the diagnosis, the rewrite and the re-run all land in the context window, and the command itself produced nothing. Fix the shell once and the whole class of retries disappears.

Verified on a real box: CodeBuddy Code's PowerShell tool resolves the system `powershell.exe` (5.1.26100.9168 / `Desktop`), while Codex, on the same machine, runs its own bundled pwsh 7.6.4 out of `~/.cache/codex-runtimes`. Same box, same question, two answers — and a scan of that machine's session history found **3 of 14** CodeBuddy sessions had already paid the tax on PS7-only syntax.

| Principle | Implementation |
|---|---|
| Global means global | `Get-GlobalPwshPath` (MSI, registry, Appx, PATH) and `Get-BundledPwshPath` are discovered separately and **never merged** |
| Trust measurement, not assumption | The verdict comes from the running process and the machine, not from `which pwsh` |
| One skill, several hosts | Every host-specific path lives in `agent-context.ps1`; the scripts stay generic — no forks |
| Prove the fix | Re-run the check; then re-run the history scan weeks later and count new sessions |
| Stay usable on the broken thing | Libraries are ASCII-only, user-facing scripts are UTF-8 **with BOM**, all output is pinned to UTF-8 |

## Quick install

```powershell
powershell -File install.ps1              # every host present on the machine
powershell -File install.ps1 -Agent auto  # only the host running this process
```

| Host | Installed to | Shell override it prints |
|---|---|---|
| Codex | `$CODEX_HOME/skills/...` (`~/.codex`) | none needed — its exec already launches pwsh |
| CodeBuddy Code | `~/.codebuddy/skills/...` | `CODEBUDDY_POWERSHELL_PATH` |
| Claude Code | `~/.claude/skills/...` | none — its Bash tool is Git Bash; it benefits from pwsh 7 on PATH |

Add `-Clean` to wipe the destination before copying (destructive). Installing needs no elevation; installing PowerShell itself does.

## Verify in one command

```powershell
powershell -File skill\scripts\check-powershell7.ps1
```

It prints the agent's own shell, every **global** pwsh 7 (the verdict), any **bundled** copy (reference only), and the next action:

```text
[less-token-powershell] check-powershell7.ps1 | host=codebuddy
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

Only a `global :` path counts as done. When the agent is still on 5.1, the same script says so and hands you the lever — this is it run **under `powershell.exe` 5.1** (the scripts run on the thing they diagnose):

```text
=== 1) Agent 实际使用的 shell(本进程) ===
Agent  : codebuddy
Version: 5.1.26100.9168
Edition: Desktop
ExePath: C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe
=== 2) 全局 PowerShell 7 (判定依据) ===
global  : C:\Program Files\PowerShell\7\pwsh.exe  (v7.6.5)  [scope=machine, via=machine-path]
=== 3) 判断 ===
NEXT: 全局 PowerShell 7 已就位，但本 agent 仍在跑 5.1 -> 把 agent 切过去，再重跑本脚本验证。
      codebuddy 的切换方式: 设置 CODEBUDDY_POWERSHELL_PATH = "C:\Program Files\PowerShell\7\pwsh.exe" (优先于自动检测)，然后重启 agent。
```

## The scripts

| Script | Reach for it when |
|---|---|
| `check-powershell7.ps1` | You need the verdict: missing → install, installed-but-unused → switch, or done. |
| `analyze-powershell-history.ps1` | You want to know what 5.1 already cost you. `-Agent all -Days 30` scans every host. |
| `srg.ps1` | You need ripgrep with argv passing and bounded output: `-Literal`, `-OutFile`, `-Count`, `-Files`. |

All three take `-Agent auto|codex|codebuddy|claude|all`, and all three print a one-line
`[less-token-powershell]` banner so a transcript shows the skill ran (`LESS_TOKEN_POWERSHELL_QUIET=1`
silences it).

### Measuring the tax in tokens

`-Tokens` turns the scan into a ledger, measured from the **real `usage` fields in the transcripts** —
the hosts record them, so nothing is estimated:

```powershell
powershell -File skill\scripts\analyze-powershell-history.ps1 -Agent all -Days 30 -Tokens
```

```text
--- token 归因 (来自 transcript 的真实 usage 字段) ---
    扫描 turn 总数                  : 11637
    失败 turn                     : 231
    (a) 归因上限(失败 turn 全计)        : 29,563,030  [实测/上限, 含上下文重发]
    (b) 重试实测(失败后至恢复前)           : 19,285,816  [实测]
    未计入                         : 未收敛 4 次 | 超窗截断 148 次
    跳过                          : 超大文件 0 个 | 超长行 30 | 解析失败 0
=== token 合计 ===
    本 skill 自身成本 : 1,346  [估算: SKILL.md; CJK 1.5 + ASCII 4 字符/token]
    对比: 每次激活本 skill 约 1,346 tokens(估算); 实测已浪费 19,285,816 -> 相当于 14,328 次激活
```

- (a) counts the turns that failed; (b) counts the turns **after** a failure until the next clean
  turn — two different sets of turns, and (b) is often larger because every retry re-sends the
  context. Only (b) is the recurring waste; (a) is an upper bound.
- The three hosts report usage differently: codex gives a per-turn delta, claude per request,
  codebuddy a **cumulative counter** that must be diffed. Summing codebuddy's counter inflates the
  total by orders of magnitude — the library handles it, do not "simplify" it away.
- Only recognisably PowerShell failures count (`ParserError`, `CategoryInfo`, a non-zero exit with
  `powershell`/`pwsh` in the command). A failed `git` or `npm` command is not this skill's tax.

### The feature does not cost tokens when you are not using it

`-Tokens` is opt-in. Measured on this machine: the default scan's output is **259 tokens** to read,
with `-Tokens` **530** (+271), and the extra runtime is seconds. Files larger than `-MaxFileMB`
(default 256, `0` disables) are skipped and counted, so a 6.8 GB codex tree stays usable.

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

3 of CodeBuddy's 14 sessions hit PS7-on-5.1 syntax failures — sessions that spent turns retrying commands which could never parse, each retry adding error text and a rewrite to the context window for zero progress.

### With the skill

Install the MSI (machine scope), set the override the check printed, restart, re-run. Then the same probe, in the agent's own shell:

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

> [!NOTE]
> **How to read the last row.** The scan reads historical transcripts, so old hits never disappear — judge by sessions created *after* the switch. One machine is one data point, not a benchmark; it is here to show the failure mode and the verification loop, not to generalise.

## When to use

**Reach for this skill when:**

- A Windows command fails with `ParserError`, `MissingEndCurlyBrace`, or `is not a valid statement separator in this version`
- You need to know which PowerShell your agent is actually running
- `&&`, `||`, `??`, `?.` or a ternary works in your terminal but not in the agent
- You want to cut token spend on Windows: every avoided `ParserError` is a whole retry cycle you do not pay for
- You want the waste as a number, not an anecdote — `analyze-powershell-history.ps1 -Tokens`
- Two agents disagree about what "the PowerShell version" is
- You are about to install PowerShell 7 and want the install to serve every agent, not one

**You do not need it if:** the machine already has a machine-scope pwsh 7 and every agent resolves it — the check confirms that in one command.

<a id="faq"></a>

## FAQ

<details>
<summary><strong>Will installing PowerShell 7 break my existing 5.1 scripts?</strong></summary>

No. PowerShell 7 installs side by side with Windows PowerShell 5.1 into its own directory (`C:\Program Files\PowerShell\7\` by default) and does not replace or remove 5.1. Scripts that call `powershell.exe` keep running on 5.1.

</details>

<details>
<summary><strong>Why isn't putting pwsh on PATH enough?</strong></summary>

Because a host that resolves an absolute exe path ignores PATH order entirely — which is exactly what a PowerShell tool or an exec launcher does. PATH ordering helps interactive terminals; the shell override is what moves the agent.

</details>

<details>
<summary><strong>Can I just point the agent at Codex's bundled pwsh instead of installing?</strong></summary>

You can, and the check script prints that path so you can unblock immediately. The trade-off: it is Codex's versioned runtime cache (`codex-primary-runtime`), so Codex upgrading or pruning it leaves your override pointing at nothing. Use it to unblock; install the MSI for a stable path.

</details>

<details>
<summary><strong>What if I cannot install (no admin, no network)?</strong></summary>

The skill degrades gracefully: it still detects the real state and still tells you the next action, and `analyze-powershell-history.ps1` still measures the damage. The MSI route and its per-user alternatives are documented in [`skill/references/install-powershell7.md`](skill/references/install-powershell7.md). Installing software or switching the shell needs approval — nothing installs itself.

</details>

<details>
<summary><strong>Do the diagnostic scripts really run on 5.1?</strong></summary>

Yes — verified. `powershell.exe -File skill\scripts\check-powershell7.ps1` runs on 5.1 and prints the switch lever for the detected host. That is why the libraries are ASCII-only, why the user-facing scripts are UTF-8 **with BOM** (5.1 decodes BOM-less files in the ANSI code page and dies with `ParserError`), and why every script pins stdout to UTF-8.

</details>

<details>
<summary><strong>Why is Codex detected before Claude Code?</strong></summary>

Because CodeBuddy Code is a Claude Code fork and **also** sets `CLAUDE_SESSION_ID` / `CLAUDE_PROJECT_DIR`. `agent-context.ps1` checks `CODEBUDDY_*` first, then `CODEX_HOME`, then `CLAUDE_*` — reorder that chain and every CodeBuddy session is misdetected as claude.

</details>

<a id="reference"></a>

## Reference

| Doc | What it covers |
|---|---|
| [`skill/SKILL.md`](skill/SKILL.md) | The skill itself: decision order, key facts, constraints |
| [`skill/references/install-powershell7.md`](skill/references/install-powershell7.md) | MSI vs MSIX, install routes, why the MSI path is stable |
| [`skill/references/codebuddy-tools.md`](skill/references/codebuddy-tools.md) | CodeBuddy Code paths, settings, env vars |
| [`skill/references/claude-tools.md`](skill/references/claude-tools.md) | Claude Code paths, Git Bash shell, detection caveat |

<details>
<summary><strong>Repository layout</strong></summary>

```text
.
├── install.ps1                    # install for one host or every host present
├── skill/
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   ├── scripts/
│   │   ├── check-powershell7.ps1          # verdict + next action
│   │   ├── analyze-powershell-history.ps1 # scan past sessions for PS failures
│   │   ├── srg.ps1                        # safe ripgrep wrapper (argv, bounded output)
│   │   ├── token-attribution.ps1          # token ledger: failure test, turns, self-cost (ASCII only, no BOM)
│   │   ├── pwsh-discovery.ps1             # global vs bundled discovery (ASCII only, no BOM)
│   │   ├── agent-context.ps1              # host detection + paths (ASCII only, no BOM)
│   │   └── force-utf8-output.ps1          # pin stdout to UTF-8 (ASCII only, no BOM)
│   └── references/
│       ├── install-powershell7.md
│       ├── codebuddy-tools.md
│       └── claude-tools.md
├── README.md
└── LICENSE
```

</details>

## License

MIT — see [LICENSE](LICENSE).
