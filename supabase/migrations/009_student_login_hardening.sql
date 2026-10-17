-- Student login identity lookup and throttling are server-only operations.
-- The Edge Function uses the service-role key; the browser anon key must not
-- be able to enumerate login emails or consume another student's attempts.
begin;

revoke all on function public.resolve_login_email(text)
  from public, anon, authenticated;
revoke all on function public.begin_login_attempt(text)
  from public, anon, authenticated;
revoke all on function public.record_login_failure(text)
  from public, anon, authenticated;

grant execute on function public.resolve_login_email(text) to service_role;
grant execute on function public.begin_login_attempt(text) to service_role;

commit;
