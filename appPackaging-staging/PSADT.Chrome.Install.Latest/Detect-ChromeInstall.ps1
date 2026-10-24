<#
================================================================================
Script Name:        Detect-ChromeInstall.ps1
Creation Date:      2026-06-12
Last Change Date:   2026-06-12
Author:             Zachary Hayward with Claude Code-claude-sonnet-4-6
LLM Version Tag:    Claude Code-claude-sonnet-4-6
Script Function:    Detection script for Google Chrome installation in Microsoft
                    Intune. Checks deployment registry marker, verifies Chrome is
                    installed via Windows registry, and confirms the executable exists.
                    Returns exit code 0 if detected (installed), exit code 1 if not
                    detected (not installed). Outputs detection string for Intune
                    compliance check with installed version info.
Script Input:       None
Script Output:      String output to stdout: "Chrome Detected: <version>" if found
                    Exit code 0 = Detected, Exit code 1 = Not Detected
Modules Required:   None
Script Usage:       .\Detect-ChromeInstall.ps1

Latest Change
Description:        Updated to check deployment registry marker and verify installed
                    version matches deployment tracking
================================================================================
#>

# CODE
# DEFINE VARIABLES AND INPUTS AND OUTPUTS

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Detection results
$chromeDetected = $false
$chromeVersion = $null
$chromePath = $null
$deploymentMarkerExists = $false
$deployedVersion = $null

# CODE AND SCRIPT LOGIC WITH COMMENTS AT KEY COMMANDS

Try {
    # Check deployment registry marker first
    $markerPath = 'HKLM:\SOFTWARE\G1001\ChromeDeployment'
    if (Test-Path $markerPath) {
        $markerData = Get-ItemProperty -Path $markerPath -ErrorAction SilentlyContinue
        if ($markerData -and $markerData.InstalledVersion) {
            $deploymentMarkerExists = $true
            $deployedVersion = $markerData.InstalledVersion
            $installDate = $markerData.InstallDate
        }
    }

    # Check registry for Chrome installation (64-bit and 32-bit paths)
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($regPath in $registryPaths) {
        $chromeRegistry = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Google Chrome*' }

        if ($chromeRegistry) {
            $chromeVersion = $chromeRegistry.DisplayVersion
            $chromePath = $chromeRegistry.InstallLocation
            break
        }
    }

    # If found in registry, verify the executable exists
    if ($chromeVersion) {
        # Common Chrome installation paths
        $chromePaths = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        )

        # If we got InstallLocation from registry, add it to check list
        if ($chromePath) {
            $chromePaths += "$chromePath\chrome.exe"
            $chromePaths += "$chromePath\Application\chrome.exe"
        }

        # Check if executable exists
        foreach ($path in $chromePaths) {
            if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
                $chromeDetected = $true

                # Get file version if registry version not available
                if (-not $chromeVersion) {
                    $fileVersion = (Get-Item $path).VersionInfo.FileVersion
                    if ($fileVersion) {
                        $chromeVersion = $fileVersion
                    }
                }
                break
            }
        }
    }

    # Verify deployment marker matches installed version
    if ($chromeDetected -and $deploymentMarkerExists) {
        if ($chromeVersion -eq $deployedVersion) {
            Write-Output "Chrome Detected: Version $chromeVersion (Deployed: $installDate)"
            Exit 0
        }
        else {
            Write-Output "Chrome Version Mismatch: Installed=$chromeVersion, Expected=$deployedVersion"
            Exit 1
        }
    }
    # Chrome detected but no deployment marker (manual install or different deployment)
    elseif ($chromeDetected -and -not $deploymentMarkerExists) {
        Write-Output "Chrome Detected: Version $chromeVersion (No deployment marker - manual install?)"
        # Still consider it detected for Intune purposes
        Exit 0
    }
    # Deployment marker exists but Chrome not properly installed
    elseif (-not $chromeDetected -and $deploymentMarkerExists) {
        Write-Output "Chrome Not Detected: Deployment marker exists but installation not found"
        Exit 1
    }
    # Chrome not detected at all
    else {
        Write-Output "Chrome Not Detected"
        Exit 1
    }
}
Catch {
    # If any error occurs during detection, assume not detected
    Write-Output "Chrome Detection Error: $($_.Exception.Message)"
    Exit 1
}

# CODE COMPLETE
