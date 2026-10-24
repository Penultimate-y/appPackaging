# AWS Session Manager Plugin - Intune Deployment Guide

Complete step-by-step guide for deploying the AWS Session Manager Plugin via Microsoft Intune using the PSADT package.

---

## Prerequisites

### Required Tools

1. **Microsoft Intune Win32 Content Prep Tool**
   - Download: [IntuneWinAppUtil.exe](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)
   - Latest version recommended

2. **Access Requirements**
   - Intune admin access (Application Administrator or higher)
   - Ability to create Win32 apps in Intune portal

### Target Environment

- **Operating Systems:** Windows 10 1607+ / Windows 11 (64-bit)
- **User Context:** System (SYSTEM account)
- **Network:** Internet connectivity required (downloads from AWS S3)

---

## Step 1: Package the Application

### 1.1 Prepare the Source Folder

Ensure your folder structure is complete:

```
PSADT.AWS.SessionManager/
├── Invoke-AppDeployToolkit.exe
├── Invoke-AppDeployToolkit.ps1
├── Detect-AWSSessionManager.ps1
├── PSAppDeployToolkit/
└── [other PSADT folders]
```

### 1.2 Create the .intunewin Package

Open PowerShell (run as Administrator) and navigate to the parent directory:

```powershell
# Navigate to intune-apps folder
cd "C:\path\to\dwx-automation-cli-scripts\intune-apps"

# Create the package
.\IntuneWinAppUtil.exe `
    -c "PSADT.AWS.SessionManager" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "."
```

**Parameters explained:**
- `-c` = Source folder containing all package files
- `-s` = Setup file (the PSADT executable wrapper)
- `-o` = Output folder for the generated `.intunewin` file

**Expected output:**
- File: `PSADT.AWS.SessionManager.intunewin` (approximately 220 KB)

---

## Step 2: Upload to Intune

### 2.1 Create New Win32 App

1. **Navigate to Intune Portal:**
   - Go to [Intune Admin Center](https://intune.microsoft.com)
   - Navigate to: **Apps** → **All apps** → **Add**

2. **Select App Type:**
   - **App type:** Windows app (Win32)
   - Click **Select**

### 2.2 App Information

Fill in the following fields:

| Field | Value |
|---|---|
| **Name** | AWS Session Manager Plugin |
| **Description** | AWS Systems Manager Session Manager plugin for AWS CLI. Enables interactive shell sessions to EC2 instances and on-premises servers via Session Manager. |
| **Publisher** | Amazon Web Services |
| **App version** | Latest |
| **Category** | (Optional) Developer Tools, IT Admin Tools |
| **Show this as a featured app** | No |
| **Information URL** | `https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html` |
| **Privacy URL** | `https://aws.amazon.com/privacy/` |
| **Developer** | Amazon Web Services |
| **Owner** | (Your organization) |
| **Notes** | Dynamically downloads latest installer from AWS. Requires AWS CLI 1.16.12+ for functionality. |

**Logo (Optional):**
- Upload AWS or Session Manager icon if desired
- Recommended size: 512x512 pixels, PNG format

### 2.3 Program Configuration

