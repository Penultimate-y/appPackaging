@{
    Assets = @{
        Logo = '..\Assets\AppIcon.png'
        LogoDark = '..\Assets\AppIcon.png'
        Banner = '..\Assets\Banner.Classic.png'
    }

    MSI = @{
        InstallParams = 'REBOOT=ReallySuppress /QN'
        LoggingOptions = '/L*V'
        LogPath = $null
        LogPathNoAdminRights = $null
        MutexWaitTime = 600
        SilentParams = 'REBOOT=ReallySuppress /QN'
        UninstallParams = 'REBOOT=ReallySuppress /QN'
    }

    Toolkit = @{
        CachePath = '$envProgramData\SoftwareCache'
        CompanyName = 'Group 1001'
        CompressLogs = $false
        FileCopyMode = 'Native'
        LogAppend = $true
        LogDebugMessage = $false
        LogMaxHistory = 10
        LogMaxSize = 10
        LogPath = '$envWinDir\Logs\Software'
        LogPathNoAdminRights = '$envProgramData\Logs\Software'
        LogToHierarchy = $false
        LogToSubfolder = $false
        LogStyle = 'CMTrace'
        LogWriteToHost = $true
        LogHostOutputToStdStreams = $false
        RegPath = 'HKLM:\SOFTWARE'
        RegPathNoAdminRights = 'HKCU:\SOFTWARE'
        TempPath = '$envTemp'
        TempPathNoAdminRights = '$envTemp'
    }

    UI = @{
        BalloonNotifications = $false
        DialogStyle = 'Fluent'
        FluentAccentColor = $null
        DefaultExitCode = 1618
        DefaultPromptPersistInterval = 60
        DefaultTimeout = 3300
        DeferExitCode = 1602
        LanguageOverride = $null
        PromptToSaveTimeout = 120
        RestartPromptPersistInterval = 600
    }
}
