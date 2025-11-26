-- Migration 0014: Fix missing unique index on actions.calendly_event_uri
-- Date: 2025-11-18
-- Purpose: Add missing unique constraint that should have been created by migration 0012
--
-- Issue: Migration 0012 created the calendly_event_uri column but the unique index
--        was not properly applied, causing webhook upserts to fail with:
--        "no unique or exclusion constraint matching the ON CONFLICT specification"
--
-- This is a forward-only fix to add the missing index without rerunning full migration 0012

-- Create unique index for Calendly webhook idempotency (idempotent)
CREATE UNIQUE INDEX IF NOT EXISTS ux_actions_calendly_event_uri
  ON public.actions (calendly_event_uri)
  WHERE calendly_event_uri IS NOT NULL;

COMMENT ON INDEX ux_actions_calendly_event_uri IS
  'Idempotency: Prevents duplicate actions from Calendly webhook retries. Required for ON CONFLICT (calendly_event_uri) upsert.';
