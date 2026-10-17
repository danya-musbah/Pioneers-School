// The Supabase Edge runtime provides Deno and resolves the esm.sh import.
// The repository's browser TypeScript checker does not load Deno typings.
// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const defaultAllowedOrigins = [
  "http://localhost",
  "https://localhost",
  "http://localhost:8000",
  "https://localhost:8000",
  "http://127.0.0.1:8000",
  "https://127.0.0.1:8000",
  "http://0.0.0.0:8000",
  "https://0.0.0.0:8000",
  "http://localhost:8080",
  "http://localhost:8756",
  "http://127.0.0.1:8756",
  "http://127.0.0.1:8080",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://localhost:3030",
  "http://127.0.0.1:3030",
  "http://localhost:4173",
  "http://localhost:5173",
];

function getAllowedOrigins() {
  const configured = (Deno.env.get("CORS_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
  // Keep explicit local development origins while adding exact production
  // origins. The bearer token and server-side permission checks remain required.
  return new Set([...defaultAllowedOrigins, ...configured]);
}

function buildCorsHeaders(request: Request) {
  const origin = request.headers.get("Origin") || "";
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-requested-with, x-supabase-api-version, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && getAllowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function json(body: unknown, status: number, request: Request) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...buildCorsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

Deno.serve(async (request: Request) => {
  const corsHeaders = buildCorsHeaders(request);
  const origin = request.headers.get("Origin") || "";

  // Preflight must complete before reading credentials, environment or body.
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: origin && !corsHeaders["Access-Control-Allow-Origin"] ? 403 : 204,
      headers: corsHeaders,
    });
  }
  if (origin && !corsHeaders["Access-Control-Allow-Origin"]) {
    return json({ error: "هذا النطاق غير مسموح له بالاتصال بالخدمة." }, 403, request);
  }

  try {
    return await handleRequest(request);
  } catch (error) {
    // Keep implementation details server-side; always return a CORS-aware,
    // structured response instead of the runtime's opaque preflight failure.
    console.error("admin-user-management failed", error);
    return json(
      { error: "تعذر تنفيذ عملية إدارة المستخدمين. يرجى المحاولة مرة أخرى." },
      500,
      request,
    );
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
    console.error("admin-user-management is missing required server configuration");
    return json({ error: "خدمة إدارة المستخدمين غير مهيأة على الخادم." }, 500, request);
  }

  const token = authorization.slice("Bearer ".length);
  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

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

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch (_) {
    return json({ error: "بيانات الطلب غير صالحة." }, 400, request);
  }

  const actor = {
    id: authData.user.id,
    name: String(session.profile.full_name || session.profile.username || "مدير النظام"),
    role: String(session.profile.role || ""),
    permissions: Array.isArray(session.permissions) ? session.permissions : [],
    schoolId: String(
      session.profile.school_id || session.school?.school_id || "",
    ),
  };
  if (!actor.schoolId) {
    return json({ error: "تعذر تحديد مدرسة الحساب الحالي." }, 403, request);
  }
  const action = String(payload.action || "");
  const isAdmin = actor.role === "admin";
  const canManage = isAdmin || actor.permissions.includes("users.manage");
  const canView = canManage || actor.permissions.includes("users.view");

  if (action === "list-users" || action === "get-user") {
    if (!canView) {
      return json({ error: "ليس لديك صلاحية عرض المستخدمين." }, 403, request);
    }
    if (action === "list-users") return listUsers(request, admin, actor.schoolId);
    return getUserDetails(request, admin, payload, actor.schoolId);
  }

  if (!canManage) {
    return json({ error: "ليس لديك صلاحية لتنفيذ هذه العملية." }, 403, request);
  }

  if (action === "list-employees") return listEmployees(request, admin, actor.schoolId);
  if (action === "create") return createUser(request, admin, payload, actor);
  if (action === "update-access") return updateAccess(request, admin, payload, actor);
  if (action === "delete") return deleteUser(request, admin, payload, actor);
  if (action === "reset-password") {
    return resetPassword(request, admin, payload, actor);
  }
  if (action === "force-password-change") {
    return forcePasswordChange(request, admin, payload, actor);
  }

  return json({ error: "إجراء إدارة المستخدم غير معروف." }, 400, request);
}

async function listUsers(
  request: Request,
  admin: ReturnType<typeof createClient>,
  schoolId: string,
) {
  const { data, error } = await admin
    .from("profiles")
    .select(
      "id,school_id,full_name,username,email,phone,role,status,must_change_password,version,updated_at,created_at,last_login_at,employee_id",
    )
    .eq("school_id", schoolId)
    .order("full_name");
  if (error) {
    console.error("Failed to list user profiles", error);
    return json({ error: "تعذر تحميل قائمة المستخدمين." }, 500, request);
  }
  const users = (data || []).map((profile) => ({
    id: profile.id,
    name: profile.full_name,
    username: profile.username,
    email: profile.email,
    phone: profile.phone,
    role: profile.role,
    status: profile.status,
    must_change_password: profile.must_change_password,
    version: profile.version,
    created_at: profile.created_at,
    updated_at: profile.updated_at,
    last_login_at: profile.last_login_at,
    employee_id: profile.employee_id,
  }));
  return json({ users }, 200, request);
}

async function getUserDetails(
  request: Request,
  admin: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  schoolId: string,
) {
  const userId = String(payload.user_id || "").trim();
  if (!userId) return json({ error: "حدد المستخدم المطلوب." }, 400, request);

  const { data: profile, error } = await admin
    .from("profiles")
    .select(
      "id,school_id,full_name,username,email,phone,role,status,must_change_password,version,updated_at,created_at,last_login_at,employee_id",
    )
    .eq("id", userId)
    .eq("school_id", schoolId)
    .maybeSingle();
  if (error) {
    console.error("Failed to load user details", error);
    return json({ error: "تعذر تحميل تفاصيل المستخدم." }, 500, request);
  }
  if (!profile) return json({ error: "المستخدم المطلوب غير موجود." }, 404, request);

  const { data: grants, error: grantsError } = await admin
    .from("user_permissions")
    .select("permission")
    .eq("user_id", userId);
  if (grantsError) {
    console.error("Failed to load user permissions", grantsError);
    return json({ error: "تعذر تحميل صلاحيات المستخدم." }, 500, request);
  }
  let employee = null;
  if (profile.employee_id) {
    const { data, error: employeeError } = await admin
      .from("employees")
      .select("id,full_name,employee_number")
      .eq("id", profile.employee_id)
      .eq("school_id", schoolId)
      .maybeSingle();
    if (employeeError) {
      console.error("Failed to load linked employee details", employeeError);
      return json({ error: "تعذر تحميل بيانات الموظف المرتبط." }, 500, request);
    }
    employee = data;
  }
  return json(
    {
      user: {
        ...profile,
        name: profile.full_name,
        employee,
        permissions: (grants || []).map((grant) => grant.permission),
      },
    },
    200,
    request,
  );
}

async function listEmployees(
  request: Request,
  admin: ReturnType<typeof createClient>,
  schoolId: string,
) {
  const { data, error } = await admin
    .from("employees")
    .select("id,full_name,employee_number,is_teacher,employment_status")
    .eq("school_id", schoolId)
    .eq("is_archived", false)
    .order("full_name");
  if (error) {
    console.error("Failed to list employees", error);
    return json({ error: "تعذر تحميل قائمة الموظفين." }, 500, request);
  }
  return json({ employees: data || [] }, 200, request);
}

async function createUser(
  request: Request,
  admin: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  actor: { id: string; name: string; role: string; schoolId: string },
) {
  const username = String(payload.username || "").trim();
  const fullName = String(payload.full_name || "").trim();
  const email = String(payload.email || "").trim().toLowerCase();
  const phone = String(payload.phone || "").trim() || null;
  const password = String(payload.temporary_password || "");
  const role = String(payload.role || "staff");
  const status = String(payload.status || "active");
  const employeeId = String(payload.employee_id || "").trim() || null;

  if (!username || !fullName || !email || !password) {
    return json(
      { error: "اسم المستخدم والاسم الكامل والبريد وكلمة المرور المؤقتة مطلوبة." },
      400,
      request,
    );
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "صيغة البريد الإلكتروني غير صحيحة." }, 400, request);
  }
  if (!["admin", "staff", "employee"].includes(role)) {
    return json({ error: "الدور المحدد غير صالح." }, 400, request);
  }
  if (!["active", "inactive", "suspended", "terminated"].includes(status)) {
    return json({ error: "حالة الحساب المحددة غير صالحة." }, 400, request);
  }
  if (role === "admin" && actor.role !== "admin") {
    return json({ error: "إنشاء حساب مدير متاح لمدير النظام فقط." }, 403, request);
  }
  if (password.length < 8) {
    return json(
      { error: "كلمة المرور المؤقتة يجب أن تتكون من 8 أحرف على الأقل." },
      400,
      request,
    );
  }

  if (employeeId) {
    const { data: employee, error: employeeError } = await admin
      .from("employees")
      .select("id")
      .eq("id", employeeId)
      .eq("school_id", actor.schoolId)
      .eq("is_archived", false)
      .maybeSingle();
    if (employeeError || !employee) {
      return json({ error: "الموظف المرتبط غير موجود أو مؤرشف." }, 400, request);
    }
  }

  const { data: duplicateUsername, error: usernameError } = await admin
    .from("profiles")
    .select("id")
    .eq("username", username)
    .maybeSingle();
  if (usernameError) {
    console.error("Failed to check username uniqueness", usernameError);
    return json({ error: "تعذر التحقق من اسم المستخدم." }, 500, request);
  }
  if (duplicateUsername) {
    return json({ error: "اسم المستخدم مستخدم بالفعل." }, 409, request);
  }

  // Auth enforces email uniqueness server-side. The normalized email plus the
  // profiles lower(email) index also protects against case-only duplicates.
  const { data: authResult, error: authError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, username },
  });
  if (authError || !authResult?.user) {
    if (isDuplicateEmailError(authError)) {
      return json(
        {
          code: "EMAIL_ALREADY_IN_USE",
          error: "البريد الإلكتروني مستخدم بالفعل. يرجى استخدام بريد إلكتروني آخر.",
        },
        409,
        request,
      );
    }
    console.error("Supabase Auth rejected user creation", authError);
    return json(
      { error: "تعذر إنشاء حساب الدخول. تحقق من البريد وكلمة المرور المطلوبة." },
      400,
      request,
    );
  }

  const userId = authResult.user.id;
  const { data: profileResult, error: profileError } = await admin.rpc(
    "create_managed_user_profile",
    {
      p_actor_id: actor.id,
      p_user_id: userId,
      p_username: username,
      p_full_name: fullName,
      p_email: email,
      p_phone: phone,
      p_role: role,
      p_status: status,
      p_employee_id: employeeId,
    },
  );
  if (profileError) {
    const { error: rollbackError } = await admin.auth.admin.deleteUser(userId);
    if (rollbackError) console.error("Failed to roll back Auth user after profile insert failure", rollbackError);
    if (profileError.code === "23505" || isDuplicateEmailError(profileError)) {
      return json({ error: "البريد الإلكتروني أو اسم المستخدم مستخدم بالفعل." }, 409, request);
    }
    console.error("Failed to create audited user profile", profileError);
    return json({ error: "تعذر حفظ بيانات المستخدم. لم يتم إكمال إنشاء الحساب." }, 400, request);
  }

  return json({ user_id: profileResult?.id || userId }, 201, request);
}

