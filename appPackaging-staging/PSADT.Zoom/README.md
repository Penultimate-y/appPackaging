# Zoom - PSADT Deployment Package

## Overview
PSADT package for deploying Zoom via Intune Win32 app deployment.

**Always-Latest Deployment:** This package automatically downloads the latest Zoom MSI installer from Zoom's CDN during deployment, ensuring devices always receive the current version without manual package updates.

This package installs the latest Zoom with comprehensive enterprise configuration including:
- Auto-update settings configured for silent background updates
- SSO authentication enforced for Group1001
- Disabled social login (Google, Facebook, Apple, Email, Microsoft)
- User self-registration disabled
- Required sign-in to join meetings and webinars
- Outlook integration enabled

## Prerequisites

### System Requirements
- **Operating System**: Windows 10 1809 or later (Windows 11 supported)
- **Architecture**: 64-bit (x64)
- **Disk Space**: 500MB minimum free space
- **Administrator Rights**: Required (SYSTEM context for Intune)
- **Network**: Internet access for Zoom installation

### Dependencies
- **Internet connectivity** (required for automatic installer download)
- No additional PowerShell modules or pre-installed software required
- The package is self-contained and will download the Zoom installer automatically

## Installation Method

### Installer Source (Always-Latest)
This package uses an **always-latest** deployment model:
- **No manual installer placement required** - the script automatically downloads the latest Zoom MSI from `https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64`
- **Optional caching** - if you place a Zoom MSI in the `Files\` subdirectory, the script will use that instead of downloading (useful for air-gapped environments or testing specific versions)
- The download happens at deployment time, ensuring each installation gets the current Zoom version

### Installation Process
The script performs the following actions:

1. **Pre-Installation**
   - Checks for running Zoom processes and closes them
   - Shows welcome message with deferral options (3 allowed)
   - Verifies disk space requirements

2. **Download (Always-Latest)**
   - Checks `Files\` directory for cached Zoom MSI installer
   - If not found, downloads latest Zoom x64 MSI from Zoom CDN
   - Verifies download completed successfully

3. **Installation**
   - Validates no newer version is already installed
   - Executes MSI installation with:
     - `/quiet /qn` - Silent installation (no UI)
     - `/norestart` - No automatic restart
     - `AllowDowngrade=1` - Allows downgrading to older versions
     - `/log` - Logs to Intune Management Extension log folder
   - Applies ZConfig settings via command-line parameters
   - Applies ZRecommend settings via command-line parameters

3. **Post-Installation**
   - Validates installation via registry and file system
   - Configures additional registry settings for:
     - Auto-update frequency and channel
     - Login/authentication restrictions
     - User experience preferences
   - Creates desktop shortcut for all users
   - Starts Zoom to ensure proper initialization

### ZConfig Settings Applied

| Setting | Value | Description |
|---------|-------|-------------|
| AU2_EnableAutoUpdate | true | Enable automatic updates |
| AU2_SetUpdateChannel | 1 | Stable channel |
| AU2_EnableShowZoomUpdates | true | Show update notifications |
| AU2_EnableUpdateSuccessNotification | true | Show update success notifications |
| AU2_EnableManualUpdate | true | Enable manual update option |
| AU2_InstallAtIdleTime | true | Install updates at idle time |
| AU2_SafeUpgradePeriod | 1800-0400 | Update window: 6 PM to 4 AM |
| nogoogle | 1 | Disable Google login |
| nofacebook | 1 | Disable Facebook login |
| DisableLoginWithMicrosoft | 1 | Disable Microsoft login |
| EnableAppleLogin | 0 | Disable Apple login |
| DisableLoginWithEmail | 1 | Disable email login |
| DisableUserSignUp | 1 | Disable user self-registration |
| AutoSSOLogin | 1 | Enable automatic SSO login |
| ForceSSOUrl | Group1001 | Force SSO to Group1001 |
| EnableNewWebView2SSO | 1 | Enable WebView2 for SSO |
| EnableEmbedBrowserForSSO | 1 | Enable embedded browser for SSO |
| EnforceSignInToJoin | 1 | Require sign-in to join meetings |
| EnforceAppSignInToJoin | 1 | Require app sign-in to join |
| EnforceSignInToJoinForWebinar | 1 | Require sign-in for webinars |

### ZRecommend Settings Applied

| Setting | Value | Description |
|---------|-------|-------------|
| AutoStartAfterReboot | 1 | Auto-start Zoom after reboot |
| ShowZoomWinWhenSharing | 1 | Show Zoom window when sharing |
| PresentToRoomOption | 0 | Default presentation option |
| IntegrateZoomWithOutlook | 1 | Integrate with Outlook calendar |
| EnableRemindMeetingTime | 0 | Disable meeting time reminders |

## Deployment Commands

**Install:**
```powershell
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

