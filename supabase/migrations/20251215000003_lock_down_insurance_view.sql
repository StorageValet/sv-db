-- Migration: 20251215000003_lock_down_insurance_view.sql
-- Purpose: Lock down v_user_insurance - accessible ONLY via fn_my_insurance() RPC
-- CTO Mandate: End users must NOT have direct SELECT on this view

-- Enable security_invoker for safer semantics
ALTER VIEW public.v_user_insurance SET (security_invoker = true);

-- Revoke ALL privileges from client-facing roles
REVOKE ALL ON public.v_user_insurance FROM anon;
REVOKE ALL ON public.v_user_insurance FROM authenticated;
REVOKE ALL ON public.v_user_insurance FROM agent_role;

-- Grant SELECT only to service_role (for server-side operations if needed)
GRANT SELECT ON public.v_user_insurance TO service_role;

COMMENT ON VIEW public.v_user_insurance IS
  'Insurance tracking per user. LOCKED DOWN - access via fn_my_insurance() RPC only. Direct SELECT revoked from authenticated/anon roles.';
