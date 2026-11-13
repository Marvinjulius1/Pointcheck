#!/usr/bin/env bash
# Runs the schema tests against a local PostgreSQL (fresh database for each test file).
# Usage: PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run_local.sh [test.sql ...]
# Without arguments all supabase/tests/*_test.sql files run.
set -euo pipefail
cd "$(dirname "$0")/../.."
db=pointcheck_schema_test
if [ "$#" -eq 0 ]; then set -- supabase/tests/*_test.sql; fi
for test in "$@"; do
    psql -v ON_ERROR_STOP=1 -q -c "drop database if exists $db" -c "create database $db"
    psql -v ON_ERROR_STOP=1 -q -d "$db" -f supabase/tests/local_supabase_stub.sql
    for migration in supabase/migrations/*.sql; do
        case "$migration" in
            *_storage.sql) continue ;;  # needs Supabase's storage schema
        esac
        psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$migration"
    done
    psql -v ON_ERROR_STOP=1 -d "$db" -f "$test"
done