| Field | Value |
|---|---|
| **Install command** | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` |
| **Uninstall command** | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| **Install behavior** | System |
| **Device restart behavior** | Determine behavior based on return codes |
| **Return codes** | (Use defaults, or add custom codes below) |

**Custom Return Codes (Optional):**

| Code | Type |
|---|---|
| 0 | Success |
| 1641 | Soft Reboot |
| 3010 | Soft Reboot |
| 60001 | Failed |
| 60008 | Failed |

### 2.4 Requirements

| Field | Value |
|---|---|
| **Operating system architecture** | 64-bit |
| **Minimum operating system** | Windows 10 1607 |
| **Disk space required (MB)** | 100 |
| **Physical memory required (MB)** | (Leave blank) |
| **Minimum number of logical processors** | (Leave blank) |
| **Minimum CPU speed (MHz)** | (Leave blank) |

**Additional requirement rules (Optional):**
- Can add registry key checks for AWS CLI if co-deployment needed
- Can add file system checks for prerequisite tools

### 2.5 Detection Rules

| Field | Value |
|---|---|
| **Rules format** | Use a custom detection script |
| **Script file** | Upload `Detect-AWSSessionManager.ps1` |
| **Run script as 32-bit process** | No |
| **Enforce script signature check** | No |

**Detection Script Logic:**
- Checks for `session-manager-plugin.exe` in Program Files
- Verifies plugin can report its version
- Returns exit code 0 if installed and functional

### 2.6 Dependencies

**No dependencies required** for this package.

**Optional dependencies** (if deploying as part of larger solution):
- AWS CLI (prerequisite for Session Manager functionality)
- PowerShell 5.1+ (built into target Windows versions)

### 2.7 Supersedence

**No supersedence configured** (this is a new deployment).

If updating from a previous non-PSADT deployment:
- Add the old package as a superseded app
- Select **Uninstall previous version**

---

## Step 3: Assignments

### 3.1 Required Assignment

**For users who must have AWS Session Manager:**

1. **Assignment type:** Required
2. **Group:** (Select Azure AD group, e.g., "AWS Administrators")
3. **End user notifications:** Show all toast notifications
4. **Deadline:** As soon as possible

### 3.2 Available Assignment

**For self-service installation:**

1. **Assignment type:** Available for enrolled devices
2. **Group:** (Select target group, e.g., "Developers" or "All Users")
3. **End user experience:**
   - Users see app in Company Portal
   - Can install on-demand

### 3.3 Exclusions

**For devices that should not receive the app:**

1. **Assignment type:** Uninstall
2. **Group:** (Select exclusion group if needed)

---

## Step 4: Review and Create

1. **Review all settings**
2. **Click Create**
3. **Wait for upload to complete** (1-2 minutes)

---

## Step 5: Verification

### 5.1 Monitor Deployment

1. **Navigate to:** Apps → AWS Session Manager Plugin → Device install status
2. **Check status:**
   - **Installed:** Successful deployment
   - **Failed:** Review error codes and logs
   - **Not applicable:** Device doesn't meet requirements
   - **Pending:** Waiting for device check-in

### 5.2 Test Installation on Pilot Device

**On a test device:**

1. **Force Intune sync:**
   ```
   Settings → Accounts → Access work or school → (Account) → Info → Sync
   ```

2. **Wait for installation** (10-15 minutes typical)

3. **Verify installation:**
   ```powershell
   # Check executable exists
   Test-Path "C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe"

   # Check version
   session-manager-plugin --version

   # Check PATH
   $env:Path -split ';' | Select-String 'SessionManagerPlugin'
   ```

4. **Test functionality** (if AWS CLI installed):
   ```powershell
   # List Systems Manager managed instances
   aws ssm describe-instance-information

   # Test session start (requires target instance)
   aws ssm start-session --target i-1234567890abcdef0
   ```

### 5.3 Review Logs

**On target device:**

Log location:
```
C:\Windows\Logs\Software\Amazon Web Services_AWS Session Manager Plugin_Latest_01_PSAppDeployToolkit_Install.log
```

**Key log entries to verify:**
- Download from AWS S3 completed
- Installer executed with exit code 0
- Version check passed
- Installation verified

---

## Step 6: Rollout Strategy

### Phased Deployment (Recommended)

**Phase 1: Pilot (Week 1)**
- Deploy to IT admin test group (5-10 devices)
- Monitor for issues
- Validate functionality

**Phase 2: Early Adopters (Week 2)**
- Deploy to AWS power users (50-100 devices)
- Gather feedback
- Confirm stability

**Phase 3: Production (Week 3+)**
- Deploy to all target users
- Monitor device install status
- Address any issues

---

## Troubleshooting

### Common Issues

#### Issue 1: Installation Fails with 60001

**Symptoms:**
- Intune reports failure code 60001
- App not detected after installation

**Cause:** Download failure or network connectivity issue

**Resolution:**
1. Check device internet connectivity
2. Verify `s3.amazonaws.com` not blocked by firewall/proxy
3. Review PSADT log for download errors
4. Retry installation

---

#### Issue 2: Detection Fails After Successful Installation

**Symptoms:**
- Installation completes with exit code 0
- Intune shows "Not detected"

**Cause:** PATH not updated or plugin not functional

**Resolution:**
1. Verify file exists:
   ```powershell
   Test-Path "C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe"
   ```
2. Test plugin manually:
   ```powershell
   & "C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe" --version
   ```
3. Restart Intune Management Extension:
   ```powershell
   Restart-Service -Name IntuneManagementExtension
   ```

---

#### Issue 3: Slow Download During Installation

**Symptoms:**
- Installation takes longer than expected
- Device has slow internet connection

**Cause:** Bandwidth limitations or AWS S3 latency

**Resolution:**
- Normal installation time: 5-10 minutes
- Slow connections: up to 30 minutes
- Installer size: ~2-5 MB (varies by version)
- No action required unless timeout occurs

---

#### Issue 4: User Cannot Run Session Manager Sessions

**Symptoms:**
- Plugin installed successfully
- `aws ssm start-session` fails with plugin not found

**Cause:** AWS CLI not installed or incompatible version

**Resolution:**
1. Verify AWS CLI installed:
   ```powershell
   aws --version
   ```
2. Check AWS CLI version (must be 1.16.12+):
   ```powershell
   # Upgrade if needed
   msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
   ```
3. Configure AWS credentials:
   ```powershell
   aws configure
   ```

---

## Advanced Configuration

### Silent Installation Parameters

The PSADT wrapper supports additional parameters for advanced scenarios:

```powershell
# Interactive mode (shows dialogs)
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive

