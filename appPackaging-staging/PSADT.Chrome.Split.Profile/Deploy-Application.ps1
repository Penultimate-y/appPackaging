<#
.SYNOPSIS
    Group 1001 - Chrome Split Profile Deployment (Onyx + Zendesk)
.DESCRIPTION
    Pure user-context deployment. No SYSTEM dependencies, no elevation.
    Creates dedicated Chrome profiles + desktop shortcuts in the running
    user's session. Designed for Intune Win32 app with Install behavior = User.

    v1.2.0 changes:
      - Removed the per-session launcher subsystem (Launch-Zendesk.vbs +
        Launch-Zendesk.ps1). Zendesk shortcut now uses a direct chrome.exe
        target with three URLs.
      - Zendesk profile launches three tabs (in order):
          1. Zendesk agent     (focused / leftmost)
          2. Connect (via MyApps SSO launcher URL)
          3. Pindrop (via MyApps SSO launcher URL)
        The Connect URL routes through Entra's sign-in flow, which also
        primes the cookie jar for the Zendesk Talk widget. No separate
        MyApps priming step is needed.
      - Uninstall now cleans up legacy launcher files from v1.1.x installs
        that get superseded by v1.2.0.

    v1.1.1 changes (retained):
      - Idempotent bookmark seeding that runs on BOTH new-profile and
        existing-profile branches. Only seeds when target Bookmarks is
        missing or empty (<= 100 bytes). User-added bookmarks preserved.
      - Per-profile bookmark results in marker file.

    v1.1.0 changes (retained):
      - Bookmarks seeded from user's existing primary Chrome profile.
      - Bookmark bar visible across all tabs by default.
      - Desktop shortcut filenames: "Onyx.lnk" / "Zendesk.lnk".
      - Legacy "Chrome - *.lnk" shortcuts removed at install.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('Install','Uninstall','Repair')]
    [string]$DeploymentType = 'Install',

    [Parameter(Mandatory=$false)]
    [ValidateSet('Interactive','Silent','NonInteractive')]
    [string]$DeployMode = 'Interactive',

    [Parameter(Mandatory=$false)]
    [switch]$AllowRebootPassThru = $false,

    [Parameter(Mandatory=$false)]
    [switch]$TerminalServerMode = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DisableLogging = $false
)

