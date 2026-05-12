<# =====================================================================
 APMS
 Advanced Performance Management Suite
 Version: 1.3.0

 Debloat approach inspired by:
   Win11Debloat by Raphire (https://github.com/Raphire/Win11Debloat)
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
    [switch]$Telemetry,
    [switch]$Debloat
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
                    Write-Host $line -ForegroundColor Cyan
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
# DEBLOAT MODULES
# Debloat approach inspired by Win11Debloat by Raphire
# https://github.com/Raphire/Win11Debloat
# Registry keys and implementation are original.
# =====================================================================

function Disable-Telemetry {

    Write-Log "Disabling telemetry and tracking"

    $keys = @{
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" = @{
            "AllowTelemetry" = 0
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{
            "AllowTelemetry"        = 0
            "MaxTelemetryAllowed"   = 0
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" = @{
            "TailoredExperiencesWithDiagnosticDataEnabled" = 0
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" = @{
            "DisabledByGroupPolicy" = 1
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" = @{
            "Enabled" = 0
        }
    }

    foreach ($path in $keys.Keys) {

        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }

        foreach ($name in $keys[$path].Keys) {
            Set-ItemProperty -Path $path -Name $name -Value $keys[$path][$name] -Type DWord -Force
        }
    }

    Write-Log "Telemetry disabled"
}

function Disable-Suggestions {

    Write-Log "Disabling tips, tricks and suggested content"

    $keys = @{
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" = @{
            "SubscribedContent-338388Enabled" = 0
            "SubscribedContent-338389Enabled" = 0
            "SubscribedContent-353698Enabled" = 0
            "SystemPaneSuggestionsEnabled"    = 0
            "SilentInstalledAppsEnabled"      = 0
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" = @{
            "ShowSyncProviderNotifications" = 0
        }
    }

    foreach ($path in $keys.Keys) {

        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }

        foreach ($name in $keys[$path].Keys) {
            Set-ItemProperty -Path $path -Name $name -Value $keys[$path][$name] -Type DWord -Force
        }
    }

    Write-Log "Suggestions disabled"
}

function Disable-LockscreenTips {

    Write-Log "Disabling lock screen tips"

    $path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $path -Name "SubscribedContent-338387Enabled"  -Value 0 -Type DWord -Force

    Write-Log "Lock screen tips disabled"
}

function Disable-EdgeAds {

    Write-Log "Disabling Edge ads and newsfeed"

    $keys = @{
        "HKLM:\SOFTWARE\Policies\Microsoft\Edge" = @{
            "HubsSidebarEnabled"         = 0
            "ShowRecommendationsEnabled" = 0
        }
        "HKCU:\SOFTWARE\Policies\Microsoft\Edge" = @{
            "PersonalizationReportingEnabled" = 0
        }
    }

    foreach ($path in $keys.Keys) {

        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }

        foreach ($name in $keys[$path].Keys) {
            Set-ItemProperty -Path $path -Name $name -Value $keys[$path][$name] -Type DWord -Force
        }
    }

    Write-Log "Edge ads disabled"
}

function Disable-DeliveryOptimization {

    Write-Log "Disabling Delivery Optimization service"

    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "DODownloadMode" -Value 0 -Type DWord -Force

    Stop-ServiceSafe  "DoSvc"
    Set-Service -Name "DoSvc" -StartupType Disabled -ErrorAction SilentlyContinue

    Write-Log "Delivery Optimization disabled"
}

$Global:DefaultBloatApps = @(
    "Microsoft.BingNews"
    "Microsoft.BingWeather"
    "Microsoft.BingFinance"
    "Microsoft.BingSports"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.People"
    "Microsoft.SkypeApp"
    "Microsoft.Todos"
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "Microsoft.YourPhone"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider"
    "Clipchamp.Clipchamp"
    "MicrosoftTeams"
    "Microsoft.MixedReality.Portal"
)

