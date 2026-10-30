import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  buildTimetableGrid,
  mapPortalData,
} from "../js/student-portal-data.mjs";
import { normalizeStudentGender } from "../js/student-artwork.js";

const currentSunday = new Date(2026, 9, 18, 12);

function portalFixture(overrides = {}) {
  return {
    student: {
      id: "student-current-session",
      student_number: "S-1001",
      full_name: "طالب للاختبار",
      file_number: "F-1001",
      registration_number: "R-1001",
      registration_date: "2020-09-01",
      graduation_date: null,
      full_name_en: "Test Student",
      first_name: "طالب",
      father_name: "أب",
      grandfather_name: "جد",
      family_name: "عائلة",
      mother_name: "أم",
      gender: "ذكر",
      date_of_birth: "2015-02-03",
      place_of_birth: "طرابلس",
      religion: "مسلم/ة",
      national_id: "123456789012",
      student_phone: "0910000000",
      address: "عنوان",
      residence_address: "سكن",
      city: "طرابلس",
      region: "المدينة",
      previous_school: "مدرسة سابقة",
      nationality: "ليبي",
      admission_type: "نظامي",
      educational_status: "active",
      file_status: "at_school",
      stage: "الابتدائية",
      grade: "الصف الرابع",
      section: "أ",
      academic_year: "2026/2027",
      enrollment_date: "2026-09-01",
      withdrawal_date: null,
      enrollment_status: "نشط",
      roll_number: 12,
      outcome: "in_progress",
      is_new_student: false,
      is_repeat: false,
      father_phone: "0911111111",
      mother_phone: "0922222222",
      nearest_relative_phone: "0933333333",
    },
    attendance: { records: [] },
    results: [],
    fees: [],
    timetable_days: [
      { day_number: 0, name_ar: "الأحد" },
      { day_number: 1, name_ar: "الاثنين" },
    ],
    timetable: [
      {
        entry_id: "entry-1",
        day_number: 0,
        day: "الأحد",
        period_id: "period-1",
        period_number: 1,
        period: "الحصة الأولى",
        start_time: "08:00:00",
        end_time: "08:45:00",
        subject_id: "subject-math",
        subject: "الرياضيات",
        teacher: "معلم",
        room: "قاعة 1",
      },
      {
        entry_id: "entry-2",
        day_number: 1,
        day: "الاثنين",
        period_id: "period-2",
        period_number: 2,
        period: "الحصة الثانية",
        start_time: "08:50:00",
        end_time: "09:35:00",
        subject_id: "subject-science",
        subject: "العلوم",
        teacher: null,
        room: null,
      },
    ],
    ...overrides,
  };
}

test("maps actual subject names into the matching numbered timetable cells", () => {
  const student = mapPortalData(portalFixture(), currentSunday);
  const grid = buildTimetableGrid(student);

  assert.equal(grid.periods.length, 2);
  assert.equal(grid.periods[0].number, 1);
  assert.equal(grid.periods[0].startTime, "08:00");
  assert.equal(grid.periods[0].endTime, "08:45");
  assert.equal(grid.rows[0].day, "الأحد");
  assert.equal(grid.rows[0].cells[0].lessons[0].subject, "الرياضيات");
  assert.equal(grid.rows[1].cells[1].lessons[0].subject, "العلوم");
  assert.equal(student.todayAgenda.length, 1);
  assert.equal(student.todayAgenda[0].subject, "الرياضيات");
  assert.equal(grid.unplacedCount, 0);
});

