<# =====================================================================
 APMS
 Advanced Performance Management Suite
 Version: 1.2.7
 ===================================================================== #>

param(
    [switch]$Silent,
    [switch]$SkipRestorePoint,

    [switch]$Full,
    [switch]$Temp,
    [switch]$Browser,
    [switch]$WindowsUpdate,
    [switch]$DISM,
    [switch]$SFC,
    [switch]$Telemetry
)

Set-StrictMode -Version Latest

# =====================================================================
# AUTO ELEVATION
# =====================================================================

$currentIdentity = `
    [Security.Principal.WindowsIdentity]::GetCurrent()

$currentPrincipal = `
    New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (
    -not $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
) {

    Start-Process `
        powershell.exe `
        -Verb RunAs `
        -ArgumentList (
            "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        )

    exit
}

# =====================================================================
# CONFIGURATION
# =====================================================================

$ErrorActionPreference = "Stop"

$ScriptStart = Get-Date

$Date = Get-Date -Format "yyyyMMdd_HHmmss"

$RootPath = Join-Path `
    $PSScriptRoot `
    "APMS"

$LogsPath = Join-Path `
    $RootPath `
    "Logs"

$ReportsPath = Join-Path `
    $RootPath `
    "Reports"

@(
    $RootPath,
    $LogsPath,
    $ReportsPath
) | ForEach-Object {

    if (!(Test-Path $_)) {

        New-Item `
            -ItemType Directory `
            -Path $_ `
            -Force | Out-Null
    }
}

$TranscriptFile = Join-Path `
    $LogsPath `
    "Transcript_$Date.log"

$LogFile = Join-Path `
    $LogsPath `
    "APMS_$Date.log"

$ReportFile = Join-Path `
    $ReportsPath `
    "Report_$Date.html"

$RestoreName = "APMS_$Date"

$Global:TotalFreedBytes = 0

$Global:ModuleResults = @()

$Global:ExcludedPaths = @(
    "C:\Windows\System32",
    "C:\Windows\WinSxS",
    "C:\Program Files",
    "C:\Program Files (x86)"
)

Start-Transcript `
    -Path $TranscriptFile `
    -Append | Out-Null

# =====================================================================
# PROCESS PRIORITY
# =====================================================================

try {

    $process = Get-Process `
        -Id $PID

    $process.PriorityClass = "BelowNormal"
}
catch {

    Write-Host `
        "Unable to change process priority"
}

# =====================================================================
# CORE
# =====================================================================

function Write-Log {

    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $time = Get-Date `
        -Format "yyyy-MM-dd HH:mm:ss"

    $line = "[$time] [$Level] $Message"

    try {

        [System.IO.File]::AppendAllText(
            $LogFile,
            $line + [Environment]::NewLine
        )

        if (!$Silent) {

            switch ($Level) {

                "ERROR" {
                    Write-Host $line -ForegroundColor Red
                }

                "WARN" {
                    Write-Host $line -ForegroundColor Yellow
                }

                default {
                    Write-Host $line
                }
            }
        }
    }
    catch {

        Write-Host `
            "Logging failure: $_"
    }
}

function Convert-Bytes {

    param([Int64]$Bytes)

    switch ($Bytes) {

        { $_ -ge 1TB } {
            return "{0:N2} TB" -f ($Bytes / 1TB)
        }

        { $_ -ge 1GB } {
            return "{0:N2} GB" -f ($Bytes / 1GB)
        }

        { $_ -ge 1MB } {
            return "{0:N2} MB" -f ($Bytes / 1MB)
        }

        { $_ -ge 1KB } {
            return "{0:N2} KB" -f ($Bytes / 1KB)
        }

        default {
            return "$Bytes Bytes"
        }
    }
}

