<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

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
    AppVendor = 'Microsoft'
    AppName = 'Windows Update ESP'
    AppVersion = '1.0'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()  # No processes to close - runs during ESP Device Setup phase
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-06-20'
    AppScriptAuthor = 'Zachary Hayward with Claude Code-claude-sonnet-4-5'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Windows Update - ESP Pre-provisioning'
    InstallTitle = 'Windows Update Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

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

    ## No welcome message - this runs during ESP with no user interaction
    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Preparing Windows Update installation...'

    ## Check if we're in ESP/OOBE phase
    try
    {
        $autopilotESPStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotPolicyCache" -ErrorAction SilentlyContinue
        if ($autopilotESPStatus)
        {
            Write-ADTLogEntry -Message "Detected Autopilot enrollment context"
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Could not detect Autopilot context: $($_.Exception.Message)" -Severity 2
    }


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Install NuGet provider
    Show-ADTInstallationProgress -StatusMessage 'Installing NuGet provider...'
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (!$nuget)
    {
        Write-ADTLogEntry -Message "Installing NuGet provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
        Write-ADTLogEntry -Message "NuGet provider installed successfully"
    }
    else
    {
        Write-ADTLogEntry -Message "NuGet provider already installed (Version: $($nuget.Version))"
    }

    ## Set PSGallery as trusted
    Show-ADTInstallationProgress -StatusMessage 'Configuring PSGallery repository...'
    Write-ADTLogEntry -Message "Setting PSGallery as trusted repository..."
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop

    ## Install PSWindowsUpdate module
    Show-ADTInstallationProgress -StatusMessage 'Installing PSWindowsUpdate module...'
    $module = Get-Module -ListAvailable -Name PSWindowsUpdate | Sort-Object Version -Descending | Select-Object -First 1

    if (!$module)
    {
        Write-ADTLogEntry -Message "Installing PSWindowsUpdate module..."
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -SkipPublisherCheck
        Write-ADTLogEntry -Message "PSWindowsUpdate module installed successfully"
    }
    else
    {
        Write-ADTLogEntry -Message "PSWindowsUpdate module already installed (Version: $($module.Version))"
    }

    Import-Module PSWindowsUpdate -Force
    Write-ADTLogEntry -Message "PSWindowsUpdate module imported"

    ## Check for available updates
    Show-ADTInstallationProgress -StatusMessage 'Checking for Windows Updates...'
    Write-ADTLogEntry -Message "Checking for available Windows Updates..."
    $availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -Verbose

    if ($availableUpdates)
    {
        Write-ADTLogEntry -Message "Found $($availableUpdates.Count) update(s) available"

        ## Install updates
        Show-ADTInstallationProgress -StatusMessage "Installing $($availableUpdates.Count) Windows Update(s)... This may take 30-60+ minutes."
        Write-ADTLogEntry -Message "Starting Windows Update installation..."

        $updateResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose

        if ($updateResult)
        {
            Write-ADTLogEntry -Message "Updates installed successfully"

            foreach ($update in $updateResult)
            {
                Write-ADTLogEntry -Message "  - $($update.Title) | Result: $($update.Result)"
            }

            ## Create marker directory
            $markerPath = "$env:ProgramData\WindowsUpdate-ESP"
            if (!(Test-Path $markerPath))
            {
                New-Item -ItemType Directory -Path $markerPath -Force | Out-Null
            }

            ## Create marker file
            $markerData = @{
                InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                UpdateCount = $updateResult.Count
                RebootRequired = (Get-WURebootStatus -Silent)
                Updates = $updateResult | Select-Object Title, KB, Result
            }

            $markerFile = "$markerPath\UpdatesInstalled.json"
            $markerData | ConvertTo-Json -Depth 3 | Out-File -FilePath $markerFile -Force
            Write-ADTLogEntry -Message "Marker file created at: $markerFile"

            ## Check reboot status
            $rebootRequired = Get-WURebootStatus -Silent

            ## Create registry key
            $regPath = "HKLM:\SOFTWARE\WindowsUpdate-ESP"
            if (!(Test-Path $regPath))
            {
                New-Item -Path $regPath -Force | Out-Null
            }

            if ($rebootRequired)
            {
                Write-ADTLogEntry -Message "REBOOT REQUIRED - Updates will complete after next restart" -Severity 2
                Set-ItemProperty -Path $regPath -Name "RebootRequired" -Value 1 -Type DWord -Force

                ## Set reboot exit code for Intune - PSADT v4 will handle this automatically
                $adtSession.ExitCode = 3010
            }
            else
            {
                Write-ADTLogEntry -Message "No reboot required"
                Set-ItemProperty -Path $regPath -Name "RebootRequired" -Value 0 -Type DWord -Force
            }
        }
        else
        {
            Write-ADTLogEntry -Message "No updates were installed (may have failed or been skipped)" -Severity 2
        }
    }
    else
    {
        Write-ADTLogEntry -Message "No Windows Updates available - system is up to date"

        ## Create marker even if no updates
        $markerPath = "$env:ProgramData\WindowsUpdate-ESP"
        if (!(Test-Path $markerPath))
        {
            New-Item -ItemType Directory -Path $markerPath -Force | Out-Null
        }

        $markerData = @{
            InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            UpdateCount = 0
            RebootRequired = $false
            Message = "No updates available"
        }

        $markerFile = "$markerPath\UpdatesInstalled.json"
        $markerData | ConvertTo-Json -Depth 3 | Out-File -FilePath $markerFile -Force
        Write-ADTLogEntry -Message "Marker file created (no updates needed)"

        ## Create registry key
        $regPath = "HKLM:\SOFTWARE\WindowsUpdate-ESP"
        if (!(Test-Path $regPath))
        {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "RebootRequired" -Value 0 -Type DWord -Force
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message "Windows Update ESP installation completed successfully"

    ## No end-user message needed - this runs silently during ESP
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

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Removing Windows Update ESP tracking files...'


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Remove marker directory
    $markerPath = "$env:ProgramData\WindowsUpdate-ESP"
    if (Test-Path $markerPath)
    {
        Write-ADTLogEntry -Message "Removing marker directory: $markerPath"
        Remove-Item -Path $markerPath -Recurse -Force
    }

    ## Remove registry key
    $regPath = "HKLM:\SOFTWARE\WindowsUpdate-ESP"
    if (Test-Path $regPath)
    {
        Write-ADTLogEntry -Message "Removing registry key: $regPath"
        Remove-Item -Path $regPath -Recurse -Force
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message "Windows Update ESP uninstallation completed successfully"
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## If there are processes to close, show Welcome Message with a 60 second countdown before automatically closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Repair tasks here>


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI repairs.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## <Perform Repair tasks here>


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Repair tasks here>
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

