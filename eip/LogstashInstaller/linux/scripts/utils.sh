#!/bin/bash

readonly config_template_name="config.json"
readonly logstash_template_name="logstash_template.conf"

install_path="/etc/cynet-logstash"
scripts_path="$install_path/scripts"
jq_cmd="$scripts_path/jq"
config_path="$install_path/config.json"


get_config_url() {
    existing_json=$(< $config_path)
    bucket_url=$(echo "${existing_json}" | ${jq_cmd} -r '.url')
    echo "$bucket_url/logstash_installer"
}

get_etag () {
    if [[ -z "$1" ]]
    then
        echo "'tkn' argument is empty or missing"
        exit 1
    fi

    if [[ -z "$2" ]]
    then
        echo "'file' argument is empty or missing"
        exit 1
    fi

    if [ ! "$2" == "$config_template_name" ] && [ ! "$2" == "$logstash_template_name" ]
    then
        echo "[$2] file argument does not equal [$config_template_name] or [$logstash_template_name]"
        exit 1
    fi

    base_url=$(get_config_url)
    url="${base_url}/${1}/${2}"
    headers=$(wget --method=HEAD -q -O - "$url" --server-response 2>&1)

    status_code=$(echo "$headers" | awk '/HTTP/' | awk '{print $2}')
    if [[ ! "$status_code" == "200" ]]
    then
        echo "got invalid $status_code response for $url"
        exit 1
    fi

    etag=$(echo "$headers" | awk '/ETag:/' | awk -F'"' '{print $2}')
    if [[ -z "$etag" ]]
    then
        echo "etag header is empty for $url"
        exit 1
    fi

    echo "$etag"
}

fetch_logstash_template() {
    if [[ -z "$1" ]]
    then
        echo "'tkn' argument is empty or missing"
        exit 1
    fi

    existing_etag=$(< $scripts_path/templateVersion)
    base_url=$(get_config_url)
    url="${base_url}/${1}/${logstash_template_name}"
    headers=$(wget -q -O "$scripts_path/new_logstash_template.conf" --header "If-None-Match: $existing_etag" "$url" --server-response 2>&1)
    status_code=$(echo "$headers" | awk '/HTTP/' | awk '{print $2}')
    if [[ "$status_code" == "304" ]]
    then
        echo "unchanged"
    elif [[ "$status_code" == "200" ]]
    then
        rm "$scripts_path/$logstash_template_name"
        mv "$scripts_path/new_logstash_template.conf" "$scripts_path/$logstash_template_name"
        new_etag=$(echo "$headers" | awk '/ETag:/' | awk -F'"' '{print $2}')
        echo "$new_etag" > "$scripts_path/templateVersion"
        echo "changed"
    else
        echo "got invalid $status_code response for $url"
        echo "unchanged"
    fi
}

fetch_config_template() {
    if [[ -z "$1" ]]
    then
        echo "'tkn' argument is empty or missing"
        exit 1
    fi

    base_url=$(get_config_url)
    url="${base_url}/${1}/${config_template_name}"
    config_template_path="$scripts_path/new_config_template.json"
    existing_etag=$(< "$scripts_path/configVersion")
    headers=$(wget -q -O "${config_template_path}" --header "If-None-Match: $existing_etag" "$url" --server-response 2>&1)

    status_code=$(echo "$headers" | awk '/HTTP/' | awk '{print $2}')
    if [[ "$status_code" == "304" ]]
    then
        echo "unchanged"
    elif [[ "$status_code" == "200" ]]
    then
        changes=$(merge_configs "$config_path" "$config_template_path")
        # replace etag
        new_etag=$(echo "$headers" | awk '/ETag:/' | awk -F'"' '{print $2}')
        echo "$new_etag" > "$scripts_path/configVersion"
        # return value of merge_configs function
        echo "$changes"
    else
        echo "got invalid $status_code response for $url"
        echo "unchanged"
    fi
}

merge_configs() {
    if [[ -z "$1" ]]
    then
        echo "'existing config path' argument is empty or missing"
        exit 1
    fi

    if [[ -z "$2" ]]
    then
        echo "'new config path' argument is empty or missing"
        exit 1
    fi

    existing_config_path="$1"
    existing_json=$(< $existing_config_path)

    new_config_path="$2"
    new_json=$(< $new_config_path)

    declare -A providers_map
    existing_providers=$(echo "${existing_json}" | ${jq_cmd} -r '.providers | to_entries[] | .key')
    while IFS= read -r line
    do
        providers_map[$line]="foo"
    done < <(printf '%s\n' "$existing_providers")

    new_providers=$(echo "${new_json}" | ${jq_cmd} -r '.providers | to_entries[] | [.key, .value] | join("=")')
    found_new_provider=false
    while IFS= read -r line
    do
        IFS=\= read -r provider port <<< $line
        if [ ! ${providers_map["$provider"]+_} ]
        then
            # add new provider to config.json
            echo "adding missing provider -- $provider -> $port"
            $jq_cmd --argjson newval "$( jo $provider=$port )" '.providers += $newval' <<<"$existing_json" > "$config_path"
            # refresh json in case we have more providers that need to be added
            existing_json=$(< $existing_config_path)
            found_new_provider=true
        fi
    done < <(printf '%s\n' "$new_providers")

    if [ "$found_new_provider" = true ]
    then
        echo "changed"
    else
        echo "unchanged"
    fi
}