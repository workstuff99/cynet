$scriptsPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_SCRIPTS', 'Machine')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module "$scriptsPath\utils.psm1"
Import-Module "$scriptsPath\templateFetcher.psm1"
Import-Module "$scriptsPath\configFetcher.psm1"

LogWrite "Executing updater script.."

$changed = $false

$configChanged = FetchConfig
if ($configChanged) {
    LogWrite "config was changed"
    $changed = $true
}

$templateChanged = FetchTemplate
if ($templateChanged) {
    LogWrite "template was changed"
    $changed = $true
}

if ($changed) {
    LogWrite "Restarting cynet_logstash for new changed to apply.."
    $nssmExe = "$scriptsPath\nssm.exe"
    &$nssmExe "stop" "cynet_logstash"
    Start-Sleep -Seconds 15
    &$nssmExe "start" "cynet_logstash"
} else {
    LogWrite "No changes to config or template found"
}
