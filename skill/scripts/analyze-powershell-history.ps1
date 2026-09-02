[CmdletBinding()]
param(
    [int]$Days = 30,
    [ValidateSet('auto', 'codex', 'codebuddy', 'claude', 'all')][string]$Agent = 'auto',
    [Alias('CodexHome')][string]$AgentHome = '',
    [switch]$Tokens,                 # opt-in: streaming JSON pass, slow on a big codex tree
    [int]$MaxFileMB = 256            # 0 = no limit
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'agent-context.ps1')
. (Join-Path $PSScriptRoot 'force-utf8-output.ps1')
. (Join-Path $PSScriptRoot 'token-attribution.ps1')

$contexts = Get-AgentContext -Agent $Agent -AgentHome $AgentHome
$bannerInfo = @("days=$Days")
if ($Tokens) { $bannerInfo += 'tokens=on' }
Write-SkillBanner -Script 'analyze-powershell-history.ps1' -Agent (Get-RunningAgentName) -Info $bannerInfo

# 平台无关的 PowerShell 症状：任何 agent 的日志里都长这样
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
$grand = @{}
$tokGrand = @{ Turns = 0; FailTurns = 0; Upper = 0; Retry = 0; Truncated = 0; OverWindow = 0 }
$self = $null
if ($Tokens) {
    $self = Get-SkillSelfCost -SkillDir (Split-Path -Parent $PSScriptRoot) -Agent $contexts[0].Name
}

foreach ($ctx in $contexts) {
    $patterns = [ordered]@{}
    foreach ($k in $basePatterns.Keys) { $patterns[$k] = $basePatterns[$k] }
    if ($agentPatterns.ContainsKey($ctx.Name)) {
        foreach ($k in $agentPatterns[$ctx.Name].Keys) { $patterns[$k] = $agentPatterns[$ctx.Name][$k] }
    }

    $sessions = Get-ChildItem -Path $ctx.LogRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $since }

    $counts = @{}
    foreach ($k in $patterns.Keys) { $counts[$k] = 0 }
    foreach ($f in $sessions) {
        foreach ($k in $patterns.Keys) {
            if (Select-String -LiteralPath $f.FullName -Pattern $patterns[$k] -List -ErrorAction SilentlyContinue) {
                $counts[$k]++
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

    if ($Tokens) {
        $tk = Get-TokenAttribution -Files $sessions -Agent $ctx.Name -MaxFileMB $MaxFileMB
        $tokGrand.Turns += $tk.Turns
        $tokGrand.FailTurns += $tk.FailTurns
        $tokGrand.Upper += $tk.UpperBound
        $tokGrand.Retry += $tk.Retry
        $tokGrand.Truncated += $tk.Truncated
        $tokGrand.OverWindow += $tk.OverWindow
        '--- token 归因 (来自 transcript 的真实 usage 字段) ---'
        '    {0,-28}: {1}' -f '扫描 turn 总数', $tk.Turns
        '    {0,-28}: {1}' -f '失败 turn', $tk.FailTurns
        '    {0,-28}: {1}  [实测/上限, 含上下文重发]' -f '(a) 归因上限(失败 turn 全计)', ('{0:N0}' -f $tk.UpperBound)
        '    {0,-28}: {1}  [实测]' -f '(b) 重试实测(失败后至恢复前)', ('{0:N0}' -f $tk.Retry)
        '    {0,-28}: 未收敛 {1} 次 | 超窗截断 {2} 次' -f '未计入', $tk.Truncated, $tk.OverWindow
        '    {0,-28}: 超大文件 {1} 个 | 超长行 {2} | 解析失败 {3}' -f '跳过', $tk.SkipBig, $tk.SkipLong, $tk.SkipParse
    }
}

if ($Tokens) {
    '=== token 合计 ==='
    '    turn 总数    : {0}' -f $tokGrand.Turns
    '    失败 turn    : {0}' -f $tokGrand.FailTurns
    '    (a) 归因上限 : {0}  [实测/上限, 含上下文重发]' -f ('{0:N0}' -f $tokGrand.Upper)
    '    (b) 重试实测 : {0}  [实测]' -f ('{0:N0}' -f $tokGrand.Retry)
    '    未计入       : 未收敛 {0} 次 | 超窗截断 {1} 次' -f $tokGrand.Truncated, $tokGrand.OverWindow
    '    口径         : (a) 是失败那一轮, (b) 是失败后到恢复前的轮次 —— 两组不同的 turn; 重试会重发整个上下文, 故 (b) 常大于 (a)'
    if ($self) {
        '    本 skill 自身成本 : {0}  [估算: {1}; CJK 1.5 + ASCII 4 字符/token]' -f ('{0:N0}' -f $self.Tokens), $self.Files
        if ($self.Tokens -gt 0 -and $tokGrand.Retry -gt 0) {
            '    对比: 每次激活本 skill 约 {0} tokens(估算); 实测已浪费 {1} -> 相当于 {2} 次激活' -f ('{0:N0}' -f $self.Tokens), ('{0:N0}' -f $tokGrand.Retry), ('{0:N0}' -f [Math]::Round($tokGrand.Retry / $self.Tokens))
        }
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
