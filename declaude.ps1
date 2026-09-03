<#
.SYNOPSIS
    Declaude - Claude Desktop Update Unlocker
.DESCRIPTION
    Resolves the WindowsApps / Helium container lock ("Another program is currently using this file")
    that occurs whenever Claude Desktop updates on Windows.
    
    Can be run locally or streamed directly:
    irm https://raw.githubusercontent.com/moltic/declaude/main/declaude.ps1 | iex
#>

# Determine directory if running from script file
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Definition) { Split-Path -Parent $MyInvocation.MyCommand.Definition } else { "" }
$LocalExe = if ($ScriptDir) { Join-Path $ScriptDir "declaude.exe" } else { "" }

$TargetExe = $null

if ($LocalExe -and (Test-Path $LocalExe)) {
    $TargetExe = $LocalExe
} else {
    # Download latest binary to temp directory if running as web one-liner
    $TempExe = Join-Path $env:TEMP "declaude.exe"
    Write-Host "[*] Fetching latest Declaude release..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $url = "https://github.com/moltic/declaude/releases/latest/download/declaude.exe"
        Invoke-WebRequest -Uri $url -OutFile $TempExe -UseBasicParsing
        $TargetExe = $TempExe
    } catch {
        Write-Host "[!] Could not fetch pre-compiled binary: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($TargetExe -and (Test-Path $TargetExe)) {
    Write-Host "[*] Launching Declaude ($TargetExe)..." -ForegroundColor Cyan
    Start-Process -FilePath $TargetExe -Verb RunAs -Wait
    exit $LASTEXITCODE
}

# Fallback: pure PowerShell cleanup if binary unavailable
function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "[!] Admin privileges required. Elevating via UAC..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { irm https://raw.githubusercontent.com/moltic/declaude/main/declaude.ps1 | iex }`"" -Verb RunAs -Wait
    exit
}

Write-Host "=================================================" -ForegroundColor Green
Write-Host "   Declaude - Claude Desktop Update Unlocker     " -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green

Write-Host "[*] Stopping CoworkVMService and lingering processes..." -ForegroundColor Cyan
Stop-Service -Name "CoworkVMService" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Claude", "cowork-svc", "chrome-native-host" -Force -ErrorAction SilentlyContinue

Write-Host "[*] Launching Claude Desktop..." -ForegroundColor Cyan
Start-Process "explorer.exe" "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Write-Host "[+] Done!" -ForegroundColor Green
