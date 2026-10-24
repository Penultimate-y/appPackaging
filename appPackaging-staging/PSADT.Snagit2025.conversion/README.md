# Snagit 2025 - PSADT v4.1.8 Win32 App

Downloads and installs the current release of Snagit 2025 at deployment time.

Built with **PSAppDeployToolkit v4.1.8**, generated from the
`PSADT.Kiro.IDE` template by `new.psadt-package.ps1`.

> **Download URL not verified.** The URL in this package has not been confirmed against a
> live vendor endpoint. Validate it before assigning the app, or stage the installer in
> `Files\` to use the offline path. See *Offline / air-gapped use* below.

## Overview

| | |
|---|---|
| **Package** | `PSADT.Snagit2025.conversion` |
| **Vendor** | TechSmith |
| **Architecture** | x64 |
| **Category** | Productivity |
| **Install context** | System |
| **Installer type** | MSI |
| **Silent switches** | `ALLUSERS=1` `TSC_SUPPRESS_REBOOT=1` `DESKTOP_SHORTCUT=0` |
| **Replaces (legacy)** | `legacy.SnagIt` |

OFFLINE-ONLY / TRANSFORM-DRIVEN. Snagit 2025 is deployed with a volume-licence MST transform (TRANSFORMS=snagit.mst), as the legacy.SnagIt scripts did - the transform carries the licence key and configuration so users are not prompted to activate. Stage BOTH snagit.msi and the snagit.mst transform in Files\. The hand-edited Invoke-AppDeployToolkit.ps1 prompts the operator for transform-file choices when run interactively (build/pilot), and under Intune silent/SYSTEM context it auto-applies the single staged .mst (plain install if none staged). The install block was hand-authored to pass TRANSFORMS= - regenerating with -Force will overwrite that edit, so re-apply the transform logic after any regeneration.

## How the installer is obtained

1. If any `.msi`, `.exe` or `.zip` file is present in `Files\`, that file is used.
2. Otherwise: **No automated download.** This vendor blocks scripted downloads, so the installer must be staged in `Files\` manually. Obtain it from https://www.techsmith.com/download/snagit/ (use the TechSmith Deployment Tool to generate the volume-licensed snagit.msi + snagit.mst transform, then stage BOTH in the package Files folder)

The download lands in the PSADT-managed support-files folder and is cleaned up with the
session, so nothing is left behind on the device.

## Offline / air-gapped use

Drop the vendor installer into `Files\` before building the `.intunewin`. The package
then installs without any outbound network access and the resolver is never called.

## MST transform (volume licence)

Snagit 2025 is **transform-driven**. The MST transform carries the TechSmith volume-licence
key and configuration, so users are not prompted to activate. This mirrors the legacy
`legacy.SnagIt` install (`msiexec /i snagit.msi TRANSFORMS=snagit.mst`).

**Stage both files in `Files\` before building:**

1. `snagit.msi` — the Snagit 2025 MSI.
2. `snagit.mst` — your volume-licence transform (generate it with the TechSmith Deployment Tool).

### How the transform is chosen

The hand-edited `Resolve-AppTransform` function in `Invoke-AppDeployToolkit.ps1` decides which
transform to apply based on how the package is run:

| Run context | Behaviour |
|---|---|
| **Interactive** (manual build / pilot run) | **Prompts the operator**: lists every `.mst` in `Files\`, offers `[1..n]` to pick one, `[A]` to apply all in order, `[N]` for no transform. If none are staged, asks for a full path or Enter to skip. |
| **Silent / NonInteractive** (Intune SYSTEM context) | Never prompts. Auto-applies the single staged `.mst`; if several are staged it applies all in name order; if none are staged it installs without a transform (logged as a warning). |

To exercise the prompt while packaging or piloting, run elevated:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

> Regenerating this package with `new.psadt-package.ps1 -Force` overwrites `Invoke-AppDeployToolkit.ps1`
> and therefore removes the transform logic. Re-apply `Resolve-AppTransform` and the `TRANSFORMS=`
> argument block in the Install and Repair actions after any regeneration.

## Test group requirement

App assignment changes affect every targeted device and user. Before widening an
assignment:

1. Assign to the **DWX application pilot group** only.
2. Confirm install, detection and uninstall on at least one device per supported Windows build.
3. Review `C:\Windows\Logs\Software\Snagit 2025 (Latest)_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.Snagit2025.conversion" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: Snagit 2025 (Latest)
- **Publisher**: TechSmith
- **Category**: Productivity

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
- **Script file**: `Detect-Snagit2025.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: Uninstall registry `DisplayName` matches `^Snagit 2025|^Snagit 25\.`

### Uninstall behaviour

Registered uninstall string for `DisplayName` matching `^Snagit 2025|^Snagit 25\.`

## Logging

```
C:\Windows\Logs\Software\Snagit 2025 (Latest)_Latest_<DeploymentType>_<timestamp>.log
```

## Update strategy

This package is evergreen: each run resolves and installs whatever the vendor currently
publishes. To push an update, trigger a sync or re-assign in Intune - the package itself
does not need to be rebuilt.

Exception: resolvers of type `PinnedUrl` do **not** auto-resolve. For those, update the
URL in `psadt-app-catalog.json` and regenerate:

```powershell
.\new.psadt-package.ps1 -PackageName 'PSADT.Snagit2025.conversion' -Force
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails immediately | PSADT log under `C:\Windows\Logs\Software\`; confirm outbound HTTPS and proxy/TLS inspection allow the vendor host |
| "Resolved an empty download URL" | Vendor changed their endpoint or index layout. Update the resolver in the catalog and regenerate |
| "post-install verification failed" | The silent switches installed to a different path than detection expects. Compare the log's install path against the detection path |
| Detection never reports installed | Run `Detect-Snagit2025.ps1` manually on the device and check its exit code |

## Support

DWX Endpoint Management team (Zachary Hayward, Kunle Ayegbusi, Allen Johnson)

## Version history

- **v1.0.0** (2026-09-18) - Initial generated release. Evergreen download, PSADT v4.1.8.
