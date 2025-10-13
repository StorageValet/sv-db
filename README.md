# sv-db — Storage Valet Database Migrations & Seeds

**Version:** v3.1
**Purpose:** Supabase migrations and seed data for Storage Valet MVP

## Structure

```
sv-db/
├── migrations/
│   └── 0001_init.sql          # Core schema: customer_profile, items, actions, billing
└── seeds/
    └── config_pricing.sql     # Runtime config: pricing, schedule, media, referrals
```

## Key Features

- **RLS-first security**: All customer tables have row-level policies
- **Single-tier pricing**: $299/month (premium299)
- **Setup fee**: Disabled by default (configurable via config_pricing)
- **Webhook idempotency**: billing.webhook_events with unique event_id constraint

## Deployment

Apply migrations via Supabase CLI:
```bash
supabase db push
```

Apply seeds (if not using remote dashboard):
```bash
psql $DATABASE_URL < seeds/config_pricing.sql
```

## Schema Overview

### public.customer_profile
- 1:1 with auth.users
- Tracks Stripe customer_id and subscription status
- RLS: owner-only access

### public.items
- Customer inventory with photo_path (Storage bucket reference)
- QR codes: SV-YYYY-######
- RLS: owner-only access

### public.actions
- Pickup/delivery scheduling
- Status: pending | confirmed | completed | canceled
- RLS: owner-only access

### billing.customers
- Denormalized Stripe customer mapping for webhook performance

### billing.webhook_events
- Idempotent event log (unique on event_id)
- Audit trail for all Stripe events

## Config Tables (Runtime)

- `config_pricing`: monthly_price_cents, setup_fee_enabled, setup_fee_amount_cents
- `config_schedule`: minimum_notice_hours
- `config_media`: max_photo_size_mb, allowed_formats
- `config_referrals`: enabled, reward_amount_cents

Managed via Retool post-launch.

---

### Project docs
Core specs & runbooks: **https://github.com/mystoragevalet/sv-docs**

- Implementation Plan v3.1
- Final Validation Checklist v3.1
- Deployment Instructions v3.1
- Go–NoGo (Line in the Sand) v3.1
- Business Context & Requirements v3.1
- Runbooks (webhook tests, env setup, smoke tests)
