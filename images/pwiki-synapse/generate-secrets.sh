#!/usr/bin/env bash

set -e
set -x

SECRETS_DIR="/secrets"
if [ -e "$SECRETS_DIR/no-volume" ]; then
	echo "Secrets volume '$SECRETS_DIR' not mounted." >&2
	exit 1
fi

chmod 700 "$SECRETS_DIR"

DH_PARAMS_FILE="$SECRETS_DIR/tls.dh"
if [ ! -f "$DH_PARAMS_FILE" ]; then
	echo "Generating 4096-bit Diffie-Hellman parameters '$DH_PARAMS'... This might take hours." >&2
	openssl dhparam -out "$DH_PARAMS_FILE" 4096
else
	echo "Diffie-Hellman parameters file exists: '$DH_PARAMS'" >&2
fi

SIGNING_KEY_ID_FILE="$SECRETS_DIR/signing_key_id.pub"
if [ ! -f "$SIGNING_KEY_ID_FILE" ]; then
	echo "Generating ed25519 signing key ID file '$SIGNING_KEY_ID_FILE'..." >&2
	openssl rand -base64 4 | tr -d '\n' > "$SIGNING_KEY_ID_FILE"
else
	echo "ed25519 signing key ID file exists: '$SIGNING_KEY_ID_FILE'" >&2
fi

SIGNING_KEY_FILE="$SECRETS_DIR/signing.key"
if [ ! -f "$SIGNING_KEY_FILE" ]; then
	echo "Generating ed25519 signing key file '$SIGNING_KEY_FILE'..." >&2
	python -c 'import sys, signedjson.key as sj; sj.write_signing_keys(sys.stdout, [sj.generate_signing_key("a_" + sys.stdin.read().strip())])' < "$SIGNING_KEY_ID_FILE" > "$SIGNING_KEY_FILE"
else
	echo "ed25519 signing key file exists: '$SIGNING_KEY_FILE'" >&2
fi

PEPPER_FILE="$SECRETS_DIR/pepper.key"
if [ ! -f "$PEPPER_FILE" ]; then
	echo "Generating pepper file '$PEPPER_FILE'..." >&2
	openssl rand -base64 50 | tr -d '\n' > "$PEPPER_FILE"
else
	echo "Pepper file exists: '$PEPPER_FILE'" >&2
fi

MACAROON_SECRET_KEY_FILE="$SECRETS_DIR/macaroon.key"
if [ ! -f "$MACAROON_SECRET_KEY_FILE" ]; then
	echo "Generating macaroon secret key file '$MACAROON_SECRET_KEY_FILE'..." >&2
	openssl rand -base64 50 | tr -d '\n' > "$MACAROON_SECRET_KEY_FILE"
else
	echo "Macaroon secret key file exists: '$MACAROON_SECRET_KEY_FILE'" >&2
fi

REGISTRATION_SECRET_KEY_FILE="$SECRETS_DIR/registration.key"
if [ ! -f "$REGISTRATION_SECRET_KEY_FILE" ]; then
	echo "Generating registration secret key file '$REGISTRATION_SECRET_KEY_FILE'..." >&2
	openssl rand -base64 50 | tr -d '\n' > "$REGISTRATION_SECRET_KEY_FILE"
else
	echo "Registration secret key file exists: '$REGISTRATION_SECRET_KEY_FILE'" >&2
fi

chmod -R g-rwx,o-rwx "$SECRETS_DIR"
chown -R root:root "$SECRETS_DIR"
