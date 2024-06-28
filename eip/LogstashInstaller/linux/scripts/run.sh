#!/bin/bash

echo "executing Cynet Logstash run script.."


output_to_file=false
while getopts ":f" option; do
   case $option in
      f)
         output_to_file=true;;
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done


readonly install_path="/etc/cynet-logstash"
readonly scripts_path="$install_path/scripts"

source "$scripts_path/render.sh"
if [ "$output_to_file" = true ]
then
    render "outputtofile"
else
    render
fi
$install_path/logstash/bin/logstash -f $install_path/logstash.conf -l $install_path/logs