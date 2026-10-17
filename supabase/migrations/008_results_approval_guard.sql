create or replace function public.approve_exam_grades(p_exam_id uuid)
returns jsonb
language plpgsql security definer
set search_path=public,app,pg_temp
as $$
declare
  n integer;
  v_exam public.exams%rowtype;
begin
  perform app.require_perm('grades.approve');
  select * into v_exam
  from public.exams
  where id=p_exam_id and school_id=app.current_school_id()
  for update;
  if not found then raise exception 'الامتحان غير موجود في المدرسة الحالية'; end if;
  if v_exam.status='closed' then raise exception 'الامتحان مغلق'; end if;

  update public.grade_records gr
  set status='approved',approved_by=auth.uid(),approved_at=now()
  where gr.exam_id=p_exam_id and gr.status in ('entered','reviewed')
    and exists (
      select 1 from public.student_enrollments e
      join public.students s on s.id=e.student_id
      where e.id=gr.enrollment_id and s.school_id=app.current_school_id()
        and e.academic_year_id=v_exam.academic_year_id
        and (v_exam.class_id is null or e.class_id=v_exam.class_id)
        and (v_exam.grade_id is null or e.grade_id=v_exam.grade_id)
    );
  get diagnostics n=row_count;
  if n = 0 then
    raise exception 'لا توجد درجات مدخلة لاعتمادها';
  end if;

  update public.exams set status='approved'
  where id=p_exam_id and school_id=app.current_school_id();
  return jsonb_build_object('approved_records',n);
end;
$$;
