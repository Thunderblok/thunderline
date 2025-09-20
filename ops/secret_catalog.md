# Secret Catalog (links only)

- Thunderline DATABASE_URL — set via env in prod (see config/runtime.exs)
- SECRET_KEY_BASE — env var (runtime)
- TOKEN_SIGNING_SECRET — env var (runtime)
- THUNDERLINE_VAULT_KEY — optional base64 256-bit key for Cloak vault
- OPENAI_API_KEY — for langchain integration
- Fly.io app secrets — per fly.toml deployment

Note: Do not store plaintext values. Reference source of truth (GitHub Encrypted Secrets, 1Password, GCP Secret Manager).
