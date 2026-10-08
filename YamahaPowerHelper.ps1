# ============================================================
# Yamaha Power Helper for Windows
# Tested with Yamaha R-N2000A / Yamaha Extended Control API
# ============================================================


# ----------------------------
# Configuration
# ----------------------------

$YamahaIP = "192.168.1.100"

# Yamaha API input name used by the PC.
$PCInput = "usb_dac"

# Optional volume setting applied when the script powers the Yamaha on.
$SetStartupVolume = $false
$StartVolume = 96

$EnableLogging = $true
$LogPath = "C:\Logs\YamahaPowerHelper.log"

# Put Yamaha into standby when signing out of Windows.
$StandbyOnLogoff = $false

# ----------------------------
# Advanced settings
# ----------------------------

$ShutdownRequestTimeoutMs = 750
$NormalRequestTimeoutMs = 1500
$StatusRequestTimeoutMs = 1000

$StartupRetryCount = 30
$StartupRetryDelayMs = 1000

$PowerOnPollCount = 40
$PowerOnPollDelayMs = 100


# ----------------------------
# Initial setup
# ----------------------------

if ($EnableLogging) {
    $LogDirectory = Split-Path -Parent $LogPath

    if ($LogDirectory -and -not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
}

Add-Type -AssemblyName System.Windows.Forms


if (-not ("YamahaPowerMessageWindow" -as [type])) {

    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

public class YamahaPowerMessageWindow : NativeWindow, IDisposable
{
    private const int WM_POWERBROADCAST  = 0x0218;
    private const int WM_QUERYENDSESSION = 0x0011;
    private const int WM_ENDSESSION      = 0x0016;

    private const int PBT_APMSUSPEND          = 0x0004;
    private const int PBT_APMRESUMECRITICAL   = 0x0006;
    private const int PBT_APMRESUMESUSPEND    = 0x0007;
    private const int PBT_APMRESUMEAUTOMATIC  = 0x0012;
    private const int ENDSESSION_LOGOFF = unchecked((int)0x80000000);

    private readonly string _pcInput;
    private readonly bool _setStartupVolume;
    private readonly int _startVolume;
    private readonly bool _standbyOnLogoff;
    private readonly bool _enableLogging;
    private readonly string _logPath;

    private readonly int _shutdownRequestTimeoutMs;
    private readonly int _normalRequestTimeoutMs;
    private readonly int _statusRequestTimeoutMs;
    private readonly int _startupRetryCount;
    private readonly int _startupRetryDelayMs;
    private readonly int _powerOnPollCount;
    private readonly int _powerOnPollDelayMs;

    private readonly string _baseUrl;

    private int _wakeWorkerRunning = 0;

    private static readonly object LogLock = new object();


    public YamahaPowerMessageWindow(
        string yamahaIP,
        string pcInput,
        bool setStartupVolume,
        int startVolume,
        bool standbyOnLogoff,
        bool enableLogging,
        string logPath,
        int shutdownRequestTimeoutMs,
        int normalRequestTimeoutMs,
        int statusRequestTimeoutMs,
        int startupRetryCount,
        int startupRetryDelayMs,
        int powerOnPollCount,
        int powerOnPollDelayMs)
    {
        _pcInput = pcInput;
        _setStartupVolume = setStartupVolume;
        _startVolume = startVolume;
        _standbyOnLogoff = standbyOnLogoff;
        _enableLogging = enableLogging;
        _logPath = logPath;

        _shutdownRequestTimeoutMs = shutdownRequestTimeoutMs;
        _normalRequestTimeoutMs = normalRequestTimeoutMs;
        _statusRequestTimeoutMs = statusRequestTimeoutMs;
        _startupRetryCount = startupRetryCount;
        _startupRetryDelayMs = startupRetryDelayMs;
        _powerOnPollCount = powerOnPollCount;
        _powerOnPollDelayMs = powerOnPollDelayMs;

        _baseUrl =
            "http://" +
            yamahaIP +
            "/YamahaExtendedControl/v1";

        CreateParams cp = new CreateParams();
        CreateHandle(cp);

        Log("Helper started.");

        QueueWakeCheck("Startup");
    }


    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_POWERBROADCAST)
        {
            int eventType = m.WParam.ToInt32();

            switch (eventType)
            {
                case PBT_APMSUSPEND:
                    Log("PBT_APMSUSPEND received.");
                    StandbyIfUsingPCInput("Suspend");
                    break;

                case PBT_APMRESUMEAUTOMATIC:
                    Log("PBT_APMRESUMEAUTOMATIC received.");
                    QueueWakeCheck("Resume");
                    break;

                case PBT_APMRESUMESUSPEND:
                    Log("PBT_APMRESUMESUSPEND received.");
                    break;

                case PBT_APMRESUMECRITICAL:
                    Log("PBT_APMRESUMECRITICAL received.");
                    QueueWakeCheck("Critical resume");
                    break;
            }
        }
        else if (m.Msg == WM_QUERYENDSESSION)
        {
            Log("WM_QUERYENDSESSION received.");

            m.Result = new IntPtr(1);
            return;
        }
		else if (m.Msg == WM_ENDSESSION)
		{
			bool sessionEnding =
				m.WParam != IntPtr.Zero;

			int flags =
				m.LParam.ToInt32();

			bool isLogoff =
				(flags & ENDSESSION_LOGOFF) != 0;

			if (sessionEnding)
			{
				Log(
					"WM_ENDSESSION received: " +
					(isLogoff ? "logoff." : "shutdown/restart.")
				);

				if (!isLogoff || _standbyOnLogoff)
				{
					StandbyIfUsingPCInput(
						isLogoff
							? "Logoff"
							: "Shutdown/restart"
					);
				}
			}
		}

        base.WndProc(ref m);
    }


    private void StandbyIfUsingPCInput(string reason)
    {
        try
        {
            string power;
            string input;

            if (!TryGetStatus(
                    out power,
                    out input,
                    _shutdownRequestTimeoutMs))
            {
                Log(
                    reason +
                    ": Yamaha status query failed."
                );

                return;
            }

            Log(
                reason +
                ": power=" +
                power +
                ", input=" +
                input
            );

            if (
                String.Equals(
                    power,
                    "on",
                    StringComparison.OrdinalIgnoreCase
                )
                &&
                String.Equals(
                    input,
                    _pcInput,
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                if (
                    SendCommand(
                        "/main/setPower?power=standby",
                        _shutdownRequestTimeoutMs
                    )
                )
                {
                    Log(reason + ": standby command sent.");
                }
                else
                {
                    Log(reason + ": standby command failed.");
                }
            }
        }
        catch (Exception ex)
        {
            Log(
                reason +
                ": error: " +
                ex.Message
            );
        }
    }


    private void QueueWakeCheck(string reason)
    {
        if (
            Interlocked.CompareExchange(
                ref _wakeWorkerRunning,
                1,
                0
            ) != 0
        )
        {
            return;
        }

        ThreadPool.QueueUserWorkItem(
            delegate
            {
                try
                {
                    WakeIfStandby(reason);
                }
                finally
                {
                    Interlocked.Exchange(
                        ref _wakeWorkerRunning,
                        0
                    );
                }
            }
        );
    }


    private void WakeIfStandby(string reason)
    {
        Log(reason + ": checking Yamaha state.");

        string power = null;
        string input = null;

        bool gotStatus = false;

        for (
            int attempt = 1;
            attempt <= _startupRetryCount;
            attempt++
        )
        {
            if (
                TryGetStatus(
                    out power,
                    out input,
                    _statusRequestTimeoutMs
                )
            )
            {
                gotStatus = true;
                break;
            }

            Thread.Sleep(_startupRetryDelayMs);
        }

        if (!gotStatus)
        {
            Log(reason + ": Yamaha unreachable.");
            return;
        }

        Log(
            reason +
            ": power=" +
            power +
            ", input=" +
            input
        );

        // If Yamaha is already on, leave its current input and volume untouched.
        if (
            !String.Equals(
                power,
                "standby",
                StringComparison.OrdinalIgnoreCase
            )
        )
        {
            return;
        }

        if (
            !SendCommand(
                "/main/setPower?power=on",
                _normalRequestTimeoutMs
            )
        )
        {
            Log(reason + ": power-on command failed.");
            return;
        }

        bool poweredOn = false;

        for (
            int attempt = 1;
            attempt <= _powerOnPollCount;
            attempt++
        )
        {
            Thread.Sleep(_powerOnPollDelayMs);

            if (
                TryGetStatus(
                    out power,
                    out input,
                    _statusRequestTimeoutMs
                )
                &&
                String.Equals(
                    power,
                    "on",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                poweredOn = true;
                break;
            }
        }

        if (!poweredOn)
        {
            Log(reason + ": Yamaha did not finish powering on.");
            return;
        }

        if (
            SendCommand(
                "/main/setInput?input=" +
                Uri.EscapeDataString(_pcInput),
                _normalRequestTimeoutMs
            )
        )
        {
            Log(
                reason +
                ": input set to " +
                _pcInput +
                "."
            );
        }
        else
        {
            Log(reason + ": input change failed.");
        }

        if (_setStartupVolume)
        {
            if (
                SendCommand(
                    "/main/setVolume?volume=" +
                    _startVolume.ToString(),
                    _normalRequestTimeoutMs
                )
            )
            {
                Log(
                    reason +
                    ": volume set to " +
                    _startVolume.ToString() +
                    "."
                );
            }
            else
            {
                Log(reason + ": volume change failed.");
            }
        }
    }


    private bool TryGetStatus(
        out string power,
        out string input,
        int timeoutMs)
    {
        power = null;
        input = null;

        try
        {
            string json =
                HttpGet(
                    _baseUrl +
                    "/main/getStatus",
                    timeoutMs
                );

            if (json == null)
                return false;

            power =
                GetJsonString(
                    json,
                    "power"
                );

            input =
                GetJsonString(
                    json,
                    "input"
                );

            return
                power != null &&
                input != null;
        }
        catch
        {
            return false;
        }
    }


    private bool SendCommand(
        string command,
        int timeoutMs)
    {
        try
        {
            string response =
                HttpGet(
                    _baseUrl +
                    command,
                    timeoutMs
                );

            if (response == null)
                return false;

            Match match =
                Regex.Match(
                    response,
                    "\"response_code\"\\s*:\\s*(-?\\d+)",
                    RegexOptions.IgnoreCase
                );

            if (match.Success)
            {
                return match.Groups[1].Value == "0";
            }

            return true;
        }
        catch
        {
            return false;
        }
    }


    private string HttpGet(
        string url,
        int timeoutMs)
    {
        HttpWebRequest request =
            (HttpWebRequest)
            WebRequest.Create(url);

        request.Method = "GET";
        request.Timeout = timeoutMs;
        request.ReadWriteTimeout = timeoutMs;
        request.KeepAlive = false;

        using (
            HttpWebResponse response =
                (HttpWebResponse)
                request.GetResponse()
        )
        using (
            StreamReader reader =
                new StreamReader(
                    response.GetResponseStream()
                )
        )
        {
            return reader.ReadToEnd();
        }
    }


    private string GetJsonString(
        string json,
        string property)
    {
        Match match =
            Regex.Match(
                json,
                "\"" +
                Regex.Escape(property) +
                "\"\\s*:\\s*\"([^\"]*)\"",
                RegexOptions.IgnoreCase
            );

        if (!match.Success)
            return null;

        return match.Groups[1].Value;
    }


    private void Log(string text)
    {
        if (!_enableLogging)
            return;

        string line =
            DateTime.Now.ToString(
                "yyyy-MM-dd HH:mm:ss.fff"
            )
            +
            "  "
            +
            text;

        lock (LogLock)
        {
            try
            {
                File.AppendAllText(
                    _logPath,
                    line +
                    Environment.NewLine
                );
            }
            catch
            {
            }
        }
    }


    public void Dispose()
    {
        Log("Helper stopped.");

        if (Handle != IntPtr.Zero)
        {
            DestroyHandle();
        }
    }
}
"@ -ReferencedAssemblies System.Windows.Forms.dll
}


# ----------------------------
# Start helper
# ----------------------------

$Listener = New-Object YamahaPowerMessageWindow(
    $YamahaIP,
    $PCInput,
    $SetStartupVolume,
    $StartVolume,
    $StandbyOnLogoff,
    $EnableLogging,
    $LogPath,
    $ShutdownRequestTimeoutMs,
    $NormalRequestTimeoutMs,
    $StatusRequestTimeoutMs,
    $StartupRetryCount,
    $StartupRetryDelayMs,
    $PowerOnPollCount,
    $PowerOnPollDelayMs
)

try {
    while ($true) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
}
finally {
    $Listener.Dispose()
}