path "pki/issue/web-role" {
  capabilities = ["update"]
}

path "pki/cert/*" {
  capabilities = ["read", "list"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

path "pki/revoke" {
  capabilities = ["update"]
}
