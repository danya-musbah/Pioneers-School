import {
  schoolProfile,
  publicSections,
  localPageCards,
  floatingIcons,
} from "./data.js";
import { getSupabaseClient, hasSupabaseConfig } from "./supabase-client.js";

const app = document.getElementById("app");
const state = {
  page: "home",
  route: "home",
  loggedIn: false,
  activePanel: "home",
  student: null,
  authUser: null,
};

function mount() {
  renderApp();
  bindGlobalEvents();
  void restoreSession();
}

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

function mapPortalData(data) {
  const source = data.student;
  const attendance = data.attendance ?? {};
  const timetable = Array.isArray(data.timetable) ? data.timetable : [];
  const byDay = new Map();

  timetable.forEach((entry) => {
    const key = Number(entry.day_number);
    if (!byDay.has(key)) {
      byDay.set(key, {
        day_number: key,
        day: escapeHTML(entry.day),
        items: [],
      });
    }
    const time = entry.start_time ? `${entry.start_time.slice(0, 5)} ` : "";
    byDay.get(key).items.push(`${time}${escapeHTML(entry.subject || "حصة")}`);
  });

  return {
    name: escapeHTML(source.full_name),
    studentNumber: escapeHTML(source.student_number),
    stage: escapeHTML(source.stage || "—"),
    grade: escapeHTML(source.grade || "—"),
    section: escapeHTML(source.section || "—"),
    academicYear: escapeHTML(source.academic_year || "—"),
    avatar: "assets/logo.png",
    attendance: {
      present: Number(attendance.present ?? 0),
      late: Number(attendance.late ?? 0),
      absent: Number(attendance.absent ?? 0),
      percent: Number(attendance.percent ?? 0),
    },
    attendanceRecords: (attendance.records ?? []).map((record) => ({
      date: escapeHTML(record.date),
      status: escapeHTML(record.status),
      note: record.minutes_late
        ? `${Number(record.minutes_late).toLocaleString("ar-LY")} دقيقة تأخير`
        : "—",
    })),
    results: (data.results ?? []).map((result) => ({
      subject: escapeHTML(result.subject),
      grade: escapeHTML(result.grade || "—"),
      percentage: Number(result.percentage ?? 0),
    })),
    feeRecords: (data.fees ?? []).map((fee) => ({
      label: escapeHTML(fee.label),
      status: escapeHTML(fee.status),
      remaining: `${Number(fee.remaining ?? 0).toLocaleString("ar-LY")} د.ل`,
    })),
    timetable: [...byDay.values()],
    todayAgenda: timetable
      .filter((entry) => Number(entry.day_number) === new Date().getDay())
      .map((entry) => ({
        time: escapeHTML(entry.start_time?.slice(0, 5) || "—"),
        subject: escapeHTML(entry.subject || "حصة"),
        teacher: escapeHTML(entry.teacher || ""),
        room: escapeHTML(entry.room || ""),
      })),
    // These features have no student-facing source in the current schema.
    platforms: [],
    notifications: [],
    badges: [],
  };
}

async function loadStudentPortal(client) {
  const { data: sessionData, error: sessionError } = await client.rpc(
    "student_portal_session",
  );
  if (sessionError || !sessionData?.student?.id) {
    throw new Error("student_session_unavailable");
  }

  const { data, error } = await client.rpc("student_portal_data");
  if (error || !data?.student?.id) {
    throw new Error("student_data_unavailable");
  }
  return mapPortalData(data);
}

async function restoreSession() {
  if (!hasSupabaseConfig()) return;
  try {
    const client = await getSupabaseClient();
    const {
      data: { session },
    } = await client.auth.getSession();
    if (!session) return;
    state.student = await loadStudentPortal(client);
    state.authUser = session.user;
    state.loggedIn = true;
    state.page = "student";
    renderApp();
  } catch {
    // Keep a valid local session if the network or the portal RPC is temporarily unavailable.
    state.student = null;
    state.authUser = null;
    state.loggedIn = false;
  }
}

