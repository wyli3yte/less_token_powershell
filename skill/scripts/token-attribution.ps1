# token-attribution.ps1 - what did PowerShell failures actually cost, in tokens?
# ASCII-only on purpose: this is a library (see agent-context.ps1 for why), so no BOM either.
#
# Every host records REAL token usage in its transcripts, so nothing here estimates tokens -
# except Get-SkillSelfCost, which counts characters and is labelled as an estimate by the caller.
#
# Measured semantics per host (verified against real transcripts, do not "simplify" this away):
#   codex      payload.info.last_token_usage   = per-turn delta        -> sum
#   claude     message.usage                   = per-request           -> sum (context re-sent each call)
#   codebuddy  providerData.rawUsage.total_tokens / turn-metrics.tokenDelta
#                                              = CUMULATIVE counters  -> must be diffed, never summed
#
#   . (Join-Path $PSScriptRoot 'token-attribution.ps1')
#   Get-TokenAttribution -Files $sessions -Agent 'codex' -MaxFileMB 256
#   Get-SkillSelfCost -SkillDir $PSScriptRoot\.. -Agent 'codebuddy'

$script:HostMarkers = @{
    'codebuddy' = @{
        Boundary = '"function_call_result"'; Result = '"function_call_result"'
        Usage = '"rawUsage"'; CumAlt = '"tokenDelta"'; Cumulative = $true
    }
    'claude' = @{
        Boundary = '"type":"assistant"'; Result = '"tool_result"'
        Usage = '"usage"'; CumAlt = ''; Cumulative = $false
    }
    'codex' = @{
        Boundary = '"token_count"'; Result = '"function_call_output"'
        Usage = '"last_token_usage"'; CumAlt = ''; Cumulative = $false
    }
}