async function updateAccess(
  request: Request,
  admin: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  actor: { id: string },
) {
  const userId = String(payload.user_id || "").trim();
  const role = String(payload.role || "");
  const status = String(payload.status || "");
  const permissions = Array.isArray(payload.permissions)
    ? payload.permissions.filter((permission): permission is string => typeof permission === "string")
    : [];
  if (!userId) return json({ error: "حدد المستخدم المطلوب." }, 400, request);

  const { data, error } = await admin.rpc("admin_set_user_access", {
    p_actor_id: actor.id,
    p_user_id: userId,
    p_role: role,
    p_status: status,
    p_expected_version:
      Number.isInteger(payload.version) && Number(payload.version) > 0
        ? Number(payload.version)
        : null,
    p_permissions: permissions,
  });
  if (error) {
    console.error("Failed to update user access", error);
    const message = String(error.message || "");
    if (/غير موجود/.test(message)) return json({ error: message }, 404, request);
    if (/صلاحية|مدير النظام|الحساب الحالي/.test(message)) {
      return json({ error: message }, 403, request);
    }
    return json({ error: message || "تعذر تحديث دور المستخدم وصلاحياته." }, 400, request);
  }
  return json({ user: data }, 200, request);
}

async function deleteUser(
  request: Request,
  admin: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  actor: { id: string; name: string; role: string; schoolId: string },
) {
  const userId = String(payload.user_id || "").trim();
  if (!userId) return json({ error: "حدد المستخدم المطلوب." }, 400, request);
  if (userId === actor.id) {
    return json({ error: "لا يمكن حذف الحساب الحالي." }, 403, request);
  }

  const { data: target, error: targetError } = await admin
    .from("profiles")
    .select("id,school_id,employee_id,full_name,username,email,role,status")
    .eq("id", userId)
    .eq("school_id", actor.schoolId)
    .maybeSingle();
  if (targetError) {
    console.error("Failed to load user before deletion", targetError);
    return json({ error: "تعذر التحقق من المستخدم المطلوب." }, 500, request);
  }
  if (!target) return json({ error: "المستخدم المطلوب غير موجود." }, 404, request);
  if (target.role === "admin" && actor.role !== "admin") {
    return json({ error: "حذف حساب مدير متاح لمدير النظام فقط." }, 403, request);
  }
  if (target.role === "admin" && target.status === "active") {
    const { count, error } = await admin
      .from("profiles")
      .select("id", { count: "exact", head: true })
      .eq("school_id", actor.schoolId)
      .eq("role", "admin")
      .eq("status", "active");
    if (error) {
      console.error("Failed to verify remaining administrators", error);
      return json({ error: "تعذر التحقق من وجود مدير بديل." }, 500, request);
    }
    if ((count || 0) <= 1) {
      return json({ error: "لا يمكن حذف آخر حساب مدير نشط في النظام." }, 409, request);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error("Supabase Auth rejected user deletion", deleteError);
    if (deleteError.code === "23503" || /foreign key/i.test(deleteError.message || "")) {
      return json(
        { error: "تعذر حذف الحساب بسبب سجلات مرتبطة. طبّق ترحيل حماية سجلات المستخدمين ثم أعد المحاولة." },
        409,
        request,
      );
    }
    return json({ error: "تعذر حذف حساب المستخدم من خدمة الدخول." }, 400, request);
  }

  const { error: auditError } = await admin.from("audit_logs").insert({
    user_id: null,
    actor_id: actor.id,
    actor_label: actor.name,
    action: "user.deleted",
    entity_type: "user",
    entity_id: userId,
    old_value: target,
    description: `حذف المستخدم ${target.full_name || target.username || userId}`,
    metadata: { module: "users", source: "admin-user-management" },
  });
  if (auditError) console.error("User deleted but deletion audit record failed", auditError);
  return json({ deleted_user_id: userId }, 200, request);
}

async function resetPassword(
  request: Request,
  admin: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  actor: { id: string; role: string; schoolId: string },
) {
  const userId = String(payload.user_id || "").trim();
  const password = String(payload.temporary_password || "");
  if (!userId || password.length < 8) {
    return json({ error: "حدد المستخدم وكلمة مرور لا تقل عن 8 أحرف." }, 400, request);
  }
  if (userId === actor.id) {
    return json({ error: "استخدم صفحة الملف الشخصي لتغيير كلمة مرور حسابك." }, 403, request);
  }
  const target = await getManageableTarget(
    admin,
    userId,
    actor.role,
    actor.schoolId,
  );
  if (target.error) return json({ error: target.error }, target.status, request);

  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) {
    console.error("Failed to reset user password", error);
    return json({ error: "تعذر تحديث كلمة مرور المستخدم." }, 400, request);
  }
  const { error: auditError } = await admin.rpc("admin_mark_password_change_required", {
    p_actor_id: actor.id,
    p_user_id: userId,
    p_action: "user.password.reset",
  });
  if (auditError) {
    console.error("Password reset succeeded but audit/profile update failed", auditError);
    return json({ error: "تم تغيير كلمة المرور، لكن تعذر تسجيل العملية أو فرض تغييرها عند الدخول." }, 500, request);
  }
  return json({ ok: true }, 200, request);
}

