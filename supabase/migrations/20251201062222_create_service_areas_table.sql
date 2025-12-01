-- Migration: Create service_areas table and is_valid_zip_code function
-- Purpose: Single source of truth for Storage Valet launch ZIP codes
-- Date: 2025-12-01

-- ============================================================================
-- 1. Create service_areas table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.service_areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  zip_code text NOT NULL,
  city text NOT NULL,
  state text NOT NULL DEFAULT 'NJ',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Unique constraint on zip_code
CREATE UNIQUE INDEX IF NOT EXISTS service_areas_zip_code_key
  ON public.service_areas (zip_code);

-- Index for fast lookups by active status
CREATE INDEX IF NOT EXISTS service_areas_is_active_idx
  ON public.service_areas (is_active);

COMMENT ON TABLE public.service_areas IS
  'Storage Valet launch service areas (14 ZIP codes in Hudson County, NJ)';

COMMENT ON COLUMN public.service_areas.zip_code IS
  'Five-digit ZIP code (e.g., 07030)';

COMMENT ON COLUMN public.service_areas.city IS
  'City name (e.g., Hoboken, Jersey City)';

COMMENT ON COLUMN public.service_areas.is_active IS
  'Whether this ZIP is currently accepting new customers';

-- ============================================================================
-- 2. Seed launch ZIP codes (14 total)
-- ============================================================================

INSERT INTO public.service_areas (zip_code, city, state, is_active)
VALUES
  ('07030', 'Hoboken', 'NJ', true),
  ('07310', 'Jersey City', 'NJ', true),
  ('07311', 'Jersey City', 'NJ', true),
  ('07302', 'Jersey City', 'NJ', true),
  ('07305', 'Jersey City', 'NJ', true),
  ('07307', 'Jersey City', 'NJ', true),
  ('07304', 'Jersey City', 'NJ', true),
  ('07306', 'Jersey City', 'NJ', true),
  ('07086', 'Weehawken', 'NJ', true),
  ('07087', 'Union City', 'NJ', true),
  ('07093', 'West New York', 'NJ', true),
  ('07020', 'Edgewater', 'NJ', true),
  ('07047', 'North Bergen', 'NJ', true)
ON CONFLICT (zip_code) DO UPDATE
  SET city = EXCLUDED.city,
      state = EXCLUDED.state,
      is_active = EXCLUDED.is_active;

-- ============================================================================
-- 3. Create/replace is_valid_zip_code function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_valid_zip_code(zip text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.service_areas sa
    WHERE sa.zip_code = left(trim(zip), 5)
      AND sa.is_active = true
  );
$$;

COMMENT ON FUNCTION public.is_valid_zip_code(text) IS
  'Check if a ZIP code is within the Storage Valet service area. Normalizes input by trimming and taking first 5 characters (handles ZIP+4 format).';
