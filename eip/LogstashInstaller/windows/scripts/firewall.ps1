$installPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_ROOT', 'Machine')
$scriptsPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_SCRIPTS', 'Machine')
Import-Module "$scriptsPath\utils.psm1"

LogWrite "Executing firewall script.."

try {
    # Reading ports that need a firewall rule from user config
    LogWrite "Reading firewall rules from config"
    $rawJson = Get-Content -Path "$installPath\config.json" -Raw
    $config = $rawJson | ConvertFrom-Json
    $ports = @()
    foreach ($provider in $config.providers.PSObject.Properties)
    {
        $ports += $provider.Value
    }

    LogWrite "Creating UDP and TCP firewall Allow rule for ports: $($ports -join ', ')"

    $rules = Get-NetFirewallRule
    $par = @{
        DisplayName = ""
        LocalPort = $ports
        Profile = "Any"
        Protocol =""
        Action = "Allow"
    }

    $par.DisplayName = "Allow Cynet CLM UDP"
    $par.Protocol = "UDP"
    if ($rules.DisplayName.Contains($par.DisplayName)) {Remove-NetFirewallRule -DisplayName $par.DisplayName}
    New-NetFirewallRule @par

    $par.DisplayName = "Allow Cynet CLM TCP"
    $par.Protocol = "TCP"
    if ($rules.DisplayName.Contains($par.DisplayName)) {Remove-NetFirewallRule -DisplayName $par.DisplayName}
    New-NetFirewallRule @par
} catch {
    LogWrite "Could not configure firewall. Skipping.."
    LogWrite $_
}