import {
  schoolProfile,
  publicSections,
  localPageCards,
  decorativeStickers,
  studentFloatingIcons,
  schoolIconConstellations,
} from "./data.js";
import { getSupabaseClient, hasSupabaseConfig } from "./supabase-client.js";
import { supabaseConfig } from "./supabase-config.js";
import {
  normalizeStudentGender,
  studentArtwork,
  studentArtworkInventory,
  studentPortraitFallbacks,
} from "./student-artwork.js";
import {
  buildTimetableGrid,
  mapPortalData as normalizeStudentPortalData,
} from "./student-portal-data.mjs";

const app = document.getElementById("app");
const state = {
  page: "home",
  activePanel: "home",
  loggedIn: false,
  authUser: null,
  student: null,
  sessionNotice: "",
};
const phonePrimaryPortalPages = new Set([
  "home",
  "attendance",
  "results",
  "fees",
]);
const portalRequestTimeout = 15000;
let revealObserver;
let logoutTrigger = null;
let loginInProgress = false;
let logoutInProgress = false;
let authStateSubscription;
let explicitSignOutInProgress = false;

function portalPageFromLocation() {
  const match = window.location.hash.match(/^#student\/([a-z-]+)$/);
  return match && localPageCards.some((card) => card.page === match[1])
    ? match[1]
    : null;
}

function syncPortalLocation(page, replace = false) {
  const hash = `#student/${page}`;
  if (window.location.hash === hash) return;
  const method = replace ? "replaceState" : "pushState";
  window.history[method]({ portalPage: page }, "", hash);
}

function closePortalMoreMenu(restoreFocus = false) {
  const menu = app.querySelector("[data-portal-more-menu]");
  const trigger = app.querySelector("[data-portal-more]");
  if (!menu || menu.hidden) return;
  menu.hidden = true;
  trigger?.setAttribute("aria-expanded", "false");
  if (restoreFocus) trigger?.focus({ preventScroll: true });
}

function scrollPortalToTop() {
  window.scrollTo({
    top: 0,
    behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
      ? "auto"
      : "smooth",
  });
}

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
    answer: `للمساعدة في استعادة الوصول، راسل المدرسة عبر واتساب أو اتصل على ${schoolProfile.phone} أو أرسل بريدًا إلى ${schoolProfile.email}.`,
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

function withRequestTimeout(request, stage, timeoutMs = portalRequestTimeout) {
  const controller = new AbortController();
  let timeoutId;
  const pending = Promise.resolve().then(() => request(controller.signal));
  const timeout = new Promise((_, reject) => {
    timeoutId = window.setTimeout(() => {
      controller.abort();
      reject(new Error(`student_portal:timeout:${stage}`));
    }, timeoutMs);
  });
  return Promise.race([pending, timeout]).finally(() => {
    window.clearTimeout(timeoutId);
  });
}

async function clearLocalSession(client, stage = "auth_cleanup") {
  if (!client) return;
  try {
    await withRequestTimeout(
      () => client.auth.signOut({ scope: "local" }),
      stage,
      5000,
    );
  } catch (error) {
    logPortalDiagnostic(stage, error);
  }
}

function logPortalDiagnostic(stage, error) {
  if (!/^(localhost|127\.0\.0\.1)$/.test(window.location.hostname)) return;
  const code =
    error instanceof Error &&
    /^student_portal:[a-z0-9:_-]+$/i.test(error.message)
      ? error.message
      : typeof error?.diagnosticCode === "string" &&
          /^[a-z0-9_-]{1,32}$/i.test(error.diagnosticCode)
        ? error.diagnosticCode
        : error?.name === "AbortError"
          ? "request_aborted"
          : error instanceof Error &&
              ["Failed to fetch", "Load failed"].includes(error.message)
            ? "network_error"
            : error instanceof Error &&
                /^[A-Z][A-Za-z0-9]{0,31}$/.test(error.name)
              ? error.name
              : "unclassified_error";
  const status = Number.isInteger(error?.status) ? error.status : undefined;
  console.warn("[student-portal] Request failed", {
    stage,
    code,
    ...(status ? { status } : {}),
  });
}

function diagnosticError(message, providerError) {
  const error = new Error(message);
  if (
    typeof providerError?.code === "string" &&
    /^[a-z0-9_-]{1,32}$/i.test(providerError.code)
  ) {
    error.diagnosticCode = providerError.code;
  }
  if (Number.isInteger(providerError?.status)) {
    error.status = providerError.status;
  }
  return error;
}

function isExpiredSessionError(error) {
  return (
    error?.status === 401 ||
    ["PGRST301", "PGRST302", "invalid_token", "jwt_expired"].includes(
      error?.diagnosticCode,
    )
  );
}

function monitorAuthState(client) {
  if (authStateSubscription) return;
  const { data } = client.auth.onAuthStateChange((event) => {
    if (event !== "SIGNED_OUT" || !state.loggedIn || explicitSignOutInProgress)
      return;
    state.student = null;
    state.authUser = null;
    state.loggedIn = false;
    state.page = "login";
    state.activePanel = "home";
    state.sessionNotice = "انتهت الجلسة. سجّل الدخول مجددًا للمتابعة.";
    renderApp();
  });
  authStateSubscription = data?.subscription;
}

function formatAmount(amount) {
  return `${Number(amount ?? 0).toLocaleString("ar-LY", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })} د.ل`;
}

function normalizeWhatsAppPhone(phone, countryCode) {
  const callingCode = String(countryCode ?? "").replace(/\D/g, "");
  let number = String(phone ?? "").replace(/\D/g, "");
  if (!callingCode || !number) return null;
  if (number.startsWith("00")) number = number.slice(2);
  if (!number.startsWith(callingCode)) {
    number = number.replace(/^0+/, "");
    number = `${callingCode}${number}`;
  }
  return number.length >= 8 && number.length <= 15 ? number : null;
}

function schoolWhatsAppUrl(context = "أحد الأمور المدرسية") {
  const phone = normalizeWhatsAppPhone(
    schoolProfile.phone,
    schoolProfile.phoneCountryCode,
  );
  if (!phone) return null;
  const message = `السلام عليكم، أود التواصل مع مدرسة رواد العلم الأولى بخصوص ${context}.`;
  return `https://wa.me/${phone}?text=${encodeURIComponent(message)}`;
}

function renderWhatsAppLink(
  label,
  context,
  className = "whatsapp-link",
  artwork = null,
) {
  const href = schoolWhatsAppUrl(context);
  const icon = '<i data-lucide="message-circle" aria-hidden="true"></i>';
  const motif = artwork
    ? studentFloatingIcon(artwork, "whatsapp-link__art")
    : "";
  if (!href) {
    return `<span class="${className} is-unavailable" aria-disabled="true">${icon}<span>رقم التواصل غير مهيأ</span></span>`;
  }
  return `<a class="${className}" href="${href}" target="_blank" rel="noopener noreferrer">${icon}<span>${escapeHTML(label)}</span><i class="whatsapp-link__arrow" data-lucide="arrow-up-left" aria-hidden="true"></i>${motif}</a>`;
}

const iconConstellationPaths = new Set(
  Object.values(schoolIconConstellations).flat(),
);
const iconConstellationSlots = [
  { left: "7%", top: "13%", size: "34px", rotate: "-12deg" },
  { left: "24%", top: "7%", size: "23px", rotate: "9deg" },
  { left: "79%", top: "12%", size: "29px", rotate: "-7deg" },
  { left: "91%", top: "45%", size: "22px", rotate: "12deg" },
  { left: "12%", top: "74%", size: "26px", rotate: "7deg" },
  { left: "68%", top: "82%", size: "31px", rotate: "-9deg" },
];

function renderIconConstellation(icons, variant) {
  const decorations = icons
    .filter((icon) => iconConstellationPaths.has(icon))
    .map((icon, index) => {
      const slot =
        iconConstellationSlots[index % iconConstellationSlots.length];
      return `<img class="icon-constellation__icon" src="${escapeHTML(icon)}" alt="" loading="lazy" decoding="async" style="--icon-left:${slot.left};--icon-top:${slot.top};--icon-size:${slot.size};--icon-rotate:${slot.rotate};--icon-delay:${index * -420}ms" />`;
    })
    .join("");
  return `<div class="icon-constellation icon-constellation--${variant}" aria-hidden="true">${decorations}</div>`;
}

function mapPortalData(data) {
  return normalizeStudentPortalData(data);
}

async function loadStudentPortal(client) {
  const { data: sessionData, error: sessionError } = await withRequestTimeout(
    (signal) => client.rpc("student_portal_session").abortSignal(signal),
    "student_portal_session",
  );
  if (sessionError)
    throw diagnosticError(
      "student_portal:session_request_failed",
      sessionError,
    );
  if (!sessionData?.student?.id)
    throw new Error("student_portal:account_not_linked");

  const portalResult = await withRequestTimeout(
    (signal) => client.rpc("student_portal_data").abortSignal(signal),
    "student_portal_data",
  );
  const { data, error } = portalResult;
  if (error) throw diagnosticError("student_portal:data_request_failed", error);
  if (!data?.student?.id)
    throw new Error("student_portal:record_not_available");
  if (data.student.id !== sessionData.student.id)
    throw new Error("student_portal:identity_mismatch");
  let student;
  try {
    student = mapPortalData(data);
  } catch (error) {
    logPortalDiagnostic("student_portal_mapping", error);
    throw new Error("student_portal:data_mapping_failed");
  }
  if (
    /^(localhost|127\.0\.0\.1)$/.test(window.location.hostname) &&
    (student.timetableIssues.missingSubject ||
      student.timetableIssues.unplacedLesson)
  ) {
    console.warn("[student-portal] Timetable rows need data review", {
      missingSubjectCount: student.timetableIssues.missingSubject,
      unplacedLessonCount: student.timetableIssues.unplacedLesson,
    });
  }
  student.gender = normalizeStudentGender(student.gender);
  student.photoUrl = null;
  student.hasPhotoReference = false;
  return student;
}

function studentPortalFailureMessage(error) {
  const code = error instanceof Error ? error.message : "";
  if (code === "student_portal:account_not_linked") {
    return "تم التحقق من كلمة المرور، لكن حساب الدخول غير مربوط بملف طالب نشط. يُرجى من إدارة المدرسة مراجعة ربط حساب البوابة.";
  }
  if (code === "student_portal:session_request_failed") {
    return "تم التحقق من الدخول، لكن تعذر التحقق من صلاحية ربط الحساب. أعد المحاولة، وإن استمرت المشكلة فتواصل مع إدارة المدرسة.";
  }
  if (code === "student_portal:record_not_available") {
    return "تم التعرف على الحساب، لكن ملف الطالب غير متاح للبوابة. يُرجى من إدارة المدرسة مراجعة القيد ونشر بيانات البوابة.";
  }
  if (code === "student_portal:identity_mismatch") {
    return "تعذر مطابقة ملف الطالب مع جلسة الدخول. أوقفنا فتح البوابة حفاظًا على خصوصية البيانات؛ تواصل مع إدارة المدرسة.";
  }
  if (code === "student_portal:data_request_failed") {
    return "تم التحقق من الدخول، لكن تعذر تحميل بيانات الطالب حاليًا. أعد المحاولة، وإن استمرت المشكلة فتواصل مع إدارة المدرسة.";
  }
  if (code === "student_portal:data_mapping_failed") {
    return "تم التحقق من الدخول، لكن تعذر تجهيز بيانات البوابة. أعد المحاولة، وإن استمرت المشكلة فتواصل مع إدارة المدرسة.";
  }
  if (code === "student_portal:client_unavailable") {
    return "تعذر تهيئة خدمة الدخول. تحقق من الاتصال أو تواصل مع إدارة المدرسة.";
  }
  if (code.startsWith("student_portal:timeout:")) {
    if (code.endsWith(":student_login")) {
      return "تأخر التحقق من بيانات الدخول. تحقق من الاتصال ثم أعد المحاولة.";
    }
    return "استغرق تحميل البوابة وقتًا أطول من المتوقع. تحقق من الاتصال ثم أعد المحاولة.";
  }
  return "تم التحقق من الدخول، لكن تعذر تحميل البوابة. يُرجى المحاولة لاحقًا أو التواصل مع إدارة المدرسة.";
}

function safeStudentPhotoUrl(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  const candidate = value.trim();
  try {
    const url = new URL(candidate);
    const projectUrl = new URL(supabaseConfig.url);
    if (
      url.protocol === "https:" &&
      url.origin === projectUrl.origin &&
      /^\/storage\/v1\/object\/sign\/photos\//.test(url.pathname)
    ) {
      return url.href;
    }
  } catch {
    return null;
  }
  return null;
}

async function hydrateStudentPhoto(client, student, isRefresh = false) {
  if (!student?.hasPhotoReference) return false;
  try {
    const { data, error } = await withRequestTimeout(
      (signal) => client.functions.invoke("student-avatar", { signal }),
      "student_avatar",
    );
    if (error) {
      logPortalDiagnostic(
        "student_avatar",
        diagnosticError("student_portal:avatar_request_failed", error),
      );
      return false;
    }
    const signedUrl = safeStudentPhotoUrl(data?.image_url);
    if (!signedUrl) {
      logPortalDiagnostic(
        "student_avatar",
        new Error("student_portal:avatar_url_unavailable"),
      );
      return false;
    }
    if (state.student !== student) return false;
    student.photoUrl = signedUrl;
    app.querySelectorAll("[data-student-portrait]").forEach((image) => {
      image.dataset.fallbackApplied = "false";
      if (!isRefresh) image.dataset.photoRefreshAttempted = "false";
      image
        .closest(".student-photo-frame")
        ?.classList.remove("is-image-unavailable");
      image
        .closest(".student-photo-frame")
        ?.setAttribute("data-avatar-kind", "personal");
      image.dataset.fallbackSrc =
        studentPortraitFallbacks[student.gender] ||
        studentPortraitFallbacks.unknown;
      image.dataset.fallbackAlt =
        student.gender === "unknown"
          ? "مجموعة محايدة من طلاب المدرسة"
          : "رسم افتراضي للطالب";
      image.alt = "الصورة الشخصية للطالب";
      image.src = signedUrl;
    });
    return true;
  } catch (error) {
    // Keep the local gender-specific portrait when signing is unavailable.
    logPortalDiagnostic("student_avatar", error);
    return false;
  }
}

async function hydrateStudentIdentity(client, student) {
  try {
    const { data, error } = await withRequestTimeout(
      (signal) => client.rpc("student_portal_identity").abortSignal(signal),
      "student_portal_identity",
    );
    if (error)
      throw diagnosticError("student_portal:identity_request_failed", error);
    if (state.student !== student) return;

    const identity = data?.student ?? null;
    student.gender = normalizeStudentGender(identity?.gender);
    // Stored paths are never rendered directly; the Edge Function signs only
    // a path resolved from this authenticated student's identity.
    student.photoUrl = null;
    student.hasPhotoReference = Boolean(
      identity &&
      [
        identity.avatar_storage_path,
        identity.photo_storage_path,
        identity.avatar_path,
        identity.photo_path,
      ].some((value) => typeof value === "string" && value.trim()),
    );

    const fallback =
      studentPortraitFallbacks[student.gender] ||
      studentPortraitFallbacks.unknown;
    const fallbackAlt =
      student.gender === "unknown"
        ? "مجموعة محايدة من طلاب المدرسة"
        : "رسم افتراضي للطالب";
    app.querySelectorAll("[data-student-portrait]").forEach((image) => {
      image.dataset.fallbackSrc = fallback;
      image.dataset.fallbackAlt = fallbackAlt;
      image.dataset.fallbackApplied = "true";
      image.dataset.photoRefreshAttempted = "false";
      image
        .closest(".student-photo-frame")
        ?.setAttribute("data-avatar-kind", student.gender);
      image.alt = fallbackAlt;
      image.src = fallback;
    });

    if (student.hasPhotoReference) {
      await hydrateStudentPhoto(client, student);
    }
  } catch (error) {
    // Identity and portrait enrichment are optional; core student data is already rendered.
    logPortalDiagnostic("student_portal_identity", error);
  }
}

function setLoginFieldState(field, isError) {
  const shell = field.closest(".input-shell");
  if (shell) {
    shell.classList.toggle("is-invalid", isError);
  }
  field.setAttribute("aria-invalid", String(isError));
}

function clearLoginFeedback(form) {
  state.sessionNotice = "";
  const feedback = form.querySelector(".form-feedback");
  if (feedback) {
    feedback.textContent = "تُحمّل بيانات الطالب بعد التحقق من الحساب.";
    feedback.dataset.state = "info";
  }
  const fields = form.querySelectorAll(
    'input[name="studentNumber"], input[name="password"]',
  );
  fields.forEach((field) => setLoginFieldState(field, false));
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
  let client;
  try {
    client = await withRequestTimeout(
      () => getSupabaseClient(),
      "supabase_client",
    );
    if (!client) return;
    monitorAuthState(client);
    const {
      data: { session },
    } = await withRequestTimeout(
      () => client.auth.getSession(),
      "auth_session_restore",
    );
    if (!session) return;
    state.student = await loadStudentPortal(client);
    state.authUser = session.user;
    state.loggedIn = true;
    state.sessionNotice = "";
    state.activePanel = portalPageFromLocation() || "home";
    state.page = "student";
    syncPortalLocation(state.activePanel, true);
    renderApp();
    void hydrateStudentIdentity(client, state.student);
  } catch (error) {
    // Preserve cached auth during temporary network or RPC outages, but never show an unvalidated portal.
    state.student = null;
    state.authUser = null;
    state.loggedIn = false;
    const sessionExpired = isExpiredSessionError(error);
    state.page = sessionExpired ? "login" : "home";
    state.activePanel = "home";
    state.sessionNotice = sessionExpired
      ? "انتهت الجلسة. سجّل الدخول مجددًا للمتابعة."
      : "";
    if (sessionExpired) {
      await clearLocalSession(client, "expired_session_cleanup");
    }
    try {
      renderApp();
    } catch {
      // Keep the public page available if the portal renderer itself failed.
    }
    logPortalDiagnostic("session_restore", error);
  }
}

function bindGlobalEvents() {
  document.addEventListener("error", handleStudentPortraitError, true);

  document.addEventListener("click", (event) => {
    const logoutDialog = app.querySelector("[data-logout-dialog]");
    if (event.target.closest("[data-logout-cancel]")) {
      dismissLogoutConfirmation(logoutDialog, "stay");
      return;
    }
    if (event.target.closest("[data-logout-confirm]")) {
      dismissLogoutConfirmation(logoutDialog, "logout");
      void logout();
      return;
    }
    if (event.target === logoutDialog) {
      dismissLogoutConfirmation(logoutDialog, "stay");
      return;
    }

    const moreTrigger = event.target.closest("[data-portal-more]");
    if (moreTrigger) {
      const menu = app.querySelector("[data-portal-more-menu]");
      const isOpening = Boolean(menu?.hidden);
      if (menu) menu.hidden = !isOpening;
      moreTrigger.setAttribute("aria-expanded", String(isOpening));
      if (isOpening) {
        menu?.querySelector("button")?.focus({ preventScroll: true });
      }
      return;
    }
    if (!event.target.closest("[data-portal-more-menu]")) {
      closePortalMoreMenu();
    }

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
    if (trigger instanceof HTMLAnchorElement) event.preventDefault();
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
      window.history.replaceState({}, "", "#home");
      renderApp();
      scrollPortalToTop();
    } else if (target === "student-dashboard") {
      if (!state.loggedIn || !state.student) return;
      state.page = "student";
      state.activePanel = "home";
      syncPortalLocation("home");
      renderApp();
      scrollPortalToTop();
    } else if (target === "logout") {
      openLogoutConfirmation(trigger);
    } else if (target.startsWith("page:")) {
      if (!state.loggedIn || !state.student) return;
      const page = target.slice("page:".length);
      if (!localPageCards.some((card) => card.page === page)) return;
      state.activePanel = page;
      state.page = "student";
      syncPortalLocation(page);
      renderApp();
      scrollPortalToTop();
    }
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!form.matches("[data-login-form]")) return;
    event.preventDefault();
    void submitLogin(form);
  });

  document.addEventListener("input", (event) => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement)) return;
    const form = target.closest("[data-login-form]");
    if (!form) return;
    clearLoginFeedback(form);
    if (target.name === "studentNumber" || target.name === "password") {
      setLoginFieldState(target, false);
    }
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
    if (event.key !== "Escape") return;
    const moreMenu = app.querySelector("[data-portal-more-menu]");
    if (moreMenu && !moreMenu.hidden) {
      event.preventDefault();
      closePortalMoreMenu(true);
      return;
    }
    const logoutDialog = app.querySelector("[data-logout-dialog]");
    if (logoutDialog?.open) {
      event.preventDefault();
      dismissLogoutConfirmation(logoutDialog, "stay");
      return;
    }
    closeMobileNav();
  });

  window.addEventListener("popstate", () => {
    if (state.loggedIn && state.student) {
      state.page = "student";
      state.activePanel = portalPageFromLocation() || "home";
      closePortalMoreMenu();
      renderApp();
      scrollPortalToTop();
      return;
    }
    if (state.page === "login") {
      state.page = "home";
      state.sessionNotice = "";
      renderApp();
    }
  });
}

