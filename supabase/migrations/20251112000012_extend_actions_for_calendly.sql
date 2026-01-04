-- Migration 0012: Extend actions table for Calendly integration
-- Date: 2025-11-12
-- Purpose: Support schedule-first booking flow with Calendly webhooks
--
-- Changes:
-- 1. Extend action_status enum with new states for schedule-first flow
-- 2. Add Calendly-specific fields (event_uri, payload, scheduled_end)
-- 3. Add item selection fields (pickup_item_ids, delivery_item_ids)
-- 4. Add service_address snapshot field
-- 5. Add unique constraint for Calendly webhook idempotency

-- ============================================================================
-- PART 1: EXTEND action_status ENUM
-- ============================================================================
-- New workflow states:
-- - pending_items: Calendly event created, awaiting item selection
-- - pending_confirmation: Items selected, awaiting final confirmation
-- (Existing: confirmed, in_progress, completed, canceled)

-- Add new enum values to existing action_status type
ALTER TYPE public.action_status ADD VALUE IF NOT EXISTS 'pending_items';
ALTER TYPE public.action_status ADD VALUE IF NOT EXISTS 'pending_confirmation';
ALTER TYPE public.action_status ADD VALUE IF NOT EXISTS 'in_progress';

COMMENT ON TYPE public.action_status IS
  'Valid states for booking lifecycle: pending_items (awaiting item selection) → pending_confirmation (items selected) → confirmed (ops confirmed) → in_progress (service underway) → completed/canceled';

-- ============================================================================
-- PART 2: ADD CALENDLY INTEGRATION FIELDS
-- ============================================================================

-- Calendly event URI (unique identifier from Calendly API)
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS calendly_event_uri text;

COMMENT ON COLUMN public.actions.calendly_event_uri IS
  'Unique Calendly event identifier (e.g., https://api.calendly.com/scheduled_events/...). Used for webhook idempotency.';

-- Scheduled end time (Calendly provides start + end for appointment window)
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS scheduled_end timestamptz;

COMMENT ON COLUMN public.actions.scheduled_end IS
  'End time of scheduled service window from Calendly. Paired with scheduled_at (start time).';

-- Raw Calendly webhook payload (for debugging and audit trail)
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS calendly_payload jsonb;

COMMENT ON COLUMN public.actions.calendly_payload IS
  'Full Calendly webhook payload (invitee.created/canceled). Stored for debugging and audit.';

-- ============================================================================
-- PART 3: ADD ITEM SELECTION FIELDS
-- ============================================================================
-- Split item_ids into pickup vs delivery based on item status at selection time

-- Items to pick up from customer (status='home' at selection time)
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS pickup_item_ids uuid[] DEFAULT '{}';

COMMENT ON COLUMN public.actions.pickup_item_ids IS
  'Item IDs to pick up from customer location (items with status=home at selection time)';

-- Items to deliver to customer (status='stored' at selection time)
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS delivery_item_ids uuid[] DEFAULT '{}';

COMMENT ON COLUMN public.actions.delivery_item_ids IS
  'Item IDs to deliver to customer location (items with status=stored at selection time)';

-- ============================================================================
-- PART 4: ADD SERVICE ADDRESS SNAPSHOT
-- ============================================================================
-- Snapshot customer address at booking time (protects against mid-service address changes)

ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS service_address jsonb;

COMMENT ON COLUMN public.actions.service_address IS
  'Snapshot of customer delivery_address at booking creation time. Prevents mid-service address changes from affecting scheduled pickups/deliveries.';

-- ============================================================================
-- PART 5: ADD UNIQUE CONSTRAINT FOR CALENDLY IDEMPOTENCY
-- ============================================================================
-- Prevents duplicate action entries when Calendly webhooks are retried

CREATE UNIQUE INDEX IF NOT EXISTS ux_actions_calendly_event_uri
  ON public.actions (calendly_event_uri)
  WHERE calendly_event_uri IS NOT NULL;

COMMENT ON INDEX ux_actions_calendly_event_uri IS
  'Idempotency: Prevents duplicate actions from Calendly webhook retries';

-- ============================================================================
-- PART 6: ADD PERFORMANCE INDEXES
-- ============================================================================

-- Index for querying pending bookings by user and status
-- NOTE: Removed WHERE clause - can't use new enum values in same transaction as ALTER TYPE ADD VALUE
CREATE INDEX IF NOT EXISTS idx_actions_user_status
  ON public.actions (user_id, status);

COMMENT ON INDEX idx_actions_user_status IS
  'Performance: Fast lookup of bookings by user and status for dashboard display';

-- GIN index for efficient array overlap queries on pickup_item_ids
CREATE INDEX IF NOT EXISTS idx_actions_pickup_items_gin
  ON public.actions USING GIN (pickup_item_ids);

COMMENT ON INDEX idx_actions_pickup_items_gin IS
  'Performance: Fast queries for "which bookings include this item for pickup"';

-- GIN index for efficient array overlap queries on delivery_item_ids
CREATE INDEX IF NOT EXISTS idx_actions_delivery_items_gin
  ON public.actions USING GIN (delivery_item_ids);

COMMENT ON INDEX idx_actions_delivery_items_gin IS
  'Performance: Fast queries for "which bookings include this item for delivery"';
