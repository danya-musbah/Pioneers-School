create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, app, extensions, pg_temp
as $$
begin
	new.updated_at := now();
	return new;
end;
$$;

create trigger schools_updated_at before update on schools for each row execute function public.set_updated_at();
create trigger settings_updated_at before update on school_settings for each row execute function public.set_updated_at();
create trigger profiles_updated_at before update on profiles for each row execute function public.set_updated_at();
create trigger stages_updated_at before update on academic_stages for each row execute function public.set_updated_at();
create trigger grades_updated_at before update on school_grades for each row execute function public.set_updated_at();
create trigger terms_updated_at before update on academic_terms for each row execute function public.set_updated_at();
create trigger subjects_updated_at before update on subjects for each row execute function public.set_updated_at();
create trigger guardians_updated_at before update on guardians for each row execute function public.set_updated_at();
create trigger students_updated_at before update on students for each row execute function public.set_updated_at();
create trigger attendance_updated_at before update on student_attendance for each row execute function public.set_updated_at();
create trigger employees_updated_at before update on employees for each row execute function public.set_updated_at();
drop trigger if exists trg_employee_number_generation on public.employees;
create trigger trg_employee_number_generation
before insert or update on public.employees
for each row
execute function public.generate_employee_number();
create trigger payroll_entries_updated_at before update on payroll_entries for each row execute function public.set_updated_at();
create trigger documents_updated_at before update on documents for each row execute function public.set_updated_at();
create trigger announcements_updated_at before update on announcements for each row execute function public.set_updated_at();

create or replace function public.set_school_calendar_exceptions_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_school_calendar_exceptions_updated_at
before update on public.school_calendar_exceptions
for each row
execute function public.set_school_calendar_exceptions_updated_at();

create or replace function public.guard_announcement_metadata()
returns trigger
language plpgsql
set search_path = public, app, pg_temp
as $$
begin
	if tg_op = 'INSERT' then
		new.school_id := app.current_school_id();
		if auth.uid() is not null then
			new.created_by := auth.uid();
		end if;
		new.created_at := now();
		new.updated_at := now();
		return new;
	end if;

	if new.id is distinct from old.id
		or new.school_id is distinct from old.school_id
		or new.created_by is distinct from old.created_by
		or new.created_at is distinct from old.created_at
		or new.publish_at is distinct from old.publish_at then
		raise exception 'لا يمكن تغيير هوية الإعلان أو وقت نشره الأصلي.'
			using errcode = '42501';
	end if;
	return new;
end;
$$;

drop trigger if exists announcement_metadata_guard on public.announcements;
create trigger announcement_metadata_guard
before insert or update on public.announcements
for each row execute function public.guard_announcement_metadata();

drop trigger if exists current_year_guard on public.academic_years;
create trigger current_year_guard
before insert or update of is_current, school_id on public.academic_years
for each row when (new.is_current)
execute function app.tg_single_current_year();
create or replace function public.guard_academic_year_unique_name()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
	if new.name_ar is null or btrim(new.name_ar) = '' then
		return new;
	end if;

	if exists (
		select 1
		from public.academic_years ay
		where ay.school_id = new.school_id
			and lower(btrim(ay.name_ar)) = lower(btrim(new.name_ar))
			and ay.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
	) then
		raise exception 'اسم السنة الدراسية "%" مستخدم بالفعل في هذه المدرسة.', new.name_ar
			using errcode = '23505';
	end if;

	return new;
end;
$$;

drop trigger if exists trg_academic_year_unique_name on public.academic_years;
create trigger trg_academic_year_unique_name
before insert or update of school_id, name_ar on public.academic_years
for each row
execute function public.guard_academic_year_unique_name();

create unique index if not exists uq_academic_year_name_per_school
on public.academic_years (school_id, lower(btrim(name_ar)))
where name_ar is not null and btrim(name_ar) <> '';
create trigger leave_overlap before insert or update on leave_requests for each row execute function app.tg_leave_overlap();
create trigger payment_immutable before update on payments for each row execute function app.tg_payment_immutable();
create trigger students_no_delete before delete on students for each row execute function app.tg_block_delete();
create trigger enrollments_no_delete before delete on student_enrollments for each row execute function app.tg_block_delete();
create trigger payments_no_delete before delete on payments for each row execute function app.tg_block_delete();
create trigger grade_records_no_delete before delete on grade_records for each row execute function app.tg_block_delete();
create trigger document_versions_no_delete before delete on document_versions for each row execute function app.tg_block_delete();
create trigger archive_records_no_delete before delete on archive_records for each row execute function app.tg_block_delete();

drop trigger if exists audit_students_after_change on public.students;
create trigger audit_students_after_change
after insert or update or delete on public.students
for each row execute function app.audit_student_change();

drop trigger if exists audit_employees_after_change on public.employees;
create trigger audit_employees_after_change
after insert or update or delete on public.employees
for each row execute function app.audit_employee_change();

-- Bind school scope and transaction-authorized state transitions.
drop trigger if exists set_audit_log_school_scope on public.audit_logs;
create trigger set_audit_log_school_scope
before insert on public.audit_logs
for each row execute function app.set_audit_log_school_scope();

drop trigger if exists guard_academic_year_closure on public.academic_years;
create trigger guard_academic_year_closure
before insert or update of status on public.academic_years
for each row execute function app.guard_academic_year_closure();

drop trigger if exists guard_student_educational_status_transition on public.students;
create trigger guard_student_educational_status_transition
before insert or update on public.students
for each row execute function app.guard_student_educational_status_transition();

drop trigger if exists prevent_enrollment_for_withdrawn_student on public.student_enrollments;
create trigger prevent_enrollment_for_withdrawn_student
before insert on public.student_enrollments
for each row execute function app.prevent_enrollment_for_withdrawn_student();

drop trigger if exists prevent_withdrawn_attendance_insert on public.student_attendance;
create trigger prevent_withdrawn_attendance_insert
before insert on public.student_attendance
for each row execute function app.prevent_new_operation_for_withdrawn_student();
drop trigger if exists prevent_withdrawn_grade_insert on public.grade_records;
create trigger prevent_withdrawn_grade_insert
before insert on public.grade_records
for each row execute function app.prevent_new_operation_for_withdrawn_student();
drop trigger if exists prevent_withdrawn_student_fee_insert on public.student_fees;
create trigger prevent_withdrawn_student_fee_insert
before insert on public.student_fees
for each row execute function app.prevent_new_operation_for_withdrawn_student();

drop trigger if exists guard_profile_student_login_identifier on public.profiles;
create trigger guard_profile_student_login_identifier
before insert or update of username on public.profiles
for each row execute function app.guard_student_login_identifier_collision();
drop trigger if exists guard_student_profile_login_identifier on public.students;
create trigger guard_student_profile_login_identifier
before insert or update of student_number on public.students
for each row execute function app.guard_student_login_identifier_collision();
