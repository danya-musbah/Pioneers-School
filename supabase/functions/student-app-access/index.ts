// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedDevelopmentOrigins = [
  "http://localhost:8000",
  "http://127.0.0.1:8000",
  "http://localhost:8080",
  "http://127.0.0.1:8080",
  "http://localhost:8756",
  "http://127.0.0.1:8756",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
];
const MAX_TARGETS = 50;
const PASSWORD_ALPHABET =
  "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

function allowedOrigins() {
  const configured = (Deno.env.get("CORS_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set(configured.length ? configured : allowedDevelopmentOrigins);
}

function corsHeaders(request: Request) {
  const origin = request.headers.get("Origin") || "";
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-requested-with, x-supabase-api-version, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && allowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function json(body: unknown, status: number, request: Request) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (request: Request) => {
  const headers = corsHeaders(request);
  const origin = request.headers.get("Origin") || "";
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: origin && !headers["Access-Control-Allow-Origin"] ? 403 : 204,
      headers,
    });
  }
  if (origin && !headers["Access-Control-Allow-Origin"]) {
    return json({ error: "هذا النطاق غير مسموح له بالاتصال بالخدمة." }, 403, request);
  }
  try {
    return await handleRequest(request);
  } catch (_) {
    // Never log request bodies, passwords, Auth responses, or raw provider errors.
    console.error("student-app-access request failed");
    return json({ error: "تعذر تنفيذ عملية الوصول. يرجى المحاولة مرة أخرى." }, 500, request);
  }
});

