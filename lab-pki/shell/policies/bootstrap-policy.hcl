# Policy for bootstrap token to fetch AppRole credentials
# This token can only read role_id and generate secret_id for vault-bot role

path "auth/approle/role/vault-bot/role-id" {
  capabilities = ["read"]
}

path "auth/approle/role/vault-bot/secret-id" {
  capabilities = ["create", "update"]
}
