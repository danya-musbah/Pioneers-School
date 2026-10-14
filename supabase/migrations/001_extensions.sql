create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists btree_gist with schema extensions;
create extension if not exists unaccent with schema extensions;

set search_path = public, extensions;

create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to authenticated;

-- Transaction-scoped authorization markers are private to guarded RPCs.
create table app.academic_year_closure_authorizations (
  transaction_id bigint not null,
  academic_year_id uuid not null,
  actor_id uuid not null,
  primary key (transaction_id, academic_year_id)
);
create table app.student_file_transition_authorizations (
  transaction_id bigint not null,
  student_id uuid not null,
  actor_id uuid not null,
  target_status text not null,
  primary key (transaction_id, student_id)
);
revoke all on app.academic_year_closure_authorizations from public, anon, authenticated;
revoke all on app.student_file_transition_authorizations from public, anon, authenticated;

create domain app.money_amount as numeric(14,2) check (value is null or value >= 0);
create domain app.percentage as numeric(6,3) check (value is null or (value >= 0 and value <= 100));

create type app.exam_round as enum ('first','second');
create type app.grade_record_status as enum ('draft','entered','reviewed','approved','corrected');
create type app.result_status as enum ('calculated','under_review','approved','closed');
create type app.pass_decision as enum ('pass','fail','second_round','incomplete');
create type app.payment_method as enum ('cash','bank_transfer','cheque','card','other');
create type app.payment_status as enum ('completed','reversed','voided','refunded');
create type app.installment_status as enum ('pending','partial','paid','overdue','cancelled');
create type app.social_case_status as enum ('open','in_progress','monitoring','closed');
create type app.social_case_priority as enum ('low','medium','high','urgent');
create type app.announcement_audience as enum ('all_staff','admins_only','specific_department');
create type app.notification_type as enum ('info','warning','urgent','payment_due','leave_request','grade_pending','document_pending','archive_reminder','system');
create type app.document_status as enum ('draft','pending_approval','approved','rejected','archived');
create type app.document_category as enum ('certificate','transcript','enrollment_letter','transfer_letter','warning_letter','contract','id_card','report_card','financial_statement','archive_manifest','other');
create type app.employment_status as enum ('active','on_leave','suspended','terminated','resigned','retired','archived');
create type app.leave_status as enum ('pending','approved','rejected','cancelled');
create type app.payroll_status as enum ('draft','calculated','approved','paid','cancelled');
create type app.archive_state as enum ('generated','saved','verified','purge_eligible','purged');
create type app.announcement_importance as enum ('low','normal','important','urgent');

