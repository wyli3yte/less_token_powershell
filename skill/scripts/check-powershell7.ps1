[CmdletBinding()]
param(
    [ValidateSet('auto', 'codex', 'codebuddy')][string]$Agent = 'auto'
)

. (Join-Path $PSScriptRoot 'agent-context.ps1')
. (Join-Path $PSScriptRoot 'pwsh-discovery.ps1')
. (Join-Path $PSScriptRoot 'force-utf8-output.ps1')
$ctx = (Get-AgentContext -Agent $Agent)[0]

$me = Get-Process -Id $PID
$vi = $me.MainModule.FileVersionInfo

'=== 1) Agent 实际使用的 shell(本进程) ==='
"Agent  : $($ctx.Name)"
"Version: $($PSVersionTable.PSVersion)"
"Edition: $($PSVersionTable.PSEdition)"
"ExePath: $($me.Path)"
"FileVer: $($vi.FileVersion)"

# 本 skill 的目标是"全局可用的 PowerShell 7": 一次安装，所有 agent 和所有终端都受益。
# 因此判定只认全局安装; agent 自带的私有副本单独列出，只作参考，不算达标。
'=== 2) 全局 PowerShell 7 (判定依据) ==='
$global = @(Get-GlobalPwshPath)
if ($global.Count -gt 0) {
    foreach ($h in $global) { "global  : $($h.Path)  (v$(Get-PwshVersion $h.Path))  [scope=$($h.Scope), via=$($h.Via)]" }
} else {
    'global  : 否 -- 未找到任何全局安装(Program Files / WindowsApps / 注册表 / Appx / PATH)'
}

# MSIX 包在位但执行别名丢失时, pwsh 在 PATH 上不可达, 表现得像完全没装。
if (@($global | Where-Object { $_.Via -eq 'appx' }).Count -gt 0 -and
    -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'))) {
    $loc = (Get-AppxPackage -Name 'Microsoft.PowerShell*' | Select-Object -First 1).InstallLocation
    '          注意: MSIX 包在位, 但执行别名缺失 -> pwsh 不在 PATH 上。重新注册:'
    "          Add-AppxPackage -Register `"$loc\AppxManifest.xml`" -DisableDevelopmentMode"
}

'=== 2b) agent 私有副本(仅参考，不算全局) ==='
$bundled = @(Get-BundledPwshPath)
if ($bundled.Count -gt 0) {
    foreach ($b in $bundled) { "bundled : $b  (v$(Get-PwshVersion $b))" }
} else {
    'bundled : 无'
}

'=== 3) 判断 ==='
$agentIsPS7     = ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7)
$agentOnPrivate = ($me.Path -and (Test-IsAgentPrivatePwsh $me.Path))

if ($global.Count -eq 0) {
    'NEXT: 缺少全局 PowerShell 7 -> 安装 MSI(见 references/install-powershell7.md)。这是本 skill 的达标条件。'
    if ($bundled.Count -gt 0) {
        '      说明: 本机存在 agent 私有副本，可临时把当前 agent 指过去先解封，但它不满足"全局生效"的目标，'
        '            且属于对方运行时缓存，对方升级或清理后会失效。'
    }
} elseif (-not $agentIsPS7) {
    'NEXT: 全局 PowerShell 7 已就位，但本 agent 仍在跑 5.1 -> 把 agent 切过去，再重跑本脚本验证。'
    if ($ctx.ShellOverrideVar) {
        "      $($ctx.Name) 的切换方式: 设置 $($ctx.ShellOverrideVar) = `"$($global[0].Path)`" (优先于自动检测)，然后重启 agent。"
    } else {
        '      切换方式随 agent 而异，见 references/ 下对应平台的映射文件。'
    }
} elseif ($agentOnPrivate) {
    'NEXT: 本 agent 已是 PowerShell 7，但用的是自带私有副本，而本机已有全局安装。'
    "      建议改指全局路径，以免受对方运行时升级影响: $($global[0].Path)"
} else {
    'NEXT: 已是全局 PowerShell 7 (Core)，无需处理。'
}
