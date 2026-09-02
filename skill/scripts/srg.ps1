# srg.ps1 - 安全版 ripgrep 封装 (PowerShell 5.1+/7)
#   - 路径/参数: 走 param() -> List[string] -> & rg @args, 以 argv 传入, 不经 shell 字符串解析, 故空格/中文/反斜杠/引号不用转义。
#   - rg 解析顺序: -RgPath -> PATH -> agent 自带的 vendor\ripgrep\*\rg.exe (CodeBuddy Code 自带但不入 PATH)。
#   - pattern 默认按正则; 要字面匹配用 -Literal (--fixed-strings)。pattern 前自动加 "--", 避免以 - 开头被当成选项。
#   - 输出默认限量(MaxLines=150 行, MaxLineLen=500 字符), 但可以通过拨杆拿到完整结果:
#       -OutFile <file>   全部结果写入该文件(不截断), 只回显总数+前几行
#       -MaxLines -1      不限行数
#       -MaxLines 0       仅统计: 只打印总数, 不打印匹配行 (O(1) 内存)
#       -MaxLineLen 0     不限单行长度
#   - 强制 --color never --no-config, 输出稳定干净。
#   - 5.1 兼容: rg 的 stderr 不再被 2>&1 吞进结果流。旧版在 EAP=Stop + 2>&1 下, rg 只要往
#     stderr 写任何东西(哪怕一条无害警告)就抛 NativeCommandError, 匹配结果全部丢失。
# 用法:
#   & .\srg.ps1 "regex" "path"
#   & .\srg.ps1 "literal 中文" "路 径" -Literal
#   & .\srg.ps1 "pat" "." -Glob "*.ps1" -Count
#   & .\srg.ps1 "" "dir" -Files
#   & .\srg.ps1 "pat" "dir" -OutFile "$env:TEMP\full.txt"

[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Pattern = '',
    [Parameter(Position=1)][string]$Path = '.',
    [switch]$Literal,
    [switch]$Files,
    [switch]$Count,
    [switch]$Hidden,
    [switch]$NoIgnore,
    [string]$Glob = '',
    [int]$MaxLines = 150,    # -1 = 不限行数; 0 = 仅统计总数
    [int]$MaxLineLen = 500,  # 0 = 不限单行长度
    [string]$OutFile = '',   # 非空则将全部结果写入该文件(不截断)
    [string]$RgPath = ''     # 显式指定 rg.exe;留空则 PATH -> agent 自带 vendor 目录
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'force-utf8-output.ps1')

# 空路径会让 rg 转去读 stdin, 在 agent 里等于永久阻塞且零输出。
if ([string]::IsNullOrWhiteSpace($Path)) {
    Write-Output 'ERROR: -Path 不能为空。要搜当前目录请传 "."。'
    exit 0
}

# rg 未必在 PATH 上: 有的 agent(如 CodeBuddy Code)自带 vendored ripgrep 而不注册到 PATH。
$rg = $null
if ($RgPath) {
    if (-not (Test-Path -LiteralPath $RgPath)) { Write-Output "ERROR: -RgPath 不存在: $RgPath"; exit 0 }
    $rg = $RgPath
} else {
    $onPath = Get-Command rg -ErrorAction SilentlyContinue
    if ($onPath) { $rg = $onPath.Source }
}
if (-not $rg) {
    $bases = @(
        (Join-Path $env:APPDATA 'npm\node_modules\@tencent-ai\codebuddy-code'),
        (Join-Path $env:USERPROFILE '.codebuddy'),
        (Join-Path $env:USERPROFILE '.codex')
    )
    foreach ($b in $bases) {
        $hit = Get-ChildItem -Path (Join-Path $b 'vendor\ripgrep\*\rg.exe') -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $rg = $hit.FullName; break }
    }
}
if (-not $rg) {
    Write-Output 'ERROR: 找不到 rg。用 -RgPath 指定，或改用 agent 内置的搜索工具(CodeBuddy Code: Grep)。'
    exit 0
}

