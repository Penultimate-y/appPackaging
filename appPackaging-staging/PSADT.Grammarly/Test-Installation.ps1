<#
.SYNOPSIS
Test wrapper for Grammarly PSADT installation with verbose logging.

.DESCRIPTION
Runs the Grammarly installation and captures detailed output and exit codes.

#>

$ErrorActionPreference = 'Continue'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Grammarly PSADT Installation Test" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Change to script directory
Set-Location $ScriptRoot
Write-Host "[INFO] Working directory: $PWD" -ForegroundColor Green

# Check if EXE exists
$exePath = Join-Path $ScriptRoot "Invoke-AppDeployToolkit.exe"
if (-not (Test-Path $exePath))
{
    Write-Host "[ERROR] Invoke-AppDeployToolkit.exe not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Found: $exePath" -ForegroundColor Green

# Run installation
Write-Host ""
Write-Host "[INFO] Starting installation in Interactive mode..." -ForegroundColor Yellow
Write-Host ""

$startTime = Get-Date

try
{
    # Run the installer
    $process = Start-Process -FilePath $exePath `
        -ArgumentList "-DeploymentType Install -DeployMode Interactive" `
        -NoNewWindow `
        -PassThru `
        -Wait

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "Installation Completed" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "[INFO] Exit Code: $($process.ExitCode)" -ForegroundColor $(if ($process.ExitCode -eq 0) { 'Green' } else { 'Red' })
    Write-Host "[INFO] Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
    Write-Host ""

    # Check for log files
    Write-Host "[INFO] Checking for log files..." -ForegroundColor Yellow
    $logPath = "C:\Windows\Logs\Software"
    if (Test-Path $logPath)
    {
        $recentLogs = Get-ChildItem -Path $logPath -Filter "*Grammarly*" -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending |
                      Select-Object -First 3

        if ($recentLogs)
        {
            Write-Host "[INFO] Found log files:" -ForegroundColor Green
            $recentLogs | ForEach-Object {
                Write-Host "  - $($_.FullName) [$($_.Length / 1KB) KB]" -ForegroundColor Cyan
            }
        }
        else
        {
            Write-Host "[WARN] No Grammarly log files found in $logPath" -ForegroundColor Yellow
        }
    }

    # Check installation
    Write-Host ""
    Write-Host "[INFO] Verifying installation..." -ForegroundColor Yellow

    $grammarlyExe = "C:\Program Files (x86)\Grammarly\DesktopIntegrations\Grammarly.Desktop.exe"
    if (Test-Path $grammarlyExe)
    {
        Write-Host "[SUCCESS] Grammarly executable found: $grammarlyExe" -ForegroundColor Green
        $version = (Get-Item $grammarlyExe).VersionInfo.FileVersion
        Write-Host "[INFO] Version: $version" -ForegroundColor Cyan
    }
    else
    {
        Write-Host "[WARN] Grammarly executable not found at: $grammarlyExe" -ForegroundColor Yellow
    }

    # Check registry
    $regPath = "HKLM:\SOFTWARE\Policies\Grammarly\DesktopIntegrations"
    if (Test-Path $regPath)
    {
        Write-Host "[SUCCESS] Registry key found: $regPath" -ForegroundColor Green
        $token = Get-ItemProperty -Path $regPath -Name "GrammarlyEnrollmentToken" -ErrorAction SilentlyContinue
        if ($token)
        {
            Write-Host "[INFO] Enrollment token configured" -ForegroundColor Cyan
        }
    }
    else
    {
        Write-Host "[WARN] Registry key not found: $regPath" -ForegroundColor Yellow
    }

    Write-Host ""
    exit $process.ExitCode
}
catch
{
    Write-Host ""
    Write-Host "[ERROR] Installation failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
