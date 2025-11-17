#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$LAB_ROOT/docker-compose.yml")
LOCAL_DIR="$LAB_ROOT/.local"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Stopping lab containers and removing volumes..."
"${COMPOSE[@]}" down -v

if [[ -d "$LOCAL_DIR" ]]; then
  log "Setup artifacts remain in $LOCAL_DIR (unseal key, tokens). Remove manually if no longer needed."
fi
