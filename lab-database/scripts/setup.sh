#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$LAB_ROOT/docker-compose.yml")
LOCAL_DIR="$LAB_ROOT/.local"
INIT_OUTPUT="$LOCAL_DIR/init-output.txt"
UNSEAL_KEY_FILE="$LOCAL_DIR/unseal-key.txt"
ROOT_TOKEN_FILE="$LOCAL_DIR/root-token.txt"
APP_TOKEN_FILE="$LOCAL_DIR/db-app-token.txt"
APPROLE_DIR="$LOCAL_DIR/approle"
ROLE_ID_FILE="$APPROLE_DIR/role_id"
SECRET_ID_FILE="$APPROLE_DIR/secret_id"

log() {
  printf '[%%s] %%s\n' "$(date '+%H:%M:%S')" "$*"
}

mkdir -p "$LOCAL_DIR"
mkdir -p "$APPROLE_DIR"

log "Starting lab containers (Vault, Postgres, Shell)..."
"${COMPOSE[@]}" up -d --build

log "Waiting for Vault API to respond..."
until "${COMPOSE[@]}" exec -T shell curl -sSf http://vault:8200/v1/sys/health >/dev/null; do
  sleep 2
  printf '.'
done
printf '\n'

if [[ ! -f "$UNSEAL_KEY_FILE" || ! -f "$ROOT_TOKEN_FILE" ]]; then
  log "Initializing Vault (storing artifacts in .local/)..."
  INIT_RESULT="$("${COMPOSE[@]}" exec -T vault vault operator init -key-shares=1 -key-threshold=1)"
  printf '%s\n' "$INIT_RESULT" > "$INIT_OUTPUT"
  UNSEAL_KEY="$(printf '%s\n' "$INIT_RESULT" | awk '/Unseal Key 1:/ {print $NF}')"
  ROOT_TOKEN="$(printf '%s\n' "$INIT_RESULT" | awk '/Initial Root Token:/ {print $NF}')"
  printf '%s\n' "$UNSEAL_KEY" > "$UNSEAL_KEY_FILE"
  printf '%s\n' "$ROOT_TOKEN" > "$ROOT_TOKEN_FILE"
else
  UNSEAL_KEY="$(<"$UNSEAL_KEY_FILE")"
  ROOT_TOKEN="$(<"$ROOT_TOKEN_FILE")"
  log "Vault already initialized; reusing credentials from .local/."
fi

log "Unsealing Vault..."
"${COMPOSE[@]}" exec -T vault vault operator unseal "$UNSEAL_KEY" >/dev/null

log "Configuring Vault database secrets engine..."
"${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell bash <<'EOF'
set -euo pipefail

if ! vault status >/dev/null 2>&1; then
  echo "Vault status check failed" >&2
  exit 1
fi

if ! vault secrets list | grep -q '^database/'; then
  vault secrets enable database
fi

vault write database/config/app-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles=app-role \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/appdb?sslmode=disable" \
  username="root" \
  password="rootpassword"

vault write database/roles/app-role \
  db_name=app-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT CONNECT ON DATABASE appdb TO \"{{name}}\"; GRANT USAGE ON SCHEMA public TO \"{{name}}\"; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="2m"

vault policy write db-app-policy /workspace/policies/db-app-policy.hcl

if ! vault auth list | grep -q '^approle/'; then
  vault auth enable approle
fi

vault write auth/approle/role/db-app \
  token_policies=db-app-policy \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=2m
EOF

log "Retrieving AppRole credentials for demo app..."
ROLE_ID="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell vault read -field=role_id auth/approle/role/db-app/role-id)"
printf '%s\n' "$ROLE_ID" > "$ROLE_ID_FILE"
SECRET_ID="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell vault write -f -field=secret_id auth/approle/role/db-app/secret-id)"
printf '%s\n' "$SECRET_ID" > "$SECRET_ID_FILE"

if [[ ! -f "$APP_TOKEN_FILE" ]]; then
  log "Creating short-lived application token bound to db-app-policy..."
  APP_TOKEN="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell bash -lc 'vault token create -policy=db-app-policy -format=json | jq -r ".auth.client_token"')"
  printf '%s\n' "$APP_TOKEN" > "$APP_TOKEN_FILE"
else
  APP_TOKEN="$(<"$APP_TOKEN_FILE")"
fi

log "Setup complete. Useful artifacts:"
log "  Root token : $ROOT_TOKEN_FILE"
log "  Unseal key : $UNSEAL_KEY_FILE"
log "  App token  : $APP_TOKEN_FILE"
log "  AppRole    : $APPROLE_DIR (role_id & secret_id)"
log "Use \"docker compose -f $LAB_ROOT/docker-compose.yml exec shell bash\" to open the workstation."
