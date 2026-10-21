## 9. الأمان والصلاحيات

### 9.1 المصادقة والتفويض

- بوابة الطالب تستخدم Supabase Auth مع حفظ الجلسة وتجديد الرمز. `student-login` تبدأ قبل المصادقة؛ config يعطل JWT gateway validation لأول ثلاث دوال، لذلك يعتمد التفويض على تحقق handler من bearer/session/permission بحسب الدالة. `student-avatar` مفعّل له gateway validation ويتحقق كذلك داخل handler.
- أدوار الموظفين `admin`, `staff`, `employee`؛ الأذونات محفوظة في `permissions/user_permissions`، وadmin يمنح ضمنيًا كل صلاحية عبر helpers. حساب الطالب Auth مرتبط بسجل `student_app_accounts`.
- migrations تفعّل RLS للجداول العامة وتطبق حدود المدرسة والصلاحيات على مجالات متعددة. بوابة الطالب تستخدم RPC security-definer محدودة بدل direct table access.
- migration 006 تسحب execute العامة/anon ثم تمنح صلاحيات انتقائية؛ دوال حل رقم الطالب وإدارة المستخدمين service-role-only، وRPCs الطالب authenticated-only.

### 9.2 البيانات الحساسة والمدخلات

- mapper يهرب النصوص قبل عرضها؛ خطأ تسجيل الدخول لا يعيد بريد حساب الطالب. أسرار الخادم تقرأها Edge Functions عبر Deno.env ولا ينبغي وضعها في ملفات المتصفح.
- الصور عبر bucket خاص ورابط موقع مؤقت. CORS حد أصل وليس بديلًا للتفويض؛ قوائم localhost ثابتة وتختلف بين الدوال.
- لا دليل في المستودع على تشفير حقول قاعدة البيانات على مستوى التطبيق، أو سياسة احتفاظ منشورة، أو مراجعة أمنية مستقلة. لا تُدرج هنا أي قيم مفاتيح أو اعتماد.

### 9.3 مخاطر ذات سند برمجي

1. `uq_current_year` فريد عالميًا على `academic_years(is_current)` عند true، بينما trigger يمسح السنة الأخرى داخل المدرسة فقط؛ قد يمنع ذلك وجود عام حالي لأكثر من مدرسة.
2. سياسات Storage تسمح للمستخدم النشط بقراءة جميع objects في buckets المحددة دون شرط يربط الكائن بمدرسة/طالب/وثيقة داخل policy نفسها.
3. الحلقة العامة في RLS تمنح select للمستخدم النشط للجداول التي لم تستبدل سياستها؛ `idempotency_keys` و`login_attempts` بلا `school_id` ولا سياسة select خاصة معروفة، وقد تكشف metadata/hash.
4. سياسات مالية تسمح لبعض الأدوار بإدخال/تحديث صفوف مباشرة، وقد يتجاوز ذلك المسار الذري الذي ينشئ الرصيد/الإيصال/التدقيق.
5. عمليات Auth وDB والتدقيق في Edge Functions متعددة الأنظمة وغير ذرية؛ يوجد rollback تعويضي في مواضع لكنه لا يضمن التراجع الكامل.
6. حد تسجيل الدخول مبني على hash اسم المستخدم وفترة 15 دقيقة؛ لا يظهر تقييد IP أو تسلسل يضمن حدًا متزامنًا، والدالة لا تستدعي `record_login_failure()`.

## 10. حالات الاستخدام

### UC-01 — تصفح الموقع

- **الممثل والهدف:** زائر يريد معرفة المدرسة والوصول إلى الدخول.
- **الشروط المسبقة:** ملفات الواجهة والأصول متاحة.
- **التدفق الأساسي:** فتح الصفحة → الاطلاع على الأقسام/المراحل/FAQ → اختيار دخول الطالب.
- **البديل:** رابط خارجي أو CDN غير متاح؛ لا يوجد بديل محلي شامل للخدمات.
- **النتيجة:** يبقى الزائر بالموقع أو ينتقل إلى نموذج الدخول.

### UC-02 — دخول الطالب ومشاهدة ملخصه

- **الممثل والهدف:** طالب بحساب فعال يفتح بياناته المرتبطة.
- **الشروط المسبقة:** Auth/mapping صالحان، النشر وتطبيق migrations مكتملان، اتصال متاح.
- **التدفق الأساسي:** إدخال بيانات → Edge Function → Auth session → `student_portal_session` و`student_portal_data` → مطابقة الهوية → عرض البوابة.
- **البديل:** مدخل ناقص/حساب غير مربوط أو معطل/حد محاولات/مهلة/خطأ بيانات أو هوية؛ تظهر رسالة ولا تعرض بيانات غير متحققة.
- **النتيجة:** بوابة للطالب المرتبط أو البقاء في الدخول.

### UC-03 — مراجعة البيانات الدراسية

- **الممثل والهدف:** طالب مسجل يراجع ملفه أو حضوره أو نتائجه أو رسومه أو جدوله.
- **الشروط المسبقة:** إسقاط بيانات صالح.
- **التدفق الأساسي:** اختيار القسم → عرض البيانات المحملة أو الحالة الفارغة → استخدام history للرجوع.
- **البديل:** النقص يظهر كحالة فارغة/تحذير، ولا تُخترع قيم للجدول.
- **النتيجة:** عرض قراءة فقط مرتبط بحساب Auth.

### UC-04 — تسجيل الخروج

- **الممثل والهدف:** طالب ينهي الجلسة.
- **الشروط المسبقة:** بوابة مفتوحة.
- **التدفق الأساسي:** اختيار الخروج → تأكيد → signOut ومسح state والعودة للموقع.
- **البديل:** إلغاء أو Escape يبقي الجلسة؛ عند الفشل يحاول التطبيق إزالة الجلسة المحلية.
- **النتيجة:** واجهة عامة دون بيانات الطالب في state المعروض.

### UC-05 — إدارة حساب عبر API الخلفية

- **الممثل والهدف:** موظف مصرح ينفذ إجراء حساب إداري/طالب.
- **الشروط المسبقة:** مستهلك API خارجي غير موجود في الواجهة المعروضة، Bearer صالح، `my_session` فعال، صلاحية ومدرسة صحيحتان.
- **التدفق الأساسي:** POST → تحقق origin/session/scope/المدخلات → Auth/DB/RPC → JSON وتدقيق حيث ينفذ.
- **البديل:** رفض 400/401/403/404/409/500 أو فشل جزئي بين الخدمات.
- **النتيجة:** تغير خادمي أو رفض؛ لا شاشة إدارة ضمن التطبيق الحالي.

## 11. القيود والاعتماديات

1. لا package manifest/build system جذر ظاهر؛ README يصف تشغيل خادم ثابت والاختبارات بـNode.
2. التشغيل الكامل يتطلب Supabase project وتهيئة خادم آمنة، migrations مطبقة، ونشر Edge Functions؛ لم يحدث اتصال أو نشر أثناء التحليل.
3. imports/CDN تعتمد على اتصال `esm.sh`, `unpkg`, Google Fonts وخدمات Supabase.
4. `verify_jwt=false` على admin-user-management/student-login/student-app-access؛ يجب أن يظل تحقق handler صحيحًا. avatar مضبوط `true`.
5. migrations متسلسلة؛ 006 و008 تغيران ACL ومنطق الإسقاط، و005 يزرع بيانات مدرسة/سنوات. الملفات لا تثبت أنها طبقت على مشروع منشور.
6. `school_settings` مفردة `id=1` مع schema أوسع متعدد المدارس؛ multi-tenant يحتاج تأكيدًا. `school_grades.code/level_number` عالميان unique.
7. قيم البيئة الفعلية، نشر CORS، أحجام الملفات، حالة المشروع الحي، ونسخ البيانات غير مدققة.

## 12. مصفوفة التتبّع

مصفوفة كل متطلب ومصدر التنفيذ والاختبار/حالة التحقق موجودة في [`requirements-traceability.md`](requirements-traceability.md). عندما لا يوجد اختبار مرتبط يرد النص **«لا يوجد اختبار معروف في المستودع»**؛ اختبارات mapper/عقد SQL لا تعادل التكامل الحي.

## 13. نقاط تحتاج إلى تحقق

التعارضات والفجوات والأسئلة والأجزاء غير المتحقق منها مدرجة في [`analysis-gaps.md`](analysis-gaps.md)، بما فيها حالة نشر Supabase، الضوابط المتعددة المدارس والتخزين، غياب واجهة الإدارة، واختبار CSS غير الناجح.

## 14. الملاحق

### 14.1 الوحدات والملفات المرجعية

| الوحدة               | الملفات                                                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| نقطة الدخول والمحتوى | `index.html`, `js/app.js`, `js/data.js`                                                                                                 |
| تحويل البيانات والفن | `js/student-portal-data.mjs`, `js/student-artwork.js`, `assets/characters/manifest.js`                                                  |
| اتصال Supabase       | `js/supabase-client.js`, `js/supabase-config.js`, `supabase/config.toml`                                                                |
| العرض                | `css/tokens.css`, `css/styles.css`, `css/student-portal.css`, `assets/`                                                                 |
| Edge Functions       | `supabase/functions/admin-user-management/index.ts`, `student-app-access/index.ts`, `student-login/index.ts`, `student-avatar/index.ts` |
| قاعدة البيانات       | migrations `001` إلى `008` ضمن `supabase/migrations/`                                                                                   |
| التوثيق والاختبار    | `README.md`, `tests/student-portal-data.test.mjs`                                                                                       |

### 14.2 قائمة الجداول حسب المجال

