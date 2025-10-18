-- Phase-1 Inventory & Scheduling Enhancements
-- Version: 1.0
-- Date: 2025-10-18
-- Non-destructive schema evolution for enhanced customer portal

-- ═══════════════════════════════════════════════════════════════════
-- I. MULTI-PHOTO SUPPORT
-- ═══════════════════════════════════════════════════════════════════

-- Add photo_paths array for 1-5 photos per item
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS photo_paths text[] DEFAULT '{}';

-- Backfill existing single photos into array
UPDATE public.items
SET photo_paths = ARRAY[photo_path]
WHERE photo_path IS NOT NULL AND (photo_paths IS NULL OR photo_paths = '{}');

-- Relax NOT NULL constraint on photo_path (keep column for backward compatibility)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='items' AND column_name='photo_path' AND is_nullable='NO'
  ) THEN
    ALTER TABLE public.items ALTER COLUMN photo_path DROP NOT NULL;
  END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════
-- II. ITEM STATUS TRACKING
-- ═══════════════════════════════════════════════════════════════════

-- Add status column for tracking item location
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'home';

-- Add CHECK constraint for valid statuses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='items_status_check'
  ) THEN
    ALTER TABLE public.items
      ADD CONSTRAINT items_status_check
      CHECK (status IN ('home', 'in_transit', 'stored'));
  END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════
-- III. CATEGORY SUPPORT
-- ═══════════════════════════════════════════════════════════════════

-- Add optional category field
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS category text;

-- Create index for category filtering
CREATE INDEX IF NOT EXISTS idx_items_category
  ON public.items(category) WHERE category IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════
-- IV. PHYSICAL DATA LOCK (after pickup confirmation)
-- ═══════════════════════════════════════════════════════════════════

-- Add timestamp for when physical data was locked
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS physical_locked_at timestamptz;

-- Trigger function to prevent editing locked physical fields
CREATE OR REPLACE FUNCTION public.prevent_physical_edits_after_pickup()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if physical data is locked
  IF OLD.physical_locked_at IS NOT NULL THEN
    -- Prevent changes to physical dimensions
    IF NEW.weight_lbs IS DISTINCT FROM OLD.weight_lbs OR
       NEW.length_inches IS DISTINCT FROM OLD.length_inches OR
       NEW.width_inches IS DISTINCT FROM OLD.width_inches OR
       NEW.height_inches IS DISTINCT FROM OLD.height_inches THEN
      RAISE EXCEPTION 'Cannot modify physical dimensions after pickup confirmation. Contact support if corrections are needed.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to items table
DROP TRIGGER IF EXISTS trg_prevent_physical_edits ON public.items;
CREATE TRIGGER trg_prevent_physical_edits
  BEFORE UPDATE ON public.items
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_physical_edits_after_pickup();

-- ═══════════════════════════════════════════════════════════════════
-- V. BATCH OPERATIONS SUPPORT
-- ═══════════════════════════════════════════════════════════════════

-- Add item_ids array for batch pickup/redelivery
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS item_ids uuid[] DEFAULT '{}';

-- Rename 'kind' to 'service_type' with extended values
DO $$
BEGIN
  -- Check if 'kind' column exists
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='actions' AND column_name='kind'
  ) THEN
    -- Rename column
    ALTER TABLE public.actions RENAME COLUMN kind TO service_type;

    -- Drop old constraint
    ALTER TABLE public.actions DROP CONSTRAINT IF EXISTS actions_kind_check;
  END IF;
END$$;

-- Add new CHECK constraint with extended service types
DO $$
BEGIN
  -- Drop existing constraint if it exists
  ALTER TABLE public.actions DROP CONSTRAINT IF EXISTS actions_service_type_check;

  -- Add new constraint
  ALTER TABLE public.actions
    ADD CONSTRAINT actions_service_type_check
    CHECK (service_type IN ('pickup', 'redelivery', 'container_delivery'));
END$$;

