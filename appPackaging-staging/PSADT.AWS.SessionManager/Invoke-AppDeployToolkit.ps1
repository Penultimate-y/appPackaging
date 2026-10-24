<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of AWS Session Manager Plugin.

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
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

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = 'Amazon Web Services'
    AppName = 'AWS Session Manager Plugin'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-07-22'
    AppScriptAuthor = 'DWX Team with Claude Code (claude-sonnet-4-6)'

    # Install Titles
    InstallName = 'AWS Session Manager Plugin'
    InstallTitle = 'AWS Session Manager Plugin Installation'

    # Script variables
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Preparing AWS Session Manager Plugin installation...'

    Write-ADTLogEntry -Message 'Starting AWS Session Manager Plugin installation' -Severity 1

    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage 'Downloading AWS Session Manager Plugin...'

    # Define download URL
    $installerUrl = 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe'
    $installerPath = Join-Path -Path $adtSession.DirFiles -ChildPath 'SessionManagerPluginSetup.exe'

    Write-ADTLogEntry -Message "Downloading installer from: $installerUrl" -Severity 1
    Write-ADTLogEntry -Message "Download destination: $installerPath" -Severity 1

    # Download the installer
    try
    {
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        $progressPreference = 'Continue'

        Write-ADTLogEntry -Message 'Download completed successfully' -Severity 1

        # Verify the file was downloaded
        if (-not (Test-Path -Path $installerPath))
        {
            throw "Downloaded installer not found at: $installerPath"
        }

        $fileSize = (Get-Item -Path $installerPath).Length
        Write-ADTLogEntry -Message "Installer file size: $([Math]::Round($fileSize / 1MB, 2)) MB" -Severity 1
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to download installer: $_" -Severity 3
        throw "Failed to download AWS Session Manager Plugin installer: $_"
    }

    Show-ADTInstallationProgress -StatusMessage 'Installing AWS Session Manager Plugin...'

    # Install the application
    Write-ADTLogEntry -Message 'Starting installation' -Severity 1

    $installResult = Start-ADTProcess -FilePath $installerPath -ArgumentList '/S' -WindowStyle Hidden -PassThru

    if ($installResult.ExitCode -eq 0)
    {
        Write-ADTLogEntry -Message 'Installation completed successfully' -Severity 1
    }
    else
    {
        Write-ADTLogEntry -Message "Installation returned exit code: $($installResult.ExitCode)" -Severity 2
    }

    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    # Verify installation
    Write-ADTLogEntry -Message 'Verifying installation' -Severity 1

    $sessionManagerPath = Join-Path -Path $env:ProgramFiles -ChildPath 'Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe'

    if (Test-Path -Path $sessionManagerPath)
    {
        Write-ADTLogEntry -Message "Installation verified: $sessionManagerPath exists" -Severity 1

        # Test the plugin
        try
        {
            $versionOutput = & $sessionManagerPath --version 2>&1
            Write-ADTLogEntry -Message "Plugin version: $versionOutput" -Severity 1
        }
        catch
        {
            Write-ADTLogEntry -Message "Could not retrieve plugin version: $_" -Severity 2
        }
    }
    else
    {
        Write-ADTLogEntry -Message "Warning: Installation verification failed - plugin executable not found at expected path: $sessionManagerPath" -Severity 2
    }

    # Clean up downloaded installer
    if (Test-Path -Path $installerPath)
    {
        Write-ADTLogEntry -Message 'Removing downloaded installer' -Severity 1
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Show-ADTInstallationProgress -StatusMessage 'Preparing AWS Session Manager Plugin uninstallation...'

    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage 'Uninstalling AWS Session Manager Plugin...'

    Write-ADTLogEntry -Message 'Starting uninstallation' -Severity 1

    # Find and uninstall via registry
    $uninstallKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*AWS Session Manager*" }

    if ($uninstallKey -and $uninstallKey.UninstallString)
    {
        Write-ADTLogEntry -Message "Found uninstall string: $($uninstallKey.UninstallString)" -Severity 1
        $uninstallString = $uninstallKey.UninstallString

        if ($uninstallString -match '"(.+)"')
        {
            $uninstallerPath = $matches[1]
            Write-ADTLogEntry -Message "Executing uninstaller: $uninstallerPath" -Severity 1
            $uninstallResult = Start-ADTProcess -FilePath $uninstallerPath -ArgumentList '/S' -WindowStyle Hidden -PassThru
            Write-ADTLogEntry -Message "Uninstall completed with exit code: $($uninstallResult.ExitCode)" -Severity 1
        }
    }
    else
    {
        Write-ADTLogEntry -Message 'AWS Session Manager Plugin not found in registry - may already be uninstalled' -Severity 2
    }

    ##================================================
    ## MARK: Post-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    # Verify uninstallation
    Write-ADTLogEntry -Message 'Verifying uninstallation' -Severity 1

    $sessionManagerPath = Join-Path -Path $env:ProgramFiles -ChildPath 'Amazon\SessionManagerPlugin'

    if (Test-Path -Path $sessionManagerPath)
    {
        Write-ADTLogEntry -Message 'Removing remaining installation directory' -Severity 2
        Remove-Item -Path $sessionManagerPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-ADTLogEntry -Message 'Uninstallation completed' -Severity 1
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Show-ADTInstallationProgress -StatusMessage 'Preparing AWS Session Manager Plugin repair...'

    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage 'Repairing AWS Session Manager Plugin...'

    Write-ADTLogEntry -Message 'Starting repair (reinstall)' -Severity 1

    # Repair is essentially a reinstall - call Install function
    Install-ADTDeployment

    Write-ADTLogEntry -Message 'Repair completed' -Severity 1

    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
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