function bindGlobalEvents() {
  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-target]");
    if (!trigger) return;
    const target = trigger.dataset.target;
    if (target === "login") {
      state.page = "login";
      renderApp();
    }
    if (target === "public-home") {
      state.page = "home";
      renderApp();
    }
    if (target === "student-dashboard") {
      if (state.loggedIn && state.student) {
        state.page = "student";
        renderApp();
      }
    }
    if (target === "logout") {
      void logout();
    }
    if (target.startsWith("page:")) {
      if (!state.loggedIn || !state.student) return;
      state.activePanel = target.replace("page:", "");
      state.page = "student";
      renderApp();
    }
    if (trigger.classList.contains("nav-toggle")) {
      document.body.classList.toggle("nav-open");
    }
    if (trigger.classList.contains("nav-close")) {
      document.body.classList.remove("nav-open");
    }
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (form.matches("[data-login-form]")) {
      event.preventDefault();
      void submitLogin(form);
    }
  });

  document.addEventListener("change", (event) => {
    const target = event.target;
    if (target.matches("[data-password-toggle]")) {
      const field = document.querySelector("[data-password-field]");
      field.type = target.checked ? "text" : "password";
    }
  });
}

async function submitLogin(form) {
  const input = form.querySelector('input[name="studentNumber"]');
  const password = form.querySelector('input[name="password"]');
  const feedback = form.querySelector(".form-feedback");
  const submitButton = form.querySelector('button[type="submit"]');
  const username = input.value.trim();
  const secret = password.value;

  if (!username || !secret) {
    feedback.textContent = "يرجى إدخال رقم الطالب وكلمة المرور.";
    feedback.dataset.state = "error";
    return;
  }
  if (!hasSupabaseConfig()) {
    feedback.textContent =
      "لم تُضف إعدادات Supabase بعد. راجع تعليمات الإعداد في README.";
    feedback.dataset.state = "error";
    return;
  }

  submitButton.disabled = true;
  feedback.textContent = "جارٍ التحقق من بيانات الدخول…";
  feedback.dataset.state = "info";

  let client;
  try {
    client = await getSupabaseClient();
    const { data: tokens, error: loginError } = await client.functions.invoke(
      "student-login",
      { body: { student_number: username, password: secret } },
    );
    if (loginError || !tokens?.access_token || !tokens?.refresh_token) {
      throw new Error("login_unavailable");
    }

    const { data: authData, error: sessionError } =
      await client.auth.setSession({
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
      });
    if (sessionError || !authData.session) throw new Error("login_unavailable");

    const studentData = await loadStudentPortal(client);
    state.student = studentData;
    state.authUser = authData.user;
    state.loggedIn = true;
    state.activePanel = "home";
    state.page = "student";
    renderApp();
  } catch {
    try {
      await client?.auth.signOut({ scope: "local" });
    } catch {
      // Keep the failure message generic and avoid exposing provider details.
    }
    feedback.textContent =
      "تعذر تسجيل الدخول. تحقق من البيانات أو تواصل مع إدارة المدرسة.";
    feedback.dataset.state = "error";
    submitButton.disabled = false;
  }
}

async function logout() {
  let client;
  try {
    client = await getSupabaseClient();
    if (client) await client.auth.signOut();
  } catch {
    try {
      await client?.auth.signOut({ scope: "local" });
    } catch {
      // Clear the visible portal state even if the auth client is unavailable.
    }
  }
  state.student = null;
  state.authUser = null;
  state.loggedIn = false;
  state.page = "home";
  renderApp();
}

function renderApp() {
  if (state.page === "student" && state.loggedIn && state.student) {
    app.innerHTML = renderStudentPortal();
    return;
  }

  if (state.page === "login") {
    app.innerHTML = renderLoginPage();
    return;
  }

  app.innerHTML = renderPublicLanding();
}

