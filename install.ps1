[CmdletBinding()]
param()

$root = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$dest = Join-Path $root 'skills\windows-powershell7-setup'
$src  = Join-Path $PSScriptRoot 'skill'

Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
"Installed skill to: $dest"
