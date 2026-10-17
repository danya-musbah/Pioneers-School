import {
  schoolProfile,
  publicSections,
  localPageCards,
  decorativeStickers,
} from "./data.js";
import { getSupabaseClient, hasSupabaseConfig } from "./supabase-client.js";

const app = document.getElementById("app");
const state = {
  page: "home",
  activePanel: "home",
  loggedIn: false,
  authUser: null,
  student: null,
};
let revealObserver;

function mount() {
  renderApp();
  bindGlobalEvents();
  bindMotionEvents();
  void restoreSession();
}

const publicFeatures = [
  {
    key: "profile",
    icon: "user-round",
    title: "ملف الطالب",
    description:
      "الاطلاع على بيانات القيد والمرحلة والصف المرتبط بحساب الطالب.",
    note: "بيانات القيد الأساسية",
  },
  {
    key: "attendance",
    icon: "calendar-check",
    title: "الحضور",
    description: "مراجعة سجلات الحضور والغياب المرتبطة بالقيد الدراسي.",
    note: "سجلات الحضور والغياب",
  },
  {
    key: "results",
    icon: "chart-no-axes-column-increasing",
    title: "النتائج",
    description: "تظهر النتائج للطالب بعد اعتمادها من المدرسة.",
    note: "النتائج المعتمدة فقط",
  },
  {
    key: "fees",
    icon: "wallet",
    title: "الرسوم",
    description: "متابعة بنود الرسوم والمبالغ المسجلة للطالب.",
    note: "بنود الرسوم المسجلة",
  },
  {
    key: "timetable",
    icon: "calendar-days",
    title: "الجدول",
    description: "عرض جدول الصف المنشور للعام الدراسي الحالي.",
    note: "الجدول المنشور للصف",
  },
];

const faqItems = [
  {
    question: "كيف أحصل على بيانات الدخول؟",
    answer:
      "يُنشأ حساب الطالب من إدارة المدرسة، وتُسلّم بيانات الدخول المؤقتة عبر القنوات المعتمدة لدى المدرسة.",
  },
  {
    question: "لماذا لا تظهر نتيجة الطالب؟",
    answer:
      "تعرض البوابة النتائج التي اعتمدتها المدرسة فقط. إذا لم تظهر نتيجة، يُرجى التأكد من اعتمادها لدى الإدارة.",
  },
  {
    question: "ما البيانات التي تظهر في البوابة؟",
    answer:
      "تعرض البوابة بيانات القيد والحضور والنتائج المعتمدة والرسوم والجدول المرتبط بحساب الطالب، بحسب ما نُشر في النظام.",
  },
  {
    question: "هل يوجد تسجيل دخول منفصل لولي الأمر؟",
    answer:
      "واجهة تسجيل الدخول الحالية مخصصة لحساب الطالب. لا يوجد في النسخة الحالية مسار مستقل لدخول ولي الأمر.",
  },
  {
    question: "كيف أستعيد الوصول إلى الحساب؟",
    answer: `تواصل مع إدارة المدرسة عبر ${schoolProfile.phone} أو ${schoolProfile.email} للتحقق من الحساب وإعادة تعيين بياناته.`,
  },
];

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

function formatAmount(amount) {
  return `${Number(amount ?? 0).toLocaleString("ar-LY", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })} د.ل`;
}

