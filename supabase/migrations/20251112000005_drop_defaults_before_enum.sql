-- ============================================================================
-- MIGRATION: Drop defaults before enum type changes (bootstrap fix)
-- Created: 2025-11-12 (backfilled for ordering) • Auth: CTO directive
-- Purpose: Ensure 20251112000006 can ALTER TYPE without default-cast failures during local reset
-- ============================================================================

DO $
BEGIN
  -- Only relevant if these columns are still text/varchar (i.e., before 0006 runs)
  -- Drop defaults so subsequent ALTER TYPE in 0006 doesn't fail.

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='items' AND column_name='status'
      AND data_type IN ('text', 'character varying')
  ) THEN
    EXECUTE 'ALTER TABLE public.items ALTER COLUMN status DROP DEFAULT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='actions' AND column_name='status'
      AND data_type IN ('text', 'character varying')
  ) THEN
    EXECUTE 'ALTER TABLE public.actions ALTER COLUMN status DROP DEFAULT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='customer_profile' AND column_name='subscription_status'
      AND data_type IN ('text', 'character varying')
  ) THEN
    EXECUTE 'ALTER TABLE public.customer_profile ALTER COLUMN subscription_status DROP DEFAULT';
  END IF;
END $;