function renderPublicLanding() {
  return `
    <div class="page-shell page-shell--public">
      <header class="topbar">
        <div class="container topbar__inner">
          <button class="nav-toggle" aria-label="فتح القائمة" type="button">☰</button>
          <a href="#" class="brand" data-target="public-home">
            <img src="assets/logo.png" alt="شعار المدرسة" />
            <div>
              <strong>${schoolProfile.shortName}</strong>
              <span>${schoolProfile.name}</span>
            </div>
          </a>
          <nav class="main-nav">
            ${publicSections.map((section) => `<a href="#${section.id}">${section.title}</a>`).join("")}
            <button class="btn btn--primary" data-target="login" type="button">تسجيل الدخول</button>
          </nav>
        </div>
      </header>

      <main>
        <section class="hero section-shell">
          <div class="container hero__layout">
            <div class="hero__content">
              <span class="eyebrow">رحلة تعليمية متكاملة</span>
              <h1>مدرسة رواد العلم الأولى<br /><span>للتعليم الأساسـي والثانوي ورياض الأطفال</span></h1>
              <p>${schoolProfile.slogan}</p>
              <div class="cta-row">
                <button class="btn btn--primary btn--large" data-target="login" type="button">دخول الطالب</button>
                <a class="btn btn--secondary btn--large" href="#about">تعرف على المدرسة</a>
              </div>
              <div class="mini-stats">
                <div><strong>4</strong><span>مراحل تعليمية</span></div>
                <div><strong>100%</strong><span>تركيز على الطالب</span></div>
                <div><strong>24/7</strong><span>متابعة أولياء الأمور</span></div>
              </div>
            </div>
            <div class="hero__visual" aria-label="رسمة شخصية مدرسية">
              <div class="floating-orb orb-one"></div>
              <div class="floating-orb orb-two"></div>
              ${floatingIcons
                .map(
                  (icon, index) => `
                <img src="${icon}" alt="" class="float-icon float-icon--${index + 1}" />
              `,
                )
                .join("")}
              <img class="main-character" src="assets/3D Schoolboy Character Reference Sheet-Photoroom.png" alt="طالب يلبس الزي المدرسي" />
              <div class="hero-card hero-card--left">
                <span>مهارات</span>
                <strong>تعلم استكشافي</strong>
              </div>
              <div class="hero-card hero-card--right">
                <span>المنصة</span>
                <strong>مواكبة يومية</strong>
              </div>
            </div>
          </div>
        </section>

        <section id="about" class="info-band section-shell">
          <div class="container band-grid">
            <div class="band-copy">
              <span class="eyebrow">من نحن</span>
              <h2>بيئة تعليمية توازن بين القيم والتعلم والابتكار</h2>
              <p>${schoolProfile.mission}</p>
            </div>
            <div class="band-card">
              <ul>
                ${schoolProfile.services.map((service) => `<li>${service}</li>`).join("")}
              </ul>
            </div>
          </div>
        </section>

        <section id="vision" class="feature-section section-shell">
          <div class="container">
            <div class="section-heading">
              <span class="eyebrow">الرؤية والرسالة</span>
              <h2>أهداف المدرسة تنمو مع الطالب</h2>
            </div>
            <div class="feature-grid">
              <article class="feature-card">
                <span class="feature-icon">🎯</span>
                <h3>الرؤية</h3>
                <p>${schoolProfile.vision}</p>
              </article>
              <article class="feature-card">
                <span class="feature-icon">🤝</span>
                <h3>القيم</h3>
                <p>${schoolProfile.values.join(" • ")}</p>
              </article>
              <article class="feature-card">
                <span class="feature-icon">🚀</span>
                <h3>الأهداف</h3>
                <p>تنمية الاستقلالية، والبحث العلمي، والمهارات الاجتماعية، والثقة بالنفس.</p>
              </article>
            </div>
          </div>
        </section>

        <section id="stages" class="stages section-shell">
          <div class="container">
            <div class="section-heading">
              <span class="eyebrow">المراحل الدراسية</span>
              <h2>رحلة تعلم متدرجة ومناسبة لمرحلة كل طالب</h2>
            </div>
            <div class="stage-grid">
              ${schoolProfile.stages
                .map(
                  (stage) => `
                <article class="stage-card">
                  <div class="stage-icon">${stage.code}</div>
                  <h3>${stage.name}</h3>
                  <p>${stage.detail}</p>
                </article>
              `,
                )
                .join("")}
            </div>
          </div>
        </section>

        <section id="services" class="services section-shell">
          <div class="container">
            <div class="section-heading">
              <span class="eyebrow">الخدمات</span>
              <h2>خدمات أساسية تدعم التعلّم والراحة والاتصال</h2>
            </div>
            <div class="service-grid">
              <article class="service-card"><span>📚</span><h3>المنهاج</h3><p>منهج متوازن يربط بين المعرفة والمهارات.</p></article>
              <article class="service-card"><span>🧭</span><h3>التوجيه</h3><p>مساندة نفسية وتربوية للطالب في كل مرحلة.</p></article>
              <article class="service-card"><span>🧑‍🏫</span><h3>المعلمون</h3><p>فريق تربوي متعاون يولي الأولوية للطالب.</p></article>
              <article class="service-card"><span>📱</span><h3>التواصل</h3><p>منصة موحدة للبيانات الدراسية والعائلة.</p></article>
            </div>
          </div>
        </section>

        <section class="showcase section-shell">
          <div class="container showcase__grid">
            <div class="showcase__visual">
              <img src="assets/Cheerful Schoolyard Friends-Photoroom.png" alt="مجموعة أطفال مدرسية" />
            </div>
            <div class="showcase__content">
              <span class="eyebrow">أداء مشرق</span>
              <h2>تعليم يشعل روح المشاركة، والبحث، والنجاح.</h2>
              <ul>
                <li>مختبرات وفعاليات تعليمية متنوعة</li>
                <li>أنشطة مجتمعية وتعزيز القيم</li>
                <li>رسائل وأخبار موحدة للجميع</li>
              </ul>
            </div>
          </div>
        </section>

        <section id="contact" class="contact section-shell">
          <div class="container contact-grid">
            <div>
              <span class="eyebrow">تواصل</span>
              <h2>معلومات الاتصال</h2>
              <ul class="contact-list">
                <li><strong>الهاتف:</strong> ${schoolProfile.phone}</li>
                <li><strong>البريد:</strong> ${schoolProfile.email}</li>
                <li><strong>العنوان:</strong> ${schoolProfile.address}</li>
              </ul>
            </div>
            <div class="contact-card">
              <a class="btn btn--secondary" href="tel:${schoolProfile.phone.replace(/[^0-9+]/g, "")}">اتصال مباشر</a>
              <a class="btn btn--primary" href="mailto:${schoolProfile.email}">إرسال بريد</a>
              <a class="btn btn--ghost" href="${schoolProfile.mapUrl}" target="_blank" rel="noreferrer">الموقع</a>
            </div>
          </div>
        </section>
      </main>

      <footer class="site-footer">
        <div class="container footer-inner">
          <div>
            <strong>${schoolProfile.name}</strong>
            <p>${schoolProfile.slogan}</p>
          </div>
          <div class="footer-links">
            <a href="#about">عن المدرسة</a>
            <a href="#stages">المراحل</a>
            <a href="#contact">تواصل</a>
          </div>
        </div>
      </footer>
    </div>
  `;
}