function Wait-Exit {

    if (!$Silent) {

        Write-Host ""

        Read-Host `
            "Press ENTER to continue"
    }
}

function Show-Header {

    if ($Silent) {
        return
    }

    Clear-Host

    Write-Host ""
    Write-Host "======================================================"
    Write-Host "      ___           ___           ___           ___     
     /\  \         /\  \         /\__\         /\  \    
    /::\  \       /::\  \       /::|  |       /::\  \   
   /:/\:\  \     /:/\:\  \     /:|:|  |      /:/\ \  \  
  /::\~\:\  \   /::\~\:\  \   /:/|:|__|__   _\:\~\ \  \ 
 /:/\:\ \:\__\ /:/\:\ \:\__\ /:/ |::::\__\ /\ \:\ \ \__\
 \/__\:\/:/  / \/__\:\/:/  / \/__/~~/:/  / \:\ \:\ \/__/
      \::/  /       \::/  /        /:/  /   \:\ \:\__\  
      /:/  /         \/__/        /:/  /     \:\/:/  /  
     /:/  /                      /:/  /       \::/  /   
     \/__/                       \/__/         \/__/    "
    Write-Host "      Advanced Performance Management Suite"
    Write-Host "                    Version 1.2.7"
    Write-Host "======================================================"
    Write-Host ""
}

function Stop-ServiceSafe {

    param([string]$Name)

    try {

        $service = Get-Service `
            -Name $Name `
            -ErrorAction SilentlyContinue

        if ($null -eq $service) {

            Write-Log `
                "Service not found: $Name" `
                "WARN"

            return
        }

        if ($service.Status -ne "Stopped") {

            Write-Log `
                "Stopping service: $Name"

            Stop-Service `
                -Name $Name `
                -Force `
                -ErrorAction Stop

            $service.WaitForStatus(
                "Stopped",
                "00:00:10"
            )
        }
    }
    catch {

        Write-Log `
            "Unable to stop service: $Name | $_" `
            "ERROR"
    }
}

function Start-ServiceSafe {

    param([string]$Name)

    try {

        $service = Get-Service `
            -Name $Name `
            -ErrorAction SilentlyContinue

        if ($null -eq $service) {
            return
        }

        if ($service.Status -ne "Running") {

            Write-Log `
                "Starting service: $Name"

            Start-Service `
                -Name $Name `
                -ErrorAction Stop

            $service.WaitForStatus(
                "Running",
                "00:00:10"
            )
        }
    }
    catch {

        Write-Log `
            "Unable to start service: $Name | $_" `
            "ERROR"
    }
}

function Test-FreeSpace {

    param(
        [int]$MinimumGB = 5
    )

    try {

        $drive = Get-PSDrive C

        $freeGB = [math]::Round(
            $drive.Free / 1GB,
            2
        )

        if ($freeGB -lt $MinimumGB) {

            Write-Log (
                "Low free space detected: " +
                "$freeGB GB"
            ) "WARN"

            return $false
        }

        return $true
    }
    catch {

        Write-Log `
            "Free space check failed" `
            "ERROR"

        return $false
    }
}

function Invoke-ModuleSafe {

    param(
        [string]$Name,
        [scriptblock]$Script
    )

    try {

        Write-Log `
            "Executing module: $Name"

        & $Script

        $Global:ModuleResults += [PSCustomObject]@{
            Module = $Name
            Status = "OK"
        }

        Write-Log `
            "Module completed: $Name"
    }
    catch {

        $Global:ModuleResults += [PSCustomObject]@{
            Module = $Name
            Status = "ERROR"
        }

        Write-Log `
            "Module failed: $Name | $_" `
            "ERROR"
    }
}

# =====================================================================
# RESTORE POINT
# =====================================================================

function New-RestorePoint {

    if ($SkipRestorePoint) {

        Write-Log `
            "Restore point skipped"

        return
    }

    try {

        Write-Log `
            "Creating restore point"

        Enable-ComputerRestore `
            -Drive "C:\" | Out-Null

        Checkpoint-Computer `
            -Description $RestoreName `
            -RestorePointType "MODIFY_SETTINGS"

        Write-Log `
            "Restore point created"
    }
    catch {

        Write-Log `
            "Restore point creation failed: $_" `
            "WARN"
    }
}

# =====================================================================
# CLEANUP ENGINE
# =====================================================================

