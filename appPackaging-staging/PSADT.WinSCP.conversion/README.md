# WinSCP - PSADT v4.1.8 Win32 App

Downloads and installs the current release of WinSCP at deployment time.

Built with **PSAppDeployToolkit v4.1.8**, generated from the
`PSADT.Kiro.IDE` template by `new.psadt-package.ps1`.

> **Download URL not verified.** The URL in this package has not been confirmed against a
> live vendor endpoint. Validate it before assigning the app, or stage the installer in
> `Files\` to use the offline path. See *Offline / air-gapped use* below.

## Overview

| | |
|---|---|
| **Package** | `PSADT.WinSCP.conversion` |
| **Vendor** | Martin Prikryl |
| **Architecture** | x86 |
| **Category** | Network Tools |
| **Install context** | System |
| **Installer type** | MSI |
| **Silent switches** | _(none)_ |
| **Replaces (legacy)** | `legacy.WinSCP` |

OFFLINE-ONLY package - media is staged in Files\ rather than downloaded. Verified 2026-09-18: the winscp/winscp GitHub repo publishes no Releases; cdn.winscp.net returns HTTP 403; and winscp.net/download/WinSCP-latest-Setup.exe 302-redirects to a plaintext http:// SourceForge path that returns 404, so it must not be used. Uses the vendor MSI (not the Inno Setup .exe) because the MSI already sets ALLUSERS=1 and needs no silent switches. Staged media: WinSCP-6.3.5.msi, ProductCode {819533C9-2894-4224-A2A8-763058A9351C}, Authenticode-signed by Martin Prikryl.

## How the installer is obtained

1. If any `.msi`, `.exe` or `.zip` file is present in `Files\`, that file is used.
2. Otherwise: **No automated download.** This vendor blocks scripted downloads, so the installer must be staged in `Files\` manually. Obtain it from https://winscp.net/eng/download.php (use the 'MSI installer' link, which WinSCP publishes specifically for automated deployment)

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
3. Review `C:\Windows\Logs\Software\WinSCP (Latest)_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.WinSCP.conversion" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: WinSCP (Latest)
- **Publisher**: Martin Prikryl
- **Category**: Network Tools

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
- **Script file**: `Detect-WinSCP.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: Uninstall registry `DisplayName` matches `^WinSCP`

### Uninstall behaviour

Registered uninstall string for `DisplayName` matching `^WinSCP`

## Logging

```
C:\Windows\Logs\Software\WinSCP (Latest)_Latest_<DeploymentType>_<timestamp>.log
```

## Update strategy

This package is evergreen: each run resolves and installs whatever the vendor currently
publishes. To push an update, trigger a sync or re-assign in Intune - the package itself
does not need to be rebuilt.

Exception: resolvers of type `PinnedUrl` do **not** auto-resolve. For those, update the
URL in `psadt-app-catalog.json` and regenerate:

```powershell
.\new.psadt-package.ps1 -PackageName 'PSADT.WinSCP.conversion' -Force
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails immediately | PSADT log under `C:\Windows\Logs\Software\`; confirm outbound HTTPS and proxy/TLS inspection allow the vendor host |
| "Resolved an empty download URL" | Vendor changed their endpoint or index layout. Update the resolver in the catalog and regenerate |
| "post-install verification failed" | The silent switches installed to a different path than detection expects. Compare the log's install path against the detection path |
| Detection never reports installed | Run `Detect-WinSCP.ps1` manually on the device and check its exit code |

## Support

DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version history

- **v1.0.0** (2026-09-18) - Initial generated release. Evergreen download, PSADT v4.1.8.
