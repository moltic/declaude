<#
.SYNOPSIS
    Migrate Claude Desktop from MSIX (Windows Store) to standard EXE installer.
.DESCRIPTION
    The MSIX version of Claude Desktop regularly deadlocks its Windows Container (Helium)
    silos during auto-updates, producing the error "Another program is currently using this file."
    
    The official standalone EXE installer avoids the WindowsApps container architecture entirely,
    preventing this update deadlock permanently. Your chat history, settings, and MCP configs
    (%APPDATA%\Claude) are preserved.
#>

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Claude Desktop Migration: MSIX -> Standalone EXE        " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Stop services & processes
Write-Host "`n[1/4] Stopping Claude services and processes..." -ForegroundColor Yellow
Stop-Service -Name "CoworkVMService" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Claude", "cowork-svc", "chrome-native-host" -Force -ErrorAction SilentlyContinue

# 2. Remove MSIX package
Write-Host "`n[2/4] Removing MSIX / WindowsApps package..." -ForegroundColor Yellow
$pkg = Get-AppxPackage -Name "*Claude*" -ErrorAction SilentlyContinue
if ($pkg) {
    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
    Write-Host "      Removed: $($pkg.PackageFullName)" -ForegroundColor Green
} else {
    Write-Host "      No MSIX package found." -ForegroundColor Gray
}

# 3. Install Standalone EXE via winget
Write-Host "`n[3/4] Installing official Claude Desktop EXE installer via winget..." -ForegroundColor Yellow
winget install --id Anthropic.Claude --installer-type exe --accept-package-agreements --accept-source-agreements

# 4. Finish
Write-Host "`n[4/4] Migration complete!" -ForegroundColor Green
Write-Host "Claude Desktop is now installed as a standard desktop application." -ForegroundColor Cyan
Write-Host "It will update cleanly in the background without WindowsApps file locks." -ForegroundColor Green
