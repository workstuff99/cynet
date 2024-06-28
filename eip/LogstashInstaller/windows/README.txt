# Install or upgrade
- Download the latest installer from the Cynet UI
- Open a powershell in admin mode and navigate to your extraction folder
- Run: Set-ExecutionPolicy -ExecutionPolicy Bypass
- Select A
- Run: powershell.exe .\install.ps1


# Uninstalling
To uninstall, do the following:
- Open a powershell in admin mode and navigate to your extraction folder
- Run: Set-ExecutionPolicy -ExecutionPolicy Bypass
- Select A
- Run: powershell.exe .\uninstall.ps1


# Verify the install or upgrade is successful
- Ensure there is a Windows service called cynet_logstash
- The installation folder is c:\cynet-logstash



# Change ports numbers (only if you have to -- not recommended)
In your installation folder, open the config.json and change the ports to your preferred mapping under the 'providers' key.
Now you can restart your service using the Windows Services tool.



# Add samplers (only if you are in an active certification process with Cynet for a new data source)
In order to add a sampler, add a key value pair under the 'samplers' key.
e.g.
    "samplers": {
        "new-sampler-firewall_1": 5999,
        "new-sampler-firewall_2": 6000,
    }

# Add group for MSSP customer

Add 'group' to the root level of the config.json to include your MSSP group.
{
    "group": "My Group"
}


# Note
If you make changes to your config.json, make sure that the json is always valid.
Do not touch logstash.conf directly.