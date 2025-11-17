#!/usr/bin/env bash
set -euo pipefail

echo "[Vault] Starting with command: vault $*"
exec vault "$@"
