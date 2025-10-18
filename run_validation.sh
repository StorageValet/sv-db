#!/usr/bin/env bash
# Storage Valet — Migrations Path Fix + Validation Runner (0003 + 0004)

set -euo pipefail

# Paths
SV_DB_DIR="${SV_DB_DIR:-$HOME/code/sv-db}"
SRC_MIG_DIR="$SV_DB_DIR/migrations"
DST_MIG_DIR="$SV_DB_DIR/supabase/migrations"
VALIDATOR="$SV_DB_DIR/scripts/validate_migration_0004.sh"

# Supabase project ref (staging)
export SUPABASE_PROJECT_REF="${SUPABASE_PROJECT_REF:-gmjucacmbrumncfnnhua}"

echo "📁 Using sv-db at: $SV_DB_DIR"
mkdir -p "$DST_MIG_DIR"

# 1) Copy migrations 0003 + 0004 into supabase/migrations if needed
copy_if_needed () {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then
    echo "❌ Missing expected migration: $src"
    exit 1
  fi
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "• Unchanged: $(basename "$dst")"
  else
    cp "$src" "$dst"
    echo "• Copied: $(basename "$src") → supabase/migrations/"
  fi
}

echo "🗂️  Synchronizing migrations → supabase/migrations/"
copy_if_needed "$SRC_MIG_DIR/0003_item_req_insurance_qr.sql" \
               "$DST_MIG_DIR/0003_item_req_insurance_qr.sql"
copy_if_needed "$SRC_MIG_DIR/0004_phase1_inventory_enhancements.sql" \
               "$DST_MIG_DIR/0004_phase1_inventory_enhancements.sql"

# 2) Ensure psql on PATH (assumes libpq already installed)
if ! command -v psql >/dev/null 2>&1; then
  echo "❌ psql not found on PATH. Install libpq (psql) and retry."
  exit 1
fi
echo "✅ psql: $(psql --version)"

# 3) Build SUPABASE_DB_URL if not set (prompt & URL-encode password)
if [ -z "${SUPABASE_DB_URL:-}" ]; then
  echo "🔐 Enter your Supabase Postgres password (hidden):"
  SUPABASE_DB_URL="$(python3 - "$SUPABASE_PROJECT_REF" <<'PY'
import sys, urllib.parse, getpass
ref = sys.argv[1]
pw = getpass.getpass('')
print(f"postgresql://postgres:{urllib.parse.quote(pw, safe='')}@db.{ref}.supabase.co:5432/postgres?sslmode=require")
PY
)"
  export SUPABASE_DB_URL
fi

# 4) Run the validator
if [ ! -x "$VALIDATOR" ]; then
  chmod +x "$VALIDATOR"
fi

echo "▶️  Running Migration 0004 validation…"
"$VALIDATOR"

echo ""
echo "🎉 DONE — If you saw GO ✅ above, proceed with Sprint 1 UI."
