import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, DebtSimulationParams } from '../types/db';

// Same type as MoneyHubClient in ./supabase, imported directly so tests need no Vite env.
type MoneyHubClient = SupabaseClient<Database>;

/**
 * The only read RPC entry point; no scenario persistence.
 * POST, not GET: supabase-js turns GET RPC args into query strings with `${value}`, so the
 * jsonb object would arrive as "[object Object]". The function is STABLE and never writes.
 */
export function simulateDebtPlan(client: MoneyHubClient, params: DebtSimulationParams, signal: AbortSignal) {
  return client.rpc('simulate_debt_plan', { p_params: params }).abortSignal(signal);
}
