# Vault Lab Collection

Hands-on labs demonstrating HashiCorp Vault in realistic scenarios. Each lab provides Docker Compose infrastructure, automation scripts, Vault policies, and demo workloads.

## Labs

### 1. Database Secrets Engine
- Location: `lab-database/`
- Focus: Dynamic PostgreSQL credentials with short TTL (~2 minutes).
- Components: Vault (Raft), Postgres, shell workstation, Flask demo app.
- Workflow: Setup script initializes Vault, enables DB secrets engine, creates AppRole. App fetches fresh credentials on demand to query sample data.
- Docs: `lab-database/README.md`

### 2. Transit Engine (Encryption as a Service)
- Location: `lab-transit/`
- Focus: Encrypt/decrypt using Vault Transit via AppRole-authenticated Flask UI.
- Components: Vault (Raft), shell workstation, Flask demo app.
- Workflow: Setup script enables Transit, creates `app-key`, provisions AppRole credentials. UI encrypts plaintext or decrypts ciphertext by calling Transit APIs.
- Docs: `lab-transit/README.md`

### 3. PKI Engine with Vaultbot
- Location: `lab-pki/`
- Focus: Short-lived TLS cert issuance/renewal using official Vaultbot + Nginx.
- Components: Vault (Raft), shell workstation, combined Nginx/Vaultbot container.
- Workflow: Setup script builds PKI hierarchy, issues AppRole creds for Vaultbot. Vaultbot continually renews certs, triggers reload and updates cert info page.
- Docs: `lab-pki/README.md`

## Getting Started

1. Pick a lab directory.
2. Run `./scripts/setup.sh` for automated provisioning.
3. Follow the lab-specific README for manual steps, verification, and teardown (`./scripts/teardown.sh`).

> **Requires:** Docker, Docker Compose v2, and Bash. Vault stores Raft data locally per lab; sensitive artifacts are written to `lab-*/.local/` (gitignored).

## Repository Structure

```
lab-database/
lab-transit/
lab-pki/
README.md
.gitignore
```

Each lab is self-contained with Dockerfiles, scripts, policies, and documentation. Use the root README as the entry point for discovering individual labs.
