#!/usr/bin/env bash
# Runs the schema tests against a local PostgreSQL (fresh database each time).
# Usage: PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run_local.sh [test.sql]
set -euo pipefail
cd "$(dirname "$0")/../.."
db=pointcheck_schema_test
psql -v ON_ERROR_STOP=1 -q -c "drop database if exists $db" -c "create database $db"
psql -v ON_ERROR_STOP=1 -q -d "$db" -f supabase/tests/local_supabase_stub.sql
for migration in supabase/migrations/*.sql; do
    case "$migration" in
        *_storage.sql) continue ;;  # needs Supabase's storage schema
    esac
    psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$migration"
done
psql -v ON_ERROR_STOP=1 -d "$db" -f "${1:-supabase/tests/schema_test.sql}"
