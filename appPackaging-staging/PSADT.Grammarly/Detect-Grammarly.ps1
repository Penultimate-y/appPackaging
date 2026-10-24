<#
.SYNOPSIS
Intune detection script for Grammarly Desktop installation.

.DESCRIPTION
Checks if Grammarly Desktop is installed by verifying:
1. The executable exists at the expected path
2. The enterprise enrollment registry key is configured

.NOTES
Exit 0 = Detected (Grammarly is installed)
Exit 1 = Not Detected (Grammarly is not installed or misconfigured)

This script runs in SYSTEM context.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -File Detect-Grammarly.ps1

#>

$ErrorActionPreference = 'SilentlyContinue'

## Define paths and registry
$grammarlyExePath = "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe"
$grammarlyRegistryPath = "HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations"

## Check 1: Executable exists
$exeExists = Test-Path -Path $grammarlyExePath

## Check 2: Registry enrollment token exists
$enrollmentToken = Get-ItemProperty -Path $grammarlyRegistryPath -Name "GrammarlyEnrollmentToken" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty GrammarlyEnrollmentToken

if ($exeExists -and $enrollmentToken)
{
    Write-Output "Grammarly Desktop detected: Executable found and enrollment configured"
    exit 0  # Detected
}
else
{
    if (-not $exeExists)
    {
        Write-Output "Grammarly Desktop not detected: Executable not found at $grammarlyExePath"
    }
    if (-not $enrollmentToken)
    {
        Write-Output "Grammarly Desktop enrollment not configured: Missing enrollment token in registry"
    }
    exit 1  # Not Detected
}
