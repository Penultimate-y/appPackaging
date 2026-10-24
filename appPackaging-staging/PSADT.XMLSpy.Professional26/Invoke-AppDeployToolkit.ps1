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
    AppVendor = 'Altova'
    AppName = 'XMLSpy Professional'
    AppVersion = '2026r2'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('XMLSpy')
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-07-15'
    AppScriptAuthor = 'DWX Team with Claude Code-claude-sonnet-4-5'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Altova XMLSpy Professional 2026 Release 2'
    InstallTitle = 'XMLSpy Professional Installation'

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

    ## Show Welcome Message, close XMLSpy if running
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
    Show-ADTInstallationProgress -StatusMessage 'Preparing XMLSpy Professional installation...'


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Check and install WebView2 Runtime prerequisite
    Show-ADTInstallationProgress -StatusMessage 'Checking WebView2 Runtime prerequisite...'
    Write-ADTLogEntry -Message "Checking if WebView2 Runtime is installed"

    $webview2Installed = $false
    try
    {
        ## Check if WebView2 is installed (check registry)
        $webview2Paths = @(
            'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
        )

        foreach ($path in $webview2Paths)
        {
            if (Test-Path $path)
            {
                $version = (Get-ItemProperty -Path $path -Name 'pv' -ErrorAction SilentlyContinue).pv
                if ($version)
                {
                    Write-ADTLogEntry -Message "WebView2 Runtime is already installed (Version: $version)"
                    $webview2Installed = $true
                    break
                }
            }
        }

        ## Install WebView2 if not present
        if (-not $webview2Installed)
        {
            Write-ADTLogEntry -Message "WebView2 Runtime not found - installing prerequisite"
            Show-ADTInstallationProgress -StatusMessage 'Installing WebView2 Runtime...'

            ## Download WebView2 Runtime bootstrapper
            $webview2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
            $webview2Installer = Join-Path $env:TEMP "MicrosoftEdgeWebview2Setup.exe"

            Write-ADTLogEntry -Message "Downloading WebView2 Runtime from: $webview2Url"
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $webview2Url -OutFile $webview2Installer -UseBasicParsing -ErrorAction Stop
            $ProgressPreference = 'Continue'

            if (Test-Path $webview2Installer)
            {
                Write-ADTLogEntry -Message "Installing WebView2 Runtime"
                $webview2Result = Start-Process -FilePath $webview2Installer -ArgumentList '/silent', '/install' -Wait -PassThru -NoNewWindow -ErrorAction Stop

                if ($webview2Result.ExitCode -eq 0)
                {
                    Write-ADTLogEntry -Message "WebView2 Runtime installed successfully"
                }
                else
                {
                    Write-ADTLogEntry -Message "WebView2 Runtime installation returned exit code: $($webview2Result.ExitCode)" -Severity 2
                }

                ## Clean up installer
                Remove-Item $webview2Installer -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to install WebView2 Runtime: $($_.Exception.Message)" -Severity 2
        Write-ADTLogEntry -Message "Continuing with XMLSpy installation - user may see WebView2 prompt" -Severity 2
    }

    ## Locate the MSI installer (pre-extracted from EXE)
    ## Note: Altova installers are EXE wrappers around MSI files
    ## The MSI has been pre-extracted using: XMLSpyProf2026rel2_x64.exe /u /qn+
    $msiInstallerName = 'XMLSpyProf2026rel2_x64.msi'
    $msiInstallerPath = Join-Path $adtSession.DirFiles $msiInstallerName

    Write-ADTLogEntry -Message "Looking for MSI installer at: $msiInstallerPath"

    if (-not (Test-Path $msiInstallerPath))
    {
        Write-ADTLogEntry -Message "MSI installer not found at: $msiInstallerPath" -Severity 3
        Show-ADTDialogBox -Text "XMLSpy MSI installer file not found. Please ensure $msiInstallerName is in the Files folder." -Icon Stop
        throw "MSI installer not found: $msiInstallerPath"
    }

    $fileSize = (Get-Item $msiInstallerPath).Length / 1MB
    Write-ADTLogEntry -Message "Found MSI installer: $msiInstallerName (Size: $($fileSize.ToString('F2')) MB)"

    ## Install XMLSpy MSI
    Show-ADTInstallationProgress -StatusMessage 'Installing Altova XMLSpy Professional...'
    Write-ADTLogEntry -Message "Installing XMLSpy Professional from MSI: $msiInstallerPath"

    try
    {
        ## Install the MSI using msiexec
        $msiLogPath = "$($adtSession.LogDir)\XMLSpy_MSI_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        $installArgs = @(
            '/i'
            "`"$msiInstallerPath`""
            '/qn'
            '/norestart'
            '/l*vx'
            "`"$msiLogPath`""
            'ALLUSERS=1'
            'REBOOT=ReallySuppress'
        )

        Write-ADTLogEntry -Message "MSI install command: msiexec.exe $($installArgs -join ' ')"

        $installResult = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop

        Write-ADTLogEntry -Message "MSI installation completed with exit code: $($installResult.ExitCode)"
        Write-ADTLogEntry -Message "MSI install log: $msiLogPath"

        if ($installResult.ExitCode -eq 0)
        {
            Write-ADTLogEntry -Message "XMLSpy Professional installation completed successfully"
        }
        elseif ($installResult.ExitCode -eq 3010 -or $installResult.ExitCode -eq 1641)
        {
            Write-ADTLogEntry -Message "XMLSpy Professional installation completed successfully (reboot required)" -Severity 2
        }
        else
        {
            Write-ADTLogEntry -Message "XMLSpy Professional installation failed with exit code: $($installResult.ExitCode)" -Severity 3
            throw "XMLSpy Professional installation failed with exit code: $($installResult.ExitCode)"
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to install XMLSpy Professional: $($_.Exception.Message)" -Severity 3
        throw
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Write registry marker for detection
    try
    {
        Write-ADTLogEntry -Message "Creating registry detection marker"
        $markerPath = 'HKLM:\SOFTWARE\G1001\XMLSpyProfessional2026'

        if (-not (Test-Path $markerPath))
        {
            New-Item -Path $markerPath -Force | Out-Null
        }

        ## Try to get installed version from registry
        $installedVersion = '2026r2'
        try
        {
            $uninstallPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            $xmlSpyInstalled = Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue |
                               Where-Object { $_.DisplayName -like "*XMLSpy*" } |
                               Select-Object -First 1

            if ($xmlSpyInstalled -and $xmlSpyInstalled.DisplayVersion)
            {
                $installedVersion = $xmlSpyInstalled.DisplayVersion
            }
        }
        catch
        {
            Write-ADTLogEntry -Message "Could not query installed version, using default: $installedVersion" -Severity 2
        }

        Set-ItemProperty -Path $markerPath -Name 'InstalledVersion' -Value $installedVersion -Force
        Set-ItemProperty -Path $markerPath -Name 'InstallDate' -Value (Get-Date -Format 'o') -Force
        Set-ItemProperty -Path $markerPath -Name 'DeploymentMethod' -Value 'PSADT-Intune-v4' -Force
        Set-ItemProperty -Path $markerPath -Name 'Edition' -Value 'Professional' -Force

        Write-ADTLogEntry -Message "Registry marker created at $markerPath (Version: $installedVersion)"
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to create registry marker: $($_.Exception.Message)" -Severity 2
    }

    Write-ADTLogEntry -Message "XMLSpy Professional installation completed successfully"

    ## Display completion message
    if ($adtSession.DeployMode -ne 'Silent')
    {
        Show-ADTInstallationPrompt -Message 'Altova XMLSpy Professional has been installed successfully.' -ButtonRightText 'OK' -NoWait
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

    ## Close XMLSpy if running
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Removing Altova XMLSpy Professional...'


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Get XMLSpy installation info
    Write-ADTLogEntry -Message "Locating XMLSpy Professional installation"

    try
    {
        $uninstallPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $xmlSpyInstalled = Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue |
                           Where-Object { $_.DisplayName -like "*XMLSpy*Professional*" } |
                           Select-Object -First 1
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to query registry for XMLSpy: $($_.Exception.Message)" -Severity 3
        throw
    }

    if ($xmlSpyInstalled)
    {
        Write-ADTLogEntry -Message "Found XMLSpy: $($xmlSpyInstalled.DisplayName) ($($xmlSpyInstalled.DisplayVersion))"

        ## Check if it's an MSI installation (has ProductCode/PSChildName as GUID)
        if ($xmlSpyInstalled.PSChildName -match '^\{[A-F0-9-]+\}$')
        {
            $productCode = $xmlSpyInstalled.PSChildName
            Write-ADTLogEntry -Message "Uninstalling via MSI Product Code: $productCode"
            try
            {
                $uninstallArgs = @(
                    '/x'
                    $productCode
                    '/quiet'
                    '/norestart'
                    "/L*V `"$($adtSession.LogDir)\XMLSpy_Uninstall.log`""
                )

                $uninstallResult = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru -NoNewWindow

                if ($uninstallResult.ExitCode -eq 0)
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional uninstalled successfully"
                }
                elseif ($uninstallResult.ExitCode -eq 3010)
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional uninstalled successfully (reboot required)" -Severity 2
                }
                else
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional uninstaller returned exit code: $($uninstallResult.ExitCode)" -Severity 2
                }
            }
            catch
            {
                Write-ADTLogEntry -Message "Failed to uninstall XMLSpy Professional: $($_.Exception.Message)" -Severity 3
                throw
            }
        }
        ## Check if uninstall string is available (EXE installation)
        elseif ($xmlSpyInstalled.UninstallString)
        {
            Write-ADTLogEntry -Message "Uninstalling via UninstallString: $($xmlSpyInstalled.UninstallString)"
            try
            {
                ## Parse uninstall string to separate executable and arguments
                $uninstallCmd = $xmlSpyInstalled.UninstallString
                if ($uninstallCmd -match '^"([^"]+)"(.*)$')
                {
                    $uninstallExe = $matches[1]
                    $uninstallArgs = $matches[2].Trim()
                }
                else
                {
                    $uninstallExe = $uninstallCmd
                    $uninstallArgs = ""
                }

                ## Add silent switches for Inno Setup uninstaller
                ## /VERYSILENT = no dialogs or progress
                ## /SUPPRESSMSGBOXES = suppress message boxes
                ## /NORESTART = don't restart
                if ($uninstallArgs -notmatch '/VERYSILENT')
                {
                    $uninstallArgs = "$uninstallArgs /VERYSILENT /SUPPRESSMSGBOXES /NORESTART".Trim()
                }

                Write-ADTLogEntry -Message "Uninstall command: `"$uninstallExe`" $uninstallArgs"
                $uninstallResult = Start-Process -FilePath $uninstallExe -ArgumentList $uninstallArgs -Wait -PassThru -NoNewWindow

                if ($uninstallResult.ExitCode -eq 0)
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional uninstalled successfully"
                }
                else
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional uninstaller returned exit code: $($uninstallResult.ExitCode)" -Severity 2
                }
            }
            catch
            {
                Write-ADTLogEntry -Message "Failed to uninstall XMLSpy Professional: $($_.Exception.Message)" -Severity 3
                throw
            }
        }
        else
        {
            Write-ADTLogEntry -Message "No uninstall method found (no ProductCode or UninstallString)" -Severity 3
            throw "Cannot uninstall - no uninstall method available"
        }
    }
    else
    {
        Write-ADTLogEntry -Message "XMLSpy Professional is not installed" -Severity 2
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Remove registry marker
    try
    {
        $markerPath = 'HKLM:\SOFTWARE\G1001\XMLSpyProfessional2026'
        if (Test-Path $markerPath)
        {
            Remove-Item -Path $markerPath -Force -ErrorAction Stop
            Write-ADTLogEntry -Message "Removed registry marker at $markerPath"
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to remove registry marker: $($_.Exception.Message)" -Severity 2
    }

    Write-ADTLogEntry -Message "XMLSpy Professional uninstallation completed"
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

    ## Show Welcome Message
    Show-ADTInstallationWelcome

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage 'Repairing Altova XMLSpy Professional...'


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Get XMLSpy installation info
    Write-ADTLogEntry -Message "Locating XMLSpy Professional installation for repair"
    $xmlSpyInstalled = Get-ADTInstalledApplication -Name 'XMLSpy*Professional*'

    if ($xmlSpyInstalled)
    {
        Write-ADTLogEntry -Message "Found XMLSpy: $($xmlSpyInstalled.DisplayName) ($($xmlSpyInstalled.DisplayVersion))"

        ## Check if it's an MSI installation
        if ($xmlSpyInstalled.ProductCode)
        {
            try
            {
                ## Repair using product code
                $repairArgs = @(
                    '/fa'
                    $xmlSpyInstalled.ProductCode
                    '/quiet'
                    '/norestart'
                    "/L*V `"$($adtSession.LogDir)\XMLSpy_Repair.log`""
                )

                $repairResult = Start-Process -FilePath "msiexec.exe" -ArgumentList $repairArgs -Wait -PassThru -NoNewWindow

                if ($repairResult.ExitCode -eq 0)
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional repaired successfully"
                }
                else
                {
                    Write-ADTLogEntry -Message "XMLSpy Professional repair returned exit code: $($repairResult.ExitCode)" -Severity 2
                }
            }
            catch
            {
                Write-ADTLogEntry -Message "Failed to repair XMLSpy Professional: $($_.Exception.Message)" -Severity 3
                throw
            }
        }
        else
        {
            Write-ADTLogEntry -Message "Repair not supported for EXE installations - performing reinstall" -Severity 2
            Show-ADTDialogBox -Text "Repair is not supported for this installation type. Please uninstall and reinstall instead." -Icon Warning
            throw "Repair not supported for EXE installation"
        }
    }
    else
    {
        Write-ADTLogEntry -Message "XMLSpy Professional is not installed - cannot repair" -Severity 3
        Show-ADTDialogBox -Text "XMLSpy Professional is not installed. Please run an installation instead." -Icon Stop
        throw "XMLSpy Professional not installed"
    }


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message "XMLSpy Professional repair completed"
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
