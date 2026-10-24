# Windows Update ESP - PSADT v4.1.8 Win32 App

This package installs Windows Updates during the Autopilot Enrollment Status Page (ESP) in pre-provisioning mode with SHI (Shared Device). This minimizes the updates required when the user kicks off user enrollment after reseal.

Built with **PSAppDeployToolkit v4.1.8**.

## Overview

- **Purpose**: Install Windows Updates during device provisioning phase
- **Deployment Model**: Autopilot pre-provisioning (White Glove)
- **Target Phase**: Device ESP (before user assignment)
- **Benefits**: Reduces user-side enrollment time by completing updates during technician provisioning
- **PSADT Version**: 4.1.8

## Files Included

1. **Invoke-AppDeployToolkit.ps1** - Main PSADT v4 deployment script
2. **Invoke-AppDeployToolkit.exe** - PSADT v4 executable wrapper
3. **Detect-WindowsUpdateESP.ps1** - Detection script for Intune
4. **PSAppDeployToolkit/** - PSADT v4.1.8 module folder
5. **Config/**, **Assets/**, **Strings/** - PSADT v4 configuration folders
6. **README.md** - This file

## Packaging Instructions

### Step 1: Prepare the Content
The folder is already structured correctly for PSADT v4. No additional preparation needed.

### Step 2: Create the .intunewin Package
Download the [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool) if not already installed.

```powershell
# Example command
.\IntuneWinAppUtil.exe `
    -c "C:\Path\To\PSADT.WindowsUpdate.ESP" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "C:\Path\To\Output" `
    -q
```

This creates `Invoke-AppDeployToolkit.intunewin`

### Step 3: Upload to Intune

1. Navigate to **Microsoft Intune admin center** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

### Step 4: Configure App Information

- **Name**: Windows Update - ESP Pre-provisioning
- **Description**: Installs Windows Updates during Autopilot device provisioning phase using PSADT v4.1.8 to minimize user-side update time
- **Publisher**: IT Department / Group 1001
- **Category**: Device Configuration (or your preferred category)

### Step 5: Configure Program Settings

**Install command:**
```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

**Uninstall command:**
```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
```

**Install behavior:** System

**Device restart behavior:** 
- **Recommended**: `Determine behavior based on return codes` (allows Intune to handle reboot; PSADT v4 returns 3010 automatically)
- Alternative: `App install may force a device restart` (if you want to force immediate reboot)

**Return codes:**
- Add custom return code if needed:
  - Code: `3010`
  - Code type: `Soft reboot`

### Step 6: Configure Requirements

- **Operating system architecture**: 64-bit
- **Minimum operating system**: Windows 10 1809 or later (recommend Windows 10 21H2+ or Windows 11)
- **Disk space required**: 100 MB (minimum)
- **Physical memory required**: Not required
- **Processor requirement**: Not required

### Step 7: Configure Detection Rules

**Rules format:** Use a custom detection script

**Script file:** Upload `Detect-WindowsUpdateESP.ps1`

**Run script as 32-bit process:** No

**Enforce script signature check:** No

### Step 8: Configure Dependencies

None required (the install script will install PSWindowsUpdate module automatically)

### Step 9: Configure Supersedence

None required for initial deployment

### Step 10: Configure Assignments

**Device Groups:**
- Assign to device group(s) used for Autopilot pre-provisioning
- **Required** assignment type (must install during ESP)

**Assignment filters (optional):**
- You may want to create a filter for devices in provisioning phase

## Deployment Strategy

### For Pre-Provisioning (White Glove) with SHI

1. **Assign to Device ESP Group**
   - Create a device group for your pre-provisioning devices
   - Assign this app as **Required** to that group

2. **Configure Enrollment Status Page**
   - In Intune → **Devices** → **Enrollment** → **Windows enrollment** → **Enrollment Status Page**
   - Ensure you have a profile that:
     - Shows app and profile installation progress: **Yes**
     - Block device use until required apps are installed: **Selected apps** (include this app)
     - Allow users to reset device if installation error occurs: **Yes** (recommended)

3. **Autopilot Profile Configuration**
   - Ensure your Autopilot profile is set to:
     - **Deployment mode**: Self-deploying or Pre-provisioning
     - **Join to Azure AD as**: Azure AD joined
     - **Skip connectivity check**: No (needs internet for updates)

### Installation Timeline

During Pre-provisioning:
1. Technician starts White Glove provisioning
2. Device goes through ESP - Device Setup phase
3. This app runs and installs available Windows Updates
4. Device may reboot if required (handled by ESP and PSADT v4)
5. Technician completes provisioning and seals device

When User Enrolls:
1. User starts enrollment after reseal
2. User goes through ESP - Account Setup phase
3. Minimal or no Windows Updates required (already done in device phase)
4. Faster user experience

## Logging

PSADT v4 writes detailed logs to:
```
C:\Windows\Logs\Software\Windows Update - ESP Pre-provisioning_1.0_<deployment-type>_<timestamp>.log
```

Detection script logs to:
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdate-ESP-Detection.log
```

## Marker Files

The script creates tracking files at:
```
C:\ProgramData\WindowsUpdate-ESP\UpdatesInstalled.json
```

This JSON file contains:
- Install date/time
- Number of updates installed
- Reboot status
- List of installed updates

## Troubleshooting

### App Not Running During ESP
- Verify app is assigned as **Required** to device group
- Check ESP profile includes this app in blocking list
- Verify device is in the assigned group

### Updates Not Installing
- Check PSADT v4 log: `C:\Windows\Logs\Software\Windows Update - ESP Pre-provisioning_1.0_Install_*.log`
- Verify internet connectivity during provisioning
- Ensure Windows Update service is running
- Check if WSUS or Windows Update for Business policies are blocking

### Detection Failing
- Check detection log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdate-ESP-Detection.log`
- Verify marker file exists at `C:\ProgramData\WindowsUpdate-ESP\UpdatesInstalled.json`
- Ensure file timestamp is within 7 days

### Long Installation Time
- Windows Updates can take 30-60+ minutes depending on update size
- This is expected during initial provisioning
- Ensure ESP timeout is set appropriately (default 60 minutes may not be enough)
- Consider adjusting ESP timeout to 90-120 minutes in Enrollment Status Page settings

### PSADT v4 Specific Issues
- Verify PSAppDeployToolkit module version: Check `PSAppDeployToolkit\PSAppDeployToolkit.psd1` shows version 4.1.8
- Ensure the entire folder structure is packaged (not just the .exe)
- Check that `Invoke-AppDeployToolkit.exe` and `Invoke-AppDeployToolkit.ps1` are both present

## Best Practices

1. **Test in Pilot Group First**
   - Test with a small device group before rolling out broadly
   - Monitor installation times and success rates

2. **ESP Timeout Configuration**
   - Set ESP timeout to at least 90 minutes to accommodate large updates
   - Configure in: Enrollment Status Page profile → Settings

3. **Network Considerations**
   - Ensure reliable internet connectivity at provisioning location
   - Consider using wired connection for faster update downloads

4. **Maintenance**
   - Updates happen automatically each time a new device is provisioned
   - No ongoing maintenance required unless script needs updating
   - PSADT v4 can be updated independently by replacing the PSAppDeployToolkit folder

5. **Monitoring**
   - Monitor app installation reports in Intune
   - Review logs on failed devices
   - Track average installation times

## Update Scope

The script installs:
- **All available Windows Updates** from Microsoft Update
- Includes: Security updates, cumulative updates, quality updates
- Includes: Feature updates (if applicable)
- Does NOT include: Optional updates or drivers (unless critical)

To modify update scope, edit the `Get-WindowsUpdate` and `Install-WindowsUpdate` parameters in `Invoke-AppDeployToolkit.ps1`

## PSADT v4 Notes

This package uses **PSAppDeployToolkit v4.1.8** with the following key features:

- **Module-based architecture**: No more dot-sourcing - cleaner imports
- **ADT function prefix**: All functions use `*-ADT*` naming (e.g., `Show-ADTInstallationProgress`)
- **Session-based**: Uses `$adtSession` hashtable for configuration
- **Auto DeployMode**: Automatically detects ESP/OOBE and sets Silent mode
- **Better reboot handling**: Automatic 3010 exit code when reboots needed
- **Improved logging**: Structured logging with better organization

### Updating to a Newer PSADT Version

To update PSADT to a newer v4.x release:

1. Download the latest PSADT v4 from https://psappdeploytoolkit.com
2. Replace the `PSAppDeployToolkit` folder with the new version
3. Update version numbers in `Invoke-AppDeployToolkit.ps1` if needed
4. Test thoroughly before deploying

## Support

For issues or questions:
- Check PSADT v4 logs in `C:\Windows\Logs\Software\`
- Check detection logs in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`
- Review Intune app installation status
- Contact DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version History

- **v1.0.0** (2026-06-20) - Initial release
  - Windows Update installation during ESP
  - Pre-provisioning support with SHI
  - Detection script
  - Built on PSADT v4.1.8
  - Automatic reboot handling with 3010 exit code
