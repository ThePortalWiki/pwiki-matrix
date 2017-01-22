#!/usr/bin/env bash

set -e
set -x

SECRETS_DIR=/secrets
SIGNING_KEY_FILE="$SECRETS_DIR/signing.key"
DH_PARAMS_FILE="$SECRETS_DIR/tls.dh"
PEPPER_FILE="$SECRETS_DIR/pepper.key"
MACAROON_SECRET_KEY_FILE="$SECRETS_DIR/macaroon.key"
REGISTRATION_SECRET_KEY_FILE="$SECRETS_DIR/registration.key"
TURN_SHARED_SECRET_FILE="$SECRETS_DIR/turn_shared_secret.key"

TLS_DIR=/tls
TLS_CERTIFICATE_FILE="$TLS_DIR/fullchain.pem"
TLS_PRIVATE_KEY_FILE="$TLS_DIR/privkey.pem"

MEDIA_DIR=/synapse-media

CONFIG_DIR=/synapse-config
CONFIG_FILE="$CONFIG_DIR/synapse.yaml"
CONFIG_FILE_LOGGING="$CONFIG_DIR/logging.yaml"

SYNAPSE_POSTGRESQL_USER=synapse
SYNAPSE_POSTGRESQL_PASSWORD_FILE="$SECRETS_DIR/postgresql_synapse.password"
SYNAPSE_POSTGRESQL_DATABASE=synapse
SYNAPSE_POSTGRESQL_HOST=postgres

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
rm "$CONFIG_DIR"/*.signing.key

# Usage: config_operation <python line of code using `c` and `argv`> [argv...]
config_operation() {
	local code
	code="$(echo "$1" | sed -r 's/[\n\t]+/ /g')"
	shift
	python -c "if True:
	import yaml, sys
	argv = sys.argv[1:]
	c = yaml.load(open('$CONFIG_FILE', 'r'))
	$code
	yaml.dump(c, open('$CONFIG_FILE', 'w'))
	" "$@"
}

# Usage: config_edit <variable_name> <python expression using `argv`> [argv...]
config_edit() {
	local varname expr
	varname="$1"
	shift
	expr="$(echo "$1" | sed -r 's/[\n\t]+/ /g')"
	shift
	config_operation "varname = argv[0]; argv = argv[1:]; c[varname] = $expr" "$varname" "$@"
}

# Usage: unset_config <variable_name>
unset_config() {
	config_operation "del c[argv[0]]" "$1"
}

# Usage: set_config_bool <variable_name> <value>
set_config_bool() {
	config_edit "$1" 'argv[0].lower() == "true"' "$2"
}

# Usage: set_config_int <variable_name> <value>
set_config_int() {
	config_edit "$1" 'int(argv[0], 10)' "$2"
}

# Usage: set_config <variable_name> <value>
# Value is expected to be a string.
set_config_string() {
	config_edit "$1" 'argv[0]' "$2"
}

set_config_string pid_file /tmp/synapse.pid

set_config_string media_store_path "$MEDIA_DIR/media"
set_config_string uploads_path "$MEDIA_DIR/uploads"
set_config_string tls_certificate_path "$TLS_CERTIFICATE_FILE"
# Purposefully empty key; the server is reverse-proxied, so it does not need to use the TLS
# key by itself. It still needs the certificate however, because it uses it as part of the
# federation protocol.
set_config_string tls_private_key_path ''
set_config_bool   no_tls True
set_config_string server_name "$SYNAPSE_DOMAIN"
set_config_string public_baseurl "https://$SYNAPSE_DOMAIN:$SYNAPSE_PORT/"
set_config_bool   enable_metrics True

# Remove debug port.
# It's not exposed outside the container but there's no reason to have it anyway.
config_operation 'c["listeners"] = [l for l in c["listeners"] if l["port"] == 8448]'
# Make sure we only have one listener left.
config_operation 'assert len(c["listeners"]) == 1, "More than one listener left."'
# Remove deprecated web client from the one listener.
set_config_bool   web_client False
config_operation 'c["listeners"][0]["resources"] = [{
	"compress": True,
	"names": ["client", "federation"],
}]'
# Ensure TLS is disabled, since the port is reverse-proxied.
config_operation 'c["listeners"][0]["tls"] = False'

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

# TURN server configuration.
config_edit turn_uris '[
	"turn:%s:%d?transport=udp" % (argv[0], int(argv[1])),
	"turn:%s:%d?transport=tcp" % (argv[0], int(argv[1])),
]' "$COTURN_DOMAIN" "$COTURN_PORT"
set_config_string turn_shared_secret "$(cat "$TURN_SHARED_SECRET_FILE")"
set_config_int turn_user_lifetime "$((24 * 3600 * 1000))"  # 24h

# Database configuration.
config_edit database '{
	"name": "psycopg2",
	"args": {
		"user":     argv[0],
		"password": open(argv[1], "r").read(),
		"database": argv[2],
		"host":     argv[3],
		"cp_min":   5,
		"cp_max":   10,
	},
}' "$SYNAPSE_POSTGRESQL_USER" "$SYNAPSE_POSTGRESQL_PASSWORD_FILE" "$SYNAPSE_POSTGRESQL_DATABASE" "$SYNAPSE_POSTGRESQL_HOST"

# URL preview API configuration.
config_edit url_preview_ip_range_blacklist '[
	"127.0.0.0/8",
	"10.0.0.0/8",
	"172.16.0.0/12",
	"192.168.0.0/16",
	"100.64.0.0/10",
	"169.254.0.0/16",
	"::/128",
	"::1/128",
	"fc00::/7",
	"fe80::/10",
	"ff00::/8",
]'
config_edit url_preview_ip_range_whitelist '[]'
config_edit url_preview_url_blacklist '[
	{"username": "*"},
	{"netloc": "google.com"},
	{"netloc": "*.google.com"},
	{"schema": "http"},
]'
set_config_string max_spider_size 8M
set_config_bool url_preview_enabled True

# Logging configuration.
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
    synapse.handlers.typing:
        level: WARN
    synapse.handlers.presence:
        level: WARN
    synapse.storage.TIME:
        level: WARN
root:
    level: INFO
    handlers: [console]
EOF
set_config_string log_config "$CONFIG_FILE_LOGGING"
unset_config log_file

# Reset config directory permissions before launching Synapse.
chown -R "$SYNAPSE_UID:$SYNAPSE_GID" "$CONFIG_DIR"
chmod -R g-w,o-rwx "$CONFIG_DIR"

echo 'Configuration generated; starting server.' >&2
exec sudo -u synapse python -m synapse.app.homeserver --config-path "$CONFIG_FILE"
