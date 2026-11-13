/**
 * Static guard for the browser's write surface (SPEC hard rule 1, narrowed).
 *
 * The web app never writes tables. Its only write path is a fixed list of owner-checked
 * database functions (RPCs), and they may be called from exactly one file: src/lib/writes.ts.
 * Reconciliation functions are deliberately absent: only Claude can reconcile.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const SRC = fileURLToPath(new URL('../src', import.meta.url));
const WRITES_FILE = ['lib', 'writes.ts'].join(sep);
const READS_FILE = ['lib', 'reads.ts'].join(sep);
const TABLE_WRITE = /\.\s*(insert|update|upsert|delete)\s*\(/g;
const RPC_CALL = /\.\s*rpc\s*\(/g;
const RPC_NAME = /\.\s*rpc\s*\(\s*['"]([a-z_]+)['"]/g;
const SCANNED_EXT = /\.(ts|tsx|js|jsx|mjs|cjs)$/;

const ALLOWED_RPCS = [
  'add_manual_transaction',
  'update_manual_transaction',
  'delete_manual_transaction',
  'set_transaction_cleared',
  'move_envelope_money',
  'create_envelope',
  'update_envelope',
  'create_set_aside',
  'update_set_aside',
];

// Read-only RPCs (STABLE, never write tables). Called only from src/lib/reads.ts.
const ALLOWED_READ_RPCS = ['simulate_debt_plan'];

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : SCANNED_EXT.test(name) ? [full] : [];
  });
}

function hits(source: string, pattern: RegExp): string[] {
  const out: string[] = [];
  source.split('\n').forEach((line, i) => {
    for (const m of line.matchAll(pattern)) out.push(`${i + 1}: ${m[0]} -> ${line.trim()}`);
  });
  return out;
}

describe('write-surface guard', () => {
  it('detects forbidden calls (self-check)', () => {
    for (const s of [
      "supabase.from('t').insert({})",
      "supabase.from('t').update({ a: 1 })",
      "supabase.from('t').upsert([])",
      "supabase.from('t').delete()",
      "supabase\n  .from('t')\n  . delete ()",
    ]) {
      expect(hits(s, TABLE_WRITE).length, s).toBeGreaterThan(0);
    }
    expect(hits("supabase.rpc('fn')", RPC_CALL).length).toBeGreaterThan(0);
    expect(hits("supabase.from('v_dashboard').select('*').eq('a', 1)", TABLE_WRITE)).toEqual([]);
  });

  it('scans a non-empty src/ tree that includes writes.ts', () => {
    const files = walk(SRC).map((f) => relative(SRC, f));
    expect(files.length).toBeGreaterThan(5);
    expect(files).toContain(WRITES_FILE);
  });

  it('never writes tables directly anywhere in src/', () => {
    const violations = walk(SRC).flatMap((file) =>
      hits(readFileSync(file, 'utf8'), TABLE_WRITE).map((v) => `${relative(SRC, file)}:${v}`),
    );
    expect(violations, `Direct table writes found:\n${violations.join('\n')}`).toEqual([]);
  });

  it('calls rpc only from src/lib/writes.ts and src/lib/reads.ts', () => {
    const violations = walk(SRC)
      .filter((file) => ![WRITES_FILE, READS_FILE].includes(relative(SRC, file)))
      .flatMap((file) => hits(readFileSync(file, 'utf8'), RPC_CALL).map((v) => `${relative(SRC, file)}:${v}`));
    expect(violations, `rpc() outside writes.ts:\n${violations.join('\n')}`).toEqual([]);
  });

  it('writes.ts calls only whitelisted functions, by literal name', () => {
    const source = readFileSync(join(SRC, 'lib', 'writes.ts'), 'utf8');
    const total = hits(source, RPC_CALL).length;
    const named = [...source.matchAll(RPC_NAME)].map((m) => m[1]);
    expect(named.length, 'every rpc call must use a literal function name').toBe(total);
    for (const name of named) expect(ALLOWED_RPCS, `${name} is not whitelisted`).toContain(name);
    expect(new Set(named)).toEqual(new Set(ALLOWED_RPCS));
  });

  it('reads.ts calls only whitelisted read-only functions, by literal name', () => {
    const source = readFileSync(join(SRC, 'lib', 'reads.ts'), 'utf8');
    const total = hits(source, RPC_CALL).length;
    const named = [...source.matchAll(RPC_NAME)].map((m) => m[1]);
    expect(named.length, 'every rpc call must use a literal function name').toBe(total);
    for (const name of named) expect(ALLOWED_READ_RPCS, `${name} is not whitelisted`).toContain(name);
    expect(new Set(named)).toEqual(new Set(ALLOWED_READ_RPCS));
    const writes = readFileSync(join(SRC, 'lib', 'writes.ts'), 'utf8');
    for (const name of ALLOWED_READ_RPCS) expect(writes, `${name} must not be called from writes.ts`).not.toContain(name);
  });

  it('never exposes reconciliation to the browser', () => {
    const violations = walk(SRC).filter((file) => /reconcile_transactions|unreconcile_transactions/.test(readFileSync(file, 'utf8')));
    expect(violations.map((f) => relative(SRC, f))).toEqual([]);
  });
});
