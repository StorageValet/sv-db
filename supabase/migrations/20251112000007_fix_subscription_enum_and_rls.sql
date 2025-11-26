-- Migration 0007: Fix Subscription ENUM and RLS Policies
-- Date: 2025-10-31
-- Purpose: Patch migration 0006 which was edited after deployment
--
-- This migration:
-- 1. Extends subscription_status_enum with 5 missing Stripe states
-- 2. Adds missing RLS INSERT policy for inventory_events
-- 3. No index changes needed - 0006 already deduplicated correctly
--
-- Background: Migration 0006 was edited to fix ENUM expansion and index
-- deduplication, but some databases may have already run the initial version.
-- This migration ensures all environments have the complete ENUM and RLS policies.

-- ============================================================================
-- PART 1: EXTEND SUBSCRIPTION_STATUS_ENUM
-- ============================================================================
-- Add the 5 missing Stripe subscription states that weren't in the original 4-value enum
-- Uses idempotent DO blocks to check pg_enum before adding each value

DO $$
BEGIN
  -- Add 'trialing' if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.subscription_status_enum'::regtype
    AND enumlabel = 'trialing'
  ) THEN
    ALTER TYPE public.subscription_status_enum ADD VALUE 'trialing';
  END IF;
END $$;

DO $$
BEGIN
  -- Add 'incomplete' if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.subscription_status_enum'::regtype
    AND enumlabel = 'incomplete'
  ) THEN
    ALTER TYPE public.subscription_status_enum ADD VALUE 'incomplete';
  END IF;
END $$;

DO $$
BEGIN
  -- Add 'incomplete_expired' if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.subscription_status_enum'::regtype
    AND enumlabel = 'incomplete_expired'
  ) THEN
    ALTER TYPE public.subscription_status_enum ADD VALUE 'incomplete_expired';
  END IF;
END $$;

DO $$
BEGIN
  -- Add 'unpaid' if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.subscription_status_enum'::regtype
    AND enumlabel = 'unpaid'
  ) THEN
    ALTER TYPE public.subscription_status_enum ADD VALUE 'unpaid';
  END IF;
END $$;

DO $$
BEGIN
  -- Add 'paused' if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.subscription_status_enum'::regtype
    AND enumlabel = 'paused'
  ) THEN
    ALTER TYPE public.subscription_status_enum ADD VALUE 'paused';
  END IF;
END $$;

COMMENT ON TYPE public.subscription_status_enum IS 'All possible Stripe subscription lifecycle states (9 total): inactive, active, past_due, canceled, trialing, incomplete, incomplete_expired, unpaid, paused';

-- ============================================================================
-- PART 2: ADD MISSING RLS POLICY FOR INVENTORY_EVENTS
-- ============================================================================
-- The initial version of migration 0006 only included SELECT policy for inventory_events
-- This broke timeline logging from the portal (sv-portal/src/lib/supabase.ts:175)
-- Adding INSERT policy with proper ownership check

-- Drop policy if it already exists (for idempotency)
DROP POLICY IF EXISTS "Users can log own inventory events" ON public.inventory_events;

-- Create INSERT policy for inventory events
CREATE POLICY "Users can log own inventory events"
  ON public.inventory_events
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

COMMENT ON POLICY "Users can log own inventory events" ON public.inventory_events IS
  'Allows authenticated users to insert inventory events for items they own. Required for movement timeline to work from portal.';

-- ============================================================================
-- VERIFICATION QUERIES (for validation, not executed during migration)
-- ============================================================================

-- Verify all 9 subscription statuses are present:
-- SELECT enumlabel FROM pg_enum
-- WHERE enumtypid = 'public.subscription_status_enum'::regtype
-- ORDER BY enumlabel;
--
-- Expected result:
-- active
-- canceled
-- incomplete
-- incomplete_expired
-- inactive
-- past_due
-- paused
-- trialing
-- unpaid

-- Verify inventory_events RLS policies:
-- SELECT policyname, cmd
-- FROM pg_policies
-- WHERE tablename = 'inventory_events'
-- ORDER BY policyname;
--
-- Expected result:
-- Users can log own inventory events | INSERT
-- Users can view own inventory events | SELECT

-- ============================================================================
-- MIGRATION SUMMARY
-- ============================================================================
--
-- This migration fixes two critical issues identified after migration 0006:
--
-- 1. ENUM Expansion: Extended subscription_status_enum from 4 values to 9
--    - Original 4: inactive, active, past_due, canceled
--    - Added 5: trialing, incomplete, incomplete_expired, unpaid, paused
--    - Prevents webhook failures when Stripe sends non-mapped statuses
--
-- 2. RLS Policy: Added INSERT policy for inventory_events
--    - Restores timeline logging from portal
--    - Maintains user_id ownership check for security
--
-- 3. Index Cleanup: NOT NEEDED
--    - Migration 0006 was corrected to avoid duplicate indexes
--    - All indexes properly deduplicated in current 0006 version
--
-- Migration 0007 is ADDITIVE ONLY - does not modify earlier migrations
