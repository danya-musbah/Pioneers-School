do $$
declare r record;
begin
  for r in
    select tablename
    from pg_tables
    where schemaname = 'public'
      and tablename not in (
        'schema_version',
        'students',
        'student_enrollments',
        'student_file_transactions',
        'notification_read_states',
        'school_calendar_exceptions',
        'student_attendance',
        'payments',
        'expenses',
        'payroll_periods',
        'payroll_entries',
        'fee_types',
        'fee_plans',
        'fee_plan_items',
        'student_fees',
        'installments'
      )
  loop
    execute format('alter table public.%I enable row level security', r.tablename);
    execute format('drop policy if exists %I on public.%I', 'rls_select_' || r.tablename, r.tablename);
    execute format('drop policy if exists %I on public.%I', 'rls_insert_' || r.tablename, r.tablename);
    execute format('drop policy if exists %I on public.%I', 'rls_update_' || r.tablename, r.tablename);
    execute format('drop policy if exists %I on public.%I', 'rls_delete_' || r.tablename, r.tablename);
    execute format('create policy %I on public.%I for select to authenticated using (app.is_active_user())', 'rls_select_' || r.tablename, r.tablename);
    execute format('create policy %I on public.%I for insert to authenticated with check (app.is_admin())', 'rls_insert_' || r.tablename, r.tablename);
    execute format('create policy %I on public.%I for update to authenticated using (app.is_admin()) with check (app.is_admin())', 'rls_update_' || r.tablename, r.tablename);
    execute format('create policy %I on public.%I for delete to authenticated using (app.is_admin())', 'rls_delete_' || r.tablename, r.tablename);
  end loop;
end $$;

-- Student CRUD follows the delegated student permissions rather than the
-- generic admin-only write policy used by the remaining tables.
revoke execute on function app.current_school_id() from public, anon;
grant execute on function app.current_school_id() to authenticated;

grant execute on function app.is_active_user() to authenticated;
grant execute on function app.is_admin() to authenticated;
grant execute on function app.has_perm(text) to authenticated;
grant execute on function app.has_any_perm(text[]) to authenticated;

alter table public.students enable row level security;
alter table public.student_attendance enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_entries enable row level security;
alter table public.fee_types enable row level security;
alter table public.fee_plans enable row level security;
alter table public.fee_plan_items enable row level security;
alter table public.student_fees enable row level security;
alter table public.installments enable row level security;

drop policy if exists rls_select_students on public.students;
drop policy if exists rls_insert_students on public.students;
drop policy if exists rls_update_students on public.students;
create policy rls_select_students
  on public.students
  for select to authenticated
  using (
    (
      app.is_admin()
      and school_id = app.current_school_id()
    )
    or (
      app.has_any_perm(
        'students.manage',
        'students.view',
        'students.create',
        'students.edit',
        'students.archive',
        'students.enrollment.manage'
      )
      and school_id = app.current_school_id()
    )
  );

create policy rls_insert_students
  on public.students
  for insert to authenticated
  with check (
    (
      app.is_admin()
      and school_id = app.current_school_id()
    )
    or (
      app.has_any_perm('students.manage','students.create')
      and school_id = app.current_school_id()
    )
  );

create policy rls_update_students
  on public.students
  for update to authenticated
  using (
    (
      app.is_admin()
      and school_id = app.current_school_id()
    )
    or (
      app.has_any_perm('students.manage','students.edit')
      and school_id = app.current_school_id()
    )
  )
  with check (
    (
      app.is_admin()
      and school_id = app.current_school_id()
    )
    or (
      app.has_any_perm('students.manage','students.edit')
      and school_id = app.current_school_id()
    )
  );

alter table public.student_enrollments enable row level security;
drop policy if exists rls_select_student_enrollments on public.student_enrollments;
drop policy if exists rls_insert_student_enrollments on public.student_enrollments;
drop policy if exists rls_update_student_enrollments on public.student_enrollments;
drop policy if exists rls_delete_student_enrollments on public.student_enrollments;
create policy rls_select_student_enrollments
  on public.student_enrollments for select to authenticated
  using (
    app.is_active_user()
    and app.has_any_perm(
      'students.view','students.create','students.edit','students.archive',
      'students.enrollment.manage','attendance.students.view','attendance.students.manage',
      'finance.fees.view','finance.fees.manage','finance.payments.view','finance.payments.create',
      'grades.view','grades.enter','results.view','reports.students.view',
      'reports.academic.view','reports.attendance.view','finance.reports.view'
    )
    and exists (
      select 1 from public.students s
      where s.id = student_enrollments.student_id
        and s.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.academic_years y
      where y.id = student_enrollments.academic_year_id
        and y.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.school_grades g
      where g.id = student_enrollments.grade_id
        and g.school_id = app.current_school_id()
    )
    and (
      student_enrollments.class_id is null
      or exists (
        select 1 from public.classes c
        where c.id = student_enrollments.class_id
          and c.school_id = app.current_school_id()
          and c.academic_year_id = student_enrollments.academic_year_id
          and c.grade_id = student_enrollments.grade_id
      )
    )
  );
create policy rls_insert_student_enrollments
  on public.student_enrollments for insert to authenticated
  with check (
    app.has_perm('students.enrollment.manage')
    and exists (
      select 1 from public.students s
      where s.id = student_enrollments.student_id
        and s.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.academic_years y
      where y.id = student_enrollments.academic_year_id
        and y.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.school_grades g
      where g.id = student_enrollments.grade_id
        and g.school_id = app.current_school_id()
    )
    and (
      student_enrollments.class_id is null
      or exists (
        select 1 from public.classes c
        where c.id = student_enrollments.class_id
          and c.school_id = app.current_school_id()
          and c.academic_year_id = student_enrollments.academic_year_id
          and c.grade_id = student_enrollments.grade_id
      )
    )
  );
create policy rls_update_student_enrollments
  on public.student_enrollments for update to authenticated
  using (
    app.has_perm('students.enrollment.manage')
    and exists (
      select 1 from public.students s
      where s.id = student_enrollments.student_id
        and s.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.academic_years y
      where y.id = student_enrollments.academic_year_id
        and y.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.school_grades g
      where g.id = student_enrollments.grade_id
        and g.school_id = app.current_school_id()
    )
    and (
      student_enrollments.class_id is null
      or exists (
        select 1 from public.classes c
        where c.id = student_enrollments.class_id
          and c.school_id = app.current_school_id()
          and c.academic_year_id = student_enrollments.academic_year_id
          and c.grade_id = student_enrollments.grade_id
      )
    )
  )
  with check (
    app.has_perm('students.enrollment.manage')
    and exists (
      select 1 from public.students s
      where s.id = student_enrollments.student_id
        and s.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.academic_years y
      where y.id = student_enrollments.academic_year_id
        and y.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.school_grades g
      where g.id = student_enrollments.grade_id
        and g.school_id = app.current_school_id()
    )
    and (
      student_enrollments.class_id is null
      or exists (
        select 1 from public.classes c
        where c.id = student_enrollments.class_id
          and c.school_id = app.current_school_id()
          and c.academic_year_id = student_enrollments.academic_year_id
          and c.grade_id = student_enrollments.grade_id
      )
    )
  );

