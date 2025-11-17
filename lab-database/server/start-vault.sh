#!/bin/sh
set -e

mkdir -p /vault/data
chown -R vault:vault /vault/data

exec /usr/local/bin/docker-entrypoint.sh "$@"
