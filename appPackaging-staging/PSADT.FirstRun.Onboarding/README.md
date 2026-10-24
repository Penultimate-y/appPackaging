# First Run Onboarding - PSADT Package

Guided first-login experience that helps new users set up their essential applications and services.

## Overview

This PSADT v4 package provides an automated, user-friendly onboarding flow that runs at first login after device enrollment. It guides users through 7 essential setup steps with progress tracking and automatic error recovery.

## Features

### 7-Step Onboarding Flow

1. **Welcome Message** - Introduces the setup process with clear expectations
2. **Zscaler Security Tunnel** - Waits for corporate network connectivity (silent, logs only)
3. **Defender Updates** - Updates Windows Defender definitions to latest version
4. **Outlook Setup** - Launches Outlook with automatic `--clearLocalState` recovery for new Outlook false update errors
5. **Teams Setup** - Launches Microsoft Teams for collaboration
6. **OneDrive Check** - Ensures OneDrive is running for file sync
7. **Company Portal** - Opens app catalog for user to browse available apps

### Key Capabilities

- **Progress Tracking**: Visual progress bar showing "Step X of 7" throughout the flow
- **Error Recovery**: Automatically detects and fixes Outlook first-launch issues
- **Silent Resilience**: Logs failures but continues to next step (no user-facing errors)
- **One-Time Execution**: Marker file prevents re-running on subsequent logins
- **User Context**: Runs as the logged-in user (not SYSTEM)

## Deployment

### Intune Configuration

**Package as Win32 App:**
- **Install Command**: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive`
- **Uninstall Command**: `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`
- **Detection Rule**: Script detection using `Detect-FirstRunComplete.ps1`
- **Install Context**: User
- **Assignment**: Required for "All Users" or specific enrollment group
- **Dependencies**: None (Office, Teams, OneDrive should already be deployed via ESP)

### Recommended Trigger

Deploy as a **Required** Win32 app with:
- **Assignment**: All Users
- **Install Behavior**: User
- **Delivery Optimization**: Enabled

The app will automatically run at first login after Intune device enrollment completes.

### Alternative: Scheduled Task

If you prefer login script approach instead of Win32 app:

```powershell
# Create scheduled task during ESP (device context)
$action = New-ScheduledTaskAction -Execute "C:\Path\To\Invoke-AppDeployToolkit.exe" -Argument "-DeploymentType Install -DeployMode Interactive"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -GroupId "Users"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "DWX-FirstRunOnboarding" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

## Error Handling

All steps are non-blocking - if a step fails, the script logs the error and continues to the next step. This ensures users always complete the onboarding flow even if specific apps have issues.

### Logged (Non-Fatal) Errors

- **Zscaler timeout**: Services don't start within 90 seconds (continues anyway)
- **Defender update failure**: Network or policy issue (continues anyway)
- **Outlook launch failure**: Not installed or launch blocked (continues anyway)
- **Teams not found**: Not installed at expected paths (continues anyway)
- **OneDrive not found**: Not installed (continues anyway)
- **Company Portal failure**: Store protocol handler blocked (continues anyway)

### Fatal Errors

The script only exits with error if:
- PSADT module cannot be loaded
- Unhandled exception in core framework

## Testing

### Manual Test (User Context)

```powershell
# Run as logged-in user
cd C:\Path\To\PSADT.FirstRun.Onboarding
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

### Reset for Re-Testing

```powershell
# Remove marker file to allow re-running
Remove-Item "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt" -Force
```

### Check Logs

Logs are written to: `$env:LOCALAPPDATA\PSAppDeployToolkit\<AppVendor>\<AppName>\Logs\`

Typical path: `C:\Users\<username>\AppData\Local\PSAppDeployToolkit\Delaware Life\First Run Onboarding\Logs\`

## Files in This Package

```
PSADT.FirstRun.Onboarding/
├── Assets/                          # PSADT UI assets (icons, branding)
├── Config/
│   └── config.psd1                  # PSADT configuration
├── Files/                           # (Empty - no binaries to deploy)
├── PSAppDeployToolkit/              # PSADT v4.1.8 framework
├── PSAppDeployToolkit.Extensions/   # (Empty - no custom extensions)
├── Strings/                         # PSADT localized strings
├── SupportFiles/                    # (Empty - no supporting files)
├── Invoke-AppDeployToolkit.exe      # Compiled launcher
├── Invoke-AppDeployToolkit.ps1      # Main deployment script (customized)
├── Detect-FirstRunComplete.ps1      # Intune detection script
├── README.md                        # This file
└── template-version.txt             # PSADT template version (4.1.8)
```

## Customization

### Modify Steps

Edit `Invoke-AppDeployToolkit.ps1` and modify the `Install-ADTDeployment` function to add, remove, or reorder steps.

### Adjust Timeouts

**Zscaler wait timeout:**
```powershell
# In Wait-ZscalerReady function
$maxWaitSeconds = 90  # Change this value
```

**Outlook error detection:**
```powershell
# In Start-OutlookFirstRun function
Start-Sleep -Seconds 10  # Time to wait before checking if Outlook crashed
```

### Change Branding

Update `$adtSession` variables:
```powershell
AppVendor = 'Delaware Life'      # Your company name
InstallTitle = 'Welcome to ...'   # Custom welcome title
```

Customize welcome message text in `Show-ADTInstallationWelcome`:
```powershell
Show-ADTInstallationWelcome -Title "..." -Subtitle "..." -CustomText "..."
```

## Troubleshooting

### "Outlook opens but immediately closes"

This is the exact scenario this package detects and fixes automatically using `olk.exe --clearLocalState`. Check logs to confirm the recovery ran.

### "Zscaler takes too long"

Increase `$maxWaitSeconds` in `Wait-ZscalerReady` function. Default is 90 seconds with 15-second tunnel establishment buffer.

### "Script runs every login"

Detection script is failing. Check that marker file exists:
```powershell
Test-Path "$env:LOCALAPPDATA\DWX\FirstRunComplete.txt"
```

If missing, check logs for errors during Post-Install phase.

### "Apps don't launch"

Check executable paths in each `Start-*` function. Paths may vary if different Office/Teams versions are deployed:
- New Outlook: `$env:LOCALAPPDATA\Microsoft\Office\16.0\Outlook\olk.exe`
- Classic Outlook: `$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE`
- Teams: `$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe`
- OneDrive: `$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe`

## Version History

### v1.0.0 (2026-06-21)
- Initial release
- 7-step guided onboarding flow
- Automatic Outlook error recovery
- Silent error handling with logging
- PSADT v4.1.8 framework

## Support

For issues or questions:
1. Check logs in `%LOCALAPPDATA%\PSAppDeployToolkit\Delaware Life\First Run Onboarding\Logs\`
2. Review Intune deployment status in Company Portal or Intune admin center
3. Contact DWX Engineering team

## License

Internal use only - Delaware Life
