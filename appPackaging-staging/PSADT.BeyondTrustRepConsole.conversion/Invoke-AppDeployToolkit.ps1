<#

.SYNOPSIS
PSAppDeployToolkit - Installs or uninstalls the BeyondTrust Remote Support Representative Console.

.DESCRIPTION
Installs the BeyondTrust Remote Support (RS) Representative Console silently from media staged
in this package's Files folder, then verifies the result.

This is an OFFLINE-ONLY package. The BeyondTrust representative console installer
(sra-con-installer.exe) is a per-appliance build tied to a specific BeyondTrust appliance
hostname - there is no stable public evergreen download URL for it, so the installer must be
staged in Files\ and refreshed from the BeyondTrust appliance whenever the site is upgraded.

Template source: PSADT.Kiro.IDE
Legacy predecessor(s): legacy.Beyond trust
Supersedes Intune app(s): none recorded

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive, Silent, NonInteractive or Auto mode.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for RDSH/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent

.NOTES
TEST GROUP REQUIREMENT
    App assignment changes affect every targeted device and user. Assign this package to
    the DWX application pilot group and confirm a successful install, detection and
    uninstall on at least one device per supported build before widening the assignment.

OFFLINE-ONLY / APPLIANCE-SPECIFIC MEDIA
    The staged installer (sra-con-installer.exe) is specific to your BeyondTrust appliance
    hostname. There is no public download URL. When the appliance is upgraded, re-download the
    representative console installer from the appliance, replace the file in Files\, rebuild the
    .intunewin and re-upload it to Intune.

PACKAGING NOTES / ASSUMPTIONS TO VERIFY IN PILOT
    - Installer family: NSIS (Nullsoft). Confirmed by probe of the staged binary.
      Silent install switch is '/S'; silent uninstall is the bundled 'Uninstall.exe /S'.
    - The desktop rep console registers an uninstall entry and Start Menu group named for the
      site hostname (e.g. support.example.com) under a 'BeyondTrust' (older builds: 'Bomgar')
      vendor grouping. Detection therefore matches the uninstall-registry DisplayName against a
      broad pattern rather than a single fixed path, because the exact folder/name is
      appliance-specific. CONFIRM the installed DisplayName in your pilot group and tighten the
      DisplayNamePattern in Detect-BeyondTrustRepConsole.ps1 and in this script if required.
    - Per-machine (System context) install assumed. If your appliance only produces a per-user
      console build, switch InstallContext to User in the catalog and regenerate/redeploy.

Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1/.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
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
    # App variables.
    AppVendor = 'BeyondTrust'
    AppName = 'Remote Support Representative Console'
    AppVersion = 'Appliance'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('scc', 'bomgar-scc', 'BeyondTrustRepConsole', 'representative')
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-10-09'
    AppScriptAuthor = 'DWX Team with Kiro'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'BeyondTrust Remote Support Representative Console'
    InstallTitle = 'BeyondTrust Representative Console Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

# Filename used for the staged installer inside the package Files folder.
$script:InstallerFileName = 'sra-con-installer.exe'

# Detection pattern for the per-appliance uninstall-registry DisplayName.
# Matches BeyondTrust/Bomgar representative console entries regardless of the site hostname.
$script:DetectionDisplayNamePattern = 'BeyondTrust|Bomgar|Representative Console'


##================================================
## MARK: Installer Acquisition
##================================================

function Get-AppInstaller
{
    <#
    .SYNOPSIS
        Returns a local path to the staged BeyondTrust representative console installer.
    .DESCRIPTION
        This package is offline-only: the appliance-specific installer must be staged in the
        package Files folder. There is no public download URL to fall back to.
    .OUTPUTS
        System.String. Full path to the installer on disk.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    ## Prefer the exact expected filename, then any .exe staged in Files\.
    if ($adtSession.DirFiles -and (Test-Path -LiteralPath $adtSession.DirFiles))
    {
        $expected = Join-Path -Path $adtSession.DirFiles -ChildPath $script:InstallerFileName
        if (Test-Path -LiteralPath $expected)
        {
            Write-ADTLogEntry -Message "Using staged installer: $expected"
            return $expected
        }

        $staged = Get-ChildItem -LiteralPath $adtSession.DirFiles -File -ErrorAction Ignore |
            Where-Object { $_.Extension -eq '.exe' } |
            Select-Object -First 1

        if ($staged)
        {
            Write-ADTLogEntry -Message "Using staged installer: $($staged.FullName)"
            return $staged.FullName
        }
    }

    ## No media present - this vendor build cannot be downloaded, so fail with clear guidance.
    $guidance = @(
        'No BeyondTrust representative console installer was found in the package Files folder.'
        ''
        'This package is OFFLINE-ONLY. The representative console installer is a per-appliance'
        'build tied to your BeyondTrust appliance hostname and has no public download URL.'
        ''
        'To use this package:'
        '  1. Log in to your BeyondTrust appliance and download the Representative Console'
        '     installer (sra-con-installer.exe) for Windows.'
        "  2. Place it in the package Files folder as '$($script:InstallerFileName)'."
        '  3. Rebuild the .intunewin and re-upload it to Intune.'
    ) -join [System.Environment]::NewLine
    throw $guidance
}


