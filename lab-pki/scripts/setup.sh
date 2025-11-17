#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$LAB_ROOT/docker-compose.yml")
LOCAL_DIR="$LAB_ROOT/.local"
INIT_OUTPUT="$LOCAL_DIR/init-output.txt"
UNSEAL_KEY_FILE="$LOCAL_DIR/unseal-key.txt"
ROOT_TOKEN_FILE="$LOCAL_DIR/root-token.txt"
BOT_ROLE_ID_FILE="$LOCAL_DIR/bot-approle/role_id"
BOT_SECRET_ID_FILE="$LOCAL_DIR/bot-approle/secret_id"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

mkdir -p "$LOCAL_DIR/bot-approle"

log "Starting PKI lab containers (Vault, Shell, Nginx+Bot)..."
"${COMPOSE[@]}" up -d --build

log "Waiting for Vault API to respond..."
until "${COMPOSE[@]}" exec -T shell curl -sSf http://vault:8200/v1/sys/health >/dev/null; do
  sleep 2
  printf '.'
done
printf '\n'

if [[ ! -f "$UNSEAL_KEY_FILE" || ! -f "$ROOT_TOKEN_FILE" ]]; then
  log "Initializing Vault (saving credentials to .local/)..."
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

log "Configuring PKI secrets engine and policies..."
"${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell bash <<'EOF'
set -euo pipefail

if ! vault secrets list | grep -q '^pki/'; then
  vault secrets enable pki
fi

vault secrets tune -max-lease-ttl=8760h pki

vault write pki/root/generate/internal \
  common_name="Lab Root CA" \
  ttl=8760h

vault write pki/config/urls \
  issuing_certificates="http://vault:8200/v1/pki/ca" \
  crl_distribution_points="http://vault:8200/v1/pki/crl"

vault write pki/roles/web-role \
  allowed_domains="web.local" \
  allow_subdomains=false \
  allow_bare_domains=true \
  max_ttl="2m" \
  ttl="1m" \
  generate_lease=true

vault policy write pki-web-policy /workspace/policies/pki-web-policy.hcl
vault policy write vault-bot-policy /workspace/policies/vault-bot-policy.hcl

if ! vault auth list | grep -q '^approle/'; then
  vault auth enable approle
fi

vault write auth/approle/role/vault-bot \
  token_policies=vault-bot-policy \
  token_ttl="2m" \
  token_max_ttl="5m" \
  secret_id_ttl="2m"
EOF

log "Retrieving AppRole credentials for nginx-bot..."
ROLE_ID="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell vault read -field=role_id auth/approle/role/vault-bot/role-id)"
printf '%s\n' "$ROLE_ID" > "$BOT_ROLE_ID_FILE"
SECRET_ID="$("${COMPOSE[@]}" exec -T --env VAULT_TOKEN="$ROOT_TOKEN" shell vault write -f -field=secret_id auth/approle/role/vault-bot/secret-id)"
printf '%s\n' "$SECRET_ID" > "$BOT_SECRET_ID_FILE"

log "Restarting nginx-bot to pick up AppRole credentials..."
"${COMPOSE[@]}" restart nginx-bot >/dev/null

log "PKI lab setup complete. Useful artifacts:"
log "  Root token : $ROOT_TOKEN_FILE"
log "  Unseal key : $UNSEAL_KEY_FILE"
log "  Bot role_id : $BOT_ROLE_ID_FILE"
log "  Bot secret_id : $BOT_SECRET_ID_FILE"
log "Open https://web.local:8443 (after updating hosts) to verify certificate rotation."