function mapPortalData(data) {
  const source = data.student;
  const attendance = data.attendance ?? {};
  const timetable = Array.isArray(data.timetable) ? data.timetable : [];
  const dayGroups = new Map();

  timetable.forEach((entry) => {
    const dayNumber = Number(entry.day_number);
    if (!dayGroups.has(dayNumber)) {
      dayGroups.set(dayNumber, {
        day_number: dayNumber,
        day: escapeHTML(entry.day || "غير محدد"),
        lessons: [],
      });
    }
    dayGroups.get(dayNumber).lessons.push({
      period: escapeHTML(entry.period || "حصة"),
      time: `${entry.start_time ? escapeHTML(entry.start_time.slice(0, 5)) : "—"}${entry.end_time ? `–${escapeHTML(entry.end_time.slice(0, 5))}` : ""}`,
      subject: escapeHTML(entry.subject || "مادة دراسية"),
      teacher: escapeHTML(entry.teacher || ""),
      room: escapeHTML(entry.room || ""),
    });
  });

  return {
    name: escapeHTML(source.full_name),
    studentNumber: escapeHTML(source.student_number),
    stage: escapeHTML(source.stage || "—"),
    grade: escapeHTML(source.grade || "—"),
    section: escapeHTML(source.section || "—"),
    academicYear: escapeHTML(source.academic_year || "—"),
    attendance: {
      present: Number(attendance.present ?? 0),
      late: Number(attendance.late ?? 0),
      absent: Number(attendance.absent ?? 0),
      recordCount: (attendance.records ?? []).length,
      percent: (attendance.records ?? []).length
        ? Number(attendance.percent ?? 0)
        : null,
    },
    attendanceRecords: (attendance.records ?? []).map((record) => ({
      date: escapeHTML(record.date),
      status: escapeHTML(record.status || "غير محدد"),
      lateMinutes: Number(record.minutes_late ?? 0),
    })),
    results: (data.results ?? []).map((result) => ({
      subject: escapeHTML(result.subject || "مادة دراسية"),
      grade: escapeHTML(result.grade || "—"),
      percentage:
        result.percentage === null || result.percentage === undefined
          ? null
          : Number(result.percentage),
    })),
    feeRecords: (data.fees ?? []).map((fee) => ({
      label: escapeHTML(fee.label || "رسوم دراسية"),
      status: escapeHTML(fee.status || "غير محدد"),
      total: Number(fee.total ?? 0),
      paid: Number(fee.paid ?? 0),
      remaining: Number(fee.remaining ?? 0),
    })),
    timetable: [...dayGroups.values()],
    todayAgenda: timetable
      .filter((entry) => Number(entry.day_number) === new Date().getDay())
      .map((entry) => ({
        time: escapeHTML(entry.start_time?.slice(0, 5) || "—"),
        subject: escapeHTML(entry.subject || "حصة"),
        teacher: escapeHTML(entry.teacher || ""),
        room: escapeHTML(entry.room || ""),
      })),
    platforms: [],
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

function refreshIcons() {
  if (window.lucide?.createIcons) {
    window.lucide.createIcons({
      attrs: { "stroke-width": 1.8, "aria-hidden": "true" },
    });
    return;
  }
  document
    .getElementById("lucide-icons")
    ?.addEventListener("load", refreshIcons, { once: true });
}

function observeReveals() {
  revealObserver?.disconnect();
  const revealElements = app.querySelectorAll("[data-reveal]");
  if (
    !("IntersectionObserver" in window) ||
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    revealElements.forEach((element) => element.classList.add("is-visible"));
    return;
  }
  revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -28px 0px" },
  );
  revealElements.forEach((element) => {
    if (!element.classList.contains("is-visible"))
      revealObserver.observe(element);
  });
}

function closeMobileNav() {
  document.body.classList.remove("nav-open");
  document
    .querySelector("[data-nav-toggle]")
    ?.setAttribute("aria-expanded", "false");
  const icon = document.querySelector("[data-nav-toggle] [data-lucide]");
  if (icon) icon.setAttribute("data-lucide", "menu");
  refreshIcons();
}

function bindMotionEvents() {
  const updateHeader = () => {
    document
      .querySelector("[data-site-header]")
      ?.classList.toggle("is-scrolled", window.scrollY > 12);
  };
  window.addEventListener("scroll", updateHeader, { passive: true });
  updateHeader();

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  if (!window.matchMedia("(pointer: fine)").matches || reducedMotion.matches)
    return;
  document.addEventListener("pointermove", (event) => {
    const scene = event.target.closest?.("[data-parallax-scene]");
    if (!scene) return;
    const bounds = scene.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    scene.style.setProperty("--pointer-x", x.toFixed(2));
    scene.style.setProperty("--pointer-y", y.toFixed(2));
  });
  document.addEventListener("pointerout", (event) => {
    const scene = event.target.closest?.("[data-parallax-scene]");
    if (!scene || scene.contains(event.relatedTarget)) return;
    scene.style.setProperty("--pointer-x", "0");
    scene.style.setProperty("--pointer-y", "0");
  });
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
    // Preserve cached auth during temporary network or RPC outages, but never show an unvalidated portal.
    state.student = null;
    state.authUser = null;
    state.loggedIn = false;
  }
}

function bindGlobalEvents() {
  document.addEventListener("click", (event) => {
    const navToggle = event.target.closest("[data-nav-toggle]");
    if (navToggle) {
      const isOpen = document.body.classList.toggle("nav-open");
      navToggle.setAttribute("aria-expanded", String(isOpen));
      navToggle.setAttribute(
        "aria-label",
        isOpen ? "إغلاق القائمة" : "فتح القائمة",
      );
      navToggle
        .querySelector("[data-lucide]")
        ?.setAttribute("data-lucide", isOpen ? "x" : "menu");
      refreshIcons();
      return;
    }

    const mainNavLink = event.target.closest(".main-nav a");
    if (mainNavLink) closeMobileNav();

    const featureTab = event.target.closest("[data-feature-tab]");
    if (featureTab) {
      selectFeature(featureTab.dataset.featureTab);
      return;
    }

    const trigger = event.target.closest("[data-target]");
    if (!trigger) return;
    const target = trigger.dataset.target;
    if (target === "login") {
      closeMobileNav();
      state.page = "login";
      renderApp();
      app
        .querySelector('input[name="studentNumber"]')
        ?.focus({ preventScroll: true });
    } else if (target === "public-home") {
      state.page = "home";
      state.activePanel = "home";
      renderApp();
      window.scrollTo({ top: 0, behavior: "smooth" });
    } else if (target === "student-dashboard") {
      if (!state.loggedIn || !state.student) return;
      state.page = "student";
      state.activePanel = "home";
      renderApp();
      window.scrollTo({ top: 0, behavior: "smooth" });
    } else if (target === "logout") {
      void logout();
    } else if (target.startsWith("page:")) {
      if (!state.loggedIn || !state.student) return;
      state.activePanel = target.slice("page:".length);
      state.page = "student";
      renderApp();
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!form.matches("[data-login-form]")) return;
    event.preventDefault();
    void submitLogin(form);
  });

  document.addEventListener("change", (event) => {
    const target = event.target;
    if (!target.matches("[data-password-toggle]")) return;
    const field = app.querySelector("[data-password-field]");
    field.type = target.checked ? "text" : "password";
    target.setAttribute(
      "aria-label",
      target.checked ? "إخفاء كلمة المرور" : "إظهار كلمة المرور",
    );
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMobileNav();
  });
}

function selectFeature(key) {
  const feature = publicFeatures.find((item) => item.key === key);
  if (!feature) return;
  app.querySelectorAll("[data-feature-tab]").forEach((tab) => {
    const selected = tab.dataset.featureTab === key;
    tab.setAttribute("aria-selected", String(selected));
    tab.classList.toggle("is-active", selected);
  });
  const icon = app.querySelector("[data-feature-preview-icon]");
  const title = app.querySelector("[data-feature-preview-title]");
  const body = app.querySelector("[data-feature-preview-body]");
  const note = app.querySelector("[data-feature-preview-note]");
  if (!icon || !title || !body || !note) return;
  icon.setAttribute("data-lucide", feature.icon);
  app
    .querySelector("#feature-preview")
    ?.setAttribute("aria-labelledby", `feature-tab-${feature.key}`);
  title.textContent = feature.title;
  body.textContent = feature.description;
  note.textContent = feature.note;
  refreshIcons();
}

