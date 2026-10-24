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
    AppVendor = 'Zoom'
    AppName = 'Zoom'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0, 3010)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('Zoom', 'ZoomCmd')
    AppScriptVersion = '1.0.1'
    AppScriptDate = '2026-09-17'
    AppScriptAuthor = 'Allen Johnson with Claude Code-claude-sonnet-4-5'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Zoom'
    InstallTitle = 'Zoom Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

## Zoom-specific configuration
## Download URL for latest Zoom x64 MSI (always-latest deployment)
$zoomDownloadUrl = "https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64"

function Uninstall-ExistingZoom
{
    <#
    .SYNOPSIS
        Removes any existing machine-wide Zoom installation via its MSI ProductCode.

    .DESCRIPTION
        Shared by both the Install and Uninstall deployment paths. The install path
        calls this BEFORE running the fresh MSI so that always-latest deployments do a
        clean remove-then-install instead of an in-place msiexec /i reconfigure over the
        already-registered product. Reconfiguring the installed product is what produced
        the "MSI reconfiguration status 1603" failures on devices that already had Zoom.

        Returns $true when Zoom is gone after the call (either it was uninstalled, or it
        was not present to begin with); returns $false when an uninstall was attempted
        but did not succeed.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
    )

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $zoomApp = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -match 'Zoom' } |
               Select-Object -First 1

    if (-not $zoomApp)
    {
        Write-ADTLogEntry -Message "No existing Zoom installation found. Nothing to uninstall." -Severity 1
        return $true
    }

    $displayName = $zoomApp.DisplayName
    $displayVersion = $zoomApp.DisplayVersion
    $uninstallString = $zoomApp.UninstallString
    Write-ADTLogEntry -Message "Found existing Zoom installation: $displayName $displayVersion" -Severity 1

    ## Resolve the MSI ProductCode. For MSI products the uninstall key name IS the
    ## ProductCode GUID, which is more reliable than parsing the UninstallString.
    $msiProductCode = $null
    if ($zoomApp.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$')
    {
        $msiProductCode = $zoomApp.PSChildName
    }
    elseif ($uninstallString -and ($uninstallString -match '(\{[0-9A-Fa-f\-]{36}\})'))
    {
        $msiProductCode = $matches[1]
    }

    if ($msiProductCode)
    {
        Write-ADTLogEntry -Message "Uninstalling existing Zoom (ProductCode $msiProductCode)..." -Severity 1

        $uninstallResult = Start-ADTProcess -FilePath "msiexec.exe" `
            -ArgumentList "/X $msiProductCode /quiet /qn /norestart /log `"C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomUninstall.log`"" `
            -PassThru -IgnoreExitCodes '0,3010,1605,1614,1641'

        Write-ADTLogEntry -Message "Uninstall completed with exit code: $($uninstallResult.ExitCode)" -Severity 1

        ## 0 = success, 3010/1641 = success + reboot, 1605 = not installed,
        ## 1614 = already removed by another method. All mean "Zoom is now gone".
        switch ($uninstallResult.ExitCode)
        {
            0     { Write-ADTLogEntry -Message "Existing Zoom uninstalled successfully." -Severity 1; return $true }
            1605  { Write-ADTLogEntry -Message "Zoom product was not installed (1605)." -Severity 2; return $true }
            1614  { Write-ADTLogEntry -Message "Zoom was uninstalled by another method (1614)." -Severity 2; return $true }
            1641  { Write-ADTLogEntry -Message "Existing Zoom uninstalled - reboot required (1641)." -Severity 2; return $true }
            3010  { Write-ADTLogEntry -Message "Existing Zoom uninstalled - reboot required (3010)." -Severity 2; return $true }
            default
            {
                Write-ADTLogEntry -Message "Uninstall of existing Zoom returned unexpected exit code: $($uninstallResult.ExitCode)" -Severity 3
                return $false
            }
        }
    }

    ## Non-MSI uninstall: fall back to the registered uninstaller executable silently.
    if ($uninstallString)
    {
        Write-ADTLogEntry -Message "No MSI ProductCode; attempting registered uninstaller directly." -Severity 2
        try
        {
            $uninstallPath = $uninstallString -replace '"', ''
            if (Test-Path $uninstallPath)
            {
                $uninstallResult = Start-ADTProcess -FilePath $uninstallPath -ArgumentList "/S" `
                    -PassThru -IgnoreExitCodes '0,3010'
                Write-ADTLogEntry -Message "Uninstaller completed with exit code: $($uninstallResult.ExitCode)" -Severity 1
                if ($uninstallResult.ExitCode -in 0, 3010) { return $true }
                return $false
            }

            Write-ADTLogEntry -Message "Uninstaller not found at: $uninstallPath" -Severity 3
            return $false
        }
        catch
        {
            Write-ADTLogEntry -Message "Error running Zoom uninstaller: $($_.Exception.Message)" -Severity 3
            return $false
        }
    }

    Write-ADTLogEntry -Message "Existing Zoom found but no usable uninstall method (no ProductCode or UninstallString)." -Severity 3
    return $false
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
    ##
    ## Process closure is owned entirely by Show-ADTInstallationWelcome above. It either
    ## closed Zoom with the user's consent or force-closed it after the countdown once
    ## deferrals ran out. Do NOT add a Stop-Process -Force here: it would terminate Zoom
    ## even when the user chose to defer, defeating the in-meeting deferral prompt and
    ## potentially dropping someone out of a live meeting.
    Write-ADTLogEntry -Message "Process closure handled by Show-ADTInstallationWelcome; no force termination performed." -Severity 1

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

    ## Install Zoom
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Zoom Installation" -Severity 1
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Target: Zoom $($adtSession.AppVersion)" -Severity 1

    ## Install directory - declared at function scope so Post-Install can reference it.
    $installDir = "C:\Program Files\Zoom"

    ## Check if Zoom is already installed
    Write-ADTLogEntry -Message "Checking for existing Zoom installation..." -Severity 1
    $alreadyInstalled = $false

    ## Registry paths to check for Zoom installation
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $zoomApp = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
               Where-Object {
                   $_.DisplayName -match 'Zoom'
               } |
               Select-Object -First 1

    ## Uninstall-then-install model.
    ##
    ## This is an always-latest package: AppVersion is 'Latest', which can never be
    ## parsed into a [version], so the old "skip if installed version >= target" gate
    ## always threw and forced an in-place msiexec /i over the already-registered Zoom.
    ## msiexec then reconfigured the existing product instead of installing, which is
    ## what failed with "MSI reconfiguration status 1603" on devices that already had
    ## Zoom. The fix is to remove the version gate entirely and, when Zoom is present,
    ## uninstall it first so the subsequent MSI is always a clean fresh install.
    if ($zoomApp)
    {
        Write-ADTLogEntry -Message "Zoom $($zoomApp.DisplayVersion) is already installed. Removing it before installing the latest version." -Severity 1

        if (-not (Uninstall-ExistingZoom))
        {
            ## Do not proceed to install over a product we failed to remove - that would
            ## reproduce the reconfigure-1603 failure. Surface a clear error instead.
            throw "Failed to uninstall the existing Zoom installation; aborting before reinstall to avoid an in-place reconfigure (1603). See ZoomUninstall.log."
        }

        ## Give the MSI database a moment to settle after removal.
        Start-Sleep -Seconds 5
    }
    else
    {
        Write-ADTLogEntry -Message "Zoom not found in registry. Proceeding with a fresh installation." -Severity 1
    }

    ## Always install the freshly downloaded MSI (always-latest). $alreadyInstalled is
    ## retained only so the existing block structure stays intact; it is always false now.
    if (-not $alreadyInstalled)
    {
        ##================================================
        ## MARK: Download Zoom Installer (Always-Latest)
        ##================================================
        Write-ADTLogEntry -Message "======================================" -Severity 1
        Write-ADTLogEntry -Message "Downloading Zoom Installer (Always-Latest)" -Severity 1
        Write-ADTLogEntry -Message "======================================" -Severity 1

        ## Check if installer already exists in Files directory
        $installerMsi = $null
        $installerSearchPaths = @(
            (Join-Path $adtSession.DirFiles "Zoom*.msi"),
            (Join-Path $adtSession.DirSupportFiles "Zoom*.msi")
        )

        foreach ($searchPattern in $installerSearchPaths)
        {
            $found = Get-ChildItem -Path $searchPattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found)
            {
                $installerMsi = $found.FullName
                Write-ADTLogEntry -Message "Existing installer found: $installerMsi" -Severity 1
                Write-ADTLogEntry -Message "Using cached installer (delete to force fresh download)" -Severity 1
                break
            }
        }

        ## Download installer if not found locally
        if (-not $installerMsi)
        {
            Write-ADTLogEntry -Message "No cached installer found, downloading latest Zoom MSI" -Severity 1
            Show-ADTInstallationProgress -StatusMessage 'Downloading latest Zoom installer...'

            try
            {
                ## Download to temp directory
                $installerMsi = "$env:TEMP\ZoomInstallerFull.msi"

                Write-ADTLogEntry -Message "Downloading from: $zoomDownloadUrl" -Severity 1
                Invoke-WebRequest -Uri $zoomDownloadUrl -OutFile $installerMsi -UseBasicParsing

                Write-ADTLogEntry -Message "Download completed: $installerMsi" -Severity 1

                ## Verify download
                if (-not (Test-Path $installerMsi))
                {
                    throw "Failed to download Zoom installer"
                }

                $fileSize = (Get-Item $installerMsi).Length
                Write-ADTLogEntry -Message "Downloaded file size: $([math]::Round($fileSize / 1MB, 2)) MB" -Severity 1
            }
            catch
            {
                Write-ADTLogEntry -Message "Failed to download Zoom installer: $($_.Exception.Message)" -Severity 3
                throw "Installer download failed. Check network connectivity and URL: $zoomDownloadUrl"
            }
        }

        ## Verify disk space
        $systemDrive = $env:SystemDrive
        $disk = Get-PSDrive -Name $systemDrive.TrimEnd(':')
        $freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
        Write-ADTLogEntry -Message "Free space on $systemDrive : $freeSpaceGB GB" -Severity 1

        if ($freeSpaceGB -lt 1)
        {
            Write-ADTLogEntry -Message "WARNING: Low disk space. At least 1GB recommended, only $freeSpaceGB GB available" -Severity 2
        }

        ## Build installation arguments
        ## ZConfig and ZRecommend settings applied via command line parameters
        Write-ADTLogEntry -Message "Building Zoom silent install command..." -Severity 1

        ## ZConfig settings - comprehensive configuration for enterprise deployment
        $zConfig = "AU2_EnableAutoUpdate=true;AU2_SetUpdateChannel=1;AU2_EnableShowZoomUpdates=true;AU2_EnableUpdateSuccessNotification=true;AU2_EnableManualUpdate=true;AU2_InstallAtIdleTime=true;AU2_SafeUpgradePeriod=1800-0400;nogoogle=1;nofacebook=1;DisableLoginWithMicrosoft=1;EnableAppleLogin=0;DisableLoginWithEmail=1;DisableUserSignUp=1;AutoSSOLogin=1;ForceSSOUrl=Group1001;EnableNewWebView2SSO=1;EnableEmbedBrowserForSSO=1;EnforceSignInToJoin=1;EnforceAppSignInToJoin=1;EnforceSignInToJoinForWebinar=1;EnforceAppSignInToJoinForWebinar=1"

        ## ZRecommend settings - user experience recommendations
        $zRecommend = "AutoStartAfterReboot=1;ShowZoomWinWhenSharing=1;PresentToRoomOption=0;IntegrateZoomWithOutlook=1;EnableRemindMeetingTime=0"

        ## Build the full argument list
        ## /quiet /qn = silent installation (no UI)
        ## /norestart = do not restart automatically
        ## AllowDowngrade=1 = allow downgrading to older versions
        ## /log = specify log file location
        ## ZConfig = Zoom configuration parameters
        ## ZRecommend = Zoom recommendation parameters
        $installArgList = "/quiet /qn /norestart AllowDowngrade=1 /log `"C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomInstall.log`" ZConfig=`"$zConfig`" ZRecommend=`"$zRecommend`""

        Write-ADTLogEntry -Message "Full command line: msiexec /i `"$installerMsi`" $installArgList" -Severity 1
        Write-ADTLogEntry -Message "Installation will take approximately 2-5 minutes" -Severity 1

        ## Start-ADTProcess keeps the process tree under PSADT/IME control
        Write-ADTLogEntry -Message "======================================" -Severity 1
        Write-ADTLogEntry -Message "Starting Installation" -Severity 1
        Write-ADTLogEntry -Message "======================================" -Severity 1
        Write-ADTLogEntry -Message "Installer: $installerMsi" -Severity 1
        Write-ADTLogEntry -Message "Arguments: $installArgList" -Severity 1

        $installResult = Start-ADTProcess -FilePath "msiexec.exe" -ArgumentList "/i `"$installerMsi`" $installArgList" `
            -PassThru -IgnoreExitCodes '0,3010,1603'

        Write-ADTLogEntry -Message "Installation process completed with exit code: $($installResult.ExitCode)" -Severity 1

        ## Interpret exit codes
        switch ($installResult.ExitCode)
        {
            0
            {
                Write-ADTLogEntry -Message "Installation completed successfully" -Severity 1
            }
            3010
            {
                Write-ADTLogEntry -Message "Installation completed successfully - reboot required" -Severity 2
            }
            1603
            {
                Write-ADTLogEntry -Message "Fatal error during installation (Error 1603)" -Severity 3
                Write-ADTLogEntry -Message "Common causes: Another Zoom installation in progress, insufficient permissions, or conflicting processes" -Severity 3
                Write-ADTLogEntry -Message "Check log file: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomInstall.log" -Severity 3
                throw "Fatal installation error - see log file for details"
            }
            default
            {
                Write-ADTLogEntry -Message "Installation completed with exit code: $($installResult.ExitCode)" -Severity 2
            }
        }

        ## Post-Installation Validation
        Write-ADTLogEntry -Message "======================================" -Severity 1
        Write-ADTLogEntry -Message "Validating Installation" -Severity 1
        Write-ADTLogEntry -Message "======================================" -Severity 1

        ## Wait for registry to propagate
        Start-Sleep -Seconds 10

        ## Check registry for Zoom installation
        $installDetected = $false
        $detectionMethods = @()

        Write-ADTLogEntry -Message "Checking registry..." -Severity 1
        $zoomReg = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
                   Where-Object {
                       $_.DisplayName -match 'Zoom'
                   } |
                   Select-Object -First 1

        if ($zoomReg)
        {
            Write-ADTLogEntry -Message "Registry detection SUCCESS: $($zoomReg.DisplayName) version $($zoomReg.DisplayVersion)" -Severity 1
            $installDetected = $true
            $detectionMethods += "Registry"
        }

        ## Check installation directory
        Write-ADTLogEntry -Message "Checking installation files..." -Severity 1
        $zoomExePath = "$installDir\bin\Zoom.exe"

        if (Test-Path $zoomExePath)
        {
            Write-ADTLogEntry -Message "File detection SUCCESS: Zoom.exe found at $zoomExePath" -Severity 1
            $installDetected = $true
            $detectionMethods += "File"
        }

        ## Final Status
        Write-ADTLogEntry -Message "======================================" -Severity 1

        if ($installDetected)
        {
            Write-ADTLogEntry -Message "INSTALLATION SUCCESSFUL" -Severity 1
            Write-ADTLogEntry -Message "Detection methods: $($detectionMethods -join ', ')" -Severity 1
            Write-ADTLogEntry -Message "Exit code: $($installResult.ExitCode)" -Severity 1

            if ($installResult.ExitCode -eq 3010)
            {
                Write-ADTLogEntry -Message "REBOOT REQUIRED to complete installation" -Severity 2
            }
        }
        else
        {
            Write-ADTLogEntry -Message "INSTALLATION VERIFICATION FAILED" -Severity 3
            Write-ADTLogEntry -Message "Installation process completed but validation failed" -Severity 3
            Write-ADTLogEntry -Message "This may indicate:" -Severity 3
            Write-ADTLogEntry -Message "  - Installation failed silently" -Severity 3
            Write-ADTLogEntry -Message "  - Detection paths need adjustment" -Severity 3
            Write-ADTLogEntry -Message "  - Additional time needed for post-install tasks" -Severity 3
            throw "Installation verification failed"
        }
    }
    else
    {
        ## Do NOT call exit here - that would bypass Close-ADTSession and leave the
        ## PSADT session open. Fall through to Post-Install so the ZConfig/ZRecommend
        ## registry settings are still enforced on an existing installation.
        Write-ADTLogEntry -Message "Skipping MSI installation. Continuing to registry configuration." -Severity 1
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Installation tasks here>

    ## Configure additional registry settings if not present
    Write-ADTLogEntry -Message "======================================" -Severity 1
    Write-ADTLogEntry -Message "Configuring Additional Registry Settings" -Severity 1
    Write-ADTLogEntry -Message "======================================" -Severity 1

    $zoomRegPath = "HKLM:\SOFTWARE\WOW6432Node\Zoom"

    ## Create Zoom registry key if it doesn't exist
    if (-not (Test-Path $zoomRegPath))
    {
        Write-ADTLogEntry -Message "Creating Zoom registry key: $zoomRegPath" -Severity 1
        New-Item -Path $zoomRegPath -Force | Out-Null
    }

    ## Set Zoom configuration values
    Write-ADTLogEntry -Message "Configuring Zoom registry settings..." -Severity 1

    ## Auto Update Settings
    Set-ItemProperty -Path $zoomRegPath -Name "AU2_EnableAutoUpdate" -Value "true" -Type String
    Write-ADTLogEntry -Message "AU2_EnableAutoUpdate: true" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AU2_SetUpdateChannel" -Value "1" -Type String
    Write-ADTLogEntry -Message "AU2_SetUpdateChannel: 1 (Stable channel)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AU2_EnableShowZoomUpdates" -Value "true" -Type String
    Write-ADTLogEntry -Message "AU2_EnableShowZoomUpdates: true" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AU2_EnableUpdateSuccessNotification" -Value "true" -Type String
    Write-ADTLogEntry -Message "AU2_EnableUpdateSuccessNotification: true" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AU2_EnableManualUpdate" -Value "true" -Type String
    Write-ADTLogEntry -Message "AU2_EnableManualUpdate: true" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AU2_InstallAtIdleTime" -Value "true" -Type String
    Write-ADTLogEntry -Message "AU2_InstallAtIdleTime: true" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AU2_SafeUpgradePeriod" -Value "1800-0400" -Type String
    Write-ADTLogEntry -Message "AU2_SafeUpgradePeriod: 1800-0400 (6 PM to 4 AM)" -Severity 1

    ## Login/Authentication Settings
    Set-ItemProperty -Path $zoomRegPath -Name "nogoogle" -Value "1" -Type String
    Write-ADTLogEntry -Message "nogoogle: 1 (Disable Google login)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "nofacebook" -Value "1" -Type String
    Write-ADTLogEntry -Message "nofacebook: 1 (Disable Facebook login)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "DisableLoginWithMicrosoft" -Value "1" -Type String
    Write-ADTLogEntry -Message "DisableLoginWithMicrosoft: 1 (Disable Microsoft login)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnableAppleLogin" -Value "0" -Type String
    Write-ADTLogEntry -Message "EnableAppleLogin: 0 (Disable Apple login)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "DisableLoginWithEmail" -Value "1" -Type String
    Write-ADTLogEntry -Message "DisableLoginWithEmail: 1 (Disable email login)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "DisableUserSignUp" -Value "1" -Type String
    Write-ADTLogEntry -Message "DisableUserSignUp: 1 (Disable user self-registration)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "AutoSSOLogin" -Value "1" -Type String
    Write-ADTLogEntry -Message "AutoSSOLogin: 1 (Enable automatic SSO login)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "ForceSSOUrl" -Value "Group1001" -Type String
    Write-ADTLogEntry -Message "ForceSSOUrl: Group1001" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnableNewWebView2SSO" -Value "1" -Type String
    Write-ADTLogEntry -Message "EnableNewWebView2SSO: 1 (Enable WebView2 for SSO)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnableEmbedBrowserForSSO" -Value "1" -Type String
    Write-ADTLogEntry -Message "EnableEmbedBrowserForSSO: 1 (Enable embedded browser for SSO)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnforceSignInToJoin" -Value "1" -Type String
    Write-ADTLogEntry -Message "EnforceSignInToJoin: 1 (Require sign-in to join meetings)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnforceAppSignInToJoin" -Value "1" -Type String
    Write-ADTLogEntry -Message "EnforceAppSignInToJoin: 1 (Require app sign-in to join)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnforceSignInToJoinForWebinar" -Value "1" -Type String
    Write-ADTLogEntry -Message "EnforceSignInToJoinForWebinar: 1 (Require sign-in for webinars)" -Severity 1

    ## User Experience Settings
    Set-ItemProperty -Path $zoomRegPath -Name "AutoStartAfterReboot" -Value "1" -Type String
    Write-ADTLogEntry -Message "AutoStartAfterReboot: 1 (Auto-start after reboot)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "ShowZoomWinWhenSharing" -Value "1" -Type String
    Write-ADTLogEntry -Message "ShowZoomWinWhenSharing: 1 (Show Zoom window when sharing)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "PresentToRoomOption" -Value "0" -Type String
    Write-ADTLogEntry -Message "PresentToRoomOption: 0 (Default presentation option)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "IntegrateZoomWithOutlook" -Value "1" -Type String
    Write-ADTLogEntry -Message "IntegrateZoomWithOutlook: 1 (Integrate with Outlook)" -Severity 1

    Set-ItemProperty -Path $zoomRegPath -Name "EnableRemindMeetingTime" -Value "0" -Type String
    Write-ADTLogEntry -Message "EnableRemindMeetingTime: 0 (Disable meeting time reminders)" -Severity 1

    Write-ADTLogEntry -Message "Registry configuration completed" -Severity 1

    ## Create desktop shortcuts for all users
    Write-ADTLogEntry -Message "Creating desktop shortcuts..." -Severity 1
    $targetPath = "$installDir\bin\Zoom.exe"
    $shortcutPath = "$env:Public\Desktop\Zoom.lnk"

    if (Test-Path $targetPath)
    {
        try
        {
            $WScriptShell = New-Object -ComObject WScript.Shell
            $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $targetPath
            $shortcut.WorkingDirectory = "$installDir\bin"
            $shortcut.Description = "Zoom - Video Conferencing"
            $shortcut.Save()

            Write-ADTLogEntry -Message "Desktop shortcut created: $shortcutPath" -Severity 1
        }
        catch
        {
            Write-ADTLogEntry -Message "Failed to create desktop shortcut: $($_.Exception.Message)" -Severity 2
        }
    }
    else
    {
        Write-ADTLogEntry -Message "WARNING: Zoom.exe not found at $targetPath - shortcut not created" -Severity 2
    }

    ## Start Zoom to ensure proper initialization
    Write-ADTLogEntry -Message "Starting Zoom to initialize configuration..." -Severity 1
    try
    {
        Start-Process -FilePath $targetPath -ErrorAction Stop
        Write-ADTLogEntry -Message "Zoom started successfully" -Severity 1
        Start-Sleep -Seconds 5

        ## Verify Zoom is running
        $zoomRunning = Get-Process -Name "Zoom" -ErrorAction SilentlyContinue
        if ($zoomRunning)
        {
            Write-ADTLogEntry -Message "Zoom is running" -Severity 1
        }
        else
        {
            Write-ADTLogEntry -Message "Zoom process not detected after start attempt" -Severity 2
        }
    }
    catch
    {
        Write-ADTLogEntry -Message "Failed to start Zoom: $($_.Exception.Message)" -Severity 2
    }

    ## Display a message at the end of the install.
    if (!$adtSession.UseDefaultMsi)
    {
        Show-ADTInstallationPrompt -Message 'Zoom installation completed successfully.' -ButtonRightText 'OK' -NoWait
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

    ## Uninstall Zoom
    ##
    ## Process closure is handled by Show-ADTInstallationWelcome in Pre-Uninstall above,
    ## so no Stop-Process -Force is used here. The actual removal is delegated to the
    ## shared Uninstall-ExistingZoom helper, which the install path also uses, so both
    ## code paths remove Zoom exactly the same way.
    Write-ADTLogEntry -Message "Starting Zoom uninstallation" -Severity 1

    $uninstalled = Uninstall-ExistingZoom

    if (-not $uninstalled)
    {
        Write-ADTLogEntry -Message "Zoom uninstall did not complete cleanly - see ZoomUninstall.log. Continuing with cleanup." -Severity 3
    }

    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>

    ## Remove desktop shortcut
    Write-ADTLogEntry -Message "Removing desktop shortcut..." -Severity 1
    $shortcutPath = "$env:Public\Desktop\Zoom.lnk"
    if (Test-Path $shortcutPath)
    {
        Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Desktop shortcut removed" -Severity 1
    }

    ## Clean up Zoom registry keys
    Write-ADTLogEntry -Message "Cleaning up Zoom registry keys..." -Severity 1
    $zoomRegPath = "HKLM:\SOFTWARE\WOW6432Node\Zoom"
    if (Test-Path $zoomRegPath)
    {
        Remove-Item -Path $zoomRegPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Zoom registry key removed" -Severity 1
    }

    ## Clean up installation directory
    Write-ADTLogEntry -Message "Cleaning up installation directory..." -Severity 1
    $installDir = "C:\Program Files\Zoom"
    if (Test-Path $installDir)
    {
        Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Installation directory removed: $installDir" -Severity 1
    }

    ## Clean up log files
    Write-ADTLogEntry -Message "Cleaning up log files..." -Severity 1
    $logDir = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
    if (Test-Path $logDir)
    {
        Remove-Item -Path "$logDir\Zoom*.log" -Force -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Zoom log files cleaned up" -Severity 1
    }
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

    ## <Perform Pre-Repair tasks here>


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Write-ADTLogEntry -Message 'Repair is not implemented for Zoom. Use Uninstall followed by Install.' -Severity 2


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
    Close-ADTSession -ExitCode 60001
}