param([switch]$Test)
# Builds installer\GomLike-Setup.exe on Windows (needs NSIS: winget install NSIS.NSIS)
# -Test builds installer\test-setup.exe with a stub instead of downloading mpv
$ErrorActionPreference = 'Stop'

$makensis = (Get-Command makensis.exe -ErrorAction SilentlyContinue).Source
if (-not $makensis) {
    $makensis = @("${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $makensis) { throw "makensis.exe not found. Install NSIS: winget install NSIS.NSIS" }

$installer = Join-Path $PSScriptRoot '..\installer' | Resolve-Path
$payload = Join-Path $installer 'payload'
Push-Location $installer
try {
    if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
    New-Item -ItemType Directory -Path $payload | Out-Null
    Copy-Item '..\player\portable_config', '..\player\README.txt' -Destination $payload -Recurse

    $nsisArgs = @('/V2')
    if ($Test) { $nsisArgs += '/DTEST' }
    & $makensis @nsisArgs 'GomLike.nsi'
    if ($LASTEXITCODE -ne 0) { throw "makensis failed with exit code $LASTEXITCODE" }

    $out = if ($Test) { 'test-setup.exe' } else { 'GomLike-Setup.exe' }
    Write-Output "Done: installer\$out"
}
finally {
    Remove-Item $payload -Recurse -Force -ErrorAction SilentlyContinue
    Pop-Location
}
