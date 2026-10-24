<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of Grammarly Desktop.

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of Grammarly Desktop.
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
- Downloads the latest Grammarly installer dynamically from: https://download-windows.grammarly.com/GrammarlyInstaller-perMachine.exe
- Configures enterprise enrollment with SSO mode enabled

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
    AppVendor = 'Grammarly'
    AppName = 'Grammarly Desktop'
    AppVersion = 'Latest'
    AppArch = 'x86'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('Grammarly.Desktop')
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-07-31'
    AppScriptAuthor = 'Allen Johnson with Claude Code-claude-sonnet-4-5'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Grammarly Desktop (Latest)'
    InstallTitle = 'Grammarly Desktop Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

## Grammarly-specific configuration
$grammarlyDownloadUrl = "https://download-windows.grammarly.com/GrammarlyInstaller-perMachine.exe"
$grammarlyEnrollmentToken = "e70bf587-b51c-41db-b159-f1cb9f522ecb"  # UPDATE THIS FOR YOUR ORGANIZATION
$grammarlyRegistryPath = "HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations"

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, close Grammarly if running
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

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Preparing Grammarly Desktop installation...'


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Download and install latest Grammarly
    Show-ADTInstallationProgress -StatusMessage 'Downloading latest Grammarly Desktop...'
    Write-ADTLogEntry -Message "Downloading latest Grammarly installer"

    try
    {
        ## Download installer
        $installerPath = "$env:TEMP\GrammarlyInstaller-perMachine.exe"

        Write-ADTLogEntry -Message "Downloading from: $grammarlyDownloadUrl"
        Invoke-WebRequest -Uri $grammarlyDownloadUrl -OutFile $installerPath -UseBasicParsing

        Write-ADTLogEntry -Message "Download completed: $installerPath"

        ## Verify download
        if (-not (Test-Path $installerPath))
        {
            throw "Failed to download Grammarly installer"
        }

        $fileSize = (Get-Item $installerPath).Length
        Write-ADTLogEntry -Message "Downloaded file size: $($fileSize / 1MB) MB"

        ## Run silent installation with SSO mode
        Show-ADTInstallationProgress -StatusMessage 'Installing Grammarly Desktop...'
        Write-ADTLogEntry -Message "Running Grammarly installer: $installerPath"

        $installArgs = @(
            '/quiet'
            'SSOMode=1'
        )

        ## Start installer and wait
        $installerProcess = Start-Process -FilePath $installerPath -ArgumentList $installArgs -PassThru -NoNewWindow

        Write-ADTLogEntry -Message "Installer process started (PID: $($installerProcess.Id))"
        $installerProcess.WaitForExit()

        Write-ADTLogEntry -Message "Installer process completed with exit code: $($installerProcess.ExitCode)"

        ## Verify installation
        if ($installerProcess.ExitCode -eq 0)
        {
            Write-ADTLogEntry -Message "Grammarly Desktop installation completed successfully"
        }
        else
        {
            throw "Grammarly installation failed with exit code: $($installerProcess.ExitCode)"
        }

        ## Clean up installer
        if (Test-Path $installerPath)
        {
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
            Write-ADTLogEntry -Message "Installer cleaned up: $installerPath"
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to install Grammarly: $($_.Exception.Message)" -Severity 3
        throw
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Configure Enterprise Enrollment
    Show-ADTInstallationProgress -StatusMessage 'Configuring Grammarly enterprise enrollment...'
    Write-ADTLogEntry -Message "Configuring enterprise enrollment registry"

    try
    {
        ## Create registry path if it doesn't exist
        if (-not (Test-Path $grammarlyRegistryPath))
        {
            Write-ADTLogEntry -Message "Creating registry path: $grammarlyRegistryPath"
            New-Item -Path $grammarlyRegistryPath -Force | Out-Null
        }

        ## Set enrollment token
        $existingToken = Get-ItemProperty -Path $grammarlyRegistryPath -Name "GrammarlyEnrollmentToken" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty GrammarlyEnrollmentToken

        if ($existingToken)
        {
            Write-ADTLogEntry -Message "Enrollment token already exists"
        }
        else
        {
            Write-ADTLogEntry -Message "Setting enrollment token"
            New-ItemProperty -Path $grammarlyRegistryPath -Name "GrammarlyEnrollmentToken" -Value $grammarlyEnrollmentToken -PropertyType String -Force | Out-Null
        }

        ## Set version marker
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        Set-ItemProperty -Path $grammarlyRegistryPath -Name "DeploymentDate" -Value $currentDate -Type String -Force
        Write-ADTLogEntry -Message "Deployment date marker set: $currentDate"

        Write-ADTLogEntry -Message "Enterprise enrollment configuration completed"
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to configure enrollment: $($_.Exception.Message)" -Severity 2
        # Non-fatal - installation succeeded even if enrollment config had issues
    }

    ## Verify installation
    $grammarlyExe = "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe"
    if (Test-Path $grammarlyExe)
    {
        Write-ADTLogEntry -Message "Verification PASS: Grammarly executable found at $grammarlyExe"
    }
    else
    {
        Write-ADTLogEntry -Message "Verification WARNING: Expected executable not found at $grammarlyExe" -Severity 2
    }

    ## Display a message at the end of the install
    if (-not $adtSession.IsNonInteractive)
    {
        Show-ADTInstallationPrompt -Message 'Grammarly Desktop has been installed successfully. You can now use Grammarly across your applications.' -ButtonRightText 'OK' -Icon Information
    }
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, close Grammarly if running
    $saiwParams = @{
        AllowDefer = $true
        DeferTimes = 3
        PersistPrompt = $true
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Preparing Grammarly Desktop uninstallation...'


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage 'Uninstalling Grammarly Desktop...'
    Write-ADTLogEntry -Message "Beginning Grammarly uninstallation"

    try
    {
        ## Find Grammarly uninstaller
        $uninstallerPath = "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Uninstall.exe"

        if (Test-Path $uninstallerPath)
        {
            Write-ADTLogEntry -Message "Found Grammarly uninstaller: $uninstallerPath"

            $uninstallArgs = @('/S')  # Silent uninstall (NSIS)

            $uninstallProcess = Start-Process -FilePath $uninstallerPath -ArgumentList $uninstallArgs -PassThru -NoNewWindow
            Write-ADTLogEntry -Message "Uninstaller process started (PID: $($uninstallProcess.Id))"

            $uninstallProcess.WaitForExit()
            Write-ADTLogEntry -Message "Uninstaller completed with exit code: $($uninstallProcess.ExitCode)"

            ## Give Windows time to clean up files
            Start-Sleep -Seconds 2
        }
        else
        {
            Write-ADTLogEntry -Message "Grammarly uninstaller not found at: $uninstallerPath" -Severity 2
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to uninstall Grammarly: $($_.Exception.Message)" -Severity 3
        throw
    }


    ##================================================
    ## MARK: Post-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Clean up registry
    Write-ADTLogEntry -Message "Cleaning up Grammarly registry entries"

    try
    {
        if (Test-Path $grammarlyRegistryPath)
        {
            Remove-Item -Path $grammarlyRegistryPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-ADTLogEntry -Message "Registry path removed: $grammarlyRegistryPath"
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to remove registry entries: $($_.Exception.Message)" -Severity 2
    }

    ## Verify uninstallation
    $grammarlyExe = "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe"
    if (-not (Test-Path $grammarlyExe))
    {
        Write-ADTLogEntry -Message "Verification PASS: Grammarly executable has been removed"
    }
    else
    {
        Write-ADTLogEntry -Message "Verification WARNING: Grammarly executable still exists at $grammarlyExe" -Severity 2
    }
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ## Same logic as Install
    Install-ADTDeployment
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

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}
