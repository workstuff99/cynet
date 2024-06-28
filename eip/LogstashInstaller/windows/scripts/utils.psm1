$installPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_ROOT', 'Machine')
$Logfile = "$installPath\logs.log"

Function LogWrite
{
    Param ([string]$logstring)
    $timestamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $caller = $MyInvocation.PSCommandPath
    $LogLine = "$timestamp [$caller] $logstring"
    Add-content $Logfile -value $LogLine
    Write-Output $LogLine
}

Function GetEtag([string]$URL){
    $response = Invoke-WebRequest -Method Get -URI $URL -UseBasicParsing
    $response.Headers["ETag"]
}


Function ReadEtagVersion([string]$versionFilePath) {
    return Get-Content -Path $versionFilePath -Raw
}


Function CheckEtagExists([string]$versionFilePath, [string]$resourceURL) {
    if (Test-Path "$versionFilePath") {
        $etag = ReadEtagVersion $versionFilePath
        if ($etag -eq "") {
            LogWrite "$versionFilePath is empty. Fetching new etag from $resourceURL" | Out-Null
            $etag = GetEtag $resourceURL
            Add-Content -Path $versionFilePath -Value $etag
            return $false
        }
        LogWrite "Found existing $etag in $versionFilePath" | Out-Null
        return $true
    }

    LogWrite "Creating new ETag version file for $versionFilePath from $resourceURL" | Out-Null
    $etag = GetEtag $resourceURL
    New-Item -Path $versionFilePath -Value $etag | Out-Null
    return $false
}

Function GetConfigToken {
    $configPath = "$installPath\config.json"
    LogWrite "Reading TKN from $configPath" | Out-Null
    $config = Get-Content -Path $configPath -Raw
    $json = $config | ConvertFrom-Json
    return $json.tkn
}

Function GetConfigUrl {
    $configPath = "$installPath\config.json"
    $rawJson = Get-Content -Path "$configPath" -Raw
    $config = $rawJson | ConvertFrom-Json
    return $config.url
}

Function MergeConfig([string]$existingPath, [string]$newPath, [bool]$replaceCredentials) {
    $newJson = Get-Content -Path $newPath -Raw
    $newConfigJson = $newJson | ConvertFrom-Json

    $existingConfig = Get-Content -Path $existingPath -Raw
    $existingConfigJson = $existingConfig | ConvertFrom-Json

    # add missing providers
    foreach ($provider in $newConfigJson.providers.PSObject.Properties)
    {
        if (!([bool]($existingConfigJson.providers.PSobject.Properties.name -contains $provider.Name))) {
            LogWrite "adding missing '$($provider.Name):$($provider.Value)' provider to config" | Out-Null
            $existingConfigJson.providers | Add-Member -MemberType NoteProperty -Name $provider.Name -Value $provider.Value
        }
    }

    # update url and token
    if ($replaceCredentials -eq $True) {
        $existingConfigJson.url = $newConfigJson.url
        $existingConfigJson.tkn = $newConfigJson.tkn
        if (Get-Member -inputobject $newConfigJson -name "group" -Membertype Properties) {
            $existingConfigJson | Add-Member -Force -MemberType NoteProperty -Name "group" -Value $newConfigJson.group
        }
    }

    # Write merged config to existing config file and remove the downloaded one
    LogWrite "Updating $existingPath" | Out-Null
    $existingConfigJson | ConvertTo-Json | Out-File $existingPath
}

Export-ModuleMember -Function LogWrite
Export-ModuleMember -Function ReadEtagVersion
Export-ModuleMember -Function CheckEtagExists
Export-ModuleMember -Function GetConfigToken
Export-ModuleMember -Function GetConfigUrl
Export-ModuleMember -Function MergeConfig