**Uninstall:**
```powershell
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
```

**Repair:**
```powershell
Invoke-AppDeployToolkit.exe -DeploymentType Repair -DeployMode Silent
```

## Detection

Uses `Detect-Zoom.ps1` - checks for Zoom installation via:

1. **Registry Detection** - Checks uninstall keys for Zoom entry
2. **File Detection** - Checks for `Zoom.exe` in common installation paths
3. **Configuration Key Detection** - Checks for Zoom registry configuration

Returns:
- Exit 0 + version output if installed
- Exit 1 if not installed

## Installation Parameters

### Silent Installation Command Line
```cmd
msiexec /i "ZoomSetup64.msi" /quiet /qn /norestart AllowDowngrade=1 /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomInstall.log" ZConfig="AU2_EnableAutoUpdate=true;AU2_SetUpdateChannel=1;AU2_EnableShowZoomUpdates=true;AU2_EnableUpdateSuccessNotification=true;AU2_EnableManualUpdate=true;AU2_InstallAtIdleTime=true;AU2_SafeUpgradePeriod=1800-0400;nogoogle=1;nofacebook=1;DisableLoginWithMicrosoft=1;EnableAppleLogin=0;DisableLoginWithEmail=1;DisableUserSignUp=1;AutoSSOLogin=1;ForceSSOUrl=Group1001;EnableNewWebView2SSO=1;EnableEmbedBrowserForSSO=1;EnforceSignInToJoin=1;EnforceAppSignInToJoin=1;EnforceSignInToJoinForWebinar=1;EnforceAppSignInToJoinForWebinar=1" ZRecommend="AutoStartAfterReboot=1;ShowZoomWinWhenSharing=1;PresentToRoomOption=0;IntegrateZoomWithOutlook=1;EnableRemindMeetingTime=0"
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Installation completed successfully |
| 3010 | Installation completed successfully - reboot required |
| 1603 | Fatal error during installation |
| 1641 | Installation completed successfully - restart initiated |
| 1605 | Product is not installed (uninstall only) |
| 1614 | Product is uninstalled by another method |

## Packaging for Intune

### Create the Win32 .intunewin Package

1. **Prerequisites:**
   - Download Microsoft Win32 Content Prep Tool: `IntuneWinAppUtil.exe`
   - **No manual installer placement required** - the package downloads Zoom automatically
   - Verify package structure:
     ```
     PSADT.Zoom\
     ├── Assets\ (AppIcon.png, Banner.Classic.png)
     ├── Config\ (config.psd1)
     ├── Files\ (optional: pre-cache Zoom MSI here for offline deployments)
     ├── Strings\
     ├── SupportFiles\
     ├── Detect-Zoom.ps1
     ├── Invoke-AppDeployToolkit.exe
     ├── Invoke-AppDeployToolkit.ps1
     ├── PSAppDeployToolkit\ (folder)
     ├── PSAppDeployToolkit.Extensions\ (folder)
     └── README.md
     ```

2. **Package the PSADT folder:**
   ```powershell
   .\IntuneWinAppUtil.exe -c "C:\path\to\PSADT.Zoom" -s "Invoke-AppDeployToolkit.exe" -o "C:\path\to\output"
   ```

3. **Upload to Intune:**
   - In Intune portal: Apps > Windows > Add > Windows app (Win32)
   - Upload the generated `.intunewin` file
   - Configure install/uninstall commands and detection rules

## Intune Configuration

### App Information
- **Name**: Zoom (Always-Latest)
- **Description**: Zoom Video Conferencing Client - Enterprise Configured (Always-Latest)
- **Publisher**: Zoom Video Communications, Inc.
- **Category**: Communications
- **Version**: Always-Latest (auto-downloads current version at deployment time)

### Program Settings

**Install command:**
```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

**Uninstall command:**
```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
```

**Install behavior**: System (runs in SYSTEM context)

> **Note:** This package must run in **System** context. It requires administrator rights (`RequireAdmin = $true`) and performs machine-wide operations: installs to `C:\Program Files\Zoom`, writes to `HKLM:\SOFTWARE\WOW6432Node\Zoom`, and logs to the Intune Management Extension folder. Running it in user context will fail with access-denied errors.

**Device restart behavior**: No action required (installer handles restart)

### Requirements
- **Operating system architecture**: 64-bit
- **Minimum operating system**: Windows 10 1809

