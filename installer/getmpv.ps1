param([Parameter(Mandatory = $true)][string]$Dest)
# Downloads the latest mpv build for Windows and puts it into $Dest (used by GomLike-Setup.exe)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tmp = Join-Path $env:TEMP ("gomlike_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Output "Looking up latest mpv build..."
    $rel = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest' -Headers @{ 'User-Agent' = 'GomLike-Setup' }
    $asset = $rel.assets | Where-Object { $_.name -match '^mpv-x86_64-\d{8}-git-[0-9a-f]+\.7z$' } | Select-Object -First 1
    if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match '^mpv-x86_64-.*\.7z$' -and $_.name -notmatch 'v3' } | Select-Object -First 1 }
    if (-not $asset) { throw "mpv archive not found in release $($rel.tag_name)" }

    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'GomLike-Setup')
    Write-Output ("Downloading {0} ({1} MB)..." -f $asset.name, [math]::Round($asset.size / 1MB))
    $archive = Join-Path $tmp $asset.name
    $wc.DownloadFile($asset.browser_download_url, $archive)

    Write-Output "Downloading 7zr.exe from 7-zip.org..."
    $sevenZip = Join-Path $tmp '7zr.exe'
    $wc.DownloadFile('https://www.7-zip.org/a/7zr.exe', $sevenZip)

    Write-Output "Extracting..."
    $out = Join-Path $tmp 'mpv'
    & $sevenZip x $archive "-o$out" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "extraction failed" }
    $exe = Get-ChildItem $out -Recurse -Filter 'mpv.exe' | Select-Object -First 1
    if (-not $exe) { throw "mpv.exe not found in archive" }

    # Only the player itself: no updater, no stock installer or file association scripts
    $skip = @('portable_config', 'installer', 'updater.bat', 'updater.ps1', 'mpv-register.bat', 'mpv-unregister.bat')
    $items = Get-ChildItem $exe.DirectoryName | Where-Object { $skip -notcontains $_.Name }
    foreach ($i in $items) { Copy-Item $i.FullName -Destination $Dest -Recurse -Force }
    $items | ForEach-Object { $_.Name } | Set-Content -Path (Join-Path $Dest 'gomlike-files.txt') -Encoding ASCII

    # Where this exact mpv build comes from (mpv is GPLv2+, see licenses\mpv)
    $src = @(
        "mpv build: $($asset.name)",
        "Build release: https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/$($rel.tag_name)",
        "Build scripts: https://github.com/shinchiro/mpv-winbuild-cmake"
    )
    if ($asset.name -match '-git-([0-9a-f]+)\.7z$') { $src += "mpv source: https://github.com/mpv-player/mpv/tree/$($Matches[1])" }
    $src | Set-Content -Path (Join-Path $Dest 'mpv-source.txt') -Encoding ASCII
    if (-not (Test-Path (Join-Path $Dest 'mpv.exe'))) { throw "mpv.exe was not copied" }
    Write-Output "mpv installed."
    exit 0
}
catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
    exit 1
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