alter table public.student_file_transactions enable row level security;
drop policy if exists rls_select_student_file_transactions on public.student_file_transactions;
drop policy if exists rls_insert_student_file_transactions on public.student_file_transactions;
drop policy if exists rls_update_student_file_transactions on public.student_file_transactions;
drop policy if exists rls_delete_student_file_transactions on public.student_file_transactions;
create policy rls_select_student_file_transactions
  on public.student_file_transactions for select to authenticated
  using (
    app.has_any_perm('students.manage','students.view','students.file.withdraw')
    and exists (
      select 1 from public.students s
      where s.id = student_file_transactions.student_id
        and s.school_id = app.current_school_id()
    )
  );

drop policy if exists rls_select_guardians on public.guardians;
drop policy if exists rls_insert_guardians on public.guardians;
drop policy if exists rls_update_guardians on public.guardians;
create policy rls_select_guardians
  on public.guardians for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('guardians.view','guardians.manage','students.manage','students.view','students.create','students.edit')
  );
create policy rls_insert_guardians
  on public.guardians for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('guardians.manage','students.manage','students.create','students.edit')
  );
create policy rls_update_guardians
  on public.guardians for update to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('guardians.manage','students.manage','students.edit'))
  with check (school_id = app.current_school_id() and app.has_any_perm('guardians.manage','students.manage','students.edit'));

drop policy if exists rls_select_student_guardians on public.student_guardians;
drop policy if exists rls_insert_student_guardians on public.student_guardians;
drop policy if exists rls_update_student_guardians on public.student_guardians;
drop policy if exists rls_delete_student_guardians on public.student_guardians;
create policy rls_select_student_guardians
  on public.student_guardians for select to authenticated
  using (
    (
      exists (
        select 1 from public.students s
        where s.id = student_guardians.student_id
          and s.school_id = app.current_school_id()
      )
      or (
        app.has_any_perm('guardians.view','guardians.manage')
        and exists (
          select 1 from public.guardians g
          where g.id = student_guardians.guardian_id
            and g.school_id = app.current_school_id()
        )
      )
    )
    and app.has_any_perm('guardians.view','guardians.manage','students.view','students.create','students.edit')
  );
create policy rls_insert_student_guardians
  on public.student_guardians for insert to authenticated
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_guardians.student_id
        and s.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.guardians g
      where g.id = student_guardians.guardian_id
        and g.school_id = app.current_school_id()
    )
    and app.has_any_perm('guardians.manage','students.create','students.edit')
  );
create policy rls_update_student_guardians
  on public.student_guardians for update to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_guardians.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('guardians.manage','students.manage','students.edit')
  )
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_guardians.student_id
        and s.school_id = app.current_school_id()
    )
    and exists (
      select 1 from public.guardians g
      where g.id = student_guardians.guardian_id
        and g.school_id = app.current_school_id()
    )
    and app.has_any_perm('guardians.manage','students.manage','students.edit')
  );
create policy rls_delete_student_guardians
  on public.student_guardians for delete to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_guardians.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('guardians.manage','students.manage','students.edit')
  );

drop policy if exists rls_select_student_notes on public.student_notes;
drop policy if exists rls_insert_student_notes on public.student_notes;
drop policy if exists rls_update_student_notes on public.student_notes;
drop policy if exists rls_delete_student_notes on public.student_notes;
create policy rls_select_student_notes
  on public.student_notes for select to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_notes.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.view','students.create','students.edit')
    and (
      not is_sensitive
      or app.has_any_perm('students.manage','students.edit','social.view','social.manage')
    )
  );
create policy rls_insert_student_notes
  on public.student_notes for insert to authenticated
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_notes.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.create','students.edit')
  );
create policy rls_update_student_notes
  on public.student_notes for update to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_notes.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.edit')
  )
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_notes.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.edit')
  );
create policy rls_delete_student_notes
  on public.student_notes for delete to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_notes.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.edit')
  );

drop policy if exists rls_select_student_file_checklist_items on public.student_file_checklist_items;
drop policy if exists rls_insert_student_file_checklist_items on public.student_file_checklist_items;
drop policy if exists rls_update_student_file_checklist_items on public.student_file_checklist_items;
drop policy if exists rls_delete_student_file_checklist_items on public.student_file_checklist_items;
create policy rls_select_student_file_checklist_items
  on public.student_file_checklist_items for select to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_file_checklist_items.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.view','students.create','students.edit')
  );
create policy rls_insert_student_file_checklist_items
  on public.student_file_checklist_items for insert to authenticated
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_file_checklist_items.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.create','students.edit')
  );
create policy rls_update_student_file_checklist_items
  on public.student_file_checklist_items for update to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_file_checklist_items.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.edit')
  )
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_file_checklist_items.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.edit')
  );
create policy rls_delete_student_file_checklist_items
  on public.student_file_checklist_items for delete to authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = student_file_checklist_items.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm('students.manage','students.edit')
  );

alter table public.social_case_categories enable row level security;
alter table public.social_cases enable row level security;
alter table public.social_case_notes enable row level security;

drop policy if exists rls_select_social_case_categories on public.social_case_categories;
drop policy if exists rls_insert_social_case_categories on public.social_case_categories;
drop policy if exists rls_update_social_case_categories on public.social_case_categories;
drop policy if exists rls_delete_social_case_categories on public.social_case_categories;
drop policy if exists rls_select_social_cases on public.social_cases;
drop policy if exists rls_insert_social_cases on public.social_cases;
drop policy if exists rls_update_social_cases on public.social_cases;
drop policy if exists rls_delete_social_cases on public.social_cases;
drop policy if exists rls_select_social_case_notes on public.social_case_notes;
drop policy if exists rls_insert_social_case_notes on public.social_case_notes;
drop policy if exists rls_update_social_case_notes on public.social_case_notes;
drop policy if exists rls_delete_social_case_notes on public.social_case_notes;

create policy rls_select_social_case_categories on public.social_case_categories for select to authenticated using (app.has_any_perm('social.view','social.manage'));
create policy rls_insert_social_case_categories on public.social_case_categories for insert to authenticated with check (app.has_perm('social.manage'));
create policy rls_update_social_case_categories on public.social_case_categories for update to authenticated using (app.has_perm('social.manage')) with check (app.has_perm('social.manage'));
create policy rls_delete_social_case_categories on public.social_case_categories for delete to authenticated using (app.has_perm('social.manage'));

