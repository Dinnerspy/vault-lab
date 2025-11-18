#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$LAB_ROOT/docker-compose.yml")
LOCAL_DIR="$LAB_ROOT/.local"
INIT_OUTPUT="$LOCAL_DIR/init-output.txt"
UNSEAL_KEY_FILE="$LOCAL_DIR/unseal-key.txt"
ROOT_TOKEN_FILE="$LOCAL_DIR/root-token.txt"
APPROLE_DIR="$LOCAL_DIR/approle"
ROLE_ID_FILE="$APPROLE_DIR/role_id"
SECRET_ID_FILE="$APPROLE_DIR/secret_id"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

mkdir -p "$APPROLE_DIR"

log "Starting transit lab containers (Vault, Shell, Demo App)..."
"${COMPOSE[@]}" up -d --build

log "Waiting for Vault API to respond..."
until "${COMPOSE[@]}" exec -T shell curl -sSf http://vault:8200/v1/sys/health >/dev/null; do
  sleep 2
  printf '.'
done
printf '\n'

if [[ ! -f "$UNSEAL_KEY_FILE" || ! -f "$ROOT_TOKEN_FILE" ]]; then
  log "Initializing Vault (storing keys under .local/)..."
  INIT_RESULT="$("${COMPOSE[@]}" exec -T vault vault operator init -key-shares=1 -key-threshold=1)"
  printf '%s\n' "$INIT_RESULT" > "$INIT_OUTPUT"
  UNSEAL_KEY="$(printf '%s\n' "$INIT_RESULT" | awk '/Unseal Key 1:/ {print $NF}')"
  ROOT_TOKEN="$(printf '%s\n' "$INIT_RESULT" | awk '/Initial Root Token:/ {print $NF}')"
  printf '%s\n' "$UNSEAL_KEY" > "$UNSEAL_KEY_FILE"
  printf '%s\n' "$ROOT_TOKEN" > "$ROOT_TOKEN_FILE"
else
  UNSEAL_KEY="$(<"$UNSEAL_KEY_FILE")"
  ROOT_TOKEN="$(<"$ROOT_TOKEN_FILE")"
  log "Vault already initialized; reusing existing credentials."
fi

log "Unsealing Vault..."
"${COMPOSE[@]}" exec -T vault vault operator unseal "$UNSEAL_KEY" >/dev/null

log "Configuring transit secrets engine and policy..."
"${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell bash <<'EOF'
set -euo pipefail

if ! vault secrets list | grep -q '^transit/'; then
  vault secrets enable transit
fi

vault write -f transit/keys/app-key

vault policy write transit-app-policy /workspace/policies/transit-app-policy.hcl

if ! vault auth list | grep -q '^approle/'; then
  vault auth enable approle
fi

vault write auth/approle/role/transit-app \
  token_policies=transit-app-policy \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=24h
EOF

log "Retrieving AppRole credentials for demo app..."
ROLE_ID="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell vault read -field=role_id auth/approle/role/transit-app/role-id)"
printf '%s\n' "$ROLE_ID" > "$ROLE_ID_FILE"
SECRET_ID="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell vault write -f -field=secret_id auth/approle/role/transit-app/secret-id)"
printf '%s\n' "$SECRET_ID" > "$SECRET_ID_FILE"

log "Restarting demo app to consume AppRole credentials..."
"${COMPOSE[@]}" restart app >/dev/null

log "Transit lab setup complete. Useful artifacts:"
log "  Root token : $ROOT_TOKEN_FILE"
log "  Unseal key : $UNSEAL_KEY_FILE"
log "  AppRole    : $APPROLE_DIR (role_id & secret_id)"
log "Visit http://localhost:5001 to exercise encryption/decryption demo."