async function submitLogin(form) {
  const input = form.querySelector('input[name="studentNumber"]');
  const password = form.querySelector('input[name="password"]');
  const feedback = form.querySelector(".form-feedback");
  const submitButton = form.querySelector('button[type="submit"]');
  const submitLabel = submitButton.querySelector("[data-login-label]");
  const username = input.value.trim();
  const secret = password.value;

  if (!username || !secret) {
    feedback.textContent = "أدخل رقم الطالب وكلمة المرور للمتابعة.";
    feedback.dataset.state = "error";
    input.focus();
    return;
  }
  if (!hasSupabaseConfig()) {
    feedback.textContent =
      "إعداد الاتصال بالبوابة غير مكتمل. تواصل مع إدارة المدرسة.";
    feedback.dataset.state = "error";
    return;
  }

  submitButton.disabled = true;
  submitButton.setAttribute("aria-busy", "true");
  submitButton.classList.add("is-loading");
  submitLabel.textContent = "جارٍ التحقق";
  feedback.textContent = "نتحقق من بيانات الدخول بأمان…";
  feedback.dataset.state = "info";
  refreshIcons();

  let client;
  let failureMessage =
    "تعذر الاتصال بخدمة الدخول. تحقق من نشر الدالة وإعداد نطاق CORS.";
  try {
    client = await getSupabaseClient();
    const { data: tokens, error: loginError } = await client.functions.invoke(
      "student-login",
      { body: { student_number: username, password: secret } },
    );
    if (loginError) {
      const status = Number(loginError.context?.status || 0);
      if (status === 404) {
        failureMessage = "خدمة الدخول غير منشورة على المشروع بعد.";
      } else if (status === 401 || status === 429) {
        failureMessage =
          "تعذر الدخول. تحقق من البيانات أو تواصل مع إدارة المدرسة.";
      }
      throw new Error("login_unavailable");
    }
    if (!tokens?.access_token || !tokens?.refresh_token) {
      throw new Error("login_unavailable");
    }

    const { data: authData, error: sessionError } =
      await client.auth.setSession({
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
      });
    if (sessionError || !authData.session) throw new Error("login_unavailable");

    failureMessage =
      "تم التحقق من الدخول لكن تعذر تحميل بيانات البوابة. تحقق من نشر بيانات النظام وصلاحية الحساب.";
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
      // Keep provider details and credentials out of the UI.
    }
    feedback.textContent = failureMessage;
    feedback.dataset.state = "error";
    submitButton.disabled = false;
    submitButton.removeAttribute("aria-busy");
    submitButton.classList.remove("is-loading");
    submitLabel.textContent = "دخول آمن";
    refreshIcons();
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
      // Clear the visible portal even when the auth network is unavailable.
    }
  }
  state.student = null;
  state.authUser = null;
  state.loggedIn = false;
  state.page = "home";
  state.activePanel = "home";
  renderApp();
}

function renderApp() {
  app.classList.add("motion-ready");
  if (state.page === "student" && state.loggedIn && state.student) {
    app.innerHTML = renderStudentPortal();
  } else if (state.page === "login") {
    app.innerHTML = renderLoginPage();
  } else {
    app.innerHTML = renderPublicLanding();
  }
  refreshIcons();
  observeReveals();
}