create policy rls_select_social_cases on public.social_cases for select to authenticated using (school_id = app.current_school_id() and exists (select 1 from public.students s where s.id = social_cases.student_id and s.school_id = app.current_school_id()) and app.has_any_perm('social.view','social.manage'));
create policy rls_insert_social_cases on public.social_cases for insert to authenticated with check (school_id = app.current_school_id() and exists (select 1 from public.students s where s.id = social_cases.student_id and s.school_id = app.current_school_id()) and app.has_perm('social.manage'));
create policy rls_update_social_cases on public.social_cases for update to authenticated using (school_id = app.current_school_id() and exists (select 1 from public.students s where s.id = social_cases.student_id and s.school_id = app.current_school_id()) and app.has_perm('social.manage')) with check (school_id = app.current_school_id() and exists (select 1 from public.students s where s.id = social_cases.student_id and s.school_id = app.current_school_id()) and app.has_perm('social.manage'));
create policy rls_delete_social_cases on public.social_cases for delete to authenticated using (school_id = app.current_school_id() and exists (select 1 from public.students s where s.id = social_cases.student_id and s.school_id = app.current_school_id()) and app.has_perm('social.manage'));

create policy rls_select_social_case_notes on public.social_case_notes for select to authenticated using (exists (select 1 from public.social_cases c where c.id = coalesce(social_case_notes.case_id, social_case_notes.social_case_id) and c.school_id = app.current_school_id()) and app.has_any_perm('social.view','social.manage'));
create policy rls_insert_social_case_notes on public.social_case_notes for insert to authenticated with check (exists (select 1 from public.social_cases c where c.id = coalesce(social_case_notes.case_id, social_case_notes.social_case_id) and c.school_id = app.current_school_id()) and app.has_perm('social.manage'));
create policy rls_update_social_case_notes on public.social_case_notes for update to authenticated using (exists (select 1 from public.social_cases c where c.id = coalesce(social_case_notes.case_id, social_case_notes.social_case_id) and c.school_id = app.current_school_id()) and app.has_perm('social.manage')) with check (exists (select 1 from public.social_cases c where c.id = coalesce(social_case_notes.case_id, social_case_notes.social_case_id) and c.school_id = app.current_school_id()) and app.has_perm('social.manage'));
create policy rls_delete_social_case_notes on public.social_case_notes for delete to authenticated using (exists (select 1 from public.social_cases c where c.id = coalesce(social_case_notes.case_id, social_case_notes.social_case_id) and c.school_id = app.current_school_id()) and app.has_perm('social.manage'));

-- Replace the generic policies created above with the scoped policies below.
-- These names are generated by the default-policy loop for every public table.
drop policy if exists rls_select_departments on public.departments;
drop policy if exists rls_insert_departments on public.departments;
drop policy if exists rls_update_departments on public.departments;
drop policy if exists rls_select_job_titles on public.job_titles;
drop policy if exists rls_insert_job_titles on public.job_titles;
drop policy if exists rls_update_job_titles on public.job_titles;
drop policy if exists rls_select_employees on public.employees;
drop policy if exists rls_insert_employees on public.employees;
drop policy if exists rls_update_employees on public.employees;
drop policy if exists rls_select_employee_attendance on public.employee_attendance;
drop policy if exists rls_insert_employee_attendance on public.employee_attendance;
drop policy if exists rls_update_employee_attendance on public.employee_attendance;
drop policy if exists rls_select_employee_assignments on public.employee_assignments;
drop policy if exists rls_insert_employee_assignments on public.employee_assignments;
drop policy if exists rls_update_employee_assignments on public.employee_assignments;
drop policy if exists rls_select_leave_types on public.leave_types;
drop policy if exists rls_insert_leave_types on public.leave_types;
drop policy if exists rls_update_leave_types on public.leave_types;
drop policy if exists rls_select_leave_requests on public.leave_requests;
drop policy if exists rls_insert_leave_requests on public.leave_requests;
drop policy if exists rls_update_leave_requests on public.leave_requests;
drop policy if exists rls_delete_leave_requests on public.leave_requests;

create policy rls_select_departments
  on public.departments for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','attendance.employees.view','attendance.employees.manage','reports.employees.view')
  );
create policy rls_insert_departments
  on public.departments for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.create','employees.edit')
  );
create policy rls_update_departments
  on public.departments for update to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.edit','employees.archive')
  )
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.edit','employees.archive')
  );

create policy rls_select_job_titles
  on public.job_titles for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','attendance.employees.view','attendance.employees.manage','reports.employees.view')
  );
create policy rls_insert_job_titles
  on public.job_titles for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.create','employees.edit')
  );
create policy rls_update_job_titles
  on public.job_titles for update to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.edit','employees.archive')
  )
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.edit','employees.archive')
  );

create policy rls_select_employees
  on public.employees for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','attendance.employees.view','attendance.employees.manage','payroll.view','payroll.manage','payroll.approve','reports.employees.view')
  );
create policy rls_insert_employees
  on public.employees for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.create','employees.edit')
  );
create policy rls_update_employees
  on public.employees for update to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.edit','employees.archive')
  )
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('employees.edit','employees.archive')
  );

-- Employee removal is permitted only through the reference-checking RPC.
drop policy if exists rls_delete_employees on public.employees;
create policy rls_delete_employees
  on public.employees for delete to authenticated
  using (false);

alter table public.employee_document_checklist_items enable row level security;
drop policy if exists rls_select_employee_document_checklist_items
  on public.employee_document_checklist_items;
drop policy if exists rls_insert_employee_document_checklist_items
  on public.employee_document_checklist_items;
drop policy if exists rls_update_employee_document_checklist_items
  on public.employee_document_checklist_items;
drop policy if exists rls_delete_employee_document_checklist_items
  on public.employee_document_checklist_items;
create policy rls_select_employee_document_checklist_items
  on public.employee_document_checklist_items for select to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_document_checklist_items.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','employees.delete')
  );
create policy rls_insert_employee_document_checklist_items
  on public.employee_document_checklist_items for insert to authenticated
  with check (
    exists (
      select 1 from public.employees e
      where e.id = employee_document_checklist_items.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('employees.create','employees.edit')
  );
create policy rls_update_employee_document_checklist_items
  on public.employee_document_checklist_items for update to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_document_checklist_items.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_perm('employees.edit')
  )
  with check (
    exists (
      select 1 from public.employees e
      where e.id = employee_document_checklist_items.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_perm('employees.edit')
  );

create policy rls_select_employee_attendance
  on public.employee_attendance for select to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_attendance.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('attendance.employees.view','attendance.employees.manage','reports.employees.view')
  );
create policy rls_insert_employee_attendance
  on public.employee_attendance for insert to authenticated
  with check (
    exists (
      select 1 from public.employees e
      where e.id = employee_attendance.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_perm('attendance.employees.manage')
  );
create policy rls_update_employee_attendance
  on public.employee_attendance for update to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_attendance.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_perm('attendance.employees.manage')
  )
  with check (
    exists (
      select 1 from public.employees e
      where e.id = employee_attendance.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_perm('attendance.employees.manage')
  );

create policy rls_select_employee_assignments
  on public.employee_assignments for select to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_assignments.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('employees.view','employees.edit','attendance.employees.view','attendance.employees.manage','timetable.view','timetable.manage')
  );
