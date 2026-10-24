<#
.SYNOPSIS
    Detection script for Windows Update ESP installation

.DESCRIPTION
    Checks if the Windows Update installation script has completed successfully
    by verifying the presence and validity of the marker file.

    Used as the detection script for Intune Win32 app deployment with PSADT v4.

.NOTES
    Version:        1.0.0
    Author:         Zachary Hayward with Claude Code-claude-sonnet-4-5
    Creation Date:  2026-06-20

    Returns:
    - Exit 0 + stdout: Updates were installed/checked successfully (app is "installed")
    - Exit 1: App not installed or updates pending
#>

$markerFile = "$env:ProgramData\WindowsUpdate-ESP\UpdatesInstalled.json"
$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$logFile = "$logPath\WindowsUpdate-ESP-Detection.log"

function Write-Log {
    param([string]$Message)
    if (!(Test-Path $logPath)) {
        New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    }
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp - $Message"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

Write-Log "=== Windows Update ESP Detection Started ==="

try {
    # Check if marker file exists
    if (Test-Path $markerFile) {
        Write-Log "Marker file found: $markerFile"

        # Read marker file
        $markerData = Get-Content -Path $markerFile -Raw | ConvertFrom-Json
        Write-Log "Install Date: $($markerData.InstallDate)"
        Write-Log "Updates Installed: $($markerData.UpdateCount)"
        Write-Log "Reboot Required: $($markerData.RebootRequired)"

        # Verify the marker file is recent (within last 7 days)
        $installDate = [DateTime]::ParseExact($markerData.InstallDate, "yyyy-MM-dd HH:mm:ss", $null)
        $daysSinceInstall = ((Get-Date) - $installDate).Days

        Write-Log "Days since installation: $daysSinceInstall"

        if ($daysSinceInstall -le 7) {
            Write-Log "Detection successful - updates were installed/checked within last 7 days"
            Write-Log "=== Windows Update ESP Detection: INSTALLED ==="

            # Output to stdout for Intune detection
            Write-Output "Windows Update ESP installed - $($markerData.UpdateCount) updates installed on $($markerData.InstallDate)"
            exit 0
        } else {
            Write-Log "Marker file is older than 7 days - may need to re-run"
            Write-Log "=== Windows Update ESP Detection: NOT INSTALLED ==="
            exit 1
        }

    } else {
        Write-Log "Marker file not found - app has not been installed yet"
        Write-Log "=== Windows Update ESP Detection: NOT INSTALLED ==="
        exit 1
    }

} catch {
    Write-Log "ERROR during detection: $($_.Exception.Message)"
    Write-Log "=== Windows Update ESP Detection: NOT INSTALLED ==="
    exit 1
}