async function handleRequest(request: Request) {
  if (request.method !== "POST") {
    return json({ error: "طريقة الطلب غير مدعومة." }, 405, request);
  }
  const authorization = request.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "يجب تسجيل الدخول لتنفيذ هذا الإجراء." }, 401, request);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("student-app-access is missing server configuration");
    return json({ error: "خدمة إدارة الوصول غير مهيأة على الخادم." }, 500, request);
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.slice("Bearer ".length);
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData?.user) {
    return json({ error: "انتهت الجلسة أو أن بيانات تسجيل الدخول غير صالحة." }, 401, request);
  }
  const { data: session, error: sessionError } = await caller.rpc("my_session");
  if (
    sessionError ||
    session?.profile?.id !== authData.user.id ||
    session?.profile?.status !== "active"
  ) {
    return json({ error: "الحساب غير نشط أو لا يملك ملف مستخدم صالحًا." }, 401, request);
  }
  const actor = {
    id: authData.user.id,
    name: String(session.profile.full_name || session.profile.username || "مدير النظام"),
    role: String(session.profile.role || ""),
    permissions: Array.isArray(session.permissions) ? session.permissions : [],
    schoolId: String(session.profile.school_id || session.school?.school_id || ""),
  };
  if (!actor.schoolId) {
    return json({ error: "تعذر تحديد مدرسة الحساب الحالي." }, 403, request);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch (_) {
    return json({ error: "بيانات الطلب غير صالحة." }, 400, request);
  }
  const isAdmin = actor.role === "admin";
  const canManageStudents =
    isAdmin || actor.permissions.some((permission) =>
      ["students.manage", "students.edit"].includes(permission)
    );
  const canManageGuardians =
    isAdmin || actor.permissions.some((permission) =>
      ["guardians.manage", "students.edit"].includes(permission)
    );
  const action = String(payload.action || "");

  if (action === "record-export") {
    if (!canManageStudents) {
      return json({ error: "ليس لديك صلاحية تصدير بيانات الدخول." }, 403, request);
    }
    const studentIds = Array.isArray(payload.student_ids)
      ? [...new Set(payload.student_ids.filter((id) => typeof id === "string" && isUuid(id)))]
      : [];
    if (!studentIds.length || studentIds.length > MAX_TARGETS) {
      return json({ error: `حدد من 1 إلى ${MAX_TARGETS} حسابًا صالحًا للتصدير.` }, 400, request);
    }
    const { data: pendingAccounts, error: pendingError } = await admin
      .from("student_app_accounts")
      .select("student_id,credential_delivery_pending,credential_issued_at,students!inner(student_app_login_status,student_app_login_enabled,educational_status,is_archived)")
      .eq("school_id", actor.schoolId)
      .eq("is_enabled", true)
      .in("student_id", studentIds);
    const allAccountsReady =
      pendingAccounts?.length === studentIds.length &&
      pendingAccounts.every((account) =>
        account.credential_delivery_pending &&
        account.credential_issued_at &&
        account.students?.student_app_login_enabled &&
        ["active", "reset_required"].includes(account.students?.student_app_login_status) &&
        account.students?.educational_status !== "withdrawn" &&
        !account.students?.is_archived
      );
    if (pendingError || !allAccountsReady) {
      return json({ error: "بعض الحسابات المحددة لم تعد مفعّلة في المدرسة الحالية." }, 409, request);
    }
    const { error } = await admin.from("audit_logs").insert({
      user_id: actor.id,
      actor_id: actor.id,
      actor_label: actor.name,
      action: "student_app_credentials.exported",
      entity_type: "student_app_accounts",
      entity_id: null,
      school_id: actor.schoolId,
      description: "تم تصدير بيانات دخول مؤقتة لحسابات الطلاب المحددة.",
      metadata: { module: "app-access", account_count: studentIds.length },
    });
    if (error) {
      console.error("student app credential export audit failed");
      return json({ error: "تعذر تسجيل عملية التصدير؛ لم يُنشأ ملف." }, 500, request);
    }
    const { data: consumedAccounts, error: consumeError } = await admin
      .from("student_app_accounts")
      .update({ credential_delivery_pending: false, updated_at: new Date().toISOString() })
      .eq("school_id", actor.schoolId)
      .eq("is_enabled", true)
      .eq("credential_delivery_pending", true)
      .in("student_id", studentIds)
      .select("student_id");
    if (consumeError || consumedAccounts?.length !== studentIds.length) {
      console.error("student app credential export state update failed");
      return json({ error: "تعذر إكمال تسجيل التصدير؛ لم يُنشأ الملف." }, 500, request);
    }
    return json({ recorded: true }, 200, request);
  }

  if (action !== "manage-accounts") {
    return json({ error: "إجراء إدارة الوصول غير معروف." }, 400, request);
  }
  const kind = String(payload.kind || "");
  const status = String(payload.status || "");
  const rawIds = Array.isArray(payload.ids) ? payload.ids : [];
  const ids = [...new Set(rawIds.filter((id) => typeof id === "string"))];
  if (!ids.length || ids.length > MAX_TARGETS || ids.some((id) => !isUuid(id))) {
    return json({ error: `حدد من 1 إلى ${MAX_TARGETS} سجل صالحًا.` }, 400, request);
  }
  if (!["active", "reset_required", "disabled"].includes(status)) {
    return json({ error: "حالة الوصول المحددة غير صالحة." }, 400, request);
  }
  if (kind === "student" && !canManageStudents) {
    return json({ error: "ليس لديك صلاحية إدارة دخول الطلاب." }, 403, request);
  }
  // A guardian uses the selected child's account. Both student-access and
  // guardian-access permissions are required because the operation affects
  // the student's login and every guardian sharing it.
  if (kind === "guardian" && (!canManageStudents || !canManageGuardians)) {
    return json({ error: "تتطلب إدارة دخول ولي الأمر صلاحية الطلاب وأولياء الأمور." }, 403, request);
  }
  if (!["student", "guardian"].includes(kind)) {
    return json({ error: "نوع الحساب المحدد غير صالح." }, 400, request);
  }

  const resolved = await resolveTargets(admin, kind, ids, actor.schoolId);
  if (resolved.error) {
    if (typeof resolved.error !== "string") {
      console.error("student app access target lookup failed");
    }
    return json(
      { error: typeof resolved.error === "string" ? resolved.error : "تعذر التحقق من السجلات المحددة." },
      typeof resolved.error === "string" ? 400 : 500,
      request,
    );
  }
  const records: Record<string, unknown>[] = [];
  const credentials: Record<string, unknown>[] = [];
  const failures: Record<string, unknown>[] = [...resolved.failures];

  for (const target of resolved.targets) {
    const result = await updateStudentAccount({
      admin,
      caller,
      actor,
      target,
      status,
    });
    records.push(result.record);
    if (result.credential) credentials.push(result.credential);
    if (result.failure) failures.push(result.failure);
  }

  const guardianStatusFailures: Record<string, unknown>[] = [];
  const completedGuardianIds: string[] = [];
  if (kind === "guardian") {
    const targetState = new Map(records.map((record) => [record.student_id, record.success]));
    for (const guardian of resolved.guardians) {
      const linkedIds = resolved.guardianStudentIds.get(guardian.id) || [];
      if (!linkedIds.length || linkedIds.some((studentId) => targetState.get(studentId) !== true)) {
        continue;
      }
      const { data, error } = await caller.rpc("update_guardian_app_login_status", {
        p_guardian_id: guardian.id,
        p_status: status,
        p_reason: "إدارة الحساب المشترك للطالب وولي الأمر",
      });
      if (error || data?.status !== status) {
        guardianStatusFailures.push({
          label: guardian.full_name || "ولي أمر محدد",
          error: "تعذر تحديث حالة ولي الأمر المسجلة.",
        });
      } else {
        completedGuardianIds.push(guardian.id);
      }
    }
  }

  return json({
    records,
    credentials,
    failures,
    guardian_status_failures: guardianStatusFailures,
    completed_guardian_ids: completedGuardianIds,
  }, 200, request);
}

