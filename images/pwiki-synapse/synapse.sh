#!/usr/bin/env bash

exec sudo -u synapse python -m synapse.app.homeserver --config-path /synapse/synapse.yaml
