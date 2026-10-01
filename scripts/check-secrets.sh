#!/bin/sh
set -eu

matches="$(rg -l --hidden --glob '!.git/**' --glob '!.env.example' --glob '!scripts/check-secrets.sh' '(service_role[^A-Za-z0-9]{0,8}eyJ|SUPABASE_SERVICE_ROLE_KEY=[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' . || true)"
if [ -n "$matches" ]; then
  echo "Potential secret material found in:"
  echo "$matches"
  exit 1
fi
echo "No committed service-role JWT or private key pattern found."
