// Student photo URLs are signed server-side. The browser never receives the
// service-role key and cannot choose another student's ID or Storage path.
// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const developmentOrigins = ["http://localhost:8000"];
const signedUrlLifetimeSeconds = 600;

function allowedOrigins() {
  const configured = (Deno.env.get("CORS_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([...configured, ...developmentOrigins]);
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

function storagePath(value: unknown, supabaseUrl: string) {
  if (typeof value !== "string") return null;
  const raw = value.trim();
  if (!raw) return null;

  if (/^https:\/\//i.test(raw)) {
    let url: URL;
    try {
      url = new URL(raw);
    } catch {
      return null;
    }
    const projectOrigin = new URL(supabaseUrl).origin;
    if (url.origin !== projectOrigin) return null;
    const match = url.pathname.match(
      /\/storage\/v1\/object\/(?:sign|public|authenticated)\/photos\/(.+)$/,
    );
    if (!match) return null;
    return safeObjectKey(match[1]);
  }

  let key = raw.replace(/\\/g, "/").replace(/^\/+/, "");
  const bucketPrefix = "photos/";
  if (key.startsWith(bucketPrefix)) key = key.slice(bucketPrefix.length);
  const storagePrefix = key.match(
    /^storage\/v1\/object\/(?:sign|public|authenticated)\/photos\/(.+)$/,
  );
  if (storagePrefix) key = storagePrefix[1];
  return safeObjectKey(key);
}

function safeObjectKey(value: string) {
  let key: string;
  try {
    key = decodeURIComponent(value).replace(/^\/+/, "");
  } catch {
    return null;
  }
  if (
    !key ||
    key.split("/").some((part) => !part || part === "." || part === "..") ||
    key.includes("\\")
  ) {
    return null;
  }
  return key;
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
    return json({ image_url: null }, 403, request);
  }
  if (request.method !== "POST") {
    return json({ image_url: null }, 405, request);
  }

  const authorization = request.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ image_url: null }, 401, request);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("student-avatar is missing server configuration");
    return json({ image_url: null }, 503, request);
  }

  try {
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = authorization.slice("Bearer ".length);
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    if (authError || !authData?.user) {
      return json({ image_url: null }, 401, request);
    }

    // This RPC resolves the current Auth identity to its one linked student.
    // No student ID or Storage key is accepted from the request body.
    const { data: identity, error: identityError } = await caller.rpc(
      "student_portal_identity",
    );
    const student = identity?.student;
    if (identityError || !student) {
      return json({ image_url: null }, 200, request);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const candidates = [
      student.avatar_storage_path,
      student.photo_storage_path,
      student.avatar_path,
      student.photo_path,
    ];

    for (const candidate of candidates) {
      const resolved = storagePath(candidate, supabaseUrl);
      if (!resolved) continue;

      const { data, error } = await admin.storage
        .from("photos")
        .createSignedUrl(resolved, signedUrlLifetimeSeconds);
      if (error || !data?.signedUrl) {
        console.error("student-avatar could not sign the current student's image");
        continue;
      }
      return json({ image_url: data.signedUrl }, 200, request);
    }

    return json({ image_url: null }, 200, request);
  } catch {
    console.error("student-avatar request failed");
    return json({ image_url: null }, 500, request);
  }
});
