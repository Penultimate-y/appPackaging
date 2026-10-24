<#
.SYNOPSIS
    Detection script for Kiro IDE installation

.DESCRIPTION
    Checks if Kiro IDE is installed by verifying the executable exists.
    Since we always download the latest version, this detects ANY installed version.

.NOTES
    Version:        1.0.0
    Author:         Zachary Hayward with Claude Code-claude-sonnet-4-5
    Creation Date:  2026-06-20

    Returns:
    - Exit 0 + stdout: Kiro IDE is installed (app is "installed")
    - Exit 1: Kiro IDE is not installed
#>

$kiroPath = "$env:LOCALAPPDATA\Programs\Kiro\Kiro.exe"

try {
    if (Test-Path $kiroPath) {
        # Get version from file properties
        $fileVersion = (Get-Item $kiroPath).VersionInfo.FileVersion

        # Output to stdout for Intune detection
        Write-Output "Kiro IDE is installed - Version: $fileVersion"
        exit 0
    } else {
        exit 1
    }
} catch {
    exit 1
}
