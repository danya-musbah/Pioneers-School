-- Narrow, authenticated-only projection for the signed-in student's own
-- gender and image references. No caller-supplied student ID is accepted.
begin;

create or replace function public.student_portal_identity()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
  v_student_id uuid;
begin
  v_student_id := app.current_student_portal_id();
  if v_student_id is null then
    return null;
  end if;

  return (
    select jsonb_build_object(
      'student', jsonb_build_object(
        'gender', s.gender,
        'photo_path', s.photo_path,
        'photo_storage_path', s.photo_storage_path,
        'avatar_path', s.avatar_path,
        'avatar_storage_path', s.avatar_storage_path
      )
    )
    from public.students s
    where s.id = v_student_id
  );
end;
$$;

revoke all on function public.student_portal_identity()
  from public, anon, authenticated;
grant execute on function public.student_portal_identity()
  to authenticated;

commit;
