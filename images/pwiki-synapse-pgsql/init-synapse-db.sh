#!/usr/bin/env bash

set -e
set -x

SECRETS_DIR=/secrets
SYNAPSE_POSTGRESQL_USER=synapse
SYNAPSE_POSTGRESQL_PASSWORD_FILE="$SECRETS_DIR/postgresql_synapse.password"
SYNAPSE_POSTGRESQL_DATABASE=synapse

if [ -e "$SECRETS_DIR/no-volume" ]; then
	echo "Secrets volume '$SECRETS_DIR' not mounted." >&2
	exit 1
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER $SYNAPSE_POSTGRESQL_USER
           PASSWORD '$(cat "$SYNAPSE_POSTGRESQL_PASSWORD_FILE")';
    CREATE DATABASE $SYNAPSE_POSTGRESQL_DATABASE
           ENCODING 'UTF8'
           LC_COLLATE='C'
           LC_CTYPE='C'
           template=template0
           OWNER $SYNAPSE_POSTGRESQL_USER;
EOSQL
