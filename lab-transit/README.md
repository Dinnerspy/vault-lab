# Lab: Vault Transit Engine (Encryption as a Service)

This lab demonstrates using HashiCorp Vault's Transit secrets engine to implement encryption at rest. A Flask app encrypts submitted secrets via Transit before persisting them to disk; ciphertext is stored locally while plaintext is only revealed on-demand after a fresh Vault decrypt call.

## Stack Overview

- **vault** – Vault OSS with Raft storage serving the transit engine.
- **shell** – Workstation container with Vault CLI and tooling for manual operations.
- **app** – Flask application that writes secrets encrypted-at-rest and decrypts them on demand via Transit.

## Prerequisites

- Docker and Docker Compose v2 (`docker compose`).
- Bash (for helper scripts).

## Quickstart (Automated)

```bash
cd lab-transit
./scripts/setup.sh
```

The script will:

1. Start the Docker Compose stack.
2. Initialize and unseal Vault (credentials stored under `.local/`).
3. Enable the Transit secrets engine and create a key named `app-key`.
4. Create `transit-app-policy` and an AppRole with short-lived credentials.
5. Restart the demo app so it picks up the AppRole files and can call Transit.

Once setup completes, open <http://localhost:5001>. Use the web form to submit plaintext for encryption. The app stores only the ciphertext on disk. Selecting an existing record triggers on-demand decryption through Vault using fresh AppRole authentication.

Tear down the lab with:

```bash
./scripts/teardown.sh
```

> **Note:** Teardown leaves `.local/` intact (root token, unseal key, AppRole credentials). Delete it manually for a clean reset.

## Manual Instructions

### 1. Start the stack

```bash
cd lab-transit
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

vault secrets enable transit
vault write -f transit/keys/app-key

vault policy write transit-app-policy /workspace/policies/transit-app-policy.hcl

vault auth enable approle
vault write auth/approle/role/transit-app \
  token_policies=transit-app-policy \
  token_ttl=2m \
  token_max_ttl=5m \
  secret_id_ttl=2m

vault read -field=role_id auth/approle/role/transit-app/role-id > /workspace/approle/role_id
vault write -f -field=secret_id auth/approle/role/transit-app/secret-id > /workspace/approle/secret_id
```

Copy the AppRole artifacts back to the host:

```bash
exit
docker cp $(docker compose ps -q shell):/workspace/approle/. .local/approle/
docker compose exec shell bash
```

### 4. Issue Encryption/Decryption Manually

```bash
PLAINTEXT=$(echo "hello world" | base64)
vault write transit/encrypt/app-key plaintext="$PLAINTEXT"
# Capture ciphertext and store it on disk
vault write transit/decrypt/app-key ciphertext="vault:v1:..."
```

### 5. Restart the demo app

```bash
docker compose restart app
```

### 6. Verify from the shell

```bash
curl -s http://app:5000
# Use the web form or issue direct API calls if desired
```

### 7. Cleanup

```bash
docker compose down -v
```

Delete `.local/` if you no longer need stored keys/tokens.

## Bonus Exercises

1. **Rotate the Transit Key:**
   ```bash
   docker compose exec shell vault write -f transit/keys/app-key/rotate
   ```
   Observe how ciphertext version increments and verify decryption still works.

2. **Key Derivation:**
   Update the setup to enable `derived=true` on the transit key, then demonstrate per-context encryption and decryption.

3. **Batch Encryption:**
   Experiment with batching multiple plaintext values in a single API call.

## Useful Commands

- Tail Vault logs:
  ```bash
  docker compose logs -f vault
  ```
- Tail app logs:
  ```bash
  docker compose logs -f app
  ```
- Issue a one-off encryption from the host:
  ```bash
  docker compose exec shell vault write -format=json transit/encrypt/app-key plaintext=$(echo -n "test" | base64)
  ```
- Decrypt value directly via curl (token required):
  ```bash
  curl --header "X-Vault-Token: $VAULT_TOKEN" \
       --request POST \
       --data '{"ciphertext":"vault:v1:..."}' \
       http://localhost:8200/v1/transit/decrypt/app-key
  ```
