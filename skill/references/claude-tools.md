# Claude Code adaptation

SKILL.md is written against Codex. On Claude Code, substitute the following. Everything
else in the skill applies unchanged.

| SKILL.md reference | Claude Code equivalent |
|---|---|
| `$CODEX_HOME`, `~/.codex` | `$CLAUDE_CONFIG_DIR`, `~/.claude` |
| Skill install dir `$CODEX_HOME/skills/<name>` | `~/.claude/skills/<name>` |
| Session logs `$CODEX_HOME/sessions/**/*.jsonl` | `~/.claude/projects/<project-slug>/*.jsonl` — same layout as CodeBuddy Code (it is a Claude Code fork) |
| Codex's bundled `pwsh.exe` | Claude Code bundles none. Its Bash tool runs Git Bash (`CLAUDE_CODE_GIT_BASH_PATH` pins `bash.exe`), not PowerShell |
| "Configure Codex to invoke `pwsh`" | No shell-override lever exists. The skill's win here is the **global** install: once pwsh 7 is on PATH, `pwsh -File ...` / `pwsh -Command ...` invocations resolve to 7 |
| `scripts/srg.ps1` | Prefer the built-in `Grep` tool. `srg.ps1` still works: it resolves `rg` from PATH, then from a host's vendored copy |

## Detection caveat

CodeBuddy Code (a Claude Code fork) also sets `CLAUDE_SESSION_ID` / `CLAUDE_PROJECT_DIR`,
so `agent-context.ps1` checks the `CODEBUDDY_*` vars **before** the `CLAUDE_*` vars. Do not
reorder that chain, or every CodeBuddy session is misdetected as claude.
