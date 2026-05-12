# APMS — Advanced Performance Management Suite

[![Download](https://img.shields.io/github/v/release/ItsMattsTheWolf/APMS?label=Download&style=for-the-badge&logo=github)](https://github.com/ItsMattsTheWolf/APMS/releases/latest/download/Clean.zip)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-blue?style=for-the-badge&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell)
![License](https://img.shields.io/github/license/ItsMattsTheWolf/APMS?style=for-the-badge)

A Windows cleanup and optimization tool with a native GUI. Removes junk files, repairs your Windows image, debloats pre-installed apps, and generates a full HTML report — all in a single PowerShell script with no external dependencies.

---

## What's new in 1.2.8

- **WPF GUI** — native Windows interface with three dedicated pages (Cleanup, Debloat, Tools)
- **Debloat module** — disable telemetry, remove bloatware apps, silence Edge ads, lock screen tips, and suggested content
- **Preset toolbar** — one-click *Select All*, *Clear Selection*, and *Safe Defaults* presets
- **`-Debloat` parameter** — run the full debloat pass from the command line without opening the GUI

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later
- Administrator privileges (the script requests elevation automatically)

---

## Installation

1. Download and extract `Clean.zip` from the [latest release](https://github.com/ItsMattsTheWolf/APMS/releases/latest/download/Clean.zip).
2. Run `Launch_APMS.bat` to open the GUI, **or** run `CreateShortcut.ps1` to pin a desktop shortcut.

No additional installation or external dependencies required.

---

## Usage

### GUI (recommended)

```bat
Launch_APMS.bat
```

Opens the WPF interface. Select modules across three pages and click **Run**.

### Silent / automated

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "APMS.ps1" -Silent -Full
```

`Launch_APMS.vbs` does exactly this in the background with no window shown — useful for scheduled tasks.

### Parameters

| Parameter           | Description                                              |
|---------------------|----------------------------------------------------------|
| `-Full`             | Runs all cleanup modules                                 |
| `-Temp`             | Cleans temporary files only                              |
| `-Browser`          | Cleans browser cache only                                |
| `-WindowsUpdate`    | Cleans Windows Update cache only                         |
| `-DISM`             | Runs DISM RestoreHealth only                             |
| `-SFC`              | Runs SFC scan only                                       |
| `-Telemetry`        | Saves a hardware snapshot only                           |
| `-Debloat`          | Runs the full debloat pass only                          |
| `-Silent`           | Suppresses console output (ideal for scheduled tasks)    |
| `-SkipRestorePoint` | Skips system restore point creation                      |

---

## Modules

### Cleanup

| Module                  | What it does                                                                 |
|-------------------------|------------------------------------------------------------------------------|
| Temporary Files         | Empties `%TEMP%`, `C:\Windows\Temp`, and `C:\Temp`                           |
| Browser Cache           | Chrome, Edge, and Firefox (all profiles)                                     |
| Windows Update          | Cleans `SoftwareDistribution\Download`, restarting required services         |
| Delivery Optimization   | Removes Windows delivery optimization cache files                            |
| WER Reports             | Deletes Windows Error Reporting data                                         |
| GPU Shader Cache        | Clears D3D and NVIDIA cache (DXCache / GLCache)                              |
| Defender History        | Removes Windows Defender scan history                                        |
| Memory Dumps            | Deletes minidumps and `MEMORY.DMP`                                           |
| Prefetch                | Clears application prefetch files                                            |
| DNS Cache               | Runs `ipconfig /flushdns`                                                    |
| Recycle Bin             | Empties the recycle bin                                                      |
| WinSxS                  | Optimizes the component store via DISM (requires 10 GB free)                 |
| DISM                    | Repairs the Windows image with `RestoreHealth`                               |
| SFC                     | Verifies and repairs system files with `sfc /scannow`                        |

### Debloat

| Module                       | What it does                                                              |
|------------------------------|---------------------------------------------------------------------------|
| Disable Telemetry            | Sets telemetry registry keys to 0 for both `HKLM` and `HKCU`             |
| Disable Suggestions          | Turns off tips, tricks, and suggested content in the Start menu           |
| Disable Lock Screen Tips     | Removes rotating tips and ads from the Windows lock screen                |
| Disable Edge Ads             | Disables Edge's newsfeed, sidebar recommendations, and personalization    |
| Disable Delivery Optimization| Disables the `DoSvc` service and sets `DODownloadMode` to 0               |
| Remove Bloatware Apps        | Uninstalls pre-installed UWP apps for all users and removes provisioning  |

Default bloatware list: Bing News, Bing Weather, Bing Finance, Bing Sports, Get Help, Get Started, Solitaire Collection, Office Hub, People, Skype, To Do, Feedback Hub, Maps, Groove Music, Movies & TV, Your Phone, Xbox apps, Clipchamp, Teams (consumer), Mixed Reality Portal.

> Apps removed with this module can be reinstalled from the Microsoft Store.

### Tools

| Module             | What it does                                                              |
|--------------------|---------------------------------------------------------------------------|
| Hardware Snapshot  | Saves CPU, RAM, and free disk space info to a `.json` file               |
| Driver Inventory   | Exports the list of installed drivers to a `.txt` file                   |
| Scheduled Task     | Registers a weekly Task Scheduler entry (Sundays at 3:00 AM, silent)     |

---

## Output files

```text
APMS/
├── Logs/
│   ├── APMS_YYYYMMDD_HHmmss.log          ← Structured execution log
│   ├── Transcript_YYYYMMDD_HHmmss.log    ← Full console transcript
│   └── drivers_YYYYMMDD_HHmmss.txt       ← Driver inventory
└── Reports/
    ├── Report_YYYYMMDD_HHmmss.html       ← HTML report (space freed, module results)
    └── Telemetry_YYYYMMDD_HHmmss.json    ← Hardware snapshot
```

Logs and reports older than 30 days are deleted automatically on each run.

---

## Security

- Creates a **system restore point** before doing anything (skippable with `-SkipRestorePoint`).
- Never touches protected paths: `System32`, `WinSxS`, `Program Files`.
- Skips files locked by the system (`.etl`, `.blf`) and symbolic links.
- DISM and WinSxS modules require at least **10 GB of free space** before running.
- Runs at **BelowNormal** process priority to avoid interfering with other applications.

---

## Project structure

```text
Clean/
├── APMS.ps1              ← Main script (cleanup, debloat, GUI)
├── Launch_APMS.bat       ← Interactive GUI launcher
├── Launch_APMS.vbs       ← Silent background launcher
├── CreateShortcut.ps1    ← Creates a desktop shortcut
└── APMS/
    ├── Logs/
    └── Reports/
```

---

## License

This project is licensed under the **MIT License** — free to use, copy, modify, and distribute as long as the original copyright notice is included.

**Author:** <mwframework.contact@gmail.com>
