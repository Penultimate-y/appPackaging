<#

.SYNOPSIS
PSAppDeployToolkit - First Run User Onboarding Experience

.DESCRIPTION
Guides users through essential first-login setup steps:
1. Welcome message with progress tracking
2. Wait for Zscaler security tunnel
3. Update Windows Defender definitions
4. Launch Outlook with automatic error recovery
5. Launch Microsoft Teams
6. Ensure OneDrive is running
7. Launch Company Portal for app catalog

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
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Interactive

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

Custom Exit Codes:
- 69001: Zscaler service timeout (non-fatal, continues)
- 69002: Defender update failed (non-fatal, continues)
- 69003: Outlook launch failed (non-fatal, continues)

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
    AppVendor = 'G1001'
    AppName = 'First Run Onboarding'
    AppVersion = '1.0.0'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-06-21'
    AppScriptAuthor = 'Zachary Hayward with Claude Code-claude-sonnet-4-5'
    RequireAdmin = $false

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'First Run Setup'
    InstallTitle = 'Welcome to Group1001'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

##================================================
## MARK: Helper Functions
##================================================

function Wait-ZscalerReady
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Step 2/7: Waiting for Zscaler security tunnel"
    Show-ADTInstallationProgress -StatusMessage "Initializing security tunnel... (Step 2 of 7)"

    $maxWaitSeconds = 90
    $elapsed = 0
    $checkInterval = 5

    $requiredServices = @('ZSAService', 'ZSATunnel')

    while ($elapsed -lt $maxWaitSeconds)
    {
        $allRunning = $true

        foreach ($serviceName in $requiredServices)
        {
            try
            {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($null -eq $service -or $service.Status -ne 'Running')
                {
                    $allRunning = $false
                    Write-ADTLogEntry -Message "Service $serviceName not yet running (Status: $($service.Status))"
                    break
                }
            }
            catch
            {
                Write-ADTLogEntry -Message "Service $serviceName not found: $($_.Exception.Message)"
                $allRunning = $false
                break
            }
        }

        if ($allRunning)
        {
            Write-ADTLogEntry -Message "All required Zscaler services are running"
            # Give tunnel time to establish after services report "Running"
            Start-Sleep -Seconds 15
            Write-ADTLogEntry -Message "Zscaler tunnel ready"
            return $true
        }

        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval
        Write-ADTLogEntry -Message "Waiting for Zscaler services... ($elapsed/$maxWaitSeconds seconds)"
    }

    # Timeout reached - log warning but continue
    Write-ADTLogEntry -Message "Zscaler services not ready after $maxWaitSeconds seconds - continuing anyway" -Severity 2
    return $false
}

function Update-DefenderDefinitions
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Step 3/7: Updating Windows Defender definitions"
    Show-ADTInstallationProgress -StatusMessage "Updating security definitions... (Step 3 of 7)"

    try
    {
        Update-MpSignature -ErrorAction Stop
        Write-ADTLogEntry -Message "Windows Defender definitions updated successfully"
        return $true
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to update Defender definitions: $($_.Exception.Message)" -Severity 2
        return $false
    }
}