create policy rls_insert_employee_assignments
  on public.employee_assignments for insert to authenticated
  with check (
    exists (
      select 1 from public.employees e
      where e.id = employee_assignments.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('employees.edit','attendance.employees.manage','timetable.manage')
  );
create policy rls_update_employee_assignments
  on public.employee_assignments for update to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_assignments.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('employees.edit','attendance.employees.manage','timetable.manage')
  )
  with check (
    exists (
      select 1 from public.employees e
      where e.id = employee_assignments.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm('employees.edit','attendance.employees.manage','timetable.manage')
  );

create policy rls_select_leave_types
  on public.leave_types for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('leaves.view','leaves.manage','leaves.approve')
  );
create policy rls_insert_leave_types
  on public.leave_types for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_perm('leaves.manage')
  );
create policy rls_update_leave_types
  on public.leave_types for update to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('leaves.manage','leaves.approve')
  )
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('leaves.manage','leaves.approve')
  );

create policy rls_select_leave_requests
  on public.leave_requests for select to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = leave_requests.employee_id
        and e.school_id = app.current_school_id()
    )
    and (
      app.has_any_perm('leaves.view','leaves.manage','leaves.approve')
      or exists (
        select 1
        from public.profiles p
        join public.employees e on e.id = p.employee_id
        where p.id = auth.uid()
          and e.id = leave_requests.employee_id
          and e.school_id = app.current_school_id()
      )
    )
  );
create policy rls_insert_leave_requests
  on public.leave_requests for insert to authenticated
  with check (false);
create policy rls_update_leave_requests
  on public.leave_requests for update to authenticated
  using (false)
  with check (false);
create policy rls_delete_leave_requests
  on public.leave_requests for delete to authenticated
  using (false);

-- Attendance is readable only within the authenticated user's school and
-- only by attendance/report users. Writes are performed through the secured
-- save_class_attendance() RPC.
drop policy if exists rls_select_student_attendance on public.student_attendance;
create policy rls_select_student_attendance
  on public.student_attendance
  for select to authenticated
  using (
    exists (
      select 1
      from public.students s
      where s.id = student_attendance.student_id
        and s.school_id = app.current_school_id()
    )
    and app.has_any_perm(
      'attendance.students.view',
      'attendance.students.manage',
      'reports.attendance.view'
    )
  );

-- Financial data is available to explicitly authorized financial staff and is
-- always restricted to the authenticated user's school. Admins are covered by
-- app.has_perm(), which grants every permission implicitly.
drop policy if exists rls_select_payments on public.payments;
drop policy if exists rls_insert_payments on public.payments;
drop policy if exists rls_update_payments on public.payments;
create policy rls_select_payments on public.payments for select to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('finance.payments.view','finance.payments.create','finance.payments.reverse'));
create policy rls_insert_payments on public.payments for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('finance.payments.create'));
create policy rls_update_payments on public.payments for update to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('finance.payments.reverse'))
  with check (school_id = app.current_school_id() and app.has_any_perm('finance.payments.reverse'));

drop policy if exists rls_select_expenses on public.expenses;
drop policy if exists rls_insert_expenses on public.expenses;
drop policy if exists rls_update_expenses on public.expenses;
create policy rls_select_expenses on public.expenses for select to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('finance.expenses.view','finance.expenses.manage','finance.reports.view'));
create policy rls_insert_expenses on public.expenses for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('finance.expenses.manage'));
create policy rls_update_expenses on public.expenses for update to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('finance.expenses.manage','finance.expenses.void'))
  with check (school_id = app.current_school_id() and app.has_any_perm('finance.expenses.manage','finance.expenses.void'));

drop policy if exists rls_select_payroll_periods on public.payroll_periods;
drop policy if exists rls_insert_payroll_periods on public.payroll_periods;
drop policy if exists rls_update_payroll_periods on public.payroll_periods;
create policy rls_select_payroll_periods on public.payroll_periods for select to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('payroll.view','payroll.manage','payroll.approve'));
create policy rls_insert_payroll_periods on public.payroll_periods for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('payroll.manage'));
create policy rls_update_payroll_periods on public.payroll_periods for update to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('payroll.manage','payroll.approve'))
  with check (school_id = app.current_school_id() and app.has_any_perm('payroll.manage','payroll.approve'));

drop policy if exists rls_select_payroll_entries on public.payroll_entries;
drop policy if exists rls_insert_payroll_entries on public.payroll_entries;
drop policy if exists rls_update_payroll_entries on public.payroll_entries;
create policy rls_select_payroll_entries on public.payroll_entries for select to authenticated
  using (exists (select 1 from payroll_periods p where p.id = payroll_period_id and p.school_id = app.current_school_id()) and app.has_any_perm('payroll.view','payroll.manage','payroll.approve'));
create policy rls_insert_payroll_entries on public.payroll_entries for insert to authenticated
  with check (exists (select 1 from payroll_periods p where p.id = payroll_period_id and p.school_id = app.current_school_id()) and app.has_perm('payroll.manage'));
create policy rls_update_payroll_entries on public.payroll_entries for update to authenticated
  using (exists (select 1 from payroll_periods p where p.id = payroll_period_id and p.school_id = app.current_school_id()) and app.has_any_perm('payroll.manage','payroll.approve'))
  with check (exists (select 1 from payroll_periods p where p.id = payroll_period_id and p.school_id = app.current_school_id()) and app.has_any_perm('payroll.manage','payroll.approve'));

drop policy if exists rls_select_fee_types on public.fee_types;
drop policy if exists rls_insert_fee_types on public.fee_types;
drop policy if exists rls_update_fee_types on public.fee_types;
create policy rls_select_fee_types on public.fee_types for select to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('finance.fees.view','finance.fees.manage'));
create policy rls_insert_fee_types on public.fee_types for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('finance.fees.manage'));
create policy rls_update_fee_types on public.fee_types for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('finance.fees.manage'))
  with check (school_id = app.current_school_id() and app.has_perm('finance.fees.manage'));

drop policy if exists rls_select_fee_plans on public.fee_plans;
drop policy if exists rls_insert_fee_plans on public.fee_plans;
drop policy if exists rls_update_fee_plans on public.fee_plans;
create policy rls_select_fee_plans on public.fee_plans for select to authenticated
  using (school_id = app.current_school_id() and app.has_any_perm('finance.fees.view','finance.fees.manage'));
create policy rls_insert_fee_plans on public.fee_plans for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('finance.fees.manage'));
create policy rls_update_fee_plans on public.fee_plans for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('finance.fees.manage'))
  with check (school_id = app.current_school_id() and app.has_perm('finance.fees.manage'));

drop policy if exists rls_select_fee_plan_items on public.fee_plan_items;
drop policy if exists rls_insert_fee_plan_items on public.fee_plan_items;
drop policy if exists rls_update_fee_plan_items on public.fee_plan_items;
create policy rls_select_fee_plan_items on public.fee_plan_items for select to authenticated
  using (exists (select 1 from fee_plans p where p.id = fee_plan_id and p.school_id = app.current_school_id()) and app.has_any_perm('finance.fees.view','finance.fees.manage'));
