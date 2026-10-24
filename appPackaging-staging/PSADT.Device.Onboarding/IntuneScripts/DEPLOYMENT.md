# First Run Onboarding - Intune Deployment Guide

## Overview

This package deploys a scheduled task-based first run onboarding experience for new users.

**Deployment Model:**
- Package deployed to: `C:\ProgramData\G1001\Packages\FirstRunOnboarding\`
- Scheduled task created: `G1001-FirstRunOnboarding`
- Trigger: At logon (any user)
- Runs once per user (uses per-user marker file)

## Package Structure

```
PSADT.Device.Onboarding/
├── IntuneScripts/                         (What Intune runs)
│   ├── Deploy-FirstRunOnboarding.ps1         Install script
│   ├── Uninstall-FirstRunOnboarding.ps1      Uninstall script
│   ├── Detect-Deployment.ps1                 Detection script
│   └── DEPLOYMENT.md                         This file
│
└── FirstRunOnboarding/                    (PSADT package to copy)
    ├── Invoke-AppDeployToolkit.exe           PSADT launcher
    ├── Invoke-AppDeployToolkit.ps1           Main onboarding script (7 steps)
    ├── Assets/                               Branding resources
    ├── Config/                               PSADT configuration
    ├── PSAppDeployToolkit/                   PSADT framework
    └── Strings/                              UI text resources
```

## Intune Configuration

### Package Creation

```powershell
IntuneWinAppUtil.exe -c "C:\Path\To\PSADT.Device.Onboarding" -s "IntuneScripts\Deploy-FirstRunOnboarding.ps1" -o "C:\temp\Output\PSADT.Device.Onboarding" -q
```

**Output:** `Deploy-FirstRunOnboarding.intunewin`

**What gets packaged:** The entire `PSADT.Device.Onboarding` folder (both `IntuneScripts/` and `FirstRunOnboarding/`)

**What Intune runs:** `IntuneScripts\Deploy-FirstRunOnboarding.ps1`

**What that script copies:** `FirstRunOnboarding\` folder → `C:\ProgramData\G1001\Packages\FirstRunOnboarding\`

### App Information

| Setting | Value |
|---------|-------|
| Name | First Run Onboarding |
| Description | Automated first-run experience for new users. Runs at first logon. |
| Publisher | G1001 |
| App Version | 1.0.0 |

### Program

| Setting | Value |
|---------|-------|
| Install command | `powershell.exe -ExecutionPolicy Bypass -File IntuneScripts\Deploy-FirstRunOnboarding.ps1` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -File IntuneScripts\Uninstall-FirstRunOnboarding.ps1` |
| Install behavior | **System** |
| Device restart behavior | No specific action |

### Requirements

| Setting | Value |
|---------|-------|
| Operating system | Windows 10 1607+, Windows 11 |
| Architecture | x64 |

### Detection Rules

| Setting | Value |
|---------|-------|
| Rules format | Use a custom detection script |
| Script file | Upload **Detect-Deployment.ps1** |

### Dependencies

None

### Supersedence

None

### Assignments

| Type | Group |
|------|-------|
| Required | **All Devices** (or white glove device group) |

**Important:** Assign to **DEVICES** not Users - deploys during Device ESP (white glove)

## How It Works

### White Glove Phase (Device ESP)

1. Technician provisions device
2. Intune deploys this Win32 app
3. `Deploy-FirstRunOnboarding.ps1` runs:
   - Copies entire package to `C:\ProgramData\G1001\Packages\FirstRunOnboarding\`
   - Creates scheduled task `G1001-FirstRunOnboarding`
   - Task stays dormant

### User First Logon

1. **Any user** logs in (post-ESP, at desktop)
2. Scheduled task triggers automatically
3. Runs: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive`
4. Script checks: Does **this user** have marker file? (`%LOCALAPPDATA%\DWX\FirstRunComplete.txt`)
5. If **NO** → Run 7-step onboarding, create marker
6. If **YES** → Exit silently

### User Subsequent Logons

1. User logs in again
2. Task triggers
3. Marker found → Script exits immediately (no UI)

### New User on Same Device

1. Different user logs in
2. Task triggers
3. No marker for **this user** → Runs onboarding
4. Creates marker in new user's profile

## What Users See

**Progress Window:**
- Title: "Group1001 Device Onboarding"
- Progress: "Setting up your device with essential applications and services."
- Steps 1-7 with status messages

**Completion Dialog:**
- "Setup complete! Your device is ready to use."
- Bullet list of what's ready (Outlook, Teams, OneDrive, Company Portal)
- "Welcome to Group1001!"
- **Get Started** button

## Onboarding Steps

1. **Zscaler** - Silent detection (15s wait)
2. **Defender** - Update definitions
3. **Outlook** - Launch with auto-recovery for false update errors
4. **Teams** - Launch if not running
5. **OneDrive** - Check/launch if needed
6. **Company Portal** - Launch via protocol handler
7. **Complete** - Show welcome message

## Logs

**Deployment logs:**
- Check Intune Management Extension logs during ESP

**Per-user execution logs:**
- `%LOCALAPPDATA%\PSAppDeployToolkit\G1001\First Run Onboarding\Logs\`

**Marker file (per-user):**
- `%LOCALAPPDATA%\DWX\FirstRunComplete.txt`

## Troubleshooting

### Task doesn't trigger at logon

Check scheduled task exists:
```powershell
Get-ScheduledTask -TaskName "G1001-FirstRunOnboarding"
```

### Task exists but script doesn't run

Check task last run result:
```powershell
Get-ScheduledTaskInfo -TaskName "G1001-FirstRunOnboarding"
```

### Script runs every login

Check if marker file exists for the user:
```powershell
Test-Path "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt"
```

If missing, check PSADT logs for errors during execution.

### Package not found

Check folder exists:
```powershell
Test-Path "C:\ProgramData\G1001\Packages\FirstRunOnboarding"
Get-ChildItem "C:\ProgramData\G1001\Packages\FirstRunOnboarding"
```

## Testing

### Test deployment (Device context)

```powershell
# Run as SYSTEM
psexec -i -s powershell.exe

# Then run
C:\Path\To\Deploy-FirstRunOnboarding.ps1
```

### Test user experience

1. Login as test user
2. Task should auto-trigger
3. Watch onboarding UI
4. Verify marker created: `$env:LOCALAPPDATA\DWX\FirstRunComplete.txt`

### Reset for re-testing

```powershell
# Remove marker
Remove-Item "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt" -Force

# Next login will re-run onboarding
```

## Version History

### v1.0.0 (2026-06-21)
- Initial release
- Device-targeted deployment with per-user scheduled task
- 7-step onboarding flow
- Automatic Outlook error recovery
- Custom branding for Group1001

## Support

Created by: Zachary Hayward with Claude Code
Date: 2026-06-21
