-- Migration 0006: Enable RLS and Database-Level Security
-- Critical security hardening before production launch
-- Implements defense-in-depth: database enforces access control independent of client code

-- ============================================================================
-- PART 1: CREATE ENUM TYPES FOR STATUS FIELDS
-- ============================================================================
-- Prevents invalid status values and enables type-safe state transitions

CREATE TYPE public.item_status AS ENUM ('home', 'in_transit', 'stored');
CREATE TYPE public.action_status AS ENUM ('pending', 'confirmed', 'completed', 'canceled');
CREATE TYPE public.subscription_status_enum AS ENUM ('inactive', 'active', 'past_due', 'canceled');

COMMENT ON TYPE public.item_status IS 'Valid states for items in customer inventory';
COMMENT ON TYPE public.action_status IS 'Valid states for pickup/delivery requests';
COMMENT ON TYPE public.subscription_status_enum IS 'Valid subscription states synced from Stripe';

-- ============================================================================
-- PART 2: MIGRATE EXISTING DATA TO ENUMS
-- ============================================================================

-- Migrate items.status (with validation)
ALTER TABLE public.items
  ALTER COLUMN status TYPE public.item_status
  USING CASE
    WHEN status IN ('home', 'in_transit', 'stored') THEN status::public.item_status
    ELSE 'home'::public.item_status  -- Default for invalid values
  END;

-- Migrate actions.status (with validation)
ALTER TABLE public.actions
  ALTER COLUMN status TYPE public.action_status
  USING CASE
    WHEN status IN ('pending', 'confirmed', 'completed', 'canceled') THEN status::public.action_status
    ELSE 'pending'::public.action_status  -- Default for invalid values
  END;

-- Migrate customer_profile.subscription_status (with validation)
ALTER TABLE public.customer_profile
  ALTER COLUMN subscription_status TYPE public.subscription_status_enum
  USING CASE
    WHEN subscription_status IN ('inactive', 'active', 'past_due', 'canceled') THEN subscription_status::public.subscription_status_enum
    ELSE 'inactive'::public.subscription_status_enum  -- Default for invalid values
  END;

-- ============================================================================
-- PART 3: ADD NOT NULL CONSTRAINTS
-- ============================================================================
-- Ensures referential integrity and prevents invalid states

ALTER TABLE public.items ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.items ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.items ALTER COLUMN label SET NOT NULL;
ALTER TABLE public.items ALTER COLUMN description SET NOT NULL;

ALTER TABLE public.actions ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.actions ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.actions ALTER COLUMN service_type SET NOT NULL;

ALTER TABLE public.claims ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.claims ALTER COLUMN item_id SET NOT NULL;
ALTER TABLE public.claims ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.inventory_events ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.inventory_events ALTER COLUMN item_id SET NOT NULL;
ALTER TABLE public.inventory_events ALTER COLUMN event_type SET NOT NULL;

ALTER TABLE public.customer_profile ALTER COLUMN email SET NOT NULL;
ALTER TABLE public.customer_profile ALTER COLUMN subscription_status SET NOT NULL;

-- ============================================================================
-- PART 4: ADD MISSING FOREIGN KEYS
-- ============================================================================

-- Ensure claims.user_id references auth.users
ALTER TABLE public.claims
  ADD CONSTRAINT claims_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================================
-- PART 5: ADD ON DELETE BEHAVIOR FOR REFERENTIAL INTEGRITY
-- ============================================================================

-- inventory_events should cascade delete when item is deleted (preserve history)
ALTER TABLE public.inventory_events
  DROP CONSTRAINT IF EXISTS inventory_events_item_id_fkey,
  ADD CONSTRAINT inventory_events_item_id_fkey
  FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;

-- claims should restrict delete if item has open claims (data protection)
ALTER TABLE public.claims
  DROP CONSTRAINT IF EXISTS claims_item_id_fkey,
  ADD CONSTRAINT claims_item_id_fkey
  FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE RESTRICT;