function Remove-BloatApps {

    param(
        [string[]]$Apps = $Global:DefaultBloatApps
    )

    Write-Log "Removing bloatware apps"

    foreach ($app in $Apps) {

        try {

            $pkg = Get-AppxPackage `
                -Name $app `
                -AllUsers `
                -ErrorAction SilentlyContinue

            if ($null -ne $pkg) {

                Write-Log "Removing: $app"

                Remove-AppxPackage `
                    -Package $pkg.PackageFullName `
                    -AllUsers `
                    -ErrorAction SilentlyContinue
            }

            $provPkg = Get-AppxProvisionedPackage `
                -Online |
                Where-Object { $_.DisplayName -eq $app }

            if ($null -ne $provPkg) {

                Remove-AppxProvisionedPackage `
                    -Online `
                    -PackageName $provPkg.PackageName `
                    -ErrorAction SilentlyContinue
            }
        }
        catch {

            Write-Log "Failed to remove: $app | $_" "WARN"
        }
    }

    Write-Log "Bloatware removal complete"
}

function Invoke-DebloatAll {

    Invoke-ModuleSafe "Disable Telemetry"            { Disable-Telemetry }
    Invoke-ModuleSafe "Disable Suggestions"          { Disable-Suggestions }
    Invoke-ModuleSafe "Disable Lockscreen Tips"      { Disable-LockscreenTips }
    Invoke-ModuleSafe "Disable Edge Ads"             { Disable-EdgeAds }
    Invoke-ModuleSafe "Disable Delivery Optimization"{ Disable-DeliveryOptimization }
    Invoke-ModuleSafe "Remove Bloat Apps"            { Remove-BloatApps }
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
# FULL CLEANUP
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

# =====================================================================
# MAIN
# =====================================================================

Write-Log "========================================="
Write-Log "START APMS"
Write-Log "========================================="
Write-Log ("Execution Path: " + $PSScriptRoot)
Write-Log ("Silent Mode: "    + $Silent)
Write-Log ("PowerShell Version: " + $PSVersionTable.PSVersion)

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

if ($Debloat) {
    Invoke-DebloatAll
    Exit-APMS
}

# =====================================================================
# WPF GUI
# =====================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="APMS - Advanced Performance Management Suite"
    Height="620" Width="900"
    MinHeight="580" MinWidth="820"
    WindowStartupLocation="CenterScreen"
    Background="#1A1A1A"
    FontFamily="Segoe UI">

    <Window.Resources>

        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize"   Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#F0F0F0"/>
            <Setter Property="Margin"     Value="0,0,0,8"/>
        </Style>

        <Style x:Key="OptionCheck" TargetType="CheckBox">
            <Setter Property="Margin"     Value="0,3,0,3"/>
            <Setter Property="FontSize"   Value="12"/>
            <Setter Property="Foreground" Value="#D0D0D0"/>
        </Style>

        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Height"     Value="36"/>
            <Setter Property="MinWidth"   Value="100"/>
            <Setter Property="Padding"    Value="16,0"/>
            <Setter Property="FontSize"   Value="13"/>
            <Setter Property="Cursor"     Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button"
               BasedOn="{StaticResource NavButton}">
            <Setter Property="Background" Value="#0067C0"/>
            <Setter Property="Foreground" Value="#242424"/>
            <Setter Property="BorderBrush" Value="#0067C0"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#005BA1"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button"
               BasedOn="{StaticResource NavButton}">
            <Setter Property="Background" Value="#242424"/>
            <Setter Property="Foreground" Value="#F0F0F0"/>
            <Setter Property="BorderBrush" Value="#555555"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2E2E2E"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="PresetButton" TargetType="Button"
               BasedOn="{StaticResource NavButton}">
            <Setter Property="Background"  Value="#242424"/>
            <Setter Property="Foreground"  Value="#F0F0F0"/>
            <Setter Property="BorderBrush" Value="#555555"/>
            <Setter Property="FontSize"    Value="12"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2E2E2E"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SectionCard" TargetType="Border">
            <Setter Property="Background"       Value="#242424"/>
            <Setter Property="BorderBrush"      Value="#3A3A3A"/>
            <Setter Property="BorderThickness"  Value="1"/>
            <Setter Property="CornerRadius"     Value="6"/>
            <Setter Property="Padding"          Value="16"/>
            <Setter Property="Margin"           Value="6"/>
        </Style>

        <Style x:Key="DotIndicator" TargetType="Ellipse">
            <Setter Property="Width"  Value="8"/>
            <Setter Property="Height" Value="8"/>
            <Setter Property="Margin" Value="4,0"/>
        </Style>

    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- TITLE BAR -->
        <Border Grid.Row="0" Background="#1E1E1E"
                BorderBrush="#3A3A3A" BorderThickness="0,0,0,1"
                Padding="24,16">
            <StackPanel>
                <TextBlock Text="APMS" FontSize="22"
                           FontWeight="Bold" Foreground="#FFFFFF"/>
                <TextBlock x:Name="PageSubtitle"
                           FontSize="12" Foreground="#999999"
                           Text="Select which modules you want to run"/>
            </StackPanel>
        </Border>

        <!-- PRESET TOOLBAR -->
        <Border Grid.Row="1" Background="#1E1E1E"
                BorderBrush="#3A3A3A" BorderThickness="0,0,0,1"
                Padding="16,10">
            <WrapPanel Orientation="Horizontal">
                <Button x:Name="BtnSelectAll"   Content="Select All"
                        Style="{StaticResource PresetButton}" Margin="0,0,8,0"/>
                <Button x:Name="BtnSelectNone"  Content="Clear Selection"
                        Style="{StaticResource PresetButton}" Margin="0,0,8,0"/>
                <Button x:Name="BtnSelectSafe"  Content="Safe Defaults"
                        Style="{StaticResource PresetButton}" Margin="0,0,8,0"/>
            </WrapPanel>
        </Border>

        <!-- PAGE CONTAINER -->
        <Grid Grid.Row="2">

            <!-- PAGE 1: CLEANUP -->
            <ScrollViewer x:Name="Page1" VerticalScrollBarVisibility="Auto"
                          Padding="12,12,12,0">
                <WrapPanel Orientation="Horizontal">

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Temporary Files"/>
                            <CheckBox x:Name="ChkTemp"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Temporary files (%TEMP%, C:\Temp)"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkDNS"
                                      Style="{StaticResource OptionCheck}"
                                      Content="DNS cache"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkRecycle"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Recycle bin"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkPrefetch"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Prefetch files"/>
                            <CheckBox x:Name="ChkMemDumps"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Memory dumps"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Browser Cache"/>
                            <CheckBox x:Name="ChkBrowser"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Chrome, Edge, Firefox cache"
                                      IsChecked="True"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Windows Update"/>
                            <CheckBox x:Name="ChkWinUpdate"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Windows Update cache"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkDelivOpt"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Delivery Optimization cache"/>
                            <CheckBox x:Name="ChkWER"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Error reports (WER)"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="System Cache"/>
                            <CheckBox x:Name="ChkGPU"
                                      Style="{StaticResource OptionCheck}"
                                      Content="GPU shader cache (D3D, NVIDIA)"/>
                            <CheckBox x:Name="ChkDefender"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Windows Defender history"/>
                            <CheckBox x:Name="ChkWinSxS"
                                      Style="{StaticResource OptionCheck}"
                                      Content="WinSxS component store (DISM)"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="System Repair"/>
                            <CheckBox x:Name="ChkDISM"
                                      Style="{StaticResource OptionCheck}"
                                      Content="DISM - Repair Windows image"/>
                            <CheckBox x:Name="ChkSFC"
                                      Style="{StaticResource OptionCheck}"
                                      Content="SFC - Scan system files"/>
                        </StackPanel>
                    </Border>

                </WrapPanel>
            </ScrollViewer>

            <!-- PAGE 2: DEBLOAT -->
            <ScrollViewer x:Name="Page2" VerticalScrollBarVisibility="Auto"
                          Visibility="Collapsed" Padding="12,12,12,0">
                <WrapPanel Orientation="Horizontal">

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Privacy"/>
                            <CheckBox x:Name="ChkTelemetry"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Disable telemetry and tracking"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkSuggestions"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Disable tips and suggested content"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkLockscreen"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Disable lock screen tips"
                                      IsChecked="True"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Browser"/>
                            <CheckBox x:Name="ChkEdgeAds"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Disable Edge ads and newsfeed"
                                      IsChecked="True"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Windows Services"/>
                            <CheckBox x:Name="ChkDoSvc"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Disable Delivery Optimization service"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Bloatware Apps"/>
                            <TextBlock FontSize="11" Foreground="#777777"
                                       TextWrapping="Wrap" Margin="0,0,0,8"
                                       Text="Removes pre-installed apps. Most can be reinstalled from the Microsoft Store."/>
                            <CheckBox x:Name="ChkBloat"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Remove default bloatware list"/>
                        </StackPanel>
                    </Border>

                </WrapPanel>
            </ScrollViewer>

            <!-- PAGE 3: TOOLS -->
            <ScrollViewer x:Name="Page3" VerticalScrollBarVisibility="Auto"
                          Visibility="Collapsed" Padding="12,12,12,0">
                <WrapPanel Orientation="Horizontal">

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="System Info"/>
                            <CheckBox x:Name="ChkHwSnap"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Hardware snapshot (CPU, RAM, disk)"
                                      IsChecked="True"/>
                            <CheckBox x:Name="ChkDrivers"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Export driver inventory"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Automation"/>
                            <CheckBox x:Name="ChkTask"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Register weekly scheduled task (Sundays 3 AM)"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SectionCard}" Width="260">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}"
                                       Text="Safety"/>
                            <CheckBox x:Name="ChkRestorePoint"
                                      Style="{StaticResource OptionCheck}"
                                      Content="Create restore point before running"
                                      IsChecked="True"/>
                        </StackPanel>
                    </Border>

                </WrapPanel>
            </ScrollViewer>

        </Grid>

        <!-- BOTTOM BAR -->
        <Border Grid.Row="3" Background="#1E1E1E"
                BorderBrush="#3A3A3A" BorderThickness="0,1,0,0"
                Padding="20,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- BACK -->
                <Button x:Name="BtnBack" Grid.Column="0"
                        Content="Back"
                        Style="{StaticResource SecondaryButton}"
                        Visibility="Collapsed"/>

                <!-- PAGE DOTS -->
                <StackPanel Grid.Column="1" Orientation="Horizontal"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center">
                    <Ellipse x:Name="Dot1" Style="{StaticResource DotIndicator}"
                             Fill="#0067C0"/>
                    <Ellipse x:Name="Dot2" Style="{StaticResource DotIndicator}"
                             Fill="#555555"/>
                    <Ellipse x:Name="Dot3" Style="{StaticResource DotIndicator}"
                             Fill="#555555"/>
                </StackPanel>

                <!-- NEXT / RUN -->
                <StackPanel Grid.Column="2" Orientation="Horizontal">
                    <Button x:Name="BtnNext" Content="Next"
                            Style="{StaticResource PrimaryButton}"/>
                </StackPanel>

            </Grid>
        </Border>

    </Grid>
