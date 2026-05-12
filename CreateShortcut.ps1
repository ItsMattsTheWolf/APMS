$DesktopPath = [Environment]::GetFolderPath("Desktop")

$ShortcutPath = Join-Path `
    $DesktopPath `
    "APMS.lnk"

$TargetPath = "powershell.exe"

$Arguments = `
'-NoProfile -ExecutionPolicy Bypass -File "' +
"$PSScriptRoot\APMS.ps1" + '"'

$WorkingDirectory = $PSScriptRoot

$WshShell = New-Object `
    -ComObject WScript.Shell

$Shortcut = `
    $WshShell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath = $TargetPath

$Shortcut.Arguments = $Arguments

$Shortcut.WorkingDirectory = `
    $WorkingDirectory

$Shortcut.IconLocation = `
    "powershell.exe,0"

$Shortcut.Description = `
    "APMS - Advanced Performance Management Suite"

$Shortcut.Save()

Write-Host ""
Write-Host "Desktop shortcut created:"
Write-Host $ShortcutPath
Write-Host ""