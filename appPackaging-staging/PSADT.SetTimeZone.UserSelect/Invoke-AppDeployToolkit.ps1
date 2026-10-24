<#

.SYNOPSIS
Group 1001 - Set Time Zone Via User Selection

.DESCRIPTION
System-context deployment with user interaction. Shows a dialog (runs in user context
via PSADT) where the user selects their timezone from all available system timezones.
The selected timezone is applied via Set-TimeZone and stored in ProgramData for detection.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive, Silent, NonInteractive mode, or Auto.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for RDS/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes
- 69000 - 69999: Recommended for user customized exit codes
- 70000 - 79999: Recommended for user customized exit codes in Extensions

Custom exit codes for this package:
- 69621: User cancelled timezone selection
- 69626: Set-TimeZone operation failed

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

$adtSession = @{
    AppVendor = 'Group 1001'
    AppName = 'Set Time Zone - User Select'
    AppVersion = '2.0.0'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()
    AppScriptVersion = '2.0.0'
    AppScriptDate = '2026-06-21'
    AppScriptAuthor = 'Zachary Hayward'
    RequireAdmin = $true
    InstallName = 'Set Time Zone - User Select'
    InstallTitle = 'Time Zone Configuration'
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

# Package-specific variables
$script:markerDir = "$env:ProgramData\G1001\TimeZoneUserSelect"
$script:markerFile = "$script:markerDir\install.marker"

$script:tzResults = @{
    WindowsTZ = $null
    Previous = $null
    Outcome = $null
    UserSelected = $true
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message "Starting $($adtSession.AppName) v$($adtSession.AppVersion)" -Severity 1

    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    # Create marker directory
    if (-not (Test-Path $script:markerDir))
    {
        New-Item -ItemType Directory -Path $script:markerDir -Force | Out-Null
        Write-ADTLogEntry -Message "Created marker directory: $script:markerDir"
    }

    # Get current timezone before showing dialog
    $previousTZ = (Get-TimeZone).Id
    $script:tzResults.Previous = $previousTZ
    Write-ADTLogEntry -Message "Current Windows TZ before selection: $previousTZ"

    # Show timezone selection dialog to user
    # PSADT automatically runs this in user context even when script runs as SYSTEM
    Write-ADTLogEntry -Message "Displaying timezone selection dialog..."

    try
    {
        $windowsTZ = Show-ADTTimeZoneSelection -DefaultTimeZone $previousTZ
    }
    catch
    {
        Write-ADTLogEntry -Message "User cancelled timezone selection: $($_.Exception.Message)" -Severity 2
        Close-ADTSession -ExitCode 69621
    }

    if (-not $windowsTZ)
    {
        Write-ADTLogEntry -Message "No timezone selected" -Severity 3
        Close-ADTSession -ExitCode 69621
    }

    Write-ADTLogEntry -Message "User selected Windows TZ: $windowsTZ"
    $script:tzResults.WindowsTZ = $windowsTZ

    # Apply timezone change
    if ($previousTZ -eq $windowsTZ)
    {
        Write-ADTLogEntry -Message "Selected timezone matches current timezone. No change needed."
        $script:tzResults.Outcome = 'unchanged'
    }
    else
    {
        try
        {
            Set-TimeZone -Id $windowsTZ -ErrorAction Stop
            Write-ADTLogEntry -Message "Time zone changed: $previousTZ -> $windowsTZ"
            $script:tzResults.Outcome = 'changed'
        }
        catch
        {
            Write-ADTLogEntry -Message "Set-TimeZone failed: $($_.Exception.Message)" -Severity 3
            Close-ADTSession -ExitCode 69626
        }
    }

    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    # Write JSON marker for detection
    @{
        InstalledOn = (Get-Date -Format 'o')
        Version = $adtSession.AppVersion
        WindowsTZ = $script:tzResults.WindowsTZ
        PreviousTZ = $script:tzResults.Previous
        Outcome = $script:tzResults.Outcome
        UserSelected = $true
        DeviceName = $env:COMPUTERNAME
    } | ConvertTo-Json | Set-Content -Path $script:markerFile -Encoding UTF8

    Write-ADTLogEntry -Message "Detection marker written: $script:markerFile (outcome=$($script:tzResults.Outcome))"
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    Write-ADTLogEntry -Message "Starting uninstall of $($adtSession.AppName)" -Severity 1

    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    # Time zone itself is left as-is (user's choice should remain).
    # Only clean up detection marker.

    if (Test-Path $script:markerFile)
    {
        Remove-ADTFile -Path $script:markerFile
        Write-ADTLogEntry -Message "Removed detection marker: $script:markerFile"
    }

    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    if (Test-Path $script:markerDir)
    {
        $remaining = Get-ChildItem $script:markerDir -ErrorAction SilentlyContinue
        if (-not $remaining)
        {
            Remove-ADTFolder -Path $script:markerDir
            Write-ADTLogEntry -Message "Removed marker directory: $script:markerDir"
        }
        else
        {
            Write-ADTLogEntry -Message "Marker directory not empty, leaving in place: $script:markerDir" -Severity 2
        }
    }
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    Write-ADTLogEntry -Message "Repair invoked - re-running install logic"

    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    # Delegate to Install logic
    Install-ADTDeployment

    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
}


##================================================
## MARK: Initialization
##================================================

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

try
{
    # Import the PSADT module
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

try
{
    # Import extensions if found
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3
    Close-ADTSession -ExitCode 60001
}
