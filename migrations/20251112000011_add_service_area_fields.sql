-- Migration 0011: Add Service Area Validation Fields to customer_profile
-- Date: 2025-11-12
-- Purpose: Support Stripe-first signup with address validation and service area enforcement
--
-- Changes:
-- 1. Add out_of_service_area flag (boolean)
-- 2. Add needs_manual_refund flag (boolean)
-- 3. Add delivery_instructions field (if not exists)
-- 4. Add indexes for email and ZIP lookup performance

-- ============================================================================
-- PART 1: ADD SERVICE AREA FLAGS
-- ============================================================================

-- Add out_of_service_area flag (default false = in service area)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS out_of_service_area boolean DEFAULT false;

COMMENT ON COLUMN public.customer_profile.out_of_service_area IS
  'True if customer address is outside service area. Blocks scheduling in portal.';

-- Add needs_manual_refund flag (set true when out_of_service_area for ops follow-up)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS needs_manual_refund boolean DEFAULT false;

COMMENT ON COLUMN public.customer_profile.needs_manual_refund IS
  'True if customer paid but is out of service area. Requires manual refund by ops.';

-- Add delivery_instructions field (if not already present)
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS delivery_instructions text;

COMMENT ON COLUMN public.customer_profile.delivery_instructions IS
  'Customer-provided special instructions for pickup/delivery (e.g., gate code, parking).';

-- ============================================================================
-- PART 2: ADD PERFORMANCE INDEXES
-- ============================================================================

-- Index on email for fast customer lookup by email (Calendly webhook use case)
CREATE INDEX IF NOT EXISTS idx_customer_profile_email
  ON public.customer_profile (email);

COMMENT ON INDEX idx_customer_profile_email IS
  'Performance: Fast customer lookup by email (used in Calendly webhook matching)';

-- Index on ZIP for service area validation queries
CREATE INDEX IF NOT EXISTS idx_customer_profile_zip
  ON public.customer_profile ((delivery_address->>'zip'));

COMMENT ON INDEX idx_customer_profile_zip IS
  'Performance: Fast ZIP lookup for service area validation and analytics';

-- ============================================================================
-- PART 3: ADD CONSTRAINTS FOR DATA INTEGRITY
-- ============================================================================

-- Ensure needs_manual_refund is only true when out_of_service_area is true
ALTER TABLE public.customer_profile
  ADD CONSTRAINT chk_manual_refund_requires_out_of_area
  CHECK (
    NOT needs_manual_refund OR out_of_service_area
  );

COMMENT ON CONSTRAINT chk_manual_refund_requires_out_of_area ON public.customer_profile IS
  'Business rule: Manual refund flag only valid when customer is out of service area';
