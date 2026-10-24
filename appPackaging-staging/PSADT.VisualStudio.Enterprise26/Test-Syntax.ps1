#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test script to verify PSADT package syntax and admin rights
#>

Write-Host "=== PSADT Visual Studio Enterprise 26 - Syntax Test ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Admin check
Write-Host "[Test 1] Checking admin rights..." -ForegroundColor Yellow
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "  ✓ Running as Administrator" -ForegroundColor Green
} else {
    Write-Host "  ✗ NOT running as Administrator" -ForegroundColor Red
    Write-Host "    Please restart PowerShell as Administrator" -ForegroundColor Red
    exit 1
}

# Test 2: File exists
Write-Host "[Test 2] Checking deployment script..." -ForegroundColor Yellow
$scriptPath = Join-Path $PSScriptRoot "Invoke-AppDeployToolkit.ps1"
if (Test-Path $scriptPath) {
    Write-Host "  ✓ Invoke-AppDeployToolkit.ps1 found" -ForegroundColor Green
} else {
    Write-Host "  ✗ Invoke-AppDeployToolkit.ps1 NOT found" -ForegroundColor Red
    exit 1
}

# Test 3: Parse syntax
Write-Host "[Test 3] Checking PowerShell syntax..." -ForegroundColor Yellow
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$errors)
if ($errors.Count -eq 0) {
    Write-Host "  ✓ No syntax errors found" -ForegroundColor Green
} else {
    Write-Host "  ✗ Syntax errors found:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "    Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red }
    exit 1
}

# Test 4: Can load parameters
Write-Host "[Test 4] Testing parameter binding..." -ForegroundColor Yellow
try {
    $cmdInfo = Get-Command $scriptPath -ErrorAction Stop
    $hasDeploymentType = $cmdInfo.Parameters.ContainsKey('DeploymentType')
    $hasDeployMode = $cmdInfo.Parameters.ContainsKey('DeployMode')

    if ($hasDeploymentType -and $hasDeployMode) {
        Write-Host "  ✓ Parameters available: DeploymentType, DeployMode" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Required parameters missing" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Failed to load script: $_" -ForegroundColor Red
    exit 1
}

# Test 5: Execution policy
Write-Host "[Test 5] Checking execution policy..." -ForegroundColor Yellow
$policy = Get-ExecutionPolicy
Write-Host "  Current policy: $policy" -ForegroundColor Cyan
if ($policy -eq 'Restricted') {
    Write-Host "  ⚠ Execution policy is Restricted - scripts may fail" -ForegroundColor Yellow
    Write-Host "    Run: Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force" -ForegroundColor Yellow
} else {
    Write-Host "  ✓ Execution policy allows scripts" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== All Tests Passed ===" -ForegroundColor Green
Write-Host ""
Write-Host "Ready to install! Run one of these commands:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Silent mode:" -ForegroundColor Yellow
Write-Host '    .\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent' -ForegroundColor White
Write-Host ""
Write-Host "  Interactive mode:" -ForegroundColor Yellow
Write-Host '    .\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Interactive' -ForegroundColor White
Write-Host ""
