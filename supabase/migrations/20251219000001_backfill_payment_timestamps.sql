-- Migration: Backfill last_payment_at for setup-fee customers
-- Date: December 19, 2025
-- Issue: 18/18 customers have NULL last_payment_at despite successful checkout
-- Root cause: checkout.session.completed handler didn't write payment timestamps
-- Fix: Edge function v3.9 now writes timestamps; this backfills existing customers

-- Uses DISTINCT ON to pick latest event per customer (deterministic)
-- Falls back to webhook_events.created_at if Stripe payload timestamp missing
-- Only updates NULL values (idempotent)

-- Strategy 1: Match by stripe_customer_id (most reliable)
-- Pick latest checkout event per customer
UPDATE customer_profile cp
SET last_payment_at = best_event.payment_ts
FROM (
  SELECT DISTINCT ON (payload->'data'->'object'->>'customer')
    payload->'data'->'object'->>'customer' AS stripe_customer_id,
    COALESCE(
      to_timestamp((payload->>'created')::bigint),
      created_at
    ) AS payment_ts
  FROM billing.webhook_events
  WHERE event_type = 'checkout.session.completed'
    AND payload->'data'->'object'->>'customer' IS NOT NULL
  ORDER BY payload->'data'->'object'->>'customer', created_at DESC
) best_event
WHERE best_event.stripe_customer_id = cp.stripe_customer_id
  AND cp.setup_fee_paid = true
  AND cp.last_payment_at IS NULL;

-- Strategy 2: Match by email for customers without stripe_customer_id ($0 promo)
UPDATE customer_profile cp
SET last_payment_at = best_event.payment_ts
FROM (
  SELECT DISTINCT ON (lower(payload->'data'->'object'->>'customer_email'))
    lower(payload->'data'->'object'->>'customer_email') AS email,
    COALESCE(
      to_timestamp((payload->>'created')::bigint),
      created_at
    ) AS payment_ts
  FROM billing.webhook_events
  WHERE event_type = 'checkout.session.completed'
    AND payload->'data'->'object'->>'customer_email' IS NOT NULL
  ORDER BY lower(payload->'data'->'object'->>'customer_email'), created_at DESC
) best_event
WHERE best_event.email = lower(cp.email)
  AND cp.stripe_customer_id IS NULL
  AND cp.setup_fee_paid = true
  AND cp.last_payment_at IS NULL;

-- Strategy 3: Last resort - use customer_profile.created_at for any remaining
-- (e.g., if webhook payload was missing both customer ID and email)
UPDATE customer_profile
SET last_payment_at = created_at
WHERE setup_fee_paid = true
  AND last_payment_at IS NULL;
