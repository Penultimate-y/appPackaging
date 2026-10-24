#Requires -Modules Microsoft.Graph.Authentication, ImportExcel

<#
================================================================================
Script Name:        get.intune-discovered-apps-graph.ps1
Creation Date:      2025-07-14
Last Change Date:   2025-09-03
Author:             devjustintison with Kiro AI (claude-sonnet-4-20250514)
LLM Version Tag:    Kiro-claude-sonnet-4-20250514
Script Function:    Reports applications discovered on managed devices via Intune.
                    Retrieves all detected apps from deviceManagement/detectedApps
                    with pagination, and expands device associations for apps exceeding
                    a configurable device count threshold.
Script Input:       -TenantId — Entra tenant ID (GUID)
                    -ClientId — (optional) App registration (SPN) client ID to
                    authenticate as, using that app's delegated permissions
Script Output:      Excel workbook written to OutputPath — sheets: 'Discovered Apps',
                    'Device Details', 'Metadata'
Modules Required:   Microsoft.Graph.Authentication 2.x+, ImportExcel
Graph Scopes:       DeviceManagementApps.Read.All (delegated)
Permissions:        Intune Administrator or Global Reader. When -ClientId is
                    supplied, sign-in is performed against that app registration
                    and the app must expose the DeviceManagementApps.Read.All
                    delegated permission with admin consent granted.
PS Version:         PowerShell 7.x+
Script Usage:       # Default (built-in Microsoft Graph PowerShell app):
                    .\get.intune-discovered-apps-graph.ps1 -TenantId "<tenant-id>"

                    # Authenticate as your own app registration (delegated):
                    .\get.intune-discovered-apps-graph.ps1 -TenantId "<tenant-id>" -ClientId "<app-client-id>"

                    Optional Parameters:
                    -ClientId              : App registration (SPN) client ID to sign in as; uses the
                                             app's configured delegated permissions. Omit to use the
                                             built-in Microsoft Graph PowerShell client.
                    -OutputPath            : Directory to write the Excel report (default: ../output/)
                    -SkipConnect           : Reuse an existing Graph connection (orchestrated runs)
                    -DeviceCountThreshold  : Minimum device count to expand device details (default: 5)

Latest Change
Description:        2026-08-28 - Added optional -ClientId parameter to authenticate
                    against a custom app registration (SPN) using its delegated
                    permissions. Backward compatible: omitting -ClientId uses the
                    built-in Microsoft Graph PowerShell client as before.
                    Initial creation - 2025-07-14
================================================================================
#>

# CODE
# DEFINE VARIABLES AND INPUTS AND OUTPUTS

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage = 'Entra tenant ID (GUID)')]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$TenantId,

    [Parameter(HelpMessage = 'App registration (SPN) client ID to sign in as (uses its delegated permissions). Omit to use the built-in Microsoft Graph PowerShell client.')]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$ClientId,

    [Parameter(HelpMessage = 'Directory to write the Excel report')]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..' 'output'),

    [Parameter(HelpMessage = 'Skip Connect/Disconnect — caller manages the Graph session')]
    [switch]$SkipConnect,

    [Parameter(HelpMessage = 'Minimum device count to expand device associations')]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$DeviceCountThreshold = 5
)

$ErrorActionPreference = 'Stop'

# Dot-source shared helpers (pagination, retry, resolution, Excel export)
. (Join-Path $PSScriptRoot '..' 'entra' '_helpers.graph-utils.ps1')

$RequiredScopes = @('DeviceManagementApps.Read.All')

# CODE AND SCRIPT LOGIC WITH COMMENTS AT KEY COMMANDS

