#!/usr/bin/env bash
set -euo pipefail

CERT_PATH=${PKI_CERT_PATH:-/etc/nginx/certs/cert.pem}
KEY_PATH=${PKI_KEY_PATH:-/etc/nginx/certs/key.pem}
CA_PATH=${PKI_CACHAIN_PATH:-/etc/nginx/certs/ca.pem}
CERT_INFO_PATH=${CERT_INFO_PATH:-/usr/share/nginx/html/cert-info.html}

if [[ ! -f "$CERT_PATH" ]]; then
  echo "[Vaultbot Hook] Certificate not found at $CERT_PATH" >&2
  exit 1
fi

chmod 600 "$KEY_PATH"

SERIAL=$(openssl x509 -in "$CERT_PATH" -noout -serial | cut -d= -f2 || echo "unknown")
NOT_BEFORE=$(openssl x509 -in "$CERT_PATH" -noout -startdate | cut -d= -f2 || echo "unknown")
NOT_AFTER=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2 || echo "unknown")

cat <<HTML > "$CERT_INFO_PATH"
<table>
  <tr><td>Issued For</td><td>${PKI_COMMON_NAME:-web.local}</td></tr>
  <tr><td>Issued At</td><td>${NOT_BEFORE}</td></tr>
  <tr><td>Expires</td><td>${NOT_AFTER}</td></tr>
  <tr><td>Serial Number</td><td>${SERIAL}</td></tr>
  <tr><td>Updated</td><td>$(date -u)</td></tr>
</table>
HTML

echo "[Vaultbot Hook] Updated certificate info at $CERT_INFO_PATH"

# Reload Nginx to pick up renewed certificate
if ! nginx -s reload; then
  echo "[Vaultbot Hook] nginx reload failed (may be first issuance)." >&2
fi
