# Set Time Zone By IP (PSADT v4)

**Version:** 2.0.0  
**PSADT Version:** 4.1.8  
**Author:** Zachary Hayward  
**Date:** 2026-06-21

## Overview

Automatically configures Windows timezone based on the device's public IP geolocation. Designed for Intune Win32 app deployment with drift detection—when a device roams to a different timezone, the next Intune evaluation cycle detects the change and re-applies the correct timezone.

## What's New in v2.0.0

### ✅ Migrated to PSADT v4.1.8
- Converted from `Deploy-Application.ps1` (v3 syntax) to `Invoke-AppDeployToolkit.ps1` (v4 syntax)
- Uses modern PSADT v4 functions: `Write-ADTLogEntry`, `Copy-ADTFile`, `Remove-ADTFile`, `Close-ADTSession`
- Restructured into `Install-ADTDeployment`, `Uninstall-ADTDeployment`, `Repair-ADTDeployment` functions
- Updated exit codes to 69xxx range per v4 conventions

### 🔒 Security Fixes
1. **HTTP → HTTPS** ([Invoke-AppDeployToolkit.ps1:122](Invoke-AppDeployToolkit.ps1#L122), [Detect-SetTimeZone.ps1:7](Detect-SetTimeZone.ps1#L7))
   - Changed `http://ipinfo.io/json` → `https://ipinfo.io/json`
   - Eliminates man-in-the-middle attack vector for timezone data injection

2. **Consistent Timeouts**
   - Install script: 5 seconds (was 15s)
   - Detect script: 5 seconds (unchanged)
   - Both now use the same value for predictable behavior

3. **Improved Error Logging**
   - Detection script now logs the specific exception when IP lookup or XML parsing fails
   - Better diagnostics for troubleshooting connectivity issues

### 🧹 Cleanup
- Removed unused `Deploy-Settings.ps1` template boilerplate
- Removed nested `PSAppDeployToolkit-3.9.3/` folder (legacy upstream reference)
- XML parsing optimization: added `-First 1` to mapping lookup for early exit

## How It Works

### Installation Flow

1. **Stage Resources**
   - Copies `windowsZones.xml` (Unicode CLDR mappings) to `C:\ProgramData\G1001\TimeZoneByIP\`
   
2. **Detect Location**
   - Queries `https://ipinfo.io/json` → returns IANA timezone (e.g., `America/New_York`)
   
3. **Map to Windows**
   - Parses `windowsZones.xml` to find Windows timezone ID (e.g., `Eastern Standard Time`)
   
4. **Apply**
   - Runs `Set-TimeZone -Id "Eastern Standard Time"`
   - Writes detection marker: `C:\ProgramData\G1001\TimeZoneByIP\install.marker` (JSON)

### Drift Detection

**Every Intune Evaluation Cycle:**
1. `Detect-SetTimeZone.ps1` runs in SYSTEM context
2. Reads marker file → version check passes
3. Queries `https://ipinfo.io/json` for current IANA timezone
4. Maps IANA → Windows timezone via staged `windowsZones.xml`
5. Compares `(Get-TimeZone).Id` to expected timezone
6. **If mismatch:** Returns `Exit 1` → Intune re-runs install → timezone corrects

**Graceful Degradation:**
- **Offline/API failure:** Returns `Exit 0` (installed) to avoid hammering ipinfo.io
- **Missing XML:** Returns `Exit 0` (trust the stamp)
- **Unmapped zone:** Returns `Exit 0` (edge case, log and continue)

### Uninstallation

- Removes marker file and staged XML
- **Does NOT revert timezone** (user's current zone is presumed correct at uninstall time)

## Deployment Requirements

### Intune Win32 App Settings

| Setting | Value |
|---------|-------|
| **Install Command** | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` |
| **Uninstall Command** | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| **Detection Rule** | Custom script: `Detect-SetTimeZone.ps1` |
| **Run as** | System |
| **Install Behavior** | System |
| **Return Codes** | 0 = Success, 1707 = Success |

### Files Included

```
PSADT.SetTimeZone.v4/
├── Invoke-AppDeployToolkit.ps1     # Main deployment script (PSADT v4)
├── Invoke-AppDeployToolkit.exe     # PSADT v4 launcher binary
├── Detect-SetTimeZone.ps1          # Intune detection script
├── Config/
│   └── config.psd1                 # PSADT configuration
├── Files/
│   └── windowsZones.xml            # Unicode CLDR timezone mappings
├── Assets/
│   ├── AppIcon.png
│   └── Banner.Classic.png
└── PSAppDeployToolkit/             # PSADT v4.1.8 module
```

## Exit Codes

| Code | Meaning |
|------|---------|
| **0** | Success (timezone set or already correct) |
| **60008** | Failed to load PSADT module |
| **60001** | Unhandled error in deployment functions |
| **69621** | Bundled `windowsZones.xml` not found |
| **69622** | Failed to stage `windowsZones.xml` to ProgramData |
| **69623** | IP geolocation lookup failed or returned no timezone |
| **69624** | Failed to parse `windowsZones.xml` |
| **69625** | No Windows timezone mapping found for detected IANA zone |
| **69626** | `Set-TimeZone` operation failed |

## Logs

**PSADT Logs:**
```
C:\Windows\Logs\Software\PSAppDeployToolkit\
└── Set Time Zone By IP_2.0.0_<timestamp>_Install.log
```

**Detection Diagnostics:**
- Stdout messages captured by Intune Management Extension logs
- Search for `"Time Zone Configuration"` in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`

## Testing

### Manual Install
```powershell
# Run as Administrator
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

### Test Detection Script
```powershell
# Run as SYSTEM (use PsExec or Intune sandbox)
powershell.exe -ExecutionPolicy Bypass -File .\Detect-SetTimeZone.ps1
# Expected: "INSTALLED: v2.0.0, TZ=<current>, IANA=<detected>" + Exit 0
```

### Simulate Drift
```powershell
# Manually change timezone
Set-TimeZone -Id "Pacific Standard Time"

# Run detection → should report drift and exit 1
powershell.exe -ExecutionPolicy Bypass -File .\Detect-SetTimeZone.ps1
```

## Known Limitations

1. **Rate Limiting**
   - ipinfo.io free tier: 50,000 requests/month
   - Large fleets may need API token: `Invoke-RestMethod -Headers @{ Authorization = "Bearer $token" }`

2. **No VPN Detection**
   - If device is on VPN, ipinfo.io returns VPN exit node location (may not match physical location)

3. **Unmapped Zones**
   - Rare IANA zones not in Unicode CLDR → fallback to "trust the stamp"

## Migration from v1.0.0 (PSADT v3)

If upgrading an existing deployment:
1. Change detection script version check in [Detect-SetTimeZone.ps1:8](Detect-SetTimeZone.ps1#L8) from `'1.0.0'` → `'2.0.0'`
2. Deploy as **supersedence** of the v1.0.0 app in Intune
3. Existing marker files will be detected as version mismatch → automatic reinstall with v2.0.0

## References

- **PSADT v4 Documentation:** https://psappdeploytoolkit.com
- **Unicode CLDR Timezone Mappings:** https://github.com/unicode-org/cldr/blob/main/common/supplemental/windowsZones.xml
- **ipinfo.io API:** https://ipinfo.io/developers

## Changelog

### v2.0.0 (2026-06-21)
- Migrated to PSADT v4.1.8
- Fixed HTTP → HTTPS security issue
- Standardized timeout to 5 seconds
- Improved error logging in detection script
- Removed unused template files
- Optimized XML parsing performance

### v1.0.0 (2026-05-28)
- Initial release with PSADT v3.10.2
- Basic IP-based timezone detection
- Drift detection via Intune Win32 detection script
