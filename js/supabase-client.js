import { supabaseConfig } from "./supabase-config.js";

let clientPromise;

function isServiceRoleKey(key) {
  const payload = key.split(".")[1];
  if (!payload) return false;
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(base64)).role === "service_role";
  } catch {
    return false;
  }
}

export function hasSupabaseConfig() {
  return Boolean(
    /^https:\/\//.test(supabaseConfig.url) &&
    supabaseConfig.anonKey &&
    !supabaseConfig.anonKey.includes("your-public") &&
    !supabaseConfig.anonKey.startsWith("sb_secret_") &&
    !isServiceRoleKey(supabaseConfig.anonKey),
  );
}

export async function getSupabaseClient() {
  if (!hasSupabaseConfig()) return null;
  clientPromise ??= import("https://esm.sh/@supabase/supabase-js@2")
    .then(({ createClient }) =>
      createClient(supabaseConfig.url, supabaseConfig.anonKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
        },
      }),
    )
    .catch((error) => {
      clientPromise = undefined;
      throw error;
    });
  return clientPromise;
}