test("keeps every configured school day and period, including empty cells", () => {
  const student = mapPortalData(
    portalFixture({
      timetable_days: [
        { day_number: 0, name_ar: "الأحد" },
        { day_number: 1, name_ar: "الاثنين" },
        { day_number: 2, name_ar: "الثلاثاء" },
        { day_number: 3, name_ar: "الأربعاء" },
        { day_number: 4, name_ar: "الخميس" },
      ],
      timetable_periods: [1, 2, 3].map((number) => ({
        period_number: number,
        period: `الحصة ${number}`,
        start_time: `0${7 + number}:00:00`,
        end_time: `0${7 + number}:40:00`,
      })),
      timetable: [
        {
          entry_id: "first-period",
          day_number: 0,
          period_number: 1,
          subject: "الرياضيات",
        },
        {
          entry_id: "last-period",
          day_number: 4,
          period_number: 3,
          subject: "العلوم",
        },
      ],
    }),
    currentSunday,
  );
  const grid = buildTimetableGrid(student);

  assert.deepEqual(grid.periods.map((period) => period.number), [1, 2, 3]);
  assert.deepEqual(
    grid.rows.map((day) => day.day_number),
    [0, 1, 2, 3, 4],
  );
  assert.equal(grid.rows[0].cells[0].lessons[0].subject, "الرياضيات");
  assert.equal(grid.rows[4].cells[2].lessons[0].subject, "العلوم");
  assert.equal(grid.rows[2].cells.every((cell) => cell.lessons.length === 0), true);
  assert.equal(grid.periods[0].startTime, "08:00");
});

test("shows a period-one-only day and preserves days with fewer or no lessons", () => {
  const student = mapPortalData(
    portalFixture({
      timetable_days: [
        { day_number: 0, name_ar: "الأحد" },
        { day_number: 1, name_ar: "الاثنين" },
        { day_number: 2, name_ar: "الثلاثاء" },
      ],
      timetable_periods: [
        { period_number: 1, period: "الحصة الأولى", start_time: "08:00:00" },
        { period_number: 2, period: "الحصة الثانية", end_time: "09:30:00" },
      ],
      timetable: [
        {
          entry_id: "only-first-period",
          day_number: 0,
          period_number: 1,
          subject: "اللغة العربية",
          teacher: null,
          start_time: null,
          end_time: null,
        },
      ],
    }),
    currentSunday,
  );
  const grid = buildTimetableGrid(student);

  assert.equal(grid.rows.length, 3);
  assert.equal(grid.rows[0].cells[0].lessons[0].subject, "اللغة العربية");
  assert.equal(grid.rows[0].cells[0].lessons[0].teacher, "");
  assert.equal(grid.rows[0].cells[0].lessons[0].time, "");
  assert.equal(grid.rows[1].cells.every((cell) => cell.lessons.length === 0), true);
  assert.equal(grid.rows[2].cells.every((cell) => cell.lessons.length === 0), true);
  assert.equal(grid.periods[1].startTime, "");
  assert.equal(grid.periods[1].endTime, "09:30");
});

test("keeps consecutive lessons ordered and retains unplaced rows for display", () => {
  const student = mapPortalData(
    portalFixture({
      timetable_days: [{ day_number: 0, name_ar: "الأحد" }],
      timetable: [
        {
          entry_id: "period-two",
          day_number: 0,
          period_number: 2,
          subject: "العلوم",
        },
        {
          entry_id: "period-one",
          day_number: 0,
          period_number: 1,
          subject: "الرياضيات",
        },
        {
          entry_id: "unplaced",
          day_number: null,
          period_number: 1,
          subject: "التاريخ",
        },
      ],
    }),
    currentSunday,
  );
  const grid = buildTimetableGrid(student);
  const visibleEntryIds = [
    ...grid.rows.flatMap((day) =>
      day.cells.flatMap((cell) => cell.lessons.map((lesson) => lesson.id)),
    ),
    ...grid.unplacedLessons.map((lesson) => lesson.entry_id),
  ];

  assert.deepEqual(
    grid.rows[0].cells.map((cell) => cell.lessons[0].subject),
    ["الرياضيات", "العلوم"],
  );
  assert.deepEqual(visibleEntryIds.sort(), [
    "period-one",
    "period-two",
    "unplaced",
  ]);
  assert.equal(grid.unplacedLessons[0].subject, "التاريخ");
  assert.equal(grid.unplacedCount, 1);
});

test("does not interpret null or blank day numbers as Sunday", () => {
  const student = mapPortalData(
    portalFixture({
      timetable_days: [],
      timetable: [
        { day_number: null, period_number: 1, subject: "غير محدد" },
        { day_number: "", period_number: 1, subject: "غير محدد أيضًا" },
      ],
    }),
    currentSunday,
  );

  assert.equal(student.timetableDays.length, 0);
  assert.equal(student.timetableIssues.unplacedLesson, 2);
  assert.equal(buildTimetableGrid(student).unplacedLessons.length, 2);
});

