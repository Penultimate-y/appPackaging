# Detect-ChromeSplitCC.ps1
# Simple contract: 0 = installed, 1 = not installed

$markerFile = "$env:LOCALAPPDATA\G1001\ChromeSplitCC\install.marker"
$expectedVersion = '1.2.0'

If (-not (Test-Path $markerFile)) {
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

If ($marker.Version -eq $expectedVersion) {
    [Console]::WriteLine("Installed v$($marker.Version)")
    Write-Host "INSTALLED: v$($marker.Version) on $($marker.InstalledOn)" -ForegroundColor Green
    Exit 0
}

Write-Host "NOT INSTALLED: found v$($marker.Version), expected v$expectedVersion" -ForegroundColor Yellow
Exit 1