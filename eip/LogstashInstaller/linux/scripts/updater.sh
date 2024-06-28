#!/bin/bash
set -x
set -euo pipefail

echo "executing updater.."

install_path="/etc/cynet-logstash"
scripts_path="$install_path/scripts"
source "$scripts_path/utils.sh"

tkn=$($scripts_path/jq -r '.tkn' $install_path/config.json)
changed=false

logstash_template_changed=$(fetch_logstash_template "$tkn")
if [ "$logstash_template_changed" == "changed" ]
then
    echo "logstash template was changed"
    changed=true
fi

config_template_changed=$(fetch_config_template "$tkn")
if [ "$config_template_changed" == "changed" ]
then
    echo "config template was changed"
    changed=true
fi

if [ "$changed" = true ]
then
    echo "restarting logstash service to apply the new changes.."
    systemctl restart cynet_logstash.service
else
    echo "no changes to template files was found.."
fi