</Window>
"@

$reader   = New-Object System.Xml.XmlNodeReader $xaml
$window   = [Windows.Markup.XamlReader]::Load($reader)

# --- Element references ---
$page1          = $window.FindName("Page1")
$page2          = $window.FindName("Page2")
$page3          = $window.FindName("Page3")
$btnBack        = $window.FindName("BtnBack")
$btnNext        = $window.FindName("BtnNext")
$btnSelectAll   = $window.FindName("BtnSelectAll")
$btnSelectNone  = $window.FindName("BtnSelectNone")
$btnSelectSafe  = $window.FindName("BtnSelectSafe")
$subtitle       = $window.FindName("PageSubtitle")
$dot1           = $window.FindName("Dot1")
$dot2           = $window.FindName("Dot2")
$dot3           = $window.FindName("Dot3")

# Cleanup checkboxes
$chkTemp        = $window.FindName("ChkTemp")
$chkDNS         = $window.FindName("ChkDNS")
$chkRecycle     = $window.FindName("ChkRecycle")
$chkPrefetch    = $window.FindName("ChkPrefetch")
$chkMemDumps    = $window.FindName("ChkMemDumps")
$chkBrowser     = $window.FindName("ChkBrowser")
$chkWinUpdate   = $window.FindName("ChkWinUpdate")
$chkDelivOpt    = $window.FindName("ChkDelivOpt")
$chkWER         = $window.FindName("ChkWER")
$chkGPU         = $window.FindName("ChkGPU")
$chkDefender    = $window.FindName("ChkDefender")
$chkWinSxS      = $window.FindName("ChkWinSxS")
$chkDISM        = $window.FindName("ChkDISM")
$chkSFC         = $window.FindName("ChkSFC")

