#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$LAB_ROOT/docker-compose.yml")

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Stopping transit lab containers and removing volumes..."
"${COMPOSE[@]}" down -v

log "Artifacts remain in $LAB_ROOT/.local (root token, unseal key, AppRole credentials). Remove manually if you no longer need them."
