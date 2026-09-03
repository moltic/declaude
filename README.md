# Declaude

A lightweight utility and script to fix the **"Another program is currently using this file"** error on Windows when Claude Desktop updates, allowing you to open Claude immediately without having to reboot your computer.

---

## The Problem

When Claude Desktop updates on Windows (via the MSIX / Windows Store distribution), the update process frequently encounters a deadlock:
1. Windows Centennial / MSIX apps use virtualized registry containers called **Helium silos** (`\REGISTRY\WC\Silo...`).
2. The companion service `CoworkVMService` and lingering background processes hold file locks on `User.dat` and `UserClasses.dat` in `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\SystemAppData\Helium\`.
3. During or immediately following an update, the old silo becomes orphaned in the Windows kernel, leaving these registry files locked exclusively by `System` (PID 4) and `Registry` (PID 280).
4. When you attempt to launch Claude, Windows fails to initialize the new AppX container with error code `0x80070020` (`ERROR_SHARING_VIOLATION` / *"Cannot create the Desktop AppX container because an error was encountered converting the job"*), displaying:
   > **Another program is currently using this file.**

Traditionally, the only known fix was restarting Windows so the kernel unmounts all hives during shutdown.

---

## The Solution: Declaude

`Declaude` clears the deadlock without rebooting:
1. Gracefully stops `CoworkVMService` and terminates any lingering processes (`cowork-svc.exe`, `chrome-native-host.exe`, `Claude.exe`).
2. Scans `HKLM:\SYSTEM\CurrentControlSet\Control\hivelist` for orphaned Claude `\REGISTRY\WC\Silo*` differencing hives.
3. Invokes the native Windows kernel API `NtUnloadKey2` with `REG_FORCE_UNLOAD` via an elevated SYSTEM worker to unmount the locked silos.
4. Releases all file locks on `User.dat` and `UserClasses.dat`.
5. Automatically relaunches Claude Desktop.

---

## Quick Usage

### Option 1: Run `declaude.cmd` or `declaude.exe` (Recommended)
Simply double-click:
- **`declaude.cmd`** (or `declaude.exe`)

Accept the standard Windows UAC prompt. Within 2–3 seconds, the locked kernel silos are freed and Claude Desktop opens.

### Option 2: Run from PowerShell Terminal
Run in an elevated or standard PowerShell terminal:
```powershell
.\declaude.ps1
```
*(If run from a standard terminal, it will automatically prompt for elevation via UAC).*

---

## Permanent Prevention: Migrate to Standalone EXE

If you prefer to never deal with MSIX container locks again, Anthropic also provides an official standalone EXE installer (Squirrel-based). The standalone version installs directly into your user profile (`%LOCALAPPDATA%\Programs\Claude`) and does not use `WindowsApps` or Helium container silos, eliminating this issue permanently.

To switch to the standalone version (preserving all your existing chats, settings, and MCP servers in `%APPDATA%\Claude`):
```powershell
powershell -ExecutionPolicy Bypass -File .\migrate-to-exe.ps1
```
Or manually run:
```powershell
winget install --id Anthropic.Claude --installer-type exe
```

---

## Building from Source

To recompile `declaude.exe`:

### Using .NET Framework compiler (`csc.exe` - built into Windows):
```cmd
csc /target:exe /win32manifest:app.manifest /out:declaude.exe Program.cs
```

### Using modern .NET SDK:
```cmd
dotnet build -c Release
```
