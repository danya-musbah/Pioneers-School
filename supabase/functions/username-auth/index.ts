import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedDevelopmentOrigins = [
  "http://localhost:8000",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://localhost:3030",
  "http://127.0.0.1:3030",
  "http://localhost:3045",
  "http://127.0.0.1:3045",
  "http://localhost:3090",
  "http://127.0.0.1:3090",
  "http://localhost:8080",
  "http://127.0.0.1:8080",
];
const allowedProductionOrigins = [
  "https://school-management-4e9.pages.dev",
  "https://pioneers-school.pages.dev",
];

function allowedOrigins() {
  const configured = (Deno.env.get("CORS_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([
    ...allowedDevelopmentOrigins,
    ...allowedProductionOrigins,
    ...configured,
  ]);
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
  if (request.method !== "POST") {
    return json({ error: "طريقة الطلب غير مدعومة." }, 405, request);
  }

  const requestId = crypto.randomUUID();
  let stage = "request";
  try {
    return await handleRequest(request, (nextStage) => {
      stage = nextStage;
    });
  } catch (error) {
    console.error(
      JSON.stringify({
        event: "username-auth internal error",
        requestId,
        stage,
        ...safeErrorDetails(error),
      }),
    );
    return json(
      {
        error: "تعذر تنفيذ تسجيل الدخول. يرجى المحاولة مرة أخرى.",
        request_id: requestId,
      },
      500,
      request,
    );
  }
});

function safeErrorDetails(error: unknown) {
  if (!error || typeof error !== "object") {
    return { errorType: "UnknownError" };
  }
  const candidate = error as {
    name?: unknown;
    code?: unknown;
    status?: unknown;
  };
  const errorType =
    typeof candidate.name === "string" &&
    /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(candidate.name)
      ? candidate.name
      : "UnknownError";
  const code =
    typeof candidate.code === "string" &&
    /^[A-Z0-9_-]{1,32}$/.test(candidate.code)
      ? candidate.code
      : undefined;
  const status =
    typeof candidate.status === "number" &&
    Number.isInteger(candidate.status) &&
    candidate.status >= 100 &&
    candidate.status <= 599
      ? candidate.status
      : undefined;
  return {
    errorType,
    ...(code ? { errorCode: code } : {}),
    ...(status ? { errorStatus: status } : {}),
  };
}

async function handleRequest(
  request: Request,
  setStage: (stage: string) => void,
) {
  setStage("configuration");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const configuration: [string, string | undefined][] = [
    ["SUPABASE_URL", supabaseUrl],
    ["SUPABASE_ANON_KEY", anonKey],
    ["SUPABASE_SERVICE_ROLE_KEY", serviceRoleKey],
  ];
  const missingConfiguration = configuration
    .filter(([, value]) => !value)
    .map(([name]) => name);
  if (missingConfiguration.length) {
    console.error(
      JSON.stringify({
        event: "username-auth missing configuration",
        missing: missingConfiguration,
      }),
    );
    return json({ error: "خدمة تسجيل الدخول غير مهيأة على الخادم." }, 500, request);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch (_) {
    return json({ error: "بيانات الطلب غير صالحة." }, 400, request);
  }
  if (
    !payload ||
    typeof payload !== "object" ||
    Array.isArray(payload)
  ) {
    return json({ error: "بيانات الطلب غير صالحة." }, 400, request);
  }
  const requestPayload = payload as Record<string, unknown>;
  const action = String(requestPayload.action || "");
  const username =
    typeof requestPayload.username === "string"
      ? requestPayload.username.trim()
      : "";
  if (!username || username.length > 120) {
    return json({ error: "يرجى إدخال اسم مستخدم صالح." }, 400, request);
  }
  if (action !== "sign-in" && action !== "password-reset") {
    return json({ error: "إجراء المصادقة غير معروف." }, 400, request);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const auth = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  setStage("request-validation");
  if (action === "password-reset") {
    setStage("password-reset-username-resolution");
    const email = await resolveLoginEmail(admin, username);
    const redirectTo = safeRedirectUrl(requestPayload.redirect_to, request);
    if (!redirectTo) {
      return json({ error: "عنوان العودة بعد الاستعادة غير مسموح." }, 400, request);
    }
    // Keep the response identical for known and unknown usernames.
    if (email) {
      setStage("password-reset-email");
      const { error } = await auth.auth.resetPasswordForEmail(email, {
        redirectTo,
      });
      if (error) throw error;
    }
    return json({ sent: true }, 200, request);
  }

  const password =
    typeof requestPayload.password === "string"
      ? requestPayload.password
      : "";
  if (!password) {
    return json({ error: "يرجى إدخال كلمة المرور." }, 400, request);
  }
  if (password.length > 1024) {
    return json({ error: "بيانات الطلب غير صالحة." }, 400, request);
  }

  setStage("begin-login-attempt");
  const { data: attempt, error: attemptError } = await admin.rpc(
    "begin_login_attempt",
    { p_username: username },
  );
  if (attemptError) throw attemptError;
  if (attempt?.allowed === false) {
    return json(
      { error: "تم تقييد محاولات الدخول مؤقتًا بسبب تكرار المحاولات. حاول بعد 15 دقيقة." },
      429,
      request,
    );
  }

  setStage("username-resolution");
  const email = await resolveLoginEmail(admin, username);
  if (!email) {
    setStage("record-login-failure");
    await recordLoginFailure(admin, username);
    return json({ error: "اسم المستخدم أو كلمة المرور غير صحيحة." }, 401, request);
  }
  setStage("password-verification");
  const { data, error } = await auth.auth.signInWithPassword({ email, password });
  if (error || !data.session) {
    setStage("record-login-failure");
    await recordLoginFailure(admin, username);
    return json({ error: "اسم المستخدم أو كلمة المرور غير صحيحة." }, 401, request);
  }

  return json(
    {
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    },
    200,
    request,
  );
}

async function resolveLoginEmail(admin: ReturnType<typeof createClient>, username: string) {
  const [studentResult, staffResult] = await Promise.all([
    admin.rpc("resolve_login_email", { p_username: username }),
    admin.rpc("resolve_staff_login_email", { p_username: username }),
  ]);
  if (studentResult.error) throw studentResult.error;
  if (staffResult.error) throw staffResult.error;

  // Historical case-insensitive collisions may predate the database guards.
  // Fail closed rather than silently selecting the student or staff identity.
  if (studentResult.data && staffResult.data) return null;
  return studentResult.data || staffResult.data || null;
}

async function recordLoginFailure(
  admin: ReturnType<typeof createClient>,
  username: string,
) {
  const { error } = await admin.rpc("record_login_failure", {
    p_username: username,
  });
  if (error) throw error;
}

function safeRedirectUrl(value: unknown, request: Request) {
  if (typeof value !== "string") return null;
  try {
    const redirect = new URL(value);
    const origin = request.headers.get("Origin") || "";
    if (
      redirect.protocol !== "https:" &&
      !(redirect.protocol === "http:" && allowedOrigins().has(redirect.origin))
    ) {
      return null;
    }
    if (!allowedOrigins().has(redirect.origin) || (origin && redirect.origin !== origin)) {
      return null;
    }
    return redirect.toString();
  } catch (_) {
    return null;
  }
}
