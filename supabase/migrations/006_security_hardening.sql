-- Security hardening for the final schema.
-- This file defines the final security baseline for a fresh database build.

grant usage on schema extensions to authenticated;

alter extension pgcrypto set schema extensions;
alter extension pg_trgm set schema extensions;
alter extension btree_gist set schema extensions;
alter extension unaccent set schema extensions;

-- Every function gets an explicit, trusted lookup path. This includes trigger
-- functions and non-SECURITY-DEFINER helpers, which are also checked by Supabase lint.
do $$
declare
  f record;
begin
  for f in
    select n.nspname as schema_name,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app')
  loop
    execute format(
      'alter function %I.%I(%s) set search_path = pg_catalog, public, app, extensions, pg_temp',
      f.schema_name,
      f.function_name,
      f.arguments
    );
  end loop;
end $$;

-- schema_version is intentionally readable to active signed-in users.
alter table public.schema_version enable row level security;
create policy schema_version_read
  on public.schema_version
  for select to authenticated
  using (app.is_active_user());

grant select on public.schema_version to authenticated;

revoke all on public.notification_read_states from public, anon, authenticated;
grant select on public.notification_read_states to authenticated;

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema app from public, anon;

grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema app to authenticated;
-- Trigger entrypoints and the explicit-school number allocator are internal;
-- browser requests use the permission-checked zero-argument allocator instead.
revoke all on function public.generate_employee_number() from public, anon, authenticated;
revoke all on function public.guard_academic_year_unique_name() from public, anon, authenticated;
revoke all on function public.next_employee_number(uuid) from public, anon, authenticated;
revoke all on function public.is_school_day_for_year(uuid, date) from public, anon, authenticated;
revoke all on function public.next_receipt_number(uuid) from public, anon, authenticated;
revoke all on function public.finance_create_payment_atomic(
  uuid, numeric, app.payment_method, date, text, text, text, text, text
) from public, anon, authenticated;
-- This legacy placeholder only echoes its inputs and is not used by the app.
revoke all on function public.calculate_subject_result(uuid, uuid, app.exam_round)
  from public, anon, authenticated;
revoke execute on function public.generate_year_archive(uuid, text) from public, anon, authenticated;
revoke execute on function public.guard_announcement_metadata() from public, anon, authenticated;
revoke execute on function app.can_view_announcement(app.announcement_audience, uuid) from public, anon;
grant execute on function app.can_view_announcement(app.announcement_audience, uuid) to authenticated;
revoke all on function public.generate_year_archive_bundle(uuid, text, text, bigint) from public, anon;
grant execute on function public.generate_year_archive_bundle(uuid, text, text, bigint) to authenticated;
revoke execute on function public.generate_year_archive_bundle(uuid, text, text, bigint, jsonb) from public, anon;
grant execute on function public.generate_year_archive_bundle(uuid, text, text, bigint, jsonb) to authenticated;
revoke execute on function public.mark_archive_saved(uuid) from public, anon;
grant execute on function public.mark_archive_saved(uuid) to authenticated;
revoke execute on function public.verify_archive(uuid, text) from public, anon;
grant execute on function public.verify_archive(uuid, text) to authenticated;
revoke execute on function public.validate_restore(uuid, jsonb) from public, anon;
grant execute on function public.validate_restore(uuid, jsonb) to authenticated;
revoke execute on function public.record_backup_created(text, bigint, text) from public, anon;
grant execute on function public.record_backup_created(text, bigint, text) to authenticated;
revoke execute on function public.record_backup_restored(uuid) from public, anon;
grant execute on function public.record_backup_restored(uuid) to authenticated;
revoke execute on function public.student_ids_by_completeness(text) from public, anon;
grant execute on function public.student_ids_by_completeness(text) to authenticated;
revoke execute on function public.search_students_for_association(text, integer) from public, anon;
grant execute on function public.search_students_for_association(text, integer) to authenticated;

-- The browser session bootstrap is an authenticated RPC only.
revoke execute on function public.my_session() from public, anon;
grant execute on function public.my_session() to authenticated;

