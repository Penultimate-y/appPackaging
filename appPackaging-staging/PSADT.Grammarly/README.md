# PSADT.Grammarly - Grammarly Desktop Intune Win32 App Package

PowerShell App Deployment Toolkit (PSADT) v4.1.8 package for deploying **Grammarly Desktop (Latest)** via Microsoft Intune.

---

## Package Overview

| Property | Value |
|---|---|
| **Application** | Grammarly Desktop |
| **Version** | Always-latest (dynamic download) |
| **Vendor** | Grammarly |
| **Architecture** | x86 |
| **Installer Type** | EXE (silent with SSO mode) |
| **Download URL** | `https://download-windows.grammarly.com/GrammarlyInstaller-perMachine.exe` |
| **Install Context** | System |
| **PSADT Version** | 4.1.8 |
| **Created By** | Allen Johnson with Claude Code-claude-sonnet-4-5 |
| **Created Date** | 2026-07-31 |

---

## Features

- ✅ **Dynamic installer download** - Always gets the latest version from Grammarly's official CDN
- ✅ **Enterprise SSO enrollment** - Automatically configures enterprise enrollment token
- ✅ **Process management** - Gracefully closes Grammarly processes before installation
- ✅ **Silent installation** - Fully unattended deployment with SSO mode enabled
- ✅ **Registry configuration** - Sets enterprise policies via `HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations`
- ✅ **Custom detection** - Verifies both executable and enterprise enrollment
- ✅ **User deferral** - Allows users to defer installation up to 3 times
- ✅ **Uninstall support** - Complete removal including registry cleanup

---

## Prerequisites

### Before Packaging:

1. **Update Enrollment Token** in `Invoke-AppDeployToolkit.ps1`:
   ```powershell
   $grammarlyEnrollmentToken = "YOUR-ORG-TOKEN-HERE"
   ```
   
   Replace `e70bf587-b51c-41db-b159-f1cb9f522ecb` with your organization's actual Grammarly enrollment token.

2. **Verify download URL** is still valid:
   ```powershell
   Invoke-WebRequest -Uri "https://download-windows.grammarly.com/GrammarlyInstaller-perMachine.exe" -Method Head
   ```

### Tools Required:

- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
- PowerShell 7.2+
- Intune admin access

---

## Packaging Instructions

### Step 1: Prepare Source Folder

Ensure the PSADT.Grammarly folder contains:
```
PSADT.Grammarly/
├── Invoke-AppDeployToolkit.ps1    # Main deployment script
├── Invoke-AppDeployToolkit.exe    # PSADT launcher
├── Detect-Grammarly.ps1            # Intune detection script
├── PSAppDeployToolkit/             # PSADT framework
├── PSAppDeployToolkit.Extensions/  # PSADT extensions
├── Assets/                         # Icons and images
├── Config/                         # PSADT config files
├── Strings/                        # Localization files
├── SupportFiles/                   # Additional support files
└── README.md                       # This file
```

### Step 2: Create .intunewin Package

```powershell
# Navigate to the Win32 Content Prep Tool directory
cd "C:\Tools\IntuneWinAppUtil"

# Create the .intunewin package
.\IntuneWinAppUtil.exe `
    -c "C:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.Grammarly" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "C:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps" `
    -q
```

Output: `PSADT.Grammarly.intunewin`

---

## Intune Configuration

### Upload Win32 App

1. **Intune Admin Center** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**
2. **Select app package file** → Upload `PSADT.Grammarly.intunewin`

### App Information

| Field | Value |
|---|---|
| **Name** | Grammarly Desktop (Latest) |
| **Description** | Grammarly Desktop with enterprise SSO enrollment. Always installs the latest version from Grammarly's CDN. |
| **Publisher** | Grammarly |
| **App version** | Latest |
| **Category** | Productivity |
| **Show this as featured app in Company Portal** | Yes (optional) |
| **Information URL** | `https://support.grammarly.com/hc/en-us/articles/360041624472` |
| **Privacy URL** | `https://www.grammarly.com/privacy-policy` |
| **Developer** | Grammarly |
| **Owner** | DWX Team |
| **Notes** | Deployed via PSADT v4.1.8. Downloads latest installer dynamically. |

### Program

