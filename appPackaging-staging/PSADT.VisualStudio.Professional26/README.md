# Visual Studio Professional 2026 - PSADT v4 Intune Package

## Overview

This package deploys **Microsoft Visual Studio Professional 2026** using PowerShell App Deployment Toolkit (PSADT) v4.1.8 for Intune Win32 app deployment.

**Status:** WIP (Work in Progress)

---

## Package Contents

```
PSADT.VisualStudio.Professional26/
├── README.md                           # This file
├── Detect-VisualStudioProfessional26.ps1  # Intune detection script
├── Invoke-AppDeployToolkit.ps1         # Main PSADT deployment script
├── Invoke-AppDeployToolkit.exe         # PSADT wrapper executable
├── template-version.txt                # PSADT version (4.1.8)
├── Assets/                             # PSADT UI assets
├── Config/                             # PSADT configuration
├── Files/                              # Installer location (place vs_Professional.exe here)
├── PSAppDeployToolkit/                 # PSADT v4 module
├── PSAppDeployToolkit.Extensions/      # PSADT extensions
├── Strings/                            # PSADT localization
└── SupportFiles/                       # PSADT supporting files
```

---

## Application Details

- **Application Name:** Visual Studio Professional 2026
- **Vendor:** Microsoft
- **Version:** 17.0 (Visual Studio 2026 uses internal version 17.x)
- **Architecture:** x64
- **Installer Type:** EXE (vs_Professional.exe bootstrapper)
- **Installation Mode:** Silent with customizable workloads
- **Default Workloads Included:**
  - `Microsoft.VisualStudio.Workload.ManagedDesktop` - .NET desktop development
  - `Microsoft.VisualStudio.Workload.NetWeb` - ASP.NET and web development
  - Recommended components included via `--includeRecommended`

---

## Detection Method

**Detection Script:** `Detect-VisualStudioProfessional26.ps1`

The detection script uses a dual-check approach:

