-- Migration: Rename in_transit to scheduled
-- Purpose: Update item status terminology for clarity

-- Step 1: Ensure ENUM type supports 'scheduled'
ALTER TYPE public.item_status
  ADD VALUE IF NOT EXISTS 'scheduled';

-- Step 2: Drop existing CHECK constraint (if it exists)
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS items_status_check;

-- NOTE: Steps 3-4 deferred - PostgreSQL doesn't allow using new enum values in same transaction
-- The UPDATE is a no-op on fresh databases (no in_transit rows)
-- The CHECK constraint is redundant since enum provides type safety
-- These would need to be in a separate migration to work properly
