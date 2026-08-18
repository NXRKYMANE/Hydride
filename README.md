# ✨ Hydride — Windows RAM Clean Service

<p align="center">
  <img src="https://img.shields.io/github/followers/NXRKYMANE?style=social" />
  <img src="https://img.shields.io/github/forks/NXRKYMANE/Hydride" />
  <img src="https://img.shields.io/github/stars/NXRKYMANE/Hydride" />
  <img src="https://img.shields.io/badge/-Rust-000000?style=flat&logo=rust&logoColor=white" />
  <img src="https://img.shields.io/badge/Douyin-Ozones-000000?style=flat&logo=tiktok&logoColor=white" />
  <img src="https://img.shields.io/badge/QQ-946777609-12B7F5?style=flat&logo=tencentqq&logoColor=white" />
  <img src="https://komarev.com/ghpvc/?username=NXRKYMANE&repo=Hydride&label=Views&color=00BFFF&style=flat" />
</p>

A lightweight high-performance physical memory cleaner service, built on Standby and PCL2. [中文文档](README_CN.md)

Built in high-performance **Rust** as a single native binary (~150 KB, UPX-packed) — no runtime required on the target machine.

> This project is built as a wrapper around the old version of **PCL2** (Plain Craft Launcher 2, by **龙腾猫跃**), combining its core memory-cleanup engine with system Standby-cache cleanup, repackaged into a long-running service with dual-engine dynamic scheduling and automatic cleanup.

## How It Works

1. On startup, decodes `Libs/LIBPCL2.dll` (base64) into `wrcs.exe` under `%WINDIR%\Temp\WRCS`.
2. Runs a 60-second cycle with two engines, interleaved by memory-usage tiers:
   - **PCL2 engine** (flush working sets): every 25% tier, 1–5 runs/min, logged in `Used` format
   - **Standby engine** (built-in, flush cache): fixed at 1 run/min, logged in `Standby` format
3. Each PCL2 cleanup runs `wrcs.exe --memory` once, comparing memory before and after, spread evenly across the cycle.
4. On exit, forcefully terminates all `wrcs` processes and deletes `%WINDIR%\Temp\WRCS`.

## Project Structure

```
Hydride/
├── Project/                         # Rust service source and build (main implementation)
│   ├── service_core.rs              # Main program (dual-engine scheduling + monitoring + cleanup)
│   ├── main.rs                      # Program entry
│   ├── Cargo.toml                   # Project file (edition 2024 / extreme release optimization)
│   └── installer.iss                # Inno Setup installer script
├── Misc/                            # Assets
│   ├── Background.bmp / .png        # Wizard left-side background image (source + bitmap)
│   ├── Proj.bmp                     # Wizard small top-right image (from Proj.png)
│   ├── Proj.ico                     # Installer and program icon
│   └── Proj.png                     # Icon source image
├── Libs/
│   └── LIBPCL2.dll                  # Memory cleanup engine (base64-encoded, decoded to wrcs.exe at runtime)
├── Publish/                         # Build output (published exe and installer)
├── .github/                         # Issue / PR templates
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── app.manifest                     # UAC administrator manifest
├── BUILD.ps1                        # One-click build script (compile → publish → package)
├── .gitattributes                   # Git language stats exclusion (installer / peripheral scripts)
├── CLAUDE.md                        # Project rules (AI collaboration conventions)
├── CODE_OF_CONDUCT.md               # Code of Conduct
├── CONTRIBUTING.md                  # Contribution guide
├── LICENSE
├── README.md                        # English documentation
├── README_CN.md                     # Chinese documentation
└── SECURITY.md                      # Security policy
```

## Requirements

**To run:**
- Windows 10 / 11 (or Windows Server equivalent)
- Administrator privileges (UAC manifest included)
- [Osmium](https://github.com/NXRKYMANE/Osmium) — prerequisite framework that registers Hydride as a Windows service

**To build:**
- [Rust](https://www.rust-lang.org/tools/install) (stable, edition 2024)
- Inno Setup 7 (only needed for packaging)

## Build

Run from the project root:

```bash
.\BUILD.ps1
```

The publish output is a single native executable: `hydride_svc64.exe` (Rust, no runtime dependencies).

## Inno Setup Installer

Build the installer package:

```bash
# 1. Build the project (as above)
# 2. Install Inno Setup (https://jrsoftware.org/isdl.php)
# 3. Compile the installer
ISCC.exe Project\installer.iss
```

Output: `Publish\hydride-svc-win-x64-setup.exe`.

Installer features:
- Bilingual UI (English / Simplified Chinese), defaulting to system language
- Smart version comparison: silent upgrade, reinstall prompt for same version, downgrade warning
- Installs `hydride_svc64.exe`, `Libs/`; writes the service TOML config
- Registers and starts the service via Osmium with exit-code checks (Abort / Retry / Ignore on failure)
- In silent mode (`/S`), waits for the old process to exit
- On uninstall, deletes the service via Osmium and removes all files

> **Osmium Integration Notes:** TOML paths with backslashes must use single-quoted literal strings; Osmium is located via the registry key `HKLM\...\App Paths\os.exe`; `ExecAndCaptureOutput` captures exit codes and shows an Abort / Retry / Ignore dialog on failure.

## Deployment

Use the Inno Setup installer from [Releases](https://github.com/NXRKYMANE/Hydride/releases) for a complete setup with automatic service registration.

For manual deployment:
1. Copy `hydride_svc64.exe` from `Publish/` to the target machine.
2. Place `Libs/LIBPCL2.dll` in the same directory as the exe.
3. Install [Osmium](https://github.com/NXRKYMANE/Osmium) (registers `os.exe` to PATH automatically).
4. Register the service: `os.exe --install Libs\hydride_svc64.toml`
5. Start the service: `os.exe --start hydride_svc64`

## Disclaimer

**This project is essentially a rather trivial utility and cannot be guaranteed to work on all computers. Test the built-in memory cleanup of a PCL2 launcher first and watch for side effects; if there is no noticeable improvement or the overhead increases, remove this service immediately.**

## Sponsor

If this project helps you, feel free to [sponsor us](https://ifdian.net/a/NXRKYMANE).

## License

Copyright © 2026 NXRKYMANE SOFTWARE
