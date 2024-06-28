Function FetchConfig {
    $scriptsPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_SCRIPTS', 'Machine')
    Import-Module "$scriptsPath\utils.psm1"

    $installPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_ROOT', 'Machine')

    $tkn = GetConfigToken
    $configVersionFile = "$scriptsPath\configVersion"
    $existingConfigPath = "$installPath\config.json"
    $newConfigPath = "$installPath\newConfig.json"

    $url = GetConfigUrl
    $configResource = "$url/logstash_installer/$tkn/config.json"

    LogWrite "Running config fetcher.." | Out-Null

    $etagExists = CheckEtagExists $configVersionFile $configResource
    # first recreate etag version file if empty or non existant
    if (!($etagExists)) {
        return $false
    }

    $etag = ReadEtagVersion $configVersionFile
    try
    {
        LogWrite "GET $configResource with etag=$etag" | Out-Null
        $response = Invoke-WebRequest -Method Get -Uri $configResource -UseBasicParsing -Headers @{'If-None-Match' = $etag} -OutFile "$newConfigPath" -PassThru
    }
    catch
    {
        switch ($_.Exception.Response.StatusCode.Value__)
        {
            304 {
                LogWrite "No new config file was found. Exiting until next schedule" | Out-Null
                return $false
            }
            default {
                LogWrite "[$_.Exception.Response.StatusCode.Value__] response for $configResource with etag=$etag" | Out-Null
                return $false
            }
        }
    }

    # Perform config file merge
    LogWrite "Merging new config file with the old" | Out-Null
    MergeConfig $existingConfigPath $newConfigPath $False
    Remove-Item $newConfigPath

    # Write newest ETag to version file
    $newEtag = $response.Headers["ETag"]
    LogWrite "Save new ETag '$newEtag' to $configVersionFile" | Out-Null
    $newEtag | Out-File -FilePath "$configVersionFile"

    return $true
}

Export-ModuleMember -Function FetchConfig
