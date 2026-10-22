# install.ps1
#
# Installs the Yamaha Power Helper scheduled task.
# Keep this file in the same folder as:
#   YamahaPowerHelper.vbs
#   YamahaPowerHelper.ps1
#
# Run this script as the user who should run the helper.
# Administrator rights are not required for the task itself.

$ErrorActionPreference = 'Stop'

$TaskName = 'Yamaha Power Helper'

# ---------------------------------------------------------------------------
# Ask where to place the task
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Task Scheduler folder'
Write-Host 'Leave empty to install the task in the Task Scheduler root.'
Write-Host 'Example: \User'
Write-Host ''

$TaskFolder = Read-Host 'Folder'
$TaskFolder = $TaskFolder.Trim()

if ([string]::IsNullOrWhiteSpace($TaskFolder)) {
    $TaskPath = "\$TaskName"
}
else {
    $TaskFolder = '\' + $TaskFolder.Trim('\')
    $TaskPath = "$TaskFolder\$TaskName"
}

# ---------------------------------------------------------------------------
# Resolve files
# ---------------------------------------------------------------------------

$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbsPath = Join-Path $scriptFolder 'YamahaPowerHelper.vbs'
$ps1Path = Join-Path $scriptFolder 'YamahaPowerHelper.ps1'

if (-not (Test-Path -LiteralPath $vbsPath)) {
    Write-Error "Missing file: $vbsPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $ps1Path)) {
    Write-Error "Missing file: $ps1Path"
    exit 1
}

$escapedVbsPath = [System.Security.SecurityElement]::Escape($vbsPath)

# Current user SID. This makes the task explicitly belong to the user
# running the installer.
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

# ---------------------------------------------------------------------------
# Build Task Scheduler XML
# ---------------------------------------------------------------------------

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Runs Yamaha Power Helper at user logon.</Description>
  </RegistrationInfo>

  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$userSid</UserId>
    </LogonTrigger>
  </Triggers>

  <Principals>
    <Principal id="Author">
      <UserId>$userSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>

  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>

    <IdleSettings>
      <Duration>PT10M</Duration>
      <WaitTimeout>PT1H</WaitTimeout>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>

    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>

  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>&quot;$escapedVbsPath&quot;</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# ---------------------------------------------------------------------------
# Register task
# ---------------------------------------------------------------------------

$tempXml = Join-Path $env:TEMP 'yamaha-power-helper-task.xml'

try {
    Set-Content `
        -LiteralPath $tempXml `
        -Value $taskXml `
        -Encoding Unicode

    & schtasks.exe /Create `
        /TN $TaskPath `
        /XML $tempXml `
        /F

    if ($LASTEXITCODE -ne 0) {
        throw "schtasks.exe failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $tempXml -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Installed scheduled task: $TaskPath"
Write-Host "User: $env:USERDOMAIN\$env:USERNAME"
Write-Host "Helper path: $vbsPath"
Write-Host ''
Write-Host 'Yamaha Power Helper is ready.'