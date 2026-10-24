# AWS Session Manager Plugin - PSADT Package

PowerShell App Deployment Toolkit (PSADT) package for deploying AWS Session Manager Plugin via Microsoft Intune.

## Package Information

| Property | Value |
|---|---|
| **Application** | AWS Session Manager Plugin |
| **Vendor** | Amazon Web Services |
| **Version** | Latest (dynamically downloaded) |
| **Architecture** | x64 |
| **Package Type** | PSADT v4 |
| **Installation Type** | EXE (silent) |
| **Created** | 2026-07-22 |
| **Author** | DWX Team |

## Description

The AWS Session Manager Plugin is a client-side tool that enables AWS Systems Manager Session Manager connections from the AWS CLI. This package:

- **Downloads the installer dynamically** from AWS official distribution URL
- **Installs silently** using native silent switches (`/S`)
- **Verifies installation** by checking the plugin executable and version
- **Supports uninstall and repair** operations
- **Self-contained** — no pre-downloaded installer files required

## Prerequisites

### Target Systems
- Windows 10 (64-bit) or later
- Windows Server 2016 or later
- Administrator rights (required for installation)

### AWS CLI
- AWS CLI version 1.16.12 or later must be installed separately
- The Session Manager Plugin extends AWS CLI functionality

### Network Requirements
- Internet connectivity to download from:
  - `https://s3.amazonaws.com/session-manager-downloads/`

## Installation

### Via Intune (Recommended)

1. **Package the application:**
   ```powershell
   # From the PSADT.AWS.SessionManager folder
   IntuneWinAppUtil.exe -c . -s Invoke-AppDeployToolkit.exe -o ..\
   ```

2. **Create Win32 app in Intune:**
   - **Name:** AWS Session Manager Plugin
   - **Description:** AWS Systems Manager Session Manager plugin for AWS CLI
   - **Publisher:** Amazon Web Services
   - **App version:** Latest
   - **Install command:**
     ```
     Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
     ```
   - **Uninstall command:**
     ```
     Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
     ```

3. **Detection rule:**
   - **Rule type:** Custom script
   - **Script file:** `Detect-AWSSessionManager.ps1`

4. **Requirements:**
   - **Operating system:** Windows 10 1607+ (64-bit)
   - **Disk space:** 100 MB

5. **Return codes:**
   - **Success:** 0
   - **Soft reboot:** 1641, 3010
   - **Hard reboot:** N/A
   - **Failure:** Any other code

### Manual Installation (Testing)

```powershell
# Install
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

# Uninstall
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent

# Repair
.\Invoke-AppDeployToolkit.exe -DeploymentType Repair -DeployMode Silent
```

## Installation Details

### What Gets Installed

| Component | Path |
|---|---|
| **Plugin Executable** | `C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe` |
| **Installation Directory** | `C:\Program Files\Amazon\SessionManagerPlugin\` |

### Installation Process

1. **Pre-Installation**
   - Checks for existing AWS Session Manager Plugin installation
   - Removes previous version if found

2. **Installation**
   - Downloads `SessionManagerPluginSetup.exe` from AWS S3
   - Installs silently with `/S` parameter
   - Installer automatically adds plugin to system PATH

3. **Post-Installation**
   - Verifies executable exists at expected path
   - Tests plugin by running `--version` command
   - Cleans up downloaded installer from temp directory

### Download Source

The installer is downloaded from AWS official distribution:

```
https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe
```

**Note:** The package always downloads the latest version at installation time, ensuring users get the most recent stable release.

## Detection Logic

The `Detect-AWSSessionManager.ps1` script checks:

1. **File existence:** Verifies `session-manager-plugin.exe` exists in Program Files
2. **Functional test:** Runs `session-manager-plugin.exe --version` to confirm the plugin works
3. **Exit codes:**
   - `0` = Detected (installed and functional)
   - `1` = Not detected or not functional

## Usage After Installation

### Verify Installation

```powershell
# Check plugin version
session-manager-plugin --version

# Check PATH includes plugin
$env:Path -split ';' | Select-String 'SessionManagerPlugin'
```

### Start Session Manager Session

```powershell
# Connect to EC2 instance via Session Manager
aws ssm start-session --target i-1234567890abcdef0

# Connect with port forwarding
aws ssm start-session --target i-1234567890abcdef0 `
    --document-name AWS-StartPortForwardingSession `
    --parameters "portNumber=3389,localPortNumber=13389"
```

## Troubleshooting

### Installation Issues

**Problem:** Download fails
- **Cause:** Network connectivity or AWS S3 access blocked
- **Solution:** Verify internet connectivity and firewall rules allow access to `s3.amazonaws.com`

**Problem:** Installation fails with exit code other than 0
- **Cause:** Installer error or insufficient permissions
- **Solution:**
  1. Check PSADT logs in `C:\Windows\Logs\Software`
  2. Verify administrator rights
  3. Try manual installation to see detailed error messages

**Problem:** Detection script fails after successful installation
- **Cause:** PATH not updated or plugin not functional
- **Solution:**
  1. Verify `C:\Program Files\Amazon\SessionManagerPlugin\bin` exists
  2. Check if `session-manager-plugin.exe` is present
  3. Restart PowerShell or log off/on to refresh PATH

### Runtime Issues

**Problem:** `aws ssm start-session` returns "SessionManagerPlugin is not found"
- **Cause:** AWS CLI cannot locate the plugin
- **Solution:**
  ```powershell
  # Check AWS CLI version (must be 1.16.12+)
  aws --version

  # Check plugin in PATH
  where.exe session-manager-plugin

  # Manually add to PATH if needed (temporary)
  $env:Path += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"
  ```

**Problem:** Session connection fails
- **Cause:** IAM permissions, instance configuration, or network
- **Solution:** See [AWS Session Manager troubleshooting](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-troubleshooting.html)

## PSADT Logs

Installation logs are written to:

```
C:\Windows\Logs\Software\Amazon Web Services_AWS Session Manager Plugin_Latest_01_PSAppDeployToolkit_Install.log
```

Log includes:
- Download progress and file size
- Installation command and exit code
- Version verification results
- All PSADT operations and status messages

## Package Structure

```
PSADT.AWS.SessionManager/
├── Assets/                          # Icons, branding (empty for this package)
├── Config/                          # PSADT configuration (uses defaults)
├── Files/                           # Empty - installer downloaded at runtime
├── PSAppDeployToolkit/              # PSADT framework files
│   ├── Frontend/
│   │   ├── v3/                      # Legacy v3 support
│   │   └── v4/                      # Current v4 framework
│   └── PSGetModuleInfo.xml
├── PSAppDeployToolkit.Extensions/   # Custom extensions (none required)
├── Strings/                         # Localization (uses defaults)
├── SupportFiles/                    # Additional scripts (empty)
├── Detect-AWSSessionManager.ps1     # Intune detection script
├── Invoke-AppDeployToolkit.exe      # PSADT executable wrapper
├── Invoke-AppDeployToolkit.ps1      # Main deployment script
└── README.md                        # This file
```

## Version History

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-07-22 | Initial package creation with dynamic download |

## References

- [AWS Session Manager Plugin Installation Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- [PSAppDeployToolkit Documentation](https://psappdeploytoolkit.com)
- [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Session Manager Prerequisites](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html)

## Support

For issues with this PSADT package, contact the DWX Team.

For AWS Session Manager Plugin issues, see AWS documentation or AWS Support.