function Remove-FolderContent {

    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    foreach ($excluded in $Global:ExcludedPaths) {

        if (
            $Path.StartsWith(
                $excluded,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {

            Write-Log `
                "Blocked protected path: $Path" `
                "WARN"

            return
        }
    }

    if (!(Test-Path $Path)) {

        Write-Log `
            "Path not found: $Path" `
            "WARN"

        return
    }

    try {

        Write-Progress `
            -Activity "Cleaning" `
            -Status $Path `
            -PercentComplete 0

        $items = Get-ChildItem `
            -Path $Path `
            -Force `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object {

                ($_.Attributes `
                    -band `
                    [IO.FileAttributes]::ReparsePoint) -eq 0
            }

        $size = (
            $items |
            Measure-Object `
                -Property Length `
                -Sum
        ).Sum

        if ($null -eq $size) {
            $size = 0
        }

        foreach ($item in $items) {

            try {

                if (
                    $item.Extension -in @(
                        ".etl",
                        ".blf"
                    )
                ) {
                    continue
                }

                Remove-Item `
                    -LiteralPath $item.FullName `
                    -Force `
                    -Recurse `
                    -ErrorAction SilentlyContinue

                Start-Sleep `
                    -Milliseconds 50
            }
            catch {

                Write-Log `
                    "Skipped locked file: $($item.FullName)" `
                    "WARN"
            }
        }

        $Global:TotalFreedBytes += $size

        Write-Log (
            "Cleaned: " +
            $Path +
            " | Freed: " +
            (Convert-Bytes $size)
        )

        Write-Progress `
            -Activity "Cleaning" `
            -Completed
    }
    catch {

        Write-Log `
            "Cleanup failed: $Path | $_" `
            "ERROR"
    }
}

# =====================================================================
# CLEANUP MODULES
# =====================================================================

function Clear-OldLogs {

    Write-Log `
        "Cleaning old logs"

    $maxAge = `
        (Get-Date).AddDays(-30)

    @(
        $LogsPath,
        $ReportsPath
    ) | ForEach-Object {

        Get-ChildItem `
            -Path $_ `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -lt $maxAge
            } |
            Remove-Item `
                -Force `
                -ErrorAction SilentlyContinue
    }
}

function Clear-TempFiles {

    Write-Log `
        "Cleaning temporary files"

    @(
        $env:TEMP,
        "C:\Windows\Temp",
        "C:\Temp"
    ) | ForEach-Object {

        Remove-FolderContent $_
    }
}

function Clear-DNS {

    Write-Log `
        "Flushing DNS cache"

    ipconfig /flushdns | Out-Null
}

function Clear-Recycle {

    Write-Log `
        "Emptying recycle bin"

    Clear-RecycleBin `
        -Force `
        -ErrorAction SilentlyContinue
}

function Clear-WindowsUpdateCache {

    Write-Log `
        "Cleaning Windows Update cache"

    Stop-ServiceSafe `
        "wuauserv"

    Stop-ServiceSafe `
        "bits"

    Remove-FolderContent `
        "C:\Windows\SoftwareDistribution\Download"

    Start-ServiceSafe `
        "wuauserv"

    Start-ServiceSafe `
        "bits"
}

function Clear-WER {

    Write-Log `
        "Cleaning WER reports"

    Remove-FolderContent `
        "C:\ProgramData\Microsoft\Windows\WER"
}

function Clear-BrowserCache {

    Write-Log `
        "Cleaning browser cache"

    $chromeProfiles = Get-ChildItem `
        "$env:LOCALAPPDATA\Google\Chrome\User Data" `
        -Directory `
        -ErrorAction SilentlyContinue

    foreach ($browserProfile in $chromeProfiles) {

        Remove-FolderContent `
            (Join-Path `
                $browserProfile.FullName `
                "Cache")
    }

    $edgeProfiles = Get-ChildItem `
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data" `
        -Directory `
        -ErrorAction SilentlyContinue

    foreach ($browserProfile in $edgeProfiles) {

        Remove-FolderContent `
            (Join-Path `
                $browserProfile.FullName `
                "Cache")
    }

    $firefoxProfiles = Get-ChildItem `
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" `
        -Directory `
        -ErrorAction SilentlyContinue

    foreach ($browserProfile in $firefoxProfiles) {

        Remove-FolderContent `
            (Join-Path `
                $browserProfile.FullName `
                "cache2")
    }
}

function Clear-DeliveryOptimization {

    Write-Log `
        "Cleaning Delivery Optimization cache"

    Remove-FolderContent `
        "C:\Windows\SoftwareDistribution\DeliveryOptimization"
}

function Clear-GPUShaderCache {

    Write-Log `
        "Cleaning GPU shader cache"

    @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache"
    ) | ForEach-Object {

        Remove-FolderContent $_
    }
}

function Clear-DefenderHistory {

    Write-Log `
        "Cleaning Defender history"

    Remove-FolderContent `
        "C:\ProgramData\Microsoft\Windows Defender\Scans\History"
}

function Clear-MemoryDumps {

    Write-Log `
        "Cleaning memory dumps"

    @(
        "C:\Windows\Minidump",
        "C:\Windows\MEMORY.DMP"
    ) | ForEach-Object {

        Remove-FolderContent $_
    }
}

function Clear-Prefetch {

    Write-Log `
        "Cleaning Prefetch"

    Remove-FolderContent `
        "C:\Windows\Prefetch"
}

function Optimize-WinSxS {

    if (!(Test-FreeSpace 10)) {

        Write-Log `
            "Skipping WinSxS optimization due to low space" `
            "WARN"

        return
    }

    Write-Log `
        "Optimizing WinSxS"

    DISM `
        /Online `
        /Cleanup-Image `
        /StartComponentCleanup `
        /ResetBase
}

function Invoke-DISMScan {

    if (!(Test-FreeSpace 10)) {

        Write-Log `
            "Skipping DISM due to low space" `
            "WARN"

        return
    }

    Write-Log `
        "Running DISM"

    DISM `
        /Online `
        /Cleanup-Image `
        /RestoreHealth `
        /StartComponentCleanup `
        /Quiet `
        /NoRestart
}

function Invoke-SFCScan {

    Write-Log `
        "Running SFC"

    sfc /scannow
}

function Export-DriverInventory {

    Write-Log `
        "Exporting driver inventory"

    pnputil /enum-drivers > `
        (Join-Path `
            $LogsPath `
            "drivers_$Date.txt")
}

function Get-SystemTelemetry {

    Write-Log `
        "Collecting telemetry"

    $cpu = Get-CimInstance `
        Win32_Processor |
        Select-Object `
            -ExpandProperty Name

    $ram = [math]::Round(
        (
            Get-CimInstance `
                Win32_ComputerSystem
        ).TotalPhysicalMemory / 1GB,
        2
    )

    $disk = Get-PSDrive C

    $telemetry = [PSCustomObject]@{

        CPU = $cpu

        RAM_GB = $ram

        FreeSpace = Convert-Bytes `
            $disk.Free

        Date = Get-Date
    }

    $jsonPath = Join-Path `
        $ReportsPath `
        "Telemetry_$Date.json"

    $telemetry |
        ConvertTo-Json |
        Set-Content `
            $jsonPath
}

function Install-ScheduledTask {

    Write-Log `
        "Installing scheduled task"

    $action = `
        New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Silent -Full"

    $trigger = `
        New-ScheduledTaskTrigger `
            -Weekly `
            -DaysOfWeek Sunday `
            -At 3am

    Register-ScheduledTask `
        -TaskName "APMS" `
        -Action $action `
        -Trigger $trigger `
        -RunLevel Highest `
        -Force
}

# =====================================================================
# REPORT
# =====================================================================

function Export-HTMLReport {

    Add-Type `
        -AssemblyName System.Web

    $freed = Convert-Bytes `
        $Global:TotalFreedBytes

    $logContent = `
        Get-Content `
            $LogFile |
            Out-String

    $encodedLog = `
        [System.Web.HttpUtility]::HtmlEncode(
            $logContent
        )

    $moduleTable = `
        $Global:ModuleResults |
        ConvertTo-Html `
            -Fragment

    $elapsed = `
        New-TimeSpan `
            -Start $ScriptStart `
            -End (Get-Date)

$html = @"
<html>
<head>
<title>APMS Report</title>
<style>
body {
    background: #111;
    color: #eee;
    font-family: Arial;
    padding: 30px;
}
table {
    border-collapse: collapse;
    width: 100%;
}
td, th {
    border: 1px solid #555;
    padding: 8px;
}
pre {
    background: #222;
    padding: 20px;
    white-space: pre-wrap;
}
</style>
</head>
<body>

<h1>APMS Report</h1>

<p><b>Date:</b> $(Get-Date)</p>

<p><b>Total Freed Space:</b> $freed</p>

<p><b>Execution Time:</b> $elapsed</p>

<h2>Module Results</h2>

$moduleTable

<h2>Logs</h2>

<pre>$encodedLog</pre>

</body>
</html>
"@

    Set-Content `
        -Path $ReportFile `
        -Value $html `
        -Encoding UTF8
}

# =====================================================================
# EXIT ENGINE
# =====================================================================

function Exit-APMS {

    Export-HTMLReport

    $elapsed = `
        New-TimeSpan `
            -Start $ScriptStart `
            -End (Get-Date)

    Write-Log (
        "Execution Time: " +
        $elapsed.ToString()
    )

    Write-Log (
        "Total Freed Space: " +
        (Convert-Bytes `
            $Global:TotalFreedBytes)
    )

    [GC]::Collect()

    [GC]::WaitForPendingFinalizers()

    Stop-Transcript | Out-Null

    exit
}

# =====================================================================
# EXECUTION
# =====================================================================

function Invoke-FullCleanup {

    Invoke-ModuleSafe `
        "Old Logs" `
        { Clear-OldLogs }

    Invoke-ModuleSafe `
        "Temp Files" `
        { Clear-TempFiles }

    Invoke-ModuleSafe `
        "DNS Cache" `
        { Clear-DNS }

    Invoke-ModuleSafe `
        "Recycle Bin" `
        { Clear-Recycle }

    Invoke-ModuleSafe `
        "Windows Update" `
        { Clear-WindowsUpdateCache }

    Invoke-ModuleSafe `
        "WER Reports" `
        { Clear-WER }

    Invoke-ModuleSafe `
        "Browser Cache" `
        { Clear-BrowserCache }

    Invoke-ModuleSafe `
        "Delivery Optimization" `
        { Clear-DeliveryOptimization }

    Invoke-ModuleSafe `
        "GPU Shader Cache" `
        { Clear-GPUShaderCache }

    Invoke-ModuleSafe `
        "Defender History" `
        { Clear-DefenderHistory }

    Invoke-ModuleSafe `
        "Memory Dumps" `
        { Clear-MemoryDumps }

    Invoke-ModuleSafe `
        "WinSxS" `
        { Optimize-WinSxS }

    Invoke-ModuleSafe `
        "DISM" `
        { Invoke-DISMScan }

    Invoke-ModuleSafe `
        "SFC" `
        { Invoke-SFCScan }

    Invoke-ModuleSafe `
        "Driver Inventory" `
        { Export-DriverInventory }
}

function Show-Menu {

    Write-Host ""
    Write-Host "1. Full cleanup"
    Write-Host "2. Temporary files"
    Write-Host "3. Browser cache"
    Write-Host "4. Windows Update cache"
    Write-Host "5. DISM"
    Write-Host "6. SFC"
    Write-Host "7. WinSxS"
    Write-Host "8. Prefetch"
    Write-Host "9. Delivery Optimization"
    Write-Host "10. GPU Shader cache"
    Write-Host "11. Defender history"
    Write-Host "12. Memory dumps"
    Write-Host "13. Telemetry"
    Write-Host "14. Install scheduled task"
    Write-Host "15. Exit"
    Write-Host ""

    return Read-Host `
        "Select an option"
}

# =====================================================================
# MAIN
# =====================================================================

Show-Header

Write-Log `
    "========================================="

Write-Log `
    "START APMS"

Write-Log `
    "========================================="

Write-Log (
    "Execution Path: " +
    $PSScriptRoot
)

Write-Log (
    "Silent Mode: " +
    $Silent
)

Write-Log (
    "PowerShell Version: " +
    $PSVersionTable.PSVersion
)

New-RestorePoint

# =====================================================================
# CLI MODE
# =====================================================================

if ($Full) {

    Invoke-FullCleanup

    Exit-APMS
}

if ($Temp) {

    Clear-TempFiles

    Exit-APMS
}

if ($Browser) {

    Clear-BrowserCache

    Exit-APMS
}

if ($WindowsUpdate) {

    Clear-WindowsUpdateCache

    Exit-APMS
}

if ($DISM) {

    Invoke-DISMScan

    Exit-APMS
}

if ($SFC) {

    Invoke-SFCScan

    Exit-APMS
}

if ($Telemetry) {

    Get-SystemTelemetry

    Exit-APMS
}

# =====================================================================
# INTERACTIVE MODE
# =====================================================================

do {

    $Option = Show-Menu

    switch ($Option) {

        "1"  { Invoke-FullCleanup }
        "2"  { Clear-TempFiles }
        "3"  { Clear-BrowserCache }
        "4"  { Clear-WindowsUpdateCache }
        "5"  { Invoke-DISMScan }
        "6"  { Invoke-SFCScan }
        "7"  { Optimize-WinSxS }
        "8"  { Clear-Prefetch }
        "9"  { Clear-DeliveryOptimization }
        "10" { Clear-GPUShaderCache }
        "11" { Clear-DefenderHistory }
        "12" { Clear-MemoryDumps }
        "13" { Get-SystemTelemetry }
        "14" { Install-ScheduledTask }
        "15" { break }

        default {

            Write-Host ""
            Write-Host "Invalid option"
            Write-Host ""
        }
    }

}
while ($Option -ne "15")

Write-Log `
    "========================================="

Write-Log `
    "END APMS"

Write-Log `
    "========================================="

Exit-APMS