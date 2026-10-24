<#
.SYNOPSIS
Detection script for First Run Onboarding - checks if setup has completed

.DESCRIPTION
Intune detection script that verifies the First Run Onboarding has been executed
by checking for the presence of the completion marker file.

.NOTES
Exit Code 0 = Installed (marker found)
Exit Code 1 = Not installed (marker not found)

Author: Zachary Hayward with Claude Code
Date: 2026-06-21
#>

$markerPath = "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt"

if (Test-Path -Path $markerPath)
{
    Write-Output "First Run Onboarding completed. Marker found: $markerPath"
    exit 0
}
else
{
    Write-Output "First Run Onboarding not completed. Marker not found: $markerPath"
    exit 1
}
