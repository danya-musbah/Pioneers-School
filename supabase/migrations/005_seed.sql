insert into permissions(key,category,label,label_ar,is_sensitive,sort_order) values
('students.view','students','View students','عرض الطلاب',false,10),
('students.create','students','Create students','إضافة طالب',false,11),
('students.edit','students','Edit students','تعديل الطلاب',false,12),
('students.manage','students','Manage student access','إدارة وصول الطلاب',false,13),
('students.archive','students','Archive students','أرشفة الطلاب',false,14),
('students.file.withdraw','students','Student files','إدارة ملفات الطلاب',false,15),
('students.enrollment.manage','students','Manage student enrollments','إدارة تسجيلات الطلاب',true,16),
('guardians.view','guardians','View guardians','عرض أولياء الأمور',false,16),
('guardians.manage','guardians','Manage guardians','إدارة أولياء الأمور',false,17),
('academics.structure.manage','academic','Manage academic structure','إدارة الهيكل الدراسي',true,42),
('attendance.students.manage','attendance','Manage attendance','إدارة الحضور',false,20),
('attendance.students.view','attendance','View student attendance','عرض حضور الطلاب',false,19),
('attendance.employees.manage','attendance','Manage employee attendance','إدارة حضور الموظفين',false,21),
('attendance.employees.view','attendance','View employee attendance','عرض حضور الموظفين',false,22),
('grades.enter','academic','Enter grades','إدخال الدرجات',false,30),
('grades.view','academic','View grades','عرض الدرجات',false,35),
('grades.approve','academic','Approve grades','اعتماد الدرجات',true,31),
('exams.view','academic','View exams','عرض الاختبارات',false,34),
('results.view','academic','View results','عرض النتائج',false,36),
('results.calculate','academic','Calculate results','احتساب النتائج',false,32),
('results.approve','academic','Approve results','اعتماد النتائج',true,33),
('academic_years.manage','admin','Manage years','إدارة السنوات',true,40),
('academic_years.close','admin','Close years','إغلاق السنوات',true,41),
('employees.view','employees','View employees','عرض الموظفين',false,50),
('employees.create','employees','Create employees','إضافة موظفين',false,51),
('employees.edit','employees','Edit employees','تعديل الموظفين',false,52),
('employees.archive','employees','Archive employees','أرشفة الموظفين',true,53),
('employees.delete','employees','Delete employees','حذف الموظفين',true,54),
('leaves.view','employees','View leave requests','عرض طلبات الإجازة',false,56),
('leaves.manage','employees','Manage leave requests','إدارة طلبات الإجازة',true,57),
('leaves.approve','employees','Approve leave requests','اعتماد طلبات الإجازة',true,58),
('payroll.manage','employees','Manage payroll','إدارة الرواتب',true,53),
('payroll.approve','employees','Approve payroll','اعتماد الرواتب',true,54),
('payroll.view','finance','View payroll','عرض الرواتب',true,55),
('finance.payments.create','finance','Create payments','تسجيل الدفعات',false,60),
('finance.payments.reverse','finance','Reverse payments','عكس الدفعات',true,61),
('finance.payments.view','finance','View payments','عرض المدفوعات',false,62),
('finance.fees.view','finance','View student fees','عرض رسوم الطلاب',false,63),
('finance.fees.manage','finance','Manage student fees','إدارة رسوم الطلاب',true,64),
('finance.expenses.view','finance','View expenses','عرض المصروفات',false,65),
('finance.expenses.manage','finance','Manage expenses','إدارة المصروفات',true,66),
('finance.expenses.void','finance','Void expenses','إلغاء المصروفات',true,67),
('finance.reports.view','finance','Finance reports','التقارير المالية',false,62),
('social.view','social','View social cases','عرض الحالات الاجتماعية',true,70),
('social.manage','social','Manage social cases','إدارة الحالات الاجتماعية',true,71),
('documents.view','documents','View documents','عرض المستندات',false,79),
('documents.upload','documents','Upload documents','رفع المستندات',false,80),
('documents.approve','documents','Approve documents','اعتماد المستندات',true,81),
('attachments.manage','documents','Manage attachments','إدارة المرفقات',true,82),
('timetable.view','academic','View timetable','عرض الجدول',false,91),
('timetable.manage','academic','Manage timetable','إدارة الجدول',false,90),
('reports.students.view','reports','Student reports','تقارير الطلاب',false,103),
('reports.employees.view','reports','Employee reports','تقارير الموظفين',false,104),
('reports.academic.view','reports','Academic reports','التقارير الأكاديمية',false,100),
('reports.attendance.view','reports','Attendance reports','تقارير الحضور',false,102),
('reports.quality.view','reports','Quality reports','تقارير الجودة',false,101),
('archive.manage','admin','Manage archive','إدارة الأرشيف',true,110),
('archive.purge','admin','Purge archive','تنظيف الأرشيف',true,111),
('backup.manage','admin','Manage backups','إدارة النسخ الاحتياطي',true,112),
('audit.view','admin','View audit logs','عرض سجل الأنشطة',true,113),
('users.view','admin','View users','عرض المستخدمين',true,119),
('users.manage','admin','Manage users','إدارة المستخدمين',true,120),
('announcements.manage','admin','Manage announcements','إدارة الإعلانات',false,122),
('settings.manage','admin','Manage settings','إدارة الإعدادات',true,121)
on conflict(key) do nothing;

