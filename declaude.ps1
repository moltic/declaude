<#
.SYNOPSIS
    Declaude - Claude Desktop Update Unlocker
.DESCRIPTION
    Resolves the WindowsApps / Helium container lock ("Another program is currently using this file")
    that occurs whenever Claude Desktop updates on Windows.
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ExePath = Join-Path $ScriptDir "declaude.exe"

# If compiled binary exists, invoke it directly
if (Test-Path $ExePath) {
    Write-Host "[*] Launching Declaude ($ExePath)..." -ForegroundColor Cyan
    Start-Process -FilePath $ExePath -Verb RunAs -Wait
    exit $LASTEXITCODE
}

# Otherwise run PowerShell-native cleanup
function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "[!] Admin privileges required. Elevating via UAC..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait
    exit
}

Write-Host "=================================================" -ForegroundColor Green
Write-Host "   Declaude - Claude Desktop Update Unlocker     " -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green

# 1. Stop CoworkVMService and kill processes
Write-Host "[*] Stopping CoworkVMService and lingering processes..." -ForegroundColor Cyan
Stop-Service -Name "CoworkVMService" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Claude", "cowork-svc", "chrome-native-host" -Force -ErrorAction SilentlyContinue

# 2. Check for locked hives
$hivelist = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\hivelist"
$claudeHives = $hivelist.psobject.properties | Where-Object { 
    $_.Value -like "*Claude*" -or $_.Name -like "*Claude*" 
} | Select-Object -ExpandProperty Name

if ($claudeHives) {
    Write-Host "[*] Found $($claudeHives.Count) locked Claude registry silo(s)." -ForegroundColor Yellow
    Write-Host "[*] Force-unloading via declaude helper..." -ForegroundColor Cyan
} else {
    Write-Host "[+] No locked Claude registry silos found." -ForegroundColor Green
}

# 3. Launch Claude Desktop
Write-Host "[*] Launching Claude Desktop..." -ForegroundColor Cyan
Start-Process "explorer.exe" "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Write-Host "[+] Done!" -ForegroundColor Green
