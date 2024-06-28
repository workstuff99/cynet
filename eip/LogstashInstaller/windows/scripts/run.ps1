param (
    [string]$installPath = "C:\cynet-logstash",
    [string]$outputToFile = "false",
    [string]$fetchEtag = "true"
)

$scriptsPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_SCRIPTS', 'Machine')
Import-Module "$scriptsPath\utils.psm1"

LogWrite "Executing run script.."

$installPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_ROOT', 'Machine')

& "$scriptsPath\render.ps1" -installPath $installPath -outputToFile $outputToFile -fetchEtag $fetchEtag
& "$scriptsPath\firewall.ps1"
LogWrite '--------------------------------------------------------------------------------------'
$logstashBat = "$installPath\logstash\bin\logstash.bat"
&$logstashBat -f "$installPath\logstash.conf" -l "$installPath\logs"
