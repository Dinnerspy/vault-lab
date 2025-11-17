#!/bin/sh
set -e

mkdir -p /vault/data
chown -R vault:vault /vault/data

# Run Vault directly instead of through docker-entrypoint.sh
# to avoid dev mode defaults that conflict with our config
if [ "$(id -u)" = '0' ]; then
    exec su-exec vault vault "$@"
else
    exec vault "$@"
fi
