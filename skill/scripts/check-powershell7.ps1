[CmdletBinding()]
param()

$me = Get-Process -Id $PID
$vi = $me.MainModule.FileVersionInfo

'=== 1) Agent 实际使用的 shell(本进程) ==='
"Version: $($PSVersionTable.PSVersion)"
"Edition: $($PSVersionTable.PSEdition)"
"ExePath: $($me.Path)"
"FileVer: $($vi.FileVersion)"

'=== 2) 本机 PowerShell 7 是否已安装 ==='
$ps7Candidates = @(
    'C:\Program Files\PowerShell\7\pwsh.exe',
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
)
$found = @()
foreach ($c in $ps7Candidates) {
    if (Test-Path -LiteralPath $c) { $found += $c }
}
if ($found.Count -eq 0) {
    $c = Get-Command pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsPowerShell' } | Select-Object -First 1
    if ($c) { $found += $c.Source }
}
if ($found.Count -gt 0) {
    foreach ($f in $found) {
        $v = (& $f -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null) -join ''
        "installed: $f  (v$v)"
    }
} else {
    'installed: 否'
}

'=== 3) 判断 ==='
$agentIsPS7 = ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7)
if ($agentIsPS7) {
    'NEXT: 已是 PowerShell 7 (Core)，无需处理。'
} elseif ($found.Count -gt 0) {
    'NEXT: 本机已装 PowerShell 7，但 agent 未使用它 -> 把 agent 切到 pwsh(加入 PATH 或改 shell 配置)，再重跑本脚本验证。'
} else {
    'NEXT: 本机未装 PowerShell 7 -> 安装 MSI(见 references/install-powershell7.md)，再重跑本脚本验证。'
}
