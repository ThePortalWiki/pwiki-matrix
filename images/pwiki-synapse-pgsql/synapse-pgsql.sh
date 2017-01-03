#!/bin/bash

set -e
set -x

SECRETS_DIR=/secrets
POSTGRESQL_SUPERUSER_PASSWORD_FILE="$SECRETS_DIR/postgresql_superuser.password"

if [ -e "$SECRETS_DIR/no-volume" ]; then
	echo "Secrets volume '$SECRETS_DIR' not mounted." >&2
	exit 1
fi

export POSTGRES_PASSWORD="$(cat "$POSTGRESQL_SUPERUSER_PASSWORD_FILE")"
exec "$POSTGRESQL_ENTRYPOINT" "$@"
