# ✨ Hydride — Windows RAM Clean Service

<p align="center">
  <img src="https://img.shields.io/github/followers/NXRKYMANE?style=social" />
  <img src="https://img.shields.io/github/forks/NXRKYMANE/Hydride" />
  <img src="https://img.shields.io/github/stars/NXRKYMANE/Hydride" />
  <img src="https://img.shields.io/badge/-Rust-FFFFFF?style=flat&logo=rust&logoColor=black" />
  <img src="https://img.shields.io/badge/Gitee-NXRKYMANE-FFFFFF?style=flat" />
  <img src="https://img.shields.io/badge/AtomGit-NXRKYMANEX-FFFFFF?style=flat" />
  <img src="https://img.shields.io/badge/Douyin-Ozones-FFFFFF?style=flat&logo=tiktok&logoColor=white" />
  <img src="https://vbr.nathanchung.dev/badge?page_id=NXRKYMANE.Hydride&color=FFFFFF&leftColor=555555&label=Views" />
</p>

A lightweight high-performance physical memory cleaner service, built entirely on native Win32 APIs. [中文文档](README_CN.md)

Built in high-performance **Rust** as a single native binary (~150 KB, UPX-packed) — no runtime or external engine required on the target machine.

> This project performs memory cleanup natively in-process: it enumerates system processes with the Toolhelp32 API and flushes their working sets via `SetProcessWorkingSetSize(-1, -1)` (EmptyWorkingSet), then purges the system Standby cache via `NtSetSystemInformation` — all in one self-contained binary.

## How It Works

1. Runs a 60-second cycle with two engines, interleaved by memory-usage tiers:
   - **WorkingSet engine** (flush working sets of all processes): every 25% tier, 1–5 runs/min, logged in `Used` format
   - **Standby engine** (purge cache): fixed at 1 run/min, logged in `Standby` format
2. **CPU-aware gating:** the WorkingSet frequency is reduced when system CPU load is high (≥30% −1 tier, ≥60% −2 tiers) and paused entirely above 85%, so older machines never suffer cleanup-induced load spikes.
3. Each WorkingSet cleanup enumerates every process once and empties its working set (temporarily paging out inactive memory), comparing memory before and after, spread evenly across the cycle.
3. The Standby engine purges the system Standby list with elevated `SeProfileSingleProcessPrivilege`.
4. Single-instance mutex prevents conflicting concurrent cleanups.

## Efficiency Mode (EcoQoS)

Both the service process and the Osmium host run in Task Manager "efficiency mode" (ProcessPowerThrottling), switching on/off automatically by CPU load:

| Component | Setting | Behavior |
| --- | --- | --- |
| Service (`hydride_svc64.exe`) | `eco_qos = "auto"` | Enters efficiency mode when idle (CPU < 10%), exits when busy (> 30%) |
| Host (`os.exe`) | `host_eco_qos = "auto"` | Enters when idle (CPU < 5%), exits when the host or the service gets busy (> 20%) |

Tuning thresholds: edit the deployed config at `ProgramData\Osmium\svcs\hydride_svc64.osiml` (fields `eco_qos_idle_cpu_pct` / `eco_qos_busy_cpu_pct` / `host_eco_qos_*`), then `os.exe --refresh hydride_svc64`.

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
├── Publish/                         # Build output (published exe and installer)
├── .github/                         # GitHub community templates (issues / PR) & release-sync workflows
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
- Installs `hydride_svc64.exe`; writes the service TOML config
- Registers and starts the service via Osmium with exit-code checks (Abort / Retry / Ignore on failure)
- In silent mode (`/S`), waits for the old process to exit
- On uninstall, deletes the service via Osmium and removes all files

> **Osmium Integration Notes:** TOML paths with backslashes must use single-quoted literal strings; Osmium is located via the registry key `HKLM\...\App Paths\os.exe`; `ExecAndCaptureOutput` captures exit codes and shows an Abort / Retry / Ignore dialog on failure.

## Deployment

Use the Inno Setup installer from [Releases](https://github.com/NXRKYMANE/Hydride/releases) for a complete setup with automatic service registration.

For manual deployment:
1. Copy `hydride_svc64.exe` from `Publish/` to the target machine.
2. Install [Osmium](https://github.com/NXRKYMANE/Osmium) (registers `os.exe` to PATH automatically).
3. Register the service: `os.exe --install hydride_svc64.toml`
4. Start the service: `os.exe --start hydride_svc64`

## Disclaimer

**This project is essentially a rather trivial utility and cannot be guaranteed to work on all computers. Flushing process working sets can temporarily slow down disk activity while paged memory is swapped back; if there is no noticeable improvement or the overhead increases, remove this service immediately.**

## Sponsor

If this project helps you, feel free to [sponsor us](https://ifdian.net/a/NXRKYMANE).

## License

Copyright © 2026 NXRKYMANE SOFTWARE