create table schools (
 id uuid primary key default gen_random_uuid(), name_ar text not null, name_en text,
 official_name_ar text, school_type text, address text, city text, region text, country text,
 phone text, phone_alt text, email text, website text, license_number text,
 logo_path text, logo_storage_path text, currency_code text default 'LYD', currency_label_ar text default 'دينار ليبي',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table school_settings (
 id smallint primary key default 1 check (id=1), school_id uuid references schools(id) on delete restrict,
 name_ar text not null default '', name_en text, official_name_ar text, school_type text,
 address text, city text, region text, country text, phone text, phone_alt text, email text, website text,
 license_number text, registration_number text, tax_number text,
 logo_path text, logo_storage_path text, currency_code text default 'LYD', currency_label_ar text default 'دينار ليبي',
 max_upload_mb integer not null default 5, max_upload_size_mb integer not null default 5, photo_max_px integer default 2400,
 audit_retention_months integer not null default 36, archive_reminder_days integer not null default 30,
 week_start_day smallint default 0, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table profiles (
 id uuid primary key references auth.users(id) on delete cascade, school_id uuid references schools(id) on delete restrict,
 employee_id uuid, username text unique, email text, full_name text not null, phone text,
 role text not null default 'staff' check (role in ('admin','staff','employee')), status text not null default 'active' check (status in ('active','inactive','suspended','terminated')),
 must_change_password boolean not null default false, password_changed_at timestamptz, last_login_at timestamptz,
 created_by uuid references auth.users(id), version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index profiles_email_case_insensitive_uq
  on public.profiles (lower(btrim(email)))
  where email is not null and btrim(email) <> '';
create table permissions (key text primary key, category text not null, label text not null, group_ar text, label_ar text, description_ar text, is_sensitive boolean not null default false, sort_order integer not null default 100);
create table user_permissions (id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(id) on delete cascade, permission text not null references permissions(key) on delete restrict, permission_code text, granted_by uuid references profiles(id), granted_at timestamptz not null default now(), unique(user_id,permission));
create table audit_logs (id bigint generated always as identity primary key, user_id uuid references profiles(id), actor_id uuid references auth.users(id), actor_label text, action text not null, entity_type text not null, entity_id text, academic_year_id uuid, school_id uuid references schools(id) on delete restrict, old_value jsonb, new_value jsonb, description text, metadata jsonb, occurred_at timestamptz not null default now(), created_at timestamptz not null default now());
create table idempotency_keys (key text primary key, operation text not null, actor_id uuid, request_hash text, result jsonb, status text not null default 'in_progress' check(status in ('in_progress','completed','failed')), created_at timestamptz not null default now(), completed_at timestamptz);
create table schema_version (id smallint primary key default 1 check(id=1), schema_version text not null, app_version text not null, applied_at timestamptz not null default now());

create table academic_years (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, code text not null, label text, name_ar text, start_date date not null, end_date date not null, status text not null default 'draft' check(status in ('draft','active','closed','archived','مسودة','نشطة','مغلقة','مؤرشفة')), is_current boolean not null default false, closed_at timestamptz, created_by uuid references profiles(id), version integer not null default 1, created_at timestamptz not null default now(), unique(school_id,code));
create table academic_stages (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, code text, name_ar text not null, name_en text, sort_order integer not null default 0, is_active boolean not null default true, is_archived boolean not null default false, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(school_id,name_ar));
create table school_grades (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, stage_id uuid not null references academic_stages(id) on delete restrict, code text not null unique, name_ar text not null, name_en text, level_number smallint not null unique, is_final_grade boolean not null default false, is_certificate_grade boolean not null default false, is_active boolean not null default true, is_archived boolean not null default false, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table subjects (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, code text, name_ar text not null, name_en text, is_core boolean not null default true, sort_order integer not null default 0, is_active boolean not null default true, is_archived boolean not null default false, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(school_id,name_ar));
create table academic_terms (id uuid primary key default gen_random_uuid(), academic_year_id uuid not null references academic_years(id) on delete restrict, term_number smallint not null check(term_number between 1 and 4), name_ar text not null, start_date date not null, end_date date not null, actual_study_days integer, is_current boolean not null default false, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(academic_year_id,term_number));
create table classes (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, academic_year_id uuid not null references academic_years(id) on delete restrict, grade_id uuid not null references school_grades(id) on delete restrict, section_code text, section_name text, name_ar text not null default '', room_name text, room text, capacity integer check(capacity is null or capacity >= 0), homeroom_employee_id uuid, is_active boolean not null default true, is_archived boolean not null default false, version integer not null default 1, created_at timestamptz not null default now(), unique(academic_year_id,grade_id,section_code), unique(academic_year_id,grade_id,name_ar));
create table grade_subjects (id uuid primary key default gen_random_uuid(), academic_year_id uuid not null references academic_years(id) on delete restrict, grade_id uuid not null references school_grades(id) on delete restrict, subject_id uuid not null references subjects(id) on delete restrict, max_score numeric(6,2) not null default 100 check(max_score>0), pass_percentage app.percentage not null default 50, coursework_weight app.percentage not null default 30, final_exam_weight app.percentage not null default 70, final_exam_min_pct app.percentage not null default 40, weekly_periods smallint check(weekly_periods is null or weekly_periods >= 0), assessment_type text not null default 'continuous' check(assessment_type in ('continuous', 'not_examined')), exam_included boolean not null default true, is_active boolean not null default true, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(academic_year_id,grade_id,subject_id), check(coursework_weight+final_exam_weight=100));
create table class_subjects (id uuid primary key default gen_random_uuid(), class_id uuid references classes(id) on delete cascade, academic_year_id uuid references academic_years(id) on delete restrict, grade_id uuid references school_grades(id) on delete restrict, subject_id uuid references subjects(id) on delete restrict, grade_subject_id uuid references grade_subjects(id) on delete cascade, employee_id uuid, weekly_periods smallint, is_active boolean not null default true, created_at timestamptz not null default now(), unique(class_id,subject_id));

create table guardians (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, full_name text not null, national_id text, phone text, phone_alt text, phone_secondary text, email text, address text, city text, occupation text, employer text, workplace_phone text, notes text, guardian_app_login_status text not null default 'not_created' check (guardian_app_login_status in ('not_created','active','reset_required','disabled')), guardian_app_login_enabled boolean not null default false, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create sequence student_number_seq start with 100000 increment by 1 no minvalue no maxvalue no cycle;
create table students (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id) on delete restrict, student_number text not null, file_number text, registration_number text, registration_date date default current_date, graduation_date date, full_name text not null default '', full_name_en text, first_name text, father_name text, grandfather_name text, family_name text, mother_name text, gender text, date_of_birth date, place_of_birth text, nearest_relative_name text, nearest_relative_relationship text, nearest_relative_phone text, religion text check (religion is null or religion in ('مسلم/ة', 'مسيحي/ة', 'يهودي/ة')), national_id text, phone text, father_phone text, mother_phone text, address text, residence_address text, city text, region text, previous_school text, nationality text default 'ليبي', health_status text, health_conditions text[] not null default '{}', disability_needs text[] not null default '{}', health_notes text, social_status text, photo_path text, photo_storage_path text, avatar_path text, avatar_storage_path text, student_app_login_status text not null default 'not_created' check (student_app_login_status in ('not_created','active','reset_required','disabled')), student_app_login_enabled boolean not null default false, educational_status text not null default 'active', file_status text not null default 'at_school', admission_type text default 'نظامي' check (admission_type is null or admission_type in ('نظامي','مستجد','منقول','أخرى')), is_archived boolean not null default false, is_delinquent boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(student_number));
create table public.student_app_accounts (
  student_id uuid primary key references public.students(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete restrict,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  login_email text not null unique,
  is_enabled boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  credential_issued_at timestamptz,
  credential_delivery_pending boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (login_email = lower(btrim(login_email))),
  check (auth_user_id is not null or not is_enabled)
);
create table student_guardians (id uuid primary key default gen_random_uuid(), student_id uuid not null references students(id) on delete restrict, guardian_id uuid not null references guardians(id) on delete restrict, relationship text, is_primary boolean not null default false, is_primary_contact boolean not null default false, can_collect_file boolean not null default false, created_at timestamptz default now(), unique(student_id,guardian_id));
create table student_enrollments (id uuid primary key default gen_random_uuid(), student_id uuid not null references students(id) on delete restrict, academic_year_id uuid not null references academic_years(id) on delete restrict, grade_id uuid not null references school_grades(id) on delete restrict, class_id uuid references classes(id) on delete restrict, enrollment_date date not null default current_date, withdrawal_date date, roll_number smallint, outcome text not null default 'in_progress', enrollment_status text default 'نشط', is_new_student boolean not null default false, is_repeat boolean not null default false, created_at timestamptz not null default now(), unique(student_id,academic_year_id));
create table student_file_transactions (id uuid primary key default gen_random_uuid(), student_id uuid not null references students(id) on delete restrict, academic_year_id uuid references academic_years(id) on delete restrict, action text not null, previous_status text, new_status text, transaction_date date not null default current_date, reason text not null, delivered_to_name text, delivered_to_relationship text, delivered_to_id_number text, delivered_to_guardian_id uuid references guardians(id), handled_by uuid references auth.users(id), notes text, created_at timestamptz not null default now());
create table student_notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  note_type text not null default 'general' check (note_type in ('general','social','medical','academic')),
  note_text text not null,
  is_sensitive boolean not null default false,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table student_file_checklist_templates (
  id uuid primary key default gen_random_uuid(),
  school_id uuid references schools(id) on delete restrict,
  code text not null,
  category text not null default 'core' check (category in ('core','family','international','grade')),
  label_ar text not null,
  sort_order integer not null default 0,
  is_required boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(school_id, code)
);
create table student_file_checklist_items (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  template_id uuid references student_file_checklist_templates(id) on delete set null,
  item_code text not null,
  item_label text not null,
  category text not null default 'core',
  is_received boolean not null default false,
  received_at date,
  notes text,
  file_path text,
  storage_key text,
  mime_type text,
  file_name text,
  file_size_bytes bigint,
  updated_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(student_id, item_code)
);

create table attendance_statuses (code text primary key, label_ar text not null, counts_present boolean not null default false, counts_as_present boolean not null default false, is_excused boolean not null default false, sort_order smallint not null default 100, is_active boolean not null default true);
create table student_attendance (id uuid primary key default gen_random_uuid(), student_id uuid not null references students(id) on delete restrict, enrollment_id uuid not null references student_enrollments(id) on delete restrict, academic_year_id uuid references academic_years(id) on delete restrict, class_id uuid references classes(id) on delete restrict, term_id uuid references academic_terms(id), attendance_date date not null, status text, status_code text references attendance_statuses(code), minutes_late smallint, excuse_note text, notes text, recorded_by uuid references profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(enrollment_id,attendance_date));
create table employee_attendance_statuses (code text primary key, label_ar text not null, counts_present boolean not null default false, is_paid boolean not null default true, sort_order smallint default 100, is_active boolean default true);

create table assessment_types (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), code text, name_ar text, label_ar text, component text, weight_percent numeric(5,2) default 0, sort_order integer default 0, is_active boolean default true, unique(school_id,name_ar));
create table exams (id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), academic_year_id uuid not null references academic_years(id), term_id uuid references academic_terms(id), class_id uuid references classes(id), grade_id uuid references school_grades(id), grade_subject_id uuid references grade_subjects(id), subject_id uuid references subjects(id), assessment_type_id uuid references assessment_types(id), assessment_type text, title_ar text not null, round app.exam_round not null default 'first', max_score numeric(6,2) not null default 100 check(max_score>0), exam_date date, status text not null default 'draft', created_at timestamptz not null default now());
create table grade_records (id uuid primary key default gen_random_uuid(), exam_id uuid not null references exams(id) on delete restrict, enrollment_id uuid not null references student_enrollments(id) on delete restrict, score numeric(6,2), max_score numeric(6,2), is_absent boolean not null default false, status app.grade_record_status not null default 'draft', notes text, entered_by uuid references auth.users(id), approved_by uuid references auth.users(id), entered_at timestamptz, approved_at timestamptz, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(exam_id,enrollment_id), check(score is null or score>=0), check(is_absent or score is not null));
create table subject_results (id uuid primary key default gen_random_uuid(), enrollment_id uuid not null references student_enrollments(id), grade_subject_id uuid not null references grade_subjects(id), round app.exam_round not null default 'first', coursework_score numeric(6,2), final_exam_score numeric(6,2), total_score numeric(6,2), max_score numeric(6,2) not null, percentage app.percentage, decision app.pass_decision not null default 'incomplete', decision_reason text, calculated_at timestamptz default now(), version integer default 1, created_at timestamptz default now(), updated_at timestamptz default now(), unique(enrollment_id,grade_subject_id,round));
create table term_results (id uuid primary key default gen_random_uuid(), enrollment_id uuid not null references student_enrollments(id), academic_year_id uuid not null references academic_years(id), round app.exam_round not null default 'first', total_score numeric(8,2), max_total numeric(8,2), average numeric(6,2), percentage app.percentage, grade_label text, attendance_pct app.percentage, decision app.pass_decision not null default 'incomplete', decision_reason text, failed_subjects smallint default 0, class_rank smallint, status app.result_status not null default 'calculated', approved_by uuid references auth.users(id), approved_at timestamptz, rules_snapshot jsonb, calculated_at timestamptz default now(), version integer default 1, created_at timestamptz default now(), updated_at timestamptz default now(), unique(enrollment_id,round));
create table grade_bands(id uuid primary key default gen_random_uuid(), label_ar text not null, min_pct app.percentage not null, max_pct app.percentage not null, sort_order smallint default 100, check(max_pct>min_pct));

create table departments(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), code text, name_ar text not null, sort_order integer default 0, is_active boolean not null default true, version integer not null default 1, created_at timestamptz default now(), unique(school_id,name_ar));
create table job_titles(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), code text, name_ar text not null, category text, department_id uuid references departments(id), implies_teaching boolean default false, sort_order integer default 0, is_active boolean not null default true, version integer not null default 1, created_at timestamptz default now(), updated_at timestamptz not null default now(), unique(school_id,name_ar));
create table employees(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), profile_id uuid unique references profiles(id) on delete set null, employee_number text not null, full_name text not null default '', first_name text, father_name text, family_name text, gender text, national_id text, phone text, phone_alt text, email text, address text, city text, qualification text, specialization text, contract_type text, date_of_birth date, hire_date date, hiring_date date, termination_date date, termination_reason text, basic_salary numeric(12,2) default 0, department_id uuid references departments(id), job_title_id uuid references job_titles(id), is_teacher boolean default false, employment_status app.employment_status default 'active', is_archived boolean default false, photo_storage_path text, notes text, version integer default 1, created_at timestamptz default now(), updated_at timestamptz default now(), unique(school_id,employee_number));
create table employee_document_checklist_items (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete restrict,
  item_code text not null,
  item_label text not null,
  is_received boolean not null default false,
  received_at date,
  updated_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(employee_id, item_code)
);
alter table profiles add constraint profiles_employee_fk foreign key(employee_id) references employees(id) on delete set null;
alter table classes add constraint classes_homeroom_fk foreign key(homeroom_employee_id) references employees(id) on delete set null;
alter table class_subjects add constraint class_subjects_employee_fk foreign key(employee_id) references employees(id) on delete set null;
create table employee_attendance (id uuid primary key default gen_random_uuid(), employee_id uuid not null references employees(id) on delete restrict, attendance_date date not null, status text, status_code text, check_in time, check_out time, minutes_late smallint not null default 0, excuse_note text, notes text, recorded_by uuid references profiles(id), created_at timestamptz not null default now(), unique(employee_id,attendance_date));
create table employee_assignments(id uuid primary key default gen_random_uuid(), employee_id uuid references employees(id), academic_year_id uuid references academic_years(id), class_subject_id uuid references class_subjects(id) on delete cascade, role_note text, weekly_periods smallint, is_active boolean default true, version integer default 1, created_at timestamptz default now(), updated_at timestamptz default now(), unique(employee_id,class_subject_id));
create table leave_types(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), code text, name_ar text not null, is_paid boolean default true, default_annual_entitlement_days integer, annual_entitlement_days integer, requires_document boolean default false, sort_order integer default 0, is_active boolean not null default true, version integer not null default 1, unique(school_id,name_ar));
create table leave_requests(id uuid primary key default gen_random_uuid(), employee_id uuid references employees(id), leave_type_id uuid references leave_types(id), start_date date not null, end_date date not null, days_count integer generated always as (end_date-start_date+1) stored, reason text, document_path text, status app.leave_status default 'pending', requested_at timestamptz not null default now(), reviewed_by uuid references profiles(id), reviewed_at timestamptz, review_note text, review_notes text, version integer not null default 1, created_at timestamptz default now(), check(end_date>=start_date));

