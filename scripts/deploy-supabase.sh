#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"
mode="${1:-plan}"
origin="${2:-http://127.0.0.1:5173}"
env_file="${3:-supabase/.env}"
project_ref=zoccosfjulasqxczhvfm
case "$mode" in plan|apply) ;; *) echo 'Gunakan plan atau apply.' >&2; exit 2 ;; esac
command -v node >/dev/null || { echo 'Node.js 22+ diperlukan.' >&2; exit 1; }
test -f "$env_file" || { echo 'File secret server belum tersedia. Salin supabase/.env.example ke supabase/.env lalu isi GEMINI_API_KEY.' >&2; exit 1; }

cli() {
  if [ -n "${SUPABASE_CLI:-}" ]; then "$SUPABASE_CLI" "$@";
  elif command -v supabase >/dev/null 2>&1; then supabase "$@";
  else npx --yes supabase@2.119.0 "$@";
  fi
}

umask 077
secrets="$(mktemp /tmp/danarapi-cloud-secrets.XXXXXX)"
trap 'rm -f "$secrets"' EXIT HUP INT TERM
node scripts/prepare-cloud-secrets.mjs "$env_file" "$secrets" "$origin"
cli link --project-ref "$project_ref"
linked_ref="$(cat supabase/.temp/project-ref)"
test "$linked_ref" = "$project_ref" || { echo 'Proyek terhubung tidak cocok. Deployment dihentikan.' >&2; exit 1; }
cli db push --linked --dry-run --skip-vault
if [ "$mode" = plan ]; then
  echo 'Rencana selesai. Belum ada perubahan database/secret/fungsi cloud.'
  exit 0
fi

cli db push --linked --skip-vault
cli secrets set --project-ref "$project_ref" --env-file "$secrets"
for function in ledger ios-data export-data receipt-scan; do
  cli functions deploy "$function" --project-ref "$project_ref" --use-api
done
node --experimental-strip-types scripts/check-cloud.mjs --backend-only
echo 'Backend terdeploy. Lengkapi provider Google/Apple serta redirect URL di Dashboard, kemudian jalankan npm run cloud:check.'