function renderPublicLanding() {
  const initialFeature = publicFeatures[0];
  return `
    <div class="public-page">
      <header class="site-header" data-site-header>
        <div class="container header__inner">
          <a class="brand" href="#home" data-target="public-home" aria-label="العودة إلى بداية الموقع">
            <img src="assets/logo.png" alt="" width="52" height="52" />
            <span class="brand__words">
              <strong>${schoolProfile.shortName}</strong>
              <small>مدرسة رواد العلم الأولى</small>
            </span>
          </a>
          <button class="icon-button nav-toggle" type="button" data-nav-toggle aria-label="فتح القائمة" aria-expanded="false" aria-controls="main-navigation">
            <i data-lucide="menu"></i>
          </button>
          <nav class="main-nav" id="main-navigation" aria-label="التنقل الرئيسي">
            ${publicSections.map((section) => `<a href="#${section.id}">${section.title}</a>`).join("")}
          </nav>
          <button class="button button--primary header__login" type="button" data-target="login">
            <i data-lucide="log-in"></i><span>دخول الطالب</span>
          </button>
        </div>
      </header>

      <main id="home">
        <section class="hero" aria-labelledby="hero-title">
          <div class="container hero__grid">
            <div class="hero__copy" data-reveal>
              <p class="eyebrow"><span class="eyebrow__dot"></span> بوابة مدرسة رواد العلم الأولى</p>
              <h1 id="hero-title">بين المدرسة والبيت،<br /><em>خيطٌ واحد من المعرفة.</em></h1>
              <p class="hero__lead">${schoolProfile.slogan} — بوابة الطالب تجمع بياناته الدراسية المنشورة في مساحة واضحة وآمنة.</p>
              <div class="hero__actions">
                <button class="button button--primary button--hero" type="button" data-target="login">
                  <span>ادخل إلى بوابتك</span><i data-lucide="arrow-up-left"></i>
                </button>
                <a class="button button--quiet" href="#portal-features">
                  <span>اكتشف ما ستجده</span><i data-lucide="arrow-down"></i>
                </a>
              </div>
              <div class="hero__note">
                <span class="hero__note-mark"><i data-lucide="shield-check"></i></span>
                <p><strong>بياناتك لك</strong><span>كل حساب يرى بيانات الطالب المرتبط به فقط.</span></p>
              </div>
            </div>

            <div class="hero-scene" data-parallax-scene data-reveal aria-label="طالب في طريقه إلى المدرسة">
              <div class="hero-scene__paper"></div>
              <div class="hero-scene__sun" aria-hidden="true"></div>
              <div class="hero-scene__label hero-scene__label--top"><i data-lucide="book-open-check"></i><span>مساحة للتعلّم</span></div>
              <img class="hero-scene__character" src="assets/3D Schoolboy Character Reference Sheet-Photoroom.png" alt="طالب يحمل كتابه ويرتدي الزي المدرسي" fetchpriority="high" />
              <img class="sticker sticker--sun" src="${decorativeStickers[0]}" alt="" aria-hidden="true" />
              <img class="sticker sticker--heart" src="${decorativeStickers[1]}" alt="" aria-hidden="true" />
              <img class="sticker sticker--flower" src="${decorativeStickers[2]}" alt="" aria-hidden="true" />
              <div class="hero-scene__label hero-scene__label--bottom"><i data-lucide="calendar-days"></i><span>يوم دراسي أكثر وضوحًا</span></div>
              <span class="scene-caption">نرافق الرحلة، ولا نستبدلها.</span>
            </div>
          </div>
          <a class="scroll-cue" href="#school"><span>اكتشف المدرسة</span><i data-lucide="arrow-down"></i></a>
        </section>

        <section class="school-story section-space" id="school" aria-labelledby="school-title">
          <div class="container story__layout">
            <div class="story__index" data-reveal>
              <span class="section-index">01 <span></span> المدرسة</span>
              <div class="story__seal"><img src="assets/logo.png" alt="شعار مدرسة رواد العلم الأولى" loading="lazy" /></div>
            </div>
            <div class="story__copy" data-reveal>
              <p class="eyebrow eyebrow--light">التعلّم يبدأ بعلاقة</p>
              <h2 id="school-title">معرفة تنمو،<br /><em>وقيم تبقى.</em></h2>
              <p>${schoolProfile.mission}</p>
              <ul class="value-list" aria-label="قيم المدرسة">
                ${schoolProfile.values.map((value) => `<li><span></span>${value}</li>`).join("")}
              </ul>
            </div>
            <aside class="story__aside" data-reveal>
              <span class="story__aside-mark" aria-hidden="true">ر</span>
              <p>${schoolProfile.vision}</p>
              <a class="text-link text-link--light" href="#stages">تعرّف إلى المراحل <i data-lucide="arrow-up-left"></i></a>
            </aside>
          </div>
        </section>

        <section class="portal-tour section-space" id="portal-features" aria-labelledby="features-title">
          <div class="container">
            <div class="section-heading section-heading--split" data-reveal>
              <div>
                <span class="section-index">02 <span></span> البوابة</span>
                <h2 id="features-title">ما يهمّك،<br /><em>في مكانه.</em></h2>
              </div>
              <p>اختر القسم لاستكشاف ما تعرضه البوابة. لا تظهر البيانات إلا بعد تسجيل الدخول وبحسب ما نُشر في النظام.</p>
            </div>
            <div class="feature-explorer" data-reveal>
              <div class="feature-tabs" role="tablist" aria-label="أقسام بوابة الطالب">
                ${publicFeatures
                  .map(
                    (feature, index) => `
                  <button class="feature-tab ${index === 0 ? "is-active" : ""}" type="button" role="tab" id="feature-tab-${feature.key}" aria-selected="${index === 0}" aria-controls="feature-preview" data-feature-tab="${feature.key}">
                    <span class="feature-tab__icon"><i data-lucide="${feature.icon}"></i></span>
                    <span>${feature.title}</span><i class="feature-tab__arrow" data-lucide="arrow-up-left"></i>
                  </button>
                `,
                  )
                  .join("")}
              </div>
              <article class="feature-preview" id="feature-preview" role="tabpanel" aria-labelledby="feature-tab-${initialFeature.key}">
                <div class="feature-preview__topline"><span>داخل بوابتك</span><span class="feature-preview__rule"></span><i data-lucide="sparkles"></i></div>
                <div class="preview-window" aria-hidden="true">
                  <div class="preview-window__bar"><span></span><span></span><span></span><i data-lucide="panel-top"></i></div>
                  <div class="preview-window__content">
                    <div class="preview-glyph"><i data-feature-preview-icon data-lucide="${initialFeature.icon}"></i></div>
                    <div class="preview-lines"><span></span><span></span><span></span></div>
                    <div class="preview-stamp"><i data-lucide="lock-keyhole"></i></div>
                  </div>
                </div>
                <div class="feature-preview__copy">
                  <span class="feature-preview__note" data-feature-preview-note>${initialFeature.note}</span>
                  <h3 data-feature-preview-title>${initialFeature.title}</h3>
                  <p data-feature-preview-body>${initialFeature.description}</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section class="journey section-space" id="journey" aria-labelledby="journey-title">
          <div class="container journey__layout">
            <div class="journey__art" data-reveal>
              <div class="journey__frame"></div>
              <img src="assets/Cheerful Schoolyard Friends-Photoroom.png" alt="مجموعة من الطلاب بزي المدرسة يتشاركون التعلّم" loading="lazy" />
              <img class="sticker sticker--journey" src="${decorativeStickers[3]}" alt="" aria-hidden="true" />
              <span class="journey__caption">معًا في طريق المعرفة</span>
            </div>
            <div class="journey__copy" data-reveal>
              <span class="section-index">03 <span></span> طريقة الاستخدام</span>
              <h2 id="journey-title">خطوات بسيطة،<br /><em>ومتابعة أوضح.</em></h2>
              <p class="journey__intro">مسار تعريفي يساعد الطالب على فهم ما يمكنه الوصول إليه في البوابة.</p>
              <ol class="journey-list">
                <li><span class="journey-list__number">١</span><div><strong>الدخول إلى الحساب</strong><p>استخدم رقم الطالب وكلمة المرور التي تسلّمتها من إدارة المدرسة.</p></div></li>
                <li><span class="journey-list__number">٢</span><div><strong>تعرّف إلى ملفك</strong><p>راجع بيانات القيد والسنة والصف المرتبط بحسابك.</p></div></li>
                <li><span class="journey-list__number">٣</span><div><strong>تابع المنشور لك</strong><p>انتقل بين الحضور والنتائج المعتمدة والرسوم والجدول الدراسي.</p></div></li>
              </ol>
            </div>
          </div>
        </section>

        <section class="stages-section section-space" id="stages" aria-labelledby="stages-title">
          <div class="container">
            <div class="section-heading section-heading--center" data-reveal>
              <span class="section-index">04 <span></span> المراحل</span>
              <h2 id="stages-title">لكل مرحلة،<br /><em>بدايتها الجميلة.</em></h2>
              <p>المراحل الدراسية المعروضة وفق تعريف المدرسة.</p>
            </div>
            <div class="stage-path">
              ${schoolProfile.stages
                .map(
                  (stage, index) => `
                <article class="stage-entry stage-entry--${index + 1}" data-reveal style="--entry-index:${index}">
                  <span class="stage-entry__code">${escapeHTML(stage.code)}</span>
                  <span class="stage-entry__marker" aria-hidden="true"><i data-lucide="${["sprout", "puzzle", "book-open", "compass"][index]}"></i></span>
                  <h3>${escapeHTML(stage.name)}</h3>
                  <p>${escapeHTML(stage.detail)}</p>
                </article>
              `,
                )
                .join("")}
              <span class="stage-path__line" aria-hidden="true"></span>
            </div>
          </div>
        </section>

        <section class="faq-section section-space" id="faq" aria-labelledby="faq-title">
          <div class="container faq__layout">
            <div class="faq__heading" data-reveal>
              <span class="section-index">05 <span></span> المساعدة</span>
              <h2 id="faq-title">أسئلة<br /><em>تتكرر.</em></h2>
              <p>لم تجد ما تبحث عنه؟ تواصل مباشرة مع المدرسة.</p>
              <a class="text-link" href="mailto:${schoolProfile.email}">راسل المدرسة <i data-lucide="arrow-up-left"></i></a>
            </div>
            <div class="faq-list" data-reveal>
              ${faqItems
                .map(
                  (item, index) => `
                <details class="faq-item" ${index === 0 ? "" : ""}>
                  <summary><span>${item.question}</span><i data-lucide="plus"></i></summary>
                  <div class="faq-item__answer"><p>${item.answer}</p></div>
                </details>
              `,
                )
                .join("")}
            </div>
          </div>
        </section>

        <section class="closing section-space" id="contact" aria-labelledby="closing-title">
          <div class="container closing__inner">
            <div class="closing__copy" data-reveal>
              <span class="eyebrow eyebrow--light">مدرسة رواد العلم الأولى</span>
              <h2 id="closing-title">نبدأ من هنا؟</h2>
              <p>افتح بوابة الطالب لمتابعة البيانات الدراسية المنشورة لحسابك.</p>
              <button class="button button--gold" type="button" data-target="login">دخول الطالب <i data-lucide="arrow-up-left"></i></button>
            </div>
            <div class="closing__contact" data-reveal>
              <img src="assets/logo.png" alt="شعار المدرسة" loading="lazy" />
              <span>${schoolProfile.address}</span>
              <a href="tel:${schoolProfile.phone.replace(/[^0-9+]/g, "")}"><i data-lucide="phone"></i>${schoolProfile.phone}</a>
              <a href="mailto:${schoolProfile.email}"><i data-lucide="mail"></i>${schoolProfile.email}</a>
              <a href="${schoolProfile.mapUrl}" target="_blank" rel="noreferrer"><i data-lucide="map-pin"></i>موقع المدرسة</a>
            </div>
            <div class="closing__seal" aria-hidden="true">ر</div>
          </div>
        </section>
      </main>

      <footer class="site-footer">
        <div class="container footer__inner">
          <a class="footer__brand" href="#home" data-target="public-home"><img src="assets/logo.png" alt="" loading="lazy" /><span>${schoolProfile.name}</span></a>
          <p>${schoolProfile.slogan}</p>
          <a class="footer__top" href="#home">العودة للأعلى <i data-lucide="arrow-up"></i></a>
          <small>© ${new Date().getFullYear()} مدرسة رواد العلم الأولى</small>
        </div>
      </footer>
    </div>
  `;
}