async function resolveTargets(
  admin: ReturnType<typeof createClient>,
  kind: string,
  ids: string[],
  schoolId: string,
) {
  const failures: Record<string, unknown>[] = [];
  const targetsById = new Map<string, Record<string, unknown>>();
  const guardians: Record<string, unknown>[] = [];
  const guardianStudentIds = new Map<string, string[]>();

  if (kind === "student") {
    const { data, error } = await admin
      .from("students")
      .select("id,school_id,student_number,full_name,educational_status,is_archived,student_app_login_status")
      .eq("school_id", schoolId)
      .in("id", ids);
    if (error) return { error };
    for (const student of data || []) {
      if (student.educational_status === "withdrawn" || student.is_archived) {
        failures.push({ label: student.full_name || "طالب محدد", error: "الطالب منسحب أو مؤرشف ولا يمكن إصدار دخول له." });
        continue;
      }
      targetsById.set(student.id, { student, guardianNames: [] });
    }
    const found = new Set((data || []).map((student) => student.id));
    for (const id of ids) if (!found.has(id)) failures.push({ label: "طالب محدد", error: "الطالب غير موجود في المدرسة الحالية." });
  } else {
    const { data: guardianRows, error: guardianError } = await admin
      .from("guardians")
      .select("id,school_id,full_name")
      .eq("school_id", schoolId)
      .in("id", ids);
    if (guardianError) return { error: guardianError };
    guardians.push(...(guardianRows || []));
    const foundGuardians = new Set((guardianRows || []).map((guardian) => guardian.id));
    for (const id of ids) {
      if (!foundGuardians.has(id)) failures.push({ label: "ولي أمر محدد", error: "ولي الأمر غير موجود في المدرسة الحالية." });
      guardianStudentIds.set(id, []);
    }
    if (foundGuardians.size) {
      const { data: links, error: linkError } = await admin
        .from("student_guardians")
        .select("guardian_id,student_id")
        .in("guardian_id", [...foundGuardians]);
      if (linkError) return { error: linkError };
      const studentIds = [...new Set((links || []).map((link) => link.student_id))];
      const { data: studentRows, error: studentError } = await admin
        .from("students")
        .select("id,school_id,student_number,full_name,educational_status,is_archived,student_app_login_status")
        .eq("school_id", schoolId)
        .in("id", studentIds.length ? studentIds : ["00000000-0000-0000-0000-000000000000"]);
      if (studentError) return { error: studentError };
      const studentsById = new Map((studentRows || []).map((student) => [student.id, student]));
      const guardiansById = new Map(guardians.map((guardian) => [guardian.id, guardian]));
      for (const link of links || []) {
        const student = studentsById.get(link.student_id);
        const guardian = guardiansById.get(link.guardian_id);
        guardianStudentIds.get(link.guardian_id)?.push(link.student_id);
        if (!student || student.educational_status === "withdrawn" || student.is_archived) continue;
        const target = targetsById.get(student.id) || { student, guardianNames: [] };
        if (guardian?.full_name && !target.guardianNames.includes(guardian.full_name)) {
          target.guardianNames.push(guardian.full_name);
        }
        targetsById.set(student.id, target);
      }
    }
    for (const guardian of guardians) {
      const linked = guardianStudentIds.get(guardian.id) || [];
      const available = linked.filter((studentId) => targetsById.has(studentId));
      if (!available.length) failures.push({ label: guardian.full_name || "ولي أمر محدد", error: "لا يوجد طالب نشط مرتبط بولي الأمر." });
    }
    const targetIds = [...targetsById.keys()];
    if (targetIds.length) {
      const { data: allLinks, error: allLinksError } = await admin
        .from("student_guardians")
        .select("student_id,guardian_id")
        .in("student_id", targetIds);
      if (allLinksError) return { error: allLinksError };
      const allGuardianIds = [...new Set((allLinks || []).map((link) => link.guardian_id))];
      if (allGuardianIds.length) {
        const { data: allGuardians, error: allGuardiansError } = await admin
          .from("guardians")
          .select("id,full_name")
          .eq("school_id", schoolId)
          .in("id", allGuardianIds);
        if (allGuardiansError) return { error: allGuardiansError };
        const guardianNames = new Map((allGuardians || []).map((guardian) => [guardian.id, guardian.full_name]));
        for (const link of allLinks || []) {
          const name = guardianNames.get(link.guardian_id);
          const target = targetsById.get(link.student_id);
          if (target && name && !target.guardianNames.includes(name)) {
            target.guardianNames.push(name);
          }
        }
      }
    }
    if (targetsById.size > MAX_TARGETS) {
      return { error: `تتجاوز الحسابات المرتبطة الحد الآمن (${MAX_TARGETS}). قلّل عدد أولياء الأمور المحددين.` };
    }
  }

  return {
    targets: [...targetsById.values()],
    failures,
    guardians,
    guardianStudentIds,
  };
}

