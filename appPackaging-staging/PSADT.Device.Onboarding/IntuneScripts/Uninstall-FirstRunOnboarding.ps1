<#
.SYNOPSIS
Uninstall script for First Run Onboarding - Removes package and scheduled task

.DESCRIPTION
Removes the PSADT package from C:\ProgramData\G1001\Packages\ and deletes
the scheduled task.

.NOTES
Author: Zachary Hayward with Claude Code
Date: 2026-06-21
Intune Deployment: Device context
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Define paths
$packageName = "FirstRunOnboarding"
$destinationPath = "C:\ProgramData\G1001\Packages\$packageName"
$taskName = "G1001-FirstRunOnboarding"

try
{
    Write-Host "Starting First Run Onboarding uninstall..."

    # Remove scheduled task
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task)
    {
        Write-Host "Removing scheduled task: $taskName"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Scheduled task removed"
    }
    else
    {
        Write-Host "Scheduled task not found (already removed or never created)"
    }

    # Remove package folder
    if (Test-Path $destinationPath)
    {
        Write-Host "Removing package folder: $destinationPath"
        Remove-Item -Path $destinationPath -Recurse -Force
        Write-Host "Package folder removed"
    }
    else
    {
        Write-Host "Package folder not found (already removed or never created)"
    }

    Write-Host "Uninstall completed successfully!"
    exit 0
}
catch
{
    Write-Error "Uninstall failed: $($_.Exception.Message)"
    exit 1
}
