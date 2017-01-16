#!/usr/bin/env bash

set -e

scriptDir="$(dirname "${BASH_SOURCE[0]}")"
readme="$scriptDir/../README.md"

echo "# Variables for pwiki-synapse saved at $(date)."
while read line; do
	varname="$(echo "$line" | cut -d= -f1)"
	if grep -qP "^\\\$ $varname=" "$readme"; then
		echo "$line"
	fi
done
echo '# End variables.'