function renderLoginPage() {
  return `
    <div class="auth-page">
      <div class="auth-shell">
        <div class="auth-visual" style="background-image: url('assets/images/login background.png');">
          <div class="auth-visual__overlay">
            <img src="assets/logo.png" alt="شعار المدرسة" />
            <h2>${schoolProfile.name}</h2>
          </div>
        </div>
        <div class="auth-card">
          <div class="auth-header">
            <span class="eyebrow">بوابة الطالب</span>
            <h1>تسجيل الدخول</h1>
          </div>
          <form data-login-form class="login-form" novalidate>
            <label>
              <span>رقم الطالب</span>
              <input type="text" name="studentNumber" inputmode="numeric" placeholder="أدخل رقم الطالب" />
            </label>
            <label>
              <span>كلمة المرور</span>
              <div class="password-wrap">
                <input type="password" name="password" data-password-field placeholder="أدخل كلمة المرور" />
                <label class="toggle-password">
                  <input type="checkbox" data-password-toggle />
                  <span>إظهار</span>
                </label>
              </div>
            </label>
            <div class="form-actions">
              <button class="btn btn--primary" type="submit">دخول</button>
              <button class="btn btn--ghost" type="button" data-target="public-home">العودة</button>
            </div>
            <div class="support-row">
              <a href="#">استعادة الوصول</a>
            </div>
            <p class="form-feedback" data-state="info">يتم التحقق من بيانات الحساب بشكل آمن.</p>
          </form>
        </div>
      </div>
    </div>
  `;
}