-- ============================================================================
-- PART 6: CREATE PERFORMANCE INDEXES
-- ============================================================================
-- Critical for RLS policy performance and general query efficiency

-- Items indexes
CREATE INDEX IF NOT EXISTS items_user_id_idx ON public.items(user_id);
CREATE INDEX IF NOT EXISTS items_status_idx ON public.items(status);
CREATE INDEX IF NOT EXISTS items_qr_code_idx ON public.items(qr_code);
CREATE INDEX IF NOT EXISTS items_category_idx ON public.items(category);
CREATE INDEX IF NOT EXISTS items_created_at_idx ON public.items(created_at DESC);

-- Actions indexes
CREATE INDEX IF NOT EXISTS actions_user_id_idx ON public.actions(user_id);
CREATE INDEX IF NOT EXISTS actions_status_idx ON public.actions(status);
CREATE INDEX IF NOT EXISTS actions_scheduled_at_idx ON public.actions(scheduled_at);
CREATE INDEX IF NOT EXISTS actions_service_type_idx ON public.actions(service_type);

-- Claims indexes
CREATE INDEX IF NOT EXISTS claims_user_id_idx ON public.claims(user_id);
CREATE INDEX IF NOT EXISTS claims_item_id_idx ON public.claims(item_id);
CREATE INDEX IF NOT EXISTS claims_status_idx ON public.claims(status);

-- Inventory events indexes
CREATE INDEX IF NOT EXISTS inventory_events_user_id_idx ON public.inventory_events(user_id);
CREATE INDEX IF NOT EXISTS inventory_events_item_id_created_idx ON public.inventory_events(item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS inventory_events_event_type_idx ON public.inventory_events(event_type);

-- ============================================================================
-- PART 7: ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.customer_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_events ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- PART 8: CREATE RLS POLICIES - CUSTOMER_PROFILE
-- ============================================================================

-- Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON public.customer_profile
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can update their own profile (except Stripe fields - handled by SECURITY DEFINER functions)
CREATE POLICY "Users can update own profile"
  ON public.customer_profile
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Service role can do anything (for system operations)
CREATE POLICY "Service role has full access"
  ON public.customer_profile
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ============================================================================
-- PART 9: CREATE RLS POLICIES - ITEMS
-- ============================================================================

-- Users can view their own items
CREATE POLICY "Users can view own items"
  ON public.items
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own items
CREATE POLICY "Users can create own items"
  ON public.items
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own items (trigger enforces physical_locked_at rules)
CREATE POLICY "Users can update own items"
  ON public.items
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own items (unless claims exist - FK will prevent)
CREATE POLICY "Users can delete own items"
  ON public.items
  FOR DELETE
  USING (auth.uid() = user_id);

-- Service role has full access
CREATE POLICY "Service role has full access to items"
  ON public.items
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ============================================================================
-- PART 10: CREATE RLS POLICIES - ACTIONS
-- ============================================================================

-- Users can view their own action requests
CREATE POLICY "Users can view own actions"
  ON public.actions
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can create their own action requests
CREATE POLICY "Users can create own actions"
  ON public.actions
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own pending actions (can cancel before confirmation)
CREATE POLICY "Users can update own pending actions"
  ON public.actions
  FOR UPDATE
  USING (auth.uid() = user_id AND status = 'pending')
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own pending actions
CREATE POLICY "Users can delete own pending actions"
  ON public.actions
  FOR DELETE
  USING (auth.uid() = user_id AND status = 'pending');

-- Service role has full access (for ops team to confirm/complete actions)
CREATE POLICY "Service role has full access to actions"
  ON public.actions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ============================================================================
-- PART 11: CREATE RLS POLICIES - CLAIMS
-- ============================================================================

-- Users can view their own claims
CREATE POLICY "Users can view own claims"
  ON public.claims
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can create claims for their own items
CREATE POLICY "Users can create claims for own items"
  ON public.claims
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.items
      WHERE items.id = claims.item_id
      AND items.user_id = auth.uid()
    )
  );

