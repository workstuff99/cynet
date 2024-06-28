#!/bin/bash
set -euo pipefail

# Ensure that the uninstaller is running as root in order to make changes
if [ "$EUID" -ne 0 ]
then
    echo "please run this script as root"
    exit 1
fi

while true; do
    read -p "Do you wish to uninstall Cynet Logstash?" yn
    case $yn in
        [Yy]* ) echo "Uninstalling.."; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

# stopping service
SERVICE_NAME="cynet_logstash.service"
services=$(systemctl list-unit-files | { grep $SERVICE_NAME || true; } )
if [ ! -z "$services" ]
then
    echo "stopping $SERVICE_NAME"
    systemctl stop $SERVICE_NAME
else
    echo "could not locate existing $SERVICE_NAME"
fi

install_path="/etc/cynet-logstash"
if [ -d "$install_path" ]
then
    echo "removing $install_path.."
    rm -f /etc/systemd/system/cynet_logstash.service
    rm -rf "$install_path"
    rm -rf /etc/cron.d/cynet_logstash_update
fi
