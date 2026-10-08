Set shell = CreateObject("WScript.Shell")

shell.Run _
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Scripts\Yamaha\YamahaPowerHelper.ps1""", _
    0, _
    False