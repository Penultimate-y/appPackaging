#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Simple launcher for Visual Studio Enterprise 2026 installation
.DESCRIPTION
    Runs the PSADT installation in Silent mode with proper error handling
#>

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$InvokeScript = Join-Path $ScriptPath "Invoke-AppDeployToolkit.ps1"

Write-Host "Starting Visual Studio Enterprise 2026 installation..." -ForegroundColor Cyan
Write-Host "This will take 45-90 minutes (download + install)" -ForegroundColor Yellow
Write-Host ""

try {
    & $InvokeScript -DeploymentType "Install" -DeployMode "Silent"

    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "Installation completed successfully!" -ForegroundColor Green
    }
    elseif ($exitCode -eq 3010) {
        Write-Host "Installation completed successfully - reboot required!" -ForegroundColor Yellow
    }
    else {
        Write-Host "Installation completed with exit code: $exitCode" -ForegroundColor Red
    }
}
catch {
    Write-Host "Error during installation: $_" -ForegroundColor Red
    exit 1
}
