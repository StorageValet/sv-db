-- Billing v2: Add trial and cancellation tracking columns
-- These columns store projections from Stripe subscription state
-- Migration created retroactively to ensure reproducibility
-- Production columns added: January 7, 2026

-- ============================================================
-- PART 1: Schema additions to customer_profile
-- ============================================================

ALTER TABLE public.customer_profile
ADD COLUMN IF NOT EXISTS trial_end_at TIMESTAMPTZ;

ALTER TABLE public.customer_profile
ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN DEFAULT false;

ALTER TABLE public.customer_profile
ADD COLUMN IF NOT EXISTS cancel_at TIMESTAMPTZ;

ALTER TABLE public.customer_profile
ADD COLUMN IF NOT EXISTS billing_version TEXT;

-- Index for querying trial users (partial index for efficiency)
CREATE INDEX IF NOT EXISTS idx_customer_profile_billing_version
ON public.customer_profile(billing_version)
WHERE billing_version IS NOT NULL;

-- Column documentation
COMMENT ON COLUMN public.customer_profile.trial_end_at IS 'Trial end timestamp from Stripe subscription.trial_end';
COMMENT ON COLUMN public.customer_profile.cancel_at_period_end IS 'True if user canceled but access continues until period end';
COMMENT ON COLUMN public.customer_profile.cancel_at IS 'Timestamp when subscription will be canceled (from Stripe)';
COMMENT ON COLUMN public.customer_profile.billing_version IS 'Billing model version: v2_trial_14d for trial signups';

-- ============================================================
-- PART 2: Extend update_subscription_status RPC for Billing v2
-- ============================================================
-- Adds optional parameters for trial and cancellation tracking
-- All new params are optional with DEFAULT NULL for backward compatibility

CREATE OR REPLACE FUNCTION public.update_subscription_status(
  p_user_id UUID,
  p_status subscription_status,
  p_subscription_id TEXT DEFAULT NULL,
  -- New v2 parameters (all optional for backward compatibility)
  p_trial_end_at TIMESTAMPTZ DEFAULT NULL,
  p_cancel_at_period_end BOOLEAN DEFAULT NULL,
  p_cancel_at TIMESTAMPTZ DEFAULT NULL,
  p_billing_version TEXT DEFAULT NULL,
  -- Existing optional parameters
  p_last_payment_at TIMESTAMPTZ DEFAULT NULL,
  p_last_payment_failed_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.customer_profile
  SET
    subscription_status = p_status,
    subscription_id = COALESCE(p_subscription_id, subscription_id),
    last_payment_at = COALESCE(p_last_payment_at, last_payment_at),
    last_payment_failed_at = COALESCE(p_last_payment_failed_at, last_payment_failed_at),
    -- v2 columns (COALESCE preserves existing values when NULL)
    trial_end_at = COALESCE(p_trial_end_at, trial_end_at),
    cancel_at_period_end = COALESCE(p_cancel_at_period_end, cancel_at_period_end),
    cancel_at = COALESCE(p_cancel_at, cancel_at),
    billing_version = COALESCE(p_billing_version, billing_version),
    updated_at = NOW()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found for user_id: %', p_user_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.update_subscription_status IS
  'SECURITY DEFINER function for webhook to update subscription state. Extended for Billing v2 trial support (January 2026).';
