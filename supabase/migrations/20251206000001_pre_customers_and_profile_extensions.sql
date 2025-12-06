-- Migration: Pre-customers table and customer_profile extensions
-- Purpose: Support data-first registration flow (form submission before Stripe checkout)
-- Date: December 6, 2025
-- Author: Claude Code (Opus 4.5) with GPT 5.1 Systems Architecture

-- =============================================================================
-- PHASE 1A: Create sv.pre_customers table
-- Captures form submissions BEFORE payment for complete customer data
-- =============================================================================

CREATE TABLE IF NOT EXISTS sv.pre_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL CHECK (email = lower(email)),
  first_name text NOT NULL,
  last_name text NOT NULL,
  phone text,
  street_address text,
  unit text,
  city text,
  state text DEFAULT 'NJ' NOT NULL,
  zip_code text NOT NULL,
  service_area_match boolean DEFAULT false NOT NULL,
  referral_source text,
  converted_at timestamptz,
  converted_user_id uuid REFERENCES auth.users(id),
  reminder_sent_at timestamptz,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,

  CONSTRAINT pre_customers_email_unique UNIQUE (email)
);

-- Trigger for updated_at (uses existing public.set_updated_at function)
DROP TRIGGER IF EXISTS t_set_updated_at_pre_customers ON sv.pre_customers;
CREATE TRIGGER t_set_updated_at_pre_customers
  BEFORE UPDATE ON sv.pre_customers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Indexes for pre_customers
CREATE INDEX IF NOT EXISTS idx_pre_customers_email ON sv.pre_customers (lower(email));
CREATE INDEX IF NOT EXISTS idx_pre_customers_zip ON sv.pre_customers (zip_code);
CREATE INDEX IF NOT EXISTS idx_pre_customers_unconverted ON sv.pre_customers (created_at)
  WHERE converted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_pre_customers_service_area ON sv.pre_customers (service_area_match);

-- RLS for pre_customers (service role only - this is backend data)
ALTER TABLE sv.pre_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access to pre_customers" ON sv.pre_customers;
CREATE POLICY "Service role full access to pre_customers"
  ON sv.pre_customers FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

COMMENT ON TABLE sv.pre_customers IS 'Pre-payment registration data from Framer form submissions';
COMMENT ON COLUMN sv.pre_customers.service_area_match IS 'True if ZIP code is in active service area at time of signup';
COMMENT ON COLUMN sv.pre_customers.converted_at IS 'Timestamp when customer completed Stripe checkout';
COMMENT ON COLUMN sv.pre_customers.converted_user_id IS 'auth.users.id after Stripe checkout creates the user';

-- =============================================================================
-- PHASE 1B: Create sv.signup_anomalies table
-- Logs edge cases for ops/dev review (checkout without form, mismatches, etc.)
-- =============================================================================

CREATE TABLE IF NOT EXISTS sv.signup_anomalies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text,
  stripe_customer_id text,
  stripe_subscription_id text,
  anomaly_type text NOT NULL,
  event_id text,
  raw_data jsonb,
  resolved_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now() NOT NULL
);

-- Indexes for signup_anomalies
CREATE INDEX IF NOT EXISTS idx_signup_anomalies_email ON sv.signup_anomalies (email);
CREATE INDEX IF NOT EXISTS idx_signup_anomalies_stripe_customer ON sv.signup_anomalies (stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_signup_anomalies_event ON sv.signup_anomalies (event_id);
CREATE INDEX IF NOT EXISTS idx_signup_anomalies_type ON sv.signup_anomalies (anomaly_type);
CREATE INDEX IF NOT EXISTS idx_signup_anomalies_unresolved ON sv.signup_anomalies (created_at)
  WHERE resolved_at IS NULL;

-- RLS for signup_anomalies (service role only)
ALTER TABLE sv.signup_anomalies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access to signup_anomalies" ON sv.signup_anomalies;
CREATE POLICY "Service role full access to signup_anomalies"
  ON sv.signup_anomalies FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

COMMENT ON TABLE sv.signup_anomalies IS 'Diagnostic log for unusual signup/payment situations';
COMMENT ON COLUMN sv.signup_anomalies.anomaly_type IS 'Type: missing_pre_customer, email_mismatch, duplicate_subscription, etc.';

-- =============================================================================
-- PHASE 1C: Extend public.customer_profile with new columns
-- Adds setup fee tracking, billing start date, and name fields
-- =============================================================================

-- Add setup_fee_paid column (default false for existing customers)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS setup_fee_paid boolean DEFAULT false;

-- Add setup_fee_amount column (default $99.00)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS setup_fee_amount numeric(10,2) DEFAULT 99.00;

-- Add billing_start_date column (null until subscription starts)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS billing_start_date date;

-- Add first_name column (may already have full_name, but separate is cleaner)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS first_name text;

-- Add last_name column
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS last_name text;

-- Index for finding customers who haven't paid setup fee
CREATE INDEX IF NOT EXISTS idx_customer_profile_setup_fee_unpaid
  ON public.customer_profile (setup_fee_paid)
  WHERE setup_fee_paid = false;

-- Index for billing date queries
CREATE INDEX IF NOT EXISTS idx_customer_profile_billing_start
  ON public.customer_profile (billing_start_date)
  WHERE billing_start_date IS NOT NULL;

COMMENT ON COLUMN public.customer_profile.setup_fee_paid IS 'True after $99 setup fee checkout completes (including $0 promo)';
COMMENT ON COLUMN public.customer_profile.setup_fee_amount IS 'Amount paid for setup fee (0 if promo used)';
COMMENT ON COLUMN public.customer_profile.billing_start_date IS 'Date when $299/month subscription billing began';

-- =============================================================================
-- PHASE 1D: Grant schema access for edge functions
-- Ensures sv schema is accessible to service_role
-- =============================================================================

GRANT USAGE ON SCHEMA sv TO service_role;
GRANT ALL ON sv.pre_customers TO service_role;
GRANT ALL ON sv.signup_anomalies TO service_role;

-- =============================================================================
-- VERIFICATION QUERIES (for manual testing after migration)
-- =============================================================================

-- Run these after migration to verify:
-- SELECT * FROM sv.pre_customers LIMIT 1;
-- SELECT setup_fee_paid, setup_fee_amount, billing_start_date, first_name, last_name FROM public.customer_profile LIMIT 1;
-- SELECT * FROM sv.signup_anomalies LIMIT 1;