test("maps available personal and enrollment fields without family phone numbers", () => {
  const student = mapPortalData(portalFixture(), currentSunday);

  assert.equal(student.fileNumber, "F-1001");
  assert.equal(student.registrationNumber, "R-1001");
  assert.equal(student.placeOfBirth, "طرابلس");
  assert.equal(student.gender, "ذكر");
  assert.equal(student.nationalId, "123456789012");
  assert.equal(student.studentNumber, "S-1001");
  assert.equal(student.rollNumber, "12");
  assert.equal(student.enrollmentDate, "2026-09-01");
  assert.equal(student.phone, "0910000000");
  assert.equal("father_phone" in student, false);
  assert.equal("mother_phone" in student, false);
  assert.equal("nearest_relative_phone" in student, false);
});

test("does not invent a day or subject when timetable rows are incomplete", () => {
  const fixture = portalFixture({
    timetable_days: [],
    timetable: [
      {
        day_number: null,
        period_number: null,
        subject: null,
        start_time: null,
        end_time: null,
      },
    ],
  });
  const student = mapPortalData(fixture, currentSunday);
  const grid = buildTimetableGrid(student);

  assert.equal(student.timetableDays.length, 0);
  assert.equal(student.todayAgenda.length, 0);
  assert.equal(grid.unplacedCount, 1);
  assert.equal(grid.missingSubjectCount, 1);
});

test("escapes database text before it reaches HTML templates", () => {
  const student = mapPortalData(
    portalFixture({
      timetable: [
        {
          day_number: 0,
          period_number: 1,
          period: "الحصة الأولى",
          start_time: "08:00:00",
          end_time: "08:45:00",
          subject: "<img src=x>",
        },
      ],
    }),
    currentSunday,
  );

  assert.equal(student.timetable[0].subject, "&lt;img src=x&gt;");
});

