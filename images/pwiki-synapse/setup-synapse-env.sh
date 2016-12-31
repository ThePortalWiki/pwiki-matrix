#!/usr/bin/env bash

set -e
set -x

# General variables.
SYNAPSE_USER=synapse
SYNAPSE_GROUP=synapse
SYNAPSE_SECRET_GROUP=synapse-secret

# Variables from build arguments.
if [ -z "$SYNAPSE_UID" ]; then
	echo 'SYNAPSE_UID build argument not specified.' >&2
	exit 1
fi
if [ -z "$SYNAPSE_GID" ]; then
	echo 'SYNAPSE_GID build argument not specified.' >&2
	exit 1
fi
if [ -z "$TLS_GID" ]; then
	echo 'TLS_GID build argument not specified.' >&2
	exit 1
fi
if [ -z "$SYNAPSE_DOMAIN" ]; then
	echo 'SYNAPSE_DOMAIN build argument not specified.' >&2
	exit 1
fi
if [ -z "$SYNAPSE_PORT" ]; then
	echo 'SYNAPSE_PORT build argument not specified.' >&2
	exit 1
fi

# Set up user and groups.
groupadd --gid="$SYNAPSE_GID" "$SYNAPSE_GROUP"
groupadd --gid="$TLS_GID" "$SYNAPSE_SECRET_GROUP"
useradd --uid="$SYNAPSE_UID" --gid="$SYNAPSE_GROUP" --groups="$SYNAPSE_SECRET_GROUP" -s /bin/false -d / -M "$SYNAPSE_USER"

# Write out this data to the image.
cat << EOF > /synapse.env
export SYNAPSE_UID=$SYNAPSE_UID
export SYNAPSE_GID=$SYNAPSE_GID
export TLS_GID=$TLS_GID
export SYNAPSE_DOMAIN=$SYNAPSE_DOMAIN
export SYNAPSE_PORT=$SYNAPSE_PORT
EOF
chmod 444 /synapse.env
