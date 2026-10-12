$YamahaIP = "192.168.1.4"

$status = Invoke-RestMethod `
    -Uri "http://$YamahaIP/YamahaExtendedControl/v1/main/getStatus" `
    -TimeoutSec 2

$status