-- Create GIN index for efficient array queries
CREATE INDEX IF NOT EXISTS idx_actions_item_ids_gin
  ON public.actions USING gin(item_ids);

-- ═══════════════════════════════════════════════════════════════════
-- VI. CUSTOMER PROFILE EXPANSION
-- ═══════════════════════════════════════════════════════════════════

-- Add personal and delivery information
ALTER TABLE public.customer_profile
  ADD COLUMN IF NOT EXISTS full_name text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS delivery_address jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS delivery_instructions text;

-- Add index for phone lookups (if needed for support)
CREATE INDEX IF NOT EXISTS idx_customer_profile_phone
  ON public.customer_profile(phone) WHERE phone IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════
-- VII. MOVEMENT HISTORY / EVENT LOG
-- ═══════════════════════════════════════════════════════════════════

-- Create inventory_events table for movement tracking
CREATE TABLE IF NOT EXISTS public.inventory_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES public.items(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  event_data jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS on inventory_events
ALTER TABLE public.inventory_events ENABLE ROW LEVEL SECURITY;

-- RLS policy: users can only see their own events
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='inventory_events' AND policyname='p_inventory_events_owner_select'
  ) THEN
    CREATE POLICY p_inventory_events_owner_select ON public.inventory_events
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END$$;

-- RLS policy: users can only insert their own events
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='inventory_events' AND policyname='p_inventory_events_owner_insert'
  ) THEN
    CREATE POLICY p_inventory_events_owner_insert ON public.inventory_events
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
END$$;

-- Index for efficient timeline queries
CREATE INDEX IF NOT EXISTS idx_inventory_events_item_id_created
  ON public.inventory_events(item_id, created_at DESC);

-- Index for user's event history
CREATE INDEX IF NOT EXISTS idx_inventory_events_user_id_created
  ON public.inventory_events(user_id, created_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- VIII. PERFORMANCE INDEXES
-- ═══════════════════════════════════════════════════════════════════

-- Index for status filtering (already created above for category)
CREATE INDEX IF NOT EXISTS idx_items_status
  ON public.items(status);

-- Composite index for user's items by status
CREATE INDEX IF NOT EXISTS idx_items_user_status_created
  ON public.items(user_id, status, created_at DESC);

-- Index for photo_paths array (for future queries)
CREATE INDEX IF NOT EXISTS idx_items_photo_paths_gin
  ON public.items USING gin(photo_paths);

-- ═══════════════════════════════════════════════════════════════════
-- IX. DATA INTEGRITY & VALIDATION
-- ═══════════════════════════════════════════════════════════════════

-- Ensure at least one photo (either photo_path or photo_paths has content)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='items_photo_required_check'
  ) THEN
    ALTER TABLE public.items
      ADD CONSTRAINT items_photo_required_check
      CHECK (
        photo_path IS NOT NULL OR
        (photo_paths IS NOT NULL AND array_length(photo_paths, 1) > 0)
      );
  END IF;
END$$;

-- Ensure photo_paths doesn't exceed 5 photos
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='items_photo_paths_max_check'
  ) THEN
    ALTER TABLE public.items
      ADD CONSTRAINT items_photo_paths_max_check
      CHECK (
        photo_paths IS NULL OR
        array_length(photo_paths, 1) IS NULL OR
        array_length(photo_paths, 1) <= 5
      );
  END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════
-- X. RLS POLICY UPDATES (if needed)
-- ═══════════════════════════════════════════════════════════════════

-- Ensure UPDATE policy exists for items (for edit functionality)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='items' AND policyname='p_items_owner_update'
  ) THEN
    CREATE POLICY p_items_owner_update ON public.items
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END$$;

-- Ensure DELETE policy exists for items (for delete functionality)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='items' AND policyname='p_items_owner_delete'
  ) THEN
    CREATE POLICY p_items_owner_delete ON public.items
      FOR DELETE TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END$$;