function renderLoginPage() {
  return `
    <main class="login-page">
      <header class="login-header container">
        <a class="brand" href="#home" data-target="public-home" aria-label="العودة إلى موقع المدرسة">
          <img src="assets/logo.png" alt="" width="48" height="48" />
          <span class="brand__words"><strong>${schoolProfile.shortName}</strong><small>بوابة الطالب</small></span>
        </a>
        <button class="button button--quiet" type="button" data-target="public-home"><i data-lucide="arrow-right"></i><span>العودة للموقع</span></button>
      </header>
      <div class="login-layout container">
        <section class="login-card" aria-labelledby="login-title" data-reveal>
          <span class="section-index">بوابة رواد العلم <span></span> دخول آمن</span>
          <h1 id="login-title">أهلًا بعودتك.</h1>
          <p class="login-card__intro">استخدم بيانات الدخول التي زوّدتك بها إدارة المدرسة.</p>
          <form data-login-form class="login-form" novalidate>
            <label class="field-label" for="student-number">رقم الطالب</label>
            <div class="input-shell"><i data-lucide="user-round"></i><input id="student-number" type="text" name="studentNumber" inputmode="numeric" autocomplete="username" placeholder="أدخل رقم الطالب" required /></div>
            <label class="field-label" for="student-password">كلمة المرور</label>
            <div class="input-shell input-shell--password"><i data-lucide="key-round"></i><input id="student-password" type="password" name="password" data-password-field autocomplete="current-password" placeholder="أدخل كلمة المرور" required /><label class="password-toggle"><input type="checkbox" data-password-toggle aria-label="إظهار كلمة المرور" /><span>إظهار</span></label></div>
            <div class="login-form__help"><i data-lucide="shield-check"></i><span>لا تشارك كلمة المرور مع الآخرين.</span></div>
            <button class="button button--primary login-submit" type="submit"><i data-lucide="log-in" data-login-spinner></i><span data-login-label>دخول آمن</span></button>
            <p class="form-feedback" data-state="info" role="status" aria-live="polite">تُحمّل بيانات الطالب بعد التحقق من الحساب.</p>
          </form>
          <div class="login-support"><span>تحتاج مساعدة؟</span><a href="mailto:${schoolProfile.email}">تواصل مع إدارة المدرسة</a></div>
        </section>
        <aside class="login-scene" data-parallax-scene data-reveal aria-label="طالبة من مدرسة رواد العلم">
          <div class="login-scene__orbit"></div>
          <span class="login-scene__tag"><i data-lucide="book-open-check"></i> التعلّم يفتح الأبواب</span>
          <img class="login-scene__girl" src="assets/Schoolgirl Character Turnaround Sheet-Photoroom.png" alt="طالبة تحمل كتابًا وترتدي الزي المدرسي" />
          <img class="login-scene__school" src="assets/images/login background.png" alt="مبنى مدرسة رواد العلم الأولى" loading="lazy" />
          <img class="sticker sticker--login" src="${decorativeStickers[4]}" alt="" aria-hidden="true" />
        </aside>
      </div>
      <footer class="login-footer container"><span>${schoolProfile.name}</span><a href="tel:${schoolProfile.phone.replace(/[^0-9+]/g, "")}"><i data-lucide="phone"></i>${schoolProfile.phone}</a></footer>
    </main>
  `;
}

