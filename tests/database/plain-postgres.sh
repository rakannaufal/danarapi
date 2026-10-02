#!/bin/sh
set -eu

pg_bin="${PG_BIN:-/Library/PostgreSQL/15/bin}"
test -x "$pg_bin/initdb"
test -x "$pg_bin/pg_ctl"
test -x "$pg_bin/psql"

cluster_dir="$(mktemp -d /tmp/danarapi-pg.XXXXXX)"
socket_dir="$cluster_dir/socket"
mkdir -p "$socket_dir"

cleanup() {
  "$pg_bin/pg_ctl" -D "$cluster_dir/data" -m fast stop >/dev/null 2>&1 || true
  rm -rf "$cluster_dir"
}
trap cleanup EXIT INT TERM

"$pg_bin/initdb" -A trust -U postgres -D "$cluster_dir/data" >/dev/null
"$pg_bin/pg_ctl" -D "$cluster_dir/data" -o "-F -p 55439 -k $socket_dir" -w start >/dev/null

database_url="postgresql://postgres@localhost:55439/postgres?host=$socket_dir"
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/bootstrap-plain-postgres.sql >/dev/null
for migration in supabase/migrations/*.sql; do
  "$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f supabase/seed.sql >/dev/null
seed_count="$("$pg_bin/psql" "$database_url" -Atc "select count(*) from public.transactions where user_id='10000000-0000-4000-8000-000000000001'")"
test "$seed_count" = "200"
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/ios-r1-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/web-r1-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/retention-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -v item_fixture="$(cat tests/fixtures/item-split-v1.json)" -f tests/database/planning-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -v receipt_fixture="$(cat tests/fixtures/receipt-split-v2.json)" -f tests/database/receipt-scan-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/goal-transactions-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/backdated-entries-smoke.sql
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 -f tests/database/product-readiness-smoke.sql
PATH="$pg_bin:$PATH" DATABASE_URL="$database_url" sh tests/database/concurrency.sh
"$pg_bin/psql" "$database_url" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set role authenticated;
select public.api_set_ai_consent(true,'2026-10-02');
select public.api_create_support_ticket('fa000000-0000-4000-8000-000000000001','lainnya','Backup sintetis untuk pemeriksaan restore','web','test');
SQL
"$pg_bin/pg_dump" --data-only --format=custom --no-owner "$database_url" -f "$cluster_dir/backup.dump"
restore_url="postgresql://postgres@localhost:55439/danarapi_restore?host=$socket_dir"
"$pg_bin/createdb" -h "$socket_dir" -p 55439 -U postgres danarapi_restore
sed '/^create role /d' tests/database/bootstrap-plain-postgres.sql | "$pg_bin/psql" "$restore_url" -v ON_ERROR_STOP=1 >/dev/null
for migration in supabase/migrations/*.sql; do
  "$pg_bin/psql" "$restore_url" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done
"$pg_bin/psql" "$restore_url" -v ON_ERROR_STOP=1 -c 'truncate storage.buckets cascade' >/dev/null
"$pg_bin/pg_restore" --data-only --disable-triggers --no-owner --exit-on-error -d "$restore_url" "$cluster_dir/backup.dump"
fingerprint_sql="select md5(string_agg(payload, '|' order by payload)) from (
  select jsonb_build_object('table', 'accounts', 'row', to_jsonb(source))::text payload from public.accounts source
  union all select jsonb_build_object('table', 'transactions', 'row', to_jsonb(source))::text from public.transactions source
  union all select jsonb_build_object('table', 'ledger_entries', 'row', to_jsonb(source))::text from public.ledger_entries source
  union all select jsonb_build_object('table', 'overview', 'row', to_jsonb(source))::text from public.financial_overview source
  union all select jsonb_build_object('table', 'consent', 'row', to_jsonb(source))::text from public.ai_consents source
  union all select jsonb_build_object('table', 'support', 'row', to_jsonb(source))::text from public.support_tickets source
) records"
original_fingerprint="$("$pg_bin/psql" "$database_url" -Atc "$fingerprint_sql")"
restored_fingerprint="$("$pg_bin/psql" "$restore_url" -Atc "$fingerprint_sql")"
test "$original_fingerprint" = "$restored_fingerprint"
"$pg_bin/psql" "$restore_url" -v ON_ERROR_STOP=1 -f tests/database/retention-smoke.sql >/dev/null
echo "Synthetic database backup/restore passed: accounts, transactions, ledger, overview, consent and support fingerprints match; retention/RLS passed after restore."
