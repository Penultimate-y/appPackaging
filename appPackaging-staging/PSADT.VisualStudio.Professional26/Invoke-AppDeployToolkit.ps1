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
    AppName = 'Visual Studio Professional 2026'
    AppVersion = '17.0'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0, 3010)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('devenv', 'MSBuild', 'vbcscompiler', 'PerfWatson2', 'ServiceHub.Host.dotnet.x64', 'ServiceHub.RoslynCodeAnalysisService')
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-07-08'
    AppScriptAuthor = 'DWX Team with Claude Code (claude-sonnet-4-6)'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Visual Studio Professional 2026'
    InstallTitle = 'Visual Studio Professional 2026'

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

    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
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

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Installation tasks here>


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI installations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
        if ($adtSession.DefaultMspFiles)
        {
            $adtSession.DefaultMspFiles | Start-ADTMsiProcess -Action Patch
        }
    }

    ## Install Visual Studio Professional 2026
    # Self-contained installation that intelligently locates or creates an offline layout
    # Bypasses Visual Studio Installer launcher completely with --noWeb flag
    # Based on proven VS_Pro_Install_SelfContained.ps1 logic

    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Visual Studio 2026 Self-Contained Installer" -Severity 1
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Target: Visual Studio Professional 2026 17.12.0" -Severity 1

    # Check if already installed
    Write-ADTLogEntry -Message "Checking for existing installation..."
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installedApps = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($app in $installedApps) {
                $displayName = (Get-ItemProperty -Path $app.PSPath -ErrorAction SilentlyContinue).DisplayName
                if ($displayName -like "*Visual Studio Professional 2026*") {
                    Write-ADTLogEntry -Message "Visual Studio 2026 Professional already installed: $displayName" -Severity 2
                    Write-ADTLogEntry -Message "Skipping installation" -Severity 1
                    return
                }
            }
        }
    }

    Write-ADTLogEntry -Message "No existing installation detected"

    # Check system requirements
    $systemDrive = $env:SystemDrive
    $disk = Get-PSDrive -Name $systemDrive.TrimEnd(':')
    $freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
    Write-ADTLogEntry -Message "Free space on $systemDrive : $freeSpaceGB GB"

    if ($freeSpaceGB -lt 20) {
        Write-ADTLogEntry -Message "WARNING: Low disk space. At least 20GB recommended, only $freeSpaceGB GB available" -Severity 2
    }

    # Configuration - Workloads to install
    $workloads = @(
        'Microsoft.VisualStudio.Workload.ManagedDesktop',  # .NET desktop development
        'Microsoft.VisualStudio.Workload.NetWeb',          # ASP.NET and web development
        'Microsoft.VisualStudio.Workload.Azure',           # Azure development
        'Microsoft.VisualStudio.Workload.Data'             # Data storage and processing
    )

    # Layout search paths (checked in order)
    $layoutSearchPaths = @(
        # Option 1: Layout in same directory as script (Win32 app package)
        (Join-Path $adtSession.DirFiles "VS2026_Layout"),

        # Option 2: Network share (recommended for multiple deployments)
        "\\fileserver\packages\VS2026_Professional_Offline_Layout",

        # Option 3: Pre-staged local path
        "C:\Packages\VS2026_Professional_Offline_Layout",

        # Option 4: Standard location from separate layout creation
        "C:\VS2026_Professional_Offline_Layout"
    )

    # Auto-create layout if not found? (requires internet connection and 30-60 minutes)
    $autoCreateLayout = $true
    $layoutCreationPath = "C:\VS2026_Professional_Offline_Layout"

    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Layout Detection" -Severity 1
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Searching for Visual Studio offline layout..."

    $layoutFound = $false
    $layoutPath = $null
    $installerExe = $null

    foreach ($searchPath in $layoutSearchPaths) {
        Write-ADTLogEntry -Message "Checking: $searchPath"

        if (Test-Path $searchPath) {
            $testInstallerExe = Join-Path $searchPath "vs_Professional.exe"

            if (Test-Path $testInstallerExe) {
                $layoutPath = $searchPath
                $installerExe = $testInstallerExe
                $layoutFound = $true
                Write-ADTLogEntry -Message "Layout found at: $layoutPath"

                # Calculate layout size
                try {
                    $layoutSize = (Get-ChildItem -Path $layoutPath -Recurse -ErrorAction SilentlyContinue |
                                  Measure-Object -Property Length -Sum).Sum / 1GB
                    Write-ADTLogEntry -Message "Layout size: $([math]::Round($layoutSize, 2)) GB"
                }
                catch {
                    Write-ADTLogEntry -Message "Could not calculate layout size" -Severity 2
                }

                break
            }
            else {
                Write-ADTLogEntry -Message "Directory exists but vs_Professional.exe not found" -Severity 2
            }
        }
    }

    # Layout Creation (if needed)
    if (-not $layoutFound) {
        Write-ADTLogEntry -Message "No offline layout found in any search path" -Severity 2

        if ($autoCreateLayout) {
            Write-ADTLogEntry -Message "Auto-create layout is ENABLED - will create layout at: $layoutCreationPath" -Severity 1
            Write-ADTLogEntry -Message "This will require internet connection and take 30-60 minutes" -Severity 2

            # Find bootstrapper
            $bootstrapper = Join-Path $adtSession.DirFiles "vs_Professional.exe"

            if (-not (Test-Path $bootstrapper)) {
                Write-ADTLogEntry -Message "Bootstrapper not found: $bootstrapper" -Severity 3
                Write-ADTLogEntry -Message "Cannot create layout without vs_Professional.exe bootstrapper" -Severity 3
                Write-ADTLogEntry -Message "Please package vs_Professional.exe with this script or disable auto-create" -Severity 3
                throw "Layout creation requires vs_Professional.exe bootstrapper"
            }

            Write-ADTLogEntry -Message "Bootstrapper found: $bootstrapper"

            # Check disk space for layout creation
            $layoutDrive = Split-Path -Qualifier $layoutCreationPath
            $layoutDisk = Get-PSDrive -Name $layoutDrive.TrimEnd(':')
            $layoutFreeSpace = [math]::Round($layoutDisk.Free / 1GB, 2)

            if ($layoutFreeSpace -lt 40) {
                Write-ADTLogEntry -Message "Insufficient disk space for layout creation" -Severity 3
                Write-ADTLogEntry -Message "Required: 40GB, Available: $layoutFreeSpace GB on $layoutDrive" -Severity 3
                throw "Insufficient disk space for layout creation"
            }

            # Create layout directory
            if (-not (Test-Path $layoutCreationPath)) {
                Write-ADTLogEntry -Message "Creating layout directory: $layoutCreationPath"
                New-Item -Path $layoutCreationPath -ItemType Directory -Force | Out-Null
            }

            # Build layout creation arguments
            $layoutArgs = @(
                '--layout', $layoutCreationPath,
                '--lang', 'en-US',
                '--quiet',
                '--wait',
                '--norestart'
            )

            foreach ($workload in $workloads) {
                $layoutArgs += '--add'
                $layoutArgs += $workload
            }

            $layoutArgs += '--includeOptional'

            Write-ADTLogEntry -Message "Creating offline layout with workloads:"
            foreach ($workload in $workloads) {
                Write-ADTLogEntry -Message "  - $workload"
            }

            Write-ADTLogEntry -Message "Executing: $bootstrapper $($layoutArgs -join ' ')"
            Write-ADTLogEntry -Message "Layout creation started - this may take 30-60 minutes..."

            $layoutResult = Invoke-ADTProcess -FilePath $bootstrapper -Parameters $layoutArgs -WaitForProcess -PassThru

            Write-ADTLogEntry -Message "Layout creation completed with exit code: $($layoutResult.ExitCode)"

            if ($layoutResult.ExitCode -eq 0 -or $layoutResult.ExitCode -eq 3010) {
                Write-ADTLogEntry -Message "Layout created successfully"

                $layoutPath = $layoutCreationPath
                $installerExe = Join-Path $layoutPath "vs_Professional.exe"
                $layoutFound = $true
            }
            else {
                Write-ADTLogEntry -Message "Layout creation failed with exit code: $($layoutResult.ExitCode)" -Severity 3
                throw "Layout creation failed"
            }
        }
        else {
            Write-ADTLogEntry -Message "Auto-create layout is DISABLED" -Severity 1
            Write-ADTLogEntry -Message "Please ensure the offline layout is available in one of these locations:" -Severity 3
            foreach ($searchPath in $layoutSearchPaths) {
                Write-ADTLogEntry -Message "  - $searchPath" -Severity 3
            }
            Write-ADTLogEntry -Message "Or set autoCreateLayout = `$true to enable automatic creation" -Severity 1
            throw "Visual Studio layout not found and auto-create is disabled"
        }
    }

    # Installation
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Starting Installation" -Severity 1
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Layout path: $layoutPath"
    Write-ADTLogEntry -Message "Installer: $installerExe"
    Write-ADTLogEntry -Message "Installation will take approximately 15-30 minutes"

    # Build installation arguments
    $installArgs = @(
        '--noWeb',                  # Force offline mode - bypass launcher
        '--quiet',                  # Silent installation
        '--wait',                   # Wait for completion
        '--norestart'               # Prevent automatic reboot
    )

    foreach ($workload in $workloads) {
        $installArgs += '--add'
        $installArgs += $workload
    }

    $installArgs += '--includeOptional'

    Write-ADTLogEntry -Message "Installing workloads:"
    foreach ($workload in $workloads) {
        Write-ADTLogEntry -Message "  - $workload"
    }

    Write-ADTLogEntry -Message "Install command: $installerExe $($installArgs -join ' ')"

    $installResult = Invoke-ADTProcess -FilePath $installerExe -Parameters $installArgs -WaitForProcess -PassThru

    Write-ADTLogEntry -Message "Installation process completed with exit code: $($installResult.ExitCode)"

    # Interpret exit codes
    switch ($installResult.ExitCode) {
        0 {
            Write-ADTLogEntry -Message "Installation completed successfully"
        }
        3010 {
            Write-ADTLogEntry -Message "Installation completed successfully - reboot required"
        }
        5007 {
            Write-ADTLogEntry -Message "Installation blocked - pending reboot detected" -Severity 3
            Write-ADTLogEntry -Message "Please reboot the system and retry" -Severity 3
            throw "Pending reboot blocks installation"
        }
        5004 {
            Write-ADTLogEntry -Message "Another Visual Studio installer instance is already running" -Severity 3
            throw "Another installer instance running"
        }
        default {
            Write-ADTLogEntry -Message "Installation completed with exit code: $($installResult.ExitCode)" -Severity 2
        }
    }

    # Post-Installation Validation
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Validating Installation" -Severity 1
    Write-ADTLogEntry -Message "======================================" -Severity 1

    # Wait for registry to propagate
    Start-Sleep -Seconds 10

    $installDetected = $false
    $detectionMethods = @()

    # Method 1: Registry detection
    Write-ADTLogEntry -Message "Checking registry..."
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installedApps = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($app in $installedApps) {
                $appProps = Get-ItemProperty -Path $app.PSPath -ErrorAction SilentlyContinue
                $displayName = $appProps.DisplayName
                $displayVersion = $appProps.DisplayVersion

                if ($displayName -like "*Visual Studio Professional 2026*") {
                    Write-ADTLogEntry -Message "Registry detection SUCCESS: $displayName version $displayVersion"
                    $installDetected = $true
                    $detectionMethods += "Registry"
                    break
                }
            }
        }
        if ($installDetected) { break }
    }

    # Method 2: File detection
    Write-ADTLogEntry -Message "Checking installation files..."
    $vsInstallPaths = @(
        "$env:ProgramFiles\Microsoft Visual Studio\2026\Professional\Common7\IDE\devenv.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2026\Professional\Common7\IDE\devenv.exe"
    )

    foreach ($vsPath in $vsInstallPaths) {
        if (Test-Path $vsPath) {
            Write-ADTLogEntry -Message "File detection SUCCESS: devenv.exe found at $vsPath"
            $installDetected = $true
            $detectionMethods += "File"
            break
        }
    }

    # Method 3: Installer shell detection
    $installerShellPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installershell.exe"
    if (Test-Path $installerShellPath) {
        Write-ADTLogEntry -Message "Installer shell found at $installerShellPath"
    }

    # Final Status
    Write-ADTLogEntry -Message "======================================"

    if ($installDetected) {
        Write-ADTLogEntry -Message "INSTALLATION SUCCESSFUL"
        Write-ADTLogEntry -Message "Detection methods: $($detectionMethods -join ', ')"
        Write-ADTLogEntry -Message "Exit code: $($installResult.ExitCode)"

        if ($installResult.ExitCode -eq 3010) {
            Write-ADTLogEntry -Message "REBOOT REQUIRED to complete installation" -Severity 2
        }
    }
    else {
        Write-ADTLogEntry -Message "INSTALLATION VERIFICATION FAILED" -Severity 3
        Write-ADTLogEntry -Message "Installation process completed but validation failed" -Severity 3
        Write-ADTLogEntry -Message "Installer exit code: $($installResult.ExitCode)" -Severity 3
        Write-ADTLogEntry -Message "This may indicate:" -Severity 3
        Write-ADTLogEntry -Message "  - Installation failed silently" -Severity 3
        Write-ADTLogEntry -Message "  - Detection paths need adjustment" -Severity 3
        Write-ADTLogEntry -Message "  - Additional time needed for post-install tasks" -Severity 3
        throw "Installation verification failed"
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Installation tasks here>


    ## Display a message at the end of the install.
    if (!$adtSession.UseDefaultMsi)
    {
        Show-ADTInstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -NoWait
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

    ## If there are processes to close, show Welcome Message with a 60 second countdown before automatically closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Uninstallation tasks here>


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI uninstallations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## Uninstall Visual Studio Professional 2026
    # Visual Studio uninstallation requires the vs_Professional.exe bootstrapper
    # with the uninstall command

    $vsInstallerPath = "$($adtSession.DirFiles)\vs_Professional.exe"

    # Alternative: Use the installed Visual Studio Installer
    $vsInstallerInstalled = "$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vs_installer.exe"

    if (Test-Path $vsInstallerInstalled) {
        Write-ADTLogEntry -Message "Starting Visual Studio Professional 2026 uninstallation using installed VS Installer"

        $uninstallArgs = @(
            'uninstall'
            '--installPath', "$env:ProgramFiles\Microsoft Visual Studio\2026\Professional"
            '--quiet'
            '--wait'
            '--norestart'
        )

        Invoke-ADTProcess -FilePath $vsInstallerInstalled -Parameters $uninstallArgs -WaitForProcess

        Write-ADTLogEntry -Message "Visual Studio Professional 2026 uninstallation completed"
    }
    elseif (Test-Path $vsInstallerPath) {
        Write-ADTLogEntry -Message "Starting Visual Studio Professional 2026 uninstallation using packaged installer"

        $uninstallArgs = @(
            'uninstall'
            '--installPath', "$env:ProgramFiles\Microsoft Visual Studio\2026\Professional"
            '--quiet'
            '--wait'
            '--norestart'
        )

        Invoke-ADTProcess -FilePath $vsInstallerPath -Parameters $uninstallArgs -WaitForProcess

        Write-ADTLogEntry -Message "Visual Studio Professional 2026 uninstallation completed"
    }
    else {
        Write-ADTLogEntry -Message "Visual Studio installer not found. Manual uninstallation may be required." -Severity 2
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>
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

