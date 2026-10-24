# AWS Session Manager Plugin - Quick Start Guide

Get the AWS Session Manager Plugin deployed via Intune in 5 minutes.

---

## What This Package Does

- **Downloads** the latest AWS Session Manager Plugin installer from AWS S3
- **Installs** silently on Windows 10/11 (64-bit)
- **Verifies** the installation is functional
- **Self-contained** — no pre-downloaded files needed

---

## Quick Deployment (5 Steps)

### 1. Package for Intune

```powershell
# Option A: Use helper script (recommended)
cd intune-apps\PSADT.AWS.SessionManager
.\Package-ForIntune.ps1

# Option B: Manual packaging
IntuneWinAppUtil.exe -c . -s Invoke-AppDeployToolkit.exe -o ..\
```

**Result:** Creates `PSADT.AWS.SessionManager.intunewin` (~220 KB)

---

### 2. Create Win32 App in Intune

**Portal:** [Intune Admin Center](https://intune.microsoft.com) → Apps → Add → Windows app (Win32)

**App Info:**
- **Name:** AWS Session Manager Plugin
- **Publisher:** Amazon Web Services
- **App version:** Latest

**Program:**
- **Install:** `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`
- **Uninstall:** `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`
- **Install behavior:** System

**Detection:**
- **Type:** Custom script
- **File:** Upload `Detect-AWSSessionManager.ps1`

**Requirements:**
- **OS:** Windows 10 1607+ (64-bit)
- **Disk:** 100 MB

---

### 3. Assign to Users/Devices

**Options:**
- **Required:** Auto-install for target group
- **Available:** Users install from Company Portal
- **Uninstall:** Remove from target group

---

### 4. Monitor Deployment

**Portal:** Apps → AWS Session Manager Plugin → Device install status

**Status meanings:**
- ✅ **Installed** — Success
- ❌ **Failed** — Check logs (see troubleshooting)
- ⏳ **Pending** — Waiting for device check-in
- ⊘ **Not applicable** — Device doesn't meet requirements

---

### 5. Verify on Device

```powershell
# Check installation
session-manager-plugin --version

# Test with AWS CLI (if installed)
aws ssm start-session --target i-1234567890abcdef0
```

---

## What Gets Installed

| Component | Path |
|---|---|
| Plugin executable | `C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe` |
| Log file | `C:\Windows\Logs\Software\Amazon Web Services_AWS Session Manager Plugin_*.log` |

---

## Troubleshooting (Common Issues)

### Installation Fails

**Check:**
1. Device has internet access to `s3.amazonaws.com`
2. Device meets requirements (Windows 10 1607+ 64-bit)
3. Review log file for errors

**Log location:**
```
C:\Windows\Logs\Software\Amazon Web Services_AWS Session Manager Plugin_Latest_01_PSAppDeployToolkit_Install.log
```

### Plugin Not Found After Install

**Cause:** PATH not updated

**Fix:**
```powershell
# Restart PowerShell, or:
$env:Path += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"
```

### Can't Start Sessions

**Cause:** AWS CLI not installed or not configured

**Fix:**
```powershell
# Install AWS CLI
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Configure credentials
aws configure
```

---

## Prerequisites (Target Systems)

### Required
- Windows 10 1607+ or Windows 11 (64-bit)
- Internet connectivity (downloads from AWS S3)

### Recommended
- AWS CLI 1.16.12+ (for Session Manager functionality)
- Configured AWS credentials

### Network
- Allow HTTPS to: `s3.amazonaws.com`

---

## Files in This Package

| File | Purpose |
|---|---|
| `Invoke-AppDeployToolkit.ps1` | Main installation script |
| `Invoke-AppDeployToolkit.exe` | PSADT executable wrapper |
| `Detect-AWSSessionManager.ps1` | Intune detection script |
| `Package-ForIntune.ps1` | Helper to create .intunewin file |
| `README.md` | Detailed documentation |
| `DEPLOYMENT-GUIDE.md` | Complete deployment walkthrough |
| `QUICKSTART.md` | This file |

---

## Support

- **Package issues:** DWX Team
- **AWS plugin issues:** [AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- **Intune issues:** Intune administrators

---

## Key Features

✅ **Dynamic download** — Always gets latest version from AWS  
✅ **Silent installation** — No user interaction required  
✅ **Detection logic** — Verifies plugin is functional  
✅ **Uninstall support** — Clean removal via Intune  
✅ **Detailed logging** — Full PSADT logs for troubleshooting  
✅ **Self-contained** — No external dependencies  

---

## Next Steps

After deployment:

1. **Deploy AWS CLI** (if not already deployed)
2. **Configure AWS credentials** for users
3. **Test Session Manager connections** to EC2/on-prem servers
4. **Monitor device install status** in Intune portal

---

**Version:** 1.0.0  
**Created:** 2026-07-22  
**Author:** DWX Team
