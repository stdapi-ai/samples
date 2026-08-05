/*
============================================================================
LobeHub Authentication Secrets
============================================================================
KEY_VAULTS_SECRET, AUTH_SECRET, and the JWKS_KEY LobeHub needs for OIDC
token signing and internal service-to-service call authentication.

JWKS_KEY must be a JWKS JSON string containing an RS256 RSA key pair
(https://lobehub.com/docs/self-hosting/environment-variables/auth). The key
itself is generated here, once, so every task signs with the same one and it
survives redeployments; the PEM is converted to the JWK members LobeHub
expects (n, e, d, p, q, dp, dq, qi) by the container at start-up, which needs
no tooling on the machine running the apply. See local.jwks_script and the
"main" container's command in lobehub.tf.
*/

resource "tls_private_key" "jwks" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

#: 32-byte, base64-encoded key LobeHub uses to encrypt provider API keys and other sensitive data at rest in Postgres.
resource "random_id" "key_vaults_secret" {
  byte_length = 32
}

#: 32-byte, base64-encoded secret LobeHub uses to encrypt session tokens.
resource "random_id" "auth_secret" {
  byte_length = 32
}