create policy rls_insert_fee_plan_items on public.fee_plan_items for insert to authenticated
  with check (exists (select 1 from fee_plans p where p.id = fee_plan_id and p.school_id = app.current_school_id()) and app.has_perm('finance.fees.manage'));
create policy rls_update_fee_plan_items on public.fee_plan_items for update to authenticated
  using (exists (select 1 from fee_plans p where p.id = fee_plan_id and p.school_id = app.current_school_id()) and app.has_perm('finance.fees.manage'))
  with check (exists (select 1 from fee_plans p where p.id = fee_plan_id and p.school_id = app.current_school_id()) and app.has_perm('finance.fees.manage'));

drop policy if exists rls_select_student_fees on public.student_fees;
drop policy if exists rls_insert_student_fees on public.student_fees;
drop policy if exists rls_update_student_fees on public.student_fees;
create policy rls_select_student_fees on public.student_fees for select to authenticated
  using (exists (select 1 from student_enrollments e join students s on s.id=e.student_id where e.id=student_fees.enrollment_id and s.school_id=app.current_school_id()) and app.has_any_perm('finance.fees.view','finance.fees.manage','finance.payments.view','finance.payments.create'));
create policy rls_insert_student_fees on public.student_fees for insert to authenticated
  with check (exists (select 1 from student_enrollments e join students s on s.id=e.student_id where e.id=student_fees.enrollment_id and s.school_id=app.current_school_id()) and app.has_perm('finance.fees.manage'));
create policy rls_update_student_fees on public.student_fees for update to authenticated
  using (exists (select 1 from student_enrollments e join students s on s.id=e.student_id where e.id=student_fees.enrollment_id and s.school_id=app.current_school_id()) and app.has_perm('finance.fees.manage'))
  with check (exists (select 1 from student_enrollments e join students s on s.id=e.student_id where e.id=student_fees.enrollment_id and s.school_id=app.current_school_id()) and app.has_perm('finance.fees.manage'));

drop policy if exists rls_select_installments on public.installments;
drop policy if exists rls_insert_installments on public.installments;
drop policy if exists rls_update_installments on public.installments;
create policy rls_select_installments on public.installments for select to authenticated
  using (exists (select 1 from student_fees f join student_enrollments e on e.id=f.enrollment_id join students s on s.id=e.student_id where f.id=installments.student_fee_id and s.school_id=app.current_school_id()) and app.has_any_perm('finance.fees.view','finance.fees.manage','finance.payments.view','finance.payments.create'));
create policy rls_insert_installments on public.installments for insert to authenticated
  with check (exists (select 1 from student_fees f join student_enrollments e on e.id=f.enrollment_id join students s on s.id=e.student_id where f.id=installments.student_fee_id and s.school_id=app.current_school_id()) and app.has_perm('finance.fees.manage'));
create policy rls_update_installments on public.installments for update to authenticated
  using (exists (select 1 from student_fees f join student_enrollments e on e.id=f.enrollment_id join students s on s.id=e.student_id where f.id=installments.student_fee_id and s.school_id=app.current_school_id()) and app.has_any_perm('finance.fees.manage','finance.payments.create'))
  with check (exists (select 1 from student_fees f join student_enrollments e on e.id=f.enrollment_id join students s on s.id=e.student_id where f.id=installments.student_fee_id and s.school_id=app.current_school_id()) and app.has_any_perm('finance.fees.manage','finance.payments.create'));

revoke all on all tables in schema public from anon;
grant select,insert,update on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema app to authenticated;
grant execute on function public.ensure_default_fee_catalog(uuid) to authenticated;
grant execute on function public.generate_installments(uuid, smallint, date, smallint) to authenticated;
revoke all on table public.employee_number_counters from public, anon, authenticated;
revoke execute on function public.next_employee_number(uuid) from public, anon, authenticated;
revoke insert,update,delete on audit_logs from authenticated;
revoke insert,update,delete on login_attempts from authenticated;
revoke insert,update,delete on document_versions from authenticated;

-- Audit logs are append-only to clients and readable only with audit.view.
drop policy if exists rls_select_audit_logs on public.audit_logs;
drop policy if exists audit_logs_read_authorized on public.audit_logs;
create policy audit_logs_read_authorized
  on public.audit_logs
  for select to authenticated
  using (app.has_perm('audit.view'));
revoke insert, update, delete on public.audit_logs from anon, authenticated;
grant select on public.audit_logs to authenticated;

-- Finance receipts are readable only by users with finance access; they are
-- created by the payment RPC and cannot be written directly by clients.
alter table public.finance_receipts enable row level security;
drop policy if exists rls_select_finance_receipts on public.finance_receipts;
create policy rls_select_finance_receipts
  on public.finance_receipts for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('finance.payments.view','finance.payments.create','finance.payments.reverse','finance.reports.view')
  );
revoke all on public.finance_receipts from anon, authenticated;
grant select on public.finance_receipts to authenticated;

-- Archive metadata is tenant-scoped and all state changes go through the
-- permission-checked archive/backup RPCs, never direct table writes.
drop policy if exists rls_select_archive_records on public.archive_records;
drop policy if exists rls_insert_archive_records on public.archive_records;
drop policy if exists rls_update_archive_records on public.archive_records;
drop policy if exists rls_delete_archive_records on public.archive_records;
create policy rls_select_archive_records
  on public.archive_records for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('archive.manage', 'archive.purge')
  );

drop policy if exists rls_select_archive_items on public.archive_items;
drop policy if exists rls_insert_archive_items on public.archive_items;
drop policy if exists rls_update_archive_items on public.archive_items;
drop policy if exists rls_delete_archive_items on public.archive_items;
create policy rls_select_archive_items
  on public.archive_items for select to authenticated
  using (
    exists (
      select 1 from public.archive_records ar
      where ar.id = coalesce(archive_items.archive_id, archive_items.archive_record_id)
        and ar.school_id = app.current_school_id()
        and app.has_any_perm('archive.manage', 'archive.purge')
    )
  );

drop policy if exists rls_select_backup_records on public.backup_records;
drop policy if exists rls_insert_backup_records on public.backup_records;
drop policy if exists rls_update_backup_records on public.backup_records;
drop policy if exists rls_delete_backup_records on public.backup_records;
create policy rls_select_backup_records
  on public.backup_records for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_perm('backup.manage')
  );

alter table public.notification_read_states enable row level security;
drop policy if exists rls_select_notification_read_states on public.notification_read_states;
drop policy if exists rls_insert_notification_read_states on public.notification_read_states;
drop policy if exists rls_update_notification_read_states on public.notification_read_states;
drop policy if exists rls_delete_notification_read_states on public.notification_read_states;
drop policy if exists notification_read_states_select_own on public.notification_read_states;
create policy notification_read_states_select_own
  on public.notification_read_states
  for select to authenticated
  using (
    user_id = auth.uid()
    and school_id = app.current_school_id()
    and app.is_active_user()
  );

