-- Storage Valet — Initial Schema Migration
-- v3.1 • Single-tier $299/month • RLS-first security

-- Billing schema for webhook events and Stripe customer mapping
CREATE SCHEMA IF NOT EXISTS billing;

-- Customer profile (1:1 with auth.users)
CREATE TABLE IF NOT EXISTS public.customer_profile (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text UNIQUE NOT NULL,
  stripe_customer_id text UNIQUE,
  subscription_status text DEFAULT 'inactive', -- inactive | active | past_due | canceled
  subscription_id text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Customer items (photos stored in Storage bucket)
CREATE TABLE IF NOT EXISTS public.items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text,
  description text,
  photo_path text, -- path in Storage bucket: {user_id}/{item_id}.jpg
  qr_code text UNIQUE, -- SV-YYYY-######
  cubic_feet numeric(6,2) DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Customer actions (pickup/delivery scheduling)
CREATE TABLE IF NOT EXISTS public.actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('pickup', 'delivery')),
  scheduled_at timestamptz,
  status text DEFAULT 'pending', -- pending | confirmed | completed | canceled
  details jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Billing: Stripe customer mapping (denormalized for webhook performance)
CREATE TABLE IF NOT EXISTS billing.customers (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  stripe_customer_id text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Billing: Webhook event log (idempotency + audit trail)
CREATE TABLE IF NOT EXISTS billing.webhook_events (
  id bigserial PRIMARY KEY,
  event_id text UNIQUE NOT NULL, -- Stripe event.id
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  processed_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);

-- Indexes for performance
CREATE INDEX idx_items_user_id ON public.items(user_id);
CREATE INDEX idx_items_qr_code ON public.items(qr_code);
CREATE INDEX idx_actions_user_id ON public.actions(user_id);
CREATE INDEX idx_actions_scheduled_at ON public.actions(scheduled_at);
CREATE INDEX idx_webhook_events_event_id ON billing.webhook_events(event_id);

-- Enable RLS on all customer-facing tables
ALTER TABLE public.customer_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Owner-only access (SELECT/INSERT/UPDATE)

-- customer_profile policies
CREATE POLICY p_customer_profile_owner_select ON public.customer_profile
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY p_customer_profile_owner_insert ON public.customer_profile
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY p_customer_profile_owner_update ON public.customer_profile
  FOR UPDATE USING (auth.uid() = user_id);

-- items policies
CREATE POLICY p_items_owner_select ON public.items
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY p_items_owner_insert ON public.items
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY p_items_owner_update ON public.items
  FOR UPDATE USING (auth.uid() = user_id);

-- actions policies
CREATE POLICY p_actions_owner_select ON public.actions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY p_actions_owner_insert ON public.actions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY p_actions_owner_update ON public.actions
  FOR UPDATE USING (auth.uid() = user_id);

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at triggers
CREATE TRIGGER set_updated_at_customer_profile
  BEFORE UPDATE ON public.customer_profile
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_items
  BEFORE UPDATE ON public.items
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_actions
  BEFORE UPDATE ON public.actions
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
