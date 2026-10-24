# Set Time Zone - User Select (PSADT v4)

**Version:** 2.0.0  
**PSADT Version:** 4.1.8  
**Author:** Zachary Hayward  
**Date:** 2026-06-21

## Overview

Interactive timezone configuration for Windows devices deployed via Intune. Runs in SYSTEM context but presents a user-facing dialog (via PSADT's user context bridge) where users select their timezone from a curated list of US timezones. Ideal for remote workers, travelers, or devices that need manual timezone assignment.

## Key Features

✅ **Runs as SYSTEM** - Full admin privileges for timezone changes  
✅ **User Interface** - PSADT automatically displays dialog in user context  
✅ **US Timezones Only** - Curated list of 7 common US timezones with friendly names  
✅ **Pre-selection** - Current timezone pre-selected in dropdown  
✅ **Detection Logic** - Marks as "not installed" if timezone changed externally  
✅ **No Drift Correction** - User's manual selection is trusted (won't auto-revert)

## US Timezones Available

| Display Name | Windows ID | Example Cities |
|-------------|------------|----------------|
| **Eastern Time (ET)** | Eastern Standard Time | New York, Miami, Atlanta |
| **Central Time (CT)** | Central Standard Time | Chicago, Dallas, Houston |
| **Mountain Time (MT)** | Mountain Standard Time | Denver, Salt Lake City |
| **Mountain Time - Arizona** | US Mountain Standard Time | Phoenix (no DST) |
| **Pacific Time (PT)** | Pacific Standard Time | Los Angeles, Seattle, Portland |
| **Alaska Time (AKT)** | Alaskan Standard Time | Anchorage |
| **Hawaii-Aleutian Time (HST)** | Hawaiian Standard Time | Honolulu |

## Deployment Requirements

### Intune Win32 App Settings

| Setting | Value |
|---------|-------|
| **Install Command** | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive` |
| **Uninstall Command** | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| **Detection Rule** | Custom script: `Detect-SetTimeZone.ps1` |
| **Run as** | System |
| **Install Behavior** | System |
| **User Experience** | Shows installation progress *(requires user logged in)* |
| **Return Codes** | 0 = Success, 69621 = User cancelled |

### Important: DeployMode Must Be Interactive
```powershell
# ✓ CORRECT - Shows UI to user
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive

# ❌ WRONG - Will fail because dialog can't display
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

## How PSADT Bridges SYSTEM → User Context

This package runs as SYSTEM (required for `Set-TimeZone` permissions) but displays a dialog in the user's session:

```
1. Intune launches: Invoke-AppDeployToolkit.exe (as SYSTEM)
2. Script calls: Show-ADTTimeZoneSelection (still SYSTEM)
3. PSADT internally launches: PSADT.ClientServer.Client.exe (as User)
4. Dialog displays in user's session (User context)
5. User selects timezone → returned to SYSTEM script
6. Set-TimeZone runs as SYSTEM (has permission)
```

No special configuration needed—this is PSADT v4's built-in behavior.

## Testing

### Local Interactive Test
```powershell
# Run as Administrator
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive

# Dialog should appear → select timezone → click OK
# Verify: Get-TimeZone
```

### Test Detection
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Detect-SetTimeZone.ps1
# Expected: Exit 0 if installed
```

## Customization

### Add/Remove Timezones

Edit `PSAppDeployToolkit.Extensions/PSAppDeployToolkit.Extensions.psm1`:

```powershell
$usTimeZones = @(
    @{ Id = 'Eastern Standard Time'; Display = 'Eastern Time (ET) - New York' }
    # Add your own:
    @{ Id = 'Romance Standard Time'; Display = 'Central European Time' }
)
```

## Comparison: User Select vs IP-Based

| Feature | User Select | IP-Based (Auto) |
|---------|-------------|-----------------|
| **User Interaction** | Required | None (silent) |
| **Timezone Source** | User dropdown | ipinfo.io API |
| **Drift Correction** | Manual (re-prompt) | Automatic |
| **Best For** | Remote workers | Fixed-location devices |
| **ESP Timing** | Post-ESP (user logged in) | During ESP (SYSTEM only) |

---

**Need automatic timezone?** Use **PSADT.SetTimeZone.v4** (IP-based) instead.