Try {
    Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    [string]$appVendor = 'Group 1001'
    [string]$appName = 'Chrome Split Profiles'
    [string]$appVersion = '1.2.0'
    [string]$appArch = 'x64'
    [string]$appLang = 'EN'
    [string]$appRevision = '01'
    [string]$appScriptVersion = '1.2.0'
    [string]$appScriptDate = '05/28/2026'
    [string]$appScriptAuthor = 'Zachary Hayward'

    [string]$installName = 'Chrome Split Profiles (Onyx + Zendesk)'
    [string]$installTitle = 'Chrome Profile Setup'

    ##* Do not modify section below
    [string]$deployAppScriptFriendlyName = 'Deploy Application'
    [version]$deployAppScriptVersion = [version]'3.10.2'
    [string]$deployAppScriptDate = '08/13/2024'
    [hashtable]$deployAppScriptParameters = $psBoundParameters

    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
    [string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    Try {
        [string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
    }
    Catch {
        If ($mainExitCode -eq 0) { [int32]$mainExitCode = 60008 }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
    }

    ##*===============================================
    ##* SHARED VARIABLES
    ##*===============================================
    [string[]]$profileNames = @('Onyx', 'Zendesk')

    # Configuration constants
    [int]$closeAppsCountdown = 300
    [int]$bookmarkSeedThreshold = 100
    [int]$maxAvatarIndex = 26

    # Startup URLs per profile.
    # Onyx: single URL, direct chrome.exe shortcut.
    # Zendesk: three URLs - agent (focused), Connect, Pindrop.
    #   The Connect URL is an Entra SSO launcher that routes through
    #   login.microsoftonline.com before redirecting to Connect, which
    #   also warms the cookie jar for the Zendesk Talk widget.
    # First URL in the array is the focused/leftmost tab in Chrome.
    [hashtable]$startupUrlMap = @{
        'Onyx'    = @('https://service.g1001.net/V2/case-management/search')
        'Zendesk' = @(
            'https://delawarelife.zendesk.com/agent',
            'https://launcher.myapps.microsoft.com/api/signin/65104d54-67e4-4f8d-86d1-e282e89fac81?tenantId=0ea7bba9-6311-47d8-be00-91b71da2d6f7',
            'https://launcher.myapps.microsoft.com/api/signin/1156eb84-cd5c-41e0-8253-f0266d70f9f6?tenantId=0ea7bba9-6311-47d8-be00-91b71da2d6f7'
        )
    }

    [string]$markerDir = "$env:LOCALAPPDATA\G1001\ChromeSplitCC"
    [string]$markerFile = "$markerDir\install.marker"
    [string]$iconCacheDir = "$env:LOCALAPPDATA\G1001\ChromeProfileIcons"

    # v1.1.x launcher directory - retained for cleanup on upgrade only
    [string]$legacyLauncherDir = "$env:LOCALAPPDATA\G1001\Launchers"

    # Per-profile bookmark seeding results, written to the marker at end
    $script:bookmarkResults = @{}

    ##*===============================================
    ##* HELPER FUNCTIONS
    ##*===============================================

    Function Get-ChromeProfileCache {
        <#
        .SYNOPSIS
            Scans Chrome User Data directory once and caches all profile information
        .DESCRIPTION
            Reduces redundant disk I/O by scanning profiles once and returning enriched objects
        #>
        [CmdletBinding()]
        Param([string]$UserDataPath)

        Try {
            Get-ChildItem -Path $UserDataPath -Directory -ErrorAction Stop |
                Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' } |
                ForEach-Object {
                    $prefsPath = Join-Path $_.FullName 'Preferences'
                    $bookmarksPath = Join-Path $_.FullName 'Bookmarks'
                    $prefs = $null
                    $profileName = $null
                    $bookmarkSize = 0

                    If (Test-Path $prefsPath) {
                        Try {
                            $prefs = Get-Content $prefsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                            $profileName = $prefs.profile.name
                        }
                        Catch {
                            Write-Log -Message "Failed to parse Preferences for $($_.Name): $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
                        }
                    }

                    If (Test-Path $bookmarksPath) {
                        Try {
                            $bookmarkSize = (Get-Item $bookmarksPath -ErrorAction Stop).Length
                        }
                        Catch { }
                    }

                    [PSCustomObject]@{
                        DirectoryName = $_.Name
                        FullPath      = $_.FullName
                        Preferences   = $prefs
                        ProfileName   = $profileName
                        BookmarksPath = $bookmarksPath
                        BookmarkSize  = $bookmarkSize
                    }
                }
        }
        Catch {
            Write-Log -Message "Failed to scan Chrome profile directory: $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
            return @()
        }
    }

    Function Get-BookmarkSourceProfile {
        <#
        .SYNOPSIS
            Identifies the best source profile for seeding bookmarks
        .DESCRIPTION
            Preference: Default > Profile 1 > Profile 2, etc.
            Excludes profiles that match target names, requires bookmarks > threshold
        #>
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory=$true)]
            [object[]]$ProfileCache,
            [Parameter(Mandatory=$true)]
            [string[]]$ExcludeNames,
            [Parameter(Mandatory=$true)]
            [int]$MinBookmarkSize
        )

        $candidates = $ProfileCache |
            Where-Object { $_.ProfileName -notin $ExcludeNames -and $_.BookmarkSize -gt $MinBookmarkSize } |
            Sort-Object {
                If ($_.DirectoryName -eq 'Default') { 0 }
                ElseIf ($_.DirectoryName -match '^Profile (\d+)$') { [int]$Matches[1] }
                Else { 999 }
            }

        return $candidates | Select-Object -First 1
    }

    Function Remove-ProfileShortcuts {
        <#
        .SYNOPSIS
            Removes desktop shortcuts for specified profiles (both current and legacy naming)
        #>
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory=$true)]
            [string[]]$ProfileNames,
            [Parameter(Mandatory=$true)]
            [string]$DesktopPath
        )

        Foreach ($name in $ProfileNames) {
            @("$name.lnk", "Chrome - $name.lnk") | ForEach-Object {
                $shortcut = Join-Path $DesktopPath $_
                If (Test-Path $shortcut) {
                    Try {
                        Remove-Item $shortcut -Force -ErrorAction Stop
                        Write-Log -Message "Removed shortcut: $shortcut" -Source 'ChromeProfile'
                    }
                    Catch {
                        Write-Log -Message "Failed to remove shortcut '$shortcut'" -Severity 2 -Source 'ChromeProfile'
                        Write-Log -Message "Exception: $($_.Exception.GetType().FullName) - $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
                    }
                }
            }
        }
    }

    Function New-ChromeProfileShortcut {
        <#
        .SYNOPSIS
            Creates a Chrome profile shortcut with enhanced error handling
        #>
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory=$true)]
            [string]$ShortcutPath,
            [Parameter(Mandatory=$true)]
            [string]$ChromeExePath,
            [Parameter(Mandatory=$true)]
            [string]$ProfileDirectory,
            [Parameter(Mandatory=$true)]
            [string[]]$StartupUrls,
            [Parameter(Mandatory=$false)]
            [string]$IconPath,
            [Parameter(Mandatory=$true)]
            [string]$Description
        )

        Try {
            $urlArgs = ($StartupUrls | ForEach-Object { "`"$_`"" }) -join ' '

            $shell = New-Object -ComObject WScript.Shell
            $sc = $shell.CreateShortcut($ShortcutPath)
            $sc.TargetPath = $ChromeExePath
            $sc.Arguments = "--profile-directory=`"$ProfileDirectory`" $urlArgs"
            $sc.WorkingDirectory = Split-Path $ChromeExePath
            $sc.IconLocation = If ($IconPath) { "$IconPath,0" } Else { "$ChromeExePath,0" }
            $sc.Description = $Description
            $sc.Save()

            # Release COM object to prevent memory leak
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

            Write-Log -Message "Shortcut created: $ShortcutPath ($($StartupUrls.Count) tab(s))" -Source 'ChromeProfile'
            return $true
        }
        Catch {
            Write-Log -Message "Failed to create shortcut at '$ShortcutPath'" -Severity 3 -Source 'ChromeProfile'
            Write-Log -Message "Exception: $($_.Exception.GetType().FullName)" -Severity 3 -Source 'ChromeProfile'
            Write-Log -Message "Error details: $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
            return $false
        }
    }

    Function Test-ShouldSeedBookmarks {
        <#
        .SYNOPSIS
            Determines if bookmarks should be seeded based on destination state
        #>
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory=$true)]
            [string]$BookmarkPath,
            [Parameter(Mandatory=$true)]
            [int]$Threshold
        )

        If (-not (Test-Path $BookmarkPath)) {
            return @{ ShouldSeed = $true; Reason = 'no Bookmarks file at destination' }
        }

        Try {
            $size = (Get-Item $BookmarkPath -ErrorAction Stop).Length
            If ($size -le $Threshold) {
                return @{ ShouldSeed = $true; Reason = "destination Bookmarks file is empty ($size bytes)" }
            }
            Else {
                return @{ ShouldSeed = $false; Reason = "destination Bookmarks file has $size bytes - preserving user data" }
            }
        }
        Catch {
            Write-Log -Message "Failed to check bookmark file size: $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
            return @{ ShouldSeed = $false; Reason = 'error checking file size' }
        }
    }

    ##*===============================================
    ##* INSTALLATION
    ##*===============================================
    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        [string]$installPhase = 'Pre-Installation'

        Show-InstallationWelcome `
            -CloseApps 'chrome=Google Chrome' `
            -CloseAppsCountdown $closeAppsCountdown `
            -PersistPrompt `
            -BlockExecution

        Show-InstallationProgress -StatusMessage 'Preparing Chrome profile setup...'

        [string]$installPhase = 'Installation'

        # ============================================================
        # Legacy cleanup - using helper function
        # ============================================================
        $desktop = [Environment]::GetFolderPath('Desktop')
        Remove-ProfileShortcuts -ProfileNames $profileNames -DesktopPath $desktop

        If (Test-Path $legacyLauncherDir) {
            Try {
                Remove-Item $legacyLauncherDir -Recurse -Force -ErrorAction Stop
                Write-Log -Message "Removed legacy launcher directory: $legacyLauncherDir" -Source 'ChromeProfile'
            }
            Catch {
                Write-Log -Message "Failed to remove legacy launcher directory '$legacyLauncherDir'" -Severity 2 -Source 'ChromeProfile'
                Write-Log -Message "Exception: $($_.Exception.GetType().FullName) - $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
            }
        }

        $chromeUserData = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        $chromeExe = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        If (-not $chromeExe) {
            Write-Log -Message 'Chrome executable not found in any standard location.' -Severity 3 -Source 'ChromeProfile'
            Show-InstallationPrompt -Message 'Google Chrome is not installed on this system. Install Chrome and try again.' -ButtonRightText 'OK' -Icon Error
            Exit-Script -ExitCode 1620
        }

        If (-not (Test-Path $chromeUserData)) {
            Write-Log -Message "Chrome User Data not found at $chromeUserData. User must launch Chrome at least once." -Severity 3 -Source 'ChromeProfile'
            Show-InstallationPrompt -Message 'Please launch Google Chrome at least once before running this setup, then retry.' -ButtonRightText 'OK' -Icon Warning
            Exit-Script -ExitCode 1619
        }

        Write-Log -Message "Chrome found at: $chromeExe" -Source 'ChromeProfile'

        If (-not (Test-Path $iconCacheDir)) {
            Try {
                New-Item -ItemType Directory -Path $iconCacheDir -Force -ErrorAction Stop | Out-Null
            }
            Catch {
                Write-Log -Message "Failed to create icon cache directory: $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
            }
        }

        # ============================================================
        # OPTIMIZED: Scan profiles once and cache results
        # Eliminates redundant disk I/O - reduces 3-4 scans to 1 scan
        # ============================================================
        Write-Log -Message "Scanning Chrome profiles (cached)..." -Source 'ChromeProfile'
        $profileCache = Get-ChromeProfileCache -UserDataPath $chromeUserData

        # ============================================================
        # Discover bookmark source using cached profile data
        # ============================================================
        $bookmarkSource = Get-BookmarkSourceProfile `
            -ProfileCache $profileCache `
            -ExcludeNames $profileNames `
            -MinBookmarkSize $bookmarkSeedThreshold

        If ($bookmarkSource) {
            $bookmarkSourcePath = $bookmarkSource.BookmarksPath
            Write-Log -Message "Bookmark seed source: $($bookmarkSource.DirectoryName) (size: $($bookmarkSource.BookmarkSize) bytes)" -Source 'ChromeProfile'
        }
        Else {
            $bookmarkSourcePath = $null
            Write-Log -Message 'No existing profile with bookmarks found. New profiles will start empty.' -Severity 2 -Source 'ChromeProfile'
        }

        Foreach ($profileName in $profileNames) {
            Write-Log -Message "Processing profile: $profileName" -Source 'ChromeProfile'
            Show-InstallationProgress -StatusMessage "Creating Chrome profile: $profileName..."

            $startupUrls = $startupUrlMap[$profileName]
            $iconSource = Join-Path -Path $dirFiles -ChildPath "$profileName.ico"

            Try {
                # ============================================================
                # OPTIMIZED: Use cached profile data to locate existing profile
                # ============================================================
                $existingProfile = $profileCache | Where-Object { $_.ProfileName -eq $profileName } | Select-Object -First 1

                If ($existingProfile) {
                    Write-Log -Message "Profile '$profileName' already exists as '$($existingProfile.DirectoryName)'. Refreshing." -Source 'ChromeProfile'
                    $profileDir = $existingProfile.DirectoryName
                    $profilePath = $existingProfile.FullPath
                }
                Else {
                    $existing = Get-ChildItem -Path $chromeUserData -Directory -Filter 'Profile *' -ErrorAction SilentlyContinue
                    $nextNum = 1
                    If ($existing) {
                        $nums = $existing.Name | ForEach-Object {
                            If ($_ -match 'Profile (\d+)') { [int]$Matches[1] }
                        }
                        If ($nums) { $nextNum = ($nums | Measure-Object -Maximum).Maximum + 1 }
                    }
                    $profileDir = "Profile $nextNum"
                    $profilePath = Join-Path $chromeUserData $profileDir

                    Try {
                        New-Item -ItemType Directory -Path $profilePath -Force -ErrorAction Stop | Out-Null
                        Write-Log -Message "Created profile directory: $profilePath" -Source 'ChromeProfile'
                    }
                    Catch {
                        Write-Log -Message "Failed to create profile directory '$profilePath': $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
                        Throw
                    }

                    $prefs = @{
                        profile = @{
                            name         = $profileName
                            avatar_index = (Get-Random -Minimum 0 -Maximum $maxAvatarIndex)
                        }
                        browser = @{ has_seen_welcome_page = $true }
                        bookmark_bar = @{ show_on_all_tabs = $true }
                        session = @{ restore_on_startup = 4; startup_urls = $startupUrls }
                    }

                    Try {
                        $prefsPath = Join-Path $profilePath 'Preferences'
                        $prefs | ConvertTo-Json -Depth 5 | Set-Content -Path $prefsPath -Encoding UTF8 -ErrorAction Stop
                        Write-Log -Message "Created Preferences file for '$profileName'" -Source 'ChromeProfile'
                    }
                    Catch {
                        Write-Log -Message "Failed to create Preferences file: $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
                        Throw
                    }

                    $localStatePath = Join-Path $chromeUserData 'Local State'
                    If (Test-Path $localStatePath) {
                        Try {
                            $ls = Get-Content $localStatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                            If (-not $ls.profile.info_cache) {
                                $ls.profile | Add-Member -NotePropertyName 'info_cache' -NotePropertyValue @{} -Force
                            }
                            $info = @{
                                name                  = $profileName
                                is_using_default_name = $false
                                avatar_icon           = "chrome://theme/IDR_PROFILE_AVATAR_$((Get-Random -Minimum 0 -Maximum $maxAvatarIndex))"
                            }
                            $ls.profile.info_cache | Add-Member -NotePropertyName $profileDir -NotePropertyValue $info -Force
                            $ls | ConvertTo-Json -Depth 10 | Set-Content $localStatePath -Encoding UTF8 -ErrorAction Stop
                            Write-Log -Message "Registered '$profileName' in Local State" -Source 'ChromeProfile'
                        }
                        Catch {
                            Write-Log -Message "Local State update failed (Chrome will re-register on next launch)" -Severity 2 -Source 'ChromeProfile'
                            Write-Log -Message "Exception: $($_.Exception.GetType().FullName) - $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
                        }
                    }
                }

                # ============================================================
                # OPTIMIZED: Bookmark seeding using helper function
                # Runs for BOTH new and existing profiles, preserves user data
                # ============================================================
                $bookmarkDest = Join-Path $profilePath 'Bookmarks'
                $seedCheck = Test-ShouldSeedBookmarks -BookmarkPath $bookmarkDest -Threshold $bookmarkSeedThreshold

                If ($seedCheck.ShouldSeed -and $bookmarkSourcePath) {
                    Try {
                        Copy-Item -Path $bookmarkSourcePath -Destination $bookmarkDest -Force -ErrorAction Stop
                        Write-Log -Message "Seeded bookmarks into '$profileName' ($profileDir) - $($seedCheck.Reason)" -Source 'ChromeProfile'

                        # Remove stale backup to prevent conflicts
                        $staleBak = Join-Path $profilePath 'Bookmarks.bak'
                        If (Test-Path $staleBak) {
                            Remove-Item $staleBak -Force -ErrorAction SilentlyContinue
                        }

                        $script:bookmarkResults[$profileName] = 'seeded'
                    }
                    Catch {
                        Write-Log -Message "Bookmark seed FAILED for '$profileName'" -Severity 3 -Source 'ChromeProfile'
                        Write-Log -Message "Exception: $($_.Exception.GetType().FullName)" -Severity 3 -Source 'ChromeProfile'
                        Write-Log -Message "Error details: $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
                        If ($_.Exception.InnerException) {
                            Write-Log -Message "Inner exception: $($_.Exception.InnerException.Message)" -Severity 3 -Source 'ChromeProfile'
                        }
                        $script:bookmarkResults[$profileName] = 'failed'
                    }
                }
                ElseIf ($seedCheck.ShouldSeed -and -not $bookmarkSourcePath) {
                    Write-Log -Message "Bookmark seed for '$profileName' skipped - no source profile available" -Severity 2 -Source 'ChromeProfile'
                    $script:bookmarkResults[$profileName] = 'no_source'
                }
                Else {
                    Write-Log -Message "Bookmark seed for '$profileName' skipped - $($seedCheck.Reason)" -Source 'ChromeProfile'
                    $script:bookmarkResults[$profileName] = 'preserved'
                }

                # ============================================================
                # Icon caching with error handling
                # ============================================================
                $iconDest = $null
                If (Test-Path $iconSource) {
                    Try {
                        $iconDest = Join-Path $iconCacheDir "$profileName.ico"
                        Copy-Item -Path $iconSource -Destination $iconDest -Force -ErrorAction Stop
                        Write-Log -Message "Cached icon for '$profileName'" -Source 'ChromeProfile'
                    }
                    Catch {
                        Write-Log -Message "Failed to cache icon for '$profileName': $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
                        $iconDest = $null
                    }
                }

                # ============================================================
                # OPTIMIZED: Shortcut creation using helper function
                # Includes COM cleanup to prevent memory leaks
                # ============================================================
                $shortcutPath = Join-Path $desktop "$profileName.lnk"
                $shortcutSuccess = New-ChromeProfileShortcut `
                    -ShortcutPath $shortcutPath `
                    -ChromeExePath $chromeExe `
                    -ProfileDirectory $profileDir `
                    -StartupUrls $startupUrls `
                    -IconPath $iconDest `
                    -Description $profileName

                If (-not $shortcutSuccess) {
                    Write-Log -Message "Warning: Shortcut creation failed for '$profileName' but profile was created successfully" -Severity 2 -Source 'ChromeProfile'
                }
            }
            Catch {
                Write-Log -Message "CRITICAL: Failed to process profile '$profileName'" -Severity 3 -Source 'ChromeProfile'
                Write-Log -Message "Exception: $($_.Exception.GetType().FullName)" -Severity 3 -Source 'ChromeProfile'
                Write-Log -Message "Error details: $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
                Write-Log -Message "Stack trace: $($_.ScriptStackTrace)" -Severity 3 -Source 'ChromeProfile'
                $script:bookmarkResults[$profileName] = 'profile_error'
            }
        }

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Installation'

        If (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
        @{
            InstalledOn      = (Get-Date -Format 'o')
            Version          = $appVersion
            Profiles         = $profileNames
            User             = $env:USERNAME
            BookmarkResults  = $script:bookmarkResults
            BookmarkSource   = If ($bookmarkSourcePath) { Split-Path $bookmarkSourcePath -Parent | Split-Path -Leaf } Else { 'none' }
        } | ConvertTo-Json | Set-Content -Path $markerFile -Encoding UTF8
        Write-Log -Message "Detection marker written: $markerFile" -Source 'ChromeProfile'
        Write-Log -Message "Bookmark results: $(($script:bookmarkResults.GetEnumerator() | ForEach-Object { ""$($_.Key)=$($_.Value)"" }) -join ', ')" -Source 'ChromeProfile'

        Close-InstallationProgress
    }
    ##*===============================================
    ##* UNINSTALLATION
    ##*===============================================
    ElseIf ($deploymentType -ieq 'Uninstall') {
        [string]$installPhase = 'Pre-Uninstallation'

        Show-InstallationWelcome `
            -CloseApps 'chrome=Google Chrome' `
            -CloseAppsCountdown $closeAppsCountdown `
            -PersistPrompt

        Show-InstallationProgress -StatusMessage 'Removing Chrome split profiles...'

        [string]$installPhase = 'Uninstallation'

        $chromeUserData = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        $desktop = [Environment]::GetFolderPath('Desktop')

        # ============================================================
        # OPTIMIZED: Remove shortcuts using helper function
        # ============================================================
        Remove-ProfileShortcuts -ProfileNames $profileNames -DesktopPath $desktop

        # ============================================================
        # OPTIMIZED: Use cached profile scan for removal
        # ============================================================
        If (Test-Path $chromeUserData) {
            $profileCache = Get-ChromeProfileCache -UserDataPath $chromeUserData

            Foreach ($name in $profileNames) {
                Try {
                    $targetProfile = $profileCache | Where-Object { $_.ProfileName -eq $name } | Select-Object -First 1

                    If ($targetProfile) {
                        Try {
                            Remove-Item $targetProfile.FullPath -Recurse -Force -ErrorAction Stop
                            Write-Log -Message "Removed profile directory: $($targetProfile.DirectoryName) ($name)" -Source 'ChromeProfile'

                            # Clean up Local State registration
                            $localStatePath = Join-Path $chromeUserData 'Local State'
                            If (Test-Path $localStatePath) {
                                Try {
                                    $ls = Get-Content $localStatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                                    If ($ls.profile.info_cache.PSObject.Properties[$targetProfile.DirectoryName]) {
                                        $ls.profile.info_cache.PSObject.Properties.Remove($targetProfile.DirectoryName)
                                        $ls | ConvertTo-Json -Depth 10 | Set-Content $localStatePath -Encoding UTF8 -ErrorAction Stop
                                        Write-Log -Message "Removed '$name' from Local State" -Source 'ChromeProfile'
                                    }
                                }
                                Catch {
                                    Write-Log -Message "Failed to update Local State during removal: $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
                                }
                            }
                        }
                        Catch {
                            Write-Log -Message "Failed to remove profile directory for '$name'" -Severity 3 -Source 'ChromeProfile'
                            Write-Log -Message "Exception: $($_.Exception.GetType().FullName) - $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
                        }
                    }
                    Else {
                        Write-Log -Message "Profile '$name' not found during uninstall (may have been manually deleted)" -Severity 1 -Source 'ChromeProfile'
                    }
                }
                Catch {
                    Write-Log -Message "Error during removal of '$name'" -Severity 3 -Source 'ChromeProfile'
                    Write-Log -Message "Exception: $($_.Exception.GetType().FullName) - $($_.Exception.Message)" -Severity 3 -Source 'ChromeProfile'
                }
            }
        }

        If (Test-Path $iconCacheDir) {
            Try {
                Remove-Item $iconCacheDir -Recurse -Force -ErrorAction Stop
                Write-Log -Message "Removed icon cache: $iconCacheDir" -Source 'ChromeProfile'
            }
            Catch {
                Write-Log -Message "Failed to remove icon cache: $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
            }
        }

        # Remove launcher dir from v1.1.x if still present
        If (Test-Path $legacyLauncherDir) {
            Try {
                Remove-Item $legacyLauncherDir -Recurse -Force -ErrorAction Stop
                Write-Log -Message "Removed legacy launcher directory: $legacyLauncherDir" -Source 'ChromeProfile'
            }
            Catch {
                Write-Log -Message "Failed to remove legacy launcher directory: $($_.Exception.Message)" -Severity 2 -Source 'ChromeProfile'
            }
        }

        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Uninstallation'

        If (Test-Path $markerFile) { Remove-Item $markerFile -Force -ErrorAction SilentlyContinue }
        If (Test-Path $markerDir) {
            Get-ChildItem $markerDir -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
            Remove-Item $markerDir -Force -ErrorAction SilentlyContinue
        }

        Close-InstallationProgress
    }
    ##*===============================================
    ##* REPAIR
    ##*===============================================
    ElseIf ($deploymentType -ieq 'Repair') {
        [string]$installPhase = 'Pre-Repair'
        Show-InstallationWelcome -CloseApps 'chrome=Google Chrome' -CloseAppsCountdown 60 -PersistPrompt
        Show-InstallationProgress -StatusMessage 'Repairing Chrome split profiles...'

        Write-Log -Message 'Repair mode invoked. Recommend uninstall + reinstall via Intune supersedence.' -Source 'ChromeProfile'

        [string]$installPhase = 'Post-Repair'
        Close-InstallationProgress
    }

    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [int32]$mainExitCode = 60001
    [string]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}