# Install or upgrade

The installer will install a systemd service, a cronjob and needed files in /etc/cynet-logstash

## Ubuntu

    - sudo apt install zip
    - cd to the directory where you downloaded the zip
    - unzip LogstashInstaller.zip
    - cd linux
    - chmod -R +x .
    - sudo ./install.sh

## Debian
    - su
    - apt-get install unzip
    - cd to the directory where you downloaded the zip
    - unzip LogstashInstaller.zip
    - cd linux
    - chmod -R +x .
    - sudo ./install.sh

# Uninstalling

To uninstall, do the following:
- cd to the location where you unarchived the installer after downloading
    - Ubuntu
        - sudo ./uninstall.sh
    - Debian
        - su
        - ./uninstall.sh


# Verify the installation or upgrade

    - systemctl -l  status cynet_logstash.service
    - tail -f /etc/cynet-logstash/logs/logstash-plain.log

# Change ports

In your installation folder, open the config.json and change the ports to your preferred mapping under the 'providers' key.

    - sudo vim /etc/cynet-logstash/config.json
    - sudo systemctl restart cynet_logstash.service

# Add samplers

In order to add a sampler, add a key value pair under the 'samplers' key.
e.g.
    "samplers": {
        "new-sampler-firewall_1": 5999,
        "new-sampler-firewall_2": 6000,
    }

    - sudo vim /etc/cynet-logstash/config.json
    - sudo systemctl restart cynet_logstash.service

# Add group for MSSP customer

Add 'group' to the root level of the config.json to include your MSSP group.
{
    "group": "My Group"
}

    - sudo vim /etc/cynet-logstash/config.json
    - sudo systemctl restart cynet_logstash.service

# Note
If you make changes to your config.json, make sure that the json is always valid.
Do not touch logstash.conf directly.