create table payroll_periods(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), year integer not null default extract(year from current_date)::integer, month smallint not null default extract(month from current_date)::smallint, label_ar text, label text, period_start date not null default current_date, period_end date not null default current_date, status app.payroll_status default 'draft', approved_by uuid references profiles(id), approved_at timestamptz, version integer not null default 1, created_at timestamptz default now(), check(month between 1 and 12), check(period_end>=period_start));
create table payroll_entries(id uuid primary key default gen_random_uuid(), payroll_period_id uuid not null references payroll_periods(id), employee_id uuid not null references employees(id), basic_salary numeric(12,2) not null default 0 check(basic_salary>=0), allowances numeric(12,2) not null default 0 check(allowances>=0), additions numeric(12,2) not null default 0 check(additions>=0), incentives numeric(12,2) not null default 0 check(incentives>=0), overtime numeric(12,2) not null default 0 check(overtime>=0), deductions numeric(12,2) not null default 0 check(deductions>=0), advances numeric(12,2) not null default 0 check(advances>=0), absence_days numeric(8,2) not null default 0 check(absence_days>=0), unpaid_leave_days numeric(8,2) not null default 0 check(unpaid_leave_days>=0), net_salary numeric(12,2) generated always as (basic_salary+allowances+additions+incentives+overtime-deductions-advances) stored, notes text, version integer default 1, created_at timestamptz default now(), updated_at timestamptz default now(), unique(payroll_period_id,employee_id));

