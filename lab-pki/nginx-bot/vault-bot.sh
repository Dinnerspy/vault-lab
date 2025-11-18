#!/usr/bin/env bash
set -euo pipefail

ROLE_ID_PATH="${ROLE_ID_PATH:-/vault-approle/role_id}"
SECRET_ID_PATH="${SECRET_ID_PATH:-/vault-approle/secret_id}"
PKI_MOUNT="${PKI_MOUNT:-pki}"
PKI_ROLE_NAME="${PKI_ROLE_NAME:-web-role}"
PKI_COMMON_NAME="${PKI_COMMON_NAME:-web.local}"
PKI_CERT_PATH="${PKI_CERT_PATH:-/etc/nginx/certs/cert.pem}"
PKI_KEY_PATH="${PKI_KEY_PATH:-/etc/nginx/certs/key.pem}"
PKI_CACHAIN_PATH="${PKI_CACHAIN_PATH:-/etc/nginx/certs/ca.pem}"
PKI_TTL="${CERT_TTL:-1m}"
PKI_RENEW_TIME="${PKI_RENEW_TIME:-30s}"
VAULTBOT_LOGFILE="${VAULTBOT_LOGFILE:-/var/log/vaultbot.log}"
RENEW_HOOK="${RENEW_HOOK:-/usr/local/bin/vaultbot-renew-hook.sh}"
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
BOOTSTRAP_TOKEN="${VAULT_BOOTSTRAP_TOKEN:-}"
APPROLE_ROLE_NAME="${APPROLE_ROLE_NAME:-vault-bot}"

# If credentials don't exist, fetch them from Vault using bootstrap token
if [[ ! -f "$ROLE_ID_PATH" || ! -f "$SECRET_ID_PATH" ]]; then
  if [[ -z "$BOOTSTRAP_TOKEN" ]]; then
    echo "[Vault Bot] Missing AppRole credentials at $ROLE_ID_PATH or $SECRET_ID_PATH" >&2
    echo "[Vault Bot] No VAULT_BOOTSTRAP_TOKEN provided to fetch credentials" >&2
    exit 1
  fi
  
  echo "[Vault Bot] Fetching AppRole credentials from Vault..." >&2
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "$ROLE_ID_PATH")"
  
  export VAULT_TOKEN="$BOOTSTRAP_TOKEN"
  
  # Fetch role_id
  echo "[Vault Bot] Fetching role_id..." >&2
  if ! vault read -field=role_id "auth/approle/role/${APPROLE_ROLE_NAME}/role-id" > "$ROLE_ID_PATH"; then
    echo "[Vault Bot] Failed to fetch role_id from Vault" >&2
    exit 1
  fi
  echo "[Vault Bot] role_id fetched" >&2
  
  # Generate secret_id
  echo "[Vault Bot] Generating secret_id..." >&2
  if ! vault write -f -field=secret_id "auth/approle/role/${APPROLE_ROLE_NAME}/secret-id" > "$SECRET_ID_PATH"; then
    echo "[Vault Bot] Failed to generate secret_id from Vault" >&2
    exit 1
  fi
  echo "[Vault Bot] secret_id generated" >&2
  
  unset VAULT_TOKEN
  echo "[Vault Bot] AppRole credentials fetched successfully" >&2
fi

export VAULT_APP_ROLE_ROLE_ID="$(cat "$ROLE_ID_PATH")"
export VAULT_APP_ROLE_SECRET_ID="$(cat "$SECRET_ID_PATH")"

echo "[Vault Bot] Starting vaultbot with role_id: ${VAULT_APP_ROLE_ROLE_ID:0:10}..." >&2
echo "[Vault Bot] Vault address: ${VAULT_ADDR:-http://vault:8200}" >&2
echo "[Vault Bot] PKI mount: $PKI_MOUNT, role: $PKI_ROLE_NAME, common_name: $PKI_COMMON_NAME" >&2

vaultbot \
  --vault_addr="${VAULT_ADDR:-http://vault:8200}" \
  --vault_auth_method=approle \
  --vault_app_role_mount=approle \
  --pki_mount="$PKI_MOUNT" \
  --pki_role_name="$PKI_ROLE_NAME" \
  --pki_common_name="$PKI_COMMON_NAME" \
  --pki_cert_path="$PKI_CERT_PATH" \
  --pki_cachain_path="$PKI_CACHAIN_PATH" \
  --pki_privkey_path="$PKI_KEY_PATH" \
  --pki_ttl="$PKI_TTL" \
  --pki_renew_time="$PKI_RENEW_TIME" \
  --logfile="$VAULTBOT_LOGFILE" \
  --renew_hook="$RENEW_HOOK" \
  --auto_confirm
