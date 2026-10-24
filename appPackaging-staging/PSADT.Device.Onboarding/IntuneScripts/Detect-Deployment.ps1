<#
.SYNOPSIS
Detection script for First Run Onboarding deployment

.DESCRIPTION
Checks if the package has been deployed correctly:
1. Package folder exists at C:\ProgramData\G1001\Packages\FirstRunOnboarding
2. Scheduled task exists

.NOTES
Exit Code 0 = Deployed correctly
Exit Code 1 = Not deployed or incomplete

Author: Zachary Hayward with Claude Code
Date: 2026-06-21
#>

$packagePath = "C:\ProgramData\G1001\Packages\FirstRunOnboarding"
$taskName = "G1001-FirstRunOnboarding"
$exePath = "$packagePath\Invoke-AppDeployToolkit.exe"

# Check if package folder exists
if (!(Test-Path $packagePath))
{
    Write-Output "Package folder not found: $packagePath"
    exit 1
}

# Check if executable exists
if (!(Test-Path $exePath))
{
    Write-Output "Executable not found: $exePath"
    exit 1
}

# Check if scheduled task exists
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (!$task)
{
    Write-Output "Scheduled task not found: $taskName"
    exit 1
}

# All checks passed
Write-Output "Deployment detected successfully. Package: $packagePath, Task: $taskName"
exit 0
