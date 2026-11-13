import type { MoneyHubClient } from './supabase';
import type { DebtSimulationParams } from '../types/db';

/** The only read RPC entry point. GET plus abort; no scenario persistence. */
export function simulateDebtPlan(client: MoneyHubClient, params: DebtSimulationParams, signal: AbortSignal) {
  return client.rpc('simulate_debt_plan', { p_params: params }, { get: true }).abortSignal(signal);
}
