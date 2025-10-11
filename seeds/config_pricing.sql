-- Storage Valet — Pricing Configuration Seed
-- v3.1 • Single-tier $299/month • Setup fee disabled by default

-- Runtime configuration for pricing (managed via Retool post-launch)
CREATE TABLE IF NOT EXISTS public.config_pricing (
  id int PRIMARY KEY DEFAULT 1,
  monthly_price_cents int NOT NULL DEFAULT 29900, -- $299/month
  setup_fee_enabled boolean NOT NULL DEFAULT false,
  setup_fee_amount_cents int NOT NULL DEFAULT 9900, -- $99 (configurable, disabled)
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Insert default single-tier pricing
INSERT INTO public.config_pricing (id, monthly_price_cents, setup_fee_enabled, setup_fee_amount_cents)
VALUES (1, 29900, false, 9900)
ON CONFLICT (id) DO NOTHING;

-- Schedule configuration
CREATE TABLE IF NOT EXISTS public.config_schedule (
  id int PRIMARY KEY DEFAULT 1,
  minimum_notice_hours int NOT NULL DEFAULT 48,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.config_schedule (id, minimum_notice_hours)
VALUES (1, 48)
ON CONFLICT (id) DO NOTHING;

-- Media/photo configuration
CREATE TABLE IF NOT EXISTS public.config_media (
  id int PRIMARY KEY DEFAULT 1,
  max_photo_size_mb int NOT NULL DEFAULT 5,
  allowed_formats text[] NOT NULL DEFAULT ARRAY['jpg', 'jpeg', 'png', 'webp'],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.config_media (id, max_photo_size_mb, allowed_formats)
VALUES (1, 5, ARRAY['jpg', 'jpeg', 'png', 'webp'])
ON CONFLICT (id) DO NOTHING;

-- Referral configuration (disabled by default)
CREATE TABLE IF NOT EXISTS public.config_referrals (
  id int PRIMARY KEY DEFAULT 1,
  enabled boolean NOT NULL DEFAULT false,
  reward_amount_cents int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.config_referrals (id, enabled, reward_amount_cents)
VALUES (1, false, 0)
ON CONFLICT (id) DO NOTHING;
