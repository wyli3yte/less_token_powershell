# force-utf8-output.ps1 - make script output decode deterministically on Windows.
# ASCII-only on purpose, so it needs no BOM.
# Dot-source it:  . (Join-Path $PSScriptRoot 'force-utf8-output.ps1')
#
# Why: Windows PowerShell 5.1 writes console output in the console code page (CP936 on a
# zh-CN box, CP437/1252 elsewhere). An agent capturing that stream then has to guess the
# charset, and it guesses wrong on lines that are mostly ASCII with a couple of CJK bytes
# ("installed: <char>" came back as mojibake while longer CJK lines survived). Pinning both
# encodings to UTF-8 removes the guesswork. PowerShell 7 is already UTF-8; this is a no-op there.
#
# Scope: [Console]::OutputEncoding is per-process. Agents spawn a fresh shell per command, so
# this does not leak into the user's interactive session.

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8NoBom } catch { }
$OutputEncoding = $utf8NoBom
