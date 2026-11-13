import { createClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import type { Database } from '../types/db';
import { simulateDebtPlan } from './reads';

describe('simulateDebtPlan', () => {
  it('sends the jsonb params as a JSON body, never as a stringified query parameter', async () => {
    const calls: { url: string; method: string; body: unknown }[] = [];
    const fetchSpy: typeof fetch = (input, init) => {
      const url = input instanceof Request ? input.url : input instanceof URL ? input.href : input;
      calls.push({ url, method: init?.method ?? 'GET', body: init?.body });
      return Promise.resolve(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));
    };
    const client = createClient<Database>('https://example.supabase.co', 'anon', {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: fetchSpy },
    });
    const params = { extra_monthly: 100, lump_sums: [{ date: '2027-02-15', amount: 500, target_debt_id: null }] };

    await simulateDebtPlan(client, params, new AbortController().signal);

    expect(calls).toHaveLength(1);
    const call = calls[0]!;
    expect(call.method).toBe('POST');
    expect(call.url).toMatch(/\/rest\/v1\/rpc\/simulate_debt_plan$/);
    expect(call.url).not.toContain('object');
    expect(JSON.parse(String(call.body))).toEqual({ p_params: params });
  });
});