function emptyState(icon, title, description) {
  return `<div class="empty-state"><span class="empty-state__icon"><i data-lucide="${icon}"></i></span><div><strong>${title}</strong><p>${description}</p></div></div>`;
}

function renderPortalHome(student) {
  const attendanceText =
    student.attendance.percent === null
      ? "لا توجد سجلات بعد"
      : `${student.attendance.percent.toLocaleString("ar-LY")}%`;
  return `
    <section class="portal-home" aria-label="ملخص الطالب">
      <div class="portal-home__lead">
        <article class="welcome-panel" data-reveal>
          <span class="welcome-panel__overline">مساحتك الدراسية</span>
          <h2>أهلًا، ${student.name.split(" ")[0]}.</h2>
          <p>${student.stage} <span>·</span> ${student.grade} <span>·</span> ${student.section}</p>
          <button class="text-link" type="button" data-target="page:profile">عرض ملفي <i data-lucide="arrow-up-left"></i></button>
          <span class="welcome-panel__shape" aria-hidden="true"></span>
        </article>
        <article class="metric-note metric-note--attendance" data-reveal>
          <span class="metric-note__icon"><i data-lucide="calendar-check"></i></span>
          <span class="metric-note__label">الحضور المسجل</span>
          <strong>${attendanceText}</strong>
          <small>${student.attendance.recordCount ? "من سجلات القيد الدراسي" : "تظهر النسبة بعد تسجيل الحضور"}</small>
        </article>
        <article class="metric-note metric-note--results" data-reveal>
          <span class="metric-note__icon"><i data-lucide="chart-no-axes-column-increasing"></i></span>
          <span class="metric-note__label">النتائج المنشورة</span>
          <strong>${student.results.length ? student.results.length.toLocaleString("ar-LY") : "—"}</strong>
          <small>${student.results.length ? "مواد لها نتائج معتمدة" : "لا توجد نتائج معتمدة حاليًا"}</small>
        </article>
      </div>

      <div class="portal-home__grid">
        <article class="portal-section portal-section--schedule" data-reveal>
          <div class="portal-section__heading"><div><span class="section-index">اليوم الدراسي</span><h2>على جدول اليوم</h2></div><i data-lucide="calendar-days"></i></div>
          ${
            student.todayAgenda.length
              ? `
            <ol class="today-agenda">${student.todayAgenda
              .map(
                (entry, index) => `
              <li class="agenda-row"><span class="agenda-row__index">${String(index + 1).padStart(2, "0")}</span><span class="agenda-row__time">${entry.time}</span><div><strong>${entry.subject}</strong>${entry.teacher || entry.room ? `<small>${[entry.teacher, entry.room].filter(Boolean).join(" · ")}</small>` : ""}</div></li>
            `,
              )
              .join("")}</ol>
          `
              : emptyState(
                  "calendar-clock",
                  "لا يوجد جدول لليوم",
                  "إذا نُشر جدول الصف فسيظهر هنا.",
                )
          }
          <button class="text-link" type="button" data-target="page:timetable">الجدول الأسبوعي <i data-lucide="arrow-up-left"></i></button>
        </article>

        <article class="portal-section portal-section--results" data-reveal>
          <div class="portal-section__heading"><div><span class="section-index">المواد</span><h2>آخر النتائج</h2></div><i data-lucide="book-open-check"></i></div>
          ${
            student.results.length
              ? `
            <ul class="result-preview">${student.results
              .slice(0, 4)
              .map(
                (result) => `
              <li><span>${result.subject}</span><strong>${result.percentage === null ? result.grade : `${result.percentage.toLocaleString("ar-LY")}%`}</strong></li>
            `,
              )
              .join("")}</ul>
          `
              : emptyState(
                  "chart-no-axes-column-increasing",
                  "لا توجد نتائج معتمدة",
                  "ستظهر هنا بعد اعتمادها من المدرسة.",
                )
          }
          <button class="text-link" type="button" data-target="page:results">كل النتائج <i data-lucide="arrow-up-left"></i></button>
        </article>

        <article class="portal-section portal-section--fees" data-reveal>
          <div class="portal-section__heading"><div><span class="section-index">المتابعة المالية</span><h2>الرسوم</h2></div><i data-lucide="wallet"></i></div>
          ${
            student.feeRecords.length
              ? `
            <ul class="fee-preview">${student.feeRecords
              .slice(0, 3)
              .map(
                (fee) => `
              <li><span>${fee.label}</span><strong>${formatAmount(fee.remaining)}</strong><small>${fee.status}</small></li>
            `,
              )
              .join("")}</ul>
          `
              : emptyState(
                  "wallet",
                  "لا توجد رسوم مسجلة",
                  "لا توجد بنود رسوم مرتبطة بهذا القيد حاليًا.",
                )
          }
          <button class="text-link" type="button" data-target="page:fees">تفاصيل الرسوم <i data-lucide="arrow-up-left"></i></button>
        </article>
      </div>
    </section>
  `;
}

