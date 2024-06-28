param (
    [string]$installPath = "C:\cynet-logstash",
	[string]$outputToFile = "false",
    [string]$fetchEtag = "true"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($([System.Environment]::CurrentDirectory).Equals($installPath)) {
    Write-Output "Cannot run the installer from the installation target folder!"
    Exit
}

$scriptsPath = "$installPath\scripts"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()

$version = Get-Content -Path ".\scripts\VERSION" -Raw
$logstashVersion = Get-Content -Path ".\scripts\LOGSTASH_VERSION" -Raw
Write-Output "Installing Cynet Logstash collector $($version) with Logstash $($logstashVersion)"

# Backup original config file
$configFilePath = "$installPath\config.json"
$backupConfigPath = "$env:TEMP\config.json"
[bool] $configBackupExists = $false
if (Test-Path $configFilePath) {
    Write-Output "Found existing config file from existing installation. Backing up to '$backupConfigPath'"
    $backupContents = Get-Content -Path $configFilePath -Raw
    Write-Output $backupContents

    # Write backup to tmp folder
    New-Item $backupConfigPath -ItemType "file" -Value $backupContents -Force
    $configBackupExists = $true
} else {
    if (Test-Path $backupConfigPath) {
        Write-Output "Found existing config file in '$backupConfigPath'"
        $existingContents = Get-Content -Path $backupConfigPath -Raw
        Write-Output $existingContents
        $configBackupExists = $true
    }
}

# Cleanup service
$localNssmExe = ".\scripts\nssm.exe"
Write-Output "Stopping existing service if it is running.."
&$localNssmExe stop cynet_logstash
Start-Sleep -Seconds 10

Write-Output "Uninstalling windows service if installed.."
&$localNssmExe remove cynet_logstash confirm

# Cleaning existing scheduled tasks
Get-ScheduledTask -TaskName CynetLogstashUpdater -ErrorAction SilentlyContinue -OutVariable existingTask
if ($existingTask) {
    Write-Output "Removing existing CynetLogstashUpdater task.."
    Unregister-ScheduledTask -TaskName CynetLogstashUpdater -Confirm:$false
}

if (Test-Path $installPath) {
    # Cleaning up installation directory
    Remove-Item "$installPath" -Recurse -Force
    Write-Output "Cleaning up completed. Ignore errors if the service was not found.."
}

# Setup clean installation and scripts directory
New-Item $installPath -Type Directory | Out-Null
New-Item $scriptsPath -Type Directory | Out-Null

[Environment]::SetEnvironmentVariable("CYNET_LOGSTASH_ROOT", $installPath, "Machine")
[Environment]::SetEnvironmentVariable("CYNET_LOGSTASH_SCRIPTS", $scriptsPath, "Machine")

# Download and uncompress Logstash
$logstashArchive = "logstash-$logstashVersion-windows-x86_64.zip"
$logstashDownloadLocation = "$env:TEMP\$logstashArchive"
if (!(Test-Path "$logstashDownloadLocation")) {
    Write-Output "Downloading logstash $logstashVersion to $logstashDownloadLocation"
    Invoke-WebRequest -TimeoutSec 600 -Uri https://artifacts.elastic.co/downloads/logstash/$logstashArchive -OutFile $logstashDownloadLocation
} else {
    Write-Output "Extracting existing $logstashDownloadLocation to $installPath"
}

Add-Type -Assembly "System.IO.Compression.Filesystem"
[System.IO.Compression.ZipFile]::ExtractToDirectory("$logstashDownloadLocation", "$installPath")
Start-Sleep -Seconds 10
Rename-Item "$installPath\logstash-$logstashVersion" "logstash" -Force


# Copy files needed for rendering and updating config after installing
Write-Output "Copying files.."
Copy-Item ".\scripts\configFetcher.psm1" -Destination $scriptsPath
Copy-Item ".\scripts\firewall.ps1" -Destination $scriptsPath
Copy-Item ".\scripts\headers_template.conf" -Destination $scriptsPath
Copy-Item ".\scripts\logstash_template.conf" -Destination $scriptsPath
Copy-Item ".\scripts\LOGSTASH_VERSION" -Destination $scriptsPath
Copy-Item ".\scripts\nssm.exe" -Destination $scriptsPath
Copy-Item ".\scripts\render.ps1" -Destination $scriptsPath
Copy-Item ".\scripts\run.ps1" -Destination $scriptsPath
Copy-Item ".\scripts\sampler_template.conf" -Destination $scriptsPath
Copy-Item ".\scripts\templateFetcher.psm1" -Destination $scriptsPath
Copy-Item ".\scripts\updater.ps1" -Destination $scriptsPath
Copy-Item ".\scripts\utils.psm1" -Destination $scriptsPath
Copy-Item ".\scripts\VERSION" -Destination $scriptsPath
Copy-Item ".\README.txt" -Destination $installPath

# import utility functions
Import-Module ".\scripts\utils.psm1"

# use backup config if it existed
if ($configBackupExists)
{
    Write-Output "using existing config backup and merging with new.."
    MergeConfig $backupConfigPath ".\scripts\config.json" $True
    $backup = Get-Content -Path $backupConfigPath -Raw
    Set-Content -Path "$configFilePath" -Value $backup
} else {
    Write-Output "using new config"
    Copy-Item ".\scripts\config.json" -Destination $installPath
}

# Getting config and template ETags
if ($fetchEtag -eq "true")
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Output "Fetching initial etags.."
    $url = GetConfigUrl
    $tkn = GetConfigToken
    $configFileURL = "$url/logstash_installer/$tkn/config.json"
    Write-Output "Requesting $configFileURL"
    CheckEtagExists "$scriptsPath\configVersion" $configFileURL | Out-Null
    $templateFileURL = "$url/logstash_installer/$tkn/logstash_template.conf"
    Write-Output "Requesting $templateFileURL"
    CheckEtagExists "$scriptsPath\templateVersion" $templateFileURL | Out-Null
}

# Installing scheduled task
Write-Output "Installing CynetLogstashUpdater task.."
$action = (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Unrestricted -WindowStyle Hidden $scriptsPath\updater.ps1")
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 60) -RepetitionDuration (New-TimeSpan -Days (365 * 20))
$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal
Register-ScheduledTask CynetLogstashUpdater -InputObject $task

# NSSM Service install + start
Write-Output "Installing service.."
$targetNssmExe = "$scriptsPath\nssm.exe"
&$targetNssmExe install cynet_logstash powershell.exe "$scriptsPath\run.ps1" -installPath $installPath -outputToFile $outputToFile -fetchEtag $fetchEtag

Write-Output "Start service.."
&$targetNssmExe start cynet_logstash

Write-Output "Installation took $($stopwatch.Elapsed.TotalSeconds) seconds"