1. **Registry Detection:** Searches Windows uninstall registry keys for Visual Studio Professional 2026
   - Paths checked:
     - `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
     - `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*`
   - Pattern match: `Visual Studio Professional.*26` or `Visual Studio Professional 2026`

2. **File-Based Detection:** Verifies Visual Studio installation path
   - File checked: `C:\Program Files\Microsoft Visual Studio\2026\Professional\Common7\IDE\devenv.exe`
   - Version validated from file properties

**Exit Codes:**
- `0` = Application is installed (passes detection)
- `1` = Application not detected (requires installation)

---

## Installation Details

### Installation Command (Intune)

```
Invoke-AppDeployToolkit.exe -DeploymentType "Install" -DeployMode "Silent"
```

### Installation Behavior

1. **Pre-Installation:**
   - Shows welcome dialog (if interactive mode)
   - Closes running Visual Studio processes:
     - `devenv.exe` (Visual Studio IDE)
     - `MSBuild.exe` (Build engine)
     - `vbcscompiler.exe` (Roslyn compiler)
     - `PerfWatson2.exe` (Telemetry)
     - `ServiceHub.Host.dotnet.x64.exe` (Service host)
     - `ServiceHub.RoslynCodeAnalysisService.exe` (Code analysis)
   - Allows up to 3 user deferrals
   - Checks available disk space
   - Displays installation progress

2. **Installation:**
   - Executes `vs_Professional.exe` with silent parameters:
     - `--quiet` - Silent installation
     - `--wait` - Wait for completion
     - `--norestart` - Suppress automatic restart
     - `--nocache` - Don't cache installer files
     - `--add [workload-id]` - Adds specified workloads
     - `--includeRecommended` - Includes recommended components

3. **Post-Installation:**
   - Logs completion
   - (Optional) Display completion message in interactive mode

### Customizing Workloads

Edit `Invoke-AppDeployToolkit.ps1` lines 166-174 to add or remove workloads:

```powershell
$installArgs = @(
    '--quiet'
    '--wait'
    '--norestart'
    '--nocache'
    '--add', 'Microsoft.VisualStudio.Workload.ManagedDesktop'      # .NET desktop
    '--add', 'Microsoft.VisualStudio.Workload.NetWeb'               # ASP.NET web
    '--add', 'Microsoft.VisualStudio.Workload.Azure'                # Azure development
    '--add', 'Microsoft.VisualStudio.Workload.Python'               # Python development
    '--includeRecommended'
)
```

**Common Workload IDs:**
- `Microsoft.VisualStudio.Workload.ManagedDesktop` - .NET desktop development
- `Microsoft.VisualStudio.Workload.NetWeb` - ASP.NET and web development
- `Microsoft.VisualStudio.Workload.Azure` - Azure development
- `Microsoft.VisualStudio.Workload.Python` - Python development
- `Microsoft.VisualStudio.Workload.NativeDesktop` - C++ desktop development
- `Microsoft.VisualStudio.Workload.Universal` - Universal Windows Platform development
- `Microsoft.VisualStudio.Workload.Data` - Data storage and processing
- `Microsoft.VisualStudio.Workload.Office` - Office/SharePoint development

For a complete list, see: https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-professional

---

## Uninstallation Details

### Uninstall Command (Intune)

```
Invoke-AppDeployToolkit.exe -DeploymentType "Uninstall" -DeployMode "Silent"
```

### Uninstall Behavior

1. **Pre-Uninstallation:**
   - Closes running Visual Studio processes (60 second countdown)
   - Displays uninstallation progress

2. **Uninstallation:**
   - Uses the Visual Studio Installer to remove the application
   - Attempts installed VS Installer first: `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe`
   - Falls back to packaged installer if available: `Files\vs_Professional.exe`
   - Uninstall parameters:
     - `uninstall` - Uninstall command
     - `--installPath` - Target installation path
     - `--quiet` - Silent mode
     - `--wait` - Wait for completion
     - `--norestart` - Suppress restart

3. **Post-Uninstallation:**
   - Logs completion

---

## Deployment Requirements

### System Requirements

- **Operating System:** Windows 10 version 1809 or later / Windows 11
- **Architecture:** 64-bit (x64)
- **Disk Space:** Minimum 50 GB free (varies by workloads selected)
- **RAM:** Minimum 8 GB (16 GB recommended)
- **Administrator Rights:** Required
- **Internet Connection:** Required during installation (for component downloads)

### Intune Configuration

1. **App Information:**
   - Name: `Visual Studio Professional 2026 (WIP)`
   - Description: `Microsoft Visual Studio Professional 2026 IDE for enterprise software development`
   - Publisher: `Microsoft`
   - Category: `Developer Tools`

2. **Program:**
   - Install command: `Invoke-AppDeployToolkit.exe -DeploymentType "Install" -DeployMode "Silent"`
   - Uninstall command: `Invoke-AppDeployToolkit.exe -DeploymentType "Uninstall" -DeployMode "Silent"`
   - Install behavior: `System`
   - Device restart behavior: `Determine behavior based on return codes`

3. **Requirements:**
   - Operating system architecture: `64-bit`
   - Minimum operating system: `Windows 10 1809`
   - Disk space required: `50000 MB` (50 GB)
   - Physical memory required: `8192 MB` (8 GB)
   - Processor speed: `1.8 GHz or faster`

4. **Detection Rules:**
   - Rule type: `Use a custom detection script`
   - Script file: Upload `Detect-VisualStudioProfessional26.ps1`
   - Run script as 32-bit process on 64-bit clients: `No`
   - Enforce script signature check: `No`

5. **Return Codes:**
   - `0` = Success
   - `1707` = Success
   - `3010` = Soft reboot
   - `1641` = Hard reboot
   - `1618` = Retry

---

## Pre-Deployment Checklist

Before deploying this package:

- [ ] Download Visual Studio Professional 2026 bootstrapper (`vs_Professional.exe`) from Microsoft
- [ ] Place `vs_Professional.exe` in the `Files\` folder
- [ ] Verify workload selections match organizational requirements
- [ ] Test installation locally (see Testing Instructions below)
- [ ] Test detection script before and after installation
- [ ] Test under SYSTEM context using PSExec
- [ ] Package using Microsoft Win32 Content Prep Tool
- [ ] Test deployment to pilot group in Intune
- [ ] Monitor initial deployments for errors
- [ ] Validate Visual Studio launches successfully post-installation

---

## Testing Instructions

### Local Testing (Before Intune Upload)

#### 1. Place Installer File

```powershell
# Download vs_Professional.exe from Microsoft and copy to Files folder
Copy-Item "C:\path\to\vs_Professional.exe" "c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.VisualStudio.Professional26\Files\"
```

#### 2. Test Detection Script (Before Installation)

```powershell
cd c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.VisualStudio.Professional26
.\Detect-VisualStudioProfessional26.ps1
# Expected: "Visual Studio Professional 26 not detected", Exit Code: 1
```

#### 3. Test Installation (PowerShell Method)

```powershell
# Run PSADT deployment
.\Invoke-AppDeployToolkit.ps1 -DeploymentType "Install" -DeployMode "Silent"
```

#### 4. Test Installation (EXE Wrapper Method)

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType "Install" -DeployMode "Silent"
```

