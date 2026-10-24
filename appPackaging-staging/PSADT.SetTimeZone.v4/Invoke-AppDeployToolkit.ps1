<#

.SYNOPSIS
Group 1001 - Set Time Zone By Public IP Address

.DESCRIPTION
System-context deployment. Queries https://ipinfo.io/json for the device's public
IANA time zone, maps it to a Windows time zone using the bundled windowsZones.xml
(Unicode CLDR), and applies it via Set-TimeZone. Re-runs on every Intune evaluation
when the detection script reports drift, so roaming devices auto-correct.

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
- 69621: Bundled windowsZones.xml not found
- 69622: Failed to stage windowsZones.xml to ProgramData
- 69623: IP geolocation lookup failed or returned no timezone
- 69624: Failed to parse windowsZones.xml
- 69625: No Windows TZ mapping found for detected IANA zone
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
    AppName = 'Set Time Zone By IP'
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
    InstallName = 'Set Time Zone By IP'
    InstallTitle = 'Time Zone Configuration'
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

# Package-specific variables
$script:markerDir = "$env:ProgramData\G1001\TimeZoneByIP"
$script:markerFile = "$script:markerDir\install.marker"
$script:persistentXml = "$script:markerDir\windowsZones.xml"
$script:ipInfoUrl = 'https://ipinfo.io/json'  # ✓ Fixed: HTTPS instead of HTTP
$script:ipInfoTimeoutSec = 5  # ✓ Fixed: Consistent 5s timeout across install and detect

$script:tzResults = @{
    IanaZone = $null
    WindowsTZ = $null
    Previous = $null
    Outcome = $null
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

    # Locate bundled XML (in Files folder)
    $sourceXml = Join-Path -Path "$PSScriptRoot\Files" -ChildPath 'windowsZones.xml'
    if (-not (Test-Path -LiteralPath $sourceXml))
    {
        Write-ADTLogEntry -Message "Bundled windowsZones.xml not found at $sourceXml" -Severity 3
        Close-ADTSession -ExitCode 69621
    }
    Write-ADTLogEntry -Message "Bundled XML located: $sourceXml"

    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    # Stage the XML to ProgramData for detection script access
    if (-not (Test-Path $script:markerDir))
    {
        New-Item -ItemType Directory -Path $script:markerDir -Force | Out-Null
    }

    try
    {
        Copy-ADTFile -Path $sourceXml -Destination $script:persistentXml
        Write-ADTLogEntry -Message "Staged windowsZones.xml to $script:persistentXml"
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to stage XML: $($_.Exception.Message)" -Severity 3
        Close-ADTSession -ExitCode 69622
    }

    # Resolve IANA zone from public IP
    Write-ADTLogEntry -Message "Querying $script:ipInfoUrl for IANA time zone..."
    $ianaTz = $null
    try
    {
        $ianaTz = (Invoke-RestMethod -Uri $script:ipInfoUrl -TimeoutSec $script:ipInfoTimeoutSec).timezone
    }
    catch
    {
        Write-ADTLogEntry -Message "IP geolocation lookup failed: $($_.Exception.Message)" -Severity 3
        Close-ADTSession -ExitCode 69623
    }

    if (-not $ianaTz)
    {
        Write-ADTLogEntry -Message "ipinfo.io returned no timezone value" -Severity 3
        Close-ADTSession -ExitCode 69623
    }
    Write-ADTLogEntry -Message "Detected IANA zone: $ianaTz"
    $script:tzResults.IanaZone = $ianaTz

    # Map IANA → Windows zone
    try
    {
        [xml]$windowsZones = Get-Content -LiteralPath $script:persistentXml -Raw -ErrorAction Stop
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to parse windowsZones.xml: $($_.Exception.Message)" -Severity 3
        Close-ADTSession -ExitCode 69624
    }

    $mapping = $windowsZones.supplementalData.windowsZones.mapTimezones.mapZone | Where-Object {
        $_.type -split ' ' -contains $ianaTz
    } | Select-Object -First 1

    if (-not $mapping)
    {
        Write-ADTLogEntry -Message "No Windows TZ mapping found for IANA zone '$ianaTz'" -Severity 3
        Close-ADTSession -ExitCode 69625
    }

    $windowsTZ = $mapping.other
    Write-ADTLogEntry -Message "Mapped to Windows TZ: $windowsTZ"
    $script:tzResults.WindowsTZ = $windowsTZ

    # Apply timezone change
    $previousTZ = (Get-TimeZone).Id
    $script:tzResults.Previous = $previousTZ
    Write-ADTLogEntry -Message "Current Windows TZ before change: $previousTZ"

    if ($previousTZ -eq $windowsTZ)
    {
        Write-ADTLogEntry -Message "Time zone already set correctly. No change needed."
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
        IanaZone = $script:tzResults.IanaZone
        WindowsTZ = $script:tzResults.WindowsTZ
        PreviousTZ = $script:tzResults.Previous
        Outcome = $script:tzResults.Outcome
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

    # Time zone itself is left as-is (changing it back would be incorrect).
    # Only clean up artifacts.

    if (Test-Path $script:markerFile)
    {
        Remove-ADTFile -Path $script:markerFile
        Write-ADTLogEntry -Message "Removed detection marker: $script:markerFile"
    }
    if (Test-Path $script:persistentXml)
    {
        Remove-ADTFile -Path $script:persistentXml
        Write-ADTLogEntry -Message "Removed staged XML: $script:persistentXml"
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
