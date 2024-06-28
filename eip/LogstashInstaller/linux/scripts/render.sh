#!/bin/bash
set +x

echo "executing Cynet Logstash renderer script.."

render() {
    output_to_file=false
    if [[ -n "$1" ]]
    then
        output_to_file=true
    fi

    readonly install_path="/etc/cynet-logstash"
    readonly scripts_path="$install_path/scripts"

    config_json=$(< $install_path/config.json)
    jq_cmd="$scripts_path/jq"

    tkn=$(echo "${config_json}" | ${jq_cmd} -r '.tkn')
    group=$(echo "${config_json}" | ${jq_cmd} -r -j '.group')
    if [[ $group == null ]]; then group=""; fi
    if [ ! -z "$group" ]
    then
        encoded_group=$(echo "$group" | ${jq_cmd} -sRr @uri)
        tkn="$tkn?CynetGroup=$encoded_group"
    fi
    url=$(echo "${config_json}" | ${jq_cmd} -r '.url')

    cp $scripts_path/logstash_template.conf $install_path/logstash.conf


    # render ports
    echo "rendering ports.."
    formatted=$(echo "${config_json}" | ${jq_cmd} '.providers | to_entries[] | [.key, .value] | join("=")')
    while IFS= read -r line
    do
        cleaned=$(echo $line | sed 's/\"//g')
        IFS=\= read -r provider port <<< $cleaned
        provider=$(echo $provider | sed "s/\-/\_/g")
        echo "$provider -> $port"
        sed -i "s/"${provider^^}"/${port}/g" $install_path/logstash.conf
    done < <(printf '%s\n' "$formatted")


    # render output block url and tkn
    echo "rendering output url: $url"
    sed -i "s,INGRESS_URL,${url},g" $install_path/logstash.conf
    echo "rendering tkn: ***"
    sed -i "s/TKN_ID/${tkn}/g" $install_path/logstash.conf


    # render samplers
    samplers=""
    formatted_samplers=$(echo "${config_json}" | ${jq_cmd} '.samplers | to_entries[] | [.key, .value] | join("=")')
    samplerContents="`cat "$scripts_path/sampler_template.conf"`"

    echo "checking for samplers.."
    if [ ! -z "$formatted_samplers" ]
    then
        echo "rendering samplers.."
        while IFS= read -r line
        do
            cleaned=$(echo $line | sed 's/\"//g')
            IFS=\= read -r name port <<< $cleaned
            name=$(echo $name | sed "s/\-/\_/g")

            echo "$name -> $port"
            sampler_copy="$samplerContents"
            rendered=$(sed -e "s/"SAMPLER_PORT"/$port/g" -e "s/"SAMPLER_NAME"/$name/g" <<< "$sampler_copy")
            samplers+="$rendered

        "
        done < <(printf '%s\n' "$formatted_samplers")

        awk -i inplace -v srch="#SAMPLERS" -v repl="$samplers" '{ sub(srch,repl,$0); print $0 }' $install_path/logstash.conf
    else
        echo "no samplers found to render"
    fi


    # render headers
    echo "rendering headers.."
    logstash_version=$(< "$scripts_path/LOGSTASH_VERSION")
    installer_version=$(< "$scripts_path/VERSION")
    template_version=$(< "$scripts_path/templateVersion")
    config_version=$(< "$scripts_path/configVersion")
    os_version=$(awk -F= '$1=="PRETTY_NAME" { print $2 ;}' /etc/os-release | tr -d '"')
    headers_contents="`cat "$scripts_path/headers_template.conf"`"
    rendered_headers=$(sed \
    -e "s/LOGSTASH_VERSION/$logstash_version/g"\
    -e "s/"INSTALLER_VERSION"/$installer_version/g"\
    -e "s/"LOGSTASH_TEMPLATE_VERSION"/\"$template_version\"/g"\
    -e "s/"CONFIG_VERSION"/\"$config_version\"/g"\
    -e "s/"PLATFORM_VERSION"/$os_version/g"\ <<< "$headers_contents")

    awk -i inplace -v srch="#HEADERS" -v repl="$rendered_headers" '{ sub(srch,repl,$0); print $0 }' $install_path/logstash.conf


    if [ "$output_to_file" = true ]
    then
        # replace output block with file output
        sed -i '/output {/,$d' "$install_path/logstash.conf"
        cat >> "$install_path/logstash.conf" <<- EOM

output {
    file {
        path => "$install_path/output.log"
        codec => "rubydebug"
    }
}
EOM
    fi

    echo "rendering of $install_path/logstash.conf completed"
}

