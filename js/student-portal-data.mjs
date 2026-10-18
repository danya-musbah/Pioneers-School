function escapeHTML(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );
}

function cleanText(value) {
  if (value === null || value === undefined) return "";
  const text = String(value).trim();
  return /^(null|undefined)$/i.test(text) ? "" : text;
}

function safeText(value) {
  return escapeHTML(cleanText(value));
}

function validDayNumber(value) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 && number <= 6 ? number : null;
}

function timePart(value) {
  const text = cleanText(value);
  return text ? text.slice(0, 5) : "";
}

function buildLessonTime(start, end) {
  const parts = [timePart(start), timePart(end)].filter(Boolean);
  return parts.join(" – ");
}

export function mapPortalData(data, now = new Date()) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new TypeError("Invalid student portal response");
  }

  const source =
    data.student && typeof data.student === "object" ? data.student : {};
  const attendance =
    data.attendance && typeof data.attendance === "object"
      ? data.attendance
      : {};
  const attendanceRecords = Array.isArray(attendance.records)
    ? attendance.records
    : [];
  const results = Array.isArray(data.results) ? data.results : [];
  const feeRecords = Array.isArray(data.fees) ? data.fees : [];
  const rawTimetable = Array.isArray(data.timetable) ? data.timetable : [];
  const today = now.getDay();
  const dayGroups = new Map();
  const timetableIssues = { missingSubject: 0, unplacedLesson: 0 };

  for (const day of Array.isArray(data.timetable_days)
    ? data.timetable_days
    : []) {
    const dayNumber = validDayNumber(day?.day_number);
    if (dayNumber === null) continue;
    dayGroups.set(dayNumber, {
      day_number: dayNumber,
      day: safeText(day.name_ar ?? day.day),
      lessons: [],
    });
  }

  for (const entry of rawTimetable) {
    if (!entry || typeof entry !== "object") continue;
    const dayNumber = validDayNumber(entry.day_number);
    const periodNumber =
      Number.isInteger(Number(entry.period_number)) &&
      Number(entry.period_number) > 0
        ? Number(entry.period_number)
        : null;
    const subject = cleanText(entry.subject);
    const periodName = cleanText(entry.period);
    const period = periodName || (periodNumber ? `الحصة ${periodNumber}` : "");
    const lesson = {
      id: safeText(entry.entry_id),
      subjectId: safeText(entry.subject_id),
      periodId: safeText(entry.period_id),
      periodNumber,
      period: safeText(period),
      startTime: safeText(timePart(entry.start_time)),
      endTime: safeText(timePart(entry.end_time)),
      time: safeText(buildLessonTime(entry.start_time, entry.end_time)),
      subject: safeText(subject),
      teacher: safeText(entry.teacher),
      room: safeText(entry.room),
    };

    if (!subject) timetableIssues.missingSubject += 1;
    if (dayNumber === null || periodNumber === null) {
      timetableIssues.unplacedLesson += 1;
      continue;
    }

    if (!dayGroups.has(dayNumber)) {
      dayGroups.set(dayNumber, {
        day_number: dayNumber,
        day: safeText(entry.day),
        lessons: [],
      });
    }
    dayGroups.get(dayNumber).lessons.push(lesson);
  }

  const timetableDays = [...dayGroups.values()].sort(
    (a, b) => a.day_number - b.day_number,
  );
  for (const day of timetableDays) {
    day.lessons.sort(
      (a, b) =>
        (a.periodNumber ?? Number.MAX_SAFE_INTEGER) -
        (b.periodNumber ?? Number.MAX_SAFE_INTEGER),
    );
  }

  return {
    name: safeText(source.full_name),
    studentNumber: safeText(source.student_number),
    fileNumber: safeText(source.file_number),
    registrationNumber: safeText(source.registration_number),
    registrationDate: safeText(source.registration_date),
    graduationDate: safeText(source.graduation_date),
    fullNameEnglish: safeText(source.full_name_en),
    firstName: safeText(source.first_name),
    fatherName: safeText(source.father_name),
    grandfatherName: safeText(source.grandfather_name),
    familyName: safeText(source.family_name),
    motherName: safeText(source.mother_name),
    nearestRelativeName: safeText(source.nearest_relative_name),
    nearestRelativeRelationship: safeText(source.nearest_relative_relationship),
    phone: safeText(source.student_phone ?? source.phone),
    gender: safeText(source.gender),
    dateOfBirth: safeText(source.date_of_birth),
    placeOfBirth: safeText(source.place_of_birth),
    nationality: safeText(source.nationality),
    religion: safeText(source.religion),
    nationalId: safeText(source.national_id),
    address: safeText(source.address),
    residenceAddress: safeText(source.residence_address),
    city: safeText(source.city),
    region: safeText(source.region),
    previousSchool: safeText(source.previous_school),
    admissionType: safeText(source.admission_type),
    educationalStatus: safeText(source.educational_status),
    fileStatus: safeText(source.file_status),
    stage: safeText(source.stage),
    grade: safeText(source.grade),
    section: safeText(source.section),
    academicYear: safeText(source.academic_year),
    enrollmentDate: safeText(source.enrollment_date),
    enrollmentStatus: safeText(source.enrollment_status),
    withdrawalDate: safeText(source.withdrawal_date),
    rollNumber: safeText(source.roll_number),
    outcome: safeText(source.outcome),
    isNewStudent:
      typeof source.is_new_student === "boolean" ? source.is_new_student : null,
    isRepeat: typeof source.is_repeat === "boolean" ? source.is_repeat : null,
    attendance: {
      present: Number(attendance.present ?? 0),
      late: Number(attendance.late ?? 0),
      absent: Number(attendance.absent ?? 0),
      recordCount: attendanceRecords.length,
      percent: attendanceRecords.length
        ? Number(attendance.percent ?? 0)
        : null,
    },
    attendanceRecords: attendanceRecords.map((record) => {
      const item = record && typeof record === "object" ? record : {};
      return {
        date: safeText(item.date),
        status: safeText(item.status),
        lateMinutes: Number(item.minutes_late ?? 0),
      };
    }),
    results: results.map((result) => {
      const item = result && typeof result === "object" ? result : {};
      return {
        subject: safeText(item.subject),
        grade: safeText(item.grade),
        percentage:
          item.percentage === null || item.percentage === undefined
            ? null
            : Number(item.percentage),
      };
    }),
    feeRecords: feeRecords.map((fee) => {
      const item = fee && typeof fee === "object" ? fee : {};
      return {
        label: safeText(item.label),
        status: safeText(item.status),
        total: Number(item.total ?? 0),
        paid: Number(item.paid ?? 0),
        remaining: Number(item.remaining ?? 0),
      };
    }),
    timetable: rawTimetable
      .filter((entry) => entry && typeof entry === "object")
      .map((entry) => ({
        day_number: validDayNumber(entry.day_number),
        day: safeText(entry.day),
        period_number:
          Number.isInteger(Number(entry.period_number)) &&
          Number(entry.period_number) > 0
            ? Number(entry.period_number)
            : null,
        period: safeText(entry.period),
        period_id: safeText(entry.period_id),
        start_time: safeText(timePart(entry.start_time)),
        end_time: safeText(timePart(entry.end_time)),
        time: safeText(buildLessonTime(entry.start_time, entry.end_time)),
        subject: safeText(entry.subject),
        teacher: safeText(entry.teacher),
        room: safeText(entry.room),
      })),
    timetableDays,
    timetableIssues,
    todayAgenda: timetableDays
      .filter((day) => day.day_number === today)
      .flatMap((day) =>
        day.lessons.map((lesson) => ({
          time: lesson.time,
          subject: lesson.subject,
          teacher: lesson.teacher,
          room: lesson.room,
        })),
      ),
    platforms: [],
  };
}

export function buildTimetableGrid(student) {
  const periodsByNumber = new Map();
  for (const lesson of student.timetable ?? []) {
    if (lesson.period_number === null) continue;
    if (!periodsByNumber.has(lesson.period_number)) {
      periodsByNumber.set(lesson.period_number, {
        number: lesson.period_number,
        name: lesson.period || `الحصة ${lesson.period_number}`,
        startTime: lesson.start_time,
        endTime: lesson.end_time,
      });
    }
  }
  const periods = [...periodsByNumber.values()].sort(
    (a, b) => a.number - b.number,
  );

  const rows = (student.timetableDays ?? []).map((day) => {
    const cells = periods.map((period) => ({
      period,
      lessons: day.lessons.filter(
        (lesson) => lesson.periodNumber === period.number,
      ),
    }));
    return { ...day, cells };
  });

  return {
    periods,
    rows,
    unplacedCount: student.timetableIssues?.unplacedLesson ?? 0,
    missingSubjectCount: student.timetableIssues?.missingSubject ?? 0,
  };
}