create table fee_types(
  id uuid primary key default gen_random_uuid(),
  school_id uuid references schools(id),
  code text,
  name_ar text not null,
  is_recurring boolean default false,
  is_active boolean not null default true,
  sort_order integer default 0,
  gender_scope text,
  allow_installments boolean not null default true,
  default_installment_count smallint not null default 1,
  check (gender_scope is null or gender_scope in ('male','female')),
  check (default_installment_count > 0),
  unique(school_id,name_ar)
);
create table fee_plans(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), academic_year_id uuid references academic_years(id), grade_id uuid references school_grades(id), name_ar text not null, created_at timestamptz default now(), unique(academic_year_id,grade_id));
create table fee_plan_items(
  id uuid primary key default gen_random_uuid(),
  fee_plan_id uuid not null references fee_plans(id),
  fee_type_id uuid not null references fee_types(id),
  amount numeric(14,2) not null default 0 check(amount>=0),
  due_date date,
  is_mandatory boolean not null default true,
  is_active boolean not null default true,
  notes text,
  default_installment_count smallint not null default 1,
  created_at timestamptz default now(),
  check (default_installment_count > 0),
  unique(fee_plan_id,fee_type_id)
);
create table student_fees(
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references student_enrollments(id),
  academic_year_id uuid not null references academic_years(id),
  fee_plan_id uuid references fee_plans(id),
  fee_type_id uuid references fee_types(id) on delete restrict,
  total_amount numeric(14,2) not null default 0 check(total_amount>=0),
  default_amount numeric(14,2) default null check(default_amount is null or default_amount >= 0),
  discount_amount numeric(14,2) not null default 0 check(discount_amount>=0),
  exemption_amount numeric(14,2) not null default 0 check(exemption_amount>=0),
  net_amount numeric(14,2) generated always as(greatest(total_amount-discount_amount-exemption_amount,0)) stored,
  discount_reason text,
  price_override_reason text,
  is_mandatory boolean not null default true,
  notes text,
  version integer default 1,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table installments(id uuid primary key default gen_random_uuid(), student_fee_id uuid not null references student_fees(id), student_fee_assignment_id uuid, fee_type_id uuid references fee_types(id), sequence_number smallint not null default 1 check(sequence_number>0), due_date date, amount numeric(14,2) not null default 0 check(amount>=0), discount_amount numeric(14,2) not null default 0 check(discount_amount>=0), penalty_amount numeric(14,2) not null default 0 check(penalty_amount>=0), paid_amount numeric(14,2) not null default 0 check(paid_amount>=0), net_due numeric(14,2) generated always as(greatest(amount-discount_amount+penalty_amount,0)) stored, remaining_amount numeric(14,2) generated always as(greatest(amount-discount_amount+penalty_amount-paid_amount,0)) stored, status app.installment_status default 'pending', created_at timestamptz default now(), check(paid_amount<=amount-discount_amount+penalty_amount+0.01));
create table payments(id uuid primary key default gen_random_uuid(), school_id uuid not null references schools(id), student_id uuid references students(id), academic_year_id uuid references academic_years(id), installment_id uuid references installments(id), amount numeric(14,2) not null check(amount>0), method app.payment_method default 'cash', payment_method text, payment_date date not null default current_date, payer_name text, reference text, notes text, bank_name text, receipt_number text not null, idempotency_key text, status app.payment_status default 'completed', reverses_payment_id uuid references payments(id), created_by uuid references profiles(id), created_at timestamptz default now(), unique(school_id,receipt_number), unique(school_id,idempotency_key));
alter table public.fee_types
  add column if not exists gender_scope text,
  add column if not exists allow_installments boolean not null default true,
  add column if not exists default_installment_count smallint not null default 1;
alter table public.fee_plan_items
  add column if not exists default_installment_count smallint not null default 1;
alter table public.student_fees
  add column if not exists fee_type_id uuid references public.fee_types(id) on delete restrict,
  add column if not exists default_amount numeric(14,2),
  add column if not exists price_override_reason text,
  add column if not exists is_mandatory boolean not null default true;
alter table public.payments
  add column if not exists bank_name text;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'fee_types_gender_scope_check'
      and conrelid = 'public.fee_types'::regclass
  ) then
    alter table public.fee_types
      add constraint fee_types_gender_scope_check
      check (gender_scope is null or gender_scope in ('male','female'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'fee_types_default_installments_check'
      and conrelid = 'public.fee_types'::regclass
  ) then
    alter table public.fee_types
      add constraint fee_types_default_installments_check
      check (default_installment_count > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'fee_plan_items_default_installments_check'
      and conrelid = 'public.fee_plan_items'::regclass
  ) then
    alter table public.fee_plan_items
      add constraint fee_plan_items_default_installments_check
      check (default_installment_count > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'student_fees_default_amount_nonnegative'
      and conrelid = 'public.student_fees'::regclass
  ) then
    alter table public.student_fees
      add constraint student_fees_default_amount_nonnegative
      check (default_amount is null or default_amount >= 0);
  end if;
end $$;
create table finance_receipt_counters(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  unique(school_id)
);
create table employee_number_counters(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null unique references schools(id) on delete cascade,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now()
);
create table expense_categories(id uuid primary key default gen_random_uuid(), code text unique, name_ar text not null, is_active boolean default true);
create table expenses(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), academic_year_id uuid references academic_years(id), category text, category_id uuid references expense_categories(id), amount numeric(14,2) not null check(amount>0), expense_date date default current_date, description text, payee text, method text default 'cash', reference_number text, document_path text, status text default 'recorded', void_reason text, created_by uuid references profiles(id), recorded_by uuid references profiles(id), created_at timestamptz default now(), updated_at timestamptz default now());
create index expenses_category_id_idx on expenses(category_id);
create index expenses_expense_date_idx on expenses(expense_date desc);
create table if not exists finance_receipts (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete restrict,
  payment_id uuid not null unique references payments(id) on delete restrict,
  receipt_number text not null,
  snapshot jsonb not null,
  issued_by uuid references profiles(id),
  issued_at timestamptz not null default now(),
  unique(school_id, receipt_number)
);
create index if not exists idx_finance_receipts_issued on finance_receipts(school_id, issued_at desc);

