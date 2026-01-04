-- Migration 0008: Add staff override policies and seed staff member
-- ---------------------------------------------------------------
-- Enables operations staff to override customer actions/items while
-- retaining owner-based RLS protections. Seeds Zach Brown as initial staff.

begin;

-- 1. Clean up legacy duplicate policies for items/actions
-- (keeps descriptive policies introduced in migration 0006)
DROP POLICY IF EXISTS p_items_owner_select ON public.items;
DROP POLICY IF EXISTS p_items_owner_update ON public.items;
DROP POLICY IF EXISTS p_items_owner_delete ON public.items;

DROP POLICY IF EXISTS p_actions_owner_select ON public.actions;
DROP POLICY IF EXISTS p_actions_owner_update ON public.actions;
DROP POLICY IF EXISTS p_actions_owner_delete ON public.actions;

-- 2. Update items policies to allow staff overrides on UPDATE / DELETE
DROP POLICY IF EXISTS "Users can update own items" ON public.items;
CREATE POLICY "Users can update own items"
  ON public.items
  FOR UPDATE
  USING (auth.uid() = user_id OR sv.is_staff())
  WITH CHECK (auth.uid() = user_id OR sv.is_staff());

DROP POLICY IF EXISTS "Users can delete own items" ON public.items;
CREATE POLICY "Users can delete own items"
  ON public.items
  FOR DELETE
  USING (auth.uid() = user_id OR sv.is_staff());

-- 3. Update actions policies to allow staff overrides on UPDATE / DELETE
DROP POLICY IF EXISTS "Users can update own pending actions" ON public.actions;
CREATE POLICY "Users can update own pending actions"
  ON public.actions
  FOR UPDATE
  USING (auth.uid() = user_id OR sv.is_staff())
  WITH CHECK (auth.uid() = user_id OR sv.is_staff());

DROP POLICY IF EXISTS "Users can delete own pending actions" ON public.actions;
CREATE POLICY "Users can delete own pending actions"
  ON public.actions
  FOR DELETE
  USING (auth.uid() = user_id OR sv.is_staff());

-- 4. Seed sv.staff with initial administrator (id from Supabase auth.users)
-- Use INSERT...SELECT to skip gracefully if user doesn't exist (local dev vs production)
INSERT INTO sv.staff (user_id, role, full_name, email)
SELECT '24b9bcd8-2a98-44e8-b0af-920ae2894c05', 'admin', 'Zach Brown', 'zach@mystoragevalet.com'
WHERE EXISTS (SELECT 1 FROM auth.users WHERE id = '24b9bcd8-2a98-44e8-b0af-920ae2894c05')
ON CONFLICT (user_id) DO NOTHING;

commit;
