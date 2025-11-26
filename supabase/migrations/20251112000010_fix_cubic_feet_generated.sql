-- Migration 0010: Fix cubic_feet to be a generated column
-- ---------------------------------------------------------------
-- Problem: Migration 0001 created cubic_feet with DEFAULT 0 (regular column).
--          Migration 0003 tried to add GENERATED column but IF NOT EXISTS blocked it.
--          Result: Column exists but stores 0 instead of calculating dimensions.
--
-- Solution: Drop the broken column and recreate as GENERATED ALWAYS.
--
-- Impact: All existing cubic_feet values (currently 0) will be recalculated
--         automatically based on length_inches × width_inches × height_inches.

BEGIN;

-- Drop existing non-generated column
ALTER TABLE public.items DROP COLUMN IF EXISTS cubic_feet;

-- Recreate as GENERATED ALWAYS column with NULL-safe calculation
ALTER TABLE public.items
  ADD COLUMN cubic_feet NUMERIC(8,2)
  GENERATED ALWAYS AS (
    CASE
      WHEN length_inches IS NOT NULL
           AND width_inches IS NOT NULL
           AND height_inches IS NOT NULL
      THEN (length_inches * width_inches * height_inches) / 1728.0
      ELSE NULL
    END
  ) STORED;

COMMIT;
