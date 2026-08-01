# 🧠 Hydride System Memory Manager Service

Hydride System Memory Manager Service — a lightweight and high-performance Windows system memory management service that periodically flushes process working sets to reduce physical memory pressure.

Built with high-performance **C#** on **.NET 10**, compiled to a single native binary via **NativeAOT** — no .NET Runtime required on the target machine.

> This project is built as a wrapper around the old version of **PCL2** (Plain Craft Launcher 2, by **龙腾猫跃**), repackaging its core memory-cleanup engine into a long-running service with dynamic scheduling and automatic cleanup.

## ⚙️ How It Works

1. On startup, decodes `libs/LIBPCL2.dll` (base64) into `hsmmts.exe` under `%WINDIR%\Temp\HSMM`.
2. Enters a 60-second loop, dynamically adjusting cleanup frequency across 8 tiers (every 12.5%):
   - **0–12.5%** → 1 cleanup/min
   - **12.5–25%** → 2 cleanups/min
   - **25–37.5%** → 3 cleanups/min
   - **37.5–50%** → 4 cleanups/min
   - **50–62.5%** → 5 cleanups/min
   - **62.5–75%** → 6 cleanups/min
   - **75–87.5%** → 7 cleanups/min
   - **87.5–100%** → 8 cleanups/min
3. Each cleanup runs `hsmmts.exe --memory` once, comparing memory usage before and after; cleanups are spread evenly across the cycle.
4. On exit, forcefully terminates all `hsmmts` processes and deletes `%WINDIR%\Temp\HSMM`.

## 📋 Requirements

**To run:**
- Windows 10 / 11 (or Windows Server equivalent)
- Administrator privileges (UAC manifest included)
- [Silanes](https://github.com/NXRKYMANE/Silanes) — prerequisite framework that registers Hydride as a Windows service

**To build:**
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- Visual Studio 2022+ with "Desktop development with C++" workload (MSVC toolchain + Windows SDK)
- or Visual Studio Build Tools with the same components
- NSIS 3.x (only needed for building the installer)

## 🛠️ Build

Build from a **Developer Command Prompt for VS** (or PowerShell with VS environment loaded):

```bash
dotnet build
```

The publish output is a single native executable:
- `hydride_svc64.exe` — self-contained native binary (NativeAOT), no runtime dependencies

## 📦 NSIS Installer

Build the installer package:

```bash
# 1. Build the project (as above)
# 2. Install NSIS (https://nsis.sourceforge.io/Download)
# 3. Compile the installer
makensis deployment.nsi
```

Output: `publish\hydride-svc-win-x64-setup-v${PRODUCT_VERSION}.exe` (currently v1.0.0).

Installer features:
- Bilingual UI (English / Simplified Chinese) with a language selector on first install, remembered for later runs
- Smart version comparison: silent upgrade, reinstall prompt for the same version, downgrade warning for older versions
- Installs `hydride_svc64.exe`, `libs/`, and documentation to the selected directory
- Writes the service YAML config with the correct install path
- Registers and starts the Windows service via Silanes, with exit-code checks throughout (Abort / Retry / Ignore on failure)
- In silent mode (`/S`), waits for the old process to exit before overwriting
- Custom icon and wizard bitmap, full version metadata on the installer
- On uninstall, deletes the service via Silanes and removes all files

> **Silanes Integration Notes:**
> 1. **YAML Path Handling** — YAML handles backslashes in unquoted values natively (e.g. `C:\Program Files\...`). No escaping or replacement needed — just write the path directly without quotes.
> 2. **Silanes Path Lookup** — `silanes64.exe` may not be in PATH within the installer process. Read the full path from registry: `HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\silanes64.exe`.
> 3. **Exit-Code Checks** — Use `nsExec::ExecToStack` to capture command output and the exit code; register / start / delete failures show an Abort / Retry / Ignore dialog so errors never fail silently.
> 4. **NSIS Variable Expansion** — Single-quoted strings in NSIS do not expand variables; use double quotes.

## 🚀 Deployment

Use the NSIS installer from the [Releases](https://github.com/NXRKYMANE/Hydride/releases) page for a complete setup with automatic service registration.

For manual deployment:
1. Copy `hydride_svc64.exe` from the `publish/` directory to the target machine.
2. Place `libs/LIBPCL2.dll` in the same directory as `hydride_svc64.exe`.
3. Ensure [Silanes](https://github.com/NXRKYMANE/Silanes) is installed (adds `silanes64.exe` to system PATH).
4. Register the service: `silanes64.exe -m --install libs\hydride_svc64.yaml`
5. Start the service: `silanes64.exe -m --start hydride_svc64`

## ⚠️ Disclaimer

**This project is essentially a rather trivial utility. I cannot guarantee that this service will be effective on all computers. It is strongly recommended that you download a PCL2 launcher and test its built-in memory cleanup feature first (there is also a description of this feature inside the launcher) to see if there are any side effects. If you experience negligible results or even increased performance overhead, please remove this service from your computer immediately.**

## 📄 License

Copyright © 2026 NXRKYMANE SOFTWARE
