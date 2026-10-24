<#
================================================================================
Script Name:        Detect-AWSSessionManager.ps1
Creation Date:      2026-07-22
Last Change Date:   2026-07-22
Author:             DWX Team with Claude Code
LLM Version Tag:    Claude Code-claude-sonnet-4-6
Script Function:    Detection script for AWS Session Manager Plugin in Microsoft
                    Intune. Checks for the presence of the AWS Session Manager
                    Plugin executable and verifies it can report its version.
Script Input:       None
Script Output:      Exit code 0 if detected (installed), exit code 1 if not
                    detected (not installed or not functional)
Modules Required:   None
Script Usage:       .\Detect-AWSSessionManager.ps1

Latest Change
Description:        Initial creation
================================================================================
#>

# CODE
# DEFINE VARIABLES AND INPUTS AND OUTPUTS

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# CODE AND SCRIPT LOGIC WITH COMMENTS AT KEY COMMANDS

# Define the expected installation path
$sessionManagerPath = Join-Path -Path $env:ProgramFiles -ChildPath 'Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe'

try
{
    # Check if the executable exists
    if (Test-Path -Path $sessionManagerPath)
    {
        Write-Host "AWS Session Manager Plugin detected at: $sessionManagerPath"

        # Verify the plugin is functional by checking version
        try
        {
            $versionOutput = & $sessionManagerPath --version 2>&1
            Write-Host "Plugin version: $versionOutput"
            Write-Host "Detection successful - AWS Session Manager Plugin is installed and functional"
            exit 0
        }
        catch
        {
            Write-Host "AWS Session Manager Plugin executable exists but cannot report version: $_"
            exit 1
        }
    }
    else
    {
        Write-Host "AWS Session Manager Plugin not detected - executable not found at: $sessionManagerPath"
        exit 1
    }
}
catch
{
    Write-Host "Detection script error: $_"
    exit 1
}

# CODE COMPLETE