# Only PowerShell failures count - a bare "Exit code 1" from git or npm is not this skill's tax.
# ASCII patterns only: PowerShell prints the English category name and the harness prints an exit
# code, so this stays accurate on a zh-CN box. Broader than this and the number stops being honest.
function Test-PsFailureLine {
    param([string]$Line)
    if (-not $Line) { return $false }
    if ($Line.IndexOf('ParserError', [StringComparison]::Ordinal) -ge 0) { return $true }
    if ($Line.IndexOf('MissingEndCurlyBrace', [StringComparison]::Ordinal) -ge 0) { return $true }
    if ($Line.IndexOf('is not a valid statement separator in this version', [StringComparison]::Ordinal) -ge 0) { return $true }
    if ($Line.IndexOf('CategoryInfo', [StringComparison]::Ordinal) -ge 0) { return $true }
    if ($Line.IndexOf('FullyQualifiedErrorId', [StringComparison]::Ordinal) -ge 0) { return $true }
    if ($Line -match 'Exit [Cc]ode:?\s*[1-9]') {
        if ($Line.IndexOf('powershell', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        if ($Line.IndexOf('pwsh', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

# Returns @{ Per = <tokens for this entry>; Cum = <cumulative counter reading or $null> }
function Get-LineTokens {
    param($Json, [Parameter(Mandatory)][string]$Agent)
    $t = 0
    if ($Agent -eq 'codex') {
        $u = $Json.payload.info.last_token_usage
        if (-not $u) { return @{ Per = 0; Cum = $null } }
        if ($u.total_tokens) { return @{ Per = [int]$u.total_tokens; Cum = $null } }
        foreach ($p in @('input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens')) {
            if ($u.$p) { $t += [int]$u.$p }
        }
        return @{ Per = $t; Cum = $null }
    }
    if ($Agent -eq 'claude') {
        $u = $Json.message.usage
        if (-not $u) { return @{ Per = 0; Cum = $null } }
        foreach ($p in @('input_tokens', 'output_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')) {
            if ($u.$p) { $t += [int]$u.$p }
        }
        return @{ Per = $t; Cum = $null }
    }
    # codebuddy: both fields are cumulative counters; either one is a reading, not a delta.
    if ($Json.tokenDelta) { return @{ Per = 0; Cum = [int]$Json.tokenDelta } }
    $u = $Json.providerData.rawUsage
    if (-not $u) { return @{ Per = 0; Cum = $null } }
    if ($u.total_tokens) { return @{ Per = 0; Cum = [int]$u.total_tokens } }
    foreach ($p in @('prompt_tokens', 'completion_tokens', 'input_tokens', 'output_tokens')) {
        if ($u.$p) { $t += [int]$u.$p }
    }
    return @{ Per = 0; Cum = $t }
}

function Add-Turn {
    param($Turns, [int]$Tokens, [bool]$Failed, [bool]$Success)
    $Turns.Add([pscustomobject]@{
        Tokens = $Tokens
        Failed = $Failed
        Clean  = ($Success -and -not $Failed)
    }) | Out-Null
}

# Stream one transcript into turns, then attribute tokens. Never loads a whole file into memory:
# the codex tree holds a 1.1 GB file, and PS 5.1 ConvertFrom-Json caps at ~2 MB per line.
function Get-TokenAttribution {
    param(
        [Parameter(Mandatory)][object[]]$Files,
        [Parameter(Mandatory)][string]$Agent,
        [int]$MaxFileMB = 256,
        [int]$RetryCap = 5
    )
    $m = $script:HostMarkers[$Agent]
    $stats = [pscustomobject]@{
        Agent = $Agent; Files = 0; Turns = 0; FailTurns = 0
        UpperBound = 0; Retry = 0; Truncated = 0; OverWindow = 0
        SkipBig = 0; SkipBigBytes = 0; SkipLong = 0; SkipParse = 0
    }
    if (-not $m) { return $stats }

    foreach ($f in $Files) {
        if ($MaxFileMB -gt 0 -and $f.Length -gt ($MaxFileMB * 1048576)) {
            $stats.SkipBig++
            $stats.SkipBigBytes += $f.Length
            continue
        }
        $stats.Files++
        $turns = New-Object System.Collections.ArrayList
        $curPer = 0; $lastCum = 0; $curCum = $null
        $curFailed = $false; $curSuccess = $false

        foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
            if ($line.Length -gt 200000) {
                $stats.SkipLong++
                if (Test-PsFailureLine $line) { $curFailed = $true }
                continue
            }
            # Cheap ordinal prefilter: no marker, no regex, no JSON parse.
            $hit = $false
            foreach ($k in @($m.Boundary, $m.Result, $m.Usage, $m.CumAlt)) {
                if ($k -and $line.IndexOf($k, [StringComparison]::Ordinal) -ge 0) { $hit = $true; break }
            }
            if (-not $hit) {
                if ($line.IndexOf('ParserError', [StringComparison]::Ordinal) -ge 0) { $hit = $true }
                elseif ($line.IndexOf('Exit ', [StringComparison]::Ordinal) -ge 0) { $hit = $true }
            }
            if (-not $hit) { continue }

            $thisFailed = Test-PsFailureLine $line
            if ($thisFailed) { $curFailed = $true }
            if (-not $thisFailed -and $line.IndexOf($m.Result, [StringComparison]::Ordinal) -ge 0) { $curSuccess = $true }

            $per = 0
            $isBoundary = $line.IndexOf($m.Boundary, [StringComparison]::Ordinal) -ge 0
            $wantJson = $isBoundary
            if (-not $wantJson -and $line.IndexOf($m.Usage, [StringComparison]::Ordinal) -ge 0) { $wantJson = $true }
            if (-not $wantJson -and $m.CumAlt -and $line.IndexOf($m.CumAlt, [StringComparison]::Ordinal) -ge 0) { $wantJson = $true }
            if ($wantJson) {
                try {
                    $u = Get-LineTokens -Json ($line | ConvertFrom-Json) -Agent $Agent
                    $per = $u.Per
                    if ($u.Cum -ne $null) { $curCum = $u.Cum }
                } catch { $stats.SkipParse++ }
            }

            if ($isBoundary) {
                if ($m.Cumulative) {
                    $base = if ($curCum -ne $null) { $curCum } else { $lastCum }
                    $delta = $base - $lastCum
                    if ($delta -lt 0) { $delta = 0 }
                    Add-Turn $turns ([int]$delta) $curFailed $curSuccess
                    $lastCum = $base
                } else {
                    Add-Turn $turns ($curPer + $per) $curFailed $curSuccess
                    $curPer = 0
                }
                $curFailed = $false; $curSuccess = $false
            } else {
                $curPer += $per
            }
        }
        if ($curPer -gt 0 -or $curFailed -or $curSuccess) {
            Add-Turn $turns $curPer $curFailed $curSuccess
        }

        $stats.Turns += $turns.Count
        # Non-overlapping windows: after measuring a retry sequence, resume AT the clean turn, so a
        # run of consecutive failures cannot count the same turn twice.
        $i = 0
        while ($i -lt $turns.Count) {
            if (-not $turns[$i].Failed) { $i++; continue }
            $stats.FailTurns++
            $stats.UpperBound += $turns[$i].Tokens
            $limit = [Math]::Min($i + 1 + $RetryCap, $turns.Count)
            $clean = -1
            for ($k = $i + 1; $k -lt $limit; $k++) {
                if ($turns[$k].Clean) { $clean = $k; break }
            }
            if ($clean -lt 0) {
                if ($limit -lt $turns.Count) { $stats.OverWindow++ } else { $stats.Truncated++ }
                $i++
                continue
            }
            for ($k = $i + 1; $k -lt $clean; $k++) { $stats.Retry += $turns[$k].Tokens }
            $i = $clean + 1
        }
    }
    return $stats
}

# What the skill itself costs when loaded: SKILL.md plus the one host mapping file it points at.
# Character heuristic (CJK ~1.5 chars/token, rest ~4 chars/token) - an ESTIMATE, not a measurement.
function Get-SkillSelfCost {
    param(
        [Parameter(Mandatory)][string]$SkillDir,
        [Parameter(Mandatory)][string]$Agent
    )
    $text = ''
    $names = @()
    $skill = Join-Path $SkillDir 'SKILL.md'
    $map = Join-Path $SkillDir ("references/$Agent-tools.md")
    if (Test-Path -LiteralPath $skill) { $text += [System.IO.File]::ReadAllText($skill); $names += 'SKILL.md' }
    if (Test-Path -LiteralPath $map) { $text += [System.IO.File]::ReadAllText($map); $names += "references/$Agent-tools.md" }
    if (-not $text) { return $null }
    $cjk = [regex]::Matches($text, '[\u3000-\u9FFF\uFF00-\uFFEF]').Count
    $tokens = [int][Math]::Round($cjk / 1.5 + ($text.Length - $cjk) / 4)
    return [pscustomobject]@{
        Files = ($names -join ' + ')
        Chars = $text.Length
        Cjk   = $cjk
        Tokens = $tokens
    }
}