alter table public.school_calendar_exceptions enable row level security;
drop policy if exists rls_select_school_calendar_exceptions on public.school_calendar_exceptions;
drop policy if exists rls_insert_school_calendar_exceptions on public.school_calendar_exceptions;
drop policy if exists rls_update_school_calendar_exceptions on public.school_calendar_exceptions;
drop policy if exists rls_delete_school_calendar_exceptions on public.school_calendar_exceptions;
create policy school_calendar_exceptions_select
  on public.school_calendar_exceptions
  for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_any_perm(
      'timetable.view',
      'timetable.manage',
      'attendance.students.manage',
      'attendance.employees.manage'
    )
    and exists (
      select 1 from public.academic_years y
      where y.id = school_calendar_exceptions.academic_year_id
        and y.school_id = school_calendar_exceptions.school_id
    )
  );
create policy school_calendar_exceptions_insert
  on public.school_calendar_exceptions
  for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_perm('timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = school_calendar_exceptions.academic_year_id
        and y.school_id = school_calendar_exceptions.school_id
    )
  );
create policy school_calendar_exceptions_update
  on public.school_calendar_exceptions
  for update to authenticated
  using (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_perm('timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = school_calendar_exceptions.academic_year_id
        and y.school_id = school_calendar_exceptions.school_id
    )
  )
  with check (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_perm('timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = school_calendar_exceptions.academic_year_id
        and y.school_id = school_calendar_exceptions.school_id
    )
  );
create policy school_calendar_exceptions_delete
  on public.school_calendar_exceptions
  for delete to authenticated
  using (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_perm('timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = school_calendar_exceptions.academic_year_id
        and y.school_id = school_calendar_exceptions.school_id
    )
  );

-- Replace the generic announcements policies with the actual audience rules.
drop policy if exists rls_select_announcements on public.announcements;
drop policy if exists rls_insert_announcements on public.announcements;
drop policy if exists rls_update_announcements on public.announcements;
create policy rls_select_announcements
  on public.announcements for select to authenticated
  using (
    school_id = app.current_school_id()
    and publish_at <= now()
    and (expires_at is null or expires_at >= now())
    and app.can_view_announcement(audience, department_id)
  );
create policy rls_insert_announcements
  on public.announcements for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and created_by = auth.uid()
    and app.has_perm('announcements.manage')
    and (expires_at is null or expires_at >= now())
    and app.can_view_announcement(audience, department_id)
    and (
      audience <> 'specific_department'
      or exists (
        select 1 from public.departments d
        where d.id = department_id
          and d.school_id = app.current_school_id()
      )
    )
  );
create policy rls_update_announcements
  on public.announcements for update to authenticated
  using (
    school_id = app.current_school_id()
    and created_by = auth.uid()
    and app.has_perm('announcements.manage')
    and publish_at <= now()
    and publish_at >= now() - interval '24 hours'
  )
  with check (
    school_id = app.current_school_id()
    and created_by = auth.uid()
    and app.has_perm('announcements.manage')
    and publish_at <= now()
    and publish_at >= now() - interval '24 hours'
    and (expires_at is null or expires_at >= now())
    and app.can_view_announcement(audience, department_id)
    and (
      audience <> 'specific_department'
      or exists (
        select 1 from public.departments d
        where d.id = department_id
          and d.school_id = app.current_school_id()
      )
    )
  );

-- The announcements trigger owns these immutable metadata columns. Keep a
-- narrow update grant so a client cannot reset the authorship/edit window.
revoke update on table public.announcements from authenticated;
grant update (
  title_ar, body_ar, audience, department_id, is_pinned, importance, expires_at
) on table public.announcements to authenticated;
revoke insert, update, delete on table public.archive_records from authenticated;
revoke insert, update, delete on table public.archive_items from authenticated;
revoke insert, update, delete on table public.backup_records from authenticated;

-- Apply a restrictive tenant boundary in addition to each table's operation
-- policies. NULL ownership is not treated as globally shared data, except for
-- legacy notifications which are individually addressed to the signed-in user.
do $$
declare
  v_table record;
begin
  for v_table in
    select distinct c.table_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public'
      and c.column_name = 'school_id'
      and t.table_type = 'BASE TABLE'
  loop
    execute format('alter table public.%I enable row level security', v_table.table_name);
    execute format('drop policy if exists tenant_school_scope_select on public.%I', v_table.table_name);
    if v_table.table_name = 'notifications' then
      execute format(
        'create policy tenant_school_scope_select on public.%I as restrictive for select to authenticated using (app.current_school_id() is not null and (school_id = app.current_school_id() or school_id is null))',
        v_table.table_name
      );
    else
      execute format(
        'create policy tenant_school_scope_select on public.%I as restrictive for select to authenticated using (app.current_school_id() is not null and school_id = app.current_school_id())',
        v_table.table_name
      );
    end if;
    execute format('drop policy if exists tenant_school_scope_insert on public.%I', v_table.table_name);
    execute format(
      'create policy tenant_school_scope_insert on public.%I as restrictive for insert to authenticated with check (app.current_school_id() is not null and school_id = app.current_school_id())',
      v_table.table_name
    );
    execute format('drop policy if exists tenant_school_scope_update on public.%I', v_table.table_name);
    execute format(
      'create policy tenant_school_scope_update on public.%I as restrictive for update to authenticated using (app.current_school_id() is not null and school_id = app.current_school_id()) with check (app.current_school_id() is not null and school_id = app.current_school_id())',
      v_table.table_name
    );
    execute format('drop policy if exists tenant_school_scope_delete on public.%I', v_table.table_name);
    execute format(
      'create policy tenant_school_scope_delete on public.%I as restrictive for delete to authenticated using (app.current_school_id() is not null and school_id = app.current_school_id())',
      v_table.table_name
    );
  end loop;
end;
$$;

-- School identity records have no school_id column, so scope them by ID.
alter table public.schools enable row level security;
drop policy if exists tenant_school_record_scope on public.schools;
create policy tenant_school_record_scope
  on public.schools as restrictive for all to authenticated
  using (app.current_school_id() is not null and id = app.current_school_id())
  with check (app.current_school_id() is not null and id = app.current_school_id());

-- Profiles and grants are readable only within the current school and are
-- mutated through the server-only user-management Edge Function.
drop policy if exists rls_select_profiles on public.profiles;
drop policy if exists rls_insert_profiles on public.profiles;
drop policy if exists rls_update_profiles on public.profiles;
drop policy if exists rls_delete_profiles on public.profiles;
create policy rls_select_profiles
  on public.profiles for select to authenticated
  using (
    app.is_active_user()
    and school_id = app.current_school_id()
    and (id = auth.uid() or app.has_any_perm('users.view', 'users.manage'))
  );

drop policy if exists rls_select_user_permissions on public.user_permissions;
drop policy if exists rls_insert_user_permissions on public.user_permissions;
drop policy if exists rls_update_user_permissions on public.user_permissions;
drop policy if exists rls_delete_user_permissions on public.user_permissions;
create policy rls_select_user_permissions
  on public.user_permissions for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = user_permissions.user_id
        and p.school_id = app.current_school_id()
        and (p.id = auth.uid() or app.has_any_perm('users.view', 'users.manage'))
    )
  );