insert into attendance_statuses(code,label_ar,counts_present,counts_as_present,sort_order) values
('present','حاضر',true,true,1),('absent','غائب',false,false,2),('late','متأخر',true,true,3),('excused','غياب بعذر',false,false,4)
on conflict(code) do nothing;
insert into employee_attendance_statuses(code,label_ar,counts_present,sort_order) values
('present','حضور',true,1),('absent','غياب',false,2),('late','تأخير',true,3),('excused','غياب بعذر',false,4),('early_out','خروج مبكر',false,5),('leave','إجازة',false,6)
on conflict(code) do nothing;
insert into week_days(day_number,name_ar,is_school_day,sort_order) values
(0,'الأحد',true,1),(1,'الاثنين',true,2),(2,'الثلاثاء',true,3),(3,'الأربعاء',true,4),(4,'الخميس',true,5),(5,'الجمعة',false,6),(6,'السبت',false,7)
on conflict(day_number) do nothing;
insert into grade_bands(label_ar,min_pct,max_pct,sort_order)
select x.label_ar,x.min_pct,x.max_pct,x.sort_order
from (values
  ('ممتاز',85,100,1),('جيد جدًا',75,85,2),('جيد',65,75,3),('مقبول',50,65,4),('ضعيف',0,50,5)
) as x(label_ar,min_pct,max_pct,sort_order)
where not exists (
  select 1 from grade_bands g
  where g.min_pct = x.min_pct and g.max_pct = x.max_pct
);
insert into expense_categories(code,name_ar) values
('SALARIES','رواتب'),('UTILITIES','مرافق'),('MAINTENANCE','صيانة'),('SUPPLIES','مستلزمات'),('OTHER','أخرى')
on conflict(code) do nothing;
insert into social_case_categories(code,name_ar) values
('FINANCIAL','صعوبات مالية'),('BEHAVIORAL','مشكلة سلوكية'),('ACADEMIC','صعوبات تعليمية'),('HEALTH','حالة صحية'),('OTHER','أخرى')
on conflict(code) do nothing;

do $$
declare
  sid uuid;
  v_year_id uuid;
  v_start_year integer;
  v_year_code text;
