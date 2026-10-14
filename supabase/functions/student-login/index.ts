import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const developmentOrigins = [
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

function allowedOrigins() {
  const configured = (Deno.env.get("CORS_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set(configured.length ? configured : developmentOrigins);
}

function corsHeaders(request: Request) {
  const origin = request.headers.get("Origin") || "";
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-supabase-api-version, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && allowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function json(request: Request, body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      Pragma: "no-cache",
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
    return json(request, { error: "هذا النطاق غير مسموح له بالاتصال بالخدمة." }, 403);
  }
  if (request.method !== "POST") {
    return json(request, { error: "طريقة الطلب غير مدعومة." }, 405);
  }
  if (Number(request.headers.get("Content-Length") || 0) > 8192) {
    return json(request, { error: "حجم الطلب يتجاوز الحد المسموح." }, 413);
  }

  try {
    const { student_number, password } = await request.json();
    const studentNumber = String(student_number || "").trim();
    if (!studentNumber || studentNumber.length > 64 || typeof password !== "string" || !password || password.length > 1024) {
      return json(request, { error: "بيانات الدخول غير صالحة." }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      console.error("student-login is missing server configuration");
      return json(request, { error: "خدمة تسجيل الدخول غير مهيأة على الخادم." }, 500);
    }

    const publicClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: attempt, error: attemptError } = await publicClient.rpc(
      "begin_login_attempt",
      { p_username: studentNumber },
    );
    if (attemptError) {
      console.error("student-login rate limit check failed");
      return json(request, { error: "تعذر التحقق من الدخول. حاول لاحقًا." }, 503);
    }
    if (attempt?.allowed === false) {
      return json(request, { error: "بيانات الدخول غير صحيحة أو تم تجاوز عدد المحاولات." }, 429);
    }

    const { data: student, error: studentError } = await admin
      .from("students")
      .select("id,school_id,student_app_login_enabled,student_app_login_status,educational_status,is_archived")
      .eq("student_number", studentNumber)
      .maybeSingle();
    if (studentError) {
      console.error("student-login account lookup failed");
      return json(request, { error: "تعذر التحقق من الدخول. حاول لاحقًا." }, 503);
    }

    if (
      !student ||
      !student.student_app_login_enabled ||
      !["active", "reset_required"].includes(student.student_app_login_status) ||
      student.educational_status === "withdrawn" ||
      student.is_archived
    ) {
      return json(request, { error: "بيانات الدخول غير صحيحة أو الحساب غير مفعّل." }, 401);
    }

    const { data: account, error: accountError } = await admin
      .from("student_app_accounts")
      .select("login_email,is_enabled,auth_user_id")
      .eq("student_id", student.id)
      .eq("school_id", student.school_id)
      .maybeSingle();
    if (
      accountError ||
      !account?.is_enabled ||
      !account.auth_user_id ||
      !account.login_email
    ) {
      if (accountError) console.error("student-login account mapping lookup failed");
      return json(request, { error: "بيانات الدخول غير صحيحة أو الحساب غير مفعّل." }, 401);
    }

    const { data: authData, error: authError } = await publicClient.auth.signInWithPassword({
      email: account.login_email,
      password,
    });
    if (
      authError ||
      !authData.session ||
      authData.user?.id !== account.auth_user_id
    ) {
      return json(request, { error: "بيانات الدخول غير صحيحة أو الحساب غير مفعّل." }, 401);
    }

    const { access_token, refresh_token, expires_in, expires_at, token_type } = authData.session;
    return json(request, {
      access_token,
      refresh_token,
      expires_in,
      expires_at,
      token_type,
    }, 200);
  } catch {
    // Do not log request bodies, passwords, Auth responses, or provider errors.
    console.error("student-login request failed");
    return json(request, { error: "تعذر تنفيذ تسجيل الدخول. حاول مرة أخرى." }, 400);
  }
});