drop policy if exists rls_select_notifications on public.notifications;
create policy rls_select_notifications
  on public.notifications for select to authenticated
  using (
    app.is_active_user()
    and (school_id = app.current_school_id() or school_id is null)
    and (user_id = auth.uid() or recipient_user_id = auth.uid())
  );

-- Year mutations require the dedicated permission; closure/reopening are
-- separately constrained by the guarded RPC and trigger.
drop policy if exists rls_select_academic_years on public.academic_years;
drop policy if exists rls_insert_academic_years on public.academic_years;
drop policy if exists rls_update_academic_years on public.academic_years;
drop policy if exists rls_delete_academic_years on public.academic_years;
create policy rls_select_academic_years
  on public.academic_years for select to authenticated
  using (school_id = app.current_school_id() and app.is_active_user());

-- Student portal identities use the minimal session RPC, never the full
-- administrative student row or the private Auth mapping table.
drop policy if exists rls_select_student_app_accounts on public.student_app_accounts;
drop policy if exists rls_insert_student_app_accounts on public.student_app_accounts;
drop policy if exists rls_update_student_app_accounts on public.student_app_accounts;
drop policy if exists rls_delete_student_app_accounts on public.student_app_accounts;
alter table public.student_app_accounts enable row level security;

drop policy if exists rls_select_students on public.students;
create policy rls_select_students
  on public.students for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm(
      'students.manage', 'students.view', 'students.create', 'students.edit',
      'students.archive', 'students.enrollment.manage'
    )
    and (educational_status <> 'withdrawn' or app.has_perm('students.archive'))
  );

-- Physical locations are scoped to the active school and academic/timetable roles.
alter table public.school_locations enable row level security;
drop policy if exists rls_select_school_locations on public.school_locations;
drop policy if exists rls_insert_school_locations on public.school_locations;
drop policy if exists rls_update_school_locations on public.school_locations;
drop policy if exists rls_delete_school_locations on public.school_locations;
create policy rls_select_school_locations
  on public.school_locations for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_any_perm('academics.structure.manage', 'timetable.view', 'timetable.manage')
  );
create policy rls_insert_school_locations
  on public.school_locations for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('academics.structure.manage', 'timetable.manage')
  );
create policy rls_update_school_locations
  on public.school_locations for update to authenticated
  using (
    school_id = app.current_school_id()
    and app.has_any_perm('academics.structure.manage', 'timetable.manage')
  )
  with check (
    school_id = app.current_school_id()
    and app.has_any_perm('academics.structure.manage', 'timetable.manage')
  );

-- class_subjects is a protected curriculum materialization; clients read it
-- only for their school and relevant timetable/employee/academic workflows.
drop policy if exists rls_select_class_subjects on public.class_subjects;
drop policy if exists rls_insert_class_subjects on public.class_subjects;
drop policy if exists rls_update_class_subjects on public.class_subjects;
drop policy if exists rls_delete_class_subjects on public.class_subjects;
create policy rls_select_class_subjects
  on public.class_subjects for select to authenticated
  using (
    exists (
      select 1 from public.classes c
      where c.id = class_subjects.class_id
        and c.school_id = app.current_school_id()
        and c.academic_year_id = class_subjects.academic_year_id
        and c.grade_id = class_subjects.grade_id
    )
    and app.has_any_perm(
      'employees.view', 'employees.edit', 'academics.structure.manage',
      'timetable.view', 'timetable.manage'
    )
  );

-- Direct teacher-assignment writes are disabled; the atomic RPC is the write path.
alter table public.employee_assignments enable row level security;
drop policy if exists rls_select_employee_assignments on public.employee_assignments;
drop policy if exists rls_insert_employee_assignments on public.employee_assignments;
drop policy if exists rls_update_employee_assignments on public.employee_assignments;
drop policy if exists rls_delete_employee_assignments on public.employee_assignments;
create policy rls_select_employee_assignments
  on public.employee_assignments for select to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_assignments.employee_id
        and e.school_id = app.current_school_id()
    )
    and app.has_any_perm(
      'employees.view', 'employees.edit', 'attendance.employees.view',
      'attendance.employees.manage', 'timetable.view', 'timetable.manage'
    )
  );

-- Periods and timetable entries are visible only in the current school/year.
drop policy if exists rls_select_timetable_periods on public.timetable_periods;
drop policy if exists rls_insert_timetable_periods on public.timetable_periods;
drop policy if exists rls_update_timetable_periods on public.timetable_periods;
drop policy if exists rls_delete_timetable_periods on public.timetable_periods;
create policy rls_select_timetable_periods
  on public.timetable_periods for select to authenticated
  using (
    school_id = app.current_school_id()
    and app.is_active_user()
    and app.has_any_perm('timetable.view', 'timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = timetable_periods.academic_year_id
        and y.school_id = app.current_school_id()
    )
  );
create policy rls_insert_timetable_periods
  on public.timetable_periods for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_perm('timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = timetable_periods.academic_year_id
        and y.school_id = app.current_school_id()
    )
  );
create policy rls_update_timetable_periods
  on public.timetable_periods for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('timetable.manage'))
  with check (
    school_id = app.current_school_id()
    and app.has_perm('timetable.manage')
    and exists (
      select 1 from public.academic_years y
      where y.id = timetable_periods.academic_year_id
        and y.school_id = app.current_school_id()
    )
  );

alter table public.timetable_entries enable row level security;
drop policy if exists rls_select_timetable_entries on public.timetable_entries;
drop policy if exists rls_insert_timetable_entries on public.timetable_entries;
drop policy if exists rls_update_timetable_entries on public.timetable_entries;
drop policy if exists rls_delete_timetable_entries on public.timetable_entries;
create policy rls_select_timetable_entries
  on public.timetable_entries for select to authenticated
  using (
    app.is_active_user()
    and app.has_any_perm('timetable.view', 'timetable.manage')
    and exists (
      select 1 from public.classes c
      join public.academic_years y
        on y.id = c.academic_year_id and y.school_id = c.school_id
      where c.id = timetable_entries.class_id
        and c.school_id = app.current_school_id()
        and c.academic_year_id = timetable_entries.academic_year_id
    )
    and exists (
      select 1 from public.timetable_periods p
      where p.id = timetable_entries.period_id
        and p.school_id = app.current_school_id()
        and p.academic_year_id = timetable_entries.academic_year_id
    )
  );

-- Tenant-scoped academic structure write policies and assessment visibility.
drop policy if exists rls_select_academic_stages on public.academic_stages;
drop policy if exists rls_insert_academic_stages on public.academic_stages;
drop policy if exists rls_update_academic_stages on public.academic_stages;
drop policy if exists rls_delete_academic_stages on public.academic_stages;
create policy rls_insert_academic_stages
  on public.academic_stages for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'));
