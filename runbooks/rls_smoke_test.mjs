#!/usr/bin/env node
import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'crypto';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('❌ Missing Supabase env vars. Set SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function createUser(label) {
  const email = `${label}-${randomUUID()}@storagevalet.test`;
  const password = `Pwd-${randomUUID()}`;
  const { data, error } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) throw new Error(`Failed to create user ${label}: ${error.message}`);
  return { email, password, user: data.user };
}

async function signIn(email, password) {
  const { data, error } = await anonClient.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`Sign-in failed for ${email}: ${error.message}`);
  return { ...data.user, session: data.session };
}

async function authedFetch(session, path, options = {}) {
  const { method = 'GET', body } = options;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${session.access_token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, json };
}

function logResult(label, { status, json }) {
  const ok = status >= 200 && status < 300;
  console.log(`${ok ? '✅' : '❌'} ${label} → status ${status}`, ok ? '' : JSON.stringify(json));
  return ok;
}

async function main() {
  console.log('▶️ Starting RLS smoke test…');

  const userA = await createUser('qa-user-a');
  const userB = await createUser('qa-user-b');

  const authedA = await signIn(userA.email, userA.password);
  const authedB = await signIn(userB.email, userB.password);

  console.log(`   User A: ${authedA.id}`);
  console.log(`   User B: ${authedB.id}`);

  const insertA = await authedFetch(
    authedA.session,
    'items',
    {
      method: 'POST',
      body: {
        user_id: authedA.id,
        label: 'QA Item A',
        description: 'RLS smoke test item',
        status: 'home',
        estimated_value_cents: 12345,
        weight_lbs: 10,
        length_inches: 10,
        width_inches: 10,
        height_inches: 10,
        tags: ['qa'],
        photo_paths: [],
      },
      headers: { Prefer: 'return=representation' },
    }
  );
  logResult('User A inserts own item', insertA);
  const itemA = insertA.json?.[0];

  const getA = await authedFetch(authedA.session, 'items?select=id,user_id,label');
  logResult('User A lists own items', getA);

  const getAasB = await authedFetch(
    authedB.session,
    `items?select=id,user_id,label&user_id=eq.${authedA.id}`
  );
  logResult('User B tries to read User A items', getAasB);

  const insertEventA = await authedFetch(
    authedA.session,
    'inventory_events',
    {
      method: 'POST',
      body: {
        item_id: itemA?.id,
        user_id: authedA.id,
        event_type: 'qa_insert_test',
        event_data: { note: 'RLS check' },
      },
      headers: { Prefer: 'return=representation' },
    }
  );
  logResult('User A inserts inventory event', insertEventA);

  const getEventsA = await authedFetch(authedA.session, 'inventory_events?select=item_id,user_id,event_type');
  logResult('User A lists own inventory events', getEventsA);

  const getEventsAasB = await authedFetch(
    authedB.session,
    `inventory_events?select=item_id,user_id,event_type&user_id=eq.${authedA.id}`
  );
  logResult('User B tries to read User A events', getEventsAasB);

  await authedFetch(
    authedA.session,
    `items?id=eq.${itemA?.id}`,
    { method: 'DELETE' }
  );

  await adminClient.auth.admin.deleteUser(authedA.id);
  await adminClient.auth.admin.deleteUser(authedB.id);

  console.log('✅ RLS smoke test complete');
}

main().catch(async (err) => {
  console.error('❌ RLS smoke test failed:', err.message);
  process.exit(1);
});
