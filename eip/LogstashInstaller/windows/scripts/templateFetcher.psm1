Function FetchTemplate {
    $scriptsPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_SCRIPTS', 'Machine')
    Import-Module "$scriptsPath\utils.psm1"

    $tkn = GetConfigToken
    $templateVersionFile = "$scriptsPath\templateVersion"
    $templatePath = "$scriptsPath\logstash_template.conf"
    $newTemplatePath = "$scriptsPath\new_logstash_template.conf"

    $url = GetConfigUrl
    $templateResource = "$url/logstash_installer/$tkn/logstash_template.conf"

    LogWrite "Running template fetcher.." | Out-Null

    $etagExists = CheckEtagExists $templateVersionFile $templateResource
    # first recreate etag version file if empty or non existant
    if (!($etagExists)) {
        return $false
    }

    $etag = ReadEtagVersion $templateVersionFile
    try
    {
        LogWrite "GET $templateResource with etag=$etag" | Out-Null
        $response = Invoke-WebRequest -Method Get -Uri $templateResource -UseBasicParsing -Headers @{'If-None-Match' = $etag} -OutFile "$newTemplatePath" -PassThru
    }
    catch
    {
        switch ($_.Exception.Response.StatusCode.Value__)
        {
            304 {
                LogWrite "No new template file was found. Exiting until next schedule" | Out-Null
                return $false
            }
            default {
                LogWrite "[$_.Exception.Response.StatusCode.Value__] response for $templateResource with etag=$etag" | Out-Null
                return $false
            }
        }
    }

    LogWrite "Replacing old template file with new file" | Out-Null
    Remove-Item $templatePath
    Rename-Item $newTemplatePath $templatePath

    # Write newest ETag to version file
    $newEtag = $response.Headers["ETag"]
    LogWrite "Save new ETag '$newEtag' to $templateVersionFile" | Out-Null
    $newEtag | Out-File -FilePath "$templateVersionFile"

    return $true
}

Export-ModuleMember -Function FetchTemplate