# Debloat checkboxes
$chkTelemetry   = $window.FindName("ChkTelemetry")
$chkSuggestions = $window.FindName("ChkSuggestions")
$chkLockscreen  = $window.FindName("ChkLockscreen")
$chkEdgeAds     = $window.FindName("ChkEdgeAds")
$chkDoSvc       = $window.FindName("ChkDoSvc")
$chkBloat       = $window.FindName("ChkBloat")

# Tools checkboxes
$chkHwSnap      = $window.FindName("ChkHwSnap")
$chkDrivers     = $window.FindName("ChkDrivers")
$chkTask        = $window.FindName("ChkTask")
$chkRestorePoint= $window.FindName("ChkRestorePoint")

# --- Page management ---
$script:CurrentPage = 1

$pageSubtitles = @{
    1 = "Select which cleanup modules you want to run"
    2 = "Select which debloat options to apply"
    3 = "Tools, automation and safety options"
}

function Set-AllChecks {
    param([bool]$Value)
    switch ($script:CurrentPage) {
        1 {
            $chkTemp.IsChecked=$Value; $chkDNS.IsChecked=$Value
            $chkRecycle.IsChecked=$Value; $chkPrefetch.IsChecked=$Value
            $chkMemDumps.IsChecked=$Value; $chkBrowser.IsChecked=$Value
            $chkWinUpdate.IsChecked=$Value; $chkDelivOpt.IsChecked=$Value
            $chkWER.IsChecked=$Value; $chkGPU.IsChecked=$Value
            $chkDefender.IsChecked=$Value; $chkWinSxS.IsChecked=$Value
            $chkDISM.IsChecked=$Value; $chkSFC.IsChecked=$Value
        }
        2 {
            $chkTelemetry.IsChecked=$Value; $chkSuggestions.IsChecked=$Value
            $chkLockscreen.IsChecked=$Value; $chkEdgeAds.IsChecked=$Value
            $chkDoSvc.IsChecked=$Value; $chkBloat.IsChecked=$Value
        }
        3 {
            $chkHwSnap.IsChecked=$Value; $chkDrivers.IsChecked=$Value
            $chkTask.IsChecked=$Value; $chkRestorePoint.IsChecked=$Value
        }
    }
}

