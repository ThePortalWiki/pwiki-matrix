#!/usr/bin/env bash

set -e
set -x

SECRETS_DIR=/secrets
DH_PARAMS_FILE="$SECRETS_DIR/tls.dh"
TURN_SHARED_SECRET_FILE="$SECRETS_DIR/turn_shared_secret.key"

TLS_DIR=/tls
TLS_CERTIFICATE_FILE="$TLS_DIR/tls.crt"
TLS_PRIVATE_KEY_FILE="$TLS_DIR/tls.key"

CONFIG_DIR=/coturn-config
CONFIG_FILE="$CONFIG_DIR/coturn.conf"

if [ -e "$SECRETS_DIR/no-volume" ]; then
	echo "Secrets volume '$SECRETS_DIR' not mounted." >&2
	exit 1
fi

if [ -e "$TLS_DIR/no-volume" ]; then
	echo "TLS volume '$TLS_DIR' not mounted." >&2
	exit 1
fi

source /coturn.env

# Set up new configuration.
if [ -d "$CONFIG_DIR" ]; then
	echo 'Script invoked while not starting from scratch. Something is wrong.' >&2
	exit 1
fi
mkdir -p "$CONFIG_DIR"
chown "$COTURN_UID:$COTURN_GID" "$CONFIG_DIR/"

cp -v "$DH_PARAMS_FILE" "$CONFIG_DIR"
cat << EOF > "$CONFIG_FILE"
# General server settings.
realm=$COTURN_DOMAIN
server-name=$COTURN_DOMAIN
log-file=stdout

# TLS 1.2 only.
cert=$TLS_CERTIFICATE_FILE
pkey=$TLS_PRIVATE_KEY_FILE
dh-file=$CONFIG_DIR/$(basename "$DH_PARAMS_FILE")
tls-listening-port=$COTURN_PORT
no-tlsv1
no-tlsv1_1
# These disable non-TLS UDP and TCP connections.
no-udp
no-tcp

# Use credentials from API using shared secret.
lt-cred-mech
use-auth-secret
static-auth-secret=$(cat "$TURN_SHARED_SECRET_FILE")

# Disable unneeded features.
no-cli
no-stun
EOF

chown -R "$COTURN_UID:$COTURN_GID" "$CONFIG_DIR"
chmod -R g-w,o-rwx "$CONFIG_DIR"

echo 'Configuration generated; starting server.' >&2
exec sudo -u coturn turnserver -c "$CONFIG_FILE"
