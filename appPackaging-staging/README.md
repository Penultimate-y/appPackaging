# appPackaging

PSADT v4 Win32 application packages for Microsoft Intune deployment.

Each `PSADT.<Name>.conversion/` (or `PSADT.<Name>.<Variant>/`) folder is a self-contained
PSAppDeployToolkit package: deployment script (`Invoke-AppDeployToolkit.ps1`), detection
logic (`Detect-*.ps1`), configuration, assets, and the bundled PSADT runtime.

## Binaries are not tracked

Installer media and build artifacts are intentionally excluded from source control and are
fetched at install time (download-at-install-time pattern). The following are gitignored:

- Installers / media: `*.msi`, `*.exe`, `*.msix`, `*.msp`, `*.cab`, `*.zip`, `*.iso`, `*.vhd`, `*.wim`
- Intune build output: `*.intunewin`

To build a package locally, stage its installer in the package's `SupportFiles/` (or `Files/`)
folder, then run the toolkit / Intune packaging step.
