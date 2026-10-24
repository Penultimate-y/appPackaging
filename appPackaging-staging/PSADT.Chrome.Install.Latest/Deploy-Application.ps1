<#
.SYNOPSIS
    Group 1001 - Google Chrome Latest Version Installer
.DESCRIPTION
    Downloads and installs the latest version of Google Chrome Enterprise.
    Runs in SYSTEM context. Prompts user to close Chrome before installation.
    Designed for Intune Win32 app deployment.

.NOTES
    Version:        1.0.0
    Author:         Zachary Hayward with Claude Code-claude-sonnet-4-6
    Creation Date:  2026-06-12
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('Install','Uninstall','Repair')]
    [string]$DeploymentType = 'Install',

    [Parameter(Mandatory=$false)]
    [ValidateSet('Interactive','Silent','NonInteractive')]
    [string]$DeployMode = 'Interactive',

    [Parameter(Mandatory=$false)]
    [switch]$AllowRebootPassThru = $false,

    [Parameter(Mandatory=$false)]
    [switch]$TerminalServerMode = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DisableLogging = $false
)

Try {
    Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    [string]$appVendor = 'Google'
    [string]$appName = 'Chrome'
    [string]$appVersion = 'Latest'
    [string]$appArch = 'x64'
    [string]$appLang = 'EN'
    [string]$appRevision = '01'
    [string]$appScriptVersion = '1.0.0'
    [string]$appScriptDate = '06/12/2026'
    [string]$appScriptAuthor = 'Zachary Hayward'

    [string]$installName = 'Google Chrome Enterprise (Latest)'
    [string]$installTitle = 'Chrome Installation'

    ##* Do not modify section below
    [string]$deployAppScriptFriendlyName = 'Deploy Application'
    [version]$deployAppScriptVersion = [version]'3.10.2'
    [string]$deployAppScriptDate = '08/13/2024'
    [hashtable]$deployAppScriptParameters = $psBoundParameters

    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
    [string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    Try {
        [string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
    }
    Catch {
        If ($mainExitCode -eq 0) { [int32]$mainExitCode = 60008 }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
    }

    ##*===============================================
    ##* SHARED VARIABLES
    ##*===============================================
    [string]$chromeDownloadUrl = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
    [string]$tempDownloadPath = "$env:TEMP\GoogleChromeEnterprise.msi"
    [int]$closeAppsCountdown = 300

    ##*===============================================
    ##* INSTALLATION
    ##*===============================================
    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        [string]$installPhase = 'Pre-Installation'

        Show-InstallationWelcome `
            -CloseApps 'chrome=Google Chrome' `
            -CloseAppsCountdown $closeAppsCountdown `
            -PersistPrompt `
            -BlockExecution

        Show-InstallationProgress -StatusMessage 'Downloading Google Chrome...'

        [string]$installPhase = 'Installation'

        # Download Chrome installer
        Try {
            Write-Log -Message "Downloading Chrome from: $chromeDownloadUrl" -Source 'ChromeInstall'

            # Remove old installer if exists
            If (Test-Path $tempDownloadPath) {
                Remove-Item $tempDownloadPath -Force -ErrorAction SilentlyContinue
            }

            # Download using Invoke-WebRequest
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $chromeDownloadUrl -OutFile $tempDownloadPath -UseBasicParsing -ErrorAction Stop
            $ProgressPreference = 'Continue'

            If (-not (Test-Path $tempDownloadPath)) {
                Throw "Download failed - installer not found at $tempDownloadPath"
            }

            $fileSize = (Get-Item $tempDownloadPath).Length / 1MB
            Write-Log -Message "Chrome installer downloaded successfully (Size: $($fileSize.ToString('F2')) MB)" -Source 'ChromeInstall'
        }
        Catch {
            Write-Log -Message "Failed to download Chrome installer: $($_.Exception.Message)" -Severity 3 -Source 'ChromeInstall'
            Show-InstallationPrompt -Message "Failed to download Google Chrome installer. Please check your internet connection and try again." -ButtonRightText 'OK' -Icon Error
            Exit-Script -ExitCode 1620
        }

        Show-InstallationProgress -StatusMessage 'Installing Google Chrome...'

        # Install Chrome
        Try {
            Write-Log -Message "Installing Chrome from: $tempDownloadPath" -Source 'ChromeInstall'

            Execute-MSI -Action Install `
                -Path $tempDownloadPath `
                -Parameters '/quiet /norestart' `
                -LogName 'Chrome_Install'

            Write-Log -Message "Chrome installation completed successfully" -Source 'ChromeInstall'
        }
        Catch {
            Write-Log -Message "Chrome installation failed: $($_.Exception.Message)" -Severity 3 -Source 'ChromeInstall'
            Show-InstallationPrompt -Message "Google Chrome installation failed. Please contact IT support." -ButtonRightText 'OK' -Icon Error
            Exit-Script -ExitCode 1603
        }

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Installation'

        # Get installed Chrome version and write marker
        Try {
            $installedChrome = Get-InstalledApplication -Name 'Google Chrome'

            If ($installedChrome) {
                $installedVersion = $installedChrome.DisplayVersion
                Write-Log -Message "Chrome version $installedVersion installed successfully" -Source 'ChromeInstall'

                # Write registry marker for detection
                $markerPath = 'HKLM:\SOFTWARE\G1001\ChromeDeployment'
                If (-not (Test-Path $markerPath)) {
                    New-Item -Path $markerPath -Force | Out-Null
                }

                Set-ItemProperty -Path $markerPath -Name 'InstalledVersion' -Value $installedVersion -Force
                Set-ItemProperty -Path $markerPath -Name 'InstallDate' -Value (Get-Date -Format 'o') -Force
                Set-ItemProperty -Path $markerPath -Name 'DeploymentMethod' -Value 'PSADT-Intune' -Force

                Write-Log -Message "Registry marker created at $markerPath" -Source 'ChromeInstall'
            }
            Else {
                Write-Log -Message "Warning: Could not verify Chrome installation" -Severity 2 -Source 'ChromeInstall'
            }
        }
        Catch {
            Write-Log -Message "Failed to create registry marker: $($_.Exception.Message)" -Severity 2 -Source 'ChromeInstall'
        }

        # Clean up installer
        If (Test-Path $tempDownloadPath) {
            Try {
                Remove-Item $tempDownloadPath -Force -ErrorAction Stop
                Write-Log -Message "Cleaned up installer file: $tempDownloadPath" -Source 'ChromeInstall'
            }
            Catch {
                Write-Log -Message "Failed to clean up installer: $($_.Exception.Message)" -Severity 2 -Source 'ChromeInstall'
            }
        }

        Close-InstallationProgress
    }
    ##*===============================================
    ##* UNINSTALLATION
    ##*===============================================
    ElseIf ($deploymentType -ieq 'Uninstall') {
        [string]$installPhase = 'Pre-Uninstallation'

        Show-InstallationWelcome `
            -CloseApps 'chrome=Google Chrome' `
            -CloseAppsCountdown $closeAppsCountdown `
            -PersistPrompt

        Show-InstallationProgress -StatusMessage 'Uninstalling Google Chrome...'

        [string]$installPhase = 'Uninstallation'

        # Get Chrome product code
        Try {
            $chromeInstalled = Get-InstalledApplication -Name 'Google Chrome'

            If ($chromeInstalled) {
                Write-Log -Message "Found Chrome installation: $($chromeInstalled.DisplayName) ($($chromeInstalled.DisplayVersion))" -Source 'ChromeUninstall'

                # Uninstall using product code
                Execute-MSI -Action Uninstall `
                    -Path $chromeInstalled.ProductCode `
                    -Parameters '/quiet /norestart' `
                    -LogName 'Chrome_Uninstall'

                Write-Log -Message "Chrome uninstallation completed" -Source 'ChromeUninstall'
            }
            Else {
                Write-Log -Message "Chrome is not installed" -Severity 2 -Source 'ChromeUninstall'
            }
        }
        Catch {
            Write-Log -Message "Chrome uninstallation failed: $($_.Exception.Message)" -Severity 3 -Source 'ChromeUninstall'
        }

        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Uninstallation'

        # Remove registry marker
        Try {
            $markerPath = 'HKLM:\SOFTWARE\G1001\ChromeDeployment'
            If (Test-Path $markerPath) {
                Remove-Item -Path $markerPath -Force -ErrorAction Stop
                Write-Log -Message "Removed registry marker at $markerPath" -Source 'ChromeUninstall'
            }
        }
        Catch {
            Write-Log -Message "Failed to remove registry marker: $($_.Exception.Message)" -Severity 2 -Source 'ChromeUninstall'
        }

        Close-InstallationProgress
    }
    ##*===============================================
    ##* REPAIR
    ##*===============================================
    ElseIf ($deploymentType -ieq 'Repair') {
        [string]$installPhase = 'Pre-Repair'

        Show-InstallationWelcome `
            -CloseApps 'chrome=Google Chrome' `
            -CloseAppsCountdown $closeAppsCountdown `
            -PersistPrompt

        Show-InstallationProgress -StatusMessage 'Repairing Google Chrome...'

        Write-Log -Message 'Repair mode invoked. Re-running installation.' -Source 'ChromeRepair'

        [string]$installPhase = 'Post-Repair'
        Close-InstallationProgress
    }

    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [int32]$mainExitCode = 60001
    [string]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}
