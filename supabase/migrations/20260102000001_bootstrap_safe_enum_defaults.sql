-- ============================================================================
-- MIGRATION: Bootstrap-Safe Enum Defaults
-- Created: 2026-01-02
-- Purpose: Ensure enum columns can be altered during local bootstrap (db reset)
--
-- CONTEXT: The original migration 20251112000006 works on fresh production
-- but fails during local `supabase db reset` because PostgreSQL cannot
-- alter a column's type while a default constraint exists.
--
-- This migration is a NO-OP on production (columns already have correct types)
-- but enables clean local bootstrap by ensuring defaults are properly set.
-- ============================================================================

-- Idempotent: Only runs if enum types already exist (they do in production)
DO $$
BEGIN
  -- Ensure items.status has correct default (idempotent)
  IF EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'item_status'
  ) THEN
    -- Drop and re-add default to ensure clean state
    ALTER TABLE public.items ALTER COLUMN status DROP DEFAULT;
    ALTER TABLE public.items ALTER COLUMN status SET DEFAULT 'home'::public.item_status;
  END IF;

  -- Ensure actions.status has correct default (idempotent)
  IF EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'action_status'
  ) THEN
    ALTER TABLE public.actions ALTER COLUMN status DROP DEFAULT;
    ALTER TABLE public.actions ALTER COLUMN status SET DEFAULT 'pending'::public.action_status;
  END IF;

  -- Ensure customer_profile.subscription_status has correct default (idempotent)
  IF EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'subscription_status_enum'
  ) THEN
    ALTER TABLE public.customer_profile ALTER COLUMN subscription_status DROP DEFAULT;
    ALTER TABLE public.customer_profile ALTER COLUMN subscription_status SET DEFAULT 'inactive'::public.subscription_status_enum;
  END IF;
END $$;

-- ============================================================================
-- VERIFICATION (no-op, just documents expected state)
-- ============================================================================
-- After this migration:
-- - items.status: item_status enum, default 'home'
-- - actions.status: action_status enum, default 'pending'
-- - customer_profile.subscription_status: subscription_status_enum, default 'inactive'
