param([switch]$Test, [switch]$UpdateMpv)
# Builds two installers on Windows (needs NSIS: winget install NSIS.NSIS):
#   installer\GomLike-Setup.exe          downloads mpv during installation
#   installer\GomLike-Setup-Offline.exe  mpv inside, no internet needed
# mpv for the offline one is downloaded once into installer\mpv and reused;
# -UpdateMpv downloads a fresh build.
# -Test builds only installer\test-setup.exe with a stub instead of mpv
$ErrorActionPreference = 'Stop'

$makensis = (Get-Command makensis.exe -ErrorAction SilentlyContinue).Source
if (-not $makensis) {
    $makensis = @("${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $makensis) { throw "makensis.exe not found. Install NSIS: winget install NSIS.NSIS" }

function Build([string[]]$Defines, [string]$Out) {
    $nsisArgs = @('/V2') + ($Defines | ForEach-Object { "/D$_" })
    & $makensis @nsisArgs 'GomLike.nsi'
    if ($LASTEXITCODE -ne 0) { throw "makensis failed with exit code $LASTEXITCODE" }
    Write-Output ("Done: installer\{0} ({1} MB)" -f $Out, [math]::Round((Get-Item $Out).Length / 1MB, 1))
}

$installer = Join-Path $PSScriptRoot '..\installer' | Resolve-Path
$payload = Join-Path $installer 'payload'
$mpv = Join-Path $installer 'mpv'
Push-Location $installer
try {
    if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
    New-Item -ItemType Directory -Path $payload | Out-Null
    Copy-Item '..\player\portable_config', '..\player\README.txt' -Destination $payload -Recurse

    if ($Test) { Build @('TEST') 'test-setup.exe'; return }

    Build @() 'GomLike-Setup.exe'

    if ($UpdateMpv -or -not (Test-Path (Join-Path $mpv 'mpv.exe'))) {
        $fresh = "$mpv.new"
        if (Test-Path $fresh) { Remove-Item $fresh -Recurse -Force }
        New-Item -ItemType Directory -Path $fresh | Out-Null
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $installer 'getmpv.ps1') -Dest $fresh
        if ($LASTEXITCODE -ne 0) { Remove-Item $fresh -Recurse -Force; throw "mpv download failed" }
        if (Test-Path $mpv) { Remove-Item $mpv -Recurse -Force }
        Rename-Item $fresh 'mpv'
    }
    else {
        Write-Output ("Using mpv from installer\mpv, build of {0:yyyy-MM-dd} (-UpdateMpv for a fresh one)" -f (Get-Item (Join-Path $mpv 'mpv.exe')).LastWriteTime)
    }
    Build @('OFFLINE') 'GomLike-Setup-Offline.exe'
}
finally {
    Remove-Item $payload -Recurse -Force -ErrorAction SilentlyContinue
    Pop-Location
}
