[CmdletBinding()]
param(
    # all (default) = every host present on the machine; auto = only the host running this process
    [ValidateSet('auto', 'codex', 'codebuddy', 'claude', 'all')][string]$Agent = 'all',
    # Remove the destination first instead of copying over it. Destructive: only stale
    # files from a previous version are lost, but it does delete a directory.
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'skill\scripts\agent-context.ps1')

$src = Join-Path $PSScriptRoot 'skill'
$contexts = Get-AgentContext -Agent $Agent
if ($Agent -eq 'all' -and $contexts.Count -eq 0) {
    throw 'No agent home directory found on this machine. Pass -Agent codex or -Agent codebuddy.'
}

foreach ($ctx in $contexts) {
    $dest = Join-Path $ctx.SkillDir 'less-token-powershell'

    if ($Clean -and (Test-Path -LiteralPath $dest)) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    # Copy the CONTENTS, not the directory: Copy-Item -Recurse nests the source folder inside an
    # existing destination, which silently produced <dest>\skill on every reinstall.
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force

    "Installed skill for $($ctx.Name): $dest"
}