function Set-SafeDefaults {
    # Cleanup — safe defaults
    $chkTemp.IsChecked=$true;  $chkDNS.IsChecked=$true
    $chkRecycle.IsChecked=$true; $chkPrefetch.IsChecked=$false
    $chkMemDumps.IsChecked=$false; $chkBrowser.IsChecked=$true
    $chkWinUpdate.IsChecked=$true; $chkDelivOpt.IsChecked=$false
    $chkWER.IsChecked=$false; $chkGPU.IsChecked=$false
    $chkDefender.IsChecked=$false; $chkWinSxS.IsChecked=$false
    $chkDISM.IsChecked=$false; $chkSFC.IsChecked=$false
    # Debloat — safe defaults
    $chkTelemetry.IsChecked=$true; $chkSuggestions.IsChecked=$true
    $chkLockscreen.IsChecked=$true; $chkEdgeAds.IsChecked=$true
    $chkDoSvc.IsChecked=$false; $chkBloat.IsChecked=$false
    # Tools — safe defaults
    $chkHwSnap.IsChecked=$true; $chkDrivers.IsChecked=$false
    $chkTask.IsChecked=$false; $chkRestorePoint.IsChecked=$true
}

function Update-Dots {
    $dot1.Fill = if ($script:CurrentPage -eq 1) { "#0067C0" } else { "#BDBDBD" }
    $dot2.Fill = if ($script:CurrentPage -eq 2) { "#0067C0" } else { "#BDBDBD" }
    $dot3.Fill = if ($script:CurrentPage -eq 3) { "#0067C0" } else { "#BDBDBD" }
}

function Set-Page {
    param([int]$Page)
    $script:CurrentPage = $Page
    $page1.Visibility = if ($Page -eq 1) { "Visible" } else { "Collapsed" }
    $page2.Visibility = if ($Page -eq 2) { "Visible" } else { "Collapsed" }
    $page3.Visibility = if ($Page -eq 3) { "Visible" } else { "Collapsed" }
    $btnBack.Visibility = if ($Page -eq 1) { "Collapsed" } else { "Visible" }
    $btnNext.Content = if ($Page -eq 3) { "Run" } else { "Next" }
    $subtitle.Text   = $pageSubtitles[$Page]
    Update-Dots
}