| Field | Value |
|---|---|
| **Install command** | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` |
| **Uninstall command** | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| **Install behavior** | System |
| **Device restart behavior** | Determine behavior based on return codes |
| **Return codes** | (Use defaults: 0 = Success, 1707 = Success, 3010 = Soft reboot, 1641 = Hard reboot, 1618 = Retry) |

### Requirements

| Field | Value |
|---|---|
| **Operating system architecture** | 64-bit, 32-bit |
| **Minimum operating system** | Windows 10 1607 |
| **Disk space required (MB)** | 250 |
| **Physical memory required (MB)** | 100 |
| **Minimum number of logical processors required** | 1 |
| **Minimum CPU speed required (MHz)** | 1000 |

### Detection Rules

**Rule type:** Use a custom detection script

**Script file:** `Detect-Grammarly.ps1`

**Run script as 32-bit process on 64-bit clients:** No

**Enforce script signature check:** No

The detection script checks:
1. Executable exists: `C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe`
2. Enrollment token exists in: `HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations`

### Dependencies

None required.

### Supersedence

Configure if replacing an older Grammarly deployment method.

---

## Assignment

### Recommended Assignment:

| Group Type | Intent | Notification |
|---|---|---|
| **Available** | All Users or targeted group | Show all toast notifications |
| **Required** | Pilot group first, then production | Show all toast notifications |

### Pilot Testing:

1. Assign as **Available** to a pilot group (10-20 users)
2. Install from Company Portal and verify:
   - Application installs successfully
   - Enterprise enrollment is configured
   - Application launches and connects to your Grammarly organization
3. After successful pilot, assign as **Required** to broader audience

---

## Post-Deployment Verification

### On a Test Device:

#### 1. Check Executable
```powershell
Test-Path "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe"
```
Expected: `True`

#### 2. Check Registry Enrollment
```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations" -Name "GrammarlyEnrollmentToken"
```
Expected: Your organization's enrollment token

#### 3. Check Deployment Date
```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations" -Name "DeploymentDate"
```
Expected: Date stamp

#### 4. Launch Application
```powershell
Start-Process "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe"
```
Expected: Grammarly launches and shows organization enrollment

---

## Troubleshooting

### Installation Fails

1. **Check Intune logs:**
   - `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`
   - `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log`

2. **Check PSADT logs:**
   - Location defined in PSADT config (usually `C:\Windows\Logs\Software\`)
   - Look for `Grammarly Desktop_*_PSAppDeployToolkit_*.log`

3. **Common issues:**
   - **Download failure:** Check device has internet access and can reach `https://download-windows.grammarly.com`
   - **Installation hangs:** Verify Grammarly processes are being closed before install
   - **Detection fails:** Run `Detect-Grammarly.ps1` manually to see specific failure

### Enrollment Not Working

1. **Verify token:**
   ```powershell
   Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations" -Name "GrammarlyEnrollmentToken"
   ```

2. **Re-run enrollment configuration:**
   - Uninstall Grammarly
   - Verify registry is clean
   - Reinstall via Intune

3. **Contact Grammarly support** if enrollment token is invalid

### Users Can't Defer

If deferral isn't working:
- Check `Invoke-AppDeployToolkit.ps1` line ~130:
  ```powershell
  AllowDefer = $true
  DeferTimes = 3
  ```
- Increase `DeferTimes` if needed

---

## Maintenance

### Updating Enrollment Token

1. Edit `Invoke-AppDeployToolkit.ps1`
2. Update line:
   ```powershell
   $grammarlyEnrollmentToken = "NEW-TOKEN-HERE"
   ```
3. Re-package and re-upload to Intune
4. **No need to change version** - detection script will trigger reinstall

### Forcing Reinstall

If you need to force a reinstall on devices that already have Grammarly:
1. Change `AppRevision` in `Invoke-AppDeployToolkit.ps1` (e.g., `'01'` → `'02'`)
2. Re-package and upload
3. Intune will detect the package change and reinstall

---

## Support

| Category | Contact |
|---|---|
| **PSADT Package** | Allen Johnson (DWX Team) |
| **Intune Deployment** | Kunle Ayegbusi (DWX Team) |
| **Grammarly Application** | Grammarly Enterprise Support |

---

## Change Log

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-07-31 | Initial PSADT package creation with dynamic download and enterprise enrollment |

---

## Related Documentation

- [Grammarly Enterprise Setup Guide](https://support.grammarly.com/hc/en-us/articles/360041624472)
- [PSADT Documentation](https://psappdeploytoolkit.com)
- [Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
