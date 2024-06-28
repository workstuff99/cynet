#!/bin/bash
set -x
set -euo pipefail


# Ensure that the installer is running as root in order to make changes
if [ "$EUID" -ne 0 ]
then
    echo "please run this script as root"
    exit 1
fi

# process options
output_to_file=false
fetch_etags=true
while getopts ":fd" option; do
   case $option in
      f)
         output_to_file=true;;
      d)
         fetch_etags=false;;
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done
echo "options:"
echo "output_to_file=$output_to_file"
echo "fetch_etags=$fetch_etags"

install_path="/etc/cynet-logstash"
scripts_path="$install_path/scripts"

version=$(< ./scripts/VERSION)
echo "installing Cynet Logstash $version to $install_path"

# backup existing config.json
config_backup_path="/tmp/cynet_config_backup.json"
config_path="$install_path/config.json"
has_config_backup=false
if [ -f "$config_path" ]
then
    echo "copying existing config.json to '$config_backup_path'"
    cp "$config_path" "$config_backup_path"
    has_config_backup=true
fi

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

# cleanup existing installation
if [ -d "$install_path" ]
then
    echo "cleaning existing $install_path"
    rm -f /etc/systemd/system/cynet_logstash.service
    rm -rf "$install_path"
    rm -rf /etc/cron.d/cynet_logstash_update
fi
echo "creating new $install_path directory"
mkdir $install_path
mkdir $scripts_path

# Install base requirements
echo "installing base requirements using apt-get"
apt-get --yes update
apt-get --yes install wget cron jo gawk

# logstash path variables
logstash_version=`cat ./scripts/LOGSTASH_VERSION`
logstash_archive="logstash-$logstash_version-linux-x86_64.tar.gz"
logstash_temp_archive="/tmp/$logstash_archive"
logstash_url="https://artifacts.elastic.co/downloads/logstash/$logstash_archive"


# download and unzip logstash
if [ -f "$logstash_temp_archive" ]
then
    echo "using existing $logstash_temp_archive"
else
    echo "downloading $logstash_url"
    wget -v -O $logstash_temp_archive $logstash_url
fi
echo "extracting $logstash_temp_archive to $install_path"
tar -zxf $logstash_temp_archive -C $install_path
mv "$install_path/logstash-$logstash_version" "$install_path/logstash"


# moving needed files to install and scripts folder
cp ./scripts/cynet_logstash.service /etc/systemd/system/cynet_logstash.service
cp ./scripts/jq $scripts_path/jq
cp ./scripts/logstash_template.conf $scripts_path/logstash_template.conf
cp ./scripts/sampler_template.conf $scripts_path/sampler_template.conf
cp ./scripts/headers_template.conf $scripts_path/headers_template.conf
cp ./scripts/LOGSTASH_VERSION $scripts_path/LOGSTASH_VERSION
cp ./scripts/render.sh $scripts_path/render.sh
cp ./scripts/run.sh $scripts_path/run.sh
cp ./scripts/utils.sh $scripts_path/utils.sh
cp ./scripts/VERSION $scripts_path/VERSION

# use backup as config.json if available
source ./scripts/utils.sh
if [ "$has_config_backup" = true ]
then
    echo "copying $config_backup_path backup config to $install_path/config.json"
    cp "$config_backup_path" "$install_path/config.json"
    cp ./scripts/config.json "/tmp/new_config.json"
    merge_configs "$install_path/config.json" "/tmp/new_config.json"
else
    echo "copying new config.json"
    cp ./scripts/config.json $install_path/config.json
fi


# fetch config and logstash template etags if enabled
if [ "$fetch_etags" = true ]
then
    # copy cron job
    cp ./scripts/updater.sh $scripts_path/updater.sh
    cp ./scripts/cynet_logstash_update /etc/cron.d/cynet_logstash_update
    chmod u+x /etc/cron.d/cynet_logstash_update

    # fetch etags for templates
    echo "fetching initial etags for template files.."
    tkn=`$(echo ./scripts/jq -r '.tkn' ./scripts/config.json)`
    echo "found tkn: $tkn"
    echo "fetching config.json etag.."
    config_template_etag=$(get_etag "$tkn" "config.json")
    echo "fetching logstash_template.conf etag.."
    logstash_template_etag=$(get_etag "$tkn" "logstash_template.conf")
    echo "$config_template_etag" > "$scripts_path/configVersion"
    echo "$logstash_template_etag" > "$scripts_path//templateVersion"
else
    echo "ignore fetching etags and cron job"
    # set defaults when fetching etags is disabled
    echo "default" > "$scripts_path/configVersion"
    echo "default" > "$scripts_path//templateVersion"
fi

cmd="/bin/bash $install_path/scripts/run.sh"
service_path="/etc/systemd/system/cynet_logstash.service"
if [ "$output_to_file" = true ]
then
    echo "installing service with file output"
    # pass on output to file flag
    cmd="$cmd -f"
else
    echo "installing service with regular output"
fi
awk -i inplace -v srch="#CMD" -v repl="$cmd" '{ sub(srch,repl,$0); print $0 }' "$service_path"

echo "setting up systemd service.."
systemctl daemon-reload
systemctl enable cynet_logstash.service
systemctl start cynet_logstash.service