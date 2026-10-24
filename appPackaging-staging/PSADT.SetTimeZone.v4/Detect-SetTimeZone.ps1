# Detect-SetTimeZone.ps1
# Intune Win32 detection contract: stdout + Exit 0 = installed, no stdout + Exit 1 = not installed
# Returns "not installed" on genuine drift (current Windows TZ != IP-derived TZ) so Intune re-runs install.
# Returns "installed" when offline / API unavailable to avoid hammering ipinfo.io on every evaluation.

$markerFile      = "$env:ProgramData\G1001\TimeZoneByIP\install.marker"
$persistentXml   = "$env:ProgramData\G1001\TimeZoneByIP\windowsZones.xml"
$expectedVersion = '2.0.0'
$ipInfoUrl       = 'https://ipinfo.io/json'  # ✓ Fixed: HTTPS instead of HTTP
$ipInfoTimeout   = 5

if (-not (Test-Path $markerFile)) {
    Write-Host "NOT INSTALLED: marker file not found" -ForegroundColor Yellow
    Exit 1
}

Try {
    $marker = Get-Content $markerFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
Catch {
    Write-Host "NOT INSTALLED: marker file unreadable - $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}

if ($marker.Version -ne $expectedVersion) {
    Write-Host "NOT INSTALLED: marker version $($marker.Version), expected $expectedVersion" -ForegroundColor Yellow
    Exit 1
}

# Drift check - only declares "not installed" on positive evidence of drift.
# Any failure mode (offline, missing XML, unmapped zone) falls back to "trust the stamp".
if (-not (Test-Path $persistentXml)) {
    [Console]::WriteLine("Installed v$($marker.Version) - stamp present; XML unavailable for drift check")
    Write-Host "INSTALLED: v$($marker.Version) (drift check skipped, XML missing)" -ForegroundColor Green
    Exit 0
}

$ianaTz = $null
Try {
    $ianaTz = (Invoke-RestMethod -Uri $ipInfoUrl -TimeoutSec $ipInfoTimeout).timezone
} Catch {
    # Log the error type for diagnostics but don't fail detection
    [Console]::WriteLine("Installed v$($marker.Version) - IP lookup failed: $($_.Exception.Message)")
}

if (-not $ianaTz) {
    [Console]::WriteLine("Installed v$($marker.Version) - stamp present; IP lookup unavailable")
    Write-Host "INSTALLED: v$($marker.Version) (drift check skipped, offline)" -ForegroundColor Green
    Exit 0
}

Try {
    [xml]$windowsZones = Get-Content -LiteralPath $persistentXml -Raw -ErrorAction Stop
    $mapping = $windowsZones.supplementalData.windowsZones.mapTimezones.mapZone | Where-Object {
        $_.type -split ' ' -contains $ianaTz
    }
    $expectedTZ = ($mapping.other | Select-Object -First 1)
} Catch {
    [Console]::WriteLine("Installed v$($marker.Version) - stamp present; XML parse error: $($_.Exception.Message)")
    Write-Host "INSTALLED: v$($marker.Version) (drift check skipped, XML error)" -ForegroundColor Green
    Exit 0
}

if (-not $expectedTZ) {
    [Console]::WriteLine("Installed v$($marker.Version) - stamp present; no mapping for $ianaTz")
    Write-Host "INSTALLED: v$($marker.Version) (no mapping for IANA=$ianaTz)" -ForegroundColor Green
    Exit 0
}

$currentTZ = (Get-TimeZone).Id

if ($currentTZ -ne $expectedTZ) {
    Write-Host "NOT INSTALLED: drift detected (current=$currentTZ, expected=$expectedTZ for IANA=$ianaTz)" -ForegroundColor Yellow
    Exit 1
}

[Console]::WriteLine("Installed v$($marker.Version) - TZ=$currentTZ matches IANA=$ianaTz")
Write-Host "INSTALLED: v$($marker.Version), TZ=$currentTZ, IANA=$ianaTz" -ForegroundColor Green
Exit 0
