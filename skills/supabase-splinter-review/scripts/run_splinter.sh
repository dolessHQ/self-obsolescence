#!/usr/bin/env bash
set -euo pipefail

SPLINTER_URL="${SPLINTER_URL:-https://raw.githubusercontent.com/supabase/splinter/refs/heads/main/splinter.sql}"
OUT_DIR="${1:-.splinter}"
mkdir -p "$OUT_DIR"

if ! command -v supabase >/dev/null 2>&1; then
  echo "error: supabase CLI is required" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "error: psql is required" >&2
  exit 1
fi

ENV_BLOCK="$(supabase status -o env 2>/dev/null || true)"
DB_URL="$(printf '%s\n' "$ENV_BLOCK" | sed -n 's/^DB_URL=//p' | tr -d '"')"

# Local Supabase default DB URL fallback.
if [[ -z "$DB_URL" ]]; then
  DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
fi

SPLINTER_SQL_PATH="$OUT_DIR/splinter.sql"
RESULTS_CSV_PATH="$OUT_DIR/splinter_results.csv"
META_PATH="$OUT_DIR/run_metadata.txt"

curl -fsSL "$SPLINTER_URL" -o "$SPLINTER_SQL_PATH"

# --csv keeps output structured for downstream review steps.
psql "$DB_URL" -v ON_ERROR_STOP=1 --csv -f "$SPLINTER_SQL_PATH" > "$RESULTS_CSV_PATH"

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "db_url=$DB_URL"
  echo "splinter_url=$SPLINTER_URL"
  echo "results_csv=$RESULTS_CSV_PATH"
} > "$META_PATH"

echo "Splinter run complete"
echo "CSV:  $RESULTS_CSV_PATH"
echo "Meta: $META_PATH"