### Detection Rules
- **Rule type**: Custom detection script
- **Script file**: Upload `Detect-Zoom.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

### Dependencies
- **Internet connectivity required** during deployment for automatic installer download
- No additional dependencies

### Supersedence
This package supersedes older Zoom versions. Configure supersedence rules in Intune to automatically upgrade existing Zoom installations.

## Testing

Before deploying to production:

1. **Test on non-production device in Interactive mode:**
   ```powershell
   .\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
   ```

2. **Verify detection script works:**
   ```powershell
   .\Detect-Zoom.ps1
   ```
   - Should return exit code 0 if installed
   - Should return exit code 1 if not installed

3. **Test uninstall:**
   ```powershell
   .\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
   ```

4. **Check log files:**
   - Installation log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomInstall.log`
   - PSADT logs: `C:\Windows\Logs\Software\`

## Uninstallation

The uninstall process:
1. Closes any running Zoom processes
2. Uninstalls Zoom via MSI
3. Removes desktop shortcuts
4. Cleans up Zoom registry keys
5. Removes installation directory (`C:\Program Files\Zoom`)
6. Cleans up log files

## Configuration Notes

### Modifying ZConfig Settings
To customize Zoom configuration, modify the `$zConfig` and `$zRecommend` variables in the `Install-ADTDeployment` function of `Invoke-AppDeployToolkit.ps1`:

```powershell
$zConfig = "AU2_EnableAutoUpdate=true;AU2_SetUpdateChannel=1;..."
$zRecommend = "AutoStartAfterReboot=1;ShowZoomWinWhenSharing=1;..."
```

### Changing Installation Directory
The script installs to `C:\Program Files\Zoom` by default. To change:

1. Modify `$installDir` in `Invoke-AppDeployToolkit.ps1`
2. Update detection paths in `Detect-Zoom.ps1`
3. Update uninstall registry cleanup paths

### Process Closure
The script automatically closes `Zoom` and `ZoomCmd` processes before installation. To modify:

```powershell
AppProcessesToClose = @('Zoom', 'ZoomCmd')
```

## Troubleshooting

### Installation Fails with 1603 Error
**Common causes:**
- Another Zoom installation is in progress
- Insufficient permissions
- Conflicting processes

**Solution:**
1. Check log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomInstall.log`
2. Restart device and retry
3. Verify no Zoom processes are running

### Installation Reports Not Installed
**Possible causes:**
- Installation failed silently
- Registry keys not created properly
- Detection paths need adjustment

**Solution:**
1. Check installation log
2. Verify `C:\Program Files\Zoom\bin\Zoom.exe` exists
3. Check registry: `HKLM:\SOFTWARE\WOW6432Node\Zoom`

### Detection Script Fails
**Common issues:**
- Script execution policy blocking
- File path incorrect

**Solution:**
1. Run detection script manually to test
2. Verify file permissions
3. Check script output for specific errors

### Uninstall Fails
**Solution:**
1. Close Zoom manually before uninstall
2. Check uninstall log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomUninstall.log`
3. Try uninstall in Interactive mode first

## Logging

### Log Files

| Location | Purpose |
|----------|---------|
| `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomInstall.log` | MSI installation log |
| `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ZoomUninstall.log` | MSI uninstallation log |
| `C:\Windows\Logs\Software\` | PSADT default logs |

### Log Format
Logs include timestamped entries with severity levels (1=Info, 2=Warning, 3=Error).

## Related Resources

- [Zoom Admin Help Center](https://admin.zoom.us/)
- [Zoom MSI Deployment Guide](https://support.zoom.us/hc/en-us/articles/201362163)
- [PSAppDeployToolkit Documentation](https://psappdeploytoolkit.com/)

## Support

Contact: DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.1 | 2026-09-17 | Updated to always-latest deployment model |
| | | - Auto-downloads latest Zoom MSI from Zoom CDN |
| | | - Removed requirement for manual installer placement |
| | | - Added support for optional installer caching in Files\ |
| | | - Fixed missing Assets (AppIcon.png, Banner.Classic.png) |
| | | - Fixed missing Config (config.psd1) |
| 1.0.0 | 2026-09-17 | Initial release (required manual Zoom MSI placement) |
| | | - Enterprise-configured ZConfig/ZRecommend settings |
| | | - Comprehensive registry configuration |
| | | - SSO enforcement for Group1001 |
| | | - Social login disabled |
| | | - User self-registration disabled |

## License

This package is for internal use by Group 1001. Zoom licensing is managed separately.