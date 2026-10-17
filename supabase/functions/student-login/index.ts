// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedDevelopmentOrigins = ["http://localhost:8000"];

function allowedOrigins() {
  const configured = (Deno.env.get("CORS_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([...configured, ...allowedDevelopmentOrigins]);
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
  const origin = request.headers.get("Origin") || "";
  const headers = corsHeaders(request);

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
    if (request.method !== "POST") {
      return json({ error: "طريقة الطلب غير مدعومة." }, 405, request);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      console.error("student-login is missing server configuration");
      return json({ error: "خدمة الدخول غير مهيأة على الخادم." }, 500, request);
    }

    let payload: Record<string, unknown>;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "بيانات الطلب غير صالحة." }, 400, request);
    }

    const studentNumber = String(payload.student_number || "").trim();
    const password = String(payload.password || "");

    if (!studentNumber || !password) {
      return json({ error: "رقم الطالب وكلمة المرور مطلوبان." }, 400, request);
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const serverClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: attempt, error: attemptError } = await serverClient.rpc(
      "begin_login_attempt",
      { p_username: studentNumber },
    );
    if (attemptError || !attempt) {
      console.error("student-login rate-limit check failed");
      return json({ error: "تعذر التحقق من طلب الدخول. حاول مرة أخرى لاحقًا." }, 503, request);
    }
    if (!attempt.allowed) {
      return json({ error: "تجاوزت عدد محاولات الدخول المسموح. انتظر قليلًا ثم أعد المحاولة." }, 429, request);
    }

    const { data: loginEmail, error: identityError } = await serverClient.rpc(
      "resolve_login_email",
      { p_username: studentNumber },
    );

    if (identityError || !loginEmail) {
      return json({ error: "رقم الطالب أو كلمة المرور غير صحيحة، أو الحساب غير مفعّل." }, 401, request);
    }

    const { data: authData, error: authError } = await authClient.auth.signInWithPassword({
      email: String(loginEmail),
      password,
    });

    if (authError || !authData?.session || !authData?.user) {
      return json({ error: "رقم الطالب أو كلمة المرور غير صحيحة، أو الحساب غير مفعّل." }, 401, request);
    }

    return json(
      {
        access_token: authData.session.access_token,
        refresh_token: authData.session.refresh_token,
        user: authData.user,
      },
      200,
      request,
    );
  } catch {
    console.error("student-login failed");
    return json({ error: "تعذر تنفيذ عملية الدخول. حاول مرة أخرى." }, 500, request);
  }
});
