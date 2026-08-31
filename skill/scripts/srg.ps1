# srg.ps1 - 安全版 ripgrep 封装 (PowerShell 5.1+/7)
#   - 路径/参数: 走 param() -> List[string] -> & rg @args, 以 argv 传入, 不经 shell 字符串解析, 故空格/中文/反斜杠/引号不用转义。
#   - rg 解析顺序: -RgPath -> PATH -> agent 自带的 vendor\ripgrep\*\rg.exe (CodeBuddy Code 自带但不入 PATH)。
#   - pattern 默认按正则; 要字面匹配用 -Literal (--fixed-strings)。pattern 前自动加 "--", 避免以 - 开头被当成选项。
#   - 输出默认限量(MaxLines=150 行, MaxLineLen=500 字符), 但可通过拨杆拿到完整结果:
#       -OutFile <file>   全部结果写入该文件(不截断), 只回显总数+前几行
#       -MaxLines -1      不限行数
#       -MaxLineLen 0     不限单行长度
#   - 强制 --color never --no-config, 输出稳定干净。
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
    [int]$MaxLines = 150,    # -1 = 不限行数
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

try {
    $out = & $rg @rgArgs 2>&1
    $code = $LASTEXITCODE
} catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
    exit 0
}

if($code -eq 2){
    Write-Output ("rg error: " + (($out | Out-String).Trim()))
    exit 0
}

$list = @($out | ForEach-Object { $_.ToString() })
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

# --- 默认限量显示 ---
$lineCap = if($MaxLines -ge 0){ $MaxLines } else { [int]::MaxValue }
$shown   = @($list | Select-Object -First $lineCap)
foreach($line in $shown){
    if($MaxLineLen -gt 0 -and $line.Length -gt $MaxLineLen){
        Write-Output ($line.Substring(0,$MaxLineLen) + " ...[+$($line.Length-$MaxLineLen) chars]")
    } else {
        Write-Output $line
    }
}
if($MaxLines -ge 0 -and $list.Count -gt $MaxLines){
    Write-Output ("... [total $($list.Count), showing first $MaxLines; +" + ($list.Count-$MaxLines) + " omitted]")
}
exit 0