function openLogoutConfirmation(trigger) {
  const dialog = app.querySelector("[data-logout-dialog]");
  if (!dialog || dialog.open) return;

  if (dialog.dataset.cancelBound !== "true") {
    dialog.addEventListener("cancel", (event) => {
      event.preventDefault();
      dismissLogoutConfirmation(dialog, "stay");
    });
    dialog.dataset.cancelBound = "true";
  }

  logoutTrigger = trigger;
  dialog.addEventListener(
    "close",
    () => {
      if (dialog.returnValue !== "logout") {
        restoreLogoutFocus();
      } else {
        logoutTrigger = null;
      }
    },
    { once: true },
  );
  dialog.showModal();
  dialog.querySelector("[data-logout-cancel]")?.focus({ preventScroll: true });
}

function dismissLogoutConfirmation(dialog, returnValue) {
  if (!dialog?.open) return;
  dialog.close(returnValue);
  if (returnValue !== "logout") restoreLogoutFocus();
}

function restoreLogoutFocus() {
  const trigger =
    logoutTrigger?.isConnected && logoutTrigger.getClientRects().length
      ? logoutTrigger
      : [...app.querySelectorAll('[data-target="logout"]')].find(
          (candidate) => candidate.getClientRects().length,
        );
  logoutTrigger = null;
  if (!trigger?.isConnected) return;
  trigger.focus({ preventScroll: true });
  window.setTimeout(() => trigger.focus({ preventScroll: true }), 0);
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
  if (loginInProgress) return;
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
    setLoginFieldState(input, !username);
    setLoginFieldState(password, !secret);
    if (!username) input.focus();
    else password.focus();
    return;
  }
  if (!hasSupabaseConfig()) {
    feedback.textContent =
      "إعداد الاتصال بالبوابة غير مكتمل. تواصل مع إدارة المدرسة.";
    feedback.dataset.state = "error";
    setLoginFieldState(input, true);
    setLoginFieldState(password, true);
    return;
  }

  submitButton.disabled = true;
  loginInProgress = true;
  submitButton.setAttribute("aria-busy", "true");
  submitButton.classList.add("is-loading");
  submitLabel.textContent = "جارٍ التحقق";
  feedback.textContent = "نتحقق من بيانات الدخول بأمان…";
  feedback.dataset.state = "info";
  state.sessionNotice = "";
  setLoginFieldState(input, false);
  setLoginFieldState(password, false);
  refreshIcons();

  let client;
  let stage = "supabase_client";
  let sessionTouched = false;
  let portalStateAssigned = false;
  let failureMessage =
    "تعذر الاتصال بخدمة البوابة. تحقق من اتصال الإنترنت أو تواصل مع إدارة المدرسة.";
  try {
    client = await withRequestTimeout(
      () => getSupabaseClient(),
      "supabase_client",
    );
    if (!client) throw new Error("student_portal:client_unavailable");
    monitorAuthState(client);

    stage = "student_login";
    const { data: loginData, error: loginError } = await withRequestTimeout(
      (signal) =>
        client.functions.invoke("student-login", {
          body: { student_number: username, password: secret },
          signal,
        }),
      "student_login",
    );

    if (loginError || !loginData?.access_token || !loginData?.refresh_token) {
      try {
        const response = loginError?.context;
        if (response instanceof Response) {
          const body = await response.clone().json();
          if (typeof body?.error === "string") failureMessage = body.error;
        }
      } catch {
        // Keep network/provider details out of the login form.
      }
      if (loginError?.status === 401) setLoginFieldState(password, true);
      throw diagnosticError("login_failed", loginError);
    }

    stage = "auth_session";
    failureMessage =
      "تم التحقق من بيانات الدخول، لكن تعذر تهيئة جلسة آمنة. أعد المحاولة أو تواصل مع إدارة المدرسة.";
    submitLabel.textContent = "جارٍ فتح البوابة";
    sessionTouched = true;
    const { data: authData, error: sessionError } =
      await client.auth.setSession({
        access_token: loginData.access_token,
        refresh_token: loginData.refresh_token,
      });
    if (sessionError || !authData?.session || !authData?.user) {
      throw new Error("login_session_unavailable");
    }

    stage = "student_portal";
    failureMessage =
      "تم التحقق من الدخول، لكن تعذر تحميل البوابة حاليًا. أعد المحاولة، وإن استمرت المشكلة فتواصل مع إدارة المدرسة.";
    const studentData = await loadStudentPortal(client);

    if (!form.isConnected) {
      await clearLocalSession(client);
      return;
    }

    stage = "student_portal_render";
    state.student = studentData;
    state.authUser = authData.user;
    state.loggedIn = true;
    state.activePanel = "home";
    state.page = "student";
    portalStateAssigned = true;
    syncPortalLocation("home", true);
    renderApp();
    void hydrateStudentIdentity(client, state.student);
  } catch (error) {
    logPortalDiagnostic(stage, error);
    if (error instanceof Error && error.message.startsWith("student_portal:")) {
      failureMessage = studentPortalFailureMessage(error);
    }
    if (portalStateAssigned) {
      state.student = null;
      state.authUser = null;
      state.loggedIn = false;
      state.activePanel = "home";
      state.page = "login";
      try {
        renderApp();
      } catch {
        app.innerHTML = renderLoginPage();
      }
    }
    if (sessionTouched) {
      await clearLocalSession(client);
    }
    const visibleFeedback =
      state.page === "login"
        ? app.querySelector(".form-feedback") || feedback
        : null;
    if (visibleFeedback) {
      visibleFeedback.textContent = failureMessage;
      visibleFeedback.dataset.state = "error";
    }
  } finally {
    loginInProgress = false;
    if (form.isConnected && state.page === "login") {
      submitButton.disabled = false;
      submitButton.removeAttribute("aria-busy");
      submitButton.classList.remove("is-loading");
      submitLabel.textContent = "دخول آمن";
      refreshIcons();
    }
  }
}