# Non-interactive mode (dialogs without user interaction)
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode NonInteractive

# Suppress reboot passthrough
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent -SuppressRebootPassThru

# Terminal Server mode (RDS/Citrix)
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent -TerminalServerMode
```

### Custom Detection Logic

If you need to modify detection (e.g., check for specific version):

```powershell
# Example: Detect specific version
$sessionManagerPath = "$env:ProgramFiles\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe"

if (Test-Path $sessionManagerPath)
{
    $version = & $sessionManagerPath --version 2>&1
    if ($version -match '1\.2\.463')  # Replace with minimum version
    {
        Write-Host "Version $version detected"
        exit 0
    }
}
exit 1
```

---

## Maintenance

### Updating to New Versions

Since this package downloads the latest version dynamically:

1. **No package update needed** for new Session Manager versions
2. **Force reinstall** if you want to update deployed instances:
   - Change assignment to "Uninstall"
   - Wait for uninstall to complete
   - Change assignment back to "Required"

### Monitoring Health

**Create a device compliance script** to monitor plugin health:

```powershell
# Compliance-Check-SessionManager.ps1
$pluginPath = "$env:ProgramFiles\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe"

if (Test-Path $pluginPath)
{
    try
    {
        $null = & $pluginPath --version 2>&1
        Write-Output "Compliant"
        exit 0
    }
    catch
    {
        Write-Output "Non-Compliant: Plugin not functional"
        exit 1
    }
}
else
{
    Write-Output "Non-Compliant: Plugin not installed"
    exit 1
}
```

---

## Support

### Internal Support

- **Package issues:** Contact DWX Team
- **Deployment issues:** Contact Intune administrators

### External Resources

- [AWS Session Manager Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [PSAppDeployToolkit Forums](https://psappdeploytoolkit.com)

---

## Appendix: Quick Reference

### Installation Commands

```powershell
# Standard silent install
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

# Standard silent uninstall
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent

# Repair installation
Invoke-AppDeployToolkit.exe -DeploymentType Repair -DeployMode Silent
```

### Key File Paths

| Item | Path |
|---|---|
| **Plugin Executable** | `C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe` |
| **Installation Log** | `C:\Windows\Logs\Software\Amazon Web Services_AWS Session Manager Plugin_Latest_01_PSAppDeployToolkit_Install.log` |
| **Intune Log** | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` |

### Intune App Settings Summary

| Setting | Value |
|---|---|
| **Install command** | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` |
| **Uninstall command** | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| **Install behavior** | System |
| **Detection** | Custom script: `Detect-AWSSessionManager.ps1` |
| **Min OS** | Windows 10 1607 (64-bit) |
| **Disk space** | 100 MB |

---

**Document Version:** 1.0.0  
**Last Updated:** 2026-07-22  
**Author:** DWX Team
