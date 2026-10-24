================================================================================
  APPLICATION DEPLOYMENT ORCHESTRATOR
  README
================================================================================

OVERVIEW
--------
This orchestrator collects deployment information for Windows applications
(MSI or EXE), generates a standalone, self-contained PowerShell deployment
script with all values hardcoded, and writes an audit manifest recording who
generated what, when, and with what result.

It supports three modes:
  1. Fully interactive (prompts for every value)
  2. Config-driven (reads values from a JSON file, prompts only for what's missing)
  3. Fully unattended (config + skip all confirmations + auto-run)


REQUIREMENTS
------------
- Windows PowerShell 5.1 or PowerShell 7+
- The companion template script: Application_Script_Template_Automate.ps1
- Execution policy that allows running local scripts:

      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned


FILES
-----
Required (must be in the same folder as the orchestrator):

  Orchestrator.ps1
      The main orchestrator script. Run this.

  Application_Script_Template_Automate.ps1
      The parameterized template that gets read and converted into a
      standalone deployment script.

Generated automatically (created on first run):

  Generated\
      Output folder for generated deployment scripts and per-run manifests.

  Generated\manifest_log.jsonl
      Append-only audit log of every generation and execution event.


QUICK START
-----------
Open PowerShell in the folder containing the orchestrator and run:

      .\Orchestrator.ps1

You'll be prompted for each piece of deployment information. When done,
the orchestrator will:
  1. Show a confirmation summary
  2. Generate a standalone .ps1 script in the Generated\ folder
  3. Write a manifest .json describing the generation
  4. Optionally execute the generated script


COMMAND-LINE PARAMETERS
-----------------------
-ConfigFile <path>
    Load deployment values from a JSON config file. Missing fields fall
    back to interactive prompts.

    Example:
        .\Orchestrator.ps1 -ConfigFile .\zoom-install.json

-NoConfirm
    Skip all Y/N confirmation prompts. Use only with -ConfigFile for true
    unattended runs. Also auto-runs the generated script.

    Example:
        .\Orchestrator.ps1 -ConfigFile .\zoom-install.json -NoConfirm

-SaveConfig <path>
    After collecting all inputs, save them to a reusable JSON config file.
    Useful for "interactive once, automated thereafter" workflows.

    Example:
        .\Orchestrator.ps1 -SaveConfig .\my-app-config.json


USAGE SCENARIOS
---------------

Scenario 1: First-time interactive run
    .\Orchestrator.ps1

Scenario 2: Save current run as a reusable config
    .\Orchestrator.ps1 -SaveConfig .\zoom-install.json

Scenario 3: Re-run with saved config (still confirm interactively)
    .\Orchestrator.ps1 -ConfigFile .\zoom-install.json

Scenario 4: Fully unattended (config + auto-confirm + auto-run)
    .\Orchestrator.ps1 -ConfigFile .\zoom-install.json -NoConfirm

Scenario 5: Partial config (only some fields pre-filled)
    Create a JSON containing just the fields you know (e.g. AppName,
    AppVersion). The orchestrator will prompt only for what's missing.

    .\Orchestrator.ps1 -ConfigFile .\partial.json


INPUT FIELDS
------------
The orchestrator collects the following information:

  AppName              Required.  Free-form application name.
                       Example: "Zoom"

  PackageName          Required.  Folder name used for logging/packaging.
                       Example: "Zoom_5.17.1.1"

  AppVersion           Required.  Version in format x.x.x.x where each
                       segment is 1 to 3 digits.
                       Example: "5.17.1.1"

  DeploymentType       Required.  Either "Install" or "Uninstall".

  InstallerType        Required.  Either "MSI" or "EXE".

  InstallerName        Required.  Filename ending in .msi or .exe (must
                       match InstallerType).
                       Example: "ZoomInstallerFull.msi"

  Arguments            Optional.  Silent install / vendor-specific switches.
                       Example MSI: "/qn /norestart"
                       Example EXE: "/S" or "/silent"

  ProcessesToStop      Optional.  Comma-separated list of process names
                       (without .exe) to kill before install runs.
                       Example: "Zoom, Zoom_launcher, CptHost"

  DetectionPath        Optional.  Full path to a file or folder used to
                       verify install success after the exit code check.
                       Example: "C:\Program Files\Zoom\bin\Zoom.exe"

  SuccessCodes         Comma-separated integers. Default: 0
  SoftRebootCodes      Comma-separated integers. Default: 3010
  HardRebootCodes      Comma-separated integers. Default: 1641 (MSI) / blank (EXE)
  RetryCodes           Comma-separated integers. Default: 1618

  Note: Soft reboot and hard reboot codes are treated as successful installs
  and merged with the success codes when passed to the target script.
  Retry codes are NOT successes — they indicate "try again later."


CONFIG FILE FORMAT
------------------
Config files are JSON. Here's a complete example:

    {
        "AppName": "Zoom",
        "PackageName": "Zoom_5.17.1.1",
        "AppVersion": "5.17.1.1",
        "DeploymentType": "Install",
        "InstallerType": "MSI",
        "InstallerName": "ZoomInstallerFull.msi",
        "Arguments": "/qn /norestart",
        "ProcessesToStop": ["Zoom", "Zoom_launcher"],
        "DetectionPath": "C:\\Program Files\\Zoom\\bin\\Zoom.exe",
        "SuccessCodes": [0],
        "SoftRebootCodes": [3010],
        "HardRebootCodes": [1641],
        "RetryCodes": [1618]
    }

IMPORTANT JSON RULES:
  - Backslashes in paths must be doubled: "C:\\Program Files" not "C:\Program Files"
  - Exit codes are arrays of integers, not strings
  - Empty array []  = "explicitly no codes for this category"
  - Missing key     = "prompt me for this one"
  - All field names are case-sensitive


EXITING / CANCELING
-------------------
At any prompt, type one of the following to cancel the entire run:

    exit
    quit
    cancel

The orchestrator will exit cleanly without generating any files.


OUTPUT
------
For every run, the orchestrator produces:

  Generated\Deploy_<AppName>_<Version>_<Type>.ps1
      Standalone deployment script with all values hardcoded. No parameters
      required. Can be run independently of the orchestrator.

  Generated\Deploy_<AppName>_<Version>_<Type>.json
      Per-run manifest describing what was generated, by whom, when, and
      (after execution) the exit code and duration.

  Generated\manifest_log.jsonl
      Rolling append-only audit log. One JSON record per line. Each
      deployment produces TWO records: one at generation time, one after
      execution completes.

If a generated script with the same name already exists, a timestamp is
appended (e.g. Deploy_Zoom_5.17.1.1_Install_20260530_142315.ps1).


MANIFEST CONTENTS
-----------------
Each manifest records:

  Generation:
    - Timestamp (UTC and local)
    - User and machine that generated it
    - Orchestrator version
    - PowerShell and OS version
    - Whether input came from interactive prompts or a config file

  Inputs:
    - Every field the user supplied or the config provided

  GeneratedScript:
    - Full path to the .ps1 file
    - SHA256 hash (for tamper detection)
    - File size

  Execution:
    - Whether the script was run
    - Exit code returned
    - Duration in seconds
    - Timestamp of execution


VALIDATION
----------
All input is validated, whether from prompts or config files:

  AppVersion           Must match x.x.x.x format (1-3 digits per segment)
  DeploymentType       Must be "Install" or "Uninstall"
  InstallerType        Must be "MSI" or "EXE"
  InstallerName        Extension must match InstallerType
  ProcessesToStop      Letters, digits, dots, dashes, underscores only
  DetectionPath        Must start with drive letter (C:\) or UNC (\\server\share)
                       No <  >  "  |  ?  * characters
  Exit codes           Must be integers; non-numeric input is rejected

Config-file validation failures throw a fail-fast error identifying the
bad field, e.g.:
    "Config error: AppVersion '1.2' is not in valid x.x.x.x format."


TROUBLESHOOTING
---------------

Problem: "execution of scripts is disabled on this system"
Fix:     Run this once as your user (no admin needed):
             Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

Problem: "Template script not found at..."
Fix:     Ensure Application_Script_Template_Automate.ps1 is in the same
         folder as Orchestrator.ps1.

Problem: "Config error: <field> ..."
Fix:     Open the JSON config and correct the offending field. Common
         issues: unescaped backslashes in paths, wrong InstallerType /
         InstallerName mismatch, malformed version string.

Problem: JSON parse error
Fix:     Validate your JSON. Common issues:
            - Trailing commas (not allowed: [0, 3010,])
            - Single quotes instead of double ('AppName' should be "AppName")
            - Missing quotes around string values
         Quick test:
             Get-Content .\my-config.json -Raw | ConvertFrom-Json

Problem: Generated script doesn't run / wrong values
Fix:     Open Generated\Deploy_*.ps1 and inspect the auto-generated values
         block at the top. The values shown there are exactly what got
         baked in. Compare to your inputs or config file.

Problem: Orchestrator hangs at a prompt
Fix:     You may have an unexpected prompt waiting for input. Type "exit"
         to cancel and rerun. If using -NoConfirm, verify your config has
         all required fields.

Problem: Need to verify the script before running
Fix:     Answer "N" when asked "Run the generated script now?". The .ps1
         and manifest are still saved. You can inspect, then run manually:
             .\Generated\Deploy_<AppName>_<Version>_<Type>.ps1


ROUND-TRIP WORKFLOW
-------------------
The recommended workflow for repeatable deployments:

  1. Run once interactively, saving the inputs:

         .\Orchestrator.ps1 -SaveConfig .\configs\zoom-install.json

  2. Edit the JSON as needed (e.g., change AppVersion for a new release).

  3. Re-run unattended whenever you need to regenerate:

         .\Orchestrator.ps1 -ConfigFile .\configs\zoom-install.json -NoConfirm

This guarantees the config matches the orchestrator's expected schema
without any guesswork.


AUDIT AND REPORTING
-------------------
The rolling manifest log (Generated\manifest_log.jsonl) is JSON Lines
format — one record per line. To analyze it:

  # Read all records
  Get-Content .\Generated\manifest_log.jsonl |
      ForEach-Object { $_ | ConvertFrom-Json }

  # Show all deployments by a specific user
  Get-Content .\Generated\manifest_log.jsonl |
      ForEach-Object { $_ | ConvertFrom-Json } |
      Where-Object { $_.Generation.GeneratedBy -like '*jsmith*' } |
      Select-Object @{n='App';e={$_.Inputs.AppName}},
                    @{n='Version';e={$_.Inputs.AppVersion}},
                    @{n='When';e={$_.Generation.TimestampLocal}},
                    @{n='ExitCode';e={$_.Execution.ExitCode}}

  # Show all failed deployments
  Get-Content .\Generated\manifest_log.jsonl |
      ForEach-Object { $_ | ConvertFrom-Json } |
      Where-Object { $_.Execution.Executed -and $_.Execution.ExitCode -ne 0 }


KEYBOARD SHORTCUTS
------------------
Press Enter at a prompt to accept the default value (shown in brackets).
Type "none" at any exit-code prompt to leave that category empty.
Type "exit", "quit", or "cancel" at any prompt to abort.


VERSION
-------
Orchestrator version: 1.0.0

Compatible with:
    Application_Script_Template_Automate.ps1


SUPPORT
-------
For issues or questions, contact the deployment automation team or
review the comments inside Orchestrator.ps1.

================================================================================
                                  END OF README
================================================================================