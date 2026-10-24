# 1Password - PSADT v4.1.8 Win32 App

Downloads and installs the current release of 1Password at deployment time.

Built with **PSAppDeployToolkit v4.1.8**, modelled on the `PSADT.Kiro.IDE` template and
the `PSADT.AWSCLIv2.conversion` evergreen-MSI pattern.


## Overview

| | |
|---|---|
| **Package** | `PSADT.1Password.conversion` |
| **Vendor** | AgileBits |
| **Architecture** | x64 |
| **Category** | Utilities |
| **Install context** | System (machine-wide) |
| **Installer type** | MSI |
| **Silent switches** | _(PSADT applies `/qn` and logging)_ |
| **Replaces (legacy)** | _(none)_ |
| **Supersedes Intune app(s)** | _(none recorded)_ |

Evergreen machine-wide MSI from the official 1Password CDN. The machine-wide MSI installs
per-device (not per-user), which is what Intune system-context deployment requires.

## How the installer is obtained

1. If any `.msi`, `.exe` or `.zip` file is present in `Files\`, that file is used.
2. Otherwise: direct evergreen download from
   `https://downloads.1password.com/win/1PasswordSetup-latest.msi`.

The download lands in the PSADT-managed support-files folder and is cleaned up with the
session, so nothing is left behind on the device.

## Offline / air-gapped use

Drop the vendor MSI into `Files\` before building the `.intunewin`. The package then
installs without any outbound network access and the resolver is never called.

## Test group requirement

App assignment changes affect every targeted device and user. Before widening an
assignment:

1. Assign to the **DWX application pilot group** only.
2. Confirm install, detection and uninstall on at least one device per supported Windows build.
3. Review `C:\Windows\Logs\Software\1Password (Latest)_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.1Password.conversion" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: 1Password (Latest)
- **Publisher**: AgileBits
- **Category**: Utilities

### Program

**Install command**

```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

**Uninstall command**

```cmd
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
```

- **Install behavior**: System
- **Device restart behavior**: Determine behavior based on return codes

### Requirements

- **Operating system architecture**: 64-bit
- **Minimum operating system**: Windows 10 1809 or later
- **Network**: outbound HTTPS to `downloads.1password.com` (unless using the `Files\` offline path)

### Detection rules

- **Rules format**: Use a custom detection script
- **Script file**: `Detect-1Password.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: Uninstall registry `DisplayName` matches `1Password`

### Uninstall behaviour

Registered uninstall string for `DisplayName` matching `1Password`

## Logging

```
C:\Windows\Logs\Software\1Password (Latest)_Latest_<DeploymentType>_<timestamp>.log
```

## Update strategy

This package is evergreen: each run resolves and installs whatever the vendor currently
publishes at the `-latest.msi` URL. To push an update, trigger a sync or re-assign in
Intune - the package itself does not need to be rebuilt.

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails immediately | PSADT log under `C:\Windows\Logs\Software\`; confirm outbound HTTPS and proxy/TLS inspection allow `downloads.1password.com` |
| "Resolved an empty download URL" | Vendor changed their endpoint. Update the resolver URL in `app-config-1password.json` and the install script |
| "post-install verification failed" | The MSI registered a different `DisplayName` than detection expects. Compare the log against the `1Password` pattern |
| Detection never reports installed | Run `Detect-1Password.ps1` manually on the device and check its exit code |

## Support

DWX Endpoint Management team

## Version history

- **v1.0.0** (2026-10-02) - Initial release. Evergreen machine-wide MSI download, PSADT v4.1.8.
