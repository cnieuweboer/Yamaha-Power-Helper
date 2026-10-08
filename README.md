# Yamaha Power Helper

A small Windows helper for Yamaha amplifiers/receivers that support the Yamaha Extended Control API.

It was originally made for a Yamaha R-N2000A used as the main audio output for a Windows PC.

The goal is to make the amplifier behave more naturally with PC sleep, resume and shutdown:

- On Windows sleep/hibernate: put the Yamaha into standby if the configured PC input is active.
- On Windows resume/logon: if the Yamaha is in standby, power it on and switch to the configured PC input.
- On shutdown/restart: put the Yamaha into standby if the configured PC input is active.
- If the Yamaha is already on using another input, leave it alone.
- Optionally set a startup volume when the script powers the Yamaha on.
- Optionally put the Yamaha into standby on Windows logoff.

## Files

- `YamahaPowerHelper.ps1` — main helper
- `StartYamahaPowerHelper.vbs` — starts the PowerShell helper invisibly
- `Yamaha Power Helper.xml` — Task Scheduler task that can be imported

## Configuration

Edit the configuration section near the top of `YamahaPowerHelper.ps1`.

The main settings are:

```powershell
$YamahaIP = "192.168.1.100"
$PCInput = "usb_dac"

$SetStartupVolume = $false
$StartVolume = 96

$StandbyOnLogoff = $false

$EnableLogging = $true
$LogPath = "C:\Logs\YamahaPowerHelper.log"
```

### Yamaha IP

Set:

```powershell
$YamahaIP
```

to the IP address of your amplifier.

Using a DHCP reservation or static IP is recommended.

### PC input

Set:

```powershell
$PCInput
```

to the Yamaha API input name used by your PC.

For the R-N2000A USB DAC input:

```powershell
$PCInput = "usb_dac"
```

### Startup volume

Volume changes are disabled by default.

To enable them:

```powershell
$SetStartupVolume = $true
$StartVolume = 96
```

The volume value is passed directly to the Yamaha API, so verify the correct value for your model before enabling this.

### Standby on logoff

By default, logging out of Windows does not put the Yamaha into standby.

To enable that behavior:

```powershell
$StandbyOnLogoff = $true
```

### Logging

Logging can be disabled with:

```powershell
$EnableLogging = $false
```

The default log location is:

```text
C:\Logs\YamahaPowerHelper.log
```

## Installation

The included Task Scheduler XML assumes the files are placed here:

```text
C:\Scripts\Yamaha\YamahaPowerHelper.ps1
C:\Scripts\Yamaha\StartYamahaPowerHelper.vbs
```

Copy the files to that folder, edit the configuration in `YamahaPowerHelper.ps1`, then import:

```text
Yamaha Power Helper.xml
```

into Windows Task Scheduler.

The task starts `StartYamahaPowerHelper.vbs` at logon. The VBScript launches the PowerShell helper without leaving a visible PowerShell window open.

The helper then remains running for the Windows session and reacts to Windows power/session events.

## Requirements

- Windows PowerShell 5.1 or later
- A Yamaha model supporting Yamaha Extended Control
- Network control / Network Standby enabled on the Yamaha
- The PC and Yamaha reachable over the same network

## Notes

The script was developed and tested with a Yamaha R-N2000A. Other Yamaha models using the same Extended Control API may also work, but input names and supported behavior can differ.
