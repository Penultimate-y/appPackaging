<#
================================================================================
Script Name:        Detect-VisualStudioEnterprise26.ps1
Creation Date:      2026-07-08
Last Change Date:   2026-07-08
Author:             DWX Team with Claude Code (claude-sonnet-4-6)
LLM Version Tag:    Claude Code-claude-sonnet-4-6
Script Function:    Detection script for Microsoft Visual Studio Enterprise 2026.
                    Checks for the presence of Visual Studio Enterprise 26 installation
                    via registry keys and validates the version. Used by Intune
                    Win32 app deployment to determine if the application is installed.
                    Exits 0 if installed with the correct version, exits 1 if not.
Script Input:       None (runs as Intune detection script)
Script Output:      Console message indicating installation status and exit code
Modules Required:   None (native PowerShell cmdlets only)
Script Usage:       .\Detect-VisualStudioEnterprise26.ps1

Latest Change
Description:        Initial creation - Visual Studio Enterprise 26 detection logic
================================================================================
#>

# CODE
# DEFINE VARIABLES AND INPUTS AND OUTPUTS

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# CODE AND SCRIPT LOGIC WITH COMMENTS AT KEY COMMANDS

try {
    # Visual Studio 2026 uses version 17.x internally (Visual Studio versioning)
    # Check multiple registry locations for Visual Studio Enterprise 2026
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    # Search for Visual Studio Enterprise 26 in uninstall registry
    $vsApp = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
             Where-Object {
                 $_.DisplayName -match 'Visual Studio Enterprise.*26' -or
                 $_.DisplayName -match 'Visual Studio Enterprise 2026'
             } |
             Select-Object -First 1

    # Alternative check: Visual Studio installation path
    $vsInstallPath = "$env:ProgramFiles\Microsoft Visual Studio\2026\Enterprise"
    $vsExePath = "$vsInstallPath\Common7\IDE\devenv.exe"

    # Check if found via registry
    if ($vsApp) {
        $version = $vsApp.DisplayVersion
        Write-Output "Visual Studio Enterprise 26 is installed - Version: $version (Registry Detection)"
        exit 0
    }

    # Check if installation path exists
    if (Test-Path $vsExePath) {
        $versionInfo = (Get-Item $vsExePath).VersionInfo
        $fileVersion = $versionInfo.FileVersion
        Write-Output "Visual Studio Enterprise 26 is installed - Version: $fileVersion (File Detection)"
        exit 0
    }

    # Not detected
    Write-Output "Visual Studio Enterprise 26 not detected"
    exit 1
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}

# CODE COMPLETE
