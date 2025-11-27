-- Migration: Rename in_transit to scheduled
-- Purpose: Update item status terminology for clarity

-- Step 1: Ensure ENUM type supports 'scheduled'
ALTER TYPE public.item_status
  ADD VALUE IF NOT EXISTS 'scheduled';

-- Step 2: Drop existing CHECK constraint (if it exists)
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS items_status_check;

-- Step 3: Update existing rows from 'in_transit' to 'scheduled'
UPDATE public.items
SET status = 'scheduled'
WHERE status = 'in_transit';

-- Step 4: Add new CHECK constraint with updated allowed values
ALTER TABLE public.items
  ADD CONSTRAINT items_status_check
  CHECK (status IN ('home', 'scheduled', 'stored'));