async function forcePasswordChange(
  request: Request,
  admin: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  actor: { id: string; role: string; schoolId: string },
) {
  const userId = String(payload.user_id || "").trim();
  if (!userId) return json({ error: "حدد المستخدم المطلوب." }, 400, request);
  if (userId === actor.id) {
    return json({ error: "لا يمكن فرض هذا الإجراء على الحساب الحالي." }, 403, request);
  }
  const target = await getManageableTarget(
    admin,
    userId,
    actor.role,
    actor.schoolId,
  );
  if (target.error) return json({ error: target.error }, target.status, request);

  const { error } = await admin.rpc("admin_mark_password_change_required", {
    p_actor_id: actor.id,
    p_user_id: userId,
    p_action: "user.password.change.required",
  });
  if (error) {
    console.error("Failed to require password change and record audit", error);
    return json({ error: "تعذر فرض تغيير كلمة المرور." }, 400, request);
  }
  return json({ ok: true }, 200, request);
}

async function getManageableTarget(
  admin: ReturnType<typeof createClient>,
  userId: string,
  actorRole: string,
  schoolId: string,
) {
  const { data, error } = await admin
    .from("profiles")
    .select("id,role")
    .eq("id", userId)
    .eq("school_id", schoolId)
    .maybeSingle();
  if (error) {
    console.error("Failed to check target user", error);
    return { error: "تعذر التحقق من المستخدم المطلوب.", status: 500 };
  }
  if (!data) return { error: "المستخدم المطلوب غير موجود.", status: 404 };
  if (data.role === "admin" && actorRole !== "admin") {
    return { error: "إدارة حسابات المديرين متاحة لمدير النظام فقط.", status: 403 };
  }
  return { data };
}

function isDuplicateEmailError(error: unknown) {
  const value = error as { code?: string; message?: string } | null;
  const code = String(value?.code || "").toLowerCase();
  const message = String(value?.message || "").toLowerCase();
  return (
    ["email_exists", "user_already_exists"].includes(code) ||
    /already (registered|exists)|already been registered|email.{0,30}(exists|in use|registered)/i.test(message)
  );
}
