# pwsh-discovery.ps1 - find PowerShell 7 installations and classify them.
# ASCII-only on purpose: this is a library, it emits data (not messages), so it needs no BOM.
# Dot-source it:  . (Join-Path $PSScriptRoot 'pwsh-discovery.ps1')
#
# The distinction that matters: a GLOBAL install serves every agent and every terminal on this
# machine. An agent's BUNDLED copy serves only that agent, lives in a versioned private cache,
# and can disappear when the agent upgrades. Only a global install satisfies the goal of this
# skill, so the two are discovered separately and never merged.

# Paths that belong to some agent's private runtime, not to the machine.
$script:AgentPrivatePwshPatterns = @(
    '\.cache\\codex-runtimes\\',
    '\\codex-primary-runtime\\'
)

function Test-IsAgentPrivatePwsh {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($pat in $script:AgentPrivatePwshPatterns) {
        if ($Path -match $pat) { return $true }
    }
    return $false
}

function New-PwshHit {
    param([string]$Path, [string]$Scope, [string]$Via)
    [pscustomobject]@{ Path = $Path; Scope = $Scope; Via = $Via }
}

# Every PowerShell 7+ install that is available machine-wide or user-wide.
# Deliberately globs the major-version folder (`PowerShell\*`) instead of hardcoding `7`,
# so a future PowerShell 8 is still found.
function Get-GlobalPwshPath {
    $hits = @()

    $globs = @(
        @{ G = (Join-Path $env:ProgramFiles 'PowerShell\*\pwsh.exe');                Scope = 'machine'; Via = 'program-files' },
        @{ G = (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\*\pwsh.exe');         Scope = 'machine'; Via = 'program-files-x86' },
        @{ G = (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\*\pwsh.exe');       Scope = 'user';    Via = 'winget-user' },
        @{ G = (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe');       Scope = 'user';    Via = 'windowsapps' }
    )
    foreach ($g in $globs) {
        foreach ($f in @(Get-ChildItem -Path $g.G -File -ErrorAction SilentlyContinue)) {
            $hits += New-PwshHit -Path $f.FullName -Scope $g.Scope -Via $g.Via
        }
    }

    # Registry uninstall entries are the authoritative record of an MSI install: they catch
    # installs that landed somewhere non-standard.
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($e in @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'PowerShell\s+\d' })) {
        if (-not $e.InstallLocation) { continue }
        $exe = Join-Path $e.InstallLocation 'pwsh.exe'
        if (Test-Path -LiteralPath $exe) {
            $scope = if ($e.PSPath -match 'HKEY_CURRENT_USER|HKCU') { 'user' } else { 'machine' }
            $hits += New-PwshHit -Path $exe -Scope $scope -Via 'registry'
        }
    }

    # MSIX/Store installs write no uninstall entry, and their execution alias can go missing.
    foreach ($p in @(Get-AppxPackage -Name 'Microsoft.PowerShell*' -ErrorAction SilentlyContinue)) {
        if (-not $p.InstallLocation) { continue }
        $exe = Join-Path $p.InstallLocation 'pwsh.exe'
        if (Test-Path -LiteralPath $exe) { $hits += New-PwshHit -Path $exe -Scope 'user' -Via 'appx' }
    }

    # The pwsh MSI leaves ARP InstallLocation empty; the persisted PATH catches those installs.
    $pathRoots = @(
        @{ K = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Scope = 'machine'; Via = 'machine-path' },
        @{ K = 'HKCU:\Environment';                                                                              Scope = 'user';    Via = 'user-path' }
    )
    foreach ($r in $pathRoots) {
        $e = Get-ItemProperty $r.K -ErrorAction SilentlyContinue
        if (-not $e -or -not $e.Path) { continue }
        foreach ($dir in @($e.Path -split ';' | Where-Object { $_ })) {
            $exe = Join-Path $dir 'pwsh.exe'
            if (Test-Path -LiteralPath $exe) { $hits += New-PwshHit -Path $exe -Scope $r.Scope -Via $r.Via }
        }
    }

    # Anything already resolvable as `pwsh` counts too, as long as it is not 5.1 and not private.
    foreach ($c in @(Get-Command pwsh -All -ErrorAction SilentlyContinue)) {
        if ($c.Source -and $c.Source -notmatch 'WindowsPowerShell') {
            $hits += New-PwshHit -Path $c.Source -Scope 'user' -Via 'path'
        }
    }

    $hits = @($hits | Where-Object { -not (Test-IsAgentPrivatePwsh $_.Path) })
    # Prefer machine scope, then path stability: a versioned Appx dir moves on every Store update.
    $rank = @{ 'program-files' = 0; 'program-files-x86' = 1; 'machine-path' = 2; 'registry' = 3; 'winget-user' = 4; 'user-path' = 5; 'windowsapps' = 6; 'path' = 7; 'appx' = 8 }
    return @($hits | Sort-Object @{ E = { $_.Scope -ne 'machine' } }, @{ E = { $rank[$_.Via] } }, Path |
                     Group-Object Path | ForEach-Object { $_.Group[0] })
}

# PowerShell 7 shipped inside an agent's own runtime. Usable, but private to that agent.
# Missing these produces a false "no PowerShell 7 anywhere" reading; counting them as global
# produces the opposite error. Report them, never merge them.
function Get-BundledPwshPath {
    $globs = @(
        # Codex runtime cache, measured:
        #   ~\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\*\dependencies\native\powershell\pwsh.exe')
    )
    $out = @()
    foreach ($g in $globs) {
        $out += @(Get-ChildItem -Path $g -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    return $out
}

function Get-PwshVersion {
    param([Parameter(Mandatory)][string]$Exe)
    (& $Exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null) -join ''
}