INSERT INTO public.finance_receipts(
  school_id, payment_id, receipt_number, snapshot, issued_by, issued_at
)
SELECT
  p.school_id,
  p.id,
  p.receipt_number,
  jsonb_build_object(
    'receipt_number', p.receipt_number,
    'payment_id', p.id,
    'student_id', p.student_id,
    'student_name', s.full_name,
    'student_number', s.student_number,
    'academic_year_id', p.academic_year_id,
    'academic_year', COALESCE(y.name_ar, y.code),
    'fee_type', COALESCE(ft.name_ar, 'رسوم سابقة غير مصنفة'),
    'installment_number', i.sequence_number,
    'due_date', i.due_date,
    'payer_name', p.payer_name,
    'amount', p.amount,
    'method', COALESCE(p.payment_method, p.method::text),
    'reference', p.reference,
    'notes', p.notes,
    'school', jsonb_build_object(
      'name_ar', ss.name_ar,
      'official_name_ar', ss.official_name_ar,
      'address', ss.address,
      'phone', ss.phone,
      'phone_alt', ss.phone_alt,
      'email', ss.email,
      'logo_storage_path', ss.logo_storage_path
    )
  ),
  p.created_by,
  p.created_at
FROM public.payments p
LEFT JOIN public.students s ON s.id = p.student_id
LEFT JOIN public.academic_years y ON y.id = p.academic_year_id
LEFT JOIN public.installments i ON i.id = p.installment_id
LEFT JOIN public.fee_types ft ON ft.id = i.fee_type_id
LEFT JOIN public.school_settings ss ON ss.id = 1
ON CONFLICT (payment_id) DO NOTHING;

