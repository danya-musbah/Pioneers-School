-- Authenticated student portal projections. The browser can call this RPC, but
-- it can only ever receive the data belonging to the authenticated student.
-- Student login resolves its identifier inside the student-login Edge Function
-- so anonymous callers cannot enumerate account email addresses.
revoke all on function public.resolve_login_email(text) from public, anon, authenticated;

create or replace function public.student_portal_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions, pg_temp
as $$
declare
  v_student_id uuid;
  v_enrollment_id uuid;
begin
  v_student_id := app.current_student_portal_id();
  if v_student_id is null then
    return null;
  end if;

  select e.id
    into v_enrollment_id
  from public.student_enrollments e
  join public.academic_years y on y.id = e.academic_year_id
  where e.student_id = v_student_id
  order by y.is_current desc nulls last, e.enrollment_date desc nulls last, e.created_at desc
  limit 1;

  return jsonb_build_object(
    'student', (
      select jsonb_build_object(
        'id', s.id,
        'student_number', s.student_number,
        'full_name', s.full_name,
        'stage', ast.name_ar,
        'grade', g.name_ar,
        'section', coalesce(c.section_name, c.section_code, c.name_ar, ''),
        'academic_year', coalesce(y.name_ar, y.label, y.code)
      )
      from public.students s
      left join public.student_enrollments e on e.id = v_enrollment_id
      left join public.academic_years y on y.id = e.academic_year_id
      left join public.school_grades g on g.id = e.grade_id
      left join public.academic_stages ast on ast.id = g.stage_id
      left join public.classes c on c.id = e.class_id
      where s.id = v_student_id
    ),
    'attendance', jsonb_build_object(
      'present', coalesce((
        select count(*) from public.student_attendance a
        left join public.attendance_statuses st on st.code = a.status_code
        where a.enrollment_id = v_enrollment_id
          and (st.counts_as_present or a.status in ('حاضر', 'present', 'attended'))
      ), 0),
      'late', coalesce((
        select count(*) from public.student_attendance a
        where a.enrollment_id = v_enrollment_id
          and (coalesce(a.minutes_late, 0) > 0 or a.status in ('متأخر', 'late'))
      ), 0),
      'absent', coalesce((
        select count(*) from public.student_attendance a
        left join public.attendance_statuses st on st.code = a.status_code
        where a.enrollment_id = v_enrollment_id
          and not coalesce(st.counts_as_present, false)
          and coalesce(a.minutes_late, 0) = 0
          and a.status not in ('حاضر', 'present', 'attended', 'متأخر', 'late')
      ), 0),
      'percent', coalesce((
        select round(
          100.0 * count(*) filter (where st.counts_as_present or a.status in ('حاضر', 'present', 'attended'))
          / nullif(count(*), 0)
        )::integer
        from public.student_attendance a
        left join public.attendance_statuses st on st.code = a.status_code
        where a.enrollment_id = v_enrollment_id
      ), 0),
      'records', coalesce((
        select jsonb_agg(item order by attendance_date desc)
        from (
          select jsonb_build_object(
            'date', a.attendance_date,
            'status', coalesce(st.label_ar, a.status, a.status_code, 'غير محدد'),
            'minutes_late', coalesce(a.minutes_late, 0)
          ) as item, a.attendance_date
          from public.student_attendance a
          left join public.attendance_statuses st on st.code = a.status_code
          where a.enrollment_id = v_enrollment_id
          order by a.attendance_date desc
          limit 20
        ) recent
      ), '[]'::jsonb)
    ),
    'results', coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject', sub.name_ar,
        'percentage', sr.percentage,
        'grade', coalesce(gb.label_ar, '—')
      ) order by sub.sort_order, sub.name_ar)
      from public.subject_results sr
      join public.term_results tr
        on tr.enrollment_id = sr.enrollment_id
       and tr.round = sr.round
       and tr.status in ('approved', 'closed')
      join public.grade_subjects gs on gs.id = sr.grade_subject_id
      join public.subjects sub on sub.id = gs.subject_id
      left join public.grade_bands gb on sr.percentage between gb.min_pct and gb.max_pct
      where sr.enrollment_id = v_enrollment_id
    ), '[]'::jsonb),
    'fees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'label', coalesce(ft.name_ar, 'رسوم دراسية'),
        'total', coalesce(f.net_amount, f.total_amount, 0),
        'paid', coalesce(payments.paid, 0),
        'remaining', greatest(coalesce(f.net_amount, f.total_amount, 0) - coalesce(payments.paid, 0), 0),
        'status', case
          when greatest(coalesce(f.net_amount, f.total_amount, 0) - coalesce(payments.paid, 0), 0) = 0 then 'مدفوع'
          when coalesce(payments.paid, 0) > 0 then 'مدفوع جزئيًا'
          else 'مستحق'
        end
      ) order by ft.name_ar)
      from public.student_fees f
      left join public.fee_types ft on ft.id = f.fee_type_id
      left join lateral (
        select sum(i.paid_amount) as paid
        from public.installments i
        where i.student_fee_id = f.id
      ) payments on true
      where f.enrollment_id = v_enrollment_id
    ), '[]'::jsonb),
    'timetable', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day_number', te.day_number,
        'day', coalesce(wd.name_ar, te.day_of_week, 'غير محدد'),
        'subject', sub.name_ar,
        'teacher', emp.full_name,
        'room', coalesce(te.room_name, te.room, c.room_name, c.room, ''),
        'period', coalesce(tp.name_ar, 'الحصة'),
        'start_time', tp.start_time,
        'end_time', tp.end_time
      ) order by te.day_number, tp.period_number)
      from public.timetable_entries te
      join public.classes c on c.id = te.class_id
      left join public.week_days wd on wd.day_number = te.day_number
      left join public.timetable_periods tp on tp.id = te.period_id
      left join public.subjects sub on sub.id = te.subject_id
      left join public.employees emp on emp.id = te.employee_id
      where te.class_id = (select e.class_id from public.student_enrollments e where e.id = v_enrollment_id)
        and te.academic_year_id = (select e.academic_year_id from public.student_enrollments e where e.id = v_enrollment_id)
        and te.is_active
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.student_portal_data() from public, anon, authenticated;
grant execute on function public.student_portal_data() to authenticated;
