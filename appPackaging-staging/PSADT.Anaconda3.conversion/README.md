# Anaconda3 - PSADT v4.1.8 Win32 App

Downloads and installs the current release of Anaconda3 at deployment time.

Built with **PSAppDeployToolkit v4.1.8**, generated from the
`PSADT.Kiro.IDE` template by `new.psadt-package.ps1`.


## Overview

| | |
|---|---|
| **Package** | `PSADT.Anaconda3.conversion` |
| **Vendor** | Anaconda |
| **Architecture** | x64 |
| **Category** | Data Science |
| **Install context** | System |
| **Installer type** | EXE |
| **Silent switches** | `/InstallationType=AllUsers` `/RegisterPython=0` `/AddToPath=0` `/S` `/D=C:\ProgramData\Anaconda3` |
| **Replaces (legacy)** | `legacy.Anaconda` |

NOTE: Anaconda's commercial terms require a paid licence for organisations over the free-use threshold. Confirm licensing before broad assignment.

## How the installer is obtained

1. If any `.msi`, `.exe` or `.zip` file is present in `Files\`, that file is used.
2. Otherwise: Newest installer found in the vendor index `https://repo.anaconda.com/archive/`.

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
3. Review `C:\Windows\Logs\Software\Anaconda3 (Latest)_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.Anaconda3.conversion" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: Anaconda3 (Latest)
- **Publisher**: Anaconda
- **Category**: Data Science

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
- **Script file**: `Detect-Anaconda3.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: File exists: `C:\ProgramData\Anaconda3\python.exe`

### Uninstall behaviour

Bundled uninstaller: `C:\ProgramData\Anaconda3\Uninstall-Anaconda3.exe`

## Logging

```
C:\Windows\Logs\Software\Anaconda3 (Latest)_Latest_<DeploymentType>_<timestamp>.log
```

## Update strategy

This package is evergreen: each run resolves and installs whatever the vendor currently
publishes. To push an update, trigger a sync or re-assign in Intune - the package itself
does not need to be rebuilt.

Exception: resolvers of type `PinnedUrl` do **not** auto-resolve. For those, update the
URL in `psadt-app-catalog.json` and regenerate:

```powershell
.\new.psadt-package.ps1 -PackageName 'PSADT.Anaconda3.conversion' -Force
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails immediately | PSADT log under `C:\Windows\Logs\Software\`; confirm outbound HTTPS and proxy/TLS inspection allow the vendor host |
| "Resolved an empty download URL" | Vendor changed their endpoint or index layout. Update the resolver in the catalog and regenerate |
| "post-install verification failed" | The silent switches installed to a different path than detection expects. Compare the log's install path against the detection path |
| Detection never reports installed | Run `Detect-Anaconda3.ps1` manually on the device and check its exit code |

## Support

DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version history

- **v1.0.0** (2026-09-18) - Initial generated release. Evergreen download, PSADT v4.1.8.
