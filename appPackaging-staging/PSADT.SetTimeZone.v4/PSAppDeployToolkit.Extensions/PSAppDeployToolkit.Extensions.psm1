<#

.SYNOPSIS
PSAppDeployToolkit.Extensions - Placeholder module for SetTimeZone v4.

.DESCRIPTION
This package does not require custom extensions. This file exists only to satisfy
PSADT's module import logic.

#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1


##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported (no custom functions)." -ScriptSection Initialization
