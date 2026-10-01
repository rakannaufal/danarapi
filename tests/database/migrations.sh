#!/bin/sh
set -eu
supabase db reset --local
supabase test db
DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}" sh tests/database/concurrency.sh
