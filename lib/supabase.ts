import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Only the public URL and the anon (publishable) key. Never the service key:
// the database itself decides what each role may read and change.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export const isConfigured = Boolean(url && anonKey);

let client: SupabaseClient | null = null;

/** The shared browser client, created on first use. */
export function supabase(): SupabaseClient {
  if (!url || !anonKey) {
    throw new Error(
      "Supabase is not configured: set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local, then restart the app.",
    );
  }
  client ??= createClient(url, anonKey, {
    // No login in this prototype, so no session to keep.
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  return client;
}
