param([string[]]$Files)
# Checks installers on VirusTotal (API v3): uploads them and waits for the results.
# Needs a VirusTotal API key in the VT_API_KEY environment variable (setx VT_API_KEY "...").
# Without -Files checks installer\GomLike-Setup.exe and installer\GomLike-Setup-Offline.exe.
# Free API keys allow 4 requests per minute, so this takes a few minutes.
$ErrorActionPreference = 'Stop'

$key = $env:VT_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('VT_API_KEY', 'User') }
if (-not $key) { throw 'VT_API_KEY is not set. Get a key at https://www.virustotal.com/gui/my-apikey and run: setx VT_API_KEY "<key>"' }
if (-not $Files) {
    $installer = Join-Path $PSScriptRoot '..\installer' | Resolve-Path
    $Files = 'GomLike-Setup.exe', 'GomLike-Setup-Offline.exe' | ForEach-Object { Join-Path $installer $_ }
}
$h = @{ 'x-apikey' = $key }
$api = 'https://www.virustotal.com/api/v3'

$jobs = foreach ($f in $Files) {
    $item = Get-Item $f
    # files over 32 MB go through a one-time upload URL
    $url = "$api/files"
    if ($item.Length -gt 32MB) { $url = (Invoke-RestMethod -Headers $h -Uri "$api/files/upload_url").data }
    Write-Host ("Uploading {0} ({1} MB)..." -f $item.Name, [math]::Round($item.Length / 1MB, 1))
    $resp = & curl.exe -s --fail-with-body -X POST $url -H "x-apikey: $key" -F "file=@$($item.FullName)"
    if ($LASTEXITCODE -ne 0) { throw "upload of $($item.Name) failed: $resp" }
    [pscustomobject]@{ Name = $item.Name; Id = ($resp | ConvertFrom-Json).data.id; Sha = (Get-FileHash $item.FullName).Hash.ToLower() }
}

foreach ($j in $jobs) {
    do {
        Start-Sleep -Seconds 30
        $a = Invoke-RestMethod -Headers $h -Uri "$api/analyses/$($j.Id)"
        Write-Host ("{0}: {1}" -f $j.Name, $a.data.attributes.status)
    } while ($a.data.attributes.status -ne 'completed')
    $s = $a.data.attributes.stats
    Write-Output ("{0}: malicious={1} suspicious={2} undetected={3} unsupported={4} timeout={5}" -f
        $j.Name, $s.malicious, $s.suspicious, $s.undetected, $s.'type-unsupported', $s.timeout)
    $a.data.attributes.results.PSObject.Properties | Where-Object { $_.Value.category -in 'malicious', 'suspicious' } |
        ForEach-Object { Write-Output ("  {0}: {1} ({2})" -f $_.Name, $_.Value.result, $_.Value.category) }
    Write-Output ("  SHA-256 {0}" -f $j.Sha)
    Write-Output ("  https://www.virustotal.com/gui/file/{0}" -f $j.Sha)
}