async function logout() {
  if (logoutInProgress) return;
  logoutInProgress = true;
  let client;
  explicitSignOutInProgress = true;
  try {
    client = await withRequestTimeout(
      () => getSupabaseClient(),
      "supabase_client",
    );
    if (client) {
      await withRequestTimeout(() => client.auth.signOut(), "sign_out");
    }
  } catch {
    await clearLocalSession(client, "logout_cleanup");
  } finally {
    explicitSignOutInProgress = false;
    logoutInProgress = false;
  }
  state.student = null;
  state.authUser = null;
  state.loggedIn = false;
  state.page = "home";
  state.activePanel = "home";
  state.sessionNotice = "";
  window.history.replaceState({}, "", "#home");
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

            <div class="hero-scene" data-parallax-scene data-reveal aria-label="طالب وطالبة من مدرسة رواد العلم">
              <div class="hero-scene__paper"></div>
              <div class="hero-scene__sun" aria-hidden="true"></div>
              <div class="hero-scene__label hero-scene__label--top"><i data-lucide="book-open-check"></i><span>نتعلّم معًا</span></div>
              <img class="hero-scene__character hero-scene__character--girl" src="assets/images/Schoolgirl-Side-Swept-Hair-Holding-Sign-Looking-Left.png" alt="طالبة من المدرسة تحمل لوحة" fetchpriority="high" />
              <img class="hero-scene__character hero-scene__character--boy" src="assets/images/Schoolboy-Standing-Holding-Sign-Looking-Right.png" alt="طالب من المدرسة يحمل لوحة" fetchpriority="high" />
              <img class="sticker sticker--sun" src="${decorativeStickers[0]}" alt="" aria-hidden="true" />
              <img class="sticker sticker--heart" src="${decorativeStickers[1]}" alt="" aria-hidden="true" />
              <img class="sticker sticker--flower" src="${decorativeStickers[2]}" alt="" aria-hidden="true" />
              <div class="hero-scene__label hero-scene__label--bottom"><i data-lucide="calendar-days"></i><span>مساحة لكل طالب</span></div>
              <span class="scene-caption">رحلة واحدة، وأحلام كثيرة.</span>
            </div>
          </div>
          <a class="scroll-cue" href="#school"><span>اكتشف المدرسة</span><i data-lucide="arrow-down"></i></a>
        </section>

        <section class="school-story section-space" id="school" aria-labelledby="school-title">
          ${renderIconConstellation(schoolIconConstellations.school, "school")}
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
          ${renderIconConstellation(schoolIconConstellations.portal, "portal")}
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
                  <div class="feature-preview__text">
                    <span class="feature-preview__note" data-feature-preview-note>${initialFeature.note}</span>
                    <h3 data-feature-preview-title>${initialFeature.title}</h3>
                    <p data-feature-preview-body>${initialFeature.description}</p>
                  </div>
                  ${studentArtworkImage(studentArtwork.pages.attendance.active, "feature-preview__character")}
                </div>
              </article>
            </div>
          </div>
        </section>

        <section class="journey section-space" id="journey" aria-labelledby="journey-title">
          ${renderIconConstellation(schoolIconConstellations.journey, "journey")}
          <div class="container journey__layout">
            <div class="journey__art" data-reveal>
              <div class="journey__frame"></div>
              <img src="${escapeHTML(studentArtwork.schoolyardScene)}" alt="مجموعة من طلاب وطالبات المدرسة في ساحة التعلّم" loading="lazy" decoding="async" />
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
          ${renderIconConstellation(schoolIconConstellations.stages, "stages")}
          <div class="container">
            <div class="section-heading section-heading--center" data-reveal>
              <span class="section-index">04 <span></span> المراحل</span>
              <div class="stage-heading__lockup">
                ${studentArtworkImage(studentArtwork.home.schedule.empty, "stage-heading__character")}
                <h2 id="stages-title">لكل مرحلة،<br /><em>بدايتها الجميلة.</em></h2>
              </div>
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
              ${renderWhatsAppLink("اسأل المدرسة عبر واتساب", "استفسار عام", "whatsapp-link whatsapp-link--section", studentFloatingIcons.contact)}
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
              <div class="closing__characters" aria-hidden="true">
                ${studentArtworkImage(studentArtwork.pages.timetable.active, "closing__character closing__character--runner")}
                ${studentArtworkImage(studentArtwork.pages.results, "closing__character closing__character--ball")}
              </div>
            </div>
            <div class="closing__contact" data-reveal>
              <img src="assets/logo.png" alt="شعار المدرسة" loading="lazy" />
              <span>${schoolProfile.address}</span>
              ${renderWhatsAppLink("ابدأ محادثة واتساب", "استفسار عام", "whatsapp-link whatsapp-link--closing", studentFloatingIcons.contact)}
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
          <div class="footer__developer"><span>تطوير الموقع <strong dir="ltr">Danya Musbah</strong></span><a href="mailto:danyamusbah8@gmail.com"><i data-lucide="mail" aria-hidden="true"></i><span dir="ltr">danyamusbah8@gmail.com</span></a></div>
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
            <button class="button button--primary login-submit" type="submit"><img class="login-submit__logo" src="assets/logo.png" alt="" aria-hidden="true" /><i class="login-submit__icon" data-lucide="log-in" aria-hidden="true"></i><span data-login-label>دخول آمن</span></button>
            <p class="form-feedback" data-state="${state.sessionNotice ? "error" : "info"}" role="status" aria-live="polite">${escapeHTML(state.sessionNotice || "تُحمّل بيانات الطالب بعد التحقق من الحساب.")}</p>
          </form>
          <div class="login-support"><span>تحتاج مساعدة؟</span>${renderWhatsAppLink("تواصل مع المدرسة عبر واتساب", "المساعدة في الدخول إلى البوابة", "whatsapp-link whatsapp-link--login", studentFloatingIcons.contact)}</div>
        </section>
        <aside class="login-scene" data-parallax-scene data-reveal aria-label="طالب وطالبة من مدرسة رواد العلم">
          ${renderIconConstellation(schoolIconConstellations.school.slice(0, 3), "login")}
          <div class="login-scene__orbit"></div>
          <span class="login-scene__tag"><i data-lucide="book-open-check"></i> التعلّم يفتح الأبواب</span>
          <img class="login-scene__girl" src="assets/images/Schoolgirl-Standing-Holding-Sign-Looking-Left.png" alt="طالبة تحمل لوحة وترتدي الزي المدرسي" />
          <img class="login-scene__boy" src="assets/images/Schoolboy-Curly-Hair-Smiling-Waving-Looking-Right.png" alt="طالب يرحب بعودتك إلى بوابة المدرسة" fetchpriority="high" />
          <img class="sticker sticker--login" src="${decorativeStickers[4]}" alt="" aria-hidden="true" />
        </aside>
      </div>
      <footer class="login-footer container"><span>${schoolProfile.name}</span><a href="tel:${schoolProfile.phone.replace(/[^0-9+]/g, "")}"><i data-lucide="phone"></i>${schoolProfile.phone}</a></footer>
    </main>
  `;
}

const studentArtworkPaths = new Set(
  studentArtworkInventory.map((asset) => asset.path),
);
const floatingIconPaths = new Set(Object.values(studentFloatingIcons));

function studentArtworkImage(source, className, loading = "lazy") {
  if (!studentArtworkPaths.has(source)) return "";
  return `<img class="${className}" src="${escapeHTML(source)}" alt="" aria-hidden="true" loading="${loading}" decoding="async" />`;
}

function studentFloatingIcon(source, className, loading = "lazy") {
  if (!floatingIconPaths.has(source)) return "";
  return `<img class="${className}" src="${escapeHTML(source)}" alt="" aria-hidden="true" loading="${loading}" decoding="async" />`;
}

function emptyState(icon, title, description, illustration = null) {
  const visual = illustration
    ? studentArtworkImage(illustration, "empty-state__art")
    : `<span class="empty-state__icon"><i data-lucide="${icon}"></i></span>`;
  return `<div class="empty-state ${illustration ? "empty-state--illustrated" : ""}">${visual}<div><strong>${title}</strong><p>${description}</p></div></div>`;
}

function greetingForNow() {
  const hour = new Date().getHours();
  if (hour < 11) return "صباحٌ مليء بالبدايات الجميلة.";
  if (hour < 16) return "نتمنى لك يومًا دراسيًا مليئًا بالاكتشاف.";
  if (hour < 21) return "مساءٌ هادئ بعد يوم من التعلّم.";
  return "أهلًا بعودتك إلى مساحتك الدراسية.";
}

function studentAvatar(student, className = "student-avatar") {
  const initial = student.name.trim().slice(0, 1) || "ط";
  return `<span class="${className}" aria-hidden="true"><span>${initial}</span><i data-lucide="sparkles"></i></span>`;
}

function studentPortraitMarkup(student, placement, loading = "lazy") {
  const gender = normalizeStudentGender(student.gender);
  const fallback =
    studentPortraitFallbacks[gender] || studentPortraitFallbacks.unknown;
  const photoUrl = safeStudentPhotoUrl(student.photoUrl);
  const hasPersonalPhoto = Boolean(photoUrl);
  const alt = hasPersonalPhoto
    ? "الصورة الشخصية للطالب"
    : gender === "unknown"
      ? "مجموعة محايدة من طلاب المدرسة"
      : "رسم افتراضي للطالب";
  const fallbackAlt =
    gender === "unknown"
      ? "مجموعة محايدة من طلاب المدرسة"
      : "رسم افتراضي للطالب";
  const initial = student.name.trim().slice(0, 1) || "ط";
  const source = photoUrl || fallback;

  return `
    <figure class="student-photo-frame student-photo-frame--${placement}" data-avatar-kind="${hasPersonalPhoto ? "personal" : gender}" data-fallback-initial="${escapeHTML(initial)}">
      <img class="student-photo-frame__image" src="${escapeHTML(source)}" alt="${alt}" loading="${loading}" decoding="async" data-student-portrait data-fallback-src="${escapeHTML(fallback)}" data-fallback-alt="${fallbackAlt}" data-fallback-applied="${hasPersonalPhoto ? "false" : "true"}" />
    </figure>
  `;
}

function renderStudyPageHeading(
  eyebrow,
  title,
  description,
  illustration,
  floatingIcon,
) {
  return `
    <header class="study-page__heading" data-reveal>
      ${floatingIcon ? studentFloatingIcon(floatingIcon, "study-page__floating-icon") : ""}
      <div class="study-page__heading-copy">
        <span class="study-page__eyebrow">${eyebrow}</span>
        <h2 id="portal-page-title">${title}</h2>
        <p>${description}</p>
      </div>
      ${illustration ? studentArtworkImage(illustration, "study-page__illustration") : ""}
    </header>
  `;
}

function handleStudentPortraitError(event) {
  const image = event.target;
  if (
    !(image instanceof HTMLImageElement) ||
    !image.matches("[data-student-portrait]")
  )
    return;
  const student = state.student;
  const frame = image.closest(".student-photo-frame");
  if (
    frame?.dataset.avatarKind === "personal" &&
    image.dataset.photoRefreshAttempted !== "true" &&
    student?.hasPhotoReference
  ) {
    image.dataset.photoRefreshAttempted = "true";
    logPortalDiagnostic(
      "student_portrait_load",
      new Error("student_portal:portrait_load_failed"),
    );
    void getSupabaseClient()
      .then(async (client) =>
        client ? hydrateStudentPhoto(client, student, true) : false,
      )
      .then((refreshed) => {
        if (!refreshed && image.isConnected) {
          handleStudentPortraitError({ target: image });
        }
      })
      .catch((error) => {
        logPortalDiagnostic("student_avatar_refresh", error);
        if (image.isConnected) handleStudentPortraitError({ target: image });
      });
    return;
  }
  const fallback = image.dataset.fallbackSrc;
  if (image.dataset.fallbackApplied !== "true" && fallback) {
    image.dataset.fallbackApplied = "true";
    image.alt = image.dataset.fallbackAlt || "رسم افتراضي للطالب";
    image
      .closest(".student-photo-frame")
      ?.setAttribute("data-avatar-kind", "fallback");
    image.src = fallback;
    return;
  }
  image.closest(".student-photo-frame")?.classList.add("is-image-unavailable");
}

function renderProgress(value, label) {
  const progress = Math.min(100, Math.max(0, Number(value) || 0));
  return `<div class="study-progress" role="progressbar" aria-label="${label}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${progress}"><span style="--progress:${progress}%"></span></div>`;
}

function renderPortalHome(student) {
  const attendancePercent =
    student.attendance.percent === null
      ? null
      : Math.min(100, Math.max(0, student.attendance.percent));
  const feeTotals = student.feeRecords.reduce(
    (totals, fee) => ({
      total: totals.total + fee.total,
      paid: totals.paid + fee.paid,
      remaining: totals.remaining + fee.remaining,
    }),
    { total: 0, paid: 0, remaining: 0 },
  );
  const feeProgress =
    feeTotals.total > 0 ? (feeTotals.paid / feeTotals.total) * 100 : 0;
  const classLine = [student.stage, student.grade, student.section]
    .filter((value) => value && value !== "—")
    .join(" · ");

  return `
    <section class="portal-home" aria-label="مساحة الطالب">
      <article class="student-hero" data-reveal>
        <div class="student-hero__float-field" aria-hidden="true">
          ${studentFloatingIcon(studentFloatingIcons.welcome, "student-floating-icon student-floating-icon--hero", "eager")}
          ${studentFloatingIcon(studentFloatingIcons.schedule, "student-floating-icon student-floating-icon--route", "eager")}
        </div>
        <div class="student-hero__copy">
          <span class="student-hero__eyebrow"><i data-lucide="sparkles"></i> مساحتك، على طريقتك</span>
          <p class="student-hero__greeting">${greetingForNow()}</p>
          <h2>${student.name}</h2>
          <p class="student-hero__class">${classLine || "رحلتك الدراسية تبدأ من هنا"}</p>
          <div class="student-hero__facts">
            ${student.academicYear !== "—" ? `<span><i data-lucide="calendar-days"></i>${student.academicYear}</span>` : ""}
            ${student.studentNumber ? `<span><i data-lucide="badge-check"></i>رقم الطالب ${student.studentNumber}</span>` : ""}
          </div>
          <button class="hero-profile-link" type="button" data-target="page:profile">اكتشف ملفك الدراسي <i data-lucide="arrow-up-left"></i></button>
        </div>
        <div class="student-hero__portrait">
          <span class="hero-orbit hero-orbit--one" aria-hidden="true"></span>
          <span class="hero-orbit hero-orbit--two" aria-hidden="true"></span>
          <span class="student-hero__portrait-label"><i data-lucide="school" aria-hidden="true"></i><span>مساحة الطالب</span></span>
          ${studentPortraitMarkup(student, "hero", "eager")}
          ${studentArtworkImage(studentArtwork.heroCompanion, "student-hero__companion")}
          <span class="hero-planet hero-planet--blue" aria-hidden="true"></span>
          <span class="hero-planet hero-planet--orange" aria-hidden="true"></span>
        </div>
      </article>

      <aside class="student-community" data-reveal aria-label="مجتمع مدرسة رواد العلم">
        <div class="student-community__copy">
          <span class="student-community__eyebrow"><i data-lucide="users-round" aria-hidden="true"></i> مجتمع روّاد العلم</span>
          <h2>نتعلّم معًا</h2>
          <p>مساحة تجمع طلابنا في رحلة واحدة نحو المعرفة.</p>
          <div class="student-community__faces" aria-hidden="true">
            ${studentArtworkImage(studentArtwork.home.communityFigures[0], "student-community__face")}
            ${studentArtworkImage(studentArtwork.home.communityFigures[1], "student-community__face")}
            <span>لكل طالب مكانه</span>
          </div>
        </div>
        <img class="student-community__scene" src="${escapeHTML(studentArtwork.home.communityScene)}" alt="مجموعة من طلاب وطالبات رواد العلم في ساحة المدرسة" loading="lazy" decoding="async" />
        <span class="student-community__spark" aria-hidden="true"><i data-lucide="sparkles"></i></span>
      </aside>

      <div class="student-home-grid">
        <article class="attendance-feature" data-reveal>
          <header class="feature-heading"><div><span class="feature-kicker">حضورك يصنع الفرق</span><h2>محطة الحضور</h2></div><i data-lucide="calendar-check"></i></header>
          ${
            attendancePercent === null
              ? emptyState(
                  "calendar-clock",
                  "لم تُسجّل بيانات الحضور بعد",
                  "ستظهر مؤشرات حضورك هنا بعد تسجيلها في النظام.",
                )
              : `<div class="attendance-orbit-layout">
                <div class="attendance-orbit" style="--attendance-offset:${100 - attendancePercent}" aria-label="نسبة الحضور ${attendancePercent.toLocaleString("ar-LY")}%">
                  <svg viewBox="0 0 120 120" aria-hidden="true"><circle class="attendance-orbit__track" cx="60" cy="60" r="50"></circle><circle class="attendance-orbit__value" cx="60" cy="60" r="50" pathLength="100"></circle></svg>
                  <div><strong>${attendancePercent.toLocaleString("ar-LY")}%</strong><span>نسبة الحضور</span></div>
                </div>
                <div class="attendance-counts"><p><span>أيام الحضور</span><strong>${student.attendance.present.toLocaleString("ar-LY")}</strong></p><p><span>مرات التأخر</span><strong>${student.attendance.late.toLocaleString("ar-LY")}</strong></p><p><span>أيام الغياب</span><strong>${student.attendance.absent.toLocaleString("ar-LY")}</strong></p></div>
              </div>`
          }
          <button class="section-jump" type="button" data-target="page:attendance">تفاصيل سجلي <i data-lucide="arrow-up-left"></i></button>
        </article>

        <article class="day-path" data-reveal>
          <header class="feature-heading"><div><span class="feature-kicker">خطوات يومك</span><h2>موعد التعلّم</h2></div>${student.todayAgenda.length ? studentArtworkImage(studentArtwork.home.schedule.active, "feature-heading__art") : ""}<i data-lucide="calendar-days"></i></header>
          ${
            student.todayAgenda.length
              ? `<ol class="day-path__list">${student.todayAgenda.map((entry, index) => `<li style="--path-index:${Math.min(index, 5)}"><span class="day-path__marker">${String(index + 1).toLocaleString("ar-LY", { minimumIntegerDigits: 2 })}</span><time>${entry.time}</time><div><strong>${entry.subject || "اسم المادة غير مسجل"}</strong>${entry.teacher || entry.room ? `<small>${[entry.teacher, entry.room].filter(Boolean).join(" · ")}</small>` : ""}</div></li>`).join("")}</ol>`
              : emptyState(
                  "calendar-clock",
                  "لا توجد حصص منشورة لهذا اليوم",
                  "عندما يُنشر جدول الصف ستظهر مواعيدك هنا.",
                  studentArtwork.home.schedule.empty,
                )
          }
          <button class="section-jump" type="button" data-target="page:timetable">استكشف الأسبوع الدراسي <i data-lucide="arrow-up-left"></i></button>
        </article>

        <article class="results-feature" data-reveal>
          <header class="feature-heading"><div><span class="feature-kicker">ثمرة اجتهادك</span><h2>نتائج معتمدة</h2></div>${student.results.length ? studentArtworkImage(studentArtwork.home.results.active, "feature-heading__art") : ""}<span class="feature-heading__count">${student.results.length.toLocaleString("ar-LY")} ${student.results.length === 1 ? "مادة" : "مواد"}</span></header>
          ${
            student.results.length
              ? `<ul class="subject-trail">${student.results
                  .slice(0, 4)
                  .map(
                    (result, index) =>
                      `<li style="--path-index:${index}"><div><strong>${result.subject}</strong><span>${result.percentage === null ? "التقدير المسجل" : `${result.percentage.toLocaleString("ar-LY")}%`}</span></div>${result.percentage === null ? `<span class="grade-token">${result.grade}</span>` : renderProgress(result.percentage, `نتيجة ${result.subject}`)}</li>`,
                  )
                  .join("")}</ul>`
              : emptyState(
                  "chart-no-axes-column-increasing",
                  "لا توجد نتائج معتمدة الآن",
                  "ستجد نتيجتك هنا بعد اعتمادها من المدرسة.",
                  studentArtwork.home.results.empty,
                )
          }
          <button class="section-jump" type="button" data-target="page:results">كل النتائج <i data-lucide="arrow-up-left"></i></button>
        </article>

        <article class="fees-feature" data-reveal>
          <div class="fees-feature__heading"><span class="fees-feature__icon"><i data-lucide="wallet-cards"></i></span><div><span class="feature-kicker">متابعة القيد</span><h2>الرسوم الدراسية</h2></div>${student.feeRecords.length ? studentArtworkImage(studentArtwork.home.fees.active, "fees-feature__art") : ""}</div>
          ${
            student.feeRecords.length
              ? `<div class="fees-total"><span>المتبقي على البنود المسجلة</span><strong>${formatAmount(feeTotals.remaining)}</strong></div>${renderProgress(feeProgress, "نسبة المبالغ المسددة من إجمالي الرسوم المسجلة")}<div class="fees-feature__meta"><span>المدفوع ${formatAmount(feeTotals.paid)}</span><span>الإجمالي ${formatAmount(feeTotals.total)}</span></div>`
              : emptyState(
                  "wallet",
                  "لا توجد رسوم مرتبطة بالقيد",
                  "لا توجد بنود مالية مسجلة لعرضها الآن.",
                  studentArtwork.home.fees.empty,
                )
          }
          <button class="section-jump" type="button" data-target="page:fees">عرض تفاصيل الرسوم <i data-lucide="arrow-up-left"></i></button>
        </article>
      </div>
    </section>
  `;
}

function renderPortalPageMarkup(page, student) {
  if (page === "profile") {
    const genderValue = String(student.gender || "").toLowerCase();
    const genderLabel = ["male", "m", "ذكر"].includes(genderValue)
      ? "ذكر"
      : ["female", "f", "أنثى", "انثى"].includes(genderValue)
        ? "أنثى"
        : "";
    const translateStatus = (value) =>
      ({
        active: "نشط",
        at_school: "في المدرسة",
        in_progress: "مستمر",
      })[value] || value;
    const sections = [
      {
        title: "المعلومات الأساسية",
        fields: [
          ["الاسم بالإنجليزية", student.fullNameEnglish],
          ["الاسم الأول", student.firstName],
          ["اسم الأب", student.fatherName],
          ["اسم الجد", student.grandfatherName],
          ["اسم العائلة", student.familyName],
          ["اسم الأم", student.motherName],
          ["اسم أقرب الأقرباء", student.nearestRelativeName],
          ["صلة القرابة", student.nearestRelativeRelationship],
          ["الجنس", genderLabel],
          ["تاريخ الميلاد", student.dateOfBirth],
          ["مكان الميلاد", student.placeOfBirth],
          ["الرقم الوطني", student.nationalId],
          ["الجنسية", student.nationality],
          ["الديانة", student.religion],
        ],
      },
      {
        title: "البيانات الدراسية",
        fields: [
          ["المرحلة الدراسية", student.stage],
          ["الصف", student.grade],
          ["الشعبة", student.section],
          ["السنة الدراسية", student.academicYear],
          ["رقم الطالب في الصف", student.rollNumber],
          ["نتيجة القيد", translateStatus(student.outcome)],
          ["المدرسة السابقة", student.previousSchool],
        ],
      },
      {
        title: "بيانات التسجيل والقيد الحالي",
        fields: [
          ["تاريخ تسجيل الطالب", student.registrationDate],
          ["تاريخ القيد الدراسي", student.enrollmentDate],
          ["تاريخ التخرج", student.graduationDate],
          ["نوع القيد", student.admissionType],
          ["حالة القيد الدراسي", translateStatus(student.enrollmentStatus)],
          ["الحالة التعليمية", translateStatus(student.educationalStatus)],
          ["حالة الملف", translateStatus(student.fileStatus)],
          [
            "طالب مستجد",
            student.isNewStudent === null
              ? ""
              : student.isNewStudent
                ? "نعم"
                : "لا",
          ],
          [
            "إعادة صف",
            student.isRepeat === null ? "" : student.isRepeat ? "نعم" : "لا",
          ],
        ],
      },
      {
        title: "العنوان والتواصل",
        fields: [
          ["هاتف الطالب", student.phone],
          ["عنوان الطالب", student.address],
          ["عنوان السكن", student.residenceAddress],
          ["المدينة", student.city],
          ["المنطقة", student.region],
        ],
      },
    ];
    const visibleSections = sections
      .map(({ title, fields }) => ({
        title,
        fields: fields.filter(
          ([, value]) =>
            value !== null &&
            value !== undefined &&
            String(value).trim() !== "" &&
            !/^(null|undefined)$/i.test(String(value).trim()),
        ),
      }))
      .filter((section) => section.fields.length);
    const profileQuickFacts = [
      {
        label: "رقم الطالب",
        value: student.studentNumber,
        icon: "badge-check",
      },
      { label: "رقم الملف", value: student.fileNumber, icon: "folder" },
      {
        label: "الصف والشعبة",
        value: [student.grade, student.section]
          .filter((value) => value && value !== "—")
          .join(" · "),
        icon: "school",
      },
      {
        label: "السنة الدراسية",
        value: student.academicYear,
        icon: "calendar-days",
      },
    ].filter(({ value }) => value && value !== "—");
    const enrollmentStatus = [
      student.enrollmentStatus,
      student.educationalStatus,
      student.fileStatus,
      student.outcome,
    ].find((value) => value && value !== "—");

    return `
      <section class="portal-page study-page" aria-labelledby="portal-page-title">
        <article class="profile-story" data-reveal>
          <header class="profile-story__hero" aria-labelledby="portal-page-title">
            <div class="profile-story__hero-copy">
              <span class="profile-story__eyebrow">هويتك في المدرسة <i data-lucide="sparkles" aria-hidden="true"></i></span>
              <h2 id="portal-page-title">ملفي الدراسي</h2>
              <p class="profile-story__intro">مساحتك التعريفية كما سُجّلت في القيد الدراسي.</p>
              <div class="profile-story__identity"><span>الاسم الرباعي</span><h3>${student.name}</h3></div>
              ${enrollmentStatus ? `<span class="profile-story__status"><i data-lucide="circle-check" aria-hidden="true"></i><span>حالة القيد · ${translateStatus(enrollmentStatus)}</span></span>` : ""}
            </div>
            <div class="profile-story__portrait">${studentPortraitMarkup(student, "profile")}</div>
            ${profileQuickFacts.length ? `<dl class="profile-story__quick-facts">${profileQuickFacts.map(({ label, value, icon }) => `<div><dt><i data-lucide="${icon}" aria-hidden="true"></i>${label}</dt><dd>${value}</dd></div>`).join("")}</dl>` : ""}
          </header>
          ${visibleSections.length ? visibleSections.map((section) => `<section class="profile-story__section"><h3>${section.title}</h3><dl class="profile-story__details">${section.fields.map(([label, value], index) => `<div style="--path-index:${Math.min(index, 5)}"><dt>${label}</dt><dd>${value}</dd></div>`).join("")}</dl></section>`).join("") : emptyState("user-round", "لا توجد بيانات إضافية مسجلة", "لم تُسجل بيانات أخرى لعرضها في ملف الطالب.")}
        </article>
      </section>
    `;
  }

  if (page === "attendance") {
    const attendancePercent =
      student.attendance.percent === null
        ? null
        : Math.min(100, Math.max(0, student.attendance.percent));
    const attendanceIllustration = student.attendanceRecords.length
      ? studentArtwork.pages.attendance.active
      : null;
    return `
      <section class="portal-page study-page" aria-labelledby="portal-page-title">
        ${renderStudyPageHeading("كل يوم هو خطوة", "الحضور والغياب", "سجلّك اليومي كما ورد من المدرسة.", attendanceIllustration, studentFloatingIcons.schedule)}
        <div class="attendance-overview" data-reveal>
          <div class="attendance-overview__lead"><span>مؤشر الحضور</span>${attendancePercent === null ? "<strong>بانتظار أول سجل</strong>" : `<strong>${attendancePercent.toLocaleString("ar-LY")}<small>%</small></strong>`}<p>${attendancePercent === null ? "لا توجد سجلات حضور مرتبطة بالقيد حتى الآن." : `مبني على ${student.attendance.recordCount.toLocaleString("ar-LY")} سجلًا دراسيًا.`}</p></div>
          <div class="attendance-overview__counts"><div><i data-lucide="circle-check"></i><span>حضور</span><strong>${student.attendance.present.toLocaleString("ar-LY")}</strong></div><div><i data-lucide="clock-3"></i><span>تأخر</span><strong>${student.attendance.late.toLocaleString("ar-LY")}</strong></div><div><i data-lucide="circle-minus"></i><span>غياب</span><strong>${student.attendance.absent.toLocaleString("ar-LY")}</strong></div></div>
        </div>
        <section class="attendance-journal" aria-label="أحدث سجلات الحضور"><header class="feature-heading"><div><span class="feature-kicker">من الأحدث إلى الأقدم</span><h3>دفتر الأيام</h3></div><i data-lucide="notebook-tabs"></i></header>
          ${student.attendanceRecords.length ? `<ol class="attendance-journal__list">${student.attendanceRecords.map((entry, index) => `<li style="--path-index:${Math.min(index, 5)}"><time>${entry.date}</time><span class="attendance-journal__status"><i data-lucide="${entry.lateMinutes ? "clock-3" : "calendar-check"}"></i>${entry.status}</span>${entry.lateMinutes ? `<small>تأخر ${entry.lateMinutes.toLocaleString("ar-LY")} دقيقة</small>` : ""}</li>`).join("")}</ol>` : emptyState("calendar-x-2", "دفتر الحضور فارغ حاليًا", "ستظهر هنا السجلات فور تسجيلها للقيد الدراسي.", studentArtwork.pages.attendance.empty)}
        </section>
      </section>
    `;
  }

  if (page === "results") {
    const resultsIllustration = student.results.length
      ? studentArtwork.pages.results
      : null;
    return `
      <section class="portal-page study-page" aria-labelledby="portal-page-title">
        ${renderStudyPageHeading("ثمار التعلّم", "النتائج والتقييمات", "تظهر هنا نتائجك التي اعتمدتها المدرسة فقط.", resultsIllustration, studentFloatingIcons.achievement)}
        ${student.results.length ? `<div class="results-atlas">${student.results.map((result, index) => `<article class="result-island" data-reveal style="--path-index:${Math.min(index, 5)}"><span class="result-island__index">${String(index + 1).toLocaleString("ar-LY", { minimumIntegerDigits: 2 })}</span><div class="result-island__subject"><span>المادة</span><h3>${result.subject}</h3></div><div class="result-island__score">${result.percentage === null ? `<span>التقدير</span><strong class="grade-token">${result.grade}</strong>` : `<span>النتيجة المعتمدة</span><strong>${result.percentage.toLocaleString("ar-LY")}<small>%</small></strong>${renderProgress(result.percentage, `نتيجة ${result.subject}`)}`}</div></article>`).join("")}</div>` : emptyState("chart-no-axes-column-increasing", "لا توجد نتائج معتمدة بعد", "ستظهر نتائجك هنا عندما تعتمدها المدرسة.", studentArtwork.home.results.empty)}
      </section>
    `;
  }

  if (page === "fees") {
    const feesIllustration = student.feeRecords.length
      ? studentArtwork.pages.fees.active
      : null;
    return `
      <section class="portal-page study-page" aria-labelledby="portal-page-title">
        ${renderStudyPageHeading("تفاصيل القيد", "الرسوم والمستحقات", "متابعة واضحة لبنود الرسوم المسجلة على القيد.", feesIllustration, studentFloatingIcons.contact)}
        ${
          student.feeRecords.length
            ? `<div class="fee-ledger">${student.feeRecords
                .map((fee, index) => {
                  const progress =
                    fee.total > 0 ? (fee.paid / fee.total) * 100 : 0;
                  return `<article class="fee-entry" data-reveal style="--path-index:${Math.min(index, 5)}"><div class="fee-entry__title"><span class="fee-entry__number">${String(index + 1).toLocaleString("ar-LY", { minimumIntegerDigits: 2 })}</span><div><h3>${fee.label}</h3><span class="fee-entry__status">${fee.status}</span></div></div><div class="fee-entry__amounts"><p><span>الإجمالي</span><strong>${formatAmount(fee.total)}</strong></p><p><span>المدفوع</span><strong>${formatAmount(fee.paid)}</strong></p><p><span>المتبقي</span><strong>${formatAmount(fee.remaining)}</strong></p></div>${renderProgress(progress, `نسبة السداد لبند ${fee.label}`)}</article>`;
                })
                .join("")}</div>`
            : emptyState(
                "wallet",
                "لا توجد بنود رسوم مسجلة",
                "لا توجد رسوم مرتبطة بهذا القيد في الوقت الحالي.",
                studentArtwork.pages.fees.empty,
              )
        }
      </section>
    `;
  }

  if (page === "timetable") {
    const timetableIllustration = student.timetable.length
      ? studentArtwork.pages.timetable.active
      : null;
    const timetableGrid = buildTimetableGrid(student);
    const currentDay = new Date().getDay();
    const rows = timetableGrid.rows
      .map(
        (day) => `
        <tr>
          <th scope="row" class="timetable-grid__day ${day.day_number === currentDay ? "is-today" : ""}">${day.day}</th>
          ${day.cells
            .map(
              ({ period, lessons }) => `
            <td class="timetable-grid__cell ${day.day_number === currentDay ? "is-today" : ""}">
              ${lessons.length ? lessons.map((lesson) => `<div class="timetable-grid__lesson"><strong>${lesson.subject || "اسم المادة غير مسجل"}</strong>${lesson.teacher ? `<span>${lesson.teacher}</span>` : ""}${lesson.room ? `<small>${lesson.room}</small>` : ""}</div>`).join("") : `<span class="timetable-grid__empty" aria-label="لا توجد حصة">—</span>`}
            </td>
          `,
            )
            .join("")}
        </tr>
      `,
      )
      .join("");
    const timetableWarnings = [
      timetableGrid.missingSubjectCount
        ? `<p class="timetable-warning" role="status">تعذر تحديد اسم المادة في ${timetableGrid.missingSubjectCount.toLocaleString("ar-LY")} حصة. أُظهرنا السجل في موضعه دون استبدال الاسم ببيانات افتراضية.</p>`
        : "",
      timetableGrid.unplacedCount
        ? `<p class="timetable-warning" role="status">تعذر وضع ${timetableGrid.unplacedCount.toLocaleString("ar-LY")} حصة في الشبكة لنقص رقم اليوم أو الفترة في سجلها.</p>`
        : "",
    ].join("");

    return `
      <section class="portal-page study-page" aria-labelledby="portal-page-title">
        ${renderStudyPageHeading(student.academicYear ? `العام الدراسي ${student.academicYear}` : "إيقاع الأسبوع", "جدولي الدراسي", "مواعيد الحصص المنشورة للصف المرتبط بقيدك.", timetableIllustration, studentFloatingIcons.schedule)}
        ${student.timetable.length ? `${timetableWarnings}<div class="timetable-shell" data-reveal><div class="timetable-grid__wrapper" tabindex="0" role="region" aria-label="جدول الحصص؛ يمكن التمرير أفقيًا"><table class="timetable-grid"><thead><tr><th scope="col" class="timetable-grid__corner">اليوم</th>${timetableGrid.periods.map((period) => `<th scope="col"><span class="timetable-grid__period-number">الحصة ${period.number.toLocaleString("ar-LY")}</span>${period.name !== `الحصة ${period.number}` ? `<span class="timetable-grid__period-name">${period.name}</span>` : ""}<time>${period.startTime && period.endTime ? `${period.startTime} – ${period.endTime}` : period.startTime || period.endTime || "وقت غير مسجل"}</time></th>`).join("")}</tr></thead><tbody>${rows}</tbody></table></div></div>` : emptyState("calendar-days", "لم يُنشر جدول الصف بعد", "سيظهر جدولك هنا عندما تضيف المدرسة الحصص إلى النظام.", studentArtwork.pages.timetable.empty)}
      </section>
    `;
  }

  if (page === "platforms") {
    return `<section class="portal-page study-page" aria-labelledby="portal-page-title">${renderStudyPageHeading("مساحات التعلّم", "روابطي التعليمية", "الخدمات التي تربطها المدرسة بحسابك.", studentArtwork.pages.platforms, studentFloatingIcons.welcome)}<div class="platform-space" data-reveal><span><i data-lucide="link-2"></i></span>${emptyState("book-open", "لا توجد روابط تعليمية مهيأة", "لم تُضف المدرسة روابط خدمات تعليمية لهذا الحساب بعد.")}</div></section>`;
  }

  return renderPortalHome(student);
}

function renderStudentPortal() {
  const student = state.student;
  const activePage = state.activePanel || "home";
  const activeCard = localPageCards.find((card) => card.page === activePage);
  const title = activeCard?.label || "مساحتي";
  return `
    <div class="student-shell">
      <aside class="portal-sidebar" aria-label="بوابة الطالب">
        <a class="portal-brand" href="#home" data-target="student-dashboard"><img src="assets/logo.png" alt="" width="46" height="46" /><span><strong>${schoolProfile.shortName}</strong><small>بوابتك المدرسية</small></span></a>
        <div class="portal-sidebar__student">${studentAvatar(student, "student-avatar student-avatar--sidebar")}<span><strong>${student.name}</strong><small>${student.grade !== "—" ? student.grade : "طالب"}${student.section !== "—" ? ` · ${student.section}` : ""}</small></span></div>
        <span class="portal-sidebar__label">مساحات التعلّم</span>
        <nav class="portal-nav" aria-label="أقسام البوابة">
          ${localPageCards
            .map(
              (card) => `
            <button class="portal-nav__item ${activePage === card.page ? "is-active" : ""}" type="button" data-target="page:${card.page}" ${phonePrimaryPortalPages.has(card.page) ? 'data-phone-primary="true"' : ""} ${activePage === card.page ? 'aria-current="page"' : ""}>
              <i data-lucide="${card.icon}"></i><span>${card.label}</span>${activePage === card.page ? '<i class="portal-nav__active-mark" data-lucide="arrow-left"></i>' : ""}
            </button>
          `,
            )
            .join("")}
          <button class="portal-nav__item portal-nav__more ${!phonePrimaryPortalPages.has(activePage) ? "is-active" : ""}" type="button" data-portal-more aria-expanded="false" aria-controls="portal-nav-more" aria-haspopup="true" aria-label="المزيد من الأقسام">
            <i data-lucide="ellipsis"></i><span>المزيد</span>
          </button>
          <div class="portal-nav__more-menu" id="portal-nav-more" data-portal-more-menu role="group" aria-label="أقسام إضافية" hidden>
            ${localPageCards
              .filter((card) => !phonePrimaryPortalPages.has(card.page))
              .map(
                (card) => `
              <button class="portal-nav__more-item ${activePage === card.page ? "is-active" : ""}" type="button" data-target="page:${card.page}" ${activePage === card.page ? 'aria-current="page"' : ""}>
                <i data-lucide="${card.icon}"></i><span>${card.label}</span>
              </button>
            `,
              )
              .join("")}
          </div>
        </nav>
        <div class="portal-sidebar__bottom">${renderWhatsAppLink("تواصل عبر واتساب", "مساعدة بشأن الحساب الدراسي", "whatsapp-link whatsapp-link--sidebar")}<button class="portal-logout" type="button" data-target="logout"><i data-lucide="log-out"></i><span>تسجيل الخروج</span></button></div>
      </aside>
      <main class="student-main">
        <header class="student-topbar">
          <div class="student-topbar__title"><span class="section-index">${activePage === "home" ? "مساحتك الرقمية" : title}</span><h1>${activePage === "home" ? "بوابتك إلى يومٍ دراسي أجمل" : title}</h1></div>
          <div class="student-topbar__actions"><span class="today-date"><i data-lucide="calendar-days"></i>${new Date().toLocaleDateString("ar-LY", { weekday: "long", day: "numeric", month: "long" })}</span><button class="student-topbar__logout" type="button" data-target="logout"><i data-lucide="log-out"></i><span>خروج آمن</span></button>${renderWhatsAppLink("واتساب", "مساعدة بشأن الحساب الدراسي", "whatsapp-link whatsapp-link--quick")}</div>
        </header>
        <div class="student-content" data-portal-view>${renderPortalPageMarkup(activePage, student)}</div>
        <footer class="student-footer"><span class="student-footer__school">${schoolProfile.shortName}</span><span class="student-footer__motto">مساحتك الدراسية، في مكان واحد</span><a class="student-footer__developer" href="mailto:danyamusbah8@gmail.com"><span>تطوير الموقع</span><strong dir="ltr">Danya Musbah</strong><i data-lucide="mail" aria-hidden="true"></i><span dir="ltr">danyamusbah8@gmail.com</span></a></footer>
      </main>
      <dialog class="logout-dialog" data-logout-dialog aria-labelledby="logout-dialog-title" aria-describedby="logout-dialog-description">
        <div class="logout-dialog__content">
          <span class="logout-dialog__icon" aria-hidden="true"><i data-lucide="log-out"></i></span>
          <span class="logout-dialog__eyebrow">إلى لقاء قريب</span>
          <h2 id="logout-dialog-title">هل تريد تسجيل الخروج؟</h2>
          <p id="logout-dialog-description">ستحتاج إلى بيانات الدخول للعودة إلى مساحتك الدراسية.</p>
          <div class="logout-dialog__actions">
            <button class="logout-dialog__stay" type="button" data-logout-cancel>البقاء في الحساب</button>
            <button class="logout-dialog__confirm" type="button" data-logout-confirm>تسجيل الخروج</button>
          </div>
        </div>
      </dialog>
    </div>
  `;
}

mount();
