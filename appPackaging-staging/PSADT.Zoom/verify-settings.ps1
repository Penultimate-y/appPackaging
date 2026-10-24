$script = "c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.Zoom\Invoke-AppDeployToolkit.ps1"
$content = Get-Content $script -Raw

# The settings exactly as specified in the requirement.
$requiredZConfig = 'AU2_EnableAutoUpdate=true;AU2_SetUpdateChannel=1;AU2_EnableShowZoomUpdates=true;AU2_EnableUpdateSuccessNotification=true;AU2_EnableManualUpdate=true;AU2_InstallAtIdleTime=true;AU2_SafeUpgradePeriod=1800-0400;nogoogle=1;nofacebook=1;DisableLoginWithMicrosoft=1;EnableAppleLogin=0;DisableLoginWithEmail=1;DisableUserSignUp=1;AutoSSOLogin=1;ForceSSOUrl=Group1001;EnableNewWebView2SSO=1;EnableEmbedBrowserForSSO=1;EnforceSignInToJoin=1;EnforceAppSignInToJoin=1;EnforceSignInToJoinForWebinar=1;EnforceAppSignInToJoinForWebinar=1'
$requiredZRecommend = 'AutoStartAfterReboot=1;ShowZoomWinWhenSharing=1;PresentToRoomOption=0;IntegrateZoomWithOutlook=1;EnableRemindMeetingTime=0'

# Pull the actual strings out of the script.
$actualZConfig = if ($content -match '\$zConfig\s*=\s*"([^"]+)"') { $matches[1] } else { $null }
$actualZRecommend = if ($content -match '\$zRecommend\s*=\s*"([^"]+)"') { $matches[1] } else { $null }

Write-Output "=== 1. Inline ZConfig string ==="
if ($actualZConfig -ceq $requiredZConfig) {
    Write-Output "  MATCH (exact, all 21 settings)"
} else {
    Write-Output "  MISMATCH"
    $req = $requiredZConfig -split ';'
    $act = if ($actualZConfig) { $actualZConfig -split ';' } else { @() }
    foreach ($r in $req) { if ($act -notcontains $r) { Write-Output "    MISSING from script: $r" } }
    foreach ($a in $act) { if ($req -notcontains $a) { Write-Output "    EXTRA in script:     $a" } }
}

Write-Output ""
Write-Output "=== 2. Inline ZRecommend string ==="
if ($actualZRecommend -ceq $requiredZRecommend) {
    Write-Output "  MATCH (exact, all 5 settings)"
} else {
    Write-Output "  MISMATCH"
    $req = $requiredZRecommend -split ';'
    $act = if ($actualZRecommend) { $actualZRecommend -split ';' } else { @() }
    foreach ($r in $req) { if ($act -notcontains $r) { Write-Output "    MISSING from script: $r" } }
    foreach ($a in $act) { if ($req -notcontains $a) { Write-Output "    EXTRA in script:     $a" } }
}

# Requirement: a registry entry for EACH setting.
Write-Output ""
Write-Output "=== 3. Registry entry per setting (Set-ItemProperty coverage) ==="
$allSettings = ($requiredZConfig -split ';') + ($requiredZRecommend -split ';')
$missingReg = @()
foreach ($s in $allSettings) {
    $name = ($s -split '=')[0]
    $val  = ($s -split '=', 2)[1]
    $pattern = 'Set-ItemProperty[^\r\n]*-Name\s+"' + [regex]::Escape($name) + '"\s+-Value\s+"' + [regex]::Escape($val) + '"'
    if ($content -notmatch $pattern) {
        # Check whether the name exists at all, to distinguish missing vs wrong value.
        if ($content -match ('-Name\s+"' + [regex]::Escape($name) + '"')) {
            $missingReg += "WRONG VALUE: $name (expected $val)"
        } else {
            $missingReg += "NO REG ENTRY: $name=$val"
        }
    }
}
Write-Output "  Total settings requiring a registry entry: $($allSettings.Count)"
if ($missingReg.Count -eq 0) {
    Write-Output "  All $($allSettings.Count) settings have a matching registry entry."
} else {
    Write-Output "  Problems found: $($missingReg.Count)"
    $missingReg | ForEach-Object { Write-Output "    $_" }
}

# Detection must verify Zoom AND all registry settings.
Write-Output ""
Write-Output "=== 4. Detection script registry coverage ==="
$detect = Get-Content "c:\DWX_Dev_Sync\dwx-automation-cli-scripts\intune-apps\PSADT.Zoom\Detect-Zoom.ps1" -Raw
$notChecked = @()
foreach ($s in $allSettings) {
    $name = ($s -split '=')[0]
    if ($detect -notmatch [regex]::Escape($name)) { $notChecked += $name }
}
Write-Output "  Settings not validated by detection: $($notChecked.Count) of $($allSettings.Count)"
if ($notChecked.Count -gt 0) { $notChecked | ForEach-Object { Write-Output "    $_" } }
