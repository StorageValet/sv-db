-- Migration: 20251215000002_missing_rpc_functions.sql
-- Purpose: Create missing RPC functions called by portal
-- CTO Mandate: All functions must enforce authorization internally (not just UI gating)

-- ============================================================================
-- FUNCTION 1: fn_is_admin()
-- Returns true if current user is admin in sv.staff table
-- Used by: WaitlistAdmin.tsx to gate admin-only pages
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'sv'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM sv.staff s
    WHERE s.user_id = auth.uid()
      AND s.role = 'admin'
  );
$$;

COMMENT ON FUNCTION public.fn_is_admin() IS
  'Checks if current authenticated user has admin role in sv.staff. Returns false if not authenticated or not admin.';

GRANT EXECUTE ON FUNCTION public.fn_is_admin() TO authenticated;

-- ============================================================================
-- FUNCTION 2: fn_waitlist_analytics()
-- Returns pre_customer registration stats for admin dashboard
-- Used by: WaitlistAdmin.tsx to display waitlist/signup analytics
-- SECURITY: Hard-checks admin role - raises exception if not admin
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_waitlist_analytics()
RETURNS TABLE (
  total_signups bigint,
  in_service_area bigint,
  out_of_service_area bigint,
  converted bigint,
  conversion_rate numeric,
  recent_signups json
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'sv'
AS $$
DECLARE
  is_admin_user boolean;
BEGIN
  -- CRITICAL: Internal authorization check (CTO mandate)
  SELECT EXISTS (
    SELECT 1 FROM sv.staff s
    WHERE s.user_id = auth.uid()
      AND s.role = 'admin'
  ) INTO is_admin_user;

  IF NOT is_admin_user THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  -- Return analytics data
  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM sv.pre_customers)::bigint AS total_signups,
    (SELECT COUNT(*) FROM sv.pre_customers WHERE service_area_match = true)::bigint AS in_service_area,
    (SELECT COUNT(*) FROM sv.pre_customers WHERE service_area_match = false)::bigint AS out_of_service_area,
    (SELECT COUNT(*) FROM sv.pre_customers WHERE converted_at IS NOT NULL)::bigint AS converted,
    CASE
      WHEN (SELECT COUNT(*) FROM sv.pre_customers WHERE service_area_match = true) > 0
      THEN ROUND(
        (SELECT COUNT(*) FROM sv.pre_customers WHERE converted_at IS NOT NULL)::numeric /
        (SELECT COUNT(*) FROM sv.pre_customers WHERE service_area_match = true)::numeric * 100,
        1
      )
      ELSE 0
    END AS conversion_rate,
    (
      SELECT json_agg(row_to_json(r))
      FROM (
        SELECT
          id,
          email,
          first_name,
          last_name,
          zip_code,
          service_area_match,
          converted_at IS NOT NULL AS is_converted,
          created_at
        FROM sv.pre_customers
        ORDER BY created_at DESC
        LIMIT 50
      ) r
    ) AS recent_signups;
END;
$$;

COMMENT ON FUNCTION public.fn_waitlist_analytics() IS
  'Returns waitlist/pre-customer analytics. ADMIN ONLY - raises exception if caller is not admin.';

GRANT EXECUTE ON FUNCTION public.fn_waitlist_analytics() TO authenticated;

-- ============================================================================
-- NOTE: fn_my_insurance() already exists in migration 0003_item_req_insurance_qr.sql
-- It reads from v_user_insurance view (which we fixed in the previous migration)
-- No changes needed - view fix propagates automatically
-- ============================================================================
