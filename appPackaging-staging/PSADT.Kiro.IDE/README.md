# Kiro IDE - PSADT v4.1.8 Win32 App

Automatically downloads and installs the latest version of Kiro IDE.

Built with **PSAppDeployToolkit v4.1.8**.

## Overview

- **Purpose**: Install/Update Kiro IDE to latest version
- **Install Location**: `%LOCALAPPDATA%\Programs\Kiro\`
- **Executable**: `Kiro.exe`
- **Always Latest**: Downloads the current latest version from https://download.kiro.dev/
- **PSADT Version**: 4.1.8

## Installation Details

The installer:
1. Downloads the latest Kiro IDE installer
2. Runs silent installation (`/S /allusers`)
3. Installs to user's LocalAppData
4. Detection script verifies `Kiro.exe` exists

## Packaging Instructions

### Create .intunewin Package

```powershell
.\IntuneWinAppUtil.exe `
    -c "C:\Path\To\PSADT.Kiro.IDE" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "C:\Path\To\Output" `
    -q
```

## Intune Configuration

### App Information
- **Name**: Kiro IDE (Latest)
- **Description**: Kiro IDE - Always installs latest version
- **Publisher**: Kiro
- **Category**: Developer Tools

### Program Settings

**Install command:**
```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

**Uninstall command:**
```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
```

**Install behavior:** User

**Device restart behavior:** No action required

### Requirements
- **Operating system architecture**: 64-bit
- **Minimum operating system**: Windows 10 1809 or later

### Detection Rules

**Rules format:** Use a custom detection script

**Script file:** Upload `Detect-KiroIDE.ps1`

**Run script as 32-bit process:** No

**Enforce script signature check:** No

### Dependencies
None

### Supersedence
- This app can supersede older versions since it always installs latest
- Configure supersedence if replacing an older Kiro IDE deployment

## Detection Logic

The detection script checks for:
- File exists: `%LOCALAPPDATA%\Programs\Kiro\Kiro.exe`
- Reads file version info
- Returns version to Intune

**Note:** Since we always download the latest version, the detection doesn't check for a specific version number - it only verifies Kiro IDE is present.

## Logging

PSADT v4 logs:
```
C:\Windows\Logs\Software\Kiro IDE (Latest)_Latest_<deployment-type>_<timestamp>.log
```

## Update Strategy

### Always-Latest Behavior
- Every time this app runs, it downloads and installs the current latest Kiro IDE
- If a newer version is available, it will be installed
- If current version is latest, it reinstalls the same version (safe operation)

### Forcing Updates
To force update all devices to latest:
1. No changes needed to the package
2. Simply re-assign or trigger a sync in Intune
3. The app will download and install whatever is currently latest

### Version Tracking
- Intune shows "Latest" as the version
- Actual installed version is logged in PSADT logs
- Detection script outputs actual version for reference

## Troubleshooting

### Installation Fails
- Check PSADT log: `C:\Windows\Logs\Software\Kiro IDE (Latest)_Latest_Install_*.log`
- Verify internet connectivity
- Check if https://download.kiro.dev/ is accessible
- Review firewall/proxy settings

### Detection Fails
- Verify `%LOCALAPPDATA%\Programs\Kiro\Kiro.exe` exists
- Run detection script manually to test
- Check file permissions

### Wrong Version Installed
- Kiro IDE always downloads latest from their server
- If version seems old, check what's currently available at https://kiro.dev/ide/
- May need to wait for Kiro to publish newer version

## Support

Contact: DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version History

- **v1.0.0** (2026-06-20) - Initial release
  - Always-latest installer
  - PSADT v4.1.8
  - Automatic version detection
  - User-context installation