#### 5. Test Detection Script (After Installation)

```powershell
.\Detect-VisualStudioProfessional26.ps1
# Expected: "Visual Studio Professional 26 is installed - Version: 17.x", Exit Code: 0
```

#### 6. Test Under SYSTEM Context

```powershell
# Download PSExec from Sysinternals if not installed
# Run detection and installation as SYSTEM (how Intune executes)
psexec -i -s powershell.exe

# Inside SYSTEM PowerShell session:
cd c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.VisualStudio.Professional26
.\Detect-VisualStudioProfessional26.ps1
# Should detect if installed

# Test installation under SYSTEM
.\Invoke-AppDeployToolkit.exe -DeploymentType "Install" -DeployMode "Silent"
exit
```

#### 7. Verify Visual Studio Launches

```powershell
# Launch Visual Studio after installation
Start-Process "C:\Program Files\Microsoft Visual Studio\2026\Professional\Common7\IDE\devenv.exe"
```

#### 8. Review PSADT Logs

```powershell
# Check installation logs
Get-ChildItem "C:\Windows\Logs\PSAppDeployToolkit\" -Recurse -File | 
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-2) } |
    Get-Content -Tail 50
```

---

## Packaging for Intune

### Using Microsoft Win32 Content Prep Tool

```powershell
# Download IntuneWinAppUtil.exe from:
# https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool

# Package the entire PSADT folder
.\IntuneWinAppUtil.exe `
    -c "c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.VisualStudio.Professional26" `
    -s "Invoke-AppDeployToolkit.ps1" `
    -o "c:\temp\intunewin" `
    -q

# Output: VisualStudio-Professional-26-PSADT4.intunewin
```

---

## Known Issues & Limitations

1. **Internet Required:** Visual Studio installation requires an active internet connection to download components during installation
2. **Large Download Size:** Installation may download several gigabytes of components depending on workloads selected
3. **Installation Time:** Installation can take 30-60 minutes depending on selected workloads and network speed
4. **Disk Space:** Visual Studio requires significant disk space; verify target devices meet minimum requirements
5. **Reboot May Be Required:** Some installations may require a system restart to complete
6. **Version Number:** Visual Studio 2026 uses internal version 17.x for versioning

---

## Troubleshooting

### Issue: Detection Script Fails in Intune (Works Locally)

**Cause:** Running in different security context

**Resolution:**
- Test detection script under SYSTEM context using PSExec
- Verify registry paths are accessible from SYSTEM account
- Check PSADT logs in `C:\Windows\Logs\PSAppDeployToolkit\`

### Issue: Installation Fails with Error 1618

**Cause:** Another installation is in progress

**Resolution:**
- Retry deployment after other installations complete
- Check if Windows Update is running
- Configure retry logic in Intune (default return code 1618 = retry)

### Issue: Installation Fails with Insufficient Disk Space

**Cause:** Target device doesn't meet minimum disk space requirements

**Resolution:**
- Verify devices meet 50 GB minimum free space
- Adjust requirements in Intune app settings
- Clean up disk space on target devices

### Issue: Workload Not Installed

**Cause:** Incorrect workload ID or network connectivity issue

**Resolution:**
- Verify workload ID is correct (see Microsoft documentation)
- Check internet connectivity during installation
- Review PSADT logs for specific error messages

---

## Support & Maintenance

**Package Owner:** DWX Team  
**Created:** 2026-07-08  
**Last Updated:** 2026-07-08  
**PSADT Version:** 4.1.8  
**Status:** WIP (Work in Progress)

### Change Log

| Date | Version | Changes |
|---|---|---|
| 2026-07-08 | 1.0.0 | Initial package creation with PSADT v4.1.8 scaffold |

---

## Additional Resources

- [Visual Studio 2026 Documentation](https://learn.microsoft.com/en-us/visualstudio/)
- [Visual Studio Workload and Component IDs](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-professional)
- [Visual Studio Administrator Guide](https://learn.microsoft.com/en-us/visualstudio/install/visual-studio-administrator-guide)
- [PSADT Documentation](https://psappdeploytoolkit.com/)
- [Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)

---

## License

Microsoft Visual Studio Professional 2026 requires appropriate licensing. Ensure your organization has valid Visual Studio Professional licenses before deployment.