- المدرسة/الهوية: `schools`, `school_settings`, `profiles`, `permissions`, `user_permissions`, `audit_logs`, `idempotency_keys`, `schema_version`.
- الهيكل الأكاديمي: `academic_years`, `academic_stages`, `school_grades`, `subjects`, `academic_terms`, `classes`, `grade_subjects`, `class_subjects`, `school_locations`, `timetable_periods`, `week_days`, `teacher_availability`, `timetable_entries`.
- الطلاب: `guardians`, `students`, `student_app_accounts`, `student_guardians`, `student_enrollments`, `student_file_transactions`, `student_notes`, `student_file_checklist_templates`, `student_file_checklist_items`.
- الحضور/النتائج: `attendance_statuses`, `student_attendance`, `employee_attendance_statuses`, `assessment_types`, `exams`, `grade_records`, `subject_results`, `term_results`, `grade_bands`.
- الموظفون: `departments`, `job_titles`, `employees`, `employee_document_checklist_items`, `employee_attendance`, `employee_assignments`, `leave_types`, `leave_requests`, `payroll_periods`, `payroll_entries`.
- الرسوم: `fee_types`, `fee_plans`, `fee_plan_items`, `student_fees`, `installments`, `payments`, `finance_receipt_counters`, `employee_number_counters`, `finance_receipts`, `expense_categories`, `expenses`.
- الوثائق/التواصل/الأرشفة: `social_case_categories`, `social_cases`, `social_case_notes`, `document_templates`, `documents`, `document_versions`, `document_approvals`, `completeness_field_rules`, `notifications`, `notification_read_states`, `school_calendar_exceptions`, `announcements`, `archive_records`, `archive_items`, `backup_records`, `retention_policies`, `login_attempts`, `attachments`.
- schema الداخلي: `app.academic_year_closure_authorizations`, `app.student_file_transition_authorizations`.

### 14.3 واجهات API/RPC الأساسية

| الواجهة                     | الوظيفة                                               |
| --------------------------- | ----------------------------------------------------- |
| `student-login`             | تحويل رقم الطالب إلى هوية Auth وتسجيل الدخول.         |
| `student-avatar`            | توقيع صورة للطالب المرتبط بالجلسة.                    |
| `student-app-access`        | إدارة دخول الطلاب أو تسجيل واقعة تسليم بيانات الدخول. |
| `admin-user-management`     | استعراض/إنشاء/إدارة حسابات موظفي المدرسة.             |
| `student_portal_session()`  | هوية موجزة للطالب المرتبط.                            |
| `student_portal_data()`     | إسقاط الملف والحضور والنتائج والرسوم والجدول.         |
| `student_portal_identity()` | الجنس ومراجع الصورة للطالب الحالي.                    |
| `my_session()`              | ملف الموظف وصلاحياته ومدرسته لخدمات الإدارة.          |

### 14.4 سجل الافتراضات والقرارات

- `منفذ` تعني وجود تنفيذ في الملفات المحلية، لا نشرًا أو تشغيلًا حيًا.
- لم تُعتبر أسماء الصفحات أو README دليلًا على الاكتمال؛ قورنت بالتنفيذ، مثل حالة الروابط التعليمية.
- metadata الأرشفة/النسخ الاحتياطي لا يثبت وجود ملف قابل للاستعادة.
- لم توضع أرقام للأداء/التوافر/الامتثال بلا دليل؛ تسجل كمسائل اعتماد.
- لم يُفتح `.env` ولم تُدرج قيم اعتماد في الوثائق.
- لم تُضف مقترحات مستقبلية إلى متطلبات التنفيذ الحالي؛ التوصيات وأسئلة المالك في ملف الفجوات.

## 4. متطلبات واجهة المستخدم

| المعرّف | الشاشة/المكوّن                 | المتطلبات المثبتة                                                                                                                                           |
| ------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| UI-01   | الصفحة العامة                  | عربية RTL؛ أقسام المدرسة، معاينة البوابة، رحلة الاستخدام، المراحل، FAQ، التواصل والتذييل؛ تنقل بالمرساة.                                                    |
| UI-02   | الدخول                         | حقلا رقم الطالب وكلمة المرور، إظهار/إخفاء كلمة المرور، مساعدة، حالة تحميل/خطأ عبر `role=status` و`aria-live`؛ النموذج `novalidate` ولا يتحقق من صيغة الرقم. |
| UI-03   | بوابة الطالب                   | sidebar للشاشة الكبيرة وشريط سفلي/«المزيد» للشاشة الصغيرة؛ تاريخ الجهاز وزر خروج وتواصل.                                                                    |
| UI-04   | الملخص                         | مؤشرات الحضور وحصص اليوم والنتائج والرسوم وحالات فارغة.                                                                                                     |
| UI-05   | الملف والحضور والنتائج والرسوم | أقسام قراءة فقط، إخفاء الحقول الفارغة، حالات غياب البيانات.                                                                                                 |
| UI-06   | الجدول                         | جدول HTML بعناوين وأعمدة ومنطقة قابلة للتمرير أفقيًا ورسائل للصفوف غير القابلة للوضع.                                                                       |
| UI-07   | الروابط التعليمية              | صفحة موجودة لكن حالة فارغة ثابتة؛ لا نموذج لإضافة روابط.                                                                                                    |
| UI-08   | الإدارة                        | لا شاشة إدارة مستخدمين/طلاب/موظفين/رسوم/درجات معروفة في `index.html` أو render functions في `js/app.js`.                                                    |
| UI-09   | التوافق والإتاحة               | media queries و`prefers-reduced-motion` وتسميات ARIA في أجزاء من التطبيق؛ لا إثبات امتثال WCAG أو اختبار إتاحة شامل، ودعم تبويبات لوحة المفاتيح جزئي.       |

## 5. متطلبات الواجهات الخارجية

| الواجهة                 | الاستخدام/العقد المثبت                                                                          | الاعتماد/الملاحظة                                                                       |
| ----------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Supabase Auth           | `signInWithPassword`, حفظ/استعادة/تحديث الجلسات، `setSession`, `signOut` وإدارة مستخدمي الخادم. | يتطلب مشروع Supabase وإعدادات مناسبة؛ لا اختبار حي.                                     |
| Edge Functions          | POST/OPTIONS: `student-login`, `student-avatar`, `student-app-access`, `admin-user-management`. | JSON وBearer بحسب الوظيفة؛ CORS عبر `CORS_ALLOWED_ORIGINS` مع أصول تطوير ثابتة متفاوتة. |
| Postgres RPC/PostgREST  | `student_portal_session`, `student_portal_data`, `student_portal_identity` وغيرها.              | RLS/صلاحيات تنفيذ من migrations؛ الحالة المنشورة غير مفحوصة.                            |
| Supabase Storage        | buckets خاصة `photos`, `documents`, `attachments`; صورة الطالب برابط موقع 600 ثانية.            | migration 007 لا يحدد حدًا للبنية MIME/حجم الملف على bucket.                            |
| مكتبات CDN              | Supabase JS v2 من `esm.sh`، Lucide 0.468.0 من `unpkg`، وTajawal من Google Fonts.                | تتطلب اتصالًا خارجيًا؛ لا إعداد build أو lockfile معروف.                                |
| روابط المستخدم الخارجية | `wa.me`, `tel:`, `mailto:`, Google Maps.                                                        | خارج نطاق التطبيق؛ لا بريد/دفع/رسائل داخلية مثبتة.                                      |

## 6. متطلبات البيانات

### 6.1 النموذج والعلاقات

قاعدة البيانات PostgreSQL في schema `public` وschema داخلي `app`، وتستخدم UUID للمفاتيح غالبًا. العلاقات المحورية: school إلى السنوات والطلاب والموظفين؛ السنة إلى الفصول والفترات والتسجيلات؛ الطالب إلى أولياء الأمور والتسجيلات والحضور والنتائج والرسوم؛ القيد إلى الحضور/النتائج/الرسوم؛ الموظف إلى الحضور والتكليفات والإجازات والرواتب؛ الرسوم إلى الأقساط فالمدفوعات؛ الوثائق إلى الإصدارات والموافقات؛ والأرشيف إلى العناصر. تعريفات FK و`ON DELETE` والحقول nullable/default موضحة في `001_extensions.sql` وتعديلات migrations اللاحقة.

### 6.2 قاموس البيانات

الأنواع المختصرة: `uuid`, `text`, `bool`, `int`, `smallint`, `bigint`, `numeric(p,s)`, `date`, `time`, `timestamptz`, `jsonb`, `text[]`. الجدول التالي يصف الحقول المحورية ذات الصلة بالتدفقات والقيود، وليس بديلًا عن تعريف كل عمود في migration 001؛ يُرجع إليه للمجموعة الكاملة والـnull/default والقيود. لا تسقط الترحيلات أعمدة توافق قديمة عند تلخيص المجال.

