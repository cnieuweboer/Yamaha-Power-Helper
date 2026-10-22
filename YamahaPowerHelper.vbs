Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptFolder = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = fso.BuildPath(scriptFolder, "YamahaPowerHelper.ps1")

shell.Run _
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1Path & """", _
    0, _
    False