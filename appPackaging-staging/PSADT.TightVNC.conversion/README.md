# TightVNC - PSADT v4.1.8 Win32 App

Downloads and installs the current release of TightVNC at deployment time.

Built with **PSAppDeployToolkit v4.1.8**, generated from the
`PSADT.Kiro.IDE` template by `new.psadt-package.ps1`.

> **Download URL not verified.** The URL in this package has not been confirmed against a
> live vendor endpoint. Validate it before assigning the app, or stage the installer in
> `Files\` to use the offline path. See *Offline / air-gapped use* below.

## Overview

| | |
|---|---|
| **Package** | `PSADT.TightVNC.conversion` |
| **Vendor** | GlavSoft |
| **Architecture** | x64 |
| **Category** | Remote Access |
| **Install context** | System |
| **Installer type** | MSI |
| **Silent switches** | `ALLUSERS=1` `ADDLOCAL=Viewer` |
| **Replaces (legacy)** | `legacy.Andretti_Installs` |

OFFLINE-ONLY package. Confirmed by probe: tightvnc.com returns HTTP 403 to scripted clients. SECURITY: this package installs the Viewer only (ADDLOCAL=Viewer) so it does not open a listening remote-control service. Adding ADDLOCAL=Server requires a security review and a server password policy.

## How the installer is obtained

1. If any `.msi`, `.exe` or `.zip` file is present in `Files\`, that file is used.
2. Otherwise: **No automated download.** This vendor blocks scripted downloads, so the installer must be staged in `Files\` manually. Obtain it from https://www.tightvnc.com/download.php

The download lands in the PSADT-managed support-files folder and is cleaned up with the
session, so nothing is left behind on the device.

## Offline / air-gapped use

Drop the vendor installer into `Files\` before building the `.intunewin`. The package
then installs without any outbound network access and the resolver is never called.

## Test group requirement

App assignment changes affect every targeted device and user. Before widening an
assignment:

1. Assign to the **DWX application pilot group** only.
2. Confirm install, detection and uninstall on at least one device per supported Windows build.
3. Review `C:\Windows\Logs\Software\TightVNC (Latest)_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.TightVNC.conversion" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: TightVNC (Latest)
- **Publisher**: GlavSoft
- **Category**: Remote Access

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
- **Network**: outbound HTTPS to the vendor download host (unless using the `Files\` offline path)

### Detection rules

- **Rules format**: Use a custom detection script
- **Script file**: `Detect-TightVNC.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: Uninstall registry `DisplayName` matches `TightVNC`

### Uninstall behaviour

Registered uninstall string for `DisplayName` matching `TightVNC`

## Logging

```
C:\Windows\Logs\Software\TightVNC (Latest)_Latest_<DeploymentType>_<timestamp>.log
```

## Update strategy

This package is evergreen: each run resolves and installs whatever the vendor currently
publishes. To push an update, trigger a sync or re-assign in Intune - the package itself
does not need to be rebuilt.

Exception: resolvers of type `PinnedUrl` do **not** auto-resolve. For those, update the
URL in `psadt-app-catalog.json` and regenerate:

```powershell
.\new.psadt-package.ps1 -PackageName 'PSADT.TightVNC.conversion' -Force
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails immediately | PSADT log under `C:\Windows\Logs\Software\`; confirm outbound HTTPS and proxy/TLS inspection allow the vendor host |
| "Resolved an empty download URL" | Vendor changed their endpoint or index layout. Update the resolver in the catalog and regenerate |
| "post-install verification failed" | The silent switches installed to a different path than detection expects. Compare the log's install path against the detection path |
| Detection never reports installed | Run `Detect-TightVNC.ps1` manually on the device and check its exit code |

## Support

DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version history

- **v1.0.0** (2026-09-18) - Initial generated release. Evergreen download, PSADT v4.1.8.