test("the SQL projection uses the current identity and class-subject relation without returning family phones", async () => {
  const sql = await readFile(
    new URL(
      "../supabase/migrations/008_student_portal_projection.sql",
      import.meta.url,
    ),
    "utf8",
  );
  const hardening = await readFile(
    new URL(
      "../supabase/migrations/006_security_hardening.sql",
      import.meta.url,
    ),
    "utf8",
  );

  assert.match(sql, /v_student_id := app\.current_student_portal_id\(\)/);
  assert.match(sql, /where s\.id = v_student_id/);
  assert.match(
    sql,
    /left join public\.class_subjects cs[\s\S]*?cs\.id = te\.class_subject_id[\s\S]*?cs\.class_id = te\.class_id[\s\S]*?cs\.academic_year_id = te\.academic_year_id/,
  );
  assert.match(sql, /coalesce\(cs\.subject_id, te\.subject_id\)/);
  assert.match(
    sql,
    /te\.class_id = \([\s\S]*?e\.class_id[\s\S]*?v_enrollment_id/,
  );
  assert.match(
    sql,
    /te\.academic_year_id = \([\s\S]*?e\.academic_year_id[\s\S]*?v_enrollment_id/,
  );
  assert.match(sql, /and te\.is_active/);
  assert.match(sql, /'period_number', tp\.period_number/);
  assert.match(sql, /'name_ar', wd\.name_ar/);
  assert.doesNotMatch(sql, /father_phone|mother_phone|nearest_relative_phone/);
  assert.match(
    hardening,
    /grant execute on function public\.student_portal_data\(\) to authenticated/,
  );
});

test("the timetable projection supplies periods only for the student's enrolled class and year", async () => {
  const migration = await readFile(
    new URL(
      "../supabase/migrations/009_student_portal_timetable_periods.sql",
      import.meta.url,
    ),
    "utf8",
  );

  assert.match(
    migration,
    /alter function public\.student_portal_data\(\)\s+rename to student_portal_data_base/,
  );
  assert.match(migration, /v_student_id := app\.current_student_portal_id\(\)/);
  assert.match(migration, /public\.student_portal_data_base\(\)/);
  assert.match(migration, /tp\.school_id = v_school_id/);
  assert.match(migration, /tp\.academic_year_id = v_academic_year_id/);
  assert.match(migration, /te\.class_id = v_class_id/);
  assert.match(migration, /te\.academic_year_id = v_academic_year_id/);
  assert.match(migration, /'period_number', tp\.period_number/);
  assert.match(migration, /'start_time', tp\.start_time/);
  assert.match(migration, /'end_time', tp\.end_time/);
  assert.match(
    migration,
    /grant execute on function public\.student_portal_data\(\) to authenticated/,
  );
  assert.match(
    migration,
    /revoke all on function public\.student_portal_data_base\(\)\s+from public, anon, authenticated/,
  );
});

test("normalizes Arabic and short-form gender values used by student records", () => {
  assert.equal(normalizeStudentGender("ذكر"), "male");
  assert.equal(normalizeStudentGender("أنثى"), "female");
  assert.equal(normalizeStudentGender("انثى"), "female");
  assert.equal(normalizeStudentGender("m"), "male");
  assert.equal(normalizeStudentGender("F"), "female");
  assert.equal(normalizeStudentGender("unknown"), "unknown");
});

test("student photos are signed from the private project bucket and never returned as arbitrary URLs", async () => {
  const avatar = await readFile(
    new URL("../supabase/functions/student-avatar/index.ts", import.meta.url),
    "utf8",
  );
  const app = await readFile(new URL("../js/app.js", import.meta.url), "utf8");

  assert.match(avatar, /if \(url\.origin !== projectOrigin\) return null/);
  assert.match(
    avatar,
    /\.from\("photos"\)[\s\S]*?\.createSignedUrl\(resolved, signedUrlLifetimeSeconds\)/,
  );
  assert.doesNotMatch(avatar, /directUrl/);
  assert.match(app, /url\.origin === projectUrl\.origin/);
  assert.match(app, /photoRefreshAttempted/);
});

test("mobile portal navigation CSS accounts for fixed positioning and safe areas", async () => {
  const css = await readFile(
    new URL("../css/student-portal.css", import.meta.url),
    "utf8",
  );
  const globalCss = await readFile(
    new URL("../css/styles.css", import.meta.url),
    "utf8",
  );
  const mobileNavRule =
    css.match(
      /@media \(max-width: 1024px\)[\s\S]*?\.portal-nav \{([\s\S]*?)\n  \}/,
    )?.[1] ?? "";
  assert.match(mobileNavRule, /position: fixed/);
  assert.match(mobileNavRule, /inset-inline: 0/);
  assert.match(mobileNavRule, /bottom: 0/);
  assert.match(mobileNavRule, /env\(safe-area-inset-bottom, 0px\)/);
  assert.doesNotMatch(mobileNavRule, /transform/);
  assert.match(
    css,
    /@media \(max-width: 1024px\)[\s\S]*?calc\(96px \+ env\(safe-area-inset-bottom, 0px\)\)/,
  );
  assert.match(
    css,
    /\.student-shell \.whatsapp-link--quick[\s\S]*?display: inline-flex/,
  );
  assert.doesNotMatch(
    globalCss,
    /\.public-page,\s*\.login-page,\s*\.student-shell\s*\{\s*animation:/,
  );
});

test("student profile renders its title and real portrait in a dedicated responsive identity header", async () => {
  const app = await readFile(new URL("../js/app.js", import.meta.url), "utf8");
  const css = await readFile(
    new URL("../css/student-portal.css", import.meta.url),
    "utf8",
  );

  assert.match(
    app,
    /class="profile-story__hero"[\s\S]*?id="portal-page-title">ملفي الدراسي/,
  );
  assert.match(
    app,
    /class="profile-story__portrait">\$\{studentPortraitMarkup\(student, "profile"\)\}/,
  );
  assert.match(app, /class="profile-story__quick-facts"/);
  assert.match(css, /\.profile-story__hero\s*\{[\s\S]*?display: grid/);
  assert.match(css, /\.profile-story__portrait \.student-photo-frame--profile/);
  assert.match(
    css,
    /\.profile-story__portrait \.student-photo-frame__image\s*\{[\s\S]*?min-height: 0;[\s\S]*?max-height: 100%/,
  );
  assert.match(
    css,
    /\.profile-story__details dd\s*\{[\s\S]*?font-size: clamp\(1\.08rem/,
  );
});
