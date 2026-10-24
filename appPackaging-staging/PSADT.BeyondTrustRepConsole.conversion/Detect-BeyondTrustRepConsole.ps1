<#
.SYNOPSIS
    Intune detection script for the BeyondTrust Remote Support Representative Console.

.DESCRIPTION
    Returns 'installed' when a BeyondTrust / Bomgar representative console is present.

    The desktop representative console is a per-appliance build: its uninstall-registry
    DisplayName is derived from the site hostname (e.g. support.example.com) under a
    'BeyondTrust' (older builds: 'Bomgar') grouping. This script therefore matches the
    DisplayName against a broad pattern rather than a single fixed path or product code.

    CONFIRM the installed DisplayName in your pilot group and tighten $displayNamePattern
    if the broad match produces false positives in your environment.

    Detection method: RegistrySearch (uninstall registry DisplayName)

.NOTES
    Version:        1.0.0
    Author:         DWX Team with Kiro
    Creation Date:  2026-10-09

    Returns:
    - Exit 0 + stdout: the representative console is installed
    - Exit 1:          the representative console is not installed
#>

$displayNamePattern = 'BeyondTrust|Bomgar|Representative Console'
$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try {
    $match = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $displayNamePattern } |
        Select-Object -First 1

    if ($match) {
        Write-Output "BeyondTrust Remote Support Representative Console is installed - $($match.DisplayName) $($match.DisplayVersion)"
        exit 0
    }
    exit 1
}
catch {
    exit 1
}
