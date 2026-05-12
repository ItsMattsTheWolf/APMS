Set objShell = CreateObject("Wscript.Shell")

objShell.Run _
"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""APMS.ps1"" -Silent -Full", _
0, _
False