# 🧠 Hydride System Memory Manager Service

Hydride System Memory Manager Service — a lightweight and high-performance Windows system memory management service that periodically flushes process working sets to reduce physical memory pressure.

Built with high-performance **C#** on **.NET 10**, compiled to a single native binary via **NativeAOT** — no .NET Runtime required on the target machine.

> This project is built as a wrapper around the old version of **PCL2** (Plain Craft Launcher 2, by **龙腾猫跃**), repackaging its core memory-cleanup engine into a long-running service with dynamic scheduling and automatic cleanup.

## ⚙️ How It Works

1. On startup, decodes `libs/LIBPCL2.dll` (base64) into `hsmmts.exe` under `%WINDIR%\Temp\HSMM`.
2. Runs a 60-second cycle, adjusting cleanup frequency across 8 tiers (every 12.5%): the higher the usage, the more frequent the cleanups (1–8 per minute).
3. Each cleanup runs `hsmmts.exe --memory` once, comparing memory before and after, spread evenly across the cycle.
4. On exit, forcefully terminates all `hsmmts` processes and deletes `%WINDIR%\Temp\HSMM`.

## 📁 Project Structure

```
Hydride/
├── csharp/                          # C# service source and build
│   ├── ServiceCore.cs               # Main program (memory monitoring + dynamic cleanup scheduling, top-level statements entry)
│   ├── Hydride.csproj               # Project file (.NET 10 / NativeAOT / single-file publish)
│   ├── installer.iss                # Inno Setup installer script
│   └── publish/                     # Build output (published exe and installer)
├── misc/                            # Assets
│   ├── Background.bmp / .png        # Wizard left-side background image (source + bitmap)
│   ├── Proj.bmp                     # Wizard small top-right image
│   ├── Proj.ico                     # Installer and program icon
│   └── Proj.png                     # Icon source image
├── docs/                            # Web documentation
│   ├── README_CN.html
│   └── README_EN.html
├── libs/
│   └── LIBPCL2.dll                  # Memory cleanup engine (base64-encoded, decoded to hsmmts.exe at runtime)
├── .github/                         # Issue / PR templates
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── app.manifest                     # UAC administrator manifest
├── BUILD.ps1                        # One-click build script (compile → publish → package)
├── .gitattributes                   # Git language stats exclusion (installer / peripheral scripts)
├── AGENTS.md                        # Project rules (AI collaboration conventions)
├── CODE_OF_CONDUCT.md               # Code of Conduct
├── CONTRIBUTING.md                  # Contribution guide
├── LICENSE
├── README.md / README_EN.md
└── SECURITY.md                      # Security policy
```

## 📋 Requirements

**To run:**
- Windows 10 / 11 (or Windows Server equivalent)
- Administrator privileges (UAC manifest included)
- [Silanes](https://github.com/NXRKYMANE/Silanes) — prerequisite framework that registers Hydride as a Windows service

**To build:**
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- Visual Studio 2022+ or Build Tools (with "Desktop development with C++" workload)
- Inno Setup 7 (only needed for packaging)

## 🛠️ Build

Build from a **Developer Command Prompt for VS** (or PowerShell with VS environment loaded):

```bash
dotnet build
```

The publish output is a single native executable: `hydride_svc64.exe` (NativeAOT, no runtime dependencies).

## 📦 Inno Setup Installer

Build the installer package:

```bash
# 1. Build the project (as above)
# 2. Install Inno Setup (https://jrsoftware.org/isdl.php)
# 3. Compile the installer
ISCC.exe csharp\installer.iss
```

Output: `csharp\publish\hydride-svc-win-x64-setup-v1.2.0.exe`.

Installer features:
- Bilingual UI (English / Simplified Chinese), defaulting to system language
- Smart version comparison: silent upgrade, reinstall prompt for same version, downgrade warning
- Installs `hydride_svc64.exe`, `libs/`, and docs; writes the service YAML config
- Registers and starts the service via Silanes with exit-code checks (Abort / Retry / Ignore on failure)
- In silent mode (`/S`), waits for the old process to exit
- On uninstall, deletes the service via Silanes and removes all files

> **Silanes Integration Notes:** YAML paths need no escaping; silanes is located via the registry key `HKLM\...\App Paths\silanes64.exe`; `ExecAndCaptureOutput` captures exit codes and shows an Abort / Retry / Ignore dialog on failure.

## 🚀 Deployment

Use the Inno Setup installer from [Releases](https://github.com/NXRKYMANE/Hydride/releases) for a complete setup with automatic service registration.

For manual deployment:
1. Copy `hydride_svc64.exe` from `csharp/publish/` to the target machine.
2. Place `libs/LIBPCL2.dll` in the same directory as the exe.
3. Install [Silanes](https://github.com/NXRKYMANE/Silanes) (registers `silanes64.exe` to PATH).
4. Register the service: `silanes64.exe -m --install libs\hydride_svc64.yaml`
5. Start the service: `silanes64.exe -m --start hydride_svc64`

## ⚠️ Disclaimer

**This project is essentially a rather trivial utility and cannot be guaranteed to work on all computers. Test the built-in memory cleanup of a PCL2 launcher first and watch for side effects; if there is no noticeable improvement or the overhead increases, remove this service immediately.**

## 💖 Sponsor

If this project helps you, feel free to [sponsor us](https://ifdian.net/a/NXRKYMANE).

## 📄 License

Copyright © 2026 NXRKYMANE SOFTWARE
