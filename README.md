# APMS — Advanced Performance Management Suite

## Version 1.2.7

[![Download](https://img.shields.io/github/v/release/ItsMattsTheWolf/APMS?label=Download&style=for-the-badge&logo=github)](https://github.com/ItsMattsTheWolf/APMS/releases/latest/download/Clean.zip)

A Windows cleanup and maintenance tool. Removes temporary files, browser cache, update leftovers, and more — with detailed logging and an HTML report on every run.

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later
- Administrator privileges (the script requests elevation automatically)

---

## Installation

1. Extract `Clean.zip` to any folder.
2. Run `Launch_APMS.bat` to open the interactive menu, or run `CreateShortcut.ps1` to create a desktop shortcut.

No additional installation or external dependencies required.

---

## Usage

### Interactive mode

```bat
Launch_APMS.bat
```

Opens a menu with all available options.

### Silent mode (automated)

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "APMS.ps1" -Silent -Full
```

`Launch_APMS.vbs` does exactly this in the background, with no window shown.

### Available parameters

| Parameter           | Description                                              |
|---------------------|----------------------------------------------------------|
| `-Full`             | Runs all cleanup modules                                 |
| `-Temp`             | Cleans temporary files only                              |
| `-Browser`          | Cleans browser cache only                                |
| `-WindowsUpdate`    | Cleans Windows Update cache only                         |
| `-DISM`             | Runs DISM scan only                                      |
| `-SFC`              | Runs SFC scan only                                       |
| `-Telemetry`        | Generates hardware snapshot only                         |
| `-Silent`           | No console output (ideal for scheduled tasks)            |
| `-SkipRestorePoint` | Skips system restore point creation                      |

---

## Modules

| Module                  | Description                                                                  |
|-------------------------|------------------------------------------------------------------------------|
| Temporary Files         | Empties `%TEMP%`, `C:\Windows\Temp`, and `C:\Temp`                           |
| Browser Cache           | Chrome, Edge, and Firefox (all profiles)                                     |
| Windows Update          | Cleans `SoftwareDistribution\Download`, restarting required services         |
| Delivery Optimization   | Removes Windows delivery optimization files                                  |
| WER Reports             | Deletes Windows Error Reporting data                                         |
| GPU Shader Cache        | Clears D3D and NVIDIA cache (DXCache / GLCache)                              |
| Defender History        | Removes Windows Defender scan history                                        |
| Memory Dumps            | Deletes minidumps and `MEMORY.DMP`                                           |
| Prefetch                | Clears application prefetch files                                            |
| WinSxS                  | Optimizes the component store via DISM (requires 10 GB free)                 |
| DISM                    | Repairs the Windows image with `RestoreHealth`                               |
| SFC                     | Verifies and repairs system files with `sfc /scannow`                        |
| DNS Cache               | Runs `ipconfig /flushdns`                                                    |
| Recycle Bin             | Empties the recycle bin                                                      |
| Driver Inventory        | Exports the list of installed drivers to a `.txt` file                       |
| Hardware Snapshot       | Saves CPU, RAM, and free space info to a `.json` file                        |

---

## Generated paths

```text
APMS/
├── Logs/
│   ├── APMS_YYYYMMDD_HHmmss.log         ← Execution log
│   ├── Transcript_YYYYMMDD_HHmmss.log   ← Console transcript
│   └── drivers_YYYYMMDD_HHmmss.txt      ← Driver inventory
└── Reports/
    ├── Report_YYYYMMDD_HHmmss.html      ← HTML report
    └── Telemetry_YYYYMMDD_HHmmss.json   ← Hardware snapshot
```

Logs and reports older than 30 days are deleted automatically on each run.

---

## Scheduled task

From the interactive menu, option **14** registers a Windows Task Scheduler entry that runs a full cleanup every Sunday at 3:00 AM in silent mode.

To register it manually:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "APMS.ps1"
# Then select option 14
```

---

## Security

- Creates a **system restore point** before doing anything (can be skipped with `-SkipRestorePoint`).
- Never touches protected paths: `System32`, `WinSxS`, `Program Files`.
- Skips files locked by the system (`.etl`, `.blf`) and symbolic links.
- DISM and WinSxS modules require at least **10 GB of free space** before running.
- The process runs at **BelowNormal** priority to avoid interfering with other applications.

---

## Project structure

```text
Clean/
├── APMS.ps1              ← Main script
├── Launch_APMS.bat       ← Interactive launcher
├── Launch_APMS.vbs       ← Silent background launcher
├── CreateShortcut.ps1    ← Creates a desktop shortcut
├── APMS.lnk              ← Pre-configured shortcut
└── APMS/
    ├── Logs/
    └── Reports/
```

---

## Code sample

The logging system writes to file and console simultaneously, with level-based color coding:

```powershell
function Write-Log {

    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$time] [$Level] $Message"

    [System.IO.File]::AppendAllText(
        $LogFile,
        $line + [Environment]::NewLine
    )

    if (!$Silent) {
        switch ($Level) {
            "ERROR" { Write-Host $line -ForegroundColor Red    }
            "WARN"  { Write-Host $line -ForegroundColor Yellow }
            default { Write-Host $line -ForegroundColor Cyan   }
        }
    }
}
```

---

## License

This project is licensed under the **MIT License**.

You are free to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of this software, as long as the original copyright notice is included.

**Author:** <mwframework.contact@gmail.com>
