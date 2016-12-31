#!/usr/bin/env bash

set -e
set -x

# General variables.
CONFIG_DIR=/synapse
CONFIG_FILE="$CONFIG_DIR/synapse.yaml"
CONFIG_FILE_LOGGING="$CONFIG_DIR/logging.yaml"
SQLITE_PATH="$CONFIG_DIR/db.sqlite"
SIGNING_KEY_FILE="$CONFIG_DIR/signing.key"
PEPPER_FILE="$CONFIG_DIR/pepper"
DH_PARAMS_FILE="$CONFIG_DIR/tls.dh"
TLS_DIR=/tls
MEDIA_DIR=/synapse-media
TLS_CERTIFICATE_FILE="$TLS_DIR/tls.crt"
TLS_PRIVATE_KEY_FILE="$TLS_DIR/tls.key"

source /synapse.env

# Set up configuration.

mkdir -p "$CONFIG_DIR"
python -m synapse.app.homeserver \
    --config-path="$CONFIG_FILE" \
    --generate-config            \
    --report-stats=yes           \
    --server-name="$SYNAPSE_DOMAIN"

rm "$CONFIG_DIR"/*.tls.{key,crt,dh}
rm "$CONFIG_DIR"/*.log.config

openssl dhparam -out "$DH_PARAMS_FILE" 4096

# Usage: get_config <variable_name>
# String values will be surrounded by quotes.
get_config() {
	local line
	line="$(grep -P "^( *$1):[^\\n]+$" "$CONFIG_FILE")"
	if [ "$?" -ne 0 ]; then
		echo "Cannot find config entry for '$1'." >&2
		exit 1
	fi
	echo "$line" | cut -d: -f2- | sed -r 's/^ +| +$//g'
}

# Usage: get_config_string <variable_name>
get_config_string() {
	get_config "$1" | sed -r 's/^"|"$//g'
}

# Usage: set_config <variable_name> <value>
# Value must be quoted if it's a string.
set_config() {
	if ! grep -qP "^( *(# *)?$1):[^\\n]+$" "$CONFIG_FILE"; then
		echo "Cannot find config entry for '$1'." >&2
		exit 1
	fi
	sed -ri "s~^( *)(# *)?$1:[^\\n]+$~\\1$1: $2~g" "$CONFIG_FILE"
}

# Usage: set_config <variable_name> <value>
# Value is expected to be a string.
set_config_string() {
	set_config "$1" "\"$2\""
}

set_config_string pid_file /tmp/synapse.pid

set_config_string media_store_path "$MEDIA_DIR/media"
set_config_string uploads_path "$MEDIA_DIR/uploads"
set_config_string tls_certificate_path "$TLS_CERTIFICATE_FILE"
set_config_string tls_private_key_path "$TLS_PRIVATE_KEY_FILE"
set_config_string tls_dh_params_path "$DH_PARAMS_FILE"
set_config_string server_name "$SYNAPSE_DOMAIN"
set_config_string public_baseurl "https://$SYNAPSE_DOMAIN:$SYNAPSE_PORT/"
set_config enable_metrics True
set_config web_client False
set_config_string database "$SQLITE_PATH"

mv "$(get_config_string signing_key_path)" "$SIGNING_KEY_FILE"
set_config_string signing_key_path "$SIGNING_KEY_FILE"

PEPPER="$(openssl rand -base64 32)"
echo "$PEPPER" > "$PEPPER_FILE"
set_config_string pepper "$PEPPER"

cat << EOF > "$CONFIG_FILE_LOGGING"
version: 1
formatters:
  precise:
   format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s\
- %(message)s'
filters:
  context:
    (): synapse.util.logcontext.LoggingContextFilter
    request: ""
handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
    filters: [context]
loggers:
    synapse:
        level: INFO
    synapse.storage.SQL:
        level: INFO
root:
    level: INFO
    handlers: [console]
EOF
set_config_string log_config "$CONFIG_FILE_LOGGING"

# Lock down file permissions.
chown -R "$SYNAPSE_UID:$SYNAPSE_GID" "$CONFIG_DIR"
chmod -R g-w,o-rwx "$CONFIG_DIR"
