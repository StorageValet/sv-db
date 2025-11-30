-- Migration: Create sv schema to capture manually-created production objects
-- This ensures fresh database replays work correctly
--
-- CONTEXT: The sv schema was originally created manually in Supabase Dashboard.
-- This migration captures the exact production structure so migrations are reproducible.

-- 1. Create schema
CREATE SCHEMA IF NOT EXISTS sv;

-- 2. Create staff table (matching production structure exactly)
CREATE TABLE IF NOT EXISTS sv.staff (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'staff' CHECK (role IN ('admin', 'staff')),
  full_name TEXT,
  email TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Create is_staff function (no parameter - uses auth.uid())
CREATE OR REPLACE FUNCTION sv.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'sv'
AS $$
  SELECT EXISTS (SELECT 1 FROM sv.staff s WHERE s.user_id = auth.uid());
$$;

-- 4. Enable RLS
ALTER TABLE sv.staff ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS policies (matching production)
DROP POLICY IF EXISTS "Service role full access" ON sv.staff;
CREATE POLICY "Service role full access" ON sv.staff
  USING ((auth.jwt() ->> 'role'::text) = 'service_role'::text);

DROP POLICY IF EXISTS "p_staff_service_role" ON sv.staff;
CREATE POLICY "p_staff_service_role" ON sv.staff
  USING (true) WITH CHECK (true);

-- 6. Seed initial admin (Zach) - only if user exists (handles local dev vs production)
INSERT INTO sv.staff (user_id, role, full_name, email)
SELECT '24b9bcd8-2a98-44e8-b0af-920ae2894c05', 'admin', 'Zach Brown', 'zach@mystoragevalet.com'
WHERE EXISTS (SELECT 1 FROM auth.users WHERE id = '24b9bcd8-2a98-44e8-b0af-920ae2894c05')
ON CONFLICT (user_id) DO NOTHING;
