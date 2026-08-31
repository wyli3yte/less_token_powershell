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
    }
}

# Which agent is running THIS process? Runtime env vars are authoritative;
# fall back to the exe path, then to whichever home directory exists.
function Get-RunningAgentName {
    if ($env:CODEBUDDY_SESSION_ID -or $env:CODEBUDDY_PROJECT_DIR) { return 'codebuddy' }
    if ($env:CODEX_HOME) { return 'codex' }
    $p = (Get-Process -Id $PID).Path
    if ($p -match 'codex')     { return 'codex' }
    if ($p -match 'codebuddy') { return 'codebuddy' }
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
    if ($Name -eq 'codebuddy') {
        $logRoot  = Join-Path $agentHome 'projects'
        $shellVar = 'CODEBUDDY_POWERSHELL_PATH'
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
# -Agent codex|codebuddy -> that host explicitly
function Get-AgentContext {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'codex', 'codebuddy', 'all')][string]$Agent = 'auto',
        [string]$AgentHome = ''
    )

    if ($Agent -eq 'all') {
        $out = @()
        foreach ($n in @('codex', 'codebuddy')) {
            $c = New-AgentContext -Name $n
            if (Test-Path -LiteralPath $c.Home) { $out += $c }
        }
        return $out
    }

    $name = $Agent
    if ($name -eq 'auto') {
        $name = Get-RunningAgentName
        if (-not $name) {
            foreach ($cand in @('codebuddy', 'codex')) {
                if (Test-Path -LiteralPath (Get-AgentHomeDefault $cand)) { $name = $cand; break }
            }
        }
        if (-not $name) { $name = 'codex' }
    }

    return , (New-AgentContext -Name $name -HomeOverride $AgentHome)
}
