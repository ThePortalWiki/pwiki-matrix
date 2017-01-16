#!/usr/bin/env bash

set -e
set -x

# General variables.
COTURN_USER=coturn
COTURN_GROUP=coturn
COTURN_SECRET_GROUP=coturn-secret

# Variables from build arguments.
fail=0
[ -n "$COTURN_UID" ] || { echo 'COTURN_UID build argument not specified.' >&2; fail=1; }
[ -n "$COTURN_GID" ] || { echo 'COTURN_GID build argument not specified.' >&2; fail=1; }
[ -n "$TLS_GID" ] || { echo 'TLS_GID build argument not specified.' >&2; fail=1; }
[ -n "$COTURN_DOMAIN" ] || { echo 'COTURN_DOMAIN build argument not specified.' >&2; fail=1; }
[ -n "$COTURN_PORT" ] || { echo 'COTURN_PORT build argument not specified.' >&2; fail=1; }
if [ "$fail" -eq 1 ]; then
	exit 1
fi

# Set up user and groups.
groupadd --gid="$COTURN_GID" "$COTURN_GROUP"
groupadd --gid="$TLS_GID" "$COTURN_SECRET_GROUP"
useradd --uid="$COTURN_UID" --gid="$COTURN_GROUP" --groups="$COTURN_SECRET_GROUP" -s /bin/false -d / -M "$COTURN_USER"

# Write out this data to the image.
cat << EOF > /coturn.env
export COTURN_UID=$COTURN_UID
export COTURN_GID=$COTURN_GID
export TLS_GID=$TLS_GID
export COTURN_DOMAIN=$COTURN_DOMAIN
export COTURN_PORT=$COTURN_PORT
EOF
chmod 444 /coturn.env
