#!/usr/bin/env bash

set -e

SYNAPSE_DOMAIN=''
SYNAPSE_TLS_CERTIFICATE_FILE=''
SYNAPSE_TLS_KEY_FILE=''
DH_PARAMS_FILE=''
SYNAPSE_PORT=''
EXTRA_INCLUDE=''
for arg; do
	case "$arg" in
		--domain=*) SYNAPSE_DOMAIN="${arg#*=}";;
		--tls-key=*) SYNAPSE_TLS_KEY_FILE="${arg#*=}";;
		--tls-cert=*) SYNAPSE_TLS_CERTIFICATE_FILE="${arg#*=}";;
		--dh-params=*) DH_PARAMS_FILE="${arg#*=}";;
		--synapse-port=*) SYNAPSE_PORT="${arg#*=}";;
		--include=*) EXTRA_INCLUDE="${arg#*=}";;
		*)
			echo "Unknown argument: '$arg'." >&2
			echo '(Make sure to use --arg=val format.)' >&2
			exit 1
			;;
	esac
done
fail=0
[ -n "$SYNAPSE_DOMAIN" ] || { echo '--domain argument not specified.' >&2; fail=1; }
[ -n "$SYNAPSE_TLS_KEY_FILE" ] || { echo '--tls-key argument not specified.' >&2; fail=1; }
[ -n "$SYNAPSE_TLS_CERTIFICATE_FILE" ] || { echo '--tls-cert argument not specified.' >&2; fail=1; }
[ -n "$DH_PARAMS_FILE" ] || { echo '--dh-params argument not specified.' >&2; fail=1; }
[ -n "$SYNAPSE_PORT" ] || { echo '--synapse-port argument not specified.' >&2; fail=1; }
if [ "$fail" -eq 1 ]; then
	exit 1
fi

include=''
if [ -n "$EXTRA_INCLUDE" ]; then
	include="include \"$EXTRA_INCLUDE\";"
fi

cat <<EOF
server {
	server_name "$SYNAPSE_DOMAIN";
	listen 443 default_server ssl;
	listen [::]:443 default_server ssl;
	ssl_protocols TLSv1.2;
	ssl_certificate "$SYNAPSE_TLS_CERTIFICATE_FILE";
	ssl_certificate_key "$SYNAPSE_TLS_KEY_FILE";
	ssl_dhparam "$DH_PARAMS_FILE";
	$include
	location /_matrix {
		proxy_pass "http://localhost:$SYNAPSE_PORT";
		proxy_set_header "X-Forwarded-For" "\$remote_addr";
	}
}
EOF
