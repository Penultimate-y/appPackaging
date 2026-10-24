<#
================================================================================
Script Name:        Detect-Zoom.ps1
Creation Date:      2026-09-17
Last Change Date:   2026-09-17
Author:             DWX Team with Claude Code
LLM Version Tag:    Claude Code
Script Function:    Detection script for Zoom installation.
                    Checks for the presence of Zoom installation via registry
                    keys and file system validation. Used by Intune Win32 app
                    deployment to determine if the application is installed.
                    Returns version information if installed, exits 0.
                    Exits 1 if not installed.
Script Input:       None (runs as Intune detection script)
Script Output:      Console message indicating installation status and exit code
Modules Required:   None (native PowerShell cmdlets only)
Script Usage:       .\Detect-Zoom.ps1

Latest Change
Description:        Initial detection script for Zoom PSADT package.
                    Detects Zoom installation via registry uninstall keys
                    and file system paths. Outputs version information.
================================================================================
#>

# CODE
# DEFINE VARIABLES AND INPUTS AND OUTPUTS

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# CODE AND SCRIPT LOGIC WITH COMMENTS AT KEY COMMANDS

try
{
    ## Define registry paths to search for Zoom installation
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    ## Search for Zoom in uninstall registry keys
    Write-Output "Checking registry for Zoom installation..."
    $zoomApp = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
               Where-Object {
                   $_.DisplayName -match 'Zoom'
               } |
               Select-Object -First 1

    if ($zoomApp)
    {
        $displayName = $zoomApp.DisplayName
        $displayVersion = $zoomApp.DisplayVersion
        $publisher = $zoomApp.Publisher

        Write-Output "Zoom detected via registry:"
        Write-Output "  Name: $displayName"
        Write-Output "  Version: $displayVersion"
        Write-Output "  Publisher: $publisher"

        ## Output version to stdout for Intune detection
        Write-Output "Zoom is installed - Version: $displayVersion (Registry Detection)"
        exit 0
    }

    ## Registry not found - check file system
    Write-Output "Registry not found. Checking file system..."

    ## Define common Zoom installation paths
    $zoomInstallPaths = @(
        "C:\Program Files\Zoom\bin\Zoom.exe",
        "C:\Program Files (x86)\Zoom\bin\Zoom.exe",
        "$env:ProgramFiles\Zoom\Zoom.exe",
        "$env:ProgramFiles(x86)\Zoom\Zoom.exe",
        "$env:LOCALAPPDATA\Programs\Zoom\Zoom.exe"
    )

    $zoomExeFound = $false
    $zoomExePath = $null

    foreach ($path in $zoomInstallPaths)
    {
        if (Test-Path $path)
        {
            $zoomExePath = $path
            $zoomExeFound = $true
            break
        }
    }

    if ($zoomExeFound)
    {
        try
        {
            ## Attempt to get version from file properties
            $versionInfo = (Get-Item $zoomExePath).VersionInfo
            $fileVersion = $versionInfo.FileVersion
            $productVersion = $versionInfo.ProductVersion

            if ($fileVersion)
            {
                Write-Output "Zoom detected via file system:"
                Write-Output "  Path: $zoomExePath"
                Write-Output "  File Version: $fileVersion"
                Write-Output "  Product Version: $productVersion"

                Write-Output "Zoom is installed - Version: $fileVersion (File Detection)"
            }
            else
            {
                Write-Output "Zoom detected via file system:"
                Write-Output "  Path: $zoomExePath"
                Write-Output "  File exists but version information not available"

                Write-Output "Zoom is installed (File Detection, version not available)"
            }
            exit 0
        }
        catch
        {
            ## File exists but version info unavailable - still consider it installed
            Write-Output "Zoom detected via file system:"
            Write-Output "  Path: $zoomExePath"

            Write-Output "Zoom is installed (File Detection)"
            exit 0
        }
    }

    ## Check Zoom registry configuration key (additional verification)
    Write-Output "Checking Zoom registry configuration key..."
    $zoomRegPath = "HKLM:\SOFTWARE\WOW6432Node\Zoom\AU2_EnableAutoUpdate"

    if (Test-Path $zoomRegPath)
    {
        Write-Output "Zoom configuration registry key found at: $zoomRegPath"
        Write-Output "Zoom is installed - Configuration key present (Registry Detection)"
        exit 0
    }

    ## Not detected
    Write-Output "Zoom not detected"
    Write-Output "No installation found via registry or file system"
    exit 1
}
catch
{
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}

# CODE COMPLETE