function Start-OutlookFirstRun
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Step 4/7: Setting up Outlook"
    Show-ADTInstallationProgress -StatusMessage "Let's setup your email... (Step 4 of 7)"

    # Check if Outlook is already running
    $outlookProcess = Get-Process -Name "OUTLOOK","olk" -ErrorAction SilentlyContinue
    if ($outlookProcess)
    {
        Write-ADTLogEntry -Message "Outlook is already running (PID: $($outlookProcess[0].Id))"
        return $true
    }

    $outlookPath = "${env:ProgramFiles}\Microsoft Office\root\Office16\OUTLOOK.EXE"
    $exePath = $null

    # Prefer new Outlook (AppX package) - check via Get-AppxPackage
    try
    {
        $outlookPackage = Get-AppxPackage -Name "Microsoft.OutlookForWindows" -ErrorAction SilentlyContinue
        if ($outlookPackage -and $outlookPackage.InstallLocation)
        {
            $newOutlookExe = Join-Path $outlookPackage.InstallLocation "olk.exe"
            if (Test-Path $newOutlookExe)
            {
                $exePath = $newOutlookExe
                Write-ADTLogEntry -Message "Using new Outlook (AppX): $exePath"
            }
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Error checking for new Outlook: $($_.Exception.Message)" -Severity 2
    }

    # Fallback to classic Outlook
    if (!$exePath -and (Test-Path $outlookPath))
    {
        $exePath = $outlookPath
        Write-ADTLogEntry -Message "Using classic Outlook: $outlookPath"
    }

    if (!$exePath)
    {
        Write-ADTLogEntry -Message "Outlook not found at expected paths" -Severity 2
        return $false
    }

    try
    {
        # Launch Outlook
        $process = Start-Process -FilePath $exePath -PassThru -ErrorAction Stop
        Write-ADTLogEntry -Message "Outlook launched (PID: $($process.Id))"

        # Wait and detect error state
        Start-Sleep -Seconds 10

        # Check if Outlook exited quickly (indicates error)
        if ($process.HasExited)
        {
            Write-ADTLogEntry -Message "Outlook exited unexpectedly - attempting recovery with --clearLocalState" -Severity 2

            if ($exePath -like "*olk.exe")
            {
                # Run clearLocalState fix
                Write-ADTLogEntry -Message "Running: olk.exe --clearLocalState"
                Start-Process -FilePath $exePath -ArgumentList "--clearLocalState" -Wait -NoNewWindow -ErrorAction Stop

                # Relaunch Outlook
                Write-ADTLogEntry -Message "Relaunching Outlook after clearLocalState"
                Start-Process -FilePath $exePath -ErrorAction Stop
                return $true
            }
            else
            {
                Write-ADTLogEntry -Message "Classic Outlook doesn't support --clearLocalState, skipping recovery" -Severity 2
                return $false
            }
        }

        # Outlook is still running - no error detected
        Write-ADTLogEntry -Message "Outlook launched successfully"
        return $true
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to launch Outlook: $($_.Exception.Message)" -Severity 2
        return $false
    }
}

function Start-TeamsFirstRun
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Step 5/7: Setting up Microsoft Teams"
    Show-ADTInstallationProgress -StatusMessage "Let's setup Teams... (Step 5 of 7)"

    # Check if Teams is already running
    $teamsProcess = Get-Process -Name "ms-teams","Teams" -ErrorAction SilentlyContinue
    if ($teamsProcess)
    {
        Write-ADTLogEntry -Message "Teams is already running (PID: $($teamsProcess[0].Id))"
        return $true
    }

    # Try new Teams (Windows 11 AppX package) first
    try
    {
        $teamsPackage = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
        if ($teamsPackage -and $teamsPackage.InstallLocation)
        {
            $newTeamsExe = Join-Path $teamsPackage.InstallLocation "ms-teams.exe"
            if (Test-Path $newTeamsExe)
            {
                Start-Process -FilePath $newTeamsExe -ErrorAction Stop
                Write-ADTLogEntry -Message "Teams launched from: $newTeamsExe"
                return $true
            }
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Error launching new Teams: $($_.Exception.Message)" -Severity 2
    }

    # Fallback to classic Teams (legacy)
    $classicTeamsPath = "${env:LOCALAPPDATA}\Microsoft\Teams\current\Teams.exe"
    if (Test-Path $classicTeamsPath)
    {
        try
        {
            Start-Process -FilePath $classicTeamsPath -ErrorAction Stop
            Write-ADTLogEntry -Message "Teams launched from: $classicTeamsPath"
            return $true
        }
        catch
        {
            Write-ADTLogEntry -Message "Failed to launch classic Teams: $($_.Exception.Message)" -Severity 2
        }
    }

    Write-ADTLogEntry -Message "Teams executable not found" -Severity 2
    return $false
}

function Start-OneDriveIfNeeded
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Step 6/7: Checking OneDrive status"
    Show-ADTInstallationProgress -StatusMessage "Configuring OneDrive... (Step 6 of 7)"

    # Check if OneDrive is already running
    $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($oneDriveProcess)
    {
        Write-ADTLogEntry -Message "OneDrive is already running (PID: $($oneDriveProcess.Id))"
        return $true
    }

    # OneDrive not running - launch it
    $oneDrivePaths = @(
        "${env:LOCALAPPDATA}\Microsoft\OneDrive\OneDrive.exe",
        "${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )

    foreach ($path in $oneDrivePaths)
    {
        if (Test-Path $path)
        {
            try
            {
                Start-Process -FilePath $path -ErrorAction Stop
                Write-ADTLogEntry -Message "OneDrive launched from: $path"
                return $true
            }
            catch
            {
                Write-ADTLogEntry -Message "Failed to launch OneDrive from ${path}: $($_.Exception.Message)" -Severity 2
            }
        }
    }

    Write-ADTLogEntry -Message "OneDrive executable not found" -Severity 2
    return $false
}

