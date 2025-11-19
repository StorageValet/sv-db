-- Migration 0009: Grant schema usage for sv helpers
-- Ensures authenticated users can execute sv.is_staff() inside RLS policies.

begin;

GRANT USAGE ON SCHEMA sv TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sv TO authenticated, service_role;

commit;
