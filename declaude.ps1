<#
.SYNOPSIS
    Declaude - Claude Desktop Update Unlocker
.DESCRIPTION
    Resolves the WindowsApps / Helium container lock ("Another program is currently using this file")
    that occurs whenever Claude Desktop updates on Windows.
#>

param(
    [switch]$System
)

$Host.UI.RawUI.WindowTitle = "Declaude - Claude Desktop Unlocker"

# C# definition for Token Privileges & NtUnloadKey2
$NativeCode = @'
using System;
using System.Runtime.InteropServices;

public class KernelRegistry
{
    [StructLayout(LayoutKind.Sequential)]
    public struct UNICODE_STRING
    {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct OBJECT_ATTRIBUTES
    {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LUID
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LUID_AND_ATTRIBUTES
    {
        public LUID Luid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TOKEN_PRIVILEGES
    {
        public uint PrivilegeCount;
        public LUID_AND_ATTRIBUTES Privilege;
    }

    [DllImport("ntdll.dll", CharSet = CharSet.Unicode)]
    public static extern int NtUnloadKey2(ref OBJECT_ATTRIBUTES TargetKey, uint Flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    const uint TOKEN_QUERY = 0x0008;
    const uint SE_PRIVILEGE_ENABLED = 0x00000002;
    const uint OBJ_CASE_INSENSITIVE = 0x00000040;
    const uint REG_FORCE_UNLOAD = 0x00000001;

    public static bool EnablePrivilege(string privName)
    {
        IntPtr hToken;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hToken))
            return false;
        try
        {
            LUID luid;
            if (!LookupPrivilegeValue(null, privName, out luid))
                return false;

            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Privilege.Luid = luid;
            tp.Privilege.Attributes = SE_PRIVILEGE_ENABLED;

            return AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        }
        finally
        {
            CloseHandle(hToken);
        }
    }

    public static int ForceUnload(string keyPath)
    {
        UNICODE_STRING uStr = new UNICODE_STRING();
        uStr.Length = (ushort)(keyPath.Length * 2);
        uStr.MaximumLength = (ushort)(uStr.Length + 2);
        uStr.Buffer = Marshal.StringToHGlobalUni(keyPath);

        IntPtr pUStr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UNICODE_STRING)));
        Marshal.StructureToPtr(uStr, pUStr, false);

        OBJECT_ATTRIBUTES objAttr = new OBJECT_ATTRIBUTES();
        objAttr.Length = Marshal.SizeOf(typeof(OBJECT_ATTRIBUTES));
        objAttr.RootDirectory = IntPtr.Zero;
        objAttr.ObjectName = pUStr;
        objAttr.Attributes = OBJ_CASE_INSENSITIVE;
        objAttr.SecurityDescriptor = IntPtr.Zero;
        objAttr.SecurityQualityOfService = IntPtr.Zero;

        int status = NtUnloadKey2(ref objAttr, REG_FORCE_UNLOAD);

        Marshal.FreeHGlobal(pUStr);
        Marshal.FreeHGlobal(uStr.Buffer);

        return status;
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'KernelRegistry').Type) {
    Add-Type -TypeDefinition $NativeCode
}

# Function to perform the actual unload
function Invoke-DeclaudeUnload {
    Write-Host "[*] Enabling restore/backup privileges..." -ForegroundColor Cyan
    [KernelRegistry]::EnablePrivilege("SeRestorePrivilege") | Out-Null
    [KernelRegistry]::EnablePrivilege("SeBackupPrivilege") | Out-Null
    [KernelRegistry]::EnablePrivilege("SeTakeOwnershipPrivilege") | Out-Null

    Write-Host "[*] Stopping CoworkVMService if running..." -ForegroundColor Cyan
    Stop-Service -Name "CoworkVMService" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "Claude", "cowork-svc", "chrome-native-host" -Force -ErrorAction SilentlyContinue

    $hivelist = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\hivelist" -ErrorAction SilentlyContinue
    $claudeHives = @()
    if ($hivelist) {
        $claudeHives = $hivelist.psobject.properties | Where-Object { 
            $_.Value -like "*Claude*" -or $_.Name -like "*Claude*" 
        } | Select-Object -ExpandProperty Name
    }

    if (-not $claudeHives -or $claudeHives.Count -eq 0) {
        Write-Host "[+] No locked Claude registry silos found in kernel." -ForegroundColor Green
        return $true
    }

    Write-Host "[*] Found $($claudeHives.Count) locked Claude registry silo(s):" -ForegroundColor Yellow
    $allOk = $true
    foreach ($hive in $claudeHives) {
        $status = [KernelRegistry]::ForceUnload($hive)
        if ($status -eq 0) {
            Write-Host "    [OK] Unloaded: $hive" -ForegroundColor Green
        } else {
            $hex = "0x{0:X8}" -f $status
            Write-Host "    [FAIL] Status $hex for $hive" -ForegroundColor Red
            $allOk = $false
        }
    }
    return $allOk
}

# Check if running as SYSTEM worker
if ($System) {
    $ok = Invoke-DeclaudeUnload
    exit $(if ($ok) { 0 } else { 1 })
}

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[!] Administrative privileges required to release kernel locks." -ForegroundColor Yellow
    Write-Host "[*] Requesting UAC elevation..." -ForegroundColor Cyan
    $script = $PSCommandPath
    if (-not $script) {
        $script = "$PSScriptRoot\declaude.ps1"
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs -Wait
    exit
}

Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   Declaude - Claude Desktop Update Unlocker     " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

$directOk = Invoke-DeclaudeUnload

# If direct unload needed SYSTEM context for container silos
if (-not $directOk) {
    Write-Host "`n[*] Direct unload required SYSTEM context. Dispatching transient SYSTEM task..." -ForegroundColor Yellow
    $script = $PSCommandPath
    if (-not $script) { $script = "$PSScriptRoot\declaude.ps1" }
    $taskName = "Declaude_Worker_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)

    try {
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`" -System"
        schtasks.exe /create /tn "$taskName" /tr "$cmd" /sc ONCE /st 00:00 /ru "SYSTEM" /rl HIGHEST /f | Out-Null
        schtasks.exe /run /tn "$taskName" | Out-Null
        Start-Sleep -Seconds 2
        schtasks.exe /delete /tn "$taskName" /f | Out-Null
        Write-Host "[+] SYSTEM worker completed." -ForegroundColor Green
    } catch {
        Write-Host "[-] Could not dispatch SYSTEM task: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Verify lock release
Write-Host "`n[*] Verifying file locks..." -ForegroundColor Cyan
$hivelist = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\hivelist" -ErrorAction SilentlyContinue
$remaining = @()
if ($hivelist) {
    $remaining = $hivelist.psobject.properties | Where-Object { 
        $_.Value -like "*Claude*" -or $_.Name -like "*Claude*" 
    } | Select-Object -ExpandProperty Name
}

if (-not $remaining -or $remaining.Count -eq 0) {
    Write-Host "[+] SUCCESS: All Claude kernel locks have been released!" -ForegroundColor Green
    Write-Host "[*] Launching Claude Desktop..." -ForegroundColor Cyan
    Start-Process "explorer.exe" "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
    Write-Host "[+] Claude Desktop launched!" -ForegroundColor Green
} else {
    Write-Host "[-] $($remaining.Count) hive(s) still remain locked." -ForegroundColor Red
}

Write-Host "`nDone. Window will close in 5 seconds (or press any key)..." -ForegroundColor Gray
$timeout = 5
while ($timeout -gt 0) {
    if ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null; break }
    Start-Sleep -Seconds 1
    $timeout--
}
