# PSADT v3 → v4 Conversion Summary

## Files Changed/Created

### Core Deployment Files
- ✅ **Invoke-AppDeployToolkit.ps1** (NEW) - Converted from `Deploy-Application.ps1`
  - Migrated to v4 function structure: `Install-ADTDeployment`, `Uninstall-ADTDeployment`, `Repair-ADTDeployment`
  - Updated all toolkit calls to v4 syntax (`Write-ADTLogEntry`, `Copy-ADTFile`, etc.)
  - Changed exit codes to 69xxx range (v4 convention)
  
- ✅ **Detect-SetTimeZone.ps1** (UPDATED)
  - Fixed HTTP → HTTPS security issue
  - Updated version check to `2.0.0`
  - Added exception logging for diagnostics

### Configuration
- ✅ **Config/config.psd1** (NEW) - PSADT v4 configuration
  - Set `CompanyName = 'Group 1001'`
  - Disabled balloon notifications (silent deployment)
  - Standard logging paths

### Module Files
- ✅ **PSAppDeployToolkit/** - PSADT v4.1.8 module copied from template
- ✅ **Invoke-AppDeployToolkit.exe** - v4 launcher binary
- ✅ **Assets/** - AppIcon.png, Banner.Classic.png

### Data Files
- ✅ **Files/windowsZones.xml** - Unicode CLDR mappings (unchanged)

### Documentation
- ✅ **README.md** - Comprehensive deployment guide
- ✅ **CONVERSION_NOTES.md** - This file

## Security Fixes Applied

### 1. HTTP → HTTPS (Critical)
**Old (v3):**
```powershell
$ipInfoUrl = 'http://ipinfo.io/json'  # ⚠️ Insecure
```

**New (v4):**
```powershell
$ipInfoUrl = 'https://ipinfo.io/json'  # ✓ Secure
```

**Impact:** Eliminates MITM attack vector for timezone data injection.

### 2. Consistent Timeouts
**Old (v3):**
- Install: 15 seconds
- Detect: 5 seconds

**New (v4):**
- Install: 5 seconds ✓
- Detect: 5 seconds ✓

**Impact:** Predictable behavior, faster failure on connectivity issues.

### 3. Enhanced Error Logging
**Old (v3):**
```powershell
Try {
    $ianaTz = (Invoke-RestMethod ...).timezone
} Catch { }  # Silent failure
```

**New (v4):**
```powershell
Try {
    $ianaTz = (Invoke-RestMethod ...).timezone
} Catch {
    [Console]::WriteLine("IP lookup failed: $($_.Exception.Message)")
}
```

**Impact:** Better diagnostics for troubleshooting.

## Code Improvements

### 1. XML Parsing Optimization
**Old (v3):**
```powershell
$mapping = $windowsZones.supplementalData.windowsZones.mapTimezones.mapZone | Where-Object {
    $_.type -split ' ' -contains $ianaTz
}
$windowsTZ = $mapping.other | Select-Object -First 1
```

**New (v4):**
```powershell
$mapping = $windowsZones.supplementalData.windowsZones.mapTimezones.mapZone | Where-Object {
    $_.type -split ' ' -contains $ianaTz
} | Select-Object -First 1

$windowsTZ = $mapping.other
```

**Impact:** Early exit from pipeline, minor performance gain.

### 2. Removed Unused Files
- ❌ `Deploy-Settings.ps1` (unused template boilerplate)
- ❌ `PSAppDeployToolkit-3.9.3/` (legacy nested reference)
- ❌ `Install-Application.cmd` (v3 batch wrapper, not needed in v4)

## PSADT v3 → v4 Syntax Changes

| v3 Syntax | v4 Syntax |
|-----------|-----------|
| `Write-Log -Message "..." -Severity 1` | `Write-ADTLogEntry -Message "..." -Severity 1` |
| `Copy-File -Path ... -Destination ...` | `Copy-ADTFile -Path ... -Destination ...` |
| `Remove-File -Path ...` | `Remove-ADTFile -Path ...` |
| `Remove-Folder -Path ...` | `Remove-ADTFolder -Path ...` |
| `Exit-Script -ExitCode ...` | `Close-ADTSession -ExitCode ...` |
| `$dirFiles` | `"$PSScriptRoot\Files"` |
| `$envProgramData` | `$env:ProgramData` |

## Testing Checklist

Before deploying to production:

- [ ] **Syntax Validation**
  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent
  ```

- [ ] **Detection Script**
  ```powershell
  # Run as SYSTEM
  powershell.exe -ExecutionPolicy Bypass -File .\Detect-SetTimeZone.ps1
  ```

- [ ] **HTTPS Verification**
  - Confirm Wireshark shows TLS traffic to ipinfo.io, not plaintext HTTP

- [ ] **Drift Simulation**
  ```powershell
  Set-TimeZone -Id "Pacific Standard Time"  # Change manually
  .\Detect-SetTimeZone.ps1                  # Should detect drift (Exit 1)
  .\Invoke-AppDeployToolkit.exe ...         # Should correct timezone
  ```

- [ ] **Offline Behavior**
  - Disconnect network → run detection → should return Exit 0 (graceful fallback)

- [ ] **Log Review**
  - Check `C:\Windows\Logs\Software\PSAppDeployToolkit\Set Time Zone By IP_2.0.0_*_Install.log`
  - Verify HTTPS requests logged correctly
  - Confirm no v3 function calls in logs

## Deployment Rollout Plan

### Phase 1: Pilot (10 devices)
- Deploy to test group with mix of locations
- Monitor for 1 week
- Verify timezone accuracy and log quality

### Phase 2: Ring 1 (100 devices)
- Expand to early adopters
- Collect feedback on detection reliability

### Phase 3: Ring 2 (1000 devices)
- Deploy to broader user base
- Monitor ipinfo.io rate limits

### Phase 4: Production (All devices)
- Full rollout
- Supersede v1.0.0 PSADT v3 deployment

## Rollback Plan

If v4 deployment fails:

1. **Intune:** Change assignment to uninstall PSADT.SetTimeZone.v4
2. **Redeploy v3:** Revert to PSADT-SetTimeZone (v1.0.0) with HTTP→HTTPS fix
3. **Root Cause:** Review logs at `C:\Windows\Logs\Software\PSAppDeployToolkit\`

## Rate Limit Mitigation (Future Enhancement)

If ipinfo.io rate limits become an issue:

1. **Get API Token:**
   ```powershell
   # Sign up at https://ipinfo.io/signup
   $headers = @{ Authorization = "Bearer YOUR_TOKEN_HERE" }
   $ianaTz = (Invoke-RestMethod -Uri $script:ipInfoUrl -Headers $headers).timezone
   ```

2. **Store Token Securely:**
   - Option A: Azure Key Vault (retrieve via managed identity)
   - Option B: Intune PowerShell script variable (less secure)

3. **Alternative Providers:**
   - ip-api.com (no auth required, 45 req/min free)
   - ipapi.co (30k req/month free)

## References

- **PSADT v4 Migration Guide:** https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/wiki/Migrating-to-v4
- **v3 to v4 Function Mapping:** https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/wiki/Function-Renames
- **ipinfo.io Rate Limits:** https://ipinfo.io/pricing

---

**Converted By:** Claude (Sonnet 4.5)  
**Conversion Date:** 2026-06-21  
**Original v3 Package:** `dwx-automation-cli-scripts/intune-apps/PSADT-SetTimeZone/`