try {
    # Connect to Microsoft Graph if not managed externally
    if (-not $SkipConnect) {
        # Build connection parameters via splatting so -ClientId is only passed
        # when supplied. With a ClientId, sign-in is performed interactively
        # against that app registration (SPN) using its delegated permissions;
        # without it, the built-in Microsoft Graph PowerShell client is used.
        $connectParams = @{
            Scopes    = $RequiredScopes
            TenantId  = $TenantId
            NoWelcome = $true
        }
        if ($ClientId) { $connectParams['ClientId'] = $ClientId }

        $authMode = if ($ClientId) { "app registration $ClientId (delegated)" } else { 'built-in Graph PowerShell client' }
        Write-Host "Connecting to Microsoft Graph (TenantId: $TenantId; auth: $authMode)..." -ForegroundColor Cyan
        Connect-MgGraph @connectParams
        Write-Host "Connected." -ForegroundColor Green
    }

    # Retrieve all detected apps from Intune device management
    Write-Host "Retrieving discovered apps from Intune..." -ForegroundColor Cyan
    $appsUri = 'https://graph.microsoft.com/v1.0/deviceManagement/detectedApps?$select=displayName,version,platform,deviceCount,sizeInBytes,publisher&$top=999'
    $detectedApps = Get-GraphCollection -Uri $appsUri -Activity 'Retrieving detected apps'
    Write-Host "Found $($detectedApps.Count) discovered apps. Processing..." -ForegroundColor Cyan

    # Initialize collections for each worksheet
    $appRows    = [System.Collections.Generic.List[PSCustomObject]]::new()
    $deviceRows = [System.Collections.Generic.List[PSCustomObject]]::new()

    $i = 0

    foreach ($app in $detectedApps) {
        $i++
        Write-Progress -Activity "Processing discovered apps" `
            -Status "$i/$($detectedApps.Count): $($app.displayName)" `
            -PercentComplete (($i / $detectedApps.Count) * 100)

        # Build 'Discovered Apps' row
        $appRows.Add([PSCustomObject]@{
            DisplayName = $app.displayName
            Version     = $app.version
            Platform    = $app.platform
            DeviceCount = $app.deviceCount
            SizeInBytes = $app.sizeInBytes
            Publisher   = $app.publisher
        })

        # For apps exceeding the threshold, retrieve managed device details
        if ($app.deviceCount -ge $DeviceCountThreshold) {
            try {
                $devicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/detectedApps/$($app.id)/managedDevices?`$select=deviceName,id,operatingSystem,osVersion,lastSyncDateTime"
                $devices = Get-GraphCollection -Uri $devicesUri -Activity "Devices: $($app.displayName)"

                foreach ($device in $devices) {
                    $deviceRows.Add([PSCustomObject]@{
                        AppDisplayName   = $app.displayName
                        DeviceName       = $device.deviceName
                        DeviceId         = $device.id
                        OperatingSystem  = $device.operatingSystem
                        OsVersion        = $device.osVersion
                        LastSyncDateTime = $device.lastSyncDateTime
                    })
                }
            }
            catch {
                # Log warning but continue processing remaining apps
                Write-Warning "Could not retrieve managed devices for '$($app.displayName)' (id: $($app.id)): $($_.Exception.Message)"
            }
        }
    }
    Write-Progress -Activity "Processing discovered apps" -Completed

    # Sort discovered apps by device count descending
    $sortedAppRows = $appRows | Sort-Object -Property DeviceCount -Descending

    Write-Host "Discovered Apps: $($appRows.Count) | Device Details: $($deviceRows.Count)" -ForegroundColor Green

    # Export workbook using shared Export-AuditWorkbook helper
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outputFile = Join-Path (Resolve-Path $OutputPath) "get.intune-discovered-apps-graph-$timestamp.xlsx"

    $worksheets = [ordered]@{
        'Discovered Apps' = $sortedAppRows
        'Device Details'  = $deviceRows
    }

    $metadata = @{
        'Generated'            = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        'TenantId'             = $TenantId
        'AuthClientId'         = if ($ClientId) { $ClientId } else { 'built-in Graph PowerShell client' }
        'DiscoveredAppCount'   = $appRows.Count
        'DeviceCountThreshold' = $DeviceCountThreshold
        'RunBy'                = [Environment]::UserName
        'Script'               = $MyInvocation.MyCommand.Name
    }

    Export-AuditWorkbook -Path $outputFile -Worksheets $worksheets -Metadata $metadata

    Write-Host "Report saved: $outputFile" -ForegroundColor Green
}
finally {
    if (-not $SkipConnect) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
}

# CODE COMPLETE
 