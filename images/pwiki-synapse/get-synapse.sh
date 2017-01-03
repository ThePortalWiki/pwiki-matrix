#!/usr/bin/env bash

set -e
set -x

apt-get install -y apt-transport-https gettext gnupg2 sudo postgresql-client python-psycopg2

echo 'deb https://matrix.org/packages/debian/ stretch main' > /etc/apt/sources.list.d/matrix.list
apt-key adv --fetch-keys 'https://matrix.org/packages/debian/repo-key.asc'
apt-get update
apt-get install -y matrix-synapse
