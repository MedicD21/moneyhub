import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/db';

export type MoneyHubClient = SupabaseClient<Database>;

type ClientState = { client: MoneyHubClient; error: null } | { client: null; error: string };

function init(): ClientState {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim();
  const key = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();

  const missing = [!url && 'VITE_SUPABASE_URL', !key && 'VITE_SUPABASE_ANON_KEY'].filter(Boolean);
  if (missing.length > 0 || !url || !key) {
    return { client: null, error: `Missing environment variable${missing.length > 1 ? 's' : ''}: ${missing.join(', ')}` };
  }
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' && parsed.hostname !== 'localhost' && parsed.hostname !== '127.0.0.1') {
      return { client: null, error: 'VITE_SUPABASE_URL must be an https:// URL.' };
    }
  } catch {
    return { client: null, error: `VITE_SUPABASE_URL is not a valid URL: "${url}"` };
  }

  try {
    const client = createClient<Database>(url, key, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    });
    return { client, error: null };
  } catch (e) {
    return { client: null, error: e instanceof Error ? e.message : 'Could not create the Supabase client.' };
  }
}

const state = init();

/** The Supabase client, or null when env vars are missing/invalid (see `configError`). */
export const supabase: MoneyHubClient | null = state.client;
/** Human-readable setup problem, or null when the client is configured. */
export const configError: string | null = state.error;