function renderPortalPageMarkup(page, student) {
  if (page === "profile") {
    return `
      <section class="portal-page" aria-labelledby="portal-page-title">
        <header class="portal-page__heading"><span class="section-index">بيانات القيد</span><h2 id="portal-page-title">ملفي الدراسي</h2><p>البيانات الأساسية المرتبطة بحساب الطالب.</p></header>
        <article class="profile-sheet" data-reveal>
          <div class="profile-sheet__monogram" aria-hidden="true">${student.name.slice(0, 1)}</div>
          <div class="profile-sheet__identity"><span>الاسم المسجل</span><h3>${student.name}</h3><p>${student.studentNumber}</p></div>
          <dl class="profile-details">
            <div><dt>المرحلة</dt><dd>${student.stage}</dd></div><div><dt>الصف</dt><dd>${student.grade}</dd></div>
            <div><dt>الشعبة</dt><dd>${student.section}</dd></div><div><dt>السنة الدراسية</dt><dd>${student.academicYear}</dd></div>
          </dl>
        </article>
      </section>
    `;
  }

  if (page === "attendance") {
    return `
      <section class="portal-page" aria-labelledby="portal-page-title">
        <header class="portal-page__heading"><span class="section-index">سجلات القيد</span><h2 id="portal-page-title">الحضور والغياب</h2><p>أحدث سجلات الحضور المرتبطة بالقيد الدراسي.</p></header>
        <div class="attendance-stats">
          <div><span>حاضر</span><strong>${student.attendance.present.toLocaleString("ar-LY")}</strong></div>
          <div><span>تأخر</span><strong>${student.attendance.late.toLocaleString("ar-LY")}</strong></div>
          <div><span>غياب</span><strong>${student.attendance.absent.toLocaleString("ar-LY")}</strong></div>
          <div><span>نسبة الحضور</span><strong>${student.attendance.percent === null ? "—" : `${student.attendance.percent.toLocaleString("ar-LY")}%`}</strong></div>
        </div>
        ${
          student.attendanceRecords.length
            ? `
          <div class="data-table-wrap" data-reveal><table class="data-table"><thead><tr><th scope="col">التاريخ</th><th scope="col">الحالة</th><th scope="col">ملاحظة</th></tr></thead><tbody>
            ${student.attendanceRecords.map((entry) => `<tr><td data-label="التاريخ">${entry.date}</td><td data-label="الحالة"><span class="status-label">${entry.status}</span></td><td data-label="ملاحظة">${entry.lateMinutes ? `${entry.lateMinutes.toLocaleString("ar-LY")} دقيقة تأخير` : "—"}</td></tr>`).join("")}
          </tbody></table></div>
        `
            : emptyState(
                "calendar-x-2",
                "لا توجد سجلات حضور",
                "عند تسجيل بيانات الحضور للقيد ستظهر هنا.",
              )
        }
      </section>
    `;
  }

  if (page === "results") {
    return `
      <section class="portal-page" aria-labelledby="portal-page-title">
        <header class="portal-page__heading"><span class="section-index">بعد الاعتماد</span><h2 id="portal-page-title">النتائج والتقييمات</h2><p>لا تعرض البوابة إلا النتائج المعتمدة من المدرسة.</p></header>
        ${
          student.results.length
            ? `
          <div class="data-table-wrap" data-reveal><table class="data-table"><thead><tr><th scope="col">المادة</th><th scope="col">التقدير</th><th scope="col">النسبة</th></tr></thead><tbody>
            ${student.results.map((result) => `<tr><td data-label="المادة">${result.subject}</td><td data-label="التقدير"><span class="grade-mark">${result.grade}</span></td><td data-label="النسبة">${result.percentage === null ? "—" : `${result.percentage.toLocaleString("ar-LY")}%`}</td></tr>`).join("")}
          </tbody></table></div>
        `
            : emptyState(
                "chart-no-axes-column-increasing",
                "لا توجد نتائج معتمدة بعد",
                "عندما تعتمد المدرسة نتائج الطالب ستظهر في هذا القسم.",
              )
        }
      </section>
    `;
  }

  if (page === "fees") {
    return `
      <section class="portal-page" aria-labelledby="portal-page-title">
        <header class="portal-page__heading"><span class="section-index">بيانات القيد</span><h2 id="portal-page-title">الرسوم والمستحقات</h2><p>ملخص بنود الرسوم المرتبطة بالقيد الدراسي.</p></header>
        ${
          student.feeRecords.length
            ? `
          <div class="data-table-wrap" data-reveal><table class="data-table"><thead><tr><th scope="col">البند</th><th scope="col">الإجمالي</th><th scope="col">المدفوع</th><th scope="col">المتبقي</th><th scope="col">الحالة</th></tr></thead><tbody>
            ${student.feeRecords.map((fee) => `<tr><td data-label="البند">${fee.label}</td><td data-label="الإجمالي">${formatAmount(fee.total)}</td><td data-label="المدفوع">${formatAmount(fee.paid)}</td><td data-label="المتبقي"><strong>${formatAmount(fee.remaining)}</strong></td><td data-label="الحالة"><span class="status-label">${fee.status}</span></td></tr>`).join("")}
          </tbody></table></div>
        `
            : emptyState(
                "wallet",
                "لا توجد بنود رسوم",
                "لا توجد رسوم مرتبطة بهذا القيد في الوقت الحالي.",
              )
        }
      </section>
    `;
  }

  if (page === "timetable") {
    return `
      <section class="portal-page" aria-labelledby="portal-page-title">
        <header class="portal-page__heading"><span class="section-index">العام الدراسي ${student.academicYear}</span><h2 id="portal-page-title">الجدول الدراسي</h2><p>الحصص المنشورة للصف المرتبط بالقيد.</p></header>
        ${
          student.timetable.length
            ? `
          <div class="week-schedule">${student.timetable
            .map(
              (day, index) => `
            <article class="day-sheet" data-reveal style="--entry-index:${index}"><header><span>${String(day.day_number + 1).padStart(2, "0")}</span><h3>${day.day}</h3></header><ol>
              ${day.lessons.map((lesson) => `<li><time>${lesson.time}</time><div><strong>${lesson.subject}</strong><small>${[lesson.period, lesson.teacher, lesson.room].filter(Boolean).join(" · ")}</small></div></li>`).join("")}
            </ol></article>
          `,
            )
            .join("")}</div>
        `
            : emptyState(
                "calendar-days",
                "لم يُنشر جدول الصف بعد",
                "سيظهر الجدول هنا عندما يُضاف إلى النظام.",
              )
        }
      </section>
    `;
  }

  if (page === "platforms") {
    return `<section class="portal-page" aria-labelledby="portal-page-title"><header class="portal-page__heading"><span class="section-index">موارد الطالب</span><h2 id="portal-page-title">الروابط التعليمية</h2><p>روابط الوصول التي تضيفها المدرسة للحساب.</p></header>${emptyState("link-2", "لا توجد روابط مهيأة", "لم تُربط منصات تعليمية بهذا الحساب حتى الآن.")}</section>`;
  }

  return renderPortalHome(student);
}