function Install-ADTDeployment
{
    [CmdletBinding()]
    param ()

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show welcome message and close the target application if it is running.
    $saiwParams = @{
        AllowDefer = $true
        DeferTimes = 3
        CheckDiskSpace = $true
        PersistPrompt = $true
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
    }
    Show-ADTInstallationWelcome @saiwParams

    Show-ADTInstallationProgress -StatusMessage 'Preparing BeyondTrust Representative Console installation...'


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Acquire the staged installer.
    $installerPath = Get-AppInstaller

    Show-ADTInstallationProgress -StatusMessage 'Installing BeyondTrust Representative Console...'
    Write-ADTLogEntry -Message "Installing BeyondTrust Representative Console from: $installerPath"

    ## NSIS silent install. '/S' is the Nullsoft silent switch.
    $null = Start-ADTProcess -FilePath $installerPath -ArgumentList @("/S") -WindowStyle Hidden

    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Verify the install registered the product.
    if (Test-AppInstalled)
    {
        Write-ADTLogEntry -Message 'BeyondTrust Representative Console installation verified successfully.'
    }
    else
    {
        Write-ADTLogEntry -Message 'BeyondTrust installer completed but post-install verification failed.' -Severity 3
        throw 'BeyondTrust Representative Console post-install verification failed. Confirm the installed DisplayName and tighten the detection pattern.'
    }

    if ($adtSession.DeployMode -ne 'Silent')
    {
        Show-ADTInstallationPrompt -Message 'The BeyondTrust Representative Console has been installed successfully.' -ButtonRightText 'OK' -NoWait
    }
}


function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param ()

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    Show-ADTInstallationProgress -StatusMessage 'Removing BeyondTrust Representative Console...'


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Locate the per-appliance uninstall-registry entry and run its registered uninstall string.
    ## The entry's QuietUninstallString / UninstallString points at the bundled NSIS Uninstall.exe;
    ## Uninstall-ADTApplication runs it silently.
    $installedApps = Get-ADTApplication -Name $script:DetectionDisplayNamePattern -NameMatch Regex
    if ($installedApps)
    {
        foreach ($app in $installedApps)
        {
            Write-ADTLogEntry -Message "Uninstalling: $($app.DisplayName) $($app.DisplayVersion)"
        }
        ## '/S' ensures the NSIS uninstaller runs silently even if no QuietUninstallString is set.
        $null = Uninstall-ADTApplication -InstalledApplication $installedApps -ArgumentList '/S'
    }
    else
    {
        Write-ADTLogEntry -Message 'BeyondTrust Representative Console not found in the uninstall registry - nothing to remove.' -Severity 2
    }

    ##================================================
    ## MARK: Post-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message 'BeyondTrust Representative Console uninstallation completed.'
}


function Repair-ADTDeployment
{
    [CmdletBinding()]
    param ()

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    Show-ADTInstallationProgress -StatusMessage 'Repairing BeyondTrust Representative Console...'


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Repair is implemented as a reinstall over the top using the staged media.
    Write-ADTLogEntry -Message 'Repair requested - reinstalling BeyondTrust Representative Console over the existing installation.'
    $installerPath = Get-AppInstaller

    ## NSIS silent install.
    $null = Start-ADTProcess -FilePath $installerPath -ArgumentList @("/S") -WindowStyle Hidden

    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message 'BeyondTrust Representative Console repair completed.'
}


function Test-AppInstalled
{
    <#
    .SYNOPSIS
        Post-install verification using the same logic as the Intune detection script.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()

    try
    {
        $found = Get-ADTApplication -Name $script:DetectionDisplayNamePattern -NameMatch Regex
        if ($found)
        {
            foreach ($app in $found)
            {
                Write-ADTLogEntry -Message "Detected: $($app.DisplayName) $($app.DisplayVersion)"
            }
            return $true
        }
        return $false
    }
    catch
    {
        Write-ADTLogEntry -Message "Verification check threw an error: $($_.Exception.Message)" -Severity 2
        return $false
    }
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
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

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
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

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3
    Close-ADTSession -ExitCode 60001
}
