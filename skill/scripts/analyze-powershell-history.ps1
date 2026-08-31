[CmdletBinding()]
param(
    [int]$Days = 30,
    [string]$CodexHome = ''
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
}

$patterns = [ordered]@{
    'sandbox/权限拒绝 (deny/ACL)' = 'deny-read|apply deny-read ACLs|Rejected|helper_unknown_error'
    '语法错误 (ParserError)'      = 'ParserError'
    '命令不存在'                  = 'is not recognized as a name|CommandNotFound'
    '进程创建失败'                = 'Failed to create unified exec process'
    '非零退出码'                  = 'Process exited with code 1'
}

$since = (Get-Date).AddDays(-$Days)
$sessions = Get-ChildItem -Path (Join-Path $CodexHome 'sessions') -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since }

$counts = @{}
foreach ($p in $patterns.Keys) { $counts[$p] = 0 }
foreach ($f in $sessions) {
    foreach ($k in $patterns.Keys) {
        if (Select-String -LiteralPath $f.FullName -Pattern $patterns[$k] -List -ErrorAction SilentlyContinue) {
            $counts[$k]++
        }
    }
}

"=== PowerShell 历史问题扫描(近 $Days 天, $($sessions.Count) 个会话文件) ==="
foreach ($k in $patterns.Keys) {
    '{0,-32} : {1} 个文件命中' -f $k, $counts[$k]
}

'=== 建议 ==='
if ($counts['sandbox/权限拒绝 (deny/ACL)'] -gt 0) {
    '  - 出现沙箱/权限拒绝: 用 $sandbox-permission-handling 分类;若是 deny_read_acl_state.json 损坏(apply deny-read ACLs),删坏文件让沙箱自愈重建。'
}
if ($counts['语法错误 (ParserError)'] -gt 0) {
    '  - 出现语法错误: 用 scripts/srg.ps1 免转义搜索;复杂命令先落成 .ps1 再 -File 调用。'
}
if ($counts['命令不存在'] -gt 0) {
    '  - 出现命令不存在: 检查路径/引号,区分是命令 bug 还是权限门。'
}