function getPortalPageMarkup(page) {
  const student = state.student;
  if (page === "profile") {
    return `
      <section class="portal-grid">
        <article class="portal-card portal-card--wide">
          <div class="card-header"><h2>الملف الشخصي</h2><span>بيانات الطالب</span></div>
          <div class="profile-grid">
            <div><strong>الاسم:</strong> ${student.name}</div>
            <div><strong>المرحلة:</strong> ${student.stage}</div>
            <div><strong>الصف:</strong> ${student.grade}</div>
            <div><strong>الشعبة:</strong> ${student.section}</div>
            <div><strong>رقم الطالب:</strong> ${student.studentNumber}</div>
            <div><strong>السنة الدراسية:</strong> ${student.academicYear}</div>
          </div>
        </article>
      </section>
    `;
  }

  if (page === "attendance") {
    return `
      <section class="portal-grid">
        <article class="portal-card portal-card--wide">
          <div class="card-header"><h2>الحضور والغياب</h2><span>آخر السجلات</span></div>
          <div class="results-stack">
            ${
              student.attendanceRecords
                .map(
                  (entry) => `
              <div class="result-row">
                <span>${entry.date}</span>
                <strong>${entry.status}</strong>
                <em>${entry.note}</em>
              </div>
            `,
                )
                .join("") ||
              '<p class="empty-state">لا توجد سجلات حضور متاحة حاليًا.</p>'
            }
          </div>
        </article>
        <article class="portal-card">
          <div class="card-header"><h2>إحصائية</h2><span>هذا الشهر</span></div>
          <p>الحضور: ${student.attendance.present} يوم</p>
          <p>التأخر: ${student.attendance.late} يوم</p>
          <p>الغياب: ${student.attendance.absent} يوم</p>
        </article>
      </section>
    `;
  }

  if (page === "results") {
    return `
      <section class="portal-grid">
        <article class="portal-card portal-card--wide">
          <div class="card-header"><h2>النتائج والتقييمات</h2><span>آخر تقييم</span></div>
          <div class="results-stack">
            ${
              student.results
                .map(
                  (result) => `
              <div class="result-row">
                <span>${result.subject}</span>
                <strong>${result.grade}</strong>
                <em>${result.percentage}%</em>
              </div>
            `,
                )
                .join("") ||
              '<p class="empty-state">لا توجد نتائج معتمدة للعرض حاليًا.</p>'
            }
          </div>
        </article>
      </section>
    `;
  }

  if (page === "fees") {
    return `
      <section class="portal-grid">
        <article class="portal-card portal-card--wide">
          <div class="card-header"><h2>الرسوم والمستحقات</h2><span>حالة الدفعات</span></div>
          <div class="results-stack">
            ${
              student.feeRecords
                .map(
                  (entry) => `
              <div class="result-row">
                <span>${entry.label}</span>
                <strong>${entry.status}</strong>
                <em>${entry.remaining}</em>
              </div>
            `,
                )
                .join("") ||
              '<p class="empty-state">لا توجد مستحقات مسجلة لهذا القيد الدراسي.</p>'
            }
          </div>
        </article>
      </section>
    `;
  }

  if (page === "timetable") {
    return `
      <section class="portal-grid">
        <article class="portal-card portal-card--wide">
          <div class="card-header"><h2>الجدول الدراسي</h2><span>الأسبوع</span></div>
          <div class="results-stack">
            ${
              student.timetable
                .map(
                  (day) => `
              <div class="result-row">
                <span>${day.day}</span>
                <strong>${day.items.join(" • ")}</strong>
                <em>حصص</em>
              </div>
            `,
                )
                .join("") ||
              '<p class="empty-state">لم يُنشر جدول دراسي لهذا الصف بعد.</p>'
            }
          </div>
        </article>
      </section>
    `;
  }

  if (page === "platforms") {
    return `
      <section class="portal-grid">
        <article class="portal-card portal-card--wide">
          <div class="card-header"><h2>المنصات التعليمية</h2><span>روابط مباشرة</span></div>
          <div class="results-stack">
            ${
              student.platforms
                .map(
                  (platform) => `
              <div class="result-row">
                <span>${platform.name}</span>
                <strong>${platform.status}</strong>
                <em><a href="${platform.url}">فتح</a></em>
              </div>
            `,
                )
                .join("") ||
              '<p class="empty-state">لا توجد روابط منصات تعليمية مهيأة حاليًا.</p>'
            }
          </div>
        </article>
      </section>
    `;
  }

  return `
    <section class="portal-grid">
      <article class="portal-card portal-card--wide">
        <div class="card-header">
          <h2>ملخص اليوم</h2>
          <span>جدول الحصة</span>
        </div>
        <div class="agenda-list">
          ${
            student.todayAgenda
              .map(
                (entry) => `
            <div class="agenda-item">
              <strong>${entry.time}</strong>
              <div>
                <p>${entry.subject}</p>
                <small>${entry.teacher} • ${entry.room}</small>
              </div>
            </div>
          `,
              )
              .join("") ||
            '<p class="empty-state">لا توجد حصص مجدولة لهذا اليوم.</p>'
          }
        </div>
      </article>

      <article class="portal-card">
        <div class="card-header">
          <h2>التنبيهات</h2>
          <span>جديد</span>
        </div>
        <ul class="list-stack">
          ${
            student.notifications
              .map(
                (item) => `
            <li class="status-item ${item.read ? "is-read" : "is-new"}">
              <span>${item.type}</span>
              <strong>${item.title}</strong>
              <small>${item.date}</small>
            </li>
          `,
              )
              .join("") || '<li class="empty-state">لا توجد تنبيهات جديدة.</li>'
          }
        </ul>
      </article>

      <article class="portal-card">
        <div class="card-header">
          <h2>أحدث الإنجازات</h2>
          <span>تقدير</span>
        </div>
        <ul class="badge-list">
          ${
            student.badges
              .map(
                (badge) => `
            <li class="badge-item ${badge.achieved ? "is-earned" : "is-future"}">
              <span>${badge.achieved ? "🏆" : "✨"}</span>
              <div>
                <strong>${badge.title}</strong>
                <small>${badge.description}</small>
              </div>
            </li>
          `,
              )
              .join("") ||
            '<li class="empty-state">ستظهر إنجازات الطالب هنا عند توفرها.</li>'
          }
        </ul>
      </article>

      <article class="portal-card">
        <div class="card-header">
          <h2>النتائج</h2>
          <span>آخر تقييم</span>
        </div>
        <div class="results-stack">
          ${
            student.results
              .map(
                (result) => `
            <div class="result-row">
              <span>${result.subject}</span>
              <strong>${result.grade}</strong>
              <em>${result.percentage}%</em>
            </div>
          `,
              )
              .join("") ||
            '<p class="empty-state">لا توجد نتائج معتمدة للعرض حاليًا.</p>'
          }
        </div>
      </article>
    </section>
  `;
}

