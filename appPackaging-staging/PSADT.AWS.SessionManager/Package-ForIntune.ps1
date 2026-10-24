<#
================================================================================
Script Name:        Package-ForIntune.ps1
Creation Date:      2026-07-22
Last Change Date:   2026-07-22
Author:             DWX Team with Claude Code
LLM Version Tag:    Claude Code-claude-sonnet-4-6
Script Function:    Helper script to package the AWS Session Manager PSADT
                    folder into an .intunewin file for Microsoft Intune
                    deployment. Validates prerequisites and runs the
                    IntuneWinAppUtil.exe packaging tool.
Script Input:       None (uses current directory)
Script Output:      Creates PSADT.AWS.SessionManager.intunewin in parent folder
Modules Required:   None (requires IntuneWinAppUtil.exe in path or parent)
Script Usage:       .\Package-ForIntune.ps1

Latest Change
Description:        Initial creation
================================================================================
#>

# CODE
# DEFINE VARIABLES AND INPUTS AND OUTPUTS

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# CODE AND SCRIPT LOGIC WITH COMMENTS AT KEY COMMANDS

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "AWS Session Manager Plugin - Intune Package Creator" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# Get current directory and parent
$sourceFolder = $PSScriptRoot
$parentFolder = Split-Path -Path $sourceFolder -Parent
$packageName = Split-Path -Path $sourceFolder -Leaf
$outputFile = Join-Path -Path $parentFolder -ChildPath "$packageName.intunewin"

Write-Host "Source folder: $sourceFolder" -ForegroundColor White
Write-Host "Output folder: $parentFolder" -ForegroundColor White
Write-Host "Package name:  $packageName" -ForegroundColor White
Write-Host ""

# Verify required files exist
$requiredFiles = @(
    'Invoke-AppDeployToolkit.exe',
    'Invoke-AppDeployToolkit.ps1',
    'Detect-AWSSessionManager.ps1',
    'README.md'
)

Write-Host "Validating package structure..." -ForegroundColor Yellow
$missingFiles = @()

foreach ($file in $requiredFiles)
{
    $filePath = Join-Path -Path $sourceFolder -ChildPath $file
    if (Test-Path -Path $filePath)
    {
        Write-Host "  [OK] $file" -ForegroundColor Green
    }
    else
    {
        Write-Host "  [MISSING] $file" -ForegroundColor Red
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0)
{
    Write-Host ""
    Write-Host "ERROR: Missing required files. Cannot create package." -ForegroundColor Red
    exit 1
}

Write-Host ""

# Check for IntuneWinAppUtil.exe
Write-Host "Locating IntuneWinAppUtil.exe..." -ForegroundColor Yellow

$intuneWinAppUtil = $null
$searchPaths = @(
    (Join-Path -Path $parentFolder -ChildPath 'IntuneWinAppUtil.exe'),
    (Join-Path -Path $env:USERPROFILE -ChildPath 'Downloads\IntuneWinAppUtil.exe'),
    'IntuneWinAppUtil.exe'  # Check PATH
)

foreach ($path in $searchPaths)
{
    if ($path -eq 'IntuneWinAppUtil.exe')
    {
        # Check PATH
        $pathCheck = Get-Command -Name 'IntuneWinAppUtil.exe' -ErrorAction SilentlyContinue
        if ($pathCheck)
        {
            $intuneWinAppUtil = $pathCheck.Source
            break
        }
    }
    else
    {
        if (Test-Path -Path $path)
        {
            $intuneWinAppUtil = $path
            break
        }
    }
}

if (-not $intuneWinAppUtil)
{
    Write-Host ""
    Write-Host "ERROR: IntuneWinAppUtil.exe not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Download from: https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool" -ForegroundColor Yellow
    Write-Host "Place in one of these locations:" -ForegroundColor Yellow
    Write-Host "  - $parentFolder" -ForegroundColor White
    Write-Host "  - $env:USERPROFILE\Downloads" -ForegroundColor White
    Write-Host "  - Any folder in your PATH" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "  Found: $intuneWinAppUtil" -ForegroundColor Green
Write-Host ""

# Check if output file already exists
if (Test-Path -Path $outputFile)
{
    Write-Host "WARNING: Output file already exists: $outputFile" -ForegroundColor Yellow
    $response = Read-Host "Overwrite? (Y/N)"
    if ($response -ne 'Y')
    {
        Write-Host "Packaging cancelled." -ForegroundColor Yellow
        exit 0
    }
    Remove-Item -Path $outputFile -Force
    Write-Host "Existing file removed." -ForegroundColor Yellow
    Write-Host ""
}

# Run IntuneWinAppUtil
Write-Host "Creating .intunewin package..." -ForegroundColor Yellow
Write-Host ""

try
{
    $arguments = @(
        '-c', "`"$sourceFolder`"",
        '-s', 'Invoke-AppDeployToolkit.exe',
        '-o', "`"$parentFolder`""
    )

    Write-Host "Command: $intuneWinAppUtil $($arguments -join ' ')" -ForegroundColor Gray
    Write-Host ""

    & $intuneWinAppUtil @arguments

    if ($LASTEXITCODE -eq 0)
    {
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host "SUCCESS: Package created successfully!" -ForegroundColor Green
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Output file: $outputFile" -ForegroundColor White

        if (Test-Path -Path $outputFile)
        {
            $fileSize = (Get-Item -Path $outputFile).Length
            $fileSizeMB = [Math]::Round($fileSize / 1MB, 2)
            Write-Host "File size:   $fileSizeMB MB" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Upload $packageName.intunewin to Intune" -ForegroundColor White
        Write-Host "  2. Configure app settings (see DEPLOYMENT-GUIDE.md)" -ForegroundColor White
        Write-Host "  3. Upload Detect-AWSSessionManager.ps1 as detection script" -ForegroundColor White
        Write-Host "  4. Assign to target groups" -ForegroundColor White
        Write-Host ""
    }
    else
    {
        Write-Host ""
        Write-Host "ERROR: IntuneWinAppUtil.exe failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
catch
{
    Write-Host ""
    Write-Host "ERROR: Failed to run IntuneWinAppUtil.exe" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# CODE COMPLETE
