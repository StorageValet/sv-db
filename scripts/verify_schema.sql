-- Quick schema verification queries for Migration 0004

\echo '==> Checking new columns in items table:'
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='items'
  AND column_name IN ('photo_paths','status','category','physical_locked_at')
ORDER BY column_name;

\echo ''
\echo '==> Checking items.status constraint:'
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON t.oid=c.conrelid
JOIN pg_namespace n ON n.oid=t.relnamespace
WHERE n.nspname='public' AND t.relname='items' AND conname LIKE '%status%check%';

\echo ''
\echo '==> Checking actions.item_ids column:'
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='actions' AND column_name='item_ids';

\echo ''
\echo '==> Checking inventory_events table:'
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema='public' AND table_name='inventory_events'
) THEN 'EXISTS ✓' ELSE 'MISSING ✗' END AS status;

\echo ''
\echo '==> Checking new indexes:'
SELECT indexname
FROM pg_indexes
WHERE schemaname='public'
  AND indexname IN (
    'idx_items_status',
    'idx_items_category',
    'idx_items_photo_paths_gin',
    'idx_actions_item_ids_gin',
    'idx_inventory_events_item_id_created'
  )
ORDER BY indexname;

\echo ''
\echo '==> Checking RLS policies on inventory_events:'
SELECT policyname
FROM pg_policies
WHERE schemaname='public' AND tablename='inventory_events'
ORDER BY policyname;
