# Windows Update ESP (PSADT v4) - Deployment Checklist

Use this checklist when deploying the Windows Update ESP Win32 app for pre-provisioning using PSADT v4.1.8.

## Pre-Deployment

- [ ] Review and test PSADT v4 package in a test environment
- [ ] Download Microsoft Win32 Content Prep Tool
- [ ] Verify entire folder structure is present (PSAppDeployToolkit, Config, Assets, etc.)
- [ ] Verify PSADT v4.1.8 version in `PSAppDeployToolkit\PSAppDeployToolkit.psd1`

## Packaging

- [ ] Create .intunewin package using IntuneWinAppUtil.exe with `Invoke-AppDeployToolkit.exe` as setup file
- [ ] Verify package created successfully
- [ ] Keep a backup of source files

## Intune Configuration

### App Creation
- [ ] Create new Win32 app in Intune admin center
- [ ] Upload .intunewin file
- [ ] Set app name: "Windows Update - ESP Pre-provisioning"
- [ ] Add description mentioning PSADT v4.1.8
- [ ] Set publisher name

### Program Settings
- [ ] Install command: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`
- [ ] Uninstall command: `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`
- [ ] Install behavior: **System**
- [ ] Device restart behavior: **Determine behavior based on return codes**
- [ ] Verify return code 3010 is configured as "Soft reboot"

### Requirements
- [ ] OS architecture: **64-bit**
- [ ] Minimum OS: **Windows 10 1809** or later (recommend 21H2+)
- [ ] Disk space: **100 MB**

### Detection Rules
- [ ] Rules format: **Use a custom detection script**
- [ ] Upload `Detect-WindowsUpdateESP.ps1`
- [ ] Run script as 32-bit: **No**
- [ ] Enforce signature check: **No**

### Assignments
- [ ] Identify device group for pre-provisioning devices
- [ ] Assign app as **Required** to device group
- [ ] Verify group contains appropriate devices
- [ ] Apply assignment filters if needed

## Enrollment Status Page Configuration

- [ ] Navigate to: Devices → Enrollment → Windows enrollment → Enrollment Status Page
- [ ] Select or create ESP profile for pre-provisioning
- [ ] Configure profile:
  - [ ] Show app and profile installation progress: **Yes**
  - [ ] Block device use until required apps are installed: **Selected apps**
  - [ ] Select this Windows Update app in the list
  - [ ] Allow users to reset device: **Yes**
  - [ ] Show error when installation takes longer than specified: **90-120 minutes**

## Autopilot Profile Configuration

- [ ] Navigate to: Devices → Enrollment → Windows enrollment → Deployment profiles
- [ ] Select your pre-provisioning Autopilot profile
- [ ] Verify settings:
  - [ ] Deployment mode: **Self-deploying** or **User-driven** with pre-provisioning
  - [ ] Join to Azure AD as: **Azure AD joined**
  - [ ] Skip connectivity check: **No**

## Testing (Pilot Phase)

- [ ] Select 1-3 test devices
- [ ] Create test device group
- [ ] Assign all profiles and apps to test group
- [ ] Perform White Glove provisioning on test device:
  - [ ] Boot device
  - [ ] Press Windows key 5 times to enter Technician Flow
  - [ ] Sign in with technician account
  - [ ] Monitor ESP progress
  - [ ] Verify Windows Update app installs
  - [ ] Check PSADT v4 logs on device: `C:\Windows\Logs\Software\Windows Update - ESP Pre-provisioning_1.0_Install_*.log`
  - [ ] Check detection logs: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdate-ESP-Detection.log`
  - [ ] Complete provisioning and seal device
  - [ ] Verify user enrollment is faster (fewer updates)

## Validation

- [ ] Check Intune app installation status (should show success)
- [ ] Review PSADT v4 logs:
  - [ ] Main log: `C:\Windows\Logs\Software\Windows Update - ESP Pre-provisioning_1.0_Install_*.log`
  - [ ] Detection log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdate-ESP-Detection.log`
- [ ] Verify marker file exists: `C:\ProgramData\WindowsUpdate-ESP\UpdatesInstalled.json`
- [ ] Check Windows Update history (Settings → Update & Security → Windows Update → View update history)
- [ ] Verify reboot handling worked correctly (if updates required restart)
- [ ] Measure time savings during user enrollment phase

## PSADT v4 Specific Checks

- [ ] Verify PSADT v4 module loaded successfully (check log for "PSAppDeployToolkit version 4.1.8")
- [ ] Verify $adtSession variables populated correctly (check log)
- [ ] Verify DeployMode auto-detected as "Silent" during ESP
- [ ] Verify 3010 exit code returned if reboot needed
- [ ] Check that no GUI prompts appeared during installation

## Troubleshooting Preparation

- [ ] Document expected installation time (baseline)
- [ ] Create process for accessing PSADT v4 logs remotely
- [ ] Identify support contacts for escalation
- [ ] Prepare rollback plan if needed

## Production Rollout

- [ ] Review pilot results
- [ ] Document any issues and resolutions
- [ ] Update device group to include all pre-provisioning devices
- [ ] Monitor first wave of production deployments
- [ ] Track success rate in Intune reporting

## Post-Deployment Monitoring

- [ ] Set up Intune report for app installation status
- [ ] Monitor installation success rate (target: >95%)
- [ ] Track average installation time
- [ ] Review failed installations weekly
- [ ] Collect feedback from technicians performing provisioning
- [ ] Review PSADT v4 logs for any unexpected behavior

## Ongoing Maintenance

- [ ] Review logs monthly for patterns
- [ ] Update scripts if Windows Update behavior changes
- [ ] Test with new Windows releases
- [ ] Keep documentation updated
- [ ] Consider updating PSADT to newer v4.x versions when available

## Notes

**ESP Timeout Recommendations:**
- Minimum: 60 minutes (may be too short)
- Recommended: 90-120 minutes (accounts for large cumulative updates)
- Very large updates: 120-180 minutes

**Network Requirements:**
- Reliable internet connection required
- Consider wired connection for faster downloads
- Ensure firewall allows Windows Update traffic

**Expected Behavior:**
- Device may reboot automatically during updates
- ESP will resume after reboot
- Installation marked complete after all updates installed and detection script succeeds
- PSADT v4 will automatically return exit code 3010 if reboot needed

**PSADT v4 Benefits:**
- Automatic Silent mode detection during ESP/OOBE
- Better logging structure
- Cleaner error handling
- Module-based architecture (easier to update)
- Better reboot code handling

## Sign-Off

- [ ] IT Manager approval
- [ ] Pilot test completed successfully
- [ ] Production deployment authorized
- [ ] Support team trained on PSADT v4 log locations

**Deployed By:** _____________________ **Date:** _____________________

**Approved By:** _____________________ **Date:** _____________________
