# DLIllustr - PSADT v4.1.8 Win32 App

Downloads and installs the current release of DLIllustr at deployment time.

Built with **PSAppDeployToolkit v4.1.8**, generated from the
`PSADT.Kiro.IDE` template by `new.psadt-package.ps1`.

> **Download URL not verified.** The URL in this package has not been confirmed against a
> live vendor endpoint. Validate it before assigning the app, or stage the installer in
> `Files\` to use the offline path. See *Offline / air-gapped use* below.

## Overview

| | |
|---|---|
| **Package** | `PSADT.DLIllustr` |
| **Vendor** | Delaware Life |
| **Architecture** | x64 |
| **Category** | Business & Collaboration |
| **Install context** | System |
| **Installer type** | MSI |
| **Silent switches** | `ALLUSERS=1` |
| **Replaces (legacy)** | `legacy.DL_illustr` |

OFFLINE-ONLY / INTERNAL. Base DLIllustr product (NOT the Nautilus variant). Current staged media: 'DLIllustr v3.8.0.msi' - ProductName 'DLIllustr v3.8.0', ProductCode {A1DC44AA-97D8-42DA-876C-19275D3AA52D}, UpgradeCode {05B7485E-D6EE-4E89-AE77-E8A26E73B617}, Manufacturer 'Delaware Life', v3.8.0. InstallShield MSI (ARPNOMODIFY=1, built-in downgrade block), installs silently via msiexec with ALLUSERS=1. ProductName embeds the version so detection is '^DLIllustr v' (DisplayName) - this intentionally excludes 'Nautilus-DLIllustr'. For an exact-version gate in Intune use ProductCode {A1DC44AA-97D8-42DA-876C-19275D3AA52D}. The legacy.DL_illustr routine also removed a stale InstallShield key and uninstalled prior versions first; add that cleanup to the package if the fleet still has older builds. No public download URL - media must be staged in Files\.

## How the installer is obtained

1. If any `.msi`, `.exe` or `.zip` file is present in `Files\`, that file is used.
2. Otherwise: **No automated download.** This vendor blocks scripted downloads, so the installer must be staged in `Files\` manually. Obtain it from DLIllustr is an internal Delaware Life / Group 1001 illustration tool (DocsCorp DocsCorp-derived InstallShield MSI) with no public download URL. Obtain the current 'DLIllustr v<version>.msi' from the internal software distribution share and stage it in the package Files folder.

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
3. Review `C:\Windows\Logs\Software\DLIllustr (Latest)_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.DLIllustr" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: DLIllustr (Latest)
- **Publisher**: Delaware Life
- **Category**: Business & Collaboration

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
- **Script file**: `Detect-DLIllustr.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: Uninstall registry `DisplayName` matches `^DLIllustr v`

### Uninstall behaviour

Registered uninstall string for `DisplayName` matching `^DLIllustr v`

## Logging

```
C:\Windows\Logs\Software\DLIllustr (Latest)_Latest_<DeploymentType>_<timestamp>.log
```

## Update strategy

This package is evergreen: each run resolves and installs whatever the vendor currently
publishes. To push an update, trigger a sync or re-assign in Intune - the package itself
does not need to be rebuilt.

Exception: resolvers of type `PinnedUrl` do **not** auto-resolve. For those, update the
URL in `psadt-app-catalog.json` and regenerate:

```powershell
.\new.psadt-package.ps1 -PackageName 'PSADT.DLIllustr' -Force
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails immediately | PSADT log under `C:\Windows\Logs\Software\`; confirm outbound HTTPS and proxy/TLS inspection allow the vendor host |
| "Resolved an empty download URL" | Vendor changed their endpoint or index layout. Update the resolver in the catalog and regenerate |
| "post-install verification failed" | The silent switches installed to a different path than detection expects. Compare the log's install path against the detection path |
| Detection never reports installed | Run `Detect-DLIllustr.ps1` manually on the device and check its exit code |

## Support

DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version history

- **v1.0.0** (2026-09-18) - Initial generated release. Evergreen download, PSADT v4.1.8.
