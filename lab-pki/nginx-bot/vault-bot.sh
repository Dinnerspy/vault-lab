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

if [[ ! -f "$ROLE_ID_PATH" || ! -f "$SECRET_ID_PATH" ]]; then
  echo "[Vault Bot] Missing AppRole credentials at $ROLE_ID_PATH or $SECRET_ID_PATH" >&2
  exit 1
fi

export VAULT_APP_ROLE_ROLE_ID="$(cat "$ROLE_ID_PATH")"
export VAULT_APP_ROLE_SECRET_ID="$(cat "$SECRET_ID_PATH")"

exec vaultbot \
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
