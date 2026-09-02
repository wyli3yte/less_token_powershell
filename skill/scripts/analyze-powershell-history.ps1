[CmdletBinding()]
param(
    [int]$Days = 30,
    [ValidateSet('auto', 'codex', 'codebuddy', 'claude', 'all')][string]$Agent = 'auto',
    [Alias('CodexHome')][string]$AgentHome = '',
    # Single-pass mode: read each session file once and match all patterns against it,
    # instead of re-reading per pattern (Select-String -List). Roughly 4-6x faster on large
    # histories (measured: 98MB / 21 files 5.1: 9.9s -> 1.9s; 7: 1.6s -> 0.4s).
    # Off by default to keep per-pattern counts identical to the documented output format.
    [switch]$Fast
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'agent-context.ps1')
. (Join-Path $PSScriptRoot 'force-utf8-output.ps1')

# 平台无关的 PowerShell 症状：任何 agent 的日志里都长这样
# PS 5.1 cannot break down `$patterns.Keys` while adding to the same ordered dict (runtime
# "Collection was modified"), so agent patterns are merged into a NEW ordered dict.
$basePatterns = [ordered]@{
    '语法错误 (ParserError)'   = 'ParserError|MissingEndCurlyBrace'
    'PS7 语法跑在 5.1 上'      = '不是此版本中的有效语句分隔符|is not a valid statement separator in this version'
    '命令不存在'               = 'is not recognized as|CommandNotFound|无法将.+识别为'
    '非零退出码'               = 'Process exited with code [1-9]|Exit Code: [1-9]'
}

# 平台相关的症状：沙箱/执行器的报错文案各家不同
$agentPatterns = @{
    'codex' = [ordered]@{
        'sandbox/权限拒绝 (deny/ACL)' = 'deny-read|apply deny-read ACLs|Rejected|helper_unknown_error'
        '进程创建失败'                = 'Failed to create unified exec process'
    }
    'codebuddy' = [ordered]@{
        'sandbox/权限拒绝 (deny/ACL)' = 'SANDBOX PERMISSION DENIED|dangerouslyDisableSandbox'
    }
}

$since = (Get-Date).AddDays(-$Days)
# -Agent all 扫描各 host 的默认 home; 此时 -AgentHome 会被库层忽略, 显式提示避免误判排查方向。
if ($Agent -eq 'all' -and $AgentHome) {
    Write-Output 'NOTE: -AgentHome is ignored when -Agent all; each host is scanned at its default home. Pass -Agent <name> -AgentHome <dir> to scan a custom location.'
}
$contexts = Get-AgentContext -Agent $Agent -AgentHome $AgentHome
$grand = @{}

foreach ($ctx in $contexts) {
    $patterns = [ordered]@{}
    foreach ($k in $basePatterns.Keys) { $patterns[$k] = $basePatterns[$k] }
    if ($agentPatterns.ContainsKey($ctx.Name)) {
        foreach ($k in $agentPatterns[$ctx.Name].Keys) { $patterns[$k] = $agentPatterns[$ctx.Name][$k] }
    }

    $sessions = Get-ChildItem -Path $ctx.LogRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $since }

    # Precompile once per agent: regex construction is surprisingly expensive on 5.1 and it
    # was being redone for every pattern x file iteration in the old loop.
    $regexes = @{}
    foreach ($k in $patterns.Keys) { $regexes[$k] = New-Object System.Text.RegularExpressions.Regex($patterns[$k], [System.Text.RegularExpressions.RegexOptions]::Compiled) }

    $counts = @{}
    foreach ($k in $patterns.Keys) { $counts[$k] = 0 }

    if ($Fast) {
        # Single pass: read each file once as one string, test every pattern against it.
        # Per-pattern hit counts are preserved ("N 个文件命中" = files with >=1 match).
        foreach ($f in $sessions) {
            $text = [IO.File]::ReadAllText($f.FullName)
            foreach ($k in $patterns.Keys) {
                if ($regexes[$k].IsMatch($text)) { $counts[$k]++ }
            }
        }
    } else {
        # Default mode: Select-String -List per pattern, same output semantics as before.
        foreach ($f in $sessions) {
            foreach ($k in $patterns.Keys) {
                if (Select-String -LiteralPath $f.FullName -Pattern $patterns[$k] -List -ErrorAction SilentlyContinue) {
                    $counts[$k]++
                }
            }
        }
    }

    "=== [$($ctx.Name)] PowerShell 历史问题扫描(近 $Days 天, $($sessions.Count) 个会话文件) ==="
    "    日志根目录: $($ctx.LogRoot)"
    if ($sessions.Count -eq 0) {
        '    (未找到 *.jsonl 会话日志；确认该 agent 是否在本机用过，或用 -AgentHome 指定目录)'
    }
    foreach ($k in $patterns.Keys) {
        '{0,-32} : {1} 个文件命中' -f $k, $counts[$k]
        if (-not $grand.ContainsKey($k)) { $grand[$k] = 0 }
        $grand[$k] += $counts[$k]
    }
    ''
}

'=== 建议 ==='
if ($grand['PS7 语法跑在 5.1 上'] -gt 0) {
    '  - 命中 PS7-only 语法(&&/||/??/?:)跑在 5.1 上: 这正是本 skill 要修的根因 -> 跑 check-powershell7.ps1 决定装 PS7 还是切 shell。'
}
if ($grand['sandbox/权限拒绝 (deny/ACL)'] -gt 0) {
    '  - 出现沙箱/权限拒绝: 先分清是命令 bug 还是权限门。若判定为状态文件损坏(如 codex 的 deny_read_acl_state.json)，删文件前先向用户确认。'
}
if ($grand['语法错误 (ParserError)'] -gt 0) {
    '  - 出现语法错误: 含中文的 .ps1 必须存成 UTF-8 with BOM，否则 PS 5.1 按 GBK 解码直接 ParserError;复杂命令先落成 .ps1 再 -File 调用。'
}
if ($grand['命令不存在'] -gt 0) {
    '  - 出现命令不存在: 检查路径/引号，并确认该命令是否只存在于 agent 自带的 vendor 目录而不在 PATH(如 rg)。'
}
