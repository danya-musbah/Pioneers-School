set search_path = public, app, extensions, pg_temp;

create or replace function app.normalize_ar(input text)
returns text
language sql immutable
set search_path=public,app,extensions,pg_temp
as $$
	select case when input is null then null else
		btrim(regexp_replace(
			regexp_replace(
				lower(unaccent(translate(input, 'أإآٱؤئىي', 'ااااوييي'))),
				U&'[\064B-\065F\0670\06D6-\06ED\0640\200C\200D]', '', 'g'
			),
			'[[:space:]]+', ' ', 'g'
		))
	end
$$;
create or replace function app.normalize_ar_compact(input text)
returns text
language sql immutable
set search_path=public,app,extensions,pg_temp
as $$
	select case when input is null then null else
		regexp_replace(app.normalize_ar(input), '[[:space:]]+', '', 'g')
	end
$$;
-- Search indexes depend on these immutable normalizers, so they are created
-- after the functions rather than in the earlier schema-only migration.
create index if not exists idx_students_name_ar_normalized
	on public.students using gin (app.normalize_ar(full_name) extensions.gin_trgm_ops);
create index if not exists idx_students_name_ar_compact
	on public.students using gin (app.normalize_ar_compact(full_name) extensions.gin_trgm_ops);
create index if not exists idx_employees_name_ar_normalized
	on public.employees using gin (app.normalize_ar(full_name) extensions.gin_trgm_ops);
create index if not exists idx_employees_name_ar_compact
	on public.employees using gin (app.normalize_ar_compact(full_name) extensions.gin_trgm_ops);
create index if not exists idx_guardians_name_ar_normalized
	on public.guardians using gin (app.normalize_ar(full_name) extensions.gin_trgm_ops);
create index if not exists idx_guardians_name_ar_compact
	on public.guardians using gin (app.normalize_ar_compact(full_name) extensions.gin_trgm_ops);

create or replace function app.is_active_user() returns boolean language sql stable security definer set search_path=public,app,pg_temp as $$ select exists(select 1 from profiles where id=auth.uid() and status='active' and role in ('admin','staff','employee')) $$;
create or replace function app.is_admin() returns boolean language sql stable security definer set search_path=public,app,pg_temp as $$ select exists(select 1 from profiles where id=auth.uid() and status='active' and role='admin') $$;
create or replace function app.has_perm(p_permission text) returns boolean language sql stable security definer set search_path=public,app,pg_temp as $$ select app.is_admin() or exists(select 1 from profiles pr join user_permissions up on up.user_id=pr.id where pr.id=auth.uid() and pr.status='active' and pr.role in ('admin','staff','employee') and (up.permission=p_permission or up.permission_code=p_permission)) $$;
create or replace function app.can(p text) returns boolean language sql stable set search_path=public,app,extensions,pg_temp as $$ select app.has_perm(p) $$;
create or replace function app.has_any_perm(variadic p_permissions text[]) returns boolean language sql stable set search_path=public,app,extensions,pg_temp as $$ select app.is_admin() or exists(select 1 from unnest(p_permissions) x(permission) where app.has_perm(x.permission)) $$;
create or replace function app.require_perm(p text) returns void language plpgsql stable security definer set search_path=public,app,pg_temp as $$ begin if not app.has_perm(p) then raise exception 'لا تملك صلاحية تنفيذ هذا الإجراء (%)',p using errcode='P0001'; end if; end $$;
create or replace function current_profile_id() returns uuid language sql stable security definer set search_path=public as $$ select auth.uid() $$;
create or replace function current_user_school() returns uuid language sql stable security definer set search_path=public as $$ select school_id from profiles where id=auth.uid() $$;
create or replace function app.current_school_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
	select coalesce(
		(select p.school_id from public.profiles p
			where p.id = auth.uid() and p.school_id is not null),
		(select a.school_id from public.student_app_accounts a
			where a.auth_user_id = auth.uid() and a.is_enabled),
		(select ss.school_id from public.school_settings ss
			where ss.id = 1 and ss.school_id is not null)
	);
$$;
create or replace function app.can_view_announcement(
	p_audience app.announcement_audience,
	p_department_id uuid
) returns boolean
language sql
stable
security definer
set search_path=public,app,pg_temp
as $$
	select app.is_active_user() and case
		when app.is_admin() then true
		when p_audience = 'all_staff' then true
		when p_audience = 'admins_only' then false
		when p_audience = 'specific_department' then exists (
			select 1
			from public.profiles p
			join public.employees e on e.id = p.employee_id
			join public.departments d on d.id = e.department_id
			where p.id = auth.uid()
				and e.school_id = app.current_school_id()
				and d.school_id = app.current_school_id()
				and d.id = p_department_id
		)
		else false
	end;
$$;
create or replace function app.tables_without_rls()
returns table(schemaname text, tablename text)
language sql
stable
security definer
set search_path=pg_catalog
as $$
	select n.nspname::text, c.relname::text
	from pg_catalog.pg_class c
	join pg_catalog.pg_namespace n on n.oid=c.relnamespace
	where n.nspname='public'
		and c.relkind in ('r','p')
		and not c.relrowsecurity
	order by n.nspname,c.relname;
$$;
create or replace function account_is_active() returns boolean language sql stable security definer set search_path=public as $$ select app.is_active_user() $$;
create or replace function is_manager() returns boolean language sql stable security definer set search_path=public as $$ select app.is_admin() $$;
create or replace function has_permission(perm_code text) returns boolean language sql stable security definer set search_path=public as $$ select app.has_perm(perm_code) $$;
create or replace function app.touch_updated_at() returns trigger language plpgsql set search_path=public,app,extensions,pg_temp as $$ begin new.updated_at=now(); return new; end $$;
create or replace function public.set_updated_at() returns trigger language plpgsql set search_path=public,app,extensions,pg_temp as $$ begin new.updated_at=now(); return new; end $$;
create or replace function app.tg_block_delete() returns trigger language plpgsql set search_path=public,app,extensions,pg_temp as $$ begin raise exception 'الحذف النهائي غير مسموح لهذا النوع من السجلات' using errcode='P0013'; end $$;
create or replace function app.tg_single_current_year()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
begin
	if new.is_current then
		update public.academic_years
		set is_current = false
		where school_id = new.school_id
			and id <> new.id
			and is_current;
	end if;
	return new;
