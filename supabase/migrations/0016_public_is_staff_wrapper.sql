-- Migration 0016: Create public.is_staff() wrapper for sv.is_staff()
-- This allows the frontend to call the function via supabase.rpc('is_staff')
-- since the JS client only allows public/graphql_public schemas

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT sv.is_staff();
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

COMMENT ON FUNCTION public.is_staff() IS 'Wrapper for sv.is_staff() - checks if current user is in sv.staff table';
