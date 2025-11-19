-- Migration 0013: Add booking_events audit table
-- Date: 2025-11-12
-- Purpose: Audit trail for booking lifecycle events (webhooks, item updates, status changes)
--
-- Provides observability and debugging for:
-- - Calendly webhook deliveries
-- - Item selection/modification
-- - Status transitions
-- - Cancellations and errors

-- ============================================================================
-- PART 1: CREATE booking_events TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.booking_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_id uuid REFERENCES public.actions(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.booking_events IS
  'Audit trail for booking lifecycle events. Tracks webhooks, item updates, status changes, errors.';

COMMENT ON COLUMN public.booking_events.action_id IS
  'FK to actions table. NULL allowed for events without associated booking (e.g., webhook errors).';

COMMENT ON COLUMN public.booking_events.event_type IS
  'Event type: created, calendly_webhook, items_added, status_changed, canceled, error, etc.';

COMMENT ON COLUMN public.booking_events.metadata IS
  'Arbitrary event data (webhook payload excerpt, error details, item IDs, etc.)';

-- ============================================================================
-- PART 2: ADD INDEXES FOR PERFORMANCE
-- ============================================================================

-- Index for querying events by action_id (most common query pattern)
CREATE INDEX IF NOT EXISTS idx_booking_events_action_id
  ON public.booking_events (action_id);

COMMENT ON INDEX idx_booking_events_action_id IS
  'Performance: Fast lookup of all events for a given booking';

-- Index for querying recent events by type (ops dashboard use case)
CREATE INDEX IF NOT EXISTS idx_booking_events_type_created
  ON public.booking_events (event_type, created_at DESC);

COMMENT ON INDEX idx_booking_events_type_created IS
  'Performance: Fast lookup of recent events by type (e.g., last 100 errors)';

-- ============================================================================
-- PART 3: ENABLE RLS AND CREATE POLICIES
-- ============================================================================

-- Enable RLS (users can only see events for their own bookings)
ALTER TABLE public.booking_events ENABLE ROW LEVEL SECURITY;

-- Policy: Users can SELECT their own booking events
CREATE POLICY p_booking_events_owner_select ON public.booking_events
  FOR SELECT
  USING (
    action_id IS NULL  -- Allow viewing orphan events (webhook errors)
    OR
    EXISTS (
      SELECT 1 FROM public.actions
      WHERE actions.id = booking_events.action_id
        AND actions.user_id = auth.uid()
    )
  );

COMMENT ON POLICY p_booking_events_owner_select ON public.booking_events IS
  'Users can view events for their own bookings, or orphan events (no action_id)';

-- No INSERT/UPDATE/DELETE policies for users (service_role only)
-- Events are created by edge functions using service_role

-- ============================================================================
-- PART 4: CREATE HELPER FUNCTION FOR LOGGING EVENTS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.log_booking_event(
  p_action_id uuid,
  p_event_type text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
SECURITY DEFINER  -- Runs with function owner's privileges (bypasses RLS)
SET search_path = public, pg_temp
LANGUAGE plpgsql
AS $$
DECLARE
  v_event_id uuid;
BEGIN
  INSERT INTO public.booking_events (action_id, event_type, metadata)
  VALUES (p_action_id, p_event_type, p_metadata)
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

COMMENT ON FUNCTION public.log_booking_event IS
  'SECURITY DEFINER: Logs booking event. Callable by edge functions to bypass RLS. Returns event ID.';

-- Grant execute to authenticated users (edge functions run as authenticated, not anon)
GRANT EXECUTE ON FUNCTION public.log_booking_event TO authenticated, service_role;