UPDATE public.fee_types
SET gender_scope = 'male', allow_installments = false, default_installment_count = 1
WHERE code = 'uniform_boys' AND gender_scope IS NULL;
UPDATE public.fee_types
SET gender_scope = 'female', allow_installments = false, default_installment_count = 1
WHERE code = 'uniform_girls' AND gender_scope IS NULL;

ALTER TABLE public.student_fees
  DROP CONSTRAINT IF EXISTS student_fees_enrollment_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_student_fees_legacy_enrollment
  ON public.student_fees(enrollment_id)
  WHERE fee_type_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_student_fees_enrollment_fee_type
  ON public.student_fees(enrollment_id, fee_type_id)
  WHERE fee_type_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_student_fees_fee_type
  ON public.student_fees(fee_type_id)
  WHERE fee_type_id IS NOT NULL;

create table timetable_periods(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), academic_year_id uuid references academic_years(id), period_number integer not null, name_ar text, start_time time not null, end_time time not null, is_active boolean default true, is_break boolean default false, unique(school_id,period_number), check(end_time>start_time));
create table week_days(day_number smallint primary key check(day_number between 0 and 6), name_ar text not null, is_school_day boolean default true, sort_order smallint not null);
create table teacher_availability(id uuid primary key default gen_random_uuid(), employee_id uuid references employees(id), academic_year_id uuid references academic_years(id), day_number smallint references week_days(day_number), period_id uuid references timetable_periods(id), is_available boolean default true, reason text, unique(employee_id,academic_year_id,day_number,period_id));
create table timetable_entries(id uuid primary key default gen_random_uuid(), academic_year_id uuid references academic_years(id), day_number smallint, day_of_week text, period_id uuid references timetable_periods(id), class_id uuid references classes(id), class_subject_id uuid references class_subjects(id), subject_id uuid references subjects(id), employee_id uuid references employees(id), room text, room_name text, is_active boolean default true, version integer default 1, created_at timestamptz default now(), created_by uuid references profiles(id));