# --- Wire up events ---
$btnBack.Add_Click({      Set-Page ($script:CurrentPage - 1) })
$btnNext.Add_Click({
    if ($script:CurrentPage -lt 3) {
        Set-Page ($script:CurrentPage + 1)
    } else {
        # Run selected modules
        $window.Close()
        Invoke-SelectedModules
    }
})

$btnSelectAll.Add_Click({  Set-AllChecks $true  })
$btnSelectNone.Add_Click({ Set-AllChecks $false })
$btnSelectSafe.Add_Click({ Set-SafeDefaults      })

# --- Invoke selected modules ---
function Invoke-SelectedModules {

    if ($chkRestorePoint.IsChecked) { New-RestorePoint }

    # Cleanup
    if ($chkTemp.IsChecked)       { Invoke-ModuleSafe "Temp Files"            { Clear-TempFiles } }
    if ($chkDNS.IsChecked)        { Invoke-ModuleSafe "DNS Cache"             { Clear-DNS } }
    if ($chkRecycle.IsChecked)    { Invoke-ModuleSafe "Recycle Bin"           { Clear-Recycle } }
    if ($chkPrefetch.IsChecked)   { Invoke-ModuleSafe "Prefetch"              { Clear-Prefetch } }
    if ($chkMemDumps.IsChecked)   { Invoke-ModuleSafe "Memory Dumps"          { Clear-MemoryDumps } }
    if ($chkBrowser.IsChecked)    { Invoke-ModuleSafe "Browser Cache"         { Clear-BrowserCache } }
    if ($chkWinUpdate.IsChecked)  { Invoke-ModuleSafe "Windows Update"        { Clear-WindowsUpdateCache } }
    if ($chkDelivOpt.IsChecked)   { Invoke-ModuleSafe "Delivery Optimization" { Clear-DeliveryOptimization } }
    if ($chkWER.IsChecked)        { Invoke-ModuleSafe "WER Reports"           { Clear-WER } }
    if ($chkGPU.IsChecked)        { Invoke-ModuleSafe "GPU Shader Cache"      { Clear-GPUShaderCache } }
    if ($chkDefender.IsChecked)   { Invoke-ModuleSafe "Defender History"      { Clear-DefenderHistory } }
    if ($chkWinSxS.IsChecked)     { Invoke-ModuleSafe "WinSxS"               { Optimize-WinSxS } }
    if ($chkDISM.IsChecked)       { Invoke-ModuleSafe "DISM"                  { Invoke-DISMScan } }
    if ($chkSFC.IsChecked)        { Invoke-ModuleSafe "SFC"                   { Invoke-SFCScan } }

    # Debloat
    if ($chkTelemetry.IsChecked)   { Invoke-ModuleSafe "Disable Telemetry"             { Disable-Telemetry } }
    if ($chkSuggestions.IsChecked) { Invoke-ModuleSafe "Disable Suggestions"           { Disable-Suggestions } }
    if ($chkLockscreen.IsChecked)  { Invoke-ModuleSafe "Disable Lockscreen Tips"       { Disable-LockscreenTips } }
    if ($chkEdgeAds.IsChecked)     { Invoke-ModuleSafe "Disable Edge Ads"              { Disable-EdgeAds } }
    if ($chkDoSvc.IsChecked)       { Invoke-ModuleSafe "Disable Delivery Optimization" { Disable-DeliveryOptimization } }
    if ($chkBloat.IsChecked)       { Invoke-ModuleSafe "Remove Bloat Apps"             { Remove-BloatApps } }

    # Tools
    if ($chkHwSnap.IsChecked)  { Invoke-ModuleSafe "Hardware Snapshot"    { Get-SystemTelemetry } }
    if ($chkDrivers.IsChecked) { Invoke-ModuleSafe "Driver Inventory"     { Export-DriverInventory } }
    if ($chkTask.IsChecked)    { Invoke-ModuleSafe "Scheduled Task"        { Install-ScheduledTask } }

    Invoke-ModuleSafe "Old Logs" { Clear-OldLogs }

    Exit-APMS
}

# --- Show window ---
[void]$window.ShowDialog()

Write-Log "========================================="
Write-Log "END APMS"
Write-Log "========================================="

Exit-APMS