-- These internal helper functions are used by policies and trigger logic, not
-- by the REST API. Do not expose them as SECURITY DEFINER RPCs.
revoke execute on function public.account_is_active() from authenticated;
revoke execute on function public.current_profile_id() from authenticated;
revoke execute on function public.current_user_school() from authenticated;
revoke execute on function public.has_permission(text) from authenticated;
revoke execute on function public.is_manager() from authenticated;
-- Pre-auth username resolution and throttling are server-side only. The
-- username-auth Edge Function uses the service-role key for these RPCs.
revoke all on function public.begin_login_attempt(text)
  from public, anon, authenticated;
grant execute on function public.begin_login_attempt(text) to service_role;
revoke all on function public.record_login_failure(text)
  from public, anon, authenticated;
grant execute on function public.record_login_failure(text) to service_role;
revoke all on function public.resolve_login_email(text)
  from public, anon, authenticated;
grant execute on function public.resolve_login_email(text) to service_role;
revoke all on function public.resolve_staff_login_email(text)
  from public, anon, authenticated;
grant execute on function public.resolve_staff_login_email(text) to service_role;
revoke all on function public.set_notification_read_states(text[], boolean) from public, anon, authenticated;
grant execute on function public.set_notification_read_states(text[], boolean) to authenticated;
revoke all on function public.mark_notification_read(uuid) from public, anon, authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
revoke all on function public.mark_all_notifications_read() from public, anon, authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- User administration RPCs are callable only from the server-side Edge Function.
revoke all on function public.admin_set_user_access(uuid, uuid, text, text, integer, text[]) from public, anon, authenticated;
grant execute on function public.admin_set_user_access(uuid, uuid, text, text, integer, text[]) to service_role;
revoke all on function public.create_managed_user_profile(uuid, uuid, text, text, text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.create_managed_user_profile(uuid, uuid, text, text, text, text, text, text, uuid) to service_role;
revoke all on function public.admin_mark_password_change_required(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.admin_mark_password_change_required(uuid, uuid, text) to service_role;

-- Audit page RPCs are authenticated-only; triggers remain internal.
revoke all on function public.audit_logs_page(text, text, text, timestamptz, timestamptz, integer, integer, text[]) from public, anon;
grant execute on function public.audit_logs_page(text, text, text, timestamptz, timestamptz, integer, integer, text[]) to authenticated;
revoke all on function public.audit_logs_page(text, text, text, timestamptz, timestamptz, integer, integer, text[], boolean) from public, anon;
grant execute on function public.audit_logs_page(text, text, text, timestamptz, timestamptz, integer, integer, text[], boolean) to authenticated;
revoke all on function public.record_login() from public, anon;
grant execute on function public.record_login() to authenticated;
revoke all on function public.mark_password_changed() from public, anon;
grant execute on function public.mark_password_changed() to authenticated;
revoke all on function public.record_logout() from public, anon;
grant execute on function public.record_logout() to authenticated;
revoke all on function app.audit_student_change() from public, anon, authenticated;
revoke all on function app.audit_employee_change() from public, anon, authenticated;

-- Student account mappings and login-collision checks are service-role only.
revoke all on public.student_app_accounts from public, anon, authenticated;
grant all on public.student_app_accounts to service_role;
revoke all on function public.student_login_identifier_conflicts(text) from public, anon, authenticated;
grant execute on function public.student_login_identifier_conflicts(text) to service_role;

-- Minimal student-portal projections; no direct access to student rows or the
-- Auth mapping table is granted to portal identities.
revoke all on function app.current_student_portal_id() from public, anon, authenticated;
grant execute on function app.current_student_portal_id() to authenticated;
revoke all on function public.student_portal_session() from public, anon, authenticated;
grant execute on function public.student_portal_session() to authenticated;
revoke all on function public.student_portal_identity() from public, anon, authenticated;
grant execute on function public.student_portal_identity() to authenticated;
revoke all on function public.student_app_access_account_statuses(uuid[]) from public, anon, authenticated;
grant execute on function public.student_app_access_account_statuses(uuid[]) to authenticated;

-- Student data is projected only for the authenticated student identity; the
-- caller cannot choose a student ID and receives no direct table access.
revoke all on function public.student_portal_data() from public, anon, authenticated;
grant execute on function public.student_portal_data() to authenticated;

-- Class-subject materialization is a permission-checked timetable RPC only.
revoke all on function public.ensure_class_subjects_for_timetable(uuid)
  from public, anon, authenticated;
grant execute on function public.ensure_class_subjects_for_timetable(uuid)
  to authenticated;

-- Tenant and withdrawal trigger helpers are not REST RPCs.
revoke all on function app.set_audit_log_school_scope() from public, anon, authenticated;
revoke all on function app.guard_academic_year_closure() from public, anon, authenticated;
revoke all on function app.guard_student_educational_status_transition() from public, anon, authenticated;
revoke all on function app.prevent_enrollment_for_withdrawn_student() from public, anon, authenticated;
revoke all on function app.prevent_new_operation_for_withdrawn_student() from public, anon, authenticated;
revoke all on function app.guard_student_login_identifier_collision() from public, anon, authenticated;

-- Audited same-school workflows are authenticated RPCs only.
revoke all on function public.close_academic_year(uuid, boolean) from public, anon;
grant execute on function public.close_academic_year(uuid, boolean) to authenticated;
revoke all on function public.withdraw_student_file(uuid, text, text) from public, anon;
grant execute on function public.withdraw_student_file(uuid, text, text) to authenticated;
revoke all on function public.restore_student_file(uuid, text) from public, anon;
grant execute on function public.restore_student_file(uuid, text) to authenticated;

-- Shared fuzzy lookup is callable by active authenticated staff; withdrawn
-- students remain excluded unless a separate, explicit archive search is used.
revoke all on function public.search_people_names(text, text, integer, boolean) from public, anon;
grant execute on function public.search_people_names(text, text, integer, boolean) to authenticated;

-- Remove only the obsolete four-argument RPC when safe; never cascade stored
-- dependencies or disturb the canonical three-argument service-only API.
do $$
declare
  v_old_oid oid := to_regprocedure(
    'public.admin_mark_password_change_required(uuid,text,text,bigint)'
  );
begin
  if v_old_oid is not null then
    if exists (
      select 1 from pg_depend
      where refobjid = v_old_oid and deptype in ('n', 'a')
    ) then
      raise exception 'The obsolete four-argument password RPC has database dependencies; review them before cleanup.';
    end if;
    execute 'drop function public.admin_mark_password_change_required(uuid,text,text,bigint)';
  end if;
end;
$$;

-- Student-only app access and guardian-login guard are internal protections.
revoke all on function app.guardian_app_login_status_write_guard()
  from public, anon, authenticated;
revoke all on function public.update_guardian_app_login_status(uuid, text, text)
  from public, anon, authenticated;

-- Location records are school-scoped; timetable/curriculum materializations
-- are readable but writable only through their permission-checked RPCs.
grant select, insert, update on public.school_locations to authenticated;
grant select on public.class_subjects to authenticated;
grant select on public.employee_assignments to authenticated;
revoke all on function app.touch_school_location_version()
  from public, anon, authenticated;
revoke all on function app.guard_timetable_entry_year()
  from public, anon, authenticated;
revoke all on function public.ensure_class_subjects_for_employee_assignments(uuid)
  from public, anon;
grant execute on function public.ensure_class_subjects_for_employee_assignments(uuid)
  to authenticated;
revoke all on function public.list_employee_assignment_options(uuid, uuid)
  from public, anon;
grant execute on function public.list_employee_assignment_options(uuid, uuid)
  to authenticated;
revoke all on function public.sync_employee_assignments(uuid, uuid, uuid[])
  from public, anon;
grant execute on function public.sync_employee_assignments(uuid, uuid, uuid[])
  to authenticated;
revoke all on function public.add_timetable_entry(uuid, smallint, uuid, uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.add_timetable_entry(uuid, smallint, uuid, uuid, uuid, uuid, text)
  to authenticated;
revoke all on function public.update_timetable_entry(uuid, smallint, uuid, uuid, uuid, text, integer)
  from public, anon;
grant execute on function public.update_timetable_entry(uuid, smallint, uuid, uuid, uuid, text, integer)
  to authenticated;

-- Payroll creation is authenticated and permission-checked by its RPC body.
revoke all on function public.generate_payroll(uuid, text) from public, anon;
grant execute on function public.generate_payroll(uuid, text) to authenticated;

notify pgrst, 'reload schema';

