-- Resolve portal logins only through the student-to-Auth mapping.
-- A staff profile with a matching username is not a valid student portal identity.
begin;

create or replace function public.resolve_login_email(p_username text)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, auth, app, pg_temp
as $$
  select u.email::text
  from public.student_app_accounts a
  join public.students s
    on s.id = a.student_id
   and s.school_id = a.school_id
  join auth.users u
    on u.id = a.auth_user_id
  where a.is_enabled
    and a.auth_user_id is not null
    and s.student_app_login_enabled
    and s.student_app_login_status in ('active', 'reset_required')
    and s.educational_status <> 'withdrawn'
    and not coalesce(s.is_archived, false)
    and lower(btrim(s.student_number)) = lower(btrim(coalesce(p_username, '')))
  limit 1;
$$;

revoke all on function public.resolve_login_email(text)
  from public, anon, authenticated;
grant execute on function public.resolve_login_email(text)
  to service_role;

commit;