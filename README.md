# Declaude

[![Release](https://img.shields.io/github/v/release/moltic/declaude?style=flat-square)](https://github.com/moltic/declaude/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?style=flat-square&logo=windows)](https://github.com/moltic/declaude)

Fixes the **"Another program is currently using this file"** error on Windows when Claude Desktop updates, allowing you to launch Claude immediately without rebooting your PC.

---

## Quick Fix (No Installation)

Open PowerShell as your normal user and run this one-liner:

```powershell
irm https://raw.githubusercontent.com/moltic/declaude/main/declaude.ps1 | iex
```

Accept the UAC prompt. The tool will unlock all kernel registry silos and launch Claude Desktop within seconds.

---

## Local Usage

You can also download the latest release or clone this repository:

### 1. Download Pre-compiled Binary
Download [`declaude.exe`](https://github.com/moltic/declaude/releases/latest) from the [Releases](https://github.com/moltic/declaude/releases) page and run or double-click it.

### 2. From Repository
Double-click:
- **`declaude.cmd`** (or `declaude.exe`)

Or run in PowerShell:
```powershell
.\declaude.ps1
```

---

## Why This Happens

When Claude Desktop updates on Windows (MSIX / WindowsApps version):
1. Windows uses isolated container silos (Centennial / Helium) that mount private differencing hives (`User.dat` and `UserClasses.dat`) at `\REGISTRY\WC\Silo...` under kernel processes `System` (PID 4) and `Registry` (PID 280).
2. The companion service `CoworkVMService` and orphaned worker processes keep the old container active during an in-place update.
3. The previous container gets orphaned in the Windows kernel, leaving these registry files locked exclusively.
4. When you attempt to open Claude, Windows fails to convert the container job object with error code `0x80070020` (`ERROR_SHARING_VIOLATION`), and Windows Shell pops up:
   > **Another program is currently using this file.**

Task Manager cannot kill these kernel locks. Previously, the only known resolution was restarting Windows.

---

## How Declaude Solves It

1. Stops `CoworkVMService` and terminates lingering processes (`cowork-svc.exe`, `Claude.exe`, `chrome-native-host.exe`).
2. Scans `HKLM:\SYSTEM\CurrentControlSet\Control\hivelist` for orphaned Claude `\REGISTRY\WC\Silo*` differencing hives.
3. Invokes the native Windows kernel API `NtUnloadKey2` with `REG_FORCE_UNLOAD` via a transient elevated SYSTEM worker to unmount the locked hives.
4. Releases all file locks on `User.dat` and `UserClasses.dat`.
5. Automatically relaunches Claude Desktop.

---

## Permanent Prevention: Switch to Standalone EXE

Anthropic also publishes an official standalone EXE (Squirrel) installer that installs to `%LOCALAPPDATA%\Programs\Claude` instead of `WindowsApps`. It does not use container silos and therefore never suffers from this update deadlock bug.

To switch to the standalone version while preserving all your chats, settings, and MCP servers in `%APPDATA%\Claude`:

```powershell
powershell -ExecutionPolicy Bypass -File .\migrate-to-exe.ps1
```

Or manually:
```powershell
winget install --id Anthropic.Claude --installer-type exe
```

---

## Contributing & Development

To compile `declaude.exe` from source:

```cmd
csc /target:exe /win32manifest:app.manifest /out:declaude.exe Program.cs
```
Or with .NET SDK:
```cmd
dotnet build -c Release
```

## License

[MIT](LICENSE)
