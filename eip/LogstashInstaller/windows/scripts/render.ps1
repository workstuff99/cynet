param (
    [string]$installPath = "C:\cynet-logstash",
    [string]$outputToFile = "false",
    [string]$fetchEtag = "true"
)


$installPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_ROOT', 'Machine')
$scriptsPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_SCRIPTS', 'Machine')
Import-Module "$scriptsPath\utils.psm1"

LogWrite "Executing render script.."

$rawJson = Get-Content -Path "$installPath\config.json" -Raw
$config = $rawJson | ConvertFrom-Json

$logstashTemplate = Get-Content -Path "$scriptsPath\logstash_template.conf" -Raw
$logstashTemplate = $logstashTemplate.replace('INGRESS_URL', $config.url)

$tkn = $config.tkn
$group = $config.group
if ($group) {
    $encodedQueryString = [uri]::EscapeDataString("$group")
    $tkn = $tkn + "?CynetGroup=$encodedQueryString"
}
$logstashTemplate = $logstashTemplate.replace('TKN_ID', $tkn)

# Rendering pre-set provider input blocks
LogWrite "Configuring logstash ports:"
foreach ($provider in $config.providers.PSObject.Properties)
{
    $replaceVar = $provider.Name.Replace('-', '_').ToUpper()
    LogWrite "$($provider.Name) -> $($provider.Value)"
    $logstashTemplate = $logstashTemplate.replace($replaceVar, $provider.Value)
}


# Generating samplers and rendering
LogWrite ""
LogWrite "Configuring samplers:"
$samplers = ""
foreach ($s in $config.samplers.PSObject.Properties)
{
    LogWrite "$($s.Name) -> $($s.Value)"
    $samplerTemplate = Get-Content -Path $scriptsPath\sampler_template.conf -Raw
    $samplerTemplate = $samplerTemplate.replace('SAMPLER_NAME', $s.Name)
    $samplerTemplate = $samplerTemplate.replace('SAMPLER_PORT', $s.Value)
    $samplers += $samplerTemplate
}
$logstashTemplate = $logstashTemplate.replace('#SAMPLERS' ,$samplers)


# Generate and insert headers block
LogWrite ""
LogWrite "Configuring headers block"
$headersTemplate = Get-Content -Path $scriptsPath\headers_template.conf -Raw

# logstash version
$logstashVersion = Get-Content -Path "$scriptsPath\LOGSTASH_VERSION" -Raw
LogWrite "Adding logstash version: $logstashVersion"
$headersTemplate = $headersTemplate.replace('LOGSTASH_VERSION', $logstashVersion)

# installation version
$installerVersion = Get-Content -Path "$scriptsPath\VERSION" -Raw
LogWrite "Adding installation version: $installerVersion"
$headersTemplate = $headersTemplate.replace('INSTALLER_VERSION', $installerVersion)

if ($fetchEtag -eq "true")
{
    # logstash template conf etag
    $templateVersion = Get-Content -Path "$scriptsPath\templateVersion" -Raw
    LogWrite "Adding logstash template version: $templateVersion"
    $headersTemplate = $headersTemplate.replace('LOGSTASH_TEMPLATE_VERSION', $templateVersion)

    # config json etag
    $configVersion = Get-Content -Path "$scriptsPath\configVersion" -Raw
    LogWrite "Adding config version: $configVersion"
    $headersTemplate = $headersTemplate.replace('CONFIG_VERSION', $configVersion)
}

# insert block
$logstashTemplate = $logstashTemplate.replace('#HEADERS', $headersTemplate)

# output to file
if ($outputToFile -eq "true")
{
    LogWrite "Removing http output"
    $logstashTemplate = $logstashTemplate.Replace("`n","NEW_LINE")
    $logstashTemplate = $logstashTemplate -Replace "#START_OF_HTTP_BLOCK.*?#END_OF_HTTP_BLOCK",""
    $logstashTemplate = $logstashTemplate.Replace("NEW_LINE","`n")

	LogWrite "Adding file output to: $installPath"
	$fileOutputTemplate = @"
	file {
      path => "$installPath\output.log"
      codec => "rubydebug"
    }
"@
	
	$logstashTemplate = $logstashTemplate.replace('#FILE_OUTPUT', $fileOutputTemplate)
}

# creating logstash file and writing new rendered config into it
if (!(Test-Path "$installPath\logstash.conf"))
{
    LogWrite "Creating new logstash.conf"
    New-Item "$installPath\logstash.conf" -type "file"
}
LogWrite "Writing configuration to logstash.conf"
$logstashTemplate | Set-Content -Path "$installPath\logstash.conf"