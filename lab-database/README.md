# Lab: Vault Database Secrets Engine with PostgreSQL

This lab demonstrates how HashiCorp Vault's Database Secrets Engine can dynamically issue short-lived PostgreSQL credentials. The environment runs entirely with Docker Compose and uses Raft storage for Vault.

## Stack Overview

- **vault** – Vault server using Raft storage and the database secrets engine.
- **postgres** – PostgreSQL database seeded with a simple schema.
- **shell** – Workstation container with Vault CLI, psql, and tooling for interacting with the lab.

## Prerequisites

- Docker and Docker Compose v2 (`docker compose`).
- Bash (for the helper scripts).

## Quickstart (Automated)

```bash
cd lab-database
./scripts/setup.sh
```

The script will:

1. Start the Docker Compose stack.
2. Initialize and unseal Vault (keys saved under `.local/`).
3. Enable and configure the database secrets engine.
4. Create the `db-app-policy`, an app token saved to `.local/db-app-token.txt`, and an AppRole with its `role_id`/`secret_id` written to `.local/approle/` for the demo web app (each button press issues new credentials with ≈2 minute TTL).

Once setup completes, browse to <http://localhost:8080> to view the sample web application. Each press of the button requests a fresh, short-lived credential (≈2 minute TTL) via AppRole and immediately queries Postgres before the credential expires.

To tear down the lab:

```bash
./scripts/teardown.sh
```

> **Note:** Teardown leaves the `.local/` directory intact so you can reuse credentials. Delete it manually if you want a clean slate.

## Manual Instructions

### 1. Start the stack

```bash
cd lab-database
docker compose up -d --build
```

### 2. Initialize and unseal Vault

```bash
docker compose exec vault vault operator init
# Save unseal key & root token (e.g., into .local/ files)
docker compose exec vault vault operator unseal <UNSEAL_KEY>
```

### 3. Configure Vault (from the shell container)

```bash
# Enter the workstation container
docker compose exec shell bash

# Inside the shell container
export VAULT_TOKEN=<ROOT_TOKEN>
vault secrets enable database
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

mkdir -p /workspace/approle
vault auth enable approle
vault write auth/approle/role/db-app \
  token_policies=db-app-policy \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=2m

vault read -field=role_id auth/approle/role/db-app/role-id > /workspace/approle/role_id
vault write -f -field=secret_id auth/approle/role/db-app/secret-id > /workspace/approle/secret_id

# Copy the approle files back to the host if needed
exit
docker cp $(docker compose ps -q shell):/workspace/approle/. .local/approle/
docker compose exec shell bash  # re-enter if you want to keep working inside
```

### 4. Generate dynamic credentials

```bash
vault token create -policy=db-app-policy
export VAULT_TOKEN=<APP_TOKEN>

vault read database/creds/app-role
```

Copy the returned username/password and test against Postgres:

```bash
psql --host=postgres --username=<dynamic-username> --dbname=appdb
``` 

### 5. Launch the demo web application

```bash
docker compose up -d app
```

Browse to <http://localhost:8080>. Each button press asks Vault for brand-new database credentials (≈2 minute TTL) via AppRole and immediately uses them to query the `app_secrets` table.

### 6. Cleanup

```bash
docker compose down -v
```

Optionally delete the `.local/` directory to remove stored keys and tokens.

## Testing Certificate Rotation

Not applicable for this lab.

## Troubleshooting

### AppRole "invalid role or secret ID" Error

If the demo app shows an AppRole authentication error, the `secret_id` may have expired (2-minute TTL by design). Regenerate it:

```bash
# From the lab-database directory
export VAULT_TOKEN=$(cat .local/root-token.txt)
docker compose exec -e VAULT_TOKEN shell vault write -f -field=secret_id auth/approle/role/db-app/secret-id > .local/approle/secret_id
docker compose restart app
```

Or re-run the setup script to regenerate all credentials.

## Useful Commands

- Check Vault status:
  ```bash
  docker compose exec shell vault status
  ```
- Inspect generated credentials:
  ```bash
  docker compose exec shell vault read database/creds/app-role
  ```
- Connect to Postgres with the workstation container:
  ```bash
  docker compose exec shell psql --host=postgres --username=root --dbname=appdb
  ```
- View the demo web application:
  ```bash
  open http://localhost:8080   # macOS
  start http://localhost:8080  # Windows
  xdg-open http://localhost:8080  # Linux/WSL
  ```
