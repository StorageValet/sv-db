-- Migration 0005: Add billing status tracking fields
-- Adds timestamp columns for payment success/failure tracking

-- Add payment tracking columns to customer_profile
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS last_payment_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_payment_failed_at timestamptz;

-- Add comment for documentation
COMMENT ON COLUMN public.customer_profile.last_payment_at IS 'Timestamp of last successful payment (updated by stripe-webhook on invoice.payment_succeeded)';
COMMENT ON COLUMN public.customer_profile.last_payment_failed_at IS 'Timestamp of last failed payment (updated by stripe-webhook on invoice.payment_failed)';