begin
  insert into schools(name_ar,name_en,official_name_ar,school_type)
  select 'مدرسة رواد العلم الأولى للتعليم الحديث','Pioneers of Science School','مدرسة رواد العلم الأولى للتعليم الحديث','خاصة'
  where not exists (
    select 1 from schools s where lower(s.name_ar) = lower('مدرسة رواد العلم الأولى للتعليم الحديث')
  )
  returning id into sid;

  if sid is null then
    select s.id into sid from schools s
    where lower(s.name_ar) = lower('مدرسة رواد العلم الأولى للتعليم الحديث')
    order by s.created_at limit 1;
  end if;

  if sid is null then
    raise exception 'تعذر إنشاء أو العثور على المدرسة الأساسية';
  end if;

  insert into school_settings(id,school_id,name_ar,name_en,official_name_ar,address,city,region,country,phone,email,registration_number,tax_number,logo_path,logo_storage_path,currency_code,currency_label_ar,max_upload_mb,max_upload_size_mb,photo_max_px,audit_retention_months,archive_reminder_days,week_start_day,version)
  values(1,sid,'مدرسة رواد العلم الأولى للتعليم الحديث','Pioneers of Science School','مدرسة رواد العلم الأولى للتعليم الحديث','تاجوراء, محلة المشاي, بالقرب من مدرسة تاجوراء الشعبية, بمنزل عيسى كوسا','تاجوراء','طرابلس','ليبيا','092-4444078','hsn324367@gmail.com',null,null,null,null,'LYD','دينار ليبي',5,5,2400,36,30,0,1)
  on conflict (id) do update set
    school_id = excluded.school_id,
    name_ar = excluded.name_ar,
    name_en = excluded.name_en,
    official_name_ar = excluded.official_name_ar,
    address = case
      when school_settings.address = 'تاجوراء' then excluded.address
      else school_settings.address
    end,
    city = excluded.city,
    region = excluded.region,
    country = excluded.country,
    phone = excluded.phone,
    email = excluded.email,
    registration_number = excluded.registration_number,
    tax_number = excluded.tax_number,
    logo_path = excluded.logo_path,
    logo_storage_path = excluded.logo_storage_path,
    currency_code = excluded.currency_code,
    currency_label_ar = excluded.currency_label_ar,
    max_upload_mb = excluded.max_upload_mb,
    max_upload_size_mb = excluded.max_upload_size_mb,
    photo_max_px = excluded.photo_max_px,
    audit_retention_months = excluded.audit_retention_months,
    archive_reminder_days = excluded.archive_reminder_days,
    week_start_day = excluded.week_start_day,
    version = case
      when school_settings.address = 'تاجوراء' then school_settings.version + 1
      else excluded.version
    end,
    updated_at = now();

  select ay.id into v_year_id from academic_years ay
  where ay.school_id = sid and ay.is_current
    and ay.status not in ('closed','archived','مغلقة','مؤرشفة')
  order by ay.start_date desc limit 1;
  if v_year_id is null then
    select ay.id into v_year_id from academic_years ay
    where ay.school_id = sid and ay.status not in ('closed','archived','مغلقة','مؤرشفة')
    order by ay.start_date desc limit 1;
    if v_year_id is not null then
      update academic_years set is_current = true, status = 'active' where id = v_year_id;
    end if;
  end if;
  if v_year_id is null then
    v_start_year := extract(year from current_date)::integer
      - case when extract(month from current_date)::integer < 8 then 1 else 0 end;
    v_year_code := v_start_year || '/' || (v_start_year + 1);
    insert into academic_years(school_id,code,name_ar,start_date,end_date,status,is_current)
    values(sid,v_year_code,'العام الدراسي ' || v_year_code,
      make_date(v_start_year,9,1),make_date(v_start_year + 1,6,30),'active',true)
    on conflict (school_id,code) do nothing;
    select ay.id into v_year_id from academic_years ay
    where ay.school_id = sid and ay.code = v_year_code
      and ay.status not in ('archived','مؤرشفة');
    if v_year_id is null then
      raise exception 'يوجد عام دراسي مؤرشف بنفس الرمز ولا يمكن اعتماده تلقائياً';
    end if;
  end if;
  insert into academic_years(school_id, code, name_ar, start_date, end_date, status, is_current)
  values
    (sid, '2026/2027', 'العام الدراسي 2026–2027', make_date(2026, 9, 1), make_date(2027, 8, 31), 'active', false),
    (sid, '2027/2028', 'العام الدراسي 2027–2028', make_date(2027, 9, 1), make_date(2028, 8, 31), 'draft', false)
  on conflict (school_id, code) do nothing;
  update academic_years set is_current = true, status = 'active' where id = v_year_id;
  select extract(year from ay.start_date)::integer into v_start_year
  from academic_years ay where ay.id = v_year_id;

  insert into fee_types(school_id, code, name_ar, is_recurring, is_active, sort_order)
  values
    (sid, 'tuition', 'القسط الدراسي', true, true, 1),
    (sid, 'mental_account', 'الحساب الذهني', true, true, 2),
    (sid, 'supplementary_pack', 'المجموعة المكملة', true, true, 3),
    (sid, 'uniform_boys', 'زي بنين', false, true, 4),
    (sid, 'uniform_girls', 'زي بنات', false, true, 5)
  on conflict (school_id, name_ar) do nothing;

  insert into academic_stages(school_id,code,name_ar,name_en,sort_order)
  select sid, x.code, x.name_ar, x.name_en, x.sort_order
  from (values
    ('KG','مرحلة الروضة','Kindergarten Stage',1),
    ('PREP','مرحلة التمهيدي','Preschool Stage',2),
    ('PRIMARY','المرحلة الابتدائية','Primary Stage',3),
    ('PREPARATORY','المرحلة الإعدادية','Preparatory Stage',4)
  ) as x(code,name_ar,name_en,sort_order)
  where sid is not null
  on conflict (school_id, name_ar) do nothing;

  insert into school_grades(school_id,stage_id,code,name_ar,name_en,level_number,is_final_grade,is_certificate_grade)
  select sid, st.id, x.code, x.name_ar, x.name_en, x.level_number, x.is_final_grade, x.is_certificate_grade
  from (values
    ('KG_MORNING','روضة صباحي','Nursery Morning',-4,false,false),
    ('KG_EVENING','روضة مسائي','Nursery Evening',-3,false,false),
    ('PREP_MORNING','تمهيدي صباحي','Pre-K Morning',-2,false,false),
    ('PREP_EVENING','تمهيدي مسائي','Pre-K Evening',-1,false,false),
    ('G1','الصف الأول الابتدائي','Grade 1',1,false,false),
    ('G2','الصف الثاني الابتدائي','Grade 2',2,false,false),
    ('G3','الصف الثالث الابتدائي','Grade 3',3,false,false),
    ('G4','الصف الرابع الابتدائي','Grade 4',4,false,false),
    ('G5','الصف الخامس الابتدائي','Grade 5',5,false,false),
    ('G6','الصف السادس الابتدائي','Grade 6',6,false,false),
    ('G7','الصف السابع / أول إعدادي','Grade 7 / First Preparatory',7,false,false),
    ('G8','الصف الثامن / ثاني إعدادي','Grade 8 / Second Preparatory',8,false,false),
    ('G9','الصف التاسع / ثالث إعدادي','Grade 9 / Third Preparatory',9,true,true)
  ) as x(code,name_ar,name_en,level_number,is_final_grade,is_certificate_grade)
  join academic_stages st on st.school_id = sid and st.code = case
    when x.code in ('KG_MORNING','KG_EVENING') then 'KG'
    when x.code in ('PREP_MORNING','PREP_EVENING') then 'PREP'
    when x.code between 'G1' and 'G6' then 'PRIMARY'
    else 'PREPARATORY'
  end
  where sid is not null
  on conflict (code) do nothing;

  insert into subjects(school_id,code,name_ar,is_core,sort_order)
  select sid, x.code, x.name_ar, x.is_core, x.sort_order
  from (values
    ('AR','اللغة العربية',true,1),
    ('ISL','التربية الإسلامية',true,2),
    ('QURAN','القرآن الكريم',true,3),
    ('EN','اللغة الإنجليزية',true,4),
    ('MATH','الرياضيات',true,5),
    ('SCI','العلوم',true,6),
    ('ICT','الحاسوب',true,7),
    ('WRITING','الكتابة',true,8),
    ('ART','التربية الفنية',false,9),
    ('PE','التربية البدنية',false,10),
    ('NATIONAL','التربية الوطنية',false,11),
    ('MUSIC_LIBRARY','التربية الموسيقية / المكتبة',false,12),
    ('HISTORY','التاريخ',true,13),
    ('GEOGRAPHY','الجغرافيا',true,14),
    ('SOCIAL_HISTORY','الاجتماعيات / التاريخ',true,15),
    ('SOCIAL_GEOGRAPHY','الاجتماعيات / الجغرافيا',true,16)
  ) as x(code,name_ar,is_core,sort_order)
  where sid is not null
  on conflict (school_id, name_ar) do nothing;

  insert into departments(school_id,code,name_ar,sort_order)
  values
    (sid,'MGMT','إدارة المدرسة',1),
    (sid,'ACADEMIC','الشؤون الأكاديمية',2),
    (sid,'STUDENTS','شؤون الطلاب',3),
    (sid,'HR','الموارد البشرية',4),
    (sid,'FINANCE','الإدارة المالية',5),
    (sid,'SERVICES','الخدمات',6)
  on conflict (school_id, name_ar) do nothing;

  insert into job_titles(school_id,code,name_ar,category,implies_teaching)
  values
    (sid,'PRINCIPAL','مدير المدرسة','قيادة',false),
    (sid,'TEACHER','معلم','تعليم',true),
    (sid,'REGISTRAR','مسؤول التسجيل','طلاب',false),
    (sid,'ACCOUNTANT','محاسب','مالية',false),
    (sid,'SECRETARY','سكرتير','إدارة',false),
    (sid,'GUARD','حارس','خدمات',false)
  on conflict (school_id, name_ar) do nothing;

  insert into timetable_periods(school_id,academic_year_id,period_number,name_ar,start_time,end_time,is_break)
  select sid, v_year_id, x.period_number, x.name_ar, x.start_time, x.end_time, x.is_break
  from (values
    (1,'الطابور',time '07:45',time '08:15',true),
    (2,'الحصة الأولى',time '08:15',time '08:55',false),
    (3,'الحصة الثانية',time '08:55',time '09:35',false),
    (4,'الحصة الثالثة',time '09:35',time '10:15',false),
    (5,'الاستراحة',time '10:15',time '10:55',true),
    (6,'الحصة الرابعة',time '10:55',time '11:35',false),
    (7,'الحصة الخامسة',time '11:35',time '12:15',false),
    (8,'الحصة السادسة',time '12:14',time '12:55',false)
  ) as x(period_number,name_ar,start_time,end_time,is_break)
  where sid is not null
  on conflict (school_id, period_number) do update set
    academic_year_id = excluded.academic_year_id,
    name_ar = excluded.name_ar,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    is_break = excluded.is_break;

  insert into classes(school_id,academic_year_id,grade_id,section_code,section_name,name_ar,capacity)
  select sid, v_year_id, g.id, x.section_code, x.section_name, x.name_ar, x.capacity
  from (values
    ('KG_MORNING','A','أ','روضة صباحي/أ',25),
    ('KG_EVENING','A','أ','روضة مسائي/أ',25),
    ('PREP_MORNING','A','أ','تمهيدي صباحي/أ',25),
    ('PREP_EVENING','A','أ','تمهيدي مسائي/أ',25),
    ('G1','A','أ','1/أ',30),
    ('G1','B','ب','1/ب',30),
    ('G2','A','أ','2/أ',30),
    ('G3','A','أ','3/أ',30),
    ('G3','B','ب','3/ب',30),
    ('G4','A','أ','4/أ',30),
    ('G5','A','أ','5/أ',30),
    ('G5','B','ب','5/ب',30),
    ('G6','A','أ','6/أ',30),
    ('G7','A','أ','7/أ',30),
    ('G7','B','ب','7/ب',30),
    ('G8','A','أ','8/أ',30),
    ('G9','A','أ','9/أ',30)
  ) as x(grade_code,section_code,section_name,name_ar,capacity)
  join school_grades g on g.school_id = sid and g.code = x.grade_code
  where sid is not null
  on conflict do nothing;

  insert into school_calendar_exceptions(
    school_id, academic_year_id, exception_date, start_date, end_date,
    kind, event_type, title_ar, grade_group, stage_code, reason, description, is_school_day
  )
  values
    (sid, v_year_id, date '2026-09-01', date '2026-09-01', date '2026-09-01', 'special_day', 'teacher_return', 'عودة المعلمين', 'all', 'all', 'عودة المعلمين', 'عودة المعلمين للعام الدراسي 2026–2027.', false),
    (sid, v_year_id, date '2026-09-13', date '2026-09-13', date '2026-09-13', 'special_day', 'academic', 'بداية العام الدراسي 2026–2027', 'all', 'all', 'بداية الدراسة', 'بداية العام الدراسي 2026–2027.', true),
    (sid, v_year_id, date '2026-12-30', date '2026-12-30', date '2026-12-31', 'holiday', 'holiday', 'راحة 30–31 ديسمبر 2026', 'all', 'all', 'عطلة نهاية العام', 'راحة 30–31 ديسمبر 2026.', false),
    (sid, v_year_id, date '2027-02-21', date '2027-02-21', date '2027-03-11', 'holiday', 'holiday', 'عطلة نصف السنة', 'all', 'all', 'عطلة نصف السنة', 'عطلة نصف السنة 2027.', false),
    (sid, v_year_id, date '2027-03-14', date '2027-03-14', date '2027-03-14', 'special_day', 'transition', 'استئناف الدراسة', 'all', 'all', 'استئناف الدراسة بعد عطلة نصف السنة', 'استئناف الدراسة بعد عطلة نصف السنة.', true),
    (sid, v_year_id, date '2027-05-16', date '2027-05-16', date '2027-05-20', 'holiday', 'holiday', 'عطلة عيد الأضحى', 'all', 'all', 'عطلة عيد الأضحى', 'عطلة عيد الأضحى 2027.', false),
    (sid, v_year_id, date '2026-12-13', date '2026-12-13', date '2026-12-29', 'exam_day', 'exam', 'اختبارات الفترة الأولى مع استمرار الدراسة', 'middle_school', 'preparatory', 'اختبارات الفترة الأولى', 'اختبارات الفترة الأولى مع استمرار الدراسة.', true),
    (sid, v_year_id, date '2027-05-23', date '2027-05-23', date '2027-06-03', 'exam_day', 'exam', 'امتحانات الدور الأول لشهادة إتمام التعليم الأساسي', 'basic_certificate', 'primary', 'امتحانات الشهادة الأساسية', 'امتحانات الدور الأول لشهادة إتمام التعليم الأساسي.', true),
    (sid, v_year_id, date '2027-06-13', date '2027-06-13', date '2027-07-01', 'exam_day', 'exam', 'امتحانات الدور الأول لشهادة إتمام التعليم الثانوي', 'secondary_certificate', 'secondary', 'امتحانات الشهادة الثانوية', 'امتحانات الدور الأول لشهادة إتمام التعليم الثانوي.', true),
    (sid, v_year_id, date '2027-07-18', date '2027-07-18', date '2027-07-29', 'exam_day', 'exam', 'امتحانات الدور الثاني لشهادة إتمام التعليم الأساسي', 'basic_certificate', 'primary', 'امتحانات الشهادة الأساسية', 'امتحانات الدور الثاني لشهادة إتمام التعليم الأساسي.', true),
    (sid, v_year_id, date '2027-08-15', date '2027-08-15', date '2027-08-26', 'exam_day', 'exam', 'امتحانات الدور الثاني لشهادة إتمام التعليم الثانوي', 'secondary_certificate', 'secondary', 'امتحانات الشهادة الثانوية', 'امتحانات الدور الثاني لشهادة إتمام التعليم الثانوي.', true),
    (sid, v_year_id, date '2026-11-08', date '2026-11-08', date '2026-11-19', 'exam_day', 'exam', 'الاختبارات النصفية للفصل الدراسي الأول', 'transition', 'preparatory', 'اختبارات نصفية', 'الاختبارات النصفية للفصل الدراسي الأول مع استمرار الدراسة.', true),
    (sid, v_year_id, date '2026-12-15', date '2026-12-15', date '2026-12-15', 'special_day', 'term', 'نهاية الفصل الدراسي الأول', 'transition', 'preparatory', 'نهاية الفصل الأول', 'نهاية الفصل الدراسي الأول.', false),
    (sid, v_year_id, date '2026-12-16', date '2026-12-16', date '2026-12-29', 'exam_day', 'exam', 'الامتحانات النهائية للفصل الدراسي الأول', 'transition', 'preparatory', 'امتحانات الفصل الأول', 'الامتحانات النهائية للفصل الدراسي الأول.', true),
    (sid, v_year_id, date '2027-01-03', date '2027-01-03', date '2027-01-03', 'special_day', 'transition', 'بداية الفصل الدراسي الثاني', 'transition', 'preparatory', 'بداية الفصل الثاني', 'بداية الفصل الدراسي الثاني.', true),
    (sid, v_year_id, date '2027-03-21', date '2027-03-21', date '2027-04-01', 'exam_day', 'exam', 'الاختبارات النصفية للفصل الدراسي الثاني', 'transition', 'preparatory', 'اختبارات نصفية', 'الاختبارات النصفية للفصل الدراسي الثاني مع استمرار الدراسة.', true),
    (sid, v_year_id, date '2027-04-29', date '2027-04-29', date '2027-04-29', 'special_day', 'term', 'نهاية الفصل الدراسي الثاني', 'transition', 'preparatory', 'نهاية الفصل الثاني', 'نهاية الفصل الدراسي الثاني.', false),
    (sid, v_year_id, date '2027-05-02', date '2027-05-02', date '2027-05-13', 'exam_day', 'exam', 'الامتحانات النهائية للفصل الدراسي الثاني', 'transition', 'preparatory', 'امتحانات الفصل الثاني', 'الامتحانات النهائية للفصل الدراسي الثاني.', true),
    (sid, v_year_id, date '2027-06-20', date '2027-06-20', date '2027-07-01', 'exam_day', 'exam', 'امتحانات الدور الثاني لصفوف النقل', 'transition', 'preparatory', 'امتحانات النقل', 'امتحانات الدور الثاني لصفوف النقل.', true),
    (sid, v_year_id, date '2026-11-12', date '2026-11-12', date '2026-11-12', 'special_day', 'exam', 'نهاية تقييم الفترة الأولى', 'primary', 'primary', 'التقييم الأول', 'نهاية تقييم الفترة الأولى للصفوف من الأول إلى الخامس.', true),
    (sid, v_year_id, date '2026-11-15', date '2026-11-15', date '2026-11-15', 'special_day', 'academic', 'بداية تقييم الفترة الثانية', 'primary', 'primary', 'بداية التقييم الثاني', 'بداية تقييم الفترة الثانية للصفوف من الأول إلى الخامس.', true),
    (sid, v_year_id, date '2027-01-14', date '2027-01-14', date '2027-01-14', 'special_day', 'exam', 'نهاية تقييم الفترة الثانية', 'primary', 'primary', 'التقييم الثاني', 'نهاية تقييم الفترة الثانية للصفوف من الأول إلى الخامس.', true),
    (sid, v_year_id, date '2027-01-17', date '2027-01-17', date '2027-01-17', 'special_day', 'academic', 'بداية تقييم الفترة الثالثة', 'primary', 'primary', 'بداية التقييم الثالث', 'بداية تقييم الفترة الثالثة للصفوف من الأول إلى الخامس.', true),
    (sid, v_year_id, date '2027-04-29', date '2027-04-29', date '2027-04-29', 'special_day', 'exam', 'نهاية تقييم الفترة الثالثة', 'primary', 'primary', 'التقييم الثالث', 'نهاية تقييم الفترة الثالثة للصفوف الأول والثاني والثالث.', true)
  on conflict (school_id, academic_year_id, exception_date) do update set
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    kind = excluded.kind,
    event_type = excluded.event_type,
    title_ar = excluded.title_ar,
    grade_group = excluded.grade_group,
    stage_code = excluded.stage_code,
    reason = excluded.reason,
    description = excluded.description,
    is_school_day = excluded.is_school_day;

  insert into academic_terms(academic_year_id,term_number,name_ar,start_date,end_date,is_current)
  select v_year_id,x.term_number,x.name_ar,x.start_date,x.end_date,
    current_date between x.start_date and x.end_date
  from (values
    (1,'الفصل الدراسي الأول',make_date(v_start_year,9,1),make_date(v_start_year,12,31)),
    (2,'الفصل الدراسي الثاني',make_date(v_start_year + 1,1,1),make_date(v_start_year + 1,3,31)),
    (3,'الفصل الدراسي الثالث',make_date(v_start_year + 1,4,1),make_date(v_start_year + 1,6,30))
  ) as x(term_number,name_ar,start_date,end_date)
  on conflict (academic_year_id,term_number) do update set
    name_ar = excluded.name_ar,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    is_current = excluded.is_current;

  insert into grade_subjects(
    academic_year_id,grade_id,subject_id,max_score,pass_percentage,
    coursework_weight,final_exam_weight,final_exam_min_pct,weekly_periods,
    assessment_type,exam_included
  )
  select v_year_id,g.id,s.id,100,50,
    case when x.exam_included then 30 else 100 end,
    case when x.exam_included then 70 else 0 end,
    case when x.exam_included then 40 else 0 end,
    x.weekly_periods,
    case when x.exam_included then 'continuous' else 'not_examined' end,
    x.exam_included
  from (values
    ('G1','ISL',3,true),('G1','AR',6,true),('G1','EN',3,true),('G1','ICT',1,true),('G1','MATH',5,true),('G1','ART',1,false),('G1','PE',2,false),('G1','MUSIC_LIBRARY',1,false),
    ('G2','ISL',3,true),('G2','AR',6,true),('G2','EN',3,true),('G2','ICT',1,true),('G2','MATH',5,true),('G2','ART',1,false),('G2','PE',2,false),('G2','MUSIC_LIBRARY',1,false),
    ('G3','ISL',3,true),('G3','AR',7,true),('G3','EN',3,true),('G3','ICT',1,true),('G3','MATH',6,true),('G3','SCI',4,true),('G3','ART',1,false),('G3','PE',2,false),('G3','MUSIC_LIBRARY',1,false),
    ('G4','ISL',3,true),('G4','AR',4,true),('G4','WRITING',2,true),('G4','EN',3,true),('G4','ICT',1,true),('G4','MATH',5,true),('G4','SCI',3,true),('G4','SOCIAL_HISTORY',1,true),('G4','SOCIAL_GEOGRAPHY',1,true),('G4','NATIONAL',1,true),('G4','ART',1,false),('G4','PE',1,false),('G4','MUSIC_LIBRARY',1,false),
    ('G5','ISL',3,true),('G5','AR',4,true),('G5','WRITING',2,true),('G5','EN',3,true),('G5','ICT',1,true),('G5','MATH',5,true),('G5','SCI',3,true),('G5','SOCIAL_HISTORY',1,true),('G5','SOCIAL_GEOGRAPHY',1,true),('G5','NATIONAL',1,true),('G5','ART',1,false),('G5','PE',1,false),('G5','MUSIC_LIBRARY',1,false),
    ('G6','ISL',3,true),('G6','AR',4,true),('G6','WRITING',2,true),('G6','EN',4,true),('G6','ICT',2,true),('G6','MATH',5,true),('G6','SCI',3,true),('G6','SOCIAL_HISTORY',1,true),('G6','SOCIAL_GEOGRAPHY',1,true),('G6','NATIONAL',1,true),('G6','ART',1,false),('G6','PE',1,false),('G6','MUSIC_LIBRARY',1,false),
    ('G7','ISL',2,true),('G7','AR',4,true),('G7','WRITING',2,true),('G7','EN',4,true),('G7','ICT',2,true),('G7','MATH',5,true),('G7','SCI',4,true),('G7','HISTORY',2,true),('G7','GEOGRAPHY',2,true),('G7','NATIONAL',1,true),('G7','ART',1,false),('G7','PE',1,false),('G7','MUSIC_LIBRARY',1,false),
    ('G8','ISL',2,true),('G8','AR',4,true),('G8','WRITING',2,true),('G8','EN',4,true),('G8','ICT',2,true),('G8','MATH',5,true),('G8','SCI',4,true),('G8','HISTORY',2,true),('G8','GEOGRAPHY',2,true),('G8','NATIONAL',1,true),('G8','ART',1,false),('G8','PE',1,false),('G8','MUSIC_LIBRARY',1,false),
    ('G9','ISL',2,true),('G9','AR',4,true),('G9','WRITING',2,true),('G9','EN',4,true),('G9','ICT',2,true),('G9','MATH',5,true),('G9','SCI',5,true),('G9','HISTORY',2,true),('G9','GEOGRAPHY',2,true),('G9','NATIONAL',1,true),('G9','ART',1,false),('G9','PE',1,false),('G9','MUSIC_LIBRARY',1,false)
  ) as x(grade_code,subject_code,weekly_periods,exam_included)
  join school_grades g on g.school_id = sid and g.code = x.grade_code
  join subjects s on s.school_id = sid and s.code = x.subject_code
  on conflict (academic_year_id,grade_id,subject_id) do update set
    weekly_periods = excluded.weekly_periods,
    assessment_type = excluded.assessment_type,
    exam_included = excluded.exam_included,
    coursework_weight = excluded.coursework_weight,
    final_exam_weight = excluded.final_exam_weight,
    final_exam_min_pct = excluded.final_exam_min_pct;

  insert into student_file_checklist_templates(school_id,code,category,label_ar,sort_order,is_required,is_active)
  select null,x.code,x.category,x.label_ar,x.sort_order,x.is_required,true
  from (values
    ('student_birth_certificate','core','شهادة ميلاد الطالب/ة',10,true),
    ('student_national_id','core','الرقم الوطني للطالب/ة',20,true),
    ('student_health_file','core','الملف الصحي / البطاقة الصحية',30,true),
    ('student_vaccination_card','core','بطاقة التطعيم',40,true),
    ('student_photo_set','core','أربع صور شخصية بالزي المدرسي',50,true),
    ('father_birth_certificate','family','شهادة ميلاد الأب',60,true),
    ('mother_birth_certificate','family','شهادة ميلاد الأم',70,true),
    ('family_status','family','الوضع العائلي',80,true),
    ('residence_certificate','family','شهادة إقامة / إفادة محل الإقامة',90,true),
    ('father_passport','international','صورة جواز سفر الأب',100,false),
    ('mother_passport','international','صورة جواز سفر الأم',110,false),
    ('student_passport','international','صورة جواز سفر الطالب/ة',120,false),
    ('foreign_student_letter','international','رسالة للوافدين للطلاب/الطالبات غير الليبيين',130,false),
    ('grade_1_sheet','grade','صحيفة الصف الأول',140,false),
    ('grade_2_sheet','grade','صحيفة الصف الثاني',150,false),
    ('grade_3_sheet','grade','صحيفة الصف الثالث',160,false),
    ('grade_4_sheet','grade','صحيفة الصف الرابع',170,false),
    ('grade_5_sheet','grade','صحيفة الصف الخامس',180,false),
    ('grade_6_sheet','grade','صحيفة الصف السادس',190,false),
    ('grade_7_sheet','grade','صحيفة الصف السابع',200,false),
    ('grade_8_sheet','grade','صحيفة الصف الثامن',210,false),
    ('grade_9_sheet','grade','صحيفة الصف التاسع',220,false),
    ('grade_10_sheet','grade','صحيفة الصف الأول ثانوي',230,false),
    ('grade_11_sheet','grade','صحيفة الصف الثاني ثانوي',240,false),
    ('grade_12_sheet','grade','صحيفة الصف الثالث ثانوي',250,false)
  ) as x(code,category,label_ar,sort_order,is_required)
  where not exists (
    select 1 from student_file_checklist_templates t
    where t.school_id is null and t.code = x.code
  );

  insert into schema_version(schema_version,app_version)
  values('2.0.0','2.0.0')
  on conflict (id) do update set
    schema_version = excluded.schema_version,
    app_version = excluded.app_version,
    applied_at = now();
end $$;

-- Preserve legacy single-school attribution when rebuilding from the canonical
-- sources; these updates are no-ops for already-scoped records.
update public.profiles p
set school_id = ss.school_id
from public.school_settings ss
where ss.id = 1 and ss.school_id is not null and p.school_id is null;

update public.academic_years ay
set school_id = ss.school_id
from public.school_settings ss
where ss.id = 1 and ss.school_id is not null and ay.school_id is null;

update public.audit_logs a
set school_id = coalesce(
  (select ay.school_id from public.academic_years ay where ay.id = a.academic_year_id),
  (select p.school_id from public.profiles p where p.id = coalesce(a.actor_id, a.user_id)),
  case
    when coalesce(a.metadata->>'school_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then (a.metadata->>'school_id')::uuid
  end,
  case when (select count(*) from public.schools) <= 1
    then (select ss.school_id from public.school_settings ss where ss.id = 1)
  end
)
where a.school_id is null;
