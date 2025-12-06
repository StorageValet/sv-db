-- Migration: Add RPC function for pre_customer upsert
-- Purpose: Allow edge functions to insert/update sv.pre_customers via public schema RPC
-- Date: December 6, 2025

-- =============================================================================
-- RPC Function: upsert_pre_customer
-- Allows edge functions to upsert into sv.pre_customers without schema exposure
-- =============================================================================

CREATE OR REPLACE FUNCTION public.upsert_pre_customer(
  p_email text,
  p_first_name text,
  p_last_name text,
  p_phone text DEFAULT NULL,
  p_street_address text DEFAULT NULL,
  p_unit text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_state text DEFAULT 'NJ',
  p_zip_code text DEFAULT NULL,
  p_service_area_match boolean DEFAULT false,
  p_referral_source text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sv
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- Normalize email to lowercase
  p_email := lower(trim(p_email));

  -- Upsert into sv.pre_customers
  INSERT INTO sv.pre_customers (
    email,
    first_name,
    last_name,
    phone,
    street_address,
    unit,
    city,
    state,
    zip_code,
    service_area_match,
    referral_source,
    updated_at
  )
  VALUES (
    p_email,
    trim(p_first_name),
    trim(p_last_name),
    p_phone,
    p_street_address,
    p_unit,
    p_city,
    p_state,
    p_zip_code,
    p_service_area_match,
    p_referral_source,
    now()
  )
  ON CONFLICT (email)
  DO UPDATE SET
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = COALESCE(EXCLUDED.phone, sv.pre_customers.phone),
    street_address = COALESCE(EXCLUDED.street_address, sv.pre_customers.street_address),
    unit = COALESCE(EXCLUDED.unit, sv.pre_customers.unit),
    city = COALESCE(EXCLUDED.city, sv.pre_customers.city),
    state = COALESCE(EXCLUDED.state, sv.pre_customers.state),
    zip_code = COALESCE(EXCLUDED.zip_code, sv.pre_customers.zip_code),
    service_area_match = EXCLUDED.service_area_match,
    referral_source = COALESCE(EXCLUDED.referral_source, sv.pre_customers.referral_source),
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Grant execute to service_role (edge functions)
GRANT EXECUTE ON FUNCTION public.upsert_pre_customer TO service_role;

COMMENT ON FUNCTION public.upsert_pre_customer IS 'Upserts a pre-customer record from Framer form submission';

-- =============================================================================
-- RPC Function: get_pre_customer_by_email
-- Allows stripe-webhook to lookup pre_customer data
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_pre_customer_by_email(p_email text)
RETURNS TABLE (
  id uuid,
  email text,
  first_name text,
  last_name text,
  phone text,
  street_address text,
  unit text,
  city text,
  state text,
  zip_code text,
  service_area_match boolean,
  referral_source text,
  converted_at timestamptz,
  converted_user_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sv
AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.id,
    pc.email,
    pc.first_name,
    pc.last_name,
    pc.phone,
    pc.street_address,
    pc.unit,
    pc.city,
    pc.state,
    pc.zip_code,
    pc.service_area_match,
    pc.referral_source,
    pc.converted_at,
    pc.converted_user_id
  FROM sv.pre_customers pc
  WHERE pc.email = lower(trim(p_email))
  LIMIT 1;
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.get_pre_customer_by_email TO service_role;

COMMENT ON FUNCTION public.get_pre_customer_by_email IS 'Retrieves pre-customer data by email for Stripe webhook processing';

-- =============================================================================
-- RPC Function: mark_pre_customer_converted
-- Marks a pre_customer as converted after Stripe checkout
-- =============================================================================

CREATE OR REPLACE FUNCTION public.mark_pre_customer_converted(
  p_pre_customer_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sv
AS $$
BEGIN
  UPDATE sv.pre_customers
  SET
    converted_at = now(),
    converted_user_id = p_user_id
  WHERE id = p_pre_customer_id;
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.mark_pre_customer_converted TO service_role;

COMMENT ON FUNCTION public.mark_pre_customer_converted IS 'Marks a pre-customer as converted after checkout completion';

-- =============================================================================
-- RPC Function: log_signup_anomaly
-- Logs unusual signup situations for ops review
-- =============================================================================

CREATE OR REPLACE FUNCTION public.log_signup_anomaly(
  p_email text DEFAULT NULL,
  p_stripe_customer_id text DEFAULT NULL,
  p_stripe_subscription_id text DEFAULT NULL,
  p_anomaly_type text DEFAULT NULL,
  p_event_id text DEFAULT NULL,
  p_raw_data jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sv
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO sv.signup_anomalies (
    email,
    stripe_customer_id,
    stripe_subscription_id,
    anomaly_type,
    event_id,
    raw_data
  )
  VALUES (
    p_email,
    p_stripe_customer_id,
    p_stripe_subscription_id,
    p_anomaly_type,
    p_event_id,
    p_raw_data
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.log_signup_anomaly TO service_role;

COMMENT ON FUNCTION public.log_signup_anomaly IS 'Logs signup anomalies for diagnostic purposes';
