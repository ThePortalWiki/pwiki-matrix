#!/usr/bin/env bash

set -e
set -x

SECRETS_DIR=/secrets
SIGNING_KEY_FILE="$SECRETS_DIR/signing.key"
DH_PARAMS_FILE="$SECRETS_DIR/tls.dh"
PEPPER_FILE="$SECRETS_DIR/pepper.key"
MACAROON_SECRET_KEY_FILE="$SECRETS_DIR/macaroon.key"
REGISTRATION_SECRET_KEY_FILE="$SECRETS_DIR/registration.key"

TLS_DIR=/tls
TLS_CERTIFICATE_FILE="$TLS_DIR/tls.crt"
TLS_PRIVATE_KEY_FILE="$TLS_DIR/tls.key"

MEDIA_DIR=/synapse-media

CONFIG_DIR=/synapse-config
CONFIG_FILE="$CONFIG_DIR/synapse.yaml"
CONFIG_FILE_LOGGING="$CONFIG_DIR/logging.yaml"
SQLITE_PATH="$CONFIG_DIR/db.sqlite"

if [ -e "$SECRETS_DIR/no-volume" ]; then
	echo "Secrets volume '$SECRETS_DIR' not mounted." >&2
	exit 1
fi

if [ -e "$TLS_DIR/no-volume" ]; then
	echo "TLS volume '$TLS_DIR' not mounted." >&2
	exit 1
fi

if [ -e "$MEDIA_DIR/no-volume" ]; then
	echo "Media volume '$MEDIA_DIR' not mounted." >&2
	exit 1
fi

source /synapse.env

# Set up new configuration.
if [ -d "$CONFIG_DIR" ]; then
	echo 'Script invoked while not starting from scratch. Something is wrong.' >&2
	exit 1
fi
mkdir -p "$CONFIG_DIR"
chown "$SYNAPSE_UID:$SYNAPSE_GID" "$CONFIG_DIR"
sudo -u synapse python -m synapse.app.homeserver \
    --config-path="$CONFIG_FILE"                 \
    --generate-config                            \
    --report-stats=yes                           \
    --server-name="$SYNAPSE_DOMAIN"

rm "$CONFIG_DIR"/*.tls.{key,crt,dh}
rm "$CONFIG_DIR"/*.log.config

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
set_config_string server_name "$SYNAPSE_DOMAIN"
set_config_string public_baseurl "https://$SYNAPSE_DOMAIN:$SYNAPSE_PORT/"
set_config enable_metrics True
set_config web_client False
set_config_string database "$SQLITE_PATH"

# The Diffie-Hellman parameters file needs to be copied rather than read directly, because it
# is in the /secrets volume which is expected to be solely root-readable.
# Same deal with signing.key.
cp "$DH_PARAMS_FILE" "$SIGNING_KEY_FILE" "$CONFIG_DIR/"
set_config_string tls_dh_params_path "$CONFIG_DIR/$(basename "$DH_PARAMS_FILE")"
set_config_string signing_key_path "$CONFIG_DIR/$(basename "$SIGNING_KEY_FILE")"

# Secret keys are stored directly in the config file rather than read from disk. Boo.
set_config_string pepper "$(cat "$PEPPER_FILE")"
set_config_string registration_shared_secret "$(cat "$REGISTRATION_SECRET_KEY_FILE")"
set_config_string macaroon_secret_key "$(cat "$MACAROON_SECRET_KEY_FILE")"

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
chown -R "$SYNAPSE_UID:$SYNAPSE_GID" "$CONFIG_DIR"
chmod -R g-w,o-rwx "$CONFIG_DIR"

echo 'Configuration generated; starting server.' >&2
exec sudo -u synapse python -m synapse.app.homeserver --config-path "$CONFIG_FILE"