| الجدول/المجموعة                                                                                    | الحقول المحورية وأنواعها                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schools`                                                                                          | `id uuid PK`; الاسم والعنوان والاتصال والشعار `text`; العملة `text`; timestamps.                                                                                                                    |
| `school_settings`                                                                                  | `id smallint PK=1`, `school_id uuid FK`; بيانات المدرسة `text`; حدود الرفع/الاحتفاظ `int`; `week_start_day smallint`, `photo_max_px int`, `version int`, timestamps.                                |
| `profiles`                                                                                         | `id uuid PK/FK auth.users`, `school_id/employee_id uuid`; username/email/name/phone/role/status `text`; `must_change_password bool`; login timestamps/version.                                      |
| `permissions`, `user_permissions`                                                                  | permission key `text PK`; user/granter `uuid`; permission `text FK`; `granted_at timestamptz`.                                                                                                      |
| `audit_logs`                                                                                       | `id bigint identity PK`; actor/user/school/year IDs; action/entity `text`; old/new/metadata `jsonb`; timestamps.                                                                                    |
| `idempotency_keys`                                                                                 | `key/operation/status/hash text`; `actor_id uuid`; `result jsonb`; timestamps.                                                                                                                      |
| `schema_version`                                                                                   | `id smallint PK=1`; schema/app version `text`; applied time.                                                                                                                                        |
| `academic_years`                                                                                   | IDs المدرسة `uuid`; `code/label/name/status text`; start/end `date`; `is_current bool`; closed timestamp/version.                                                                                   |
| `academic_stages`, `school_grades`, `subjects`                                                     | معرفات `uuid`; code/name `text`; مستوى/ترتيب `smallint/int`; flags `bool`; version/timestamps؛ grade `code` و`level_number` عالميّا unique.                                                         |
| `academic_terms`, `classes`                                                                        | year/grade/class/employee IDs `uuid`; dates `date`; term/roll/capacity `smallint/int`; room/section/name `text`; flags/version/timestamps.                                                          |
| `grade_subjects`, `class_subjects`                                                                 | year/grade/subject/class/employee IDs `uuid`; scores/weights `numeric`; weekly periods `smallint`; flags/version؛ coursework+final=100.                                                             |
| `guardians`, `students`                                                                            | الأسماء/الاتصال/الحالات `text`; DOB/registration/graduation `date`; `health_conditions/disability_needs text[]`; flags login/archive/delinquent `bool`; مسارات الصور `text`; `student_number` فريد. |
| `student_app_accounts`                                                                             | `student_id uuid PK/FK`, `school_id/auth_user_id uuid`; `login_email text unique`; enabled/delivery flags `bool`; issue/create/update timestamps.                                                   |
| `student_guardians`, `student_enrollments`                                                         | روابط `uuid`; relationship/status/outcome `text`; dates; roll number `smallint`; new/repeat/primary flags `bool`; unique student/year.                                                              |
| `student_file_transactions`, `student_notes`, `student_file_checklist_templates/items`             | student/template/actor UUIDs؛ نصوص note/reason/path/MIME؛ تواريخ؛ sensitivity/received/required/active flags؛ file size `bigint`.                                                                   |
| `attendance_statuses`, `student_attendance`, `employee_attendance_statuses`, `employee_attendance` | code/status `text`; student/enrollment/employee/class UUIDs؛ attendance date `date`; check-in/out `time`; late `smallint`; flags present/excused/paid؛ unique enrollment/date وemployee/date.       |
| `assessment_types`, `exams`, `grade_records`                                                       | school/year/class/grade/subject/exam UUIDs؛ title/status `text`; exam date `date`; max/score/weight `numeric`; absent `bool`; status/round enums/version.                                           |
| `subject_results`, `term_results`, `grade_bands`                                                   | enrollment/subject/year UUIDs؛ scores/percentage `numeric`; round/decision/status enums؛ failed subjects/rank `smallint`; rules `jsonb`; calculation/approval times.                                |
| `departments`, `job_titles`, `employees`                                                           | IDs UUID؛ الاسم/الرقم/الاتصال/المؤهل `text`; dates؛ salary `numeric(12,2)`؛ status enum؛ teacher/archive flags؛ version/timestamps.                                                                 |
| `employee_document_checklist_items`, `employee_assignments`                                        | employee/class-subject/year UUIDs؛ item/role_note `text`; received date؛ periods `smallint`; received/active `bool`; version/timestamps.                                                            |
| `leave_types`, `leave_requests`                                                                    | employee/type/reviewer UUIDs؛ start/end `date`; generated `days_count int`; status enum؛ entitlements `int`; reason/review/document `text`; version.                                                |
| `payroll_periods`, `payroll_entries`                                                               | school/period/employee UUIDs؛ year `int`, month `smallint`, dates؛ amounts `numeric(12,2)`؛ generated net salary؛ status enum/version.                                                              |
| `fee_types`, `fee_plans`, `fee_plan_items`                                                         | school/year/grade/type UUIDs؛ code/name/gender scope `text`; amount `numeric(14,2)`؛ due date؛ installment count `smallint`; active/mandatory flags.                                                |
| `student_fees`, `installments`, `payments`, `finance_receipts`                                     | enrollment/student/installment/school/payment UUIDs؛ amounts `numeric(14,2)`؛ date؛ status/method enums؛ receipt text؛ snapshot `jsonb`; generated net/remaining؛ idempotency unique.               |
| `finance_receipt_counters`, `employee_number_counters`                                             | ID/school UUIDs؛ `last_number bigint`; `updated_at`.                                                                                                                                                |
| `expense_categories`, `expenses`                                                                   | category/school/year/actor UUIDs؛ amount `numeric(14,2)`؛ date؛ description/status/method `text`; flags.                                                                                            |
| `timetable_periods`, `week_days`, `teacher_availability`, `timetable_entries`, `school_locations`  | IDs UUID؛ day/period/order `smallint/int`; start/end `time`; names/room `text`; active flags/version؛ entry links class/period/employee/subject/location.                                           |
| `social_case_categories`, `social_cases`, `social_case_notes`                                      | student/year/actor/case UUIDs؛ priority/status enums؛ summary/note `text`; opened/closed/followup dates؛ version.                                                                                   |
| `document_templates`, `documents`, `document_versions`, `document_approvals`                       | document/template/version/actor UUIDs؛ content `text/jsonb`; category/status enums؛ version no `int`; file size `bigint`; hash/MIME/path `text`; approval bool.                                     |
| `completeness_field_rules`                                                                         | `id/school_id uuid`; entity/record/field/label/importance `text`.                                                                                                                                   |
| `notifications`, `notification_read_states`, `announcements`                                       | UUIDs؛ title/body/category `text`; type/audience/importance enums؛ read/pinned flags؛ timestamps؛ read-state PK `(school_id,user_id,notification_key)`.                                             |
| `school_calendar_exceptions`                                                                       | school/year UUIDs؛ dates/ranges؛ kind/type/title `text`; school-day flag؛ unique school/year/date.                                                                                                  |
| `archive_records`, `archive_items`, `backup_records`, `retention_policies`                         | school/year/archive UUIDs؛ state/status/type `text/enum`; manifest `jsonb`; checksum/path `text`; item count `int`, sizes `bigint`; retention days `int`; timestamps.                               |
| `login_attempts`                                                                                   | `id bigint identity`; hashed login key `text`; attempted time; blocked `bool`.                                                                                                                      |
| `attachments`                                                                                      | id/school UUIDs؛ entity/bucket/path/MIME/name `text`; size `bigint`; uploader UUID؛ deleted bool/version int/metadata jsonb.                                                                        |
| `app.academic_year_closure_authorizations`, `app.student_file_transition_authorizations`           | transaction `bigint`; year/student/actor UUIDs؛ target status text؛ composite PK؛ privileges revoked from ordinary roles.                                                                           |

### 6.3 القيود ودورة الحياة

- مفاتيح UUID وFKs مع سياسات `RESTRICT`, `CASCADE`, `SET NULL` بحسب تعريف كل جدول؛ لا توجد سياسة حذف موحدة.
- enrollment فريد `(student_id, academic_year_id)`؛ حضور الطالب فريد enrollment/date؛ الدرجات ونتائج المواد فريدة وفق exam/enrollment أو enrollment/grade_subject/round.
- `app.money_amount` غير سالب و`app.percentage` بين 0 و100؛ المبالغ المالية وبعض الصافي/المتبقي أعمدة generated.
- triggers تحدث timestamps، تدقق تغييرات محددة، تمنع الحذف النهائي لكيانات مختارة، وتحمي عمليات سحب الطالب وإغلاق السنة وعدم تغيير أعمدة دفعة محددة.
- يوجد seed للمدرسة والسنوات والتقويم والمراحل والمواد وغيرها في `005_seed.sql`؛ لا ينشئ حساب مدير أو كلمة مرور.
- لا يوجد استيراد/تصدير عام بالواجهة. `record-export` لا ينشئ ملفًا. metadata الأرشيف/النسخ لا تثبت إنشاء نسخة خارجية قابلة للاستعادة.

## 7. المتطلبات غير الوظيفية

| المعرّف | المتطلب/الحقيقة القابلة للتحقق                                                                                                            | المصدر                                                            | الحالة/الاعتماد المطلوب                                                      |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| NFR-001 | الواجهة تضبط `lang=ar` و`dir=rtl`.                                                                                                        | `index.html`                                                      | منفذ؛ اختبار كل الصفحات مطلوب.                                               |
| NFR-002 | الواجهة تتكيف مع الشاشات الصغيرة؛ التنقل السفلي حتى 1024px يراعي safe-area.                                                               | `css/student-portal.css`                                          | CSS موجود؛ توافق المتصفحات يحتاج اختبارًا.                                   |
| NFR-003 | احترام `prefers-reduced-motion`؛ Parallax لا يعمل عند تفضيل تقليل الحركة أو غياب مؤشر دقيق.                                               | `js/app.js`, `css/*.css`                                          | منفذ جزئيًا؛ لا قياس أداء بصري.                                              |
| NFR-004 | نصوص البيانات المحولة تهرب HTML قبل تركيب قوالب الواجهة.                                                                                  | `js/student-portal-data.mjs:escapeHTML`                           | مثبت في mapper؛ اختبار أمني لبقية المخرجات مطلوب.                            |
| NFR-005 | لا يرسل المتصفح مفتاح service-role؛ عميل Supabase يرفض المفتاح المعروف كخدمة ويستخدم المفتاح العام.                                       | `js/supabase-client.js`, Edge Functions                           | حاجز كودي موجود؛ مراجعة أسرار النشر خارج الفحص.                              |
| NFR-006 | هوية الطالب مصدرها `auth.uid()` وربط خاص؛ لا direct access لجداول الطالب/الربط عبر مسار البوابة.                                          | `006_security_hardening.sql`, `008_student_portal_projection.sql` | مثبت في migrations محليًا؛ تطبيقها الحي غير متحقق.                           |
| NFR-007 | RLS/Edge Functions تقيد البيانات بحسب المدرسة/الصلاحيات وتتحقق من bearer/session.                                                         | `004_rls.sql`, Edge Functions                                     | تنفيذ محلي؛ يتطلب اختبار صلاحيات على بيئة مصرح بها، ولا يثبت امتثال معيار.   |
| NFR-008 | توقيع صورة الطالب مؤقت لعشر دقائق ويتحقق من هوية المستخدم والمسار/المشروع.                                                                | `student-avatar/index.ts`                                         | بالكود؛ لم يختبر Storage حيًا.                                               |
| NFR-009 | طلبات البوابة محدودة بمهلة 15 ثانية مع رسائل حالة مفهومة.                                                                                 | `js/app.js:withRequestTimeout`                                    | يطبق على الطلبات المشار إليها؛ `auth.setSession()` بلا مهلة صريحة؛ ليست SLA. |
| NFR-010 | سجلات audit قابلة للقراءة بصلاحية `audit.view` وكتابة العميل المباشرة ممنوعة.                                                             | migrations 001/003/004/006                                        | إعداد مخطط موجود؛ لا إثبات لمراقبة/تنبيه تشغيلية أو retention job.           |
| NFR-011 | واجهة الطالب للقراءة ولا توفر تعديل/دفع.                                                                                                  | `js/app.js`                                                       | منفذ للتطبيق الحالي.                                                         |
| NFR-012 | لا توجد حدود موثقة لزمن الاستجابة العام أو عدد المستخدمين أو التوافر.                                                                     | لا يوجد SLA/قياس معروف                                            | يتطلب قياسًا واعتمادًا؛ لا تُخترع أرقام.                                     |
| NFR-013 | لا يوجد إعداد موثق لنسخ احتياطي مجدول أو استعادة مجربة أو RPO/RTO.                                                                        | migrations تحفظ metadata                                          | يتطلب تحققًا تشغيليًا؛ الجداول لا تثبت التعافي.                              |
| NFR-014 | تحميل الخطوط والمكتبات يعتمد على CDN ولا يوجد تثبيت/بناء محلي ظاهر.                                                                       | `index.html`, `js/supabase-client.js`                             | مثبت؛ اعتماد الخدمة وسياسة الخصوصية/التوفر قرار أصحاب المصلحة.               |
| NFR-015 | الاستخدام بلوحة المفاتيح وقارئ الشاشة يجب دعمه؛ توجد ARIA و`dialog` لكن اختبار WCAG شامل غير موجود والتبويبات لا تدعم أسهم لوحة المفاتيح. | `js/app.js`, اختبار CSS                                           | دعم جزئي؛ يحتاج تقييم إتاحة واعتماد مستوى المطابقة.                          |

## 8. قواعد العمل

| المعرّف | القاعدة                                                                                         | المصدر                                                                                 |
| ------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| BR-001  | الدخول يتطلب حساب Auth مربوطًا ومفعّلًا وسجل طالب مفعّلًا غير مسحوب/مؤرشف.                      | `002_functions.sql:resolve_login_email/current_student_portal_id`                      |
| BR-002  | RPC البوابة لا يقبل UUID طالب من المتصفح؛ يحل هوية الطالب من Auth.                              | `002_functions.sql`, `006_security_hardening.sql`, `008_student_portal_projection.sql` |
| BR-003  | الإسقاط يختار قيدًا نشطًا غير منسحب، مع أولوية العام الحالي ثم تاريخ القيد الأحدث.              | `008_student_portal_projection.sql`                                                    |
| BR-004  | النتائج التي تظهر للطالب مرتبطة بحالة `approved` أو `closed`.                                   | `008_student_portal_projection.sql`                                                    |
| BR-005  | تعرض أحدث 20 سجل حضور؛ mapper لا يعيد الترتيب.                                                  | `008_student_portal_projection.sql`, `js/student-portal-data.mjs`                      |
| BR-006  | قيمة الرسوم المدفوعة تستند لمجموع الأقساط، والمتبقي لا يقل عن صفر.                              | `008_student_portal_projection.sql`                                                    |
| BR-007  | لا ينشأ enrollment/حضور/درجة/رسم جديد لطالب مسحوب.                                              | `002_functions.sql`, `003_triggers.sql`                                                |
| BR-008  | التحول إلى/من `withdrawn` يتطلب RPC مخولًا ويسجل أثرًا.                                         | `withdraw_student_file`, `restore_student_file`, triggers                              |
| BR-009  | لا تنشأ سنة مغلقة مباشرة ولا يعاد فتح سنة مغلقة؛ يلزم إجراء معتمد.                              | `002_functions.sql`, `003_triggers.sql`                                                |
| BR-010  | مجموع أوزان coursework والامتحان النهائي يساوي 100 ودرجة المادة القصوى موجبة.                   | `001_extensions.sql`                                                                   |
| BR-011  | حضور الطالب فريد للقيد/التاريخ، ونتائج المادة للقيد/المادة/الدور.                               | `001_extensions.sql`                                                                   |
| BR-012  | الدفعة موجبة، ولا تعدل amount/installment/date بعد التسجيل ولا تحذف نهائيًا.                    | `001_extensions.sql`, `003_triggers.sql`                                               |
| BR-013  | سحب الطالب يعطل تسجيل الدخول؛ status وحده لا ينشئ mapping/Auth صالحًا.                          | `002_functions.sql`, `003_triggers.sql`, `student-app-access/index.ts`                 |
| BR-014  | إدارة دخول الطلاب تقبل 1–50 UUID وحالات active/reset_required/disabled وتستبعد المسحوب/المؤرشف. | `student-app-access/index.ts`                                                          |
| BR-015  | `record-export` يوثق عملية تسليم ويمسح pending؛ لا ينشئ ملفًا.                                  | `student-app-access/index.ts`                                                          |

### 3.3 وظائف خلفية دون واجهة إدارية ظاهرة

#### FR-018 — استعراض مستخدمي المدرسة وموظفيها

| الحقل                  | الوصف                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | مستخدم نشط بدور admin أو صلاحية `users.view`؛ إجراءات الإدارة تتطلب `users.manage`.                           |
| الشروط المسبقة         | POST إلى `admin-user-management` مع Bearer صالح و`my_session()` نشط ومدرسة محددة.                             |
| التدفق الأساسي         | `list-users`, `get-user`, `list-employees` تعيد الملفات والصلاحيات والموظف المرتبط أو الموظفين غير المؤرشفين. |
| البدائل/الفشل          | يرفض الأصل أو الجلسة أو المدرسة أو الصلاحية غير الصالحة؛ أخطاء 400/401/403/404/500.                           |
| المدخلات/المخرجات      | `action` وعند الحاجة `user_id` → بيانات مقيدة بـ`school_id`.                                                  |
| قواعد العمل والصلاحيات | التحقق Auth ثم `my_session()`؛ لا يوجد مستهلك UI معروف في المشروع.                                            |
| المصدر                 | `supabase/functions/admin-user-management/index.ts`, `002_functions.sql:my_session`, `004_rls.sql`.           |
| الحالة                 | منفذ خادميًا جزئيًا؛ لا واجهة ولا اختبار تكاملي معروف.                                                        |
| معيار القبول           | طلب مصرح يعيد سجلات المدرسة فقط؛ مستخدم بلا صلاحية يتلقى 403.                                                 |

#### FR-019 — إنشاء مستخدم إداري أو موظف

| الحقل                  | الوصف                                                                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | admin أو `users.manage`؛ إنشاء دور admin للـadmin فقط.                                                                                                |
| الشروط المسبقة         | جلسة نشطة؛ username والاسم والبريد وكلمة مؤقتة.                                                                                                       |
| التدفق الأساسي         | يتحقق من البريد والدور والحالة وكلمة المرور (8 أحرف فأكثر) وربط الموظف؛ ينشئ Auth ثم `create_managed_user_profile` ويحاول حذف Auth عند فشل حفظ الملف. |
| البدائل/الفشل          | يرفض البريد/اسم المستخدم المكرر أو الموظف غير الصالح؛ يعيد أخطاء Auth/RPC.                                                                            |
| المدخلات/المخرجات      | ملف المستخدم وربط موظف اختياري → `user_id` أو خطأ.                                                                                                    |
| قواعد العمل والصلاحيات | الأدوار admin/staff/employee والحالات active/inactive/suspended/terminated؛ ليست العملية ذرية عبر Auth وDB.                                           |
| المصدر                 | `admin-user-management/index.ts:createUser`, `002_functions.sql:create_managed_user_profile`, `006_security_hardening.sql`.                           |
| الحالة                 | تنفيذ خادمي جزئي؛ غير متحقق تكامليًا.                                                                                                                 |
| معيار القبول           | اختبار الخادم يثبت التحقق والتراجع التعويضي عند فشل إنشاء profile.                                                                                    |

#### FR-020 — تحديث صلاحيات المستخدم وكلمة مروره وحذفه

| الحقل                  | الوصف                                                                                                                                                                          |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | admin أو `users.manage`؛ إدارة حساب admin للـadmin فقط.                                                                                                                        |
| الشروط المسبقة         | جلسة نشطة وهدف ضمن مدرسة الفاعل.                                                                                                                                               |
| التدفق الأساسي         | `update-access` يستدعي `admin_set_user_access` مع النسخة المتوقعة؛ reset يطلب كلمة مؤقتة ≥8 ويعلّم تغييرها؛ force-password-change يسجل الطلب؛ delete يمنع الذات وآخر مدير نشط. |
| البدائل/الفشل          | رفض صلاحيات/هدف مفقود/تعارض/خطأ Auth؛ حذف Auth يسبق التدقيق وقد يفشل التدقيق بعد الحذف.                                                                                        |
| المدخلات/المخرجات      | action, user_id, الدور/الحالة/الصلاحيات/النسخة أو كلمة مؤقتة → حالة العملية.                                                                                                   |
| قواعد العمل والصلاحيات | لا تعاد كلمة المرور في الرد؛ عمليات Auth وDB غير ذرية كليًا.                                                                                                                   |
| المصدر                 | `admin-user-management/index.ts:updateAccess/deleteUser/resetPassword/forcePasswordChange`, `002_functions.sql`, `006_security_hardening.sql`.                                 |
| الحالة                 | منفذ جزئيًا في الخادم؛ لا واجهة إدارية معروفة.                                                                                                                                 |
| معيار القبول           | اختبار يمنع حذف الذات/آخر مدير ويتحقق من معالجة الفشل الجزئي والتدقيق.                                                                                                         |

#### FR-021 — إدارة دخول الطلاب وتسجيل التسليم

| الحقل                  | الوصف                                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | admin أو `students.manage`/`students.edit` في المدرسة الحالية.                                                                                                           |
| الشروط المسبقة         | Bearer صالح و`my_session()` نشط؛ من 1 إلى 50 UUID طالب.                                                                                                                  |
| التدفق الأساسي         | `manage-accounts` يدير الحالات active/reset_required/disabled ويحدث Auth والربط والحالة والتدقيق. `record-export` يتحقق من التسليم المعلق ثم يسجل الواقعة ويستهلك العلم. |
| البدائل/الفشل          | استبعاد المسحوب/المؤرشف؛ نتائج لكل سجل وفشل خارجي؛ عمليات Auth/DB تعويضية وليست معاملة ذرية.                                                                             |
| المدخلات/المخرجات      | action/kind=student/ids/status أو student_ids → سجلات واعتمادات مؤقتة عند إصدارها، أو `{recorded:true}`.                                                                 |
| قواعد العمل والصلاحيات | كلمة مؤقتة ستة أرقام؛ record-export لا ينشئ ملفًا ولا يولّد بيانات دخول.                                                                                                 |
| المصدر                 | `supabase/functions/student-app-access/index.ts`, `002_functions.sql:update_student_app_login_status/student_app_access_account_statuses`, `006_security_hardening.sql`. |
| الحالة                 | منفذ خادمي جزئي؛ لا شاشة إدارة أو اختبار تكاملي معروف.                                                                                                                   |
| معيار القبول           | إثبات حد 50 ورفض المسحوب وتسجيل التدقيق وعدم الادعاء بإنشاء ملف.                                                                                                         |

#### FR-022 — إدارة ملفات الطلاب والقيود والتحولات

| الحقل                  | الوصف                                                                                                                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | موظف بصلاحيات `students.create/edit/archive/enrollment.manage`.                                                                                                                                       |
| الشروط المسبقة         | هوية موظف نشطة ومدرسة حالية؛ RPC مخول.                                                                                                                                                                |
| التدفق الأساسي         | توجد `save_student_profile`, `register_student_enrollment`, `promote_class`, `withdraw_student_file`, `restore_student_file`, `graduate_student` ودوال اكتمال الملف؛ السحب يعطل الدخول ويسجل التدقيق. |
| البدائل/الفشل          | تحقق حقول/عمر/تكرار الطلب، طالب مفقود أو مسحوب؛ trigger يمنع عمليات دراسية جديدة لطالب مسحوب.                                                                                                         |
| المدخلات/المخرجات      | JSON الملف/الأولياء/القائمة أو معرف الطالب والسبب → حفظ أو انتقال موثق.                                                                                                                               |
| قواعد العمل والصلاحيات | رقم الطالب واسم الطالب/العائلة وتاريخ التسجيل مطلوبة للإنشاء؛ DOB لا مستقبل ولا عمر أقل من 3 أو أكبر من 30؛ الانتقال إلى/من withdrawn عبر RPC؛ الحذف النهائي محظور.                                   |
| المصدر                 | `002_functions.sql`, `003_triggers.sql`, `004_rls.sql`, `006_security_hardening.sql`.                                                                                                                 |
| الحالة                 | RPC/قيود موجودة؛ تكامل واجهة الإدارة والبيانات الحية غير متحقق منه.                                                                                                                                   |
| معيار القبول           | اختبار DB يثبت التفويض وidempotency ومنع التحول المباشر والحذف النهائي.                                                                                                                               |

#### FR-023 — الحضور والتقييم والنتائج للموظفين

| الحقل                  | الوصف                                                                                                                                                                 |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | موظف بصلاحيات `attendance.*`, `grades.*`, `results.*`؛ الطالب قارئ للإسقاط.                                                                                           |
| الشروط المسبقة         | قيد/عام/فصل/اختبار صحيح والصلاحيات مطابقة.                                                                                                                            |
| التدفق الأساسي         | RPCs تشمل `save_class_attendance`, `save_employee_attendance`, `save_exam_grades`, `approve_exam_grades`, `calculate_term_result`, `approve_class_results` والتقارير. |
| البدائل/الفشل          | قيود تمنع تكرار الحضور/التاريخ والدرجة/الاختبار/القيد؛ أنواع الحالات enums؛ تمنع عملية لطالب مسحوب.                                                                   |
| المدخلات/المخرجات      | معرفات صف/اختبار/قيد وبيانات → حفظ/اعتماد/نتيجة/تقرير.                                                                                                                |
| قواعد العمل والصلاحيات | أوزان المادة مجموعها 100؛ البوابة تعرض approved/closed فقط. `calculate_subject_result()` placeholder يعيد مدخلاته ولا يحسب نتيجة فعلية.                               |
| المصدر                 | `002_functions.sql`, `001_extensions.sql`, `003_triggers.sql`, `004_rls.sql`, `006_security_hardening.sql`.                                                           |
| الحالة                 | تنفيذ خلفي جزئي؛ بعض الحساب placeholder؛ لا واجهة أو اختبار DB معروف.                                                                                                 |
| معيار القبول           | اختبار DB يثبت الصلاحيات والانتقالات ومعادلات يعتمدها مالك النظام، وليس مجرد وجود الدالة.                                                                             |

#### FR-024 — الرسوم والمدفوعات والمصروفات

| الحقل                  | الوصف                                                                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | موظف مالي بصلاحيات `finance.*`؛ الطالب للقراءة فقط.                                                                                      |
| الشروط المسبقة         | رسوم/قسط/دفعة ضمن المدرسة وصلاحية مالية.                                                                                                 |
| التدفق الأساسي         | RPCs تنشئ الرسوم والأقساط والمدفوعات وتعكسها وتعرض الملخص وتحدث المتأخرات وتدير المصروفات؛ مسار دفع ذري يحدّث الأقساط والإيصال والتدقيق. |
| البدائل/الفشل          | قيود ترفض مبالغ غير صالحة؛ إيصال/idempotency فريدان؛ trigger يمنع تعديل مبلغ/قسط/تاريخ الدفعة والحذف.                                    |
| المدخلات/المخرجات      | خطة/رسوم/قسط/طريقة/مبلغ/تاريخ → حالة مالية وإيصال/تدقيق.                                                                                 |
| قواعد العمل والصلاحيات | RLS يسمح ببعض direct insert/update المالية وقد تتجاوز مسار RPC الذري والإيصال والتدقيق.                                                  |
| المصدر                 | `002_functions.sql`, `001_extensions.sql`, `003_triggers.sql`, `004_rls.sql`, `006_security_hardening.sql`.                              |
| الحالة                 | وظائف خلفية مع فجوة ضمان؛ تكامل العمليات الحية غير متحقق منه.                                                                            |
| معيار القبول           | اختبار معاملة يثبت اتساق الرصيد والإيصال والتدقيق وعدم التكرار؛ مراجعة direct-write.                                                     |

#### FR-025 — الهيكل الأكاديمي والجدول والموظفون والإجازات والرواتب

| الحقل                  | الوصف                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | موظف بصلاحيات الهيكل/الجدول/الموظفين/الإجازات/الرواتب.                                                                                      |
| الشروط المسبقة         | سنة ومدرسة ومراجع موظف/صف/فترة صحيحة.                                                                                                       |
| التدفق الأساسي         | RPCs لنسخ/إغلاق السنة، إدارة الحصص والتكليفات، الموظفين وحضورهم، الإجازات، وإنشاء/اعتماد الرواتب.                                           |
| البدائل/الفشل          | trigger يمنع فصل/فترة من سنة مختلفة في الكتابات الجديدة؛ يرفض الإجازات المعتمدة المتداخلة؛ أيام الإجازة وصافي الراتب generated.             |
| المدخلات/المخرجات      | بنية سنة/صف/فترة أو بيانات موظف/طلب → حالة/جدول/مبلغ.                                                                                       |
| قواعد العمل والصلاحيات | صلاحيات إدارة واعتماد منفصلة؛ سياسات leave_requests تمنع الكتابة المباشرة. قيود timetable المركبة NOT VALID لا تثبت صحة البيانات التاريخية. |
| المصدر                 | `002_functions.sql`, `001_extensions.sql`, `003_triggers.sql`, `004_rls.sql`, `006_security_hardening.sql`.                                 |
| الحالة                 | تنفيذ خلفي جزئي؛ لا دليل على واجهة لهذه العمليات أو نشرها.                                                                                  |
| معيار القبول           | اختبارات DB تتحقق من تطابق السنة وتداخل الإجازة وصلاحية الإغلاق واعتماد الرواتب.                                                            |

#### FR-026 — الوثائق والحالات الاجتماعية والإعلانات والتنبيهات والأرشفة

| الحقل                  | الوصف                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | موظف يملك صلاحية المجال؛ لا واجهة طالب لهذه العمليات.                                                                                       |
| الشروط المسبقة         | حساب نشط ومدرسة/كيان وصلاحية مطابقة.                                                                                                        |
| التدفق الأساسي         | المخطط والدوال توفر إصدارات/اعتمادات الوثائق، حالات اجتماعية، إعلانات، علامات قراءة، أرشفة/تحقق/استعادة وmetadata للنسخ الاحتياطي والتدقيق. |
| البدائل/الفشل          | metadata لا يثبت إنشاء/استعادة ملف؛ دوال mark notification أعيد تعريف بعضها لاحقًا؛ لا شاشة لهذه المجالات في الواجهة الحالية.               |
| المدخلات/المخرجات      | RPC/سجل مرتبط → metadata وحالة/تدقيق؛ ملفات عبر Storage الخاص عند استدعاء التدفق.                                                           |
| قواعد العمل والصلاحيات | ضوابط RLS تختلف حسب المجال؛ لا يوجد دليل على اكتمال دورة التخزين/التنزيل/الإشعار.                                                           |
| المصدر                 | `001_extensions.sql`, `002_functions.sql`, `004_rls.sql`, `006_security_hardening.sql`, `007_storage.sql`.                                  |
| الحالة                 | غير متحقق منه تشغيليًا؛ schema/RPC موجودان ولا واجهة في التطبيق.                                                                            |
| معيار القبول           | اختبار تكاملي لكل workflow يثبت التفويض والتخزين/الاستعادة والتدقيق وعدم إعلان النجاح بلا artifact.                                         |

<!-- متابعة متطلبات SRS -->

#### FR-010 — عرض الحضور

| الحقل                  | الوصف                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | الطالب المرتبط.                                                                                        |
| الشروط المسبقة         | تحميل سجلات الحضور في الإسقاط.                                                                         |
| التدفق الأساسي         | يعرض ملخص الحضور/التأخر/الغياب والنسبة، ثم حتى 20 سجلًا من الأحدث إلى الأقدم وفق SQL.                  |
| البدائل/الفشل          | غياب السجلات يعرض حالة فارغة؛ غياب النسبة أو السجلات يعرض انتظار أول سجل.                              |
| المدخلات/المخرجات      | `attendance`, `records[]` → أرقام وقائمة تواريخ وحالات.                                                |
| قواعد العمل والصلاحيات | النسبة محسوبة في `student_portal_data()`؛ تحويل الواجهة لا يعيد ترتيب القائمة.                         |
| المصدر                 | `008_student_portal_projection.sql`, `js/student-portal-data.mjs`, `js/app.js:renderPortalPageMarkup`. |
| الحالة                 | منفذ.                                                                                                  |
| معيار القبول           | لا يتجاوز الإسقاط 20 سجلًا وتطابق القائمة ترتيب SQL؛ اختبار المصدر الحي مطلوب.                         |

#### FR-011 — عرض النتائج المعتمدة

| الحقل                  | الوصف                                                                                        |
| ---------------------- | -------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | الطالب المرتبط.                                                                              |
| الشروط المسبقة         | نتيجة المادة مرتبطة بقيد الطالب ونتيجة الفصل حالتها `approved` أو `closed`.                  |
| التدفق الأساسي         | يعرض اسم المادة والنسبة والتقدير؛ الملخص يعرض أول أربع مواد.                                 |
| البدائل/الفشل          | لا توجد نتيجة مؤهلة: حالة فارغة؛ قد يكون التقدير `—` عند غياب نطاق مطابق.                    |
| المدخلات/المخرجات      | `subject_results` مع `term_results` → عناصر نتيجة مرتبة حسب المادة.                          |
| قواعد العمل والصلاحيات | شرط الاعتماد مفروض في SQL؛ الواجهة لا تعيد فحص حالة الاعتماد.                                |
| المصدر                 | `008_student_portal_projection.sql`, `js/app.js:renderPortalHome`, `renderPortalPageMarkup`. |
| الحالة                 | منفذ.                                                                                        |
| معيار القبول           | لا تظهر نتيجة مسودة وتظهر النتيجة المعتمدة/المغلقة للطالب المرتبط فقط.                       |

#### FR-012 — عرض الرسوم والمستحقات

| الحقل                  | الوصف                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | الطالب المرتبط.                                                                                        |
| الشروط المسبقة         | وجود رسوم مرتبطة بقيد مؤهل.                                                                            |
| التدفق الأساسي         | يعرض كل بند إجماليه ومدفوعه ومتبقيه وحالته، ويجمع المبالغ في الملخص بعملة LYD.                         |
| البدائل/الفشل          | غياب البنود يعرض حالة فارغة؛ القيم المفقودة تتحول إلى صفر عند التطبيع.                                 |
| المدخلات/المخرجات      | رسوم القيد ومجموع `installments.paid_amount` → تفاصيل ومجاميع للقراءة.                                 |
| قواعد العمل والصلاحيات | لا دفع أو تعديل أو إصدار إيصال في واجهة الطالب؛ حالة السداد تحسب في الإسقاط.                           |
| المصدر                 | `008_student_portal_projection.sql`, `js/student-portal-data.mjs`, `js/app.js:renderPortalPageMarkup`. |
| الحالة                 | منفذ.                                                                                                  |
| معيار القبول           | تقارن المجاميع المعروضة ببيانات الاختبار المعروفة دون إنشاء عملية دفع.                                 |

#### FR-013 — عرض الجدول الدراسي

| الحقل                  | الوصف                                                                                                                   |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | الطالب المرتبط.                                                                                                         |
| الشروط المسبقة         | قيد مرتبط بفصل وسنة وجدول نشط.                                                                                          |
| التدفق الأساسي         | الإسقاط يربط الحصص بفصل وسنة القيد ويرجع اليوم والفترة والمادة والمعلم والمكان؛ الواجهة تعرض شبكة وأجندة اليوم.         |
| البدائل/الفشل          | لا حصص: حالة فارغة؛ اليوم/الفترة غير الصالحين لا يوضعان في الشبكة ويصدر تحذير؛ المادة الناقصة لا تستبدل بمعلومة مخترعة. |
| المدخلات/المخرجات      | صفوف الجدول وقائمة الأيام → شبكة قابلة للتمرير أفقيًا وأجندة اليوم.                                                     |
| قواعد العمل والصلاحيات | الحصص النشطة للقيد/السنة فقط، وترتب باليوم ثم رقم الفترة؛ اليوم وفق ساعة الجهاز.                                        |
| المصدر                 | `008_student_portal_projection.sql`, `js/student-portal-data.mjs:mapPortalData/buildTimetableGrid`, `js/app.js`.        |
| الحالة                 | منفذ.                                                                                                                   |
| معيار القبول           | اختبار بيانات مكتملة يطابق الشبكة؛ البيانات الناقصة لا تنشئ يومًا/مادة افتراضية.                                        |

#### FR-014 — قسم الروابط التعليمية

| الحقل                  | الوصف                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | الطالب المرتبط.                                                                             |
| الشروط المسبقة         | دخول ناجح.                                                                                  |
| التدفق الأساسي         | يفتح قسم «روابطي التعليمية».                                                                |
| البدائل/الفشل          | يعرض دائمًا «لا توجد روابط تعليمية مهيأة»؛ mapper يعيد `platforms: []` ولا يوجد مصدر روابط. |
| المدخلات/المخرجات      | لا مدخل عملي → حالة فارغة ثابتة.                                                            |
| قواعد العمل والصلاحيات | وجود الصفحة لا يعني تكامل منصات خارجية.                                                     |
| المصدر                 | `js/student-portal-data.mjs:mapPortalData`, `js/app.js:renderPortalPageMarkup`.             |
| الحالة                 | منفذ جزئيًا (واجهة فقط).                                                                    |
| معيار القبول           | يؤكد فحص الكود الحالة الفارغة؛ عرض روابط فعلية يتطلب مصدر إعداد غير موجود.                  |

#### FR-015 — إثراء صورة الطالب

| الحقل                  | الوصف                                                                                                                           |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | طالب مصادق ومرتبط.                                                                                                              |
| الشروط المسبقة         | نجاح بيانات البوابة؛ قد يوجد مرجع صورة.                                                                                         |
| التدفق الأساسي         | `student_portal_identity()` يرجع مراجع الطالب الحالي؛ `student-avatar` يتحقق من الهوية ويوقع object من `photos` لمدة 600 ثانية. |
| البدائل/الفشل          | لا هوية/مسار يعيد `image_url:null`؛ الفشل يبقي الرسم المحلي الاحتياطي، ويحاول التطبيق تحديث الرابط عند فشل تحميله.              |
| المدخلات/المخرجات      | Bearer فقط؛ لا يقبل student ID أو مسارًا في جسم الطلب → رابط مؤقت أو null.                                                      |
| قواعد العمل والصلاحيات | bucket خاص؛ تحقق من أصل المشروع والمسار؛ `verify_jwt=true` مع فحص Bearer داخل الدالة.                                           |
| المصدر                 | `student-avatar/index.ts`, `002_functions.sql:student_portal_identity`, `007_storage.sql`, `js/app.js`.                         |
| الحالة                 | منفذ بالكود؛ رابط Storage الحي غير مختبر.                                                                                       |
| معيار القبول           | في بيئة مصرح بها، صورة الطالب المرتبط وحدها تعاد برابط موقع مؤقت؛ يرفض مسار/مشروع آخر.                                          |

#### FR-016 — التنقل داخل بوابة الطالب

| الحقل                  | الوصف                                                                                                                          |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | الطالب المسجل.                                                                                                                 |
| الشروط المسبقة         | حالة الجلسة والبيانات صالحتان.                                                                                                 |
| التدفق الأساسي         | يعرض سبعة أقسام: الملخص، الملف، الحضور، النتائج، الرسوم، الجدول، الروابط؛ يستخدم `#student/<page>` ويدعم history.              |
| البدائل/الفشل          | hash غير معروف يعود للملخص؛ على الهاتف تجمع الأقسام الإضافية في «المزيد» وEscape يغلقها.                                       |
| المدخلات/المخرجات      | اختيار قسم/حدث History → تغيير العرض والـhash.                                                                                 |
| قواعد العمل والصلاحيات | لا يفتح قسم دون `loggedIn` وبيانات طالب.                                                                                       |
| المصدر                 | `js/data.js:localPageCards`, `js/app.js:portalPageFromLocation/syncPortalLocation/bindGlobalEvents`, `css/student-portal.css`. |
| الحالة                 | منفذ.                                                                                                                          |
| معيار القبول           | كل hash صحيح يعرض قسمه؛ الرجوع يعيد السابق؛ hash غير معروف لا يفتح بيانات أخرى.                                                |

#### FR-017 — تسجيل الخروج

| الحقل                  | الوصف                                                                                         |
| ---------------------- | --------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | طالب مسجل.                                                                                    |
| الشروط المسبقة         | عرض البوابة.                                                                                  |
| التدفق الأساسي         | يطلب تأكيدًا في `dialog`؛ التأكيد ينفذ `auth.signOut()` ويمسح حالة الطالب ويعود للموقع العام. |
| البدائل/الفشل          | الإلغاء/Escape يعيد التركيز؛ عند فشل الطلب يحاول مسح الجلسة محليًا ثم يمسح حالة الواجهة.      |
| المدخلات/المخرجات      | تأكيد/إلغاء → جلسة منتهية أو استمرار.                                                         |
| قواعد العمل والصلاحيات | لا يوجد مسار لحذف حساب الطالب.                                                                |
| المصدر                 | `js/app.js:openLogoutConfirmation/dismissLogoutConfirmation/logout`.                          |
| الحالة                 | منفذ محليًا؛ الخروج الحي غير مختبر.                                                           |
| معيار القبول           | بعد التأكيد تختفي بيانات البوابة؛ الإلغاء يبقيها ويعيد التركيز.                               |

# وثيقة متطلبات البرمجيات (SRS)

> **النظام:** موقع مدرسة رواد العلم الأولى وبوابة الطالب وخدمات Supabase المرافقة  
> **الإصدار:** 1.0 — تحليل المستودع الحالي  
> **تاريخ التحليل:** 2026-10-21  
> **طبيعة الوثيقة:** وصف للوظائف والقيود المثبتة في الشيفرة المحلية، لا مواصفة تصميم مستقبلية ولا إثبات لحالة النشر.

## 1. المقدمة

### 1.1 الغرض

تصف هذه الوثيقة النظام كما يظهر في المستودع: موقعًا عامًا عربيًا، ومسار دخول الطالب وبوابته القرائية، إضافة إلى مخطط PostgreSQL وواجهات Supabase الخلفية التي تتضمن إمكانات إدارية وأكاديمية ومالية أوسع. وهي تميّز بين الواجهة التي يستدعيها المتصفح، والدوال الخلفية الموجودة دون واجهة ظاهرة، وبين ما لم يُتحقق منه تكامليًا.

### 1.2 النطاق والأهداف

- تعريف المدرسة ومعلوماتها ومراحلها ووسائل التواصل، وتوجيه الطالب إلى الدخول.
- مصادقة الطالب عبر رقم الطالب وكلمة المرور، واستعادة جلسة Supabase، وعرض إسقاط للبيانات المرتبطة به.
- إتاحة قراءة الملف الدراسي والحضور والنتائج المعتمدة والرسوم والجدول؛ مع صفحة روابط تعليمية ذات حالة فارغة حاليًا.
- توفير أساس بيانات وصلاحيات ودوال خلفية لتسيير نطاقات مدرسية أوسع. وجودها في المخطط لا يعني وجود شاشة أو تدفق أمامي مكتمل.

### 1.3 الجمهور

مالك النظام، إدارة المدرسة، محللو الأعمال، مطورو الواجهة والخدمات، مسؤولو قواعد البيانات والأمن، وفريق الاختبار.

### 1.4 التعريفات والاختصارات

| المصطلح         | المقصود                                                             |
| --------------- | ------------------------------------------------------------------- |
| SRS             | Software Requirements Specification، وثيقة متطلبات البرمجيات        |
| SPA             | تطبيق صفحة واحدة؛ هنا واجهة JavaScript دون إطار عمل                 |
| RPC             | استدعاء دالة PostgreSQL عن طريق Supabase/PostgREST                  |
| Edge Function   | دالة خادمية تعمل في بيئة Deno على Supabase                          |
| RLS             | Row-Level Security، سياسات أمن الصفوف في PostgreSQL                 |
| Auth            | خدمة المصادقة وإدارة الجلسات في Supabase                            |
| إسقاط البيانات  | JSON محدود من قاعدة البيانات لاستخدام بوابة الطالب                  |
| `منفذ`          | يوجد تنفيذ محلي مباشر للمسار الموصوف؛ لا يعني نجاح نشره             |
| `منفذ جزئيًا`   | يوجد بعض التنفيذ، لكن واجهة/تدفق/ضمان أو اختبار تكاملي ناقص         |
| `غير متحقق منه` | وجود كود/مخطط لا يكفي لإثبات السلوك التشغيلي الحي أو اكتمال الوظيفة |

### 1.5 مصادر المستودع

- نقطة الدخول والمحتوى: [`index.html`](../../index.html)، [`js/app.js`](../../js/app.js)، [`js/data.js`](../../js/data.js).
- إعدادات العميل وتحويل البيانات: [`js/supabase-client.js`](../../js/supabase-client.js)، [`js/supabase-config.js`](../../js/supabase-config.js)، [`js/student-portal-data.mjs`](../../js/student-portal-data.mjs).
- العرض: [`css/tokens.css`](../../css/tokens.css)، [`css/styles.css`](../../css/styles.css)، [`css/student-portal.css`](../../css/student-portal.css).
- الخدمات: [`supabase/config.toml`](../../supabase/config.toml)، [`supabase/functions/`](../../supabase/functions/)، والترحيلات [`001_extensions.sql`](../../supabase/migrations/001_extensions.sql) إلى [`008_student_portal_projection.sql`](../../supabase/migrations/008_student_portal_projection.sql).
- توثيق واختبارات: [`README.md`](../../README.md)، [`tests/student-portal-data.test.mjs`](../../tests/student-portal-data.test.mjs).

## 2. الوصف العام للنظام

### 2.1 السياق والمعمارية

الواجهة تطبيق ثابت يستخدم HTML وCSS وJavaScript ES Modules، دون إطار واجهة أو إعداد بناء جذر معروف. تحمل الصفحة المكتبات الخارجية من CDN، وتنشئ `js/supabase-client.js` عميل Supabase عند وجود إعداد URL ومفتاح عميل عام مقبول. المصادقة تتم في Supabase Auth، وتنفذ Edge Functions عمليات الدخول وإدارة الحسابات، وتوفر دوال PostgreSQL/RPC بيانات الطالب والعمليات المدرسية. المتصفح لا يتصل مباشرةً بقاعدة البيانات ببيانات خدمة؛ ويقرأ الطالب بياناته عبر RPC مصادق عليها.

### 2.2 الوظائف الرئيسية

1. صفحة تعريفية ومدخل إلى تسجيل الطالب.
2. تسجيل دخول الطالب واستعادة الجلسة وتسجيل الخروج.
3. بوابة طالب تعرض الملخص والملف والحضور والنتائج والرسوم والجدول.
4. توقيع صورة الطالب الخاصة عند توفر مرجع صورة.
5. وظائف خلفية إدارية ومدرسية تشمل مستخدمي الموظفين، حسابات الطلاب، السجلات الأكاديمية والمالية وغيرها؛ لا يظهر في `index.html` تطبيق إداري يستدعيها.

### 2.3 أنواع المستخدمين

| الدور           | ما يثبته التنفيذ                                                                                               |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| زائر            | يتصفح الصفحة العامة وروابط التواصل.                                                                            |
| طالب            | يسجل الدخول برقم الطالب ويقرأ بيانات الطالب المرتبط بحساب Auth. لا توجد واجهة ولي أمر منفصلة.                  |
| مدير/موظف إداري | أدوار وصلاحيات موجودة في `profiles` و`permissions` وEdge Functions/RLS؛ لا توجد شاشة إدارة في الواجهة الحالية. |
| خدمة Supabase   | `service_role` يستخدم داخل Edge Functions لأعمال مميزة؛ لا يجوز وضعه في المتصفح.                               |

### 2.4 بيئة التشغيل والتقنيات

- متصفح حديث يدعم ES Modules وواجهات DOM الحديثة؛ خادم ملفات ثابت مطلوب لتشغيل الوحدات محليًا.
- HTML5، CSS، JavaScript ES Modules، Node.js لاختبارات `node:test`، PostgreSQL مع Supabase Auth/Storage/PostgREST/Edge Functions (Deno).
- Supabase JS v2 وLucide وGoogle Fonts/Tajawal تُحمّل من مصادر CDN محددة في `index.html` وملفات الخدمات.
- ملفات migrations المحلية هي وصف حالة مقصودة إذا طُبقت بالترتيب؛ لم يتم فحص قاعدة منشورة.

### 2.5 الافتراضات والحدود

- يتطلب التشغيل الكامل إعداد Supabase صالحًا، نشر الدوال، وتطبيق migrations؛ لا تثبت الملفات أن ذلك تم.
- إعدادات المتصفح تتضمن URL ومفتاحًا عامًا؛ لم تُدرج أي قيمة اعتماد في هذه الوثيقة. ملف `.env` لم يُفتح.
- بيانات البوابة تعتمد على ارتباط `auth_user_id` بسجل طالب نشط ومفعّل وعلى وجود قيد مناسب.
- النظام الحالي ليس بوابة ولي أمر، ولا دليل على أنظمة دفع إلكتروني أو بريد أو إشعارات حية.
- الوظائف الإدارية الموصوفة أدناه هي وظائف خلفية موجودة، وليست واجهة مستخدم مكتملة.

## 3. المتطلبات الوظيفية

**معايير الحالة:** تصف الحالة تنفيذ المستودع لا جاهزية النشر. «معيار القبول» أدناه فحص قابل للتكرار على الكود/اختبار تكاملي مصرح به، وليس ادعاء أن جميع الفحوص أجريت.

### 3.1 الموقع العام والتنقل

#### FR-001 — عرض الصفحة العامة

| الحقل                  | الوصف                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | زائر.                                                                                                 |
| الشروط المسبقة         | تحميل `index.html` وخدمات الأصول.                                                                     |
| التدفق الأساسي         | يعرض الشعار والرسالة التعريفية والمدرسة والمراحل واستعراض البوابة والأسئلة الشائعة والتواصل والتذييل. |
| البدائل/الفشل          | الأصول الخارجية قد لا تحمل؛ لا يوجد بديل موثق لكل مكتبة/خط خارجي.                                     |
| المدخلات ← المخرجات    | لا مدخل مستخدم؛ محتوى ثابت من `js/data.js` → صفحة عربية RTL.                                          |
| قواعد العمل والصلاحيات | المحتوى معلوماتي؛ لا يتطلب جلسة. لا تعتبر بطاقات المعاينة بيانات طالب حقيقية.                         |
| المصدر                 | `index.html`، `js/app.js:renderPublicLanding`، `js/data.js`.                                          |
| الحالة                 | منفذ.                                                                                                 |
| معيار القبول           | تحميل الصفحة يعرض الأقسام العامة والعناوين والانتقال إلى نموذج الدخول دون جلسة.                       |

#### FR-002 — التنقل العام ومعاينة أقسام البوابة

| الحقل                  | الوصف                                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | زائر.                                                                                             |
| الشروط المسبقة         | الصفحة العامة محملة.                                                                              |
| التدفق الأساسي         | روابط الأقسام تنتقل إلى المرساة؛ أزرار تبويب المعاينة تغيّر النص والأيقونة وحالة `aria-selected`. |
| البدائل/الفشل          | لا يوجد دعم ظاهر لمفاتيح الأسهم/تركيز roving في تبويبات المعاينة.                                 |
| المدخلات ← المخرجات    | ضغط رابط/تبويب → تغيير موضع الصفحة أو المعاينة.                                                   |
| قواعد العمل والصلاحيات | المعاينة توضيحية ولا تستدعي API.                                                                  |
| المصدر                 | `js/app.js:bindGlobalEvents`, `selectFeature`, `renderPublicLanding`.                             |
| الحالة                 | منفذ جزئيًا.                                                                                      |
| معيار القبول           | اختيار كل تبويب يحدّث المحتوى؛ تحقق لوحة المفاتيح وإمكانية الوصول يتطلب اختبارًا مخصصًا.          |

#### FR-003 — إظهار وسائل التواصل

| الحقل                  | الوصف                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------ |
| المستخدم/الدور         | زائر أو طالب.                                                                        |
| الشروط المسبقة         | بيانات المدرسة مهيأة في `js/data.js`.                                                |
| التدفق الأساسي         | يعرض روابط الهاتف والبريد والخريطة وWhatsApp حيث أمكن تكوين الرابط.                  |
| البدائل/الفشل          | إذا تعذر تكوين رقم WhatsApp يعرض عنصرًا غير متاح؛ وجهة الخريطة/الخدمات خارج التطبيق. |
| المدخلات ← المخرجات    | بيانات اتصال ثابتة → `tel:`, `mailto:`, `wa.me` وروابط خريطة خارجية.                 |
| قواعد العمل والصلاحيات | لا ترسل بيانات البوابة عبر هذه الروابط؛ لا يوجد دعم محادثة داخل النظام.              |
| المصدر                 | `js/data.js:schoolProfile`، `js/app.js:renderWhatsAppLink`, `schoolWhatsAppUrl`.     |
| الحالة                 | منفذ.                                                                                |
| معيار القبول           | الروابط تتطابق مع القيم المصدرية وتفتح الوجهة المحددة.                               |

### 3.2 المصادقة والبوابة

#### FR-004 — إدخال بيانات دخول الطالب والتحقق الأولي

| الحقل                  | الوصف                                                                                                                                   |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | طالب.                                                                                                                                   |
| الشروط المسبقة         | فتح صفحة الدخول.                                                                                                                        |
| التدفق الأساسي         | إدخال رقم الطالب وكلمة المرور؛ يرفض التطبيق الحقول الفارغة، يعطل زر الإرسال أثناء الطلب، ويعرض حالة التحميل والنتيجة في منطقة حالة حية. |
| البدائل/الفشل          | غياب إعداد Supabase يعرض إرشادًا؛ الخطأ يعرض رسالة عربية؛ تغيير الإدخال يمسح حالة الخطأ.                                                |
| المدخلات ← المخرجات    | `studentNumber`, `password` → استدعاء `student-login` ثم حالة/رسالة.                                                                    |
| قواعد العمل والصلاحيات | النموذج `novalidate`؛ رقم الطالب لا يخضع لتحقق صيغة أو طول في المتصفح؛ تلميح لوحة المفاتيح الرقمية ليس تحققًا.                          |
| المصدر                 | `js/app.js:renderLoginPage`, `submitLogin`, `setLoginFieldState`.                                                                       |
| الحالة                 | منفذ.                                                                                                                                   |
| معيار القبول           | اختبار حقلين فارغين لا يرسل الطلب ويحدد الحقل الناقص؛ اختبار الطلب يثبت تعطيل/إعادة زر الإرسال.                                         |

#### FR-005 — مصادقة رقم الطالب من الخادم

| الحقل                  | الوصف                                                                                                                                                                          |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | طالب غير مصادق.                                                                                                                                                                |
| الشروط المسبقة         | POST إلى `/functions/v1/student-login`؛ إعدادات الخادم متوفرة.                                                                                                                 |
| التدفق الأساسي         | يتحقق من JSON ووجود الرقم وكلمة المرور؛ يستدعي `begin_login_attempt` ثم `resolve_login_email` ثم `Auth.signInWithPassword`؛ يعيد رمزي الجلسة والمستخدم عند النجاح.             |
| البدائل/الفشل          | يرفض الأصل غير المسموح، الطريقة غير POST، JSON غير صالح، تجاوز حد المحاولات (429)، بيانات غير صحيحة (401)، أو إعداد الخدمة الناقص (500/503). رسائل بيانات الدخول موحدة نسبيًا. |
| المدخلات ← المخرجات    | `student_number`, `password` → `access_token`, `refresh_token`, user أو خطأ منظم.                                                                                              |
| قواعد العمل والصلاحيات | `verify_jwt=false` لهذه الدالة؛ لا تقبل جلسة مسبقة. حل البريد ومحاولة الدخول محصوران بـ`service_role` في migration 006.                                                        |
| المصدر                 | `supabase/functions/student-login/index.ts`، `supabase/config.toml`، `002_functions.sql:resolve_login_email/begin_login_attempt`، `006_security_hardening.sql`.                |
| الحالة                 | منفذ، غير مختبر على مشروع حي.                                                                                                                                                  |
| معيار القبول           | اختبار تكاملي مصرح به يتحقق من قبول حساب طالب مفعّل ورفض معطّل/مجهول وتطبيق حد المحاولات دون كشف البريد.                                                                       |

#### FR-006 — استعادة الجلسة وإنشاء جلسة الطالب

| الحقل                  | الوصف                                                                                                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | طالب سبق له تسجيل الدخول.                                                                                                                                    |
| الشروط المسبقة         | عميل Supabase وإعداداته متوفران وجلسة قابلة للاستعادة.                                                                                                       |
| التدفق الأساسي         | يستعيد العميل الجلسة، يستدعي `student_portal_session` و`student_portal_data`، يتحقق من وجود هوية الطالب ومن تطابق المعرّف، ثم يعرض البوابة.                  |
| البدائل/الفشل          | جلسة منتهية تُمسح محليًا وتظهر صفحة الدخول؛ فشل مؤقت لا يعرض بوابة غير متحقق منها ويعيد الصفحة العامة. تغير Auth إلى `SIGNED_OUT` يمسح الحالة.               |
| المدخلات ← المخرجات    | جلسة Supabase → هوية طالب وبيانات مسقطة أو رفض.                                                                                                              |
| قواعد العمل والصلاحيات | RPCs لا تستقبل student ID من العميل؛ `app.current_student_portal_id()` يحدد سجل الطالب من الربط.                                                             |
| المصدر                 | `js/app.js:restoreSession`, `loadStudentPortal`, `monitorAuthState`; `002_functions.sql`, `006_security_hardening.sql`, `008_student_portal_projection.sql`. |
| الحالة                 | منفذ محليًا، التكامل الحي غير متحقق منه.                                                                                                                     |
| معيار القبول           | جلسة اختبار مرتبطة تُظهر بيانات الطالب نفسه فقط؛ جلسة بلا ربط أو بهوية متعارضة لا تفتح البوابة.                                                              |

#### FR-007 — إسقاط بيانات البوابة من قاعدة البيانات

| الحقل                  | الوصف                                                                                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| المستخدم/الدور         | طالب مصادق ومرتبط.                                                                                                                                          |
| الشروط المسبقة         | حساب Auth مفعّل، سجل `student_app_accounts` مطابق، الطالب غير مسحوب/مؤرشف، وقيد نشط مؤهل.                                                                   |
| التدفق الأساسي         | `student_portal_data()` يختار الطالب المرتبط ثم قيده النشط مع أولوية العام الحالي؛ يعيد الملف والحضور والنتائج والرسوم وأيام/حصص الجدول.                    |
| البدائل/الفشل          | غياب الربط يعيد `null`؛ غياب القيد قد ينتج بيانات أساسية مع مجموعات فارغة؛ العميل يرفض غياب الهوية.                                                         |
| المدخلات ← المخرجات    | هوية `auth.uid()` فقط → JSON محدود.                                                                                                                         |
| قواعد العمل والصلاحيات | لا وصول مباشر ممنوح إلى `students` أو `student_app_accounts` لبوابة الطالب؛ النتائج مرتبطة بحالة `approved` أو `closed`؛ الحضور بحد أقصى 20 وبترتيب الأحدث. |
| المصدر                 | `supabase/migrations/008_student_portal_projection.sql`, `002_functions.sql:current_student_portal_id`, `006_security_hardening.sql`.                       |
| الحالة                 | تنفيذ SQL موجود؛ لم يُختبر على قاعدة منشورة.                                                                                                                |
| معيار القبول           | فحص صلاحيات RPC ثم استدعاءها بجلسات ربط مختلفة يثبت اقتصار البيانات على الطالب المرتبط واستبعاد النتائج غير المعتمدة.                                       |

#### FR-008 — عرض ملخص الطالب

| الحقل                  | الوصف                                                                                     |
| ---------------------- | ----------------------------------------------------------------------------------------- |
| المستخدم/الدور         | الطالب المرتبط.                                                                           |
| الشروط المسبقة         | تحميل إسقاط البوابة.                                                                      |
| التدفق الأساسي         | يعرض الاسم والصف والسنة، مؤشر الحضور، حصص اليوم، عدد/جزء النتائج، ومجاميع الرسوم المسجلة. |
| البدائل/الفشل          | كل جزء يعرض حالة فارغة إذا لم توجد سجلات؛ الجدول يعتمد يوم الجهاز المحلي.                 |
| المدخلات ← المخرجات    | كائن الطالب المحول → بطاقة ملخص.                                                          |
| قواعد العمل والصلاحيات | لا يعدل البيانات؛ المجاميع محلية من سجل الرسوم المسقط.                                    |
| المصدر                 | `js/app.js:renderPortalHome`, `js/student-portal-data.mjs:mapPortalData`.                 |
| الحالة                 | منفذ.                                                                                     |
| معيار القبول           | بيانات fixture ذات سجلات معروفة تظهر مجاميعها وحالاتها الفارغة وفق المصدر.                |

#### FR-009 — عرض الملف الدراسي

| الحقل                  | الوصف                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------ |
| المستخدم/الدور         | الطالب المرتبط.                                                                            |
| الشروط المسبقة         | استجابة ملف صالح.                                                                          |
| التدفق الأساسي         | يعرض المعلومات الشخصية والدراسية والتسجيل والعنوان، ويخفي الحقول الفارغة.                  |
| البدائل/الفشل          | إذا لم توجد حقول إضافية يعرض حالة فارغة؛ الصورة تستخدم رسمًا احتياطيًا عند عدم توافر صورة. |
| المدخلات ← المخرجات    | حقول `student` → أقسام وصفية دون حقول هواتف أفراد الأسرة.                                  |
| قواعد العمل والصلاحيات | قراءة فقط؛ بعض حقول mapper مثل بعض معلومات التسجيل/المنصات لا تظهر جميعها في القالب.       |
| المصدر                 | `js/app.js:renderPortalPageMarkup(profile)`, `js/student-portal-data.mjs:mapPortalData`.   |
| الحالة                 | منفذ.                                                                                      |
| معيار القبول           | عند إرجاع حقول فارغة تختفي الحقول المقابلة؛ لا تعرض حقول هاتف الأسرة في الملف.             |