create table social_case_categories(id uuid primary key default gen_random_uuid(), code text unique, name_ar text not null, is_active boolean default true);
create table social_cases(
  id uuid primary key default gen_random_uuid(),
  school_id uuid references schools(id),
  student_id uuid references students(id),
  category_id uuid references social_case_categories(id),
  academic_year_id uuid references academic_years(id),
  case_type text,
  category text,
  priority app.social_case_priority default 'medium',
  status app.social_case_status default 'open',
  summary text,
  opened_date date default current_date,
  opened_by uuid references profiles(id),
  assigned_to uuid references profiles(id),
  closed_date date,
  closure_summary text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  version integer default 1
);
create table social_case_notes(id uuid primary key default gen_random_uuid(), case_id uuid references social_cases(id), social_case_id uuid references social_cases(id), note text not null, action_taken text, follow_up_date date, created_by uuid references profiles(id), created_at timestamptz default now());

create table document_templates(id uuid primary key default gen_random_uuid(), code text unique, name_ar text not null, category app.document_category default 'other', body_html text not null, is_active boolean default true, version integer default 1, created_by uuid references auth.users(id), created_at timestamptz default now(), updated_at timestamptz default now());
create table documents(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), entity_type text not null, entity_id uuid, title_ar text not null, title text, category app.document_category default 'other', status app.document_status default 'draft', academic_year_id uuid references academic_years(id), template_id uuid references document_templates(id), current_version_id uuid, version integer default 1, requires_approval boolean default true, created_by uuid references profiles(id), created_at timestamptz default now(), updated_at timestamptz default now());
create table document_versions(id uuid primary key default gen_random_uuid(), document_id uuid references documents(id), version_number integer not null, content_html text, content jsonb, storage_path text, file_hash text, file_size_bytes bigint, mime_type text, data_snapshot jsonb, created_by uuid references profiles(id), created_at timestamptz default now(), unique(document_id,version_number));
alter table documents add constraint documents_current_version_fk foreign key(current_version_id) references document_versions(id) on delete set null;
create table document_approvals(id uuid primary key default gen_random_uuid(), document_id uuid references documents(id), version_id uuid references document_versions(id), action text, decision text, actor uuid references profiles(id), notes text, decided_at timestamptz, created_at timestamptz default now());

create table completeness_field_rules(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), entity_type text, record_type text, field_name text not null, label_ar text, importance text not null, unique(school_id,entity_type,field_name));
create table notifications(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), user_id uuid references profiles(id), recipient_user_id uuid references profiles(id), type app.notification_type default 'info', category text, title_ar text, title text, body_ar text, body text, entity_type text, related_entity_type text, link_entity_type text, entity_id uuid, related_entity_id uuid, link_entity_id uuid, is_read boolean default false, read_at timestamptz, created_at timestamptz default now());
create table notification_read_states (
  school_id uuid not null references public.schools(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_key text not null,
  is_read boolean not null default false,
  read_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (school_id, user_id, notification_key),
  check (
    notification_key ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or notification_key in (
      'system-payment-due',
      'system-upcoming-exam',
      'system-year-setup',
      'system-review-needed',
      'system-missing-data'
    )
    or notification_key ~* '^announcement:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
);
-- Preserve legacy per-recipient read states before clearing the shared flag.
insert into public.notification_read_states (
  school_id, user_id, notification_key, is_read, read_at, updated_at
)
select
  coalesce(n.school_id, p.school_id),
  p.id,
  n.id::text,
  true,
  n.read_at,
  now()
from public.notifications n
join public.profiles p
  on p.id = coalesce(n.user_id, n.recipient_user_id)
where coalesce(n.is_read, false)
  and coalesce(n.school_id, p.school_id) = p.school_id
on conflict (school_id, user_id, notification_key) do nothing;

update public.notifications
set is_read = false,
    read_at = null
where coalesce(is_read, false) or read_at is not null;

create table school_calendar_exceptions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  academic_year_id uuid not null references public.academic_years(id) on delete cascade,
  exception_date date not null,
  start_date date,
  end_date date,
  kind text not null default 'holiday' check (kind in ('holiday','special_day','exam_day','makeup_day')),
  event_type text not null default 'academic' check (event_type in ('academic','holiday','exam','teacher_return','term','special_day','makeup_day','transition')),
  title_ar text,
  grade_group text,
  stage_code text,
  reason text,
  description text,
  is_school_day boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(school_id, academic_year_id, exception_date),
  check (start_date is null or end_date is null or end_date >= start_date),
  check (start_date is null or exception_date is null or start_date <= exception_date or end_date is not null)
);
create table announcements(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), title_ar text not null, body_ar text not null, audience app.announcement_audience default 'all_staff', department_id uuid references departments(id), is_pinned boolean default false, importance app.announcement_importance default 'normal', publish_at timestamptz default now(), expires_at timestamptz, created_by uuid references auth.users(id), version integer default 1, created_at timestamptz default now(), updated_at timestamptz default now());
create table archive_records(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), academic_year_id uuid references academic_years(id), scope text default 'academic_year', label_ar text, state app.archive_state default 'generated', status text, schema_version text default '1.0', app_version text, manifest jsonb default '{}', manifest_hash text, item_count integer default 0, total_size_bytes bigint, storage_location text, checksum_sha256 text, generated_at timestamptz default now(), saved_at timestamptz, verified_at timestamptz, purge_eligible_at timestamptz, purged_at timestamptz, created_by uuid references profiles(id), verified_by uuid references profiles(id));
-- Metadata-only legacy archives are not proof of an externally saved ZIP.
update public.archive_records
set checksum_sha256 = null,
    state = 'generated',
    saved_at = null,
    verified_at = null,
    verified_by = null,
    purge_eligible_at = null
