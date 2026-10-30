-- Keep the existing authenticated projection intact while adding the
-- enrollment-scoped period definitions needed to render empty timetable cells.
alter function public.student_portal_data()
  rename to student_portal_data_base;

revoke all on function public.student_portal_data_base()
  from public, anon, authenticated;

create or replace function public.student_portal_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions, pg_temp
as $$
declare
  v_student_id uuid;
  v_school_id uuid;
  v_class_id uuid;
  v_academic_year_id uuid;
  v_data jsonb;
begin
  v_student_id := app.current_student_portal_id();
  if v_student_id is null then
    return null;
  end if;

  v_data := public.student_portal_data_base();
  if v_data is null then
    return null;
  end if;

  select s.school_id
  into v_school_id
  from public.students s
  where s.id = v_student_id;

  select e.class_id, e.academic_year_id
  into v_class_id, v_academic_year_id
  from public.student_enrollments e
  join public.students s
    on s.id = e.student_id
    and s.school_id = v_school_id
  join public.academic_years y
    on y.id = e.academic_year_id
    and y.school_id = s.school_id
  where e.student_id = v_student_id
    and e.withdrawal_date is null
    and coalesce(e.enrollment_status, 'نشط') in ('نشط', 'active')
  order by y.is_current desc nulls last,
    e.enrollment_date desc nulls last,
    e.created_at desc,
    e.id desc
  limit 1;

  return v_data || jsonb_build_object(
    'timetable_periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'period_id', tp.id,
        'period_number', tp.period_number,
        'period', tp.name_ar,
        'start_time', tp.start_time,
        'end_time', tp.end_time
      ) order by tp.period_number, tp.id)
      from public.timetable_periods tp
      where tp.school_id = v_school_id
        and tp.academic_year_id = v_academic_year_id
        and (
          (coalesce(tp.is_active, false) and not coalesce(tp.is_break, false))
          or exists (
            select 1
            from public.timetable_entries te
            where te.period_id = tp.id
              and te.class_id = v_class_id
              and te.academic_year_id = v_academic_year_id
              and te.is_active
          )
        )
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.student_portal_data()
  from public, anon, authenticated;
grant execute on function public.student_portal_data() to authenticated;