$rgArgs = New-Object System.Collections.Generic.List[string]
$rgArgs.Add('--no-heading')
$rgArgs.Add('--color')
$rgArgs.Add('never')
$rgArgs.Add('--no-config')
if($Hidden){ $rgArgs.Add('--hidden') }
if($NoIgnore){ $rgArgs.Add('--no-ignore') }
if($Glob){ $rgArgs.Add('--glob'); $rgArgs.Add($Glob) }

if($Files){
    $rgArgs.Add('--files')
    $rgArgs.Add('--')
    $rgArgs.Add($Path)
} else {
    if([string]::IsNullOrEmpty($Pattern)){
        Write-Output 'USAGE: a pattern is required (or use -Files).'
        exit 0
    }
    if($Count){ $rgArgs.Add('--count') }
    if($Literal){ $rgArgs.Add('--fixed-strings') }
    $rgArgs.Add('--')
    $rgArgs.Add($Pattern)
    $rgArgs.Add($Path)
}

# --- Run rg without 2>&1 -----------------------------------------------
# 5.1: EAP=Stop turns ANY stderr byte into a terminating NativeCommandError and throws
# away the whole match list. Redirecting to a file alone does NOT prevent that (stderr
# lines become ErrorRecords even when redirected). The reliable 5.1 pattern is to run
# the native call under EAP=Continue and restore it afterwards; stderr goes to a temp
# file and is only surfaced when rg exits with code 2 (real error). PS7 is unaffected.
$errFile = Join-Path ([IO.Path]::GetTempPath()) ("srg-{0}.err" -f ([guid]::NewGuid().ToString('N')))
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out = & $rg @rgArgs 2>$errFile
    $code = $LASTEXITCODE
} catch {
    $ErrorActionPreference = $prevEap
    Write-Output ("ERROR: " + $_.Exception.Message)
    if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue }
    exit 0
}
$ErrorActionPreference = $prevEap

if($code -eq 2){
    $errText = ''
    if (Test-Path -LiteralPath $errFile) { $errText = ([IO.File]::ReadAllText($errFile)).Trim() }
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    if ($errText) { Write-Output ("rg error: " + $errText) } else { Write-Output 'rg error: (no stderr output)' }
    exit 0
}
Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue

# --- 限量输出 ------------------------------------------------------------
# 旧版 `@($out | ForEach-Object { $_.ToString() })` 在已有 $out 之外又物化一份逐行 ToString
# 的副本(两份全量同时存活)。现在直接消费 $out, 不再复制; 行数上限照旧生效。
$list = @($out)
if($list.Count -eq 0){
    if($code -eq 1){ Write-Output '0 matches' }
    exit 0
}

# --- 全部写入文件, 只回显总数+预览 ---
if($OutFile){
    $list | Set-Content -LiteralPath $OutFile -Encoding UTF8
    Write-Output ("Wrote {0} lines to {1}" -f $list.Count, $OutFile)
    $preview = @($list | Select-Object -First 5)
    foreach($l in $preview){
        if($l.Length -gt 120){ Write-Output ($l.Substring(0,120) + ' ...') } else { Write-Output $l }
    }
    if($list.Count -gt 5){ Write-Output ('... [+' + ($list.Count-5) + ' more in file]') }
    exit 0
}

# --- MaxLines 0: 仅统计模式 ---
if($MaxLines -eq 0){
    Write-Output ("total {0} lines" -f $list.Count)
    exit 0
}

# --- 默认限量显示 ---
$lineCap = if($MaxLines -ge 0){ $MaxLines } else { [int]::MaxValue }
$shown = 0
foreach($line in $list){
    $shown++
    if($shown -gt $lineCap){ break }
    if($MaxLineLen -gt 0 -and $line.Length -gt $MaxLineLen){
        Write-Output ($line.Substring(0,$MaxLineLen) + " ...[+$($line.Length-$MaxLineLen) chars]")
    } else {
        Write-Output $line
    }
}
if($lineCap -lt $list.Count){
    Write-Output ("... [total $($list.Count), showing first $MaxLines; +" + ($list.Count-$MaxLines) + " omitted]")
}
exit 0
