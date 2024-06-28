$nssmExe = ".\scripts\nssm.exe"

# Stop service
Write-Output "Stopping existing service if it is running... ignore errors.."
&$nssmExe "stop" "cynet_logstash"
Start-Sleep -Seconds 10

# Remove service
&$nssmExe "remove" "cynet_logstash" "confirm"

# remove installation folder
$installPath = [Environment]::GetEnvironmentVariable('CYNET_LOGSTASH_ROOT', 'Machine')
Write-Output "Removing '$installPath' installation folder"
Remove-Item "$installPath" -Recurse -Force

# remove scheduled tasks

Get-ScheduledTask -TaskName CynetLogstashUpdater -ErrorAction SilentlyContinue -OutVariable existingTask
if ($existingTask) {
    Write-Output "Removing CynetLogstashUpdater task.."
    Unregister-ScheduledTask -TaskName CynetLogstashUpdater -Confirm:$false
}

# reset environment variables
Write-Output "Removing CYNET_LOGSTASH_ROOT machine variable.."
[Environment]::SetEnvironmentVariable("CYNET_LOGSTASH_ROOT", $null, "Machine")
Write-Output "Removing CYNET_LOGSTASH_SCRIPTS machine variable.."
[Environment]::SetEnvironmentVariable("CYNET_LOGSTASH_SCRIPTS", $null, "Machine")