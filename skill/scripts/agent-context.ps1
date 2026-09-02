# agent-context.ps1 - resolve which agent host is running and where its data lives.
# ASCII-only on purpose: this is a library, it emits data (not messages), so it needs no BOM.
# Dot-source it:  . (Join-Path $PSScriptRoot 'agent-context.ps1')
#
# One skill, several hosts. Everything host-specific lives here; the other scripts stay generic.

function Get-AgentHomeDefault {
    param([Parameter(Mandatory)][string]$Name)
    switch ($Name) {
        'codex' {
            if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
        }
        'codebuddy' {
            # CODEBUDDY_CONFIG_DIR is the documented override for config/data location.
            if ($env:CODEBUDDY_CONFIG_DIR) { $env:CODEBUDDY_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.codebuddy' }
        }
        'claude' {
            if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
        }
    }
}

# Which agent is running THIS process? Runtime env vars are authoritative;
# fall back to the exe path, then to whichever home directory exists.
# CodeBuddy (a Claude Code fork) also sets CLAUDE_* vars, so claude must be checked AFTER codebuddy.
function Get-RunningAgentName {
    if ($env:CODEBUDDY_SESSION_ID -or $env:CODEBUDDY_PROJECT_DIR) { return 'codebuddy' }
    if ($env:CODEX_HOME) { return 'codex' }
    if ($env:CLAUDE_SESSION_ID -or $env:CLAUDE_PROJECT_DIR) { return 'claude' }
    $p = (Get-Process -Id $PID).Path
    if ($p -match 'codex')     { return 'codex' }
    if ($p -match 'codebuddy') { return 'codebuddy' }
    if ($p -match 'claude')    { return 'claude' }
    return ''
}

function New-AgentContext {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$HomeOverride = ''
    )
    $agentHome = if ($HomeOverride) { $HomeOverride } else { Get-AgentHomeDefault $Name }

    # Session transcript layout differs per host:
    #   codex     -> <home>\sessions\**\*.jsonl
    #   codebuddy -> <home>\projects\<project-slug>\*.jsonl
    #   claude    -> <home>\projects\<project-slug>\*.jsonl (same layout; codebuddy forked from it)
    if ($Name -eq 'codebuddy' -or $Name -eq 'claude') {
        $logRoot  = Join-Path $agentHome 'projects'
        $shellVar = if ($Name -eq 'codebuddy') { 'CODEBUDDY_POWERSHELL_PATH' } else { '' }
    } else {
        $logRoot  = Join-Path $agentHome 'sessions'
        $shellVar = ''
    }

    [pscustomobject]@{
        Name             = $Name
        Home             = $agentHome
        SkillDir         = (Join-Path $agentHome 'skills')
        LogRoot          = $logRoot
        ShellOverrideVar = $shellVar
    }
}

# -Agent auto      -> the host running this process
# -Agent all       -> every host whose home directory exists on this machine
# -Agent codex|codebuddy|claude -> that host explicitly
function Get-AgentContext {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'codex', 'codebuddy', 'claude', 'all')][string]$Agent = 'auto',
        [string]$AgentHome = ''
    )

    if ($Agent -eq 'all') {
        $out = @()
        foreach ($n in @('codex', 'codebuddy', 'claude')) {
            $c = New-AgentContext -Name $n
            if (Test-Path -LiteralPath $c.Home) { $out += $c }
        }
        return $out
    }

    $name = $Agent
    if ($name -eq 'auto') {
        $name = Get-RunningAgentName
        if (-not $name) {
            foreach ($cand in @('codebuddy', 'codex', 'claude')) {
                if (Test-Path -LiteralPath (Get-AgentHomeDefault $cand)) { $name = $cand; break }
            }
        }
        if (-not $name) { $name = 'codex' }
    }

    return , (New-AgentContext -Name $name -HomeOverride $AgentHome)
}

# One-line identity marker, so a transcript shows this skill actually ran. ASCII only: '|', not U+00B7.
# Silence it with $env:LESS_TOKEN_POWERSHELL_QUIET = '1'.
function Write-SkillBanner {
    param(
        [Parameter(Mandatory)][string]$Script,
        [string]$Agent = '',
        [string[]]$Info = @()
    )
    if ($env:LESS_TOKEN_POWERSHELL_QUIET -eq '1') { return }
    if (-not $Agent) { $Agent = Get-RunningAgentName }
    if (-not $Agent) { $Agent = 'auto' }
    $parts = New-Object System.Collections.ArrayList
    $parts.Add("[less-token-powershell] $Script") | Out-Null
    $parts.Add("host=$Agent") | Out-Null
    foreach ($i in $Info) { if ($i) { $parts.Add($i) | Out-Null } }
    Write-Output ($parts -join ' | ')
}