function Start-CompanyPortal
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Step 7/7: Launching Company Portal"
    Show-ADTInstallationProgress -StatusMessage "Opening app catalog... (Step 7 of 7)"

    # Try to launch Company Portal app directly first
    $companyPortalPaths = @(
        "${env:ProgramFiles}\WindowsApps\Microsoft.CompanyPortal_*\Microsoft.CompanyPortal.exe",
        "${env:ProgramFiles(x86)}\WindowsApps\Microsoft.CompanyPortal_*\Microsoft.CompanyPortal.exe"
    )

    foreach ($path in $companyPortalPaths)
    {
        $resolved = Get-Item -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved)
        {
            try
            {
                Start-Process -FilePath $resolved.FullName -ErrorAction Stop
                Write-ADTLogEntry -Message "Company Portal launched from: $($resolved.FullName)"
                return $true
            }
            catch
            {
                Write-ADTLogEntry -Message "Failed to launch Company Portal from $($resolved.FullName): $($_.Exception.Message)" -Severity 2
            }
        }
    }

    # Fallback: try protocol handler (may open Store if Company Portal not installed)
    try
    {
        Start-Process "companyportal:" -ErrorAction Stop
        Write-ADTLogEntry -Message "Company Portal launched via protocol handler"
        return $true
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to launch Company Portal via protocol handler: $($_.Exception.Message)" -Severity 2
    }

    # If both methods fail, just log and continue
    Write-ADTLogEntry -Message "Company Portal could not be launched - may not be installed yet" -Severity 2
    return $false
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param()

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message
    Show-ADTInstallationWelcome

    ## Show Progress Message
    Show-ADTInstallationProgress -StatusMessage "Starting first-run setup... (Step 1 of 7)"


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Create marker file to prevent re-running
    $markerPath = "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt"
    $markerDir = Split-Path $markerPath -Parent

    if (!(Test-Path $markerDir))
    {
        New-Item -Path $markerDir -ItemType Directory -Force | Out-Null
        Write-ADTLogEntry -Message "Created marker directory: $markerDir"
    }

    ## Step 2: Wait for Zscaler
    Wait-ZscalerReady

    ## Step 3: Update Defender
    Update-DefenderDefinitions

    ## Step 4: Outlook first launch with error recovery
    Start-OutlookFirstRun

    # Brief pause before next step
    Start-Sleep -Seconds 2

    ## Step 5: Teams
    Start-TeamsFirstRun

    # Brief pause before next step
    Start-Sleep -Seconds 2

    ## Step 6: OneDrive
    Start-OneDriveIfNeeded

    # Brief pause before next step
    Start-Sleep -Seconds 2

    ## Step 7: Company Portal
    Start-CompanyPortal


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Write marker file
    Set-Content -Path $markerPath -Value "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Force
    Write-ADTLogEntry -Message "First run setup completed - marker file created: $markerPath"

    ## Display completion message
    if ($adtSession.DeployMode -ne 'Silent')
    {
        $completionMessage = @"
Setup complete! Your device is ready to use.

You can now:
- Check your email in Outlook
- Chat with colleagues in Teams
- Access files in OneDrive
- Browse available apps in Company Portal

Welcome to Group1001!
"@
        Show-ADTInstallationPrompt -Message $completionMessage -ButtonRightText 'Get Started' -Icon Information -NoWait
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

    Show-ADTInstallationProgress -StatusMessage "Removing first-run marker..."

    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Remove marker file
    $markerPath = "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt"
    if (Test-Path $markerPath)
    {
        Remove-Item -Path $markerPath -Force -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Removed marker file: $markerPath"
    }

    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message "First-run marker removed successfully"
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param()

    # Repair = re-run the install
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
    Show-ADTInstallationPrompt -Message "Setup encountered an error. Please contact IT support if this continues.

Error details have been logged for troubleshooting." -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}
