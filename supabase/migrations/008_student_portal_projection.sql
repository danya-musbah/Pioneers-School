-- Correct and extend the authenticated student portal projection without
-- changing base migrations or granting direct table access to portal users.
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
	v_enrollment_id uuid;
begin
	v_student_id := app.current_student_portal_id();
	if v_student_id is null then
		return null;
	end if;

	select s.school_id
	into v_school_id
	from public.students s
	where s.id = v_student_id;

	select e.id
	into v_enrollment_id
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

	return jsonb_build_object(
		'student', (
			select jsonb_build_object(
				'id', s.id,
				'student_number', s.student_number,
				'file_number', s.file_number,
				'registration_number', s.registration_number,
				'registration_date', s.registration_date,
				'graduation_date', s.graduation_date,
				'full_name', s.full_name,
				'full_name_en', s.full_name_en,
				'first_name', s.first_name,
				'father_name', s.father_name,
				'grandfather_name', s.grandfather_name,
				'family_name', s.family_name,
				'mother_name', s.mother_name,
				'nearest_relative_name', s.nearest_relative_name,
				'nearest_relative_relationship', s.nearest_relative_relationship,
				'gender', s.gender,
				'date_of_birth', s.date_of_birth,
				'place_of_birth', s.place_of_birth,
				'religion', s.religion,
				'national_id', s.national_id,
				'student_phone', s.phone,
				'address', s.address,
				'residence_address', s.residence_address,
				'city', s.city,
				'region', s.region,
				'previous_school', s.previous_school,
				'nationality', s.nationality,
				'admission_type', s.admission_type,
				'educational_status', s.educational_status,
				'file_status', s.file_status,
				'stage', ast.name_ar,
				'grade', g.name_ar,
				'section', coalesce(nullif(btrim(c.section_name), ''), nullif(btrim(c.section_code), ''), nullif(btrim(c.name_ar), '')),
				'academic_year', coalesce(y.name_ar, y.label, y.code),
				'enrollment_date', e.enrollment_date,
				'withdrawal_date', e.withdrawal_date,
				'enrollment_status', e.enrollment_status,
				'roll_number', e.roll_number,
				'outcome', e.outcome,
				'is_new_student', e.is_new_student,
				'is_repeat', e.is_repeat
			)
			from public.students s
			left join public.student_enrollments e
				on e.id = v_enrollment_id
				and e.student_id = s.id
			left join public.academic_years y
				on y.id = e.academic_year_id
				and y.school_id = s.school_id
			left join public.school_grades g
				on g.id = e.grade_id
			left join public.academic_stages ast
				on ast.id = g.stage_id
			left join public.classes c
				on c.id = e.class_id
				and c.academic_year_id = e.academic_year_id
				and c.school_id = s.school_id
			where s.id = v_student_id
				and s.school_id = v_school_id
		),
		'attendance', jsonb_build_object(
			'present', coalesce((
				select count(*)
				from public.student_attendance a
				left join public.attendance_statuses st on st.code = a.status_code
				where a.enrollment_id = v_enrollment_id
					and (st.counts_as_present or a.status in ('حاضر', 'present', 'attended'))
			), 0),
			'late', coalesce((
				select count(*)
				from public.student_attendance a
				where a.enrollment_id = v_enrollment_id
					and (coalesce(a.minutes_late, 0) > 0 or a.status in ('متأخر', 'late'))
			), 0),
			'absent', coalesce((
				select count(*)
				from public.student_attendance a
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
						'status', coalesce(st.label_ar, a.status, a.status_code),
						'minutes_late', coalesce(a.minutes_late, 0)
					) as item,
					a.attendance_date
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
				'grade', gb.label_ar
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
				'label', ft.name_ar,
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
		'timetable_days', coalesce((
			select jsonb_agg(jsonb_build_object(
				'day_number', wd.day_number,
				'name_ar', wd.name_ar
			) order by wd.sort_order, wd.day_number)
			from public.week_days wd
			where wd.is_school_day
		), '[]'::jsonb),
		'timetable', coalesce((
			select jsonb_agg(jsonb_build_object(
				'entry_id', te.id,
				'day_number', te.day_number,
				'day', coalesce(wd.name_ar, nullif(btrim(te.day_of_week), '')),
				'period_id', te.period_id,
				'period_number', tp.period_number,
				'period', tp.name_ar,
				'start_time', tp.start_time,
				'end_time', tp.end_time,
				'subject_id', coalesce(cs.subject_id, te.subject_id),
				'subject', sub.name_ar,
				'teacher', emp.full_name,
				'room', coalesce(
					nullif(btrim(te.room_name), ''),
					nullif(btrim(te.room), ''),
					loc.name_ar,
					nullif(btrim(c.room_name), ''),
					nullif(btrim(c.room), '')
				)
			) order by te.day_number, tp.period_number, te.created_at, te.id)
			from public.timetable_entries te
			join public.classes c
				on c.id = te.class_id
				and c.academic_year_id = te.academic_year_id
				and c.school_id = v_school_id
			left join public.class_subjects cs
				on cs.id = te.class_subject_id
				and cs.class_id = te.class_id
				and cs.academic_year_id = te.academic_year_id
				and (cs.grade_id is null or cs.grade_id = c.grade_id)
			left join public.subjects sub
				on sub.id = coalesce(cs.subject_id, te.subject_id)
				and sub.school_id = c.school_id
			left join public.week_days wd on wd.day_number = te.day_number
			left join public.timetable_periods tp
				on tp.id = te.period_id
				and tp.academic_year_id = te.academic_year_id
				and tp.school_id = c.school_id
			left join public.employees emp
				on emp.id = te.employee_id
				and emp.school_id = c.school_id
			left join public.school_locations loc
				on loc.id = te.location_id
				and loc.school_id = c.school_id
			where te.class_id = (
				select e.class_id from public.student_enrollments e where e.id = v_enrollment_id
			)
				and te.academic_year_id = (
					select e.academic_year_id from public.student_enrollments e where e.id = v_enrollment_id
				)
				and te.is_active
		), '[]'::jsonb)
	);
end;
$$;
