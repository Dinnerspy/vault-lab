#!/bin/sh
set -e

mkdir -p /vault/data
chown -R vault:vault /vault/data

# Run Vault directly to avoid dev mode defaults
if [ "$(id -u)" = '0' ]; then
    exec su-exec vault vault "$@"
else
    exec vault "$@"
fi
