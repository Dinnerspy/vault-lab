#!/usr/bin/env bash
set -euo pipefail

# Ensure default cert info exists so the static page has content before Vault Bot runs.
CERT_INFO="/usr/share/nginx/html/cert-info.html"
if [[ ! -f "$CERT_INFO" ]]; then
  cat <<'HTML' > "$CERT_INFO"
<p>No Vault certificate has been issued yet.</p>
HTML
fi

# Start nginx in the background
nginx

# Start the Vault Bot loop (foreground)
exec /usr/local/bin/vault-bot.sh