function renderStudentPortal() {
  const student = state.student;
  const activePage = state.activePanel || "home";
  const activeCard = localPageCards.find((card) => card.page === activePage);
  const title = activeCard?.label || "ملخصي";
  return `
    <div class="student-shell">
      <aside class="portal-sidebar" aria-label="قائمة بوابة الطالب">
        <a class="portal-brand" href="#home" data-target="student-dashboard"><img src="assets/logo.png" alt="" width="46" height="46" /><span><strong>${schoolProfile.shortName}</strong><small>بوابة الطالب</small></span></a>
        <span class="portal-sidebar__label">مساحتي</span>
        <nav class="portal-nav" aria-label="أقسام البوابة">
          ${localPageCards
            .map(
              (card) => `
            <button class="portal-nav__item ${activePage === card.page ? "is-active" : ""}" type="button" data-target="page:${card.page}" ${activePage === card.page ? 'aria-current="page"' : ""}>
              <i data-lucide="${card.icon}"></i><span>${card.label}</span>
            </button>
          `,
            )
            .join("")}
        </nav>
        <div class="portal-sidebar__bottom"><a href="mailto:${schoolProfile.email}"><i data-lucide="circle-help"></i><span>مساعدة</span></a><button class="portal-logout" type="button" data-target="logout"><i data-lucide="log-out"></i><span>تسجيل الخروج</span></button></div>
      </aside>
      <main class="student-main">
        <header class="student-topbar">
          <div><span class="section-index">${title}</span><h1>${activePage === "home" ? "مساحتك الدراسية" : title}</h1></div>
          <div class="student-topbar__actions"><span class="today-date"><i data-lucide="calendar-days"></i>${new Date().toLocaleDateString("ar-LY", { weekday: "long", day: "numeric", month: "long" })}</span><button class="icon-button student-topbar__logout" type="button" data-target="logout" aria-label="تسجيل الخروج"><i data-lucide="log-out"></i></button></div>
        </header>
        <section class="student-identity" aria-label="هوية الطالب">
          <div class="student-identity__monogram" aria-hidden="true">${student.name.slice(0, 1)}</div>
          <div class="student-identity__copy"><strong>${student.name}</strong><span>${student.stage} <b>·</b> ${student.grade} <b>·</b> ${student.section}</span></div>
          <div class="student-identity__year"><span>السنة الدراسية</span><strong>${student.academicYear}</strong></div>
        </section>
        ${renderPortalPageMarkup(activePage, student)}
      </main>
    </div>
  `;
}

mount();
