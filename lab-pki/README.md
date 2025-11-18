# Lab: Vault PKI with Nginx + Vault Bot

This lab demonstrates HashiCorp Vault's PKI secrets engine issuing short-lived TLS certificates for an Nginx server. A combined container runs both Nginx and the official [vaultbot](https://github.com/soundcloud/vault-bot) binary (downloaded at build time) to authenticate via AppRole, request leaf certificates with ≈1 minute TTL, write them into a shared location, and reload Nginx automatically.

## Stack Overview

- **vault** – Vault OSS using Raft storage and the PKI secrets engine.
- **shell** – Workstation container with Vault CLI and tooling for manual configuration.
- **nginx-bot** – Combined container running Nginx plus vaultbot under a lightweight supervisor. Starts with a self-signed placeholder and switches to Vault-issued certificates once configured.

## Prerequisites

- Docker and Docker Compose v2 (`docker compose`).
- Bash (for helper scripts).
- Host entries for `web.local` (e.g., add `127.0.0.1 web.local` to `/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`).

## Quickstart (Automated)

```bash
cd lab-pki
./scripts/setup.sh
```

The script will:

1. Start the Docker Compose stack.
2. Initialize and unseal Vault (credentials stored under `.local/`).
3. Enable and configure the PKI secrets engine (root CA + role).
4. Create policies and an AppRole dedicated to the Vault Bot with short-lived credentials.
5. Restart the `nginx-bot` container so it picks up the AppRole files and vaultbot begins certificate rotation (≈1 minute TTL, renews every ~60 seconds).

After setup completes, browse to:

- <https://web.local:8443> – HTTPS endpoint showing the current Vault-issued certificate.
- <http://web.local:8080> – Plain HTTP endpoint (same content) if you want to inspect without TLS.

The page embeds `cert-info.html`, which vaultbot's renew hook rewrites every rotation showing issue time, serial, and expiration. Because certificates are short-lived, refreshing the page after a couple of minutes should show new serial numbers and timestamps.

Tear down the lab with:

```bash
./scripts/teardown.sh
```

> **Note:** Teardown leaves `.local/` intact (root token, unseal key, AppRole credentials). Remove it manually for a clean reset.

## Manual Instructions

### 1. Start the stack

```bash
cd lab-pki
docker compose up -d --build
```

### 2. Initialize and unseal Vault

```bash
docker compose exec vault vault operator init
# Save unseal key & root token into .local/
docker compose exec vault vault operator unseal <UNSEAL_KEY>
```

### 3. Configure Vault (from the shell container)

```bash
# Enter workstation container
docker compose exec shell bash

# Inside the shell container
export VAULT_TOKEN=<ROOT_TOKEN>

vault secrets enable pki
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
  ttl="1m" \
  max_ttl="2m" \
  generate_lease=true

vault policy write pki-web-policy /workspace/policies/pki-web-policy.hcl
vault policy write vault-bot-policy /workspace/policies/vault-bot-policy.hcl
vault policy write bootstrap-policy /workspace/policies/bootstrap-policy.hcl

mkdir -p /workspace/approle
vault auth enable approle
vault write auth/approle/role/vault-bot \
  token_policies=vault-bot-policy \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=24h

# Create bootstrap token for nginx-bot to fetch its own credentials
vault token create -policy=bootstrap-policy -ttl=10m -field=token > /workspace/bootstrap-token.txt
cat /workspace/bootstrap-token.txt
```

The `nginx-bot` container will automatically fetch its AppRole credentials from Vault using the bootstrap token when it starts. No manual copying is needed.

### 4. Demonstrate manual issuance (optional)

```bash
vault write -format=json pki/issue/web-role common_name=web.local ttl=1m > /tmp/manual-cert.json
jq -r .data.certificate /tmp/manual-cert.json
```

### 5. Start/Restart the Nginx + Vault Bot container

First, copy the bootstrap token to the host and set it as an environment variable:

```bash
exit  # Exit the shell container
docker cp $(docker compose ps -q shell):/workspace/bootstrap-token.txt .local/
export VAULT_BOOTSTRAP_TOKEN=$(cat .local/bootstrap-token.txt)
docker compose up -d nginx-bot
```

Watch the bot logs to confirm certificate issuance and rotations:

```bash
docker compose logs -f nginx-bot
```

### 6. Verify from the shell

```bash
curl -vk --resolve web.local:443:nginx-bot https://web.local
openssl s_client -connect nginx-bot:443 -servername web.local </dev/null
```

(You can also access <https://web.local:8443> from the host browser after adding the hosts entry.)

### 7. Bonus – Manual Vault Bot Actions

To simulate manual bot behavior from the shell:

```bash
vault write -format=json pki/issue/web-role common_name=web.local ttl=1m \
  | tee /tmp/rotate.json
jq -r .data.certificate /tmp/rotate.json > /workspace/rotate/cert.pem
jq -r .data.private_key /tmp/rotate.json > /workspace/rotate/key.pem
```

(You can then copy these into `/etc/nginx/certs` inside the container to mimic bot behavior.)

### 8. Bonus – Revoke Lab

1. List issued certificates:
   ```bash
   vault list pki/cert/
   ```
2. Revoke a specific certificate by serial number:
   ```bash
   vault write pki/revoke serial_number=<SERIAL>
   ```
3. Inspect the CRL or confirm the bot has issued a replacement:
   ```bash
   curl http://vault:8200/v1/pki/crl
   docker compose logs -f nginx-bot
   ```

### 9. Cleanup

```bash
docker compose down -v
```

Delete `.local/` if you no longer need stored keys/tokens.

## Troubleshooting

### nginx-bot Container Fails to Start

The `nginx-bot` container fetches its own AppRole credentials from Vault at startup using a bootstrap token. If it fails to start:

1. **Bootstrap token expired** (10-minute TTL). Regenerate it:
   ```bash
   export VAULT_TOKEN=$(cat .local/root-token.txt)
   export VAULT_BOOTSTRAP_TOKEN=$(docker compose exec -e VAULT_TOKEN shell vault token create -policy=bootstrap-policy -ttl=10m -field=token)
   docker compose up -d nginx-bot
   ```

2. **AppRole credentials expired** (24-hour TTL). The container will automatically restart and fetch fresh credentials. Check logs:
   ```bash
   docker compose logs nginx-bot --tail 50
   ```

3. **Vault sealed or unhealthy**. Unseal Vault:
   ```bash
   docker compose exec vault vault operator unseal <unseal-key>
   ```

### Certificate Not Issued

If you see "No Vault certificate has been issued yet" on the web page:

- The container automatically detects the placeholder certificate and forces renewal on first run
- Check vaultbot logs: `docker compose logs nginx-bot | grep -i certificate`
- Vaultbot checks every 60 seconds and renews certificates 30 seconds before expiry

## Useful Commands

- Tail Vault logs:
  ```bash
  docker compose logs -f vault
  ```
- Tail bot logs:
  ```bash
  docker compose logs -f nginx-bot
  ```
- Issue a one-off certificate:
  ```bash
  docker compose exec shell vault write -format=json pki/issue/web-role common_name=web.local ttl=1m
  ```
- Inspect current certificate from the host:
  ```bash
  openssl s_client -connect web.local:8443 -servername web.local </dev/null | openssl x509 -noout -dates -serial
  ```
