# BeyondTrust Remote Support Representative Console - PSADT v4.1.8 Win32 App

Installs the BeyondTrust Remote Support (RS) Representative Console from media staged in this
package's `Files\` folder.

Built with **PSAppDeployToolkit v4.1.8**, modelled on the `PSADT.Kiro.IDE` template.

> **Offline-only / appliance-specific.** The representative console installer
> (`sra-con-installer.exe`) is a per-appliance build tied to your BeyondTrust appliance
> hostname. There is **no public download URL**, so the installer must be staged in `Files\`.
> `UrlVerified` is `false` by design. See *Offline / air-gapped use* below.

## Overview

| | |
|---|---|
| **Package** | `PSADT.BeyondTrustRepConsole.conversion` |
| **Vendor** | BeyondTrust |
| **Architecture** | x64 |
| **Category** | Remote Access |
| **Install context** | System |
| **Installer type** | EXE (NSIS / Nullsoft) |
| **Silent switches** | `/S` |
| **Replaces (legacy)** | `legacy.Beyond trust` |

The staged installer was confirmed as a valid NSIS installer, Authenticode-signed by
`CN=BeyondTrust Corporation` (~27.7 MB).

## How the installer is obtained

This package does **not** download. It uses the `sra-con-installer.exe` staged in `Files\`.
If that file is missing, the package fails with clear guidance to download it from the
appliance and stage it.

## Offline / air-gapped use

1. Log in to your BeyondTrust appliance and download the Windows **Representative Console**
   installer.
2. Save it into `Files\` as `sra-con-installer.exe`.
3. Build the `.intunewin` and upload it to Intune.

## Assumptions to verify in pilot

- **Silent switches** `/S` (NSIS). Silent uninstall uses the bundled `Uninstall.exe /S`.
- **Detection / uninstall** match the uninstall-registry `DisplayName` against
  `BeyondTrust|Bomgar|Representative Console`. The real entry is named for the site hostname
  (e.g. `support.example.com`). Confirm the installed `DisplayName` on a pilot device and
  tighten the pattern in `Detect-BeyondTrustRepConsole.ps1`, `app-config-beyondtrustrepconsole.json`,
  and `Invoke-AppDeployToolkit.ps1` (`$script:DetectionDisplayNamePattern`) if the broad match
  risks false positives (for example, if other BeyondTrust products are present on the device).
- **Per-machine (System) install** assumed. If your appliance only produces a per-user console,
  switch to User context.
- **ProcessesToClose** is a best-effort list; confirm the actual console process name in pilot.

## Test group requirement

App assignment changes affect every targeted device and user. Before widening an assignment:

1. Assign to the **DWX application pilot group** only.
2. Confirm install, detection and uninstall on at least one device per supported Windows build.
3. Review `C:\Windows\Logs\Software\BeyondTrust Remote Support Representative Console_*.log`.
4. Only then extend the assignment.

## Packaging

```powershell
.\IntuneWinAppUtil.exe `
    -c "<repo>\PSADT.BeyondTrustRepConsole.conversion" `
    -s "Invoke-AppDeployToolkit.exe" `
    -o "<output folder>" `
    -q
```

## Intune configuration

### App information

- **Name**: BeyondTrust Remote Support Representative Console
- **Publisher**: BeyondTrust

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

### Detection rules

- **Rules format**: Use a custom detection script
- **Script file**: `Detect-BeyondTrustRepConsole.ps1`
- **Run script as 32-bit process**: No
- **Enforce script signature check**: No

Detection logic: uninstall-registry `DisplayName` matches `BeyondTrust|Bomgar|Representative Console`.

### Uninstall behaviour

Runs the registered uninstall string for the matched entry (the bundled NSIS `Uninstall.exe`)
with `/S`.

## Logging

```
C:\Windows\Logs\Software\BeyondTrust Remote Support Representative Console_*.log
```

## Update strategy

Not evergreen. When the BeyondTrust appliance is upgraded, re-download the representative
console installer, replace `Files\sra-con-installer.exe`, rebuild the `.intunewin`, and
re-upload to Intune.

## Troubleshooting

| Symptom | Check |
|---|---|
| "No installer was found" | Stage `sra-con-installer.exe` in `Files\` and rebuild the `.intunewin` |
| Install returns 0 but detection fails | The site `DisplayName` did not match the pattern. Run `Detect-BeyondTrustRepConsole.ps1` on the device, read the actual `DisplayName`, and tighten the pattern |
| Detection reports installed after uninstall | Another BeyondTrust product may match the broad pattern; narrow it to the site hostname |

## Support

DWX Endpoint Management team.

## Version history

- **v1.0.0** (2026-10-09) - Initial release. Offline/appliance-specific, NSIS `/S`, PSADT v4.1.8.
