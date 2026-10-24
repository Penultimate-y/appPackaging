# PSADT.Device.Onboarding

## Overview

PSADT v4 first-run onboarding experience for new users after Autopilot white glove enrollment.

Deploys during Device ESP (white glove), executes at first user login. Runs once per user.

## What It Does

7-step guided onboarding:
1. **Zscaler** - Wait for services (ZSAService, ZSATunnel)
2. **Defender** - Update definitions
3. **Outlook** - Launch with auto-recovery for false update errors
4. **Teams** - Launch if not running
5. **OneDrive** - Check/launch if needed
6. **Company Portal** - Launch for app browsing
7. **Complete** - Welcome message with Get Started button

## Deployment Model

**Intune Win32 App:**
- Deploy to: Device groups
- Install context: SYSTEM
- Target: White glove / pre-provisioned devices

**What happens:**
1. During Device ESP: Package copied to `C:\ProgramData\G1001\Packages\FirstRunOnboarding\`
2. Scheduled task created: `G1001-FirstRunOnboarding` (trigger: at logon, any user)
3. At first user login: Task runs PSADT in user context
4. Marker file prevents re-runs: `%LOCALAPPDATA%\DWX\FirstRunComplete.txt`

## Folder Structure

```
PSADT.Device.Onboarding/
├── IntuneScripts/                         What Intune runs
│   ├── Deploy-FirstRunOnboarding.ps1         Install
│   ├── Uninstall-FirstRunOnboarding.ps1      Uninstall
│   ├── Detect-Deployment.ps1                 Detection
│   └── DEPLOYMENT.md                         Full guide
│
└── FirstRunOnboarding/                    PSADT package
    ├── Invoke-AppDeployToolkit.exe
    ├── Invoke-AppDeployToolkit.ps1           Main script (7 steps)
    ├── Assets/, Config/, Strings/            Branding/UI
    └── PSAppDeployToolkit/                   Framework v4.1.8
```

## Quick Start

**Package:**
```powershell
C:\G1001_DEV\Intune.Win32Apps\IntuneWinAppUtil.exe `
  -c "C:\G1001_DEV\DWX-fresh\dwx-automation-cli-scripts\intune-apps\PSADT.Device.Onboarding" `
  -s "IntuneScripts\Deploy-FirstRunOnboarding.ps1" `
  -o "C:\temp\Output\PSADT.Device.Onboarding" `
  -q
```

**Intune Setup:**
- Install command: `powershell.exe -ExecutionPolicy Bypass -File IntuneScripts\Deploy-FirstRunOnboarding.ps1`
- Uninstall command: `powershell.exe -ExecutionPolicy Bypass -File IntuneScripts\Uninstall-FirstRunOnboarding.ps1`
- Detection: Custom script → Upload `IntuneScripts\Detect-Deployment.ps1`
- Assignment: Required → Device group

**Full guide:** See [DEPLOYMENT.md](IntuneScripts/DEPLOYMENT.md)

## Branding

- **Company:** Group1001 (multi-company environment)
- **App Vendor:** G1001
- **Banner:** "Group1001 Device Onboarding"
- **Welcome:** "Welcome to Group1001!"

## Version

- **Package Version:** 1.0.0
- **PSADT Version:** 4.1.8
- **Created:** 2026-06-21
- **Author:** Zachary Hayward with Claude Code

## Files

| Path | Purpose |
|------|---------|
| [IntuneScripts/Deploy-FirstRunOnboarding.ps1](IntuneScripts/Deploy-FirstRunOnboarding.ps1) | Install - copies package, creates scheduled task |
| [IntuneScripts/Uninstall-FirstRunOnboarding.ps1](IntuneScripts/Uninstall-FirstRunOnboarding.ps1) | Uninstall - removes package and task |
| [IntuneScripts/Detect-Deployment.ps1](IntuneScripts/Detect-Deployment.ps1) | Detection - checks package and task exist |
| [IntuneScripts/DEPLOYMENT.md](IntuneScripts/DEPLOYMENT.md) | Full deployment guide with troubleshooting |
| [FirstRunOnboarding/Invoke-AppDeployToolkit.ps1](FirstRunOnboarding/Invoke-AppDeployToolkit.ps1) | Main onboarding script with 7-step flow |

## Testing

**Local test (as SYSTEM):**
```powershell
psexec -i -s powershell.exe
cd C:\Path\To\PSADT.Device.Onboarding\IntuneScripts
.\Deploy-FirstRunOnboarding.ps1
```

**User experience test:**
1. Login as test user
2. Onboarding should auto-launch
3. Click through 7 steps
4. Verify marker: `Test-Path "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt"`

**Re-test:**
```powershell
Remove-Item "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt" -Force
# Next login will re-run
```

## Notes

- **Office must be installed** - Deployed during Device ESP to device group
- **New Outlook detection** - Uses Get-AppxPackage for Microsoft.OutlookForWindows
- **Automatic recovery** - Detects Outlook crash state, runs `olk.exe --clearLocalState`
- **Multi-user support** - Per-user marker files allow different users on same device
- **No silent caps** - All 7 steps logged, errors don't block subsequent steps

## Owner

Zachary Hayward · Kunle Ayegbusi · Allen Johnson (EPM / Intune Apps)