-- Ensure UPDATE policy exists for customer_profile (for profile editing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='customer_profile' AND policyname='p_customer_profile_owner_update'
  ) THEN
    CREATE POLICY p_customer_profile_owner_update ON public.customer_profile
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END$$;

-- Ensure UPDATE policy exists for actions (for status updates)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='actions' AND policyname='p_actions_owner_update'
  ) THEN
    CREATE POLICY p_actions_owner_update ON public.actions
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════
-- XI. HELPER FUNCTIONS (optional, for future use)
-- ═══════════════════════════════════════════════════════════════════

-- Function to auto-lock physical data when pickup is completed
CREATE OR REPLACE FUNCTION public.lock_item_physical_data_on_pickup()
RETURNS TRIGGER AS $$
BEGIN
  -- If this is a pickup action being marked as completed
  IF NEW.service_type = 'pickup' AND NEW.status = 'completed' AND
     (OLD.status IS NULL OR OLD.status != 'completed') THEN

    -- Lock physical data for all items in this pickup
    UPDATE public.items
    SET physical_locked_at = now()
    WHERE id = ANY(NEW.item_ids) AND physical_locked_at IS NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to actions table (optional, can be done in app layer instead)
-- Uncomment if you want automatic locking via database trigger
-- DROP TRIGGER IF EXISTS trg_lock_items_on_pickup ON public.actions;
-- CREATE TRIGGER trg_lock_items_on_pickup
--   AFTER UPDATE ON public.actions
--   FOR EACH ROW
--   EXECUTE FUNCTION public.lock_item_physical_data_on_pickup();

-- ═══════════════════════════════════════════════════════════════════
-- XII. MIGRATION VERIFICATION
-- ═══════════════════════════════════════════════════════════════════

-- Verify all new columns exist
DO $$
DECLARE
  missing_columns text[] := ARRAY[]::text[];
BEGIN
  -- Check items table columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='items' AND column_name='photo_paths') THEN
    missing_columns := array_append(missing_columns, 'items.photo_paths');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='items' AND column_name='status') THEN
    missing_columns := array_append(missing_columns, 'items.status');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='items' AND column_name='category') THEN
    missing_columns := array_append(missing_columns, 'items.category');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='items' AND column_name='physical_locked_at') THEN
    missing_columns := array_append(missing_columns, 'items.physical_locked_at');
  END IF;

  -- Check actions table columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='actions' AND column_name='item_ids') THEN
    missing_columns := array_append(missing_columns, 'actions.item_ids');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='actions' AND column_name='service_type') THEN
    missing_columns := array_append(missing_columns, 'actions.service_type');
  END IF;

  -- Check customer_profile table columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='customer_profile' AND column_name='full_name') THEN
    missing_columns := array_append(missing_columns, 'customer_profile.full_name');
  END IF;

  -- Check inventory_events table exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='inventory_events') THEN
    missing_columns := array_append(missing_columns, 'inventory_events (table)');
  END IF;

  -- Report missing columns (if any)
  IF array_length(missing_columns, 1) > 0 THEN
    RAISE WARNING 'Migration incomplete: missing columns/tables: %', array_to_string(missing_columns, ', ');
  ELSE
    RAISE NOTICE 'Migration 0004 completed successfully. All schema enhancements applied.';
  END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION COMPLETE
-- ═══════════════════════════════════════════════════════════════════
-- Summary of changes:
-- ✅ Multi-photo support (photo_paths[])
-- ✅ Item status tracking (home/in_transit/stored)
-- ✅ Category support
-- ✅ Physical data lock (physical_locked_at + trigger)
-- ✅ Batch operations (item_ids[], service_type)
-- ✅ Customer profile expansion (name, phone, address, instructions)
-- ✅ Movement history (inventory_events table)
-- ✅ RLS policies for all new tables/operations
-- ✅ Performance indexes for filtering and queries
-- ✅ Data integrity constraints (photo requirements, max photos)
-- ═══════════════════════════════════════════════════════════════════