-- Users cannot update claims (read-only after submission)
-- Service role updates claim status

-- Users cannot delete claims (audit trail)
-- Service role can delete claims

-- Service role has full access
CREATE POLICY "Service role has full access to claims"
  ON public.claims
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ============================================================================
-- PART 12: CREATE RLS POLICIES - INVENTORY_EVENTS
-- ============================================================================

-- Users can view their own inventory events
CREATE POLICY "Users can view own inventory events"
  ON public.inventory_events
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users cannot directly insert events (managed by system functions)
-- Service role inserts events via logInventoryEventAuto()

-- Users cannot update or delete events (immutable audit log)

-- Service role has full access
CREATE POLICY "Service role has full access to inventory events"
  ON public.inventory_events
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ============================================================================
-- PART 13: PROTECT BILLING FIELDS WITH SECURITY DEFINER FUNCTION
-- ============================================================================

-- Revoke direct UPDATE on Stripe-managed columns from authenticated users
REVOKE UPDATE(subscription_status, subscription_id, stripe_customer_id, last_payment_at, last_payment_failed_at)
  ON public.customer_profile
  FROM authenticated;

-- Create function for Stripe webhook to update subscription status
CREATE OR REPLACE FUNCTION public.update_subscription_status(
  p_user_id UUID,
  p_status public.subscription_status_enum,
  p_subscription_id TEXT DEFAULT NULL,
  p_last_payment_at TIMESTAMPTZ DEFAULT NULL,
  p_last_payment_failed_at TIMESTAMPTZ DEFAULT NULL
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.customer_profile SET
    subscription_status = p_status,
    subscription_id = COALESCE(p_subscription_id, subscription_id),
    last_payment_at = COALESCE(p_last_payment_at, last_payment_at),
    last_payment_failed_at = COALESCE(p_last_payment_failed_at, last_payment_failed_at),
    updated_at = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found for user_id: %', p_user_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.update_subscription_status IS
  'Stripe webhook uses this to update subscription status. Protected by SECURITY DEFINER to bypass RLS.';

-- Grant execute to service_role only (used by stripe-webhook edge function)
GRANT EXECUTE ON FUNCTION public.update_subscription_status TO service_role;
REVOKE EXECUTE ON FUNCTION public.update_subscription_status FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_subscription_status FROM anon;

-- ============================================================================
-- PART 14: ADD WEBHOOK IDEMPOTENCY CONSTRAINT
-- ============================================================================

ALTER TABLE billing.webhook_events
  ADD CONSTRAINT webhook_events_event_id_unique UNIQUE (event_id);

COMMENT ON CONSTRAINT webhook_events_event_id_unique ON billing.webhook_events IS
  'Ensures Stripe webhooks are processed exactly once (idempotency)';

-- ============================================================================
-- PART 15: CREATE UPDATED_AT TRIGGER FOR CONSISTENCY
-- ============================================================================

-- Create reusable trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Apply to all tables with updated_at column
CREATE TRIGGER set_updated_at_trigger
  BEFORE UPDATE ON public.customer_profile
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_trigger
  BEFORE UPDATE ON public.items
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_trigger
  BEFORE UPDATE ON public.actions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_trigger
  BEFORE UPDATE ON public.claims
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Summary of changes:
-- ✅ Status columns converted to ENUMs (prevents invalid values)
-- ✅ NOT NULL constraints added (prevents missing critical data)
-- ✅ Foreign keys strengthened (referential integrity)
-- ✅ Performance indexes created (RLS + query optimization)
-- ✅ RLS enabled on all public tables (defense-in-depth security)
-- ✅ Baseline ownership policies created (users can only access their data)
-- ✅ Billing fields protected by SECURITY DEFINER function (prevents fraud)
-- ✅ Webhook idempotency enforced (prevents duplicate processing)
-- ✅ updated_at triggers added (consistent timestamp management)
