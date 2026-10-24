# Detect-SetTimeZone.ps1 (User Select Version)
# Intune Win32 detection contract: stdout + Exit 0 = installed, no stdout + Exit 1 = not installed
# For user-selected timezone, we check if the marker exists and if the timezone hasn't been changed externally.
# No automatic drift correction - user's manual selection is trusted.

$markerFile      = "$env:ProgramData\G1001\TimeZoneUserSelect\install.marker"
$expectedVersion = '2.0.0'

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

# Verify the timezone in the marker still matches the system
# If someone changed it externally, report as "not installed" to trigger re-selection
$currentTZ = (Get-TimeZone).Id
$markerTZ = $marker.WindowsTZ

if ($currentTZ -ne $markerTZ) {
    Write-Host "NOT INSTALLED: timezone changed externally (current=$currentTZ, expected=$markerTZ)" -ForegroundColor Yellow
    Exit 1
}

[Console]::WriteLine("Installed v$($marker.Version) - TZ=$currentTZ (user selected)")
Write-Host "INSTALLED: v$($marker.Version), TZ=$currentTZ (user selected)" -ForegroundColor Green
Exit 0
