-- Migration: 20251215000001_fix_insurance_view.sql
-- Purpose: Fix v_user_insurance to only count items in SV possession (scheduled/stored)
-- Issue: Current view counts ALL items regardless of status
-- Impact: Insurance coverage display was inaccurate - showing items still at customer's home
-- CTO Approved: This is the single source of truth for insurance calculations

-- Drop and recreate view with status filter
DROP VIEW IF EXISTS public.v_user_insurance;

CREATE VIEW public.v_user_insurance AS
SELECT
    auth.uid() AS user_id,
    300000 AS insurance_cap_cents,
    COALESCE(SUM(i.estimated_value_cents), 0)::integer AS total_item_value_cents,
    GREATEST(300000 - COALESCE(SUM(i.estimated_value_cents), 0), 0)::integer AS remaining_cents,
    LEAST(GREATEST((300000 - COALESCE(SUM(i.estimated_value_cents), 0))::numeric / 300000, 0), 1) AS remaining_ratio
FROM items i
WHERE i.user_id = auth.uid()
  AND i.status IN ('scheduled', 'stored')  -- CRITICAL: Only items in SV possession are insured
GROUP BY auth.uid();

COMMENT ON VIEW public.v_user_insurance IS
  'Insurance tracking per user. Only counts items with status scheduled or stored (in SV possession). Secured by auth.uid() filter.';

-- Maintain security: revoke anon, grant authenticated
REVOKE ALL PRIVILEGES ON public.v_user_insurance FROM anon;
GRANT SELECT ON public.v_user_insurance TO authenticated;
