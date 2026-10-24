<#
.SYNOPSIS
Deployment script for First Run Onboarding - Copies package and creates scheduled task

.DESCRIPTION
This script is deployed as an Intune Win32 app (Device context) during ESP.
It copies the PSADT package to C:\ProgramData\G1001\Packages\ and creates a
scheduled task that runs at any user logon.

.NOTES
Author: Zachary Hayward with Claude Code
Date: 2026-06-21
Intune Deployment: Device context, runs during Device ESP (white glove)
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Define paths
$packageName = "FirstRunOnboarding"
$destinationRoot = "C:\ProgramData\G1001\Packages"
$destinationPath = "$destinationRoot\$packageName"
$taskName = "G1001-FirstRunOnboarding"
$exePath = "$destinationPath\Invoke-AppDeployToolkit.exe"

try
{
    Write-Host "Starting First Run Onboarding deployment..."

    # Create destination directory
    if (!(Test-Path $destinationRoot))
    {
        Write-Host "Creating directory: $destinationRoot"
        New-Item -Path $destinationRoot -ItemType Directory -Force | Out-Null
    }

    # Remove old package if exists
    if (Test-Path $destinationPath)
    {
        Write-Host "Removing existing package at: $destinationPath"
        Remove-Item -Path $destinationPath -Recurse -Force
    }

    # Copy PSADT package to destination
    Write-Host "Copying package to: $destinationPath"
    $sourcePath = Join-Path $PSScriptRoot "..\FirstRunOnboarding"
    Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force

    Write-Host "Package copied successfully"

    # Check if scheduled task already exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask)
    {
        Write-Host "Removing existing scheduled task: $taskName"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    # Create scheduled task
    Write-Host "Creating scheduled task: $taskName"

    $action = New-ScheduledTaskAction -Execute $exePath -Argument "-DeploymentType Install -DeployMode Interactive"

    $trigger = New-ScheduledTaskTrigger -AtLogOn

    $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "First run onboarding experience for new users. Runs once per user at first logon."

    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

    Write-Host "Scheduled task created successfully"
    Write-Host "Deployment completed successfully!"
    Write-Host ""
    Write-Host "Package location: $destinationPath"
    Write-Host "Task name: $taskName"
    Write-Host "Trigger: At logon (any user)"

    exit 0
}
catch
{
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}