where state in ('generated', 'saved', 'verified')
  and coalesce(total_size_bytes, 0) = 0
  and checksum_sha256 = manifest_hash;

create table archive_items(id uuid primary key default gen_random_uuid(), archive_id uuid references archive_records(id), archive_record_id uuid references archive_records(id), category text not null, record_count integer default 0, checksum_sha256 text, created_at timestamptz default now());
create table backup_records(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), backup_type text default 'full', status text default 'created', file_size_bytes bigint, size_bytes bigint, storage_location text, checksum_sha256 text, manifest_hash text, label text, label_ar text, schema_version text, app_version text, created_at timestamptz default now(), created_by uuid references profiles(id), restored_at timestamptz);
create table retention_policies(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), category text not null, retention_days integer not null, unique(school_id,category));
create table login_attempts(id bigint generated always as identity primary key, login_key_hash text not null, attempted_at timestamptz default now(), blocked boolean default false);
create table attachments(id uuid primary key default gen_random_uuid(), school_id uuid references schools(id), entity_type text not null, entity_id text, bucket text default 'attachments', storage_path text not null, mime_type text, file_size_bytes bigint, original_name text not null, uploaded_by uuid references auth.users(id), uploaded_at timestamptz default now(), is_deleted boolean default false, version integer default 1, metadata jsonb default '{}');

create index idx_students_name on students using gin(full_name gin_trgm_ops);
create index idx_students_file_number on students(file_number);
create index idx_students_registration_number on students(registration_number);
create index idx_students_nationality on students(nationality); 
create index idx_student_notes_student on student_notes(student_id, created_at desc);
create index idx_student_file_checklist_student on student_file_checklist_items(student_id, category, is_received);
create index idx_employees_name on employees using gin(full_name gin_trgm_ops);
create index idx_guardians_name on guardians using gin(full_name gin_trgm_ops);
create index idx_audit_created on audit_logs(created_at desc);
create index idx_audit_occurred_id on public.audit_logs (occurred_at desc, id desc);
create index idx_audit_action_occurred on public.audit_logs (action, occurred_at desc);
create index idx_audit_entity_occurred on public.audit_logs (entity_type, occurred_at desc);
create index idx_audit_actor_occurred on public.audit_logs (actor_id, occurred_at desc);
create index if not exists idx_audit_logs_school_occurred
  on public.audit_logs (school_id, occurred_at desc, id desc);
create index if not exists student_app_accounts_school_enabled_idx
  on public.student_app_accounts (school_id, is_enabled);
create index if not exists idx_students_school_educational_status_name
  on public.students (school_id, educational_status, full_name)
  where not is_archived;
create index idx_school_calendar_exceptions_year
  on public.school_calendar_exceptions (academic_year_id, exception_date);
create index idx_school_calendar_exceptions_range
  on public.school_calendar_exceptions (academic_year_id, start_date, end_date);
create index idx_school_calendar_exceptions_school
  on public.school_calendar_exceptions (school_id, academic_year_id, exception_date);
create index idx_attendance_date on student_attendance(attendance_date);
create index idx_payments_installment on payments(installment_id);
create index idx_enrollments_class on student_enrollments(class_id);
create index idx_grade_records_exam on grade_records(exam_id);
create index idx_notifications_user on notifications(user_id,is_read);
create unique index uq_current_year on academic_years(is_current) where is_current;
create unique index uq_primary_guardian on student_guardians(student_id) where is_primary or is_primary_contact;

alter table school_settings enable row level security;

-- Keep nullable historical attribution when an Auth/profile identity is deleted.
do $$
declare
  v_fk record;
  v_definition text;
begin
  for v_fk in
    select c.conrelid::regclass as table_name,
           c.conname,
           pg_get_constraintdef(c.oid) as definition
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid in ('public.profiles'::regclass, 'auth.users'::regclass)
      and c.confdeltype = 'a'
      and not exists (
        select 1
        from unnest(c.conkey) as key_column(attnum)
        join pg_attribute a
          on a.attrelid = c.conrelid
         and a.attnum = key_column.attnum
        where a.attnotnull
      )
  loop
    v_definition := v_fk.definition || ' ON DELETE SET NULL';
    execute format('alter table %s drop constraint %I', v_fk.table_name, v_fk.conname);
    execute format(
      'alter table %s add constraint %I %s',
      v_fk.table_name,
      v_fk.conname,
      v_definition
    );
  end loop;
end $$;