create policy rls_select_academic_stages
  on public.academic_stages for select to authenticated
  using (school_id = app.current_school_id() and app.is_active_user());
create policy rls_update_academic_stages
  on public.academic_stages for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'))
  with check (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'));
create policy rls_delete_academic_stages
  on public.academic_stages for delete to authenticated
  using (school_id = app.current_school_id() and app.is_admin());

drop policy if exists rls_select_school_grades on public.school_grades;
drop policy if exists rls_insert_school_grades on public.school_grades;
drop policy if exists rls_update_school_grades on public.school_grades;
drop policy if exists rls_delete_school_grades on public.school_grades;
create policy rls_insert_school_grades
  on public.school_grades for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage')
    and exists (select 1 from public.academic_stages s
      where s.id = school_grades.stage_id and s.school_id = app.current_school_id())
  );
create policy rls_select_school_grades
  on public.school_grades for select to authenticated
  using (school_id = app.current_school_id() and app.is_active_user());
create policy rls_update_school_grades
  on public.school_grades for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'))
  with check (
    school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage')
    and exists (select 1 from public.academic_stages s
      where s.id = school_grades.stage_id and s.school_id = app.current_school_id())
  );
create policy rls_delete_school_grades
  on public.school_grades for delete to authenticated
  using (school_id = app.current_school_id() and app.is_admin());

drop policy if exists rls_select_subjects on public.subjects;
drop policy if exists rls_insert_subjects on public.subjects;
drop policy if exists rls_update_subjects on public.subjects;
drop policy if exists rls_delete_subjects on public.subjects;
create policy rls_insert_subjects
  on public.subjects for insert to authenticated
  with check (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'));
create policy rls_select_subjects
  on public.subjects for select to authenticated
  using (school_id = app.current_school_id() and app.is_active_user());
create policy rls_update_subjects
  on public.subjects for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'))
  with check (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'));
create policy rls_delete_subjects
  on public.subjects for delete to authenticated
  using (school_id = app.current_school_id() and app.is_admin());

drop policy if exists rls_insert_academic_years on public.academic_years;
drop policy if exists rls_update_academic_years on public.academic_years;
drop policy if exists rls_delete_academic_years on public.academic_years;
create policy rls_insert_academic_years
  on public.academic_years for insert to authenticated
  with check (school_id = app.current_school_id()
    and app.has_any_perm('academic_years.manage', 'academics.structure.manage'));
create policy rls_update_academic_years
  on public.academic_years for update to authenticated
  using (school_id = app.current_school_id()
    and app.has_any_perm('academic_years.manage', 'academics.structure.manage'))
  with check (school_id = app.current_school_id()
    and app.has_any_perm('academic_years.manage', 'academics.structure.manage'));
create policy rls_delete_academic_years
  on public.academic_years for delete to authenticated
  using (school_id = app.current_school_id() and app.is_admin());

drop policy if exists rls_select_classes on public.classes;
drop policy if exists rls_insert_classes on public.classes;
drop policy if exists rls_update_classes on public.classes;
drop policy if exists rls_delete_classes on public.classes;
create policy rls_insert_classes
  on public.classes for insert to authenticated
  with check (
    school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage')
    and exists (select 1 from public.academic_years y
      where y.id = classes.academic_year_id and y.school_id = app.current_school_id())
    and exists (select 1 from public.school_grades g
      where g.id = classes.grade_id and g.school_id = app.current_school_id())
  );
create policy rls_select_classes
  on public.classes for select to authenticated
  using (school_id = app.current_school_id() and app.is_active_user());
create policy rls_update_classes
  on public.classes for update to authenticated
  using (school_id = app.current_school_id() and app.has_perm('academics.structure.manage'))
  with check (
    school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage')
    and exists (select 1 from public.academic_years y
      where y.id = classes.academic_year_id and y.school_id = app.current_school_id())
    and exists (select 1 from public.school_grades g
      where g.id = classes.grade_id and g.school_id = app.current_school_id())
  );
create policy rls_delete_classes
  on public.classes for delete to authenticated
  using (school_id = app.current_school_id() and app.is_admin());

drop policy if exists rls_select_grade_subjects on public.grade_subjects;
drop policy if exists rls_insert_grade_subjects on public.grade_subjects;
drop policy if exists rls_update_grade_subjects on public.grade_subjects;
drop policy if exists rls_delete_grade_subjects on public.grade_subjects;
create policy rls_insert_grade_subjects
  on public.grade_subjects for insert to authenticated
  with check (
    app.has_perm('academics.structure.manage')
    and exists (
      select 1 from public.academic_years y
      join public.school_grades g on g.school_id = y.school_id
      join public.subjects s on s.school_id = y.school_id
      where y.id = grade_subjects.academic_year_id and g.id = grade_subjects.grade_id
        and s.id = grade_subjects.subject_id and y.school_id = app.current_school_id()
    )
  );
create policy rls_select_grade_subjects
  on public.grade_subjects for select to authenticated
  using (
    app.is_active_user()
    and exists (
      select 1 from public.academic_years y
      join public.school_grades g on g.school_id = y.school_id
      join public.subjects s on s.school_id = y.school_id
      where y.id = grade_subjects.academic_year_id and g.id = grade_subjects.grade_id
        and s.id = grade_subjects.subject_id and y.school_id = app.current_school_id()
    )
  );
create policy rls_update_grade_subjects
  on public.grade_subjects for update to authenticated
  using (app.has_perm('academics.structure.manage') and exists (
    select 1 from public.academic_years y where y.id = grade_subjects.academic_year_id
      and y.school_id = app.current_school_id()))
  with check (
    app.has_perm('academics.structure.manage')
    and exists (
      select 1 from public.academic_years y
      join public.school_grades g on g.school_id = y.school_id
      join public.subjects s on s.school_id = y.school_id
      where y.id = grade_subjects.academic_year_id and g.id = grade_subjects.grade_id
        and s.id = grade_subjects.subject_id and y.school_id = app.current_school_id()
    )
  );
create policy rls_delete_grade_subjects
  on public.grade_subjects for delete to authenticated
  using (app.is_admin() and exists (
    select 1 from public.academic_years y where y.id = grade_subjects.academic_year_id
      and y.school_id = app.current_school_id()));

drop policy if exists rls_select_assessment_types on public.assessment_types;
drop policy if exists rls_insert_assessment_types on public.assessment_types;
drop policy if exists rls_update_assessment_types on public.assessment_types;
drop policy if exists rls_delete_assessment_types on public.assessment_types;
create policy rls_select_assessment_types
  on public.assessment_types for select to authenticated
  using (school_id = app.current_school_id() and app.is_active_user());
create policy rls_insert_assessment_types
  on public.assessment_types for insert to authenticated
  with check (school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage'));
create policy rls_update_assessment_types
  on public.assessment_types for update to authenticated
  using (school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage'))
  with check (school_id = app.current_school_id()
    and app.has_perm('academics.structure.manage'));
create policy rls_delete_assessment_types
  on public.assessment_types for delete to authenticated
  using (school_id = app.current_school_id() and app.is_admin());