async function updateStudentAccount({ admin, caller, actor, target, status }) {
  const student = target.student;
  const label = `${student.full_name || "الطالب"} — ${student.student_number || "بدون رقم"}`;
  const accountResult = await admin
    .from("student_app_accounts")
    .select("student_id,school_id,auth_user_id,login_email,is_enabled,credential_issued_at,credential_delivery_pending")
    .eq("student_id", student.id)
    .eq("school_id", actor.schoolId)
    .maybeSingle();
  if (accountResult.error) {
    return failedRecord(student, label, "تعذر تحميل ربط حساب المصادقة.");
  }
  let account = accountResult.data;
  const createdMapping = !account;

  if (status === "disabled") {
    if (account) {
      const { error } = await admin
        .from("student_app_accounts")
        .update({ is_enabled: false, updated_at: new Date().toISOString() })
        .eq("student_id", student.id)
        .eq("school_id", actor.schoolId);
      if (error) return failedRecord(student, label, "تعذر تعطيل ربط حساب المصادقة.");
    }
    const statusResult = await setStudentStatus(caller, student.id, "disabled");
    if (!statusResult.ok) return failedRecord(student, label, statusResult.message);
    const audited = await auditAccountChange(admin, actor, student.id, "disabled");
    if (!audited) return failedRecord(student, label, "تم تعطيل الوصول لكن تعذر تسجيل التدقيق؛ راجع سجل الطالب قبل المتابعة.");
    return { record: { ...recordFor(student, target, true), status: "disabled", outcome: "disabled" } };
  }

  const issuePassword =
    status === "reset_required" ||
    !account?.auth_user_id ||
    !account?.credential_issued_at ||
    account?.credential_delivery_pending;
  const loginEmail = account?.login_email || syntheticLoginEmail(student.id);
  let password: string | null = null;
  let authUserId = account?.auth_user_id || null;
  let createdAuthUser = false;

  if (issuePassword) {
    if (!account && await hasProfileUsernameCollision(admin, student.student_number)) {
      return failedRecord(student, label, "يتعارض رقم الطالب مع اسم مستخدم إداري؛ تعذر إنشاء اسم دخول فريد.");
    }
    password = generateTemporaryPassword();
    if (account) {
      const { error: disableError } = await admin
        .from("student_app_accounts")
        .update({
          is_enabled: false,
          credential_delivery_pending: true,
          credential_issued_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("student_id", student.id)
        .eq("school_id", actor.schoolId);
      if (disableError) return failedRecord(student, label, "تعذر قفل الحساب أثناء إعادة التعيين.");
    }
    if (authUserId) {
      const { error } = await admin.auth.admin.updateUserById(authUserId, { password });
      if (error) return failedRecord(student, label, "تعذر تحديث كلمة المرور؛ لم تُعرض بيانات دخول جديدة.");
    } else {
      const { data, error } = await admin.auth.admin.createUser({
        email: loginEmail,
        password,
        email_confirm: true,
      });
      if (error || !data?.user) {
        return failedRecord(student, label, "تعذر إنشاء حساب المصادقة؛ لم تُعرض بيانات دخول.");
      }
      authUserId = data.user.id;
      createdAuthUser = true;
    }
    if (!account) {
      const { data, error } = await admin
        .from("student_app_accounts")
        .insert({
          student_id: student.id,
          school_id: actor.schoolId,
          auth_user_id: authUserId,
          login_email: loginEmail,
          is_enabled: false,
          created_by: actor.id,
        })
        .select("student_id")
        .maybeSingle();
      if (error || !data) {
        if (createdAuthUser) await admin.auth.admin.deleteUser(authUserId);
        return failedRecord(student, label, "تعذر حفظ ربط الحساب؛ لم تُعرض بيانات دخول.");
      }
      account = { student_id: student.id, auth_user_id: authUserId, login_email: loginEmail };
    }
  }

  const nextStatus = status === "reset_required" ? "reset_required" : "active";
  const statusResult = await setStudentStatus(caller, student.id, nextStatus);
  if (!statusResult.ok) {
    if (createdAuthUser) {
      if (createdMapping) {
        await admin.from("student_app_accounts").delete().eq("student_id", student.id);
      } else {
        await admin.from("student_app_accounts")
          .update({ auth_user_id: null, is_enabled: false, updated_at: new Date().toISOString() })
          .eq("student_id", student.id);
      }
      await admin.auth.admin.deleteUser(authUserId);
    }
    return failedRecord(student, label, statusResult.message);
  }

  const { error: enableError } = await admin
    .from("student_app_accounts")
    .update({
      auth_user_id: authUserId,
      login_email: loginEmail,
      is_enabled: true,
      credential_issued_at: password ? new Date().toISOString() : account?.credential_issued_at,
      credential_delivery_pending: Boolean(password),
      updated_at: new Date().toISOString(),
    })
    .eq("student_id", student.id)
    .eq("school_id", actor.schoolId);
  if (enableError) {
    if (createdAuthUser) {
      if (createdMapping) {
        await admin.from("student_app_accounts").delete().eq("student_id", student.id);
      } else {
        await admin.from("student_app_accounts")
          .update({
            auth_user_id: null,
            is_enabled: false,
            credential_delivery_pending: true,
            updated_at: new Date().toISOString(),
          })
          .eq("student_id", student.id)
          .eq("school_id", actor.schoolId);
      }
      await admin.auth.admin.deleteUser(authUserId);
    } else {
      await admin.from("student_app_accounts")
        .update({
          is_enabled: false,
          credential_delivery_pending: true,
          updated_at: new Date().toISOString(),
        })
        .eq("student_id", student.id)
        .eq("school_id", actor.schoolId);
    }
    await setStudentStatus(caller, student.id, "disabled");
    return failedRecord(student, label, "تعذر تفعيل ربط الحساب؛ لم تُعرض بيانات الدخول.");
  }

  const outcome = password ? (status === "reset_required" ? "reset" : "created") : "enabled";
  const audited = await auditAccountChange(admin, actor, student.id, outcome);
  if (!audited) {
    await admin.from("student_app_accounts")
      .update({ is_enabled: false, updated_at: new Date().toISOString() })
      .eq("student_id", student.id);
    await setStudentStatus(caller, student.id, "disabled");
    return failedRecord(student, label, "تعذر تسجيل التدقيق؛ عُطّل الحساب ولم تُعرض بيانات الدخول.");
  }

  const record = {
    ...recordFor(student, target, true),
    status: nextStatus,
    outcome,
    credential_issued_at: password ? new Date().toISOString() : null,
  };
  const credential = password
    ? {
        student_id: student.id,
        account_type: "حساب طالب مشترك مع ولي الأمر",
        student_name: student.full_name || "اسم غير متوفر",
        student_number: student.student_number || "غير متوفر",
        guardian_names: (target.guardianNames || []).join("، ") || "ولي الأمر المرتبط",
        password,
        operation: outcome === "reset" ? "إعادة تعيين" : "إنشاء حساب",
        status: "نجاح",
        created_at: record.credential_issued_at,
      }
    : null;
  return { record, credential };
}

async function setStudentStatus(caller, studentId: string, status: string) {
  const { data, error } = await caller.rpc("update_student_app_login_status", {
    p_student_id: studentId,
    p_status: status,
    p_reason: "إدارة الحساب المشترك للطالب وولي الأمر",
  });
  if (error || data?.student_id !== studentId || data?.status !== status) {
    return { ok: false, message: "لم يؤكد الخادم تحديث حالة الطالب." };
  }
  return { ok: true };
}

function recordFor(student, target, success) {
  return {
    student_id: student.id,
    student_name: student.full_name || "اسم غير متوفر",
    student_number: student.student_number || "غير متوفر",
    guardian_names: (target.guardianNames || []).join("، "),
    success,
  };
}

function failedRecord(student, label: string, message: string) {
  return {
    record: {
      student_id: student.id,
      student_name: student.full_name || "اسم غير متوفر",
      student_number: student.student_number || "غير متوفر",
      success: false,
      outcome: "failed",
    },
    failure: { label, error: message },
  };
}

function generateTemporaryPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  let password = "Aa7!";
  for (const byte of bytes) password += PASSWORD_ALPHABET[byte % PASSWORD_ALPHABET.length];
  return password;
}

function syntheticLoginEmail(studentId: string) {
  return `student-${studentId.toLowerCase()}@accounts.school.invalid`;
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function hasProfileUsernameCollision(admin, studentNumber: string) {
  const { data, error } = await admin.rpc("student_login_identifier_conflicts", {
    p_student_number: studentNumber,
  });
  if (error) return true;
  return data === true;
}

async function auditAccountChange(admin, actor, studentId: string, operation: string) {
  const action = operation === "disabled"
    ? "student_app_account.disabled"
    : operation === "reset"
      ? "student_app_account.password_reset"
      : operation === "created"
        ? "student_app_account.created"
        : "student_app_account.enabled";
  const { error } = await admin.from("audit_logs").insert({
    user_id: actor.id,
    actor_id: actor.id,
    actor_label: actor.name,
    action,
    entity_type: "student_app_accounts",
    entity_id: studentId,
    school_id: actor.schoolId,
    description: operation === "disabled"
      ? "تم تعطيل حساب التطبيق المشترك للطالب وولي أمره."
      : operation === "reset"
        ? "أُعيد تعيين كلمة مرور حساب التطبيق المشترك."
        : operation === "created"
          ? "أُنشئ حساب التطبيق المشترك للطالب وولي أمره."
          : "تم تفعيل حساب التطبيق المشترك للطالب وولي أمره.",
    metadata: { module: "app-access", operation },
  });
  if (error) {
    console.error("student app account audit failed");
    return false;
  }
  return true;
}