function renderStudentPortal() {
  const student = state.student;
  const activePage = state.activePanel || "home";
  const cards = localPageCards;

  return `
    <div class="student-shell">
      <aside class="sidebar">
        <div class="sidebar__brand">
          <img src="assets/logo.png" alt="شعار المدرسة" />
          <div>
            <strong>${schoolProfile.shortName}</strong>
            <span>بوابة الطالب</span>
          </div>
        </div>
        <nav class="sidebar-nav">
          ${cards
            .map(
              (card) => `
            <button class="sidebar-link ${activePage === card.page ? "is-active" : ""}" type="button" data-target="page:${card.page}">
              <span>${card.icon}</span>
              <span>${card.label}</span>
            </button>
          `,
            )
            .join("")}
        </nav>
        <button class="btn btn--ghost sidebar__logout" type="button" data-target="logout">تسجيل الخروج</button>
      </aside>

      <main class="student-main">
        <header class="student-topbar">
          <div>
            <span class="eyebrow">مرحبا بك</span>
            <h1>أهلاً ${student.name.split(" ")[0]} 👋</h1>
          </div>
          <div class="today-date">${new Date().toLocaleDateString("ar-EG", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</div>
        </header>

        <section class="student-summary">
          <div class="student-summary__profile">
            <img src="${student.avatar}" alt="صورة الطالب" />
            <div>
              <strong>${student.name}</strong>
              <p>${student.stage} • ${student.grade} • ${student.section}</p>
              <small>السنة الدراسية: ${student.academicYear}</small>
            </div>
          </div>
          <div class="summary-stat">
            <span>الحضور</span>
            <strong>${student.attendance.percent}%</strong>
            <small>مستوى الحضور الحالي</small>
          </div>
          <div class="summary-stat">
            <span>الإنجازات</span>
            <strong>${student.results.length}</strong>
            <small>مواد لها نتائج معتمدة</small>
          </div>
        </section>

        ${getPortalPageMarkup(activePage)}
      </main>
    </div>
  `;
}

mount();