end;
$$;
create or replace function app.set_audit_log_school_scope()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_school_id uuid;
begin
	if new.school_id is null then
		select p.school_id into v_school_id
		from public.profiles p
		where p.id = coalesce(new.actor_id, new.user_id);
		if v_school_id is null and new.academic_year_id is not null then
			select ay.school_id into v_school_id
			from public.academic_years ay where ay.id = new.academic_year_id;
		end if;
		if v_school_id is null
			and coalesce(new.metadata->>'school_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
			v_school_id := (new.metadata->>'school_id')::uuid;
		end if;
		if v_school_id is null and (select count(*) from public.schools) <= 1 then
			select ss.school_id into v_school_id
			from public.school_settings ss where ss.id = 1;
		end if;
		if v_school_id is null then
			raise exception 'تعذر تحديد المدرسة لسجل التدقيق.' using errcode = '42501';
		end if;
		new.school_id := v_school_id;
	end if;
	return new;
end;
$$;

create or replace function app.guard_academic_year_closure()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_authorized boolean;
begin
	if tg_op = 'INSERT' then
		if new.status in ('closed', 'مغلقة') then
			raise exception 'يجب إنشاء السنة بحالة مفتوحة ثم إغلاقها عبر الإجراء المعتمد.' using errcode = '42501';
		end if;
		return new;
	end if;
	if old.status in ('closed', 'مغلقة') and new.status is distinct from old.status then
		raise exception 'لا يمكن إعادة فتح سنة دراسية مغلقة أو تغيير حالتها مباشرة.' using errcode = '42501';
	end if;
	if new.status in ('closed', 'مغلقة') and new.status is distinct from old.status then
		select exists (
			select 1 from app.academic_year_closure_authorizations a
			where a.transaction_id = txid_current()
				and a.academic_year_id = new.id
				and a.actor_id = auth.uid()
		) into v_authorized;
		if not v_authorized then
			raise exception 'يجب استخدام إجراء إغلاق السنة المعتمد.' using errcode = '42501';
		end if;
		delete from app.academic_year_closure_authorizations
		where transaction_id = txid_current() and academic_year_id = new.id;
	end if;
	return new;
end;
$$;

create or replace function app.guard_student_educational_status_transition()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_authorized boolean;
begin
	if tg_op = 'INSERT' then
		if new.educational_status = 'withdrawn' then
			raise exception 'يجب استخدام إجراء سحب ملف الطالب.' using errcode = '42501';
		end if;
		return new;
	end if;
	if old.educational_status = 'withdrawn'
		and not app.has_perm('students.archive') then
		raise exception 'لا تملك صلاحية تعديل ملف طالب مسحوب.' using errcode = '42501';
	end if;
	if old.educational_status is distinct from new.educational_status
		and (old.educational_status = 'withdrawn' or new.educational_status = 'withdrawn') then
		select exists (
			select 1 from app.student_file_transition_authorizations a
			where a.transaction_id = txid_current()
				and a.student_id = new.id
				and a.actor_id = auth.uid()
				and a.target_status = new.educational_status
		) into v_authorized;
		if not v_authorized then
			raise exception 'يجب استخدام إجراء سحب أو استرجاع ملف الطالب.' using errcode = '42501';
		end if;
		delete from app.student_file_transition_authorizations
		where transaction_id = txid_current() and student_id = new.id;
	end if;
	if new.educational_status = 'withdrawn' then
		if new.student_app_login_status <> 'disabled' then
			raise exception 'لا يمكن تفعيل دخول طالب مسحوب.' using errcode = '42501';
		end if;
		new.student_app_login_enabled := false;
	end if;
	return new;
end;
$$;

create or replace function app.prevent_enrollment_for_withdrawn_student()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
begin
	if exists (
		select 1 from public.students s
		where s.id = new.student_id and s.educational_status = 'withdrawn'
	) then
		raise exception 'لا يمكن تسجيل طالب مسحوب؛ استرجع ملفه أولًا.' using errcode = 'P0001';
	end if;
	return new;
end;
$$;

create or replace function app.prevent_new_operation_for_withdrawn_student()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_status text;
begin
	if tg_table_name in ('student_attendance', 'grade_records', 'student_fees') then
		select s.educational_status into v_status
		from public.student_enrollments e
		join public.students s on s.id = e.student_id
		where e.id = new.enrollment_id;
	else
		raise exception 'المشغل غير مهيأ لهذا الجدول.' using errcode = 'P0001';
	end if;
	if v_status = 'withdrawn' then
		raise exception 'لا يمكن إنشاء عملية دراسية جديدة لطالب مسحوب؛ استرجع ملفه أولًا.' using errcode = 'P0001';
	end if;
	return new;
end;
$$;

create or replace function public.withdraw_student_file(
	p_student_id uuid,
	p_reason text default null,
	p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_student public.students%rowtype;
	v_actor_label text;
	v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
	v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
	perform app.require_perm('students.archive');
	if auth.uid() is null or v_school_id is null or p_student_id is null then
		raise exception 'تعذر تحديد الطالب أو المدرسة الحالية.' using errcode = '42501';
	end if;
	select * into v_student from public.students
	where id = p_student_id and school_id = v_school_id
	for update;
	if not found then
		raise exception 'الطالب غير موجود في المدرسة الحالية أو لا تملك صلاحية الوصول إليه.' using errcode = 'P0001';
	end if;
	if v_student.educational_status = 'withdrawn' then
		raise exception 'ملف الطالب مسحوب بالفعل.' using errcode = 'P0001';
	end if;
	insert into app.student_file_transition_authorizations(
		transaction_id, student_id, actor_id, target_status
	) values (txid_current(), p_student_id, auth.uid(), 'withdrawn');
	update public.students
	set educational_status = 'withdrawn', student_app_login_status = 'disabled',
			student_app_login_enabled = false, updated_at = now()
	where id = p_student_id and school_id = v_school_id;

	select coalesce(nullif(btrim(full_name), ''), username)
	into v_actor_label from public.profiles where id = auth.uid();
	insert into public.audit_logs(
		actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata
	) values (
		auth.uid(), v_actor_label, 'student.file.withdrawn', 'student', p_student_id::text,
		jsonb_build_object('educational_status', v_student.educational_status,
			'student_app_login_status', v_student.student_app_login_status,
			'student_app_login_enabled', v_student.student_app_login_enabled),
		jsonb_build_object('educational_status', 'withdrawn',
			'student_app_login_status', 'disabled', 'student_app_login_enabled', false),
		'تم سحب ملف الطالب',
		jsonb_build_object('school_id', v_school_id, 'reason', v_reason, 'notes', v_notes,
			'previous_educational_status', v_student.educational_status,
			'previous_app_login_status', v_student.student_app_login_status,
			'previous_app_login_enabled', v_student.student_app_login_enabled)
	);
	return jsonb_build_object('withdrawn', true, 'student_id', p_student_id,
		'educational_status', 'withdrawn', 'app_login_status', 'disabled');
end;
$$;

create or replace function public.restore_student_file(
	p_student_id uuid,
	p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_student public.students%rowtype;
	v_withdrawal public.audit_logs%rowtype;
	v_actor_label text;
	v_restore_status text;
	v_login_status text;
	v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
	perform app.require_perm('students.archive');
	if auth.uid() is null or v_school_id is null or p_student_id is null then
		raise exception 'تعذر تحديد الطالب أو المدرسة الحالية.' using errcode = '42501';
	end if;
	select * into v_student from public.students
	where id = p_student_id and school_id = v_school_id
	for update;
	if not found then
		raise exception 'الطالب غير موجود في المدرسة الحالية أو لا تملك صلاحية الوصول إليه.' using errcode = 'P0001';
	end if;
	if v_student.educational_status <> 'withdrawn' then
		raise exception 'ملف الطالب غير مسحوب.' using errcode = 'P0001';
	end if;
	select * into v_withdrawal from public.audit_logs
	where entity_type = 'student' and entity_id = p_student_id::text
		and action = 'student.file.withdrawn'
		and metadata->>'school_id' = v_school_id::text
	order by occurred_at desc, id desc
	limit 1;
	v_restore_status := v_withdrawal.metadata->>'previous_educational_status';
	if v_restore_status is null or v_restore_status = 'withdrawn' then
		v_restore_status := 'active';
	end if;
	v_login_status := v_withdrawal.metadata->>'previous_app_login_status';
	if v_login_status not in ('not_created', 'active', 'reset_required', 'disabled') then
		v_login_status := 'disabled';
	end if;
	insert into app.student_file_transition_authorizations(
		transaction_id, student_id, actor_id, target_status
	) values (txid_current(), p_student_id, auth.uid(), v_restore_status);
	update public.students
	set educational_status = v_restore_status,
			student_app_login_status = v_login_status,
			student_app_login_enabled = v_login_status in ('active', 'reset_required'),
			updated_at = now()
	where id = p_student_id and school_id = v_school_id;

	select coalesce(nullif(btrim(full_name), ''), username)
	into v_actor_label from public.profiles where id = auth.uid();
	insert into public.audit_logs(
		actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata
	) values (
		auth.uid(), v_actor_label, 'student.file.restored', 'student', p_student_id::text,
		jsonb_build_object('educational_status', 'withdrawn',
			'student_app_login_status', v_student.student_app_login_status),
		jsonb_build_object('educational_status', v_restore_status,
			'student_app_login_status', v_login_status),
		'تم استرجاع ملف الطالب',
		jsonb_build_object('school_id', v_school_id, 'notes', v_notes,
			'restored_from_withdrawal_audit_id', v_withdrawal.id)
	);
	return jsonb_build_object('restored', true, 'student_id', p_student_id,
		'educational_status', v_restore_status, 'app_login_status', v_login_status);
end;
$$;

create or replace function app.tg_leave_overlap() returns trigger language plpgsql set search_path=public,app,extensions,pg_temp as $$ begin if new.status='approved' and exists(select 1 from leave_requests x where x.employee_id=new.employee_id and x.id<>new.id and x.status='approved' and daterange(x.start_date,x.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')) then raise exception 'يوجد طلب إجازة متداخل'; end if; return new; end $$;
create or replace function app.reject_paused_leave_mutation()
returns trigger
language plpgsql
set search_path=public,app,pg_temp
as $$
begin
	raise exception 'إدارة طلبات الإجازات متوقفة مؤقتًا. لم يتم حفظ أي تغيير.'
		using errcode = 'P0001';
end;
$$;
create or replace function app.tg_payment_immutable() returns trigger language plpgsql set search_path=public,app,extensions,pg_temp as $$ begin if new.amount<>old.amount or new.installment_id<>old.installment_id or new.payment_date<>old.payment_date then raise exception 'لا يمكن تعديل بيانات دفعة مسجلة' using errcode='P0027'; end if; return new; end $$;
create or replace function public.my_permissions() returns table(permission text) language sql stable security definer set search_path=public,app,pg_temp as $$ select key from permissions where app.is_admin() union select coalesce(up.permission,up.permission_code) from user_permissions up where up.user_id=auth.uid() $$;
create or replace function public.my_session() returns jsonb language sql stable security definer set search_path=public,app,pg_temp as $$ select jsonb_build_object('profile',(select to_jsonb(x) from (select p.id,p.school_id,p.full_name,p.username,p.email,p.role,p.status,p.must_change_password,p.last_login_at,p.employee_id from profiles p where p.id=auth.uid()) x),'permissions',coalesce((select jsonb_agg(permission) from public.my_permissions()),'[]'::jsonb),'school',(select to_jsonb(s) from (select * from school_settings where id=1) s)) $$;
create or replace function public.set_notification_read_states(
  p_notification_keys text[],
  p_is_read boolean
)
returns integer
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_school_id uuid := app.current_school_id();
  v_key text;
  v_count integer := 0;
begin
  if v_user_id is null or not app.is_active_user() then
    raise exception 'يجب تسجيل الدخول لتحديث حالة التنبيه.' using errcode = '42501';
  end if;
  if v_school_id is null then
    raise exception 'تعذر تحديد المدرسة الحالية.' using errcode = '42501';
  end if;
  if p_is_read is null or p_notification_keys is null
    or cardinality(p_notification_keys) = 0
    or cardinality(p_notification_keys) > 500
    or exists (
      select 1
      from unnest(p_notification_keys) as keys(key_value)
      where key_value is null or btrim(key_value) = ''
    ) then
    raise exception 'قائمة التنبيهات والإعلانات غير صالحة.' using errcode = '22023';
  end if;

  for v_key in
    select distinct lower(btrim(key_value))
    from unnest(p_notification_keys) as keys(key_value)
    where key_value is not null and btrim(key_value) <> ''
  loop
    if v_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      if not exists (
        select 1
        from public.notifications n
        where n.id = v_key::uuid
          and (n.school_id = v_school_id or n.school_id is null)
          and (n.user_id = v_user_id or n.recipient_user_id = v_user_id)
      ) then
        raise exception 'التنبيه غير موجود أو لا تملك صلاحية تحديثه.' using errcode = '42501';
      end if;
    elsif v_key ~ '^announcement:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      if not exists (
        select 1
        from public.announcements a
        where a.id = split_part(v_key, ':', 2)::uuid
          and a.school_id = v_school_id
          and a.publish_at <= now()
          and (a.expires_at is null or a.expires_at >= now())
          and app.can_view_announcement(a.audience, a.department_id)
      ) then
        raise exception 'الإعلان غير متاح لك أو لم يعد منشورًا.' using errcode = '42501';
      end if;
    elsif v_key not in (
      'system-payment-due',
      'system-upcoming-exam',
      'system-year-setup',
      'system-review-needed',
      'system-missing-data'
    ) then
      raise exception 'معرّف التنبيه غير صالح.' using errcode = '22023';
    end if;

    insert into public.notification_read_states (
      school_id, user_id, notification_key, is_read, read_at, updated_at
    ) values (
      v_school_id,
      v_user_id,
      v_key,
      p_is_read,
      case when p_is_read then now() else null end,
      now()
    )
    on conflict (school_id, user_id, notification_key)
    do update set
      is_read = excluded.is_read,
      read_at = excluded.read_at,
      updated_at = excluded.updated_at;

    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise exception 'لم يتم تحديث أي عنصر.' using errcode = '22023';
  end if;
  return v_count;
end;
$$;

create or replace function public.mark_notification_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform public.set_notification_read_states(array[p_id::text], true);
end;
$$;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_school_id uuid := app.current_school_id();
  v_count integer := 0;
  v_rows integer;
begin
  if v_user_id is null or not app.is_active_user() or v_school_id is null then
    raise exception 'تعذر التحقق من المستخدم أو المدرسة الحالية.' using errcode = '42501';
  end if;

  insert into public.notification_read_states (
    school_id, user_id, notification_key, is_read, read_at, updated_at
  )
  select distinct
    v_school_id,
    v_user_id,
    lower(n.id::text),
    true,
    now(),
    now()
  from public.notifications n
  where (n.school_id = v_school_id or n.school_id is null)
    and (n.user_id = v_user_id or n.recipient_user_id = v_user_id)
    and not exists (
      select 1 from public.notification_read_states state
      where state.school_id = v_school_id
        and state.user_id = v_user_id
        and state.notification_key = lower(n.id::text)
        and state.is_read
    )
  on conflict (school_id, user_id, notification_key)
  do update set
    is_read = true,
    read_at = now(),
    updated_at = now();

  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  insert into public.notification_read_states (
    school_id, user_id, notification_key, is_read, read_at, updated_at
  )
  select distinct
    v_school_id,
    v_user_id,
    'announcement:' || lower(a.id::text),
    true,
    now(),
    now()
  from public.announcements a
  where a.school_id = v_school_id
    and a.publish_at <= now()
    and (a.expires_at is null or a.expires_at >= now())
    and app.can_view_announcement(a.audience, a.department_id)
    and not exists (
      select 1 from public.notification_read_states state
      where state.school_id = v_school_id
        and state.user_id = v_user_id
        and state.notification_key = 'announcement:' || lower(a.id::text)
        and state.is_read
    )
  on conflict (school_id, user_id, notification_key)
  do update set
    is_read = true,
    read_at = now(),
    updated_at = now();

  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  insert into public.notification_read_states (
    school_id, user_id, notification_key, is_read, read_at, updated_at
  )
  select
    v_school_id,
    v_user_id,
    key_value,
    true,
    now(),
    now()
  from (
    values
      ('system-payment-due'),
      ('system-upcoming-exam'),
      ('system-year-setup'),
      ('system-review-needed'),
      ('system-missing-data')
  ) as keys(key_value)
  where not exists (
    select 1 from public.notification_read_states state
    where state.school_id = v_school_id
      and state.user_id = v_user_id
      and state.notification_key = keys.key_value
      and state.is_read
  )
  on conflict (school_id, user_id, notification_key)
  do update set
    is_read = true,
    read_at = now(),
    updated_at = now();

  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  return v_count;
end;
$$;

create or replace function public.student_ids_by_completeness(p_status text) returns setof uuid language sql stable security definer set search_path=public,app,pg_temp as $$
with current_enrollment as (
	select distinct on (e.student_id)
		e.student_id,
		case when y.id is not null then e.academic_year_id end as academic_year_id,
		st.id as stage_id,
		case when g.id is not null then e.grade_id end as grade_id,
		case when c.id is not null then e.class_id end as class_id
	from public.student_enrollments e
	join public.students s on s.id=e.student_id and s.school_id=app.current_school_id()
		and s.educational_status <> 'withdrawn' and not coalesce(s.is_archived, false)
	left join public.academic_years y on y.id=e.academic_year_id and y.school_id=s.school_id
	left join public.school_grades g on g.id=e.grade_id and g.school_id=s.school_id
	left join public.academic_stages st on st.id=g.stage_id and st.school_id=s.school_id
	left join public.classes c on c.id=e.class_id and c.school_id=s.school_id
		and c.academic_year_id=e.academic_year_id and c.grade_id=e.grade_id
	order by e.student_id,y.is_current desc nulls last,e.enrollment_date desc nulls last,e.created_at desc
), evaluated as (
	select s.id,
		(nullif(btrim(coalesce(s.student_number,'')),'') is null or nullif(btrim(coalesce(s.full_name,'')),'') is null or nullif(btrim(coalesce(s.gender,'')),'') is null or s.date_of_birth is null or nullif(btrim(coalesce(s.national_id,'')),'') is null or s.registration_date is null or e.academic_year_id is null or e.stage_id is null or e.grade_id is null or e.class_id is null) as critical_missing,
		(nullif(btrim(coalesce(s.nationality,'')),'') is null or nullif(btrim(coalesce(s.father_phone,s.mother_phone,s.phone,'')),'') is null or nullif(btrim(coalesce(s.residence_address,s.address,'')),'') is null) as important_missing,
		(nullif(btrim(coalesce(s.health_status,'')),'') is null or nullif(btrim(coalesce(s.social_status,'')),'') is null) as optional_missing
	from public.students s left join current_enrollment e on e.student_id=s.id
	where coalesce(s.is_archived,false)=false and s.educational_status <> 'withdrawn'
		and s.school_id is not distinct from app.current_school_id()
)
select id from evaluated where p_status in ('missing','incomplete','complete') and app.has_any_perm('students.manage','students.view','students.create','students.edit','students.archive','students.enrollment.manage') and case
	when p_status='missing' then critical_missing
	when p_status='incomplete' then not critical_missing and (important_missing or optional_missing)
	when p_status='complete' then not critical_missing and not important_missing and not optional_missing
end;
$$;
create or replace function public.resolve_login_email(p_username text)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, auth, app, pg_temp
as $$
	select coalesce(
		(
			select coalesce(p.email, u.email::text)
			from public.profiles p
			join auth.users u on u.id = p.id
			where p.status = 'active'
				and lower(btrim(p.username)) = lower(btrim(p_username))
			limit 1
		),
		(
			select a.login_email
			from public.student_app_accounts a
			join public.students s on s.id = a.student_id and s.school_id = a.school_id
			where a.is_enabled
				and s.student_app_login_enabled
				and s.student_app_login_status in ('active', 'reset_required')
				and s.educational_status <> 'withdrawn'
				and not coalesce(s.is_archived, false)
				and lower(btrim(s.student_number)) = lower(btrim(p_username))
			limit 1
		)
	);
$$;

-- Student numbers are login identifiers and cannot shadow staff usernames.
create or replace function app.guard_student_login_identifier_collision()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
begin
	if tg_table_name = 'profiles' then
		if nullif(btrim(new.username), '') is not null and exists (
			select 1 from public.students s
			where lower(btrim(s.student_number)) = lower(btrim(new.username))
		) then
			raise exception 'اسم المستخدم يتعارض مع رقم طالب مستخدم لتسجيل الدخول.'
				using errcode = '23505';
		end if;
	elsif tg_table_name = 'students' then
		if nullif(btrim(new.student_number), '') is not null and exists (
			select 1 from public.profiles p
			where lower(btrim(p.username)) = lower(btrim(new.student_number))
		) then
			raise exception 'رقم الطالب يتعارض مع اسم مستخدم إداري.'
				using errcode = '23505';
		end if;
	end if;
	return new;
end;
$$;

create or replace function public.student_login_identifier_conflicts(p_student_number text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
	select exists (
		select 1 from public.profiles p
		where lower(btrim(p.username)) = lower(btrim(p_student_number))
	);
$$;

create or replace function app.current_student_portal_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
	select a.student_id
	from public.student_app_accounts a
	join public.students s on s.id = a.student_id and s.school_id = a.school_id
	where a.auth_user_id = auth.uid()
		and a.is_enabled
		and s.student_app_login_enabled
		and s.student_app_login_status in ('active', 'reset_required')
		and s.educational_status <> 'withdrawn'
		and not coalesce(s.is_archived, false)
	limit 1;
$$;

create or replace function public.student_portal_session()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
	select jsonb_build_object(
		'student', jsonb_build_object(
			'id', s.id,
			'school_id', s.school_id,
			'student_number', s.student_number,
			'full_name', s.full_name
		)
	)
	from public.student_app_accounts a
	join public.students s on s.id = a.student_id and s.school_id = a.school_id
	where a.auth_user_id = auth.uid()
		and a.is_enabled
		and s.student_app_login_enabled
		and s.student_app_login_status in ('active', 'reset_required')
		and s.educational_status <> 'withdrawn'
		and not coalesce(s.is_archived, false)
	limit 1;
$$;

create or replace function public.student_app_access_account_statuses(
	p_student_ids uuid[] default null
)
returns table (
	student_id uuid,
	has_account boolean,
	is_enabled boolean,
	credential_delivery_pending boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
begin
	if auth.uid() is null or not app.has_any_perm('students.manage', 'students.edit') then
		raise exception 'ليس لديك صلاحية عرض حالة حسابات الطلاب.' using errcode = '42501';
	end if;
	if coalesce(cardinality(p_student_ids), 0) > 2000 then
		raise exception 'عدد سجلات حالة الوصول يتجاوز الحد المسموح.' using errcode = '22023';
	end if;
	return query
		select s.id,
			(a.auth_user_id is not null),
			coalesce(a.is_enabled, false)
				and s.student_app_login_enabled
				and s.student_app_login_status in ('active', 'reset_required'),
			coalesce(a.credential_delivery_pending, false)
		from public.students s
		left join public.student_app_accounts a
			on a.student_id = s.id and a.school_id = s.school_id
		where s.school_id = app.current_school_id()
			and s.educational_status <> 'withdrawn'
			and not coalesce(s.is_archived, false)
			and (p_student_ids is null or s.id = any(p_student_ids));
end;
$$;

create or replace function public.begin_login_attempt(p_username text) returns jsonb language plpgsql security definer set search_path=public,app,extensions,pg_temp as $$ declare h text:=encode(extensions.digest(convert_to(lower(btrim(coalesce(p_username,''))), 'UTF8'), 'sha256'::text),'hex'); n integer; begin select count(*) into n from login_attempts where login_key_hash=h and attempted_at>now()-interval '15 minutes' and not blocked; insert into login_attempts(login_key_hash,blocked) values(h,n>=5); return jsonb_build_object('allowed',n<5,'remaining',greatest(0,4-n)); end $$;
create or replace function public.record_login_failure(p_username text) returns void language plpgsql security definer set search_path=public,app,extensions,pg_temp as $$ declare h text:=encode(extensions.digest(convert_to(lower(btrim(coalesce(p_username,''))), 'UTF8'), 'sha256'::text),'hex'); begin insert into login_attempts(login_key_hash) values(h); end $$;
create or replace function public.next_student_number() returns text language plpgsql security definer set search_path=public,app,pg_temp as $$
declare candidate bigint;
begin
	loop
		candidate := nextval('public.student_number_seq');
		exit when not exists (select 1 from public.students where student_number = candidate::text);
	end loop;
	return candidate::text;
end $$;
alter table public.students alter column student_number set default public.next_student_number();

create or replace function public.save_student_profile(
	p_student_id uuid,
	p_request_id uuid,
	p_student jsonb,
	p_guardians jsonb default '{}'::jsonb,
	p_note text default null,
	p_checklist jsonb default '[]'::jsonb,
	p_photo_update boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=public,app,extensions,pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_student public.students%rowtype;
	v_saved_student public.students%rowtype;
	v_entry record;
	v_checklist_item jsonb;
	v_guardian_id uuid;
	v_guardian_name text;
	v_guardian_phone text;
	v_guardian_national_id text;
	v_relationship text;
	v_managed_relationships text[] := array[]::text[];
	v_guardian_ids uuid[] := array[]::uuid[];
	v_links jsonb := '[]'::jsonb;
	v_note_id uuid;
	v_is_primary boolean;
	v_is_existing boolean;
	v_checklist_count integer := 0;
	v_request_key text;
	v_request_hash text;
	v_operation text;
	v_idempotency public.idempotency_keys%rowtype;
	v_result jsonb;
begin
	if p_student_id is null then
		raise exception 'معرّف الطالب مطلوب';
	end if;
	if p_request_id is null then
		raise exception 'معرّف طلب الحفظ مطلوب';
	end if;
	if v_school_id is null then
		raise exception 'حساب المستخدم غير مرتبط بمدرسة';
	end if;
	perform pg_advisory_xact_lock(hashtext(v_school_id::text));
	if jsonb_typeof(p_student) is distinct from 'object' then
		raise exception 'بيانات الطالب غير صالحة';
	end if;
	if jsonb_typeof(coalesce(p_guardians, '{}'::jsonb)) is distinct from 'object' then
		raise exception 'بيانات أولياء الأمور غير صالحة';
	end if;
	if jsonb_typeof(coalesce(p_checklist, '[]'::jsonb)) is distinct from 'array' then
		raise exception 'قائمة ملفات الطالب غير صالحة';
	end if;
	v_request_key := 'student-profile:' || p_request_id::text;
	v_request_hash := md5(jsonb_build_object(
		'student_id', p_student_id,
		'student', p_student - 'photo_path' - 'photo_storage_path',
		'guardians', coalesce(p_guardians, '{}'::jsonb),
		'note', coalesce(p_note, ''),
		'checklist', coalesce(p_checklist, '[]'::jsonb),
		'photo_update', coalesce(p_photo_update, false)
	)::text);

	select * into v_idempotency
	from public.idempotency_keys
	where key = v_request_key;
	if found then
		if v_idempotency.actor_id is distinct from auth.uid()
			or v_idempotency.request_hash is distinct from v_request_hash
			or v_idempotency.operation not in ('students.create','students.edit') then
			raise exception 'معرّف طلب الحفظ مستخدم لطلب مختلف';
		end if;
		perform app.require_perm(v_idempotency.operation);
		if v_idempotency.status = 'completed' and v_idempotency.result is not null then
			select * into v_saved_student
			from public.students
			where id = p_student_id and school_id = v_school_id;
			if not found then
				raise exception 'الطالب المحفوظ غير موجود في المدرسة الحالية';
			end if;
			return jsonb_build_object(
				'student', to_jsonb(v_saved_student),
				'guardian_links', coalesce((v_idempotency.result->>'guardian_links')::integer, 0),
				'checklist_items', coalesce((v_idempotency.result->>'checklist_items')::integer, 0)
			);
		end if;
		raise exception 'عملية الحفظ السابقة غير مكتملة؛ أعد المحاولة بطلب جديد';
	end if;

	select exists (select 1 from public.students where id = p_student_id)
	into v_is_existing;
	if v_is_existing then
		v_operation := 'students.edit';
	else
		v_operation := 'students.create';
	end if;
	perform app.require_perm(v_operation);
	insert into public.idempotency_keys(key,operation,actor_id,request_hash,status)
	values(v_request_key,v_operation,auth.uid(),v_request_hash,'in_progress');

	v_student := jsonb_populate_record(null::public.students, p_student);
	if nullif(btrim(v_student.student_number), '') is null then
		raise exception 'رقم الطالب مطلوب';
	end if;
	if nullif(btrim(v_student.first_name), '') is null
		or nullif(btrim(v_student.family_name), '') is null then
		raise exception 'الاسم الأول واسم العائلة مطلوبان';
	end if;
	if not v_is_existing and v_student.registration_date is null then
		raise exception 'تاريخ التسجيل مطلوب';
	end if;
	if v_student.date_of_birth is not null then
		if v_student.date_of_birth > current_date then
			raise exception 'تاريخ الميلاد لا يمكن أن يكون في المستقبل';
		end if;
		if extract(year from age(current_date, v_student.date_of_birth)) < 3 then
			raise exception 'عمر الطالب لا يمكن أن يكون أقل من 3 سنوات';
		end if;
		if extract(year from age(current_date, v_student.date_of_birth)) > 30 then
			raise exception 'عمر الطالب غير مناسب لنظام المدرسة؛ يرجى مراجعة تاريخ الميلاد';
		end if;
	end if;
	if v_student.national_id is not null and v_student.national_id !~ '^[0-9]{12}$' then
		raise exception 'الرقم الوطني يجب أن يتكون من 12 رقمًا بالضبط';
	end if;
	if (v_student.phone is not null and v_student.phone !~ '^09[0-9]{8}$')
		or (v_student.father_phone is not null and v_student.father_phone !~ '^09[0-9]{8}$')
		or (v_student.mother_phone is not null and v_student.mother_phone !~ '^09[0-9]{8}$')
		or (v_student.nearest_relative_phone is not null and v_student.nearest_relative_phone !~ '^09[0-9]{8}$') then
		raise exception 'يجب أن تبدأ أرقام الهواتف بـ 09 وتتكون من 10 أرقام';
	end if;
	if v_student.school_id is not null and v_student.school_id <> v_school_id then
		raise exception 'لا يمكن حفظ طالب في مدرسة أخرى';
	end if;
	if v_student.national_id is not null and exists (
		select 1 from public.students s
		where s.school_id = v_school_id
			and s.id <> p_student_id
			and s.is_archived = false
			and s.national_id = v_student.national_id
	) then
		raise exception 'هذا الرقم الوطني مسجل بالفعل لطالب آخر في النظام';
	end if;

	if v_is_existing then
		update public.students set
			school_id = v_school_id,
			student_number = v_student.student_number,
			file_number = coalesce(v_student.file_number, v_student.student_number),
			registration_number = v_student.registration_number,
			registration_date = v_student.registration_date,
			full_name = v_student.full_name,
			full_name_en = v_student.full_name_en,
			first_name = v_student.first_name,
			father_name = v_student.father_name,
			grandfather_name = v_student.grandfather_name,
			family_name = v_student.family_name,
			mother_name = v_student.mother_name,
			gender = v_student.gender,
			date_of_birth = v_student.date_of_birth,
			place_of_birth = v_student.place_of_birth,
			nearest_relative_name = v_student.nearest_relative_name,
			nearest_relative_relationship = v_student.nearest_relative_relationship,
			nearest_relative_phone = v_student.nearest_relative_phone,
			religion = v_student.religion,
			national_id = v_student.national_id,
			phone = v_student.phone,
			father_phone = v_student.father_phone,
			mother_phone = v_student.mother_phone,
			address = v_student.address,
			residence_address = v_student.residence_address,
			city = v_student.city,
			region = v_student.region,
			previous_school = v_student.previous_school,
			nationality = v_student.nationality,
			health_status = v_student.health_status,
			health_conditions = coalesce(v_student.health_conditions, '{}'::text[]),
			disability_needs = coalesce(v_student.disability_needs, '{}'::text[]),
			health_notes = v_student.health_notes,
			social_status = v_student.social_status,
			photo_path = case when p_photo_update then v_student.photo_path else photo_path end,
			photo_storage_path = case when p_photo_update then v_student.photo_storage_path else photo_storage_path end,
			avatar_path = case when p_photo_update then v_student.avatar_path else avatar_path end,
			avatar_storage_path = case when p_photo_update then v_student.avatar_storage_path else avatar_storage_path end,
			admission_type = coalesce(v_student.admission_type, 'نظامي'),
			student_app_login_status = coalesce(v_student.student_app_login_status, 'not_created'),
			student_app_login_enabled = coalesce(v_student.student_app_login_enabled, false),
			is_delinquent = coalesce(v_student.is_delinquent, false)
		where id = p_student_id and school_id = v_school_id
		returning * into v_saved_student;
		if not found then
			raise exception 'الطالب غير موجود في المدرسة الحالية أو لا تملك صلاحية تعديله';
		end if;
	else
		insert into public.students (
			id, school_id, student_number, file_number, registration_number,
			registration_date, full_name, full_name_en, first_name, father_name,
			grandfather_name, family_name, mother_name, gender, date_of_birth,
			place_of_birth, nearest_relative_name, nearest_relative_relationship,
			nearest_relative_phone, religion, national_id, phone, father_phone,
			mother_phone, address, residence_address, city, region, previous_school,
			nationality, health_status, health_conditions, disability_needs, health_notes, social_status, photo_path,
			photo_storage_path, avatar_path, avatar_storage_path, admission_type,
			student_app_login_status, student_app_login_enabled, is_delinquent
		) values (
			p_student_id, v_school_id, v_student.student_number,
			coalesce(v_student.file_number, v_student.student_number),
			v_student.registration_number, v_student.registration_date,
			v_student.full_name, v_student.full_name_en, v_student.first_name, v_student.father_name,
			v_student.grandfather_name, v_student.family_name, v_student.mother_name,
			v_student.gender, v_student.date_of_birth, v_student.place_of_birth,
			v_student.nearest_relative_name, v_student.nearest_relative_relationship,
			v_student.nearest_relative_phone, v_student.religion, v_student.national_id,
			v_student.phone, v_student.father_phone, v_student.mother_phone,
			v_student.address, v_student.residence_address, v_student.city,
			v_student.region, v_student.previous_school, v_student.nationality,
			v_student.health_status,
			coalesce(v_student.health_conditions, '{}'::text[]),
			coalesce(v_student.disability_needs, '{}'::text[]),
			v_student.health_notes,
			v_student.social_status, v_student.photo_path,
			v_student.photo_storage_path, v_student.avatar_path, v_student.avatar_storage_path,
			coalesce(v_student.admission_type, 'نظامي'),
			coalesce(v_student.student_app_login_status, 'not_created'),
			coalesce(v_student.student_app_login_enabled, false),
			coalesce(v_student.is_delinquent, false)
		)
		returning * into v_saved_student;
		if not found then
			raise exception 'معرّف الطالب مستخدم في مدرسة أخرى';
		end if;
	end if;

	if v_saved_student.national_id is not null and exists (
		select 1 from public.students s
		where s.school_id = v_school_id
			and s.id <> p_student_id
			and s.is_archived = false
			and s.national_id = v_saved_student.national_id
	) then
		raise exception 'هذا الرقم الوطني مسجل بالفعل لطالب آخر في النظام';
	end if;

	for v_entry in
		select key, value from jsonb_each(coalesce(p_guardians, '{}'::jsonb))
	loop
		if v_entry.key not in ('father','mother','relative') then
			continue;
		end if;
		if v_entry.key in ('father','mother','relative') then
			v_managed_relationships := array_append(
				v_managed_relationships,
				case when v_entry.key = 'relative' then 'nearest_relative' else v_entry.key end
			);
		end if;
		v_guardian_name := nullif(btrim(coalesce(v_entry.value->>'full_name', '')), '');
		v_guardian_phone := nullif(regexp_replace(coalesce(v_entry.value->>'phone', ''), '[^0-9]', '', 'g'), '');
		v_guardian_national_id := nullif(regexp_replace(coalesce(v_entry.value->>'national_id', ''), '[^0-9]', '', 'g'), '');
		if v_guardian_name is null and v_guardian_phone is null then
			continue;
		end if;
		if v_guardian_name is null then
			v_guardian_name := case v_entry.key
				when 'father' then 'الأب'
				when 'mother' then 'الأم'
				else 'أقرب قريب'
			end;
		end if;
		if v_guardian_phone is not null and v_guardian_phone !~ '^09[0-9]{8}$' then
			raise exception 'رقم هاتف ولي الأمر يجب أن يبدأ بـ 09 ويتكون من 10 أرقام';
		end if;
		if v_guardian_national_id is not null and length(v_guardian_national_id) <> 12 then
			raise exception 'الرقم الوطني لولي الأمر يجب أن يتكون من 12 رقمًا';
		end if;

		v_guardian_id := nullif(v_entry.value->>'guardian_id', '')::uuid;
		if v_guardian_id is not null then
			if not exists (
				select 1 from public.guardians g
				where g.id = v_guardian_id
				  and g.school_id = v_school_id
			) then
				raise exception 'ولي الأمر المحدد غير موجود في المدرسة الحالية';
			end if;
			if nullif(btrim(coalesce(v_entry.value->>'guardian_app_login_status', '')), '') is not null then
				update public.guardians
				set guardian_app_login_status = lower(v_entry.value->>'guardian_app_login_status'),
					guardian_app_login_enabled = lower(v_entry.value->>'guardian_app_login_status') in ('active','reset_required'),
					updated_at = now()
				where id = v_guardian_id and school_id = v_school_id;
			end if;
		else
			select g.id into v_guardian_id
			from public.guardians g
			where g.school_id = v_school_id
				and (
					(v_guardian_national_id is not null and g.national_id = v_guardian_national_id)
					or (v_guardian_phone is not null and v_guardian_phone in (g.phone, g.phone_alt, g.phone_secondary, g.workplace_phone))
				)
			order by
				case
					when v_guardian_national_id is not null and g.national_id = v_guardian_national_id then 1
					when v_guardian_phone is not null and v_guardian_phone in (g.phone, g.phone_alt, g.phone_secondary, g.workplace_phone) then 2
					else 3
				end,
				g.created_at
			limit 1;
		end if;
		if v_guardian_id is null then
			insert into public.guardians(school_id,full_name,phone,national_id,notes,guardian_app_login_status,guardian_app_login_enabled)
			values (
				v_school_id,
				v_guardian_name,
				v_guardian_phone,
				v_guardian_national_id,
				nullif(btrim(coalesce(
					v_entry.value->>'notes',
					case when nullif(btrim(v_entry.value->>'relationship_label'),'') is not null
						then 'صلة القرابة: ' || btrim(v_entry.value->>'relationship_label')
						else null
					end
				)), ''),
				coalesce(nullif(lower(v_entry.value->>'guardian_app_login_status'), ''), 'not_created'),
				coalesce((lower(v_entry.value->>'guardian_app_login_status') in ('active','reset_required')), false)
			)
			returning id into v_guardian_id;
		end if;

		v_relationship := case when v_entry.key = 'relative' then 'nearest_relative' else v_entry.key end;
		v_is_primary := v_entry.key = 'father';
		if not (v_guardian_id = any(v_guardian_ids)) then
			v_guardian_ids := array_append(v_guardian_ids, v_guardian_id);
		end if;
		v_links := v_links || jsonb_build_array(jsonb_build_object(
			'guardian_id', v_guardian_id,
			'relationship', v_relationship,
			'is_primary', v_is_primary,
			'can_collect_file', v_entry.key in ('father','mother')
		));
	end loop;

	if cardinality(v_managed_relationships) > 0 then
		delete from public.student_guardians sg
		where sg.student_id = p_student_id
			and sg.relationship = any(v_managed_relationships)
			and sg.guardian_id <> all(v_guardian_ids);
	end if;
	for v_checklist_item in
		select value from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb))
	loop
		if nullif(btrim(coalesce(v_checklist_item->>'code','')), '') is null then
			raise exception 'عنصر قائمة الملفات بلا رمز';
		end if;
		insert into public.student_file_checklist_items as existing_item (
			student_id,item_code,item_label,category,is_received,received_at,updated_by
		) values (
			p_student_id,
			v_checklist_item->>'code',
			coalesce(nullif(btrim(v_checklist_item->>'label'),''),v_checklist_item->>'code'),
			coalesce(nullif(v_checklist_item->>'category',''),'core'),
			coalesce((v_checklist_item->>'is_received')::boolean,false),
			case when coalesce((v_checklist_item->>'is_received')::boolean,false) then current_date else null end,
			auth.uid()
		)
		on conflict (student_id,item_code) do update set
			item_label = excluded.item_label,
			category = excluded.category,
			is_received = excluded.is_received,
			received_at = case
				when excluded.is_received then coalesce(existing_item.received_at, excluded.received_at)
				else null
			end,
			updated_by = excluded.updated_by,
			updated_at = now();
		v_checklist_count := v_checklist_count + 1;
	end loop;

	select id into v_note_id
	from public.student_notes
	where student_id = p_student_id and note_type = 'general'
	order by created_at desc
	limit 1
	for update;
	if nullif(btrim(coalesce(p_note,'')), '') is null then
		delete from public.student_notes
		where student_id = p_student_id and note_type = 'general';
	elsif v_note_id is null then
		insert into public.student_notes(student_id,note_type,note_text,created_by)
		values(p_student_id,'general',btrim(p_note),auth.uid());
	else
		update public.student_notes
		set note_text = btrim(p_note), updated_at = now()
		where id = v_note_id;
	end if;
	if v_note_id is not null and nullif(btrim(coalesce(p_note,'')), '') is not null then
		delete from public.student_notes
		where student_id = p_student_id and note_type = 'general' and id <> v_note_id;
	end if;

	for v_entry in select value from jsonb_array_elements(v_links)
	loop
		v_is_primary := coalesce((v_entry.value->>'is_primary')::boolean,false);
		if v_is_primary and exists (
			select 1 from public.student_guardians sg
			where sg.student_id = p_student_id
				and sg.guardian_id <> (v_entry.value->>'guardian_id')::uuid
				and (sg.is_primary or sg.is_primary_contact)
		) then
			v_is_primary := false;
		end if;
		insert into public.student_guardians as existing_link (
			student_id,guardian_id,relationship,is_primary,is_primary_contact,can_collect_file
		) values (
			p_student_id,
			(v_entry.value->>'guardian_id')::uuid,
			v_entry.value->>'relationship',
			v_is_primary,
			false,
			coalesce((v_entry.value->>'can_collect_file')::boolean,false)
		)
		on conflict (student_id,guardian_id) do update set
			relationship = case
				when excluded.relationship in ('father','mother') then excluded.relationship
				else existing_link.relationship
			end,
			is_primary = existing_link.is_primary or excluded.is_primary,
			is_primary_contact = existing_link.is_primary_contact,
			can_collect_file = existing_link.can_collect_file;
	end loop;

	v_result := jsonb_build_object(
		'student_id', v_saved_student.id,
		'guardian_links', jsonb_array_length(v_links),
		'checklist_items', v_checklist_count
	);
	update public.idempotency_keys
	set result = v_result, status = 'completed', completed_at = now()
	where key = v_request_key;
	return jsonb_build_object(
		'student', to_jsonb(v_saved_student),
		'guardian_links', jsonb_array_length(v_links),
		'checklist_items', v_checklist_count
	);
end;
$$;

create or replace function public.next_employee_number(p_school_id uuid)
returns text
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_next bigint;
begin
	if p_school_id is null then
		raise exception 'معرّف المدرسة مطلوب لتوليد رقم الموظف';
	end if;

	insert into public.employee_number_counters(school_id, last_number)
	select p_school_id,
				 coalesce(max(substring(employee_number from '^EMP-([0-9]+)$')::bigint), 0)
	from public.employees
	where school_id = p_school_id
	on conflict (school_id) do nothing;

	update public.employee_number_counters
	set last_number = last_number + 1,
			updated_at = now()
	where school_id = p_school_id
	returning last_number into v_next;

	if v_next is null then
		raise exception 'تعذر توليد رقم الموظف لهذه المدرسة';
	end if;

	return 'EMP-' || lpad(v_next::text, 4, '0');
end;
$$;

create or replace function public.next_employee_number()
returns text
language sql
security definer
set search_path=public,app,pg_temp
as $$
	select public.next_employee_number(app.current_school_id());
$$;

create or replace function public.generate_employee_number()
returns trigger
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
begin
	if new.employee_number is null or btrim(new.employee_number) = '' then
		new.employee_number := public.next_employee_number(new.school_id);
	end if;
	return new;
end;
$$;

create or replace function public.next_receipt_number(p_school_id uuid)
returns text
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  v_existing_max bigint;
  v_next bigint;
begin
  perform app.require_perm('finance.payments.create');
  if p_school_id is null or p_school_id <> app.current_school_id() then
    raise exception 'معرّف المدرسة غير صالح';
  end if;

  select coalesce(max(receipt_number::bigint), 0)
    into v_existing_max
  from public.payments
  where school_id = p_school_id
    and receipt_number ~ '^[0-9]{8}$';

  insert into public.finance_receipt_counters(school_id, last_number)
  values (p_school_id, v_existing_max)
  on conflict (school_id) do nothing;

  update public.finance_receipt_counters
  set last_number = greatest(last_number, v_existing_max) + 1,
      updated_at = now()
  where school_id = p_school_id
  returning last_number into v_next;

  if v_next is null or v_next > 99999999 then
    raise exception 'تم الوصول إلى الحد الأقصى لرموز الإيصالات في هذه المدرسة';
  end if;

  return lpad(v_next::text, 8, '0');
end;
$$;
revoke execute on function public.next_receipt_number(uuid) from public, anon, authenticated;

create or replace function public.ensure_default_fee_catalog(p_school_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  v_tuition uuid;
  v_mental uuid;
  v_pack uuid;
  v_uniform_boys uuid;
  v_uniform_girls uuid;
  v_year record;
  v_grade record;
  v_plan_id uuid;
  v_tuition_amount numeric;
  v_mental_amount numeric;
  v_pack_amount numeric;
begin
  if p_school_id is null or p_school_id <> app.current_school_id() then
    raise exception 'معرّف المدرسة غير صالح';
  end if;

  perform app.require_perm('finance.fees.manage');

  insert into public.fee_types(
    school_id, code, name_ar, is_recurring, is_active, sort_order,
    gender_scope, allow_installments, default_installment_count
  ) values
    (p_school_id, 'tuition', 'القسط الدراسي', true, true, 1, null, true, 4),
    (p_school_id, 'mental_account', 'الحساب الذهني', true, true, 2, null, true, 1),
    (p_school_id, 'supplementary_pack', 'المجموعة المكملة', true, true, 3, null, true, 1),
    (p_school_id, 'uniform_boys', 'زي بنين', false, true, 4, 'male', false, 1),
    (p_school_id, 'uniform_girls', 'زي بنات', false, true, 5, 'female', false, 1)
  on conflict (school_id, name_ar) do nothing;

  select id into v_tuition from public.fee_types where school_id = p_school_id and code = 'tuition' limit 1;
  select id into v_mental from public.fee_types where school_id = p_school_id and code = 'mental_account' limit 1;
  select id into v_pack from public.fee_types where school_id = p_school_id and code = 'supplementary_pack' limit 1;
  select id into v_uniform_boys from public.fee_types where school_id = p_school_id and code = 'uniform_boys' limit 1;
  select id into v_uniform_girls from public.fee_types where school_id = p_school_id and code = 'uniform_girls' limit 1;

  for v_year in select * from public.academic_years where school_id = p_school_id order by start_date loop
    for v_grade in select * from public.school_grades where school_id = p_school_id order by level_number loop
      if v_grade.level_number in (-4, -3, -2, -1) then
        v_tuition_amount := 1800; v_mental_amount := 0; v_pack_amount := 0;
      elsif v_grade.level_number between 1 and 6 then
        v_tuition_amount := 2100 + ((v_grade.level_number - 1) * 100); v_mental_amount := 350; v_pack_amount := 200;
      elsif v_grade.level_number = 7 then
        v_tuition_amount := 2900; v_mental_amount := 0; v_pack_amount := 0;
      elsif v_grade.level_number = 8 then
        v_tuition_amount := 3000; v_mental_amount := 0; v_pack_amount := 0;
      elsif v_grade.level_number = 9 then
        v_tuition_amount := 3200; v_mental_amount := 0; v_pack_amount := 0;
      else
        v_tuition_amount := 0; v_mental_amount := 0; v_pack_amount := 0;
      end if;

      insert into public.fee_plans(school_id, academic_year_id, grade_id, name_ar)
      values (p_school_id, v_year.id, v_grade.id, 'رسوم ' || coalesce(v_grade.name_ar, v_grade.code))
      on conflict (academic_year_id, grade_id) do nothing;

      select id into v_plan_id
      from public.fee_plans
      where school_id = p_school_id
        and academic_year_id = v_year.id
        and grade_id = v_grade.id
      limit 1;

	if v_plan_id is not null and v_tuition is not null and v_tuition_amount > 0 then
        insert into public.fee_plan_items(
          fee_plan_id, fee_type_id, amount, is_mandatory, is_active,
          default_installment_count, notes
        ) values (
          v_plan_id, v_tuition, v_tuition_amount, true, true, 4,
          'القسط الدراسي الأساسي'
        ) on conflict (fee_plan_id, fee_type_id) do nothing;
      end if;

      if v_plan_id is not null and v_mental_amount > 0 then
        insert into public.fee_plan_items(
          fee_plan_id, fee_type_id, amount, is_mandatory, is_active,
          default_installment_count, notes
        ) values (
          v_plan_id, v_mental, v_mental_amount, true, true, 1, 'الحساب الذهني'
        ) on conflict (fee_plan_id, fee_type_id) do nothing;
      end if;

      if v_plan_id is not null and v_pack_amount > 0 then
        insert into public.fee_plan_items(
          fee_plan_id, fee_type_id, amount, is_mandatory, is_active,
          default_installment_count, notes
        ) values (
          v_plan_id, v_pack, v_pack_amount, true, true, 1, 'المجموعة المكملة'
        ) on conflict (fee_plan_id, fee_type_id) do nothing;
      end if;

      if v_plan_id is not null then
        insert into public.fee_plan_items(
          fee_plan_id, fee_type_id, amount, is_mandatory, is_active,
          default_installment_count, notes
        ) values
          (v_plan_id, v_uniform_boys, 310, false, true, 1, 'زي بنين - بدون بنطلون'),
          (v_plan_id, v_uniform_girls, 440, false, true, 1, 'زي بنات - كامل')
        on conflict (fee_plan_id, fee_type_id) do nothing;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('school_id', p_school_id, 'initialized', true);
end;
$$;

create or replace function public.create_student_fee(
  p_enrollment_id uuid,
  p_fee_type_id uuid,
  p_amount numeric,
  p_discount_amount numeric default 0,
  p_exemption_amount numeric default 0,
  p_installment_count smallint default 1,
  p_first_due_date date default null,
  p_interval_months smallint default 1,
  p_price_override_reason text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  v_enrollment public.student_enrollments%rowtype;
  v_student public.students%rowtype;
  v_year public.academic_years%rowtype;
  v_plan_id uuid;
  v_item public.fee_plan_items%rowtype;
  v_type public.fee_types%rowtype;
  v_fee public.student_fees%rowtype;
  v_net numeric(14,2);
  v_base numeric(14,2);
  v_amount numeric(14,2);
  v_sequence integer;
begin
  perform app.require_perm('finance.fees.manage');
  if p_amount is null or p_amount <= 0 or p_installment_count is null or p_installment_count < 1
    or p_interval_months is null or p_interval_months < 1 then
    raise exception 'بيانات الرسوم أو الأقساط غير صالحة';
  end if;
  if coalesce(p_discount_amount, 0) < 0 or coalesce(p_exemption_amount, 0) < 0
    or coalesce(p_discount_amount, 0) + coalesce(p_exemption_amount, 0) > p_amount then
    raise exception 'قيمة الخصم أو الإعفاء غير صالحة';
  end if;

  select e.* into v_enrollment
  from public.student_enrollments e
  join public.students s on s.id = e.student_id
  where e.id = p_enrollment_id
    and s.school_id = app.current_school_id()
  for update of e;
  if not found then raise exception 'تسجيل الطالب غير موجود في المدرسة الحالية'; end if;

  select s.* into v_student from public.students s
  where s.id = v_enrollment.student_id
    and s.school_id = app.current_school_id();
  select y.* into v_year from public.academic_years y
  where y.id = v_enrollment.academic_year_id
    and y.school_id = app.current_school_id();
  if not found then raise exception 'السنة الدراسية غير موجودة في المدرسة الحالية'; end if;
  if v_year.status in ('closed','archived','مغلقة','مؤرشفة') then
    raise exception 'السنة الدراسية مغلقة؛ لا يمكن إنشاء رسوم جديدة';
  end if;

  select ft.* into v_type from public.fee_types ft
  where ft.id = p_fee_type_id
    and ft.school_id = app.current_school_id()
    and ft.is_active;
  if not found then raise exception 'نوع الرسوم غير فعال أو غير موجود'; end if;
  if v_type.gender_scope is not null and v_student.gender is distinct from v_type.gender_scope then
    raise exception 'نوع الزي لا يتوافق مع جنس الطالب';
  end if;
  if not v_type.allow_installments and p_installment_count <> 1 then
    raise exception 'هذا النوع من الرسوم لا يقبل التقسيط';
  end if;

  select fp.id into v_plan_id from public.fee_plans fp
  where fp.school_id = app.current_school_id()
    and fp.academic_year_id = v_enrollment.academic_year_id
    and fp.grade_id = v_enrollment.grade_id
  limit 1;
  if v_plan_id is null then raise exception 'لا توجد خطة رسوم للصف والسنة المختارين'; end if;

  select fi.* into v_item from public.fee_plan_items fi
  where fi.fee_plan_id = v_plan_id
    and fi.fee_type_id = p_fee_type_id
    and fi.is_active
  for update;
  if not found then raise exception 'نوع الرسوم غير متاح للصف والسنة المختارين'; end if;

  v_net := greatest(p_amount - coalesce(p_discount_amount, 0) - coalesce(p_exemption_amount, 0), 0);
  v_base := round(v_net / p_installment_count, 2);

  insert into public.student_fees(
    enrollment_id, academic_year_id, fee_plan_id, fee_type_id,
    default_amount, total_amount, discount_amount, exemption_amount,
    price_override_reason, is_mandatory, notes
  ) values (
    v_enrollment.id, v_enrollment.academic_year_id, v_plan_id, p_fee_type_id,
    v_item.amount, p_amount, coalesce(p_discount_amount, 0),
    coalesce(p_exemption_amount, 0), nullif(btrim(p_price_override_reason), ''),
    v_item.is_mandatory, nullif(btrim(p_notes), '')
  ) returning * into v_fee;

  for v_sequence in 1..p_installment_count loop
    v_amount := case when v_sequence = p_installment_count
      then v_net - v_base * (p_installment_count - 1)
      else v_base end;
    insert into public.installments(
      student_fee_id, fee_type_id, sequence_number, due_date, amount
    ) values (
      v_fee.id, p_fee_type_id, v_sequence,
      case when p_first_due_date is null then null
        else (p_first_due_date + ((v_sequence - 1) * p_interval_months || ' months')::interval)::date
      end,
      v_amount
    );
  end loop;

  insert into public.audit_logs(
    user_id, actor_id, action, entity_type, entity_id,
    academic_year_id, old_value, new_value, description
  ) values (
    auth.uid(), auth.uid(), 'student_fee.created', 'student_fee', v_fee.id::text,
    v_enrollment.academic_year_id, null,
    jsonb_build_object(
      'enrollment_id', v_enrollment.id,
      'fee_type_id', p_fee_type_id,
      'default_amount', v_item.amount,
      'approved_amount', p_amount,
      'discount_amount', coalesce(p_discount_amount, 0),
      'exemption_amount', coalesce(p_exemption_amount, 0),
      'installment_count', p_installment_count,
      'override_reason', nullif(btrim(p_price_override_reason), '')
    ),
    'تم إنشاء استحقاق رسوم مصنف للطالب'
  );

  return jsonb_build_object(
    'id', v_fee.id,
    'default_amount', v_item.amount,
    'approved_amount', p_amount,
    'net_amount', v_net,
    'fee_type_id', p_fee_type_id,
    'installment_count', p_installment_count
  );
exception when unique_violation then
  raise exception 'يوجد بالفعل استحقاق من نوع الرسوم هذا لهذا التسجيل';
end;
$$;

create or replace function public.finance_create_payment_atomic(
  p_installment_id uuid,
  p_amount numeric,
  p_method app.payment_method,
  p_payment_date date,
  p_payer_name text,
  p_reference text,
  p_notes text,
  p_idempotency_key text,
  p_bank_name text
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  i public.installments%rowtype;
  p public.payments%rowtype;
  existing_payment public.payments%rowtype;
  v_student public.students%rowtype;
  v_year public.academic_years%rowtype;
  v_academic_year_id uuid;
  v_type_name text;
  v_school_snapshot jsonb;
  v_snapshot jsonb;
  v_receipt text;
begin
  perform app.require_perm('finance.payments.create');
  if p_idempotency_key is not null then
    select * into existing_payment from public.payments
    where school_id = app.current_school_id()
      and idempotency_key = p_idempotency_key
    for update;
    if found then
      return jsonb_build_object(
        'payment_id', existing_payment.id,
        'receipt_number', existing_payment.receipt_number,
        'is_duplicate', true
      );
    end if;
  end if;
  if p_method = 'cheque' and nullif(btrim(p_bank_name), '') is null then
    raise exception 'اسم المصرف مطلوب عند الدفع بصك';
  end if;

  select inst.* into i
  from public.installments inst
  join public.student_fees f on f.id = inst.student_fee_id
  join public.student_enrollments e on e.id = f.enrollment_id
  join public.students s on s.id = e.student_id
  where inst.id = p_installment_id
    and s.school_id = app.current_school_id()
  for update of inst;
  if not found or p_amount is null or p_amount <= 0 or p_amount > i.remaining_amount + 0.01 then
    raise exception 'قيمة الدفعة غير صالحة';
  end if;

  select s.* into v_student
  from public.installments inst
  join public.student_fees sf on sf.id = inst.student_fee_id
  join public.student_enrollments e on e.id = sf.enrollment_id
  join public.students s on s.id = e.student_id
  where inst.id = p_installment_id
    and s.school_id = app.current_school_id();
  if not found then
    raise exception 'بيانات الطالب المرتبطة بالقسط غير موجودة';
  end if;

  select sf.academic_year_id into v_academic_year_id
  from public.installments inst
  join public.student_fees sf on sf.id = inst.student_fee_id
  where inst.id = p_installment_id;

  select y.* into v_year
  from public.academic_years y
  where y.id = v_academic_year_id
    and y.school_id = app.current_school_id();

  select ft.name_ar into v_type_name
  from public.fee_types ft
  where ft.id = (
    select sf.fee_type_id
    from public.installments inst
    join public.student_fees sf on sf.id = inst.student_fee_id
    where inst.id = p_installment_id
  ) and ft.school_id = app.current_school_id();

  select jsonb_build_object(
    'name_ar', ss.name_ar,
    'official_name_ar', ss.official_name_ar,
    'address', ss.address,
    'phone', ss.phone,
    'phone_alt', ss.phone_alt,
    'email', ss.email,
    'logo_storage_path', ss.logo_storage_path
  ) into v_school_snapshot from public.school_settings ss where ss.id = 1;

  v_receipt := public.next_receipt_number(app.current_school_id());
  insert into public.payments(
    school_id, student_id, academic_year_id, installment_id, amount,
    method, payment_method, payment_date, payer_name, reference, notes,
    bank_name, receipt_number, idempotency_key, created_by
  ) values (
    app.current_school_id(), v_student.id, v_academic_year_id, i.id, p_amount,
    p_method, p_method::text, p_payment_date, nullif(btrim(p_payer_name), ''),
    nullif(btrim(p_reference), ''), nullif(btrim(p_notes), ''),
    nullif(btrim(p_bank_name), ''), v_receipt, p_idempotency_key, auth.uid()
  ) returning * into p;

  update public.installments
  set paid_amount = paid_amount + p_amount,
      status = case
        when paid_amount + p_amount >= net_due then 'paid'::app.installment_status
        when paid_amount + p_amount > 0 then 'partial'::app.installment_status
        else 'pending'::app.installment_status
      end
  where id = i.id;

  v_snapshot := jsonb_build_object(
    'receipt_number', p.receipt_number,
    'payment_id', p.id,
    'student_id', v_student.id,
    'student_name', v_student.full_name,
    'student_number', v_student.student_number,
    'academic_year_id', v_academic_year_id,
    'academic_year', coalesce(v_year.name_ar, v_year.code),
    'fee_type', coalesce(v_type_name, 'رسوم سابقة غير مصنفة'),
    'installment_id', i.id,
    'installment_number', i.sequence_number,
    'due_date', i.due_date,
    'payer_name', p.payer_name,
    'amount', p.amount,
    'method', coalesce(p.payment_method, p.method::text),
    'bank_name', p.bank_name,
    'reference', p.reference,
    'notes', p.notes,
    'issued_by', coalesce((select nullif(btrim(pr.full_name), '') from public.profiles pr where pr.id = auth.uid()), '')
  );
  v_snapshot := v_snapshot || jsonb_build_object('school', coalesce(v_school_snapshot, '{}'::jsonb));

  insert into public.finance_receipts(
    school_id, payment_id, receipt_number, snapshot, issued_by
  ) values (
    p.school_id, p.id, p.receipt_number, v_snapshot, auth.uid()
  ) on conflict (payment_id) do update set
    receipt_number = excluded.receipt_number,
    snapshot = excluded.snapshot,
    issued_by = excluded.issued_by,
    issued_at = now();

  insert into public.audit_logs(
    user_id, actor_id, action, entity_type, entity_id,
    academic_year_id, old_value, new_value, description
  ) values (
    auth.uid(), auth.uid(), 'payment.created', 'payment', p.id::text,
    v_academic_year_id,
    jsonb_build_object('installment_id', i.id, 'amount', p_amount),
    to_jsonb(p),
    'تم تسجيل دفعة جديدة مع رقم إيصال ' || p.receipt_number
  );

  return jsonb_build_object(
    'payment_id', p.id,
    'receipt_id', (select r.id from public.finance_receipts r where r.payment_id = p.id),
    'receipt_number', p.receipt_number,
    'amount', p.amount,
    'is_duplicate', false,
    'remaining_after', greatest(0, i.remaining_amount - p_amount)
  );
end;
$$;
revoke execute on function public.finance_create_payment_atomic(uuid,numeric,app.payment_method,date,text,text,text,text,text) from public, anon, authenticated;

create or replace function public.create_payment(
  p_installment_id uuid,
  p_amount numeric,
  p_method app.payment_method default 'cash',
  p_payment_date date default current_date,
  p_payer_name text default null,
  p_reference text default null,
  p_notes text default null,
  p_idempotency_key text default null
)
returns jsonb
language sql
security definer
set search_path=public,app,pg_temp
as $$
  select public.finance_create_payment_atomic(
    p_installment_id, p_amount, p_method, p_payment_date, p_payer_name,
    p_reference, p_notes, p_idempotency_key, null
  );
$$;

create or replace function public.create_payment_with_bank(
  p_installment_id uuid,
  p_amount numeric,
  p_method app.payment_method,
  p_payment_date date,
  p_payer_name text,
  p_reference text,
  p_notes text,
  p_idempotency_key text,
  p_bank_name text
)
returns jsonb
language sql
security definer
set search_path=public,app,pg_temp
as $$
  select public.finance_create_payment_atomic(
    p_installment_id, p_amount, p_method, p_payment_date, p_payer_name,
    p_reference, p_notes, p_idempotency_key, p_bank_name
  );
$$;

create or replace function public.generate_installments(
  p_student_fee_id uuid,
  p_count smallint,
  p_first_due_date date default null,
  p_interval_months smallint default 1
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  f public.student_fees%rowtype;
  v_amount numeric;
  v_sequence integer;
begin
  perform app.require_perm('finance.fees.manage');
  select sf.* into f
  from public.student_fees sf
  join public.student_enrollments e on e.id = sf.enrollment_id
  join public.students s on s.id = e.student_id
  where sf.id = p_student_fee_id
    and s.school_id = app.current_school_id()
  for update of sf;
  if not found or p_count < 1 or p_interval_months < 1 then
    raise exception 'بيانات خطة الرسوم غير صالحة';
  end if;

  v_amount := round(f.net_amount / p_count, 2);
  for v_sequence in 1..p_count loop
    insert into public.installments(
      student_fee_id, fee_type_id, sequence_number, due_date, amount
    ) values (
      f.id, f.fee_type_id, v_sequence,
      case when p_first_due_date is null then null
        else (p_first_due_date + ((v_sequence - 1) * p_interval_months || ' months')::interval)::date
      end,
      case when v_sequence = p_count
        then f.net_amount - v_amount * (p_count - 1)
        else v_amount
      end
    );
  end loop;

  return jsonb_build_object('created', p_count);
end;
$$;

create or replace function public.create_expense(
  p_academic_year_id uuid,
  p_category_id uuid,
  p_amount numeric,
  p_expense_date date,
  p_description text,
  p_payee text default null,
  p_method text default 'cash',
  p_reference_number text default null,
  p_document_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  v_expense public.expenses%rowtype;
begin
  perform app.require_perm('finance.expenses.manage');
  if p_amount is null or p_amount <= 0 or p_expense_date is null or nullif(btrim(p_description), '') is null then
    raise exception 'بيانات المصروف غير صالحة';
  end if;
  if p_academic_year_id is not null and not exists (
    select 1 from public.academic_years y
    where y.id = p_academic_year_id and y.school_id = app.current_school_id()
  ) then
    raise exception 'السنة الدراسية لا تنتمي إلى المدرسة الحالية';
  end if;
  if not exists (
    select 1 from public.expense_categories c
    where c.id = p_category_id and c.is_active
  ) then
    raise exception 'نوع المصروف غير فعال أو غير موجود';
  end if;

  insert into public.expenses(
    school_id, academic_year_id, category_id, amount, expense_date,
    description, payee, method, reference_number, document_path,
    recorded_by, created_by, status
  ) values (
    app.current_school_id(), p_academic_year_id, p_category_id, p_amount,
    p_expense_date, btrim(p_description), nullif(btrim(p_payee), ''),
    coalesce(nullif(btrim(p_method), ''), 'cash'),
    nullif(btrim(p_reference_number), ''), nullif(btrim(p_document_path), ''),
    auth.uid(), auth.uid(), 'completed'
  ) returning * into v_expense;

  insert into public.audit_logs(
    user_id, actor_id, action, entity_type, entity_id, academic_year_id,
    old_value, new_value, description
  ) values (
    auth.uid(), auth.uid(), 'expense.created', 'expense', v_expense.id::text,
    p_academic_year_id, null, to_jsonb(v_expense), 'تم تسجيل مصروف'
  );

  return jsonb_build_object('id', v_expense.id, 'created', true);
end;
$$;

create or replace function public.void_expense(p_expense_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
  v_expense public.expenses%rowtype;
begin
  perform app.require_perm('finance.expenses.void');
  if nullif(btrim(p_reason), '') is null then
    raise exception 'سبب الإلغاء مطلوب';
  end if;

  select * into v_expense from public.expenses
  where id = p_expense_id and school_id = app.current_school_id()
  for update;
  if not found or v_expense.status = 'voided' then
    raise exception 'المصروف غير موجود أو ملغى مسبقًا';
  end if;

  update public.expenses
  set status = 'voided', void_reason = btrim(p_reason), updated_at = now()
  where id = v_expense.id;

  insert into public.audit_logs(
    user_id, actor_id, action, entity_type, entity_id, academic_year_id,
    old_value, new_value, description
  ) values (
    auth.uid(), auth.uid(), 'expense.voided', 'expense', v_expense.id::text,
    v_expense.academic_year_id, to_jsonb(v_expense),
    jsonb_build_object('status', 'voided', 'reason', btrim(p_reason)),
    'تم إلغاء مصروف مع الاحتفاظ بالسجل'
  );

  return jsonb_build_object('id', v_expense.id, 'voided', true);
end;
$$;

grant execute on function public.create_student_fee(uuid,uuid,numeric,numeric,numeric,smallint,date,smallint,text,text) to authenticated;
grant execute on function public.create_payment(uuid,numeric,app.payment_method,date,text,text,text,text) to authenticated;
grant execute on function public.create_payment_with_bank(uuid,numeric,app.payment_method,date,text,text,text,text,text) to authenticated;
grant execute on function public.create_expense(uuid,uuid,numeric,date,text,text,text,text,text) to authenticated;
grant execute on function public.void_expense(uuid,text) to authenticated;

create or replace function public.is_school_day_for_year(
  p_academic_year_id uuid,
  p_attendance_date date
) returns boolean
language sql
security definer
set search_path=public,app,pg_temp
as $$
  select coalesce(
    (
      select s.is_school_day
      from public.school_calendar_exceptions s
      where s.academic_year_id = p_academic_year_id
        and s.exception_date = p_attendance_date
      order by s.updated_at desc, s.created_at desc
      limit 1
    ),
    (
      select w.is_school_day
      from public.week_days w
      where w.day_number = extract(dow from p_attendance_date)::smallint
      limit 1
    ),
    false
  );
$$;

grant execute on function public.is_school_day_for_year(uuid,date) to authenticated;

create or replace function public.save_class_attendance(
	p_class_id uuid,
	p_attendance_date date,
	p_records jsonb,
	p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	x jsonb;
	v_status text;
	v_saved integer := 0;
	v_class classes%rowtype;
	v_year academic_years%rowtype;
	v_enrollment student_enrollments%rowtype;
	v_actor_label text;
begin
	perform app.require_perm('attendance.students.manage');
	select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.username), ''))
	into v_actor_label
	from public.profiles p
	where p.id=auth.uid();
	if p_attendance_date is null then
		raise exception 'تاريخ الحضور مطلوب';
	end if;

	select c.* into v_class
	from public.classes c
	where c.id=p_class_id
		and c.school_id=app.current_school_id();
	if not found then raise exception 'الفصل لا ينتمي إلى المدرسة الحالية'; end if;
	select y.* into v_year
	from public.academic_years y
	where y.id=v_class.academic_year_id
		and y.school_id=app.current_school_id();
	if not found then raise exception 'السنة الدراسية لا تنتمي إلى المدرسة الحالية'; end if;
	if v_year.status in ('closed','archived','مغلقة','مؤرشفة') then
		raise exception 'لا يمكن تعديل حضور سنة دراسية مغلقة أو مؤرشفة';
	end if;
	if not public.is_school_day_for_year(v_year.id, p_attendance_date) then
		raise exception 'لا يمكن تسجيل الحضور في يوم غير دراسي أو عطلة. يرجى اختيار يوم مدرسي.';
	end if;

	for x in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
		v_status := coalesce(nullif(x->>'status',''), nullif(x->>'status_code',''));
		if v_status is null or not exists (
			select 1 from public.attendance_statuses s
			where s.code=v_status and s.is_active
		) then
			raise exception 'حالة حضور غير صالحة: %', coalesce(v_status,'فارغة');
		end if;

		select e.* into v_enrollment
		from public.student_enrollments e
		join public.students s on s.id=e.student_id
		where e.id=(x->>'enrollment_id')::uuid
			and e.academic_year_id=v_class.academic_year_id
			and e.class_id=p_class_id
			and s.school_id=app.current_school_id()
			and coalesce(e.outcome,'in_progress')='in_progress';
		if not found then raise exception 'تسجيل الطالب لا يطابق السنة والفصل المحددين'; end if;

		insert into public.student_attendance(
			student_id,enrollment_id,academic_year_id,class_id,attendance_date,
			status,status_code,recorded_by
		) values (
			v_enrollment.student_id,v_enrollment.id,v_enrollment.academic_year_id,
			v_enrollment.class_id,p_attendance_date,v_status,v_status,auth.uid()
		)
		on conflict(enrollment_id,attendance_date) do update set
			status=excluded.status,
			status_code=excluded.status_code,
			recorded_by=excluded.recorded_by,
			updated_at=now();
		v_saved := v_saved + 1;
		insert into public.audit_logs(
			user_id,actor_id,actor_label,action,entity_type,entity_id,academic_year_id,new_value,description
		) values (
			auth.uid(),auth.uid(),coalesce(v_actor_label,'مستخدم غير معروف'),'attendance.saved','student_attendance',
			v_enrollment.student_id::text,v_enrollment.academic_year_id,
			jsonb_build_object('enrollment_id',v_enrollment.id,'class_id',p_class_id,
				'attendance_date',p_attendance_date,'status',v_status),
			'تم حفظ حضور الطالب'
		);
	end loop;
	return jsonb_build_object('saved',v_saved,'total',v_saved);
end $$;
-- One permission-scoped Arabic matcher shared by the student, employee, and guardian lists.
create or replace function public.search_people_names(
	p_entity_type text,
	p_query text,
	p_limit integer default 100,
	p_include_withdrawn boolean default false
)
returns table(id uuid, full_name text, similarity_score real, match_kind text)
language plpgsql volatile security invoker
set search_path = pg_catalog, public, app, extensions, pg_temp
as $$
declare
	v_query text := app.normalize_ar(nullif(btrim(coalesce(p_query, '')), ''));
	v_limit integer := greatest(1, least(coalesce(p_limit, 100),
		case
			when length(app.normalize_ar_compact(v_query)) <= 3 then 30
			when length(app.normalize_ar_compact(v_query)) <= 5 then 100
			else 500
		end));
begin
	if p_entity_type not in ('student', 'guardian', 'employee') then
		raise exception 'نوع البحث غير مدعوم';
	end if;
	if v_query is null or length(app.normalize_ar_compact(v_query)) < 1 then
		return;
	end if;
	if not app.is_active_user() then
		return;
	end if;
	perform set_config('pg_trgm.word_similarity_threshold', '0.30', true);

	return query
	with query_value as (
		select v_query as normalized, app.normalize_ar_compact(v_query) as compact
	), source as (
		select 'student'::text as kind, s.id as person_id, s.full_name as person_name
		from public.students s
		where p_entity_type = 'student'
			and s.school_id = app.current_school_id()
			and not coalesce(s.is_archived, false)
			and (p_include_withdrawn or s.educational_status <> 'withdrawn')
			and (not p_include_withdrawn or app.has_perm('students.archive'))
			and app.has_any_perm('students.manage','students.view','students.create',
				'students.edit','students.archive','students.enrollment.manage')
		union all
		select 'guardian', g.id, g.full_name
		from public.guardians g
		where p_entity_type = 'guardian'
			and g.school_id = app.current_school_id()
			and app.has_any_perm('guardians.view','guardians.manage','students.manage',
				'students.view','students.create','students.edit')
		union all
		select 'employee', e.id, e.full_name
		from public.employees e
		where p_entity_type = 'employee'
			and e.school_id = app.current_school_id()
			and app.has_perm('employees.view')
	), normalized_names as (
		select source.person_id, source.person_name,
			app.normalize_ar(source.person_name) as normalized,
			app.normalize_ar_compact(source.person_name) as compact
		from source
	), scored as (
		select n.person_id, n.person_name, n.normalized, n.compact,
			q.normalized as search_text, q.compact as compact_search,
			case
				when n.normalized = q.normalized then 1.0::real
				when position(q.normalized in n.normalized) > 0 then 0.98::real
				when n.compact = q.compact then 0.97::real
				when position(q.compact in n.compact) > 0 then 0.95::real
				else greatest(
					word_similarity(q.normalized, n.normalized),
					word_similarity(q.compact, n.compact),
					case when length(q.compact) >= 5 then greatest(
						word_similarity(replace(q.normalized, 'ة', 'ه'), n.normalized),
						word_similarity(q.normalized, replace(n.normalized, 'ة', 'ه')),
						word_similarity(replace(q.compact, 'ة', 'ه'), n.compact),
						word_similarity(q.compact, replace(n.compact, 'ة', 'ه'))
					) else 0 end
				)::real
			end as relevance
		from normalized_names n
		cross join query_value q
		where position(q.normalized in n.normalized) > 0
			or position(q.compact in n.compact) > 0
			or (length(q.compact) >= 3 and (
				n.normalized %> q.normalized or n.compact %> q.compact
				or (length(q.compact) >= 5 and (
					n.normalized %> replace(q.normalized, 'ة', 'ه')
					or n.normalized %> replace(q.normalized, 'ه', 'ة')
					or n.compact %> replace(q.compact, 'ة', 'ه')
					or n.compact %> replace(q.compact, 'ه', 'ة')
				))
			))
	)
	select s.person_id, s.person_name, s.relevance,
		case
			when s.normalized = s.search_text then 'exact'
			when position(s.search_text in s.normalized) > 0
				or position(s.compact_search in s.compact) > 0 then 'normalized'
			else 'fuzzy'
		end
	from scored s
	where s.relevance >= case
		when position(s.search_text in s.normalized) > 0
			or position(s.compact_search in s.compact) > 0 then 0.0
		when length(s.compact_search) <= 3 then 0.50
		when length(s.compact_search) <= 5 then 0.46
		when length(s.compact_search) <= 7 then 0.42
		else 0.38
	end
	order by s.relevance desc, s.person_name, s.person_id
	limit v_limit;
end;
$$;

create or replace function public.global_search(p_query text, p_limit integer default 20)
returns table(entity_type text, entity_id uuid, title text, subtitle text, similarity_score real)
language sql volatile security invoker
set search_path = pg_catalog, public, app, extensions, pg_temp
as $$
	with people as (
		select 'students'::text entity_type, m.id entity_id, m.full_name title,
			s.student_number subtitle, m.similarity_score
		from public.search_people_names('student', p_query, p_limit) m
		join public.students s on s.id = m.id
		union all
		select 'employees', m.id, m.full_name, e.employee_number, m.similarity_score
		from public.search_people_names('employee', p_query, p_limit) m
		join public.employees e on e.id = m.id
		union all
		select 'guardians', m.id, m.full_name, g.phone, m.similarity_score
		from public.search_people_names('guardian', p_query, p_limit) m
		join public.guardians g on g.id = m.id
		union all
		select 'students', s.id, s.full_name, s.student_number, 1.0::real
		from public.students s
		where s.school_id = app.current_school_id()
			and not coalesce(s.is_archived, false)
			and s.educational_status <> 'withdrawn'
			and app.has_perm('students.view')
			and length(btrim(coalesce(p_query, ''))) >= 2
			and position(lower(coalesce(p_query, '')) in lower(coalesce(s.student_number, ''))) > 0
		union all
		select 'employees', e.id, e.full_name, e.employee_number, 1.0::real
		from public.employees e
		where e.school_id = app.current_school_id()
			and app.has_perm('employees.view')
			and length(btrim(coalesce(p_query, ''))) >= 2
			and position(lower(coalesce(p_query, '')) in lower(coalesce(e.employee_number, ''))) > 0
		union all
		select 'guardians', g.id, g.full_name, g.phone, 1.0::real
		from public.guardians g
		where g.school_id = app.current_school_id()
			and app.has_any_perm('guardians.view','guardians.manage','students.manage',
				'students.view','students.create','students.edit')
			and length(btrim(coalesce(p_query, ''))) >= 2
			and position(lower(coalesce(p_query, '')) in lower(coalesce(g.phone, ''))) > 0
	), deduplicated as (
		select distinct on (entity_type, entity_id) *
		from people
		order by entity_type, entity_id, similarity_score desc
	)
	select deduplicated.entity_type, deduplicated.entity_id, deduplicated.title,
		deduplicated.subtitle, deduplicated.similarity_score
	from deduplicated
	order by deduplicated.similarity_score desc, deduplicated.title
	limit greatest(1, least(p_limit, 100));
$$;
-- Searchable, fuzzy student lookup used only for same-school associations.
-- Keep this RPC beside the other canonical search functions; permissions and
-- execute grants are finalized in migration 006_security_hardening.sql.
create or replace function public.search_students_for_association(
	p_query text,
	p_limit integer default 8
)
returns table (
	id uuid,
	full_name text,
	student_number text,
	registration_number text,
	academic_year text,
	stage_name text,
	grade_name text,
	class_name text,
	similarity_score real
)
language sql
stable
security definer
set search_path = pg_catalog, public, app, extensions, pg_temp
as $$
	with query_value as (
		select nullif(btrim(coalesce(p_query, '')), '') as value,
			app.normalize_ar(nullif(btrim(coalesce(p_query, '')), '')) as normalized,
			app.normalize_ar_compact(nullif(btrim(coalesce(p_query, '')), '')) as compact
	), candidates as (
		select
			s.id,
			s.full_name,
			s.student_number,
			s.registration_number,
			y.name_ar as academic_year,
			st.name_ar as stage_name,
			g.name_ar as grade_name,
			c.name_ar as class_name,
			greatest(
				word_similarity(q.normalized, app.normalize_ar(coalesce(s.full_name, ''))),
				word_similarity(q.compact, app.normalize_ar_compact(coalesce(s.full_name, ''))),
				word_similarity(coalesce(s.student_number, ''), q.value),
				word_similarity(coalesce(s.registration_number, ''), q.value)
			)::real as similarity_score
		from public.students s
		cross join query_value q
		left join lateral (
			select e.academic_year_id, e.grade_id, e.class_id
			from public.student_enrollments e
			left join public.academic_years ay
				on ay.id = e.academic_year_id
				and ay.school_id = s.school_id
			where e.student_id = s.id
			order by ay.is_current desc nulls last,
				e.enrollment_date desc nulls last,
				e.created_at desc
			limit 1
		) enrollment on true
		left join public.academic_years y
			on y.id = enrollment.academic_year_id
			and y.school_id = s.school_id
		left join public.school_grades g
			on g.id = enrollment.grade_id
			and g.school_id = s.school_id
		left join public.academic_stages st
			on st.id = g.stage_id
			and st.school_id = s.school_id
		left join public.classes c
			on c.id = enrollment.class_id
			and c.school_id = s.school_id
			and c.academic_year_id = enrollment.academic_year_id
			and c.grade_id = enrollment.grade_id
		where q.value is not null
			and length(q.value) >= 2
			and s.school_id = app.current_school_id()
			and s.educational_status <> 'withdrawn'
			and not coalesce(s.is_archived, false)
			and app.is_active_user()
			and app.has_any_perm(
				'students.view',
				'students.create',
				'students.edit',
				'guardians.manage',
				'social.manage'
			)
			and (position(q.normalized in app.normalize_ar(coalesce(s.full_name, ''))) > 0
				or position(q.compact in app.normalize_ar_compact(coalesce(s.full_name, ''))) > 0
				or s.student_number ilike '%' || q.value || '%'
				or s.registration_number ilike '%' || q.value || '%'
				or (length(q.compact) >= 3 and greatest(
					word_similarity(q.normalized, app.normalize_ar(coalesce(s.full_name, ''))),
					word_similarity(q.compact, app.normalize_ar_compact(coalesce(s.full_name, '')))
				) >= case
					when length(q.compact) <= 3 then 0.50
					when length(q.compact) <= 5 then 0.46
					when length(q.compact) <= 7 then 0.42
					else 0.38
				end))
	)
	select id, full_name, student_number, registration_number,
		academic_year, stage_name, grade_name, class_name, similarity_score
	from candidates
	order by similarity_score desc, full_name
	limit greatest(1, least(coalesce(p_limit, 8), 20));
$$;

create or replace function public.mark_notification_read(p_id uuid) returns void language sql security definer set search_path=public,app,pg_temp as $$ update notifications set is_read=true,read_at=now() where id=p_id and coalesce(user_id,recipient_user_id)=auth.uid() $$;
create or replace function public.mark_all_notifications_read() returns integer language plpgsql security definer set search_path=public,app,pg_temp as $$ declare n integer; begin update notifications set is_read=true,read_at=now() where coalesce(user_id,recipient_user_id)=auth.uid() and not is_read; get diagnostics n=row_count; return n; end $$;
create or replace function public.student_completeness(p_student_id uuid) returns table(critical_missing text[],important_missing text[],optional_missing text[],completeness_percentage numeric) language plpgsql stable security definer set search_path=public,app,pg_temp as $$ declare s students%rowtype; c text[]:='{}'; i text[]:='{}'; begin if not app.has_any_perm('students.view','students.create','students.edit','students.archive','students.enrollment.manage') then raise exception 'لا تملك صلاحية عرض اكتمال بيانات الطلاب'; end if; select * into s from students where id=p_student_id and school_id=app.current_school_id(); if not found then raise exception 'الطالب غير موجود في المدرسة الحالية'; end if; if s.full_name is null or btrim(s.full_name)='' then c:=array_append(c,'full_name'); end if; if s.gender is null then c:=array_append(c,'gender'); end if; if s.date_of_birth is null then c:=array_append(c,'date_of_birth'); end if; if s.national_id is null then i:=array_append(i,'national_id'); end if; if coalesce(s.address,s.residence_address) is null then i:=array_append(i,'address'); end if; return query select c,i,'{}'::text[],round(100.0*(6-coalesce(array_length(c,1),0)-coalesce(array_length(i,1),0))/6,2); end $$;
create or replace function public.data_quality_summary(p_entity_type text default 'students')
returns jsonb
language plpgsql
stable
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_result jsonb;
begin
	perform app.require_perm('reports.quality.view');
	if p_entity_type is null or p_entity_type not in ('students','employees','guardians') then
		raise exception 'نوع السجل غير صالح';
	end if;

	if p_entity_type = 'students' then
		with current_enrollment as (
			select distinct on (e.student_id)
				e.student_id,
				y.code as academic_year,
				st.name_ar as stage_name,
				g.name_ar as grade_name,
				c.name_ar as class_name
			from public.student_enrollments e
			join public.students owner_student
				on owner_student.id = e.student_id
				and owner_student.school_id = app.current_school_id()
			left join public.academic_years y
				on y.id = e.academic_year_id
				and y.school_id = owner_student.school_id
			left join public.school_grades g
				on g.id = e.grade_id
				and g.school_id = owner_student.school_id
			left join public.academic_stages st
				on st.id = g.stage_id
				and st.school_id = owner_student.school_id
			left join public.classes c
				on c.id = e.class_id
				and c.school_id = owner_student.school_id
				and c.academic_year_id = e.academic_year_id
				and c.grade_id = e.grade_id
			order by e.student_id,y.is_current desc nulls last,
				e.enrollment_date desc nulls last,e.created_at desc
		), evaluated as (
			select s.id,
				array_remove(array[
					case when nullif(btrim(s.student_number),'') is null then 'رقم الطالب' end,
					case when nullif(btrim(s.full_name),'') is null then 'الاسم الكامل' end,
					case when nullif(btrim(s.gender),'') is null then 'الجنس' end,
					case when s.date_of_birth is null then 'تاريخ الميلاد' end,
					case when nullif(btrim(s.national_id),'') is null then 'الرقم الوطني' end,
					case when s.registration_date is null then 'تاريخ التسجيل' end,
					case when e.academic_year is null then 'السنة الدراسية' end,
					case when e.stage_name is null then 'المرحلة الدراسية' end,
					case when e.grade_name is null then 'الصف' end,
					case when e.class_name is null then 'الفصل' end
				]::text[],null) as missing_critical,
				array_remove(array[
					case when nullif(btrim(s.nationality),'') is null then 'الجنسية' end,
					case when nullif(btrim(coalesce(s.father_phone,s.mother_phone,s.phone,'')),'') is null then 'رقم هاتف ولي الأمر' end,
					case when nullif(btrim(coalesce(s.residence_address,s.address,'')),'') is null then 'العنوان' end
				]::text[],null) as missing_important,
				array_remove(array[
					case when nullif(btrim(s.health_status),'') is null then 'الحالة الصحية' end,
					case when nullif(btrim(s.health_status),'') is null then 'الحالة الصحية' end,
					case when nullif(btrim(s.social_status),'') is null then 'الحالة الاجتماعية' end
				]::text[],null) as missing_optional
			from public.students s
			left join current_enrollment e on e.student_id=s.id
			where s.school_id=app.current_school_id()
				and not coalesce(s.is_archived,false)
		), reports as (
			select e.id,
				case
					when cardinality(e.missing_critical)>0 then 'critical'
					when cardinality(e.missing_important)>0 or cardinality(e.missing_optional)>0 then 'review'
					else 'complete'
				end as quality_status,
				greatest(0,round(100.0*(15-cardinality(e.missing_critical)-cardinality(e.missing_important)-cardinality(e.missing_optional))/15,2)) as completeness_percentage,
				e.missing_critical,e.missing_important,e.missing_optional
			from evaluated e
		)
		select jsonb_build_object(
			'entity_type','students',
			'total_checked',count(*),
			'incomplete_critical_count',count(*) filter (where quality_status='critical'),
			'complete_count',count(*) filter (where quality_status<>'critical'),
			'review_count',count(*) filter (where quality_status='review'),
			'records',coalesce(jsonb_agg(jsonb_build_object(
				'entity_id',id,
				'report',jsonb_build_object(
					'quality_status',quality_status,
					'completeness_percentage',completeness_percentage,
					'missing_critical',missing_critical,
					'missing_important',missing_important,
					'missing_optional',missing_optional
				)
			) order by case quality_status when 'critical' then 1 else 2 end,completeness_percentage)
			filter (where quality_status <> 'complete'),'[]'::jsonb)
		) into v_result
		from reports;
		return v_result;
	end if;

	if p_entity_type = 'employees' then
		with evaluated as (
			select e.id,
				array_remove(array[
					case when nullif(btrim(e.employee_number),'') is null then 'الرقم الوظيفي' end,
					case when nullif(btrim(e.full_name),'') is null then 'الاسم الكامل' end
				]::text[],null) as missing_critical,
				array_remove(array[
					case when nullif(btrim(e.phone),'') is null then 'رقم الهاتف' end,
					case when e.department_id is null then 'القسم' end,
					case when e.job_title_id is null then 'المسمى الوظيفي' end
				]::text[],null) as missing_important
			from public.employees e
			where e.school_id=app.current_school_id()
				and not coalesce(e.is_archived,false)
		), reports as (
			select e.id,e.missing_critical,e.missing_important,
				case when cardinality(e.missing_critical)>0 then 'critical'
					when cardinality(e.missing_important)>0 then 'review' else 'complete' end as quality_status,
				greatest(0,round(100.0*(5-cardinality(e.missing_critical)-cardinality(e.missing_important))/5,2)) as completeness_percentage
			from evaluated e
		)
		select jsonb_build_object(
			'entity_type','employees','total_checked',count(*),
			'incomplete_critical_count',count(*) filter(where quality_status='critical'),
			'complete_count',count(*) filter(where quality_status<>'critical'),
			'review_count',count(*) filter(where quality_status='review'),
			'records',coalesce(jsonb_agg(jsonb_build_object('entity_id',id,'report',jsonb_build_object(
				'quality_status',quality_status,'completeness_percentage',completeness_percentage,
				'missing_critical',missing_critical,'missing_important',missing_important
			)) order by case quality_status when 'critical' then 1 else 2 end,completeness_percentage)
			filter(where quality_status<>'complete'),'[]'::jsonb)
		) into v_result from reports;
		return v_result;
	end if;

	with evaluated as (
		select g.id,
			array_remove(array[
				case when nullif(btrim(g.full_name),'') is null then 'الاسم الكامل' end
			]::text[],null) as missing_critical,
			array_remove(array[
				case when nullif(btrim(coalesce(g.phone,g.phone_alt,g.phone_secondary,'')),'') is null
					and nullif(btrim(coalesce(g.email,'')),'') is null
					and nullif(btrim(coalesce(g.national_id,'')),'') is null then 'بيانات التواصل' end
			]::text[],null) as missing_important
		from public.guardians g
		where g.school_id=app.current_school_id()
	), reports as (
		select e.id,e.missing_critical,e.missing_important,
			case when cardinality(e.missing_critical)>0 then 'critical'
				when cardinality(e.missing_important)>0 then 'review' else 'complete' end as quality_status,
			greatest(0,round(100.0*(2-cardinality(e.missing_critical)-cardinality(e.missing_important))/2,2)) as completeness_percentage
		from evaluated e
	)
	select jsonb_build_object(
		'entity_type','guardians','total_checked',count(*),
		'incomplete_critical_count',count(*) filter(where quality_status='critical'),
		'complete_count',count(*) filter(where quality_status<>'critical'),
		'review_count',count(*) filter(where quality_status='review'),
		'records',coalesce(jsonb_agg(jsonb_build_object('entity_id',id,'report',jsonb_build_object(
			'quality_status',quality_status,'completeness_percentage',completeness_percentage,
			'missing_critical',missing_critical,'missing_important',missing_important
		)) order by case quality_status when 'critical' then 1 else 2 end,completeness_percentage)
		filter(where quality_status<>'complete'),'[]'::jsonb)
	) into v_result from reports;
	return v_result;
end;
$$;
create or replace function public.completeness_report(p_entity_type text,p_entity_id uuid) returns jsonb language plpgsql stable security definer set search_path=public,app,pg_temp as $$ declare v_result jsonb; begin if p_entity_type <> 'students' then raise exception 'نوع السجل غير مدعوم'; end if; select to_jsonb(x) into v_result from public.student_completeness(p_entity_id) x; return v_result; end $$;
create or replace function public.reverse_payment(p_payment_id uuid,p_reason text,p_idempotency_key text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare p payments%rowtype; begin perform app.require_perm('finance.payments.reverse'); select * into p from payments where id=p_payment_id and school_id=app.current_school_id() for update; if not found or p.status<>'completed' then raise exception 'الدفعة غير قابلة للعكس'; end if; update payments set status='reversed',notes=concat_ws(' | ',notes,'سبب العكس: '||coalesce(nullif(btrim(p_reason),''),'غير محدد')) where id=p.id; update installments i set paid_amount=greatest(0,i.paid_amount-p.amount),status=case when greatest(0,i.paid_amount-p.amount)<=0 then 'pending'::app.installment_status when greatest(0,i.paid_amount-p.amount)>=i.net_due then 'paid'::app.installment_status else 'partial'::app.installment_status end where i.id=p.installment_id; insert into audit_logs(user_id,actor_id,action,entity_type,entity_id,old_value,new_value,description) values(auth.uid(),auth.uid(),'payment.reversed','payment',p.id::text,to_jsonb(p),jsonb_build_object('reason',p_reason),'تم عكس الدفعة'); return jsonb_build_object('payment_id',p.id,'reversed',true); end $$;
create or replace function public.student_financial_summary(p_student_id uuid,p_academic_year_id uuid default null) returns jsonb language sql stable security definer set search_path=public,app,pg_temp as $$ with totals as (select se.academic_year_id,coalesce(sum(i.net_due),0) total_due,coalesce(sum(i.paid_amount),0) total_paid,coalesce(sum(i.remaining_amount),0) remaining from installments i join student_fees sf on sf.id=i.student_fee_id join student_enrollments se on se.id=sf.enrollment_id join students s on s.id=se.student_id where se.student_id=p_student_id and s.school_id=app.current_school_id() and app.has_any_perm('finance.payments.view','finance.payments.create','finance.fees.view','finance.fees.manage') and (p_academic_year_id is null or se.academic_year_id=p_academic_year_id) group by se.academic_year_id), current_row as (select t.*,y.code,y.name_ar,y.is_current from totals t join academic_years y on y.id=t.academic_year_id), previous as (select coalesce(jsonb_agg(jsonb_build_object('academic_year',coalesce(code,name_ar),'total_due',total_due,'total_paid',total_paid,'remaining',remaining) order by code desc),'[]'::jsonb) rows from current_row where is_current is distinct from true) select jsonb_build_object('current_year',coalesce((select jsonb_build_object('academic_year',coalesce(code,name_ar),'total_due',total_due,'total_paid',total_paid,'remaining',remaining) from current_row where is_current is true limit 1),'{}'::jsonb),'previous_years',(select rows from previous),'total_due',coalesce((select sum(total_due) from totals),0),'paid',coalesce((select sum(total_paid) from totals),0),'remaining',coalesce((select sum(remaining) from totals),0)) $$;
create or replace function public.refresh_overdue_installments() returns integer language plpgsql security definer set search_path=public,app,pg_temp as $$ declare n integer; begin perform app.require_perm('finance.payments.view'); update installments set status='overdue' where due_date<current_date and paid_amount<net_due and status in ('pending','partial'); get diagnostics n=row_count; return n; end $$;
create or replace function public.check_timetable_conflict(p_academic_year_id uuid,p_day_number smallint,p_period_id uuid,p_class_id uuid,p_employee_id uuid default null,p_room text default null,p_exclude_entry_id uuid default null) returns jsonb language sql stable security definer set search_path=public,app,pg_temp as $$
with candidate as (
  select p.start_time, p.end_time from public.timetable_periods p where p.id = p_period_id
), overlaps as (
  select t.id
  from public.timetable_entries t
  join public.timetable_periods tp on tp.id = t.period_id
  join candidate c on true
  where t.is_active
    and t.id is distinct from p_exclude_entry_id
    and t.academic_year_id = p_academic_year_id
    and t.day_number = p_day_number
    and (
      t.class_id = p_class_id
      or (p_employee_id is not null and t.employee_id = p_employee_id)
      or (nullif(btrim(coalesce(p_room, '')), '') is not null and nullif(btrim(coalesce(t.room, '')), '') is not null and lower(btrim(t.room)) = lower(btrim(p_room)))
    )
    and not (tp.end_time <= c.start_time or c.end_time <= tp.start_time)
)
select jsonb_build_object('has_conflict', exists(select 1 from overlaps));
$$;
create or replace function public.suggest_timetable_slots(p_academic_year_id uuid,p_class_id uuid,p_employee_id uuid default null,p_room text default null,p_limit integer default 8) returns table(day_number smallint,day_name text,period_id uuid,period_name text) language sql stable security definer set search_path=public,app,pg_temp as $$ select d.day_number,d.name_ar,p.id,coalesce(p.name_ar,'الفترة '||p.period_number) from week_days d cross join timetable_periods p where d.is_school_day and p.academic_year_id=p_academic_year_id and p.is_active and not exists(select 1 from timetable_entries t where t.is_active and t.day_number=d.day_number and t.period_id=p.id and(t.class_id=p_class_id or(p_employee_id is not null and t.employee_id=p_employee_id) or(p_room is not null and t.room=p_room))) order by d.sort_order,p.period_number limit p_limit $$;
create or replace function public.add_timetable_entry(p_academic_year_id uuid,p_day_number smallint,p_period_id uuid,p_class_id uuid,p_class_subject_id uuid,p_employee_id uuid default null,p_room text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare c jsonb; x uuid; begin perform app.require_perm('timetable.manage'); c:=public.check_timetable_conflict(p_academic_year_id,p_day_number,p_period_id,p_class_id,p_employee_id,p_room); insert into timetable_entries(academic_year_id,day_number,period_id,class_id,class_subject_id,employee_id,room,created_by) values(p_academic_year_id,p_day_number,p_period_id,p_class_id,p_class_subject_id,p_employee_id,p_room,auth.uid()) returning id into x; return c || jsonb_build_object('id',x,'saved',true,'warning', case when (c->>'has_conflict')::boolean then 'تم حفظ الحصة مع تحذير تعارض في الجدول. راجع الإسناد قبل الاعتماد.' else null end); end $$;
create or replace function public.clone_year_structure(
	p_source_year uuid,
	p_target_year uuid,
	p_copy_teachers boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	source_class record;
	source_grade_subject record;
	target_class_id uuid;
	rows_inserted integer;
	classes_created integer := 0;
	grade_subjects_created integer := 0;
	class_subjects_created integer := 0;
begin
	perform app.require_perm('academic_years.manage');
	if p_source_year = p_target_year then
		raise exception 'لا يمكن نسخ السنة إلى نفسها';
	end if;

	for source_grade_subject in
		select * from public.grade_subjects where academic_year_id = p_source_year
	loop
		insert into public.grade_subjects (
			academic_year_id, grade_id, subject_id, max_score,
			pass_percentage, coursework_weight, final_exam_weight,
			final_exam_min_pct, weekly_periods, assessment_type, exam_included,
			is_active
		)
		values (
			p_target_year, source_grade_subject.grade_id, source_grade_subject.subject_id,
			source_grade_subject.max_score, source_grade_subject.pass_percentage,
			source_grade_subject.coursework_weight, source_grade_subject.final_exam_weight,
			source_grade_subject.final_exam_min_pct, source_grade_subject.weekly_periods,
			source_grade_subject.assessment_type, source_grade_subject.exam_included,
			source_grade_subject.is_active
		)
		on conflict (academic_year_id, grade_id, subject_id) do nothing;
		get diagnostics rows_inserted = row_count;
		grade_subjects_created := grade_subjects_created + rows_inserted;
	end loop;

	for source_class in
		select * from public.classes where academic_year_id = p_source_year
	loop
		select c.id into target_class_id
		from public.classes c
		where c.academic_year_id = p_target_year
			and c.grade_id = source_class.grade_id
			and c.section_code is not distinct from source_class.section_code
		limit 1;

		if target_class_id is null then
			insert into public.classes (
				school_id, academic_year_id, grade_id, section_code,
				section_name, name_ar, room_name, room, capacity, is_active
			)
			values (
				source_class.school_id, p_target_year, source_class.grade_id,
				source_class.section_code, source_class.section_name,
				source_class.name_ar, source_class.room_name, source_class.room,
				source_class.capacity, source_class.is_active
			)
			on conflict (academic_year_id, grade_id, section_code) do nothing
			returning id into target_class_id;
			if target_class_id is not null then classes_created := classes_created + 1; end if;
		end if;

		if target_class_id is not null then
			insert into public.class_subjects (
				class_id, academic_year_id, grade_id, subject_id,
				grade_subject_id, employee_id, weekly_periods, is_active
			)
			select
				target_class_id, p_target_year, cs.grade_id, cs.subject_id,
				gs_target.id,
				case when p_copy_teachers then cs.employee_id else null end,
				cs.weekly_periods, cs.is_active
			from public.class_subjects cs
			left join public.grade_subjects gs_target
				on gs_target.academic_year_id = p_target_year
			 and gs_target.grade_id = cs.grade_id
			 and gs_target.subject_id = cs.subject_id
			where cs.class_id = source_class.id
				and not exists (
					select 1 from public.class_subjects existing
					where existing.class_id = target_class_id
						and existing.subject_id is not distinct from cs.subject_id
						and existing.grade_subject_id is not distinct from gs_target.id
				);
			get diagnostics rows_inserted = row_count;
			class_subjects_created := class_subjects_created + rows_inserted;
		end if;
	end loop;

	return jsonb_build_object(
		'classes_created', classes_created,
		'grade_subjects_created', grade_subjects_created,
		'class_subjects_created', class_subjects_created
	);
end $$;
create or replace function public.close_academic_year(
	p_year_id uuid,
	p_confirm boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_year public.academic_years%rowtype;
	v_actor_label text;
begin
	perform app.require_perm('academic_years.close');
	if auth.uid() is null or v_school_id is null or p_year_id is null then
		raise exception 'تعذر تحديد السنة أو المدرسة الحالية.' using errcode = '42501';
	end if;
	select * into v_year
	from public.academic_years
	where id = p_year_id and school_id = v_school_id
	for update;
	if not found then
		raise exception 'السنة الدراسية غير موجودة في المدرسة الحالية أو لا تملك صلاحية الوصول إليها.' using errcode = 'P0001';
	end if;
	if not p_confirm then
		return jsonb_build_object(
			'requires_confirmation', true,
			'warning', 'سيتم إغلاق السنة الدراسية الحالية للمدرسة فقط وحماية سجلاتها التاريخية.'
		);
	end if;
	if v_year.status in ('closed', 'archived', 'مغلقة', 'مؤرشفة') then
		return jsonb_build_object('closed', true, 'already_closed', true);
	end if;
	if v_year.status not in ('draft', 'active', 'مسودة', 'نشطة') then
		raise exception 'لا يمكن إغلاق السنة بالحالة الحالية.' using errcode = 'P0001';
	end if;
	insert into app.academic_year_closure_authorizations(
		transaction_id, academic_year_id, actor_id
	) values (txid_current(), p_year_id, auth.uid());
	update public.academic_years
	set status = 'closed', is_current = false,
			closed_at = coalesce(closed_at, now()), version = version + 1
	where id = p_year_id and school_id = v_school_id;
	if not found then
		raise exception 'تعذر إغلاق السنة الدراسية.' using errcode = 'P0001';
	end if;
	select coalesce(nullif(btrim(full_name), ''), username)
	into v_actor_label from public.profiles where id = auth.uid();
	insert into public.audit_logs(
		actor_id, actor_label, action, entity_type, entity_id, academic_year_id,
		old_value, new_value, description, metadata
	) values (
		auth.uid(), v_actor_label, 'academic_year.closed', 'academic_year',
		p_year_id::text, p_year_id,
		jsonb_build_object('status', v_year.status, 'is_current', v_year.is_current),
		jsonb_build_object('status', 'closed', 'is_current', false),
		'تم إغلاق السنة الدراسية', jsonb_build_object('school_id', v_school_id)
	);
	return jsonb_build_object('closed', true, 'year_id', p_year_id);
end;
$$;
create or replace function public.graduate_student(p_student_id uuid,p_academic_year_id uuid,p_graduation_date date default current_date,p_notes text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare v_school_id uuid:=app.current_school_id(); v_student public.students%rowtype; v_updated integer; begin perform app.require_perm('students.archive'); select s.* into v_student from public.students s join public.academic_years y on y.id=p_academic_year_id and y.school_id=s.school_id where s.id=p_student_id and s.school_id=v_school_id for update of s; if not found then raise exception 'الطالب أو السنة الدراسية غير موجودين في المدرسة الحالية'; end if; update public.student_enrollments set outcome='graduated' where student_id=p_student_id and academic_year_id=p_academic_year_id; get diagnostics v_updated=row_count; if v_updated=0 then raise exception 'لا يوجد تسجيل للطالب في السنة المحددة'; end if; update public.students set educational_status='graduated',graduation_date=coalesce(p_graduation_date,current_date) where id=p_student_id and school_id=v_school_id; if nullif(btrim(coalesce(p_notes,'')),'') is not null then insert into public.student_notes(student_id,note_type,note_text,created_by) values(p_student_id,'academic',btrim(p_notes),auth.uid()); end if; return jsonb_build_object('graduated',true,'graduation_date',coalesce(p_graduation_date,current_date)); end $$;
create or replace function public.change_student_file_status(p_student_id uuid,p_action text,p_reason text,p_academic_year_id uuid default null,p_delivered_to_name text default null,p_delivered_to_relationship text default null,p_delivered_to_id_number text default null,p_delivered_to_guardian_id uuid default null,p_transaction_date date default current_date,p_notes text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare v_school_id uuid:=app.current_school_id(); old text; newv text; begin perform app.require_perm('students.file.withdraw'); if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'سبب تغيير حالة الملف مطلوب'; end if; select file_status into old from public.students where id=p_student_id and school_id=v_school_id for update; if not found then raise exception 'الطالب غير موجود في المدرسة الحالية'; end if; if p_academic_year_id is not null and not exists(select 1 from public.academic_years where id=p_academic_year_id and school_id=v_school_id) then raise exception 'السنة الدراسية لا تنتمي إلى المدرسة الحالية'; end if; if p_delivered_to_guardian_id is not null and not exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=p_student_id and sg.guardian_id=p_delivered_to_guardian_id and g.school_id=v_school_id) then raise exception 'ولي الأمر غير مرتبط بالطالب في المدرسة الحالية'; end if; newv=case p_action when 'mark_ready' then 'ready' when 'deliver' then 'delivered' when 'withdraw' then 'withdrawn' when 'return' then 'at_school' else null end; if newv is null then raise exception 'إجراء حالة الملف غير صالح'; end if; update public.students set file_status=newv where id=p_student_id and school_id=v_school_id; insert into public.student_file_transactions(student_id,academic_year_id,action,previous_status,new_status,reason,delivered_to_name,delivered_to_relationship,delivered_to_id_number,delivered_to_guardian_id,handled_by,transaction_date,notes) values(p_student_id,p_academic_year_id,p_action,old,newv,btrim(p_reason),p_delivered_to_name,p_delivered_to_relationship,p_delivered_to_id_number,p_delivered_to_guardian_id,auth.uid(),coalesce(p_transaction_date,current_date),p_notes); return jsonb_build_object('new_status',newv); end $$;
create or replace function public.create_document_version(p_document_id uuid,p_content_html text default null,p_storage_path text default null,p_file_hash text default null,p_file_size_bytes bigint default null,p_mime_type text default null,p_data_snapshot jsonb default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare n integer; v uuid; begin perform app.require_perm('documents.upload'); select coalesce(max(version_number),0)+1 into n from document_versions where document_id=p_document_id; insert into document_versions(document_id,version_number,content_html,storage_path,file_hash,file_size_bytes,mime_type,data_snapshot,created_by) values(p_document_id,n,p_content_html,p_storage_path,p_file_hash,p_file_size_bytes,p_mime_type,p_data_snapshot,auth.uid()) returning id into v; update documents set current_version_id=v,status='pending_approval' where id=p_document_id; return jsonb_build_object('id',v,'version_number',n); end $$;
create or replace function public.decide_document(p_document_id uuid,p_decision text,p_note text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ begin perform app.require_perm('documents.approve'); update documents set status=case when p_decision='approved' then 'approved'::app.document_status when p_decision='rejected' then 'rejected'::app.document_status else status end where id=p_document_id; return jsonb_build_object('document_id',p_document_id,'decision',p_decision); end $$;
drop function if exists public.record_backup_created(text,bigint,text);
create function public.record_backup_created(
	p_checksum_sha256 text,
	p_size_bytes bigint,
	p_label text default null
) returns uuid
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	x uuid;
	v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
	perform app.require_perm('backup.manage');
	if p_checksum_sha256 is null or lower(p_checksum_sha256) !~ '^[0-9a-f]{64}$' then
		raise exception 'بصمة ملف النسخة الاحتياطية غير صالحة.' using errcode = '22023';
	end if;
	if p_size_bytes is null or p_size_bytes <= 0 then
		raise exception 'حجم ملف النسخة الاحتياطية غير صالح.' using errcode = '22023';
	end if;
	if app.current_school_id() is null then
		raise exception 'تعذر تحديد المدرسة الحالية.' using errcode = 'P0001';
	end if;

	insert into public.backup_records(
		school_id, checksum_sha256, size_bytes, file_size_bytes, label,
		label_ar, status, backup_type, schema_version, app_version, created_by
	) values (
		app.current_school_id(), lower(p_checksum_sha256), p_size_bytes, p_size_bytes,
		v_label, coalesce(v_label, 'نسخة احتياطية كاملة'), 'created', 'full',
		'1.0', 'school-management', auth.uid()
	) returning id into x;
	return x;
end $$;

create or replace function public.record_backup_restored(p_backup_id uuid)
returns void
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
begin
	perform app.require_perm('backup.manage');
	update public.backup_records
	set restored_at = coalesce(restored_at, now()), status = 'restored'
	where id = p_backup_id and school_id = app.current_school_id();
	if not found then
		raise exception 'النسخة الاحتياطية غير موجودة أو غير مصرح بها.' using errcode = 'P0001';
	end if;
end $$;
create or replace function public.mark_archive_saved(p_archive_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_archive public.archive_records%rowtype;
begin
	perform app.require_perm('archive.manage');
	select * into v_archive
	from public.archive_records
	where id = p_archive_id and school_id = app.current_school_id()
	for update;
	if not found then
		raise exception 'الأرشيف غير موجود أو غير مصرح به.' using errcode = 'P0001';
	end if;
	if v_archive.state not in ('generated', 'saved') then
		raise exception 'لا يمكن تأكيد حفظ أرشيف بهذه الحالة.' using errcode = 'P0001';
	end if;
	if v_archive.checksum_sha256 is null or v_archive.total_size_bytes is null
		or v_archive.total_size_bytes <= 0 then
		raise exception 'لا توجد بصمة وحجم صالحان للملف؛ أنشئ ملف الأرشيف من جديد.' using errcode = 'P0001';
	end if;

	update public.archive_records
	set state = 'saved',
		saved_at = coalesce(saved_at, now()),
		storage_location = coalesce(storage_location, 'external_media')
	where id = p_archive_id;
	return jsonb_build_object('saved', true, 'archive_id', p_archive_id, 'state', 'saved');
end $$;

create or replace function public.verify_archive(p_archive_id uuid, p_uploaded_hash text)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_archive public.archive_records%rowtype;
	v_purge_days integer;
	v_can_purge boolean;
	v_uploaded_hash text := lower(btrim(coalesce(p_uploaded_hash, '')));
begin
	perform app.require_perm('archive.manage');
	if v_uploaded_hash !~ '^[0-9a-f]{64}$' then
		raise exception 'بصمة الملف المرفوع غير صالحة.' using errcode = '22023';
	end if;
	select * into v_archive
	from public.archive_records
	where id = p_archive_id and school_id = app.current_school_id();
	if not found then
		raise exception 'الأرشيف غير موجود أو غير مصرح به.' using errcode = 'P0001';
	end if;
	if v_archive.state = 'verified' then
		return jsonb_build_object(
			'verified', v_archive.checksum_sha256 = v_uploaded_hash,
			'message', case when v_archive.checksum_sha256 = v_uploaded_hash
				then 'تم التحقق من هذا الأرشيف مسبقًا.'
				else 'لا تطابق بصمة الملف الأرشيف المسجل.' end,
			'archive_id', p_archive_id
		);
	end if;
	if v_archive.state <> 'saved' then
		raise exception 'يجب تأكيد حفظ الملف خارجيًا قبل التحقق منه.' using errcode = 'P0001';
	end if;
	if v_archive.checksum_sha256 is null then
		raise exception 'لا توجد بصمة ملف مسجلة لهذا الأرشيف.' using errcode = 'P0001';
	end if;
	if v_archive.checksum_sha256 <> v_uploaded_hash then
		return jsonb_build_object(
			'verified', false,
			'message', 'لا تطابق بصمة الملف الأرشيف المسجل. لم تتغير حالة الأرشيف.'
		);
	end if;

	select coalesce(max(retention_days), 30)
	into v_purge_days
	from public.retention_policies
	where school_id = v_archive.school_id and category = 'audit_logs';
	v_can_purge := v_archive.scope = 'academic_year'
		and v_archive.academic_year_id is not null;
	update public.archive_records
	set state = 'verified',
		verified_at = now(),
		verified_by = auth.uid(),
		purge_eligible_at = case when v_can_purge
			then now() + make_interval(days => v_purge_days) else null end
	where id = p_archive_id;
	return jsonb_build_object(
		'verified', true,
		'message', 'تم التحقق من سلامة الملف المسجل.',
		'archive_id', p_archive_id,
		'purge_eligible_at', case when v_can_purge
			then (now() + make_interval(days => v_purge_days)) else null end
	);
end $$;

create or replace function public.validate_restore(p_archive_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_archive public.archive_records%rowtype;
	v_items jsonb;
	v_schema_version text;
	v_total_records bigint := 0;
	v_mismatches jsonb := '[]'::jsonb;
	v_item jsonb;
	v_table text;
	v_count integer;
	v_checksum text;
	v_file text;
	v_expected_count bigint;
begin
	perform app.require_perm('archive.manage');
	select * into v_archive
	from public.archive_records
	where id = p_archive_id and school_id = app.current_school_id();
	if not found then
		raise exception 'الأرشيف غير موجود أو غير مصرح به.' using errcode = 'P0001';
	end if;
	if jsonb_typeof(p_items) = 'object' then
		v_items := p_items->'included_tables';
		v_schema_version := p_items->>'schema_version';
		if coalesce(p_items->>'total_records', '') !~ '^[0-9]+$' then
			return jsonb_build_object('valid', false,
				'mismatches', jsonb_build_array('إجمالي السجلات غير صالح.'));
		end if;
		v_expected_count := (p_items->>'total_records')::bigint;
	elsif jsonb_typeof(p_items) = 'array' then
		v_items := p_items;
		v_schema_version := '1.0';
		v_expected_count := null;
	else
		return jsonb_build_object('valid', false,
			'mismatches', jsonb_build_array('ملخص الملف غير صالح.'));
	end if;
	if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
		return jsonb_build_object('valid', false,
			'mismatches', jsonb_build_array('لا توجد مجموعات بيانات في الملف.'));
	end if;
	if v_schema_version is distinct from v_archive.schema_version then
		v_mismatches := v_mismatches || jsonb_build_array('إصدار بنية الملف لا يطابق السجل.');
	end if;
	if jsonb_array_length(v_items) <> (
		select count(*) from public.archive_items
		where coalesce(archive_id, archive_record_id) = p_archive_id
	) then
		v_mismatches := v_mismatches || jsonb_build_array('عدد مجموعات الملف لا يطابق السجل.');
	end if;

	for v_item in select value from jsonb_array_elements(v_items)
	loop
		v_table := coalesce(v_item->>'table', v_item->>'entity_type', '');
		v_file := coalesce(v_item->>'file', '');
		if v_table = '' or v_file = ''
			or v_file ~ '(^/|(^|/)\.\.(/|$))'
			or coalesce(v_item->>'count', '') !~ '^[0-9]+$'
			or lower(coalesce(v_item->>'checksum_sha256', '')) !~ '^[0-9a-f]{64}$' then
			v_mismatches := v_mismatches || jsonb_build_array('بيانات إحدى مجموعات الملف غير صالحة.');
			continue;
		end if;
		v_count := (v_item->>'count')::integer;
		v_checksum := lower(v_item->>'checksum_sha256');
		v_total_records := v_total_records + v_count;
		if not exists (
			select 1 from public.archive_items ai
			where coalesce(ai.archive_id, ai.archive_record_id) = p_archive_id
				and ai.category = v_table
				and ai.record_count = v_count
				and lower(ai.checksum_sha256) = v_checksum
		) then
			v_mismatches := v_mismatches || jsonb_build_array(
				jsonb_build_object('table', v_table, 'message', 'بيانات المجموعة لا تطابق السجل.')
			);
		end if;
	end loop;
	if v_total_records <> v_archive.item_count
		or (v_expected_count is not null and v_expected_count <> v_total_records) then
		v_mismatches := v_mismatches || jsonb_build_array('إجمالي السجلات لا يطابق السجل.');
	end if;
	return jsonb_build_object(
		'valid', jsonb_array_length(v_mismatches) = 0,
		'mismatches', v_mismatches,
		'total_records', v_total_records
	);
end $$;

create or replace function public.list_social_cases(p_status app.social_case_status default null,p_query text default null) returns table(id uuid,student_id uuid,student_name text,category text,priority app.social_case_priority,status app.social_case_status,summary text,opened_date date,assigned_to uuid,version integer) language sql security definer set search_path=public,app,pg_temp as $$ select c.id,c.student_id,s.full_name,coalesce(c.category,c.case_type),c.priority,c.status,c.summary,c.opened_date,c.assigned_to,c.version from social_cases c join students s on s.id=c.student_id where s.school_id = app.current_school_id() and app.has_any_perm('social.view','social.manage') and (p_status is null or c.status=p_status) and (p_query is null or btrim(p_query) = '' or s.full_name ilike '%'||p_query||'%') order by c.opened_date desc, c.created_at desc $$;
create or replace function public.get_social_case(p_case_id uuid) returns jsonb language sql security definer set search_path=public,app,pg_temp as $$ select jsonb_build_object('case',to_jsonb(c),'student',to_jsonb(s),'notes',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.social_case_notes n where n.case_id = c.id or n.social_case_id = c.id),'[]'::jsonb)) from social_cases c join students s on s.id=c.student_id where c.id=p_case_id and s.school_id = app.current_school_id() and app.has_any_perm('social.view','social.manage') $$;
create or replace function public.create_social_case(p_student_id uuid,p_academic_year_id uuid,p_category_id uuid default null,p_priority app.social_case_priority default 'medium',p_summary text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare v_case_id uuid; begin perform app.require_perm('social.manage'); if p_student_id is null then raise exception 'يجب اختيار الطالب.' using errcode='P0001'; end if; if not exists (select 1 from public.students s where s.id = p_student_id and s.school_id = app.current_school_id()) then raise exception 'لا يملك الطالب نفس مدرسة المستخدم الحالي.' using errcode='P0001'; end if; insert into public.social_cases(school_id,student_id,academic_year_id,category_id,priority,summary,status,opened_date,opened_by,created_at,version) values(app.current_school_id(),p_student_id,p_academic_year_id,p_category_id,p_priority,nullif(btrim(p_summary),''),'open',current_date,auth.uid(),now(),1) returning id into v_case_id; return jsonb_build_object('id',v_case_id,'created',true); end $$;
create or replace function public.add_social_case_note(p_case_id uuid,p_note_type text default 'note',p_note text default null,p_action text default null,p_follow_up_date date default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare v_note_id uuid; begin perform app.require_perm('social.manage'); if p_case_id is null then raise exception 'معرّف الحالة مطلوب.' using errcode='P0001'; end if; if nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'نص الملاحظة مطلوب.' using errcode='P0001'; end if; insert into public.social_case_notes(case_id,social_case_id,note,action_taken,follow_up_date,created_by) values(p_case_id,p_case_id,p_note,nullif(btrim(p_action),''),p_follow_up_date,auth.uid()) returning id into v_note_id; return jsonb_build_object('id',v_note_id,'created',true); end $$;
create or replace function public.update_social_case_status(p_case_id uuid,p_new_status app.social_case_status,p_closure_summary text default null,p_expected_version integer default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare v_version integer; begin perform app.require_perm('social.manage'); select version into v_version from public.social_cases where id = p_case_id and school_id = app.current_school_id(); if v_version is null then raise exception 'الحالة غير موجودة أو غير مصرح بها.' using errcode='P0001'; end if; if p_expected_version is not null and v_version <> p_expected_version then raise exception 'تم تعديل الحالة من مستخدم آخر. حدّث القائمة ثم أعد المحاولة.' using errcode='P0001'; end if; update public.social_cases set status = p_new_status, closed_date = case when p_new_status = 'closed' then current_date else null end, closure_summary = case when p_new_status = 'closed' then nullif(btrim(p_closure_summary), '') else null end, version = version + 1, updated_at = now() where id = p_case_id; return jsonb_build_object('updated',true,'status',p_new_status); end $$;
create or replace function public.save_employee_attendance(p_date date,p_records jsonb,p_idempotency_key text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare x jsonb; n integer:=0; v_year_id uuid; begin perform app.require_perm('attendance.employees.manage'); if p_date is null then raise exception 'تاريخ الحضور مطلوب'; end if; v_year_id := (select id from public.academic_years where school_id = app.current_school_id() and status in ('draft','active') order by start_date desc limit 1); if v_year_id is null then raise exception 'لا توجد سنة دراسية نشطة للمدرسة الحالية.'; end if; if not public.is_school_day_for_year(v_year_id, p_date) then raise exception 'لا يمكن تسجيل حضور الموظفين في يوم غير دراسي أو عطلة. يرجى اختيار يوم مدرسي.'; end if; for x in select * from jsonb_array_elements(coalesce(p_records,'[]')) loop insert into employee_attendance(employee_id,attendance_date,status,status_code,notes,recorded_by) values((x->>'employee_id')::uuid,p_date,coalesce(x->>'status',x->>'status_code'),coalesce(x->>'status',x->>'status_code'),x->>'notes',auth.uid()) on conflict(employee_id,attendance_date) do update set status=excluded.status,status_code=excluded.status_code,notes=excluded.notes; n:=n+1; end loop; return jsonb_build_object('saved',n,'total',n); end $$;
create or replace function public.generate_payroll(p_period_id uuid,p_idempotency_key text default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare n integer; begin perform app.require_perm('payroll.manage'); if not exists(select 1 from payroll_periods where id=p_period_id and school_id=app.current_school_id() and status='draft') then raise exception 'فترة الرواتب غير صالحة أو ليست مسودة'; end if; insert into payroll_entries(payroll_period_id,employee_id) select p_period_id,id from employees where school_id=app.current_school_id() and not is_archived on conflict(payroll_period_id,employee_id) do nothing; get diagnostics n=row_count; update payroll_periods set status='calculated' where id=p_period_id; return jsonb_build_object('entries',n); end $$;
create or replace function public.approve_payroll(p_period_id uuid) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ begin perform app.require_perm('payroll.approve'); if not exists(select 1 from payroll_periods where id=p_period_id and school_id=app.current_school_id() and status='calculated') then raise exception 'فترة الرواتب غير صالحة للاعتماد'; end if; update payroll_periods set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_period_id; return jsonb_build_object('approved',true); end $$;
create or replace function public.student_grade_age_compatibility(p_student_id uuid,p_grade_id uuid) returns text
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_student students%rowtype;
	v_grade school_grades%rowtype;
	v_age integer;
	v_min_age integer;
	v_max_age integer;
begin
	if p_student_id is null or p_grade_id is null then
		return null;
	end if;

	select * into v_student from public.students where id = p_student_id and school_id = app.current_school_id();
	if not found or v_student.date_of_birth is null then
		return null;
	end if;

	select * into v_grade from public.school_grades where id = p_grade_id and school_id = v_student.school_id;
	if not found then
		return null;
	end if;

	v_age := extract(year from age(current_date, v_student.date_of_birth))::int;

	if upper(coalesce(v_grade.code, '')) like 'KG%' or lower(coalesce(v_grade.name_ar, '')) like '%روضة%' then
		v_min_age := 3; v_max_age := 5;
	elsif upper(coalesce(v_grade.code, '')) like 'PREP%' or lower(coalesce(v_grade.name_ar, '')) like '%تمهيدي%' then
		v_min_age := 4; v_max_age := 6;
	elsif v_grade.level_number is not null then
		v_min_age := greatest(3, v_grade.level_number + 5);
		v_max_age := v_grade.level_number + 6;
	else
		return null;
	end if;

	if v_age < v_min_age or v_age > v_max_age then
		return format('عمر الطالب %s سنة لا يتوافق مع الصف %s. العمر المناسب لهذا الصف هو %s-%s سنة.',
			v_age,
			coalesce(v_grade.name_ar, v_grade.code),
			v_min_age,
			v_max_age);
	end if;

	return null;
end $$;

revoke all on function public.student_grade_age_compatibility(uuid,uuid) from public, anon;
grant execute on function public.student_grade_age_compatibility(uuid,uuid) to authenticated;

create or replace function public.update_student_app_login_status(
	p_student_id uuid,
	p_status text default 'reset_required',
	p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_status text := lower(coalesce(nullif(btrim(p_status), ''), 'reset_required'));
	v_enabled boolean;
begin
	if not app.has_any_perm('students.manage','students.edit') then
		raise exception 'لا تملك صلاحية إدارة دخول الطلاب إلى التطبيق';
	end if;
	if p_student_id is null then
		raise exception 'معرّف الطالب مطلوب';
	end if;
	if not exists (select 1 from public.students where id = p_student_id and school_id = v_school_id) then
		raise exception 'الطالب غير موجود في المدرسة الحالية';
	end if;
	if v_status not in ('not_created','active','reset_required','disabled') then
		raise exception 'حالة دخول التطبيق غير صالحة';
	end if;

	v_enabled := v_status in ('active', 'reset_required');
	update public.students
	set student_app_login_status = v_status,
		student_app_login_enabled = v_enabled,
		updated_at = now()
	where id = p_student_id and school_id = v_school_id;

	insert into public.audit_logs (
		user_id, actor_id, action, entity_type, entity_id, description, metadata
	) values (
		auth.uid(), auth.uid(), 'student_app_login.updated', 'students', p_student_id::text,
		case v_status
			when 'active' then 'تم تفعيل دخول الطالب إلى التطبيق.'
			when 'reset_required' then 'تم تحديد أن الطالب يحتاج إعادة تعيين كلمة المرور.'
			when 'disabled' then 'تم تعطيل دخول الطالب إلى التطبيق.'
			else 'تم تحديث حالة دخول الطالب إلى التطبيق.'
		end,
		jsonb_build_object('status', v_status, 'enabled', v_enabled, 'reason', nullif(btrim(coalesce(p_reason, '')), ''))
	);

	return jsonb_build_object(
		'student_id', p_student_id,
		'status', v_status,
		'enabled', v_enabled,
		'reason', nullif(btrim(coalesce(p_reason, '')), '')
	);
end $$;

revoke all on function public.update_student_app_login_status(uuid,text,text) from public, anon;
grant execute on function public.update_student_app_login_status(uuid,text,text) to authenticated;

create or replace function public.update_guardian_app_login_status(
	p_guardian_id uuid,
	p_status text default 'reset_required',
	p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_status text := lower(coalesce(nullif(btrim(p_status), ''), 'reset_required'));
	v_enabled boolean;
begin
	if not app.has_any_perm('guardians.manage','students.edit') then
		raise exception 'لا تملك صلاحية إدارة دخول أولياء الأمور إلى التطبيق';
	end if;
	if p_guardian_id is null then
		raise exception 'معرّف ولي الأمر مطلوب';
	end if;
	if not exists (select 1 from public.guardians where id = p_guardian_id and school_id = v_school_id) then
		raise exception 'ولي الأمر غير موجود في المدرسة الحالية';
	end if;
	if v_status not in ('not_created','active','reset_required','disabled') then
		raise exception 'حالة دخول ولي الأمر غير صالحة';
	end if;

	v_enabled := v_status in ('active', 'reset_required');
	update public.guardians
	set guardian_app_login_status = v_status,
		guardian_app_login_enabled = v_enabled,
		updated_at = now()
	where id = p_guardian_id and school_id = v_school_id;

	insert into public.audit_logs (
		user_id, actor_id, action, entity_type, entity_id, description, metadata
	) values (
		auth.uid(), auth.uid(), 'guardian_app_login.updated', 'guardians', p_guardian_id::text,
		case v_status
			when 'active' then 'تم تفعيل دخول ولي الأمر إلى التطبيق.'
			when 'reset_required' then 'تم تحديد أن ولي الأمر يحتاج إعادة تعيين كلمة المرور.'
			when 'disabled' then 'تم تعطيل دخول ولي الأمر إلى التطبيق.'
			else 'تم تحديث حالة دخول ولي الأمر إلى التطبيق.'
		end,
		jsonb_build_object('status', v_status, 'enabled', v_enabled, 'reason', nullif(btrim(coalesce(p_reason, '')), ''))
	);

	return jsonb_build_object(
		'guardian_id', p_guardian_id,
		'status', v_status,
		'enabled', v_enabled,
		'reason', nullif(btrim(coalesce(p_reason, '')), '')
	);
end $$;

revoke all on function public.update_guardian_app_login_status(uuid,text,text) from public, anon;
grant execute on function public.update_guardian_app_login_status(uuid,text,text) to authenticated;

create or replace function public.register_student_enrollment(
	p_student_id uuid,
	p_academic_year_id uuid,
	p_grade_id uuid,
	p_class_id uuid default null,
	p_enrollment_type text default 'new',
	p_enrollment_status text default 'نشط',
	p_enrollment_date date default current_date,
	p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_student students%rowtype;
	v_year academic_years%rowtype;
	v_grade school_grades%rowtype;
	v_class classes%rowtype;
	v_enrollment student_enrollments%rowtype;
	v_inserted boolean := false;
	v_grade_age_error text;
	v_is_new boolean := p_enrollment_type in ('new', 'مستجد');
	v_is_repeat boolean := p_enrollment_type in ('repeat', 'failed', 'معيد');
	v_existing_id uuid;
begin
	perform app.require_perm('students.enrollment.manage');
	select * into v_student from students where id = p_student_id and coalesce(is_archived, false) = false;
	if not found then raise exception 'الطالب غير موجود أو مؤرشف'; end if;

	select * into v_year from academic_years where id = p_academic_year_id;
	if not found then raise exception 'السنة الدراسية غير موجودة'; end if;
	if v_year.school_id is distinct from app.current_school_id()
		 or v_student.school_id is distinct from v_year.school_id then
		raise exception 'بيانات التسجيل لا تنتمي إلى المدرسة الحالية';
	end if;
	if v_year.status in ('closed','archived','مغلقة','مؤرشفة') then
		raise exception 'لا يمكن التسجيل في سنة دراسية مغلقة أو مؤرشفة';
	end if;

	select * into v_grade from school_grades
	where id = p_grade_id and is_active and is_archived = false;
	if not found or v_grade.school_id is distinct from v_year.school_id then
		raise exception 'الصف الدراسي غير صالح لهذه المدرسة';
	end if;

	v_grade_age_error := public.student_grade_age_compatibility(p_student_id, p_grade_id);
	if v_grade_age_error is not null then
		raise exception '%', v_grade_age_error;
	end if;

	if p_class_id is not null then
		select * into v_class from classes
		where id = p_class_id and is_active and is_archived = false
		for update;
		if not found
			 or v_class.academic_year_id is distinct from p_academic_year_id
			 or v_class.grade_id is distinct from p_grade_id
			 or v_class.school_id is distinct from v_year.school_id then
			raise exception 'الفصل لا يتبع السنة والصف المحددين';
		end if;
		if v_class.capacity is not null and (
			select count(*) from student_enrollments e
			where e.class_id = v_class.id
				and e.outcome = 'in_progress'
				and coalesce(e.enrollment_status, 'نشط') in ('نشط','active')
		) >= v_class.capacity then
			raise exception 'الفصل ممتلئ ولا يمكن إضافة تسجيل جديد';
		end if;
	end if;

	insert into student_enrollments (
		student_id, academic_year_id, grade_id, class_id, enrollment_date,
		outcome, enrollment_status, is_new_student, is_repeat
	) values (
		p_student_id, p_academic_year_id, p_grade_id, p_class_id,
		coalesce(p_enrollment_date, current_date), 'in_progress',
		coalesce(nullif(btrim(p_enrollment_status), ''), 'نشط'),
		v_is_new, v_is_repeat
	)
	on conflict (student_id, academic_year_id) do nothing
	returning * into v_enrollment;

	v_inserted := v_enrollment.id is not null;
	if not v_inserted then
		select * into v_enrollment from student_enrollments
		where student_id = p_student_id and academic_year_id = p_academic_year_id;
		v_existing_id := v_enrollment.id;
	end if;

	if v_inserted then
		insert into audit_logs (
			user_id, actor_id, action, entity_type, entity_id, academic_year_id,
			new_value, description, metadata
		) values (
			auth.uid(), auth.uid(), 'enrollment.created', 'student_enrollment',
			v_enrollment.id::text, p_academic_year_id,
			jsonb_build_object('student_id', p_student_id, 'grade_id', p_grade_id,
				'class_id', p_class_id),
			'تم تسجيل طالب في سنة دراسية',
			jsonb_build_object('enrollment_type', p_enrollment_type)
		);
	end if;

	return jsonb_build_object(
		'created', v_inserted,
		'is_duplicate', not v_inserted,
		'enrollment_id', coalesce(v_enrollment.id, v_existing_id)
	);
end $$;

create or replace function public.promote_class(
	p_source_class_id uuid,
	p_target_year_id uuid,
	p_decisions jsonb,
	p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	x jsonb;
	v_source student_enrollments%rowtype;
	v_source_class classes%rowtype;
	v_target_year academic_years%rowtype;
	v_target_class classes%rowtype;
	v_target_grade school_grades%rowtype;
	v_target_id uuid;
	v_created integer := 0;
	v_skipped integer := 0;
	v_decision text;
	v_existing boolean;
begin
	perform app.require_perm('students.enrollment.manage');
	select * into v_source_class from classes where id = p_source_class_id and is_active;
	if not found or v_source_class.school_id is distinct from app.current_school_id() then
		raise exception 'الفصل المصدر غير صالح';
	end if;
	if not exists (
		select 1 from public.academic_years y
		where y.id=v_source_class.academic_year_id
			and y.school_id=app.current_school_id()
	) then
		raise exception 'السنة المصدر غير صالحة أو مغلقة';
	end if;

	select * into v_target_year from academic_years where id = p_target_year_id;
	if not found or v_target_year.school_id is distinct from app.current_school_id() then
		raise exception 'السنة المستهدفة غير صالحة';
	end if;
	if v_target_year.status in ('closed','archived','مغلقة','مؤرشفة') then
		raise exception 'لا يمكن إنشاء تسجيلات في سنة مغلقة أو مؤرشفة';
	end if;

	for x in select * from jsonb_array_elements(coalesce(p_decisions, '[]'::jsonb)) loop
		v_decision := coalesce(x->>'outcome', 'promoted');
		if v_decision in ('withdrawn', 'منسحب') then continue; end if;
		if v_decision not in ('promoted','failed','repeat','ناجح/منقول','معيد') then
			raise exception 'قرار ترقية غير صالح';
		end if;

		select e.* into v_source
		from public.student_enrollments e
		join public.students s on s.id=e.student_id
		where e.id = (x->>'enrollment_id')::uuid
			and e.class_id = p_source_class_id
			and e.academic_year_id = v_source_class.academic_year_id
			and e.outcome = 'in_progress'
			and s.school_id = app.current_school_id();
		if not found then raise exception 'يوجد تسجيل مصدر غير صالح'; end if;

		if nullif(x->>'target_grade_id', '') is null then raise exception 'الصف المستهدف مطلوب'; end if;
		select * into v_target_grade from school_grades
		where id = (x->>'target_grade_id')::uuid and is_active and not is_archived;
		if not found or v_target_grade.school_id is distinct from v_target_year.school_id then
			raise exception 'الصف المستهدف غير صالح';
		end if;

		if public.student_grade_age_compatibility(v_source.student_id, v_target_grade.id) is not null then
			raise exception '%', public.student_grade_age_compatibility(v_source.student_id, v_target_grade.id);
		end if;

		if nullif(x->>'target_class_id', '') is null then raise exception 'الفصل المستهدف مطلوب'; end if;
		select * into v_target_class from classes
		where id = (x->>'target_class_id')::uuid and is_active and not is_archived
		for update;
		if not found
			 or v_target_class.academic_year_id is distinct from p_target_year_id
			 or v_target_class.grade_id is distinct from v_target_grade.id
			 or v_target_class.school_id is distinct from v_target_year.school_id then
			raise exception 'الفصل المستهدف لا يتبع السنة والصف المحددين';
		end if;

		select exists (select 1 from student_enrollments
			where student_id = v_source.student_id and academic_year_id = p_target_year_id)
			into v_existing;
		if v_existing then v_skipped := v_skipped + 1; continue; end if;

		if v_target_class.capacity is not null and (
			select count(*) from student_enrollments e
			where e.class_id = v_target_class.id
				and e.outcome = 'in_progress'
				and coalesce(e.enrollment_status, 'نشط') in ('نشط','active')
		) >= v_target_class.capacity then
			raise exception 'الفصل المستهدف ممتلئ';
		end if;

		insert into student_enrollments (
			student_id, academic_year_id, grade_id, class_id, outcome,
			enrollment_status, is_new_student, is_repeat
		) values (
			v_source.student_id, p_target_year_id, v_target_grade.id,
			v_target_class.id, 'in_progress', 'نشط', false,
			v_decision in ('failed','repeat','معيد')
		)
		on conflict (student_id, academic_year_id) do nothing
		returning id into v_target_id;

		if v_target_id is null then
			v_skipped := v_skipped + 1;
		else
			v_created := v_created + 1;
			insert into audit_logs (
				user_id, actor_id, action, entity_type, entity_id, academic_year_id,
				old_value, new_value, description
			) values (
				auth.uid(), auth.uid(), 'enrollment.promoted', 'student_enrollment',
				v_target_id::text, p_target_year_id,
				jsonb_build_object('source_enrollment_id', v_source.id,
					'source_class_id', p_source_class_id),
				jsonb_build_object('target_grade_id', v_target_grade.id,
					'target_class_id', v_target_class.id),
				'تم إنشاء تسجيل جديد للطالب ضمن الترقية'
			);
		end if;
	end loop;
	return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end $$;

revoke all on function public.register_student_enrollment(uuid,uuid,uuid,uuid,text,text,date,text) from public, anon;
grant execute on function public.register_student_enrollment(uuid,uuid,uuid,uuid,text,text,date,text) to authenticated;
revoke all on function public.promote_class(uuid,uuid,jsonb,text) from public, anon;
grant execute on function public.promote_class(uuid,uuid,jsonb,text) to authenticated;
create or replace function public.update_timetable_entry(p_entry_id uuid,p_day_number smallint,p_period_id uuid,p_class_subject_id uuid,p_employee_id uuid default null,p_room text default null,p_expected_version integer default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ declare v_entry record; begin perform app.require_perm('timetable.manage'); select * into v_entry from timetable_entries where id = p_entry_id for update; if not found then return jsonb_build_object('updated',false,'warning','لم يتم العثور على الحصة المراد تعديلها.'); end if; update timetable_entries set day_number=p_day_number,period_id=p_period_id,class_subject_id=p_class_subject_id,employee_id=p_employee_id,room=p_room,version=version+1 where id=p_entry_id and (p_expected_version is null or version=p_expected_version); return jsonb_build_object('updated',found,'warning', case when exists (select 1 from timetable_entries t join timetable_periods tp on tp.id = t.period_id where t.is_active and t.id <> p_entry_id and t.academic_year_id = v_entry.academic_year_id and t.day_number = p_day_number and not (tp.end_time <= (select start_time from timetable_periods where id = p_period_id) or (select end_time from timetable_periods where id = p_period_id) <= tp.start_time) and (t.class_id = v_entry.class_id or (p_employee_id is not null and t.employee_id = p_employee_id) or (nullif(btrim(coalesce(p_room, '')), '') is not null and nullif(btrim(coalesce(t.room, '')), '') is not null and lower(btrim(t.room)) = lower(btrim(p_room)))) ) then 'تم حفظ التعديل مع تحذير تعارض في الجدول. راجع الإسناد قبل الاعتماد.' else null end); end $$;
create or replace function public.deactivate_timetable_entry(p_entry_id uuid,p_expected_version integer default null) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$ begin perform app.require_perm('timetable.manage'); update timetable_entries set is_active=false,version=version+1 where id=p_entry_id and (p_expected_version is null or version=p_expected_version); return jsonb_build_object('updated',found); end $$;
create or replace function public.generate_year_archive(
	p_academic_year_id uuid,
	p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,app,extensions,pg_temp
as $$
declare
	v_school_id uuid := app.current_school_id();
	v_year public.academic_years%rowtype;
	v_manifest jsonb;
	v_hash text;
	v_archive_id uuid;
	v_label text;
	v_item_count integer := 0;
	v_scope text := case when p_academic_year_id is null then 'school' else 'academic_year' end;
begin
	perform app.require_perm('archive.manage');
	if v_school_id is null then
		raise exception 'تعذر تحديد المدرسة الحالية.' using errcode = 'P0001';
	end if;
	if p_academic_year_id is not null then
		select * into v_year from public.academic_years
		where id = p_academic_year_id and school_id = v_school_id;
		if not found then
			raise exception 'السنة الدراسية غير موجودة في المدرسة الحالية.' using errcode = 'P0001';
		end if;
		v_label := coalesce(v_year.name_ar, v_year.code, 'أرشيف السنة الدراسية');
	else
		v_label := 'أرشيف المدرسة الكامل';
	end if;

	v_manifest := jsonb_build_object(
		'scope', v_scope,
		'academic_year_id', p_academic_year_id,
		'school_id', v_school_id,
		'records', jsonb_build_object(
			'students', (select count(*) from public.students where school_id = v_school_id),
			'student_enrollments', (
				select count(*) from public.student_enrollments se
				join public.students s on s.id = se.student_id
				where s.school_id = v_school_id
					and (p_academic_year_id is null or se.academic_year_id = p_academic_year_id)
			),
			'audit_logs', (
				select count(*) from public.audit_logs a
				where a.academic_year_id in (
					select y.id from public.academic_years y
					where y.school_id = v_school_id
						and (p_academic_year_id is null or y.id = p_academic_year_id)
				)
			),
			'payments', (
				select count(*) from public.payments
				where school_id = v_school_id
					and (p_academic_year_id is null or academic_year_id = p_academic_year_id)
			),
			'expenses', (
				select count(*) from public.expenses
				where school_id = v_school_id
					and (p_academic_year_id is null or academic_year_id = p_academic_year_id)
			)
		)
	);
	v_item_count := coalesce((
		select sum(value::integer) from jsonb_each_text(v_manifest->'records')
	), 0);
	v_hash := encode(
		extensions.digest(convert_to(v_manifest::text, 'UTF8'), 'sha256'::text),
		'hex'
	);

	insert into public.archive_records(
		school_id, academic_year_id, scope, label_ar, state, schema_version,
		app_version, manifest, manifest_hash, item_count, total_size_bytes,
		checksum_sha256, generated_at, created_by
	) values (
		v_school_id, p_academic_year_id, v_scope, v_label, 'generated',
		'1.0', 'school-management', v_manifest, v_hash, v_item_count, 0,
		null, now(), auth.uid()
	) returning id into v_archive_id;

	return jsonb_build_object(
		'archive_id', v_archive_id,
		'manifest_hash', v_hash,
		'item_count', v_item_count,
		'scope', v_scope,
		'state', 'generated'
	);
end $$;

create or replace function public.generate_year_archive_bundle(
	p_academic_year_id uuid,
	p_idempotency_key text,
	p_file_sha256 text,
	p_file_size_bytes bigint,
	p_bundle_manifest jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public,app,extensions,pg_temp
as $$
declare
	v_result jsonb;
	v_archive_id uuid;
	v_request_key text;
	v_request_hash text;
	v_existing public.idempotency_keys%rowtype;
	v_checksum text := lower(btrim(coalesce(p_file_sha256, '')));
	v_school_id uuid := app.current_school_id();
	v_manifest_hash text;
	v_total_records bigint := 0;
	v_item jsonb;
	v_table text;
	v_file text;
	v_count integer;
	v_checksum_item text;
	v_seen_tables text[] := array[]::text[];
begin
	perform app.require_perm('archive.manage');
	if auth.uid() is null or nullif(btrim(p_idempotency_key), '') is null then
		raise exception 'معرّف طلب الأرشيف مطلوب.' using errcode = '22023';
	end if;
	if v_checksum !~ '^[0-9a-f]{64}$' then
		raise exception 'بصمة ملف الأرشيف غير صالحة.' using errcode = '22023';
	end if;
	if p_file_size_bytes is null or p_file_size_bytes <= 0 then
		raise exception 'حجم ملف الأرشيف غير صالح.' using errcode = '22023';
	end if;
	if v_school_id is null or p_bundle_manifest is null
		or jsonb_typeof(p_bundle_manifest) is distinct from 'object'
		or jsonb_typeof(p_bundle_manifest->'included_tables') is distinct from 'array'
		or jsonb_array_length(p_bundle_manifest->'included_tables') = 0 then
		raise exception 'ملخص محتويات الأرشيف غير صالح أو فارغ.' using errcode = '22023';
	end if;
	if p_bundle_manifest->'school'->>'id' is distinct from v_school_id::text then
		raise exception 'الأرشيف لا يخص المدرسة الحالية.' using errcode = '42501';
	end if;
	if p_academic_year_id is not null
		and p_bundle_manifest->'academicYear'->>'id' is distinct from p_academic_year_id::text then
		raise exception 'السنة داخل الملف لا تطابق السنة المختارة.' using errcode = '22023';
	end if;
	if (p_academic_year_id is null and p_bundle_manifest->>'scope' is distinct from 'school')
		or (p_academic_year_id is not null and p_bundle_manifest->>'scope' is distinct from 'academic_year') then
		raise exception 'نطاق الأرشيف لا يطابق محتوى الملف.' using errcode = '22023';
	end if;
	if coalesce(p_bundle_manifest->>'schema_version', '') <> '1.0'
		or coalesce(p_bundle_manifest->>'total_records', '') !~ '^[0-9]+$' then
		raise exception 'إصدار الملف أو إجمالي سجلاته غير صالح.' using errcode = '22023';
	end if;

	for v_item in select value from jsonb_array_elements(p_bundle_manifest->'included_tables')
	loop
		v_table := coalesce(v_item->>'table', '');
		v_file := coalesce(v_item->>'file', '');
		if v_table = '' or v_file = '' or v_file ~ '(^/|(^|/)\.\.(/|$))'
			or coalesce(v_item->>'count', '') !~ '^[0-9]+$'
			or lower(coalesce(v_item->>'checksum_sha256', '')) !~ '^[0-9a-f]{64}$' then
			raise exception 'بيانات إحدى مجموعات الأرشيف غير صالحة.' using errcode = '22023';
		end if;
		if v_table = any(v_seen_tables) then
			raise exception 'قائمة محتويات الأرشيف تحتوي مجموعة مكررة.' using errcode = '22023';
		end if;
		v_seen_tables := array_append(v_seen_tables, v_table);
		v_count := (v_item->>'count')::integer;
		v_checksum_item := lower(v_item->>'checksum_sha256');
		v_total_records := v_total_records + v_count;
	end loop;
	if v_total_records <> (p_bundle_manifest->>'total_records')::bigint then
		raise exception 'إجمالي السجلات لا يطابق مجموع المجموعات.' using errcode = '22023';
	end if;
	if p_academic_year_id is null
		and p_bundle_manifest->'academicYear' is distinct from 'null'::jsonb then
		raise exception 'نطاق الأرشيف لا يطابق محتوى الملف.' using errcode = '22023';
	end if;

	v_request_key := 'year-archive-bundle:' || btrim(p_idempotency_key);
	v_request_hash := md5(jsonb_build_object(
		'academic_year_id', p_academic_year_id,
		'file_sha256', v_checksum,
		'file_size_bytes', p_file_size_bytes,
		'bundle_manifest', p_bundle_manifest
	)::text);
	perform pg_advisory_xact_lock(hashtextextended(v_request_key, 0));

	select * into v_existing from public.idempotency_keys where key = v_request_key;
	if found then
		if v_existing.actor_id is distinct from auth.uid()
			or v_existing.operation <> 'archive.generate_bundle'
			or v_existing.request_hash is distinct from v_request_hash then
			raise exception 'معرّف طلب الأرشيف مستخدم لطلب مختلف.' using errcode = 'P0001';
		end if;
		if v_existing.status = 'completed' and v_existing.result is not null then
			return v_existing.result;
		end if;
		raise exception 'عملية إنشاء الأرشيف السابقة غير مكتملة؛ استخدم طلبًا جديدًا.' using errcode = 'P0001';
	end if;

	insert into public.idempotency_keys(key, operation, actor_id, request_hash, status)
	values(v_request_key, 'archive.generate_bundle', auth.uid(), v_request_hash, 'in_progress');
	v_result := public.generate_year_archive(p_academic_year_id, p_idempotency_key);
	v_archive_id := nullif(v_result->>'archive_id', '')::uuid;
	if v_archive_id is null then
		raise exception 'تعذر إنشاء سجل الأرشيف.' using errcode = 'P0001';
	end if;
	v_manifest_hash := encode(
		extensions.digest(convert_to(p_bundle_manifest::text, 'UTF8'), 'sha256'::text),
		'hex'
	);

	update public.archive_records
	set checksum_sha256 = v_checksum,
		total_size_bytes = p_file_size_bytes,
		manifest = p_bundle_manifest,
		manifest_hash = v_manifest_hash,
		item_count = v_total_records
	where id = v_archive_id and school_id = v_school_id and state = 'generated';
	if not found then
		raise exception 'تعذر ربط بصمة الملف وملخصه بسجل الأرشيف.' using errcode = 'P0001';
	end if;

	insert into public.archive_items(
		archive_id, archive_record_id, category, record_count, checksum_sha256
	)
	select v_archive_id, v_archive_id, value->>'table',
		(value->>'count')::integer, lower(value->>'checksum_sha256')
	from jsonb_array_elements(p_bundle_manifest->'included_tables');

	v_result := v_result || jsonb_build_object(
		'checksum_sha256', v_checksum,
		'manifest_hash', v_manifest_hash,
		'item_count', v_total_records,
		'total_size_bytes', p_file_size_bytes,
		'scope', case when p_academic_year_id is null then 'school' else 'academic_year' end
	);
	update public.idempotency_keys
	set result = v_result, status = 'completed', completed_at = now()
	where key = v_request_key;
	return v_result;
end $$;

-- Compatibility overload retained for callers that register a ZIP checksum
-- without submitting the newer per-table bundle manifest.
create or replace function public.generate_year_archive_bundle(
	p_academic_year_id uuid,
	p_idempotency_key text,
	p_file_sha256 text,
	p_file_size_bytes bigint
) returns jsonb
language plpgsql
security definer
set search_path=public,app,extensions,pg_temp
as $$
declare
	v_result jsonb;
	v_archive_id uuid;
	v_request_key text;
	v_request_hash text;
	v_existing public.idempotency_keys%rowtype;
	v_checksum text := lower(p_file_sha256);
begin
	perform app.require_perm('archive.manage');
	if auth.uid() is null or nullif(btrim(p_idempotency_key), '') is null then
		raise exception 'معرّف طلب الأرشيف مطلوب.' using errcode = '22023';
	end if;
	if v_checksum is null or v_checksum !~ '^[0-9a-f]{64}$' then
		raise exception 'بصمة ملف الأرشيف غير صالحة.' using errcode = '22023';
	end if;
	if p_file_size_bytes is null or p_file_size_bytes < 0 then
		raise exception 'حجم ملف الأرشيف غير صالح.' using errcode = '22023';
	end if;

	v_request_key := 'year-archive-bundle:' || btrim(p_idempotency_key);
	v_request_hash := md5(jsonb_build_object(
		'academic_year_id', p_academic_year_id,
		'file_sha256', v_checksum,
		'file_size_bytes', p_file_size_bytes
	)::text);
	perform pg_advisory_xact_lock(hashtextextended(v_request_key, 0));

	select * into v_existing
	from public.idempotency_keys
	where key = v_request_key;
	if found then
		if v_existing.actor_id is distinct from auth.uid()
			or v_existing.operation <> 'archive.generate_bundle'
			or v_existing.request_hash is distinct from v_request_hash then
			raise exception 'معرّف طلب الأرشيف مستخدم لطلب مختلف.';
		end if;
		if v_existing.status = 'completed' and v_existing.result is not null then
			return v_existing.result;
		end if;
		raise exception 'عملية إنشاء الأرشيف السابقة غير مكتملة؛ استخدم طلبًا جديدًا.';
	end if;

	insert into public.idempotency_keys(key, operation, actor_id, request_hash, status)
	values(v_request_key, 'archive.generate_bundle', auth.uid(), v_request_hash, 'in_progress');
	v_result := public.generate_year_archive(p_academic_year_id, p_idempotency_key);
	v_archive_id := nullif(v_result->>'archive_id', '')::uuid;
	if v_archive_id is null then
		raise exception 'تعذر إنشاء سجل الأرشيف.';
	end if;

	update public.archive_records
	set checksum_sha256 = v_checksum,
		total_size_bytes = p_file_size_bytes
	where id = v_archive_id
		and school_id = app.current_school_id()
		and state = 'generated';
	if not found then
		raise exception 'تعذر ربط بصمة الملف بسجل الأرشيف.';
	end if;

	v_result := v_result || jsonb_build_object(
		'checksum_sha256', v_checksum,
		'total_size_bytes', p_file_size_bytes
	);
	update public.idempotency_keys
	set result = v_result,
		status = 'completed',
		completed_at = now()
	where key = v_request_key;
	return v_result;
end $$;

create or replace function public.purge_archived_audit_logs(p_archive_id uuid) returns jsonb language plpgsql security definer set search_path=public,app,pg_temp as $$
declare v_archive archive_records%rowtype; v_deleted integer := 0;
begin
	perform app.require_perm('archive.purge');
	select * into v_archive from archive_records where id = p_archive_id and school_id = app.current_school_id();
	if not found then
		raise exception 'الأرشيف غير موجود أو غير مصرح به.';
	end if;
	if v_archive.scope <> 'academic_year' or v_archive.academic_year_id is null then
		raise exception 'الحذف المتحكم فيه متاح لأرشيف سنة دراسية فقط.' using errcode = 'P0001';
	end if;
	if v_archive.state <> 'verified' then
		raise exception 'لا يمكن تنظيف الأرشيف قبل التحقق الكامل من سلامته.';
	end if;
	if v_archive.purge_eligible_at is null or now() < v_archive.purge_eligible_at then
		raise exception 'لم تنتهِ فترة انتظار التنظيف المحددة في السياسة.';
	end if;
	delete from public.audit_logs where academic_year_id = v_archive.academic_year_id;
	get diagnostics v_deleted = row_count;
	update archive_records set state = 'purged', purged_at = now() where id = p_archive_id;
	return jsonb_build_object('purged_rows', v_deleted, 'archive_id', p_archive_id, 'state', 'purged');
end $$;
create or replace function public.calculate_subject_result(p_enrollment_id uuid,p_grade_subject_id uuid,p_round app.exam_round default 'first') returns jsonb language sql security definer set search_path=public,app,pg_temp as $$ select jsonb_build_object('enrollment_id',p_enrollment_id,'grade_subject_id',p_grade_subject_id,'round',p_round) $$;

create or replace function public.academic_plan_totals(p_academic_year_id uuid)
returns table (
	grade_code text,
	grade_name text,
	actual_weekly_periods integer,
	expected_weekly_periods integer,
	difference integer,
	is_match boolean
)
language sql
stable
security definer
set search_path=public,app,pg_temp
as $$
	select
		g.code,
		g.name_ar,
		coalesce(sum(gs.weekly_periods) filter (where gs.is_active), 0)::integer,
		expected.periods,
		coalesce(sum(gs.weekly_periods) filter (where gs.is_active), 0)::integer - expected.periods,
		coalesce(sum(gs.weekly_periods) filter (where gs.is_active), 0)::integer = expected.periods
	from public.school_grades g
	join public.academic_years y on y.id = p_academic_year_id
		and y.school_id = g.school_id
		and y.school_id = app.current_school_id()
	join (values
		('G1', 22), ('G2', 22), ('G3', 28), ('G4', 27), ('G5', 27),
		('G6', 29), ('G7', 31), ('G8', 31), ('G9', 32)
	) as expected(code, periods) on expected.code = g.code
	left join public.grade_subjects gs
		on gs.academic_year_id = p_academic_year_id
	 and gs.grade_id = g.id
	group by g.code, g.name_ar, g.level_number, expected.periods
	order by g.level_number;
$$;

revoke execute on function public.academic_plan_totals(uuid) from public, anon;
grant execute on function public.academic_plan_totals(uuid) to authenticated;

-- Tenant-scoped academic result RPCs. These are the single canonical
-- implementations, grouped here for review and permission auditing.
create or replace function public.attendance_percentage(
	p_enrollment_id uuid,
	p_term_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path=public,app,pg_temp
as $$
declare
	v_total integer;
	v_present integer;
begin
	if not app.has_any_perm('attendance.students.view','attendance.students.manage','reports.attendance.view') then
		raise exception 'لا تملك صلاحية عرض نسبة الحضور';
	end if;
	if not exists (
		select 1 from public.student_enrollments e
		join public.students s on s.id=e.student_id
		where e.id=p_enrollment_id and s.school_id=app.current_school_id()
	) then
		raise exception 'التسجيل غير موجود في المدرسة الحالية';
	end if;
	if p_term_id is not null and not exists (
		select 1 from public.academic_terms t
		join public.student_enrollments e on e.academic_year_id=t.academic_year_id
		where t.id=p_term_id and e.id=p_enrollment_id
	) then
		raise exception 'الفصل الدراسي لا يطابق تسجيل الطالب';
	end if;
	select count(*),count(*) filter(where coalesce(a.status_code,a.status) in ('present','late','early_out'))
	into v_total,v_present
	from public.student_attendance a
	where a.enrollment_id=p_enrollment_id and (p_term_id is null or a.term_id=p_term_id);
	return jsonb_build_object(
		'percentage',coalesce(round(100.0*v_present/nullif(v_total,0),2),0),
		'denominator',v_total
	);
end;
$$;

create or replace function public.save_exam_grades(
	p_exam_id uuid,
	p_records jsonb,
	p_idempotency_key text default null
) returns jsonb
language plpgsql security definer
set search_path=public,app,pg_temp
as $$
declare
	x jsonb;
	n integer:=0;
	v_exam public.exams%rowtype;
	v_enrollment public.student_enrollments%rowtype;
	v_score numeric;
	v_absent boolean;
begin
	perform app.require_perm('grades.enter');
	select * into v_exam
	from public.exams
	where id=p_exam_id and school_id=app.current_school_id()
	for update;
	if not found then raise exception 'الامتحان غير موجود في المدرسة الحالية'; end if;
	if v_exam.status in ('approved','closed') then
		raise exception 'لا يمكن تعديل درجات امتحان معتمد أو مغلق';
	end if;
	if jsonb_typeof(coalesce(p_records,'[]'::jsonb)) <> 'array' then
		raise exception 'قائمة الدرجات غير صالحة';
	end if;
	for x in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
		select e.* into v_enrollment
		from public.student_enrollments e
		join public.students s on s.id=e.student_id
		where e.id=(x->>'enrollment_id')::uuid
			and s.school_id=app.current_school_id()
			and e.academic_year_id=v_exam.academic_year_id
			and (v_exam.class_id is null or e.class_id=v_exam.class_id)
			and (v_exam.grade_id is null or e.grade_id=v_exam.grade_id);
		if not found then raise exception 'تسجيل الطالب لا يطابق الامتحان أو المدرسة الحالية'; end if;
		v_absent:=coalesce((x->>'is_absent')::boolean,false);
		v_score:=nullif(x->>'score','')::numeric;
		if not v_absent and v_score is null then
			raise exception 'يجب إدخال درجة أو تحديد الطالب كغائب';
		end if;
		if v_score is not null and (v_score<0 or v_score>v_exam.max_score) then
			raise exception 'الدرجة خارج النطاق';
		end if;
		insert into public.grade_records(
			exam_id,enrollment_id,score,max_score,is_absent,notes,status,entered_by,entered_at
		) values (
			p_exam_id,v_enrollment.id,v_score,v_exam.max_score,v_absent,x->>'notes',
			'entered',auth.uid(),now()
		)
		on conflict(exam_id,enrollment_id) do update set
			score=excluded.score,max_score=excluded.max_score,is_absent=excluded.is_absent,
			notes=excluded.notes,status='entered',entered_by=auth.uid(),
			entered_at=now(),version=grade_records.version+1
		where grade_records.status <> 'approved';
		if not found then raise exception 'لا يمكن تعديل سجل درجات معتمد'; end if;
		n:=n+1;
	end loop;
	update public.exams set status='entered'
	where id=p_exam_id and school_id=app.current_school_id();
	return jsonb_build_object('saved',n,'total',n);
end;
$$;

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
	select * into v_exam from public.exams
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
	update public.exams set status='approved'
	where id=p_exam_id and school_id=app.current_school_id();
	return jsonb_build_object('approved_records',n);
end;
$$;

create or replace function public.academic_results_report(
	p_academic_year_id uuid default null,
	p_class_id uuid default null,
	p_round app.exam_round default 'first'
) returns table(
	academic_year text,class_name text,student_number text,student_name text,
	round app.exam_round,total_score numeric,max_total numeric,percentage app.percentage,
	grade_label text,attendance_pct app.percentage,decision app.pass_decision,
	decision_reason text,result_status app.result_status
)
language sql stable security definer
set search_path=public,app,pg_temp
as $$
	select y.code,c.name_ar,s.student_number,s.full_name,tr.round,tr.total_score,
		tr.max_total,tr.percentage,tr.grade_label,tr.attendance_pct,tr.decision,
		tr.decision_reason,tr.status
	from public.term_results tr
	join public.academic_years y on y.id=tr.academic_year_id
		and y.school_id=app.current_school_id()
	join public.student_enrollments e on e.id=tr.enrollment_id
		and e.academic_year_id=y.id
	join public.students s on s.id=e.student_id
		and s.school_id=app.current_school_id()
	left join public.classes c on c.id=e.class_id
		and c.school_id=app.current_school_id()
	where app.has_perm('reports.academic.view')
		and (p_academic_year_id is null or tr.academic_year_id=p_academic_year_id)
		and (p_class_id is null or e.class_id=p_class_id)
		and tr.round=p_round;
$$;

create or replace function public.approve_class_results(
	p_class_id uuid,
	p_round app.exam_round default 'first'
) returns jsonb
language plpgsql security definer
set search_path=public,app,pg_temp
as $$
declare n integer;
begin
	perform app.require_perm('results.approve');
	if not exists(select 1 from public.classes c
		where c.id=p_class_id and c.school_id=app.current_school_id()) then
		raise exception 'الفصل غير موجود في المدرسة الحالية';
	end if;
	update public.term_results tr
	set status='approved',approved_by=auth.uid(),approved_at=now()
	from public.student_enrollments e
	join public.students s on s.id=e.student_id
	where e.id=tr.enrollment_id and e.class_id=p_class_id
		and e.academic_year_id=tr.academic_year_id
		and s.school_id=app.current_school_id()
		and tr.round=p_round and tr.status in ('calculated','under_review');
	get diagnostics n=row_count;
	return jsonb_build_object('approved',n);
end;
$$;

create or replace function public.calculate_term_result(
	p_enrollment_id uuid,
	p_round app.exam_round default 'first'
) returns jsonb
language plpgsql security definer
set search_path=public,app,pg_temp
as $$
declare
	total numeric;
	mx numeric;
	v_enrollment public.student_enrollments%rowtype;
	v_status app.result_status;
	v_percentage numeric;
begin
	perform app.require_perm('results.calculate');
	select e.* into v_enrollment
	from public.student_enrollments e
	join public.students s on s.id=e.student_id
	where e.id=p_enrollment_id and s.school_id=app.current_school_id()
	for update of e;
	if not found then raise exception 'التسجيل غير موجود في المدرسة الحالية'; end if;
	select tr.status into v_status
	from public.term_results tr
	where tr.enrollment_id=p_enrollment_id and tr.round=p_round
	for update;
	if v_status in ('approved','closed') then
		raise exception 'لا يمكن إعادة احتساب نتيجة معتمدة أو مغلقة';
	end if;
	select coalesce(sum(gr.score),0),coalesce(sum(gr.max_score),0)
	into total,mx
	from public.grade_records gr
	join public.exams ex on ex.id=gr.exam_id
		and ex.school_id=app.current_school_id()
		and ex.academic_year_id=v_enrollment.academic_year_id
	where gr.enrollment_id=p_enrollment_id and gr.status='approved'
		and ex.round=p_round;
	v_percentage:=case when mx=0 then 0 else total/mx*100 end;
	insert into public.term_results(
		enrollment_id,academic_year_id,round,total_score,max_total,average,
		percentage,decision,status
	) values (
		p_enrollment_id,v_enrollment.academic_year_id,p_round,total,mx,
		v_percentage,v_percentage,
		case when mx=0 then 'incomplete'::app.pass_decision
			when v_percentage>=50 then 'pass'::app.pass_decision
			else 'fail'::app.pass_decision end,
		'calculated'
	)
	on conflict(enrollment_id,round) do update set
		total_score=excluded.total_score,max_total=excluded.max_total,
		average=excluded.average,percentage=excluded.percentage,
		decision=excluded.decision,status='calculated',calculated_at=now(),
		version=public.term_results.version+1;
	return jsonb_build_object('enrollment_id',p_enrollment_id,'percentage',v_percentage);
end;
$$;

-- Atomic, server-only user access management; execute privileges are finalized
-- in the canonical security migration (006).
create or replace function public.admin_set_user_access(
	p_actor_id uuid,
	p_user_id uuid,
	p_role text,
	p_status text,
	p_expected_version integer default null,
	p_permissions text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_actor public.profiles%rowtype;
	v_target public.profiles%rowtype;
	v_actor_is_admin boolean;
	v_school_id uuid;
begin
	if p_actor_id is null or p_user_id is null then
		raise exception 'معرّف المنفذ والمستخدم مطلوب.' using errcode = 'P0001';
	end if;
	select * into v_actor
	from public.profiles
	where id = p_actor_id and status = 'active';
	if not found then
		raise exception 'الحساب الإداري غير نشط أو غير موجود.' using errcode = 'P0001';
	end if;

	v_actor_is_admin := v_actor.role = 'admin';
	if not v_actor_is_admin and not exists (
		select 1 from public.user_permissions up
		where up.user_id = p_actor_id
			and coalesce(up.permission, up.permission_code) = 'users.manage'
	) then
		raise exception 'لا تملك صلاحية إدارة المستخدمين.' using errcode = 'P0001';
	end if;
	v_school_id := coalesce(
		v_actor.school_id,
		(select ss.school_id from public.school_settings ss where ss.id = 1)
	);
	if v_school_id is null then
		raise exception 'تعذر تحديد مدرسة الحساب الإداري.' using errcode = 'P0001';
	end if;

	if p_actor_id = p_user_id then
		raise exception 'لا يمكن تعديل صلاحيات الحساب الحالي من هذه الشاشة.' using errcode = 'P0001';
	end if;
	if p_role not in ('admin', 'staff', 'employee') then
		raise exception 'الدور المحدد غير صالح.' using errcode = 'P0001';
	end if;
	if p_status not in ('active', 'inactive', 'suspended', 'terminated') then
		raise exception 'حالة الحساب المحددة غير صالحة.' using errcode = 'P0001';
	end if;
	if p_role = 'admin' and not v_actor_is_admin then
		raise exception 'تعيين دور المدير متاح لمدير النظام فقط.' using errcode = 'P0001';
	end if;

	select * into v_target
	from public.profiles
	where id = p_user_id and school_id = v_school_id
	for update;
	if not found then
		raise exception 'المستخدم المطلوب غير موجود في المدرسة الحالية أو لا تملك صلاحية إدارته.' using errcode = 'P0001';
	end if;
	if v_target.role = 'admin' and not v_actor_is_admin then
		raise exception 'إدارة حسابات المديرين متاحة لمدير النظام فقط.' using errcode = 'P0001';
	end if;
	if v_target.employee_id is not null and not exists (
		select 1 from public.employees e
		where e.id = v_target.employee_id and e.school_id = v_school_id
	) then
		raise exception 'الموظف المرتبط لا ينتمي إلى المدرسة الحالية.' using errcode = 'P0001';
	end if;
	if p_expected_version is not null and v_target.version <> p_expected_version then
		raise exception 'تم تعديل الحساب من مستخدم آخر. حدّث القائمة ثم أعد المحاولة.' using errcode = 'P0004';
	end if;

	if exists (
		select 1
		from unnest(coalesce(p_permissions, '{}'::text[])) requested(permission)
		left join public.permissions allowed on allowed.key = requested.permission
		where allowed.key is null
	) then
		raise exception 'تتضمن الصلاحيات المرسلة قيمة غير معروفة.' using errcode = 'P0001';
	end if;

	update public.profiles
	set role = p_role,
			status = p_status,
			version = version + 1,
			updated_at = now()
	where id = p_user_id and school_id = v_school_id;

	if v_target.role <> 'admin' and p_role <> 'admin' then
		delete from public.user_permissions where user_id = p_user_id;
		insert into public.user_permissions(user_id, permission, permission_code, granted_by)
		select p_user_id, requested.permission, requested.permission, p_actor_id
		from (
			select distinct unnest(coalesce(p_permissions, '{}'::text[])) as permission
		) requested;
	end if;

	insert into public.audit_logs(
		user_id, actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description
	) values (
		p_user_id, p_actor_id, v_actor.full_name, 'user.access.updated', 'user',
		p_user_id::text,
		jsonb_build_object(
			'name', v_target.full_name,
			'username', v_target.username,
			'email', v_target.email,
			'role', v_target.role,
			'status', v_target.status
		),
		jsonb_build_object('role', p_role, 'status', p_status,
			'permissions', coalesce(p_permissions, '{}'::text[])),
		'تم تحديث دور المستخدم وحالته وصلاحياته',
		jsonb_build_object('school_id', v_school_id)
	);

	return jsonb_build_object('id', p_user_id, 'role', p_role, 'status', p_status);
end;
$$;

-- Create the public profile and its audit row in one transaction. Auth itself
-- is created by the server-only Edge Function.
create or replace function public.create_managed_user_profile(
	p_actor_id uuid,
	p_user_id uuid,
	p_username text,
	p_full_name text,
	p_email text,
	p_phone text,
	p_role text,
	p_status text,
	p_employee_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_actor public.profiles%rowtype;
	v_profile public.profiles%rowtype;
	v_is_admin boolean;
	v_school_id uuid;
begin
	if p_actor_id is null or p_user_id is null then
		raise exception 'معرّف المنفذ والمستخدم مطلوب.' using errcode = 'P0001';
	end if;
	select * into v_actor
	from public.profiles
	where id = p_actor_id and status = 'active';
	if not found then
		raise exception 'الحساب الإداري غير نشط أو غير موجود.' using errcode = 'P0001';
	end if;
	v_is_admin := v_actor.role = 'admin';
	if not v_is_admin and not exists (
		select 1 from public.user_permissions up
		where up.user_id = p_actor_id
			and coalesce(up.permission, up.permission_code) = 'users.manage'
	) then
		raise exception 'لا تملك صلاحية إنشاء المستخدمين.' using errcode = 'P0001';
	end if;
	v_school_id := coalesce(
		v_actor.school_id,
		(select ss.school_id from public.school_settings ss where ss.id = 1)
	);
	if v_school_id is null then
		raise exception 'تعذر تحديد مدرسة الحساب الإداري.' using errcode = 'P0001';
	end if;
	if p_role not in ('admin', 'staff', 'employee')
		or p_status not in ('active', 'inactive', 'suspended', 'terminated') then
		raise exception 'دور المستخدم أو حالته غير صالحة.' using errcode = 'P0001';
	end if;
	if p_role = 'admin' and not v_is_admin then
		raise exception 'إنشاء حساب مدير متاح لمدير النظام فقط.' using errcode = 'P0001';
	end if;
	if p_user_id is null or not exists (
		select 1 from auth.users u where u.id = p_user_id
	) then
		raise exception 'حساب Auth الجديد غير موجود.' using errcode = 'P0001';
	end if;
	if p_employee_id is not null and not exists (
		select 1 from public.employees e
		where e.id = p_employee_id
			and e.school_id = v_school_id
			and not e.is_archived
	) then
		raise exception 'الموظف المرتبط غير موجود أو مؤرشف في المدرسة الحالية.' using errcode = 'P0001';
	end if;

	insert into public.profiles(
		id, school_id, username, full_name, email, phone, role, status,
		employee_id, must_change_password, created_by
	) values (
		p_user_id, v_school_id, btrim(p_username), btrim(p_full_name),
		lower(btrim(p_email)), nullif(btrim(coalesce(p_phone, '')), ''), p_role,
		p_status, p_employee_id, true, p_actor_id
	) returning * into v_profile;

	insert into public.audit_logs(
		user_id, actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata
	) values (
		v_profile.id, p_actor_id,
		coalesce(nullif(btrim(v_actor.full_name), ''), v_actor.username),
		'user.created', 'user', v_profile.id::text, null,
		jsonb_build_object(
			'name', v_profile.full_name,
			'username', v_profile.username,
			'email', v_profile.email,
			'role', v_profile.role,
			'status', v_profile.status,
			'employee_id', v_profile.employee_id
		),
		'تم إنشاء مستخدم جديد: ' || v_profile.full_name,
		jsonb_build_object('module', 'users', 'school_id', v_school_id)
	);

	return jsonb_build_object('id', v_profile.id, 'name', v_profile.full_name);
end;
$$;

create or replace function public.admin_mark_password_change_required(
	p_actor_id uuid,
	p_user_id uuid,
	p_action text
)
returns jsonb
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_actor public.profiles%rowtype;
	v_target public.profiles%rowtype;
	v_school_id uuid;
begin
	if p_actor_id is null or p_user_id is null then
		raise exception 'معرّف المنفذ والمستخدم مطلوب.' using errcode = 'P0001';
	end if;
	select * into v_actor from public.profiles
	where id = p_actor_id and status = 'active';
	if not found or (
		v_actor.role <> 'admin'
		and not exists (
			select 1 from public.user_permissions up
			where up.user_id = p_actor_id
				and coalesce(up.permission, up.permission_code) = 'users.manage'
		)
	) then
		raise exception 'لا تملك صلاحية إدارة كلمات مرور المستخدمين.' using errcode = 'P0001';
	end if;
	v_school_id := coalesce(
		v_actor.school_id,
		(select ss.school_id from public.school_settings ss where ss.id = 1)
	);
	if v_school_id is null then
		raise exception 'تعذر تحديد مدرسة الحساب الإداري.' using errcode = 'P0001';
	end if;
	if p_actor_id = p_user_id then
		raise exception 'لا يمكن تنفيذ هذه العملية على الحساب الحالي.' using errcode = 'P0001';
	end if;
	if p_action not in ('user.password.reset', 'user.password.change.required') then
		raise exception 'نوع تسجيل كلمة المرور غير صالح.' using errcode = 'P0001';
	end if;

	select * into v_target from public.profiles
	where id = p_user_id and school_id = v_school_id
	for update;
	if not found then
		raise exception 'المستخدم المطلوب غير موجود في المدرسة الحالية أو لا تملك صلاحية إدارته.' using errcode = 'P0001';
	end if;
	if v_target.role = 'admin' and v_actor.role <> 'admin' then
		raise exception 'إدارة كلمات مرور المديرين متاحة لمدير النظام فقط.' using errcode = 'P0001';
	end if;
	if v_target.employee_id is not null and not exists (
		select 1 from public.employees e
		where e.id = v_target.employee_id and e.school_id = v_school_id
	) then
		raise exception 'الموظف المرتبط لا ينتمي إلى المدرسة الحالية.' using errcode = 'P0001';
	end if;

	update public.profiles
	set must_change_password = true,
			password_changed_at = null,
			version = version + 1,
			updated_at = now()
	where id = p_user_id and school_id = v_school_id;

	insert into public.audit_logs(
		user_id, actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata
	) values (
		p_user_id, p_actor_id,
		coalesce(nullif(btrim(v_actor.full_name), ''), v_actor.username),
		p_action, 'user', p_user_id::text,
		jsonb_build_object('must_change_password', v_target.must_change_password),
		jsonb_build_object('must_change_password', true),
		case when p_action = 'user.password.reset'
			then 'تمت إعادة تعيين كلمة مرور المستخدم'
			else 'تم فرض تغيير كلمة مرور المستخدم عند الدخول التالي' end,
		jsonb_build_object('module', 'users', 'school_id', v_school_id)
	);
	return jsonb_build_object('id', p_user_id, 'must_change_password', true);
end;
$$;

-- Authenticated login/password/logout audit events never store credentials.
create or replace function public.record_login()
returns void
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_profile public.profiles%rowtype;
	v_previous_login timestamptz;
begin
	select * into v_profile
	from public.profiles
	where id = auth.uid() and status = 'active'
	for update;
	if not found then raise exception 'الحساب غير نشط أو غير موجود'; end if;
	v_previous_login := v_profile.last_login_at;
	update public.profiles set last_login_at = now(), updated_at = now()
	where id = v_profile.id;
	insert into public.audit_logs(
		user_id, actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata
	) values (
		v_profile.id, v_profile.id,
		coalesce(nullif(btrim(v_profile.full_name), ''), v_profile.username),
		'login', 'user', v_profile.id::text,
		jsonb_build_object('last_login_at', v_previous_login),
		jsonb_build_object('last_login_at', now()),
		'تم تسجيل دخول المستخدم', jsonb_build_object('module', 'auth')
	);
end;
$$;

create or replace function public.mark_password_changed()
returns void
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_profile public.profiles%rowtype;
	v_was_required boolean;
begin
	select must_change_password into v_was_required
	from public.profiles
	where id = auth.uid() and status = 'active'
	for update;
	if not found then raise exception 'الحساب غير نشط أو غير موجود'; end if;
	update public.profiles
	set must_change_password = false,
			password_changed_at = now(),
			updated_at = now()
	where id = auth.uid() and status = 'active'
	returning * into v_profile;
	insert into public.audit_logs(
		user_id, actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata
	) values (
		v_profile.id, v_profile.id,
		coalesce(nullif(btrim(v_profile.full_name), ''), v_profile.username),
		'password.changed', 'user', v_profile.id::text,
		jsonb_build_object('must_change_password', v_was_required),
		jsonb_build_object('must_change_password', false),
		'تم تغيير كلمة مرور المستخدم', jsonb_build_object('module', 'auth')
	);
end;
$$;

create or replace function public.record_logout()
returns void
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_profile public.profiles%rowtype;
begin
	select * into v_profile from public.profiles
	where id = auth.uid() and status = 'active';
	if not found then return; end if;
	insert into public.audit_logs(
		user_id, actor_id, actor_label, action, entity_type, entity_id,
		description, metadata
	) values (
		v_profile.id, v_profile.id,
		coalesce(nullif(btrim(v_profile.full_name), ''), v_profile.username),
		'logout', 'user', v_profile.id::text,
		'تم تسجيل خروج المستخدم', jsonb_build_object('module', 'auth')
	);
end;
$$;

-- Filtered, permission-checked audit listing RPC used by the audit viewer.
create or replace function app.audit_entity_display_name(
	p_entity_type text,
	p_entity_id text,
	p_metadata jsonb,
	p_new_value jsonb,
	p_old_value jsonb,
	p_actor_id uuid,
	p_actor_label text
)
returns text
language plpgsql stable security invoker
set search_path=public,app,pg_temp
as $$
declare
	v_name text;
begin
	v_name := coalesce(
		nullif(btrim(p_metadata->>'entity_name'), ''),
		nullif(btrim(p_new_value->>'full_name'), ''),
		nullif(btrim(p_new_value->>'name_ar'), ''),
		nullif(btrim(p_new_value->>'name'), ''),
		nullif(btrim(p_old_value->>'full_name'), ''),
		nullif(btrim(p_old_value->>'name_ar'), ''),
		nullif(btrim(p_old_value->>'name'), '')
	);
	if v_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
		v_name := null;
	end if;
	if v_name is not null then return v_name; end if;

	if p_entity_type in ('student','students','student_attendance','student_app_accounts')
		and app.has_any_perm('students.manage','students.view','students.create','students.edit','students.archive','students.enrollment.manage') then
		select s.full_name into v_name from public.students s
		where s.id::text = p_entity_id and s.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type = 'student_enrollment'
		and app.has_any_perm('students.view','students.create','students.edit','students.enrollment.manage') then
		select s.full_name into v_name from public.student_enrollments e
		join public.students s on s.id = e.student_id
		where e.id::text = p_entity_id and s.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type in ('guardian','guardians')
		and app.has_any_perm('guardians.view','guardians.manage','students.manage','students.view','students.create','students.edit') then
		select g.full_name into v_name from public.guardians g
		where g.id::text = p_entity_id and g.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type in ('employee','employees')
		and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','reports.employees.view') then
		select e.full_name into v_name from public.employees e
		where e.id::text = p_entity_id and e.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type = 'payment'
		and app.has_any_perm('finance.payments.view','finance.payments.create','finance.payments.reverse','finance.reports.view') then
		select s.full_name into v_name from public.payments pay
		join public.students s on s.id = pay.student_id
		where pay.id::text = p_entity_id and pay.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type = 'student_fee'
		and app.has_any_perm('finance.fees.view','finance.fees.manage','finance.payments.view','finance.payments.create') then
		select s.full_name into v_name from public.student_fees f
		join public.student_enrollments e on e.id = f.enrollment_id
		join public.students s on s.id = e.student_id
		where f.id::text = p_entity_id and s.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type in ('academic_year','academic_years')
		and app.has_any_perm('academic_years.manage','academic_years.close') then
		select coalesce(nullif(y.name_ar, ''), y.code) into v_name
		from public.academic_years y
		where y.id::text = p_entity_id and y.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type in ('document','documents')
		and app.has_any_perm('documents.view','documents.upload','documents.approve') then
		select d.title_ar into v_name from public.documents d
		where d.id::text = p_entity_id and d.school_id = app.current_school_id();
		if v_name is not null then return v_name; end if;
	elsif p_entity_type in ('user','profile') then
		if p_entity_id = p_actor_id::text and nullif(btrim(p_actor_label), '') is not null then
			return p_actor_label;
		end if;
		if app.has_any_perm('users.view','users.manage') then
			select pr.full_name into v_name from public.profiles pr
			where pr.id::text = p_entity_id and pr.school_id = app.current_school_id();
			if v_name is not null then return v_name; end if;
		end if;
	end if;

	return case
		when p_entity_type in ('student','students','student_attendance','student_app_accounts','student_enrollment') then 'طالب غير محدد'
		when p_entity_type in ('guardian','guardians') then 'ولي أمر غير محدد'
		when p_entity_type in ('employee','employees') then 'موظف غير محدد'
		when p_entity_type in ('user','profile') then 'مستخدم غير محدد'
		when p_entity_type in ('payment','payments') then 'دفعة غير محددة'
		when p_entity_type = 'student_fee' then 'استحقاق مالي غير محدد'
		when p_entity_type in ('academic_year','academic_years') then 'سنة دراسية غير محددة'
		when p_entity_type in ('document','documents') then 'مستند غير محدد'
		when p_entity_type in ('expense','expenses') then 'مصروف غير محدد'
		else 'كيان غير محدد'
	end;
end;
$$;

revoke all on function app.audit_entity_display_name(text,text,jsonb,jsonb,jsonb,uuid,text) from public, anon;
grant execute on function app.audit_entity_display_name(text,text,jsonb,jsonb,jsonb,uuid,text) to authenticated;

create or replace function public.audit_logs_page(
	p_action text,
	p_entity_type text,
	p_query text,
	p_from timestamptz,
	p_to timestamptz,
	p_page integer,
	p_page_size integer,
	p_ids text[],
	p_include_facets boolean
)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,app,pg_temp
as $$
declare
	v_page integer := greatest(coalesce(p_page, 1), 1);
	v_page_size integer := least(greatest(coalesce(p_page_size, 25), 1), 100);
	v_total integer := 0;
	v_overall integer := 0;
	v_total_pages integer := 0;
	v_rows jsonb := '[]'::jsonb;
	v_actions jsonb := '[]'::jsonb;
	v_entities jsonb := '[]'::jsonb;
	v_query text := nullif(btrim(coalesce(p_query, '')), '');
begin
	perform app.require_perm('audit.view');
	if p_from is not null and p_to is not null and p_to <= p_from then
		raise exception 'نطاق تاريخ سجل التدقيق غير صالح';
	end if;

	select count(*)::integer into v_overall
	from public.audit_logs l;

	with base as (
		select l.id,
					 l.occurred_at,
					 l.actor_id,
					 l.user_id,
					 coalesce(nullif(btrim(l.actor_label), ''), nullif(btrim(p.full_name), ''), 'نظام/غير معروف') as actor_label,
					 l.action,
					 l.entity_type,
					 l.entity_id,
					 l.description,
					 coalesce(
						 nullif(btrim(l.metadata->>'entity_name'), ''),
						 nullif(btrim(l.new_value->>'full_name'), ''),
						 nullif(btrim(l.new_value->>'name_ar'), ''),
						 nullif(btrim(l.new_value->>'name'), ''),
						 nullif(btrim(l.old_value->>'full_name'), ''),
						 nullif(btrim(l.old_value->>'name_ar'), ''),
						 nullif(btrim(l.old_value->>'name'), ''),
						 case
							 when l.entity_type in ('student', 'student_attendance')
								 and app.has_any_perm('students.view','students.create','students.edit','students.archive','students.enrollment.manage')
							 then (select s.full_name from public.students s
								 where s.id::text = l.entity_id and s.school_id = app.current_school_id())
							 when l.entity_type = 'student_enrollment'
								 and app.has_any_perm('students.view','students.create','students.edit','students.enrollment.manage')
							 then (select s.full_name from public.student_enrollments e
								 join public.students s on s.id = e.student_id
								 where e.id::text = l.entity_id and s.school_id = app.current_school_id())
							 when l.entity_type = 'payment'
								 and app.has_any_perm('finance.payments.view','finance.payments.create','finance.payments.reverse','finance.reports.view')
							 then (select s.full_name from public.payments p
								 join public.students s on s.id = p.student_id
								 where p.id::text = l.entity_id and p.school_id = app.current_school_id())
							 when l.entity_type = 'student_fee'
								 and app.has_any_perm('finance.fees.view','finance.fees.manage','finance.payments.view','finance.payments.create')
							 then (select s.full_name from public.student_fees f
								 join public.student_enrollments e on e.id = f.enrollment_id
								 join public.students s on s.id = e.student_id
								 where f.id::text = l.entity_id and s.school_id = app.current_school_id())
							 when l.entity_type = 'employee'
								 and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','reports.employees.view')
							 then (select e.full_name from public.employees e
								 where e.id::text = l.entity_id and e.school_id = app.current_school_id())
							 when l.entity_type in ('user','profile')
								 and app.has_any_perm('users.view','users.manage')
							 then (select p.full_name from public.profiles p where p.id::text = l.entity_id)
							 else null
						 end,
						 nullif(btrim(l.entity_id), ''),
						 '—'
					 ) as entity_label,
					 l.metadata,
					 l.new_value,
					 l.old_value
		from public.audit_logs l
		left join public.profiles p on p.id = l.actor_id
	), filtered as (
		select b.*
		from base b
		where (p_action is null or b.action = p_action)
			and (p_entity_type is null or b.entity_type = p_entity_type)
			and (p_from is null or b.occurred_at >= p_from)
			and (p_to is null or b.occurred_at < p_to)
			and (p_ids is null or b.id::text = any(p_ids))
			and (
				v_query is null
				or b.actor_label ilike '%' || v_query || '%'
				or b.entity_label ilike '%' || v_query || '%'
				or coalesce(b.entity_id, '') ilike '%' || v_query || '%'
				or coalesce(b.description, '') ilike '%' || v_query || '%'
				or b.entity_type ilike '%' || v_query || '%'
			)
	)
	select count(*)::integer into v_total from filtered;

	v_total_pages := case
		when v_total = 0 then 0
		else ceil(v_total::numeric / v_page_size)::integer
	end;

	with base as (
		select l.id,
					 l.occurred_at,
					 l.actor_id,
					 l.user_id,
					 coalesce(nullif(btrim(l.actor_label), ''), nullif(btrim(p.full_name), ''), 'نظام/غير معروف') as actor_label,
					 l.action,
					 l.entity_type,
					 l.entity_id,
					 l.description,
					 coalesce(
						 nullif(btrim(l.metadata->>'entity_name'), ''),
						 nullif(btrim(l.new_value->>'full_name'), ''),
						 nullif(btrim(l.new_value->>'name_ar'), ''),
						 nullif(btrim(l.new_value->>'name'), ''),
						 nullif(btrim(l.old_value->>'full_name'), ''),
						 nullif(btrim(l.old_value->>'name_ar'), ''),
						 nullif(btrim(l.old_value->>'name'), ''),
						 case
							 when l.entity_type in ('student', 'student_attendance')
								 and app.has_any_perm('students.view','students.create','students.edit','students.archive','students.enrollment.manage')
							 then (select s.full_name from public.students s
								 where s.id::text = l.entity_id and s.school_id = app.current_school_id())
							 when l.entity_type = 'student_enrollment'
								 and app.has_any_perm('students.view','students.create','students.edit','students.enrollment.manage')
							 then (select s.full_name from public.student_enrollments e
								 join public.students s on s.id = e.student_id
								 where e.id::text = l.entity_id and s.school_id = app.current_school_id())
							 when l.entity_type = 'payment'
								 and app.has_any_perm('finance.payments.view','finance.payments.create','finance.payments.reverse','finance.reports.view')
							 then (select s.full_name from public.payments p
								 join public.students s on s.id = p.student_id
									 where p.id::text = l.entity_id and p.school_id = app.current_school_id())
							 when l.entity_type = 'student_fee'
								 and app.has_any_perm('finance.fees.view','finance.fees.manage','finance.payments.view','finance.payments.create')
							 then (select s.full_name from public.student_fees f
								 join public.student_enrollments e on e.id = f.enrollment_id
								 join public.students s on s.id = e.student_id
								 where f.id::text = l.entity_id and s.school_id = app.current_school_id())
							 when l.entity_type = 'employee'
								 and app.has_any_perm('employees.view','employees.create','employees.edit','employees.archive','reports.employees.view')
							 then (select e.full_name from public.employees e
								 where e.id::text = l.entity_id and e.school_id = app.current_school_id())
							 when l.entity_type in ('user','profile')
								 and app.has_any_perm('users.view','users.manage')
							 then (select p.full_name from public.profiles p where p.id::text = l.entity_id)
							 else null
						 end,
						 nullif(btrim(l.entity_id), ''),
						 '—'
					 ) as entity_label,
					 l.metadata,
					 l.new_value,
					 l.old_value
		from public.audit_logs l
		left join public.profiles p on p.id = l.actor_id
	), filtered as (
		select b.*
		from base b
		where (p_action is null or b.action = p_action)
			and (p_entity_type is null or b.entity_type = p_entity_type)
			and (p_from is null or b.occurred_at >= p_from)
			and (p_to is null or b.occurred_at < p_to)
			and (p_ids is null or b.id::text = any(p_ids))
			and (
				v_query is null
				or b.actor_label ilike '%' || v_query || '%'
				or b.entity_label ilike '%' || v_query || '%'
				or coalesce(b.entity_id, '') ilike '%' || v_query || '%'
				or coalesce(b.description, '') ilike '%' || v_query || '%'
				or b.entity_type ilike '%' || v_query || '%'
			)
	)
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'id', page_rows.id::text,
				'occurred_at', page_rows.occurred_at,
				'actor_id', page_rows.actor_id,
				'user_id', page_rows.user_id,
				'actor_label', page_rows.actor_label,
				'action', page_rows.action,
				'entity_type', page_rows.entity_type,
				'entity_id', page_rows.entity_id,
				'entity_label', app.audit_entity_display_name(
					page_rows.entity_type,
					page_rows.entity_id,
					page_rows.metadata,
					page_rows.new_value,
					page_rows.old_value,
					page_rows.actor_id,
					page_rows.actor_label
				),
				'login_status', page_rows.metadata->>'status',
				'description', page_rows.description
			) order by page_rows.occurred_at desc, page_rows.id desc
		),
		'[]'::jsonb
	) into v_rows
	from (
		select * from filtered
		order by occurred_at desc, id desc
		limit v_page_size
		offset (v_page - 1) * v_page_size
	) page_rows;

	if coalesce(p_include_facets, true) then
		select coalesce(jsonb_agg(f.action order by f.action), '[]'::jsonb)
		into v_actions
		from (select distinct action from public.audit_logs where action is not null) f;

		select coalesce(jsonb_agg(f.entity_type order by f.entity_type), '[]'::jsonb)
		into v_entities
		from (select distinct entity_type from public.audit_logs where entity_type is not null) f;
	end if;

	return jsonb_build_object(
		'rows', v_rows,
		'total_count', v_total,
		'overall_count', v_overall,
		'page', v_page,
		'page_size', v_page_size,
		'total_pages', v_total_pages,
		'actions', v_actions,
		'entity_types', v_entities
	);
end;
$$;

-- Minimal audit snapshots for student and employee row changes.
create or replace function app.audit_student_change()
returns trigger
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_actor_label text;
	v_action text;
	v_old jsonb;
	v_new jsonb;
begin
	select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.username), ''))
	into v_actor_label from public.profiles p where p.id = auth.uid();

	if tg_op = 'UPDATE'
		and (to_jsonb(old) - array['updated_at','student_app_login_status','student_app_login_enabled'])
			= (to_jsonb(new) - array['updated_at','student_app_login_status','student_app_login_enabled']) then
		return new;
	end if;
	if tg_op = 'DELETE' then
		v_action := 'student.deleted';
		v_old := jsonb_build_object(
			'student_number', old.student_number,
			'full_name', old.full_name,
			'educational_status', old.educational_status,
			'is_archived', old.is_archived
		);
		insert into public.audit_logs(actor_id, actor_label, action, entity_type, entity_id,
			old_value, description, metadata)
		values (auth.uid(), coalesce(v_actor_label, 'نظام'), v_action, 'student', old.id::text,
			v_old, 'تم حذف سجل طالب', jsonb_build_object('module', 'students', 'source', 'database-trigger'));
		return old;
	end if;

	v_new := jsonb_build_object(
		'student_number', new.student_number,
		'full_name', new.full_name,
		'educational_status', new.educational_status,
		'is_archived', new.is_archived
	);
	if tg_op = 'UPDATE' then
		v_old := jsonb_build_object(
			'student_number', old.student_number,
			'full_name', old.full_name,
			'educational_status', old.educational_status,
			'is_archived', old.is_archived
		);
		v_action := case
			when not old.is_archived and new.is_archived then 'student.archived'
			when old.is_archived and not new.is_archived then 'student.restored'
			else 'student.updated'
		end;
	else
		v_action := 'student.created';
	end if;
	insert into public.audit_logs(actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata)
	values (
		auth.uid(), coalesce(v_actor_label, 'نظام'), v_action, 'student', new.id::text,
		v_old, v_new,
		case when tg_op = 'INSERT' then 'تم إنشاء ملف طالب: ' || coalesce(new.full_name, new.student_number)
			else 'تم تعديل ملف الطالب: ' || coalesce(new.full_name, new.student_number) end,
		jsonb_build_object('module', 'students', 'source', 'database-trigger')
	);
	return new;
end;
$$;

create or replace function app.audit_employee_change()
returns trigger
language plpgsql
security definer
set search_path=public,app,pg_temp
as $$
declare
	v_actor_label text;
	v_action text;
	v_old jsonb;
	v_new jsonb;
	v_id uuid;
	v_name text;
begin
	select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.username), ''))
	into v_actor_label from public.profiles p where p.id = auth.uid();

	if tg_op = 'DELETE' then
		v_id := old.id;
		v_name := old.full_name;
		v_action := 'employee.deleted';
		v_old := jsonb_build_object(
			'employee_number', old.employee_number, 'full_name', old.full_name,
			'department_id', old.department_id, 'job_title_id', old.job_title_id,
			'employment_status', old.employment_status, 'is_teacher', old.is_teacher,
			'is_archived', old.is_archived
		);
	else
		v_id := new.id;
		v_name := new.full_name;
		v_new := jsonb_build_object(
			'employee_number', new.employee_number, 'full_name', new.full_name,
			'department_id', new.department_id, 'job_title_id', new.job_title_id,
			'employment_status', new.employment_status, 'is_teacher', new.is_teacher,
			'is_archived', new.is_archived
		);
		if tg_op = 'UPDATE' then
			if (to_jsonb(old) - array['updated_at','version']) = (to_jsonb(new) - array['updated_at','version']) then
				return new;
			end if;
			v_old := jsonb_build_object(
				'employee_number', old.employee_number, 'full_name', old.full_name,
				'department_id', old.department_id, 'job_title_id', old.job_title_id,
				'employment_status', old.employment_status, 'is_teacher', old.is_teacher,
				'is_archived', old.is_archived
			);
			v_action := case
				when not old.is_archived and new.is_archived then 'employee.archived'
				when old.is_archived and not new.is_archived then 'employee.restored'
				else 'employee.updated'
			end;
		else
			v_action := 'employee.created';
		end if;
	end if;

	insert into public.audit_logs(actor_id, actor_label, action, entity_type, entity_id,
		old_value, new_value, description, metadata)
	values (
		auth.uid(), coalesce(v_actor_label, 'نظام'), v_action, 'employee', v_id::text,
		v_old, v_new,
		case when v_action = 'employee.created' then 'تم إنشاء ملف موظف: ' || coalesce(v_name, '')
			when v_action = 'employee.deleted' then 'تم حذف ملف موظف: ' || coalesce(v_name, '')
			else 'تم تحديث ملف الموظف: ' || coalesce(v_name, '') end,
		jsonb_build_object('module', 'employees', 'source', 'database-trigger')
	);
	if tg_op = 'DELETE' then return old; end if;
	return new;
end;
$$;

-- Backwards-compatible 8-argument signature used by older SQL callers.
create or replace function public.audit_logs_page(
	p_action text,
	p_entity_type text,
	p_query text,
	p_from timestamptz,
	p_to timestamptz,
	p_page integer,
	p_page_size integer,
	p_ids text[]
)
returns jsonb
language plpgsql
security invoker
set search_path=public,app,pg_temp
as $$
begin
	return public.audit_logs_page(
		p_action, p_entity_type, p_query, p_from, p_to,
		p_page, p_page_size, p_ids, true
	);
end;
$$;
