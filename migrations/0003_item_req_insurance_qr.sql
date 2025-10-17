-- Items: required business fields + QR generator + insurance view + claims scaffold

ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS estimated_value_cents int,
  ADD COLUMN IF NOT EXISTS weight_lbs numeric(7,2),
  ADD COLUMN IF NOT EXISTS length_inches numeric(7,2),
  ADD COLUMN IF NOT EXISTS width_inches  numeric(7,2),
  ADD COLUMN IF NOT EXISTS height_inches numeric(7,2),
  ADD COLUMN IF NOT EXISTS tags text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS details jsonb DEFAULT '{}'::jsonb;

DO $
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='items' AND column_name='photo_path' AND is_nullable='NO'
  ) THEN
    ALTER TABLE public.items ALTER COLUMN photo_path SET NOT NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='items_estimated_value_cents_nn') THEN
    ALTER TABLE public.items ALTER COLUMN estimated_value_cents SET NOT NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='items_weight_lbs_nn') THEN
    ALTER TABLE public.items ALTER COLUMN weight_lbs SET NOT NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='items_dims_nn') THEN
    ALTER TABLE public.items
      ALTER COLUMN length_inches SET NOT NULL,
      ALTER COLUMN width_inches  SET NOT NULL,
      ALTER COLUMN height_inches SET NOT NULL;
  END IF;
END$;

DO $
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='items_estimated_value_cents_ck') THEN
    ALTER TABLE public.items ADD CONSTRAINT items_estimated_value_cents_ck
      CHECK (estimated_value_cents >= 0 AND estimated_value_cents <= 100000000);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='items_weight_lbs_ck') THEN
    ALTER TABLE public.items ADD CONSTRAINT items_weight_lbs_ck CHECK (weight_lbs > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='items_dims_ck') THEN
    ALTER TABLE public.items ADD CONSTRAINT items_dims_ck
      CHECK (length_inches > 0 AND width_inches > 0 AND height_inches > 0);
  END IF;
END$;

DO $
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='items' AND column_name='cubic_feet'
  ) THEN
    ALTER TABLE public.items
      ADD COLUMN cubic_feet numeric GENERATED ALWAYS AS
      (((length_inches * width_inches * height_inches) / 1728.0)) STORED;
  END IF;
END$;

CREATE OR REPLACE VIEW public.v_user_insurance AS
SELECT
  u.id AS user_id,
  300000::int AS insurance_cap_cents,
  COALESCE(SUM(i.estimated_value_cents),0)::int AS total_item_value_cents,
  GREATEST(300000 - COALESCE(SUM(i.estimated_value_cents),0), 0)::int AS remaining_cents,
  LEAST( GREATEST( (300000 - COALESCE(SUM(i.estimated_value_cents),0))::numeric / 300000, 0), 1) AS remaining_ratio
FROM auth.users u
LEFT JOIN public.items i ON i.user_id = u.id
GROUP BY u.id;

CREATE OR REPLACE FUNCTION public.fn_my_insurance()
RETURNS TABLE (
  insurance_cap_cents int,
  total_item_value_cents int,
  remaining_cents int,
  remaining_ratio numeric
) LANGUAGE sql SECURITY DEFINER SET search_path = public AS $
  SELECT v.insurance_cap_cents, v.total_item_value_cents, v.remaining_cents, v.remaining_ratio
  FROM public.v_user_insurance v
  WHERE v.user_id = auth.uid();
$;

GRANT EXECUTE ON FUNCTION public.fn_my_insurance() TO authenticated;

CREATE SEQUENCE IF NOT EXISTS public.items_qr_seq;

CREATE OR REPLACE FUNCTION public.sv_next_qr_code() RETURNS text
LANGUAGE plpgsql AS $
DECLARE
  y text := to_char(now() at time zone 'utc', 'YYYY');
  n bigint;
BEGIN
  n := nextval('public.items_qr_seq');
  RETURN 'SV-' || y || '-' || lpad(n::text, 6, '0');
END $;

DO $
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='items' AND column_name='qr_code'
  ) THEN
    ALTER TABLE public.items ADD COLUMN qr_code text UNIQUE;
  END IF;
END $;

CREATE OR REPLACE FUNCTION public.trg_items_assign_qr() RETURNS trigger
LANGUAGE plpgsql AS $
BEGIN
  IF NEW.qr_code IS NULL OR btrim(NEW.qr_code) = '' THEN
    NEW.qr_code := public.sv_next_qr_code();
  END IF;
  RETURN NEW;
END $;

DROP TRIGGER IF EXISTS t_items_assign_qr ON public.items;
CREATE TRIGGER t_items_assign_qr BEFORE INSERT ON public.items
FOR EACH ROW EXECUTE FUNCTION public.trg_items_assign_qr();

DROP POLICY IF EXISTS p_items_owner_insert ON public.items;
CREATE POLICY p_items_owner_insert ON public.items
  FOR INSERT TO authenticated
  WITH CHECK ( user_id = auth.uid() );

DROP POLICY IF EXISTS p_items_owner_select ON public.items;
CREATE POLICY p_items_owner_select ON public.items
  FOR SELECT TO authenticated
  USING ( user_id = auth.uid() );

CREATE TABLE IF NOT EXISTS public.claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  item_id uuid NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  claim_amount_cents int NOT NULL CHECK (claim_amount_cents > 0),
  description text,
  status text NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_claims_owner_select ON public.claims;
CREATE POLICY p_claims_owner_select ON public.claims
  FOR SELECT TO authenticated
  USING ( user_id = auth.uid() );

DROP POLICY IF EXISTS p_claims_owner_insert ON public.claims;
CREATE POLICY p_claims_owner_insert ON public.claims
  FOR INSERT TO authenticated
  WITH CHECK ( user_id = auth.uid() );

-- Performance indexes for fast queries at scale
CREATE INDEX IF NOT EXISTS idx_items_user_created_at
  ON public.items (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_items_tags_gin
  ON public.items USING gin (tags);

CREATE INDEX IF NOT EXISTS idx_items_details_gin
  ON public.items USING gin (details);
